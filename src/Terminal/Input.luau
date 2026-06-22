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
local Search = require(script.Parent.Search)
local Highlight = require(script.Parent.Highlight)

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
	self.paletteSource = nil :: (() -> { any })?
	self.mode = nil :: string? -- nil | "search" (ctrl+r) | "palette" (ctrl+shift+p)
	self.modeHeader = nil :: string?
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
		-- in a picker, enter accepts the selection, clicking away cancels it
		if self.mode then
			if enterPressed then
				self:submit()
			else
				self:exitMode(self.draft)
			end
			return
		end
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
		-- in a picker the box holds the search query, not a command line
		if self.mode then
			self._lastText = box.Text
			self:updatePicker()
			return
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
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

		-- open the pickers. ctrl+shift+p = command palette, ctrl+r = reverse history search
		-- (pressing ctrl+r again cycles to an older match)
		if ctrl and shift and key == Enum.KeyCode.P then
			self:enterPalette()
			return
		elseif ctrl and key == Enum.KeyCode.R then
			if self.mode == "search" then
				self:moveSel(1)
			else
				self:enterSearch()
			end
			return
		end

		-- while a picker is open, the arrows/tab/esc drive it and nothing else
		if self.mode then
			if key == Enum.KeyCode.Escape then
				self:exitMode(self.draft)
			elseif key == Enum.KeyCode.Up then
				self:moveSel(-1)
			elseif key == Enum.KeyCode.Down then
				self:moveSel(1)
			elseif key == Enum.KeyCode.Tab then
				self:acceptPicker()
			end
			return
		end

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
	-- enter inside a picker accepts the selection rather than running a command
	if self.mode then
		self:acceptPicker()
		task.defer(function()
			if self.keepFocus and self.box.Parent then
				self.box:CaptureFocus()
			end
		end)
		return
	end
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

-- map a Highlight group name to a colour off the active palette, falling back to Foreground
function Input:groupColor(group: string): string
	local p = self.palette
	if not p then
		return "rgb(220,220,220)"
	end
	local c = (group ~= "Plain" and p[group]) or p.Foreground
	return rgb(c)
end

-- full syntax colouring: run the shell lexer over the line and tint every token (command word,
-- args, strings, numbers, flags, operators, @vars, /refs). an unknown leading word shows up in
-- the Error colour, so you can see a command is wrong before you even hit enter.
function Input:markup(text: string): string
	local isCommand = self.completer and self.completer.isCommand
	local spans = Highlight.spans(text, isCommand)
	local out = {}
	for _, span in spans do
		if span.group == "Plain" then
			table.insert(out, esc(span.text))
		else
			table.insert(out, `<font color="{self:groupColor(span.group)}">{esc(span.text)}</font>`)
		end
	end
	return table.concat(out)
end

-- the faded inline completion drawn after the caret (cmdr-style ghost text). only when the caret
-- sits at the very end and the top suggestion extends the word youre typing.
function Input:ghostMarkup(): string
	local sug = self.suggestions[self.sugIndex]
	if not sug or type(sug.insert) ~= "string" then
		return ""
	end
	local text = self.box.Text
	if self.box.CursorPosition ~= #text + 1 then
		return "" -- only trail the caret when it's at the end of the line
	end
	local trailing = string.match(text, "%S*$") or ""
	if trailing == "" then
		return ""
	end
	if #sug.insert <= #trailing or string.lower(string.sub(sug.insert, 1, #trailing)) ~= string.lower(trailing) then
		return "" -- the suggestion doesn't continue what's typed
	end
	local remainder = string.sub(sug.insert, #trailing + 1)
	local ghost = self.palette and self.palette.Ghost or (self.palette and self.palette.Muted)
	local color = ghost and rgb(ghost) or "rgb(110,110,120)"
	return `<font color="{color}">{esc(remainder)}</font>`
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
		self.overlay.Text = self:markup(self.box.Text) .. self:ghostMarkup()
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
	-- suggestions just changed, so the ghost trailing the caret may have too
	if self.box.Text ~= "" and not self.mode then
		self.overlay.Text = self:markup(self.box.Text) .. self:ghostMarkup()
	end
end

function Input:renderDropdown()
	for _, l in self.sugLabels do
		l:Destroy()
	end
	table.clear(self.sugLabels)

	local show = self.focused and (self.modeHeader ~= nil or self.signature ~= nil or #self.suggestions > 0)
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

	-- a picker shows its own header (mode + live query) in place of the command signature
	if self.modeHeader then
		local header = create("TextLabel", {
			Name = "PickerHeader",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			Font = FONT,
			TextSize = 12,
			RichText = true,
			Text = `<font color="{rgb(accent)}">{esc(self.modeHeader)}</font>`,
			TextColor3 = accent,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 0,
			ZIndex = 51,
			Parent = self.sugFrame,
		}) :: TextLabel
		table.insert(self.sugLabels, header)
	elseif self.signature then
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

-- pickers (ctrl+r reverse search, ctrl+shift+p command palette) ------------

function Input:setPaletteSource(fn: () -> { any })
	self.paletteSource = fn
end

-- enter a picker: stash whatever was on the line, clear the box (it becomes the query)
function Input:enterMode(mode: string, promptChar: string)
	self.draft = self.box.Text
	self.mode = mode
	self.sugIndex = 1
	self.prompt.Text = promptChar
	self._settingText = true
	self.box.Text = ""
	self.box.CursorPosition = 1
	self._settingText = false
	self._lastText = ""
	self:updatePicker()
end

function Input:enterSearch()
	self:enterMode("search", "r")
end

function Input:enterPalette()
	self:enterMode("palette", "?")
end

-- leave the picker, dropping `finalText` onto the line (the accepted match, or the draft on
-- cancel). back to a normal command line.
function Input:exitMode(finalText: string?)
	self.mode = nil
	self.modeHeader = nil
	self.prompt.Text = PROMPT_TEXT
	local restore = finalText or ""
	self._settingText = true
	self.box.Text = restore
	self.box.CursorPosition = #restore + 1
	self._settingText = false
	self._lastText = restore
	self:hideDropdown()
	self:updateOverlay()
	self:refreshDropdown()
end

-- rebuild the picker results from the current query (called on every keystroke in a mode)
function Input:updatePicker()
	local query = self.box.Text
	local results: { any } = {}
	if self.mode == "search" then
		self.modeHeader = `reverse-search: {query}`
		for occ = 1, MAX do
			local line = Search.history(self.history, query, occ)
			if not line then
				break
			end
			table.insert(results, { text = line, detail = "", insert = line })
		end
	elseif self.mode == "palette" then
		self.modeHeader = "command palette"
		local items = self.paletteSource and self.paletteSource() or {}
		local ranked = Search.rank(query, items, function(it)
			return it.name
		end)
		for i, it in ranked do
			if i > MAX then
				break
			end
			table.insert(results, { text = it.name, detail = it.detail or "", insert = it.name })
		end
	end
	self.suggestions = results
	self.signature = nil
	if self.sugIndex < 1 or self.sugIndex > #results then
		self.sugIndex = #results > 0 and 1 or 0
	end

	-- draw the query in the overlay (plain, no command colouring), or a hint when empty
	if query == "" then
		local muted = self.palette and rgb(self.palette.Muted) or "rgb(120,120,120)"
		local hint = self.mode == "search" and "search history" or "search commands"
		self.overlay.Text = `<font color="{muted}">{hint}</font>`
	else
		self.overlay.Text = esc(query)
	end
	self:renderDropdown()
end

-- accept the highlighted result: insert a command name (palette, with a trailing space so
-- you can keep typing args) or drop the matched line back on the prompt (search).
function Input:acceptPicker()
	local sug = self.suggestions[self.sugIndex]
	local chosen: string
	if sug then
		chosen = self.mode == "palette" and (sug.insert .. " ") or sug.insert
	else
		chosen = self.draft
	end
	self:exitMode(chosen)
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
