-- lua/clmux/init.lua
local M = {}

M.config = {
  highlight_group = "ClmuxFlash",
  highlight_duration = 3000,
  discovery_dir = vim.fn.expand("~/.claude/nvim-servers"),
  auto_install = true,
}

M._tmux_key = nil

local ns = vim.api.nvim_create_namespace("clmux_flash")

-- Find this plugin's root directory (parent of lua/)
local function get_plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2) -- remove leading @
  -- source is .../lua/clmux/init.lua, we want ...
  return vim.fn.fnamemodify(source, ":h:h:h")
end

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

local function ensure_hook_installed()
  local plugin_root = get_plugin_root()
  local hook_src = plugin_root .. "/hooks/clmux-hook.sh"
  local hook_dst = vim.fn.expand("~/.claude/hooks/clmux-hook.sh")

  if vim.fn.filereadable(hook_src) == 0 then
    return
  end

  -- Copy hook if missing or outdated
  vim.fn.mkdir(vim.fn.fnamemodify(hook_dst, ":h"), "p")
  local src_contents = vim.fn.readfile(hook_src)
  local dst_contents = vim.fn.filereadable(hook_dst) == 1
    and vim.fn.readfile(hook_dst) or {}

  if not vim.deep_equal(src_contents, dst_contents) then
    vim.fn.writefile(src_contents, hook_dst)
    vim.fn.setfperm(hook_dst, "rwxr-xr-x")
  end
end

local function read_claude_settings()
  local settings_path = vim.fn.expand("~/.claude/settings.json")
  if vim.fn.filereadable(settings_path) == 1 then
    local content = table.concat(vim.fn.readfile(settings_path), "\n")
    local ok, decoded = pcall(vim.fn.json_decode, content)
    if ok and type(decoded) == "table" then
      return decoded
    end
  end
  return {}
end

local function write_claude_settings(settings)
  local settings_path = vim.fn.expand("~/.claude/settings.json")
  vim.fn.mkdir(vim.fn.fnamemodify(settings_path, ":h"), "p")
  local json = vim.fn.json_encode(settings)
  vim.fn.writefile({ json }, settings_path)
end

local function has_clmux_hook(settings)
  local post_tool_use = (settings.hooks or {}).PostToolUse or {}
  for _, entry in ipairs(post_tool_use) do
    for _, hook in ipairs(entry.hooks or {}) do
      if type(hook.command) == "string" and hook.command:match("clmux") then
        return true
      end
    end
  end
  return false
end

local function ensure_hook_registered()
  local settings = read_claude_settings()

  if has_clmux_hook(settings) then
    return
  end

  local hook_cmd = vim.fn.expand("~/.claude/hooks/clmux-hook.sh")

  if not settings.hooks then
    settings.hooks = {}
  end
  if not settings.hooks.PostToolUse then
    settings.hooks.PostToolUse = {}
  end

  table.insert(settings.hooks.PostToolUse, {
    matcher = "Edit|Write|MultiEdit",
    hooks = {
      { type = "command", command = hook_cmd },
    },
  })

  write_claude_settings(settings)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  if M.config.auto_install then
    ensure_hook_installed()
    ensure_hook_registered()
  end

  M._register()

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M._unregister()
    end,
  })
end

function M._flash(buf, start_line, end_line)
  vim.api.nvim_set_hl(0, M.config.highlight_group, { bg = "#5f3f6f", fg = "#e0d0f0", bold = true })

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for line = start_line, end_line do
    vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
      line_hl_group = M.config.highlight_group,
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

function M.uninstall()
  -- Remove hook script
  local hook_path = vim.fn.expand("~/.claude/hooks/clmux-hook.sh")
  if vim.fn.filereadable(hook_path) == 1 then
    vim.fn.delete(hook_path)
    vim.notify("clmux: removed " .. hook_path)
  end

  -- Remove hook from settings.json
  local settings = read_claude_settings()
  if has_clmux_hook(settings) then
    local post_tool_use = settings.hooks.PostToolUse
    local filtered = {}
    for _, entry in ipairs(post_tool_use) do
      local dominated_by_clmux = false
      for _, hook in ipairs(entry.hooks or {}) do
        if type(hook.command) == "string" and hook.command:match("clmux") then
          dominated_by_clmux = true
          break
        end
      end
      if not dominated_by_clmux then
        table.insert(filtered, entry)
      end
    end
    settings.hooks.PostToolUse = filtered
    if #filtered == 0 then
      settings.hooks.PostToolUse = nil
    end
    if vim.tbl_isempty(settings.hooks) then
      settings.hooks = nil
    end
    write_claude_settings(settings)
    vim.notify("clmux: removed hook from ~/.claude/settings.json")
  end

  -- Remove discovery files
  M._unregister()
  local discovery_dir = M.config.discovery_dir
  if vim.fn.isdirectory(discovery_dir) == 1 then
    vim.fn.delete(discovery_dir, "rf")
    vim.notify("clmux: removed " .. discovery_dir)
  end

  vim.notify("clmux: uninstall complete — remove the plugin from your lazy.nvim config")
end

return M
