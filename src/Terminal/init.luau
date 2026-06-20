-- Karet.Terminal - the visible console surface (the Alacritty analogue).
--
-- Composes the window chrome, the scrolling Output log, and the Input row, drives them all
-- from the active Karet.Theme (recolouring live on a theme switch), and owns the open/close
-- lifecycle. Switch provides the toggle/close *actions*; because Switch is client-only it is
-- required lazily inside enableSwitch(), never at module load, so the Karet umbrella that
-- requires this module stays safe to load on the server.
--
-- Two presentations:
--   • full window (default) - title bar + scrolling output + input, optionally Draggable.
--   • Compact = true        - a single-line command bar (Top/Bottom/Middle) that grows by
--                             one line to show the latest result, then collapses on clear.
--
-- Placement, Parent, Size, Position are all configurable via Terminal.new(opts) / :mount().

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local deps = require(script.Parent.deps)
local Capture = require(script.Parent.Capture)
local create = require(script.create)
local Output = require(script.Output)
local Input = require(script.Input)
local Indicators = require(script.Parent.Indicators)
local Render = require(script.Parent.Render)

local Terminal = {}
Terminal.__index = Terminal

-- Public terminal surface (typed so `local t = Karet.Start(...)` autocompletes t:open() etc.)
export type Terminal = {
	isOpen: boolean,
	compact: boolean,
	gui: Instance,
	open: (self: Terminal) -> (),
	close: (self: Terminal) -> (),
	toggle: (self: Terminal) -> (),
	mount: (self: Terminal, target: Instance?) -> Terminal,
	enableSwitch: (self: Terminal, toggle: string | { Key: string, Modifier: string? }) -> (),
	print: (self: Terminal, text: string, group: string?) -> (),
	error: (self: Terminal, text: string) -> (),
	warn: (self: Terminal, text: string) -> (),
	info: (self: Terminal, text: string) -> (),
	success: (self: Terminal, text: string) -> (),
	indicator: (self: Terminal, opts: { [string]: any }?) -> any,
	printRich: (self: Terminal, richText: string, group: string?) -> (),
	ui: (self: Terminal) -> { [string]: any },
	promptText: (self: Terminal, question: string) -> boolean,
	promptWindow: (self: Terminal, question: string) -> boolean,
	clear: (self: Terminal) -> (),
	onSubmit: (self: Terminal, fn: (string) -> ()) -> (),
	destroy: (self: Terminal) -> (),
}

local OPEN_CONTEXT = "KaretTerminal"

-- Full-window geometry per placement mode. Custom Size/Position in opts override these.
local PLACEMENTS = {
	Window = { Anchor = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 340) },
	Top = { Anchor = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(1, -16, 0, 320) },
	Bottom = { Anchor = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -16, 0, 320) },
}

-- Compact single-line bar geometry. Height grows by RESULT_H when there's a result to show.
local BAR_H = 34
local RESULT_H = 24
local COMPACT_PLACEMENTS = {
	Top = { Anchor = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(1, -16, 0, BAR_H) },
	Bottom = { Anchor = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -16, 0, BAR_H) },
	Middle = { Anchor = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, BAR_H) },
}

-- opts: { Compact = boolean?, Placement = string?, Parent = Instance?, Size = UDim2?,
--         Position = UDim2?, Draggable = boolean? }
function Terminal.new(opts: { [string]: any }?)
	local self = setmetatable({}, Terminal)
	local options = opts or {}

	self.options = options
	self.compact = options.Compact == true
	self.isOpen = false
	self.switch = nil :: any
	self.actions = {} :: { string }
	self.themed = {} :: { [string]: any }
	self.palette = nil :: any

	if self.compact then
		self.placement = COMPACT_PLACEMENTS[options.Placement or "Bottom"] or COMPACT_PLACEMENTS.Bottom
		self:buildCompact(options)
	else
		self.placement = PLACEMENTS[options.Placement or "Window"] or PLACEMENTS.Window
		self:buildWindow(options)
	end

	-- Recolour everything now and whenever the theme changes.
	self.unsubscribeTheme = Theme.OnChanged(function(palette)
		self:applyTheme(palette)
	end)

	-- ctrl +/- zoom (and ctrl+0 reset), client only.
	if RunService:IsClient() then
		self:setupZoom()
	end

	return self
end

-- ---------------------------------------------------------------------------
-- zoom (ctrl +/-), scales the whole window via UIScale
-- ---------------------------------------------------------------------------

local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 0.6, 2.0, 0.1

function Terminal:setScale(scale: number)
	if not self.scaleObj then
		return
	end
	self.scaleObj.Scale = math.clamp(scale, ZOOM_MIN, ZOOM_MAX)
end

function Terminal:zoomBy(delta: number)
	if self.scaleObj then
		self:setScale(self.scaleObj.Scale + delta)
	end
end

function Terminal:setupZoom()
	self.zoomConn = UserInputService.InputBegan:Connect(function(input)
		if not self.isOpen then
			return
		end
		if not (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Equals or key == Enum.KeyCode.KeypadPlus then
			self:zoomBy(ZOOM_STEP)
		elseif key == Enum.KeyCode.Minus or key == Enum.KeyCode.KeypadMinus then
			self:zoomBy(-ZOOM_STEP)
		elseif key == Enum.KeyCode.Zero or key == Enum.KeyCode.KeypadZero then
			self:setScale(1)
		end
	end)
end

local function makeGui(window: Instance): Instance
	return create("ScreenGui", {
		Name = "Karet",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = true,
		Children = { window },
	})
end

-- ---------------------------------------------------------------------------
-- full window
-- ---------------------------------------------------------------------------

function Terminal:buildWindow(options)
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
		Children = { create("UICorner", { CornerRadius = UDim.new(0, 8) }), title },
	})

	local separator = create("Frame", {
		Name = "Separator",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0, 24),
	})

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
	local scale = create("UIScale", { Scale = 1 })

	local window = create("Frame", {
		Name = "Window",
		AnchorPoint = self.placement.Anchor,
		Position = options.Position or self.placement.Position,
		Size = options.Size or self.placement.Size,
		BorderSizePixel = 0,
		Visible = false,
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			scale,
			stroke,
			titleBar,
			separator,
			outputHolder,
			inputHolder,
		},
	})
	self.scaleObj = scale

	self.gui = makeGui(window)
	self.window = window
	self.output = Output.new(outputHolder)
	self.input = Input.new(inputHolder)

	self.themed.Background = window
	self.themed.Surface = titleBar
	self.themed.Accent = title
	self.themed.Border = { stroke, separator }

	self:wireSubmit()

	-- Optional dragging by the title bar (Window placement only - docked bars stay put).
	if options.Draggable and (options.Placement or "Window") == "Window" then
		self:enableDrag(titleBar, window)
	end
end

function Terminal:enableDrag(handle: Instance, window: Instance)
	local dragging, dragStart, startPos = false, Vector3.zero, UDim2.new()
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = window.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			window.Position =
				UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- ---------------------------------------------------------------------------
-- compact single-line bar
-- ---------------------------------------------------------------------------

function Terminal:buildCompact(options)
	local resultLabel = create("TextLabel", {
		Name = "Result",
		BackgroundTransparency = 1,
		Visible = false,
		Size = UDim2.new(1, -16, 0, RESULT_H - 2),
		Position = UDim2.new(0, 8, 0, 4),
		Font = Enum.Font.Code,
		TextSize = 14,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}) :: TextLabel

	local inputHolder = create("Frame", {
		Name = "InputHolder",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, BAR_H - 4),
		Position = UDim2.new(0, 0, 1, -(BAR_H - 4)),
	})

	local stroke = create("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local scale = create("UIScale", { Scale = 1 })

	local window = create("Frame", {
		Name = "Window",
		AnchorPoint = self.placement.Anchor,
		Position = options.Position or self.placement.Position,
		Size = options.Size or self.placement.Size,
		BorderSizePixel = 0,
		Visible = false,
		Children = { create("UICorner", { CornerRadius = UDim.new(0, 8) }), scale, stroke, resultLabel, inputHolder },
	})
	self.scaleObj = scale

	self.gui = makeGui(window)
	self.window = window
	self.resultLabel = resultLabel
	self.input = Input.new(inputHolder)

	self.themed.Background = window
	self.themed.Border = { stroke }

	self:wireSubmit()
end

-- Compact: show the latest line and grow the bar by one row; collapse on clear.
function Terminal:setResult(group: string, text: string)
	local label = self.resultLabel
	label.Text = text
	if self.palette then
		label.TextColor3 = self.palette[group] or self.palette.Output
	end
	label.Visible = true
	local w = self.placement.Size
	self.window.Size = UDim2.new(w.Width.Scale, w.Width.Offset, 0, BAR_H + RESULT_H)
end

-- ---------------------------------------------------------------------------
-- shared
-- ---------------------------------------------------------------------------

function Terminal:wireSubmit()
	self.input:onSubmit(function(line)
		if not self.compact then
			self.output:append(`› {line}`, "Comment")
		end
		-- a pending prompt (eg the dangerous-command y/N gate) swallows the next line as its
		-- answer instead of running it as a command
		if self.pendingPrompt then
			local resolve = self.pendingPrompt
			self.pendingPrompt = nil
			resolve(line)
			return
		end
		if self.submitHandler then
			self.submitHandler(line)
		end
	end)
end

-- Ask a yes/no question on the terminal and yield until the next line is submitted. Returns
-- true for y/yes (anything else is no). Used by the dangerous-command gate in "text" mode.
function Terminal:promptText(question: string): boolean
	self:emit("Warn", `{question}  [y/N]`)
	local thread = coroutine.running()
	self.pendingPrompt = function(line: string)
		local a = string.lower((string.gsub(line, "%s", "")))
		task.spawn(thread, a == "y" or a == "yes")
	end
	-- make sure the box has focus so the answer can be typed
	task.defer(function()
		self.input:focus()
	end)
	return coroutine.yield()
end

-- ---------------------------------------------------------------------------
-- modal confirm (the "window" prompt) - a small themed dialog, built once and reused
-- ---------------------------------------------------------------------------

function Terminal:buildPromptModal()
	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.new(0, 14, 0, 12),
		Font = Enum.Font.Code,
		TextSize = 15,
		Text = "⚠  confirm",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}) :: TextLabel
	local message = create("TextLabel", {
		Name = "Message",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 0, 44),
		Position = UDim2.new(0, 14, 0, 38),
		Font = Enum.Font.Code,
		TextSize = 14,
		Text = "",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}) :: TextLabel

	local function button(name: string, text: string, x: number)
		return create("TextButton", {
			Name = name,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 1),
			Size = UDim2.new(0, 92, 0, 28),
			Position = UDim2.new(1, x, 1, -12),
			Font = Enum.Font.Code,
			TextSize = 14,
			Text = text,
			Children = { create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
		}) :: TextButton
	end
	local noBtn = button("No", "cancel", -14)
	local yesBtn = button("Yes", "run", -114)

	local cardStroke = create("UIStroke", { Thickness = 1 })
	local card = create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(360, 150),
		BorderSizePixel = 0,
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 10) }),
			cardStroke,
			title,
			message,
			yesBtn,
			noBtn,
		},
	})
	local overlay = create("Frame", {
		Name = "PromptOverlay",
		Visible = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 100,
		Children = { card },
		Parent = self.window,
	})

	self.promptModal = {
		overlay = overlay,
		card = card,
		cardStroke = cardStroke,
		title = title,
		message = message,
		yes = yesBtn,
		no = noBtn,
	}

	yesBtn.MouseButton1Click:Connect(function()
		if self.promptResolve then
			self.promptResolve(true)
		end
	end)
	noBtn.MouseButton1Click:Connect(function()
		if self.promptResolve then
			self.promptResolve(false)
		end
	end)

	self:colorPromptModal()
end

function Terminal:colorPromptModal()
	local m = self.promptModal
	if not m or not self.palette then
		return
	end
	local p = self.palette
	m.card.BackgroundColor3 = p.Surface
	m.cardStroke.Color = p.Border
	m.title.TextColor3 = p.Warn
	m.message.TextColor3 = p.Foreground
	m.yes.BackgroundColor3 = p.Error
	m.yes.TextColor3 = p.Background
	m.no.BackgroundColor3 = p.Background
	m.no.TextColor3 = p.Foreground
end

-- Show the modal confirm and yield until a button is clicked. Returns true on "run".
function Terminal:promptWindow(question: string): boolean
	if not self.promptModal then
		self:buildPromptModal()
	end
	self:colorPromptModal()
	self.promptModal.message.Text = question
	self.promptModal.overlay.Visible = true
	-- drop focus so stray typing can't run a command behind the modal
	self.input:blur()
	local thread = coroutine.running()
	self.promptResolve = function(v: boolean)
		self.promptResolve = nil
		self.promptModal.overlay.Visible = false
		task.defer(function()
			self.input:focus()
		end)
		task.spawn(thread, v == true)
	end
	return coroutine.yield()
end

-- Spin up an indicator (progress bar / spinner / ...) on its own live output line. Compact
-- bars have no scrolling log, so they get a no-op with the same shape.
function Terminal:indicator(opts: { [string]: any }?): any
	if self.compact or not self.output then
		return Indicators.noop()
	end
	local line = self.output:appendLive((opts and opts.group) or "Output")
	return Indicators.new(line, opts)
end

-- Print a pre-built RichText block (a Render.* result). Multi-line, non-wrapped.
function Terminal:printRich(richText: string, group: string?)
	if self.compact or not self.output then
		return
	end
	self.output:appendRich(richText, group or "Output")
end

-- The ctx.UI surface, bound to this terminal: each method builds a Render block and prints
-- it. The pure builders (badge/color/sparkline) are returned too, so handlers can compose
-- them into a Markup line.
function Terminal:ui(): { [string]: any }
	local t = self
	local function printer(builder)
		return function(...)
			t:printRich(builder(...), "Output")
		end
	end
	return {
		available = true, -- lets commands branch: rich table on the terminal, plain text off it
		Markup = function(rich: string, group: string?)
			t:printRich(rich, group)
		end,
		Rule = printer(Render.rule),
		Panel = printer(Render.panel),
		Table = printer(Render.table),
		Tree = printer(Render.tree),
		Fields = printer(Render.fields),
		List = printer(Render.list),
		BarChart = printer(Render.barchart),
		Columns = printer(Render.columns),
		Chart = printer(Render.sparkline), -- prints a sparkline on its own line
		-- pure helpers (return a string to drop into Markup / table cells)
		Badge = Render.badge,
		Color = Render.color,
		Sparkline = Render.sparkline,
		Render = Render, -- the whole pure builder module, for composing blocks
	}
end

-- One sink for all output, branching on presentation.
function Terminal:emit(group: string, text: string)
	if self.compact then
		self:setResult(group, text)
	else
		self.output:append(text, group)
	end
end

function Terminal:mount(target: Instance?)
	local parent = target or self.options.Parent
	if not parent and RunService:IsClient() then
		-- wait so we don't run before the player/gui exists
		local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
		parent = player:WaitForChild("PlayerGui")
	end
	if parent then
		self.gui.Parent = parent
	else
		warn("karet: no parent and no playergui to mount into")
	end
	return self
end

function Terminal:applyTheme(palette: { [string]: Color3 })
	self.palette = palette
	self.window.BackgroundColor3 = palette.Background
	-- border stuff is either a stroke or a thin frame
	for _, inst in self.themed.Border do
		if inst:IsA("UIStroke") then
			inst.Color = palette.Border
		else
			inst.BackgroundColor3 = palette.Border
		end
	end
	if self.compact then
		self.resultLabel.TextColor3 = palette.Foreground
	else
		self.themed.Surface.BackgroundColor3 = palette.Surface
		self.themed.Accent.TextColor3 = palette.Accent
		self.output:applyTheme(palette)
	end
	self.input:applyTheme(palette)
	self:colorPromptModal()
end

-- Move the window to a named placement live (config editor uses this). Full window only.
function Terminal:setPlacement(name: string): boolean
	local set = self.compact and COMPACT_PLACEMENTS or PLACEMENTS
	local pl = set[name]
	if not pl then
		return false
	end
	self.placement = pl
	self.window.AnchorPoint = pl.Anchor
	self.window.Position = pl.Position
	self.window.Size = pl.Size
	return true
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
	Capture.acquire("terminal")
	if self.switch then
		self.switch.PushContext(OPEN_CONTEXT)
	end
	self.input.keepFocus = true
	self.input:focus()
end

function Terminal:close()
	if not self.isOpen then
		return
	end
	self.isOpen = false
	self.input.keepFocus = false
	self.input:blur()
	self.window.Visible = false
	Capture.release("terminal")
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

-- Parse a toggle spec into (keyName, modifierName?). Accepts:
--   "Semicolon"                            -> a single key
--   "LeftControl+Semicolon"                -> a shortcut (modifier + key)
--   { Key = "Semicolon", Modifier = "..." } -> the explicit table form
local function parseToggle(toggle: any): (string?, string?)
	if type(toggle) == "table" then
		return toggle.Key, toggle.Modifier
	end
	local s = tostring(toggle)
	local mod, key = string.match(s, "^(%w+)%+(%w+)$")
	if mod then
		return key, mod
	end
	return s, nil
end

-- Wire the toggle/close actions through Switch. `toggle` is a KeyCode name ("Semicolon"),
-- a shortcut ("LeftControl+Semicolon" or { Key=..., Modifier=... }). Client-only; degrades
-- to a no-op with a warning if Switch is unavailable. The toggle is a single global action
-- driven off self.isOpen (so it never desyncs from a programmatic open/close). A plain
-- (modifier-less) global toggle key can't also be typed into a command while open - either
-- pick a key you wouldn't type, or use a modifier shortcut. Escape closes.
function Terminal:enableSwitch(toggle: any)
	if not RunService:IsClient() then
		warn("Karet.Terminal:enableSwitch - Switch is client-only; ignoring on the server")
		return
	end
	local Switch = deps.Switch()
	if not Switch then
		return
	end

	local keyName, modName = parseToggle(toggle)
	local keyCode = keyName and (Enum.KeyCode :: any)[keyName]
	if not keyCode then
		warn(`Karet.Terminal:enableSwitch - '{tostring(keyName)}' is not a valid KeyCode name`)
		return
	end
	local modCode = modName and (Enum.KeyCode :: any)[modName] or nil
	if modName and not modCode then
		warn(`Karet.Terminal:enableSwitch - '{modName}' is not a valid modifier KeyCode`)
		return
	end

	self.switch = Switch
	local Enums = Switch.Enums

	local function action(name: string, config: { [string]: any }, handler: (any) -> ())
		config.Sink = true
		local handle = Switch.Define(name, config)
		handle:Next(Enums.State.Pressed):Then(handler)
		table.insert(self.actions, name)
	end

	-- Toggle: a Shortcut (modifier+key) if a modifier was given, else a plain key. Global.
	local toggleConfig
	if modCode then
		toggleConfig = { Bindings = { { KeyCode = keyCode, Modifier = modCode } }, Mode = Enums.Mode.Shortcut }
	else
		toggleConfig = { Bindings = { keyCode } }
	end
	action("KaretToggle", toggleConfig, function(event)
		-- let shift+key (eg : in kaveat) through instead of toggling
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
			return
		end
		event:Consume()
		self:toggle()
	end)

	-- Escape closes. (Up/Down history is handled in Input via UserInputService, since arrow
	-- actions don't fire reliably through Switch while the TextBox holds focus.)
	action("KaretClose", { Bindings = { Enum.KeyCode.Escape }, Contexts = { OPEN_CONTEXT } }, function(event)
		event:Consume()
		self:close()
	end)
end

-- ---------------------------------------------------------------------------
-- output API
-- ---------------------------------------------------------------------------

function Terminal:print(text: string, group: string?)
	self:emit(group or "Output", text)
end

function Terminal:error(text: string)
	self:emit("Error", text)
end

function Terminal:warn(text: string)
	self:emit("Warn", text)
end

function Terminal:info(text: string)
	self:emit("Info", text)
end

function Terminal:success(text: string)
	self:emit("Success", text)
end

function Terminal:clear()
	if self.compact then
		self.resultLabel.Visible = false
		self.resultLabel.Text = ""
		self.window.Size = self.placement.Size
	else
		self.output:clear()
	end
end

-- Register the handler that runs a submitted line (after it is echoed, in full mode).
function Terminal:onSubmit(fn: (string) -> ())
	self.submitHandler = fn
end

function Terminal:destroy()
	if self.unsubscribeTheme then
		self.unsubscribeTheme()
	end
	if self.zoomConn then
		self.zoomConn:Disconnect()
	end
	if self.switch then
		for _, name in self.actions do
			self.switch.Remove(name)
		end
		self.switch.PopContext(OPEN_CONTEXT)
	end
	if self.output then
		self.output:destroy()
	end
	self.input:destroy()
	self.gui:Destroy()
end

return Terminal
