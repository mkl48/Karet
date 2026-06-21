-- the live HUD: a pinned, always-on overlay of watched expressions. each row shows a label,
-- the current value, and a little sparkline of its recent history. lives on the ScreenGui so
-- it stays visible with the terminal closed (that's the point - glance at @hp while you play).
--
-- this module is just the renderer. the polling (evaluate an expression on an interval and
-- push the value in) is driven from the umbrella, where the shell `run` lives.

local create = require(script.Parent.create)
local Defaults = require(script.Parent.Parent.Defaults)

local Hud = {}
Hud.__index = Hud

local FONT = Defaults.Font

function Hud.new(parent: Instance)
	local self = setmetatable({}, Hud)
	self.palette = nil :: any
	self.rows = {} :: { any }
	self._order = 0

	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, 14),
		Position = UDim2.new(0, 8, 0, 4),
		Font = FONT,
		TextSize = 11,
		Text = "watches",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}) :: TextLabel

	local list = create("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Children = {
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 2),
			}),
			create("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 6),
			}),
		},
	})

	local stroke = create("UIStroke", { Thickness = 1 })
	local container = create("Frame", {
		Name = "KaretHud",
		Visible = false,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 12, 0, 12),
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		ZIndex = 150,
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			stroke,
			title,
			list,
		},
		Parent = parent,
	})

	self.container = container
	self.title = title
	self.stroke = stroke
	self.list = list
	return self
end

function Hud:applyTheme(palette: { [string]: Color3 })
	self.palette = palette
	self.container.BackgroundColor3 = palette.Surface
	self.stroke.Color = palette.Border
	self.title.TextColor3 = palette.Muted
	for _, row in self.rows do
		row.label.TextColor3 = palette.Foreground
	end
end

-- add a row, returns a handle: handle.set(richText) updates it, handle.remove() deletes it.
-- the container shows itself when it has at least one row and hides when empty.
function Hud:addRow(): any
	self._order += 1
	local label = create("TextLabel", {
		Name = "Watch",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		TextSize = 13,
		RichText = true,
		Text = "",
		TextColor3 = self.palette and self.palette.Foreground or Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = self._order,
		ZIndex = 151,
		Parent = self.list,
	}) :: TextLabel

	local row = { label = label }
	table.insert(self.rows, row)
	self.container.Visible = true

	local handle = {}
	function handle.set(richText: string)
		label.Text = richText
	end
	function handle.remove()
		local i = table.find(self.rows, row)
		if i then
			table.remove(self.rows, i)
		end
		label:Destroy()
		if #self.rows == 0 then
			self.container.Visible = false
		end
	end
	return handle
end

function Hud:destroy()
	if self.container then
		self.container:Destroy()
	end
	table.clear(self.rows)
end

return Hud
