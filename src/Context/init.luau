-- Builds the `ctx` object passed to every command handler (DESIGN → ctx reference).
--
-- Context.new(opts) returns (ctx, control): `ctx` is the handler-facing surface; `control`
-- is the private side the Host reads back (collected returns, an abort message, a Context
-- command's committed payload). Output (Print/Warn/Err/Reply) routes through opts.sink,
-- which the terminal/console provides. ctx.Abort cancels mid-handler by raising a tagged
-- error the Host catches - so it unwinds the handler cleanly without a magic return value.

local Context = {}

-- A unique tag so the Host can tell an intentional Abort from a real Lua error.
local ABORT = "__KaretAbort"

export type Options = {
	player: any?, -- Player or nil (Studio/no-player)
	command: string,
	rawInput: string?,
	args: { [string]: any },
	attributes: { [string]: boolean },
	isServer: boolean,
	isClient: boolean,
	role: string?,
	rank: number?,
	sink: (group: string, message: string) -> (), -- group = a Karet.Theme group name
	cache: any?, -- the global Karet.Cache
	query: any?, -- the global Karet.Query
}

export type Control = {
	returns: () -> { any },
	committed: () -> any,
	abortMessage: () -> string?,
}

-- The handler-facing ctx surface (typed so editors autocomplete ctx.* in your handlers).
export type Context = {
	Player: Player?,
	Command: string,
	RawInput: string?,
	Args: { [string]: any },
	Attributes: { [string]: boolean },
	IsServer: boolean,
	IsClient: boolean,
	ExecutedAt: number,
	Role: string?,
	Rank: number?,
	Cache: any, -- Karet.Cache
	Query: any, -- Karet.Query
	Print: (message: any) -> (),
	Warn: (message: any) -> (),
	Err: (message: any) -> (),
	Info: (message: any) -> (),
	Reply: (message: any) -> (),
	Return: (...any) -> (),
	Commit: (payload: any) -> (),
	Abort: (message: string?) -> (),
}

function Context.isAbort(err: any): boolean
	return type(err) == "table" and err[ABORT] == true
end

function Context.abortMessage(err: any): string
	return (type(err) == "table" and err.message) or tostring(err)
end

function Context.new(opts: Options): (any, Control)
	-- table.pack preserves embedded nils so ctx.Return(a, nil, c) records three slots.
	local returns = { n = 0 }
	local committedPayload: any = nil
	local abortMsg: string? = nil

	local ctx = {
		Player = opts.player,
		Command = opts.command,
		RawInput = opts.rawInput,
		Args = opts.args,
		Attributes = opts.attributes,
		IsServer = opts.isServer,
		IsClient = opts.isClient,
		ExecutedAt = os.clock(),
		Role = opts.role,
		Rank = opts.rank,
		Cache = opts.cache, -- global key/value cache (ctx.Cache:Get/Set/...)
		Query = opts.query, -- named-query service (ctx.Query:Run("players"))
	}

	function ctx.Print(message: any)
		opts.sink("Output", tostring(message))
	end

	function ctx.Warn(message: any)
		opts.sink("Warn", tostring(message))
	end

	function ctx.Err(message: any)
		opts.sink("Error", tostring(message))
	end

	function ctx.Info(message: any)
		opts.sink("Info", tostring(message))
	end

	-- Reply is Print's semantic twin (a direct answer to the caller).
	function ctx.Reply(message: any)
		opts.sink("Output", tostring(message))
	end

	-- Push return values, matched positionally to the command's Returns schema by the
	-- evaluator/pool. Nils are preserved as real slots.
	function ctx.Return(...)
		local packed = table.pack(...)
		for i = 1, packed.n do
			returns.n += 1
			returns[returns.n] = packed[i]
		end
	end

	-- Context (bridge) command only: hand a payload from On.Client to On.Server.
	function ctx.Commit(payload: any)
		committedPayload = payload
	end

	-- Cancel mid-handler with a message.
	function ctx.Abort(message: string?)
		abortMsg = message or "aborted"
		error({ [ABORT] = true, message = abortMsg }, 0)
	end

	local control: Control = {
		returns = function()
			local out = {}
			for i = 1, returns.n do
				out[i] = returns[i]
			end
			return out
		end,
		committed = function()
			return committedPayload
		end,
		abortMessage = function()
			return abortMsg
		end,
	}

	return ctx, control
end

return Context
