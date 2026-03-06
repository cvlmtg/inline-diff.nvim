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
        count = #opts.virt_lines,
        text = opts.virt_lines[1][1][1],
      })
    end
  end
  return result
end

-- Helper: collect extmarks that carry an hl_group.
local function get_hl_marks(bufnr, ns)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local result = {}
  for _, mark in ipairs(marks) do
    if mark[4].hl_group then
      result[#result + 1] = { row = mark[2], hl_group = mark[4].hl_group }
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

describe("apply – changed and multi-line hunks", function()
  local bufnr, ns

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    ns = vim.api.nvim_create_namespace("test-render-changed")
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("changed line: old content appears as virt_line above, new line highlighted", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "bar" })
    local hunk = {
      old_start = 1, old_count = 1,
      new_start = 1, new_count = 1,
      old_lines = { "foo" }, new_lines = { "bar" },
    }
    render.apply(bufnr, ns, { hunk })

    local virt = get_virt_marks(bufnr, ns)
    assert.are.equal(1, #virt)
    assert.are.equal(0, virt[1].row)
    assert.is_true(virt[1].above)
    assert.are.equal("foo", virt[1].text)

    local hls = get_hl_marks(bufnr, ns)
    local groups = {}
    for _, h in ipairs(hls) do groups[h.hl_group] = true end
    assert.is_true(groups["InlineDiffAdd"], "expected InlineDiffAdd on the new line")
    assert.is_true(groups["InlineDiffWordAdd"], "expected InlineDiffWordAdd for changed word")
  end)

  it("multiple deleted lines all appear in one virt_lines block", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep" })
    local hunk = {
      old_start = 1, old_count = 3,
      new_start = 1, new_count = 0,
      old_lines = { "del1", "del2", "del3" }, new_lines = {},
    }
    render.apply(bufnr, ns, { hunk })

    local virt = get_virt_marks(bufnr, ns)
    assert.are.equal(1, #virt)
    assert.are.equal(3, virt[1].count)
  end)

  it("excess old lines: extra deletions rendered as virt_lines after paired region", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "new1" })
    -- 3 old lines paired against 1 new line → 1 paired, 2 excess old
    local hunk = {
      old_start = 1, old_count = 3,
      new_start = 1, new_count = 1,
      old_lines = { "old1", "old2", "old3" }, new_lines = { "new1" },
    }
    render.apply(bufnr, ns, { hunk })

    local virt = get_virt_marks(bufnr, ns)
    -- One virt_line above for the paired old1, one below with 2 entries for old2+old3
    assert.are.equal(2, #virt)
    local extra = nil
    for _, m in ipairs(virt) do
      if not m.above then extra = m end
    end
    assert.is_not_nil(extra, "expected a non-above virt_lines mark for excess old lines")
    assert.are.equal(2, extra.count)
  end)

  it("excess new lines: extra additions are all highlighted", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "new1", "new2", "new3" })
    -- 1 old line paired against 3 new lines → 1 paired, 2 excess new
    local hunk = {
      old_start = 1, old_count = 1,
      new_start = 1, new_count = 3,
      old_lines = { "old1" }, new_lines = { "new1", "new2", "new3" },
    }
    render.apply(bufnr, ns, { hunk })

    local hls = get_hl_marks(bufnr, ns)
    local add_rows = {}
    for _, h in ipairs(hls) do
      if h.hl_group == "InlineDiffAdd" then add_rows[h.row] = true end
    end
    assert.is_true(add_rows[0], "row 0 (new1) should have InlineDiffAdd")
    assert.is_true(add_rows[1], "row 1 (new2) should have InlineDiffAdd")
    assert.is_true(add_rows[2], "row 2 (new3) should have InlineDiffAdd")
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
