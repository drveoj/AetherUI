--[[--------------------------------------------------------------------------
	Lattice :: Onboard

	The first run, as a GROWTH (onboarding v2, as Joe amended it). The screen
	starts dark with only your own frame on it, and each stop grows the next
	piece of the lattice out of the last, asks one thing about it, and applies
	the answer live: the spine, what hangs off it, the bars, the two trunks,
	the skin, a fight, the map, and the layout as one line to share.

	THE PIECES ARE THE REAL FRAMES. Nothing here is a drawing of the HUD. A
	piece not grown yet is held at nothing - through the fader for the frames
	it watches, by its own alpha for the rest - and growing it lets it back.
	Alpha only, never Hide and never a move: half of these frames are secure,
	and alpha is the one thing about them that is not protected.

	THE SCRIM DIMS THE WORLD, NOT THE HUD. It sits under every frame of ours, so
	what has grown is lit and usable - the spine really drags, the trunks' nodes
	really open - and what has not is simply not there yet. It lifts a step at
	every stop and is gone at the finish.

	NOTHING IS STAGED. Every control writes straight into the system that owns
	it the moment it is touched, so quitting half way through costs nothing.

	PER CHARACTER, AND ONCE. `db.char.onboard` holds `completed` and the stop
	you reached. Finishing sets completed; so does skipping, and so does
	dismissing the resume toast - a player who has said no twice has said no.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local OB = A:NewModule("onboard")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- The design's own numbers, drawn at profile.scale like everything else.
local CALLOUT_W      = 330
local CALLOUT_PAD    = 20
local CALLOUT_GAP    = 22      -- from the element to the callout
local CARD_W         = 520     -- welcome and finish
-- THE MARK, on the welcome card. Width chosen, height taken from the art so
-- nobody squashes it: Media.logoAspect is the ink inside Logo.tga, and
-- Media.logoCoord is where that ink is.
local LOGO_W         = 300
local ARROW          = 14      -- the rotated square pointing at the element
local DOT            = 5
local TOAST_H        = 34      -- the resume toast

-- THE SKIP LINE'S OWN STRIP, ACROSS THE TOP, and the callout may not enter it:
-- the band is the line's own row plus a gap, and the vertical clamp in
-- PlaceCallout subtracts it.
local SKIP_TOP       = 44
local SKIP_H         = 24
-- Long enough for the movers to have put every frame back. The growth works
-- on real frames, and a frame not restored yet is in the wrong place.
local FIRST_RUN_DELAY = 2
local DOT_GAP        = 7

-- Timings, in seconds.
local CALLOUT_FADE   = 0.16
local GROW           = 0.16    -- one piece fading in
local STAGGER        = 0.04    -- between one frame of a piece and the next
local REDUCED        = 0.12    -- reduced motion: no stagger, this long

-- How dark the world goes: rgba(6,5,14,.78) at the welcome, a step of .08
-- lighter at each stop, and gone at the finish.
local SCRIM_RGB      = { 6 / 255, 5 / 255, 14 / 255 }
local SCRIM_TOP      = 0.78
local SCRIM_STEP     = 0.08

--- Fade one of the tour's OWN frames. Never a HUD frame: W.DriveFade takes the
--  frame's OnUpdate and hides it at nothing, which on a frame of somebody
--  else's would take its script and its visibility with it.
local function FadeTo(f, want, secs)
	if not f then return end
	f.__aetherWant = want
	f.__aetherFadeSecs = secs
	if want > 0 then f:Show() end
	W.DriveFade(f)
end

local function Reduced()
	return A.db and A.db.profile and A.db.profile.reducedMotion and true or false
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

--- The character's record. Created on demand.
local function Store()
	if not A.db or not A.db.char then return nil end
	A.db.char.onboard = A.db.char.onboard or {}
	return A.db.char.onboard
end

--- Has this character finished, skipped, or waved the toast away?
function OB:Completed()
	local s = Store()
	return (s and s.completed) and true or false
end

--- Nothing more, ever. Set by finishing, by skipping, and by dismissing the
--  resume toast.
function OB:Finish()
	local s = Store()
	if s then
		s.completed = true
		-- AND WHEN, for the alt welcome: with two characters done, the one
		-- worth naming is the one you were just playing.
		s.completedAt = (time and time()) or 0
		s.stopIndex = nil
	end
	self:Teardown()
end

--- Another character on this account that has finished or skipped, or nil.
--
--  OFF db.sv.char, WHICH IS THE WHOLE SAVED FILE rather than this character's
--  slice of it. The most recent one, by completedAt; a record written before
--  that existed reads as zero, which is "long ago".
function OB:Others()
	local sv = A.db and A.db.sv and A.db.sv.char
	local me = A.db and A.db.keys and A.db.keys.char
	if not sv then return nil end

	local bestKey, bestAt
	for key, rec in pairs(sv) do
		local ob = (key ~= me) and rec and rec.onboard
		if ob and ob.completed then
			local at = tonumber(ob.completedAt) or 0
			if not bestKey or at > bestAt
				or (at == bestAt and key < bestKey) then
				bestKey, bestAt = key, at
			end
		end
	end
	if not bestKey then return nil end
	-- AceDB builds the key as "Name - Realm"; the name is the half worth saying.
	return bestKey, (bestKey:match("^(.-) %- ") or bestKey)
end

--- "Keep my layout" on an alt: the layout, the bars and the skin are in the
--  shared profile already, so the one thing to carry over is the Toolbox's
--  side, which is stored per character.
function OB:AdoptFrom(key)
	local sv = A.db and A.db.sv and A.db.sv.char
	local them = key and sv and sv[key]
	if not them then return false end
	local edge = them.toolbox and them.toolbox.docked
	local TB = A.GetModule and A:GetModule("toolbox")
	if edge and TB and TB.SetDock then TB:SetDock(edge) end
	return true
end

-- ---------------------------------------------------------------------------
-- the pieces
--
-- Each is a list of real frames, resolved late: on a fresh character some of
-- them do not exist yet, and a module switched off has none at all.
-- ---------------------------------------------------------------------------

local function Mod(name) return A.GetModule and A:GetModule(name) end

local function Trunk(name)
	return A.Trunk and A.Trunk:Get(name)
end

local PIECE = {}

function PIECE.you()
	local UF = Mod("unitframes")
	return { UF and UF.player }
end

function PIECE.spine()
	local UF = Mod("unitframes")
	return { UF and UF.target, UF and UF.spine }
end

function PIECE.hangers()
	local UF = Mod("unitframes")
	return { UF and UF.pet, UF and UF.tot }
end

function PIECE.bars()
	local AB, out = Mod("actionbars"), {}
	for _, bar in ipairs((AB and AB.bars) or {}) do out[#out + 1] = bar.dock end
	return out
end

function PIECE.trunks()
	local TB, MM = Mod("toolbox"), Mod("minimap")
	local tb, wt = Trunk("toolbox"), Trunk("world")
	return { TB and TB.root, tb and tb.frame, MM and MM.frame, MM and MM.pill,
		wt and wt.frame }
end

--- Every frame of the HUD the growth holds back: everything the movers place,
--  everything the fader dims, the trunks, the XP hairline and the resource
--  tray. Nameplates are the world's, and the tour's own frames are not here.
function OB:HudFrames()
	local set, list = {}, {}
	local function add(f)
		if f and f.SetAlpha and not set[f] then set[f] = true list[#list + 1] = f end
	end
	for _, entry in pairs((A.Movers and A.Movers.registry) or {}) do add(entry.frame) end
	for f in pairs((A.Fader and A.Fader.watched) or {}) do add(f) end
	for _, f in ipairs(PIECE.trunks()) do add(f) end
	local XP, RS = Mod("xpbar"), Mod("resources")
	add(XP and XP.frame)
	add(RS and RS.tray)
	return list
end

-- What grows when: the welcome (0) grows you, each of the first four stops
-- grows its piece, and the finish grows everything still held.
local GROWS = { [0] = { "you" }, { "spine" }, { "hangers" }, { "bars" }, { "trunks" } }

-- ---------------------------------------------------------------------------
-- holding back, and growing
-- ---------------------------------------------------------------------------

--- Hold one frame at nothing, remembering how to let it go.
local function Veil(f)
	if not f or OB.veil[f] then return end
	local rec = { alpha = f:GetAlpha() or 1 }
	if A.Fader and A.Fader:Hold(f, 0) then
		rec.fader = true
	else
		f:SetAlpha(0)
	end
	OB.veil[f] = rec
end

--- Let one held frame go, now.
local function Release(f, rec)
	if rec.fader then
		if not (A.Fader and A.Fader:Hold(f, nil)) then f:SetAlpha(rec.alpha) end
	else
		f:SetAlpha(rec.alpha)
	end
end

--- The driver for growing pieces: the tour's own frame, its own OnUpdate.
local function Grower()
	if OB.grower then return OB.grower end
	local g = CreateFrame("Frame")
	g:Hide()
	g:SetScript("OnUpdate", function(self, dt)
		self.at = (self.at or 0) + (dt or 0)
		for i = #OB.jobs, 1, -1 do
			local j = OB.jobs[i]
			local t = self.at - j.delay
			if t >= 0 then
				if j.rec.fader then
					Release(j.frame, j.rec)
					table.remove(OB.jobs, i)
				else
					local p = math.min(1, t / j.dur)
					j.frame:SetAlpha(j.rec.alpha * p)
					if p >= 1 then table.remove(OB.jobs, i) end
				end
			end
		end
		if #OB.jobs == 0 then self:Hide() end
	end)
	OB.grower = g
	return g
end

--- Every growth in flight, finished now. Leaving the tour and a fight both
--  come through here, and so does the harness, which has no frames to tick.
function OB:FinishGrowth()
	for _, j in ipairs(self.jobs or {}) do Release(j.frame, j.rec) end
	self.jobs = {}
	if self.grower then self.grower:Hide() end
end

--- Grow one piece: its frames come back one after another, 40 ms apart.
function OB:GrowPiece(key)
	if self.grown[key] then return end
	self.grown[key] = true
	local frames
	if key == "rest" then
		frames = {}
		for f in pairs(self.veil) do frames[#frames + 1] = f end
	else
		frames = PIECE[key] and PIECE[key]() or {}
	end
	local reduced = Reduced()
	local g = Grower()
	-- From now on the driver's own clock, so a piece grown while another is
	-- still coming in waits its turn rather than arriving already late.
	if not g:IsShown() then g.at = 0 end
	local base, n = g.at or 0, 0
	for _, f in ipairs(frames) do
		local rec = f and self.veil[f]
		if rec then
			self.veil[f] = nil
			self.jobs[#self.jobs + 1] = {
				frame = f, rec = rec,
				delay = base + (reduced and 0 or n * STAGGER),
				dur = reduced and REDUCED or GROW,
			}
			n = n + 1
		end
	end
	if #self.jobs > 0 then g:Show() end
end

--- Hold the whole HUD back, once per run of the tour.
function OB:Hold()
	if self.holding then return end
	self.holding = true
	self.veil, self.jobs, self.grown = {}, {}, {}
	for _, f in ipairs(self:HudFrames()) do Veil(f) end
end

--- Everything the tour has grown so far, through stop `index` (0 is the
--  welcome).
function OB:GrowTo(index)
	self:Hold()
	for s = 0, math.min(index, #GROWS) do
		for _, key in ipairs(GROWS[s] or {}) do self:GrowPiece(key) end
	end
end

--- The whole HUD back, at once. Every way out of the tour comes through here.
function OB:LetGo()
	self:FinishGrowth()
	for f, rec in pairs(self.veil or {}) do Release(f, rec) end
	self.veil, self.jobs, self.grown = {}, {}, {}
	self.holding = nil
end

--- Is this frame held back right now?
function OB:Held(f)
	return (self.veil and self.veil[f]) and true or false
end

-- ---------------------------------------------------------------------------
-- the stops
-- ---------------------------------------------------------------------------

--- Every stop, in order. A SET stop carries a control; a SHOW stop plays or
--  opens something. `unlock` is the set of frames a stop unlocks for
--  dragging; `target` what the callout points at, or nothing; `anchor` a
--  fixed place for the callout instead.
OB.stops = {
	{
		key = "spine", name = L.tour.spine.name, head = L.tour.spine.head,
		body = L.tour.spine.body, kind = "set",
		unlock = { player = true, target = true },
		target = function() local UF = Mod("unitframes") return UF and UF.target end,
	},
	{
		key = "hangers", name = L.tour.hangers.name, head = L.tour.hangers.head,
		body = L.tour.hangers.body, kind = "set",
		unlock = { player = true, target = true, pet = true, targettarget = true },
		target = function() local UF = Mod("unitframes") return UF and UF.target end,
	},
	{
		key = "bars", name = L.tour.bars.name, head = L.tour.bars.head,
		body = L.tour.bars.body, kind = "set",
		target = function()
			local AB = Mod("actionbars")
			for _, bar in ipairs((AB and AB.bars) or {}) do
				if bar.id == "1" then return bar.dock end
			end
		end,
	},
	{
		key = "trunks", name = L.tour.trunks.name, head = L.tour.trunks.head,
		-- The sides as they are: the Toolbox can be docked right, and then the
		-- world is on the left.
		body = function()
			local docked = A.db and A.db.char and A.db.char.toolbox
				and A.db.char.toolbox.docked
			return docked == "RIGHT" and L.tour.trunks.body_right or L.tour.trunks.body_left
		end,
		kind = "show",
		target = function() return nil end,
	},
	{
		key = "skin", name = L.tour.skin.name, head = L.tour.skin.head,
		body = L.tour.skin.body, kind = "set",
		target = function() local UF = Mod("unitframes") return UF and UF.player end,
	},
	{
		key = "fight", name = L.tour.fight.name, head = L.tour.fight.head,
		body = L.tour.fight.body, kind = "show",
		target = function() local UF = Mod("unitframes") return UF and UF.player end,
	},
	{
		key = "map", name = L.tour.map.name, head = L.tour.map.head,
		body = L.tour.map.body, kind = "show",
		-- THE REAL WINDOW, over the HUD that was just built - and shut again on
		-- the way out, whoever leaves.
		before = function()
			if not (A.Options and A.Options.Open) then return end
			A.Options:Open()
			OB:OnLeave(function() if A.Options.Close then A.Options:Close() end end)
		end,
		target = function() return nil end,
		-- Under the window, which sits near the top: beside it there is no room.
		anchor = { "BOTTOM", "BOTTOM", 0, 90 },
	},
	{
		key = "share", name = L.tour.share.name, head = L.tour.share.head,
		body = L.tour.share.body, kind = "show",
		before = function()
			local LY = A.Layout
			if not (LY and LY.Show) then return end
			LY:Show()
			OB:OnLeave(function() if LY.frame then LY.frame:Hide() end end)
		end,
		target = function() return nil end,
		anchor = { "BOTTOM", "BOTTOM", 0, 90 },
	},
}

OB.COUNT = #OB.stops

--- Put a frame at the scale the rest of the HUD is drawn at.
local function Rescale(f)
	if not f or not f.SetScale then return end
	local scale = (A.db and A.db.profile and A.db.profile.scale) or 1
	if type(scale) ~= "number" or scale <= 0 then scale = 1 end
	f:SetScale(scale)
end

-- ---------------------------------------------------------------------------
-- the scrim
-- ---------------------------------------------------------------------------

--- The dim over the world.
--
--  ANCHORED TO WorldFrame, the physical screen whatever the UI Scale says.
--
--  STRATA `BACKGROUND`, under every frame of ours: it dims the world and
--  nothing else. A piece of the HUD that has grown is lit and works; one that
--  has not is held at nothing, so there is nothing under here to hide.
--
--  The tour's own frames are its children - at the profile's scale through
--  this one SetScale - with strata of their own above everything.
local function BuildScrim()
	if OB.scrim then return OB.scrim end

	local f = CreateFrame("Frame", ADDON .. "OnboardScrim")
	f:SetFrameStrata("BACKGROUND")
	f:SetFrameLevel(0)
	f:SetAllPoints(WorldFrame or UIParent)
	Rescale(f)
	-- The world's clicks stop here while the tour is up: a camera swung by a
	-- stray click is a scene that moved under the callout.
	f:EnableMouse(true)
	f:Hide()

	local tint = f:CreateTexture(nil, "BACKGROUND")
	tint:SetAllPoints(f)
	tint:SetTexture(A.Media.texture.flat)
	f.tint = tint

	OB.scrim = f
	return f
end

--- The scrim's weight for a stop (0 the welcome); `false` takes it away.
local function Dim(index)
	local f = BuildScrim()
	local a = 0
	if index then a = math.max(0, SCRIM_TOP - SCRIM_STEP * index) end
	f.tint:SetVertexColor(SCRIM_RGB[1], SCRIM_RGB[2], SCRIM_RGB[3], a)
	f.dim = a
	f:Show()
end

-- ---------------------------------------------------------------------------
-- the callout
-- ---------------------------------------------------------------------------

--- The glass panel that carries a stop. Built once and refilled.
local function BuildCallout()
	if OB.callout then return OB.callout end

	local c = Glass.CreatePanel(BuildScrim(), {
		corner = 20, fill = "dialogFill", edge = "glassEdgeHi", shadow = 0.6,
	})
	c:SetFrameStrata("FULLSCREEN_DIALOG")
	c:SetWidth(CALLOUT_W)
	c:EnableMouse(true)
	c:Hide()

	local arrow = c:CreateTexture(nil, "BACKGROUND")
	arrow:SetSize(ARROW, ARROW)
	arrow:SetTexture(A.Media.texture.flat)
	arrow:Hide()
	c.arrow = arrow

	c.kicker = W.Text(c, "tbSection", "LEFT")
	c.kicker:SetPoint("TOPLEFT", c, "TOPLEFT", CALLOUT_PAD, -CALLOUT_PAD)

	c.head = W.Text(c, "tbTitle", "LEFT")
	c.head:SetPoint("TOPLEFT", c.kicker, "BOTTOMLEFT", 0, -8)
	c.head:SetWidth(CALLOUT_W - CALLOUT_PAD * 2)
	c.head:SetWordWrap(true)

	c.body = W.Text(c, "tbCardBody", "LEFT")
	c.body:SetPoint("TOPLEFT", c.head, "BOTTOMLEFT", 0, -8)
	c.body:SetWidth(CALLOUT_W - CALLOUT_PAD * 2)
	c.body:SetWordWrap(true)

	-- WHERE A STOP'S OWN THING GOES. Every stop anchors its content to this and
	-- reports a height.
	c.slot = CreateFrame("Frame", nil, c)
	c.slot:SetPoint("TOPLEFT", c.body, "BOTTOMLEFT", 0, -12)
	c.slot:SetWidth(CALLOUT_W - CALLOUT_PAD * 2)
	c.slot:SetHeight(1)

	OB.callout = c
	return c
end

--- The footer: Back, the dots, Next.
local function BuildNav(c)
	if c.nav then return c.nav end

	local nav = CreateFrame("Frame", nil, c)
	nav:SetPoint("LEFT", c, "LEFT", CALLOUT_PAD, 0)
	nav:SetPoint("RIGHT", c, "RIGHT", -CALLOUT_PAD, 0)
	nav:SetHeight(28)
	c.nav = nav

	-- BACK IS QUIET, and it is always there - greyed on stop 1 rather than
	-- removed, so the footer never jumps. A word, not a glass button.
	local back = CreateFrame("Button", nil, nav)
	back:SetSize(52, 24)
	back:SetPoint("LEFT", nav, "LEFT", 0, 0)
	back.label = W.Text(back, "tbLabel", "CENTER")
	back.label:SetPoint("CENTER")
	back.label:SetText(L.tour.nav.back)
	back:SetScript("OnClick", function() OB:Back() end)
	nav.back = back

	local next_ = W.CreateButton(nav, { corner = 12 })
	next_:SetSize(64, 24)
	next_:SetPoint("RIGHT", nav, "RIGHT", 0, 0)
	next_.label = W.Text(next_, "tbLabel", "CENTER")
	next_.label:SetPoint("CENTER")
	next_.label:SetText(L.tour.nav.next)
	next_:SetScript("OnClick", function() OB:Next() end)
	nav.next = next_

	nav.dots = {}
	for i = 1, OB.COUNT do
		local d = nav:CreateTexture(nil, "ARTWORK")
		d:SetSize(DOT, DOT)
		d:SetTexture(A.Media.texture.chipDisc)
		nav.dots[i] = d
	end
	local span = OB.COUNT * DOT + (OB.COUNT - 1) * DOT_GAP
	for i, d in ipairs(nav.dots) do
		d:SetPoint("LEFT", nav, "CENTER",
			-span / 2 + (i - 1) * (DOT + DOT_GAP), 0)
	end

	return nav
end

--- Paint the footer for a stop: done 40 %, this one in the accent, to come 25 %.
local function PaintNav(nav, index)
	local c = Palette.c
	for i, d in ipairs(nav.dots) do
		local a = (i == index) and 1 or (i < index and 0.4 or 0.25)
		W.Tint(d, c.accent, a)
	end
	local first = index <= 1
	W.Color(nav.back.label, first and c.textFaint or c.textDim)
	nav.back:EnableMouse(not first)
	nav.next.label:SetText(index >= OB.COUNT and L.tour.nav.finish or L.tour.nav.next)
end

-- ---------------------------------------------------------------------------
-- placing the callout
-- ---------------------------------------------------------------------------

--- Beside the element, and never off the screen - or at a stop's fixed place.
--
--  MEASURED IN SCREEN PIXELS, WRITTEN BACK IN THE CALLOUT'S OWN UNITS: every
--  frame here is drawn at the profile's scale, so `cs` is taken once,
--  everything below is pixels, and the division happens at the anchors.
local function PlaceCallout(c, frame, anchor)
	c:ClearAllPoints()
	c.arrow:Hide()
	c.__aetherAt = nil

	local cs = c:GetEffectiveScale() or 1
	if cs <= 0 then cs = 1 end

	if anchor then
		local us = UIParent:GetEffectiveScale() or 1
		c:SetPoint(anchor[1], UIParent, anchor[2], anchor[3] * us / cs, anchor[4] * us / cs)
		return
	end

	local sw = (UIParent:GetWidth() or 0) * (UIParent:GetEffectiveScale() or 1)
	local sh = (UIParent:GetHeight() or 0) * (UIParent:GetEffectiveScale() or 1)
	local cw, ch = (c:GetWidth() or 0) * cs, (c:GetHeight() or 0) * cs

	if not frame or not frame.GetCenter or not frame:GetCenter()
		or sw <= 0 or sh <= 0 then
		c:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		return
	end

	local fs = frame:GetEffectiveScale() or 1
	local fx, fy = frame:GetCenter()
	fx, fy = fx * fs, fy * fs
	local halfW = ((frame:GetWidth() or 0) * fs) / 2

	local onRight = fx < sw / 2
	local gap = CALLOUT_GAP * cs
	local x = onRight and (fx + halfW + gap + cw / 2)
		or (fx - halfW - gap - cw / 2)
	local y = fy

	-- INSIDE THE SCREEN, both ways, and under the skip line's band.
	local m = 16 * cs
	local wantX = x
	local ceiling = sh - ch / 2 - m - (SKIP_TOP + SKIP_H) * cs
	x = math.max(cw / 2 + m, math.min(sw - cw / 2 - m, x))
	y = math.max(ch / 2 + m, math.min(ceiling, y))

	c:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / cs, y / cs)

	-- WHERE IT WENT, IN NUMBERS, kept on the frame: the arithmetic above is the
	-- thing that has gone wrong before, and the harness reads the sum.
	c.__aetherAt = { x = x, y = y, w = cw, h = ch,
		sw = sw, sh = sh, onRight = onRight, wantX = wantX, scale = cs }

	-- THE ARROW FOLLOWS THE ELEMENT, and only while it can reach it.
	if math.abs(x - wantX) > cw / 2 then return end
	local dy = fy - y
	if math.abs(dy) > ch / 2 - ARROW * cs then return end

	local edge = onRight and "LEFT" or "RIGHT"
	c.arrow:ClearAllPoints()
	c.arrow:SetPoint("CENTER", c, edge, 0, dy / cs)
	c.__aetherAt.edge, c.__aetherAt.dy = edge, dy
	W.Tint(c.arrow, Palette.c.dialogFill, 1)
	c.arrow:Show()
end

--- Tall enough for what is in it, and no taller.
local function SizeCallout(c)
	local h = CALLOUT_PAD
		+ (c.kicker:GetStringHeight() or 0) + 8
		+ (c.head:GetStringHeight() or 0) + 8
		+ (c.body:GetStringHeight() or 0) + 12
		+ (c.slot:GetHeight() or 0) + 14
		+ 28 + CALLOUT_PAD
	c:SetHeight(h)
	c.nav:ClearAllPoints()
	c.nav:SetPoint("LEFT", c, "LEFT", CALLOUT_PAD, 0)
	c.nav:SetPoint("RIGHT", c, "RIGHT", -CALLOUT_PAD, 0)
	c.nav:SetPoint("BOTTOM", c, "BOTTOM", 0, CALLOUT_PAD - 6)
end

-- ---------------------------------------------------------------------------
-- the skip line
-- ---------------------------------------------------------------------------

--- "Skip — use the defaults", across the top of the screen at every stop.
local function BuildSkip()
	if OB.skip then return OB.skip end

	local b = CreateFrame("Button", nil, BuildScrim())
	b:SetFrameStrata("FULLSCREEN_DIALOG")
	b:SetSize(220, SKIP_H)
	b:SetPoint("TOP", UIParent, "TOP", 0, -SKIP_TOP)

	b.label = W.Text(b, "tbLabel", "CENTER")
	b.label:SetPoint("CENTER")
	b.label:SetText(L.tour.skip)
	W.Color(b.label, Palette.c.textFaint)

	b:SetScript("OnEnter", function() W.Color(b.label, Palette.c.textDim) end)
	b:SetScript("OnLeave", function() W.Color(b.label, Palette.c.textFaint) end)
	b:SetScript("OnClick", function() OB:Skip() end)
	b:Hide()

	OB.skip = b
	return b
end

-- ---------------------------------------------------------------------------
-- leaving a stop
-- ---------------------------------------------------------------------------

--- Anything a stop changed out in the world, put back: ONE LIST, POPPED IN
--  REVERSE, and every route out of a stop goes through it - Go on the way to
--  the next stop, and Teardown for finishing, skipping, a fight starting and
--  the module being switched off.
function OB:Undo()
	local list = self.__undo
	self.__undo = nil
	for i = #(list or {}), 1, -1 do pcall(list[i]) end
end

--- Do this when the stop is left, whatever leaves it.
function OB:OnLeave(fn)
	if type(fn) ~= "function" then return end
	self.__undo = self.__undo or {}
	self.__undo[#self.__undo + 1] = fn
end

--- Run `step(at)` on the slot's own OnUpdate until it returns false or the
--  stop is left. The opening frame now, not a frame late.
local function Play(slot, step)
	if step(0) == false then return end
	local at = 0
	slot:SetScript("OnUpdate", function(self, dt)
		at = at + (dt or 0)
		if step(at) == false then self:SetScript("OnUpdate", nil) end
	end)
	OB:OnLeave(function() slot:SetScript("OnUpdate", nil) end)
end

-- ---------------------------------------------------------------------------
-- the slot's frames
-- ---------------------------------------------------------------------------

--- Everything a stop put in the slot, gone. Pooled, because frames cannot be
--  destroyed and the tour can be run as often as somebody likes.
function OB:ClearSlot(slot)
	slot.__aetherKids = slot.__aetherKids or {}
	slot:SetScript("OnUpdate", nil)
	for _, pool in pairs(slot.__aetherKids) do
		for _, f in ipairs(pool) do
			f:Hide()
			f:ClearAllPoints()
			-- ASKED FIRST: the client throws on SetScript for a script the type
			-- has not got, clearing one as much as setting one.
			if f.HasScript and f:HasScript("OnClick") then f:SetScript("OnClick", nil) end
			if f.HasScript and f:HasScript("OnEnter") then
				f:SetScript("OnEnter", nil)
				f:SetScript("OnLeave", nil)
			end
		end
	end
end

--- One frame out of the slot's pool, built by `make` the first time. A pool
--  per kind: the controls' frames are not interchangeable.
local function Kid(slot, kind, i, make)
	slot.__aetherKids = slot.__aetherKids or {}
	slot.__aetherKids[kind] = slot.__aetherKids[kind] or {}
	local pool = slot.__aetherKids[kind]
	local f = pool[i]
	if not f then
		f = make(slot)
		pool[i] = f
	end
	f:Show()
	return f
end

--- A card lit or not: the accent rim is the whole signal.
local function Chosen(card, on)
	local c = Palette.c
	if card.SetFillColor then
		card:SetFillColor(on and c.glassEdgeHi or c.glass)
		card:SetEdgeColor(on and c.accent or c.glassEdge)
	end
	if card.label then W.Color(card.label, on and c.text or c.textDim) end
end

-- ---------------------------------------------------------------------------
-- stops 1 and 2: unlocked
-- ---------------------------------------------------------------------------

--- Unlock what a stop teaches - quietly, with no chat lines and no LOCK pill -
--  and lock again on the way out.
local function Unlocked(stop)
	local MV = A.Movers
	if not (stop.unlock and MV and MV.Unlock) then return end
	MV:Unlock(stop.unlock, true)
	OB:OnLeave(function() if MV.unlocked then MV:Lock(true) end end)
end

local NUDGE, NUDGE_AT, NUDGE_FOR = 12, 4, 0.3

--- The player's centre now, to tell a drag from stillness.
local function Where()
	local UF = Mod("unitframes")
	local f = UF and UF.player
	if not (f and f.GetCenter) then return nil end
	return f:GetCenter()
end

--- One handle offset toward its parent by `d`, or put back on its frame.
local function Lean(name, d)
	local MV = A.Movers
	local entry = MV and MV.registry[name]
	local h = entry and entry.handle
	if not (h and entry.frame) then return end
	h:ClearAllPoints()
	if not d or d == 0 then
		h:SetAllPoints(entry.frame)
		return
	end
	local parent = MV.registry[entry.parent or ""]
	local px, py
	if parent and parent.frame then px, py = parent.frame:GetCenter() end
	local cx, cy = entry.frame:GetCenter()
	local dx, dy = 0, 1
	if px and cx then
		local len = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
		if len > 0 then dx, dy = (px - cx) / len, (py - cy) / len end
	end
	h:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", dx * d, dy * d)
	h:SetPoint("BOTTOMRIGHT", entry.frame, "BOTTOMRIGHT", dx * d, dy * d)
end

local TOGGLE_H = 24

--- Two switches, Target of target and Pet, writing the capsules live - and
--  the lesson: drag the spine and the callout notices; leave it four seconds
--  and the two hangers lean toward their parents once.
local function HangersControl(slot)
	local UF = Mod("unitframes")
	local rows = {
		{ key = "targettarget", label = L.tour.hangers.tot },
		{ key = "pet", label = L.tour.hangers.pet, note = L.tour.hangers.pet_note },
	}
	for i, row in ipairs(rows) do
		local b = Kid(slot, "hangers", i, function(parent)
			local f = CreateFrame("Button", nil, parent)
			f:SetHeight(TOGGLE_H)
			f.d = f:CreateTexture(nil, "ARTWORK")
			f.d:SetTexture(Media.texture.diamond)
			f.d:SetSize(14, 14)
			f.d:SetPoint("LEFT", f, "LEFT", 2, 0)
			f.label = W.Text(f, "tbCardBody", "LEFT")
			f.label:SetPoint("LEFT", f.d, "RIGHT", 10, 0)
			f.note = W.Text(f, "tbLabel", "LEFT")
			f.note:SetPoint("LEFT", f.label, "RIGHT", 6, 0)
			f.state = W.Text(f, "tbLabel", "RIGHT")
			f.state:SetPoint("RIGHT", f, "RIGHT", 0, 0)
			return f
		end)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -(i - 1) * (TOGGLE_H + 6))
		b:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
		local on = UF and UF.SatelliteOn and UF:SatelliteOn(row.key) or false
		local c = Palette.c
		W.Tint(b.d, c.accent, on and 1 or 0.3)
		b.label:SetText(row.label)
		W.Color(b.label, on and c.text or c.textDim)
		b.note:SetText(row.note or "")
		W.Color(b.note, c.textFaint)
		b.state:SetText(on and L.tour.hangers.on or L.tour.hangers.off)
		W.Color(b.state, on and c.accent or c.textFaint)
		b.key, b.on = row.key, on
		b:SetScript("OnClick", function()
			if UF and UF.SetSatellite and UF:SetSatellite(row.key, not on) then
				-- Part of what this stop has grown: a capsule switched on here
				-- arrives lit, not held.
				local f = (row.key == "pet") and UF.pet or UF.tot
				if f and OB.veil and OB.veil[f] then
					Release(f, OB.veil[f])
					OB.veil[f] = nil
				end
				OB:Go(OB.index or 2)
			end
		end)
	end
	slot:SetHeight(#rows * TOGGLE_H + (#rows - 1) * 6)

	-- THE LESSON. A drag is the player's centre moving; the callout says so.
	local x0, y0 = Where()
	local dragged, leaned = false, false
	OB:OnLeave(function() Lean("pet", 0) Lean("targettarget", 0) end)
	Play(slot, function(at)
		if not dragged then
			local x, y = Where()
			if x0 and x and (math.abs(x - x0) > 1 or math.abs(y - y0) > 1) then
				dragged = true
				OB.callout.head:SetText(L.tour.hangers.head_dragged)
				Lean("pet", 0)
				Lean("targettarget", 0)
			end
		end
		if not dragged and not leaned and at >= NUDGE_AT then
			-- One beat, out and back: 12 toward the parent over 300 ms.
			local t = at - NUDGE_AT
			if t >= NUDGE_FOR then
				leaned = true
				Lean("pet", 0)
				Lean("targettarget", 0)
			else
				local d = NUDGE * math.sin(math.pi * t / NUDGE_FOR)
				Lean("pet", d)
				Lean("targettarget", d)
			end
		end
		return true
	end)
end

-- ---------------------------------------------------------------------------
-- stop 3: the bars' shape
-- ---------------------------------------------------------------------------

local CARD_H = 62

--- A wireframe of an arrangement, drawn from the arrangement itself: the
--  player, the target, and the bars this preset switches on. A thumbnail has
--  one job, which is telling arrangements apart at a glance.
local SHOWN = { player = true, target = true }

local function Wireframe(box, preset)
	box.marks = box.marks or {}
	for _, m in ipairs(box.marks) do m:Hide() end

	local bw, bh = box:GetWidth(), box:GetHeight()
	if not bw or bw <= 0 or not bh or bh <= 0 then return end

	local at, sw, sh = A.Layout:Resolve(preset.decoded)
	if sw <= 0 or sh <= 0 then return end

	local n = 0
	local function mark(p, wide, strong, tall, block)
		n = n + 1
		local m = box.marks[n]
		if not m then
			m = box:CreateTexture(nil, "OVERLAY")
			m:SetTexture(A.Media.texture.flat)
			box.marks[n] = m
		end
		if block then
			m:SetSize(bh * 0.3 * block, bh * 0.3)
		elseif tall then
			m:SetSize(math.max(2, bh * 0.11), bh * 0.45)
		else
			m:SetSize(bw * (wide and 0.30 or 0.20), math.max(2, bh * 0.11))
		end
		m:ClearAllPoints()
		m:SetPoint("CENTER", box, "CENTER", p.x / sw * bw, p.y / sh * bh)
		W.Tint(m, Palette.c.accent, strong and 0.75 or 0.4)
		m:Show()
	end

	for name in pairs(SHOWN) do
		if at[name] then mark(at[name], false, true) end
	end
	for id in pairs(preset.bars or {}) do
		local p = at["bar" .. id]
		local r = preset.decoded.records["bar" .. id]
		local block = r and r.rows and r.rows > 1 and r.cols > 1 and r.cols / r.rows
		if p then mark(p, true, false, r and r.rows and r.rows > r.cols, block) end
	end
end

--- Three shapes - Rows, Block, Split - and tapping one moves every bar the
--  shape places, live.
local function BarsControl(slot)
	local P = A.Presets
	if not P then slot:SetHeight(1) return end

	local keys = P.order
	local gap = 7
	local w = (slot:GetWidth() - gap * (#keys - 1)) / #keys
	local now = P:Current()

	for i, key in ipairs(keys) do
		local preset = P.list[key]
		local card = Kid(slot, "layout", i, function(parent)
			local f = Glass.CreatePanel(parent, { frameType = "Button", corner = 11 })
			f.box = CreateFrame("Frame", nil, f)
			f.box:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
			f.box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
			f.box:SetHeight(34)
			f.label = W.Text(f, "tbLabel", "CENTER")
			f.label:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)
			return f
		end)
		card:SetSize(w, CARD_H)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", slot, "TOPLEFT", (i - 1) * (w + gap), 0)
		card.box:SetWidth(w - 12)
		Wireframe(card.box, preset)
		card.label:SetText(preset.label or key)
		Chosen(card, now == key)
		card:SetScript("OnClick", function()
			P:Apply(key)
			OB:Go(OB.index or 3)
		end)
	end
	slot:SetHeight(CARD_H)
end

-- ---------------------------------------------------------------------------
-- stop 4: the trunks
-- ---------------------------------------------------------------------------

--- Every branch shut, on both trunks: a node opened as a preview closes on
--  Next.
local function ShutBranches()
	local TB = Mod("toolbox")
	if TB and TB.IsOpen and TB:IsOpen() and TB.SetOpen then TB:SetOpen(false, true) end
	local wt = Trunk("world")
	for _, node in ipairs((wt and wt.nodes) or {}) do
		if node.isOpen and node.isOpen() and node.close then node.close(node) end
	end
	if wt and wt.frame then wt:Paint() end
end

local function TrunksDemo(slot)
	OB:OnLeave(ShutBranches)
	slot:SetHeight(1)
end

-- ---------------------------------------------------------------------------
-- stop 5: the skin
-- ---------------------------------------------------------------------------

local TILE, TILE_GAP, ROW_GAP, FAMILY_W = 22, 6, 6, 58
local PREVIEW_IN, PREVIEW_OUT = 0.12, 0.2

local FAMILY_NAME = {
	sky     = L.options.general.skin.sky,
	gem     = L.options.general.skin.gem,
	seasons = L.options.general.skin.seasons,
}

--- The skin worn now by preview, or nil.
OB.preview = nil

--- Try a skin on, or nil to put the chosen one back.
function OB:Preview(key)
	if key == self.preview then return end
	self.preview = key
	A:Restyle(key)
	local foot = self.callout and self.callout.slot.__aetherFoot
	if foot then
		local skin = Palette.skins[key or Palette.current]
		foot:SetText((skin and skin.label) or "")
	end
end

--- Three rows - Sky, Gem, Seasons - of the picker's tile at 22 px. Hover tries
--  one on (120 ms in, back 200 ms after leaving); a click keeps it.
local function SkinControl(slot)
	local fams = Palette.families or {}
	local want

	local function hover(key)
		want = key
		local function go()
			if want == key then OB:Preview(key) end
		end
		if C_Timer and C_Timer.After then C_Timer.After(PREVIEW_IN, go) else go() end
	end
	local function leave()
		want = nil
		local function back()
			if want == nil and OB.preview then OB:Preview(nil) end
		end
		if C_Timer and C_Timer.After then C_Timer.After(PREVIEW_OUT, back) else back() end
	end
	OB:OnLeave(function() want = nil if OB.preview then OB:Preview(nil) end end)

	local n = 0
	for r, fam in ipairs(fams) do
		local head = Kid(slot, "skinHead", r, function(parent)
			local t = CreateFrame("Frame", nil, parent)
			t:SetSize(FAMILY_W, TILE)
			t.text = W.Text(t, "opSub", "LEFT")
			t.text:SetPoint("LEFT", t, "LEFT", 0, 0)
			return t
		end)
		head:ClearAllPoints()
		head:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -(r - 1) * (TILE + ROW_GAP))
		head.text:SetText(A.Trunk.Spaced(FAMILY_NAME[fam.key] or fam.key))
		W.Color(head.text, Palette.c.textDim)

		for col, key in ipairs(fam.skins) do
			n = n + 1
			local tile = Kid(slot, "skin", n, function(parent)
				local f = Glass.CreatePanel(parent, { frameType = "Button", corner = 6 })
				f:SetSize(TILE, TILE)
				f.glow = f:CreateTexture(nil, "ARTWORK")
				f.glow:SetTexture(Media.texture.glow)
				f.glow:SetSize(18, 18)
				f.glow:SetPoint("CENTER")
				f.glow:SetBlendMode("ADD")
				f.dot = f:CreateTexture(nil, "OVERLAY")
				f.dot:SetTexture(Media.texture.diamond)
				f.dot:SetSize(8, 8)
				f.dot:SetPoint("CENTER")
				return f
			end)
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", slot, "TOPLEFT", FAMILY_W + (col - 1) * (TILE + TILE_GAP),
				-(r - 1) * (TILE + ROW_GAP))
			tile.key = key
			-- ITS OWN SKIN, as the options picker draws it: the tile shows what
			-- picking it would give.
			local skin = Palette.skins[key]
			local on = (A.db.profile.skin or "midnight") == key
			if skin then
				local g, e, a = skin.nodeFill, skin.glassEdge, skin.accent
				tile:SetFillColor({ g[1], g[2], g[3], 0.88 })
				tile:SetEdgeColor(on and { a[1], a[2], a[3], 1 } or { e[1], e[2], e[3], 0.5 })
				tile.dot:SetVertexColor(a[1], a[2], a[3], 1)
				if skin.family == "gem" then
					tile.glow:SetVertexColor(a[1], a[2], a[3], 0.7)
					tile.glow:Show()
				else
					tile.glow:Hide()
				end
			end
			tile.on = on
			tile:SetScript("OnEnter", function() hover(key) end)
			tile:SetScript("OnLeave", leave)
			tile:SetScript("OnClick", function()
				want = nil
				OB.preview = nil
				A.db.profile.skin = key
				A:Restyle()
				OB:Go(OB.index or 5)
			end)
		end
	end

	local rows = #fams
	local foot = Kid(slot, "skinFoot", 1, function(parent)
		local t = CreateFrame("Frame", nil, parent)
		t:SetHeight(14)
		t.text = W.Text(t, "tbLabel", "LEFT")
		t.text:SetPoint("LEFT")
		return t
	end)
	foot:ClearAllPoints()
	foot:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -rows * (TILE + ROW_GAP) - 2)
	foot:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
	local skin = Palette.skins[Palette.current]
	foot.text:SetText((skin and skin.label) or "")
	W.Color(foot.text, Palette.c.textDim)
	slot.__aetherFoot = foot.text
	slot:SetHeight(rows * (TILE + ROW_GAP) + 16)
end

-- ---------------------------------------------------------------------------
-- stop 6: a fight
-- ---------------------------------------------------------------------------

local FIGHT = 3        -- the whole demo, then everything relaxes
local TARGET_CAST_AT = 0.5

--- Everything the demo changed, back.
local function Relax(state)
	if state.done then return end
	state.done = true
	local AB, TH, QT, MM, UF = Mod("actionbars"), Mod("threat"), Mod("questtracker"),
		Mod("minimap"), Mod("unitframes")
	if AB then AB.demoFight = nil end
	if A.Fader then A.Fader:Update() end
	if TH and TH.ClearPreview then TH:ClearPreview("player") end
	if QT and QT.SetCollapsed and state.collapsed ~= nil then QT:SetCollapsed(state.collapsed) end
	if MM and MM.UpdateZone then MM:UpdateZone() end
	if UF and UF.CastStop then
		UF.CastStop(UF.cast)
		UF.CastStop(UF.targetCast)
	end
end

--- Three seconds of a made-up fight on the real frames, played once: a cast
--  runs along the spine and the target's comes back, the bars wake, the
--  quests tuck into the pill and it says In combat, your frame wears the
--  warning gold - and then it all lets go.
local function FightDemo(slot)
	local state
	local function run()
		if state then Relax(state) end
		state = {}
		local AB, TH, QT, MM, UF = Mod("actionbars"), Mod("threat"), Mod("questtracker"),
			Mod("minimap"), Mod("unitframes")
		if AB then AB.demoFight = true end
		if A.Fader then A.Fader:Update() end
		if UF and UF.DemoCast then UF:DemoCast("player", L.tour.fight.my_cast, 2) end
		if TH and TH.Preview then TH:Preview("player") end
		if QT and QT.SetCollapsed then
			state.collapsed = QT.collapsed and true or false
			QT:SetCollapsed(true)
		end
		if MM and MM.SetPillState then MM:SetPillState(L.tour.fight.in_combat, Palette.c.danger) end
		local s = state
		Play(slot, function(at)
			if at >= TARGET_CAST_AT and not s.theirs then
				s.theirs = true
				if UF and UF.DemoCast then UF:DemoCast("target", L.tour.fight.their_cast, 1.8) end
			end
			if at >= FIGHT then
				Relax(s)
				return false
			end
			return true
		end)
	end
	OB:OnLeave(function() if state then Relax(state) end end)

	local replay = Kid(slot, "fight.replay", 1, function(parent)
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(80, 20)
		b.label = W.Text(b, "tbLabel", "LEFT")
		b.label:SetPoint("LEFT")
		return b
	end)
	replay:ClearAllPoints()
	replay:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
	replay.label:SetText(L.tour.fight.replay)
	W.Color(replay.label, Palette.c.accent)
	replay:SetScript("OnClick", run)
	slot:SetHeight(20)
	run()
end

--- Which control or demo a stop carries.
local FILL = {
	hangers = HangersControl,
	bars    = BarsControl,
	trunks  = TrunksDemo,
	skin    = SkinControl,
	fight   = FightDemo,
}

-- ---------------------------------------------------------------------------
-- running
-- ---------------------------------------------------------------------------

local function Text(v)
	if type(v) == "function" then return v() end
	return v
end

--- Show one stop.
function OB:Go(index)
	if index < 1 then index = 1 end
	-- WHATEVER THE LAST STOP CHANGED, PUT BACK - before anything about this one
	-- is decided.
	self:Undo()
	if index > OB.COUNT then return self:ShowFinish() end

	local stop = self.stops[index]
	if not stop then return end
	self.index = index

	-- WRITTEN THE MOMENT IT IS REACHED: a player who leaves on stop 5 comes
	-- back to stop 5.
	local s = Store()
	if s then s.stopIndex = index end

	if self.card then self.card:Hide() end
	Dim(index)
	BuildSkip():Show()
	-- The growth so far: every piece up to and including this stop's.
	self:GrowTo(index)

	local c = BuildCallout()
	BuildNav(c)

	if stop.before then stop.before() end
	Unlocked(stop)

	c.kicker:SetText(L.tour.kicker:format(index, OB.COUNT, stop.name))
	c.head:SetText(Text(stop.head))
	c.body:SetText(Text(stop.body))
	W.Color(c.kicker, Palette.c.accent)
	W.Color(c.head, Palette.c.text)
	W.Color(c.body, Palette.c.textDim)

	self:ClearSlot(c.slot)
	c.slot:SetHeight(1)
	c.slot.__aetherFoot = nil
	local fill = FILL[stop.key]
	if fill then fill(c.slot) end

	PaintNav(c.nav, index)
	SizeCallout(c)
	local target = stop.target and stop.target()
	if target and not (target.IsVisible and target:IsVisible()) then target = nil end
	PlaceCallout(c, target, stop.anchor)

	c:Show()
	c:SetAlpha(0)
	FadeTo(c, 1, CALLOUT_FADE)
end

function OB:Next()
	self:Go((self.index or 0) + 1)
end

--- BACK RESTORES NOTHING: every value was written the moment it was touched,
--  so Back only re-shows the callout you were looking at.
function OB:Back()
	if (self.index or 1) <= 1 then return end
	self:Go(self.index - 1)
end

function OB:Skip()
	self:Finish()
end

--- Everything down, the whole HUD back, nothing left changed.
function OB:Teardown()
	self:Undo()
	self:LetGo()
	if self.callout then self.callout:Hide() end
	if self.skip then self.skip:Hide() end
	if self.card then self.card:Hide() end
	if self.toast then self.toast:Hide() end
	if self.scrim then self.scrim:Hide() end
	self.index = nil
end

--- Start at the top, from a fresh character or from "Take the tour".
function OB:Start()
	if InCombatLockdown() then
		A:Print(L.tour.start.during_fight_try_again)
		return false
	end
	-- AND NOTHING LEFT IN FRONT OF IT: the options window it is most often
	-- started from, and an open Toolbox branch.
	if A.Options and A.Options.Close then A.Options:Close() end
	do
		local TB = Mod("toolbox")
		if TB and TB.IsOpen and TB:IsOpen() and TB.SetOpen then TB:SetOpen(false, true) end
	end

	local s = Store()
	if s then s.completed = nil end
	self:ShowWelcome()
	return true
end

-- ---------------------------------------------------------------------------
-- the resume toast
--
-- ONE QUIET LINE, AND ONLY ONE. Dismissing counts as skipping, which is the
-- reason there is never a second toast. On UIParent at the profile's scale: a
-- notice on the HUD with everything else.
-- ---------------------------------------------------------------------------

local function BuildToast()
	if OB.toast then return OB.toast end

	local t = Glass.CreatePanel(UIParent, {
		frameType = "Button", corner = 14,
		fill = "dialogFill", edge = "glassEdgeHi", shadow = 0.5,
	})
	t:SetFrameStrata("HIGH")
	t:SetHeight(TOAST_H)
	t:SetPoint("TOP", UIParent, "TOP", 0, -120)
	t:Hide()

	t.label = W.Text(t, "tbLabel", "LEFT")
	t.label:SetPoint("LEFT", t, "LEFT", 14, 0)

	t.go = W.Text(t, "tbLabel", "RIGHT")
	t.go:SetText(L.tour.build_toast.resume)

	t.close = W.CloseButton(t)
	t.close:SetScript("OnClick", function()
		OB:Hush()
		OB:Finish()
	end)

	t:SetScript("OnClick", function()
		OB:Hush()
		local at = (Store() and Store().stopIndex) or 1
		OB:Go(at)
	end)

	OB.toast = t
	return t
end

--- Take the toast down without answering it.
function OB:Hush()
	if self.toast then self.toast:Hide() end
end

--- "Finish setup? N stops left"
function OB:ShowResume(at)
	at = math.max(1, math.min(tonumber(at) or 1, OB.COUNT))
	local left = OB.COUNT - at + 1

	local t = BuildToast()
	t:SetScale((A.db and A.db.profile and A.db.profile.scale) or 1)
	t.label:SetText(left == 1 and L.tour.build_toast.one_left
		or L.tour.build_toast.n_left:format(left))
	W.Color(t.label, Palette.c.text)
	W.Color(t.go, Palette.c.accent)

	W.PlaceClose(t.close, t)
	t.go:ClearAllPoints()
	t.go:SetPoint("RIGHT", t.close, "LEFT", -4, 0)
	t:SetWidth(14 + math.ceil(t.label:GetStringWidth() or 0) + 16
		+ math.ceil(t.go:GetStringWidth() or 0) + 30)

	t:Show()
	t:SetAlpha(0)
	FadeTo(t, 1, CALLOUT_FADE)
	return t
end

-- ---------------------------------------------------------------------------
-- the two cards
-- ---------------------------------------------------------------------------

--- Welcome and Finish share one panel.
local function BuildCard()
	if OB.card then return OB.card end

	local c = Glass.CreatePanel(BuildScrim(), {
		corner = 24, fill = "dialogFill", edge = "glassEdgeHi", shadow = 0.6,
	})
	c:SetFrameStrata("FULLSCREEN_DIALOG")
	c:SetWidth(CARD_W)
	c:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	c:EnableMouse(true)
	c:Hide()

	c.kicker = W.Text(c, "tbSection", "LEFT")
	c.kicker:SetPoint("TOPLEFT", c, "TOPLEFT", 28, -26)

	-- THE MARK, on the welcome card: the one screen in the addon that is
	-- introducing itself.
	c.logo = c:CreateTexture(nil, "ARTWORK")
	c.logo:SetTexture(Media.texture.logo)
	c.logo:SetTexCoord(unpack(Media.logoCoord))
	c.logo:SetSize(LOGO_W, math.floor(LOGO_W / Media.logoAspect + 0.5))
	c.logo:SetPoint("TOPLEFT", c, "TOPLEFT", 28, -26)
	c.logo:Hide()

	c.head = W.Text(c, "tbTitle", "LEFT")
	c.head:SetWidth(CARD_W - 56)
	c.head:SetWordWrap(true)

	c.body = W.Text(c, "tbCardBody", "LEFT")
	c.body:SetPoint("TOPLEFT", c.head, "BOTTOMLEFT", 0, -10)
	c.body:SetWidth(CARD_W - 56)
	c.body:SetWordWrap(true)

	c.lines = {}
	for i = 1, 3 do
		local t = W.Text(c, "tbCardBody", "LEFT")
		t:SetWidth(CARD_W - 56)
		t:SetWordWrap(true)
		t:Hide()
		c.lines[i] = t
	end

	c.go = W.CreateButton(c, { corner = 12 })
	c.go:SetSize(150, 28)
	c.go.label = W.Text(c.go, "tbLabel", "CENTER")
	c.go.label:SetPoint("CENTER")

	-- THE QUIET HALF OF THE PAIR: a plain Button with a label, no surface.
	c.alt = CreateFrame("Button", nil, c)
	c.alt:SetSize(180, 28)
	c.alt.label = W.Text(c.alt, "tbLabel", "LEFT")
	c.alt.label:SetPoint("LEFT")
	c.alt:SetScript("OnEnter", function(b) W.Color(b.label, Palette.c.text) end)
	c.alt:SetScript("OnLeave", function(b) W.Color(b.label, Palette.c.textDim) end)

	OB.card = c
	return c
end

--- Stack the card's parts and size it to them.
local function LayCard(c, lines)
	local top  = c.logo:IsShown() and c.logo or c.kicker
	local topH = c.logo:IsShown() and (c.logo:GetHeight() or 0)
		or (c.kicker:GetStringHeight() or 0)
	c.head:ClearAllPoints()
	c.head:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -10)

	local y = -26
	y = y - topH - 10
	y = y - (c.head:GetStringHeight() or 0) - 10
	y = y - (c.body:GetStringHeight() or 0) - 14

	local anchor, offset = c.body, -14
	for i, t in ipairs(c.lines) do
		local text = lines and lines[i]
		if text then
			t:SetText(text)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset)
			t:Show()
			W.Color(t, Palette.c.textDim)
			anchor, offset = t, -7
			y = y - (t:GetStringHeight() or 0) - 7
		else
			t:Hide()
		end
	end

	c.go:ClearAllPoints()
	c.go:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
	c.alt:ClearAllPoints()
	c.alt:SetPoint("LEFT", c.go, "RIGHT", 14, 0)

	c:SetHeight(-y + 20 + 28 + 26)
end

--- The welcome: only your own frame on a dark screen, and the card. On a
--  character whose account has already been set up, it leads with keeping
--  that layout - the layout lives in the shared profile, and growing a new
--  one here would rewrite it for every character on it.
function OB:ShowWelcome()
	self:Undo()
	self.index = nil
	if self.callout then self.callout:Hide() end
	if self.skip then self.skip:Hide() end
	Dim(0)
	self:GrowTo(0)

	local c = BuildCard()
	c.kicker:Hide()
	c.logo:Show()
	c.head:SetText(L.tour.welcome.head)
	c.body:SetText(L.tour.welcome.body)
	W.Color(c.head, Palette.c.text)
	W.Color(c.body, Palette.c.textDim)

	local key = self:Others()
	c.alt:Show()
	W.Color(c.alt.label, Palette.c.textDim)
	if key then
		LayCard(c, { L.tour.welcome.shared })
		c.go.label:SetText(L.tour.welcome.keep)
		c.go:SetScript("OnClick", function()
			OB:AdoptFrom(key)
			OB:Finish()
		end)
		c.alt.label:SetText(L.tour.welcome.go)
		c.alt:SetScript("OnClick", function() OB:Go(1) end)
	else
		LayCard(c, nil)
		c.go.label:SetText(L.tour.welcome.go)
		c.go:SetScript("OnClick", function() OB:Go(1) end)
		c.alt.label:SetText(L.tour.skip)
		c.alt:SetScript("OnClick", function() OB:Skip() end)
	end
	W.Color(c.go.label, Palette.c.text)
	c.alt.label:SetWidth(0)
	c.alt:SetWidth(math.ceil(c.alt.label:GetStringWidth() or 0) + 4)

	c:Show()
end

--- What you set up, read back out of the systems that own it rather than out
--  of anything the tour remembered: the shape, what hangs off the spine, the
--  skin.
function OB:Recap()
	local P = A.Presets
	local preset = P and P:Current()
	local shape = (preset and P.list[preset] and P.list[preset].label)
		or L.tour.finish.own_shape
	local UF = Mod("unitframes")
	local hangers = {}
	if UF and UF.SatelliteOn then
		if UF:SatelliteOn("targettarget") then hangers[#hangers + 1] = L.tour.finish.tot end
		if UF:SatelliteOn("pet") then hangers[#hangers + 1] = L.tour.finish.pet end
	end
	local skin = Palette.skins[Palette.current]
	return table.concat({
		shape,
		#hangers > 0 and table.concat(hangers, ", ") or L.tour.finish.no_hangers,
		(skin and skin.label) or "",
	}, "  \194\183  ")
end

function OB:ShowFinish()
	self:Undo()
	if self.callout then self.callout:Hide() end
	if self.skip then self.skip:Hide() end
	self.index = nil
	-- THE WHOLE LATTICE, in colour: everything still held grows, and the scrim
	-- is gone.
	self:GrowPiece("rest")
	Dim(false)

	local c = BuildCard()
	c.logo:Hide()
	c.kicker:Hide()
	c.head:SetText(L.tour.finish.thanks)
	c.body:SetText(L.tour.finish.setup)
	W.Color(c.head, Palette.c.text)
	W.Color(c.body, Palette.c.textDim)
	LayCard(c, { self:Recap(), L.tour.finish.hint })

	c.go.label:SetText(L.tour.finish.done)
	W.Color(c.go.label, Palette.c.text)
	c.go:SetScript("OnClick", function() OB:Finish() end)
	c.alt:Hide()
	c:Show()
end

-- ---------------------------------------------------------------------------
-- combat, and coming back
-- ---------------------------------------------------------------------------

--- A fight takes the tour down instantly - and the whole HUD comes back with
--  it: every piece is a real frame, and a fight is no time for one to be
--  missing.
function OB:OnCombat()
	if not self.index and not (self.card and self.card:IsShown()) then return end
	self.resumeAt = self.index
	self:Teardown()
end

--- Everything that means "not yet": a fight, and a film of either kind.
local function NotNow()
	if InCombatLockdown() then return true end
	if MovieFrame and MovieFrame.IsShown and MovieFrame:IsShown() then
		return true
	end
	if CinematicFrame and CinematicFrame.IsShown and CinematicFrame:IsShown() then
		return true
	end
	if _G.InCinematic then
		local ok, yes = pcall(_G.InCinematic)
		if ok and yes then return true end
	end
	return false
end

--- What this character sees when it arrives: nothing if it has answered, the
--  toast if it was half way through, and otherwise the welcome.
function OB:OnLogin()
	-- Answered: nothing is owed, and the flag that said so goes too - left up,
	-- a tour re-run later and interrupted by a fight came back as the resume
	-- toast rather than at its stop, the fight's end taking it for a login.
	if self:Completed() then
		self.__pendingLogin = nil
		return
	end
	-- HELD RATHER THAN DROPPED, whatever is in the way.
	if NotNow() then
		self.__pendingLogin = true
		return
	end
	self.__pendingLogin = nil

	local s = Store()
	local at = tonumber(s and s.stopIndex) or 0
	if at > 0 then
		self:ShowResume(at)
	else
		self:ShowWelcome()
	end
end

--- Try the first run again, if one is still owed - a beat later.
function OB:Retry()
	if not self.__pendingLogin then return end
	if _G.C_Timer and _G.C_Timer.After then
		_G.C_Timer.After(FIRST_RUN_DELAY, function() OB:OnLogin() end)
	else
		self:OnLogin()
	end
end

--- A film has STARTED with the tour up: step aside the way a fight makes us.
function OB:OnFilm()
	if self:Completed() then return end
	if self.index then
		self.resumeAt = self.index
		self:Teardown()
	elseif self.card and self.card:IsShown() then
		self:Teardown()
		self.__pendingLogin = true
	end
end

--- And the film is over.
function OB:OnFilmOver()
	if NotNow() then return end
	if self.__pendingLogin then return self:Retry() end
	if not self.resumeAt then return end
	local at = self.resumeAt
	self.resumeAt = nil
	if self:Completed() then return end
	self:Go(at)
end

function OB:OnCombatOver()
	if self.__pendingLogin then return self:Retry() end
	if not self.resumeAt then return end
	local at = self.resumeAt
	self.resumeAt = nil
	if self:Completed() then return end
	self:Go(at)
end

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

function OB:OnEnable()
	A:RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() OB:OnCombat() end)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function() OB:OnCombatOver() end)

	-- THE FIRST RUN, ONCE, and a beat after arriving: the frames are built by
	-- then but not yet put back where they were saved.
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		if OB.__arrived then return end
		OB.__arrived = true
		OB.__pendingLogin = true
		OB:Retry()
	end)

	-- A film ending - watched or skipped, it is the same event - and one
	-- starting, which on WoW Forever is a moment after we arrive.
	for _, event in ipairs({ "STOP_MOVIE", "CINEMATIC_STOP" }) do
		A:RegisterEvent(self, event, function() OB:OnFilmOver() end)
	end
	for _, event in ipairs({ "PLAY_MOVIE", "CINEMATIC_START" }) do
		A:RegisterEvent(self, event, function() OB:OnFilm() end)
	end
end

--- The scale is a setting, and a setting can move while the tour is up.
function OB:OnConfigChanged()
	if not self.scrim then return end
	Rescale(self.scrim)
	if self.index then self:Go(self.index) end
end

function OB:OnDisable()
	self:Teardown()
end

return OB
