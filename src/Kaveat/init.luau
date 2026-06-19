-- Kaveat - Karet's built-in Luau script editor (the Neovim + neo-tree analogue).
--
-- STATUS: scaffold. This stands up the editor *surface* - a themed window with a
-- line-numbered multi-line code box, a per-buffer Context (Client/Server), and a Run seam -
-- so the rest can be layered on. Still TODO (large, some with open design questions):
--   • Luau syntax highlighting + autocomplete against the live DataModel
--   • a buffer/file tree (the neo-tree side)
--   • execution: source is compiled on the SERVER via loadstring (the single gatekeeper),
--     which enforces the buffer's declared Context. Client-context *execution* (the client
--     can't loadstring) is an open decision in DESIGN - so :setRunner() is a seam the host
--     wires once that story lands; the default runner just reports it isn't wired yet.
--
-- Kaveat reuses the Terminal's create() helper and the shared Theme.

local Theme = require(script.Parent.Theme)
local create = require(script.Parent.Terminal.create)

local Kaveat = {}
Kaveat.__index = Kaveat

local FONT = Enum.Font.Code
local TEXT_SIZE = 15

export type Buffer = {
	name: string,
	context: string, -- "Client" | "Server"
	source: string,
}

-- opts: { Parent = Instance?, Context = "Client"|"Server"? }
function Kaveat.new(opts: { [string]: any }?)
	local self = setmetatable({}, Kaveat)
	local options = opts or {}

	self.options = options
	self.isOpen = false
	self.themed = {} :: { [string]: any }
	self.runner = nil :: ((source: string, context: string) -> any)?
	self.buffer = { name = "untitled.luau", context = options.Context or "Client", source = "" } :: Buffer

	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -120, 1, 0),
		Position = UDim2.new(0, 10, 0, 0),
		Font = FONT,
		TextSize = 13,
		Text = self.buffer.name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}) :: TextLabel

	local contextLabel = create("TextLabel", {
		Name = "Context",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 110, 1, 0),
		Position = UDim2.new(1, -116, 0, 0),
		Font = FONT,
		TextSize = 13,
		Text = self.buffer.context .. "  ·  F5 run",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
	}) :: TextLabel

	local header = create("Frame", {
		Name = "Header",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 26),
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			title,
			contextLabel,
		},
	})

	local gutter = create("TextLabel", {
		Name = "Gutter",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 40, 1, -52),
		Position = UDim2.new(0, 0, 0, 28),
		Font = FONT,
		TextSize = TEXT_SIZE,
		Text = "1",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
	}) :: TextLabel

	local editor = create("TextBox", {
		Name = "Editor",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -48, 1, -52),
		Position = UDim2.new(0, 46, 0, 28),
		Font = FONT,
		TextSize = TEXT_SIZE,
		Text = "",
		PlaceholderText = "-- Luau here",
		MultiLine = true,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = false,
	}) :: TextBox

	local status = create("TextLabel", {
		Name = "Status",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -22),
		Font = FONT,
		TextSize = 12,
		Text = "ready",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Children = { create("UIPadding", { PaddingLeft = UDim.new(0, 8) }) },
	}) :: TextLabel

	local stroke = create("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })

	local window = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(720, 460),
		BorderSizePixel = 0,
		Visible = false,
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			stroke,
			header,
			gutter,
			editor,
			status,
		},
	})

	local gui = create("ScreenGui", {
		Name = "KaretKaveat",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 11,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Children = { window },
	})

	self.gui = gui
	self.window = window
	self.editor = editor
	self.gutter = gutter
	self.title = title
	self.contextLabel = contextLabel
	self.status = status

	self.themed.Background = window
	self.themed.Surface = { header, status }
	self.themed.Accent = title
	self.themed.Muted = { gutter, contextLabel }
	self.themed.Foreground = editor
	self.themed.Border = stroke

	-- Keep the line-number gutter in sync, and mirror text into the buffer.
	editor:GetPropertyChangedSignal("Text"):Connect(function()
		self.buffer.source = editor.Text
		self:refreshGutter()
	end)

	self.unsubscribeTheme = Theme.OnChanged(function(palette)
		self:applyTheme(palette)
	end)

	return self
end

function Kaveat:refreshGutter()
	local lines = select(2, string.gsub(self.editor.Text, "\n", "\n")) + 1
	local numbers = table.create(lines)
	for i = 1, lines do
		numbers[i] = tostring(i)
	end
	self.gutter.Text = table.concat(numbers, "\n")
end

function Kaveat:applyTheme(palette: { [string]: Color3 })
	self.window.BackgroundColor3 = palette.Background
	for _, inst in self.themed.Surface do
		inst.BackgroundColor3 = palette.Surface
	end
	self.title.TextColor3 = palette.Accent
	for _, inst in self.themed.Muted do
		inst.TextColor3 = palette.Muted
	end
	self.editor.TextColor3 = palette.Foreground
	self.editor.PlaceholderColor3 = palette.Muted
	self.status.TextColor3 = palette.Muted
	self.themed.Border.Color = palette.Border
end

function Kaveat:mount(target: Instance?)
	local parent = target or self.options.Parent
	if parent then
		self.gui.Parent = parent
	end
	return self
end

-- The buffer's realm. Drives which APIs are allowed once execution + sandboxing land.
function Kaveat:setContext(context: string)
	self.buffer.context = context
	self.contextLabel.Text = context .. "  ·  F5 run"
end

function Kaveat:setSource(source: string)
	self.editor.Text = source
end

function Kaveat:getSource(): string
	return self.editor.Text
end

-- Host wires the real executor here: runner(source, context) -> result. Until then the
-- default below reports that execution isn't wired (server loadstring is the next step).
function Kaveat:setRunner(runner: (source: string, context: string) -> any)
	self.runner = runner
end

function Kaveat:run()
	if not self.runner then
		self.status.Text = "execution not wired yet (server loadstring pending)"
		return
	end
	self.status.Text = "running..."
	local ok, result = pcall(self.runner, self.buffer.source, self.buffer.context)
	self.status.Text = ok and ("ok: " .. tostring(result)) or ("error: " .. tostring(result))
end

function Kaveat:open()
	self.isOpen = true
	self.window.Visible = true
	self.editor:CaptureFocus()
end

function Kaveat:close()
	self.isOpen = false
	self.editor:ReleaseFocus()
	self.window.Visible = false
end

function Kaveat:toggle()
	if self.isOpen then
		self:close()
	else
		self:open()
	end
end

function Kaveat:destroy()
	if self.unsubscribeTheme then
		self.unsubscribeTheme()
	end
	self.gui:Destroy()
end

return Kaveat
