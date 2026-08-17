--[[--------------------------------------------------------------------------
	AetherUI :: Fonts

	The game's lettering, all of it, in one pass.

	THE ONE GLOBAL LEVER THIS API HAS. Every FontString the client builds either
	inherits a font object or names its own face. The inheriting ones - which is
	almost all of them - follow that object for as long as they live, including
	strings created long afterwards, and including strings a pool hands back out
	and resets. Change the object and they all change with it.

	There is no equivalent for art. A border or a background is a texture placed
	on a particular frame, and re-skinning one is per-frame work. This is the
	only place where "all of it" is a thing you can actually say.

	WHAT THIS DELIBERATELY DOES NOT DO:

	  * it does not change SIZES. Each object keeps its own, read back off it
	    first, so nothing on screen reflows and a 32-point zone banner is still
	    32 points. This is a change of face and weight only.
	  * it does not change OUTLINES or shadows, for the same reason: they are
	    load-bearing on text drawn over the world.
	  * it does not change COLOURS. Colour is on the string, not the object.
	  * it does not touch a string that names its own face. An addon that calls
	    SetFont explicitly has said what it wants and keeps it.

	OTHER ADDONS COME WITH US, and that is the point rather than a side effect:
	anything drawn with GameFontNormal - which is most of what most addons draw
	with - reads as part of the same interface without its author doing
	anything. An addon that wanted its own lettering set it explicitly and is
	untouched.

	THE LIST IS THE POLICY. There are around 270 font objects in the client and
	no way to enumerate them, so they are written out. Objects inherit from each
	other in the XML, but only at load - remapping SystemFont_Shadow_Med1 does
	NOT reach GameFontNormal at runtime - so these are the leaves, not the
	families.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local FT = A:NewModule("fonts")

local Media = A.Media

local function cfg() return A.Config:Module("fonts") end

--- Which of ours each of the client's wears.
--
--  Grouped by what the type is FOR rather than by name, because the client's
--  names describe colour and size as much as role - GameFontNormal is not
--  normal-weight, it is the gold one.
local FACE = {
	-- Body text, labels, most of every panel in the game.
	regular = {
		"GameFontNormal", "GameFontNormalSmall", "GameFontNormalSmall2",
		"GameFontHighlight", "GameFontHighlightSmall", "GameFontHighlightSmall2",
		"GameFontDisable", "GameFontDisableSmall",
		"GameFontGreen", "GameFontGreenSmall",
		"GameFontRed", "GameFontRedSmall",
		"GameFontWhite", "GameFontDarkGraySmall",
		"GameFontNormalTiny", "GameFontHighlightTiny",
		"SystemFont_Small", "SystemFont_Tiny",
		"QuestFont", "QuestFontNormalSmall", "QuestFontHighlight",
		"SpellFont_Small", "InvoiceTextFontNormal", "InvoiceTextFontSmall",
		"ChatFontNormal", "ChatFontSmall",
		"CombatLogFont",
		"Tooltip_Small",
	},

	-- Anything that is a heading, a title, or the loudest thing on screen.
	semibold = {
		"GameFontNormalLarge", "GameFontHighlightLarge",
		"GameFontNormalHuge", "GameFontHighlightHuge", "GameFontDisableHuge",
		"GameFontNormalMed1", "GameFontHighlightMed1",
		"GameFontNormalMed2", "GameFontHighlightMed2",
		"QuestTitleFont", "QuestTitleFontBlackShadow",
		"MailFont_Large", "SubSpellFont",
		"DialogButtonNormalText", "DialogButtonHighlightText",
		"ZoneTextFont", "SubZoneTextFont", "PVPInfoTextFont",
		"ErrorFont", "Tooltip_Med",
		"BossEmoteNormalHuge",
	},

	-- Numbers. A digit carries more weight than a letter at the same size -
	-- a stack count or a damage number is read at a glance, not at leisure.
	bold = {
		"NumberFont_Small", "NumberFont_Normal_Med",
		"NumberFont_Outline_Small", "NumberFont_Outline_Med",
		"NumberFont_Outline_Large", "NumberFont_Outline_Huge",
		"NumberFont_Shadow_Small", "NumberFont_Shadow_Med",
		"NumberFontNormalSmall", "NumberFontNormal",
		"NumberFontNormalLarge", "NumberFontNormalHuge",
		"GameNormalNumberFont", "WhiteNormalNumberFont",
		"CombatTextFont", "CombatTextFontOutline",
	},
}

--- The frames that carry their OWN font instance instead of inheriting one.
--
--  A MessageFrame is the case: UIErrorsFrame builds a FontString per message
--  from a font set on the FRAME, so remapping ErrorFont does not reach it and
--  "You can't do that yet" stays in Friz Quadrata while everything around it
--  changes. It is the one thing on screen that made the old lettering obvious,
--  and it is the reason this list exists at all.
--
--  Written out because there is no way to find them: a frame does not say
--  whether its font is its own or inherited.
local FRAMES = {
	{ "UIErrorsFrame", "semibold" },
}

-- What each object was, so switching the module off puts the game back.
local originals = {}

-- ---------------------------------------------------------------------------
-- the pass
-- ---------------------------------------------------------------------------

--- One object. Face swapped, everything else left exactly as it was.
local function Dress(name, weight)
	local obj = _G[name]
	if type(obj) ~= "table" or not obj.GetFont or not obj.SetFont then return false end

	local path, size, flags = obj:GetFont()
	-- A font object with no face on it is one this client does not really
	-- have. Setting a size we invented onto it would be worse than skipping.
	if not path or type(size) ~= "number" or size <= 0 then return false end

	if not originals[name] then originals[name] = { path, size, flags } end

	local ours = Media.font[weight] or Media.font.regular
	if not ours then return false end

	obj:SetFont(ours, size, flags)

	-- READ BACK. A face the client cannot load leaves the font unchanged, and
	-- the client says nothing about it - so the only way to know a remap took
	-- is to ask. One that did not is put back rather than left half-applied.
	local got = obj:GetFont()
	if got ~= ours then
		local was = originals[name]
		obj:SetFont(was[1], was[2], was[3])
		originals[name] = nil
		return false
	end
	return true
end

function FT:Dress()
	local n, missed = 0, 0
	for weight, names in pairs(FACE) do
		for _, name in ipairs(names) do
			if Dress(name, weight) then n = n + 1 else missed = missed + 1 end
		end
	end
	-- Same function, same recording, same restore. A frame's font instance and
	-- a font object answer the identical four methods, which is what lets one
	-- pass cover both.
	for _, e in ipairs(FRAMES) do
		if Dress(e[1], e[2]) then n = n + 1 else missed = missed + 1 end
	end
	self.dressed, self.missed = n, missed
	return n
end

function FT:Undress()
	for name, was in pairs(originals) do
		local obj = _G[name]
		if obj and obj.SetFont then obj:SetFont(was[1], was[2], was[3]) end
	end
	originals = {}
	self.dressed, self.missed = 0, 0
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function FT:OnEnable()
	self:Dress()

	-- Again on entering the world, and once more after everything has loaded.
	-- An addon that creates its own font objects, or re-sets one of the
	-- client's, does it at its own load time - which may be after ours.
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() FT:Dress() end)
end

function FT:OnDisable()
	A:UnregisterAllEvents(self)
	self:Undress()
end

--- Nothing on a skin change, and nothing on a config change.
--
--  A face is not a colour. There is no font setting in the profile and no skin
--  that asks for different lettering, so re-running this would be a pass over
--  seventy objects to set them to what they already are.
