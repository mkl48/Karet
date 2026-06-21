-- WindowManager - a retained-mode wrapper over Iris so a command can pop a real window
-- without touching Iris' immediate-mode lifecycle. you describe the window once (add labels,
-- buttons, inputs, checkboxes, sliders) and the manager re-renders it every Iris frame,
-- wiring button clicks and syncing input/checkbox/slider state back to getters you hold.
--
-- a command grabs one from ctx.Window{ title = "..." }:
--   local w = ctx.Window({ title = "Teleport" })
--   local x = w:Input("x", 0)
--   w:Button("go", function() teleport(tonumber(x.get())) end)
-- the window stays open until w:Close() or the user clicks its X.
--
-- Iris is client-only; off the terminal ctx.Window hands back a no-op with the same shape.

local deps = require(script.Parent.deps)
local Theme = require(script.Parent.Theme)
local Defaults = require(script.Parent.Defaults)

local WindowManager = {}

local iris: any = nil
local started = false
local themed = false
local windows: { any } = {}

-- Map Karet's active palette onto Iris' (ImGui-style) config so windows match the rest of
-- the library instead of looking like stock Iris. Re-applied whenever the theme switches.
local function applyTheme()
	if not iris then
		return
	end
	local p = Theme.Get()
	pcall(iris.UpdateGlobalConfig, {
		TextFont = Font.fromEnum(Defaults.Font),
		TextColor = p.Foreground,
		TextTransparency = 0,
		TextDisabledColor = p.Muted,

		WindowBgColor = p.Background,
		WindowBgTransparency = 0,
		PopupBgColor = p.Surface,
		PopupBgTransparency = 0,

		TitleBgColor = p.Surface,
		TitleBgTransparency = 0,
		TitleBgActiveColor = p.Surface,
		TitleBgActiveTransparency = 0,
		TitleBgCollapsedColor = p.Surface,
		TitleBgCollapsedTransparency = 0,

		BorderColor = p.Border,
		BorderTransparency = 0,
		BorderActiveColor = p.Accent,
		BorderActiveTransparency = 0,
		WindowBorderSize = 1,
		FrameBorderSize = 0,
		FrameRounding = 6,

		ButtonColor = p.Surface,
		ButtonTransparency = 0,
		ButtonHoveredColor = p.Selection,
		ButtonHoveredTransparency = 0,
		ButtonActiveColor = p.Accent,
		ButtonActiveTransparency = 0,

		FrameBgColor = p.Surface,
		FrameBgTransparency = 0,
		FrameBgHoveredColor = p.Selection,
		FrameBgHoveredTransparency = 0,
		FrameBgActiveColor = p.Selection,
		FrameBgActiveTransparency = 0,

		CheckMarkColor = p.Accent,
		CheckMarkTransparency = 0,
		SliderGrabColor = p.Accent,
		SliderGrabTransparency = 0,
		SliderGrabActiveColor = p.Accent,
		SliderGrabActiveTransparency = 0,

		HeaderColor = p.Selection,
		HeaderTransparency = 0,
		HeaderHoveredColor = p.Selection,
		HeaderHoveredTransparency = 0,
		HeaderActiveColor = p.Accent,
		HeaderActiveTransparency = 0,

		SeparatorColor = p.Border,
		SeparatorTransparency = 0,
		ScrollbarGrabColor = p.Muted,
		ScrollbarGrabTransparency = 0,
		ResizeGripColor = p.Muted,
		ResizeGripTransparency = 0.4,
		ResizeGripHoveredColor = p.Accent,
		ResizeGripHoveredTransparency = 0,
		ResizeGripActiveColor = p.Accent,
		ResizeGripActiveTransparency = 0,
	})
end

local Window = {}
Window.__index = Window

-- Is Iris around? (ctx.Window falls back to a no-op when it isn't.)
function WindowManager.available(): boolean
	return deps.Iris() ~= nil
end

local function ensureStarted(parent: Instance?): any?
	if started then
		return iris
	end
	iris = deps.Iris()
	if not iris then
		return nil
	end
	pcall(iris.Init, parent, nil, true)
	-- theme to match Karet, and stay matched on theme switches
	if not themed then
		themed = true
		Theme.OnChanged(function()
			applyTheme()
		end)
	end
	iris:Connect(function()
		-- iterate a snapshot - a render may close (and remove) its window
		for _, w in table.clone(windows) do
			if w.open then
				w:_render()
			end
		end
	end)
	started = true
	return iris
end

-- open a window. opts = { title?, parent? }
function WindowManager.open(opts: { [string]: any }?): any?
	local i = ensureStarted(opts and opts.parent)
	if not i then
		return nil
	end
	local self = setmetatable({
		title = (opts and opts.title) or "Karet",
		widgets = {},
		open = true,
		openState = i.State(true),
		onClose = nil :: (() -> ())?,
	}, Window)
	table.insert(windows, self)
	return self
end

-- a text line. `text` may be a string OR a function evaluated every frame (for live
-- readouts). returns a handle so you can also update a static label: label.set("...").
function Window:Label(text: any): any
	local spec = { kind = "text", text = (type(text) == "function") and text or tostring(text) }
	table.insert(self.widgets, spec)
	return { set = function(t: any)
		spec.text = (type(t) == "function") and t or tostring(t)
	end }
end

-- a rolling line graph. returns { push(value) } - push a sample each frame (usually from
-- OnRender) and it scrolls. opts = { height?, min?, max?, capacity? }.
function Window:Plot(label: string, opts: { [string]: any }?): any
	opts = opts or {}
	local capacity = opts.capacity or 96
	local values = { 0 }
	local state = iris.State(values)
	table.insert(self.widgets, { kind = "plot", label = label, state = state, height = opts.height or 60, min = opts.min, max = opts.max })
	return {
		push = function(v: number)
			table.insert(values, v)
			while #values > capacity do
				table.remove(values, 1)
			end
			state:set(table.clone(values))
		end,
	}
end

-- run `fn` once per frame while the window is open (drive plots / dynamic state from here)
function Window:OnRender(fn: () -> ())
	self._onRender = fn
end

-- a button; onClick runs (on its own thread) when pressed
function Window:Button(text: string, onClick: (() -> ())?): any
	table.insert(self.widgets, { kind = "button", text = text, onClick = onClick })
	return self
end

function Window:Separator(): any
	table.insert(self.widgets, { kind = "sep" })
	return self
end

-- a text field. returns { get(), set(v) }
function Window:Input(label: string, default: any?): any
	local state = iris.State(tostring(default or ""))
	table.insert(self.widgets, { kind = "input", label = label, state = state })
	return {
		get = function()
			return state:get()
		end,
		set = function(v: any)
			state:set(tostring(v))
		end,
	}
end

-- a checkbox. returns { get() -> boolean, set(v) }
function Window:Checkbox(label: string, default: boolean?): any
	local state = iris.State(default == true)
	table.insert(self.widgets, { kind = "check", label = label, state = state })
	return {
		get = function()
			return state:get()
		end,
		set = function(v: any)
			state:set(v == true)
		end,
	}
end

-- a number slider. returns { get() -> number, set(v) }
function Window:Slider(label: string, min: number?, max: number?, default: number?): any
	local lo, hi = min or 0, max or 100
	local state = iris.State(default or lo)
	table.insert(self.widgets, { kind = "slider", label = label, min = lo, max = hi, state = state })
	return {
		get = function()
			return state:get()
		end,
		set = function(v: any)
			state:set(v)
		end,
	}
end

-- a Color3 picker (Iris InputColor3). returns { get() -> Color3, set(c) }
function Window:Color(label: string, default: Color3?): any
	local state = iris.State(default or Color3.new(1, 1, 1))
	table.insert(self.widgets, { kind = "color", label = label, state = state })
	return {
		get = function()
			return state:get()
		end,
		set = function(v: Color3)
			state:set(v)
		end,
	}
end

function Window:OnClose(fn: () -> ())
	self.onClose = fn
end

function Window:Close()
	if not self.open then
		return
	end
	self.open = false
	pcall(function()
		self.openState:set(false)
	end)
	local idx = table.find(windows, self)
	if idx then
		table.remove(windows, idx)
	end
	if self.onClose then
		task.spawn(self.onClose)
	end
end

function Window:_render()
	local i = iris
	if self._onRender then
		pcall(self._onRender)
	end
	local ok = pcall(function()
		i.Window({ self.title }, { isOpened = self.openState })
		for _, w in self.widgets do
			if w.kind == "text" then
				local text = w.text
				if type(text) == "function" then
					local okEval, result = pcall(text)
					text = okEval and tostring(result) or "?"
				end
				i.Text({ text })
			elseif w.kind == "plot" then
				local args = { w.label, w.height }
				args[3] = w.min
				args[4] = w.max
				i.PlotLines(args, { values = w.state })
			elseif w.kind == "button" then
				if i.Button({ w.text }).clicked() and w.onClick then
					task.spawn(w.onClick)
				end
			elseif w.kind == "sep" then
				i.Separator()
			elseif w.kind == "input" then
				i.InputText({ w.label }, { text = w.state })
			elseif w.kind == "check" then
				i.Checkbox({ w.label }, { isChecked = w.state })
			elseif w.kind == "slider" then
				i.SliderNum({ w.label, 1, w.min, w.max }, { number = w.state })
			elseif w.kind == "color" then
				i.InputColor3({ w.label }, { color = w.state })
			end
		end
		i.End()
	end)
	-- user closed it via the X, or a render error - tear it down once
	if (not ok or self.openState:get() == false) and self.open then
		self:Close()
	end
end

return WindowManager
