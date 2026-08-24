--[[--------------------------------------------------------------------------
	AetherUI :: Nameplates

	Concept 7a / 7b. One capsule carries the lot - level badge, name, and a
	health bar inside the pill - tinted by the unit's reaction.

	The plate is DECORATION hung on Blizzard's base frame, never a replacement
	for it. The client creates the base, it is the click target, and it is
	protected: hiding it or moving it in a fight is refused. So we parent a frame
	to it, draw on that, and leave the base entirely alone. Nothing in this file
	touches the base beyond reading it.

	Two things about the client's plates shape everything here, both learned the
	expensive way by other addons:

	  * Base frames are RECYCLED. The plate that was on a kodo is handed straight
	    back out for the next mob that walks up. So a plate is built once per
	    BASE and rebound to whichever unit turns up on it - never built per unit,
	    and never left holding the last tenant's text.

	  * Blizzard's own plate on top is pooled SEPARATELY, re-acquired on every
	    UNIT_ADDED, and comes back shown. Hiding it once when the plate is
	    created is why skinned nameplates ship with Blizzard's flickering
	    underneath. It gets hidden every time a unit arrives, and it gets a hook
	    so it stays that way.

	Friendly units, the target's emphasis and chips, and cast bars are not here
	yet - see the concept for where they land.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local NP = A:NewModule("nameplates")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- The deck's own box: 7 top and bottom, 8 in to the badge, 10 across to the
-- right column, 18 of air on the right so the bar never runs into the cap.
local PAD_L, PAD_R, PAD_Y = 8, 18, 7
local GAP_BADGE, GAP_ROW  = 10, 5
local GAP_CHIP            = 6

-- The friendly form: a 17px class pip and a 6px gap, and no glass at all.
local PIP, GAP_PIP, GAP_GUILD = 20, 6, 1

-- The client draws this for a unit too far above you to read a level from.
local SKULL = "|T" .. [[Interface\TargetingFrame\UI-TargetingFrame-Skull]] .. ":12:12:0:0|t"

local plates = {}    -- base frame  -> our plate
local byUnit = {}    -- unit token  -> our plate
-- Readable from outside, the way the other modules expose their frame
-- lists. A plate is otherwise reachable only as an unnamed child of a
-- client frame, which is not a thing to go hunting for.
NP.byUnit = byUnit

-- Defined with the chips, well below, but UpdateAll calls it.
local UpdateChips

local function cfg() return A.Config:Module("nameplates") end

--- Every other module is drawn at profile.scale and a plate is no different.
--  Left at 1 the capsule is enormous against a HUD at 0.71, which is what the
--  first pass shipped looking like.
local function PlateScale()
	local profile = A.db and A.db.profile
	return (profile and profile.scale or 1) * (cfg().scale or 1)
end

-- ---------------------------------------------------------------------------
-- what a unit is
-- ---------------------------------------------------------------------------

--- ELITE and RARE, as the deck draws them: a filled chip with dark type.
local function Classification(unit)
	local kind = UnitClassification and UnitClassification(unit)
	if kind == "elite" or kind == "worldboss" then
		return "ELITE", Palette.c.ttElite
	end
	if kind == "rare" or kind == "rareelite" then
		return "RARE", Palette.c.npRare
	end
	return nil
end

--- An NPC's title - <Innkeeper>, <Flight Master>, <Beverage Merchant>.
--
--  A nameplate carries no title. The client keeps it on the SECOND LINE of the
--  unit's tooltip, in the same slot a player's guild goes, so the only way to
--  have it is to read it from there.
--
--  Through a tooltip of our own, never GameTooltip: that one belongs to
--  whatever the cursor is over, and driving it here would flicker somebody
--  else's tooltip every time a vendor walked past.
--
--  Cached by NAME, because a title belongs to the creature rather than to the
--  plate. Every Beverage Merchant in the world is one, and this runs on every
--  plate that comes up.
local scanner, titleCache = nil, {}

--- Is this line the unit's LEVEL rather than a title?
--
--  Built from the client's own UNIT_LEVEL_TEMPLATE so it survives a locale. A
--  unit with no title has its level on the second line, and taking that for one
--  puts "Level 15 Beast" under a kodo's name.
local function IsLevelLine(text)
	local template = _G.UNIT_LEVEL_TEMPLATE or "Level %d"
	-- Both %d and %s. Plater's version only replaces %d, which is what the live
	-- client's template carries; anything that formats a "??" level uses %s
	-- instead, and a pattern that missed it would read "Level ?? Elite" as a
	-- perfectly good job title.
	local pattern = template:lower():gsub("%%[ds]", "(%%.*)")
	return text:lower():match(pattern) ~= nil
end

--- What to file a scanned title under.
--
--  NOT THE NAME. A hunter's boar and a wild boar of the same species share
--  a name exactly, and a pet's title is "<Somebody's Pet>" - so the first
--  tamed one scanned put its owner's name under every wild animal of that
--  species for the rest of the session. Which is what happened.
--
--  The GUID carries what was actually wanted. Creature-0-server-instance-
--  zone-ID-spawn: the TYPE tells a pet from a mob, and the ID is per
--  creature kind, so every Beverage Merchant in the world still shares one
--  answer and is scanned once.
--
--  A PET IS KEYED BY ITS WHOLE GUID, because its title is its OWNER'S name:
--  two hunters with the same species of boar share the type and the id and
--  have different titles. Per spawn is the only key that is true for those.
local function TitleKey(guid)
	if not guid then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if not kind then return guid end
	if kind == "Pet" then return guid end
	if not id then return guid end
	return kind .. ":" .. id
end

local function NpcTitle(unit)
	if not unit then return nil end
	if UnitIsPlayer and UnitIsPlayer(unit) then return nil end

	local name = UnitName(unit)
	if not name then return nil end

	-- THE GUID FIRST, because the cache is keyed off it.
	local guid = UnitGUID and UnitGUID(unit)
	if not guid then return nil end
	local key = TitleKey(guid)

	local seen = titleCache[key]
	if seen ~= nil then return seen or nil end

	if not scanner then
		scanner = CreateFrame("GameTooltip", ADDON .. "PlateScanner", nil,
			"GameTooltipTemplate")
	end

	-- SetHyperlink on the unit's GUID, not SetUnit. Plater reads titles this way
	-- on this flavour and it is the reason it works: a scanning tooltip driven
	-- by SetUnit does not reliably fill its lines, and the first version of this
	-- read nothing at all in game while reading fine in the harness.
	--
	-- Owner is WorldFrame, parented to nothing, exactly as Plater has it.
	scanner:SetOwner(_G.WorldFrame or UIParent, "ANCHOR_NONE")
	scanner:SetHyperlink("unit:" .. guid)

	-- COLOURBLIND MODE ADDS A LINE. With it on, the title is on line three and
	-- line two is something else entirely - so the index moves with the CVar.
	local shift = tonumber(GetCVar and GetCVar("colorblindMode") or 0) or 0
	local line = _G[(scanner:GetName() or "") .. "TextLeft" .. (2 + shift)]
	local text = line and line:GetText()

	-- Unbracketed, which is how the client writes it - Plater puts its own
	-- angle brackets on for display and so do we. The first version here only
	-- accepted a bracketed line and therefore accepted nothing.
	local title = nil
	if text and text ~= "" and not IsLevelLine(text) then
		title = text:match("^<(.+)>$") or text
	end

	A:Debug("plate title:", name, key, "line", 2 + shift, "->", tostring(text),
		"=>", tostring(title))

	-- false, not nil: "asked and there is none" has to be tellable from "not
	-- asked yet", or every plain mob is re-scanned on every plate it appears on.
	titleCache[key] = title or false
	return title
end

--- Somebody who lives here, rather than something you fight.
--
--  ATTACKABILITY, not reaction. Reaction cannot answer this: a wandering kodo
--  and a flight master are both non-hostile, and only one of them is a mob. Nor
--  can reputation - an NPC of a faction you have not earned yet reads neutral
--  while still being a person standing behind a counter.
--
--  What separates them is whether you can hit it. A flight master, an innkeeper
--  and a friendly player cannot be attacked and get a name; a kodo, a centaur
--  and anything hostile can, and get the capsule with the level and the health
--  on it, which is what you want to know about a thing you might have to fight.
local function IsNameForm(unit)
	if not unit or cfg().friendlyNames == false then return false end

	local r = UnitReaction and UnitReaction(unit, "player")
	if not UnitCanAttack then return r ~= nil and r >= 5 end

	-- Cannot be attacked at all: a friendly player, an innkeeper, a city guard.
	if not UnitCanAttack("player", unit) then return true end

	-- Attackable, but a person doing a job - the neutral goblin selling ammo,
	-- the flight master of a faction you have not earned yet. Reaction cannot
	-- separate those from a wandering kodo, because both are simply neutral, and
	-- neither can attackability. What does is that the client gives a person
	-- with a job a TITLE and gives a kodo none.
	--
	-- Hostiles are excluded whatever they carry. A named boss has a title too,
	-- and the last thing you want from one of those is its name without its
	-- health.
	if r and r >= 4 and NpcTitle(unit) then return true end

	return false
end

--- Does this plate carry a health bar at all?
--
--  Hostiles always. Neutral only once it is in a fight: a yellow plate means
--  "not my problem yet", and a health bar on one is a row of numbers that
--  answers a question nobody asked.
local function WantsBar(unit)
	-- A name shows a bar only when it is hurt. A street of full green bars over
	-- a city is noise with nothing in it, and the one missing a third of itself
	-- is the only one you wanted to see.
	if IsNameForm(unit) then
		local max = UnitHealthMax(unit) or 0
		return max > 0 and (UnitHealth(unit) or 0) < max
	end

	local reaction = UnitReaction and UnitReaction(unit, "player")
	if not reaction then return true end
	if reaction <= 3 then return true end

	if reaction == 4 then
		if cfg().neutralBarInCombat == false then return true end
		return UnitAffectingCombat and UnitAffectingCombat(unit) or false
	end
	return true
end

-- ---------------------------------------------------------------------------
-- building
-- ---------------------------------------------------------------------------

local function Build(base)
	local c = cfg()

	local f = Glass.CreatePill(base, { fill = "glass", edge = "glassEdge" })
	f:SetFrameStrata(base:GetFrameStrata())
	f:SetPoint("CENTER", base, "CENTER", 0, 0)
	f:Hide()

	local badge = W.CreateBadge(f, { size = c.badgeSize, style = "npBadge" })
	badge:SetPoint("LEFT", f, "LEFT", PAD_L, 0)
	f.badge = badge

	-- THE RAID MARK, riding the badge the way it rides a party member's level
	-- pip and the player capsule's orb. There was none at all before: mark a
	-- mob with a skull and the plate over its head said nothing about it,
	-- which is the one moment a marked mob is worth marking.
	--
	-- Parented to the plate rather than the badge, because the friendly form
	-- hides the badge and the mark still has to be somewhere.
	f.markLayer = W.DecoratorLayer(f, badge)
	f.mark = W.CreateDecorator(f.markLayer, badge, "TOP", { size = 15 })

	local name = W.Text(f, "npName", "LEFT")
	name:SetWordWrap(false)
	f.name = name

	local guild = W.Text(f, "npGuild", "CENTER")
	guild:SetWordWrap(false)
	guild:Hide()
	f.guild = guild

	local chip = W.Pill(f, "npChip", { height = 13, padX = 5 })
	chip:Hide()
	f.chip = chip

	local bar = W.CreateBar(f, { height = c.barHeight, smooth = true })
	bar:SetWidth(c.barWidth)
	f.bar = bar

	-- The right column is name over bar, both left-aligned off the badge, so a
	-- long name truncates against the same rule the bar ends on. Where the name
	-- sits vertically is not fixed - see LayoutRow.
	bar:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -GAP_ROW)

	f:SetSize(PAD_L + c.badgeSize + GAP_BADGE + c.barWidth + PAD_R,
		c.badgeSize + PAD_Y * 2)

	return f
end

-- ---------------------------------------------------------------------------
-- the two forms
-- ---------------------------------------------------------------------------
--
-- A friendly is a NAME, not a plate: no glass, no rim, plain shadowed text.
-- Same frame either way, because a unit's reaction can change under a plate
-- that is already up and rebuilding one mid-fight is how you drop a frame.

local function ApplyForm(f, friendly)
	f._nameForm = friendly
	W.Restyle(f.name, friendly and "npFriendly" or "npName")
	if friendly then
		-- The glass goes entirely, rather than being dimmed. A faint capsule
		-- behind a friendly name is the thing the deck is most explicit about
		-- NOT wanting: the whole point is that a street of people costs you no
		-- furniture at all.
		f:SetFillColor({ 0, 0, 0, 0 })
		f:SetEdgeShown(false)
		f:SetRimGlow(nil)
	else
		f:ApplySkin("glass", "glassEdge")
		f:SetEdgeShown(true)
	end
end

--- The name form: pip, name, guild, sized to what is actually on it.
local function LayoutNameForm(f)
	local unit = f.unit
	local isPlayer = UnitIsPlayer and UnitIsPlayer(unit)
	local level = UnitLevel and UnitLevel(unit) or 0

	-- A pip only for players, and only when the client will tell us a level.
	-- Never a skull: "too far above you to read" is a threat judgement, and a
	-- friendly is not a threat. A friendly whose level is unknown simply has no
	-- pip rather than a skull saying something untrue about them.
	local pip = isPlayer and level > 0

	f.badge:ClearAllPoints()
	f.name:ClearAllPoints()
	f.name:SetWidth(0)          -- sized by its text, not pinned to the bar

	if pip then
		f.badge:Resize(PIP)
		f.badge:SetLabel(tostring(level))
		-- OrbBaseColor, not ClassColor: the deck calls this "a mini version of
		-- the level badge", and the big one on the HUD is drawn from the orb
		-- palette - the hand-authored one where a Shaman is era pink rather
		-- than the client's blue. Two sizes of the same disc should not be two
		-- different colours.
		f.badge:SetColors(Palette:ChipColors(Palette:OrbBaseColor(unit)))
		f.badge:Show()
		f.badge:SetPoint("LEFT", f, "LEFT", 0, 0)
		f.name:SetPoint("LEFT", f.badge, "RIGHT", GAP_PIP, 0)
	else
		f.badge:Hide()
		f.name:SetPoint("LEFT", f, "LEFT", 0, 0)
	end

	-- The line under the name is a player's guild or an NPC's title. Both are
	-- angle-bracketed and both answer "who is this", which is why they share a
	-- row rather than each having one.
	local sub = isPlayer and (GetGuildInfo and GetGuildInfo(unit)) or NpcTitle(unit)
	if sub then
		f.guild:SetText("<" .. sub .. ">")
		f.guild:ClearAllPoints()
		f.guild:SetPoint("TOP", f.name, "BOTTOM", 0, -GAP_GUILD)
		-- A guild is somebody else's affiliation and takes the accent. A title
		-- is part of the same label as the name - "Boorand Plainswind, who is
		-- the innkeeper" - so it takes the name's own colour, stepped back.
		if isPlayer then
			W.Color(f.guild, Palette.c.ttGuild)
		else
			local c = Palette:NameReaction(unit)
			W.Color(f.guild, { c[1], c[2], c[3], 0.75 })
		end
		f.guild:Show()
	else
		f.guild:Hide()
	end

	-- The frame is the text's own size, so anything hung under it - a cast
	-- capsule, a row of chips - centres on the NAME rather than on a box that
	-- is mostly empty.
	local nameW = math.ceil(f.name:GetStringWidth() or 0)
	local w = nameW + (pip and (PIP + GAP_PIP) or 0)
	local h = math.ceil(f.name:GetStringHeight() or 12)
	if guild then h = h + GAP_GUILD + math.ceil(f.guild:GetStringHeight() or 10) end
	f:SetSize(math.max(w, PIP), math.max(h, PIP))

	f.chip:Hide()
end

--- Where the name sits depends on whether anything is under it.
--
--  With a bar the two share the height and the name rides above centre. Without
--  one, a name still anchored for a bar it does not have hangs visibly high in
--  the capsule with a band of empty glass beneath it - which is what every
--  neutral plate looked like. So it centres, and moves up when the bar arrives.
local function LayoutRow(f, hasBar)
	f.name:ClearAllPoints()
	if hasBar then
		f.name:SetPoint("BOTTOMLEFT", f.badge, "RIGHT", GAP_BADGE, GAP_ROW * 0.5)
	else
		f.name:SetPoint("LEFT", f.badge, "RIGHT", GAP_BADGE, 0)
	end
	f._hasBar = hasBar
end

--- Our plate for a base, built once and kept.
local function PlateFor(base)
	local f = plates[base]
	if not f then
		f = Build(base)
		plates[base] = f
	end
	return f
end

-- ---------------------------------------------------------------------------
-- Blizzard's own plate
-- ---------------------------------------------------------------------------

--- Put Blizzard's plate away, and make it stay away.
--
--  Called on every UNIT_ADDED, not once per base: the frame is pooled and
--  re-acquired per unit, so the object here may be one we have never seen and
--  it always arrives shown. The hook is what covers the driver showing it again
--  after us - the two of us answer the same event and the order is not ours to
--  choose.
local function HideBlizzard(base)
	local uf = base.UnitFrame
	if not uf then return end

	uf:Hide()
	if not uf.__aetherHooked then
		uf.__aetherHooked = true
		uf:HookScript("OnShow", function(s)
			if NP.enabled and cfg().hideBlizzard ~= false then s:Hide() end
		end)
	end
end

--- And give it back, for the switch that turns us off.
local function ShowBlizzard(base)
	local uf = base.UnitFrame
	if uf then uf:Show() end
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------

local function UpdateHealth(f)
	local unit = f.unit
	if not unit then return end

	local max = UnitHealthMax(unit) or 0
	f.bar:SetMinMaxValues(0, max > 0 and max or 1)
	f.bar:SetValue(UnitHealth(unit) or 0)

	-- Flat, one colour. SetColors takes a pair for a gradient and a single
	-- triple for a flat fill, and HealthColor hands back the triple: two stops
	-- on a bar this thin read as a wash rather than as a colour, and the
	-- reaction has already said it.
	f.bar:SetColors(Palette:HealthColor(unit))
end

--- What a friendly player's name is coloured with.
--
--  Blue, because that is what "a friendly player" looks like everywhere else in
--  this UI. Class colours are an opt-in and apply to your PARTY only: a street
--  of nine class colours in a capital says something you did not ask about
--  everybody who happens to be standing there.
local function FriendlyNameColor(unit)
	if cfg().partyClassColors and UnitInParty and UnitInParty(unit) then
		-- The orb palette again, not ClassColor: that reads the CLIENT's table,
		-- where a Shaman is blue, and this UI has settled on era pink. One
		-- class palette, or the same person is two colours on two surfaces.
		if UnitIsPlayer and UnitIsPlayer(unit) then
			return Palette:OrbBaseColor(unit)
		end
	end
	return Palette:NameReaction(unit)
end

local function UpdateName(f)
	local unit = f.unit
	if not unit then return end
	local c = cfg()

	f.name:SetText(UnitName(unit) or "")
	W.Color(f.name, f._nameForm and FriendlyNameColor(unit)
		or Palette:NameReaction(unit))

	if f._nameForm then return LayoutNameForm(f) end

	local label, tint = Classification(unit)
	if label then
		f.chip:SetLabel(label)
		f.chip:SetColors(tint, Palette.c.ttEliteInk)
		f.chip:ClearAllPoints()
		f.chip:SetPoint("LEFT", f.name, "LEFT", 0, 0)
		f.chip:Show()
		-- The chip is inline right of the name, so the name gives up the room.
		f.name:SetWidth(math.max(20, c.barWidth - f.chip:GetWidth() - GAP_CHIP))
		f.chip:ClearAllPoints()
		f.chip:SetPoint("LEFT", f.name, "RIGHT", GAP_CHIP, 0)
	else
		f.chip:Hide()
		f.name:SetWidth(c.barWidth)
	end
end

--- The plate form's level badge. Not guarded against the name form: that draws
--  its own pip in LayoutNameForm, which runs after this and owns the badge
--  outright, so a guard here would be a line nothing could ever observe.
local function UpdateBadge(f)
	local unit = f.unit
	if not unit then return end

	local level = UnitLevel and UnitLevel(unit) or 0
	if Palette:SkullLevel(level) then
		f.badge:SetLabel(SKULL)
		-- A skull is the top band by definition, whatever number came with it.
		f.badge:SetColors(Palette:DifficultyColors(level < 0 and 999 or level))
	else
		f.badge:SetLabel(tostring(level))
		f.badge:SetColors(Palette:DifficultyColors(level))
	end
end

local function UpdateBar(f)
	if not f.unit then return end
	local wants = WantsBar(f.unit)
	if f._nameForm then
		-- Under the name (or the guild line), not inside a capsule there is not.
		f.bar:ClearAllPoints()
		f.bar:SetPoint("TOP", f.guild:IsShown() and f.guild or f.name,
			"BOTTOM", 0, -GAP_ROW)
		f.bar:SetWidth(math.max(40, f:GetWidth() or 40))
		if wants then f.bar:Show() UpdateHealth(f) else f.bar:Hide() end
		return
	end
	LayoutRow(f, wants)
	if wants then
		f.bar:Show()
		UpdateHealth(f)
	else
		f.bar:Hide()
	end
end

-- ---------------------------------------------------------------------------
-- target emphasis
-- ---------------------------------------------------------------------------
--
-- The deck's rule: the target is full size and full strength with a rim glow in
-- its reaction, and everything else shrinks to .8 and dims to .62. Reading a
-- fight is mostly the question "which of these is mine", and a screen of
-- identical plates does not answer it.
--
-- Driven by its own OnUpdate rather than A:RegisterTicker, which runs at 0.1s -
-- three frames of a 150ms fade is a stutter, not a transition. The frame is
-- shown only while something is actually moving, so it costs nothing at rest.

local OFF_SCALE, OFF_ALPHA = 0.80, 0.62
local EDGE_OFF, EDGE_ON    = 0.30, 0.55
local GLOW_ALPHA           = 0.28
local FADE                 = 0.15

local moving = {}
local anim = CreateFrame("Frame")
anim:Hide()

--- Paint a plate at wherever its transition has got to.
local function ApplyEmphasis(f)
	local t = f._at or 0

	f:SetScale(PlateScale() * (OFF_SCALE + (1 - OFF_SCALE) * t))
	f:SetAlpha(OFF_ALPHA + (1 - OFF_ALPHA) * t)

	if not f.unit or f._nameForm then return end

	-- THREAT OWNS THE HUE, THE DECK OWNS THE STRENGTH. 16d wants the border and
	-- the glow, and this function already owns both for target emphasis - two
	-- writers on one property is a state that is right until the other one
	-- paints. So the disposition, where there is one, replaces the reaction
	-- colour and sets a floor under the emphasis; the deck keeps scaling above
	-- it. A red plate you are not targeting is still dimmer than the one you
	-- are, which is what both features wanted.
	local th = A:GetModule("threat")
	local c, floor = nil, 0
	if th and th.enabled and th.Plate then c, floor = th:Plate(f.unit) end
	c = c or Palette:NameReaction(f.unit)
	local lit = math.max(t, floor or 0)

	f:SetEdgeColor({ c[1], c[2], c[3], EDGE_OFF + (EDGE_ON - EDGE_OFF) * lit })

	-- The glow is the target's alone - unless a plate is carrying a disposition,
	-- which 16d gives to every engaged hostile whether you are looking at it or
	-- not. Carried at a fraction of its strength on the way in and out, so it
	-- arrives with the scale rather than snapping on at the end of it.
	if lit > 0.01 then
		f:SetRimGlow({ c[1], c[2], c[3], GLOW_ALPHA * lit })
	else
		f:SetRimGlow(nil)
	end
end

local function Step(_, dt)
	local busy = false
	for f in pairs(moving) do
		local want, at = f._want or 0, f._at or 0
		local d = dt / FADE
		if at < want then at = math.min(want, at + d) else at = math.max(want, at - d) end
		f._at = at
		ApplyEmphasis(f)
		if at == want then moving[f] = nil else busy = true end
	end
	if not busy then anim:Hide() end
	return busy
end

anim:SetScript("OnUpdate", Step)

--- Aim a plate at target or off-target. `instant` skips the fade, which is what
--  a plate arriving already-targeted wants: it should come up correct, not
--  swell into place.
local function Emphasise(f, on, instant)
	f._want = on and 1 or 0
	if instant or f._at == nil then
		f._at = f._want
		moving[f] = nil
		ApplyEmphasis(f)
	elseif f._at ~= f._want then
		moving[f] = true
		anim:Show()
	end
end

local function IsTarget(unit)
	return (unit and UnitIsUnit and UnitIsUnit(unit, "target")) and true or false
end

local function UpdateEdge(f)
	if not f.unit then return end
	ApplyEmphasis(f)
end

--- Repaint whichever plates threat has something to say about.
--
--  Called by the threat module on its own tick, because the deck's animation
--  frame runs only while a plate is growing or shrinking - a pulsing border has
--  nothing moving it otherwise. Passing nil repaints everything, which is how
--  the colours go back when the module is switched off.
function NP:RepaintThreat(which)
	for token, f in pairs(byUnit) do
		if f.unit and not f._nameForm and (which == nil or which[token]) then
			ApplyEmphasis(f)
		end
	end
end

--- Restore the capsule's own geometry, which the name form takes apart.
local function LayoutPlateForm(f)
	local c = cfg()
	f.badge:ClearAllPoints()
	f.badge:Resize(c.badgeSize)
	f.badge:SetPoint("LEFT", f, "LEFT", PAD_L, 0)
	f.badge:Show()
	f.guild:Hide()
	f.name:SetWidth(c.barWidth)
	-- The name form re-anchors the bar under the guild line, so put it back
	-- rather than leaving it where a friendly left it. This frame is about to
	-- be a capsule for somebody else.
	f.bar:ClearAllPoints()
	f.bar:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -GAP_ROW)
	f.bar:SetWidth(c.barWidth)
	f:SetSize(PAD_L + c.badgeSize + GAP_BADGE + c.barWidth + PAD_R,
		c.badgeSize + PAD_Y * 2)
end

--- The raid mark, on whichever disc this form of the plate has.
--
--  BOTH FORMS, which is why it is here and not in either layout function.
--  A hostile plate has a level badge and a friendly drawn as a name has
--  none, so the mark rides the badge when there is one and takes the place
--  the badge would have had when there is not. Written into the friendly
--  layout first, where it meant that marking a mob - the only case anybody
--  cares about - drew nothing at all.
local function UpdateMark(f)
	if not f.mark then return end
	f.mark:ClearAllPoints()
	if f.badge and f.badge:IsShown() then
		f.mark:SetPoint("CENTER", f.badge, "TOP", 0, 1)
	else
		f.mark:SetPoint("CENTER", f.name, "LEFT", -10, 0)
	end
	W.SetRaidMark(f.mark, f.unit)
end

local function UpdateAll(f)
	local friendly = IsNameForm(f.unit)
	if friendly ~= f._nameForm then
		ApplyForm(f, friendly)
		if not friendly then LayoutPlateForm(f) end
	end

	UpdateBadge(f)
	UpdateName(f)
	UpdateBar(f)
	UpdateEdge(f)
	UpdateChips(f)
	UpdateMark(f)
end

NP.UpdateAll = UpdateAll

-- ---------------------------------------------------------------------------
-- the cast capsule
-- ---------------------------------------------------------------------------
--
-- Slides in under the plate: icon, spell name, and a short bar. On every plate
-- rather than the target's alone - something winding up a Fireball at you
-- matters whether or not you happen to be looking at it.
--
-- Classic Era does not report other units' casts natively. LibClassicCasterino
-- infers them from the combat log and DOES broadcast for nameplate tokens - it
-- keeps a GUID-to-plate map off the same NAME_PLATE_UNIT_ADDED/REMOVED pair we
-- use - so the callbacks are registered per event and routed by token here.
--
-- KNOWN GAP: the deck greys the capsule's border for an uninterruptible cast.
-- Nothing on this client can tell us that - the library reconstructs a cast
-- from combat log lines and there is no notInterruptible in them - so the state
-- is deliberately NOT built rather than built and left permanently false.

local CAST_H, CAST_ICON, CAST_BAR_W, CAST_BAR_H = 20, 16, 64, 4
local CAST_PAD, CAST_GAP = 5, 4

local function BuildCast(f)
	local cap = Glass.CreatePill(f, { fill = "glassStrong", edge = "castEdge" })
	cap:SetHeight(CAST_H)
	cap:SetPoint("TOP", f, "BOTTOM", 0, -CAST_GAP)
	cap:Hide()

	local icon = cap:CreateTexture(nil, "ARTWORK")
	icon:SetSize(CAST_ICON, CAST_ICON)
	icon:SetPoint("LEFT", cap, "LEFT", CAST_PAD, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cap.icon = icon

	cap.text = W.Text(cap, "npAura", "LEFT")
	cap.text:SetPoint("LEFT", icon, "RIGHT", CAST_GAP, 0)

	local bar = W.CreateBar(cap, { height = CAST_BAR_H, smooth = false })
	bar:SetWidth(CAST_BAR_W)
	bar:SetPoint("RIGHT", cap, "RIGHT", -CAST_PAD, 0)
	bar:SetMinMaxValues(0, 1)
	cap.bar = bar

	f.cast = cap
	return cap
end

local function CastStop(f)
	local cap = f.cast
	if not cap then return end
	cap.state = nil
	cap:Hide()
	cap:SetScript("OnUpdate", nil)
	UpdateChips(f)
end

--- Per frame, not on the shared 0.1s ticker. A cast bar is a continuously
--  moving object and at 10Hz a 2.5s cast advances in 25 visible steps, which
--  reads as stutter next to Blizzard's. Same reasoning as the HUD's own.
local function CastTick(cap, _)
	local st = cap.state
	if not st then return end

	local now = GetTime() * 1000
	local span = (st.finish or 0) - (st.start or 0)
	if span <= 0 or now >= st.finish then return CastStop(cap:GetParent()) end

	local pct = (now - st.start) / span
	cap.bar:SetValue(st.channel and (1 - pct) or pct)
end

local function CastStart(f, channel)
	if not f.unit then return end

	local UF = A:GetModule("unitframes")
	local info = UF and UF.CastInfo
	if not info then return end

	local name, _, icon, startMs, finishMs = info(f.unit, channel)
	if not name or not startMs or not finishMs then return CastStop(f) end

	local cap = f.cast or BuildCast(f)
	cap.state = { channel = channel, start = startMs, finish = finishMs }
	cap.icon:SetTexture(icon)
	cap.text:SetText(name)
	W.Color(cap.text, Palette.c.npChipInk)
	cap.bar:SetColors(Palette.c.cast)

	-- Sized to the name, so a long one is not cropped and a short one does not
	-- leave the capsule rattling.
	cap:SetWidth(CAST_PAD * 2 + CAST_ICON + CAST_GAP
		+ math.ceil(cap.text:GetStringWidth() or 0) + CAST_GAP + CAST_BAR_W)

	CastTick(cap, 0)
	cap:Show()
	cap:SetScript("OnUpdate", CastTick)
	UpdateChips(f)
end

-- ---------------------------------------------------------------------------
-- your debuffs, under the target
-- ---------------------------------------------------------------------------
--
-- Yours only, and on the target only. Every debuff on every plate is a wall of
-- icons that says nothing; the four things YOU put on the thing you are hitting
-- is the question a fight actually asks.
--
-- Read through Auras.lua's GetAura rather than a second copy of the
-- C_UnitAuras/UnitAura fallback, and asked for with PLAYER in the filter - the
-- suite's target carries a Bleeding somebody else cast, precisely so forgetting
-- that shows up.

local CHIP_MAX, CHIP_H, CHIP_ICON, CHIP_GAP, CHIP_PAD = 4, 17, 13, 4, 5

local function BuildChip(f)
	local chip = Glass.CreatePill(f, { fill = "glass", edge = "castEdge" })
	chip:SetHeight(CHIP_H)

	local icon = chip:CreateTexture(nil, "ARTWORK")
	icon:SetSize(CHIP_ICON, CHIP_ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	chip.icon = icon

	chip.text = W.Text(chip, "npAura", "LEFT")
	return chip
end

--- One chip: an icon, a name, and what is left of it. The "+2" chip has no
--  icon, so the text takes the whole pill.
local function SetChip(chip, texture, label)
	chip.text:ClearAllPoints()
	if texture then
		chip.icon:SetTexture(texture)
		chip.icon:ClearAllPoints()
		chip.icon:SetPoint("LEFT", chip, "LEFT", CHIP_PAD, 0)
		chip.icon:Show()
		chip.text:SetPoint("LEFT", chip.icon, "RIGHT", CHIP_GAP, 0)
	else
		chip.icon:Hide()
		chip.text:SetPoint("LEFT", chip, "LEFT", CHIP_PAD, 0)
	end

	chip.text:SetText(label or "")
	W.Color(chip.text, Palette.c.npChipInk)

	local w = (texture and (CHIP_ICON + CHIP_GAP) or 0)
		+ math.ceil(chip.text:GetStringWidth() or 0)
	chip:SetWidth(w + CHIP_PAD * 2)
	chip:Show()
end

--- Mine, in the order the client hands them over.
local function MyDebuffs(unit)
	local out = {}
	local Aur = A:GetModule("auras")
	local get = Aur and Aur.GetAura
	if not get then return out end

	for i = 1, 40 do
		local name, tex, _, _, duration, expiration, mine = get(unit, i, "HARMFUL|PLAYER")
		if not name then break end
		-- Belt and braces: the filter should have done this, but sourceUnit is
		-- nil for a fair few auras and GetAura is the thing that knows.
		if mine ~= false then
			out[#out + 1] = { name = name, tex = tex,
				duration = duration, expiration = expiration }
		end
	end
	return out
end

function UpdateChips(f)
	f.chips = f.chips or {}

	-- Off-target plates carry none at all, which is most of what makes the
	-- target's readable.
	local mine = (f.unit and (f._want or 0) == 1) and MyDebuffs(f.unit) or {}

	local shown = math.min(#mine, CHIP_MAX)
	for i = 1, shown do
		f.chips[i] = f.chips[i] or BuildChip(f)
		local a = mine[i]
		local left = W.AuraTime(a.expiration, a.duration)
		SetChip(f.chips[i], a.tex, left ~= "" and (a.name .. " · " .. left) or a.name)
	end

	local over = #mine - shown
	if over > 0 then
		shown = shown + 1
		f.chips[shown] = f.chips[shown] or BuildChip(f)
		SetChip(f.chips[shown], nil, "+" .. over)
	end

	for i = shown + 1, #f.chips do f.chips[i]:Hide() end
	f._chipCount = shown

	-- Centred as a row under the capsule.
	local total = 0
	for i = 1, shown do total = total + (f.chips[i]:GetWidth() or 0) end
	total = total + CHIP_GAP * math.max(0, shown - 1)

	-- Under the cast capsule when there is one. Both want the space beneath the
	-- plate, and a row of chips through the middle of a cast bar is neither.
	local below = (f.cast and f.cast:IsShown()) and f.cast or f

	local x = -total / 2
	for i = 1, shown do
		local chip = f.chips[i]
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", below, "BOTTOM", x, -CHIP_GAP)
		x = x + (chip:GetWidth() or 0) + CHIP_GAP
	end
end

--- The countdown has to move on its own - nothing fires an event for a second
--  passing. Only plates that actually have chips, which is at most one.
local function TickChips()
	for _, f in pairs(byUnit) do
		if (f._chipCount or 0) > 0 then UpdateChips(f) end
	end
end

-- ---------------------------------------------------------------------------
-- asking the client for friendly plates
-- ---------------------------------------------------------------------------
--
-- Without this there is nothing to draw on. The engine only makes a nameplate
-- for a friendly unit when it is asked to; left alone it renders them as
-- floating name text instead - the client's yellow name with its <Innkeeper>
-- line - which is a different system entirely and never reaches this module.
-- The friendly form was complete and invisible for exactly that reason.
--
-- Only ever turned ON. The off state is the player's own client setting and not
-- ours to clear: switching friendlyNames off makes friendlies wear the capsule,
-- it does not go and edit their console variables.
--
-- Probed rather than assumed - SetCVar on a name this client does not have
-- raises, and the set has moved between flavours, which is why the legacy
-- nameplateShowFriends is in the list and why nothing here writes blind.
local FRIENDLY_CVARS = {
	"nameplateShowFriendlyPlayers",
	"nameplateShowFriends",           -- what older clients called it
	"nameplateShowFriendlyNpcs",
	-- Pets, imps, water elementals, everything somebody summoned. Without these
	-- they keep the client's own floating name while their owner standing next
	-- to them wears ours, which reads as the addon having missed something -
	-- and it had.
	"nameplateShowFriendlyPlayerMinions",
	"nameplateShowEnemyMinions",
	"nameplateShowEnemyMinus",
}

--- `initial` means "we are setting up, or the player just changed a setting",
--  as opposed to "something moved a console variable and we are putting ours
--  back". The difference matters for exactly one of these - see below.
local function ApplyCVars(initial)
	if cfg().friendlyNames == false then return end

	-- Refused in combat. Queued rather than dropped, or a fight starting while
	-- the UI loads costs you friendly plates until the next reload.
	if InCombatLockdown and InCombatLockdown() then
		NP._cvarsPending = true
		return
	end

	-- Zen has these on loan while it is running and gives them back when it
	-- ends. Writing over the top puts every friendly plate back on screen in
	-- the middle of a zen - which is the one thing zen is for - and leaves Zen
	-- restoring a value it never took. It borrowed OUR value, so there is
	-- nothing to redo afterwards.
	local Zen = A:GetModule("zen")
	if Zen and Zen._worldText then
		NP._cvarsPending = true
		return
	end

	NP._cvarsPending = nil

	-- Written only when it is not already right, which makes this idempotent -
	-- and that is what lets CVAR_UPDATE re-run it without the two of us setting
	-- each other off forever.
	for _, name in ipairs(FRIENDLY_CVARS) do
		if GetCVar and GetCVar(name) ~= nil and GetCVar(name) ~= "1" then
			pcall(SetCVar, name, "1")
		end
	end

	-- How far out the client makes a plate. Past it there is none, and the
	-- engine draws its own floating name instead - so the boundary shows up as
	-- the typeface changing at a fixed distance, which is what it looked like.
	-- Clamped to the range Blizzard's own slider offers on this flavour.
	-- Without this the client only makes a plate for your target and whatever is
	-- fighting you. Everything else - the vendor, the flight master, the kodo
	-- standing in a field - keeps the engine's floating name, which is why they
	-- were in the client's font with none of our treatment on them at all.
	--
	-- SET, then left alone. This one is bound to a key: V toggles it, and people
	-- toggle it constantly. Putting it back every time it moves - which is what
	-- the others get - would mean pressing V did nothing, and the player would
	-- be fighting an addon over their own keybind. Zen borrows it too, and is
	-- entitled to give it back off if that is how it found it.
	if initial and cfg().alwaysShow ~= false and GetCVar
		and GetCVar("nameplateShowAll") ~= nil
		and GetCVar("nameplateShowAll") ~= "1" then
		pcall(SetCVar, "nameplateShowAll", "1")
	end

	local far = tonumber(cfg().maxDistance)
	if far and GetCVar and GetCVar("nameplateMaxDistance") ~= nil then
		far = math.max(20, math.min(41, far))
		if GetCVar("nameplateMaxDistance") ~= tostring(far) then
			pcall(SetCVar, "nameplateMaxDistance", tostring(far))
		end
	end
end

-- ---------------------------------------------------------------------------
-- the driver
-- ---------------------------------------------------------------------------

local function OnUnitAdded(_, _, token)
	if not token then return end
	local base = C_NamePlate and C_NamePlate.GetNamePlateForUnit(token)
	-- nil for a forbidden plate, which is the client telling us to keep out.
	if not base then return end

	if cfg().hideBlizzard ~= false then HideBlizzard(base) end

	local f = PlateFor(base)
	f.unit = token
	byUnit[token] = f
	-- Arrives correct rather than swelling into place.
	Emphasise(f, IsTarget(token), true)
	UpdateAll(f)
	f:Show()

	-- And asked again on the next frame. A plate can arrive before the client
	-- will answer UnitIsUnit about it - notably when a batch of them comes back
	-- at once, which is what happens the moment zen gives the nameplate CVars
	-- back. Answer "not the target" then and nothing asks again until you click
	-- something, so your own target sits at off-target dim while everything
	-- else on screen has already brightened.
	if _G.C_Timer and _G.C_Timer.After then
		_G.C_Timer.After(0, function()
			if f.unit then Emphasise(f, IsTarget(f.unit), true) end
		end)
	end
end

local function OnUnitRemoved(_, _, token)
	if not token then return end
	local f = byUnit[token]
	if not f then return end

	-- Cleared, not just hidden. This frame is going back out on somebody else.
	f:Hide()
	f.unit = nil
	f.name:SetText("")
	f.badge:SetLabel("")
	f.chip:Hide()
	f:SetRimGlow(nil)
	for i = 1, #(f.chips or {}) do f.chips[i]:Hide() end
	f._chipCount = 0
	if f.cast then
		f.cast.state = nil
		f.cast:Hide()
		f.cast:SetScript("OnUpdate", nil)
	end
	moving[f] = nil
	byUnit[token] = nil
end

local function OnUnitEvent(_, _, token)
	local f = token and byUnit[token]
	if f then UpdateBar(f) end
end

--- Both plates move on a target change - the one that gained it and the one
--  that lost it - so this asks every plate up rather than tracking the last.
local function OnTargetChanged()
	for _, f in pairs(byUnit) do
		Emphasise(f, IsTarget(f.unit))
		-- Chips follow focus rather than fading with it: they are information,
		-- not decoration, and a row of them dimming to .62 under a plate you
		-- have stopped caring about is just clutter with a countdown on it.
		UpdateChips(f)
	end
end

local function OnAuraChanged(_, _, token)
	local f = token and byUnit[token]
	if f then UpdateChips(f) end
end

--- Reaction can move under a plate that is already up - a neutral mob you pull,
--  a player who flags. Everything on the plate is coloured by it.
local function OnFactionChanged(_, _, token)
	local f = token and byUnit[token]
	if f then UpdateAll(f) end
end

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

function NP:OnEnable()
	A:RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", OnUnitAdded)
	A:RegisterEvent(self, "NAME_PLATE_UNIT_REMOVED", OnUnitRemoved)
	A:RegisterEvent(self, "UNIT_HEALTH", OnUnitEvent)
	A:RegisterEvent(self, "UNIT_MAXHEALTH", OnUnitEvent)
	A:RegisterEvent(self, "UNIT_FACTION", OnFactionChanged)
	-- RAID_TARGET_UPDATE CARRIES NO UNIT. It is one event for the whole
	-- group's marks at once, so every plate on screen has to be asked - the
	-- alternative is a plate still wearing a skull that has moved to somebody
	-- else.
	A:RegisterEvent(self, "RAID_TARGET_UPDATE", function()
		for _, f in pairs(byUnit) do UpdateAll(f) end
	end)
	A:RegisterEvent(self, "PLAYER_TARGET_CHANGED", OnTargetChanged)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
		if NP._cvarsPending then ApplyCVars(true) end
	end)

	-- Somebody else moved a console variable. Ours get put back.
	--
	-- Addons that hide the world's text around a cutscene or a dialogue - and
	-- DialogueUI is one - back these up, zero them, and restore the backup
	-- afterwards. Take that backup before we have set ours and the restore
	-- writes the OLD values over the top, which is a nameplate module that
	-- silently stops working and never hears about it.
	--
	-- Generic on purpose: it is not about that addon, it is about the fact that
	-- a console variable has no owner. Safe to run on its own event because
	-- ApplyCVars only writes what is actually wrong, and defers to Zen, which
	-- moves the same ones on purpose.
	A:RegisterEvent(self, "CVAR_UPDATE", function() ApplyCVars(false) end)
	A:RegisterEvent(self, "UNIT_AURA", OnAuraChanged)

	-- Casts. THE NATIVE EVENTS DO FIRE FOR A NAMEPLATE UNIT on this build, and
	-- this comment used to say they never did - written when that was true and
	-- left standing when it stopped being. Measured, not assumed: /aether diag
	-- counts both sources, and a fight reports native events in the same
	-- numbers as the library's.
	--
	-- LibClassicCasterino is relayed alongside them and is going nowhere.
	-- MEASURED, NOT ASSUMED: over a few fights, native 31, library 35, and
--  twenty-one of the library's were casts the client never announced at all.
--  Both sources are real and neither is a superset of the other, which is why
--  both are wired.
	local function onStart(_, _, token)   local f = token and byUnit[token]; if f then CastStart(f, false) end end
	local function onChannel(_, _, token) local f = token and byUnit[token]; if f then CastStart(f, true) end end
	local function onStop(_, _, token)    local f = token and byUnit[token]; if f then CastStop(f) end end
	local function onDelayed(_, _, token)
		local f = token and byUnit[token]
		if f and f.cast and f.cast.state then CastStart(f, f.cast.state.channel) end
	end

	local CAST_EVENTS = {
		UNIT_SPELLCAST_START           = onStart,
		UNIT_SPELLCAST_CHANNEL_START   = onChannel,
		UNIT_SPELLCAST_DELAYED         = onDelayed,
		UNIT_SPELLCAST_CHANNEL_UPDATE  = onDelayed,
		UNIT_SPELLCAST_STOP            = onStop,
		UNIT_SPELLCAST_FAILED          = onStop,
		UNIT_SPELLCAST_INTERRUPTED     = onStop,
		UNIT_SPELLCAST_CHANNEL_STOP    = onStop,
	}
	for event, fn in pairs(CAST_EVENTS) do
		-- Counted on the way past. A nameplate token is never the player, so
		-- anything arriving here at all is the client reporting somebody
		-- else's cast - which it has never done on this flavour.
		A:RegisterEvent(self, event, function(owner, ev, token)
			A.castSource.native = A.castSource.native + 1
			-- Stamped so the relay below can tell a duplicate from a cast
			-- only the library saw. Keyed on unit AND event, because a stop
			-- arriving from one source and a start from the other is two
			-- different facts about the same cast.
			A.castSource.seen[tostring(token) .. ev] =
				(GetTime and GetTime()) or 0
			return fn(owner, ev, token)
		end)
	end

	local LibCC = LibStub and LibStub("LibClassicCasterino", true)
	if LibCC and not self._ccHooked then
		self._ccHooked = true
		local function relay(event, token)
			A.castSource.lib = A.castSource.lib + 1
			-- A SECOND EITHER SIDE. The library infers from the combat log, so
			-- its copy of an event the client also sent arrives near it rather
			-- than with it - and a window is the only honest way to pair them.
			local at = (GetTime and GetTime()) or 0
			local when = A.castSource.seen[tostring(token) .. event]
			if not when or math.abs(at - when) > 1 then
				A.castSource.only = A.castSource.only + 1
			end
			local fn = CAST_EVENTS[event]
			-- The library's handler signature is (event, unit); ours is
			-- (owner, event, unit). Line them up rather than writing a second
			-- set of handlers that can drift from the first.
			if fn then fn(nil, event, token) end
		end
		for event in pairs(CAST_EVENTS) do
			-- CallbackHandler embeds RegisterCallback with the TARGET first:
			-- lib.RegisterCallback(target, event, handler).
			pcall(LibCC.RegisterCallback, self, event, relay)
		end
	end
	A:RegisterTicker(self, TickChips)
	A:RegisterEvent(self, "UNIT_FLAGS", OnUnitEvent)

	ApplyCVars(true)

	-- Plates already up when we are switched on mid-session.
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, base in ipairs(C_NamePlate.GetNamePlates()) do
			if base.unitToken then OnUnitAdded(nil, nil, base.unitToken) end
		end
	end
end

function NP:OnDisable()
	A:UnregisterAllEvents(self)
	A:UnregisterTicker(self)
	for base, f in pairs(plates) do
		f:Hide()
		f.unit = nil
		ShowBlizzard(base)
	end
	wipe(byUnit)
end

function NP:OnSkinChanged()
	for _, f in pairs(plates) do
		if f.unit then UpdateAll(f) end
	end
end

function NP:OnConfigChanged()
	local c = cfg()
	ApplyCVars(true)
	for base, f in pairs(plates) do
		f.bar:SetWidth(c.barWidth)
		f.bar:SetHeight(c.barHeight)
		f.badge:Resize(c.badgeSize)
		f:SetSize(PAD_L + c.badgeSize + GAP_BADGE + c.barWidth + PAD_R,
			c.badgeSize + PAD_Y * 2)
		if c.hideBlizzard == false then ShowBlizzard(base) else HideBlizzard(base) end
		-- Emphasis owns the scale, because it multiplies profile.scale by the
		-- off-target .8. Setting the raw scale here would flip every unfocused
		-- plate to full size until the next target change.
		ApplyEmphasis(f)
		if f.unit then UpdateAll(f) end
	end
end

-- Exposed for the suite: which plate belongs to a base, and all of them.
NP.plateFor = PlateFor
NP.plates = plates
NP.step = Step
NP.moving = moving
NP.updateChips = UpdateChips
NP.castStart = CastStart
NP.applyCVars = ApplyCVars
NP.applyEmphasis = ApplyEmphasis
