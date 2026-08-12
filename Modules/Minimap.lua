--[[--------------------------------------------------------------------------
	AetherUI :: Minimap

	A round map with a frosted rim, an "N" above it, and a glass pill under it
	carrying the zone, your coordinates and the time. In a fight the pill's
	contents swap for a red dot and "In combat".

	No mail indicator. It lived here because the minimap is where Blizzard put
	one, and it moved to the Toolbox rail with everything else you have to be
	able to reach with the drawer shut - see Modules/Toolbox.lua, which is also
	where the client's very short list of mail APIs is written down.

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

	Addon launcher buttons
	----------------------
	They are NOT here. Core/Launchers.lua finds every addon's minimap button and
	Modules/Toolbox.lua puts them on the Toolbox rail; this module only clears
	Blizzard's own furniture off the map.

----------------------------------------------------------------------------]]

local ADDON, A = ...

local MM = A:NewModule("minimap")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- Widget methods captured unbound, so a collected button that has stomped its
-- own `SetPoint` (some do, to keep themselves welded to the ring) can still be
-- placed. Called as plain functions with the frame as the first argument.
-- Captured once, in Core/Launchers.lua, and shared: this module and the Toolbox
-- both place borrowed frames and there is no reason for two copies.
local Launchers = A.Launchers
local RawSetParent      = Launchers.RawSetParent
local RawClearAllPoints = Launchers.RawClearAllPoints
local RawSetPoint       = Launchers.RawSetPoint
local RawSetSize        = Launchers.RawSetSize
local RawGetName        = Launchers.RawGetName

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
-- addon launcher buttons: not here any more
--
-- This module used to collect every addon's minimap button into a drawer that
-- slid out of the zone pill. That is the Toolbox's job now - Core/Launchers.lua
-- finds them and Modules/Toolbox.lua puts them on the rail - and the drawer is
-- gone rather than kept as a setting.
--
-- It had to go rather than merely default off. The drawer showed its contents
-- ON HOVER, so any button the rail had not claimed sat in a frame at alpha 0
-- and simply vanished until somebody happened to hover the pill; and with two
-- surfaces collecting the same frames, which one owned a given button depended
-- on load order. Both symptoms were reported. One owner, one surface.
-- ---------------------------------------------------------------------------

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

	return p
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



	f.north:SetShown(cfg.showNorth ~= false)
	f.border:SetShown(cfg.ring ~= false)
end

function MM:OnEnable()
	local cfg = A.Config:Module("minimap")


	if not self.frame then
		self.frame  = BuildFrame()
		self.pill   = BuildPill(self.frame)

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
	A:RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() MM:UpdateZone() end)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
		MM:UpdateZone()
	end)

	-- Blizzard registers the zone events on MinimapCluster itself and its
	-- handler writes MinimapZoneText. Ours is a different frame, so leave that
	-- alone - the frame it writes into is banished either way.
	-- LibDBIcon's own creation callback used to land here, calling Collect
	-- directly. It belongs to Core/Launchers.lua now, and deliberately so: two
	-- entry points into Collect meant one of them skipped Claim, so a button

	-- One ticker drives the clock and the coordinates. It used to drive the
	-- drawer's hover grace period too; that went with the drawer.
	--
	-- Coordinates are the only expensive part and they are the part that can
	-- answer nothing, so a run of nils backs it off rather than asking ten times
	-- a second for the length of an instance.
	self._coordFails = 0
	A:RegisterTicker(self, function()
		MM._tick = (MM._tick or 0) + 1
		if MM._tick % (MM._coordFails > 3 and 50 or 5) ~= 0 then return end
		MM:UpdateZone()
	end)

	self:UpdateZone()
end

function MM:OnDisable()
	A:UnregisterTicker(self)
	if self._ticker then self._ticker:Cancel(); self._ticker = nil end
	A.Movers:Unregister("minimap")
	if self.frame then
		A.Fader:Unregister(self.frame)
		A.Fader:Unregister(self.pill)
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
	self.pill.dot:SetVertexColor(c.danger[1], c.danger[2], c.danger[3], 1)
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
	self:UpdateZone()
	A.Fader:Refresh()
end
