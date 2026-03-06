local render = require("inline-diff.render")

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
