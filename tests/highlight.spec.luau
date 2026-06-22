-- Tests for the input syntax highlighter. Highlight.spans runs the shell lexer and tags each
-- token with a Theme group; here we reuse the Shell loader to satisfy its require paths, then
-- assert the tagging (command vs unknown, args, strings, numbers, flags, operators, @vars).

local luau = require("@lune/luau")
local fs = require("@lune/fs")
local ShellLoader = require("./loader")
local Assert = require("./assert")

-- Highlight lives at src/Terminal/Highlight.luau and reaches back into the Shell modules via
-- `script.Parent.Parent.Shell.{Lexer,Token}`. Build just enough of a handle tree for that path
-- to resolve to the already-loaded Shell modules.
local lexerH = { _mod = ShellLoader.get("Lexer") }
local tokenH = { _mod = ShellLoader.get("Token") }
local shellH = { Lexer = lexerH, Token = tokenH }
local rootH = { Shell = shellH }
local terminalH = { Parent = rootH }
local highlightH = { Parent = terminalH }

local function req(handle)
	return handle._mod
end

local Highlight = luau.load(fs.readFile("src/Terminal/Highlight.luau"), {
	debugName = "Highlight",
	environment = { script = highlightH, require = req },
})()

-- group of the span whose text matches `want` (first match), or nil
local function groupOf(spans, want)
	for _, s in spans do
		if s.text == want then
			return s.group
		end
	end
	return nil
end

-- the spans must always reconstruct the original input exactly
local function roundtrip(spans)
	local parts = {}
	for _, s in spans do
		table.insert(parts, s.text)
	end
	return table.concat(parts)
end

return function(t)
	local known = { ban = true, echo = true, give = true }
	local isCommand = function(w)
		return known[string.lower(w)] == true
	end

	t.test("spans reconstruct the input", function()
		local line = 'ban Player1 --reason="spam" && echo hi'
		Assert.eq(roundtrip(Highlight.spans(line, isCommand)), line, "lossless")
	end)

	t.test("known leading word is a Command, unknown is an Error", function()
		Assert.eq(groupOf(Highlight.spans("ban x", isCommand), "ban"), "Command", "known command")
		Assert.eq(groupOf(Highlight.spans("nope x", isCommand), "nope"), "Error", "unknown command")
	end)

	t.test("arguments after the command are plain", function()
		local spans = Highlight.spans("ban Player1", isCommand)
		Assert.eq(groupOf(spans, "Player1"), "Plain", "positional arg not coloured as a command")
	end)

	t.test("strings and numbers get their groups", function()
		local spans = Highlight.spans('echo "hi" 42', isCommand)
		Assert.eq(groupOf(spans, '"hi"'), "String", "string literal")
		Assert.eq(groupOf(spans, "42"), "Number", "number literal")
	end)

	t.test("flags colour the dash and the name", function()
		local spans = Highlight.spans("ban -s", isCommand)
		Assert.eq(groupOf(spans, "-"), "Flag", "short flag dash")
		Assert.eq(groupOf(spans, "s"), "Flag", "short flag name")
	end)

	t.test("the word after a chain operator is a fresh command", function()
		local spans = Highlight.spans("ban x && echo hi", isCommand)
		Assert.eq(groupOf(spans, "&&"), "Operator", "chain operator")
		Assert.eq(groupOf(spans, "echo"), "Command", "second segment command")
	end)

	t.test("@variables are tagged Variable", function()
		local spans = Highlight.spans("echo @x", isCommand)
		Assert.eq(groupOf(spans, "@"), "Variable", "variable sigil")
	end)

	t.test("tolerates an empty line", function()
		Assert.eq(roundtrip(Highlight.spans("", isCommand)), "", "empty input")
	end)
end
