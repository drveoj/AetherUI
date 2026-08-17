--[[--------------------------------------------------------------------------
	AetherUI :: Messages

	The text the game throws at the middle of your screen and takes away again:
	"You can't do that yet", the zone name as you cross a border, a raid warning,
	a boss emote. Every one of them was still in Friz Quadrata while the rest of
	the interface was not, which on a HUD this quiet is the loudest thing on it.

	A FACE CHANGE AND NOTHING ELSE. Not the size, not the position, not the
	colour, not how long a message stays up:

	  * the SIZE is whatever the client's own font object was using. Reskin.Font
	    reads it back before it swaps the face, so nothing on screen moves and a
	    zone banner is the same height it always was.
	  * the OUTLINES are kept exactly as the client has them. These strings are
	    drawn over the world with nothing behind them, and a zone name in our
	    lettering with the thick outline dropped is unreadable over snow.
	  * the COLOUR is the client's and stays that way. An error is red and an
	    info line is yellow because UIErrorsMixin passes RED_FONT_COLOR and
	    YELLOW_FONT_COLOR per message; that is the game telling you which kind of
	    thing just happened, and it is not ours to restate.

	UIErrorsFrame is a MessageFrame, so the font lives on the FRAME rather than
	on a child string - it builds its own FontStrings per message from that.
	Everything else here is a named FontString and is set directly.

	Reversible, like every other reskin in this addon: the original font is
	recorded the first time we touch a string, and switching the module off puts
	it back.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local MSG = A:NewModule("messages")

local Reskin = A.Reskin

local function cfg() return A.Config:Module("messages") end

--- What we re-letter, and as what.
--
--  Written out rather than discovered, because these are the client's own
--  globals and the list is the policy. A name that does not exist on a given
--  client is skipped, not guessed at: RaidBossEmoteFrame is absent on some
--  builds and its slots are nil, and reaching for them is a load-time error in
--  a module that has no business failing.
local STRINGS = {
	{ "ZoneTextString",       "zoneName"   },   -- the zone, crossing a border
	{ "PVPInfoTextString",    "zoneSub"    },   -- "Contested Territory"
	{ "SubZoneTextString",    "zoneSub"    },
	{ "PVPArenaTextString",   "zoneSub"    },
	{ "RaidWarningFrameSlot1", "raidNotice" },
	{ "RaidWarningFrameSlot2", "raidNotice" },
	{ "RaidBossEmoteFrameSlot1", "raidNotice" },
	{ "RaidBossEmoteFrameSlot2", "raidNotice" },
}

--- The MessageFrames, whose font is on the frame itself.
local FRAMES = {
	{ "UIErrorsFrame", "errMessage" },
}

-- ---------------------------------------------------------------------------
-- dressing
-- ---------------------------------------------------------------------------

--- Remember what it was, once.
--
--  ONCE, and only the first time: Dress runs again on every skin change and on
--  every config change, and a recording made on the second pass would record
--  our own font as the client's and make Undress a no-op.
local function Remember(obj)
	if obj.__aetherFont or not obj.GetFont then return end
	local path, size, flags = obj:GetFont()
	if path then obj.__aetherFont = { path, size, flags } end
end

local function DressOne(obj, style)
	if not obj or not obj.SetFont then return false end
	Remember(obj)
	Reskin.Font(obj, style)
	obj.__aetherStyled = style
	return true
end

--- Safe to call repeatedly, and called that way.
function MSG:Dress()
	local n = 0
	for _, e in ipairs(FRAMES) do
		if DressOne(_G[e[1]], e[2]) then n = n + 1 end
	end
	for _, e in ipairs(STRINGS) do
		if DressOne(_G[e[1]], e[2]) then n = n + 1 end
	end
	self.dressed = n
	return n
end

--- Blizzard's own lettering back.
local function UndressOne(obj)
	if not obj or not obj.__aetherFont then return end
	local f = obj.__aetherFont
	obj:SetFont(f[1], f[2], f[3])
	obj.__aetherFont = nil
	obj.__aetherStyled = nil
	-- The size Reskin.Font recorded goes too, or re-enabling the module would
	-- restyle from a stale one after the player has changed UI scale.
	obj._aetherSize = nil
	obj._aetherStyle = nil
end

function MSG:Undress()
	for _, e in ipairs(FRAMES) do UndressOne(_G[e[1]]) end
	for _, e in ipairs(STRINGS) do UndressOne(_G[e[1]]) end
	self.dressed = 0
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function MSG:OnEnable()
	self:Dress()

	-- Again on entering the world. These frames belong to Blizzard_UIParent and
	-- exist by the time we run, but a zone change is also when the strings are
	-- next drawn - and re-dressing something already dressed costs one SetFont.
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() MSG:Dress() end)
end

function MSG:OnDisable()
	A:UnregisterAllEvents(self)
	self:Undress()
end

--- NO OnSkinChanged, and NO OnConfigChanged, deliberately.
--
--  Every other reskin in this addon has both, because every other reskin sets
--  colours out of the palette. This one sets a FACE and nothing else: the
--  colours here are the client's, the sizes are the client's, and there is no
--  font setting in the profile for a config change to have moved. A hook that
--  re-ran SetFont with identical arguments on every skin change would be work
--  nobody asked for and one more thing to keep working.
--
--  If a font ever becomes a setting, this is where it comes back.
