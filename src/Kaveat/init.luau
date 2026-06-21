-- Kaveat, the script editor. custom ui, feels like neovim: a topbar, a kavs file tree,
-- tabs, the editor, an output pane and a modeline, all resizable, plus a draggable window.
-- two modes like nvim: READ and WRITE. click or press i to write, esc to read. : opens a
-- cmdline (READ mode). ctrl+enter runs. files live in the profile (Profile.Kavs).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local deps = require(script.Parent.deps)
local Capture = require(script.Parent.Capture)
local create = require(script.Parent.Terminal.create)
local LuauComplete = require(script.Complete)
local Defaults = require(script.Parent.Defaults)

local Kaveat = {}
Kaveat.__index = Kaveat

local FONT = Defaults.Font
local SIZE = Defaults.Editor.TextSize
local TOP_H = Defaults.Editor.TopBarHeight
local TREE_W = Defaults.Editor.TreeWidth
local OUT_H = Defaults.Editor.OutputHeight
local TAB_H = Defaults.Editor.TabHeight
local MODE_H = Defaults.Editor.ModelineHeight

-- the : commands, used for the cmdline autocomplete
local CMDS = {
	{ name = "w", detail = "save" },
	{ name = "q", detail = "close tab" },
	{ name = "wq", detail = "save and close" },
	{ name = "e", detail = "open file" },
	{ name = "new", detail = "new file" },
	{ name = "run", detail = "run buffer" },
	{ name = "server", detail = "server context" },
	{ name = "client", detail = "client context" },
	{ name = "ls", detail = "list kavs" },
	{ name = "close", detail = "close editor" },
}

local function rgb(c: Color3): string
	return string.format("rgb(%d,%d,%d)", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

-- lucide icon per suggestion kind (the intellisense icons)
local ICONS = {
	global = "globe-2",
	["local"] = "circle-dot",
	["function"] = "square-function",
	method = "function-square",
	member = "code-2",
	keyword = "key-round",
	class = "whole-word",
}

export type Buffer = { name: string, context: string, source: string, dirty: boolean, isConfig: boolean? }

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
	self.cmdSuggestions = {}
	self.cmdSel = 0
	self.cmdSugLabels = {}
	self.acSuggestions = {}
	self.acSel = 0
	self.acLabels = {}
	self.lucide = deps.Lucide()
	self.iconCache = {}

	self:build(options)

	-- syntax highlighting on the editor box (boatbombers highlighter, vendored)
	local Highlighter = deps.Highlighter()
	if Highlighter then
		self.highlighter = Highlighter
		self.hlCleanup = Highlighter.highlight({ textObject = self.box })
	end

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
		TextColor3 = Color3.fromRGB(130, 203, 255),
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
	-- the luau autocomplete popup, follows the cursor line roughly
	local acStroke = create("UIStroke", { Thickness = 1 })
	local acFrame = create("Frame", {
		Name = "AutoComplete",
		Visible = false,
		Position = UDim2.new(0, 50, 0, 0),
		Size = UDim2.fromOffset(260, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		ZIndex = 9,
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 6) }),
			acStroke,
			create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			create("UIPadding", {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
			}),
		},
	})
	self.acFrame, self.acStroke = acFrame, acStroke

	local editor = create("Frame", {
		Name = "EditorArea",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -(TAB_H + self.outH)),
		Position = UDim2.new(0, 0, 0, TAB_H),
		Children = { gutter, box, acFrame },
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

	-- cmdline autocomplete, sits just above the cmdline
	local cmdStroke = create("UIStroke", { Thickness = 1 })
	local cmdSug = create("Frame", {
		Name = "CmdSug",
		Visible = false,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 0, -2),
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		ZIndex = 8,
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 6) }),
			cmdStroke,
			create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			create("UIPadding", {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
			}),
		},
		Parent = cmdline,
	})
	self.cmdSug, self.cmdStroke = cmdSug, cmdStroke

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

	local scale = create("UIScale", { Scale = 1 })
	local window = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(900, 560),
		BorderSizePixel = 0,
		Visible = false,
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			scale,
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
	self.scaleObj = scale
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

	self.themed.bg = { window, tree, tabBar, output, cmdSug, acFrame }
	self.themed.surface = { topbar, modeline, cmdline }
	self.themed.fg = { box }
	self.themed.muted = { gutter, treeTitle, ctxLabel, fileLabel }
	self.themed.accent = { title }
	self.themed.border = { stroke, treeDrag, outDrag, cmdStroke, acStroke }

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
		if not self._setting then
			self:editorComplete()
		end
	end)

	exit.MouseButton1Click:Connect(function()
		self:close()
	end)
	self:wireDrag(treeDrag, "tree")
	self:wireDrag(outDrag, "out")
	self:wireWindow(topbar, grip)

	cmdBox:GetPropertyChangedSignal("Text"):Connect(function()
		self:cmdSuggest()
	end)
	cmdBox.FocusLost:Connect(function(enter)
		self.cmdline.Visible = false
		self:hideCmdSug()
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

	-- ctrl +/- zoom (ctrl+0 resets), scales the whole editor window
	if ctrl and (key == Enum.KeyCode.Equals or key == Enum.KeyCode.KeypadPlus) then
		self:zoomBy(0.1)
		return
	elseif ctrl and (key == Enum.KeyCode.Minus or key == Enum.KeyCode.KeypadMinus) then
		self:zoomBy(-0.1)
		return
	elseif ctrl and (key == Enum.KeyCode.Zero or key == Enum.KeyCode.KeypadZero) then
		self:setScale(1)
		return
	end

	-- cmdline open: tab accepts, up/down move the suggestion (these are processed by the
	-- cmd textbox so handle them before the processed guard)
	if self.cmdline.Visible then
		if key == Enum.KeyCode.Tab then
			if #self.cmdSuggestions > 0 then
				self:acceptCmdSug()
			end
		elseif key == Enum.KeyCode.Up then
			self:moveCmdSel(-1)
		elseif key == Enum.KeyCode.Down then
			self:moveCmdSel(1)
		end
		return
	end

	if self.mode == "WRITE" then
		local hasAc = #self.acSuggestions > 0
		if key == Enum.KeyCode.Tab then
			-- roblox textboxes dont insert a tab, so we handle it: accept or indent
			if hasAc then
				self:acceptAc(self.acSuggestions[self.acSel])
			else
				self:insertText("    ")
			end
			return
		end
		-- up/down cycle the autocomplete when its open, otherwise let the caret move
		if hasAc and key == Enum.KeyCode.Up then
			self:moveAcSel(-1)
			return
		elseif hasAc and key == Enum.KeyCode.Down then
			self:moveAcSel(1)
			return
		end
		if key == Enum.KeyCode.Escape then
			if hasAc then
				self:hideAc()
			else
				self.box:ReleaseFocus()
			end
		end
		return
	end

	-- READ mode, ignore keys eaten by another textbox
	if processed then
		return
	end
	if key == Enum.KeyCode.I then
		self.box:CaptureFocus()
	elseif key == Enum.KeyCode.Semicolon and shift then
		self.cmdline.Visible = true
		self.cmdBox:CaptureFocus()
		self:cmdSuggest()
	end
end

-- cmdline autocomplete -----------------------------------------------------

function Kaveat:cmdSuggest()
	local text = self.cmdBox.Text
	local word, rest = string.match(text, "^(%S*)(.*)$")
	local out = {}
	if rest == "" then
		local p = string.lower(word)
		for _, c in CMDS do
			if string.sub(c.name, 1, #p) == p then
				table.insert(out, { text = c.name, detail = c.detail, insert = c.name .. " " })
			end
		end
	else
		local cmd = string.lower(word)
		if cmd == "e" or cmd == "edit" or cmd == "new" then
			local partial = string.lower((string.gsub(rest, "^%s*", "")))
			for _, name in self:listFiles() do
				if string.sub(string.lower(name), 1, #partial) == partial then
					table.insert(out, { text = name, detail = "kav", insert = word .. " " .. name })
				end
			end
		end
	end
	self.cmdSuggestions = out
	self.cmdSel = #out > 0 and 1 or 0
	self:renderCmdSug()
end

function Kaveat:renderCmdSug()
	for _, l in self.cmdSugLabels do
		l:Destroy()
	end
	table.clear(self.cmdSugLabels)
	local show = self.cmdline.Visible and #self.cmdSuggestions > 0
	self.cmdSug.Visible = show
	if not show then
		return
	end
	local p = self.palette
	local fg = (p and p.Foreground) or Color3.new(1, 1, 1)
	local muted = (p and p.Muted) or Color3.fromRGB(120, 120, 120)
	local sel = (p and p.Selection) or Color3.fromRGB(60, 60, 80)
	for i, s in self.cmdSuggestions do
		if i > 8 then
			break
		end
		local label = create("TextLabel", {
			Name = "S",
			BackgroundColor3 = sel,
			BackgroundTransparency = i == self.cmdSel and 0 or 1,
			Size = UDim2.new(1, 0, 0, 18),
			Font = FONT,
			TextSize = 13,
			RichText = true,
			Text = `{s.text}  <font color="{rgb(muted)}" size="11">{s.detail}</font>`,
			TextColor3 = fg,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i,
			ZIndex = 9,
			Parent = self.cmdSug,
		})
		table.insert(self.cmdSugLabels, label)
	end
end

function Kaveat:moveCmdSel(d: number)
	local n = math.min(#self.cmdSuggestions, 8)
	if n == 0 then
		return
	end
	self.cmdSel = ((self.cmdSel - 1 + d) % n) + 1
	self:renderCmdSug()
end

function Kaveat:acceptCmdSug()
	local s = self.cmdSuggestions[self.cmdSel]
	if not s then
		return
	end
	self.cmdBox.Text = s.insert
	self.cmdBox.CursorPosition = #s.insert + 1
end

function Kaveat:hideCmdSug()
	self.cmdSuggestions = {}
	self.cmdSel = 0
	self:renderCmdSug()
end

-- editor (luau) autocomplete -----------------------------------------------

function Kaveat:editorComplete()
	if self.mode ~= "WRITE" then
		self:hideAc()
		return
	end
	-- remember where the caret was when we computed these, so accepting still targets the
	-- right word even if up/down nudged the native textbox caret while cycling suggestions
	self.acCursor = self.box.CursorPosition
	self.acSuggestions = LuauComplete.complete(self.box.Text, self.box.CursorPosition)
	self.acSel = #self.acSuggestions > 0 and 1 or 0
	local before = string.sub(self.box.Text, 1, math.max(0, self.box.CursorPosition - 1))
	local line = select(2, string.gsub(before, "\n", "\n"))
	self.acFrame.Position = UDim2.new(0, 50, 0, (line + 1) * (SIZE + 2))
	self:renderAc()
end

-- cycle the autocomplete selection (wraps), capped at the 8 shown rows
function Kaveat:moveAcSel(d: number)
	local n = math.min(#self.acSuggestions, 8)
	if n == 0 then
		return
	end
	self.acSel = ((self.acSel - 1 + d) % n) + 1
	self:renderAc()
end

function Kaveat:renderAc()
	for _, l in self.acLabels do
		l:Destroy()
	end
	table.clear(self.acLabels)
	local show = self.mode == "WRITE" and #self.acSuggestions > 0
	self.acFrame.Visible = show
	if not show then
		return
	end
	local p = self.palette
	local fg = (p and p.Foreground) or Color3.new(1, 1, 1)
	local muted = (p and p.Muted) or Color3.fromRGB(120, 120, 120)
	local sel = (p and p.Selection) or Color3.fromRGB(60, 60, 80)
	for i, s in self.acSuggestions do
		if i > 8 then
			break
		end
		local row = create("Frame", {
			Name = "Ac",
			BackgroundColor3 = sel,
			BackgroundTransparency = i == self.acSel and 0 or 1, -- highlighted row, tab takes it
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = i,
			ZIndex = 10,
			Parent = self.acFrame,
		})
		local asset = self:icon(s.detail)
		if asset then
			create("ImageLabel", {
				Name = "Icon",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(14, 14),
				Position = UDim2.new(0, 0, 0.5, -7),
				Image = asset.Url,
				ImageRectSize = asset.ImageRectSize,
				ImageRectOffset = asset.ImageRectOffset,
				ImageColor3 = self:iconColor(s.detail),
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 11,
				Parent = row,
			})
		end
		create("TextLabel", {
			Name = "T",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -20, 1, 0),
			Position = UDim2.new(0, 20, 0, 0),
			Font = FONT,
			TextSize = 13,
			RichText = true,
			Text = `{s.text}  <font color="{rgb(muted)}" size="11">{s.detail}</font>`,
			TextColor3 = fg,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 11,
			Parent = row,
		})
		table.insert(self.acLabels, row)
	end
end

-- resolve a lucide asset for a suggestion kind (cached, degrades if the name is bad)
function Kaveat:icon(detail: string): any?
	if not self.lucide then
		return nil
	end
	if self.iconCache[detail] == nil then
		local name = ICONS[detail] or "file-code"
		local ok, asset = pcall(self.lucide.GetAsset, name, 256)
		if not ok then
			ok, asset = pcall(self.lucide.GetAsset, "file-code", 256)
		end
		self.iconCache[detail] = (ok and asset) or false
	end
	return self.iconCache[detail] or nil
end

function Kaveat:iconColor(detail: string): Color3
	local p = self.palette
	if not p then
		return Color3.new(1, 1, 1)
	end
	local map = {
		global = p.Accent,
		["local"] = p.Variable or p.Foreground,
		["function"] = p.Function or p.Accent,
		method = p.Function or p.Accent,
		member = p.Field or p.Accent,
		keyword = p.Keyword,
		class = p.Type,
	}
	return map[detail] or p.Foreground
end

function Kaveat:hideAc()
	self.acSuggestions = {}
	self.acSel = 0
	self:renderAc()
end

-- replace the word being typed with the suggestion
function Kaveat:acceptAc(s: any)
	if not s then
		return
	end
	local text = self.box.Text
	local cur = self.acCursor or self.box.CursorPosition
	if cur < 1 then
		cur = #text + 1
	end
	local before = string.sub(text, 1, cur - 1)
	local partial = string.match(before, "[%w_]*$") or ""
	local newBefore = string.sub(before, 1, #before - #partial) .. s.insert
	self._setting = true
	self.box.Text = newBefore .. string.sub(text, cur)
	self.box.CursorPosition = #newBefore + 1
	self._setting = false
	local buf = self.buffers[self.active]
	if buf then
		buf.source = self.box.Text
		buf.dirty = true
	end
	self:hideAc()
end

function Kaveat:insertText(str: string)
	local text = self.box.Text
	local cur = self.box.CursorPosition
	if cur < 1 then
		cur = #text + 1
	end
	self._setting = true
	self.box.Text = string.sub(text, 1, cur - 1) .. str .. string.sub(text, cur)
	self.box.CursorPosition = cur + #str
	self._setting = false
	local buf = self.buffers[self.active]
	if buf then
		buf.source = self.box.Text
		buf.dirty = true
	end
	self:refreshGutter()
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

-- open the @CONFIG buffer (a live settings file). saving it applies, instead of writing a
-- kav. `apply(source)` returns a list of summary lines to echo in the output pane.
function Kaveat:openConfig(text: string, apply: (string) -> { string })
	self.configApply = apply
	for i, buf in self.buffers do
		if buf.isConfig then
			buf.source = text
			buf.dirty = false
			self.active = i
			self:open()
			self:showActive()
			return
		end
	end
	table.insert(self.buffers, { name = "@CONFIG", context = "Client", source = text, dirty = false, isConfig = true })
	self.active = #self.buffers
	self:open()
	self:showActive()
	self:refreshTabs()
end

function Kaveat:save()
	local buf = self.buffers[self.active]
	-- saving the config buffer applies it rather than writing to the kavs store
	if buf and buf.isConfig and self.configApply then
		local ok, res = pcall(self.configApply, buf.source)
		if ok and type(res) == "table" then
			for _, line in res do
				self:print(line, "Success")
			end
		else
			self:print("config error: " .. tostring(res), "Error")
		end
		buf.dirty = false
		self:refreshTitle()
		self:refreshTabs()
		return
	end
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

-- zoom ---------------------------------------------------------------------

function Kaveat:setScale(scale: number)
	if self.scaleObj then
		self.scaleObj.Scale = math.clamp(scale, Defaults.Zoom.Min, Defaults.Zoom.Max)
	end
end

function Kaveat:zoomBy(delta: number)
	if self.scaleObj then
		self:setScale(self.scaleObj.Scale + delta)
	end
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
	Capture.acquire("kaveat")
	self:refreshTree()
	self.mode = "READ"
	self:refreshMode()
	self:refreshTitle()
end

function Kaveat:close()
	self.isOpen = false
	self.window.Visible = false
	Capture.release("kaveat")
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
	if self.highlighter then
		self.highlighter.setTokenColors({
			background = palette.Background,
			iden = palette.Foreground,
			keyword = palette.Keyword,
			builtin = palette.Type,
			string = palette.String,
			number = palette.Number,
			comment = palette.Comment,
			operator = palette.Operator,
		})
	end
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
	if self.hlCleanup then
		self.hlCleanup()
	end
	self.gui:Destroy()
end

return Kaveat
