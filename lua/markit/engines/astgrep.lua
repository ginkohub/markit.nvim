local M = {}
local state = require("markit.state")
local utils = require("markit.utils")

-- basic ast-grep implementation
local current_job = nil

function M.run(query, filter, flags, path, on_complete)
	if current_job then
		vim.fn.jobstop(current_job)
		current_job = nil
	end

	local results = {}
	local executable = vim.fn.executable("ast-grep") == 1

	if not executable or not query or #query == 0 then
		on_complete({}, executable)
		return
	end

	local args = { "ast-grep", "run", "--json=compact" }

	-- basic pattern search
	table.insert(args, "--pattern")
	table.insert(args, query) -- jobstart handles escaping

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
	table.insert(args, search_path)

	local stdout_data = ""
	current_job = vim.fn.jobstart(args, {
		on_stdout = function(_, data, _)
			if data then
				stdout_data = stdout_data .. table.concat(data, "")
			end
		end,
		on_exit = function()
			current_job = nil
			local ok, decoded = pcall(vim.json.decode, stdout_data)

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

			vim.schedule(function()
				on_complete(results, true)
			end)
		end,
	})
end

return M
