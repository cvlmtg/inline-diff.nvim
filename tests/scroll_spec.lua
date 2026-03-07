local init = require("inline-diff")
local state = require("inline-diff.state")

init.setup()

local function make_win(bufnr, height)
  return vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = 60,
    height = height,
    row = 0,
    col = 0,
    style = "minimal",
  })
end

describe("_adjust_scroll – bottom virt_lines", function()
  local bufnr, ns, winid

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    ns = vim.api.nvim_create_namespace("test-adj-scroll")
    winid = make_win(bufnr, 5)
    vim.api.nvim_set_current_win(winid)
    state._bufs[bufnr] = state.get(bufnr)
    state._bufs[bufnr].has_bot_virt = true
    state._bufs[bufnr].has_top_virt = false
  end)

  after_each(function()
    pcall(vim.api.nvim_win_close, winid, true)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    state._bufs[bufnr] = nil
  end)

  local function run(n_lines, n_deleted)
    local lines = {}
    for i = 1, n_lines do lines[i] = "line" .. i end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local virt = {}
    for i = 1, n_deleted do
      virt[i] = { { "del" .. i, "InlineDiffDelete" } }
    end
    vim.api.nvim_buf_set_extmark(bufnr, ns, n_lines - 1, 0, {
      virt_lines = virt,
      virt_lines_above = false,
    })

    -- Position: last buffer line at the very bottom of the 5-row window
    vim.api.nvim_win_set_cursor(winid, { n_lines, 0 })
    vim.fn.winrestview({ topline = 1, topfill = 0 })

    init._adjust_scroll(bufnr, ns)
  end

  -- Instead of re-using the same formula as the code under test, verify by
  -- checking topline directly.  After scrolling, the last buffer line (1-indexed
  -- buf_line_count) must be high enough in the window for all n_deleted rows to
  -- fit below it:
  --   (buf_line_count - topline) + 1 + n_deleted <= win_height
  --   ⟹  topline >= buf_line_count + n_deleted - win_height + 1
  -- (This assumes no line wrapping, which holds for our "line1".."line5" content.)
  local function check(n_lines, n_deleted, win_h)
    local view = vim.api.nvim_win_call(winid, vim.fn.winsaveview)
    local min_topline = n_lines + n_deleted - win_h + 1
    assert.is_true(
      view.topline >= min_topline,
      string.format(
        "topline=%d but need >=%d so that %d virt_lines fit in %d-row window below last buffer line",
        view.topline, min_topline, n_deleted, win_h
      )
    )
  end

  it("reveals all 3 deleted virt_lines (buffer fits in window)", function()
    run(5, 3)
    check(5, 3, 5)
  end)

  it("reveals all 3 deleted virt_lines (buffer larger than window)", function()
    -- Buffer has 10 lines but window is only 5 rows tall.  The user scrolls to
    -- the bottom (last line at row 4) then _adjust_scroll should scroll enough
    -- to expose all 3 deleted virt_lines.
    local n_lines, n_deleted, win_h = 10, 3, 5
    local lines = {}
    for i = 1, n_lines do lines[i] = "line" .. i end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local virt = {}
    for i = 1, n_deleted do virt[i] = { { "del" .. i, "InlineDiffDelete" } } end
    vim.api.nvim_buf_set_extmark(bufnr, ns, n_lines - 1, 0, {
      virt_lines = virt,
      virt_lines_above = false,
    })

    -- Position: last buffer line at the very bottom of the 5-row window
    vim.api.nvim_win_set_cursor(winid, { n_lines, 0 })
    vim.fn.winrestview({ topline = n_lines - win_h + 1, topfill = 0 })

    init._adjust_scroll(bufnr, ns)
    check(n_lines, n_deleted, win_h)
  end)

  it("reveals a single deleted virt_line below the last buffer line", function()
    run(5, 1)
    check(5, 1, 5)
  end)

  it("reveals all 3 deleted virt_lines when the last buffer line wraps", function()
    -- Use a narrow window (width=10) so a 12-char line wraps to 2 visual rows.
    -- _adjust_scroll must account for the extra visual row, otherwise it scrolls
    -- 1 line short and only 2 of 3 virt_lines are visible.
    pcall(vim.api.nvim_win_close, winid, true)
    winid = vim.api.nvim_open_win(bufnr, true, {
      relative = "editor",
      width = 10,
      height = 5,
      row = 0,
      col = 0,
      style = "minimal",
    })
    vim.api.nvim_set_current_win(winid)

    local n_lines, n_deleted, win_h = 4, 3, 5
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false,
      { "line1", "line2", "line3", "123456789012" })  -- last line: 12 chars → wraps

    local last_h = vim.api.nvim_win_text_height(winid, { start_row = 3, end_row = 3 })
    assert.is_true(last_h.all >= 2, "expected last line to wrap to >= 2 visual rows in a 10-char window")

    local virt = {}
    for i = 1, n_deleted do virt[i] = { { "del" .. i, "InlineDiffDelete" } } end
    vim.api.nvim_buf_set_extmark(bufnr, ns, n_lines - 1, 0, {
      virt_lines = virt,
      virt_lines_above = false,
    })

    state._bufs[bufnr].has_bot_virt = true
    vim.api.nvim_win_set_cursor(winid, { n_lines, 0 })
    vim.fn.winrestview({ topline = 2, topfill = 0 })  -- last line visible at bottom

    init._adjust_scroll(bufnr, ns)

    -- After adjustment all n_deleted virt_lines must fit below the last buffer
    -- line (which takes last_line_visual_height rows due to wrapping).
    -- The minimum required topline is:
    --   n_lines + n_deleted + last_line_visual_height - win_h
    local view = vim.fn.winsaveview()
    local min_topline = n_lines + n_deleted + last_h.all - win_h
    assert.is_true(
      view.topline >= min_topline,
      string.format(
        "topline=%d but need >=%d (last line takes %d visual rows, need %d virt_lines in %d-row window)",
        view.topline, min_topline, last_h.all, n_deleted, win_h
      )
    )
  end)
end)
