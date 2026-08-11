--[[--------------------------------------------------------------------------
	AetherUI :: Zen

	Stage two of "the HUD breathes". Core\Fader.lua decides *when*; this decides
	what is left on screen once everything else has gone.

	From the concept, bottom-centre, where the dock used to be:

	        Zen mode. Move or press a key to cancel
	    ╭───────────────────────────────────────────╮
	    │  ● ───────────────  ● ─────────────────   │   health, then power
	    ╰───────────────────────────────────────────╯
	           ╭─────────────────────────╮
	           │   · · · · · · · ·       │              a slow breath
	           ╰─────────────────────────╯

	and a small pill in the top-right corner with a map glyph, the zone and the
	time - the two things you want when you glance back at a screen you walked
	away from.

	Why this frame has no parent
	----------------------------
	Because the way to make the HUD go away is to fade `UIParent`, and a child of
	UIParent cannot survive that.

	The first version faded only the frames registered with the fader, and the
	list of things that were still on screen afterwards was long and getting
	longer: the minimap (our module re-*positions* Blizzard's map but never
	re-parents it, so fading the holder never touched it), the mail pill and the
	XP hairline (both top-level frames nobody had registered), Blizzard's chat,
	nameplates. Enumerating that set is a job with no end - every module added
	from here would have to remember to join in, and every Blizzard frame would
	have to be found by hand.

	One `UIParent:SetAlpha` covers all of it, for ever, including things that do
	not exist yet. The cost is that this frame has to live outside UIParent, which
	means it does not inherit UIParent's scale (so it is set explicitly) and it
	does not vanish with Alt-Z (so that is checked for).

	The cost that matters more: if this code ever errors while UIParent is at zero
	the player's entire interface is invisible until they reload. The tick is
	therefore wrapped, and every path out of zen restores the alpha.

	Why the map glyph is drawn rather than being the real minimap
	------------------------------------------------------------
	Because re-parenting `Minimap` is a fight you lose. SexyMap installs a
	hooksecurefunc on Minimap.SetParent that slams it back to UIParent on every
	call, and it is not the only addon that does something like this. A 16px disc
	with a rim and a blip reads as "map" at this size anyway.

	Combat
	------
	Zen cannot start in combat - the fader treats combat as a hard awake signal -
	but it can be *running* when combat starts, so nothing here calls Hide. The
	readout is parked at alpha 0 and left shown, the same as the aura tiles, and
	SetAlpha is not protected on UIParent or on anything else.

	The key watcher
	---------------
	The caption promises that a key brings the HUD back, so there has to be
	something listening. A frame with EnableKeyboard(true) whose OnKeyDown calls
	SetPropagateKeyboardInput(true) sees every press and swallows none - the same
	trick the keybind overlay uses, with the same caveat that the client resets
	propagation for every single keyboard event, so the call belongs at the top of
	the handler and nowhere else.

	It is only enabled while zen is actually on screen. A permanently
	keyboard-enabled frame is a permanent way to lock someone out of their
	keyboard if any of this is ever wrong.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Zen = A:NewModule("zen")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- Geometry, in UIParent units, measured off the concept. The readout sits on the
-- screen's bottom edge rather than following the player: it is a HUD element
-- collapsing to a whisper in the place the HUD used to be, and a fixed spot is
-- the only one that is the same every time you glance at it.
local PILL_H     = 18     -- the capsule holding both bars
local PAD        = 9      -- capsule inset
local MID        = 14     -- gap between the health half and the power half
local BLIP       = 5      -- the round pip at the head of each bar
local BLIP_GAP   = 4
local BAR_H      = 4

local DOTS       = 8
local DOT_SIZE   = 3.5
local DOT_GAP    = 9
local DOT_PILL_H = 14

local ROW_GAP    = 10     -- between the bar capsule and the dot capsule
local CAP_GAP    = 18     -- between the caption and the bar capsule

--- One full breath. Twelve a minute is roughly a resting adult, and it is slow
--  enough that the row reads as drifting rather than blinking.
local BREATH  = 5.0
local CAPTION = "Zen mode. Move or press a key to cancel"

-- ---------------------------------------------------------------------------
-- construction
-- ---------------------------------------------------------------------------

local function Disc(parent, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(Media.texture.flat)
	W.AddMask(t, parent, Media.texture.circleMask)
	return t
end

local function Build()
	-- No parent. See the note at the top: this has to outlive UIParent's alpha.
	local f = CreateFrame("Frame", ADDON .. "Zen")
	f:SetFrameStrata("MEDIUM")
	f:SetSize(250, 90)
	f:SetAlpha(0)
	f:EnableMouse(false)

	f.caption = W.Text(f, "tiny", "CENTER")
	f.caption:SetText(CAPTION)

	-- the two bars, side by side in one capsule
	local bp = Glass.CreatePill(f, { shadow = A.db.profile.glass.shadow })
	bp:EnableMouse(false)
	f.barPill = bp

	f.hpBlip = Disc(bp)
	f.pwBlip = Disc(bp)
	f.hp = W.CreateBar(bp, { rounded = true, smooth = false, bgAlpha = 0.10 })
	f.pw = W.CreateBar(bp, { rounded = true, smooth = false, bgAlpha = 0.10 })
	f.hp:EnableMouse(false)
	f.pw:EnableMouse(false)

	-- the breath
	local dp = Glass.CreatePill(f, { shadow = A.db.profile.glass.shadow })
	dp:EnableMouse(false)
	f.dotPill = dp

	f.dots = {}
	for i = 1, DOTS do f.dots[i] = Disc(dp) end

	-- the corner
	local cp = Glass.CreatePill(f, { shadow = A.db.profile.glass.shadow })
	cp:SetHeight(24)
	cp:EnableMouse(false)
	f.corner = cp

	cp.disc = Disc(cp)
	-- The zone's own map art, cropped to a circle around where you are standing.
	-- Above the disc, which stays as the backing for everywhere the art cannot
	-- be had: an instance, a battleground, anywhere GetBestMapForUnit shrugs.
	cp.map = cp:CreateTexture(nil, "ARTWORK", nil, 1)
	W.AddMask(cp.map, cp, Media.texture.circleMask)
	cp.map:Hide()
	cp.rim = cp:CreateTexture(nil, "OVERLAY")
	cp.rim:SetTexture(Media.texture.ring)
	cp.blip = cp:CreateTexture(nil, "OVERLAY")
	cp.blip:SetTexture(Media.texture.glow)
	cp.zone = W.Text(cp, "tiny", "LEFT")
	cp.clock = W.Text(cp, "tiny", "LEFT")

	return f
end

-- ---------------------------------------------------------------------------
-- layout
-- ---------------------------------------------------------------------------

local function Layout()
	local f = Zen.frame
	if not f then return end
	local cfg = A.Config:Module("zen")

	local width = cfg.width or 250
	local half  = (width - 2 * PAD - MID) / 2
	local barW  = half - BLIP - BLIP_GAP

	-- Parentless, so nothing hands us UIParent's scale. Without this the whole
	-- readout is drawn at 1.0 while every measurement here is in UIParent units.
	f:SetScale(UIParent:GetEffectiveScale() or 1)
	f:ClearAllPoints()
	f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, cfg.yOffset or 14)
	f:SetSize(width, DOT_PILL_H + ROW_GAP + PILL_H + CAP_GAP + 16)

	f.dotPill:ClearAllPoints()
	f.dotPill:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
	f.dotPill:SetSize(DOTS * DOT_SIZE + (DOTS - 1) * DOT_GAP + 20, DOT_PILL_H)

	for i, d in ipairs(f.dots) do
		d:ClearAllPoints()
		d:SetSize(DOT_SIZE, DOT_SIZE)
		d:SetPoint("LEFT", f.dotPill, "LEFT", 10 + (i - 1) * (DOT_SIZE + DOT_GAP), 0)
	end

	f.barPill:ClearAllPoints()
	f.barPill:SetPoint("BOTTOM", f.dotPill, "TOP", 0, ROW_GAP)
	f.barPill:SetSize(width, PILL_H)

	f.hpBlip:ClearAllPoints()
	f.hpBlip:SetSize(BLIP, BLIP)
	f.hpBlip:SetPoint("LEFT", f.barPill, "LEFT", PAD, 0)

	f.hp:ClearAllPoints()
	f.hp:SetSize(barW, BAR_H)
	f.hp:SetPoint("LEFT", f.hpBlip, "RIGHT", BLIP_GAP, 0)

	f.pwBlip:ClearAllPoints()
	f.pwBlip:SetSize(BLIP, BLIP)
	f.pwBlip:SetPoint("LEFT", f.hp, "RIGHT", MID, 0)

	f.pw:ClearAllPoints()
	f.pw:SetSize(barW, BAR_H)
	f.pw:SetPoint("LEFT", f.pwBlip, "RIGHT", BLIP_GAP, 0)

	f.caption:ClearAllPoints()
	f.caption:SetPoint("BOTTOM", f.barPill, "TOP", 0, CAP_GAP)
	f.caption:SetAlpha(cfg.showCaption ~= false and 1 or 0)
	f.dotPill:SetAlpha(cfg.showDots ~= false and 1 or 0)

	local cp = f.corner
	cp:ClearAllPoints()

	-- With the real map on screen, the zone and the clock belong under it --
	-- which is where the minimap module's own pill sits, and that one has faded
	-- out by the time this is on. Without it, the block stands on its own in the
	-- corner and keeps the drawn glyph.
	local MM = A:GetModule("minimap")
	local liveMap = cfg.keepMinimap ~= false and MM and MM.enabled and MM.frame
	if liveMap then
		cp:SetPoint("TOP", MM.frame, "BOTTOM", 0, -10)
	else
		cp:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -24)
	end

	-- The glyph keeps a real SIZE whether or not it is drawn, and is taken off
	-- screen with Hide.
	--
	-- Sizing it to 0 to "remove" it is how the whole thing went wrong once: a
	-- Texture given a zero width and height does not vanish, it falls back to
	-- the dimensions of the file behind it, so the ring drew at its native 512
	-- and put a purple hoop most of the way across the screen. Zero is not a
	-- size, it is the absence of one.
	--
	-- Hide rather than alpha, and only here: the note further up is about
	-- FRAMES, which are refused mid-combat when something protected hangs off
	-- them. A texture region is never protected, so this is safe from anywhere.
	-- Bigger than it was, because it is a picture now rather than a dot. The
	-- pill grows with it rather than the glyph being squeezed into a height
	-- chosen when there was nothing in it.
	local glyph = math.max(10, math.min(48, tonumber(cfg.glyphSize) or 22))
	cp:SetHeight(math.max(24, glyph + 8))
	cp.glyphW = liveMap and 0 or glyph

	cp.disc:ClearAllPoints()
	cp.disc:SetPoint("LEFT", cp, "LEFT", 10, 0)
	cp.disc:SetSize(glyph, glyph)

	cp.rim:ClearAllPoints()
	cp.rim:SetPoint("CENTER", cp.disc, "CENTER", 0, 0)
	cp.rim:SetSize(glyph, glyph)

	cp.blip:ClearAllPoints()
	cp.blip:SetPoint("CENTER", cp.disc, "CENTER", 0, 0)
	cp.blip:SetSize(6, 6)

	cp.map:ClearAllPoints()
	cp.map:SetPoint("CENTER", cp.disc, "CENTER", 0, 0)
	cp.map:SetSize(glyph, glyph)

	cp.disc:SetShown(not liveMap)
	cp.rim:SetShown(not liveMap)
	cp.blip:SetShown(not liveMap)
	if liveMap then cp.map:Hide() end

	cp.zone:ClearAllPoints()
	if liveMap then
		cp.zone:SetPoint("LEFT", cp, "LEFT", 12, 0)
	else
		cp.zone:SetPoint("LEFT", cp.disc, "RIGHT", 8, 0)
	end
	cp.clock:ClearAllPoints()
	cp.clock:SetPoint("LEFT", cp.zone, "RIGHT", 8, 0)
	-- Alpha rather than Hide, all the way down. Layout runs from OnConfigChanged,
	-- which a UI scale change can fire at any moment including mid-fight.
	cp:SetAlpha(cfg.showPill ~= false and 1 or 0)

	Zen:UpdateText()
	Zen:Restyle()
end

-- ---------------------------------------------------------------------------
-- the map crop
--
-- The world map's own art, cropped to a small circle around the player. NOT the
-- minimap: there is no way to capture what the minimap is rendering - the client
-- exposes no render-to-texture and no frame capture to an addon, and the only
-- screenshot path writes a file to disk. The zone art is the one picture of your
-- surroundings an addon can actually hold.
--
-- It is also the better one for this. It is static: no blips, no player arrow,
-- nothing moving. A calm mode is the wrong place for the only animated thing on
-- screen.
--
-- The tile arithmetic is Blizzard's own, from MapCanvasDetailLayerMixin: a layer
-- is a grid of fixed-size tiles, row-major, and the texture for a tile is at
-- (row - 1) * columns + column.
-- ---------------------------------------------------------------------------

--- How much of a tile to show, as a half-extent in tile units. Small, because
--  this is a glyph: at 0.5 you would be showing a whole tile, which for most
--  zones is a quarter of the continent and reads as brown soup.
local MAP_CROP = 0.11

local function MapArt()
	if not C_Map or not C_Map.GetMapArtLayers then return nil end

	local ok, uiMap = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok or not uiMap then return nil end

	local ok2, pos = pcall(C_Map.GetPlayerMapPosition, uiMap, "player")
	if not ok2 or not pos or not pos.x then return nil end

	local ok3, layers = pcall(C_Map.GetMapArtLayers, uiMap)
	if not ok3 or type(layers) ~= "table" then return nil end

	-- Layer one, always: the layers run coarse to fine and the finer ones are
	-- more tiles of more pixels for a picture that ends up 22 across.
	local info = layers[1]
	if type(info) ~= "table" or not info.tileWidth or info.tileWidth <= 0 then return nil end
	if not info.layerWidth or info.layerWidth <= 0 then return nil end

	local ok4, textures = pcall(C_Map.GetMapArtLayerTextures, uiMap, 1)
	if not ok4 or type(textures) ~= "table" or #textures == 0 then return nil end

	local cols = math.ceil(info.layerWidth / info.tileWidth)
	local rows = math.ceil(info.layerHeight / info.tileHeight)
	if cols < 1 or rows < 1 then return nil end

	-- Where the player is, in the layer's own pixels.
	local ax = math.max(0, math.min(1, pos.x)) * info.layerWidth
	local ay = math.max(0, math.min(1, pos.y)) * info.layerHeight

	local col = math.min(cols, math.floor(ax / info.tileWidth) + 1)
	local row = math.min(rows, math.floor(ay / info.tileHeight) + 1)

	local file = textures[(row - 1) * cols + col]
	if not file then return nil end

	-- ...and within that tile, 0..1.
	local tx = (ax - (col - 1) * info.tileWidth) / info.tileWidth
	local ty = (ay - (row - 1) * info.tileHeight) / info.tileHeight

	-- Slid rather than squashed at an edge. Clamping the two sides
	-- independently would stretch the crop into an oval as you walked into a
	-- corner of the zone; moving the whole window keeps it square and simply
	-- stops following you the last few yards.
	local h = MAP_CROP
	local function window(c)
		if c - h < 0 then return 0, 2 * h end
		if c + h > 1 then return 1 - 2 * h, 1 end
		return c - h, c + h
	end
	local l, r = window(tx)
	local t, b = window(ty)
	return file, l, r, t, b
end

--- Returns true if real art went on screen.
function Zen:UpdateMap()
	local f = self.frame
	if not f or not f.corner or not f.corner.map then return false end
	local cfg = A.Config:Module("zen")
	local m = f.corner.map

	if cfg.showMapArt == false or cfg.keepMinimap ~= false then
		m:Hide()
		return false
	end

	local file, l, r, t, b = MapArt()
	if not file then
		m:Hide()
		return false
	end

	m:SetTexture(file)
	m:SetTexCoord(l, r, t, b)
	m:Show()
	return true
end

-- ---------------------------------------------------------------------------
-- content
-- ---------------------------------------------------------------------------

function Zen:UpdateText()
	local f = self.frame
	if not f then return end
	local cp = f.corner

	-- GetMinimapZoneText is the subzone-aware one and is what the map itself
	-- shows; it comes back empty in a few places, so the broader zone name is the
	-- fallback.
	local zone = (GetMinimapZoneText and GetMinimapZoneText()) or ""
	if zone == "" then zone = (GetZoneText and GetZoneText()) or "" end

	cp.zone:SetText(zone)
	cp.clock:SetText(date("%H:%M"))

	-- Same one-second beat as the zone name. The crop only moves when you do,
	-- and a glyph this size does not need to know sooner than that.
	self:UpdateMap()

	-- Measured, not guessed: the zone name is whatever the zone is called.
	local glyphW = cp.glyphW or 16
	cp:SetWidth(10 + glyphW + (glyphW > 0 and 8 or 0) + (cp.zone:GetStringWidth() or 0)
		+ 8 + (cp.clock:GetStringWidth() or 0) + 12)
end

local function Fraction(cur, max)
	if not max or max <= 0 then return 0 end
	return math.max(0, math.min(1, (cur or 0) / max))
end

function Zen:UpdateBars()
	local f = self.frame
	if not f then return end

	f.hp:SetMinMaxValues(0, 1)
	f.hp:SetValue(Fraction(UnitHealth("player"), UnitHealthMax("player")))

	local pwMax = UnitPowerMax("player")
	local hasPower = pwMax and pwMax > 0
	f.pw:SetMinMaxValues(0, 1)
	f.pw:SetValue(hasPower and Fraction(UnitPower("player"), pwMax) or 0)
	-- A class with no power pool at all (a level-one warrior out of combat) would
	-- otherwise show an empty half-capsule, which reads as a bug rather than as
	-- an absence.
	f.pw:SetAlpha(hasPower and 1 or 0)
	f.pwBlip:SetAlpha(hasPower and 1 or 0)
end

function Zen:Restyle()
	local f = self.frame
	if not f then return end
	local c = Palette.c

	local hp = Palette:HealthColor("player")
	local pw = Palette:PowerColor("player")
	f.hp:SetColors(hp)
	f.pw:SetColors(pw)
	f.hp:SetBackdropColor({ c.text[1], c.text[2], c.text[3], 0.10 })
	f.pw:SetBackdropColor({ c.text[1], c.text[2], c.text[3], 0.10 })
	f.hpBlip:SetVertexColor(hp[1][1], hp[1][2], hp[1][3], 1)
	f.pwBlip:SetVertexColor(pw[1][1], pw[1][2], pw[1][3], 1)

	-- The concept's caption is plain text on open ground with no plate behind it,
	-- which only works if it is bright enough to survive whatever is back there.
	-- textFaint was not - over a lit doorway it disappeared completely.
	W.Color(f.caption, c.textDim)
	W.Color(f.corner.zone, c.text)
	W.Color(f.corner.clock, c.textDim)

	-- The disc takes the glass token's OWN alpha, not 0.85 of it. Midnight's
	-- glass is C(12, 10, 28) -- very nearly black -- and a near-black fill at
	-- 0.85 is not a glass disc, it is a hole. On screen it read as a rendering
	-- fault rather than as a glyph. The rim carries the shape instead, which is
	-- the same rule a pale panel follows on Daylight.
	f.corner.disc:SetVertexColor(c.glass[1], c.glass[2], c.glass[3], c.glass[4] or 0.55)
	f.corner.rim:SetVertexColor(c.glassEdgeHi[1], c.glassEdgeHi[2], c.glassEdgeHi[3],
		c.glassEdgeHi[4] or 1)
	f.corner.blip:SetVertexColor(c.accent[1], c.accent[2], c.accent[3], 0.9)

	for _, d in ipairs(f.dots) do
		d:SetVertexColor(c.text[1], c.text[2], c.text[3], 1)
	end
end

--- The breath. Each dot lags the one before it, so the row reads as one wave
--  travelling across rather than eight things blinking in unison. Shallow on
--  purpose: the concept's dots are a uniform quiet grey, and this only has to be
--  enough that a completely still screen does not read as a frozen client.
local function Breathe(f, t)
	for i, d in ipairs(f.dots) do
		local s = math.sin((t / BREATH) * 2 * math.pi - (i - 1) * 0.38)
		d:SetAlpha(0.28 + 0.32 * (s > 0 and s * s or 0))
	end
end

-- ---------------------------------------------------------------------------
-- taking the rest of the interface away
-- ---------------------------------------------------------------------------

--- The frames `UIParent`'s alpha does not reach.
--
--  `Minimap` is here for a reason worth writing down. Our own module re-parents
--  the map into its holder, the holder is a child of UIParent, and fading
--  UIParent left the map sitting there at full brightness anyway. It is not an
--  ordinary Frame - it is a widget type the client renders into, and the map
--  surface is composited outside the normal alpha cascade, the same family of
--  quirk as it refusing to composite against a sibling at its own strata. Its
--  *own* SetAlpha is honoured, so it gets driven by hand.
--
--  **And so does every frame hanging off it.** Minimap being outside the
--  cascade means its children are outside it too, and dimming the parent does
--  not reach them. Anything an addon hangs on the minimap - a Questie marker, a
--  TomTom waypoint - lands in that set, so it cannot be a list of names, it has
--  to be a walk.
--
--  What the walk still does NOT reach is the layers the ENGINE draws into the
--  minimap: the POI blips and the player arrow. Those are not regions and not
--  children, they are part of what the widget renders, and no SetAlpha we can
--  make reaches them. On screen that left a flight-master icon and the player
--  arrow hanging over an empty hillside in the middle of zen mode. The only
--  thing that takes them is Hide, which is why DimUI does that as well.
--
--  Resolved on each call rather than cached: the global is not guaranteed to
--  exist before PLAYER_LOGIN, another addon replacing it is exactly the sort of
--  thing that happens, and pins come and go while zen is running.
local function Escapees(out)
	out = out or {}
	local mm = _G.Minimap
	if not mm then return out end
	if mm.IsForbidden and mm:IsForbidden() then return out end

	out[#out + 1] = mm

	if not mm.GetChildren then return out end
	local kids = { pcall(mm.GetChildren, mm) }
	if not kids[1] then return out end
	for i = 2, #kids do
		local k = kids[i]
		-- IsForbidden first, and a failed call counts as forbidden: any method
		-- on a forbidden frame raises, including GetName.
		local ok, forbidden = true, false
		if k and k.IsForbidden then ok, forbidden = pcall(k.IsForbidden, k) end
		if k and k.SetAlpha and ok and not forbidden then
			out[#out + 1] = k
		end
	end
	return out
end

--- `a` is the readout's own alpha, so the interface is exactly its inverse.
function Zen:DimUI(a)
	local cfg = A.Config:Module("zen")
	if cfg.dimUI == false then
		self:RestoreUI()
		return
	end

	local ui = 1 - a * (1 - (cfg.hudAlpha or 0))
	UIParent:SetAlpha(ui)

	-- The map stays. Zen used to draw a small glass disc in the corner as a
	-- stand-in for it; the real thing, left exactly where it already is, is a
	-- better answer than any glyph -- it is the one part of the HUD that is
	-- still telling you something while you are not playing.
	--
	-- Left ALONE rather than moved. Shrinking it into the corner block means
	-- handing it back on wake, and zen wakes on PLAYER_REGEN_DISABLED -- so the
	-- hand-back always runs with combat already locked down, where SetParent is
	-- refused for anything with a protected frame hanging off it. Getting that
	-- wrong strands the minimap in the corner for the whole fight.
	--
	-- Nothing to dim, nothing to hide, nothing to put back.
	if cfg.keepMinimap ~= false then
		self._dimmed = a > 0
		return
	end

	-- Each escapee is dimmed against the alpha it already had, not slammed to
	-- `ui`. A minimap pin an addon is deliberately holding at half alpha must
	-- come back at half alpha, not at full.
	self._escapeeAlpha = self._escapeeAlpha or {}
	local base = self._escapeeAlpha
	for _, f in ipairs(Escapees()) do
		if base[f] == nil then base[f] = f:GetAlpha() or 1 end
		pcall(f.SetAlpha, f, base[f] * ui)
	end

	-- The engine's own layers -- POI blips and the player arrow -- ignore every
	-- alpha we can set, so at the bottom of the fade the map is hidden outright.
	--
	-- At the BOTTOM, not throughout, because Hide has no half measure: hiding it
	-- when zen starts would pop the map off a second before everything around it
	-- had finished fading. The blips stay bright through the fade and go with
	-- the rest of it, which is the least visible of the three wrong answers.
	--
	-- Minimap is a plain widget, so Hide is combat-safe. Whether it was shown is
	-- recorded, because the player may have had no minimap to begin with and
	-- handing them one back is not a restore.
	local mm = _G.Minimap
	if mm and mm.IsShown and not (mm.IsForbidden and mm:IsForbidden()) then
		if ui <= 0.02 then
			if self._mmShown == nil then self._mmShown = mm:IsShown() and true or false end
			if mm:IsShown() then pcall(mm.Hide, mm) end
		elseif self._mmShown ~= nil then
			if self._mmShown then pcall(mm.Show, mm) end
			self._mmShown = nil
		end
	end

	self._dimmed = a > 0
end

function Zen:RestoreUI()
	if not self._dimmed then return end
	self._dimmed = false
	UIParent:SetAlpha(1)

	-- Everything we touched, put back to what it was -- including anything that
	-- has since gone away, which is why this walks the RECORD rather than the
	-- minimap. A pin that vanished mid-zen and came back is not our business;
	-- one we dimmed and never restored is.
	local base = self._escapeeAlpha
	if base then
		for f, a in pairs(base) do
			if f and f.SetAlpha then pcall(f.SetAlpha, f, a) end
		end
	end
	self._escapeeAlpha = nil

	local mm = _G.Minimap
	if self._mmShown ~= nil then
		if self._mmShown and mm and mm.Show then pcall(mm.Show, mm) end
		self._mmShown = nil
	end
end

-- ---------------------------------------------------------------------------
-- the key watcher
-- ---------------------------------------------------------------------------

local function Wake()
	if not A.Fader then return end
	A.Fader:Touch()
	A.Fader:Update()
end

local function BuildKeys()
	local k = CreateFrame("Frame", ADDON .. "ZenKeys", UIParent)
	k:SetSize(1, 1)
	k:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	k:SetFrameStrata("TOOLTIP")
	k:EnableKeyboard(false)
	k:SetPropagateKeyboardInput(true)

	k:SetScript("OnKeyDown", function(self)
		-- First line, every time. The client clears the propagation flag after
		-- every keyboard event, so setting it once at construction buys nothing
		-- and setting it after the wake would leave a window where an error in
		-- Wake() eats somebody's keypress.
		self:SetPropagateKeyboardInput(true)
		Wake()
	end)
	k:SetScript("OnKeyUp", function(self)
		self:SetPropagateKeyboardInput(true)
	end)

	return k
end

function Zen:SetKeysEnabled(on)
	local cfg = A.Config:Module("zen")
	if on and cfg.keyboardWake == false then on = false end

	if on and not self.keys then self.keys = BuildKeys() end
	if not self.keys then return end
	if self._keysOn == on then return end
	self._keysOn = on
	self.keys:EnableKeyboard(on and true or false)
	self.keys:SetPropagateKeyboardInput(true)
end

-- ---------------------------------------------------------------------------
-- driving
-- ---------------------------------------------------------------------------

local textAccum = 0

local function TickBody(self, dt)
	local f = self.frame
	if not f then return end
	local cfg = A.Config:Module("zen")

	-- Alt-Z, a cinematic, a screenshot with the UI off. Whatever hid the
	-- interface meant this too, and we are outside UIParent so nothing else is
	-- going to tell us.
	if not UIParent:IsShown() then
		f:SetAlpha(0)
		self:RestoreUI()
		return
	end

	local cur  = f:GetAlpha()
	local want = self.want or 0
	local diff = want - cur

	if math.abs(diff) < 0.005 then
		f:SetAlpha(want)
		if want <= 0 then
			-- Parked. Put the interface back first, then stop costing anything
			-- until the fader asks for us again.
			self:RestoreUI()
			A:UnregisterTicker(self)
			self:SetKeysEnabled(false)
			return
		end
	else
		-- Rising is the HUD going away, so it borrows the HUD's fade-out time;
		-- falling is the HUD coming back, and borrows its fade-in.
		local speed = diff > 0 and (cfg.fadeOut or 2.5) or (cfg.fadeIn or 0.30)
		f:SetAlpha(cur + diff * math.min(1, (dt / math.max(0.01, speed)) * 2.5))
	end

	self:DimUI(f:GetAlpha())
	self:UpdateBars()
	if cfg.showDots ~= false then Breathe(f, GetTime()) end

	textAccum = textAccum + dt
	if textAccum >= 1 then
		textAccum = 0
		self:UpdateText()
	end
end

local function Tick(self, dt)
	local ok, err = pcall(TickBody, self, dt)
	if ok then return end

	-- Never leave somebody's entire interface at zero alpha because of a bug in
	-- here. This is the one failure in this module that cannot be shrugged off:
	-- the HUD not fading is a cosmetic complaint, an invisible UI is a reload.
	self:RestoreUI()
	self.want = 0
	if self.frame then self.frame:SetAlpha(0) end
	self:SetKeysEnabled(false)
	A:UnregisterTicker(self)
	A.lastFailure = "zen: " .. tostring(err)
	A:Print("|cffff8a8azen failed and put the interface back:|r " .. tostring(err))
end

--- Called by the fader on every state change.
function Zen:SetActive(on)
	if not self.frame then return end
	self.want = on and 1 or 0
	A:RegisterTicker(self, Tick)

	if on then
		self:UpdateText()
		self:UpdateBars()
		self:Restyle()
		-- Not in combat, by construction: the fader treats combat as awake. The
		-- guard is here anyway because "by construction" is how the last three
		-- combat bugs started.
		if not InCombatLockdown() then self:SetKeysEnabled(true) end
	else
		self:SetKeysEnabled(false)
	end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function Zen:OnEnable()
	if not self.frame then self.frame = Build() end
	self.frame:Show()
	self.want = 0
	self.frame:SetAlpha(0)
	self:RestoreUI()

	A:RegisterEvent(self, "ZONE_CHANGED", "UpdateText")
	A:RegisterEvent(self, "ZONE_CHANGED_INDOORS", "UpdateText")
	A:RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", "UpdateText")

	self:OnConfigChanged()
	if A.Fader then A.Fader:Refresh() end
end

function Zen:OnDisable()
	self:SetKeysEnabled(false)
	self.want = 0
	if self.frame then self.frame:SetAlpha(0) end
	self:RestoreUI()
	A:UnregisterTicker(self)
	-- The fader gates zen on this module being enabled, so it has to be told the
	-- ground moved - otherwise the HUD stays at zen's alpha with nothing to show
	-- for it.
	if A.Fader then A.Fader:Refresh() end
end

function Zen:OnSkinChanged()
	self:Restyle()
end

function Zen:OnConfigChanged()
	Layout()
	self:UpdateBars()
end
