#!/bin/bash
# plan-guard: SessionStart (compact) hook
# Re-injects the most recent plan file content after context compaction

PLANS_DIR="$HOME/.claude/plans"

if [ ! -d "$PLANS_DIR" ]; then
  exit 0
fi

# Find the most recently modified plan file (not in .backups)
LATEST_PLAN=$(find "$PLANS_DIR" -maxdepth 1 -name "*.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

# macOS fallback (no -printf support)
if [ -z "$LATEST_PLAN" ]; then
  LATEST_PLAN=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1)
fi

if [ -z "$LATEST_PLAN" ] || [ ! -f "$LATEST_PLAN" ]; then
  exit 0
fi

PLAN_NAME=$(basename "$LATEST_PLAN")
PLAN_CONTENT=$(head -150 "$LATEST_PLAN")

CONTEXT="[plan-guard] Active plan file recovered after compaction.
Plan file path: ${LATEST_PLAN}
Plan file name: ${PLAN_NAME}

--- Plan Content ---
${PLAN_CONTENT}
--- End Plan Content ---

IMPORTANT: If you need to update this plan, write to: ${LATEST_PLAN}"

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
