-- Integration tests: run compute_hunks against real git output, then apply
-- the hunks to a buffer and check the resulting extmarks.
-- This catches issues caused by git version differences in hunk header format.

local diff = require("inline-diff.diff")
local render = require("inline-diff.render")

local function get_virt_marks(bufnr, ns)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local result = {}
  for _, mark in ipairs(marks) do
    local opts = mark[4]
    if opts.virt_lines then
      table.insert(result, {
        row = mark[2],
        above = opts.virt_lines_above == true,
        text = opts.virt_lines[1][1][1],
      })
    end
  end
  return result
end

local function run_pipeline(old_lines, new_lines, callback)
  diff.compute_hunks(old_lines, new_lines, function(hunks, err)
    callback(hunks, err)
  end)
end

describe("pipeline – pure deletion", function()
  local bufnr, ns

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    ns = vim.api.nvim_create_namespace("test-pipeline")
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("first-line deletion: virt_line appears above line 0", function()
    local old_lines = { "line1", "line2", "line3" }
    local new_lines = { "line2", "line3" }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

    local hunks, err
    run_pipeline(old_lines, new_lines, function(h, e) hunks = h; err = e end)
    vim.wait(2000, function() return hunks ~= nil or err ~= nil end)

    assert.is_nil(err, "compute_hunks returned an error: " .. tostring(err))
    assert.are.equal(1, #hunks, "expected 1 hunk")
    assert.are.equal(0, hunks[1].new_count)

    render.apply(bufnr, ns, hunks)

    local marks = get_virt_marks(bufnr, ns)
    assert.are.equal(1, #marks, "expected exactly one virt_lines extmark")
    assert.are.equal(0, marks[1].row, "extmark should be anchored to line 0")
    assert.is_true(marks[1].above, "virt_line should be above line 0")
    assert.are.equal("line1", marks[1].text)
  end)

  it("last-line deletion: virt_line appears below the last line", function()
    local old_lines = { "line1", "line2", "line3" }
    local new_lines = { "line1", "line2" }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

    local hunks, err
    run_pipeline(old_lines, new_lines, function(h, e) hunks = h; err = e end)
    vim.wait(2000, function() return hunks ~= nil or err ~= nil end)

    assert.is_nil(err)
    assert.are.equal(1, #hunks)
    assert.are.equal(0, hunks[1].new_count)

    -- Print what git actually produced so we can see the new_start value
    -- in case of failure.
    local h = hunks[1]
    local info = string.format("old_start=%d new_start=%d", h.old_start, h.new_start)

    render.apply(bufnr, ns, hunks)

    local marks = get_virt_marks(bufnr, ns)
    assert.are.equal(1, #marks, "expected exactly one virt_lines extmark (" .. info .. ")")
    assert.are.equal(1, marks[1].row, "extmark should be anchored to the last line (" .. info .. ")")
    assert.is_false(marks[1].above, "virt_line should be below the last line (" .. info .. ")")
    assert.are.equal("line3", marks[1].text)
  end)

  it("modified line: old content appears as virt_line above the changed line", function()
    local old_lines = { "line1", "foo", "line3" }
    local new_lines = { "line1", "bar", "line3" }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

    local hunks, err
    run_pipeline(old_lines, new_lines, function(h, e) hunks = h; err = e end)

    assert.is_nil(err)
    assert.are.equal(1, #hunks)
    assert.are.equal(1, hunks[1].old_count)
    assert.are.equal(1, hunks[1].new_count)

    render.apply(bufnr, ns, hunks)

    local marks = get_virt_marks(bufnr, ns)
    assert.are.equal(1, #marks)
    assert.are.equal(1, marks[1].row)   -- 0-indexed row 1 = "bar"
    assert.is_true(marks[1].above)
    assert.are.equal("foo", marks[1].text)
  end)

  it("middle-line deletion: virt_line appears between the surrounding lines", function()
    local old_lines = { "line1", "line2", "line3" }
    local new_lines = { "line1", "line3" }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

    local hunks, err
    run_pipeline(old_lines, new_lines, function(h, e) hunks = h; err = e end)
    vim.wait(2000, function() return hunks ~= nil or err ~= nil end)

    assert.is_nil(err)
    assert.are.equal(1, #hunks)
    assert.are.equal(0, hunks[1].new_count)

    render.apply(bufnr, ns, hunks)

    local marks = get_virt_marks(bufnr, ns)
    assert.are.equal(1, #marks)
    -- git sets new_start=1 (1 line before the gap); we show below row 0 (line1),
    -- which renders between line1 and line3.
    assert.are.equal(0, marks[1].row, "extmark should be anchored to row 0 (line1)")
    assert.is_false(marks[1].above, "virt_line should be below row 0")
    assert.are.equal("line2", marks[1].text)
  end)
end)
