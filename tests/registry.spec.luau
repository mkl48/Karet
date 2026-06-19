-- Tests for the command registry: registration, case-insensitive name/alias resolution,
-- the fluent builder, and structural validation.

local fw = require("./fwloader")
local Assert = require("./assert")

local Registry = fw.get("Registry")

local function noop() end

return function(t)
	t.test("registers and resolves by name (case-insensitive)", function()
		local r = Registry.new()
		r:register({ Name = "Ban", On = { Server = noop }, Network = "Server" })
		Assert.truthy(r:get("ban"), "lowercase lookup")
		Assert.truthy(r:get("BAN"), "uppercase lookup")
		Assert.eq(r:get("ban").Name, "Ban", "keeps original Name")
	end)

	t.test("resolves aliases", function()
		local r = Registry.new()
		r:register({ Name = "kick", Aliases = { "k", "boot" }, On = { Server = noop }, Network = "Server" })
		Assert.truthy(r:get("k"), "short alias")
		Assert.truthy(r:get("BOOT"), "alias case-insensitive")
	end)

	t.test("list returns sorted names", function()
		local r = Registry.new()
		r:register({ Name = "zed", On = { Shared = noop } })
		r:register({ Name = "alpha", On = { Shared = noop } })
		Assert.eq(r:list(), { "alpha", "zed" }, "sorted")
	end)

	t.test("builder accumulates and registers", function()
		local r = Registry.new()
		r:command("give")
			:Alias("g")
			:Description("give an item")
			:Network("Server")
			:Arg({ Name = "item", Types = { "String" }, Required = true })
			:Attribute({ Name = "silent", Short = "s" })
			:On("Server", noop)
			:Register()
		local def = r:get("g")
		Assert.truthy(def, "registered via builder")
		Assert.eq(def.Name, "give", "name")
		Assert.eq(#def.Args, 1, "one arg")
		Assert.eq(def.Args[1].Name, "item", "arg name")
	end)

	t.test("validation: Context needs both client and server handlers", function()
		local r = Registry.new()
		local ok = pcall(function()
			r:register({ Name = "bridge", Network = "Context", On = { Client = noop } })
		end)
		Assert.falsy(ok, "missing On.Server rejected")
	end)

	t.test("validation: a handler is required for the declared realm", function()
		local r = Registry.new()
		local ok = pcall(function()
			r:register({ Name = "broken", Network = "Server", On = { Client = noop } })
		end)
		Assert.falsy(ok, "Server command with only a client handler rejected")
	end)
end
