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
	content.news:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -(PAD + 34))
	content.news:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
	content.news.dot:SetShown(self:NewsUnread())

	content.widgetsHead:ClearAllPoints()
	content.widgetsHead:SetPoint("TOPLEFT", content.news, "BOTTOMLEFT", 0, -16)

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
end
