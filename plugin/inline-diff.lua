vim.api.nvim_create_user_command("InlineDiffEnable", function()
  require("inline-diff").enable()
end, {})

vim.api.nvim_create_user_command("InlineDiffDisable", function()
  require("inline-diff").disable()
end, {})

vim.api.nvim_create_user_command("InlineDiffToggle", function()
  require("inline-diff").toggle()
end, {})
