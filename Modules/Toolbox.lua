--[[--------------------------------------------------------------------------
	Lattice :: Toolbox

	The left trunk (Lattice 5b and 6a): a strand down the screen edge from a
	Cell glyph, a node per section - Menu, Widgets, Addons, Settings, What's
	new - each opening its own branch panel beside it, and the pinned addons
	hanging below the last node. It replaced the drawer and its rail; what was
	in the drawer carries over a branch at a time, with the contents, scroll
	rules and settings it had (README "Supersedes").

	THE GLYPH AT THE TOP is the way to the settings, as the rail's mark was.

	IT DOCKS LEFT OR RIGHT, and the World trunk takes the other side (Joe,
	2026-10-07, decision 4c): docked right, the minimap is mirrored to the
	left. A character docked top or bottom under the drawer comes back on the
	left. In unlock, drag the glyph to the other half of the screen to swap.
	Per character, as the drawer's edge was.

	IN A FIGHT the trunk keeps its nodes, drops its labels and closes the open
	branch (README "Two energies for trunks").

	WHAT IS NOT HERE ANY MORE: mail and the music player, which are World
	trunk nodes (Core/Mail.lua, Modules/IFEC/Node.lua).
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = A.L
local TB = A:NewModule("toolbox")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- Board 5b and 6a at 1920 x 1080, in HUD units: the glyph's centre 40 in
-- from the dock edge and 300 down, 30 across.
local EDGE_X, TOP_Y, ROOT = 40, 300, 30
-- The board's first node is 72 under the glyph's centre: the strand starts
-- 12 under the glyph rather than the World trunk's 30 under its pill.
local CAP_GAP = 12
-- Pinned addons: 24 px tiles, 8 apart, under the last node.
local PIN, PIN_STEP = 24, 32
-- Inside a branch panel.
local PAD, HEAD_H = 16, 26

local SIDES = { LEFT = true, RIGHT = true }

local function Trunk() return A.Trunk:Get("toolbox") end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

local function Char()
	if not A.db or not A.db.char then return nil end
	A.db.char.toolbox = A.db.char.toolbox or {}
	local t = A.db.char.toolbox
	-- Top and bottom were the drawer's; the trunk docks left or right.
	if not SIDES[t.docked] then t.docked = "LEFT" end
	return t
end

function TB:Dock()
	local c = Char()
	return (c and c.docked) or "LEFT"
end

local function Cols(key, fallback)
	return math.max(1, tonumber(A.Config:Module("toolbox")[key]) or fallback)
end

local function RowsFor(n, per)
	return math.ceil(math.max(0, n) / math.max(1, per))
end

--- Place the i-th frame of a grid whose top-left is (x, y) in `parent`, y down.
local function GridPlace(parent, frame, i, x, y, cols, cellW, cellH, gapX, gapY)
	local r, c = math.floor((i - 1) / cols), (i - 1) % cols
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT",
		x + c * (cellW + (gapX or 0)), -(y + r * (cellH + (gapY or 0))))
end

-- ---------------------------------------------------------------------------
-- the glyph and the trunk
-- ---------------------------------------------------------------------------

function TB:BuildRoot()
	if self.root then return self.root end
	local r = CreateFrame("Button", ADDON .. "ToolboxRoot", UIParent)
	r:SetSize(ROOT, ROOT)
	r:SetFrameStrata("MEDIUM")
	r:SetClampedToScreen(true)
	r.glyph = r:CreateTexture(nil, "ARTWORK")
	r.glyph:SetAllPoints(r)
	r.glyph:SetTexture(Media.texture.icon)
	r:RegisterForClicks("LeftButtonUp")
	r:RegisterForDrag("LeftButton")
	r:SetScript("OnClick", function(self2)
		if self2.__dragged then self2.__dragged = nil return end
		if A.Options and A.Options.Open then A.Options:Open() end
	end)
	r:SetScript("OnEnter", function(self2)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
		GameTooltip:SetText(L.toolbox.build.aetherui_settings)
		if A.Movers and A.Movers.unlocked then
			GameTooltip:AddLine(L.toolbox.root.swap, 0.8, 0.8, 0.85, true)
		end
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	-- In unlock, a drag to the other half of the screen swaps the trunks.
	r:SetScript("OnDragStart", function(self2)
		if not (A.Movers and A.Movers.unlocked) then return end
		if InCombatLockdown() then
			A:Print(A.Bad(L.toolbox.root.combat))
			return
		end
		self2.__dragging = true
	end)
	r:SetScript("OnDragStop", function(self2)
		if not self2.__dragging then return end
		self2.__dragging = nil
		self2.__dragged = true
		local us = UIParent:GetEffectiveScale() or 1
		local mx = GetCursorPosition()
		TB:DropAt((mx or 0) / us)
	end)
	self.root = r
	return r
end

--- A drag let go at `x` (UIParent units): the side of the screen it is on.
function TB:DropAt(x)
	local side = (x > (UIParent:GetWidth() or 0) / 2) and "RIGHT" or "LEFT"
	if side == self:Dock() then return false end
	if not self:SetDock(side) then return false end
	A:Print(A.F(L.common.toolbox_docked_s, A.Val(side:lower())))
	return true
end

function TB:PlaceRoot()
	local r = self:BuildRoot()
	r:SetScale(A.db.profile.scale or 1)
	r:ClearAllPoints()
	local left = self:Dock() == "LEFT"
	r:SetPoint("CENTER", UIParent, left and "TOPLEFT" or "TOPRIGHT",
		left and EDGE_X or -EDGE_X, -TOP_Y)
	r:Show()
	local t = Trunk()
	t.capGap = CAP_GAP
	t:SetRoot(r)
end

--- Dock to LEFT or RIGHT. The World trunk takes the other side: a minimap on
--  this side is mirrored across. Refused in combat, where the minimap's place
--  is not ours to change.
function TB:SetDock(edge)
	edge = edge and tostring(edge):upper()
	if not SIDES[edge] or InCombatLockdown() then return false end
	local c = Char()
	if c then c.docked = edge end
	self:CloseAll()
	self:PlaceRoot()
	local MMm = A:GetModule("minimap")
	if MMm and MMm.enabled and MMm.frame and A.Movers and A.Movers.PointAt then
		local x = A.Movers.PointAt(MMm.frame, "CENTER")
		local onLeft = x and x < (UIParent:GetWidth() or 0) / 2
		if x and ((edge == "LEFT") == onLeft) then A.Movers:Mirror("minimap") end
	end
	self:LayoutPins()
	return true
end

-- ---------------------------------------------------------------------------
-- branches
-- ---------------------------------------------------------------------------

TB.BRANCHES = {
	{ key = "menu",     icon = "menu",     order = 100, width = 300 },
	{ key = "widgets",  icon = "widgets",  order = 200, width = 360 },
	{ key = "addons",   icon = "addons",   order = 300, width = 360 },
	{ key = "settings", icon = "gear",     order = 400, width = 300 },
	{ key = "news",     icon = "whatsnew", order = 500, width = 320 },
}

local BUILD = {}   -- key -> function(panel), filled in below
local FILL = {}    -- key -> function(panel), lays the branch out and sizes it

-- Spelled out, so the phrase check can see every key asked for.
local LABELS = {
	menu = L.toolbox.node.menu, widgets = L.toolbox.node.widgets,
	addons = L.toolbox.node.addons, settings = L.toolbox.node.settings,
	news = L.common.what_s_new,
}

local function Label(key) return LABELS[key] end

function TB:Panel(key)
	self.panels = self.panels or {}
	local p = self.panels[key]
	if p then return p end
	local spec
	for _, b in ipairs(self.BRANCHES) do if b.key == key then spec = b end end
	if not spec then return nil end
	p = Trunk():Branch("Toolbox" .. key:gsub("^%l", string.upper), spec.width)
	p.key = key
	p.head = A.Trunk.Head(p)
	p.head:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -PAD)
	p.head:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -PAD)
	p.head:Set(Label(key), "")
	if BUILD[key] then BUILD[key](self, p) end
	self.panels[key] = p
	return p
end

function TB:IsBranchOpen(key)
	local p = self.panels and self.panels[key]
	return p and p:IsShown() and true or false
end

--- The branch that is open, or nil.
function TB:OpenKey()
	for _, b in ipairs(self.BRANCHES) do
		if self:IsBranchOpen(b.key) then return b.key end
	end
	return nil
end

function TB:IsOpen() return self:OpenKey() ~= nil end

function TB:Fill(key)
	local p = self.panels and self.panels[key]
	if p and FILL[key] then FILL[key](self, p) end
end

function TB:OpenBranch(key)
	local p = self:Panel(key)
	if not p then return false end
	-- Every value read again on opening: one not available at login, or whose
	-- event we have not thought of, is right by the time it is seen.
	if key == "widgets" then self:RefreshProviders() end
	if key == "addons" then self._addonRows = self:AddonRows() end
	self:Fill(key)
	if not Trunk():Place(key, p) then return false end
	p:Show()
	if key == "news" then self:MarkNewsRead() end
	if key == "widgets" then self:SetPolling(true) end
	return true
end

function TB:CloseBranch(key)
	local p = self.panels and self.panels[key]
	if p then p:Hide() end
end

function TB:CloseAll()
	for _, b in ipairs(self.BRANCHES) do self:CloseBranch(b.key) end
end

--- Open a branch (Menu if none is named), or close them all. One at a time.
function TB:SetOpen(open, _, key)
	if not open then return self:CloseAll() end
	key = key or "menu"
	if self:IsBranchOpen(key) then return end
	Trunk():Toggle(key)
end

function TB:Toggle(key)
	Trunk():Toggle(key or self:OpenKey() or "menu")
end

function TB:AddNodes()
	local t = Trunk()
	for _, b in ipairs(self.BRANCHES) do
		local key = b.key
		t:AddNode(key, {
			icon = b.icon, label = Label(key), order = b.order,
			transient = true,
			available = function() return TB.enabled and true or false end,
			isOpen = function() return TB:IsBranchOpen(key) end,
			open = function() TB:OpenBranch(key) end,
			close = function() TB:CloseBranch(key) end,
			badge = key == "news" and function() return TB:NewsUnread() end or nil,
		})
	end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

--- Latency and framerate cannot be event-driven: polled while the Widgets
--  branch is open, and only then.
local POLL_EVERY = 1.0

function TB:SetPolling(on)
	if on and not self._polling then
		self._polling = true
		-- Due at once, so the first numbers seen are fresh.
		self._pollAccum = POLL_EVERY
		A:RegisterTicker(self._pollToken, function(_, dt)
			TB._pollAccum = (TB._pollAccum or 0) + dt
			if TB._pollAccum < POLL_EVERY then return end
			TB._pollAccum = 0
			TB:RefreshProviders("Latency")
			TB:RefreshProviders("FPS")
			TB:RefreshWidgets()
		end)
	elseif not on and self._polling then
		self._polling = nil
		A:UnregisterTicker(self._pollToken)
	end
end

function TB:OnEnable()
	self._pollToken = self._pollToken or {}
	self._menuToken = self._menuToken or {}
	self:BuildRoot()
	-- The glyph breathes with the HUD; the trunk's frame, and the branches and
	-- pins on it, are registered by the trunk.
	if A.Fader then A.Fader:Register(self.root, {}) end
	self:AddNodes()
	self:PlaceRoot()
	self:PublishWidgets()

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

	-- Ours is a display too: a third party writing to its own object updates
	-- the Widgets branch with no wiring at all.
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if ldb and ldb.RegisterCallback and not self._ldbHooked then
		self._ldbHooked = true
		pcall(ldb.RegisterCallback, self, "LibDataBroker_AttributeChanged",
			function() TB:RefreshWidgets() end)
	end

	A.Launchers:StartScanning({ [self.root] = true, [Trunk():Frame()] = true })
	self:ClaimPins()
	self:LayoutPins()

	-- The Talents door appears at level 10, and a character past it logs in
	-- with no level-up to fire.
	for _, ev in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
		A:RegisterEvent(self, ev, function() TB:RefreshMicro() end)
	end

	-- The other energy: nodes only in a fight.
	A:RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() Trunk():SetQuiet(true) end)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function() Trunk():SetQuiet(false) end)

	-- "Unlock frames" reads the movers live, so it is redrawn when they change.
	if A.Movers then
		A.Movers:OnLockChanged("toolbox", function() TB:RefreshTiles() end)
	end

	A.Launchers:OnChanged("toolbox", function()
		-- Re-claimed on every change: a pinned addon's button may arrive after
		-- login, and claiming once would forget the pin.
		TB:ClaimPins()
		TB:RefreshAddons()
		TB:LayoutPins()
	end)
end

function TB:OnDisable()
	self:CloseAll()
	self:SetPolling(false)
	if A.Movers and A.Movers.watchers then A.Movers.watchers.toolbox = nil end
	if self.root then
		if A.Fader then A.Fader:Unregister(self.root) end
		self.root:Hide()
	end
	Trunk():SetRoot(nil)
end

function TB:OnSkinChanged()
	for _, p in pairs(self.panels or {}) do
		A.Trunk.SkinBranch(p)
		p.head:Paint()
	end
	local key = self:OpenKey()
	if key then self:Fill(key) end
	Trunk():Paint()
end

function TB:OnConfigChanged()
	if not self.enabled then return end
	self:PlaceRoot()
	local key = self:OpenKey()
	if key then
		self:Fill(key)
		Trunk():Place(key, self.panels[key])
	end
	self:LayoutPins()
end

-- ---------------------------------------------------------------------------
-- the widgets, published rather than drawn
--
-- Ours are LDB `data source` objects, and the Widgets branch draws whatever
-- data sources the player has chosen - ours first. So anyone can write a
-- widget in ten lines, and our numbers show in Titan, Bazooka and
-- ChocolateBar for free.
-- ---------------------------------------------------------------------------

local PREFIX = "AetherUI_"

--- Our six. Latency and FPS are polled; the rest follow their events, and
--  every one has PLAYER_ENTERING_WORLD so it is right at login.
TB.PROVIDERS = {
	{ key = "Gold",       label = "Gold",
	  events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" } },
	{ key = "BagSpace",   label = L.toolbox.on_config_changed.bag_space,  events = { "BAG_UPDATE", "PLAYER_ENTERING_WORLD" } },
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

--- The WORST slot, not the mean: the number exists to send you to a vendor.
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

-- XP/hr has no API: tracked over the session.
TB._xp = { gained = 0, from = nil, last = nil }

--- A level-up resets the bar, so the gain across it is (max - before) + after.
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

-- Under a minute there is no rate, only a big number from a short window.
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

--- Register the six. A published name is a contract with whoever displays it.
function TB:PublishWidgets()
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if not ldb or self._published then return end
	self._published = {}
	for _, p in ipairs(self.PROVIDERS) do
		local name = PREFIX .. p.key
		local obj  = ldb:GetDataObjectByName(name)
		if not obj then
			obj = ldb:NewDataObject(name, {
				type = "data source", label = p.label, text = "—", value = "—",
			})
		end
		self._published[p.key] = obj
	end
	self:RefreshProviders()
end

--- Recompute ours and write them back, only on a change: each assignment
--  fires the library's callback and a display redraws on it.
function TB:RefreshProviders(only)
	if not self._published then return end
	for _, p in ipairs(self.PROVIDERS) do
		if not only or only == p.key then
			local obj = self._published[p.key]
			local fn  = self.VALUES[p.key]
			if obj and fn then
				local ok, v = pcall(fn)
				local text = (ok and v) or "—"
				if obj.value ~= text then
					obj.value = text
					obj.text  = text
				end
			end
		end
	end
end

local EMDASH = "\226\128\148"

--- A data source as a value and a label. Render what is given - a third
--  party's `text` with colour escapes in it is drawn as it is.
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
	local small = obj.label
	if small == nil or small == "" then small = name end
	return big, tostring(small)
end

--- Which data sources the Widgets branch shows: ours by default, a list so a
--  third party's can be added and the order is the player's.
function TB:WidgetList()
	local c = Char()
	if c and type(c.widgets) == "table" and #c.widgets > 0 then return c.widgets end
	local out = {}
	for _, p in ipairs(self.PROVIDERS) do out[#out + 1] = PREFIX .. p.key end
	return out
end

-- ---------------------------------------------------------------------------
-- the Widgets branch: readings on strands
--
-- README "Panel vocabulary": a reading is a 7 px hollow diamond on a 1 px
-- strand, the value above it and the label below.
-- ---------------------------------------------------------------------------

local READ_H, READ_GAP_X, READ_GAP_Y = 50, 14, 10

BUILD.widgets = function(self, p)
	p.cells = {}
	p:HookScript("OnHide", function() TB:SetPolling(false) end)
end

FILL.widgets = function(self, p)
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	local list = self:WidgetList()
	local cols = Cols("widgetColumns", 3)
	local avail = p:GetWidth() - PAD * 2
	local cw = (avail - READ_GAP_X * (cols - 1)) / cols
	local a = Palette.c.accent
	for i, name in ipairs(list) do
		local cell = p.cells[i]
		if not cell then
			cell = CreateFrame("Frame", nil, p)
			cell:SetHeight(READ_H)
			cell.value = W.Text(cell, "tbValue", "LEFT")
			cell.value:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
			cell.value:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, 0)
			cell.value:SetWordWrap(false)
			cell.node = cell:CreateTexture(nil, "ARTWORK")
			cell.node:SetTexture(Media.texture.diamondRim)
			cell.node:SetSize(7, 7)
			cell.node:SetPoint("LEFT", cell, "TOPLEFT", 0, -27)
			cell.strand = cell:CreateTexture(nil, "BACKGROUND")
			cell.strand:SetTexture(Media.texture.flat)
			cell.strand:SetHeight(1)
			cell.strand:SetPoint("LEFT", cell.node, "RIGHT", 0, 0)
			cell.strand:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
			cell.label = W.Text(cell, "tbLabel", "LEFT")
			cell.label:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -34)
			cell.label:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, -34)
			cell.label:SetWordWrap(false)
			p.cells[i] = cell
		end
		local obj = ldb and ldb:GetDataObjectByName(name)
		local big, small = self:CardText(name, obj)
		cell.value:SetText(big)
		cell.label:SetText(small)
		W.Color(cell.value, Palette.c.text)
		W.Color(cell.label, { Palette.c.text[1], Palette.c.text[2], Palette.c.text[3], 0.55 })
		cell.node:SetVertexColor(a[1], a[2], a[3], 0.8)
		cell.strand:SetVertexColor(a[1], a[2], a[3], 0.3)
		cell.__source = name
		cell:SetWidth(cw)
		GridPlace(p, cell, i, PAD, PAD + HEAD_H, cols, cw, READ_H, READ_GAP_X, READ_GAP_Y)
		cell:Show()
	end
	for i = #list + 1, #p.cells do p.cells[i]:Hide() end
	p.head:Set(Label("widgets"), ldb and "" or L.cmd.toolbox.libdatabroker)
	local rows = RowsFor(#list, cols)
	p:SetHeight(PAD + HEAD_H + rows * READ_H + math.max(0, rows - 1) * READ_GAP_Y + PAD)
end

function TB:RefreshWidgets()
	if self:IsBranchOpen("widgets") then self:Fill("widgets") end
end

-- ---------------------------------------------------------------------------
-- the Settings branch: toggles as diamonds on strands
--
-- Joe, 2026-10-07 (decision 4a): today's four - Zen, I.F.E.C., Unlock frames,
-- Keybind mode - drawn as Lattice toggles. Three kinds of thing:
--
--   setting   a path into the profile, written the way the options panel
--             writes it, `modules.<name>.enabled` included
--   mode      runtime state with nothing saved, read off the module that
--             owns it every time
--   launcher  an addon the player added from Core/Launchers.lua: no state,
--             so no ON or OFF, because it cannot know
-- ---------------------------------------------------------------------------

TB.TILES = {
	{ kind = "setting", key = "zen", label = "Zen",
	  path = { "modules", "zen", "enabled" },
	  tip = L.toolbox.refresh_widgets.tip },

	-- The in-flight player, not the flight timer.
	{ kind = "setting", key = "ifec", label = L.common.i_f_e_c,
	  path = { "modules", "ifec", "player" },
	  tip = L.toolbox.refresh_widgets.tip2 },

	{ kind = "mode", key = "lock", label = L.toolbox.refresh_widgets.unlock_frames,
	  get = function() return A.Movers and A.Movers.unlocked or false end,
	  set = function(want)
		if not A.Movers then return false end
		if want then A.Movers:Unlock() else A.Movers:Lock() end
		return true
	  end,
	  tip = "Drag any part of the interface to move it, or scroll to nudge it a"
	     .. " pixel at a time - hold shift to nudge sideways. Locked again from"
	     .. " here or with /lattice lock." },

	{ kind = "mode", key = "keybinds", label = L.toolbox.refresh_widgets.keybind_mode,
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
	  tip = L.toolbox.refresh_widgets.tip3 },
}

local function Resolve(path)
	if not path or #path == 0 then return nil end
	local t = A.db.profile
	for i = 1, #path - 1 do t = t and t[path[i]] end
	return t, path[#path]
end

--- true, false, or nil for "no state", which is a launcher.
function TB:TileState(tile)
	if not tile then return nil end
	if tile.kind == "setting" then
		local t, k = Resolve(tile.path)
		if not t then return false end
		return t[k] ~= false
	end
	if tile.kind == "mode" then
		local ok, v = pcall(tile.get)
		return ok and v and true or false
	end
	return nil
end

function TB:TileTooltip(frame)
	local t = frame and frame.__tile
	if not t or not GameTooltip then return end
	GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
	GameTooltip:SetText(t.label or t.key, 1, 1, 1)
	local on = self:TileState(t)
	if on ~= nil then
		local c = on and Palette.c.accent or Palette.c.textDim
		GameTooltip:AddLine(on and L.common.on or L.common.off, c[1], c[2], c[3])
	end
	if t.tip then
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
		-- A module switched off has to be torn down, and one switched on built.
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
		-- Both modes are things you do to the screen, so the branch gets out
		-- of the way when one is switched on.
		if want then self:CloseAll() end
		self:RefreshTiles()
		return true
	end
	return false
end

--- Ours, then the launchers the player put here.
function TB:TileList()
	local out = {}
	for _, t in ipairs(self.TILES) do out[#out + 1] = t end
	local c = Char()
	local chosen = c and c.tiles
	if type(chosen) == "table" and A.Launchers then
		for _, key in ipairs(chosen) do
			local entry = A.Launchers.byKey[key]
			if entry then
				out[#out + 1] = { kind = "launcher", key = key,
					label = entry.label or key, entry = entry }
			end
		end
	end
	return out
end

-- README: a 24 px diamond; on = accent fill, glow, dark icon and ON; off =
-- glass, a 45 % rim, the icon at 50 % and OFF.
local SET_H, SET_NODE, SET_ICON = 36, 24, 14

BUILD.settings = function(self, p)
	p.rows = {}
end

FILL.settings = function(self, p)
	local list = self:TileList()
	self._tileList = list
	local c = Palette.c
	local a = c.accent
	for i, t in ipairs(list) do
		local row = p.rows[i]
		if not row then
			row = CreateFrame("Button", nil, p)
			row:SetHeight(SET_H)
			row.glow = row:CreateTexture(nil, "BACKGROUND")
			row.glow:SetTexture(Media.texture.glow)
			row.glow:SetSize(SET_NODE * 2.2, SET_NODE * 2.2)
			row.fill = row:CreateTexture(nil, "ARTWORK")
			row.fill:SetTexture(Media.texture.diamond)
			row.fill:SetSize(SET_NODE, SET_NODE)
			row.fill:SetPoint("LEFT", row, "LEFT", 0, 0)
			row.glow:SetPoint("CENTER", row.fill, "CENTER")
			row.rim = row:CreateTexture(nil, "ARTWORK", nil, 1)
			row.rim:SetTexture(Media.texture.diamondRim)
			row.rim:SetAllPoints(row.fill)
			row.icon = row:CreateTexture(nil, "OVERLAY")
			row.icon:SetSize(SET_ICON, SET_ICON)
			row.icon:SetPoint("CENTER", row.fill, "CENTER")
			-- The node's strand, out to the label.
			row.strand = row:CreateTexture(nil, "BACKGROUND")
			row.strand:SetTexture(Media.texture.flat)
			row.strand:SetHeight(1)
			row.strand:SetPoint("LEFT", row.fill, "RIGHT", 0, 0)
			row.strand:SetWidth(12)
			row.name = W.Text(row, "tbCardBody", "LEFT")
			row.name:SetPoint("LEFT", row.strand, "RIGHT", 8, 0)
			row.name:SetPoint("RIGHT", row, "RIGHT", -40, 0)
			row.name:SetWordWrap(false)
			row.state = W.Text(row, "tbChip", "RIGHT")
			row.state:SetPoint("RIGHT", row, "RIGHT", 0, 0)
			row:SetScript("OnClick", function(self2)
				if self2.__tile then TB:ToggleTile(self2.__tile) end
			end)
			-- Read off __tile at hover time: rows are reused.
			row:SetScript("OnEnter", function(self2) TB:TileTooltip(self2) end)
			row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
			p.rows[i] = row
		end
		row.__tile = t
		row.name:SetText(t.label or t.key)
		W.Color(row.name, c.text)

		local on = self:TileState(t)
		if t.kind == "launcher" then
			local ic = t.entry and t.entry.obj and t.entry.obj.icon
			if ic then row.icon:SetTexture(ic); row.icon:SetTexCoord(0, 1, 0, 1) end
			row.icon:SetShown(ic ~= nil)
		else
			row.icon:SetShown(Media:SetIcon(row.icon, t.key) and true or false)
		end
		if on then
			W.Tint(row.fill, a, 1)
			W.Tint(row.rim, a, 1)
			W.Tint(row.glow, a, 0.7)
			row.glow:Show()
			if row.icon:IsShown() and t.kind ~= "launcher" then
				row.icon:SetVertexColor(20 / 255, 16 / 255, 31 / 255, 1)
			end
			row.state:SetText(L.common.on:upper())
			W.Color(row.state, a)
		else
			W.Tint(row.fill, { 14 / 255, 11 / 255, 32 / 255 }, 0.85)
			W.Tint(row.rim, a, 0.45)
			row.glow:Hide()
			if row.icon:IsShown() and t.kind ~= "launcher" then
				row.icon:SetVertexColor(1, 1, 1, 0.5)
			end
			row.state:SetText(on == nil and "" or L.common.off:upper())
			W.Color(row.state, c.textDim)
		end
		row.strand:SetVertexColor(a[1], a[2], a[3], on and 0.8 or 0.3)
		row.__on = on
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(PAD + HEAD_H + (i - 1) * SET_H))
		row:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -(PAD + HEAD_H + (i - 1) * SET_H))
		row:Show()
	end
	for i = #list + 1, #p.rows do p.rows[i]:Hide() end
	p:SetHeight(PAD + HEAD_H + #list * SET_H + PAD - 6)
end

function TB:RefreshTiles()
	self._tileList = self:TileList()
	if self:IsBranchOpen("settings") then self:Fill("settings") end
end

-- ---------------------------------------------------------------------------
-- the Addons branch: the launchers, two columns, pins
--
-- Only addons with a launcher: what you can reach from here. A 7 px diamond
-- on each row pins it to the trunk, filled when pinned (board 5b).
-- ---------------------------------------------------------------------------

local ROW_H, ROW_GAP = 28, 4
-- Rows shown before the list scrolls, which keeps the branch on the screen.
local ADDON_ROWS = 10

--- A registry key, made readable where the addon's own title does not match.
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
	-- `LA`, not `L`: L is the phrase table.
	local LA = A.Launchers
	if not LA then return rows end
	local titles = {}
	local api = C_AddOns or _G
	local count = (api.GetNumAddOns and api.GetNumAddOns()) or 0
	for i = 1, count do
		local name, title = api.GetAddOnInfo and api.GetAddOnInfo(i)
		if name then titles[name:lower()] = (title ~= "" and title) or name end
	end
	self._addonsLoaded = count
	for entry in LA:Iterate() do
		rows[#rows + 1] = {
			name  = entry.key,
			label = entry.label or titles[tostring(entry.key):lower()] or PrettyName(entry.key),
			entry = entry,
		}
	end
	table.sort(rows, function(x, y)
		return tostring(x.label):lower() < tostring(y.label):lower()
	end)
	return rows
end

--- Move the list by whole rows, so the two columns never swap over.
function TB:ScrollAddons(delta)
	if not delta or delta == 0 then return end
	local cols = Cols("addonColumns", 2)
	self._addonOffset = math.max(0, (self._addonOffset or 0) - delta * cols)
	if self:IsBranchOpen("addons") then self:Fill("addons") end
end

BUILD.addons = function(self, p)
	p.rows = {}
	-- A chevron, not an arrow character: the font has none.
	p.arrow = p:CreateTexture(nil, "OVERLAY")
	p.arrow:SetSize(9, 9)
	p.arrow:SetTexture(Media.texture.chevron)
	p.arrow:Hide()
	-- The wheel over the whole block, not only over a row.
	p:EnableMouseWheel(true)
	p:SetScript("OnMouseWheel", function(_, delta) TB:ScrollAddons(delta) end)
end

FILL.addons = function(self, p)
	local rows = self._addonRows or self:AddonRows()
	self._addonRows = rows
	local cols = Cols("addonColumns", 2)
	local avail = p:GetWidth() - PAD * 2
	local rw = (avail - ROW_GAP * (cols - 1)) / cols
	local total = #rows
	local maxShown = ADDON_ROWS * cols

	-- The last page starts on a row boundary at or past where the final entry
	-- fits, or an odd count leaves its last entry under the fold.
	local maxOffset = math.max(0, total - maxShown)
	if maxOffset % cols ~= 0 then maxOffset = maxOffset + cols - (maxOffset % cols) end
	local offset = math.min(math.max(0, self._addonOffset or 0), maxOffset)
	offset = offset - (offset % cols)
	self._addonOffset = offset

	local c = Palette.c
	local shown = 0
	for i, r in ipairs(rows) do
		local row = p.rows[i]
		if not row then
			row = CreateFrame("Button", nil, p)
			row:SetHeight(ROW_H)
			row:EnableMouseWheel(true)
			row:SetScript("OnMouseWheel", function(_, delta) TB:ScrollAddons(delta) end)
			row.tile = Glass.CreatePanel(row, { corner = 8 })
			row.tile:SetSize(25, 25)
			row.tile:SetPoint("LEFT", row, "LEFT", 0, 0)
			row.icon = row.tile:CreateTexture(nil, "ARTWORK")
			row.icon:SetPoint("CENTER", row.tile, "CENTER", 0, 0)
			row.icon:SetSize(17, 17)
			row.initial = W.Text(row.tile, "tbLabel", "CENTER")
			row.initial:SetPoint("CENTER", row.tile, "CENTER", 0, 0)
			row.name = W.Text(row, "tbCardBody", "LEFT")
			row.name:SetPoint("LEFT", row.tile, "RIGHT", 9, 0)
			row.name:SetPoint("RIGHT", row, "RIGHT", -18, 0)
			row.name:SetWordWrap(false)
			row.pin = CreateFrame("Button", nil, row)
			row.pin:SetSize(15, 15)
			row.pin:SetPoint("RIGHT", row, "RIGHT", 0, 0)
			row.pin.glyph = row.pin:CreateTexture(nil, "ARTWORK")
			row.pin.glyph:SetSize(7, 7)
			row.pin.glyph:SetPoint("CENTER")
			row.pin:SetScript("OnClick", function(self2)
				local rr = self2:GetParent().__row
				if rr and rr.entry then TB:TogglePin(rr.entry.key) end
			end)
			row:SetScript("OnClick", function(self2)
				local rr = self2.__row
				if rr and rr.entry then A.Launchers:Click(rr.entry, "LeftButton") end
			end)
			p.rows[i] = row
		end
		row.__row = r
		row.name:SetText(r.label)
		W.Color(row.name, c.text)
		-- The icon, or the initial: about half of all addons offer no icon, so
		-- the letter is the ordinary case.
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
		local pinned = self:IsPinned(r.entry.key)
		row.pin.glyph:SetTexture(pinned and Media.texture.diamond or Media.texture.diamondRim)
		row.pin.glyph:SetVertexColor(c.accent[1], c.accent[2], c.accent[3], pinned and 1 or 0.4)
		row.__pinned = pinned

		local slot = i - offset
		if slot >= 1 and slot <= maxShown then
			row:SetWidth(rw)
			GridPlace(p, row, slot, PAD, PAD + HEAD_H, cols, rw, ROW_H, ROW_GAP, ROW_GAP)
			row:Show()
			shown = shown + 1
		else
			row:Hide()
		end
	end
	for i = total + 1, #p.rows do p.rows[i]:Hide() end

	self._addonsCut = math.max(0, total - shown)
	self._addonsMore = math.max(0, total - offset - shown)
	local scrollable = self._addonsCut > 0 or offset > 0
	p.head:Set(L.toolbox.head.addons,
		scrollable and A.F(L.toolbox.head.addons_scroll_d, total) or tostring(total))
	-- One arrow, the way there is more: down until the end, then up.
	p.arrow:SetShown(scrollable)
	if scrollable then
		p.arrow:ClearAllPoints()
		p.arrow:SetPoint("RIGHT", p.head.hint, "LEFT", -4, 0)
		if p.arrow.SetRotation then
			pcall(p.arrow.SetRotation, p.arrow, self._addonsMore > 0 and 0 or math.pi)
		end
		p.arrow:SetVertexColor(c.text[1], c.text[2], c.text[3], 0.55)
		p.head.strand:ClearAllPoints()
		p.head.strand:SetPoint("LEFT", p.head.label, "RIGHT", 8, 0)
		p.head.strand:SetPoint("RIGHT", p.arrow, "LEFT", -6, 0)
	end
	local lines = math.max(1, RowsFor(shown, cols))
	p:SetHeight(PAD + HEAD_H + lines * (ROW_H + ROW_GAP) - ROW_GAP + PAD)
end

function TB:RefreshAddons()
	self._addonRows = self:AddonRows()
	if self:IsBranchOpen("addons") then self:Fill("addons") end
end

-- ---------------------------------------------------------------------------
-- pinning, and the pins on the trunk
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

--- Pinning claims the entry for the trunk, whoever had it.
function TB:SetPinned(key, on)
	local pinned = self:Pinned()
	local LA = A.Launchers
	local entry = LA and LA.byKey[key]
	if not entry then return false end
	if on and not self:IsPinned(key) then
		pinned[#pinned + 1] = key
		LA:Claim(entry, self, true)
	elseif not on then
		for i = #pinned, 1, -1 do
			if pinned[i] == key then table.remove(pinned, i) end
		end
		LA:Release(entry, self)
		-- Still ours, so it is parked rather than left on the minimap ring.
		LA:Claim(entry, self)
	end
	self:LayoutPins()
	self:RefreshAddons()
	return true
end

function TB:TogglePin(key)
	return self:SetPinned(key, not self:IsPinned(key))
end

--- Take every launcher: pins first and forced, then everything else, because
--  a launcher nobody positions is one still sitting on the minimap ring.
--  Idempotent, so it runs on every launcher change.
function TB:ClaimPins()
	local LA = A.Launchers
	if not LA then return 0 end
	local n = 0
	for _, key in ipairs(self:Pinned()) do
		local e = LA.byKey[key]
		if e and LA:OwnerOf(e) ~= self then
			LA:Claim(e, self, true)
			n = n + 1
		end
	end
	for e in LA:Iterate() do
		if not LA:OwnerOf(e) then
			LA:Claim(e, self)
			n = n + 1
		end
	end
	return n
end

--- The pinned addons, hung below the last node (board 5b): one bare item
--  node each, the addon's own button on it. Never Hide()n - another addon's
--  button may carry a secure template - so the rest are parked.
function TB:LayoutPins()
	local LA = A.Launchers
	if not LA then return end
	local list = {}
	for _, key in ipairs(self:Pinned()) do
		local e = LA.byKey[key]
		if e and e.button and LA:OwnerOf(e) == self then list[#list + 1] = e end
	end
	self._pins = list
	self.pinNodes = self.pinNodes or {}
	local t = Trunk()
	for i = #self.pinNodes + 1, #list do
		self.pinNodes[i] = t:AddNode("pin" .. i, {
			kind = "item", bare = true, size = PIN, step = PIN_STEP, order = 1000 + i,
			available = function() return TB.enabled and TB._pins and TB._pins[i] ~= nil or false end,
		})
	end
	t:Refresh()

	for i, e in ipairs(list) do
		local host = self.pinNodes[i] and self.pinNodes[i].button
		local b = e.button
		if host then
			-- Prepared again every time: LibDBIcon re-pins its own strata and
			-- level, and a button left at MEDIUM 8 draws behind the trunk.
			e._prepared = nil
			LA:Prepare(e)
			pcall(LA.RawSetParent, b, host)
			pcall(LA.RawClearAllPoints, b)
			pcall(LA.RawSetPoint, b, "CENTER", host, "CENTER", 0, 0)
			pcall(LA.RawSetSize, b, PIN, PIN)
			if b.SetFrameStrata then pcall(b.SetFrameStrata, b, host:GetFrameStrata()) end
			if b.SetFrameLevel then pcall(b.SetFrameLevel, b, host:GetFrameLevel() + 5) end
			if b.SetAlpha then pcall(b.SetAlpha, b, 1) end
			if b.EnableMouse then pcall(b.EnableMouse, b, true) end
		end
	end
	for e in LA:Iterate() do
		if LA:OwnerOf(e) == self and not self:IsPinned(e.key) then LA:Park(e) end
	end
	self._railCount = #list
end

-- ---------------------------------------------------------------------------
-- the Menu branch
--
-- Our own buttons, not Blizzard's micro buttons. Every action is probed
-- first: a global that is not there is a door that is not drawn. Ten, as a
-- 5 x 2 grid (decision 4b), and the one whose window is open is lit (board
-- 6a). Social and Guild are both here, whichever way the client's CVar
-- shows them; Bags is ours, through the global our bags module hooks.
-- ---------------------------------------------------------------------------

--- Whether this character can open the talent window at all: below level 10
--  the client's own toggle silently does nothing. A client that will not
--  answer gets the door.
local function CanUseTalents()
	local S = _G.C_SpecializationInfo
	local fn = S and S.CanPlayerUseTalentUI
	if type(fn) ~= "function" then return true end
	local ok, can = pcall(fn)
	if not ok then return true end
	return can and true or false
end

local function Shown(...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if type(f) == "string" then f = _G[f] end
		if f and f.IsShown and f:IsShown() then return true end
	end
	return false
end

TB.MICRO = {
	{ key = "character", label = "Character",
	  fn = function() ToggleCharacter("PaperDollFrame") end,
	  probe = function() return ToggleCharacter ~= nil end,
	  open = function() return Shown("CharacterFrame") end },
	{ key = "spellbook", label = "Spellbook",
	  fn = function() ToggleSpellBook(BOOKTYPE_SPELL or "spell") end,
	  probe = function() return ToggleSpellBook ~= nil end,
	  open = function() return Shown("SpellBookFrame") end },
	{ key = "talents",   label = "Talents",
	  fn = function() ToggleTalentFrame() end,
	  probe = function() return ToggleTalentFrame ~= nil and CanUseTalents() end,
	  open = function() return Shown("TalentFrame", "PlayerTalentFrame") end },
	{ key = "quests",    label = L.toolbox.refresh_addons.quest_log,
	  fn = function() ToggleQuestLog() end,
	  probe = function() return ToggleQuestLog ~= nil end,
	  open = function()
		local QL = A:GetModule("questlog")
		return Shown(QL and QL.win, "QuestLogFrame")
	  end },
	{ key = "bags",      label = "Bags",
	  fn = function() ToggleAllBags() end,
	  probe = function() return ToggleAllBags ~= nil end,
	  open = function()
		local BG = A:GetModule("bags")
		return Shown(BG and BG.frames and BG.frames.bags, "ContainerFrame1")
	  end },
	{ key = "social",    label = "Social",
	  fn = function() ToggleFriendsFrame() end,
	  probe = function() return ToggleFriendsFrame ~= nil end,
	  open = function() return Shown("FriendsFrame") end },
	{ key = "guild",     label = "Guild",
	  fn = function() ToggleGuildFrame() end,
	  probe = function() return ToggleGuildFrame ~= nil end,
	  open = function() return Shown("GuildFrame", "CommunitiesFrame") end },
	{ key = "map",       label = "Map",
	  fn = function() ToggleWorldMap() end,
	  probe = function() return ToggleWorldMap ~= nil end,
	  open = function() return Shown("WorldMapFrame") end },
	{ key = "menu",      label = "Menu",
	  -- NOT ToggleGameMenu, which is the Escape handler: it closes a window
	  -- first and never reaches the menu. Shut the windows, then open the
	  -- menu, as Blizzard's own button does.
	  fn = function()
		  if GameMenuFrame and GameMenuFrame:IsShown() then
			  if HideUIPanel then HideUIPanel(GameMenuFrame) end
			  return
		  end
		  if CloseMenus then pcall(CloseMenus) end
		  if CloseAllWindows then pcall(CloseAllWindows) end
		  if GameMenuFrame and ShowUIPanel then ShowUIPanel(GameMenuFrame) end
	  end,
	  probe = function() return GameMenuFrame ~= nil and ShowUIPanel ~= nil end,
	  open = function() return Shown("GameMenuFrame") end },
	{ key = "help",      label = "Help",
	  fn = function() ToggleHelpFrame() end,
	  probe = function() return ToggleHelpFrame ~= nil end,
	  open = function() return Shown("HelpFrame") end },
}

function TB:MicroList()
	local out = {}
	for _, m in ipairs(self.MICRO) do
		local ok, present = pcall(m.probe)
		if ok and present then out[#out + 1] = m end
	end
	return out
end

local MENU_PER, MENU_H, MENU_GAP = 5, 50, 6

BUILD.menu = function(self, p)
	p.cells = {}
	-- The lit door follows windows opened and shut any other way.
	p:HookScript("OnShow", function()
		A:RegisterTicker(TB._menuToken, function() TB:PaintMenu() end)
	end)
	p:HookScript("OnHide", function() A:UnregisterTicker(TB._menuToken) end)
end

FILL.menu = function(self, p)
	local list = self:MicroList()
	self._microList = list
	local avail = p:GetWidth() - PAD * 2
	local cw = (avail - MENU_GAP * (MENU_PER - 1)) / MENU_PER
	for i, m in ipairs(list) do
		local b = p.cells[i]
		if not b then
			b = W.CreateButton(p, { corner = 10 })
			b.glyph = b:CreateTexture(nil, "OVERLAY")
			b.glyph:SetSize(20, 20)
			b.glyph:SetPoint("TOP", b, "TOP", 0, -8)
			b.name = W.Text(b, "tbLabel", "CENTER")
			b.name:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 7)
			b.name:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 7)
			b.name:SetWordWrap(false)
			b.__aetherLabel = b.name
			b:SetScript("OnClick", function(self2)
				if self2.__micro then pcall(self2.__micro.fn) end
				TB:PaintMenu()
			end)
			b:SetScript("OnEnter", function(self2)
				self2.__hover = true
				TB:PaintMenu()
				if GameTooltip and self2.__micro then
					GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
					GameTooltip:SetText(self2.__micro.label)
					GameTooltip:Show()
				end
			end)
			b:SetScript("OnLeave", function(self2)
				self2.__hover = nil
				TB:PaintMenu()
				if GameTooltip then GameTooltip:Hide() end
			end)
			p.cells[i] = b
		end
		b.__micro = m
		b.glyph:SetShown(Media:SetIcon(b.glyph, m.key) and true or false)
		b.name:SetText(m.label or "")
		b:SetSize(cw, MENU_H)
		GridPlace(p, b, i, PAD, PAD + HEAD_H, MENU_PER, cw, MENU_H, MENU_GAP, MENU_GAP)
		b:Show()
	end
	for i = #list + 1, #p.cells do p.cells[i]:Hide() end
	local rows = RowsFor(#list, MENU_PER)
	p:SetHeight(PAD + HEAD_H + rows * MENU_H + math.max(0, rows - 1) * MENU_GAP + PAD)
	self:PaintMenu()
end

--- Lit for the door whose window is open.
function TB:PaintMenu()
	local p = self.panels and self.panels.menu
	if not p then return end
	local c = Palette.c
	for _, b in ipairs(p.cells) do
		if b:IsShown() and b.__micro then
			local ok, lit = pcall(b.__micro.open or function() return false end)
			lit = ok and lit and true or false
			b.__lit = lit
			W.SetButtonState(b, lit, b.__hover)
			local g = lit and c.btnFillText or c.text
			b.glyph:SetVertexColor(g[1], g[2], g[3], lit and 1 or 0.85)
		end
	end
end

function TB:RefreshMicro()
	self._microList = self:MicroList()
	if self:IsBranchOpen("menu") then self:Fill("menu") end
end

-- ---------------------------------------------------------------------------
-- the What's new branch
--
-- Read from Core/Changelog.lua; the .toc is the version, and the harness
-- refuses a build where the two disagree. The node's dot is lit until the
-- branch is opened on this version.
-- ---------------------------------------------------------------------------

--- Lines of the current entry the branch shows; Notes has the rest.
TB.NEWS_LINES = 3

function TB:NewsVersion()
	local entry = A.Notes and A:Notes()
	return (entry and entry.version) or A.version or "0.0.0"
end

--- The lines the branch shows.
function TB:NewsLines()
	local entry = A.Notes and A:Notes()
	if not entry or not entry.lines or #entry.lines == 0 then
		return { L.toolbox.news.none }
	end
	local out = {}
	for i = 1, math.min(#entry.lines, self.NEWS_LINES) do out[i] = entry.lines[i] end
	return out
end

--- Whether there is more than the branch shows, which is when Notes is offered.
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
	Trunk():Paint()
end

local NEWS_GAP, NOTES_H = 8, 22

BUILD.news = function(self, p)
	p.lines = {}
	local notes = CreateFrame("Button", nil, p)
	notes:SetSize(46, 16)
	notes.text = W.Text(notes, "tbLabel", "LEFT")
	notes.text:SetPoint("LEFT", notes, "LEFT", 0, 0)
	notes.text:SetText(L.toolbox.build_content.notes)
	-- Underlined: "Notes" in the accent beside body text reads as emphasis,
	-- not as somewhere to click.
	notes.rule = notes:CreateTexture(nil, "OVERLAY")
	notes.rule:SetTexture(Media.texture.flat)
	notes.rule:SetHeight(1)
	notes.rule:SetPoint("TOPLEFT", notes.text, "BOTTOMLEFT", 0, -1)
	notes.rule:SetPoint("TOPRIGHT", notes.text, "BOTTOMRIGHT", 0, -1)
	notes:SetScript("OnClick", function()
		TB:MarkNewsRead()
		TB:CloseAll()
		if A.Options and A.Options.Open then A.Options:Open("changelog") end
	end)
	p.notes = notes
end

FILL.news = function(self, p)
	local c = Palette.c
	local a = c.accent
	local text = self:NewsLines()
	local width = p:GetWidth() - PAD * 2 - 14
	local y = PAD + HEAD_H
	for i, s in ipairs(text) do
		local ln = p.lines[i]
		if not ln then
			ln = {}
			ln.node = p:CreateTexture(nil, "ARTWORK")
			ln.node:SetTexture(Media.texture.diamond)
			ln.node:SetSize(5, 5)
			ln.text = W.Text(p, "tbCardBody", "LEFT")
			ln.text:SetJustifyV("TOP")
			p.lines[i] = ln
		end
		ln.text:SetWidth(width)
		ln.text:SetText(s)
		ln.text:ClearAllPoints()
		ln.text:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + 14, -y)
		ln.node:ClearAllPoints()
		ln.node:SetPoint("CENTER", p, "TOPLEFT", PAD + 3, -(y + 7))
		ln.node:SetVertexColor(a[1], a[2], a[3], 0.6)
		W.Color(ln.text, c.text)
		ln.text:Show()
		ln.node:Show()
		y = y + math.max(14, ln.text:GetStringHeight() or 14) + NEWS_GAP
	end
	for i = #text + 1, #p.lines do
		p.lines[i].text:Hide()
		p.lines[i].node:Hide()
	end
	p.head:Set(L.common.what_s_new, A.F(L.common.aether_ui_s, A.version or "?"))
	local more = self:NewsHasMore()
	p.notes:SetShown(more)
	W.Color(p.notes.text, a)
	p.notes.rule:SetVertexColor(a[1], a[2], a[3], 0.55)
	if more then
		p.notes:ClearAllPoints()
		p.notes:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + 14, -y)
		y = y + NOTES_H
	end
	p:SetHeight(y - NEWS_GAP + PAD)
end

function TB:RefreshNews()
	if self:IsBranchOpen("news") then self:Fill("news") end
	Trunk():Paint()
end
