-- Emacs mode is Insert mode started from Normal mode. Emacs keys are mapped in its buffer until Insert mode ends.
-- Plain Insert mode and other buffers are unaffected.
local motion = require("emacs-mode.motion")
local edit = require("emacs-mode.edit")
local region = require("emacs-mode.region")
local fill = require("emacs-mode.fill")
local line_edit = require("emacs-mode.lines")
local keys = require("emacs-mode.keys")

local M = {}

local DESC = "Emacs mode"
local group = vim.api.nvim_create_augroup("emacs_mode", { clear = false })
local namespace = vim.api.nvim_create_namespace("emacs_mode")

local defaults = {
	start_key = false,
	-- Terminals send C-SPC as NUL, which Neovim reads as <C-@>. macOS may take C-SPC to switch the input source.
	set_mark = { "<C-Space>", "<C-@>" },
	-- Extra keys per command, as { command = { "<key>", ... } }, for keys the terminal sends differently.
	aliases = {},
	-- Hooks for a scrolling plugin and a completion plugin. See :help emacs-mode-hooks.
	scroll = {},
	completion = {},
}
local config = defaults

-- pending: the start key was pressed and Insert mode is about to begin.
-- active: the mode is on in this buffer and window.
local state = { pending = nil, active = nil }
-- Counts the keys typed while the mode is on. A command continues the previous one only if no other key came between.
local key_sequence = 0
local last_kill
local append_next
local vertical_goal
local last_yank
local last_cycle
local last_command
-- The value key_sequence had when the running command was typed, before it read any keys itself.
local command_key_sequence = 0
local spacing_cycle

local function cursor()
	local pos = vim.api.nvim_win_get_cursor(0)
	return { pos[1] - 1, pos[2] }
end

local function notify(message)
	vim.api.nvim_echo({ { message } }, false, {})
end

local editable, on_mode_changed, activate, restore, commands, close_completion
local scroll_busy, stop_when_left

local function emit(pattern)
	vim.api.nvim_exec_autocmds("User", { pattern = pattern, modeline = false })
end

-- The Normal mode mapping of start_key that was in place before setup, if any, and the callback of ours that
-- replaced it. A mapping of an earlier load of this module, left behind, is not worth keeping.
local start_key_mapping

local function global_normal_mapping(lhs)
	local raw = vim.keycode(lhs)
	for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
		if mapping.lhsraw == raw or mapping.lhsrawalt == raw then
			return mapping
		end
	end
end

local function map_start_key(start_key)
	local previous = global_normal_mapping(start_key)
	if previous and previous.desc == DESC then
		previous = nil
	end
	local function callback()
		return editable(0) and "<Cmd>lua require('emacs-mode').start()<CR>" or start_key
	end
	vim.keymap.set("n", start_key, callback, { expr = true, desc = DESC })
	start_key_mapping = { lhs = start_key, callback = callback, previous = previous }
end

-- A mapping that something else put in place of ours since setup() stays as it is.
local function unmap_start_key()
	local ours = start_key_mapping
	start_key_mapping = nil
	if not ours then
		return
	end
	local current = global_normal_mapping(ours.lhs)
	if not (current and current.callback == ours.callback) then
		return
	end
	vim.keymap.del("n", ours.lhs)
	if ours.previous then
		vim.fn.mapset("n", false, ours.previous)
	end
end

function M.setup(opts)
	M.teardown()
	config = vim.tbl_extend("force", defaults, opts or {})
	if config.start_key then
		map_start_key(config.start_key)
	end
	vim.api.nvim_create_autocmd("ModeChanged", { group = group, callback = on_mode_changed })
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = group,
		callback = function()
			if state.active then
				M.stop()
			end
		end,
	})
	-- Typed text and other changes end the selection. Cursor moves from other sources, such as the mouse, stretch it.
	vim.api.nvim_create_autocmd("TextChangedI", {
		group = group,
		callback = function(args)
			if state.active and region.changed(args.buf) then
				region.deactivate()
			end
		end,
	})
	vim.api.nvim_create_autocmd("CursorMovedI", {
		group = group,
		callback = function(args)
			if state.active then
				region.draw(args.buf, cursor())
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
		group = group,
		callback = function(args)
			if state.active and state.active.buf == args.buf then
				M.stop()
			end
		end,
	})
	vim.on_key(function(_, typed)
		if state.active and typed ~= "" then
			key_sequence = key_sequence + 1
		end
	end, namespace)
end

-- Keys are mapped after Insert mode starts. InsertEnter autocommands that map keys of their own, such as a
-- completion plugin's, have run by then.
function M.start()
	local buf = vim.api.nvim_get_current_buf()
	if state.active or not editable(buf) then
		return false
	end
	state.pending = { buf = buf, win = vim.api.nvim_get_current_win() }
	vim.cmd.startinsert()
	return true
end

function M.is_active()
	return state.active ~= nil
end

-- Keys after a prefix such as C-x are read here, not by mappings. A mapping times out after 'timeoutlen' and can
-- lose the key. Here the mode waits as long as it takes. Esc and C-g give up.
local function read_prefixed(prefix)
	notify(prefix.label .. "-")
	vim.cmd.redraw()
	local ok, char = pcall(vim.fn.getcharstr)
	vim.cmd("echo ''")
	if not ok or char == "" then
		return nil
	end
	local name = prefix.keys[char]
	if not name and char ~= vim.keycode("<Esc>") and char ~= vim.keycode("<C-g>") then
		notify(("%s %s is undefined"):format(prefix.label, vim.fn.keytrans(char)))
	end
	return name
end

local function execute(buf, name, command, shifted)
	local pos = cursor()
	if shifted then
		if not (region.is_active(buf) and region.kind() == "shift") then
			region.set_mark(buf, pos, true, "shift")
		end
	elseif command.motion and region.is_active(buf) and region.kind() == "shift" then
		region.deactivate()
	end
	if command.kind ~= "kill" then
		last_kill = nil
	end
	if command.kind ~= "vertical" then
		vertical_goal = nil
	end
	command.run(buf, pos)
	last_command = { name = name, key_sequence = key_sequence }
	if command.keeps_region or shifted then
		region.draw(buf, cursor(), true)
	else
		region.deactivate()
	end
end

function M.run(name, shifted)
	local active = state.active
	if not (active and active.buf == vim.api.nvim_get_current_buf()) then
		return
	end
	command_key_sequence = key_sequence
	local command = commands[name]
	-- A command that reads keys gets its closing <C-g>u from this function, after it has read them.
	local reads_keys = command.reads_key
	local ok, err = pcall(function()
		if command.prefix then
			name = read_prefixed(command.prefix)
			if not name then
				return
			end
			command = commands[name]
		end
		execute(active.buf, name, command, shifted)
	end)
	if reads_keys then
		vim.api.nvim_feedkeys(vim.keycode("<C-g>u"), "ni", false)
	end
	if not ok then
		error(err, 0)
	end
end

function M.close_completion()
	close_completion()
end

function M.stop()
	state.pending = nil
	local active = state.active
	if not active then
		return
	end
	state.active = nil
	last_kill = nil
	append_next = nil
	vertical_goal = nil
	last_yank = nil
	last_cycle = nil
	last_command = nil
	spacing_cycle = nil
	region.clear()
	restore(active)
	emit("EmacsModeLeave")
end

function M.teardown()
	M.stop()
	vim.api.nvim_clear_autocmds({ group = group })
	vim.on_key(nil, namespace)
	unmap_start_key()
end

function editable(buf)
	return vim.bo[buf].buftype == "" and vim.bo[buf].modifiable
end

local function in_normal_mode(mode)
	return mode == "n" or mode == "nt" or vim.startswith(mode, "t")
end

function scroll_busy()
	local busy = config.scroll.busy
	return busy ~= nil and busy() == true
end

-- Ends the mode if Neovim is still in Normal mode after the command that went there. A scroll step run from a timer
-- returns to Insert mode before scheduled callbacks run. Normal mode at that point means the mode was left.
function stop_when_left(active)
	vim.schedule(function()
		if state.active == active and in_normal_mode(vim.api.nvim_get_mode().mode) then
			M.stop()
		end
	end)
end

function on_mode_changed()
	local new = vim.v.event.new_mode
	local pending = state.pending
	if pending then
		state.pending = nil
		if
			new == "i"
			and pending.buf == vim.api.nvim_get_current_buf()
			and pending.win == vim.api.nvim_get_current_win()
		then
			activate(pending.buf, pending.win)
		end
		return
	end
	if not (state.active and in_normal_mode(new)) then
		return
	end
	local old = vim.v.event.old_mode
	if (vim.startswith(old, "i") or vim.startswith(old, "R")) and not scroll_busy() then
		M.stop()
	else
		-- i_CTRL-O passes through niI and the modes of its command, then returns to Insert mode. :normal also passes
		-- through Normal mode. Only :stopinsert and the like stay there.
		stop_when_left(state.active)
	end
end

-- <C-g>u on both sides makes each command its own undo step, separate from the text typed around it.
-- A command that reads a key would read the rest of the mapping. It gets the last <C-g>u from run() instead.
local function rhs(name, shifted)
	local own_keys = commands[name].keys
	if own_keys then
		return "<Cmd>lua require('emacs-mode').close_completion()<CR><C-g>u" .. own_keys
	end
	local run = ("<Cmd>lua require('emacs-mode').close_completion()<CR><C-g>u<Cmd>lua require('emacs-mode').run(%q, %s)<CR>"):format(
		name,
		shifted and "true" or "false"
	)
	return commands[name].reads_key and run or run .. "<C-g>u"
end

local function completion_open()
	if vim.fn.pumvisible() == 1 then
		return true
	end
	local visible = config.completion.visible
	return visible ~= nil and visible() == true
end

local function pass_through(lhs, mapping)
	local noremap = mapping and mapping.noremap == 1
	if mapping and mapping.callback then
		local ok, result = pcall(mapping.callback)
		if mapping.expr == 1 and ok and type(result) == "string" and result ~= "" then
			local typed = mapping.replace_keycodes == 1 and vim.keycode(result) or result
			vim.api.nvim_feedkeys(typed, noremap and "n" or "m", false)
		end
	elseif mapping and mapping.rhs and mapping.rhs ~= "" then
		-- Expand <SID> to the script that made the mapping, not to this one.
		local keys_to_feed = mapping.rhs:gsub("<SID>", ("<SNR>%d_"):format(mapping.sid or 0))
		if mapping.expr == 1 then
			local ok, result = pcall(vim.fn.eval, keys_to_feed)
			keys_to_feed = ok and tostring(result) or ""
		end
		vim.api.nvim_feedkeys(vim.keycode(keys_to_feed), noremap and "n" or "m", false)
	else
		vim.api.nvim_feedkeys(vim.keycode(lhs), "n", false)
	end
end

-- The keys in keys.completion check for an open menu first. An expr mapping cannot do that check: it would run
-- the completion plugin's own mapping with the text locked.
function M.completion_key(key, name, shifted)
	local lhs = "<" .. key .. ">"
	local active = state.active
	if not (active and active.buf == vim.api.nvim_get_current_buf()) then
		return
	end
	if completion_open() then
		pass_through(lhs, active.passed[lhs])
	else
		vim.api.nvim_feedkeys(vim.keycode(rhs(name, shifted)), "ni", false)
	end
end

local function key_table()
	local found = {}
	for lhs, name in pairs(keys.single) do
		found[lhs] = { name = name }
	end
	for lhs, name in pairs(keys.shifted) do
		found[lhs] = { name = name, shifted = true }
	end
	for lhs, prefix in pairs(keys.prefixes) do
		found[lhs] = { name = prefix.name }
	end
	for _, lhs in ipairs(config.set_mark) do
		found[lhs] = { name = "set_mark" }
	end
	for name, list in pairs(config.aliases) do
		if commands[name] then
			for _, lhs in ipairs(list) do
				found[lhs] = { name = name }
			end
		else
			vim.notify("emacs-mode: no command " .. name .. " to give keys to", vim.log.levels.WARN)
		end
	end
	return found
end

local function install(buf)
	local saved, passed = {}, {}
	vim.api.nvim_buf_call(buf, function()
		for lhs, entry in pairs(key_table()) do
			local mapping = vim.fn.maparg(lhs, "i", false, true)
			saved[lhs] = mapping.buffer == 1 and mapping or false
			passed[lhs] = next(mapping) ~= nil and mapping or nil
			local options = { buffer = buf, nowait = true, silent = true, desc = DESC }
			local keys_of_command = rhs(entry.name, entry.shifted)
			if keys.completion[lhs] then
				-- The name goes in without brackets. With them, Neovim would read it as a key.
				keys_of_command = ("<Cmd>lua require('emacs-mode').completion_key(%q, %q, %s)<CR>"):format(
					lhs:sub(2, -2),
					entry.name,
					entry.shifted and "true" or "false"
				)
			end
			vim.keymap.set("i", lhs, keys_of_command, options)
		end
	end)
	return saved, passed
end

function activate(buf, win)
	region.clear()
	local saved, passed = install(buf)
	state.active = { buf = buf, win = win, saved = saved, passed = passed }
	emit("EmacsModeEnter")
end

local function ours(mapping)
	return mapping.buffer == 1 and mapping.desc == DESC
end

function restore(active)
	if active.unwrapped and vim.api.nvim_win_is_valid(active.win) and not vim.wo[active.win].wrap then
		vim.wo[active.win].wrap = true
	end
	local buf = active.buf
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_buf_call(buf, function()
		for lhs, mapping in pairs(active.saved) do
			if ours(vim.fn.maparg(lhs, "i", false, true)) then
				vim.api.nvim_buf_del_keymap(buf, "i", lhs)
				if mapping then
					vim.fn.mapset("i", false, mapping)
				end
			end
		end
	end)
end

function close_completion()
	local hooks = config.completion
	if hooks.visible and hooks.close and hooks.visible() then
		hooks.close()
	end
	if vim.fn.pumvisible() == 1 then
		vim.api.nvim_feedkeys(vim.keycode("<C-e>"), "ni", false)
	end
end

local CANCELLED = "\1"

local function ask(prompt, default)
	local pos = cursor()
	local ok, answer = pcall(vim.fn.input, { prompt = prompt, default = default or "", cancelreturn = CANCELLED })
	-- Some configurations pull the cursor back from the end of the line after a prompt.
	if not vim.deep_equal(cursor(), pos) then
		edit.set_cursor(pos)
	end
	if not ok or answer == CANCELLED then
		return nil
	end
	return answer
end

local function ask_number(prompt, default)
	local answer = ask(prompt, default)
	if not answer then
		return nil
	end
	local number = tonumber(vim.trim(answer))
	if not number or number ~= math.floor(number) then
		notify("Not an integer: " .. answer)
		return nil
	end
	return number
end

local function moving(target)
	return {
		keeps_region = true,
		motion = true,
		run = function(buf, pos)
			local to = target(buf, pos)
			if to then
				edit.set_cursor(to)
			end
		end,
	}
end

local function deleting(from, to, honors_region)
	return {
		run = function(buf, pos)
			local first, last = from(buf, pos), to(buf, pos)
			if honors_region then
				local start, finish = region.bounds(buf, pos)
				if start then
					first, last = start, finish
				end
			end
			if first and last then
				edit.delete(first, last)
			end
		end,
	}
end

local function here(_, pos)
	return pos
end

local function before(a, b)
	return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
end

local function kill_continues(buf, pos)
	if append_next and append_next.key_sequence == command_key_sequence - 1 then
		return edit.killed() ~= nil
	end
	return last_kill ~= nil
		and last_kill.buf == buf
		and last_kill.tick == vim.b.changedtick
		and vim.deep_equal(last_kill.pos, pos)
		and last_kill.key_sequence == command_key_sequence - 1
end

local function remember_kill(buf)
	append_next = nil
	last_kill = { buf = buf, tick = vim.b.changedtick, pos = cursor(), key_sequence = key_sequence }
end

-- target may also return true or false: whether the kill goes in front of the previous one. Emacs decides that the
-- other way round for a region.
local function killing(target)
	return {
		kind = "kill",
		run = function(buf, pos)
			-- This check comes before target(), which may read a key of its own (M-z).
			local continued = kill_continues(buf, pos)
			local to, in_front = target(buf, pos)
			if to then
				if in_front == nil then
					in_front = before(to, pos)
				end
				edit.store(edit.delete(pos, to), continued and (in_front and "prepend" or "append") or "replace")
			elseif not continued then
				last_kill = nil
				return
			end
			remember_kill(buf)
		end,
	}
end

-- Runs a Normal mode command from Insert mode and returns 'curswant'. Without 'virtualedit', a Normal mode command
-- cannot put the cursor after the last character. Setting it recomputes 'curswant'. Therefore prepare() runs after
-- it is set, and 'curswant' is read before it is restored.
local function normal(keys_to_press, prepare)
	local win = vim.api.nvim_get_current_win()
	local virtualedit = vim.api.nvim_get_option_value("virtualedit", { scope = "local", win = win })
	local function set_virtualedit(value)
		vim.api.nvim_cmd({ cmd = "setlocal", args = { "virtualedit=" .. value }, mods = { noautocmd = true } }, {})
	end
	set_virtualedit("onemore")
	if prepare then
		prepare()
	end
	-- Autocommands are off. Otherwise the switch to Normal mode here would end the mode.
	local ok, err = pcall(vim.api.nvim_cmd, {
		cmd = "normal",
		args = { vim.keycode(keys_to_press) },
		bang = true,
		mods = { noautocmd = true },
	}, {})
	local curswant = vim.fn.winsaveview().curswant
	set_virtualedit(virtualedit)
	assert(ok, err)
	return curswant
end

-- Insert mode resets 'curswant' after every command, so a run of gj and gk restores its target column from
-- vertical_goal. A goal column set with C-x C-n takes precedence.
local function screen_line(direction)
	return {
		kind = "vertical",
		keeps_region = true,
		motion = true,
		run = function(buf, pos)
			local win = vim.api.nvim_get_current_win()
			local goal_column = vim.b[buf].emacs_goal_column
			local curswant = normal("g" .. direction, function()
				local goal = vertical_goal
				if goal_column then
					vim.fn.winrestview({ curswant = goal_column })
				elseif
					goal
					and goal.win == win
					and goal.tick == vim.b.changedtick
					and vim.deep_equal(goal.pos, pos)
				then
					vim.fn.winrestview({ curswant = goal.curswant })
				end
			end)
			vertical_goal = { win = win, tick = vim.b.changedtick, pos = cursor(), curswant = curswant }
		end,
	}
end

local function cycling(steps)
	local command = { keeps_region = true }
	local function step_with(step)
		if type(step) == "string" then
			normal(step)
		else
			step()
		end
	end
	function command.run()
		local cycle = last_cycle
		local step = 1
		if cycle and cycle.command == command and cycle.key_sequence == command_key_sequence - 1 then
			step = cycle.step % #steps + 1
		end
		step_with(steps[step])
		last_cycle = { command = command, step = step, key_sequence = key_sequence }
	end
	return command
end

local function converting(convert)
	return {
		run = function(buf, pos)
			local to = motion.forward_word(buf, pos)
			if to then
				edit.replace(pos, to, convert(edit.text(pos, to)))
			end
		end,
	}
end

-- As in Emacs, the mark is used even after the selection was dropped.
local function converting_region(convert)
	return {
		run = function(buf, pos)
			local mark = region.mark(buf)
			if not mark then
				notify("The mark is not set now, so there is no region")
				return
			end
			local from, to = edit.ordered(mark, pos)
			local text = edit.text(from, to)
			local converted = convert(text)
			if converted == text then
				return
			end
			local after = edit.splice(from, to, converted)
			-- A mark at the end of the replaced text would move to its start. Put it after the new text.
			if vim.deep_equal(mark, to) then
				region.move_mark(buf, after)
			end
			edit.set_cursor(vim.deep_equal(pos, to) and after or from)
		end,
	}
end

local function smooth(keys_to_press)
	return function()
		local run = config.scroll.run
		if not (run and run(keys_to_press)) then
			normal(keys_to_press)
		end
	end
end

-- With a goal column set, scroll at once and move the cursor to the goal column. A scroll hook may scroll later, from
-- a timer.
local function paging(keys_to_press)
	local scroll = smooth(keys_to_press)
	return function(buf)
		local goal = vim.b[buf].emacs_goal_column
		if goal then
			normal(keys_to_press)
			edit.set_cursor(motion.column_position(buf, cursor()[1], goal))
		else
			scroll()
		end
	end
end

local scroll_down = paging("<C-f>")
local scroll_up = paging("<C-b>")

-- Scrolls sideways by the window width less 2, like Emacs. Wrapped lines cannot scroll sideways. Wrapping is turned
-- off for the window until the text is back at the left or the mode ends.
local function scrolling_sideways(keys_to_press)
	return {
		keeps_region = true,
		run = function()
			local win = vim.api.nvim_get_current_win()
			local active = state.active
			if vim.wo[win].wrap then
				if keys_to_press == "zh" then
					return
				end
				vim.wo[win].wrap = false
				active.unwrapped = true
			end
			local info = vim.fn.getwininfo(win)[1]
			normal(math.max(info.width - info.textoff - 2, 1) .. keys_to_press)
			if active.unwrapped and vim.fn.winsaveview().leftcol == 0 then
				vim.wo[win].wrap = true
				active.unwrapped = false
			end
		end,
	}
end

local function fill_options(buf)
	local width = vim.b[buf].emacs_fill_column
	if not width then
		width = vim.bo[buf].textwidth > 0 and vim.bo[buf].textwidth or 70
	end
	return { width = width, prefix = vim.b[buf].emacs_fill_prefix or "" }
end

local function fill_rows(buf, pos)
	local first, last = region.bounds(buf, pos)
	if first then
		-- A selection ending at the start of a line excludes that line.
		return first[1], (last[2] == 0 and last[1] > first[1]) and last[1] - 1 or last[1]
	end
	local total = vim.api.nvim_buf_line_count(buf)
	for row = pos[1], total - 1 do
		if not vim.api.nvim_buf_get_lines(buf, row, row + 1, true)[1]:find("^[ \t]*$") then
			return row, row
		end
	end
end

local function fill_paragraphs(buf, pos)
	local from, to = fill_rows(buf, pos)
	if not from then
		return
	end
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
	local edits, note = fill.fill(lines, from, to, fill_options(buf))
	if #edits == 0 then
		if note then
			notify("Not filled: " .. note)
		end
		return
	end
	-- Keep the cursor at the same place in the text. Paragraphs above it may gain or lose lines.
	local target, count
	for _, change in ipairs(edits) do
		if pos[1] >= change.first and pos[1] <= change.last then
			target, count = change, change.count(pos[1] - change.first + 1, pos[2])
		end
	end
	local shift_above = function(row)
		local shift = 0
		for _, change in ipairs(edits) do
			if change.last < row then
				shift = shift + #change.lines - (change.last - change.first + 1)
			end
		end
		return shift
	end
	for _, change in ipairs(edits) do
		vim.api.nvim_buf_set_lines(buf, change.first, change.last + 1, true, change.lines)
	end
	if target then
		local index, col = target.place(count)
		edit.set_cursor({ target.first + shift_above(target.first) + index - 1, col })
	else
		edit.set_cursor({ pos[1] + shift_above(pos[1]), pos[2] })
	end
end

local function preview(text)
	local shown = text:gsub("\n", "↵")
	if vim.fn.strchars(shown) > 80 then
		shown = vim.fn.strcharpart(shown, 0, 79) .. "…"
	end
	return shown
end

-- A vim.ui.select() prompt may be answered later. Run fn only if buf is unchanged by then.
local function if_unchanged(buf, win, tick, fn)
	if
		not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf)
	then
		return
	end
	if vim.api.nvim_buf_get_changedtick(buf) == tick then
		vim.api.nvim_win_call(win, fn)
	end
end

local function choose_kill(buf, pos)
	local entries = edit.entries()
	if #entries == 0 then
		return
	end
	local win, tick = vim.api.nvim_get_current_win(), vim.b[buf].changedtick
	local items = {}
	for index, text in ipairs(entries) do
		items[index] = { index = index, text = text }
	end
	vim.ui.select(items, {
		prompt = "Yank from kill ring:",
		format_item = function(item)
			return ("%d  %s"):format(item.index, preview(item.text))
		end,
	}, function(item)
		if_unchanged(buf, win, tick, function()
			if not item then
				-- Some configurations pull the cursor back from the end of the line after a prompt.
				edit.set_cursor(pos)
				return
			end
			edit.insert(pos, edit.select(item.index))
			if state.active and state.active.buf == buf then
				region.set_mark(buf, pos, false)
			end
		end)
	end)
end

local function join_lines(buf, pos)
	local prefix = vim.b[buf].emacs_fill_prefix or ""
	local first, last = region.bounds(buf, pos)
	local joined
	if first then
		for row = last[1], first[1] + 1, -1 do
			joined = line_edit.join_previous(row, prefix)
		end
	elseif pos[1] > 0 then
		joined = line_edit.join_previous(pos[1], prefix)
	end
	if joined then
		edit.set_cursor(joined)
	end
end

local function deleting_blank_lines(buf, pos)
	local row = line_edit.delete_blank(pos[1])
	local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, true)[1]
	edit.set_cursor({ row, row == pos[1] and math.min(pos[2], #text) or 0 })
end

commands = {
	forward_char = moving(motion.forward_char),
	backward_char = moving(motion.backward_char),
	next_line = screen_line("j"),
	previous_line = screen_line("k"),
	line_start = moving(motion.line_start),
	line_end = moving(motion.line_end),
	forward_word = moving(motion.forward_word),
	backward_word = moving(motion.backward_word),
	buffer_start = moving(motion.buffer_start),
	buffer_end = moving(motion.buffer_end),
	backward_paragraph = moving(motion.backward_paragraph),
	forward_paragraph = moving(motion.forward_paragraph),
	backward_sentence = moving(motion.backward_sentence),
	forward_sentence = moving(motion.forward_sentence),
	back_to_indentation = moving(motion.back_to_indentation),
	goto_prefix = { reads_key = true, prefix = keys.prefixes["<M-g>"] },
	ctl_x = { reads_key = true, prefix = keys.prefixes["<C-x>"] },
	goto_line = {
		reads_key = true,
		keeps_region = true,
		motion = true,
		run = function(buf)
			local number = ask_number("Goto line: ")
			if number then
				local row = math.max(number, 1) - 1
				local last = vim.api.nvim_buf_line_count(buf) - 1
				if row > last then
					edit.set_cursor({ last, #vim.api.nvim_buf_get_lines(buf, last, last + 1, true)[1] })
				else
					edit.set_cursor({ row, 0 })
				end
			end
		end,
	},
	goto_char = {
		reads_key = true,
		keeps_region = true,
		motion = true,
		run = function(buf)
			local number = ask_number("Goto char: ")
			if number then
				edit.set_cursor(motion.char_position(buf, number))
			end
		end,
	},
	move_to_column = {
		reads_key = true,
		keeps_region = true,
		motion = true,
		run = function(buf, pos)
			local number = ask_number("Move to column: ")
			if number then
				edit.set_cursor(motion.column_position(buf, pos[1], math.max(number, 0)))
			end
		end,
	},
	set_goal_column = {
		keeps_region = true,
		run = function(buf, pos)
			local column = motion.display_column(buf, pos)
			if vim.b[buf].emacs_goal_column == column then
				vim.b[buf].emacs_goal_column = nil
				notify("No goal column")
			else
				vim.b[buf].emacs_goal_column = column
				notify("Goal column " .. column)
			end
		end,
	},
	delete_char = deleting(here, motion.forward_char),
	delete_forward_char = deleting(here, motion.forward_char, true),
	delete_backward_char = deleting(motion.backward_char, here, true),
	kill_line_start = killing(motion.line_start),
	kill_line_end = killing(motion.kill_line_end),
	kill_word = killing(motion.forward_word),
	backward_kill_word = killing(motion.backward_word),
	backward_kill_sentence = killing(motion.backward_sentence),
	-- A continued kill gets the part before the cursor prepended and the part after it appended.
	kill_whole_line = {
		kind = "kill",
		run = function(buf, pos)
			local continued = kill_continues(buf, pos)
			local start = { pos[1], 0 }
			local finish = { pos[1] + 1, 0 }
			if pos[1] == vim.api.nvim_buf_line_count(buf) - 1 then
				finish = motion.line_end(buf, { pos[1], 0 }) or start
			end
			if vim.deep_equal(start, finish) then
				if not continued then
					last_kill = nil
				end
				return
			end
			local front, back = edit.text(start, pos), edit.text(pos, finish)
			edit.delete(start, finish)
			if continued then
				edit.store(front, "prepend")
				edit.store(back, "append")
			else
				edit.store(front .. back, "replace")
			end
			remember_kill(buf)
		end,
	},
	yank = {
		run = function(buf, pos)
			local text = edit.to_yank()
			if text then
				local to = edit.insert(pos, text)
				region.set_mark(buf, pos, false)
				last_yank = { buf = buf, from = pos, to = to, tick = vim.b.changedtick, key_sequence = key_sequence }
			end
		end,
	},
	yank_pop = {
		reads_key = true,
		run = function(buf, pos)
			local yank = last_yank
			if
				not yank
				or yank.buf ~= buf
				or yank.tick ~= vim.b.changedtick
				or not vim.deep_equal(yank.to, pos)
				or yank.key_sequence ~= command_key_sequence - 1
			then
				choose_kill(buf, pos)
				return
			end
			local text = edit.rotate()
			edit.delete(yank.from, yank.to)
			local to = edit.insert(yank.from, text)
			last_yank = { buf = buf, from = yank.from, to = to, tick = vim.b.changedtick, key_sequence = key_sequence }
		end,
	},
	append_next_kill = {
		keeps_region = true,
		run = function()
			append_next = { key_sequence = key_sequence }
			notify("If the next command is a kill, it will append")
		end,
	},
	scroll_down = { keeps_region = true, motion = true, run = scroll_down },
	scroll_up = { keeps_region = true, motion = true, run = scroll_up },
	scroll_left = scrolling_sideways("zl"),
	scroll_right = scrolling_sideways("zh"),
	recenter = cycling({ smooth("zz"), smooth("zt"), smooth("zb") }),
	-- Emacs puts the cursor at the start of the line
	move_to_window_line = vim.tbl_extend("force", cycling({ "M0", "H0", "L0" }), { motion = true }),
	set_mark = {
		keeps_region = true,
		run = function(buf, pos)
			local mark = region.mark(buf)
			local again = last_command
				and last_command.name == "set_mark"
				and last_command.key_sequence == command_key_sequence - 1
			if mark and again then
				if region.is_active(buf) then
					region.deactivate()
				else
					region.activate(buf, "mark")
				end
			elseif mark and vim.deep_equal(mark, pos) then
				region.activate(buf, "mark")
			else
				region.set_mark(buf, pos, true, "mark")
			end
		end,
	},
	-- Without a selection, C-w kills the word before the cursor, as in Readline and Vim.
	kill_region = killing(function(buf, pos)
		if region.is_active(buf) then
			local mark = region.mark(buf)
			if vim.deep_equal(mark, pos) then
				return nil
			end
			return mark, before(pos, mark)
		end
		return motion.backward_word(buf, pos)
	end),
	copy_region = {
		run = function(buf, pos)
			local first, last = region.bounds(buf, pos)
			if first then
				edit.store(edit.text(first, last), "replace")
			end
		end,
	},
	-- Only ends the selection. The mark stays.
	keyboard_quit = { run = function() end },
	mark_paragraph = {
		keeps_region = true,
		run = function(buf, pos)
			if region.is_active(buf) then
				local to = motion.forward_paragraph(buf, region.mark(buf))
				if to then
					region.move_mark(buf, to)
				end
				return
			end
			local to = motion.forward_paragraph(buf, pos) or pos
			region.set_mark(buf, to, true, "mark")
			edit.set_cursor(motion.backward_paragraph(buf, to) or to)
		end,
	},
	mark_word = {
		keeps_region = true,
		run = function(buf, pos)
			if region.is_active(buf) then
				local mark = region.mark(buf)
				local step = before(mark, pos) and motion.backward_word or motion.forward_word
				local to = step(buf, mark)
				if to then
					region.move_mark(buf, to)
				end
			else
				region.set_mark(buf, motion.forward_word(buf, pos) or pos, true, "mark")
			end
		end,
	},
	mark_whole_buffer = {
		keeps_region = true,
		run = function(buf)
			local last = vim.api.nvim_buf_line_count(buf) - 1
			region.set_mark(buf, { last, #vim.api.nvim_buf_get_lines(buf, last, last + 1, true)[1] }, true, "mark")
			edit.set_cursor({ 0, 0 })
		end,
	},
	exchange_point_and_mark = {
		keeps_region = true,
		run = function(buf, pos)
			local mark = region.mark(buf)
			if not mark then
				notify("No mark set in this buffer")
				return
			end
			local kind = region.is_active(buf) and region.kind() or "mark"
			region.set_mark(buf, pos, true, kind)
			edit.set_cursor(mark)
		end,
	},
	transpose_chars = {
		run = function(buf, pos)
			local middle = pos
			if pos[2] >= #vim.api.nvim_buf_get_lines(buf, pos[1], pos[1] + 1, true)[1] then
				middle = motion.backward_char(buf, pos) or pos
			end
			local left, right = motion.backward_char(buf, middle), motion.forward_char(buf, middle)
			if left and right then
				edit.set_cursor(edit.splice(left, right, edit.text(middle, right) .. edit.text(left, middle)))
			end
		end,
	},
	transpose_words = {
		run = function(buf, pos)
			-- backward_word stops at the start of the buffer even before blanks or punctuation. Find the start of the first
			-- word from its end instead.
			local end1 = motion.forward_word(buf, motion.backward_word(buf, pos) or pos)
			local start1 = end1 and motion.backward_word(buf, end1)
			local end2 = end1 and motion.forward_word(buf, end1)
			local start2 = end2 and motion.backward_word(buf, end2)
			if not (start2 and not before(start2, end1)) then
				return
			end
			local first, between, second = edit.text(start1, end1), edit.text(end1, start2), edit.text(start2, end2)
			edit.replace(start1, end2, second .. between .. first)
		end,
	},
	transpose_lines = {
		run = function(_, pos)
			local after = line_edit.transpose(pos[1])
			if after then
				edit.set_cursor(after)
			end
		end,
	},
	upcase_word = converting(vim.fn.toupper),
	downcase_word = converting(vim.fn.tolower),
	capitalize_word = converting(function(text)
		return vim.fn.substitute(vim.fn.tolower(text), [[\k]], [[\u&]], "")
	end),
	upcase_region = converting_region(vim.fn.toupper),
	downcase_region = converting_region(vim.fn.tolower),
	delete_horizontal_space = deleting(function(buf, pos)
		return (motion.blanks_around(buf, pos))
	end, function(buf, pos)
		return select(2, motion.blanks_around(buf, pos))
	end),
	cycle_spacing = {
		run = function(buf, pos)
			local repeated = last_command
				and last_command.name == "cycle_spacing"
				and last_command.key_sequence == command_key_sequence - 1
				and spacing_cycle
				and spacing_cycle.buf == buf
				and spacing_cycle.tick == vim.b.changedtick
			if not repeated then
				local from, to = motion.space_around(buf, pos, true)
				spacing_cycle = { buf = buf, original = pos, blanks = edit.text(from, to), step = 0 }
			else
				local from, to = motion.space_around(buf, pos, true)
				edit.splice(from, to, spacing_cycle.blanks)
				edit.set_cursor(spacing_cycle.original)
				pos = spacing_cycle.original
			end
			spacing_cycle.step = spacing_cycle.step % 3 + 1
			local from, to = motion.blanks_around(buf, pos)
			if spacing_cycle.step == 1 and edit.text(from, to) ~= " " then
				edit.set_cursor(edit.splice(from, to, " "))
			elseif spacing_cycle.step == 2 then
				edit.delete(from, to)
			end
			spacing_cycle.tick = vim.b[buf].changedtick
		end,
	},
	delete_indentation = { run = join_lines },
	split_line = {
		run = function(buf, pos)
			edit.set_cursor(line_edit.split(pos, vim.b[buf].emacs_fill_prefix or ""))
		end,
	},
	delete_blank_lines = { run = deleting_blank_lines },
	fill_paragraph = { run = fill_paragraphs },
	set_fill_column = {
		reads_key = true,
		run = function(buf, pos)
			local width = fill_options(buf).width
			local number =
				ask_number(("Change fill-column from %d to: "):format(width), tostring(motion.display_column(buf, pos)))
			if number and number >= 1 then
				vim.b[buf].emacs_fill_column = number
				notify(("Fill column set to %d (was %d)"):format(number, width))
			end
		end,
	},
	set_fill_prefix = {
		run = function(buf, pos)
			local prefix = vim.api.nvim_buf_get_lines(buf, pos[1], pos[1] + 1, true)[1]:sub(1, pos[2])
			if prefix == "" then
				vim.b[buf].emacs_fill_prefix = nil
				notify("fill-prefix canceled")
			else
				vim.b[buf].emacs_fill_prefix = prefix
				notify(('fill-prefix: "%s"'):format(prefix))
			end
		end,
	},
	zap_to_char = vim.tbl_extend(
		"force",
		killing(function(buf, pos)
			local ok, char = pcall(vim.fn.getcharstr)
			return ok and char ~= "" and motion.after_next(buf, pos, char) or nil
		end),
		{ reads_key = true }
	),
	kill_sentence = killing(motion.forward_sentence),
	-- Vim's search from i_CTRL-O shows matches while typing and returns to the mode at the match.
	search_forward = { keys = "<C-o>/" },
	search_backward = { keys = "<C-o>?" },
	undo = {
		run = function()
			vim.cmd("silent! undo")
		end,
	},
	redo = {
		run = function()
			vim.cmd("silent! redo")
		end,
	},
}

return M
