-- Headless tests for Karet.Theme's logic (derivation, registry, change signal).
--
-- Theme uses Roblox's Color3, which lune lacks, so we load the module under a minimal
-- Color3 shim. This exercises everything *except* actual rendering — the visual side is
-- verified in Studio. Each test reloads the module fresh, since Theme holds global
-- mutable state (active theme, listeners, registry).

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Assert = require("./assert")

-- Minimal Color3 stand-in: enough for fromHex / new / :Lerp and .R/.G/.B reads.
local Color3 = {}
Color3.__index = Color3

function Color3.new(r: number?, g: number?, b: number?)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end

function Color3.fromHex(h: string)
	h = (h:gsub("#", ""))
	return Color3.new(
		tonumber(h:sub(1, 2), 16) / 255,
		tonumber(h:sub(3, 4), 16) / 255,
		tonumber(h:sub(5, 6), 16) / 255
	)
end

function Color3:Lerp(other, t: number)
	return Color3.new(self.R + (other.R - self.R) * t, self.G + (other.G - self.G) * t, self.B + (other.B - self.B) * t)
end

local SOURCE = fs.readFile("src/Theme/init.luau")

-- Load a fresh Theme module plus the list it will warn into.
local function load(): (any, { string })
	local warnings: { string } = {}
	local chunk = luau.load(SOURCE, {
		debugName = "Theme",
		environment = {
			Color3 = Color3,
			warn = function(msg: string)
				table.insert(warnings, msg)
			end,
		},
	})
	return chunk(), warnings
end

local function isColor(v: any): boolean
	return type(v) == "table" and type(v.R) == "number" and type(v.G) == "number" and type(v.B) == "number"
end

return function(t)
	t.test("derive fills every declared group from a minimal palette", function()
		local Theme = load()
		Theme.Set({ Background = Color3.fromHex("000000"), Foreground = Color3.fromHex("ffffff") })
		local palette = Theme.Get()
		for _, group in Theme.Groups() do
			Assert.truthy(isColor(palette[group]), `group '{group}' resolved to a colour`)
		end
	end)

	t.test("Define returns a complete resolved palette and registers it", function()
		local Theme = load()
		local resolved = Theme.Define("mono", { Background = Color3.fromHex("101010") })
		Assert.truthy(isColor(resolved.Accent), "missing Accent was derived")
		Assert.truthy(table.find(Theme.List(), "mono"), "theme registered")
	end)

	t.test("author-supplied groups survive derivation untouched", function()
		local Theme = load()
		local red = Color3.fromHex("ff0000")
		Theme.Set({ Background = Color3.fromHex("000000"), Foreground = Color3.fromHex("ffffff"), Error = red })
		Assert.eq(Theme.Get("Error"), red, "Error kept the supplied colour")
	end)

	t.test("built-in themes are registered and exposed as values", function()
		local Theme = load()
		for _, name in { "tokyonight", "gruvbox", "catppuccin", "nord" } do
			Assert.truthy(table.find(Theme.List(), name), `{name} is registered`)
		end
		Assert.truthy(isColor(Theme.Tokyonight.Background), "Theme.Tokyonight is a palette value")
		Assert.eq(Theme.Name(), "tokyonight", "defaults to tokyonight")
	end)

	t.test("Set by name switches the active theme", function()
		local Theme = load()
		Theme.Set("gruvbox")
		Assert.eq(Theme.Name(), "gruvbox", "active name updated")
		Assert.eq(Theme.Get("Background"), Color3.fromHex("282828"), "active palette is gruvbox")
	end)

	t.test("Set by raw palette clears the active name", function()
		local Theme = load()
		Theme.Set({ Background = Color3.fromHex("123456"), Foreground = Color3.fromHex("ffffff") })
		Assert.eq(Theme.Name(), nil, "no name for an inline palette")
	end)

	t.test("Set with an unknown name errors", function()
		local Theme = load()
		local ok = pcall(Theme.Set, "does-not-exist")
		Assert.falsy(ok, "unknown theme name rejected")
	end)

	t.test("Get with an invalid group errors", function()
		local Theme = load()
		local ok = pcall(Theme.Get, "Nonsense")
		Assert.falsy(ok, "unknown group rejected")
	end)

	t.test("unknown groups in Define warn but do not throw", function()
		local Theme, warnings = load()
		Theme.Define("typo", { Backgound = Color3.fromHex("000000") } :: any)
		local warned = false
		for _, w in warnings do
			if w:find("unknown group") then
				warned = true
			end
		end
		Assert.truthy(warned, "an unknown group was warned about")
	end)

	t.test("OnChanged fires immediately and on every Set", function()
		local Theme = load()
		local calls = 0
		local lastName: string? = "<unset>"
		local unsubscribe = Theme.OnChanged(function(_, name)
			calls += 1
			lastName = name
		end)
		Assert.eq(calls, 1, "fired immediately on subscribe")
		Theme.Set("nord")
		Assert.eq(calls, 2, "fired again on Set")
		Assert.eq(lastName, "nord", "passed the new theme name")
		unsubscribe()
		Theme.Set("gruvbox")
		Assert.eq(calls, 2, "no fire after unsubscribe")
	end)

	t.test("redefining the active theme recolors live", function()
		local Theme = load()
		Theme.Set("tokyonight")
		local seen: any = nil
		Theme.OnChanged(function(palette)
			seen = palette.Background
		end)
		local newBg = Color3.fromHex("abcdef")
		Theme.Define("tokyonight", { Background = newBg, Foreground = Color3.fromHex("ffffff") })
		Assert.eq(seen, newBg, "listener saw the redefined background")
		Assert.eq(Theme.Get("Background"), newBg, "active palette updated in place")
	end)
end
