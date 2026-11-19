local M = require("inline-diff")
local state = require("inline-diff.state")
local diff_mod = require("inline-diff.diff")

if vim.fn.exists(":InlineDiffSetRef") == 0 then
  vim.cmd("runtime plugin/inline-diff.lua")
end

M.setup()

describe("default ref", function()
  local bufs
  local orig_get_ref_content
  local orig_compute_hunks

  local function new_buf()
    local b = vim.api.nvim_create_buf(false, true)
    bufs[#bufs + 1] = b
    return b
  end

  before_each(function()
    bufs = {}
    M.set_ref("HEAD")
  end)

  after_each(function()
    if orig_get_ref_content then
      diff_mod.get_ref_content = orig_get_ref_content
      orig_get_ref_content = nil
    end
    if orig_compute_hunks then
      diff_mod.compute_hunks = orig_compute_hunks
      orig_compute_hunks = nil
    end
    for _, b in ipairs(bufs) do
      local s = state._bufs[b]
      if s and not vim.api.nvim_buf_is_valid(b) then
        if s.timer then
          s.timer:stop()
          s.timer:close()
        end
        pcall(vim.api.nvim_del_augroup_by_id, s.augroup)
      else
        pcall(M.disable, b)
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
      state._bufs[b] = nil
    end
    M.set_ref("HEAD")
  end)

  it("uses the configured ref when enabled without one", function()
    M.setup({ default_ref = "HEAD~1" })
    local b = new_buf()

    M.enable(b)

    assert.are.equal("HEAD~1", M.get_ref())
    assert.are.equal("HEAD~1", state._bufs[b].ref)
  end)

  it("keeps explicit refs separate from the default", function()
    local b1, b2 = new_buf(), new_buf()

    M.enable(b1, "HEAD~2")
    M.toggle(b2, "HEAD~1")

    assert.are.equal("HEAD~2", state._bufs[b1].ref)
    assert.are.equal("HEAD~1", state._bufs[b2].ref)
    assert.are.equal("HEAD", M.get_ref())
  end)

  it("preserves the default ref when toggling a buffer", function()
    M.set_ref("main")
    local b = new_buf()

    M.toggle(b)
    assert.are.equal("main", state._bufs[b].ref)

    M.toggle(b)
    assert.is_nil(state._bufs[b])
    assert.are.equal("main", M.get_ref())

    M.toggle(b)
    assert.are.equal("main", state._bufs[b].ref)
  end)

  it(":InlineDiffSetRef changes the default ref", function()
    vim.cmd("InlineDiffSetRef main")
    assert.are.equal("main", M.get_ref())

    vim.cmd("InlineDiffSetRef")
    assert.are.equal("HEAD", M.get_ref())
  end)

  it("updates enabled buffers when the default ref changes", function()
    local b1, b2 = new_buf(), new_buf()
    M.enable(b1)
    M.enable(b2, "HEAD~2")

    M.set_ref("main")
    assert.are.equal("main", M.get_ref())
    assert.are.equal("main", state._bufs[b1].ref)
    assert.are.equal("main", state._bufs[b2].ref)

    M.set_ref()
    assert.are.equal("HEAD", M.get_ref())
    assert.are.equal("HEAD", state._bufs[b1].ref)
    assert.are.equal("HEAD", state._bufs[b2].ref)

    vim.api.nvim_buf_delete(b2, { force = true })
    assert.has_no.errors(function()
      M.set_ref("main")
    end)
    assert.are.equal("main", state._bufs[b1].ref)
  end)

  it("fetches the default ref again after re-enabling a buffer", function()
    local calls = {}
    orig_get_ref_content = diff_mod.get_ref_content
    orig_compute_hunks = diff_mod.compute_hunks
    diff_mod.get_ref_content = function(_, ref, cb)
      calls[#calls + 1] = ref
      cb({ "line1" })
    end
    diff_mod.compute_hunks = function(_, _, cb)
      cb({})
    end

    local b = new_buf()
    vim.api.nvim_buf_set_name(b, "/tmp/inline-diff-default-ref-" .. b .. ".txt")
    M.set_ref("HEAD~1")

    M.toggle(b)
    M.toggle(b)
    M.toggle(b)

    assert.are.equal(2, #calls)
    assert.are.equal("HEAD~1", calls[1])
    assert.are.equal("HEAD~1", calls[2])
  end)
end)
