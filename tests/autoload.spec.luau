-- Tests the folder auto-load registration path. Start{ Commands = ... } ultimately funnels a list
-- of command defs through Registry:registerMany (the Instance/require side lives in init.luau and
-- needs a live game, so we exercise the pure batch-registration core here, the same way a folder of
-- command modules that each return a def would land).

local fw = require("./fwloader")
local Assert = require("./assert")

local Registry = fw.get("Registry")

local function noop() end

-- stand-ins for command modules, each "returning" a def table (carrying its own Name)
local function commandModules()
	return {
		{ Name = "ban", Network = "Server", Permission = "Admin", Server = noop, Aliases = { "b" } },
		{ Name = "echo", Network = "Client", Args = { { Name = "text", Type = "String" } }, Client = noop },
		{ Name = "ping", Network = "Shared", Shared = noop },
	}
end

return function(t)
	t.test("registers a batch of command-module defs", function()
		local r = Registry.new()
		local ok, errors = r:registerMany(commandModules())
		Assert.eq(#errors, 0, "no failures")
		Assert.eq(ok, { "ban", "echo", "ping" }, "all three registered, in order")
		Assert.truthy(r:get("ban"), "ban resolves")
		Assert.truthy(r:get("b"), "ban alias resolves")
		Assert.eq(r:get("echo").Args[1].Types, { "String" }, "Type normalized on an auto-loaded def")
	end)

	t.test("one broken module does not sink the rest", function()
		local r = Registry.new()
		local defs = commandModules()
		table.insert(defs, 2, { Name = "broken", Network = "Server" }) -- no handler -> throws
		local ok, errors = r:registerMany(defs)
		Assert.eq(#ok, 3, "the three good commands still registered")
		Assert.eq(#errors, 1, "the broken one is reported")
		Assert.eq(errors[1].name, "broken", "reported by name")
		Assert.truthy(r:get("ping"), "registration continued past the bad def")
		Assert.falsy(r:get("broken"), "the bad def did not register")
	end)

	t.test("an unnamed def is reported, not thrown", function()
		local r = Registry.new()
		local ok, errors = r:registerMany({ { Network = "Shared", Shared = noop } })
		Assert.eq(#ok, 0, "nothing registered")
		Assert.eq(#errors, 1, "the nameless def is captured as an error")
	end)
end
