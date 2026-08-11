--[[--------------------------------------------------------------------------
	AetherUI :: Minimap

	A round map with a frosted rim, an "N" above it, and a glass pill under it
	carrying the zone, your coordinates and the time. In a fight the pill's
	contents swap for a red dot and "In combat". Mail, when you have some, gets
	a small pill of its own beside the block.

	Everything else Blizzard hangs off the minimap - zoom, tracking, the
	day/night dial, the battleground eye, the border art, the toggle tab - is
	banished. Zoom is on the wheel and tracking is on right-click, so the two
	that were actually load-bearing survive without any chrome to show for it.

	Blizzard's Minimap cannot be rebuilt
	------------------------------------
	`Minimap` is a special widget type the client draws into; you cannot make
	another one. So this module *reshapes the real thing* - reparents it, sizes
	it, masks it round, and draws its own rim around it. Everything else here is
	ours and ordinary.

	The button drawer
	-----------------
	Third-party addons park buttons on the minimap ring, and enough of them turn
	the map into a dartboard. They are collected into a drawer that slides out of
	the zone pill on hover and is otherwise not on screen at all.

	Finding them is three passes, in this order, because they overlap:

	  1. LibDBIcon-1.0's own registry, if any addon on the machine has loaded a
	     copy. This is the reliable one - the library knows exactly what it made.
	  2. `Minimap:GetChildren()`, filtered. That catches the addons that roll
	     their own button.
	  3. Both again, a few times over the first fifteen seconds, because there is
	     no event for "a child was added to the minimap" and addons create their
	     buttons whenever they happen to finish loading.

	The filter leans on `issecurevariable`: Blizzard's own globals are secure and
	an addon's are not, which sorts the furniture from the arrivals without a
	hardcoded list to keep up to date. Map *pins* are the other thing living on
	the minimap - Questie and friends can put thousands there - so names ending
	in a digit are rejected, and the usual pin-heavy addons are excluded by
	prefix. `Minimap:GetChildren()` itself is wrapped in a pcall for the same
	reason: with a pin addon running, that vararg is enormous.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local MM = A:NewModule("minimap")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- Widget methods captured unbound, so a collected button that has stomped its
-- own `SetPoint` (some do, to keep themselves welded to the ring) can still be
-- placed. Called as plain functions with the frame as the first argument.
local RawSetParent, RawClearAllPoints, RawSetPoint, RawSetSize, RawGetName
do
	local probe = CreateFrame("Frame")
	RawSetParent      = probe.SetParent
	RawClearAllPoints = probe.ClearAllPoints
	RawSetPoint       = probe.SetPoint
	RawSetSize        = probe.SetSize
	RawGetName        = probe.GetName
end

-- ---------------------------------------------------------------------------
-- Blizzard's furniture
-- ---------------------------------------------------------------------------

-- Confirmed present on Classic Era 1.15. Deliberately *not* here:
-- MiniMapWorldMapButton (Wrath+ only), MiniMapInstanceDifficulty (Wrath+),
-- QueueStatusMinimapButton / GarrisonLandingPageMinimapButton (Retail), and
-- the whole MinimapCluster.* sub-object tree Retail moved everything into.
--
-- This list is the *named* half of the job and no longer the whole of it. The
-- first pass hid these and nothing else, and left the top border bar, the
-- toggle tab and a couple of unnamed textures sitting above the map - because
-- some of that art is an anonymous region of MinimapCluster with no global to
-- put in a list. SweepCluster below is what actually finishes it.
MM.blizzardFrames = {
	"MinimapBorder", "MinimapBorderTop", "MinimapNorthTag",
	"MinimapZoomIn", "MinimapZoomOut", "MinimapToggleButton",
	"MinimapZoneTextButton", "MiniMapTracking", "MiniMapBattlefieldFrame",
	"GameTimeFrame", "MinimapCompassTexture", "MiniMapMailFrame",
}

local hider
local function GetHider()
	if not hider then
		hider = CreateFrame("Frame", ADDON .. "MinimapHider", UIParent)
		hider:Hide()
	end
	return hider
end

local function Forbidden(f)
	if not f or not f.IsForbidden then return false end
	local ok, forbidden = pcall(f.IsForbidden, f)
	return (not ok) or forbidden
end

--- Take one piece of furniture off screen for good.
--
--  Reparenting to a hidden frame rather than only calling Hide: another addon
--  calling Show() on it would otherwise put it straight back, and several do.
--  Textures have no SetParent, so those are hidden and their alpha zeroed - a
--  texture nobody re-shows stays gone.
local function BanishObject(f, key, report)
	if not f or Forbidden(f) then
		if report and key then report[key] = f and "forbidden" or "absent" end
		return
	end
	if InCombatLockdown() then
		if report and key then report[key] = "deferred (combat)" end
		return
	end

	-- One pcall per call. Bundling them means a throw on the first silently
	-- skips the rest, which is how the action bar sweep once hid nothing.
	if f.UnregisterAllEvents then pcall(f.UnregisterAllEvents, f) end
	if f.Hide then pcall(f.Hide, f) end
	if f.SetAlpha then pcall(f.SetAlpha, f, 0) end
	if f.SetParent then pcall(f.SetParent, f, GetHider()) end

	if report and key then
		report[key] = (f.IsShown and f:IsShown()) and "STILL SHOWN" or "hidden"
	end
end

local function Banish(name, report)
	BanishObject(_G[name], name, report)
end

--- Everything on the cluster that is Blizzard's, named or not.
--
--  Two passes, and both are needed:
--
--  * Regions. `MinimapBorderTop` and its neighbours are textures, and some of
--    the art up there has no global name at all - there is nothing to put in a
--    list, so the list can never be finished. Hiding every region of the
--    cluster and its backdrop is the only way to be sure.
--  * Child frames, filtered by `issecurevariable`. Blizzard declares its
--    globals securely and an addon cannot, so this catches the zone-text
--    button, the toggle tab and anything Blizzard adds later, while leaving an
--    addon's button exactly where it is. Same trick the button collector uses,
--    pointed the other way.
--
--  `Minimap` itself is excluded by identity, because at the point this runs it
--  is still a child of the cluster.
local function SweepCluster(root, report, keep, depth)
	if not root or Forbidden(root) or (depth or 0) > 2 then return end

	if root.GetRegions then
		local regions = { pcall(root.GetRegions, root) }
		if regions[1] then
			for i = 2, #regions do
				local r = regions[i]
				if r and not keep[r] and r.Hide then
					pcall(r.Hide, r)
					if r.SetAlpha then pcall(r.SetAlpha, r, 0) end
				end
			end
		end
	end

	if not root.GetChildren then return end
	local kids = { pcall(root.GetChildren, root) }
	if not kids[1] then return end

	for i = 2, #kids do
		local child = kids[i]
		if child and not keep[child] and not Forbidden(child) then
			local ok, name = pcall(child.GetName, child)
			local mine = ok and name and issecurevariable and issecurevariable(name)
			if mine then
				-- The backdrop is the parent of the zoom, tracking and day/night
				-- buttons. Recurse rather than banish, so a third-party button
				-- that happens to be parented there is not carried off with it.
				if name == "MinimapBackdrop" then
					SweepCluster(child, report, keep, (depth or 0) + 1)
					if report then report[name] = "swept" end
				else
					BanishObject(child, name, report)
				end
			end
		end
	end
end

function MM:HideBlizzard()
	local cfg = A.Config:Module("minimap")
	if cfg.hideBlizzard == false then return end

	self.hideReport = self.hideReport or {}
	for _, name in ipairs(MM.blizzardFrames) do
		Banish(name, self.hideReport)
	end

	-- Then everything the list could not name.
	local keep = { [_G.Minimap] = true }
	SweepCluster(_G.MinimapCluster, self.hideReport, keep, 0)
	SweepCluster(_G.MinimapBackdrop, self.hideReport, keep, 1)

	-- The cluster is a mouse-enabled rectangle considerably larger than the map,
	-- and it swallows clicks meant for whatever is behind it. It stays *on
	-- screen* though, empty: other addons anchor to it, and moving it would take
	-- their frames with it.
	if _G.MinimapCluster and not InCombatLockdown() then
		pcall(_G.MinimapCluster.EnableMouse, _G.MinimapCluster, false)
	end
end

-- ---------------------------------------------------------------------------
-- collected buttons
-- ---------------------------------------------------------------------------

-- Names that are map *pins*, not buttons. A pin addon can put thousands of
-- children on the minimap; letting one into the drawer is the least of it.
local PIN_PREFIX = {
	"^HandyNotes", "^TomTom", "^HereBeDragons", "^Questie", "^GatherMate",
	"^Routes", "^pin", "^Pin", "^Nx",
}

-- What an addon button tends to be called. Anything matching none of these is
-- assumed not to be one, which errs toward leaving things where they are.
local BUTTON_PATTERN = {
	"^LibDBIcon10_", "MinimapButton", "MinimapFrame", "MinimapIcon",
	"[%-_]Minimap[%-_]", "Minimap$", "^BT4",
}

local function Matches(name, list)
	for _, pat in ipairs(list) do
		if name:find(pat) then return true end
	end
	return false
end

--- Is this child of the minimap something we should collect?
local function IsAddonButton(frame, own)
	if type(frame) ~= "table" then return false end
	if own[frame] then return false end
	if not frame.IsObjectType or not frame:IsObjectType("Frame") then return false end
	if Forbidden(frame) then return false end

	local ok, name = pcall(RawGetName, frame)
	if not ok or not name or name == "" then return false end

	-- Blizzard declares its globals securely and addons cannot, so this sorts
	-- the furniture from the arrivals without a list to keep up to date.
	if issecurevariable then
		local secure = select(1, issecurevariable(name))
		if secure then return false end
	end

	if Matches(name, PIN_PREFIX) then return false end
	-- Pins are numbered; buttons are not. A name ending in a digit is almost
	-- always the ninetieth copy of something.
	if name:find("%d$") and not name:find("^LibDBIcon10_") then return false end
	if not Matches(name, BUTTON_PATTERN) then return false end

	return true
end

--- Stop a button putting itself back on the ring.
--
--  LibDBIcon's drag handlers recompute an angle from the cursor and re-anchor to
--  the minimap's centre every frame while held, and its own Show/Refresh do the
--  same on demand. `Lock` is the library's supported way to switch that off and
--  it survives a refresh, so use it when the library is there.
--- Let go of a strata and level the button is holding onto.
--
--  LibDBIcon pins both - `SetFixedFrameStrata(true)` and `SetFixedFrameLevel(true)`
--  - so that reparenting cannot shuffle its buttons around behind things. Good
--  hygiene for a library, and it means our own SetFrameStrata is quietly refused:
--  the button stays at MEDIUM while the drawer sits at DIALOG, so the drawer's
--  own panel art is painted over the top of it and the click never lands.
--
--  This is exactly what the diagnostics showed - a hand-rolled button took the
--  level we gave it and worked; the two LibDBIcon ones kept their own and did
--  not. Unpin first, then set.
local function Unpin(f)
	if f.SetFixedFrameStrata then pcall(f.SetFixedFrameStrata, f, false) end
	if f.SetFixedFrameLevel then pcall(f.SetFixedFrameLevel, f, false) end
end

local function Pacify(button, name)
	local ldbi = LibStub and LibStub("LibDBIcon-1.0", true)
	if ldbi and name and ldbi.IsRegistered and ldbi:IsRegistered(name) then
		pcall(ldbi.Lock, ldbi, name)
	end
	if button.SetScript then
		pcall(button.SetScript, button, "OnDragStart", nil)
		pcall(button.SetScript, button, "OnDragStop", nil)
	end
end

-- What a third-party button hangs off itself, none of which is ours to keep:
-- a bevelled ring, a tracking-border, a plate behind the icon. LibDBIcon names
-- its three parts, so those are exact; anything else is matched on the texture
-- path, because a *name* is what the addon chose to call it and a path is what
-- it actually drew.
local FURNITURE = {
	"MiniMap%-TrackingBorder", "MinimapButtonBorder", "MiniMapButtonBorder",
	"UI%-Minimap%-Border", "MinimapBorder", "Button%-Border",
}

--- Make somebody else's button look like it belongs here: the icon masked to a
--  circle with our ring around it, and everything else it arrived with off.
--
--  The first version matched the bevel by texture path against a list of the
--  usual suspects. That was too clever by half: an addon's border is whatever
--  file that addon happened to ship, and there is no list that covers "whatever
--  file that addon happened to ship". So the rule is inverted - **find the icon
--  and hide every other texture** - which needs no list and cannot go stale.
--
--  Finding the icon, in order of how much the answer can be trusted:
--    1. `b.icon`, which LibDBIcon sets by name and most hand-rolled buttons copy
--    2. a region named <button>Icon, the old FrameXML convention
--    3. the largest ARTWORK texture, which is what an icon almost always is
--
--  Light touch throughout, because these frames belong to other addons: regions
--  are hidden and their texture cleared, never removed, and nothing is renamed
--  or reparented beyond the one move into the drawer.
local function FindIcon(b, regions)
	if type(b.icon) == "table" and b.icon.SetTexCoord then return b.icon end

	local ok, name = pcall(RawGetName, b)
	if ok and name and _G[name .. "Icon"] then
		local r = _G[name .. "Icon"]
		if type(r) == "table" and r.SetTexCoord then return r end
	end

	local best, bestArea
	for _, r in ipairs(regions) do
		if r.GetObjectType and r:GetObjectType() == "Texture" then
			local okt, tex = pcall(r.GetTexture, r)
			local area = (r.GetWidth and (r:GetWidth() or 0) * (r:GetHeight() or 0)) or 0
			-- A texture with nothing in it is not the icon.
			if okt and tex and (not bestArea or area > bestArea) then
				best, bestArea = r, area
			end
		end
	end
	return best
end

local function SkinButton(b)
	if b.__aetherSkinned then return end

	local got = { pcall(b.GetRegions, b) }
	if not got[1] then return end
	local regions = {}
	for i = 2, #got do regions[#regions + 1] = got[i] end

	local icon = FindIcon(b, regions)
	b.__aetherSkinned = true
	b.__aetherHidden = 0

	for _, r in ipairs(regions) do
		if r ~= icon and r.GetObjectType and r:GetObjectType() == "Texture" then
			pcall(r.SetTexture, r, nil)
			pcall(r.SetAlpha, r, 0)
			pcall(r.Hide, r)
			b.__aetherHidden = b.__aetherHidden + 1
		end
	end

	if icon then
		-- Trim the icon's own baked border before masking, the way every icon in
		-- this UI is trimmed, or the circle cuts through somebody's frame art.
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "TOPLEFT", b, "TOPLEFT", 2, -2)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
		pcall(icon.SetDrawLayer, icon, "ARTWORK")
		pcall(W.AddMask, icon, b, Media.texture.circleMask, b)
		b.__aetherIcon = icon
	end

	if not b.__aetherRing then
		local ok, ring = pcall(b.CreateTexture, b, nil, "OVERLAY")
		if ok and ring then
			ring:SetTexture(Media.texture.ring)
			ring:SetAllPoints(b)
			local c = Palette.c.glassEdge
			ring:SetVertexColor(c[1], c[2], c[3], 0.9)
			b.__aetherRing = ring
		end
	end
end

function MM:Collect(button, ldbiName)
	if not button or self.buttons[button] then return end
	if InCombatLockdown() then
		self._collectPending = true
		return
	end

	local ok, name = pcall(RawGetName, button)
	if not ok then return end

	Pacify(button, ldbiName)

	self.buttons[button] = name or true
	self.buttonOrder[#self.buttonOrder + 1] = button

	if A.Config:Module("minimap").skinButtons ~= false then
		pcall(SkinButton, button)
	end

	pcall(RawSetParent, button, self.drawer.tray)
	Unpin(button)
	if button.SetFrameStrata then pcall(button.SetFrameStrata, button, "DIALOG") end
	if button.SetIgnoreParentScale then
		pcall(button.SetIgnoreParentScale, button, false)
	end

	-- Its own Show/Hide, hooked rather than scripted: an OnShow script also
	-- fires when the *parent's* visibility changes, which would relayout the
	-- drawer every time it opened.
	if not button.__aetherHooked and hooksecurefunc then
		button.__aetherHooked = true
		pcall(hooksecurefunc, button, "Show", function() MM:LayoutDrawer() end)
		pcall(hooksecurefunc, button, "Hide", function() MM:LayoutDrawer() end)
	end

	self:LayoutDrawer()
	return true
end

--- One sweep: the LibDBIcon registry, then the minimap's own children.
function MM:Scan()
	if not self.drawer then return 0 end
	local cfg = A.Config:Module("minimap")
	if cfg.drawer == false then return 0 end

	local found = 0

	local ldbi = LibStub and LibStub("LibDBIcon-1.0", true)
	if ldbi and ldbi.GetButtonList then
		local okList, list = pcall(ldbi.GetButtonList, ldbi)
		for _, name in ipairs(okList and list or {}) do
			local b = ldbi:GetMinimapButton(name)
			if b and self:Collect(b, name) then found = found + 1 end
		end
	end

	-- With a pin addon running this vararg is enormous, and expanding it into a
	-- table has been known to throw outright. Nobody's day should end here.
	local own = { [self.frame] = true, [self.pill] = true, [self.drawer] = true }
	local results = { pcall(_G.Minimap.GetChildren, _G.Minimap) }
	if results[1] then
		for i = 2, #results do
			local child = results[i]
			if IsAddonButton(child, own) and self:Collect(child) then
				found = found + 1
			end
		end
	else
		self.scanError = results[2]
	end

	return found
end

--- Sweep repeatedly for a while after login.
--
--  There is no event for "a child was added to the minimap" - this was checked
--  against three addons that all solve it the same way - and an addon creates
--  its button whenever it happens to finish loading. So: sweep now, sweep again
--  on a timer for fifteen seconds, and subscribe to LibDBIcon's own creation
--  callback forever after.
function MM:StartScanning()
	self:Scan()
	if not C_Timer or not C_Timer.NewTicker then return end
	if self._ticker then return end
	local left = 7
	self._ticker = C_Timer.NewTicker(2, function()
		MM:Scan()
		left = left - 1
		if left <= 0 and MM._ticker then
			MM._ticker:Cancel()
			MM._ticker = nil
		end
	end, 7)
end

-- ---------------------------------------------------------------------------
-- the drawer
-- ---------------------------------------------------------------------------

local function VisibleButtons(self)
	local out = {}
	for _, b in ipairs(self.buttonOrder) do
		if b:IsShown() then out[#out + 1] = b end
	end
	table.sort(out, function(x, y)
		return (x:GetName() or "") < (y:GetName() or "")
	end)
	return out
end

function MM:LayoutDrawer()
	if not self.drawer then return end
	local cfg = A.Config:Module("minimap")
	local size = cfg.buttonSize or 24
	local gap  = cfg.buttonSpacing or 6
	local pad  = 8

	local list = VisibleButtons(self)
	self.drawer.count = #list

	if #list == 0 then
		self.drawer:SetSize(1, 1)
		self:SetDrawerOpen(false, true)
		self:UpdateHint()
		return
	end

	local cols = math.max(1, math.min(cfg.drawerColumns or 6, #list))
	local rows = math.ceil(#list / cols)

	-- Above the drawer's *own* panel art, not merely above the tray. These
	-- arrive owning a frame level - LibDBIcon pins every button it makes at 8 -
	-- and one sitting under the panel is drawn over and cannot be clicked.
	local level = math.max(self.drawer:GetFrameLevel() or 0,
		self.drawer.tray:GetFrameLevel() or 0) + 5
	for i, b in ipairs(list) do
		local r, c = math.ceil(i / cols), (i - 1) % cols

		-- Re-applied on every layout, not just on collection: a button whose
		-- addon puts its strata back is a button that stops working, and this is
		-- the cheapest place to notice.
		Unpin(b)
		pcall(b.SetFrameStrata, b, self.drawer:GetFrameStrata())

		-- Level as well as strata. These arrive owning their own frame level -
		-- LibDBIcon pins every button it makes at 8 - and a button sitting below
		-- the drawer's own panel art is drawn over and cannot be clicked, which
		-- looks from the outside like the buttons piling up on each other.
		pcall(b.SetFrameLevel, b, level)
		pcall(b.SetScale, b, 1)

		-- Clear first and *check it took*. A button whose ClearAllPoints was
		-- refused keeps its old anchor, and adding a second one on top of it is
		-- what actually stacks them - so skip it rather than pile it up.
		local cleared = pcall(RawClearAllPoints, b)
		if cleared then
			pcall(RawSetSize, b, size, size)
			pcall(RawSetPoint, b, "TOPLEFT", self.drawer.tray, "TOPLEFT",
				c * (size + gap), -(r - 1) * (size + gap))
		end
	end

	self.drawer:SetSize(
		pad * 2 + cols * size + (cols - 1) * gap,
		pad * 2 + rows * size + (rows - 1) * gap)
	self.drawer.tray:SetSize(
		cols * size + (cols - 1) * gap,
		rows * size + (rows - 1) * gap)
	self:UpdateHint()
end

--- Open or close the drawer.
--
--  By alpha and mouse, never Show/Hide. A collected button belongs to somebody
--  else and may well carry a secure template; hiding a frame with a protected
--  descendant is refused in combat, and hovering a pill is exactly the sort of
--  thing you do mid-fight. Alpha and EnableMouse are not protected.
--- Show the chevron only when there is something behind it, and turn it over
--  while that thing is open.
function MM:UpdateHint()
	local h = self.pill and self.pill.hint
	if not h then return end
	local n = (self.drawer and self.drawer.count) or 0
	if n == 0 then h:Hide() return end
	h:Show()
	if self.drawer.open then
		h:SetTexCoord(0, 1, 1, 0)     -- pointing up: you are looking at it
		h:SetAlpha(0.7)
	else
		h:SetTexCoord(0, 1, 0, 1)
		h:SetAlpha(0.35)
	end
end

function MM:SetDrawerOpen(open, instant)
	local d = self.drawer
	if not d then return end
	if open and (d.count or 0) == 0 then open = false end

	d.open = open and true or false
	d:EnableMouse(d.open)
	self:UpdateHint()
	if instant then
		d:SetAlpha(d.open and 1 or 0)
		d._alpha = nil
		return
	end
	d._alpha = d.open and 1 or 0
end

local function DrawerFade(d, elapsed)
	if not d._alpha then return end
	local a = d:GetAlpha()
	local step = elapsed / 0.15
	if a < d._alpha then
		a = math.min(d._alpha, a + step)
	else
		a = math.max(d._alpha, a - step)
	end
	d:SetAlpha(a)
	if math.abs(a - d._alpha) < 0.01 then d._alpha = nil end
end

--- Hover tracking across two frames that are not touching.
--
--  The drawer slides out of the pill, so the cursor has to travel from one to
--  the other and there is a gap between them. Closing on the pill's OnLeave
--  alone would shut it before you arrived; a short grace period, re-checked
--  against both frames, is what makes it reachable.
function MM:TouchDrawer()
	self._hoverUntil = GetTime() + 0.4
	self:SetDrawerOpen(true)
end

function MM:CheckHover()
	if not self.drawer or not self.drawer.open then return end
	if (self.pill and self.pill:IsMouseOver())
		or (self.drawer and self.drawer:IsMouseOver()) then
		self._hoverUntil = GetTime() + 0.4
		return
	end
	if GetTime() > (self._hoverUntil or 0) then self:SetDrawerOpen(false) end
end

-- ---------------------------------------------------------------------------
-- readouts
-- ---------------------------------------------------------------------------

-- Blizzard's own colours for zone type, so a contested zone reads the same
-- amber here as it does everywhere else in the game.
local PVP_COLOR = {
	sanctuary = { 0.41, 0.80, 0.94 },
	arena     = { 1.00, 0.10, 0.10 },
	friendly  = { 0.10, 1.00, 0.10 },
	hostile   = { 1.00, 0.10, 0.10 },
	contested = { 1.00, 0.70, 0.00 },
	combat    = { 1.00, 0.10, 0.10 },
}

local function ZonePVPColor()
	local fn = (C_PvP and C_PvP.GetZonePVPInfo) or _G.GetZonePVPInfo
	if not fn then return nil end
	local ok, pvpType = pcall(fn)
	if not ok then return nil end
	return PVP_COLOR[pvpType or ""]
end

--- Player position as two whole numbers, or nil.
--
--  Two separate ways to get nothing: no map for the unit at all, and a map that
--  exists but reports no position - which is what an instance does. Either way
--  the answer is "no coordinates", and the caller backs off rather than asking
--  ten times a second for the length of a raid.
local function Coords()
	if not C_Map or not C_Map.GetBestMapForUnit then return nil end
	local ok, uiMap = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok or not uiMap then return nil end
	local ok2, pos = pcall(C_Map.GetPlayerMapPosition, uiMap, "player")
	if not ok2 or not pos or not pos.x then return nil end
	return math.floor(pos.x * 100 + 0.5), math.floor(pos.y * 100 + 0.5)
end

-- The two fields that change while you are looking at them: coordinates walk a
-- digit at a time as you move, and the clock ticks over every minute. Measured
-- to their content, either one nudges the whole pill sideways.
--
-- So they get fixed widths - and those widths are *measured*, not guessed. The
-- first pass picked 56 and 38 by eye, which was half again too wide and pushed
-- the block off the side of the screen. Asking the font how wide its own widest
-- content is costs one call at build time and cannot be wrong.
local COORD_SAMPLE = "100 \194\183 100"
local CLOCK_SAMPLE = "00:00"

local function FieldWidth(fs, sample)
	local prev = fs:GetText()
	fs:SetWidth(0)
	fs:SetText(sample)
	local w = math.ceil((fs:GetStringWidth() or 0) + 2)
	fs:SetText(prev or "")
	fs:SetWidth(w)
	return w
end

local function ClockText()
	return date("%H:%M")
end

function MM:UpdateZone()
	if not self.pill then return end
	local cfg = A.Config:Module("minimap")
	local c = Palette.c

	if InCombatLockdown() then
		self.pill.dot:Show()
		-- The dot and the label were both anchored 14 in from the left edge, so
		-- the dot sat on top of the first word - "In combat" rendered as a red
		-- blob and the word "combat". Move the label out of its way.
		self.pill.zone:ClearAllPoints()
		self.pill.zone:SetPoint("LEFT", self.pill.dot, "RIGHT", 6, 0)
		self.pill.zone:SetText("In combat")
		W.Color(self.pill.zone, c.danger)
		self.pill.coords:SetText("")
	else
		self.pill.dot:Hide()
		self.pill.zone:ClearAllPoints()
		self.pill.zone:SetPoint("LEFT", self.pill, "LEFT", 14, 0)
		local zone = (GetMinimapZoneText and GetMinimapZoneText()) or ""
		self.pill.zone:SetText(cfg.showZone == false and "" or zone)
		W.Color(self.pill.zone, ZonePVPColor() or c.text)

		if cfg.showCoords == false then
			self.pill.coords:SetText("")
		else
			local x, y = Coords()
			self.pill.coords:SetText(x and ("%d · %d"):format(x, y) or "")
		end
	end

	self.pill.clock:SetText(cfg.showClock == false and "" or ClockText())

	-- A fixed-width field with nothing in it still takes up its width in the
	-- anchor chain, and the chain runs zone -> coords -> clock. In combat the
	-- coordinates are blank, so the clock was being pushed a whole empty field
	-- to the right - past the end of a pill sized as though the field were not
	-- there. Collapse it, and close the gap it was holding open.
	local hasCoords = (self.pill.coords:GetText() or "") ~= ""
	self.pill.coords:SetWidth(hasCoords and (self.pill.coordW or 0) or 0)
	self.pill.clock:ClearAllPoints()
	self.pill.clock:SetPoint("LEFT", self.pill.coords, "RIGHT", hasCoords and 10 or 0, 0)

	self:SizePill()
end

--- The pill is exactly as wide as what is in it. A fixed width would leave
--  "Camp Taurajo" and "The Barrens" sitting in differently-sized holes.
function MM:SizePill()
	local p = self.pill
	if not p then return end
	local pad, gap = 14, 10

	local w = pad
	if p.dot:IsShown() then w = w + 8 + 6 end

	-- The zone name is measured, because it only changes when you walk into a
	-- different place - and when it does, the pill resizing is the point. The
	-- coordinates and the clock take their fixed widths instead: those change
	-- while you are standing still looking at them.
	local t = p.zone:GetText()
	if t and t ~= "" then w = w + math.ceil(p.zone:GetStringWidth() or 0) + gap end
	if (p.coords:GetText() or "") ~= "" then w = w + (p.coordW or 0) + gap end
	if (p.clock:GetText() or "") ~= "" then w = w + (p.clockW or 0) + gap end

	p:SetWidth(math.max(60, w - gap + pad))
end

--- Which side of the zone block the mail pill sits on.
--
--  The map's default home is the top right of the screen, and the first version
--  put the pill to the *right* of the block - which is to say, off the edge,
--  where it could never be seen. It picks the side with room now, re-checked
--  whenever the map moves, so dragging the whole thing to the left of the
--  screen flips it back.
function MM:AnchorMail()
	if not self.mail or not self.pill then return end
	local f = self.frame
	local cx = f and select(1, f:GetCenter())
	local us = UIParent:GetEffectiveScale() or 1
	local fs = (f and f:GetEffectiveScale()) or 1

	local onLeft = true
	if cx and us > 0 and fs > 0 then
		onLeft = (cx * fs / us) > (UIParent:GetWidth() / 2)
	end
	if onLeft == self._mailLeft then return end
	self._mailLeft = onLeft

	self.mail:ClearAllPoints()
	if onLeft then
		self.mail:SetPoint("RIGHT", self.pill, "LEFT", -8, 0)
	else
		self.mail:SetPoint("LEFT", self.pill, "RIGHT", 8, 0)
	end
end

function MM:UpdateMail()
	self:AnchorMail()
	if not self.mail then return end
	local cfg = A.Config:Module("minimap")
	local has = cfg.showMail ~= false and HasNewMail and HasNewMail()
	-- Alpha rather than Show, for the same reason the drawer uses it: this can
	-- flip mid-fight and it costs nothing to stay out of that argument.
	self.mail:SetAlpha(has and 1 or 0)
	self.mail:EnableMouse(has and true or false)
end

-- ---------------------------------------------------------------------------
-- build
-- ---------------------------------------------------------------------------

local function BuildFrame()
	local cfg = A.Config:Module("minimap")
	local c = Palette.c

	local f = CreateFrame("Frame", ADDON .. "Minimap", UIParent)
	f:SetSize(cfg.size, cfg.size)

	-- Three layers, and the order is the whole point ------------------------
	--
	--   f        LOW strata          the holder
	--   Minimap  LOW, +1 level       Blizzard's own, where Blizzard puts it
	--   top      LOW, +10 levels     the inner shadow, the rim and the "N"
	--
	-- An earlier version hung a soft ring off the holder as a plain BACKGROUND
	-- region, meaning to put it *behind* the map. A region draws at its frame's
	-- strata, and the holder is above the map, so it landed on top of it and the
	-- outer third came out muddy. Draw layers only order things within one frame.
	f:SetFrameStrata("LOW")

	-- MEDIUM, not LOW-with-a-higher-level, and this is what was wrong.
	--
	-- Frame *level* only orders frames within the same strata, and the Minimap is
	-- a widget type the client renders into rather than an ordinary frame - it
	-- does not composite against a sibling at LOW the way a normal frame would.
	-- The rim and the inner shadow were being drawn underneath the map, which is
	-- to say not at all: no rim, no vignette, just a hard-edged circle.
	--
	-- A whole strata up is unambiguous. Nothing else of ours lives at MEDIUM, so
	-- there is nothing here to fight with.
	local top = CreateFrame("Frame", nil, f)
	top:SetAllPoints(f)
	top:SetFrameStrata("MEDIUM")
	top:SetFrameLevel(f:GetFrameLevel() + 10)
	if top.SetFixedFrameStrata then top:SetFixedFrameStrata(true) end
	if top.SetFixedFrameLevel then top:SetFixedFrameLevel(true) end
	f.top = top

	-- border ------------------------------------------------------------------
	-- One texture, drawn over the map at exactly the map's size: a dark band
	-- around the inside and a light hairline on the edge.
	--
	-- It was two - a rim and an inner vignette - and every time I touched this
	-- element the bug was in the seam between them: first they were both under
	-- the map, then the vignette was gated behind a config value that could be
	-- zero. Two textures on one frame is a draw order, a second colour and a
	-- second switch. One is none of those, and it either draws or it does not.
	-- Drawn a few pixels *proud* of the map, deliberately. The map is shaped by
	-- a mask, and the client anti-aliases a mask edge poorly - stair-stepping
	-- around the outside is what that looks like. A border that stops at the
	-- map's edge leaves it showing; one that laps over it covers it.
	local border = top:CreateTexture(nil, "OVERLAY")
	border:SetTexture(Media.texture.minimapBorder)
	border:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
	border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
	-- Tinted with the same glassEdge every pill's rim uses, so the map's border
	-- and the zone pill below it are the same colour.
	--
	-- One vertex colour still carries two tones, because tinting is a multiply:
	-- the band is baked at luminance 0.09, so any tint leaves it near-black with
	-- a faint cast of the hue, while the hairline at 0.89 comes through as the
	-- colour itself. That is the whole reason the tones are baked as luminance
	-- rather than as finished colours.
	border:SetVertexColor(c.glassEdge[1], c.glassEdge[2], c.glassEdge[3], 1)
	f.border = border

	-- north -------------------------------------------------------------------
	local north = W.Text(f.top, "label", "CENTER")
	north:SetPoint("BOTTOM", f, "TOP", 0, 4)
	north:SetText("N")
	W.Color(north, c.textDim)
	f.north = north

	return f
end

local function BuildPill(parent)
	local cfg = A.Config:Module("minimap")
	local c = Palette.c

	local p = Glass.CreatePill(UIParent, { shadow = A.db.profile.glass.shadow })
	p:SetHeight(26)
	p:SetWidth(160)
	p:EnableMouse(true)

	-- The combat dot. A texture rather than a bullet character: it has to be the
	-- danger colour exactly, and a font's bullet is whatever the font says.
	local dot = p:CreateTexture(nil, "OVERLAY")
	dot:SetTexture(Media.texture.circleMask)
	dot:SetSize(8, 8)
	dot:SetPoint("LEFT", p, "LEFT", 14, 0)
	dot:SetVertexColor(c.danger[1], c.danger[2], c.danger[3], 1)
	dot:Hide()
	p.dot = dot

	local zone = W.Text(p, "questTitle", "LEFT")
	zone:SetPoint("LEFT", p, "LEFT", 14, 0)
	p.zone = zone

	-- Centred inside their fixed fields, not left-justified. Left-justified, the
	-- text hugs whatever is before it and all of the field's slack piles up on
	-- the right - so the gap between the zone and the coordinates read tight and
	-- the gap between the coordinates and the clock read loose, from the same
	-- 10 units of padding. Centring splits the slack.
	local coords = W.Text(p, "tiny", "CENTER")
	coords:SetPoint("LEFT", zone, "RIGHT", 10, 0)
	W.Color(coords, c.textDim)
	p.coords = coords

	local clock = W.Text(p, "tiny", "CENTER")
	clock:SetPoint("LEFT", coords, "RIGHT", 10, 0)
	W.Color(clock, c.textDim)
	p.clock = clock

	p.coordW = FieldWidth(coords, COORD_SAMPLE)
	p.clockW = FieldWidth(clock, CLOCK_SAMPLE)

	-- "There is something folded away under here."
	--
	-- A drawer with no handle is a drawer nobody opens: the buttons are off
	-- screen by design, so without this there is nothing to say the hover is
	-- worth trying. Deliberately faint - it is an affordance, not a control, and
	-- it costs its own visibility if it competes with the zone name.
	--
	-- It flips to point up while the drawer is open, which is the cheapest way to
	-- say "this is the thing you just opened" without adding a second element.
	local hint = p:CreateTexture(nil, "OVERLAY")
	hint:SetTexture(Media.texture.chevron)
	hint:SetSize(14, 7)
	-- Down on the rim rather than floating above it: at +3 it sat in the text's
	-- lap and read as part of the line rather than as a handle on the edge.
	hint:SetPoint("BOTTOM", p, "BOTTOM", 0, 1)
	hint:SetVertexColor(c.text[1], c.text[2], c.text[3], 0.35)
	hint:Hide()
	p.hint = hint

	return p
end

local function BuildDrawer(parent)
	local d = Glass.CreatePanel(UIParent, { corner = 10, shadow = A.db.profile.glass.shadow })
	d:SetSize(1, 1)
	d:SetFrameStrata("DIALOG")
	d:SetAlpha(0)
	d:EnableMouse(false)

	local tray = CreateFrame("Frame", nil, d)
	tray:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -8)
	d.tray = tray

	d:SetScript("OnUpdate", DrawerFade)
	return d
end

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

function MM:AnchorAll()
	local cfg = A.Config:Module("minimap")
	local f = self.frame

	f:SetSize(cfg.size, cfg.size)
	f:SetScale(A.db.profile.scale)
	f.border:SetAlpha(cfg.border == nil and 1 or cfg.border)

	if _G.Minimap and not InCombatLockdown() then
		pcall(_G.Minimap.SetParent, _G.Minimap, f)
		pcall(_G.Minimap.ClearAllPoints, _G.Minimap)
		pcall(_G.Minimap.SetPoint, _G.Minimap, "CENTER", f, "CENTER", 0, 0)
		pcall(_G.Minimap.SetSize, _G.Minimap, cfg.size, cfg.size)
		if _G.Minimap.SetMaskTexture then
			pcall(_G.Minimap.SetMaskTexture, _G.Minimap, Media.texture.circleMask)
		end
		-- Under the inner shadow and the rim. Blizzard's own default is LOW/2,
		-- and staying in that band keeps the map behaving the way every other
		-- addon expects it to.
		pcall(_G.Minimap.SetFrameStrata, _G.Minimap, "LOW")
		pcall(_G.Minimap.SetFrameLevel, _G.Minimap, f:GetFrameLevel() + 1)
	end

	self.pill:SetScale(A.db.profile.scale)
	self.pill:ClearAllPoints()
	self.pill:SetPoint("TOP", f, "BOTTOM", 0, -(cfg.pillOffset or 10))

	self.mail:SetScale(A.db.profile.scale)
	self:AnchorMail()

	self.drawer:SetScale(A.db.profile.scale)
	self.drawer:ClearAllPoints()
	self.drawer:SetPoint("TOP", self.pill, "BOTTOM", 0, -6)

	f.north:SetShown(cfg.showNorth ~= false)
	f.border:SetShown(cfg.ring ~= false)
end

function MM:OnEnable()
	local cfg = A.Config:Module("minimap")

	self.buttons     = self.buttons or {}
	self.buttonOrder = self.buttonOrder or {}

	if not self.frame then
		self.frame  = BuildFrame()
		self.pill   = BuildPill(self.frame)
		self.drawer = BuildDrawer(self.frame)

		-- mail, its own small pill beside the block
		local m = Glass.CreatePill(UIParent, { shadow = A.db.profile.glass.shadow })
		m:SetSize(30, 26)
		m:SetAlpha(0)
		m:EnableMouse(false)
		local icon = m:CreateTexture(nil, "ARTWORK")
		icon:SetTexture("Interface\\Minimap\\Tracking\\Mailbox")
		icon:SetSize(16, 16)
		icon:SetPoint("CENTER")
		m.icon = icon
		m:SetScript("OnEnter", function(self_)
			GameTooltip:SetOwner(self_, "ANCHOR_RIGHT")
			GameTooltip:SetText(_G.HAVE_MAIL or "You have unread mail", 1, 1, 1)
			GameTooltip:Show()
		end)
		m:SetScript("OnLeave", function() GameTooltip:Hide() end)
		self.mail = m

		-- hover: the pill opens the drawer, and both of them keep it open
		self.pill:SetScript("OnEnter", function() MM:TouchDrawer() end)
		self.pill:SetScript("OnLeave", function() MM._hoverUntil = GetTime() + 0.4 end)
		self.drawer:HookScript("OnEnter", function() MM:TouchDrawer() end)

		-- the map's own mouse: wheel zooms, right-click tracks
		if _G.Minimap then
			_G.Minimap:EnableMouseWheel(true)
			_G.Minimap:SetScript("OnMouseWheel", function(_, delta)
				if delta > 0 then
					if _G.Minimap_ZoomInClick then _G.Minimap_ZoomInClick()
					else _G.Minimap:SetZoom(math.min(5, _G.Minimap:GetZoom() + 1)) end
				else
					if _G.Minimap_ZoomOutClick then _G.Minimap_ZoomOutClick()
					else _G.Minimap:SetZoom(math.max(0, _G.Minimap:GetZoom() - 1)) end
				end
			end)
			-- Tracking has no button any more, so it lives here. This is the one
			-- piece of hidden furniture that was doing real work.
			_G.Minimap:SetScript("OnMouseUp", function(self_, button)
				if button == "RightButton" then
					local dd = _G.MiniMapTrackingDropDown
					if dd and ToggleDropDownMenu then
						pcall(ToggleDropDownMenu, 1, nil, dd, "cursor")
					end
					return
				end
				if _G.Minimap_OnClick then pcall(_G.Minimap_OnClick, self_, button) end
			end)
		end
	end

	-- LibDBIcon positions its buttons off this global, and errors on a shape
	-- string it does not know. The map is round; say so.
	if not _G.GetMinimapShape then
		_G.GetMinimapShape = function() return "ROUND" end
	end

	self:HideBlizzard()
	self:AnchorAll()

	A.Movers:Register("minimap", self.frame,
		{ point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -24, y = -24 }, "Minimap")
	A.Fader:Register(self.frame, {})
	A.Fader:Register(self.pill, {})

	for _, e in ipairs({
		"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
		"PLAYER_ENTERING_WORLD",
	}) do
		A:RegisterEvent(self, e, function() MM:UpdateZone() end)
	end
	A:RegisterEvent(self, "UPDATE_PENDING_MAIL", function() MM:UpdateMail() end)
	A:RegisterEvent(self, "MAIL_INBOX_UPDATE", function() MM:UpdateMail() end)
	A:RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() MM:UpdateZone() end)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
		MM:UpdateZone()
		if MM._collectPending then
			MM._collectPending = nil
			MM:Scan()
		end
	end)
	A:RegisterEvent(self, "PLAYER_LOGIN", function() MM:StartScanning() end)

	-- Blizzard registers the zone events on MinimapCluster itself and its
	-- handler writes MinimapZoneText. Ours is a different frame, so leave that
	-- alone - the frame it writes into is banished either way.
	local ldbi = LibStub and LibStub("LibDBIcon-1.0", true)
	if ldbi and ldbi.RegisterCallback and not self._ldbiHooked then
		self._ldbiHooked = true
		-- CallbackHandler's embed takes the *registering* object first, not the
		-- library: ldbi.RegisterCallback(me, event, handler).
		pcall(ldbi.RegisterCallback, self, "LibDBIcon_IconCreated",
			function(_, button, name) MM:Collect(button, name) end)
	end

	-- One ticker drives the clock, the coordinates and the hover grace period.
	-- Coordinates are the only expensive part and they are the part that can
	-- answer nothing, so a run of nils backs it off rather than asking ten times
	-- a second for the length of an instance.
	self._coordFails = 0
	A:RegisterTicker(self, function()
		MM:CheckHover()
		MM._tick = (MM._tick or 0) + 1
		if MM._tick % (MM._coordFails > 3 and 50 or 5) ~= 0 then return end
		MM:UpdateZone()
	end)

	self:UpdateZone()
	self:UpdateMail()
	self:StartScanning()
end

function MM:OnDisable()
	A:UnregisterTicker(self)
	if self._ticker then self._ticker:Cancel(); self._ticker = nil end
	A.Movers:Unregister("minimap")
	if self.frame then
		A.Fader:Unregister(self.frame)
		A.Fader:Unregister(self.pill)
		self:SetDrawerOpen(false, true)
	end
end

function MM:OnSkinChanged()
	if not self.frame then return end
	local c = Palette.c
	local gc = Palette.c.glassEdge
	self.frame.border:SetVertexColor(gc[1], gc[2], gc[3], 1)
	W.Color(self.frame.north, c.textDim)
	self.pill:ApplySkin()
	self.pill:SetShadow(A.db.profile.glass.shadow)
	self.mail:ApplySkin()
	self.drawer:ApplySkin()
	self.pill.dot:SetVertexColor(c.danger[1], c.danger[2], c.danger[3], 1)
	self.pill.hint:SetVertexColor(c.text[1], c.text[2], c.text[3], 0.35)
	W.Color(self.pill.coords, c.textDim)
	W.Color(self.pill.clock, c.textDim)
	-- The font may have changed with the skin, so re-measure.
	self.pill.coordW = FieldWidth(self.pill.coords, COORD_SAMPLE)
	self.pill.clockW = FieldWidth(self.pill.clock, CLOCK_SAMPLE)
	self:UpdateZone()
end

function MM:OnConfigChanged()
	if not self.frame then return end
	self:HideBlizzard()
	self:AnchorAll()
	self:LayoutDrawer()
	self:UpdateZone()
	self:UpdateMail()
	A.Fader:Refresh()
end
