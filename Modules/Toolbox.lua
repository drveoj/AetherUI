--[[--------------------------------------------------------------------------
	AetherUI :: Toolbox

	Concept 4: a drawer docked to the centre of a screen edge, with a slim rail
	that stays on screen when the drawer is closed.

	This file is layer 1 of docs/PLAN-Toolbox.md - the frame, the dock, the
	slide and the scrim. Nothing goes inside it yet, deliberately: the panel has
	two layouts and two sizes and both have to be right before anything is laid
	out within them.

	Overlay, never reflow
	---------------------
	The drawer slides out OVER the HUD. Nothing beneath moves, which in WoW is
	free - there is no layout to disturb - so the only work is strata. It sits at
	FULLSCREEN_DIALOG, above the HUD and below tooltips, and a scrim dims the
	strip it covers so the covered UI reads as behind rather than merely dark.

	Two layouts, and the numbers are the deck's
	-------------------------------------------
	Left and right docks use the vertical panel (388x910 deck px); top and bottom
	use the horizontal one (1280 wide). Everything is drawn at profile.scale like
	the quest log and the bags window, so at the default 0.71 the vertical panel
	is 276x646 against a 768-unit screen and the horizontal is 909 of 1365. Both
	fit, and the harness checks that at 0.71 AND at 1.0 - a panel that fits at
	the deck's own scale and overflows at 1.0 is a panel nobody with a big UI
	scale can use.

	The rail's width is DERIVED from the icon size rather than written down. The
	deck draws it about 52px wide, which is a 34px icon with 9 either side; write
	52 and the day somebody changes the icon size the rail stops fitting it.

	Sliding
	-------
	There is no transition system, so the slide is an OnUpdate lerp. It must be
	INTERRUPTIBLE: clicking the chevron twice quickly should reverse, not queue.
	That is why there is a single `_travel` in 0..1 driven toward `_want` rather
	than a start time and a duration - reversing is then just changing `_want`,
	and the frame carries on from wherever it had got to.

	Docking is not a Mover
	----------------------
	Every other placeable frame here uses Core/Movers.lua. This one does not, and
	the reason is worth stating so nobody wires it in later: a mover means
	"anywhere, remembered against the nearest corner", and this drawer has
	exactly four legal positions, each of which changes the panel's LAYOUT rather
	than its offset.

	So dragging the rail to re-dock is its OWN gesture, further down this file.
	It borrows one thing from Movers and nothing else: the moment placement mode
	turns on, via Movers:OnLockChanged. That matters because the drawer was the
	only thing on screen you could not place after `/aether unlock` - every other
	frame grew a handle and this one silently did not, which reads as the drawer
	being fixed rather than as it having a different gesture.

	`docked` and `open` live in db.char. A drawer edge is a per-character habit
	the way tracked quests are.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local TB = A:NewModule("toolbox")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- The deck's own pixels. Drawn at profile.scale, like the quest log and bags.
local PANEL_V_W, PANEL_V_H = 388, 910
local PANEL_H_W, PANEL_H_H = 1280, 240

-- The rail. Width comes from the icon it has to hold, not from the 52 the deck
-- happens to measure.
local RAIL_ICON  = 26
local RAIL_PAD   = 7
local RAIL_W     = RAIL_ICON + RAIL_PAD * 2
-- The chevron is a HINT, not a button you hunt for: it was 26 against a 34 icon
-- and read as the largest thing on the rail. Half that, and the rail reads as a
-- seam with a handle rather than a column of controls.
local RAIL_CHEV  = 14
-- A DRAWER-PULL, not a capsule. At 16 on a 40-wide rail the two corner slices
-- are 32 of the 40 and the ends read as semicircles - which is a pill, which is
-- exactly what it looked like. 8 leaves a flat run down the middle of each end
-- and the shape reads as a handle on the side of a drawer.
-- How big the rail's OWN glyphs are drawn.
--
-- These are bare line glyphs on the rail itself - no chip, no rim - and that is
-- deliberate: the envelope and the gear are part of the rail, and the launchers
-- look different because they ARE different, being other addons' art in their
-- own circles. What was wrong was the size. At RAIL_ICON - 8 they were 18px of
-- thin line beside 26px filled discs and read as an afterthought.
--
-- Two off the icon size rather than flush with it: a line glyph needs a little
-- air inside a 26 slot where a filled disc does not, and at 24 the envelope's
-- stroke lands on a comfortable pixel and a half.
local RAIL_GLYPH = RAIL_ICON - 2

local RAIL_CORNER = 8

-- How far the rail sits INTO the panel. Without this it is a separate capsule
-- floating beside the drawer with its own rounded inner edge - two shapes with
-- a gap of shadow between them. Overlapped by its corner radius, the inner
-- curve is hidden behind the panel and the rail reads as a tab growing out of
-- the drawer's edge. When the drawer is shut the same overlap puts that curve
-- off the screen edge, so it hugs there too.
local RAIL_BITE  = 14

local PANEL_CORNER = 28

-- 300-400ms, per the handoff. Expressed as a rate so the lerp is reversible.
local SLIDE_RATE = 1 / 0.34

local EDGES = { LEFT = true, RIGHT = true, TOP = true, BOTTOM = true }

-- The same four, in an order. `pairs` over EDGES is fine for asking "is this an
-- edge" and useless for building four ghosts, which have to come out the same
-- way every time or the harness is testing a coin toss.
local EDGE_ORDER = { "LEFT", "RIGHT", "TOP", "BOTTOM" }

local function IsVertical(edge)
	return edge == "LEFT" or edge == "RIGHT"
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

local function Char()
	if not A.db or not A.db.char then return nil end
	A.db.char.toolbox = A.db.char.toolbox or {}
	local t = A.db.char.toolbox
	if t.docked == nil or not EDGES[t.docked] then t.docked = "LEFT" end
	if t.open == nil then t.open = false end
	return t
end

function TB:Dock()
	local c = Char()
	return (c and c.docked) or "LEFT"
end

function TB:IsOpen()
	local c = Char()
	return (c and c.open) or false
end

-- ---------------------------------------------------------------------------
-- construction
-- ---------------------------------------------------------------------------

function TB:Build()
	if self.panel then return end

	-- The scrim, underneath everything the drawer draws.
	--
	-- SHAPED LIKE THE PANEL, not a rectangle. It was a plain SetColorTexture
	-- sized to the panel's bounds, which is square - so at each of the four
	-- corners, where the panel curves away, the scrim's own corner carried on
	-- and showed as a hard black notch outside the rounding. Four of them, one
	-- per corner, which is exactly what got reported.
	--
	-- A Glass panel at the same radius is the same rounded shape by
	-- construction, and it costs nothing extra: the 9-slice is already loaded.
	-- Tinted black, with its rim taken off - a scrim with an edge is a second
	-- outline a finger-width outside the first.
	local scrim = Glass.CreatePanel(UIParent, { corner = PANEL_CORNER })
	scrim:SetFrameStrata("FULLSCREEN_DIALOG")
	scrim:SetFrameLevel(1)
	scrim:SetFillColor({ 0, 0, 0, 1 })
	scrim:SetEdgeColor({ 0, 0, 0, 0 })
	scrim:Hide()
	self.scrim = scrim

	local panel = Glass.CreatePanel(UIParent, {
		corner = PANEL_CORNER,
		shadow = A.db.profile.glass.shadow,
	})
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetFrameLevel(10)
	-- A READING FILL, like the quest log and the chat. This is a drawer that
	-- slides out OVER whatever is behind it - a quest window, the world, another
	-- addon's panel - carrying five columns of small text. At the opacity a
	-- button uses, all of that shows through every line of it.
	self.panel = panel

	-- The rail is a surface of its own rather than a region of the panel: it
	-- stays on screen when the drawer is shut, so it cannot be part of the thing
	-- that slides away.
	--
	-- A PANEL, not a pill. A pill's caps sit left and right and take their width
	-- from the height, which is right for the version chip and wrong for a rail
	-- that is four times taller than it is wide: the caps overlap through the
	-- middle and it renders as one huge circle. A 9-slice panel is the same
	-- rounded shape at any aspect.
	local rail = Glass.CreatePanel(UIParent, {
		corner = RAIL_CORNER,
		shadow = A.db.profile.glass.shadow,
	})
	rail:SetFrameStrata("FULLSCREEN_DIALOG")
	rail:SetFrameLevel(20)
	self.rail = rail

	local chev = CreateFrame("Button", nil, rail)
	chev:SetSize(RAIL_CHEV, RAIL_CHEV)
	local glyph = chev:CreateTexture(nil, "ARTWORK")
	glyph:SetAllPoints(chev)
	glyph:SetTexture(Media.texture.chevron)
	chev.glyph = glyph
	chev:SetScript("OnClick", function() TB:Toggle() end)
	rail.chev = chev

	-- The gear, at the far end of the rail. The drawer carries the settings the
	-- deck asks for; this is the way to the rest of them, and it belongs on the
	-- rail because it has to be reachable with the drawer shut.
	local gear = CreateFrame("Button", nil, rail)
	gear:SetSize(RAIL_ICON, RAIL_ICON)
	-- NOT a unicode gear. Outfit is a text face with no geometric shapes in it -
	-- generate_textures.py says as much where it draws the chevron from line
	-- segments rather than borrowing a glyph - so U+2699 came out as the three
	-- bytes of its own UTF-8 rendered as latin: "]lk" on the rail.
	--
	-- A ring stands in until there is real art. It is a shape rather than a
	-- symbol, which is the honest version of "we have no gear yet"; the concept
	-- wants a gear or the star, and both need a generator pass.
	local gg = gear:CreateTexture(nil, "ARTWORK")
	gg:SetPoint("CENTER", gear, "CENTER", 0, 0)
	gg:SetSize(RAIL_GLYPH, RAIL_GLYPH)
	Media:SetIcon(gg, "gear")
	gear.glyph = gg
	gear:SetScript("OnClick", function()
		if A.Options and A.Options.Open then A.Options:Open() end
	end)
	gear:SetScript("OnEnter", function(self2)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
		GameTooltip:SetText("AetherUI settings")
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	rail.gear = gear

	-- Mail, immediately above the gear. On the rail rather than only inside the
	-- drawer because "you have mail" is the one thing here you need to see with
	-- the drawer SHUT - it is the reason the minimap carried an indicator at all,
	-- and that indicator is gone now.
	--
	-- Always present, never hidden: an envelope that only exists when there is
	-- mail is an icon that moves the gear every time the postman calls. Empty
	-- and full are two cells of the sheet, the way pin and pinned are.
	local mail = CreateFrame("Button", nil, rail)
	mail:SetSize(RAIL_ICON, RAIL_ICON)
	local mg = mail:CreateTexture(nil, "ARTWORK")
	mg:SetPoint("CENTER", mail, "CENTER", 0, 0)
	mg:SetSize(RAIL_GLYPH, RAIL_GLYPH)
	Media:SetIcon(mg, "mail")
	mail.glyph = mg
	mail:SetScript("OnClick", function() TB:Toggle() end)
	mail:SetScript("OnEnter", function(self2) TB:MailTooltip(self2) end)
	mail:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	rail.mail = mail

	-- The mini-player's transport. On the rail for the same reason the envelope
	-- is: "stop this" is the one thing about the player you need with the drawer
	-- SHUT, and everything else about it can wait for the drawer to open. It is
	-- also the only thing on screen saying something is playing at all.
	--
	-- Dressed by the IFEC's own mini-player rather than scripted here, so the
	-- Toolbox owns where it sits and how big it is and knows nothing else about
	-- it. With that half of the addon absent the chip simply never appears.
	local play = CreateFrame("Button", nil, rail)
	play:SetSize(RAIL_ICON, RAIL_ICON)
	local pg = play:CreateTexture(nil, "ARTWORK")
	pg:SetPoint("CENTER", play, "CENTER", 0, 0)
	pg:SetSize(RAIL_GLYPH - 8, RAIL_GLYPH - 8)
	Media:SetIcon(pg, "play")
	play.glyph = pg
	play:Hide()
	rail.play = play

	self._travel = self:IsOpen() and 1 or 0
	self._want   = self._travel

	self:Layout()
	self:ApplySkin()
end

function TB:ApplySkin()
	if not self.panel then return end
	self.panel:ApplySkin()
	-- Re-asserted after ApplySkin, which puts the token fill back. Here and
	-- nowhere else: Build calls this, so setting it at construction as well
	-- would be a second owner for one fact.
	self.panel:SetFillColor(Palette:ReadingFill())
	self.rail:ApplySkin()
	local c = Palette.c
	if self.rail.chev and c.text then
		self.rail.chev.glyph:SetVertexColor(c.text[1], c.text[2], c.text[3], 0.75)
	end
	-- Re-tinted here rather than only on a mail event: a restyle changes what
	-- the accent IS, and the envelope is the one glyph on the rail that carries
	-- it.
	self:RefreshMail()
	if self.scrim then
		-- Re-asserted on a skin change, because ApplySkin is what a restyle calls
		-- and it would otherwise put the glass tint back on a frame that is
		-- meant to be black.
		self.scrim:SetFillColor({ 0, 0, 0, 1 })
		self.scrim:SetEdgeColor({ 0, 0, 0, 0 })
	end
	-- The placement furniture is accent-coloured, and a restyle changes what the
	-- accent IS. Only worth doing if it has been built - which it has not, for
	-- anyone who has never unlocked their frames.
	if self._dockHandle then
		self._dockHandle:ApplySkin()
		self._dockHandle:SetFillColor({ c.accent[1], c.accent[2], c.accent[3], 0.22 })
		self._dockHandle:SetEdgeColor({ c.accent[1], c.accent[2], c.accent[3], 0.85 })
		W.Color(self._dockHandle.label, c.text)
	end
	if self._ghosts then
		for _, e in ipairs(EDGE_ORDER) do self._ghosts[e]:ApplySkin() end
		self:HighlightGhost(self._litGhost)
	end
end

-- ---------------------------------------------------------------------------
-- geometry
-- ---------------------------------------------------------------------------

--- Panel size for a dock, in the panel's own units.
--
--  The deck's numbers, capped at the deck's own PROPORTION of the screen, and
--  the cap is not decoration - it is the first thing that had to be checked and
--  it failed. 910 deck px is 84% of the deck's 1080-tall canvas, which at
--  profile.scale 0.71 is 646 of a 768-unit screen and fits with room to spare.
--  At scale 1.0 the same 910 is 910 of 768: eighteen per cent taller than the
--  screen, hanging off both ends, on any UI running at full scale.
--
--  So the size is the deck value or the deck's fraction of the screen,
--  whichever is smaller. At 0.71 the screen is 1082 panel units tall and the
--  cap lands at 912, so the deck's 910 wins untouched and nothing changes for
--  anyone using the design scale. At 1.0 it clamps to 647 and the drawer keeps
--  the same share of the screen the deck drew it with, which is what the
--  proportion was expressing in the first place.
--
--  The handoff's "fixed panel size" is about not resizing with CONTENT. It is
--  not a claim that the panel can be bigger than the screen.
local DECK_W, DECK_H = 1920, 1080

function TB:PanelSize(edge)
	local scale = A.db.profile.scale or 1
	if scale <= 0 then scale = 1 end

	local sw = ((UIParent:GetWidth()  or 1365) / scale)
	local sh = ((UIParent:GetHeight() or 768)  / scale)

	if IsVertical(edge) then
		return math.min(PANEL_V_W, sw * (PANEL_V_W / DECK_W)),
		       math.min(PANEL_V_H, sh * (PANEL_V_H / DECK_H))
	end

	-- The flat panel has a FLOOR as well as a cap, and the vertical one does not.
	--
	-- The proportional clamp is the right rule for a panel whose height is the
	-- long axis: shrink it and you lose rows off a list, which is what the addon
	-- list gives way for. On the flat panel height is the SHORT axis and nothing
	-- on it is a list - the identity column is a title, a card and a row of
	-- glyphs, all fixed - so shrinking it does not drop rows, it draws them
	-- through the floor. On a 600-unit screen at scale 1.0 the proportion asks
	-- for 133 against a column that cannot be built in less than 218.
	--
	-- So: no smaller than the tallest fixed column, and still never taller than
	-- the screen. The floor is a fifth of a 1080 canvas, so the second clamp only
	-- bites on something extraordinary.
	local floorH = math.min(self:HorizontalFloor(), sh)
	return math.min(PANEL_H_W, sw * (PANEL_H_W / DECK_W)),
	       math.min(PANEL_H_H, math.max(floorH, sh * (PANEL_H_H / DECK_H)))
end

--- How far off screen the panel sits when closed: its own depth on the docking
--  axis, so the whole thing clears the edge.
local function ClosedOffset(edge, w, h)
	if edge == "LEFT"  then return -w, 0 end
	if edge == "RIGHT" then return  w, 0 end
	if edge == "TOP"   then return  0, h end
	return 0, -h
end

function TB:Layout()
	if not self.panel then return end

	local edge  = self:Dock()
	local scale = A.db.profile.scale
	local w, h  = self:PanelSize(edge)

	self.panel:SetScale(scale)
	self.rail:SetScale(scale)
	self.scrim:SetScale(scale)

	self.panel:SetSize(w, h)
	Glass.SetPanelCorner(self.panel, PANEL_CORNER)

	-- The rail runs the panel's full extent on the cross axis in the deck, but
	-- only as far as its contents need; layer 1 has one chevron in it, so it is
	-- sized to that plus padding and grows later.
	-- Sized in LayoutRail, which knows how many pins there are. This is the
	-- floor: the chevron and the gear, which are always both there.
	local railLen = RAIL_PAD + RAIL_CHEV + RAIL_PAD + RAIL_ICON + RAIL_PAD
	if IsVertical(edge) then
		self.rail:SetSize(RAIL_W, math.max(self.rail:GetHeight() or 0, railLen))
	else
		self.rail:SetSize(math.max(self.rail:GetWidth() or 0, railLen), RAIL_W)
	end

	local ox, oy = ClosedOffset(edge, w, h)
	local t = self._travel or 0
	-- t = 0 closed (fully off screen), t = 1 open (flush to the edge)
	local dx, dy = ox * (1 - t), oy * (1 - t)

	self.panel:ClearAllPoints()
	self.rail:ClearAllPoints()
	self.scrim:ClearAllPoints()

	-- The rail bites INTO the panel so the curve on that side disappears behind
	-- the drawer and the two read as one shape - but it is anchored to the
	-- SCREEN and clamped, not hung off the panel.
	--
	-- Hung off the panel it travelled with it: shut, the panel is a full width
	-- off screen, so the rail went with it and sat a bite's worth past the
	-- screen edge with its left side - and the icons on it - cut off. The bite
	-- is a join with the panel, and there is nothing to join to once the panel
	-- has gone.
	--
	-- So the offset is computed and clamped at the edge. Open it lands inside
	-- the panel by RAIL_BITE; shut it stops flush against the screen, whole.
	if edge == "LEFT" then
		self.panel:SetPoint("LEFT", UIParent, "LEFT", dx, 0)
		self.rail:SetPoint("LEFT", UIParent, "LEFT",
			math.max(0, dx + w - RAIL_BITE), 0)
	elseif edge == "RIGHT" then
		self.panel:SetPoint("RIGHT", UIParent, "RIGHT", dx, 0)
		self.rail:SetPoint("RIGHT", UIParent, "RIGHT",
			math.min(0, dx - w + RAIL_BITE), 0)
	elseif edge == "TOP" then
		self.panel:SetPoint("TOP", UIParent, "TOP", 0, dy)
		self.rail:SetPoint("TOP", UIParent, "TOP", 0,
			math.min(0, dy - h + RAIL_BITE))
	else
		self.panel:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, dy)
		self.rail:SetPoint("BOTTOM", UIParent, "BOTTOM", 0,
			math.max(0, dy + h - RAIL_BITE))
	end

	-- Chevron at the inboard end, gear at the far one, pins between. The rail
	-- is read from the drawer outwards, so the control that closes it comes
	-- first.
	local vertical = IsVertical(edge)
	self.rail.chev:ClearAllPoints()
	self.rail.gear:ClearAllPoints()
	self.rail.mail:ClearAllPoints()
	self.rail.play:ClearAllPoints()
	-- Whether there is a transport at all is decided by RefreshPlayer, and the
	-- chain has to be built from what is SHOWING: anchored to a hidden frame the
	-- envelope keeps the geometry that frame would have had, so a season nobody
	-- has installed leaves an icon's worth of hole in the middle of the rail.
	self:RefreshPlayer()
	local hasPlay = self.rail.play:IsShown()
	local afterGear = hasPlay and self.rail.play or self.rail.gear

	if vertical then
		self.rail.chev:SetPoint("TOP", self.rail, "TOP", 0, -RAIL_PAD)
		self.rail.gear:SetPoint("BOTTOM", self.rail, "BOTTOM", 0, RAIL_PAD)
		-- IMMEDIATELY ABOVE THE GEAR. The two settled controls sit at the far
		-- end together: the way to the options and the way to stop the music.
		self.rail.play:SetPoint("BOTTOM", self.rail.gear, "TOP", 0, RAIL_PAD)
		self.rail.mail:SetPoint("BOTTOM", afterGear, "TOP", 0, RAIL_PAD)
	else
		self.rail.chev:SetPoint("LEFT", self.rail, "LEFT", RAIL_PAD, 0)
		self.rail.gear:SetPoint("RIGHT", self.rail, "RIGHT", -RAIL_PAD, 0)
		self.rail.play:SetPoint("RIGHT", self.rail.gear, "LEFT", -RAIL_PAD, 0)
		self.rail.mail:SetPoint("RIGHT", afterGear, "LEFT", -RAIL_PAD, 0)
	end

	-- The scrim covers exactly the strip the panel is over, so it travels with
	-- it rather than sitting still and being revealed.
	self.scrim:SetSize(w, h)
	self.scrim:SetPoint("CENTER", self.panel, "CENTER", 0, 0)
	Glass.SetPanelCorner(self.scrim, PANEL_CORNER)
	self.scrim:SetAlpha((tonumber(A.Config:Module('toolbox').scrim) or 0.28) * t)
	self.scrim:SetShown(t > 0.001)

	self:PointChevron()
end

-- Which way the chevron points, as a rotation of the art.
--
-- `Chevron.tga` IS A V - it points DOWN. The generator says so in as many
-- words ("A small V, for 'there is something folded away under here'"), and the
-- first version of this file assumed it pointed RIGHT and built its rotations
-- from there. Every dock was ninety degrees out: docked left, closed, it drew a
-- downward V on a drawer that opens sideways.
--
-- Rotation is counter-clockwise, so a down-pointing arrow (0, -1) becomes
-- (1, 0) - right - at +pi/2.
local CHEV_DOWN, CHEV_UP    = 0, math.pi
local CHEV_RIGHT, CHEV_LEFT = math.pi / 2, -math.pi / 2

--- The chevron points the way the drawer will go if you click it.
--
--  Left and right docks get < and >; top and bottom get ^ and v. The drawer
--  moves along the axis it is docked on, so an arrow across that axis would be
--  pointing at nothing.
function TB:PointChevron()
	local edge = self:Dock()
	local open = (self._want or 0) > 0.5
	local g = self.rail and self.rail.chev and self.rail.chev.glyph
	if not g then return end

	-- Open, the click RETREATS the drawer to its own edge; shut, it emerges
	-- away from it.
	-- W.PointChevron, which the party dock handle uses too. Eight cases and
	-- one of them backwards is an arrow pointing at nothing.
	self._chevronFacing = W.PointChevron(g, edge, open)
end

-- ---------------------------------------------------------------------------
-- opening and closing
-- ---------------------------------------------------------------------------

--- Driven from the shared ticker. `_travel` chases `_want`, so a click that
--  reverses direction mid-slide simply changes the target and the panel carries
--  on from where it is - no queue, no snap back to the start.
local function Slide(self, dt)
	local want = self._want or 0
	local at   = self._travel or 0
	if math.abs(want - at) < 0.001 then
		self._travel = want
		self:Layout()
		A:UnregisterTicker(self)
		self._sliding = nil
		return
	end

	local step = SLIDE_RATE * dt
	if want > at then
		at = math.min(want, at + step)
	else
		at = math.max(want, at - step)
	end
	self._travel = at
	self:Layout()
end

function TB:SetOpen(open, instant)
	local c = Char()
	if c then c.open = open and true or false end

	self._want = open and 1 or 0
	self:PointChevron()
	self:SetPolling(open and true or false)

	-- THE LIBRARY GOES WITH THE DRAWER. It hangs off the mini-player at the foot
	-- of the panel and slides away with it - but it hangs off the RIGHT of that,
	-- so a panel a full width off screen leaves the drawer it opened sitting
	-- just inside the edge with nothing behind it. Shut, rather than left
	-- floating over the world attached to something that is not there.
	--
	-- CloseFor, so the console's drawer at ten thousand feet is not shut by
	-- somebody closing the Toolbox on the ground.
	if not open and self.content and A.IFEC and A.IFEC.Library then
		A.IFEC.Library:CloseFor(self.content.now)
	end
	if open then
		-- Re-read EVERYTHING first, then draw. Opening the drawer is the moment
		-- somebody looks at these, and it costs six function calls.
		--
		-- The specific bug was Gold, and it is fixed above by giving it the
		-- login event the others had. This is the general version: any provider
		-- whose value was not available yet at login, or whose event we have
		-- not thought of, is correct by the time it is seen rather than correct
		-- only after the thing it measures happens to change.
		self:RefreshProviders()
		self:RefreshWidgets()
	end

	if instant or not self.panel then
		self._travel = self._want
		self._sliding = nil
		A:UnregisterTicker(self)
		self:Layout()
		return
	end

	if not self._sliding then
		self._sliding = true
		A:RegisterTicker(self, Slide)
	end
end

function TB:Toggle()
	self:SetOpen(not self:IsOpen())
end

function TB:SetDock(edge)
	edge = edge and edge:upper()
	if not EDGES[edge] then return false end
	local c = Char()
	if c then c.docked = edge end
	self:Layout()

	-- ...and the CONTENT, which is the whole of what changes.
	--
	-- This was missing, and it is the bug you see rather than the one you
	-- reason about: Layout moves and resizes the panel, LayoutRail moves the
	-- rail, and neither of them touches what is drawn inside. Re-docking from a
	-- side to the top therefore put a 1280x240 panel at the top of the screen
	-- with the tall panel's column of sections still laid out down the left of
	-- it, most of them below the panel's own bottom edge.
	--
	-- Nothing caught it because every test that looks at the flat layout calls
	-- Refresh* afterwards, and those call LayoutContent. The one path nobody
	-- had was the one the player uses: drag, let go, look.
	self:LayoutContent()
	self:LayoutRail()
	self:AnchorDockHandle()
	return true
end

-- ---------------------------------------------------------------------------
-- drag to re-dock
--
-- Four targets, not a position. Grab the rail while frames are unlocked, four
-- ghosts appear where the drawer could go, the one nearest the cursor lights
-- up, and letting go docks it there. That is the Windows-snap idiom rather than
-- the Movers one, and it is the honest shape for something with four legal
-- answers: dragging the drawer itself would imply it could be left in the
-- middle, which it cannot.
-- ---------------------------------------------------------------------------

--- Which edge a screen point is nearest, as a FRACTION of each axis rather than
--  in pixels.
--
--  Pixels are the obvious version and the wrong one: on a 2560x1440 screen the
--  centre is 1280 from either side and 720 from top or bottom, so a plain
--  distance says "top" for the entire middle third of the screen and the two
--  side docks are unreachable from anywhere near the middle. Fractions make
--  each edge own its own quarter, wedge-shaped, which is what the gesture looks
--  like it should do.
--
--  Ties resolve to whichever comes first in EDGE_ORDER, because a comparison
--  that has to be strict somewhere is better than one that is arbitrary.
-- W.NearestEdge, which the party dock handle uses too. It answers nil on a
-- screen with no size rather than guessing; this dock falls back to the one
-- it is already on, which is the answer that changes nothing.
function TB:NearestEdge(x, y, w, h)
	return W.NearestEdge(x, y, w, h) or self:Dock()
end

function TB:BuildGhosts()
	if self._ghosts then return self._ghosts end
	local ghosts = {}
	for _, edge in ipairs(EDGE_ORDER) do
		local g = Glass.CreatePanel(UIParent, { corner = PANEL_CORNER })
		g:SetFrameStrata("FULLSCREEN_DIALOG")
		-- Above the panel (10) and the rail (20) so a ghost on the edge the
		-- drawer is ALREADY on is still visible, and below the handle (70) so it
		-- never eats the drag.
		g:SetFrameLevel(30)
		g.tag = W.Text(g, "tbSection", "CENTER")
		g.tag:SetPoint("CENTER", g, "CENTER", 0, 0)
		g.tag:SetText(edge)
		g:Hide()
		ghosts[edge] = g
	end
	self._ghosts = ghosts
	return ghosts
end

--- Each ghost is the drawer's own footprint on that edge - the size the panel
--  WOULD be there, at the panel's scale. A uniform strip on each side would be
--  cheaper and would lie about the top and bottom docks, which are a different
--  shape entirely.
function TB:LayoutGhosts()
	local ghosts = self:BuildGhosts()
	local scale = A.db.profile.scale
	for _, edge in ipairs(EDGE_ORDER) do
		local g = ghosts[edge]
		local w, h = self:PanelSize(edge)
		g:SetScale(scale)
		g:SetSize(w, h)
		g:ClearAllPoints()
		g:SetPoint(edge, UIParent, edge, 0, 0)
		Glass.SetPanelCorner(g, PANEL_CORNER)
	end
end

--- The lit one is the one you would get. Everything else is a hint that it is
--  also available, which is the difference between four targets and one.
function TB:HighlightGhost(edge)
	local ghosts = self._ghosts
	if not ghosts then return end
	local c = Palette.c
	for _, e in ipairs(EDGE_ORDER) do
		local g = ghosts[e]
		local on = (e == edge)
		g:SetFillColor({ c.accent[1], c.accent[2], c.accent[3], on and 0.30 or 0.07 })
		g:SetEdgeColor({ c.accent[1], c.accent[2], c.accent[3], on and 0.95 or 0.28 })
		if g.tag then W.Color(g.tag, on and c.text or c.textFaint) end
	end
	self._litGhost = edge
end

function TB:ShowGhosts(show)
	if not show then
		if self._ghosts then
			for _, e in ipairs(EDGE_ORDER) do self._ghosts[e]:Hide() end
		end
		self._litGhost = nil
		return
	end
	local ghosts = self:BuildGhosts()
	self:LayoutGhosts()
	self:HighlightGhost(self:Dock())
	for _, e in ipairs(EDGE_ORDER) do ghosts[e]:Show() end
end

--- The handle sits ON the rail, because the rail is the part of the drawer that
--  is always on screen - there is no grabbing a panel that is currently a
--  screen's width off to the left.
--
--  FULLSCREEN_DIALOG at a level above the rail's, not DIALOG. DIALOG is BELOW
--  FULLSCREEN_DIALOG in the strata order, so a handle there would be painted
--  under the very frame it is meant to be a handle for and would never see a
--  click. That is the same mistake the chat resize grip made.
function TB:BuildDockHandle()
	if self._dockHandle or not self.rail then return self._dockHandle end

	local h = Glass.CreatePanel(UIParent, { corner = RAIL_CORNER, shadow = 8 })
	h:SetFrameStrata("FULLSCREEN_DIALOG")
	h:SetFrameLevel((self.rail:GetFrameLevel() or 20) + 50)
	h:SetAllPoints(self.rail)
	h:EnableMouse(true)
	h:RegisterForDrag("LeftButton")
	h:Hide()

	local c = Palette.c
	h:SetFillColor({ c.accent[1], c.accent[2], c.accent[3], 0.22 })
	h:SetEdgeColor({ c.accent[1], c.accent[2], c.accent[3], 0.85 })

	-- Beside the rail, never on it. The rail is RAIL_W wide - forty-odd pixels -
	-- and a label centred on it is a word laid across a strip narrower than
	-- itself. AnchorDockHandle puts it on whichever side has screen to spare.
	--
	-- A child of the handle even though it is anchored OUTSIDE it: a region may
	-- be positioned beyond its parent's bounds and still draws, and being a
	-- child is what makes it inherit the handle's strata - which is the only
	-- level above the drawer - and vanish with it.
	local label = W.Text(h, "tbSection", "CENTER")
	W.Color(label, c.text)
	label:SetText("TOOLBOX")
	h.label = label

	local function Stop(self2)
		self2:SetScript("OnUpdate", nil)
		self._dragging = nil
		self:ShowGhosts(false)

		local edge = self._dockTarget
		self._dockTarget = nil
		if edge and EDGES[edge] and edge ~= self:Dock() then
			self:SetDock(edge)
			A:Print("toolbox docked -> " .. A.Val(edge:lower()))
		end
		self:AnchorDockHandle()
	end

	local function Drag(self2)
		-- The fight can start, or the frames can be locked from the options
		-- panel, while the button is still down. Re-docking moves the rail, and
		-- the rail is the parent of other addons' launcher buttons - some of
		-- which carry secure templates - so finishing the gesture mid-combat is
		-- a protected action. Drop the drag rather than find out.
		--
		-- DISARMED first. Stop is the drop path and commits whatever is armed,
		-- so falling into it with a target still set does in combat exactly the
		-- thing this guard exists to prevent - and it would have looked fine in
		-- a test that turned combat on before the cursor had armed anything.
		if InCombatLockdown() or not (A.Movers and A.Movers.unlocked) then
			self._dockTarget = nil
			return Stop(self2)
		end

		local us = UIParent:GetEffectiveScale() or 1
		if us <= 0 then return end
		local mx, my = GetCursorPosition()
		local edge = self:NearestEdge(mx / us, my / us)
		if edge ~= self._litGhost then self:HighlightGhost(edge) end
		self._dockTarget = edge
	end

	h:SetScript("OnDragStart", function(self2)
		if InCombatLockdown() then
			A:Print(A.Bad("can't re-dock the toolbox in combat."))
			return
		end
		self._dragging = true
		self._dockTarget = self:Dock()
		self:ShowGhosts(true)
		self2:SetScript("OnUpdate", Drag)
	end)

	h:SetScript("OnDragStop", Stop)

	-- The label says WHAT, the tooltip says HOW. Every other handle on screen
	-- means "drag me anywhere"; this one means "drag me to one of four", and
	-- there is nothing about a purple slab that distinguishes the two.
	h:SetScript("OnEnter", function(self2)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
		GameTooltip:SetText("Toolbox")
		GameTooltip:AddLine("Drag to any screen edge. The drawer docks to one of"
			.. " four, and each edge has its own layout.", 0.8, 0.8, 0.85, true)
		GameTooltip:Show()
	end)
	h:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	self._dockHandle = h
	self:AnchorDockHandle()
	return h
end

--- Which side of the rail the label goes on, and it is always the side the
--  SCREEN is on. Docked left the rail is hard against the left edge, so a label
--  to its left is a label off the screen.
function TB:AnchorDockHandle()
	local h = self._dockHandle
	if not h or not h.label then return end
	local edge = self:Dock()
	h.label:ClearAllPoints()
	if edge == "LEFT" then
		h.label:SetPoint("LEFT", h, "RIGHT", 10, 0)
	elseif edge == "RIGHT" then
		h.label:SetPoint("RIGHT", h, "LEFT", -10, 0)
	elseif edge == "TOP" then
		h.label:SetPoint("TOP", h, "BOTTOM", 0, -10)
	else
		h.label:SetPoint("BOTTOM", h, "TOP", 0, 10)
	end
end

--- Driven from Movers, so the drawer's gesture appears and goes away with
--  everything else's rather than needing its own command to find.
function TB:ShowDockHandle(show)
	if show then
		self:BuildDockHandle()
	elseif self._dragging then
		-- Locked mid-drag. Nothing has been committed, so the ghosts go and the
		-- dock stays where it was.
		--
		-- The tracker has to go with it. A hidden frame gets no OnUpdate, so one
		-- left attached is not harmless - it is a script that fires the instant
		-- the handle is shown again, with a stale target still armed.
		self._dragging, self._dockTarget = nil, nil
		if self._dockHandle then self._dockHandle:SetScript("OnUpdate", nil) end
		self:ShowGhosts(false)
	end
	local h = self._dockHandle
	if not h then return end
	h:SetShown(show and true or false)
	if show then self:AnchorDockHandle() end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

--- Only the two that cannot be event-driven, and only while the drawer is on
--  screen. A closed drawer shows no numbers, so polling for them is work for
--  nobody - and latency is refreshed by the client about every 30s anyway, so
--  asking faster than that is a lie dressed as precision.
local POLL_EVERY = 1.0

local function PollTick(self, dt)
	self._pollAccum = (self._pollAccum or 0) + dt
	if self._pollAccum < POLL_EVERY then return end
	self._pollAccum = 0
	self:RefreshProviders("Latency")
	self:RefreshProviders("FPS")
	self:RefreshWidgets()
end

function TB:SetPolling(on)
	if on and not self._polling then
		self._polling = true
		-- Due IMMEDIATELY, not in a second's time. Latency and framerate are the
		-- two that cannot be event-driven, so a fresh accumulator means the
		-- first thing you see on opening the drawer is up to a second old - and
		-- on the very first open of a session it is whatever GetNetStats said
		-- before the client had pinged anything, which is nothing.
		self._pollAccum = POLL_EVERY
		A:RegisterTicker(self._pollToken, function(_, dt) PollTick(TB, dt) end)
	elseif not on and self._polling then
		self._polling = nil
		A:UnregisterTicker(self._pollToken)
	end
end

function TB:OnEnable()
	self._pollToken = self._pollToken or {}
	self:Build()
	self:BuildContent()
	self:PublishWidgets()

	-- The event-driven four. Each names the events that can change it, so a
	-- widget nobody is looking at still costs nothing between them.
	for _, prov in ipairs(self.PROVIDERS) do
		for _, ev in ipairs(prov.events or {}) do
			A:RegisterEvent(self, ev, function(_, event)
				if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
					TB:XPTick(event == "PLAYER_LEVEL_UP")
				end
				TB:RefreshProviders(prov.key)
				TB:RefreshWidgets()
			end)
		end
	end

	self:XPTick(false)
	self:RefreshProviders()

	-- Ours is a display too, so it listens the same way any other would. A third
	-- party writing to its own object updates our grid with no wiring at all.
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if ldb and ldb.RegisterCallback and not self._ldbHooked then
		self._ldbHooked = true
		-- The registering object first, not the library.
		pcall(ldb.RegisterCallback, self, "LibDataBroker_AttributeChanged",
			function() if TB:IsOpen() then TB:RefreshWidgets() end end)
	end

	self:SetOpen(self:IsOpen(), true)
	self:SetPolling(self:IsOpen())

	-- Discovery starts HERE now. It used to be kicked off by the minimap module
	-- on PLAYER_LOGIN, and when the drawer went so did the only caller - so the
	-- registry callbacks were never subscribed and the fifteen-second retry
	-- never ran. Every launcher that finished loading after us was invisible.
	A.Launchers:StartScanning({ [self.panel] = true, [self.rail] = true })

	self:ClaimPins()
	self:LayoutRail()

	-- UPDATE_PENDING_MAIL is the only event the client fires for this, and it
	-- covers both the flag and the sender list. MAIL_INBOX_UPDATE is registered
	-- too because reading your mail at a mailbox clears the flag without
	-- necessarily firing the first one, and an envelope still glowing purple
	-- after you have emptied the box is the version of this anybody would
	-- notice.
	for _, ev in ipairs({ "UPDATE_PENDING_MAIL", "MAIL_CLOSED",
		"PLAYER_ENTERING_WORLD" }) do
		A:RegisterEvent(self, ev, function() TB:RefreshMail() end)
	end

	-- MAIL_INBOX_UPDATE is the one moment the client will tell us everything:
	-- it fires when the inbox arrives at a mailbox, and that is the only place
	-- GetInboxHeaderInfo answers. Read and remembered there, so the section has
	-- something to say for the rest of the time - see TB:ReadInbox.
	A:RegisterEvent(self, "MAIL_INBOX_UPDATE", function() TB:ReadInbox() end)

	self:RefreshMail()

	-- The HUD breathes and this was the one thing that did not.
	--
	-- Every other module registers what it draws, and the Toolbox registered
	-- nothing at all - so the rail sat at full brightness against a dimmed
	-- interface, which is the one place a missing registration is visible.
	--
	-- The rail and the panel, NOT the scrim: the scrim's alpha is ours, written
	-- on every Layout from the slide position, and a second writer would fight
	-- it once per frame while the drawer moves. That is the rule the aura trays
	-- and the minimap mail pill already follow - one owner per alpha.
	A.Fader:Register(self.rail, {})
	A.Fader:Register(self.panel, {})

	-- The drawer's own placement gesture, on the same switch as everyone else's.
	-- Keyed by module name so a disable/enable cycle replaces the watcher rather
	-- than stacking a second one.
	if A.Movers then
		A.Movers:OnLockChanged("toolbox", function(unlocked)
			TB:ShowDockHandle(unlocked)
			-- ...and the SETTINGS TILE that reports the same fact.
			--
			-- "Unlock frames" is a mode tile: it has no stored value and reads
			-- A.Movers.unlocked live, which is right - but only when something
			-- asks. Nothing did. The tile was drawn when the drawer was built
			-- and then only when a widget changed, so unlocking from the
			-- options panel or `/aether lock`, or unlocking and locking again
			-- with the drawer shut, left it reporting whatever it had said
			-- last. Every other way of changing this already went through here.
			TB:RefreshTiles()
		end)
	end

	A.Launchers:OnChanged("toolbox", function()
		-- Re-claim on every change, not only at enable. A pin restored from
		-- saved variables names an addon whose button may not exist yet: the
		-- launcher sweep runs for fifteen seconds after login and LibDBIcon
		-- announces buttons as their addons finish loading. Claiming once at
		-- enable caught only whatever had already arrived, so a pinned addon
		-- that loaded a moment later stayed in the saved list and never
		-- appeared on the rail - which reads exactly like the pin not being
		-- saved at all.
		TB:ClaimPins()
		TB:RefreshAddons()
		TB:LayoutRail()
	end)
end

function TB:OnDisable()
	if A.Fader then
		-- Unregister puts the alpha back to 1. A module switched off mid-fade
		-- would otherwise leave its frames parked at whatever the fade had
		-- reached, and nothing left running to bring them up.
		if self.rail then A.Fader:Unregister(self.rail) end
		if self.panel then A.Fader:Unregister(self.panel) end
	end
	self:SetPolling(false)

	-- The handle and the ghosts belong to the drawer, so a disabled drawer must
	-- not leave a purple slab and four targets on screen for a frame that is no
	-- longer there. The watcher goes too, or locking later puts them back.
	if A.Movers and A.Movers.watchers then A.Movers.watchers.toolbox = nil end
	self:ShowDockHandle(false)
	self:ShowGhosts(false)

	if self.panel then
		self._want, self._travel = 0, 0
		self:Layout()
		self.panel:Hide()
		self.rail:Hide()
		self.scrim:Hide()
	end
	A:UnregisterTicker(self)
	self._sliding = nil
end

function TB:OnSkinChanged()
	self:ApplySkin()
end

function TB:OnConfigChanged()
	if not self.panel then return end
	self.panel:Show()
	self.rail:Show()
	self:Layout()
	-- The grids too. A column slider that writes a number nothing re-reads is
	-- the same silent no-op as a mistyped option path, and the options walker
	-- only proves the path RESOLVES.
	self:RefreshWidgets()
	self:RefreshTiles()
	self:RefreshAddons()
	self:RefreshMicro()
	self:RefreshNews()
	self:LayoutRail()
end

-- ---------------------------------------------------------------------------
-- the widgets, published rather than drawn
--
-- The handoff draws six fixed cards. They are registered as LDB `data source`
-- objects instead, and the grid renders whatever data sources the player has
-- chosen - ours first, because ours are the six that ship.
--
-- Three things fall out of that, and the third is the reason:
--   * somebody else can write a widget in ten lines and no knowledge of this
--     addon, which is the entire point of the protocol;
--   * the grid is a LIST rather than a layout, the same shape as the settings
--     tiles and the pinned addons;
--   * our numbers appear in Titan, Bazooka and ChocolateBar for free, because
--     publishing is publishing.
--
-- The card has a big value and a small label. LDB offers `text`, or `value` +
-- `suffix`, plus `label`. Ours write value+suffix+label, which is the shape the
-- deck draws. Third-party sources overwhelmingly use `text`, often with colour
-- escapes already in it - so the card RENDERS a text it is given and does not
-- try to parse it.
-- ---------------------------------------------------------------------------

local PREFIX = "AetherUI_"

--- Our six. `poll` marks the two that genuinely cannot be event-driven.
TB.PROVIDERS = {
	-- PLAYER_ENTERING_WORLD on every event-driven one, INCLUDING Gold.
	--
	-- Gold had only PLAYER_MONEY, which fires when your money CHANGES. At login
	-- GetMoney answers 0 before the client has been told otherwise, so the one
	-- read at enable wrote "0s" and nothing looked again until you earned or
	-- spent something. Bag space and durability were right on the same screen
	-- because they carry this event and Gold did not - which is exactly the
	-- kind of difference that reads as "sometimes it works".
	{ key = "Gold",       label = "Gold",
	  events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" } },
	{ key = "BagSpace",   label = "Bag space",  events = { "BAG_UPDATE", "PLAYER_ENTERING_WORLD" } },
	{ key = "Durability", label = "Durability", events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_ENTERING_WORLD" } },
	{ key = "XPHour",     label = "XP / hr",
	  events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" } },
	{ key = "Latency",    label = "Latency",    poll = true },
	{ key = "FPS",        label = "FPS",        poll = true },
}

local function Money()
	local m = GetMoney and GetMoney() or 0
	local g = math.floor(m / 10000)
	local s = math.floor((m % 10000) / 100)
	if g > 0 then return g .. "g " .. s .. "s" end
	return s .. "s"
end

local function BagSpace()
	if not C_Container or not C_Container.GetContainerNumFreeSlots then return nil end
	local free, total = 0, 0
	for bag = 0, 4 do
		local f = select(1, C_Container.GetContainerNumFreeSlots(bag))
		local n = C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)
		free  = free + (tonumber(f) or 0)
		total = total + (tonumber(n) or 0)
	end
	if total == 0 then return nil end
	return (total - free) .. " / " .. total
end

--- The WORST slot, not the mean. A mean says "94%" while the one item that is
--  about to break says 3, and the number exists to tell you to go to a vendor.
local function Durability()
	if not GetInventoryItemDurability then return nil end
	local worst
	for slot = 1, 19 do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then
			local pct = cur / max
			if not worst or pct < worst then worst = pct end
		end
	end
	if not worst then return nil end
	return math.floor(worst * 100 + 0.5) .. "%"
end

-- XP/hr has no API. Session-tracked, and three ways to be confidently wrong.
TB._xp = { gained = 0, from = nil, last = nil }

--- A LEVEL-UP resets the numerator, not the session. UnitXP drops to near zero
--  and UnitXPMax changes, so the delta across the boundary is
--  (max - before) + after rather than after - before. Getting this wrong loses
--  a whole level's XP from the rate every time somebody dings.
function TB:XPTick(levelled)
	local now  = UnitXP and UnitXP("player") or 0
	local last = self._xp.last
	if last then
		if levelled or now < last then
			local max = self._xp.lastMax or last
			self._xp.gained = self._xp.gained + math.max(0, max - last) + now
		else
			self._xp.gained = self._xp.gained + (now - last)
		end
	end
	self._xp.last    = now
	self._xp.lastMax = UnitXPMax and UnitXPMax("player") or nil
	if not self._xp.from then self._xp.from = GetTime and GetTime() or 0 end
end

--- Under a minute of session there is no rate, only a two-second window with a
--  big number extrapolated out of it. The aura tiles refuse to print a timer
--  they do not have; this refuses for the same reason.
local XP_MIN_SESSION = 60

function TB:XPRate()
	local from = self._xp.from
	if not from or not GetTime then return nil end
	local elapsed = GetTime() - from
	if elapsed < XP_MIN_SESSION then return nil end
	local perHour = self._xp.gained / elapsed * 3600
	if perHour >= 1000 then
		return string.format("%.1fk", perHour / 1000)
	end
	return tostring(math.floor(perHour + 0.5))
end

local function Latency()
	if not GetNetStats then return nil end
	local _, _, home, world = GetNetStats()
	local ms = math.max(tonumber(home) or 0, tonumber(world) or 0)
	if ms <= 0 then return nil end
	return math.floor(ms) .. " ms"
end

local function Framerate()
	if not GetFramerate then return nil end
	return tostring(math.floor(GetFramerate() + 0.5))
end

TB.VALUES = {
	Gold       = Money,
	BagSpace   = BagSpace,
	Durability = Durability,
	XPHour     = function() return TB:XPRate() end,
	Latency    = Latency,
	FPS        = Framerate,
}

--- Register the six. Names are prefixed and permanent for the session: once
--  published, the name is a contract with whoever is displaying it.
function TB:PublishWidgets()
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if not ldb or self._published then return end
	self._published = {}

	for _, p in ipairs(self.PROVIDERS) do
		local name = PREFIX .. p.key
		local obj  = ldb:GetDataObjectByName(name)
		if not obj then
			obj = ldb:NewDataObject(name, {
				type   = "data source",
				label  = p.label,
				text   = "—",
				value  = "—",
			})
		end
		self._published[p.key] = obj
	end

	self:RefreshProviders()
end

--- Recompute ours and write them back onto the objects. Writing an attribute
--  fires the library's callback, which is what a display - including our own
--  grid - listens to, so there is no separate "tell the grid" step.
function TB:RefreshProviders(only)
	if not self._published then return end
	for _, p in ipairs(self.PROVIDERS) do
		if not only or only == p.key then
			local obj = self._published[p.key]
			local fn  = self.VALUES[p.key]
			if obj and fn then
				local ok, v = pcall(fn)
				local text = (ok and v) or "—"
				-- Only write on a CHANGE. The library fires a callback per
				-- assignment and the grid redraws on it; rewriting the same
				-- string ten times a second is work nobody can see.
				if obj.value ~= text then
					obj.value = text
					obj.text  = text
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- reading a data source onto a card
--
-- The card has a big value and a small label. LDB gives `text`, or
-- `value` + `suffix`, plus `label`. Ours write the first shape because that is
-- what the deck draws; third-party sources overwhelmingly write the second,
-- often with colour escapes already baked into `text`.
--
-- So: RENDER what is given, do not interpret it. A source handing us
-- "|cff00ff0042|r" gets that drawn, colour and all, and nothing here tries to
-- pull the number back out of it.
-- ---------------------------------------------------------------------------

local EMDASH = "\226\128\148"

function TB:CardText(name, obj)
	if not obj then return EMDASH, name end

	local big
	if obj.value ~= nil and obj.value ~= "" then
		big = tostring(obj.value) .. (obj.suffix and tostring(obj.suffix) or "")
	elseif obj.text ~= nil and obj.text ~= "" then
		big = tostring(obj.text)
	else
		big = EMDASH
	end

	-- The label, or failing that the registered name - which is at least a true
	-- statement about where the number came from.
	local small = obj.label
	if small == nil or small == "" then small = name end

	return big, tostring(small)
end

--- Which data sources the grid shows. Ours by default; a LIST rather than a
--  layout, so a third party's can be added and the order is the player's.
function TB:WidgetList()
	local c = Char()
	if c and type(c.widgets) == "table" and #c.widgets > 0 then return c.widgets end
	local out = {}
	for _, p in ipairs(self.PROVIDERS) do out[#out + 1] = PREFIX .. p.key end
	return out
end

-- ---------------------------------------------------------------------------
-- content
-- ---------------------------------------------------------------------------

local CARD_H, CARD_GAP = 46, 8
local PAD = 22

--- The deck letter-spaces its section headings. The client has no
--  letter-spacing, so the spacing is baked into the string - which is why these
--  read oddly in source and correctly on screen.
local function Spaced(s)
	return (s:gsub("(.)", "%1 "):gsub(" $", ""))
end

-- ---------------------------------------------------------------------------
-- mail
--
-- WHAT THE CLIENT WILL TELL US, which is very little and worth writing down so
-- nobody goes looking for the rest of it:
--
--   HasNewMail()            -> boolean. That is the whole of it.
--   GetLatestThreeSenders() -> up to three sender NAMES. No subject, no item,
--                              no timestamp, no count. Capped at three by the
--                              client, not by us.
--   UPDATE_PENDING_MAIL     -> fires when either of the above changes.
--
-- There is no unread COUNT away from a mailbox. GetInboxNumItems only answers
-- once the inbox has been read at a real mailbox and goes stale the moment you
-- walk away, so a number taken from it is a number from the last time you
-- checked rather than a number about now. Blizzard's own strings settle the
-- question: HAVE_MAIL is "You have new mail." and HAVE_MAIL_FROM is "You have
-- new mail from:" - neither carries a figure, because the client does not have
-- one to put there.
--
-- So the chip counts SENDERS, and says "3+" at three, because three is the
-- client's cap and not necessarily the total. Two is exactly two; three might
-- be nine.
--
-- GetLatestThreeSenders can also come back empty while HasNewMail is true -
-- mail from an auction house or an NPC arrives without a name attached. "You
-- have mail" with no list is a real state, not a bug, and both the tooltip and
-- the section have to say something sensible in it.
-- ---------------------------------------------------------------------------

TB.MAIL_ROWS = 3

--- Read the inbox while we are standing at one, and remember what it said.
--
--  This is the ONLY way to learn anything real. GetLatestThreeSenders knows
--  about mail that arrived while you were logged in and nothing else, so mail
--  sitting in the box from before login has no names attached at all - which is
--  why the section could show "you have mail" and nothing under it, and why it
--  looked intermittent rather than broken.
--
--  At a mailbox the client will finally say everything: GetInboxHeaderInfo
--  gives a sender, a subject and wasRead per item, so there is a true unread
--  COUNT here and nowhere else. Remembered per character, because that is what
--  it is about.
--
--  Written down as "what the box held when you last looked", never as "what is
--  in the box". Those are different claims and the section says which one it is
--  making.
function TB:ReadInbox()
	-- Refresh WHATEVER happens below, including every early return. This is the
	-- handler for MAIL_INBOX_UPDATE, and that event also fires when the box is
	-- emptied - so a client missing these calls, or a character with no saved
	-- table, must still end up with the right envelope on the rail rather than
	-- one still glowing after the mail has been read.
	local function done() TB:RefreshMail() end

	if not GetInboxNumItems or not GetInboxHeaderInfo then return done() end
	local c = Char()
	if not c then return done() end

	local okN, n = pcall(GetInboxNumItems)
	if not okN or not n then return done() end

	local seen, senders, unread = {}, {}, 0
	for i = 1, n do
		-- Nine returns deep for wasRead, and it is the one that matters: an
		-- inbox is not a list of unread mail, it is a list of mail.
		local ok, _, _, sender, _, _, _, _, _, wasRead = pcall(GetInboxHeaderInfo, i)
		if ok and not wasRead then
			unread = unread + 1
			local who = (type(sender) == "string" and sender ~= "") and sender
				or (_G.UNKNOWN or "Unknown")
			if not seen[who] then
				seen[who] = true
				senders[#senders + 1] = who
			end
		end
	end

	if unread == 0 then
		-- Standing at an empty box is knowledge too, and the most reliable kind:
		-- it clears a cache that would otherwise outlive the mail it describes.
		c.mail = nil
	else
		c.mail = { senders = senders, unread = unread,
		           at = (_G.time and _G.time()) or 0 }
	end
	done()
end

--- What this character last saw in its mailbox, or nil.
--
--  Its own accessor because it is saved-variable state: the thing that reads it
--  and the thing that clears it should not each know the shape independently.
function TB:MailRecord()
	local c = Char()
	return c and c.mail or nil
end

--- `has`, the senders, a true unread count if we have one, and whether that
--  came from memory rather than from the client.
--
--  Read at call time, never cached in the module: the live senders change under
--  us on UPDATE_PENDING_MAIL and a stale list is worse than no list. The
--  per-character record is a different thing - it is deliberately old, and it
--  says so.
function TB:MailState()
	local has = HasNewMail and HasNewMail() and true or false
	if not has then return false, {}, nil, false end

	local senders = {}
	if GetLatestThreeSenders then
		-- pcall because this is one of the few calls that can be answered by a
		-- client that has not finished logging in yet.
		local ok, a, b, c = pcall(GetLatestThreeSenders)
		if ok then
			for _, s in ipairs({ a, b, c }) do
				if type(s) == "string" and s ~= "" then senders[#senders + 1] = s end
			end
		end
	end
	-- The client's own answer wins when it has one: it is about now, and the
	-- record is about the last time anybody looked.
	if #senders > 0 then return true, senders, nil, false end

	local c = Char()
	local rec = c and c.mail
	if rec and rec.senders and #rec.senders > 0 then
		local out = {}
		for i, who in ipairs(rec.senders) do out[i] = who end
		return true, out, rec.unread, true
	end

	return true, {}, nil, false
end

--- The count for the chip, or nil when there is nothing honest to show.
function TB:MailCount()
	local has, senders, unread = self:MailState()
	if not has then return nil end
	if unread then return unread, false end
	if #senders == 0 then return nil end
	return #senders, #senders >= self.MAIL_ROWS
end

--- Empty envelope or full one, and the full one in the accent.
function TB:RefreshMail()
	if not self.rail or not self.rail.mail then return end
	local has = self:MailState()
	Media:SetIcon(self.rail.mail.glyph, has and "mailfull" or "mail")

	local c = Palette.c
	if has then
		local a = c.accent or c.text
		self.rail.mail.glyph:SetVertexColor(a[1], a[2], a[3], 1)
	else
		-- Dimmer than the gear beside it. An empty postbox is not a control you
		-- are being asked to look at.
		self.rail.mail.glyph:SetVertexColor(c.text[1], c.text[2], c.text[3], 0.45)
	end

	-- Relaid out, not just refreshed. The section appears and disappears with
	-- the mail, so everything under it - the settings tiles - moves, and a
	-- refresh that only rewrote the rows would leave them overlapping.
	if self.content then
		self:RefreshMailRows()
		self:LayoutContent()
	end
end

function TB:MailTooltip(owner)
	if not GameTooltip then return end
	local has, senders = self:MailState()
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if not has then
		GameTooltip:SetText(_G.NO_MAIL or "No new mail")
	elseif #senders == 0 then
		-- The client's own wording for "mail, but we cannot say who from".
		GameTooltip:SetText(_G.HAVE_MAIL or "You have new mail.")
	else
		GameTooltip:SetText(_G.HAVE_MAIL_FROM or "You have new mail from:")
		for _, s in ipairs(senders) do
			GameTooltip:AddLine(s, 1, 1, 1)
		end
		if #senders >= self.MAIL_ROWS then
			GameTooltip:AddLine("and possibly more - the client only names three",
				0.6, 0.6, 0.6)
		end
	end
	GameTooltip:Show()
end

-- What's new: read from Core/Changelog.lua rather than written here.
--
-- These were two literals in this file, and the pair had to be edited together
-- every release: the paragraph, and the version it was marked read against.
-- Nothing checked that either one had been touched, so the failure mode was a
-- drawer confidently showing the previous release's news with no dot on it.
--
-- The changelog is the one place now, the .toc is the version, and the harness
-- refuses a build where the two disagree.

--- How many lines of the entry fit on the card.
--
--  ONE. It was two, and two changelog lines joined into a paragraph wrapped to
--  three rendered lines, which filled the card to its bottom edge and drew
--  straight through the Notes link sitting there. A card is a headline, not a
--  release summary; the rest is what Notes is for.
TB.NEWS_LINES = 1

-- Where the type on the card starts, and where it stops. The tile is 38 wide at
-- 14 in from the edge with 12 of gap after it; everything else on the card -
-- the title, the body, the Notes link - lines up past that.
local NEWS_TEXT_X   = 14 + 38 + 12
local NEWS_TEXT_PAD = 14        -- and the gap at the right-hand end

--- Fit the body to the card: give it a width, then trim it to the height.
--
--  Called from both layouts once the card has been sized, because the card is
--  what changes between them - the tall panel gives the body about 300px to
--  wrap in and the flat one's identity column about 170, which is the same
--  sentence at two and at four lines.
--
--  Trimmed rather than trusted to be short. A changelog line is prose somebody
--  writes months from now, and the failure when it is too long is not a clipped
--  word: the body grows downward, the Notes link is anchored to the card's
--  bottom, and they are drawn through each other. Trimming is the only version
--  of this that cannot go wrong later.
--
--  Word at a time from the end, with "..." to say so. Not the unicode ellipsis:
--  Outfit is a text face and probably has one, but "probably" is how the gear
--  ended up rendering as three bytes of its own UTF-8, and three dots cost
--  nothing.
function TB:SizeNewsBody()
	local card = self.content and self.content.news
	if not card or not card.body then return end

	card.body:SetWidth(math.max(20,
		(card:GetWidth() or 0) - NEWS_TEXT_X - NEWS_TEXT_PAD))

	local avail = (card:GetHeight() or NEWS_H)
		- 14                                                -- top padding
		- (card.titleText:GetStringHeight() or 0)
		- 6                                                 -- title to body
		- 4                                                 -- body to link
		- ((card.notes and card.notes:GetHeight()) or 0)
		- 12                                                -- bottom padding
	if avail <= 0 then card.body:SetText("") return end

	local full = self:NewsText()
	card.body:SetText(full)
	if (card.body:GetStringHeight() or 0) <= avail then return end

	-- Guarded by a counter as well as by the text running out. This loop shrinks
	-- a string every pass so it does terminate, but a mock or a client that
	-- reports a constant height would spin it forever, and a frozen client is a
	-- worse bug than a long line.
	local text = full
	for _ = 1, 64 do
		local shorter = text:gsub("%s*%S+$", "")
		if shorter == "" or shorter == text then break end
		text = shorter
		card.body:SetText(text .. "...")
		if (card.body:GetStringHeight() or 0) <= avail then return end
	end
	-- Nothing fit. One line beats an overlap.
	card.body:SetText("...")
end

--- The version the card is currently reporting on.
function TB:NewsVersion()
	local entry = A.Notes and A:Notes()
	return (entry and entry.version) or A.version or "0.0.0"
end

--- The card's body: the first couple of lines of the current entry, joined.
function TB:NewsText()
	local entry = A.Notes and A:Notes()
	if not entry or not entry.lines or #entry.lines == 0 then
		return "No notes for this build."
	end
	local out = {}
	for i = 1, math.min(#entry.lines, self.NEWS_LINES) do out[i] = entry.lines[i] end
	return table.concat(out, " ")
end

--- Whether there is more than the card is showing, which is what decides
--  whether the Notes link is worth offering.
function TB:NewsHasMore()
	local entry = A.Notes and A:Notes()
	if not entry or not entry.lines then return false end
	if #entry.lines > self.NEWS_LINES then return true end
	return #(A.CHANGELOG or {}) > 1
end

function TB:NewsUnread()
	local c = Char()
	return not (c and c.newsSeen == self:NewsVersion())
end

function TB:MarkNewsRead()
	local c = Char()
	if c then c.newsSeen = self:NewsVersion() end
	if self.content and self.content.news then
		self.content.news.dot:SetShown(self:NewsUnread())
	end
end

--- Refresh the card from the changelog. Called on build and on config change,
--  so a reload after a bump redraws rather than keeping the text it was built
--  with.
function TB:RefreshNews()
	local card = self.content and self.content.news
	if not card then return end
	-- The body's TEXT is set by SizeNewsBody, not here: it has to be trimmed to
	-- whatever the card is at the moment, and only the layout knows that. Two
	-- writers on one string means the untrimmed one wins whenever it runs last.
	self:SizeNewsBody()
	card.dot:SetShown(self:NewsUnread())
	if card.notes then card.notes:SetShown(self:NewsHasMore()) end

	-- The chip carries the running version, and it is re-measured rather than
	-- left at whatever width it was built with: 0.2.0 is wider than 0.1.0 the
	-- moment a number goes double-digit, and a pill sized once is a pill with
	-- its own text hanging out of it.
	local chip = self.content.chip
	if chip and chip.text then
		chip.text:SetText("Aether UI " .. (A.version or "?"))
		chip:SetWidth((chip.text:GetStringWidth() or 40) + 14)
	end
end

function TB:BuildContent()
	if self.content then return end
	local panel = self.panel
	if not panel then return end

	local content = CreateFrame("Frame", nil, panel)
	self.content = content

	local title = W.Text(content, "tbTitle", "LEFT")
	title:SetText("Toolbox")
	content.title = title

	-- The version pill: DARK TEXT ON THE ACCENT, which is the one place the
	-- deck asks for a filled chip rather than a glass one. `btnFill` and
	-- `btnFillText` exist as their own tokens for exactly this - `accent` at
	-- full alpha is not the same colour, and text at `text` on top of it is
	-- unreadable.
	-- Small, and beside the title rather than competing with it. The first cut
	-- was an 18-tall lozenge carrying "Aether UI 0.1.0" at 11pt, which next to
	-- an 18pt "Toolbox" is two headings - and the version is the least
	-- interesting thing on the panel. Just the number, at 10, in a pill only as
	-- tall as the text needs.
	local chip = Glass.CreatePill(content, {})
	chip:SetHeight(15)
	chip:ApplySkin("btnFill", "btnFill")
	local chipText = W.Text(chip, "tbChip", "CENTER", nil, 10)
	chipText:SetPoint("CENTER", chip, "CENTER", 0, 0)
	chipText:SetText("Aether UI " .. (A.version or "0.1.0"))
	W.Color(chipText, Palette.c.btnFillText)
	chipText:SetShadowColor(0, 0, 0, 0)
	chip:SetWidth((chipText:GetStringWidth() or 40) + 14)
	chip.text = chipText
	content.chip = chip

	local close = CreateFrame("Button", nil, content)
	close:SetSize(18, 18)
	local x = W.Text(close, "tbCardTitle", "CENTER")
	x:SetPoint("CENTER", close, "CENTER", 0, 0)
	x:SetText("\195\151")
	close.glyph = x
	close:SetScript("OnClick", function() TB:SetOpen(false) end)
	content.close = close

	local card = Glass.CreatePanel(content, { corner = 18 })
	card:SetHeight(84)
	local tile = Glass.CreatePanel(card, { corner = 11 })
	tile:SetSize(38, 38)
	tile:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -14)
	tile:ApplySkin("btnFill", "cardEdgeHi")
	local spark = tile:CreateTexture(nil, "OVERLAY")
	spark:SetPoint("CENTER", tile, "CENTER", 0, 0)
	spark:SetSize(20, 20)
	if Media:SetIcon(spark, "whatsnew") then
		W.Tint(spark, Palette.c.btnFillText)
	end
	tile.spark = spark
	card.tile = tile

	local ct = W.Text(card, "tbCardTitle", "LEFT")
	ct:SetPoint("TOPLEFT", tile, "TOPRIGHT", 12, -2)
	ct:SetText("What's new")
	card.titleText = ct

	-- The unread dot needs a notion of READ, or it is either always lit or never
	-- - so the last version whose notes were seen is persisted and the dot is
	-- the comparison against the running one.
	local dot = card:CreateTexture(nil, "OVERLAY")
	dot:SetSize(7, 7)
	dot:SetPoint("LEFT", ct, "RIGHT", 6, 0)
	dot:SetTexture(Media.texture.circleMask or Media.texture.ring)
	card.dot = dot

	local body = W.Text(card, "tbCardBody", "LEFT")
	body:SetPoint("TOPLEFT", ct, "BOTTOMLEFT", 0, -6)
	-- One anchor and an explicit WIDTH, rather than being stretched between a
	-- left and a right anchor. A stretched FontString has a width the client
	-- knows and nothing else does - GetStringHeight, which is the only way to
	-- ask how many lines this is going to be, needs a width that was SET. The
	-- card cannot be checked for overflow without that number.
	body:SetJustifyV("TOP")
	card.body = body

	-- Notes: the way to the rest of it. The card is a fixed 84px and shows the
	-- first couple of lines of the current entry; everything else, and every
	-- release before this one, is behind here.
	--
	-- A button rather than a hyperlink in the body text. SetHyperlinksEnabled on
	-- a plain FontString needs a link type the client knows, and inventing one
	-- means hooking the global hyperlink handler to catch it - a lot of surface
	-- for a word that opens a panel we already have.
	local notes = CreateFrame("Button", nil, card)
	notes:SetSize(46, 16)
	-- Lined up with the title and the body, all three of which start just past
	-- the tile: 14 of padding, a 38 tile, 12 of gap.
	notes:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", NEWS_TEXT_X, 12)
	local nt = W.Text(notes, "tbLabel", "LEFT")
	nt:SetPoint("LEFT", notes, "LEFT", 0, 0)
	nt:SetText("Notes")
	W.Color(nt, Palette.c.accent)
	notes.text = nt
	-- An underline, because "Notes" in the accent beside body text at the same
	-- size reads as an emphasised word rather than as somewhere to click.
	local rule = notes:CreateTexture(nil, "OVERLAY")
	rule:SetTexture(Media.texture.flat)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", nt, "BOTTOMLEFT", 0, -1)
	rule:SetPoint("TOPRIGHT", nt, "BOTTOMRIGHT", 0, -1)
	do
		local c = Palette.c.accent
		rule:SetVertexColor(c[1], c[2], c[3], 0.55)
	end
	notes.rule = rule
	notes:SetScript("OnClick", function()
		TB:MarkNewsRead()
		if A.Options and A.Options.Open then A.Options:Open("changelog") end
	end)
	card.notes = notes

	card:EnableMouse(true)
	card:SetScript("OnMouseUp", function() TB:MarkNewsRead() end)
	content.news = card

	local head = W.Text(content, "tbSection", "LEFT")
	head:SetText(Spaced("WIDGETS"))
	content.widgetsHead = head

	content.cards = {}
	self:BuildNowPlaying()
	self:RefreshWidgets()
	self:BuildMail()
	self:BuildTiles()
	self:BuildAddons()
	self:BuildMicro()
	-- Last, because it writes into the card AND re-measures the version chip,
	-- and both want the whole header to exist first.
	self:RefreshNews()
end

--- Is there a mini-player to draw?
--
--  Content decides, which is the same question the in-flight console asks: with
--  nothing installed the section is ABSENT rather than empty, and the drawer
--  lays out as though it were never there.
--
--  Nothing here needs the IFEC to exist. That half of the addon can be missing,
--  broken or switched off and the Toolbox lays out exactly as it did before it
--  was written.
function TB:HasPlayer()
	local M = A.IFEC and A.IFEC.Mini
	return (M ~= nil and M:HasContent()) and true or false
end

--- How tall the mini-player wants to be. ASKED FOR rather than repeated here:
--  the two numbers disagreeing is a section with a gap under it, or one drawn
--  through the panel's floor.
local function NowHeight()
	local M = A.IFEC and A.IFEC.Mini
	return M and M.HEIGHT or 0
end

--- NOW PLAYING: the mini-player, at the foot of the drawer.
--
--  The region belongs to the IFEC and this only finds it a home - the same
--  boundary the in-flight console draws around its own content half, pointing
--  the same way: the Toolbox calls the player, and the player has never heard
--  of the Toolbox.
function TB:BuildNowPlaying()
	if not self.content or self.content.now then return end
	local M = A.IFEC and A.IFEC.Mini
	if not M then return end

	local head = W.Text(self.content, "tbSection", "LEFT")
	head:SetText(Spaced("NOW PLAYING"))
	self.content.nowHead = head
	self.content.now = M:Build(self.content)
end

--- The rail's transport chip, in whichever state it is in.
function TB:RefreshPlayer()
	local play = self.rail and self.rail.play
	if not play then return end

	local M = A.IFEC and A.IFEC.Mini
	play:SetShown(self:HasPlayer())
	if not M or not play:IsShown() then return end

	-- WHERE THE MENU OPENS is ours, because only we know which edge the rail is
	-- docked to. It goes AWAY from that edge: hung downwards on a rail docked at
	-- the bottom it ran off the screen, and the chip sits at the far end of the
	-- rail where there is least room in that direction.
	local edge = self:Dock()
	if edge == "LEFT" then
		M.railMenuOpts = { point = "BOTTOMLEFT", relPoint = "BOTTOMRIGHT", x = 6, y = 0 }
	elseif edge == "RIGHT" then
		M.railMenuOpts = { point = "BOTTOMRIGHT", relPoint = "BOTTOMLEFT", x = -6, y = 0 }
	elseif edge == "TOP" then
		M.railMenuOpts = { point = "TOPRIGHT", relPoint = "BOTTOMRIGHT", x = 0, y = -4 }
	else
		M.railMenuOpts = { point = "BOTTOMRIGHT", relPoint = "TOPRIGHT", x = 0, y = 4 }
	end

	-- AND WHICH WAY THE LIBRARY OPENS, for the same reason: only we know which
	-- edge we are docked to. Away from the drawer's own body - out to the side
	-- of a column, and DOWN from a strip across the top, where beside it is the
	-- middle of the strip and the list opened over the settings tiles.
	if M.frame then
		local away = {
			LEFT = "RIGHT", RIGHT = "LEFT", TOP = "BELOW", BOTTOM = "ABOVE",
		}
		M.frame.__aetherLibraryFrom = away[edge]
	end

	M:AdoptRailChip(play)
	M:PaintRailChip(play)
end

--- One card per chosen data source. Frames are POOLED by index, because WoW has
--  no way to destroy one and a list that shrinks must not leak a second set.
function TB:RefreshWidgets()
	if not self.content then return end
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	local list = self:WidgetList()

	for i, name in ipairs(list) do
		local card = self.content.cards[i]
		if not card then
			card = Glass.CreatePanel(self.content, { corner = 14 })
			card:SetHeight(CARD_H)
			card.value = W.Text(card, "tbValue", "LEFT")
			card.value:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -9)
			card.label = W.Text(card, "tbLabel", "LEFT")
			card.label:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 9)
			W.Color(card.label, Palette.c.textDim)
			self.content.cards[i] = card
		end

		local obj = ldb and ldb:GetDataObjectByName(name)
		local big, small = self:CardText(name, obj)
		card.value:SetText(big)
		card.label:SetText(small)
		card.__source = name
		card:Show()
	end

	-- Surplus cards are hidden, not destroyed. These are OURS, so hiding is free
	-- - the rule about never hiding a collected button does not reach them.
	for i = #list + 1, #self.content.cards do
		self.content.cards[i]:Hide()
	end

	self:LayoutContent()
end


-- ---------------------------------------------------------------------------
-- UI settings - a list of tiles, not a layout of six
--
-- The handoff names six settings and draws six tiles. Four of the six are not
-- the same KIND of thing, which is the finding: two are config paths, one is a
-- client CVar, one is not a setting at all, and one is deferred.
--
--   setting   a path into the profile, written exactly the way the options
--             panel writes it - including the `modules.<name>.enabled` rule,
--             or a module could be switched off in here and carry on running
--   cvar      a client setting; ours to write, NOT ours to keep (see below)
--   launcher  an addon, from Core/Launchers.lua. Not a toggle at all
--
-- "Daylight skin" is deliberately absent: the skin pass is deferred, so the
-- tile is not built rather than built and hidden.
--
-- A LAUNCHER TILE HAS NO STATE TO SHOW. LDB launchers are buttons, not
-- toggles - there is no attribute that answers "are you on", and a `data
-- source` can carry text but a launcher cannot. So launcher tiles draw their
-- icon and name with no On/Off chip, and the chip stays reserved for entries
-- that genuinely have two states. Drawing a fake one would be the chat badge
-- mistake in different clothes: a control that says something it cannot know.
-- ---------------------------------------------------------------------------

-- The four the deck asks for, and they are three different KINDS of thing:
--
--   setting   a path into the profile, written exactly the way the options
--             panel writes it - including the `modules.<name>.enabled` rule,
--             or a module could be switched off in here and carry on running
--   mode      a RUNTIME state with nothing saved behind it. Unlocked frames
--             and keybind mode are both like this: they are off at every
--             login by definition, they are read off the module that owns
--             them, and there is no default to configure because there is no
--             stored value to default.
--   launcher  an addon, from Core/Launchers.lua. Not a toggle at all
--
-- `cvar` was a fourth and is gone with the damage-numbers tile it existed for.
-- The mechanism is worth remembering rather than the tile: a client setting is
-- ours to write and NOT ours to keep, so it was never restored on disable -
-- unlike zen, which borrows CVars and gives them back because zen is temporary
-- and the player never asked for it.
--
-- Every tile carries a `tip`. A two-word label on a chip is a reminder for
-- somebody who already knows what it does; the tooltip is for everybody else,
-- and two of these four do something drastic enough to the screen that finding
-- out by pressing it is not reasonable.
--
-- A LAUNCHER TILE HAS NO STATE TO SHOW. LDB launchers are buttons, not
-- toggles - there is no attribute that answers "are you on", and a `data
-- source` can carry text but a launcher cannot. So launcher tiles draw their
-- icon and name with no On/Off chip, and the chip stays reserved for entries
-- that genuinely have two states. Drawing a fake one would be the chat badge
-- mistake in different clothes: a control that says something it cannot know.

TB.TILES = {
	{ kind = "setting", key = "zen", label = "Zen",
	  path = { "modules", "zen", "enabled" },
	  tip = "Fades the interface away when you stand still, and brings it"
	     .. " straight back the moment anything happens. Your character sits"
	     .. " down and the camera pulls back for the view." },

	-- The in-flight player, NOT the flight timer. Combat collapse had this slot
	-- and has gone to the options panel, where it already lived: four tiles is
	-- what the deck draws and the one thing that had no home anywhere else was
	-- this. A player who never wants a programme on a griffin still wants to
	-- know when the griffin lands.
	{ kind = "setting", key = "ifec", label = "I.F.E.C.",
	  path = { "modules", "ifec", "player" },
	  tip = "Plays the season's music and stories while you are a passenger."
	     .. " The flight timer, the route and the countdown are not this and"
	     .. " stay either way." },

	-- Both of the below are MODES. They are read from the module that owns the
	-- state rather than from the profile, because that is where the truth is:
	-- /aether lock, the options panel and this tile all move the same flag, and
	-- a copy of it in the profile would be a second answer that goes stale the
	-- first time somebody uses the slash command.
	{ kind = "mode", key = "lock", label = "Unlock frames",
	  get = function() return A.Movers and A.Movers.unlocked or false end,
	  set = function(want)
		if not A.Movers then return false end
		if want then A.Movers:Unlock() else A.Movers:Lock() end
		return true
	  end,
	  tip = "Drag any part of the interface to move it, or scroll to nudge it a"
	     .. " pixel at a time - hold shift to nudge sideways. Locked again from"
	     .. " here or with /aether lock." },

	{ kind = "mode", key = "keybinds", label = "Keybind mode",
	  get = function()
		local AB = A:GetModule("actionbars")
		return (AB and AB.enabled and AB.bindMode) and true or false
	  end,
	  set = function(want)
		local AB = A:GetModule("actionbars")
		if not AB or not AB.enabled then return false end
		AB:SetBindMode(want)
		return true
	  end,
	  tip = "Hover an action button and press a key to bind it. Keys go into"
	     .. " Blizzard's own binding set, so they survive this addon being"
	     .. " disabled and show up in the keybinding panel." },
}

local function Resolve(path)
	if not path or #path == 0 then return nil end
	local t = A.db.profile
	for i = 1, #path - 1 do
		t = t and t[path[i]]
	end
	return t, path[#path]
end

--- true, false, or nil for "this has no state" - which is a launcher.
function TB:TileState(tile)
	if not tile then return nil end

	if tile.kind == "setting" then
		local t, k = Resolve(tile.path)
		if not t then return false end
		-- Several of ours default to nil-meaning-true, the same convention the
		-- options panel's `defaultTrue` covers.
		return t[k] ~= false
	end

	-- Asked of the module that owns it, every time. A mode has no stored value
	-- to read and three different ways to be changed - this tile, the options
	-- panel and a slash command - so anything cached here is a second answer
	-- waiting to disagree with the first.
	if tile.kind == "mode" then
		local ok, v = pcall(tile.get)
		return ok and v and true or false
	end

	return nil
end

--- What a settings tile says when you hover it.
--
--  The state goes in the tooltip as well as on the chip, because On/Off in
--  eleven point beside a coloured disc is the sort of thing you read wrong once
--  and then distrust - and one of these four unlocks every frame on the screen.
function TB:TileTooltip(frame)
	local t = frame and frame.__tile
	if not t or not GameTooltip then return end

	GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
	GameTooltip:SetText(t.label or t.key, 1, 1, 1)

	local on = self:TileState(t)
	if on ~= nil then
		local c = on and Palette.c.accent or Palette.c.textDim
		GameTooltip:AddLine(on and "On" or "Off", c[1], c[2], c[3])
	end

	if t.tip then
		-- Wrapped. These run to three lines and an unwrapped AddLine draws one
		-- that reaches the far side of the screen.
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(t.tip, 0.8, 0.8, 0.85, true)
	end
	GameTooltip:Show()
end

function TB:ToggleTile(tile)
	if not tile then return false end

	if tile.kind == "launcher" then
		local entry = tile.entry or (A.Launchers and A.Launchers.byKey[tile.key])
		if entry then return A.Launchers:Click(entry, "LeftButton") end
		return false
	end

	local want = not self:TileState(tile)

	if tile.kind == "setting" then
		local t, k = Resolve(tile.path)
		if not t then return false end
		t[k] = want

		-- The same three-element rule the options panel uses. A module being
		-- switched off has to be told to tear itself down and one switched on
		-- has to be built; writing the flag and stopping there leaves a module
		-- running with its own setting saying it is off.
		local p = tile.path
		if #p == 3 and p[1] == "modules" and p[3] == "enabled" and A.modules[p[2]] then
			A:SetModuleEnabled(p[2], want)
		else
			A:Reconfigure()
		end
		self:RefreshTiles()
		return true
	end

	if tile.kind == "mode" then
		local ok, done = pcall(tile.set, want)
		if not ok or done == false then return false end

		-- The drawer gets out of the way when a mode is switched ON. Both of
		-- these are things you do TO the screen - drag a frame, hover a button
		-- and press a key - and neither is possible with a panel over half of
		-- it. Switching one off does not close anything, because then you are
		-- finished rather than starting.
		if want then self:SetOpen(false) end

		self:RefreshTiles()
		return true
	end

	return false
end

--- Ours, then whatever launchers the player has put in the grid. A list, so the
--  order is theirs and a third party's launcher sits alongside our settings.
function TB:TileList()
	local out = {}
	for _, t in ipairs(self.TILES) do out[#out + 1] = t end

	local c = Char()
	local chosen = c and c.tiles
	if type(chosen) == "table" and A.Launchers then
		for _, key in ipairs(chosen) do
			local entry = A.Launchers.byKey[key]
			if entry then
				out[#out + 1] = {
					kind = "launcher", key = key,
					label = entry.label or key, entry = entry,
				}
			end
		end
	end

	return out
end

-- ---------------------------------------------------------------------------

local TILE_H, TILE_GAP = 62, 8

-- A settings tile has two arrangements, and the width decides which.
--
--   ROW      [icon]  Combat collapse            On
--   STACKED  [icon]                             On
--            Combat collapse
--
-- The row is the one to want. Stacked, the label sits directly under the icon
-- with the whole middle-right of the tile empty, which is what got reported -
-- and it is the arrangement a 62px tile forces when there is no room beside the
-- icon for two words.
--
-- The numbers below are what a row costs: padding, the chip, the gap after it,
-- the gap before the state, the state itself, and padding again. Anything left
-- over is the label's, and below about sixty pixels of that a two-word setting
-- cannot wrap into it - so the flat drawer's narrow settings column keeps the
-- stack and the tall panel gets the row.
local TILE_PAD    = 12
local TILE_CHIP   = 30
local TILE_GAP_X  = 10     -- chip to label
local TILE_STATE  = 30     -- room reserved for "On" / "Off"
local TILE_NAME_MIN = 60   -- below this a row is not worth having

-- ---------------------------------------------------------------------------
-- the MAIL section
-- ---------------------------------------------------------------------------

local MAIL_ROW_H, MAIL_ROW_GAP = 30, 5
local MAIL_CHIP = 24

function TB:BuildMail()
	if not self.content or self.content.mail then return end
	local head = W.Text(self.content, "tbSection", "LEFT")
	head:SetText(Spaced("MAIL"))
	self.content.mailHead = head

	local hint = W.Text(self.content, "tbLabel", "RIGHT")
	self.content.mailHint = hint

	self.content.mail = {}
	self:RefreshMailRows()
end

--- One row per sender the client named, up to its cap of three.
--
--  Rows are REUSED and hidden rather than destroyed, like every other list
--  here: mail arrives mid-combat and creating frames then is a thing to avoid
--  on principle even where it is currently allowed.
function TB:RefreshMailRows()
	if not self.content or not self.content.mail then return end
	local has, senders, unread, stale = self:MailState()
	self._mailSenders = senders
	self._mailStale = stale

	-- "You have mail and we cannot say who from" is a real state, and it was
	-- reading as a bug because the section said so and stopped. It is worth ONE
	-- row saying why, since the answer is a thing the player can do: the client
	-- only names senders for mail that arrived while you were logged in, and
	-- the rest of it is behind a mailbox.
	local explain = has and #senders == 0

	-- And an EMPTY box gets a row of its own too, rather than the section
	-- disappearing.
	--
	-- It used to vanish, on the reasoning that a section reporting nothing is
	-- furniture. What that missed is that a section which is sometimes absent is
	-- a section you go looking for and cannot find - which is exactly what
	-- happened - and that the drawer's shape changing under you every time the
	-- postman calls is worse than one quiet line. The rail's envelope is still
	-- the thing you read at a glance; this is the drawer agreeing with it.
	local empty = not has

	local rows = senders
	if explain then
		rows = { _G.MAIL_LABEL or "Mail" }
	elseif empty then
		rows = { "none" }
	end
	senders = rows

	-- How many rows are DRAWN, which is not how many senders there are: both the
	-- explain row and the empty row are one row carrying no sender at all. The
	-- layout reserves height from this, and reserving from the sender count is
	-- what would draw a row it had not made room for.
	self._mailRowCount = #rows

	for i = 1, self.MAIL_ROWS do
		local row = self.content.mail[i]
		if not row then
			row = CreateFrame("Frame", nil, self.content)
			row:SetHeight(MAIL_ROW_H)

			-- A sender's INITIAL in a chip, not a repeated envelope.
			--
			-- Three rows carrying the same small mail glyph is three copies of
			-- what the section heading already said, and it read as flat as it
			-- was: the only thing that varied down the column was the name. The
			-- initial varies with the row, which is the whole job of a list.
			--
			-- Chips are the drawer's own language - the settings tiles are built
			-- from the same widget - and they are wrong on the RAIL for the
			-- opposite reason: out there the bare glyphs ARE the rail, and only
			-- a launcher, which is somebody else's art, gets a circle.
			local chip = W.CreateBadge(row, { size = MAIL_CHIP, style = "tbChip" })
			chip:SetPoint("LEFT", row, "LEFT", 0, 0)
			row.chip = chip

			row.name = W.Text(row, "tbCardTitle", "LEFT")
			row.name:SetPoint("LEFT", chip, "RIGHT", 10, 0)
			self.content.mail[i] = row
		end
		local who = senders[i]
		row.name:SetText(who or "")
		row:SetShown(who ~= nil)

		if who and empty then
			-- An empty box. The quiet chip the explain row uses, and a zero
			-- rather than a question mark: this section knows the answer, and
			-- the answer is none.
			row.chip.label:SetText("0")
			local c = Palette.c
			local q = c.cardBg
			row.chip.disc:SetVertexColor(q[1], q[2], q[3], q[4] or 1)
			row.chip.ring:Show()
			local e = c.glassEdge
			row.chip.ring:SetVertexColor(e[1], e[2], e[3], 0.9)
			W.Color(row.chip.label, c.textDim)
			row.name:SetText("No unread mail")
			W.Color(row.name, c.textDim)
		elseif who and explain then
			-- The one row that is not a sender. A question mark rather than an
			-- initial, and the quiet fill rather than the accent: this is the
			-- section admitting what it does not know, not an entry in a list.
			row.chip.label:SetText("?")
			local c = Palette.c
			local q = c.cardBg
			row.chip.disc:SetVertexColor(q[1], q[2], q[3], q[4] or 1)
			row.chip.ring:Show()
			local e = c.glassEdge
			row.chip.ring:SetVertexColor(e[1], e[2], e[3], 0.9)
			W.Color(row.chip.label, c.textDim)
			row.name:SetText("Senders show after a mailbox visit")
			W.Color(row.name, c.textDim)
		elseif who then
			W.Color(row.name, Palette.c.text)
			-- The first LETTER, not the first byte. A name can begin with a
			-- multi-byte character on any client, and half of one draws as a
			-- box. Lua has no unicode, so the continuation bytes are counted
			-- from the lead byte's own high bits, which is the one thing UTF-8
			-- guarantees without a library.
			local b1 = who:byte(1) or 0
			local n = (b1 < 0x80 and 1) or (b1 < 0xE0 and 2) or (b1 < 0xF0 and 3) or 4
			local initial = who:sub(1, n)
			if n == 1 then initial = initial:upper() end
			row.chip.label:SetText(initial)

			local c = Palette.c
			local fill, ink = c.btnFill, c.btnFillText
			row.chip.disc:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1)
			-- Filled chip, no rim - see the settings tiles. A bright ring lapped
			-- a pixel proud of a bright disc doubles the coverage in the outer
			-- pixel and the edge stops being an edge.
			row.chip.ring:Hide()
			W.Color(row.chip.label, ink)
		end
	end

	-- "You have mail but we cannot say from whom" is a real state - auction
	-- house and NPC mail arrives with no name on it - so the section still
	-- appears, carrying the client's own wording instead of a list.
	-- The hint says WHICH claim the section is making, because there are three
	-- and they are not the same:
	--
	--   a true unread count, from the last time you stood at a mailbox
	--   a number of senders the client named, capped at three by the client
	--   nothing at all, which is what "you have mail" on its own means
	if self.content.mailHint then
		local c = Palette.c
		if not has then
			-- Nothing. The row already says "No unread mail" and a hint saying
			-- the same thing at the other end of the line is the section saying
			-- it twice.
			self.content.mailHint:SetText("")
		elseif explain then
			self.content.mailHint:SetText(_G.HAVE_MAIL or "New mail")
			W.Color(self.content.mailHint, c.textDim)
		elseif unread then
			-- A REAL count. Marked as remembered rather than current, because
			-- it is: mail read on another character, or sent since, is not in
			-- it. An unqualified number here would be the one lie this section
			-- has been careful not to tell.
			self.content.mailHint:SetText(unread .. " unread \194\183 last visit")
			W.Color(self.content.mailHint, c.textDim)
		else
			self.content.mailHint:SetText(#senders
				.. (#senders >= self.MAIL_ROWS and "+" or "") .. " new")
			W.Color(self.content.mailHint, c.accent or c.text)
		end
	end
end

--- Lay a tile's three pieces out for the width it has been given.
--
--  Called from the layout rather than from the constructor, because the width
--  is the input and only the layout knows it. Both arrangements are set fully -
--  every anchor cleared and re-made - so a tile that changes width when the
--  drawer is re-docked cannot keep half of the other one.
function TB:ArrangeTile(tile, width)
	if not tile or not tile.chip then return end
	local room = (width or 0) - TILE_PAD * 2 - TILE_CHIP - TILE_GAP_X - TILE_STATE
	local row  = room >= TILE_NAME_MIN

	tile.chip:ClearAllPoints()
	tile.state:ClearAllPoints()
	tile.name:ClearAllPoints()

	if row then
		-- Everything on one line, vertically centred. The label takes the space
		-- between the icon and the state, and WRAPS into it rather than being
		-- cut: there are two lines' worth of height going spare in a 62px tile
		-- once nothing is stacked under the icon.
		tile.chip:SetPoint("LEFT", tile, "LEFT", TILE_PAD, 0)
		tile.state:SetPoint("RIGHT", tile, "RIGHT", -TILE_PAD, 0)
		tile.name:SetPoint("LEFT", tile.chip, "RIGHT", TILE_GAP_X, 0)
		tile.name:SetPoint("RIGHT", tile.state, "LEFT", -8, 0)
		tile.name:SetWordWrap(true)
		tile.name:SetJustifyV("MIDDLE")
	else
		-- Not enough width beside the icon, so the label goes under it. No
		-- wrapping here: the chip is in the top of a 62px tile and a second line
		-- lands on it.
		tile.chip:SetPoint("TOPLEFT", tile, "TOPLEFT", TILE_PAD, -10)
		tile.state:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -TILE_PAD, -16)
		tile.name:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", TILE_PAD, 10)
		tile.name:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -TILE_PAD, 10)
		tile.name:SetWordWrap(false)
		tile.name:SetJustifyV("BOTTOM")
	end
	-- Written down rather than recomputed by anyone who wants it. The label's
	-- two anchors are to two DIFFERENT frames in the row form, so its width
	-- cannot be read back off the region - not by the harness, and not by a
	-- diagnostic either. This is the number that decided the arrangement, so it
	-- is the honest one to keep.
	tile._nameRoom = row and room or nil
	tile._row = row
	return row
end

function TB:BuildTiles()
	if not self.content or self.content.tiles then return end
	local head = W.Text(self.content, "tbSection", "LEFT")
	head:SetText(Spaced("UI SETTINGS"))
	self.content.tilesHead = head
	self.content.tiles = {}
	self:RefreshTiles()
end

function TB:RefreshTiles()
	if not self.content or not self.content.tiles then return end
	local list = self:TileList()
	self._tileList = list

	for i, t in ipairs(list) do
		local tile = self.content.tiles[i]
		if not tile then
			tile = Glass.CreatePanel(self.content, { corner = 16 })
			tile:SetHeight(TILE_H)

			-- The chip carries the state, which is what the deck says state is
			-- carried by: an accent fill when on, a dim one when off. The
			-- per-setting glyph inside it is not drawn yet - there is no such
			-- art, and a new .tga needs a client restart rather than a reload -
			-- so the chip reads its state by fill alone for now, which is the
			-- half of it the deck leans on anyway.
			-- W.CreateBadge, not a pill. A 30x30 pill draws the 512-wide pill
			-- art with its caps minified eight times, and its rim - three
			-- texels there - lands under half a pixel here, which is the
			-- speckled circle that got reported. The badge is the solved
			-- version of exactly this shape: a masked disc, a rim lapped one
			-- PHYSICAL pixel proud of it, and a diameter snapped in the badge's
			-- own units so the ring does not sit across a pixel boundary all
			-- the way round.
			local chip = W.CreateBadge(tile, { size = 30 })
			chip.label:Hide()
			tile.chip = chip

			local icon = chip:CreateTexture(nil, "OVERLAY")
			icon:SetPoint("CENTER", chip, "CENTER", 0, 0)
			icon:SetSize(17, 17)
			tile.icon = icon

			tile.state = W.Text(tile, "tbLabel", "RIGHT")
			tile.name  = W.Text(tile, "tbCardBody", "LEFT")
			-- Anchored by ArrangeTile, which needs the tile's WIDTH and
			-- therefore cannot run until the layout has set one.
			self:ArrangeTile(tile, 0)

			tile:EnableMouse(true)
			tile:SetScript("OnMouseUp", function(self2)
				if self2.__tile then TB:ToggleTile(self2.__tile) end
			end)

			-- Read off __tile at hover time rather than captured when the frame
			-- was made. These tiles are REUSED - RefreshTiles hands frame 3 to
			-- whichever entry is third now, and a launcher the player added can
			-- put a different one there - so a closed-over tile would describe
			-- whatever this frame used to be.
			tile:SetScript("OnEnter", function(self2)
				TB:TileTooltip(self2)
			end)
			tile:SetScript("OnLeave", function()
				if GameTooltip then GameTooltip:Hide() end
			end)
			self.content.tiles[i] = tile
		end

		tile.__tile = t
		tile.name:SetText(t.label or t.key)

		-- The chip's glyph. Settings tiles name their own; a launcher tile uses
		-- the addon's own icon, which it has and we do not.
		if t.kind ~= "launcher" then
			if Media:SetIcon(tile.icon, t.key) then
				tile.icon:Show()
			else
				tile.icon:Hide()
			end
		end

		local on = self:TileState(t)
		if on == nil then
			-- A launcher. No state, so no chip label - and its own icon, which
			-- is the one thing it does have that our settings do not.
			tile.state:SetText("")
			local ic = t.entry and t.entry.obj and t.entry.obj.icon
			if ic then tile.icon:SetTexture(ic) end
			tile.icon:SetShown(ic ~= nil)
			W.Color(tile.chip.text or tile.name, Palette.c.text)
		else
			tile.state:SetText(on and "On" or "Off")
			W.Color(tile.state, on and Palette.c.accent or Palette.c.textDim)
			-- Dark ink on the accent chip, dim ink on the quiet one. The deck
			-- carries the state in the CHIP, and a light glyph on a light fill
			-- is the one combination that says nothing.
			if tile.icon:IsShown() then
				local c = on and Palette.c.btnFillText or Palette.c.textDim
				tile.icon:SetVertexColor(c[1], c[2], c[3], on and 1 or 0.55)
			end
		end
		-- `btnFill` is the deck's opaque accent - already its own token because
		-- the deck asks for dark text on it, which is exactly the chip's "on".
		-- NOT an invented name: ApplySkin falls back to plain glass for a token
		-- it does not know, so a typo here would make On and Off identical and
		-- say nothing at all.
		-- The chip carries the state: the deck's opaque accent when on, the
		-- quiet fill when off. Vertex colours rather than ApplySkin, because a
		-- badge is two plain textures rather than a Glass surface.
		local fill = on and Palette.c.btnFill or Palette.c.cardBg
		tile.chip.disc:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1)

		-- A FILLED chip needs no rim, and putting one on it is what made these
		-- read as smudges rather than circles: a bright ring lapped one pixel
		-- proud of a bright disc doubles the coverage in the outer pixel, so the
		-- edge stops being an edge and becomes a two-pixel gradient. The rim is
		-- for the QUIET state, where the disc is nearly the panel colour and has
		-- nothing else to define it.
		tile.chip.ring:SetShown(not on)
		if not on then
			local edge = Palette.c.cardEdge
			tile.chip.ring:SetVertexColor(edge[1], edge[2], edge[3], edge[4] or 1)
		end
		tile.chip._fillColor = fill
		tile:Show()
	end

	for i = #list + 1, #self.content.tiles do
		self.content.tiles[i]:Hide()
	end

	self:LayoutTiles()
end


-- ---------------------------------------------------------------------------
-- the addon list
--
-- Every loaded addon, which is a SUPERSET of the ones you can do anything with.
-- Core/Launchers.lua finds the actionable half - an LDB launcher, a LibDBIcon
-- button, or a hand-rolled one - and plenty of addons offer none of those.
--
-- A row with nothing behind it is still worth listing: you want to know what is
-- loaded. But it must LOOK inert rather than silently doing nothing when
-- clicked, which is the most common case and therefore the one designed first.
-- ---------------------------------------------------------------------------

local ROW_H, ROW_GAP = 26, 4

--- Loaded addons, by title, with their launcher entry where there is one.
--
--  Titles carry colour escapes surprisingly often - addons put their own name in
--  their TOC with |cff codes - so the title is used as given and the NAME is
--  what the launcher is matched on.
--- A registry key, made readable.
--
--  An LDB name is whatever the addon picked and a LibDBIcon one is often worse:
--  "LeaPlusCustomIcon_SmartBuffMiniMapButton" is a real entry on this machine.
--  The addon's own title is preferred wherever one matches; this is the
--  fallback, and it only trims the furniture rather than trying to be clever -
--  a name we cannot improve is left exactly as the addon wrote it, because a
--  half-mangled name is worse than a long one.
local function PrettyName(key)
	local s = tostring(key or "?")
	s = s:gsub("^LibDBIcon10_", "")
	s = s:gsub("MiniMapButton$", ""):gsub("MinimapButton$", "")
	s = s:gsub("MiniMapIcon$", ""):gsub("MinimapIcon$", "")
	s = s:gsub("CustomIcon_", "")
	s = s:gsub("^%s*(.-)%s*$", "%1")
	if s == "" then return tostring(key) end
	return s
end

function TB:AddonRows()
	local rows = {}
	local L = A.Launchers
	if not L then return rows end

	-- ONLY addons with a launcher. The first version listed every loaded addon
	-- on the theory that you want to know what is installed - and on screen that
	-- was twenty-five rows of which fifteen did nothing, which buried the ten
	-- that worked. What you want to know is what you can REACH from here; the
	-- rest is what the Blizzard addon list is for.
	--
	-- The count of the rest is still worth one line, so the header says how many
	-- of the loaded addons have a launcher at all.
	local titles = {}
	local api = C_AddOns or _G
	local count = (api.GetNumAddOns and api.GetNumAddOns()) or 0
	for i = 1, count do
		local name, title = api.GetAddOnInfo and api.GetAddOnInfo(i)
		if name then titles[name:lower()] = (title ~= "" and title) or name end
	end
	self._addonsLoaded = count

	for entry in L:Iterate() do
		rows[#rows + 1] = {
			name  = entry.key,
			-- see PrettyName below
			-- The addon's own title where the launcher's name matches one, since
			-- an LDB object is often named for the addon but not always titled
			-- like it.
			label = entry.label or titles[tostring(entry.key):lower()]
				or PrettyName(entry.key),
			entry = entry,
		}
	end

	table.sort(rows, function(x, y)
		return tostring(x.label):lower() < tostring(y.label):lower()
	end)

	return rows
end

-- ---------------------------------------------------------------------------
-- pinning
-- ---------------------------------------------------------------------------

function TB:Pinned()
	local c = Char()
	if not c then return {} end
	c.pinned = c.pinned or {}
	return c.pinned
end

function TB:IsPinned(key)
	for _, k in ipairs(self:Pinned()) do
		if k == key then return true end
	end
	return false
end

--- Pinning is an explicit instruction to put this addon on the rail, so it
--  CLAIMS the entry even if the minimap drawer already had it. Unpinning
--  releases, and the drawer takes it back on its next layout.
function TB:SetPinned(key, on)
	local pinned = self:Pinned()
	local L = A.Launchers
	local entry = L and L.byKey[key]
	if not entry then return false end

	if on and not self:IsPinned(key) then
		pinned[#pinned + 1] = key
		L:Claim(entry, self, true)
	elseif not on then
		for i = #pinned, 1, -1 do
			if pinned[i] == key then table.remove(pinned, i) end
		end
		L:Release(entry, self)
	end

	self:LayoutRail()
	self:RefreshAddons()
	return true
end

--- Take ownership of every pinned entry that exists right now.
--
--  Idempotent and cheap, so it can run on every launcher change rather than
--  only at enable - which is the difference between a pin surviving a reload
--  and appearing to have been forgotten.
function TB:ClaimPins()
	local L = A.Launchers
	if not L then return 0 end
	local n = 0

	-- Pins first, and forced: a pin is an explicit instruction to put this
	-- addon on the rail, so it overrides whoever holds it.
	for _, key in ipairs(self:Pinned()) do
		local e = L.byKey[key]
		if e and L:OwnerOf(e) ~= self then
			L:Claim(e, self, true)
			n = n + 1
		end
	end

	-- ...and with the drawer retired, EVERYTHING ELSE too.
	--
	-- Not greed: an unclaimed launcher button is one nobody positions, and a
	-- LibDBIcon button that nobody positions is one still sitting on the minimap
	-- ring. Clearing the ring is what the drawer was for, so somebody has to
	-- keep doing it - and the entries that are not pinned get parked by
	-- LayoutRail rather than drawn anywhere.
	--
	-- Unconditionally. This was gated on the minimap drawer being switched off,
	-- back when the drawer was still a setting; the key is gone now and the gate
	-- read nil rather than false, so it never fired and every launcher went
	-- unowned. There is one surface, so there is nothing to defer to.
	for e in L:Iterate() do
		if not L:OwnerOf(e) then
			L:Claim(e, self)
			n = n + 1
		end
	end

	return n
end

function TB:TogglePin(key)
	return self:SetPinned(key, not self:IsPinned(key))
end

-- ---------------------------------------------------------------------------
-- the rail
-- ---------------------------------------------------------------------------

--- Pinned buttons live ON the rail, so they are there when the drawer is shut -
--  which is the whole reason the rail is a separate surface.
--
--  Never Hide()n. A collected button belongs to another addon and may carry a
--  secure template; hiding a frame with a protected descendant is refused in
--  combat, and opening a drawer mid-fight is exactly the sort of thing people
--  do. Alpha and EnableMouse, the same rule the minimap drawer follows.
function TB:LayoutRail()
	if not self.rail then return end
	local L = A.Launchers
	if not L then return end

	local edge = self:Dock()
	local vertical = IsVertical(edge)
	local n = 0

	for _, key in ipairs(self:Pinned()) do
		local entry = L.byKey[key]
		local b = entry and entry.button
		if b and L:OwnerOf(entry) == self then
			n = n + 1

			-- RE-PREPARED on every layout, not just when claimed. LibDBIcon pins
			-- both strata and level with SetFixedFrameStrata/SetFixedFrameLevel
			-- so reparenting cannot shuffle its buttons behind things, and it
			-- re-applies that on its own Refresh and Show. Once it does, our
			-- SetFrameStrata below is quietly REFUSED: the button stays at
			-- MEDIUM level 8 while the rail sits at FULLSCREEN_DIALOG, the
			-- rail's own panel art is painted over the top of it, and the pin
			-- looks like it vanished. A reload brought them back because nothing
			-- had refreshed yet.
			--
			-- The drawer did exactly this on every layout and said why; that
			-- line went with the drawer and did not come to the rail.
			entry._prepared = nil
			L:Prepare(entry)

			pcall(L.RawSetParent, b, self.rail)
			pcall(L.RawClearAllPoints, b)
			local off = RAIL_PAD + RAIL_CHEV + RAIL_PAD + (n - 1) * (RAIL_ICON + RAIL_PAD)
			-- chevron, then pins, then the gear at the far end
			if vertical then
				pcall(L.RawSetPoint, b, "TOP", self.rail, "TOP", 0, -off)
			else
				pcall(L.RawSetPoint, b, "LEFT", self.rail, "LEFT", off, 0)
			end
			pcall(L.RawSetSize, b, RAIL_ICON, RAIL_ICON)
			if b.SetFrameStrata then pcall(b.SetFrameStrata, b, self.rail:GetFrameStrata()) end
			if b.SetFrameLevel then pcall(b.SetFrameLevel, b, self.rail:GetFrameLevel() + 5) end
			if b.SetAlpha then pcall(b.SetAlpha, b, 1) end
			if b.EnableMouse then pcall(b.EnableMouse, b, true) end
		end
	end

	-- Everything we own that is NOT pinned goes off screen. Parked, never
	-- hidden: these belong to other addons and may carry secure templates, and
	-- hiding a frame with a protected descendant is refused in combat.
	for e in L:Iterate() do
		if L:OwnerOf(e) == self and not self:IsPinned(e.key) then
			L:Park(e)
		end
	end

	self._railCount = n

	-- The rail grows to fit EVERYTHING on it: the chevron, one slot per pin,
	-- then the envelope and the gear at the far end.
	--
	-- The envelope was missing from this sum when it was added. It anchors above
	-- the gear and the gear anchors to the rail's far end, so a rail one icon
	-- too short does not clip it - it puts it exactly on top of the LAST PIN,
	-- where it reads as simply not being there. Anything anchored from the far
	-- end has to be counted here or it walks backwards into the list.
	local len = RAIL_PAD + RAIL_CHEV + RAIL_PAD + n * (RAIL_ICON + RAIL_PAD)
		+ (RAIL_ICON + RAIL_PAD)      -- mail
		+ RAIL_ICON + RAIL_PAD        -- gear
	-- The transport chip anchors off the envelope, which anchors off the gear,
	-- which anchors off the far end - so it has to be counted here for the same
	-- reason the envelope does, and with the same failure if it is not: it lands
	-- exactly on top of the last pin and reads as simply not being there.
	if self.rail.play and self.rail.play:IsShown() then
		len = len + RAIL_ICON + RAIL_PAD
	end
	if vertical then
		self.rail:SetSize(RAIL_W, math.max(len, RAIL_CHEV + RAIL_PAD * 2))
	else
		self.rail:SetSize(math.max(len, RAIL_CHEV + RAIL_PAD * 2), RAIL_W)
	end
end

-- ---------------------------------------------------------------------------
-- rows
-- ---------------------------------------------------------------------------

function TB:BuildAddons()
	if not self.content or self.content.addons then return end
	local head = W.Text(self.content, "tbSection", "LEFT")
	head:SetText(Spaced("ADDONS"))
	self.content.addonsHead = head

	local hint = W.Text(self.content, "tbLabel", "RIGHT")
	self.content.addonsHint = hint

	-- The arrow that says the list moves.
	--
	-- A CHEVRON TEXTURE, not an arrow character. Outfit is a text face with no
	-- geometric shapes in it - the gear had to become a drawn ring for exactly
	-- this reason, having rendered as the three bytes of its own UTF-8 - and
	-- U+2193 is no safer a bet than U+2699 was. The chevron is already loaded,
	-- already the drawer's own vocabulary, and rotates.
	local arrow = self.content:CreateTexture(nil, "OVERLAY")
	arrow:SetSize(9, 9)
	arrow:SetTexture(Media.texture.chevron)
	arrow:Hide()
	self.content.addonsArrow = arrow

	-- What the wheel lands on. A frame BEHIND the rows rather than the rows
	-- themselves: the wheel goes to the topmost frame under the cursor that has
	-- EnableMouseWheel set, and the rows do not, so they are transparent to it
	-- and this catches everything over the block. The rows get it too, further
	-- down, for the client that disagrees.
	local catch = CreateFrame("Frame", nil, self.content)
	catch:EnableMouseWheel(true)
	catch:SetScript("OnMouseWheel", function(_, delta) TB:ScrollAddons(delta) end)
	catch:Hide()
	self.content.addonsCatch = catch

	self.content.addons = {}
	self:RefreshAddons()
end

function TB:RefreshAddons()
	if not self.content or not self.content.addons then return end
	local rows = self:AddonRows()
	self._addonRows = rows

	local actionable = 0
	for _, r in ipairs(rows) do if r.entry then actionable = actionable + 1 end end
	self.content.addonsHint:SetText(#rows .. " installed \194\183 " .. actionable .. " with a launcher")

	for i, r in ipairs(rows) do
		local row = self.content.addons[i]
		if not row then
			row = CreateFrame("Button", nil, self.content)
			row:SetHeight(ROW_H)

			-- The rows take the wheel too, not only the frame behind them. The
			-- client sends it to the topmost frame under the cursor with the
			-- wheel enabled and a Button does not have it - so in theory the
			-- catcher behind is enough. In practice the cursor is over a row
			-- most of the time somebody wants to scroll, and this is one line
			-- against finding out that theory was wrong on somebody's client.
			row:EnableMouseWheel(true)
			row:SetScript("OnMouseWheel", function(_, delta) TB:ScrollAddons(delta) end)

			row.tile = Glass.CreatePanel(row, { corner = 8 })
			row.tile:SetSize(25, 25)
			row.tile:SetPoint("LEFT", row, "LEFT", 0, 0)
			row.icon = row.tile:CreateTexture(nil, "ARTWORK")
			row.icon:SetPoint("CENTER", row.tile, "CENTER", 0, 0)
			row.icon:SetSize(17, 17)
			-- The letter, for the many addons with no icon to offer.
			row.initial = W.Text(row.tile, "tbLabel", "CENTER")
			row.initial:SetPoint("CENTER", row.tile, "CENTER", 0, 0)

			-- Truncated, not wrapped. LibDBIcon registry names are whatever the
			-- addon chose - "LeaPlusCustomIcon_SmartBuffMiniMapButton" is a real
			-- one - and at two columns a name that long ran straight across the
			-- row beside it and the two overprinted.
			row.name = W.Text(row, "tbCardBody", "LEFT")
			row.name:SetPoint("LEFT", row.tile, "RIGHT", 8, 0)
			row.name:SetPoint("RIGHT", row.pinAnchor or row, "RIGHT", -18, 0)
			row.name:SetWordWrap(false)

			row.pin = CreateFrame("Button", nil, row)
			row.pin:SetSize(13, 13)
			row.pin:SetPoint("RIGHT", row, "RIGHT", 0, 0)
			row.pin.glyph = row.pin:CreateTexture(nil, "ARTWORK")
			row.pin.glyph:SetAllPoints(row.pin)
			Media:SetIcon(row.pin.glyph, "pin")
			row.pin:SetScript("OnClick", function(self2)
				local rr = self2:GetParent().__row
				if rr and rr.entry then TB:TogglePin(rr.entry.key) end
			end)

			row:SetScript("OnClick", function(self2)
				local rr = self2.__row
				if rr and rr.entry then A.Launchers:Click(rr.entry, "LeftButton") end
			end)

			self.content.addons[i] = row
		end

		row.__row = r
		row.name:SetText(r.label)

		-- The icon, or the initial. Only about half the addons on a machine
		-- declare one, so the letter tile is the BASE CASE rather than a
		-- placeholder - a grid where half the tiles are a question mark looks
		-- broken, and the handoff's "use real addon icons" cannot be followed
		-- for the other half.
		local icon = r.entry and r.entry.obj and r.entry.obj.icon
		if not icon and C_AddOns and C_AddOns.GetAddOnMetadata then
			local ok, v = pcall(C_AddOns.GetAddOnMetadata, r.name, "IconTexture")
			if ok then icon = v end
		end
		if icon then
			row.icon:SetTexture(icon)
			row.icon:Show()
			row.initial:SetText("")
		else
			row.icon:Hide()
			row.initial:SetText((r.label or "?"):sub(1, 1):upper())
		end

		-- A row with nothing behind it is listed and INERT, and looks it. The
		-- alternative - a row that accepts a click and does nothing - is the
		-- one thing worse than not listing it.
		if r.entry then
			row:EnableMouse(true)
			row.pin:Show()
			W.Color(row.name, Palette.c.text)
			local pinned = self:IsPinned(r.entry.key)
			Media:SetIcon(row.pin.glyph, pinned and "pinned" or "pin")
			row.pin.glyph:SetVertexColor(
				pinned and Palette.c.accent[1] or Palette.c.textDim[1],
				pinned and Palette.c.accent[2] or Palette.c.textDim[2],
				pinned and Palette.c.accent[3] or Palette.c.textDim[3],
				pinned and 1 or 0.45)
		else
			row:EnableMouse(false)
			row.pin:Hide()
			W.Color(row.name, Palette.c.textDim)
		end

		row:Show()
	end

	for i = #rows + 1, #self.content.addons do
		self.content.addons[i]:Hide()
	end

	self:LayoutAddons()
end


-- ---------------------------------------------------------------------------
-- the micro menu
--
-- Not in the design handoff; added because hiding MainMenuBar takes the micro
-- menu with it and the README has owed it a home ever since.
--
-- OUR buttons, not Blizzard's. The first plan adopted the real frames -
-- reparenting them is legal, they are plain <Button>s with no Secure inherit
-- and Blizzard's own container does exactly that - but adopting them buys a
-- three-way argument over who owns them: ActionBars banishes them, QuestLog
-- hooks UpdateMicroButtons for the quest button's lit state, and this module
-- would want their position. Building nine of our own costs a table of
-- functions and ends the argument. The originals stay hidden, exactly as the
-- action bar sweep already leaves them.
--
-- The ACTIONS are read off Blizzard's own handlers rather than guessed, because
-- guessing gets one of nine subtly wrong and nobody notices until they click it:
--
--   Character  ToggleCharacter("PaperDollFrame")   XML OnClick
--   Spellbook  ToggleSpellBook(BOOKTYPE_SPELL)     XML OnClick
--   Talents    ToggleTalentFrame()                 XML OnClick
--   Quest log  ToggleQuestLog()                    XML OnClick - and OURS, the
--                                                  quest log module replaces it
--   Social     ToggleFriendsFrame()                SocialsMicroButtonMixin
--   Guild      ToggleGuildFrame()                  GuildMicroButtonMixin
--   Map        ToggleWorldMap()                    XML OnClick
--   Menu       ToggleGameMenu()                    bound in Bindings_Vanilla
--   Help       ToggleHelpFrame()                   XML OnClick
--
-- SOCIAL AND GUILD ARE MUTUALLY EXCLUSIVE, which is the one thing here that is
-- not obvious. Both mixins carry an UpdateVisibility that reads the
-- `useClassicGuildUI` CVar, and each shows only when the other does not:
-- Socials with the classic guild UI, Guild without it. So there are nine
-- buttons declared and eight on screen, and a row that drew both would have one
-- that opens a window this client does not use.
--
-- Every action is probed before its button is built. A global that is not there
-- is a button that is not drawn, rather than a button that errors on click.
-- ---------------------------------------------------------------------------

local MICRO_SIZE, MICRO_GAP = 26, 6

TB.MICRO = {
	{ key = "character", label = "Character",
	  fn = function() ToggleCharacter("PaperDollFrame") end,
	  probe = function() return ToggleCharacter ~= nil end },
	{ key = "spellbook", label = "Spellbook",
	  fn = function() ToggleSpellBook(BOOKTYPE_SPELL or "spell") end,
	  probe = function() return ToggleSpellBook ~= nil end },
	{ key = "talents",   label = "Talents",
	  fn = function() ToggleTalentFrame() end,
	  probe = function() return ToggleTalentFrame ~= nil end },
	{ key = "quests",    label = "Quest log",
	  fn = function() ToggleQuestLog() end,
	  probe = function() return ToggleQuestLog ~= nil end },
	{ key = "social",    label = "Social",
	  fn = function() ToggleFriendsFrame() end,
	  probe = function()
		  if not ToggleFriendsFrame then return false end
		  -- Only with the classic guild UI; otherwise Guild takes this slot.
		  if GetCVarBool then return GetCVarBool("useClassicGuildUI") and true or false end
		  return true
	  end },
	{ key = "guild",     label = "Guild",
	  fn = function() ToggleGuildFrame() end,
	  probe = function()
		  if not ToggleGuildFrame then return false end
		  if GetCVarBool then return not GetCVarBool("useClassicGuildUI") end
		  return false
	  end },
	{ key = "map",       label = "Map",
	  fn = function() ToggleWorldMap() end,
	  probe = function() return ToggleWorldMap ~= nil end },
	{ key = "menu",      label = "Menu",
	  fn = function()
		  if ToggleGameMenu then return ToggleGameMenu() end
		  -- What MainMenuMicroButtonMixin:OnMouseUp does by hand, for a client
		  -- without the global.
		  if GameMenuFrame and GameMenuFrame:IsShown() then
			  if HideUIPanel then HideUIPanel(GameMenuFrame) end
		  elseif GameMenuFrame and ShowUIPanel then
			  ShowUIPanel(GameMenuFrame)
		  end
	  end,
	  probe = function() return ToggleGameMenu ~= nil or GameMenuFrame ~= nil end },
	{ key = "help",      label = "Help",
	  fn = function() ToggleHelpFrame() end,
	  probe = function() return ToggleHelpFrame ~= nil end },
}

--- Which of the nine this client actually offers.
function TB:MicroList()
	local out = {}
	for _, m in ipairs(self.MICRO) do
		local ok, present = pcall(m.probe)
		if ok and present then out[#out + 1] = m end
	end
	return out
end

function TB:BuildMicro()
	if not self.content or self.content.micro then return end
	local head = W.Text(self.content, "tbSection", "LEFT")
	head:SetText(Spaced("MENU"))
	self.content.microHead = head
	self.content.micro = {}
	self:RefreshMicro()
end

function TB:RefreshMicro()
	if not self.content or not self.content.micro then return end
	local list = self:MicroList()
	self._microList = list

	for i, m in ipairs(list) do
		local b = self.content.micro[i]
		if not b then
			b = CreateFrame("Button", nil, self.content)
			b:SetSize(MICRO_SIZE, MICRO_SIZE)

			-- Glyph above, name below, the way the deck draws the MENU row.
			-- A chip behind every one made eight filled circles in a block that
			-- read as heavier than the widget cards under it; the glyph carries
			-- itself and the row stays quiet.
			--
			-- No glyph ART yet. The concept's icon language is lucide-style
			-- strokes, there is no such .tga in Media/Textures, and a new
			-- texture file needs a client RESTART rather than a reload - so it
			-- is a generator pass of its own. The initial stands in, with the
			-- name UNDER it rather than only on a tooltip: a label you can read
			-- is worth more than a letter you have to decode.
			b.glyph = b:CreateTexture(nil, "ARTWORK")
			b.glyph:SetPoint("TOP", b, "TOP", 0, -5)
			b.glyph:SetSize(20, 20)

			b.name = W.Text(b, "tbLabel", "CENTER")
			b.name:SetPoint("TOP", b.glyph, "BOTTOM", 0, -4)
			b.name:SetPoint("LEFT", b, "LEFT", 2, 0)
			b.name:SetPoint("RIGHT", b, "RIGHT", -2, 0)

			b:SetScript("OnClick", function(self2)
				local mm = self2.__micro
				if mm then pcall(mm.fn) end
			end)
			b:SetScript("OnEnter", function(self2)
				if not GameTooltip or not self2.__micro then return end
				GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
				GameTooltip:SetText(self2.__micro.label)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function()
				if GameTooltip then GameTooltip:Hide() end
			end)

			self.content.micro[i] = b
		end

		b.__micro = m
		-- The icon, and the initial only if the sheet has nothing for it. A
		-- missing name draws the WHOLE atlas without a SetTexCoord, which is
		-- unmistakable rather than subtle - but the fallback means a key added
		-- here before its glyph is drawn degrades to a letter instead.
		if Media:SetIcon(b.glyph, m.key) then
			b.glyph:Show()
			if b.initial then b.initial:SetText("") end
		else
			b.glyph:Hide()
			if not b.initial then
				b.initial = W.Text(b, "tbCardTitle", "CENTER")
				b.initial:SetPoint("TOP", b, "TOP", 0, -4)
			end
			b.initial:SetText((m.label or "?"):sub(1, 1):upper())
		end
		W.Color(b.glyph and b.name or b.name, Palette.c.textDim)
		if b.glyph.SetVertexColor then
			local c = Palette.c.text
			b.glyph:SetVertexColor(c[1], c[2], c[3], 0.9)
		end
		b.name:SetText(m.label or "")
		W.Color(b.name, Palette.c.textDim)
		b:Show()
	end

	for i = #list + 1, #self.content.micro do
		self.content.micro[i]:Hide()
	end

	self:LayoutMicro()
end

-- ---------------------------------------------------------------------------
-- layout: ONE top-down pass, in Lua arithmetic
--
-- The first version anchored each section to the one above it - the tiles to
-- the last widget card, the addon list to the last tile - and measured the room
-- left with GetBottom(). Both were wrong, and together they drew every section
-- on top of every other:
--
--   * A region given SetPoint("TOPLEFT", content, ...) AND
--     SetPoint("TOP", other, "BOTTOM", ...) has two anchors on the same axis.
--     The second does not replace the first; the frame is stretched between
--     them, and where it lands is not what either line says.
--   * GetBottom() answers in screen coordinates and only once a frame has been
--     positioned AND shown. Called during the very pass that positions things,
--     it returns whatever was true last frame - or nil on the first one, which
--     the `or 0` then quietly turned into "the bottom of the screen".
--
-- So there is no chaining and no measuring. A running `y` accumulates down the
-- panel and every region is anchored TOPLEFT to the content frame at an offset
-- this function computed. It is arithmetic; it cannot disagree with itself, and
-- it produces the same answer on the first pass as on the hundredth.
-- ---------------------------------------------------------------------------

local HEADER_H   = 30
-- The What's new card. 84 was the height of a card with a title and a body on
-- it, before the Notes link was added underneath - so the body ran to the
-- bottom edge and Notes was drawn through the last line of it. This is the
-- title, two rendered lines of body (one changelog line usually wraps to two at
-- the vertical panel's width), the link, and the padding round the lot.
local NEWS_H     = 100
local SECTION_H  = 20      -- a section label and the gap under it
local SECTION_GAP = 14     -- between one section's last row and the next label
local MICRO_CELL_H = 46
local MICRO_PER_ROW = 4

-- Flat, the row is glyphs ONLY and the cell shrinks to fit them.
--
-- Eight cells across a column a fifth of the panel's width is about thirty
-- pixels each, and "Character" does not go in thirty pixels - it came out as
-- "Ch...". The concept draws this row as bare glyphs for exactly that reason,
-- and the names are on the tooltips where a name that does not fit belongs.
local MICRO_CELL_H_FLAT = 30

local function Cols(key, fallback)
	return math.max(1, tonumber(A.Config:Module("toolbox")[key]) or fallback)
end

--- Rows of `n` items at `per` per row.
local function RowsFor(n, per)
	return math.ceil(math.max(0, n) / math.max(1, per))
end

--- Place the i-th frame of a grid whose top-left corner is (x, y) in content
--  space, y measured DOWN.
--
--  Three lines, and it is a function because it was four copies of three lines:
--  the vertical panel does this for the micro row, the widget cards, the addon
--  rows and the settings tiles, and the horizontal panel would have made it
--  eight. The arithmetic is the thing most worth having exactly one of - an
--  off-by-one in the row index is a section drawn on top of the one above it.
local function GridPlace(content, frame, i, x, y, cols, cellW, cellH, gapX, gapY)
	local r, c = math.floor((i - 1) / cols), (i - 1) % cols
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", content, "TOPLEFT",
		x + c * (cellW + (gapX or 0)), -(y + r * (cellH + (gapY or 0))))
end

--- Move the addon list by whole ROWS.
--
--  Rows, not entries: the list is two columns wide, so stepping by one would
--  swap which column every name is in and the list would appear to shuffle
--  rather than scroll.
--
--  The offset is clamped by the LAYOUT rather than here, because only the layout
--  knows how many rows fit - that is a function of the panel, the dock, and
--  everything above the list. This just moves the number and asks for a redraw.
function TB:ScrollAddons(delta)
	if not delta or delta == 0 then return end
	local cols = Cols("addonColumns", 2)
	self._addonOffset = math.max(0, (self._addonOffset or 0) - delta * cols)
	self:LayoutContent()
end

--- Place the rows for one addon list, cutting to `maxShown` and honouring the
--  scroll offset, and write the hint that says what is off the end.
--
--  Shared by both layouts. The two differ in where the block goes and how much
--  room it has; what they do with it - which slice of the list, in which slots,
--  with which arrow on the heading - is the same in both, and was the obvious
--  next thing to drift apart.
--
--  Returns the number of rows placed.
--- `headY` is the HEADING's line, not the rows'.
--
--  Passed separately rather than derived, because the hint and the arrow belong
--  on the heading and everything else here belongs below it. Deriving it from
--  `y - SECTION_H` would work today and be wrong the moment a layout puts a gap
--  between the two. It was neither for a while: the hint went out at the rows'
--  y and was drawn straight through the first row of the list, which is the
--  version of this you can see in a screenshot.
function TB:PlaceAddonRows(x, y, width, cols, maxShown, hintRight, headY)
	headY = headY or y
	local content = self.content
	local frames  = content.addons or {}
	local rows    = self._addonRows or {}
	local total   = #rows

	-- Clamped HERE, where maxShown is known. Scrolling past the end and then
	-- widening the drawer would otherwise leave the list parked below its own
	-- last row, showing nothing.
	--
	-- ROUNDED UP TO A ROW BOUNDARY, not down. The offset moves a row at a time -
	-- it has to, or the two columns swap over as you scroll - so the last page
	-- has to start on a boundary at or PAST the point where the window's last
	-- slot reaches the final entry. Taking the boundary below it instead leaves
	-- that entry one slot under the fold with nowhere left to scroll, and it
	-- only shows up on an ODD number of launchers: an even one lands on the
	-- boundary exactly and loses nothing, which is why 56 of them were fine and
	-- the fifty-seventh could not be reached.
	local maxOffset = math.max(0, total - maxShown)
	if maxOffset % cols ~= 0 then
		maxOffset = maxOffset + cols - (maxOffset % cols)
	end

	local offset = math.min(math.max(0, self._addonOffset or 0), maxOffset)
	offset = offset - (offset % cols)
	self._addonOffset = offset

	local rw = (width - ROW_GAP * (cols - 1)) / cols
	local shown = 0
	for i, row in ipairs(frames) do
		local slot = i - offset
		if i <= total and slot >= 1 and slot <= maxShown then
			row:SetWidth(rw)
			GridPlace(content, row, slot, x, y, cols, rw, ROW_H, ROW_GAP, ROW_GAP)
			row:Show()
			shown = shown + 1
		else
			row:Hide()
		end
	end

	self._addonsCut = math.max(0, total - shown)
	self._addonsMore = math.max(0, total - offset - shown)   -- below the fold

	-- The hint, and the arrow beside it.
	--
	-- One arrow, not two: it points the way there is MORE, which is down until
	-- you reach the end and up once you have. Two would need two textures and a
	-- rule for what to do when only one direction is live, and the answer to
	-- "can I go back" is obvious once you have been somewhere.
	local hint, arrow = content.addonsHint, content.addonsArrow
	if hint then
		hint:ClearAllPoints()
		local scrollable = self._addonsCut > 0 or offset > 0
		if arrow then
			arrow:ClearAllPoints()
			arrow:SetShown(scrollable)
			-- Chevron.tga is a V - it points DOWN at rotation 0, which is what
			-- the rail's chevron had to learn the hard way. Up is pi.
			if arrow.SetRotation then
				pcall(arrow.SetRotation, arrow, self._addonsMore > 0 and 0 or math.pi)
			end
			local c = Palette.c
			arrow:SetVertexColor(c.text[1], c.text[2], c.text[3], 0.55)
			arrow:SetPoint("TOPRIGHT", content, "TOPLEFT", hintRight, -(headY + 5))
		end
		hint:SetPoint("TOPRIGHT", content, "TOPLEFT",
			hintRight - (scrollable and 14 or 0), -headY)
		hint:SetText(scrollable
			and (total .. " \194\183 scroll")
			or (total .. " with a launcher"))
	end

	-- The wheel catcher covers the block, so the wheel works anywhere over the
	-- list rather than only over a row.
	local catch = content.addonsCatch
	if catch then
		local rowsShown = RowsFor(shown, cols)
		catch:ClearAllPoints()
		catch:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
		catch:SetSize(math.max(1, width),
			math.max(1, rowsShown * (ROW_H + ROW_GAP)))
		catch:SetShown(shown > 0)
	end

	return shown
end

-- ---------------------------------------------------------------------------
-- the horizontal drawer
--
-- Top and bottom dock to a panel 1280x240 in deck units - more than five times
-- wider than it is tall. The vertical layout's single running `y` draws a column
-- of sections down the left fifth of that, with the last three off the bottom
-- and most of the panel empty. It was written for the tall narrow panel and says
-- so; this is the other one.
--
-- So the sections become COLUMNS. Each lays out exactly as it does in the
-- vertical panel - a heading, then a grid - from its own origin, and each cuts
-- to the panel's height on its own account rather than the whole drawer giving
-- way in one fixed order. There is no order to give way in when the sections are
-- side by side.
-- ---------------------------------------------------------------------------

-- The deck's own proportions rather than equal shares. Identity and widgets take
-- about a quarter each, the addon list a little less, mail least of all - three
-- short names is the most it ever holds - and the settings tiles are fixed-size
-- chips where everything else is text that wants room.
-- Rebalanced against a real screenshot rather than against the concept's
-- proportions. The addon list is the column with the longest strings in it -
-- "Auc-Util-AutoMagic" is a real registry name - and at 22 it was truncating
-- every second one to "Auc-Util-A...". Mail holds one line of a sender's name
-- and the settings tiles are fixed-size chips, so both give some back.
local H_WEIGHTS = { identity = 20, widgets = 19, addons = 27, mail = 14, settings = 20,
	nowplaying = 17 }
local H_COL_GAP = 18

--- The shortest the flat panel can usefully be, in panel units.
--
--  The identity column is the one that cannot give way: a title, the What's new
--  card and one row of glyphs, every one of them a fixed height. Everything else
--  here is a grid that cuts to fit and says what it dropped. So this is the
--  number, computed rather than written down - the constants are two hundred
--  lines from PanelSize, which is exactly the distance over which a literal 218
--  goes stale without anybody noticing.
function TB:HorizontalFloor()
	return PAD * 2 + HEADER_H + NEWS_H + SECTION_GAP + MICRO_CELL_H_FLAT
end

--- Which columns there are, left to right.
--
--  Mail has a COLUMN of its own rather than stacking under the addon list the
--  way an earlier version did. Stacked it costs the list half its rows every
--  time the postman calls, and the addon list is already the one section that
--  gives way. A drawer this wide has room for another column; it has no room for
--  that trade.
--
--  ALWAYS five, including when the box is empty. The column used to come and go
--  with the mail, which meant every other column changed width the moment
--  anything arrived - the whole drawer reflowing under you to report one more
--  thing. And a section that is sometimes absent is one you go looking for and
--  cannot find, which is how the vertical panel's version of this got noticed.
function TB:HorizontalColumns()
	local order = { "identity", "widgets", "addons", "mail", "settings" }
	-- NOW PLAYING is the one column that can be absent, and it is absent on the
	-- same question the console asks: no content installed, no player. That is a
	-- reload-scale fact rather than something that changes while you are looking
	-- at the drawer, so the column cannot appear under you and reflow the rest -
	-- which is the whole reason mail's column is permanent.
	if self:HasPlayer() then order[#order + 1] = "nowplaying" end
	return order, H_WEIGHTS
end

function TB:LayoutContent()
	if IsVertical(self:Dock()) then return self:LayoutVertical() end
	return self:LayoutHorizontal()
end

function TB:LayoutHorizontal()
	if not self.content or not self.panel then return end
	local content = self.content
	local w, h    = self.panel:GetWidth(), self.panel:GetHeight()

	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", self.panel, "TOPLEFT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", self.panel, "BOTTOMRIGHT", 0, 0)

	-- Same guard as the vertical pass, for the same reason: the first layout of
	-- the first login runs before three of the six sections have been built.
	local micros = content.micro  or {}
	local cards  = content.cards  or {}
	local addons = content.addons or {}
	local tilesF = content.tiles  or {}
	local mails  = content.mail   or {}

	local order, weights = self:HorizontalColumns()
	local total = 0
	for _, k in ipairs(order) do total = total + weights[k] end

	local avail = w - PAD * 2 - H_COL_GAP * (#order - 1)
	local colX, colW = {}, {}
	do
		local x = PAD
		for _, k in ipairs(order) do
			colW[k] = avail * (weights[k] / total)
			colX[k] = x
			x = x + colW[k] + H_COL_GAP
		end
	end

	-- Every column starts here and every one has the same floor, so "what fits"
	-- is one number rather than five.
	local top     = PAD
	local bottom  = h - PAD
	local tallest = 0
	local function used(y) if y > tallest then tallest = y end end

	local function place(region, x, y, width)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
		if width then region:SetWidth(width) end
	end

	-- identity ---------------------------------------------------------------
	do
		local x, cw = colX.identity, colW.identity
		local y = top

		place(content.title, x, y)
		content.chip:ClearAllPoints()
		content.chip:SetPoint("LEFT", content.title, "RIGHT", 10, 0)
		-- No close button. The vertical drawer has one because it covers a
		-- quarter of the screen edge-to-edge; this one is a strip along the
		-- bottom with the chevron on the rail an inch away.
		content.close:SetShown(false)
		y = y + HEADER_H

		place(content.news, x, y, cw)
		content.news:SetHeight(NEWS_H)
		self:SizeNewsBody()
		content.news.dot:SetShown(self:NewsUnread())
		y = y + NEWS_H + SECTION_GAP

		-- The micro row, and NO heading over it. The concept draws these as a
		-- single strip under the card, and the 20px a "MENU" label costs is the
		-- 20px that decides whether the strip fits above the panel's floor.
		--
		-- One row of however many the client offers, rather than a fixed four per
		-- row: at most eight are ever present (social and guild are mutually
		-- exclusive), and wrapping to a second row in a 240px panel would put it
		-- through the floor. A tenth entry added later makes the cells narrower,
		-- which is visible, rather than hiding one, which is not.
		local micro = self._microList or {}
		if content.microHead then content.microHead:Hide() end
		if #micro > 0 then
			local per   = #micro
			local cellW = cw / per
			for i, b in ipairs(micros) do
				if i <= per then
					b:SetSize(cellW, MICRO_CELL_H_FLAT)
					GridPlace(content, b, i, x, y, per, cellW, MICRO_CELL_H_FLAT, 0, 0)
					-- Glyph only. The name goes with the label's own row: eight
					-- of them across this column is about thirty pixels each,
					-- and "Character" came out as "Ch...". It is still on the
					-- tooltip, which is where a name that does not fit belongs.
					if b.name then b.name:Hide() end
					b:Show()
				else
					b:Hide()
				end
			end
			y = y + MICRO_CELL_H_FLAT
		end
		used(y)
	end

	-- WIDGETS ----------------------------------------------------------------
	do
		local x, cw = colX.widgets, colW.widgets
		local y = top
		local shownCards = 0
		for _, c in ipairs(cards) do if c:IsShown() then shownCards = shownCards + 1 end end

		if shownCards > 0 and content.widgetsHead then
			place(content.widgetsHead, x, y)
			y = y + SECTION_H
			-- TWO columns here, not the three the vertical panel defaults to.
			-- The setting is a count of columns in a panel a third of this one's
			-- width, and carrying it across gives six cards 100px wide with
			-- "14g 32s" wrapped in them.
			local cols = math.min(Cols("widgetColumns", 3), 2)
			local cardW = (cw - CARD_GAP * (cols - 1)) / cols

			-- Cut to the column's floor like every other grid here. The panel's
			-- own minimum height is built to fit all six, so this never bites
			-- today - but "never bites today" is how the vertical layout came to
			-- draw a section off the bottom of the drawer, and a grid that
			-- silently overflows is the one failure mode this file keeps having.
			local maxRows = math.max(0, math.floor((bottom - y + CARD_GAP) / (CARD_H + CARD_GAP)))
			local fit = math.min(shownCards, maxRows * cols)
			for i, card in ipairs(cards) do
				if i <= fit then
					card:SetWidth(cardW)
					GridPlace(content, card, i, x, y, cols, cardW, CARD_H, CARD_GAP, CARD_GAP)
					card:Show()
				elseif i <= shownCards then
					card:Hide()
				end
			end
			self._widgetsCut = shownCards - fit
			content.widgetsHead:SetText(Spaced("WIDGETS")
				.. (self._widgetsCut > 0 and ("   +" .. self._widgetsCut) or ""))
			if fit > 0 then y = y + RowsFor(fit, cols) * (CARD_H + CARD_GAP) - CARD_GAP end
		end
		used(y)
	end

	-- ADDONS -----------------------------------------------------------------
	do
		local x, cw = colX.addons, colW.addons
		local y = top
		local rows = self._addonRows or {}
		local cols = Cols("addonColumns", 2)
		local shown = 0

		if #rows > 0 and content.addonsHead then
			local headY = y
			place(content.addonsHead, x, y)
			y = y + SECTION_H

			-- Cut to the column's own floor, and scrollable for the rest, which
			-- is the vertical panel's rule and the quest tracker's before it.
			local maxRows  = math.max(0, math.floor((bottom - y + ROW_GAP) / (ROW_H + ROW_GAP)))
			shown = self:PlaceAddonRows(x, y, cw, cols, maxRows * cols, x + cw, headY)
			y = y + RowsFor(shown, cols) * (ROW_H + ROW_GAP) - ROW_GAP
		end
		used(y)
	end

	-- MAIL -------------------------------------------------------------------
	--
	-- Always, empty or not. The rows themselves carry the empty case - one quiet
	-- line reading "No unread mail" - so there is nothing to decide here beyond
	-- whether the section has been built yet.
	do
		local showMail = content.mailHead ~= nil and colX.mail ~= nil
		if showMail then
			local x, cw = colX.mail, colW.mail
			local y = top
			place(content.mailHead, x, y)
			content.mailHint:ClearAllPoints()
			content.mailHint:SetPoint("TOPRIGHT", content, "TOPLEFT", x + cw, -y)
			y = y + SECTION_H
			-- The count of rows DRAWN, not of senders: the empty line and the
			-- "we cannot say who from" line are each one row carrying no sender.
			local n = self._mailRowCount or 0
			for i, row in ipairs(mails) do
				if i <= n then
					row:SetWidth(cw)
					GridPlace(content, row, i, x, y, 1, cw, MAIL_ROW_H, 0, MAIL_ROW_GAP)
					-- SHOWN here, not left to RefreshMailRows. Positioning a
					-- region says nothing about whether it is visible, and the
					-- other layout hides these when it drops the section - so a
					-- drawer dragged to an edge after that came home with a mail
					-- heading over nothing. The same bug the MENU heading had.
					row:Show()
				else
					row:Hide()
				end
			end
			if n > 0 then y = y + n * (MAIL_ROW_H + MAIL_ROW_GAP) - MAIL_ROW_GAP end
			used(y)
		end
		if content.mailHead then content.mailHead:SetShown(showMail) end
		if content.mailHint then content.mailHint:SetShown(showMail) end
		if not showMail then for _, row in ipairs(mails) do row:Hide() end end
	end

	-- UI SETTINGS ------------------------------------------------------------
	do
		local x, cw = colX.settings, colW.settings
		local y = top
		local tiles = self._tileList or {}
		local cols  = Cols("tileColumns", 2)
		local shownTiles = 0

		if #tiles > 0 and content.tilesHead then
			place(content.tilesHead, x, y)
			y = y + SECTION_H
			local maxRows = math.max(0, math.floor((bottom - y + TILE_GAP) / (TILE_H + TILE_GAP)))
			local rowsFit = math.min(RowsFor(#tiles, cols), maxRows)
			shownTiles = math.min(#tiles, rowsFit * cols)

			local tw = (cw - TILE_GAP * (cols - 1)) / cols
			for i, tile in ipairs(tilesF) do
				if i <= shownTiles then
					tile:SetWidth(tw)
					self:ArrangeTile(tile, tw)
					GridPlace(content, tile, i, x, y, cols, tw, TILE_H, TILE_GAP, TILE_GAP)
					tile:Show()
				else
					tile:Hide()
				end
			end
			if rowsFit > 0 then y = y + rowsFit * (TILE_H + TILE_GAP) - TILE_GAP end
		else
			for _, tile in ipairs(tilesF) do tile:Hide() end
		end

		self._tilesCut = #tiles - shownTiles
		if content.tilesHead then
			content.tilesHead:SetText(Spaced("UI SETTINGS")
				.. (self._tilesCut > 0 and ("   +" .. self._tilesCut) or ""))
			content.tilesHead:SetShown(shownTiles > 0)
		end
		used(y)
	end

	-- NOW PLAYING ------------------------------------------------------------
	--
	-- The last column, which is the right-hand end of a flat drawer - the same
	-- place the foot of the vertical one is. It is the only column that can be
	-- absent, and HorizontalColumns is where that is decided.
	do
		local showNow = colX.nowplaying ~= nil and content.now ~= nil
		if showNow then
			local x, cw = colX.nowplaying, colW.nowplaying
			local y = top
			place(content.nowHead, x, y)
			content.nowHead:Show()
			y = y + SECTION_H
			place(content.now, x, y, cw)
			content.now:SetHeight(NowHeight())
			content.now:Show()
			y = y + NowHeight()
			used(y)
		else
			if content.nowHead then content.nowHead:Hide() end
			if content.now then content.now:Hide() end
		end
	end

	self._contentHeight = tallest + PAD
end

function TB:LayoutVertical()
	if not self.content or not self.panel then return end
	local content = self.content
	local w, h    = self.panel:GetWidth(), self.panel:GetHeight()
	local avail   = w - PAD * 2

	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", self.panel, "TOPLEFT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", self.panel, "BOTTOMRIGHT", 0, 0)

	-- Every section is optional at this point. LayoutContent runs from
	-- RefreshWidgets, which BuildContent calls before BuildTiles, BuildAddons
	-- and BuildMicro exist - so the first pass of the very first layout has
	-- three of the six sections still unbuilt. Guarded here rather than at each
	-- use, because "the table is not there yet" is one fact about when this runs
	-- and not six separate special cases.
	local micros = content.micro  or {}
	local cards  = content.cards  or {}
	local addons = content.addons or {}
	local tilesF = content.tiles  or {}
	local mails  = content.mail   or {}

	local function place(region, x, y, width)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
		if width then region:SetWidth(width) end
	end

	local y = PAD

	-- header ----------------------------------------------------------------
	place(content.title, PAD, y)
	content.chip:ClearAllPoints()
	content.chip:SetPoint("LEFT", content.title, "RIGHT", 10, 0)
	content.close:ClearAllPoints()
	content.close:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -y)
	content.close:SetShown(IsVertical(self:Dock()))
	y = y + HEADER_H

	-- what's new ------------------------------------------------------------
	place(content.news, PAD, y, avail)
	content.news:SetHeight(NEWS_H)
	self:SizeNewsBody()
	content.news.dot:SetShown(self:NewsUnread())
	y = y + NEWS_H + SECTION_GAP

	-- MENU (the micro row) ---------------------------------------------------
	local micro = self._microList or {}
	if #micro > 0 and content.microHead then
		place(content.microHead, PAD, y)
		-- Shown explicitly, because the FLAT layout hides it - the heading is
		-- 20px it has not got. Placing a region says nothing about whether it is
		-- visible, so a drawer dragged from the bottom back to a side came home
		-- with a nameless row of glyphs under the card.
		content.microHead:Show()
		y = y + SECTION_H
		-- GLYPH ONLY, the way the flat layout already draws them. The names were
		-- costing sixteen pixels a row for words the tooltip says better, and the
		-- drawer needed them for the mini-player at its foot. Nothing was lost
		-- that the flat panel had not already decided it could do without.
		local cellW = avail / MICRO_PER_ROW
		for i, b in ipairs(micros) do
			if i <= #micro then
				b:SetSize(cellW, MICRO_CELL_H_FLAT)
				GridPlace(content, b, i, PAD, y, MICRO_PER_ROW, cellW,
					MICRO_CELL_H_FLAT, 0, 0)
				if b.name then b.name:Hide() end
				b:Show()
			else
				b:Hide()
			end
		end
		y = y + RowsFor(#micro, MICRO_PER_ROW) * MICRO_CELL_H_FLAT + SECTION_GAP
	end

	-- WIDGETS ----------------------------------------------------------------
	local shownCards = 0
	for _, c in ipairs(cards) do if c:IsShown() then shownCards = shownCards + 1 end end
	if shownCards > 0 and content.widgetsHead then
		place(content.widgetsHead, PAD, y)
		-- Re-asserted, not left alone. The flat layout appends "+N" to this when
		-- it has to cut cards, and a heading is a piece of state like any other:
		-- docking back to a side with the count still on it reports a cut that
		-- the tall panel did not make.
		self._widgetsCut = 0
		content.widgetsHead:SetText(Spaced("WIDGETS"))
		y = y + SECTION_H
		local cols = Cols("widgetColumns", 3)
		local cw = (avail - CARD_GAP * (cols - 1)) / cols
		for i, card in ipairs(cards) do
			if i <= shownCards then
				card:SetWidth(cw)
				GridPlace(content, card, i, PAD, y, cols, cw, CARD_H, CARD_GAP, CARD_GAP)
			end
		end
		y = y + RowsFor(shownCards, cols) * (CARD_H + CARD_GAP) - CARD_GAP + SECTION_GAP
	end

	-- UI SETTINGS is laid out BEFORE the addon list even though it is drawn
	-- below it, because the addon list is the one section that gives way. Its
	-- height has to be known first or there is nothing to subtract.
	local tiles = self._tileList or {}
	local tileCols = Cols("tileColumns", 2)
	local tileRows = RowsFor(#tiles, tileCols)

	-- Both lists give way, and in this order: the addon list first, the settings
	-- tiles second. A drawer clamped small enough - a low screen at scale 1.0 -
	-- cannot fit the fixed sections plus every tile, and the first version drew
	-- the overflow off the bottom of the panel where nobody could reach it.
	--
	-- Cutting the addon list to nothing and stopping there was not enough: with
	-- zero addon rows the column still wanted 614 of a 506 panel. So the tiles
	-- are cut too, and both say what they dropped.
	-- MAIL is measured here too, for the same reason and before the same
	-- subtraction: it is drawn under the addon list, so the list can only be
	-- told how much room it has once this block's height is known.
	--
	-- It is NOT cut to fit. Three rows of 30 is the smallest fixed section on
	-- the panel, and a mail list that drops the sender you were looking for to
	-- make room for a settings tile has its priorities backwards.
	--
	-- And it is ALWAYS THERE, empty or not. It used to vanish when the box was
	-- empty, on the reasoning that a section reporting nothing is furniture.
	-- What that missed is that a section which comes and goes is one you go
	-- looking for and cannot find - which is exactly what happened - and that
	-- the whole panel below it shifting every time the postman calls is worse
	-- than one quiet line saying "No unread mail". The flat layout keeps its
	-- mail column on the same reasoning, so the two now agree.
	--
	-- The count is of rows DRAWN rather than of senders: an empty box and a
	-- "we cannot say who from" box are each one row carrying no sender at all,
	-- and reserving from the sender count draws a row nothing made room for.
	local mailEmpty = not self:MailState()
	local mailRows = self._mailRowCount or 0

	-- Measured ONCE and reused below, rather than written out twice. The
	-- reserved height and the height the rows are actually placed into have to
	-- agree, and two copies of an expression are two things that can drift -
	-- the failure being a section that reserves a row it never draws, or draws
	-- one it never reserved.
	local mailRowsH = (mailRows > 0)
		and (mailRows * (MAIL_ROW_H + MAIL_ROW_GAP) - MAIL_ROW_GAP) or 0
	local mailBlock = SECTION_H + mailRowsH + SECTION_GAP

	-- NOW PLAYING is fixed cost like mail, and is drawn BELOW everything - so
	-- like mail it has to be measured before the two lists that give way are
	-- told how much room they have. Reserved after the fact, it would be drawn
	-- through the floor of the panel by exactly its own height.
	local showNow = self:HasPlayer() and content.now ~= nil
	local nowBlock = showNow and (SECTION_H + NowHeight() + SECTION_GAP) or 0

	-- The addon section's own HEADER is fixed cost too, and it was missing from
	-- this sum. Its ROWS give way to nothing, which is what "the addon list
	-- gives way" means - but the heading and the gap under it are drawn whether
	-- there is one row or twenty, so the tiles were being handed room that the
	-- heading was always going to take. It overflowed by exactly SECTION_H the
	-- moment anything above got taller, which is how taller mail rows found it.
	local addonFixed = (#(self._addonRows or {}) > 0 and content.addonsHead)
		and (SECTION_H + SECTION_GAP) or 0

	local roomLeft = h - y - PAD - mailBlock - addonFixed - nowBlock

	-- The ONE case where the mail section gives way: the box is empty and the
	-- panel is too short to fit it and a single row of settings tiles.
	--
	-- "Mail is never cut" is right about mail you HAVE - a list that drops the
	-- sender you were looking for to make room for a toggle has its priorities
	-- backwards. It is not right about a line reading "No unread mail", which is
	-- the least informative thing on the panel and the obvious first thing to go
	-- when there is genuinely no room. Only bites on a very short screen at
	-- scale 1.0; every real drawer keeps it.
	local dropMail = false
	if mailEmpty and roomLeft < SECTION_H + TILE_H then
		dropMail = true
		mailBlock = 0
		roomLeft = h - y - PAD - addonFixed - nowBlock
	end

	local maxTileRows = math.max(0, math.floor((roomLeft - SECTION_H) / (TILE_H + TILE_GAP)))
	if tileRows > maxTileRows then tileRows = maxTileRows end
	local shownTiles = math.min(#tiles, tileRows * tileCols)
	self._tilesCut = #tiles - shownTiles

	local tileBlock = (shownTiles > 0)
		and (SECTION_H + tileRows * (TILE_H + TILE_GAP) - TILE_GAP) or 0

	-- ADDONS -----------------------------------------------------------------
	local rows = self._addonRows or {}
	local addonCols = Cols("addonColumns", 2)
	local shown = 0
	if #rows > 0 and content.addonsHead then
		local headY = y
		place(content.addonsHead, PAD, y)
		y = y + SECTION_H

		-- What is left after the settings block and the bottom padding. The list
		-- is CUT to fit rather than the panel being grown, and what did not fit
		-- is reachable by the wheel and said so - the quest tracker's rule, for
		-- the same reason: a list that silently drops the row you were looking
		-- for is worse than one that admits it ran out of room.
		local room = h - y - PAD - tileBlock - mailBlock - nowBlock - SECTION_GAP
		local maxRows = math.max(0, math.floor(room / (ROW_H + ROW_GAP)))
		shown = self:PlaceAddonRows(PAD, y, avail, addonCols,
			maxRows * addonCols, w - PAD, headY)

		y = y + RowsFor(shown, addonCols) * (ROW_H + ROW_GAP) - ROW_GAP + SECTION_GAP
	end

	-- MAIL -------------------------------------------------------------------
	--
	-- Always, empty or not - see the note by mailBlock above. The rows carry the
	-- empty case themselves, so the only questions left here are whether the
	-- section has been built yet and whether an empty one had to be dropped for
	-- room on a very short panel.
	local showMail = content.mailHead ~= nil and not dropMail
	if showMail then
		place(content.mailHead, PAD, y)
		content.mailHint:ClearAllPoints()
		content.mailHint:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -y)
		y = y + SECTION_H
		for i, row in ipairs(mails) do
			if i <= mailRows then
				row:SetWidth(avail)
				GridPlace(content, row, i, PAD, y, 1, avail, MAIL_ROW_H, 0, MAIL_ROW_GAP)
				-- Shown here rather than left to RefreshMailRows, for the same
				-- reason the flat layout does it: this pass hides them when it
				-- drops the section, so whoever draws next has to put them back.
				row:Show()
			else
				row:Hide()
			end
		end
		y = y + mailRowsH + SECTION_GAP
	end
	-- Driven by the SAME boolean the block above is. Two conditions that have
	-- to agree are two conditions that can stop agreeing, and the failure is a
	-- section header shown at whatever position it last had.
	if content.mailHead then content.mailHead:SetShown(showMail) end
	if content.mailHint then content.mailHint:SetShown(showMail) end
	if not showMail then for _, row in ipairs(mails) do row:Hide() end end

	-- UI SETTINGS ------------------------------------------------------------
	if shownTiles > 0 then
		if not content.tilesHead then return end
		place(content.tilesHead, PAD, y)
		content.tilesHead:SetText(Spaced("UI SETTINGS")
			.. (self._tilesCut > 0 and ("   +" .. self._tilesCut) or ""))
		y = y + SECTION_H
		local tw = (avail - TILE_GAP * (tileCols - 1)) / tileCols
		for i, tile in ipairs(tilesF) do
			if i <= shownTiles then
				tile:SetWidth(tw)
				self:ArrangeTile(tile, tw)
				GridPlace(content, tile, i, PAD, y, tileCols, tw, TILE_H, TILE_GAP, TILE_GAP)
				tile:Show()
			else
				tile:Hide()
			end
		end
		y = y + tileRows * (TILE_H + TILE_GAP) - TILE_GAP
	else
		for _, tile in ipairs(tilesF) do tile:Hide() end
	end
	if content.tilesHead then content.tilesHead:SetShown(shownTiles > 0) end

	-- NOW PLAYING ------------------------------------------------------------
	if showNow then
		y = y + SECTION_GAP
		place(content.nowHead, PAD, y)
		content.nowHead:Show()
		y = y + SECTION_H
		place(content.now, PAD, y, avail)
		content.now:SetHeight(NowHeight())
		content.now:Show()
		y = y + NowHeight()
	else
		if content.nowHead then content.nowHead:Hide() end
		if content.now then content.now:Hide() end
	end

	self._contentHeight = y + PAD
end

-- The four old per-section layout passes are gone. They are kept as no-ops
-- because Refresh* calls them, and because a reader looking for LayoutTiles
-- should find out where it went rather than find nothing.
function TB:LayoutTiles()  self:LayoutContent() end
function TB:LayoutAddons() self:LayoutContent() end
function TB:LayoutMicro()  self:LayoutContent() end
