local loader = require("./loader")
local Assert = require("./assert")

local Lexer = loader.get("Lexer")

local function kinds(result): { string }
	local out = {}
	for _, tok in result.tokens do
		table.insert(out, tok.kind)
	end
	return out
end

local function pair(result, index): { kind: string, text: string, value: any, spaceBefore: boolean }
	local tok = result.tokens[index]
	return { kind = tok.kind, text = tok.text, value = tok.value, spaceBefore = tok.spaceBefore }
end

return function(t)
	t.test("tokenizes a simple command", function()
		local r = Lexer.tokenize("ban Player 5")
		Assert.eq(kinds(r), { "Ident", "Ident", "Number", "EOF" }, "kinds")
		Assert.eq(r.tokens[1].value, "ban", "first ident value")
		Assert.eq(r.tokens[3].value, 5, "number value")
		Assert.eq(#r.diagnostics, 0, "no diagnostics")
	end)

	t.test("tracks spaceBefore for adjacency", function()
		-- "-s" : the Ident after Minus has no space before it (a flag)
		local flag = Lexer.tokenize("ban Player -s")
		Assert.eq(flag.tokens[3].kind, "Minus", "dash is Minus")
		Assert.truthy(flag.tokens[3].spaceBefore, "dash separated from prev")
		Assert.eq(flag.tokens[4].kind, "Ident", "flag name")
		Assert.falsy(flag.tokens[4].spaceBefore, "flag name adjacent to dash")

		-- "- s" : spaced, so the name is NOT adjacent
		local spaced = Lexer.tokenize("x - s")
		Assert.truthy(spaced.tokens[3].spaceBefore, "spaced name has space before")
	end)

	t.test("distinguishes / and //", function()
		local r = Lexer.tokenize("/Player // 10/2")
		Assert.eq(kinds(r), { "Slash", "Ident", "SlashSlash", "Number", "Slash", "Number", "EOF" }, "slash kinds")
		Assert.falsy(r.tokens[2].spaceBefore, "ref name adjacent to slash")
	end)

	t.test("longest-match operators", function()
		local r = Lexer.tokenize("&& & || == != >= <= -- -")
		Assert.eq(
			kinds(r),
			{ "AmpAmp", "Amp", "PipePipe", "EqEq", "BangEq", "Gte", "Lte", "MinusMinus", "Minus", "EOF" },
			"operator kinds"
		)
	end)

	t.test("ident keeps internal dash before a letter, splits before a digit", function()
		local kept = Lexer.tokenize("--Ignore-Errors")
		Assert.eq(kept.tokens[1].kind, "MinusMinus", "directive dashes")
		Assert.eq(kept.tokens[2].value, "Ignore-Errors", "dashed ident kept whole")

		local split = Lexer.tokenize("x-2")
		Assert.eq(kinds(split), { "Ident", "Minus", "Number", "EOF" }, "x-2 splits")
		Assert.eq(split.tokens[1].value, "x", "ident is just x")
	end)

	t.test("digit-led barewords stay one token", function()
		local r = Lexer.tokenize("1d 30s 5m 100")
		Assert.eq(kinds(r), { "Ident", "Ident", "Ident", "Number", "EOF" }, "duration words vs number")
		Assert.eq(r.tokens[1].value, "1d", "1d is a word")
		Assert.eq(r.tokens[4].value, 100, "100 is a number")
	end)

	t.test("booleans and floats", function()
		local r = Lexer.tokenize("true false 3.14")
		Assert.eq(kinds(r), { "Boolean", "Boolean", "Number", "EOF" }, "bool/float kinds")
		Assert.eq(r.tokens[1].value, true, "true value")
		Assert.eq(r.tokens[2].value, false, "false value")
		Assert.eq(r.tokens[3].value, 3.14, "float value")
	end)

	t.test("string escapes", function()
		local r = Lexer.tokenize([["a\tb\n\"q\" \x41 \u{1F600} \65"]])
		Assert.eq(r.tokens[1].kind, "String", "is a string")
		Assert.eq(r.tokens[1].value, "a\tb\n\"q\" A " .. utf8.char(0x1F600) .. " A", "cooked escapes")
		Assert.eq(#r.diagnostics, 0, "no escape diagnostics")
	end)

	t.test("sigils, brackets, refs", function()
		local r = Lexer.tokenize("@x @TYPE[number] /Player#2.UserId")
		Assert.eq(kinds(r), {
			"At", "Ident", -- @x
			"At", "Ident", "LBracket", "Ident", "RBracket", -- @TYPE[number]
			"Slash", "Ident", "Hash", "Number", "Dot", "Ident", -- /Player#2.UserId
			"EOF",
		}, "sigil/bracket kinds")
	end)

	t.test("newlines are tokens and bump line numbers", function()
		local r = Lexer.tokenize("a\nb")
		Assert.eq(kinds(r), { "Ident", "Newline", "Ident", "EOF" }, "newline kinds")
		Assert.eq(r.tokens[1].line, 1, "first line")
		Assert.eq(r.tokens[3].line, 2, "second line")
	end)

	t.test("diagnostics: unterminated string and bad char", function()
		local s = Lexer.tokenize('"oops')
		Assert.truthy(#s.diagnostics >= 1, "unterminated string flagged")

		local c = Lexer.tokenize("a ` b")
		Assert.truthy(#c.diagnostics >= 1, "backtick flagged as unexpected")
	end)
end
