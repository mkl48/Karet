-- autocomplete logic. command names, arg type autocomplete, flags, last command in a chain

local fw = require("./fwloader")
local Assert = require("./assert")

local Registry = fw.get("Registry")
local Types = fw.get("Types")
local Complete = fw.get("Complete")

local function noop() end

local function rig()
	local r = Registry.new()
	r:register({
		Name = "ban",
		Network = "Shared",
		Args = { { Name = "dur", Types = { "Duration" }, Required = true } },
		Attributes = { { Name = "silent", Short = "s" }, { Name = "permanent", Short = "p" } },
		On = { Shared = noop },
	})
	r:register({ Name = "bandage", Network = "Shared", On = { Shared = noop } })
	r:register({
		Name = "kick",
		Network = "Shared",
		Args = { { Name = "confirm", Types = { "Boolean" } } },
		On = { Shared = noop },
	})
	return Complete.build(r, Types.new())
end

local function set(out)
	local s = {}
	for _, x in out do
		s[x.text] = true
	end
	return s
end

return function(t)
	t.test("command name prefix", function()
		local names = set(rig()("ba"))
		Assert.truthy(names["ban"], "ban")
		Assert.truthy(names["bandage"], "bandage")
	end)

	t.test("no match returns nothing", function()
		Assert.eq(#rig()("zzz"), 0, "empty")
	end)

	t.test("arg autocomplete (duration)", function()
		Assert.truthy(set(rig()("ban "))["30s"], "30s suggested")
	end)

	t.test("arg autocomplete filtered by prefix", function()
		local out = rig()("ban 3")
		Assert.truthy(#out >= 1, "at least one")
		for _, x in out do
			Assert.eq(string.sub(x.text, 1, 1), "3", "starts with 3")
		end
	end)

	t.test("boolean arg suggests true/false", function()
		local vals = set(rig()("kick "))
		Assert.truthy(vals["true"] and vals["false"], "true and false")
	end)

	t.test("flag completion", function()
		local flags = set(rig()("ban 30s -"))
		Assert.truthy(flags["-s"], "-s")
		Assert.truthy(flags["-p"], "-p")
	end)

	t.test("only the last command in a chain", function()
		Assert.truthy(set(rig()("kick true && ba"))["ban"], "completes the second command")
	end)
end
