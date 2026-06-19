-- Tests for the argument type system: primitive coercion, union ordering, custom types,
-- and @TYPE satisfaction. Roblox-backed types (Player/Team/...) need a live game and are
-- verified in Studio, not here.

local fw = require("./fwloader")
local Assert = require("./assert")

local Types = fw.get("Types")

return function(t)
	t.test("Number parses strings and rejects non-numbers", function()
		local types = Types.new()
		local v = types:coerce("5", { "Number" })
		Assert.eq(v, 5, "string -> number")
		local bad, err = types:coerce("abc", { "Number" })
		Assert.eq(bad, nil, "nil on failure")
		Assert.truthy(err, "an error message")
	end)

	t.test("union is tried left-to-right, first match wins", function()
		local types = Types.new()
		Assert.eq(types:coerce("5", { "Number", "String" }), 5, "Number wins for a numeric token")
		Assert.eq(types:coerce("abc", { "Number", "String" }), "abc", "falls through to String")
	end)

	t.test("Integer rejects fractionals", function()
		local types = Types.new()
		Assert.eq(types:coerce("5", { "Integer" }), 5, "whole number ok")
		local bad = types:coerce("5.5", { "Integer" })
		Assert.eq(bad, nil, "fractional rejected")
	end)

	t.test("Boolean parses a rich set of spellings", function()
		local types = Types.new()
		Assert.eq(types:coerce("true", { "Boolean" }), true, "true")
		Assert.eq(types:coerce("false", { "Boolean" }), false, "false")
		Assert.eq(types:coerce("yes", { "Boolean" }), true, "yes")
		Assert.eq(types:coerce("on", { "Boolean" }), true, "on")
		Assert.eq(types:coerce("n", { "Boolean" }), false, "n")
		Assert.eq(types:coerce("+", { "Boolean" }), true, "+")
		local bad = types:coerce("maybe", { "Boolean" })
		Assert.eq(bad, nil, "non-boolean rejected")
	end)

	t.test("Duration parses units, compounds, and bare seconds", function()
		local types = Types.new()
		Assert.eq(types:coerce("30s", { "Duration" }), 30, "seconds")
		Assert.eq(types:coerce("5m", { "Duration" }), 300, "minutes")
		Assert.eq(types:coerce("1h", { "Duration" }), 3600, "hours")
		Assert.eq(types:coerce("2d", { "Duration" }), 172800, "days")
		Assert.eq(types:coerce("1w", { "Duration" }), 604800, "weeks")
		Assert.eq(types:coerce("1h30m", { "Duration" }), 5400, "compound h+m")
		Assert.eq(types:coerce("90", { "Duration" }), 90, "bare seconds")
		Assert.eq(types:coerce("5x", { "Duration" }), nil, "unknown unit rejected")
	end)

	t.test("custom DefineType participates in coercion", function()
		local types = Types.new()
		types:Define("Shout", {
			Parse = function(raw)
				return string.upper(tostring(raw)), nil
			end,
			Validate = function(v)
				return type(v) == "string" or "expected text"
			end,
		})
		Assert.eq(types:coerce("hi", { "Shout" }), "HI", "custom Parse ran")
	end)

	t.test("satisfies answers type guards", function()
		local types = Types.new()
		Assert.truthy(types:satisfies(5, "Number"), "5 is a Number")
		Assert.falsy(types:satisfies("x", "Number"), "string is not a Number")
		Assert.truthy(types:satisfies(5, "Integer"), "5 is an Integer")
		Assert.falsy(types:satisfies(5.5, "Integer"), "5.5 is not an Integer")
		Assert.falsy(types:satisfies(5, "Nonexistent"), "unknown type -> false")
	end)
end
