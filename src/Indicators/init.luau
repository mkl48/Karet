-- Indicators - the terminal eye candy. progress bars, spinners, animated dots, all the
-- stuff you see scroll by in a real terminal (apt, npm, cargo...). a command grabs one
-- from ctx.Indicator{...}, then drives it: ind:Set(0.4), ind:Step(), ind:Succeed("done").
--
-- each indicator owns one live output line (an Output:appendLive() handle, just :set/:remove)
-- and rewrites it in place. spinners/dots animate on their own task loop until a terminal
-- state (Succeed/Fail/Remove). colours + characters are theme-driven but fully overridable
-- per indicator, so you can ship the legacy/shades/rect looks from the screenshots.
--
-- this is a client/terminal-only surface. on the server (or a compact bar) ctx.Indicator
-- hands back a no-op with the same shape, so handler code never has to branch on realm.

local Theme = require(script.Parent.Theme)
local Central = require(script.Parent.Defaults).Indicator

local Indicators = {}

-- preset spinner frame sets, pick with opts.spinner = "dots" / "line" / ...
local SPINNERS = {
	dots = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
	line = { "|", "/", "-", "\\" },
	bounce = { "⠁", "⠂", "⠄", "⠂" },
	arrow = { "←", "↖", "↑", "↗", "→", "↘", "↓", "↙" },
	circle = { "◐", "◓", "◑", "◒" },
	square = { "◰", "◳", "◲", "◱" },
	moon = { "🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘" },
	earth = { "🌍", "🌎", "🌏" },
	toggle = { "▮", "▯" },
	pulse = { "█", "▓", "▒", "░", "▒", "▓" },
}

local DEFAULTS = {
	width = Central.Width, -- bar cells
	fill = Central.Fill,
	empty = Central.Empty,
	left = Central.Left,
	right = Central.Right,
	spinner = Central.Spinner,
	interval = Central.Interval, -- seconds between animation frames
	check = Central.Check,
	cross = Central.Cross,
}

local function rgb(c: Color3): string
	return string.format("rgb(%d,%d,%d)", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- accept a Color3, a hex string ("#ff0000"/"ff0000"), or nil
local function toColor(v: any): Color3?
	if typeof(v) == "Color3" then
		return v
	elseif type(v) == "string" then
		local ok, c = pcall(Color3.fromHex, (string.gsub(v, "^#", "")))
		if ok then
			return c
		end
	end
	return nil
end

local function esc(s: string): string
	return (string.gsub(string.gsub(string.gsub(tostring(s), "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function span(text: string, color: Color3): string
	return `<font color="{rgb(color)}">{esc(text)}</font>`
end

local function clamp01(n: number): number
	return math.clamp(n, 0, 1)
end

-- ---------------------------------------------------------------------------

local Indicator = {}
Indicator.__index = Indicator

-- line: a live-line handle ({ set(richText), remove() }) from Output:appendLive
-- opts: { type, label, width, total, eta, spinner, interval, colors, characters }
function Indicators.new(line: any, opts: { [string]: any }?): any
	local options = opts or {}
	local self = setmetatable({}, Indicator)

	self.line = line
	self.kind = options.type or "progress"
	self.label = options.label or ""
	self.width = options.width or DEFAULTS.width
	self.total = options.total -- if set, Set/Step are absolute counts
	self.showEta = options.eta == true and self.total ~= nil
	self.value = 0
	self.frame = 1
	self.running = true
	self.startClock = os.clock()

	-- character overrides. characters can be a dict, or an array used as a custom spinner.
	local chars = options.characters or {}
	if type(chars) == "table" and chars[1] ~= nil then
		self.frames = chars
	else
		self.frames = SPINNERS[options.spinner] or (type(options.spinner) == "table" and options.spinner) or SPINNERS[DEFAULTS.spinner]
	end
	self.fillCh = (type(chars) == "table" and chars.fill) or DEFAULTS.fill
	self.emptyCh = (type(chars) == "table" and chars.empty) or DEFAULTS.empty
	self.leftCh = (type(chars) == "table" and chars.left) or DEFAULTS.left
	self.rightCh = (type(chars) == "table" and chars.right) or DEFAULTS.right
	self.interval = options.interval or DEFAULTS.interval

	-- colours. colors can be a named dict, or an array used as a left->right fill gradient.
	local p = Theme.Get()
	local colors = options.colors or {}
	self.gradient = nil
	if type(colors) == "table" and colors[1] ~= nil then
		self.gradient = {}
		for _, c in colors do
			table.insert(self.gradient, toColor(c) or p.Accent)
		end
	end
	self.cFill = toColor(colors.fill) or p.Accent
	self.cEmpty = toColor(colors.empty) or p.Muted
	self.cText = toColor(colors.text) or p.Foreground
	self.cSpin = toColor(colors.spinner) or p.Accent
	self.cDone = toColor(colors.done) or p.Success
	self.cFail = toColor(colors.fail) or p.Error

	if self.kind == "spinner" or self.kind == "dots" then
		self:_animate()
	else
		self:_render()
	end
	return self
end

function Indicator:_frac(): number
	if self.total then
		return clamp01(self.value / self.total)
	end
	local v = self.value
	if v > 1 then
		v /= 100 -- be forgiving: Set(72) means 72%
	end
	return clamp01(v)
end

-- the coloured bar string: [filled empty] with an optional left->right gradient
function Indicator:_bar(): string
	local frac = self:_frac()
	local cells = math.floor(frac * self.width + 0.5)
	local out = { span(self.leftCh, self.cEmpty) }
	if self.gradient and cells > 0 then
		local n = #self.gradient
		for i = 1, cells do
			local g = n == 1 and self.gradient[1] or self.gradient[math.min(n, math.floor((i - 1) / math.max(1, cells - 1) * (n - 1)) + 1)]
			table.insert(out, span(self.fillCh, g))
		end
	elseif cells > 0 then
		table.insert(out, span(string.rep(self.fillCh, cells), self.cFill))
	end
	if cells < self.width then
		table.insert(out, span(string.rep(self.emptyCh, self.width - cells), self.cEmpty))
	end
	table.insert(out, span(self.rightCh, self.cEmpty))
	return table.concat(out)
end

function Indicator:_etaText(): string?
	if not self.showEta or self.value <= 0 then
		return "ETA --"
	end
	local frac = self:_frac()
	if frac <= 0 or frac >= 1 then
		return nil
	end
	local elapsed = os.clock() - self.startClock
	local remaining = elapsed / frac - elapsed
	return string.format("ETA %ds", math.max(0, math.floor(remaining + 0.5)))
end

function Indicator:_render()
	if not self.running then
		return
	end
	if self.kind == "spinner" then
		local f = self.frames[(self.frame - 1) % #self.frames + 1]
		self.line.set(`{span(f, self.cSpin)} {span(self.label, self.cText)}`)
		return
	elseif self.kind == "dots" then
		local n = (self.frame - 1) % 4
		self.line.set(`{span(self.label, self.cText)}{span(string.rep(".", n), self.cSpin)}`)
		return
	end

	-- progress / bar
	local parts = { self:_bar() }
	local meta = { string.format("%d%%", math.floor(self:_frac() * 100 + 0.5)) }
	local eta = self:_etaText()
	if eta then
		table.insert(meta, eta)
	end
	if self.total then
		table.insert(meta, string.format("%d/%d", math.floor(self.value + 0.5), math.floor(self.total)))
	end
	table.insert(parts, span(table.concat(meta, " | "), self.cText))
	if self.label ~= "" then
		table.insert(parts, span(self.label, self.cText))
	end
	self.line.set(table.concat(parts, "  "))
end

-- self-driving frame loop for spinners/dots, stops on a terminal state
function Indicator:_animate()
	task.spawn(function()
		while self.running do
			self:_render()
			self.frame += 1
			task.wait(self.interval)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- public handle (the bit commands call)
-- ---------------------------------------------------------------------------

-- set progress: a 0..1 fraction, a 0..100 percent, or a count when opts.total is set
function Indicator:Set(value: number)
	self.value = value
	self:_render()
	return self
end

-- bump progress by `by` (default 1, or 1/total of a fraction bar)
function Indicator:Step(by: number?)
	self.value += by or (self.total and 1 or (1 / self.width))
	self:_render()
	return self
end

function Indicator:Label(text: string)
	self.label = tostring(text)
	self:_render()
	return self
end

-- freeze and mark done with a green check + message
function Indicator:Succeed(text: string?)
	self.running = false
	self.line.set(`{span(DEFAULTS.check, self.cDone)} {span(text or self.label, self.cDone)}`)
	return self
end

-- freeze and mark failed with a red cross + message
function Indicator:Fail(text: string?)
	self.running = false
	self.line.set(`{span(DEFAULTS.cross, self.cFail)} {span(text or self.label, self.cFail)}`)
	return self
end

-- finish a bar at 100% (or just stop a spinner), keeping it on screen
function Indicator:Finish(text: string?)
	self.running = false
	if self.kind == "progress" or self.kind == "bar" then
		self.value = self.total or 1
		if text then
			self.label = text
		end
		self:_render()
	else
		self:Succeed(text)
	end
	return self
end

-- drop the line entirely
function Indicator:Remove()
	self.running = false
	self.line.remove()
end

-- a same-shaped no-op for server handlers / compact bars where theres no live line
local NoopMeta = { __index = function()
	return function(self)
		return self
	end
end }
function Indicators.noop(): any
	return setmetatable({}, NoopMeta)
end

return Indicators
