-- Defaults - the one place Karet's tunable constants live, instead of magic numbers
-- scattered across the UI modules. Fonts, text sizes, panel dimensions, animation timings,
-- zoom limits, indicator characters... every surface reads from here, and it's exposed as
-- Karet.Defaults so it's reachable from kav scripts (require the Karet module, read .Defaults)
-- and from the `defaults` command.
--
-- This module uses Roblox datatypes (Enum.Font), so it's engine-only - the headless test
-- suite never loads it (nothing it tests requires this).

local Defaults = {
	-- the monospaced font every Karet surface draws in
	Font = Enum.Font.Code,

	-- the main terminal window
	Terminal = {
		TitleTextSize = 14,
		CornerRadius = 8,
		TitleBarHeight = 24,
		InputRowHeight = 30,
		SeparatorHeight = 1,
		WindowWidth = 640,
		WindowHeight = 340,
	},

	-- the compact single-line command bar
	Compact = {
		BarHeight = 34,
		ResultHeight = 24,
	},

	-- the input row + autocomplete
	Input = {
		TextSize = 15,
		Prompt = "›",
		MaxSuggestions = 8,
	},

	-- the scrolling output log
	Output = {
		TextSize = 15,
		LinePadding = 2,
	},

	-- the Kaveat editor
	Editor = {
		TextSize = 14,
		TopBarHeight = 26,
		TreeWidth = 190,
		OutputHeight = 130,
		TabHeight = 26,
		ModelineHeight = 22,
	},

	-- progress bars / spinners
	Indicator = {
		Width = 24,
		Fill = "█",
		Empty = "─",
		Left = "[",
		Right = "]",
		Spinner = "dots",
		Interval = 0.08,
		Check = "✓",
		Cross = "✗",
	},

	-- the rich-output toolkit
	Render = {
		RuleWidth = 48,
		BarWidth = 24,
	},

	-- ctrl +/- zoom
	Zoom = {
		Min = 0.6,
		Max = 2.0,
		Step = 0.1,
	},

	-- the dangerous-command modal
	Prompt = {
		CardWidth = 360,
		CardHeight = 150,
	},

	-- the repc repeat command
	Repeat = {
		MaxTimes = 10000,
	},
}

return Defaults
