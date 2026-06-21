-- transient toast notifications. a corner stack of little cards that fade in, sit for a few
-- seconds, then fade out. lives on the ScreenGui (not the window) so toasts still show when
-- the terminal is closed. themed by the same semantic groups as the output log.

local TweenService = game:GetService("TweenService")

local create = require(script.Parent.create)
local Defaults = require(script.Parent.Parent.Defaults)

local Toaster = {}
Toaster.__index = Toaster

local FONT = Defaults.Font
local CFG = Defaults.Toast

function Toaster.new(parent: Instance)
	local self = setmetatable({}, Toaster)
	self.palette = nil :: any
	self.cards = {} :: { any }

	-- top-right column. AutomaticSize grows it to fit the stack; high ZIndex floats it over
	-- the window and anything else Karet draws.
	local container = create("Frame", {
		Name = "KaretToasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(CFG.Width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 200,
		Children = {
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, CFG.Gap),
			}),
		},
		Parent = parent,
	})
	self.container = container
	return self
end

function Toaster:applyTheme(palette: { [string]: Color3 })
	self.palette = palette
	for _, card in self.cards do
		self:colorCard(card)
	end
end

function Toaster:colorCard(card: any)
	local p = self.palette
	if not p then
		return
	end
	card.frame.BackgroundColor3 = p.Surface
	card.stroke.Color = p[card.group] or p.Border
	card.accent.BackgroundColor3 = p[card.group] or p.Accent
	card.title.TextColor3 = p[card.group] or p.Accent
	card.body.TextColor3 = p.Foreground
end

-- opts: { group = "Output"|"Error"|..., title = string?, duration = number? }
function Toaster:push(text: string, opts: { [string]: any }?)
	opts = opts or {}
	local group = opts.group or "Output"
	local nextOrder = (self._order or 0) + 1
	self._order = nextOrder

	local stroke = create("UIStroke", { Thickness = 1, Transparency = 1 })
	-- a coloured spine down the left edge, group-tinted
	local accent = create("Frame", {
		Name = "Accent",
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundTransparency = 1,
	})
	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.new(0, 12, 0, 8),
		Font = FONT,
		TextSize = 13,
		Text = opts.title or "karet",
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}) :: TextLabel
	local body = create("TextLabel", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 0),
		Position = UDim2.new(0, 12, 0, 26),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		TextSize = 14,
		Text = text,
		TextTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}) :: TextLabel

	local frame = create("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder,
		ZIndex = 200,
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10) }),
			stroke,
			accent,
			title,
			body,
		},
		Parent = self.container,
	})

	local card = { frame = frame, stroke = stroke, accent = accent, title = title, body = body, group = group }
	self:colorCard(card)
	table.insert(self.cards, card)

	-- evict the oldest if we've stacked too many
	while #self.cards > CFG.Max do
		self:dismiss(self.cards[1])
	end

	-- fade in
	local info = TweenInfo.new(CFG.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	frame.BackgroundTransparency = 1
	TweenService:Create(frame, info, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(stroke, info, { Transparency = 0 }):Play()
	TweenService:Create(title, info, { TextTransparency = 0 }):Play()
	TweenService:Create(body, info, { TextTransparency = 0 }):Play()
	TweenService:Create(accent, info, { BackgroundTransparency = 0 }):Play()

	-- auto dismiss after its time, unless someone already removed it
	local duration = opts.duration or CFG.Duration
	task.delay(duration, function()
		if card.frame and card.frame.Parent then
			self:dismiss(card)
		end
	end)

	return card
end

function Toaster:dismiss(card: any)
	local i = table.find(self.cards, card)
	if i then
		table.remove(self.cards, i)
	end
	local frame = card.frame
	if not (frame and frame.Parent) then
		return
	end
	local info = TweenInfo.new(CFG.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(card.stroke, info, { Transparency = 1 }):Play()
	TweenService:Create(card.title, info, { TextTransparency = 1 }):Play()
	TweenService:Create(card.body, info, { TextTransparency = 1 }):Play()
	TweenService:Create(card.accent, info, { BackgroundTransparency = 1 }):Play()
	task.delay(CFG.FadeTime, function()
		if frame then
			frame:Destroy()
		end
	end)
end

function Toaster:destroy()
	if self.container then
		self.container:Destroy()
	end
	table.clear(self.cards)
end

return Toaster
