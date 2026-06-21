-- the kav module system: lets one kav `require` another by name, ModuleScript-style. a kav
-- module runs at most once and its return value is cached; a require cycle errors cleanly
-- instead of hanging.
--
-- this module is just the bookkeeping (resolve a name, cache results, detect cycles). the
-- actual compile+run is injected as `run(source, name)` by the server (it needs loadstring /
-- setfenv, which are engine-only), so the bookkeeping stays pure and unit-tested.

local Modules = {}

-- find a kav in the source map, tolerating a `.luau` suffix on either side
local function resolve(map: { [string]: string }, name: string): string?
	if map[name] ~= nil then
		return name
	end
	if map[name .. ".luau"] ~= nil then
		return name .. ".luau"
	end
	local stripped = (string.gsub(name, "%.luau$", ""))
	if map[stripped] ~= nil then
		return stripped
	end
	return nil
end

-- build a require(name) closure over `map` (name -> source). `run(source, name)` compiles and
-- runs a module's source and returns its value. caching + cycle detection live here; a module
-- that returns nothing caches as `true` (so it still requires cleanly).
function Modules.newRequire(map: { [string]: string }, run: (source: string, name: string) -> any): (string) -> any
	local cache: { [string]: any } = {}
	local loading: { [string]: boolean } = {}

	local function req(name: string): any
		name = tostring(name)
		local key = resolve(map, name)
		if not key then
			error(`no kav module '{name}'`, 0)
		end
		if cache[key] ~= nil then
			return cache[key]
		end
		if loading[key] then
			error(`cyclic require of kav '{key}'`, 0)
		end
		loading[key] = true
		local ok, value = pcall(run, map[key], key)
		loading[key] = nil
		if not ok then
			error(value, 0)
		end
		if value == nil then
			value = true
		end
		cache[key] = value
		return value
	end

	return req
end

return Modules
