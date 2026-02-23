#!/usr/bin/env bash
# install.sh
# Copies the hook script and registers it in Claude Code settings.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SRC="${SCRIPT_DIR}/hooks/clmux-hook.sh"
HOOK_DST="${HOME}/.claude/hooks/clmux-hook.sh"
SETTINGS="${HOME}/.claude/settings.json"

echo "Installing clmux.nvim hook..."

# Copy hook script
mkdir -p "$(dirname "$HOOK_DST")"
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"
echo "  Copied hook to ${HOOK_DST}"

# Create discovery directory
mkdir -p "${HOME}/.claude/nvim-servers"
echo "  Created discovery directory"

# Check if settings already has the hook
if [ -f "$SETTINGS" ] && jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command | test("clmux"))' "$SETTINGS" >/dev/null 2>&1; then
  echo "  Hook already registered in settings.json"
else
  echo ""
  echo "  Add this to your ~/.claude/settings.json hooks section:"
  echo ""
  echo '  "hooks": {'
  echo '    "PostToolUse": ['
  echo '      {'
  echo '        "matcher": "Edit|Write|MultiEdit",'
  echo '        "hooks": ['
  echo '          {'
  echo '            "type": "command",'
  echo "            \"command\": \"${HOOK_DST}\""
  echo '          }'
  echo '        ]'
  echo '      }'
  echo '    ]'
  echo '  }'
  echo ""
  echo "  (Auto-editing settings.json is risky — please add it manually.)"
fi

echo ""
echo "Done. Add clmux.nvim to your lazy.nvim config:"
echo ""
echo "  {"
echo "    dir = '${SCRIPT_DIR}',"
echo "    config = function()"
echo "      require('clmux').setup()"
echo "    end,"
echo "  }"
