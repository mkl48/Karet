local loader = require("./loader")
local Assert = require("./assert")

local Parser = loader.get("Parser")
local Evaluator = loader.get("Evaluator")

local PLAYERS = {
	Alice = { Name = "Alice", UserId = 10 },
	Bob = { Name = "Bob", UserId = 20 },
}

local function parseDuration(raw: any): number?
	if type(raw) ~= "string" then
		return nil
	end
	local num, unit = string.match(raw, "^(%d+)([smhd])$")
	if not num then
		return nil
	end
	local mult = ({ s = 1, m = 60, h = 3600, d = 86400 })[unit]
	return tonumber(num) * mult
end

-- A fake Host: stand-in registry + type system + runner, with shared state for asserts.
local function makeHost()
	local state = { marks = 0, lastEcho = nil }
	local commands: { [string]: any } = {}

	local function define(name, def)
		commands[name] = def
	end

	define("GetPlayer", {
		Args = { { Name = "name", Types = { "Player" }, Required = true } },
		Returns = { { Name = "player", Type = "Player" } },
		_run = function(inv)
			return { ok = true, returns = { inv.args.name } }
		end,
	})
	define("echo", {
		Args = { { Name = "value", Types = { "Number", "String" }, Required = true } },
		_run = function(inv)
			state.lastEcho = inv.args.value
			return { ok = true, returns = { inv.args.value } }
		end,
	})
	define("add", {
		Args = { { Name = "n", Types = { "Number" }, Required = true } },
		Returns = { { Name = "sum", Type = "Number" } },
		_run = function(inv)
			return { ok = true, returns = { inv.args.n } }
		end,
	})
	define("ok", { Args = {}, _run = function()
		return { ok = true }
	end })
	define("fail", { Args = {}, _run = function()
		return { ok = false, error = "nope" }
	end })
	define("mark", { Args = {}, _run = function()
		state.marks += 1
		return { ok = true }
	end })
	define("now", { Args = {}, Returns = { { Name = "t", Type = "String" } }, _run = function()
		return { ok = true, returns = { "NOW" } }
	end })

	local host = {}

	function host.getCommand(name)
		return commands[name]
	end

	function host.coerce(raw, types)
		for _, t in types do
			if t == "Number" then
				local n = tonumber(raw)
				if n then
					return n
				end
			elseif t == "Integer" then
				local n = tonumber(raw)
				if n and math.floor(n) == n then
					return n
				end
			elseif t == "String" then
				return tostring(raw)
			elseif t == "Boolean" then
				if raw == true or raw == "true" then
					return true
				elseif raw == false or raw == "false" then
					return false
				end
			elseif t == "Player" then
				if type(raw) == "table" and raw.UserId then
					return raw
				end
				local p = PLAYERS[raw]
				if p then
					return p
				end
			elseif t == "Duration" then
				local secs = parseDuration(raw)
				if secs then
					return secs
				end
			end
		end
		return nil, `'{tostring(raw)}' is not a {table.concat(types, "|")}`
	end

	function host.satisfies(value, typeName)
		local n = string.lower(typeName)
		if n == "number" then
			return type(value) == "number"
		elseif n == "string" then
			return type(value) == "string"
		elseif n == "boolean" then
			return type(value) == "boolean"
		elseif n == "player" then
			return type(value) == "table" and value.UserId ~= nil
		end
		return false
	end

	function host.run(inv)
		return inv.definition._run(inv)
	end

	return host, state
end

local function newEval()
	local host, state = makeHost()
	return Evaluator.new(host), state
end

local function run(ev, src)
	return ev:run(Parser.parse(src).ast)
end

return function(t)
	t.test("runs a command and pushes typed returns to the pool", function()
		local ev = newEval()
		local r = run(ev, "GetPlayer Alice")
		Assert.truthy(r.ok, "command ok")
		Assert.eq((ev.pool:resolve({ name = "Player", path = {} })).UserId, 10, "/Player.UserId")
		Assert.eq((ev.pool:resolve({ last = true, path = { "Name" } })), "Alice", "//.Name")
		Assert.eq((ev.pool:resolve({ name = "player", path = {} })).UserId, 10, "/player by label")
	end)

	t.test("&& continues on success, skips the rest on failure", function()
		local ev = newEval()
		local ev2, state = newEval()
		Assert.truthy(run(ev, "ok && ok").ok, "ok && ok succeeds")
		Assert.falsy(run(ev2, "fail && mark").ok, "fail && mark fails")
		Assert.eq(state.marks, 0, "mark after failed && did not run")
	end)

	t.test("|| runs the alternative only on failure", function()
		local ev, state = newEval()
		Assert.truthy(run(ev, "fail || mark").ok, "fail || mark recovers")
		Assert.eq(state.marks, 1, "mark ran once")
		run(ev, "ok || mark")
		Assert.eq(state.marks, 1, "mark did not run after ok")
	end)

	t.test("& runs regardless", function()
		local ev, state = newEval()
		run(ev, "fail & mark")
		Assert.eq(state.marks, 1, "& always runs next")
	end)

	t.test("failed commands do not pollute the pool", function()
		local ev = newEval()
		run(ev, "fail")
		local _, err = ev.pool:resolve({ last = true, path = {} })
		Assert.truthy(err, "pool is empty after a failure")
	end)

	t.test("variable assignment persists and resolves", function()
		local ev = newEval()
		run(ev, "(x = 5)\necho @x")
		Assert.eq((ev.pool:resolve({ last = true, path = {} })), 5, "echo returned 5")
	end)

	t.test("command substitution bound to a variable", function()
		local ev = newEval()
		run(ev, "(p = (GetPlayer Bob))\necho @p.UserId")
		Assert.eq((ev.pool:resolve({ last = true, path = {} })), 20, "echoed Bob.UserId")
	end)

	t.test("expression argument is computed then typed", function()
		local ev = newEval()
		run(ev, "add (3 + 4 * 2)")
		Assert.eq((ev.pool:resolve({ last = true, path = {} })), 11, "3 + 4*2 = 11")
	end)

	t.test("guard runs block only when true", function()
		local ev, state = newEval()
		run(ev, "(x = 5)")
		run(ev, "(@x == 5){ mark }")
		Assert.eq(state.marks, 1, "guard true -> block ran")
		run(ev, "(@x == 9){ mark }")
		Assert.eq(state.marks, 1, "guard false -> block skipped")
	end)

	t.test("type guard via injected satisfies", function()
		local ev, state = newEval()
		run(ev, "(x = 5)")
		run(ev, "(@x == @TYPE[Number]){ mark }")
		Assert.eq(state.marks, 1, "5 satisfies Number")
		run(ev, "(@x == @TYPE[Player]){ mark }")
		Assert.eq(state.marks, 1, "5 does not satisfy Player")
	end)

	t.test("not-nil guard with postfix ~!", function()
		local ev, state = newEval()
		run(ev, "(x = 5)")
		run(ev, "(@x ~!){ mark }")
		Assert.eq(state.marks, 1, "@x is not nil -> ran")
		run(ev, "(@y ~!){ mark }")
		Assert.eq(state.marks, 1, "@y is nil -> skipped")
	end)

	t.test("ambiguous lone word: command if registered else literal", function()
		local ev, state = newEval()
		run(ev, "echo (now)")
		Assert.eq(state.lastEcho, "NOW", "(now) ran as a command")
		run(ev, "echo (nope)")
		Assert.eq(state.lastEcho, "nope", "(nope) fell back to a literal")
	end)

	t.test("type errors surface as a failed result", function()
		local ev = newEval()
		local r = run(ev, "GetPlayer Nobody")
		Assert.falsy(r.ok, "unknown player fails coercion")
		Assert.truthy(r.error, "has an error message")
	end)

	t.test("unknown command fails cleanly", function()
		local ev = newEval()
		local r = run(ev, "frobnicate 1 2 3")
		Assert.falsy(r.ok, "unknown command")
	end)
end
