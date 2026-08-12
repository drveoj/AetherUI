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
	pill        = TEX .. "Glass-Pill",        -- 512x256, 3-slice, cap 128 (0.25)
	pillEdge    = TEX .. "Glass-Pill-Edge",
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
	divider     = TEX .. "Divider",
	chevron     = TEX .. "Chevron",
	send        = TEX .. "Send",             -- the edit box's paper plane
	badges      = TEX .. "Chat-Badges",      -- the chat line pills, one per row
}

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
	local i = a.index[name]
	if not i then return nil end
	local c, r = i % a.cols, math.floor(i / a.cols)
	return a.file, c / a.cols, (c + 1) / a.cols, r / a.rows, (r + 1) / a.rows
end

--- Point a texture at one. Returns false when the name is unknown, so a caller
--- can fall back rather than draw the whole sheet - which is what a texture
--- with no SetTexCoord does, and it is unmistakable on screen.
function Media:SetIcon(tex, name)
	if not tex then return false end
	local file, l, r, t, b = Media:Icon(name)
	if not file then return false end
	tex:SetTexture(file)
	tex:SetTexCoord(l, r, t, b)
	return true
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
	ttBarLabel   = { "medium",   11, "" },   -- "Health" / "1,240 / 1,240"
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

-- Whether a face is really loadable, asked ONCE per path through a scratch
-- FontString.
--
-- This used to be `if not fontString:SetFont(...) then fall back`, reading the
-- return of the very call being made. That is right for a FontString, whose
-- SetFont answers isValid - and wrong for a font OBJECT, whose SetFont answers
-- nothing at all. `not nil` is true, so every font object we styled fell
-- straight through to FRIZQT__.TTF: the three tooltip objects
-- (GameTooltipHeaderText / GameTooltipText / GameTooltipTextSmall) came out in
-- the client's own face at OUR sizes, which reads as "huge Friz Quadrata"
-- rather than as a font that failed. Every FontString in the addon was fine,
-- which is exactly why it took so long to see: the only things wrong on screen
-- were the three objects, and they are the three we never draw ourselves.
--
-- The harness had the same hole in reverse - its font-object mock returned
-- true, so the fallback was never once exercised in a test.
--
-- Probing separately also means the fallback answers the question it was
-- written for ("is this install missing its TTFs?") rather than the question
-- the call site happened to answer.
local probe, verified = nil, {}
local function Usable(path)
	if verified[path] ~= nil then return verified[path] end

	if probe == nil then
		local ok, fs = pcall(function()
			return UIParent and UIParent:CreateFontString(nil, "BACKGROUND")
		end)
		probe = (ok and fs) or false
	end
	-- No probe, no verdict: assume the face is good rather than condemning
	-- every string in the addon to the game font on the strength of not being
	-- able to ask.
	if not probe then verified[path] = true return true end

	local ok, valid = pcall(probe.SetFont, probe, path, 12, "")
	verified[path] = (ok and valid) and true or false
	return verified[path]
end

--- Apply a named style from Media.style to a FontString OR a font object.
--  Falls back to the game font if the TTF fails to load, so a bad install
--  degrades to "ugly" instead of "invisible text".
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

	if not Usable(path) then
		path = STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]
	end
	fontString:SetFont(path, size, flags)
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
function Media:Track(text, spaces)
	if not text or text == "" then return "" end
	if text:find("[\224-\244]") then return text end

	local sep = string.rep(" ", spaces or 1)
	local out = {}
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		out[#out + 1] = ch
	end
	return table.concat(out, sep)
end
