# clmux.nvim Design

## Problem

When Claude Code edits files via its CLI tools (Edit/Write/MultiEdit), neovim
buffers go stale. There's no notification from Claude to the editor. You have to
manually `:e` to see changes. No visual indication of what changed or where.

## Solution

Two components that bridge Claude Code and neovim using tmux as the discovery
layer:

1. **Neovim plugin** — registers the nvim instance for discovery, exposes a
   `on_file_changed()` function that reloads buffers, jumps to the changed line,
   and flashes a highlight.

2. **Claude Code PostToolUse hook** — fires after Edit/Write/MultiEdit, extracts
   file path and line info from the tool's JSON, discovers the right nvim
   instance via tmux session/window matching, and calls into the plugin.

## Architecture

```
Claude Code (Edit tool)
  │
  ├─ writes to disk
  ├─ PostToolUse fires
  │
  ▼
claude-live-hook.sh
  │
  ├─ parses JSON stdin (file_path, new_string)
  ├─ greps file for line number of new content
  ├─ tmux display-message → session:window key
  ├─ reads ~/.claude/nvim-servers/<key>.json
  ├─ validates PID
  │
  ▼
nvim --server <socket> --remote-expr
  │
  ▼
clmux.on_file_changed(file, start_line, end_line)
  │
  ├─ finds visible windows with that buffer
  ├─ :checktime to reload
  ├─ jumps to start_line, centers (zz)
  ├─ applies extmark highlight (ClmuxFlash)
  └─ 1.5s timer clears highlight
```

## Nvim Discovery

Each nvim instance writes a discovery file on setup:

- Path: `~/.claude/nvim-servers/<tmux_session>:<tmux_window>.json`
- Content: `{ "socket": "<v:servername>", "pid": <nvim_pid> }`
- Cleaned up on VimLeavePre

The hook finds the right nvim by matching its own tmux session:window against
discovery files.

## Highlight Behavior

- Flash-then-fade: highlight changed lines for ~1.5s using `ClmuxFlash`
  highlight group (defaults to `IncSearch`)
- Only on visible windows — if the buffer isn't displayed, silent reload only
- Similar UX to vim's `yankhighlight`

## File Structure

```
lua/clmux/
  init.lua              -- setup(), on_file_changed(), discovery

hooks/
  clmux-hook.sh         -- PostToolUse hook script

install.sh              -- copies hook + updates claude settings
```

## Scope

This plugin does ONE thing: live buffer sync with visual feedback. It does not
replace claudecode.nvim (selection sharing, diagnostics, diffs). They run
alongside each other.
