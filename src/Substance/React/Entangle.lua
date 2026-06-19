-- Substance
-- React/Entangle.lua
-- Plinko Labs

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Remotes = require(script.Parent.Parent.Particle.Remotes)

local IS_SERVER = RunService:IsServer()

local Entangle = {}

local bound: {[string]: boolean} = {}

function Entangle.Bind(atom: any, owner: string): any
	local name = atom._channel or atom.Name
	local channelName = "Entangle::" .. name

	if bound[name] then
		return atom
	end
	bound[name] = true

	local instance = Remotes.Get(channelName, "Strict") :: RemoteEvent
	local state = { Value = nil :: any }

	local isOwnerSide = (owner == "Server" and IS_SERVER) or (owner == "Client" and not IS_SERVER)

	if isOwnerSide and IS_SERVER then
		Players.PlayerAdded:Connect(function(player: Player)
			if state.Value == nil then
				return
			end
			instance:FireClient(player, state.Value)
		end)
	elseif not isOwnerSide then
		if IS_SERVER then
			instance.OnServerEvent:Connect(function(_player: Player, value: any)
				state.Value = value
			end)
		else
			instance.OnClientEvent:Connect(function(value: any)
				state.Value = value
			end)
		end
	end

	atom.Set = function(_self: any, value: any)
		if not isOwnerSide then
			return
		end

		state.Value = value

		if IS_SERVER then
			for _, player in Players:GetPlayers() do
				instance:FireClient(player, value)
			end
		else
			instance:FireServer(value)
		end
	end

	atom.Get = function(_self: any): any
		return state.Value
	end

	return atom
end

return Entangle
