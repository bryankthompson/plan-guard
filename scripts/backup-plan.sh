#!/bin/bash
# plan-guard: PreCompact hook
# Backs up recently modified plan files before context compaction

PLANS_DIR="$HOME/.claude/plans"
BACKUP_DIR="$PLANS_DIR/.backups"

# Nothing to do if no plans directory
if [ ! -d "$PLANS_DIR" ]; then
  exit 0
fi

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKED_UP=""

# Find plan files modified in the last 30 minutes
while IFS= read -r plan_file; do
  [ -z "$plan_file" ] && continue
  BASENAME=$(basename "$plan_file")
  BACKUP_NAME="${BASENAME%.md}-${TIMESTAMP}.md"
  cp "$plan_file" "$BACKUP_DIR/$BACKUP_NAME"
  BACKED_UP="${BACKED_UP}  - ${BASENAME} -> .backups/${BACKUP_NAME}\n"
done < <(find "$PLANS_DIR" -maxdepth 1 -name "*.md" -type f -mmin -30 2>/dev/null)

# Clean up old backups (keep last 20)
ls -t "$BACKUP_DIR"/*.md 2>/dev/null | tail -n +21 | xargs rm -f 2>/dev/null

if [ -n "$BACKED_UP" ]; then
  CONTEXT="[plan-guard] Backed up plan files before compaction:\n${BACKED_UP}Backups stored in: ${BACKUP_DIR}"
  jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
      hookEventName: "PreCompact",
      additionalContext: $ctx
    }
  }'
fi

exit 0
