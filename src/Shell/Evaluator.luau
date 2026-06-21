-- The Karet shell evaluator: walk an AST, run chains/guards, drive the return pool and
-- session variables, and evaluate expressions/type-guards.
--
-- The evaluator fully resolves AND types arguments (the chosen model), so it depends on a
-- `Host` for the registry + type system + execution. Everything realm/networking/auth
-- specific lives behind the host, keeping this module pure and testable with a fake one.
--
-- Host interface:
--   getCommand(name)            -> definition? { Args, Returns, Attributes, ... }
--   coerce(rawValue, types)     -> (typedValue, errorMessage?)   -- parse+validate a slot
--   satisfies(value, typeName)  -> boolean                       -- for @TYPE[...] guards
--   run(invocation)             -> { ok: boolean, returns: {any}?, error: string? }
--     invocation = { name, definition, args = {[string]: any}, attributes = {[string]: boolean}, node }
--
-- A command definition's relevant fields:
--   Args  = { { Name, Types: {string}, Required: boolean?, Default: any? }, ... }
--   Returns = { { Name, Type }, ... }
--   Attributes = { { Name, Short }, ... }

local ReturnPool = require(script.Parent.ReturnPool)
local Ast = require(script.Parent.Ast)

local N = Ast.Kind

local Evaluator = {}
Evaluator.__index = Evaluator

local function truthy(v: any): boolean
	return v ~= nil and v ~= false
end

local function inferType(v: any): string
	local t = type(v)
	if t == "number" then
		return "Number"
	elseif t == "string" then
		return "String"
	elseif t == "boolean" then
		return "Boolean"
	elseif t == "table" then
		return "Table"
	end
	return "Value"
end

-- `scope` is the @name variable store. Pass a shared table to seed defaults / persist env
-- vars across the session (Karet.Env); omit it for an isolated scope (tests).
function Evaluator.new(host: any, scope: { [string]: any }?)
	return setmetatable({
		host = host,
		pool = ReturnPool.new(),
		scope = scope or {}, -- session variables: @name -> value
	}, Evaluator)
end

-- reset per-session state (e.g. when the terminal closes, if you want a clean slate)
function Evaluator:reset()
	self.pool:clear()
	table.clear(self.scope)
end

-- ---- expression evaluation: returns (value, errorMessage?) ----

function Evaluator:evalExpr(node: any): (any, string?)
	local k = node.kind
	if k == N.Literal then
		return node.value, nil
	elseif k == N.VarRef then
		local value = self.scope[node.name]
		for _, key in node.path do
			if value == nil then
				return nil, `cannot read '{key}' of nil (@{node.name})`
			end
			local ok, got = pcall(function()
				return (value :: any)[key]
			end)
			if not ok then
				return nil, `cannot index '{key}' on @{node.name}`
			end
			value = got
		end
		return value, nil
	elseif k == N.Reference then
		return self.pool:resolve(node)
	elseif k == N.TypeValue then
		-- a bare type value; only meaningful as a == / != right-hand side (handled below)
		return { __karetType = node.typeName }, nil
	elseif k == N.IsNil then
		local v, err = self:evalExpr(node.operand)
		if err then
			return nil, err
		end
		return v == nil, nil
	elseif k == N.Unary then
		local v, err = self:evalExpr(node.operand)
		if err then
			return nil, err
		end
		if node.op == "~" then
			return not truthy(v), nil
		else -- "neg"
			if type(v) ~= "number" then
				return nil, "cannot negate a non-number"
			end
			return -v, nil
		end
	elseif k == N.Binary then
		return self:evalBinary(node)
	elseif k == N.Command then
		-- command substitution used as a value: run it, take its first return
		local result = self:executeCommand(node)
		if not result.ok then
			return nil, result.error or "command failed"
		end
		local returns = result.returns
		if returns and #returns > 0 then
			return returns[1], nil
		end
		return nil, nil
	elseif k == N.Assignment then
		local v, err = self:evalExpr(node.value)
		if err then
			return nil, err
		end
		self.scope[node.name] = v
		return v, nil
	end
	return nil, `cannot evaluate node '{tostring(k)}'`
end

function Evaluator:evalBinary(node: any): (any, string?)
	local op = node.op

	-- boolean and/or with Lua short-circuit semantics
	if op == "&&" then
		local l, lerr = self:evalExpr(node.left)
		if lerr then
			return nil, lerr
		end
		if not truthy(l) then
			return l, nil
		end
		return self:evalExpr(node.right)
	elseif op == "||" then
		local l, lerr = self:evalExpr(node.left)
		if lerr then
			return nil, lerr
		end
		if truthy(l) then
			return l, nil
		end
		return self:evalExpr(node.right)
	end

	-- type-satisfaction: `value == @TYPE[name]` / `value != @TYPE[name]`
	if (op == "==" or op == "!=") and node.right.kind == N.TypeValue then
		local l, lerr = self:evalExpr(node.left)
		if lerr then
			return nil, lerr
		end
		local ok = self.host.satisfies(l, node.right.typeName)
		if op == "!=" then
			ok = not ok
		end
		return ok, nil
	end

	local l, lerr = self:evalExpr(node.left)
	if lerr then
		return nil, lerr
	end
	local r, rerr = self:evalExpr(node.right)
	if rerr then
		return nil, rerr
	end

	if op == "==" then
		return l == r, nil
	elseif op == "!=" then
		return l ~= r, nil
	elseif op == ">" or op == "<" or op == ">=" or op == "<=" then
		if type(l) ~= type(r) or (type(l) ~= "number" and type(l) ~= "string") then
			return nil, `cannot compare {inferType(l)} {op} {inferType(r)}`
		end
		if op == ">" then
			return l > r, nil
		elseif op == "<" then
			return l < r, nil
		elseif op == ">=" then
			return l >= r, nil
		else
			return l <= r, nil
		end
	elseif op == "+" or op == "-" or op == "*" or op == "/" or op == "%" then
		if type(l) ~= "number" or type(r) ~= "number" then
			return nil, `arithmetic needs numbers, got {inferType(l)} {op} {inferType(r)}`
		end
		if op == "+" then
			return l + r, nil
		elseif op == "-" then
			return l - r, nil
		elseif op == "*" then
			return l * r, nil
		elseif op == "/" then
			return l / r, nil
		else
			return l % r, nil
		end
	end
	return nil, `unknown operator '{op}'`
end

-- ---- argument resolution + typing ----

-- resolve the expression layer of one argument to a raw value
function Evaluator:resolveArg(argNode: any): (any, string?)
	return self:evalExpr(argNode)
end

-- expand raw flag chunks (e.g. "sp", "silent") against the command's Attributes
local function resolveFlags(rawChunks: { string }, attributes: { any }?): ({ [string]: boolean }, string?)
	local set: { [string]: boolean } = {}
	local byName: { [string]: any } = {}
	local byShort: { [string]: any } = {}
	for _, attr in attributes or {} do
		byName[attr.Name] = attr
		if attr.Short then
			byShort[attr.Short] = attr
		end
	end
	for _, chunk in rawChunks do
		if byName[chunk] then
			set[byName[chunk].Name] = true
		else
			-- stacked single-char shorts: -sp => s, p
			for i = 1, #chunk do
				local c = string.sub(chunk, i, i)
				local attr = byShort[c]
				if not attr then
					return set, `unknown flag '-{chunk}'`
				end
				set[attr.Name] = true
			end
		end
	end
	return set, nil
end

-- ---- command execution ----

function Evaluator:executeCommand(node: any): any
	local host = self.host

	-- lone ambiguous word in a group: command if registered, else a literal string
	if node.ambiguous then
		if not host.getCommand(node.name) then
			return { ok = true, returns = { node.name } }
		end
	end

	local def = host.getCommand(node.name)
	if not def then
		return { ok = false, error = `unknown command '{node.name}'` }
	end

	-- resolve + type the positional args against the Args schema
	local typedArgs: { [string]: any } = {}
	local specs = def.Args or {}
	if #node.args > #specs then
		return { ok = false, error = `'{node.name}' takes {#specs} argument(s), got {#node.args}` }
	end
	for i, spec in specs do
		local argNode = node.args[i]
		if argNode ~= nil then
			local raw, rerr = self:resolveArg(argNode)
			if rerr then
				return { ok = false, error = rerr }
			end
			local typed, terr = host.coerce(raw, spec.Types)
			if terr then
				return { ok = false, error = `argument '{spec.Name}': {terr}` }
			end
			typedArgs[spec.Name] = typed
		elseif spec.Required then
			return { ok = false, error = `missing required argument '{spec.Name}'` }
		else
			typedArgs[spec.Name] = spec.Default
		end
	end

	local flags, ferr = resolveFlags(node.flags, def.Attributes)
	if ferr then
		return { ok = false, error = ferr }
	end

	-- valued long options (--name=value): resolve each value expression
	local options: { [string]: any } = {}
	for name, valueNode in node.options or {} do
		local v, oerr = self:evalExpr(valueNode)
		if oerr then
			return { ok = false, error = `option '--{name}': {oerr}` }
		end
		options[name] = v
	end

	local result = host.run({
		name = node.name,
		definition = def,
		args = typedArgs,
		attributes = flags,
		options = options,
		node = node,
	})

	-- tag successful returns and push them to the pool
	if result.ok and result.returns then
		local returnSpecs = def.Returns or {}
		for i, value in result.returns do
			local rspec = returnSpecs[i]
			self.pool:push(value, rspec and rspec.Type or inferType(value), rspec and rspec.Name, node.name)
		end
	end

	return result
end

-- ---- guards / statements / chains / program ----

function Evaluator:evalGuard(guard: any): (boolean, string?)
	local acc: boolean? = nil
	for _, term in guard.terms do
		local v, err = self:evalExpr(term.expr)
		if err then
			return false, err
		end
		local tv = truthy(v)
		if term.negate then
			tv = not tv
		end
		if acc == nil then
			acc = tv
		elseif term.op == "&&" then
			acc = acc and tv
		elseif term.op == "||" then
			acc = acc or tv
		end
	end
	return acc == true, nil
end

function Evaluator:executeStatement(node: any): any
	if node == nil then
		return { ok = false, error = "empty statement" }
	end
	local k = node.kind
	if k == N.Command then
		return self:executeCommand(node)
	elseif k == N.Guarded then
		local pass, err = self:evalGuard(node.guard)
		if err then
			return { ok = false, error = err }
		end
		if not pass then
			return { ok = true, skipped = true }
		end
		return self:executeProgram(node.block)
	elseif k == N.ValueStmt then
		local v, err = self:evalExpr(node.value)
		if err then
			return { ok = false, error = err }
		end
		-- a bare value statement contributes to the pool
		self.pool:push(v, inferType(v), nil, "value")
		return { ok = true, returns = { v } }
	end
	return { ok = false, error = `cannot execute statement '{tostring(k)}'` }
end

function Evaluator:executeChain(chain: any): any
	local directives: { [string]: boolean } = {}
	for _, d in chain.directives do
		directives[d] = true
	end
	local ignoreErrors = directives["Ignore-Errors"] == true
	local dryRun = directives["Dry-Run"] == true

	local result: any = nil
	for index, step in chain.steps do
		local shouldRun
		if index == 1 then
			shouldRun = true
		elseif step.op == "&" then
			shouldRun = true
		elseif step.op == "&&" then
			shouldRun = result.ok or ignoreErrors
		elseif step.op == "||" then
			shouldRun = not result.ok and not ignoreErrors
		else
			shouldRun = true
		end

		if shouldRun then
			if dryRun then
				result = { ok = true, dryRun = true }
			else
				result = self:executeStatement(step.node)
				if ignoreErrors and not result.ok then
					result = { ok = true, suppressed = result.error }
				end
			end
		end
	end
	return result or { ok = true }
end

function Evaluator:executeProgram(program: any): any
	local last: any = { ok = true }
	for _, chain in program.chains do
		last = self:executeChain(chain)
	end
	return last
end

-- run a parsed Program AST; returns the last chain's result
function Evaluator:run(program: any): any
	return self:executeProgram(program)
end

return Evaluator
