local M = {}
local state = require("markit.state")
local utils = require("markit.utils")

local current_job = nil

function M.run(query, filter, flags, path, on_complete)
	if current_job then
		vim.fn.jobstop(current_job)
		current_job = nil
	end

	local results = {}
	local executable = vim.fn.executable("rg") == 1

	if not executable or not query or #query == 0 then
		on_complete({}, executable)
		return
	end

	local args = { "rg", "--vimgrep", "--smart-case", "--max-columns=100" }
	local ft = filter or "*"
	if ft ~= "" and ft ~= "*" and ft ~= "*.*" then
		table.insert(args, "-g")
		table.insert(args, "*." .. ft:gsub("%.", ""))
	else
		table.insert(args, "-g")
		table.insert(args, "*.*")
	end

	if flags and flags ~= "" then
		local sanitized = flags:gsub("[^%w%s%.%-]", "")
		local BLOCKED = { "exec", "pre%-glob", "iglob" }
		for _, b in ipairs(BLOCKED) do
			if sanitized:find("%-%-" .. b) then
				vim.notify("markit: flag '" .. b .. "' tidak diizinkan", vim.log.levels.WARN)
				on_complete({}, true)
				return
			end
		end
		for flag in string.gmatch(sanitized, "%S+") do
			table.insert(args, flag)
		end
	end

	table.insert(args, "-g")
	table.insert(args, "!.git/*")
	table.insert(args, query)

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
				stdout_data = stdout_data .. table.concat(data, "\n")
			end
		end,
		on_exit = function()
			current_job = nil
			local lines = vim.split(stdout_data, "\n", { trimempty = true })
			for _, line in ipairs(lines) do
				local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)")
				if file then
					file = file:gsub("\\", "/")
					table.insert(results, { file = file, lnum = lnum, text = vim.trim(text) })
				end
				if #results >= state.data.config.max_results then
					break
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
