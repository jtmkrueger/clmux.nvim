describe("on_file_changed", function()
  local clmux
  local tmpfile

  before_each(function()
    package.loaded["clmux"] = nil
    clmux = require("clmux")
    clmux.setup({ discovery_dir = vim.fn.tempname(), auto_install = false })

    tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "line1", "line2", "line3", "line4", "line5" }, tmpfile)
    vim.cmd("edit " .. tmpfile)
  end)

  after_each(function()
    vim.cmd("bdelete!")
    vim.fn.delete(tmpfile)
  end)

  it("reloads buffer when file changes on disk", function()
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
    clmux.on_file_changed(otherfile, 1, 1)
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert.equals(1, cursor[1])
    vim.fn.delete(otherfile)
  end)
end)
