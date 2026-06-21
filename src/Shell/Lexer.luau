-- The Karet shell lexer: source text -> a flat list of neutral tokens.
--
-- Neutral means: no FLAG / DIRECTIVE / SLASH_REF / SLASH_DIV tokens. `-`, `--`, `/`,
-- `//` come out as plain operator tokens; the parser assigns meaning by context and by
-- `spaceBefore` adjacency (GRAMMAR.md §2). The lexer never throws - malformed input
-- yields diagnostics and the scan continues, so this also backs `Analyze`.

local Token = require(script.Parent.Token)
local Kind = Token.Kind

local Lexer = {}

export type Diagnostic = {
	message: string,
	pos: number,
	line: number,
	col: number,
	len: number,
}

export type LexResult = {
	tokens: { Token.Token },
	diagnostics: { Diagnostic },
}

local function isDigit(b: number?): boolean
	return b ~= nil and b >= 48 and b <= 57
end

local function isAlpha(b: number?): boolean
	-- letters or underscore
	return b ~= nil and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95)
end

local function isAlphaNum(b: number?): boolean
	return isDigit(b) or isAlpha(b)
end

function Lexer.tokenize(source: string): LexResult
	local tokens: { Token.Token } = {}
	local diagnostics: { Diagnostic } = {}

	local i = 1
	local n = #source
	local line = 1
	local lineStart = 1 -- byte index where the current line begins (for column math)
	local spaceBefore = false

	local function col(pos: number): number
		return pos - lineStart + 1
	end

	local function addDiag(message: string, pos: number, len: number)
		table.insert(diagnostics, { message = message, pos = pos, line = line, col = col(pos), len = len })
	end

	local function push(kind: Token.Kind, text: string, value: any, pos: number)
		table.insert(tokens, {
			kind = kind,
			text = text,
			value = value,
			pos = pos,
			line = line,
			col = col(pos),
			spaceBefore = spaceBefore,
		})
		spaceBefore = false
	end

	-- does the char at p keep a bareword going. lets us lex things like 1,200,1 (vectors),
	-- a,b,c (player lists) and 1.5,2,3 as one token instead of choking on the comma
	local function continues(p: number, allowDot: boolean): boolean
		local c = string.byte(source, p)
		if isAlphaNum(c) then
			return true
		end
		if c == 45 and isAlpha(string.byte(source, p + 1)) then
			return true -- internal -letter, eg Ignore-Errors
		end
		if c == 44 and isAlphaNum(string.byte(source, p + 1)) then
			return true -- comma seperated list
		end
		if allowDot and c == 46 and isDigit(string.byte(source, p + 1)) then
			return true -- decimal inside a coord
		end
		return false
	end

	while i <= n do
		local b = string.byte(source, i)

		if b == 32 or b == 9 then
			-- space / tab
			spaceBefore = true
			i += 1
		elseif b == 10 or b == 13 then
			-- newline: \n, \r, or \r\n as one
			local startPos = i
			push(Kind.Newline, "\n", nil, startPos)
			i += 1
			if b == 13 and string.byte(source, i) == 10 then
				i += 1
			end
			line += 1
			lineStart = i
		elseif isDigit(b) then
			-- NUMBER: digits [ . digits ]  (unsigned; sign is the parser's job).
			-- But a digit run directly followed by a letter is a bareword: 1d, 30s, 5m.
			local startPos = i
			while isDigit(string.byte(source, i)) do
				i += 1
			end
			-- optional decimal part
			if string.byte(source, i) == 46 and isDigit(string.byte(source, i + 1)) then
				i += 1
				while isDigit(string.byte(source, i)) do
					i += 1
				end
			end
			-- if a letter or comma list follows its a bareword (1d, 30s, 1,200,1, 1.5,2,3)
			if continues(i, true) then
				while continues(i, true) do
					i += 1
				end
				local text = string.sub(source, startPos, i - 1)
				push(Kind.Ident, text, text, startPos)
			else
				local text = string.sub(source, startPos, i - 1)
				push(Kind.Number, text, tonumber(text), startPos)
			end
		elseif isAlpha(b) then
			-- IDENT / BOOL. Internal '-' is kept only when followed by a letter/_, so
			-- `Ignore-Errors` is one ident but `x-2` splits into x, -, 2.
			local startPos = i
			i += 1
			while continues(i, false) do
				i += 1
			end
			local text = string.sub(source, startPos, i - 1)
			if text == "true" then
				push(Kind.Boolean, text, true, startPos)
			elseif text == "false" then
				push(Kind.Boolean, text, false, startPos)
			else
				push(Kind.Ident, text, text, startPos)
			end
		elseif b == 34 then
			-- STRING with the full Luau escape set.
			local startPos = i
			i += 1
			local buf: { string } = {}
			local terminated = false
			while i <= n do
				local c = string.byte(source, i)
				if c == 34 then
					i += 1
					terminated = true
					break
				elseif c == 10 or c == 13 then
					break -- raw newline => unterminated
				elseif c == 92 then
					-- escape
					i += 1
					local e = string.byte(source, i)
					if e == nil then
						break
					elseif e == 110 then
						table.insert(buf, "\n")
						i += 1
					elseif e == 116 then
						table.insert(buf, "\t")
						i += 1
					elseif e == 114 then
						table.insert(buf, "\r")
						i += 1
					elseif e == 34 then
						table.insert(buf, '"')
						i += 1
					elseif e == 92 then
						table.insert(buf, "\\")
						i += 1
					elseif e == 97 then
						table.insert(buf, "\a")
						i += 1
					elseif e == 98 then
						table.insert(buf, "\b")
						i += 1
					elseif e == 102 then
						table.insert(buf, "\f")
						i += 1
					elseif e == 118 then
						table.insert(buf, "\v")
						i += 1
					elseif e == 120 then
						-- \xHH
						local hex = string.sub(source, i + 1, i + 2)
						local code = #hex == 2 and tonumber(hex, 16) or nil
						if code then
							table.insert(buf, string.char(code))
							i += 3
						else
							addDiag("invalid \\x escape (expected two hex digits)", i - 1, 2)
							i += 1
						end
					elseif e == 117 then
						-- \u{HEX}
						if string.byte(source, i + 1) == 123 then
							local close = string.find(source, "}", i + 2, true)
							if close then
								local hex = string.sub(source, i + 2, close - 1)
								local code = tonumber(hex, 16)
								if code then
									table.insert(buf, utf8.char(code))
									i = close + 1
								else
									addDiag("invalid \\u{...} escape", i - 1, close - (i - 1) + 1)
									i += 1
								end
							else
								addDiag("unterminated \\u{ escape", i - 1, 2)
								i += 1
							end
						else
							addDiag("malformed \\u escape (expected '{')", i - 1, 2)
							i += 1
						end
					elseif isDigit(e) then
						-- \ddd decimal, 1-3 digits
						local k = i
						local ds = {}
						while #ds < 3 and isDigit(string.byte(source, k)) do
							table.insert(ds, string.char(string.byte(source, k) :: number))
							k += 1
						end
						local code = tonumber(table.concat(ds))
						if code and code <= 255 then
							table.insert(buf, string.char(code))
							i = k
						else
							addDiag("decimal escape out of range (0-255)", i - 1, #ds + 1)
							i = k
						end
					else
						addDiag("unknown escape sequence", i - 1, 2)
						table.insert(buf, string.char(e))
						i += 1
					end
				else
					table.insert(buf, string.char(c))
					i += 1
				end
			end
			local text = string.sub(source, startPos, i - 1)
			if not terminated then
				addDiag("unterminated string literal", startPos, #text)
			end
			push(Kind.String, text, table.concat(buf), startPos)
		elseif b == 91 and (isDigit(string.byte(source, i + 1)) or string.byte(source, i + 1) == 45) then
			-- [1,2,3] wraps a coord/value list into one token, brackets stripped. a [ before
			-- a letter is left as a normal bracket (eg @TYPE[Player])
			local startPos = i
			local close = string.find(source, "]", i + 1, true)
			if close then
				local inner = string.gsub(string.sub(source, i + 1, close - 1), "%s", "")
				push(Kind.Ident, inner, inner, startPos)
				i = close + 1
			else
				push(Kind.LBracket, "[", nil, startPos)
				i += 1
			end
		else
			-- operators / punctuation, longest match first
			local startPos = i
			local b2 = string.byte(source, i + 1)
			if b == 47 and b2 == 47 then
				push(Kind.SlashSlash, "//", nil, startPos)
				i += 2
			elseif b == 38 and b2 == 38 then
				push(Kind.AmpAmp, "&&", nil, startPos)
				i += 2
			elseif b == 124 and b2 == 124 then
				push(Kind.PipePipe, "||", nil, startPos)
				i += 2
			elseif b == 61 and b2 == 61 then
				push(Kind.EqEq, "==", nil, startPos)
				i += 2
			elseif b == 33 and b2 == 61 then
				push(Kind.BangEq, "!=", nil, startPos)
				i += 2
			elseif b == 62 and b2 == 61 then
				push(Kind.Gte, ">=", nil, startPos)
				i += 2
			elseif b == 60 and b2 == 61 then
				push(Kind.Lte, "<=", nil, startPos)
				i += 2
			elseif b == 45 and b2 == 45 then
				push(Kind.MinusMinus, "--", nil, startPos)
				i += 2
			else
				local kind: Token.Kind? = nil
				if b == 47 then
					kind = Kind.Slash
				elseif b == 46 then
					kind = Kind.Dot
				elseif b == 35 then
					kind = Kind.Hash
				elseif b == 64 then
					kind = Kind.At
				elseif b == 61 then
					kind = Kind.Assign
				elseif b == 33 then
					kind = Kind.Bang
				elseif b == 126 then
					kind = Kind.Tilde
				elseif b == 38 then
					kind = Kind.Amp
				elseif b == 124 then
					kind = Kind.Pipe
				elseif b == 62 then
					kind = Kind.Gt
				elseif b == 60 then
					kind = Kind.Lt
				elseif b == 43 then
					kind = Kind.Plus
				elseif b == 45 then
					kind = Kind.Minus
				elseif b == 42 then
					kind = Kind.Star
				elseif b == 37 then
					kind = Kind.Percent
				elseif b == 40 then
					kind = Kind.LParen
				elseif b == 41 then
					kind = Kind.RParen
				elseif b == 123 then
					kind = Kind.LBrace
				elseif b == 125 then
					kind = Kind.RBrace
				elseif b == 91 then
					kind = Kind.LBracket
				elseif b == 93 then
					kind = Kind.RBracket
				end

				if kind then
					push(kind, string.char(b), nil, startPos)
					i += 1
				else
					addDiag(string.format("unexpected character %q", string.char(b)), startPos, 1)
					i += 1
				end
			end
		end
	end

	push(Kind.EOF, "", nil, i)
	return { tokens = tokens, diagnostics = diagnostics }
end

return Lexer
