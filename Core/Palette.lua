--[[--------------------------------------------------------------------------
	AetherUI :: Palette

	Colour tokens for the skin family: Midnight, Dawn, Noon and Dusk.

	Because every texture in Media\Textures is neutral greyscale, a skin is just a
	table of colours. Adding one costs no art - and now costs eight values, not
	eighty-six: see the note over CHROME for what a skin is allowed to be.

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

--- The same, for a colour the CLIENT states in 0..1 already.
--
--  Debuff schools and zone types are Blizzard's numbers, and they have to
--  match the ones the rest of the game draws to the digit. Rounding them
--  through a byte to fit the constructor above would move every one of them
--  by a fraction, for tidiness and nothing else.
local function F(r, g, b, a)
	return { r, g, b, a or 1 }
end

-- ---------------------------------------------------------------------------
-- skins
--
-- A SKIN IS ONE TOKEN REMAP, and the brief that named the family is binding
-- about what that means: components never change geometry, size, opacity, blur,
-- shadow or layout between skins, and BRIGHTNESS LIVES IN THE HUE, NEVER THE
-- VALUE. The glass stays dark in all four. A white-chrome "Daylight" was tried
-- and rejected for flipping value, which is jarring in a game you are looking
-- past the interface to play.
--
-- This file used to be two hand-written tables of eighty-six colours each, and
-- eighty-one of the eighty-six differed - including health green, power blue,
-- the difficulty scale, the reaction tints and every IFEC channel tint, all of
-- which the brief says NEVER change. That is not a skin, it is a second
-- interface, and it is a fair part of why Daylight read as wrong.
--
-- So there are three kinds of colour here and only the first is a skin's to
-- choose:
--
--   CHROME     what the skin IS. Eight values.
--   SEMANTIC   what a colour MEANS - health, danger, a channel, a quality.
--              Identical in every skin, so it lives once and cannot drift.
--   DERIVED    mechanically, from chrome. Alphas of the surface, the rim at its
--              various weights, the type, the button that is a filled accent.
--
-- Adding a token is now one line in one place instead of four, which is the
-- whole point: with two skins a forgotten one was a bug, with four it is a
-- certainty.
-- ---------------------------------------------------------------------------

--- The eight a skin actually chooses.
--
--  Six are the brief's own table; `disc` and `soft` are the two derivations it
--  specifies PER SKIN rather than as a formula - the near-black in the skin's
--  hue that the dial sits on, and the tinted white its secondary type is drawn
--  in. Deriving either by mixing looked close and was not, and a colour that is
--  nearly right is worse than one that is written down.
local CHROME = {
	midnight = {
		label  = "Midnight",
		accent = C(205, 188, 255),   -- #cdbcff
		deep   = C(185, 164, 245),   -- #b9a4f5
		bg     = C( 14,  11,  32),   -- #0e0b20
		border = C(150, 130, 235),   -- #9682eb
		bright = C(240, 236, 255),   -- #f0ecff
		track  = C(255, 255, 255),
		disc   = C( 21,  17,  41),   -- #151129
		soft   = C(220, 210, 255),
	gold   = C(240, 217, 168),   -- #f0d9a8, the reserved gold
	goldDim= C(232, 200, 106),   -- #e8c86a, its companion tint
	},

	dawn = {
		label  = "Dawn",
		accent = C(245, 203, 170),   -- #f5cbaa
		deep   = C(232, 164, 130),   -- #e8a482
		bg     = C( 34,  18,  16),
		border = C(240, 180, 150),
		bright = C(255, 245, 238),   -- #fff5ee
		track  = C(255, 235, 224),
		disc   = C( 36,  17,  16),   -- #241110
		soft   = C(255, 224, 208),
	gold   = C(240, 217, 168),
	goldDim= C(232, 200, 106),
	},

	noon = {
		label  = "Noon",
		accent = C(207, 234, 250),   -- #cfeafa
		deep   = C(142, 196, 232),   -- #8ec4e8
		bg     = C( 14,  24,  34),
		border = C(150, 200, 235),
		bright = C(244, 250, 254),   -- #f4fafe
		track  = C(225, 242, 252),
		disc   = C( 13,  22,  32),   -- #0d1620
		soft   = C(214, 236, 250),
	gold   = C(240, 217, 168),
	goldDim= C(232, 200, 106),
	},

	dusk = {
		label  = "Dusk",
		accent = C(240, 217, 168),   -- #f0d9a8
		deep   = C(232, 200, 106),   -- #e8c86a
		bg     = C( 30,  22,  12),
		border = C(232, 200, 106),
		bright = C(255, 248, 236),   -- #fff8ec
		track  = C(255, 244, 220),
		disc   = C( 33,  24,   9),   -- #211809
		soft   = C(250, 232, 200),
	gold   = C(255, 207, 102),   -- #ffcf66, THE ONE REMAP
	goldDim= C(255, 207, 102),
	},
}

--- The same colour at another alpha. Every derived token is one of these.
local function A_(c, a) return { c[1], c[2], c[3], a } end

--- What a colour MEANS. The brief's list, and everything else that answers a
--  question about the game rather than about the skin: how hurt something is,
--  how hard it is, what kind of thing is playing, whether you may sell it.
--
--  ONE COPY. A skin cannot reach these, which is the point - the rejected skin
--  moved health green and the power blue and nothing anywhere said no.
local SEMANTIC = {
	shadow = C(0, 0, 0, 0.50),
	scrim  = C(0, 0, 0, 0.45),

	-- bars
	health = { C(159, 232, 180), C( 95, 198, 134) },
	power  = { C(138, 180, 255), C(106, 144, 232) },
	rage   = { C(255, 154, 118), C(240, 110,  90) },
	energy = { C(255, 224, 130), C(232, 190,  80) },
	focus  = { C(255, 180, 130), C(232, 140,  90) },
	hostileBar = { C(255, 154, 118), C(240, 110,  90) },
	cast   = { C(142, 200, 255), C(212, 236, 255) },
	xp     = { C(138, 106, 224), C(185, 154, 245) },

	-- reactions
	hostile  = C(255, 138, 138),
	neutral  = C(240, 180, 106),
	friendly = C(159, 232, 180),
	danger   = C(255, 138, 138),

	-- the target capsule reads as the thing it is pointed at
	targetGlass = C( 24,  10,  20, 0.55),
	targetEdge  = C(255, 138, 138, 0.35),
	targetText  = C(255, 217, 196),

	castEdge = C(150, 200, 255, 0.45),
	castGlow = C(140, 200, 255, 0.55),

	-- messages
	info     = C(164, 216, 245),
	infoBg   = C(140, 200, 255, 0.13),
	infoEdge = C(140, 200, 255, 0.30),
	dangerText  = C(255, 150, 140, 0.80),
	dangerEdge  = C(255, 138, 120, 0.30),
	dangerHover = C(255, 138, 120, 0.12),

	-- the bank, which is a blue place
	bankAccent = C(142, 200, 255),
	bankBg     = C(140, 200, 255, 0.16),
	bankEdge   = C(140, 200, 255, 0.34),

	-- The grey a chat line is dimmed to. Its own token rather than a tinted white
	-- at low alpha, because a chat escape cannot carry alpha - Hex drops it - so
	-- textFaint would come back out at full strength and not be faint at all.
	dim = C(136, 136, 136),

	-- Debuff schools, so "Chilled" reads as frost rather than as generic
	-- red. The client's own numbers: an aura ring that disagreed with the
	-- rest of the game about what a curse looks like would be worse than no
	-- ring at all.
	debuffSchool = {
		Magic   = F(0.55, 0.78, 1.00),
		Curse   = F(0.70, 0.50, 1.00),
		Disease = F(0.70, 0.60, 0.35),
		Poison  = F(0.55, 0.85, 0.45),
	},

	-- And zone type, likewise - a contested zone reads the same amber here
	-- as it does on the world map.
	zonePvP = {
		sanctuary = F(0.41, 0.80, 0.94),
		arena     = F(1.00, 0.10, 0.10),
		friendly  = F(0.10, 1.00, 0.10),
		hostile   = F(1.00, 0.10, 0.10),
		contested = F(1.00, 0.70, 0.00),
		combat    = F(1.00, 0.10, 0.10),
	},

	-- What a button says about itself when it cannot be pressed. Near enough
	-- Blizzard's own two - it desaturates and dims the same way - so a bar
	-- of ours next to one of theirs does not argue about what unusable
	-- looks like.
	iconNoMana   = F(0.45, 0.55, 1.00),
	iconUnusable = F(0.40, 0.40, 0.40),

	-- Money is gold, and it is gold in every skin. A purse that went rose on
	-- Dawn would be reading as a warning.
	money = F(0.90, 0.76, 0.42),

	talentOpen = C(159, 232, 180),
	talentFull = C(255, 226, 150),
	junkTint   = C(150, 150, 150, 0.42),

	-- the in-flight console: three channels and a brass rim. The LANDING
	-- gold is not here - it is the reserved semantic gold, and that one is
	-- the single colour a skin may reach. See semanticGold in Compose.
	ifecMusic   = C(159, 212, 200),
	ifecGossip  = C(232, 200, 106),
	ifecPodcast = C(240, 160, 106),
	ifecBrass   = C(200, 168, 106, 0.55),

	-- a hunter's pet has a mood, and it means the same thing in every skin
	petHappy   = C(142, 214, 158),
	petContent = C(232, 200, 106),
	petUnhappy = C(232, 122, 122),

	-- tooltips: what a thing IS
	ttLore        = C(232, 212, 154),
	ttElite       = C(232, 200, 106),
	ttFriendly    = C(142, 200, 255),
	ttHostile     = C(240, 138, 122),
	ttNeutral     = C(232, 200, 106),
	ttFriendlyNPC = C(159, 224, 168),
	npRare        = C(205, 216, 232),
	npChipInk     = C(191, 227, 255),

	-- quest difficulty, and the same scale on a tooltip
	-- A quest's difficulty, as a row tint and the ink on it. Two colours per
	-- step and not one: the tint is a wash behind a whole row and the text has
	-- to stay legible on it, which is not the same colour at another alpha.
	questDiff = {
		impossible    = { text = C(255, 154, 138), bg = C(255, 120, 105, 0.16) },
		verydifficult = { text = C(255, 180, 106), bg = C(255, 160,  80, 0.15) },
		difficult     = { text = C(255, 232, 154), bg = C(255, 220, 120, 0.14) },
		standard      = { text = C(159, 232, 180), bg = C(120, 230, 160, 0.14) },
		trivial       = { text = C(168, 164, 184), bg = C(180, 176, 200, 0.12) },
	},

	-- item quality, which is Blizzard's scale and nobody's to restyle
	itemQuality = {
		[0] = { edge = C(157, 157, 157, 0.55) },
		[1] = { edge = C(255, 255, 255, 0.30) },
		[2] = { edge = C(111, 220, 127, 0.85) },
		[3] = { edge = C(111, 168, 255, 0.90), glow = C(111, 168, 255, 0.35) },
		[4] = { edge = C(180, 127, 255, 0.90), glow = C(180, 127, 255, 0.45) },
		[5] = { edge = C(255, 168,  92, 0.90), glow = C(255, 168,  92, 0.45) },
	},
	ttQuality = {
		[0] = C(157, 157, 157),
		[1] = C(255, 255, 255, 0.90),
		[2] = C(111, 220, 127),
		[3] = C(111, 168, 255),
		[4] = C(180, 127, 255),
		[5] = C(255, 168,  92),
	},
	ttHealth = { C(127, 214, 138), C( 74, 168,  88) },
}

--- Everything else, from the eight.
--
--  MECHANICAL ON PURPOSE. Every line here is the skin's own colour at another
--  alpha, and that is the whole reason four skins cost four rows rather than
--  four files: there is nothing in this function that can be got wrong for one
--  skin and right for the others.
local function Compose(name, k)
	local c = {
		label = k.label,

		-- the frosted surface, at the three weights it is used at
		glass       = A_(k.bg, 0.55),
		glassSoft   = A_(k.bg, 0.40),
		glassStrong = A_(k.bg, 0.68),
		dialogFill  = A_(k.bg, 0.97),

		-- its rim, bright and ordinary
		glassEdge   = A_(k.border, 0.32),
		glassEdgeHi = A_(k.deep, 0.55),

		-- type
		text      = A_(k.bright, 1),
		textDim   = A_(k.soft, 0.55),
		textFaint = A_(k.soft, 0.38),
		junkText  = A_(k.soft, 0.38),
		ttTitle   = A_(k.bright, 1),

		accent     = A_(k.accent, 1),
		accentDeep = A_(k.deep, 1),

		-- rows and cards: the rim again, quieter, and the accent for what is on
		rowSel     = A_(k.accent, 0.20),
		rowHover   = A_(k.border, 0.14),
		cardBg     = A_(k.track, 0.06),
		cardEdge   = A_(k.border, 0.30),
		cardEdgeHi = A_(k.accent, 0.70),

		-- a filled button is the accent with the skin's own near-black on it,
		-- which is the one inversion this interface makes
		btnFill     = A_(k.accent, 1),
		btnFillHi   = A_(k.bright, 1),
		btnFillText = A_(k.disc, 1),
		btnEdge     = A_(k.border, 0.32),
		btnHover    = A_(k.border, 0.14),

		--- SEMANTIC GOLD: the one meaning a skin is allowed to move.
		--
		--  Everything else in SEMANTIC answers a question about the GAME and is
		--  one shared copy no skin can reach. This one answers a question about
		--  the game too - warning, leader, this changes your group - but it has
		--  to be legible ON the chrome, and in Dusk the chrome is gold. Dusk's
		--  accent is #f0d9a8; the reserved gold was #f0d9a8. The same colour,
		--  exactly, so the warning ring on the console was the frame's own rim.
		--
		--  IT LIVES IN CHROME, which is what keeps the conditional out of the
		--  code. The brief writes it as `(skin == "Dusk") and A or B` at the
		--  call site, which is the very thing the same paragraph forbids two
		--  lines later. A per-skin value belongs in the per-skin table and then
		--  there is no branch anywhere, and the live sweep carries it for free.
		--
		--  The dim companion is a HUE step, not an alpha: gold at 55% is still
		--  gold, and the point of the pair is two separable weights of it.
		semanticGold    = A_(k.gold, 1),
		semanticGoldDim = A_(k.goldDim, 1),


		-- the console's dial: the accent on a near-black disc, over a white track
		ifecDial  = A_(k.accent, 1),
		ifecDisc  = A_(k.disc, 1),
		ifecTrack = A_(k.track, 0.13),

		-- The wash behind a bar, and the plate a stack count sits on. The
		-- track white is one of the brief's six, so both follow the skin.
		barTrack   = A_(k.track, 0.14),
		countPill  = A_(k.disc, 0.85),

		-- tooltips take the skin only where they are furniture
		ttGuild      = A_(k.accent, 0.80),
		ttBadgeInk   = A_(k.accent, 1),
		ttBadgeBg    = A_(k.border, 0.18),
		ttBadgeEdge  = A_(k.border, 0.35),
		ttDivider    = A_(k.border, 0.18),
		ttEliteInk   = A_(k.disc, 1),
		ttHealthBg   = A_(k.track, 0.08),
	}

	for token, v in pairs(SEMANTIC) do c[token] = v end
	return c
end

--- The family in the order it is offered, which is the day it is named for and
--  not the alphabet. Four swatches reading dawn, dusk, midnight, noon say
--  nothing; Midnight, Dawn, Noon, Dusk says what the set IS.
Palette.order = { "midnight", "dawn", "noon", "dusk" }

Palette.skins = {}
for _, name in ipairs(Palette.order) do
	Palette.skins[name] = Compose(name, CHROME[name])
end
-- The live skin. Modules read A.Palette.c.<token>.
Palette.c = Palette.skins.midnight
Palette.current = "midnight"

--- Which token a colour table IS, by identity.
--
--  Rebuilt on every Apply, and it is what lets a FontString be re-coloured
--  on a skin change without its owner recording anything: W.Color is handed
--  Palette.c.text - the very table, not a copy - so the token can be read
--  back off the reference.
--
--  TOP LEVEL ONLY. The nested ones - a difficulty band, a quality rim - are
--  semantic and identical in all four skins, so re-applying them would be
--  work with no effect.
local function IndexTokens(skin)
	local by = {}
	for token, v in pairs(skin) do
		if type(v) == "table" and type(v[1]) == "number" and #v >= 3 then
			by[v] = token
		end
	end
	return by
end

function Palette:Apply(name)
	local skin = Palette.skins[name] or Palette.skins.midnight
	Palette.c = skin
	Palette.current = Palette.skins[name] and name or "midnight"
	Palette.tokenOf = IndexTokens(skin)
	return skin
end

function Palette:List()
	local out = {}
	for _, k in ipairs(Palette.order) do
		out[#out + 1] = { key = k, label = Palette.skins[k].label }
	end
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

--- The same thing, wrapped round a run of text, by ROLE rather than by hex.
--
--  There were 203 hand-written |cff escapes in this addon and five distinct
--  colours between them, two of which - the accent and the type - are chrome
--  and had been wrong since the day a second skin existed: every /aether line
--  printed the same violet whatever skin you were on, because the hex was
--  baked into the string.
--
--  Roles, not colours, is the whole point. "accent" stays right when the accent
--  moves; "9d7bff" was only ever right once.
function Palette:Ink(token, text)
	local c = Palette.c[token]
	if type(c) ~= "table" or type(c[1]) ~= "number" then c = Palette.c.text end
	return Palette:InkHex(Palette:Hex(c), text)
end

--- The skin's track white at whatever alpha the caller wants.
--
--  A bar's wash, a card, a rail - all the same white at a different weight,
--  and all of them were the literal 1, 1, 1 before the family existed.
function Palette:Track(alpha)
	local c = Palette.c.barTrack
	-- NAMED, because this is a fresh table every call and so cannot be found
	-- in tokenOf by identity. The name is what lets a wash be re-applied on a
	-- skin change; the alpha rides along so the caller's weight survives it.
	return { c[1], c[2], c[3], alpha or c[4] or 1, token = "barTrack" }
end

--- The same, for a hex this palette did not choose.
--
--  Class colours come out of RAID_CLASS_COLORS and channel colours out of
--  ChatTypeInfo, and neither is ours to remap - but the ESCAPE around them is,
--  and it is the only thing in the addon allowed to write one. Everything else
--  goes through here or through Ink, so there is exactly one place that knows
--  what the sequence looks like.
function Palette:InkHex(hex, text)
	return "|cff" .. tostring(hex) .. tostring(text) .. "|r"
end

--- The five roles chat text actually comes in, named short because they are
--  written INSIDE other strings and a long call swamps the line it decorates.
--
--  Five, and no more without a reason. A sixth grey that is not quite `dim` is
--  how the 203 escapes happened in the first place.
function A.Hi(text)   return Palette:Ink("accent", text) end     -- a command, a name
function A.Val(text)  return Palette:Ink("text", text) end       -- a value being reported
function A.Good(text) return Palette:Ink("friendly", text) end   -- on, ok, done
function A.Bad(text)  return Palette:Ink("danger", text) end     -- off, failed, missing
function A.Dim(text)  return Palette:Ink("dim", text) end        -- an aside

-- ---------------------------------------------------------------------------
-- dynamic colours
-- ---------------------------------------------------------------------------

local function Mix(a, b, t)
	return a + (b - a) * t
end

--- The one colour a unit's class-coloured health bar is drawn in.
--
--  Flat, and the same for both. The orb used to be its own vertical gradient,
--  which read as a shiny ball rather than a disc.
--
--- Full strength. A health bar is only a few pixels tall, so darkening its
--- class tint would make it read as an inactive track. The level disc has its
--- own face/rim recipe below because it also has to carry white type.
function Palette:UnitColor(unit)
	local base = Palette:ClassColor(unit)
	if base then return { base[1], base[2], base[3] } end

	local c = Palette.c
	local r = unit and UnitExists(unit) and UnitReaction(unit, "player")
	if r and r <= 3 then return c.hostileBar[1] end
	if r == 4 then return c.neutral end
	return c.accent
end

--- The first stop of a bar colour, whichever shape it is.
--
--  Bar colours are either {r,g,b} or a {from,to} pair, and callers that want one
--  triple - a blip, a text colour - should not have to know which.
function Palette:Stop(colors)
	if type(colors) ~= "table" then return { 1, 1, 1 } end
	return type(colors[1]) == "table" and colors[1] or colors
end

-- The level disc is a compact piece of UI rather than a health bar: it needs a
-- deliberately stable palette. In particular, it must not turn into the
-- current skin's accent for a friendly NPC, or inherit a ClassColors addon's
-- custom palette. These are the Classic Era values the disc is specified to
-- communicate, in the 0-255 values used by Blizzard's class-colour table.
--
-- Shaman is intentionally the Vanilla pink supplied for this design. It is
-- kept here, rather than changing RAID_CLASS_COLORS, because the rest of the
-- UI should still respect the player's chosen class-colour addon.
local ORB_CLASS_COLOR = {
	WARRIOR = C(199, 156, 110),
	PALADIN = C(245, 140, 186),
	HUNTER  = C(171, 212, 115),
	ROGUE   = C(255, 245, 105),
	PRIEST  = C(255, 255, 255),
	SHAMAN  = C(245, 140, 186),
	MAGE    = C( 64, 199, 235),
	WARLOCK = C(135, 135, 237),
	DRUID   = C(255, 125,  10),
}

local ORB_HOSTILE  = C(255, 154, 118)
local ORB_NEUTRAL  = C(240, 180, 106)
local ORB_FRIENDLY = C(185, 154, 245)

local function OrbLuminance(c)
	return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
end

local function OrbScale(c, factor)
	return { c[1] * factor, c[2] * factor, c[3] * factor, 1 }
end

local function OrbMix(c, r, g, b, t, a)
	return {
		Mix(c[1], r, t),
		Mix(c[2], g, t),
		Mix(c[3], b, t),
		a or 1,
	}
end

--- The specific colour a level disc represents.
---
--- Players carry their class colour. Everything else carries only the
--- information Blizzard exposes for an NPC: hostile, neutral, or friendly/no
--- reaction. This gives pets, guardians, unclassified creatures, and units
--- without a reaction a coherent treatment instead of falling back to whichever
--- skin happens to be selected.
function Palette:OrbBaseColor(unit)
	if unit and UnitExists(unit) and UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local color = class and ORB_CLASS_COLOR[class]
		if color then return { color[1], color[2], color[3], 1 } end

		-- A future class should not make the disc disappear. It keeps the
		-- client-provided class colour until this explicit table gains a value.
		local fallback = Palette:ClassColor(unit)
		if fallback then return fallback end
	end

	local reaction = unit and UnitExists(unit) and UnitReaction(unit, "player")
	if reaction and reaction <= 3 then return { ORB_HOSTILE[1], ORB_HOSTILE[2], ORB_HOSTILE[3], 1 } end
	if reaction == 4 then return { ORB_NEUTRAL[1], ORB_NEUTRAL[2], ORB_NEUTRAL[3], 1 } end
	return { ORB_FRIENDLY[1], ORB_FRIENDLY[2], ORB_FRIENDLY[3], 1 }
end

--- Face, rim, ink, face highlight, and rim highlight for a unit's level disc.
---
--- The old disc applied the exact same vertex colour to its face, reflection,
--- and rim. At 46px that reads as a flat coloured button. The concept needs a
--- dark enough centre to carry white type, a light raised rim, and just one
--- restrained top-to-bottom lift across the face. Keeping its *perceived*
--- luminance near 0.38 makes a white Priest and a dark Warlock equally legible.
function Palette:OrbColors(unit)
	local base = Palette:OrbBaseColor(unit)
	local lum = math.max(OrbLuminance(base), 0.01)
	local faceScale = math.min(0.72, math.max(0.43, 0.38 / lum))
	local face = OrbScale(base, faceScale)
	local faceHi = OrbMix(face, base[1], base[2], base[3], 0.18)
	local rim = OrbMix(base, 1, 1, 1, 0.46)
	local rimHi = OrbMix(base, 1, 1, 1, 0.70, 0.92)

	return face, rim, { 1, 1, 1, 1 }, faceHi, rimHi
end
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
		-- The same colour the orb gets, flat. Two stops on a bar read as a
		-- gradient wash; a class colour is one colour.
		if Palette:ClassColor(unit) then return Palette:UnitColor(unit) end
	end

	if UnitIsDeadOrGhost(unit) then return { 0.30, 0.30, 0.35 } end

	local reaction = UnitReaction(unit, "player")
	if reaction then
		if reaction <= 3 then return c.hostileBar[1] end
		if reaction == 4 then return c.neutral end
	end
	return c.health[1]
end

--- Which of the five difficulty bands a level falls in.
--
--  Lives here rather than in the quest log because three surfaces now ask the
--  question - the log, the tracker, and a nameplate's level badge - and a
--  threshold that drifted between them would show the same mob as yellow in one
--  place and orange in another.
--
--  Thresholds are Blizzard's own from GetRelativeDifficultyColor. The green
--  range comes from GetQuestGreenRange rather than the `floor(P/10)+5` formula,
--  because the formula is only the client's default and the call is what it
--  actually uses.
function Palette:DifficultyBand(level)
	if not level or level <= 0 then return "difficult" end
	local player = (UnitLevel and UnitLevel("player")) or level
	local diff = level - player

	if diff >= 5 then return "impossible" end
	if diff >= 3 then return "verydifficult" end
	if diff >= -2 then return "difficult" end

	local green = 5
	if GetQuestGreenRange then
		local ok, g = pcall(GetQuestGreenRange)
		if ok and type(g) == "number" then green = g end
	end
	if -diff <= green then return "standard" end
	return "trivial"
end

--- Is this level far enough above you to be a skull rather than a number?
--
--  Two ways to be one: the client hands back -1 for a unit whose level it will
--  not tell you, and ten levels up is the concept's own threshold.
function Palette:SkullLevel(level)
	if not level or level < 0 then return true end
	local player = (UnitLevel and UnitLevel("player")) or level
	return level - player >= 10
end

--- Disc, rim and ink for a level badge, from the difficulty of that level.
--
--  The tooltip badge's recipe - the colour at .15 for the disc, .40 for the rim,
--  full strength for the number - over the quest log's difficulty colour. One
--  colour doing three jobs, which is what keeps a 26px disc from turning into
--  two competing rings, and the same red on a nameplate that means "come back
--  later" in the log.
--
--  Deliberately not the concept's filled gradient with dark type on it. Every
--  other badge in this UI is a tinted disc with the colour as the number, and a
--  nameplate is the last place to introduce a second kind.
function Palette:DifficultyColors(level)
	local band = Palette.c.questDiff[Palette:DifficultyBand(level)]
		or Palette.c.questDiff.difficult
	return Palette:ChipColors(band.text)
end

--- One colour, three jobs: disc, rim, ink.
--
--  The recipe every badge in this UI wears, named once so the difficulty badge
--  and the class-coloured pip on a friendly nameplate cannot drift apart.
function Palette:ChipColors(c)
	if not c then c = Palette.c.text end
	return { c[1], c[2], c[3], 0.15 }, { c[1], c[2], c[3], 0.40 }, c
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

--- The four-way reaction colour: hostile, neutral, friendly NPC, friendly player.
--
--  ReactionEdge answers a coarser question and collapses the two friendlies into
--  one green, which is right for a capsule rim - the thing you want to know mid
--  -fight is whether the rim is red. A name is not that: a green name and a blue
--  one are how you tell an innkeeper from a person, and on a nameplate that is
--  most of the information on screen.
--
--  These are the tooltip's tokens rather than new ones, because they already are
--  the concept's four nameplate hexes to the digit and a name should not change
--  colour depending on which surface you read it from.
function Palette:NameReaction(unit)
	local c = Palette.c
	if not unit or not UnitExists(unit) then return c.ttFriendlyNPC end
	if UnitIsPlayer(unit) then
		local reaction = UnitReaction(unit, "player")
		if reaction and reaction <= 3 then return c.ttHostile end
		if reaction == 4 then return c.ttNeutral end
		return c.ttFriendly
	end
	local reaction = UnitReaction(unit, "player")
	if reaction and reaction <= 3 then return c.ttHostile end
	if reaction == 4 then return c.ttNeutral end
	return c.ttFriendlyNPC
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
