-- the kav module loader bookkeeping (cache + cycle detection + name resolution)

local fw = require("./fwloader")
local Assert = require("./assert")

local KavModules = fw.get("KavModules")

return function(t)
	t.test("a module runs once and its return is cached", function()
		local runs = {}
		local req = KavModules.newRequire({ a = "SRC_A" }, function(source, name)
			runs[name] = (runs[name] or 0) + 1
			return "value:" .. source
		end)
		Assert.eq(req("a"), "value:SRC_A", "returns the module value")
		Assert.eq(req("a"), "value:SRC_A", "second require returns the cached value")
		Assert.eq(runs.a, 1, "ran only once")
	end)

	t.test("a module that returns nothing caches as true", function()
		local req = KavModules.newRequire({ a = "x" }, function()
			return nil
		end)
		Assert.eq(req("a"), true, "nil return becomes true")
	end)

	t.test("unknown module errors", function()
		local req = KavModules.newRequire({}, function()
			return 1
		end)
		local ok, err = pcall(req, "nope")
		Assert.falsy(ok, "errored")
		Assert.truthy(string.find(err, "no kav module"), "names the problem")
	end)

	t.test("name resolution tolerates a .luau suffix either way", function()
		local req1 = KavModules.newRequire({ ["util.luau"] = "U" }, function(s)
			return s
		end)
		Assert.eq(req1("util"), "U", "require without suffix finds util.luau")
		local req2 = KavModules.newRequire({ util = "U" }, function(s)
			return s
		end)
		Assert.eq(req2("util.luau"), "U", "require with suffix finds util")
	end)

	t.test("a require cycle errors instead of looping", function()
		local req
		req = KavModules.newRequire({ a = "A", b = "B" }, function(_source, name)
			-- a requires b, b requires a -> cycle
			if name == "a" then
				return req("b")
			else
				return req("a")
			end
		end)
		local ok, err = pcall(req, "a")
		Assert.falsy(ok, "errored")
		Assert.truthy(string.find(err, "cyclic"), "reports the cycle")
	end)

	t.test("a module can require a sibling that returns cleanly", function()
		local req
		req = KavModules.newRequire({
			helper = "HELPER",
			main = "MAIN",
		}, function(_source, name)
			if name == "helper" then
				return 41
			else
				return req("helper") + 1
			end
		end)
		Assert.eq(req("main"), 42, "main got helper's value")
	end)
end
