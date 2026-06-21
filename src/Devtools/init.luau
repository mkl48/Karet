-- Devtools - the first real Karet extension: live diagnostics that register through the
-- plugin platform (Karet.RegisterExtension) rather than being hardcoded. ships a Performance
-- Profiler panel and an instance Inspector. more diagnostics (log console, network monitor)
-- will land here as additional panels/commands.
--
-- client-only (it draws Iris windows via ctx.Window). registered from startClient.

local Devtools = {}

-- ---------------------------------------------------------------------------
-- live perf stats (one Heartbeat sampler shared by the profiler panel)
-- ---------------------------------------------------------------------------

local stats = { fps = 60, ms = 16.7, mem = 0 }
local statsStarted = false

local function startStats()
	if statsStarted then
		return
	end
	statsStarted = true
	local RunService = game:GetService("RunService")
	local Stats = game:GetService("Stats")
	RunService.Heartbeat:Connect(function(dt)
		stats.ms = dt * 1000
		local fps = dt > 0 and (1 / dt) or 0
		stats.fps += (fps - stats.fps) * 0.1 -- smoothed
		local ok, mem = pcall(function()
			return Stats:GetTotalMemoryUsageMb()
		end)
		if ok then
			stats.mem = mem
		end
	end)
end

-- ---------------------------------------------------------------------------
-- log console: a structured ring buffer of the game's log stream, with replay
-- ---------------------------------------------------------------------------

local LOG_CAP = 500
local logBuffer: { { clock: number, level: string, text: string } } = {}
local logStarted = false

local function startLogs()
	if logStarted then
		return
	end
	logStarted = true
	game:GetService("LogService").MessageOut:Connect(function(message, messageType)
		local level = "info"
		if messageType == Enum.MessageType.MessageError then
			level = "error"
		elseif messageType == Enum.MessageType.MessageWarning then
			level = "warn"
		end
		table.insert(logBuffer, { clock = os.clock(), level = level, text = message })
		while #logBuffer > LOG_CAP do
			table.remove(logBuffer, 1)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- network monitor: incoming RemoteEvent traffic for remotes you register
-- ---------------------------------------------------------------------------

local NET_CAP = 200
local netBuffer: { { clock: number, name: string, kind: string, size: number } } = {}

-- Watch a RemoteEvent's incoming traffic (client OnClientEvent). RemoteFunctions are skipped
-- because OnClientInvoke is single-owner and hooking it would swallow the call. There's no
-- vanilla way to intercept ALL remote traffic, so you register the ones you care about.
local function watchRemote(remote: Instance)
	if remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(function(...)
			local packed = table.pack(...)
			table.insert(netBuffer, { clock = os.clock(), name = remote.Name, kind = "Event", size = packed.n })
			while #netBuffer > NET_CAP do
				table.remove(netBuffer, 1)
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- instance path resolution (game.Workspace.Baseplate / Workspace.Spawn / ...)
-- ---------------------------------------------------------------------------

local function resolve(path: string): Instance?
	if not path or path == "" then
		return nil
	end
	local node: any = game
	for segment in string.gmatch(path, "[^%.]+") do
		if string.lower(segment) == "game" then
			node = game
		else
			local ok, child = pcall(function()
				return node:FindFirstChild(segment)
			end)
			if ok and child then
				node = child
			else
				local ok2, service = pcall(function()
					return game:GetService(segment)
				end)
				node = (ok2 and service) or nil
			end
			if not node then
				return nil
			end
		end
	end
	return node
end

-- ---------------------------------------------------------------------------
-- panels / commands
-- ---------------------------------------------------------------------------

local function profilerPanel(ctx)
	startStats()
	local w = ctx.Window({ title = "profiler" })
	w:Label(function()
		return string.format("FPS     %d", math.floor(stats.fps + 0.5))
	end)
	w:Label(function()
		return string.format("frame   %.2f ms", stats.ms)
	end)
	w:Label(function()
		return string.format("memory  %.0f MB", stats.mem)
	end)
	w:Separator()
	local plot = w:Plot("frame ms", { height = 64, min = 0, max = 50 })
	w:OnRender(function()
		plot.push(stats.ms)
	end)
	w:Separator()
	w:Button("close", function()
		w:Close()
	end)
end

local function logsPanel(ctx)
	startLogs()
	local w = ctx.Window({ title = "logs" })
	local search = w:Input("search", "")
	local showInfo = w:Checkbox("info", true)
	local showWarn = w:Checkbox("warn", true)
	local showError = w:Checkbox("error", true)
	w:Separator()
	-- "replay": scrub anchors the view N entries back from the newest, so you can step back
	-- through a recorded sequence instead of only seeing the tail.
	local scrub = w:Slider("scrub back", 0, LOG_CAP, 0)
	w:Separator()
	w:Label(function()
		local query = string.lower(search.get() or "")
		local levels = { info = showInfo.get(), warn = showWarn.get(), error = showError.get() }
		local filtered = {}
		for _, entry in logBuffer do
			if levels[entry.level] and (query == "" or string.find(string.lower(entry.text), query, 1, true)) then
				table.insert(filtered, entry)
			end
		end
		local back = math.floor(scrub.get())
		local anchor = math.max(1, #filtered - back)
		local lines = {}
		for i = math.max(1, anchor - 17), anchor do
			local entry = filtered[i]
			if entry then
				table.insert(lines, string.format("[%s] %s", entry.level, entry.text))
			end
		end
		return #lines > 0 and table.concat(lines, "\n") or "(no matching logs)"
	end)
	w:Separator()
	w:Button("clear", function()
		table.clear(logBuffer)
	end)
	w:Button("close", function()
		w:Close()
	end)
end

local function netmonPanel(ctx)
	local w = ctx.Window({ title = "netmon" })
	w:Label("incoming RemoteEvent traffic (register with Karet.WatchRemote)")
	w:Separator()
	w:Label(function()
		if #netBuffer == 0 then
			return "(nothing yet)"
		end
		local lines = {}
		for i = math.max(1, #netBuffer - 17), #netBuffer do
			local e = netBuffer[i]
			table.insert(lines, string.format("%-24s %s  x%d", e.name, e.kind, e.size))
		end
		return table.concat(lines, "\n")
	end)
	w:Separator()
	w:Button("clear", function()
		table.clear(netBuffer)
	end)
	w:Button("close", function()
		w:Close()
	end)
end

local function inspectWindow(ctx, target: Instance)
	local w = ctx.Window({ title = "inspect: " .. target.Name })
	w:Label(function()
		return "class:    " .. target.ClassName
	end)
	w:Label(function()
		return "name:     " .. target.Name
	end)
	w:Label(function()
		return "children: " .. #target:GetChildren()
	end)
	w:Separator()
	w:Label("attributes")

	-- attributes are the one generically-enumerable + editable surface (Roblox has no general
	-- property reflection), so we expose those as live fields.
	local fields = {}
	for name, value in target:GetAttributes() do
		local kind = type(value)
		if kind == "boolean" then
			local handle = w:Checkbox(name, value)
			table.insert(fields, { name = name, kind = "boolean", get = handle.get })
		elseif kind == "number" or kind == "string" then
			local handle = w:Input(name, tostring(value))
			table.insert(fields, { name = name, kind = kind, get = handle.get })
		end
	end
	if #fields == 0 then
		w:Label("(none)")
	else
		w:Button("apply", function()
			for _, field in fields do
				local raw = field.get()
				if field.kind == "number" then
					target:SetAttribute(field.name, tonumber(raw) or 0)
				else
					target:SetAttribute(field.name, raw)
				end
			end
		end)
	end
	w:Separator()
	w:Button("close", function()
		w:Close()
	end)
end

-- Register the whole Devtools extension into a Karet instance.
function Devtools.register(Karet: any)
	-- expose remote watching on the umbrella so games can feed the network monitor
	Karet.WatchRemote = watchRemote

	Karet.RegisterExtension({
		Name = "Devtools",
		Description = "profiler, inspector, log console, network monitor",
		Init = function()
			startLogs() -- start capturing immediately so the console has history when opened
		end,
		Panels = {
			{ Name = "profiler", Description = "fps / frame / memory + graph", Open = profilerPanel },
			{ Name = "logs", Description = "log console with filters + replay", Open = logsPanel },
			{ Name = "netmon", Description = "incoming RemoteEvent traffic", Open = netmonPanel },
		},
		Commands = {
			{
				Name = "inspect",
				Aliases = { "explore" },
				Description = "inspect an instance: inspect Workspace.Baseplate",
				Network = "Client",
				Args = { { Name = "path", Types = { "String" }, Required = false } },
				On = { Client = function(ctx)
					local target: Instance? = nil
					if ctx.Args.path then
						target = resolve(ctx.Args.path)
						if not target then
							return ctx.Err(`no instance at '{ctx.Args.path}'`)
						end
					else
						local plr = game:GetService("Players").LocalPlayer
						target = (plr and plr.Character) or workspace
					end
					inspectWindow(ctx, target :: Instance)
					ctx.Info(`inspecting {(target :: Instance):GetFullName()}`)
				end },
			},
		},
	})
end

return Devtools
