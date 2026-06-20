-- the editor luau completer. globals, members after . / :, buffer symbols, class methods

local fw = require("./fwloader")
local Assert = require("./assert")

local KC = fw.get("KaveatComplete")

local function set(out)
	local s = {}
	for _, x in out do
		s[x.text] = true
	end
	return s
end

return function(t)
	t.test("member access on a known global", function()
		local s = set(KC.complete("game.", 6))
		Assert.truthy(s["GetService"], "GetService")
	end)

	t.test("method access on an unknown base falls back to instance methods", function()
		local s = set(KC.complete("part:", 6))
		Assert.truthy(s["FindFirstChild"], "FindFirstChild")
		Assert.truthy(s["WaitForChild"], "WaitForChild")
	end)

	t.test("locals from the buffer", function()
		local src = "local myvar = 5\nmyv"
		Assert.truthy(set(KC.complete(src, #src + 1))["myvar"], "myvar")
	end)

	t.test("class methods you define", function()
		local src = "function Car:Drive() end\nCar:"
		Assert.truthy(set(KC.complete(src, #src + 1))["Drive"], "Drive")
	end)

	t.test("globals and keywords by prefix", function()
		Assert.truthy(set(KC.complete("tas", 4))["task"], "task")
		Assert.truthy(set(KC.complete("fu", 3))["function"], "function keyword")
	end)

	t.test("nothing when theres no word", function()
		Assert.eq(#KC.complete("  ", 3), 0, "empty")
	end)
end
