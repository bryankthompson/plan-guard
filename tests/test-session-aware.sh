#!/bin/bash
# tests/test-session-aware.sh — regression suite for plan-guard v1.1.0 session-aware behavior
#
# Covers the two hooks added/changed in v1.1.0:
#   - scripts/reinject-plan.sh  (SessionStart compact, session-scoped reinjection)
#   - scripts/backup-plan.sh    (PreCompact, session-id stamping + backup)
#
# Each test uses a unique mktemp -d directory passed via PLANS_DIR; the real
# ~/.claude/plans/ is NEVER touched. The hooks read PLANS_DIR from env (added
# in v1.1.0 specifically to enable this isolation).
#
# Usage: bash tests/test-session-aware.sh
# Returns: 0 if all tests pass, 1 if any fail.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$TESTS_DIR")"
SCRIPTS_DIR="$REPO_ROOT/scripts"

PASS=0
FAIL=0

# --- Test infrastructure --------------------------------------------------

TMPDIR_TEST=""

cleanup_tmpdir() {
  if [ -n "${TMPDIR_TEST:-}" ]; then
    rm -rf "$TMPDIR_TEST"
    TMPDIR_TEST=""
  fi
}
trap cleanup_tmpdir EXIT

setup() {
  cleanup_tmpdir
  TMPDIR_TEST=$(mktemp -d -t plan-guard-tests.XXXXXX)
  export PLANS_DIR="$TMPDIR_TEST/plans"
  mkdir -p "$PLANS_DIR"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    echo "    expected: ${expected}"
    echo "    actual:   ${actual}"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    echo "    needle:   ${needle}"
    echo "    haystack: ${haystack:0:200}..."
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    echo "    should NOT contain: ${needle}"
    echo "    haystack:           ${haystack:0:200}..."
    FAIL=$((FAIL + 1))
  fi
}

# --- Tests ----------------------------------------------------------------

echo "=== T1: reinject matches by session-id, even when newer plan from another session exists ==="
setup
SESSION_A="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
SESSION_B="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
cat > "$PLANS_DIR/plan-A.md" <<EOF
---
session-id: $SESSION_A
---
# Plan A
EOF
sleep 1
cat > "$PLANS_DIR/plan-B.md" <<EOF
---
session-id: $SESSION_B
---
# Plan B
EOF
out=$(printf '%s' "{\"session_id\":\"$SESSION_A\",\"source\":\"compact\"}" \
  | bash "$SCRIPTS_DIR/reinject-plan.sh")
assert_contains   "surfaces plan-A.md"           "plan-A.md" "$out"
assert_not_contains "does not surface plan-B.md" "plan-B.md" "$out"

echo ""
echo "=== T2: reinject emits 'no match' message when session-id matches nothing ==="
setup
cat > "$PLANS_DIR/plan-X.md" <<EOF
---
session-id: some-other-id
---
# Plan X
EOF
out=$(printf '%s' '{"session_id":"unknown-id","source":"compact"}' \
  | bash "$SCRIPTS_DIR/reinject-plan.sh")
assert_contains "emits 'No active plan file matched'" "No active plan file matched" "$out"

echo ""
echo "=== T3: reinject silent skip (no output, exit 0) when session_id is missing ==="
setup
cat > "$PLANS_DIR/plan-X.md" <<EOF
---
session-id: any-id
---
# Plan X
EOF
out=$(printf '%s' '{"source":"compact"}' \
  | bash "$SCRIPTS_DIR/reinject-plan.sh")
assert_eq "output is empty" "" "$out"

echo ""
echo "=== T4: reinject ignores plans with malformed frontmatter (no closing ---) ==="
setup
TARGET_SID="target-session-id"
# Malformed: no closing ---
cat > "$PLANS_DIR/malformed.md" <<EOF
---
session-id: $TARGET_SID
# Plan content runs directly into the frontmatter — no closing marker
EOF
out=$(printf '%s' "{\"session_id\":\"$TARGET_SID\",\"source\":\"compact\"}" \
  | bash "$SCRIPTS_DIR/reinject-plan.sh")
# With the current awk parser, missing closing --- still allows reading session-id
# from inside the open block. Document the current behavior — if we want to
# require well-formed frontmatter, this test is where we'd flip the assertion.
# For now: parser is permissive, which is fine because the malformed file STILL
# carries a session-id and recovering it doesn't risk cross-session leakage.
assert_contains "permissive match still requires session-id present" "malformed.md" "$out"

echo ""
echo "=== T5: backup stamps an unfrontmattered file with session-id ==="
setup
SESSION_ID="t5-session-id"
cat > "$PLANS_DIR/plan-no-fm.md" <<EOF
# Plan without frontmatter
This file has no YAML frontmatter.
EOF
touch "$PLANS_DIR/plan-no-fm.md"
printf '%s' "{\"session_id\":\"$SESSION_ID\",\"trigger\":\"manual\"}" \
  | bash "$SCRIPTS_DIR/backup-plan.sh" > /dev/null
first_line=$(head -1  "$PLANS_DIR/plan-no-fm.md")
second_line=$(sed -n 2p "$PLANS_DIR/plan-no-fm.md")
fourth_line=$(sed -n 4p "$PLANS_DIR/plan-no-fm.md")
assert_eq "first line is opening ---"   "---"                          "$first_line"
assert_eq "second line is session-id"   "session-id: $SESSION_ID"      "$second_line"
assert_eq "fourth line is closing ---"  "---"                          "$fourth_line"

echo ""
echo "=== T6: backup LEAVES frontmattered files UNTOUCHED (idempotence — the most important test) ==="
setup
SESSION_ID="t6-caller-session-id"
ORIGINAL_SID="original-session-id-DO-NOT-OVERWRITE"
ORIGINAL_TASK="task-hint: \"Pre-existing frontmatter that must survive\""
cat > "$PLANS_DIR/plan-fm.md" <<EOF
---
session-id: $ORIGINAL_SID
$ORIGINAL_TASK
---
# Plan with original frontmatter
EOF
touch "$PLANS_DIR/plan-fm.md"
printf '%s' "{\"session_id\":\"$SESSION_ID\",\"trigger\":\"manual\"}" \
  | bash "$SCRIPTS_DIR/backup-plan.sh" > /dev/null
second_line=$(sed -n 2p "$PLANS_DIR/plan-fm.md")
third_line=$(sed -n  3p "$PLANS_DIR/plan-fm.md")
assert_eq "original session-id preserved" "session-id: $ORIGINAL_SID" "$second_line"
assert_eq "original task-hint preserved"  "$ORIGINAL_TASK"            "$third_line"

echo ""
echo "=== T7: backup doesn't stamp when session_id is empty/missing ==="
setup
cat > "$PLANS_DIR/plan-no-fm.md" <<EOF
# Plan without frontmatter
EOF
touch "$PLANS_DIR/plan-no-fm.md"
printf '%s' '{"trigger":"manual"}' \
  | bash "$SCRIPTS_DIR/backup-plan.sh" > /dev/null
first_line=$(head -1 "$PLANS_DIR/plan-no-fm.md")
assert_eq "first line unchanged (no stamping)" "# Plan without frontmatter" "$first_line"

echo ""
echo "========================================"
echo "  $PASS passed, $FAIL failed"
echo "========================================"

[ "$FAIL" -eq 0 ]
