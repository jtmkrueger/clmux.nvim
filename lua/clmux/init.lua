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
