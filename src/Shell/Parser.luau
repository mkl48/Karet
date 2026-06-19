-- Recursive-descent parser for the Karet shell. Tokens -> AST + diagnostics.
--
-- The parser is where context lives (GRAMMAR.md §1): the same `/` token becomes a
-- reference in value position and division in operator position; `&&` is chain control
-- between statements and boolean inside an expression. Nothing here throws — errors are
-- collected as diagnostics with best-effort recovery, so this also powers `Analyze`.

local Lexer = require(script.Parent.Lexer)
local Token = require(script.Parent.Token)
local Ast = require(script.Parent.Ast)

local K = Token.Kind
local N = Ast.Kind

local Parser = {}

export type ParseResult = {
	ast: any,
	diagnostics: { Lexer.Diagnostic },
}

-- tokens that can begin an argument / expression operand (used for juxtaposition)
local ARG_START: { [string]: boolean } = {
	[K.Ident] = true,
	[K.Number] = true,
	[K.String] = true,
	[K.Boolean] = true,
	[K.At] = true,
	[K.Slash] = true,
	[K.SlashSlash] = true,
	[K.LParen] = true,
}

-- binary operators that, after an operand, mean "this is an expression"
local BINOP: { [string]: boolean } = {
	[K.Plus] = true,
	[K.Star] = true,
	[K.Percent] = true,
	[K.EqEq] = true,
	[K.BangEq] = true,
	[K.Gt] = true,
	[K.Lt] = true,
	[K.Gte] = true,
	[K.Lte] = true,
	[K.AmpAmp] = true,
	[K.PipePipe] = true,
	-- Minus and Slash are handled specially (adjacency decides flag/ref vs operator)
}

local COMPARE: { [string]: string } = {
	[K.EqEq] = "==",
	[K.BangEq] = "!=",
	[K.Gt] = ">",
	[K.Lt] = "<",
	[K.Gte] = ">=",
	[K.Lte] = "<=",
}

function Parser.parseTokens(tokens: { Token.Token }, diagnostics: { Lexer.Diagnostic }): ParseResult
	local pos = 1
	diagnostics = diagnostics or {}

	local function cur(): Token.Token
		return tokens[pos]
	end
	local function kind(): string
		return tokens[pos].kind
	end
	local function at(k: string): boolean
		return tokens[pos].kind == k
	end
	local function peek(off: number): Token.Token?
		return tokens[pos + off]
	end
	local function advance(): Token.Token
		local t = tokens[pos]
		if t.kind ~= K.EOF then
			pos += 1
		end
		return t
	end
	local function diag(message: string, tok: Token.Token?)
		tok = tok or cur()
		table.insert(diagnostics, {
			message = message,
			pos = tok.pos,
			line = tok.line,
			col = tok.col,
			len = math.max(#tok.text, 1),
		})
	end
	local function expect(k: string, what: string): Token.Token?
		if at(k) then
			return advance()
		end
		diag(`expected {what}`)
		return nil
	end
	local function skipNewlines()
		while at(K.Newline) do
			advance()
		end
	end

	-- forward decls
	local parseProgram, parseChain, parseStatement, parseCommand, parseArgument
	local parseGroup, parseGroupBody, parseCommandOrExpr
	local parseExpr, parseAtValue, parseReference, parsePath
	local tryParseGuarded, parseGuard, parseGuardTerm, parseBlock

	function parsePath(): { string }
		local path = {}
		while at(K.Dot) do
			advance()
			local id = expect(K.Ident, "property name")
			if id then
				table.insert(path, id.value)
			else
				break
			end
		end
		return path
	end

	-- @x , @x.prop , @TYPE[name]
	function parseAtValue(): any
		advance() -- '@'
		if not at(K.Ident) then
			diag("expected a name after '@'")
			return { kind = N.VarRef, name = "", path = {} }
		end
		local nameTok = advance()
		if nameTok.value == "TYPE" and at(K.LBracket) then
			advance() -- '['
			local typeTok = expect(K.Ident, "type name")
			expect(K.RBracket, "']'")
			return { kind = N.TypeValue, typeName = typeTok and typeTok.value or "" }
		end
		return { kind = N.VarRef, name = nameTok.value, path = parsePath() }
	end

	-- // , /Name , with optional #index and .path
	function parseReference(): any
		local last = false
		local name: string? = nil
		if at(K.SlashSlash) then
			advance()
			last = true
		else
			advance() -- '/'
			local id = expect(K.Ident, "reference name")
			name = id and id.value or ""
		end
		local index: number? = nil
		if at(K.Hash) then
			advance()
			local num = expect(K.Number, "reference index")
			index = num and num.value or nil
		end
		return { kind = N.Reference, last = last, name = name, index = index, path = parsePath() }
	end

	-- ---- expression grammar (precedence climbing) ----

	local function parsePrimary(): any
		local k = kind()
		if k == K.Number then
			local t = advance()
			return { kind = N.Literal, valueType = "number", value = t.value, token = t }
		elseif k == K.String then
			local t = advance()
			return { kind = N.Literal, valueType = "string", value = t.value, token = t }
		elseif k == K.Boolean then
			local t = advance()
			return { kind = N.Literal, valueType = "boolean", value = t.value, token = t }
		elseif k == K.Ident then
			local t = advance() -- bare word in an expression is a literal string
			return { kind = N.Literal, valueType = "string", value = t.value, token = t }
		elseif k == K.At then
			return parseAtValue()
		elseif k == K.Slash or k == K.SlashSlash then
			return parseReference()
		elseif k == K.LParen then
			return parseGroup()
		else
			diag("expected an expression")
			if not at(K.EOF) then
				advance()
			end
			return { kind = N.Literal, valueType = "nil", value = nil }
		end
	end

	local function parsePostfix(): any
		local p = parsePrimary()
		-- postfix nil-tests: `x!` = is-nil, `x~!` = not-nil (here `~` prefixes the `!`).
		while true do
			if at(K.Bang) then
				advance()
				p = { kind = N.IsNil, operand = p }
			elseif at(K.Tilde) then
				local n = peek(1)
				if n and n.kind == K.Bang then
					advance() -- '~'
					advance() -- '!'
					p = { kind = N.Unary, op = "~", operand = { kind = N.IsNil, operand = p } }
				else
					break
				end
			else
				break
			end
		end
		return p
	end

	local function parseUnary(): any
		if at(K.Tilde) then
			advance()
			return { kind = N.Unary, op = "~", operand = parseUnary() }
		elseif at(K.Minus) then
			advance()
			return { kind = N.Unary, op = "neg", operand = parseUnary() }
		end
		return parsePostfix()
	end

	local function parseMul(): any
		local left = parseUnary()
		while at(K.Star) or at(K.Slash) or at(K.Percent) do
			local op = at(K.Star) and "*" or at(K.Slash) and "/" or "%"
			advance()
			left = { kind = N.Binary, op = op, left = left, right = parseUnary() }
		end
		return left
	end

	local function parseAdd(): any
		local left = parseMul()
		while at(K.Plus) or at(K.Minus) do
			local op = at(K.Plus) and "+" or "-"
			advance()
			left = { kind = N.Binary, op = op, left = left, right = parseMul() }
		end
		return left
	end

	local function parseCmp(): any
		local left = parseAdd()
		local op = COMPARE[kind()]
		if op then
			advance()
			return { kind = N.Binary, op = op, left = left, right = parseAdd() }
		end
		return left
	end

	local function parseAnd(): any
		local left = parseCmp()
		while at(K.AmpAmp) do
			advance()
			left = { kind = N.Binary, op = "&&", left = left, right = parseCmp() }
		end
		return left
	end

	local function parseOr(): any
		local left = parseAnd()
		while at(K.PipePipe) do
			advance()
			left = { kind = N.Binary, op = "||", left = left, right = parseAnd() }
		end
		return left
	end

	function parseExpr(): any
		return parseOr()
	end

	-- ---- §4 group resolution: command-sub vs expression vs assignment ----

	-- returns true (command sub), false (expression), or "lone" (ambiguous bare word)
	local function looksLikeCommandSub(): (boolean | string)
		if not at(K.Ident) then
			return false
		end
		local n = peek(1)
		if not n then
			return false
		end
		local nk = n.kind
		if nk == K.RParen then
			return "lone"
		end
		if BINOP[nk] then
			return false
		end
		if nk == K.Minus then
			-- flag (`word -s`) or negative-number arg (`word -5`) => command; spaced minus => expr
			local n2 = peek(2)
			if n2 and not n2.spaceBefore and (n2.kind == K.Ident or n2.kind == K.Number) then
				return true
			end
			return false
		end
		if nk == K.Slash then
			-- `word /Player` (ref arg) => command; `word / 2` (division) => expr
			local n2 = peek(2)
			if n2 and not n2.spaceBefore and n2.kind == K.Ident then
				return true
			end
			return false
		end
		if ARG_START[nk] then
			return true
		end
		return false
	end

	function parseCommandOrExpr(): any
		local verdict = looksLikeCommandSub()
		if verdict == true then
			return parseCommand()
		elseif verdict == "lone" then
			local word = advance()
			return {
				kind = N.Command,
				name = word.value,
				nameToken = word,
				args = {},
				flags = {},
				ambiguous = true, -- eval: registered command -> run; else literal string
			}
		end
		return parseExpr()
	end

	function parseGroupBody(): any
		if at(K.Ident) then
			local n = peek(1)
			if n and n.kind == K.Assign then
				local nameTok = advance()
				advance() -- '='
				return { kind = N.Assignment, name = nameTok.value, value = parseCommandOrExpr() }
			end
		end
		return parseCommandOrExpr()
	end

	function parseGroup(): any
		expect(K.LParen, "'('")
		local body = parseGroupBody()
		expect(K.RParen, "')'")
		return body
	end

	-- ---- commands ----

	function parseArgument(): any?
		local k = kind()
		if k == K.Number then
			local t = advance()
			return { kind = N.Literal, valueType = "number", value = t.value, token = t }
		elseif k == K.String then
			local t = advance()
			return { kind = N.Literal, valueType = "string", value = t.value, token = t }
		elseif k == K.Boolean then
			local t = advance()
			return { kind = N.Literal, valueType = "boolean", value = t.value, token = t }
		elseif k == K.Ident then
			local t = advance()
			return { kind = N.Literal, valueType = "string", value = t.value, token = t }
		elseif k == K.At then
			return parseAtValue()
		elseif k == K.Slash or k == K.SlashSlash then
			return parseReference()
		elseif k == K.LParen then
			return parseGroup()
		end
		return nil
	end

	function parseCommand(): any
		local nameTok = advance() -- Ident (caller guarantees)
		local args = {}
		local flags = {}
		while true do
			local k = kind()
			if
				k == K.Newline
				or k == K.EOF
				or k == K.RParen
				or k == K.RBrace
				or k == K.LBrace
				or k == K.AmpAmp
				or k == K.PipePipe
				or k == K.Amp
				or k == K.MinusMinus
			then
				break
			elseif k == K.Minus then
				local nx = peek(1)
				if nx and not nx.spaceBefore and nx.kind == K.Ident then
					advance() -- '-'
					-- raw flag chunk; stacking/name resolution happens with the Attributes
					table.insert(flags, advance().value)
				elseif nx and not nx.spaceBefore and nx.kind == K.Number then
					advance() -- '-'
					local num = advance()
					table.insert(args, { kind = N.Literal, valueType = "number", value = -num.value, token = num })
				else
					diag("unexpected '-'")
					break
				end
			else
				local arg = parseArgument()
				if arg == nil then
					break
				end
				table.insert(args, arg)
			end
		end
		return { kind = N.Command, name = nameTok.value, nameToken = nameTok, args = args, flags = flags }
	end

	-- ---- guards & blocks ----

	function parseGuardTerm(): any?
		local negate = false
		if at(K.Tilde) then
			advance()
			negate = true
		end
		if not at(K.LParen) then
			return nil
		end
		advance() -- '('
		local expr = parseExpr()
		if not at(K.RParen) then
			return nil
		end
		advance() -- ')'
		return { negate = negate, expr = expr }
	end

	function parseGuard(): any?
		local first = parseGuardTerm()
		if not first then
			return nil
		end
		local terms = { first }
		while at(K.AmpAmp) or at(K.PipePipe) do
			local op = at(K.AmpAmp) and "&&" or "||"
			advance()
			local term = parseGuardTerm()
			if not term then
				return nil
			end
			term.op = op
			table.insert(terms, term)
		end
		return { kind = N.Guard, terms = terms }
	end

	function parseBlock(): any
		expect(K.LBrace, "'{'")
		local prog = parseProgram(K.RBrace)
		expect(K.RBrace, "'}'")
		return prog
	end

	function tryParseGuarded(): any?
		local savePos = pos
		local saveDiag = #diagnostics
		local guard = parseGuard()
		if guard and at(K.LBrace) then
			return { kind = N.Guarded, guard = guard, block = parseBlock() }
		end
		-- backtrack: it wasn't a guard
		pos = savePos
		while #diagnostics > saveDiag do
			table.remove(diagnostics)
		end
		return nil
	end

	-- ---- statements / chains / program ----

	function parseStatement(): any?
		if at(K.Tilde) or at(K.LParen) then
			local guarded = tryParseGuarded()
			if guarded then
				return guarded
			end
			if at(K.LParen) then
				return { kind = N.ValueStmt, value = parseGroup() }
			end
			diag("expected '(' to begin a guard")
			advance()
			return nil
		elseif at(K.Slash) or at(K.SlashSlash) then
			return { kind = N.ValueStmt, value = parseReference() }
		elseif at(K.Ident) then
			return parseCommand()
		end
		local t = cur()
		diag(`unexpected {t.text ~= "" and t.text or t.kind}`)
		if not at(K.EOF) then
			advance()
		end
		return nil
	end

	function parseChain(): any
		local steps = { { op = nil, node = parseStatement() } }
		while at(K.AmpAmp) or at(K.PipePipe) or at(K.Amp) do
			local op = at(K.AmpAmp) and "&&" or at(K.PipePipe) and "||" or "&"
			advance()
			table.insert(steps, { op = op, node = parseStatement() })
		end
		local directives = {}
		while at(K.MinusMinus) do
			advance()
			local id = expect(K.Ident, "directive name after '--'")
			if id then
				table.insert(directives, id.value)
			end
		end
		return { kind = N.Chain, steps = steps, directives = directives }
	end

	function parseProgram(stopKind: string?): any
		local chains = {}
		skipNewlines()
		while not at(K.EOF) and not (stopKind ~= nil and at(stopKind)) do
			local before = pos
			local chain = parseChain()
			if chain then
				table.insert(chains, chain)
			end
			if at(K.Newline) then
				skipNewlines()
			elseif pos == before then
				-- no progress: force advance so we never loop forever
				if not at(K.EOF) then
					diag(`unexpected {cur().kind}`)
					advance()
				else
					break
				end
			end
		end
		return { kind = N.Program, chains = chains }
	end

	local ast = parseProgram(nil)
	return { ast = ast, diagnostics = diagnostics }
end

function Parser.parse(source: string): ParseResult
	local lexed = Lexer.tokenize(source)
	return Parser.parseTokens(lexed.tokens, lexed.diagnostics)
end

return Parser
