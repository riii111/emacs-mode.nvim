-- The region between the mark and the cursor, highlighted while it is active as in Emacs' Transient Mark mode.
-- Positions are { row, col } as in motion.lua. Only one buffer has a mark at a time.
local M = {}

M.namespace = vim.api.nvim_create_namespace("emacs_region")

-- buf, the extmark ids of the mark and the highlight, and the changedtick when the mark was set
local current

function M.clear()
	if current and vim.api.nvim_buf_is_valid(current.buf) then
		vim.api.nvim_buf_clear_namespace(current.buf, M.namespace, 0, -1)
	end
	current = nil
end

-- The mark stays before text inserted at it, as an Emacs marker does.
function M.set_mark(buf, pos)
	M.clear()
	current = {
		buf = buf,
		mark = vim.api.nvim_buf_set_extmark(buf, M.namespace, pos[1], pos[2], { right_gravity = false }),
		tick = vim.api.nvim_buf_get_changedtick(buf),
	}
end

-- the position of the mark while the region is active in buf
function M.mark(buf)
	if not current or current.buf ~= buf then
		return nil
	end
	local mark = vim.api.nvim_buf_get_extmark_by_id(buf, M.namespace, current.mark, {})
	return { mark[1], mark[2] }
end

-- whether buf changed since the mark was set; any change but the mode's own commands ends the region
function M.changed(buf)
	return current ~= nil and current.buf == buf and vim.api.nvim_buf_get_changedtick(buf) ~= current.tick
end

function M.draw(buf, cursor)
	local from, to = M.mark(buf), cursor
	if not from then
		return
	end
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
