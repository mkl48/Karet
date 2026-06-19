-- A small global key/value cache for commands. One instance lives per realm (Karet.Cache);
-- handlers reach it through ctx.Cache to stash and share data between commands - lookups,
-- computed state, last results, etc. Optional TTL expiry per key.

local Cache = {}
Cache.__index = Cache

function Cache.new()
	return setmetatable({
		store = {} :: { [any]: any },
		expiry = {} :: { [any]: number }, -- key -> os.clock() deadline
	}, Cache)
end

-- Store a value, optionally expiring after `ttl` seconds. Returns the value.
function Cache:Set(key: any, value: any, ttl: number?): any
	self.store[key] = value
	self.expiry[key] = ttl and (os.clock() + ttl) or nil
	return value
end

-- Read a value, lazily evicting it if its TTL has passed.
function Cache:Get(key: any): any
	local deadline = self.expiry[key]
	if deadline and os.clock() > deadline then
		self.store[key] = nil
		self.expiry[key] = nil
		return nil
	end
	return self.store[key]
end

function Cache:Has(key: any): boolean
	return self:Get(key) ~= nil
end

-- Get the cached value, or compute + store it (memoise). `ttl` optional.
function Cache:GetOrSet(key: any, compute: () -> any, ttl: number?): any
	local existing = self:Get(key)
	if existing ~= nil then
		return existing
	end
	return self:Set(key, compute(), ttl)
end

function Cache:Delete(key: any)
	self.store[key] = nil
	self.expiry[key] = nil
end

function Cache:Clear()
	table.clear(self.store)
	table.clear(self.expiry)
end

function Cache:Keys(): { any }
	local keys = {}
	for key in self.store do
		if self:Get(key) ~= nil then -- skip expired
			table.insert(keys, key)
		end
	end
	return keys
end

-- Return a { key = value } table of live entries matching predicate(value, key).
function Cache:Query(predicate: (value: any, key: any) -> boolean): { [any]: any }
	local out = {}
	for key in self.store do
		local value = self:Get(key)
		if value ~= nil and predicate(value, key) then
			out[key] = value
		end
	end
	return out
end

return Cache
