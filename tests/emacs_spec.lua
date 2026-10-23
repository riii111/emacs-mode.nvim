-- Integration tests of emacs-mode. Keys go through the real mappings: each case types its keys in one
-- feedkeys() call, records the state on the way with <Cmd> and leaves with <Esc>.
--
-- `make test` runs them without other plugins. A configuration with blink.cmp or neoscroll can run them as
-- well, to test the mode together with those: dofile("<this file>")() inside Neovim.
local emacs = require("emacs-mode")
local edit = require("emacs-mode.edit")
local region = require("emacs-mode.region")

local OPTS = { start_key = "e" }

local T = { snaps = {} }
_G.emacs_test = T

local mode_keys = {}
do
	local table_of_keys = require("emacs-mode.keys")
	for _, group in ipairs({ table_of_keys.single, table_of_keys.shifted, table_of_keys.prefixes }) do
		for lhs in pairs(group) do
			table.insert(mode_keys, lhs)
		end
	end
	vim.list_extend(mode_keys, { "<C-Space>", "<C-@>" })
end

-- "abc|def\nxyz": the lines, with the cursor where "|" is
local function parse(spec)
	local lines = vim.split(spec, "\n", { plain = true })
	for row, line in ipairs(lines) do
		local col = line:find("|", 1, true)
		if col then
			lines[row] = line:sub(1, col - 1) .. line:sub(col + 1)
			return lines, { row - 1, col - 1 }
		end
	end
	error("no cursor in " .. spec)
end

local function render()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
	local pos = vim.api.nvim_win_get_cursor(0)
	local line = lines[pos[1]]
	lines[pos[1]] = line:sub(1, pos[2]) .. "|" .. line:sub(pos[2] + 1)
	return table.concat(lines, "\n")
end

local function text()
	return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, true), "\n")
end

-- the highlighted region as { row, col, end_row, end_col }
local function highlighted()
	for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(0, region.namespace, 0, -1, { details = true })) do
		if extmark[4].hl_group then
			return { extmark[2], extmark[3], extmark[4].end_row, extmark[4].end_col }
		end
	end
end

local function settle()
	if package.loaded["neoscroll.scroll"] then
		vim.wait(2000, function()
			return not require("neoscroll.scroll").scrolling
		end, 5)
	end
end

function T.snap(label)
	settle()
	T.snaps[label] = {
		text = render(),
		mode = vim.fn.mode(),
		active = emacs.is_active(),
		killed = edit.killed(),
		buf = vim.api.nvim_get_current_buf(),
		screen_row = vim.fn.winline(),
		top = vim.fn.line("w0"),
		pos = vim.api.nvim_win_get_cursor(0),
		region = highlighted(),
		mark = region.mark(vim.api.nvim_get_current_buf()),
		selected = region.is_active(vim.api.nvim_get_current_buf()),
		leftcol = vim.fn.winsaveview().leftcol,
		wrap = vim.wo.wrap,
	}
end

function T.place(row, col)
	vim.api.nvim_win_set_cursor(0, { row + 1, col })
end

local function snap(label)
	return ("<Cmd>lua emacs_test.snap(%q)<CR>"):format(label)
end

local function feed(input)
	vim.api.nvim_feedkeys(vim.keycode(input), "tx", false)
end

local function eq(expected, actual, what)
	if not vim.deep_equal(expected, actual) then
		error(("%s\nexpected: %s\n  actual: %s"):format(what or "", vim.inspect(expected), vim.inspect(actual)), 2)
	end
end

local buffers = {}

local function open(spec)
	feed("<Esc>")
	vim.cmd.enew()
	table.insert(buffers, vim.api.nvim_get_current_buf())
	local lines, pos = parse(spec)
	vim.api.nvim_buf_set_lines(0, 0, -1, true, lines)
	vim.api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
	T.snaps = {}
	return pos
end

local function session(spec, input)
	local pos = open(spec)
	feed(("e<Cmd>lua emacs_test.place(%d, %d)<CR>"):format(pos[1], pos[2]) .. input .. snap("end") .. "<Esc>")
	return T.snaps["end"]
end

local function check(spec, input, expected, killed)
	local state = session(spec, input)
	eq(expected, state.text, ("%q after %s"):format(spec, input))
	if killed ~= nil then
		eq(killed, state.killed, ("kill of %q after %s"):format(spec, input))
	end
	eq({ "i", true }, { state.mode, state.active }, "mode during " .. input)
end

local function buffer_maps(buf)
	local found = {}
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "i")) do
		if mapping.desc == "Emacs mode" then
			table.insert(found, mapping.lhs)
		end
	end
	return found
end

local cases = {}

cases["e starts the mode at the cursor and Esc or CTRL-C ends it"] = function()
	open("ab|c")
	feed("e" .. snap("started") .. "X<Esc>")
	eq({ "i", true, "ab|c" }, { T.snaps.started.mode, T.snaps.started.active, T.snaps.started.text })
	eq("ab|Xc", render())
	eq({ "n", false }, { vim.fn.mode(), emacs.is_active() })
	eq({}, buffer_maps(0), "mappings left after <Esc>")

	open("ab|c")
	feed("e" .. snap("started") .. "Y<C-c>" .. snap("after"))
	eq(true, T.snaps.started.active)
	eq({ "n", false }, { T.snaps.after.mode, T.snaps.after.active }, "after CTRL-C")
	eq({}, buffer_maps(0), "mappings left after CTRL-C")

	check("|ab", "e", "e|ab")
end

cases["the cursor is a block while the mode is on"] = function()
	local guicursor = vim.o.guicursor
	open("ab|c")
	feed("e<Cmd>lua emacs_test.guicursor = vim.o.guicursor<CR><Esc>")
	eq(guicursor .. ",i-ci:block", T.guicursor, "'guicursor' in the mode")
	eq(guicursor, vim.o.guicursor, "'guicursor' after the mode")

	feed("e<Cmd>set guicursor=a:hor20<CR><Esc>")
	eq("a:hor20", vim.o.guicursor)
	vim.o.guicursor = guicursor
end

cases["start_key picks the key that starts the mode, and none is mapped without it"] = function()
	local ok, err = pcall(function()
		emacs.setup({})
		eq("", vim.fn.maparg("e", "n"), "e mapped without start_key")
		open("|foo bar")
		feed("e")
		eq({ "n", false, "fo|o bar" }, { vim.fn.mode(), emacs.is_active(), render() }, "e without start_key")

		emacs.setup({ start_key = "<F2>" })
		open("ab|c")
		feed("<F2>" .. snap("on") .. "<C-k><Esc>")
		eq({ true, "ab" }, { T.snaps.on.active, text() }, "the mode from <F2>")
		emacs.setup({})
		eq("", vim.fn.maparg("<F2>", "n"), "<F2> left mapped by an earlier setup")
	end)
	emacs.setup(OPTS)
	assert(ok, err)
end

cases["plain Insert mode and the e motion are unchanged"] = function()
	open("|abc\nxyz")
	feed("i<C-e><C-k>a:<Esc>")
	eq("x\u{e4}abc\nxyz", text(), "CTRL-E and CTRL-K of plain Insert mode")
	eq({}, buffer_maps(0))

	open("|foo bar")
	feed("de")
	eq(" bar", text(), "de")
	open("|foo bar")
	feed('"aye')
	eq("foo", vim.fn.getreg("a"), "ye")
	open("|foo bar")
	feed("ve<Esc>")
	eq(3, vim.fn.col("'>"), "e in Visual mode")

	open("|foo bar")
	vim.bo.buftype = "nofile"
	feed("e")
	eq({ "n", false, "fo|o bar" }, { vim.fn.mode(), emacs.is_active(), render() }, "e in a nofile buffer")
	vim.bo.buftype = ""
	vim.bo.modifiable = false
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	feed("e")
	eq({ "n", false, "fo|o bar" }, { vim.fn.mode(), emacs.is_active(), render() }, "e in a nomodifiable buffer")
	vim.bo.modifiable = true
end

cases["moving by characters crosses lines and stops at the ends"] = function()
	check("ab|c\nd", "<C-f>", "abc|\nd")
	check("abc|\nd", "<C-f>", "abc\n|d")
	check("abc\nd|", "<C-f>", "abc\nd|")
	check("abc\n|d", "<C-b>", "abc|\nd")
	check("|abc", "<C-b>", "|abc")
	check("a|bc", "<C-b>", "|abc")
	check("\n|\nx", "<C-f><C-f>", "\n\nx|")
	check("\n|\nx", "<C-b>", "|\n\nx")
end

cases["line and buffer ends"] = function()
	check("  ab|cd\nx", "<C-a>", "|  abcd\nx")
	check("  ab|cd\nx", "<C-e>", "  abcd|\nx")
	check("|", "<C-a><C-e>", "|")
	check("a\nb|c\nd", "<M-lt>", "|a\nbc\nd")
	check("a\nb|c\nde", "<M->>", "a\nbc\nde|")
	check("a\nb|c\n", "<M->>", "a\nbc\n|")
	-- what Option+Shift+, and Option+Shift+. send through the kitty keyboard protocol
	check("a\nb|c\nd", "<M-S-,>", "|a\nbc\nd")
	check("a\nb|c\nde", "<M-S-.>", "a\nbc\nde|")
end

cases["words follow iskeyword and cross lines"] = function()
	check("|foo bar", "<M-f>", "foo| bar")
	check("foo| bar", "<M-f>", "foo bar|")
	check("fo|o, bar", "<M-f>", "foo|, bar")
	check("foo|  \n  bar baz", "<M-f>", "foo  \n  bar| baz")
	check("foo bar|", "<M-f>", "foo bar|")
	check("foo, ...|", "<M-f>", "foo, ...|")
	check("foo ba|r", "<M-b>", "foo |bar")
	check("foo |bar", "<M-b>", "|foo bar")
	check("foo\n  |bar", "<M-b>", "|foo\n  bar")
	check("  |x", "<M-b>", "|  x")
	check("foo_bar-ba|z", "<M-b>", "foo_bar-|baz")
	local pos = open("foo-ba|r")
	vim.bo.iskeyword = vim.bo.iskeyword .. ",-"
	feed(("e<Cmd>lua emacs_test.place(%d, %d)<CR><M-b>"):format(pos[1], pos[2]) .. snap("end") .. "<Esc>")
	eq("|foo-bar", T.snaps["end"].text, "M-b with - in iskeyword")
end

cases["deleting characters joins lines and keeps the kill"] = function()
	edit.store("kept", "replace")
	check("ab|c", "<C-d>", "ab|", "kept")
	check("ab|\ncd", "<C-d>", "ab|cd", "kept")
	check("ab|\ncd", "<Del>", "ab|cd", "kept")
	check("ab\ncd|", "<C-d>", "ab\ncd|", "kept")
	check("ab|c", "<BS>", "a|c", "kept")
	check("ab\n|cd", "<BS>", "ab|cd", "kept")
	check("ab\n|cd", "<C-h>", "ab|cd", "kept")
	check("|ab", "<BS>", "|ab", "kept")
	check("|", "<BS><C-d>", "|", "kept")
end

cases["C-u kills to the start of the line, past where Insert mode started"] = function()
	check("abc|def", "<C-u>", "|def", "abc")
	check("  ab|c\nd", "XY<C-u>", "|c\nd", "  abXY")
	edit.store("kept", "replace")
	check("ab\n|cd", "<C-u>", "ab\n|cd", "kept")
	check("|", "<C-u>", "|", "kept")
end

cases["C-k kills to the end of the line or the line break"] = function()
	check("abc|def", "<C-k>", "abc|", "def")
	check("abc|\ndef", "<C-k>", "abc|def", "\n")
	check("abc|   \ndef", "<C-k>", "abc|def", "   \n")
	check("abc|\t \ndef", "<C-k>", "abc|def", "\t \n")
	check("a|bc\nde\nf", "<C-k><C-k><C-k>", "a|\nf", "bc\nde")
	check("a|b  ", "<C-k>", "a|", "b  ")
	check("a|  ", "<C-k>", "a|", "  ")
	edit.store("kept", "replace")
	check("ab\ncd|", "<C-k>", "ab\ncd|", "kept")
	check("|", "<C-k>", "|", "kept")
end

cases["kill words"] = function()
	check("foo |bar baz", "<M-d>", "foo | baz", "bar")
	check("foo| \n bar", "<M-d>", "foo|", " \n bar")
	check("foo bar|", "<M-BS>", "foo |", "bar")
	check("foo\n  |bar", "<M-BS>", "|bar", "foo\n  ")
	edit.store("kept", "replace")
	check("foo bar|", "<M-d>", "foo bar|", "kept")
	check("|foo", "<M-BS>", "|foo", "kept")
end

cases["C-y puts back the last kill, also in other buffers and after the mode"] = function()
	check("ab|c\nde\nf", "<C-k><C-k><C-k><C-y>", "abc\nde|\nf", "c\nde")
	check("x|y", "<C-y>", "xc\nde|y")
	check("x|y", "<C-y><C-y>", "xc\ndec\nde|y")
	check("a|b", "<C-u><C-y><C-y>", "aa|b", "a")
end

cases["M-y goes back through older kills"] = function()
	-- a kill puts the yank pointer back on the latest kill; 60 kills are kept, so the oldest of these 61 is gone
	local function kills(...)
		for _, text in ipairs({ ... }) do
			edit.store(text, "replace")
		end
	end
	local sixty_one = {}
	for i = 0, 60 do
		table.insert(sixty_one, "k" .. i)
	end
	for count, expected in pairs({ [0] = "xk60|", [2] = "xk58|", [59] = "xk1|", [60] = "xk60|" }) do
		kills(unpack(sixty_one))
		check("x|", "<C-y>" .. string.rep("<M-y>", count), expected)
	end

	kills("a", "b")
	check("x|", "<M-y><Esc>", "x|")
	check("x|", "<C-y>Z<M-y><Esc>", "xbZ|")
	check("x|", "<C-y><C-b><C-f><M-y><Esc>", "xb|")

	check("x|", "<C-y><M-y> <C-y>", "xa a|")
	check("x|y", "<C-k><C-y>", "xy|", "y")

	kills("l1\nl2", "s")
	check("x|y", "<C-y><M-y>", "xl1\nl2|y")
	kills("s", "l1\nl2")
	check("x|y", "<C-y><M-y>", "xs|y")

	kills("a", "b")
	session("x|", "<C-y><M-y><C-/>" .. snap("undone"))
	eq("xb", (T.snaps.undone.text:gsub("|", "")), "undo of M-y")
end

cases["the region from the mark is killed, copied or dropped"] = function()
	check("ab|cdef", "<C-Space><C-f><C-f><C-w>", "ab|ef", "cd")
	check("abcd|ef", "<C-Space><C-b><C-b><C-w>", "ab|ef", "cd")
	check("ab|c\ndef", "<C-Space><C-n><C-w>", "ab|f", "c\nde")
	check("ab|cd", "<C-@><C-e><C-w>", "ab|", "cd")
	check("ab|cd", "<C-Space><C-e><M-w><C-y>", "abcdcd|", "cd")
	check("foo ab|cd", "<C-Space><C-b><C-b><C-w><C-w>", "|cd", "foo ab")

	session("ab|cdef", "<C-Space><C-f><C-f>" .. snap("on") .. "<C-g>" .. snap("quit"))
	eq({ 0, 2, 0, 4 }, T.snaps.on.region, "highlighted region")
	eq({ nil, true, "abcd|ef" }, { T.snaps.quit.region, T.snaps.quit.active, T.snaps.quit.text }, "after C-g")

	-- Neovim fires these when it waits for a key, which it does not while the test's keys are queued
	local idle = "<Cmd>doautocmd CursorMovedI<CR><Cmd>doautocmd TextChangedI<CR>"
	session("ab|cd", "<C-Space><Right><Right>" .. idle .. snap("arrows") .. "X" .. idle .. snap("typed"))
	eq({ 0, 2, 0, 4 }, T.snaps.arrows.region, "region stretched by the arrow keys")
	eq({ nil, "abcdX|" }, { T.snaps.typed.region, T.snaps.typed.text }, "typing ends the region and replaces nothing")
	session("ab|cd", "<C-Space><C-f>")
	eq({}, vim.api.nvim_buf_get_extmarks(0, region.namespace, 0, -1, {}), "region after the mode")

	check("|", "abc<C-Space>" .. idle .. "<C-b><C-b>" .. idle .. "<C-w>", "a|", "bc")
	local ok, err = pcall(function()
		emacs.setup({ start_key = "e", set_mark = { "<C-Space>", "<C-Space>", "<C-g>" } })
		check("ab|cd", "<C-Space><C-e><C-w>", "ab|", "cd")
		eq({}, buffer_maps(0), "mappings left after a key given twice")
	end)
	emacs.setup(OPTS)
	assert(ok, err)

	edit.store("kept", "replace")
	check("ab|cd", "<C-Space><C-w>", "ab|cd", "kept")
	-- C-y ends the region, so C-w kills the word
	check("ab|cd", "<C-Space><C-y><C-b><C-w>", "|tcd", "abkep")
	check("foo bar|", "<C-w>", "foo |", "bar")

	check("a\n\nb|1\nb2\n\nc", "<M-h><C-w>", "a\n|\nc", "\nb1\nb2\n")
	check("a\n\nb|1\nb2", "<M-h><C-w>", "a\n|", "\nb1\nb2")

	local ok, err = pcall(function()
		emacs.setup({ start_key = "e", set_mark = { "<C-]>" } })
		check("ab|cd", "<C-]><C-e><C-w>", "ab|", "cd")
		open("ab|cd")
		feed("e<Cmd>lua emacs_test.mark_map = vim.fn.maparg('<lt>C-Space>', 'i', false, true).desc<CR><Esc>")
		assert(T.mark_map ~= "Emacs mode", "C-Space is still mapped after another key was set")
	end)
	emacs.setup(OPTS)
	assert(ok, err)
end

cases["words are swapped, cased and spaced"] = function()
	check("foo |bar baz", "<M-t>", "bar foo| baz")
	check("foo |bar baz", "<M-t><M-t>", "bar baz foo|")
	check("fo|o, bar", "<M-t>", "bar, foo|")
	check("|foo bar", "<M-t>", "bar foo|")
	check("  |foo bar", "<M-t>", "  bar foo|")
	check("|-- foo bar", "<M-t>", "-- bar foo|")
	check("one|\ntwo", "<M-t>", "two\none|")
	check("foo bar|", "<M-t>", "foo bar|")
	check("a|", "<M-t>", "a|")

	check("fo|o bar", "<M-u>", "foO| bar")
	check("|foo bar", "<M-u><M-u>", "FOO BAR|")
	check("|FOO Bar", "<M-l>", "foo| Bar")
	check("|hELLO, wORLD", "<M-c><M-c>", "Hello, World|")
	check("|\u{e9}lan", "<M-u>", "\u{c9}LAN|")
	check("|日本語 abc", "<M-u><M-u>", "日本語 ABC|")
	check("x|", "<M-u>", "x|")

	check("a  | \tb", "<M-Bslash>", "a|b")
	check("ab|", "<M-Bslash>", "ab|")
	check("a|b", "<M-Space>", "a |b")
	check("a |b", "<M-Space>", "a |b")
end

cases["M-z kills up to and with the typed character"] = function()
	check("a|bc,de", "<M-z>,", "a|de", "bc,")
	check("a|b\nc,d", "<M-z>,", "a|d", "b\nc,")
	check("|あいう、え", "<M-z>、", "|え", "あいう、")
	check("a|,b,c", "<M-z>,", "a|b,c", ",")
	check("a|b c,d", "<M-d><M-z>,", "a|d", "b c,")
	check("a|b,c,d", "<M-z>,<M-z>,", "a|d", "b,c,")
	check("a|b,cd", "<M-z>,<M-d>", "a|", "b,cd")
	edit.store("kept", "replace")
	check("a|bc", "<M-z>,", "a|bc", "kept")
	check("a|bc", "<M-z><Esc>", "a|bc", "kept")
end

cases["sentences end at 。！？ and at . ! ? before a blank"] = function()
	local text = "Hello world. Next one! Last?"
	check("|" .. text, "<M-e>", "Hello world.| Next one! Last?")
	check("|" .. text, "<M-e><M-e>", "Hello world. Next one!| Last?")
	check("|" .. text, "<M-e><M-e><M-e><M-e>", text .. "|")
	check("Hello world. Ne|xt one!", "<M-a>", "Hello world. |Next one!")
	check("Hello world. |Next one!", "<M-a>", "|Hello world. Next one!")
	check("|x", "<M-a>", "|x")

	check(
		"|今日は晴れ。明日は雨！あさっては？",
		"<M-e><M-e>",
		"今日は晴れ。明日は雨！|あさっては？"
	)
	check(
		"今日は晴れ。明日は雨！あさ|っては？",
		"<M-a>",
		"今日は晴れ。明日は雨！|あさっては？"
	)
	check("|「行く。」と言った。次", "<M-e>", "「行く。」|と言った。次")
	check("|v1.2 is out. Yes", "<M-e>", "v1.2 is out.| Yes")
	check("|本当！？次。", "<M-e>", "本当！？|次。")
	check("本当！？次|。", "<M-a>", "本当！？|次。")
	check("|「本当？！」次", "<M-e>", "「本当？！」|次")
	check("|Yes.\u{3000}No.", "<M-e>", "Yes.|\u{3000}No.")
	check("|Really?! Yes", "<M-e>", "Really?!| Yes")

	check("first line\nsecond. Th|ird", "<M-a><M-a>", "|first line\nsecond. Third")
	check("|no end here\nstill\n\nnext.", "<M-e>", "no end here\nstill|\n\nnext.")
	check("one. two\n\n|three", "<M-a>", "one. |two\n\nthree")

	check("Hello |world. Next.", "<M-k>", "Hello | Next.", "world.")
	check("Hello |world. Next.", "<M-k><M-k>", "Hello |", "world. Next.")
end

cases["C-s and C-r search with Vim's search and stay in the mode"] = function()
	check("ab|c foo bar foo", "<C-s>foo<CR>", "abc |foo bar foo")
	check("ab|c foo bar foo", "<C-s>foo<CR><C-s><CR>", "abc foo bar |foo")
	check("foo bar foo|", "<C-r>foo<CR>", "foo bar |foo")
	check("foo bar foo|", "<C-r>foo<CR><C-r><CR>", "|foo bar foo")
	check("abc|\nfoo", "<C-s>foo<CR>", "abc\n|foo")
	check("ab|c foo", "<C-s>fo<Esc>", "ab|c foo")
	check("ab|c foo", "<C-s>foo<CR>X", "abc X|foo")
end

cases["kills in a row join in text order"] = function()
	check("one two thr|ee", "<M-BS><M-BS>", "one |ee", "two thr")
	check("one t|wo three", "<M-d><M-d>", "one t|", "wo three")
	check("abc|def", "<C-k><C-u>", "|", "abcdef")
	check("one two| three", "<M-BS><M-d>", "one |", "two three")
	check("one two| three x", "<M-BS><M-d><M-BS>", "| x", "one two three")
	check("ab|c\nd", "<C-k><C-k><M-BS>", "|d", "abc\n")
end

cases["any other key ends a row of kills"] = function()
	check("a|bc\nde", "<C-k>X<C-k>", "aX|de", "\n")
	check("a|bc\nde", "<C-k><C-f><C-b><C-k>", "a|de", "\n")
	check("a|bc\nde", "<C-k><Left><Right><C-k>", "a|de", "\n")
	check("a|bc\nde", "<C-k><C-y><C-k>", "abc|de", "\n")
	check("a|bc\nde", "<C-k><BS><C-k>", "|de", "\n")
	check("a|bc\nde", "<C-k><C-/><C-k>", "a|\nde", "bc")
	check("a|b", "<C-k><C-k><C-u>", "|", "ab")
	session("a|bc", "<C-k>")
	check("x|y", "<C-k>", "x|", "y")
	open("a|b")
	feed("e<C-k><Esc>e<C-k><Esc>")
	eq("", vim.fn.getline(1))
	eq("a", edit.killed(), "kill after the mode restarted")
end

local function undo_steps(spec, input)
	local pos = open(spec)
	feed(
		("e<Cmd>lua emacs_test.place(%d, %d)<CR>"):format(pos[1], pos[2])
			.. snap("0")
			.. "A"
			.. snap("1")
			.. input
			.. snap("2")
			.. "B"
			.. "<C-/>"
			.. snap("u1")
			.. "<C-/>"
			.. snap("u2")
			.. "<C-_>"
			.. snap("u3")
			.. "<Esc>"
	)
	local s = T.snaps
	local function body(label)
		return (s[label].text:gsub("|", ""))
	end
	local what = ("undo of %s in %q"):format(input, spec)
	assert(body("2") ~= body("1"), what .. ": the command changed nothing")
	eq({ body("2"), body("1"), body("0") }, { body("u1"), body("u2"), body("u3") }, what)
	eq(true, s.u3.active, what)
	eq(body("0"), text(), what .. " after <Esc>")
end

cases["every edit is one undo step of its own"] = function()
	edit.store("Y", "replace")
	-- <Del> and <C-h> run the same commands as <C-d> and <BS>, which the deletion case checks
	for _, input in ipairs({
		"<C-d>",
		"<BS>",
		"<C-u>",
		"<C-k>",
		"<M-d>",
		"<M-BS>",
		"<C-y>",
		"<C-w>",
		"<M-t>",
		"<M-u>",
		"<M-c>",
		"<M-Space>",
		"<M-z>z",
	}) do
		undo_steps("foo b|ar\nbaz", input)
	end
	undo_steps("foo bar|\nbaz", "<C-k>")
	undo_steps("foo bar\n|baz", "<BS>")
end

cases["undo goes on in the mode and redo in Normal mode"] = function()
	open("|x")
	feed("eab<C-k>cd<C-/><C-/><C-/>" .. snap("undone") .. "ef<Esc>")
	eq({ "|x", true }, { T.snaps.undone.text, T.snaps.undone.active })
	eq("efx", text())
	feed("u")
	eq("x", text())
	feed("<C-r>")
	eq("efx", text())

	open("x|\ny")
	feed("e<C-e>A<C-n><C-a>B<C-p><C-e>C<Esc>")
	eq("xAC\nBy", text())
	local undone = {}
	for _ = 1, 3 do
		feed("u")
		table.insert(undone, text())
	end
	eq({ "xA\nBy", "xA\ny", "x\ny" }, undone)
end

cases["characters are what `l` and `h` move over"] = function()
	local line = "aあé" .. "e\u{301}" .. "👨‍👩‍👧" .. "🇯🇵" .. "\tz"
	open("|" .. line)
	local expected = { 0 }
	for _ = 1, 9 do
		feed("l")
		table.insert(expected, vim.fn.col(".") - 1)
	end
	expected = vim.fn.uniq(expected)
	table.insert(expected, #line)
	local input = ""
	for i = 1, #expected do
		input = input .. snap(tostring(i)) .. (i < #expected and "<C-f>" or "")
	end
	session("|" .. line, input .. "<C-f>" .. snap("past"))
	local cols = {}
	for i = 1, #expected do
		local _, col = T.snaps[tostring(i)].text:find("|", 1, true)
		table.insert(cols, col - 1)
	end
	eq(T.snaps[tostring(#expected)].text, T.snaps.past.text, "C-f at the end of the buffer")
	eq(expected, cols, "C-f over " .. line)

	local back = {}
	local input_back = ""
	for i = 1, #cols do
		input_back = input_back .. snap(tostring(i)) .. "<BS>"
	end
	session(line .. "|", input_back)
	for i = 1, #cols do
		table.insert(back, (T.snaps[tostring(i)].text:gsub("|", "")))
	end
	eq({
		line,
		"aあée\u{301}👨‍👩‍👧🇯🇵\t",
		"aあée\u{301}👨‍👩‍👧🇯🇵",
		"aあée\u{301}👨‍👩‍👧",
		"aあée\u{301}",
		"aあé",
		"aあ",
		"a",
		"",
	}, back, "BS over " .. line)
	check("|あいう", "<C-d>", "|いう")
	check("|e\u{301}x", "<C-d>", "|x")
	check("|👍🏽x", "<C-d>", "|x")
	check("a|\tb", "<C-f>", "a\t|b")
end

cases["words in Japanese and mixed text"] = function()
	check("|日本語のテキスト、English words", "<M-f>", "日本語のテキスト|、English words")
	check("日本語のテキスト|、English words", "<M-f>", "日本語のテキスト、English| words")
	check("日本語のテキスト、English words|", "<M-b><M-b>", "日本語のテキスト、|English words")
	check("全角　スペ|ース", "<M-b><M-b>", "|全角　スペース")
	check("全角　スペ|ース", "<M-d>", "全角　スペ|", "ース")
	check("日本|語 text", "<C-k><C-y><C-a><C-y>", "語 text|日本語 text", "語 text")
end

cases["C-n and C-p move by screen lines and keep the column"] = function()
	local width = 20
	vim.cmd.vnew()
	vim.cmd("vertical resize " .. width)
	vim.wo.wrap = true
	vim.wo.linebreak = true
	vim.wo.breakindent = true
	vim.wo.number = false
	vim.wo.relativenumber = false
	vim.wo.signcolumn = "no"
	vim.wo.foldcolumn = "0"
	vim.wo.statuscolumn = ""
	vim.wo.list = false
	vim.cmd("setlocal showbreak=NONE")
	-- session() opens a new buffer, which takes the global value
	local tabstop = vim.go.tabstop
	vim.go.tabstop = 8
	local options = { vim.wo.wrap, vim.wo.linebreak, vim.wo.breakindent, vim.o.virtualedit, vim.wo.virtualedit }
	local lines = {
		"aaaa bbbb cccc dddd eeee ffff",
		"xy",
		"0123456789",
		"あいうえおかきくけこさしすせそ",
		"\tab\tcd",
		"  indented line that wraps here",
	}
	local spec = table.concat(lines, "\n"):gsub("^aaa", "aaa|", 1)
	local input = ""
	for i = 1, 9 do
		input = input .. "<C-n>" .. snap("d" .. i)
	end
	for i = 1, 9 do
		input = input .. "<C-p>" .. snap("u" .. i)
	end
	session(spec, input)
	vim.go.tabstop = tabstop
	local function at(label)
		local snapshot = T.snaps[label].text
		local row = select(2, snapshot:sub(1, snapshot:find("|", 1, true)):gsub("\n", "")) + 1
		local col = snapshot:find("|", 1, true) - 1 - #table.concat(vim.list_slice(lines, 1, row - 1), "\n")
		return { row, col - (row > 1 and 1 or 0) }
	end
	local down, up, rows = {}, {}, {}
	for i = 1, 9 do
		table.insert(down, at("d" .. i))
		table.insert(up, at("u" .. i))
	end
	for i = 1, 7 do
		table.insert(rows, T.snaps["d" .. i].screen_row - T.snaps["u" .. (8 - i)].screen_row)
	end
	eq({
		{ 1, 23 },
		{ 2, 2 },
		{ 3, 3 },
		{ 4, 3 },
		{ 4, 33 },
		{ 5, 0 },
		{ 6, 3 },
		{ 6, 19 },
		{ 6, 19 },
	}, down, "C-n")
	eq({ { 6, 3 }, { 5, 0 }, { 4, 33 }, { 4, 3 }, { 3, 3 }, { 2, 2 }, { 1, 23 }, { 1, 3 }, { 1, 3 } }, up, "C-p")
	eq({ 0, 0, 0, 0, 0, 0, 0 }, rows, "screen rows of C-n and C-p")
	local steps = {}
	for i = 2, 8 do
		table.insert(steps, T.snaps["d" .. i].screen_row - T.snaps["d" .. (i - 1)].screen_row)
	end
	eq({ 1, 1, 1, 1, 1, 1, 1 }, steps, "screen rows moved by C-n")
	eq(options, { vim.wo.wrap, vim.wo.linebreak, vim.wo.breakindent, vim.o.virtualedit, vim.wo.virtualedit })
	vim.cmd.close()

	check("abc|def\nxy\nabcdef", "<C-e><C-n><C-n>", "abcdef\nxy\nabcdef|")
	check("abcdef\nx|y\nabcdef", "<C-n>ZZ<C-p><C-p>", "abc|def\nxy\naZZbcdef")
	check("abc\n|", "<C-n><C-p><C-p>", "|abc\n")
end

cases["paragraphs are separated by blank lines"] = function()
	check("a\nb|b\n\nc\nd", "<M-}>", "a\nbb\n|\nc\nd")
	check("a\nbb\n|\nc\nd\n\n\ne", "<M-}>", "a\nbb\n\nc\nd\n|\n\ne")
	check("a\nbb\n\nc\nd\n\n|\ne", "<M-}>", "a\nbb\n\nc\nd\n\n\ne|")
	check("a\nbb\n\nc\nd|", "<M-}>", "a\nbb\n\nc\nd|")
	check("a\nbb\n \t\nc|c\nd", "<M-{>", "a\nbb\n| \t\ncc\nd")
	check("a\nbb\n\n|cc", "<M-{>", "a\nbb\n|\ncc")
	check("a\nbb\n|\ncc", "<M-{>", "|a\nbb\n\ncc")
	check("a\nb|b\n\ncc", "<M-}><M-}><M-{><M-{>", "|a\nbb\n\ncc")
	check("a\nb|b\n\ncc", "<M-S-]>", "a\nbb\n|\ncc")
	check("a\nbb\n\nc|c", "<M-S-[>", "a\nbb\n|\ncc")
end

cases["C-v, M-v, C-l and M-r work on the window"] = function()
	vim.cmd.new()
	vim.cmd.resize(10)
	vim.wo.scrolloff = 0
	vim.wo.wrap = false
	local lines = {}
	for i = 1, 100 do
		lines[i] = "line " .. i
	end
	local spec = table.concat(lines, "\n"):gsub("line 50", "lin|e 50", 1)
	-- the full configuration lazy-loads neoscroll, which animates these keys
	local smooth = pcall(require, "neoscroll")
	local function at(label)
		local snapshot = T.snaps[label]
		return { snapshot.top, snapshot.pos[1], snapshot.pos[2], snapshot.screen_row, snapshot.active }
	end

	session(
		"|" .. table.concat(lines, "\n"),
		"<C-v>" .. snap("down") .. "<C-v>" .. snap("down2") .. "<M-v><M-v>" .. snap("up")
	)
	if smooth then
		eq({ 11, 11, 0, 1, true }, at("down"), "C-v")
		eq({ 21, 21, 0, 1, true }, at("down2"), "C-v again")
	else
		-- a window of 10 lines scrolls by 8, keeping 2 lines on the screen
		eq({ 9, 9, 0, 1, true }, at("down"), "C-v")
		eq({ 17, 17, 0, 1, true }, at("down2"), "C-v again")
	end
	eq(1, T.snaps.up.top, "M-v")

	if smooth then
		local guicursor = vim.o.guicursor
		open(spec)
		feed("e<C-v>" .. snap("scrolled") .. "<C-v><Esc>")
		eq(true, T.snaps.scrolled.active, "the mode after C-v")
		assert(
			vim.wait(2000, function()
				return not emacs.is_active()
			end, 5),
			"the mode stays on after Esc during the animation"
		)
		settle()
		eq({ guicursor, {} }, { vim.o.guicursor, buffer_maps(0) }, "after Esc during the animation")

		-- the mode ends right after Esc, before the animation is over, so that Insert mode entered again during
		-- the animation is plain Insert mode
		open(spec)
		feed("e<C-v><Esc>")
		local scrolling_then
		assert(
			vim.wait(2000, function()
				scrolling_then = require("neoscroll.scroll").scrolling
				return not emacs.is_active()
			end, 1),
			"the mode stays on after Esc during the animation"
		)
		eq(true, scrolling_then, "the mode ended only after the animation")
		settle()

		open(spec)
		feed("e<C-v><C-o>:enew<CR>")
		table.insert(buffers, vim.api.nvim_get_current_buf())
		settle()
		feed("<Esc>")
		eq(
			{ false, guicursor },
			{ emacs.is_active(), vim.o.guicursor },
			"after leaving the buffer during the animation"
		)
	end

	-- the state after every command, since a snapshot between them would be a key that ends the cycle
	local function after_each(input)
		local run = emacs.run
		local states = {}
		emacs.run = function(name)
			run(name)
			T.snap("command")
			table.insert(states, T.snaps.command)
		end
		local ok, err = pcall(session, spec, input)
		emacs.run = run
		assert(ok, err)
		return vim.tbl_map(function(state)
			return { state.top, state.pos[1], state.pos[2], state.screen_row }
		end, states)
	end
	eq(
		{ 5, 1, 10, 5 },
		vim.tbl_map(function(state)
			return state[4]
		end, after_each("<C-l><C-l><C-l><C-l>")),
		"screen row of the cursor after C-l"
	)
	eq(
		{ 5, 1, 1, 5 },
		vim.tbl_map(function(state)
			return state[4]
		end, after_each("<C-l><C-l><C-f><C-l>")),
		"C-l after another key"
	)
	local states = after_each("<C-l><C-l><C-l><C-l>")
	eq({ 50, 3 }, { states[4][2], states[4][3] }, "C-l moves no cursor")

	eq(
		{ { 46, 50, 3, 5 }, { 46, 50, 0, 5 }, { 46, 46, 0, 1 }, { 46, 55, 0, 10 } },
		after_each("<C-l><M-r><M-r><M-r>"),
		"M-r"
	)
	vim.cmd.close()

	check("ab\nabc|", "<C-l>", "ab\nabc|")
end

cases["CTRL-O keeps the mode; leaving the buffer or window ends it for good"] = function()
	check("ab|c", "<C-o>:let g:emacs_test = 1<CR><C-k>", "ab|", "c")
	check("ab|c", "<C-o>0<C-e>X", "abcX|")
	check("ab|c", '<C-o>:normal! "_x<CR><C-a>Y', "Y|ab")

	open("ab|c")
	feed("e<C-o>:stopinsert<CR>")
	assert(
		vim.wait(1000, function()
			return not emacs.is_active()
		end),
		"still on after CTRL-O :stopinsert"
	)
	eq({}, buffer_maps(0))

	open("ab|c")
	local first = vim.api.nvim_get_current_buf()
	feed("e<C-o>:enew<CR>" .. snap("left") .. "<C-o>:buffer " .. first .. "<CR>" .. snap("back") .. "<Esc>")
	eq({ "i", false }, { T.snaps.left.mode, T.snaps.left.active }, "after leaving the buffer")
	eq({ first, false }, { T.snaps.back.buf, T.snaps.back.active }, "back in the buffer")
	eq({}, buffer_maps(first))
	table.insert(buffers, vim.api.nvim_get_current_buf())

	open("ab|c")
	vim.cmd.split()
	feed("e<C-o><C-w>w" .. snap("left") .. "<C-o><C-w>w" .. snap("back") .. "<Esc>")
	eq({ false, false }, { T.snaps.left.active, T.snaps.back.active }, "after leaving the window")
	eq({}, buffer_maps(0))
	vim.cmd.close()

	open("ab|c")
	local doomed = vim.api.nvim_get_current_buf()
	vim.cmd("split | enew")
	table.insert(buffers, vim.api.nvim_get_current_buf())
	vim.cmd("wincmd p")
	feed("e" .. snap("on") .. ("<Cmd>bwipeout! %d<CR>"):format(doomed) .. snap("wiped") .. "<Esc>")
	eq({ true, false }, { T.snaps.on.active, T.snaps.wiped.active }, "after the buffer was wiped out")
	vim.cmd.only()
end

cases["setup can run again"] = function()
	local function registered()
		return #vim.api.nvim_get_autocmds({ group = "emacs_mode" })
	end
	local before = registered()
	open("ab|c")
	feed("e<Cmd>lua require('emacs-mode').setup({ start_key = 'e' })<CR>" .. snap("again") .. "<Esc>")
	eq(false, T.snaps.again.active, "setup ends the mode")
	eq({}, buffer_maps(0))
	emacs.setup(OPTS)
	eq(before, registered())
	check("a|bc\nd", "<C-k><C-k>", "a|d", "bc\n")
end

cases["mappings of the buffer come back as they were"] = function()
	open("ab|c")
	local buf = vim.api.nvim_get_current_buf()
	_G.emacs_test_bs = function()
		return "<BS>"
	end
	vim.keymap.set("i", "<C-k>", function()
		return "K"
	end, { buffer = true, expr = true, replace_keycodes = false, desc = "callback" })
	vim.api.nvim_buf_set_keymap(buf, "i", "<BS>", "v:lua.emacs_test_bs()", { expr = true, noremap = true })
	vim.api.nvim_buf_set_keymap(buf, "i", "<C-a>", "<C-k>", { silent = true, nowait = true })
	vim.api.nvim_buf_set_keymap(buf, "i", "<M-f>", "", {
		callback = function() end,
		desc = "lua callback",
	})
	vim.keymap.set("i", "<C-y>", "GLOBAL")
	local function maps()
		local found = {}
		for _, lhs in ipairs(mode_keys) do
			found[lhs] = vim.fn.maparg(lhs, "i", false, true)
		end
		return found
	end
	-- plugins may map keys of their own on the first InsertEnter of a buffer (blink.cmp does)
	feed("i<Esc>")
	local before = maps()
	vim.api.nvim_buf_set_lines(0, 0, -1, true, { "abc" })
	edit.store("Y", "replace")
	feed("e<C-k><C-y><Cmd>lua vim.keymap.set('i', '<lt>C-e>', 'OTHER', { buffer = true })<CR>" .. snap("on") .. "<Esc>")
	eq("abc|", T.snaps.on.text, "the mode's keys win while it is on")
	local after = maps()
	eq("OTHER", after["<C-e>"].rhs, "a mapping set while the mode was on")
	before["<C-e>"], after["<C-e>"] = nil, nil
	for _, lhs in ipairs(mode_keys) do
		eq(before[lhs], after[lhs], "mapping of " .. lhs)
	end
	feed("A<C-k><Esc>")
	eq("abcK", text(), "the callback mapping works again")
	vim.keymap.del("i", "<C-y>")
end

cases["registers stay untouched"] = function()
	-- with 'clipboard' the unnamed register is the system clipboard; the mode reads and writes no register either way
	local clipboard = vim.o.clipboard
	vim.o.clipboard = ""
	local names = { '"', "-", "0", "1", "a", "." }
	open("|x")
	feed("ireg<Esc>")
	for _, name in ipairs(names) do
		if name ~= "." then
			vim.fn.setreg(name, "reg " .. name)
		end
	end
	local function registers()
		local found = {}
		for _, name in ipairs(names) do
			found[name] = vim.fn.getreg(name)
		end
		return found
	end
	local before = registers()
	session(
		"foo bar| baz\nqux",
		"<C-k><C-k><C-u><M-BS><M-d><C-y><C-d><BS><C-t><C-Space><C-e><C-x><C-u><C-x><C-t><M-^><M-@><M-y><Esc><C-S-BS><M-q>"
	)
	local after = registers()
	vim.o.clipboard = clipboard
	eq(before, after)
end

local function each(rows)
	for _, row in ipairs(rows) do
		check(unpack(row))
	end
end

local function kill_ago(n)
	return edit.entries()[n + 1]
end

local function kills(...)
	for _, killed in ipairs({ ... }) do
		edit.store(killed, "replace")
	end
end

-- Options are global because new buffers take them.
local function with_options(options, fn)
	local saved = {}
	for name, value in pairs(options) do
		saved[name] = vim.go[name]
		vim.go[name] = value
	end
	local ok, err = pcall(fn)
	for name, value in pairs(saved) do
		vim.go[name] = value
	end
	assert(ok, err)
end

local TABS = { tabstop = 8, expandtab = false }

cases["alias keys do what their Emacs keys do"] = function()
	each({
		{ "ab|c\nd", "<Right>", "abc|\nd" },
		{ "ab|c\nd", "<kRight>", "abc|\nd" },
		{ "ab|c", "<Left>", "a|bc" },
		{ "ab|c", "<kLeft>", "a|bc" },
		{ "a|bc\ndef", "<Down>", "abc\nd|ef" },
		{ "a|bc\ndef", "<kDown>", "abc\nd|ef" },
		{ "abc\nd|ef", "<Up>", "a|bc\ndef" },
		{ "abc\nd|ef", "<kUp>", "a|bc\ndef" },
		{ "  ab|cd", "<Home>", "|  abcd" },
		{ "  ab|cd", "<kHome>", "|  abcd" },
		{ "  ab|cd", "<End>", "  abcd|" },
		{ "  ab|cd", "<kEnd>", "  abcd|" },
		{ "|foo bar", "<C-Right>", "foo| bar" },
		{ "|foo bar", "<M-Right>", "foo| bar" },
		{ "foo ba|r", "<C-Left>", "foo |bar" },
		{ "foo ba|r", "<M-Left>", "foo |bar" },
		{ "a\nb|c", "<C-Home>", "|a\nbc" },
		{ "a\nb|c", "<kOrigin>", "|a\nbc" },
		{ "a\nb|c\nd", "<C-End>", "a\nbc\nd|" },
		{ "a\nb|b\n\nc", "<C-Down>", "a\nbb\n|\nc" },
		{ "a\nbb\n\nc|c", "<C-Up>", "a\nbb\n|\ncc" },
		{ "ab|\ncd", "<kDel>", "ab|cd" },
		{ "foo bar|", "<C-BS>", "foo |", "bar" },
		{ "|foo bar", "<C-Del>", "| bar", "foo" },
		{ "ab|cd", "<C-Space><C-e><C-Insert><S-Insert>", "abcdcd|", "cd" },
		{ "ab|cd", "<C-Space><C-e><S-Del>", "ab|", "cd" },
	})
end

cases["M-m goes to the first character that is not a blank"] = function()
	each({
		{ "  ab|c", "<M-m>", "  |abc" },
		{ "\t\tab|c", "<M-m>", "\t\t|abc" },
		{ "\u{3000}\u{3000}ab|c", "<M-m>", "\u{3000}\u{3000}|abc" },
		{ "  |abc", "<M-m>", "  |abc" },
		{ "|abc", "<M-m>", "|abc" },
		{ "x\n  |", "<M-m>", "x\n  |" },
		{ "x\n \t|  \ny", "<M-m>", "x\n \t  |\ny" },
	})
end

cases["M-g goes to a line, a character or a column"] = function()
	each({
		{ "|a\nb\nc", "<M-g>g2<CR>", "a\n|b\nc" },
		{ "|a\nb\nc", "<M-g><M-g>3<CR>", "a\nb\n|c" },
		{ "|a\nb\nc", "<M-g>g99<CR>", "a\nb\nc|" },
		{ "a\nb|\nc", "<M-g>g0<CR>", "|a\nb\nc" },
		{ "a\nb|\nc", "<M-g>g<Esc>", "a\nb|\nc" },
		{ "a\nb|\nc", "<M-g>gx<CR>", "a\nb|\nc" },
		{ "a\nb|\nc", "<M-g>g1.5<CR>", "a\nb|\nc" },
		{ "|ab\ncd", "<M-g>c4<CR>", "ab\n|cd" },
		{ "|ab\ncd", "<M-g>c1<CR>", "|ab\ncd" },
		{ "|ab\ncd", "<M-g>c99<CR>", "ab\ncd|" },
		{ "|日本語\nx", "<M-g>c3<CR>", "日本|語\nx" },
		{ "|e\u{301}x", "<M-g>c2<CR>", "|e\u{301}x" },
		{ "|e\u{301}x", "<M-g>c3<CR>", "e\u{301}|x" },
		{ "|👨‍👩‍👧x", "<M-g>c6<CR>", "👨‍👩‍👧|x" },
		{ "|abcdef", "<M-g><Tab>3<CR>", "abc|def" },
		{ "|abcdef", "<M-g><Tab>0<CR>", "|abcdef" },
		{ "|ab", "<M-g><Tab>9<CR>", "ab|" },
		{ "|あいう", "<M-g><Tab>3<CR>", "あい|う" },
		{ "|あいう", "<M-g><Tab>2<CR>", "あ|いう" },
		{ "a\n|bcdef\nx", "<M-g><Tab>2<CR>", "a\nbc|def\nx" },
	})
	with_options(TABS, function()
		check("|\tx", "<M-g><Tab>4<CR>", "\t|x")
	end)
end

cases["a prefix key waits for the next key, or is given up with Esc or C-g"] = function()
	each({
		{ "ab|c", "<C-x><Esc>X", "abX|c" },
		{ "ab|c", "<C-x><C-g>X", "abX|c" },
		{ "ab|c", "<C-x>zX", "abX|c" },
		{ "ab|c", "<M-g><Esc>X", "abX|c" },
		{ "ab|c", "<M-g>zX", "abX|c" },
		{ "ab|c", "<C-x><C-x>X", "abX|c" },
	})
end

cases["a prefix key does not time out and keeps the keys after it"] = function()
	local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
	local chan = vim.fn.jobstart({
		vim.v.progpath,
		"--embed",
		"--headless",
		"--clean",
		"-n",
		"-i",
		"NONE",
		"--cmd",
		"set rtp^=" .. root,
	}, { rpc = true })
	local function call(name, ...)
		return vim.rpcrequest(chan, name, ...)
	end
	local ok, err = pcall(function()
		call("nvim_exec_lua", [[require("emacs-mode").setup({ start_key = "e" })]], {})
		call("nvim_buf_set_lines", 0, 0, -1, true, { "abc", "def" })
		call("nvim_input", "e")
		vim.wait(200)
		local timeout = call("nvim_get_option_value", "timeoutlen", {})
		call("nvim_input", "<C-x>")
		vim.wait(timeout + 600)
		call("nvim_input", "h")
		vim.wait(200)
		local selected =
			call("nvim_exec_lua", [[return require("emacs-mode.region").is_active(vim.api.nvim_get_current_buf())]], {})
		eq({ true, "i" }, { selected, call("nvim_get_mode").mode }, "C-x h after the wait")

		call("nvim_input", "<C-g>")
		call("nvim_input", "<M-g>")
		vim.wait(timeout + 600)
		call("nvim_input", "g2<CR>")
		vim.wait(200)
		eq({ 2, "i" }, { call("nvim_win_get_cursor", 0)[1], call("nvim_get_mode").mode }, "M-g g after the wait")
	end)
	pcall(vim.fn.jobstop, chan)
	assert(ok, err)
end

cases["BS and Delete delete the selection, C-d only a character"] = function()
	edit.store("kept", "replace")
	each({
		{ "ab|cdef", "<C-Space><C-f><C-f><BS>", "ab|ef", "kept" },
		{ "abcd|ef", "<C-Space><C-b><C-b><BS>", "ab|ef", "kept" },
		{ "ab|cdef", "<C-Space><C-f><C-f><Del>", "ab|ef", "kept" },
		{ "ab|cdef", "<C-Space><C-f><C-f><C-h>", "ab|ef", "kept" },
		{ "ab|c\ndef", "<C-Space><C-n><BS>", "ab|f", "kept" },
		{ "ab|cdef", "<C-Space><C-f><C-f><C-d>", "abcd|f", "kept" },
		{ "ab|cdef", "<C-Space><BS>", "a|cdef", "kept" },
		{ "ab|cdef", "<C-Space><Del>", "ab|def", "kept" },
		{ "ab|cdef", "<C-Space><C-f><C-g><BS>", "ab|def", "kept" },
		{ "|日本語abc", "<S-Right><S-Right><BS>", "|語abc", "kept" },
		{ "ab|c", "<BS>", "a|c", "kept" },
	})
	local state = session("ab|cdef", "<C-Space><C-f><C-f><BS>" .. snap("end"))
	state = T.snaps["end"]
	eq({ nil, false, { 0, 2 } }, { state.region, state.selected, state.mark }, "selection and mark after BS")
end

cases["C-x DEL kills back to the start of the sentence"] = function()
	each({
		{ "One. Two. Th|ree", "<C-x><BS>", "One. Two. |ree", "Th" },
		{ "One. Two. Th|ree", "<C-x><BS><C-x><BS>", "One. |ree", "Two. Th" },
		{ "One. Two. Th|ree", "<C-x><C-h>", "One. Two. |ree", "Th" },
		{ "|One", "<C-x><BS>", "|One" },
	})
	local before = kill_ago(0)
	check("One. Two. Th|ree", "<C-k><C-x><BS>", "One. Two. |", "Three")
	eq(before, kill_ago(1), "C-k and C-x DEL in a row make one kill")
end

cases["kills join with C-M-w, also with keys of two strokes"] = function()
	local before = kill_ago(0)
	check("aa bb| cc dd", "<M-d><M-f><C-M-w><M-BS>", "aa bb |", "dd cc")
	eq(before, kill_ago(1), "C-M-w joins the kill")
	before = kill_ago(0)
	check("aa bb| cc dd", "<M-d><M-f><M-BS>", "aa bb |", "dd")
	eq({ " cc", before }, { kill_ago(1), kill_ago(2) }, "without C-M-w the kills are separate")
	check("One. Two. Th|ree", "<C-k><C-b><C-M-w><C-x><BS>", "One. Two. |h", "Tree")
	check("aa| bb cc", "<M-d><C-M-w><C-S-BS>", "|", "aa bb cc")
	check("aa| bb cc dd", "<M-d><C-Space><C-e><C-x><C-x><C-M-w><C-w>", "aa|", " cc dd bb")
	check("aa bb cc| dd", "<M-d><C-b><C-b><C-b><C-Space><C-f><C-f><C-f><C-M-w><C-w>", "aa bb|", " dd cc")
	check("aa| bb cc", "<M-d><C-M-w><C-f><M-d>", "aa |", "cc")
	edit.store("old", "replace")
	check("x|y", "<C-M-w><C-k>", "x|", "oldy")
end

cases["C-S-BS kills the whole line with its line break"] = function()
	each({
		{ "a\nb|c\nd", "<C-S-BS>", "a\n|d", "bc\n" },
		{ "a\n|bc\nd", "<C-S-BS>", "a\n|d", "bc\n" },
		{ "a\nbc|\nd", "<C-S-BS>", "a\n|d", "bc\n" },
		{ "a\nb|c\nd", "<C-S-BS><C-S-BS>", "a\n|", "bc\nd" },
		{ "a\nb|c", "<C-S-BS>", "a\n|", "bc" },
		{ "a\nb|c\nd", "<C-k><C-S-BS>", "a\n|d", "bc\n" },
		{ "a\n|\nd", "<C-S-BS>", "a\n|d", "\n" },
		{ "|日本語\nx", "<C-S-BS>", "|x", "日本語\n" },
		{ "x|", "<C-S-BS>", "|", "x" },
	})
	edit.store("kept", "replace")
	check("a\n|", "<C-S-BS>", "a\n|", "kept")
	check("|", "<C-S-BS>", "|", "kept")
end

cases["the mark stays when the selection is dropped, and is separate from the selection"] = function()
	session("ab|cdef", "<C-Space><C-f><C-f>" .. snap("on") .. "<C-g>" .. snap("quit") .. "<C-f>" .. snap("moved"))
	eq({ true, { 0, 2 }, { 0, 2, 0, 4 } }, { T.snaps.on.selected, T.snaps.on.mark, T.snaps.on.region })
	eq({ false, { 0, 2 }, nil }, { T.snaps.quit.selected, T.snaps.quit.mark, T.snaps.quit.region }, "after C-g")
	eq({ false, nil }, { T.snaps.moved.selected, T.snaps.moved.region }, "a move after C-g")
	session("ab|cdef", "<C-Space><C-f><C-f><C-g><C-f><C-x><C-x>" .. snap("swapped"))
	eq({ "ab|cdef", true, { 0, 5 }, { 0, 2, 0, 5 } }, {
		T.snaps.swapped.text,
		T.snaps.swapped.selected,
		T.snaps.swapped.mark,
		T.snaps.swapped.region,
	})
	check("ab|cdef", "<C-Space><C-f><C-f><C-x><C-x><C-w>", "ab|ef", "cd")
	check("ab|cdef", "<C-x><C-x>X", "abX|cdef")
	session("ab|cd", "<C-Space><C-f><C-Space><C-Space>" .. snap("off") .. "<C-Space>" .. snap("on"))
	eq({ false, nil, { 0, 3 } }, { T.snaps.off.selected, T.snaps.off.region, T.snaps.off.mark })
	eq({ true, { 0, 3, 0, 3 } }, { T.snaps.on.selected, T.snaps.on.region })
	session("ab|cd", "<C-Space><C-g>X<C-b><C-Space>" .. snap("again"))
	eq(true, T.snaps.again.selected)
end

cases["typing does not replace the selection, which ends"] = function()
	local idle = "<Cmd>doautocmd CursorMovedI<CR><Cmd>doautocmd TextChangedI<CR>"
	session("ab|cd", "<C-Space><C-f>" .. idle .. "X" .. idle .. snap("typed"))
	eq({ "abcX|d", false, nil, { 0, 2 } }, {
		T.snaps.typed.text,
		T.snaps.typed.selected,
		T.snaps.typed.region,
		T.snaps.typed.mark,
	})
	session("ab|cd", "<S-Right>" .. idle .. "X" .. idle .. snap("typed"))
	eq({ "abcX|d", false, nil }, { T.snaps.typed.text, T.snaps.typed.selected, T.snaps.typed.region })
end

cases["Shift moves select, and a move without Shift ends a selection that Shift started"] = function()
	local function state_after(input, spec)
		session(spec or "ab|cdef\nxyz", input .. snap("end"))
		return T.snaps["end"]
	end
	local state = state_after("<S-Right><S-Right>")
	eq({ true, { 0, 2, 0, 4 }, { 0, 2 } }, { state.selected, state.region, state.mark }, "S-Right")
	eq({ 0, 4 }, { state.pos[1] - 1, state.pos[2] })
	state = state_after("<S-Right><S-Right><Right>")
	eq({ false, nil, { 0, 2 } }, { state.selected, state.region, state.mark }, "Right after S-Right")
	eq(5, state.pos[2], "Right still moves")
	each({
		{ "ab|cdef\nxyz", "<S-Left><C-w>", "a|cdef\nxyz", "b" },
		{ "ab|cdef\nxyz", "<S-End><C-w>", "ab|\nxyz", "cdef" },
		{ "ab|cdef\nxyz", "<S-Home><C-w>", "|cdef\nxyz", "ab" },
		{ "ab|cdef\nxyz", "<S-Down><C-w>", "ab|z", "cdef\nxy" },
		{ "ab|cdef\nxyz", "<C-S-Right><C-w>", "ab|\nxyz", "cdef" },
		{ "ab|cdef\nxyz", "<M-S-Right><C-w>", "ab|\nxyz", "cdef" },
		{ "ab cd|", "<C-S-Left><C-w>", "ab |", "cd" },
		{ "ab|cdef\nxyz", "<C-S-End><C-w>", "ab|", "cdef\nxyz" },
		{ "ab|cdef\nxyz", "<S-Right><S-Right><S-Right><C-w>", "ab|f\nxyz", "cde" },
		{ "a\nb|\n\nc", "<C-S-Down><C-w>", "a\nb|\nc", "\n" },
	})
	each({
		{ "|abcdef\nghijkl", "<S-Right><M-g>g2<CR><BS>", "abcdef|ghijkl" },
		{ "|abcdef\nghijkl", "<S-Right><M-g>c9<CR><BS>", "abcdef\n|hijkl" },
		{ "|abcdef\nghijkl", "<S-Right><M-g><Tab>3<CR><BS>", "ab|def\nghijkl" },
		{ "|abcdef\nghijkl", "<C-Space><M-g>g2<CR><BS>", "|ghijkl" },
		{ "|abcdef\nghijkl", "<C-Space><M-g><Tab>3<CR><BS>", "|def\nghijkl" },
	})
	state = state_after("<C-Space><Right><Right><Right>")
	eq({ true, { 0, 2, 0, 5 } }, { state.selected, state.region }, "moves after C-SPC")
	state = state_after("<C-Space><Right><Right><S-Right>")
	eq({ true, { 0, 4, 0, 5 }, { 0, 4 } }, { state.selected, state.region, state.mark }, "S-Right after C-SPC")
	state = state_after("<S-Right><S-Right><C-x><C-x><Right>")
	eq(false, state.selected, "Right after C-x C-x of a Shift selection")
	state = state_after("<S-PageDown>", "|a\nb\nc")
	eq(true, state.selected, "S-PageDown")
end

cases["M-@ marks the next word, and again one word further"] = function()
	session("|foo bar baz", "<M-@>" .. snap("end"))
	local state = T.snaps["end"]
	eq({ "|foo bar baz", true, { 0, 0, 0, 3 } }, { state.text, state.selected, state.region })
	edit.store("kept", "replace")
	each({
		{ "|foo bar baz", "<M-@><M-@><C-w>", "| baz", "foo bar" },
		{ "|foo bar baz", "<M-@><M-@><M-@><C-w>", "|", "foo bar baz" },
		{ "foo bar| baz", "<M-@><C-x><C-x><M-@><C-w>", "foo |", "bar baz" },
		{ "a|b c", "<C-Space><M-@><C-w>", "a| c", "b" },
		{ "|日本語 abc", "<M-@><C-w>", "| abc", "日本語" },
	})
	edit.store("kept", "replace")
	check("x|", "<M-@><C-w>", "x|", "kept")
end

cases["C-x h selects the buffer, M-h again takes the next paragraph"] = function()
	each({
		{ "a\nb|c\nd", "<C-x>h<C-w>", "|", "a\nbc\nd" },
		{ "a\nb|c\nd", "<C-x>h<C-x><C-x><C-w>", "|", "a\nbc\nd" },
		{ "a\n\nb|1\nb2\n\nc1\n\nd", "<M-h><M-h><C-w>", "a\n|\nd", "\nb1\nb2\n\nc1\n" },
		{ "a\n\nb|1\nb2\n\nc1", "<M-h><M-h><M-h><C-w>", "a\n|", "\nb1\nb2\n\nc1" },
	})
end

cases["C-y sets the mark at the start of what it puts, without a selection"] = function()
	edit.store("abc", "replace")
	session("x|y", "<C-y>" .. snap("end"))
	local state = T.snaps["end"]
	eq({ "xabc|y", false, { 0, 1 }, nil }, { state.text, state.selected, state.mark, state.region })
	check("x|y", "<C-y><C-x><C-x>X", "xX|abcy")
	check("x|y", "<C-y><C-x><C-u>", "xABC|y")
	edit.store("def", "replace")
	edit.store("abc", "replace")
	check("x|y", "<C-y><M-y><C-x><C-u>", "xDEF|y")
end

cases["M-y alone asks which kill to put"] = function()
	kills("a", "b", "c")
	each({
		{ "x|", "<M-y>2<CR>", "xb|" },
		{ "x|", "<M-y>1<CR>", "xc|" },
		{ "x|", "<M-y>3<CR>", "xa|" },
		{ "x|", "<M-y><Esc>", "x|" },
		{ "x|", "<M-y>q", "x|" },
		{ "x|", "<M-y>2<CR><C-y>", "xbb|" },
		{ "x|", "<M-y>2<CR><M-y>3<CR>", "xba|" },
		{ "x|", "<M-y>2<CR><C-x><C-u>", "xB|" },
	})
	kills("l1\nl2", "s")
	check("x|y", "<M-y>2<CR>", "xl1\nl2|y")
	session("x|", "<M-y>2<CR><C-/>" .. snap("undone"))
	eq("x", (T.snaps.undone.text:gsub("|", "")))

	local select = vim.ui.select
	vim.ui.select = function(items, _, callback)
		vim.schedule(function()
			callback(items[2])
		end)
	end
	kills("a", "b", "c")
	session("x|", "<M-y>")
	local put = vim.wait(1000, function()
		return text() == "xb"
	end)
	vim.ui.select = select
	assert(put, "the kill is not put: " .. text())
end

cases["C-t swaps the characters around the cursor"] = function()
	each({
		{ "a|bc", "<C-t>", "ba|c" },
		{ "ab|c", "<C-t><C-t>", "abc|" },
		{ "abc|", "<C-t>", "acb|" },
		{ "ab|\ncd", "<C-t>", "ba|\ncd" },
		{ "|ab", "<C-t>", "|ab" },
		{ "|", "<C-t>", "|" },
		{ "a|", "<C-t>", "a|" },
		{ "あ|い", "<C-t>", "いあ|" },
		{ "e\u{301}|x", "<C-t>", "xe\u{301}|" },
		{ "a|👨‍👩‍👧b", "<C-t>", "👨‍👩‍👧a|b" },
		{ "a🇯🇵|b", "<C-t>", "ab🇯🇵|" },
		{ "ab\n|cd", "<C-t>", "abc\n|d" },
		{ "ab|\n", "<C-t>", "ba|\n" },
	})
end

cases["C-x C-t swaps the line with the one before it"] = function()
	each({
		{ "a\nb|c\nd", "<C-x><C-t>", "bc\na\n|d" },
		{ "a\nb|c", "<C-x><C-t>", "bc\na|" },
		{ "a|\nb\nc", "<C-x><C-t>", "b\na\n|c" },
		{ "a\nb|\nc\nd", "<C-x><C-t><C-x><C-t>", "b\nc\na\n|d" },
		{ "|x", "<C-x><C-t>", "|x" },
		{ "日本\n|語", "<C-x><C-t>", "語\n日本|" },
	})
end

cases["C-x C-u and C-x C-l change the case of the region"] = function()
	each({
		{ "ab|cd\nef", "<C-Space><C-e><C-x><C-u>", "abCD|\nef" },
		{ "ABCD|EF", "<C-Space><C-b><C-b><C-x><C-l>", "AB|cdEF" },
		{ "|日本語 abc é\nxy", "<C-Space><C-e><C-x><C-u>", "日本語 ABC É|\nxy" },
		{ "|ÀB e\u{301}x", "<C-Space><C-e><C-x><C-l>", "àb e\u{301}x|" },
		{ "|ab\ncd", "<C-Space><C-n><C-e><C-x><C-u>", "AB\nCD|" },
		-- the upper case of a letter can be shorter in bytes
		{ "|aı", "<C-Space><C-e><C-x><C-u>", "AI|" },
		{ "ab|cd", "<C-Space><C-e><C-g><C-x><C-u>", "abCD|" },
		{ "ab|cd", "<S-End><C-x><C-u>", "abCD|" },
		{ "ab|cd", "<C-Space><C-x><C-u>", "ab|cd" },
		{ "ab|cd", "<C-x><C-u>", "ab|cd" },
		{ "ab|cd", "<C-x><C-l>", "ab|cd" },
	})
	session("ab|cd", "<C-Space><C-e><C-x><C-u>" .. snap("end"))
	local state = T.snaps["end"]
	eq({ false, { 0, 2 } }, { state.selected, state.mark }, "selection and mark after C-x C-u")
	session("ab|ı", "<C-Space><C-e><C-x><C-x><C-x><C-u>" .. snap("end"))
	state = T.snaps["end"]
	eq({ "ab|I", { 0, 3 } }, { state.text, state.mark })
end

cases["M-SPC goes from one space to none and back to the blanks it found"] = function()
	each({
		{ "a  | \tb", "<M-Space>", "a |b" },
		{ "a  | \tb", "<M-Space><M-Space>", "a|b" },
		{ "a  | \tb", "<M-Space><M-Space><M-Space>", "a  | \tb" },
		{ "a  | \tb", "<M-Space><M-Space><M-Space><M-Space>", "a |b" },
		{ "a|b", "<M-Space><M-Space><M-Space>", "a|b" },
		{ "a\u{3000}|b", "<M-Space>", "a\u{3000} |b" },
		{ "a |\nb", "<M-Space><M-Space><M-Space>", "a |\nb" },
		{ "a  |b", "<M-Space>X<M-Space>", "a X |b" },
	})
end

cases["M-^ joins the line to the one before it"] = function()
	each({
		{ "foo\n  |bar", "<M-^>", "foo| bar" },
		{ "foo  \n\t|bar", "<M-^>", "foo| bar" },
		{ "foo(\n  |bar)", "<M-^>", "foo(|bar)" },
		{ "(foo\n|)", "<M-^>", "(foo|)" },
		{ "foo\n|", "<M-^>", "foo|" },
		{ "\n|foo", "<M-^>", "|foo" },
		{ "日本語\n  |テキスト", "<M-^>", "日本語|テキスト" },
		{ "foo\n  |テキスト", "<M-^>", "foo|テキスト" },
		{ "|foo", "<M-^>", "|foo" },
		{ "a\nb\n|c", "<C-Space><C-p><C-p><M-^>", "a| b c" },
		{ "a\n|b\nc", "<C-Space><C-n><M-^>", "a\nb| c" },
	})
end

cases["C-M-o splits the line and keeps the rest in its column"] = function()
	each({
		{ "foo b|ar", "<C-M-o>", "foo b|\n     ar" },
		{ "foo | bar", "<C-M-o>", "foo  |\n     bar" },
		{ "|foo", "<C-M-o>", "|\nfoo" },
		{ "foo|", "<C-M-o>", "foo|\n   " },
		{ "日本|語", "<C-M-o>", "日本|\n    語" },
	})
	with_options(TABS, function()
		check("\tab|cd", "<C-M-o>", "\tab|\n\t  cd")
	end)
	with_options({ tabstop = 4, expandtab = true }, function()
		check("\tab|cd", "<C-M-o>", "\tab|\n      cd")
	end)
end

cases["C-x C-o removes blank lines"] = function()
	each({
		{ "a\n|\n\n\nb", "<C-x><C-o>", "a\n|\nb" },
		{ "a\n\n|\n\nb", "<C-x><C-o>", "a\n|\nb" },
		{ "a\n|\nb", "<C-x><C-o>", "a\n|b" },
		{ "a|\n\n\nb", "<C-x><C-o>", "a|\nb" },
		{ "a|\nb", "<C-x><C-o>", "a|\nb" },
		{ "a\n \t|\n\nb", "<C-x><C-o>", "a\n \t|\nb" },
		{ "a\n|\n", "<C-x><C-o>", "a\n|" },
		{ "|", "<C-x><C-o>", "|" },
	})
end

local function width_keys(width)
	return ("<C-x>f<C-u>%d<CR>"):format(width)
end

cases["M-q fills the paragraph at the width C-x f set"] = function()
	local textwidth = vim.go.textwidth
	each({
		{ "|aaa bbb ccc ddd eee fff ggg hhh", width_keys(20) .. "<M-q>", "|aaa bbb ccc ddd eee\nfff ggg hhh" },
		{ "|aaa\nbbb\nccc", "<M-q>", "|aaa bbb ccc" },
		{ "aaa\nbb|b\n\nccc\nddd", "<M-q>", "aaa bb|b\n\nccc\nddd" },
		{ "a\n|\nb\nc", "<M-q>", "a\n|\nb c" },
		{ "aaaa  bbbb cccc|", width_keys(10) .. "<M-q>", "aaaa bbbb\ncccc|" },
		{ "  |aaa bbb ccc ddd", width_keys(12) .. "<M-q>", "  |aaa bbb\n  ccc ddd" },
		{ "|aaa bbb ccc ddd\n    eee", width_keys(12) .. "<M-q>", "|aaa bbb ccc\n    ddd eee" },
		{ "aaa b|bb ccc", "<C-x>f<CR><M-q>", "aaa\nb|bb\nccc" },
	})
	eq(textwidth, vim.go.textwidth, "'textwidth'")
	open("|x")
	feed("e" .. width_keys(33) .. "<Esc>")
	eq(33, vim.b.emacs_fill_column)
	open("|x")
	eq(nil, vim.b.emacs_fill_column)
	vim.go.textwidth = 12
	check("|aaa bbb ccc ddd", "<M-q>", "|aaa bbb ccc\nddd")
	vim.go.textwidth = textwidth
end

cases["M-q breaks Japanese and English text where it is allowed"] = function()
	each({
		{
			"|日本語の文章です。次の文です。",
			width_keys(12) .. "<M-q>",
			"|日本語の文章\nです。次の文\nです。",
		},
		{ "|あいうえお。かきく", width_keys(10) .. "<M-q>", "|あいうえ\nお。かきく" },
		{ "|日本語\nEnglish\nword", "<M-q>", "|日本語English word" },
		{ "|日本語\n日本語", "<M-q>", "|日本語日本語" },
		{ "|日本語 and English words", width_keys(14) .. "<M-q>", "|日本語 and\nEnglish words" },
		{ "|「あいう」えお", width_keys(6) .. "<M-q>", "|「あい\nう」え\nお" },
		{ "|aaa bbb - ccc", width_keys(8) .. "<M-q>", "|aaa\nbbb -\nccc" },
		{ "|see item 1. next", width_keys(10) .. "<M-q>", "|see\nitem 1.\nnext" },
	})
end

cases["M-q leaves alone what Markdown would read differently"] = function()
	local function unchanged(spec)
		check(spec, "<M-q>", spec)
	end
	unchanged("# He|ading\ntext")
	unchanged("```\na|\nb\n```")
	unchanged("~~~\na\n|b\n~~~")
	unchanged("|    code\n    more")
	unchanged("| a | b |\n| - | - |")
	unchanged("|a | b\n--|--")
	unchanged("|<div>\ntext\n</div>")
	unchanged("---\ntitle: a\n|b: c\n---\ntext")
	unchanged("|aaa  \nbbb")
	unchanged("|aaa\\\nbbb")
	unchanged("|Title\n=====")
	unchanged("|Title\n-----")
	unchanged("|[ref]: http://example.com\nnext")
	unchanged("|> a\n>> b")
	unchanged("|> # h\n> text")
	unchanged("|> - item\n> more")
	unchanged("|---")
	unchanged("|- aaa\n- bbb")
	unchanged("- before\n    ```\n    code\n\n  nex|t code\n    ```")
	check(
		"|- before\n    ```\n    code\n\n  next code\n    ```",
		"<C-x>h<M-q>",
		"|- before\n    ```\n    code\n\n  next code\n    ```"
	)
	unchanged("|Use `a  b` here.")
	unchanged("|literal \\` and `a  b`")
	unchanged("|escaped \\\\`a  b` here")
	unchanged("|a `x   y` b ``p ` q`` c")
	unchanged("|aaa\n- bbb")
	unchanged("|> aaa\n>\n> bbb")
	unchanged("- aaa\n\n|  bbb ccc")
	unchanged("- |before\n    ```\n    some code\n    ```\n    after")
	unchanged("10. |before\n    ~~~\n    some code\n    ~~~\n    after")
	unchanged("- |before\n  ```\n  code\n  ```")
	each({
		{ "# Title\nte|xt\nmore", "<M-q>", "# Title\nte|xt more" },
		{ "|see `a b c` and more", width_keys(12) .. "<M-q>", "|see `a b c`\nand more" },
		{ "|a `b\nc` d", "<M-q>", "|a `b c` d" },
		{ "- |aaa bbb\n  ccc ddd", "<M-q>", "- |aaa bbb ccc ddd" },
		{ "- |aaa bbb\n  ccc ddd", width_keys(12) .. "<M-q>", "- |aaa bbb\n  ccc ddd" },
		{ "1. |aaa bbb ccc", width_keys(10) .. "<M-q>", "1. |aaa bbb\n   ccc" },
		{ "- [ ] aaa bbb ccc|", width_keys(12) .. "<M-q>", "- [ ] aaa\n  bbb ccc|" },
		{ "> |aaa\n> bbb", "<M-q>", "> |aaa bbb" },
		{ "> |aaa bbb ccc", width_keys(9) .. "<M-q>", "> |aaa bbb\n> ccc" },
		{ ">> |aaa\n>> bbb", "<M-q>", ">> |aaa bbb" },
	})
end

cases["M-q fills the selection and uses the fill prefix"] = function()
	each({
		{ "|aaa\nbbb\n\nccc\nddd\n\n# h\neee\nfff", "<C-x>h<M-q>", "|aaa bbb\n\nccc ddd\n\n# h\neee fff" },
		{ "|aaa\nbbb\n\nccc\nddd", "<C-Space><C-n><C-n><C-n><M-q>", "aaa bbb\n\n|ccc\nddd" },
		{ "; ; |aaa bbb ccc ddd eee", "<C-x>." .. width_keys(12) .. "<M-q>", "; ; |aaa bbb\n; ; ccc ddd\n; ; eee" },
	})
	open("; ; |aaa bbb ccc")
	feed("e<C-x>.<C-a><C-x>.<Esc>")
	eq(nil, vim.b.emacs_fill_prefix)
	open("| aaa")
	feed("e<C-x>.<Esc>")
	eq(nil, vim.b.emacs_fill_prefix)
	open(" ; |aaa")
	feed("e<C-x>.<Esc>")
	eq(" ; ", vim.b.emacs_fill_prefix)
end

cases["undo and redo go through Neovim's history"] = function()
	local pairings = {
		{ "<C-/>", "<C-?>" },
		{ "<C-_>", "<C-S-/>" },
		{ "<C-x>u", "<C-M-_>" },
		{ "<C-/>", "<C-M-S-->" },
	}
	for _, pairing in ipairs(pairings) do
		local undo, redo = pairing[1], pairing[2]
		session("a|", "X" .. undo .. snap("undone") .. redo .. snap("redone") .. undo .. redo .. snap("again"))
		local what = ("%s then %s"):format(undo, redo)
		eq({ "a", "aX", "aX" }, {
			(T.snaps.undone.text:gsub("|", "")),
			(T.snaps.redone.text:gsub("|", "")),
			(T.snaps.again.text:gsub("|", "")),
		}, what)
		eq(true, T.snaps.again.active, what)
	end
	check("a|", "<C-?>", "a|")
	check("ab|", "<BS><BS>", "|")
end

cases["the goal column holds the column of C-n and C-p until it is released"] = function()
	local spec = "abc|def\nxy\nabcdef"
	each({
		{ spec, "<C-x><C-n><C-n><C-e><C-n>", "abcdef\nxy\nabc|def" },
		{ spec, "<C-n><C-e><C-n>", "abcdef\nxy\nab|cdef" },
		{ spec, "<C-x><C-n><C-n><C-e><C-n><C-p><C-p>", "abc|def\nxy\nabcdef" },
		{ spec, "<C-x><C-n><Down><Down>", "abcdef\nxy\nabc|def" },
		{ spec, "<C-x><C-n><C-n><C-e><C-n><C-x><C-n><C-p><C-e><C-p>", "ab|cdef\nxy\nabcdef" },
		{ spec, "<C-x><C-n><C-n><C-e><C-x><C-n><C-n>", "abcdef\nxy\nab|cdef" },
	})
	with_options(TABS, function()
		open("|\tab\nabcdefghijklm")
		feed("e<C-f><C-x><C-n><Esc>")
		eq(8, vim.b.emacs_goal_column)
	end)
	open("|x")
	eq(nil, vim.b.emacs_goal_column)
end

cases["C-x < and C-x > scroll the text sideways, also where lines wrap"] = function()
	vim.cmd.vnew()
	vim.cmd("vertical resize 20")
	vim.wo.number = false
	vim.wo.relativenumber = false
	vim.wo.signcolumn = "no"
	vim.wo.foldcolumn = "0"
	vim.wo.statuscolumn = ""
	local long = string.rep("0123456789", 20)
	local function after(wrap, input)
		vim.wo.wrap = wrap
		session("|" .. long, input .. snap("end"))
		return T.snaps["end"]
	end
	local state = after(true, "<C-x><lt>")
	eq({ 18, false }, { state.leftcol, state.wrap }, "C-x < where lines wrap")
	eq(true, state.pos[2] >= 18, "the cursor stays in view")
	eq(true, vim.wo.wrap, "'wrap' after the mode")
	state = after(true, "<C-x><lt><C-x><lt>")
	eq({ 36, false }, { state.leftcol, state.wrap })
	state = after(true, "<C-x><lt><C-x><lt><C-x>>")
	eq({ 18, false }, { state.leftcol, state.wrap }, "C-x >")
	state = after(true, "<C-x><lt><C-x>>")
	eq({ 0, true }, { state.leftcol, state.wrap }, "back at the left, wrapping again")
	state = after(true, "<C-x>>")
	eq({ 0, true }, { state.leftcol, state.wrap }, "C-x > at the left")
	state = after(false, "<C-x><lt><C-PageDown>")
	eq({ 36, false }, { state.leftcol, state.wrap }, "C-PageDown")
	state = after(false, "<C-x><lt><C-x><lt><C-PageUp>")
	eq({ 18, false }, { state.leftcol, state.wrap }, "C-PageUp")
	vim.wo.wrap = true
	open("|" .. long)
	feed("e<C-x><lt><Esc>")
	eq({ true, 0 }, { vim.wo.wrap, vim.fn.winsaveview().leftcol }, "after Esc")
	state = after(true, "<C-Space><C-x><lt>")
	eq(true, state.selected)
	vim.cmd.close()
end

cases["Page keys scroll like C-v and M-v, with or without Shift"] = function()
	vim.cmd.new()
	vim.cmd.resize(10)
	vim.wo.scrolloff = 0
	local lines = {}
	for i = 1, 100 do
		lines[i] = "line " .. i
	end
	local spec = "|" .. table.concat(lines, "\n")
	local function at(input)
		session(spec, input .. snap("end"))
		return { T.snaps["end"].top, T.snaps["end"].pos[1] }
	end
	-- C-a first: a completion menu that is open takes the Page keys
	eq(at("<C-v>"), at("<C-a><PageDown>"))
	eq(at("<C-v>"), at("<C-a><kPageDown>"))
	eq(at("<C-v><C-v><M-v>"), at("<C-a><PageDown><PageDown><PageUp>"))
	eq(at("<C-v>"), at("<C-a><S-PageDown>"))
	session(spec, "<S-PageDown>" .. snap("end"))
	eq(true, T.snaps["end"].selected, "S-PageDown selects")
	local function placed(input)
		local snapshot = at(input)
		return { snapshot[1], snapshot[2], T.snaps["end"].pos[2] }
	end
	eq({ 9, 9, 3 }, placed("<C-a><C-f><C-f><C-f><C-x><C-n><C-v>"), "C-v with a goal column")
	eq({ 9, 9, 3 }, placed("<C-a><C-f><C-f><C-f><C-x><C-n><PageDown>"), "PageDown with a goal column")
	eq({ 1, 1, 3 }, placed("<C-a><C-f><C-f><C-f><C-x><C-n><M-v>"), "M-v with a goal column")
	vim.cmd.close()
end

cases["Up and Down keep the mappings they had on an open completion menu"] = function()
	-- blink.cmp maps Down in each buffer itself, over the mapping this case sets
	if package.loaded["blink.cmp"] then
		return
	end
	local counted = 0
	_G.emacs_test_down = function()
		counted = counted + 1
		return ""
	end
	vim.cmd([[
		function! EmacsTestDown()
			call v:lua.emacs_test_down()
			return ""
		endfunction
	]])
	local menu = "<Cmd>lua vim.fn.complete(1, { 'ab', 'ac' })<CR>"
	local function run(prepare)
		counted = 0
		open("x\ny|")
		prepare()
		feed("e" .. menu .. "<Down><Esc>")
		return counted
	end
	eq(
		1,
		run(function()
			vim.keymap.set("i", "<Down>", _G.emacs_test_down, { buffer = true })
		end),
		"mapping of the buffer"
	)
	eq(
		1,
		run(function()
			vim.keymap.set("i", "<Down>", "EmacsTestDown()", { buffer = true, expr = true })
		end),
		"expression of the buffer"
	)
	eq(
		1,
		run(function()
			vim.keymap.set("i", "<Down>", _G.emacs_test_down)
		end),
		"global mapping"
	)
	pcall(vim.keymap.del, "i", "<Down>")
	local script = vim.fn.tempname() .. ".vim"
	vim.fn.writefile({
		"function! s:Down()",
		"  call v:lua.emacs_test_down()",
		"  return ''",
		"endfunction",
		"function! EmacsTestMapDown()",
		"  inoremap <buffer> <expr> <Down> <SID>Down()",
		"endfunction",
	}, script)
	vim.cmd.source(script)
	eq(
		1,
		run(function()
			vim.fn.EmacsTestMapDown()
		end),
		"expression with <SID>"
	)
	vim.fn.delete(script)
	counted = 0
	open("x\ny|")
	vim.keymap.set("i", "<Down>", _G.emacs_test_down, { buffer = true })
	feed("e<Up><Esc>")
	eq({ 0, 0 }, { counted, vim.api.nvim_win_get_cursor(0)[1] - 1 }, "Up without a menu")
	feed("A<Down><Esc>")
	eq(1, counted, "mapping after the mode")
	_G.emacs_test_down = nil
end

cases["aliases give more keys to a command"] = function()
	local ok, err = pcall(function()
		emacs.setup({ start_key = "e", aliases = { redo = { "<F8>" }, kill_whole_line = { "<F7>" } } })
		check("a\nb|\nc", "<F7>", "a\n|c", "b\n")
		session("a|", "X<C-/><F8>" .. snap("end"))
		eq("aX", (T.snaps["end"].text:gsub("|", "")))
		eq({}, buffer_maps(0), "mappings left")
	end)
	emacs.setup(OPTS)
	assert(ok, err)
end

cases["new commands are undone one at a time"] = function()
	edit.store("Y", "replace")
	for _, row in ipairs({
		{ "foo b|ar\nbaz", "<C-t>" },
		{ "foo b|ar\nbaz", "<C-x><C-t>" },
		{ "foo b|ar\nbaz", "<C-x><BS>" },
		{ "foo b|ar\nbaz", "<C-S-BS>" },
		{ "foo b|ar\nbaz", "<C-Space><C-e><C-x><C-u>" },
		{ "foo B|AR\nbaz", "<C-Space><C-e><C-x><C-l>" },
		{ "foo\n b|ar\nbaz", "<M-^>" },
		{ "foo b|ar\nbaz", "<C-M-o>" },
		{ "foo b|ar\n\n\nbaz", "<C-x><C-o>" },
		{ "foo b|ar\nbaz", "<C-Space><C-e><BS>" },
		{ "foo b|ar\nbaz", "<M-y>1<CR>" },
		{ "foo b|ar\nbaz", "<M-@><C-w>" },
		{ "foo  |bar\nbaz", "<M-Space>" },
		{ "aaa bbb ccc ddd eee fff ggg hhh|", width_keys(12) .. "<M-q>" },
	}) do
		undo_steps(row[1], row[2])
	end
end

local function completion()
	local cmp = require("blink.cmp")
	local function menu()
		return "<Cmd>lua assert(vim.wait(5000, require('blink.cmp').is_menu_visible), 'no menu')<CR>"
	end
	_G.emacs_test_show = function()
		require("blink.cmp").show()
	end
	local show = "<Cmd>lua emacs_test_show()<CR>" .. menu()
	edit.store("KILL", "replace")

	check("alpha alphabet\nal|\nnext", show .. "<C-n>", "alpha alphabet\nal\nne|xt")
	eq(false, cmp.is_menu_visible(), "menu after C-n")
	check("alpha alphabet\nal|\nnext", show .. "<C-p>", "al|pha alphabet\nal\nnext")
	check("alpha alphabet\nal|", show .. "<C-y>", "alpha alphabet\nalKILL|")
	check("alpha alphabet\nal|", show .. "<C-e>", "alpha alphabet\nal|")
	local previewed = "<Cmd>lua vim.wait(1000, function() return vim.fn.getline('.') ~= 'al' end)<CR>"
	check("alpha alphabet\nal|", show .. "<Down>" .. previewed .. snap("preview") .. "<C-a>", "alpha alphabet\n|al")
	assert(T.snaps.preview.text ~= "alpha alphabet\nal|", "selecting did not preview an item")
	check("alpha alphabet\nal|", show .. "<Down>" .. previewed .. "<C-k>", "alpha alphabet\nal|", "KILL")
	session(
		"alpha alphabet\nal|",
		show .. "<Down>" .. previewed .. snap("down") .. "<Up>" .. "<Cmd>lua vim.wait(200)<CR>" .. snap("up")
	)
	assert(T.snaps.up.text ~= T.snaps.down.text, "Up did not choose another item than Down: " .. T.snaps.up.text)
	check("alpha alphabet\nal|", show .. "<S-Right>", "alpha alphabet\nal|")

	open("alpha alphabet\nal|")
	local accepted = "<Cmd>lua vim.wait(1000, function() return not require('blink.cmp').is_menu_visible() end)<CR>"
	feed("A" .. show .. "<C-n>" .. previewed .. "<C-y>" .. accepted .. "<Esc>")
	assert(vim.fn.getline(2):find("^alpha"), "plain C-n and C-y accepted " .. vim.fn.getline(2))
	eq("blink.cmp", vim.fn.maparg("<C-n>", "i", false, true).desc)
end

-- opts.exit: quit Neovim afterwards, with exit status 1 when a case failed
return function(opts)
	if vim.fn.maparg("e", "n", false, true).desc ~= "Emacs mode" then
		emacs.setup(OPTS)
	end
	local skipped = {}
	if package.loaded["blink.cmp"] then
		cases["completion menus do not take the mode's keys"] = completion
	else
		table.insert(skipped, "completion (no blink.cmp)")
	end
	vim.cmd.tabnew()
	local tab = vim.api.nvim_get_current_tabpage()
	local failed = {}
	local names = vim.tbl_keys(cases)
	table.sort(names)
	for _, name in ipairs(names) do
		local ok, err = xpcall(cases[name], debug.traceback)
		if not ok then
			table.insert(failed, name .. ": " .. err)
		end
		feed("<Esc>")
		emacs.stop()
	end
	vim.api.nvim_set_current_tabpage(tab)
	vim.cmd("tabclose!")
	for _, buf in ipairs(buffers) do
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
	local report = #failed .. " Emacs mode case(s) failed:\n" .. table.concat(failed, "\n\n")
	local summary = ("Emacs mode: %d cases OK"):format(#names)
		.. (#skipped > 0 and "; skipped " .. table.concat(skipped, ", ") or "")
	if opts and opts.exit then
		io.stderr:write((#failed > 0 and report or summary) .. "\n")
		vim.cmd(#failed > 0 and "cquit 1" or "qall!")
	end
	assert(#failed == 0, report)
	print(summary .. "\n")
end
