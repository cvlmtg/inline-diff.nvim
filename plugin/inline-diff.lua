vim.api.nvim_create_user_command("InlineDiffEnable", function(args)
  local ref = args.args ~= "" and args.args or nil
  require("inline-diff").enable(nil, ref)
end, { nargs = "?" })

vim.api.nvim_create_user_command("InlineDiffDisable", function()
  require("inline-diff").disable()
end, {})

vim.api.nvim_create_user_command("InlineDiff", function(args)
  local ref = args.args ~= "" and args.args or nil
  require("inline-diff").toggle(nil, ref)
end, { nargs = "?" })

vim.api.nvim_create_user_command("InlineDiffNext", function()
  require("inline-diff").next_hunk()
end, { desc = "Jump to next inline-diff change" })

vim.api.nvim_create_user_command("InlineDiffPrev", function()
  require("inline-diff").prev_hunk()
end, { desc = "Jump to previous inline-diff change" })
