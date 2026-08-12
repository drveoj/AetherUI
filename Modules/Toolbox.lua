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
	than its offset. Dragging the rail to re-dock is its own gesture, and it
	lands in a later layer.

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
	gg:SetSize(RAIL_ICON - 8, RAIL_ICON - 8)
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
	mg:SetSize(RAIL_ICON - 8, RAIL_ICON - 8)
	Media:SetIcon(mg, "mail")
	mail.glyph = mg
	mail:SetScript("OnClick", function() TB:Toggle() end)
	mail:SetScript("OnEnter", function(self2) TB:MailTooltip(self2) end)
	mail:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	rail.mail = mail

	self._travel = self:IsOpen() and 1 or 0
	self._want   = self._travel

	self:Layout()
	self:ApplySkin()
end

function TB:ApplySkin()
	if not self.panel then return end
	self.panel:ApplySkin()
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
	return math.min(PANEL_H_W, sw * (PANEL_H_W / DECK_W)),
	       math.min(PANEL_H_H, sh * (PANEL_H_H / DECK_H))
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
	if vertical then
		self.rail.chev:SetPoint("TOP", self.rail, "TOP", 0, -RAIL_PAD)
		self.rail.gear:SetPoint("BOTTOM", self.rail, "BOTTOM", 0, RAIL_PAD)
		self.rail.mail:SetPoint("BOTTOM", self.rail.gear, "TOP", 0, RAIL_PAD)
	else
		self.rail.chev:SetPoint("LEFT", self.rail, "LEFT", RAIL_PAD, 0)
		self.rail.gear:SetPoint("RIGHT", self.rail, "RIGHT", -RAIL_PAD, 0)
		self.rail.mail:SetPoint("RIGHT", self.rail.gear, "LEFT", -RAIL_PAD, 0)
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
	local turns
	if edge == "LEFT" then
		turns = open and CHEV_LEFT or CHEV_RIGHT
	elseif edge == "RIGHT" then
		turns = open and CHEV_RIGHT or CHEV_LEFT
	elseif edge == "TOP" then
		turns = open and CHEV_UP or CHEV_DOWN
	else
		turns = open and CHEV_DOWN or CHEV_UP
	end

	self._chevronFacing = turns
	if g.SetRotation then pcall(g.SetRotation, g, turns) end
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
	if open then self:RefreshWidgets() end

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
	self:LayoutRail()
	return true
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
	for _, ev in ipairs({ "UPDATE_PENDING_MAIL", "MAIL_INBOX_UPDATE",
		"MAIL_CLOSED", "PLAYER_ENTERING_WORLD" }) do
		A:RegisterEvent(self, ev, function() TB:RefreshMail() end)
	end
	self:RefreshMail()

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
	self:SetPolling(false)
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
	{ key = "Gold",       label = "Gold",       events = { "PLAYER_MONEY" } },
	{ key = "BagSpace",   label = "Bag space",  events = { "BAG_UPDATE", "PLAYER_ENTERING_WORLD" } },
	{ key = "Durability", label = "Durability", events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_ENTERING_WORLD" } },
	{ key = "XPHour",     label = "XP / hr",    events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP" } },
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

--- `has` and the senders the client knows about, as a fresh list every time.
--
--  Read at call time, never cached: the senders change under us on
--  UPDATE_PENDING_MAIL and a stale list is worse than no list.
function TB:MailState()
	local has = HasNewMail and HasNewMail() and true or false
	local senders = {}
	if has and GetLatestThreeSenders then
		-- pcall because this is one of the few calls that can be answered by a
		-- client that has not finished logging in yet.
		local ok, a, b, c = pcall(GetLatestThreeSenders)
		if ok then
			for _, s in ipairs({ a, b, c }) do
				if type(s) == "string" and s ~= "" then senders[#senders + 1] = s end
			end
		end
	end
	return has, senders
end

--- The count for the chip, or nil when there is nothing honest to show.
function TB:MailCount()
	local has, senders = self:MailState()
	if not has or #senders == 0 then return nil end
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

TB.NEWS_VERSION = "0.1.0"
TB.NEWS = "The Toolbox has arrived: a drawer that docks to any screen edge, with"
	.. " your addon launchers on the rail beside it."

function TB:NewsUnread()
	local c = Char()
	return not (c and c.newsSeen == self.NEWS_VERSION)
end

function TB:MarkNewsRead()
	local c = Char()
	if c then c.newsSeen = self.NEWS_VERSION end
	if self.content and self.content.news then
		self.content.news.dot:SetShown(self:NewsUnread())
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
	chipText:SetText("v" .. (A.version or "0.1.0"))
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
		local c = Palette.c.btnFillText
		spark:SetVertexColor(c[1], c[2], c[3], 1)
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
	body:SetPoint("RIGHT", card, "RIGHT", -14, 0)
	body:SetJustifyV("TOP")
	body:SetText(self.NEWS or "")
	card.body = body

	card:EnableMouse(true)
	card:SetScript("OnMouseUp", function() TB:MarkNewsRead() end)
	content.news = card

	local head = W.Text(content, "tbSection", "LEFT")
	head:SetText(Spaced("WIDGETS"))
	content.widgetsHead = head

	content.cards = {}
	self:RefreshWidgets()
	self:BuildMail()
	self:BuildTiles()
	self:BuildAddons()
	self:BuildMicro()
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

	{ kind = "setting", key = "combat", label = "Combat collapse",
	  path = { "modules", "questtracker", "combatCollapse" },
	  tip = "Collapses the quest tracker to its title while you are fighting,"
	     .. " and opens it again when you are not." },

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

-- ---------------------------------------------------------------------------
-- the MAIL section
-- ---------------------------------------------------------------------------

local MAIL_ROW_H, MAIL_ROW_GAP = 24, 4

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
	local has, senders = self:MailState()
	self._mailSenders = senders

	for i = 1, self.MAIL_ROWS do
		local row = self.content.mail[i]
		if not row then
			row = CreateFrame("Frame", nil, self.content)
			row:SetHeight(MAIL_ROW_H)

			local dot = row:CreateTexture(nil, "ARTWORK")
			dot:SetSize(12, 12)
			dot:SetPoint("LEFT", row, "LEFT", 2, 0)
			Media:SetIcon(dot, "mailfull")
			row.dot = dot

			row.name = W.Text(row, "tbCardBody", "LEFT")
			row.name:SetPoint("LEFT", dot, "RIGHT", 8, 0)
			self.content.mail[i] = row
		end
		local who = senders[i]
		row.name:SetText(who or "")
		row:SetShown(who ~= nil)
	end

	-- "You have mail but we cannot say from whom" is a real state - auction
	-- house and NPC mail arrives with no name on it - so the section still
	-- appears, carrying the client's own wording instead of a list.
	if self.content.mailHint then
		if not has then
			self.content.mailHint:SetText("")
		elseif #senders == 0 then
			self.content.mailHint:SetText(_G.HAVE_MAIL or "New mail")
		else
			self.content.mailHint:SetText(#senders
				.. (#senders >= self.MAIL_ROWS and "+" or ""))
		end
	end
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
			chip:SetPoint("TOPLEFT", tile, "TOPLEFT", 12, -10)
			chip.label:Hide()
			tile.chip = chip

			local icon = chip:CreateTexture(nil, "OVERLAY")
			icon:SetPoint("CENTER", chip, "CENTER", 0, 0)
			icon:SetSize(17, 17)
			tile.icon = icon

			tile.state = W.Text(tile, "tbLabel", "RIGHT")
			tile.state:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -12, -16)

			tile.name = W.Text(tile, "tbCardBody", "LEFT")
			tile.name:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 12, 10)

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
local NEWS_H     = 84
local SECTION_H  = 20      -- a section label and the gap under it
local SECTION_GAP = 14     -- between one section's last row and the next label
local MICRO_CELL_H = 46
local MICRO_PER_ROW = 4

local function Cols(key, fallback)
	return math.max(1, tonumber(A.Config:Module("toolbox")[key]) or fallback)
end

--- Rows of `n` items at `per` per row.
local function RowsFor(n, per)
	return math.ceil(math.max(0, n) / math.max(1, per))
end

function TB:LayoutContent()
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
	content.news.dot:SetShown(self:NewsUnread())
	y = y + NEWS_H + SECTION_GAP

	-- MENU (the micro row) ---------------------------------------------------
	local micro = self._microList or {}
	if #micro > 0 and content.microHead then
		place(content.microHead, PAD, y)
		y = y + SECTION_H
		local cellW = avail / MICRO_PER_ROW
		for i, b in ipairs(micros) do
			if i <= #micro then
				local r, c = math.floor((i - 1) / MICRO_PER_ROW), (i - 1) % MICRO_PER_ROW
				b:ClearAllPoints()
				b:SetSize(cellW, MICRO_CELL_H)
				b:SetPoint("TOPLEFT", content, "TOPLEFT",
					PAD + c * cellW, -(y + r * MICRO_CELL_H))
				b:Show()
			else
				b:Hide()
			end
		end
		y = y + RowsFor(#micro, MICRO_PER_ROW) * MICRO_CELL_H + SECTION_GAP
	end

	-- WIDGETS ----------------------------------------------------------------
	local shownCards = 0
	for _, c in ipairs(cards) do if c:IsShown() then shownCards = shownCards + 1 end end
	if shownCards > 0 and content.widgetsHead then
		place(content.widgetsHead, PAD, y)
		y = y + SECTION_H
		local cols = Cols("widgetColumns", 3)
		local cw = (avail - CARD_GAP * (cols - 1)) / cols
		for i, card in ipairs(cards) do
			if i <= shownCards then
				local r, c = math.floor((i - 1) / cols), (i - 1) % cols
				card:ClearAllPoints()
				card:SetWidth(cw)
				card:SetPoint("TOPLEFT", content, "TOPLEFT",
					PAD + c * (cw + CARD_GAP), -(y + r * (CARD_H + CARD_GAP)))
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
	-- It is NOT cut to fit. Three rows of 24 is the smallest fixed section on
	-- the panel, and a mail list that drops the sender you were looking for to
	-- make room for a settings tile has its priorities backwards.
	local has = self:MailState()
	local mailRows = has and #(self._mailSenders or {}) or 0

	-- Measured ONCE and reused below, rather than written out twice. The
	-- reserved height and the height the rows are actually placed into have to
	-- agree, and two copies of an expression are two things that can drift -
	-- the failure being a section that reserves a row it never draws, or draws
	-- one it never reserved.
	--
	-- Zero rows costs nothing beyond the heading, because the "you have mail
	-- but we cannot say from whom" wording is the HINT, which sits on the
	-- heading's own line at its right-hand end.
	local mailRowsH = (mailRows > 0)
		and (mailRows * (MAIL_ROW_H + MAIL_ROW_GAP) - MAIL_ROW_GAP) or 0
	local mailBlock = has and (SECTION_H + mailRowsH + SECTION_GAP) or 0

	local roomLeft = h - y - PAD - mailBlock
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
		place(content.addonsHead, PAD, y)
		content.addonsHint:ClearAllPoints()
		content.addonsHint:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -y)
		y = y + SECTION_H

		-- What is left after the settings block and the bottom padding. The list
		-- is CUT to fit rather than the panel being grown, and what did not fit
		-- is reported - the quest tracker's rule, for the same reason: a list
		-- that silently drops the row you were looking for is worse than one
		-- that admits it ran out of room.
		local room = h - y - PAD - tileBlock - mailBlock - SECTION_GAP
		local maxRows = math.max(0, math.floor(room / (ROW_H + ROW_GAP)))
		local maxShown = maxRows * addonCols

		local rw = (avail - ROW_GAP * (addonCols - 1)) / addonCols
		for i, row in ipairs(addons) do
			if i <= #rows and i <= maxShown then
				local r, c = math.floor((i - 1) / addonCols), (i - 1) % addonCols
				row:ClearAllPoints()
				row:SetWidth(rw)
				row:SetPoint("TOPLEFT", content, "TOPLEFT",
					PAD + c * (rw + ROW_GAP), -(y + r * (ROW_H + ROW_GAP)))
				row:Show()
				shown = shown + 1
			else
				row:Hide()
			end
		end

		self._addonsCut = math.max(0, #rows - shown)
		content.addonsHint:SetText(self._addonsCut > 0
			and (#rows .. " \194\183 +" .. self._addonsCut .. " more")
			or (#rows .. " with a launcher"))

		y = y + RowsFor(shown, addonCols) * (ROW_H + ROW_GAP) - ROW_GAP + SECTION_GAP
	end

	-- MAIL -------------------------------------------------------------------
	--
	-- Only when there IS mail. An empty section every time you open the drawer
	-- is a row of furniture reporting nothing; the rail's envelope is the thing
	-- that is always there, and it says "empty" by being empty.
	local showMail = has and content.mailHead ~= nil
	if showMail then
		place(content.mailHead, PAD, y)
		content.mailHint:ClearAllPoints()
		content.mailHint:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -y)
		y = y + SECTION_H
		for i, row in ipairs(mails) do
			row:ClearAllPoints()
			row:SetWidth(avail)
			row:SetPoint("TOPLEFT", content, "TOPLEFT",
				PAD, -(y + (i - 1) * (MAIL_ROW_H + MAIL_ROW_GAP)))
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
				local r, c = math.floor((i - 1) / tileCols), (i - 1) % tileCols
				tile:ClearAllPoints()
				tile:SetWidth(tw)
				tile:SetPoint("TOPLEFT", content, "TOPLEFT",
					PAD + c * (tw + TILE_GAP), -(y + r * (TILE_H + TILE_GAP)))
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

	self._contentHeight = y + PAD
end

-- The four old per-section layout passes are gone. They are kept as no-ops
-- because Refresh* calls them, and because a reader looking for LayoutTiles
-- should find out where it went rather than find nothing.
function TB:LayoutTiles()  self:LayoutContent() end
function TB:LayoutAddons() self:LayoutContent() end
function TB:LayoutMicro()  self:LayoutContent() end
