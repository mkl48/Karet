--!nonstrict
-- Example server bootstrap (ServerScriptService). Registers a server-authoritative
-- command, sets a role hook, and starts Karet's server listener.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Karet = require(ReplicatedStorage.Karet)

-- A server command: the client invokes it over Substance, the server runs it. Auth is
-- checked server-side before the handler runs.
Karet.Command("announce")
	:Description("broadcast a message (Admin+)")
	:Network("Server")
	:Permission("Admin")
	:Arg({ Name = "message", Types = { "String" }, Required = true })
	:On("Server", function(ctx)
		ctx.Reply("announced: " .. ctx.Args.message)
	end)
	:Register()

Karet.SetRoleHook(function(player)
	-- Replace with real logic (group rank, owner id, datastore, ...).
	return "Admin"
end)

Karet.Start({ DefaultRole = "User" })
