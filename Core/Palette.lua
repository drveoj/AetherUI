--[[--------------------------------------------------------------------------
	AetherUI :: Palette

	Colour tokens for the two skins in the concept deck.

	Because every texture in Media\Textures is neutral greyscale, a skin is just a
	table of colours. Adding a third skin costs no art.

	Token vocabulary (kept deliberately small):
	  glass / glassEdge      the frosted surface and its rim
	  glassStrong            same surface when it must stay readable in combat
	  text / textDim         primary and secondary type
	  accent                 the skin's signature hue (xp bar, highlights)
	  health / power / rage / energy / focus
	  hostile / neutral / friendly
	  cast / castGlow        spell cast bar
	  danger                 in-combat markers
	  shadow                 ambient drop shadow
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Palette = {}
A.Palette = Palette

-- convenience: colours are {r, g, b, a} in 0..1
local function C(r, g, b, a)
	return { r / 255, g / 255, b / 255, a or 1 }
end

-- ---------------------------------------------------------------------------
-- skins
-- ---------------------------------------------------------------------------

Palette.skins = {

	-- 1b / 2a in the deck: dark arcane glass.
	midnight = {
		label       = "Midnight",

		glass       = C(12, 10, 28, 0.55),
		glassSoft   = C(12, 10, 28, 0.40),
		glassStrong = C(12, 10, 28, 0.68),
		glassEdge   = C(150, 130, 235, 0.32),
		glassEdgeHi = C(185, 164, 245, 0.55),
		shadow      = C(0, 0, 0, 0.50),

		text        = C(236, 230, 255, 1.00),
		textDim     = C(220, 210, 255, 0.55),
		textFaint   = C(220, 210, 255, 0.38),

		accent      = C(185, 154, 245, 1.00),
		accentDeep  = C(138, 106, 224, 1.00),

		health      = { C(159, 232, 180), C(95, 198, 134) },
		power       = { C(138, 180, 255), C(106, 144, 232) },
		rage        = { C(255, 154, 118), C(240, 110, 90)  },
		energy      = { C(255, 224, 130), C(232, 190, 80)  },
		focus       = { C(255, 180, 130), C(232, 140, 90)  },

		hostile     = C(255, 138, 138, 1.00),
		hostileBar  = { C(255, 154, 118), C(240, 110, 90) },
		neutral     = C(240, 180, 106, 1.00),
		friendly    = C(159, 232, 180, 1.00),
		targetGlass = C(24, 10, 20, 0.55),
		targetEdge  = C(255, 138, 138, 0.35),
		targetText  = C(255, 217, 196, 1.00),

		cast        = { C(142, 200, 255), C(212, 236, 255) },
		castEdge    = C(150, 200, 255, 0.45),
		castGlow    = C(140, 200, 255, 0.55),

		danger      = C(255, 138, 138, 1.00),
		xp          = { C(138, 106, 224), C(185, 154, 245) },

		-- Quest log (concept 3b). The level chip's five difficulty bands, the
		-- blue "Dungeon" tag, and the two list-row states.
		rowSel      = C(205, 188, 255, 0.20),
		rowHover    = C(150, 130, 235, 0.14),
		info        = C(164, 216, 245, 1.00),
		infoBg      = C(140, 200, 255, 0.13),
		infoEdge    = C(140, 200, 255, 0.30),
		questDiff = {
			impossible    = { text = C(255, 154, 138), bg = C(255, 120, 105, 0.16) },
			verydifficult = { text = C(255, 180, 106), bg = C(255, 160,  80, 0.15) },
			difficult     = { text = C(255, 232, 154), bg = C(255, 220, 120, 0.14) },
			standard      = { text = C(159, 232, 180), bg = C(120, 230, 160, 0.14) },
			trivial       = { text = C(168, 164, 184), bg = C(180, 176, 200, 0.12) },
		},

		-- Reward cards and the action footer. The filled button is the one place
		-- the deck asks for an OPAQUE accent with dark text on it, which is why
		-- it is its own token rather than `accent` at full alpha.
		cardBg      = C(255, 255, 255, 0.06),
		cardEdge    = C(150, 130, 235, 0.30),
		cardEdgeHi  = C(205, 188, 255, 0.70),
		btnFill     = C(205, 188, 255, 1.00),
		btnFillHi   = C(222, 212, 255, 1.00),
		btnFillText = C(20,   16,  31, 1.00),
		btnEdge     = C(150, 130, 235, 0.32),
		btnHover    = C(150, 130, 235, 0.14),
		dangerText  = C(255, 150, 140, 0.80),
		dangerEdge  = C(255, 138, 120, 0.30),
		dangerHover = C(255, 138, 120, 0.12),

		-- Bags. The bank is a second window of the same anatomy, told apart by a
		-- blue accent rather than by its shape. Modelled on the info/infoBg/
		-- infoEdge triple, which is already this skin's blue "tag" family --
		-- deliberately NOT on `cast`, whose #8ec8ff it shares to a digit, because
		-- cast means "a spell is going off" and would drag the bank with it the
		-- next time the cast bar is retuned.
		bankAccent  = C(142, 200, 255, 1.00),
		bankBg      = C(140, 200, 255, 0.16),
		bankEdge    = C(140, 200, 255, 0.34),

		-- Poor-quality items are dimmed rather than hidden: still there, still
		-- clickable, visibly not worth the space. junkTint is a VERTEX colour on
		-- the icon (there is no grayscale filter in this UI, so desaturation plus
		-- a grey multiply is the nearest thing), junkText is the section's ink.
		junkTint    = C(150, 150, 150, 0.42),
		junkText    = C(220, 210, 255, 0.38),

		-- Item quality rims, softer than Blizzard's. The deck tunes these to sit
		-- on a dark frosted panel rather than on Blizzard's opaque slate, so they
		-- are its numbers, not ITEM_QUALITY_COLORS'.
		--
		-- `edge` is the 1px rim; `glow` is the outer bloom, and only rare and
		-- above have one -- that is what makes a purple readable at a glance in a
		-- grid of eighty. nil glow means no bloom, which is not the same as a
		-- transparent one.
		itemQuality = {
			[0] = { edge = C(157, 157, 157, 0.55) },                                  -- poor
			[1] = { edge = C(255, 255, 255, 0.30) },                                  -- common
			[2] = { edge = C(111, 220, 127, 0.85) },                                  -- uncommon
			[3] = { edge = C(111, 168, 255, 0.90), glow = C(111, 168, 255, 0.35) },   -- rare
			[4] = { edge = C(180, 127, 255, 0.90), glow = C(180, 127, 255, 0.45) },   -- epic
			[5] = { edge = C(255, 168,  92, 0.90), glow = C(255, 168,  92, 0.45) },   -- legendary
		},

		-- Tooltips (concept 6a / 6b).
		--
		-- These get their own names rather than borrowing, for the same reason the
		-- bank triple above does. ttFriendly is #8ec8ff to a digit, which is also
		-- `cast[1]`; ttHostile and ttNeutral are within a shade of `hostile` and
		-- `neutral`. Aliasing them would mean the next time somebody retunes the
		-- cast bar for readability mid-pull, every friendly player's name in every
		-- tooltip moves with it. A tooltip name is answering a different question.
		--
		-- ttTitle, ttLore and ttElite are genuinely new: the deck's title ink is a
		-- half-step brighter than `text`, and neither gold exists anywhere else in
		-- this UI.
		ttTitle     = C(240, 236, 255, 1.00),   -- spell/item name
		ttLore      = C(232, 212, 154, 1.00),   -- spell body copy
		ttElite     = C(232, 200, 106, 1.00),   -- the ELITE chip and its rim
		ttEliteInk  = C( 20,  16,  31, 1.00),   -- dark text ON the gold chip
		ttGuild     = C(205, 188, 255, 0.80),   -- <Samophlange>
		ttFriendly  = C(142, 200, 255, 1.00),   -- a friendly player's name
		ttHostile   = C(240, 138, 122, 1.00),
		ttNeutral   = C(232, 200, 106, 1.00),
		ttFriendlyNPC = C(159, 224, 168, 1.00),
		-- The deck's health fill, which is a shade deeper than the HUD's `health`
		-- because it sits on a 7px hairline rather than on a 12px capsule and a
		-- pale green that thin reads as grey.
		ttHealth    = { C(127, 214, 138), C(74, 168, 88) },
		ttHealthBg  = C(255, 255, 255, 0.08),
		ttDivider   = C(150, 130, 235, 0.18),
		-- The level badge when the unit has no reaction worth colouring (your own
		-- pet, a friendly player). Reaction badges tint from the name colour at
		-- .15 bg / .40 edge, which is the deck's recipe rather than a token.
		-- The level badge when the unit is a PLAYER. Screen 6a is explicit about
		-- this and it is easy to miss: the anchored player card's badge is the
		-- skin's own purple - bg .18, rim .35, number #cdbcff - while only the
		-- three NPC variants tint theirs from the reaction. It reads correctly
		-- once you see why: a player's reaction is nearly always friendly, so
		-- tinting the badge by it says nothing and costs the card its accent.
		ttBadgeBg   = C(150, 130, 235, 0.18),
		ttBadgeEdge = C(150, 130, 235, 0.35),
		ttBadgeInk  = C(205, 188, 255, 1.00),

		-- An item title's INK, which is not the same value as its rim.
		--
		-- The first pass reused itemQuality[q].edge for both, which is right on
		-- this skin and wrong on Daylight: those numbers are deliberately dark
		-- there, because a rim on a pale panel has to be. Reused as text they put
		-- a near-black item name on a pale wash while every other string in the
		-- tooltip stayed white. A rim is read as a shape and ink is read as
		-- letters; they want different contrast, so they get different tokens.
		--
		-- These are the deck's own scale: #9d9d9d, white at .90, #6fdc7f, #6fa8ff,
		-- #b47fff, plus a legendary the deck does not draw.
		ttQuality = {
			[0] = C(157, 157, 157, 1.00),
			[1] = C(255, 255, 255, 0.90),
			[2] = C(111, 220, 127, 1.00),
			[3] = C(111, 168, 255, 1.00),
			[4] = C(180, 127, 255, 1.00),
			[5] = C(255, 168,  92, 1.00),
		},

		-- A modal is the one surface that must NOT be glass. Frosted-on-frosted
		-- over a lit world is unreadable, and a confirmation nobody can read is
		-- worse than no confirmation. Near-opaque, with a scrim behind it.
		--
		-- Dark in both skins, deliberately: the deck dims the world behind the
		-- window in both, and a dark modal over a light UI is the normal reading.
		-- It also means the light button text works unchanged on either skin.
		dialogFill  = C(14, 11, 32, 0.97),
		scrim       = C(0, 0, 0, 0.45),
	},

	-- 1a in the deck: warm light glass, sits better over Classic's palette.
	--
	-- Two failed attempts are worth writing down, because both looked reasonable
	-- on paper and neither survived a screenshot:
	--
	--   fill 0.17, white text   the deck's own values. But the deck has a 38px
	--                           backdrop blur under the panel and we have none,
	--                           so over real terrain the fill did nothing at all
	--                           and the text floated on the world with no surface
	--                           under it.
	--   fill 0.72, dark ink     a genuine light theme. Legible, and horrible: a
	--                           bright slab in the corner of a warm desert. Worse,
	--                           WoW's OUTLINE flag is always BLACK, so every role
	--                           carrying it - the level orb, stack counts, keybinds
	--                           - drew dark text inside a black rim on white.
	--
	-- What was actually wrong with the first one was not the fill, it was the
	-- EDGE. A panel reads as a panel because it has a boundary. So the rim goes
	-- to 0.85 and the drop shadow to 0.65, the fill lifts only as far as 0.30,
	-- and the text stays white - which keeps every OUTLINE role, every class
	-- colour and every difficulty colour working exactly as they do on Midnight.
	daylight = {
		label       = "Daylight",

		glass       = C(252, 246, 236, 0.30),
		glassSoft   = C(252, 246, 236, 0.22),
		glassStrong = C(252, 246, 236, 0.40),
		-- The rim is doing the work here, not the fill. Nearly solid.
		glassEdge   = C(255, 252, 244, 0.85),
		glassEdgeHi = C(255, 255, 255, 0.98),
		-- And the shadow is what lifts a pale panel off pale ground.
		shadow      = C(24, 12, 0, 0.65),

		text        = C(255, 255, 255, 1.00),
		textDim     = C(255, 255, 255, 0.62),
		textFaint   = C(255, 255, 255, 0.42),

		accent      = C(255, 235, 190, 0.95),
		accentDeep  = C(232, 200, 150, 1.00),

		health      = { C(159, 232, 180), C(111, 214, 150) },
		power       = { C(168, 204, 245), C(127, 176, 236) },
		rage        = { C(255, 154, 118), C(240, 110, 90)  },
		energy      = { C(255, 230, 150), C(240, 200, 96)  },
		focus       = { C(255, 190, 140), C(240, 150, 100) },

		hostile     = C(255, 154, 118, 1.00),
		hostileBar  = { C(255, 154, 118), C(240, 110, 90) },
		neutral     = C(240, 190, 120, 1.00),
		friendly    = C(159, 232, 180, 1.00),
		targetGlass = C(252, 246, 236, 0.30),
		targetEdge  = C(255, 255, 255, 0.55),
		targetText  = C(255, 255, 255, 1.00),

		cast        = { C(142, 200, 255), C(212, 236, 255) },
		castEdge    = C(180, 220, 255, 0.50),
		castGlow    = C(160, 210, 255, 0.45),

		danger      = C(255, 138, 138, 1.00),
		xp          = { C(185, 138, 224), C(217, 184, 240) },

		-- Quest log. Chips carry their own light backgrounds with dark text on
		-- them, which is the deck's own treatment and works against either skin.
		rowSel      = C(255, 252, 245, 0.30),
		rowHover    = C(255, 252, 245, 0.20),
		info        = C(18, 56, 78, 1.00),
		infoBg      = C(190, 228, 255, 0.85),
		infoEdge    = C(255, 255, 255, 0.45),
		questDiff = {
			impossible    = { text = C(110, 26, 16), bg = C(255, 185, 165, 0.92) },
			verydifficult = { text = C(110, 58,  8), bg = C(255, 212, 155, 0.92) },
			difficult     = { text = C( 94, 74,  8), bg = C(255, 238, 175, 0.92) },
			standard      = { text = C( 20, 80, 42), bg = C(185, 240, 200, 0.92) },
			trivial       = { text = C( 74, 70, 80), bg = C(228, 226, 235, 0.88) },
		},

		cardBg      = C(255, 252, 245, 0.16),
		cardEdge    = C(255, 255, 255, 0.40),
		cardEdgeHi  = C(255, 255, 255, 0.80),
		btnFill     = C(255, 252, 245, 0.92),
		btnFillHi   = C(255, 255, 255, 1.00),
		btnFillText = C( 42,  36,  24, 1.00),
		btnEdge     = C(255, 255, 255, 0.45),
		btnHover    = C(255, 252, 245, 0.20),
		dangerText  = C(255, 212, 200, 1.00),
		dangerEdge  = C(255, 180, 160, 0.55),
		dangerHover = C(255, 160, 140, 0.18),

		-- Bags. Same triple as info/infoBg/infoEdge above: on a pale panel the
		-- blue has to be the INK and the fill has to be near-solid, or the chip
		-- reads as a smudge.
		bankAccent  = C( 18,  56,  78, 1.00),
		bankBg      = C(190, 228, 255, 0.85),
		bankEdge    = C(255, 255, 255, 0.45),

		junkTint    = C(120, 116, 112, 0.45),
		junkText    = C(255, 255, 255, 0.42),

		-- Deepened against a pale fill. The hues are the deck's; the values are
		-- not, because a light green rim on a near-white panel is not a rim.
		itemQuality = {
			[0] = { edge = C(120, 120, 120, 0.60) },
			[1] = { edge = C( 90,  86,  80, 0.35) },
			[2] = { edge = C( 34, 148,  62, 0.90) },
			[3] = { edge = C( 30, 108, 208, 0.95), glow = C( 60, 140, 232, 0.30) },
			[4] = { edge = C(124,  56, 208, 0.95), glow = C(150,  90, 232, 0.38) },
			[5] = { edge = C(206, 108,  16, 0.95), glow = C(232, 148,  56, 0.38) },
		},

		-- Tooltips. Light type again, for the reason the header of this skin gives:
		-- the rim and the shadow make the panel, the fill does not, so the ink can
		-- stay white and every OUTLINE role keeps working.
		--
		-- The two golds are the exception and they move. Daylight's fill is a warm
		-- pale wash, and #e8d49a lore gold on it is a cream note on a cream field -
		-- the body copy stops being distinguishable from the labels above it, which
		-- is the one job that colour has. Both are pulled down and saturated until
		-- they read as gold ON something rather than as part of it.
		ttTitle     = C(255, 255, 255, 1.00),
		ttLore      = C(255, 232, 176, 1.00),
		ttElite     = C(255, 214, 120, 1.00),
		ttEliteInk  = C( 58,  42,  10, 1.00),
		ttGuild     = C(255, 252, 245, 0.80),
		ttFriendly  = C(190, 228, 255, 1.00),
		ttHostile   = C(255, 154, 118, 1.00),
		ttNeutral   = C(255, 214, 120, 1.00),
		ttFriendlyNPC = C(159, 232, 180, 1.00),
		ttHealth    = { C(159, 232, 180), C(111, 214, 150) },
		ttHealthBg  = C(255, 255, 255, 0.16),
		ttDivider   = C(255, 255, 255, 0.30),
		ttBadgeBg   = C(255, 252, 245, 0.22),
		ttBadgeEdge = C(255, 255, 255, 0.55),
		ttBadgeInk  = C(255, 255, 255, 1.00),

		-- Item title ink. Lifted well clear of this skin's itemQuality RIMS, which
		-- are dark on purpose - see the note beside the Midnight set. Poor and
		-- common in particular have to stay legible as light type on a pale fill,
		-- so they go to a dimmed white rather than to a grey.
		ttQuality = {
			[0] = C(230, 228, 235, 0.60),
			[1] = C(255, 255, 255, 0.92),
			[2] = C(150, 255, 170, 1.00),
			[3] = C(160, 205, 255, 1.00),
			[4] = C(212, 175, 255, 1.00),
			[5] = C(255, 200, 140, 1.00),
		},

		-- The modal stays dark on both skins. It sits over the chrome rather than
		-- over the world, and the light button text works unchanged on either.
		dialogFill  = C(28, 22, 12, 0.96),
		scrim       = C(20, 12, 0, 0.40),
	},
}

-- The live skin. Modules read A.Palette.c.<token>.
Palette.c = Palette.skins.midnight
Palette.current = "midnight"

function Palette:Apply(name)
	local skin = Palette.skins[name] or Palette.skins.midnight
	Palette.c = skin
	Palette.current = Palette.skins[name] and name or "midnight"
	return skin
end

function Palette:List()
	local out = {}
	for k, v in pairs(Palette.skins) do out[#out + 1] = { key = k, label = v.label } end
	table.sort(out, function(a, b) return a.key < b.key end)
	return out
end

--- The fill for a surface you READ from, as opposed to one you operate.
--
--  Two kinds of panel live on this HUD and they want different opacities:
--
--    control surfaces   action bars, unit capsules, the dock. Glanced at, not
--                       read. They stay translucent so the world shows through
--                       and the HUD keeps breathing.
--    reading surfaces   chat and the quest log. Paragraphs of small text over
--                       moving, high-contrast scenery. At the control-surface
--                       opacity the clutter behind competes with every glyph.
--
--  Chat has had this treatment since the start and it is the reason chat reads
--  comfortably where the quest log did not. Shared rather than duplicated so
--  the two cannot drift, and so there is one number to tune.
--
--  The boost closes a fixed FRACTION OF THE REMAINING TRANSPARENCY rather than
--  adding a constant. Two earlier formulations were wrong for instructive
--  reasons: a flat +0.14 is +21% on a 0.68 base and +58% on a 0.24 one, so the
--  two skins disagreed visibly; and a x1.2 multiplier overshoots into fully
--  opaque once the base is already high, so it clamps and they disagree again.
--  A fraction of the gap cannot overshoot and behaves the same at any base.
--  The fraction is `profile.glass.readOpacity`, a user setting rather than a
--  constant: how much background clutter a person can comfortably read through
--  is a matter of eyesight and taste. `readBoost` is only the fallback for the
--  window before the database exists.
Palette.readBoost = 0.35

function Palette:ReadingFill(skin)
	local c = skin or Palette.c
	local base = c.glassStrong or c.glass
	local a = base[4] or 1

	local boost = Palette.readBoost
	local cfg = A.db and A.db.profile and A.db.profile.glass
	if cfg and type(cfg.readOpacity) == "number" then boost = cfg.readOpacity end
	if boost < 0 then boost = 0 elseif boost > 1 then boost = 1 end

	return { base[1], base[2], base[3], a + (1 - a) * boost }
end

--- A token as the six hex digits an inline `|cff` escape wants.
--
--  Everything else in this UI colours a *region*, with SetVertexColor or
--  SetTextColor, and a region can be re-coloured later. A chat line cannot: it
--  is one FontString holding text that was already assembled, so any colour
--  inside it has to be written into the string at the moment it is built and
--  lives there for as long as the line is on screen. That is the whole reason
--  this exists, and the reason a skin change cannot restyle the lines already
--  in the log.
--
--  Alpha is dropped rather than packed into the leading two digits. `|caarrggbb`
--  does take one, but a chat line is drawn over the world at whatever alpha the
--  frame is set to, so a per-run alpha only ever fights the fader.
function Palette:Hex(color)
	if type(color) ~= "table" then return "ffffff" end
	local function b(v) return math.floor(math.min(math.max(v or 0, 0), 1) * 255 + 0.5) end
	return string.format("%02x%02x%02x", b(color[1]), b(color[2]), b(color[3]))
end

-- ---------------------------------------------------------------------------
-- dynamic colours
-- ---------------------------------------------------------------------------

local function Mix(a, b, t)
	return a + (b - a) * t
end

--- Colour for the portrait orb, which is a different problem from a bar.
--
--  A bar is read by *length*, so it can be as bright as it likes. The orb has a
--  white level number sitting on top of it, so it has to stay dark enough to
--  carry that text. Feeding it the health colour meant Mage, Hunter, Rogue and
--  Priest orbs came out near-white with an invisible number on them.
--
--  The concept's orb is a muted mid-to-dark disc (#7fb3e8 -> #4a5fa8), so that
--  is what this reproduces: pull the hue down toward a dark, slightly blue-
--  shifted base rather than up toward white.
--- A player's class colour, or nil.
--
--  CUSTOM_CLASS_COLORS FIRST, which is what a colour-blind or ClassColors addon
--  publishes. Modules/Chat.lua already did this and the other two places did
--  not, so somebody running one of those got recoloured names in chat and
--  Blizzard's palette everywhere else - the kind of inconsistency that reads as
--  a bug in whichever half you noticed second.
function Palette:ClassColor(unit)
	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
	local _, class = UnitClass(unit)
	if type(class) ~= "string" then return nil end
	local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
	local cc = colors and colors[class]
	if not cc or not cc.r then return nil end
	return { cc.r, cc.g, cc.b, 1 }
end

function Palette:OrbColor(unit)
	local base
	do
		local cc = Palette:ClassColor(unit)
		if cc then base = { cc[1], cc[2], cc[3] } end
	end

	if not base then
		local c = Palette.c
		local reaction = unit and UnitExists(unit) and UnitReaction(unit, "player")
		if reaction and reaction <= 3 then
			base = { c.neutral[1], c.neutral[2], c.neutral[3] }
		elseif reaction and reaction == 4 then
			base = { c.neutral[1], c.neutral[2], c.neutral[3] }
		else
			base = { c.accent[1], c.accent[2], c.accent[3] }
		end
	end

	return {
		{ base[1] * 0.62 + 0.05, base[2] * 0.62 + 0.05, base[3] * 0.62 + 0.07 },
		{ base[1] * 0.30 + 0.02, base[2] * 0.30 + 0.02, base[3] * 0.30 + 0.06 },
	}
end

--- Power bar colour for a unit, as a {from, to} gradient pair.
local POWER_TOKEN = {
	MANA = "power", RAGE = "rage", ENERGY = "energy", FOCUS = "focus",
	RUNIC_POWER = "power", COMBO_POINTS = "energy",
}

function Palette:PowerColor(unit)
	local c = Palette.c
	if not unit or not UnitExists(unit) then return c.power end
	local _, token = UnitPowerType(unit)
	return c[POWER_TOKEN[token or "MANA"] or "power"] or c.power
end

--- Health bar colour: class colour for players, reaction-tinted for everything else.
function Palette:HealthColor(unit)
	local c = Palette.c
	if not unit or not UnitExists(unit) then return c.health end

	local classColor = not A.db or A.db.profile.classColorHealth ~= false
	if classColor and UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if cc then
			-- Two stops either side of the class colour: a modestly lifted head and
			-- a darkened tail. The first pass lifted the head by 1.25x + 0.10,
			-- which drove the pale classes (Hunter, Mage, Rogue, Priest) to within
			-- a hair of white and made the bar read as cream rather than as the
			-- class. Keep the lift small enough that the hue survives.
			--
			return {
				{ Mix(cc.r, 1, 0.18), Mix(cc.g, 1, 0.18), Mix(cc.b, 1, 0.18) },
				{ cc.r * 0.70, cc.g * 0.70, cc.b * 0.70 },
			}
		end
	end

	if UnitIsDeadOrGhost(unit) then
		return { { 0.35, 0.35, 0.40 }, { 0.22, 0.22, 0.26 } }
	end

	local reaction = UnitReaction(unit, "player")
	if reaction then
		if reaction <= 3 then return c.hostileBar end
		if reaction == 4 then return { c.neutral, c.neutral } end
	end
	return c.health
end

--- Rim colour that follows the target's reaction, used on the target capsule.
function Palette:ReactionEdge(unit)
	local c = Palette.c
	-- Your own frame is never "a reaction". Without this the orb ring picked up
	-- friendly green off UnitReaction("player", "player"), which is true and
	-- useless: reaction is information about somebody else.
	if not unit or unit == "player" or not UnitExists(unit) then return c.glassEdge end
	local reaction = UnitReaction(unit, "player")
	-- Built from the reaction tokens rather than from `targetEdge`, which was a
	-- flat red on midnight and a flat *white* on daylight - so on one of the two
	-- skins the rim carried no reaction information at all. Stronger than it was,
	-- too: at 0.35 the difference between your capsule and your target's was
	-- there if you went looking for it, which is not the same as being able to
	-- tell them apart mid-fight.
	if reaction and reaction <= 3 then
		return { c.hostile[1], c.hostile[2], c.hostile[3], 0.55 }
	end
	if reaction == 4 then return { c.neutral[1], c.neutral[2], c.neutral[3], 0.45 } end
	return { c.friendly[1], c.friendly[2], c.friendly[3], 0.40 }
end

--- What a cast bar should be coloured for whoever is casting.
--
--  Your own casts keep the concept's blue. Anyone else's take their reaction.
--  The question you actually have to answer mid-fight is "is that bar mine or
--  theirs", and two identically blue capsules stacked one above the other do not
--  answer it - which is the whole reason this exists.
function Palette:CastColor(unit)
	local c = Palette.c
	if not unit or unit == "player" or not UnitExists(unit) then return c.cast end
	local reaction = UnitReaction(unit, "player")
	if reaction then
		if reaction <= 3 then return c.hostileBar end
		if reaction == 4 then return { c.neutral, c.neutral } end
	end
	return c.cast
end

--- The rim and the icon ring that go with it.
function Palette:CastEdge(unit)
	local c = Palette.c
	if not unit or unit == "player" or not UnitExists(unit) then return c.castEdge end
	local reaction = UnitReaction(unit, "player")
	if reaction then
		if reaction <= 3 then return { c.hostile[1], c.hostile[2], c.hostile[3], 0.60 } end
		if reaction == 4 then return { c.neutral[1], c.neutral[2], c.neutral[3], 0.55 } end
	end
	return { c.friendly[1], c.friendly[2], c.friendly[3], 0.50 }
end
