local M = {}
local state = require("markit.state")
local ui = require("markit.ui")

function M.setup(opts)
	opts = opts or {}
	if opts.config then
		state.data.config = vim.tbl_deep_extend("force", state.data.config, opts.config)
	end
end

function M.toggle()
	if state.data.win and vim.api.nvim_win_is_valid(state.data.win) then
		ui.clear_previews()
		vim.api.nvim_win_close(state.data.win, true)
		state.data.win = nil
	else
		ui.create_window()
	end
end

return M
