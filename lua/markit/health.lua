local M = {}

function M.check(force_print)
	local rg_exists = vim.fn.executable("rg") == 1
	local data_dir = vim.fn.stdpath("data") .. "/markit"
	local dir_exists = vim.fn.isdirectory(data_dir) == 1
	local has_health, health = pcall(require, "vim.health")
	if not force_print and has_health and health.start then
		health.start("markit")
		if rg_exists then
			health.ok("ripgrep is installed and executable")
		else
			health.error("ripgrep is not installed or not in PATH")
		end
		if dir_exists then
			health.ok("State directory exists and is writable: " .. data_dir)
		else
			health.warn("State directory does not exist yet: " .. data_dir)
		end
	else
		local lines = { "=== MarkIt Health Status ===" }
		if rg_exists then
			table.insert(lines, " [OK] ripgrep is installed")
		else
			table.insert(lines, " [ERROR] ripgrep is not installed")
		end
		if dir_exists then
			table.insert(lines, " [OK] State directory exists")
		else
			table.insert(lines, " [WARN] State directory does not exist yet")
		end
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
	end
end

return M
