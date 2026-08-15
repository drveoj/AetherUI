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

	The frosted pane, and why it is not a blur
	------------------------------------------
	It is not a blur because there is no way to write one. The client exposes no
	render-to-texture, no shader stage and no post-process hook to an addon; the
	3D scene is the one surface in the game whose pixels this addon can never
	read, let alone convolve. Every "blur" addon that has ever existed either
	fakes it or is not doing what it says.

	So this fakes it, in the honest direction: rather than blurring the world, it
	puts a pane in front of the world. That is what frosted glass physically is -
	the scene behind stays perfectly sharp, and every cue that reads as "frosted"
	lives on the pane.

	**It gets brighter, not darker.** This is the correction that mattered and it
	is worth stating plainly, because the first version got it backwards on a
	reasonable-sounding theory. The theory was that zen means the world steps
	back, so the pane should be dark. What that produces on a dark skin is a
	near-black sheet, and a near-black sheet does not read as glass: every edge
	in the scene stays perfectly crisp behind it and it looks like somebody
	turned the lights off. Frosted glass SCATTERS light. It is brighter than what
	is behind it, and what it destroys is contrast, not brightness.

	Four layers:

	  tint      the skin's glass colour lifted toward white, flat, full screen.
	            The body of the glass.
	  scatter   Frost.tga, ordinary blend, tiled a few times across the screen.
	            The structure - the patches you can actually see, which is what
	            makes the eye read a *surface* rather than a filter.
	  bloom     Frost.tga again, ADDITIVE, at a different scale. This is the one
	            that does the work a blur would: additive light lifts the darks
	            without touching the brights, which compresses the contrast of
	            everything behind the pane. Contrast is most of what a blur takes
	            away, so this is what reads as "blurred".
	  vignette  a little darker at the edges, so the surface has a shape. Kept
	            low - at 0.45 it was doing most of the darkening the pane was
	            being blamed for.

	The two Frost layers are tiled at deliberately mismatched scales and drift
	slowly in opposite directions. The mismatch is not decoration: two copies of
	one texture at the same scale sliding past each other beat into a moire far
	more visible than either layer. The drift is what gives the pane parallax
	against a static world, and the eye is much better at detecting parallax than
	texture - it is the cheapest cue available for "there is a surface between
	you and this".

	Parentless and anchored to `WorldFrame` rather than to `UIParent`, for two
	separate reasons. It has to survive UIParent's alpha like the readout does;
	and WorldFrame is the physical screen at scale 1, always, which means the
	scatter can be tiled against real pixels without any scale arithmetic and
	without moving when the UI scale changes.

	Strata BACKGROUND: above WorldFrame, below everything the interface puts up.
	If `dimUI` is off - so the HUD is still on screen during zen - the HUD is
	still drawn over the pane, which is the right way round.

	Nameplates, and names
	---------------------
	The one distraction UIParent's alpha genuinely does not reach. Both of these
	are rendered against the world rather than composited into the interface, so
	fading the interface leaves them hanging over an empty hillside.

	**They are two separate systems.** The bars are `nameplateShow*`; the
	floating text is `UnitName*`; turning off one does nothing whatever to the
	other. The first version took only the bars, and the result was a quiet
	screen with every name, guild tag and pet label still floating over it -
	which looks broken rather than deliberate, and is arguably worse than leaving
	both alone. One switch drives both, because nobody wants half of it.

	At the bottom of the fade rather than throughout, for the same reason the
	minimap is hidden there: the CVars have no half measure, and a plate cannot
	be dimmed on the way down.

	Dimming them by hand *was* tried - walk `C_NamePlate.GetNamePlates()` each
	tick and drive alpha - and was thrown away. The client pools plate frames and
	hands the same frame back for a different unit later, so a plate we left at
	alpha 0 comes back as an invisible nameplate on somebody else, in combat,
	with no way to notice. Popping out at the end of a fade is a cosmetic
	complaint. An invisible nameplate in a raid is not.

	Tooltips need nothing at all. GameTooltip is a child of UIParent and goes
	with it.

	The shot
	--------
	Zen sets up a camera rather than only clearing a screen: the character sits,
	and the view pulls back.

	Sitting goes through `C_ChatInfo.PerformEmote`, not `SitStandOrDescendStart`
	- the latter is what the keybind runs and it is a TOGGLE, so on a player who
	is already sitting it stands them up. That is the wrong way round on exactly
	the players most likely to have been idle long enough to get here. And not
	`DoEmote` either, which on 1.15 exists only when `loadDeprecationFallbacks`
	is set, so the fallback runs the other way from usual: the modern call first.

	Nothing can ask whether the player is already sitting - Classic exposes no
	such query - which is why standing up at the end is unconditional rather than
	conditional on us having been the ones who sat them down.

	The camera divides cleanly into a half that is reversible and a half that is
	not, and the difference is worth knowing before touching it:

	  zoom   exact. `GetCameraZoom` reads the current distance, so the target is
	         a difference and the player's own distance goes back precisely. One
	         call each way: each CameraZoom call starts the client's own glide,
	         and issuing a new one every tick restarts that glide every tick,
	         which is a camera that never arrives.
	  pitch  NOT TOUCHED. There is no getter and no setter - only
	         MoveViewUpStart/Stop, which is movement over time - so an amount
	         can be asked for and never measured. Worse, the RATE is
	         `cameraPitchMoveSpeed`, which the player's own Mouse Look Speed
	         slider writes anywhere between 45 and 135 degrees a second: the
	         same duration is a different angle on every machine, and the number
	         that framed the shot here put the camera through the floor there.

	         DialogueUI gets a consistent cinematic camera on this same client
	         and calls MoveView exactly zero times - it sets CVars, every one of
	         them absolute, readable and restorable. So does this. The shot is
	         the zoom and the nameplate CVars, and the
	         tilt that kept breaking is simply gone.

	`SaveView(5)`/`SetView(5)` would restore a pitch exactly if one were ever
	wanted. It costs the player a saved-view slot for ever and DialogueUI's own
	camera module carries a note that it breaks the camera-following style, which
	is why it is not used here either.
	The audio profile
	-----------------
	Zen borrows the sound channels for as long as it is on screen and gives them
	back. Three rules, and they are all about giving them back:

	**Ratios, not volumes.** The duck settings are fractions of what the player
	already had. This never needs to know what anybody's normal mix is and can
	never flatten a careful one into ours.

	**Master is never touched.** Somebody who has turned the game down has turned
	the game down.

	**What we wrote is what we take back.** Every channel records the value we
	last pushed into it; on the way out, a channel that no longer holds that
	value was changed by the player (or by another addon) while zen was running,
	and is left exactly where they put it. Restoring it would be overwriting a
	deliberate change with a stale one.

	`PlayMusic` is used rather than `PlaySoundFile` because it loops the file it
	is given, on the Music channel, for free - which is the whole requirement.

	The one channel that goes UP is Music, and only ever to a floor. A meditation
	track played through a music channel somebody left at zero is a feature that
	silently does nothing, and "it's broken" is the report you get. Above the
	floor already, nothing happens.

	Nothing here starts at all if `Sound_EnableAllSound` is off. That is not a
	setting to work around; it is somebody saying they want silence.
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

--- Noise.tga's own size. The grain is tiled at 1:1 against physical pixels, so
--  it is the same grain on a 1080p laptop and a 4K monitor rather than a
--  four-times-coarser one.
--- How wide one tile of Frost.tga is drawn, in PHYSICAL pixels. 900 puts a
--  little under three tiles across a 2560 screen, so a patch of scatter is
--  roughly a tenth of the screen: big enough to see, small enough that the
--  repeat does not announce itself.
--
--  It is not the file's own 512. Tiling a texture 1:1 against physical pixels
--  is what the first version did with Noise.tga, and at twenty tiles across a
--  screen the result is finer than the eye resolves and contributes nothing at
--  all - the pane read as a flat filter because, in effect, it was one.
local FROST_SCALE = 900

--- The second scatter layer is drawn this much larger than the first. Anything
--  near 1 and the two copies beat into a moire as they drift past each other;
--  1.6 is far enough off that they read as two separate depths in the glass.
local FROST_SCALE2 = 1.6

local AUDIO = [[Interface\AddOns\]] .. ADDON .. [[\Media\Audio\]]

--- The bundled tracks. `key` is what goes in the profile, so renaming a file
--  here breaks nothing that is already saved as long as the key survives; a key
--  that no longer resolves falls back to the first track rather than to silence.
Zen.TRACKS = {
	{ key = "garden",    name = "Garden",    file = AUDIO .. "zen-garden.ogg"    },
	{ key = "ocean",     name = "Ocean",     file = AUDIO .. "zen-ocean.ogg"     },
	{ key = "serenity",  name = "Serenity",  file = AUDIO .. "zen-serenity.ogg"  },
	{ key = "stillness", name = "Stillness", file = AUDIO .. "zen-stillness.ogg" },
	{ key = "water",     name = "Water",     file = AUDIO .. "zen-water.ogg"     },
}

--- The channels zen ducks, and the profile key holding each one's ratio.
--  Master is deliberately absent. Music is handled separately - it is the one
--  channel that goes up rather than down.
local DUCKED = {
	{ cvar = "Sound_SFXVolume",      key = "duckSFX",      default = 0.05 },
	{ cvar = "Sound_AmbienceVolume", key = "duckAmbience", default = 0.15 },
	{ cvar = "Sound_DialogVolume",   key = "duckDialog",   default = 0.10 },
}

--- Everything the engine draws into the world that is made of words.
--
--  TWO INDEPENDENT SYSTEMS, which is the thing worth knowing here. Nameplates
--  (the bars) and unit names (the floating text) are separate features with
--  separate CVars, and turning off one leaves the other exactly where it was.
--  The first version took only the plates, and the result was a quiet screen
--  with every name, guild tag and pet label still hanging in the air over it -
--  which is arguably worse than leaving both, because it looks broken rather
--  than deliberate.
--
--  Note `UnitNameHostleNPC`. That is Blizzard's spelling, in their own source,
--  and it has been wrong for twenty years. Correcting it here would simply mean
--  the CVar is never found.
--
--  Probed rather than assumed: `nameplateShowFriendlyPlayers` is what 1.15
--  calls the friendly toggle, but it was `nameplateShowFriends` for years and
--  other flavours still use that name. Setting a CVar that does not exist
--  throws, so the list is filtered at runtime against GetCVar rather than being
--  a version table somebody has to maintain.
local WORLD_TEXT_CVARS = {
	-- the bars
	"nameplateShowAll",
	"nameplateShowEnemies",
	"nameplateShowEnemyMinions",
	"nameplateShowEnemyMinus",
	"nameplateShowFriendlyPlayers",
	"nameplateShowFriends",
	"nameplateShowFriendlyPlayerMinions",
	"nameplateShowFriendlyNpcs",

	-- the words. A player's guild tag and a pet's <Owner's Pet> label are part
	-- of their name block rather than settings of their own, so they go with it.
	"UnitNameOwn",
	"UnitNameNPC",
	"UnitNameFriendlySpecialNPCName",
	"UnitNameHostleNPC",
	"UnitNameInteractiveNPC",
	"UnitNameNonCombatCreatureName",
	"UnitNameFriendlyPlayerName",
	"UnitNameFriendlyMinionName",
	"UnitNameEnemyPlayerName",
	"UnitNameEnemyMinionName",
	-- Four more that DialogueUI's camera module lists and the Classic settings
	-- panel does not expose. They may well not exist on this client; the probe
	-- means listing one that does not is free, and listing one that DOES exist
	-- and forgetting it is a pet's name left hanging in the middle of the shot.
	"UnitNameFriendlyPetName",
	"UnitNameFriendlyGuardianName",
	"UnitNameEnemyPetName",
	"UnitNameEnemyGuardianName",
}

-- ---------------------------------------------------------------------------
-- construction
-- ---------------------------------------------------------------------------

--- A small filled circle.
--
--  Chip-Disc rather than a flat texture masked by Circle-Mask. Both draw a
--  disc; the difference is where the anti-aliasing comes from. A MASK's edge is
--  the client's to resolve and it does that poorly - the note in
--  generate_textures.py's minimap_border() says so, and W.CreateBadge says it
--  again - and Circle-Mask is 256 because the minimap MAGNIFIES it, so at the
--  sixteen pixels this glyph is drawn at it was being minified sixteen times.
--  Chip-Disc is 64 with its own ramp baked in.
local function Disc(parent, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(Media.texture.chipDisc)
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
	cp.rim:SetTexture(Media.texture.chipRim)
	cp.blip = cp:CreateTexture(nil, "OVERLAY")
	cp.blip:SetTexture(Media.texture.glow)
	cp.zone = W.Text(cp, "tiny", "LEFT")
	cp.clock = W.Text(cp, "tiny", "LEFT")

	return f
end

-- ---------------------------------------------------------------------------
-- the frosted pane
--
-- See the note at the top: this is a pane in front of the world, not a blur of
-- it, because a blur is not a thing an addon can write.
-- ---------------------------------------------------------------------------

local function BuildFrost()
	-- Parentless for the same reason the readout is, and anchored to WorldFrame
	-- rather than UIParent because WorldFrame is the physical screen at scale 1
	-- and never moves, never rescales and is never hidden.
	local f = CreateFrame("Frame", ADDON .. "ZenFrost")
	f:SetFrameStrata("BACKGROUND")
	f:SetFrameLevel(0)
	f:SetScale(1)
	f:SetAllPoints(WorldFrame)
	f:EnableMouse(false)
	f:SetAlpha(0)
	f:Hide()

	-- 1. the wash. A flat sheet of the skin's glass, lifted toward white.
	f.tint = f:CreateTexture(nil, "BACKGROUND")
	f.tint:SetTexture(Media.texture.flat)
	f.tint:SetAllPoints(f)

	-- 2 and 3. the scatter, twice.
	--
	-- "REPEAT" on both axes turns the texcoords into a tile count rather than a
	-- crop; Frost.tga is authored seamless for exactly this.
	--
	-- The two are not a mistake and not a doubling for strength. They do
	-- different jobs. `scatter` is an ordinary blend and gives the pane its
	-- structure - the patches you can see. `bloom` is ADDITIVE, and additive
	-- light over a scene is the one tool here that behaves anything like a blur:
	-- it lifts the darks without touching the brights, which compresses the
	-- contrast of everything behind the pane. Contrast is most of what a blur
	-- takes away, so this is the layer that reads as "blurred" rather than as
	-- "dimmed", and it is why the pane gets BRIGHTER rather than darker.
	--
	-- They are tiled at deliberately mismatched scales. At the same scale two
	-- copies of one texture drifting past each other beat into a moire that is
	-- far more visible than either layer.
	f.scatter = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.scatter:SetTexture(Media.texture.frost, "REPEAT", "REPEAT")
	f.scatter:SetAllPoints(f)

	f.bloom = f:CreateTexture(nil, "ARTWORK", nil, 0)
	f.bloom:SetTexture(Media.texture.frost, "REPEAT", "REPEAT")
	f.bloom:SetAllPoints(f)

	-- 4. the edge.
	f.vignette = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.vignette:SetTexture(Media.texture.vignette)
	f.vignette:SetAllPoints(f)

	return f
end

--- Work out how many times each scatter layer repeats across the screen, and
--  remember it so the drift can offset from it without recomputing.
--
--  Measured against PHYSICAL pixels, so the pane looks the same on a laptop and
--  on a 4K monitor rather than being four times coarser on one of them.
local function LayoutFrost()
	local f = Zen.frost
	if not f then return end

	local w, h
	if GetPhysicalScreenSize then w, h = GetPhysicalScreenSize() end
	-- WorldFrame's own size is in virtual units, so it is only the right answer
	-- when the physical size is not available: the scatter comes out coarser or
	-- finer than intended but still seamless, which is a far smaller wrong than
	-- dividing by zero.
	if not w or w <= 0 then w = (WorldFrame and WorldFrame:GetWidth()) or 1920 end
	if not h or h <= 0 then h = (WorldFrame and WorldFrame:GetHeight()) or 1080 end

	-- Both axes divide by the SAME number, so the tile stays square and the
	-- patches are not stretched into ovals on a wide screen.
	f.tilesX  = w / FROST_SCALE
	f.tilesY  = h / FROST_SCALE
	f.tiles2X = w / (FROST_SCALE * FROST_SCALE2)
	f.tiles2Y = h / (FROST_SCALE * FROST_SCALE2)

	Zen:DriftFrost(0)
end

--- Slide the two scatter layers past each other. `dt` is the tick's own delta.
--
--  Slow enough that it is not motion - at the default it takes most of a minute
--  to cross a patch - but it is what makes the pane read as a SURFACE between
--  you and a static world rather than as a decal stuck to the monitor. The eye
--  is far better at detecting parallax than it is at detecting texture.
--
--  Opposite directions, and on different axes, so neither layer can look like
--  the other one lagging.
--
--  ACCUMULATED from dt rather than computed from GetTime(). Two reasons, and
--  the first one is visible: with `offset = now * speed`, dragging the speed
--  slider to zero does not stop the pane, it teleports it back to the origin,
--  because the offset is a function of a clock that never stops. Accumulating
--  means zero simply means "stop", which is what the slider says it does.
--
--  The second is that GetTime() counts up from login, so a long session would
--  push the texture coordinates into the thousands and start losing precision
--  in the fraction that actually matters.
function Zen:DriftFrost(dt)
	local f = self.frost
	if not f or not f.tilesX then return end
	local cfg = A.Config:Module("zen")

	local u = (self._drift or 0) + (dt or 0) * (tonumber(cfg.frostDrift) or 0)
	-- Wrapped at one tile. The texture repeats, so an offset of 1 and an offset
	-- of 0 are the same picture; letting it run means the number climbs for ever
	-- for no benefit at all.
	self._drift = u % 1
	u = self._drift

	f.scatter:SetTexCoord(u, u + f.tilesX, u * 0.6, u * 0.6 + f.tilesY)
	f.bloom:SetTexCoord(-u * 0.75, -u * 0.75 + f.tiles2X,
		u * 0.45, u * 0.45 + f.tiles2Y)
end

--- Colours only. The pane's overall *opacity* is the zen fade, set in SetFrost.
local function RestyleFrost()
	local f = Zen.frost
	if not f then return end
	local cfg = A.Config:Module("zen")
	local c = Palette.c

	-- The skin's glass HUE, lifted toward white by the brightness setting, at
	-- the user's own opacity rather than at the token's - a full-screen pane is
	-- not a small panel, and the token's alpha was chosen for something you look
	-- through at a health bar.
	--
	-- The lift is the whole correction. The first version did the opposite: it
	-- CAPPED the tint's brightness on the theory that the world should step
	-- back, which on Midnight means dragging a near-black sheet across the
	-- screen. That is not what frosted glass does. Frosted glass SCATTERS light,
	-- so it is brighter than what is behind it and it destroys contrast; a dark
	-- sheet keeps every edge in the scene perfectly crisp and merely turns the
	-- lights off. On screen it read as a fault rather than as glass.
	local lift = math.max(0, math.min(1, tonumber(cfg.frostBrightness) or 0.75))
	local r = c.glass[1] + (1 - c.glass[1]) * lift
	local g = c.glass[2] + (1 - c.glass[2]) * lift
	local b = c.glass[3] + (1 - c.glass[3]) * lift

	f.tint:SetVertexColor(r, g, b,
		math.max(0, math.min(1, tonumber(cfg.frostOpacity) or 0.70)))

	local scatter = math.max(0, math.min(1, tonumber(cfg.frostScatter) or 0.35))

	-- Structure, in the same colour as the wash so the patches read as thicker
	-- and thinner glass rather than as dirt on it.
	f.scatter:SetBlendMode("BLEND")
	f.scatter:SetVertexColor(r, g, b, scatter * 0.55)

	-- Light. Tinted toward the skin's type colour rather than the glass colour,
	-- because this one is not the surface - it is what the surface is scattering.
	f.bloom:SetBlendMode("ADD")
	f.bloom:SetVertexColor(c.text[1], c.text[2], c.text[3], scatter * 0.45)

	-- Untinted black. The vignette is a shape, not a colour: tinting it with the
	-- skin would make Daylight's edges *lighter* than its middle, which is the
	-- opposite of what a vignette is for. Low by default now - it was doing most
	-- of the darkening the pane was being blamed for.
	f.vignette:SetVertexColor(0, 0, 0,
		math.max(0, math.min(1, tonumber(cfg.frostVignette) or 0.15)))
end

--- `a` is the readout's alpha, so the pane arrives exactly as the HUD leaves.
function Zen:SetFrost(a)
	local f = self.frost
	if not f then return end
	local cfg = A.Config:Module("zen")

	if cfg.frost == false or a <= 0.001 then
		-- Hide rather than alpha 0, so a pane that is not wanted costs nothing to
		-- draw. Safe from anywhere: this frame is parentless and has never had
		-- anything protected on it.
		f:SetAlpha(0)
		if f:IsShown() then f:Hide() end
		return
	end

	if not f:IsShown() then f:Show() end
	f:SetAlpha(a)
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
	-- The rim laps OVER the disc rather than sitting flush on it, which is the
	-- same correction W.CreateBadge records and generate_textures.py's
	-- minimap_border() records before that: the disc is masked, a mask's edge is
	-- the client's to anti-alias and it does that poorly, so a rim stopping
	-- exactly on it leaves the mask's own stair-stepping showing outside. Flush,
	-- this read as a second rougher circle just outside the first.
	local proud = A:PxIn(cp)
	cp.rim:SetPoint("CENTER", cp.disc, "CENTER", 0, 0)
	cp.rim:SetSize(glyph + proud * 2, glyph + proud * 2)

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

	-- Not part of the readout's geometry, but it is the other thing on screen
	-- whose size is a function of the display rather than of the config, and a
	-- UI scale change is exactly when its grain needs retiling.
	LayoutFrost()

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
	local hp1, pw1 = Palette:Stop(hp), Palette:Stop(pw)
	f.hpBlip:SetVertexColor(hp1[1], hp1[2], hp1[3], 1)
	f.pwBlip:SetVertexColor(pw1[1], pw1[2], pw1[3], 1)

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

	RestyleFrost()
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
-- CVars, borrowed and given back
--
-- Everything below writes into settings the player owns, which makes the
-- give-back the interesting half. Two rules, shared by the nameplate CVars and
-- the sound ones:
--
--   * A CVar that does not exist on this client is never written. Setting an
--     unknown CVar throws, and the names move between flavours.
--   * A CVar that no longer holds the value WE last wrote was changed by the
--     player, or by another addon, while zen was running. It is left alone.
--     Restoring it would be overwriting a deliberate change with a stale one -
--     which is the bug the whole "save the old value" pattern is famous for.
-- ---------------------------------------------------------------------------

local function CVarExists(name)
	if not GetCVar then return false end
	local ok, v = pcall(GetCVar, name)
	return ok and v ~= nil
end

local function CVarNumber(name)
	local ok, v = pcall(GetCVar, name)
	if not ok then return nil end
	return tonumber(v)
end

--- Numbers, because GetCVar hands back strings and the client is free to
--  normalise "0.05" into "0.050000". Comparing those as strings is a restore
--  that silently never fires.
local function SameValue(a, b)
	local na, nb = tonumber(a), tonumber(b)
	if na and nb then return math.abs(na - nb) < 0.0005 end
	return tostring(a) == tostring(b)
end

--- Ramped volumes are written in half-percent steps. Without this the ramp
--  writes a new value to four CVars ten times a second for the whole of a 2.5s
--  fade, all of them differing in the fourth decimal place, which nobody can
--  hear and the client has to write to disk on logout.
local function Step(v)
	return math.floor(v * 200 + 0.5) / 200
end

--- Record what we wrote alongside where it came from. `store[name].was` is the
--  player's value; `store[name].set` is ours, and is what the give-back checks.
local function Borrow(store, name, value)
	if not CVarExists(name) then return false end
	local entry = store[name]

	-- Handed back for good. The sound channels are re-borrowed on every tick of
	-- the ramp, so without this the check below would notice the player's change,
	-- overwrite it a tenth of a second later, and then "restore" our own stale
	-- value on the way out - which is the exact bug the check exists to prevent,
	-- reintroduced by the fact that it runs ten times a second.
	if entry and entry.released then return false end

	if not entry then
		local ok, was = pcall(GetCVar, name)
		if not ok then return false end
		entry = { was = was }
		store[name] = entry
	end

	if entry.set ~= nil then
		local ok, now = pcall(GetCVar, name)
		if ok and not SameValue(now, entry.set) then
			entry.released = true
			return false
		end
		if SameValue(entry.set, value) then return true end
	end

	-- ALREADY WHAT WE WANT, so touch nothing.
	--
	-- The client treats some CVars as experimental and asks the player to
	-- confirm every write to one - test_cameraOverShoulder fires
	-- EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED and Blizzard's own UIParent throws
	-- up a modal (Vanilla/UIParent.lua:932). Zen writes a real 0 there for
	-- CENTRE rather than skipping it, deliberately, so anyone running their own
	-- over-the-shoulder camera is centred - but for everyone whose shoulder is
	-- already 0 that is a dialog on the way in and another on the way out, for
	-- a write that changed nothing.
	--
	-- Recorded without `set`, so the give-back leaves it alone too.
	local same, current = pcall(GetCVar, name)
	if same and SameValue(current, value) then return true end

	if not pcall(SetCVar, name, value) then
		-- A refused write is not a borrow. Dropping the record means the give-back
		-- will not try to "restore" a value we never actually changed.
		if entry.set == nil then store[name] = nil end
		return false
	end
	entry.set = value
	return true
end

local function GiveBack(store)
	if not store then return end
	for name, entry in pairs(store) do
		local ok, now = pcall(GetCVar, name)
		if ok and not entry.released and entry.set ~= nil and SameValue(now, entry.set) then
			pcall(SetCVar, name, entry.was)
		end
	end
end

-- ---------------------------------------------------------------------------
-- nameplates
-- ---------------------------------------------------------------------------

--- Called with the readout's alpha, the same as DimUI. The plates go at the
--  BOTTOM of the fade, not throughout - see the note at the top for why they
--  are not dimmed on the way down.
function Zen:SetWorldText(a)
	local cfg = A.Config:Module("zen")
	if cfg.hideNameplates == false then
		self:RestoreWorldText()
		return
	end

	-- Combat is what makes the give-back urgent rather than tidy. Zen cannot
	-- start in combat, but it is very often *running* when combat starts, and the
	-- fader's wake drops this alpha on the very next tick - so plates are back
	-- within a tenth of a second of the first hit, before anything has had time
	-- to matter.
	--
	-- SetCVar itself is not a protected call and these names are read by the
	-- engine rather than by secure Lua, so writing them mid-lockdown is allowed;
	-- it is wrapped anyway, because "allowed" is a claim about this patch.
	if a <= 0.98 then
		if self._worldText then self:RestoreWorldText() end
		return
	end
	if self._worldText then return end

	local store = {}
	for _, name in ipairs(WORLD_TEXT_CVARS) do
		Borrow(store, name, "0")
	end
	-- Only remembered if something was actually borrowed, so a client with none
	-- of these names does not leave an empty table standing in for "we did this".
	if next(store) then self._worldText = store end
end

function Zen:RestoreWorldText()
	if not self._worldText then return end
	local store = self._worldText
	self._worldText = nil
	GiveBack(store)
end

-- ---------------------------------------------------------------------------
-- the audio profile
-- ---------------------------------------------------------------------------

--- The track the profile asks for. "random" resolves once per zen, not once per
--  tick, which is why the answer is cached on the module until the music stops.
function Zen:PickTrack()
	local cfg = A.Config:Module("zen")
	local want = cfg.track

	if want == "random" or want == nil then
		return Zen.TRACKS[math.random(#Zen.TRACKS)]
	end
	for _, t in ipairs(Zen.TRACKS) do
		if t.key == want then return t end
	end
	-- A key from a profile written against a track that no longer ships. The
	-- first track beats silence, and silence is what "return nil" would mean.
	return Zen.TRACKS[1]
end

--- True if the game is audible at all. Not a thing to work around: somebody who
--  has turned every sound off has said what they want.
local function SoundIsOn()
	if not GetCVar then return false end
	if CVarExists("Sound_EnableAllSound") and CVarNumber("Sound_EnableAllSound") == 0 then
		return false
	end
	local master = CVarNumber("Sound_MasterVolume")
	if master and master <= 0.001 then return false end
	return true
end

--- `a` is the readout's alpha again, so the room quietens at exactly the pace
--  the HUD leaves and comes back at the pace it returns.
function Zen:SetAudio(a)
	local cfg = A.Config:Module("zen")

	if cfg.audio == false or a <= 0.001 then
		self:RestoreAudio()
		return
	end

	if not self._audio then
		if not SoundIsOn() then return end
		self._audio = {}

		-- The music channel has to be switched on before PlayMusic will make a
		-- sound. Borrowed like everything else, so somebody who plays with music
		-- off gets it back the moment zen ends.
		Borrow(self._audio, "Sound_EnableMusic", "1")

		local track = self:PickTrack()
		self._track = track
		-- PlayMusic replaces whatever is on the channel, so an options-panel
		-- preview left running is already gone; the flag has to go with it or the
		-- next click on the preview button reads as "stop".
		self._preview = nil
		if track and PlayMusic then pcall(PlayMusic, track.file) end
	end

	local store = self._audio

	for _, ch in ipairs(DUCKED) do
		local was = store[ch.cvar] and tonumber(store[ch.cvar].was) or CVarNumber(ch.cvar)
		if was then
			local ratio = tonumber(cfg[ch.key]) or ch.default
			ratio = math.max(0, math.min(1, ratio))
			-- Interpolated by `a` rather than snapped to the ratio, so at the top
			-- of the fade the channel is exactly where the player left it and at
			-- the bottom it is exactly `was * ratio`.
			Borrow(store, ch.cvar, Step(was * (1 - a * (1 - ratio))))
		end
	end

	-- Music goes the other way: up to the floor, and only if it is under it.
	-- Ramped from where the player had it so the track arrives rather than
	-- starting at full.
	local floor = tonumber(cfg.musicFloor) or 0
	if floor > 0 then
		local was = store.Sound_MusicVolume and tonumber(store.Sound_MusicVolume.was)
			or CVarNumber("Sound_MusicVolume")
		if was and was < floor then
			Borrow(store, "Sound_MusicVolume", Step(was + (floor - was) * a))
		end
	end
end

function Zen:RestoreAudio()
	if not self._audio then return end
	local store = self._audio
	self._audio = nil
	self._track = nil

	if StopMusic then pcall(StopMusic) end
	GiveBack(store)
end

-- ---------------------------------------------------------------------------
-- the chair
--
-- `C_ChatInfo.PerformEmote` rather than `DoEmote`, which is deprecated on 1.15
-- and only exists at all when `loadDeprecationFallbacks` is on - so the fallback
-- is the other way round from usual: the modern call first, the old global only
-- if this client has not got the new one.
--
-- And rather than `SitStandOrDescendStart()`, which is what the keybind runs.
-- That one is a TOGGLE, so on a player who is already sitting it stands them up
-- - the exact opposite of the request, on the exact players most likely to be
-- idle enough to trigger zen. The emote is not a toggle: sit when sitting is
-- sitting.
--
-- Nothing here can ask whether the player is already sitting. Classic exposes no
-- such query, which is why "only stand up if we were the ones who sat them down"
-- is not on offer and standing up is unconditional.
-- ---------------------------------------------------------------------------

local function Emote(token)
	if C_ChatInfo and C_ChatInfo.PerformEmote then
		return pcall(C_ChatInfo.PerformEmote, token)
	end
	if DoEmote then return pcall(DoEmote, token) end
	return false
end

--- Every state in which sitting is impossible, refused, or simply wrong.
--
--  Checked rather than attempted. A refused emote puts a red error across the
--  middle of the screen, and a red error across the middle of a mode whose whole
--  purpose is a quiet screen is worse than not sitting.
local function CanSit()
	if InCombatLockdown() then return false end
	if IsMounted and IsMounted() then return false end
	if UnitOnTaxi and UnitOnTaxi("player") then return false end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
	return true
end

function Zen:SetSitting(a)
	local cfg = A.Config:Module("zen")
	if cfg.sit == false then
		self:StandUp()
		return
	end

	-- At the TOP of the fade rather than the bottom, unlike the plates and the
	-- audio. Those are things being taken away, and taking them away early means
	-- taking them away from somebody who has not gone yet. This is the opposite:
	-- it is the shot being set up, and watching the character settle while the
	-- HUD breathes out is the whole picture. At the bottom of the fade they would
	-- simply snap into a sitting pose on an already-still screen.
	if a < 0.02 then
		if self._sat then self:StandUp() end
		return
	end
	if self._sat then return end
	if not CanSit() then return end

	if Emote("SIT") then self._sat = true end
end

function Zen:StandUp()
	if not self._sat then return end
	self._sat = false
	-- Not gated on CanSit: if combat started, standing is exactly what we want,
	-- and standing while mounted or dead is a no-op rather than an error.
	Emote("STAND")
end

-- ---------------------------------------------------------------------------
-- the camera
--
-- Three metres back, tilted a little above the head.
--
-- Zoom is exact and reversible: GetCameraZoom() reads the current distance, so
-- the target is set by asking for the difference and the player's own distance
-- is put back the same way. One call each way rather than a per-tick ramp - each
-- CameraZoom call starts the client's own glide, and issuing a new one ten times
-- a second restarts that glide ten times a second, which is a camera that never
-- arrives.
--
-- Pitch is NOT TOUCHED AT ALL, and that is the answer rather than a limitation.
--
-- There is no getter for camera pitch on this client and no setter: the only
-- control is MoveViewUpStart/Stop, which is movement over TIME. This module
-- used that, and every version of it was wrong in a different way - the shot
-- landed somewhere different depending on where the player's camera already
-- was, the reversal was exact only while nothing clamped, and the rate turned
-- out to be `cameraPitchMoveSpeed`, a CVar the player's own Mouse Look Speed
-- slider writes anywhere between 45 and 135 degrees a second. A fixed duration
-- is a different angle for every player, so the same number that framed the
-- shot on one machine put the camera through the floor on another.
--
-- DialogueUI gets a consistent cinematic camera on this same client and calls
-- MoveView exactly zero times. It sets the zoom, which is absolute, readable
-- and restorable exactly - the whole property the timed nudge could never
-- have.
--
-- So zen's camera is zoom plus CVars, and there is no pitch setting. The shot
-- the deck describes - pulled back, character centred, looking out at the world
-- - is what that produces on its own. What the tilt was adding was the part
-- that kept breaking.
-- ---------------------------------------------------------------------------

function Zen:SetCamera(a)
	local cfg = A.Config:Module("zen")
	if cfg.camera == false then
		self:RestoreCamera()
		return
	end

	if a < 0.02 then
		if self._cam then self:RestoreCamera() end
		return
	end
	if self._cam then return end

	-- A taxi flies the camera itself, and a second addon fighting it for the
	-- same camera is how you get a spinning screen over the Barrens.
	if UnitOnTaxi and UnitOnTaxi("player") then return end
	if not GetCameraZoom or not CameraZoomIn or not CameraZoomOut then return end

	local ok, current = pcall(GetCameraZoom)
	if not ok or type(current) ~= "number" then return end

	local cam = { zoom = current, pitch = 0 }

	local goal = math.max(0, tonumber(cfg.cameraZoom) or 3)
	local diff = current - goal
	if math.abs(diff) > 0.05 then
		if diff > 0 then pcall(CameraZoomIn, diff) else pcall(CameraZoomOut, -diff) end
	end

	-- Every camera value zen touches goes through the same borrow/give-back, so
	-- it is handed back by the paths that already exist - including the
	-- PLAYER_LOGOUT one.
	cam.store = {}

	self._cam = cam
end

--- Put the camera back exactly as it was.
--
--  Every value zen touches is absolute and readable, so "exactly" is literal
--  here rather than a best effort: the zoom is measured with GetCameraZoom on
--  the way in and restored by the difference, and the CVars come back through
--  the same Borrow/GiveBack every other borrowed setting uses.
--
--  That is the whole argument for having no pitch. A timed nudge could only be
--  undone by running the same movement backwards for the same duration, which
--  is exact if nothing else moved the camera in between and wrong if anything
--  did - and moving the camera means moving the mouse, which is the fader's
--  most reliable wake signal.
function Zen:RestoreCamera()
	local cam = self._cam
	if not cam then return end
	self._cam = nil

	if cam.store then GiveBack(cam.store) end

	if cam.zoom and GetCameraZoom then
		local ok, now = pcall(GetCameraZoom)
		if ok and type(now) == "number" then
			local diff = now - cam.zoom
			if math.abs(diff) > 0.05 then
				if diff > 0 then pcall(CameraZoomIn, diff) else pcall(CameraZoomOut, -diff) end
			end
		end
	end
end

--- Hand back everything zen borrowed, whatever state it is in.
--
--  Deliberately not "and also park the readout": this is called from the logout
--  event, where there is no next frame to draw anything in and the only thing
--  that matters is that the client's own settings are the player's again.
function Zen:ReleaseAll()
	pcall(self.RestoreWorldText, self)
	pcall(self.RestoreAudio, self)
	-- The zoom is read back and put back exactly.
	pcall(self.RestoreCamera, self)
end

--- Play a track from the options panel, so somebody choosing one can hear it
--  without sitting out the zen timer. A second call stops it.
--
--  Deliberately does NOT duck anything or touch the music volume. A preview is a
--  question about which track, not a request to enter zen, and a preview that
--  quietly rearranged the sound options would be a trap.
function Zen:PreviewTrack(key)
	if self._preview then
		self._preview = nil
		if StopMusic then pcall(StopMusic) end
		return false
	end

	if not PlayMusic then return false end
	local track
	for _, t in ipairs(Zen.TRACKS) do
		if t.key == key then track = t break end
	end
	track = track or self:PickTrack()
	if not track then return false end

	self._preview = track.key
	local ok = pcall(PlayMusic, track.file)
	if not ok then self._preview = nil end
	return ok and track.name or false
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
	A:SetPropagate(k, true)

	k:SetScript("OnKeyDown", function(self)
		-- First line, every time, and never the widget method directly.
		--
		-- This used to say the client clears the propagation flag after every
		-- event, so setting it once at construction bought nothing. That is not
		-- true - the value persists - and believing it put a call that is
		-- PROTECTED IN COMBAT on the path of every key the player presses while
		-- zen is armed. A:SetPropagate keeps the same guarantee (propagation is
		-- on before Wake can raise anything) at the cost of nothing at all,
		-- because setting true when it is already true does not call through.
		A:SetPropagate(self, true)
		Wake()
	end)
	k:SetScript("OnKeyUp", function(self)
		A:SetPropagate(self, true)
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
	A:SetPropagate(self.keys, true)
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
		self:SetFrost(0)
		self:RestoreWorldText()
		self:RestoreAudio()
		self:RestoreCamera()
		self:StandUp()
		return
	end

	local cur  = f:GetAlpha()
	local want = self.want or 0
	local diff = want - cur

	if math.abs(diff) < 0.005 then
		f:SetAlpha(want)
		if want <= 0 then
			-- Parked. Put everything back first, then stop costing anything until
			-- the fader asks for us again. The music and the plates are released
			-- here rather than the moment the fader says "wake", so the track fades
			-- down with the readout instead of being cut off mid-breath.
			self:RestoreUI()
			self:SetFrost(0)
			self:RestoreWorldText()
			self:RestoreAudio()
			-- The camera and the chair go back HERE rather than the moment the
			-- fader said wake, so the shot unwinds with the readout instead of
			-- snapping the instant somebody twitches the mouse.
			self:RestoreCamera()
			self:StandUp()
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
	self:SetFrost(f:GetAlpha())
	self:DriftFrost(dt)
	self:SetWorldText(f:GetAlpha())
	self:SetAudio(f:GetAlpha())
	self:SetSitting(f:GetAlpha())
	self:SetCamera(f:GetAlpha())
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
	--
	-- The same argument now covers three more things that outlive an error: a
	-- full-screen pane nothing else will take down, a player with no nameplates
	-- for the rest of the session, and a meditation track looping over their
	-- raid. Each restore is its own pcall, so one of them failing cannot stop the
	-- others - which is the whole reason they are not a single call.
	pcall(self.RestoreUI, self)
	pcall(self.SetFrost, self, 0)
	pcall(self.RestoreWorldText, self)
	pcall(self.RestoreAudio, self)
	-- The camera one is not optional. Everything else on this list leaves the
	-- player with something wrong on screen; a half-finished pitch nudge leaves
	-- the camera ROTATING, and it does not stop until they reload.
	pcall(self.RestoreCamera, self)
	pcall(self.StandUp, self)
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
	if not self.frost then self.frost = BuildFrost() end
	self.frame:Show()
	self.want = 0
	self.frame:SetAlpha(0)
	self:RestoreUI()
	self:SetFrost(0)

	A:RegisterEvent(self, "ZONE_CHANGED", "UpdateText")
	A:RegisterEvent(self, "ZONE_CHANGED_INDOORS", "UpdateText")
	A:RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", "UpdateText")

	-- The one that matters most, and the one nothing else here would catch.
	--
	-- CVars are the client's, not ours: it writes every one of them to Config.wtf
	-- when the session ends. Logging out from inside zen without this makes the
	-- ducked volumes and the missing nameplates *permanent* - they are the values
	-- the game starts with next time, on every character, with no sign that this
	-- addon did it. Every other restore path in this module is about the next few
	-- seconds. This one is about the rest of somebody's account.
	A:RegisterEvent(self, "PLAYER_LOGOUT", "ReleaseAll")

	self:OnConfigChanged()
	if A.Fader then A.Fader:Refresh() end
end

function Zen:OnDisable()
	self:SetKeysEnabled(false)
	self.want = 0
	if self.frame then self.frame:SetAlpha(0) end
	self:RestoreUI()
	-- Switching the module off mid-zen has to hand back everything it borrowed,
	-- and this is the only place that runs. The ticker is unregistered two lines
	-- down, so there is no later pass to do it.
	self:SetFrost(0)
	self:RestoreWorldText()
	self:RestoreAudio()
	self:RestoreCamera()
	self:StandUp()
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
