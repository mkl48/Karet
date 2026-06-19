-- Switch
-- Platform.lua
-- Plinko Labs

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Enums = require(script.Parent.Enums)

type Platform = Enums.Platform

local Platform = {}

local _current: Platform = nil
local _callbacks: { (new: Platform, prev: Platform) -> () } = {}

local function _detect(): Platform
	if GuiService:IsTenFootInterface() then
		return Enums.Platform.Console
	end

	if UserInputService.TouchEnabled then
		return Enums.Platform.Mobile
	end

	return Enums.Platform.Computer
end

local function _notify(new: Platform, prev: Platform)
	for _, cb in _callbacks do
		task.spawn(cb, new, prev)
	end
end

_current = _detect()

UserInputService.LastInputTypeChanged:Connect(function()
	local new = _detect()
	if new ~= _current then
		local prev = _current
		_current = new
		_notify(new, prev)
	end
end)

function Platform.Get(): Platform
	return _current
end

function Platform.IsConsole(): boolean
	return _current == Enums.Platform.Console
end

function Platform.IsMobile(): boolean
	return _current == Enums.Platform.Mobile
end

function Platform.IsComputer(): boolean
	return _current == Enums.Platform.Computer
end

function Platform.OnChanged(cb: (new: Platform, prev: Platform) -> ()): () -> ()
	assert(typeof(cb) == "function", "[Switch.Platform] OnChanged expects a function")
	table.insert(_callbacks, cb)

	return function()
		local index = table.find(_callbacks, cb)
		if index then
			table.remove(_callbacks, index)
		end
	end
end

return Platform