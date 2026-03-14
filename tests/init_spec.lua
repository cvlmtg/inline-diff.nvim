local M = require("inline-diff")
local state = require("inline-diff.state")

local function make_hunk(old_start, old_lines, new_start, new_lines)
  return {
    old_start = old_start,
    old_count = #old_lines,
    new_start = new_start,
    new_count = #new_lines,
    old_lines = old_lines,
    new_lines = new_lines,
  }
end

-- Initialise highlight groups once; safe in headless mode (fallback colors).
M.setup()

describe("enable / disable / toggle", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    pcall(M.disable, bufnr)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    state._bufs[bufnr] = nil
  end)

  -- enable ------------------------------------------------------------------

  it("enable marks buffer as enabled with default ref HEAD", function()
    M.enable(bufnr)
    local s = state._bufs[bufnr]
    assert.is_not_nil(s)
    assert.is_true(s.enabled)
    assert.are.equal("HEAD", s.ref)
  end)

  it("enable stores a custom ref", function()
    M.enable(bufnr, "HEAD~1")
    assert.are.equal("HEAD~1", state._bufs[bufnr].ref)
  end)

  it("enable with the same ref is a no-op (generation unchanged)", function()
    M.enable(bufnr, "main")
    local gen = state._bufs[bufnr].generation
    M.enable(bufnr, "main")
    assert.are.equal(gen, state._bufs[bufnr].generation)
  end)

  it("enable with a different ref resets cached ref content and prev_hunks", function()
    M.enable(bufnr, "HEAD")
    local s = state._bufs[bufnr]
    s.ref_lines = { "cached", "content" }
    s.ref_dirty = false
    s.prev_hunks = { { old_start = 1, old_count = 1, new_start = 1, new_count = 1, old_lines = {}, new_lines = {} } }
    M.enable(bufnr, "HEAD~1")
    assert.are.equal("HEAD~1", s.ref)
    assert.is_nil(s.ref_lines)
    assert.is_true(s.ref_dirty)
    assert.is_nil(s.prev_hunks)
  end)

  -- disable -----------------------------------------------------------------

  it("disable removes buffer state", function()
    M.enable(bufnr)
    M.disable(bufnr)
    assert.is_nil(state._bufs[bufnr])
  end)

  it("disable is a no-op when not enabled", function()
    M.disable(bufnr) -- must not error
    assert.is_nil(state._bufs[bufnr])
  end)

  -- toggle ------------------------------------------------------------------

  it("toggle enables when the buffer is not yet enabled", function()
    M.toggle(bufnr)
    local s = state._bufs[bufnr]
    assert.is_not_nil(s)
    assert.is_true(s.enabled)
  end)

  it("toggle disables when already enabled and no ref given", function()
    M.enable(bufnr)
    M.toggle(bufnr)
    assert.is_nil(state._bufs[bufnr])
  end)

  it("toggle with a ref always enables and never disables", function()
    M.enable(bufnr)
    M.toggle(bufnr, "HEAD~1")
    local s = state._bufs[bufnr]
    assert.is_not_nil(s)
    assert.is_true(s.enabled)
    assert.are.equal("HEAD~1", s.ref)
  end)
end)

describe("_hunks_equal", function()
  it("returns true for both nil", function()
    assert.is_true(M._hunks_equal(nil, nil))
  end)

  it("returns true for same reference", function()
    local h = { make_hunk(1, { "a" }, 1, { "b" }) }
    assert.is_true(M._hunks_equal(h, h))
  end)

  it("returns false when one is nil", function()
    local h = { make_hunk(1, { "a" }, 1, { "b" }) }
    assert.is_false(M._hunks_equal(h, nil))
    assert.is_false(M._hunks_equal(nil, h))
  end)

  it("returns true for equal empty arrays", function()
    assert.is_true(M._hunks_equal({}, {}))
  end)

  it("returns false for different lengths", function()
    local h1 = { make_hunk(1, { "a" }, 1, { "b" }) }
    assert.is_false(M._hunks_equal(h1, {}))
  end)

  it("returns true for identical hunks", function()
    local a = { make_hunk(1, { "old" }, 1, { "new" }) }
    local b = { make_hunk(1, { "old" }, 1, { "new" }) }
    assert.is_true(M._hunks_equal(a, b))
  end)

  it("returns false when a hunk field differs", function()
    local a = { make_hunk(1, { "old" }, 1, { "new" }) }
    local b = { make_hunk(2, { "old" }, 1, { "new" }) }  -- different old_start
    assert.is_false(M._hunks_equal(a, b))
  end)

  it("returns false when old_lines content differs", function()
    local a = { make_hunk(1, { "foo" }, 1, { "new" }) }
    local b = { make_hunk(1, { "bar" }, 1, { "new" }) }
    assert.is_false(M._hunks_equal(a, b))
  end)

  it("returns false when new_lines content differs", function()
    local a = { make_hunk(1, { "old" }, 1, { "foo" }) }
    local b = { make_hunk(1, { "old" }, 1, { "bar" }) }
    assert.is_false(M._hunks_equal(a, b))
  end)
end)
