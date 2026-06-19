-- Substance
-- Particle/init.lua
-- Plinko Labs

local Schema = require(script.Schema)
local AtomModule = require(script.Atom)
local Molecule = require(script.Molecule)
local Dispatch = require(script.Dispatch)
local Registry = require(script.Registry)
local Hooks = require(script.Hooks)
local Fossil = require(script.Fossil)
local Types = require(script.Types)
local TypeSystem = require(script.Type)

local Particle = {}

Particle.Dispatch = Dispatch
Particle.Registry = Registry
Particle.Hooks = Hooks
Particle.Fossil = Fossil
Particle.Type = TypeSystem

function Particle.Quark(name: string, definition: any)
	Schema.Quark(name, definition)
end

function Particle.Gluon(name: string, shape: Types.Shape)
	Schema.Gluon(name, shape)
end

function Particle.Define(name: string, shape: Types.Shape): Types.AtomHandle
	return AtomModule.Define(name, shape)
end

function Particle.Compose(name: string, atoms: {any}, eventType: Types.EventType): Types.MoleculeHandle
	return Molecule.Compose(name, atoms, eventType)
end

return Particle
