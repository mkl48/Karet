-- A named-query registry. Karet (and your game) registers providers - "players", "teams",
-- "commands", whatever - and commands run them by name through ctx.Query. This gives
-- commands a uniform way to look things up without each one re-implementing resolution.
--
--   Karet.Query:Register("players", function(filter) ... return list end)
--   ctx.Query:Run("players", "admins")   -> (result, err)

local Query = {}
Query.__index = Query

function Query.new()
	return setmetatable({ providers = {} :: { [string]: (...any) -> any } }, Query)
end

-- Register (or replace) a provider.
function Query:Register(name: string, fn: (...any) -> any)
	assert(type(name) == "string" and name ~= "", "Karet.Query: name must be a non-empty string")
	assert(type(fn) == "function", "Karet.Query: provider must be a function")
	self.providers[name] = fn
end

function Query:Has(name: string): boolean
	return self.providers[name] ~= nil
end

-- Run a provider by name. Returns (result, nil) or (nil, errorMessage) if unknown / if the
-- provider errors.
function Query:Run(name: string, ...): (any, string?)
	local fn = self.providers[name]
	if not fn then
		return nil, `no query '{name}'`
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		return nil, `query '{name}' failed: {result}`
	end
	return result, nil
end

-- Names of all registered providers, sorted.
function Query:List(): { string }
	local names = {}
	for name in self.providers do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return Query
