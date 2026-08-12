--[[--------------------------------------------------------------------------
	AetherUI :: Movers

	Drag-to-place for any registered frame, with the position persisted per
	profile under db.profile.anchors[name].

	Why a separate overlay rather than making the frame itself draggable:
	the real frames will eventually include secure action buttons, which cannot
	be moved in combat and should not be given mouse scripts at all. A dumb
	overlay that repositions its target sidesteps that whole class of problem.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Movers = {}
A.Movers = Movers

Movers.registry = {}
Movers.unlocked = false

local VALID_POINTS = {
	TOPLEFT = true, TOP = true, TOPRIGHT = true,
	LEFT = true, CENTER = true, RIGHT = true,
	BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- ---------------------------------------------------------------------------

local function SavePosition(entry)
	local f = entry.frame
	local point, _, relPoint, x, y = f:GetPoint(1)
	if not point then return end
	A.db.profile.anchors[entry.name] = {
		point = point, relPoint = relPoint,
		x = math.floor(x + 0.5), y = math.floor(y + 0.5),
	}

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

local function RestorePosition(entry)
	local saved = A.db.profile.anchors[entry.name]
	local d = entry.default
	local point, relPoint, x, y

	if saved and VALID_POINTS[saved.point] and VALID_POINTS[saved.relPoint] then
		point, relPoint, x, y = saved.point, saved.relPoint, saved.x, saved.y
	else
		point, relPoint, x, y = d.point, d.relPoint or d.point, d.x, d.y
	end

	if InCombatLockdown() then
		-- Re-anchoring a frame with secure descendants is protected. Defer.
		Movers._pending = Movers._pending or {}
		Movers._pending[entry.name] = true
		return
	end

	entry.frame:ClearAllPoints()
	entry.frame:SetPoint(point, UIParent, relPoint, x, y)
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
--  SetVertexColor. Kept in one place because it is called from four.
local function Tint(t, c, alpha)
	t:SetVertexColor(c[1], c[2], c[3], alpha)
end

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

--- Candidate lines to snap to, in UIParent units: the screen's own edges and
--  centre, and every other registered frame's edges and centre.
local function SnapTargets(exclude)
	local xs, ys = {}, {}
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()

	xs[#xs + 1] = 0 ; xs[#xs + 1] = w / 2 ; xs[#xs + 1] = w
	ys[#ys + 1] = 0 ; ys[#ys + 1] = h / 2 ; ys[#ys + 1] = h

	for _, entry in pairs(Movers.registry) do
		local f = entry.frame
		if f ~= exclude and f:IsShown() and f:GetLeft() then
			local s = f:GetEffectiveScale() / (UIParent:GetEffectiveScale() or 1)
			local l, r = f:GetLeft() * s, f:GetRight() * s
			local b, t = f:GetBottom() * s, f:GetTop() * s
			xs[#xs + 1] = l ; xs[#xs + 1] = r ; xs[#xs + 1] = (l + r) / 2
			ys[#ys + 1] = b ; ys[#ys + 1] = t ; ys[#ys + 1] = (b + t) / 2
		end
	end
	return xs, ys
end

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

		local f = entry.frame
		local fs = f:GetEffectiveScale() or 1
		local us = UIParent:GetEffectiveScale() or 1
		if fs <= 0 or us <= 0 then return end

		local mx, my = GetCursorPosition()
		mx, my = mx / us, my / us

		local x = self._origX + (mx - self._grabX)
		local y = self._origY + (my - self._grabY)

		local cfg = GridConfig()
		local w, h2 = f:GetWidth() * fs / us, f:GetHeight() * fs / us
		local gx, gy

		-- Alt is the escape hatch: sometimes the place you want is a pixel off
		-- the line, and fighting a snap you cannot switch off is miserable.
		if cfg.snap ~= false and not IsAltKeyDown() then
			local xs, ys = SnapTargets(f)
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
			A:Print("|cffff8a8acan't move frames in combat.|r")
			return
		end
		local f = entry.frame
		local fs = f:GetEffectiveScale() or 1
		local us = UIParent:GetEffectiveScale() or 1
		if fs <= 0 or us <= 0 or not f:GetLeft() then return end

		local mx, my = GetCursorPosition()
		self._grabX, self._grabY = mx / us, my / us
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

		-- Re-express the position relative to whichever screen corner the frame
		-- ended up nearest. Anchoring a bottom-centre HUD element by TOPLEFT
		-- makes it drift the moment the resolution changes.
		--
		-- Every measurement below has to cross a scale boundary, and getting that
		-- wrong is what made frames leap to a corner the moment you let go of
		-- them. GetLeft/GetTop/GetCenter report in the FRAME's own coordinate
		-- space, UIParent:GetWidth() reports in UIParent's, and SetPoint's
		-- offsets are read back in the frame's space again. Our frames run at
		-- profile.scale (0.71 by default), so mixing the two overshot by ~40%,
		-- and SetClampedToScreen then pinned the wreckage to an edge.
		local f = entry.frame
		local fs = f:GetEffectiveScale() or 1
		local us = UIParent:GetEffectiveScale() or 1
		if fs <= 0 or us <= 0 then return end

		local function toUI(v) return v * fs / us end     -- frame space -> UIParent
		local function toFrame(v) return v * us / fs end  -- and back again

		local cx, cy = f:GetCenter()
		if not cx then return end
		cx, cy = toUI(cx), toUI(cy)

		local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
		local hx = cx < sw / 3 and "LEFT" or cx > sw * 2 / 3 and "RIGHT" or ""
		local vy = cy < sh / 3 and "BOTTOM" or cy > sh * 2 / 3 and "TOP" or ""

		-- A frame that grows downward has to be pinned by its top edge, or every
		-- row it gains shoves the whole thing upward off its own anchor.
		if entry.growsDown then vy = "TOP" end

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

		f:ClearAllPoints()
		f:SetPoint(point, UIParent, point, toFrame(x), toFrame(y))
		SavePosition(entry)
	end)

	-- Nudge with the arrow keys for the last few pixels.
	h:EnableKeyboard(false)
	h:SetScript("OnMouseWheel", function(_, delta)
		local point, _, relPoint, x, y = entry.frame:GetPoint(1)
		if not point then return end
		if IsShiftKeyDown() then x = x + delta else y = y + delta end
		entry.frame:ClearAllPoints()
		entry.frame:SetPoint(point, UIParent, relPoint, x, y)
		SavePosition(entry)
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

	frame:SetClampedToScreen(true)
	RestorePosition(entry)

	if Movers.unlocked then
		if not entry.handle then CreateHandle(entry) end
		entry.handle:Show()
	end
	return entry
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

function Movers:Unlock()
	Movers.unlocked = true
	ShowGrid(true)
	for _, entry in pairs(Movers.registry) do
		-- Preview first: the handle takes its size from the frame, so a frame
		-- that is still collapsed gets a handle nobody can grab.
		if entry.preview then pcall(entry.preview, true) end
		if not entry.handle then CreateHandle(entry) end
		entry.handle:Show()
	end
	A:Print("frames unlocked - drag to move, scroll to nudge (hold shift for horizontal). |cff9d7bff/aether lock|r when done.")
	A:Print("|cff888888Edges snap to the grid and to other frames; hold alt while dragging"
		.. " to place freely. Frames that only appear when the game says so - the pet"
		.. " bar, the taxi button - are held up so you can place them.|r")
end

function Movers:Lock()
	Movers.unlocked = false
	ShowGrid(false)
	ClearGuides()
	for _, entry in pairs(Movers.registry) do
		if entry.handle then entry.handle:Hide() end
		if entry.preview then pcall(entry.preview, false) end
	end
	A:Print("frames locked.")
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
	Movers:RestoreAll()
	A:Print("frame positions reset.")
end
