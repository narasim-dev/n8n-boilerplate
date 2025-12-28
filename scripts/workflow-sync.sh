#!/bin/bash
set -e

CONTAINER_NAME="${1:-narasim-n8n-1}"
ACTION="${2:-help}"
FILE="${3:-}"

DB_CONTAINER="narasim-supabase-1"
DB_NAME="n8n"
DB_USER="postgres"

delete_workflow_by_id() {
  local ID="$1"
  echo "Deleting workflow ID: $ID from database..."
  docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM workflow_entity WHERE id = '$ID';" 2>/dev/null || true
}

case "$ACTION" in
  import)
    if [ -z "$FILE" ]; then
      echo "Usage: $0 $CONTAINER_NAME import <file.json>"
      exit 1
    fi
    
    WORKFLOW_NAME=$(docker exec -u node "$CONTAINER_NAME" sh -c "cat /workflows/$FILE | jq -r '.name'")
    echo "Workflow name: $WORKFLOW_NAME"
    
    EXISTING_IDS=$(docker exec -u node "$CONTAINER_NAME" sh -c "n8n export:workflow --all 2>/dev/null | jq -r '.[] | select(.name == \"'\"$WORKFLOW_NAME\"'\" and .isArchived != true) | .id'")
    
    if [ -n "$EXISTING_IDS" ] && [ "$EXISTING_IDS" != "null" ] && [ "$EXISTING_IDS" != "" ]; then
      for ID in $EXISTING_IDS; do
        echo "Found existing workflow with ID: $ID"
        delete_workflow_by_id "$ID"
      done
      echo "Deleted all duplicates. Importing new version..."
    else
      echo "No existing workflow found. Importing..."
    fi
    
    docker exec -u node "$CONTAINER_NAME" n8n import:workflow --input="/workflows/$FILE"
    echo "Import complete: $FILE"
    ;;
    
  delete)
    if [ -z "$FILE" ]; then
      echo "Usage: $0 $CONTAINER_NAME delete <workflow-name>"
      exit 1
    fi
    
    WORKFLOW_NAME="$FILE"
    echo "Looking for workflow: $WORKFLOW_NAME"
    
    EXISTING_IDS=$(docker exec -u node "$CONTAINER_NAME" sh -c "n8n export:workflow --all 2>/dev/null | jq -r '.[] | select(.name == \"'\"$WORKFLOW_NAME\"'\" and .isArchived != true) | .id'")
    
    if [ -z "$EXISTING_IDS" ] || [ "$EXISTING_IDS" = "null" ]; then
      echo "Workflow not found: $WORKFLOW_NAME"
      exit 1
    fi
    
    for ID in $EXISTING_IDS; do
      delete_workflow_by_id "$ID"
    done
    echo "Delete complete"
    ;;
    
  list)
    echo "Listing all workflows (excluding archived)..."
    docker exec -u node "$CONTAINER_NAME" sh -c "n8n export:workflow --all 2>/dev/null | jq -r '.[] | select(.isArchived != true) | \"\(.id)\t\(.name)\"'"
    ;;
    
  export)
    echo "Exporting all workflows..."
    docker exec -u node "$CONTAINER_NAME" n8n export:workflow --all --separate --output=/workflows/
    echo "Export complete. Check ./n8n/workflows/ directory."
    ;;
    
  *)
    echo "n8n Workflow Sync Tool"
    echo ""
    echo "Usage: $0 [container] [action] [file/name]"
    echo ""
    echo "Actions:"
    echo "  import <file.json>  - Delete existing workflow by name and import new"
    echo "  delete <name>       - Delete workflow(s) by name"
    echo "  list                - List all workflows with IDs"
    echo "  export              - Export all workflows to Git directory"
    echo ""
    echo "Examples:"
    echo "  $0 narasim-n8n-1 import api-me.json"
    echo "  $0 narasim-n8n-1 delete 'API: Get Current User (me)'"
    echo "  $0 narasim-n8n-1 list"
    ;;
esac
