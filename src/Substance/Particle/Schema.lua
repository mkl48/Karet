-- Substance
-- Particle/Schema.lua
-- Plinko Labs

local TypeDef = require(script.Parent.Type.TypeDef)
local Type = require(script.Parent.Type)

local Schema = {}

local quarks: {[string]: TypeDef.TypeDef} = {}
local gluons: {[string]: TypeDef.TypeDef} = {}

local LEGACY_PRIMITIVES: {[string]: () -> TypeDef.TypeDef} = {
	number = Type.number,
	string = Type.string,
	boolean = Type.bool,
	table = Type.table,
}

function Schema.Quark(name: string, definition: any)
	if TypeDef.is(definition) then
		quarks[name] = definition
		return
	end

	local legacy = LEGACY_PRIMITIVES[definition]
	assert(legacy, string.format("[Substance] Quark '%s': invalid type '%s'", name, tostring(definition)))
	quarks[name] = legacy()
end

function Schema.Gluon(name: string, shape: {[string]: any})
	gluons[name] = Schema.ResolveShape(shape)
end

function Schema.GetGluon(name: string): TypeDef.TypeDef?
	return gluons[name]
end

function Schema.Resolve(definition: any): TypeDef.TypeDef?
	if TypeDef.is(definition) then
		return definition
	end

	if type(definition) ~= "string" then
		return nil
	end

	if gluons[definition] then
		return gluons[definition]
	end

	if quarks[definition] then
		return quarks[definition]
	end

	local legacy = LEGACY_PRIMITIVES[definition]
	if legacy then
		return legacy()
	end

	return nil
end

function Schema.ResolveShape(shape: any): TypeDef.TypeDef
	if TypeDef.is(shape) then
		return shape :: TypeDef.TypeDef
	end

	local resolvedFields = {}

	for field, definition in shape :: {[string]: any} do
		local resolved = Schema.Resolve(definition)
		assert(resolved, string.format("[Substance] unknown type '%s' for field '%s'", tostring(definition), field))
		resolvedFields[field] = resolved
	end

	return Type.struct(resolvedFields)
end

function Schema.Validate(value: any, shape: {[string]: any}): (boolean, string?, any)
	local structDef = Schema.ResolveShape(shape)
	return structDef:Validate(value)
end

return Schema
