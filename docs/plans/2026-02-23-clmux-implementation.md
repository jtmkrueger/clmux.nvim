# clmux.nvim Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a neovim plugin that live-syncs buffers when Claude Code edits files, with cursor jump and flash highlight, using tmux for nvim instance discovery.

**Architecture:** Two components — a Lua neovim plugin (discovery + buffer reload + highlight) and a shell hook script (JSON parsing + tmux discovery + nvim RPC call). Communication flows: Claude PostToolUse → hook.sh → nvim RPC → plugin Lua function.

**Tech Stack:** Neovim Lua API, vim.loop (libuv), jq, tmux CLI, nvim --remote-expr RPC. Testing with busted + nlua.

---

### Task 1: Project scaffolding

**Files:**
- Create: `lua/clmux/init.lua`
- Create: `hooks/clmux-hook.sh`
- Create: `.busted`
- Create: `Makefile`
- Create: `spec/minimal_init.lua`

**Step 1: Create the Lua module skeleton**

```lua
-- lua/clmux/init.lua
local M = {}

M.config = {
  highlight_group = "ClmuxFlash",
  highlight_duration = 1500,
  discovery_dir = vim.fn.expand("~/.claude/nvim-servers"),
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

function M.on_file_changed(file_path, start_line, end_line)
end

return M
```

**Step 2: Create the hook script skeleton**

```bash
#!/usr/bin/env bash
# hooks/clmux-hook.sh
# Claude Code PostToolUse hook for clmux.nvim
# Reads JSON from stdin, extracts file change info,
# discovers the right nvim instance, and calls on_file_changed.
set -euo pipefail
exit 0
```

**Step 3: Create test infrastructure**

`.busted`:
```lua
return {
  _all = {
    coverage = false,
    lpath = "lua/?.lua;lua/?/init.lua",
    lua = "nlua",
  },
  default = {
    verbose = true,
  },
}
```

`spec/minimal_init.lua`:
```lua
vim.opt.rtp:prepend(".")
```

`Makefile`:
```makefile
.PHONY: test lint

test:
	@eval $$(luarocks path --no-bin) && busted --verbose

lint:
	luacheck lua/ spec/
```

**Step 4: Commit**

```bash
git add lua/clmux/init.lua hooks/clmux-hook.sh .busted Makefile spec/minimal_init.lua
git commit -m "scaffold project structure"
```

---

### Task 2: Discovery — nvim registers itself

**Files:**
- Modify: `lua/clmux/init.lua`
- Create: `spec/clmux/discovery_spec.lua`

**Step 1: Write failing test for discovery registration**

```lua
-- spec/clmux/discovery_spec.lua
describe("discovery", function()
  local clmux

  before_each(function()
    -- Use a temp dir so tests don't touch real ~/.claude
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")

    -- Mock tmux response
    local original_system = vim.fn.system
    _G._clmux_original_system = original_system
    vim.fn.system = function(cmd)
      if type(cmd) == "string" and cmd:match("tmux display%-message") then
        return "work:2\n"
      end
      return original_system(cmd)
    end

    package.loaded["clmux"] = nil
    clmux = require("clmux")
    clmux.setup({ discovery_dir = tmpdir })
  end)

  after_each(function()
    vim.fn.system = _G._clmux_original_system
    clmux._unregister()
  end)

  it("writes discovery file with socket and pid", function()
    clmux._register()
    local key = "work:2"
    local path = clmux.config.discovery_dir .. "/" .. key .. ".json"
    local content = vim.fn.readfile(path)
    local data = vim.fn.json_decode(table.concat(content, "\n"))
    assert.is_not_nil(data.socket)
    assert.equals(vim.fn.getpid(), data.pid)
  end)

  it("removes discovery file on unregister", function()
    clmux._register()
    local key = "work:2"
    local path = clmux.config.discovery_dir .. "/" .. key .. ".json"
    assert.equals(1, vim.fn.filereadable(path))
    clmux._unregister()
    assert.equals(0, vim.fn.filereadable(path))
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `_register` and `_unregister` don't exist

**Step 3: Implement discovery registration**

In `lua/clmux/init.lua`, add:

```lua
local M = {}

M.config = {
  highlight_group = "ClmuxFlash",
  highlight_duration = 1500,
  discovery_dir = vim.fn.expand("~/.claude/nvim-servers"),
}

M._tmux_key = nil

local function get_tmux_key()
  local result = vim.fn.system("tmux display-message -p '#{session_name}:#{window_index}'")
  return vim.trim(result)
end

function M._register()
  if vim.env.TMUX == nil then
    return
  end

  vim.fn.mkdir(M.config.discovery_dir, "p")

  local key = get_tmux_key()
  M._tmux_key = key

  local data = vim.fn.json_encode({
    socket = vim.v.servername,
    pid = vim.fn.getpid(),
  })

  local path = M.config.discovery_dir .. "/" .. key .. ".json"
  vim.fn.writefile({ data }, path)
end

function M._unregister()
  if M._tmux_key == nil then
    return
  end

  local path = M.config.discovery_dir .. "/" .. M._tmux_key .. ".json"
  vim.fn.delete(path)
  M._tmux_key = nil
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  M._register()

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M._unregister()
    end,
  })
end

function M.on_file_changed(file_path, start_line, end_line)
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/clmux/init.lua spec/clmux/discovery_spec.lua
git commit -m "feat: discovery registration via tmux session:window"
```

---

### Task 3: on_file_changed — buffer reload + cursor jump

**Files:**
- Modify: `lua/clmux/init.lua`
- Create: `spec/clmux/on_file_changed_spec.lua`

**Step 1: Write failing test for buffer reload and cursor jump**

```lua
-- spec/clmux/on_file_changed_spec.lua
describe("on_file_changed", function()
  local clmux
  local tmpfile

  before_each(function()
    package.loaded["clmux"] = nil
    clmux = require("clmux")
    clmux.setup({ discovery_dir = vim.fn.tempname() })

    -- Create a temp file with known content
    tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "line1", "line2", "line3", "line4", "line5" }, tmpfile)

    -- Open it in a buffer
    vim.cmd("edit " .. tmpfile)
  end)

  after_each(function()
    vim.cmd("bdelete!")
    vim.fn.delete(tmpfile)
  end)

  it("reloads buffer when file changes on disk", function()
    -- Modify file on disk (simulating Claude's edit)
    vim.fn.writefile({ "line1", "CHANGED", "line3", "line4", "line5" }, tmpfile)

    clmux.on_file_changed(tmpfile, 2, 2)

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.equals("CHANGED", lines[2])
  end)

  it("jumps cursor to start_line", function()
    vim.fn.writefile({ "line1", "CHANGED", "line3", "line4", "line5" }, tmpfile)

    clmux.on_file_changed(tmpfile, 2, 2)

    local cursor = vim.api.nvim_win_get_cursor(0)
    assert.equals(2, cursor[1])
  end)

  it("does nothing if file is not in any visible window", function()
    local otherfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "other" }, otherfile)

    -- Should not error, just silently reload buffer if loaded
    clmux.on_file_changed(otherfile, 1, 1)

    -- Cursor should not have moved
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert.equals(1, cursor[1])

    vim.fn.delete(otherfile)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — on_file_changed is empty

**Step 3: Implement on_file_changed (reload + jump)**

Replace the empty `on_file_changed` in `lua/clmux/init.lua`:

```lua
function M.on_file_changed(file_path, start_line, end_line)
  start_line = start_line or 1
  end_line = end_line or start_line

  local abs_path = vim.fn.fnamemodify(file_path, ":p")

  -- Find buffers for this file
  local target_buf = nil
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local buf_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")
      if buf_path == abs_path then
        target_buf = buf
        break
      end
    end
  end

  if target_buf == nil then
    return
  end

  -- Reload the buffer from disk
  vim.api.nvim_buf_call(target_buf, function()
    vim.cmd("checktime")
  end)

  -- Find visible windows showing this buffer
  local visible_wins = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == target_buf then
      table.insert(visible_wins, win)
    end
  end

  if #visible_wins == 0 then
    return
  end

  -- Jump and highlight in each visible window
  for _, win in ipairs(visible_wins) do
    local line_count = vim.api.nvim_buf_line_count(target_buf)
    local safe_line = math.min(start_line, line_count)
    local safe_end = math.min(end_line, line_count)

    vim.api.nvim_win_set_cursor(win, { safe_line, 0 })

    -- Center the viewport
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! zz")
    end)

    M._flash(target_buf, safe_line, safe_end)
  end
end
```

**Step 4: Add a stub `_flash` that does nothing (highlight is next task)**

```lua
function M._flash(buf, start_line, end_line)
  -- implemented in Task 4
end
```

**Step 5: Run test to verify it passes**

Run: `make test`
Expected: PASS

**Step 6: Commit**

```bash
git add lua/clmux/init.lua spec/clmux/on_file_changed_spec.lua
git commit -m "feat: on_file_changed reloads buffer and jumps to line"
```

---

### Task 4: Flash highlight

**Files:**
- Modify: `lua/clmux/init.lua`
- Create: `spec/clmux/highlight_spec.lua`

**Step 1: Write failing test for highlight**

```lua
-- spec/clmux/highlight_spec.lua
describe("flash highlight", function()
  local clmux
  local tmpfile

  before_each(function()
    package.loaded["clmux"] = nil
    clmux = require("clmux")
    clmux.setup({
      discovery_dir = vim.fn.tempname(),
      highlight_duration = 100,  -- fast for tests
    })

    tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "line1", "line2", "line3", "line4", "line5" }, tmpfile)
    vim.cmd("edit " .. tmpfile)
  end)

  after_each(function()
    vim.cmd("bdelete!")
    vim.fn.delete(tmpfile)
  end)

  it("creates extmarks on the highlighted lines", function()
    local buf = vim.api.nvim_get_current_buf()
    clmux._flash(buf, 2, 3)

    local ns = vim.api.nvim_create_namespace("clmux_flash")
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    assert.equals(2, #marks)
  end)

  it("clears extmarks after duration", function()
    local buf = vim.api.nvim_get_current_buf()
    clmux._flash(buf, 2, 3)

    -- Wait for timer to fire (duration + margin)
    vim.wait(200, function() return false end)

    local ns = vim.api.nvim_create_namespace("clmux_flash")
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    assert.equals(0, #marks)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `_flash` is a stub

**Step 3: Implement flash highlight**

Replace the `_flash` stub in `lua/clmux/init.lua`:

```lua
local ns = vim.api.nvim_create_namespace("clmux_flash")

function M._flash(buf, start_line, end_line)
  -- Set up highlight group if it doesn't exist
  local ok = pcall(vim.api.nvim_get_hl_by_name, M.config.highlight_group, true)
  if not ok then
    vim.api.nvim_set_hl(0, M.config.highlight_group, { link = "IncSearch" })
  end

  -- Clear any existing flash marks
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  -- Add extmarks for the highlight range (0-indexed)
  local mark_ids = {}
  for line = start_line, end_line do
    local id = vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
      end_row = line - 1,
      end_col = 0,
      hl_group = M.config.highlight_group,
      hl_eol = true,
    })
    table.insert(mark_ids, id)
  end

  -- Clear after duration
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end, M.config.highlight_duration)
end
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/clmux/init.lua spec/clmux/highlight_spec.lua
git commit -m "feat: flash-then-fade highlight on changed lines"
```

---

### Task 5: Hook script — JSON parsing + line detection

**Files:**
- Modify: `hooks/clmux-hook.sh`
- Create: `spec/hook_spec.sh` (shell-based test)

**Step 1: Write test for the hook script**

Create `spec/hook_test.sh` — a simple shell test since the hook is a bash script:

```bash
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
    ((PASS++))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    ((FAIL++))
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
```

**Step 2: Implement the hook script**

```bash
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
```

**Step 3: Make hook executable and run tests**

```bash
chmod +x hooks/clmux-hook.sh
bash spec/hook_test.sh
```

Expected: all 4 tests PASS

**Step 4: Add hook test to Makefile**

Add to `Makefile`:

```makefile
test-hook:
	bash spec/hook_test.sh

test-all: test test-hook
```

**Step 5: Commit**

```bash
git add hooks/clmux-hook.sh spec/hook_test.sh Makefile
git commit -m "feat: PostToolUse hook with JSON parsing and nvim discovery"
```

---

### Task 6: Install script

**Files:**
- Create: `install.sh`

**Step 1: Write the install script**

```bash
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
```

**Step 2: Commit**

```bash
chmod +x install.sh
git add install.sh
git commit -m "feat: install script for hook and settings"
```

---

### Task 7: End-to-end manual test

**Files:** None (manual verification)

**Step 1: Install the plugin in your nvim config**

Add to `init.lua`:
```lua
{
  dir = '~/Code/clmux.nvim',
  config = function()
    require('clmux').setup()
  end,
},
```

**Step 2: Run install.sh**

```bash
cd ~/Code/clmux.nvim && bash install.sh
```

**Step 3: Add the hook to ~/.claude/settings.json**

**Step 4: Verify discovery file is created**

```bash
ls ~/.claude/nvim-servers/
# Should show <session>:<window>.json
cat ~/.claude/nvim-servers/*.json
# Should show socket and pid
```

**Step 5: Test the full loop**

Open a file in nvim. In the claude terminal (same tmux window), make an edit to that file. Observe:
- Buffer reloads
- Cursor jumps to the changed line
- Flash highlight appears and fades

**Step 6: Commit any fixes, then tag**

```bash
git tag v0.1.0
```
