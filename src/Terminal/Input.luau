-- The terminal's input row: a Prompt sigil + a real TextBox.
--
-- The TextBox does the actual typing (characters, IME, clipboard, caret) — Switch is not
-- involved in text entry, only in the open/close/history *actions* (wired by the
-- orchestrator). Submitting fires onSubmit(line) and records the line in a command
-- history that Up/Down navigate via historyPrev/historyNext.

local UserInputService = game:GetService("UserInputService")

local create = require(script.Parent.create)

local Input = {}
Input.__index = Input

local FONT = Enum.Font.Code
local TEXT_SIZE = 15
local PROMPT_TEXT = "›"

function Input.new(parent: Instance)
	local self = setmetatable({}, Input)

	self.history = {} :: { string }
	self.historyIndex = 0 -- 0 = editing a fresh line; 1..#history = browsing
	self.draft = "" -- the in-progress line stashed while browsing history
	self.submitHandler = nil :: ((string) -> ())?
	self.palette = nil :: any
	self.focused = false

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
		PlaceholderText = "type a command…",
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
			create("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
			prompt,
			box,
		},
		Parent = parent,
	})

	self.frame = row
	self.prompt = prompt
	self.box = box

	box.Focused:Connect(function()
		self.focused = true
	end)
	box.FocusLost:Connect(function(enterPressed)
		self.focused = false
		if enterPressed then
			self:submit()
		end
	end)

	-- History via UserInputService: arrow actions routed through Switch don't fire reliably
	-- while a TextBox holds keyboard focus, so we read Up/Down here whenever the box is
	-- focused. This is what makes history repeatable (the old Switch path fired once).
	self.inputConn = UserInputService.InputBegan:Connect(function(input)
		if not self.focused then
			return
		end
		if input.KeyCode == Enum.KeyCode.Up then
			self:historyPrev()
		elseif input.KeyCode == Enum.KeyCode.Down then
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
	if line ~= "" then
		-- Avoid logging an identical consecutive command twice.
		if self.history[#self.history] ~= line then
			table.insert(self.history, line)
		end
		if self.submitHandler then
			self.submitHandler(line)
		end
	end
	-- Keep focus so you can fire commands back-to-back without re-clicking. Deferred so it
	-- runs after this FocusLost finishes settling.
	task.defer(function()
		if self.box.Parent then
			self.box:CaptureFocus()
		end
	end)
end

-- Older entry (Up arrow). Stashes the current draft on first step back.
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

-- Newer entry (Down arrow). Past the newest entry restores the stashed draft.
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
end

function Input:destroy()
	if self.inputConn then
		self.inputConn:Disconnect()
	end
	self.frame:Destroy()
	table.clear(self.history)
end

return Input
