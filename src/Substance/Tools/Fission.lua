-- Substance
-- Tools/Fission.lua
-- Plinko Labs

local Dispatch = require(script.Parent.Parent.Particle.Dispatch)

export type Target = string | {
	Name: string,
	Map: ((any) -> any)?,
}

local Fission = {}

function Fission.Register(trigger: string, targets: {Target})
	Dispatch.Subscribe(trigger, function(payload: any, player: Player?)
		for _, target in targets do
			local targetName = target
			local map = nil

			if type(target) == "table" then
				targetName, map = target.Name, target.Map
			end

			local outgoing = if map then map(payload) else payload
			Dispatch.Post(targetName :: string, outgoing, player)
		end
	end)
end

return Fission
