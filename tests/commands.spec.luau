-- Built-in commands, run end-to-end through the real Parser + Evaluator + Host with
-- stubbed services (so no terminal/theme/Roblox is needed).

local shell = require("./loader")
local fw = require("./fwloader")
local Assert = require("./assert")

local Parser = shell.get("Parser")
local Evaluator = shell.get("Evaluator")
local Registry = fw.get("Registry")
local Types = fw.get("Types")
local Host = fw.get("Host")
local Commands = fw.get("Commands")

-- Build a rig with the built-ins registered and stub services. Pass a `ui` table to
-- exercise the rich-output path (commands branch on ctx.UI.available).
local function rig(ui)
	local registry = Registry.new()
	local state = { cleared = false, theme = nil :: string? }
	local ev -- forward ref so the `run`/`functions` services can drive the same evaluator
	local fnStore = {} :: { [string]: string }
	local services = {
		clear = function()
			state.cleared = true
		end,
		setTheme = function(name)
			state.theme = name
		end,
		listThemes = function()
			return { "tokyonight", "gruvbox" }
		end,
		list = function()
			return registry:list()
		end,
		get = function(name)
			return registry:get(name)
		end,
		playerName = function()
			return "Tester"
		end,
		-- functions: store the body and register a runnable command (mirrors the real wiring)
		functions = {
			get = function(name)
				return fnStore[name]
			end,
			set = function(name, body)
				fnStore[name] = body
				registry:register({
					Name = name,
					Description = `function: {body}`,
					Network = "Client",
					On = { Client = function(ctx)
						local out = ev:run(Parser.parse(fnStore[name]).ast)
						if type(out) == "table" and out.ok == false and out.error then
							ctx.Abort(out.error)
						end
					end },
				})
			end,
			unset = function(name)
				fnStore[name] = nil
				registry:unregister(name)
			end,
			list = function()
				local names = {}
				for k in fnStore do
					table.insert(names, k)
				end
				table.sort(names)
				return names
			end,
		},
		version = "9.9.9",
	}
	for _, def in Commands.build(services) do
		registry:register(def)
	end

	local out = {}
	local host = Host.new({
		registry = registry,
		types = Types.new(),
		isClient = true,
		sink = function(group, message)
			table.insert(out, { group = group, message = message })
		end,
		hooks = { pre = {}, post = {}, onErr = {} },
		auth = { defaultRole = "User", allowed = {}, denied = {} },
		ui = ui,
	})
	ev = Evaluator.new(host)
	return {
		run = function(line)
			return ev:run(Parser.parse(line).ast)
		end,
		out = out,
		state = state,
	}
end

local function joined(out: { any }): string
	local parts = {}
	for _, line in out do
		table.insert(parts, line.message)
	end
	return table.concat(parts, "\n")
end

return function(t)
	t.test("version prints the injected version", function()
		local k = rig()
		k.run("version")
		Assert.eq(k.out[1].message, "Karet v9.9.9", "version output")
	end)

	t.test("echo prints its argument", function()
		local k = rig()
		k.run("echo hello")
		Assert.eq(k.out[1].message, "hello", "echoed")
	end)

	t.test("me uses playerName service", function()
		local k = rig()
		k.run("me")
		Assert.eq(k.out[1].message, "Tester", "name")
	end)

	t.test("ping pongs and returns", function()
		local k = rig()
		local result = k.run("ping")
		Assert.eq(k.out[1].message, "pong", "printed")
		Assert.truthy(result.ok, "ok")
	end)

	t.test("clear calls the clear service", function()
		local k = rig()
		k.run("clear")
		Assert.truthy(k.state.cleared, "clear ran")
	end)

	t.test("theme switches via the setTheme service", function()
		local k = rig()
		k.run("theme gruvbox")
		Assert.eq(k.state.theme, "gruvbox", "theme set")
		Assert.truthy(string.find(joined(k.out), "gruvbox"), "confirmation printed")
	end)

	t.test("themes lists available themes", function()
		local k = rig()
		k.run("themes")
		Assert.truthy(string.find(k.out[1].message, "tokyonight"), "lists tokyonight")
	end)

	t.test("help with no arg lists commands", function()
		local k = rig()
		k.run("help")
		Assert.truthy(string.find(joined(k.out), "echo"), "mentions a command")
	end)

	t.test("help <command> shows details", function()
		local k = rig()
		k.run("help echo")
		Assert.truthy(string.find(joined(k.out), "echo"), "names the command")
		Assert.truthy(string.find(joined(k.out), "text"), "shows the arg")
	end)

	t.test("aliases resolve (cls -> clear)", function()
		local k = rig()
		k.run("cls")
		Assert.truthy(k.state.cleared, "alias ran clear")
	end)

	-- when ctx.UI is available (a terminal), list commands render a table instead of text
	local function capturingUI()
		local calls = { tables = {} }
		return setmetatable({
			available = true,
			Table = function(opts)
				table.insert(calls.tables, opts)
			end,
		}, { __index = function()
			return function() end
		end }),
			calls
	end

	t.test("help renders a command table when UI is available", function()
		local ui, calls = capturingUI()
		local k = rig(ui)
		k.run("help")
		Assert.eq(#calls.tables, 1, "one table drawn")
		Assert.truthy(calls.tables[1].headers[1] == "command", "command column")
		Assert.truthy(#calls.tables[1].rows > 0, "has rows")
	end)

	t.test("themes renders a table when UI is available", function()
		local ui, calls = capturingUI()
		local k = rig(ui)
		k.run("themes")
		Assert.eq(#calls.tables, 1, "themes table drawn")
	end)

	t.test("function defines a runnable named macro", function()
		local k = rig()
		k.run('function hi "echo hello"')
		k.run("hi")
		Assert.truthy(string.find(joined(k.out), "hello"), "running the function ran its body")
	end)

	t.test("function body runs a multi-statement sequence", function()
		local k = rig()
		k.run('function two "echo one; echo two"')
		k.run("two")
		local text = joined(k.out)
		Assert.truthy(string.find(text, "one"), "first statement ran")
		Assert.truthy(string.find(text, "two"), "second statement ran")
	end)

	t.test("function wont clobber an existing command", function()
		local k = rig()
		k.run('function echo "echo nope"')
		Assert.truthy(string.find(joined(k.out), "already a command"), "explains why")
		-- echo still behaves like the builtin
		k.run("echo hi")
		Assert.truthy(string.find(joined(k.out), "hi"), "builtin echo intact")
	end)

	t.test("unfunction removes the function", function()
		local k = rig()
		k.run('function gone "echo x"')
		k.run("unfunction gone")
		local result = k.run("gone")
		Assert.falsy(result.ok, "function no longer exists")
	end)

	t.test("functions lists defined functions", function()
		local k = rig()
		k.run('function a "echo 1"')
		k.run('function b "echo 2"')
		k.run("functions")
		local text = joined(k.out)
		Assert.truthy(string.find(text, "a()"), "lists a")
		Assert.truthy(string.find(text, "b()"), "lists b")
	end)

	t.test("a function can call another function", function()
		local k = rig()
		k.run('function inner "echo deep"')
		k.run('function outer "inner"')
		k.run("outer")
		Assert.truthy(string.find(joined(k.out), "deep"), "nested function ran")
	end)
end
