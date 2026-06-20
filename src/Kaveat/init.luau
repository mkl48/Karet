-- Kaveat, the script editor. custom ui, feels like neovim: a topbar, a kavs file tree,
-- tabs, the editor, an output pane and a modeline, all resizable, plus a draggable window.
-- two modes like nvim: READ and WRITE. click or press i to write, esc to read. : opens a
-- cmdline (READ mode). ctrl+enter runs. files live in the profile (Profile.Kavs).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local create = require(script.Parent.Terminal.create)

local Kaveat = {}
Kaveat.__index = Kaveat

local FONT = Enum.Font.Code
local SIZE = 14
local TOP_H = 26
local TREE_W = 190
local OUT_H = 130
local TAB_H = 26
local MODE_H = 22

export type Buffer = { name: string, context: string, source: string, dirty: boolean }

function Kaveat.new(opts: { [string]: any }?)
	local self = setmetatable({}, Kaveat)
	local options = opts or {}
	self.options = options

	self.buffers = {} :: { Buffer }
	self.active = 0
	self.mode = "READ"
	self.isOpen = false
	self.store = nil :: (() -> { [string]: string })?
	self.runner = nil :: any
	self.themed = {}
	self.treeW = TREE_W
	self.outH = OUT_H
	self.outLines = {}
	self._setting = false

	self:build(options)

	self.unsubscribeTheme = Theme.OnChanged(function(palette)
		self:applyTheme(palette)
	end)
	self.inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		self:onKey(input, processed)
	end)

	return self
end

function Kaveat:build(options)
	local stroke = create("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })

	-- topbar: title + dirty marker + exit, also the drag handle
	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -70, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		Font = FONT,
		TextSize = 13,
		Text = "Kaveat",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	local exit = create("TextButton", {
		Name = "Exit",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 28, 1, 0),
		Position = UDim2.new(1, -28, 0, 0),
		Font = FONT,
		TextSize = 16,
		Text = "x",
	})
	local topbar = create("Frame", {
		Name = "TopBar",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, TOP_H),
		Children = { create("UICorner", { CornerRadius = UDim.new(0, 8) }), title, exit },
	})

	-- tree
	local treeTitle = create("TextLabel", {
		Name = "TreeTitle",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 20),
		Position = UDim2.new(0, 8, 0, 0),
		Font = FONT,
		TextSize = 12,
		Text = "kavs",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local treeScroll = create("ScrollingFrame", {
		Name = "TreeList",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -22),
		Position = UDim2.new(0, 0, 0, 22),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Children = {
			create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }),
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 2) }),
		},
	})
	local tree = create("Frame", {
		Name = "Tree",
		BorderSizePixel = 0,
		Size = UDim2.new(0, self.treeW, 1, -(TOP_H + MODE_H)),
		Position = UDim2.new(0, 0, 0, TOP_H),
		Children = { treeTitle, treeScroll },
	})
	local treeDrag = create("TextButton", {
		Name = "TreeSplit",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, -(TOP_H + MODE_H)),
		Position = UDim2.new(0, self.treeW, 0, TOP_H),
	})

	-- tabs
	local tabBar = create("Frame", {
		Name = "Tabs",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, TAB_H),
		Children = { create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 1),
		}) },
	})

	-- editor
	local gutter = create("TextLabel", {
		Name = "Gutter",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 38, 1, 0),
		Font = FONT,
		TextSize = SIZE,
		Text = "1",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local box = create("TextBox", {
		Name = "Editor",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -46, 1, 0),
		Position = UDim2.new(0, 44, 0, 0),
		Font = FONT,
		TextSize = SIZE,
		Text = "",
		PlaceholderText = "",
		MultiLine = true,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ClipsDescendants = true,
	})
	local editor = create("Frame", {
		Name = "EditorArea",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -(TAB_H + self.outH)),
		Position = UDim2.new(0, 0, 0, TAB_H),
		Children = { gutter, box },
	})

	local outDrag = create("TextButton", {
		Name = "OutSplit",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 3),
		Position = UDim2.new(0, 0, 1, -self.outH - 3),
	})
	local output = create("ScrollingFrame", {
		Name = "Output",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, self.outH),
		Position = UDim2.new(0, 0, 1, -self.outH),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Children = {
			create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 4) }),
		},
	})

	local right = create("Frame", {
		Name = "Right",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(self.treeW + 3), 1, -(TOP_H + MODE_H)),
		Position = UDim2.new(0, self.treeW + 3, 0, TOP_H),
		Children = { tabBar, editor, outDrag, output },
	})

	-- modeline: a coloured mode chip + context + file
	local modeChip = create("TextLabel", {
		Name = "ModeChip",
		BorderSizePixel = 0,
		Size = UDim2.new(0, 70, 1, -4),
		Position = UDim2.new(0, 4, 0, 2),
		Font = FONT,
		TextSize = 12,
		Text = "READ",
		TextColor3 = Color3.new(0, 0, 0),
		Children = { create("UICorner", { CornerRadius = UDim.new(0, 4) }) },
	})
	local ctxLabel = create("TextLabel", {
		Name = "Ctx",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 90, 1, 0),
		Position = UDim2.new(0, 82, 0, 0),
		Font = FONT,
		TextSize = 12,
		Text = "Client",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	local fileLabel = create("TextLabel", {
		Name = "File",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -190, 1, 0),
		Position = UDim2.new(0, 180, 0, 0),
		Font = FONT,
		TextSize = 12,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	local modeline = create("Frame", {
		Name = "Modeline",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, MODE_H),
		Position = UDim2.new(0, 0, 1, -MODE_H),
		Children = { modeChip, ctxLabel, fileLabel },
	})

	-- cmdline, hidden until :
	local cmdBox = create("TextBox", {
		Name = "Cmd",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		Font = FONT,
		TextSize = 13,
		Text = "",
		PlaceholderText = ":w  :q  :e <file>  :server  :client  :run  :ls",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local cmdline = create("Frame", {
		Name = "Cmdline",
		Visible = false,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, MODE_H),
		Position = UDim2.new(0, 0, 1, -MODE_H),
		ZIndex = 5,
		Children = { create("UIStroke", { Thickness = 1 }), cmdBox },
	})

	-- resize grip, bottom right corner
	local grip = create("TextButton", {
		Name = "Grip",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 14, 0, 14),
		Position = UDim2.new(1, -14, 1, -14),
		ZIndex = 6,
	})

	local window = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(900, 560),
		BorderSizePixel = 0,
		Visible = false,
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			stroke,
			topbar,
			tree,
			treeDrag,
			right,
			modeline,
			cmdline,
			grip,
		},
	})
	local gui = create("ScreenGui", {
		Name = "KaretKaveat",
		ResetOnSpawn = false,
		DisplayOrder = 11,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Children = { window },
	})

	self.gui, self.window = gui, window
	self.tree, self.treeScroll = tree, treeScroll
	self.tabBar, self.gutter, self.box, self.editor = tabBar, gutter, box, editor
	self.output, self.modeline = output, modeline
	self.modeChip, self.ctxLabel, self.fileLabel, self.title = modeChip, ctxLabel, fileLabel, title
	self.cmdline, self.cmdBox, self.treeDrag, self.outDrag = cmdline, cmdBox, treeDrag, outDrag

	self.themed.bg = { window, tree, tabBar, output }
	self.themed.surface = { topbar, modeline, cmdline }
	self.themed.fg = { box }
	self.themed.muted = { gutter, treeTitle, ctxLabel, fileLabel }
	self.themed.accent = { title }
	self.themed.border = { stroke, treeDrag, outDrag }

	box.Focused:Connect(function()
		self.mode = "WRITE"
		self:refreshMode()
	end)
	box.FocusLost:Connect(function()
		self.mode = "READ"
		self:refreshMode()
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local buf = self.buffers[self.active]
		if buf then
			buf.source = box.Text
			if not self._setting then
				buf.dirty = true
				self:refreshTitle()
			end
		end
		self:refreshGutter()
	end)

	exit.MouseButton1Click:Connect(function()
		self:close()
	end)
	self:wireDrag(treeDrag, "tree")
	self:wireDrag(outDrag, "out")
	self:wireWindow(topbar, grip)

	cmdBox.FocusLost:Connect(function(enter)
		self.cmdline.Visible = false
		local text = cmdBox.Text
		cmdBox.Text = ""
		if enter then
			self:runCmd(text)
		end
	end)
end

function Kaveat:refreshGutter()
	local lines = select(2, string.gsub(self.box.Text, "\n", "\n")) + 1
	local nums = table.create(lines)
	for i = 1, lines do
		nums[i] = tostring(i)
	end
	self.gutter.Text = table.concat(nums, "\n")
end

function Kaveat:refreshMode()
	local p = self.palette
	local write = self.mode == "WRITE"
	self.modeChip.Text = write and "WRITE" or "READ"
	if p then
		self.modeChip.BackgroundColor3 = write and (p.Success or p.Accent) or p.Accent
	end
	local buf = self.buffers[self.active]
	self.ctxLabel.Text = buf and buf.context or ""
end

function Kaveat:refreshTitle()
	local buf = self.buffers[self.active]
	if buf then
		self.title.Text = "Kaveat - " .. buf.name .. (buf.dirty and "  [+]" or "")
		self.fileLabel.Text = buf.name .. (buf.dirty and " [+]" or " [saved]")
	else
		self.title.Text = "Kaveat"
		self.fileLabel.Text = ""
	end
end

-- input --------------------------------------------------------------------

function Kaveat:onKey(input: InputObject, processed: boolean)
	if not self.isOpen then
		return
	end
	local key = input.KeyCode
	local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

	if ctrl and key == Enum.KeyCode.Return then
		self:run()
		return
	end

	if self.mode == "WRITE" then
		if key == Enum.KeyCode.Escape then
			self.box:ReleaseFocus()
		end
		return
	end

	-- READ mode, ignore keys eaten by another textbox (eg the cmdline)
	if processed then
		return
	end
	if key == Enum.KeyCode.I then
		self.box:CaptureFocus()
	elseif key == Enum.KeyCode.Semicolon and shift then
		self.cmdline.Visible = true
		self.cmdBox:CaptureFocus()
	end
end

function Kaveat:runCmd(text: string)
	local cmd, arg = string.match(text, "^%s*(%S+)%s*(.-)%s*$")
	cmd = cmd and string.lower(cmd) or ""
	if cmd == "w" or cmd == "write" then
		self:save()
	elseif cmd == "q" or cmd == "quit" then
		self:closeActive()
	elseif cmd == "wq" then
		self:save()
		self:closeActive()
	elseif cmd == "e" or cmd == "edit" or cmd == "new" then
		if arg ~= "" then
			self:openFile(arg)
		else
			self:print("usage: :e <file>", "Warn")
		end
	elseif cmd == "run" then
		self:run()
	elseif cmd == "server" then
		self:setContext("Server")
		self:print("context: Server", "Info")
	elseif cmd == "client" then
		self:setContext("Client")
		self:print("context: Client", "Info")
	elseif cmd == "ls" or cmd == "files" then
		self:print("kavs: " .. table.concat(self:listFiles(), ", "), "Info")
	elseif cmd == "x" or cmd == "close" then
		self:close()
	else
		self:print("not an editor command: " .. text, "Error")
	end
end

-- tree + tabs --------------------------------------------------------------

function Kaveat:refreshTree()
	for _, c in self.treeScroll:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local p = self.palette
	for i, name in self:listFiles() do
		local btn = create("TextButton", {
			Name = "File",
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.new(1, -8, 0, 18),
			Font = FONT,
			TextSize = 13,
			Text = name,
			TextColor3 = p and p.Foreground or Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i,
			Parent = self.treeScroll,
		})
		btn.MouseButton1Click:Connect(function()
			self:openFile(name)
		end)
	end
end

function Kaveat:refreshTabs()
	for _, c in self.tabBar:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local p = self.palette
	for i, buf in self.buffers do
		local on = i == self.active
		local tab = create("TextButton", {
			Name = "Tab",
			AutoButtonColor = false,
			BackgroundColor3 = p and (on and p.Background or p.Surface) or Color3.new(),
			BorderSizePixel = 0,
			Size = UDim2.new(0, 120, 1, 0),
			Font = FONT,
			TextSize = 12,
			Text = buf.name .. (buf.dirty and " +" or ""),
			TextColor3 = p and (on and p.Accent or p.Muted) or Color3.new(1, 1, 1),
			LayoutOrder = i,
			Parent = self.tabBar,
		})
		tab.MouseButton1Click:Connect(function()
			self.active = i
			self:showActive()
		end)
	end
end

function Kaveat:showActive()
	local buf = self.buffers[self.active]
	if not buf then
		return
	end
	self._setting = true
	self.box.Text = buf.source
	self._setting = false
	self:refreshGutter()
	self:refreshTabs()
	self:refreshTitle()
	self:refreshMode()
end

-- output -------------------------------------------------------------------

function Kaveat:print(text: string, group: string?)
	local label = create("TextLabel", {
		Name = "Line",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		TextSize = 13,
		Text = text,
		TextColor3 = (self.palette and self.palette[group or "Output"]) or Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = #self.outLines + 1,
		Parent = self.output,
	})
	table.insert(self.outLines, label)
end

-- files --------------------------------------------------------------------

function Kaveat:setStore(get: () -> { [string]: string })
	self.store = get
end

function Kaveat:listFiles(): { string }
	local kavs = (self.store and self.store()) or {}
	local names = {}
	for n in kavs do
		table.insert(names, n)
	end
	table.sort(names)
	return names
end

function Kaveat:openFile(name: string)
	for i, buf in self.buffers do
		if buf.name == name then
			self.active = i
			self:open()
			self:showActive()
			return
		end
	end
	local kavs = self.store and self.store()
	table.insert(self.buffers, {
		name = name,
		context = "Client",
		source = (kavs and kavs[name]) or "",
		dirty = false,
	})
	self.active = #self.buffers
	self:open()
	self:showActive()
	self:refreshTree()
end

function Kaveat:save()
	local buf = self.buffers[self.active]
	local kavs = self.store and self.store()
	if not (buf and kavs) then
		self:print("nothing to save", "Warn")
		return
	end
	kavs[buf.name] = buf.source
	buf.dirty = false
	self:print("saved " .. buf.name, "Success")
	self:refreshTitle()
	self:refreshTabs()
	self:refreshTree()
end

function Kaveat:closeActive()
	if self.active == 0 then
		return
	end
	table.remove(self.buffers, self.active)
	self.active = math.min(self.active, #self.buffers)
	if self.active == 0 then
		self._setting = true
		self.box.Text = ""
		self._setting = false
		self:refreshTabs()
		self:refreshTitle()
	else
		self:showActive()
	end
end

function Kaveat:setContext(context: string)
	local buf = self.buffers[self.active]
	if buf then
		buf.context = context
	end
	self:refreshMode()
end

function Kaveat:getSource(): string
	local buf = self.buffers[self.active]
	return buf and buf.source or ""
end

function Kaveat:setSource(source: string)
	local buf = self.buffers[self.active]
	if buf then
		buf.source = source
		self:showActive()
	end
end

function Kaveat:setRunner(runner: any)
	self.runner = runner
end

function Kaveat:run()
	local buf = self.buffers[self.active]
	if not buf then
		return
	end
	if not self.runner then
		self:print("run isnt wired yet (server loadstring pending)", "Warn")
		return
	end
	local ok, result = pcall(self.runner, buf.source, buf.context)
	self:print(ok and ("ok: " .. tostring(result)) or ("error: " .. tostring(result)), ok and "Output" or "Error")
end

-- drag / resize ------------------------------------------------------------

function Kaveat:wireDrag(handle: TextButton, which: string)
	local dragging = false
	handle.MouseButton1Down:Connect(function()
		dragging = true
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local abs, size = self.window.AbsolutePosition, self.window.AbsoluteSize
		if which == "tree" then
			self.treeW = math.clamp(input.Position.X - abs.X, 120, size.X - 320)
		else
			self.outH = math.clamp(abs.Y + size.Y - input.Position.Y, 60, size.Y - 220)
		end
		self:layout()
	end)
end

function Kaveat:wireWindow(topbar: Instance, grip: TextButton)
	local moving, sizing, start, startPos, startSize = false, false, Vector3.zero, UDim2.new(), Vector2.zero
	topbar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			moving = true
			start = input.Position
			startPos = self.window.Position
		end
	end)
	grip.MouseButton1Down:Connect(function()
		sizing = true
		start = UserInputService:GetMouseLocation()
		startSize = self.window.AbsoluteSize
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			moving, sizing = false, false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		if moving then
			local d = input.Position - start
			self.window.Position =
				UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		elseif sizing then
			local m = UserInputService:GetMouseLocation()
			self.window.Size = UDim2.fromOffset(
				math.max(480, startSize.X + (m.X - start.X)),
				math.max(320, startSize.Y + (m.Y - start.Y))
			)
			self:layout()
		end
	end)
end

function Kaveat:layout()
	self.tree.Size = UDim2.new(0, self.treeW, 1, -(TOP_H + MODE_H))
	self.treeDrag.Position = UDim2.new(0, self.treeW, 0, TOP_H)
	local right = self.window:FindFirstChild("Right")
	if right then
		right.Size = UDim2.new(1, -(self.treeW + 3), 1, -(TOP_H + MODE_H))
		right.Position = UDim2.new(0, self.treeW + 3, 0, TOP_H)
	end
	self.editor.Size = UDim2.new(1, 0, 1, -(TAB_H + self.outH))
	self.outDrag.Position = UDim2.new(0, 0, 1, -self.outH - 3)
	self.output.Size = UDim2.new(1, 0, 0, self.outH)
	self.output.Position = UDim2.new(0, 0, 1, -self.outH)
end

-- lifecycle ----------------------------------------------------------------

function Kaveat:mount(target: Instance?)
	local parent = target or self.options.Parent
	if not parent and RunService:IsClient() then
		local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
		parent = player:WaitForChild("PlayerGui")
	end
	if parent then
		self.gui.Parent = parent
	end
	return self
end

function Kaveat:open()
	self.isOpen = true
	self.window.Visible = true
	self:refreshTree()
	self.mode = "READ"
	self:refreshMode()
	self:refreshTitle()
end

function Kaveat:close()
	self.isOpen = false
	self.window.Visible = false
	self.box:ReleaseFocus()
end

function Kaveat:toggle()
	if self.isOpen then
		self:close()
	else
		self:open()
	end
end

function Kaveat:applyTheme(palette: { [string]: Color3 })
	self.palette = palette
	for _, inst in self.themed.bg do
		inst.BackgroundColor3 = palette.Background
	end
	for _, inst in self.themed.surface do
		inst.BackgroundColor3 = palette.Surface
	end
	for _, inst in self.themed.fg do
		inst.TextColor3 = palette.Foreground
	end
	for _, inst in self.themed.muted do
		inst.TextColor3 = palette.Muted
	end
	for _, inst in self.themed.accent do
		inst.TextColor3 = palette.Accent
	end
	for _, inst in self.themed.border do
		if inst:IsA("UIStroke") then
			inst.Color = palette.Border
		else
			inst.BackgroundColor3 = palette.Border
		end
	end
	self.cmdBox.TextColor3 = palette.Foreground
	self.cmdBox.PlaceholderColor3 = palette.Muted
	self:refreshMode()
	self:refreshTree()
	self:refreshTabs()
end

function Kaveat:destroy()
	if self.unsubscribeTheme then
		self.unsubscribeTheme()
	end
	if self.inputConn then
		self.inputConn:Disconnect()
	end
	self.gui:Destroy()
end

return Kaveat
