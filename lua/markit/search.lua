local M = {}

M.engines = {
	ripgrep = require("markit.engines.ripgrep"),
	astgrep = require("markit.engines.astgrep"),
}

function M.run(method, query, filter, flags, path, on_complete)
	local m = method or "ripgrep"
	if m == "rg" then
		m = "ripgrep"
	elseif m == "ast" then
		m = "astgrep"
	end
	local engine = M.engines[m] or M.engines.ripgrep
	engine.run(query, filter, flags, path, on_complete)
end

return M
