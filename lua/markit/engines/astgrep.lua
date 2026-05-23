local M = {}
local state = require("markit.state")
local utils = require("markit.utils")

-- basic ast-grep implementation
function M.run(query, filter, flags, path)
	local results = {}
	local executable = vim.fn.executable("ast-grep") == 1

	if executable and query and #query > 0 then
		local args = { "ast-grep", "run", "--json=compact" }

		-- basic pattern search
		table.insert(args, "--pattern")
		table.insert(args, vim.fn.shellescape(query))

		if filter and filter ~= "" and filter ~= "*" then
			table.insert(args, "--lang")
			table.insert(args, filter)
		end

		local root = utils.get_project_root()
		local search_path = root
		if path and path ~= "" then
			search_path = vim.fn.expand(path)
		end
		search_path = search_path:gsub("\\", "/")
		table.insert(args, vim.fn.shellescape(search_path))

		local cmd = table.concat(args, " ")
		local output = vim.fn.system(cmd)
		local ok, decoded = pcall(vim.json.decode, output)

		if ok and decoded then
			for _, item in ipairs(decoded) do
				local file = item.file:gsub("\\", "/")
				local lnum = item.range.start.line + 1
				local text = item.lines:gsub("\n", " ")
				table.insert(results, { file = file, lnum = tostring(lnum), text = vim.trim(text) })
				if #results >= state.data.config.max_results then
					break
				end
			end
		end
		table.sort(results, function(a, b)
			if a.file ~= b.file then
				return a.file < b.file
			end
			return tonumber(a.lnum) < tonumber(b.lnum)
		end)
	end

	return results, executable
end

return M
