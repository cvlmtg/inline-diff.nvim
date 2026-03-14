local diff = require("inline-diff.diff")

describe("_myers_matched", function()
  it("marks the single common line in a substitution", function()
    -- old={"a","b","c"}, new={"a","x","c"}: prefix=1 ("a"), suffix=1 ("c"), middle old={"b"}, new={"x"}
    local old = { "a", "b", "c" }
    local new = { "a", "x", "c" }
    local old_m, new_m = diff._myers_matched(old, new, 1, 1, 3, 3, 1, 1)
    -- prefix "a" and suffix "c" matched; middle "b" vs "x" unmatched
    assert.is_true(old_m[1])  -- "a"
    assert.is_nil(old_m[2])   -- "b" unmatched
    assert.is_true(old_m[3])  -- "c"
    assert.is_true(new_m[1])
    assert.is_nil(new_m[2])
    assert.is_true(new_m[3])
  end)

  it("marks nothing in the middle for a pure deletion", function()
    -- old={"a","b","c"}, new={"a","c"}: prefix=1, suffix=1, middle old={"b"}, new={}
    local old = { "a", "b", "c" }
    local new = { "a", "c" }
    local om, nm = diff._myers_matched(old, new, 1, 1, 3, 2, 1, 0)
    assert.is_true(om[1])
    assert.is_nil(om[2])  -- "b" deleted
    assert.is_true(om[3])
    assert.is_true(nm[1])
    assert.is_true(nm[2])
  end)

  it("marks the LCS correctly across multiple changes", function()
    -- old={"a","b","c","d","e"}, new={"a","x","c","y","e"}: prefix=1, suffix=1, middle 3 vs 3
    local old = { "a", "b", "c", "d", "e" }
    local new = { "a", "x", "c", "y", "e" }
    local om, nm = diff._myers_matched(old, new, 1, 1, 5, 5, 3, 3)
    assert.is_true(om[1])   -- "a"
    assert.is_nil(om[2])    -- "b" changed
    assert.is_true(om[3])   -- "c" matched
    assert.is_nil(om[4])    -- "d" changed
    assert.is_true(om[5])   -- "e"
    assert.is_true(nm[1])
    assert.is_nil(nm[2])    -- "x" changed
    assert.is_true(nm[3])   -- "c" matched
    assert.is_nil(nm[4])    -- "y" changed
    assert.is_true(nm[5])
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

  it("handles duplicate lines without misattributing hunks", function()
    -- old: a b a c  →  new: a a c  (the "b" is the only deletion)
    local hunks = diff._diff_lines({ "a", "b", "a", "c" }, { "a", "a", "c" })
    assert.are.equal(1, #hunks)
    assert.are.equal(0, hunks[1].new_count)
    assert.are.same({ "b" }, hunks[1].old_lines)
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

  it("falls back to full-line diff for lines with more than 200 tokens", function()
    -- "x " tokenizes into 2 tokens; 101 repetitions = 202 tokens (> 200 guard)
    local old_line = string.rep("x ", 101)
    local new_line = string.rep("y ", 101)
    local old_segs, new_segs = diff._word_diff(old_line, new_line)
    assert.are.equal(1, #old_segs)
    assert.are.equal("del", old_segs[1].type)
    assert.are.equal(old_line, old_segs[1].text)
    assert.are.equal(1, #new_segs)
    assert.are.equal("add", new_segs[1].type)
    assert.are.equal(new_line, new_segs[1].text)
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

  it("does not split multi-byte UTF-8 characters across segment boundaries", function()
    -- "hello 世界" vs "hello 地球": only the CJK characters differ
    local old_line = "hello \xe4\xb8\x96\xe7\x95\x8c" -- 世界
    local new_line = "hello \xe5\x9c\xb0\xe7\x90\x83" -- 地球
    local old_segs, new_segs = diff._word_diff(old_line, new_line)

    -- Every segment text must equal string.sub(line, byte_start, byte_end)
    for _, seg in ipairs(old_segs) do
      assert.are.equal(seg.text, old_line:sub(seg.byte_start, seg.byte_end))
    end
    for _, seg in ipairs(new_segs) do
      assert.are.equal(seg.text, new_line:sub(seg.byte_start, seg.byte_end))
    end

    -- "hello " prefix must be marked equal (not changed)
    assert.are.equal("equal", old_segs[1].type)
    assert.are.equal("hello ", old_segs[1].text)
  end)

  it("handles lines containing only multi-byte characters", function()
    local old_line = "\xc3\xa9" -- é (2-byte)
    local new_line = "\xc3\xa0" -- à (2-byte)
    local old_segs, new_segs = diff._word_diff(old_line, new_line)

    -- Byte offsets must reconstruct the original lines
    for _, seg in ipairs(old_segs) do
      assert.are.equal(seg.text, old_line:sub(seg.byte_start, seg.byte_end))
    end
    for _, seg in ipairs(new_segs) do
      assert.are.equal(seg.text, new_line:sub(seg.byte_start, seg.byte_end))
    end
  end)
end)

describe("_tokenize", function()
  it("treats each multi-byte UTF-8 character as a single token", function()
    -- é = 0xC3 0xA9 (2 bytes); must be one token, not two
    local tokens = diff._tokenize("\xc3\xa9")
    assert.are.equal(1, #tokens)
    assert.are.equal("\xc3\xa9", tokens[1])
  end)

  it("treats each 3-byte CJK character as a single token", function()
    -- 中 = 0xE4 0xB8 0xAD (3 bytes)
    local tokens = diff._tokenize("\xe4\xb8\xad")
    assert.are.equal(1, #tokens)
    assert.are.equal("\xe4\xb8\xad", tokens[1])
  end)

  it("mixes ASCII words and multi-byte chars correctly", function()
    -- "hi é" -> {"hi", " ", "é"}
    local tokens = diff._tokenize("hi \xc3\xa9")
    assert.are.equal(3, #tokens)
    assert.are.equal("hi", tokens[1])
    assert.are.equal(" ", tokens[2])
    assert.are.equal("\xc3\xa9", tokens[3])
  end)
end)
