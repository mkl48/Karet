-- Substance
-- init.lua
-- Plinko Labs

local Particle = require(script.Particle)
local React = require(script.React)
local Tools = require(script.Tools)

local Substance = {}

function Substance.Quark(name: string, definition: any)
	Particle.Quark(name, definition)
end

function Substance.Gluon(name: string, schema: {[string]: any})
	Particle.Gluon(name, schema)
end

function Substance.Define(name: string, schema: {[string]: any}): any
	return Particle.Define(name, schema)
end

function Substance.Compose(name: string, atoms: {any}, eventType: string): any
	return Particle.Compose(name, atoms, eventType)
end

function Substance.Post(name: string, payload: any, target: Player?): any
	return Particle.Dispatch.Post(name, payload, target)
end

function Substance.Subscribe(name: string, handler: (any, Player?) -> any): any
	return Particle.Dispatch.Subscribe(name, handler)
end

function Substance.Broadcast(name: string, payload: any, filter: ((Player) -> boolean)?)
	Particle.Dispatch.Broadcast(name, payload, filter)
end

function Substance.Pre(name: string, hook: (any) -> any)
	Tools.Hooks.Pre(name, hook)
end

function Substance.Hook(name: string, hook: (any) -> any)
	Tools.Hooks.Hook(name, hook)
end

function Substance.LandLine(name: string, steps: {any}): any
	return Tools.LandLine(name, steps)
end

function Substance.Batch(requests: {any}): any
	return Tools.Batch(requests)
end

function Substance.Fission(trigger: string, targets: {any})
	Tools.Fission(trigger, targets)
end

function Substance.River(name: string): any
	return React.River(name)
end

function Substance.Flux(name: string, schema: {[string]: any}?, authority: string?): any
	return React.Flux(name, schema, authority)
end

Substance.Fossil = Tools.Fossil
Substance.Type = Particle.Type

return Substance
