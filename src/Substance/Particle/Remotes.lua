-- Substance
-- Particle/Remotes.lua
-- Plinko Labs

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER = RunService:IsServer()

local CLASS_BY_TYPE = {
	Lazy = "UnreliableRemoteEvent",
	Strict = "RemoteEvent",
	Solve = "RemoteFunction",
}

local Remotes = {}
local root: Folder? = nil

local function getRoot(): Folder
	if root then
		return root
	end

	if IS_SERVER then
		root = Instance.new("Folder")
		root.Name = "SubstanceRemotes"
		root.Parent = ReplicatedStorage
		return root
	end

	root = ReplicatedStorage:WaitForChild("SubstanceRemotes")
	return root
end

function Remotes.Get(channelName: string, eventType: string): Instance
	local className = CLASS_BY_TYPE[eventType]
	assert(className, string.format("[Substance] Unknown event type '%s'", tostring(eventType)))

	local folder = getRoot()

	if not IS_SERVER then
		return folder:WaitForChild(channelName)
	end

	local existing = folder:FindFirstChild(channelName)
	if existing then
		return existing
	end

	local instance = Instance.new(className)
	instance.Name = channelName
	instance.Parent = folder
	return instance
end

return Remotes
