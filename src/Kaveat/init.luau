-- Kaveat - Karet's built-in Luau editor, rendered with Iris (immediate-mode), themed from
-- the Karet palette so it reads custom rather than default-Iris.
--
-- Iris model: Iris.Init() once, then Iris:Connect(renderFn) runs renderFn every frame. We
-- bind widgets straight to our buffer via Iris.TableState, so editing the InputText writes
-- back to self.buffer.source and the window's close (X) flows into self.isOpen.
--
-- STATUS: the editor surface (window, toolbar, multi-line code box, status) is on Iris.
-- Still TODO (large / open design): Luau syntax highlighting + autocomplete vs the live
-- DataModel, a buffer/file tree, and EXECUTION - source is meant to compile on the SERVER
-- via loadstring (the single gatekeeper enforcing the buffer's Context); client-context
-- execution is an open DESIGN decision, so :setRunner() is the seam the host wires later.

local Theme = require(script.Parent.Theme)
local deps = require(script.Parent.deps)

local Kaveat = {}
Kaveat.__index = Kaveat

export type Buffer = { name: string, context: string, source: string }

-- Iris widget arg indices (avoids relying on Iris.Args being populated):
--   Window.NoCollapse = 4 ; InputText.TextHint = 2, InputText.MultiLine = 4
local WINDOW_NOCOLLAPSE = 4
local INPUT_TEXTHINT = 2
local INPUT_MULTILINE = 4

-- Map the active Karet palette onto Iris's global config.
local function irisConfig(p: { [string]: Color3 })
	return {
		WindowBgColor = p.Background,
		WindowBgTransparency = 0,
		ChildBgColor = p.Background,
		ChildBgTransparency = 0,
		PopupBgColor = p.Surface,
		PopupBgTransparency = 0,
		TitleBgColor = p.Surface,
		TitleBgTransparency = 0,
		TitleBgActiveColor = p.Surface,
		TitleBgActiveTransparency = 0,
		TitleBgCollapsedColor = p.Surface,
		TitleBgCollapsedTransparency = 0.25,
		MenubarBgColor = p.Surface,
		MenubarBgTransparency = 0,
		TextColor = p.Foreground,
		TextTransparency = 0,
		TextDisabledColor = p.Muted,
		TextDisabledTransparency = 0,
		BorderColor = p.Border,
		BorderTransparency = 0.35,
		BorderActiveColor = p.Accent,
		BorderActiveTransparency = 0,
		FrameBgColor = p.Surface,
		FrameBgTransparency = 0,
		FrameBgHoveredColor = p.Surface,
		FrameBgHoveredTransparency = 0,
		FrameBgActiveColor = p.Surface,
		FrameBgActiveTransparency = 0,
		ButtonColor = p.Accent,
		ButtonTransparency = 0.15,
		ButtonHoveredColor = p.Accent,
		ButtonHoveredTransparency = 0,
		ButtonActiveColor = p.AccentAlt or p.Accent,
		ButtonActiveTransparency = 0,
		HeaderColor = p.Accent,
		HeaderTransparency = 0.35,
		HeaderHoveredColor = p.Accent,
		HeaderHoveredTransparency = 0.15,
		HeaderActiveColor = p.Accent,
		HeaderActiveTransparency = 0,
		ScrollbarGrabColor = p.Muted,
		ScrollbarGrabTransparency = 0,
		SeparatorColor = p.Border,
		SeparatorTransparency = 0.3,
		WindowRounding = 8,
		FrameRounding = 6,
		PopupRounding = 6,
		GrabRounding = 6,
		TextFont = Font.fromEnum(Enum.Font.Code),
		TextSize = 14,
	}
end

-- opts: { Parent = Instance?, Context = "Client"|"Server"? }
function Kaveat.new(opts: { [string]: any }?)
	local self = setmetatable({}, Kaveat)
	local options = opts or {}
	self.options = options
	self.buffer = { name = "untitled.luau", context = options.Context or "Client", source = "" } :: Buffer
	self.isOpen = false
	self.status = "ready"
	self.runner = nil :: ((source: string, context: string) -> any)?

	local Iris = deps.Iris()
	if not Iris then
		warn("Karet.Kaveat: Iris not found (vendored under the Karet module?); editor disabled")
		self.isStub = true
		return self
	end
	self.iris = Iris
	Iris.Init(options.Parent, nil, true)

	-- Theme -> Iris config now and on every theme change.
	self.unsubscribeTheme = Theme.OnChanged(function(palette)
		Iris.UpdateGlobalConfig(irisConfig(palette))
	end)

	self.disconnect = Iris:Connect(function()
		self:render()
	end)

	return self
end

function Kaveat:render()
	local Iris = self.iris
	-- Bind window open-state and source text straight to our fields.
	local openState = Iris.TableState(self, "isOpen")
	local sourceState = Iris.TableState(self.buffer, "source")
	local sizeState = Iris.State(Vector2.new(640, 420))
	local posState = Iris.State(Vector2.new(120, 120))

	Iris.Window(
		{ `Kaveat - {self.buffer.name}`, [WINDOW_NOCOLLAPSE] = true },
		{ isOpened = openState, size = sizeState, position = posState }
	)
	Iris.SameLine()
	if Iris.Button({ "Run" }).clicked() then
		self:run()
	end
	if Iris.Button({ "Clear" }).clicked() then
		self.buffer.source = ""
	end
	if Iris.Button({ `Context: {self.buffer.context}` }).clicked() then
		self.buffer.context = self.buffer.context == "Client" and "Server" or "Client"
	end
	Iris.End()

	Iris.Separator()
	Iris.InputText({ [INPUT_TEXTHINT] = "-- Luau here", [INPUT_MULTILINE] = true }, { text = sourceState })
	Iris.Separator()
	Iris.Text({ self.status })
	Iris.End()
end

-- Iris manages its own ScreenGui (parented in Init); mount is kept for API symmetry.
function Kaveat:mount(_target: Instance?)
	return self
end

function Kaveat:open()
	self.isOpen = true
end

function Kaveat:close()
	self.isOpen = false
end

function Kaveat:toggle()
	self.isOpen = not self.isOpen
end

function Kaveat:setContext(context: string)
	self.buffer.context = context
end

function Kaveat:setSource(source: string)
	self.buffer.source = source
end

function Kaveat:getSource(): string
	return self.buffer.source
end

-- Host wires the real executor here: runner(source, context) -> result.
function Kaveat:setRunner(runner: (source: string, context: string) -> any)
	self.runner = runner
end

function Kaveat:run()
	if not self.runner then
		self.status = "execution not wired yet (server loadstring pending)"
		return
	end
	self.status = "running..."
	local ok, result = pcall(self.runner, self.buffer.source, self.buffer.context)
	self.status = ok and ("ok: " .. tostring(result)) or ("error: " .. tostring(result))
end

function Kaveat:destroy()
	if self.disconnect then
		self.disconnect()
	end
	if self.unsubscribeTheme then
		self.unsubscribeTheme()
	end
end

return Kaveat
