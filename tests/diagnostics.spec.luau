-- the heuristic Luau checker behind the editor's :check

local fw = require("./fwloader")
local Assert = require("./assert")

local Diagnostics = fw.get("Diagnostics")

local function check(src: string)
	return Diagnostics.check(src)
end

local function messages(src: string): string
	local parts = {}
	for _, d in check(src) do
		table.insert(parts, d.message)
	end
	return table.concat(parts, " | ")
end

return function(t)
	t.test("clean code yields no diagnostics", function()
		Assert.eq(#check("local function f(a, b)\n  return a + b\nend"), 0, "balanced function is clean")
	end)

	t.test("for / while loops balance via their do", function()
		Assert.eq(#check("for i = 1, 3 do\n  print(i)\nend"), 0, "for...do...end clean")
		Assert.eq(#check("while true do break end"), 0, "while...do...end clean")
	end)

	t.test("missing end is reported", function()
		local d = check("if x then\n  print(1)")
		Assert.truthy(#d >= 1, "flagged")
		Assert.truthy(string.find(messages("if x then print(1)"), "missing 'end'"), "names the cause")
	end)

	t.test("extra end is reported", function()
		Assert.truthy(string.find(messages("do end end"), "unexpected 'end'"), "extra end flagged")
	end)

	t.test("unbalanced parentheses are reported with the open line", function()
		local d = check("print((1)")
		Assert.truthy(#d >= 1, "flagged")
		Assert.truthy(string.find(messages("print((1)"), "unclosed '%('"), "names the unclosed paren")
	end)

	t.test("a stray closer is reported", function()
		Assert.truthy(string.find(messages("print(1))"), "unexpected '%)'"), "stray ) flagged")
	end)

	t.test("mismatched bracket kinds are reported", function()
		Assert.truthy(string.find(messages("foo(]"), "doesn't match"), "(] mismatch flagged")
	end)

	t.test("unterminated string is reported", function()
		Assert.truthy(string.find(messages('local s = "abc'), "unterminated string"), "open string flagged")
	end)

	t.test("keywords inside strings and comments are ignored", function()
		Assert.eq(#check('local s = "if then end function"'), 0, "string body ignored")
		Assert.eq(#check("-- if then end\nlocal x = 1"), 0, "line comment ignored")
		Assert.eq(#check("local s = [[ if then end ]]"), 0, "long string ignored")
		Assert.eq(#check("--[[ if then\n end ]] local x = 1"), 0, "long comment ignored")
	end)

	t.test("repeat / until balance, and a lone until is caught", function()
		Assert.eq(#check("repeat\n  x()\nuntil done"), 0, "repeat...until clean")
		Assert.truthy(string.find(messages("until done"), "without 'repeat'"), "lone until flagged")
	end)

	t.test("identifiers containing keywords don't false-positive", function()
		Assert.eq(#check("local endpoint = 1\nlocal myfunction = 2"), 0, "endpoint/myfunction not keywords")
	end)

	t.test("diagnostics carry a line number", function()
		local d = check("local a = 1\nlocal b = (2\nlocal c = 3")
		Assert.truthy(#d >= 1, "flagged")
		Assert.eq(d[1].line, 2, "points at the line with the open paren")
	end)
end
