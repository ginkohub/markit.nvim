local M = {}
local state = require("markit.state")
local search = require("markit.search")

local hl_ns = vim.api.nvim_create_namespace("markit_hl")

local query_prefix = " Query : "
local filter_prefix = "󰈔 Filter: "
local flags_prefix = " Flags : "
local path_prefix = " Path  : "
local method_prefix = "󱓞 Method: "

local previewed_bufs = {}

local function safe_set_lines(buf, start, end_, strict_indexing, replacement)
	state.data.programmatic_change = true
	local ok, err = pcall(vim.api.nvim_buf_set_lines, buf, start, end_, strict_indexing, replacement)
	vim.schedule(function()
		state.data.programmatic_change = false
	end)
	if not ok then
		error(err)
	end
end

local function format_input_line(prefix, value)
	return prefix .. value
end

local function extract_value(line, prefix)
	if not vim.startswith(line, prefix) then
		return ""
	end
	local val = line:sub(#prefix + 1)
	val = val:match("^(.-)%s*$") or ""
	return val:gsub("\n", " ")
end

local function parse_current_inputs(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 1, 6, false)
	local q = extract_value(lines[1] or "", query_prefix)
	local f = extract_value(lines[2] or "", filter_prefix)
	local fl = extract_value(lines[3] or "", flags_prefix)
	local p = extract_value(lines[4] or "", path_prefix)
	local m = extract_value(lines[5] or "", method_prefix)
	return q, f, fl, p, m
end

local save_timer = nil
local function debounced_save()
	if save_timer then
		save_timer:stop()
		save_timer:close()
		save_timer = nil
	end
	save_timer = vim.uv.new_timer()
	if save_timer then
		save_timer:start(
			500,
			0,
			vim.schedule_wrap(function()
				state.save()
				if save_timer then
					save_timer:stop()
					save_timer:close()
					save_timer = nil
				end
			end)
		)
	end
end

local function lpad(str, len, char)
	char = char or " "
	return string.rep(char, len - #str) .. str
end

local function setup_highlights()
	local hl_config = state.data.config.highlights
	for name, hl in pairs(hl_config) do
		vim.api.nvim_set_hl(0, "MarkIt" .. name, hl)
	end
end

local function add_to_history(q, f, fl, p, m)
	if q == "" then
		return
	end
	local entry = string.format("%s | %s | %s | %s | %s", q, f, fl, p, m)
	if state.data.history[#state.data.history] == entry then
		return
	end
	table.insert(state.data.history, entry)
	if #state.data.history > 50 then
		table.remove(state.data.history, 1)
	end
	state.data.history_idx = #state.data.history + 1
	state.save()
end

local search_timer = nil
function M.update_ui(query, filter, flags, path, method, force)
	if not state.data.buf or not vim.api.nvim_buf_is_valid(state.data.buf) then
		return
	end

	local prev_query = state.data.last_query
	local prev_filter = state.data.last_filter
	local prev_flags = state.data.last_flags
	local prev_path = state.data.last_path
	local prev_method = state.data.last_method

	local current_query = query or ""
	local current_filter = filter or "*"
	local current_flags = flags or ""
	local current_path = path or ""
	local current_method = method or state.data.config.engine or "ripgrep"

	local changed = (
		prev_query ~= current_query
		or prev_filter ~= current_filter
		or prev_flags ~= current_flags
		or prev_path ~= current_path
		or prev_method ~= current_method
	)

	state.data.last_query = current_query
	state.data.last_filter = current_filter
	state.data.last_flags = current_flags
	state.data.last_path = current_path
	state.data.last_method = current_method
	debounced_save()

	if changed then
		state.data.folded_files = {}
	end

	local function render(results, is_searching, executable_exists)
		state.data.ui_map = {}

		local status_emoji = (#results > 0) and "" or ""
		local status_hl = (#results > 0) and "MarkItSuccess" or "MarkItError"
		local status_text = string.format("%s Found: %d matches", status_emoji, #results)

		if is_searching then
			status_emoji = "󱎫"
			status_hl = "MarkItLabel"
			status_text = "󱎫 Searching..."
		elseif not query or query == "" then
			status_emoji = ""
			status_hl = "MarkItLabel"
			status_text = string.format("%s Found: %d matches", status_emoji, #results)
		elseif not executable_exists then
			status_emoji = string.format(" (%s not found)", current_method)
			status_hl = "MarkItError"
			status_text = status_emoji
		end

		local lines = {
			"MarkIt Search",
			"",
			"",
			"",
			"",
			"",
			status_text,
			"",
		}

		local grouped = {}
		local file_order = {}
		for _, res in ipairs(results) do
			if not grouped[res.file] then
				grouped[res.file] = {}
				table.insert(file_order, res.file)
			end
			table.insert(grouped[res.file], res)
		end

		local current_line_idx = #lines
		for _, file in ipairs(file_order) do
			local is_folded = state.data.folded_files[file]
			local icon = is_folded and " 󰉋 " or " 󰉖 "
			table.insert(lines, icon .. file)
			current_line_idx = current_line_idx + 1

			if not is_folded then
				for _, res in ipairs(grouped[file]) do
					local cleaned_text = res.text:gsub("\n", " ")
					table.insert(lines, string.format("  %s: %s", lpad(res.lnum, 3), cleaned_text))
					current_line_idx = current_line_idx + 1
					state.data.ui_map[current_line_idx] = res
				end
			end
		end

		safe_set_lines(state.data.buf, 0, 1, false, { lines[1] })
		local remainder = {}
		for j = 7, #lines do
			table.insert(remainder, lines[j])
		end
		safe_set_lines(state.data.buf, 6, -1, false, remainder)

		vim.api.nvim_buf_clear_namespace(state.data.buf, hl_ns, 0, -1)

		-- (Extmarks are set here - keeping existing logic)
		vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 1, 0, { hl_group = "MarkItLabel", end_col = #query_prefix })
		vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 2, 0, { hl_group = "MarkItLabel", end_col = #filter_prefix })
		vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 3, 0, { hl_group = "MarkItLabel", end_col = #flags_prefix })
		vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 4, 0, { hl_group = "MarkItLabel", end_col = #path_prefix })
		vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 5, 0, { hl_group = "MarkItLabel", end_col = #method_prefix })

		if current_query == "" then
			vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 1, #query_prefix, {
				virt_text = { { "Search pattern...", "Comment" } },
				virt_text_pos = "eol",
			})
		end
		-- ... (rest of virt_texts)
		if current_filter == "" then
			vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 2, #filter_prefix, {
				virt_text = { { "e.g. lua, js (optional)", "Comment" } },
				virt_text_pos = "eol",
			})
		end
		if current_flags == "" then
			vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 3, #flags_prefix, {
				virt_text = { { "e.g. -i, -w (optional)", "Comment" } },
				virt_text_pos = "eol",
			})
		end
		if current_path == "" then
			vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 4, #path_prefix, {
				virt_text = { { "e.g. ./src (optional)", "Comment" } },
				virt_text_pos = "eol",
			})
		end
		if current_method == "" then
			vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 5, #method_prefix, {
				virt_text = { { "rg or ast", "Comment" } },
				virt_text_pos = "eol",
			})
		end

		local buf_lines_rendered = vim.api.nvim_buf_get_lines(state.data.buf, 0, -1, false)
		vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 0, 0, { hl_group = "MarkItTitle", end_col = #(buf_lines_rendered[1] or "") })
		vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, 6, 0, { hl_group = status_hl, end_col = #(buf_lines_rendered[7] or "") })

		for l_idx, res in pairs(state.data.ui_map) do
			-- Highlight matches and text (keeping existing logic)
			vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, l_idx - 1, 0, { hl_group = "MarkItText", end_col = #(buf_lines_rendered[l_idx] or "") })
			local lnum_str = ":" .. res.lnum
			vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, l_idx - 1, 2, { hl_group = "MarkItLine", end_col = 2 + #lnum_str })
			if current_query ~= "" then
				local text = res.text
				local q = current_query:lower()
				local start = 1
				local prefix = string.format("  %s: ", lpad(res.lnum, 3))
				local offset = #prefix
				while true do
					local s, e = text:lower():find(q, start, true)
					if not s then break end
					vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, l_idx - 1, offset + s - 1, { hl_group = "MarkItMatch", end_col = offset + e })
					start = e + 1
				end
			end
		end

		for i, line in ipairs(lines) do
			if line:match("󰉋 ") then
				vim.api.nvim_buf_set_extmark(state.data.buf, hl_ns, i - 1, 0, { hl_group = "MarkItFile", end_col = #(buf_lines_rendered[i] or "") })
			end
		end
	end

	if search_timer then
		search_timer:stop()
		search_timer:close()
		search_timer = nil
	end

	if force then
		search.run(current_method, current_query, current_filter, current_flags, current_path, function(results, executable_exists)
			state.data.results = results
			render(results, false, executable_exists)
		end)
		return
	end

	if changed then
		-- Immediate visual feedback that search is pending
		render(state.data.results or {}, true, true)

		search_timer = vim.uv.new_timer()
		if search_timer then
			search_timer:start(
				500,
				0,
				vim.schedule_wrap(function()
					search.run(current_method, current_query, current_filter, current_flags, current_path, function(results, executable_exists)
						state.data.results = results
						render(results, false, executable_exists)
					end)
					if search_timer then
						search_timer:stop()
						search_timer:close()
						search_timer = nil
					end
				end)
			)
		end
	else
		render(state.data.results or {}, false, true)
	end
end

local function navigate_history(dir)
	if #state.data.history == 0 then
		return
	end
	local new_idx = state.data.history_idx + dir
	if new_idx < 1 then
		new_idx = 1
	end
	if new_idx > #state.data.history then
		new_idx = #state.data.history + 1
		local q = state.data.last_query or ""
		local f = state.data.last_filter or ""
		local fl = state.data.last_flags or ""
		local p = state.data.last_path or ""
		local m = state.data.last_method or "ripgrep"
		safe_set_lines(state.data.buf, 1, 6, false, {
			format_input_line(query_prefix, q),
			format_input_line(filter_prefix, f),
			format_input_line(flags_prefix, fl),
			format_input_line(path_prefix, p),
			format_input_line(method_prefix, m),
		})
		state.data.history_idx = new_idx
		local win = state.data.win
		if win and vim.api.nvim_win_is_valid(win) then
			local cursor = vim.api.nvim_win_get_cursor(win)
			if cursor[1] == 2 then
				pcall(vim.api.nvim_win_set_cursor, win, { 2, #query_prefix + #q })
			elseif cursor[1] == 3 then
				pcall(vim.api.nvim_win_set_cursor, win, { 3, #filter_prefix + #f })
			elseif cursor[1] == 4 then
				pcall(vim.api.nvim_win_set_cursor, win, { 4, #flags_prefix + #fl })
			elseif cursor[1] == 5 then
				pcall(vim.api.nvim_win_set_cursor, win, { 5, #path_prefix + #p })
			elseif cursor[1] == 6 then
				pcall(vim.api.nvim_win_set_cursor, win, { 6, #method_prefix + #m })
			end
		end
		return
	end
	state.data.history_idx = new_idx
	local entry = state.data.history[new_idx]
	local q, f, fl, p, m = entry:match("^(.-) | (.-) | (.-) | (.-) | (.*)$")
	if not q then
		q, f, fl, p = entry:match("^(.-) | (.-) | (.-) | (.*)$")
		m = "ripgrep"
	end
	if not q then
		q, f = entry:match("^(.*) | (.*)$")
		fl = ""
		p = ""
		m = "ripgrep"
	end
	safe_set_lines(state.data.buf, 1, 6, false, {
		format_input_line(query_prefix, q),
		format_input_line(filter_prefix, f),
		format_input_line(flags_prefix, fl),
		format_input_line(path_prefix, p),
		format_input_line(method_prefix, m),
	})
	local win = state.data.win
	if win and vim.api.nvim_win_is_valid(win) then
		local cursor = vim.api.nvim_win_get_cursor(win)
		if cursor[1] == 2 then
			pcall(vim.api.nvim_win_set_cursor, win, { 2, #query_prefix + #q })
		elseif cursor[1] == 3 then
			pcall(vim.api.nvim_win_set_cursor, win, { 3, #filter_prefix + #f })
		elseif cursor[1] == 4 then
			pcall(vim.api.nvim_win_set_cursor, win, { 4, #flags_prefix + #fl })
		elseif cursor[1] == 5 then
			pcall(vim.api.nvim_win_set_cursor, win, { 5, #path_prefix + #p })
		elseif cursor[1] == 6 then
			pcall(vim.api.nvim_win_set_cursor, win, { 6, #method_prefix + #m })
		end
	end
	M.update_ui(q, f, fl, p, m)
end

local preview_ns = vim.api.nvim_create_namespace("markit_preview")

-- Function to find if a file is ALREADY open in any tab (Robust Absolute Path Match)
local function find_existing_buf_win(file_path)
	if not file_path or file_path == "" then
		return nil, nil
	end
	local target_path = vim.fn.fnamemodify(file_path, ":p")

	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
			if vim.api.nvim_win_is_valid(win) then
				local b = vim.api.nvim_win_get_buf(win)
				local bpath = vim.api.nvim_buf_get_name(b)
				if bpath ~= "" and vim.fn.fnamemodify(bpath, ":p") == target_path then
					return win, tab
				end
			end
		end
	end
	return nil, nil
end

local function find_editor_win(file_path)
	local target_win = nil
	local fallback_win = nil
	local target_path = file_path and vim.fn.fnamemodify(file_path, ":p") or nil

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if win ~= state.data.win and vim.api.nvim_win_is_valid(win) then
			local b = vim.api.nvim_win_get_buf(win)
			local bt = vim.api.nvim_get_option_value("buftype", { buf = b })
			local ft = vim.api.nvim_get_option_value("filetype", { buf = b })
			local config = vim.api.nvim_win_get_config(win)

			if ft ~= "markit" and config.relative == "" then
				-- Highest priority: window already showing this file
				if target_path and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":p") == target_path then
					return win, vim.api.nvim_get_current_tabpage()
				end
				-- Preferred: normal editor window
				if bt == "" then
					target_win = win
				-- Fallback: dashboard, landing page, etc.
				elseif bt == "nofile" or ft:match("dashboard") or ft == "alpha" then
					fallback_win = win
				end
			end
		end
	end

	return target_win or fallback_win, vim.api.nvim_get_current_tabpage()
end

function M.clear_previews()
	for _, b in ipairs(previewed_bufs) do
		if vim.api.nvim_buf_is_valid(b) then
			vim.api.nvim_buf_clear_namespace(b, preview_ns, 0, -1)
		end
	end
	previewed_bufs = {}
end

local function preview_line()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line_idx = cursor[1]
	local res = state.data.ui_map[line_idx]

	M.clear_previews()

	if res then
		local editor_win, tab = find_editor_win(res.file)

		if editor_win then
			local buf = vim.fn.bufadd(res.file)
			vim.fn.bufload(buf)
			vim.api.nvim_win_set_buf(editor_win, buf)
			table.insert(previewed_bufs, buf)

			if vim.api.nvim_get_option_value("filetype", { buf = buf }) == "" then
				vim.api.nvim_buf_call(buf, function()
					vim.cmd("filetype detect")
				end)
			end

			local lnum = tonumber(res.lnum)
			local line_count = vim.api.nvim_buf_line_count(buf)
			if lnum > line_count then
				lnum = line_count
			end
			if lnum < 1 then
				lnum = 1
			end
			vim.api.nvim_win_set_cursor(editor_win, { lnum, 0 })

			vim.api.nvim_buf_set_extmark(buf, preview_ns, lnum - 1, 0, {
				end_line = lnum - 1,
				line_hl_group = "Visual",
			})
		end
	end
end

function M.create_window()
	setup_highlights()
	if not state.data.buf or not vim.api.nvim_buf_is_valid(state.data.buf) then
		state.data.buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.data.buf })
		vim.api.nvim_set_option_value("bufhidden", "hide", { buf = state.data.buf })
		vim.api.nvim_set_option_value("buflisted", false, { buf = state.data.buf })
		vim.api.nvim_set_option_value("swapfile", false, { buf = state.data.buf })
		vim.api.nvim_set_option_value("filetype", "markit", { buf = state.data.buf })

		vim.b[state.data.buf].completion = false
		local ok, cmp = pcall(require, "cmp")
		if ok then
			cmp.setup.buffer({ enabled = false })
		end

		safe_set_lines(state.data.buf, 0, -1, false, {
			"MarkIt Search",
			format_input_line(query_prefix, state.data.last_query or ""),
			format_input_line(filter_prefix, state.data.last_filter or ""),
			format_input_line(flags_prefix, state.data.last_flags or ""),
			format_input_line(path_prefix, state.data.last_path or ""),
			format_input_line(method_prefix, state.data.last_method or "ripgrep"),
			" Found: 0 matches",
		})
		M.update_ui(
			state.data.last_query or "",
			state.data.last_filter or "",
			state.data.last_flags or "",
			state.data.last_path or "",
			state.data.last_method or "ripgrep",
			false
		)

		vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
			buffer = state.data.buf,
			callback = function()
				if state.data.programmatic_change then
					return
				end
				if not state.data.buf or not vim.api.nvim_buf_is_valid(state.data.buf) then
					return
				end

				local buf_lines = vim.api.nvim_buf_get_lines(state.data.buf, 0, -1, false)
				local needs_restore = false

				-- Check if we have enough lines for the header, 5 inputs, and status line
				if #buf_lines < 7 then
					needs_restore = true
				else
					-- Rigorous check for all fixed prefixes and positions
					if buf_lines[1] ~= "MarkIt Search" then
						needs_restore = true
					elseif not vim.startswith(buf_lines[2] or "", query_prefix) then
						needs_restore = true
					elseif not vim.startswith(buf_lines[3] or "", filter_prefix) then
						needs_restore = true
					elseif not vim.startswith(buf_lines[4] or "", flags_prefix) then
						needs_restore = true
					elseif not vim.startswith(buf_lines[5] or "", path_prefix) then
						needs_restore = true
					elseif not vim.startswith(buf_lines[6] or "", method_prefix) then
						needs_restore = true
					elseif not (buf_lines[7] or ""):match("Found: %d+ matches") then
						needs_restore = true
					end
				end

				if needs_restore then
					-- When restoring, we try to preserve whatever values were there
					-- but we look for them across all lines in case they merged
					local full_text = table.concat(buf_lines, "\n")
					
					local function find_value(text, prefix, next_prefix)
						local start_idx = text:find(prefix, 1, true)
						if not start_idx then return "" end
						
						local val_start = start_idx + #prefix
						local end_idx
						if next_prefix then
							end_idx = text:find(next_prefix, val_start, true)
						end
						
						local val
						if end_idx then
							val = text:sub(val_start, end_idx - 1)
						else
							-- If no next prefix, take until first newline or end
							local nl = text:find("\n", val_start)
							if nl then
								val = text:sub(val_start, nl - 1)
							else
								val = text:sub(val_start)
							end
						end
						return vim.trim(val):gsub("\n", " ")
					end

					local q = find_value(full_text, query_prefix, filter_prefix)
					local f = find_value(full_text, filter_prefix, flags_prefix)
					local fl = find_value(full_text, flags_prefix, path_prefix)
					local p = find_value(full_text, path_prefix, method_prefix)
					local m = find_value(full_text, method_prefix, nil)

					local results = state.data.results or {}
					local status_emoji = (#results > 0) and "" or ""
					if q == "" then status_emoji = "" end

					safe_set_lines(state.data.buf, 0, 7, false, {
						"MarkIt Search",
						format_input_line(query_prefix, q),
						format_input_line(filter_prefix, f),
						format_input_line(flags_prefix, fl),
						format_input_line(path_prefix, p),
						format_input_line(method_prefix, m),
						string.format("%s Found: %d matches", status_emoji, #results),
					})

					-- Reset cursor to a safe place
					local win = state.data.win
					if win and vim.api.nvim_win_is_valid(win) then
						pcall(vim.api.nvim_win_set_cursor, win, { 2, #query_prefix + #q })
					end
					
					M.update_ui(q, f, fl, p, m)
					return
				end

				-- Normal processing if structure is intact
				local cursor = vim.api.nvim_win_get_cursor(0)
				if cursor[1] >= 2 and cursor[1] <= 6 then
					local q, f, fl, p, m = parse_current_inputs(state.data.buf)
					M.update_ui(vim.trim(q), vim.trim(f), vim.trim(fl), vim.trim(p), vim.trim(m))
				end
			end,
		})

		vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
			buffer = state.data.buf,
			callback = function()
				local cursor = vim.api.nvim_win_get_cursor(0)
				local line = cursor[1]
				local col = cursor[2]
				local mode = vim.api.nvim_get_mode().mode
				local is_insert = vim.startswith(mode, "i")

				if is_insert then
					if line < 2 then
						local q = state.data.last_query or ""
						pcall(vim.api.nvim_win_set_cursor, 0, { 2, #query_prefix + #q })
						line = 2
						col = #query_prefix + #q
					elseif line > 6 then
						local m = state.data.last_method or "ripgrep"
						pcall(vim.api.nvim_win_set_cursor, 0, { 6, #method_prefix + #m })
						line = 6
						col = #method_prefix + #m
					end
				end

				if line == 2 then
					local lines = vim.api.nvim_buf_get_lines(state.data.buf, 1, 2, false)
					local q = extract_value(lines[1] or "", query_prefix)
					local min_col = #query_prefix
					local max_col = min_col + #q
					if col < min_col then
						pcall(vim.api.nvim_win_set_cursor, 0, { 2, min_col })
					elseif col > max_col then
						pcall(vim.api.nvim_win_set_cursor, 0, { 2, max_col })
					end
				elseif line == 3 then
					local lines = vim.api.nvim_buf_get_lines(state.data.buf, 2, 3, false)
					local f = extract_value(lines[1] or "", filter_prefix)
					local min_col = #filter_prefix
					local max_col = min_col + #f
					if col < min_col then
						pcall(vim.api.nvim_win_set_cursor, 0, { 3, min_col })
					elseif col > max_col then
						pcall(vim.api.nvim_win_set_cursor, 0, { 3, max_col })
					end
				elseif line == 4 then
					local lines = vim.api.nvim_buf_get_lines(state.data.buf, 3, 4, false)
					local fl = extract_value(lines[1] or "", flags_prefix)
					local min_col = #flags_prefix
					local max_col = min_col + #fl
					if col < min_col then
						pcall(vim.api.nvim_win_set_cursor, 0, { 4, min_col })
					elseif col > max_col then
						pcall(vim.api.nvim_win_set_cursor, 0, { 4, max_col })
					end
				elseif line == 5 then
					local lines = vim.api.nvim_buf_get_lines(state.data.buf, 4, 5, false)
					local p = extract_value(lines[1] or "", path_prefix)
					local min_col = #path_prefix
					local max_col = min_col + #p
					if col < min_col then
						pcall(vim.api.nvim_win_set_cursor, 0, { 5, min_col })
					elseif col > max_col then
						pcall(vim.api.nvim_win_set_cursor, 0, { 5, max_col })
					end
				elseif line == 6 then
					local lines = vim.api.nvim_buf_get_lines(state.data.buf, 5, 6, false)
					local m = extract_value(lines[1] or "", method_prefix)
					local min_col = #method_prefix
					local max_col = min_col + #m
					if col < min_col then
						pcall(vim.api.nvim_win_set_cursor, 0, { 6, min_col })
					elseif col > max_col then
						pcall(vim.api.nvim_win_set_cursor, 0, { 6, max_col })
					end
				end
				preview_line()
			end,
		})

		vim.api.nvim_create_autocmd("BufWinLeave", {
			buffer = state.data.buf,
			callback = function()
				M.clear_previews()
				state.data.win = nil
			end,
		})

		vim.keymap.set("i", "<C-p>", function()
			navigate_history(-1)
		end, { buffer = state.data.buf })
		vim.keymap.set("i", "<C-n>", function()
			navigate_history(1)
		end, { buffer = state.data.buf })

		vim.keymap.set("i", "<CR>", function()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local lines = vim.api.nvim_buf_get_lines(state.data.buf, 1, 6, false)
			if cursor[1] == 2 then
				local f = extract_value(lines[2] or "", filter_prefix)
				vim.api.nvim_win_set_cursor(0, { 3, #filter_prefix + #f })
			elseif cursor[1] == 3 then
				local fl = extract_value(lines[3] or "", flags_prefix)
				vim.api.nvim_win_set_cursor(0, { 4, #flags_prefix + #fl })
			elseif cursor[1] == 4 then
				local p = extract_value(lines[4] or "", path_prefix)
				vim.api.nvim_win_set_cursor(0, { 5, #path_prefix + #p })
			elseif cursor[1] == 5 then
				local m = extract_value(lines[5] or "", method_prefix)
				vim.api.nvim_win_set_cursor(0, { 6, #method_prefix + #m })
			else
				local q = extract_value(lines[1] or "", query_prefix)
				local f = extract_value(lines[2] or "", filter_prefix)
				local fl = extract_value(lines[3] or "", flags_prefix)
				local p = extract_value(lines[4] or "", path_prefix)
				local m = extract_value(lines[5] or "", method_prefix)
				add_to_history(vim.trim(q), vim.trim(f), vim.trim(fl), vim.trim(p), vim.trim(m))
				vim.cmd("stopinsert")
				local line_count = vim.api.nvim_buf_line_count(state.data.buf)
				if line_count >= 9 then
					vim.api.nvim_win_set_cursor(0, { 9, 2 })
				end
			end
		end, { buffer = state.data.buf })

		vim.keymap.set("n", "<CR>", function()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local line_idx = cursor[1]
			local res = state.data.ui_map[line_idx]
			if res then
				local existing_win, existing_tab = find_existing_buf_win(res.file)

				if existing_win and existing_tab then
					-- 1. JUMP to existing tab/window if found anywhere
					vim.api.nvim_set_current_tabpage(existing_tab)
					vim.api.nvim_set_current_win(existing_win)
				else
					-- 2. REUSE existing editor window in current tab (NO SPLIT)
					local target_win = nil
					local fallback_win = nil

					for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
						if win ~= state.data.win then
							local b = vim.api.nvim_win_get_buf(win)
							local ft = vim.api.nvim_get_option_value("filetype", { buf = b })
							local bt = vim.api.nvim_get_option_value("buftype", { buf = b })

							if ft ~= "markit" and vim.api.nvim_win_get_config(win).relative == "" then
								-- Preferred: a normal editor buffer
								if bt == "" then
									target_win = win
									break
								end
								-- Fallback: a landing/dashboard buffer (usually nofile)
								if bt == "nofile" or ft == "snacks_dashboard" or ft == "alpha" or ft == "dashboard" then
									fallback_win = win
								end
							end
						end
					end

					target_win = target_win or fallback_win

					if target_win then
						vim.api.nvim_set_current_win(target_win)
						local buf = vim.fn.bufadd(res.file)
						vim.fn.bufload(buf)
						vim.api.nvim_win_set_buf(target_win, buf)
						-- Force filetype detection if it's a new buffer
						if vim.api.nvim_get_option_value("filetype", { buf = buf }) == "" then
							vim.api.nvim_buf_call(buf, function()
								vim.cmd("filetype detect")
							end)
						end
					else
						-- Fallback only if NO windows exist
						vim.cmd("tabedit " .. vim.fn.fnameescape(res.file))
					end
					existing_win = vim.api.nvim_get_current_win()
				end

				if existing_win then
					local buf = vim.api.nvim_win_get_buf(existing_win)
					local lnum = tonumber(res.lnum)
					local line_count = vim.api.nvim_buf_line_count(buf)
					if lnum > line_count then
						lnum = line_count
					end
					if lnum < 1 then
						lnum = 1
					end
					vim.api.nvim_win_set_cursor(existing_win, { lnum, 0 })
					vim.api.nvim_buf_clear_namespace(buf, preview_ns, 0, -1)
					vim.api.nvim_buf_set_extmark(buf, preview_ns, lnum - 1, 0, {
						end_line = lnum - 1,
						line_hl_group = "Visual",
					})
					local group = vim.api.nvim_create_augroup("MarkItOpenHighlight", { clear = true })
					vim.api.nvim_create_autocmd("CursorMoved", {
						buffer = buf,
						group = group,
						callback = function()
							vim.api.nvim_buf_clear_namespace(buf, preview_ns, 0, -1)
							pcall(vim.api.nvim_del_augroup_by_name, "MarkItOpenHighlight")
						end,
					})
				end
			else
				local line_text = vim.api.nvim_buf_get_lines(state.data.buf, line_idx - 1, line_idx, false)[1]
				local file = line_text:match("[󰉋󰉖] (.*)$")
				if file then
					state.data.folded_files[file] = not state.data.folded_files[file]
					local lines = vim.api.nvim_buf_get_lines(state.data.buf, 1, 6, false)
					local q = extract_value(lines[1] or "", query_prefix)
					local f = extract_value(lines[2] or "", filter_prefix)
					local fl = extract_value(lines[3] or "", flags_prefix)
					local p = extract_value(lines[4] or "", path_prefix)
					local m = extract_value(lines[5] or "", method_prefix)
					M.update_ui(vim.trim(q), vim.trim(f), vim.trim(fl), vim.trim(p), vim.trim(m))
				end
			end
		end, { buffer = state.data.buf })

		vim.keymap.set("n", "<TAB>", function()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local line_idx = cursor[1]
			local line_text = vim.api.nvim_buf_get_lines(state.data.buf, line_idx - 1, line_idx, false)[1]
			local file = line_text:match("[󰉋󰉖] (.*)$")
			if file then
				state.data.folded_files[file] = not state.data.folded_files[file]
				local lines = vim.api.nvim_buf_get_lines(state.data.buf, 1, 6, false)
				local q = extract_value(lines[1] or "", query_prefix)
				local f = extract_value(lines[2] or "", filter_prefix)
				local fl = extract_value(lines[3] or "", flags_prefix)
				local p = extract_value(lines[4] or "", path_prefix)
				local m = extract_value(lines[5] or "", method_prefix)
				M.update_ui(vim.trim(q), vim.trim(f), vim.trim(fl), vim.trim(p), vim.trim(m))
			end
		end, { buffer = state.data.buf })

		vim.keymap.set("n", "t", function()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local line_idx = cursor[1]
			local res = state.data.ui_map[line_idx]
			if res then
				vim.cmd("tabedit " .. vim.fn.fnameescape(res.file))
				local buf = vim.api.nvim_get_current_buf()
				local lnum = tonumber(res.lnum)
				local line_count = vim.api.nvim_buf_line_count(buf)
				if lnum > line_count then
					lnum = line_count
				end
				if lnum < 1 then
					lnum = 1
				end
				vim.api.nvim_win_set_cursor(0, { lnum, 0 })
			end
		end, { buffer = state.data.buf })

		vim.keymap.set("n", "q", function()
			if state.data.win and vim.api.nvim_win_is_valid(state.data.win) then
				M.clear_previews()
				vim.api.nvim_win_close(state.data.win, true)
				state.data.win = nil
			end
		end, { buffer = state.data.buf, nowait = true })
	end

	vim.cmd("rightbelow vsplit")
	state.data.win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_width(state.data.win, state.data.config.width or 40)
	vim.api.nvim_win_set_buf(state.data.win, state.data.buf)

	local opts = {
		number = false,
		relativenumber = false,
		winfixwidth = true,
		signcolumn = "no",
		foldcolumn = "0",
	}
	for k, v in pairs(opts) do
		vim.api.nvim_set_option_value(k, v, { scope = "local", win = state.data.win })
	end

	local init_q = state.data.last_query or ""
	vim.api.nvim_win_set_cursor(state.data.win, { 2, #query_prefix + #init_q })
	vim.cmd("startinsert!")
end

return M
