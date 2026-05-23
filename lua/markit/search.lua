local M = {}

M.engines = {
	ripgrep = require("markit.engines.ripgrep"),
	astgrep = require("markit.engines.astgrep"),
}

function M.run(method, query, filter, flags, path)
	local m = method or "ripgrep"
	if m == "rg" then
		m = "ripgrep"
	elseif m == "ast" then
		m = "astgrep"
	end
	local engine = M.engines[m] or M.engines.ripgrep
	return engine.run(query, filter, flags, path)
end

return M
