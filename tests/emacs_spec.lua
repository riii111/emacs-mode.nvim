-- Integration tests of emacs-mode. Keys go through the real mappings: each case types its keys in one
-- feedkeys() call, records the state on the way with <Cmd> and leaves with <Esc>.
--
-- `make test` runs them without other plugins. A configuration with blink.cmp or neoscroll can run them as
-- well, to test the mode together with those: dofile("<this file>")() inside Neovim.
local emacs = require("emacs-mode")
local edit = require("emacs-mode.edit")
local region = require("emacs-mode.region")

-- the tests start the mode with `e`
local OPTS = { start_key = "e" }

local T = { snaps = {} }
_G.emacs_test = T

local keys = {
	"<C-f>",
	"<C-b>",
	"<C-n>",
	"<C-p>",
	"<C-a>",
	"<C-e>",
	"<M-f>",
	"<M-b>",
	"<M-lt>",
	"<M->>",
	"<C-d>",
	"<Del>",
	"<BS>",
	"<C-h>",
	"<C-u>",
	"<C-k>",
	"<M-d>",
	"<M-BS>",
	"<C-y>",
	"<M-y>",
	"<C-/>",
	"<C-_>",
	"<C-v>",
	"<M-v>",
	"<C-l>",
	"<M-r>",
	"<M-{>",
	"<M-}>",
	"<M-S-,>",
	"<M-S-.>",
	"<M-S-[>",
	"<M-S-]>",
	"<C-w>",
	"<M-w>",
	"<C-g>",
	"<M-h>",
	"<C-Space>",
	"<C-@>",
	"<M-t>",
	"<M-u>",
	"<M-l>",
	"<M-c>",
	"<M-Bslash>",
	"<M-Space>",
	"<M-z>",
	"<M-a>",
	"<M-e>",
	"<M-k>",
	"<C-s>",
	"<C-r>",
}

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

-- waits for neoscroll's animation, when C-v, M-v or C-l started one
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

-- a new buffer with the text of spec and the Normal mode cursor on (or before the end of) its "|"
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

-- Opens spec, starts the mode with `e`, puts the cursor on "|", types input and leaves; returns the state
-- just before leaving.
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

	-- e typed in the mode is text
	check("|ab", "e", "e|ab")
end

cases["the cursor is a block while the mode is on"] = function()
	local guicursor = vim.o.guicursor
	open("ab|c")
	feed("e<Cmd>lua emacs_test.guicursor = vim.o.guicursor<CR><Esc>")
	eq(guicursor .. ",i-ci:block", T.guicursor, "'guicursor' in the mode")
	eq(guicursor, vim.o.guicursor, "'guicursor' after the mode")

	-- a value set while the mode was on stays
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

	-- buffers that are not for editing text keep the motion
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

	-- only right after C-y or M-y
	kills("a", "b")
	check("x|", "<M-y>", "x|")
	check("x|", "<C-y>Z<M-y>", "xbZ|")
	check("x|", "<C-y><C-b><C-f><M-y>", "xb|")

	-- C-y puts back the kill M-y went to, until the next kill
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
	-- a C-w right after another joins the kill in text order
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

	-- the mark set right after typing stays: the change came before it
	check("|", "abc<C-Space>" .. idle .. "<C-b><C-b>" .. idle .. "<C-w>", "a|", "bc")
	-- a key given twice is mapped once and comes back unmapped
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
	-- without a region C-w kills the word before the cursor
	check("foo bar|", "<C-w>", "foo |", "bar")

	check("a\n\nb|1\nb2\n\nc", "<M-h><C-w>", "a\n|\nc", "\nb1\nb2\n")
	check("a\n\nb|1\nb2", "<M-h><C-w>", "a\n|", "\nb1\nb2")

	-- other keys can set the mark
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
	check("a  | \tb", "<M-Space>", "a |b")
	check("a|b", "<M-Space>", "a |b")
	check("a |b", "<M-Space>", "a |b")
end

cases["M-z kills up to and with the typed character"] = function()
	check("a|bc,de", "<M-z>,", "a|de", "bc,")
	check("a|b\nc,d", "<M-z>,", "a|d", "b\nc,")
	check("|あいう、え", "<M-z>、", "|え", "あいう、")
	check("a|,b,c", "<M-z>,", "a|b,c", ",")
	-- it joins kills right before and after it
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

	-- a line break inside a paragraph is like a blank, and a paragraph ends its last sentence
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
	-- a kill that kills nothing neither clears nor breaks the row
	check("a|b", "<C-k><C-k><C-u>", "|", "ab")
	-- a row does not continue in another buffer or after the mode ended
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
			.. snap("3")
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
	feed("<C-r><C-r><C-r>")
	eq(body("3"), text(), what .. ": redo in Normal mode")
	feed("uuu")
	eq(body("0"), text(), what .. ": undo in Normal mode")
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

	-- text typed before and after a move to another line are separate steps that undo cleanly
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
	-- C-p comes back over the same screen rows
	for i = 1, 7 do
		table.insert(rows, T.snaps["d" .. i].screen_row - T.snaps["u" .. (8 - i)].screen_row)
	end
	-- the same positions as gj and gk in Normal mode, but after the last character where the line is too short
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

	-- the last column of a line stays reachable, and typing between moves sets a new column
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
		-- neoscroll scrolls a whole window and the cursor with it
		eq({ 11, 11, 0, 1, true }, at("down"), "C-v")
		eq({ 21, 21, 0, 1, true }, at("down2"), "C-v again")
	else
		-- a window of 10 lines scrolls by 8, keeping 2 lines on the screen
		eq({ 9, 9, 0, 1, true }, at("down"), "C-v")
		eq({ 17, 17, 0, 1, true }, at("down2"), "C-v again")
	end
	eq(1, T.snaps.up.top, "M-v")

	if smooth then
		-- the animation passes through Normal mode without ending the mode, and Esc during it ends the mode with
		-- the cursor shape put back once neoscroll stops hiding the cursor
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

		-- leaving the buffer during the animation puts the cursor shape back after neoscroll shows it again
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

	-- the cursor after the end of the line stays there
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
		for _, lhs in ipairs(keys) do
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
	for _, lhs in ipairs(keys) do
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
	session("foo bar| baz\nqux", "<C-k><C-k><C-u><M-BS><M-d><C-y><C-d><BS>")
	local after = registers()
	vim.o.clipboard = clipboard
	eq(before, after)
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

	-- the mode's keys do not select or accept items
	check("alpha alphabet\nal|\nnext", show .. "<C-n>", "alpha alphabet\nal\nne|xt")
	eq(false, cmp.is_menu_visible(), "menu after C-n")
	check("alpha alphabet\nal|\nnext", show .. "<C-p>", "al|pha alphabet\nal\nnext")
	check("alpha alphabet\nal|", show .. "<C-y>", "alpha alphabet\nalKILL|")
	check("alpha alphabet\nal|", show .. "<C-e>", "alpha alphabet\nal|")
	-- a previewed item is taken back, not accepted
	local previewed = "<Cmd>lua vim.wait(1000, function() return vim.fn.getline('.') ~= 'al' end)<CR>"
	check("alpha alphabet\nal|", show .. "<Down>" .. previewed .. snap("preview") .. "<C-a>", "alpha alphabet\n|al")
	assert(T.snaps.preview.text ~= "alpha alphabet\nal|", "selecting did not preview an item")
	check("alpha alphabet\nal|", show .. "<Down>" .. previewed .. "<C-k>", "alpha alphabet\nal|", "KILL")

	-- plain Insert mode completion is unchanged
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
