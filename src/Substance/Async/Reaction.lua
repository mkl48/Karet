-- Substance
-- Async/Reaction.lua
-- Plinko Labs

local Promise = require(script.Parent.Promise)
local Branch = require(script.Parent.Branch)

export type Reaction = {
	Next: (self: Reaction, fn: (any) -> any) -> Reaction,
	Throw: (self: Reaction, fn: (string) -> any) -> Reaction,
	Conclusion: (self: Reaction, fn: () -> ()) -> Reaction,
	Await: (self: Reaction) -> any,
	Timeout: (self: Reaction, seconds: number) -> Reaction,
	Retry: (self: Reaction, attempts: number) -> Reaction,
	Decay: (self: Reaction, seconds: number) -> Reaction,
	Cancel: (self: Reaction) -> (),
	Branch: (self: Reaction, table: Branch.BranchTable) -> Reaction,
}

local Reaction = {}
Reaction.__index = Reaction

function Reaction.new(attempt: () -> any): Reaction
	local self = setmetatable({}, Reaction)

	self._attempt = attempt
	self._retriesLeft = 0
	self._cancelled = false
	self._consumed = false
	self._reject = nil
	self._timeoutThread = nil
	self._decayThread = nil

	self._promise = self:_dispatch()

	self._promise:finally(function()
		if self._timeoutThread then
			task.cancel(self._timeoutThread)
			self._timeoutThread = nil
		end
		if self._decayThread then
			task.cancel(self._decayThread)
			self._decayThread = nil
		end
	end)

	return (self :: any) :: Reaction
end

function Reaction:_dispatch()
	return Promise.new(function(resolve, reject)
		self._reject = reject

		local ok, result = pcall(self._attempt)

		if self._cancelled then
			reject("cancelled")
			return
		end

		if ok then
			resolve(result)
			return
		end

		if self._retriesLeft > 0 then
			self._retriesLeft -= 1
			self:_dispatch():andThen(resolve, reject)
			return
		end

		reject(result)
	end)
end

function Reaction:Next(fn: (any) -> any): Reaction
	self._consumed = true
	self._promise:andThen(fn)
	return self
end

function Reaction:Throw(fn: (string) -> any): Reaction
	self._consumed = true
	self._promise:catch(fn)
	return self
end

function Reaction:Conclusion(fn: () -> ()): Reaction
	self._promise:finally(fn)
	return self
end

function Reaction:Await(): any
	self._consumed = true
	return self._promise:expect()
end

function Reaction:Timeout(seconds: number): Reaction
	if self._timeoutThread then
		task.cancel(self._timeoutThread)
	end

	self._timeoutThread = task.delay(seconds, function()
		if self._reject then
			self._reject("timeout")
		end
	end)

	return self
end

function Reaction:Retry(attempts: number): Reaction
	self._retriesLeft = attempts
	return self
end

function Reaction:Decay(seconds: number): Reaction
	if self._decayThread then
		task.cancel(self._decayThread)
	end

	self._decayThread = task.delay(seconds, function()
		if not self._consumed and self._reject then
			self._reject("decayed")
		end
	end)

	return self
end

function Reaction:Cancel()
	self._cancelled = true
	if self._reject then
		self._reject("cancelled")
	end
end

function Reaction:Branch(table: Branch.BranchTable): Reaction
	self:Next(function(value)
		return Branch.Resolve(value, table)
	end)
	return self
end

return Reaction
