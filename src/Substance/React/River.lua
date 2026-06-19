-- Substance
-- React/River.lua
-- Plinko Labs

local RunService = game:GetService("RunService")

local Remotes = require(script.Parent.Parent.Particle.Remotes)

local IS_SERVER = RunService:IsServer()

export type River = {
	Name: string,
	Push: (self: River, player: Player, payload: any) -> (),
	Next: (self: River, handler: (any) -> ()) -> River,
	Cancel: (self: River) -> (),
}

local River = {}
River.__index = River

local rivers: {[string]: River} = {}

function River.Get(name: string): River
	local existing = rivers[name]
	if existing then
		return existing
	end

	local self = setmetatable({}, River)
	self.Name = name
	self._instance = Remotes.Get(name, "Strict")
	self._handlers = {}

	if not IS_SERVER then
		(self._instance :: RemoteEvent).OnClientEvent:Connect(function(payload: any)
			for _, handler in self._handlers do
				handler(payload)
			end
		end)
	end

	rivers[name] = (self :: any) :: River
	return (self :: any) :: River
end

function River:Push(player: Player, payload: any)
	if not IS_SERVER then
		return
	end
	(self :: any)._instance:FireClient(player, payload)
end

function River:Next(handler: (any) -> ()): River
	table.insert((self :: any)._handlers, handler)
	return self
end

function River:Cancel()
	table.clear((self :: any)._handlers)
end

return River
