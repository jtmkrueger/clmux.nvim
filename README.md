# clmux.nvim

See what Claude Code is doing in real time. When Claude edits a file you have
open, the changes appear in your buffer immediately. No reload prompt, no
context switch. A brief highlight flashes over the changed lines so you can
follow along.
You and Claude can work in the file together at the same time. Your unsaved
changes are preserved; only the lines Claude touched get updated. Claude's
edits are written to disk normally, so tests and other tools see them right
away. Your own edits stay in the buffer until you save.
Requires tmux. The plugin uses your tmux session and window to find the right
Neovim instance when you have multiple running.

## Install

Add the plugin with lazy.nvim:

```lua
{
  'jtmkrueger/clmux.nvim',
  config = function()
    require('clmux').setup()
  end,
}
```

On first startup the plugin automatically installs a Claude Code
hook and registers itself. No manual setup required.

## What it does

When Claude Code uses Edit, Write, or MultiEdit on a file:

1. The hook detects which lines changed and finds your Neovim instance
2. Only the changed lines are spliced into your buffer (not a full reload)
3. The changed lines flash briefly so you can see what happened
4. The cursor jumps to the change (optional — see Configuration)

If the file isn't open in Neovim, nothing happens. If you're not in tmux,
the plugin quietly does nothing.

## Working alongside Claude

The plugin is designed for you to keep editing while Claude works. If you're
writing code on line 20 and Claude edits line 80, your unsaved work on line 20
is untouched. Claude's changes land on disk immediately, so Claude can move on
to other files or run tests without waiting for you to save.

Set `jump = false` if you don't want the cursor pulled away from where you're
working:

```lua
require('clmux').setup({
  jump = false,
})
```

The highlight still flashes on the changed lines so you know something
happened, but your cursor stays put.

## Configuration

All options and their defaults:

```lua
require('clmux').setup({
  jump = true,                    -- jump cursor to the changed lines
  highlight_duration = 3000,      -- ms the flash highlight stays visible
  highlight = {                   -- style of the flash highlight
    bg = "#5f3f6f",
    fg = "#e0d0f0",
    bold = true,
  },
  highlight_group = "ClmuxFlash", -- highlight group name
  auto_install = true,            -- install hook and register automatically
  discovery_dir = "~/.claude/nvim-servers",
})
```

Set `auto_install = false` if you prefer to manage the hook and settings
yourself. See `install.sh` for a manual install script.

## Requirements

- Neovim 0.9+
- tmux
- jq
- Claude Code CLI

## Multiple Neovim instances

Each Neovim instance registers itself by tmux session and window. When Claude
edits a file, the hook finds the Neovim instance in the same tmux window and
sends the update there. Other instances in other windows or sessions are
unaffected.

## Uninstall

Before removing the plugin from your lazy.nvim config:

```vim
:lua require('clmux').uninstall()
```

This removes the hook script, the `settings.json` entry, and the discovery
directory. Then remove the plugin from your config.

## How it works

```
Claude Code edits a file on disk
  → PostToolUse hook fires
  → hook parses the tool JSON, finds which lines changed
  → looks up the Neovim socket via ~/.claude/nvim-servers/<session>:<window>.json
  → sends an RPC call to Neovim
  → plugin splices the changed lines into the buffer and flashes the highlight
```
