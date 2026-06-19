-- Tiny assertion helpers for the headless test runner.

local function serialize(v: any, seen: { [any]: boolean }?): string
	if type(v) == "string" then
		return string.format("%q", v)
	elseif type(v) ~= "table" then
		return tostring(v)
	end
	seen = seen or {}
	if seen[v] then
		return "<cycle>"
	end
	seen[v] = true
	local parts = {}
	-- array part
	local isArray = #v > 0
	if isArray then
		for _, item in v do
			table.insert(parts, serialize(item, seen))
		end
	else
		local keys = {}
		for k in v do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for _, k in keys do
			table.insert(parts, `{tostring(k)} = {serialize(v[k], seen)}`)
		end
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function deepEq(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, va in a do
		if not deepEq(va, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local Assert = {}

Assert.serialize = serialize

function Assert.eq(actual: any, expected: any, ctx: string?)
	if not deepEq(actual, expected) then
		error(`{ctx or "values differ"}\n  expected: {serialize(expected)}\n  actual:   {serialize(actual)}`, 2)
	end
end

function Assert.truthy(v: any, ctx: string?)
	if not v then
		error(ctx or "expected a truthy value", 2)
	end
end

function Assert.falsy(v: any, ctx: string?)
	if v then
		error(ctx or "expected a falsy value", 2)
	end
end

return Assert
