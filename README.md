# clmux.nvim

Live buffer sync between Claude Code and Neovim. When Claude edits a file, your
buffer reloads, the cursor jumps to the changed line, and a brief highlight
flashes so you can see what changed.

Requires tmux — uses tmux session/window to discover the right Neovim instance
when multiple are running.

## How it works

```
Claude Code edits a file
  → PostToolUse hook fires
  → hook parses JSON, greps for changed line
  → discovers nvim via tmux session:window
  → sends RPC to nvim
  → buffer reloads, cursor jumps, highlight flashes
```

## Requirements

- Neovim 0.9+
- tmux
- jq
- Claude Code CLI

## Install

Add the plugin with lazy.nvim:

```lua
{
  'jkrueger/clmux.nvim',
  config = function()
    require('clmux').setup()
  end,
}
```

Or from a local checkout:

```lua
{
  dir = '~/Code/clmux.nvim',
  config = function()
    require('clmux').setup()
  end,
}
```

That's it. On first startup the plugin automatically:

1. Copies the hook script to `~/.claude/hooks/clmux-hook.sh`
2. Registers the PostToolUse hook in `~/.claude/settings.json`
3. Creates the discovery directory at `~/.claude/nvim-servers/`

You can verify it's working:

```bash
ls ~/.claude/nvim-servers/
# Should show <session>:<window>.json

cat ~/.claude/nvim-servers/*.json
# Should show {"socket":"/tmp/nvimXXXXXX/0","pid":12345}
```

## Configuration

```lua
require('clmux').setup({
  highlight_group = "ClmuxFlash",  -- highlight group for the flash
  highlight_duration = 1500,       -- ms before highlight fades
  discovery_dir = "~/.claude/nvim-servers",
  auto_install = true,             -- auto-install hook and register in settings
})
```

Set `auto_install = false` if you prefer to manage the hook and settings
yourself. See `install.sh` for a manual install script.

The `ClmuxFlash` highlight group defaults to linking to `IncSearch`. Override it
in your colorscheme if you want a different flash color:

```lua
vim.api.nvim_set_hl(0, "ClmuxFlash", { bg = "#4a3a5a" })
```

## Uninstall

Before removing the plugin from your lazy.nvim config, run:

```vim
:lua require('clmux').uninstall()
```

This removes the hook script, the settings.json entry, and the discovery
directory. Then remove the plugin spec from your config.

## Behavior

- **Visible buffer**: reloads from disk, jumps to changed line, flashes highlight
- **Hidden buffer**: silently reloads, no cursor change
- **File not open**: nothing happens
- **Not in tmux**: plugin skips registration, hook exits silently
- **Multiple nvim instances**: each registers by tmux session:window, hook finds
  the one in the same window as Claude
