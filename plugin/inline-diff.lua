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
