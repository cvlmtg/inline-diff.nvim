local diff = require("inline-diff.diff")

describe("_parse_diff", function()
  it("parses a single hunk with additions and deletions", function()
    local raw = table.concat({
      "diff --git a/tmp1 b/tmp2",
      "index 1234567..abcdefg 100644",
      "--- a/tmp1",
      "+++ b/tmp2",
      "@@ -1,2 +1,2 @@",
      "-old line 1",
      "-old line 2",
      "+new line 1",
      "+new line 2",
    }, "\n")

    local hunks = diff._parse_diff(raw)
    assert.are.equal(1, #hunks)
    assert.are.equal(1, hunks[1].old_start)
    assert.are.equal(2, hunks[1].old_count)
    assert.are.equal(1, hunks[1].new_start)
    assert.are.equal(2, hunks[1].new_count)
    assert.are.same({ "old line 1", "old line 2" }, hunks[1].old_lines)
    assert.are.same({ "new line 1", "new line 2" }, hunks[1].new_lines)
  end)

  it("parses pure addition (old_count=0)", function()
    local raw = table.concat({
      "diff --git a/tmp1 b/tmp2",
      "--- a/tmp1",
      "+++ b/tmp2",
      "@@ -1,0 +2,3 @@",
      "+added 1",
      "+added 2",
      "+added 3",
    }, "\n")

    local hunks = diff._parse_diff(raw)
    assert.are.equal(1, #hunks)
    assert.are.equal(0, hunks[1].old_count)
    assert.are.equal(3, hunks[1].new_count)
    assert.are.equal(2, hunks[1].new_start)
    assert.are.same({}, hunks[1].old_lines)
    assert.are.same({ "added 1", "added 2", "added 3" }, hunks[1].new_lines)
  end)

  it("parses pure deletion (new_count=0)", function()
    local raw = table.concat({
      "diff --git a/tmp1 b/tmp2",
      "--- a/tmp1",
      "+++ b/tmp2",
      "@@ -2,3 +1,0 @@",
      "-deleted 1",
      "-deleted 2",
      "-deleted 3",
    }, "\n")

    local hunks = diff._parse_diff(raw)
    assert.are.equal(1, #hunks)
    assert.are.equal(3, hunks[1].old_count)
    assert.are.equal(0, hunks[1].new_count)
    assert.are.same({ "deleted 1", "deleted 2", "deleted 3" }, hunks[1].old_lines)
  end)

  it("parses single-line hunk without count", function()
    local raw = table.concat({
      "diff --git a/tmp1 b/tmp2",
      "--- a/tmp1",
      "+++ b/tmp2",
      "@@ -5 +5 @@",
      "-old",
      "+new",
    }, "\n")

    local hunks = diff._parse_diff(raw)
    assert.are.equal(1, #hunks)
    assert.are.equal(5, hunks[1].old_start)
    assert.are.equal(1, hunks[1].old_count)
    assert.are.equal(5, hunks[1].new_start)
    assert.are.equal(1, hunks[1].new_count)
  end)

  it("parses multiple hunks", function()
    local raw = table.concat({
      "diff --git a/tmp1 b/tmp2",
      "--- a/tmp1",
      "+++ b/tmp2",
      "@@ -1 +1 @@",
      "-a",
      "+b",
      "@@ -5,2 +5,3 @@",
      "-c",
      "-d",
      "+e",
      "+f",
      "+g",
    }, "\n")

    local hunks = diff._parse_diff(raw)
    assert.are.equal(2, #hunks)
    assert.are.same({ "a" }, hunks[1].old_lines)
    assert.are.same({ "b" }, hunks[1].new_lines)
    assert.are.same({ "c", "d" }, hunks[2].old_lines)
    assert.are.same({ "e", "f", "g" }, hunks[2].new_lines)
  end)

  it("skips backslash lines", function()
    local raw = table.concat({
      "diff --git a/tmp1 b/tmp2",
      "--- a/tmp1",
      "+++ b/tmp2",
      "@@ -1 +1 @@",
      "-no newline",
      "\\ No newline at end of file",
      "+has newline",
    }, "\n")

    local hunks = diff._parse_diff(raw)
    assert.are.equal(1, #hunks)
    assert.are.same({ "no newline" }, hunks[1].old_lines)
    assert.are.same({ "has newline" }, hunks[1].new_lines)
  end)
end)

describe("_lcs", function()
  it("finds common subsequence", function()
    local a = { "a", "b", "c", "d" }
    local b = { "a", "x", "c", "d" }
    local ma, mb = diff._lcs(a, b)
    assert.is_true(ma[1])
    assert.is_nil(ma[2])
    assert.is_true(ma[3])
    assert.is_true(ma[4])
    assert.is_true(mb[1])
    assert.is_nil(mb[2])
    assert.is_true(mb[3])
    assert.is_true(mb[4])
  end)

  it("handles empty arrays", function()
    local ma, mb = diff._lcs({}, { "a" })
    assert.are.same({}, ma)
    assert.are.same({}, mb)
  end)

  it("handles identical arrays", function()
    local a = { "x", "y" }
    local ma, mb = diff._lcs(a, a)
    assert.is_true(ma[1])
    assert.is_true(ma[2])
    assert.is_true(mb[1])
    assert.is_true(mb[2])
  end)
end)

describe("_diff_lines", function()
  it("returns empty for identical content", function()
    local hunks = diff._diff_lines({ "a", "b", "c" }, { "a", "b", "c" })
    assert.are.same({}, hunks)
  end)

  it("detects a pure addition", function()
    local hunks = diff._diff_lines({ "a", "c" }, { "a", "b", "c" })
    assert.are.equal(1, #hunks)
    assert.are.equal(0, hunks[1].old_count)
    assert.are.equal(1, hunks[1].new_count)
    assert.are.same({ "b" }, hunks[1].new_lines)
  end)

  it("detects a pure deletion", function()
    local hunks = diff._diff_lines({ "a", "b", "c" }, { "a", "c" })
    assert.are.equal(1, #hunks)
    assert.are.equal(1, hunks[1].old_count)
    assert.are.equal(0, hunks[1].new_count)
    assert.are.same({ "b" }, hunks[1].old_lines)
  end)

  it("detects a modification", function()
    local hunks = diff._diff_lines({ "a", "b", "c" }, { "a", "x", "c" })
    assert.are.equal(1, #hunks)
    assert.are.equal(1, hunks[1].old_count)
    assert.are.equal(1, hunks[1].new_count)
    assert.are.same({ "b" }, hunks[1].old_lines)
    assert.are.same({ "x" }, hunks[1].new_lines)
  end)

  it("detects multiple hunks", function()
    local hunks = diff._diff_lines({ "a", "b", "c", "d", "e" }, { "a", "x", "c", "y", "e" })
    assert.are.equal(2, #hunks)
    assert.are.same({ "b" }, hunks[1].old_lines)
    assert.are.same({ "x" }, hunks[1].new_lines)
    assert.are.same({ "d" }, hunks[2].old_lines)
    assert.are.same({ "y" }, hunks[2].new_lines)
  end)

  it("handles empty old (all additions)", function()
    local hunks = diff._diff_lines({}, { "a", "b" })
    assert.are.equal(1, #hunks)
    assert.are.equal(0, hunks[1].old_count)
    assert.are.equal(2, hunks[1].new_count)
  end)

  it("handles empty new (all deletions)", function()
    local hunks = diff._diff_lines({ "a", "b" }, {})
    assert.are.equal(1, #hunks)
    assert.are.equal(2, hunks[1].old_count)
    assert.are.equal(0, hunks[1].new_count)
  end)

  it("handles first-line deletion", function()
    local hunks = diff._diff_lines({ "x", "a", "b" }, { "a", "b" })
    assert.are.equal(1, #hunks)
    assert.are.equal(1, hunks[1].old_count)
    assert.are.equal(0, hunks[1].new_count)
    assert.are.same({ "x" }, hunks[1].old_lines)
    -- new_start should be 0 for deletion before the first line
    assert.are.equal(0, hunks[1].new_start)
  end)

  it("handles last-line deletion", function()
    local hunks = diff._diff_lines({ "a", "b", "x" }, { "a", "b" })
    assert.are.equal(1, #hunks)
    assert.are.equal(1, hunks[1].old_count)
    assert.are.equal(0, hunks[1].new_count)
    assert.are.same({ "x" }, hunks[1].old_lines)
    assert.are.equal(2, hunks[1].new_start)
  end)
end)

describe("_word_diff", function()
  it("detects changed words", function()
    local old_segs, new_segs = diff._word_diff("font-size: 12px;", "font-size: 4em;")

    -- Check old segments contain a deletion
    local found_del = false
    for _, seg in ipairs(old_segs) do
      if seg.type == "del" and seg.text:find("12px") then
        found_del = true
      end
    end
    assert.is_true(found_del, "expected to find deleted '12px'")

    -- Check new segments contain an addition
    local found_add = false
    for _, seg in ipairs(new_segs) do
      if seg.type == "add" and seg.text:find("4em") then
        found_add = true
      end
    end
    assert.is_true(found_add, "expected to find added '4em'")
  end)

  it("returns all-equal for identical lines", function()
    local old_segs, new_segs = diff._word_diff("hello world", "hello world")
    for _, seg in ipairs(old_segs) do
      assert.are.equal("equal", seg.type)
    end
    for _, seg in ipairs(new_segs) do
      assert.are.equal("equal", seg.type)
    end
  end)

  it("handles completely different lines", function()
    local old_segs, new_segs = diff._word_diff("aaa bbb", "xxx yyy")
    local has_del = false
    local has_add = false
    for _, seg in ipairs(old_segs) do
      if seg.type == "del" then has_del = true end
    end
    for _, seg in ipairs(new_segs) do
      if seg.type == "add" then has_add = true end
    end
    assert.is_true(has_del)
    assert.is_true(has_add)
  end)

  it("provides correct byte offsets", function()
    local old_segs, _ = diff._word_diff("aaa bbb ccc", "aaa xxx ccc")
    -- Reconstruct the line from segments
    local reconstructed = ""
    for _, seg in ipairs(old_segs) do
      reconstructed = reconstructed .. seg.text
    end
    assert.are.equal("aaa bbb ccc", reconstructed)

    -- Verify byte_start/byte_end are consistent
    local pos = 1
    for _, seg in ipairs(old_segs) do
      assert.are.equal(pos, seg.byte_start)
      assert.are.equal(pos + #seg.text - 1, seg.byte_end)
      pos = seg.byte_end + 1
    end
  end)
end)
