local M = {}

local data_dir = vim.fn.stdpath("data") .. "/markit"
local data_path = data_dir .. "/state.json"

M.data = {
	results = {},
	last_query = "",
	last_filter = "*",
	last_flags = "",
	last_path = "",
	history = {},
	history_idx = 0,
	buf = nil,
	win = nil,
	ui_map = {},
	folded_files = {},
}

function M.load()
	local path = data_path
	local f = io.open(path, "r")
	if not f then
		local old_path = vim.fn.stdpath("data") .. "/markit_state.json"
		f = io.open(old_path, "r")
	end
	if f then
		local content = f:read("*a")
		f:close()
		local ok, decoded = pcall(vim.json.decode, content)
		if ok and decoded then
			for k, v in pairs(decoded) do
				M.data[k] = v
			end
			if decoded.last_type and not decoded.last_filter then
				M.data.last_filter = decoded.last_type
			end
		end
	end
	M.data.history_idx = #M.data.history + 1
end

function M.save()
	local to_save = {
		last_query = M.data.last_query,
		last_filter = M.data.last_filter,
		last_flags = M.data.last_flags,
		last_path = M.data.last_path,
		history = M.data.history,
	}
	if vim.fn.isdirectory(data_dir) == 0 then
		vim.fn.mkdir(data_dir, "p")
	end
	local f = io.open(data_path, "w")
	if f then
		f:write(vim.json.encode(to_save))
		f:close()
	end
end

M.load()

return M
