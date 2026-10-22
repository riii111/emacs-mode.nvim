-- Text changes through the buffer API, so no register, mark or 'clipboard' setting is involved.
local M = {}

-- Kills are shared by all buffers and kept after the mode ends. A kill resets the yank pointer to the latest one.
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

function M.ordered(from, to)
	return ordered(from, to)
end

function M.text(from, to)
	from, to = ordered(from, to)
	return table.concat(vim.api.nvim_buf_get_text(0, from[1], from[2], to[1], to[2], {}), "\n")
end

-- Replaces the text between two positions in one change, which keeps marks at its ends where they were.
-- Returns the position after the new text.
function M.splice(from, to, text)
	from, to = ordered(from, to)
	local lines = vim.split(text, "\n", { plain = true })
	vim.api.nvim_buf_set_text(0, from[1], from[2], to[1], to[2], lines)
	return { from[1] + #lines - 1, (#lines == 1 and from[2] or 0) + #lines[#lines] }
end

-- Leaves the cursor at the start of the deleted text and returns it.
function M.delete(from, to)
	local text = M.text(from, to)
	from, to = ordered(from, to)
	vim.api.nvim_buf_set_text(0, from[1], from[2], to[1], to[2], {})
	set_cursor(from)
	return text
end

-- Leaves the cursor after the new text and returns that position.
function M.insert(pos, text)
	local lines = vim.split(text, "\n", { plain = true })
	vim.api.nvim_buf_set_text(0, pos[1], pos[2], pos[1], pos[2], lines)
	local after = { pos[1] + #lines - 1, (#lines == 1 and pos[2] or 0) + #lines[#lines] }
	set_cursor(after)
	return after
end

-- Unlike splice, moves the cursor: it ends after the new text, whose position is returned.
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

function M.killed()
	return kills[1]
end

function M.to_yank()
	return kills[pointer]
end

-- the latest first
function M.entries()
	return vim.list_slice(kills)
end

-- index is a position in entries()
function M.select(index)
	if kills[index] then
		pointer = index
	end
	return kills[index]
end

-- wraps from the oldest kill to the latest
function M.rotate()
	if #kills == 0 then
		return nil
	end
	pointer = pointer % #kills + 1
	return kills[pointer]
end

return M
