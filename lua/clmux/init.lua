-- lua/clmux/init.lua
local M = {}

M.config = {
  highlight_group = "ClmuxFlash",
  highlight_duration = 1500,
  discovery_dir = vim.fn.expand("~/.claude/nvim-servers"),
}

M._tmux_key = nil

local ns = vim.api.nvim_create_namespace("clmux_flash")

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

function M._flash(buf, start_line, end_line)
  local hl = vim.api.nvim_get_hl(0, { name = M.config.highlight_group })
  if vim.tbl_isempty(hl) then
    vim.api.nvim_set_hl(0, M.config.highlight_group, { link = "IncSearch" })
  end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for line = start_line, end_line do
    vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
      end_row = line - 1,
      end_col = 0,
      hl_group = M.config.highlight_group,
      hl_eol = true,
    })
  end

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end, M.config.highlight_duration)
end

function M.on_file_changed(file_path, start_line, end_line)
  start_line = start_line or 1
  end_line = end_line or start_line

  local abs_path = vim.fn.resolve(vim.fn.fnamemodify(file_path, ":p"))

  -- Find buffer for this file
  local target_buf = nil
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local buf_path = vim.fn.resolve(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p"))
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
    vim.cmd("edit!")
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

    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! zz")
    end)

    M._flash(target_buf, safe_line, safe_end)
  end
end

return M
