--[[--------------------------------------------------------------------------
	Lattice :: Options window (the map)

	The options handoff (design_handoff_options, boards 7a-7c). One window,
	1200 x 760, whose home is a map of the player's own screen: every module a
	node where it lives in the HUD now, bonded as the HUD is, with a SYSTEM
	strand along the bottom for what has no place on screen. Point at the thing
	you want to change.

	  Hover a node   it fills, its real frame lights, a card says what is in it.
	  Click          the map folds into the nav strand down the left and the
	                 node unfolds into its page. The strand is the only
	                 navigation: its root is the map; Esc steps back.
	  Shift-click    unlock just that module.
	  /              search; matching nodes light and the settings list under
	                 the field; Enter opens the first and pulses its row.

	Pages are drawn from the option tree (Core/Options.lua) by
	Core/OptionsControls.lua, two columns of panel-vocabulary controls; every
	change applies at once. Not shown in a fight: it fades out when one starts
	and comes back after.

	All of it is our own plain frames, moved and faded by one driver on the
	window - alpha, position and scale, nothing the client can refuse.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = A.L
local W, Media, Palette = A.Widgets, A.Media, A.Palette
local C = A.OptionsControls

local OW = { views = {}, mode = "map" }
A.OptionsWindow = OW

-- The handoff's numbers, in the window's own units.
local WIN_W, WIN_H, HEAD_H = 1200, 760, 64
local NAV_W, NAV_X = 100, 36
-- The map's field: the HUD scaled into it (x 62 to 1138, as 7a's x 0.56 from
-- 62), the System strand under it.
local MAP_L, MAP_R, MAP_T, MAP_B = 62, 1138, 84, 640
local SYS_Y, SYS_L, SYS_R = 712, 60, 1140
local FIELD_STEP = 48
local PAD_T, PAD_R, PAD_B, PAD_L = 22, 32, 26, 28
local PREVIEW_H = 130
-- 28 apart: sixteen module pages and five System ones down a 760 window.
local NAV_TOP, NAV_STEP = 96, 28
local CARD_W = 220

-- Timing (7c), in seconds.
local HOP, NODE_IN, UNFOLD, BODY_AT, SWITCH = 0.04, 0.16, 0.26, 0.2, 0.15
local REDUCED = 0.12
local SLIDE = 12

local NODE_FILL = C.NODE_FILL

--- One colour from a palette entry that may be a gradient's stops.
local function Flat(c)
	if type(c) == "table" and type(c[1]) == "table" then return c[1] end
	return c
end

-- ---------------------------------------------------------------------------
-- the pages
--
-- One per node on the map, then the System strand's. `groups` are the tree's
-- top-level groups the page holds; the first is the page, the rest its
-- sub-pages (the sub-label under the map node). `unlock` is the module's
-- movers, for Shift-click and the page's Unlock button.
-- ---------------------------------------------------------------------------

OW.PAGES = {
	{ key = "unitframes", form = "pill", module = "unitframes", groups = { "unitframes" },
		title = L.options.map.unitframes.title, desc = L.options.map.unitframes.desc,
		unlock = { "player", "target", "pet", "targettarget" }, preview = true },
	{ key = "auras", form = "square", module = "auras", groups = { "auras" },
		title = L.options.map.auras.title, desc = L.options.map.auras.desc },
	{ key = "actionbars", form = "square", module = "actionbars", groups = { "actionbars" },
		title = L.options.map.actionbars.title, desc = L.options.map.actionbars.desc, bars = true },
	{ key = "nameplates", form = "pill", tint = "danger", module = "nameplates",
		groups = { "nameplates", "threat", "tooltips" },
		title = L.options.map.nameplates.title, desc = L.options.map.nameplates.desc },
	{ key = "partyframes", form = "pill", tint = "friendly", module = "partyframes",
		groups = { "partyframes" }, unlock = { "party" },
		title = L.options.map.partyframes.title, desc = L.options.map.partyframes.desc },
	{ key = "chat", form = "square", module = "chat", groups = { "chat" }, unlock = { "chat" },
		title = L.options.map.chat.title, desc = L.options.map.chat.desc },
	{ key = "bags", form = "square", module = "bags", groups = { "bags" },
		title = L.options.map.bags.title, desc = L.options.map.bags.desc },
	{ key = "toolbox", form = "diamond", module = "toolbox", groups = { "toolbox", "fader" },
		title = L.options.map.toolbox.title, desc = L.options.map.toolbox.desc },
	{ key = "minimap", form = "circle", module = "minimap", groups = { "minimap" },
		unlock = { "minimap" },
		title = L.options.map.minimap.title, desc = L.options.map.minimap.desc },
	-- THE WORLD TRUNK, a node each, as it is on the trunk (Joe, 2026-10-10).
	{ key = "quests", form = "diamond", module = "questtracker", groups = { "quests" },
		unlock = { "minimap" },
		title = L.options.map.quests.title, desc = L.options.map.quests.desc },
	{ key = "mail", form = "diamond", groups = { "mail" }, world = "mail",
		title = L.options.map.mail.title, desc = L.options.map.mail.desc },
	{ key = "tracking", form = "diamond", groups = { "tracking" }, world = "tracking",
		title = L.options.map.tracking.title, desc = L.options.map.tracking.desc },
	{ key = "calendar", form = "diamond", groups = { "calendar" }, world = "calendar",
		title = L.options.map.calendar.title, desc = L.options.map.calendar.desc },
	{ key = "nifec", form = "diamond", groups = { "nifec" }, world = "nifec",
		title = L.options.map.nifec.title, desc = L.options.map.nifec.desc },
	-- The flight console, where it shows in flight.
	{ key = "ifec", form = "square", module = "ifec", groups = { "ifec" }, unlock = { "ifec" },
		title = L.options.map.ifec.title, desc = L.options.map.ifec.desc },

	{ key = "general", system = true, groups = { "general", "xpbar", "onboard" },
		title = L.options.map.general.title, desc = L.options.map.general.desc },
	-- ONE PAGE: the game's own panels are a section of it, not a tab (Joe).
	{ key = "skins", system = true, groups = { "skins", "gameown" }, merge = true,
		title = L.options.map.skins.title, desc = L.options.map.skins.desc },
	{ key = "profiles", system = true, groups = { "profiles" },
		title = L.options.map.profiles.title, desc = L.options.map.profiles.desc },
	{ key = "conveniences", system = true, groups = { "conveniences" },
		title = L.options.map.conveniences.title, desc = L.options.map.conveniences.desc },
	{ key = "unlock", system = true, action = "unlock",
		title = L.options.map.unlock.title, desc = L.options.map.unlock.desc },
	{ key = "tour", system = true, action = "tour",
		title = L.options.map.tour.title, desc = L.options.map.tour.desc },
	{ key = "changelog", system = true, groups = { "changelog" }, news = true,
		title = L.options.map.changelog.title, desc = L.options.map.changelog.desc },
}

function OW:Page(key)
	for _, p in ipairs(self.PAGES) do
		if p.key == key then return p end
	end
end

--- The page holding a tree group (`/lattice config chat`, the Notes link's
--  "changelog"), and which of its sub-pages.
function OW:PageFor(section)
	if not section then return nil end
	local direct = self:Page(section)
	if direct and not direct.action then return direct, 1 end
	for _, p in ipairs(self.PAGES) do
		for i, g in ipairs(p.groups or {}) do
			if g == section then
				local subs = self:Subs(p)
				for j, s in ipairs(subs) do
					if s.groupKey == g and s.first then return p, j end
				end
				return p, i
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- the tree, per page
-- ---------------------------------------------------------------------------

function OW:Tree()
	self.tree = self.tree or A.Options:Build()
	return self.tree
end

--- A page's sub-pages, in order: each of its groups, and a group's own pages
--  (the bars) after it.
function OW:Subs(page)
	local tree, out = self:Tree(), {}
	-- A merged page draws its later groups as sections of the first.
	if page.merge then
		local first = tree.args[page.groups[1]]
		if not first then return out end
		local args = {}
		for k, v in pairs(first.args or {}) do args[k] = v end
		for i = 2, #page.groups do
			local g = tree.args[page.groups[i]]
			if g then
				local copy = {}
				for k, v in pairs(g) do copy[k] = v end
				copy.inline, copy.order = true, 1000 + i
				args["__" .. page.groups[i]] = copy
			end
		end
		local merged = {}
		for k, v in pairs(first) do merged[k] = v end
		merged.args = args
		out[1] = { label = C.Name(first), group = merged, groupKey = page.groups[1], first = true }
		return out
	end
	for _, key in ipairs(page.groups or {}) do
		local g = tree.args[key]
		if g then
			local own = C.Subs(g)
			out[#out + 1] = { label = (#own > 0) and L.options.map.all_bars or C.Name(g),
				group = g, groupKey = key, first = true }
			for _, e in ipairs(own) do
				out[#out + 1] = { label = C.Name(e.node), group = e.node, groupKey = key, subKey = e.key }
			end
		end
	end
	return out
end

--- Every setting a page holds, across its sub-pages.
function OW:Leaves(page)
	local out = {}
	for _, s in ipairs(self:Subs(page)) do C.Leaves(s.group, out) end
	return out
end

local function ModuleOn(page)
	if page.world then return A.db.profile.world[page.world] ~= false end
	if not page.module then return true end
	local cfg = A.Config:Module(page.module)
	return not (cfg and cfg.enabled == false)
end

-- ---------------------------------------------------------------------------
-- where things are: the HUD, measured, into the map
-- ---------------------------------------------------------------------------

local function MoverFrame(name)
	local e = A.Movers.registry and A.Movers.registry[name]
	return e and e.frame or nil
end

local function BagsFrame()
	local B = A:GetModule("bags")
	return B and B.frames and B.frames.bags or nil
end

local function TrunkRoot(name)
	local t = A.Trunk.list[name]
	return t and t.root or nil
end

--- A frame's centre on the map, or nil when it has none to give.
local function OnMap(frame)
	if not frame then return nil end
	local x, y = A.Movers.PointAt(frame, "CENTER")
	if not (x and y) then return nil end
	local sw, sh = UIParent:GetWidth() or 1, UIParent:GetHeight() or 1
	return MAP_L + (x / sw) * (MAP_R - MAP_L), MAP_T + (1 - y / sh) * (MAP_B - MAP_T)
end

local function FromFraction(fx, fy)
	return MAP_L + fx * (MAP_R - MAP_L), MAP_T + (1 - fy) * (MAP_B - MAP_T)
end

local function Clamp(x, y, w, h)
	x = math.max(MAP_L - 40 + w / 2, math.min(MAP_R + 40 - w / 2, x))
	y = math.max(MAP_T + h / 2, math.min(MAP_B - h / 2, y))
	return x, y
end

--- The map's nodes, measured from the HUD as it stands. Rebuilt on every
--  open: the map is the layout, so a frame moved in unlock is moved here.
function OW:Spec()
	local list = {}
	local function add(t) list[#list + 1] = t return t end
	add({ key = "player", page = "unitframes", label = L.options.map.unitframes.title,
		form = "pill", w = 108, h = 32, hop = 0, mover = "player", big = true, at = { 0.36, 0.19 } })
	add({ key = "target", page = "unitframes", label = L.common.target,
		form = "pill", w = 108, h = 32, hop = 1, mover = "target", big = true, at = { 0.64, 0.19 } })
	add({ key = "targettarget", page = "unitframes", label = L.options.map.tot,
		form = "pill", w = 86, h = 26, hop = 1, mover = "targettarget", at = { 0.72, 0.28 } })
	add({ key = "pet", page = "unitframes", label = L.options.map.pet,
		form = "pill", w = 60, h = 26, hop = 1, mover = "pet", at = { 0.28, 0.28 } })
	add({ key = "auras", page = "auras", label = L.options.map.auras.title,
		form = "auras", w = 92, h = 14, hop = 2, near = "player", dx = 22, dy = -28 })

	-- ONE NODE PER STRAND, drawn in its shape (strands brief), hidden ones
	-- hollow - one click from their page.
	local AB = A:GetModule("actionbars")
	local cfg = A.Config:Module("actionbars")
	for _, bar in ipairs(cfg.bars or {}) do
		local id = tostring(bar.id)
		local cols, rows = 12, 1
		if AB and AB.ShapeOf then cols, rows = AB:ShapeOf(id) end
		cols, rows = math.max(1, math.min(12, cols or 12)), math.max(1, math.min(12, rows or 1))
		add({ key = "bar" .. id, page = "actionbars", subKey = "bar" .. id,
			label = bar.label or ("Bar " .. id), form = "strand", cols = cols, rows = rows,
			w = cols * 5 + 9, h = rows * 5 + 9, hop = 2, mover = "bar" .. id,
			hollow = bar.enabled == false, at = { 0.5, 0.06 } })
	end

	add({ key = "nameplates", page = "nameplates", label = L.options.map.nameplates.title,
		form = "pill", tint = "danger", w = 104, h = 26, hop = 2, at = { 0.5, 0.7 } })
	add({ key = "party", page = "partyframes", label = L.options.map.partyframes.title,
		form = "pill", tint = "friendly", w = 80, h = 26, hop = 3, mover = "party", at = { 0.12, 0.6 } })
	add({ key = "chat", page = "chat", label = L.options.map.chat.title,
		form = "square", w = 80, h = 26, hop = 3, mover = "chat", at = { 0.1, 0.12 } })
	add({ key = "bags", page = "bags", label = L.options.map.bags.title,
		form = "square", w = 70, h = 26, hop = 3, frame = BagsFrame(), at = { 0.84, 0.22 } })
	add({ key = "toolbox", page = "toolbox", label = L.options.map.toolbox.title,
		form = "diamond", w = 24, h = 24, hop = 3, frame = TrunkRoot("toolbox"), at = { 0.02, 0.72 },
		trunk = true })
	add({ key = "minimap", page = "minimap", label = L.options.map.minimap.title,
		form = "circle", w = 60, h = 60, hop = 3, mover = "minimap", at = { 0.94, 0.79 } })
	-- The World trunk's nodes, measured from their own buttons on the trunk;
	-- stacked under the map where the trunk is not up.
	local world = A.Trunk.list.world
	local function WorldNode(trunkKey)
		local n = world and world:Node(trunkKey)
		return n and n.button and n.button:IsShown() and n.button or nil
	end
	for i, e in ipairs({
		{ "quests", "questlog", L.options.map.quests.title },
		{ "mail", "mail", L.options.map.mail.title },
		{ "tracking", "tracking", L.options.map.tracking.title },
		{ "calendar", "calendar", L.options.map.calendar.title },
		{ "nifec", "nowplaying", L.options.map.nifec.title },
	}) do
		local real = WorldNode(e[2])
		add({ key = e[1], page = e[1], label = e[3], form = "diamond",
			w = i == 1 and 24 or 18, h = i == 1 and 24 or 18, hop = 3, trunk = true,
			frame = real, near = not real and "minimap" or nil, dx = 0, dy = 60 + 34 * i })
	end
	add({ key = "ifec", page = "ifec", label = L.options.map.ifec.title,
		form = "square", w = 100, h = 26, hop = 3, mover = "ifec", at = { 0.5, 0.82 } })

	local byKey = {}
	for _, n in ipairs(list) do byKey[n.key] = n end
	for _, n in ipairs(list) do
		local x, y
		if n.near then
			local o = byKey[n.near]
			if o and o.x then x, y = o.x + (n.dx or 0), o.y + (n.dy or 0) end
		else
			local f = n.frame or (n.mover and MoverFrame(n.mover))
			n.real = f
			x, y = OnMap(f)
		end
		if not x then x, y = FromFraction(n.at and n.at[1] or 0.5, n.at and n.at[2] or 0.5) end
		n.x, n.y = Clamp(x, y, n.w, n.h)
		n.pageDef = self:Page(n.page)
		n.off = n.hollow or not ModuleOn(n.pageDef)
	end
	-- The trunks' sides: a label runs toward the middle of the screen.
	for _, n in ipairs(list) do
		if n.trunk then n.side = (n.x > WIN_W / 2) and -1 or 1 end
	end
	-- Parents, for the bonds: the spine is the middle of the axis.
	for _, n in ipairs(list) do
		local parent = n.mover and A.Movers:ParentOf(n.mover)
		n.parent = parent and (parent == "spine" and "spine" or byKey[parent] and parent) or nil
	end
	if byKey.pet and not byKey.pet.parent then byKey.pet.parent = "player" end
	if byKey.targettarget and not byKey.targettarget.parent then byKey.targettarget.parent = "target" end
	self.byKey = byKey
	return list
end

-- ---------------------------------------------------------------------------
-- building
-- ---------------------------------------------------------------------------

local function Hairline(parent)
	return W.Hairline(parent)
end

local function Line(parent, layer)
	local l = parent:CreateLine(nil, layer or "ARTWORK")
	l:SetTexture(Media.texture.flat)
	return l
end

local function SetLine(l, parent, x1, y1, x2, y2, thick, alpha)
	local a = Palette.c.accent
	l:SetStartPoint("TOPLEFT", parent, x1, -y1)
	l:SetEndPoint("TOPLEFT", parent, x2, -y2)
	l:SetThickness(thick or 1)
	l:SetColorTexture(a[1], a[2], a[3], alpha or 0.4)
	l.__alpha = alpha or 0.4
end

--- The window's scale: the HUD's, unless the screen is too short or narrow
--  for 1200 x 760 at it.
function OW:Scale()
	local s = A.db.profile.scale or 1
	local sw, sh = UIParent:GetWidth() or WIN_W, UIParent:GetHeight() or WIN_H
	return math.min(s, sh * 0.94 / WIN_H, sw * 0.98 / WIN_W)
end

function OW:Place()
	local f = self.frame
	local s = self:Scale()
	f:SetScale(s)
	f:ClearAllPoints()
	local spot = A.db.profile.anchors and A.db.profile.anchors.__options
	if spot and spot.point then
		f:SetPoint(spot.point, UIParent, spot.relPoint or spot.point, spot.x or 0, spot.y or 0)
	else
		-- Centred, its top at 4 % of the screen, so the HUD below stays in view.
		f:SetPoint("TOP", UIParent, "TOP", 0, -((UIParent:GetHeight() or 768) * 0.04) / s)
	end
end

local function BuildHeader(f)
	local h = CreateFrame("Frame", nil, f)
	h:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	h:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	h:SetHeight(HEAD_H)
	h:EnableMouse(true)
	h:RegisterForDrag("LeftButton")
	h:SetScript("OnDragStart", function() f:StartMoving() end)
	h:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local point, _, relPoint, x, y = f:GetPoint(1)
		if point then
			A.db.profile.anchors.__options = { point = point, relPoint = relPoint,
				x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
		end
	end)
	f.head = h

	h.glyph = h:CreateTexture(nil, "ARTWORK")
	h.glyph:SetTexture(Media.texture.icon)
	h.glyph:SetSize(26, 26)
	h.glyph:SetPoint("LEFT", h, "LEFT", 24, 0)

	h.brand = W.Text(h, "opBrand", "LEFT")
	h.brand:SetPoint("LEFT", h.glyph, "RIGHT", 14, 0)
	h.brand:SetText(Media:Track(L.options.map.brand:upper(), 1))

	h.version = A.Glass.CreatePanel(h, { corner = 9 })
	h.version:SetHeight(18)
	h.version:SetPoint("LEFT", h.brand, "RIGHT", 14, 0)
	h.version.text = W.Text(h.version, "opChip", "CENTER")
	h.version.text:SetPoint("CENTER", h.version, "CENTER", 0, 0)

	h.close = W.CloseButton(h, { onClick = function() OW:Close() end })
	h.close:SetPoint("RIGHT", h, "RIGHT", -18, 0)

	-- Profiles · <active>: the Profiles page.
	h.profile = A.Glass.CreatePanel(h, { frameType = "Button", corner = 14 })
	h.profile:SetHeight(28)
	h.profile:SetPoint("RIGHT", h.close, "LEFT", -14, 0)
	h.profile.text = W.Text(h.profile, "opProfile", "CENTER")
	h.profile.text:SetPoint("CENTER", h.profile, "CENTER", 0, 0)
	h.profile:SetScript("OnClick", function() OW:Go("profiles") end)

	-- The search field, with its `/` chip.
	local s = A.Glass.CreatePanel(h, { frameType = "Button", corner = 14 })
	s:SetSize(300, 32)
	s:SetPoint("RIGHT", h.profile, "LEFT", -14, 0)
	s.lens = s:CreateTexture(nil, "ARTWORK")
	s.lens:SetTexture(Media.texture.ring)
	s.lens:SetSize(12, 12)
	s.lens:SetPoint("LEFT", s, "LEFT", 13, 1)
	local box = CreateFrame("EditBox", nil, s)
	box:SetPoint("LEFT", s, "LEFT", 34, 0)
	box:SetPoint("RIGHT", s, "RIGHT", -34, 0)
	box:SetHeight(32)
	box:SetAutoFocus(false)
	Media:SetFont(box, "opSearch")
	box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		OW:OpenResult(1)
	end)
	box:SetScript("OnTextChanged", function(self) OW:Search(self:GetText()) end)
	box:SetScript("OnEditFocusGained", function() OW:PaintSearch() end)
	box:SetScript("OnEditFocusLost", function() OW:PaintSearch() end)
	s.box = box
	s.placeholder = W.Text(s, "opSearch", "LEFT")
	s.placeholder:SetPoint("LEFT", box, "LEFT", 0, 0)
	s.placeholder:SetText(L.options.map.search)
	s.key = A.Glass.CreatePanel(s, { corner = 5 })
	s.key:SetSize(16, 16)
	s.key:SetPoint("RIGHT", s, "RIGHT", -10, 0)
	s.key.text = W.Text(s.key, "opChip", "CENTER")
	s.key.text:SetPoint("CENTER", s.key, "CENTER", 0, 0)
	s.key.text:SetText("/")
	s:SetScript("OnClick", function() box:SetFocus() end)
	h.search = s

	h.rule = Hairline(f)
	h.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEAD_H)
	h.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEAD_H)
	return h
end

local function BuildFooter(f)
	local foot = CreateFrame("Frame", nil, f)
	foot:SetHeight(16)
	foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 10)
	foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 10)
	foot.text = W.Text(foot, "opFoot", "RIGHT")
	foot.text:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
	foot.text:SetText("discord.gg/drveoj")
	foot.dot = foot:CreateTexture(nil, "ARTWORK")
	foot.dot:SetTexture(Media.texture.chipDisc)
	foot.dot:SetSize(7, 7)
	foot.dot:SetPoint("RIGHT", foot.text, "LEFT", -6, 0)
	f.foot = foot
end

--- The search's results, under the field.
local RESULT_H, RESULTS = 28, 8

local function BuildResults(f)
	local r = A.Glass.CreatePanel(f, { corner = 12, shadow = A.db.profile.glass.shadow })
	r:SetFrameLevel(f:GetFrameLevel() + 40)
	r:SetWidth(360)
	r:SetPoint("TOPRIGHT", f.head.search, "BOTTOMRIGHT", 0, -6)
	r:Hide()
	r.rows = {}
	for i = 1, RESULTS do
		local b = CreateFrame("Button", nil, r)
		b:SetHeight(RESULT_H)
		b:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -6 - (i - 1) * RESULT_H)
		b:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -6 - (i - 1) * RESULT_H)
		b.hl = b:CreateTexture(nil, "BACKGROUND")
		b.hl:SetTexture(Media.texture.flat)
		b.hl:SetAllPoints(b)
		b.hl:SetAlpha(0)
		b.name = W.Text(b, "opControl", "LEFT")
		b.name:SetPoint("LEFT", b, "LEFT", 8, 0)
		b.name:SetPoint("RIGHT", b, "RIGHT", -130, 0)
		b.name:SetWordWrap(false)
		b.where = W.Text(b, "opHelp", "RIGHT")
		b.where:SetPoint("RIGHT", b, "RIGHT", -8, 0)
		b:SetScript("OnEnter", function(self) self.hl:SetAlpha(1) end)
		b:SetScript("OnLeave", function(self) self.hl:SetAlpha(0) end)
		b:SetScript("OnClick", function() OW:OpenResult(i) end)
		r.rows[i] = b
	end
	f.results = r
end

--- The card over a hovered node.
local function BuildCard(f)
	local card = A.Glass.CreatePanel(f, { corner = 12, shadow = A.db.profile.glass.shadow })
	card:SetFrameLevel(f:GetFrameLevel() + 30)
	card:SetWidth(CARD_W)
	card:EnableMouse(false)
	card.title = W.Text(card, "opCardTitle", "LEFT")
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
	card.body = W.Text(card, "opCardBody", "LEFT")
	card.body:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
	card.body:SetWidth(CARD_W - 24)
	card.hint = W.Text(card, "opHelp", "LEFT")
	card.hint:SetPoint("TOPLEFT", card.body, "BOTTOMLEFT", 0, -6)
	card.hint:SetWidth(CARD_W - 24)
	card:Hide()
	f.card = card
end

-- A node on the map: its form, its label, a sub-label, a glow.
local function BuildNode(parent, n)
	local b = CreateFrame("Button", nil, parent)
	b:RegisterForClicks("LeftButtonUp")
	b:SetSize(n.w, n.h)
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetTexture(Media.texture.glow)
	b.glow:SetPoint("CENTER")
	b.glow:SetSize(n.w + 40, n.h + 40)
	b.glow:Hide()
	local form = n.form
	if form == "pill" or form == "square" or form == "strand" then
		local corner = form == "pill" and n.h / 2 or (form == "strand" and 6 or 9)
		b.body = A.Glass.CreatePanel(b, { corner = corner })
		b.body:SetAllPoints(b)
		b.body:EnableMouse(false)
	elseif form == "circle" then
		b.disc = b:CreateTexture(nil, "ARTWORK")
		b.disc:SetTexture(Media.texture.chipDisc)
		b.disc:SetAllPoints(b)
		b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
		b.ring:SetTexture(Media.texture.chipRim)
		b.ring:SetAllPoints(b)
	elseif form == "diamond" then
		b.d = C.Diamond(b, n.w)
		b.d.fill:SetPoint("CENTER", b, "CENTER", 0, 0)
	end
	if form == "strand" then
		-- The strand's shape: 4 px cells, 1 px apart.
		b.cells = {}
		for row = 1, n.rows do
			for col = 1, n.cols do
				local t = b:CreateTexture(nil, "OVERLAY")
				t:SetTexture(Media.texture.flat)
				t:SetSize(4, 4)
				t:SetPoint("TOPLEFT", b, "TOPLEFT", 5 + (col - 1) * 5, -5 - (row - 1) * 5)
				b.cells[#b.cells + 1] = t
			end
		end
	elseif form == "auras" then
		b.cells = {}
		for i = 1, 3 do
			local t = b:CreateTexture(nil, "OVERLAY")
			t:SetTexture(Media.texture.flat)
			t:SetSize(12, 12)
			t:SetPoint("LEFT", b, "LEFT", (i - 1) * 15, 0)
			b.cells[i] = t
		end
	end

	-- THE LABEL: inside a pill, square or circle; beside a diamond (toward
	-- the middle of the screen), a strand's shape or the aura squares.
	local left = (n.side or 1) < 0
	local just = "CENTER"
	if form == "diamond" then just = left and "RIGHT" or "LEFT"
	elseif form == "strand" or form == "auras" then just = "LEFT" end
	local style = (form == "strand" or form == "auras") and "opSub"
		or (n.big and "opNodeBig" or "opNode")
	b.label = W.Text(b, style, just)
	if form == "diamond" then
		if left then
			b.label:SetPoint("RIGHT", b, "LEFT", -10, 4)
		else
			b.label:SetPoint("LEFT", b, "RIGHT", 10, 4)
		end
	elseif form == "strand" then
		b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
	elseif form == "auras" then
		b.label:SetPoint("LEFT", b, "LEFT", 49, 0)
	else
		b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
	end
	b.label:SetText(n.label)

	-- The sub-pages it unfolds into, under it.
	local page = n.pageDef
	if page and #(page.groups or {}) > 1 and n.key ~= "targettarget" then
		local names = {}
		local tree = OW:Tree()
		for i = 2, #page.groups do
			local g = tree.args[page.groups[i]]
			if g then names[#names + 1] = C.Name(g) end
		end
		b.sub = W.Text(b, "opSub", form == "diamond" and just or "CENTER")
		if form == "diamond" then
			if left then
				b.sub:SetPoint("TOPRIGHT", b.label, "BOTTOMRIGHT", 0, -3)
			else
				b.sub:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -3)
			end
		else
			b.sub:SetPoint("TOP", b, "BOTTOM", 0, -6)
		end
		b.sub:SetText(table.concat(names, " \194\183 "))
	end

	b:SetScript("OnEnter", function(self) OW:Hover(n, true) end)
	b:SetScript("OnLeave", function(self) OW:Hover(n, false) end)
	b:SetScript("OnClick", function()
		if IsShiftKeyDown() then OW:UnlockPage(n.pageDef) else OW:Unfold(n) end
	end)
	n.button = b
	return b
end

--- A node's look: idle, hovered (filled accent, glow, dark label), lit by a
--  search, or off (hollow at 45 %).
function OW:PaintNode(n)
	local b = n.button
	if not b then return end
	local c = Palette.c
	local a = c.accent
	local tint = n.tint and c[n.tint] or a
	local hot = n.hovered or n.found
	local dark = { 20 / 255, 16 / 255, 31 / 255, 1 }
	if b.body then
		if hot then
			b.body:SetFillColor({ a[1], a[2], a[3], 1 })
			b.body:SetEdgeColor({ a[1], a[2], a[3], 1 })
		else
			b.body:SetFillColor(n.off and { NODE_FILL[1], NODE_FILL[2], NODE_FILL[3], 0 }
				or { NODE_FILL[1], NODE_FILL[2], NODE_FILL[3], 0.9 })
			b.body:SetEdgeColor({ tint[1], tint[2], tint[3], n.big and 1 or 0.6 })
		end
	elseif b.disc then
		W.Tint(b.disc, hot and a or NODE_FILL, hot and 1 or (n.off and 0 or 0.9))
		W.Tint(b.ring, a, hot and 1 or 0.7)
	elseif b.d then
		C.PaintDiamond(b.d, hot, 0.7)
		if n.off and not hot then W.Tint(b.d.fill, NODE_FILL, 0) end
	end
	for _, t in ipairs(b.cells or {}) do
		if n.form == "strand" then
			t:SetVertexColor(hot and dark[1] or a[1], hot and dark[2] or a[2], hot and dark[3] or a[3], hot and 1 or 0.6)
		else
			t:SetVertexColor(a[1], a[2], a[3], hot and 1 or 0.5)
		end
	end
	if hot and b.body then
		b.glow:Show()
		W.Tint(b.glow, a, 0.8)
	else
		b.glow:Hide()
	end
	local inside = b.body and n.form ~= "strand" or b.disc
	W.Color(b.label, (hot and inside) and dark or (n.tint and tint) or c.text)
	if b.sub then W.Color(b.sub, { c.text[1], c.text[2], c.text[3], 0.45 }) end
	b.__off = n.off and not hot
end

local function BuildMap(f)
	local m = CreateFrame("Frame", nil, f)
	m:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	m:SetSize(WIN_W, WIN_H)
	m:SetFrameLevel(f:GetFrameLevel() + 2)
	f.map = m

	-- The faint field of dots.
	m.dots = {}
	for y = MAP_T - 20 + FIELD_STEP / 2, SYS_Y - 70, FIELD_STEP do
		for x = FIELD_STEP / 2, WIN_W - FIELD_STEP / 2, FIELD_STEP do
			local d = m:CreateTexture(nil, "BACKGROUND")
			d:SetTexture(Media.texture.flat)
			d:SetSize(1.5, 1.5)
			d:SetPoint("CENTER", m, "TOPLEFT", x, -y)
			m.dots[#m.dots + 1] = d
		end
	end

	m.lines = {}
	m.system = {}
	m.sysLine = Line(m)
	m.sysLabel = W.Text(m, "opTag", "LEFT")
	m.sysLabel:SetPoint("LEFT", m, "TOPLEFT", SYS_L, -(SYS_Y - 19))
	m.sysLabel:SetText(Media:Track(L.options.map.system:upper(), 1))
	local count = 0
	for _, p in ipairs(OW.PAGES) do
		if p.system then count = count + 1 end
	end
	local i = 0
	for _, p in ipairs(OW.PAGES) do
		if p.system then
			i = i + 1
			local b = CreateFrame("Button", nil, m)
			b:SetSize(110, 40)
			local x = 160 + (i - 1) * ((SYS_R - 60 - 160) / math.max(1, count - 1))
			b:SetPoint("CENTER", m, "TOPLEFT", x, -(SYS_Y - 12))
			b.d = C.Diamond(b, 9)
			b.d.fill:SetPoint("CENTER", m, "TOPLEFT", x, -SYS_Y)
			b.label = W.Text(b, "opNode", "CENTER")
			b.label:SetPoint("BOTTOM", b.d.fill, "TOP", 0, 9)
			b.label:SetText(p.title)
			local node = { key = "sys:" .. p.key, page = p.key, pageDef = p, hop = 4,
				x = x, y = SYS_Y, w = 9, h = 9, form = "system", button = b, label = p.title }
			b:SetScript("OnEnter", function() OW:Hover(node, true) end)
			b:SetScript("OnLeave", function() OW:Hover(node, false) end)
			b:SetScript("OnClick", function() OW:Unfold(node) end)
			m.system[#m.system + 1] = node
		end
	end
end

function OW:PaintSystem()
	local c = Palette.c
	local a = c.accent
	local m = self.frame.map
	SetLine(m.sysLine, m, SYS_L, SYS_Y, SYS_R, SYS_Y, 1, 0.35)
	W.Color(m.sysLabel, { a[1], a[2], a[3], 0.5 })
	for _, n in ipairs(m.system) do
		local b = n.button
		local hot = n.hovered or n.found
		local unread = n.pageDef.news and self:NewsUnread()
		if unread and not hot then
			C.PaintDiamond(b.d, false, 1)
			W.Tint(b.d.rim, c.info or a, 1)
			b.d.glow:Show()
			W.Tint(b.d.glow, c.info or a, 0.8)
		else
			C.PaintDiamond(b.d, true)
			if not hot then b.d.glow:Hide() end
		end
		W.Color(b.label, hot and a or { c.text[1], c.text[2], c.text[3], 0.85 })
	end
	for _, d in ipairs(m.dots) do d:SetVertexColor(a[1], a[2], a[3], 0.18) end
end

--- What's new, unread: the Toolbox keeps the record.
function OW:NewsUnread()
	local TB = A:GetModule("toolbox")
	return TB and TB.NewsUnread and TB:NewsUnread() or false
end

--- Lay the map out from the HUD as it is now: nodes, bonds, trunks.
function OW:LayMap()
	local m = self.frame.map
	for _, n in ipairs(self.nodes or {}) do
		if n.button then n.button:Hide() end
	end
	self.nodes = self:Spec()
	-- Built per open, pooled by key: a strand whose shape changed is built
	-- again, everything else is reused.
	self.pool = self.pool or {}
	for _, n in ipairs(self.nodes) do
		local sig = n.key .. ":" .. (n.cols or 0) .. "x" .. (n.rows or 0) .. ":" .. (n.side or 0)
		local b = self.pool[sig]
		if b then
			n.button = b
			b:SetScript("OnEnter", function() OW:Hover(n, true) end)
			b:SetScript("OnLeave", function() OW:Hover(n, false) end)
			b:SetScript("OnClick", function()
				if IsShiftKeyDown() then OW:UnlockPage(n.pageDef) else OW:Unfold(n) end
			end)
			b.label:SetText(n.label)
		else
			self.pool[sig] = BuildNode(m, n)
		end
		n.button:Show()
		self:PaintNode(n)
	end

	-- The bonds: the axis, each node to its parent, the dashed hairline up
	-- to the nameplates, the two trunks.
	local by = self.byKey
	local lines = {}
	local function bond(x1, y1, x2, y2, thick, alpha, hop, dashed)
		lines[#lines + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, thick = thick, alpha = alpha,
			hop = hop, dashed = dashed }
	end
	local p, t = by.player, by.target
	local ax, ay = p and t and (p.x + t.x) / 2, p and t and (p.y + t.y) / 2
	if p and t then bond(p.x, p.y, t.x, t.y, 1.5, 0.9, 1) end
	for _, n in ipairs(self.nodes) do
		if n.parent == "spine" and ax then
			bond(ax, ay, n.x, n.y, 1, 0.4, n.hop)
		elseif n.parent and by[n.parent] and not (n.key == "target" and n.parent == "player") then
			local o = by[n.parent]
			bond(o.x, o.y, n.x, n.y, 1, 0.4, n.hop)
		end
	end
	local np = by.nameplates
	if np and ax then bond(ax, ay, np.x, np.y, 1, 0.25, 2, true) end
	local tb = by.toolbox
	if tb then
		bond(tb.x, math.max(MAP_T, tb.y - 120), tb.x, math.min(MAP_B, tb.y + 150), 1.5, 0.5, 3)
	end
	local mm, q = by.minimap, by.quests
	if mm and q then
		bond(mm.x, mm.y + 30, mm.x, math.min(MAP_B, q.y + 140), 1.5, 0.5, 3)
	end
	self.bonds = lines
	m.pool = m.pool or {}
	local used = 0
	for _, l in ipairs(lines) do
		if l.dashed then
			local dx, dy = l.x2 - l.x1, l.y2 - l.y1
			local len = math.sqrt(dx * dx + dy * dy)
			local steps = math.floor(len / 8)
			l.parts = {}
			for k = 0, steps - 1 do
				used = used + 1
				local seg = m.pool[used] or Line(m, "BACKGROUND")
				m.pool[used] = seg
				local s0, s1 = k * 8 / len, math.min(1, (k * 8 + 2) / len)
				l.parts[#l.parts + 1] = { seg = seg, s0 = s0, s1 = s1 }
			end
		else
			used = used + 1
			local seg = m.pool[used] or Line(m, "BACKGROUND")
			m.pool[used] = seg
			l.parts = { { seg = seg, s0 = 0, s1 = 1 } }
		end
	end
	for k = used + 1, #m.pool do m.pool[k]:Hide() end
	self:PaintSystem()
end

--- Draw one bond `grown` of the way along (0 to 1), at `alpha` of its own.
local function DrawBond(m, l, grown, alpha)
	for _, part in ipairs(l.parts) do
		local s0, s1 = part.s0, math.min(part.s1, grown)
		local seg = part.seg
		if s1 <= s0 or alpha <= 0 then
			seg:Hide()
		else
			local x1, y1 = l.x1 + (l.x2 - l.x1) * s0, l.y1 + (l.y2 - l.y1) * s0
			local x2, y2 = l.x1 + (l.x2 - l.x1) * s1, l.y1 + (l.y2 - l.y1) * s1
			SetLine(seg, m, x1, y1, x2, y2, l.thick, l.alpha * alpha)
			seg:Show()
		end
	end
end

-- ---------------------------------------------------------------------------
-- the nav strand (7b)
-- ---------------------------------------------------------------------------

local NAV_FORM = {
	pill = { 24, 20 }, square = { 20, 20 }, diamond = { 16, 16 }, circle = { 20, 20 },
}

--- Every page's slot on the strand: the modules in map order, a hairline,
--  then the System pages that open a page.
function OW:NavSlots()
	if self.slots then return self.slots end
	local slots, y = {}, NAV_TOP + 50
	local hairY
	for _, p in ipairs(self.PAGES) do
		if not p.system then
			slots[p.key] = y
			y = y + NAV_STEP
		end
	end
	hairY = y - NAV_STEP / 2 + 12
	y = hairY + 24
	for _, p in ipairs(self.PAGES) do
		if p.system and not p.action then
			slots[p.key] = y
			y = y + NAV_STEP
		end
	end
	slots.__hair = hairY
	self.slots = slots
	return slots
end

local function BuildNav(f)
	local nav = CreateFrame("Frame", nil, f)
	nav:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	nav:SetSize(NAV_W, WIN_H)
	nav:SetFrameLevel(f:GetFrameLevel() + 3)
	f.nav = nav
	local slots = OW:NavSlots()

	nav.strand = Line(nav)
	nav.stub = Line(nav)
	nav.hair = W.Hairline(nav)
	nav.hair:SetWidth(24)
	nav.hair:SetPoint("CENTER", nav, "TOPLEFT", NAV_X, -slots.__hair)

	-- The root: the junction glyph, hollow. The map.
	local root = CreateFrame("Button", nil, nav)
	root:SetSize(28, 28)
	root:SetPoint("CENTER", nav, "TOPLEFT", NAV_X, -NAV_TOP)
	root.v = Line(root)
	root.h = Line(root)
	root.ring = root:CreateTexture(nil, "ARTWORK")
	root.ring:SetTexture(Media.texture.diamondRim)
	root.ring:SetSize(16, 16)
	root.ring:SetPoint("CENTER")
	root.tag = A.Glass.CreatePanel(root, { corner = 6 })
	root.tag:SetSize(46, 20)
	root.tag:SetPoint("LEFT", root, "RIGHT", 6, 0)
	root.tag.text = W.Text(root.tag, "opTag", "CENTER")
	root.tag.text:SetPoint("CENTER", root.tag, "CENTER", 0, 0)
	root.tag.text:SetText(Media:Track(L.options.map.map:upper(), 1))
	root.tag:Hide()
	root:SetScript("OnEnter", function(self) self.tag:Show() end)
	root:SetScript("OnLeave", function(self) self.tag:Hide() end)
	root:SetScript("OnClick", function() OW:Fold() end)
	nav.root = root

	nav.nodes = {}
	for _, p in ipairs(OW.PAGES) do
		local y = slots[p.key]
		if y then
			local size = p.system and { 8, 8 } or NAV_FORM[p.form] or { 20, 20 }
			local b = CreateFrame("Button", nil, nav)
			b:SetSize(math.max(24, size[1]), math.max(24, size[2]))
			b:SetPoint("CENTER", nav, "TOPLEFT", NAV_X, -y)
			if p.system or p.form == "diamond" then
				b.d = C.Diamond(b, size[1] + (p.system and 1 or 0))
				b.d.fill:SetPoint("CENTER", b, "CENTER", 0, 0)
			elseif p.form == "circle" then
				b.disc = b:CreateTexture(nil, "ARTWORK")
				b.disc:SetTexture(Media.texture.chipDisc)
				b.disc:SetSize(size[1], size[2])
				b.disc:SetPoint("CENTER")
				b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
				b.ring:SetTexture(Media.texture.chipRim)
				b.ring:SetAllPoints(b.disc)
			else
				b.body = A.Glass.CreatePanel(b, { corner = p.form == "pill" and 10 or 6 })
				b.body:SetSize(size[1], size[2])
				b.body:SetPoint("CENTER")
				b.body:EnableMouse(false)
			end
			b.glow = b:CreateTexture(nil, "BACKGROUND")
			b.glow:SetTexture(Media.texture.glow)
			b.glow:SetSize(size[1] + 30, size[2] + 30)
			b.glow:SetPoint("CENTER")
			b:SetScript("OnEnter", function(self) W.Tooltip(self, "ANCHOR_RIGHT", p.title) end)
			b:SetScript("OnLeave", function() W.HideTooltip() end)
			b:SetScript("OnClick", function() OW:Go(p.key) end)
			b.page = p
			b.y = y
			nav.nodes[p.key] = b
		end
	end
end

function OW:PaintNav()
	local nav = self.frame.nav
	local c = Palette.c
	local a = c.accent
	local slots = self:NavSlots()
	local last = 0
	for _, y in pairs(slots) do last = math.max(last, y) end
	SetLine(nav.strand, nav, NAV_X, NAV_TOP - 2, NAV_X, last + 24, 1.5, 0.45)
	local stubY = self.stubY or (self.page and slots[self.page.key]) or NAV_TOP
	SetLine(nav.stub, nav, NAV_X, stubY, NAV_W, stubY, 1.5, 1)
	nav.stub:SetShown(self.page ~= nil)
	local root = nav.root
	SetLine(root.v, root, 14, 2, 14, 26, 1.5, 0.5)
	SetLine(root.h, root, 2, 14, 26, 14, 1.5, 0.5)
	W.Tint(root.ring, a, 1)
	root.tag:SetFillColor({ NODE_FILL[1], NODE_FILL[2], NODE_FILL[3], 0.95 })
	root.tag:SetEdgeColor({ a[1], a[2], a[3], 0.3 })
	W.Color(root.tag.text, a)
	for key, b in pairs(nav.nodes) do
		local p = b.page
		local on = self.page and self.page.key == key
		local tint = p.tint and c[p.tint] or a
		if b.d then
			C.PaintDiamond(b.d, on, 0.5)
			if p.system and not on then W.Tint(b.d.fill, a, 0.5) end
		elseif b.disc then
			W.Tint(b.disc, on and a or NODE_FILL, on and 1 or 0.9)
			W.Tint(b.ring, a, on and 1 or 0.5)
		elseif b.body then
			b.body:SetFillColor(on and { a[1], a[2], a[3], 1 } or { NODE_FILL[1], NODE_FILL[2], NODE_FILL[3], 0 })
			b.body:SetEdgeColor(on and { a[1], a[2], a[3], 1 } or { tint[1], tint[2], tint[3], 0.6 })
		end
		b.glow:SetShown(on and true or false)
		if on then W.Tint(b.glow, a, 0.8) end
	end
	W.PaintHairline(nav.hair)
end

-- ---------------------------------------------------------------------------
-- the page
-- ---------------------------------------------------------------------------

local function BuildPageFrame(f)
	local pg = CreateFrame("Frame", nil, f)
	pg:SetPoint("TOPLEFT", f, "TOPLEFT", NAV_W, -HEAD_H)
	pg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	pg:SetFrameLevel(f:GetFrameLevel() + 4)
	pg:Hide()
	f.pageFrame = pg

	pg.title = W.Text(pg, "opTitle", "LEFT")
	pg.title:SetPoint("TOPLEFT", pg, "TOPLEFT", PAD_L, -PAD_T)
	pg.desc = W.Text(pg, "opDesc", "LEFT")
	pg.desc:SetPoint("BOTTOMLEFT", pg.title, "BOTTOMRIGHT", 12, 2)

	-- The sub-pages, as small chips to the right of the title.
	pg.tabs = {}

	-- The live preview (Unit frames).
	local pv = A.Glass.CreatePanel(pg, { corner = 18 })
	pv:SetPoint("TOPLEFT", pg, "TOPLEFT", PAD_L, -(PAD_T + 40))
	pv:SetPoint("TOPRIGHT", pg, "TOPRIGHT", -PAD_R, -(PAD_T + 40))
	pv:SetHeight(PREVIEW_H)
	pv.tag = W.Text(pv, "opTag", "LEFT")
	pv.tag:SetPoint("TOPLEFT", pv, "TOPLEFT", 14, -12)
	pv.tag:SetText(Media:Track(L.options.map.preview:upper(), 1))
	pv:Hide()
	pg.preview = pv

	pg.scroll = W.Scroller(pg, 48, { well = false })
	pg.foot = CreateFrame("Frame", nil, pg)
	pg.foot:SetHeight(32)
	pg.foot:SetPoint("BOTTOMLEFT", pg, "BOTTOMLEFT", PAD_L, PAD_B + 8)
	pg.foot:SetPoint("BOTTOMRIGHT", pg, "BOTTOMRIGHT", -PAD_R, PAD_B + 8)

	local function Pill(text, fn)
		local b = A.Glass.CreatePanel(pg.foot, { frameType = "Button", corner = 15 })
		b:SetHeight(30)
		b.text = W.Text(b, "opButton", "CENTER")
		b.text:SetPoint("CENTER", b, "CENTER", 6, 0)
		b:SetScript("OnClick", fn)
		b:SetScript("OnEnter", function(self) self.over = true OW:PaintPage() end)
		b:SetScript("OnLeave", function(self) self.over = nil OW:PaintPage() end)
		return b
	end
	pg.unlock = Pill("", function() OW:UnlockPage(OW.page) end)
	pg.unlock.icon = pg.unlock:CreateTexture(nil, "OVERLAY")
	pg.unlock.icon:SetTexture(Media.texture.diamondRim)
	pg.unlock.icon:SetSize(9, 9)
	pg.unlock.icon:SetPoint("RIGHT", pg.unlock.text, "LEFT", -8, 0)
	pg.unlock:SetPoint("LEFT", pg.foot, "LEFT", 0, 0)
	pg.reset = Pill(L.options.map.reset_page, function() OW:ResetPage() end)
	pg.reset.text:SetPoint("CENTER", pg.reset, "CENTER", 0, 0)
end

--- The preview: the player and the target as they are, with the bond and a
--  cast lane between - a miniature of the real thing, from real data.
local function BuildPreview(pv)
	local function capsule(right)
		local cap = A.Glass.CreatePanel(pv, { corner = 27 })
		cap:SetSize(300, 54)
		cap.orb = cap:CreateTexture(nil, "ARTWORK")
		cap.orb:SetTexture(Media.texture.chipDisc)
		cap.orb:SetSize(44, 44)
		cap.orb:SetPoint(right and "RIGHT" or "LEFT", cap, right and "RIGHT" or "LEFT", right and -5 or 5, 0)
		cap.level = W.Text(cap, "opChip", "CENTER")
		cap.level:SetPoint("CENTER", cap.orb, "CENTER", 0, 0)
		cap.name = W.Text(cap, "opCardTitle", right and "RIGHT" or "LEFT")
		cap.name:SetPoint(right and "TOPRIGHT" or "TOPLEFT", cap, right and "TOPRIGHT" or "TOPLEFT", right and -60 or 60, -9)
		cap.track = cap:CreateTexture(nil, "ARTWORK")
		cap.track:SetTexture(Media.texture.flat)
		cap.track:SetSize(220, 7)
		cap.track:SetPoint(right and "TOPRIGHT" or "TOPLEFT", cap, right and "TOPRIGHT" or "TOPLEFT", right and -60 or 60, -29)
		cap.health = cap:CreateTexture(nil, "ARTWORK", nil, 1)
		cap.health:SetTexture(Media.texture.flat)
		cap.health:SetHeight(7)
		cap.health:SetPoint(right and "RIGHT" or "LEFT", cap.track, right and "RIGHT" or "LEFT", 0, 0)
		cap.ptrack = cap:CreateTexture(nil, "ARTWORK")
		cap.ptrack:SetTexture(Media.texture.flat)
		cap.ptrack:SetSize(220, 4)
		cap.ptrack:SetPoint("TOP", cap.track, "BOTTOM", 0, -5)
		cap.power = cap:CreateTexture(nil, "ARTWORK", nil, 1)
		cap.power:SetTexture(Media.texture.flat)
		cap.power:SetHeight(4)
		cap.power:SetPoint(right and "RIGHT" or "LEFT", cap.ptrack, right and "RIGHT" or "LEFT", 0, 0)
		return cap
	end
	pv.player = capsule(false)
	pv.player:SetPoint("RIGHT", pv, "CENTER", -100, -6)
	pv.target = capsule(true)
	pv.target:SetPoint("LEFT", pv, "CENTER", 100, -6)
	pv.lane1 = Line(pv)
	pv.lane2 = Line(pv)
	pv.cast = Line(pv)
end

function OW:PaintPreview()
	local pv = self.frame.pageFrame.preview
	if not pv.player then BuildPreview(pv) end
	local c = Palette.c
	local cfg = A.Config:Module("unitframes")
	local a = c.accent
	local function fill(cap, unit, right)
		local exists = UnitExists(unit)
		cap:SetAlpha(exists and 1 or 0.4)
		cap:SetFillColor({ NODE_FILL[1], NODE_FILL[2], NODE_FILL[3], 0.72 })
		local rim = a
		if right and cfg.reactionTint ~= false and exists then rim = Flat(Palette:ReactionEdge(unit) or a) end
		cap:SetEdgeColor({ rim[1], rim[2], rim[3], right and 1 or 0.4 })
		cap.name:SetText(exists and (UnitName(unit) or "") or L.options.map.no_target)
		W.Color(cap.name, right and exists and (Palette:NameReaction(unit) or c.text) or c.text)
		local lv = exists and UnitLevel(unit) or nil
		cap.level:SetText(lv and lv > 0 and tostring(lv) or "")
		W.Color(cap.level, c.text)
		local portrait = cfg.showPortrait ~= false
		cap.orb:SetShown(portrait)
		cap.level:SetShown(portrait)
		local oc = Flat(exists and (Palette:OrbBaseColor(unit) or a) or a)
		cap.orb:SetVertexColor(oc[1], oc[2], oc[3], 1)
		local hp = exists and (UnitHealthMax(unit) or 0) > 0 and UnitHealth(unit) / UnitHealthMax(unit) or 0
		local hc = Flat(exists and (Palette:HealthColor(unit) or c.friendly) or c.friendly)
		cap.track:SetVertexColor(1, 1, 1, 0.13)
		cap.health:SetWidth(math.max(0.01, 220 * hp))
		cap.health:SetVertexColor(hc[1], hc[2], hc[3], 1)
		local showPower = cfg.showPower ~= false
		local pm = exists and (UnitPowerMax(unit) or 0) or 0
		local pp = pm > 0 and (UnitPower(unit) or 0) / pm or 0
		local pc = Flat(exists and Palette:PowerColor(unit) or c.info or a)
		cap.ptrack:SetShown(showPower)
		cap.power:SetShown(showPower and pp > 0)
		cap.ptrack:SetVertexColor(1, 1, 1, 0.1)
		cap.power:SetWidth(math.max(0.01, 220 * pp))
		cap.power:SetVertexColor(pc[1], pc[2], pc[3], 1)
	end
	fill(pv.player, "player", false)
	fill(pv.target, "target", true)
	local cx, cy = pv:GetWidth() / 2, PREVIEW_H / 2 + 6
	SetLine(pv.lane1, pv, cx - 100, cy - 3, cx + 100, cy - 3, 1, 0.3)
	SetLine(pv.lane2, pv, cx - 100, cy + 3, cx + 100, cy + 3, 1, 0.3)
	local ca = Flat(c.cast or c.info or a)
	pv.cast:SetStartPoint("TOPLEFT", pv, cx - 100, -(cy - 3))
	pv.cast:SetEndPoint("TOPLEFT", pv, cx + 20, -(cy - 3))
	pv.cast:SetThickness(4)
	pv.cast:SetColorTexture(ca[1], ca[2], ca[3], 1)
	pv:SetFillColor({ 0, 0, 0, 0.25 })
	pv:SetEdgeColor({ a[1], a[2], a[3], 0.18 })
	W.Color(pv.tag, { a[1], a[2], a[3], 0.5 })
end

--- The view for one sub-page, built the first time it is shown.
function OW:View(page, i)
	local subs = self:Subs(page)
	local sub = subs[i] or subs[1]
	if not sub then return nil end
	local key = page.key .. "/" .. (sub.subKey or sub.groupKey)
	local v = self.views[key]
	if not v then
		local pg = self.frame.pageFrame
		local width = WIN_W - NAV_W - PAD_L - PAD_R - 16
		v = C.View(pg.scroll.child, sub.group, width)
		v.sub = sub
		self.views[key] = v
	end
	return v, sub
end

--- Lay the page out: title, sub-page chips, preview, body, the two buttons.
function OW:ShowPage(page, i)
	local pg = self.frame.pageFrame
	self.page, self.sub = page, i or 1
	pg.title:SetText(page.title)
	pg.desc:SetText(page.desc or "")

	-- SUB-PAGES AS NODES ON A STRAND, not tabs (Joe: tabs are not Lattice):
	-- a diamond each, its name beside it, the strand through them all. Only
	-- when there are several.
	local subs = self:Subs(page)
	for _, t in ipairs(pg.tabs) do t:Hide() end
	pg.subLinks = pg.subLinks or {}
	for _, l in ipairs(pg.subLinks) do l:Hide() end
	local x, y = PAD_L + 6, PAD_T + 44
	if #subs > 1 then
		for k, s in ipairs(subs) do
			local t = pg.tabs[k]
			if not t then
				t = CreateFrame("Button", nil, pg)
				t:SetHeight(20)
				t.d = C.Diamond(t, 11)
				t.d.fill:SetPoint("LEFT", t, "LEFT", 0, 0)
				t.text = W.Text(t, "opHelp", "LEFT")
				t.text:SetPoint("LEFT", t, "LEFT", 19, 0)
				pg.tabs[k] = t
			end
			t.text:SetText(s.label)
			local w = 19 + math.ceil(t.text:GetStringWidth() or 40)
			t:SetWidth(w)
			t:ClearAllPoints()
			t:SetPoint("LEFT", pg, "TOPLEFT", x - 5.5, -y)
			t:SetScript("OnClick", function() OW:ShowPage(page, k) end)
			t.index = k
			t:Show()
			-- The strand from the last name's end to this node.
			if k > 1 then
				local l = pg.subLinks[k - 1] or Line(pg)
				pg.subLinks[k - 1] = l
				SetLine(l, pg, pg.subEnd + 6, y, x - 9, y, 1, 0.3)
				l:Show()
			end
			pg.subEnd = x - 5.5 + w
			x = x + w + 30
		end
	end
	local top = PAD_T + 34 + (#subs > 1 and 34 or 0)

	-- The preview strip, where there is one.
	local pv = pg.preview
	pv:ClearAllPoints()
	pv:SetPoint("TOPLEFT", pg, "TOPLEFT", PAD_L, -top)
	pv:SetPoint("TOPRIGHT", pg, "TOPRIGHT", -PAD_R, -top)
	pv:SetShown(page.preview and true or false)
	if page.preview then
		self:PaintPreview()
		top = top + PREVIEW_H + 18
	end

	-- The body.
	for _, v in pairs(self.views) do v.frame:Hide() end
	local v = self:View(page, self.sub)
	local sc = pg.scroll
	sc:ClearAllPoints()
	sc:SetPoint("TOPLEFT", pg, "TOPLEFT", PAD_L, -top)
	sc:SetPoint("BOTTOMRIGHT", pg, "BOTTOMRIGHT", -PAD_R + 8, PAD_B + 50)
	if v then
		v.frame:ClearAllPoints()
		v.frame:SetPoint("TOPLEFT", sc.child, "TOPLEFT", 0, 0)
		v:Refresh()
		v.frame:Show()
		sc.child:SetSize(v.frame:GetWidth(), math.max(1, v.height + 12))
		self.view = v
	end
	sc:SetVerticalScroll(0)
	sc:Clamp()

	pg.unlock:SetShown(page.unlock ~= nil or page.bars == true)
	pg.unlock.text:SetText(A.F(L.options.map.unlock_s, page.title))
	pg.unlock:SetWidth(math.ceil(pg.unlock.text:GetStringWidth() or 80) + 50)
	pg.reset:ClearAllPoints()
	if pg.unlock:IsShown() then
		pg.reset:SetPoint("LEFT", pg.unlock, "RIGHT", 10, 0)
	else
		pg.reset:SetPoint("LEFT", pg.foot, "LEFT", 0, 0)
	end
	pg.reset.text:SetText(L.options.map.reset_page)
	pg.reset:SetWidth(math.ceil(pg.reset.text:GetStringWidth() or 80) + 36)

	if page.news then self:MarkNewsRead() end
	self:PaintPage()
	self:PaintNav()
end

function OW:MarkNewsRead()
	local TB = A:GetModule("toolbox")
	if TB and TB.MarkNewsRead then TB:MarkNewsRead() end
end

function OW:PaintPage()
	local pg = self.frame and self.frame.pageFrame
	if not (pg and self.page) then return end
	local c = Palette.c
	local a = c.accent
	W.Color(pg.title, c.text)
	W.Color(pg.desc, { c.text[1], c.text[2], c.text[3], 0.55 })
	for _, t in ipairs(pg.tabs) do
		if t:IsShown() then
			local on = t.index == self.sub
			C.PaintDiamond(t.d, on, 0.5)
			local l = pg.subLinks and pg.subLinks[t.index]
			if l and l:IsShown() then l:SetColorTexture(a[1], a[2], a[3], 0.3) end
			W.Restyle(t.text, on and "opHelpOn" or "opHelp")
			W.Color(t.text, on and c.text or c.textDim)
			t.on = on
		end
	end
	for _, b in ipairs({ pg.unlock, pg.reset }) do
		b:SetFillColor(b.over and { a[1], a[2], a[3], 0.12 } or { 1, 1, 1, 0.02 })
		b:SetEdgeColor({ a[1], a[2], a[3], b == pg.unlock and 0.35 or 0.2 })
	end
	W.Color(pg.unlock.text, c.text)
	W.Color(pg.reset.text, { c.text[1], c.text[2], c.text[3], 0.6 })
	-- Live only when there is something to put back.
	local dirty = self:PageDirty()
	pg.reset:SetAlpha(dirty and 1 or 0.35)
	pg.reset:EnableMouse(dirty)
	W.Tint(pg.unlock.icon, a, 1)
	if self.page.preview then self:PaintPreview() end
end

--- A setting's default, from the config's own defaults.
local function Default(path)
	local d = A.Config.defaults and A.Config.defaults.profile
	-- Not `and ... or nil`: a default of false would come out nil.
	for i = 1, #path do
		if type(d) == "table" then d = d[path[i]] else return nil end
	end
	return d
end

local function Same(a, b)
	if type(a) == "table" and type(b) == "table" then
		for k, v in pairs(a) do if b[k] ~= v then return false end end
		for k, v in pairs(b) do if a[k] ~= v then return false end end
		return true
	end
	return a == b
end

--- Whether anything on the sub-page in view is off its default: what Reset
--  page has to do. Nothing, and it is dimmed (Joe: What's new has nothing
--  to reset).
function OW:PageDirty()
	local v = self.view
	if not v then return false end
	for _, n in ipairs(C.Leaves(v.sub.group)) do
		local path = n.arg and n.arg.path
		if path then
			local t, k = A.Options.Resolve(path)
			if t and k ~= nil and not Same(t[k], Default(path)) then return true end
		end
	end
	return false
end

--- Back to the module's defaults, for every setting on the page's sub-page in
--  view. Only what has a path; buttons and the profile calls are left alone.
function OW:ResetPage()
	if not self.page or InCombatLockdown() then return false end
	local v = self.view
	if not v then return false end
	local defaults = A.Config.defaults and A.Config.defaults.profile
	local enabled = {}
	local any = false
	for _, n in ipairs(C.Leaves(v.sub.group)) do
		local path = n.arg and n.arg.path
		if path and defaults then
			local t, k = A.Options.Resolve(path)
			local d = Default(path)
			if t and k ~= nil then
				if type(d) == "table" then
					local copy = {}
					for kk, vv in pairs(d) do copy[kk] = vv end
					d = copy
				end
				t[k] = d
				any = true
				if #path == 3 and path[1] == "modules" and path[3] == "enabled" and A.modules[path[2]] then
					enabled[path[2]] = d and true or false
				end
			end
		end
	end
	for name, on in pairs(enabled) do A:SetModuleEnabled(name, on) end
	if any then
		A:Restyle()
		A:Reconfigure()
	end
	self:AfterWrite()
	return any
end

-- ---------------------------------------------------------------------------
-- hovering
-- ---------------------------------------------------------------------------

--- A highlight's alpha toward where it is going: in over 120 ms, out over
--  200 ms (7c), then hidden.
local function FadeLight(h, dt)
	local a = h:GetAlpha() or 0
	if h.want > a then
		a = math.min(h.want, a + dt / 0.12)
	else
		a = math.max(h.want, a - dt / 0.2)
	end
	h:SetAlpha(a)
	if a == h.want then
		h:SetScript("OnUpdate", nil)
		if a <= 0 then h:Hide() end
	end
end

local function WantLight(h, want)
	h.want = want
	if not h:IsShown() then
		if want <= 0 then return end
		h:SetAlpha(0)
		h:Show()
	end
	h:SetScript("OnUpdate", FadeLight)
end

--- The world highlight: an accent rim and glow on the real frame.
function OW:Light(frames)
	self.lights = self.lights or {}
	local used = 0
	for _, f in ipairs(frames or {}) do
		if f and f.IsShown and f:IsShown() then
			used = used + 1
			local h = self.lights[used]
			if not h then
				h = A.Glass.CreatePanel(UIParent, { corner = 14 })
				h:SetFrameStrata("HIGH")
				h:EnableMouse(false)
				h:Hide()
				self.lights[used] = h
			end
			local a = Palette.c.accent
			local fh = (f:GetHeight() or 20) * (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
			A.Glass.SetPanelCorner(h, math.min(30, fh / 2 + 3))
			h:SetFillColor({ a[1], a[2], a[3], 0.06 })
			h:SetEdgeColor({ a[1], a[2], a[3], 1 })
			h:SetRimGlow({ a[1], a[2], a[3], 0.6 })
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
			h:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
			WantLight(h, 1)
			h.target = f
		end
	end
	for k = used + 1, #self.lights do WantLight(self.lights[k], 0) end
	return used
end

--- Every highlight off at once: the window going, not the cursor moving.
function OW:Unlight()
	for _, h in ipairs(self.lights or {}) do
		h:SetScript("OnUpdate", nil)
		h.want = 0
		h:Hide()
	end
end

--- The real frames a node stands for.
function OW:RealFrames(n)
	if n.key == "player" then
		return { MoverFrame("player"), MoverFrame("target") }
	end
	if n.real then return { n.real } end
	if n.key == "quests" then
		local t = A.Trunk.list.world
		return { t and t.frame }
	end
	if n.key == "auras" then
		local Au = A:GetModule("auras")
		return { Au and Au.buffs, Au and Au.debuffs }
	end
	return {}
end

function OW:Hover(n, on)
	n.hovered = on or nil
	if n.form == "system" then self:PaintSystem() else self:PaintNode(n) end
	local card = self.frame.card
	if not on then
		card:Hide()
		self:Light(nil)
		return
	end
	local p = n.pageDef
	self:Light(self:RealFrames(n))
	card.title:SetText(n.form == "system" and p.title or (n.key == "player" and p.title or n.label))
	local count = p.action and 0 or #self:Leaves(p)
	local body = p.desc or ""
	if count > 0 then body = body .. " \194\183 " .. A.F(L.options.map.settings_n, count) end
	card.body:SetText(body)
	local canUnlock = p.unlock or p.bars
	card.hint:SetText(p.action and L.options.map.hint_action
		or (canUnlock and L.options.map.hint_unlock or L.options.map.hint))
	local c = Palette.c
	local a = c.accent
	card:SetFillColor({ NODE_FILL[1], NODE_FILL[2], NODE_FILL[3], 0.95 })
	card:SetEdgeColor({ a[1], a[2], a[3], 0.4 })
	W.Color(card.title, c.text)
	W.Color(card.body, { c.text[1], c.text[2], c.text[3], 0.65 })
	W.Color(card.hint, { a[1], a[2], a[3], 0.6 })
	card:SetHeight(10 + 16 + 4 + math.ceil(card.body:GetStringHeight() or 14) + 6
		+ math.ceil(card.hint:GetStringHeight() or 12) + 10)
	card:ClearAllPoints()
	-- Above the node, kept inside the window.
	local x = math.max(16, math.min(WIN_W - CARD_W - 16, n.x - CARD_W / 2))
	local y = n.y - (n.h or 20) / 2 - 10
	if y - card:GetHeight() < HEAD_H + 8 then
		card:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -(n.y + (n.h or 20) / 2 + 10))
	else
		card:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", x, -y)
	end
	card:Show()
end

-- ---------------------------------------------------------------------------
-- search
-- ---------------------------------------------------------------------------

--- Every setting, once per open: its page, sub-page, leaf and the words it
--  can be found by.
function OW:Index()
	if self.index then return self.index end
	local out = {}
	for _, p in ipairs(self.PAGES) do
		if not p.action then
			for i, s in ipairs(self:Subs(p)) do
				for _, n in ipairs(C.Leaves(s.group)) do
					local name = C.Name(n)
					out[#out + 1] = { page = p, sub = i, node = n, name = name,
						where = (#self:Subs(p) > 1) and (p.title .. " \194\183 " .. s.label) or p.title,
						text = (name .. " " .. (C.Desc(n) or "")):lower() }
				end
			end
		end
	end
	self.index = out
	return out
end

function OW:Search(text)
	text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	self.query = text
	local results = {}
	local pages = {}
	if text ~= "" then
		for _, e in ipairs(self:Index()) do
			if e.text:find(text, 1, true) then
				results[#results + 1] = e
				pages[e.page.key] = true
			end
		end
	end
	self.results = results
	for _, n in ipairs(self.nodes or {}) do
		n.found = pages[n.page] or nil
		self:PaintNode(n)
	end
	for _, n in ipairs(self.frame.map.system) do n.found = pages[n.page] or nil end
	self:PaintSystem()
	self:PaintSearch()
	return #results
end

function OW:PaintSearch()
	local f = self.frame
	local s = f.head.search
	local c = Palette.c
	local a = c.accent
	local typed = (s.box:GetText() or "") ~= ""
	s.placeholder:SetShown(not typed)
	s:SetFillColor({ 1, 1, 1, 0.05 })
	s:SetEdgeColor({ a[1], a[2], a[3], s.box:HasFocus() and 0.5 or 0.2 })
	W.Color(s.placeholder, { c.text[1], c.text[2], c.text[3], 0.45 })
	W.Tint(s.lens, c.text, 0.5)
	s.key:SetFillColor({ 0, 0, 0, 0 })
	s.key:SetEdgeColor({ a[1], a[2], a[3], 0.3 })
	W.Color(s.key.text, { a[1], a[2], a[3], 0.5 })
	W.Color(s.box, c.text)

	local r = f.results
	local list = self.results or {}
	if not typed or #list == 0 then
		r:Hide()
		return
	end
	local shown = math.min(#list, RESULTS)
	for i, b in ipairs(r.rows) do
		local e = list[i]
		if e and i <= shown then
			b.name:SetText(e.name)
			b.where:SetText(e.where)
			W.Color(b.name, c.text)
			W.Color(b.where, c.textDim)
			b.hl:SetVertexColor(a[1], a[2], a[3], 0.16)
			b:Show()
		else
			b:Hide()
		end
	end
	r:SetHeight(12 + shown * RESULT_H)
	r:SetFillColor({ NODE_FILL[1], NODE_FILL[2], NODE_FILL[3], 0.95 })
	r:SetEdgeColor({ a[1], a[2], a[3], 0.4 })
	r:Show()
end

--- Open a search result: its page, scrolled to the row, the row pulsing.
function OW:OpenResult(i)
	local e = self.results and self.results[i]
	if not e then return false end
	self.frame.results:Hide()
	self:Go(e.page.key, e.sub)
	local row = self.view and self.view:RowFor(e.node)
	if row then
		local sc = self.frame.pageFrame.scroll
		local _, _, _, _, ry = row:GetPoint(1)
		local max = math.max(0, (sc.child:GetHeight() or 0) - (sc:GetHeight() or 0))
		sc:SetVerticalScroll(math.max(0, math.min(max, -(ry or 0) - 40)))
		sc:Measure()
		self.pulse = { row = row, t = 0 }
		self:Drive()
	end
	return true
end

-- ---------------------------------------------------------------------------
-- moving between map and pages
-- ---------------------------------------------------------------------------

local function Ease(p)
	if p <= 0 then return 0 elseif p >= 1 then return 1 end
	return 1 - (1 - p) * (1 - p) * (1 - p)
end

local function Clamp01(p) return math.max(0, math.min(1, p)) end

function OW:Reduced() return A.db.profile.reducedMotion and true or false end

--- A node drawn at (x, y) in window units, at `scale` and `alpha`.
local function Pose(n, x, y, scale, alpha)
	local b = n.button
	if not b then return end
	scale = scale or 1
	b:SetScale(scale)
	b:ClearAllPoints()
	b:SetPoint("CENTER", b:GetParent(), "TOPLEFT", x / scale, -y / scale)
	b:SetAlpha((b.__off and 0.45 or 1) * (alpha or 1))
	b:SetShown((alpha or 1) > 0.01)
end

--- The open: each node arrives `hop` x 40 ms after the player, 12 px out
--  from its spot along the line from the player, over 160 ms. `t` runs back
--  down for the close.
function OW:PoseOpen(t)
	local reduced = self:Reduced()
	local dur = reduced and REDUCED or NODE_IN
	local by = self.byKey or {}
	local px, py = by.player and by.player.x or WIN_W / 2, by.player and by.player.y or WIN_H / 2
	local m = self.frame.map
	local function at(hop) return Ease(Clamp01((t - (reduced and 0 or hop * HOP)) / dur)) end
	for _, n in ipairs(self.nodes or {}) do
		local p = at(n.hop or 0)
		local dx, dy = n.x - px, n.y - py
		local len = math.sqrt(dx * dx + dy * dy)
		local ox, oy = 0, 0
		if len > 0 then ox, oy = -dx / len * SLIDE, -dy / len * SLIDE end
		Pose(n, n.x + ox * (1 - p), n.y + oy * (1 - p), 1, p)
	end
	for _, l in ipairs(self.bonds or {}) do
		local p = at(l.hop or 1)
		DrawBond(m, l, p, p)
	end
	local sys = at(4)
	m.sysLine:SetAlpha(sys)
	m.sysLabel:SetAlpha(sys)
	for _, n in ipairs(m.system) do n.button:SetAlpha(sys) end
	local field = at(0)
	for _, d in ipairs(m.dots) do d:SetAlpha(field) end
	return t >= (reduced and REDUCED or (4 * HOP + NODE_IN))
end

--- The unfold: every node slides to its page's place on the strand and
--  shrinks to it, staggered as the open is; the clicked one swells and fades
--  toward the title; the bonds and the field go; the strand's own nodes and
--  the page come in. `t` runs back down for the fold.
function OW:PoseUnfold(t)
	local reduced = self:Reduced()
	local dur = reduced and REDUCED or UNFOLD
	local slots = self:NavSlots()
	local m, nav, pg = self.frame.map, self.frame.nav, self.frame.pageFrame
	local chosen = self.chosen
	for _, n in ipairs(self.nodes or {}) do
		local delay = reduced and 0 or (n.hop or 0) * HOP
		local q = Ease(Clamp01((t - delay) / dur))
		if n == chosen then
			local c = Ease(Clamp01(t / (reduced and REDUCED or 0.2)))
			local tx, ty = NAV_W + PAD_L + 60, HEAD_H + PAD_T + 10
			Pose(n, n.x + (tx - n.x) * c, n.y + (ty - n.y) * c, 1 + 0.4 * c, 1 - c)
		else
			local sy = slots[n.page] or NAV_TOP
			local navW = (NAV_FORM[n.pageDef and n.pageDef.form] or { 20 })[1]
			local s = 1 + (math.min(1, navW / math.max(1, n.w or 20)) - 1) * q
			local fade = 1 - Clamp01((q - 0.7) / 0.3)
			Pose(n, n.x + (NAV_X - n.x) * q, n.y + (sy - n.y) * q, s, fade)
		end
	end
	local gone = 1 - Ease(Clamp01(t / (reduced and REDUCED or 0.15)))
	for _, l in ipairs(self.bonds or {}) do DrawBond(m, l, 1, gone) end
	for _, d in ipairs(m.dots) do d:SetAlpha(gone) end
	m.sysLine:SetAlpha(gone)
	m.sysLabel:SetAlpha(gone)
	for _, n in ipairs(m.system) do
		n.button:SetAlpha(gone)
		n.button:SetShown(gone > 0.01)
	end
	local navIn = Ease(Clamp01((t - (reduced and 0 or 0.18)) / (reduced and REDUCED or 0.12)))
	nav:SetAlpha(navIn)
	nav:SetShown(navIn > 0.01)
	local body = Ease(Clamp01((t - (reduced and 0 or BODY_AT)) / (reduced and REDUCED or 0.15)))
	pg:SetAlpha(body)
	pg:SetShown(body > 0.01)
	return t >= (reduced and REDUCED or (BODY_AT + 0.15))
end

--- Run the animation `kind` from where it is; `back` runs it in reverse.
function OW:Play(kind, back, done)
	self.anim = { kind = kind, back = back, t = 0, done = done }
	if back then
		-- Start from the end: the longest the pose function needs.
		self.anim.t = (kind == "open") and (4 * HOP + NODE_IN) or (BODY_AT + 0.15)
		if self:Reduced() then self.anim.t = REDUCED end
	end
	self:Drive()
	self:Step(0)
end

function OW:Drive()
	self.frame:SetScript("OnUpdate", function(_, dt) OW:Step(dt) end)
end

--- One frame of whatever is moving.
function OW:Step(dt)
	dt = dt or 0
	local busy = false
	local a = self.anim
	if a then
		if a.kind == "switch" then
			a.t = a.t + dt
			local dur = self:Reduced() and REDUCED or SWITCH
			local p = Clamp01(a.t / dur)
			local pg = self.frame.pageFrame
			if a.swap and p >= 0.5 then
				a.swap()
				a.swap = nil
			end
			pg:SetAlpha(p < 0.5 and (1 - p * 2) or ((p - 0.5) * 2))
			if a.fromY and a.toY then
				self.stubY = a.fromY + (a.toY - a.fromY) * Ease(p)
				self:PaintNav()
			end
			if p >= 1 then
				self.stubY = nil
				pg:SetAlpha(1)
				self:PaintNav()
				self.anim = nil
				if a.done then a.done() end
			else
				busy = true
			end
		else
			local pose = (a.kind == "open") and self.PoseOpen or self.PoseUnfold
			local finished
			if a.back then
				a.t = math.max(0, a.t - dt)
				pose(self, a.t)
				finished = a.t <= 0
			else
				a.t = a.t + dt
				finished = pose(self, a.t)
			end
			if finished then
				self.anim = nil
				if a.done then a.done() end
			else
				busy = true
			end
		end
	end
	local pulse = self.pulse
	if pulse then
		pulse.t = pulse.t + dt
		local a2 = Palette.c.accent
		local k = math.max(0, 1 - pulse.t / 1.6) * (0.5 + 0.5 * math.cos(pulse.t * 8))
		pulse.row.hit:SetVertexColor(a2[1], a2[2], a2[3], 1)
		pulse.row.hit:SetAlpha(0.22 * k)
		if pulse.t >= 1.6 then
			pulse.row.hit:SetAlpha(0)
			self.pulse = nil
		else
			busy = true
		end
	end
	if not busy and self.frame then self.frame:SetScript("OnUpdate", nil) end
end

--- Everything moving lands where it is going, now.
function OW:Finish()
	for _ = 1, 200 do
		if not (self.anim or self.pulse) then break end
		self:Step(0.05)
	end
end

--- The map, as it stands.
function OW:ShowMap()
	local f = self.frame
	self.mode, self.page, self.chosen = "map", nil, nil
	f.map:Show()
	f.map:SetAlpha(1)
	f.nav:Hide()
	f.pageFrame:Hide()
end

--- Click a node: its page, out of the map.
function OW:Unfold(n)
	local p = n.pageDef
	if not p then return end
	if p.action then return self:Act(p) end
	self.frame.card:Hide()
	self:Unlight()
	n.hovered = nil
	if n.form == "system" then self:PaintSystem() else self:PaintNode(n) end
	self.chosen = n
	self.mode = "page"
	local sub = 1
	if n.subKey then
		for i, s in ipairs(self:Subs(p)) do
			if s.subKey == n.subKey then sub = i end
		end
	end
	self:ShowPage(p, sub)
	self.frame.pageFrame:SetAlpha(0)
	self:Play("unfold", false)
end

--- Back to the map from a page: the reverse of the unfold.
function OW:Fold()
	if self.mode ~= "page" then return end
	if not self.chosen then
		-- Opened straight onto a page: there is no unfold to run back.
		self:LayMap()
		self:ShowMap()
		self:PoseOpen(10)
		return
	end
	self.mode = "map"
	self:Play("unfold", true, function()
		OW:ShowMap()
		OW:PoseOpen(10)
	end)
end

--- Go to a page from anywhere: from the map, a straight unfold of its node;
--  from a page, the bodies cross-fade and the stub slides.
function OW:Go(key, sub)
	local p = self:Page(key)
	if not p then return false end
	if p.action then return self:Act(p) end
	if self.mode ~= "page" then
		local node
		for _, n in ipairs(self.nodes or {}) do
			if n.page == key then node = n break end
		end
		for _, n in ipairs(self.frame.map.system) do
			if n.page == key then node = node or n end
		end
		if node then
			self:Unfold(node)
			if sub and sub ~= self.sub then self:ShowPage(p, sub) end
			return true
		end
	end
	local slots = self:NavSlots()
	local fromY = self.page and slots[self.page.key]
	self.anim = { kind = "switch", t = 0, fromY = fromY, toY = slots[key],
		swap = function() OW:ShowPage(p, sub) end }
	self:Drive()
	self:Step(0)
	return true
end

--- The System strand's two that are not pages.
function OW:Act(p)
	if p.action == "unlock" then
		self:Close(true)
		A.Movers:Unlock()
	elseif p.action == "tour" then
		self:Close(true)
		local OB = A:GetModule("onboard")
		if OB then OB:Start() end
	end
	return true
end

--- Unlock just this module (Shift-click, or the page's own button).
function OW:UnlockPage(p)
	if not p then return false end
	local names
	if p.bars then
		names = {}
		for name in pairs(A.Movers.registry or {}) do
			if name:find("^bar") then names[name] = true end
		end
	elseif p.unlock then
		names = {}
		for _, name in ipairs(p.unlock) do names[name] = true end
	else
		return false
	end
	if InCombatLockdown() then return false end
	self:Close(true)
	A.Movers:Unlock(names)
	return true
end

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

function OW:Build()
	if self.frame then return self.frame end
	local f = A.Glass.CreatePanel(UIParent, { name = ADDON .. "Options", corner = 28,
		shadow = 1 })
	f:SetSize(WIN_W, WIN_H)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	self.frame = f

	BuildHeader(f)
	BuildFooter(f)
	BuildMap(f)
	BuildNav(f)
	BuildPageFrame(f)
	BuildCard(f)
	BuildResults(f)

	-- THE KEYS: `/` to search, Esc back a step, the arrows on a hovered
	-- slider. Everything else passes through to the game, through
	-- A:SetPropagate (protected in a fight; see there).
	f:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			A:SetPropagate(self, false)
			if OW.mode == "page" then OW:Fold() else OW:Close() end
		elseif key == "/" and not f.head.search.box:HasFocus() then
			A:SetPropagate(self, false)
			f.head.search.box:SetFocus()
		elseif (key == "LEFT" or key == "RIGHT") and OW:HoveredSlider() then
			A:SetPropagate(self, false)
			OW:HoveredSlider():Step(key == "LEFT" and -1 or 1)
		else
			A:SetPropagate(self, true)
			return
		end
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(0.1, function() A:SetPropagate(self, true) end)
		else
			A:SetPropagate(self, true)
		end
	end)
	f:SetScript("OnShow", function(self) self:EnableKeyboard(A:SetPropagate(self, true)) end)
	-- A field still holding the cursor once its window is gone takes every key
	-- the player presses, movement included.
	f:SetScript("OnHide", function(self)
		self.head.search.box:ClearFocus()
		for _, v in pairs(OW.views) do
			for _, row in ipairs(v.rows) do
				if row.box then row.box:ClearFocus() end
			end
		end
		W.HideTooltip()
	end)

	C.onChange = function(node) OW:AfterWrite(node) end
	A:OnSkinChanged(function() OW:Repaint() end)
	return f
end

function OW:HoveredSlider()
	local v = self.mode == "page" and self.view
	if not v then return nil end
	for _, row in ipairs(v.rows) do
		if row.track and row.hovered then return row end
	end
end

--- After any write: the page again, since a name, a disabled state or the
--  preview may follow from it; and the header's profile name.
function OW:AfterWrite()
	if not (self.frame and self.frame:IsShown()) then return end
	if self.view then self.view:Refresh() end
	self:PaintHeader()
	self:PaintPage()
end

function OW:PaintHeader()
	local h = self.frame.head
	local c = Palette.c
	local a = c.accent
	W.Tint(h.glyph, a, 1)
	W.Color(h.brand, c.text)
	h.version:SetFillColor({ a[1], a[2], a[3], 1 })
	h.version:SetEdgeColor({ a[1], a[2], a[3], 1 })
	h.version.text:SetText(A.version or "?")
	h.version:SetWidth(math.ceil(h.version.text:GetStringWidth() or 30) + 18)
	W.Color(h.version.text, { 20 / 255, 16 / 255, 31 / 255, 1 })
	local name = A.db.GetCurrentProfile and A.db:GetCurrentProfile() or "?"
	h.profile.text:SetText(A.F(L.options.map.profile_s, name))
	h.profile:SetWidth(math.ceil(h.profile.text:GetStringWidth() or 80) + 28)
	h.profile:SetFillColor({ 0, 0, 0, 0 })
	h.profile:SetEdgeColor({ a[1], a[2], a[3], 0.3 })
	W.Color(h.profile.text, { c.text[1], c.text[2], c.text[3], 0.7 })
	W.RepaintClose(h.close)
	W.PaintHairline(h.rule)
	local foot = self.frame.foot
	W.Color(foot.text, { c.text[1], c.text[2], c.text[3], 0.45 })
	W.Tint(foot.dot, c.info or a, 1)
	self:PaintSearch()
end

--- A skin change, or the window opening: every colour again.
function OW:Repaint()
	local f = self.frame
	if not f then return end
	local a = Palette.c.accent
	f:SetFillColor(Palette:ReadingFill())
	f:SetEdgeColor({ a[1], a[2], a[3], 0.35 })
	self:PaintHeader()
	for _, n in ipairs(self.nodes or {}) do self:PaintNode(n) end
	self:PaintSystem()
	self:PaintNav()
	if self.view then self.view:Refresh() end
	self:PaintPage()
end

--- Open on the map, or straight onto the page holding `section`.
function OW:Open(section)
	if InCombatLockdown() then
		self.reopen = section or true
		A:Print(L.options.map.after_fight)
		return false
	end
	local f = self:Build()
	self.tree, self.index, self.results = nil, nil, nil
	-- Hidden before they are forgotten: a page drawn last time and dropped
	-- from the cache still showed under the new one (Joe, in game).
	for _, v in pairs(self.views) do v.frame:Hide() end
	wipe(self.views)
	self.view = nil
	self:Place()
	f:Show()
	f:SetAlpha(1)
	f.head.search.box:SetText("")
	f.results:Hide()
	f.card:Hide()
	self:LayMap()
	self:Repaint()
	local page, sub = self:PageFor(section)
	if page then
		self.chosen = nil
		self.mode = "page"
		f.map:Hide()
		f.nav:Show()
		f.nav:SetAlpha(1)
		f.pageFrame:Show()
		f.pageFrame:SetAlpha(1)
		self:ShowPage(page, sub)
		self.anim = nil
	else
		self:ShowMap()
		self:Play("open", false)
	end
	return true
end

--- Shut it: the open run backwards, or at once (`now`, for a mode that needs
--  the screen straight away).
function OW:Close(now)
	local f = self.frame
	if not (f and f:IsShown()) then return end
	self.closing = true
	self.frame.card:Hide()
	self:Unlight()
	W.CloseMenu()
	local function shut()
		OW.closing = nil
		f:Hide()
		f:SetScript("OnUpdate", nil)
		OW.anim, OW.pulse = nil, nil
	end
	if now or self.mode ~= "map" then
		shut()
		return
	end
	self:Play("open", true, shut)
end

function OW:IsOpen()
	return self.frame and self.frame:IsShown() and not self.closing or false
end

--- The tree's shape changed (a bar added): pages are drawn again.
function OW:Refresh()
	if not self.frame then return end
	self.tree, self.index = nil, nil
	for _, v in pairs(self.views) do v.frame:Hide() end
	wipe(self.views)
	if self:IsOpen() then
		if self.mode == "page" and self.page then
			self:ShowPage(self.page, self.sub)
		else
			self:LayMap()
			self:PoseOpen(10)
		end
	end
end

-- NOT IN A FIGHT (handoff "Window"): out over 200 ms when one starts, back
-- when it ends, where it was.
A:RegisterEvent(OW, "PLAYER_REGEN_DISABLED", function()
	local f = OW.frame
	if not (f and f:IsShown()) then return end
	OW.reopen = (OW.mode == "page" and OW.page and OW.page.key) or true
	OW.fight = { t = 0 }
	f.card:Hide()
	OW:Unlight()
	W.CloseMenu()
	f:SetScript("OnUpdate", function(self, dt)
		OW.fight.t = OW.fight.t + (dt or 0)
		local p = math.min(1, OW.fight.t / 0.2)
		self:SetAlpha(1 - p)
		if p >= 1 then
			self:SetScript("OnUpdate", nil)
			self:Hide()
			self:SetAlpha(1)
			OW.fight = nil
		end
	end)
end)

A:RegisterEvent(OW, "PLAYER_REGEN_ENABLED", function()
	local again = OW.reopen
	OW.reopen = nil
	if again then OW:Open(again ~= true and again or nil) end
end)
