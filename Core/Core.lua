--[[--------------------------------------------------------------------------
	AetherUI :: Core

	Namespace, module registry and the single event pump every module shares.

	Design notes
	------------
	* One event frame for the whole suite. Modules subscribe by name; the pump
	  fans out. That keeps the number of live event registrations proportional to
	  the number of *distinct events* rather than the number of frames.
	* Modules are plain tables with optional OnInitialize / OnEnable / OnDisable /
	  OnSkinChanged / OnConfigChanged. Nothing is required.
	* Everything is lazy: a module is only enabled if its config says so, and
	  disabling one at runtime tears down cleanly.
----------------------------------------------------------------------------]]

local ADDON, A = ...

_G[ADDON] = A

A.name     = ADDON
A.version  = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
             or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "0.1.0"
A.modules  = {}
A.moduleOrder = {}

-- ---------------------------------------------------------------------------
-- chat output
-- ---------------------------------------------------------------------------

--- The name, built EVERY TIME rather than once into an upvalue.
--
--  Twice wrong as a constant: this file loads before the palette does, so the
--  helpers are not there yet, and a prefix frozen at load carries the skin you
--  started on for the rest of the session.
local function prefix()
	return A.Hi("Aether") .. A.Val("UI") .. ": "
end

function A:Print(...)
	local n = select("#", ...)
	local parts = {}
	for i = 1, n do parts[i] = tostring((select(i, ...))) end
	DEFAULT_CHAT_FRAME:AddMessage(prefix() .. table.concat(parts, " "))
end

function A:Debug(...)
	if not A.db or not A.db.profile or not A.db.profile.debug then return end
	A:Print(A.Palette:Ink("info", "[dbg]"), ...)
end

-- ---------------------------------------------------------------------------
-- pixel helpers
--
-- WoW's virtual coordinate space is 768 units tall regardless of resolution.
-- A "pixel" is therefore 768 / screenHeight / effectiveScale virtual units, and
-- snapping to that grid is what stops 1px rims turning into 0.7px smudges.
-- ---------------------------------------------------------------------------

A.pixel = 1

function A:UpdatePixelScale()
	local physicalHeight
	if GetPhysicalScreenSize then
		local _, h = GetPhysicalScreenSize()
		physicalHeight = h
	end
	if not physicalHeight or physicalHeight <= 0 then
		-- Fall back to deriving it from the virtual height and the current scale.
		local h = UIParent:GetHeight()
		local s = UIParent:GetEffectiveScale() or 1
		physicalHeight = (h and s and h * s) or 1080
	end

	local scale = UIParent:GetEffectiveScale()
	if not scale or scale <= 0 then scale = 1 end

	local p = 768 / physicalHeight / scale
	-- guard against NaN / nonsense before it propagates into every anchor
	if p ~= p or p <= 0 or p > 4 then p = 1 end
	A.pixel = p
end

--- Snap a virtual-unit value onto the physical pixel grid.
function A:Snap(v)
	local p = A.pixel
	return math.floor(v / p + 0.5) * p
end

--- Convert a count of real screen pixels into virtual units.
function A:Px(n)
	return (n or 1) * A.pixel
end

--- One physical pixel, in a particular FRAME's own units.
--
--  A.pixel is in UIParent units. A frame at profile.scale is not in UIParent
--  units, so anything that wants to land on the pixel grid inside a scaled frame
--  - a 1px rim, a snapped diameter - has to convert across first. A tooltip runs
--  at 0.71, so "one pixel" there is 1.4 of its own units, and using A.pixel
--  directly draws a rim seven tenths of a pixel wide: present, sub-pixel, and
--  grey wherever it lands across a boundary.
function A:PxIn(frame)
	local us = UIParent:GetEffectiveScale() or 1
	local fs = (frame and frame.GetEffectiveScale and frame:GetEffectiveScale()) or us
	if not fs or fs <= 0 then fs = us end
	local step = (A.pixel or 1) * us / fs
	if not step or step <= 0 or step ~= step then return A.pixel or 1 end
	return step
end

--- Snap a length onto the physical pixel grid, in a frame's own units.
function A:SnapIn(frame, v)
	local step = A:PxIn(frame)
	return math.floor(v / step + 0.5) * step
end

-- ---------------------------------------------------------------------------
-- keyboard propagation
-- ---------------------------------------------------------------------------

--- Let a key through, or hold on to it, without shouting in the error log.
--
--  SetPropagateKeyboardInput is PROTECTED, on every frame - not only secure
--  ones. Called during combat lockdown it is refused and the client writes
--  "attempted to call a protected function" into the player's log, naming our
--  frame. The bag window shipped calling it from OnKeyDown for keys it does not
--  even act on, and put that line in front of a player nine times in one fight.
--
--  Two things make it safe, both learned from CinematicTaxi, which hit exactly
--  this and wrote down why:
--
--    * The value PERSISTS between keyboard events. So remember it, and setting
--      it to what it already holds becomes a no-op that never reaches the
--      protected call at all. Since propagation rests at true and every key we
--      do not act on wants true, that alone is most of the fix.
--    * When we genuinely do need to change it mid-fight, queue it and replay on
--      PLAYER_REGEN_ENABLED. Dropping a pending "back to true" is how a window
--      ends up eating every key the player presses until they close it.
--
--  Zen's OnKeyDown carried a comment saying the client clears the flag after
--  every event, so setting it once buys nothing. That was wrong, and it is the
--  reason this call was on a hot path in the first place.
--  Returns whether the frame is KNOWN to be in the state you asked for. False
--  means the write was deferred to the end of combat, which matters to a caller
--  about to enable the keyboard: a frame that captures but cannot propagate eats
--  every key the player presses.
local propagateQueue
function A:SetPropagate(frame, value)
	if not frame or not frame.SetPropagateKeyboardInput then return false end
	value = value and true or false

	-- NO assumption about the starting state, and the first call on a frame
	-- always goes through.
	--
	-- This said "frames are created propagating, so an unknown state is true",
	-- which is exactly backwards: a frame with EnableKeyboard(true) CAPTURES
	-- until it is told otherwise. So the one call that mattered - the explicit
	-- "propagate" at construction - was skipped as redundant, and the bag window
	-- swallowed every key the moment it opened. Escape still worked, because
	-- that one we handle ourselves, which is what made it look like a bag bug
	-- rather than an input one.
	--
	-- CinematicTaxi seeds its cache the same way and does NOT have this problem,
	-- because it calls SetPropagateKeyboardInput explicitly first and sets the
	-- cache after. Copying the cache without the call was the mistake.
	if frame.__propagating ~= nil and frame.__propagating == value then return true end

	if InCombatLockdown and InCombatLockdown() then
		frame.__pendingPropagate = value
		if not propagateQueue then
			propagateQueue = {}
			A.__propagateQueue = propagateQueue
			A:RegisterEvent(A, "PLAYER_REGEN_ENABLED", function()
				for f in pairs(propagateQueue) do
					local want = f.__pendingPropagate
					if want ~= nil then
						f:SetPropagateKeyboardInput(want)
						f.__propagating, f.__pendingPropagate = want, nil
					end
					propagateQueue[f] = nil
				end
			end)
		end
		propagateQueue[frame] = true
		return false
	end

	frame:SetPropagateKeyboardInput(value)
	frame.__propagating, frame.__pendingPropagate = value, nil
	return true
end

-- ---------------------------------------------------------------------------
-- module registry
-- ---------------------------------------------------------------------------

function A:NewModule(name, defaults)
	assert(not A.modules[name], "AetherUI: duplicate module " .. tostring(name))
	local m = {
		name      = name,
		defaults  = defaults,
		enabled   = false,
		_events   = {},
	}
	A.modules[name] = m
	A.moduleOrder[#A.moduleOrder + 1] = name
	return m
end

function A:GetModule(name)
	return A.modules[name]
end

--- Iterate modules in registration order (deterministic; pairs() is not).
function A:IterateModules()
	local i = 0
	return function()
		i = i + 1
		local n = A.moduleOrder[i]
		if n then return n, A.modules[n] end
	end
end

-- ---------------------------------------------------------------------------
-- event pump
-- ---------------------------------------------------------------------------

local pump = CreateFrame("Frame", ADDON .. "EventPump")
A.pump = pump

local listeners = {}   -- event -> { [module or table] = handlerName or function }

pump:SetScript("OnEvent", function(_, event, ...)
	local bucket = listeners[event]
	if not bucket then return end
	for owner, handler in pairs(bucket) do
		if type(handler) == "function" then
			handler(owner, event, ...)
		else
			local fn = owner[handler]
			if fn then fn(owner, event, ...) end
		end
	end
end)

--- Subscribe `owner` to `event`. `handler` is a function or a method name on owner.
function A:RegisterEvent(owner, event, handler)
	local bucket = listeners[event]
	if not bucket then
		-- Registering an event the client does not know about throws. Classic Era
		-- and Retail disagree about a handful of unit events, and the set moves
		-- between patches, so probe rather than maintain a version table.
		local ok = pcall(pump.RegisterEvent, pump, event)
		if not ok then
			A:Debug("event not available on this client:", event)
			return false
		end
		bucket = {}
		listeners[event] = bucket
	end
	bucket[owner] = handler or event
	return true
end

function A:UnregisterEvent(owner, event)
	local bucket = listeners[event]
	if not bucket then return end
	bucket[owner] = nil
	if not next(bucket) then
		listeners[event] = nil
		pump:UnregisterEvent(event)
	end
end

function A:UnregisterAllEvents(owner)
	for event, bucket in pairs(listeners) do
		if bucket[owner] then
			bucket[owner] = nil
			if not next(bucket) then
				listeners[event] = nil
				pump:UnregisterEvent(event)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- shared ticker
--
-- Modules that need polling (fader idle detection, range checks) share one
-- OnUpdate rather than each creating their own.
-- ---------------------------------------------------------------------------

local tickers, tickAccum = {}, 0
local TICK = 0.1

pump:SetScript("OnUpdate", function(_, elapsed)
	tickAccum = tickAccum + elapsed
	if tickAccum < TICK then return end
	local dt = tickAccum
	tickAccum = 0
	for owner, fn in pairs(tickers) do
		fn(owner, dt)
	end
end)

function A:RegisterTicker(owner, fn)
	tickers[owner] = fn
end

function A:UnregisterTicker(owner)
	tickers[owner] = nil
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

local booted = false

local function EnableModule(name, module)
	if module.enabled then return end
	local cfg = A.db and A.db.profile.modules[name]
	if cfg and cfg.enabled == false then return end
	module.enabled = true
	module.lastError = nil
	if module.OnEnable then
		local ok, err = pcall(module.OnEnable, module)
		if not ok then
			module.enabled = false
			module.lastError = tostring(err)
			A:Print(A.Bad("module '" .. name .. "' failed to enable:") .. " " .. tostring(err))
			A:Print(A.Bad("run") .. " /aether diag " .. A.Bad("for the full picture."))
		end
	end
end

local function DisableModule(name, module)
	if not module.enabled then return end
	module.enabled = false
	if module.OnDisable then pcall(module.OnDisable, module) end
	A:UnregisterAllEvents(module)
	A:UnregisterTicker(module)
end

A.EnableModule, A.DisableModule = EnableModule, DisableModule

function A:SetModuleEnabled(name, on)
	local m = A.modules[name]
	if not m then return end
	A.db.profile.modules[name] = A.db.profile.modules[name] or {}
	A.db.profile.modules[name].enabled = on and true or false
	if on then EnableModule(name, m) else DisableModule(name, m) end
end

--- Push a config/skin change through every live module.
--- Errors from these two are recorded as well as printed.
--
--  A restyle or a reconfigure runs every module, and a pcall that only prints
--  means a broken one shows up in chat while everything carries on looking
--  fine. Recording it gives /aether diag something to report and the harness
--  something to fail on - which is what it took to notice that flipping one
--  toggle was quietly erroring inside the action bars.
A.lastFailure = nil

local function RunAll(hook, label)
	for name, m in A:IterateModules() do
		if m.enabled and m[hook] then
			local ok, err = pcall(m[hook], m)
			if not ok then
				m.lastError = tostring(err)
				A.lastFailure = label .. " '" .. name .. "': " .. tostring(err)
				A:Print(A.Bad(label .. " '" .. name .. "':") .. " " .. tostring(err))
			end
		end
	end
end

--- Anyone who is not a module, told when the skin changes.
--
--  The eighteen modules get OnSkinChanged and always have. This is for the
--  rest: the movers' lock button, the library slide-out, a widget somebody
--  built outside a module. Before it existed those had no way to hear about
--  a skin change at all, and the brief asks for a live switch with no
--  reload - which means everything on screen, not everything owned by a
--  module.
--
--  A listener is a plain function. It cannot unregister, deliberately: WoW
--  never destroys a frame, so nothing here can go stale, and an unregister
--  nobody calls is a second way to get it wrong.
local skinListeners = {}

function A:OnSkinChanged(fn)
	if type(fn) ~= "function" then return end
	skinListeners[#skinListeners + 1] = fn
end

--- Fired at the END of a restyle, after the sweeps and after the modules -
--  so a listener sees the interface already in its new skin rather than
--  halfway through changing.
local function FireSkinChanged()
	for i = 1, #skinListeners do
		local ok, err = pcall(skinListeners[i])
		if not ok then
			A.lastFailure = tostring(err)
			A:Print(A.Bad("a skin listener failed:") .. " " .. tostring(err))
		end
	end
end

function A:Restyle()
	A:UpdatePixelScale()
	A.Palette:Apply(A.db.profile.skin)
	-- Every glass surface still dressed by token, in one sweep, BEFORE the
	-- modules get their say. A surface knows which palette entries it was built
	-- from; its owner should not have to remember on its behalf, and eighteen
	-- modules each walking their own widgets is eighteen chances to miss one.
	if A.Glass and A.Glass.RestyleAll then A.Glass.RestyleAll() end
	if A.Widgets and A.Widgets.RestyleInk then A.Widgets.RestyleInk() end
	RunAll("OnSkinChanged", "restyle")
	FireSkinChanged()
end

function A:Reconfigure()
	A:UpdatePixelScale()
	RunAll("OnConfigChanged", "reconfigure")
end

local function Boot()
	if booted then return end
	booted = true

	A:UpdatePixelScale()
	A.Config:Initialize()          -- builds A.db
	A.Media:Initialize()           -- registers media with LibSharedMedia
	A.Palette:Apply(A.db.profile.skin)

	for name, m in A:IterateModules() do
		if m.OnInitialize then
			local ok, err = pcall(m.OnInitialize, m)
			if not ok then A:Print(A.Bad("init '" .. name .. "':") .. " " .. tostring(err)) end
		end
	end
	for name, m in A:IterateModules() do
		EnableModule(name, m)
	end

	-- After the modules, because the bar pages in the option tree are built from
	-- whatever bars actually exist. Failing here costs the panel, not the HUD.
	if A.Options then pcall(A.Options.Register, A.Options) end
end

--- One line at login: which build this is, and where to go next.
--
--  So a player reporting a bug can say what they are running without being
--  asked first, which is the whole point of it. Two lines, not a banner - a
--  greeting long enough to scroll the chat frame is one people turn off.
function A:Greet()
	if A.db and A.db.profile and A.db.profile.greet == false then return end
	if A.__greeted then return end
	A.__greeted = true

	A:Print("v" .. (A.version or "?") .. " loaded  ·  skin "
		.. A.Val((A.Palette and A.Palette.current) or "?"))
	-- Bare /aether opens the settings panel, so pointing at it "for commands"
	-- sends people somewhere that does not list any.
	A:Print(A.Hi("/aether") .. " settings  ·  " .. A.Hi("/aether help") .. " commands"
		.. "  ·  " .. A.Hi("/aether errors") .. " bug report")
end

A:RegisterEvent(A, "ADDON_LOADED", function(_, _, addon)
	if addon == ADDON then Boot() end
end)

A:RegisterEvent(A, "PLAYER_LOGIN", function()
	Boot()
	A:UpdatePixelScale()
	A:Reconfigure()

	-- Catch errors from here on. At login rather than at load, so anything else
	-- that wants the handler has had its chance to take it and we chain to it
	-- rather than over it.
	if A.Errors then A.Errors:Install() end

	A:Greet()
end)

A:RegisterEvent(A, "UI_SCALE_CHANGED", function()
	A:UpdatePixelScale()
	A:Reconfigure()
end)

A:RegisterEvent(A, "DISPLAY_SIZE_CHANGED", function()
	A:UpdatePixelScale()
	A:Reconfigure()
end)
