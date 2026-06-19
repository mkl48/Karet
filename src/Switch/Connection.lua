-- Switch
-- Connection.lua
-- Plinko Labs

local Promise = require(script.Parent.Promise)
local Types   = require(script.Parent.Types)

export type Connection = {
	Then:    (self: Connection, cb: (Types.InputEvent) -> any) -> Connection,
	Catch:   (self: Connection, cb: (string) -> ()) -> Connection,
	Once:    (self: Connection) -> Connection,
	Await:   (self: Connection) -> (boolean, Types.InputEvent?),
	Destroy: (self: Connection) -> (),
}

local Connection = {}
Connection.__index = Connection

function Connection.new(bindFn: ((Types.InputEvent) -> ()) -> () -> ()): Connection
	local self       = setmetatable({}, Connection)

	self._cbs        = {}
	self._errCbs     = {}
	self._once       = false
	self._destroyed  = false
	self._disconnect = nil

	self._disconnect = bindFn(function(value: Types.InputEvent)
		if self._destroyed then return end

		local ok, err = pcall(function()
			for _, cb in self._cbs do
				cb(value)
			end
		end)

		if not ok then
			for _, cb in self._errCbs do
				cb(err)
			end
		end

		if self._once then
			self:Destroy()
		end
	end)

	return self
end

function Connection:Then(cb: (Types.InputEvent) -> any): Connection
	assert(not self._destroyed, "[Switch] Cannot chain Then on a destroyed connection")
	table.insert(self._cbs, cb)
	return self
end

function Connection:Catch(cb: (string) -> ()): Connection
	assert(not self._destroyed, "[Switch] Cannot chain Catch on a destroyed connection")
	table.insert(self._errCbs, cb)
	return self
end

function Connection:Once(): Connection
	self._once = true
	return self
end

function Connection:Await(): (boolean, Types.InputEvent?)
	assert(not self._destroyed, "[Switch] Cannot Await a destroyed connection")
	local thread = coroutine.running()
	local result, success

	self:Then(function(value)
		success = true
		result  = value
		task.spawn(thread)
	end):Catch(function(err)
		success = false
		result  = err
		task.spawn(thread)
	end):Once()

	coroutine.yield()
	return success, result
end

function Connection:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	if self._disconnect then
		self._disconnect()
		self._disconnect = nil
	end

	table.clear(self._cbs)
	table.clear(self._errCbs)
end

return {
	Connection = Connection,
	Promise    = Promise,
}