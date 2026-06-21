-- Headless test runner. Usage: lune run tests/run

local process = require("@lune/process")
local Harness = require("./harness")

local specs = {
	{ name = "Lexer", spec = require("./lexer.spec") },
	{ name = "Parser", spec = require("./parser.spec") },
	{ name = "ReturnPool", spec = require("./returnpool.spec") },
	{ name = "Evaluator", spec = require("./evaluator.spec") },
	{ name = "Shell", spec = require("./shell.spec") },
	{ name = "Theme", spec = require("./theme.spec") },
	{ name = "Types", spec = require("./types.spec") },
	{ name = "Registry", spec = require("./registry.spec") },
	{ name = "Host", spec = require("./host.spec") },
	{ name = "Commands", spec = require("./commands.spec") },
	{ name = "Cache", spec = require("./cache.spec") },
	{ name = "Complete", spec = require("./complete.spec") },
	{ name = "KaveatComplete", spec = require("./kaveatcomplete.spec") },
	{ name = "Alias", spec = require("./alias.spec") },
	{ name = "Extensions", spec = require("./extensions.spec") },
}

local t = Harness.new()
for _, entry in specs do
	entry.spec(t)
end

print(`\n{t.passed} passed, {t.failed} failed`)
if t.failed > 0 then
	print("")
	for _, f in t.failures do
		print(`FAIL  {f.name}`)
		print(`      {tostring(f.err)}`)
	end
	process.exit(1)
end
process.exit(0)
