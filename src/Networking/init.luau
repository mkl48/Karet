-- The client/server transport for Karet commands, over Substance.
--
-- Only Server and Context commands cross the boundary; Shared/Client run entirely on the
-- client (the Host handles those without ever calling here). The contract:
--   • client `invoke(request)`  -> yields, returns the server's { ok, returns?, error? }
--   • server `listen(runner)`   -> runs `runner(request, player)` per incoming invocation
--
-- A single Solve channel (RemoteFunction semantics) carries the request and the result.
-- Payloads are loose tables (DESIGN open-decision #1: loose by default) — the server
-- re-validates authoritatively in the Host before running anything.
--
-- NOTE: Substance isn't resolvable in the headless test environment, so this module is
-- verified in-engine, not by the lune suite. Every Substance call is guarded; if the
-- dependency is missing, invoke() fails closed with a clear error instead of crashing.

local deps = require(script.Parent.deps)

local Networking = {}
Networking.__index = Networking

local CHANNEL = "KaretCommand"

export type Request = {
	name: string, -- command name
	args: { [string]: any }, -- resolved (still-to-be-revalidated) args
	attributes: { [string]: boolean }, -- flag set
	payload: any, -- Context command's committed payload, if any
	rawInput: string?, -- the original line, for audit/re-parse
}

export type Result = { ok: boolean, returns: { any }?, error: string? }

function Networking.new()
	local self = setmetatable({}, Networking)
	self.substance = deps.Substance()
	self.ready = false
	self.runner = nil :: ((Request, any) -> Result)?

	if self.substance then
		-- Define the command channel once. Loose schema; the Host re-validates.
		local ok, err = pcall(function()
			self.substance.Compose(CHANNEL, {}, "Solve")
		end)
		self.ready = ok
		if not ok then
			warn(`Karet.Networking: failed to compose channel — {err}`)
		end
	end

	return self
end

-- CLIENT: send a command request to the server and yield for its result.
function Networking:invoke(request: Request): Result
	if not (self.substance and self.ready) then
		return { ok = false, error = "Karet networking unavailable (Substance not installed?)" }
	end
	local ok, result = pcall(function()
		return self.substance.Post(CHANNEL, request):Await()
	end)
	if not ok then
		return { ok = false, error = `network error: {result}` }
	end
	if type(result) ~= "table" then
		return { ok = false, error = "malformed server response" }
	end
	return result
end

-- SERVER: register the function that authoritatively runs an incoming request. The
-- handler receives (request, callingPlayer) and must return a Result.
function Networking:listen(runner: (Request, any) -> Result)
	self.runner = runner
	if not (self.substance and self.ready) then
		warn("Karet.Networking: cannot listen — Substance unavailable")
		return
	end
	self.substance.Subscribe(CHANNEL, function(request: Request, player: any): Result
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

return Networking
