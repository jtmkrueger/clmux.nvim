#!/usr/bin/env bash
# spec/hook_test.sh
# Integration test for clmux-hook.sh
set -euo pipefail

HOOK="$(dirname "$0")/../hooks/clmux-hook.sh"
PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

# --- Test: extract_file_path for Edit ---
echo "Test: extract file_path from Edit JSON"
RESULT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test.lua","old_string":"old","new_string":"new"}}' \
  | bash "$HOOK" --dry-run 2>&1 | head -1)
assert_eq "file_path" "/tmp/test.lua" "$RESULT"

# --- Test: extract_file_path for Write ---
echo "Test: extract file_path from Write JSON"
RESULT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.lua","content":"hello"}}' \
  | bash "$HOOK" --dry-run 2>&1 | head -1)
assert_eq "file_path" "/tmp/test.lua" "$RESULT"

# --- Test: line detection for Edit ---
echo "Test: find line number for Edit new_string"
TMPFILE=$(mktemp)
printf 'line1\nNEW_CONTENT\nline3\n' > "$TMPFILE"
RESULT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPFILE\",\"old_string\":\"old\",\"new_string\":\"NEW_CONTENT\"}}" \
  | bash "$HOOK" --dry-run 2>&1 | sed -n '2p')
assert_eq "start_line" "2" "$RESULT"
rm -f "$TMPFILE"

# --- Test: Write defaults to line 1 ---
echo "Test: Write defaults to line 1"
RESULT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.lua","content":"hello"}}' \
  | bash "$HOOK" --dry-run 2>&1 | sed -n '2p')
assert_eq "start_line" "1" "$RESULT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
