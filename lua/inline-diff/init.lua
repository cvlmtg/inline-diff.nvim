local M = {}

M.config = {
  debounce_ms = 150,
  ref = "HEAD",
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

function M.enable(bufnr) end

function M.disable(bufnr) end

function M.toggle(bufnr) end

return M
