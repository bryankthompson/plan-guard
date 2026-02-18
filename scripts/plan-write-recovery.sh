#!/bin/bash
# plan-guard: PostToolUseFailure hook
# Catches plan file write failures and creates a recovery file

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
ERROR=$(echo "$INPUT" | jq -r '.error // empty')

# Only handle plan file failures
if [[ "$FILE_PATH" != *"/plans/"* ]] && [[ "$FILE_PATH" != *"/plans\\"* ]]; then
  exit 0
fi

# Skip backup files
if [[ "$FILE_PATH" == *"/.backups/"* ]]; then
  exit 0
fi

PLANS_DIR="$HOME/.claude/plans"
BACKUP_DIR="$PLANS_DIR/.backups"
BASENAME=$(basename "$FILE_PATH")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RECOVERY_NAME="${BASENAME%.md}-recovered-${TIMESTAMP}.md"
RECOVERY_PATH="$PLANS_DIR/$RECOVERY_NAME"

mkdir -p "$PLANS_DIR"

# Try to restore from backup
RESTORED=false
if [ -d "$BACKUP_DIR" ]; then
  # Find the most recent backup of this plan file
  PLAN_PREFIX="${BASENAME%.md}"
  LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/${PLAN_PREFIX}-*.md 2>/dev/null | head -1)

  if [ -n "$LATEST_BACKUP" ] && [ -f "$LATEST_BACKUP" ]; then
    cp "$LATEST_BACKUP" "$RECOVERY_PATH"
    RESTORED=true
  fi
fi

# If no backup found, create empty recovery file
if [ "$RESTORED" = false ]; then
  touch "$RECOVERY_PATH"
fi

if [ "$RESTORED" = true ]; then
  CONTEXT="[plan-guard] Plan file write FAILED for: ${FILE_PATH}
Error: ${ERROR}

RECOVERED from backup: ${LATEST_BACKUP}
New plan file created at: ${RECOVERY_PATH}

ACTION REQUIRED: Write your plan to this new file instead: ${RECOVERY_PATH}"
else
  CONTEXT="[plan-guard] Plan file write FAILED for: ${FILE_PATH}
Error: ${ERROR}

No backup found, but a new empty plan file was created at: ${RECOVERY_PATH}

ACTION REQUIRED: Write your plan to this new file instead: ${RECOVERY_PATH}"
fi

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUseFailure",
    additionalContext: $ctx
  }
}'

exit 0
