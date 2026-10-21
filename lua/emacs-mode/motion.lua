-- Positions are { row, col } with a 0-based row and a 0-based byte column, the gap before that byte.
-- Each function returns the target position, or nil when there is nowhere to go.
local M = {}

local function line(buf, row)
	return vim.api.nvim_buf_get_lines(buf, row, row + 1, true)[1]
end

local function last_row(buf)
	return vim.api.nvim_buf_line_count(buf) - 1
end

-- charidx()/byteidx() step over a character with its composing characters the way `l` and `h` do
local function next_boundary(text, col)
	return vim.fn.byteidx(text, vim.fn.charidx(text, col) + 1)
end

local function previous_boundary(text, col)
	local index = vim.fn.charidx(text, col)
	local start = vim.fn.byteidx(text, index)
	return start < col and start or vim.fn.byteidx(text, index - 1)
end

-- charclass() is 2 or more for the characters 'iskeyword' (or the Unicode class of a wide character) makes a word
local function is_word(text, col)
	return vim.fn.charclass(text:sub(col + 1)) >= 2
end

local function moved(from, row, col)
	if row == from[1] and col == from[2] then
		return nil
	end
	return { row, col }
end

function M.forward_char(buf, pos)
	local text = line(buf, pos[1])
	if pos[2] < #text then
		return { pos[1], next_boundary(text, pos[2]) }
	elseif pos[1] < last_row(buf) then
		return { pos[1] + 1, 0 }
	end
end

function M.backward_char(buf, pos)
	if pos[2] > 0 then
		return { pos[1], previous_boundary(line(buf, pos[1]), pos[2]) }
	elseif pos[1] > 0 then
		return { pos[1] - 1, #line(buf, pos[1] - 1) }
	end
end

function M.line_start(_, pos)
	return moved(pos, pos[1], 0)
end

function M.line_end(buf, pos)
	return moved(pos, pos[1], #line(buf, pos[1]))
end

function M.buffer_start(_, pos)
	return moved(pos, 0, 0)
end

function M.buffer_end(buf, pos)
	local row = last_row(buf)
	return moved(pos, row, #line(buf, row))
end

-- Skips what is not a word, line breaks included, then the word: the gap after the end of the next word.
function M.forward_word(buf, pos)
	local last = last_row(buf)
	local row, col = pos[1], pos[2]
	local text = line(buf, row)
	local in_word = false
	while true do
		if col >= #text then
			if in_word or row == last then
				break
			end
			row, col = row + 1, 0
			text = line(buf, row)
		else
			if is_word(text, col) then
				in_word = true
			elseif in_word then
				break
			end
			col = next_boundary(text, col)
		end
	end
	return moved(pos, row, col)
end

function M.backward_word(buf, pos)
	local row, col = pos[1], pos[2]
	local text = line(buf, row)
	local in_word = false
	while true do
		if col == 0 then
			if in_word or row == 0 then
				break
			end
			row = row - 1
			text = line(buf, row)
			col = #text
		else
			local start = previous_boundary(text, col)
			if is_word(text, start) then
				in_word = true
			elseif in_word then
				break
			end
			col = start
		end
	end
	return moved(pos, row, col)
end

local function blank(buf, row)
	return line(buf, row):find("^[ \t]*$") ~= nil
end

-- Paragraphs are separated by lines with nothing but blanks, as in Emacs; both stop at the separating line.
function M.forward_paragraph(buf, pos)
	local last = last_row(buf)
	local row = pos[1]
	while row <= last and blank(buf, row) do
		row = row + 1
	end
	while row <= last and not blank(buf, row) do
		row = row + 1
	end
	if row > last then
		return M.buffer_end(buf, pos)
	end
	return moved(pos, row, 0)
end

function M.backward_paragraph(buf, pos)
	local row = pos[1]
	while row >= 0 and blank(buf, row) do
		row = row - 1
	end
	while row >= 0 and not blank(buf, row) do
		row = row - 1
	end
	if row < 0 then
		return M.buffer_start(buf, pos)
	end
	return moved(pos, row, 0)
end

-- Sentences end at 。！？ (and the full-width period) or at . ! ? before a blank or the end of the line, with
-- the closing quotes and brackets after them, as with Emacs' sentence-end-double-space off. A paragraph
-- ends its last sentence. Abbreviations such as "Mr." end a sentence too.
local ENDS = { ["。"] = true, ["！"] = true, ["？"] = true, ["．"] = true }
local ASCII_ENDS = { ["."] = true, ["!"] = true, ["?"] = true }
local CLOSERS = {}
for _, closer in ipairs({ '"', "'", ")", "]", "」", "』", "）", "】", "”", "’" }) do
	CLOSERS[closer] = true
end

local function char_at(text, col)
	local stop = next_boundary(text, col)
	return text:sub(col + 1, stop), stop
end

-- the gap after the end of the sentence the cursor is in, or of the next one
function M.forward_sentence(buf, pos)
	local last = last_row(buf)
	local row, col = pos[1], pos[2]
	local text = line(buf, row)
	local seen = false
	while true do
		if col >= #text then
			if row == last or (seen and blank(buf, row + 1)) then
				return moved(pos, row, #text)
			end
			row, col = row + 1, 0
			text = line(buf, row)
		else
			local char, stop = char_at(text, col)
			seen = seen or not char:find("^[ \t]$")
			if ENDS[char] or ASCII_ENDS[char] then
				-- 「本当！？」 ends once, after the closer
				local after = stop
				while after < #text do
					local next_char, next_stop = char_at(text, after)
					if not (CLOSERS[next_char] or ENDS[next_char] or ASCII_ENDS[next_char]) then
						break
					end
					after = next_stop
				end
				local rest = text:sub(after + 1)
				if ENDS[char] or rest == "" or rest:find("^[ \t]") or rest:find("^\u{3000}") then
					return moved(pos, row, after)
				end
			end
			col = stop
		end
	end
end

local function before(a, b)
	return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
end

-- past blanks and line breaks, up to the end of the buffer
local function skip_blanks(buf, pos)
	local last = last_row(buf)
	local row, col = pos[1], pos[2]
	local text = line(buf, row)
	while true do
		if col >= #text then
			if row == last then
				return { row, col }
			end
			row, col = row + 1, 0
			text = line(buf, row)
		elseif text:sub(col + 1, col + 1):find("[ \t]") then
			col = col + 1
		else
			return { row, col }
		end
	end
end

-- the start of the sentence the cursor is in, or of the previous one when the cursor is at a start already
function M.backward_sentence(buf, pos)
	local row = pos[1]
	if not blank(buf, row) then
		while row > 0 and not blank(buf, row - 1) do
			row = row - 1
		end
		local start, found = skip_blanks(buf, { row, 0 }), nil
		while before(start, pos) do
			found = start
			local stop = M.forward_sentence(buf, start)
			if not (stop and before(stop, pos)) then
				break
			end
			start = skip_blanks(buf, stop)
		end
		if found then
			return moved(pos, found[1], found[2])
		end
	end
	-- the last sentence of the paragraph before
	row = row - 1
	while row >= 0 and blank(buf, row) do
		row = row - 1
	end
	if row < 0 then
		return M.buffer_start(buf, pos)
	end
	return M.backward_sentence(buf, { row, #line(buf, row) })
end

-- the blanks around the cursor on its line, as { from, to }
function M.blanks_around(buf, pos)
	local text = line(buf, pos[1])
	local from, to = pos[2], pos[2]
	while from > 0 and text:sub(from, from):find("[ \t]") do
		from = from - 1
	end
	while to < #text and text:sub(to + 1, to + 1):find("[ \t]") do
		to = to + 1
	end
	return { pos[1], from }, { pos[1], to }
end

-- the gap after the next char at or after the cursor, over line breaks; nil when there is none
function M.after_next(buf, pos, char)
	local last = last_row(buf)
	local col = pos[2]
	for row = pos[1], last do
		local found = line(buf, row):find(char, col + 1, true)
		if found then
			return { row, found - 1 + #char }
		end
		col = 0
	end
end

-- Up to the line break, or the line break itself when only blanks are left before it.
function M.kill_line_end(buf, pos)
	local text = line(buf, pos[1])
	if text:sub(pos[2] + 1):find("^[ \t]*$") and pos[1] < last_row(buf) then
		return { pos[1] + 1, 0 }
	end
	return M.line_end(buf, pos)
end

return M
