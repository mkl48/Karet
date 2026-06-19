-- Switch
-- Context.lua
-- Plinko Labs

local Types = require(script.Parent.Types)

local Context = {}

local _stack: { Types.ContextEntry } = {}
local _callbacks: {
	Push:    { (name: string) -> () },
	Pop:     { (name: string) -> () },
	Changed: { (stack: { string }) -> () },
} = {
	Push    = {},
	Pop     = {},
	Changed = {},
}

local function _stackNames(): { string }
	local names = {}
	for _, entry in _stack do
		table.insert(names, entry.Name)
	end
	return names
end

local function _notifyChanged()
	local names = _stackNames()
	for _, cb in _callbacks.Changed do
		task.spawn(cb, names)
	end
end

local function _sortStack()
	table.sort(_stack, function(a, b)
		return a.Priority > b.Priority
	end)
end

function Context.Push(name: string, options: Types.ContextOptions?)
	assert(typeof(name) == "string", "[Switch.Context] Push expects a string")

	local opts = options or {}

	if opts.Exclusive then
		Context.Clear()
	end

	for _, entry in _stack do
		if entry.Name == name then return end
	end

	table.insert(_stack, {
		Name     = name,
		Priority = opts.Priority or 100,
		Sink     = opts.Sink or false,
	})

	_sortStack()

	for _, cb in _callbacks.Push do
		task.spawn(cb, name)
	end

	_notifyChanged()
end

function Context.Pop(name: string?)
	if name then
		for i, entry in _stack do
			if entry.Name == name then
				table.remove(_stack, i)

				for _, cb in _callbacks.Pop do
					task.spawn(cb, name)
				end

				_notifyChanged()
				return
			end
		end
	else
		local entry = table.remove(_stack)
		if entry then
			for _, cb in _callbacks.Pop do
				task.spawn(cb, entry.Name)
			end
			_notifyChanged()
		end
	end
end

function Context.Peek(): string?
	local top = _stack[#_stack]
	return top and top.Name or nil
end

function Context.Has(name: string): boolean
	for _, entry in _stack do
		if entry.Name == name then return true end
	end
	return false
end

function Context.Stack(): { string }
	return _stackNames()
end

function Context.Clear()
	local names = _stackNames()
	table.clear(_stack)

	for _, name in names do
		for _, cb in _callbacks.Pop do
			task.spawn(cb, name)
		end
	end

	_notifyChanged()
end

function Context.Snapshot(): { Types.ContextEntry }
	local snap = {}
	for _, entry in _stack do
		table.insert(snap, table.clone(entry))
	end
	return snap
end

function Context.Restore(snapshot: { Types.ContextEntry })
	table.clear(_stack)
	for _, entry in snapshot do
		table.insert(_stack, table.clone(entry))
	end
	_sortStack()
	_notifyChanged()
end

function Context.IsActive(contexts: { string }?): boolean
	if not contexts or #contexts == 0 then return true end
	for _, name in contexts do
		if Context.Has(name) then return true end
	end
	return false
end

function Context.OnPush(name: string, cb: (name: string) -> ()): () -> ()
	assert(typeof(cb) == "function", "[Switch.Context] OnPush expects a function")
	table.insert(_callbacks.Push, cb)
	return function()
		local i = table.find(_callbacks.Push, cb)
		if i then table.remove(_callbacks.Push, i) end
	end
end

function Context.OnPop(name: string, cb: (name: string) -> ()): () -> ()
	assert(typeof(cb) == "function", "[Switch.Context] OnPop expects a function")
	table.insert(_callbacks.Pop, cb)
	return function()
		local i = table.find(_callbacks.Pop, cb)
		if i then table.remove(_callbacks.Pop, i) end
	end
end

function Context.OnChanged(cb: (stack: { string }) -> ()): () -> ()
	assert(typeof(cb) == "function", "[Switch.Context] OnChanged expects a function")
	table.insert(_callbacks.Changed, cb)
	return function()
		local i = table.find(_callbacks.Changed, cb)
		if i then table.remove(_callbacks.Changed, i) end
	end
end

return Context