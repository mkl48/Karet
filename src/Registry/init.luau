-- The command registry. Holds command definitions, resolves names + aliases
-- (case-insensitively), and offers the fluent builder (sugar over the table form).
--
-- A definition is the canonical record from DESIGN → Command definition:
--   { Name, Aliases?, Description?, Network?, Permission?,
--     Args = { { Name, Types, Required?, Default? }, ... },
--     Flags = { { Name, Short?, Description? }, ... },        -- boolean -s toggles
--     Modifiers = { { Name, Types?, Default?, Description? }, ... }, -- --name=value
--     Returns = { { Name, Type }, ... },
--     On = { Client?, Server?, Shared? } }

local Registry = {}
Registry.__index = Registry

local Context = require(script.Parent.Context)
local Types = require(script.Parent.Types)

export type NetworkKind = "Shared" | "Client" | "Server" | "Context"

-- A typed command handler. TArgs is the command's arg record, so ctx.Args comes out fully typed
-- (ctx.Args.target : Player) instead of any. Defaults to a loose map for untyped commands.
export type Handler<TArgs = { [string]: any }> = (ctx: Context.Context<TArgs>, payload: any?) -> ()

-- One positional argument. You write `Type` (a built-in type name, or a list of names tried in
-- order, first that parses+validates wins). For a custom Karet.DefineType type, write
-- `Type = "MyType" :: any`. `Types` is the engine-canonical array the normalizer fills in.
export type Arg = {
	Name: string,
	Type: (Types.TypeName | { Types.TypeName })?,
	Types: { string }?,
	Required: boolean?,
	Default: any?,
	Description: string?,
}
-- boolean toggles: -s / -p (stackable shorts), declared per command
export type Flag = { Name: string, Short: string?, Description: string? }
-- valued long options: --delay=2 / --label=hi, optionally typed + defaulted
export type Modifier = {
	Name: string,
	Type: (Types.TypeName | { Types.TypeName })?,
	Types: { string }?,
	Default: any?,
	Description: string?,
}
export type Return = { Name: string, Type: string }

-- A command definition. `Name` is supplied as the first arg to Karet.Command (or carried in the
-- table for folder auto-load). Handlers are the top-level Server/Client/Shared fields; TArgs threads
-- your arg record into each handler's ctx. `On` is the engine-canonical form the normalizer fills.
export type Definition<TArgs = { [string]: any }> = {
	Name: string?,
	Aliases: { string }?,
	Description: string?,
	Network: NetworkKind?,
	Permission: string?,
	Dangerous: boolean?, -- prompt for confirmation before running (see Start{ PromptType })
	Args: { Arg }?,
	Flags: { Flag }?,
	Modifiers: { Modifier }?,
	Returns: { Return }?,
	Server: Handler<TArgs>?,
	Client: Handler<TArgs>?,
	Shared: Handler<TArgs>?,
	On: { Client: Handler<TArgs>?, Server: Handler<TArgs>?, Shared: Handler<TArgs>? }?,
}

local VALID_NETWORK = { Shared = true, Client = true, Server = true, Context = true }

-- Fold the public def shape into the engine's canonical record, in place: top-level Server/Client/
-- Shared handlers move under `On`, and each arg/modifier's `Type` becomes the `Types` array the
-- evaluator coerces against. Already-canonical defs (On/Types set directly) pass through untouched.
local function normalize(def: Definition)
	local on = def.On or {}
	if def.Server then
		on.Server = def.Server
	end
	if def.Client then
		on.Client = def.Client
	end
	if def.Shared then
		on.Shared = def.Shared
	end
	def.On = on

	local function fillTypes(specs: { any }?)
		for _, spec in specs or {} do
			if spec.Type ~= nil and spec.Types == nil then
				spec.Types = (type(spec.Type) == "table" and spec.Type) or { spec.Type }
			end
		end
	end
	fillTypes(def.Args)
	fillTypes(def.Modifiers)
end

--[=[
	@class Registry

	Holds the command definitions, keyed by name (case-insensitive) with alias resolution. One
	registry is shared across both realms. You usually go through [Karet.Command] rather than
	touching this directly.
]=]
function Registry.new()
	return setmetatable({
		commands = {} :: { [string]: Definition }, -- keyed by lowercase Name
		aliases = {} :: { [string]: string }, -- lowercase alias -> lowercase Name
	}, Registry)
end

local function validate(def: Definition)
	assert(type(def.Name) == "string" and def.Name ~= "", "Karet.Command: a command needs a Name")
	local network = def.Network or "Shared"
	assert(VALID_NETWORK[network], `Karet.Command('{def.Name}'): invalid Network '{network}'`)
	local on = def.On or {}
	if network == "Context" then
		assert(on.Client and on.Server, `'{def.Name}' is a Context command and needs both a Client and a Server handler`)
	else
		assert(on[network] or on.Shared, `'{def.Name}' (Network '{network}') needs a {network} (or Shared) handler`)
	end
end

--[=[
	@within Registry
	@method register
	@param def Definition
	@return Definition
	Register a command from a table definition. The def is normalized (top-level Server/Client/Shared
	handlers folded into `On`, each arg's `Type` expanded into `Types`) then validated. Returns the
	stored definition.
]=]
function Registry:register(def: Definition): Definition
	normalize(def)
	validate(def)
	local key = string.lower(def.Name)
	self.commands[key] = def
	for _, alias in def.Aliases or {} do
		self.aliases[string.lower(alias)] = key
	end
	return def
end

-- Register a list of def tables, isolating failures so one bad command doesn't sink the batch
-- (used by the folder auto-loader). Returns the names that registered and a list of the ones that
-- threw, each as { name, error }.
function Registry:registerMany(defs: { Definition }): ({ string }, { { name: string, error: string } })
	local ok, errors = {}, {}
	for _, def in defs do
		local success, result = pcall(function()
			return self:register(def)
		end)
		if success then
			table.insert(ok, def.Name)
		else
			table.insert(errors, { name = tostring(type(def) == "table" and def.Name or def), error = tostring(result) })
		end
	end
	return ok, errors
end

-- Drop a command (and any of its aliases) from the registry. used by the function/macro
-- system when you redefine or remove a user function. no-op if it isnt registered.
function Registry:unregister(name: string)
	local key = string.lower(name)
	local def = self.commands[key]
	if not def then
		return
	end
	self.commands[key] = nil
	for _, alias in def.Aliases or {} do
		local a = string.lower(alias)
		if self.aliases[a] == key then
			self.aliases[a] = nil
		end
	end
end

--[=[
	@within Registry
	@method get
	@param name string
	@return Definition?
	Resolve a name or alias to a definition (case-insensitive).
]=]
function Registry:get(name: string): Definition?
	local key = string.lower(name)
	local direct = self.commands[key]
	if direct then
		return direct
	end
	local aliased = self.aliases[key]
	return aliased and self.commands[aliased] or nil
end

function Registry:has(name: string): boolean
	return self:get(name) ~= nil
end

--[=[
	@within Registry
	@method list
	@return {string}
	All registered command names, sorted.
]=]
function Registry:list(): { string }
	local names = {}
	for _, def in self.commands do
		table.insert(names, def.Name)
	end
	table.sort(names)
	return names
end

return Registry
