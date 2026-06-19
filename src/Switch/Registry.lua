-- Switch
-- Registry.lua
-- Plinko Labs

local Enums      = require(script.Parent.Enums)
local Action     = require(script.Parent.Action)
local Connection = require(script.Parent.Connection).Connection
local Types      = require(script.Parent.Types)

local Registry = {}

local _actions: { [string]: Types.ActionHandle } = {}

function Registry.Define(name: string, config: Types.ActionConfig): Types.ActionHandle
	assert(typeof(name) == "string", "[Switch] Define expects a string name")
	assert(not _actions[name], "[Switch] Action '" .. name .. "' is already defined")

	local action   = Action.new(name, config)
	_actions[name] = action

	return action
end

function Registry.Fetch(name: string): Types.ActionHandle?
	return _actions[name] or nil
end

function Registry.Fork(name: string, newName: string, overrides: Types.ActionConfig?): Types.ActionHandle
	local source = _actions[name]
	assert(source,                "[Switch] Fork: action '" .. name    .. "' does not exist")
	assert(not _actions[newName], "[Switch] Fork: action '" .. newName .. "' already exists")

	local config = {}
	for k, v in source.Config do
		config[k] = v
	end
	if overrides then
		for k, v in overrides do
			config[k] = v
		end
	end

	local forked      = Action.new(newName, config)
	_actions[newName] = forked

	return forked
end

function Registry.Merge(...: Types.ActionHandle): Types.MergedHandle
	local actions = { ... }
	assert(#actions >= 2, "[Switch] Merge expects at least 2 actions")

	local merged = {}

	function merged:Next(state: Types.State)
		return Connection.new(function(fire)
			local disconnects = {}

			for _, action in actions do
				local conn = action:Next(state)
				conn:Then(function(event)
					fire(event)
				end)
				table.insert(disconnects, function()
					conn:Destroy()
				end)
			end

			return function()
				for _, disconnect in disconnects do
					disconnect()
				end
			end
		end)
	end

	function merged:Poll(): Types.PollState
		for _, action in actions do
			if action:Poll() ~= Enums.Poll.Idle then
				return action:Poll()
			end
		end
		return Enums.Poll.Idle
	end

	function merged:IsHeld(): boolean
		for _, action in actions do
			if action:IsHeld() then return true end
		end
		return false
	end

	function merged:Destroy()
		for _, action in actions do
			action:Destroy()
		end
	end

	return merged
end

function Registry.Remove(name: string)
	local action = _actions[name]
	if action then
		action:Destroy()
		_actions[name] = nil
	end
end

function Registry.Clear()
	for name, action in _actions do
		action:Destroy()
		_actions[name] = nil
	end
end

function Registry.GetByTag(tag: string): { Types.ActionHandle }
	local results = {}
	for _, action in _actions do
		if action.Config.Tags and table.find(action.Config.Tags, tag) then
			table.insert(results, action)
		end
	end
	return results
end

function Registry.All(): { Types.ActionHandle }
	local results = {}
	for _, action in _actions do
		table.insert(results, action)
	end
	return results
end

return Registry