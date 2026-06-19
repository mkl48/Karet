-- Lazy resolver for Karet's runtime dependencies (Switch, Substance).
--
-- These are resolved through *functions*, never at module load, for two reasons:
--   1. Switch is CLIENT-ONLY — requiring it on the server errors. The Karet umbrella
--      loads on both realms, so it must never transitively require Switch at load time.
--   2. The install layout isn't known until Wally places packages. Centralising the
--      require here means there is exactly ONE line to adjust if the path differs.
--
-- Wally convention: a package's dependencies are installed as siblings of the package
-- root, so from this module (which sits at the Karet root, `src/`) the dep links live at
-- `script.Parent.Parent.<Name>`. Resolution is wrapped so a missing dependency degrades
-- gracefully (a warning) instead of hard-crashing Karet.

local deps = {}

local cache: { [string]: any } = {}

local function resolve(name: string): any?
	if cache[name] ~= nil then
		return cache[name]
	end
	-- Karet root is this module's parent folder; its parent is the Packages folder that
	-- holds the dependency link scripts.
	local packages = script.Parent.Parent
	local ok, mod = pcall(function()
		return require((packages :: any)[name])
	end)
	if not ok then
		warn(`Karet: dependency '{name}' could not be resolved — {mod}`)
		return nil
	end
	cache[name] = mod
	return mod
end

-- Switch — input detection. Client-only; call this only from client code.
function deps.Switch(): any?
	return resolve("Switch")
end

-- Substance — networking transport. Safe on both realms.
function deps.Substance(): any?
	return resolve("Substance")
end

return deps
