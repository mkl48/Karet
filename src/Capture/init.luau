-- stops the game from eating our keys while the terminal/editor is open. disabling the
-- movement controls kills the char moving on arrows/wasd, and sinking shift via CAS stops
-- shift lock when you press : (shift+;). text input + the textbox cursor are untouched.
-- ref counted so it only re enables once everything is closed.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Capture = {}

local active: { [string]: boolean } = {}
local count = 0
local controls: any = nil

local function getControls()
	local player = Players.LocalPlayer
	local ps = player and player:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if not pm then
		return nil
	end
	local ok, mod = pcall(require, pm)
	if not ok then
		return nil
	end
	local ok2, c = pcall(function()
		return mod:GetControls()
	end)
	return ok2 and c or nil
end

local function enable()
	controls = controls or getControls()
	if controls then
		pcall(function()
			controls:Disable()
		end)
	end
	ContextActionService:BindActionAtPriority("KaretCapture", function()
		return Enum.ContextActionResult.Sink
	end, false, 9000, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
end

local function disable()
	if controls then
		pcall(function()
			controls:Enable()
		end)
	end
	ContextActionService:UnbindAction("KaretCapture")
end

function Capture.acquire(id: string)
	if not RunService:IsClient() or active[id] then
		return
	end
	active[id] = true
	count += 1
	if count == 1 then
		enable()
	end
end

function Capture.release(id: string)
	if not active[id] then
		return
	end
	active[id] = nil
	count -= 1
	if count <= 0 then
		count = 0
		disable()
	end
end

return Capture
