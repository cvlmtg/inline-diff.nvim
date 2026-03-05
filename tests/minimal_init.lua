local plenary_path = vim.fn.stdpath("data") .. "/site/pack/vendor/start/plenary.nvim"

if vim.fn.isdirectory(plenary_path) == 0 then
  vim.fn.system({ "git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_path })
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_path)

vim.cmd("runtime plugin/plenary.vim")
