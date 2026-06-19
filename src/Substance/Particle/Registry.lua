-- Substance
-- Particle/Registry.lua
-- Plinko Labs

local Types = require(script.Parent.Types)

local Registry = {}

local channels: {[string]: Types.Channel} = {}

function Registry.Ensure(name: string): Types.Channel
	local channel = channels[name]
	if channel then
		return channel
	end

	channel = {
		Name = name,
		Subscribers = {},
		IsMolecule = false,
	}
	channels[name] = channel
	return channel
end

function Registry.Get(name: string): Types.Channel?
	return channels[name]
end

function Registry.AddSubscriber(name: string, handler: (any, Player?) -> any): Types.Subscription
	local channel = Registry.Ensure(name)
	table.insert(channel.Subscribers, handler)

	return {
		Cancel = function()
			local index = table.find(channel.Subscribers, handler)
			if not index then
				return
			end
			table.remove(channel.Subscribers, index)
		end,
	}
end

return Registry
