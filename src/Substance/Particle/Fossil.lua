-- Substance
-- Particle/Fossil.lua
-- Plinko Labs

local Fossil = {}

local recording = false
local history: {any} = {}

function Fossil.Start()
	recording = true
end

function Fossil.Stop()
	recording = false
end

function Fossil.Record(name: string, direction: string, payload: any)
	if not recording then
		return
	end

	table.insert(history, {
		Name = name,
		Direction = direction,
		Payload = payload,
		Time = os.clock(),
	})
end

function Fossil.Replay(handler: (any) -> ())
	for _, entry in history do
		handler(entry)
	end
end

function Fossil.Export(): {any}
	local copy = table.create(#history)
	for index, entry in history do
		copy[index] = entry
	end
	return copy
end

function Fossil.Clear()
	table.clear(history)
end

return Fossil
