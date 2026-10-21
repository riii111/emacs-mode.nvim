-- Characters as Normal mode's `l` moves over them: a base character with its composing characters, and emoji
-- sequences as one.
local M = {}

function M.split(text)
	local result, col = {}, 0
	while col < #text do
		local stop = vim.fn.byteidx(text, vim.fn.charidx(text, col) + 1)
		if stop <= col then
			stop = #text
		end
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
	return M.split(text)[1]
end

function M.last(text)
	local all = M.split(text)
	return all[#all]
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
