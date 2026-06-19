-- Substance
-- React/Flux.lua
-- Plinko Labs

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Remotes = require(script.Parent.Parent.Particle.Remotes)

local IS_SERVER = RunService:IsServer()

export type FluxInstance = {
	Name: string,
	Patch: (self: FluxInstance, partial: {[string]: any}) -> (),
	Get: (self: FluxInstance) -> {[string]: any},
	Subscribe: (self: FluxInstance, handler: ({[string]: any}) -> ()) -> {Cancel: () -> ()},
}

local Flux = {}
Flux.__index = Flux

local instances: {[string]: FluxInstance} = {}

local function merge(target: {[string]: any}, partial: {[string]: any})
	for key, value in partial do
		target[key] = value
	end
end

function Flux.GetOrCreate(name: string, _schema: {[string]: any}?, authority: string?): FluxInstance
	local existing = instances[name]
	if existing then
		return existing
	end

	local self = setmetatable({}, Flux)
	self.Name = name
	self._state = {}
	self._handlers = {}
	self._isAuthority = (authority == "Server" and IS_SERVER) or (authority == "Client" and not IS_SERVER)
	self._instance = Remotes.Get("Flux::" .. name, "Strict") :: RemoteEvent

	if self._isAuthority then
		if IS_SERVER then
			Players.PlayerAdded:Connect(function(player: Player)
				self._instance:FireClient(player, self._state)
			end)
		end
	else
		local signal = if IS_SERVER then self._instance.OnServerEvent else self._instance.OnClientEvent
		signal:Connect(function(playerOrPatch: any, maybePatch: any)
			local patch = if IS_SERVER then maybePatch else playerOrPatch
			merge(self._state, patch)
			for _, handler in self._handlers do
				handler(self._state)
			end
		end)
	end

	instances[name] = (self :: any) :: FluxInstance
	return (self :: any) :: FluxInstance
end

function Flux:Patch(partial: {[string]: any})
	local self = self :: any
	if not self._isAuthority then
		return
	end

	merge(self._state, partial)

	if IS_SERVER then
		for _, player in Players:GetPlayers() do
			self._instance:FireClient(player, partial)
		end
	else
		self._instance:FireServer(partial)
	end

	for _, handler in self._handlers do
		handler(self._state)
	end
end

function Flux:Get(): {[string]: any}
	return (self :: any)._state
end

function Flux:Subscribe(handler: ({[string]: any}) -> ()): {Cancel: () -> ()}
	local self = self :: any
	table.insert(self._handlers, handler)

	return {
		Cancel = function()
			local index = table.find(self._handlers, handler)
			if not index then
				return
			end
			table.remove(self._handlers, index)
		end,
	}
end

return Flux
