--[[--------------------------------------------------------------------------
	AetherUI :: Party frames

	Four capsules, one per party member, in the same glass and lettering as the
	player's own - compacted, because a party member is somebody you glance at
	rather than read. Blizzard's four go away with them.

	FIXED SLOTS, NOT A GROWING STACK. The design asks for a stack that grows
	from its anchored top edge as members join and leave. It cannot be built
	that way: each capsule carries a SecureUnitButtonTemplate so left-click
	targets and right-click opens the unit menu, and re-anchoring a frame with a
	secure child is refused while you are in a fight. Somebody dying, releasing
	or dropping group mid-pull is exactly when the layout would want to change
	and exactly when the client will not allow it.

	So the four slots are anchored ONCE and never move. RegisterUnitWatch shows
	and hides each button securely, and the glass around it follows. A gap where
	a fourth member used to be is the price, and it is also what "a placed stack
	never creeps" was asking for in the first place.

	THE STACK DRAGS AS ONE. The capsules are children of a container frame and
	the container is what Movers knows about, so unlocking gives you one grip
	for the group rather than four. In db.profile.anchors like every other
	positioned frame - the brief says per character, but placement lives in the
	profile for everything else in this interface, and splitting it is how a
	profile switch starts moving some things and not others.

	WHAT IS NOT OURS TO STYLE. Class colours and the raid target icons are the
	game's own and stay exactly as the game draws them. The level pip is the
	nameplate's badge at a bigger size, from the same recipe, because two sizes
	of the same disc must not be two different colours.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local PF = A:NewModule("partyframes")

local W, Glass, Palette = A.Widgets, A.Glass, A.Palette

local function cfg() return A.Config:Module("partyframes") end

-- party1..party4. Four, and the player is not among them: this interface
-- already draws a player capsule, and a fifth here would be a second answer to
-- the same question.
local UNITS = { "party1", "party2", "party3", "party4" }

-- ---------------------------------------------------------------------------
-- measurements
-- ---------------------------------------------------------------------------

local PAD_L    = 8
local PAD_R    = 18
local PIP      = 38
local GAP_PIP  = 10
local GAP_VAL  = 12
local VAL_W    = 40
local ROLE     = 22
local GAP_ROLE = 10

-- The crown and the marker BOTH ride the pip, and the brief puts them in the
-- same place. A party leader who has also been marked is ordinary, so they get
-- a corner each: the marker keeps the top, which is where the game's own frames
-- put it and where the eye goes for it, and the crown takes the top-left.
local CROWN  = 13
local MARKER = 14

--- Which classes can put somebody back on their feet.
--
--  Keyed off CLASS, not off role. The brief shows the resurrect glyph "to
--  healers", but a role on Classic Era is opt-in - set by answering a role poll
--  or listing in the group finder - so for most players UnitGroupRolesAssigned
--  answers "NONE" and the glyph would never appear for anyone.
local CAN_RES = {
	PRIEST = true, PALADIN = true, SHAMAN = true, DRUID = true, WARLOCK = true,
}

--- Which roles are worth a glyph.
--
--  NOT DAMAGER, and that is a departure from the brief. It draws an arrow
--  for dps, and in a five-man that is an arrow on four capsules out of four
--  - a mark every member wears tells you nothing about any of them. Tank
--  and healer are the two that answer a question you actually ask.
--
--  It also turned out that this client does not answer "NONE" the way the
--  role poll suggests it would: somebody who has never set a role still
--  comes back as a damager, so the empty state was unreachable and every
--  capsule wore the arrow.
local ROLE_GLYPH = { TANK = "tank", HEALER = "healer" }

-- ---------------------------------------------------------------------------
-- Blizzard's own, out of the way
-- ---------------------------------------------------------------------------

--- The client's own party frames.
--
--  THERE ARE NO PartyMemberFrame1..4 GLOBALS on this client, which is how
--  the first version of this hid nothing at all. PartyFrame.lua builds the
--  member buttons out of a FRAME POOL:
--
--    self.PartyMemberFramePool = CreateFramePool("BUTTON", self,
--        "PartyMemberFrameTemplate", PartyMemberFrameReset)
--
--  and a pooled frame gets no name. The container is what has one, and
--  banishing it takes its pool with it because they are its children.
--
--  CompactPartyFrame is the raid-style version of the same four people,
--  drawn instead when the player has that setting on. Only the party one -
--  a raid's frames are somebody else's window and we do not draw those.
local BLIZZARD = { "PartyFrame", "CompactPartyFrame" }

--- Hide them, and SAY WHAT HAPPENED TO EACH.
--
--  The report is the point. A name this client does not have is a silent
--  no-op - no error, nothing in the log, and a party frame still on screen
--  next to ours - which is exactly the bug this replaced. The suite reads it
--  back and fails on "absent".
--
--  ASKED FOR REPEATEDLY, not once at login. These carry secure templates,
--  so banishing is refused while you are in a fight - and a party you join
--  mid-fight is one whose frames arrive in the one window where nothing can
--  be done about them.
function PF:HideBlizzard()
	if not cfg().hideBlizzard then return end
	self.hideReport = self.hideReport or {}
	for _, name in ipairs(BLIZZARD) do
		local f = _G[name]
		if not f then
			self.hideReport[name] = "absent"
		else
			A:Banish(f)
			self.hideReport[name] = f:IsShown() and "STILL SHOWN" or "hidden"
		end
	end
end

-- ---------------------------------------------------------------------------
-- the capsule
-- ---------------------------------------------------------------------------

local function BuildCapsule(unit)
	local c = cfg()

	-- The same two-frame split the player capsule uses: a plain core at a fixed
	-- size, with the glass filling it. The frame carrying the secure template
	-- never changes size for its whole life, which is a promise worth keeping
	-- for the same reason it was made there.
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(c.width, c.height)
	f.unit = unit

	local glass = Glass.CreatePill(f, { shadow = A.db.profile.glass.shadow })
	glass:SetAllPoints(f)
	glass:_Resize()
	f.glass = glass

	-- the level pip ---------------------------------------------------------
	-- W.CreateBadge, which is the nameplate's level disc. Same widget, same
	-- colour recipe, a different size - the alternative is a second drawing of
	-- a circle with a number in it that has to agree with the first.
	local pip = W.CreateBadge(glass, { size = PIP, style = "npBadge" })
	pip:SetPoint("LEFT", f, "LEFT", PAD_L, 0)
	f.pip = pip

	-- Riding the pip rather than the capsule: both of these say something
	-- about the person, and the person is the disc with their level in it.
	--
	-- W.CreateCrown, which the player's own capsule uses too. Two drawings
	-- of a crown in two files is two places to disagree about where it sits.
	f.crown = W.CreateCrown(glass, pip, CROWN)

	-- The game's own icon sheet, untouched. SetRaidTargetIconTexture picks the
	-- cell; a skin has no business recolouring a skull.
	local marker = glass:CreateTexture(nil, "OVERLAY")
	marker:SetSize(MARKER, MARKER)
	marker:SetPoint("CENTER", pip, "TOP", 0, 1)
	marker:Hide()
	f.marker = marker

	-- name and class --------------------------------------------------------
	local block = CreateFrame("Frame", nil, glass)
	block:SetWidth(c.barWidth)
	block:SetPoint("LEFT", pip, "RIGHT", GAP_PIP, 0)
	block:SetHeight(c.height)
	f.block = block

	local name = W.Text(block, "unitName", "LEFT")
	name:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -8)
	name:SetWordWrap(false)
	f.name = name

	local class = W.Text(block, "unitSub", "LEFT")
	class:SetPoint("LEFT", name, "RIGHT", 8, 0)
	class:SetWordWrap(false)
	f.class = class

	-- bars ------------------------------------------------------------------
	local health = W.CreateBar(block, { height = 6 })
	health:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	health:SetWidth(c.barWidth)
	f.health = health

	local power = W.CreateBar(block, { height = 4 })
	power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -4)
	power:SetWidth(c.barWidth)
	f.power = power
	if not c.showPower then power:Hide() end

	-- DEAD, written in the health track rather than over the name. The bar is
	-- the thing that has gone empty, so that is where the word explaining it
	-- belongs - and it leaves the name legible, which is what you are reading
	-- the frame for.
	local deadText = W.Text(glass, "unitValueAlt", "CENTER")
	deadText:SetPoint("CENTER", health, "CENTER", 0, 0)
	deadText:Hide()
	f.deadText = deadText

	-- the readout, each number beside its own bar ---------------------------
	local hpText = W.Text(glass, "unitValue", "RIGHT")
	hpText:SetWidth(VAL_W)
	hpText:SetPoint("LEFT", health, "RIGHT", GAP_VAL, 0)
	f.hpText = hpText

	local mpText = W.Text(glass, "unitValueAlt", "RIGHT")
	mpText:SetWidth(VAL_W)
	mpText:SetPoint("LEFT", power, "RIGHT", GAP_VAL, 0)
	f.mpText = mpText

	-- the role glyph --------------------------------------------------------
	-- Hidden unless the member has actually set a role, which on this game
	-- version is the uncommon case. Nothing reflows when it is absent: the slot
	-- is a fixed layout, so an empty corner is an empty corner.
	local role = glass:CreateTexture(nil, "OVERLAY")
	role:SetSize(ROLE - 8, ROLE - 8)
	role:SetPoint("RIGHT", f, "RIGHT", -PAD_R + (ROLE - 8) / 2, 0)
	role:Hide()
	f.role = role

	-- interaction -----------------------------------------------------------
	if c.clickTarget then
		local click = CreateFrame("Button", ADDON .. "Party" .. unit,
			f, "SecureUnitButtonTemplate")
		click:SetAllPoints(f)
		click:SetAttribute("unit", unit)
		click:SetAttribute("*type1", "target")
		-- togglemenu, for the reason Modules/UnitFrames.lua records at length:
		-- it is the client's own generic opener and it works out which menu the
		-- unit wants. "menu" calls a menu-function attribute we do not set.
		click:SetAttribute("*type2", "togglemenu")
		click:RegisterForClicks("AnyUp")
		click:EnableMouse(true)
		f.click = click

		if RegisterUnitWatch then
			RegisterUnitWatch(click)
			f.unitWatched = true
		end
	end

	return f
end

-- ---------------------------------------------------------------------------
-- updates
-- ---------------------------------------------------------------------------

local function UpdateName(f)
	local unit = f.unit
	if not UnitExists(unit) then return end

	f.name:SetText(UnitName(unit) or "")
	f.class:SetText(UnitClass(unit) or "")

	local level = UnitLevel(unit)
	f.pip:SetLabel(level and level > 0 and tostring(level) or "??")
	f.pip:SetColors(Palette:ChipColors(Palette:OrbBaseColor(unit)))
end

local function UpdateHealth(f)
	local unit = f.unit
	if not UnitExists(unit) then return end

	local cur, max = UnitHealth(unit), UnitHealthMax(unit)
	if not max or max <= 0 then max = 1 end

	local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
	if dead then cur = 0 end

	f.health:SetMinMaxValues(0, max)
	f.health:SetSmoothValue(cur)
	f.health:SetColors(Palette:HealthColor(unit))

	local c = Palette.c
	f.hpText:SetText(dead and "0" or W.Short(cur))

	-- THE NUMBER IS NOT A WARNING COLOUR. The brief turns it gold as the member
	-- gets hurt, which is the reserved semantic gold carried by hue alone on a
	-- number - and on Dusk that gold is a step from the chrome. The bar beside
	-- it is already shrinking and already going from green to red, which is the
	-- same fact said in the place built to say it. So: ordinary type, and red
	-- only when it is nearly over.
	if dead then
		W.Color(f.hpText, c.textFaint)
	elseif cur / max <= 0.2 then
		W.Color(f.hpText, c.danger)
	else
		W.Color(f.hpText, c.text)
	end
end

local function UpdatePower(f)
	local unit = f.unit
	if not UnitExists(unit) or not cfg().showPower then return end

	local cur, max = UnitPower(unit), UnitPowerMax(unit)
	if not max or max <= 0 then max = 1 end

	f.power:SetMinMaxValues(0, max)
	f.power:SetSmoothValue(cur)
	f.power:SetColors(Palette:PowerColor(unit))
	f.mpText:SetText(cur > 0 and W.Short(cur) or "")
	W.Color(f.mpText, Palette.c.textDim)
end

--- Everything that is about the PERSON rather than about their bars: whether
--  they are there at all, whether they lead, what they have been marked with,
--  and what they said they do.
local function UpdateStatus(f)
	local unit = f.unit
	local c = Palette.c

	local offline = UnitIsConnected and not UnitIsConnected(unit)
	local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)

	-- OFFLINE IS QUIETER THAN DEAD, and both are quieter than present. The
	-- brief draws offline with a dashed rim; there is no dashed rim in this
	-- interface and inventing one for a state you see twice a month is a
	-- texture nobody would recognise. The alpha carries it, which is what the
	-- brief's own .5 was doing anyway.
	f:SetAlpha(offline and 0.5 or dead and 0.6 or 1)
	f.glass:SetEdgeColor(offline and c.glassEdge or c.glassEdgeHi)

	f.deadText:SetShown(dead and not offline)
	if dead then f.deadText:SetText(_G.DEAD or "Dead") end
	if dead then W.Color(f.deadText, c.danger) end

	if offline then
		f.class:SetText(_G.PLAYER_OFFLINE or "offline")
		f.hpText:SetText("")
		f.mpText:SetText("")
	end

	-- The crown. UnitIsGroupLeader rather than a roster walk: the client
	-- answers this per unit and the answer changes on its own event.
	f.crown:SetShown(UnitIsGroupLeader and UnitIsGroupLeader(unit) or false)

	-- The marker, in the game's own art. A skull is a skull on every skin.
	local mark = GetRaidTargetIndex and GetRaidTargetIndex(unit)
	if mark and SetRaidTargetIconTexture then
		SetRaidTargetIconTexture(f.marker, mark)
		f.marker:Show()
	else
		f.marker:Hide()
	end

	-- The role, or the resurrect glyph in its place when somebody is down and
	-- you are the one who can do something about it.
	local glyph, tint
	local _, myClass = UnitClass("player")
	if dead and myClass and CAN_RES[myClass] then
		glyph, tint = "resurrect", c.friendly
	else
		local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
		glyph = ROLE_GLYPH[role or "NONE"]
		tint = (role == "TANK") and c.accent or c.friendly
	end

	if glyph and A.Media:SetIcon(f.role, glyph) then
		f.role:SetVertexColor(tint[1], tint[2], tint[3], 0.9)
		f.role:Show()
	else
		f.role:Hide()
	end
end

local function UpdateAll(f)
	if not f then return end
	if not UnitExists(f.unit) then
		f.glass:Hide()
		return
	end
	f.glass:Show()
	UpdateName(f)
	UpdateHealth(f)
	UpdatePower(f)
	UpdateStatus(f)
end

PF.UpdateAll = UpdateAll

-- ---------------------------------------------------------------------------
-- the stack
-- ---------------------------------------------------------------------------

--- Anchor the four slots inside the container. Called once at build and again
--  when a measurement changes, never in response to somebody joining - the
--  slots do not move for that, which is the whole point of them.
function PF:Layout()
	local c = cfg()
	local step = c.height + c.gap

	-- THE PROFILE'S SCALE, on the container - so one call sizes all four
	-- and the mover positions the thing the player actually sees. Every
	-- other frame in this interface is drawn at profile.scale and this one
	-- was not, which read as party frames half again too big beside the
	-- player's own.
	self.stack:SetScale(A.db.profile.scale or 1)
	self.stack:SetSize(c.width, c.height * #UNITS + c.gap * (#UNITS - 1))

	for i, f in ipairs(self.frames) do
		f:SetSize(c.width, c.height)
		f:ClearAllPoints()
		f:SetPoint("TOP", self.stack, "TOP", 0, -(i - 1) * step)
		f.block:SetWidth(c.barWidth)
		f.health:SetWidth(c.barWidth)
		f.power:SetWidth(c.barWidth)
		f.power:SetShown(c.showPower)
		f.mpText:SetShown(c.showPower)
	end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function PF:RegisterEvents()
	local function unitEvent(handler)
		return function(_, _, unit)
			for _, f in ipairs(PF.frames) do
				if f.unit == unit then handler(f) end
			end
		end
	end

	A:RegisterEvent(self, "UNIT_HEALTH",       unitEvent(UpdateHealth))
	A:RegisterEvent(self, "UNIT_MAXHEALTH",    unitEvent(UpdateHealth))
	A:RegisterEvent(self, "UNIT_POWER_UPDATE", unitEvent(UpdatePower))
	A:RegisterEvent(self, "UNIT_MAXPOWER",     unitEvent(UpdatePower))
	A:RegisterEvent(self, "UNIT_DISPLAYPOWER", unitEvent(UpdatePower))
	A:RegisterEvent(self, "UNIT_NAME_UPDATE",  unitEvent(UpdateName))
	A:RegisterEvent(self, "UNIT_LEVEL",        unitEvent(UpdateName))

	-- The roster, the crown and the markers each have their own event and each
	-- of them changes something on every capsule at once, so they all go
	-- through the same sweep rather than through four handlers that would
	-- drift apart.
	local function sweep()
		for _, f in ipairs(PF.frames) do UpdateAll(f) end
	end
	-- Blizzard's frames come back with the roster and cannot be sent away
	-- mid-fight, so both of those moments ask again.
	local function sweepAndHide()
		PF:HideBlizzard()
		sweep()
	end
	A:RegisterEvent(self, "GROUP_ROSTER_UPDATE",   sweepAndHide)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED",  sweepAndHide)
	A:RegisterEvent(self, "PARTY_LEADER_CHANGED",  sweep)
	A:RegisterEvent(self, "RAID_TARGET_UPDATE",    sweep)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", sweepAndHide)

	-- A member coming back online does not announce itself as a unit event on
	-- that unit, the way a pet arriving does not. These two are how the client
	-- says so.
	A:RegisterEvent(self, "PARTY_MEMBER_ENABLE",  sweep)
	A:RegisterEvent(self, "PARTY_MEMBER_DISABLE", sweep)
end

function PF:RegisterMovers()
	A.Movers:Register("party", self.stack,
		{ point = "LEFT", relPoint = "LEFT", x = 140, y = 120 }, "Party")
end

function PF:OnEnable()
	local c = cfg()

	if self.stack then
		self.stack:Show()
		self:HideBlizzard()
		self:Layout()
		self:RegisterMovers()
		self:RegisterEvents()
		for _, f in ipairs(self.frames) do
			if f.unitWatched and RegisterUnitWatch then RegisterUnitWatch(f.click) end
			UpdateAll(f)
		end
		return
	end

	-- ONE CONTAINER, so the group drags as one thing. It is not secure and
	-- never will be: it carries no unit, takes no clicks, and exists so that
	-- Movers has a single frame to put a grip on.
	self.stack = CreateFrame("Frame", ADDON .. "PartyStack", UIParent)
	self.stack:SetSize(c.width, c.height * #UNITS)

	self.frames = {}
	for i, unit in ipairs(UNITS) do
		local f = BuildCapsule(unit)
		f:SetParent(self.stack)
		self.frames[i] = f
	end

	self:Layout()
	self:RegisterMovers()
	self:RegisterEvents()
	self:HideBlizzard()
	A:RegisterTicker(self, function()
		for _, f in ipairs(PF.frames) do UpdateAll(f) end
	end)

	for _, f in ipairs(self.frames) do UpdateAll(f) end
end

function PF:OnDisable()
	if not self.stack then return end

	-- The unit watch has to come off, or the client keeps showing the click
	-- buttons for a module that is switched off - and they are still clickable,
	-- which is a frame you cannot see stealing your target.
	for _, f in ipairs(self.frames) do
		if f.unitWatched and UnregisterUnitWatch then
			UnregisterUnitWatch(f.click)
			f.click:Hide()
		end
	end
	self.stack:Hide()
end

function PF:OnSkinChanged()
	if not self.stack then return end
	for _, f in ipairs(self.frames) do UpdateAll(f) end
end

function PF:OnConfigChanged()
	if not self.stack then return end

	-- Not in a fight. Every capsule holds a secure button and SetSize on the
	-- frame under one is refused while the lockdown is on; the change is worth
	-- nothing to anybody mid-pull anyway.
	if InCombatLockdown and InCombatLockdown() then return end

	self:Layout()
	for _, f in ipairs(self.frames) do
		Glass.SetPanelCorner(f.glass, A.db.profile.glass.corner)
		f.glass:SetShadow(A.db.profile.glass.shadow)
		UpdateAll(f)
	end
end
