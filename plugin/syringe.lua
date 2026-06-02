if vim.g.loaded_syringe then
  return
end
vim.g.loaded_syringe = true

-- Create user commands
vim.api.nvim_create_user_command("SyringeRun", function()
  require("syringe").run()
end, {
  range = true,
  desc = "Run Syringe prompt replacement on selection",
})

vim.api.nvim_create_user_command("SyringeCancel", function()
  require("syringe").cancel()
end, {
  desc = "Cancel active Syringe job in current buffer",
})
