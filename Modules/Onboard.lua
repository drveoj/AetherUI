--[[--------------------------------------------------------------------------
	AetherUI :: Onboard

	The first run. Eight stops over the real HUD, and the tour IS the setup.

	NOT A WIZARD. There is no full-screen settings window with a Finish button
	at the end of it, and the difference is the whole design: the world dims,
	one REAL element of the interface is lifted out of the dim, and a glass
	callout beside it carries that stop's control. What you are looking at while
	you choose is the thing you are choosing about. The game is the preview.

	THREE STOPS THAT SET, FIVE THAT SHOW. Palette, layout and the Toolbox edge
	each carry a live control; action bars, the quest tracker, bags, threat and
	the flight console each play one behaviour once and ask for nothing. The
	split is deliberate - a first run that asked eight questions would be a
	form, and a first run that asked none would be a slideshow.

	NOTHING IS STAGED. Every control writes straight into the system that owns
	it the moment it is touched: the palette into the profile, the layout into
	the anchors, the edge into the character's Toolbox record. There is no
	pending state here and no Apply at the end, which is what makes quitting
	half way through cost nothing.

	PER CHARACTER, AND ONCE. `db.char.onboard` holds `completed` and the stop
	you reached. Finishing sets completed; so does skipping, and so does
	dismissing the resume toast - because a player who has said no twice has
	said no, and an addon that keeps asking is one you uninstall.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local OB = A:NewModule("onboard")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- The design deck's own numbers, drawn at profile.scale like everything else.
local CALLOUT_W      = 330
local CALLOUT_PAD    = 20
local CALLOUT_GAP    = 22      -- from the spotlit element to the callout
local CARD_W         = 520     -- welcome and finish
local ARROW          = 14      -- the rotated square pointing at the element
local RING_PAD       = 6       -- how far the accent ring stands off the element
local DOT            = 5
local OFFER_H        = 28      -- the alt offer's own row
local TOAST_H        = 34      -- the resume toast
-- Long enough for the movers to have put every frame back. The tour places
-- its callout against real frames, and a frame that has not been restored
-- yet is a frame in the wrong place.
local FIRST_RUN_DELAY = 2
local DOT_GAP        = 7

-- Timings, in seconds. The deck asks for 200ms on the scrim and 160ms on the
-- callout, and the pulse is a single 300ms beat rather than a loop.
local SCRIM_FADE     = 0.20
local CALLOUT_FADE   = 0.16
local PULSE          = 0.30

-- How dark the world goes: rgba(6,5,14,.62).
local SCRIM_RGB      = { 6 / 255, 5 / 255, 14 / 255 }
local SCRIM_ALPHA    = 0.62

--- Fade a frame to an alpha over a number of seconds.
--
--  W.StepFade and W.DriveFade are the interface's one fade, driven on the
--  frame's own OnUpdate rather than the shared ticker - which runs at a tenth
--  of a second, three steps across a 300ms fade, and reads as a stutter.
local function FadeTo(f, want, secs)
	if not f then return end
	f.__aetherWant = want
	f.__aetherFadeSecs = secs
	if want > 0 then f:Show() end
	W.DriveFade(f)
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

--- The character's record. Created on demand: AceDB hands us db.char whether
--  or not anybody has written to it, but the table inside it is ours.
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
--  resume toast - a player who has said no twice has said no.
function OB:Finish()
	local s = Store()
	if s then
		s.completed = true
		-- AND WHEN, for the alt offer: with two characters done, the one worth
		-- naming is the one you were just playing.
		s.completedAt = (time and time()) or 0
		s.stopIndex = nil
	end
	self:Teardown()
end

--- Somebody else who has already been through this, or nothing.
--
--  OFF db.sv.char, WHICH IS THE WHOLE SAVED FILE rather than this character's
--  slice of it. `A.db.char` is the current character and nothing else; the
--  other records are there beside it and AceDB does not hide them.
--
--  THE MOST RECENT ONE, because with two alts done the one worth naming is the
--  one you were just playing. A record written before completedAt existed reads
--  as zero, which is "long ago" and is the right answer for it.
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

	-- AceDB builds the key as "Name - Realm"; the name is the half worth
	-- saying, and a realm nobody has to read is a longer button.
	return bestKey, (bestKey:match("^(.-) %- ") or bestKey)
end

--- Take that character's setup, and skip the questions.
--
--  ONE THING TO COPY, AND THAT IS NOT A SHORTCOMING. The palette, the layout
--  and the scale live in the PROFILE, and this addon opens on the shared
--  Default profile - so an alt already HAS them, which is the whole reason the
--  offer makes sense. The Toolbox edge is the only choice the tour makes that
--  is stored per character, so it is the only one there is to carry over.
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
-- the stops
-- ---------------------------------------------------------------------------

--- Every stop, in order.
--
--  `target` names what the spotlight lifts, resolved late: a stop's element may
--  not exist yet when this file loads, and on a fresh character some of them do
--  not exist at all (no pet bar, no flight console until a flight). A stop
--  whose target cannot be found still runs - it just has nothing to lift, which
--  is better than a tour with a hole in it.
--
--  `kind` is "set" or "show", and is the only difference in how a stop is
--  built: a SET stop calls `control` to fill the callout's middle, a SHOW stop
--  calls `demo` once on entry.
OB.stops = {
	{
		key   = "palette",
		name  = "YOUR PALETTE",
		head  = "This is you. Pick the light you'll live in.",
		body  = "One palette colours your ENTIRE interface — tap to try each "
			.. "live; everything recolours at once, not just this frame.",
		kind  = "set",
		target = function() return _G[ADDON .. "PlayerFrame"] end,
	},
	{
		key   = "layout",
		name  = "YOUR LAYOUT",
		head  = "Where should everything live?",
		body  = "Three starting layouts — watch the unit frames move as you "
			.. "tap. You can fine-tune every frame later.",
		kind  = "set",
		-- No spotlight: the whole HUD is the subject, so the scrim stays down
		-- and nothing is lifted out of it. A ring around one frame here would
		-- be pointing at the wrong thing.
		target = function() return nil end,
	},
	{
		key   = "toolbox",
		name  = "THE TOOLBOX",
		head  = "Every panel, one drawer.",
		body  = "Quests, addons, settings, this menu — all slide from the "
			.. "Toolbox. Pick which edge it lives on.",
		kind  = "set",
		target = function()
			local TB = A.GetModule and A:GetModule("toolbox")
			return TB and TB.rail
		end,
	},
	{
		key   = "zen",
		name  = "ZEN MODE",
		head  = "When you stop, so does the interface.",
		body  = "After a while of quiet the HUD fades to a breath, a clock and "
			.. "the zone you are in. Pick how long — or never.",
		kind  = "set",
		-- NO SPOTLIGHT, for the same reason the layout stop has none: the
		-- subject is EVERYTHING going away, and a ring round any one frame
		-- would be saying that frame is the thing that fades.
		target = function() return nil end,
	},
	{
		key   = "bars",
		name  = "ACTION BARS",
		head  = "Your spells, undecorated.",
		body  = "Cooldowns, charges and range all draw ON the icon — no extra "
			.. "widgets. Watch: this one's on cooldown.",
		kind  = "show",
		-- THE DOCK, which is the glass the bar is drawn on - the header above
		-- it is a secure state driver with no art of its own.
		--
		-- And found by walking AB.bars, because there is no AB:Bar(id) and
		-- there never was: this asked for one and got nil, so stop 4 lit
		-- nothing for two builds. `stop.target` being a function is not the
		-- same as it finding anything, which is the check that was missing.
		target = function()
			local AB = A.GetModule and A:GetModule("actionbars")
			for _, bar in ipairs((AB and AB.bars) or {}) do
				if bar.id == "1" then return bar.dock end
			end
			return nil
		end,
	},
	{
		key   = "quests",
		name  = "QUEST TRACKER",
		head  = "It knows when you're busy.",
		body  = "The tracker folds itself away the moment combat starts and "
			.. "returns when it ends — like this.",
		kind  = "show",
		-- THE PANEL, which is what the tracker calls its own frame. This asked
		-- for QT.frame and got nil, which is the third of three: see the
		-- harness note under "what each stop points at".
		target = function()
			local QT = A.GetModule and A:GetModule("questtracker")
			return QT and QT.panel
		end,
	},
	{
		key   = "bags",
		name  = "BAGS",
		head  = "One bag. Everything in its place.",
		body  = "All your bags pour into one organised panel — gear, potions, "
			.. "trade goods, junk, each under its own heading.",
		kind  = "show",
		-- THE PANEL IS THE DEMO, so it opens before the spotlight looks for it
		-- and closes on the way out - unless it was already open, in which case
		-- it was the player's and stays theirs.
		before = function()
			local BG = A.GetModule and A:GetModule("bags")
			if not BG or not BG.Show then return end
			local f = BG.frames and BG.frames.bags
			if f and f:IsShown() then return end
			BG:Show()
			OB:OnLeave(function() if BG.Hide then BG:Hide() end end)
		end,
		target = function()
			local BG = A.GetModule and A:GetModule("bags")
			return BG and BG.frames and BG.frames.bags
		end,
	},
	{
		key   = "threat",
		name  = "THREAT",
		head  = "It watches who the monsters want.",
		body  = "Your frame warns you BEFORE trouble: gold means act now, red "
			.. "means it is on you. What counts as trouble flips with your role.",
		kind  = "show",
		target = function() return _G[ADDON .. "PlayerFrame"] end,
	},
	{
		key   = "ifec",
		name  = "I.F.E.C.",
		head  = "Long flight? We've got you.",
		-- AND WHERE IT IS ON THE GROUND, which the first version left out
		-- entirely: it said "boards on your next flight" and stopped, so the
		-- honest reading was that there is nothing to look at until then. There
		-- is - the same programme, in the Toolbox, under its own bad joke of a
		-- name. Reported from the game against 0.31.0.
		body  = "Music, podcasts and a truly disreputable gossip rag, timed to "
			.. "your route. Boards at takeoff — and N.I.F.E.C. plays it on "
			.. "the ground, from the Toolbox.",
		kind  = "show",
		-- THE DRAWER OPENS, the same way the bags stop opens the bag panel,
		-- and for the same reason: the thing being described lives inside it.
		-- A stop that says "it is in the Toolbox" over a shut Toolbox is a stop
		-- that has told you where to look and then not let you.
		--
		-- Shut again on the way out unless it was already open, in which case
		-- it was the player's and stays theirs.
		before = function()
			local TB = A.GetModule and A:GetModule("toolbox")
			if not TB or not TB.SetOpen then return end
			if TB:IsOpen() then return end
			-- Instant, because the callout is placed against the region inside
			-- it on this same frame - mid-slide, the drawer is off the edge of
			-- the screen and the callout goes with it.
			TB:SetOpen(true, true)
			OB:OnLeave(function() TB:SetOpen(false, true) end)
		end,
		-- N.I.F.E.C. ITSELF, at the foot of the drawer, with the rail's
		-- transport chip as the fallback: with no content installed the region
		-- is ABSENT rather than empty - the Toolbox lays out as though it were
		-- never there - and then there is genuinely nothing to point at.
		--
		-- And off A.IFEC rather than off the module: the console's module is
		-- "ifec" and the mini is not on it. This asked for `M.mini` and got nil.
		target = function()
			local M = A.IFEC and A.IFEC.Mini
			if not M then return nil end
			local f = M.frame
			if f and f.IsVisible and f:IsVisible() then return f end
			local TB = A.GetModule and A:GetModule("toolbox")
			return TB and TB.rail and TB.rail.play
		end,
	},
}

OB.COUNT = #OB.stops

--- The first stop that only shows something, which is where the alt offer
--- lands: everything before it is a question this character has answered.
--
--  COMPUTED RATHER THAN WRITTEN DOWN. The deck says "jumps to stop 4", which
--  was true while three stops set something and stopped being true the moment
--  zen made it four. A number here is a number that goes wrong the next time a
--  stop is added, silently, by landing in the middle of the questions.
function OB:FirstShow()
	for i, stop in ipairs(self.stops) do
		if stop.kind == "show" then return i end
	end
	return 1
end

-- ---------------------------------------------------------------------------
-- the scrim
-- ---------------------------------------------------------------------------

--- The dim over the world.
--
--  ANCHORED TO WorldFrame, not UIParent, for the same reason Zen's frosted pane
--  is: WorldFrame is the physical screen at scale 1 whatever the player's UI
--  Scale slider says, and a dim that stops short of the edge of the monitor is
--  worse than no dim at all.
--
--  STRATA `FULLSCREEN`: above the HUD, which is the point - everything the
--  interface draws goes under it, and the one element this stop is about is
--  lifted back out. Below FULLSCREEN_DIALOG, so the callout and the client's
--  own error dialogs still land on top.
local function BuildScrim()
	if OB.scrim then return OB.scrim end

	local f = CreateFrame("Frame", ADDON .. "OnboardScrim")
	f:SetFrameStrata("FULLSCREEN")
	f:SetFrameLevel(0)
	f:SetAllPoints(WorldFrame or UIParent)
	f:EnableMouse(true)
	f:Hide()

	local tint = f:CreateTexture(nil, "BACKGROUND")
	tint:SetAllPoints(f)
	tint:SetTexture(A.Media.texture.flat)
	tint:SetVertexColor(SCRIM_RGB[1], SCRIM_RGB[2], SCRIM_RGB[3], SCRIM_ALPHA)
	f.tint = tint

	OB.scrim = f
	return f
end

-- ---------------------------------------------------------------------------
-- the spotlight
-- ---------------------------------------------------------------------------

--- Lift one real element out of the dim.
--
--  BY STRATA, NOT BY REPARENTING. The obvious way to put a frame above the
--  scrim is to reparent it, and half the things this tour points at are secure:
--  an action bar's parent cannot be changed from insecure code at all, and the
--  attempt is a taint error rather than a no-op. Raising the strata is not a
--  protected operation, so it works on every frame the same way - and putting
--  it back is one call rather than an unwinding.
--
--  WHAT IT WAS, REMEMBERED. A frame whose strata we raised and never restored
--  is a frame that draws over the player's dialogs for the rest of the session.
local function Lift(frame)
	if not frame or not frame.SetFrameStrata then return end
	if OB.lifted then return end
	OB.lifted = {
		frame  = frame,
		strata = frame:GetFrameStrata(),
		level  = frame:GetFrameLevel(),
	}
	frame:SetFrameStrata("FULLSCREEN")
	frame:SetFrameLevel(20)
end

local function Drop()
	local was = OB.lifted
	OB.lifted = nil
	if not was or not was.frame then return end
	if was.strata then was.frame:SetFrameStrata(was.strata) end
	if was.level then was.frame:SetFrameLevel(was.level) end
end

--- The accent ring around the lifted element.
--
--  FOUR HAIRLINES, NOT A PANEL. A Glass panel is a fill AND an edge, and this
--  wants only the edge - the element it wraps is the thing you are meant to be
--  looking at, and a wash of glass over it is the opposite of a spotlight.
--  Glass has no transparent fill token, and giving it one for a single caller
--  would put a colour nobody uses into all four palettes.
--
--  RE-TINTED ON ENTRY rather than skinned once, because stop 1 IS the palette:
--  a ring drawn in Midnight and left there while the player tries Dawn is the
--  one place in the interface where a stale colour is the actual subject.
local function BuildRing()
	if OB.ring then return OB.ring end

	local r = CreateFrame("Frame", nil, BuildScrim())
	r:SetFrameStrata("FULLSCREEN")
	r:SetFrameLevel(18)
	r:Hide()

	r.edges = {}
	for i = 1, 4 do
		local t = r:CreateTexture(nil, "OVERLAY")
		t:SetTexture(A.Media.texture.flat)
		r.edges[i] = t
	end

	local px = A:Px(2)
	r.edges[1]:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.edges[1]:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
	r.edges[1]:SetHeight(px)
	r.edges[2]:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
	r.edges[2]:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
	r.edges[2]:SetHeight(px)
	r.edges[3]:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.edges[3]:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
	r.edges[3]:SetWidth(px)
	r.edges[4]:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
	r.edges[4]:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
	r.edges[4]:SetWidth(px)

	OB.ring = r
	return r
end

local function RingAround(frame)
	local r = BuildRing()
	if not frame or not frame.GetWidth then r:Hide() return end

	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", frame, "TOPLEFT", -RING_PAD, RING_PAD)
	r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", RING_PAD, -RING_PAD)
	for _, t in ipairs(r.edges) do W.Tint(t, Palette.c.accent, 0.55) end
	r:Show()

	-- ONE BEAT, NOT A LOOP. A ring that pulses forever is a ring you stop
	-- seeing; one that pulses as the stop arrives is a ring that says "here".
	r:SetAlpha(0)
	FadeTo(r, 1, PULSE)
end

-- ---------------------------------------------------------------------------
-- the callout
-- ---------------------------------------------------------------------------

--- The glass panel that carries a stop.
--
--  BUILT ONCE AND REFILLED. Eight panels built and thrown away is eight frames
--  the client can never reclaim - frames are not garbage collected - and the
--  tour can be re-run from the Toolbox as many times as somebody likes.
local function BuildCallout()
	if OB.callout then return OB.callout end

	local c = Glass.CreatePanel(BuildScrim(), {
		-- The deck's own drop: 0 16px 50px rgba(0,0,0,.6). `shadow` is an
	-- OPACITY here, not a flag - passing true reaches math.min and takes
	-- the panel down with it.
	corner = 20, fill = "dialogFill", edge = "glassEdgeHi", shadow = 0.6,
	})
	c:SetFrameStrata("FULLSCREEN_DIALOG")
	c:SetWidth(CALLOUT_W)
	c:EnableMouse(true)
	c:Hide()

	-- The arrow tab: a rotated square, half of it under the panel's rim, which
	-- is how the deck draws it. Hidden on a stop with nothing to point at.
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

	-- WHERE A STOP'S OWN THING GOES. Swatches, preset cards, an edge picker,
	-- or a demo's caption - the callout does not know which, and every stop
	-- anchors its content to this and reports a height.
	c.slot = CreateFrame("Frame", nil, c)
	c.slot:SetPoint("TOPLEFT", c.body, "BOTTOMLEFT", 0, -12)
	c.slot:SetWidth(CALLOUT_W - CALLOUT_PAD * 2)
	c.slot:SetHeight(1)

	-- THE ALT OFFER, under the control and above the footer. Its own row rather
	-- than a fifth swatch in the slot: it is not another palette, it is a way
	-- of not being asked about palettes at all.
	c.offer = W.CreateButton(c, { corner = 11 })
	c.offer:SetHeight(OFFER_H)
	c.offer:SetPoint("TOPLEFT", c.slot, "BOTTOMLEFT", 0, -10)
	c.offer:SetPoint("RIGHT", c.slot, "RIGHT", 0, 0)
	c.offer.label = W.Text(c.offer, "tbLabel", "CENTER")
	c.offer.label:SetPoint("CENTER")
	c.offer:Hide()

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

	-- BACK IS QUIET, and it is always there. The deck greys it on stop 1
	-- rather than removing it: a control that appears and disappears makes the
	-- footer jump, and the tour is eight of these in a row.
	-- A WORD, NOT A BUTTON. Glass has no transparent fill or edge token -
	-- an unknown name falls back to `glass` and `glassEdge` - so "quiet"
	-- here means a plain Button with a label on it and no surface at all.
	local back = CreateFrame("Button", nil, nav)
	back:SetSize(52, 24)
	back:SetPoint("LEFT", nav, "LEFT", 0, 0)
	back.label = W.Text(back, "tbLabel", "CENTER")
	back.label:SetPoint("CENTER")
	back.label:SetText("Back")
	back:SetScript("OnClick", function() OB:Back() end)
	nav.back = back

	local next_ = W.CreateButton(nav, { corner = 12 })
	next_:SetSize(64, 24)
	next_:SetPoint("RIGHT", nav, "RIGHT", 0, 0)
	next_.label = W.Text(next_, "tbLabel", "CENTER")
	next_.label:SetPoint("CENTER")
	next_.label:SetText("Next")
	next_:SetScript("OnClick", function() OB:Next() end)
	nav.next = next_

	-- The dots. One per stop, the current one in the accent.
	nav.dots = {}
	for i = 1, OB.COUNT do
		local d = nav:CreateTexture(nil, "ARTWORK")
		d:SetSize(DOT, DOT)
		d:SetTexture(A.Media.texture.flat)
		nav.dots[i] = d
	end
	local span = OB.COUNT * DOT + (OB.COUNT - 1) * DOT_GAP
	for i, d in ipairs(nav.dots) do
		d:SetPoint("LEFT", nav, "CENTER",
			-span / 2 + (i - 1) * (DOT + DOT_GAP), 0)
	end

	return nav
end

--- Paint the footer for a stop.
local function PaintNav(nav, index)
	local c = Palette.c
	for i, d in ipairs(nav.dots) do
		W.Tint(d, i == index and c.accent or c.textFaint,
			i == index and 1 or 0.35)
	end

	-- Nothing behind stop 1, so Back says so rather than lying about it.
	local first = index <= 1
	W.Color(nav.back.label, first and c.textFaint or c.textDim)
	nav.back:EnableMouse(not first)

	nav.next.label:SetText(index >= OB.COUNT and "Finish" or "Next")
end

-- ---------------------------------------------------------------------------
-- placing the callout
-- ---------------------------------------------------------------------------

--- Beside the element, and never off the screen.
--
--  MEASURED AGAINST THE SCREEN, not chosen by the stop. Which side of a frame
--  has room depends on where the player has dragged that frame, and a callout
--  anchored "to the right of the player frame" by somebody looking at their own
--  layout is a callout half off the screen on anybody else's.
--
--  AND CLAMPED, WHICH IS THE HALF THAT WAS MISSING. Anchoring the callout's
--  LEFT to the element's RIGHT centres it vertically on the element - so a
--  target near the top of the screen puts most of the callout above the top of
--  the screen, and the first build showed nothing but its footer. Reported in
--  game against 0.30.0.
--
--  PLACED IN SCREEN PIXELS, against UIParent's bottom-left corner. The callout
--  hangs off the scrim, which is parentless and therefore at scale 1 whatever
--  the player's UI Scale slider says - so its offsets ARE pixels, and the
--  element's own centre becomes pixels by multiplying by its effective scale.
--  Doing this in anchor points instead means clamping something whose position
--  you have not got a number for.
local function PlaceCallout(c, frame)
	c:ClearAllPoints()
	c.arrow:Hide()

	local sw = (UIParent:GetWidth() or 0) * (UIParent:GetEffectiveScale() or 1)
	local sh = (UIParent:GetHeight() or 0) * (UIParent:GetEffectiveScale() or 1)
	local cw, ch = c:GetWidth() or 0, c:GetHeight() or 0

	if not frame or not frame.GetCenter or not frame:GetCenter()
		or sw <= 0 or sh <= 0 then
		c:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		return
	end

	local fs = frame:GetEffectiveScale() or 1
	local fx, fy = frame:GetCenter()
	fx, fy = fx * fs, fy * fs
	local halfW = ((frame:GetWidth() or 0) * fs) / 2

	-- The side with room, then the position on it.
	local onRight = fx < sw / 2
	local x = onRight and (fx + halfW + CALLOUT_GAP + cw / 2)
		or (fx - halfW - CALLOUT_GAP - cw / 2)
	local y = fy

	-- INSIDE THE SCREEN, both ways. A margin rather than flush, because a panel
	-- touching the edge of the monitor reads as one that has been cut off.
	local m = 16
	local wantX = x
	x = math.max(cw / 2 + m, math.min(sw - cw / 2 - m, x))
	y = math.max(ch / 2 + m, math.min(sh - ch / 2 - m, y))

	c:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)

	-- WHERE IT WENT, IN NUMBERS, kept on the frame.
	--
	-- Not for the addon - nothing reads this - but because the arithmetic
	-- above IS the thing that went wrong, and it cannot be checked from the
	-- outside: asking a frame where it ended up means resolving an anchor
	-- chain, which the harness models as a fixed answer. So the sum shows
	-- its working.
	c.__aetherAt = { x = x, y = y, w = cw, h = ch,
		sw = sw, sh = sh, onRight = onRight, wantX = wantX }

	-- THE ARROW FOLLOWS THE ELEMENT, not the callout's middle. Once the callout
	-- has been shoved back onto the screen the two are no longer level, and an
	-- arrow left in the centre points at nothing.
	--
	-- Only when the callout is still on the side it asked for: pushed past the
	-- element entirely there is nothing sensible for it to point at, and an
	-- arrow on the wrong edge is worse than none.
	local slid = math.abs(x - wantX) > cw / 2
	if slid then return end

	local edge = onRight and "LEFT" or "RIGHT"
	local dy = fy - y
	local limit = ch / 2 - ARROW
	if dy > limit then dy = limit elseif dy < -limit then dy = -limit end

	c.arrow:ClearAllPoints()
	c.arrow:SetPoint("CENTER", c, edge, 0, dy)
	c.__aetherAt.edge, c.__aetherAt.dy = edge, dy
	W.Tint(c.arrow, Palette.c.dialogFill, 1)
	c.arrow:Show()
end

--- Tall enough for what is in it, and no taller.
local function SizeCallout(c)
	-- The offer's row only when there is one. Left in the sum unconditionally,
	-- a stop with no offer gets a strip of empty glass above its footer.
	local offer = (c.offer and c.offer:IsShown()) and (OFFER_H + 10) or 0
	local h = CALLOUT_PAD
		+ (c.kicker:GetStringHeight() or 0) + 8
		+ (c.head:GetStringHeight() or 0) + 8
		+ (c.body:GetStringHeight() or 0) + 12
		+ (c.slot:GetHeight() or 0) + offer + 14
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

--- "Skip tour — keep defaults", pinned to the bottom of the screen at every
--  stop. Its own frame rather than part of the callout, because the callout
--  moves with the element and this must not.
local function BuildSkip()
	if OB.skip then return OB.skip end

	local b = CreateFrame("Button", nil, BuildScrim())
	b:SetFrameStrata("FULLSCREEN_DIALOG")
	b:SetSize(220, 24)
	b:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 42)

	b.label = W.Text(b, "tbLabel", "CENTER")
	b.label:SetPoint("CENTER")
	b.label:SetText("Skip tour — keep defaults")
	W.Color(b.label, Palette.c.textFaint)

	b:SetScript("OnEnter", function() W.Color(b.label, Palette.c.textDim) end)
	b:SetScript("OnLeave", function() W.Color(b.label, Palette.c.textFaint) end)
	b:SetScript("OnClick", function() OB:Skip() end)
	b:Hide()

	OB.skip = b
	return b
end

-- ---------------------------------------------------------------------------
-- the controls
--
-- Three stops carry one, and every one of them writes STRAIGHT INTO THE SYSTEM
-- THAT OWNS IT the moment it is touched. No staging, no Apply at the end - the
-- palette goes into the profile, the layout into the anchors, the edge into the
-- character's Toolbox record, and each of those systems repaints itself the way
-- it would if the change had come from the options panel. Which is the whole
-- reason quitting half way through costs nothing.
-- ---------------------------------------------------------------------------

local CHIP_H     = 58      -- a swatch card
local CARD_H     = 62      -- a layout card, wireframe and all
local EDGE_H     = 74      -- the edge picker
local ZEN_H      = 34      -- a delay card

--- Everything a stop put in the slot, gone.
--
--  POOLED BY THE SLOT rather than destroyed, because frames cannot be
--  destroyed - and the tour can be re-run as many times as somebody likes.
--  A control left over from the last stop is a control that still works.
function OB:ClearSlot(slot)
	slot.__aetherKids = slot.__aetherKids or {}
	for _, pool in pairs(slot.__aetherKids) do
		for _, f in ipairs(pool) do
			f:Hide()
			f:ClearAllPoints()
			-- ASKED FIRST. Not everything in a slot is a Button - stop 3's box
			-- is a plain Frame with four tabs on it - and the client throws on
			-- SetScript for a script the type has not got, CLEARING one as
			-- much as setting one. Reported in game against 0.30.0.
			if f.HasScript and f:HasScript("OnClick") then
				f:SetScript("OnClick", nil)
			end
		end
	end
end

--- One frame out of the slot's pool, built by `make` the first time.
--
--  A POOL PER CONTROL, not one list by index. The three controls share this
--  slot and their frames are not interchangeable - the fourth palette swatch
--  and the first layout card would be the same frame, and the layout card
--  would be looking for a wireframe box a swatch has not got. Which is exactly
--  how this failed the first time it was run.
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

--- The look of a card that is either the chosen one or not.
--
--  THE ACCENT RIM IS THE WHOLE SIGNAL. There is no tick and no radio dot in
--  the deck: the chosen card is lit and the others are not, which is the same
--  language the Toolbox tiles and the chat tabs already speak.
local function Chosen(card, on)
	local c = Palette.c
	if card.SetFillColor then
		card:SetFillColor(on and c.glassEdgeHi or c.glass)
		card:SetEdgeColor(on and c.accent or c.glassEdge)
	end
	if card.label then W.Color(card.label, on and c.text or c.textDim) end
end

-- ---------------------------------------------------------------------------
-- stop 1: the palette
-- ---------------------------------------------------------------------------

--- Four swatch cards. Tapping one recolours the ENTIRE interface, live.
--
--  THROUGH A:Restyle, the same door the options panel and /aether skin use.
--  A palette applied any other way is a palette that half the interface has
--  not heard about - and the one thing this stop must not do is show somebody
--  a preview that is not what they will get.
local function PaletteControl(slot)
	local list = Palette:List()
	local gap = 7
	local w = (slot:GetWidth() - gap * (#list - 1)) / #list

	for i, entry in ipairs(list) do
		local card = Kid(slot, "palette", i, function(parent)
			local f = Glass.CreatePanel(parent, {
				frameType = "Button", corner = 11,
			})
			f.dot = f:CreateTexture(nil, "OVERLAY")
			f.dot:SetSize(19, 19)
			-- chipDisc, not circleMask: the same circle authored at 64 for
			-- things drawn near that size. The 256px one minified to 19 is
			-- eight times down with no mipmap behind it, which is the crunch
			-- the chip rim, the check box and the tooltip badge all record.
			f.dot:SetTexture(A.Media.texture.chipDisc)
			f.dot:SetPoint("TOP", f, "TOP", 0, -8)
			f.label = W.Text(f, "tbLabel", "CENTER")
			f.label:SetPoint("BOTTOM", f, "BOTTOM", 0, 7)
			return f
		end)

		card:SetSize(w, CHIP_H)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", slot, "TOPLEFT", (i - 1) * (w + gap), 0)

		-- THE SWATCH IS THAT PALETTE'S OWN ACCENT, not the one in use. The
		-- point of four cards is to show four colours; drawing them all in the
		-- current skin's accent would make the choice invisible.
		local skin = Palette.skins[entry.key]
		W.Tint(card.dot, skin and skin.accent or Palette.c.accent, 1)
		card.label:SetText(entry.label or entry.key)
		Chosen(card, Palette.current == entry.key)

		card:SetScript("OnClick", function()
			A.db.profile.skin = entry.key
			A:Restyle()
			-- AND THE TOUR REPAINTS ITSELF WITH EVERYTHING ELSE. The callout,
			-- the ring and the dots are all drawn in the accent that just
			-- changed, and a tour that stayed Midnight while the HUD went Dawn
			-- would be the one thing on screen contradicting its own copy.
			OB:Go(OB.index or 1)
		end)
	end

	slot:SetHeight(CHIP_H)
end

-- ---------------------------------------------------------------------------
-- stop 2: the layout
-- ---------------------------------------------------------------------------

--- A wireframe of an arrangement, drawn from the arrangement itself.
--
--  FROM THE PRESET'S OWN NUMBERS, not from three hand-drawn thumbnails. The
--  anchors are already fractions of the screen - that is what makes them
--  portable - so a thumbnail is those fractions on a small rectangle, and it
--  cannot drift away from what the card actually does.
--
--  FOUR MARKS AT MOST, AND NOT ELEVEN.
--
--  The first version drew every anchor a preset names, which is six bars, the
--  party frame, the pet, the tooltip and the rest - eleven smears in a box the
--  size of a postage stamp, overlapping into a texture rather than a layout.
--  A thumbnail is not a map; it has one job, which is to let somebody tell
--  three arrangements apart at a glance.
--
--  So: the player frame, the target frame, and the bars this preset actually
--  SWITCHES ON. A preset that leaves bar 5 off has no business drawing it, and
--  the anchors table still carries a position for it either way.
local SHOWN = { player = true, target = true }

local function Wireframe(box, preset)
	box.marks = box.marks or {}
	for _, m in ipairs(box.marks) do m:Hide() end

	local bw, bh = box:GetWidth(), box:GetHeight()
	if not bw or bw <= 0 or not bh or bh <= 0 then return end

	local n = 0
	local function mark(a, wide, strong)
		n = n + 1
		local m = box.marks[n]
		if not m then
			m = box:CreateTexture(nil, "OVERLAY")
			m:SetTexture(A.Media.texture.flat)
			box.marks[n] = m
		end

		-- The fraction is an offset from the anchor point, so it becomes a
		-- position on the box the same way Presets turns it into a position on
		-- the screen: from the corner it is measured from.
		m:SetSize(bw * (wide and 0.30 or 0.20), math.max(2, bh * 0.11))
		m:ClearAllPoints()
		m:SetPoint("CENTER", box, a.point or "CENTER",
			(a.fx or 0) * bw, (a.fy or 0) * bh)
		W.Tint(m, Palette.c.accent, strong and 0.75 or 0.4)
		m:Show()
	end

	for name in pairs(SHOWN) do
		local a = preset.anchors and preset.anchors[name]
		if a then mark(a, false, true) end
	end

	for id in pairs(preset.bars or {}) do
		local a = preset.bars[id] and preset.anchors
			and preset.anchors["bar" .. id]
		if a then mark(a, true, false) end
	end
end

--- Three cards. Tapping one moves the real frames, live.
local function LayoutControl(slot)
	local P = A.Presets
	if not P then slot:SetHeight(1) return end

	local keys = P.order
	local gap = 7
	local w = (slot:GetWidth() - gap * (#keys - 1)) / #keys
	local now = P:Current()

	for i, key in ipairs(keys) do
		local preset = P.list[key]
		local card = Kid(slot, "layout", i, function(parent)
			local f = Glass.CreatePanel(parent, {
				frameType = "Button", corner = 11,
			})
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
			OB:Go(OB.index or 2)
		end)
	end

	slot:SetHeight(CARD_H)
end

-- ---------------------------------------------------------------------------
-- stop 4: how long before the HUD goes quiet
-- ---------------------------------------------------------------------------

-- The three timings worth offering, and off. In the words somebody thinks in
-- rather than in seconds, and topped out by the client: it flags you away at
-- five minutes and zen follows it there regardless, so nothing longer than that
-- could ever fire.
local ZEN_DELAYS = {
	{ label = "30s",   secs = 30 },
	{ label = "1 min", secs = 60 },
	{ label = "5 min", secs = 300 },
	{ label = "never" },
}

--- Four cards. Tapping one sets the timer, or switches the whole thing off.
--
--  STRAIGHT INTO THE PROFILE, the same door /aether zen delay uses - and the
--  fader with it. Zen is stage TWO of one feature: with the idle fade switched
--  off there is no stage one to fade out of, so a delay chosen here would be a
--  delay for something that can never happen. Picking a time is asking for the
--  breathing HUD, and this is what asking for it means.
local function ZenControl(slot)
	local zcfg = A.db.profile.modules.zen or {}
	local live = (A:GetModule("zen") or {}).enabled and true or false
	local gap = 7
	local w = (slot:GetWidth() - gap * (#ZEN_DELAYS - 1)) / #ZEN_DELAYS

	for i, opt in ipairs(ZEN_DELAYS) do
		local card = Kid(slot, "zen", i, function(parent)
			local f = Glass.CreatePanel(parent, {
				frameType = "Button", corner = 11,
			})
			f.label = W.Text(f, "tbLabel", "CENTER")
			f.label:SetPoint("CENTER")
			return f
		end)

		card:SetSize(w, ZEN_H)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", slot, "TOPLEFT", (i - 1) * (w + gap), 0)
		card.label:SetText(opt.label)

		-- "never" IS THE MODULE BEING OFF rather than a fourth delay. A timer
		-- that never elapses is a ticker running for ever to do nothing.
		local on
		if opt.secs then
			on = live and (zcfg.delay or 60) == opt.secs
		else
			on = not live
		end
		Chosen(card, on)

		card:SetScript("OnClick", function()
			if not opt.secs then
				A:SetModuleEnabled("zen", false)
			else
				A.db.profile.modules.zen = A.db.profile.modules.zen or {}
				A.db.profile.modules.zen.delay = opt.secs
				A.db.profile.fader.enabled = true
				if not (A:GetModule("zen") or {}).enabled then
					A:SetModuleEnabled("zen", true)
				end
			end
			OB:Go(OB.index or 4)
		end)
	end

	slot:SetHeight(ZEN_H)
end

-- ---------------------------------------------------------------------------
-- stop 3: the Toolbox edge
-- ---------------------------------------------------------------------------

local EDGES = { "LEFT", "TOP", "RIGHT", "BOTTOM" }

--- Tap an edge. A rectangle with four targets on it, which is the picker the
--  movers already use when you drag the rail - the same gesture in a smaller
--  box, so the one you learn here is the one that works later.
local function ToolboxControl(slot)
	local TB = A.GetModule and A:GetModule("toolbox")
	local now = (A.db and A.db.char and A.db.char.toolbox
		and A.db.char.toolbox.docked) or "LEFT"

	local box = Kid(slot, "toolbox", 1, function(parent)
		local f = Glass.CreatePanel(parent, { corner = 11 })
		f.hint = W.Text(f, "tbLabel", "CENTER")
		f.hint:SetPoint("CENTER")
		f.hint:SetText("tap an edge")
		return f
	end)
	box:SetSize(slot:GetWidth(), EDGE_H)
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
	W.Color(box.hint, Palette.c.textFaint)

	for i, edge in ipairs(EDGES) do
		local tab = Kid(slot, "toolbox", i + 1, function(parent)
			local f = CreateFrame("Button", nil, parent)
			f.fill = f:CreateTexture(nil, "OVERLAY")
			f.fill:SetAllPoints(f)
			f.fill:SetTexture(A.Media.texture.flat)
			return f
		end)
		tab:SetParent(box)
		tab:ClearAllPoints()

		if edge == "LEFT" then
			tab:SetSize(9, 32)
			tab:SetPoint("LEFT", box, "LEFT", 0, 0)
		elseif edge == "RIGHT" then
			tab:SetSize(9, 32)
			tab:SetPoint("RIGHT", box, "RIGHT", 0, 0)
		elseif edge == "TOP" then
			tab:SetSize(32, 9)
			tab:SetPoint("TOP", box, "TOP", 0, 0)
		else
			tab:SetSize(32, 9)
			tab:SetPoint("BOTTOM", box, "BOTTOM", 0, 0)
		end

		W.Tint(tab.fill, Palette.c.accent, now == edge and 1 or 0.25)
		tab:SetScript("OnClick", function()
			if TB and TB.SetDock then TB:SetDock(edge) end
			OB:Go(OB.index or 3)
		end)
	end

	slot:SetHeight(EDGE_H)
end

--- Which control a SET stop carries.
local CONTROLS = {
	palette = PaletteControl,
	layout  = LayoutControl,
	toolbox = ToolboxControl,
	zen     = ZenControl,
}

function OB:Control(stop, slot)
	local fn = CONTROLS[stop.key]
	if fn then fn(slot) end
end

-- ---------------------------------------------------------------------------
-- stops 4-8: the demos
--
-- A SHOW stop carries no control. What it carries is one behaviour, played
-- ONCE - the deck's own note under each of these five reads "SHOWS ... once" -
-- and once is the whole discipline. A demo that loops is a screensaver: the eye
-- reads it twice and then stops seeing it, and the callout beside it goes
-- unread with it.
--
-- AND THE REAL THING DOES IT WHERE THE REAL THING CAN. Three of the five cost
-- the player nothing to show for real - the tracker really folds, the bag panel
-- really opens, the player's own frame really wears the warning - so those are
-- not demonstrations of a behaviour, they ARE the behaviour, with the tour
-- pointing at it. The other two have nowhere real to happen without a spell on
-- cooldown or a flight to be on, so their demo is drawn in the callout. Even
-- there it is drawn with the SAME widgets the real one uses: the bar tiles are
-- W.DecorateSlot carrying the player's own spell icons under a real Cooldown
-- frame, and the console's programme bar is the console's programme bar. A demo
-- built out of its own rectangles is a demo that goes stale the first time the
-- real one is restyled.
--
-- WHAT A DEMO CHANGES OUT THERE, IT PUTS BACK. See OB:Undo - a tour that folded
-- somebody's tracker and then took a disconnect is a tour that cost them their
-- tracker.
-- ---------------------------------------------------------------------------

local TILE     = 34       -- an icon square in the bars demo
local CD_SECS  = 4.2      -- the deck's own number on the sweeping tile
local SWAP_AT  = 2.4      -- when a before-and-after demo turns over
local STAGGER  = 0.14     -- between one category chip and the next
local STATE_H  = 24       -- a dot-and-a-line pill
local CAT_H    = 22       -- a category chip
local BAR_H    = 7        -- the console's programme bar

--- The same colour, softer.
--
--  There is no token for a 14%-alpha accent and there should not be: it is the
--  fill under a chip's own label, wanted in one place, and a token exists so
--  that four palettes can disagree about a colour. This one cannot.
local function Soft(c, a)
	return { c[1], c[2], c[3], a }
end

--- Anything a stop changed out in the world, put back.
--
--  ONE LIST, POPPED IN REVERSE, and every route out of a stop goes through it:
--  Go on the way to the next stop, and Teardown for finishing, skipping, a
--  fight starting and the module being switched off. A demo's undo is not
--  optional tidying - the tracker being folded and the bag panel being open are
--  states the player did not ask for and must not be left holding.
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

--- Play one demo, once. `step(at)` gets seconds since entry, and returns false
--- when it has finished.
--
--  ON THE SLOT'S OWN OnUpdate rather than a chain of C_Timer.After. A timer
--  that fires after the player has moved on is a timer writing into the NEXT
--  stop's frames: the pools are shared by design, so the frame is still there
--  and still takes the write. This stops when the stop does, because leaving
--  the stop takes the script off.
--
--  THE OPENING FRAME NOW, not on the first tick. A demo whose first state
--  arrives a frame late shows an empty callout for that frame, which reads as
--  the thing having failed to load.
local function Play(slot, step)
	if step(0) == false then return end
	local at = 0
	slot:SetScript("OnUpdate", function(self, dt)
		at = at + (dt or 0)
		if step(at) == false then self:SetScript("OnUpdate", nil) end
	end)
	OB:OnLeave(function() slot:SetScript("OnUpdate", nil) end)
end

--- The little arrow between a before and an after.
--
--  A TEXTURE, because this font has no arrows. A real arrow character comes out
--  of it as a hollow box, which is exactly how one shipped on the finish card
--  and a second sat in a tooltip diagnostic for months. Every arrow this addon
--  draws is Media.texture.chevron.
local function Chev(slot, key)
	local f = Kid(slot, key, 1, function(parent)
		local c = CreateFrame("Frame", nil, parent)
		c:SetSize(13, 13)
		c.tex = c:CreateTexture(nil, "OVERLAY")
		c.tex:SetAllPoints(c)
		c.tex:SetTexture(Media.texture.chevron)
		return c
	end)
	W.FaceChevron(f.tex, "RIGHT")
	W.Tint(f.tex, Palette.c.accent, 0.6)
	return f
end

--- A dot and a line of words: "tracking", "in combat - folded".
--
--  Not W.Pill, and this is the one place in here it is not. A pill centres its
--  label by design and this has a dot in front of the label, so the text is
--  off-centre by half the dot for ever - the two cannot be reconciled without
--  giving W.Pill an asymmetric padding that only this caller would ever pass.
local function StatePill(slot, key)
	local p = Kid(slot, key, 1, function(parent)
		local f = Glass.CreatePill(parent, {
			fill = "glass", edge = "glassEdge" })
		f:SetHeight(STATE_H)
		f.dot = f:CreateTexture(nil, "OVERLAY")
		f.dot:SetSize(7, 7)
		f.dot:SetTexture(Media.texture.chipDisc)
		f.dot:SetPoint("LEFT", f, "LEFT", 11, 0)
		f.label = W.Text(f, "tbLabel", "LEFT")
		f.label:SetPoint("LEFT", f.dot, "RIGHT", 7, 0)

		--- One state, said in one call: the words, and the colour that means
		--  them. The dot, the ink and the rim all move together or the pill
		--  says two things.
		function f:Say(text, colour)
			colour = colour or Palette.c.textDim
			self.label:SetText(text or "")
			W.Color(self.label, colour)
			W.Tint(self.dot, colour, 1)
			self:SetEdgeColor(Soft(colour, 0.35))
			self:SetWidth(11 + 7 + 7
				+ math.ceil(self.label:GetStringWidth() or 0) + 13)
		end
		return f
	end)
	return p
end

-- ---------------------------------------------------------------------------
-- stop 4: the action bars
-- ---------------------------------------------------------------------------

--- Four slots, and the second one goes on cooldown.
--
--  THE PLAYER'S OWN SPELLS, read straight off action slots 1 to 4. The sentence
--  beside this says "your spells, undecorated" and a row of invented squares
--  would be decorating them. An empty slot draws empty, which is the honest
--  answer on a level-one character with two things on the bar and is the same
--  silhouette either way.
--
--  A REAL Cooldown FRAME, swiping a real duration with the real swipe texture
--  and the real countdown formatter. Nothing in here is a drawing of a
--  cooldown - which matters because the whole claim being made is that the
--  cooldown draws ON the icon.
local function BarsDemo(slot)
	local gap = 6
	local tiles = {}

	for i = 1, 4 do
		local tile = Kid(slot, "bars.tile", i, function(parent)
			local f = CreateFrame("Frame", nil, parent)
			f:SetSize(TILE, TILE)
			-- No count: there is no stack to show and the string would sit
			-- over the countdown.
			W.DecorateSlot(f, TILE, { count = false })

			local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
			cd:SetAllPoints(f)
			pcall(cd.SetSwipeTexture, cd, Media.texture.slotMask)
			pcall(cd.SetSwipeColor, cd, 0.02, 0.01, 0.06, 0.72)
			pcall(cd.SetDrawEdge, cd, false)
			pcall(cd.SetDrawBling, cd, false)
			pcall(cd.SetHideCountdownNumbers, cd, true)
			cd:Hide()
			f.cd = cd

			f.cdText = W.Text(f, "stack", "CENTER")
			f.cdText:SetPoint("CENTER", f, "CENTER", 0, 0)
			-- Sized off the tile the way the real button's is sized off the
			-- button, rather than off the role: a number that fits a 44px slot
			-- does not fit a 34px one.
			Media:SetFont(f.cdText, "stack", math.max(10, TILE * 0.24))
			W.Color(f.cdText, Palette.c.text)
			return f
		end)

		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", slot, "TOPLEFT", (i - 1) * (TILE + gap), 0)

		local tex = GetActionTexture and GetActionTexture(i)
		tile.icon:SetTexture(tex or Media.texture.flat)
		tile.icon:SetAlpha(tex and 1 or 0.10)
		tile.cdText:SetText("")
		tile.cd:Hide()

		-- THE FOURTH WEARS THE READY RIM, which is the other half of the claim:
		-- range and readiness are the slot's own edge, not a widget beside it.
		W.Tint(tile.edge, i == 4 and Palette.c.accent or Palette.c.glassEdge,
			i == 4 and 0.9 or 1)

		tiles[i] = tile
	end

	slot:SetHeight(TILE)

	local hot = tiles[2]
	hot.cd:Show()
	hot.cd:SetCooldown((GetTime and GetTime()) or 0, CD_SECS)

	Play(slot, function(at)
		local left = CD_SECS - at
		if left <= 0 then
			hot.cdText:SetText("")
			hot.cd:Hide()
			return false
		end
		-- W.Duration, the same formatter the real button uses - which is why
		-- this reads 4.2 and then 4.1 rather than 4 and then 4.
		hot.cdText:SetText(W.Duration(left))
	end)
end

-- ---------------------------------------------------------------------------
-- stop 5: the quest tracker
-- ---------------------------------------------------------------------------

--- A quest, and then the tracker folds - the real one included.
local function QuestsDemo(slot)
	-- THE REAL TRACKER REALLY FOLDS, through the same call the combat handler
	-- makes. Restored on the way out, and restored to what it WAS rather than
	-- to open: somebody who keeps their tracker folded should get it back
	-- folded.
	local QT = A.GetModule and A:GetModule("questtracker")
	if QT and QT.SetCollapsed then
		local was = QT.collapsed and true or false
		OB:OnLeave(function() QT:SetCollapsed(was) end)
	else
		QT = nil
	end

	local card = Kid(slot, "quests.card", 1, function(parent)
		local f = Glass.CreatePanel(parent, { corner = 10 })
		f.title = W.Text(f, "tbLabel", "LEFT")
		f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -9)
		f.line = W.Text(f, "tbLabel", "LEFT")
		f.line:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
		return f
	end)

	-- The deck's own quest, and the gag is in the content rather than the
	-- chrome - which is the copy rule for this whole addon.
	card.title:SetText("Wanted: Hogger")
	card.line:SetText("0/1 slain")
	W.Color(card.title, Palette.c.text)
	W.Color(card.line, Palette.c.textDim)
	card:SetWidth(math.max(card.title:GetStringWidth() or 0,
		card.line:GetStringWidth() or 0) + 24)

	local chev = Chev(slot, "quests.chev")
	local pill = StatePill(slot, "quests.pill")

	local OPEN, FOLDED = 44, 28
	card:ClearAllPoints()
	card:SetPoint("LEFT", slot, "LEFT", 0, 0)
	chev:ClearAllPoints()
	chev:SetPoint("LEFT", card, "RIGHT", 9, 0)
	pill:ClearAllPoints()
	pill:SetPoint("LEFT", chev, "RIGHT", 9, 0)

	-- THE SLOT'S HEIGHT DOES NOT MOVE with the card's. The callout is sized
	-- from the slot, and a callout that changed height half way through a demo
	-- would jump - and it is anchored beside the element, so it would jump
	-- sideways as well.
	slot:SetHeight(OPEN)

	-- TWO STATES, WRITTEN ON THE CHANGE. A before-and-after demo has nothing
	-- to animate between its two halves, so it is a latch rather than a curve -
	-- and without the latch the pill re-measures its own label a hundred and
	-- forty times to say the same word.
	local state = nil
	Play(slot, function(at)
		local want = (at < SWAP_AT) and "open" or "folded"
		if want == state then return want == "open" end
		state = want

		if want == "open" then
			card:SetHeight(OPEN)
			card.line:Show()
			pill:Say("tracking", Palette.c.textFaint)
			chev:SetAlpha(0.25)
			return true
		end

		card:SetHeight(FOLDED)
		card.line:Hide()
		pill:Say("in combat — folded", Palette.c.danger)
		chev:SetAlpha(1)
		if QT then QT:SetCollapsed(true) end
		return false
	end)
end

-- ---------------------------------------------------------------------------
-- stop 6: the bags
-- ---------------------------------------------------------------------------

-- The headings the panel actually sorts into, in the order it sorts them.
-- Junk is last and is dimmed in the deck, and it is dimmed for a reason: it is
-- the one heading you are being invited to sell rather than to keep.
local CATEGORIES = { "Gear", "Consumables", "Trade goods", "Quest", "Junk" }

--- The headings, arriving one at a time.
local function BagsDemo(slot)
	local gap, chips = 6, {}
	local avail = slot:GetWidth() or CALLOUT_W
	local x, y, rows = 0, 0, 1

	for i, name in ipairs(CATEGORIES) do
		local chip = Kid(slot, "bags.chip", i, function(parent)
			return W.Pill(parent, "tbLabel",
				{ height = CAT_H, padX = 10, edge = true })
		end)
		chip:SetLabel(name)

		local lit = (name ~= "Junk")
		chip:SetColors(lit and Soft(Palette.c.accent, 0.12) or Palette.c.glass,
			lit and Palette.c.accent or Palette.c.textFaint)
		chip:SetEdgeColor(lit and Soft(Palette.c.accent, 0.28)
			or Palette.c.glassEdge)

		-- WRAPPED, because five headings do not fit across a 330 callout and
		-- the fifth one running off the edge is the one that says "Junk".
		local w = chip:GetWidth() or 0
		if x > 0 and x + w > avail then
			x, y, rows = 0, y - (CAT_H + gap), rows + 1
		end
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", slot, "TOPLEFT", x, y)
		x = x + w + gap

		chips[i] = chip
	end

	slot:SetHeight(rows * CAT_H + (rows - 1) * gap)

	local shown = nil
	Play(slot, function(at)
		local n = math.floor(at / STAGGER) + 1
		if n == shown then return n < #chips end
		shown = n
		for i, chip in ipairs(chips) do
			chip:SetAlpha(i <= n and 1 or 0)
		end
		return n < #chips
	end)
end

-- ---------------------------------------------------------------------------
-- stop 7: threat
-- ---------------------------------------------------------------------------

--- The warning goes on the real frame, and the callout says it goes away again.
local function ThreatDemo(slot)
	-- THE REAL FRAME REALLY WEARS IT. Threat owns what a threat record is, so
	-- this asks for a preview rather than assembling one - and the preview
	-- clears itself the way a real warning does, when its dwell runs out
	-- against a live state of nothing. The undo is here for the case where it
	-- does not get that far, which is somebody pressing Next after one second.
	local TH = A.GetModule and A:GetModule("threat")
	if TH and TH.Preview then
		TH:Preview("player")
		OB:OnLeave(function()
			-- ClearPreview rather than Draw(nil): the alarm holds itself up so
			-- that it can be read, and Draw honours the hold. Handed nothing,
			-- it redraws the held record - so the ring stayed gold on a frame
			-- that was not in a fight.
			if TH.ClearPreview then TH:ClearPreview("player") end
		end)
	end

	-- AND THE CALLOUT NARRATES rather than drawing a second capsule.
	--
	-- The deck puts a miniature of the warned capsule in here and was right to:
	-- the deck had nothing else to show it on. We have - this stop's spotlight
	-- IS the player frame, and it is wearing the warning a few inches away
	-- while you read this. Two of the same capsule side by side is the reader
	-- working out which one is the real one.
	--
	-- What the callout adds is the half the frame cannot say: that it stops.
	-- And it says it WITHOUT the chip's own words, deliberately - those are
	-- role-dependent and they live in Threat's own table. Spelling "HIGH
	-- THREAT" here would be a copy of that table which is wrong for a tank.
	local warn = StatePill(slot, "threat.warn")
	local chev = Chev(slot, "threat.chev")
	local calm = StatePill(slot, "threat.calm")

	warn:ClearAllPoints()
	warn:SetPoint("LEFT", slot, "LEFT", 0, 0)
	chev:ClearAllPoints()
	chev:SetPoint("LEFT", warn, "RIGHT", 9, 0)
	calm:ClearAllPoints()
	calm:SetPoint("LEFT", chev, "RIGHT", 9, 0)

	warn:Say("trouble coming", Palette.c.semanticGold)
	calm:Say("eased off — quiet again", Palette.c.friendly)
	slot:SetHeight(STATE_H)

	local state = nil
	Play(slot, function(at)
		local want = (at < SWAP_AT) and "warned" or "eased"
		if want == state then return want == "warned" end
		state = want

		if want == "warned" then
			-- Set here rather than once before the play, so a second visit to
			-- this stop starts where the first one did.
			warn:SetAlpha(1)
			chev:SetAlpha(0.25)
			calm:SetAlpha(0.18)
			return true
		end

		chev:SetAlpha(1)
		calm:SetAlpha(1)
		-- The gold has had its moment. Both left lit says both are true.
		warn:SetAlpha(0.35)
		return false
	end)
end

-- ---------------------------------------------------------------------------
-- stop 8: the flight console
-- ---------------------------------------------------------------------------

--- What is actually aboard, and the programme it would make.
--
--  READ OFF THE REAL LIBRARY. The first version drew a made-up flight from
--  Booty Bay to Ironforge with three invented legs on it, and it was a picture
--  of the feature rather than the feature - which is exactly what Joe said when
--  he saw it: it does not show us the console.
--
--  This does. The title is the first thing the console would really play, the
--  bar is the console's own segmented bar filled from the real durations in the
--  three channel colours, and the line under it counts what is installed in the
--  library's own three words. On a clone with no audio in it, it says so.
local function IfecDemo(slot)
	local Content = A.IFEC and A.IFEC.Content

	-- IN THE ORDER THE CONSOLE WOULD REACH FOR THEM. Everything() is the
	-- programme builder run over the whole library, so the first item here is
	-- the first item a flight would actually get - not the first one the
	-- registry happens to hold.
	local queue = (Content and Content:Everything()) or {}
	local all = (Content and Content:Available()) or {}

	-- The three channels in the library's order and its own words, because a
	-- filter tab reading "Stories" and a count reading "podcasts" are the same
	-- thing under two names.
	local CHANNELS = {
		{ key = "podcast", word = "Stories" },
		{ key = "music",   word = "Music" },
		{ key = "gossip",  word = "Gossip" },
	}
	local TINT = {
		podcast = Palette.c.ifecPodcast,
		music   = Palette.c.ifecMusic,
		gossip  = Palette.c.ifecGossip,
	}

	local count = {}
	for _, item in ipairs(all) do
		count[item.type] = (count[item.type] or 0) + 1
	end

	local pill = Kid(slot, "ifec.pill", 1, function(parent)
		-- A PANEL, not a pill. The deck draws this as a capsule and the deck's
		-- is one line tall; three rows in a capsule is a balloon - see the note
		-- on Glass.CreatePill, which clamps rather than draws one.
		local f = Glass.CreatePanel(parent, { corner = 12 })

		f.glyph = f:CreateTexture(nil, "OVERLAY")
		f.glyph:SetSize(13, 13)
		f.glyph:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -11)

		f.title = W.Text(f, "ifecTitle", "LEFT")
		f.title:SetPoint("LEFT", f.glyph, "RIGHT", 8, 0)
		f.title:SetPoint("RIGHT", f, "RIGHT", -12, 0)

		f.bar = W.CreateSegmentedBar(f, { height = BAR_H })
		f.bar:SetPoint("TOPLEFT", f.glyph, "BOTTOMLEFT", 0, -9)

		f.sub = W.Text(f, "ifecSub", "LEFT")
		f.sub:SetPoint("TOPLEFT", f.bar, "BOTTOMLEFT", 0, -6)
		return f
	end)

	pill:ClearAllPoints()
	pill:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
	pill:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, 0)

	local first = queue[1]
	if first then
		Media:SetIcon(pill.glyph, first.type)
		local tint = TINT[first.type] or Palette.c.accent
		W.Tint(pill.glyph, tint, 1)
		pill.title:SetText(first.title or "")
		W.Color(pill.title, Palette.c.text)

		local said = {}
		for _, ch in ipairs(CHANNELS) do
			local n = count[ch.key]
			if n then said[#said + 1] = n .. " " .. ch.word end
		end
		-- A middle dot, which this font has. See the glyph guard in the harness
		-- for the one it has not.
		pill.sub:SetText(table.concat(said, "  ·  "))
		W.Color(pill.sub, Palette.c.textFaint)
	else
		-- NOTHING INSTALLED IS A STATE, not a failure to load - a clone of this
		-- repository has the magazines and no audio, because the cut music is
		-- derived and untracked. The console still boards; it has nothing to
		-- play, and saying so is more use than an empty row.
		Media:SetIcon(pill.glyph, "music")
		W.Tint(pill.glyph, Palette.c.textFaint, 0.8)
		pill.title:SetText("Nothing installed yet")
		W.Color(pill.title, Palette.c.textDim)
		-- FROM THE CONSOLE, because there are three reasons for this and only
		-- one of them is "you have not installed it".
		pill.sub:SetText((Content and Content:DormantReason())
			or "No content installed")
		W.Color(pill.sub, Palette.c.textFaint)
	end

	-- The bar has one anchor, so its width is said here - and it is known by
	-- now, because the callout sized the slot before it asked for the demo.
	pill.bar:SetWidth(math.max(40, (slot:GetWidth() or CALLOUT_W) - 24))

	local h = 11 + math.max(13, pill.title:GetStringHeight() or 13) + 9 + BAR_H
		+ 6 + (pill.sub:GetStringHeight() or 12) + 11
	pill:SetHeight(h)
	slot:SetHeight(h)

	-- THE FIRST FEW LEGS, at their real lengths in their real colours. Four,
	-- because a whole library on a 300px bar is a row of hairlines - and the
	-- programme a flight gets is a handful of items, not all of them.
	--
	-- THE RAG IS NOT ON THE BAR, and that is not an omission. A programme is
	-- built to COVER a flight, so it is assembled out of things that take time;
	-- gossip is read rather than played and occupies none, so the builder never
	-- reaches for it. The bar says what will PLAY and the line above says what
	-- is ABOARD, which is a real distinction and the one the console makes.
	--
	-- A nominal slice was given to it here at first, to get its colour onto the
	-- bar. It was dead code from the moment it was written: nothing with no
	-- length ever arrives in this queue to be given one.
	local LEGS, TOTAL = {}, 0
	for i = 1, math.min(4, #queue) do
		local item = queue[i]
		local secs = (Content and Content:Length(item)) or 0
		if secs > 0 then
			LEGS[#LEGS + 1] = { secs, TINT[item.type] or Palette.c.accent }
			TOTAL = TOTAL + secs
		end
	end

	if TOTAL <= 0 then
		pill.bar:SetPieces({}, 1)
		slot:SetScript("OnUpdate", nil)
		return
	end

	local FILL = 1.6      -- seconds to fill the whole programme

	Play(slot, function(at)
		local through = math.min(1, at / FILL) * TOTAL
		local pieces, used = {}, 0
		for _, leg in ipairs(LEGS) do
			local secs = math.max(0, math.min(leg[1], through - used))
			if secs > 0 then
				pieces[#pieces + 1] =
					{ seconds = secs, colour = leg[2], filled = true }
			end
			used = used + leg[1]
		end
		pill.bar:SetPieces(pieces, TOTAL)
		return at < FILL
	end)
end

--- Which demo a SHOW stop plays.
local DEMOS = {
	bars   = BarsDemo,
	quests = QuestsDemo,
	bags   = BagsDemo,
	threat = ThreatDemo,
	ifec   = IfecDemo,
}

function OB:Demo(stop, slot)
	local fn = DEMOS[stop.key]
	if fn then fn(slot) end
end

-- ---------------------------------------------------------------------------
-- running
-- ---------------------------------------------------------------------------

--- Show one stop.
function OB:Go(index)
	if index < 1 then index = 1 end
	-- WHATEVER THE LAST STOP CHANGED, PUT BACK - before anything about this one
	-- is decided. Run after the new stop had set itself up, an undo would be
	-- closing the panel this stop had just opened.
	self:Undo()
	if index > OB.COUNT then return self:ShowFinish() end

	local stop = self.stops[index]
	if not stop then return end
	self.index = index

	-- WRITTEN THE MOMENT IT IS REACHED, not at the end. A player who alt-F4s
	-- on stop 5 comes back to stop 5.
	local s = Store()
	if s then s.stopIndex = index end

	BuildScrim():Show()
	FadeTo(self.scrim, 1, SCRIM_FADE)
	BuildSkip():Show()

	local c = BuildCallout()
	BuildNav(c)

	Drop()
	-- WHAT THIS STOP NEEDS ON SCREEN BEFORE THE SPOTLIGHT GOES LOOKING FOR IT.
	-- The bags stop points at the bag panel and the bag panel is shut: opened
	-- after the target had been resolved it would sit UNDER the scrim with no
	-- ring on it, which is the one place in the tour where the thing being
	-- described would be the only thing you could not see.
	if stop.before then stop.before() end
	local target = stop.target and stop.target()
	if target and target.IsVisible and target:IsVisible() then
		Lift(target)
		RingAround(target)
	else
		target = nil
		BuildRing():Hide()
	end

	c.kicker:SetText(("STEP %d OF %d · %s"):format(index, OB.COUNT, stop.name))
	c.head:SetText(stop.head)
	c.body:SetText(stop.body)
	W.Color(c.kicker, Palette.c.accent)
	W.Color(c.head, Palette.c.text)
	W.Color(c.body, Palette.c.textDim)

	-- The stop's own middle. Cleared first: the slot is shared, and a control
	-- left over from the last stop is a control that still works.
	if self.ClearSlot then self:ClearSlot(c.slot) end
	c.slot:SetHeight(1)
	if stop.kind == "set" and self.Control then
		self:Control(stop, c.slot)
	elseif stop.kind == "show" and self.Demo then
		self:Demo(stop, c.slot)
	end

	-- THE ALT OFFER, ON THE FIRST STOP AND NOWHERE ELSE.
	--
	-- A fresh character on an account that has already been set up is being
	-- asked four questions it has answered. The offer is the way out of them,
	-- and it belongs on the first one rather than on the welcome card: the card
	-- is where you decide whether to do this at all, and this is a shortcut
	-- through the doing.
	c.offer:Hide()
	if index == 1 then
		local key, who = self:Others()
		if key then
			c.offer.label:SetText(("Use %s's setup"):format(who))
			W.Color(c.offer.label, Palette.c.text)
			c.offer:SetScript("OnClick", function()
				OB:AdoptFrom(key)
				OB:Go(OB:FirstShow())
			end)
			c.offer:Show()
		end
	end

	PaintNav(c.nav, index)
	SizeCallout(c)
	PlaceCallout(c, target)

	c:Show()
	c:SetAlpha(0)
	FadeTo(c, 1, CALLOUT_FADE)
end

function OB:Next()
	self:Go((self.index or 0) + 1)
end

function OB:Back()
	-- BACK RESTORES NOTHING. Every value was written the moment it was
	-- touched, so there is nothing to undo - Back only re-shows the callout
	-- you were looking at. Which is the honest behaviour: a Back that silently
	-- reverted a palette you had chosen and moved on from would be a surprise.
	if (self.index or 1) <= 1 then return end
	self:Go(self.index - 1)
end

function OB:Skip()
	self:Finish()
end

--- Everything down, nothing left raised.
function OB:Teardown()
	-- EVERY OTHER WAY OUT comes through here: finishing, skipping, a fight
	-- starting, the module being switched off. Go handles stop-to-stop; this
	-- handles the rest, and between them there is no exit that leaves a demo's
	-- change standing.
	self:Undo()
	Drop()
	if self.ring then self.ring:Hide() end
	if self.callout then self.callout:Hide() end
	if self.skip then self.skip:Hide() end
	if self.card then self.card:Hide() end
	if self.toast then self.toast:Hide() end
	if self.scrim then self.scrim:Hide() end
	self.index = nil
end

--- Start at the top, from a fresh character or from the Toolbox.
function OB:Start()
	if InCombatLockdown() then
		A:Print("not during a fight - try again when it is over.")
		return false
	end
	local s = Store()
	if s then s.completed = nil end
	self:ShowWelcome()
	return true
end

-- ---------------------------------------------------------------------------
-- the resume toast
--
-- ONE QUIET LINE, AND ONLY ONE. Somebody who left half way through has already
-- shown you what they think of being interrupted, so this is not the tour
-- coming back - it is a door being held open, once, with a handle on it for
-- shutting it for good. Dismissing counts as skipping, which is the design's
-- own rule and the reason there is never a second toast.
--
-- PARENTED TO UIParent AND AT THE PROFILE'S SCALE, unlike the tour itself. The
-- tour hangs off a parentless scrim because it has to draw OVER a faded world;
-- this is a notice sitting on the HUD with everything else, so it is the size
-- of everything else.
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
	t.go:SetText("Resume")

	-- The shared close, which is also the shared HIT SIZE: a dismiss smaller
	-- than the thing it dismisses is a dismiss people miss and click through.
	t.close = W.CloseButton(t)
	t.close:SetScript("OnClick", function()
		-- DISMISSING IS SKIPPING. The design says so, and it is the only
		-- reading that makes this a single toast rather than a nag: a dismiss
		-- that only closed the window would be answered with another one at
		-- the next login.
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

--- Take the toast down without answering it, which the two answers both do
--- first: one goes on to resume and the other to mark the character done.
function OB:Hush()
	if self.toast then self.toast:Hide() end
end

--- "Finish setup? N stops left"
function OB:ShowResume(at)
	at = math.max(1, math.min(tonumber(at) or 1, OB.COUNT))
	local left = OB.COUNT - at + 1

	local t = BuildToast()
	t:SetScale((A.db and A.db.profile and A.db.profile.scale) or 1)
	t.label:SetText(("Finish setup? %d stop%s left")
		:format(left, left == 1 and "" or "s"))
	W.Color(t.label, Palette.c.text)
	W.Color(t.go, Palette.c.accent)

	-- Sized to what it says, because a fixed width is either too wide for one
	-- stop left or too narrow for nine.
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

--- Welcome and Finish share one panel: same family in the deck, same shape
--  here, and the alternative is two nearly identical builders drifting apart.
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

	c.head = W.Text(c, "tbTitle", "LEFT")
	c.head:SetPoint("TOPLEFT", c.kicker, "BOTTOMLEFT", 0, -10)
	c.head:SetWidth(CARD_W - 56)
	c.head:SetWordWrap(true)

	c.body = W.Text(c, "tbCardBody", "LEFT")
	c.body:SetPoint("TOPLEFT", c.head, "BOTTOMLEFT", 0, -10)
	c.body:SetWidth(CARD_W - 56)
	c.body:SetWordWrap(true)

	c.lines = {}
	for i = 1, 4 do
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

	-- A PLAIN BUTTON, NOT A GLASS ONE. This is the quiet half of the pair and
	-- the deck draws it as bare text beside the filled pill - so it was built
	-- with `fill = "none"`, which is not a token: Glass has no transparent
	-- fill, the lookup misses, and the surface keeps whatever colour it was
	-- born with for the rest of the session. It went unnoticed because nothing
	-- built this card before the skin checks ran.
	--
	-- The skip line at the foot of the screen is the same shape and was already
	-- written this way; this is that, on a card.
	c.alt = CreateFrame("Button", nil, c)
	c.alt:SetSize(120, 28)
	c.alt.label = W.Text(c.alt, "tbLabel", "CENTER")
	c.alt.label:SetPoint("CENTER")
	c.alt:SetScript("OnEnter", function(b) W.Color(b.label, Palette.c.text) end)
	c.alt:SetScript("OnLeave", function(b) W.Color(b.label, Palette.c.textDim) end)

	c.note = W.Text(c, "tbLabel", "RIGHT")

	OB.card = c
	return c
end

--- Stack the card's parts and size it to them.
local function LayCard(c, lines)
	local y = -26
	y = y - (c.kicker:GetStringHeight() or 0) - 10
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
	c.alt:SetPoint("LEFT", c.go, "RIGHT", 12, 0)
	c.note:ClearAllPoints()
	c.note:SetPoint("RIGHT", c, "RIGHT", -28, 0)
	c.note:SetPoint("TOP", c.go, "TOP", 0, 0)
	c.note:SetHeight(28)

	c:SetHeight(-y + 20 + 28 + 26)
end

function OB:ShowWelcome()
	BuildScrim():Show()
	self.scrim:SetAlpha(0)
	FadeTo(self.scrim, 1, SCRIM_FADE)
	if self.callout then self.callout:Hide() end
	if self.skip then self.skip:Hide() end

	local c = BuildCard()
	c.kicker:SetText("AETHER UI")
	c.head:SetText("A quieter, glassier way to play")
	c.body:SetText("Your whole interface, rebuilt as calm dark glass — nothing "
		.. "shouts, everything is where you left it. A quick tour will set you "
		.. "up; every choice applies live and nothing is locked in.")
	W.Color(c.kicker, Palette.c.accent)
	W.Color(c.head, Palette.c.text)
	W.Color(c.body, Palette.c.textDim)

	LayCard(c, {
		"Four carefully curated palettes — Midnight, Dawn, Noon, Dusk; one tap "
		.. "recolours the whole UI",
		"Everything movable — unit frames and panels float free, snap to a "
		.. "grid, saved per character",
		"A UI that knows the moment — the quest tracker ducks in combat, "
		.. "flights get in-flight entertainment",
		"Smarter everyday tools — auto-sorted bags, one Toolbox for every "
		.. "panel and addon",
	})

	c.go.label:SetText("Take the tour")
	W.Color(c.go.label, Palette.c.text)
	c.go:SetScript("OnClick", function() c:Hide() OB:Go(1) end)

	c.alt:Show()
	c.alt.label:SetText("Skip the tour")
	W.Color(c.alt.label, Palette.c.textDim)
	c.alt:SetScript("OnClick", function() OB:Skip() end)

	-- HONEST, and the deck says so in as many words. A tour that claims to be
	-- quick and is not is one nobody finishes.
	c.note:SetText("~1 minute")
	W.Color(c.note, Palette.c.textFaint)

	c:Show()
end

function OB:ShowFinish()
	Drop()
	if self.ring then self.ring:Hide() end
	if self.callout then self.callout:Hide() end
	if self.skip then self.skip:Hide() end

	local c = BuildCard()
	c.kicker:SetText("ALL SET")
	c.head:SetText("Your HUD, your way. Go break it in.")
	c.body:SetText("")
	W.Color(c.kicker, Palette.c.accent)
	W.Color(c.head, Palette.c.text)

	-- WHAT YOU ACTUALLY CHOSE, read back out of the systems that own it rather
	-- than out of anything the tour remembered. If the recap and the HUD ever
	-- disagree, the recap is the one that is wrong.
	local skin = Palette.skins[Palette.current]
	local preset = A.Presets and A.Presets:Current()
	local presetName = preset and A.Presets.list[preset]
		and A.Presets.list[preset].label or "a layout of your own"
	local edge = A.db and A.db.char and A.db.char.toolbox
		and A.db.char.toolbox.docked or "LEFT"

	LayCard(c, {
		("%s palette · %s · Toolbox %s"):format(
			(skin and skin.label) or "Midnight", presetName, edge:lower()),
		-- NO ARROW. The deck writes this with a rightwards arrow between
		-- "Toolbox" and "Layout", and the
		-- interface font has not got that character - it came out as a hollow
		-- box in game. Every arrow this addon draws is a TEXTURE for exactly
		-- that reason (Media.texture.chevron); a line of recap text is not
		-- worth a texture, so it is worded without one.
		"Fine-tune anytime: unlock frames from the Toolbox and drag any of them",
		"Re-run this tour: /aether tour",
	})

	c.go.label:SetText("Done")
	W.Color(c.go.label, Palette.c.text)
	c.go:SetScript("OnClick", function() OB:Finish() end)
	c.alt:Hide()
	c.note:SetText("")

	c:Show()
end

-- ---------------------------------------------------------------------------
-- combat, and coming back
-- ---------------------------------------------------------------------------

--- A fight takes the tour down instantly.
--
--  NOT PAUSED, DROPPED. Whatever else is true when a mob opens on you, a scrim
--  over the world and a panel over your action bars are the two things you
--  least want - and half of what the tour lifts is secure, which cannot be put
--  back where it belongs until the fight is over anyway.
function OB:OnCombat()
	if not self.index and not (self.card and self.card:IsShown()) then return end
	self.resumeAt = self.index
	self:Teardown()
end

--- What this character sees when it arrives.
--
--  THREE ANSWERS, AND THE FIRST ONE IS NOTHING. A character that has finished
--  or skipped is never asked again, by anything, ever - which is the promise
--  that makes a first-run tour tolerable at all.
--
--  Then a stop index, which means somebody was half way through when they
--  logged out: one quiet toast rather than the tour reopening over whatever
--  they logged in to do.
--
--  And otherwise the welcome card, which is the first run.
function OB:OnLogin()
	if self:Completed() then return end

	-- NOT DURING A FIGHT, and not dropped either: held until it ends, down the
	-- same door an interrupted tour already uses.
	if InCombatLockdown() then
		self.__pendingLogin = true
		return
	end

	local s = Store()
	local at = tonumber(s and s.stopIndex) or 0
	if at > 0 then
		self:ShowResume(at)
	else
		self:ShowWelcome()
	end
end

function OB:OnCombatOver()
	if self.__pendingLogin then
		self.__pendingLogin = nil
		return self:OnLogin()
	end
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
	A:RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
		OB:OnCombat()
	end)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
		OB:OnCombatOver()
	end)

	-- THE FIRST RUN, ONCE.
	--
	-- PLAYER_ENTERING_WORLD rather than login, because it is the one that also
	-- arrives after a loading screen - and once, because it arrives after EVERY
	-- loading screen. A tour that reopened on the far side of a zone line would
	-- be the thing this whole file is written to avoid.
	--
	-- AND A BEAT LATER. The tour spotlights real frames and places its callout
	-- against them, and at the moment this fires the unit frames have been
	-- built but not yet had their saved positions restored - so a callout
	-- placed now is placed beside where a frame was going to be.
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		if OB.__arrived then return end
		OB.__arrived = true
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(FIRST_RUN_DELAY, function() OB:OnLogin() end)
		else
			OB:OnLogin()
		end
	end)
end

function OB:OnDisable()
	self:Teardown()
end

return OB
