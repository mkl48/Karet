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

local WindowManager = {}

local iris: any = nil
local started = false
local windows: { any } = {}

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

-- a text line. returns a handle so you can update it: label.set("new text")
function Window:Label(text: any): any
	local spec = { kind = "text", text = tostring(text) }
	table.insert(self.widgets, spec)
	return { set = function(t: any)
		spec.text = tostring(t)
	end }
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
	local ok = pcall(function()
		i.Window({ self.title }, { isOpened = self.openState })
		for _, w in self.widgets do
			if w.kind == "text" then
				i.Text({ w.text })
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
