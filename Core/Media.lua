--[[--------------------------------------------------------------------------
	AetherUI :: Media

	Every texture and font path in one table, plus LibSharedMedia registration so
	other addons (Bartender4, Plater, Gnosis, WeakAuras...) can pick up the same
	assets and the whole UI stays coherent.

	Slice metadata lives here too. The generator in Tools/generate_textures.py
	guarantees the corner geometry quoted below; if you change one, change both.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Media = {}
A.Media = Media

local TEX  = [[Interface\AddOns\]] .. ADDON .. [[\Media\Textures\]]
local FONT = [[Interface\AddOns\]] .. ADDON .. [[\Media\Fonts\]]

-- ---------------------------------------------------------------------------
-- textures
-- ---------------------------------------------------------------------------

Media.texture = {
	-- frosted surfaces
	panel       = TEX .. "Glass-Panel",       -- 256x256, 9-slice, corner 64 (0.25)
	panelEdge   = TEX .. "Glass-Panel-Edge",
	-- The same rounded shape with FLAT alpha. Glass-Panel's alpha carries the
	-- top-light falloff as well as the shape, so a tint on it tops out at 89%
	-- and a reading surface asked for solid could not get there. This goes
	-- behind one when it is asked for more than the art can carry.
	panelSolid  = TEX .. "Glass-Panel-Solid",
	pill        = TEX .. "Glass-Pill",        -- 512x256, 3-slice, cap 128 (0.25)
	pillEdge    = TEX .. "Glass-Pill-Edge",
	-- THE SAME CAPSULE, AUTHORED SMALL. 128x64, the same 0.25 slice, so the
	-- geometry is identical and only the texture changes. The big one is drawn
	-- for 2x a 4K display; at a level chip's twenty pixels its 128-texel cap is
	-- minified thirteen times with no mipmap behind it, and the ends come back
	-- jagged. Core/Glass.lua picks between them by height.
	pillSmall     = TEX .. "Glass-Pill-Small",
	pillSmallEdge = TEX .. "Glass-Pill-Small-Edge",
	shadow      = TEX .. "Glass-Shadow",      -- 256x256, 9-slice, corner 96 (0.375)
	pillShadow  = TEX .. "Glass-Pill-Shadow", -- 512x256, 3-slice, spread = h/4
	noise       = TEX .. "Noise",             -- 128x128, seamless, tileable
	-- 512x512, seamless, tileable. Zen's full-screen pane. Unlike Noise this
	-- carries its pattern in ALPHA rather than RGB, so it survives being tinted,
	-- and it is authored at a scale you can see - tiled ~3x across a screen, not
	-- ~20x. See frost_tile() in Tools/generate_textures.py.
	frost       = TEX .. "Frost",

	-- ability / aura slots
	slotMask    = TEX .. "Slot-Mask",
	slotShade   = TEX .. "Slot-Shade",
	slotGloss   = TEX .. "Slot-Gloss",
	slotEdge    = TEX .. "Slot-Edge",
	slotGlow    = TEX .. "Slot-Glow",         -- drawn at 2x the slot, centred

	-- round things
	circleMask  = TEX .. "Circle-Mask",
	-- The same two shapes at 64, for chips drawn near that size rather than
	-- magnified onto the minimap. A 256px circle drawn at 30 is minified eight
	-- times and the client does not mipmap.
	chipDisc    = TEX .. "Chip-Disc",
	chipRim     = TEX .. "Chip-Rim",
	ring        = TEX .. "Ring",
	orbFace     = TEX .. "Orb-Face",
	orbRing     = TEX .. "Orb-Ring",
	ringGlow    = TEX .. "Ring-Glow",         -- drawn at 2x, centred
	-- The map's whole edge in one texture: dark band inside, hairline on the
	-- edge. Two tones, so its colours are baked in and it is drawn untinted.
	minimapBorder = TEX .. "Minimap-Border",

	-- bars
	bar         = TEX .. "Bar-Smooth",
	flat        = TEX .. "Bar-Flat",
	barGlow     = TEX .. "Bar-Glow",
	barMask     = TEX .. "Bar-Mask",

	-- misc
	glow        = TEX .. "Glow-Soft",
	vignette    = TEX .. "Vignette",
	-- The threat alarm's screen edge. Its own texture rather than the vignette
	-- above: that one is authored BLACK, to darken corners for Zen, and a vertex
	-- colour multiplies - so tinting it red gives black. This one is white and
	-- hugs the four edges rather than making a circle in the middle.
	threatEdge  = TEX .. "Threat-Edge",
	divider     = TEX .. "Divider",
	chevron     = TEX .. "Chevron",
	send        = TEX .. "Send",             -- the edit box's paper plane
	badges      = TEX .. "Chat-Badges",      -- the chat line pills, one per row

	-- THE BRAND. Not drawn by generate_textures.py like everything above it -
	-- these two are artwork, and they come in from docs/brand via
	-- Tools/generate_brand_textures.py, which strips the logo's dark plate so
	-- the mark sits on whichever palette is loaded rather than on Midnight's
	-- navy wherever it is put.
	--
	-- 512x256, holding a 3.3:1 lockup: the mark, then the wordmark. The nearest
	-- power of two that holds it leaves a fifth of the height empty at each end,
	-- so the band below is the ink. Draw with it and the size you ask for is the
	-- size you get; draw without it and a fifth of your height is air.
	logo        = TEX .. "Logo",
	-- 64x64, the mark on its own, transparent to the edge of its glow. Sixty-four
	-- rather than 128 for the reason the icon atlas above is: this is drawn near
	-- 35 physical pixels on the rail and in the addon list, and a texture minified
	-- four times with no mipmap behind it comes back speckled.
	icon        = TEX .. "Icon",
}

--- Where the logo's ink actually is inside its canvas. SetTexCoord takes it
--  straight: `tex:SetTexCoord(unpack(Media.logoCoord))`.
--
--  A CONTRACT with Tools/generate_brand_textures.py, the same way the icon
--  atlas order is one: that script measures the band it produced and refuses to
--  write anything if these four numbers disagree with it.
Media.logoCoord = { 0, 1, 53 / 256, 205 / 256 }

--- That band's aspect, width over height: 512 texels by 152. A caller picks
--  one dimension and takes the other from here, so the mark is never squashed
--  by somebody guessing the second number.
Media.logoAspect = 512 / 152

--- The chat badge atlas: thirteen pills, one per row, three characters each.
--
--  Unlike everything else here, this one is addressed by *texel* rather than by
--  fraction, because that is what an inline `|T...|t` escape takes. `index` is
--  the row, top to bottom, and the aspect never changes - every pill is `pill`
--  wide and `row` tall - so a badge's on-screen width is always its height times
--  pill/row. See Modules/Chat.lua, which builds the markup.
--
--  A contract with Tools/generate_textures.py: the BADGES list there is these
--  row numbers, in order. The harness checks the two still agree.
-- The Toolbox icon sheet: line art on a 4x4 grid of 128px cells.
--
-- ONE atlas rather than sixteen files, for the reason the chat badges are one:
-- a new .tga needs a client RESTART and not a reload, so the fewer files there
-- are the fewer times anybody has to quit the game. SetTexCoord costs nothing
-- at the call site.
--
-- THE ORDER HERE IS THE ORDER IN Tools/generate_textures.py (ICON_ORDER).
-- Change one and you must change the other; the harness asserts the two agree
-- by reading the generator, because a silently shifted atlas is sixteen wrong
-- icons and no error anywhere.
Media.icons = {
	file = TEX .. "Toolbox-Icons",
	-- A FIXED 8x8 of 64px cells. Fixed because sizing the sheet to the number
	-- of icons gives a non-power-of-two height the moment there are seventeen,
	-- and 64 rather than 128 because these are drawn at twenty-odd pixels: a
	-- 128 cell is minified five times and its stroke falls under a pixel, which
	-- is the speckling this file's rim notes already record. Sixty-four slots,
	-- and adding one never moves an existing one.
	cell = 64,
	cols = 8,
	rows = 8,
	order = {
		"character", "spellbook", "talents", "quests",
		"social", "guild", "map", "menu",
		"help", "zen", "damage", "keybinds",
		"combat", "gear", "pin", "pinned",
		"whatsnew",
		"mail", "mailfull",
		"lock",
		"exit",
		"music", "podcast", "gossip",
		"play", "pause", "prev", "next",
		"grip", "tick",
		"library", "ifec", "zoom", "close",
		"crown", "healer", "dps", "resurrect",
		"bags", "keys",
		-- Turning a paper doll. ONE drawing: the other direction is this one
		-- mirrored, which is a swap of two texture coordinates rather than a
		-- second cell that has to agree about what an arrow looks like.
		"rotate",
		-- what Mists puts on its menu and Era has not got. Dungeons and the
		-- Guide are aliases below, because the sheet already means them.
		"achievements", "pvp", "collections",
	},

	--- One drawing, more than one name for it.
	--
	--  A tank's shield is the shield already on the sheet and the party
	--  handle's pair of figures is the one already on the sheet. Drawing
	--  either a second time would be two cells that have to agree about
	--  what a shield looks like, and one day would not.
	alias = {
		tank  = "guild",
		party = "social",
		-- The Mists menu entries, where a drawing already on the sheet means
		-- the thing: the group finder IS a group of people, and the encounter
		-- journal IS a book. Aliases rather than new cells, so there is never a
		-- second drawing that has to agree with the first about what a book
		-- looks like.
		--
		-- The other three - Achievements, Collections and PvP - did get cells of
		-- their own, in the generator pass that followed. They are in `order`
		-- above and drawn on the sheet; nothing in this row stands as a letter
		-- any more.
		dungeons = "social",
		guide    = "library",
	},
}

do
	local ix = {}
	for i, name in ipairs(Media.icons.order) do ix[name] = i - 1 end
	Media.icons.index = ix
end

--- Texel coordinates for one icon, ready for SetTexCoord.
function Media:Icon(name)
	local a = Media.icons
	local i = a.index[name] or a.index[a.alias[name] or false]
	if not i then return nil end
	local c, r = i % a.cols, math.floor(i / a.cols)
	return a.file, c / a.cols, (c + 1) / a.cols, r / a.rows, (r + 1) / a.rows
end

--- Point a texture at one. Returns false when the name is unknown, so a caller
--- can fall back rather than draw the whole sheet - which is what a texture
--- with no SetTexCoord does, and it is unmistakable on screen.
--- `flip` mirrors it left to right, which is two coordinates swapped rather
--- than a second drawing of the same thing facing the other way.
function Media:SetIcon(tex, name, flip)
	if not tex then return false end
	local file, l, r, t, b = Media:Icon(name)
	if not file then return false end
	tex:SetTexture(file)
	if flip then l, r = r, l end
	tex:SetTexCoord(l, r, t, b)
	return true
end

-- A DIAL: A RING THAT FILLS CLOCKWISE, as a sheet of baked steps.
--
-- Classic cannot fill a ring by angle - there is no conic gradient and no arc
-- primitive - so the sweep is 64 frames and the caller picks one. A step every
-- 1/64 is under noticing for anything that moves at a readable speed, and it
-- costs one SetTexCoord rather than a mask stack rebuilt every frame.
--
-- Frame i is (i+1)/64 of a turn, so there is no empty frame: nothing showing is
-- the texture hidden. Keep `steps`, `cols` and `ring` in step with
-- generate_textures.py, which is the other half of this contract.
--
-- TWO OF THEM, AND ONE MECHANISM. The flight console's dial and the threat ring
-- are the same shape at two band widths, so the generator draws both from one
-- pair of functions and this is a family rather than a second dial invented
-- beside the first. Anything else wanting a gauge that fills round a disc adds
-- a row here; it does not add a mechanism.
Media.dial = {
	-- Each family says where its sweep starts and how much of a turn a full one
	-- covers, both in turns clockwise from twelve o'clock. Nothing here reads
	-- them - the sweep is baked into the sheet - but Tools/generate_textures.py
	-- holds itself to them and the harness holds this file to them, because a
	-- dial that starts or stops somewhere else throws no error anywhere. It just
	-- looks like a different instrument.

	-- The flight console's, 4.5 of band on a 44 ring.
	--
	-- A WHOLE TURN FROM THE TOP, because it is a clock rather than a gauge. A
	-- flight is a length of time you are part way along; time starts at twelve,
	-- and a countdown has to be able to reach the end.
	ifec = {
		track = TEX .. "IFEC-Dial-Track",
		arc   = TEX .. "IFEC-Dial-Arc",
		from  = 0,
		span  = 1,
	},
	-- 16b's threat ring: 3 of band, 44 outer round a 38 pip.
	--
	-- NO TRACK. The console's dial has one because a flight has a length you
	-- are part way along; a threat ring does not. 16b describes an arc and
	-- nothing behind it, and below the floor the design shows NOTHING - so a
	-- track would be a faint ring sitting round every pip for the whole fight,
	-- which is the one thing quiet-by-default is against.
	--
	-- ELEVEN TWELFTHS, FROM HALF PAST SIX, which is the difference between the
	-- two. This one is a GAUGE - a needle sweeping a scale - and every gauge
	-- ever built sweeps up from the bottom and stops short of it on the way
	-- back, leaving the scale's two ends distinguishable. Filling twelve to
	-- twelve made it read as a clock counting something down, which is the one
	-- thing threat is not: it has no length and no end, only a level.
	--
	-- THE GAP IS MEASURED, NOT CHOSEN. It is the addon's own mark: the ring in
	-- docs/brand/AetherUI-Icon.png opens 29 degrees about six o'clock and covers
	-- 91.9% of a turn, and 11/12 is that to within half a degree.
	--
	-- Which means full is not a closed circle here. That is the point - a gauge
	-- at the top of its scale should still read as a gauge.
	threat = {
		arc  = TEX .. "Threat-Dial-Arc",
		from = 6.5 / 12,
		span = 11 / 12,
	},
}

-- Shared by every family, because the sheet layout is the mechanism and the
-- band is the only thing that differs.
Media.dialSheet = {
	cell  = 64,
	cols  = 8,
	rows  = 8,
	steps = 64,
	-- The ring is inset inside its cell so a bilinear sample at the edge cannot
	-- read the frame next door. A frame drawn at size S shows a ring of S*ring,
	-- so the caller divides by this to land on the design's 44.
	ring  = 0.875,
}

--- Texel coordinates for the frame nearest `fraction` of a turn.
--
--  Returns nil below the first step rather than a blank frame - there isn't
--  one, and a caller that hides the texture reads better than one that draws
--  nothing very carefully.
function Media:DialArc(fraction, family)
	local d = Media.dialSheet
	local art = Media.dial[family or "ifec"]
	if not art then return nil end
	if type(fraction) ~= "number" or fraction <= 0 then return nil end
	if fraction > 1 then fraction = 1 end

	local i = math.ceil(fraction * d.steps) - 1
	if i < 0 then i = 0 end
	if i >= d.steps then i = d.steps - 1 end

	local c, r = i % d.cols, math.floor(i / d.cols)
	return art.arc, c / d.cols, (c + 1) / d.cols, r / d.rows, (r + 1) / d.rows
end

Media.badges = {
	file   = TEX .. "Chat-Badges",
	-- The file's own dimensions, which a `|T` escape needs to make sense of the
	-- texel coordinates that follow it...
	width  = 128,
	height = 512,
	row    = 38,
	-- ...and how much of each row the pill actually occupies. The tile is 128
	-- wide because that is the power of two the file needs; three characters in
	-- a pill this tall want an aspect near 2.3, and stretching one to the full
	-- tile gives 3.4 - a letterbox with three letters rattling about in it.
	pill   = 88,
	index  = {
		SAY = 0, YELL = 1, PARTY = 2, RAID = 3, GUILD = 4, OFFICER = 5,
		WHISPER = 6, TO = 7, EMOTE = 8,
		-- The four channels a Classic Era character actually joins. Everything
		-- else falls back to the channel's own name as plain text, because a
		-- word baked into a texture cannot be localised or invented at runtime.
		GENERAL = 9, TRADE = 10, LFG = 11, DEFENSE = 12,
	},
}

--- Slice fractions, consumed by Core\Glass.lua. These are a contract with
--  Tools/generate_textures.py: change one and you must change the other.
--    panel/pill  0.25   corner 32 of 128, cap 64 of 256
--    shadow      0.375  corner 48 of 128 - wider, because the blur spill has to
--                       fit inside the corner slice or the edges stop being
--                       uniform along their stretch axis
Media.slice = {
	panel      = 0.25,
	pill       = 0.25,
	shadow     = 0.375,
	pillShadow = 0.25,
}

--- Source dimensions, so Core\Glass.lua can inset slice texcoords by half a
--  texel. Without that inset the GPU's bilinear filter samples across a slice
--  boundary and pulls in a neighbouring region's texels, which shows up as a
--  faint mark at each corner - worst where two slices are drawn at very
--  different scales, e.g. a 32-texel corner rendered at 14px next to a
--  64-texel edge stretched across hundreds.
Media.textureSize = {
	-- All authored at 2x the size they are drawn at on a 4K display. At 1:1 the
	-- only anti-aliasing on a curve is the single texel the generator puts
	-- there; minified 2x, bilinear averages four samples per pixel and the edge
	-- comes out smooth. See Tools/generate_textures.py.
	panel      = { 256, 256 },
	pill       = { 512, 256 },
	pillSmall  = { 128, 64 },
	shadow     = { 256, 256 },
	pillShadow = { 512, 256 },
}

-- ---------------------------------------------------------------------------
-- fonts
-- ---------------------------------------------------------------------------

Media.font = {
	light    = FONT .. "Outfit-Light.ttf",
	regular  = FONT .. "Outfit-Regular.ttf",
	medium   = FONT .. "Outfit-Medium.ttf",
	semibold = FONT .. "Outfit-SemiBold.ttf",
	bold     = FONT .. "Outfit-Bold.ttf",
}

--- Named roles, so modules never hard-code a weight/size pair.
--  { fontKey, size, outline }
Media.style = {
	unitName     = { "semibold", 14, "" },
	unitSub      = { "light",    11, "" },
	unitValue    = { "semibold", 11, "" },
	unitValueAlt = { "regular",  10, "" },
	level        = { "bold",     12, "OUTLINE" },
	castName     = { "semibold", 13, "" },
	castTime     = { "medium",   11, "" },
	keybind      = { "semibold",  9, "OUTLINE" },
	stack        = { "bold",      11, "OUTLINE" },
	label        = { "semibold", 11, "" },   -- letter-spaced section headings
	tiny         = { "light",    10, "" },
	-- Aura timers sit under the icon on open background rather than on glass,
	-- so this one is outlined where `tiny` is not.
	auraTime     = { "medium",   10, "OUTLINE" },
	-- The hairline's readout. Its own role rather than borrowing `tiny`: that one
	-- is Light, which at this size on a bright background comes out wispy and
	-- half-legible, and it was a couple of points larger than the line wants.
	-- Medium is the same family as the unit names one weight down.
	xpText       = { "medium",    9, "" },
	-- Chat. The message face is Regular rather than Light: this is the one thing
	-- on screen somebody actually reads a paragraph of, and it is read against
	-- whatever the world happens to be doing behind it.
	chatText     = { "regular",  12, "" },
	-- 10, not 11. At 11 the channel names read a shade heavier than the messages
	-- beside them, which inverts the emphasis: the tabs are navigation, the lines
	-- are the content. The composer's channel capsule does NOT inherit this - it
	-- is re-sized from Chat:FontSize so the code reads at the size you type at.
	chatTab      = { "semibold", 10, "" },
	chatBadge    = { "bold",      8, "" },   -- the channel tag, uppercase
	-- The messages the game throws at the middle of the screen: an error, a
	-- zone banner, a raid warning. All of them are drawn over the WORLD with
	-- nothing behind them, so the outlines the client uses are load-bearing
	-- and are kept exactly as it has them - a zone name in our lettering with
	-- the thick outline dropped is unreadable over snow.
	--
	-- The sizes here are only fallbacks: Reskin.Font keeps whatever size the
	-- client's own font object was using, so this is a change of FACE and
	-- nothing else. Nothing on screen moves or reflows.
	errMessage   = { "semibold", 16, "" },            -- "You can't do that yet"
	zoneName     = { "semibold", 32, "THICKOUTLINE" },
	zoneSub      = { "medium",   26, "THICKOUTLINE" },
	raidNotice   = { "bold",     20, "" },

	questTitle   = { "medium",   12, "" },
	questLine    = { "light",    11, "" },   -- objective lines under a quest

	-- Quest log window (concept 3b). Sizes are the deck's own, because the whole
	-- window is drawn at profile.scale like the rest of the module geometry - the
	-- deck's 24px title at 0.71 is 17 virtual units, which on a 1600-tall display
	-- lands back on 35 physical pixels, exactly where the deck put it.
	--
	-- The deck uses half-point sizes (11.5, 13.5, 14.5). SetFont takes them, but
	-- the glyph rasteriser rounds anyway and a half point is invisible at this
	-- scale, so each is rounded to the nearest whole point here rather than
	-- carrying a fraction through the layout arithmetic.
	qlHeading    = { "semibold", 19, "" },   -- "Quest Log"
	qlTitle      = { "semibold", 24, "" },   -- the selected quest's name
	qlCount      = { "medium",   13, "" },   -- the 17 / 20 chip
	qlSearch     = { "light",    13, "" },
	qlZone       = { "semibold", 12, "" },   -- letter-spaced zone heading
	qlRow        = { "regular",  14, "" },
	qlRowSel     = { "semibold", 14, "" },   -- the selected row goes up a weight
	qlChip       = { "bold",     12, "" },   -- level chip
	qlTag        = { "semibold", 11, "" },   -- "Dungeon"
	qlSummary    = { "light",    15, "" },
	qlBody       = { "light",    14, "" },   -- description paragraph
	qlLabel      = { "semibold", 12, "" },   -- letter-spaced DESCRIPTION
	qlObjName    = { "medium",   14, "" },
	qlObjCount   = { "semibold", 13, "" },
	qlBtn        = { "semibold", 14, "" },   -- the filled Track button
	qlBtnAlt     = { "medium",   14, "" },   -- Share / Abandon outlines

	-- Bags. The deck's sizes are a point or two under the quest log's at every
	-- role, because a bag panel is a dense grid rather than a page of prose, so
	-- these are their own roles rather than borrowed ql* ones.
	--
	-- None of them carry OUTLINE. The stack count does, and it uses the shared
	-- `stack` role for exactly that reason: it is the only string here that has
	-- to stay legible on top of an arbitrary item icon.
	bagTitle     = { "semibold", 18, "" },   -- "Bags" / "Bank"
	bagChip      = { "bold",     11, "" },   -- the 58 / 80 capacity chip
	bagLabel     = { "semibold", 11, "" },   -- letter-spaced EQUIPMENT / JUNK
	bagCount     = { "medium",   10, "" },   -- the count trailing a section label
	bagMoney     = { "semibold", 13, "" },   -- 142g
	bagFoot      = { "regular",  12, "" },   -- "22 slots free"
	bagSearch    = { "light",    13, "" },
	bagBag       = { "medium",   12, "" },   -- a bag's name in the flyout
	bagBagSub    = { "light",    10, "" },   -- "20 - herbs only"
	bagGlyph     = { "bold",     12, "" },   -- the letter on a bag tile
	bagPrice     = { "semibold",  9, "" },   -- "10g" on a purchasable bank slot

	-- Tooltips (concept 6a / 6b). The deck's own sizes, because the tooltip is
	-- drawn at profile.scale like every other module - 15 at 0.71 is 10.7 virtual
	-- units, which is where the deck put it.
	--
	-- ttBody is the one that matters and it is Light rather than Regular, unlike
	-- chatText. Chat is a paragraph you read; a tooltip is a table you scan, and
	-- the deck weights it at 300 throughout precisely so the ONE thing carrying
	-- weight on the card - the name - is the thing your eye lands on first.
	--
	-- These three are also the roles applied to the client's own font OBJECTS
	-- (GameTooltipHeaderText / GameTooltipText / GameTooltipTextSmall), so every
	-- line another addon adds inherits them without knowing we exist. ttName maps
	-- to the header object, ttBody to the body object, ttSmall to the small one.
	ttName       = { "semibold", 15, "" },   -- unit / spell / item name
	ttBody       = { "light",    13, "" },   -- everything the client writes
	ttSmall      = { "light",    12, "" },
	ttSub        = { "light",    12, "" },   -- "Humanoid - Hostile"
	ttBadge      = { "semibold", 12, "" },   -- the number in the level badge

	-- Toolbox. The deck's own sizes: 18 header, 14 card title, 12.5 body,
	-- 14.5 widget value, 11 label, 11 section heading. The section headings are
	-- letter-spaced in the deck; the client has no letter-spacing, so those are
	-- drawn with the spacing baked into the string instead (see Toolbox.lua).
	-- Whole points, and nothing lighter than Regular. The deck's 12.5 Light
	-- body is a web weight at a web size; drawn at profile.scale 0.71 it is a
	-- nine-pixel Light, which is spidery rather than quiet and reads as the
	-- text being badly rendered rather than as a light weight.
	tbTitle      = { "semibold", 18, "" },
	tbChip       = { "bold",     11, "" },
	tbCardTitle  = { "semibold", 14, "" },
	tbCardBody   = { "regular",  13, "" },
	tbSection    = { "semibold", 11, "" },
	tbValue      = { "semibold", 15, "" },
	tbLabel      = { "medium",   11, "" },
	ttChip       = { "bold",     10, "" },   -- ELITE
	thChip       = { "bold",     10, "" },   -- LOSING AGGRO
	ttBarLabel   = { "medium",   11, "" },   -- "Health" / "1,240 / 1,240"

	-- The client's own windows (Panels.lua).
	--
	-- NOT OUTLINED, and they used to be. The argument was that these labels sit
	-- over whatever the window is showing - a paper doll, a talent tree's
	-- artwork - rather than over an even fill of ours, so an unoutlined word
	-- would read as smudged. That was true of the stone windows and stopped
	-- being true the moment the art came off: what they sit over now is our own
	-- glass, the same as every other string in this interface, and nothing else
	-- here is outlined. On a filled tab it was worse than useless - a black
	-- stroke around dark type on a light fill, which reads as a sticker.
	pnTab        = { "semibold", 12, "" },
	-- 16 AND NEVER LARGER, which is the panel package's one hard number for
	-- type: one title size for every panel in the interface. It was 18, and
	-- the client windows added a point on top of that for 19.
	pnTitle      = { "semibold", 16, "" },
	-- The way out. Its own role because the cross is drawn at one size
	-- everywhere, and hanging it off the title role made it grow and shrink
	-- with a heading it has nothing to do with.
	-- SEMIBOLD. The quest log's own cross was semibold 19 before the shared
	-- button took the job, and at medium 14 it went from a mark you could see
	-- across a 1240-wide window to a grey smudge. The handoff's "14px stroke"
	-- is a number for a browser at 1:1; everything here is drawn at the
	-- profile's scale, so 14 lands at ten physical pixels of thin type.
	pnClose      = { "semibold", 16, "" },
	pnSub        = { "medium",   13, "" },
	-- Everything else inside one: stat rows, resistances, faction names. Drawn
	-- at whatever size the client already gave the string, so its own layout
	-- still measures out - only the family and the outline are ours.
	pnBody       = { "medium",   12, "" },

	-- Nameplates (concept 7a / 7b). Their own roles rather than the tooltip's,
	-- close as the numbers are: a tooltip is read under the cursor with the
	-- world stopped, and a plate is read at thirty yards over moving ground
	-- while something is hitting you. When one of these two has to grow to stay
	-- legible it should be able to without dragging the other with it.
	npName       = { "semibold", 14, "" },
	npBadge      = { "bold",     10, "" },   -- the number in the level badge
	npChip       = { "bold",      9, "" },   -- ELITE / RARE
	npAura       = { "medium",   11, "" },   -- "Chilled - 4s" under a target
	npGuild      = { "regular",  12, "" },   -- <Samophlange>, under a friendly
	-- A point up on npName. The capsule forms have glass behind them and
	-- read fine at 14; a friendly name is shadowed type straight onto the
	-- world, and the same size there is a size smaller.
	npFriendly   = { "semibold", 15, "" },

	-- The in-flight console. The design's 14.5/11.5/10.5 rounded: a font size
	-- is a request for a pixel grid and half points are not one.
	ifecRoute    = { "semibold", 15, "" },   -- Booty Bay -> Ironforge
	ifecSub      = { "light",    12, "" },   -- elapsed 2:01 - lands 4:12 - 2 legs
	ifecDial     = { "semibold", 11, "" },   -- the numeral inside the ring
	ifecTitle    = { "semibold", 14, "" },   -- The Gadgeteer - S0 E01
	ifecMeta     = { "light",    11, "" },   -- 4:12 left - then Winds of Feralas
	ifecUpNext   = { "regular",  13, "" },
	ifecCaption  = { "light",    11, "" },   -- programme fills 5:52 of 6:04
	ifecSection  = { "semibold", 11, "" },   -- UP NEXT
	ifecChip     = { "medium",   12, "" },
}

-- ---------------------------------------------------------------------------
-- LibSharedMedia
-- ---------------------------------------------------------------------------

function Media:Initialize()
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if not LSM then return end

	LSM:Register("statusbar", "Aether Smooth",  Media.texture.bar)
	LSM:Register("statusbar", "Aether Flat",    Media.texture.flat)
	LSM:Register("background", "Aether Glass",  Media.texture.panel)
	LSM:Register("background", "Aether Noise",  Media.texture.noise)
	LSM:Register("border",     "Aether Rim",    Media.texture.panelEdge)

	LSM:Register("font", "Outfit Light",    Media.font.light)
	LSM:Register("font", "Outfit",          Media.font.regular)
	LSM:Register("font", "Outfit Medium",   Media.font.medium)
	LSM:Register("font", "Outfit SemiBold", Media.font.semibold)
	LSM:Register("font", "Outfit Bold",     Media.font.bold)

	Media.LSM = LSM
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

-- Fallback by READ-BACK, which is the only question that has one answer for
-- both kinds of thing we call SetFont on.
--
-- This has now been wrong twice, in opposite directions, and both times because
-- it tried to learn something from a RETURN VALUE:
--
--   1. `if not fontString:SetFont(...) then fall back` read the return of the
--      call it had just made. Right for a FontString, whose SetFont answers
--      isValid. Wrong for a font OBJECT, whose SetFont answers nothing - so
--      `not nil` was true and the three tooltip objects were stamped with
--      FRIZQT__.TTF a microsecond after being given Outfit.
--
--   2. Probing each face ONCE through a scratch FontString and caching the
--      verdict. That answered false for Outfit on a real client - and being
--      cached, it condemned EVERY string in the addon to the game font for the
--      rest of the session. Worse than the bug it replaced: the first version
--      lost three font objects, this one lost the whole interface, and it
--      passed its tests either way because the mock's SetFont returns true.
--
-- So nothing is read from a return and nothing is cached. Set the font, then
-- ask the object what font it HAS. Both FontStrings and font objects answer
-- GetFont, and the answer is the truth rather than a report about it.
--
-- The fallback fires only when there is NO font at all afterwards, which is the
-- case it was written for: one of our own new FontStrings whose face failed to
-- load has nothing, and nothing draws as invisible text. A font OBJECT that
-- refuses our face keeps the client's, and the client's face is exactly what
-- the fallback would have set anyway - so there is nothing to correct and no
-- opinion to have about it.
local FALLBACK = [[Fonts\FRIZQT__.TTF]]

--- Apply a named style from Media.style to a FontString OR a font object.
--  Falls back to the game font if the TTF fails to load, so a bad install
--  degrades to "ugly" instead of "invisible text".
--- The FILE a style is drawn in, without touching anything.
--
--  SetFont below is written for a FontString. A SimpleHTML holds a font
--  per text type and takes the type as its first argument, so it needs the
--  path and the size rather than a widget to set them on.
function Media:FontFor(styleName)
	local style = Media.style[styleName] or Media.style.unitSub
	return Media.font[style[1]] or Media.font.regular,
		math.floor((tonumber(style[2]) or 12) + 0.5), style[3]
end

function Media:SetFont(fontString, styleName, sizeOverride)
	local style = Media.style[styleName] or Media.style.unitSub
	local path  = Media.font[style[1]] or Media.font.regular
	-- ROUNDED. A font size is a request for a pixel grid, and 12.5 is not one:
	-- the rasteriser rounds it anyway, but it rounds AFTER the frame's scale has
	-- been applied, so the same role lands on a different fraction in every
	-- module and the hinting differs with it. Rounding here means the deck's
	-- half-points (12.5, 14.5, 10.5) become one consistent size rather than
	-- whatever 0.71 of them happened to be.
	local size  = sizeOverride or style[2]
	size = math.floor((tonumber(size) or 12) + 0.5)
	local flags = style[3]

	fontString:SetFont(path, size, flags)

	-- Read back. No return value is consulted, so it cannot matter whether this
	-- particular widget type answers one.
	local ok, got = pcall(fontString.GetFont, fontString)
	if not ok or got == nil or got == "" then
		fontString:SetFont(STANDARD_TEXT_FONT or FALLBACK, size, flags)
	end
	return fontString
end

--- The base point size a role is defined at, so a module can offset from it
--  without hard-coding the number in two places.
function Media:Size(styleName)
	local style = Media.style[styleName]
	return (style and style[2]) or 11
end

--- WoW has no letter-spacing. Section labels in the concepts are widely tracked
--  ("Q U E S T S"), so we fake it by injecting thin spaces between characters.
--
--  Iterates CODE POINTS, not bytes. The first version walked `text:sub(i, i)`,
--  which was safe only while every caller passed a hard-coded ASCII literal. The
--  quest log feeds it zone names straight from the client, and those are
--  localized: byte-splitting "Düstermarschen" tears the ü in half and draws a
--  replacement box, and on ruRU or zhCN every character is multi-byte, so the
--  whole heading becomes a run of garbage.
--
--  CJK is passed through untouched. Those scripts have no letter-spacing
--  convention to imitate and the result reads as broken rather than as tracked.
--- The code point of one UTF-8 character.
local function CodePoint(ch)
	local b1 = ch:byte(1)
	if not b1 then return 0 end
	if b1 < 0xC0 then return b1 end
	if b1 < 0xE0 then
		return (b1 - 0xC0) * 0x40 + ((ch:byte(2) or 0) - 0x80)
	end
	if b1 < 0xF0 then
		return (b1 - 0xE0) * 0x1000 + ((ch:byte(2) or 0) - 0x80) * 0x40
			+ ((ch:byte(3) or 0) - 0x80)
	end
	return 0x10000
end

--- Is this a script with no tracking convention to imitate?
local function IsCJK(cp)
	return (cp >= 0x2E80 and cp <= 0x9FFF)     -- radicals through unified han
		or (cp >= 0xAC00 and cp <= 0xD7AF)     -- hangul
		or (cp >= 0xF900 and cp <= 0xFAFF)     -- compatibility ideographs
		or (cp >= 0xFF00 and cp <= 0xFF60)     -- fullwidth forms
end

function Media:Track(text, spaces)
	if not text or text == "" then return "" end

	local sep = string.rep(" ", spaces or 1)
	local out = {}
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		-- BY CODE POINT, NOT BY LEAD BYTE. This used to bail on any character
		-- whose first byte was in the three-byte range, which is every
		-- three-byte sequence in UTF-8 - so an EM DASH, at U+2014, read as CJK
		-- and turned tracking off for the whole string. The threat chips found
		-- it: two of the four carry a real dash, and both came out untracked
		-- beside two that were.
		if IsCJK(CodePoint(ch)) then return text end
		out[#out + 1] = ch
	end
	return table.concat(out, sep)
end
