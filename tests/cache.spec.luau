-- Tests for the global Cache + Query services (pure logic, no Roblox needed).

local fw = require("./fwloader")
local Assert = require("./assert")

local Cache = fw.get("Cache")
local Query = fw.get("Query")

return function(t)
	t.test("Cache set/get/has/delete", function()
		local c = Cache.new()
		c:Set("a", 1)
		Assert.eq(c:Get("a"), 1, "get")
		Assert.truthy(c:Has("a"), "has")
		c:Delete("a")
		Assert.falsy(c:Has("a"), "deleted")
	end)

	t.test("Cache GetOrSet memoises", function()
		local c = Cache.new()
		local calls = 0
		local function compute()
			calls += 1
			return "v"
		end
		Assert.eq(c:GetOrSet("k", compute), "v", "first computes")
		Assert.eq(c:GetOrSet("k", compute), "v", "second cached")
		Assert.eq(calls, 1, "computed once")
	end)

	t.test("Cache Keys lists live keys", function()
		local c = Cache.new()
		c:Set("x", 1)
		c:Set("y", 2)
		local keys = c:Keys()
		table.sort(keys)
		Assert.eq(keys, { "x", "y" }, "two keys")
	end)

	t.test("Cache Query filters by predicate", function()
		local c = Cache.new()
		c:Set("a", 5)
		c:Set("b", 50)
		c:Set("c", 500)
		local big = c:Query(function(v)
			return v >= 50
		end)
		Assert.eq(big.a, nil, "small excluded")
		Assert.eq(big.b, 50, "b included")
		Assert.eq(big.c, 500, "c included")
	end)

	t.test("Cache Clear empties", function()
		local c = Cache.new()
		c:Set("a", 1)
		c:Clear()
		Assert.eq(#c:Keys(), 0, "empty")
	end)

	t.test("Query register/run/has/list", function()
		local q = Query.new()
		q:Register("double", function(n)
			return n * 2
		end)
		Assert.truthy(q:Has("double"), "registered")
		Assert.eq((q:Run("double", 21)), 42, "ran with arg")
		Assert.eq(q:List(), { "double" }, "listed")
	end)

	t.test("Query unknown name returns an error", function()
		local q = Query.new()
		local result, err = q:Run("nope")
		Assert.eq(result, nil, "no result")
		Assert.truthy(err, "error message")
	end)

	t.test("Query provider error is caught", function()
		local q = Query.new()
		q:Register("boom", function()
			error("kaboom")
		end)
		local result, err = q:Run("boom")
		Assert.eq(result, nil, "no result")
		Assert.truthy(string.find(err, "boom"), "surfaces the error")
	end)
end
