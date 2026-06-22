-- Pik - Better Data Store.
--
-- an opinionated, single-module wrapper over ProfileStore. multi-schema stores, promise
-- based sessions, dot-path mutations, per-key observers, auto-save, reconciliation and
-- version migration, all behind one clean server-side API.
--
-- server only. never require this on the client - replicate handles to players yourself
-- over RemoteEvents or whatever networking you like.
--
-- this keeps the Keep API 1:1 (Pik.Configure / SetSchema / StartPlayerSession / ... and the
-- handle's Get/Set/Increment/Observe/...), so anything written against Keep works unchanged.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProfileStore = require(script.ProfileStore)

local Pik = {}

-- ---------------------------------------------------------------------------
-- tiny Signal (events + observers)
-- ---------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handler = { fn = fn, connected = true }
	table.insert(self._handlers, handler)
	return {
		Disconnect = function()
			handler.connected = false
			local i = table.find(self._handlers, handler)
			if i then
				table.remove(self._handlers, i)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, handler in self._handlers do
		if handler.connected then
			task.spawn(handler.fn, ...)
		end
	end
end

-- ---------------------------------------------------------------------------
-- tiny Promise (chained with .next / .catch, exactly like the Keep examples)
-- ---------------------------------------------------------------------------

local Promise = {}
Promise.__index = Promise

function Promise.new(executor: ((resolve: (...any) -> (), reject: (...any) -> ()) -> ())?)
	local self = setmetatable({ _state = "pending", _values = nil, _queue = {} }, Promise)
	self.next = function(onResolve)
		return self:_chain(onResolve, nil)
	end
	self.catch = function(onReject)
		return self:_chain(nil, onReject)
	end
	local function resolve(...)
		self:_settle("resolved", table.pack(...))
	end
	local function reject(...)
		self:_settle("rejected", table.pack(...))
	end
	if executor then
		local ok, err = pcall(executor, resolve, reject)
		if not ok then
			reject(err)
		end
	end
	return self
end

function Promise:_settle(state: string, values: any)
	if self._state ~= "pending" then
		return
	end
	self._state = state
	self._values = values
	for _, q in self._queue do
		self:_dispatch(q)
	end
	self._queue = {}
end

function Promise:_dispatch(q)
	local handler = (self._state == "resolved") and q.onResolve or q.onReject
	task.spawn(function()
		if handler then
			local ok, res = pcall(handler, table.unpack(self._values, 1, self._values.n))
			q.child:_settle(ok and "resolved" or "rejected", table.pack(res))
		else
			q.child:_settle(self._state, self._values) -- pass straight through
		end
	end)
end

function Promise:_chain(onResolve, onReject)
	local child = Promise.new()
	local q = { onResolve = onResolve, onReject = onReject, child = child }
	if self._state == "pending" then
		table.insert(self._queue, q)
	else
		self:_dispatch(q)
	end
	return child
end

local function resolved(...): any
	local packed = table.pack(...)
	return Promise.new(function(resolve)
		resolve(table.unpack(packed, 1, packed.n))
	end)
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function deepMerge(dst: { [any]: any }, src: { [any]: any })
	for k, v in src do
		if type(v) == "table" and type(dst[k]) == "table" then
			deepMerge(dst[k], v)
		else
			dst[k] = deepCopy(v)
		end
	end
end

local function splitPath(path: string): { string }
	local parts = {}
	for segment in string.gmatch(path, "[^%.]+") do
		table.insert(parts, segment)
	end
	return parts
end

-- read a dot-path; never errors on a missing middle segment
local function getPath(data: any, path: string?): any
	if path == nil or path == "" then
		return data
	end
	local node = data
	for _, key in splitPath(path) do
		if type(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

-- write a dot-path, creating intermediate tables as needed
local function setPath(data: any, path: string, value: any)
	local parts = splitPath(path)
	local node = data
	for i = 1, #parts - 1 do
		local key = parts[i]
		if type(node[key]) ~= "table" then
			node[key] = {}
		end
		node = node[key]
	end
	node[parts[#parts]] = value
end

local function resolveId(plrOrId: Player | number): number
	if type(plrOrId) == "number" then
		return plrOrId
	elseif typeof(plrOrId) == "Instance" and plrOrId:IsA("Player") then
		return plrOrId.UserId
	end
	error("[Pik]: expected a Player or a UserId", 3)
end

-- ---------------------------------------------------------------------------
-- config + state
-- ---------------------------------------------------------------------------

local config = {
	StorageType = "Single",
	StudioSeparate = false,
	AutoSave = true,
	AutoSaveInterval = 60,
	Reconcile = true,
	LogLevel = "Warn",
	Version = 1,
	Migration = nil :: ((data: any, oldVersion: number) -> any)?,
}

local LOG_ORDER = { None = 0, Warn = 1, Verbose = 2 }

local schemas: { [string]: { template: any, store: any } } = {}
local sessions: { [number]: any } = {} -- userId -> owner
local pendingSessions: { [number]: any } = {} -- userId -> Promise (loading)
local awaiters: { [number]: { (stores: any, owner: any) -> () } } = {}

Pik.OnSessionStart = Signal.new()
Pik.OnSessionEnd = Signal.new()
Pik.OnSaveComplete = Signal.new()

local function log(level: string, message: string)
	local want = LOG_ORDER[config.LogLevel] or 1
	local lvl = LOG_ORDER[level] or 1
	if want == 0 or lvl > want then
		return
	end
	if level == "Warn" then
		warn(`[Pik]: {message}`)
	else
		print(`[Pik]: {message}`)
	end
end

-- ---------------------------------------------------------------------------
-- handle (proxy over a ProfileStore profile)
-- ---------------------------------------------------------------------------

local HandleMethods = {}

local function notify(handle: any, path: string, new: any, old: any)
	local observers = rawget(handle, "_observers")
	local sig = observers[path]
	if sig then
		sig:Fire(new, old)
	end
	rawget(handle, "_all"):Fire(handle:GetAll())
end

function HandleMethods:Get(path: string)
	return getPath(rawget(self, "_profile").Data, path)
end

function HandleMethods:GetAll()
	return deepCopy(rawget(self, "_profile").Data)
end

HandleMethods.Snapshot = HandleMethods.GetAll

function HandleMethods:Set(path: string, value: any)
	local data = rawget(self, "_profile").Data
	local old = getPath(data, path)
	setPath(data, path, value)
	notify(self, path, value, old)
	return self
end

function HandleMethods:Patch(tbl: { [string]: any })
	for key, value in tbl do
		self:Set(key, value)
	end
	return self
end

function HandleMethods:DeepPatch(tbl: { [string]: any })
	local data = rawget(self, "_profile").Data
	deepMerge(data, tbl)
	rawget(self, "_all"):Fire(self:GetAll())
	return self
end

function HandleMethods:Increment(path: string, amount: number?)
	local current = getPath(rawget(self, "_profile").Data, path)
	return self:Set(path, (tonumber(current) or 0) + (amount or 1))
end

function HandleMethods:Append(path: string, value: any)
	local data = rawget(self, "_profile").Data
	local list = getPath(data, path)
	if type(list) ~= "table" then
		list = {}
		setPath(data, path, list)
	end
	table.insert(list, value)
	notify(self, path, list, list)
	return self
end

function HandleMethods:Remove(path: string, index: number)
	local list = getPath(rawget(self, "_profile").Data, path)
	if type(list) == "table" then
		table.remove(list, index)
		notify(self, path, list, list)
	end
	return self
end

function HandleMethods:Observe(path: string, callback: (new: any, old: any) -> ())
	local observers = rawget(self, "_observers")
	local sig = observers[path]
	if not sig then
		sig = Signal.new()
		observers[path] = sig
	end
	return sig:Connect(callback)
end

function HandleMethods:ObserveAll(callback: (data: any) -> ())
	return rawget(self, "_all"):Connect(callback)
end

local HandleMeta = {
	-- read a method, else fall through to profile.Data (the "handle proxy" feature)
	__index = function(self, key)
		local method = HandleMethods[key]
		if method ~= nil then
			return method
		end
		return rawget(self, "_profile").Data[key]
	end,
	-- direct writes go to the data with no signals fired (as documented)
	__newindex = function(self, key, value)
		rawget(self, "_profile").Data[key] = value
	end,
}

local function makeHandle(profile: any, schemaName: string): any
	local handle = {}
	rawset(handle, "_profile", profile)
	rawset(handle, "_schema", schemaName)
	rawset(handle, "_observers", {})
	rawset(handle, "_all", Signal.new())
	return setmetatable(handle, HandleMeta)
end

-- ---------------------------------------------------------------------------
-- migration + first-load overrides
-- ---------------------------------------------------------------------------

local function runMigration(profile: any)
	local data = profile.Data
	local version = data.__PikVersion or 1
	if version < config.Version and config.Migration then
		local ok, migrated = pcall(config.Migration, data, version)
		if ok and type(migrated) == "table" then
			-- replace the contents in place (ProfileStore tracks the Data table by reference)
			for key in data do
				data[key] = nil
			end
			for key, value in migrated do
				data[key] = value
			end
		else
			log("Warn", `migration failed: {tostring(migrated)}`)
		end
	end
	data.__PikVersion = config.Version
end

local function applyOverrides(profile: any, overrides: any, schemaName: string)
	local data = profile.Data
	if data.__PikInit ~= true then
		if type(overrides) == "table" and type(overrides[schemaName]) == "table" then
			deepMerge(data, overrides[schemaName])
		end
		data.__PikInit = true
	end
end

-- ---------------------------------------------------------------------------
-- sessions
-- ---------------------------------------------------------------------------

local function startAutoSave(owner: any)
	if not config.AutoSave then
		return
	end
	task.spawn(function()
		while sessions[owner.UserId] == owner do
			task.wait(config.AutoSaveInterval)
			if sessions[owner.UserId] ~= owner then
				break
			end
			for _, handle in owner.Stores do
				local profile = rawget(handle, "_profile")
				if profile:IsActive() then
					profile:Save()
				end
			end
			Pik.OnSaveComplete:Fire(owner)
		end
	end)
end

local function fireAwaiters(userId: number, stores: any, owner: any)
	local list = awaiters[userId]
	if list then
		awaiters[userId] = nil
		for _, resolve in list do
			task.spawn(resolve, stores, owner)
		end
	end
end

-- Override default settings. Best called before SetSchema / sessions.
function Pik.Configure(overrides: { [string]: any })
	for key, value in overrides do
		config[key] = value
	end
end

-- Register a named schema (and its ProfileStore). Pik[name] then returns an accessor.
function Pik.SetSchema(name: string, schema: { [string]: any })
	local storeName = name
	if config.StudioSeparate and RunService:IsStudio() then
		storeName = "Studio_" .. storeName
	end
	local template = deepCopy(schema)
	template.__PikVersion = config.Version
	schemas[name] = {
		template = schema,
		store = ProfileStore.New(storeName, template),
	}
	log("Verbose", `registered schema '{name}'`)
end

-- The main entry point: load every schema for a player, start auto-save, resolve with the
-- handles + owner. Returns the existing session if one is already active.
function Pik.StartPlayerSession(plrOrId: Player | number, overrides: any): any
	local userId = resolveId(plrOrId)
	local player = (typeof(plrOrId) == "Instance") and plrOrId or Players:GetPlayerByUserId(userId)

	if sessions[userId] then
		return resolved(sessions[userId].Stores, sessions[userId])
	end
	if pendingSessions[userId] then
		return pendingSessions[userId]
	end

	local promise = Promise.new(function(resolve, reject)
		task.spawn(function()
			local ok, err = pcall(function()
				local stores = {}
				for name, schema in schemas do
					-- StartSessionAsync returns nil (or throws) when the key is contended or the
					-- datastore request budget is full, which is common at join when other systems
					-- are loading their own data. retry a few times with backoff before giving up.
					local profile, lastErr
					for attempt = 1, 4 do
						local ok2, result = pcall(schema.store.StartSessionAsync, schema.store, `{name}_{userId}`, {
							Cancel = function()
								return player ~= nil and player.Parent == nil
							end,
						})
						if ok2 and result then
							profile = result
							break
						end
						lastErr = if ok2 then "session unavailable (key contended or store throttled)" else result
						if player and player.Parent == nil then
							break -- they already left, stop trying
						end
						task.wait(attempt) -- 1s, 2s, 3s backoff
					end
					if not profile then
						error(`could not start a session for schema '{name}': {tostring(lastErr)}`)
					end
					profile:AddUserId(userId)
					runMigration(profile)
					if config.Reconcile then
						profile:Reconcile()
					end
					applyOverrides(profile, overrides, name)

					local handle = makeHandle(profile, name)
					stores[name] = handle

					profile.OnSessionEnd:Connect(function()
						-- if every schema for this player has ended, drop + announce the owner
						local owner = sessions[userId]
						if not owner then
							return
						end
						for _, h in owner.Stores do
							if rawget(h, "_profile"):IsActive() then
								return
							end
						end
						sessions[userId] = nil
						Pik.OnSessionEnd:Fire(owner)
						log("Verbose", `session ended for {userId}`)
					end)
				end

				local owner = { UserId = userId, Player = player, Stores = stores }
				sessions[userId] = owner
				startAutoSave(owner)
				Pik.OnSessionStart:Fire(owner)
				fireAwaiters(userId, stores, owner)
				log("Verbose", `session started for {userId}`)
				resolve(stores, owner)
			end)
			if not ok then
				reject(err)
			end
		end)
	end)

	pendingSessions[userId] = promise
	promise.next(function()
		pendingSessions[userId] = nil
	end)
	promise.catch(function(err)
		pendingSessions[userId] = nil
		log("Warn", `session failed for {userId}: {tostring(err)}`)
	end)
	return promise
end

-- Resolve as soon as the session is ready (great for independent startup systems).
function Pik.AwaitSession(plrOrId: Player | number): any
	local userId = resolveId(plrOrId)
	return Promise.new(function(resolve)
		local owner = sessions[userId]
		if owner then
			resolve(owner.Stores, owner)
			return
		end
		awaiters[userId] = awaiters[userId] or {}
		table.insert(awaiters[userId], resolve)
	end)
end

-- Synchronous AwaitSession: yields the current thread until the session is active.
function Pik.WaitForSession(plrOrId: Player | number): (any, any)
	local userId = resolveId(plrOrId)
	if sessions[userId] then
		return sessions[userId].Stores, sessions[userId]
	end
	local thread = coroutine.running()
	Pik.AwaitSession(plrOrId).next(function(stores, owner)
		task.spawn(thread, stores, owner)
	end)
	return coroutine.yield()
end

-- End a session (save + release every schema). Normally handled for you on leave/shutdown.
function Pik.EndPlayerSession(plrOrId: Player | number)
	local userId = resolveId(plrOrId)
	local owner = sessions[userId]
	if not owner then
		return
	end
	for _, handle in owner.Stores do
		local profile = rawget(handle, "_profile")
		if profile:IsActive() then
			profile:EndSession()
		end
	end
end

-- Pik[name](player) -> that player's handle for the named schema.
setmetatable(Pik, {
	__index = function(_, key)
		if schemas[key] then
			return function(plrOrId: Player | number)
				local owner = sessions[resolveId(plrOrId)]
				return owner and owner.Stores[key] or nil
			end
		end
		return nil
	end,
})

-- automatic cleanup
Players.PlayerRemoving:Connect(function(player)
	Pik.EndPlayerSession(player)
end)

game:BindToClose(function()
	for userId in sessions do
		Pik.EndPlayerSession(userId)
	end
end)

return Pik
