-- Text changes through the buffer API, so no register, mark or 'clipboard' setting is involved.
local M = {}

-- Killed texts, the latest first, shared by all buffers and kept after the mode ends. C-y puts back the one
-- at the yank pointer, which a kill puts back on the latest and M-y moves to older ones.
local MAX_KILLS = 60
local kills = {}
local pointer = 1

local function set_cursor(pos)
	vim.api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
end

local function ordered(from, to)
	if from[1] > to[1] or (from[1] == to[1] and from[2] > to[2]) then
		return to, from
	end
	return from, to
end

-- the text between two positions, in either order
function M.text(from, to)
	from, to = ordered(from, to)
	return table.concat(vim.api.nvim_buf_get_text(0, from[1], from[2], to[1], to[2], {}), "\n")
end

-- Deletes the text between two positions (in either order), leaves the cursor there and returns the text.
function M.delete(from, to)
	local text = M.text(from, to)
	from, to = ordered(from, to)
	vim.api.nvim_buf_set_text(0, from[1], from[2], to[1], to[2], {})
	set_cursor(from)
	return text
end

-- Inserts text at a position, leaves the cursor after it and returns that position.
function M.insert(pos, text)
	local lines = vim.split(text, "\n", { plain = true })
	vim.api.nvim_buf_set_text(0, pos[1], pos[2], pos[1], pos[2], lines)
	local after = { pos[1] + #lines - 1, (#lines == 1 and pos[2] or 0) + #lines[#lines] }
	set_cursor(after)
	return after
end

-- Replaces the text between two positions, leaves the cursor after the new text and returns that position.
function M.replace(from, to, text)
	M.delete(from, to)
	from = vim.api.nvim_win_get_cursor(0)
	return M.insert({ from[1] - 1, from[2] }, text)
end

function M.set_cursor(pos)
	set_cursor(pos)
end

-- how: "replace" starts over, "append" and "prepend" join a kill that continues the previous one
function M.store(text, how)
	if how == "append" and kills[1] then
		kills[1] = kills[1] .. text
	elseif how == "prepend" and kills[1] then
		kills[1] = text .. kills[1]
	else
		table.insert(kills, 1, text)
		kills[MAX_KILLS + 1] = nil
	end
	pointer = 1
end

-- the latest kill
function M.killed()
	return kills[1]
end

-- the kill C-y puts back
function M.to_yank()
	return kills[pointer]
end

-- Moves the yank pointer to the next older kill, around to the latest after the oldest, and returns that kill.
function M.rotate()
	if #kills == 0 then
		return nil
	end
	pointer = pointer % #kills + 1
	return kills[pointer]
end

return M
