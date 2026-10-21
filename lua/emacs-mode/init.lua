-- Emacs editing mode: Insert mode entered with a key of Normal mode, with Emacs keys mapped to its buffer
-- until Insert mode ends. Plain Insert mode and other buffers are left alone.
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
	-- the Normal mode key that starts the mode; none by default
	start_key = false,
	-- C-SPC reaches Neovim as <C-@> from terminals that send it as NUL; macOS may take it for the input source
	set_mark = { "<C-Space>", "<C-@>" },
	-- milliseconds of neoscroll's animation for C-v, M-v and C-l, when neoscroll is loaded
	scroll_duration = 100,
	-- more keys for a command, as { command = { "<key>", ... } }, for what a terminal sends otherwise
	aliases = {},
}
local config = defaults

-- pending: `e` was pressed and Insert mode is about to start; active: the mode is on in this buffer and window
local state = { pending = nil, active = nil }
-- counts the keys typed while the mode is on; a kill continues the previous one only when no other key came between
local key_sequence = 0
local last_kill
-- set by C-M-w: the next kill joins the previous one
local append_next
-- the column C-n and C-p aim at, kept while they move the cursor one after another
local vertical_goal
-- where C-y or M-y put the text last; M-y replaces it when it comes right after them
local last_yank
-- the step C-l or M-r took last; pressed again right after, they go on to the next step
local last_cycle
-- the command that ran last and the key it ended with; some commands go on from themselves when pressed again
local previous
-- the count of keys when the running command was typed, before it read keys of its own
local started = 0
-- the blanks M-SPC started from, which it brings back after its other steps
local spacing

local function cursor()
	local pos = vim.api.nvim_win_get_cursor(0)
	return { pos[1] - 1, pos[2] }
end

local function notify(message)
	vim.api.nvim_echo({ { message } }, false, {})
end

-- defined below, in the order the mode goes through them
local editable, on_mode_changed, activate, restore, commands, close_completion
local smooth_scrolling, stop_when_left

-- opts: start_key, set_mark, scroll_duration and aliases, as in `defaults`
function M.setup(opts)
	M.teardown()
	config = vim.tbl_extend("force", defaults, opts or {})
	local start_key = config.start_key
	if start_key then
		-- buffers that are not for editing text keep what the key does there
		vim.keymap.set("n", start_key, function()
			return editable(0) and "<Cmd>lua require('emacs-mode').start()<CR>" or start_key
		end, { expr = true, desc = DESC })
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
	-- typed text and other changes end the selection; moves of other keys, such as the mouse, stretch it
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

-- Enters Insert mode at the cursor like `i`; the keys are mapped once Insert mode has started, after the
-- InsertEnter autocommands that map keys of their own (blink.cmp does).
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

-- The keys that follow a prefix such as C-x are read here, not by mappings, so that nothing waits for 'timeoutlen'
-- and no key is lost: the mode waits for the key as long as it takes. Esc and C-g give up.
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
		-- a selection of shifted moves goes on; otherwise one starts here
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
	previous = { name = name, key_sequence = key_sequence }
	-- moves stretch the selection; anything else ends it, and the mark stays
	if command.keeps_region or shifted then
		region.draw(buf, cursor(), true)
	else
		region.deactivate()
	end
end

-- shifted: the key is a move with Shift, which starts a selection
function M.run(name, shifted)
	local active = state.active
	if not (active and active.buf == vim.api.nvim_get_current_buf()) then
		return
	end
	started = key_sequence
	local command = commands[name]
	-- a command that reads keys leaves the last <C-g>u of its mapping to this function, once it has read them
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
	previous = nil
	spacing = nil
	region.clear()
	restore(active)
	vim.cmd.redrawstatus()
end

function M.teardown()
	M.stop()
	vim.api.nvim_clear_autocmds({ group = group })
	vim.on_key(nil, namespace)
	local start_key = config.start_key
	if start_key and vim.fn.maparg(start_key, "n", false, true).desc == DESC then
		vim.keymap.del("n", start_key)
	end
end

-- Entering and leaving

function editable(buf)
	return vim.bo[buf].buftype == "" and vim.bo[buf].modifiable
end

local function in_normal_mode(mode)
	return mode == "n" or mode == "nt" or vim.startswith(mode, "t")
end

-- neoscroll animates C-v, M-v and C-l with :normal from a timer, which passes through Normal mode every step
function smooth_scrolling()
	local scroll = package.loaded["neoscroll.scroll"]
	return scroll ~= nil and scroll.scrolling
end

-- Ends the mode if Neovim is still in Normal mode once the command that went there is over. A step of
-- neoscroll's animation comes back to Insert mode before anything scheduled runs, so Normal mode then means
-- the mode was left.
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
	if (vim.startswith(old, "i") or vim.startswith(old, "R")) and not smooth_scrolling() then
		M.stop()
	else
		-- i_CTRL-O passes through niI and the modes of its command, also Normal mode for :normal, and then comes
		-- back to Insert mode; only :stopinsert and the like stay in Normal mode
		stop_when_left(state.active)
	end
end

-- <C-g>u on both sides makes every command its own undo step without joining the text typed around it
-- A command that reads a key would read the rest of the mapping instead, so it gets the last <C-g>u itself.
-- A command with keys of its own runs them instead.
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
	if package.loaded["blink.cmp"] then
		local ok, visible = pcall(function()
			return require("blink.cmp").is_visible()
		end)
		return ok and visible
	end
	return false
end

-- What a key does on an open completion menu: what was mapped to it, in the buffer or globally, or the key itself.
local function pass_through(lhs, mapping)
	local noremap = mapping and mapping.noremap == 1
	if mapping and mapping.callback then
		local ok, result = pcall(mapping.callback)
		if mapping.expr == 1 and ok and type(result) == "string" and result ~= "" then
			local typed = mapping.replace_keycodes == 1 and vim.keycode(result) or result
			vim.api.nvim_feedkeys(typed, noremap and "n" or "m", false)
		end
	elseif mapping and mapping.rhs and mapping.rhs ~= "" then
		-- <SID> of the script that made the mapping, which this function is not in
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

-- The keys of `keys.completion` check for a menu first. The check is not made in an expr mapping, which would
-- run what a completion plugin maps with the text locked.
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

-- every key of the mode with the command it runs, as lhs = { name, shifted }
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
			-- a key given twice would save the mode's own mapping and put it back when the mode ends
			if saved[lhs] == nil then
				local mapping = vim.fn.maparg(lhs, "i", false, true)
				saved[lhs] = mapping.buffer == 1 and mapping or false
				passed[lhs] = next(mapping) ~= nil and mapping or nil
				local options = { buffer = buf, nowait = true, silent = true, desc = DESC }
				local keys_of_command = rhs(entry.name, entry.shifted)
				if keys.completion[lhs] then
					-- without the brackets, which would be read as a key
					keys_of_command = ("<Cmd>lua require('emacs-mode').completion_key(%q, %q, %s)<CR>"):format(
						lhs:sub(2, -2),
						entry.name,
						entry.shifted and "true" or "false"
					)
				end
				vim.keymap.set("i", lhs, keys_of_command, options)
			end
		end
	end)
	return saved, passed
end

-- A block cursor like Normal mode and Emacs, set in 'guicursor' after what is there so the rest stays
local function block_cursor()
	local guicursor = vim.o.guicursor
	if guicursor == "" then
		return nil
	end
	local block = guicursor .. ",i-ci:block"
	vim.o.guicursor = block
	return { saved = guicursor, set = block }
end

function activate(buf, win)
	region.clear()
	local saved, passed = install(buf)
	state.active = { buf = buf, win = win, saved = saved, passed = passed, cursor = block_cursor() }
	vim.cmd.redrawstatus()
end

local function ours(mapping)
	return mapping.buffer == 1 and mapping.desc == DESC
end

-- Puts back the cursor and what was mapped before, unless something changed them in the meantime.
function restore(active)
	local cursor_shape = active.cursor
	local scroll = package.loaded["neoscroll.scroll"]
	if cursor_shape and vim.o.guicursor == cursor_shape.set then
		vim.o.guicursor = cursor_shape.saved
	elseif cursor_shape and scroll and scroll.scrolling and scroll.guicursor == cursor_shape.set then
		-- neoscroll hides the cursor while it scrolls and puts back what it saved when it is done
		scroll.guicursor = cursor_shape.saved
	end
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

-- Commands

function close_completion()
	if package.loaded["blink.cmp"] then
		-- blink.cmp's own cancel() is deferred and would undo the preview after this command has edited the text
		pcall(function()
			if require("blink.cmp").is_visible() then
				require("blink.cmp.completion.list").undo_preview()
				require("blink.cmp.completion.trigger").hide()
			end
		end)
	end
	if vim.fn.pumvisible() == 1 then
		vim.api.nvim_feedkeys(vim.keycode("<C-e>"), "ni", false)
	end
end

-- Asks for a line of text with Vim's `input()`, and returns nil when it is given up with Esc.
local CANCELLED = "\1"
local function ask(prompt, default)
	local pos = cursor()
	local ok, answer = pcall(vim.fn.input, { prompt = prompt, default = default or "", cancelreturn = CANCELLED })
	-- some configurations leave the cursor pulled back from the end of the line after a prompt
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

-- deletes the text between the cursor and target, or the selection when honors_region and there is one
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

-- whether a kill goes on from the one before: it came right after it, with the cursor where it left it, or after C-M-w
local function kill_continues(buf, pos)
	if append_next and append_next.key_sequence == started - 1 then
		return edit.killed() ~= nil
	end
	return last_kill ~= nil
		and last_kill.buf == buf
		and last_kill.tick == vim.b.changedtick
		and vim.deep_equal(last_kill.pos, pos)
		and last_kill.key_sequence == started - 1
end

local function remember_kill(buf)
	append_next = nil
	last_kill = { buf = buf, tick = vim.b.changedtick, pos = cursor(), key_sequence = key_sequence }
end

-- Kills the text between the cursor and the position target returns; a kill in a row adds backward kills in front.
-- target can return true or false as well to tell whether the kill goes in front, which Emacs decides the other way
-- round for a region.
local function killing(target)
	return {
		kind = "kill",
		run = function(buf, pos)
			-- before target(), which may read a key of its own (M-z)
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

-- Runs a Normal mode command from Insert mode and returns 'curswant'. Normal mode commands cannot put the cursor
-- after the last character without 'virtualedit'. Setting it recomputes 'curswant', so prepare() runs after it
-- is set and 'curswant' is read before it is restored.
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
	-- without autocommands, Normal mode here is not taken for the end of Insert mode
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

-- gj and gk keep the target column in 'curswant', which Insert mode resets after every command. A goal column
-- set with C-x C-n is the target instead.
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

-- Like Emacs' recenter-positions: the middle of the window first, then the top and the bottom.
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
		if cycle and cycle.command == command and cycle.key_sequence == started - 1 then
			step = cycle.step % #steps + 1
		end
		step_with(steps[step])
		last_cycle = { command = command, step = step, key_sequence = key_sequence }
	end
	return command
end

-- Changes the next word with convert(text) and moves after it, as M-u, M-l and M-c do.
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

-- Changes the text between the mark and the cursor with convert(text), as C-x C-u and C-x C-l do. The mark is
-- used also when the selection was dropped, as in Emacs.
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
			-- the mark stays before text put at it, so one at the end of the text goes to the start
			if vim.deep_equal(mark, to) then
				region.move_mark(buf, after)
			end
			edit.set_cursor(vim.deep_equal(pos, to) and after or from)
		end,
	}
end

-- runs the neoscroll function when neoscroll is loaded, else the Normal mode keys
local function smooth(keys_to_press, animate)
	return function()
		if package.loaded["neoscroll"] then
			animate(require("neoscroll"))
		else
			normal(keys_to_press)
		end
	end
end

-- With a goal column set, the cursor goes to it after the scroll, which is not animated then: neoscroll scrolls
-- later, from a timer.
local function paging(keys_to_press, animate)
	local scroll = smooth(keys_to_press, animate)
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

local scroll_down = paging("<C-f>", function(neoscroll)
	neoscroll.ctrl_f({ duration = config.scroll_duration })
end)
local scroll_up = paging("<C-b>", function(neoscroll)
	neoscroll.ctrl_b({ duration = config.scroll_duration })
end)
local function recenter(keys_to_press)
	return smooth(keys_to_press, function(neoscroll)
		neoscroll[keys_to_press]({ half_win_duration = config.scroll_duration })
	end)
end

-- Scrolls the text sideways by the width of the window less 2, as Emacs does. Lines that wrap cannot scroll, so
-- wrapping is turned off for the window until the text is back at the left or the mode ends.
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

-- the lines of the buffer from the first to the last row that a command fills
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
		-- a selection that ends at the start of a line does not take that line
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
	-- the cursor stays at the same place of the text, which moves with the lines the paragraphs above it gain
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

-- shows the text of a kill on one line, for the list M-y offers
local function preview(text)
	local shown = text:gsub("\n", "↵")
	if vim.fn.strchars(shown) > 80 then
		shown = vim.fn.strcharpart(shown, 0, 79) .. "…"
	end
	return shown
end

-- runs fn in the window win if it still shows buf as it was, with the changedtick it had
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

-- M-y when it does not follow C-y: asks which kill to put, with vim.ui.select()
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
				-- some configurations leave the cursor pulled back from the end of the line after a prompt
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
	-- the prompts of the commands below are read with the keys of their own, so they read keys as well
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
	-- the goal column is released by pressing C-x C-n again where it is
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
	-- the line with its line break, joined to the kill before as the parts before and after the cursor
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
	-- right after C-y or M-y it puts the next older kill instead; otherwise it asks which kill to put
	yank_pop = {
		reads_key = true,
		run = function(buf, pos)
			local yank = last_yank
			if
				not yank
				or yank.buf ~= buf
				or yank.tick ~= vim.b.changedtick
				or not vim.deep_equal(yank.to, pos)
				or yank.key_sequence ~= started - 1
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
	recenter = cycling({ recenter("zz"), recenter("zt"), recenter("zb") }),
	-- Emacs puts the cursor at the start of the line
	move_to_window_line = vim.tbl_extend("force", cycling({ "M0", "H0", "L0" }), { motion = true }),
	-- a second press right after drops the selection or brings it back
	set_mark = {
		keeps_region = true,
		run = function(buf, pos)
			local mark = region.mark(buf)
			local again = previous and previous.name == "set_mark" and previous.key_sequence == started - 1
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
	-- without a selection, C-w kills the word before the cursor as in Readline and Vim
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
	-- ends the selection and nothing else; the mark stays
	keyboard_quit = { run = function() end },
	-- the selection from the separating line before the paragraph to the one after it, as Emacs marks it; again
	-- while it is on, it takes the next paragraph too
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
	-- the mark goes to the end of the next word, and again while the selection is on, one word further away
	-- from the cursor
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
	-- works with the mark of a dropped selection as well, and brings the selection back
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
	-- the characters on both sides of the cursor, a line break being one; at the end of a line the two before it
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
	-- the word at or before the cursor and the word after it; the cursor ends after both, as in Emacs
	transpose_words = {
		run = function(buf, pos)
			-- backward_word stops at the start of the buffer even before blanks or punctuation, so the start of the
			-- first word is found back from its end
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
	-- M-SPC leaves one space, pressed again none, and again the blanks it started from
	cycle_spacing = {
		run = function(buf, pos)
			local repeated = previous
				and previous.name == "cycle_spacing"
				and previous.key_sequence == started - 1
				and spacing
				and spacing.buf == buf
				and spacing.tick == vim.b.changedtick
			if not repeated then
				local from, to = motion.space_around(buf, pos, true)
				spacing = { buf = buf, original = pos, blanks = edit.text(from, to), step = 0 }
			else
				local from, to = motion.space_around(buf, pos, true)
				edit.splice(from, to, spacing.blanks)
				edit.set_cursor(spacing.original)
				pos = spacing.original
			end
			spacing.step = spacing.step % 3 + 1
			local from, to = motion.blanks_around(buf, pos)
			if spacing.step == 1 and edit.text(from, to) ~= " " then
				edit.set_cursor(edit.splice(from, to, " "))
			elseif spacing.step == 2 then
				edit.delete(from, to)
			end
			spacing.tick = vim.b[buf].changedtick
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
	-- kills up to and with the next typed character, which is read after the key
	zap_to_char = vim.tbl_extend(
		"force",
		killing(function(buf, pos)
			local ok, char = pcall(vim.fn.getcharstr)
			return ok and char ~= "" and motion.after_next(buf, pos, char) or nil
		end),
		{ reads_key = true }
	),
	kill_sentence = killing(motion.forward_sentence),
	-- Vim's search from i_CTRL-O shows the matches while typing and comes back to the mode at the match
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
