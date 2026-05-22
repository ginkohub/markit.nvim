local M = {}

local function get_project_root()
	local root = vim.fn.finddir(".git", ".;")
	if type(root) == "table" then
		root = root[1]
	end
	local path
	if type(root) == "string" and root ~= "" then
		path = vim.fn.fnamemodify(root, ":h")
	else
		path = vim.fn.getcwd()
	end
	return path:gsub("\\", "/")
end

function M.run(query, filter, flags, path)
	local results = {}
	local rg_exists = vim.fn.executable("rg") == 1

	if rg_exists and query and #query > 0 then
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
			for flag in string.gmatch(sanitized, "%S+") do
				table.insert(args, flag)
			end
		end

		table.insert(args, "-g")
		table.insert(args, "!.git/*")

		table.insert(args, query)

		local root = get_project_root()
		local search_path = root
		if path and path ~= "" then
			search_path = vim.fn.expand(path)
		end
		search_path = search_path:gsub("\\", "/")
		table.insert(args, search_path)

		local output = vim.fn.systemlist(args)
		for _, line in ipairs(output) do
			local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)")
			if file then
				file = file:gsub("\\", "/")
				table.insert(results, { file = file, lnum = lnum, text = vim.trim(text) })
			end
			if #results >= 100 then
				break
			end
		end
		table.sort(results, function(a, b)
			if a.file ~= b.file then
				return a.file < b.file
			end
			return tonumber(a.lnum) < tonumber(b.lnum)
		end)
	end

	return results, rg_exists
end

return M
