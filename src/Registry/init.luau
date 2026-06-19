-- The command registry. Holds command definitions, resolves names + aliases
-- (case-insensitively), and offers the fluent builder (sugar over the table form).
--
-- A definition is the canonical record from DESIGN → Command definition:
--   { Name, Aliases?, Description?, Network?, Permission?,
--     Args = { { Name, Types, Required?, Default? }, ... },
--     Attributes = { { Name, Short?, Description? }, ... },
--     Returns = { { Name, Type }, ... },
--     On = { Client?, Server?, Shared? } }

local Registry = {}
Registry.__index = Registry

export type NetworkKind = "Shared" | "Client" | "Server" | "Context"
export type Handler = (ctx: any, payload: any?) -> ()

export type Arg = { Name: string, Types: { string }, Required: boolean?, Default: any? }
export type Attribute = { Name: string, Short: string?, Description: string? }
export type Return = { Name: string, Type: string }

export type Definition = {
	Name: string,
	Aliases: { string }?,
	Description: string?,
	Network: NetworkKind?,
	Permission: string?,
	Args: { Arg }?,
	Attributes: { Attribute }?,
	Returns: { Return }?,
	On: { Client: Handler?, Server: Handler?, Shared: Handler? }?,
}

-- The fluent builder surface (so editors autocomplete the chain).
export type Builder = {
	Alias: (self: Builder, ...string) -> Builder,
	Description: (self: Builder, text: string) -> Builder,
	Network: (self: Builder, kind: NetworkKind) -> Builder,
	Permission: (self: Builder, role: string) -> Builder,
	Arg: (self: Builder, arg: Arg) -> Builder,
	Attribute: (self: Builder, attr: Attribute) -> Builder,
	Return: (self: Builder, ret: Return) -> Builder,
	On: (self: Builder, realm: NetworkKind, handler: Handler) -> Builder,
	Register: (self: Builder) -> Definition,
}

local VALID_NETWORK = { Shared = true, Client = true, Server = true, Context = true }

function Registry.new()
	return setmetatable({
		commands = {} :: { [string]: Definition }, -- keyed by lowercase Name
		aliases = {} :: { [string]: string }, -- lowercase alias -> lowercase Name
	}, Registry)
end

local function validate(def: Definition)
	assert(type(def.Name) == "string" and def.Name ~= "", "Karet.Register: a command needs a Name")
	local network = def.Network or "Shared"
	assert(VALID_NETWORK[network], `Karet.Register('{def.Name}'): invalid Network '{network}'`)
	assert(type(def.On) == "table", `Karet.Register('{def.Name}'): handlers must live under an On table`)
	if network == "Context" then
		assert(def.On.Client and def.On.Server, `'{def.Name}' is a Context command and needs both On.Client and On.Server`)
	else
		assert(def.On[network] or def.On.Shared, `'{def.Name}' (Network '{network}') needs an On.{network} handler`)
	end
end

-- Register a command from a table definition. Returns the stored definition.
function Registry:register(def: Definition): Definition
	validate(def)
	local key = string.lower(def.Name)
	self.commands[key] = def
	for _, alias in def.Aliases or {} do
		self.aliases[string.lower(alias)] = key
	end
	return def
end

-- Resolve a name or alias to a definition (case-insensitive).
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

-- All registered command names, sorted.
function Registry:list(): { string }
	local names = {}
	for _, def in self.commands do
		table.insert(names, def.Name)
	end
	table.sort(names)
	return names
end

-- ---------------------------------------------------------------------------
-- fluent builder — sugar that accumulates a Definition then :Register()s it
-- ---------------------------------------------------------------------------

local Builder = {}
Builder.__index = Builder

function Registry:command(name: string): Builder
	return setmetatable({
		registry = self,
		def = { Name = name, Aliases = {}, Args = {}, Attributes = {}, Returns = {}, On = {} } :: Definition,
	}, Builder) :: any
end

function Builder:Alias(...: string)
	for _, a in { ... } do
		table.insert(self.def.Aliases, a)
	end
	return self
end

function Builder:Description(text: string)
	self.def.Description = text
	return self
end

function Builder:Network(kind: string)
	self.def.Network = kind
	return self
end

function Builder:Permission(role: string)
	self.def.Permission = role
	return self
end

function Builder:Arg(arg: Arg)
	table.insert(self.def.Args, arg)
	return self
end

function Builder:Attribute(attr: Attribute)
	table.insert(self.def.Attributes, attr)
	return self
end

function Builder:Return(ret: Return)
	table.insert(self.def.Returns, ret)
	return self
end

function Builder:On(realm: string, handler: (...any) -> ())
	self.def.On[realm] = handler
	return self
end

function Builder:Register(): Definition
	return self.registry:register(self.def)
end

return Registry
