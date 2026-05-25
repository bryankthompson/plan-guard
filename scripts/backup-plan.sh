#!/bin/bash
# plan-guard: PreCompact hook — session-aware backup + stamping
#
# Backs up recently modified plan files before context compaction.
# Also stamps unfrontmattered plan files with `session-id:` YAML frontmatter
# so the SessionStart reinject hook can correctly match them later.
#
# Stamping is idempotent: only adds frontmatter to files that have none.
# Files that already have ANY YAML frontmatter (any `---` first line) are
# left untouched, so we don't clobber agent-authored metadata.

# PLANS_DIR is overridable for test isolation; defaults to the real plans dir.
PLANS_DIR="${PLANS_DIR:-$HOME/.claude/plans}"
BACKUP_DIR="$PLANS_DIR/.backups"

if [ ! -d "$PLANS_DIR" ]; then
  exit 0
fi

# Read hook input: PreCompact receives {session_id, ...} via stdin
INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null || echo "")

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ISO_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BACKED_UP=""
STAMPED=""

# Find plan files modified in the last 30 minutes
while IFS= read -r plan_file; do
  [ -z "$plan_file" ] && continue
  BASENAME=$(basename "$plan_file")

  # Stamp session-id frontmatter if the file has no frontmatter AND we know
  # the current session id. Atomic write via temp file + mv.
  if [ -n "$SESSION_ID" ] && ! head -1 "$plan_file" 2>/dev/null | grep -q '^---[[:space:]]*$'; then
    TMP=$(mktemp)
    {
      printf -- '---\n'
      printf 'session-id: %s\n' "$SESSION_ID"
      printf 'stamped-by: plan-guard PreCompact %s\n' "$ISO_TIMESTAMP"
      printf -- '---\n\n'
      cat "$plan_file"
    } > "$TMP"
    if mv "$TMP" "$plan_file" 2>/dev/null; then
      STAMPED="${STAMPED}  - ${BASENAME} stamped with session-id\n"
    else
      rm -f "$TMP"
    fi
  fi

  BACKUP_NAME="${BASENAME%.md}-${TIMESTAMP}.md"
  cp "$plan_file" "$BACKUP_DIR/$BACKUP_NAME"
  BACKED_UP="${BACKED_UP}  - ${BASENAME} -> .backups/${BACKUP_NAME}\n"
done < <(find "$PLANS_DIR" -maxdepth 1 -name "*.md" -type f -mmin -30 2>/dev/null)

# Clean up old backups (keep last 20)
ls -t "$BACKUP_DIR"/*.md 2>/dev/null | tail -n +21 | xargs rm -f 2>/dev/null

if [ -n "$BACKED_UP" ]; then
  CONTEXT="[plan-guard] Backed up plan files before compaction:\n${BACKED_UP}"
  if [ -n "$STAMPED" ]; then
    CONTEXT="${CONTEXT}\n[plan-guard] Stamped session-id frontmatter on:\n${STAMPED}"
  fi
  CONTEXT="${CONTEXT}Backups stored in: ${BACKUP_DIR}"
  jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
      hookEventName: "PreCompact",
      additionalContext: $ctx
    }
  }'
fi

exit 0
