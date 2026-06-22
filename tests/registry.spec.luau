-- Tests for the command registry: registration, case-insensitive name/alias resolution, the
-- new-shape normalization (top-level Server/Client/Shared -> On, Arg.Type -> Types), batch
-- registration, and structural validation.

local fw = require("./fwloader")
local Assert = require("./assert")

local Registry = fw.get("Registry")

local function noop() end

return function(t)
	t.test("registers and resolves by name (case-insensitive)", function()
		local r = Registry.new()
		r:register({ Name = "Ban", Server = noop, Network = "Server" })
		Assert.truthy(r:get("ban"), "lowercase lookup")
		Assert.truthy(r:get("BAN"), "uppercase lookup")
		Assert.eq(r:get("ban").Name, "Ban", "keeps original Name")
	end)

	t.test("resolves aliases", function()
		local r = Registry.new()
		r:register({ Name = "kick", Aliases = { "k", "boot" }, Server = noop, Network = "Server" })
		Assert.truthy(r:get("k"), "short alias")
		Assert.truthy(r:get("BOOT"), "alias case-insensitive")
	end)

	t.test("list returns sorted names", function()
		local r = Registry.new()
		r:register({ Name = "zed", Shared = noop })
		r:register({ Name = "alpha", Shared = noop })
		Assert.eq(r:list(), { "alpha", "zed" }, "sorted")
	end)

	t.test("normalizes top-level handlers into On", function()
		local r = Registry.new()
		local def = r:register({ Name = "give", Network = "Server", Server = noop })
		Assert.truthy(def.On, "On table built")
		Assert.eq(def.On.Server, noop, "Server handler folded into On.Server")
	end)

	t.test("normalizes Arg.Type into the engine Types array", function()
		local r = Registry.new()
		local def = r:register({
			Name = "echo",
			Network = "Client",
			Args = { { Name = "text", Type = "String", Required = true } },
			Client = noop,
		})
		Assert.eq(def.Args[1].Types, { "String" }, "single Type becomes a one-element Types list")
	end)

	t.test("Arg.Type accepts a list (union) of types", function()
		local r = Registry.new()
		local def = r:register({
			Name = "to",
			Network = "Client",
			Args = { { Name = "where", Type = { "Player", "Vector3" } } },
			Client = noop,
		})
		Assert.eq(def.Args[1].Types, { "Player", "Vector3" }, "Type list passes through as Types")
	end)

	t.test("registerMany isolates a failing def from the batch", function()
		local r = Registry.new()
		local ok, errors = r:registerMany({
			{ Name = "good1", Network = "Client", Client = noop },
			{ Name = "bad", Network = "Server" }, -- no handler -> throws
			{ Name = "good2", Network = "Shared", Shared = noop },
		})
		Assert.eq(ok, { "good1", "good2" }, "the two valid commands registered")
		Assert.eq(#errors, 1, "one failure captured")
		Assert.eq(errors[1].name, "bad", "the bad def is reported by name")
		Assert.truthy(r:get("good2"), "registration continued past the failure")
	end)

	t.test("validation: Context needs both client and server handlers", function()
		local r = Registry.new()
		local ok = pcall(function()
			r:register({ Name = "bridge", Network = "Context", Client = noop })
		end)
		Assert.falsy(ok, "missing Server handler rejected")
	end)

	t.test("validation: a handler is required for the declared realm", function()
		local r = Registry.new()
		local ok = pcall(function()
			r:register({ Name = "broken", Network = "Server", Client = noop })
		end)
		Assert.falsy(ok, "Server command with only a client handler rejected")
	end)
end
