--[[--------------------------------------------------------------------------
	Lattice :: Braids

	A braid is two or more strands fused edge to edge into one block: one pad,
	one gap, one button size (strands brief, "Braid"). It is purely visual.
	Buttons never change bars, so secure buttons, keys and paging are untouched.

	A braid is a BOND WITH A FLAG. The braided strand hangs from its host's
	edge in the parent model, and its record carries `braid = <slot>`:

	    anchors.bar2 = { lat = { parent = "bar1", point = "TOPLEFT",
	                             relPoint = "TOPRIGHT", x, y }, braid = 0 }

	The points say which edge (SEATS). The slot says how many buttons along
	that edge it sits, so its buttons line up with the host's. x and y are
	worked out from those (Seat) whenever the bars are laid out, never kept
	as the truth: the seam has to stay one gap wide whatever the size.

	THE SEAM. The brief says the dragged strand hangs from the host's edge
	"with offset 0". Dock against dock, that puts two pads' worth of padding
	between the buttons (20 against a gap of 8), so the docks overlap by
	2 x pad - gap instead, and the gap across the seam is the strand's own.

	A chain is a braid onto a braided strand. Its ROOT is the first host: the
	pad is the root's, and every member draws at the root's button size.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = A.L
local Braids = {}
A.Braids = Braids

--- How a member sits on each edge of its host: its own point, the host's,
--  and which way the slot runs.
local SEATS = {
	RIGHT  = { point = "TOPLEFT",    rel = "TOPRIGHT",   along = "y" },
	LEFT   = { point = "TOPRIGHT",   rel = "TOPLEFT",    along = "y" },
	BOTTOM = { point = "TOPLEFT",    rel = "BOTTOMLEFT", along = "x" },
	TOP    = { point = "BOTTOMLEFT", rel = "TOPLEFT",    along = "x" },
}
Braids.SEATS = SEATS

--- The edge a pair of anchor points describes, or nil.
function Braids.EdgeOf(point, relPoint)
	for edge, s in pairs(SEATS) do
		if s.point == point and s.rel == relPoint then return edge end
	end
	return nil
end

local function round(v) return math.floor((v or 0) + 0.5) end

local function Anchors() return A.db and A.db.profile.anchors or {} end

local function Bars() return A.GetModule and A:GetModule("actionbars") end

--- The pad, gap and button size a braid rooted on `root` draws with, in the
--  docks' own units.
local function Metrics(root)
	local cfg = A.Config:Module("actionbars")
	local AB = Bars()
	local size = AB and AB.DrawSize and AB:DrawSize(root) or cfg.size or 36
	return cfg.padding or 0, cfg.spacing or 0, size
end

--- Where a member sits on its host for an edge and slot: point, relPoint,
--  x, y in the member's own units (the same as the root's, as it draws at
--  the root's scale).
function Braids:Seat(root, edge, slot)
	local s = SEATS[edge]
	if not s then return nil end
	local pad, gap, size = Metrics(root)
	local over = 2 * pad - gap
	local along = (slot or 0) * (size + gap)
	local x, y
	if edge == "RIGHT" then x, y = -over, -along
	elseif edge == "LEFT" then x, y = over, -along
	elseif edge == "BOTTOM" then x, y = along, over
	else x, y = along, -over end
	return s.point, s.rel, x, y
end

-- ---------------------------------------------------------------------------
-- who is braided to whom
-- ---------------------------------------------------------------------------

local function Braidable(name)
	local e = A.Movers.registry[name]
	return e and e.braid and true or false
end

--- The strand `name` is braided onto, or nil.
function Braids:HostOf(name)
	local r = Anchors()[name]
	if type(r) ~= "table" or r.braid == nil or r.free then return nil end
	local lat = type(r.lat) == "table" and r.lat
	if not (lat and lat.parent and Braids.EdgeOf(lat.point, lat.relPoint)) then return nil end
	if not Braidable(lat.parent) then return nil end
	return lat.parent
end

--- The first host up the chain: the strand that owns the pad. A strand in
--  no braid is its own root.
function Braids:Root(name)
	local cur, hops = name, 0
	while hops < 12 do
		local host = Braids:HostOf(cur)
		if not host or host == name then break end
		cur, hops = host, hops + 1
	end
	return cur
end

--- Every strand in `root`'s braid, the root first, then each member after
--  its own host. Just the root when nothing is braided onto it.
function Braids:Members(root)
	local out, seen = { root }, { [root] = true }
	local i = 1
	while out[i] do
		for name in pairs(A.Movers.registry) do
			if not seen[name] and Braids:HostOf(name) == out[i] then
				seen[name] = true
				out[#out + 1] = name
			end
		end
		i = i + 1
	end
	return out
end

--- Whether `name`'s dock is drawn bare, because a pad is drawn round it.
function Braids:Bare(name)
	return Braids.bare and Braids.bare[name] or false
end

-- ---------------------------------------------------------------------------
-- joining and leaving
-- ---------------------------------------------------------------------------

--- Braid `name` onto `host`'s edge at a slot. Refused in combat, onto itself,
--  onto a strand that hangs from it (a loop), or for anything that is not a
--  strand. Returns true when it took.
function Braids:Join(name, host, edge, slot)
	if InCombatLockdown() or not SEATS[edge] then return false end
	if name == host or not (Braidable(name) and Braidable(host)) then return false end
	if A.Movers.Descends(host, name) then return false end

	local point, rel, x, y = Braids:Seat(Braids:Root(host), edge, slot)
	local entry = A.Movers.registry[name]
	entry.parent, entry.free = host, nil
	Anchors()[name] = { lat = { parent = host, point = point, relPoint = rel, x = x, y = y },
		braid = round(slot or 0) }
	Braids:Relayout()
	return true
end

--- Take `name` out of its braid. It stays bonded to its host where it is
--  now, and goes back to its own size and dock.
function Braids:Leave(name)
	if InCombatLockdown() then return false end
	local host = Braids:HostOf(name)
	if not host then return false end
	Anchors()[name].braid = nil
	-- The bond where it stands, measured before the bars are laid out again:
	-- otherwise it is placed back on its seat first.
	A.Movers:SetParent(name, host)
	Braids:Relayout()
	return true
end

--- The bars laid out again, which re-seats every braid and lays the pads.
function Braids:Relayout()
	local AB = Bars()
	if AB and AB.OnConfigChanged then AB:OnConfigChanged() else Braids:Refresh() end
end

-- ---------------------------------------------------------------------------
-- the pad
-- ---------------------------------------------------------------------------

Braids.pads = {}

local function DockOf(name)
	local e = A.Movers.registry[name]
	return e and e.frame
end

local function Pad(root)
	local p = Braids.pads[root]
	if p then return p end
	-- 14, the strand pad's own; the Theme's corner scales it with the rest.
	p = A.Glass.CreatePanel(UIParent, { corner = 14,
		shadow = A.db.profile.glass.shadow })
	p:EnableMouse(false)
	p:Hide()
	-- The HIGHEST energy among its strands (strands brief), so the block never
	-- reads as half-faded. Each strand keeps its own over it.
	A.Fader:Register(p, { energy = function()
		local AB, top, hot = Bars(), nil, nil
		if not (AB and AB.Energy) then return 1 end
		for _, n in ipairs(Braids:Members(root)) do
			local e, h = AB:Energy(n)
			if not top or e > top then top = e end
			hot = hot or h
		end
		return top or 1, hot
	end })
	Braids.pads[root] = p
	return p
end

--- A member's dock coming or going changes the pad. In combat only the
--  pad's own visibility can change; the rest waits for the fight to end.
local function Watch(dock)
	if dock.__latticeBraidWatch then return end
	dock.__latticeBraidWatch = true
	local function changed()
		if Braids._refreshing then return end
		if InCombatLockdown() then
			Braids._pending = true
			for root, p in pairs(Braids.pads) do
				local shown = 0
				for _, n in ipairs(Braids:Members(root)) do
					local d = DockOf(n)
					if d and d:IsShown() then shown = shown + 1 end
				end
				p:SetShown(shown >= 2)
			end
		else
			Braids:Refresh()
		end
	end
	dock:HookScript("OnShow", changed)
	dock:HookScript("OnHide", changed)
end

--- Lay `root`'s pad round every shown member's dock, anchored to the root's
--  dock so a drag of the root carries it. Returns the members it covers.
local function LayPad(root)
	local rootDock = DockOf(root)
	local shown = {}
	for _, n in ipairs(Braids:Members(root)) do
		local d = DockOf(n)
		if d then
			Watch(d)
			if d:IsShown() then shown[#shown + 1] = n end
		end
	end
	local p = Braids.pads[root]
	if #shown < 2 or not (rootDock and rootDock:IsShown() and rootDock:GetLeft()) then
		if p then p:Hide() end
		return {}
	end

	p = Pad(root)
	-- Every member draws at the root's scale, so their edges are in one space.
	local rl, rt = rootDock:GetLeft(), rootDock:GetTop()
	local l, r, b, t
	for _, n in ipairs(shown) do
		local d = DockOf(n)
		local dl, dr, db, dt = d:GetLeft(), d:GetRight(), d:GetBottom(), d:GetTop()
		if dl then
			l, r = math.min(l or dl, dl), math.max(r or dr, dr)
			b, t = math.min(b or db, db), math.max(t or dt, dt)
		end
	end
	p:SetScale(rootDock:GetScale() or 1)
	p:SetFrameStrata(rootDock:GetFrameStrata())
	p:SetFrameLevel(math.max(0, (rootDock:GetFrameLevel() or 1) - 1))
	p:ClearAllPoints()
	p:SetPoint("TOPLEFT", rootDock, "TOPLEFT", l - rl, t - rt)
	p:SetPoint("BOTTOMRIGHT", rootDock, "TOPLEFT", r - rl, b - rt)

	local AB = Bars()
	local rootCfg = AB and AB.ConfigOf and AB:ConfigOf(root)
	if rootCfg and rootCfg.backdrop == false then
		p:SetFillColor({ 0, 0, 0, 0 })
		p:SetEdgeShown(false)
		p:SetShadow(0)
	else
		p:ApplySkin()
		p:SetEdgeShown(true)
		p:SetShadow(A.db.profile.glass.shadow)
	end
	A.Glass.SetPanelCorner(p, 14)
	p:Show()
	return shown
end

--- Every braid re-seated on its host and every pad laid. Out of combat:
--  the docks hold secure buttons. Runs after the bars are laid out.
function Braids:Refresh()
	if InCombatLockdown() then
		Braids._pending = true
		return
	end
	if Braids._refreshing then return end
	Braids._refreshing = true
	Braids._pending = nil

	-- Root first down each chain, so a member is seated on a host that is
	-- already where it belongs.
	local roots, done = {}, {}
	for name in pairs(A.Movers.registry) do
		if Braids:HostOf(name) then
			local root = Braids:Root(name)
			if not done[root] then done[root] = true; roots[#roots + 1] = root end
		end
	end
	for _, root in ipairs(roots) do
		for i, name in ipairs(Braids:Members(root)) do
			if i > 1 then
				local r = Anchors()[name]
				local edge = Braids.EdgeOf(r.lat.point, r.lat.relPoint)
				local point, rel, x, y = Braids:Seat(root, edge, r.braid)
				r.lat.point, r.lat.relPoint, r.lat.x, r.lat.y = point, rel, x, y
				A.Movers:Restore(name)
				A.Movers:SaveTree(name)
			end
		end
	end

	local bare = {}
	for _, root in ipairs(roots) do
		for _, n in ipairs(LayPad(root)) do bare[n] = true end
	end
	for root, p in pairs(Braids.pads) do
		if not done[root] then p:Hide() end
	end
	Braids.bare = bare

	local AB = Bars()
	if AB and AB.ApplyDockSkins then AB:ApplyDockSkins() end
	Braids._refreshing = nil
end

A:RegisterEvent(Braids, "PLAYER_REGEN_ENABLED", function()
	if Braids._pending then Braids:Refresh() end
end)

-- ---------------------------------------------------------------------------
-- in unlock: the edge a drop would braid onto
-- ---------------------------------------------------------------------------

local feedback

local function Feedback()
	if feedback then return feedback end
	local f = CreateFrame("Frame", ADDON .. "BraidEdge", UIParent)
	f:SetAllPoints(UIParent)
	f:SetFrameStrata("FULLSCREEN")
	f.glow = f:CreateTexture(nil, "ARTWORK")
	f.glow:SetTexture(A.Media.texture.glow)
	f.edge = f:CreateLine(nil, "OVERLAY")
	f.node = f:CreateTexture(nil, "OVERLAY")
	f.node:SetTexture(A.Media.texture.diamond)
	f.text = A.Widgets.Text(f, "label", "LEFT")
	f:Hide()
	feedback = f
	return f
end

Braids.__feedback = function() return feedback end

--- The lit edge, or nil to take it away. t = { x1, y1, x2, y2, label } in
--  UIParent units.
function Braids:ShowEdge(t)
	if not t then
		if feedback then feedback:Hide() end
		return
	end
	local f = Feedback()
	local g = A.Palette.c.friendly
	local Px = A.Movers.Px
	f.edge:SetStartPoint("BOTTOMLEFT", UIParent, t.x1, t.y1)
	f.edge:SetEndPoint("BOTTOMLEFT", UIParent, t.x2, t.y2)
	f.edge:SetThickness(Px(3))
	f.edge:SetColorTexture(g[1], g[2], g[3], 1)
	local mx, my = (t.x1 + t.x2) / 2, (t.y1 + t.y2) / 2
	local len = math.max(math.abs(t.x2 - t.x1), math.abs(t.y2 - t.y1))
	f.glow:ClearAllPoints()
	f.glow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx, my)
	if t.x1 == t.x2 then f.glow:SetSize(Px(24), len + Px(24))
	else f.glow:SetSize(len + Px(24), Px(24)) end
	A.Widgets.Tint(f.glow, g, 0.55)
	f.node:SetSize(Px(14), Px(14))
	f.node:ClearAllPoints()
	f.node:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx, my)
	A.Widgets.Tint(f.node, g, 1)
	f.text:SetText(("%s · %s"):format(L.movers.snap.braid, t.label))
	f.text:ClearAllPoints()
	f.text:SetPoint("LEFT", f.node, "RIGHT", Px(8), 0)
	A.Widgets.Color(f.text, g)
	f.info = t
	f:Show()
end

--- The braid a drop of `entry` here would make: the nearest strand edge
--  within 8 of one of its own, overlapping it along that edge. `skip` holds
--  the frames that move with it. Returns { host, edge, slot, ... } or nil.
function Braids:Probe(entry, skip)
	if not entry.braid then return nil end
	local M = A.Movers
	local reach = M.Px(8)
	local fl, fb = M.PointAt(entry.frame, "BOTTOMLEFT")
	local fr, ft = M.PointAt(entry.frame, "TOPRIGHT")
	if not fl then return nil end

	local best
	for name, e in pairs(M.registry) do
		local f = e.frame
		if e.braid and name ~= entry.name and not (skip and skip[f]) and f:IsShown() then
			local hl, hb = M.PointAt(f, "BOTTOMLEFT")
			local hr, ht = M.PointAt(f, "TOPRIGHT")
			if hl then
				-- Measured from the SEAT, where the docks overlap by the seam:
				-- a member let go where it sits is still 0 away.
				local pad, gap = Metrics(Braids:Root(name))
				local over = (2 * pad - gap) * (f:GetEffectiveScale() or 1)
					/ (UIParent:GetEffectiveScale() or 1)
				local across = fb < ht and ft > hb
				local down = fl < hr and fr > hl
				local tries = {
					{ "RIGHT", across, fl - (hr - over), hr, math.max(fb, hb), hr, math.min(ft, ht) },
					{ "LEFT", across, (hl + over) - fr, hl, math.max(fb, hb), hl, math.min(ft, ht) },
					{ "BOTTOM", down, (hb + over) - ft, math.max(fl, hl), hb, math.min(fr, hr), hb },
					{ "TOP", down, fb - (ht - over), math.max(fl, hl), ht, math.min(fr, hr), ht },
				}
				for _, try in ipairs(tries) do
					local d = math.abs(try[3])
					if try[2] and d <= reach and (not best or d < best.dist) then
						best = { host = name, edge = try[1], dist = d,
							x1 = try[4], y1 = try[5], x2 = try[6], y2 = try[7],
							hl = hl, ht = ht, fl = fl, ft = ft, frame = f }
					end
				end
			end
		end
	end
	if not best then return nil end

	-- The slot: how many of the host's buttons along the edge it starts, so
	-- the columns (or rows) line up.
	local _, gap, size = Metrics(Braids:Root(best.host))
	local step = (size + gap) * (best.frame:GetEffectiveScale() or 1)
		/ (UIParent:GetEffectiveScale() or 1)
	local off = SEATS[best.edge].along == "y" and (best.ht - best.ft) or (best.fl - best.hl)
	best.slot = step > 0 and round(off / step) or 0
	local he = M.registry[best.host]
	best.label = tostring(he.label or best.host):upper()
	return best
end
