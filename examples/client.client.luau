--!nonstrict
-- Example client bootstrap (StarterPlayerScripts). Registers a local command, starts
-- Karet with a theme + toggle key, and prints a hint.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Karet = require(ReplicatedStorage.Karet)

-- A client-only command — runs entirely on the client, no server round-trip.
Karet.Command("echo")
	:Description("print your text back")
	:Network("Client")
	:Arg({ Name = "text", Types = { "String" }, Required = true })
	:On("Client", function(ctx)
		ctx.Print(ctx.Args.text)
	end)
	:Register()

local terminal = Karet.Start({
	Toggle = "Semicolon", -- press ; to open/close
	Theme = Karet.Theme.Tokyonight,
})

terminal:print("Karet ready — press ;  to open. Try:  echo hello", "Comment")
