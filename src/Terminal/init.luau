-- Karet.Terminal — the visible console surface (the Alacritty analogue).
--
-- Composes the window chrome, the scrolling Output log, and the Input row, drives them
-- all from the active Karet.Theme (recolouring live on a theme switch), and owns the
-- open/close lifecycle. Switch provides the toggle/close/history *actions*; because Switch
-- is client-only it is required lazily inside enableSwitch(), never at module load, so the
-- Karet umbrella that requires this module stays safe to load on the server.
--
-- Text entry itself is the Input row's TextBox - Switch is not in that path. The toggle is
-- a single global action driven off the open state; while open, an OPEN_CONTEXT carries the
-- Escape-to-close and Up/Down history actions. Placement (Window/Top/Bottom) and the mount
-- parent are configurable via Terminal.new(opts) / :mount().

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)
local deps = require(script.Parent.deps)
local create = require(script.create)
local Output = require(script.Output)
local Input = require(script.Input)

local Terminal = {}
Terminal.__index = Terminal

local OPEN_CONTEXT = "KaretTerminal"

-- Window geometry per placement mode. Custom Size/Position in opts override these.
local PLACEMENTS = {
	Window = { Anchor = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 340) },
	Top = { Anchor = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(1, -16, 0, 320) },
	Bottom = { Anchor = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -16, 0, 320) },
}

-- opts: { Placement = "Window"|"Top"|"Bottom", Parent = Instance?, Size = UDim2?, Position = UDim2? }
function Terminal.new(opts: { [string]: any }?)
	local self = setmetatable({}, Terminal)
	local options = opts or {}

	self.options = options
	self.placement = PLACEMENTS[options.Placement or "Window"] or PLACEMENTS.Window
	self.isOpen = false
	self.switch = nil :: any -- the Switch module, once enableSwitch resolves it
	self.actions = {} :: { string } -- Switch action names, for teardown
	self.themed = {} :: { [string]: any } -- chrome instances keyed by their theme group

	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		Font = Enum.Font.Code,
		TextSize = 14,
		Text = "Karet",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}) :: TextLabel

	local titleBar = create("Frame", {
		Name = "TitleBar",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 24),
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			title,
		},
	})

	local separator = create("Frame", {
		Name = "Separator",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0, 24),
	})

	-- Holders so Output fills the space above the fixed-height Input row.
	local outputHolder = create("Frame", {
		Name = "OutputHolder",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -24 - 30),
		Position = UDim2.new(0, 0, 0, 25),
	})

	local inputHolder = create("Frame", {
		Name = "InputHolder",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 1, -30),
	})

	local stroke = create("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })

	local window = create("Frame", {
		Name = "Window",
		AnchorPoint = self.placement.Anchor,
		Position = options.Position or self.placement.Position,
		Size = options.Size or self.placement.Size,
		BorderSizePixel = 0,
		Visible = false,
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			stroke,
			titleBar,
			separator,
			outputHolder,
			inputHolder,
		},
	})

	local gui = create("ScreenGui", {
		Name = "Karet",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = true,
		Children = { window },
	})

	self.gui = gui
	self.window = window
	self.output = Output.new(outputHolder)
	self.input = Input.new(inputHolder)

	self.themed.Background = window
	self.themed.Surface = titleBar
	self.themed.Accent = title
	self.themed.Border = { stroke, separator }

	-- Echo the submitted line, then hand it to the external submit handler.
	self.input:onSubmit(function(line)
		self.output:append(`› {line}`, "Comment")
		if self.submitHandler then
			self.submitHandler(line)
		end
	end)

	-- Recolour everything now and whenever the theme changes.
	self.unsubscribeTheme = Theme.OnChanged(function(palette)
		self:applyTheme(palette)
	end)

	return self
end

-- Parent the ScreenGui. Uses the target arg, else opts.Parent, else (on the client) the
-- local player's PlayerGui. A custom Parent can be any GuiBase2d/ScreenGui/CoreGui surface.
function Terminal:mount(target: Instance?)
	local parent = target or self.options.Parent
	if not parent and RunService:IsClient() then
		local player = Players.LocalPlayer
		parent = player and player:FindFirstChildOfClass("PlayerGui")
	end
	if parent then
		self.gui.Parent = parent
	else
		warn("Karet.Terminal:mount - no parent given and no PlayerGui found")
	end
	return self
end

function Terminal:applyTheme(palette: { [string]: Color3 })
	self.window.BackgroundColor3 = palette.Background
	self.themed.Surface.BackgroundColor3 = palette.Surface
	self.themed.Accent.TextColor3 = palette.Accent
	for _, inst in self.themed.Border do
		if inst:IsA("UIStroke") then
			inst.Color = palette.Border
		else
			inst.BackgroundColor3 = palette.Border
		end
	end
	self.output:applyTheme(palette)
	self.input:applyTheme(palette)
end

-- ---------------------------------------------------------------------------
-- open / close lifecycle
-- ---------------------------------------------------------------------------

function Terminal:open()
	if self.isOpen then
		return
	end
	self.isOpen = true
	self.window.Visible = true
	if self.switch then
		self.switch.PushContext(OPEN_CONTEXT)
	end
	self.input:focus()
end

function Terminal:close()
	if not self.isOpen then
		return
	end
	self.isOpen = false
	self.input:blur()
	self.window.Visible = false
	if self.switch then
		self.switch.PopContext(OPEN_CONTEXT)
	end
end

function Terminal:toggle()
	if self.isOpen then
		self:close()
	else
		self:open()
	end
end

-- Wire the toggle/close/history actions through Switch. toggleKey is a KeyCode name string
-- (e.g. "Semicolon"). Client-only; degrades to a no-op with a warning if Switch is
-- unavailable, so the terminal still works programmatically and via mouse focus.
--
-- The toggle is a single global action driven off self.isOpen (so it never desyncs from a
-- programmatic open/close). Note: a global toggle key cannot also be *typed* into a command
-- while the terminal is open - pick a key you wouldn't type (the default ; is fine). Escape
-- closes; Up/Down browse history (only while open, via the OPEN_CONTEXT).
function Terminal:enableSwitch(toggleKey: string)
	if not RunService:IsClient() then
		warn("Karet.Terminal:enableSwitch - Switch is client-only; ignoring on the server")
		return
	end
	local Switch = deps.Switch()
	if not Switch then
		return
	end
	local keyCode = (Enum.KeyCode :: any)[toggleKey]
	if not keyCode then
		warn(`Karet.Terminal:enableSwitch - '{toggleKey}' is not a valid KeyCode name`)
		return
	end

	self.switch = Switch
	local Enums = Switch.Enums

	local function action(name: string, bindings: { any }, contexts: { string }?, handler: (any) -> ())
		local handle = Switch.Define(name, { Bindings = bindings, Contexts = contexts, Sink = true })
		handle:Next(Enums.State.Pressed):Then(handler)
		table.insert(self.actions, name)
	end

	-- Global toggle: always active, flips based on current state.
	action("KaretToggle", { keyCode }, nil, function(event)
		event:Consume()
		self:toggle()
	end)
	-- Escape closes; history nav - only while the terminal is open.
	action("KaretClose", { Enum.KeyCode.Escape }, { OPEN_CONTEXT }, function(event)
		event:Consume()
		self:close()
	end)
	action("KaretHistoryPrev", { Enum.KeyCode.Up }, { OPEN_CONTEXT }, function()
		self.input:historyPrev()
	end)
	action("KaretHistoryNext", { Enum.KeyCode.Down }, { OPEN_CONTEXT }, function()
		self.input:historyNext()
	end)
end

-- ---------------------------------------------------------------------------
-- output API
-- ---------------------------------------------------------------------------

function Terminal:print(text: string, group: string?)
	self.output:append(text, group or "Output")
end

function Terminal:error(text: string)
	self.output:append(text, "Error")
end

function Terminal:warn(text: string)
	self.output:append(text, "Warn")
end

function Terminal:info(text: string)
	self.output:append(text, "Info")
end

function Terminal:success(text: string)
	self.output:append(text, "Success")
end

function Terminal:clear()
	self.output:clear()
end

-- Register the handler that runs a submitted line (after it is echoed).
function Terminal:onSubmit(fn: (string) -> ())
	self.submitHandler = fn
end

function Terminal:destroy()
	if self.unsubscribeTheme then
		self.unsubscribeTheme()
	end
	if self.switch then
		for _, name in self.actions do
			self.switch.Remove(name)
		end
		self.switch.PopContext(OPEN_CONTEXT)
	end
	self.output:destroy()
	self.input:destroy()
	self.gui:Destroy()
end

return Terminal
