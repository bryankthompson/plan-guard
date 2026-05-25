#!/bin/bash
# plan-guard: SessionStart (compact) hook — session-scoped reinjection
#
# Reads session_id from hook input (stdin JSON) and only surfaces a plan file
# whose `session-id:` YAML frontmatter matches. If no plan matches, emits an
# explicit "no plan recovered" context so the agent doesn't silently inherit
# the wrong plan from a different session's work stream.
#
# Backward compat: plan files without `session-id:` frontmatter are ignored.
# The companion backup-plan.sh (PreCompact) stamps unfrontmattered plans with
# the current session id, so any plan that has been compacted at least once
# will be recoverable.

PLANS_DIR="$HOME/.claude/plans"
[ ! -d "$PLANS_DIR" ] && exit 0

# Read hook input: SessionStart receives {session_id, source, ...} via stdin
INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null || echo "")

if [ -z "$SESSION_ID" ]; then
  # No session id — can't disambiguate. Skip rather than risk wrong-plan recovery.
  exit 0
fi

# Find the most recent plan file whose session-id frontmatter matches.
MATCHED=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # Parse YAML frontmatter, extract session-id value, strip surrounding quotes.
  f_session=$(awk '
    BEGIN { in_fm = 0 }
    /^---[[:space:]]*$/ {
      if (in_fm) { exit } else { in_fm = 1; next }
    }
    in_fm && /^session-id:/ {
      sub(/^session-id:[[:space:]]*/, "")
      sub(/^"/, ""); sub(/"$/, "")
      sub(/^\047/, ""); sub(/\047$/, "")
      print
      exit
    }
  ' "$f" 2>/dev/null)

  if [ "$f_session" = "$SESSION_ID" ]; then
    MATCHED="$f"
    break
  fi
done < <(ls -t "$PLANS_DIR"/*.md 2>/dev/null)

if [ -z "$MATCHED" ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: "[plan-guard] No active plan file matched this session id. Start fresh or read an existing plan by explicit path."
    }
  }'
  exit 0
fi

PLAN_NAME=$(basename "$MATCHED")
PLAN_CONTENT=$(head -150 "$MATCHED")

CONTEXT="[plan-guard] Active plan file recovered after compaction.
Plan file path: ${MATCHED}
Plan file name: ${PLAN_NAME}

--- Plan Content ---
${PLAN_CONTENT}
--- End Plan Content ---

IMPORTANT: If you need to update this plan, write to: ${MATCHED}"

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
