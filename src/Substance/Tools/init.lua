-- Substance
-- Tools/init.lua
-- Plinko Labs

local HooksModule = require(script.Hooks)
local FossilModule = require(script.Fossil)
local LandLineModule = require(script.LandLine)
local BatchModule = require(script.Batch)
local FissionModule = require(script.Fission)

local Tools = {}

Tools.Hooks = HooksModule
Tools.Fossil = FossilModule

function Tools.LandLine(name: string, steps: {LandLineModule.Step}): any
	return LandLineModule.Run(name, steps)
end

function Tools.Batch(requests: {BatchModule.Request}): any
	return BatchModule.Run(requests)
end

function Tools.Fission(trigger: string, targets: {FissionModule.Target})
	FissionModule.Register(trigger, targets)
end

return Tools
