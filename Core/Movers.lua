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
Movers.VALID_POINTS = VALID_POINTS

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
Movers.Descends = Descends

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
Movers.PointAt = PointAt

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

local function SavePosition(entry, carried)
	local f = entry.frame
	local point, _, relPoint, x, y = f:GetPoint(1)
	if not point then return end

	local pf = ParentFrame(entry)
	if pf then
		-- The screen half for 1.x and for presets, the bond for us. A braid
		-- keeps its seat: it is an edge and a slot, not where it was measured.
		-- So does a node CARRIED by its parent: it hangs from that frame, so its
		-- bond still holds, and measuring it again turned an edge bond into a
		-- centre one - the Block seed's pet bar, off bar 2's right end, stopped
		-- reading as the seed when bar 2 was re-seated.
		local sp, sx, sy = ScreenAnchor(f, entry.growsDown)
		local old = A.db.profile.anchors[entry.name]
		local same = old and type(old.lat) == "table" and old.lat.parent == entry.parent
		local braided = same and old.braid ~= nil
		A.db.profile.anchors[entry.name] = {
			point = sp or point, relPoint = sp or relPoint,
			x = round(sx or x), y = round(sy or y),
			lat = (braided or (carried and same)) and old.lat or MeasureBond(entry, pf),
			braid = braided and old.braid or nil,
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
			SavePosition(e, true)
			SaveDescendants(e.name, depth + 1)
		end
	end
	for node, owner in pairs(Movers.nodeOwner) do
		if owner == name then SaveDescendants(node, depth + 1) end
	end
end

--- A node and everything hanging from it written again where they stand.
function Movers:SaveTree(name)
	local entry = Movers.registry[name]
	if not entry then return end
	SavePosition(entry)
	SaveDescendants(name)
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
-- the field, and snapping
--
-- THE LATTICE UNLOCK LOOK (board 4a). Unlocking dims the world and lays the
-- FIELD over it: a dot every 24, a faint strand every 96, a dashed line down
-- the middle, and the spine drawn solid across the whole screen at the
-- capsules' centre line. Frames snap to the dots.
--
-- The handoff draws at 1920x1080, so its lengths are a fraction of the screen
-- height (Px). The world cannot be desaturated from an addon - only darkened -
-- so the dimming is a black veil under every frame of ours.
--
-- Everything below works in *screen pixels*, converts once at each boundary, and
-- never mixes the two. That is deliberate: the last bug in this file came from
-- treating a frame-space edge as a UIParent-space one, and placing frames next
-- to each other is exactly the job where a few percent of error is visible.
-- ---------------------------------------------------------------------------

local grid

local function GridConfig()
	local c = A.db and A.db.profile.movers
	return c or { grid = true, snap = true, snapDistance = 10 }
end

--- A length from the handoff, in UIParent units on this screen.
local REF_H = 1080
local function Px(v) return v * (UIParent:GetHeight() or 768) / REF_H end
Movers.Px = Px

--- The field's spacing: a dot every 24, a strand every fourth dot.
local function FieldStep() return Px(24) end
Movers.FieldStep = FieldStep

local function BuildGrid()
	local f = CreateFrame("Frame", ADDON .. "MoverGrid", UIParent)
	f:SetAllPoints(UIParent)
	f:SetFrameStrata("BACKGROUND")
	f.lines, f.dashes = {}, {}

	-- The world, dimmed. Under every frame of ours: BACKGROUND, level 0.
	f.veil = f:CreateTexture(nil, "BACKGROUND")
	f.veil:SetAllPoints(f)
	f.veil:SetColorTexture(0, 0, 0, 0.45)

	-- One texture for every dot: REPEAT turns its texcoords into a count of
	-- cells, which LayGrid sets from the step and the screen.
	f.dots = f:CreateTexture(nil, "ARTWORK")
	f.dots:SetAllPoints(f)
	f.dots:SetTexture(A.Media.texture.fieldDot, "REPEAT", "REPEAT")

	-- The spine, across the whole screen. Hung from the spine node itself, so
	-- it goes where the capsules go while they are dragged.
	f.spine = f:CreateLine(nil, "OVERLAY")

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

--- Lay the field out at the current resolution, out from the centre so the
--  middle of the screen is always on a dot and a strand. "Show grid" off takes
--  the dots, strands and centre line away and leaves the dimming and the
--  spine, which are what say the frames are unlocked.
local function LayGrid()
	local cfg = GridConfig()
	grid = grid or BuildGrid()

	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	local step = FieldStep()
	local c = A.Palette.c.accent
	local cx, cy = w / 2, h / 2
	local field = cfg.grid ~= false

	-- The dots: the tile's dot is at its centre, so the offset that puts one
	-- on the screen's centre is half a cell less the distance to it.
	local u0, v0 = 0.5 - cx / step, 0.5 - cy / step
	grid.dots:SetTexCoord(u0, u0 + w / step, v0, v0 + h / step)
	Tint(grid.dots, c, 0.25)
	grid.dots:SetShown(field)

	-- A strand every fourth dot. The vertical centre is the dashed line below.
	local n = 0
	local function strand(vertical, at)
		n = n + 1
		local t = GridLine(grid, n)
		Tint(t, c, 0.16)
		t:ClearAllPoints()
		if vertical then
			t:SetPoint("TOP", grid, "TOPLEFT", at, 0)
			t:SetPoint("BOTTOM", grid, "BOTTOMLEFT", at, 0)
			t:SetWidth(1)
		else
			t:SetPoint("LEFT", grid, "BOTTOMLEFT", 0, at)
			t:SetPoint("RIGHT", grid, "BOTTOMRIGHT", 0, at)
			t:SetHeight(1)
		end
	end
	local major = step * 4
	if field then
		for k = major, cx, major do strand(true, cx - k); strand(true, cx + k) end
		strand(false, cy)
		for k = major, cy, major do strand(false, cy - k); strand(false, cy + k) end
	end
	for i = n + 1, #grid.lines do grid.lines[i]:Hide() end

	-- The centre, dashed 6 on 8 off.
	local d, y, dash, gap = 0, h, Px(6), Px(8)
	while field and y > 0 do
		d = d + 1
		local t = grid.dashes[d]
		if not t then
			t = grid:CreateTexture(nil, "ARTWORK")
			t:SetTexture(A.Media.texture.flat)
			grid.dashes[d] = t
		end
		Tint(t, c, 0.3)
		t:ClearAllPoints()
		t:SetPoint("TOP", grid, "BOTTOMLEFT", cx, y)
		t:SetSize(1, math.min(dash, y))
		t:Show()
		y = y - dash - gap
	end
	for i = d + 1, #grid.dashes do grid.dashes[i]:Hide() end

	-- The spine, solid, across the screen - only while its capsules are here.
	local spine = Movers.nodes.spine
	if spine and Movers.registry[Movers.nodeOwner.spine] then
		local l = grid.spine
		l:SetStartPoint("CENTER", spine, -10000, 0)
		l:SetEndPoint("CENTER", spine, 10000, 0)
		l:SetThickness(Px(1.5))
		l:SetColorTexture(c[1], c[2], c[3], 0.55)
		l:Show()
	else
		grid.spine:Hide()
	end
end

local function ShowGrid(show)
	if show then
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

-- bonds ----------------------------------------------------------------------
-- A line from each child's centre to its parent's, drawn only while unlocked
-- (board 4a), and a junction on the nodes that are parents but have no handle
-- of their own - the spine. The two halves of the pair get no bond: the spine
-- is what joins them, and the field draws it.
--
-- LINES ANCHORED TO THE FRAMES THEMSELVES, so a drag carries its bonds with
-- it and nothing has to be redrawn every frame. Above the field, below the
-- handles.

local bonds

local function DrawBonds()
	if not bonds then
		bonds = CreateFrame("Frame", ADDON .. "MoverBonds", UIParent)
		bonds:SetAllPoints(UIParent)
		bonds:SetFrameStrata("HIGH")
		bonds.lines, bonds.nodes = {}, {}
	end
	local c = A.Palette.c.accent

	local n = 0
	for _, e in pairs(Movers.registry) do
		local pf = not e.pairLead and ParentFrame(e)
		if pf then
			n = n + 1
			local l = bonds.lines[n] or bonds:CreateLine(nil, "ARTWORK")
			bonds.lines[n] = l
			l:SetStartPoint("CENTER", e.frame, 0, 0)
			l:SetEndPoint("CENTER", pf, 0, 0)
			l:SetThickness(Px(1.5))
			l:SetColorTexture(c[1], c[2], c[3], 0.6)
			l.child, l.parent = e.name, e.parent
			l:Show()
		end
	end
	for i = n + 1, #bonds.lines do bonds.lines[i]:Hide(); bonds.lines[i].child = nil end

	local k = 0
	for name, nf in pairs(Movers.nodes) do
		if Movers.registry[Movers.nodeOwner[name]] then
			k = k + 1
			local t = bonds.nodes[k] or bonds:CreateTexture(nil, "OVERLAY")
			bonds.nodes[k] = t
			t:SetTexture(A.Media.texture.diamond)
			t:SetSize(Px(10), Px(10))
			t:ClearAllPoints()
			t:SetPoint("CENTER", nf, "CENTER", 0, 0)
			Tint(t, c, 1)
			t.node = name
			t:Show()
		end
	end
	for i = k + 1, #bonds.nodes do bonds.nodes[i]:Hide(); bonds.nodes[i].node = nil end

	bonds:Show()
end

Movers.__bonds = function() return bonds end

local function HideBonds()
	if bonds then bonds:Hide() end
end

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
--  Returns the adjusted low edge and the line it caught, or nil. `origin` is
--  where the field's dots start on this axis - the screen's centre, which is
--  where LayGrid lays them out from.
local function SnapAxis(lo, size, targets, step, threshold, origin)
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

	-- the field is a weaker pull than another frame, so it only applies if
	-- nothing better caught
	if not best and step and step > 0 then
		origin = origin or 0
		local snapped = origin + math.floor((lo - origin) / step + 0.5) * step
		if math.abs(snapped - lo) < threshold then return snapped, nil end
	end

	return best or lo, bestAt
end

-- ---------------------------------------------------------------------------
-- the drag's own signals (board 4a)
--
-- SNAP: while a child is dragged its parent's centre lines are the strongest
-- pull, and when one catches, the drag says so - a green diamond on the
-- child's centre, a dashed green bond to the parent, and SNAP · PLAYER with a
-- chevron and the distance in field units (24 to a dot).
--
-- BOND: the junction under the cursor that a drop would hang the node from,
-- lit green - or red, with the reason, where the bond would be refused.
--
-- THE INSPECTOR: Parent, Offset, Grows and Scale beside the dragged node, and
-- the spine's length while it is being stretched.
--
-- All of it on frames of our own over the handles; none of it is saved.
-- ---------------------------------------------------------------------------

-- Chevron.tga points down, and SetRotation turns counter-clockwise.
local ARROW = { down = 0, right = math.pi / 2, up = math.pi, left = -math.pi / 2 }

local feedback

local function Feedback()
	if feedback then return feedback end
	local f = CreateFrame("Frame", ADDON .. "MoverSnap", UIParent)
	f:SetAllPoints(UIParent)
	f:SetFrameStrata("FULLSCREEN")
	f.dashes = {}
	f.glow = f:CreateTexture(nil, "ARTWORK")
	f.glow:SetTexture(A.Media.texture.glow)
	f.snap = f:CreateTexture(nil, "OVERLAY")
	f.snap:SetTexture(A.Media.texture.diamond)
	f.snapText = A.Widgets.Text(f, "label", "LEFT")
	f.snapArrow = f:CreateTexture(nil, "OVERLAY")
	f.snapArrow:SetTexture(A.Media.texture.chevron)
	f.snapDist = A.Widgets.Text(f, "label", "LEFT")
	f.bond = f:CreateTexture(nil, "OVERLAY")
	f.bond:SetTexture(A.Media.texture.diamond)
	f.bondText = A.Widgets.Text(f, "label", "LEFT")
	-- The reshape ghost (strands brief 9b).
	f.ghost = f:CreateTexture(nil, "BACKGROUND")
	f.ghost:SetTexture(A.Media.texture.flat)
	f.ghostDashes = {}
	f.ghostText = A.Widgets.Text(f, "label", "LEFT")
	feedback = f
	return f
end

Movers.__feedback = function() return feedback end

--- Dashes from one point to another, out of short Lines on `f` taken from
--  `pool` after its first `n`: a Line cannot be dashed itself. Points are from
--  the bottom-left of opts.rel (UIParent unless given), in its units.
--  opts: rel, alpha (1), dash and gap (4 and 6 field units). Returns how many
--  of the pool are now in use.
local function Dash(f, pool, n, x1, y1, x2, y2, c, thick, opts)
	opts = opts or {}
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	if len <= 0 then return n end
	local ux, uy = dx / len, dy / len
	local rel, a = opts.rel or UIParent, opts.alpha or 1
	local dash, gap, t, stop = opts.dash or Px(4), opts.gap or Px(6), 0, n + 400
	while t < len and n < stop do
		n = n + 1
		local l = pool[n] or f:CreateLine(nil, "ARTWORK")
		pool[n] = l
		local e = math.min(t + dash, len)
		l:SetStartPoint("BOTTOMLEFT", rel, x1 + ux * t, y1 + uy * t)
		l:SetEndPoint("BOTTOMLEFT", rel, x1 + ux * e, y1 + uy * e)
		l:SetThickness(thick)
		l:SetColorTexture(c[1], c[2], c[3], a)
		l:Show()
		t = e + gap
	end
	return n
end
Movers.Dash = Dash

--- A dashed line between two points in UIParent units. With no points it clears.
local function DashedLine(x1, y1, x2, y2, c)
	local f = Feedback()
	local n = x1 and Dash(f, f.dashes, 0, x1, y1, x2, y2, c, Px(2)) or 0
	for i = n + 1, #f.dashes do f.dashes[i]:Hide() end
end

--- The shape a reshape would give: g = { l, b, r, t, label, x, y } in UIParent
--  units, the label at the cursor (x, y); nil takes it away. A dashed outline
--  1.5 thick on a 6% fill, in the snap's green (strands brief tokens).
local function ShowGhost(g)
	local f = Feedback()
	f.ghostInfo = g
	local n = 0
	if g then
		local c = A.Palette.c.friendly
		f.ghost:ClearAllPoints()
		f.ghost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", g.l, g.b)
		f.ghost:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", g.r, g.t)
		Tint(f.ghost, c, 0.06)
		f.ghost:Show()
		local th = Px(1.5)
		n = Dash(f, f.ghostDashes, n, g.l, g.t, g.r, g.t, c, th)
		n = Dash(f, f.ghostDashes, n, g.r, g.t, g.r, g.b, c, th)
		n = Dash(f, f.ghostDashes, n, g.r, g.b, g.l, g.b, c, th)
		n = Dash(f, f.ghostDashes, n, g.l, g.b, g.l, g.t, c, th)
		f.ghostText:SetText(g.label)
		f.ghostText:ClearAllPoints()
		f.ghostText:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.x + Px(14), g.y - Px(14))
		A.Widgets.Color(f.ghostText, c)
		f.ghostText:Show()
	else
		f.ghost:Hide()
		f.ghostText:Hide()
	end
	for i = n + 1, #f.ghostDashes do f.ghostDashes[i]:Hide() end
end

--- The green snap: s = { x, y = the child's centre, px, py = the parent's,
--  name, dir, dist, labelX }, or nil to take it away.
local function ShowSnap(s)
	local f = Feedback()
	f.snapInfo = s
	local parts = { f.glow, f.snap, f.snapText, f.snapArrow, f.snapDist }
	if not s then
		for _, r in ipairs(parts) do r:Hide() end
		DashedLine()
		return
	end
	local g = A.Palette.c.friendly
	f.snap:SetSize(Px(14), Px(14))
	f.snap:ClearAllPoints()
	f.snap:SetPoint("CENTER", UIParent, "BOTTOMLEFT", s.x, s.y)
	Tint(f.snap, g, 1)
	f.glow:SetSize(Px(44), Px(44))
	f.glow:ClearAllPoints()
	f.glow:SetPoint("CENTER", f.snap, "CENTER", 0, 0)
	Tint(f.glow, g, 0.55)
	DashedLine(s.x, s.y, s.px, s.py, g)

	f.snapText:SetText(("%s · %s"):format(L.movers.snap.snap, s.name))
	f.snapText:ClearAllPoints()
	f.snapText:SetPoint("LEFT", UIParent, "BOTTOMLEFT", s.labelX, s.y)
	A.Widgets.Color(f.snapText, g)
	f.snapArrow:SetSize(Px(10), Px(10))
	f.snapArrow:SetRotation(ARROW[s.dir] or 0)
	f.snapArrow:ClearAllPoints()
	f.snapArrow:SetPoint("LEFT", f.snapText, "RIGHT", Px(6), 0)
	Tint(f.snapArrow, g, 1)
	f.snapDist:SetText(tostring(s.dist))
	f.snapDist:ClearAllPoints()
	f.snapDist:SetPoint("LEFT", f.snapArrow, "RIGHT", Px(4), 0)
	A.Widgets.Color(f.snapDist, g)
	for _, r in ipairs(parts) do r:Show() end
end

--- The junction a drop would bond to: t = { x, y, label, refused }, or nil.
local function ShowBondTarget(t)
	local f = Feedback()
	f.bondInfo = t
	if not t then
		f.bond:Hide()
		f.bondText:Hide()
		return
	end
	local c = t.refused and A.Palette.c.danger or A.Palette.c.friendly
	f.bond:SetSize(Px(14), Px(14))
	f.bond:ClearAllPoints()
	f.bond:SetPoint("CENTER", UIParent, "BOTTOMLEFT", t.x, t.y)
	Tint(f.bond, c, 1)
	f.bondText:SetText(("%s · %s"):format(
		t.refused and L.movers.snap.no_bond or L.movers.snap.bond, t.label))
	f.bondText:ClearAllPoints()
	f.bondText:SetPoint("LEFT", f.bond, "RIGHT", Px(8), 0)
	A.Widgets.Color(f.bondText, c)
	f.bond:Show()
	f.bondText:Show()
end

--- What a node is called on screen: the name its module gave it.
local function NodeLabel(name)
	local e = Movers.registry[name]
	return tostring((e and e.label) or name):upper()
end

--- Why `mover` may not hang from `parent`, or nil if it may.
local function BondRefusal(mover, parent)
	if mover.pairLead or Partner(mover) then return L.movers.bond.pair end
	if Descends(parent, mover.name) then
		return A.F(L.movers.bond.loop, NodeLabel(mover.name), NodeLabel(parent), NodeLabel(parent))
	end
	return nil
end

--- The junction under the cursor that a drop would hang `mover` from: another
--  node's centre within 14 of it. Not its own, not its pair's, and not the
--  one it already hangs from - dropping there changes nothing.
local function JunctionUnder(mover, mx, my)
	local reach = Px(14)
	local partner = Partner(mover)
	local best, bestD
	local function consider(name, frame)
		if name == mover.name or (partner and name == partner.name) then return end
		local x, y = PointAt(frame, "CENTER")
		if not x then return end
		local d = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
		if d <= reach and (not bestD or d < bestD) then
			best, bestD = { name = name, x = x, y = y }, d
		end
	end
	for name, e in pairs(Movers.registry) do
		if e.handle and e.handle:IsShown() then consider(name, e.frame) end
	end
	for name, nf in pairs(Movers.nodes) do
		if Movers.registry[Movers.nodeOwner[name]] then consider(name, nf) end
	end
	if not best or best.name == mover.parent then return nil end
	best.label = NodeLabel(best.name)
	best.refused = BondRefusal(mover, best.name)
	return best
end

Movers.__junctionUnder = JunctionUnder

-- the inspector ---------------------------------------------------------------

local INSPECTOR_W, ROW_H = 230, 20
local inspector

local function Inspector()
	if inspector then return inspector end
	local p = A.Glass.CreatePanel(UIParent, { corner = 12 })
	p:SetFrameStrata("FULLSCREEN")
	p:SetSize(INSPECTOR_W, 40)
	p:EnableMouse(false)
	p:Hide()
	p.title = A.Widgets.Text(p, "label", "LEFT")
	p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -12)
	p.rows = {}
	for i = 1, 8 do
		local k = A.Widgets.Text(p, "label", "LEFT")
		k:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -12 - i * ROW_H)
		local v = A.Widgets.Text(p, "label", "RIGHT")
		v:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -12 - i * ROW_H)
		p.rows[i] = { k = k, v = v }
	end
	inspector = p
	return p
end

Movers.__inspector = function() return inspector end

--- Which way a node grows, from the edge it is pinned by: pinned by its top it
--  grows down, by its left it grows right, by its centre both ways.
local function GrowsText(point)
	point = point or "CENTER"
	local v = (point:find("TOP") and L.movers.inspector.down)
		or (point:find("BOTTOM") and L.movers.inspector.up)
	local h = (point:find("LEFT") and L.movers.inspector.right)
		or (point:find("RIGHT") and L.movers.inspector.left)
	if v and h then return A.F(L.movers.inspector.two_ways, v, tostring(h):lower()) end
	return v or h or L.movers.inspector.both
end

--- Show the inspector beside `frame` with `rows` ({ label, value } pairs), on
--  whichever side has room; nil hides it.
local function ShowInspector(title, rows, frame)
	local p = Inspector()
	if not title then p:Hide() return end
	local c = A.Palette.c
	local g = c.friendly
	local scale = A.db.profile.scale or 1
	p:SetScale(scale)
	local nf = c.nodeFill
	p:SetFillColor({ nf[1], nf[2], nf[3], 0.9 })
	p:SetEdgeColor({ g[1], g[2], g[3], 0.4 })
	p.title:SetText(title)
	A.Widgets.Color(p.title, g)
	for i, r in ipairs(p.rows) do
		local row = rows[i]
		if row then
			r.k:SetText(row[1])
			r.v:SetText(row[2])
			A.Widgets.Color(r.k, c.textDim)
			A.Widgets.Color(r.v, c.text)
			r.k:Show()
			r.v:Show()
		else
			r.k:Hide()
			r.v:Hide()
		end
	end
	p:SetHeight(24 + ROW_H * (#rows + 1))

	local l, b = PointAt(frame, "BOTTOMLEFT")
	local r, t = PointAt(frame, "TOPRIGHT")
	if not l then p:Hide() return end
	local w, sw, sh = INSPECTOR_W * scale, UIParent:GetWidth(), UIParent:GetHeight()
	local x = (r + Px(16) + w <= sw) and (r + Px(16)) or math.max(0, l - Px(16) - w)
	local top = math.max(p:GetHeight() * scale, math.min(t, sh - Px(8)))
	p:ClearAllPoints()
	p:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, top / scale)
	p:Show()
end

--- The inspector's rows for a node being dragged: its parent, its centre's
--  offset from the parent's (up is positive) in field units, which way it
--  grows from where it would be pinned, and its scale against the HUD's.
--  `cols` and `rows` are the shape a reshape would give, passed to the node's
--  own rows.
local function NodeRows(entry, cols, rows)
	local f = entry.frame
	local pf = not entry.pairLead and ParentFrame(entry)
	local cx, cy = PointAt(f, "CENTER")
	local px, py
	if pf then px, py = PointAt(pf, "CENTER")
	else px, py = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2 end
	local unit = Px(1)
	local point = ScreenAnchor(f, entry.growsDown)
	local scale = (f:GetEffectiveScale() or 1) / UIScale() / (A.db.profile.scale or 1)
	local out = {
		{ L.movers.inspector.parent, pf and NodeLabel(entry.parent) or L.movers.inspector.screen },
		{ L.movers.inspector.offset, ("%d, %d"):format(round(((cx or 0) - (px or 0)) / unit),
			round(((cy or 0) - (py or 0)) / unit)) },
		{ L.movers.inspector.grows, GrowsText(point) },
		{ L.movers.inspector.scale, ("%d%%"):format(round(scale * 100)) },
	}
	local host = A.Braids and A.Braids:HostOf(entry.name)
	if host then out[#out + 1] = { L.movers.inspector.braided, NodeLabel(host) } end
	-- The node's own: a strand's shape, size and energy.
	if entry.rows then
		for _, r in ipairs(entry.rows(cols, rows)) do out[#out + 1] = r end
	end
	return out
end

-- hollow junctions -------------------------------------------------------------

--- Whether a node is on the lattice: on each axis one of its edges or its
--  centre lies on a dot of the field, on another frame's line, or on its
--  parent's centre line. A node placed with Shift usually is not, and its
--  junction is drawn hollow to say so (board 4a). Worked out, never saved.
local function OnLattice(entry)
	local f = entry.frame
	local l, b = PointAt(f, "BOTTOMLEFT")
	local r, t = PointAt(f, "TOPRIGHT")
	if not (l and r) then return true end
	local xs, ys = SnapTargets(Movers:SnapFamily(entry))
	local pf = not entry.pairLead and ParentFrame(entry)
	if pf then
		local px, py = PointAt(pf, "CENTER")
		if px then xs[#xs + 1], ys[#ys + 1] = px, py end
	end
	local step = (GridConfig().grid ~= false) and FieldStep() or nil
	local function on(lo, hi, targets, origin)
		for _, m in ipairs({ lo, (lo + hi) / 2, hi }) do
			for _, tg in ipairs(targets) do
				if math.abs(m - tg) <= 1 then return true end
			end
			if step then
				local k = (m - origin) / step
				if math.abs(k - math.floor(k + 0.5)) * step <= 1 then return true end
			end
		end
		return false
	end
	return on(l, r, xs, UIParent:GetWidth() / 2) and on(b, t, ys, UIParent:GetHeight() / 2)
end

Movers.__onLattice = OnLattice

local function SetJunction(entry, on)
	if not entry.handle then return end
	entry.handle.junction:SetTexture(on and A.Media.texture.diamond or A.Media.texture.diamondRim)
	entry.handle.onLattice = on and true or false
end

--- Every shown node's junction, filled or hollow, after anything has moved.
local function RefreshJunctions()
	for _, e in pairs(Movers.registry) do
		if e.handle and e.handle:IsShown() then SetJunction(e, OnLattice(e)) end
	end
end

-- ---------------------------------------------------------------------------

--- The wire outline a node wears while unlocked (board 4a): a pill for a
--  unit, a rounded rectangle for anything else, its junction - a diamond - at
--  its centre, and its name in capitals on a tag in the top-left corner.
--  Dressed again on every unlock, so a skin, a resolution or a size changed
--  since the last one is picked up.
--
--  THE NAME IS NOT IN THE MIDDLE (Joe, 2026-10-07, in game). The middle is
--  where the junction is and where the bonds and the dashed centre line meet,
--  so a centred name had a diamond on it and lines through it. The tag is a
--  frame of its own over the handle, with a dark backing, so whatever passes
--  under it goes behind it instead of through the letters.
local function DressHandle(entry)
	local h = entry.handle
	local c = A.Palette.c.accent
	h:SetFillColor({ c[1], c[2], c[3], 0.06 })
	h:SetEdgeColor({ c[1], c[2], c[3], 0.8 })
	h.junction:SetSize(Px(10), Px(10))
	Tint(h.junction, c, 1)

	h.label:SetText(tostring(entry.label or entry.name):upper())
	A.Widgets.Color(h.label, c)
	local tag = h.tag
	local nf = A.Palette.c.nodeFill
	tag:SetFillColor({ nf[1], nf[2], nf[3], 0.9 })
	tag:SetEdgeColor({ c[1], c[2], c[3], 0.35 })
	local th = math.ceil((h.label:GetStringHeight() or 10) + 6)
	tag:SetSize(math.ceil((h.label:GetStringWidth() or 0) + 12), th)
	A.Glass.SetPanelCorner(tag, th / 2)
	-- Inside the corner. A pill has no corner - its end is a half circle - so
	-- its tag starts where the straight top edge does.
	local inset = (entry.shape == "pill") and math.max(6, (h:GetHeight() or 0) / 2) or 6
	tag:ClearAllPoints()
	tag:SetPoint("TOPLEFT", h, "TOPLEFT", inset, -4)

	-- The shape handle, on a strand with more than one shape to take.
	local g = h.grip
	if g then
		g:SetSize(Px(16), Px(16))
		g.tex:SetSize(Px(10), Px(10))
		Tint(g.tex, c, 1)
		local shapes = entry.reshape and entry.reshape.shapes()
		g:SetShown(shapes ~= nil and #shapes >= 2)
	end
end

-- reshaping ------------------------------------------------------------------
-- STRANDS BRIEF 9b: the bottom-right junction is the shape handle. Dragging it
-- picks the nearest cols x rows for the extent from the strand's top-left to
-- the cursor, shown as a green ghost; letting go lays the strand out in it.
-- Button size never changes.

--- The shape in `shapes` whose size is nearest w x h, in UIParent units.
local function NearestShape(shapes, w, h)
	local best, bestD
	for _, s in ipairs(shapes) do
		local d = (s.w - w) ^ 2 + (s.h - h) ^ 2
		if not bestD or d < bestD then best, bestD = s, d end
	end
	return best
end
Movers.NearestShape = NearestShape

--- Where frame `f` would sit at w x h: it keeps the point it is anchored by,
--  so a bar hung by its top centre reshapes about its centre. l, b, r, t.
local function LandingRect(f, w, h)
	local point = f:GetPoint(1)
	if not VALID_POINTS[point] then point = "CENTER" end
	local px, py = PointAt(f, point)
	if not px then return nil end
	local l = point:find("LEFT") and px or point:find("RIGHT") and (px - w) or (px - w / 2)
	local t = point:find("TOP") and py or point:find("BOTTOM") and (py + h) or (py + h / 2)
	return l, t - h, l + w, t
end

local function CreateGrip(entry, h)
	local g = CreateFrame("Button", nil, h)
	g:SetPoint("CENTER", h, "BOTTOMRIGHT", 0, 0)
	g:SetFrameLevel((h:GetFrameLevel() or 1) + 5)
	g:EnableMouse(true)
	g:RegisterForDrag("LeftButton")
	g.tex = g:CreateTexture(nil, "OVERLAY")
	g.tex:SetTexture(A.Media.texture.diamond)
	g.tex:SetPoint("CENTER", g, "CENTER", 0, 0)
	g:Hide()

	local function Finish(self, commit)
		self:SetScript("OnUpdate", nil)
		local rs = self._reshape
		self._reshape = nil
		ShowGhost(nil)
		ShowInspector(nil)
		Tint(self.tex, A.Palette.c.accent, 1)
		if not (commit and rs and rs.pick) then return end
		if rs.pick.cols == rs.cols and rs.pick.rows == rs.rows then return end
		if entry.reshape.apply(rs.pick.cols, rs.pick.rows) then
			-- Its bond is unchanged; only the screen half of the records moves.
			if A.db.profile.anchors[entry.name] then SavePosition(entry, true) end
			SaveDescendants(entry.name)
			RefreshJunctions()
		end
	end

	local function Track(self)
		if InCombatLockdown() or not Movers.unlocked then Finish(self, false) return end
		local rs = self._reshape
		local us = UIScale()
		local mx, my = GetCursorPosition()
		mx, my = mx / us, my / us
		local s = NearestShape(rs.shapes, mx - rs.l, rs.t - my)
		rs.pick = s
		local l, b, r, t = LandingRect(entry.frame, s.w, s.h)
		if not l then return end
		ShowGhost({ l = l, b = b, r = r, t = t, x = mx, y = my,
			label = A.F(L.movers.inspector.shape_cr, s.cols, s.rows) })
		ShowInspector(NodeLabel(entry.name), NodeRows(entry, s.cols, s.rows), entry.frame)
	end

	g:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then
			A:Print(A.Bad(L.movers.create_handle.can_t_move_frames))
			return
		end
		local shapes = entry.reshape and entry.reshape.shapes() or {}
		local l, b = PointAt(entry.frame, "BOTTOMLEFT")
		local r, t = PointAt(entry.frame, "TOPRIGHT")
		if #shapes < 2 or not l then return end
		local now = NearestShape(shapes, r - l, t - b)
		self._reshape = { shapes = shapes, l = l, t = t, cols = now.cols, rows = now.rows }
		Tint(self.tex, A.Palette.c.friendly, 1)
		self:SetScript("OnUpdate", Track)
	end)
	g:SetScript("OnDragStop", function(self) Finish(self, true) end)

	h.grip = g
end

local function CreateHandle(entry)
	local h = (entry.shape == "pill") and A.Glass.CreatePill(UIParent, {})
		or A.Glass.CreatePanel(UIParent, { corner = 8 })
	h:SetFrameStrata("DIALOG")
	h:SetAllPoints(entry.frame)
	h:EnableMouse(true)
	h:SetMovable(true)
	h:RegisterForDrag("LeftButton")
	h:Hide()

	-- A child frame, so it draws over the handle's own junction; deaf to the
	-- mouse, so a drag that starts on it still moves the node.
	h.tag = A.Glass.CreatePanel(h, { corner = 8 })
	h.tag:EnableMouse(false)
	h.label = A.Widgets.Text(h.tag, "label", "CENTER")
	h.label:SetPoint("CENTER", h.tag, "CENTER", 0, 0)

	h.junction = h:CreateTexture(nil, "OVERLAY")
	h.junction:SetTexture(A.Media.texture.diamond)
	h.junction:SetPoint("CENTER", h, "CENTER", 0, 0)

	if entry.reshape then CreateGrip(entry, h) end

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
			ShowSnap(nil)
			ShowBondTarget(nil)
			ShowInspector(nil)
			if A.Braids then A.Braids:ShowEdge(nil) end
			if self._mover and self._mover.park then self._mover.park.finish(false) end
			self._park = nil
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
			local len = StretchPair(st.lead, st.partner, st.from.len + d * us / ps, st.from)
			ShowInspector(L.movers.inspector.spine:upper(), {
				{ L.movers.inspector.length, tostring(round(len * ps / us / Px(1))) },
			}, st.partner.frame)
			return
		end

		local mover = self._mover
		local f = mover.frame
		local fs = f:GetEffectiveScale() or 1
		if fs <= 0 or us <= 0 then return end

		local x = self._origX + (mx - self._grabX)
		local y = self._origY + (my - self._grabY)

		local cfg = GridConfig()
		local w, h2 = f:GetWidth() * fs / us, f:GetHeight() * fs / us
		local gx, gy, snap

		-- Shift is the escape hatch (board 4a; Alt until 2026-10-07): sometimes
		-- the place you want is a pixel off the line, and fighting a snap you
		-- cannot switch off is miserable.
		if cfg.snap ~= false and not IsShiftKeyDown() then
			local dist = cfg.snapDistance or 12

			-- THE PARENT'S CENTRE LINES FIRST, before any other frame or the
			-- field: a child lined up on its parent is what the lattice is.
			local onX, onY, px, py
			local pf = self._parentFrame
			if pf then
				px, py = PointAt(pf, "CENTER")
				if px then
					if math.abs(x + w / 2 - px) < dist then x = px - w / 2; onX = true end
					if math.abs(y + h2 / 2 - py) < dist then y = py - h2 / 2; onY = true end
				end
			end

			local xs, ys = SnapTargets(self._skip or { [f] = true })
			local step = (cfg.grid ~= false) and FieldStep() or nil
			if not onX then x, gx = SnapAxis(x, w, xs, step, dist, UIParent:GetWidth() / 2) end
			if not onY then y, gy = SnapAxis(y, h2, ys, step, dist, UIParent:GetHeight() / 2) end

			-- One axis lined up says where the child is from its parent. Both
			-- means it is sitting on top of it, which has no direction to name.
			local cx, cy = x + w / 2, y + h2 / 2
			if onX ~= onY then
				local d = onX and (cy - py) or (cx - px)
				snap = {
					x = cx, y = cy, px = px, py = py,
					name = NodeLabel(mover.parent),
					dir = onX and (d >= 0 and "up" or "down") or (d >= 0 and "right" or "left"),
					dist = round(math.abs(d) / Px(1)),
					labelX = x + w + Px(14),
				}
			end
		end

		ClearGuides()
		if gx then DrawGuide(1, true, gx) end
		if gy then DrawGuide(2, false, gy) end
		ShowSnap(snap)

		f:ClearAllPoints()
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x * us / fs, y * us / fs)

		-- Over the parked row, a drop hides it; nothing else is offered.
		self._park = mover.park and mover.park.over(mx, my) or nil
		-- Where a drop would bond it, and what the inspector reads now.
		self._bondTo = not self._park and JunctionUnder(mover, mx, my) or nil
		ShowBondTarget(self._bondTo)
		-- A strand edge within 8 of another's lights: a drop braids it there.
		-- A junction under the cursor is the stronger signal.
		self._braid = nil
		if A.Braids and mover.braid and not self._bondTo and not self._park then
			self._braid = A.Braids:Probe(mover, self._skip)
		end
		if A.Braids then A.Braids:ShowEdge(self._braid) end
		SetJunction(mover, OnLattice(mover))
		ShowInspector(NodeLabel(mover.name), NodeRows(mover), f)
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
		self._bondTo = nil
		-- The pair has no parent of its own to line up on; the spine is theirs.
		self._parentFrame = (not mover.pairLead) and ParentFrame(mover) or nil
		-- Worked out once per drag: nothing in it changes while the button is
		-- down, and it is a walk of the whole registry.
		self._skip = Movers:SnapFamily(mover)
		self._origX = f:GetLeft() * fs / us
		self._origY = f:GetBottom() * fs / us

		f:SetMovable(true)
		self._dragging = true
		self._park = nil
		if mover.park then mover.park.start() end
		self:SetScript("OnUpdate", Drag)
	end)

	h:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self._dragging = false
		ClearGuides()
		ShowSnap(nil)
		ShowBondTarget(nil)
		ShowInspector(nil)
		if A.Braids then A.Braids:ShowEdge(nil) end

		local st = self._stretch
		self._stretch = nil
		if st then
			SavePosition(st.lead)
			SaveDescendants(st.lead.name)
			RefreshJunctions()
			return
		end

		local mover = self._mover or entry
		-- DROPPED ON THE PARKED ROW: hidden. Put back where it was first, so
		-- whatever hangs from it goes back too and it returns there when shown.
		local parked = self._park
		self._park = nil
		if mover.park then
			if parked then
				RestorePosition(mover)
				-- Written down where it stands, so a strand still on its default
				-- comes back here rather than to its parked outline. A bond it
				-- has is kept exactly (carried).
				SavePosition(mover, true)
				mover.park.finish(true)
				return
			end
			mover.park.finish(false)
		end

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

		-- DROPPED ON ANOTHER NODE'S JUNCTION: hang it from that one, where it
		-- lies. SetParent measures the new bond from here and saves it.
		local to = self._bondTo
		self._bondTo = nil
		local braid = self._braid
		self._braid = nil
		if to and to.refused then
			A:Print(A.Bad(to.refused))
		elseif to and Movers:SetParent(mover.name, to.name) then
			A:Print(A.F(L.movers.bond.done, NodeLabel(mover.name), to.label))
		elseif braid and A.Braids:Join(mover.name, braid.host, braid.edge, braid.slot) then
			A:Print(A.F(L.movers.braid.done, NodeLabel(mover.name), braid.label))
		elseif not braid and A.Braids and A.Braids:HostOf(mover.name) then
			-- Dragged more than 8 off every edge: out of the braid, still bonded
			-- to its host where it was dropped.
			local host = A.Braids:HostOf(mover.name)
			if A.Braids:Leave(mover.name) then
				A:Print(A.F(L.movers.braid.left, NodeLabel(mover.name), NodeLabel(host)))
			end
		end

		SavePosition(mover)
		SaveDescendants(mover.name)
		RefreshJunctions()
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
		RefreshJunctions()
	end)
	h:EnableMouseWheel(true)

	entry.handle = h
	DressHandle(entry)
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
--    shape = "pill"        a unit: its unlock outline is a pill, as the unit
--                          is (board 4a). Anything else is a rounded rectangle.
--    braid = true          a strand: it can be braided onto another strand's
--                          edge, and another onto its own (Core/Braids.lua).
--    rows = function(cols, rows)
--                          the node's own inspector rows; cols and rows are a
--                          reshape's preview when one is being dragged.
--    reshape = { shapes = fn, apply = fn(cols, rows) }
--                          a strand with a shape handle. shapes() lists
--                          { cols, rows, w, h } in UIParent units.
--    park = { start = fn, over = fn(mx, my), finish = fn(parked) }
--                          a node that can be hidden by dropping it on a
--                          row of its module's: start when a drag begins,
--                          over says whether the cursor (UIParent units) is
--                          on it, finish(true) hides it.

--- Which node an entry hangs from, from its saved record.
--
--  THE SAVED PARENT WINS over the module's default: a node somebody hung
--  elsewhere - or set free onto the screen - stays where they put it when its
--  module registers it again on the next config change, and a layout string
--  that bonds it elsewhere is obeyed.
local function ResolveParent(entry)
	local saved = A.db.profile.anchors[entry.name]
	local parent = entry.defaultParent
	entry.free = (saved and saved.free) and true or nil
	if entry.free then
		parent = nil
	elseif saved and type(saved.lat) == "table" and saved.lat.parent then
		parent = saved.lat.parent
	end
	-- A parent that hangs from this node would be an anchor loop.
	if parent and Descends(parent, entry.name) then parent = nil end
	entry.parent = parent
end

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
	entry.shape = opts and opts.shape or entry.shape
	entry.braid = opts and opts.braid or nil
	entry.rows = opts and opts.rows or nil
	entry.reshape = opts and opts.reshape or nil
	entry.park = opts and opts.park or nil

	entry.defaultParent = opts and opts.parent or nil
	ResolveParent(entry)

	frame:SetClampedToScreen(true)
	RestorePosition(entry)
	Adopt(name)

	if Movers.unlocked then
		-- Dressed again: a strand that gained or lost buttons gains or loses
		-- its shape handle.
		if entry.handle then DressHandle(entry) else CreateHandle(entry) end
		entry.handle:SetShown(not Movers.only or Movers.only[name] or false)
		DrawBonds()
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
	if Movers.unlocked then DrawBonds() end
	return true
end

--- Where a node sits NOW, as a layout record would put it: its bond to its
--  parent, or its place on the screen. Measured, never saved. For a node with
--  no saved record that a layout still has to describe - a bar nobody has
--  moved carries its shape in the string, so it needs a position there too.
function Movers:Measure(name)
	local entry = Movers.registry[name]
	if not entry or not entry.frame then return nil end
	local pf = ParentFrame(entry)
	if pf then
		local b = MeasureBond(entry, pf)
		if b then return b.parent, b.point, b.relPoint, b.x, b.y end
		return nil
	end
	local point, x, y = ScreenAnchor(entry.frame, entry.growsDown)
	if point then return "screen", point, point, round(x), round(y) end
	return nil
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
	if Movers.unlocked then DrawBonds() end
end

function Movers:Restore(name)
	local entry = Movers.registry[name]
	if entry then RestorePosition(entry) end
end

--- Put a node hung from the screen in the mirror of its place, across the
--  screen's centre line: the trunks swapping sides (decision 4c - they dock
--  left or right, and swap together). Refused in combat or for a node with a
--  parent. Returns true when it moved.
function Movers:Mirror(name)
	local entry = Movers.registry[name]
	if not entry or entry.parent or InCombatLockdown() then return false end
	local saved = A.db.profile.anchors[name]
	local src = (saved and VALID_POINTS[saved.point]) and saved or entry.default
	local function flip(p)
		p = p or "CENTER"
		if p:find("LEFT") then return (p:gsub("LEFT", "RIGHT")) end
		if p:find("RIGHT") then return (p:gsub("RIGHT", "LEFT")) end
		return p
	end
	A.db.profile.anchors[name] = {
		point = flip(src.point), relPoint = flip(src.relPoint or src.point),
		x = -(src.x or 0), y = src.y or 0,
		free = saved and saved.free or nil,
	}
	RestorePosition(entry)
	return true
end

function Movers:RestoreAll()
	for _, entry in pairs(Movers.registry) do RestorePosition(entry) end
end

--- Every registered node takes its parent from the store again.
--
--  BEFORE ANYTHING IS PLACED, when a whole layout has been written. A node
--  still carrying its old parent is re-placed by its old parent's
--  registration - bar 1 coming back puts every child of bar 1 back - and a
--  record bonded to a different parent than the live one reads as an old
--  record and is measured again, against the wrong parent, over the layout's
--  own bond. Seen in the suite, 2026-10-07.
function Movers:ResolveParents()
	for _, entry in pairs(Movers.registry) do ResolveParent(entry) end
end

--- A whole layout has just been written into the store (Core/Layout.lua).
--  Every node takes its parent from its record again - or its module's
--  default where the record has none - and is placed again.
--
--  A record that arrived as a BOND has no screen half yet, and 1.1 reads
--  nothing else; it is measured and written back once its node is placed. A
--  record that arrived on the SCREEN is left exactly as written, so the layout
--  it came from still recognises it.
function Movers:AdoptLayout()
	Movers:ResolveParents()
	Movers:RestoreAll()
	-- THE SCREEN HALF ONLY. The bond is what the layout said, exactly; measuring
	-- it again would hand back a rounding of it.
	local anchors = A.db.profile.anchors
	for name, entry in pairs(Movers.registry) do
		local saved = anchors[name]
		if saved and not saved.point and ParentFrame(entry) then
			local sp, sx, sy = ScreenAnchor(entry.frame, entry.growsDown)
			if sp then
				saved.point, saved.relPoint, saved.x, saved.y = sp, sp, round(sx), round(sy)
			end
		end
	end
	if Movers.unlocked then
		DrawBonds()
		RefreshJunctions()
	end
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
--
-- THE MODE PILL (board 4a): a diamond, "Lattice unlocked", the hint, and a
-- LOCK chip, at the top of the screen. The whole pill locks when pressed.
-- ---------------------------------------------------------------------------

local LOCK_H = 34

local function LockSpot()
	A.db.profile.anchors = A.db.profile.anchors or {}
	return A.db.profile.anchors.__lockButton
end

--- Lay the pill out round its words, which are only measurable once set.
local function LayLockButton(b)
	local c = A.Palette.c
	b:SetFillColor({ c.nodeFill[1], c.nodeFill[2], c.nodeFill[3], 0.85 })
	b:SetEdgeColor({ c.accent[1], c.accent[2], c.accent[3], 0.45 })
	Tint(b.glyph, c.accent, 1)
	A.Widgets.Color(b.label, c.text)
	A.Widgets.Color(b.hint, c.textDim)
	b.chip:SetFillColor(c.btnFill)
	A.Widgets.Color(b.chipText, c.btnFillText)

	local chipW = math.ceil(b.chipText:GetStringWidth() or 0) + 24
	b.chip:SetSize(chipW, LOCK_H - 10)
	local w = 16 + 9 + 10 + (b.label:GetStringWidth() or 0) + 6
		+ (b.hint:GetStringWidth() or 0) + 14 + chipW + 5
	b:SetSize(math.ceil(w), LOCK_H)
end

local function BuildLockButton()
	local b = A.Glass.CreatePanel(UIParent, { frameType = "Button", corner = LOCK_H / 2 })
	b:SetSize(LOCK_H * 8, LOCK_H)
	b:SetFrameStrata("FULLSCREEN_DIALOG")
	b:SetToplevel(true)
	b:EnableMouse(true)
	b:SetMovable(true)
	b:SetClampedToScreen(true)
	b:RegisterForDrag("LeftButton")
	b:Hide()

	b.glyph = b:CreateTexture(nil, "OVERLAY")
	b.glyph:SetTexture(A.Media.texture.diamond)
	b.glyph:SetSize(9, 9)
	b.glyph:SetPoint("LEFT", b, "LEFT", 16, 0)

	b.label = A.Widgets.Text(b, "label", "LEFT")
	b.label:SetPoint("LEFT", b.glyph, "RIGHT", 10, 0)
	b.label:SetText(L.movers.pill.unlocked)

	b.hint = A.Widgets.Text(b, "label", "LEFT")
	b.hint:SetPoint("LEFT", b.label, "RIGHT", 6, 0)
	b.hint:SetText(L.movers.pill.hint)

	b.chip = A.Glass.CreatePanel(b, { corner = (LOCK_H - 10) / 2 })
	b.chip:SetPoint("RIGHT", b, "RIGHT", -5, 0)
	b.chip:EnableMouse(false)
	b.chipText = A.Widgets.Text(b.chip, "label", "CENTER")
	b.chipText:SetPoint("CENTER", b.chip, "CENTER", 0, 0)
	b.chipText:SetText(L.movers.pill.lock)

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
	local scale = A.db.profile.scale or 1
	b:ClearAllPoints()
	if spot then
		b:SetPoint(spot.point, UIParent, spot.relPoint, spot.x, spot.y)
	else
		-- Top centre, 22 down, as the board has it: clear of the frames you
		-- have come to move, which are mostly lower down.
		b:SetPoint("TOP", UIParent, "TOP", 0, -Px(22) / scale)
	end
	b:SetScale(scale)
	LayLockButton(b)
	b:Show()
	b:Raise()
end

Movers.ShowLockButton = ShowLockButton

--- Placement mode. `only`, a set of node names, unlocks just those (the
--  options map's Shift-click: "unlock just this"); nil unlocks everything.
function Movers:Unlock(only)
	Movers.unlocked = true
	Movers.only = only
	ShowGrid(true)
	ShowLockButton(true)
	for name, entry in pairs(Movers.registry) do
		if not only or only[name] then
			-- Preview first: the handle takes its size from the frame, so a frame
			-- that is still collapsed gets a handle nobody can grab.
			if entry.preview then pcall(entry.preview, true) end
			if not entry.handle then CreateHandle(entry) end
			DressHandle(entry)
			entry.handle:Show()
		elseif entry.handle then
			entry.handle:Hide()
		end
	end
	-- After the previews, so a bond is drawn to a frame that is up.
	DrawBonds()
	RefreshJunctions()
	Announce()
	A:Print(A.F(L.movers.unlock.frames_unlocked_drag_move,
		A.Hi(L.movers.pill.lock), A.Hi("/lattice lock")))
	A:Print(A.Dim("A child snaps to its parent's centre lines first, then to other frames"
		.. " and the field's dots; hold Shift while dragging to place freely. Drop a node"
		.. " on another's junction to hang it from that one. Frames that only appear"
		.. " when the game says so - the pet bar, the taxi button - are held up so you"
		.. " can place them."))
end

function Movers:Lock()
	Movers.unlocked = false
	Movers.only = nil
	ShowGrid(false)
	ClearGuides()
	HideBonds()
	ShowSnap(nil)
	ShowBondTarget(nil)
	ShowGhost(nil)
	ShowInspector(nil)
	if A.Braids then A.Braids:ShowEdge(nil) end
	ShowLockButton(false)
	for _, entry in pairs(Movers.registry) do
		if entry.handle then entry.handle:Hide() end
		if entry.preview then pcall(entry.preview, false) end
	end
	Announce()
	A:Print(L.movers.lock.frames_locked)
end

--- Re-lay the field after a settings change, so turning it off is visible
--  without locking and unlocking again.
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
	-- Braids went with the records: every strand back to its own size and dock.
	if A.Braids then A.Braids:Relayout() end
	if Movers.unlocked then DrawBonds() end
	A:Print(L.movers.reset_all.frame_positions_reset)
end
