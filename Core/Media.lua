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

	-- ability / aura slots
	slotMask    = TEX .. "Slot-Mask",
	slotShade   = TEX .. "Slot-Shade",
	slotGloss   = TEX .. "Slot-Gloss",
	slotEdge    = TEX .. "Slot-Edge",
	slotGlow    = TEX .. "Slot-Glow",         -- drawn at 2x the slot, centred

	-- round things
	circleMask  = TEX .. "Circle-Mask",
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
	chatTab      = { "semibold", 11, "" },
	chatBadge    = { "bold",      8, "" },   -- the channel tag, uppercase
	questTitle   = { "medium",   12, "" },
	questLine    = { "light",    11, "" },   -- objective lines under a quest
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

--- Apply a named style from Media.style to a FontString.
--  Falls back to the game font if the TTF fails to load, so a bad install
--  degrades to "ugly" instead of "invisible text".
function Media:SetFont(fontString, styleName, sizeOverride)
	local style = Media.style[styleName] or Media.style.unitSub
	local path  = Media.font[style[1]] or Media.font.regular
	local size  = sizeOverride or style[2]
	local flags = style[3]

	if not fontString:SetFont(path, size, flags) then
		fontString:SetFont(STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]], size, flags)
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
function Media:Track(text, spaces)
	local sep = string.rep(" ", spaces or 1)
	local out = {}
	for i = 1, #text do out[#out + 1] = text:sub(i, i) end
	return table.concat(out, sep)
end
