local Enums    = require(script.Enums)
local Platform = require(script.Platform)
local Context  = require(script.Context)
local Registry = require(script.Registry)
local Types    = require(script.Types)

local Switch = {}

Switch.Enums    = Enums
Switch.Platform = Platform

function Switch.Define(name: string, config: Types.ActionConfig): Types.ActionHandle
	return Registry.Define(name, config)
end

function Switch.Fetch(name: string): Types.ActionHandle?
	return Registry.Fetch(name)
end

function Switch.Fork(name: string, newName: string, overrides: Types.ActionConfig?): Types.ActionHandle
	return Registry.Fork(name, newName, overrides)
end

function Switch.Merge(...: Types.ActionHandle): Types.MergedHandle
	return Registry.Merge(...)
end

function Switch.Poll(name: string): Types.PollState
	local action = Registry.Fetch(name)
	assert(action, "[Switch] Poll: action '" .. name .. "' does not exist")
	return action:Poll()
end

function Switch.Remove(name: string)
	Registry.Remove(name)
end

function Switch.Clear()
	Registry.Clear()
end

function Switch.GetByTag(tag: string): { Types.ActionHandle }
	return Registry.GetByTag(tag)
end

function Switch.PushContext(name: string, options: Types.ContextOptions?)
	Context.Push(name, options)
end

function Switch.PopContext(name: string?)
	Context.Pop(name)
end

function Switch.PeekContext(): string?
	return Context.Peek()
end

function Switch.HasContext(name: string): boolean
	return Context.Has(name)
end

function Switch.ContextStack(): { string }
	return Context.Stack()
end

function Switch.ClearContext()
	Context.Clear()
end

function Switch.SnapshotContext(): { Types.ContextEntry }
	return Context.Snapshot()
end

function Switch.RestoreContext(snapshot: { Types.ContextEntry })
	Context.Restore(snapshot)
end

function Switch.OnContextPush(name: string, cb: (string) -> ()): () -> ()
	return Context.OnPush(name, cb)
end

function Switch.OnContextPop(name: string, cb: (string) -> ()): () -> ()
	return Context.OnPop(name, cb)
end

function Switch.OnContextChanged(cb: ({ string }) -> ()): () -> ()
	return Context.OnChanged(cb)
end

return Switch