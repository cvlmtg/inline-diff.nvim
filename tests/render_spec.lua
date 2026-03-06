local render = require("inline-diff.render")

-- Helper: collect extmarks that carry virt_lines from a buffer+namespace.
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

describe("apply – pure deletion", function()
  local bufnr, ns

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    ns = vim.api.nvim_create_namespace("test-render-deletion")
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("first-line deletion: virt_line appears above line 0", function()
    -- git: @@ -1 +0,0 @@ → new_start=0 (0 lines before gap); show above row 0
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line2", "line3" })
    local hunk = {
      old_start = 1, old_count = 1,
      new_start = 0, new_count = 0,
      old_lines = { "line1" }, new_lines = {},
    }
    render.apply(bufnr, ns, { hunk })
    local marks = get_virt_marks(bufnr, ns)
    assert.are.equal(1, #marks, "expected exactly one virt_lines extmark")
    assert.are.equal(0, marks[1].row, "extmark should be on line 0")
    assert.is_true(marks[1].above, "virt_lines should be above line 0")
    assert.are.equal("line1", marks[1].text)
  end)

  -- git diff --unified=0 can emit either "+3,0" or "+2,0" for a last-line
  -- deletion depending on version; both must render the virt_line BELOW the
  -- last buffer line (not above it).
  it("last-line deletion: virt_line appears below last line", function()
    -- git: @@ -3 +2,0 @@ → new_start=2 (2 lines before gap); anchor=row 1, below
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2" })
    local hunk = {
      old_start = 3, old_count = 1,
      new_start = 2, new_count = 0,
      old_lines = { "line3" }, new_lines = {},
    }
    render.apply(bufnr, ns, { hunk })
    local marks = get_virt_marks(bufnr, ns)
    assert.are.equal(1, #marks, "expected exactly one virt_lines extmark")
    assert.are.equal(1, marks[1].row, "extmark should be on the last line (row 1)")
    assert.is_false(marks[1].above, "virt_lines should be below the last line")
    assert.are.equal("line3", marks[1].text)
  end)

  it("middle-line deletion: virt_line appears below the preceding line", function()
    -- git: @@ -2 +1,0 @@ → new_start=1 (1 line before gap); anchor=row 0, below
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line3" })
    local hunk = {
      old_start = 2, old_count = 1,
      new_start = 1, new_count = 0,
      old_lines = { "line2" }, new_lines = {},
    }
    render.apply(bufnr, ns, { hunk })
    local marks = get_virt_marks(bufnr, ns)
    assert.are.equal(1, #marks)
    assert.are.equal(0, marks[1].row, "extmark should be anchored to row 0 (line1)")
    assert.is_false(marks[1].above, "virt_line below row 0 renders between line1 and line3")
    assert.are.equal("line2", marks[1].text)
  end)
end)

describe("_build_old_line_chunks", function()
  it("returns full line as InlineDiffDelete when no segments", function()
    local chunks = render._build_old_line_chunks("hello world", nil)
    assert.are.same({ { "hello world", "InlineDiffDelete" } }, chunks)
  end)

  it("maps equal segments to InlineDiffDelete and del segments to InlineDiffWordDel", function()
    local segments = {
      { text = "hello ", type = "equal", byte_start = 1, byte_end = 6 },
      { text = "world", type = "del", byte_start = 7, byte_end = 11 },
    }
    local chunks = render._build_old_line_chunks("hello world", segments)
    assert.are.same({
      { "hello ", "InlineDiffDelete" },
      { "world", "InlineDiffWordDel" },
    }, chunks)
  end)
end)

describe("_build_new_line_highlights", function()
  it("returns empty table when no segments", function()
    local highlights = render._build_new_line_highlights(nil)
    assert.are.same({}, highlights)
  end)

  it("returns highlights only for add segments", function()
    local segments = {
      { text = "hello ", type = "equal", byte_start = 1, byte_end = 6 },
      { text = "world", type = "add", byte_start = 7, byte_end = 11 },
    }
    local highlights = render._build_new_line_highlights(segments)
    assert.are.equal(1, #highlights)
    assert.are.equal(6, highlights[1].col) -- 0-indexed
    assert.are.equal(11, highlights[1].end_col) -- exclusive
    assert.are.equal("InlineDiffWordAdd", highlights[1].hl_group)
  end)

  it("skips equal segments", function()
    local segments = {
      { text = "all equal", type = "equal", byte_start = 1, byte_end = 9 },
    }
    local highlights = render._build_new_line_highlights(segments)
    assert.are.same({}, highlights)
  end)
end)
