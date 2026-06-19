-- Substance
-- React/init.lua
-- Plinko Labs

local RiverModule = require(script.River)
local EntangleModule = require(script.Entangle)
local FluxModule = require(script.Flux)

local React = {}

function React.River(name: string): RiverModule.River
	return RiverModule.Get(name)
end

function React.Entangle(atom: any, owner: string): any
	return EntangleModule.Bind(atom, owner)
end

function React.Flux(name: string, schema: {[string]: any}?, authority: string?): FluxModule.FluxInstance
	return FluxModule.GetOrCreate(name, schema, authority)
end

return React
