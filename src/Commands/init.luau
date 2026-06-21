-- Karet's built-in commands. Returns command definitions parameterised by a small
-- `services` table, so the commands stay decoupled from the umbrella (and are testable
-- headlessly by passing stubs). Karet.Start registers these unless BuiltIns = false.
--
-- services = {
--   clear()            -> clear the terminal output
--   setTheme(name)     -> switch the active theme
--   listThemes()       -> { string } of theme names
--   list()             -> { string } of registered command names
--   get(name)          -> definition? for a command
--   playerName()       -> the local player's name (or "server")
--   version            -> Karet.Version string
-- }

local Commands = {}

export type Services = {
	clear: () -> (),
	setTheme: (name: string) -> (),
	listThemes: () -> { string },
	list: () -> { string },
	get: (name: string) -> any?,
	playerName: () -> string,
	player: (() -> any)?,
	editor: (() -> any)?,
	closeTerminal: (() -> ())?,
	history: (() -> { string })?,
	env: {
		get: (name: string) -> any,
		set: (name: string, value: any) -> (),
		unset: (name: string) -> (),
		list: () -> { string },
	}?,
	openConfig: (() -> ())?,
	run: ((line: string) -> any)?,
	defaults: { [string]: any }?,
	version: string,
}

-- turn a raw `set` value into a typed one: booleans and numbers parse, everything else
-- stays a string (so `set hp 100` stores a number, `set name bob` stores a string).
local function coerceValue(s: string): any
	if s == "true" then
		return true
	elseif s == "false" then
		return false
	end
	return tonumber(s) or s
end

-- Build the list of built-in command definitions.
function Commands.build(services: Services): { any }
	local defs = {
		{
			Name = "help",
			Aliases = { "h", "?" },
			Description = "list commands, or show one command's details",
			Network = "Client",
			Args = { { Name = "command", Types = { "String" }, Required = false } },
			On = {
				Client = function(ctx)
					local rich = ctx.UI.available == true
					local which = ctx.Args.command
					if which then
						local def = services.get(which)
						if not def then
							return ctx.Err(`no command '{which}'`)
						end
						ctx.Print(`{def.Name}{def.Description and " - " .. def.Description or ""}`)
						if rich then
							if def.Args and #def.Args > 0 then
								local rows = {}
								for _, arg in def.Args do
									table.insert(rows, { `<{arg.Name}{arg.Required and "" or "?"}>`, table.concat(arg.Types, " | ") })
								end
								ctx.UI.Table({ headers = { "argument", "types" }, rows = rows })
							end
							if def.Attributes and #def.Attributes > 0 then
								local rows = {}
								for _, attr in def.Attributes do
									table.insert(rows, { "-" .. (attr.Short or attr.Name), attr.Description or attr.Name })
								end
								ctx.UI.Table({ headers = { "flag", "description" }, rows = rows })
							end
						else
							for _, arg in def.Args or {} do
								ctx.Info(`  <{arg.Name}{arg.Required and "" or "?"}> : {table.concat(arg.Types, " | ")}`)
							end
							for _, attr in def.Attributes or {} do
								ctx.Info(`  -{attr.Short or attr.Name}  {attr.Description or attr.Name}`)
							end
						end
					elseif rich then
						local rows = {}
						for _, name in services.list() do
							local d = services.get(name)
							table.insert(rows, { name, (d and d.Description) or "" })
						end
						ctx.UI.Table({ headers = { "command", "description" }, rows = rows })
						ctx.Info("type  help <command>  for details")
					else
						ctx.Print("commands: " .. table.concat(services.list(), ", "))
						ctx.Info("type  help <command>  for details")
					end
				end,
			},
		},

		{
			Name = "commands",
			Aliases = { "cmds" },
			Description = "list every registered command",
			Network = "Client",
			On = { Client = function(ctx)
				if ctx.UI.available == true then
					local rows = {}
					for _, name in services.list() do
						local d = services.get(name)
						table.insert(rows, { name, (d and d.Description) or "" })
					end
					ctx.UI.Table({ headers = { "command", "description" }, rows = rows })
				else
					ctx.Print(table.concat(services.list(), ", "))
				end
			end },
		},

		{
			Name = "clear",
			Aliases = { "cls" },
			Description = "clear the terminal output",
			Network = "Client",
			On = { Client = function()
				services.clear()
			end },
		},

		{
			Name = "echo",
			Aliases = { "print" },
			Description = "print text back",
			Network = "Client",
			Args = { { Name = "text", Types = { "String" }, Required = true } },
			On = { Client = function(ctx)
				ctx.Print(ctx.Args.text)
			end },
		},

		{
			Name = "version",
			Aliases = { "ver" },
			Description = "show the Karet version",
			Network = "Client",
			On = { Client = function(ctx)
				ctx.Print(`Karet v{services.version}`)
			end },
		},

		{
			Name = "time",
			Description = "show the current time",
			Network = "Client",
			On = { Client = function(ctx)
				ctx.Print(os.date("%H:%M:%S"))
			end },
		},

		{
			Name = "me",
			Aliases = { "whoami" },
			Description = "show your name",
			Network = "Client",
			On = { Client = function(ctx)
				ctx.Print(services.playerName())
			end },
		},

		{
			Name = "ping",
			Description = "pong",
			Network = "Client",
			On = { Client = function(ctx)
				ctx.Print("pong")
				ctx.Return("pong")
			end },
		},

		{
			Name = "theme",
			Description = "switch the active colour theme",
			Network = "Client",
			Args = { { Name = "name", Types = { "String" }, Required = true } },
			On = { Client = function(ctx)
				local ok, err = pcall(services.setTheme, ctx.Args.name)
				if ok then
					ctx.Print(`theme set to {ctx.Args.name}`)
				else
					ctx.Err(tostring(err))
				end
			end },
		},

		{
			Name = "themes",
			Description = "list the available themes",
			Network = "Client",
			On = { Client = function(ctx)
				local names = services.listThemes()
				if ctx.UI.available == true then
					local rows = {}
					for _, name in names do
						table.insert(rows, { name })
					end
					ctx.UI.Table({ headers = { "theme" }, rows = rows })
				else
					ctx.Print(table.concat(names, ", "))
				end
			end },
		},

		{
			Name = "kaveat",
			Aliases = { "kav" },
			Description = "open the script editor",
			Network = "Client",
			Args = { { Name = "file", Types = { "String" }, Required = false } },
			Attributes = {
				{ Name = "server", Short = "s", Description = "edit in server context" },
				{ Name = "client", Short = "c", Description = "edit in client context" },
			},
			On = { Client = function(ctx)
				local editor = services.editor and services.editor()
				if not editor then
					ctx.Err("kaveat isnt on, start with Kaveat = true")
					return
				end
				local a = ctx.Attributes
				if a.server and a.client then
					ctx.Err("cant be both server and client")
					return
				end
				if a.server then
					editor:setContext("Server")
				end
				if a.client then
					editor:setContext("Client")
				end
				-- hand keyboard focus over to the editor
				if services.closeTerminal then
					services.closeTerminal()
				end
				local file = ctx.Args.file
				if file then
					editor:openFile(file)
				else
					editor:open()
				end
			end },
		},

		-- ----- config -----

		{
			Name = "config",
			Aliases = { "cfg", "settings" },
			Description = "open the @CONFIG editor (theme, placement, prompt...)",
			Network = "Client",
			On = { Client = function(ctx)
				if not (services.editor and services.editor()) then
					return ctx.Err("config needs Kaveat - start with Karet.Start{ Kaveat = true }")
				end
				if not services.openConfig then
					return ctx.Err("config editor unavailable")
				end
				ctx.Info("opening @CONFIG in kaveat (edit values, then :w to apply)")
				services.openConfig()
			end },
		},

		{
			Name = "defaults",
			Aliases = { "consts" },
			Description = "show karet's default constants (fonts, sizes, timings...)",
			Network = "Client",
			On = { Client = function(ctx)
				local d = services.defaults
				if not d then
					return ctx.Err("defaults unavailable")
				end
				local groups = {}
				for g in d do
					table.insert(groups, g)
				end
				table.sort(groups)
				local rows = {}
				for _, g in groups do
					local v = d[g]
					if type(v) == "table" then
						local keys = {}
						for k in v do
							table.insert(keys, k)
						end
						table.sort(keys)
						for _, k in keys do
							table.insert(rows, { `{g}.{k}`, tostring(v[k]) })
						end
					else
						table.insert(rows, { g, tostring(v) })
					end
				end
				if ctx.UI.available == true then
					ctx.UI.Table({ headers = { "key", "value" }, rows = rows })
				else
					for _, r in rows do
						ctx.Print(`{r[1]} = {r[2]}`)
					end
				end
			end },
		},

		-- ----- environment variables (@name) -----

		{
			Name = "set",
			Description = "set a shell variable: set name value  (read it back as @name)",
			Network = "Client",
			Args = {
				{ Name = "name", Types = { "String" }, Required = true },
				{ Name = "value", Types = { "String" }, Required = true },
			},
			On = { Client = function(ctx)
				if not services.env then
					return ctx.Err("env vars unavailable")
				end
				services.env.set(ctx.Args.name, coerceValue(ctx.Args.value))
				ctx.Success(`@{ctx.Args.name} = {ctx.Args.value}`)
			end },
		},

		{
			Name = "get",
			Description = "read a shell variable",
			Network = "Client",
			Args = { { Name = "name", Types = { "String" }, Required = true } },
			On = { Client = function(ctx)
				if not services.env then
					return ctx.Err("env vars unavailable")
				end
				local v = services.env.get(ctx.Args.name)
				if v == nil then
					ctx.Warn(`@{ctx.Args.name} is unset`)
				else
					ctx.Print(`@{ctx.Args.name} = {tostring(v)}`)
					ctx.Return(v)
				end
			end },
		},

		{
			Name = "unset",
			Description = "remove a shell variable",
			Network = "Client",
			Args = { { Name = "name", Types = { "String" }, Required = true } },
			On = { Client = function(ctx)
				if not services.env then
					return ctx.Err("env vars unavailable")
				end
				services.env.unset(ctx.Args.name)
				ctx.Info(`unset @{ctx.Args.name}`)
			end },
		},

		{
			Name = "vars",
			Aliases = { "env" },
			Description = "list shell variables and their values",
			Network = "Client",
			On = { Client = function(ctx)
				if not services.env then
					return ctx.Err("env vars unavailable")
				end
				local names = services.env.list()
				if #names == 0 then
					return ctx.Info("no variables set (try: set greeting hello)")
				end
				local rows = {}
				for _, n in names do
					table.insert(rows, { "@" .. n, tostring(services.env.get(n)) })
				end
				if ctx.UI.available == true then
					ctx.UI.Table({ headers = { "variable", "value" }, rows = rows })
				else
					for _, r in rows do
						ctx.Print(`{r[1]} = {r[2]}`)
					end
				end
			end },
		},

		-- ----- info / system -----

		{
			Name = "history",
			Aliases = { "hist" },
			Description = "show recent command history",
			Network = "Client",
			On = { Client = function(ctx)
				local hist = services.history and services.history() or {}
				local n = #hist
				if n == 0 then
					return ctx.Info("no history yet")
				end
				local start = math.max(1, n - 19)
				if ctx.UI.available == true then
					local rows = {}
					for i = start, n do
						table.insert(rows, { tostring(i), hist[i] })
					end
					ctx.UI.Table({ headers = { "#", "command" }, rows = rows })
				else
					for i = start, n do
						ctx.Print(`{i}  {hist[i]}`)
					end
				end
			end },
		},

		{
			Name = "neofetch",
			Aliases = { "fetch", "about" },
			Description = "system info card, karet style",
			Network = "Client",
			On = { Client = function(ctx)
				local specs = {
					{ "user", services.playerName() },
					{ "shell", "karet " .. services.version },
					{ "cmds", tostring(#services.list()) },
					{ "vars", tostring(services.env and #services.env.list() or 0) },
					{ "themes", tostring(#services.listThemes()) },
					{ "uptime", string.format("%ds", math.floor(time())) },
				}
				if ctx.UI.available == true then
					local R = ctx.UI.Render
					local logo = table.concat({
						" __  __ ",
						"| |/ /  ",
						"| ' /   ",
						"| . \\   ",
						"|_|\\_\\  ",
					}, "\n")
					ctx.UI.Markup(R.columns({ R.color(logo, "Accent"), R.fields(specs) }, { gap = 3 }))
				else
					for _, kv in specs do
						ctx.Print(`{kv[1]}: {kv[2]}`)
					end
				end
			end },
		},

		{
			Name = "players",
			Aliases = { "who" },
			Description = "list players in the server",
			Network = "Client",
			On = { Client = function(ctx)
				local plrs = game:GetService("Players"):GetPlayers()
				if #plrs == 0 then
					return ctx.Info("no players")
				end
				if ctx.UI.available == true then
					local rows = {}
					for _, p in plrs do
						table.insert(rows, { p.Name, p.DisplayName, tostring(p.UserId) })
					end
					ctx.UI.Table({ headers = { "name", "display", "userid" }, rows = rows })
				else
					local names = {}
					for _, p in plrs do
						table.insert(names, p.Name)
					end
					ctx.Print(table.concat(names, ", "))
				end
				ctx.Return(#plrs)
			end },
		},

		{
			Name = "pos",
			Aliases = { "position", "where" },
			Description = "your character's position",
			Network = "Client",
			On = { Client = function(ctx)
				local plr = services.player and services.player()
				local char = plr and plr.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if not root then
					return ctx.Warn("no character")
				end
				local p = root.Position
				ctx.Print(string.format("%.1f, %.1f, %.1f", p.X, p.Y, p.Z))
				ctx.Return(p)
			end },
		},

		{
			Name = "uptime",
			Description = "how long this server has been running",
			Network = "Client",
			On = { Client = function(ctx)
				local s = math.floor(time())
				ctx.Print(string.format("%dh %dm %ds", s // 3600, (s % 3600) // 60, s % 60))
			end },
		},

		{
			Name = "date",
			Aliases = { "day" },
			Description = "current date",
			Network = "Client",
			On = { Client = function(ctx)
				ctx.Print(os.date("%Y-%m-%d %A"))
			end },
		},

		-- ----- utility -----

		{
			Name = "wait",
			Aliases = { "sleep" },
			Description = "pause for a duration (30s, 1m, ...)",
			Network = "Client",
			Args = { { Name = "duration", Types = { "Duration" }, Required = true } },
			On = { Client = function(ctx)
				local secs = ctx.Args.duration
				local spin = ctx.Indicator({ type = "spinner", label = `waiting {secs}s` })
				task.wait(secs)
				spin:Succeed(`waited {secs}s`)
			end },
		},

		{
			Name = "random",
			Aliases = { "rand" },
			Description = "a random number: random / random max / random min max",
			Network = "Client",
			Args = {
				{ Name = "a", Types = { "Number" }, Required = false },
				{ Name = "b", Types = { "Number" }, Required = false },
			},
			On = { Client = function(ctx)
				local a, b = ctx.Args.a, ctx.Args.b
				local n
				if a and b then
					n = math.random(math.floor(a), math.floor(b))
				elseif a then
					n = math.random(1, math.floor(a))
				else
					n = math.random()
				end
				ctx.Print(tostring(n))
				ctx.Return(n)
			end },
		},

		{
			Name = "roll",
			Description = "roll a die (default d6)",
			Network = "Client",
			Args = { { Name = "sides", Types = { "Integer" }, Required = false, Default = 6 } },
			On = { Client = function(ctx)
				local n = math.random(1, math.max(2, ctx.Args.sides))
				ctx.Print(`rolled {n}`)
				ctx.Return(n)
			end },
		},

		{
			Name = "flip",
			Aliases = { "coin" },
			Description = "flip a coin",
			Network = "Client",
			On = { Client = function(ctx)
				local r = math.random() < 0.5 and "heads" or "tails"
				ctx.Print(r)
				ctx.Return(r)
			end },
		},

		{
			Name = "upper",
			Description = "UPPERCASE a string",
			Network = "Client",
			Args = { { Name = "text", Types = { "String" }, Required = true } },
			On = { Client = function(ctx)
				local s = string.upper(ctx.Args.text)
				ctx.Print(s)
				ctx.Return(s)
			end },
		},

		{
			Name = "lower",
			Description = "lowercase a string",
			Network = "Client",
			Args = { { Name = "text", Types = { "String" }, Required = true } },
			On = { Client = function(ctx)
				local s = string.lower(ctx.Args.text)
				ctx.Print(s)
				ctx.Return(s)
			end },
		},

		{
			Name = "len",
			Aliases = { "length" },
			Description = "length of a string",
			Network = "Client",
			Args = { { Name = "text", Types = { "String" }, Required = true } },
			On = { Client = function(ctx)
				local n = utf8.len(ctx.Args.text) or #ctx.Args.text
				ctx.Print(tostring(n))
				ctx.Return(n)
			end },
		},

		{
			Name = "reverse",
			Aliases = { "rev" },
			Description = "reverse a string",
			Network = "Client",
			Args = { { Name = "text", Types = { "String" }, Required = true } },
			On = { Client = function(ctx)
				local s = string.reverse(ctx.Args.text)
				ctx.Print(s)
				ctx.Return(s)
			end },
		},

		{
			Name = "repeat",
			Aliases = { "rep" },
			Description = "repeat a string n times",
			Network = "Client",
			Args = {
				{ Name = "text", Types = { "String" }, Required = true },
				{ Name = "times", Types = { "Integer" }, Required = false, Default = 2 },
			},
			On = { Client = function(ctx)
				local s = string.rep(ctx.Args.text, math.clamp(ctx.Args.times, 1, 100))
				ctx.Print(s)
				ctx.Return(s)
			end },
		},

		{
			Name = "count",
			Description = "count matched players (count all / count me / ...)",
			Network = "Client",
			Args = { { Name = "players", Types = { "Players" }, Required = true } },
			On = { Client = function(ctx)
				local n = #ctx.Args.players
				ctx.Print(tostring(n))
				ctx.Return(n)
			end },
		},

		{
			Name = "notify",
			Aliases = { "say" },
			Description = "echo a highlighted message",
			Network = "Client",
			Args = { { Name = "text", Types = { "String" }, Required = true } },
			On = { Client = function(ctx)
				ctx.Success(ctx.Args.text)
			end },
		},
	}

	-- ---------------------------------------------------------------------------
	-- the big batch: ~100 small commands generated from compact tables. each helper
	-- builds a Client command that prints its result and pushes it to the return pool.
	-- ---------------------------------------------------------------------------

	local function add(def: any)
		table.insert(defs, def)
	end

	local function emit(ctx: any, value: any)
		ctx.Print(tostring(value))
		ctx.Return(value)
	end

	-- one Number arg -> Number
	local function num1(name: string, desc: string, fn: (number) -> any)
		add({
			Name = name,
			Description = desc,
			Network = "Client",
			Args = { { Name = "n", Types = { "Number" }, Required = true } },
			On = { Client = function(ctx)
				emit(ctx, fn(ctx.Args.n))
			end },
		})
	end

	-- two Number args -> Number
	local function num2(name: string, desc: string, fn: (number, number) -> any)
		add({
			Name = name,
			Description = desc,
			Network = "Client",
			Args = {
				{ Name = "a", Types = { "Number" }, Required = true },
				{ Name = "b", Types = { "Number" }, Required = true },
			},
			On = { Client = function(ctx)
				emit(ctx, fn(ctx.Args.a, ctx.Args.b))
			end },
		})
	end

	-- one String arg -> anything
	local function str1(name: string, desc: string, fn: (string) -> any)
		add({
			Name = name,
			Description = desc,
			Network = "Client",
			Args = { { Name = "text", Types = { "String" }, Required = true } },
			On = { Client = function(ctx)
				emit(ctx, fn(ctx.Args.text))
			end },
		})
	end

	-- two String args -> anything
	local function str2(name: string, desc: string, fn: (string, string) -> any)
		add({
			Name = name,
			Description = desc,
			Network = "Client",
			Args = {
				{ Name = "a", Types = { "String" }, Required = true },
				{ Name = "b", Types = { "String" }, Required = true },
			},
			On = { Client = function(ctx)
				emit(ctx, fn(ctx.Args.a, ctx.Args.b))
			end },
		})
	end

	-- no args
	local function plain(name: string, desc: string, fn: (any) -> ())
		add({ Name = name, Description = desc, Network = "Client", On = { Client = fn } })
	end

	-- math (one number) --------------------------------------------------------
	num1("abs", "absolute value", math.abs)
	num1("ceil", "round up", math.ceil)
	num1("floor", "round down", math.floor)
	num1("round", "round to nearest", function(n) return math.round(n) end)
	num1("sqrt", "square root", math.sqrt)
	num1("cbrt", "cube root", function(n) return n ^ (1 / 3) end)
	num1("sign", "sign (-1/0/1)", math.sign)
	num1("square", "n squared", function(n) return n * n end)
	num1("cube", "n cubed", function(n) return n * n * n end)
	num1("sin", "sine (radians)", math.sin)
	num1("cos", "cosine (radians)", math.cos)
	num1("tan", "tangent (radians)", math.tan)
	num1("asin", "arc sine", math.asin)
	num1("acos", "arc cosine", math.acos)
	num1("atan", "arc tangent", math.atan)
	num1("exp", "e^n", math.exp)
	num1("ln", "natural log", function(n) return math.log(n) end)
	num1("log2", "log base 2", function(n) return math.log(n, 2) end)
	num1("log10", "log base 10", function(n) return math.log(n, 10) end)
	num1("deg", "radians to degrees", math.deg)
	num1("rad", "degrees to radians", math.rad)
	num1("recip", "1 / n", function(n) return 1 / n end)
	num1("double", "n * 2", function(n) return n * 2 end)
	num1("half", "n / 2", function(n) return n / 2 end)
	num1("int", "integer part", function(n) return (n < 0) and math.ceil(n) or math.floor(n) end)
	num1("frac", "fractional part", function(n) return n - ((n < 0) and math.ceil(n) or math.floor(n)) end)
	num1("factorial", "n! (n<=170)", function(n)
		local r = 1
		for i = 2, math.min(170, math.floor(n)) do
			r *= i
		end
		return r
	end)
	num1("fib", "nth fibonacci (n<=90)", function(n)
		local a, b = 0, 1
		for _ = 1, math.clamp(math.floor(n), 0, 90) do
			a, b = b, a + b
		end
		return a
	end)
	num1("isprime", "is n prime?", function(n)
		n = math.floor(n)
		if n < 2 then
			return false
		end
		for i = 2, math.floor(math.sqrt(n)) do
			if n % i == 0 then
				return false
			end
		end
		return true
	end)
	num1("bin", "decimal to binary", function(n)
		n = math.floor(math.abs(n))
		if n == 0 then
			return "0"
		end
		local s = ""
		while n > 0 do
			s = (n % 2) .. s
			n //= 2
		end
		return s
	end)
	num1("hex", "decimal to hex", function(n) return string.format("%x", math.floor(n)) end)
	num1("oct", "decimal to octal", function(n) return string.format("%o", math.floor(n)) end)
	num1("char", "code point to char", function(n) return utf8.char(math.floor(n)) end)

	-- math (two numbers) -------------------------------------------------------
	num2("add", "a + b", function(a, b) return a + b end)
	num2("sub", "a - b", function(a, b) return a - b end)
	num2("mul", "a * b", function(a, b) return a * b end)
	num2("divide", "a / b", function(a, b) return a / b end)
	num2("mod", "a % b", function(a, b) return a % b end)
	num2("pow", "a ^ b", function(a, b) return a ^ b end)
	num2("min", "smaller of a, b", math.min)
	num2("max", "larger of a, b", math.max)
	num2("hypot", "sqrt(a^2+b^2)", function(a, b) return math.sqrt(a * a + b * b) end)
	num2("atan2", "angle of (b, a)", function(a, b) return math.atan2(a, b) end)
	num2("logbase", "log a base b", function(a, b) return math.log(a, b) end)
	num2("gcd", "greatest common divisor", function(a, b)
		a, b = math.floor(math.abs(a)), math.floor(math.abs(b))
		while b ~= 0 do
			a, b = b, a % b
		end
		return a
	end)
	num2("lcm", "least common multiple", function(a, b)
		local x, y = math.floor(math.abs(a)), math.floor(math.abs(b))
		if x == 0 or y == 0 then
			return 0
		end
		local g = x
		local h = y
		while h ~= 0 do
			g, h = h, g % h
		end
		return x // g * y
	end)
	num2("nthroot", "b-th root of a", function(a, b) return a ^ (1 / b) end)
	num2("percent", "a as % of b", function(a, b) return a / b * 100 end)

	-- strings ------------------------------------------------------------------
	str1("trim", "strip whitespace", function(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end)
	str1("ltrim", "strip left whitespace", function(s) return (string.gsub(s, "^%s*", "")) end)
	str1("rtrim", "strip right whitespace", function(s) return (string.gsub(s, "%s*$", "")) end)
	str1("capitalize", "capitalize first letter", function(s) return (string.gsub(s, "^%l", string.upper)) end)
	str1("title", "Title Case", function(s) return (string.gsub(s, "(%a)([%w]*)", function(a, b) return string.upper(a) .. string.lower(b) end)) end)
	str1("swapcase", "swap letter case", function(s) return (string.gsub(s, "%a", function(c) return c == string.upper(c) and string.lower(c) or string.upper(c) end)) end)
	str1("rot13", "rot13 cipher", function(s)
		return (string.gsub(s, "%a", function(c)
			local base = c:lower() == c and 97 or 65
			return string.char((c:byte() - base + 13) % 26 + base)
		end))
	end)
	str1("shout", "UPPER + !", function(s) return string.upper(s) .. "!" end)
	str1("words", "word count", function(s)
		local n = 0
		for _ in string.gmatch(s, "%S+") do
			n += 1
		end
		return n
	end)
	str1("lines", "line count", function(s) return select(2, string.gsub(s, "\n", "\n")) + 1 end)
	str1("vowels", "vowel count", function(s) return select(2, string.gsub(string.lower(s), "[aeiou]", "")) end)
	str1("code", "first char's code point", function(s) return utf8.codepoint(s) end)
	str1("slug", "url-style slug", function(s) return (string.gsub(string.lower((string.gsub(s, "%s+", "-"))), "[^%w%-]", "")) end)
	str1("nato", "spell with nato alphabet", function(s)
		local A = { a = "alpha", b = "bravo", c = "charlie", d = "delta", e = "echo", f = "foxtrot", g = "golf", h = "hotel", i = "india", j = "juliet", k = "kilo", l = "lima", m = "mike", n = "november", o = "oscar", p = "papa", q = "quebec", r = "romeo", s = "sierra", t = "tango", u = "uniform", v = "victor", w = "whiskey", x = "xray", y = "yankee", z = "zulu" }
		local parts = {}
		for c in string.gmatch(string.lower(s), "%a") do
			table.insert(parts, A[c] or c)
		end
		return table.concat(parts, " ")
	end)

	str2("concat", "join two strings", function(a, b) return a .. b end)
	str2("contains", "does a contain b?", function(a, b) return string.find(a, b, 1, true) ~= nil end)
	str2("startswith", "does a start with b?", function(a, b) return string.sub(a, 1, #b) == b end)
	str2("endswith", "does a end with b?", function(a, b) return b == "" or string.sub(a, -#b) == b end)
	str2("before", "part of a before b", function(a, b)
		local i = string.find(a, b, 1, true)
		return i and string.sub(a, 1, i - 1) or a
	end)
	str2("after", "part of a after b", function(a, b)
		local i = string.find(a, b, 1, true)
		return i and string.sub(a, i + #b) or ""
	end)

	-- random / fun -------------------------------------------------------------
	plain("uuid", "a random uuid", function(ctx)
		local t = string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function(c)
			local v = c == "x" and math.random(0, 15) or math.random(8, 11)
			return string.format("%x", v)
		end)
		emit(ctx, t)
	end)
	plain("8ball", "ask the magic 8 ball", function(ctx)
		local a = { "it is certain", "without a doubt", "yes definitely", "most likely", "ask again later", "cannot predict now", "dont count on it", "my reply is no", "very doubtful", "outlook good" }
		ctx.Print(a[math.random(#a)])
	end)
	plain("fortune", "a random fortune", function(ctx)
		local a = { "a smooth sea never made a skilled sailor", "the best way out is always through", "ship it", "today is a good day to refactor", "you will fix the bug you wrote yesterday" }
		ctx.Print(a[math.random(#a)])
	end)
	plain("coinstreak", "flip until tails", function(ctx)
		local n = 0
		while math.random() < 0.5 do
			n += 1
		end
		ctx.Print(`{n} heads before tails`)
		ctx.Return(n)
	end)
	str1("shuffle", "shuffle a string's characters", function(s)
		local t = {}
		for c in string.gmatch(s, ".") do
			table.insert(t, c)
		end
		for i = #t, 2, -1 do
			local j = math.random(i)
			t[i], t[j] = t[j], t[i]
		end
		return table.concat(t)
	end)
	num1("d", "roll a dN die", function(n) return math.random(1, math.max(2, math.floor(n))) end)
	num1("percentof", "random 0..n percent", function(n) return math.random() * n end)

	-- time ---------------------------------------------------------------------
	plain("now", "unix timestamp", function(ctx) emit(ctx, os.time()) end)
	plain("clock", "HH:MM:SS", function(ctx) ctx.Print(os.date("%H:%M:%S")) end)
	plain("weekday", "day of the week", function(ctx) ctx.Print(os.date("%A")) end)
	plain("month", "current month", function(ctx) ctx.Print(os.date("%B")) end)
	plain("year", "current year", function(ctx) emit(ctx, tonumber(os.date("%Y"))) end)
	plain("isodate", "ISO 8601 date-time", function(ctx) ctx.Print(os.date("!%Y-%m-%dT%H:%M:%SZ")) end)
	plain("epoch", "seconds since the game started", function(ctx) emit(ctx, math.floor(time())) end)

	-- repeat a command ---------------------------------------------------------
	if services.run then
		add({
			Name = "repc",
			Aliases = { "loop", "rep-cmd" },
			Description = "run a command N times: repc jump 200  (pace it with --delay=0.5)",
			Network = "Client",
			Args = {
				{ Name = "command", Types = { "String" }, Required = true },
				{ Name = "times", Types = { "Integer" }, Required = true },
			},
			On = { Client = function(ctx)
				local line = ctx.Args.command
				local maxTimes = (services.defaults and services.defaults.Repeat.MaxTimes) or 10000
				local times = math.clamp(ctx.Args.times, 1, maxTimes)
				local delay = tonumber(ctx.Options.delay) or 0
				local ind = ctx.Indicator({ type = "progress", label = `{line} x{times}`, total = times })
				local fails = 0
				for i = 1, times do
					local r = services.run(line)
					if type(r) == "table" and r.ok == false then
						fails += 1
					end
					ind:Set(i)
					if delay > 0 then
						task.wait(delay)
					end
				end
				if fails > 0 then
					ind:Fail(`{line}: ran {times}x, {fails} failed`)
				else
					ind:Succeed(`{line}: ran {times}x`)
				end
				ctx.Return(times - fails)
			end },
		})
	end

	-- env helpers --------------------------------------------------------------
	if services.env then
		local env = services.env
		add({
			Name = "incr",
			Aliases = { "inc" },
			Description = "increment a numeric variable",
			Network = "Client",
			Args = {
				{ Name = "name", Types = { "String" }, Required = true },
				{ Name = "by", Types = { "Number" }, Required = false, Default = 1 },
			},
			On = { Client = function(ctx)
				local v = tonumber(env.get(ctx.Args.name)) or 0
				v += ctx.Args.by
				env.set(ctx.Args.name, v)
				ctx.Success(`@{ctx.Args.name} = {v}`)
				ctx.Return(v)
			end },
		})
		add({
			Name = "decr",
			Aliases = { "dec" },
			Description = "decrement a numeric variable",
			Network = "Client",
			Args = {
				{ Name = "name", Types = { "String" }, Required = true },
				{ Name = "by", Types = { "Number" }, Required = false, Default = 1 },
			},
			On = { Client = function(ctx)
				local v = tonumber(env.get(ctx.Args.name)) or 0
				v -= ctx.Args.by
				env.set(ctx.Args.name, v)
				ctx.Success(`@{ctx.Args.name} = {v}`)
				ctx.Return(v)
			end },
		})
		add({
			Name = "append",
			Description = "append text to a variable",
			Network = "Client",
			Args = {
				{ Name = "name", Types = { "String" }, Required = true },
				{ Name = "text", Types = { "String" }, Required = true },
			},
			On = { Client = function(ctx)
				local v = tostring(env.get(ctx.Args.name) or "") .. ctx.Args.text
				env.set(ctx.Args.name, v)
				ctx.Success(`@{ctx.Args.name} = {v}`)
			end },
		})
	end

	-- player / character (local, client side) ----------------------------------
	local function withChar(ctx: any): any?
		local plr = services.player and services.player()
		local char = plr and plr.Character
		if not char then
			ctx.Warn("no character")
			return nil
		end
		return char
	end
	add({
		Name = "walkspeed",
		Aliases = { "ws", "speed" },
		Description = "set your walk speed",
		Network = "Client",
		Args = { { Name = "speed", Types = { "Number" }, Required = true } },
		On = { Client = function(ctx)
			local char = withChar(ctx)
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.WalkSpeed = ctx.Args.speed
				ctx.Success(`walkspeed = {ctx.Args.speed}`)
			end
		end },
	})
	add({
		Name = "jumppower",
		Aliases = { "jp" },
		Description = "set your jump power",
		Network = "Client",
		Args = { { Name = "power", Types = { "Number" }, Required = true } },
		On = { Client = function(ctx)
			local char = withChar(ctx)
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.UseJumpPower = true
				hum.JumpPower = ctx.Args.power
				ctx.Success(`jumppower = {ctx.Args.power}`)
			end
		end },
	})
	plain("jump", "make your character jump", function(ctx)
		local char = withChar(ctx)
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Jump = true
		end
	end)
	plain("respawn", "respawn your character", function(ctx)
		local plr = services.player and services.player()
		if plr then
			plr:LoadCharacter()
			ctx.Success("respawned")
		end
	end)
	plain("health", "your current health", function(ctx)
		local char = withChar(ctx)
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			emit(ctx, math.floor(hum.Health))
		end
	end)

	-- a windowed control panel - shows off ctx.Window (the Iris WindowManager)
	add({
		Name = "controls",
		Aliases = { "panel" },
		Description = "open a control-panel window (walkspeed / jump / respawn)",
		Network = "Client",
		On = { Client = function(ctx)
			local plr = services.player and services.player()
			local w = ctx.Window({ title = "controls" })
			w:Label("character")
			local speed = w:Slider("walkspeed", 0, 200, 16)
			local jump = w:Slider("jumppower", 0, 200, 50)
			w:Button("apply", function()
				local char = plr and plr.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.WalkSpeed = speed.get()
					hum.UseJumpPower = true
					hum.JumpPower = jump.get()
				end
			end)
			w:Separator()
			w:Button("respawn", function()
				if plr then
					plr:LoadCharacter()
				end
			end)
			w:Button("close", function()
				w:Close()
			end)
			ctx.Info("opened the controls window")
		end },
	})

	return defs
end

return Commands
