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
local KavModules = require(script.Kaveat.Modules)
local Cache = require(script.Cache)
local Query = require(script.Query)
local Profile = require(script.Profile)
local Complete = require(script.Complete)
local ContextMod = require(script.Context)
local Render = require(script.Render)
local Defaults = require(script.Defaults)
local WindowManager = require(script.WindowManager)
local Alias = require(script.Alias)
local Extensions = require(script.Extensions)
local Admin = require(script.Admin)
local ThemeEditor = require(script.Theme.Editor)

-- ---------------------------------------------------------------------------
-- public types (exported so editors autocomplete config + params)
-- ---------------------------------------------------------------------------

export type ThemePalette = Theme.Palette
export type ThemeGroup = Theme.Group
export type Argument = Registry.Arg
export type ReturnSpec = Registry.Return
export type NetworkKind = Registry.NetworkKind
export type Handler<TArgs = { [string]: any }> = Registry.Handler<TArgs>
export type CommandDefinition<TArgs = { [string]: any }> = Registry.Definition<TArgs>
-- the ctx handed to every handler. parameterise it with your arg record for typed args:
-- `Server = function(ctx: Karet.Context<{ target: Player }>) ... end`
export type Context<TArgs = { [string]: any }> = ContextMod.Context<TArgs>
-- a built-in argument type name ("Player" / "Number" / ...), for Arg.Type
export type TypeName = Types.TypeName
export type TypeDefinition = Types.Definition
export type RateLimit = { MaxCalls: number, Window: number }
export type ToggleSpec = string | { Key: string, Modifier: string? }

--[=[
	@interface StartConfig
	@within Karet
	.Toggle ToggleSpec? -- key / shortcut to open the terminal, e.g. "Semicolon" or "LeftControl+Semicolon"
	.Theme (string | ThemePalette)? -- a built-in theme name or a palette
	.Placement ("Window" | "Top" | "Bottom" | "Middle")? -- where the window / bar sits
	.Compact boolean? -- single-line command bar instead of the full window
	.Draggable boolean? -- drag the Window-placement terminal by its title bar
	.Parent Instance? -- where to mount (defaults to PlayerGui)
	.Size UDim2? -- override the window size
	.Position UDim2? -- override the window position
	.Kaveat boolean? -- enable the Kaveat editor
	.PromptType ("text" | "window")? -- how Dangerous commands confirm: terminal y/N or an Iris modal
	.Persist boolean? -- autosave/load the profile via Pik DataStores. on by default; pass false to disable
	.Admin boolean? -- enable the moderation suite (kick / ban / mute / audit + dashboard)
	.BuiltIns boolean? -- register built-in commands (default true)
	.Commands (Instance | { Instance } | { CommandDefinition<any> })? -- auto-load command modules: a Folder (required recursively), a list of ModuleScripts, or ready-made defs
	.DefaultRole string? -- server: default role for players
	.RateLimit RateLimit? -- server: rate limiting (reserved)
	.KaveatExec (boolean | (player: Player) -> boolean)? -- server: allow kaveat to run code

	The options table passed to [Karet.Start]. The same shape is used on both realms; each
	realm reads the options that apply to it.
]=]
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
	Persist: boolean?, -- autosave/load the profile (history/vars/kavs/theme/aliases/functions) via Pik DataStores. defaults on; false disables
	Admin: boolean?, -- enable the moderation suite (kick/ban/mute/audit + dashboard)
	BuiltIns: boolean?, -- register built-in commands (default true)
	Commands: (Instance | { Instance } | { CommandDefinition<any> })?, -- auto-load command modules (Folder, list of ModuleScripts, or ready-made defs)
	DefaultRole: string?, -- server: default role for players
	RateLimit: RateLimit?, -- server: rate limiting (reserved)
	KaveatExec: (boolean | (player: Player) -> boolean)?, -- server: allow kaveat to run code (studio always allowed)
}

--[=[
	@class Karet

	The Karet entry point. `require` it on both realms and call [Karet.Start] once per realm:

	```lua
	local Karet = require(game.ReplicatedStorage.Karet)
	Karet.Start({ Toggle = "Semicolon", Theme = "tokyonight", Kaveat = true })
	```

	`Karet` is the product, the terminal surface, and the shell grammar that runs inside it.
	Register your own commands with [Karet.Command], gate them with the permission hooks, and
	hook the lifecycle with the middleware hooks. The shell, theme engine, editor and rich
	output toolkit hang off this table too ([Karet.Shell], [Karet.Theme], ...).
]=]
local Karet = {}

--[=[
	@prop Version string
	@within Karet
	@readonly
	The Karet version string, e.g. `"0.1.0"`.
]=]
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

-- The rich-output toolkit (panels, tables, trees, charts, ...). Pure string builders, also
-- handed to handlers as ctx.UI. Karet.Render.table{...} etc. work anywhere.
Karet.Render = Render

-- Tunable constants (fonts, sizes, timings, zoom limits, ...). One source of truth for the
-- magic numbers, reachable from kav scripts and the `defaults` command.
Karet.Defaults = Defaults

-- Iris-backed windows for commands (ctx.Window). Karet.WindowManager.open{...} also works
-- directly. Client-only.
Karet.WindowManager = WindowManager

-- ---------------------------------------------------------------------------
-- extension platform - register commands, types, and dockable panels so tools
-- (yours or third-party) plug into the same shell. `panels` / `open` surface them.
-- ---------------------------------------------------------------------------

local extensions = Extensions.new()
Karet.Extensions = extensions

--[=[
	@within Karet
	@function RegisterPanel
	@tag Commands
	@param panel Panel
	@return Panel
	Register a dockable panel, a named view usually built with `ctx.Window` inside its `Open`.
	Panels are surfaced by the `panels` command and opened with `open <name>`.
]=]
function Karet.RegisterPanel(panel: Extensions.Panel): Extensions.Panel
	return extensions:registerPanel(panel)
end

--[=[
	@within Karet
	@function RegisterExtension
	@tag Commands
	@param ext Extension
	@return Extension
	Register a whole extension: its `Commands` and `Types` are wired into Karet, its `Panels`
	become openable, and `Init(Karet)` runs once. This is the unit that makes Karet a platform.
]=]
function Karet.RegisterExtension(ext: Extensions.Extension): Extensions.Extension
	assert(type(ext) == "table" and type(ext.Name) == "string" and ext.Name ~= "", "Karet.RegisterExtension: needs a Name")
	if ext.Types then
		for name, def in ext.Types do
			types:Define(name, def)
		end
	end
	local commandNames = {}
	if ext.Commands then
		for _, def in ext.Commands do
			registry:register(def)
			table.insert(commandNames, def.Name)
		end
	end
	local panelNames = {}
	if ext.Panels then
		for _, panel in ext.Panels do
			extensions:registerPanel(panel)
			table.insert(panelNames, panel.Name)
		end
	end
	extensions:addExtension({ Name = ext.Name, Description = ext.Description, Commands = commandNames, Panels = panelNames })
	if type(ext.Init) == "function" then
		task.spawn(ext.Init, Karet)
	end
	return ext
end

--[=[
	@within Karet
	@function Panels
	@tag Commands
	@return {Panel}
	Every registered panel.
]=]
function Karet.Panels(): { Extensions.Panel }
	return extensions:listPanels()
end

-- Global key/value cache + named-query service, also reachable from handlers as
-- ctx.Cache / ctx.Query. One instance per realm.
Karet.Cache = cache
Karet.Query = query

-- Shell environment variables - the @name store the shell reads/writes. This IS the
-- evaluator's variable scope (shared), so defaults set here, the `set` command, and
-- `(x = ...)` assignments all see the same table. Seed defaults before Karet.Start.
Karet.Env = {} :: { [string]: any }

--[=[
	@within Karet
	@function SetVar
	@tag Variables
	@param name string
	@param value any
	Set a shell variable. The same value is readable in the shell as `@name`, since this writes
	straight into the evaluator's scope ([Karet.Env]). Seed defaults before [Karet.Start].
]=]
function Karet.SetVar(name: string, value: any)
	Karet.Env[name] = value
end

--[=[
	@within Karet
	@function GetVar
	@tag Variables
	@param name string
	@return any
	Read a shell variable (the `@name` store).
]=]
function Karet.GetVar(name: string): any
	return Karet.Env[name]
end

-- a couple handy defaults; users add their own with Karet.SetVar or the `set` command
Karet.Env.pi = math.pi
Karet.Env.version = Karet.Version

--[=[
	@within Karet
	@function Run
	@tag Output
	@param line string
	@return any
	Run a line through the shell (alias-expanded), exactly as if it had been typed. Returns the
	chain result `{ ok, returns?, error? }`, or `nil` before [Karet.Start] has run.
]=]
function Karet.Run(line: string): any
	if not Karet.Evaluator then
		return nil
	end
	line = Alias.expand(line, Karet.Profile.Aliases)
	local parsed = Karet.Parse(line)
	if #parsed.diagnostics > 0 then
		return { ok = false, error = parsed.diagnostics[1].message }
	end
	return Karet.Evaluator:run(parsed.ast)
end

--[=[
	@within Karet
	@function Toast
	@tag Output
	@client
	@param text string
	@param opts { group: string?, title: string?, duration: number? }?
	Pop a transient toast notification on the active terminal. No-op on the server or before a
	terminal exists. `group` keys into the theme like any output group. Handy for extensions and
	admin events.
]=]
function Karet.Toast(text: string, opts: { [string]: any }?)
	if Karet.Active then
		Karet.Active:toast(text, opts)
	end
end

-- Server-side: is this player muted? (set by the `mute` command; nil before Admin setup.)
function Karet.IsMuted(player: any): boolean
	local backend = Karet._adminBackend
	if backend and player then
		return backend.isMuted(player.UserId)
	end
	return false
end

-- Open the @CONFIG editor (wired up by startClient). The `config` command calls this.
function Karet.OpenConfig()
	if Karet._openConfig then
		Karet._openConfig()
	else
		warn("karet: config editor is client + Kaveat only (Start{ Kaveat = true })")
	end
end

-- profiles, holds history / theme / saved kav scripts. Karet.Profile is the active one
local profiles = { default = Profile.new("default") }
Karet.Profiles = profiles
Karet.Profile = profiles.default

--[=[
	@within Karet
	@function UseProfile
	@tag Setup
	@param name string
	@return Profile
	Switch the active profile (history, theme, saved kavs, aliases, functions), creating it if
	it doesn't exist yet. [Karet.Profile] then points at it.
]=]
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

--[=[
	@within Karet
	@function Command
	@tag Commands
	@param name string
	@param def CommandDefinition
	@return CommandDefinition
	Define and register a command. The one way to add a command:

	```lua
	type BanArgs = { target: Player, reason: string? }

	Karet.Command("ban", {
	    Network = "Server",
	    Permission = "Admin",
	    Args = {
	        { Name = "target", Type = "Player" },
	        { Name = "reason", Type = "String", Required = false },
	    },
	    Server = function(ctx: Karet.Context<BanArgs>)
	        -- ctx.Args.target is typed as Player, ctx.Args.reason as string?
	    end,
	})
	```

	Declare the arg record (`BanArgs` here) and annotate the handler's `ctx` with
	`Karet.Context<...>` to get fully typed, autocompleted `ctx.Args`. See
	[the commands guide](/docs/commands) for the full shape.
]=]
function Karet.Command<TArgs>(name: string, def: CommandDefinition<TArgs>): CommandDefinition<TArgs>
	def.Name = name
	return registry:register(def)
end

--[=[
	@within Karet
	@function DefineType
	@tag Commands
	@param name string
	@param def TypeDefinition
	Register a custom argument type (a la Cmdr). Types parse and validate the raw token into a
	typed value, and can supply autocomplete.
]=]
function Karet.DefineType(name: string, def: TypeDefinition)
	types:Define(name, def)
end

--[=[
	@within Karet
	@function List
	@tag Commands
	@return {string}
	The names of every registered command.
]=]
function Karet.List(): { string }
	return registry:list()
end

--[=[
	@within Karet
	@function Get
	@tag Commands
	@param name string
	@return CommandDefinition?
	A single command's definition, or nil.
]=]
function Karet.Get(name: string): any?
	return registry:get(name)
end

-- ---------------------------------------------------------------------------
-- auth & roles (server-authoritative)
-- ---------------------------------------------------------------------------

--[=[
	@within Karet
	@function SetRoleHook
	@tag Permissions
	@server
	@param fn (player: Player) -> string
	Decide a player's role. Roles are compared against a command's `Permission` using the rank
	ordering from [Karet.SetRoles].
]=]
function Karet.SetRoleHook(fn: (player: Player) -> string)
	auth.roleHook = fn
end

--[=[
	@within Karet
	@function SetAuthHook
	@tag Permissions
	@server
	@param fn (player: Player, command: string) -> boolean?
	A per-command gate. Return `true` to allow, `false` to deny, or `nil` to fall through to the
	normal role check.
]=]
function Karet.SetAuthHook(fn: (player: Player, command: string) -> boolean?)
	auth.authHook = fn
end

--[=[
	@within Karet
	@function SetGroupHook
	@tag Permissions
	@server
	@param fn (player: Player) -> number
	Resolve a player's numeric rank (e.g. a Roblox group rank), for commands that compare against
	a number.
]=]
function Karet.SetGroupHook(fn: (player: Player) -> number)
	auth.groupHook = fn
end

--[=[
	@within Karet
	@function AllowPlayer
	@tag Permissions
	@server
	@param userId number
	Allowlist a userId outright.
]=]
function Karet.AllowPlayer(userId: number)
	auth.allowed[userId] = true
end

--[=[
	@within Karet
	@function DenyPlayer
	@tag Permissions
	@server
	@param userId number
	Denylist a userId outright.
]=]
function Karet.DenyPlayer(userId: number)
	auth.denied[userId] = true
end

--[=[
	@within Karet
	@function SetDefaultRole
	@tag Permissions
	@server
	@param role string
	The role players get when no role hook is set or it returns nothing.
]=]
function Karet.SetDefaultRole(role: string)
	auth.defaultRole = role
end

--[=[
	@within Karet
	@function SetRoles
	@tag Permissions
	@server
	@param ranks { [string]: number }
	Define the role -> rank ordering used for `Permission` comparisons, e.g.
	`{ User = 0, Mod = 50, Admin = 100 }`.
]=]
function Karet.SetRoles(ranks: { [string]: number })
	auth.roleRanks = ranks
end

-- ---------------------------------------------------------------------------
-- middleware
-- ---------------------------------------------------------------------------

--[=[
	@within Karet
	@function PreExecute
	@tag Middleware
	@param fn (ctx: Context) -> any?
	Run before every command. Return `false` to cancel it.
]=]
function Karet.PreExecute(fn: (ctx: Context) -> any?)
	table.insert(hooks.pre, fn)
end

--[=[
	@within Karet
	@function PostExecute
	@tag Middleware
	@param fn (ctx: Context, result: any) -> ()
	Run after every command with its result.
]=]
function Karet.PostExecute(fn: (ctx: Context, result: any) -> ())
	table.insert(hooks.post, fn)
end

--[=[
	@within Karet
	@function OnErr
	@tag Middleware
	@param fn (ctx: Context, err: any) -> ()
	Run when a command errors.
]=]
function Karet.OnErr(fn: (ctx: Context, err: any) -> ())
	table.insert(hooks.onErr, fn)
end

--[=[
	@within Karet
	@function OnConnect
	@tag Middleware
	@server
	@param fn (player: Player) -> ()
	Run when a player joins.
]=]
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
	terminal.input:setCompleter(Complete.build(registry, types, function()
		local names = {}
		for k in Karet.Env do
			table.insert(names, k)
		end
		table.sort(names)
		return names
	end))
	-- command palette (ctrl+shift+p) draws its list straight from the registry
	terminal.input:setPaletteSource(function()
		local items = {}
		for _, name in registry:list() do
			local d = registry:get(name)
			table.insert(items, { name = name, detail = (d and d.Description) or "" })
		end
		return items
	end)
	if options.Toggle then
		local ok, err = pcall(function()
			terminal:enableSwitch(options.Toggle)
		end)
		if not ok then
			warn("karet: couldnt bind the toggle key - " .. tostring(err))
		end
	end

	-- Background-job registry (drives `every` / `jobs` / `stop`). A job is just a label + a
	-- cancel function; the command that starts it owns the loop.
	local jobList: { [number]: { id: number, label: string, cancel: () -> () } } = {}
	local nextJobId = 0
	local jobs = {
		add = function(label: string, cancel: () -> ()): number
			nextJobId += 1
			jobList[nextJobId] = { id = nextJobId, label = label, cancel = cancel }
			return nextJobId
		end,
		remove = function(id: number)
			jobList[id] = nil
		end,
		stop = function(id: number): boolean
			local j = jobList[id]
			if not j then
				return false
			end
			pcall(j.cancel)
			jobList[id] = nil
			return true
		end,
		stopAll = function()
			for id, j in jobList do
				pcall(j.cancel)
				jobList[id] = nil
			end
		end,
		list = function()
			local out = {}
			for _, j in jobList do
				table.insert(out, j)
			end
			table.sort(out, function(a, b)
				return a.id < b.id
			end)
			return out
		end,
	}

	-- Pipe the whole game's print/warn/error stream into the terminal (the `logs` command).
	local logConn: RBXScriptConnection? = nil
	local logCapture = {
		on = function()
			if logConn then
				return
			end
			logConn = game:GetService("LogService").MessageOut:Connect(function(msg, msgType)
				local group = "Output"
				if msgType == Enum.MessageType.MessageError then
					group = "Error"
				elseif msgType == Enum.MessageType.MessageWarning then
					group = "Warn"
				elseif msgType == Enum.MessageType.MessageInfo then
					group = "Info"
				end
				terminal:print(msg, group)
			end)
		end,
		off = function()
			if logConn then
				logConn:Disconnect()
				logConn = nil
			end
		end,
		isOn = function(): boolean
			return logConn ~= nil
		end,
	}

	-- re-run a line through the shell (expand aliases, parse, evaluate). shared by the `run`
	-- service and the function/macro handlers, so it lives outside the services table (a table
	-- constructor cant reference itself).
	local function runLine(line: string): any
		if not Karet.Evaluator then
			return { ok = false, error = "shell not ready" }
		end
		line = Alias.expand(line, Karet.Profile.Aliases)
		local parsed = Karet.Parse(line)
		if #parsed.diagnostics > 0 then
			return { ok = false, error = parsed.diagnostics[1].message }
		end
		return Karet.Evaluator:run(parsed.ast)
	end

	-- Live HUD watches (the `pin` command). Each watch evaluates an expression on an interval
	-- and pushes the value (with a sparkline for numbers) onto a row in the corner overlay.
	-- Like the jobs registry, this owns the loops so the commands stay thin.
	local function escMarkup(s: string): string
		return (string.gsub(string.gsub(string.gsub(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
	end
	local function fmtNum(n: number): string
		if n == math.floor(n) and math.abs(n) < 1e15 then
			return tostring(math.floor(n))
		end
		return string.format("%.2f", n)
	end
	local hudList: { [number]: { id: number, expr: string, label: string, cancel: () -> () } } = {}
	local nextHudId = 0
	local hudWatches = {
		add = function(expr: string, label: string?, interval: number?): number
			nextHudId += 1
			local id = nextHudId
			local name = (label and label ~= "") and label or expr
			local row = terminal:hudRow()
			local running = true
			hudList[id] = { id = id, expr = expr, label = name, cancel = function()
				running = false
			end }
			local period = math.max(0.1, interval or 0.5)
			task.spawn(function()
				local history: { number } = {}
				while running do
					local r = runLine(expr)
					local value: any = (type(r) == "table" and r.returns) and r.returns[1] or nil
					local head = `{escMarkup(name)}: `
					if type(value) == "number" then
						table.insert(history, value)
						while #history > 24 do
							table.remove(history, 1)
						end
						row.set(`{head}{fmtNum(value)} {Render.sparkline(history)}`)
					elseif value == nil then
						row.set(`{head}<i>nil</i>`)
					else
						row.set(`{head}{escMarkup(tostring(value))}`)
					end
					local t = 0
					while running and t < period do
						t += task.wait()
					end
				end
				row.remove()
				hudList[id] = nil
			end)
			return id
		end,
		remove = function(id: number): boolean
			local w = hudList[id]
			if not w then
				return false
			end
			pcall(w.cancel)
			hudList[id] = nil
			return true
		end,
		clear = function()
			for id, w in hudList do
				pcall(w.cancel)
				hudList[id] = nil
			end
		end,
		list = function()
			local out = {}
			for _, w in hudList do
				table.insert(out, w)
			end
			table.sort(out, function(a, b)
				return a.id < b.id
			end)
			return out
		end,
	}

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
			player = function()
				return Players.LocalPlayer
			end,
			editor = function()
				return Karet.Editor
			end,
			closeTerminal = function()
				terminal:close()
			end,
			history = function()
				return Karet.Profile.History
			end,
			-- shell env vars (the @name store) live on Karet.Env, shared with the evaluator
			env = {
				get = function(name)
					return Karet.Env[name]
				end,
				set = function(name, value)
					Karet.Env[name] = value
				end,
				unset = function(name)
					Karet.Env[name] = nil
				end,
				list = function()
					local names = {}
					for k in Karet.Env do
						table.insert(names, k)
					end
					table.sort(names)
					return names
				end,
			},
			openConfig = function()
				Karet.OpenConfig()
			end,
			defaults = Karet.Defaults,
			jobs = jobs,
			hud = hudWatches,
			logCapture = logCapture,
			panels = {
				list = function()
					return extensions:listPanels()
				end,
				get = function(name)
					return extensions:getPanel(name)
				end,
			},
			extensions = function()
				return extensions:listExtensions()
			end,
			-- command aliases, stored on the active profile
			aliases = {
				get = function(name)
					return Karet.Profile.Aliases[name]
				end,
				set = function(name, line)
					Karet.Profile.Aliases[name] = line
				end,
				unset = function(name)
					Karet.Profile.Aliases[name] = nil
				end,
				list = function()
					local names = {}
					for k in Karet.Profile.Aliases do
						table.insert(names, k)
					end
					table.sort(names)
					return names
				end,
			},
			-- named macros, stored on the profile. set() also registers a real command that
			-- runs the body, so functions appear in help/completion and nest inside each other.
			functions = {
				get = function(name)
					return Karet.Profile.Functions[name]
				end,
				set = function(name, body)
					Karet.Profile.Functions[name] = body
					registry:register({
						Name = name,
						Description = `function: {body}`,
						Network = "Client",
						On = { Client = function(ctx)
							local b = Karet.Profile.Functions[name]
							if b == nil then
								return
							end
							-- run the body through the shell; bubble up a failure so chains see it
							local out = runLine(b)
							if type(out) == "table" and out.ok == false and out.error then
								ctx.Abort(out.error)
							end
						end },
					})
				end,
				unset = function(name)
					Karet.Profile.Functions[name] = nil
					registry:unregister(name)
				end,
				list = function()
					local names = {}
					for k in Karet.Profile.Functions do
						table.insert(names, k)
					end
					table.sort(names)
					return names
				end,
			},
			-- re-run a line through the shell (used by `repc`/`every`/`watch`). returns the chain result.
			run = runLine,
			version = Karet.Version,
		}
		for _, def in Commands.build(services) do
			registry:register(def)
		end
		-- expose the function store so persistence-load can re-register saved macros
		Karet.Functions = services.functions
	end

	-- Live, editable settings (the @CONFIG editor writes here). Seeded from Start options.
	local cfg = {
		promptType = options.PromptType or "text",
		placement = options.Placement or "Window",
		toggle = options.Toggle,
	}

	-- Dangerous-command confirmation. "window" pops a small themed modal; "text" (default)
	-- asks y/N right on the terminal. Both yield the command's thread until answered.
	local function confirm(name: string, _def: any): boolean
		local question = `run dangerous command '{name}'?`
		if cfg.promptType == "window" then
			return terminal:promptWindow(question)
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
		ui = terminal:ui(),
		window = function(windowOpts)
			windowOpts = windowOpts or {}
			windowOpts.parent = terminal.gui.Parent
			return WindowManager.open(windowOpts)
		end,
		confirm = confirm,
	})
	local evaluator = Shell.newEvaluator(host, Karet.Env)

	terminal:onSubmit(function(line: string)
		line = Alias.expand(line, Karet.Profile.Aliases)
		local parsed = Karet.Parse(line)
		if #parsed.diagnostics > 0 then
			for _, d in parsed.diagnostics do
				terminal:error(d.message)
			end
			return
		end
		-- run the command on its OWN thread, not the input's submit thread. commands that
		-- yield (a dangerous-command prompt waiting for an answer, a progress bar's task.wait,
		-- a Server round-trip) need a thread that can suspend and resume cleanly - the submit
		-- thread can't, which is why the prompts never waited before. the input stays usable
		-- the whole time.
		task.spawn(function()
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
	end)

	-- kaveat editor, mounted beside the terminal if enabled
	if options.Kaveat then
		local editor = Kaveat.new({ Parent = terminal.gui.Parent })
		editor:mount(terminal.gui.Parent)
		-- save/open named scripts from the active profile
		editor:setStore(function()
			return Karet.Profile.Kavs
		end)
		-- ctrl+enter / :run ships the script to the server to loadstring. any print/warn the
		-- script makes is captured server-side and replayed line by line into the kav output.
		editor:setRunner(function(source, _context)
			-- ship the whole kav store alongside so the script can require() sibling kavs
			local res = networking:invokeKaveat(source, _context, Karet.Profile.Kavs)
			if type(res.lines) == "table" then
				for _, l in res.lines do
					editor:print(tostring(l.text), l.group or "Output")
				end
			end
			if res.ok then
				return res.output or "ran ok"
			end
			error(res.error or "run failed")
		end)
		Karet.Editor = editor

		-- @CONFIG editor: a live settings file. it serialises the current settings, and
		-- saving it (:w) parses key=value back and applies theme/prompt/placement live.
		local function parseConfig(src: string): { [string]: string }
			local out: { [string]: string } = {}
			for line in (src .. "\n"):gmatch("(.-)\n") do
				line = string.gsub(line, "#.*$", "")
				local k, v = string.match(line, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
				if k then
					out[string.lower(k)] = v
				end
			end
			return out
		end
		local function serializeConfig(): string
			return table.concat({
				"# karet @CONFIG  -  edit values then :w to apply",
				"# format:  Key = value   (# starts a comment)",
				"",
				"Theme     = " .. (Karet.Theme.Name() or "tokyonight"),
				"Prompt    = " .. cfg.promptType .. "        # text | window",
				"Placement = " .. cfg.placement .. "        # Window | Top | Bottom",
				"Toggle    = " .. tostring(cfg.toggle or "Semicolon"),
			}, "\n")
		end
		local function applyConfig(src: string): { string }
			local kv = parseConfig(src)
			local out = {}
			if kv.theme and kv.theme ~= "" and kv.theme ~= Karet.Theme.Name() then
				if pcall(Karet.Theme.Set, kv.theme) then
					Karet.Profile.CurrentTheme = kv.theme
					table.insert(out, "Theme -> " .. kv.theme)
				else
					table.insert(out, "! unknown theme '" .. kv.theme .. "'")
				end
			end
			if kv.prompt == "text" or kv.prompt == "window" then
				if kv.prompt ~= cfg.promptType then
					cfg.promptType = kv.prompt
					table.insert(out, "Prompt -> " .. kv.prompt)
				end
			elseif kv.prompt then
				table.insert(out, "! Prompt must be text | window")
			end
			if kv.placement and kv.placement ~= cfg.placement then
				if terminal:setPlacement(kv.placement) then
					cfg.placement = kv.placement
					table.insert(out, "Placement -> " .. kv.placement)
				else
					table.insert(out, "! bad placement '" .. kv.placement .. "'")
				end
			end
			if kv.toggle and kv.toggle ~= "" and kv.toggle ~= tostring(cfg.toggle) then
				cfg.toggle = kv.toggle
				table.insert(out, "Toggle -> " .. kv.toggle .. " (restart to apply)")
			end
			if #out == 0 then
				table.insert(out, "nothing changed")
			end
			return out
		end
		Karet._openConfig = function()
			terminal:close()
			editor:openConfig(serializeConfig(), applyConfig)
		end
	end

	-- profile persistence (client side). load the saved shell state on join, then push saves
	-- on an interval. fields are filled IN PLACE so existing references (input.history bound to
	-- Profile.History, the evaluator's @env scope, the kav store) keep pointing at live data.
	if options.Persist ~= false then
		local function fillArray(dst, src)
			if type(src) == "table" then
				table.clear(dst)
				for _, v in src do
					table.insert(dst, v)
				end
			end
		end
		local function fillMap(dst, src)
			if type(src) == "table" then
				table.clear(dst)
				for k, v in src do
					dst[k] = v
				end
			end
		end
		task.spawn(function()
			local res = networking:syncProfile({ action = "load" })
			if res and res.ok and res.data then
				local d = res.data
				fillArray(Karet.Profile.History, d.History)
				fillMap(Karet.Profile.Kavs, d.Kavs)
				fillMap(Karet.Profile.Aliases, d.Aliases)
				-- re-register saved functions as runnable commands
				if type(d.Functions) == "table" and Karet.Functions then
					for name, body in d.Functions do
						if type(name) == "string" and type(body) == "string" then
							Karet.Functions.set(name, body)
						end
					end
				end
				if type(d.Vars) == "table" then
					for k, v in d.Vars do
						Karet.Env[k] = v
					end
				end
				if type(d.Theme) == "string" and d.Theme ~= "" then
					pcall(Karet.Theme.Set, d.Theme)
					Karet.Profile.CurrentTheme = d.Theme
				end
			end
		end)
		task.spawn(function()
			while true do
				task.wait(60)
				networking:syncProfile({ action = "save", data = {
					History = Karet.Profile.History,
					Kavs = Karet.Profile.Kavs,
					Aliases = Karet.Profile.Aliases,
					Functions = Karet.Profile.Functions,
					Vars = Karet.Env,
					Theme = Karet.Theme.Name() or Karet.Profile.CurrentTheme,
				} })
			end
		end)
	end

	-- the built-in Devtools extension (profiler + inspector), registered through the platform
	pcall(function()
		require(script.Devtools).register(Karet)
	end)

	-- moderation suite (client): register the command shapes so they parse + ship to the
	-- server (which holds the real handlers), plus the dashboard panel.
	if options.Admin then
		Karet.RegisterExtension({
			Name = "Admin",
			Description = "moderation: kick / ban / mute / audit + dashboard",
			Commands = Admin.defs(nil),
			Panels = { Admin.dashboardPanel(Karet) },
		})
	end

	-- built-in panels (client only), so `panels` / `open` show something out of the box and
	-- demonstrate the platform other tools register through.
	Karet.RegisterPanel({
		Name = "themes",
		Description = "quick theme switcher",
		Open = function(ctx)
			local w = ctx.Window({ title = "themes" })
			w:Label("pick a theme")
			for _, name in Karet.Theme.List() do
				w:Button(name, function()
					Karet.Theme.Set(name)
					Karet.Profile.CurrentTheme = name
				end)
			end
			w:Separator()
			w:Button("close", function()
				w:Close()
			end)
		end,
	})
	-- the full live colour editor (open theme)
	Karet.RegisterPanel(ThemeEditor.panel(Karet))

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

	-- profile persistence (server side). Pik is required lazily so the DataStore-touching
	-- ProfileStore never loads unless persistence is actually on. one KaretProfile schema
	-- holds the saved shell state; the client loads it on join and pushes saves periodically.
	if options.Persist ~= false then
		local ok, Pik = pcall(require, script.Pik)
		if ok and Pik then
			Pik.Configure({ AutoSave = true, AutoSaveInterval = 120, Reconcile = true, LogLevel = "Warn" })
			Pik.SetSchema("KaretProfile", {
				History = {},
				Vars = {},
				Kavs = {},
				Theme = "",
				Aliases = {},
				Functions = {},
			})
			-- persistence is on by default now, so in studio with API access off this would warn on
			-- every join. say it once and stay quiet (almost always "studio access to apis is off").
			local warnedSession = false
			local function startSession(player: Player)
				Pik.StartPlayerSession(player).catch(function(err)
					if not warnedSession then
						warnedSession = true
						warn(`karet: profile autosave unavailable - {tostring(err)} (pass Persist = false to Start to silence)`)
					end
				end)
			end
			Players.PlayerAdded:Connect(startSession)
			for _, player in Players:GetPlayers() do
				startSession(player)
			end
			-- the saved fields the client is allowed to read/write
			local FIELDS = { "History", "Vars", "Kavs", "Theme", "Aliases", "Functions" }
			networking:listenProfile(function(payload, player)
				local stores = Pik.WaitForSession(player)
				local handle = stores and stores.KaretProfile
				if not handle then
					return { ok = false, error = "no profile session" }
				end
				if payload.action == "load" then
					local data = {}
					for _, f in FIELDS do
						data[f] = handle:Get(f)
					end
					return { ok = true, data = data }
				elseif payload.action == "save" then
					local incoming = payload.data or {}
					for _, f in FIELDS do
						if incoming[f] ~= nil then
							handle:Set(f, incoming[f])
						end
					end
					return { ok = true }
				end
				return { ok = false, error = "unknown profile action" }
			end)
		else
			warn("karet: Persist is on but Pik failed to load - " .. tostring(Pik))
		end
	end

	-- moderation suite (server): stand up the backend and register the role-gated commands so
	-- the server actually executes them (the client registers no-op shapes that ship here).
	if options.Admin then
		local backend = Admin.serverSetup(options)
		Karet._adminBackend = backend
		for _, def in Admin.defs(backend) do
			registry:register(def)
		end
	end

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
	local realRequire = require
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
		-- capture the script's print/warn so they replay in the kav output pane. everything
		-- else (game, workspace, string, ...) falls through to the real environment.
		local lines = {}
		local function capture(group: string)
			return function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					parts[i] = tostring((select(i, ...)))
				end
				table.insert(lines, { text = table.concat(parts, "\t"), group = group })
			end
		end

		-- kav module system: require("other") loads a sibling kav (from the map the client sent)
		-- in this same sandbox, caching its return and guarding against cycles. a non-string
		-- argument (a ModuleScript / asset id) falls through to the real require.
		local modules = type(payload.modules) == "table" and payload.modules or {}
		local env: any
		local moduleRequire = KavModules.newRequire(modules, function(source: string, name: string)
			local mfn, merr = loadstring(source)
			if not mfn then
				error(`compile error in kav '{name}': {tostring(merr)}`, 0)
			end
			pcall(setfenv, mfn, env)
			return mfn()
		end)
		local function envRequire(arg: any): any
			if type(arg) == "string" then
				return moduleRequire(arg)
			end
			return realRequire(arg)
		end
		env = setmetatable(
			{ print = capture("Output"), warn = capture("Warn"), require = envRequire },
			{ __index = getfenv() }
		)

		pcall(setfenv, fn, env)
		local okr, result = pcall(fn)
		if not okr then
			table.insert(lines, { text = tostring(result), group = "Error" })
			return { ok = false, error = tostring(result), lines = lines }
		end
		return { ok = true, output = result ~= nil and tostring(result) or "ran ok", lines = lines }
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

--[=[
	@within Karet
	@function Start
	@tag Setup
	@param opts StartConfig?
	@return Terminal?
	Boot Karet. On the client this builds and wires the terminal and the command evaluator and
	returns the [Terminal]; on the server it stands up the networking listener and the auth
	pipeline and returns `nil`. The same call works in both realms.

	```lua
	Karet.Start({ Toggle = "Semicolon", Theme = "tokyonight", Kaveat = true })
	```
]=]
-- Auto-load commands from Start{ Commands = ... }. Accepts a Folder (require every descendant
-- ModuleScript), a list of ModuleScripts, or a list of ready-made def tables. A command module is
-- expected to call Karet.Command(...) at scope, so simply requiring it registers the command; a
-- plain def table (carrying Name) is registered directly. One bad module/def warns and doesn't
-- abort the rest. Called from Start on each realm, so Server-network commands register everywhere.
local function loadCommands(source: any)
	if source == nil then
		return
	end

	local function requireModule(module: Instance)
		local ok, err = pcall(require, module :: any)
		if not ok then
			warn(`karet: failed to load command module '{module:GetFullName()}' - {tostring(err)}`)
		end
	end

	-- a Roblox container: require every ModuleScript in it (or itself, if it is one)
	if typeof(source) == "Instance" then
		if source:IsA("ModuleScript") then
			requireModule(source)
		else
			for _, descendant in source:GetDescendants() do
				if descendant:IsA("ModuleScript") then
					requireModule(descendant)
				end
			end
		end
		return
	end

	-- a list: each entry is a ModuleScript to require or a ready-made def to register
	if type(source) == "table" then
		local defs = {}
		for _, entry in source do
			if typeof(entry) == "Instance" then
				if entry:IsA("ModuleScript") then
					requireModule(entry)
				end
			elseif type(entry) == "table" then
				table.insert(defs, entry)
			end
		end
		if #defs > 0 then
			local _, errors = registry:registerMany(defs)
			for _, fail in errors do
				warn(`karet: failed to register command '{fail.name}' - {fail.error}`)
			end
		end
	end
end

function Karet.Start(opts: StartConfig?): Terminal.Terminal?
	local options: StartConfig = opts or {}
	-- register user command modules on both realms before booting the realm-specific surface
	loadCommands(options.Commands)
	if RunService:IsClient() then
		return startClient(options)
	end
	return startServer(options)
end

return Karet
