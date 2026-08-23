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
		s.stopIndex = nil
	end
	self:Teardown()
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
		key   = "bars",
		name  = "ACTION BARS",
		head  = "Your spells, undecorated.",
		body  = "Cooldowns, charges and range all draw ON the icon — no extra "
			.. "widgets. Watch: this one's on cooldown.",
		kind  = "show",
		target = function()
			local AB = A.GetModule and A:GetModule("actionbars")
			return AB and AB.Bar and AB:Bar("1")
		end,
	},
	{
		key   = "quests",
		name  = "QUEST TRACKER",
		head  = "It knows when you're busy.",
		body  = "The tracker folds itself away the moment combat starts and "
			.. "returns when it ends — like this.",
		kind  = "show",
		target = function()
			local QT = A.GetModule and A:GetModule("questtracker")
			return QT and QT.frame
		end,
	},
	{
		key   = "bags",
		name  = "BAGS",
		head  = "One bag. Everything in its place.",
		body  = "All your bags pour into one organised panel — gear, potions, "
			.. "trade goods, junk, each under its own heading.",
		kind  = "show",
		target = function()
			local BG = A.GetModule and A:GetModule("bags")
			return BG and BG.frame
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
		body  = "Music, podcasts and a truly disreputable gossip rag, timed to "
			.. "your route. It boards automatically on your next flight.",
		kind  = "show",
		target = function()
			local M = A.GetModule and A:GetModule("ifec")
			return M and M.mini and M.mini.frame
		end,
	},
}

OB.COUNT = #OB.stops

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

--- Beside the element, on whichever side has room.
--
--  MEASURED AGAINST THE SCREEN, not chosen by the stop. Which side of a frame
--  has room depends on where the player has dragged that frame, and a callout
--  anchored "to the right of the player frame" by a designer looking at their
--  own layout is a callout half off the screen on somebody else's.
local function PlaceCallout(c, frame)
	c:ClearAllPoints()
	c.arrow:Hide()

	if not frame or not frame.GetCenter or not frame:GetCenter() then
		c:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		return
	end

	local cx = select(1, frame:GetCenter()) or 0
	local sw = (UIParent:GetWidth() or 0)
	local right = cx < sw / 2

	if right then
		c:SetPoint("LEFT", frame, "RIGHT", CALLOUT_GAP, 0)
		c.arrow:ClearAllPoints()
		c.arrow:SetPoint("CENTER", c, "LEFT", 0, 0)
	else
		c:SetPoint("RIGHT", frame, "LEFT", -CALLOUT_GAP, 0)
		c.arrow:ClearAllPoints()
		c.arrow:SetPoint("CENTER", c, "RIGHT", 0, 0)
	end

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
			f:SetScript("OnClick", nil)
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
local UNITS = { player = true, target = true, pet = true, party = true }

local function Wireframe(box, preset)
	box.marks = box.marks or {}
	for _, m in ipairs(box.marks) do m:Hide() end

	local n = 0
	for name, a in pairs(preset.anchors or {}) do
		local bar = name:find("^bar") ~= nil
		if UNITS[name] or bar then
			n = n + 1
			local m = box.marks[n]
			if not m then
				m = box:CreateTexture(nil, "OVERLAY")
				m:SetTexture(A.Media.texture.flat)
				box.marks[n] = m
			end

			-- The fraction is an offset from the anchor point, so it is turned
			-- into a position on the box the same way Presets turns it into a
			-- position on the screen: from the corner it is measured from.
			local bw, bh = box:GetWidth(), box:GetHeight()
			local px = (a.fx or 0) * bw
			local py = (a.fy or 0) * bh
			m:SetSize(bar and bw * 0.22 or bw * 0.16, math.max(2, bh * 0.09))
			m:ClearAllPoints()
			m:SetPoint("CENTER", box, a.point or "CENTER", px, py)
			W.Tint(m, Palette.c.accent, bar and 0.45 or 0.7)
			m:Show()
		end
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
}

function OB:Control(stop, slot)
	local fn = CONTROLS[stop.key]
	if fn then fn(slot) end
end

-- ---------------------------------------------------------------------------
-- running
-- ---------------------------------------------------------------------------

--- Show one stop.
function OB:Go(index)
	if index < 1 then index = 1 end
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
	Drop()
	if self.ring then self.ring:Hide() end
	if self.callout then self.callout:Hide() end
	if self.skip then self.skip:Hide() end
	if self.card then self.card:Hide() end
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

	c.alt = W.CreateButton(c, { corner = 12, fill = "none" })
	c.alt:SetSize(120, 28)
	c.alt.label = W.Text(c.alt, "tbLabel", "CENTER")
	c.alt.label:SetPoint("CENTER")

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
		and A.Presets.list[preset].label or "your own layout"
	local edge = A.db and A.db.char and A.db.char.toolbox
		and A.db.char.toolbox.docked or "LEFT"

	LayCard(c, {
		("%s palette · %s · Toolbox %s"):format(
			(skin and skin.label) or "Midnight", presetName, edge:lower()),
		"Fine-tune anytime: Toolbox → Layout unlocks every frame",
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

function OB:OnCombatOver()
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
end

function OB:OnDisable()
	self:Teardown()
end

return OB
