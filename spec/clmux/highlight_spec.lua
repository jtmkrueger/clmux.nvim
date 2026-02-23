describe("flash highlight", function()
  local clmux
  local tmpfile

  before_each(function()
    package.loaded["clmux"] = nil
    clmux = require("clmux")
    clmux.setup({
      discovery_dir = vim.fn.tempname(),
      highlight_duration = 100,
      auto_install = false,
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

    vim.wait(200, function() return false end)

    local ns = vim.api.nvim_create_namespace("clmux_flash")
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    assert.equals(0, #marks)
  end)
end)
