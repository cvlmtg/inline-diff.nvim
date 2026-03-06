local M = require("inline-diff")
local state = require("inline-diff.state")

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

  it("enable with a different ref resets cached ref content", function()
    M.enable(bufnr, "HEAD")
    local s = state._bufs[bufnr]
    s.ref_lines = { "cached", "content" }
    s.ref_dirty = false
    M.enable(bufnr, "HEAD~1")
    assert.are.equal("HEAD~1", s.ref)
    assert.is_nil(s.ref_lines)
    assert.is_true(s.ref_dirty)
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
