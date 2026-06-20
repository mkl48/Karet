-- the input row. a prompt + a real textbox plus the autocomplete dropdown.
-- the box does the typing, switch isnt in this path. up/down do history unless the
-- suggestion list is open, then they move the selection. tab accepts.

local UserInputService = game:GetService("UserInputService")

local create = require(script.Parent.create)

local Input = {}
Input.__index = Input

local FONT = Enum.Font.Code
local TEXT_SIZE = 15
local PROMPT_TEXT = "›"
local MAX = 8 -- how many suggestions to show at once

local function rgb(c: Color3): string
	return string.format("rgb(%d,%d,%d)", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

function Input.new(parent: Instance)
	local self = setmetatable({}, Input)

	self.history = {} :: { string }
	self.historyIndex = 0
	self.draft = ""
	self.submitHandler = nil :: ((string) -> ())?
	self.palette = nil :: any
	self.focused = false

	self.suggester = nil :: ((string) -> { any })?
	self.suggestions = {} :: { any }
	self.sugIndex = 0
	self.sugLabels = {} :: { TextLabel }
	self._settingText = false

	local prompt = create("TextLabel", {
		Name = "Prompt",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 18, 1, 0),
		Font = FONT,
		TextSize = TEXT_SIZE,
		Text = PROMPT_TEXT,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}) :: TextLabel

	local box = create("TextBox", {
		Name = "Entry",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -22, 1, 0),
		Position = UDim2.new(0, 22, 0, 0),
		Font = FONT,
		TextSize = TEXT_SIZE,
		Text = "",
		PlaceholderText = "type a command",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		ClipsDescendants = true,
	}) :: TextBox

	local row = create("Frame", {
		Name = "InputRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Children = {
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
			prompt,
			box,
		},
		Parent = parent,
	})

	-- the dropdown sits just above the input and grows upward
	local sugStroke = create("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local sugFrame = create("Frame", {
		Name = "Suggestions",
		Visible = false,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 0, -4),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		ZIndex = 50,
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 6) }),
			sugStroke,
			create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			create("UIPadding", {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
			}),
		},
		Parent = row,
	})

	self.frame = row
	self.prompt = prompt
	self.box = box
	self.sugFrame = sugFrame
	self.sugStroke = sugStroke

	box.Focused:Connect(function()
		self.focused = true
	end)
	box.FocusLost:Connect(function(enterPressed)
		self.focused = false
		self:hideSuggestions()
		if enterPressed then
			self:submit()
		end
	end)

	box:GetPropertyChangedSignal("Text"):Connect(function()
		if self._settingText then
			return
		end
		-- single line box shouldnt keep tabs, we use tab to accept
		if string.find(box.Text, "\t") then
			self._settingText = true
			box.Text = string.gsub(box.Text, "\t", "")
			self._settingText = false
		end
		self:refreshSuggestions()
	end)

	-- read keys here, switch doesnt fire reliably while the box has focus
	self.inputConn = UserInputService.InputBegan:Connect(function(input)
		if not self.focused then
			return
		end
		local key = input.KeyCode
		local hasSug = #self.suggestions > 0
		if key == Enum.KeyCode.Tab and hasSug then
			self:acceptSuggestion()
		elseif hasSug and key == Enum.KeyCode.Up then
			self:moveSel(-1)
		elseif hasSug and key == Enum.KeyCode.Down then
			self:moveSel(1)
		elseif key == Enum.KeyCode.Up then
			self:historyPrev()
		elseif key == Enum.KeyCode.Down then
			self:historyNext()
		end
	end)

	return self
end

function Input:onSubmit(fn: (string) -> ())
	self.submitHandler = fn
end

function Input:submit()
	local line = self.box.Text
	self.box.Text = ""
	self.historyIndex = 0
	self.draft = ""
	self:hideSuggestions()
	if line ~= "" then
		if self.history[#self.history] ~= line then
			table.insert(self.history, line)
		end
		if self.submitHandler then
			self.submitHandler(line)
		end
	end
	-- keep focus so you can fire commands back to back
	task.defer(function()
		if self.box.Parent then
			self.box:CaptureFocus()
		end
	end)
end

-- autocomplete -------------------------------------------------------------

function Input:setSuggester(fn: (string) -> { any })
	self.suggester = fn
end

function Input:refreshSuggestions()
	if self.suggester and self.box.Text ~= "" then
		self.suggestions = self.suggester(self.box.Text)
	else
		self.suggestions = {}
	end
	self.sugIndex = #self.suggestions > 0 and 1 or 0
	self:renderSuggestions()
end

function Input:renderSuggestions()
	for _, l in self.sugLabels do
		l:Destroy()
	end
	table.clear(self.sugLabels)

	local show = #self.suggestions > 0 and self.focused
	self.sugFrame.Visible = show
	if not show then
		return
	end

	local p = self.palette
	local fg = (p and p.Foreground) or Color3.new(1, 1, 1)
	local sel = (p and p.Selection) or Color3.fromRGB(60, 60, 80)
	local muted = p and p.Muted

	for i, sug in self.suggestions do
		if i > MAX then
			break
		end
		local text = sug.text
		if sug.detail ~= "" and muted then
			text = `{sug.text}  <font color="{rgb(muted)}" size="11">{sug.detail}</font>`
		end
		local label = create("TextLabel", {
			Name = "Sug",
			BackgroundColor3 = sel,
			BackgroundTransparency = i == self.sugIndex and 0 or 1,
			Size = UDim2.new(1, 0, 0, 18),
			Font = FONT,
			TextSize = 13,
			RichText = true,
			Text = text,
			TextColor3 = fg,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i,
			ZIndex = 51,
			Parent = self.sugFrame,
		}) :: TextLabel
		table.insert(self.sugLabels, label)
	end
end

function Input:moveSel(delta: number)
	local n = math.min(#self.suggestions, MAX)
	if n == 0 then
		return
	end
	self.sugIndex = ((self.sugIndex - 1 + delta) % n) + 1
	self:renderSuggestions()
end

function Input:replaceLastToken(text: string, insert: string): string
	local trailing = string.match(text, "%S*$") or ""
	return string.sub(text, 1, #text - #trailing) .. insert
end

function Input:acceptSuggestion()
	local sug = self.suggestions[self.sugIndex]
	if not sug then
		return
	end
	local newText = self:replaceLastToken(self.box.Text, sug.insert) .. " "
	self._settingText = true
	self.box.Text = newText
	self.box.CursorPosition = #newText + 1
	self._settingText = false
	self:refreshSuggestions()
end

function Input:hideSuggestions()
	self.suggestions = {}
	self.sugIndex = 0
	self:renderSuggestions()
end

-- history ------------------------------------------------------------------

function Input:historyPrev()
	if #self.history == 0 then
		return
	end
	if self.historyIndex == 0 then
		self.draft = self.box.Text
		self.historyIndex = #self.history
	elseif self.historyIndex > 1 then
		self.historyIndex -= 1
	end
	self.box.Text = self.history[self.historyIndex]
	self.box.CursorPosition = #self.box.Text + 1
end

function Input:historyNext()
	if self.historyIndex == 0 then
		return
	end
	if self.historyIndex < #self.history then
		self.historyIndex += 1
		self.box.Text = self.history[self.historyIndex]
	else
		self.historyIndex = 0
		self.box.Text = self.draft
	end
	self.box.CursorPosition = #self.box.Text + 1
end

function Input:focus()
	self.box:CaptureFocus()
end

function Input:blur()
	self.box:ReleaseFocus()
end

function Input:applyTheme(palette: { [string]: Color3 })
	self.palette = palette
	self.prompt.TextColor3 = palette.Prompt
	self.box.TextColor3 = palette.Foreground
	self.box.PlaceholderColor3 = palette.Muted
	self.sugFrame.BackgroundColor3 = palette.Surface
	self.sugStroke.Color = palette.Border
	self:renderSuggestions()
end

function Input:destroy()
	if self.inputConn then
		self.inputConn:Disconnect()
	end
	self.frame:Destroy()
	table.clear(self.history)
end

return Input
