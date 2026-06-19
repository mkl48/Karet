-- Substance
-- Particle/Hooks.lua
-- Plinko Labs

local Hooks = {}

local preHooks: {[string]: {(any) -> any}} = {}
local postHooks: {[string]: {(any) -> any}} = {}

local function append(store: {[string]: {(any) -> any}}, name: string, hook: (any) -> any)
	local list = store[name]
	if not list then
		list = {}
		store[name] = list
	end
	table.insert(list, hook)
end

local function run(store: {[string]: {(any) -> any}}, name: string, payload: any): any
	local list = store[name]
	if not list then
		return payload
	end

	for _, hook in list do
		local result = hook(payload)
		if result == nil then
			continue
		end
		payload = result
	end

	return payload
end

function Hooks.Pre(name: string, hook: (any) -> any)
	append(preHooks, name, hook)
end

function Hooks.Hook(name: string, hook: (any) -> any)
	append(postHooks, name, hook)
end

function Hooks.RunPre(name: string, payload: any): any
	return run(preHooks, name, payload)
end

function Hooks.RunPost(name: string, payload: any): any
	return run(postHooks, name, payload)
end

return Hooks
