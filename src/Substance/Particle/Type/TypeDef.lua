-- Substance
-- Particle/Type/TypeDef.lua
-- Plinko Labs

export type Predicate = (value: any) -> boolean

export type TypeDef = {
	_kind: string,
	_struct: {[string]: TypeDef}?,
	_element: TypeDef?,
	_elements: {TypeDef}?,
	_key: TypeDef?,
	_value: TypeDef?,
	_resolve: (() -> TypeDef)?,
	_className: string?,
	_nullable: boolean?,
	_default: any?,
	_unions: {TypeDef}?,
	_intersects: {TypeDef}?,
	_nots: {TypeDef}?,
	_wheres: {Predicate}?,
	_literal: any?,
	_enum: {any}?,
	_min: number?,
	_max: number?,
	_step: number?,
	_minLength: number?,
	_maxLength: number?,
	_pattern: string?,
	_minSize: number?,
	_maxSize: number?,
	_tag: string?,
	_describe: string?,

	Validate: (self: TypeDef, value: any, path: string?) -> (boolean, string?, any),
	Check: (self: TypeDef, value: any) -> boolean,
	also: (self: TypeDef, other: TypeDef) -> TypeDef,
	Or: (self: TypeDef, other: TypeDef) -> TypeDef,
	Not: (self: TypeDef, other: TypeDef) -> TypeDef,
	nullable: (self: TypeDef) -> TypeDef,
	default: (self: TypeDef, value: any) -> TypeDef,
	where: (self: TypeDef, predicate: Predicate) -> TypeDef,
	literal: (self: TypeDef, value: any) -> TypeDef,
	enum: (self: TypeDef, values: {any}) -> TypeDef,
	min: (self: TypeDef, n: number) -> TypeDef,
	max: (self: TypeDef, n: number) -> TypeDef,
	bet: (self: TypeDef, minValue: number, maxValue: number) -> TypeDef,
	step: (self: TypeDef, n: number) -> TypeDef,
	minLength: (self: TypeDef, n: number) -> TypeDef,
	maxLength: (self: TypeDef, n: number) -> TypeDef,
	pattern: (self: TypeDef, p: string) -> TypeDef,
	minSize: (self: TypeDef, n: number) -> TypeDef,
	maxSize: (self: TypeDef, n: number) -> TypeDef,
	tag: (self: TypeDef, name: string) -> TypeDef,
	describe: (self: TypeDef, text: string) -> TypeDef,
}

local TypeDef = {}
TypeDef.__index = TypeDef
TypeDef.__call = function(self: TypeDef, value: any): boolean
	return self:Check(value)
end

local function label(self: TypeDef): string
	return self._describe or self._tag or self._kind
end

local function tableSize(value: {[any]: any}): number
	local count = 0
	for _ in value do
		count += 1
	end
	return count
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function TypeDef.new(kind: string): TypeDef
	return setmetatable({ _kind = kind }, TypeDef) :: any
end

function TypeDef.is(value: any): boolean
	return typeof(value) == "table" and getmetatable(value :: any) == TypeDef
end

local baseCheckers: {[string]: (self: TypeDef, value: any, path: string) -> (boolean, string?)}

local function checkPrimitive(luauType: string)
	return function(self: TypeDef, value: any, path: string): (boolean, string?)
		if typeof(value) ~= luauType then
			return false, string.format("expected %s at %s, got %s", label(self), path, typeof(value))
		end
		return true
	end
end

local function checkInteger(min: number, max: number)
	return function(self: TypeDef, value: any, path: string): (boolean, string?)
		if typeof(value) ~= "number" then
			return false, string.format("expected %s at %s, got %s", label(self), path, typeof(value))
		end
		if value % 1 ~= 0 or value < min or value > max then
			return false, string.format("expected %s in [%d, %d] at %s, got %s", label(self), min, max, path, tostring(value))
		end
		return true
	end
end

baseCheckers = {
	table = checkPrimitive("table"),
	string = checkPrimitive("string"),
	number = checkPrimitive("number"),
	bool = checkPrimitive("boolean"),
	buff = checkPrimitive("buffer"),
	float32 = checkPrimitive("number"),
	float64 = checkPrimitive("number"),
	uint8 = checkInteger(0, 255),
	uint16 = checkInteger(0, 65535),
	uint32 = checkInteger(0, 4294967295),
	int8 = checkInteger(-128, 127),
	int16 = checkInteger(-32768, 32767),
	int32 = checkInteger(-2147483648, 2147483647),
	any = function(): (boolean, string?)
		return true
	end,
	never = function(self: TypeDef, _value: any, path: string): (boolean, string?)
		return false, string.format("%s never accepts a value, at %s", label(self), path)
	end,
	unknown = function(): (boolean, string?)
		return true
	end,
	["nil"] = function(_self: TypeDef, value: any, path: string): (boolean, string?)
		if value ~= nil then
			return false, string.format("expected nil at %s", path)
		end
		return true
	end,
	vec2 = checkPrimitive("Vector2"),
	vec3 = checkPrimitive("Vector3"),
	vec2int16 = checkPrimitive("Vector2int16"),
	cframe = checkPrimitive("CFrame"),
	color3 = checkPrimitive("Color3"),
	udim = checkPrimitive("UDim"),
	udim2 = checkPrimitive("UDim2"),
	rect = checkPrimitive("Rect"),
	region3 = checkPrimitive("Region3"),
	numberRange = checkPrimitive("NumberRange"),
	numberSequence = checkPrimitive("NumberSequence"),
	colorSequence = checkPrimitive("ColorSequence"),
	tweenInfo = checkPrimitive("TweenInfo"),
	enumItem = checkPrimitive("EnumItem"),

	inst = function(self: TypeDef, value: any, path: string): (boolean, string?)
		if typeof(value) ~= "Instance" then
			return false, string.format("expected Instance at %s, got %s", path, typeof(value))
		end
		if self._className and not (value :: Instance):IsA(self._className) then
			return false, string.format("expected Instance of class '%s' at %s, got '%s'", self._className, path, (value :: Instance).ClassName)
		end
		return true
	end,

	struct = function(self: TypeDef, value: any, path: string): (boolean, string?)
		if typeof(value) ~= "table" then
			return false, string.format("expected table at %s", path)
		end
		local struct = self._struct :: {[string]: TypeDef}
		for field, fieldType in struct do
			local ok, err, resolved = fieldType:Validate(value[field], path .. "." .. field)
			if not ok then
				return false, err
			end
			if resolved ~= nil and resolved ~= value[field] then
				value[field] = resolved
			end
		end
		return true
	end,

	array = function(self: TypeDef, value: any, path: string): (boolean, string?)
		if typeof(value) ~= "table" then
			return false, string.format("expected array at %s", path)
		end
		local element = self._element :: TypeDef
		for index, item in value do
			local ok, err, resolved = element:Validate(item, string.format("%s[%s]", path, tostring(index)))
			if not ok then
				return false, err
			end
			if resolved ~= nil and resolved ~= item then
				value[index] = resolved
			end
		end
		return true
	end,

	tuple = function(self: TypeDef, value: any, path: string): (boolean, string?)
		if typeof(value) ~= "table" then
			return false, string.format("expected tuple at %s", path)
		end
		local elements = self._elements :: {TypeDef}
		for index, elementType in elements do
			local ok, err, resolved = elementType:Validate(value[index], string.format("%s[%d]", path, index))
			if not ok then
				return false, err
			end
			if resolved ~= nil and resolved ~= value[index] then
				value[index] = resolved
			end
		end
		return true
	end,

	map = function(self: TypeDef, value: any, path: string): (boolean, string?)
		if typeof(value) ~= "table" then
			return false, string.format("expected map at %s", path)
		end
		local keyType = self._key :: TypeDef
		local valueType = self._value :: TypeDef
		for key, item in value do
			local kok, kerr = keyType:Validate(key, path .. ".<key>")
			if not kok then
				return false, kerr
			end
			local vok, verr = valueType:Validate(item, string.format("%s[%s]", path, tostring(key)))
			if not vok then
				return false, verr
			end
		end
		return true
	end,

	record = function(self: TypeDef, value: any, path: string): (boolean, string?)
		if typeof(value) ~= "table" then
			return false, string.format("expected record at %s", path)
		end
		local valueType = self._value :: TypeDef
		for key, item in value do
			if type(key) ~= "string" then
				return false, string.format("expected string key at %s", path)
			end
			local ok, err = valueType:Validate(item, string.format("%s.%s", path, key))
			if not ok then
				return false, err
			end
		end
		return true
	end,

	lazy = function(self: TypeDef, value: any, path: string): (boolean, string?)
		local resolved = (self._resolve :: () -> TypeDef)()
		local ok, err = resolved:Validate(value, path)
		return ok, err
	end,

	custom = function(): (boolean, string?)
		return true
	end,
}

function TypeDef:Validate(value: any, path: string?): (boolean, string?, any)
	path = path or "$"

	if value == nil then
		if self._default ~= nil then
			value = self._default
		elseif self._nullable then
			return true, nil, nil
		end
	end

	if self._nots then
		for _, notType in self._nots :: {TypeDef} do
			local ok = notType:Check(value)
			if ok then
				return false, string.format("%s must not match excluded type at %s", label(self), path)
			end
		end
	end

	if self._unions then
		local ok = self:_selfCheck(value, path)
		if not ok then
			for _, unionType in self._unions :: {TypeDef} do
				local uok, _uerr, uval = unionType:Validate(value, path)
				if uok then
					value = if uval ~= nil then uval else value
					ok = true
					break
				end
			end
		end
		if not ok then
			return false, string.format("value did not match %s or any union member at %s", label(self), path)
		end
	else
		local ok, err = self:_selfCheck(value, path)
		if not ok then
			return false, err
		end
	end

	if self._intersects then
		for _, andType in self._intersects :: {TypeDef} do
			local ok, err = andType:Validate(value, path)
			if not ok then
				return false, err
			end
		end
	end

	local ok, err = self:_constraints(value, path)
	if not ok then
		return false, err
	end

	return true, nil, value
end

function TypeDef:_selfCheck(value: any, path: string): (boolean, string?)
	local checker = baseCheckers[self._kind]
	if not checker then
		return false, string.format("unknown type kind '%s' at %s", self._kind, path)
	end
	return checker(self, value, path)
end

function TypeDef:_constraints(value: any, path: string): (boolean, string?)
	if self._literal ~= nil and not deepEqual(value, self._literal) then
		return false, string.format("expected literal %s at %s", tostring(self._literal), path)
	end

	if self._enum then
		local found = false
		for _, candidate in self._enum :: {any} do
			if deepEqual(value, candidate) then
				found = true
				break
			end
		end
		if not found then
			return false, string.format("value not in enum at %s", path)
		end
	end

	if typeof(value) == "number" then
		if self._min and value < self._min then
			return false, string.format("expected >= %s at %s", tostring(self._min), path)
		end
		if self._max and value > self._max then
			return false, string.format("expected <= %s at %s", tostring(self._max), path)
		end
		if self._step and (value % self._step) ~= 0 then
			return false, string.format("expected multiple of %s at %s", tostring(self._step), path)
		end
	end

	if typeof(value) == "string" then
		if self._minLength and #value < self._minLength then
			return false, string.format("expected length >= %d at %s", self._minLength, path)
		end
		if self._maxLength and #value > self._maxLength then
			return false, string.format("expected length <= %d at %s", self._maxLength, path)
		end
		if self._pattern and not string.match(value, self._pattern) then
			return false, string.format("expected to match pattern '%s' at %s", self._pattern, path)
		end
	end

	if typeof(value) == "table" then
		if self._minSize and tableSize(value) < self._minSize then
			return false, string.format("expected size >= %d at %s", self._minSize, path)
		end
		if self._maxSize and tableSize(value) > self._maxSize then
			return false, string.format("expected size <= %d at %s", self._maxSize, path)
		end
	end

	if self._wheres then
		for _, predicate in self._wheres :: {Predicate} do
			if not predicate(value) then
				return false, string.format("failed custom predicate at %s", path)
			end
		end
	end

	return true
end

function TypeDef:Check(value: any): boolean
	local ok = self:Validate(value)
	return ok
end

function TypeDef:also(other: TypeDef): TypeDef
	self._intersects = self._intersects or {}
	table.insert(self._intersects, other)
	return self
end

-- "or" and "not" are reserved words in Luau and cannot follow `:` in a method
-- call, so the union/negation modifiers are capitalized: `:Or()` / `:Not()`.
function TypeDef:Or(other: TypeDef): TypeDef
	self._unions = self._unions or {}
	table.insert(self._unions, other)
	return self
end

function TypeDef:Not(other: TypeDef): TypeDef
	self._nots = self._nots or {}
	table.insert(self._nots, other)
	return self
end

function TypeDef:nullable(): TypeDef
	self._nullable = true
	return self
end

function TypeDef:default(value: any): TypeDef
	self._default = value
	return self
end

function TypeDef:where(predicate: Predicate): TypeDef
	self._wheres = self._wheres or {}
	table.insert(self._wheres, predicate)
	return self
end

function TypeDef:literal(value: any): TypeDef
	self._literal = value
	return self
end

function TypeDef:enum(values: {any}): TypeDef
	self._enum = values
	return self
end

function TypeDef:min(n: number): TypeDef
	self._min = n
	return self
end

function TypeDef:max(n: number): TypeDef
	self._max = n
	return self
end

function TypeDef:bet(minValue: number, maxValue: number): TypeDef
	self._min = minValue
	self._max = maxValue
	return self
end

function TypeDef:step(n: number): TypeDef
	self._step = n
	return self
end

function TypeDef:minLength(n: number): TypeDef
	self._minLength = n
	return self
end

function TypeDef:maxLength(n: number): TypeDef
	self._maxLength = n
	return self
end

function TypeDef:pattern(p: string): TypeDef
	self._pattern = p
	return self
end

function TypeDef:minSize(n: number): TypeDef
	self._minSize = n
	return self
end

function TypeDef:maxSize(n: number): TypeDef
	self._maxSize = n
	return self
end

function TypeDef:tag(name: string): TypeDef
	self._tag = name
	return self
end

function TypeDef:describe(text: string): TypeDef
	self._describe = text
	return self
end

return TypeDef
