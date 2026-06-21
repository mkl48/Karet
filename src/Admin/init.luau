-- Admin - the moderation backend + commands. server-authoritative: bans persist in a
-- DataStore (single "bans" map key, cached in memory) and sync across servers over
-- MessagingService; kicks/mutes/audit run through here too. the commands are role-gated
-- (Permission = "Admin"), so they only run for players your role hooks rank high enough.
--
-- the backend lives only on the server. the client registers the same command shapes with
-- no-op handlers (Network = "Server" ships them to the server, which holds the real logic),
-- plus the dashboard panel.

local Admin = {}

local BAN_KEY = "bans"
local BAN_TOPIC = "KaretBan"
local AUDIT_CAP = 200

-- ---------------------------------------------------------------------------
-- server backend
-- ---------------------------------------------------------------------------

function Admin.serverSetup(_options: any): any
	local Players = game:GetService("Players")
	local MessagingService = game:GetService("MessagingService")

	local banStore: any = nil
	pcall(function()
		banStore = game:GetService("DataStoreService"):GetDataStore("KaretBans")
	end)

	local function loadBans(): { [string]: any }
		if not banStore then
			return {}
		end
		local ok, data = pcall(function()
			return banStore:GetAsync(BAN_KEY)
		end)
		return (ok and type(data) == "table") and data or {}
	end

	local banCache = loadBans()
	local muted: { [number]: boolean } = {}
	local audit: { any } = {}

	local function record(action: string, by: string?, target: string?, detail: string?)
		table.insert(audit, { clock = os.time(), action = action, by = by or "console", target = target, detail = detail })
		while #audit > AUDIT_CAP do
			table.remove(audit, 1)
		end
	end

	local function isBanned(userId: number): (boolean, any)
		local rec = banCache[tostring(userId)]
		if not rec then
			return false, nil
		end
		if rec.expires and rec.expires > 0 and os.time() > rec.expires then
			return false, nil -- lapsed temp ban
		end
		return true, rec
	end

	local function kickIfHere(userId: number, reason: string?)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			pcall(function()
				player:Kick("[Karet] " .. (reason or "removed"))
			end)
		end
	end

	local backend: any = {}

	backend.audit = record
	backend.getAudit = function()
		return audit
	end
	backend.isBanned = isBanned
	backend.isMuted = function(userId: number): boolean
		return muted[userId] == true
	end

	backend.kick = function(target: Player, reason: string?, by: Player?)
		record("kick", by and by.Name, target.Name, reason)
		pcall(function()
			target:Kick("[Karet] " .. (reason or "kicked"))
		end)
	end

	backend.ban = function(target: Player, reason: string?, by: Player?, durationSecs: number?)
		local userId = target.UserId
		local rec = {
			userId = userId,
			name = target.Name,
			reason = reason or "no reason",
			by = by and by.Name or "console",
			at = os.time(),
			expires = durationSecs and (os.time() + durationSecs) or 0,
		}
		banCache[tostring(userId)] = rec
		if banStore then
			pcall(function()
				banStore:UpdateAsync(BAN_KEY, function(old)
					old = (type(old) == "table") and old or {}
					old[tostring(userId)] = rec
					return old
				end)
			end)
		end
		record("ban", rec.by, target.Name, reason)
		kickIfHere(userId, "banned: " .. rec.reason)
		pcall(function()
			MessagingService:PublishAsync(BAN_TOPIC, { action = "ban", rec = rec })
		end)
		return rec
	end

	backend.unban = function(userId: number, by: Player?)
		banCache[tostring(userId)] = nil
		if banStore then
			pcall(function()
				banStore:UpdateAsync(BAN_KEY, function(old)
					old = (type(old) == "table") and old or {}
					old[tostring(userId)] = nil
					return old
				end)
			end)
		end
		record("unban", by and by.Name, tostring(userId))
		pcall(function()
			MessagingService:PublishAsync(BAN_TOPIC, { action = "unban", userId = userId })
		end)
	end

	backend.mute = function(target: Player, by: Player?)
		muted[target.UserId] = true
		record("mute", by and by.Name, target.Name)
	end
	backend.unmute = function(target: Player, by: Player?)
		muted[target.UserId] = nil
		record("unmute", by and by.Name, target.Name)
	end

	backend.listBans = function(): { any }
		local out = {}
		for _, rec in banCache do
			table.insert(out, rec)
		end
		table.sort(out, function(a, b)
			return (a.at or 0) > (b.at or 0)
		end)
		return out
	end

	-- enforce bans on join (and on anyone already here)
	local function enforce(player: Player)
		local banned, rec = isBanned(player.UserId)
		if banned then
			kickIfHere(player.UserId, "banned: " .. (rec and rec.reason or ""))
		end
	end
	Players.PlayerAdded:Connect(enforce)
	for _, player in Players:GetPlayers() do
		enforce(player)
	end

	-- cross-server: react to bans/unbans published by other servers
	pcall(function()
		MessagingService:SubscribeAsync(BAN_TOPIC, function(message)
			local data = message.Data
			if type(data) ~= "table" then
				return
			end
			if data.action == "ban" and type(data.rec) == "table" then
				banCache[tostring(data.rec.userId)] = data.rec
				kickIfHere(data.rec.userId, "banned: " .. (data.rec.reason or ""))
			elseif data.action == "unban" and data.userId then
				banCache[tostring(data.userId)] = nil
			end
		end)
	end)

	return backend
end

-- ---------------------------------------------------------------------------
-- commands (registered on both realms; backend is nil on the client)
-- ---------------------------------------------------------------------------

function Admin.defs(backend: any): { any }
	-- on the client backend is nil, so the On.Server handler is a no-op - the command still
	-- ships to the server (Network = "Server"), which has the real handler registered.
	local function srv(fn)
		return backend and fn or function() end
	end

	return {
		{
			Name = "kick",
			Network = "Server",
			Permission = "Admin",
			Description = "kick a player",
			Args = {
				{ Name = "target", Types = { "Player" }, Required = true },
				{ Name = "reason", Types = { "String" }, Required = false },
			},
			On = { Server = srv(function(ctx)
				backend.kick(ctx.Args.target, ctx.Args.reason, ctx.Player)
				ctx.Success(`kicked {ctx.Args.target.Name}`)
			end) },
		},
		{
			Name = "ban",
			Network = "Server",
			Permission = "Admin",
			Description = "ban a player (persisted + cross-server); --duration for a temp ban",
			Args = {
				{ Name = "target", Types = { "Player" }, Required = true },
				{ Name = "reason", Types = { "String" }, Required = false },
			},
			Modifiers = {
				{ Name = "duration", Types = { "Duration" }, Description = "temp-ban length (e.g. 1d)" },
			},
			On = { Server = srv(function(ctx)
				backend.ban(ctx.Args.target, ctx.Args.reason, ctx.Player, ctx.Modifiers.duration)
				ctx.Success(`banned {ctx.Args.target.Name}`)
			end) },
		},
		{
			Name = "unban",
			Network = "Server",
			Permission = "Admin",
			Description = "lift a ban by user id",
			Args = { { Name = "userId", Types = { "Integer" }, Required = true } },
			On = { Server = srv(function(ctx)
				backend.unban(ctx.Args.userId, ctx.Player)
				ctx.Success(`unbanned {ctx.Args.userId}`)
			end) },
		},
		{
			Name = "bans",
			Network = "Server",
			Permission = "Admin",
			Description = "list active bans",
			On = { Server = srv(function(ctx)
				local list = backend.listBans()
				if #list == 0 then
					return ctx.Info("no active bans")
				end
				for _, rec in list do
					ctx.Print(`{rec.userId}  {rec.name or "?"}  "{rec.reason}"  by {rec.by}`)
				end
			end) },
		},
		{
			Name = "mute",
			Network = "Server",
			Permission = "Admin",
			Description = "mute a player (Karet.IsMuted reads this)",
			Args = { { Name = "target", Types = { "Player" }, Required = true } },
			On = { Server = srv(function(ctx)
				backend.mute(ctx.Args.target, ctx.Player)
				ctx.Success(`muted {ctx.Args.target.Name}`)
			end) },
		},
		{
			Name = "unmute",
			Network = "Server",
			Permission = "Admin",
			Description = "unmute a player",
			Args = { { Name = "target", Types = { "Player" }, Required = true } },
			On = { Server = srv(function(ctx)
				backend.unmute(ctx.Args.target, ctx.Player)
				ctx.Success(`unmuted {ctx.Args.target.Name}`)
			end) },
		},
		{
			Name = "audit",
			Network = "Server",
			Permission = "Admin",
			Description = "recent moderation actions",
			On = { Server = srv(function(ctx)
				local log = backend.getAudit()
				if #log == 0 then
					return ctx.Info("no audit entries")
				end
				for i = math.max(1, #log - 19), #log do
					local e = log[i]
					ctx.Print(`{os.date("%H:%M:%S", e.clock)}  {e.action}  {e.by} -> {e.target or ""}  {e.detail or ""}`)
				end
			end) },
		},
	}
end

-- The client-side moderation dashboard panel (snapshots the player list at open time).
function Admin.dashboardPanel(Karet: any): any
	return {
		Name = "admin",
		Description = "moderation dashboard",
		Open = function(ctx)
			local Players = game:GetService("Players")
			local w = ctx.Window({ title = "admin" })
			w:Label("online players (reopen to refresh)")
			w:Separator()
			for _, player in Players:GetPlayers() do
				w:Label(player.Name)
				w:Button(`kick {player.Name}`, function()
					Karet.Run(`kick {player.Name}`)
				end)
				w:Button(`ban {player.Name}`, function()
					Karet.Run(`ban {player.Name}`)
				end)
				w:Separator()
			end
			w:Button("close", function()
				w:Close()
			end)
		end,
	}
end

return Admin
