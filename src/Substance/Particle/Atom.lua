-- Substance
-- Particle/Atom.lua
-- Plinko Labs

local Registry = require(script.Parent.Registry)
local Dispatch = require(script.Parent.Dispatch)
local Types = require(script.Parent.Types)

local Atom = {}
Atom.__index = Atom

local isotopeCounter = 0

local function wrap(name: string, shape: Types.Shape?): Types.AtomHandle
	return setmetatable({
		Name = name,
		Shape = shape,
	}, Atom) :: any
end

function Atom.Define(name: string, shape: Types.Shape): Types.AtomHandle
	local channel = Registry.Ensure(name)
	channel.Shape = shape
	return wrap(name, shape)
end

function Atom:Isotope(constraints: Types.Constraints): Types.AtomHandle
	isotopeCounter += 1
	local isotopeName = string.format("%s::Isotope%d", self.Name, isotopeCounter)

	local channel = Registry.Ensure(isotopeName)
	channel.Shape = self.Shape
	channel.Constraints = constraints

	local handle = wrap(isotopeName, self.Shape)
	;(handle :: any)._constraints = constraints
	return handle
end

function Atom:Compose(channelName: string, eventType: Types.EventType): Types.AtomHandle
	(self :: any)._channel = channelName
	Dispatch.Compose(channelName, self.Shape, eventType, (self :: any)._constraints)
	return self :: any
end

function Atom:Post(payload: any, target: Player?): any
	local channelName = (self :: any)._channel or self.Name
	return Dispatch.Post(channelName, payload, target)
end

function Atom:Subscribe(handler: (any, Player?) -> any): Types.Subscription
	local channelName = (self :: any)._channel or self.Name
	return Dispatch.Subscribe(channelName, handler)
end

function Atom:Entangle(owner: Types.Authority): Types.AtomHandle
	local React = require(script.Parent.Parent.React)
	return React.Entangle(self, owner)
end

function Atom:Set(_value: any)
	error(string.format("[Substance] '%s' is not Entangled, call :Entangle() first", self.Name))
end

function Atom:Get(): any
	error(string.format("[Substance] '%s' is not Entangled, call :Entangle() first", self.Name))
end

return Atom
