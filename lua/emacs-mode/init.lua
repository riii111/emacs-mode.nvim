-- Emacs editing mode: Insert mode entered with a key of Normal mode, with Emacs keys mapped to its buffer
-- until Insert mode ends. Plain Insert mode and other buffers are left alone.
local motion = require("emacs-mode.motion")
local edit = require("emacs-mode.edit")
local region = require("emacs-mode.region")

local M = {}

local DESC = "Emacs mode"
local group = vim.api.nvim_create_augroup("emacs_mode", { clear = false })
local namespace = vim.api.nvim_create_namespace("emacs_mode")

local keys = {
	["<C-f>"] = "forward_char",
	["<C-b>"] = "backward_char",
	["<C-n>"] = "next_line",
	["<C-p>"] = "previous_line",
	["<C-a>"] = "line_start",
	["<C-e>"] = "line_end",
	["<M-f>"] = "forward_word",
	["<M-b>"] = "backward_word",
	["<M-lt>"] = "buffer_start",
	["<M->>"] = "buffer_end",
	-- with the kitty keyboard protocol, Option+Shift+, arrives as <M-S-,>, not <M-lt>
	["<M-S-,>"] = "buffer_start",
	["<M-S-.>"] = "buffer_end",
	["<C-d>"] = "delete_char",
	["<Del>"] = "delete_char",
	["<BS>"] = "delete_backward_char",
	["<C-h>"] = "delete_backward_char",
	["<C-u>"] = "kill_line_start",
	["<C-k>"] = "kill_line_end",
	["<M-d>"] = "kill_word",
	["<M-BS>"] = "backward_kill_word",
	["<C-y>"] = "yank",
	["<M-y>"] = "yank_pop",
	["<C-v>"] = "scroll_down",
	["<M-v>"] = "scroll_up",
	["<C-l>"] = "recenter",
	["<M-r>"] = "move_to_window_line",
	["<M-{>"] = "backward_paragraph",
	["<M-}>"] = "forward_paragraph",
	["<M-S-[>"] = "backward_paragraph",
	["<M-S-]>"] = "forward_paragraph",
	["<C-w>"] = "kill_region",
	["<M-w>"] = "copy_region",
	["<C-g>"] = "keyboard_quit",
	["<M-h>"] = "mark_paragraph",
	["<M-t>"] = "transpose_words",
	["<M-u>"] = "upcase_word",
	["<M-l>"] = "downcase_word",
	["<M-c>"] = "capitalize_word",
	["<M-Bslash>"] = "delete_horizontal_space",
	["<M-Space>"] = "just_one_space",
	["<M-z>"] = "zap_to_char",
	["<M-a>"] = "backward_sentence",
	["<M-e>"] = "forward_sentence",
	["<M-k>"] = "kill_sentence",
	["<C-s>"] = "search_forward",
	["<C-r>"] = "search_backward",
	-- terminals send CTRL-/ as CTRL-_
	["<C-/>"] = "undo",
	["<C-_>"] = "undo",
}

local defaults = {
	-- the Normal mode key that starts the mode; none by default
	start_key = false,
	-- C-SPC reaches Neovim as <C-@> from terminals that send it as NUL; macOS may take it for the input source
	set_mark = { "<C-Space>", "<C-@>" },
	-- milliseconds of neoscroll's animation for C-v, M-v and C-l, when neoscroll is loaded
	scroll_duration = 100,
}
local config = defaults

-- pending: `e` was pressed and Insert mode is about to start; active: the mode is on in this buffer and window
local state = { pending = nil, active = nil }
-- counts the keys typed while the mode is on; a kill continues the previous one only when no other key came between
local key_sequence = 0
local last_kill
-- the column C-n and C-p aim at, kept while they move the cursor one after another
local vertical_goal
-- where C-y or M-y put the text last; M-y replaces it when it comes right after them
local last_yank
-- the step C-l or M-r took last; pressed again right after, they go on to the next step
local last_cycle

local function cursor()
	local pos = vim.api.nvim_win_get_cursor(0)
	return { pos[1] - 1, pos[2] }
end

-- defined below, in the order the mode goes through them
local editable, on_mode_changed, activate, restore, commands, close_completion
local smooth_scrolling, stop_when_left

-- opts: start_key, set_mark and scroll_duration, as in `defaults`
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
	-- typed text and other changes end the region; moves of other keys, such as the arrow keys, stretch it
	vim.api.nvim_create_autocmd("TextChangedI", {
		group = group,
		callback = function(args)
			if state.active and region.changed(args.buf) then
				region.clear()
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

function M.run(name)
	local active = state.active
	if not (active and active.buf == vim.api.nvim_get_current_buf()) then
		return
	end
	local command = commands[name]
	if command.kind ~= "kill" then
		last_kill = nil
	end
	if command.kind ~= "vertical" then
		vertical_goal = nil
	end
	command.run(active.buf, cursor())
	-- moves stretch the region; anything else ends it
	if command.keeps_region then
		region.draw(active.buf, cursor())
	else
		region.clear()
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
	vertical_goal = nil
	last_yank = nil
	last_cycle = nil
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
local function rhs(name)
	local own_keys = commands[name].keys
	if own_keys then
		return "<Cmd>lua require('emacs-mode').close_completion()<CR><C-g>u" .. own_keys
	end
	local run = ("<Cmd>lua require('emacs-mode').close_completion()<CR><C-g>u<Cmd>lua require('emacs-mode').run(%q)<CR>"):format(
		name
	)
	return commands[name].reads_key and run or run .. "<C-g>u"
end

local function install(buf)
	local saved = {}
	vim.api.nvim_buf_call(buf, function()
		local function map(lhs, name)
			-- a key given twice would save the mode's own mapping and put it back when the mode ends
			if saved[lhs] ~= nil then
				return
			end
			local mapping = vim.fn.maparg(lhs, "i", false, true)
			saved[lhs] = mapping.buffer == 1 and mapping or false
			vim.keymap.set("i", lhs, rhs(name), { buffer = buf, nowait = true, silent = true, desc = DESC })
		end
		for lhs, name in pairs(keys) do
			map(lhs, name)
		end
		for _, lhs in ipairs(config.set_mark) do
			map(lhs, "set_mark")
		end
	end)
	return saved
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
	state.active = { buf = buf, win = win, saved = install(buf), cursor = block_cursor() }
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

local function moving(target)
	return {
		keeps_region = true,
		run = function(buf, pos)
			local to = target(buf, pos)
			if to then
				edit.set_cursor(to)
			end
		end,
	}
end

local function deleting(from, to)
	return {
		run = function(buf, pos)
			local first, last = from(buf, pos), to(buf, pos)
			if first and last then
				edit.delete(first, last)
			end
		end,
	}
end

local function here(_, pos)
	return pos
end

-- kills the text between the cursor and target; a kill in a row adds backward kills in front
local function killing(target)
	return {
		kind = "kill",
		run = function(buf, pos)
			-- before target(), which may read a key of its own (M-z)
			local continued = last_kill
				and last_kill.buf == buf
				and last_kill.tick == vim.b.changedtick
				and vim.deep_equal(last_kill.pos, pos)
				and last_kill.key_sequence == key_sequence - 1
			local to = target(buf, pos)
			local backward = to and (to[1] < pos[1] or (to[1] == pos[1] and to[2] < pos[2]))
			if to then
				edit.store(edit.delete(pos, to), continued and (backward and "prepend" or "append") or "replace")
			elseif not continued then
				last_kill = nil
				return
			end
			last_kill = { buf = buf, tick = vim.b.changedtick, pos = cursor(), key_sequence = key_sequence }
		end,
	}
end

-- Runs a Normal mode command from Insert mode and returns 'curswant'. Normal mode commands cannot put the cursor
-- after the last character without 'virtualedit'. Setting it recomputes 'curswant', so prepare() runs after it
-- is set and 'curswant' is read before it is restored.
local function normal(keys, prepare)
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
		args = { vim.keycode(keys) },
		bang = true,
		mods = { noautocmd = true },
	}, {})
	local curswant = vim.fn.winsaveview().curswant
	set_virtualedit(virtualedit)
	assert(ok, err)
	return curswant
end

-- gj and gk keep the target column in 'curswant', which Insert mode resets after every command
local function screen_line(direction)
	return {
		kind = "vertical",
		keeps_region = true,
		run = function(_, pos)
			local win = vim.api.nvim_get_current_win()
			local curswant = normal("g" .. direction, function()
				local goal = vertical_goal
				if goal and goal.win == win and goal.tick == vim.b.changedtick and vim.deep_equal(goal.pos, pos) then
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
		if cycle and cycle.command == command and cycle.key_sequence == key_sequence - 1 then
			step = cycle.step % #steps + 1
		end
		step_with(steps[step])
		last_cycle = { command = command, step = step, key_sequence = key_sequence }
	end
	return command
end

local function before(a, b)
	return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
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

-- runs the neoscroll function when neoscroll is loaded, else the Normal mode keys
local function smooth(keys, animate)
	return function()
		if package.loaded["neoscroll"] then
			animate(require("neoscroll"))
		else
			normal(keys)
		end
	end
end

local scroll_down = smooth("<C-f>", function(neoscroll)
	neoscroll.ctrl_f({ duration = config.scroll_duration })
end)
local scroll_up = smooth("<C-b>", function(neoscroll)
	neoscroll.ctrl_b({ duration = config.scroll_duration })
end)
local function recenter(keys)
	return smooth(keys, function(neoscroll)
		neoscroll[keys]({ half_win_duration = config.scroll_duration })
	end)
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
	delete_char = deleting(here, motion.forward_char),
	delete_backward_char = deleting(motion.backward_char, here),
	kill_line_start = killing(motion.line_start),
	kill_line_end = killing(motion.kill_line_end),
	kill_word = killing(motion.forward_word),
	backward_kill_word = killing(motion.backward_word),
	yank = {
		run = function(buf, pos)
			local text = edit.to_yank()
			if text then
				local to = edit.insert(pos, text)
				last_yank = { buf = buf, from = pos, to = to, tick = vim.b.changedtick, key_sequence = key_sequence }
			end
		end,
	},
	-- does nothing unless it comes right after C-y or M-y, as Emacs refuses to
	yank_pop = {
		run = function(buf, pos)
			local yank = last_yank
			if
				not yank
				or yank.buf ~= buf
				or yank.tick ~= vim.b.changedtick
				or not vim.deep_equal(yank.to, pos)
				or yank.key_sequence ~= key_sequence - 1
			then
				return
			end
			local text = edit.rotate()
			edit.delete(yank.from, yank.to)
			local to = edit.insert(yank.from, text)
			last_yank = { buf = buf, from = yank.from, to = to, tick = vim.b.changedtick, key_sequence = key_sequence }
		end,
	},
	scroll_down = { keeps_region = true, run = scroll_down },
	scroll_up = { keeps_region = true, run = scroll_up },
	recenter = cycling({ recenter("zz"), recenter("zt"), recenter("zb") }),
	-- Emacs puts the cursor at the start of the line
	move_to_window_line = cycling({ "M0", "H0", "L0" }),
	backward_paragraph = moving(motion.backward_paragraph),
	forward_paragraph = moving(motion.forward_paragraph),
	set_mark = {
		keeps_region = true,
		run = function(buf, pos)
			region.set_mark(buf, pos)
		end,
	},
	-- without a region, C-w kills the word before the cursor as in Readline and Vim
	kill_region = killing(function(buf, pos)
		local mark = region.mark(buf)
		if mark then
			return not vim.deep_equal(mark, pos) and mark or nil
		end
		return motion.backward_word(buf, pos)
	end),
	copy_region = {
		run = function(buf, pos)
			local mark = region.mark(buf)
			if mark and not vim.deep_equal(mark, pos) then
				edit.store(edit.text(mark, pos), "replace")
			end
		end,
	},
	-- ends the region and nothing else
	keyboard_quit = { run = function() end },
	-- the region from the separating line before the paragraph to the one after it, as Emacs marks it
	mark_paragraph = {
		keeps_region = true,
		run = function(buf, pos)
			local to = motion.forward_paragraph(buf, pos) or pos
			region.set_mark(buf, to)
			edit.set_cursor(motion.backward_paragraph(buf, to) or to)
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
	upcase_word = converting(vim.fn.toupper),
	downcase_word = converting(vim.fn.tolower),
	capitalize_word = converting(function(text)
		return vim.fn.substitute(vim.fn.tolower(text), [[\k]], [[\u&]], "")
	end),
	delete_horizontal_space = deleting(function(buf, pos)
		return (motion.blanks_around(buf, pos))
	end, function(buf, pos)
		return select(2, motion.blanks_around(buf, pos))
	end),
	just_one_space = {
		run = function(buf, pos)
			local from, to = motion.blanks_around(buf, pos)
			if edit.text(from, to) ~= " " then
				edit.replace(from, to, " ")
			end
		end,
	},
	-- kills up to and with the next typed character, which is read after the key
	zap_to_char = vim.tbl_extend(
		"force",
		killing(function(buf, pos)
			local ok, char = pcall(vim.fn.getcharstr)
			vim.api.nvim_feedkeys(vim.keycode("<C-g>u"), "ni", false)
			return ok and char ~= "" and motion.after_next(buf, pos, char) or nil
		end),
		{ reads_key = true }
	),
	backward_sentence = moving(motion.backward_sentence),
	forward_sentence = moving(motion.forward_sentence),
	kill_sentence = killing(motion.forward_sentence),
	-- Vim's search from i_CTRL-O shows the matches while typing and comes back to the mode at the match
	search_forward = { keys = "<C-o>/" },
	search_backward = { keys = "<C-o>?" },
	undo = {
		run = function()
			vim.cmd("silent! undo")
		end,
	},
}

return M
