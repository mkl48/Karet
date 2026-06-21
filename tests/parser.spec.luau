local loader = require("./loader")
local Assert = require("./assert")

local Parser = loader.get("Parser")

-- Render an AST as a compact s-expression so cases read as one line.
local function sx(node: any): string
	if node == nil then
		return "nil"
	end
	local k = node.kind
	if k == "Program" then
		local parts = {}
		for _, c in node.chains do
			table.insert(parts, sx(c))
		end
		return "(program " .. table.concat(parts, " ") .. ")"
	elseif k == "Chain" then
		local parts = {}
		for _, step in node.steps do
			if step.op then
				table.insert(parts, step.op)
			end
			table.insert(parts, sx(step.node))
		end
		if #node.directives > 0 then
			table.insert(parts, "--[" .. table.concat(node.directives, ",") .. "]")
		end
		return "(chain " .. table.concat(parts, " ") .. ")"
	elseif k == "Command" then
		local parts = { node.name }
		for _, a in node.args do
			table.insert(parts, sx(a))
		end
		if #node.flags > 0 then
			table.insert(parts, "-[" .. table.concat(node.flags, ",") .. "]")
		end
		return "(cmd" .. (node.ambiguous and "?" or "") .. " " .. table.concat(parts, " ") .. ")"
	elseif k == "Literal" then
		if node.valueType == "string" then
			return '"' .. tostring(node.value) .. '"'
		elseif node.valueType == "nil" then
			return "nil"
		end
		return tostring(node.value)
	elseif k == "Reference" then
		local s = node.last and "//" or ("/" .. tostring(node.name))
		if node.index then
			s = s .. "#" .. tostring(node.index)
		end
		for _, p in node.path do
			s = s .. "." .. p
		end
		return s
	elseif k == "VarRef" then
		local s = "@" .. node.name
		for _, p in node.path do
			s = s .. "." .. p
		end
		return s
	elseif k == "TypeValue" then
		return "@TYPE[" .. node.typeName .. "]"
	elseif k == "Assignment" then
		return "(= " .. node.name .. " " .. sx(node.value) .. ")"
	elseif k == "Binary" then
		return "(" .. node.op .. " " .. sx(node.left) .. " " .. sx(node.right) .. ")"
	elseif k == "Unary" then
		return "(" .. node.op .. " " .. sx(node.operand) .. ")"
	elseif k == "IsNil" then
		return "(! " .. sx(node.operand) .. ")"
	elseif k == "Guarded" then
		local terms = {}
		for _, t in node.guard.terms do
			table.insert(terms, (t.op and (t.op .. " ") or "") .. (t.negate and "~" or "") .. sx(t.expr))
		end
		return "(guard [" .. table.concat(terms, " ") .. "] " .. sx(node.block) .. ")"
	elseif k == "ValueStmt" then
		return "(val " .. sx(node.value) .. ")"
	end
	return "<" .. tostring(k) .. ">"
end

local function parse(src: string)
	return Parser.parse(src)
end

return function(t)
	local function ok(name: string, src: string, expected: string)
		t.test(name, function()
			local r = parse(src)
			Assert.eq(sx(r.ast), expected, `AST for: {src}`)
			Assert.eq(#r.diagnostics, 0, `no diagnostics for: {src}`)
		end)
	end

	ok("simple command", "ban Player 5", '(program (chain (cmd ban "Player" 5)))')

	ok(
		"chain operators",
		'give P coins 500 && kick P "bye"',
		'(program (chain (cmd give "P" "coins" 500) && (cmd kick "P" "bye")))'
	)

	ok(
		"semicolons separate statements like newlines",
		"echo one; echo two",
		'(program (chain (cmd echo "one")) (chain (cmd echo "two")))'
	)

	ok("flags trail the command", 'ban P 1d "g" -s -p', '(program (chain (cmd ban "P" "1d" "g" -[s,p])))')

	ok("stacked flag stays raw for the registry", "ban P -sp", "(program (chain (cmd ban \"P\" -[sp])))")

	ok("negative number argument", "tp P -5", '(program (chain (cmd tp "P" -5)))')

	ok(
		"references: last + property as a value statement",
		"GetPlayer Kr && //.UserId",
		'(program (chain (cmd GetPlayer "Kr") && (val //.UserId)))'
	)

	ok("reference by type with index", 'ban /target#2.UserId "alt"', '(program (chain (cmd ban /target#2.UserId "alt")))')

	ok("variable arg", "give @x coins 500", '(program (chain (cmd give @x "coins" 500)))')

	ok("assignment statement (literal)", "(x = 5)", "(program (chain (val (= x 5))))")

	ok(
		"assignment with command substitution",
		"(x = (GetPlayer me))",
		'(program (chain (val (= x (cmd GetPlayer "me")))))'
	)

	ok("expression argument", "give @x (@y + 2)", '(program (chain (cmd give @x (+ @y 2))))')

	ok(
		"precedence: + before ==, ~ negates the group",
		"give @x (~(@a + 2 == 4))",
		'(program (chain (cmd give @x (~ (== (+ @a 2) 4)))))'
	)

	ok("division uses / in operator position", "echo (10 / 2)", "(program (chain (cmd echo (/ 10 2))))")

	ok(
		"reference arg vs division disambiguated by adjacency",
		"echo (GetThing /Player)",
		'(program (chain (cmd echo (cmd GetThing /Player))))'
	)

	ok("postfix not-nil", "echo (@x ~!)", "(program (chain (cmd echo (~ (! @x)))))")
	ok("postfix is-nil", "echo (@x !)", "(program (chain (cmd echo (! @x))))")

	ok("type guard satisfaction", "echo (@x == @TYPE[number])", "(program (chain (cmd echo (== @x @TYPE[number]))))")

	ok(
		"guard + block",
		"(@x ~!){ ban @x.UserId \"c\" -p }",
		'(program (chain (guard [(~ (! @x))] (program (chain (cmd ban @x.UserId "c" -[p]))))))'
	)

	ok(
		"joined guard terms with negation",
		"~(@a + 2 == 4) && (@x == @TYPE[number]) { give @x coins 500 }",
		"(program (chain (guard [~(== (+ @a 2) 4) && (== @x @TYPE[number])] "
			.. '(program (chain (cmd give @x "coins" 500))))))'
	)

	ok(
		"trailing directive is chain-level",
		"GetPlayer x && ban //.UserId \"x\" --Ignore-Errors",
		'(program (chain (cmd GetPlayer "x") && (cmd ban //.UserId "x") --[Ignore-Errors]))'
	)

	ok(
		"multi-line program",
		"(x = (GetPlayer me))\ngive @x coins 500",
		'(program (chain (val (= x (cmd GetPlayer "me")))) (chain (cmd give @x "coins" 500)))'
	)

	ok("lone bare word in group is ambiguous", "echo (now)", "(program (chain (cmd echo (cmd? now))))")

	t.test("diagnostics on unterminated group", function()
		local r = parse("echo (@x + ")
		Assert.truthy(#r.diagnostics >= 1, "missing ')' flagged")
	end)
end
