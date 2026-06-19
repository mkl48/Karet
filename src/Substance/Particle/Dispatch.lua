-- Substance
-- Particle/Dispatch.lua
-- Plinko Labs

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Remotes = require(script.Parent.Remotes)
local Registry = require(script.Parent.Registry)
local Schema = require(script.Parent.Schema)
local Hooks = require(script.Parent.Hooks)
local Fossil = require(script.Parent.Fossil)
local Types = require(script.Parent.Types)

local IS_SERVER = RunService:IsServer()
local IS_DEV = RunService:IsStudio()

local Dispatch = {}
local bound: {[string]: boolean} = {}

local function validatePayload(channel: Types.Channel, payload: any): (boolean, string?)
	if not IS_DEV then
		return true
	end

	if channel.Shape then
		local ok, err = Schema.Validate(payload, channel.Shape)
		if not ok then
			return false, string.format("'%s' failed schema validation: %s", channel.Name, err or "unknown error")
		end
	end

	if not channel.Constraints then
		return true
	end

	for field, validator in channel.Constraints do
		if not validator(payload[field]) then
			return false, string.format("'%s' failed constraint on field '%s'", channel.Name, field)
		end
	end

	return true
end

local function callSubscribers(channel: Types.Channel, payload: any, player: Player?): any
	local result = nil

	for _, handler in channel.Subscribers do
		local handlerResult = handler(payload, player)
		if handlerResult == nil then
			continue
		end
		result = handlerResult
	end

	return result
end

local function bind(channel: Types.Channel)
	if bound[channel.Name] then
		return
	end
	bound[channel.Name] = true

	local instance = Remotes.Get(channel.Name, channel.EventType :: string)

	if channel.EventType == "Solve" then
		if IS_SERVER then
			(instance :: RemoteFunction).OnServerInvoke = function(player: Player, payload: any): any
				payload = Hooks.RunPost(channel.Name, payload)
				local ok, err = validatePayload(channel, payload)
				if not ok then
					warn("[Substance] dropped incoming packet: " .. (err :: string))
					return nil
				end
				Fossil.Record(channel.Name, "Received", payload)
				return callSubscribers(channel, payload, player)
			end
		else
			(instance :: RemoteFunction).OnClientInvoke = function(payload: any): any
				payload = Hooks.RunPost(channel.Name, payload)
				local ok, err = validatePayload(channel, payload)
				if not ok then
					warn("[Substance] dropped incoming packet: " .. (err :: string))
					return nil
				end
				Fossil.Record(channel.Name, "Received", payload)
				return callSubscribers(channel, payload, nil)
			end
		end
		return
	end

	local signal = if IS_SERVER then (instance :: RemoteEvent).OnServerEvent else (instance :: RemoteEvent).OnClientEvent
	signal:Connect(function(playerOrPayload: any, maybePayload: any)
		local player: Player? = nil
		local payload = playerOrPayload

		if IS_SERVER then
			player = playerOrPayload
			payload = maybePayload
		end

		payload = Hooks.RunPost(channel.Name, payload)
		local ok, err = validatePayload(channel, payload)
		if not ok then
			warn("[Substance] dropped incoming packet: " .. (err :: string))
			return
		end
		Fossil.Record(channel.Name, "Received", payload)
		callSubscribers(channel, payload, player)
	end)
end

function Dispatch.Compose(name: string, shape: Types.Shape?, eventType: Types.EventType, constraints: Types.Constraints?): Types.Channel
	local channel = Registry.Ensure(name)
	channel.Shape = shape or channel.Shape
	channel.EventType = eventType
	channel.Constraints = constraints or channel.Constraints
	bind(channel)
	return channel
end

function Dispatch.Subscribe(name: string, handler: (any, Player?) -> any): Types.Subscription
	return Registry.AddSubscriber(name, handler)
end

function Dispatch.Post(name: string, payload: any, target: Player?): any
	local channel = Registry.Get(name)
	assert(channel, string.format("[Substance] Post: channel '%s' is not composed", name))
	assert(channel.EventType, string.format("[Substance] Post: channel '%s' has no event type, call :Compose() first", name))

	bind(channel)

	local Async = require(script.Parent.Parent.Async)

	return Async.Reaction.new(function()
		local outgoing = Hooks.RunPre(name, payload)

		local ok, err = validatePayload(channel, outgoing)
		if not ok then
			warn("[Substance] " .. (err :: string))
			error("validation_failed", 0)
		end

		Fossil.Record(name, "Sent", outgoing)

		local instance = Remotes.Get(name, channel.EventType :: string)

		if channel.EventType == "Solve" then
			if IS_SERVER then
				assert(target, string.format("[Substance] Post: '%s' is Solve and requires a target Player from the server", name))
				return (instance :: RemoteFunction):InvokeClient(target, outgoing)
			end
			return (instance :: RemoteFunction):InvokeServer(outgoing)
		end

		if IS_SERVER then
			if target then
				(instance :: RemoteEvent):FireClient(target, outgoing)
			else
				(instance :: RemoteEvent):FireAllClients(outgoing)
			end
		else
			(instance :: RemoteEvent):FireServer(outgoing)
		end

		return true
	end)
end

function Dispatch.Broadcast(name: string, payload: any, filter: ((Player) -> boolean)?)
	assert(IS_SERVER, "[Substance] Broadcast can only be called from the server")

	local channel = Registry.Get(name)
	assert(channel, string.format("[Substance] Broadcast: channel '%s' is not composed", name))
	bind(channel)

	local outgoing = Hooks.RunPre(name, payload)

	local ok, err = validatePayload(channel, outgoing)
	assert(ok, "[Substance] " .. tostring(err))

	Fossil.Record(name, "Sent", outgoing)

	local instance = Remotes.Get(name, channel.EventType :: string)

	for _, player in Players:GetPlayers() do
		if filter and not filter(player) then
			continue
		end

		if channel.EventType == "Solve" then
			task.spawn(function()
				(instance :: RemoteFunction):InvokeClient(player, outgoing)
			end)
			continue
		end

		(instance :: RemoteEvent):FireClient(player, outgoing)
	end
end

return Dispatch
