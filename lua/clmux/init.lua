-- lua/clmux/init.lua
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
