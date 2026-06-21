-- the input row. a prompt + a real textbox, a coloured overlay behind it (so valid
-- commands show up green-ish vs normal text), and the autocomplete dropdown with a
-- signature line telling you which arg youre on.
--
-- the box does the typing but its own text is hidden (transparent), the overlay label
-- draws the coloured version. switch isnt in this path. up/down do history unless the
-- dropdown has suggestions, then they move the selection. tab accepts.

local UserInputService = game:GetService("UserInputService")

local create = require(script.Parent.create)
local Defaults = require(script.Parent.Parent.Defaults)

local Input = {}
Input.__index = Input

local FONT = Defaults.Font
local TEXT_SIZE = Defaults.Input.TextSize
local PROMPT_TEXT = Defaults.Input.Prompt
local MAX = Defaults.Input.MaxSuggestions

-- auto pairing. type an opener, get the closer for free with the caret in the middle
local PAIRS = { ["("] = ")", ["["] = "]", ["{"] = "}", ['"'] = '"', ["'"] = "'" }
local CLOSERS = { [")"] = true, ["]"] = true, ["}"] = true, ['"'] = true, ["'"] = true }

local function rgb(c: Color3): string
	return string.format("rgb(%d,%d,%d)", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function esc(s: string): string
	return (string.gsub(string.gsub(string.gsub(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

function Input.new(parent: Instance)
	local self = setmetatable({}, Input)

	self.history = {} :: { string }
	self.historyIndex = 0
	self.draft = ""
	self.submitHandler = nil :: ((string) -> ())?
	self.palette = nil :: any
	self.focused = false

	self.completer = nil :: any
	self.suggestions = {} :: { any }
	self.signature = nil :: any
	self.sugIndex = 0
	self.sugLabels = {} :: { TextLabel }
	self._settingText = false
	self._lastText = ""
	self.keepFocus = true -- terminal sets this false when it closes so it stops grabbing keys

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

	-- the coloured version, sits under the box
	local overlay = create("TextLabel", {
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -22, 1, 0),
		Position = UDim2.new(0, 22, 0, 0),
		Font = FONT,
		TextSize = TEXT_SIZE,
		RichText = true,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ClipsDescendants = true,
		ZIndex = 1,
	}) :: TextLabel

	local box = create("TextBox", {
		Name = "Entry",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -22, 1, 0),
		Position = UDim2.new(0, 22, 0, 0),
		Font = FONT,
		TextSize = TEXT_SIZE,
		Text = "",
		PlaceholderText = "",
		TextTransparency = 1, -- hidden, the overlay draws it. caret still shows
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		ClipsDescendants = true,
		ZIndex = 2,
	}) :: TextBox

	local row = create("Frame", {
		Name = "InputRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Children = {
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
			prompt,
			overlay,
			box,
		},
		Parent = parent,
	})

	local sugStroke = create("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local sugFrame = create("Frame", {
		Name = "Suggestions",
		Visible = false,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 0, -4),
		Size = UDim2.fromOffset(320, 0),
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
	self.overlay = overlay
	self.box = box
	self.sugFrame = sugFrame
	self.sugStroke = sugStroke

	box.Focused:Connect(function()
		self.focused = true
	end)
	box.FocusLost:Connect(function(enterPressed)
		self.focused = false
		self:hideDropdown()
		if enterPressed then
			self:submit()
		end
	end)

	box:GetPropertyChangedSignal("Text"):Connect(function()
		if self._settingText then
			return
		end
		if string.find(box.Text, "\t") then
			self._settingText = true
			box.Text = string.gsub(box.Text, "\t", "")
			self._settingText = false
		end
		self:autoPair()
		self._lastText = box.Text
		self:updateOverlay()
		self:refreshDropdown()
	end)

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
	self:hideDropdown()
	self:updateOverlay()
	if line ~= "" then
		if self.history[#self.history] ~= line then
			table.insert(self.history, line)
		end
		if self.submitHandler then
			self.submitHandler(line)
		end
	end
	task.defer(function()
		if self.keepFocus and self.box.Parent then
			self.box:CaptureFocus()
		end
	end)
end

-- command colouring --------------------------------------------------------

-- colour the leading word of each chain segment if its a real command
function Input:markup(text: string): string
	local cmdColor = self.palette and rgb(self.palette.Command) or "rgb(180,200,255)"
	local isCommand = self.completer and self.completer.isCommand
	local result = {}
	local pos, len, segStart = 1, #text, 1

	local function flush(seg: string)
		local lead, word, rest = string.match(seg, "^(%s*)(%S*)(.*)$")
		if word and word ~= "" and isCommand and isCommand(word) then
			table.insert(result, esc(lead) .. `<font color="{cmdColor}">` .. esc(word) .. `</font>` .. esc(rest))
		else
			table.insert(result, esc(seg))
		end
	end

	while pos <= len do
		local op
		for _, o in { "&&", "||", "&", ";" } do
			if string.sub(text, pos, pos + #o - 1) == o then
				op = o
				break
			end
		end
		if op then
			flush(string.sub(text, segStart, pos - 1))
			table.insert(result, esc(op))
			pos += #op
			segStart = pos
		else
			pos += 1
		end
	end
	flush(string.sub(text, segStart))
	return table.concat(result)
end

-- on a single typed char, drop in the closing half or type over an existing closer
function Input:autoPair()
	local new = self.box.Text
	if #new ~= #self._lastText + 1 then
		return -- only react to one typed char, not paste/delete
	end
	local cur = self.box.CursorPosition
	if cur < 2 then
		return
	end
	local ch = string.sub(new, cur - 1, cur - 1)
	local nextCh = string.sub(new, cur, cur)
	if CLOSERS[ch] and nextCh == ch then
		self._settingText = true
		self.box.Text = string.sub(new, 1, cur - 1) .. string.sub(new, cur + 1)
		self.box.CursorPosition = cur
		self._settingText = false
	elseif PAIRS[ch] then
		self._settingText = true
		self.box.Text = string.sub(new, 1, cur - 1) .. PAIRS[ch] .. string.sub(new, cur)
		self.box.CursorPosition = cur
		self._settingText = false
	end
end

function Input:updateOverlay()
	if self.box.Text == "" then
		local muted = self.palette and rgb(self.palette.Muted) or "rgb(120,120,120)"
		self.overlay.Text = `<font color="{muted}">type a command</font>`
	else
		self.overlay.Text = self:markup(self.box.Text)
	end
end

-- dropdown -----------------------------------------------------------------

function Input:setCompleter(completer: any)
	self.completer = completer
end

function Input:refreshDropdown()
	if self.completer and self.box.Text ~= "" then
		self.suggestions = self.completer.suggest(self.box.Text)
		self.signature = self.completer.signature(self.box.Text)
	else
		self.suggestions = {}
		self.signature = nil
	end
	self.sugIndex = #self.suggestions > 0 and 1 or 0
	self:renderDropdown()
end

function Input:renderDropdown()
	for _, l in self.sugLabels do
		l:Destroy()
	end
	table.clear(self.sugLabels)

	local show = self.focused and (self.signature ~= nil or #self.suggestions > 0)
	self.sugFrame.Visible = show
	if not show then
		return
	end

	local p = self.palette
	local fg = (p and p.Foreground) or Color3.new(1, 1, 1)
	local muted = (p and p.Muted) or Color3.fromRGB(120, 120, 120)
	local accent = (p and p.Accent) or Color3.fromRGB(120, 160, 255)
	local cmd = (p and p.Command) or accent
	local sel = (p and p.Selection) or Color3.fromRGB(60, 60, 80)

	if self.signature then
		local parts = { `<font color="{rgb(cmd)}">{esc(self.signature.name)}</font>` }
		for _, a in self.signature.args do
			local color = a.current and rgb(accent) or rgb(muted)
			table.insert(parts, `<font color="{color}">&lt;{esc(a.label)}&gt;</font>`)
		end
		local header = create("TextLabel", {
			Name = "Sig",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			Font = FONT,
			TextSize = 12,
			RichText = true,
			Text = table.concat(parts, " "),
			TextColor3 = muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 0,
			ZIndex = 51,
			Parent = self.sugFrame,
		}) :: TextLabel
		table.insert(self.sugLabels, header)
	end

	for i, sug in self.suggestions do
		if i > MAX then
			break
		end
		local text = sug.text
		if sug.detail ~= "" then
			text = `{esc(sug.text)}  <font color="{rgb(muted)}" size="11">{esc(sug.detail)}</font>`
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
	self:renderDropdown()
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
	self._lastText = newText
	self:updateOverlay()
	self:refreshDropdown()
end

function Input:hideDropdown()
	self.suggestions = {}
	self.signature = nil
	self.sugIndex = 0
	self:renderDropdown()
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
	self.box.TextColor3 = palette.Foreground -- caret colour
	self.overlay.TextColor3 = palette.Foreground
	self.sugFrame.BackgroundColor3 = palette.Surface
	self.sugStroke.Color = palette.Border
	self:updateOverlay()
	self:renderDropdown()
end

function Input:destroy()
	if self.inputConn then
		self.inputConn:Disconnect()
	end
	self.frame:Destroy()
	table.clear(self.history)
end

return Input
