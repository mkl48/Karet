-- Integration: the real shell Parser + Evaluator driving the framework Host. This is the
-- whole local pipeline — parse a line, type-check args, run the handler, collect output and
-- returns, honour chain control / middleware / abort — exercised end-to-end without Roblox.

local shell = require("./loader") -- src/Shell modules
local fw = require("./fwloader") -- framework modules
local Assert = require("./assert")

local Parser = shell.get("Parser")
local Evaluator = shell.get("Evaluator")
local Registry = fw.get("Registry")
local Types = fw.get("Types")
local Host = fw.get("Host")

-- Build a host + evaluator over a registry, capturing output into `out`.
local function rig(register: (any) -> ())
	local registry = Registry.new()
	local types = Types.new()
	register(registry)
	local out = {}
	local hooks = { pre = {}, post = {}, onErr = {} }
	local host = Host.new({
		registry = registry,
		types = types,
		isClient = true,
		sink = function(group, message)
			table.insert(out, { group = group, message = message })
		end,
		hooks = hooks,
		auth = { defaultRole = "User", allowed = {}, denied = {} },
	})
	local ev = Evaluator.new(host)
	local function run(line: string)
		local parsed = Parser.parse(line)
		return ev:run(parsed.ast), parsed
	end
	return { run = run, out = out, ev = ev, hooks = hooks, host = host }
end

local function greetCommand(r)
	r:register({
		Name = "greet",
		Network = "Shared",
		Args = { { Name = "who", Types = { "String" }, Required = true } },
		Returns = { { Name = "msg", Type = "String" } },
		On = {
			Shared = function(ctx)
				ctx.Print("hi " .. ctx.Args.who)
				ctx.Return("hi " .. ctx.Args.who)
			end,
		},
	})
end

return function(t)
	t.test("runs a Shared command: output + returns + pool", function()
		local k = rig(greetCommand)
		local result = k.run("greet World")
		Assert.truthy(result.ok, "command ok")
		Assert.eq(k.out[1], { group = "Output", message = "hi World" }, "printed")
		Assert.eq(k.ev.pool:last().value, "hi World", "return pooled")
		Assert.eq(k.ev.pool:last().label, "msg", "return labelled from schema")
	end)

	t.test("typed args: coercion failure rejects before the handler", function()
		local ran = false
		local k = rig(function(r)
			r:register({
				Name = "wait",
				Network = "Shared",
				Args = { { Name = "secs", Types = { "Number" }, Required = true } },
				On = { Shared = function() ran = true end },
			})
		end)
		local result = k.run("wait notanumber")
		Assert.falsy(result.ok, "rejected")
		Assert.falsy(ran, "handler never ran")
		Assert.truthy(string.find(result.error, "secs"), "error names the arg")
	end)

	t.test("missing required argument is reported", function()
		local k = rig(greetCommand)
		local result = k.run("greet")
		Assert.falsy(result.ok, "rejected")
		Assert.truthy(string.find(result.error, "who"), "names the missing arg")
	end)

	t.test("unknown command errors", function()
		local k = rig(greetCommand)
		local result = k.run("nope")
		Assert.falsy(result.ok, "rejected")
		Assert.truthy(string.find(result.error, "nope"), "names the command")
	end)

	t.test("chain control: && runs the second only on success", function()
		local k = rig(greetCommand)
		k.run("greet A && greet B")
		Assert.eq(#k.out, 2, "both ran")
		Assert.eq(k.out[2].message, "hi B", "second ran after success")
	end)

	t.test("chain control: || skips after success", function()
		local k = rig(greetCommand)
		k.run("greet A || greet B")
		Assert.eq(#k.out, 1, "second skipped after success")
	end)

	t.test("default argument fills when omitted", function()
		local k = rig(function(r)
			r:register({
				Name = "echo",
				Network = "Shared",
				Args = { { Name = "text", Types = { "String" }, Required = false, Default = "default" } },
				On = { Shared = function(ctx) ctx.Print(ctx.Args.text) end },
			})
		end)
		k.run("echo")
		Assert.eq(k.out[1].message, "default", "used the default")
	end)

	t.test("middleware PreExecute can cancel", function()
		local k = rig(greetCommand)
		table.insert(k.hooks.pre, function()
			return false
		end)
		local result = k.run("greet World")
		Assert.falsy(result.ok, "cancelled")
		Assert.eq(#k.out, 0, "handler never printed")
	end)

	t.test("ctx.Abort cancels mid-handler with its message", function()
		local k = rig(function(r)
			r:register({
				Name = "danger",
				Network = "Shared",
				On = { Shared = function(ctx)
					ctx.Abort("too risky")
				end },
			})
		end)
		local result = k.run("danger")
		Assert.falsy(result.ok, "aborted")
		Assert.eq(result.error, "too risky", "abort message surfaced")
	end)

	t.test("attributes (flags) reach the handler", function()
		local seen
		local k = rig(function(r)
			r:register({
				Name = "ban",
				Network = "Shared",
				Attributes = { { Name = "permanent", Short = "p" } },
				On = { Shared = function(ctx)
					seen = ctx.Attributes.permanent
				end },
			})
		end)
		k.run("ban -p")
		Assert.truthy(seen, "flag set true")
	end)

	-- Dangerous commands run through a confirm gate (Start{ PromptType } wires the real one).
	local function rigConfirm(confirmFn)
		local registry = Registry.new()
		local types = Types.new()
		local ran = false
		registry:register({
			Name = "nuke",
			Network = "Shared",
			Dangerous = true,
			On = { Shared = function() ran = true end },
		})
		local host = Host.new({
			registry = registry,
			types = types,
			isClient = true,
			sink = function() end,
			confirm = confirmFn,
		})
		local ev = Evaluator.new(host)
		local function run(line)
			return ev:run(Parser.parse(line).ast)
		end
		return { run = run, ranRef = function() return ran end }
	end

	t.test("dangerous command is cancelled when confirm says no", function()
		local asked
		local k = rigConfirm(function(name)
			asked = name
			return false
		end)
		local result = k.run("nuke")
		Assert.eq(asked, "nuke", "confirm got the command name")
		Assert.falsy(result.ok, "cancelled")
		Assert.falsy(k.ranRef(), "handler never ran")
	end)

	t.test("dangerous command runs when confirm says yes", function()
		local k = rigConfirm(function()
			return true
		end)
		local result = k.run("nuke")
		Assert.truthy(result.ok, "ran")
		Assert.truthy(k.ranRef(), "handler ran")
	end)

	t.test("ctx.Indicator is a chainable no-op without a terminal", function()
		local ok = false
		local k = rig(function(r)
			r:register({
				Name = "load",
				Network = "Shared",
				On = { Shared = function(ctx)
					-- every method chains and returns the handle; nothing should error
					ctx.Indicator({ type = "progress" }):Set(0.5):Step():Succeed("done")
					ok = true
				end },
			})
		end)
		k.run("load")
		Assert.truthy(ok, "indicator calls didn't error")
	end)

	t.test("guarded block: assignment guard term binds then runs the block", function()
		local ran = 0
		local k = rig(function(r)
			r:register({ Name = "mark", Network = "Shared", On = { Shared = function() ran += 1 end } })
		end)
		-- (x = 2) binds @x = 2; @x == @TYPE[number] is type-satisfaction (lowercase ok)
		k.run('(x = 2) && (@x == @TYPE[number]) { mark }')
		Assert.eq(ran, 1, "block ran when both guard terms passed")
		k.run('(y = 2) && (@y == @TYPE[string]) { mark }')
		Assert.eq(ran, 1, "block skipped when a guard term failed")
	end)

	t.test("case-insensitive @TYPE names resolve", function()
		local k = rig(greetCommand)
		k.run('(n = 5) && (@n == @TYPE[NUMBER]) { greet ok }')
		Assert.eq(k.out[#k.out] and k.out[#k.out].message, "hi ok", "NUMBER matched the value")
	end)

	t.test("ctx.Success / ctx.Hint route to their theme groups", function()
		local k = rig(function(r)
			r:register({ Name = "ok", Network = "Shared", On = { Shared = function(ctx)
				ctx.Success("done")
				ctx.Hint("psst")
			end } })
		end)
		local result = k.run("ok")
		Assert.truthy(result.ok, "no nil-call error")
		Assert.eq(k.out[1], { group = "Success", message = "done" }, "Success group")
		Assert.eq(k.out[2], { group = "Hint", message = "psst" }, "Hint group")
	end)

	t.test("ctx.UI is a no-op toolkit without a terminal", function()
		local ok = false
		local k = rig(function(r)
			r:register({
				Name = "report",
				Network = "Shared",
				On = { Shared = function(ctx)
					ctx.UI.Rule("hi")
					ctx.UI.Table({ headers = { "a" }, rows = { { "1" } } })
					ctx.UI.Panel("body", { title = "t" })
					ok = true
				end },
			})
		end)
		k.run("report")
		Assert.truthy(ok, "ui calls didn't error")
	end)
end
