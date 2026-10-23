-- Edits of whole lines and of the blanks between them, through the buffer API of the current buffer.
-- Rows are 0-based and columns are byte columns, as in motion.lua.
local chars = require("emacs-mode.chars")

local M = {}

local function line(row)
	return vim.api.nvim_buf_get_lines(0, row, row + 1, true)[1]
end

local function last_row()
	return vim.api.nvim_buf_line_count(0) - 1
end

local function blank(row)
	return line(row):find("^[ \t]*$") ~= nil
end

local OPENERS = chars.set("([{（［｛〔〈《「『【")
local CLOSERS = chars.set(")]}）］｝〕〉》」』】")

-- Like Emacs' fixup-whitespace; lines next to a CJK character join without a space, as when filling.
local function needs_space(before, after)
	if before == "" or after == "" then
		return false
	end
	local left, right = chars.last(before), chars.first(after)
	return not (OPENERS[left] or CLOSERS[right] or chars.cjk(left) or chars.cjk(right))
end

function M.join_previous(row, prefix)
	local previous, current = line(row - 1), line(row)
	local start = (prefix ~= "" and current:sub(1, #prefix) == prefix) and #prefix or 0
	local lead = start + #current:sub(start + 1):match("^[ \t]*")
	local trailing = #previous:match("[ \t]*$")
	local keep = #previous - trailing
	local space = needs_space(previous:sub(1, keep), current:sub(lead + 1)) and " " or ""
	vim.api.nvim_buf_set_text(0, row - 1, keep, row, lead, { space })
	return { row - 1, keep }
end

local function padding(from, to)
	if to <= from then
		return ""
	end
	local pad, column = "", from
	if not vim.bo.expandtab then
		local tabstop = vim.bo.tabstop
		local next_stop = (math.floor(column / tabstop) + 1) * tabstop
		while next_stop <= to do
			pad = pad .. "\t"
			column = next_stop
			next_stop = column + tabstop
		end
	end
	return pad .. string.rep(" ", to - column)
end

-- The rest keeps its display column.
function M.split(pos, prefix)
	local text = line(pos[1])
	local col = pos[2]
	while col < #text and text:sub(col + 1, col + 1):find("[ \t]") do
		col = col + 1
	end
	local column = vim.fn.strdisplaywidth(text:sub(1, col))
	local lead = (prefix ~= "" and text:sub(1, #prefix) == prefix) and prefix or ""
	vim.api.nvim_buf_set_text(
		0,
		pos[1],
		col,
		pos[1],
		col,
		{ "", lead .. padding(vim.fn.strdisplaywidth(lead), column) }
	)
	return { pos[1], col }
end

local function delete_rows(first, last)
	vim.api.nvim_buf_set_lines(0, first, last + 1, true, {})
end

-- Emacs' delete-blank-lines.
function M.delete_blank(row)
	local last = last_row()
	local after = row
	while after < last and blank(after + 1) do
		after = after + 1
	end
	if not blank(row) then
		if after > row then
			delete_rows(row + 1, after)
		end
		return row
	end
	local before = row
	while before > 0 and blank(before - 1) do
		before = before - 1
	end
	if before == row and after == row then
		if last == 0 then
			return row
		end
		delete_rows(row, row)
		return math.min(row, last - 1)
	end
	if after > row then
		delete_rows(row + 1, after)
	end
	if before < row then
		delete_rows(before, row - 1)
	end
	return before
end

-- Like Emacs' transpose-lines, the first line swaps with the one after it.
function M.transpose(row)
	local last = last_row()
	local first = row == 0 and 0 or row - 1
	if first + 1 > last then
		return nil
	end
	vim.api.nvim_buf_set_lines(0, first, first + 2, true, { line(first + 1), line(first) })
	if first + 2 <= last then
		return { first + 2, 0 }
	end
	return { first + 1, #line(first + 1) }
end

return M
