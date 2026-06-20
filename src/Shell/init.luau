-- The Karet shell: the tokenizer + parser + evaluator that turn a line of input into an
-- executed chain. This is the power-user surface; the umbrella `Karet` re-exports the
-- common entry points (Karet.Tokenize / Parse / Analyze / ...) flat.

local Token = require(script.Token)
local Ast = require(script.Ast)
local Lexer = require(script.Lexer)
local Parser = require(script.Parser)
local ReturnPool = require(script.ReturnPool)
local Evaluator = require(script.Evaluator)

local Shell = {}

Shell.Token = Token
Shell.Ast = Ast
Shell.Lexer = Lexer
Shell.Parser = Parser
Shell.ReturnPool = ReturnPool
Shell.Evaluator = Evaluator

-- raw source -> { tokens, diagnostics }
function Shell.Tokenize(raw: string)
	return Lexer.tokenize(raw)
end

-- raw source -> { ast, diagnostics }
function Shell.Parse(raw: string)
	return Parser.parse(raw)
end

-- One static pass for as-you-type validation. Today it returns lexical + syntactic
-- diagnostics and the AST; registry-aware analysis (resolved command, expected next arg,
-- type errors, completions) layers on once a host/registry is threaded through. (§GRAMMAR)
function Shell.Analyze(source: string)
	local parsed = Parser.parse(source)
	return {
		ast = parsed.ast,
		diagnostics = parsed.diagnostics,
	}
end

-- Construct an evaluator bound to a host (registry + type system + runner). Holds the
-- session's return pool and variable scope. Pass a shared `scope` table to seed env-var
-- defaults and keep them across the session.
function Shell.newEvaluator(host: any, scope: { [string]: any }?)
	return Evaluator.new(host, scope)
end

return Shell
