--[[--------------------------------------------------------------------------
	AetherUI :: Fader

	Concept 1c / 2b: "after 6s of no input, everything collapses to whispers".

	The HUD breathes out in two steps.

	  awake -> idle    after fader.delay (6s).   Everything dims to idleAlpha.
	  idle  -> zen     after zen.delay (60s), or the moment the client flags you
	                   AFK. The HUD goes to nothing and Modules\Zen.lua puts up a
	                   hairline readout in its place.

	Detecting "no input" is the interesting part. Classic Era gives addons no
	general keypress or mouse-move hook outside secure handlers, so instead of
	trying to observe input we observe *consequences* and treat their absence as
	idleness:

	  in combat            -> active   (PLAYER_REGEN_DISABLED)
	  casting              -> active   (UNIT_SPELLCAST_* on player)
	  has a target         -> active
	  health/power not full-> active   (you are regenerating, so you just did something)
	  cursor over the HUD  -> active
	  cursor moved at all  -> active   (polled; the one true input signal we get)

	The cursor poll runs on the shared 0.1s ticker and costs two GetCursorPosition
	calls, which is nothing. Everything else is event-driven.

	Hard signals vs soft signals
	----------------------------
	Only some of those are evidence that *you are at the keyboard*. The rest are
	evidence that something on screen is worth looking at, which is a different
	claim. Stage one honours both, because "you are hurt, keep the bars up" is a
	reasonable thing to want. Stage two honours only the hard ones - combat,
	casting, and the cursor sitting on the HUD - because a stale target or a
	half-empty health bar says nothing at all about whether you are in the chair,
	and gating zen on them would mean anyone who wandered off at 60% health never
	saw it.

	Going AFK
	---------
	The client flags you away by itself after five minutes without input (not the
	fifteen it feels like), and `autoClearAFK` - on by default - drops the flag
	again on the next thing you do. That gives us two things for free:
	PLAYER_FLAGS_CHANGED as a zen trigger, and, more usefully, PLAYER_FLAGS_CHANGED
	as the one *keyboard* wake signal Classic hands out without a secure frame.
	Zen's own key watcher (Modules\Zen.lua) covers the case where you get there on
	our shorter timer instead.

	Nothing here ever calls Hide. Alpha is not protected; visibility is, and it is
	not per-object - hiding a frame is refused outright if anything underneath it
	is protected. A fader that reached for Hide would work perfectly until the
	first time it fired in combat.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Fader = {}
A.Fader = Fader

Fader.watched = {}
Fader.active = true

--- The client's own auto-AFK delay, in seconds. Nothing exposes it to addons -
--  `autoClearAFK` gates whether the flag is cleared again, not how long it takes
--  to be set - so it is a constant here, and it is the ceiling on zen.delay:
--  past this point going AFK triggers zen anyway and a longer timer could never
--  be the thing that fired.
local AFK_TIMEOUT = 300
Fader.AFK_TIMEOUT = AFK_TIMEOUT

local lastActivity = 0
local lastCursorX, lastCursorY = 0, 0
local casting = false

Fader.state = "awake"   -- "awake" | "idle" | "zen"

-- ---------------------------------------------------------------------------
-- per-frame animation
-- ---------------------------------------------------------------------------

local function StepFrame(entry, dt)
	local target = entry.target
	local cur = entry.frame:GetAlpha()
	local diff = target - cur
	if math.abs(diff) < 0.005 then
		entry.frame:SetAlpha(target)
		entry.animating = false
		return true
	end
	local speed = diff > 0 and entry.fadeIn or entry.fadeOut
	local step = dt / math.max(0.01, speed)
	entry.frame:SetAlpha(cur + diff * math.min(1, step * 2.5))
	return false
end

-- ---------------------------------------------------------------------------

function Fader:Register(frame, opts)
	opts = opts or {}
	local entry = {
		frame     = frame,
		target    = 1,
		-- Kept separate from the live fadeIn/fadeOut. They used to be the same
		-- field, resolved with `entry.fadeIn = entry.fadeIn or cfg.fadeIn`, which
		-- meant the first Update baked the config in permanently and every later
		-- change to a fade time did nothing until a reload.
		optFadeIn  = opts.fadeIn,
		optFadeOut = opts.fadeOut,
		fadeIn     = opts.fadeIn or 0.25,
		fadeOut    = opts.fadeOut or 0.75,
		minAlpha   = opts.minAlpha,
		animating  = false,
	}
	Fader.watched[frame] = entry
	return entry
end

function Fader:Unregister(frame)
	local entry = Fader.watched[frame]
	if entry then
		frame:SetAlpha(1)
		Fader.watched[frame] = nil
	end
end

function Fader:Touch()
	lastActivity = GetTime()
end

--- Seconds since the last thing we could see. Zen's readout uses it to decide
--  how far into its own fade it should already be after a /reload.
function Fader:Quiet()
	return GetTime() - lastActivity
end

-- ---------------------------------------------------------------------------
-- state evaluation
-- ---------------------------------------------------------------------------

local function ZenModule()
	local Z = A.modules and A.modules.zen
	if Z and Z.enabled then return Z end
	return nil
end

local function PlayerIsAFK()
	if not UnitIsAFK then return false end
	local ok, afk = pcall(UnitIsAFK, "player")
	return (ok and afk) and true or false
end

Fader.PlayerIsAFK = PlayerIsAFK

--- Evidence that you are at the keyboard right now.
local function HardAwake(cfg)
	if InCombatLockdown() then return true end
	if casting then return true end

	-- ON A TAXI. A flight is the most idle you ever are - no combat, no target,
	-- no cursor, nothing to cast - so every other test here says "gone" and the
	-- HUD faded out from under the one thing you were watching. The map is
	-- drawing the ground going past and the pill is counting the flight down;
	-- both are the reason to be looking at the screen at all.
	if UnitOnTaxi and UnitOnTaxi("player") then return true end

	-- Dragging frames around is the one time a disappearing HUD is actively
	-- hostile, and the cursor poll alone will not save you while you sit still
	-- deciding where something should go.
	if A.Movers and A.Movers.unlocked then return true end

	if cfg.keepOnMouse then
		for frame in pairs(Fader.watched) do
			if frame:IsMouseOver() then return true end
			-- A unit capsule registers its fixed-size layout core, but the glass
			-- around it grows downward to wrap the debuff tray. Hovering the part
			-- that grew still counts as hovering the frame.
			if frame.glass and frame.glass:IsMouseOver() then return true end
		end
	end

	return false
end

--- Evidence that something on screen is worth looking at. Stage one only.
local function SoftAwake(cfg)
	if cfg.keepOnTarget and UnitExists("target") then return true end

	if cfg.keepOnHurt then
		local hp, hpMax = UnitHealth("player"), UnitHealthMax("player")
		if hpMax and hpMax > 0 and hp < hpMax then return true end
		local pw, pwMax = UnitPower("player"), UnitPowerMax("player")
		-- Rage and energy sitting below max is normal idle state, not activity;
		-- only mana-style pools imply "you just did something".
		local _, token = UnitPowerType("player")
		if token == "MANA" and pwMax and pwMax > 0 and pw < pwMax then return true end
	end

	return false
end

local function Evaluate(cfg)
	if not cfg.enabled then return "awake" end
	if HardAwake(cfg) then return "awake" end

	local quiet = GetTime() - lastActivity

	local Z = ZenModule()
	if Z then
		local zcfg = A.db.profile.modules.zen
		if zcfg.onAFK ~= false and PlayerIsAFK() then return "zen" end
		if quiet >= math.min(zcfg.delay or 60, AFK_TIMEOUT) then return "zen" end
	end

	if SoftAwake(cfg) then return "awake" end
	if quiet < (cfg.delay or 6) then return "awake" end
	return "idle"
end

function Fader:Update()
	local cfg = A.db and A.db.profile.fader
	if not cfg then return end

	local state = Evaluate(cfg)
	local changed = (state ~= Fader.state)
	Fader.state = state

	local target, fadeIn, fadeOut
	if state == "zen" then
		local zcfg = A.db.profile.modules.zen
		-- When zen is fading UIParent, that is the only thing that should be
		-- taking the HUD away. Driving both would multiply two fades together and
		-- the result reads as a snap at the tail rather than an exhale; worse, it
		-- would mean two authorities for one effect. Our frames just stay at the
		-- stage-one dim and let the interface-wide fade carry them.
		target  = (zcfg.dimUI ~= false) and (cfg.idleAlpha or 0.6) or (zcfg.hudAlpha or 0)
		-- Sinking into zen is the slow direction and coming back is the fast one,
		-- which is the opposite way round from stage one: stage one is a dim you
		-- should barely notice, zen is a deliberate exhale.
		fadeOut = zcfg.fadeOut or 2.5
		fadeIn  = zcfg.fadeIn  or 0.30
	elseif state == "idle" then
		target  = cfg.idleAlpha or 0.35
		fadeOut = cfg.fadeOut or 0.75
		fadeIn  = cfg.fadeIn  or 0.25
	else
		target  = cfg.activeAlpha or 1
		fadeOut = cfg.fadeOut or 0.75
		-- Leaving zen keeps zen's fade-in, so the HUD snaps back at the speed the
		-- caption promises rather than easing in over stage one's quarter second
		-- from a standing start of nothing.
		fadeIn  = (Fader._wasZen and A.db.profile.modules.zen.fadeIn) or cfg.fadeIn or 0.25
	end
	Fader._wasZen = (state == "zen")

	for _, entry in pairs(Fader.watched) do
		-- minAlpha is a floor for "this frame never fully fades", which is a
		-- statement about the idle dim. Zen is not a dim, so it ignores it.
		local t = target
		if state ~= "zen" and entry.minAlpha then t = math.max(t, entry.minAlpha) end
		entry.fadeIn  = entry.optFadeIn  or fadeIn
		entry.fadeOut = entry.optFadeOut or fadeOut
		if entry.target ~= t then
			entry.target = t
			entry.animating = true
		end
	end

	if changed then
		local Z = A.modules and A.modules.zen
		if Z and Z.SetActive then Z:SetActive(state == "zen") end
	end
end

-- ---------------------------------------------------------------------------
-- driving
-- ---------------------------------------------------------------------------

local function Tick(_, dt)
	local x, y = GetCursorPosition()
	if x ~= lastCursorX or y ~= lastCursorY then
		lastCursorX, lastCursorY = x, y
		Fader:Touch()
	end

	Fader:Update()

	for _, entry in pairs(Fader.watched) do
		if entry.animating then StepFrame(entry, dt) end
	end
end

function Fader:Enable()
	if Fader._on then return end
	Fader._on = true
	lastActivity = GetTime()
	lastCursorX, lastCursorY = GetCursorPosition()

	A:RegisterTicker(Fader, Tick)

	A:RegisterEvent(Fader, "PLAYER_REGEN_DISABLED", function() Fader:Touch(); Fader:Update() end)
	A:RegisterEvent(Fader, "PLAYER_REGEN_ENABLED",  function() Fader:Touch(); Fader:Update() end)
	A:RegisterEvent(Fader, "PLAYER_TARGET_CHANGED", function() Fader:Touch(); Fader:Update() end)

	-- One argument, the unit whose flags changed, and it fires for party members
	-- too. Confirmed present on Classic Era 1.15.
	A:RegisterEvent(Fader, "PLAYER_FLAGS_CHANGED", function(_, _, unit)
		if unit and unit ~= "player" then return end
		-- The flag clearing means the client saw input we could not. That is the
		-- only free keyboard hook in the game and it is worth more than the flag
		-- being set is.
		if not PlayerIsAFK() then Fader:Touch() end
		Fader:Update()
	end)

	A:RegisterEvent(Fader, "UNIT_SPELLCAST_START", function(_, _, unit)
		if unit == "player" then casting = true; Fader:Touch(); Fader:Update() end
	end)
	A:RegisterEvent(Fader, "UNIT_SPELLCAST_CHANNEL_START", function(_, _, unit)
		if unit == "player" then casting = true; Fader:Touch(); Fader:Update() end
	end)
	local function stop(_, _, unit)
		if unit == "player" then casting = false; Fader:Touch(); Fader:Update() end
	end
	A:RegisterEvent(Fader, "UNIT_SPELLCAST_STOP", stop)
	A:RegisterEvent(Fader, "UNIT_SPELLCAST_CHANNEL_STOP", stop)
	A:RegisterEvent(Fader, "UNIT_SPELLCAST_FAILED", stop)
	A:RegisterEvent(Fader, "UNIT_SPELLCAST_INTERRUPTED", stop)
end

function Fader:Disable()
	Fader._on = false
	Fader.state = "awake"
	Fader._wasZen = false
	A:UnregisterTicker(Fader)
	A:UnregisterAllEvents(Fader)
	local Z = A.modules and A.modules.zen
	if Z and Z.SetActive then Z:SetActive(false) end
	for frame, entry in pairs(Fader.watched) do
		entry.target = 1
		entry.animating = false
		frame:SetAlpha(1)
	end
end

--- Drop straight into zen without sitting out the timer.
--
--  Implemented by backdating the activity clock rather than by pinning the state,
--  so it is not a mode you can get stuck in: the very next thing that touches the
--  fader - a cursor move, a keypress, combat - evaluates its way back out on its
--  own, which is exactly what a preview should do.
function Fader:ForceZen()
	lastActivity = GetTime() - AFK_TIMEOUT
	Fader:Update()
end

function Fader:Refresh()
	local cfg = A.db and A.db.profile.fader
	if cfg and cfg.enabled then
		Fader:Enable()
		Fader:Touch()
		Fader:Update()
	else
		Fader:Disable()
	end
end
