--[[--------------------------------------------------------------------------
	AetherUI :: Movers

	Drag-to-place for any registered frame, with the position persisted per
	profile under db.profile.anchors[name].

	Why a separate overlay rather than making the frame itself draggable:
	the real frames will eventually include secure action buttons, which cannot
	be moved in combat and should not be given mouse scripts at all. A dumb
	overlay that repositions its target sidesteps that whole class of problem.

	THE PARENT MODEL (Lattice). A node can hang from another node - its PARENT
	- rather than from the screen, and a node that moves carries everything
	bonded to it: the pet and focus capsules hang from the player, the ToT from
	the target, bars 1 and 2 from the spine's centre, and the stance, pet and
	extra-action bars from bar 1 ("actions are bonded to actions" - Joe). A
	parent is another node's name, or nothing for the screen.

	One record per node, in db.profile.anchors[name]:
	  point, relPoint, x, y   where it sits on the SCREEN - the record 1.x
	                          reads, kept current so a rollback still lands
	                          everything where it was
	  lat                     { parent, point, relPoint, x, y }: the bond, the
	                          offset from the parent, which is what places it

	A record with no `lat` is a 1.x record, or one a preset wrote. It is placed
	on the screen exactly as 1.x placed it and then MEASURED against its parent
	and bonded there, so the upgrade moves nothing.

	THE SPINE'S PAIR. The target is not a child of the player: the two are one
	piece, level, with the spine between them (Joe, 2026-10-07). Dragging
	either moves both; Ctrl-dragging either stretches the spine about its own
	centre, never below its minimum. Recorded as the target bonded LEFT to the
	player's RIGHT at the spine's length, with no height of its own.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local Movers = {}
A.Movers = Movers

Movers.registry = {}
Movers.unlocked = false

-- Modules that place themselves, but still want to know when placement MODE is
-- on. The Toolbox is the case: it has four legal docks rather than a position,
-- so it is deliberately not in the registry (see the note at the top of
-- Modules/Toolbox.lua) - but "unlock frames" has to be the moment its own
-- gesture becomes available, or the drawer is the one thing on screen that
-- cannot be placed while everything else can.
Movers.watchers = {}

-- Nodes that can be a parent but are not dragged themselves: the spine. Each
-- remembers the node it belongs to, so a bond that would loop back through it
-- is still seen as a loop.
Movers.nodes = {}
Movers.nodeOwner = {}

local VALID_POINTS = {
	TOPLEFT = true, TOP = true, TOPRIGHT = true,
	LEFT = true, CENTER = true, RIGHT = true,
	BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function round(v) return math.floor((v or 0) + 0.5) end

local function UIScale() return UIParent:GetEffectiveScale() or 1 end

-- ---------------------------------------------------------------------------
-- bonds
-- ---------------------------------------------------------------------------

--- The frame a node hangs from, or nil for the screen. A parent that has not
--  registered yet answers nil too: the node waits on the screen, and is bonded
--  when its parent arrives (see Adopt).
local function ParentFrame(entry)
	local p = entry.parent
	if not p or p == "screen" then return nil end
	local e = Movers.registry[p]
	if e then return e.frame end
	return Movers.nodes[p]
end

--- Whether `parent` is `name`, or hangs from it somewhere up the chain. A node
--  bonded to its own descendant is an anchor loop, which the client refuses.
local function Descends(parent, name)
	local p, hops = parent, 0
	while p and p ~= "screen" and hops < 16 do
		if p == name then return true end
		local e = Movers.registry[p]
		p = (e and e.parent) or Movers.nodeOwner[p]
		hops = hops + 1
	end
	return false
end

--- One of a frame's nine points, in UIParent units. Measured from its edges,
--  so it answers whatever the frame is anchored by and whatever its scale.
local function PointAt(f, point)
	local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
	if not (l and r and b and t) then return nil end
	local s = (f:GetEffectiveScale() or 1) / UIScale()
	local x = (point:find("LEFT") and l) or (point:find("RIGHT") and r) or (l + r) / 2
	local y = (point:find("TOP") and t) or (point:find("BOTTOM") and b) or (b + t) / 2
	return x * s, y * s
end

--- The bond that holds a node where it is NOW: its own anchor point against
--  its parent's centre, measured rather than assumed, so it is right whatever
--  put the frame there - a 1.x record, a preset, a drag.
--
--  The node's own point is whichever it is anchored by, because that point
--  stays put while the frame changes size: a bar measured by its CENTER before
--  its buttons were laid out would be bonded half a bar out.
local function MeasureBond(entry, pf)
	local f = entry.frame
	local us = UIScale()
	local fs = f:GetEffectiveScale() or us
	if fs <= 0 or us <= 0 then return nil end

	if entry.pairLead then
		local x1 = PointAt(pf, "RIGHT")
		local x2 = PointAt(f, "LEFT")
		if not (x1 and x2) then return nil end
		local len = math.max(entry.pairMin or 0, round((x2 - x1) * us / fs))
		return { parent = entry.parent, point = "LEFT", relPoint = "RIGHT", x = len, y = 0 }
	end

	local point = f:GetPoint(1)
	if not VALID_POINTS[point] then point = "CENTER" end
	local cx, cy = PointAt(f, point)
	local px, py = PointAt(pf, "CENTER")
	if not (cx and px) then return nil end
	return { parent = entry.parent, point = point, relPoint = "CENTER",
		x = round((cx - px) * us / fs), y = round((cy - py) * us / fs) }
end

--- Through the widget's own methods where Edit Mode has replaced them - see
--  PlaceOnScreen for why.
local function Place(f, point, rel, relPoint, x, y)
	local clear = f.ClearAllPointsBase or f.ClearAllPoints
	local place = f.SetPointBase or f.SetPoint
	clear(f)
	place(f, point, rel, relPoint, x, y)
end

--- Where a frame sits, re-expressed against whichever screen corner it is
--  nearest. Anchoring a bottom-centre HUD element by TOPLEFT makes it drift the
--  moment the resolution changes. Returns point, x, y in the frame's own units.
--
--  Every measurement crosses a scale boundary, and getting that wrong is what
--  made frames leap to a corner the moment you let go of them. GetLeft, GetTop
--  and GetCenter report in the FRAME's own coordinate space, UIParent:GetWidth()
--  in UIParent's, and SetPoint's offsets are read back in the frame's space
--  again. Our frames run at profile.scale (0.71 by default), so mixing the two
--  overshot by ~40%, and SetClampedToScreen then pinned the wreckage to an edge.
local function ScreenAnchor(f, growsDown)
	local fs = f:GetEffectiveScale() or 1
	local us = UIScale()
	if fs <= 0 or us <= 0 then return nil end

	local function toUI(v) return v * fs / us end
	local function toFrame(v) return v * us / fs end

	local cx, cy = f:GetCenter()
	if not cx then return nil end
	cx, cy = toUI(cx), toUI(cy)

	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local hx = cx < sw / 3 and "LEFT" or cx > sw * 2 / 3 and "RIGHT" or ""
	local vy = cy < sh / 3 and "BOTTOM" or cy > sh * 2 / 3 and "TOP" or ""

	-- A frame that grows downward has to be pinned by its top edge, or every
	-- row it gains shoves the whole thing upward off its own anchor.
	if growsDown then vy = "TOP" end

	local point = (vy .. hx)
	if point == "" then point = "CENTER" end

	local left, right = toUI(f:GetLeft()), toUI(f:GetRight())
	local bottom, top = toUI(f:GetBottom()), toUI(f:GetTop())

	local x = (hx == "LEFT") and left
		or (hx == "RIGHT") and (right - sw)
		or (cx - sw / 2)
	local y = (vy == "BOTTOM") and bottom
		or (vy == "TOP") and (top - sh)
		or (cy - sh / 2)

	return point, toFrame(x), toFrame(y)
end

local function SavePosition(entry)
	local f = entry.frame
	local point, _, relPoint, x, y = f:GetPoint(1)
	if not point then return end

	local pf = ParentFrame(entry)
	if pf then
		-- The screen half for 1.x and for presets, the bond for us.
		local sp, sx, sy = ScreenAnchor(f, entry.growsDown)
		A.db.profile.anchors[entry.name] = {
			point = sp or point, relPoint = sp or relPoint,
			x = round(sx or x), y = round(sy or y),
			lat = MeasureBond(entry, pf),
		}
	else
		A.db.profile.anchors[entry.name] = {
			point = point, relPoint = relPoint,
			x = round(x), y = round(y),
			-- Set free of the parent its module gives it, and kept free. Only by
			-- choice (SetParent): a node dragged while its parent's module is
			-- off is not a node anybody meant to set free.
			free = entry.free or nil,
		}
	end

	-- Some frames are not ours, and the system that owns them keeps its OWN
	-- record of where they go. Writing our answer down and stopping there
	-- leaves two records disagreeing, and the other one wins the next time its
	-- owner feels like restoring.
	--
	-- The chat frame is the one that matters: it belongs to Blizzard's FCF
	-- dock, which stores position per character and puts it back on events we
	-- do not all hear. On an established character its record happens to be
	-- roughly where you left things and nobody notices; on a NEW one it is the
	-- default, so a frame you just dragged goes home a few seconds later.
	--
	-- So a module that borrows somebody else's frame says how to tell them.
	-- pcall because this is somebody else's function and it is being handed a
	-- frame we have just re-anchored.
	if entry.onPlaced then pcall(entry.onPlaced, f) end
end

--- Where 1.x put a node: its screen record, or its default.
local function PlaceOnScreen(entry, saved)
	local d = entry.default
	local point, relPoint, x, y

	if saved and VALID_POINTS[saved.point] and VALID_POINTS[saved.relPoint] then
		point, relPoint, x, y = saved.point, saved.relPoint, saved.x, saved.y
	else
		point, relPoint, x, y = d.point, d.relPoint or d.point, d.x, d.y
	end

	-- A DEFAULT WITH NO POINT IN IT still has to put the frame somewhere.
	--
	-- A BACKSTOP, not the fix. What made this reachable was the action bars
	-- holding config tables that AceDB had hollowed out on a profile change,
	-- and that is fixed where it happened - see AB:OnProfileChanged. It stays
	-- because the consequence is out of all proportion to the cause: a frame
	-- with no point has no position at all, which in this API means the
	-- top-left corner of the screen and no way to find it again.
	--
	-- Centred rather than skipped, deliberately: a frame you can see in the
	-- wrong place is one you can drag, and a frame that never got a point is one
	-- you cannot.
	if not VALID_POINTS[point] then
		point, relPoint = "CENTER", "CENTER"
		x, y = x or 0, y or 0
	end
	if not VALID_POINTS[relPoint] then relPoint = point end

	-- THROUGH THE WIDGET'S OWN METHODS where something has replaced them.
	--
	-- Edit Mode is the case, and it turned out to be what had been moving the
	-- chat window all along. A frame it manages has SetPoint swapped for
	-- SetPointOverride, which anchors the frame and then tells the manager its
	-- layout has unsaved changes. Putting our own position back through that
	-- marks somebody else's saved layout dirty every time we do it, which is a
	-- side effect nobody asked for and one the player would eventually be
	-- prompted about.
	--
	-- SetPointBase and ClearAllPointsBase are the widget's own, which Edit Mode
	-- keeps precisely so that it can place a frame without telling itself the
	-- layout changed. A frame with no override has neither and gets the ordinary
	-- pair, which is every other frame in this registry.
	Place(entry.frame, point, UIParent, relPoint, x, y)
end

local function RestorePosition(entry, depth)
	if InCombatLockdown() then
		-- Re-anchoring a frame with secure descendants is protected. Defer.
		Movers._pending = Movers._pending or {}
		Movers._pending[entry.name] = true
		return
	end

	depth = depth or 0
	local saved = A.db.profile.anchors[entry.name]
	local pf = depth < 8 and ParentFrame(entry) or nil

	if pf then
		-- The parent first: a bond is measured against where it IS.
		local pe = Movers.registry[entry.parent]
		if pe then RestorePosition(pe, depth + 1) end

		local lat = saved and saved.lat
		if type(lat) == "table" and lat.parent == entry.parent
			and VALID_POINTS[lat.point] and VALID_POINTS[lat.relPoint] then
			Place(entry.frame, lat.point, pf, lat.relPoint, lat.x or 0, lat.y or 0)
		else
			-- A 1.x record, a preset's, or none: put it where 1.x would, then bond
			-- it right there. Nothing moves. A real record keeps its bond; a
			-- default is measured again each time, so a reset leaves no record.
			PlaceOnScreen(entry, saved)
			local bond = MeasureBond(entry, pf)
			if bond then
				if saved then saved.lat = bond end
				Place(entry.frame, bond.point, pf, bond.relPoint, bond.x, bond.y)
			end
		end
	else
		PlaceOnScreen(entry, saved)
	end

	-- AND THE OWNER IS TOLD ON THIS PATH TOO, not only when the player drags.
	--
	-- SavePosition has said this since the first attempt at the chat window
	-- walking home, and it was only ever half wired up: the handshake ran when
	-- you MOVED the frame and never when we merely put it back. Which is why the
	-- symptom was "only on a new character" and looked like a different bug
	-- every time.
	--
	-- On an established character you have dragged the chat window at some
	-- point, so Blizzard's record was written once and roughly agrees with ours
	-- forever after; every restore path it owns puts the frame somewhere close
	-- and nobody notices. On a NEW one nothing was ever dragged - we place the
	-- frame from our own default and Blizzard has never been told - so the first
	-- restore path we are not hooked to puts it back in its corner.
	--
	-- Hooking those paths one at a time was three fixes and counting. Telling
	-- the owner what we did means its answer is already ours, and the paths we
	-- never find give the right result anyway.
	if entry.onPlaced then pcall(entry.onPlaced, entry.frame) end
end

--- After a node moves, everything hanging from it has moved too - carried by
--  its anchor - so each one's record is written again. Without this a child
--  still on its default would be re-measured from that default next session,
--  and would stay behind on the screen while its parent went somewhere else.
local function SaveDescendants(name, depth)
	depth = depth or 0
	if depth > 8 then return end
	for _, e in pairs(Movers.registry) do
		if e.parent == name then
			SavePosition(e)
			SaveDescendants(e.name, depth + 1)
		end
	end
	for node, owner in pairs(Movers.nodeOwner) do
		if owner == name then SaveDescendants(node, depth + 1) end
	end
end

--- The node a drag actually moves. The target hands its drag to the player:
--  the two are one piece.
local function Lead(entry)
	return (entry.pairLead and Movers.registry[entry.pairLead]) or entry
end

--- The other half of a pair, from either half.
local function Partner(entry)
	if entry.pairLead then return entry end
	for _, e in pairs(Movers.registry) do
		if e.pairLead == entry.name then return e end
	end
end

--- Stretch the spine to `len` (in the partner's own units) about its own
--  centre: the lead gives way by half to the left, the partner goes out by
--  half to the right, so whatever hangs from the spine's centre stays put.
--  `from` is where the lead was when the stretch began, so a drag sets an
--  absolute length rather than accumulating rounding on every frame.
local function StretchPair(lead, partner, len, from)
	local lf, pfr = lead.frame, partner.frame
	local min = partner.pairMin or 0
	len = math.max(min, round(len))

	local us = UIScale()
	local ls = lf:GetEffectiveScale() or us
	local ps = pfr:GetEffectiveScale() or us
	local was = from.len
	local shift = (len - was) * ps / us / 2          -- UIParent units
	Place(lf, from.point, from.rel, from.relPoint, from.x - shift * us / ls, from.y)
	Place(pfr, "LEFT", lf, "RIGHT", len, 0)
	return len
end

--- Where a pair stands right now, for StretchPair.
local function PairState(lead, partner)
	local point, rel, relPoint, x, y = lead.frame:GetPoint(1)
	if not point then return nil end
	local saved = A.db.profile.anchors[partner.name]
	local len = (saved and saved.lat and saved.lat.x)
	if not len then
		local bond = MeasureBond(partner, lead.frame)
		len = bond and bond.x or (partner.pairMin or 0)
	end
	return { point = point, rel = rel or UIParent, relPoint = relPoint or point,
		x = x or 0, y = y or 0, len = len }
end

--- Stretch the spine to a length, about its centre, and keep it. The inspector
--  and the tests use this; the drag uses the same pieces.
function Movers:StretchPair(name, len)
	local entry = Movers.registry[name]
	if not entry or InCombatLockdown() then return nil end
	local lead, partner = Lead(entry), Partner(entry)
	if not (lead and partner) or lead == partner then return nil end
	local from = PairState(lead, partner)
	if not from then return nil end
	len = StretchPair(lead, partner, len, from)
	SavePosition(lead)
	SaveDescendants(lead.name)
	return len
end

-- ---------------------------------------------------------------------------
-- grid and snapping
--
-- Everything below works in *screen pixels*, converts once at each boundary, and
-- never mixes the two. That is deliberate: the last bug in this file came from
-- treating a frame-space edge as a UIParent-space one, and placing frames next
-- to each other is exactly the job where a few percent of error is visible.
-- ---------------------------------------------------------------------------

local grid

local function GridConfig()
	local c = A.db and A.db.profile.movers
	return c or { grid = true, gridSize = 16, snap = true, snapDistance = 10 }
end

local function BuildGrid()
	local f = CreateFrame("Frame", ADDON .. "MoverGrid", UIParent)
	f:SetAllPoints(UIParent)
	f:SetFrameStrata("BACKGROUND")
	f.lines = {}
	f:Hide()
	return f
end

local function GridLine(g, i)
	local t = g.lines[i]
	if not t then
		t = g:CreateTexture(nil, "BACKGROUND")
		t:SetTexture(A.Media.texture.flat)
		g.lines[i] = t
	end
	t:Show()
	return t
end

--- The lines are a real texture rather than a solid colour block, so tinting is
--  SetVertexColor. This was a private copy of W.Tint with the same signature,
--  written before there was a shared one; it is the shared one now, which is
--  also what puts the grid and the guides on the skin-change sweep.
local Tint = A.Widgets.Tint

--- Lay the grid out at the current resolution. Every fourth line is brighter,
--  which is what makes a grid readable rather than a grey haze.
local function LayGrid()
	local cfg = GridConfig()
	grid = grid or BuildGrid()

	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	local step = math.max(4, cfg.gridSize or 16)
	local c = A.Palette.c.accent
	local n = 0

	local cx, cy = w / 2, h / 2

	-- Out from the centre in both directions, so the centre line is always a
	-- line. Placing a bar "in the middle" is the single most common thing anyone
	-- does with this.
	local x = 0
	while x <= cx do
		for _, px in ipairs(x == 0 and { cx } or { cx - x, cx + x }) do
			n = n + 1
			local t = GridLine(grid, n)
			local major = (x % (step * 4) == 0)
			Tint(t, c, major and 0.28 or 0.10)
			t:ClearAllPoints()
			t:SetPoint("TOP", grid, "TOPLEFT", px, 0)
			t:SetPoint("BOTTOM", grid, "BOTTOMLEFT", px, 0)
			t:SetWidth(x == 0 and 2 or 1)
		end
		x = x + step
	end

	local y = 0
	while y <= cy do
		for _, py in ipairs(y == 0 and { cy } or { cy - y, cy + y }) do
			n = n + 1
			local t = GridLine(grid, n)
			local major = (y % (step * 4) == 0)
			Tint(t, c, major and 0.28 or 0.10)
			t:ClearAllPoints()
			t:SetPoint("LEFT", grid, "BOTTOMLEFT", 0, py)
			t:SetPoint("RIGHT", grid, "BOTTOMRIGHT", 0, py)
			t:SetHeight(y == 0 and 2 or 1)
		end
		y = y + step
	end

	for i = n + 1, #grid.lines do grid.lines[i]:Hide() end
end

local function ShowGrid(show)
	local cfg = GridConfig()
	if show and cfg.grid ~= false then
		LayGrid()
		grid:Show()
	elseif grid then
		grid:Hide()
	end
end

-- guides -------------------------------------------------------------------
-- A snap you cannot see is indistinguishable from the frame not moving where
-- you put it, so the edge that caught gets a line drawn on it.

local guides

local function Guide(i)
	guides = guides or { frame = CreateFrame("Frame", nil, UIParent), lines = {} }
	guides.frame:SetAllPoints(UIParent)
	guides.frame:SetFrameStrata("FULLSCREEN_DIALOG")
	local t = guides.lines[i]
	if not t then
		t = guides.frame:CreateTexture(nil, "OVERLAY")
		t:SetTexture(A.Media.texture.flat)
		guides.lines[i] = t
	end
	return t
end

local function ClearGuides()
	if not guides then return end
	-- `pairs`, not `ipairs`. Guides are created on demand and indexed by which
	-- axis snapped, so a horizontal-only snap leaves lines[1] nil and lines[2]
	-- set - and `ipairs` stops at the hole, so the line that was actually drawn
	-- is the one that never gets hidden. That is the purple hairline left lying
	-- across the screen after `/aether lock`.
	for _, t in pairs(guides.lines) do t:Hide() end
end

--- Test seams. The guide table is a file-local built on demand, and the bug it
--  had - a hole in the array - is invisible from outside unless the harness can
--  draw one guide and ask whether it went away.
function Movers.__test_drawGuide(i, vertical, at)
	return Movers.__drawGuide(i, vertical, at)
end

--- Forget every guide, so a test can recreate the *hole* that was the bug.
--  Without this the earlier drag tests have already filled slot 1 and `ipairs`
--  walks the whole table quite happily.
function Movers.__test_resetGuides()
	if not guides then return end
	for _, t in pairs(guides.lines) do t:Hide() end
	guides.lines = {}
end

function Movers.__test_guideShown(i)
	return guides ~= nil and guides.lines[i] ~= nil and guides.lines[i]:IsShown()
end

local function DrawGuide(i, vertical, at)
	local c = A.Palette.c.accentDeep
	local t = Guide(i)
	t:ClearAllPoints()
	if vertical then
		t:SetPoint("TOP", guides.frame, "TOPLEFT", at, 0)
		t:SetPoint("BOTTOM", guides.frame, "BOTTOMLEFT", at, 0)
		t:SetWidth(1)
	else
		t:SetPoint("LEFT", guides.frame, "BOTTOMLEFT", 0, at)
		t:SetPoint("RIGHT", guides.frame, "BOTTOMRIGHT", 0, at)
		t:SetHeight(1)
	end
	Tint(t, c, 0.9)
	t:Show()
end

Movers.__drawGuide = DrawGuide

--- Everything that moves when `entry` is dragged: the node itself, the other
--  half of its pair, and everything bonded to either, however deep. None of
--  them can be a snap target for that drag - they move with it, so snapping to
--  them chases the frame's own children and it judders between two answers
--  every frame (seen in game, 2026-10-07).
function Movers:SnapFamily(entry)
	-- From the lead, so either half of the pair answers for both.
	entry = Lead(entry)
	local skip = { [entry.frame] = true }
	local roots = { entry.name }
	local partner = Partner(entry)
	if partner and partner ~= entry then
		skip[partner.frame] = true
		roots[#roots + 1] = partner.name
	end
	for _, e in pairs(Movers.registry) do
		for _, root in ipairs(roots) do
			if e.parent and Descends(e.parent, root) then skip[e.frame] = true end
		end
	end
	return skip
end

--- Candidate lines to snap to, in UIParent units: the screen's own edges and
--  centre, and every registered frame's that is not in `skip`.
local function SnapTargets(skip)
	skip = skip or {}
	local xs, ys = {}, {}
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()

	xs[#xs + 1] = 0 ; xs[#xs + 1] = w / 2 ; xs[#xs + 1] = w
	ys[#ys + 1] = 0 ; ys[#ys + 1] = h / 2 ; ys[#ys + 1] = h

	for _, entry in pairs(Movers.registry) do
		local f = entry.frame
		if not skip[f] and f:IsShown() and f:GetLeft() then
			local s = f:GetEffectiveScale() / (UIParent:GetEffectiveScale() or 1)
			local l, r = f:GetLeft() * s, f:GetRight() * s
			local b, t = f:GetBottom() * s, f:GetTop() * s
			xs[#xs + 1] = l ; xs[#xs + 1] = r ; xs[#xs + 1] = (l + r) / 2
			ys[#ys + 1] = b ; ys[#ys + 1] = t ; ys[#ys + 1] = (b + t) / 2
		end
	end
	return xs, ys
end

Movers.__snapTargets = SnapTargets

--- Move `lo` (one edge of the frame) so that one of ours lands on a target.
--  Returns the adjusted low edge and the line it caught, or nil.
local function SnapAxis(lo, size, targets, step, threshold)
	local best, bestAt, bestDist = nil, nil, threshold

	-- our three interesting positions: low edge, centre, high edge
	local mine = { lo, lo + size / 2, lo + size }
	for _, target in ipairs(targets) do
		for i, m in ipairs(mine) do
			local d = math.abs(m - target)
			if d < bestDist then
				bestDist = d
				best = target - (i == 1 and 0 or (i == 2 and size / 2 or size))
				bestAt = target
			end
		end
	end

	-- the grid is a weaker pull than another frame, so it only applies if
	-- nothing better caught
	if not best and step and step > 0 then
		local snapped = math.floor(lo / step + 0.5) * step
		if math.abs(snapped - lo) < threshold then return snapped, nil end
	end

	return best or lo, bestAt
end

-- ---------------------------------------------------------------------------

local function CreateHandle(entry)
	local h = A.Glass.CreatePanel(UIParent, { corner = 8, shadow = 8})
	h:SetFrameStrata("DIALOG")
	h:SetAllPoints(entry.frame)
	h:EnableMouse(true)
	h:SetMovable(true)
	h:RegisterForDrag("LeftButton")
	h:Hide()

	local c = A.Palette.c
	h:SetFillColor({ c.accent[1], c.accent[2], c.accent[3], 0.22 })
	h:SetEdgeColor({ c.accent[1], c.accent[2], c.accent[3], 0.85 })

	local label = A.Widgets.Text(h, "label", "CENTER")
	label:SetPoint("CENTER")
	label:SetText(entry.label or entry.name)
	A.Widgets.Color(label, c.text)

	-- Dragging is tracked by hand rather than handed to StartMoving, because
	-- StartMoving owns the frame's position for the length of the drag and there
	-- is no way to nudge it: a snapped frame has to be *placed* where the snap
	-- says, every frame, while the mouse is still down. The cost is that we do
	-- the scale arithmetic ourselves - see the note in OnDragStop, and note that
	-- GetCursorPosition reports in true screen pixels, so it is divided by
	-- UIParent's scale and never by the frame's.
	local function Drag(self)
		-- A fight can start, or the frames can be locked from the options panel,
		-- while the button is still down. Either one makes the next SetPoint
		-- either illegal or unwanted, so stop tracking rather than find out.
		if InCombatLockdown() or not Movers.unlocked then
			self:SetScript("OnUpdate", nil)
			ClearGuides()
			return
		end

		local us = UIParent:GetEffectiveScale() or 1
		local mx, my = GetCursorPosition()
		mx, my = mx / us, my / us

		-- STRETCHING THE SPINE: the cursor carries the edge it grabbed, and the
		-- other capsule gives way by the same amount, so the centre stays put.
		local st = self._stretch
		if st then
			local d = (mx - self._grabX) * st.sign * 2
			local ps = st.partner.frame:GetEffectiveScale() or us
			StretchPair(st.lead, st.partner, st.from.len + d * us / ps, st.from)
			return
		end

		local f = self._mover.frame
		local fs = f:GetEffectiveScale() or 1
		if fs <= 0 or us <= 0 then return end

		local x = self._origX + (mx - self._grabX)
		local y = self._origY + (my - self._grabY)

		local cfg = GridConfig()
		local w, h2 = f:GetWidth() * fs / us, f:GetHeight() * fs / us
		local gx, gy

		-- Alt is the escape hatch: sometimes the place you want is a pixel off
		-- the line, and fighting a snap you cannot switch off is miserable.
		if cfg.snap ~= false and not IsAltKeyDown() then
			local xs, ys = SnapTargets(self._skip or { [f] = true })
			local step = (cfg.grid ~= false) and math.max(4, cfg.gridSize or 16) or nil
			local dist = cfg.snapDistance or 12
			x, gx = SnapAxis(x, w, xs, step, dist)
			y, gy = SnapAxis(y, h2, ys, step, dist)
		end

		ClearGuides()
		if gx then DrawGuide(1, true, gx) end
		if gy then DrawGuide(2, false, gy) end

		f:ClearAllPoints()
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x * us / fs, y * us / fs)
	end

	h:SetScript("OnDragStart", function(self)
		-- The dock's children are secure; moving their ancestor mid-combat is a
		-- protected action. Refuse rather than let the client throw.
		if InCombatLockdown() then
			A:Print(A.Bad(L.movers.create_handle.can_t_move_frames))
			return
		end
		local us = UIParent:GetEffectiveScale() or 1
		local mx, my = GetCursorPosition()
		self._grabX, self._grabY = mx / us, my / us
		self._stretch = nil

		-- Ctrl on either half of the pair stretches the spine instead.
		local partner = Partner(entry)
		if partner and IsControlKeyDown and IsControlKeyDown() then
			local lead = Lead(partner)
			local from = lead ~= partner and PairState(lead, partner)
			if from then
				self._stretch = { lead = lead, partner = partner, from = from,
					sign = (entry == partner) and 1 or -1 }
				self._dragging = true
				self:SetScript("OnUpdate", Drag)
				return
			end
		end

		-- The target's handle drags the player: they are one piece.
		local mover = Lead(entry)
		local f = mover.frame
		local fs = f:GetEffectiveScale() or 1
		if fs <= 0 or us <= 0 or not f:GetLeft() then return end
		self._mover = mover
		-- Worked out once per drag: nothing in it changes while the button is
		-- down, and it is a walk of the whole registry.
		self._skip = Movers:SnapFamily(mover)
		self._origX = f:GetLeft() * fs / us
		self._origY = f:GetBottom() * fs / us

		f:SetMovable(true)
		self._dragging = true
		self:SetScript("OnUpdate", Drag)
	end)

	h:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self._dragging = false
		ClearGuides()

		local st = self._stretch
		self._stretch = nil
		if st then
			SavePosition(st.lead)
			SaveDescendants(st.lead.name)
			return
		end

		local mover = self._mover or entry
		local f = mover.frame
		local point, x, y = ScreenAnchor(f, mover.growsDown)
		if not point then return end
		Place(f, point, UIParent, point, x, y)

		-- And back onto its parent, at wherever it was dropped.
		local pf = ParentFrame(mover)
		if pf then
			local bond = MeasureBond(mover, pf)
			if bond then Place(f, bond.point, pf, bond.relPoint, bond.x, bond.y) end
		end
		SavePosition(mover)
		SaveDescendants(mover.name)
	end)

	-- Nudge with the wheel for the last few pixels, in the node's own anchor -
	-- against its parent where it has one. The target nudges the pair.
	h:EnableKeyboard(false)
	h:SetScript("OnMouseWheel", function(_, delta)
		if InCombatLockdown() then return end
		local mover = Lead(entry)
		local point, rel, relPoint, x, y = mover.frame:GetPoint(1)
		if not point then return end
		if IsShiftKeyDown() then x = x + delta else y = y + delta end
		Place(mover.frame, point, rel or UIParent, relPoint, x, y)
		SavePosition(mover)
		SaveDescendants(mover.name)
	end)
	h:EnableMouseWheel(true)

	entry.handle = h
	return h
end

-- ---------------------------------------------------------------------------
-- public
-- ---------------------------------------------------------------------------

--- default: { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 200 }
--  opts:
--    growsDown = true      pin by the top edge when dropped, for a frame whose
--                          height changes with its contents
--    onPlaced = function(frame)
--                          called after a drop or a nudge, once our own answer
--                          is written down. For a frame we have BORROWED, this
--                          is where its real owner gets told - otherwise two
--                          records of "where does this go" disagree and the
--                          other one wins later. See Modules/Chat.lua.
--    preview = function(show)
--                          called on unlock and lock. Some frames are only on
--                          screen when the game says so - the pet bar with no
--                          pet out, the taxi button off a flight path - and you
--                          cannot drag a frame you can never see. This is how a
--                          module says "hold it up while I place it".
--    parent = "player"     the node this one hangs from (see the top of the
--                          file). Nil is the screen.
--    pairLead = "player"   this node is the other half of a PAIR with that
--                          one: bonded level to its right edge, dragged with
--                          it, stretched apart with Ctrl. The target.
--    pairMin = 40          the shortest the pair may be stretched.

--- Everything waiting on `name` as its parent is placed again: a node that
--  registered before its parent sat on the screen, and is bonded now.
local function Adopt(name)
	for _, e in pairs(Movers.registry) do
		if e.parent == name then RestorePosition(e) end
	end
end

function Movers:Register(name, frame, default, label, opts)
	local entry = Movers.registry[name]
	if entry then
		entry.frame, entry.default, entry.label = frame, default, label or entry.label
	else
		entry = { name = name, frame = frame, default = default, label = label }
		Movers.registry[name] = entry
	end
	entry.growsDown = opts and opts.growsDown or nil
	entry.preview = opts and opts.preview or entry.preview
	entry.onPlaced = opts and opts.onPlaced or entry.onPlaced
	entry.pairLead = opts and opts.pairLead or nil
	entry.pairMin = opts and opts.pairMin or nil

	-- THE SAVED PARENT WINS over the module's default: a node somebody hung
	-- elsewhere - or set free onto the screen - stays where they put it when
	-- its module registers it again on the next config change.
	entry.defaultParent = opts and opts.parent or nil
	local saved = A.db.profile.anchors[name]
	local parent = entry.defaultParent
	entry.free = (saved and saved.free) and true or nil
	if entry.free then
		parent = nil
	elseif saved and type(saved.lat) == "table" and saved.lat.parent then
		parent = saved.lat.parent
	end
	-- A parent that hangs from this node would be an anchor loop.
	if parent and Descends(parent, name) then parent = nil end
	entry.parent = parent

	frame:SetClampedToScreen(true)
	RestorePosition(entry)
	Adopt(name)

	if Movers.unlocked then
		if not entry.handle then CreateHandle(entry) end
		entry.handle:Show()
	end
	return entry
end

--- A node that can be a parent but is not dragged itself - the spine, which
--  is part of the player capsule (`owner`) and moves with it.
function Movers:RegisterNode(name, frame, owner)
	Movers.nodes[name] = frame
	Movers.nodeOwner[name] = owner
	Adopt(name)
end

--- Hang a node from a different parent, where it stands. Refused for a loop,
--  and in combat. Returns true when it took.
function Movers:SetParent(name, parent)
	local entry = Movers.registry[name]
	if not entry or InCombatLockdown() then return false end
	if parent == "screen" then parent = nil end
	if parent and (parent == name or Descends(parent, name)) then return false end
	entry.parent = parent
	entry.free = (not parent and entry.defaultParent) and true or nil
	local pf = ParentFrame(entry)
	if pf then
		local bond = MeasureBond(entry, pf)
		if bond then Place(entry.frame, bond.point, pf, bond.relPoint, bond.x, bond.y) end
	else
		local point, x, y = ScreenAnchor(entry.frame, entry.growsDown)
		if point then Place(entry.frame, point, UIParent, point, x, y) end
	end
	SavePosition(entry)
	return true
end

--- What a node hangs from, for the inspector and the tests.
function Movers:ParentOf(name)
	local entry = Movers.registry[name]
	return entry and entry.parent or nil
end

function Movers:Unregister(name)
	local entry = Movers.registry[name]
	if not entry then return end
	if entry.handle then entry.handle:Hide() end
	Movers.registry[name] = nil
end

function Movers:Restore(name)
	local entry = Movers.registry[name]
	if entry then RestorePosition(entry) end
end

function Movers:RestoreAll()
	for _, entry in pairs(Movers.registry) do RestorePosition(entry) end
end

-- Replay anything RestorePosition had to skip because it landed mid-fight.
A:RegisterEvent(Movers, "PLAYER_REGEN_ENABLED", function()
	if not Movers._pending then return end
	for name in pairs(Movers._pending) do
		local entry = Movers.registry[name]
		if entry then RestorePosition(entry) end
	end
	Movers._pending = nil
end)

--- Tell `fn` whenever placement mode turns on or off, keyed so a module that
--  re-enables does not stack a second copy of itself.
--
--  Called ONCE immediately with the current state, because the alternative is a
--  module that enables while frames are already unlocked and shows no handle
--  until you lock and unlock again.
function Movers:OnLockChanged(key, fn)
	if type(fn) ~= "function" then return end
	Movers.watchers[key] = fn
	pcall(fn, Movers.unlocked)
end

--- pcall per watcher: one module throwing must not leave the REST of the UI
--  half-unlocked, which is a worse state than either.
local function Announce()
	for _, fn in pairs(Movers.watchers) do pcall(fn, Movers.unlocked) end
end

-- ---------------------------------------------------------------------------
-- the way out
--
-- Unlocking hides nothing, but it puts a handle over everything - including the
-- Toolbox, whose rail and drawer are exactly what you would reach for to lock
-- again. So the way back is `/aether lock` or four steps into the options
-- panel, and a mode you can only leave by typing is a mode people get stuck in.
--
-- ITS OWN FRAME, and draggable, because it is one more thing over a screen you
-- are trying to arrange - and the one place it must never be is on top of the
-- frame you are dragging. Not a mover entry: a mover entry is moved by its
-- handle, and a handle over the button that hides the handles is a circle.
-- ---------------------------------------------------------------------------

local LOCK_W, LOCK_H = 132, 34

local function LockSpot()
	A.db.profile.anchors = A.db.profile.anchors or {}
	return A.db.profile.anchors.__lockButton
end

local function BuildLockButton()
	local b = A.Widgets.CreateButton(UIParent, { corner = 10 })
	b:SetSize(LOCK_W, LOCK_H)
	b:SetFrameStrata("FULLSCREEN_DIALOG")
	b:SetToplevel(true)
	b:EnableMouse(true)
	b:SetMovable(true)
	b:SetClampedToScreen(true)
	b:RegisterForDrag("LeftButton")
	b:Hide()

	local c = A.Palette.c
	b.label = A.Widgets.Text(b, "label", "CENTER")
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.label:SetText(L.common.lock_frames)
	A.Widgets.Color(b.label, c.text)
	b.__aetherLabel = b.label

	b.glyph = b:CreateTexture(nil, "OVERLAY")
	b.glyph:SetSize(12, 12)
	b.glyph:SetPoint("LEFT", b, "LEFT", 12, 0)
	A.Media:SetIcon(b.glyph, "lock")

	-- DRAG AND CLICK ON ONE BUTTON. RegisterForDrag takes the button that
	-- starts a drag out of the click path only once the drag actually starts,
	-- so a press that does not move still fires OnClick - which is what makes
	-- this both a button and a thing you can push out of the way.
	b:SetScript("OnDragStart", function(self) self:StartMoving() end)
	b:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint(1)
		if point then
			A.db.profile.anchors.__lockButton = {
				point = point, relPoint = relPoint,
				x = math.floor(x + 0.5), y = math.floor(y + 0.5),
			}
		end
	end)
	b:SetScript("OnClick", function() Movers:Lock() end)

	return b
end

--- Show it, where it was last put.
local function ShowLockButton(show)
	if not show then
		if Movers.lockButton then Movers.lockButton:Hide() end
		return
	end

	Movers.lockButton = Movers.lockButton or BuildLockButton()
	local b = Movers.lockButton

	-- PLACED EVERY TIME, from clear. Anchors set again without clearing leave a
	-- frame spanned between where it was and where it is being put.
	local spot = LockSpot()
	b:ClearAllPoints()
	if spot then
		b:SetPoint(spot.point, UIParent, spot.relPoint, spot.x, spot.y)
	else
		-- Above the middle rather than in it: the middle of the screen is where
		-- the frames you have come to move mostly are.
		b:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
	end
	b:SetScale(A.db.profile.scale or 1)
	A.Widgets.SetButtonState(b, true, false)
	b:Show()
	b:Raise()
end

Movers.ShowLockButton = ShowLockButton

function Movers:Unlock()
	Movers.unlocked = true
	ShowGrid(true)
	ShowLockButton(true)
	for _, entry in pairs(Movers.registry) do
		-- Preview first: the handle takes its size from the frame, so a frame
		-- that is still collapsed gets a handle nobody can grab.
		if entry.preview then pcall(entry.preview, true) end
		if not entry.handle then CreateHandle(entry) end
		entry.handle:Show()
	end
	Announce()
	A:Print(A.F(L.movers.unlock.frames_unlocked_drag_move,
		A.Hi(L.common.lock_frames), A.Hi("/lattice lock")))
	A:Print(A.Dim("Edges snap to the grid and to other frames; hold alt while dragging"
		.. " to place freely. Frames that only appear when the game says so - the pet"
		.. " bar, the taxi button - are held up so you can place them."))
end

function Movers:Lock()
	Movers.unlocked = false
	ShowGrid(false)
	ClearGuides()
	ShowLockButton(false)
	for _, entry in pairs(Movers.registry) do
		if entry.handle then entry.handle:Hide() end
		if entry.preview then pcall(entry.preview, false) end
	end
	Announce()
	A:Print(L.movers.lock.frames_locked)
end

--- Re-lay the grid after a settings change, so turning it off or changing the
--  spacing is visible without locking and unlocking again.
function Movers:RefreshGrid()
	if Movers.unlocked then ShowGrid(true) end
	if not Movers.unlocked and grid then grid:Hide() end
end

function Movers:Toggle()
	if Movers.unlocked then Movers:Lock() else Movers:Unlock() end
end

function Movers:ResetAll()
	wipe(A.db.profile.anchors)
	-- Every node back on the parent its module gives it.
	for _, entry in pairs(Movers.registry) do
		entry.parent, entry.free = entry.defaultParent, nil
	end
	Movers:RestoreAll()
	A:Print(L.movers.reset_all.frame_positions_reset)
end
