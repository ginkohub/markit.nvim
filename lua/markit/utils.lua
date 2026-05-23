local M = {}

function M.get_project_root()
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

return M
