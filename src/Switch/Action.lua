-- Switch
-- Action.lua
-- Plinko Labs

local ContextActionService = game:GetService("ContextActionService")
local UserInputService     = game:GetService("UserInputService")
local RunService           = game:GetService("RunService")

local Enums      = require(script.Parent.Enums)
local Context    = require(script.Parent.Context)
local Connection = require(script.Parent.Connection).Connection
local Types      = require(script.Parent.Types)

local Action = {}
Action.__index = Action

local function _makeSignalTable()
	return setmetatable({}, {
		__index = function(t, k)
			t[k] = {}
			return t[k]
		end,
	})
end

local function _makeEvent(source, state, extra)
	local event = {
		Source   = source,
		State    = state,
		Delta    = extra and extra.Delta,
		Position = extra and extra.Position,
		Progress = extra and extra.Progress,
		Count    = extra and extra.Count,
		Step     = extra and extra.Step,
		Held     = extra and extra.Held or false,
		Consumed = false,
	}

	function event:Consume()
		self.Consumed = true
	end

	return event
end

local StateResult = {}
StateResult.__index = StateResult

function StateResult.new(value, data)
	return setmetatable({ _value = value, _data = data }, StateResult)
end

function StateResult:With()
	return self._data
end

local function _result(value, data)
	if not value then return nil end
	return StateResult.new(value, data)
end

function Action.new(name, config)
	local self = setmetatable({}, Action)

	self.Name         = name
	self.Config       = config
	self._signals     = _makeSignalTable()
	self._driver      = config.Driver or Enums.Driver.IAS
	self._enabled     = true
	self._held        = false
	self._heldStart   = nil
	self._pollState   = Enums.Poll.Idle

	self._activeStates   = {}

	self._comboStep      = 0
	self._comboTimer     = nil

	self._charging       = false
	self._chargeConn     = nil
	self._chargeStart    = nil
	self._chargeProgress = 0

	self._mashCount  = 0
	self._mashTimer  = nil
	self._mashWindow = {}

	self._doubleTapPending = false
	self._doubleTapTimer   = nil
	self._doubleTapTime    = nil

	self._longPressTimer = nil
	self._holdTimer      = nil

	self._conflicts = {}

	self._iasContext  = nil
	self._iasAction   = nil
	self._iasBindings = {}

	self._uisConn    = nil
	self._uisEndConn = nil

	self:_Setup()

	return self
end

function Action:_SetState(state, active)
	self._activeStates[state] = active or nil
end

function Action:_Fire(state, event)
	if not self._enabled then return end
	if not Context.IsActive(self.Config.Contexts) then return end

	local listeners = self._signals[state]
	if not listeners then return end

	for _, entry in listeners do
		if not event.Consumed then
			task.spawn(entry.fire, event)
		end
	end
end

function Action:_PlatformAllowed()
	local platforms = self.Config.Platforms
	if not platforms or #platforms == 0 then return true end

	local Platform = require(script.Parent.Platform)
	local current  = Platform.Get()

	for _, p in platforms do
		if p == current then return true end
	end

	return false
end

function Action:_SetupIAS()
	local actionsFolder = script.Actions

	local context = Instance.new("InputContext")
	context.Name     = self.Name .. "_Context"
	context.Priority = self.Config.Priority or 100
	context.Sink     = self.Config.Sink or false
	context.Enabled  = false
	context.Parent   = actionsFolder
	self._iasContext = context

	local action = Instance.new("InputAction")
	action.Name   = self.Name
	action.Parent = context
	self._iasAction = action

	if self.Config.Bindings then
		for _, binding in self.Config.Bindings do
			local b = Instance.new("InputBinding")
			if typeof(binding) == "table" then
				b.KeyCode = binding.KeyCode
				if binding.Modifier then
					b.ModifierKey = binding.Modifier
				end
			else
				b.KeyCode = binding
			end
			b.Parent = action
			table.insert(self._iasBindings, b)
		end
	end

	context.Enabled = true

	action.Pressed:Connect(function()
		if not self:_PlatformAllowed() then return end
		self:_HandlePressed(action)
	end)

	action.Released:Connect(function()
		if not self:_PlatformAllowed() then return end
		self:_HandleReleased(action)
	end)

	action.StateChanged:Connect(function(value)
		if not self:_PlatformAllowed() then return end
		local event = _makeEvent(action, Enums.State.Changed, { Progress = value })
		self:_SetState(Enums.State.Changed, true)
		self:_Fire(Enums.State.Changed, event)
		task.delay(0, function() self:_SetState(Enums.State.Changed, nil) end)
	end)
end

function Action:_SetupCAS()
	if not self.Config.Bindings then return end

	local bindings = {}
	for _, b in self.Config.Bindings do
		local key = typeof(b) == "table" and b.KeyCode or b
		table.insert(bindings, key)
	end

	ContextActionService:BindActionAtPriority(
		self.Name,
		function(_, inputState, inputObject)
			if not self:_PlatformAllowed() then
				return Enum.ContextActionResult.Pass
			end

			local source = inputObject.KeyCode ~= Enum.KeyCode.Unknown
				and inputObject.KeyCode
				or inputObject.UserInputType

			if inputState == Enum.UserInputState.Begin then
				self:_HandlePressed(source)
			elseif inputState == Enum.UserInputState.End then
				self:_HandleReleased(source)
			elseif inputState == Enum.UserInputState.Change then
				local event = _makeEvent(source, Enums.State.Changed, {
					Delta    = inputObject.Delta,
					Position = inputObject.Position,
				})
				self:_SetState(Enums.State.Changed, true)
				self:_Fire(Enums.State.Changed, event)
				task.delay(0, function() self:_SetState(Enums.State.Changed, nil) end)
			end

			return Enum.ContextActionResult.Pass
		end,
		false,
		self.Config.Priority or 100,
		table.unpack(bindings)
	)
end

function Action:_SetupUIS()
	if not self.Config.Bindings then return end

	self._uisConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if not self:_PlatformAllowed() then return end

		for _, binding in self.Config.Bindings do
			local key = typeof(binding) == "table" and binding.KeyCode or binding
			if input.KeyCode == key or input.UserInputType == key then
				self:_HandlePressed(key)
				break
			end
		end
	end)

	self._uisEndConn = UserInputService.InputEnded:Connect(function(input)
		if not self:_PlatformAllowed() then return end

		for _, binding in self.Config.Bindings do
			local key = typeof(binding) == "table" and binding.KeyCode or binding
			if input.KeyCode == key or input.UserInputType == key then
				self:_HandleReleased(key)
				break
			end
		end
	end)
end

function Action:_Setup()
	if self._driver == Enums.Driver.IAS then
		self:_SetupIAS()
	elseif self._driver == Enums.Driver.CAS then
		self:_SetupCAS()
	elseif self._driver == Enums.Driver.UIS then
		self:_SetupUIS()
	end
end

function Action:_HandlePressed(source)
	self._held      = true
	self._heldStart = os.clock()
	self._pollState = Enums.Poll.Active

	self:_SetState(Enums.State.Pressed, true)
	self:_SetState(Enums.State.Released, nil)

	local mode = self.Config.Mode or Enums.Mode.Button

	if mode == Enums.Mode.Button or mode == Enums.Mode.Shortcut then
		local event = _makeEvent(source, Enums.State.Pressed)
		self:_Fire(Enums.State.Pressed, event)
		self:_StartHeldLoop(source)

	elseif mode == Enums.Mode.Hold then
		self:_StartHoldTimer(source)

	elseif mode == Enums.Mode.Charge then
		self:_StartCharge(source)

	elseif mode == Enums.Mode.DoubleTap then
		self:_HandleDoubleTap(source)

	elseif mode == Enums.Mode.Mash then
		self:_HandleMash(source)

	elseif mode == Enums.Mode.Combo then
		self:_HandleComboStep(source)

	elseif mode == Enums.Mode.LongPress then
		local event = _makeEvent(source, Enums.State.Pressed)
		self:_Fire(Enums.State.Pressed, event)
		self:_StartLongPress(source)
	end
end

function Action:_HandleReleased(source)
	self._held      = false
	self._heldStart = nil
	self._pollState = Enums.Poll.Idle

	self:_SetState(Enums.State.Pressed, nil)
	self:_SetState(Enums.State.Held, nil)
	self:_SetState(Enums.State.Released, true)

	local mode  = self.Config.Mode or Enums.Mode.Button
	local event = _makeEvent(source, Enums.State.Released)
	self:_Fire(Enums.State.Released, event)

	if mode == Enums.Mode.Hold then
		if self._holdTimer then
			task.cancel(self._holdTimer)
			self._holdTimer = nil
			-- released before hold completed
			self:_SetState(Enums.State.Canceled, true)
			local cancelEvent = _makeEvent(source, Enums.State.Canceled)
			self:_Fire(Enums.State.Canceled, cancelEvent)
			task.delay(0, function() self:_SetState(Enums.State.Canceled, nil) end)
		end
	end

	if mode == Enums.Mode.Charge then
		self:_StopCharge(source)
	end

	if mode == Enums.Mode.LongPress then
		if self._longPressTimer then
			task.cancel(self._longPressTimer)
			self._longPressTimer = nil
			self:_SetState(Enums.State.Canceled, true)
			local cancelEvent = _makeEvent(source, Enums.State.Canceled)
			self:_Fire(Enums.State.Canceled, cancelEvent)
			task.delay(0, function() self:_SetState(Enums.State.Canceled, nil) end)
		end
	end
end

function Action:_StartHeldLoop(source)
	if not self.Config.RepeatInterval then return end

	task.spawn(function()
		while self._held do
			task.wait(self.Config.RepeatInterval)
			if not self._held then break end
			self:_SetState(Enums.State.Held, true)
			local event = _makeEvent(source, Enums.State.Held, { Held = true })
			self:_Fire(Enums.State.Held, event)
		end
	end)
end

function Action:_StartHoldTimer(source)
	local holdTime = self.Config.HoldTime or 0.5

	self._holdTimer = task.delay(holdTime, function()
		if not self._held then return end
		self._holdTimer = nil
		self:_SetState(Enums.State.Triggered, true)
		local event = _makeEvent(source, Enums.State.Triggered)
		self:_Fire(Enums.State.Triggered, event)
		task.delay(0, function() self:_SetState(Enums.State.Triggered, nil) end)
	end)
end

function Action:_StartCharge(source)
	self._charging       = true
	self._chargeStart    = os.clock()
	self._chargeProgress = 0

	self:_SetState(Enums.State.Charged, true)

	self._chargeConn = RunService.Heartbeat:Connect(function()
		if not self._charging then return end

		local elapsed  = os.clock() - self._chargeStart
		local holdTime = self.Config.HoldTime or 1
		local progress = math.clamp(elapsed / holdTime, 0, 1)

		self._chargeProgress = progress

		local event = _makeEvent(source, Enums.State.Charged, { Progress = progress })
		self:_Fire(Enums.State.Charged, event)
	end)
end

function Action:_StopCharge(source)
	if not self._charging then return end
	self._charging = false

	self:_SetState(Enums.State.Charged, nil)

	if self._chargeConn then
		self._chargeConn:Disconnect()
		self._chargeConn = nil
	end

	local elapsed  = os.clock() - (self._chargeStart or os.clock())
	local holdTime = self.Config.HoldTime or 1
	local progress = math.clamp(elapsed / holdTime, 0, 1)

	self._chargeProgress = progress
	self:_SetState(Enums.State.Triggered, true)

	local event = _makeEvent(source, Enums.State.Triggered, { Progress = progress })
	self:_Fire(Enums.State.Triggered, event)
	task.delay(0, function() self:_SetState(Enums.State.Triggered, nil) end)
end

function Action:_HandleDoubleTap(source)
	local window = self.Config.Window or 0.3
	local now    = os.clock()

	if self._doubleTapPending and (now - (self._doubleTapTime or 0)) <= window then
		self._doubleTapPending = false

		if self._doubleTapTimer then
			task.cancel(self._doubleTapTimer)
			self._doubleTapTimer = nil
		end

		self:_SetState(Enums.State.DoubleTapped, true)
		local event = _makeEvent(source, Enums.State.DoubleTapped)
		self:_Fire(Enums.State.DoubleTapped, event)
		task.delay(0, function() self:_SetState(Enums.State.DoubleTapped, nil) end)
	else
		self._doubleTapPending = true
		self._doubleTapTime    = now

		if self._doubleTapTimer then
			task.cancel(self._doubleTapTimer)
		end

		self._doubleTapTimer = task.delay(window, function()
			self._doubleTapPending = false
			self._doubleTapTimer   = nil
			self._doubleTapTime    = nil
		end)
	end
end

function Action:_HandleMash(source)
	local window    = self.Config.Window or 1
	local threshold = self.Config.MashThreshold or 5
	local now       = os.clock()

	local fresh = {}
	for _, t in self._mashWindow do
		if now - t <= window then
			table.insert(fresh, t)
		end
	end
	table.insert(fresh, now)
	self._mashWindow = fresh
	self._mashCount  = #fresh

	if self._mashTimer then
		task.cancel(self._mashTimer)
	end

	self._mashTimer = task.delay(window, function()
		self._mashWindow = {}
		self._mashCount  = 0
		self._mashTimer  = nil
		self:_SetState(Enums.State.Mashed, nil)
	end)

	if self._mashCount >= threshold then
		local count      = self._mashCount
		self._mashWindow = {}
		self._mashCount  = 0

		if self._mashTimer then
			task.cancel(self._mashTimer)
			self._mashTimer = nil
		end

		self:_SetState(Enums.State.Mashed, count)
		local event = _makeEvent(source, Enums.State.Mashed, { Count = count })
		self:_Fire(Enums.State.Mashed, event)
	end
end

function Action:_HandleComboStep(source)
	local sequence = self.Config.Sequence
	if not sequence or #sequence == 0 then return end

	local window   = self.Config.Window or 0.4
	local expected = sequence[self._comboStep + 1]
	local matches  = typeof(expected) == "EnumItem" and source == expected

	if not matches then
		self._comboStep = 0

		if self._comboTimer then
			task.cancel(self._comboTimer)
			self._comboTimer = nil
		end

		self:_SetState(Enums.State.Canceled, true)
		local cancelEvent = _makeEvent(source, Enums.State.Canceled)
		self:_Fire(Enums.State.Canceled, cancelEvent)
		task.delay(0, function() self:_SetState(Enums.State.Canceled, nil) end)

		-- restart from step 1 if this key matches the first in sequence
		if sequence[1] == source then
			self._comboStep = 1
			self:_SetState(Enums.State.Stepped, 1)
			local stepEvent = _makeEvent(source, Enums.State.Stepped, { Step = 1 })
			self:_Fire(Enums.State.Stepped, stepEvent)

			self._comboTimer = task.delay(window, function()
				self._comboStep  = 0
				self._comboTimer = nil
				self:_SetState(Enums.State.Stepped, nil)
			end)
		end

		return
	end

	self._comboStep += 1

	if self._comboTimer then
		task.cancel(self._comboTimer)
		self._comboTimer = nil
	end

	self:_SetState(Enums.State.Stepped, self._comboStep)
	local stepEvent = _makeEvent(source, Enums.State.Stepped, { Step = self._comboStep })
	self:_Fire(Enums.State.Stepped, stepEvent)

	if self._comboStep >= #sequence then
		self._comboStep = 0
		self:_SetState(Enums.State.Stepped, nil)
		self:_SetState(Enums.State.Triggered, true)

		local event = _makeEvent(source, Enums.State.Triggered)
		self:_Fire(Enums.State.Triggered, event)
		task.delay(0, function() self:_SetState(Enums.State.Triggered, nil) end)
	else
		self._comboTimer = task.delay(window, function()
			self._comboStep  = 0
			self._comboTimer = nil
			self:_SetState(Enums.State.Stepped, nil)
			self:_SetState(Enums.State.Canceled, true)

			local cancelEvent = _makeEvent(source, Enums.State.Canceled)
			self:_Fire(Enums.State.Canceled, cancelEvent)
			task.delay(0, function() self:_SetState(Enums.State.Canceled, nil) end)
		end)
	end
end

function Action:_StartLongPress(source)
	local holdTime = self.Config.HoldTime or 0.6

	self._longPressTimer = task.delay(holdTime, function()
		if not self._held then return end
		self._longPressTimer = nil

		self:_SetState(Enums.State.LongPressed, true)
		local event = _makeEvent(source, Enums.State.LongPressed)
		self:_Fire(Enums.State.LongPressed, event)
	end)
end

function Action:Next(state: Types.State): Types.Connection
	return Connection.new(function(fire)
		local listeners = self._signals[state]
		local entry     = { fire = fire }
		table.insert(listeners, entry)

		return function()
			local i = table.find(listeners, entry)
			if i then table.remove(listeners, i) end
		end
	end)
end

function Action:HoldFor(seconds: number): Types.Connection
	return Connection.new(function(fire)
		local timer        = nil
		local releaseEntry = nil

		local pressEntry = {
			fire = function(event)
				timer = task.delay(seconds, function()
					if self._held then
						fire(event)
					end
				end)
			end,
		}

		releaseEntry = {
			fire = function(_event)
				if timer then
					task.cancel(timer)
					timer = nil
				end
			end,
		}

		table.insert(self._signals[Enums.State.Pressed], pressEntry)
		table.insert(self._signals[Enums.State.Released], releaseEntry)

		return function()
			local i = table.find(self._signals[Enums.State.Pressed], pressEntry)
			if i then table.remove(self._signals[Enums.State.Pressed], i) end

			local j = table.find(self._signals[Enums.State.Released], releaseEntry)
			if j then table.remove(self._signals[Enums.State.Released], j) end

			if timer then
				task.cancel(timer)
				timer = nil
			end
		end
	end)
end

function Action:Set(state)
	local extra = nil

	if state == Enums.State.Charged then
		extra = { Progress = self._chargeProgress }
	elseif state == Enums.State.Mashed then
		extra = { Count = self._mashCount }
	elseif state == Enums.State.Stepped then
		extra = { Step = self._comboStep }
	end

	self:_SetState(state, true)
	local event = _makeEvent(Enum.KeyCode.Unknown, state, extra)
	self:_Fire(state, event)
	task.delay(0, function() self:_SetState(state, nil) end)
end

function Action:Is(state)
	local value = self._activeStates[state]
	if not value then return nil end

	local data = nil

	if state == Enums.State.Held then
		data = self:HeldDuration()
	elseif state == Enums.State.Charged then
		data = self._chargeProgress
	elseif state == Enums.State.Mashed then
		data = self._mashCount
	elseif state == Enums.State.Stepped then
		data = self._comboStep
	elseif state == Enums.State.Conflicted then
		data = self._conflicts
	end

	return _result(value, data)
end

function Action:Poll(): Types.PollState
	return self._pollState
end

function Action:IsHeld(): boolean
	return self._held
end

function Action:HeldDuration(): number
	if not self._heldStart then return 0 end
	return os.clock() - self._heldStart
end

function Action:Enable()
	self._enabled = true
	self:_SetState(Enums.State.Enabled, true)
	local event = _makeEvent(Enum.KeyCode.Unknown, Enums.State.Enabled)
	self:_Fire(Enums.State.Enabled, event)
	task.delay(0, function() self:_SetState(Enums.State.Enabled, nil) end)
end

function Action:Disable()
	self._enabled = false
	self:_SetState(Enums.State.Disabled, true)
	local event = _makeEvent(Enum.KeyCode.Unknown, Enums.State.Disabled)
	self:_Fire(Enums.State.Disabled, event)
	task.delay(0, function() self:_SetState(Enums.State.Disabled, nil) end)
end

function Action:Destroy()
	self._enabled = false
	self._held    = false

	if self._driver == Enums.Driver.IAS then
		if self._iasContext then
			self._iasContext.Enabled = false
			self._iasContext:Destroy()
		end
	elseif self._driver == Enums.Driver.CAS then
		ContextActionService:UnbindAction(self.Name)
	elseif self._driver == Enums.Driver.UIS then
		if self._uisConn    then self._uisConn:Disconnect()    end
		if self._uisEndConn then self._uisEndConn:Disconnect() end
	end

	if self._holdTimer      then task.cancel(self._holdTimer)      end
	if self._comboTimer     then task.cancel(self._comboTimer)     end
	if self._mashTimer      then task.cancel(self._mashTimer)      end
	if self._doubleTapTimer then task.cancel(self._doubleTapTimer) end
	if self._longPressTimer then task.cancel(self._longPressTimer) end
	if self._chargeConn     then self._chargeConn:Disconnect()     end

	table.clear(self._signals)
	table.clear(self._activeStates)
end

return Action