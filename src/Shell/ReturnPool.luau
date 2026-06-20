-- The return pool (GRAMMAR.md §5). Commands push typed/labelled return records; `/`
-- references read them back. There is no positional stack - you reference returns by
-- what they are. Failed links contribute nothing, so the pool only holds real results.

local ReturnPool = {}
ReturnPool.__index = ReturnPool

export type Record = {
	value: any,
	type: string?, -- the declared/inferred type, e.g. "Player"
	label: string?, -- the Returns-schema name, e.g. "target"
	fromCommand: string?,
}

export type Reference = {
	last: boolean, -- `//`
	name: string?, -- `/Name`
	index: number?, -- `#n` (1 = most recent)
	path: { string }, -- `.a.b`
}

function ReturnPool.new()
	return setmetatable({ records = {} :: { Record } }, ReturnPool)
end

function ReturnPool:clear()
	table.clear(self.records)
end

-- Append a successful return. A nil value is still a valid result and is recorded.
function ReturnPool:push(value: any, valueType: string?, label: string?, fromCommand: string?)
	table.insert(self.records, { value = value, type = valueType, label = label, fromCommand = fromCommand })
end

function ReturnPool:last(): Record?
	return self.records[#self.records]
end

-- nth-most-recent record (1 = newest) satisfying pred
local function nthMatch(records: { Record }, n: number, pred: (Record) -> boolean): Record?
	local seen = 0
	for i = #records, 1, -1 do
		local r = records[i]
		if pred(r) then
			seen += 1
			if seen == n then
				return r
			end
		end
	end
	return nil
end

local function describe(ref: Reference): string
	local head = ref.last and "//" or ("/" .. tostring(ref.name))
	if ref.index then
		head ..= "#" .. tostring(ref.index)
	end
	return head
end

-- Resolve a reference to its record (label takes precedence over type on a name clash).
function ReturnPool:resolveRecord(ref: Reference): Record?
	local n = ref.index or 1
	if ref.last then
		return nthMatch(self.records, n, function()
			return true
		end)
	elseif ref.name ~= nil then
		local name = ref.name
		local hasLabel = nthMatch(self.records, 1, function(r)
			return r.label == name
		end) ~= nil
		if hasLabel then
			return nthMatch(self.records, n, function(r)
				return r.label == name
			end)
		end
		return nthMatch(self.records, n, function(r)
			return r.type == name
		end)
	end
	return nil
end

-- Resolve a reference to a value, applying any `.path`. Returns (value, nil) on success
-- or (nil, errorMessage) on a missing return or a bad property access.
function ReturnPool:resolve(ref: Reference): (any, string?)
	local record = self:resolveRecord(ref)
	if not record then
		return nil, `no return matching {describe(ref)}`
	end
	local value = record.value
	for _, key in ref.path do
		if value == nil then
			return nil, `cannot read '{key}' of nil ({describe(ref)})`
		end
		local ok, got = pcall(function()
			return (value :: any)[key]
		end)
		if not ok then
			return nil, `cannot index '{key}' on {describe(ref)}`
		end
		value = got
	end
	return value, nil
end

return ReturnPool
