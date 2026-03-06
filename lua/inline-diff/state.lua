local M = {}

M._bufs = {}

function M.get(bufnr)
  if M._bufs[bufnr] then
    return M._bufs[bufnr]
  end
  local s = {
    ns = vim.api.nvim_create_namespace("inline-diff:" .. bufnr),
    augroup = vim.api.nvim_create_augroup("InlineDiff:" .. bufnr, {}),
    timer = nil,
    enabled = false,
    generation = 0,
    has_top_virt = false,
    has_bot_virt = false,
    ref_lines = nil,
    ref_dirty = true,
  }
  M._bufs[bufnr] = s
  return s
end

function M.remove(bufnr)
  local s = M._bufs[bufnr]
  if not s then
    return
  end
  if s.timer then
    s.timer:stop()
    s.timer:close()
  end
  vim.api.nvim_buf_clear_namespace(bufnr, s.ns, 0, -1)
  pcall(vim.api.nvim_del_augroup_by_id, s.augroup)
  M._bufs[bufnr] = nil
end

return M
