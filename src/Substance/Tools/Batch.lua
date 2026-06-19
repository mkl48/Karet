-- Substance
-- Tools/Batch.lua
-- Plinko Labs

local Dispatch = require(script.Parent.Parent.Particle.Dispatch)
local Async = require(script.Parent.Parent.Async)

export type Request = {
	Name: string,
	Payload: any?,
	Target: Player?,
}

local Batch = {}

function Batch.Run(requests: {Request}): any
	return Async.Reaction.new(function()
		local reactions = table.create(#requests)
		for index, request in requests do
			reactions[index] = Dispatch.Post(request.Name, request.Payload, request.Target)
		end

		local results = table.create(#requests)
		for index, reaction in reactions do
			results[index] = reaction:Await()
		end

		return results
	end)
end

return Batch
