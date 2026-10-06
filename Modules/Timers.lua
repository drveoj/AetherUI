--[[--------------------------------------------------------------------------
	AetherUI :: Timers

	The mirror timers - the breath you have left underwater, your fatigue out at
	sea, the seconds of a feigned death - drawn as Lattice's MIRROR LANES.

	WHAT THE WORLD IS DOING TO YOU ARRIVES AT YOUR LEFT EDGE. The handoff's rule
	for the player-target axis (Cast lanes): what you do leaves the capsule's
	right edge, what is done to you comes in at its left. So a mirror timer is a
	4px lane running 170 out from the left of your own capsule, draining away as
	time runs out, labelled against the capsule - BREATH 0:38 - in the colour
	that says which it is before you have read the word. Under ten seconds it
	pulses. Two at once stack, 8 apart.

	OURS, DRIVEN BY THE CLIENT'S EVENTS. This used to reskin Blizzard's three
	MirrorTimer frames in place, which worked on Classic Era and did nothing at
	all on WoW Forever: Forever has no MirrorTimer1-3 and no MirrorTimer_Show,
	only a pooled MirrorTimerContainer (Blizzard_MirrorTimer/Mainline/
	MirrorTimer.xml:57). What the two clients DO share is the data:
	MIRROR_TIMER_START / STOP / PAUSE and GetMirrorTimerInfo /
	GetMirrorTimerProgress, none of them secret (MirrorTimerDocumentation.lua).
	So the lanes read those, and Blizzard's frames - whichever this client has -
	are kept hidden while the module is on and left to come back when it is off.

	Times arrive in MILLISECONDS: start and max values and the progress reading
	alike (Era's own MirrorTimer.lua divides all three by 1000).
----------------------------------------------------------------------------]]

local ADDON, A = ...

local TM = A:NewModule("timers")

local W, Palette = A.Widgets, A.Palette

local LANE_W    = 170   -- the handoff's lane length
local LANE_H    = 4     -- the lane's own stroke
local STACK     = 8     -- between two lanes
local LABEL_GAP = 3     -- from a lane to its label
local PULSE_AT  = 10    -- seconds left before the lane starts to pulse
local PULSE_T   = 1.2   -- latticePulse period for a mirror lane

-- The client's own slot count, read where it exists.
local function NumSlots() return _G.MIRRORTIMER_NUMTIMERS or 3 end

--- Which colour says which timer. Keys are the client's timer names.
local function LaneColor(kind)
	local c = Palette.c
	if kind == "BREATH" then return c.mirrorBreath end
	if kind == "EXHAUSTION" then return c.mirrorFatigue end
	if kind == "FEIGNDEATH" or kind == "DEATH" then return c.mirrorFeign end
	return c.accent
end

TM.LaneColor = LaneColor

-- ---------------------------------------------------------------------------
-- Blizzard's own, kept out of sight
-- ---------------------------------------------------------------------------

--- Whichever mirror-timer frames this client has.
local function BlizzardFrames()
	local out = {}
	if _G.MirrorTimerContainer then out[#out + 1] = _G.MirrorTimerContainer end
	for i = 1, NumSlots() do
		local f = _G["MirrorTimer" .. i]
		if f then out[#out + 1] = f end
	end
	return out
end

--- Hidden, and hidden again whenever the client shows it - but neither
--  unregistered nor reparented. MirrorTimerContainer is an Edit Mode system,
--  and Blizzard code that reads a frame's parent as a typed object has bitten
--  this addon before (ActionBars.lua's KEEP_PARENT); none of these frames is
--  protected, so a hide is honoured in combat too. Gated on the module, so
--  switching it off hands the client its frames back on the next timer.
local function HideBlizzard()
	for _, f in ipairs(BlizzardFrames()) do
		if not f.__aetherMirrorHook and f.HookScript then
			f.__aetherMirrorHook = true
			f:HookScript("OnShow", function(self)
				if TM.enabled then self:Hide() end
			end)
		end
		if f.Hide then f:Hide() end
	end
end

--- Off: let a timer that is running right now show the client's way again.
local function RestoreBlizzard()
	local box = _G.MirrorTimerContainer
	if box and box.ShouldShow and box.SetShown then
		pcall(function() box:SetShown(box:ShouldShow()) end)
	end
	for i = 1, NumSlots() do
		local f = _G["MirrorTimer" .. i]
		if f and f.timer and f.Show then f:Show() end
	end
end

-- ---------------------------------------------------------------------------
-- the lanes
-- ---------------------------------------------------------------------------

--- The player capsule the lanes leave from, or nil.
local function Capsule()
	local UF = A:GetModule("unitframes")
	return UF and UF.enabled and UF.player or nil
end

local function BuildLane(parent)
	local lane = CreateFrame("Frame", nil, parent)
	lane:SetSize(LANE_W, LANE_H)

	-- The rail: the bond hairline, the whole length, so the eye can see how
	-- much is left against how much there was.
	lane.rail = lane:CreateTexture(nil, "BACKGROUND")
	lane.rail:SetTexture(A.Media.texture.flat)
	lane.rail:SetPoint("LEFT", lane, "LEFT", 0, 0)
	lane.rail:SetPoint("RIGHT", lane, "RIGHT", 0, 0)
	lane.rail:SetHeight(A:PxIn(lane))

	-- The fill hangs off the RIGHT end, the capsule's side, and shortens toward
	-- it: the lane drains away from you.
	lane.fill = lane:CreateTexture(nil, "ARTWORK")
	lane.fill:SetTexture(A.Media.texture.flat)
	lane.fill:SetPoint("RIGHT", lane, "RIGHT", 0, 0)
	lane.fill:SetHeight(LANE_H)

	lane.label = W.Text(lane, "laneLabel", "RIGHT")
	lane:Hide()
	return lane
end

function TM:Build()
	if self.holder then return end
	self.holder = CreateFrame("Frame", nil, UIParent)
	self.holder:SetSize(LANE_W, LANE_H * 2 + STACK)
	self.holder:SetFrameStrata("MEDIUM")
	self.lanes = {}
	for i = 1, NumSlots() do self.lanes[i] = BuildLane(self.holder) end
	-- Empty, not nil: a skin or config change paints before any timer starts.
	self.timers, self.order = self.timers or {}, self.order or {}
end

--- Where the lanes start: the capsule's left edge, on its centre line. With no
--  capsule (unit frames switched off) they hang at the top of the screen
--  rather than vanish - breath is not optional information.
function TM:Anchor()
	local h = self.holder
	if not h then return end
	h:SetScale(A.db.profile.scale)
	h:ClearAllPoints()
	local cap = Capsule()
	if cap then
		h:SetPoint("TOPRIGHT", cap, "LEFT", 0, LANE_H / 2)
	else
		h:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end

	-- First lane on the centre line with its label above; a second 8 below
	-- with its label below it, so neither word sits on the other's lane.
	for i, lane in ipairs(self.lanes) do
		lane:ClearAllPoints()
		lane:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -((i - 1) * (LANE_H + STACK)))
		lane.label:ClearAllPoints()
		if i == 1 then
			lane.label:SetPoint("BOTTOMRIGHT", lane, "TOPRIGHT", -4, LABEL_GAP)
		else
			lane.label:SetPoint("TOPRIGHT", lane, "BOTTOMRIGHT", -4, -LABEL_GAP)
		end
	end
end

--- m:ss, the handoff's "BREATH 0:38".
local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

TM.Clock = Clock

--- Paint one lane from one timer.
local function Paint(lane, t, now)
	local remain = t.remain or 0
	local frac = (t.max and t.max > 0) and math.min(1, math.max(0, remain / t.max)) or 0

	local c = LaneColor(t.kind)
	lane.fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	lane.fill:SetWidth(math.max(0.001, LANE_W * frac))
	if frac <= 0 then lane.fill:Hide() else lane.fill:Show() end

	local r = Palette.c.mirrorRail
	lane.rail:SetVertexColor(r[1], r[2], r[3], r[4] or 1)

	local word = (t.label and t.label ~= "") and t.label or t.kind or ""
	lane.label:SetText(string.upper(word) .. " " .. Clock(remain / 1000))
	W.Color(lane.label, { c[1], c[2], c[3], 1 })

	-- latticePulse: .55 -> 1 -> .55. Only while it is running out; a paused
	-- lane holds still, because nothing about it is changing.
	if not t.paused and remain < PULSE_AT * 1000 then
		local phase = ((now or 0) % PULSE_T) / PULSE_T
		lane:SetAlpha(0.55 + 0.45 * (0.5 - 0.5 * math.cos(phase * 2 * math.pi)))
	else
		lane:SetAlpha(1)
	end
	lane:Show()
end

function TM:Paint()
	if not self.lanes then return end
	local now = GetTime and GetTime() or 0
	for i, lane in ipairs(self.lanes) do
		local t = self.order[i]
		if t then Paint(lane, t, now) else lane:Hide() end
	end
end

-- ---------------------------------------------------------------------------
-- the timers themselves
-- ---------------------------------------------------------------------------

--- Read the time left from the client, which is the authority: the event's
--  value is where it STARTED, and a pause or a resurface moves it.
local function Refresh(t)
	if t.paused then return end
	if GetMirrorTimerProgress then
		local ok, ms = pcall(GetMirrorTimerProgress, t.kind)
		if ok and type(ms) == "number" then t.remain = ms end
	end
end

function TM:Start(kind, value, maxvalue, paused, label)
	if not kind or kind == "UNKNOWN" then return end
	self.timers = self.timers or {}
	self.order = self.order or {}
	local t = self.timers[kind]
	if not t then
		t = { kind = kind }
		self.timers[kind] = t
		self.order[#self.order + 1] = t
	end
	t.max = maxvalue or t.max or 0
	t.remain = value or t.remain or 0
	t.paused = (paused or 0) > 0
	t.label = label
	HideBlizzard()
	self:Paint()
	A:RegisterTicker(self, function() TM:Tick() end)
end

function TM:Stop(kind)
	local t = self.timers and self.timers[kind]
	if not t then return end
	self.timers[kind] = nil
	for i, o in ipairs(self.order) do
		if o == t then table.remove(self.order, i) break end
	end
	self:Paint()
	if #self.order == 0 then A:UnregisterTicker(self) end
end

function TM:Pause(kind, paused)
	local t = self.timers and self.timers[kind]
	if not t then return end
	t.paused = (paused or 0) > 0
	self:Paint()
end

function TM:Tick()
	for _, t in ipairs(self.order or {}) do Refresh(t) end
	self:Paint()
end

--- A timer already running when we arrive - a reload underwater.
function TM:Scan()
	if not GetMirrorTimerInfo then return end
	for i = 1, NumSlots() do
		local ok, kind, value, maxvalue, _, paused, label = pcall(GetMirrorTimerInfo, i)
		if ok and kind and kind ~= "UNKNOWN" then
			self:Start(kind, value, maxvalue, paused, label)
		end
	end
end

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

function TM:OnEnable()
	self:Build()
	self:Anchor()
	self.holder:Show()
	HideBlizzard()

	A:RegisterEvent(self, "MIRROR_TIMER_START", function(_, _, kind, value, maxvalue, _, paused, label)
		TM:Start(kind, value, maxvalue, paused, label)
	end)
	A:RegisterEvent(self, "MIRROR_TIMER_STOP", function(_, _, kind) TM:Stop(kind) end)
	A:RegisterEvent(self, "MIRROR_TIMER_PAUSE", function(_, _, kind, paused) TM:Pause(kind, paused) end)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() TM:Anchor() TM:Scan() end)

	self:Scan()
end

function TM:OnDisable()
	A:UnregisterAllEvents(self)
	A:UnregisterTicker(self)
	self.timers, self.order = {}, {}
	if self.holder then self.holder:Hide() end
	RestoreBlizzard()
end

function TM:OnSkinChanged() self:Paint() end

function TM:OnConfigChanged()
	self:Anchor()
	self:Paint()
end
