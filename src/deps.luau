-- Lazy resolver for Karet's runtime dependencies (Switch, Substance).
--
-- These are resolved through *functions*, never at module load, for two reasons:
--   1. Switch is CLIENT-ONLY - requiring it on the server errors. The Karet umbrella
--      loads on both realms, so it must never transitively require Switch at load time.
--   2. There is exactly ONE line (the `parent` below) to change if your install puts the
--      dependencies somewhere else.
--
-- Layout: Switch and Substance live as ModuleScripts *inside* the Karet module, so from
-- this module (also a child of the Karet root) they are siblings - `script.Parent.<Name>`.
-- (For a Wally install where deps are siblings of the package in a Packages folder, change
-- the line to `script.Parent.Parent`.) Resolution is wrapped so a missing dependency
-- degrades gracefully (a warning) instead of hard-crashing Karet.

local deps = {}

local cache: { [string]: any } = {}

local function resolve(name: string): any?
	if cache[name] ~= nil then
		return cache[name]
	end
	-- The Karet root is this module's parent; Switch/Substance sit beside us under it.
	local parent = script.Parent
	local ok, mod = pcall(function()
		return require((parent :: any)[name])
	end)
	if not ok then
		warn(`Karet: dependency '{name}' could not be resolved - {mod}`)
		return nil
	end
	cache[name] = mod
	return mod
end

-- Switch - input detection. Client-only; call this only from client code.
function deps.Switch(): any?
	return resolve("Switch")
end

-- Substance - networking transport. Safe on both realms.
function deps.Substance(): any?
	return resolve("Substance")
end

-- Iris - immediate-mode UI, used by Kaveat. Vendored under the Karet module.
function deps.Iris(): any?
	return resolve("Iris")
end

return deps
