#!/usr/bin/env bash
# hooks/clmux-hook.sh
# Claude Code PostToolUse hook for clmux.nvim
#
# Reads JSON from stdin, extracts file path and changed line range,
# discovers the nvim instance in the same tmux window, and sends
# an RPC call to trigger buffer reload + highlight.
set -euo pipefail

INPUT=$(cat)
DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

# --- Extract file path ---
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# --- Determine changed line range ---
START_LINE=1
END_LINE=1

if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
  # For Edit: grep the file for the first line of new_string
  if [ "$TOOL_NAME" = "Edit" ]; then
    NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
  else
    # MultiEdit: use the last edit's new_string (most recently changed)
    NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.edits[-1].new_string // empty')
  fi

  if [ -n "$NEW_STRING" ] && [ -f "$FILE_PATH" ]; then
    FIRST_LINE=$(echo "$NEW_STRING" | head -1)
    MATCH=$(grep -n -F -m 1 -- "$FIRST_LINE" "$FILE_PATH" 2>/dev/null || true)
    if [ -n "$MATCH" ]; then
      START_LINE=$(echo "$MATCH" | cut -d: -f1)
      # Count lines in new_string for end_line
      LINE_COUNT=$(echo "$NEW_STRING" | wc -l | tr -d ' ')
      END_LINE=$((START_LINE + LINE_COUNT - 1))
    fi
  fi
fi

# --- Dry run: output parsed values for testing ---
if [ "$DRY_RUN" = true ]; then
  echo "$FILE_PATH"
  echo "$START_LINE"
  echo "$END_LINE"
  exit 0
fi

# --- Discover nvim instance ---
DISCOVERY_DIR="${HOME}/.claude/nvim-servers"
TMUX_KEY=$(tmux display-message -p '#{session_name}:#{window_index}' 2>/dev/null || true)
[ -z "$TMUX_KEY" ] && exit 0

DISCOVERY_FILE="${DISCOVERY_DIR}/${TMUX_KEY}.json"
[ -f "$DISCOVERY_FILE" ] || exit 0

SOCKET=$(jq -r '.socket // empty' "$DISCOVERY_FILE")
PID=$(jq -r '.pid // empty' "$DISCOVERY_FILE")

[ -z "$SOCKET" ] && exit 0
[ -z "$PID" ] && exit 0

# Validate PID is alive
kill -0 "$PID" 2>/dev/null || exit 0

# --- Send RPC to nvim ---
# Escape file path for Lua string
ESCAPED_PATH=$(echo "$FILE_PATH" | sed "s/'/\\\\'/g")

nvim --server "$SOCKET" --remote-expr \
  "luaeval('require(\"clmux\").on_file_changed(_A[1], _A[2], _A[3])', ['${ESCAPED_PATH}', ${START_LINE}, ${END_LINE}])" \
  2>/dev/null || true

exit 0
