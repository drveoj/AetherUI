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

-- The client draws this for a unit too far above you to read a level from.
local SKULL = "|T" .. [[Interface\TargetingFrame\UI-TargetingFrame-Skull]] .. ":12:12:0:0|t"

local plates = {}    -- base frame  -> our plate
local byUnit = {}    -- unit token  -> our plate

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

--- Does this plate carry a health bar at all?
--
--  Hostiles always. Neutral only once it is in a fight: a yellow plate means
--  "not my problem yet", and a health bar on one is a row of numbers that
--  answers a question nobody asked.
local function WantsBar(unit)
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
	f:SetScale(PlateScale())
	f:SetPoint("CENTER", base, "CENTER", 0, 0)
	f:Hide()

	local badge = W.CreateBadge(f, { size = c.badgeSize, style = "npBadge" })
	badge:SetPoint("LEFT", f, "LEFT", PAD_L, 0)
	f.badge = badge

	local name = W.Text(f, "npName", "LEFT")
	name:SetWordWrap(false)
	f.name = name

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

local function UpdateName(f)
	local unit = f.unit
	if not unit then return end
	local c = cfg()

	f.name:SetText(UnitName(unit) or "")
	W.Color(f.name, Palette:NameReaction(unit))

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
	LayoutRow(f, wants)
	if wants then
		f.bar:Show()
		UpdateHealth(f)
	else
		f.bar:Hide()
	end
end

local function UpdateEdge(f)
	if not f.unit then return end
	local c = Palette:NameReaction(f.unit)
	f:SetEdgeColor({ c[1], c[2], c[3], 0.30 })
end

local function UpdateAll(f)
	UpdateBadge(f)
	UpdateName(f)
	UpdateBar(f)
	UpdateEdge(f)
end

NP.UpdateAll = UpdateAll

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
	UpdateAll(f)
	f:Show()
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
	byUnit[token] = nil
end

local function OnUnitEvent(_, _, token)
	local f = token and byUnit[token]
	if f then UpdateBar(f) end
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
	A:RegisterEvent(self, "UNIT_FLAGS", OnUnitEvent)

	-- Plates already up when we are switched on mid-session.
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, base in ipairs(C_NamePlate.GetNamePlates()) do
			if base.unitToken then OnUnitAdded(nil, nil, base.unitToken) end
		end
	end
end

function NP:OnDisable()
	A:UnregisterAllEvents(self)
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
	for base, f in pairs(plates) do
		f:SetScale(PlateScale())
		f.bar:SetWidth(c.barWidth)
		f.bar:SetHeight(c.barHeight)
		f.badge:Resize(c.badgeSize)
		f:SetSize(PAD_L + c.badgeSize + GAP_BADGE + c.barWidth + PAD_R,
			c.badgeSize + PAD_Y * 2)
		if c.hideBlizzard == false then ShowBlizzard(base) else HideBlizzard(base) end
		if f.unit then UpdateAll(f) end
	end
end

-- Exposed for the suite: which plate belongs to a base, and all of them.
NP.plateFor = PlateFor
NP.plates = plates
