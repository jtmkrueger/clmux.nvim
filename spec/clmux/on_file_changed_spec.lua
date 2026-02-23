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

  it("updates buffer when file changes on disk", function()
    vim.fn.writefile({ "line1", "CHANGED", "line3", "line4", "line5" }, tmpfile)
    clmux.on_file_changed(tmpfile, 2, 2)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.equals("CHANGED", lines[2])
  end)

  it("jumps cursor to changed line", function()
    vim.fn.writefile({ "line1", "CHANGED", "line3", "line4", "line5" }, tmpfile)
    clmux.on_file_changed(tmpfile, 2, 2)
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert.equals(2, cursor[1])
  end)

  it("preserves unsaved edits outside the changed region", function()
    -- User edits line 1 in the buffer (unsaved)
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { "user_edit" })

    -- Claude changes line 5 on disk
    vim.fn.writefile({ "line1", "line2", "line3", "line4", "CHANGED" }, tmpfile)
    clmux.on_file_changed(tmpfile, 5, 5)

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    -- User's edit at the top is preserved (outside diff region)
    assert.equals("user_edit", lines[1])
    -- Claude's edit at the bottom is applied
    assert.equals("CHANGED", lines[5])
  end)

  it("handles inserted lines", function()
    vim.fn.writefile({ "line1", "new_a", "new_b", "line2", "line3", "line4", "line5" }, tmpfile)
    clmux.on_file_changed(tmpfile, 2, 3)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.equals(7, #lines)
    assert.equals("new_a", lines[2])
    assert.equals("new_b", lines[3])
    assert.equals("line2", lines[4])
  end)

  it("handles deleted lines", function()
    vim.fn.writefile({ "line1", "line4", "line5" }, tmpfile)
    clmux.on_file_changed(tmpfile, 2, 2)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.equals(3, #lines)
    assert.equals("line4", lines[2])
  end)

  it("does nothing if file has no differences", function()
    -- File unchanged, should be a no-op
    clmux.on_file_changed(tmpfile, 1, 1)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.equals(5, #lines)
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
