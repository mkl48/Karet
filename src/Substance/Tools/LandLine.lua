-- Substance
-- Tools/LandLine.lua
-- Plinko Labs

local Dispatch = require(script.Parent.Parent.Particle.Dispatch)
local Async = require(script.Parent.Parent.Async)

export type Step = string | {
	Name: string,
	Payload: any?,
	Map: ((any) -> any)?,
}

local LandLine = {}

local function normalize(step: Step): (string, any?, ((any) -> any)?)
	if type(step) == "string" then
		return step, nil, nil
	end
	return step.Name, step.Payload, step.Map
end

function LandLine.Run(_name: string, steps: {Step}): any
	return Async.Reaction.new(function()
		local result = nil

		for index, step in steps do
			local channelName, payload, map = normalize(step)

			local input = payload
			if input == nil and map then
				input = map(result)
			elseif input == nil and index > 1 then
				input = result
			end

			result = Dispatch.Post(channelName, input):Await()
		end

		return result
	end)
end

return LandLine
