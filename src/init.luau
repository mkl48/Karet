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
local Render = require(script.Render)

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

-- The rich-output toolkit (panels, tables, trees, charts, ...). Pure string builders, also
-- handed to handlers as ctx.UI. Karet.Render.table{...} etc. work anywhere.
Karet.Render = Render

-- Global key/value cache + named-query service, also reachable from handlers as
-- ctx.Cache / ctx.Query. One instance per realm.
Karet.Cache = cache
Karet.Query = query

-- Shell environment variables - the @name store the shell reads/writes. This IS the
-- evaluator's variable scope (shared), so defaults set here, the `set` command, and
-- `(x = ...)` assignments all see the same table. Seed defaults before Karet.Start.
Karet.Env = {} :: { [string]: any }

function Karet.SetVar(name: string, value: any)
	Karet.Env[name] = value
end

function Karet.GetVar(name: string): any
	return Karet.Env[name]
end

-- a couple handy defaults; users add their own with Karet.SetVar or the `set` command
Karet.Env.pi = math.pi
Karet.Env.version = Karet.Version

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
	terminal.input:setCompleter(Complete.build(registry, types, function()
		local names = {}
		for k in Karet.Env do
			table.insert(names, k)
		end
		table.sort(names)
		return names
	end))
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
			version = Karet.Version,
		}
		for _, def in Commands.build(services) do
			registry:register(def)
		end
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
		confirm = confirm,
	})
	local evaluator = Shell.newEvaluator(host, Karet.Env)

	terminal:onSubmit(function(line: string)
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
			local res = networking:invokeKaveat(source, _context)
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
				"# format:  key = value   (# starts a comment)",
				"",
				"theme     = " .. (Karet.Theme.Name() or "tokyonight"),
				"prompt    = " .. cfg.promptType .. "        # text | window",
				"placement = " .. cfg.placement .. "        # Window | Top | Bottom",
				"toggle    = " .. tostring(cfg.toggle or "Semicolon"),
			}, "\n")
		end
		local function applyConfig(src: string): { string }
			local kv = parseConfig(src)
			local out = {}
			if kv.theme and kv.theme ~= "" and kv.theme ~= Karet.Theme.Name() then
				if pcall(Karet.Theme.Set, kv.theme) then
					Karet.Profile.CurrentTheme = kv.theme
					table.insert(out, "theme -> " .. kv.theme)
				else
					table.insert(out, "! unknown theme '" .. kv.theme .. "'")
				end
			end
			if kv.prompt == "text" or kv.prompt == "window" then
				if kv.prompt ~= cfg.promptType then
					cfg.promptType = kv.prompt
					table.insert(out, "prompt -> " .. kv.prompt)
				end
			elseif kv.prompt then
				table.insert(out, "! prompt must be text | window")
			end
			if kv.placement and kv.placement ~= cfg.placement then
				if terminal:setPlacement(kv.placement) then
					cfg.placement = kv.placement
					table.insert(out, "placement -> " .. kv.placement)
				else
					table.insert(out, "! bad placement '" .. kv.placement .. "'")
				end
			end
			if kv.toggle and kv.toggle ~= "" and kv.toggle ~= tostring(cfg.toggle) then
				cfg.toggle = kv.toggle
				table.insert(out, "toggle -> " .. kv.toggle .. " (restart to apply)")
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
		local okEnv = pcall(function()
			setfenv(fn, setmetatable({ print = capture("Output"), warn = capture("Warn") }, { __index = getfenv() }))
		end)
		local okr, result = pcall(fn)
		if not okr then
			table.insert(lines, { text = tostring(result), group = "Error" })
			return { ok = false, error = tostring(result), lines = lines }
		end
		local _ = okEnv
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
