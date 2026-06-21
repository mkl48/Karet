-- AST node kinds for the Karet shell. The parser builds plain tables tagged with a
-- `kind` from Ast.Kind; the evaluator dispatches on it. See GRAMMAR.md §3.

local Ast = {}

Ast.Kind = {
	-- structure
	Program = "Program", -- { chains: {Chain} }
	Chain = "Chain", -- { steps: { {op: string?, node} }, directives: {string} }
	Command = "Command", -- { name, nameToken, args: {Arg}, flags: {string}, ambiguous: boolean? }
	Guarded = "Guarded", -- { guard: Guard, block: Program }
	Guard = "Guard", -- { terms: { {op: string?, negate: boolean, expr} } }
	ValueStmt = "ValueStmt", -- { value }  (a bare reference or group used as a statement)
	Pipeline = "Pipeline", -- { stages: {Command} }  (a | b | c: thread each output into the next)

	-- values / args
	Literal = "Literal", -- { valueType: "string"|"number"|"boolean"|"nil", value }
	Reference = "Reference", -- { last: boolean, name: string?, index: number?, path: {string} }
	VarRef = "VarRef", -- { name: string, path: {string} }
	TypeValue = "TypeValue", -- { typeName: string }
	Assignment = "Assignment", -- { name: string, value }

	-- expressions
	Binary = "Binary", -- { op: string, left, right }
	Unary = "Unary", -- { op: "~"|"neg", operand }
	IsNil = "IsNil", -- { operand }  (postfix `!`)
}

return Ast
