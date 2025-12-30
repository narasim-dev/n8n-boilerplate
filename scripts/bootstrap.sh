#!/bin/sh
set -e

DATA_DIR="${N8N_DATA_DIR:-/home/node}"
BOOTSTRAP_MARKER="$DATA_DIR/.bootstrapped"
WORKFLOWS_DIR="${N8N_WORKFLOWS_DIR:-$DATA_DIR/workflows}"
DB_FILE="$DATA_DIR/.n8n/database.sqlite"
BOOTSTRAP_ENV="/tmp/credentials/bootstrap.env"

log() {
    echo "[bootstrap] $1"
}

if [ -f "$BOOTSTRAP_MARKER" ]; then
    log "Already bootstrapped, skipping..."
    exit 0
fi

if [ -f "$BOOTSTRAP_ENV" ]; then
    log "Loading bootstrap credentials from $BOOTSTRAP_ENV..."
    set -a
    . "$BOOTSTRAP_ENV"
    set +a
fi

mkdir -p "$(dirname "$BOOTSTRAP_MARKER")"
touch "$BOOTSTRAP_MARKER"
log "Starting n8n bootstrap..."

if [ -n "$N8N_BOOTSTRAP_OWNER_EMAIL" ] && [ -n "$N8N_BOOTSTRAP_OWNER_PASSWORD" ]; then
    log "Creating owner account..."
    
    n8n start &
    N8N_PID=$!
    
    log "Waiting for n8n to initialize database..."
    sleep 5
    
    for i in $(seq 1 30); do
        if [ -f "$DB_FILE" ]; then
            log "Database file created"
            break
        fi
        sleep 1
    done
    
    log "Waiting for n8n API to be ready..."
    for i in $(seq 1 60); do
        if curl -s http://localhost:5678/healthz > /dev/null 2>&1; then
            log "n8n API is ready"
            break
        fi
        sleep 2
    done
    
    sleep 3
    
    log "Resetting owner setup flag..."
    sqlite3 "$DB_FILE" "UPDATE settings SET value = 'false' WHERE key = 'userManagement.isInstanceOwnerSetUp';" 2>/dev/null || true

    # SQLite needs time to commit changes before n8n reads them
    # Without this delay, owner setup API returns error and all subsequent imports fail
    sleep 3
    
    log "Setting up owner via API..."
    SETUP_RESPONSE=$(curl -s -X POST http://localhost:5678/rest/owner/setup \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$N8N_BOOTSTRAP_OWNER_EMAIL\",
            \"password\": \"$N8N_BOOTSTRAP_OWNER_PASSWORD\",
            \"firstName\": \"${N8N_BOOTSTRAP_OWNER_FIRSTNAME:-Admin}\",
            \"lastName\": \"${N8N_BOOTSTRAP_OWNER_LASTNAME:-User}\"
        }" 2>&1)
    
    if echo "$SETUP_RESPONSE" | grep -q '"id"'; then
        log "Owner account created successfully"
    else
        log "Owner setup response: $SETUP_RESPONSE"
    fi
    
    # Login to get session cookie for API imports
    log "Logging in for API imports..."
    curl -s -X POST http://localhost:5678/rest/login \
        -H "Content-Type: application/json" \
        -d "{\"emailOrLdapLoginId\": \"$N8N_BOOTSTRAP_OWNER_EMAIL\", \"password\": \"$N8N_BOOTSTRAP_OWNER_PASSWORD\"}" \
        -c /tmp/n8n-cookies.txt > /dev/null
    
    CREDENTIALS_DIR="${N8N_CREDENTIALS_DIR:-/tmp/credentials}"
    if [ -d "$CREDENTIALS_DIR" ]; then
        CRED_FILES=$(find "$CREDENTIALS_DIR" -maxdepth 1 -name "*.json" -type f 2>/dev/null)
        if [ -n "$CRED_FILES" ]; then
            log "Importing credentials from $CREDENTIALS_DIR..."
            for cred_file in $CRED_FILES; do
                log "Importing credential: $cred_file"
                jq -c '.[]' "$cred_file" 2>/dev/null | while read cred_json; do
                    CRED_RESPONSE=$(curl -s -X POST http://localhost:5678/rest/credentials \
                        -H "Content-Type: application/json" \
                        -b /tmp/n8n-cookies.txt \
                        -d "$cred_json" 2>&1)
                    if echo "$CRED_RESPONSE" | grep -q '"id"'; then
                        log "Credential imported successfully"
                    else
                        log "Credential import response: $CRED_RESPONSE"
                    fi
                done
                rm -f "$cred_file"
                log "Credential file deleted: $cred_file"
            done
        fi
    fi
    
    if [ -d "$WORKFLOWS_DIR" ]; then
        log "Importing workflows from $WORKFLOWS_DIR..."
        
        find "$WORKFLOWS_DIR" -mindepth 2 -name "*.json" -type f | while read workflow_file; do
            log "Importing: $workflow_file"
            WF_RESPONSE=$(curl -s -X POST http://localhost:5678/rest/workflows \
                -H "Content-Type: application/json" \
                -b /tmp/n8n-cookies.txt \
                -d @"$workflow_file" 2>&1)
            if echo "$WF_RESPONSE" | grep -q '"id"'; then
                log "Workflow imported successfully"
            else
                log "Workflow import response: $WF_RESPONSE"
            fi
        done
        
        find "$WORKFLOWS_DIR" -maxdepth 1 -name "*.json" -type f | while read workflow_file; do
            log "Importing: $workflow_file"
            WF_RESPONSE=$(curl -s -X POST http://localhost:5678/rest/workflows \
                -H "Content-Type: application/json" \
                -b /tmp/n8n-cookies.txt \
                -d @"$workflow_file" 2>&1)
            if echo "$WF_RESPONSE" | grep -q '"id"'; then
                log "Workflow imported successfully"
            else
                log "Workflow import response: $WF_RESPONSE"
            fi
        done
        
        log "Resolving workflow dependencies..."
        ID_MAP=$(n8n export:workflow --all 2>/dev/null | jq -c '[.[] | {(.name): .id}] | add')
        
        AGENT_ID=$(echo "$ID_MAP" | jq -r '."Agent: Chat" // empty')
        if [ -n "$AGENT_ID" ]; then
            log "Resolving Agent: Chat (ID: $AGENT_ID) tool references..."
            
            AGENT_EXPORT=$(n8n export:workflow --id="$AGENT_ID" 2>/dev/null | jq '.[0]')
            
            RESOLVED=$(echo "$AGENT_EXPORT" | jq --argjson map "$ID_MAP" '
              .nodes |= map(
                if .parameters.workflowId.__rl == true and .parameters.workflowId.mode == "list" and ($map[.parameters.workflowId.value] != null) then
                  .parameters.workflowId.mode = "id" |
                  .parameters.workflowId.value = $map[.parameters.workflowId.value]
                else . end
              )
            ')
            
            echo "$RESOLVED" > /tmp/agent-resolved.json
            PATCH_RESPONSE=$(curl -s -X PATCH "http://localhost:5678/rest/workflows/$AGENT_ID" \
                -H "Content-Type: application/json" \
                -b /tmp/n8n-cookies.txt \
                -d @/tmp/agent-resolved.json 2>&1)
            rm -f /tmp/agent-resolved.json
            
            if echo "$PATCH_RESPONSE" | grep -q '"id"'; then
                log "Agent: Chat dependencies resolved successfully"
            else
                log "Agent: Chat patch response: $PATCH_RESPONSE"
            fi
        fi
    fi
    
    # Activate workflows if requested (must be done while n8n is running)
    # N8N_BOOTSTRAP_ACTIVATE_WORKFLOWS can be:
    #   - "true" or "all" - activate all workflows
    #   - comma-separated list of workflow names - activate only those
    if [ -n "$N8N_BOOTSTRAP_ACTIVATE_WORKFLOWS" ]; then
        log "Activating workflows..."
        curl -s http://localhost:5678/rest/workflows \
            -b /tmp/n8n-cookies.txt | jq -c '.data[] | {id, versionId, name, description}' | while read wf_data; do
            wf_id=$(echo "$wf_data" | jq -r '.id')
            wf_versionId=$(echo "$wf_data" | jq -r '.versionId')
            wf_name=$(echo "$wf_data" | jq -r '.name')
            wf_desc=$(echo "$wf_data" | jq -r '.description // ""')
            
            should_activate=false
            if [ "$N8N_BOOTSTRAP_ACTIVATE_WORKFLOWS" = "true" ] || [ "$N8N_BOOTSTRAP_ACTIVATE_WORKFLOWS" = "all" ]; then
                should_activate=true
            else
                if echo ",$N8N_BOOTSTRAP_ACTIVATE_WORKFLOWS," | grep -q ",$wf_name,"; then
                    should_activate=true
                fi
            fi
            
            if [ "$should_activate" = "true" ]; then
                ACTIVATE_RESPONSE=$(curl -s -X POST "http://localhost:5678/rest/workflows/$wf_id/activate" \
                    -H "Content-Type: application/json" \
                    -b /tmp/n8n-cookies.txt \
                    -d "{\"versionId\": \"$wf_versionId\", \"name\": \"$wf_name\", \"description\": \"$wf_desc\"}" 2>&1)
                if echo "$ACTIVATE_RESPONSE" | grep -q '"active":true'; then
                    log "Workflow '$wf_name' activated"
                else
                    log "Workflow '$wf_name' activation: $(echo "$ACTIVATE_RESPONSE" | jq -r '.message // "ok"')"
                fi
            else
                log "Workflow '$wf_name' skipped (not in activation list)"
            fi
        done
    fi
    
    # Cleanup
    rm -f /tmp/n8n-cookies.txt
    rm -f "$BOOTSTRAP_ENV"
    log "Bootstrap credentials file deleted"
    
    log "Stopping temporary n8n instance..."
    kill $N8N_PID 2>/dev/null || true
    wait $N8N_PID 2>/dev/null || true
    sleep 2
else
    log "No owner credentials provided, skipping user setup"
    
    if [ -d "$WORKFLOWS_DIR" ]; then
        log "Note: Workflows will be imported after manual owner setup"
    fi
fi

log "Bootstrap complete"
