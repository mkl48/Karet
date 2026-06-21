-- Render - the terminal eye-candy toolkit. pure string builders that turn data into the
-- rich, box-drawn, coloured blocks you see in a real terminal: panels, tables, trees,
-- key/value cards (neofetch style), bar charts, sparklines, rules, badges, side-by-side
-- columns. every function returns a RichText string (one or more \n lines), themed off the
-- active Karet.Theme but fully overridable per call.
--
-- these are PURE (no Roblox UI, just Color3 + the theme), so they're reachable as
-- Karet.Render.* anywhere and as ctx.UI.* (which also prints them to the terminal). the
-- terminal renders them in a monospaced font, so column alignment is done by character
-- count (utf8-aware, so box chars line up).

local Theme = require(script.Parent.Theme)
local Defaults = require(script.Parent.Defaults).Render

local Render = {}

-- ---------------------------------------------------------------------------
-- low-level helpers
-- ---------------------------------------------------------------------------

local function rgb(c: Color3): string
	return string.format("rgb(%d,%d,%d)", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function esc(s: string): string
	return (string.gsub(string.gsub(string.gsub(tostring(s), "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- resolve a colour input: a Color3, a hex string, or a theme group name ("Accent")
local function toColor(v: any): Color3?
	if typeof(v) == "Color3" then
		return v
	elseif type(v) == "string" then
		local pal = Theme.Get()
		if pal[v] then
			return pal[v]
		end
		local ok, c = pcall(Color3.fromHex, (string.gsub(v, "^#", "")))
		if ok then
			return c
		end
	end
	return nil
end

local function span(text: string, color: Color3): string
	return `<font color="{rgb(color)}">{esc(text)}</font>`
end

-- visible width of a string, ignoring rich <font> tags and counting unicode glyphs once
local function vlen(s: string): number
	local stripped = string.gsub(s, "<[^>]->", "")
	return utf8.len(stripped) or #stripped
end

local function padR(s: string, w: number): string
	local n = vlen(s)
	return n >= w and s or s .. string.rep(" ", w - n)
end

local function padL(s: string, w: number): string
	local n = vlen(s)
	return n >= w and s or string.rep(" ", w - n) .. s
end

local function splitLines(s: any): { string }
	if type(s) == "table" then
		return s
	end
	local out = {}
	for line in string.gmatch(tostring(s) .. "\n", "(.-)\n") do
		table.insert(out, line)
	end
	return out
end

-- ---------------------------------------------------------------------------
-- rules / dividers
-- ---------------------------------------------------------------------------

-- a horizontal divider, optionally with a centred label: ──── label ────
function Render.rule(label: string?, opts: { [string]: any }?): string
	opts = opts or {}
	local p = Theme.Get()
	local color = toColor(opts.color) or p.Border
	local width = opts.width or Defaults.RuleWidth
	local ch = opts.char or "─"
	if not label or label == "" then
		return span(string.rep(ch, width), color)
	end
	local lab = " " .. label .. " "
	local left = math.max(0, math.floor((width - vlen(lab)) / 2))
	local right = math.max(0, width - vlen(lab) - left)
	return span(string.rep(ch, left), color) .. span(lab, toColor(opts.label) or p.Accent) .. span(string.rep(ch, right), color)
end

-- ---------------------------------------------------------------------------
-- panels / boxes
-- ---------------------------------------------------------------------------

-- a bordered box around content (string or {lines}), with an optional title in the top edge
function Render.panel(content: any, opts: { [string]: any }?): string
	opts = opts or {}
	local p = Theme.Get()
	local bc = toColor(opts.color) or p.Border
	local tc = toColor(opts.titleColor) or p.Accent
	local fc = toColor(opts.text) or p.Foreground
	local lines = splitLines(content)

	local inner = opts.width or 0
	for _, l in lines do
		inner = math.max(inner, vlen(l))
	end
	if opts.title then
		inner = math.max(inner, vlen(opts.title) + 4)
	end

	local out = {}
	if opts.title then
		local fill = inner + 2 - (vlen(opts.title) + 3)
		table.insert(
			out,
			span("┌─ ", bc) .. span(opts.title, tc) .. span(" " .. string.rep("─", math.max(0, fill)) .. "┐", bc)
		)
	else
		table.insert(out, span("┌" .. string.rep("─", inner + 2) .. "┐", bc))
	end
	for _, l in lines do
		table.insert(out, span("│ ", bc) .. span(padR(l, inner), fc) .. span(" │", bc))
	end
	table.insert(out, span("└" .. string.rep("─", inner + 2) .. "┘", bc))
	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- tables
-- ---------------------------------------------------------------------------

-- a box-drawn table. opts = { headers = {..}, rows = {{..},..}, border = true?, color?, ... }
-- pass border = false for a lighter header-underline-only style.
function Render.table(opts: { [string]: any }): string
	local p = Theme.Get()
	local bc = toColor(opts.color) or p.Border
	local hc = toColor(opts.headerColor) or p.Accent
	local fc = toColor(opts.text) or p.Foreground
	local headers = opts.headers or {}
	local rows = opts.rows or {}
	local border = opts.border ~= false

	-- column count + widths
	local cols = #headers
	for _, r in rows do
		cols = math.max(cols, #r)
	end
	local w = table.create(cols, 0)
	for i = 1, cols do
		w[i] = vlen(tostring(headers[i] or ""))
	end
	for _, r in rows do
		for i = 1, cols do
			w[i] = math.max(w[i], vlen(tostring(r[i] or "")))
		end
	end

	local out = {}
	local function bar(l: string, m: string, r: string)
		local segs = {}
		for i = 1, cols do
			table.insert(segs, string.rep("─", w[i] + 2))
		end
		return span(l .. table.concat(segs, m) .. r, bc)
	end
	local function rowLine(cells: { any }, color: Color3)
		local segs = { span("│", bc) }
		for i = 1, cols do
			table.insert(segs, span(" " .. padR(tostring(cells[i] or ""), w[i]) .. " ", color))
			table.insert(segs, span("│", bc))
		end
		return table.concat(segs)
	end

	if border then
		table.insert(out, bar("┌", "┬", "┐"))
		if #headers > 0 then
			table.insert(out, rowLine(headers, hc))
			table.insert(out, bar("├", "┼", "┤"))
		end
		for _, r in rows do
			table.insert(out, rowLine(r, fc))
		end
		table.insert(out, bar("└", "┴", "┘"))
	else
		if #headers > 0 then
			local segs = {}
			for i = 1, cols do
				table.insert(segs, span(padR(tostring(headers[i] or ""), w[i]), hc))
			end
			table.insert(out, table.concat(segs, span("  ", bc)))
			local total = 0
			for i = 1, cols do
				total += w[i] + 2
			end
			table.insert(out, span(string.rep("─", math.max(0, total - 2)), bc))
		end
		for _, r in rows do
			local segs = {}
			for i = 1, cols do
				table.insert(segs, span(padR(tostring(r[i] or ""), w[i]), fc))
			end
			table.insert(out, table.concat(segs, "  "))
		end
	end
	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- trees
-- ---------------------------------------------------------------------------

-- a tree view. node = string, or { label = "..", children = { node, .. } }. nested freely.
function Render.tree(node: any, opts: { [string]: any }?): string
	opts = opts or {}
	local p = Theme.Get()
	local branch = toColor(opts.color) or p.Muted
	local fc = toColor(opts.text) or p.Foreground
	local rootColor = toColor(opts.rootColor) or p.Accent
	local out = {}

	local function label(n: any): string
		return type(n) == "table" and tostring(n.label) or tostring(n)
	end
	local function kids(n: any): { any }?
		return type(n) == "table" and n.children or nil
	end

	local function walk(n: any, prefix: string, isLast: boolean, isRoot: boolean)
		if isRoot then
			table.insert(out, span(label(n), rootColor))
		else
			table.insert(out, span(prefix .. (isLast and "└─ " or "├─ "), branch) .. span(label(n), fc))
		end
		local children = kids(n)
		if children then
			local childPrefix = isRoot and "" or (prefix .. (isLast and "   " or "│  "))
			for i, c in children do
				walk(c, childPrefix, i == #children, false)
			end
		end
	end
	walk(node, "", true, true)
	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- key/value cards (the neofetch look)
-- ---------------------------------------------------------------------------

-- aligned key : value pairs. items = { { "Key", "Value" }, .. } or { Key = "Value", .. }
function Render.fields(items: any, opts: { [string]: any }?): string
	opts = opts or {}
	local p = Theme.Get()
	local kc = toColor(opts.keyColor) or p.Accent
	local vc = toColor(opts.text) or p.Foreground
	local sc = toColor(opts.sepColor) or p.Muted
	local sep = opts.sep or " : "

	-- normalise to an ordered array of {key, value}
	local pairs_ = {}
	if items[1] ~= nil then
		for _, kv in items do
			table.insert(pairs_, { tostring(kv[1]), tostring(kv[2]) })
		end
	else
		for k, v in items do
			table.insert(pairs_, { tostring(k), tostring(v) })
		end
		table.sort(pairs_, function(a, b)
			return a[1] < b[1]
		end)
	end

	local kw = 0
	for _, kv in pairs_ do
		kw = math.max(kw, vlen(kv[1]))
	end
	local out = {}
	for _, kv in pairs_ do
		table.insert(out, span(padR(kv[1], kw), kc) .. span(sep, sc) .. span(kv[2], vc))
	end
	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- lists / checklists
-- ---------------------------------------------------------------------------

local LIST_ICONS = {
	ok = { "✓", "Success" },
	done = { "✓", "Success" },
	fail = { "✗", "Error" },
	err = { "✗", "Error" },
	warn = { "!", "Warn" },
	pending = { "…", "Muted" },
	info = { "•", "Accent" },
	bullet = { "•", "Muted" },
}

-- a status list. items = { "text", .. } or { { text = "..", status = "ok"/"fail"/.. }, .. }
function Render.list(items: { any }, opts: { [string]: any }?): string
	opts = opts or {}
	local p = Theme.Get()
	local fc = toColor(opts.text) or p.Foreground
	local out = {}
	for _, it in items do
		local text, status
		if type(it) == "table" then
			text, status = tostring(it.text or it[1]), it.status or it[2]
		else
			text, status = tostring(it), "bullet"
		end
		local def = LIST_ICONS[status or "bullet"] or LIST_ICONS.bullet
		local ic = toColor(def[2]) or p.Muted
		table.insert(out, span(def[1] .. " ", ic) .. span(text, fc))
	end
	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- charts
-- ---------------------------------------------------------------------------

local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

-- a tiny inline chart from a list of numbers: ▁▂▄▆█▆▄▂
function Render.sparkline(numbers: { number }, opts: { [string]: any }?): string
	opts = opts or {}
	local p = Theme.Get()
	local color = toColor(opts.color) or p.Accent
	if #numbers == 0 then
		return ""
	end
	local lo, hi = math.huge, -math.huge
	for _, n in numbers do
		lo, hi = math.min(lo, n), math.max(hi, n)
	end
	local range = hi - lo
	local chars = {}
	for _, n in numbers do
		local idx = range == 0 and 4 or (math.floor((n - lo) / range * (#SPARK - 1) + 0.5) + 1)
		table.insert(chars, SPARK[idx])
	end
	return span(table.concat(chars), color)
end

-- a horizontal bar chart. items = { { "label", value }, .. }. opts.width = bar cells.
function Render.barchart(items: { any }, opts: { [string]: any }?): string
	opts = opts or {}
	local p = Theme.Get()
	local lc = toColor(opts.labelColor) or p.Accent
	local fillc = toColor(opts.color) or p.Accent
	local emptyc = toColor(opts.empty) or p.Muted
	local vc = toColor(opts.text) or p.Foreground
	local width = opts.width or Defaults.BarWidth
	local fillCh, emptyCh = opts.fill or "█", opts.emptyChar or "░"

	local lw, maxv = 0, opts.max or -math.huge
	for _, it in items do
		lw = math.max(lw, vlen(tostring(it[1])))
		if not opts.max then
			maxv = math.max(maxv, it[2])
		end
	end
	if maxv <= 0 then
		maxv = 1
	end

	local out = {}
	for _, it in items do
		local frac = math.clamp(it[2] / maxv, 0, 1)
		local cells = math.floor(frac * width + 0.5)
		local bar = span(string.rep(fillCh, cells), fillc) .. span(string.rep(emptyCh, width - cells), emptyc)
		table.insert(out, span(padR(tostring(it[1]), lw), lc) .. " " .. bar .. " " .. span(tostring(it[2]), vc))
	end
	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- inline bits + layout
-- ---------------------------------------------------------------------------

-- an inline coloured tag: [label]
function Render.badge(text: string, opts: { [string]: any }?): string
	opts = opts or {}
	local p = Theme.Get()
	local color = toColor(opts.color) or p.Accent
	local bracket = toColor(opts.bracket) or p.Muted
	return span("[", bracket) .. span(tostring(text), color) .. span("]", bracket)
end

-- colour a chunk of text (Color3 / hex / theme group). handy inside ctx.UI.Markup.
function Render.color(text: string, color: any): string
	return span(tostring(text), toColor(color) or Theme.Get().Foreground)
end

-- lay blocks side by side: columns({ asciiArt, fields }, { gap = 3 }). rich-safe (it pads
-- by visible width), so this is how you get the neofetch art-beside-specs layout.
function Render.columns(blocks: { any }, opts: { [string]: any }?): string
	opts = opts or {}
	local gap = string.rep(" ", opts.gap or 2)
	local cols, widths, height = {}, {}, 0
	for i, b in blocks do
		local lines = splitLines(b)
		cols[i] = lines
		local w = 0
		for _, l in lines do
			w = math.max(w, vlen(l))
		end
		widths[i] = w
		height = math.max(height, #lines)
	end
	local out = {}
	for row = 1, height do
		local cells = {}
		for i, lines in cols do
			table.insert(cells, padR(lines[row] or "", widths[i]))
		end
		table.insert(out, table.concat(cells, gap))
	end
	return table.concat(out, "\n")
end

return Render
