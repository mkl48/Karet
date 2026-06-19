local loader = require("./loader")
local Assert = require("./assert")

local Shell = loader.get("Shell")

return function(t)
	t.test("aggregator exposes the public API", function()
		Assert.truthy(Shell.Tokenize, "Tokenize")
		Assert.truthy(Shell.Parse, "Parse")
		Assert.truthy(Shell.Analyze, "Analyze")
		Assert.truthy(Shell.newEvaluator, "newEvaluator")
	end)

	t.test("Tokenize / Parse / Analyze round-trip", function()
		local toks = Shell.Tokenize("ban Player 5")
		Assert.eq(toks.tokens[1].value, "ban", "tokenized")

		local parsed = Shell.Parse("ban Player 5")
		Assert.eq(parsed.ast.kind, "Program", "parsed to a Program")
		Assert.eq(#parsed.diagnostics, 0, "clean parse")

		local analysis = Shell.Analyze("ban Player (@x +")
		Assert.truthy(#analysis.diagnostics >= 1, "analyze surfaces a syntax error")
	end)

	t.test("newEvaluator builds an evaluator with a pool and scope", function()
		local ev = Shell.newEvaluator({})
		Assert.truthy(ev.pool, "has a return pool")
		Assert.truthy(ev.scope, "has a variable scope")
	end)
end
