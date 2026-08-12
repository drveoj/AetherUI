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

	-- Pins are claimed on the way in, or a rail restored from saved variables
	-- would draw nothing until somebody toggled a pin.
	for _, key in ipairs(self:Pinned()) do
		local e = A.Launchers and A.Launchers.byKey[key]
		if e then A.Launchers:Claim(e, self, true) end
	end
	self:LayoutRail()

	A.Launchers:OnChanged("toolbox", function()
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

	local chip = Glass.CreatePill(content, {})
	chip:SetHeight(18)
	local chipText = W.Text(chip, "tbChip", "CENTER")
	chipText:SetPoint("CENTER", chip, "CENTER", 0, 0)
	chipText:SetText("Aether UI " .. (A.version or "0.1.0"))
	chip:SetWidth((chipText:GetStringWidth() or 60) + 18)
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

--- Three columns, as the deck draws it in the vertical dock. The horizontal one
--  gets the same three: the cards are the same size either way, and six in a
--  row reads as a status bar rather than as a grid.
function TB:LayoutContent()
	if not self.content or not self.panel then return end
	local content = self.content
	local w = self.panel:GetWidth()

	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", self.panel, "TOPLEFT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", self.panel, "BOTTOMRIGHT", 0, 0)

	content.title:ClearAllPoints()
	content.title:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD)
	content.chip:ClearAllPoints()
	content.chip:SetPoint("LEFT", content.title, "RIGHT", 10, 0)
	content.close:ClearAllPoints()
	content.close:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -PAD)
	-- The deck only draws the close X on the vertical layout; the horizontal one
	-- has the chevron right beside it on the rail.
	content.close:SetShown(IsVertical(self:Dock()))

	content.news:ClearAllPoints()
	-- Below the micro row, which sits between the header and the card.
	content.news:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -(PAD + 30 + 26 + 14))
	content.news:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
	content.news.dot:SetShown(self:NewsUnread())

	content.widgetsHead:ClearAllPoints()
	content.widgetsHead:SetPoint("TOPLEFT", content.news, "BOTTOMLEFT", 0, -16)

	self:LayoutMicro()

	local cols = 3
	local avail = w - PAD * 2
	local cw = (avail - CARD_GAP * (cols - 1)) / cols
	for i, card in ipairs(content.cards) do
		if card:IsShown() then
			local r, c = math.floor((i - 1) / cols), (i - 1) % cols
			card:SetWidth(cw)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", content.widgetsHead, "BOTTOMLEFT",
				c * (cw + CARD_GAP), -(10 + r * (CARD_H + CARD_GAP)))
		end
	end

	self:LayoutTiles()
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

TB.TILES = {
	{ kind = "setting", key = "zen",      label = "Zen",
	  path = { "modules", "zen", "enabled" } },
	{ kind = "setting", key = "combat",   label = "Combat collapse",
	  path = { "modules", "questtracker", "combatCollapse" } },
	{ kind = "setting", key = "keybinds", label = "Keybind chips",
	  path = { "modules", "actionbars", "showKeybinds" } },
	-- A client setting rather than one of ours. Written directly and left
	-- written: a player who turns damage numbers off in this panel has made a
	-- choice, not lent us a CVar. Zen borrows and gives back because zen is
	-- TEMPORARY - it holds a value for as long as it is on screen and the player
	-- never asked for it. This is the opposite, and restoring it on disable
	-- would quietly undo something somebody deliberately did.
	{ kind = "cvar",    key = "damage",   label = "Damage numbers",
	  cvar = "floatingCombatTextCombatDamage" },
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

	if tile.kind == "cvar" then
		if not GetCVar then return false end
		local ok, v = pcall(GetCVar, tile.cvar)
		if not ok then return false end
		return v == "1" or v == 1 or v == true
	end

	return nil
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

	if tile.kind == "cvar" then
		if not SetCVar then return false end
		-- A CVar this client does not have throws rather than returning nil, so
		-- it is probed rather than fired blind - the same rule Zen follows for
		-- the nameplate and audio families.
		-- Probed by VALUE, not by whether the read threw. GetCVar answers nil for
		-- a name the client does not have - it does not error - so a pcall around
		-- it succeeds and tells you nothing. Only the nil says the CVar is
		-- missing, and SetCVar on a missing one is what the client logs.
		if not GetCVar then return false end
		local okRead, cur = pcall(GetCVar, tile.cvar)
		if not okRead or cur == nil then return false end
		if not pcall(SetCVar, tile.cvar, want and "1" or "0") then return false end
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
			local chip = Glass.CreatePill(tile, {})
			chip:SetSize(30, 30)
			chip:SetPoint("TOPLEFT", tile, "TOPLEFT", 12, -10)
			tile.chip = chip

			local icon = chip:CreateTexture(nil, "ARTWORK")
			icon:SetPoint("CENTER", chip, "CENTER", 0, 0)
			icon:SetSize(18, 18)
			tile.icon = icon

			tile.state = W.Text(tile, "tbLabel", "RIGHT")
			tile.state:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -12, -16)

			tile.name = W.Text(tile, "tbCardBody", "LEFT")
			tile.name:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 12, 10)

			tile:EnableMouse(true)
			tile:SetScript("OnMouseUp", function(self2)
				if self2.__tile then TB:ToggleTile(self2.__tile) end
			end)
			self.content.tiles[i] = tile
		end

		tile.__tile = t
		tile.name:SetText(t.label or t.key)

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
			tile.icon:SetShown(false)
			W.Color(tile.state, on and Palette.c.accent or Palette.c.textDim)
		end
		-- `btnFill` is the deck's opaque accent - already its own token because
		-- the deck asks for dark text on it, which is exactly the chip's "on".
		-- NOT an invented name: ApplySkin falls back to plain glass for a token
		-- it does not know, so a typo here would make On and Off identical and
		-- say nothing at all.
		tile.chip:ApplySkin(on and "btnFill" or "cardBg", on and "cardEdgeHi" or "cardEdge")
		tile:Show()
	end

	for i = #list + 1, #self.content.tiles do
		self.content.tiles[i]:Hide()
	end

	self:LayoutTiles()
end

function TB:LayoutTiles()
	if not self.content or not self.content.tiles or not self.content.tilesHead then return end
	local content = self.content
	local w = self.panel:GetWidth()

	-- Under the widget grid, which is where the deck puts it. The anchor is the
	-- LAST VISIBLE widget card rather than a computed row count, so the two
	-- sections cannot drift apart when the widget list changes length.
	local last
	for _, c in ipairs(content.cards) do
		if c:IsShown() then last = c end
	end

	content.tilesHead:ClearAllPoints()
	if last then
		content.tilesHead:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, 0)
		content.tilesHead:SetPoint("TOP", last, "BOTTOM", 0, -18)
	else
		content.tilesHead:SetPoint("TOPLEFT", content.widgetsHead, "BOTTOMLEFT", 0, -18)
	end

	local cols = 2
	local avail = w - PAD * 2
	local tw = (avail - TILE_GAP * (cols - 1)) / cols
	for i, tile in ipairs(content.tiles) do
		if tile:IsShown() then
			local r, c = math.floor((i - 1) / cols), (i - 1) % cols
			tile:SetWidth(tw)
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", content.tilesHead, "BOTTOMLEFT",
				c * (tw + TILE_GAP), -(10 + r * (TILE_H + TILE_GAP)))
		end
	end

	self:LayoutAddons()
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
function TB:AddonRows()
	local rows, seen = {}, {}
	local L = A.Launchers

	local api = C_AddOns or _G
	local count = (api.GetNumAddOns and api.GetNumAddOns()) or 0
	for i = 1, count do
		local name, title = api.GetAddOnInfo and api.GetAddOnInfo(i)
		local loaded = true
		if api.IsAddOnLoaded then loaded = api.IsAddOnLoaded(i) and true or false end
		if name and loaded then
			-- The launcher whose key matches the addon, if there is one. LDB
			-- names are the addon's choice and usually the addon's name, so this
			-- matches on both and settles for neither.
			local entry = L and (L.byKey[name] or L.byKey[title or ""])
			rows[#rows + 1] = {
				name  = name,
				label = (title and title ~= "" and title) or name,
				entry = entry,
			}
			seen[name] = true
			if entry then seen[entry.key] = true end
		end
	end

	-- Launchers whose addon we could not match by name still belong in the list;
	-- they are the actionable ones, which is more than most rows manage.
	if L then
		for entry in L:Iterate() do
			if not seen[entry.key] then
				rows[#rows + 1] = { name = entry.key, label = entry.label or entry.key, entry = entry }
			end
		end
	end

	table.sort(rows, function(x, y)
		-- Actionable first, then alphabetical. A list where half the rows do
		-- nothing reads better with the useful half at the top.
		local xa, ya = x.entry ~= nil, y.entry ~= nil
		if xa ~= ya then return xa end
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
			pcall(L.RawSetParent, b, self.rail)
			pcall(L.RawClearAllPoints, b)
			local off = RAIL_PAD + RAIL_CHEV + RAIL_PAD + (n - 1) * (RAIL_ICON + RAIL_PAD)
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

	self._railCount = n

	-- The rail grows to fit what is on it: the chevron, then one slot per pin.
	local len = RAIL_PAD + RAIL_CHEV + RAIL_PAD + n * (RAIL_ICON + RAIL_PAD)
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

			row.name = W.Text(row, "tbCardBody", "LEFT")
			row.name:SetPoint("LEFT", row.tile, "RIGHT", 8, 0)

			row.pin = CreateFrame("Button", nil, row)
			row.pin:SetSize(13, 13)
			row.pin:SetPoint("RIGHT", row, "RIGHT", 0, 0)
			row.pin.glyph = row.pin:CreateTexture(nil, "ARTWORK")
			row.pin.glyph:SetAllPoints(row.pin)
			row.pin.glyph:SetTexture(Media.texture.circleMask or Media.texture.ring)
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

--- Two columns, as the deck draws it. The list is CUT to what fits rather than
--  resizing the panel, and what did not fit is reported - a list that silently
--  drops the addon you were looking for is worse than one that admits it ran
--  out of room, which is the rule the quest tracker already follows.
function TB:LayoutAddons()
	if not self.content or not self.content.addons then return end
	local content = self.content
	local w = self.panel:GetWidth()

	local anchor
	for _, t in ipairs(content.tiles or {}) do
		if t:IsShown() then anchor = t end
	end
	anchor = anchor or content.widgetsHead

	content.addonsHead:ClearAllPoints()
	content.addonsHead:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, 0)
	content.addonsHead:SetPoint("TOP", anchor, "BOTTOM", 0, -18)
	content.addonsHint:ClearAllPoints()
	content.addonsHint:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
	content.addonsHint:SetPoint("TOP", content.addonsHead, "TOP", 0, 0)

	local cols = 2
	local avail = w - PAD * 2
	local rw = (avail - ROW_GAP * (cols - 1)) / cols

	-- How many rows there is actually room for, measured against the panel
	-- rather than guessed at.
	local top = content.addonsHead:GetBottom() or 0
	local floorY = content:GetBottom() or 0
	local room = math.max(0, top - floorY - 12)
	local maxRows = math.max(1, math.floor(room / (ROW_H + ROW_GAP)))
	local maxShown = maxRows * cols

	local shown = 0
	for i, row in ipairs(content.addons) do
		if row.__row and i <= maxShown and (self._addonRows and i <= #self._addonRows) then
			local r, c = math.floor((i - 1) / cols), (i - 1) % cols
			row:SetWidth(rw)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content.addonsHead, "BOTTOMLEFT",
				c * (rw + ROW_GAP), -(10 + r * (ROW_H + ROW_GAP)))
			row:Show()
			shown = shown + 1
		else
			row:Hide()
		end
	end

	local total = #(self._addonRows or {})
	self._addonsCut = math.max(0, total - shown)
	if self._addonsCut > 0 then
		content.addonsHint:SetText(total .. " installed \194\183 +"
			.. self._addonsCut .. " more")
	end
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

			b.chip = Glass.CreatePill(b, {})
			b.chip:SetAllPoints(b)

			-- No glyph art yet. The concept's icon language is lucide-style
			-- strokes and there is no such .tga in Media/Textures - and a new
			-- texture file needs a client RESTART rather than a reload, so it is
			-- a generator pass of its own. The initial is the honest stand-in
			-- and the tooltip carries the name, which is the half that matters
			-- for a control you use by memory.
			b.glyph = W.Text(b, "tbLabel", "CENTER")
			b.glyph:SetPoint("CENTER", b, "CENTER", 0, 0)

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
		b.glyph:SetText((m.label or "?"):sub(1, 1):upper())
		b.chip:ApplySkin("cardBg", "cardEdge")
		b:Show()
	end

	for i = #list + 1, #self.content.micro do
		self.content.micro[i]:Hide()
	end

	self:LayoutMicro()
end

--- A row under the header and above What's-new. It is chrome rather than
--  content, and putting it at the bottom means scrolling past the addon list to
--  reach the character sheet.
function TB:LayoutMicro()
	if not self.content or not self.content.micro then return end
	local content = self.content
	for i, b in ipairs(content.micro) do
		if b:IsShown() then
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", content, "TOPLEFT",
				PAD + (i - 1) * (MICRO_SIZE + MICRO_GAP), -(PAD + 30))
		end
	end
end
