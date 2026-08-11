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
	},

	-- 1a in the deck: warm light glass, sits better over Classic's palette.
	daylight = {
		label       = "Daylight",

		glass       = C(252, 248, 240, 0.17),
		glassSoft   = C(252, 248, 240, 0.12),
		glassStrong = C(252, 248, 240, 0.24),
		glassEdge   = C(255, 255, 255, 0.36),
		glassEdgeHi = C(255, 255, 255, 0.55),
		shadow      = C(30, 15, 0, 0.35),

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
		targetGlass = C(252, 248, 240, 0.17),
		targetEdge  = C(255, 255, 255, 0.36),
		targetText  = C(255, 255, 255, 1.00),

		cast        = { C(142, 200, 255), C(212, 236, 255) },
		castEdge    = C(180, 220, 255, 0.50),
		castGlow    = C(160, 210, 255, 0.45),

		danger      = C(255, 138, 138, 1.00),
		xp          = { C(185, 138, 224), C(217, 184, 240) },
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
function Palette:OrbColor(unit)
	local base
	if unit and UnitExists(unit) and UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if cc then base = { cc.r, cc.g, cc.b } end
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
