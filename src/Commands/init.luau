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
	return {
		{
			Name = "help",
			Aliases = { "h", "?" },
			Description = "list commands, or show one command's details",
			Network = "Client",
			Args = { { Name = "command", Types = { "String" }, Required = false } },
			On = {
				Client = function(ctx)
					local which = ctx.Args.command
					if which then
						local def = services.get(which)
						if not def then
							return ctx.Err(`no command '{which}'`)
						end
						ctx.Print(`{def.Name}{def.Description and " - " .. def.Description or ""}`)
						for _, arg in def.Args or {} do
							local opt = arg.Required and "" or "?"
							ctx.Info(`  <{arg.Name}{opt}> : {table.concat(arg.Types, " | ")}`)
						end
						for _, attr in def.Attributes or {} do
							ctx.Info(`  -{attr.Short or attr.Name}  {attr.Description or attr.Name}`)
						end
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
				ctx.Print(table.concat(services.list(), ", "))
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
				ctx.Print(table.concat(services.listThemes(), ", "))
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
				if services.openConfig and services.editor and services.editor() then
					services.openConfig()
				else
					ctx.Err("config editor needs Kaveat (Start{ Kaveat = true })")
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
				ctx.UI.Fields(rows)
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
				for i = math.max(1, n - 19), n do
					ctx.Print(`{i}  {hist[i]}`)
				end
			end },
		},

		{
			Name = "neofetch",
			Aliases = { "fetch", "about" },
			Description = "system info card, karet style",
			Network = "Client",
			On = { Client = function(ctx)
				local R = ctx.UI.Render
				local logo = table.concat({
					" __  __ ",
					"| |/ /  ",
					"| ' /   ",
					"| . \\   ",
					"|_|\\_\\  ",
				}, "\n")
				local fields = R and R.fields({
					{ "user", services.playerName() },
					{ "shell", "karet " .. services.version },
					{ "cmds", tostring(#services.list()) },
					{ "vars", tostring(services.env and #services.env.list() or 0) },
					{ "themes", tostring(#services.listThemes()) },
					{ "uptime", string.format("%ds", math.floor(time())) },
				})
				if R then
					ctx.UI.Markup(R.columns({ R.color(logo, "Accent"), fields }, { gap = 3 }))
				else
					ctx.Print("karet " .. services.version)
				end
			end },
		},

		{
			Name = "players",
			Aliases = { "who" },
			Description = "list players in the server",
			Network = "Client",
			On = { Client = function(ctx)
				local names = {}
				for _, p in game:GetService("Players"):GetPlayers() do
					table.insert(names, p.Name)
				end
				if #names == 0 then
					return ctx.Info("no players")
				end
				ctx.Print(table.concat(names, ", "))
				ctx.Return(#names)
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
end

return Commands
