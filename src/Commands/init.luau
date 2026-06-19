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
	version: string,
}

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
	}
end

return Commands
