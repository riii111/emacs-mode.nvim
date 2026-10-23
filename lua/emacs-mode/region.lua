-- The mark, and the region between the mark and the cursor, which is highlighted while it is active as in Emacs'
-- Transient Mark mode. The mark and the selection are separate: dropping the selection keeps the mark.
-- Positions are { row, col } as in motion.lua. Only one buffer has a mark at a time.
local M = {}

M.namespace = vim.api.nvim_create_namespace("emacs_region")

-- kind: "mark" is set with the mark keys, "shift" is started by a shifted move, which an unshifted move ends
local current

local function clear_highlight()
	if current and current.highlight and vim.api.nvim_buf_is_valid(current.buf) then
		pcall(vim.api.nvim_buf_del_extmark, current.buf, M.namespace, current.highlight)
	end
	if current then
		current.highlight = nil
	end
end

function M.clear()
	if current and vim.api.nvim_buf_is_valid(current.buf) then
		vim.api.nvim_buf_clear_namespace(current.buf, M.namespace, 0, -1)
	end
	current = nil
end

-- The mark stays before text inserted at it, as an Emacs marker does.
function M.set_mark(buf, pos, active, kind)
	if current and current.buf ~= buf then
		M.clear()
	end
	local id = current and current.mark
	current = current or { buf = buf }
	current.mark = vim.api.nvim_buf_set_extmark(buf, M.namespace, pos[1], pos[2], { id = id, right_gravity = false })
	current.active = active
	current.kind = kind or "mark"
	current.tick = vim.api.nvim_buf_get_changedtick(buf)
	if not active then
		clear_highlight()
	end
end

function M.mark(buf)
	if not current or current.buf ~= buf then
		return nil
	end
	local mark = vim.api.nvim_buf_get_extmark_by_id(buf, M.namespace, current.mark, {})
	return { mark[1], mark[2] }
end

function M.is_active(buf)
	return current ~= nil and current.buf == buf and current.active
end

function M.kind()
	return current and current.kind
end

function M.move_mark(buf, pos)
	M.set_mark(buf, pos, M.is_active(buf), current and current.kind)
end

function M.activate(buf, kind)
	if current and current.buf == buf then
		current.active = true
		current.kind = kind or current.kind
		current.tick = vim.api.nvim_buf_get_changedtick(buf)
	end
end

function M.deactivate()
	if current then
		current.active = false
		clear_highlight()
	end
end

function M.bounds(buf, cursor)
	local mark = M.is_active(buf) and M.mark(buf)
	if not mark or (mark[1] == cursor[1] and mark[2] == cursor[2]) then
		return nil
	end
	if mark[1] > cursor[1] or (mark[1] == cursor[1] and mark[2] > cursor[2]) then
		return cursor, mark
	end
	return mark, cursor
end

-- Whether buf changed behind an active selection, as typed text does; the caller ends the selection.
function M.changed(buf)
	return M.is_active(buf) and vim.api.nvim_buf_get_changedtick(buf) ~= current.tick
end

-- sync_tick accepts the buffer's current changes as the mode's own, so that they do not end the selection.
function M.draw(buf, cursor, sync_tick)
	if not M.is_active(buf) then
		return
	end
	if sync_tick then
		current.tick = vim.api.nvim_buf_get_changedtick(buf)
	end
	local from, to = M.mark(buf), cursor
	if from[1] > to[1] or (from[1] == to[1] and from[2] > to[2]) then
		from, to = to, from
	end
	current.highlight = vim.api.nvim_buf_set_extmark(buf, M.namespace, from[1], from[2], {
		id = current.highlight,
		end_row = to[1],
		end_col = to[2],
		hl_group = "Visual",
	})
end

return M
