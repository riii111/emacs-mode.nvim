-- Paragraph filling in the way of Emacs' fill-paragraph, for text that mixes Latin and CJK characters. Lines that
-- Markdown would read differently once joined (code, headings, tables, HTML, hard line breaks, ...) are left alone.
-- Rows are 0-based as in motion.lua.
local chars = require("emacs-mode.chars")

local M = {}

local cjk, first_char, last_char = chars.cjk, chars.first, chars.last

local fill_unit

-- Fills the paragraphs that overlap the rows from..to. Returns the replacements { first, last, lines, count, place }
-- from the last to the first, and the note of the first paragraph left alone, if any.
function M.fill(lines, from, to, options)
	local edits, note = {}, nil
	for _, unit in ipairs(M.units(lines)) do
		if unit.last >= from and unit.first <= to then
			if unit.kind == "skip" then
				note = note or unit.note
			else
				local old = vim.list_slice(lines, unit.first + 1, unit.last + 1)
				local new, count, place = fill_unit(old, unit, options)
				if not vim.deep_equal(old, new) then
					table.insert(
						edits,
						1,
						{ first = unit.first, last = unit.last, lines = new, count = count, place = place }
					)
				end
			end
		end
	end
	return edits, note
end

local function blank(text)
	return text:find("^[ \t]*$") ~= nil
end

local function trim(text)
	local trimmed = text:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
	return trimmed
end

-- tabs of 4, as CommonMark counts them
local function indent_width(text)
	local width = 0
	for char in text:match("^[ \t]*"):gmatch(".") do
		width = char == " " and width + 1 or width + 4 - width % 4
	end
	return width
end

-- kinsoku: characters that do not start a line, and characters that do not end one
local NO_START = chars.set(
	"、。，．・：；？！゛゜ゝゞ々ー…‥）］｝〕〉》」』】〙〗〟’”ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶ)]}"
)
local NO_START_AFTER_CJK = chars.set(",.;:!?")
local NO_END = chars.set("（［｛〔〈《「『【〘〖〝‘“([{")
local CLOSERS = chars.set([[)]"'”’」』）】]])

local function width(text)
	return vim.fn.strdisplaywidth(text)
end

local function ends_sentence(text)
	local all = chars.split(text)
	local index = #all
	while index > 1 and CLOSERS[all[index]] do
		index = index - 1
	end
	return all[index] == "." or all[index] == "?" or all[index] == "!"
end

local function starts_block(token)
	return token:find("^#+$")
		or token:find("^[-*+]$")
		or token:find("^%d+[.)]$")
		or token:find("^>")
		or token:find("^|")
		or token:find("^```")
		or token:find("^~~~")
		or token:find("^[-=_*]+$")
		or token:find("^<[%a/!?]")
		or token:find("^%$%$")
end

-- A fence at any indentation: one indented by 4 or more is code in a text paragraph, but a block of a list item.
local function fence(text)
	local marks = text:match("^%s*(```+)") or text:match("^%s*(~~~+)")
	return marks and { char = marks:sub(1, 1), length = #marks }
end

local function closes_fence(text, open)
	local marks = text:match("^%s*([`~]+)%s*$")
	return marks ~= nil and marks:sub(1, 1) == open.char and #marks >= open.length
end

local function rule(text)
	local marks = text:gsub("%s", "")
	if #marks < 3 then
		return false
	end
	return marks:find("^%-+$") ~= nil or marks:find("^%*+$") ~= nil or marks:find("^_+$") ~= nil
end

local function heading(text)
	return text:find("^%s*#+%s") ~= nil or text:find("^%s*#+$") ~= nil
end

local function table_row(text)
	return text:find("^%s*|") ~= nil
end

local function delimiter_row(text)
	return text:find("|", 1, true) ~= nil and text:find("-", 1, true) ~= nil and text:find("^[|:%-%s]+$") ~= nil
end

local function html(text)
	return text:find("^%s*<[%a/!?]") ~= nil
end

local function definition(text)
	return text:find("^%s*%[[^%]]+%]:") ~= nil
end

local function math_fence(text)
	return text:find("^%s*%$%$") ~= nil
end

local function list_item(text)
	if rule(text) then
		return nil
	end
	local lead, marker, gap, body = text:match("^(%s*)([-*+])(%s+)(.*)$")
	if not lead then
		lead, marker, gap, body = text:match("^(%s*)(%d+[.)])(%s+)(.*)$")
	end
	if lead and indent_width(lead) < 4 then
		return { lead = lead, marker = marker, gap = gap, body = body }
	end
end

local function quote(text)
	return text:find("^%s*>") ~= nil and indent_width(text) < 4
end

local function empty_quote(text)
	return text:find("^[%s>]+$") ~= nil and text:find(">", 1, true) ~= nil
end

local function block_start(text)
	return fence(text) ~= nil
		or heading(text)
		or rule(text)
		or table_row(text)
		or html(text)
		or definition(text)
		or math_fence(text)
		or quote(text)
		or list_item(text) ~= nil
end

local function skipped(first, last, note)
	return { first = first, last = last, kind = "skip", note = note }
end

local function until_blank(lines, first, count)
	local last = first
	while last < count and not blank(lines[last + 1]) do
		last = last + 1
	end
	return last
end

local function hard_break(lines, first, last)
	for row = first, last - 1 do
		if lines[row]:find("  +$") or lines[row]:find("\\$") then
			return true
		end
	end
	return false
end

-- the marks of a quoted line with one space after them, the text after the marks, whether the text is indented as
-- code, and how deeply the line is quoted
local function quoted(text)
	local lead = text:match("^[%s>]*>%s?") or ""
	local depth = select(2, lead:gsub(">", ""))
	return lead, text:sub(#lead + 1), #(text:match("^[%s>]*>(%s*)") or "") >= 5, depth
end

-- first and last are 1-based here.
local function unit_at(lines, first, count)
	local text = lines[first]
	local item = list_item(text)
	if indent_width(text) >= 4 and not item then
		return skipped(first, until_blank(lines, first, count), "indented code")
	elseif heading(text) or rule(text) or definition(text) or math_fence(text) or text:find("^%s*[-*+]$") then
		return skipped(first, first, "heading, rule or definition")
	elseif table_row(text) or html(text) then
		return skipped(first, until_blank(lines, first, count), "table or HTML")
	end

	local is_quote = quote(text)
	local last = first
	if is_quote then
		while last < count and quote(lines[last + 1]) and not empty_quote(lines[last + 1]) do
			last = last + 1
		end
		local _, _, _, depth = quoted(text)
		for row = first, last do
			local _, body, indented, row_depth = quoted(lines[row])
			if row_depth ~= depth then
				return skipped(first, last, "quote of different depths")
			elseif indented or block_start(body) then
				return skipped(first, last, "block inside a quote")
			end
		end
	else
		while last < count and not blank(lines[last + 1]) and not block_start(lines[last + 1]) do
			last = last + 1
		end
		local underline = lines[last + 1]
		if not item and underline and underline:find("^%s*[=-]+%s*$") then
			return skipped(first, last + 1, "heading")
		end
		for row = first + 1, last do
			if delimiter_row(lines[row]) then
				return skipped(first, last, "table or HTML")
			elseif not item and (lines[row]:find("^%s*=+%s*$") or lines[row]:find("^%s*%-+%s*$")) then
				return skipped(first, last, "heading")
			end
		end
	end
	if hard_break(lines, first, last) then
		return skipped(first, last, "hard line break")
	end
	if item then
		return { first = first, last = last, kind = "list", item = item }
	end
	return { first = first, last = last, kind = is_quote and "quote" or "text" }
end

-- Every paragraph and block of the lines, in order, as { first, last, kind, note }: kind is "text", "list" or
-- "quote" for what can be filled, and "skip" for what is left alone because of the note.
function M.units(lines)
	local units = {}
	local count = #lines
	local row = 1
	local opening = lines[1] and lines[1]:match("^(%-%-%-)%s*$") or lines[1] and lines[1]:match("^(%+%+%+)%s*$")
	if opening then
		for candidate = 2, count do
			local text = lines[candidate]
			if text:match("^%s*$") == nil and (trim(text) == opening or trim(text) == "...") then
				table.insert(units, skipped(1, candidate, "front matter"))
				row = candidate + 1
				break
			end
		end
	end
	while row <= count do
		local text = lines[row]
		if blank(text) or empty_quote(text) then
			row = row + 1
		else
			local open = fence(text)
			local unit
			if open then
				local last = count
				for candidate = row + 1, count do
					if closes_fence(lines[candidate], open) then
						last = candidate
						break
					end
				end
				unit = skipped(row, last, "code block")
			else
				unit = unit_at(lines, row, count)
			end
			table.insert(units, unit)
			row = unit.last + 1
		end
	end
	for _, unit in ipairs(units) do
		unit.first, unit.last = unit.first - 1, unit.last - 1
	end
	return units
end

local function join_bodies(bodies)
	local parts, tail = {}, nil
	for _, body in ipairs(bodies) do
		body = trim(body)
		if body ~= "" then
			local between = ""
			if tail then
				between = (cjk(tail) or cjk(first_char(body))) and "" or " "
			end
			table.insert(parts, between .. body)
			tail = last_char((tail or "") .. between .. body)
		end
	end
	return table.concat(parts)
end

local function code_span_end(all, index)
	local length = 0
	while all[index + length] == "`" do
		length = length + 1
	end
	local position = index + length
	while position <= #all do
		if all[position] == "`" then
			local run = 0
			while all[position + run] == "`" do
				run = run + 1
			end
			if run == length then
				return position + run - 1
			end
			position = position + run
		else
			position = position + 1
		end
	end
	return nil
end

-- Words as { text, gap, cjk }, gap being the space before the word: a run of spaces becomes one, or two where it
-- followed the end of a sentence with two. Each CJK character is a word of its own.
local function atoms_of(text)
	local atoms = {}
	local pending, current = 0, nil
	local function flush()
		if current then
			table.insert(atoms, current)
			current = nil
		end
	end
	local function open_atom(atom_text, is_cjk)
		local previous = atoms[#atoms]
		local gap = ""
		if previous and pending > 0 then
			gap = (pending >= 2 and ends_sentence(previous.text)) and "  " or " "
		end
		current = { text = atom_text, gap = gap, cjk = is_cjk }
		pending = 0
	end
	local all = chars.split(text)
	local index = 0
	while index < #all do
		index = index + 1
		local char = all[index]
		-- a backslash makes the punctuation after it text: an escaped backtick starts no code span
		if char == "\\" and all[index + 1] and all[index + 1]:find("^%p$") then
			char = char .. all[index + 1]
			index = index + 1
		end
		local span_end = char == "`" and code_span_end(all, index)
		if char == "`" and not span_end then
			-- backticks that close nothing are text, the whole run of them
			local run_end = index
			while all[run_end + 1] == "`" do
				run_end = run_end + 1
			end
			char = table.concat(all, "", index, run_end)
			index = run_end
		end
		if span_end then
			-- the text of a code span is not touched, and no line breaks in it
			local span = table.concat(all, "", index, span_end)
			if current then
				current.text = current.text .. span
			else
				open_atom(span, false)
			end
			index = span_end
		elseif char == " " or char == "\t" then
			flush()
			pending = pending + 1
		else
			local is_cjk = cjk(char)
			if is_cjk or not current then
				flush()
				open_atom(char, is_cjk)
				if is_cjk then
					flush()
				end
			else
				current.text = current.text .. char
			end
		end
	end
	flush()
	return atoms
end

local function legal_before(previous, atom)
	if starts_block(atom.text) then
		return false
	end
	local first = first_char(atom.text)
	if NO_START[first] or NO_END[last_char(previous.text)] then
		return false
	end
	if NO_START_AFTER_CJK[first] and atom.gap == "" then
		return false
	end
	return atom.gap ~= "" or atom.cjk or previous.cjk
end

local function render(list)
	local text = ""
	for index, atom in ipairs(list) do
		text = text .. (index > 1 and atom.gap or "") .. atom.text
	end
	return text
end

-- A line that cannot be broken legally goes beyond the limit.
local function layout(atoms, lead, prefix, limit)
	local out, line, line_width = {}, {}, 0
	for _, atom in ipairs(atoms) do
		if #line == 0 then
			line = { atom }
			line_width = width(lead) + width(atom.text)
		else
			local extended = line_width + width(atom.gap) + width(atom.text)
			if extended <= limit then
				table.insert(line, atom)
				line_width = extended
			else
				local start
				for index = #line + 1, 2, -1 do
					if legal_before(line[index - 1], index == #line + 1 and atom or line[index]) then
						start = index
						break
					end
				end
				if start then
					table.insert(out, lead .. render(vim.list_slice(line, 1, start - 1)))
					lead = prefix
					local rest = start <= #line and vim.list_slice(line, start, #line) or {}
					table.insert(rest, atom)
					line = rest
					line_width = width(lead) + width(render(line))
				else
					table.insert(line, atom)
					line_width = extended
				end
			end
		end
	end
	if #line > 0 then
		table.insert(out, lead .. render(line))
	end
	return out
end

-- Returns { body_column, body } per line, then the prefixes of the first and of the other lines when filled.
local function split_prefixes(lines, unit, options)
	local split, lead, prefix = {}, "", ""
	local first = lines[1]
	if unit.kind == "list" then
		lead = unit.item.lead .. unit.item.marker .. unit.item.gap
		prefix = string.rep(" ", width(lead))
		split[1] = { #lead, first:sub(#lead + 1) }
		for row = 2, #lines do
			split[row] = { 0, lines[row] }
		end
	elseif unit.kind == "quote" then
		lead = quoted(first)
		prefix = lead
		for row = 1, #lines do
			local text_lead, body = quoted(lines[row])
			split[row] = { #text_lead, body }
		end
	else
		local indent = first:match("^[ \t]*")
		local explicit = options.prefix ~= "" and options.prefix or nil
		lead = explicit and first:sub(1, #explicit) == explicit and explicit or indent
		split[1] = { #lead, first:sub(#lead + 1) }
		for row = 2, #lines do
			local text = lines[row]
			local own = explicit and text:sub(1, #explicit) == explicit and explicit or text:match("^[ \t]*")
			split[row] = { #own, text:sub(#own + 1) }
		end
		prefix = explicit or (#lines > 1 and lines[2]:match("^[ \t]*") or indent)
	end
	return split, lead, prefix
end

local function nonblank_count(text)
	local total = 0
	for _, char in ipairs(chars.split(text)) do
		if char ~= " " and char ~= "\t" then
			total = total + 1
		end
	end
	return total
end

-- Fills the lines of one unit. Returns the new lines, and two functions that carry a position over: count(row, col)
-- tells how many characters that are not blanks come before a position of the old lines, and place(count) gives
-- the position after that many in the new lines.
function fill_unit(lines, unit, options)
	local split, lead, prefix = split_prefixes(lines, unit, options)
	local bodies = {}
	for _, pair in ipairs(split) do
		table.insert(bodies, pair[2])
	end
	-- "[ ]" of a task is no place to break
	local task
	if unit.kind == "list" then
		local box, rest = bodies[1]:match("^(%[[ xX]%])%s+(.*)$")
		if box then
			task, bodies[1] = box, rest
		end
	end
	local atoms = atoms_of(join_bodies(bodies))
	if task then
		if atoms[1] then
			atoms[1].gap = " "
		end
		table.insert(atoms, 1, { text = task, gap = "", cjk = false })
	end
	local out = #atoms > 0 and layout(atoms, lead, prefix, options.width) or vim.deepcopy(lines)

	local function count(row, col)
		local total = 0
		for index = 1, row do
			local start, body = split[index][1], split[index][2]
			if index < row then
				total = total + nonblank_count(body)
			elseif col > start then
				total = total + nonblank_count(lines[index]:sub(start + 1, col))
			end
		end
		return total
	end

	local function place(total)
		for index, text in ipairs(out) do
			local start = #(index == 1 and lead or prefix)
			local body = text:sub(start + 1)
			local available = nonblank_count(body)
			if total <= available or index == #out then
				local col = start
				for _, char in ipairs(chars.split(body)) do
					if total == 0 then
						break
					end
					col = col + #char
					if char ~= " " and char ~= "\t" then
						total = total - 1
					end
				end
				return index, col
			end
			total = total - available
		end
	end

	return out, count, place
end

return M
