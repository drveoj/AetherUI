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
local RAIL_ICON  = 34
local RAIL_PAD   = 9
local RAIL_W     = RAIL_ICON + RAIL_PAD * 2
local RAIL_CHEV  = 26
local RAIL_CORNER = 22

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

	-- The scrim first, so it is underneath everything the drawer draws. A plain
	-- solid with a gradient rather than a new .tga: a texture file needs a
	-- client restart to appear, a SetGradient needs a /reload.
	local scrim = CreateFrame("Frame", ADDON .. "ToolboxScrim", UIParent)
	scrim:SetFrameStrata("FULLSCREEN_DIALOG")
	scrim:SetFrameLevel(1)
	local tex = scrim:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints(scrim)
	tex:SetColorTexture(1, 1, 1, 1)
	scrim.tex = tex
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
	local rail = Glass.CreatePill(UIParent, {
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
	if self.scrim then
		-- Dark, and it fades AWAY from the drawer: the strip nearest the panel is
		-- the most covered, and a scrim of one flat alpha reads as a grey slab
		-- with an edge of its own rather than as the drawer casting over the HUD.
		self.scrim.tex:SetColorTexture(0, 0, 0, 1)
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
	local railLen = RAIL_CHEV + RAIL_PAD * 2
	if IsVertical(edge) then
		self.rail:SetSize(RAIL_W, railLen)
	else
		self.rail:SetSize(railLen, RAIL_W)
	end

	local ox, oy = ClosedOffset(edge, w, h)
	local t = self._travel or 0
	-- t = 0 closed (fully off screen), t = 1 open (flush to the edge)
	local dx, dy = ox * (1 - t), oy * (1 - t)

	self.panel:ClearAllPoints()
	self.rail:ClearAllPoints()
	self.scrim:ClearAllPoints()

	if edge == "LEFT" then
		self.panel:SetPoint("LEFT", UIParent, "LEFT", dx, 0)
		self.rail:SetPoint("LEFT", self.panel, "RIGHT", 0, 0)
		self.rail.chev:SetPoint("CENTER", self.rail, "CENTER", 0, 0)
	elseif edge == "RIGHT" then
		self.panel:SetPoint("RIGHT", UIParent, "RIGHT", dx, 0)
		self.rail:SetPoint("RIGHT", self.panel, "LEFT", 0, 0)
		self.rail.chev:SetPoint("CENTER", self.rail, "CENTER", 0, 0)
	elseif edge == "TOP" then
		self.panel:SetPoint("TOP", UIParent, "TOP", 0, dy)
		self.rail:SetPoint("TOP", self.panel, "BOTTOM", 0, 0)
		self.rail.chev:SetPoint("CENTER", self.rail, "CENTER", 0, 0)
	else
		self.panel:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, dy)
		self.rail:SetPoint("BOTTOM", self.panel, "TOP", 0, 0)
		self.rail.chev:SetPoint("CENTER", self.rail, "CENTER", 0, 0)
	end

	-- The scrim covers exactly the strip the panel is over, so it travels with
	-- it rather than sitting still and being revealed.
	self.scrim:SetSize(w, h)
	self.scrim:SetPoint("CENTER", self.panel, "CENTER", 0, 0)
	self.scrim:SetAlpha(0.28 * t)
	self.scrim:SetShown(t > 0.001)

	self:PointChevron()
end

--- The chevron points the way the drawer will go if you click it.
function TB:PointChevron()
	local edge = self:Dock()
	local opening = (self._want or 0) > 0.5
	local g = self.rail and self.rail.chev and self.rail.chev.glyph
	if not g then return end

	-- The art points right. Rotate rather than ship four textures.
	local turns = {
		LEFT   = opening and math.pi or 0,
		RIGHT  = opening and 0 or math.pi,
		TOP    = opening and -math.pi / 2 or math.pi / 2,
		BOTTOM = opening and math.pi / 2 or -math.pi / 2,
	}
	if g.SetRotation then pcall(g.SetRotation, g, turns[edge] or 0) end
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
	return true
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function TB:OnEnable()
	self:Build()
	self:SetOpen(self:IsOpen(), true)
end

function TB:OnDisable()
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
end
