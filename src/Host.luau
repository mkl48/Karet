-- The Host: the bridge between the pure shell Evaluator and Karet's command framework.
--
-- The Evaluator dot-calls four functions on whatever host it's given —
-- getCommand / coerce / satisfies / run — so this module returns a *table of closures*
-- (not an OO object) capturing the registry, type system, realm, output sink, auth, and
-- middleware. `run` is the realm dispatcher:
--
--   Shared / Client  -> execute the handler locally (client) right here.
--   Server           -> ship the request to the server over Networking, yield for result.
--   Context          -> run On.Client locally to build a payload (ctx.Commit), then ship.
--
-- On the server, the Networking listener calls `runServerRequest`, which re-validates the
-- arguments authoritatively, checks auth, and runs On.Server — the client is never trusted.

local Context = require(script.Parent.Context)

local Host = {}

-- Default role ordering for Permission checks; override via auth.roleRanks.
local DEFAULT_RANKS = { User = 1, Admin = 2, Owner = 3 }

export type Auth = {
	roleHook: ((player: any) -> string)?,
	authHook: ((player: any, command: string) -> boolean?)?,
	groupHook: ((player: any) -> number)?,
	allowed: { [number]: boolean }?,
	denied: { [number]: boolean }?,
	roleRanks: { [string]: number }?,
	defaultRole: string?,
}

export type Hooks = {
	pre: { (ctx: any) -> any? },
	post: { (ctx: any, result: any) -> () },
	onErr: { (ctx: any, err: any) -> () },
}

export type Options = {
	registry: any,
	types: any,
	isServer: boolean?,
	isClient: boolean?,
	player: any?,
	sink: ((group: string, message: string) -> ())?,
	hooks: Hooks?,
	auth: Auth?,
	networking: any?,
}

function Host.new(opts: Options)
	local registry = opts.registry
	local types = opts.types
	local hooks: Hooks = opts.hooks or { pre = {}, post = {}, onErr = {} }
	local auth: Auth = opts.auth or {}
	local networking = opts.networking
	local cache = opts.cache
	local query = opts.query
	local isServer = opts.isServer == true
	local isClient = opts.isClient == true

	-- Output routing: the client writes straight to the provided sink (the terminal). The
	-- server buffers a command's output per-request so it can ride back inside the Result
	-- and be replayed on the caller's screen — there's no always-on server->client console
	-- channel yet.
	local clientSink = opts.sink or function() end
	local currentOutput: { { group: string, message: string } }? = nil
	local function sink(group: string, message: string)
		if isServer then
			if currentOutput then
				table.insert(currentOutput, { group = group, message = message })
			end
		else
			clientSink(group, message)
		end
	end

	-- Send a request to the server and replay any buffered server output locally.
	local function invokeAndReplay(request: any): any
		local result = networking:invoke(request)
		if type(result) == "table" and result.output then
			for _, line in result.output do
				clientSink(line.group, line.message)
			end
		end
		return result
	end

	-- Mutable per-evaluation session, updated by the caller (terminal / server listener).
	local session = { player = opts.player, rawInput = nil :: string? }

	local function roleRank(role: string): number?
		return (auth.roleRanks or DEFAULT_RANKS)[role]
	end

	local function roleInfoFor(player: any): { role: string?, rank: number? }
		if not player then
			return { role = auth.defaultRole, rank = nil }
		end
		local role = (auth.roleHook and auth.roleHook(player)) or auth.defaultRole
		local rank = auth.groupHook and auth.groupHook(player) or nil
		return { role = role, rank = rank }
	end

	-- Server-authoritative permission gate.
	local function checkAuth(name: string, def: any, player: any): (boolean, string?)
		if player == nil then
			return true -- no player context (Studio / local server invocation)
		end
		local uid = player.UserId
		if auth.denied and auth.denied[uid] then
			return false, "you are denied"
		end
		if auth.allowed and auth.allowed[uid] then
			return true
		end
		if def.Permission then
			local role = (auth.roleHook and auth.roleHook(player)) or auth.defaultRole or "User"
			local need, have = roleRank(def.Permission), roleRank(role)
			if need and have then
				if have < need then
					return false, `requires {def.Permission}`
				end
			elseif role ~= def.Permission then
				return false, `requires {def.Permission}`
			end
		end
		if auth.authHook then
			if auth.authHook(player, name) == false then
				return false, "not authorized"
			end
		end
		return true
	end

	-- Build ctx, run middleware + the handler, collect returns. Returns (result, control).
	local function executeLocal(name, def, handlerFn, args, attributes, payload, roleInfo)
		local ctx, control = Context.new({
			player = session.player,
			command = name,
			rawInput = session.rawInput,
			args = args,
			attributes = attributes,
			isServer = isServer,
			isClient = isClient,
			role = roleInfo and roleInfo.role,
			rank = roleInfo and roleInfo.rank,
			sink = sink,
			cache = cache,
			query = query,
		})

		for _, pre in hooks.pre do
			if pre(ctx) == false then
				return { ok = false, error = "cancelled by middleware" }, control
			end
		end

		local ok, err = pcall(handlerFn, ctx, payload)
		if not ok then
			if Context.isAbort(err) then
				return { ok = false, error = Context.abortMessage(err) }, control
			end
			for _, h in hooks.onErr do
				pcall(h, ctx, err)
			end
			return { ok = false, error = tostring(err) }, control
		end

		local result = { ok = true, returns = control.returns() }
		for _, post in hooks.post do
			pcall(post, ctx, result)
		end
		return result, control
	end

	local host: any = {}
	host.session = session

	function host.getCommand(name: string): any?
		return registry:get(name)
	end

	function host.coerce(raw: any, typeNames: { string }): (any, string?)
		return types:coerce(raw, typeNames)
	end

	function host.satisfies(value: any, typeName: string): boolean
		return types:satisfies(value, typeName)
	end

	-- Evaluator entry: dispatch one command by Network type + realm.
	function host.run(invocation: any): any
		local name, def = invocation.name, invocation.definition
		local network = def.Network or "Shared"
		local On = def.On or {}

		if isServer then
			local authed, why = checkAuth(name, def, session.player)
			if not authed then
				return { ok = false, error = why }
			end
			local fn = On.Server or On.Shared
			if not fn then
				return { ok = false, error = `'{name}' has no server handler` }
			end
			local result = executeLocal(name, def, fn, invocation.args, invocation.attributes, nil, roleInfoFor(session.player))
			return result
		end

		-- client realm
		if network == "Shared" or network == "Client" then
			local fn = (network == "Client" and On.Client) or On.Shared or On.Client
			if not fn then
				return { ok = false, error = `'{name}' has no {network} handler` }
			end
			local result = executeLocal(name, def, fn, invocation.args, invocation.attributes, nil, roleInfoFor(session.player))
			return result
		elseif network == "Server" then
			if not networking then
				return { ok = false, error = "no networking configured" }
			end
			return invokeAndReplay({
				name = name,
				args = invocation.args,
				attributes = invocation.attributes,
				payload = nil,
				rawInput = session.rawInput,
			})
		elseif network == "Context" then
			local fn = On.Client
			if not fn then
				return { ok = false, error = `'{name}' has no client handler` }
			end
			local result, control = executeLocal(name, def, fn, invocation.args, invocation.attributes, nil, roleInfoFor(session.player))
			if not result.ok then
				return result
			end
			if not networking then
				return { ok = false, error = "no networking configured" }
			end
			return invokeAndReplay({
				name = name,
				args = invocation.args,
				attributes = invocation.attributes,
				payload = control.committed(),
				rawInput = session.rawInput,
			})
		end

		return { ok = false, error = `unknown Network '{network}'` }
	end

	-- Server Networking entry: authoritatively re-validate + run an incoming request.
	function host.runServerRequest(request: any, player: any): any
		local def = registry:get(request.name)
		if not def then
			return { ok = false, error = `unknown command '{request.name}'` }
		end
		local authed, why = checkAuth(request.name, def, player)
		if not authed then
			return { ok = false, error = why }
		end

		-- Never trust client-supplied args; re-coerce against the schema.
		local typedArgs: { [string]: any } = {}
		for _, spec in def.Args or {} do
			local raw = request.args and request.args[spec.Name]
			if raw == nil then
				if spec.Required then
					return { ok = false, error = `missing required argument '{spec.Name}'` }
				end
				typedArgs[spec.Name] = spec.Default
			else
				local typed, terr = types:coerce(raw, spec.Types)
				if terr then
					return { ok = false, error = `argument '{spec.Name}': {terr}` }
				end
				typedArgs[spec.Name] = typed
			end
		end

		local fn = (def.On or {}).Server or (def.On or {}).Shared
		if not fn then
			return { ok = false, error = `'{request.name}' has no server handler` }
		end

		local prevPlayer, prevRaw, prevOut = session.player, session.rawInput, currentOutput
		session.player, session.rawInput, currentOutput = player, request.rawInput, {}
		local result = executeLocal(request.name, def, fn, typedArgs, request.attributes or {}, request.payload, roleInfoFor(player))
		result.output = currentOutput
		session.player, session.rawInput, currentOutput = prevPlayer, prevRaw, prevOut
		return result
	end

	return host
end

return Host
