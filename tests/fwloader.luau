-- Headless loader for Karet's framework modules (Types, Registry, Context, Host, ...).
--
-- Like tests/loader.luau but for the modules that hang off the Karet root rather than off
-- Shell. It emulates just enough of the instance tree for `script.Parent.X` requires to
-- resolve, and deliberately never loads the umbrella / Theme / Terminal (those touch
-- Color3 / game at module load, which lune lacks). The Roblox-only code paths inside these
-- modules (Player parsing, Substance) live behind functions, so the modules LOAD fine —
-- only calling those specific paths would need a live game.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

-- module name -> source file, relative to repo root
local FILES = {
	Types = "src/Types/init.luau",
	Registry = "src/Registry/init.luau",
	Context = "src/Context/init.luau",
	Host = "src/Host.luau",
	Networking = "src/Networking/init.luau",
	Commands = "src/Commands/init.luau",
	Cache = "src/Cache/init.luau",
	Query = "src/Query/init.luau",
	Complete = "src/Complete/init.luau",
	KaveatComplete = "src/Kaveat/Complete.luau",
	Diagnostics = "src/Kaveat/Diagnostics.luau",
	Alias = "src/Alias/init.luau",
	Search = "src/Terminal/Search.luau",
	Extensions = "src/Extensions/init.luau",
	deps = "src/deps.luau",
}

local nodeMt = {
	__index = function(self, key)
		if key == "Parent" then
			return rawget(self, "_parent")
		end
		local kids = rawget(self, "_children")
		local kid = kids and kids[key]
		if kid then
			return kid
		end
		error(`fwloader: '{rawget(self, "_name")}' has no child '{tostring(key)}'`, 2)
	end,
}

local function makeNode(name: string, file: string?, parent: any)
	return setmetatable({ _name = name, _file = file, _children = {}, _parent = parent }, nodeMt)
end

-- Packages folder -> Karet root -> the framework modules. Packages has no Switch/Substance
-- children, so deps.resolve() pcalls and degrades, exactly as in a real install missing them.
local packages = makeNode("Packages", nil, nil)
local root = makeNode("Karet", "src/init.luau", packages)
for name, file in FILES do
	root._children[name] = makeNode(name, file, root)
end

local cache: { [any]: any } = {}

local function customRequire(node: any)
	if cache[node] ~= nil then
		return cache[node]
	end
	local source = fs.readFile(rawget(node, "_file"))
	local chunk = luau.load(source, {
		debugName = rawget(node, "_name"),
		environment = { script = node, require = customRequire },
	})
	local result = chunk()
	cache[node] = result
	return result
end

local Loader = {}

function Loader.get(name: string): any
	local node = root._children[name]
	if not node then
		error(`fwloader: no module '{name}'`, 2)
	end
	return customRequire(node)
end

return Loader
