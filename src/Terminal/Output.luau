-- The terminal's scrolling output log. Each line is a TextLabel coloured by a semantic
-- theme group (Output / Error / Warn / Info / Success / Comment for echoes), so a theme
-- switch recolours the whole backlog. Lines remember their group, which is what lets
-- applyTheme() re-tint history in place.

local create = require(script.Parent.create)

local Output = {}
Output.__index = Output

export type Line = {
	label: TextLabel,
	group: string, -- a Karet.Theme group name
}

local FONT = Enum.Font.Code
local TEXT_SIZE = 15

function Output.new(parent: Instance)
	local self = setmetatable({}, Output)

	self.lines = {} :: { Line }
	self.palette = nil :: any -- last applied palette, for colouring new lines

	local layout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})

	local frame = create("ScrollingFrame", {
		Name = "Output",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Children = {
			layout,
			create("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
			}),
		},
		Parent = parent,
	}) :: ScrollingFrame

	self.frame = frame
	self.layout = layout

	-- Keep the view pinned to the newest line as content grows.
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		frame.CanvasPosition = Vector2.new(0, layout.AbsoluteContentSize.Y)
	end)

	return self
end

-- Append a line tagged with a theme group (defaults to "Output").
function Output:append(text: string, group: string?)
	local grp = group or "Output"
	local color = self.palette and self.palette[grp] or Color3.new(1, 1, 1)

	local label = create("TextLabel", {
		Name = "Line",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		TextSize = TEXT_SIZE,
		TextColor3 = color,
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = false,
		LayoutOrder = #self.lines + 1,
		Parent = self.frame,
	}) :: TextLabel

	table.insert(self.lines, { label = label, group = grp })
end

-- Append a block of RichText (panels, tables, trees, ...). Not wrapped, so monospaced
-- column/box alignment is preserved; long lines just clip at the edge.
function Output:appendRich(richText: string, group: string?)
	local grp = group or "Output"
	local color = self.palette and self.palette[grp] or Color3.new(1, 1, 1)

	local label = create("TextLabel", {
		Name = "Rich",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		TextSize = TEXT_SIZE,
		TextColor3 = color,
		Text = richText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = false,
		RichText = true,
		LayoutOrder = #self.lines + 1,
		Parent = self.frame,
	}) :: TextLabel

	table.insert(self.lines, { label = label, group = grp })
end

-- A line you can keep rewriting in place (RichText), used by indicators/progress bars.
-- Returns a handle: handle:set(richText) updates it, handle:remove() deletes it.
function Output:appendLive(group: string?)
	local grp = group or "Output"
	local color = self.palette and self.palette[grp] or Color3.new(1, 1, 1)

	local label = create("TextLabel", {
		Name = "LiveLine",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		TextSize = TEXT_SIZE,
		TextColor3 = color,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		LayoutOrder = #self.lines + 1,
		Parent = self.frame,
	}) :: TextLabel

	local entry = { label = label, group = grp }
	table.insert(self.lines, entry)

	local handle = {}
	function handle.set(richText: string)
		label.Text = richText
	end
	function handle.remove()
		local i = table.find(self.lines, entry)
		if i then
			table.remove(self.lines, i)
		end
		label:Destroy()
	end
	return handle
end

function Output:clear()
	for _, line in self.lines do
		line.label:Destroy()
	end
	table.clear(self.lines)
end

-- Recolour the backlog and remember the palette for subsequent lines.
function Output:applyTheme(palette: { [string]: Color3 })
	self.palette = palette
	for _, line in self.lines do
		line.label.TextColor3 = palette[line.group] or palette.Output
	end
end

function Output:destroy()
	self.frame:Destroy()
	table.clear(self.lines)
end

return Output
