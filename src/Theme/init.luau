-- Karet.Theme - one semantic colorscheme, piped through every surface (DESIGN → Theme).
--
-- A theme is NOT a set of raw frame colors; it is a set of *semantic highlight groups*
-- (Background, String, Error, Accent, ...), exactly like a Neovim colorscheme. Every
-- Karet surface - terminal, Kaveat editor, autocomplete ghost text, pickers, windows -
-- reads its colors from these groups, so `Theme.Set("gruvbox")` recolors the whole UI at
-- once, the way `:colorscheme` does in Neovim.
--
-- Authors may define a *partial* palette: any group left out is derived from the ones
-- present (e.g. Surface lightens Background, Prompt follows Accent), so a minimal theme
-- still produces a complete, coherent palette. Surfaces subscribe via Theme.OnChanged to
-- recolor live when the active theme switches.
--
-- This module uses Roblox datatypes (Color3) and is intended to run in-engine; the
-- headless lune test suite loads only src/Shell, so it never imports this file.

local Theme = {}

-- The full set of semantic groups. Adding a member here makes it themable everywhere;
-- the deriver (below) must know how to fill it when an author omits it.
export type Group =
	-- surfaces & chrome
	"Background" -- the terminal/editor base
	| "Surface" -- raised panels: pickers, popups, status line
	| "Overlay" -- the topmost layer: tooltips, floating pickers
	| "Foreground" -- primary text
	| "Muted" -- de-emphasised text, line numbers, separators
	| "Border" -- outlines, dividers
	| "Selection" -- selected-text background
	| "Cursor" -- the caret
	| "CursorLine" -- current-line highlight
	-- accents
	| "Accent" -- primary accent: prompt, active border, brand
	| "AccentAlt" -- secondary accent
	-- syntax (shared by the shell grammar and Kaveat's Luau)
	| "Command" -- a resolved command word
	| "Keyword" -- language keywords / guard words
	| "String"
	| "Number"
	| "Boolean"
	| "Comment"
	| "Operator" -- + - * / && || == ...
	| "Punctuation" -- ( ) { } , . sigils
	| "Variable" -- @x
	| "Reference" -- /Player, //
	| "Type" -- @TYPE[...] and type names
	| "Flag" -- -s, --Dry-Run
	| "Field" -- .prop / table fields
	| "Function" -- function names (Luau)
	-- diagnostics & status
	| "Error"
	| "Warn"
	| "Info"
	| "Hint"
	| "Success"
	-- terminal roles
	| "Prompt" -- the prompt sigil
	| "Ghost" -- autocomplete ghost / inline suggestion text
	| "Match" -- fuzzy-match highlight in completion lists
	| "Output" -- normal command output text

export type Palette = { [Group]: Color3 }

-- The canonical ordered list of every group, so the deriver and validators can iterate.
local GROUPS: { Group } = {
	"Background",
	"Surface",
	"Overlay",
	"Foreground",
	"Muted",
	"Border",
	"Selection",
	"Cursor",
	"CursorLine",
	"Accent",
	"AccentAlt",
	"Command",
	"Keyword",
	"String",
	"Number",
	"Boolean",
	"Comment",
	"Operator",
	"Punctuation",
	"Variable",
	"Reference",
	"Type",
	"Flag",
	"Field",
	"Function",
	"Error",
	"Warn",
	"Info",
	"Hint",
	"Success",
	"Prompt",
	"Ghost",
	"Match",
	"Output",
}

local GROUP_SET: { [string]: boolean } = {}
for _, g in GROUPS do
	GROUP_SET[g] = true
end

-- ---------------------------------------------------------------------------
-- colour helpers
-- ---------------------------------------------------------------------------

local hex = Color3.fromHex
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

-- Mix two colours; t = 0 keeps a, t = 1 keeps b.
local function mix(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

local function lighten(c: Color3, t: number): Color3
	return mix(c, WHITE, t)
end

local function darken(c: Color3, t: number): Color3
	return mix(c, BLACK, t)
end

-- A rough perceived luminance, used to decide whether to lighten or darken so the same
-- derivation rule reads well on both dark and light themes.
local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

-- Nudge a colour *away* from the background (lighter on dark themes, darker on light),
-- e.g. for raised surfaces and current-line highlights.
local function raise(base: Color3, bg: Color3, t: number): Color3
	if luminance(bg) < 0.5 then
		return lighten(base, t)
	end
	return darken(base, t)
end

-- ---------------------------------------------------------------------------
-- derivation: fill a partial palette into a complete one
-- ---------------------------------------------------------------------------

-- Hard fallbacks for the three load-bearing groups, so even Theme.Define("x", {})
-- yields a usable (Tokyonight-ish) palette rather than erroring.
local FALLBACK_BG = hex("1a1b26")
local FALLBACK_FG = hex("c0caf5")
local FALLBACK_ACCENT = hex("7aa2f7")

-- Resolve a partial palette into a complete one. Every group not supplied is derived
-- from supplied groups (or other derived ones, computed in dependency order below).
local function derive(p: Palette): Palette
	local out: Palette = {}
	-- pick(group, fallback) returns the author's colour if present, else the fallback.
	local function pick(group: Group, fallback: Color3): Color3
		local given = p[group]
		if given ~= nil then
			out[group] = given
			return given
		end
		out[group] = fallback
		return fallback
	end

	-- Core three first - everything else can lean on them.
	local bg = pick("Background", FALLBACK_BG)
	local fg = pick("Foreground", FALLBACK_FG)
	local accent = pick("Accent", FALLBACK_ACCENT)

	-- surfaces & chrome
	local surface = pick("Surface", raise(bg, bg, 0.06))
	pick("Overlay", raise(surface, bg, 0.06))
	local muted = pick("Muted", mix(fg, bg, 0.45))
	pick("Border", mix(muted, bg, 0.35))
	pick("Selection", mix(bg, accent, 0.3))
	pick("Cursor", accent)
	pick("CursorLine", raise(bg, bg, 0.04))

	-- accents
	pick("AccentAlt", p.AccentAlt or accent)

	-- diagnostics & status (sensible defaults; themes usually override these)
	local err = pick("Error", hex("f7768e"))
	local warn = pick("Warn", hex("e0af68"))
	pick("Info", hex("7aa2f7"))
	pick("Hint", hex("1abc9c"))
	local success = pick("Success", hex("9ece6a"))

	-- syntax
	local keyword = pick("Keyword", hex("bb9af7"))
	pick("String", success)
	pick("Number", hex("ff9e64"))
	pick("Boolean", warn)
	pick("Comment", muted)
	local operator = pick("Operator", mix(fg, accent, 0.4))
	pick("Punctuation", muted)
	pick("Variable", accent)
	pick("Reference", keyword)
	pick("Type", p.Type or keyword)
	pick("Flag", warn)
	pick("Field", accent)
	pick("Function", p.Function or accent)
	pick("Command", p.Command or accent)
	-- Operator is also a convenient base if no AccentAlt was given.
	out["Operator"] = operator

	-- terminal roles
	pick("Prompt", accent)
	pick("Ghost", muted)
	pick("Match", accent)
	pick("Output", fg)

	return out
end

-- ---------------------------------------------------------------------------
-- registry + active theme + change signal
-- ---------------------------------------------------------------------------

local registry: { [string]: Palette } = {}
local activeName: string? = nil
local active: Palette = derive({}) -- never nil; replaced by Set

local listeners: { (Palette, string?) -> () } = {}

local function emit()
	for _, fn in listeners do
		local ok, err = pcall(fn, active, activeName)
		if not ok then
			warn(`Karet.Theme: a change listener errored - {err}`)
		end
	end
end

-- Validate author keys, warning (not erroring) on unknown groups so a typo is visible
-- without breaking the game.
local function validate(name: string, palette: Palette)
	for key in palette do
		if not GROUP_SET[key] then
			warn(`Karet.Theme: theme '{name}' has unknown group '{tostring(key)}' (ignored)`)
		end
	end
end

-- Define (or redefine) a named theme from a partial palette. Returns the *resolved*
-- complete palette so callers can pass it straight to Set or inspect it.
function Theme.Define(name: string, palette: Palette): Palette
	assert(type(name) == "string" and name ~= "", "Karet.Theme.Define: name must be a non-empty string")
	validate(name, palette)
	local resolved = derive(palette)
	registry[name] = resolved
	-- If the active theme was just redefined, recolor live.
	if activeName == name then
		active = resolved
		emit()
	end
	return resolved
end

-- Set the active theme by name or by an explicit (partial) palette. Switching fires
-- OnChanged so every subscribed surface recolors at once.
function Theme.Set(theme: string | Palette)
	if type(theme) == "string" then
		local resolved = registry[theme]
		if not resolved then
			error(`Karet.Theme.Set: no theme named '{theme}' (define it first)`, 2)
		end
		active = resolved
		activeName = theme
	else
		active = derive(theme)
		activeName = nil
	end
	emit()
end

-- Read the active palette, or a single group's colour. Theme.Get() -> full palette;
-- Theme.Get("Error") -> Color3.
function Theme.Get(group: Group?): any
	if group == nil then
		return active
	end
	local color = active[group]
	if color == nil then
		error(`Karet.Theme.Get: '{tostring(group)}' is not a theme group`, 2)
	end
	return color
end

-- The name of the active theme, or nil if a raw palette was Set directly.
function Theme.Name(): string?
	return activeName
end

-- Names of all defined themes.
function Theme.List(): { string }
	local names = {}
	for name in registry do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- The canonical list of group names (a copy, so callers can't mutate the source).
function Theme.Groups(): { Group }
	return table.clone(GROUPS)
end

-- Subscribe to theme changes; the callback fires immediately with the current theme and
-- again on every Set/redefine. Returns an unsubscribe function.
function Theme.OnChanged(fn: (Palette, string?) -> ()): () -> ()
	table.insert(listeners, fn)
	fn(active, activeName)
	return function()
		local i = table.find(listeners, fn)
		if i then
			table.remove(listeners, i)
		end
	end
end

-- ---------------------------------------------------------------------------
-- built-in palettes - Neovim ports, so Karet feels at home out of the box.
-- Each is Define()d at load and also exposed as a value (Theme.Tokyonight) so it can be
-- passed straight to Karet.Start{ Theme = Karet.Theme.Tokyonight }.
-- ---------------------------------------------------------------------------

local BUILTINS: { [string]: Palette } = {
	-- Tokyonight (night) - https://github.com/folke/tokyonight.nvim
	tokyonight = {
		Background = hex("1a1b26"),
		Surface = hex("24283b"),
		Foreground = hex("c0caf5"),
		Muted = hex("565f89"),
		Accent = hex("7aa2f7"),
		AccentAlt = hex("bb9af7"),
		Comment = hex("565f89"),
		String = hex("9ece6a"),
		Number = hex("ff9e64"),
		Keyword = hex("bb9af7"),
		Function = hex("7aa2f7"),
		Type = hex("2ac3de"),
		Operator = hex("89ddff"),
		Error = hex("f7768e"),
		Warn = hex("e0af68"),
		Info = hex("7aa2f7"),
		Hint = hex("1abc9c"),
		Success = hex("9ece6a"),
		Selection = hex("283457"),
	},

	-- Gruvbox (dark, medium) - https://github.com/morhetz/gruvbox
	gruvbox = {
		Background = hex("282828"),
		Surface = hex("3c3836"),
		Foreground = hex("ebdbb2"),
		Muted = hex("928374"),
		Accent = hex("83a598"),
		AccentAlt = hex("d3869b"),
		Comment = hex("928374"),
		String = hex("b8bb26"),
		Number = hex("d3869b"),
		Keyword = hex("fb4934"),
		Function = hex("b8bb26"),
		Type = hex("fabd2f"),
		Operator = hex("8ec07c"),
		Error = hex("fb4934"),
		Warn = hex("fabd2f"),
		Info = hex("83a598"),
		Hint = hex("8ec07c"),
		Success = hex("b8bb26"),
		Selection = hex("504945"),
	},

	-- Catppuccin (Mocha) - https://github.com/catppuccin/catppuccin
	catppuccin = {
		Background = hex("1e1e2e"),
		Surface = hex("313244"),
		Foreground = hex("cdd6f4"),
		Muted = hex("6c7086"),
		Accent = hex("89b4fa"),
		AccentAlt = hex("cba6f7"),
		Comment = hex("6c7086"),
		String = hex("a6e3a1"),
		Number = hex("fab387"),
		Keyword = hex("cba6f7"),
		Function = hex("89b4fa"),
		Type = hex("f9e2af"),
		Operator = hex("89dceb"),
		Error = hex("f38ba8"),
		Warn = hex("f9e2af"),
		Info = hex("89b4fa"),
		Hint = hex("94e2d5"),
		Success = hex("a6e3a1"),
		Selection = hex("45475a"),
	},

	-- Nord - https://www.nordtheme.com
	nord = {
		Background = hex("2e3440"),
		Surface = hex("3b4252"),
		Foreground = hex("d8dee9"),
		Muted = hex("616e88"),
		Accent = hex("88c0d0"),
		AccentAlt = hex("b48ead"),
		Comment = hex("616e88"),
		String = hex("a3be8c"),
		Number = hex("b48ead"),
		Keyword = hex("81a1c1"),
		Function = hex("88c0d0"),
		Type = hex("8fbcbb"),
		Operator = hex("81a1c1"),
		Error = hex("bf616a"),
		Warn = hex("ebcb8b"),
		Info = hex("5e81ac"),
		Hint = hex("8fbcbb"),
		Success = hex("a3be8c"),
		Selection = hex("434c5e"),
	},
}

Theme.Tokyonight = Theme.Define("tokyonight", BUILTINS.tokyonight)
Theme.Gruvbox = Theme.Define("gruvbox", BUILTINS.gruvbox)
Theme.Catppuccin = Theme.Define("catppuccin", BUILTINS.catppuccin)
Theme.Nord = Theme.Define("nord", BUILTINS.nord)

-- Sensible default so Theme.Get() is always meaningful before Karet.Start runs.
Theme.Set("tokyonight")

return Theme
