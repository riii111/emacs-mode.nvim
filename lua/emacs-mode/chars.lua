-- Characters as Normal mode's `l` moves over them: a base character with its composing characters, and emoji
-- sequences as one.
local M = {}

-- Vim counts characters from the start of the string, so each boundary is looked up in a short window: the window
-- must hold the whole character and the code point after it, which can still join it.
local function char_length(text, col)
	local byte, next_byte = text:byte(col + 1, col + 2)
	if byte < 0x80 and (not next_byte or next_byte < 0x80) then
		return 1
	end
	local size = 16
	while true do
		local window = text:sub(col + 1, col + size)
		local stop = vim.fn.byteidx(window, 1)
		if col + size >= #text then
			return stop > 0 and stop or #window
		elseif stop > 0 and stop + 4 <= #window then
			return stop
		end
		size = size * 2
	end
end

function M.split(text)
	local result, col = {}, 0
	while col < #text do
		local stop = col + char_length(text, col)
		table.insert(result, text:sub(col + 1, stop))
		col = stop
	end
	return result
end

function M.set(text)
	local found = {}
	for _, char in ipairs(M.split(text)) do
		found[char] = true
	end
	return found
end

function M.first(text)
	if text ~= "" then
		return text:sub(1, char_length(text, 0))
	end
end

function M.last(text)
	local byte, previous = text:byte(-1), text:byte(-2)
	if byte and byte < 0x80 and (not previous or previous < 0x80) then
		return text:sub(-1)
	elseif byte then
		return text:sub(vim.fn.byteidx(text, vim.fn.charidx(text, #text - 1)) + 1)
	end
end

local CJK_RANGES = {
	{ 0x1100, 0x11FF },
	{ 0x2E80, 0x2FDF },
	{ 0x3000, 0x4DBF },
	{ 0x4E00, 0x9FFF },
	{ 0xA960, 0xA97F },
	{ 0xAC00, 0xD7FF },
	{ 0xF900, 0xFAFF },
	{ 0xFE30, 0xFE4F },
	{ 0xFF00, 0xFFEF },
	{ 0x20000, 0x3FFFF },
}

-- the characters Emacs breaks a line next to without a space: Han, kana, Hangul and the full-width forms
function M.cjk(char)
	local code = vim.fn.char2nr(char)
	for _, range in ipairs(CJK_RANGES) do
		if code >= range[1] and code <= range[2] then
			return true
		end
	end
	return false
end

return M
