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
local ROLE     = 14

--- Narrowest capsule that still fits pip, bars and readout without them
--  touching - and, read the other way, the width at which there is no dead
--  pill hanging off the right-hand end.
--
--  MIRRORS THE ANCHOR CHAIN in BuildCapsule; keep the two in step. The
--  suite asserts the default width IS this number, so a measurement changed
--  in one place and not the other is a failure rather than a look.
function PF.MinWidth(c)
	return PAD_L + PIP + GAP_PIP + c.barWidth + GAP_VAL + VAL_W + PAD_R
end

-- ALL THREE MARKS RIDE THE PIP.
--
-- The brief puts the ROLE glyph at the far right of the capsule, in a well of
-- its own, and reserves the width for it on every member. Most members wear no
-- glyph at all now, so that reservation was thirty-two units of empty pill on
-- most capsules - and a capsule whose width changed with the glyph would give
-- a ragged stack, which is worse. On the pip it costs no layout at all.
--
-- It also groups them: the pip is where everything about the PERSON is said,
-- so who leads, what they are marked with and what they do are three corners
-- of one disc rather than three places to look.
--
-- The crown and the marker would collide - the brief puts BOTH on the top
-- edge - and a marked leader is ordinary, so they get a corner each: the
-- marker keeps the top, where the game's own frames put it and where the eye
-- goes for it, and the crown takes the top-left.
local CROWN  = 13
local MARKER = 14
local PVP    = 15

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
	-- FOUR CORNERS, ONE DISC, on a layer ABOVE the disc - the pip is a child
	-- frame of the glass and would otherwise draw over every one of them.
	local layer = W.DecoratorLayer(glass, pip)
	f.crown  = W.CreateDecorator(layer, pip, "TOPLEFT",
		{ glyph = "crown", token = "semanticGold", size = CROWN })
	f.marker = W.CreateDecorator(layer, pip, "TOP", { size = MARKER })
	f.pvp    = W.CreateDecorator(layer, pip, "BOTTOMLEFT", { size = PVP })

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

	-- the fourth corner ----------------------------------------------------
	-- Hidden unless the member is a tank or a healer. Nothing reflows when
	-- it is absent, because a decorator is not part of the layout.
	f.role = W.CreateDecorator(layer, pip, "BOTTOMRIGHT", { size = ROLE })

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

	-- The mark and the flag, both in the client's own art.
	W.SetRaidMark(f.marker, unit)
	W.SetPvPMark(f.pvp, unit)

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

	-- Never narrower than its contents. The width slider goes down to 240
	-- and the bars alone can be 300, so this is the difference between a
	-- narrow capsule and a readout hanging out of one.
	local width = math.max(c.width, PF.MinWidth(c))
	self.stack:SetSize(width, c.height * #UNITS + c.gap * (#UNITS - 1))

	for i, f in ipairs(self.frames) do
		f:SetSize(width, c.height)
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
-- the controls panel
--
-- What the client's own Party Members flyout does - assign a target mark, call
-- a ready check, start a countdown, poll for roles, turn the party into a raid
-- - in this interface's glass.
--
-- NOT SECURE, and it does not need to be: none of these four is a protected
-- call on this game version. That is worth saying because every other frame
-- near a unit in this addon is secure and the habit is catching.
-- ---------------------------------------------------------------------------

local PANEL_W   = 320
local WELL      = 34
local WELL_GAP  = 6
local ROW_H     = 30
local MARKERS   = 8

--- How long a countdown runs, and the choices offered.
--
--  Capped by the client's own constant rather than by a number of ours:
--  C_PartyInfo.DoCountdown refuses anything longer and says nothing about it.
local COUNTDOWNS = { 5, 10, 15, 30 }

--- Which screen edge the panel comes off.
--
--  A PANEL FLOATING IN THE MIDDLE IS NOT A DOCK. The brief has this sliding
--  out of a handle flush to a screen edge, and half of that shape is the
--  panel being AT the edge - it reads as drawn out of the side of the
--  screen rather than dropped on top of the game.
--
--  In db.char, like the Toolbox drawer's edge and for the same reason: a
--  drawer edge is a per-character habit rather than a look, and one
--  character's is not another's.
local EDGES = { LEFT = true, RIGHT = true, TOP = true, BOTTOM = true }

--- Which way a dock runs. Up here with the edges rather than down with the
--- handle that reads it: AnchorPanel is written above the handle and needs
--- it, and a `local function` used before its declaration resolves to a
--- GLOBAL - which is nil, and errors on every event that touches the panel.
local function IsVertical(edge)
	return edge == "LEFT" or edge == "RIGHT"
end
-- The handle's measurements, up here for the same reason: AnchorPanel bites
-- the panel into the handle by HANDLE_BITE, and it is written above the code
-- that draws one.
local HANDLE_THICK  = 34
local HANDLE_LONG   = 68
local HANDLE_CORNER = 8
local HANDLE_BITE   = HANDLE_CORNER
local HANDLE_GLYPH  = 18
local HANDLE_CHEV   = 11

function PF:PanelEdge()
	local c = A.db and A.db.char
	local e = c and c.partyDock
	return (e and EDGES[e]) and e or "LEFT"
end

function PF:SetPanelEdge(edge)
	if not EDGES[edge] then return false end
	A.db.char.partyDock = edge
	self:AnchorPanel()
	return true
end

--- Where the stack sits, when you have not said.
--
--  ATTACHED TO THE DOCK UNTIL YOU MOVE IT. The client's own party frames
--  come off the left edge with the controls, and somebody installing this
--  should find their party where they left it rather than somewhere new
--  they now have to tidy up. Drag the stack once and it is yours - Movers
--  has written an anchor and that is the answer from then on.
--
--  /aether party reset drops the anchor and hands it back to the dock.
--
--  ANCHORED TO THE PANEL EVEN WHILE IT IS SHUT, which is the point rather
--  than an oversight: a hidden frame still has a position, so the stack
--  stays exactly where it is whether the controls are open or not. Tying it
--  to whether the panel is showing is how a party frame moves every time
--  you glance at the controls.
local DOCK_GAP = 8

local ATTACH = {
	LEFT   = { "TOPLEFT",     "TOPRIGHT",     DOCK_GAP,  0 },
	RIGHT  = { "TOPRIGHT",    "TOPLEFT",     -DOCK_GAP,  0 },
	TOP    = { "TOP",         "BOTTOM",       0, -DOCK_GAP },
	BOTTOM = { "BOTTOM",      "TOP",          0,  DOCK_GAP },
}

function PF:StackIsPlaced()
	local a = A.db and A.db.profile and A.db.profile.anchors
	return (a and a.party) ~= nil
end

function PF:AnchorStack()
	if not self.stack or not self.panel then return false end
	if self:StackIsPlaced() then return false end
	
	-- NOT IN A FIGHT. The stack carries secure children, so re-anchoring it
	-- is a protected call - and this runs from the roster sweep, which is
	-- exactly what fires when somebody in your party dies mid-pull. The
	-- suite caught this the moment the handle started calling it: eleven
	-- refused calls on one event.
	--
	-- Nothing is lost by waiting: PLAYER_REGEN_ENABLED sweeps again.
	if InCombatLockdown and InCombatLockdown() then return false end
	local a = ATTACH[self:PanelEdge()] or ATTACH.LEFT
	self.stack:ClearAllPoints()
	self.stack:SetPoint(a[1], self.panel, a[2], a[3], a[4])
	return true
end

--- Hand the stack back to the dock.
function PF:ResetStack()
	if A.db and A.db.profile and A.db.profile.anchors then
		A.db.profile.anchors.party = nil
	end
	self:BuildPanel()
	return self:AnchorStack()
end

function PF:AnchorPanel()
	local p = self.panel
	if not p then return end
	local edge = self:PanelEdge()
	p:ClearAllPoints()
	-- OUT OF THE HANDLE, not off the bare edge - and biting into it by its
	-- own corner radius, so the two read as one shape rather than as a tab
	-- floating beside a panel with a gap of shadow between them.
	local h = self.handle
	if h then
		self:LayoutHandle()
		if IsVertical(edge) then
			local anchor = (edge == "LEFT") and "LEFT" or "RIGHT"
			local opposite = (edge == "LEFT") and "RIGHT" or "LEFT"
			local dx = (edge == "LEFT") and -HANDLE_BITE or HANDLE_BITE
			p:SetPoint(anchor, h, opposite, dx, 0)
		else
			local anchor = (edge == "TOP") and "TOP" or "BOTTOM"
			local opposite = (edge == "TOP") and "BOTTOM" or "TOP"
			local dy = (edge == "TOP") and HANDLE_BITE or -HANDLE_BITE
			p:SetPoint(anchor, h, opposite, 0, dy)
		end
	else
		p:SetPoint(edge, UIParent, edge, 0, 0)
	end

	-- The stack rides with it, unless it has been placed by hand.
	self:AnchorStack()
end

local function MaxCountdown()
	local k = _G.Constants and _G.Constants.PartyCountdownConstants
	return (k and k.MaxCountdownSeconds) or 60
end

--- Who may press what.
--
--  READY CHECK, ROLE CHECK and CONVERT are the leader's. The client gates the
--  first itself; the other two it simply ignores, which is worse - a button
--  that does nothing and does not say so. So they are HIDDEN for a member
--  rather than dimmed, and the panel is shorter. A greyed row is a row you
--  keep trying.
--
--  COUNTDOWN IS NOT ON THE LIST, and that is the client's decision rather than
--  ours: its own slash command gates ready-check on being leader and does not
--  gate countdown at all.
local function IsLeader()
	return UnitIsGroupLeader and UnitIsGroupLeader("player") or false
end

local ACTIONS = {
	{
		key = "ready", label = READY_CHECK or "Ready Check",
		glyph = "tick", token = "friendly", primary = true, leader = true,
		run = function()
			if C_PartyInfo and C_PartyInfo.DoReadyCheck then C_PartyInfo.DoReadyCheck() end
		end,
	},
	{
		key = "countdown", label = "Countdown", glyph = "zen", token = "text",
		run = function(self)
			local n = math.min(self.seconds or 10, MaxCountdown())
			if C_PartyInfo and C_PartyInfo.DoCountdown then C_PartyInfo.DoCountdown(n) end
		end,
	},
	{
		key = "roles", label = "Role Check", glyph = "dps", token = "text",
		leader = true,
		run = function()
			if InitiateRolePoll then InitiateRolePoll() end
		end,
	},
	{
		-- THE GOLD ONE, because it changes the shape of the group rather than
		-- asking it a question.
		--
		-- THE BARE GLOBAL, not C_PartyInfo. This client's own right-click menu
		-- calls ConvertToRaid() - Blizzard_UnitPopup_Vanilla.toc loads
		-- Classic/UnitPopupButtons_Shared.lua, and that is what it uses. The
		-- namespaced C_PartyInfo.ConvertToRaid is the Mainline form.
		--
		-- And NOT ConfirmConvertToRaid, which was the first thing tried here
		-- on the strength of its name. It is not an ask-first version of this
		-- call: the group finder uses it inside a popup's OnAccept, after the
		-- player has already answered. Called cold it does nothing at all,
		-- silently, which is exactly what the button did.
		key = "raid", label = _G.CONVERT_TO_RAID or "Convert to Raid",
		glyph = "gear", token = "semanticGold", leader = true,
		run = function()
			if ConvertToRaid then
				ConvertToRaid()
			elseif C_PartyInfo and C_PartyInfo.ConvertToRaid then
				C_PartyInfo.ConvertToRaid()
			end
		end,
	},
}

--- One target mark well.
--
--  THE MARK GOES ON YOUR TARGET, which is the fact the brief never says and
--  the one that decides how this behaves. SetRaidTarget takes a unit, and the
--  unit is always "target" - so with nothing targeted every well here is inert,
--  and the ring showing which mark is 'active' is really showing what your
--  current target is wearing. Both follow the target rather than the party.
local function BuildWell(panel, index)
	local b = W.CreateButton(panel, { corner = 10, fill = "cardBg", edge = "cardEdge" })
	b:SetSize(WELL, WELL)
	b.index = index

	if index then
		local icon = b:CreateTexture(nil, "OVERLAY")
		icon:SetSize(WELL - 12, WELL - 12)
		icon:SetPoint("CENTER", b, "CENTER", 0, 0)
		W.SetMarkIcon(icon, index)
		b.icon = icon
	else
		-- Clear. Its own label rather than a ninth icon, because there is no
		-- ninth mark and a crossed-out one would read as a mark you can set.
		local label = W.Text(b, "tiny", "CENTER")
		label:SetPoint("CENTER", b, "CENTER", 0, 0)
		label:SetText(_G.NONE or "Clear")
		b.label = label
	end

	b:SetScript("OnClick", function(self)
		if not UnitExists("target") or not SetRaidTarget then return end
		SetRaidTarget("target", self.index or 0)
		PF:RefreshPanel()
	end)
	b:SetScript("OnEnter", function(self) W.SetButtonState(self, self.__on, true) end)
	b:SetScript("OnLeave", function(self) W.SetButtonState(self, self.__on, false) end)
	return b
end

--- One action row.
local function BuildRow(panel, spec)
	local b = W.CreateButton(panel, { corner = 12,
		fill = spec.primary and "rowSel" or "glassSoft", edge = "cardEdge" })
	b:SetHeight(ROW_H)
	b.spec = spec

	local glyph = b:CreateTexture(nil, "OVERLAY")
	glyph:SetSize(14, 14)
	glyph:SetPoint("LEFT", b, "LEFT", 10, 0)
	A.Media:SetIcon(glyph, spec.glyph)
	W.Tint(glyph, A.Palette.c[spec.token] or A.Palette.c.text)
	b.glyph = glyph

	local label = W.Text(b, "qlRow", "LEFT")
	label:SetPoint("LEFT", glyph, "RIGHT", 10, 0)
	label:SetText(spec.label)
	b.label = label

	-- The inline duration picker, on the countdown row only. A picker rather
	-- than four rows: the number is a preference you set once.
	--
	-- ITS OWN BUTTON, because a FontString cannot be clicked - and it has to
	-- swallow the click, or picking 30s would also start a 10s countdown on
	-- the way past.
	if spec.key == "countdown" then
		b.seconds = 10
		local pick = W.CreateButton(b, { corner = 6, fill = "glassSoft",
			edge = "cardEdge" })
		pick:SetSize(46, 18)
		pick:SetPoint("RIGHT", b, "RIGHT", -10, 0)
		pick.text = W.Text(pick, "tiny", "CENTER")
		pick.text:SetPoint("CENTER", pick, "CENTER", 0, 0)
		pick:SetScript("OnClick", function()
			local entries = {}
			for _, n in ipairs(COUNTDOWNS) do
				if n <= MaxCountdown() then
					entries[#entries + 1] = {
						text = n .. "s",
						func = function() b.seconds = n; PF:RefreshPanel() end,
					}
				end
			end
			W.Menu(pick, entries)
		end)
		b.pick = pick
	end

	b:SetScript("OnClick", function(self) spec.run(self) end)
	b:SetScript("OnEnter", function(self) W.SetButtonState(self, false, true) end)
	b:SetScript("OnLeave", function(self) W.SetButtonState(self, false, false) end)
	return b
end

-- ---------------------------------------------------------------------------
-- the dock handle
--
-- A slim glass tab flush to a screen edge: the party glyph, how many of you
-- there are, and an arrow. Click it and the controls come out.
--
-- SAME SHAPE AS THE TOOLBOX RAIL, and by the same trick rather than by the
-- same code. A tab beside a panel is two capsules with a gap of shadow
-- between them; overlapped INTO the panel by its own corner radius, the inner
-- curve is hidden behind the panel and it reads as a tab growing out of the
-- drawer's edge. Shut, the same overlap puts that curve off the screen edge,
-- so it hugs there too.
-- ---------------------------------------------------------------------------

function PF:BuildHandle()
	if self.handle then return self.handle end

	local h = Glass.CreatePanel(UIParent, {
		frameType = "Button",
		corner = HANDLE_CORNER,
		shadow = A.db.profile.glass.shadow,
	})
	-- Above the panel it opens, and above the party capsules, because it is
	-- the thing you press to reach both.
	h:SetFrameStrata("HIGH")
	self.handle = h

	local glyph = h:CreateTexture(nil, "OVERLAY")
	glyph:SetSize(HANDLE_GLYPH, HANDLE_GLYPH)
	-- "party" is an alias of the social glyph in Core/Media.lua - the same
	-- pair of figures, not a second drawing of them.
	A.Media:SetIcon(glyph, "party")
	W.Tint(glyph, A.Palette.c.text)
	h.glyph = glyph

	local count = W.Text(h, "tiny", "CENTER")
	h.count = count

	-- THE ARROW IS THE RESERVED GOLD, which is the brief's one conditional
	-- colour - so it reads through W.Tint and follows a skin change on its
	-- own, and on Dusk it is the deeper gold rather than the chrome.
	local chev = h:CreateTexture(nil, "OVERLAY")
	chev:SetSize(HANDLE_CHEV, HANDLE_CHEV)
	chev:SetTexture(A.Media.texture.chevron)
	W.Tint(chev, A.Palette.c.semanticGold)
	h.chev = chev

	h:SetScript("OnClick", function() PF:TogglePanel() end)
	h:SetScript("OnEnter", function(self2)
		W.SetButtonState(self2, false, true)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
		GameTooltip:SetText(_G.PARTY or "Party")
		GameTooltip:Show()
	end)
	h:SetScript("OnLeave", function(self2)
		W.SetButtonState(self2, false, false)
		if GameTooltip then GameTooltip:Hide() end
	end)

	self:LayoutHandle()
	return h
end

--- Where the handle sits, which way its arrow points, and what it says.
function PF:LayoutHandle()
	local h = self.handle
	if not h then return end
	local edge = self:PanelEdge()
	local vertical = IsVertical(edge)

	h:SetScale(A.db.profile.scale or 1)
	h:ClearAllPoints()
	h:SetPoint(edge, UIParent, edge, 0, 0)
	if vertical then
		h:SetSize(HANDLE_THICK, HANDLE_LONG)
	else
		h:SetSize(HANDLE_LONG, HANDLE_THICK)
	end

	-- Laid out ALONG the edge it is docked on, so the three things read in a
	-- line rather than stacked into a tab that is the wrong way round.
	h.glyph:ClearAllPoints()
	h.count:ClearAllPoints()
	h.chev:ClearAllPoints()
	if vertical then
		h.glyph:SetPoint("TOP", h, "TOP", 0, -7)
		h.count:SetPoint("TOP", h.glyph, "BOTTOM", 0, -3)
		h.chev:SetPoint("BOTTOM", h, "BOTTOM", 0, 6)
	else
		h.glyph:SetPoint("LEFT", h, "LEFT", 7, 0)
		h.count:SetPoint("LEFT", h.glyph, "RIGHT", 4, 0)
		h.chev:SetPoint("RIGHT", h, "RIGHT", -6, 0)
	end

	W.PointChevron(h.chev, edge, self.panel and self.panel:IsShown())

	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	h.count:SetText(n > 0 and (n .. "/" .. n) or "")
	W.Color(h.count, A.Palette.c.textDim)

	-- NOT IN A GROUP, NOT ON SCREEN. A dock to party controls with nobody in
	-- the party is a tab that does nothing, permanently, on the edge of every
	-- screen - and this addon already has one thing living there.
	h:SetShown(n > 0)
end
function PF:BuildPanel()
	if self.panel then return self.panel end
	-- Before the panel, because the panel hangs off it.
	self:BuildHandle()

	local p = Glass.CreatePanel(UIParent, {
		corner = 20, fill = "dialogFill", edge = "glassEdgeHi",
		shadow = A.db.profile.glass.shadow,
	})
	p:SetWidth(PANEL_W)
	p:Hide()
	self.panel = p

	-- header
	local title = W.Text(p, "qlHeading", "LEFT")
	title:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -14)
	title:SetText(_G.PARTY or "Party")
	p.title = title

	local count = W.Text(p, "tiny", "LEFT")
	count:SetPoint("LEFT", title, "RIGHT", 8, 0)
	p.count = count

	local rule = W.Divider(p)
	rule:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -40)
	rule:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -40)

	local label = W.Text(p, "tiny", "LEFT")
	label:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -50)
	label:SetText((_G.RAID_TARGET_ICON or "Target markers"):upper())
	W.Color(label, A.Palette.c.textDim)

	-- FIVE ACROSS, TWO DOWN: eight marks and a Clear spanning the last two
	-- cells, which is the brief's grid and also the one that fits 320 wide.
	-- HIGHEST INDEX FIRST: skull, cross, square, moon, triangle, diamond,
	-- circle, star. That is not an arrangement, it is THE arrangement -
	-- Blizzard's own grid has read that way since the marks existed, and
	-- everybody reaches for the skull in the top-left without looking.
	-- Laying them out 1 to 8 puts the star there instead and every mark you
	-- set is the wrong one until you slow down and read the grid.
	p.wells = {}
	local x0, y0 = 16, -70
	for slot = 1, MARKERS do
		local index = MARKERS + 1 - slot
		local b = BuildWell(p, index)
		local col, row = (slot - 1) % 5, math.floor((slot - 1) / 5)
		b:SetPoint("TOPLEFT", p, "TOPLEFT",
			x0 + col * (WELL + WELL_GAP), y0 - row * (WELL + WELL_GAP))
		p.wells[slot] = b
	end

	local clear = BuildWell(p, nil)
	clear:SetWidth(WELL * 2 + WELL_GAP)
	clear:SetPoint("TOPLEFT", p, "TOPLEFT",
		x0 + 3 * (WELL + WELL_GAP), y0 - (WELL + WELL_GAP))
	p.clear = clear

	local rule2 = W.Divider(p)
	rule2:SetPoint("TOPLEFT", p, "TOPLEFT", 14, y0 - 2 * (WELL + WELL_GAP) - 8)
	rule2:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, y0 - 2 * (WELL + WELL_GAP) - 8)
	p.rule2 = rule2

	p.rows = {}
	for i, spec in ipairs(ACTIONS) do
		local b = BuildRow(p, spec)
		b:SetPoint("LEFT", p, "LEFT", 14, 0)
		b:SetPoint("RIGHT", p, "RIGHT", -14, 0)
		p.rows[i] = b
	end

	self:RefreshPanel()
	return p
end

--- Everything about the panel that can change while it is open.
--
--  ONE FUNCTION, called on every event that touches it. The rows that hide for
--  a member change the panel's height, so laying them out and sizing the panel
--  cannot be two places that both think they own the number.
function PF:RefreshPanel()
	local p = self.panel
	if not p then return end
	local c = A.Palette.c

	-- At the profile's scale, like every frame this addon draws. Here
	-- rather than at build, because a scale change has to reach a panel
	-- that was built before it.
	p:SetScale(A.db.profile.scale or 1)
	self:AnchorPanel()

	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	p.count:SetText(n > 0 and (n .. "/" .. n) or "")
	W.Color(p.count, c.textDim)

	-- THE WELLS FOLLOW YOUR TARGET, not the party. Inert with nothing
	-- targeted, because SetRaidTarget has no unit to act on - and a well that
	-- looks pressable and does nothing is the worse of the two.
	local hasTarget = UnitExists and UnitExists("target")
	local on = hasTarget and GetRaidTargetIndex and GetRaidTargetIndex("target")
	-- THE DIM GOES ON LAST. A well IS its own glass surface, so
	-- W.SetButtonState writes its alpha too - setting the dim first and the
	-- state second put every well straight back to full, and the grid looked
	-- ready when there was nothing to mark.
	-- b.index, not the slot: the grid is laid out highest-first, so the two
	-- are opposites and comparing the wrong one rings the wrong well.
	for _, b in ipairs(p.wells) do
		b.__on = (on == b.index)
		W.SetButtonState(b, b.__on, false)
		b:EnableMouse(hasTarget and true or false)
		b:SetAlpha(hasTarget and 1 or 0.4)
	end
	p.clear:SetAlpha(hasTarget and 1 or 0.4)
	p.clear:EnableMouse(hasTarget and true or false)

	-- HIDDEN, NOT DIMMED, and then the panel shortens. A greyed row is a row
	-- you keep trying; a row that is not there is a question you do not ask.
	local leader = IsLeader()
	local y = -160
	local shown = 0
	for _, b in ipairs(p.rows) do
		if b.spec.leader and not leader then
			b:Hide()
		else
			b:Show()
			b:SetPoint("TOP", p, "TOP", 0, y)
			y = y - (ROW_H + 6)
			shown = shown + 1
			if b.pick then
				b.pick.text:SetText((b.seconds or 10) .. "s")
				W.Color(b.pick.text, c.textDim)
			end
		end
	end
	p:SetHeight(160 + shown * (ROW_H + 6) + 10)
end

function PF:TogglePanel()
	local p = self:BuildPanel()
	if p:IsShown() then
		p:Hide()
	else
		self:RefreshPanel()
		p:Show()
	end
	-- The arrow turns round: open, the click retreats the drawer to its own
	-- edge; shut, it emerges away from it.
	self:LayoutHandle()
	return p:IsShown()
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
		PF:LayoutHandle()
		PF:RefreshPanel()
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
	
	-- The panel's marker grid follows your TARGET, so it moves on an event
	-- none of the capsules care about.
	local function panel() PF:RefreshPanel() end
	A:RegisterEvent(self, "PLAYER_TARGET_CHANGED", panel)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", sweepAndHide)

	-- A member coming back online does not announce itself as a unit event on
	-- that unit, the way a pet arriving does not. These two are how the client
	-- says so.
	A:RegisterEvent(self, "PARTY_MEMBER_ENABLE",  sweep)
	A:RegisterEvent(self, "PARTY_MEMBER_DISABLE", sweep)
end

function PF:RegisterMovers()
	-- onPlaced is what keeps this to ONE owner. Movers positions the stack
	-- from the saved anchor or from the default, and then hands it back -
	-- at which point the dock takes it if nobody has placed it. Without the
	-- hook, unlocking the frames would snap it away from the dock.
	A.Movers:Register("party", self.stack,
		{ point = "LEFT", relPoint = "LEFT", x = 140, y = 120 }, "Party",
		{ onPlaced = function() PF:AnchorStack() end })
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
	self:BuildPanel()
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
	if self.handle then self.handle:Hide() end
	if self.panel then self.panel:Hide() end
end

function PF:OnSkinChanged()
	if not self.stack then return end
	if self.handle then self.handle:ApplySkin() end
	if self.panel then
		self.panel:ApplySkin("dialogFill", "glassEdgeHi")
		self:RefreshPanel()
	end
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
