-- Substance
-- Particle/Type/Constructors.lua
-- Plinko Labs

local TypeDef = require(script.Parent.TypeDef)

export type TypeDef = TypeDef.TypeDef

local Type = {}

Type.is = TypeDef.is

local function simple(kind: string): () -> TypeDef
	return function(): TypeDef
		return TypeDef.new(kind)
	end
end

Type.table = simple("table")
Type.string = simple("string")
Type.number = simple("number")
Type.bool = simple("bool")
Type.buff = simple("buff")
Type.float32 = simple("float32")
Type.float64 = simple("float64")
Type.uint8 = simple("uint8")
Type.uint16 = simple("uint16")
Type.uint32 = simple("uint32")
Type.int8 = simple("int8")
Type.int16 = simple("int16")
Type.int32 = simple("int32")
Type.any = simple("any")
Type.never = simple("never")
Type.unknown = simple("unknown")
Type.nil_ = simple("nil")
Type.none = TypeDef.new("nil")

Type.vec2 = simple("vec2")
Type.vec3 = simple("vec3")
Type.vec2int16 = simple("vec2int16")
Type.cframe = simple("cframe")
Type.color3 = simple("color3")
Type.udim = simple("udim")
Type.udim2 = simple("udim2")
Type.rect = simple("rect")
Type.region3 = simple("region3")
Type.numberRange = simple("numberRange")
Type.numberSequence = simple("numberSequence")
Type.colorSequence = simple("colorSequence")
Type.tweenInfo = simple("tweenInfo")
Type.enumItem = simple("enumItem")

function Type.inst(className: string?): TypeDef
	local def = TypeDef.new("inst")
	def._className = className
	return def
end

function Type.struct(shape: {[string]: TypeDef}): TypeDef
	local def = TypeDef.new("struct")
	def._struct = shape
	return def
end

Type.shape = Type.struct

function Type.array(element: TypeDef): TypeDef
	local def = TypeDef.new("array")
	def._element = element
	return def
end

function Type.tuple(...: TypeDef): TypeDef
	local def = TypeDef.new("tuple")
	def._elements = { ... }
	return def
end

function Type.map(keyType: TypeDef, valueType: TypeDef): TypeDef
	local def = TypeDef.new("map")
	def._key = keyType
	def._value = valueType
	return def
end

function Type.record(valueType: TypeDef): TypeDef
	local def = TypeDef.new("record")
	def._value = valueType
	return def
end

function Type.lazy(resolve: () -> TypeDef): TypeDef
	local def = TypeDef.new("lazy")
	def._resolve = resolve
	return def
end

local function assertStruct(def: TypeDef, fnName: string): {[string]: TypeDef}
	assert(def._struct, string.format("[Substance] Type.%s expects a struct TypeDef", fnName))
	return def._struct :: {[string]: TypeDef}
end

function Type.partial(structDef: TypeDef): TypeDef
	local source = assertStruct(structDef, "partial")
	local shape = {}
	for field, fieldType in source do
		shape[field] = fieldType:nullable()
	end
	return Type.struct(shape)
end

function Type.pick(structDef: TypeDef, keys: {string}): TypeDef
	local source = assertStruct(structDef, "pick")
	local shape = {}
	for _, key in keys do
		shape[key] = source[key]
	end
	return Type.struct(shape)
end

function Type.omit(structDef: TypeDef, keys: {string}): TypeDef
	local source = assertStruct(structDef, "omit")
	local excluded = {}
	for _, key in keys do
		excluded[key] = true
	end

	local shape = {}
	for field, fieldType in source do
		if excluded[field] then
			continue
		end
		shape[field] = fieldType
	end
	return Type.struct(shape)
end

function Type.merge(structA: TypeDef, structB: TypeDef): TypeDef
	local sourceA = assertStruct(structA, "merge")
	local sourceB = assertStruct(structB, "merge")

	local shape = {}
	for field, fieldType in sourceA do
		shape[field] = fieldType
	end
	for field, fieldType in sourceB do
		shape[field] = fieldType
	end
	return Type.struct(shape)
end

export type DefineTypeConfig = {
	Mask: () -> TypeDef,
	Validate: ((value: any) -> boolean)?,
}

function Type.defineType(config: DefineTypeConfig): () -> TypeDef
	return function(): TypeDef
		local def = config.Mask()
		if config.Validate then
			def:where(config.Validate)
		end
		return def
	end
end

return Type
