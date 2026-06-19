-- Substance
-- Particle/Molecule.lua
-- Plinko Labs

local Registry = require(script.Parent.Registry)
local Dispatch = require(script.Parent.Dispatch)
local Types = require(script.Parent.Types)
local TypeDef = require(script.Parent.Type.TypeDef)

local Molecule = {}

local function nameOf(atom: any): string
	if type(atom) == "string" then
		return atom
	end
	return atom.Name
end

local function mergeShape(atoms: {any}): Types.Shape
	local merged = {}

	for _, atom in atoms do
		local channel = Registry.Get(nameOf(atom))
		local shape = if channel then channel.Shape else (type(atom) == "table" and atom.Shape or nil)
		if not shape or TypeDef.is(shape) then
			continue
		end

		for field, fieldType in shape do
			merged[field] = fieldType
		end
	end

	return merged
end

function Molecule.Compose(name: string, atoms: {any}, eventType: Types.EventType): Types.MoleculeHandle
	local channel = Registry.Ensure(name)
	channel.IsMolecule = true

	local atomNames = table.create(#atoms)
	for index, atom in atoms do
		atomNames[index] = nameOf(atom)
	end
	channel.AtomNames = atomNames
	channel.Shape = mergeShape(atoms)

	Dispatch.Compose(name, channel.Shape, eventType)

	return { Name = name }
end

return Molecule
