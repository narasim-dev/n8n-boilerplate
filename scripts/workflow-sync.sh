#!/bin/sh
set -e

ACTION="${1:-help}"
FILE="${2:-}"
DB_PATH="/home/node/.n8n/database.sqlite"

case "$ACTION" in
  import)
    if [ -z "$FILE" ]; then
      echo "Usage: workflow-sync.sh import <file.json>"
      exit 1
    fi
    
    WORKFLOW_NAME=$(cat /data/workflows/$FILE | jq -r '.name')
    echo "Workflow name: $WORKFLOW_NAME"
    
    EXPORT_OUTPUT=$(n8n export:workflow --all 2>&1) || true
    EXISTING_IDS=$(echo "$EXPORT_OUTPUT" | jq -r '.[] | select(.name == "'"$WORKFLOW_NAME"'" and .isArchived != true) | .id' 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_IDS" ] && [ "$EXISTING_IDS" != "null" ] && [ "$EXISTING_IDS" != "" ]; then
      for ID in $EXISTING_IDS; do
        echo "Deleting existing workflow: $ID"
        sqlite3 "$DB_PATH" "DELETE FROM workflow_entity WHERE id = '$ID';" 2>/dev/null || true
      done
      echo "Importing new version..."
    else
      echo "Importing..."
    fi
    
    n8n import:workflow --input="/data/workflows/$FILE"
    echo "Done: $FILE"
    ;;
    
  delete)
    if [ -z "$FILE" ]; then
      echo "Usage: workflow-sync.sh delete <workflow-name>"
      exit 1
    fi
    
    WORKFLOW_NAME="$FILE"
    echo "Looking for: $WORKFLOW_NAME"
    
    EXPORT_OUTPUT=$(n8n export:workflow --all 2>&1) || true
    EXISTING_IDS=$(echo "$EXPORT_OUTPUT" | jq -r '.[] | select(.name == "'"$WORKFLOW_NAME"'" and .isArchived != true) | .id' 2>/dev/null || echo "")
    
    if [ -z "$EXISTING_IDS" ] || [ "$EXISTING_IDS" = "null" ]; then
      echo "Not found: $WORKFLOW_NAME"
      exit 1
    fi
    
    for ID in $EXISTING_IDS; do
      echo "Deleting: $ID"
      sqlite3 "$DB_PATH" "DELETE FROM workflow_entity WHERE id = '$ID';" 2>/dev/null || true
    done
    echo "Done"
    ;;
    
  list)
    n8n list:workflow 2>/dev/null || echo "No workflows"
    ;;
    
  export)
    n8n export:workflow --all --separate --output=/data/workflows/
    echo "Exported to /data/workflows/"
    ;;
    
  *)
    echo "Usage: workflow-sync.sh [action] [file/name]"
    echo ""
    echo "Actions:"
    echo "  import <file.json>  - Import workflow (replaces existing)"
    echo "  delete <name>       - Delete workflow by name"
    echo "  list                - List all workflows"
    echo "  export              - Export all workflows"
    ;;
esac
