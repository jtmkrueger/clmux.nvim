describe("discovery", function()
  local clmux

  before_each(function()
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")

    -- Mock TMUX env so the guard in _register() passes
    vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"

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
    vim.env.TMUX = nil
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
