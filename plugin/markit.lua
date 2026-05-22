-- Create the user command
vim.api.nvim_create_user_command("MarkIt", function()
	require("markit").toggle()
end, {})

vim.api.nvim_create_user_command("MarkItHealth", function()
	require("markit.health").check(true)
end, {})
