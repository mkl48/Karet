-- Built-in commands, run end-to-end through the real Parser + Evaluator + Host with
-- stubbed services (so no terminal/theme/Roblox is needed).

local shell = require("./loader")
local fw = require("./fwloader")
local Assert = require("./assert")

local Parser = shell.get("Parser")
local Evaluator = shell.get("Evaluator")
local Registry = fw.get("Registry")
local Types = fw.get("Types")
local Host = fw.get("Host")
local Commands = fw.get("Commands")

-- Build a rig with the built-ins registered and stub services.
local function rig()
	local registry = Registry.new()
	local state = { cleared = false, theme = nil :: string? }
	local services = {
		clear = function()
			state.cleared = true
		end,
		setTheme = function(name)
			state.theme = name
		end,
		listThemes = function()
			return { "tokyonight", "gruvbox" }
		end,
		list = function()
			return registry:list()
		end,
		get = function(name)
			return registry:get(name)
		end,
		playerName = function()
			return "Tester"
		end,
		version = "9.9.9",
	}
	for _, def in Commands.build(services) do
		registry:register(def)
	end

	local out = {}
	local host = Host.new({
		registry = registry,
		types = Types.new(),
		isClient = true,
		sink = function(group, message)
			table.insert(out, { group = group, message = message })
		end,
		hooks = { pre = {}, post = {}, onErr = {} },
		auth = { defaultRole = "User", allowed = {}, denied = {} },
	})
	local ev = Evaluator.new(host)
	return {
		run = function(line)
			return ev:run(Parser.parse(line).ast)
		end,
		out = out,
		state = state,
	}
end

local function joined(out: { any }): string
	local parts = {}
	for _, line in out do
		table.insert(parts, line.message)
	end
	return table.concat(parts, "\n")
end

return function(t)
	t.test("version prints the injected version", function()
		local k = rig()
		k.run("version")
		Assert.eq(k.out[1].message, "Karet v9.9.9", "version output")
	end)

	t.test("echo prints its argument", function()
		local k = rig()
		k.run("echo hello")
		Assert.eq(k.out[1].message, "hello", "echoed")
	end)

	t.test("me uses playerName service", function()
		local k = rig()
		k.run("me")
		Assert.eq(k.out[1].message, "Tester", "name")
	end)

	t.test("ping pongs and returns", function()
		local k = rig()
		local result = k.run("ping")
		Assert.eq(k.out[1].message, "pong", "printed")
		Assert.truthy(result.ok, "ok")
	end)

	t.test("clear calls the clear service", function()
		local k = rig()
		k.run("clear")
		Assert.truthy(k.state.cleared, "clear ran")
	end)

	t.test("theme switches via the setTheme service", function()
		local k = rig()
		k.run("theme gruvbox")
		Assert.eq(k.state.theme, "gruvbox", "theme set")
		Assert.truthy(string.find(joined(k.out), "gruvbox"), "confirmation printed")
	end)

	t.test("themes lists available themes", function()
		local k = rig()
		k.run("themes")
		Assert.truthy(string.find(k.out[1].message, "tokyonight"), "lists tokyonight")
	end)

	t.test("help with no arg lists commands", function()
		local k = rig()
		k.run("help")
		Assert.truthy(string.find(joined(k.out), "echo"), "mentions a command")
	end)

	t.test("help <command> shows details", function()
		local k = rig()
		k.run("help echo")
		Assert.truthy(string.find(joined(k.out), "echo"), "names the command")
		Assert.truthy(string.find(joined(k.out), "text"), "shows the arg")
	end)

	t.test("aliases resolve (cls -> clear)", function()
		local k = rig()
		k.run("cls")
		Assert.truthy(k.state.cleared, "alias ran clear")
	end)
end
