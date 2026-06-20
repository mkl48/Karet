-- Karet - an in-game command framework and terminal for Roblox.
--
-- Karet is the product, the terminal emulator (the ScreenGui CLI surface), and the
-- shell/command grammar that runs inside it. Kaveat is the built-in Luau editor.
-- Built on Switch (input) and Substance (networking).
--
-- One entry point on both realms: require(ReplicatedStorage.Karet). Behaviour diverges
-- by RunService internally - Start() boots the client terminal or the server listener.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shell = require(script.Shell)
local Theme = require(script.Theme)
local Terminal = require(script.Terminal)
local Registry = require(script.Registry)
local Types = require(script.Types)
local Host = require(script.Host)
local Networking = require(script.Networking)
local Commands = require(script.Commands)
local Kaveat = require(script.Kaveat)
local Cache = require(script.Cache)
local Query = require(script.Query)
local Profile = require(script.Profile)
local Complete = require(script.Complete)
local ContextMod = require(script.Context)
local Prompt = require(script.Prompt)

-- ---------------------------------------------------------------------------
-- public types (exported so editors autocomplete config + params)
-- ---------------------------------------------------------------------------

export type ThemePalette = Theme.Palette
export type ThemeGroup = Theme.Group
export type Argument = Registry.Arg
export type Attribute = Registry.Attribute
export type ReturnSpec = Registry.Return
export type NetworkKind = Registry.NetworkKind
export type Handler = Registry.Handler
export type CommandDefinition = Registry.Definition
export type CommandBuilder = Registry.Builder
export type Context = ContextMod.Context
export type TypeDefinition = Types.Definition
export type RateLimit = { MaxCalls: number, Window: number }
export type ToggleSpec = string | { Key: string, Modifier: string? }

export type StartConfig = {
	Toggle: ToggleSpec?, -- key / shortcut to open the terminal, e.g. "Semicolon" or "LeftControl+Semicolon"
	Theme: (string | ThemePalette)?, -- a built-in theme name or a palette
	Placement: ("Window" | "Top" | "Bottom" | "Middle")?, -- where the window/bar sits
	Compact: boolean?, -- single-line command bar instead of the full window
	Draggable: boolean?, -- drag the Window-placement terminal by its title bar
	Parent: Instance?, -- where to mount (defaults to PlayerGui)
	Size: UDim2?, -- override the window size
	Position: UDim2?, -- override the window position
	Kaveat: boolean?, -- enable the Kaveat editor
	PromptType: ("text" | "window")?, -- how Dangerous commands confirm: terminal y/N or an Iris modal
	BuiltIns: boolean?, -- register built-in commands (default true)
	DefaultRole: string?, -- server: default role for players
	RateLimit: RateLimit?, -- server: rate limiting (reserved)
	KaveatExec: (boolean | (player: Player) -> boolean)?, -- server: allow kaveat to run code (studio always allowed)
}

local Karet = {}

Karet.Version = "0.1.0"

-- ---------------------------------------------------------------------------
-- shared framework state (one registry + type system across both realms)
-- ---------------------------------------------------------------------------

local registry = Registry.new()
local types = Types.new()
local cache = Cache.new()
local query = Query.new()
local hooks = { pre = {}, post = {}, onErr = {}, onConnect = {} }
local auth = { allowed = {} :: { [number]: boolean }, denied = {} :: { [number]: boolean }, defaultRole = "User" }

-- A built-in query so commands can list commands uniformly: ctx.Query:Run("commands").
query:Register("commands", function()
	return registry:list()
end)

-- ---------------------------------------------------------------------------
-- shell surface
-- ---------------------------------------------------------------------------

-- The shell lives under Karet directly (no separate sub-brand). Power users can reach
-- the pieces via Karet.Shell; the common entry points are re-exported flat.
Karet.Shell = Shell
Karet.Tokenize = Shell.Tokenize
Karet.Parse = Shell.Parse
Karet.Analyze = Shell.Analyze

-- One semantic colorscheme piped through every Karet surface (terminal, editor, pickers).
-- Set with Karet.Theme.Set("gruvbox") or pass a built-in to Start{ Theme = ... }.
Karet.Theme = Theme

-- The terminal surface (class). Karet.Start builds and mounts one on the client.
Karet.Terminal = Terminal

-- Kaveat, the built-in Luau editor (scaffold). Enable with Start{ Kaveat = true }.
Karet.Kaveat = Kaveat

-- Global key/value cache + named-query service, also reachable from handlers as
-- ctx.Cache / ctx.Query. One instance per realm.
Karet.Cache = cache
Karet.Query = query

-- profiles, holds history / theme / saved kav scripts. Karet.Profile is the active one
local profiles = { default = Profile.new("default") }
Karet.Profiles = profiles
Karet.Profile = profiles.default

function Karet.UseProfile(name: string): Profile.Profile
	local p = profiles[name]
	if not p then
		p = Profile.new(name)
		profiles[name] = p
	end
	Karet.Profile = p
	return p
end

-- Config the server stashes (rate limiting etc. land in a later layer).
Karet.Config = {}

-- ---------------------------------------------------------------------------
-- command + type registration
-- ---------------------------------------------------------------------------

-- Register a command from a table definition (DESIGN → Command definition).
function Karet.Register(def: CommandDefinition): CommandDefinition
	return registry:register(def)
end

-- Start the fluent builder: Karet.Command("ban"):Alias("b"):...:Register().
function Karet.Command(name: string): CommandBuilder
	return registry:command(name)
end

-- Register a custom argument type (à la Cmdr/Conch).
function Karet.DefineType(name: string, def: TypeDefinition)
	types:Define(name, def)
end

-- Names of all registered commands, and a single command's definition.
function Karet.List(): { string }
	return registry:list()
end

function Karet.Get(name: string): any?
	return registry:get(name)
end

-- ---------------------------------------------------------------------------
-- auth & roles (server-authoritative)
-- ---------------------------------------------------------------------------

function Karet.SetRoleHook(fn: (player: Player) -> string)
	auth.roleHook = fn
end

function Karet.SetAuthHook(fn: (player: Player, command: string) -> boolean?)
	auth.authHook = fn
end

function Karet.SetGroupHook(fn: (player: Player) -> number)
	auth.groupHook = fn
end

function Karet.AllowPlayer(userId: number)
	auth.allowed[userId] = true
end

function Karet.DenyPlayer(userId: number)
	auth.denied[userId] = true
end

function Karet.SetDefaultRole(role: string)
	auth.defaultRole = role
end

-- Define the role -> rank ordering used for Permission comparisons.
function Karet.SetRoles(ranks: { [string]: number })
	auth.roleRanks = ranks
end

-- ---------------------------------------------------------------------------
-- middleware
-- ---------------------------------------------------------------------------

function Karet.PreExecute(fn: (ctx: Context) -> any?)
	table.insert(hooks.pre, fn)
end

function Karet.PostExecute(fn: (ctx: Context, result: any) -> ())
	table.insert(hooks.post, fn)
end

function Karet.OnErr(fn: (ctx: Context, err: any) -> ())
	table.insert(hooks.onErr, fn)
end

function Karet.OnConnect(fn: (player: Player) -> ())
	table.insert(hooks.onConnect, fn)
end

-- ---------------------------------------------------------------------------
-- boot
-- ---------------------------------------------------------------------------

local function buildAuth()
	return {
		roleHook = auth.roleHook,
		authHook = auth.authHook,
		groupHook = auth.groupHook,
		allowed = auth.allowed,
		denied = auth.denied,
		roleRanks = auth.roleRanks,
		defaultRole = auth.defaultRole,
	}
end

local function startClient(options: StartConfig)
	if options.Theme ~= nil then
		Karet.Theme.Set(options.Theme)
	elseif Karet.Profile.CurrentTheme ~= "" then
		Karet.Theme.Set(Karet.Profile.CurrentTheme)
	end

	local terminal = Terminal.new(options :: any)
	terminal:mount()
	-- back the input history with the profile so it sticks around
	terminal.input.history = Karet.Profile.History
	-- autocomplete + signature + command colouring from the registry + types
	terminal.input:setCompleter(Complete.build(registry, types))
	if options.Toggle then
		local ok, err = pcall(function()
			terminal:enableSwitch(options.Toggle)
		end)
		if not ok then
			warn("karet: couldnt bind the toggle key - " .. tostring(err))
		end
	end

	-- Built-in commands (help/clear/echo/theme/...), unless opted out.
	if options.BuiltIns ~= false then
		local services = {
			clear = function()
				terminal:clear()
			end,
			setTheme = function(name)
				Karet.Theme.Set(name)
				Karet.Profile.CurrentTheme = name
			end,
			listThemes = function()
				return Karet.Theme.List()
			end,
			list = function()
				return registry:list()
			end,
			get = function(name)
				return registry:get(name)
			end,
			playerName = function()
				local p = Players.LocalPlayer
				return p and p.Name or "client"
			end,
			editor = function()
				return Karet.Editor
			end,
			closeTerminal = function()
				terminal:close()
			end,
			version = Karet.Version,
		}
		for _, def in Commands.build(services) do
			registry:register(def)
		end
	end

	-- Dangerous-command confirmation. "window" pops an Iris modal (falls back to text if Iris
	-- isn't around); "text" (default) asks y/N right on the terminal. Both yield until answered.
	local promptType = options.PromptType or "text"
	local function confirm(name: string, _def: any): boolean
		local question = `run dangerous command '{name}'?`
		if promptType == "window" and Prompt.available() then
			return Prompt.window(question, terminal.gui.Parent)
		end
		return terminal:promptText(question)
	end

	local networking = Networking.new()
	local host = Host.new({
		registry = registry,
		types = types,
		isClient = true,
		player = Players.LocalPlayer,
		sink = function(group, message)
			terminal:print(message, group)
		end,
		hooks = hooks,
		auth = buildAuth(),
		networking = networking,
		cache = cache,
		query = query,
		indicator = function(indicatorOpts)
			return terminal:indicator(indicatorOpts)
		end,
		confirm = confirm,
	})
	local evaluator = Shell.newEvaluator(host)

	terminal:onSubmit(function(line: string)
		local parsed = Karet.Parse(line)
		if #parsed.diagnostics > 0 then
			for _, d in parsed.diagnostics do
				terminal:error(d.message)
			end
			return
		end
		host.session.rawInput = line
		local ok, result = pcall(function()
			return evaluator:run(parsed.ast)
		end)
		if not ok then
			terminal:error(tostring(result))
		elseif type(result) == "table" and result.ok == false and result.error then
			terminal:error(result.error)
		end
	end)

	-- kaveat editor, mounted beside the terminal if enabled
	if options.Kaveat then
		local editor = Kaveat.new({ Parent = terminal.gui.Parent })
		editor:mount(terminal.gui.Parent)
		-- save/open named scripts from the active profile
		editor:setStore(function()
			return Karet.Profile.Kavs
		end)
		-- ctrl+enter / :run ships the script to the server to loadstring
		editor:setRunner(function(source, _context)
			local res = networking:invokeKaveat(source, _context)
			if res.ok then
				return res.output or "ran ok"
			end
			error(res.error or "run failed")
		end)
		Karet.Editor = editor
	end

	Karet.Active = terminal
	Karet.Host = host
	Karet.Evaluator = evaluator
	return terminal
end

local function startServer(options: StartConfig)
	if options.DefaultRole then
		auth.defaultRole = options.DefaultRole
	end
	Karet.Config.DefaultRole = auth.defaultRole
	Karet.Config.RateLimit = options.RateLimit
	Karet.Config.KaveatExec = options.KaveatExec

	local networking = Networking.new()
	local host = Host.new({
		registry = registry,
		types = types,
		isServer = true,
		hooks = hooks,
		auth = buildAuth(),
		networking = networking,
		cache = cache,
		query = query,
	})
	networking:listen(function(request, player)
		return host.runServerRequest(request, player)
	end)

	-- kaveat runs code with loadstring (server only). gated for safety: studio is always
	-- allowed, otherwise Start{ KaveatExec = true } or KaveatExec = function(player) ... end.
	-- WARNING: enabling this on a live game lets allowed clients run arbitrary server code.
	local function kaveatAllowed(player): boolean
		if RunService:IsStudio() then
			return true
		end
		local ke = Karet.Config.KaveatExec
		if type(ke) == "function" then
			return ke(player) == true
		end
		return ke == true
	end
	networking:listenKaveat(function(payload, player)
		if not kaveatAllowed(player) then
			return { ok = false, error = "kaveat run is disabled here (server Start{ KaveatExec = true })" }
		end
		local okc, fn, compileErr = pcall(loadstring, payload.source)
		if not okc then
			return { ok = false, error = "loadstring is off (enable ServerScriptService.LoadStringEnabled)" }
		end
		if not fn then
			return { ok = false, error = "compile error: " .. tostring(compileErr) }
		end
		local okr, result = pcall(fn)
		if not okr then
			return { ok = false, error = tostring(result) }
		end
		return { ok = true, output = result ~= nil and tostring(result) or "ran ok" }
	end)

	-- OnConnect middleware
	Players.PlayerAdded:Connect(function(player)
		for _, fn in hooks.onConnect do
			task.spawn(fn, player)
		end
	end)
	for _, player in Players:GetPlayers() do
		for _, fn in hooks.onConnect do
			task.spawn(fn, player)
		end
	end

	Karet.Host = host
	return nil
end

-- Boot Karet. Client → build+wire the terminal and the command evaluator; server → stand
-- up the networking listener + auth pipeline. One `Karet.Start(...)` works in both realms.
function Karet.Start(opts: StartConfig?): Terminal.Terminal?
	local options: StartConfig = opts or {}
	if RunService:IsClient() then
		return startClient(options)
	end
	return startServer(options)
end

return Karet
