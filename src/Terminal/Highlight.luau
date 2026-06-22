-- splits a shell command line into coloured spans for the input overlay. pure + headless
-- testable: returns a list of { text, group } where group is a Theme group name ("Plain" for
-- whitespace / anything we dont colour). the caller maps groups to palette colours. runs the
-- real shell lexer so the highlighting matches how the line actually parses.

local Lexer = require(script.Parent.Parent.Shell.Lexer)
local Token = require(script.Parent.Parent.Shell.Token)

local Highlight = {}

local K = Token.Kind

-- token kinds that map straight to a group no matter where they sit
local DIRECT: { [string]: string } = {
	[K.Number] = "Number",
	[K.String] = "String",
	[K.Boolean] = "Boolean",
	[K.At] = "Variable",
	[K.Slash] = "Reference",
	[K.SlashSlash] = "Reference",
	[K.Hash] = "Reference",
	[K.Assign] = "Operator",
	[K.Bang] = "Operator",
	[K.Tilde] = "Operator",
	[K.EqEq] = "Operator",
	[K.BangEq] = "Operator",
	[K.Gte] = "Operator",
	[K.Lte] = "Operator",
	[K.Gt] = "Operator",
	[K.Lt] = "Operator",
	[K.Plus] = "Operator",
	[K.Star] = "Operator",
	[K.Percent] = "Operator",
	[K.AmpAmp] = "Operator",
	[K.PipePipe] = "Operator",
	[K.Amp] = "Operator",
	[K.Pipe] = "Operator",
	[K.Semicolon] = "Operator",
	[K.LParen] = "Punctuation",
	[K.RParen] = "Punctuation",
	[K.LBrace] = "Punctuation",
	[K.RBrace] = "Punctuation",
	[K.LBracket] = "Punctuation",
	[K.RBracket] = "Punctuation",
	[K.Dot] = "Punctuation",
}

-- operators that end a command segment, so the next ident is a fresh command word
local SEGMENT_BREAK: { [string]: boolean } = {
	[K.AmpAmp] = true,
	[K.PipePipe] = true,
	[K.Pipe] = true,
	[K.Amp] = true,
	[K.Semicolon] = true,
	[K.Newline] = true,
}

export type Span = { text: string, group: string }

-- a dash hugging the next ident (no space between) is a flag (-s, --dry-run), otherwise its
-- arithmetic minus. lets us colour the whole flag including its leading dash.
local function dashIsFlag(tokens, idx): boolean
	local nextTok = tokens[idx + 1]
	return nextTok ~= nil and nextTok.kind == K.Ident and not nextTok.spaceBefore
end

--[=[
	Classify `text` into coloured spans. `isCommand(word)` (optional) decides whether the leading
	word of each segment is a known command (coloured Command) or not (Error), giving the live
	"this command exists" feedback as you type.
]=]
function Highlight.spans(text: string, isCommand: ((string) -> boolean)?): { Span }
	local ok, result = pcall(Lexer.tokenize, text)
	if not ok or type(result) ~= "table" or not result.tokens then
		return { { text = text, group = "Plain" } }
	end

	local spans: { Span } = {}
	local tokens = result.tokens
	local cursor = 1 -- byte offset we've emitted up to
	local expectCommand = true -- the next ident is a command word
	local flagNext = false -- previous dash hugs this ident, colour it Flag

	for idx, tok in tokens do
		if tok.kind == K.EOF then
			break
		end
		-- whatever sits between the last token and this one is whitespace: emit it plain
		if tok.pos > cursor then
			table.insert(spans, { text = string.sub(text, cursor, tok.pos - 1), group = "Plain" })
		end

		local group: string
		if tok.kind == K.Minus or tok.kind == K.MinusMinus then
			if dashIsFlag(tokens, idx) then
				group = "Flag"
				flagNext = true
			else
				group = "Operator"
			end
		elseif tok.kind == K.Ident then
			if flagNext then
				group = "Flag"
				flagNext = false
			elseif expectCommand then
				group = (isCommand and isCommand(tok.text)) and "Command" or "Error"
				expectCommand = false
			else
				group = "Plain" -- a positional argument
			end
		else
			group = DIRECT[tok.kind] or "Plain"
			if SEGMENT_BREAK[tok.kind] then
				expectCommand = true
			end
		end

		table.insert(spans, { text = tok.text, group = group })
		cursor = tok.pos + #tok.text
	end

	-- trailing whitespace the lexer dropped
	if cursor <= #text then
		table.insert(spans, { text = string.sub(text, cursor), group = "Plain" })
	end
	return spans
end

return Highlight
