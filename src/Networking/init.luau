-- The client/server transport for Karet commands, over Substance.
--
-- Only Server and Context commands cross the boundary; Shared/Client run entirely on the
-- client (the Host handles those without ever calling here). The contract:
--   • client `invoke(request)`  -> yields, returns the server's { ok, returns?, error? }
--   • server `listen(runner)`   -> runs `runner(request, player)` per incoming invocation
--
-- Substance is schema-first, so we Define an Atom for the request shape, give it a Solve
-- (RemoteFunction) identity with :Compose, then :Post (client) / :Subscribe (server). Both
-- realms construct Networking, so both register the same Atom. Payloads are intentionally
-- loose (DESIGN open-decision #1): args/attributes/payload are Type.any() - the server
-- re-validates authoritatively in the Host before running anything. The Solve subscriber's
-- return value becomes the client Reaction's result.
--
-- NOTE: Substance isn't resolvable in the headless test environment, so this module is
-- verified in-engine, not by the lune suite. Every Substance call is guarded; if the
-- dependency is missing, invoke() fails closed with a clear error instead of crashing.

local deps = require(script.Parent.deps)

local Networking = {}
Networking.__index = Networking

local ATOM = "KaretCommandRequest"
local CHANNEL = "KaretCommand"
local KAVEAT_ATOM = "KaretKaveatRun"
local KAVEAT_CHANNEL = "KaretKaveat"

export type Request = {
	name: string, -- command name
	args: { [string]: any }?, -- resolved (still-to-be-revalidated) args
	flags: { [string]: boolean }?, -- boolean flag set (-s)
	modifiers: { [string]: any }?, -- valued long options (--name=value)
	payload: any, -- Context command's committed payload, if any
	rawInput: string?, -- the original line, for audit/re-parse
}

export type Result = { ok: boolean, returns: { any }?, error: string? }

function Networking.new()
	local self = setmetatable({}, Networking)
	self.substance = deps.Substance()
	self.atom = nil :: any
	self.ready = false
	self.runner = nil :: ((Request, any) -> Result)?

	if self.substance then
		-- Define the request Atom + give it a two-way Solve channel. Loose payload fields;
		-- the Host re-validates. Wrapped so a Substance hiccup degrades instead of crashing.
		local ok, atomOrErr = pcall(function()
			local Type = self.substance.Type
			local atom = self.substance.Define(ATOM, {
				name = Type.string(),
				args = Type.any():nullable(),
				flags = Type.any():nullable(),
				modifiers = Type.any():nullable(),
				payload = Type.any():nullable(),
				rawInput = Type.string():nullable(),
			})
			atom:Compose(CHANNEL, "Solve")
			return atom
		end)
		if ok then
			self.atom = atomOrErr
			self.ready = true
		else
			warn(`Karet.Networking: failed to define channel - {atomOrErr}`)
		end

		-- separate channel for running kaveat scripts
		local ok2, kav = pcall(function()
			local Type = self.substance.Type
			local atom = self.substance.Define(KAVEAT_ATOM, {
				source = Type.string(),
				context = Type.string():nullable(),
			})
			atom:Compose(KAVEAT_CHANNEL, "Solve")
			return atom
		end)
		if ok2 then
			self.kaveatAtom = kav
		else
			warn(`Karet.Networking: failed to define kaveat channel - {kav}`)
		end
	end

	return self
end

-- CLIENT: send a command request to the server and yield for its result.
function Networking:invoke(request: Request): Result
	if not (self.ready and self.atom) then
		return { ok = false, error = "Karet networking unavailable (Substance not installed?)" }
	end
	local ok, result = pcall(function()
		return self.atom:Post(request):Await()
	end)
	if not ok then
		return { ok = false, error = `network error: {result}` }
	end
	if type(result) ~= "table" then
		return { ok = false, error = "malformed server response" }
	end
	return result
end

-- SERVER: register the function that authoritatively runs an incoming request. The handler
-- receives (request, callingPlayer) and must return a Result; that Result is what the Solve
-- channel returns to the calling client.
function Networking:listen(runner: (Request, any) -> Result)
	self.runner = runner
	if not (self.ready and self.atom) then
		warn("Karet.Networking: cannot listen - Substance unavailable")
		return
	end
	self.atom:Subscribe(function(request: Request, player: any): Result
		if not self.runner then
			return { ok = false, error = "Karet server not ready" }
		end
		local ok, result = pcall(self.runner, request, player)
		if not ok then
			return { ok = false, error = tostring(result) }
		end
		return result
	end)
end

-- CLIENT: ship a kaveat script to the server to run, yield for the result.
function Networking:invokeKaveat(source: string, context: string?): any
	if not self.kaveatAtom then
		return { ok = false, error = "kaveat networking unavailable (Substance not installed?)" }
	end
	local ok, result = pcall(function()
		return self.kaveatAtom:Post({ source = source, context = context }):Await()
	end)
	if not ok then
		return { ok = false, error = `network error: {result}` }
	end
	if type(result) ~= "table" then
		return { ok = false, error = "malformed server response" }
	end
	return result
end

-- SERVER: handle incoming kaveat run requests. runner(payload, player) -> result.
function Networking:listenKaveat(runner: (any, any) -> any)
	if not self.kaveatAtom then
		warn("Karet.Networking: cannot listen for kaveat - Substance unavailable")
		return
	end
	self.kaveatAtom:Subscribe(function(payload: any, player: any): any
		local ok, result = pcall(runner, payload, player)
		if not ok then
			return { ok = false, error = tostring(result) }
		end
		return result
	end)
end

return Networking
