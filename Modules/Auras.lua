--[[--------------------------------------------------------------------------
	AetherUI :: Auras

	Four trays, one per unit per kind, all built from the same tile.

	  player buffs     above the player capsule, growing upward
	  player debuffs   below it, growing downward
	  target buffs     above the target capsule
	  target debuffs   below it

	A tile is the Lattice handoff's square, on both clients: 24 px with a
	hairline edge, a timer tag under thirty seconds and a gold stack tag. A
	row starts where the capsule's bars start and grows toward the other
	capsule; three at rest, eight in a fight, never a second row. Your
	debuffs on the target come first, lit; everyone else's are dimmed; a
	debuff you can dispel off yourself is edged red. (Era drew the deck's
	buff pill until 2026-10-10; Joe: Era as the brief, like Forever.)

	Why it looks like this
	----------------------
	The first design put debuff pills *inside* the capsule, under the bars, and
	grew the capsule downward to wrap them. It worked, and it was wrong: the
	frames resized constantly, and a player with a debuff next to a target
	without one gave you two frames of different heights sitting side by side.
	The fix is to take the auras out of the capsule entirely. Nothing grows, the
	two capsules are always the same shape, and the trays extend into empty space
	above and below where a changing height costs nothing.

	The aura's name is on the tooltip, which is where you go when you do not
	already recognise the icon.

	Nothing here is ever Hidden. See ParkTile: the player's buff tiles carry
	secure cancel buttons, and hiding a frame with a protected descendant is
	refused in combat, which is exactly when auras come and go. Every slot a
	fight can show is placed before one starts; a fight only shows more.

	Aura API
	--------
	Classic Era 1.15 has `UnitAura` with the modern (8.0+) signature - name,
	texture, count, auraType, duration, expirationTime, caster, ... with no
	`rank` return. That is not a guess: ShadowedUnitFrames calls it that way and
	works on this client. `C_UnitAuras` is preferred when present so this keeps
	working if `UnitAura` is eventually removed the way it was on Retail.

	Target auras need no special handling - PitBull4 reads the target through the
	same two functions as every other unit, and so do we. The only difference is
	the filter and which capsule the tray hangs off.

	One deliberate choice worth keeping
	-----------------------------------
	Right-click cancels a buff, in combat as well as out of it, and it cancels by
	*name*. See AddCancel for why that is possible here and is not, generally,
	elsewhere.

	WoW Forever
	-----------
	Everything above is the Classic Era path. WoW Forever refuses the aura read
	in combat, encounters and PvP, so these tiles would go blank in every fight.
	There the trays are the client's own aura containers instead, drawn to the
	Lattice handoff - see "WoW Forever: trays the client fills" below.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local Aur = A:NewModule("auras")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- ---------------------------------------------------------------------------
-- aura source
-- ---------------------------------------------------------------------------

--- Are auras readable at all this frame?
--
--  A DIFFERENT PROBLEM FROM A SECRET NUMBER, and it needs a different answer.
--  A secret value can be handed straight to a setter - see A.IsSecret. An aura
--  cannot: on WoW Forever the READ ITSELF is refused, and it is a hard error
--  rather than a nil return:
--
--      GetAuraDataByIndex(): Auras cannot be accessed when secret while
--      tainted by 'AetherUI'
--
--  "Tainted by AetherUI" is not a leak of ours to go hunting. Addon code is
--  insecure by definition; the API simply refuses an insecure caller while the
--  data is restricted, and names whoever is on the stack.
--
--  Ask first, probe second, and cache for the frame:
--
--  1. `C_Secrets.ShouldAurasBeSecret()` is the client's own question and costs
--     nothing.
--  2. Where it cannot answer, a pcall on one known-cheap read says whether the
--     door is open. Restriction can engage between frames, so a stale "open"
--     is possible - hence only ever caching within the same GetTime().
--  3. Failure means restricted, never "no auras": the difference is a tray
--     that goes blank for a moment versus one that lies about what is on you.
--
--  Same shape EllesmereUI arrived at, and for the same reason. Era has no
--  C_Secrets and never refuses the read, so this answers false there and the
--  scan below is untouched.
local aurasRestrictedAt = -1
function Aur.AurasRestricted()
	local now = (GetTime and GetTime()) or 0

	-- WHEN THE CLIENT WILL ANSWER, TAKE ITS ANSWER AND CLEAR THE STAMP. The
	-- frame cache below exists for the probe path only, and left in place it can
	-- LATCH: a "no" that never expires empties the tray for the rest of the
	-- session. Caught by the test that lifts the restriction and looks again.
	if C_Secrets and C_Secrets.ShouldAurasBeSecret then
		if C_Secrets.ShouldAurasBeSecret() then
			aurasRestrictedAt = now
			return true
		end
		aurasRestrictedAt = -1
		return false
	end

	if now == aurasRestrictedAt then return true end

	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		if pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL") then
			return false
		end
		aurasRestrictedAt = now
		return true
	end

	return false
end

--- Returns: name, texture, count, auraType, duration, expirationTime, isMine
--
--  "Is this mine" comes from isFromPlayerOrPlayerPet / castByPlayer rather than
--  comparing sourceUnit to "player", because sourceUnit is nil for a fair few
--  auras and the comparison then quietly reports every one of them as someone
--  else's. Falls back to the comparison only when the flag is absent.
local function GetAura(unit, index, filter)
	-- The read is REFUSED, not merely secret - see Aur.AurasRestricted. Answer
	-- "no aura here" and let every caller's existing end-of-list handling do the
	-- rest, rather than teaching all of them about a third state.
	if Aur.AurasRestricted() then return nil end

	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		-- pcall even so: the frame-scoped cache above can go stale between the
		-- probe and this call, and one throw here is a whole tray of them.
		local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
		if not ok then
			aurasRestrictedAt = (GetTime and GetTime()) or 0
			return nil
		end
		if not d then return nil end
		local mine = d.isFromPlayerOrPlayerPet
		if mine == nil then mine = (d.sourceUnit == "player" or d.sourceUnit == "pet") end
		return d.name, d.icon, d.applications or d.charges or 0, d.dispelName,
			d.duration or 0, d.expirationTime or 0, mine
	end
	if UnitAura then
		local name, texture, count, auraType, duration, expiration, caster,
			_, _, _, _, _, castByPlayer = UnitAura(unit, index, filter)
		if not name then return nil end
		local mine = castByPlayer
		if mine == nil then mine = (caster == "player" or caster == "pet") end
		return name, texture, count, auraType, duration, expiration, mine
	end
	return nil
end

-- Shared, so the nameplate chips read auras through the same two-API fallback
-- rather than growing a second copy of it that drifts.
Aur.GetAura = GetAura

-- ---------------------------------------------------------------------------
-- the square: one drawing for both clients (Lattice handoff, Auras)
--
-- 24 px squares with a hairline edge, a timer tag under thirty seconds and a
-- gold stack tag. Classic Era draws its own; WoW Forever's are the client's
-- buttons, dressed the same way (see "WoW Forever" below). Era once drew the
-- deck's buff pill instead; Joe, 2026-10-10: the two clients look alike.
-- ---------------------------------------------------------------------------

local SQ, SQ_GAP = 24, 4
local SQ_STEP = SQ + SQ_GAP
-- Three a row at rest, up to eight in a fight, never a second row.
local REST, COMBAT = 3, 8
-- Above this many seconds left, the timer says nothing.
local TIMER_UNDER = 30
-- The timer tag hangs this far below its square, so a row above the capsule
-- stands that much further off it.
local TAG_DROP = 6

-- Per aura on Era, per group on Forever. `mine` is your debuff on the target,
-- edged in the accent with a glow; `theirs` everyone else's, dimmed; `dispel`
-- a debuff you can take off yourself.
local LOOKS = {
	plain  = { edge = "auraEdge",      width = 1 },
	faint  = { edge = "auraEdgeFaint", width = 1 },
	theirs = { edge = "auraEdgeOther", width = 1, alpha = 0.5 },
	mine   = { edge = "accent",        width = 1.5, glow = 0.6 },
	dispel = { edge = "auraDispel",    width = 1.5 },
}

--- A tag: text on a chip exactly as wide as the text. The chip hangs off the
--  string's own ends, so when the text is "" there is nothing to draw - which
--  is how a long timer and a single stack show no chip. On a frame of its own,
--  above the square's art.
local function Tag(button, ink, fill)
	local carrier = CreateFrame("Frame", nil, button)
	carrier:SetAllPoints(button)
	carrier:SetFrameLevel(button:GetFrameLevel() + 3)
	carrier:EnableMouse(false)

	-- Lettered BEFORE the client is given it: registering writes to it at once,
	-- and a string with no font is a hard error inside the engine.
	local fs = carrier:CreateFontString(nil, "OVERLAY")
	Media:SetFont(fs, "auraTag")
	fs:SetTextColor(ink[1], ink[2], ink[3], ink[4] or 1)
	fs:SetText("")

	local chip = carrier:CreateTexture(nil, "ARTWORK")
	chip:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
	-- Pulled in a pixel at each end. Hung flush on an empty string, the game
	-- still rounded the chip up to a one-pixel tick beside every square (seen
	-- 2026-10-06); inset, an empty string leaves it less than nothing wide and
	-- it is not drawn. The spaces padding each number keep the margin.
	chip:SetPoint("TOPLEFT", fs, "TOPLEFT", 1, 1)
	chip:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", -1, -1)
	W.AddMask(chip, carrier, Media.texture.slotMask, chip)

	carrier.text, carrier.chip = fs, chip
	return carrier
end

-- How often a tile that claims to have no timer asks again. One API call for one
-- index, so a player walking around with five permanent buffs costs five calls a
-- second - nothing - and in exchange no tile can be wrong for ever.
local RECHECK = 1.0

--- A timer tag's words: whole seconds, rounded up so it never reads 0 with time
--  left, padded a space each side for the chip's margin; nothing from thirty
--  seconds up, or with no time at all.
local function TimerWords(exp)
	local left = (exp or 0) - GetTime()
	if left <= 0 or left >= TIMER_UNDER then return "" end
	return (" %d "):format(math.ceil(left))
end
Aur.TimerWords = TimerWords

--- Write a tile's timer, and record whether the numbers behind it can be
--  trusted.
--
--  There are three states here, not two, and collapsing them to two is what made
--  buff timers go missing after a login:
--
--    a real time            -> believed; the tag shows under thirty seconds
--    duration 0             -> a permanent aura, believed
--    duration, no future    -> neither. The server has not finished telling us
--    expiry                    about this aura yet, which lasts for several
--                              seconds after a login or a zone change.
--
--  The last two put the tile on the re-poll list below. A permanent aura is
--  re-checked too, because "duration 0" and "the server has not said yet" are
--  the same value.
local function SetTimerText(t)
	if t._noTime then
		t.time:SetText("")
		t._timeless, t._stale = false, false
		return
	end
	local dur, exp = t._duration or 0, t._expiration or 0
	if dur > 0 and exp > GetTime() then
		t.time:SetText(TimerWords(exp))
		t._timeless, t._stale = false, false
	else
		t.time:SetText("")
		t._timeless = (dur <= 0)
		t._stale    = (dur > 0)
	end
end

--- Ask the API again about one tile, cheaply.
--
--  This is the only thing standing between "the server had not told us the
--  duration yet" and a pill that reads n/a for the rest of the session, and it
--  costs one call for one index. It never rewrites anything but the clock: the
--  icon, the count and the tint all belong to Update.
local function Repoll(t)
	if not t.unit or not t.index then return end
	local name, _, _, _, duration, expiration = GetAura(t.unit, t.index, t.filter)
	if not name or name ~= t._name then return end
	if duration == t._duration and expiration == t._expiration then return end
	t._duration, t._expiration = duration, expiration
	SetTimerText(t)
end

-- ---------------------------------------------------------------------------
-- the tile
-- ---------------------------------------------------------------------------

local function TileWidth() return SQ end
local function TileHeight() return SQ end

--- Tooltip scripts live on whichever frame is actually on top: the tile itself,
--  or the secure cancel button covering it on the player's buff tray.
local function TileEnter(self)
	local p = self.__tile or self
	-- A parked tile keeps its slot and its mouse - moving it or disabling its
	-- mouse are both refused in combat - so "is this one on screen" is asked
	-- here, in Lua, where nothing can refuse it.
	if p._parked then return end
	if not p.unit or not p.index then return end
	-- Not while auras are restricted. The tray is emptying itself anyway, and
	-- on the beta Blizzard's own PTR feedback addon hooks SetUnitAura and reads
	-- the aura by index after us - which the client refuses from our call, so
	-- the tooltip turned into an error (Blizzard_PTRFeedback_Tooltips.lua:24,
	-- 2026-09-23).
	if Aur.AurasRestricted() then return end
	GameTooltip:SetOwner(p, "ANCHOR_BOTTOM")
	pcall(GameTooltip.SetUnitAura, GameTooltip, p.unit, p.index, p.filter)
	GameTooltip:Show()
end

local function TileLeave()
	GameTooltip:Hide()
end

--- Right-click to cancel, by name rather than by index.
--
--  The first pass used the "cancelaura" secure action type with a fixed `index`
--  attribute. It does not dispatch on this client - right-click did nothing.
--  "macro" does dispatch, on every client there has ever been, and Classic has
--  `/cancelaura <name>`; it is how everyone drops Ice Block. So the button runs
--  a macro instead.
--
--  Cancelling *by name* turns out to be the better design anyway, and the reason
--  is the combat lockdown. `SetAttribute` is protected, so a fight freezes
--  whatever the tile was last told. Frozen by index, that is a live hazard: the
--  buff at index 3 changes as auras come and go, and a stale 3 cancels whatever
--  drifted into the slot. Frozen by name it is harmless - `/cancelaura Ice
--  Barrier` either finds Ice Barrier or does nothing at all. It can be out of
--  date. It cannot be wrong.
--
--  Two fallbacks sit behind it, and neither can double-fire:
--
--  * PostClick on the secure button. Runs *after* the secure dispatch, so it
--    cannot taint it - a PreClick hook would, and the cancel would then be
--    refused in combat, which is the whole reason for the secure button. Out of
--    combat it finishes the job directly, the way ShadowedUnitFrames does.
--  * OnMouseUp on the tile underneath. Mouse events only reach the topmost
--    enabled frame, so this fires exactly when the secure button is absent -
--    if the template failed to create, say - and never alongside it.
local function CancelAura(p)
	if not p or not p._auraName then return end
	if InCombatLockdown and InCombatLockdown() then return end

	-- Out of combat the index is guaranteed fresh - the last UNIT_AURA wrote it -
	-- so the exact call is the right one here, and the name is only the fallback.
	-- In combat it is the other way round, which is what the macro is for.
	if CancelUnitBuff and p.index then
		pcall(CancelUnitBuff, "player", p.index, "HELPFUL")
	elseif CancelSpellByName then
		pcall(CancelSpellByName, p._auraName)
	end
end

local function CancelClicked(self, button)
	if button ~= "RightButton" then return end
	CancelAura(self.__tile or self)
end

--- Keep the macro in step with what the tile is showing. Silently skipped in
--  combat, where the frozen text stays safe for the reason above.
local function SetCancelName(p, name)
	p._auraName = name
	local click = p.click
	if not click or not name then return end
	if InCombatLockdown and InCombatLockdown() then return end
	if click._macroName == name then return end
	click._macroName = name
	click:SetAttribute("macrotext2", "/cancelaura " .. name)
end

--- One square: the edge is the square itself in the edge colour, with the icon
--  on it inset by the edge's width - a one-texel ring drawn at 24px loses its
--  hairline to resampling, and a filled shape keeps it. The glow for your own
--  debuff behind; the timer tag out past the bottom right, the stack tag past
--  the top right. The same drawing Forever's buttons are given.
local function CreateTile(parent)
	local t = CreateFrame("Frame", nil, parent)
	t:SetSize(SQ, SQ)

	t.glow = t:CreateTexture(nil, "BACKGROUND", nil, -1)
	t.glow:SetTexture(Media.texture.slotGlow)
	t.glow:SetBlendMode("ADD")
	t.glow:SetPoint("CENTER", t, "CENTER")
	t.glow:SetSize(SQ * 2, SQ * 2)
	t.glow:Hide()

	t.plate = t:CreateTexture(nil, "BACKGROUND")
	t.plate:SetTexture(Media.texture.slotMask)
	t.plate:SetAllPoints(t)

	t.art = { icon = t:CreateTexture(nil, "ARTWORK") }
	t.art.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	W.AddMask(t.art.icon, t, Media.texture.slotMask, t.art.icon)

	local c = Palette.c
	t.timer = Tag(t, c.auraTimer, c.auraChip)
	t.timer.text:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 3, 1 - TAG_DROP)
	t.stack = Tag(t, c.auraStackInk, c.auraStack)
	t.stack.text:SetPoint("TOPRIGHT", t, "TOPRIGHT", 4, TAG_DROP - 1)
	t.time, t.count = t.timer.text, t.stack.text

	t:EnableMouse(true)
	t:SetScript("OnEnter", TileEnter)
	t:SetScript("OnLeave", TileLeave)
	-- Inert unless the display sets _auraName, and unreachable while the secure
	-- button is covering the tile. See AddCancel.
	t:SetScript("OnMouseUp", CancelClicked)

	return t
end

--- The tags on or off, from the options.
local function SizeTile(t, spec)
	t.timer:SetShown(spec.showTime)
	t.stack:SetShown(spec.showCount)
end

--- A square's look, by its LOOKS key: the edge colour and width, the glow,
--  the strength. Repainted from the palette each time, so a skin change
--  reaches it.
local function Look(t, key, trayAlpha)
	local look = LOOKS[key] or LOOKS.plain
	local col = Palette.c[look.edge] or Palette.c.accent
	t.plate:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
	local w = look.width
	t.art.icon:ClearAllPoints()
	t.art.icon:SetPoint("TOPLEFT", t, "TOPLEFT", w, -w)
	t.art.icon:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -w, w)
	t.glow:SetShown(look.glow ~= nil)
	if look.glow then t.glow:SetVertexColor(col[1], col[2], col[3], look.glow) end
	t._look, t._trayAlpha = key, trayAlpha
	t._lookAlpha = (look.alpha or 1) * (trayAlpha or 1)
	if not t._parked then t:SetAlpha(t._lookAlpha) end
end

--- Take a tile out of play.
--
--  Deliberately *not* `Hide()`. The player's buff tiles carry secure cancel
--  buttons, and hiding a frame with a protected descendant is refused in combat
--  - which is precisely when auras come and go.
--
--  It used to move the tile off screen as well, on the reasoning that "position
--  is not protected on a plain frame". **That is the half of it that was
--  wrong.** The restriction reaches every *ancestor* of a protected frame, not
--  only the frame itself, so `SetPoint` on a tile carrying a cancel button is
--  refused in combat exactly like `Hide` is - and so is `SetSize` on the tray
--  around it. Four buff changes in one fight produced fourteen blocked-action
--  reports.
--
--  So a parked tile now keeps its slot and only loses its alpha. Nothing here
--  asks the client for permission, and a tile that comes back into play is
--  already where it belongs - which is what makes a frozen layout survivable.
local function ParkTile(t)
	if t._parked then return end
	t._parked = true
	t:SetAlpha(0)
	-- Alpha, and nothing else. `EnableMouse` is refused on an ancestor of a
	-- protected frame exactly like `SetPoint` is, and `Hide` on the secure button
	-- itself is refused too - so the first version of this traded one blocked
	-- call for another. A parked tile is taken out of the mouse path by a plain
	-- Lua flag that the tooltip handlers read instead; see TileEnter. Nothing
	-- here asks the client for anything.
end

local function UnparkTile(t)
	if not t._parked then return end
	t._parked = nil
	t:SetAlpha(t._lookAlpha or 1)
end

local function AddCancel(p)
	if p.click or not CreateFrame then return end

	local ok, click = pcall(CreateFrame, "Button", nil, p, "SecureActionButtonTemplate")
	if not ok or not click then
		p.clickFailed = true
		return
	end

	click:SetAllPoints(p)
	click:RegisterForClicks("RightButtonUp")
	click:SetAttribute("type2", "macro")
	click:SetAttribute("unit", "player")
	click:SetScript("PostClick", CancelClicked)

	-- The button covers the tile, so the tooltip has to come from here.
	click.__tile = p
	click:SetScript("OnEnter", TileEnter)
	click:SetScript("OnLeave", TileLeave)

	p.click = click
	if p._auraName then
		click._macroName = nil
		SetCancelName(p, p._auraName)
	end
	return click
end

-- ---------------------------------------------------------------------------
-- a display: one grid of tiles for one unit and one filter
-- ---------------------------------------------------------------------------

local Display = {}
Display.__index = Display

local function NewDisplay(name, spec, opts)
	local d = setmetatable({}, Display)
	d.name, d.spec, d.opts = name, spec, opts
	d.tiles = {}
	d.frame = CreateFrame("Frame", nil, UIParent)
	d.frame:SetSize(SQ, SQ)
	d.active = 0
	return d
end

--- Is this display's geometry off limits right now?
--
--  Only the player's buff tray answers yes, and only in combat: it is the one
--  with `cancel`, so it is the one whose tiles own secure buttons. The other
--  three trays have no protected descendants anywhere and re-flow through a
--  fight exactly as they do outside one.
--
--  What is *not* gated is everything that makes an aura readable: textures,
--  cooldowns, stack counts, timer text and tint are all plain region calls on
--  unprotected objects. A frozen tray still tells you what you have and how long
--  is left on it; what it cannot do until the fight ends is move.
function Display:Locked()
	return (self.opts.cancel and InCombatLockdown and InCombatLockdown()) and true or false
end

function Display:Acquire(i)
	local t = self.tiles[i]
	if not t then
		t = CreateTile(self.frame, self.spec)
		self.tiles[i] = t
		if self.opts.cancel then
			if InCombatLockdown and InCombatLockdown() then
				-- A secure button's attributes cannot be written mid-fight, so
				-- this tile gets its cancel wiring the moment the fight ends.
				self._primePending = true
			else
				AddCancel(t)
			end
		end
	end
	UnparkTile(t)
	return t
end

--- Build every tile the display can ever need, up front and out of combat.
--
--  Lazily creating the eleventh buff tile during a fight would leave it without
--  a cancel button until the fight ended, so the whole set is made in advance
--  and this runs again on PLAYER_REGEN_ENABLED to catch anything that slipped
--  through - a max raised mid-fight, say.
function Display:Prime()
	if not self.opts.cancel then return end
	if InCombatLockdown and InCombatLockdown() then
		self._primePending = true
		return
	end

	for i = 1, self.opts.max or 0 do
		local t = self.tiles[i]
		if not t then
			t = CreateTile(self.frame, self.spec)
			self.tiles[i] = t
		end
		if not t.click then AddCancel(t) end
		SizeTile(t, self.spec)
	end

	-- Every slot gets a position while we are still allowed to give it one. In
	-- combat `Arrange` refuses, so a tile that had never been on screen would
	-- have no points at all and simply not draw - a buff gained mid-fight would
	-- vanish rather than appear late. Laying out the full grid first means the
	-- worst a frozen tray can do is centre a row for the wrong count.
	self:Arrange(self.opts.max or 0)

	for i = 1, self.opts.max or 0 do
		if i > self.active then ParkTile(self.tiles[i]) end
	end

	-- ...and then back to the real count, so out of combat it is centred for
	-- what is actually on screen rather than for what might be.
	if self.active > 0 then self:Arrange() else self:Collapse() end
	self._primePending = nil
end

--- One row of squares, from where the capsule's bars start, growing toward
--  the other capsule: left to right off the player, right to left off the
--  mirrored target (Lattice handoff, Auras). Never a second row.
--
--  `count` is how many slots to lay out and defaults to what is on screen. Prime
--  passes the display's maximum instead, so that every tile has a home before
--  combat starts and a buff gained mid-fight lands somewhere sensible rather
--  than nowhere at all - a frame that has never been given a point does not
--  draw, so without that pass a frozen tray would simply swallow anything new.
--  One row means every slot's place is the same at rest and in a fight: a fight
--  only shows more of them.
function Display:Arrange(count)
	if self:Locked() then
		-- Replayed on PLAYER_REGEN_ENABLED. Until then the tray keeps the layout
		-- it entered the fight with, which is the whole of what freezing costs.
		self._layoutPending = true
		return
	end

	local opts = self.opts
	local slots = count or self.active
	local vp = opts.growUp and "BOTTOM" or "TOP"
	local side = opts.mirror and "RIGHT" or "LEFT"
	local dir = opts.mirror and -1 or 1
	local inset = opts.inset or 0
	for i = 1, slots do
		local t = self.tiles[i]
		if not t then break end
		t:ClearAllPoints()
		t:SetPoint(vp .. side, self.frame, vp .. side, dir * (inset + (i - 1) * SQ_STEP), 0)
	end
	if opts.fillWidth then
		self.frame:SetHeight(SQ)
	else
		self.frame:SetSize(math.max(1, slots * SQ_STEP - SQ_GAP), SQ)
	end
end

--- This tray's auras in the order they are drawn, each with its look. Your
--  debuffs on the target come first and lit, everyone else's after and
--  dimmed; on yourself, what you can dispel first, edged red.
function Display:Collect()
	local opts = self.opts
	local unit = opts.unit
	local first, rest = {}, {}
	local dispel
	if opts.dispelFirst then
		dispel = {}
		for i = 1, 40 do
			local name = GetAura(unit, i, "HARMFUL|RAID")
			if not name then break end
			dispel[name] = true
		end
	end
	for index = 1, 40 do
		local name, texture, count, auraType, duration, expiration, mine =
			GetAura(unit, index, opts.filter)
		if not name then break end
		local e = { index = index, name = name, texture = texture, count = count,
			duration = duration, expiration = expiration }
		if opts.mineFirst then
			if mine then
				e.look = "mine"
				first[#first + 1] = e
			elseif not opts.onlyMine then
				e.look = "theirs"
				rest[#rest + 1] = e
			end
		elseif dispel and dispel[name] then
			e.look = "dispel"
			first[#first + 1] = e
		else
			e.look = opts.look or "plain"
			rest[#rest + 1] = e
		end
	end
	for _, e in ipairs(rest) do first[#first + 1] = e end
	return first
end

--- How many show: three at rest, eight in a fight.
function Display:Limit()
	local n = (Aur.fighting or (InCombatLockdown and InCombatLockdown())) and COMBAT or REST
	return math.min(n, self.opts.max or n)
end

function Display:Update()
	local opts, spec = self.opts, self.spec
	local unit = opts.unit
	if not UnitExists(unit) then
		self:Clear()
		return
	end

	local shown = 0
	local limit = self:Limit()

	for _, e in ipairs(self:Collect()) do
		if shown >= limit then break end
		shown = shown + 1
		local t = self:Acquire(shown)

		t.unit, t.index, t.filter = unit, e.index, opts.filter
		t.art.icon:SetTexture(e.texture)
		if opts.cancel then SetCancelName(t, e.name) end

		SizeTile(t, spec)
		local count = e.count
		t.count:SetText((spec.showCount and count and count > 1) and (" %d "):format(count) or "")

		-- The name is kept so a re-poll can prove it is still reading the same
		-- aura: indices shift as auras come and go, and pulling a neighbour's
		-- duration onto this tile would be worse than showing nothing.
		t._name = e.name
		t._expiration, t._duration = e.expiration, e.duration
		t._noTime = (spec.showTime == false)
		t._nextPoll = GetTime() + RECHECK
		SetTimerText(t)

		Look(t, e.look, opts.alpha)
	end

	for i = shown + 1, #self.tiles do ParkTile(self.tiles[i]) end
	self.active = shown

	if shown == 0 then
		self:Collapse()
	else
		self:Arrange()
	end
end

--- Nothing to show. The frame keeps its place and loses its height; the tiles
--  park. See ParkTile for why none of this is a Hide.
function Display:Collapse()
	if self:Locked() then self._layoutPending = true return end
	if self.opts.fillWidth then
		self.frame:SetHeight(1)
	else
		self.frame:SetSize(1, 1)
	end
end

function Display:Clear()
	for _, t in ipairs(self.tiles) do ParkTile(t) end
	self.active = 0
	self:Collapse()
end

--- Only the text changes on a tick, never the layout - every tile is the same
--  size whatever its timer says, so nothing here can reflow anything.
function Display:Tick()
	if self.active == 0 then return end
	local now = GetTime()
	for i = 1, self.active do
		local t = self.tiles[i]
		if t._noTime then
			-- nothing to say, and nothing to ask about

		elseif t._timeless or t._stale then
			-- Believed permanent, or known to be missing its numbers. Either way
			-- the belief is worth re-testing at a rate nobody can feel.
			if now >= (t._nextPoll or 0) then
				t._nextPoll = now + RECHECK
				Repoll(t)
			end

		elseif t._expiration then
			if t._expiration <= now then
				-- Ran out from under us, or the expiry we were given has gone
				-- stale: re-classify, then go back and ask.
				SetTimerText(t)
				t._nextPoll = now + RECHECK
			else
				local text = TimerWords(t._expiration)
				if text ~= t.time:GetText() then t.time:SetText(text) end
			end
		end
	end
end

--- A skin change: the tags' inks and every square's edge, again.
function Display:ApplySkin()
	local c = Palette.c
	for _, t in ipairs(self.tiles) do
		t.timer.text:SetTextColor(c.auraTimer[1], c.auraTimer[2], c.auraTimer[3], c.auraTimer[4] or 1)
		t.timer.chip:SetColorTexture(c.auraChip[1], c.auraChip[2], c.auraChip[3], c.auraChip[4] or 1)
		t.stack.text:SetTextColor(c.auraStackInk[1], c.auraStackInk[2], c.auraStackInk[3], c.auraStackInk[4] or 1)
		t.stack.chip:SetColorTexture(c.auraStack[1], c.auraStack[2], c.auraStack[3], c.auraStack[4] or 1)
		if t._look then Look(t, t._look, t._trayAlpha) end
	end
	self:Update()
end

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

-- Which tray is which. `above` decides both which edge of the capsule it hangs
-- off and which way its rows grow, because those two are the same question.
local TRAYS = {
	{ key = "playerBuffs",   unit = "player", filter = "HELPFUL", debuff = false,
	  above = true,  cancel = true },
	{ key = "playerDebuffs", unit = "player", filter = "HARMFUL", debuff = true,
	  above = false },
	{ key = "targetBuffs",   unit = "target", filter = "HELPFUL", debuff = false,
	  above = true },
	{ key = "targetDebuffs", unit = "target", filter = "HARMFUL", debuff = true,
	  above = false },
}
Aur.TRAYS = TRAYS

--- The square, and the rest and fight counts, for the harness.
function Aur:TileWidth() return TileWidth() end
function Aur:TileHeight() return TileHeight() end
Aur.REST, Aur.COMBAT, Aur.SQ_STEP = REST, COMBAT, SQ_STEP

--- The capsule a tray belongs to, or nil if unit frames are off.
local function CapsuleFor(unit)
	local UFm = A:GetModule("unitframes")
	if not UFm or not UFm.enabled then return nil end
	return (unit == "target") and UFm.target or UFm.player
end

--- The config side a tray reads from, and whether it is on at all.
local function SideFor(cfg, t)
	return t.debuff and cfg.debuffs or cfg.buffs
end

local function TrayEnabled(cfg, t)
	local side = SideFor(cfg, t)
	return side.enabled ~= false and side[t.unit] ~= false
end

--- Blizzard's own buff row, top-right of the screen.
--
--  Not hidden by the ActionBars module because it is not part of the bar: it is
--  its own frame, it survives everything that sweep does, and the first pass
--  simply forgot it - so the stock icons sat above the glass tiles showing the
--  same auras twice.
--
--  TemporaryEnchantFrame goes with it. That does mean weapon enchant timers
--  disappear and we do not yet replace them, which is a real gap; leaving the
--  frame up on its own puts three orphaned icons in the corner instead, which is
--  worse. `auras.hideBlizzard = false` brings the lot back.
Aur.blizzardFrames = {
	"BuffFrame", "DebuffFrame", "TemporaryEnchantFrame",
}

function Aur:HideBlizzard()
	local cfg = A.Config:Module("auras")
	if cfg.hideBlizzard == false then return end

	self.hideReport = self.hideReport or {}
	for _, name in ipairs(Aur.blizzardFrames) do
		local f = _G[name]
		if not f then
			self.hideReport[name] = "absent"
		elseif f.IsForbidden and select(2, pcall(f.IsForbidden, f)) then
			self.hideReport[name] = "forbidden"
		else
			-- One pcall per call: bundling them means a throw on the first
			-- silently skips the rest, which is how the action bar sweep hid
			-- nothing for two rounds.
			pcall(f.UnregisterAllEvents, f)
			pcall(f.Hide, f)
			if f.HookScript and not f.__aetherHooked then
				f.__aetherHooked = true
				pcall(f.HookScript, f, "OnShow", function(self)
					if not InCombatLockdown() then self:Hide() end
				end)
			end
			self.hideReport[name] = (f.IsShown and f:IsShown()) and "STILL SHOWN" or "hidden"
		end
	end
end

-- ---------------------------------------------------------------------------
-- WoW Forever: trays the client fills
-- ---------------------------------------------------------------------------

--[[
	Blizzard_AuraContainer (12.1) is the client's answer to auras we may not
	read: it picks the auras, makes the buttons and fills them, secret or not.
	We say what a button looks like, once, when the client builds it.

	Drawn to the Lattice handoff (Auras): 24px squares with a hairline edge,
	buffs above the capsule and debuffs below, each row starting where the bars
	start and growing toward the other capsule. Your debuffs on the target are
	edged in the accent with a glow and come first, nearest the portrait;
	everyone else's are dimmed. A debuff you can dispel off yourself is edged
	red. A dark timer tag under thirty seconds, a gold stack tag. Three per row
	at rest, up to eight in a fight, never a second row.

	What the engine decides, not us:
	  - Style is per GROUP. We never see an aura, so "mine" and "theirs" are two
	    groups with two looks, not one group coloured per aura.
	  - A button is ours inside initializeFrame and nowhere else. Afterwards a
	    write to it is refused while auras are secret, so nothing here makes one.
	  - Groups cannot be removed, only switched off, so all are declared once.
	  - Nothing may be anchored TO a container. It sizes itself.
	  - It never says how many auras did not fit, so the handoff's "+n" is not
	    drawn.

	Method learned from Blizzard's own source (Blizzard_CustomAuraContainer.lua,
	Blizzard_CustomAuraButton.lua) and from how EllesmereUI_AuraKit.lua uses it.
]]

-- Room round a row for the glow (drawn at twice the square) and the tags. The
-- host clips to it, and that is what makes a line size a cap: whatever does
-- not fit wraps onto a second line outside the host and is not drawn.
local CLIP_PAD = SQ / 2
local WRAP_GAP = CLIP_PAD * 2

-- Groups in the order they lay out. RAID on a debuff means one YOU can
-- dispel; PLAYER means you (or your pet) cast it.
local FOREVER_TRAYS = {
	{ key = "playerBuffs", unit = "player", above = true, cancel = true,
	  groups = { { key = "buffs", filter = "HELPFUL", look = "plain" } } },
	{ key = "playerDebuffs", unit = "player", debuff = true,
	  groups = { { key = "dispel", filter = "HARMFUL|RAID", look = "dispel" },
	             { key = "debuffs", filter = "HARMFUL|!RAID", look = "plain" } } },
	{ key = "targetBuffs", unit = "target", above = true, alpha = 0.6,
	  groups = { { key = "buffs", filter = "HELPFUL", look = "faint" } } },
	{ key = "targetDebuffs", unit = "target", debuff = true,
	  groups = { { key = "mine", filter = "HARMFUL|PLAYER", look = "mine" },
	             { key = "theirs", filter = "HARMFUL|!PLAYER", look = "theirs",
	               theirs = true } } },
}
Aur.FOREVER_TRAYS = FOREVER_TRAYS

--- Does this client fill aura trays for us? Asked of the client, not the
--  flavour: Classic Era ships no Blizzard_AuraContainer, so the load fails.
function Aur.ContainersAvailable()
	if Aur._containers == nil then
		local AO, ok = C_AddOns, false
		if AO and AO.LoadAddOn and AO.IsAddOnLoaded then
			if not AO.IsAddOnLoaded("Blizzard_AuraContainer") then
				pcall(AO.LoadAddOn, "Blizzard_AuraContainer")
			end
			ok = AO.IsAddOnLoaded("Blizzard_AuraContainer") and AuraContainerSortMethod ~= nil
		end
		Aur._containers = ok and true or false
	end
	return Aur._containers
end

--- A rule formatter the client runs on the remaining time or stack count,
--  secret or not. Nil if this client will not take the rules.
local function RuleFormatter(points)
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
	local f = C_StringUtil.CreateNumericRuleFormatter()
	if not pcall(f.SetBreakpoints, f, points) then return nil end
	return f
end

local words
--- The tags' words, built once. Padded a space each side so the chip behind
--  has a margin, and empty where the tag should not show: a timer from
--  TIMER_UNDER up, a stack of one. Seconds round up, so a timer never reads 0
--  with time left.
local function Words()
	if words then return words end
	local R = Enum and Enum.NumericRuleFormatRounding
	words = {
		timer = RuleFormatter({
			{ threshold = 0, format = " %d ", step = 1, rounding = R and R.Up },
			{ threshold = TIMER_UNDER, format = "" },
		}),
		stack = RuleFormatter({
			{ threshold = 0, format = "" },
			{ threshold = 2, format = " %d ", step = 1, rounding = R and R.Down },
		}),
	}
	-- A permanent aura and one that has just run out say nothing either. The
	-- client copies the binding into every button it is handed to.
	if words.timer and C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
		local b = C_DurationUtil.CreateDurationTextBinding()
		b:SetFormatter(words.timer)
		b:SetZeroDurationText("")
		b:SetExpiredText("")
		words.timerOpts = { binding = b }
	elseif words.timer then
		words.timerOpts = { textFormatter = words.timer }
	end
	return words
end

--- What the client calls on every button it builds for one group: our only
--  chance to touch it.
--
--  An error in here kills the whole batch, so the body is caught and the
--  error kept for /lattice auras.
--- Tint a region by token and remember it, so a skin change can tint it again.
local function Paint(F, tex, token, alpha)
	local p = { tex = tex, token = token, alpha = alpha }
	F.paint[#F.paint + 1] = p
	local col = Palette.c[token]
	tex:SetVertexColor(col[1], col[2], col[3], alpha or col[4] or 1)
end

local function Initializer(lookKey, tray, F)
	local look = LOOKS[lookKey]
	return function(button)
		local ok, err = pcall(function()
			local c = Palette.c
			button:SetSize(SQ, SQ)
			if look.alpha then button:SetAlpha(look.alpha) end

			-- The edge is the square itself in the edge colour, with the icon on
			-- it inset by the edge's width. A one-texel ring drawn at 24px loses
			-- its hairline to resampling; a filled shape keeps it.
			local plate = button:CreateTexture(nil, "BACKGROUND")
			plate:SetTexture(Media.texture.slotMask)
			plate:SetAllPoints(button)
			Paint(F, plate, look.edge)

			if look.glow then
				local glow = button:CreateTexture(nil, "BACKGROUND", nil, -1)
				glow:SetTexture(Media.texture.slotGlow)
				glow:SetBlendMode("ADD")
				glow:SetPoint("CENTER", button, "CENTER")
				glow:SetSize(SQ * 2, SQ * 2)
				Paint(F, glow, look.edge, look.glow)
			end

			local w = look.width
			local icon = button:CreateTexture(nil, "ARTWORK")
			icon:SetPoint("TOPLEFT", button, "TOPLEFT", w, -w)
			icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -w, w)
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			W.AddMask(icon, button, Media.texture.slotMask, icon)

			-- The handoff's corners: the timer chip out past the bottom right,
			-- the stack chip out past the top right.
			local timer = Tag(button, c.auraTimer, c.auraChip)
			timer.text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, 1 - TAG_DROP)
			local stack = Tag(button, c.auraStackInk, c.auraStack)
			stack.text:SetPoint("TOPRIGHT", button, "TOPRIGHT", 4, TAG_DROP - 1)
			F.tags[#F.tags + 1] = { timer = timer, stack = stack }

			local cfg = A.Config:Module("auras")
			timer:SetShown(cfg.showTime ~= false)
			stack:SetShown(cfg.showCount ~= false)

			-- Handed over. From here on the client writes these, not us.
			button:SetIcon(icon)
			local say = Words()
			if not (say.timerOpts
				and pcall(button.SetDurationText, button, timer.text, say.timerOpts)) then
				-- The client's own words, always on, if it would not take ours.
				button:SetDurationText(timer.text, {})
				F.timerRule = false
			end
			button:SetApplicationCount(stack.text, say.stack and { formatter = say.stack } or {})

			if tray.cancel then
				button:SetCancelAuraButtons("RightButtonUp")
			else
				-- Clicks off, motion kept for the tooltip: a click on a square
				-- that cannot do anything should reach whatever is under it.
				pcall(button.SetMouseClickEnabled, button, false)
			end
			-- Away from the capsule, so the tooltip never covers it.
			pcall(button.SetTooltipAnchorPoint, button,
				tray.above and "ANCHOR_TOP" or "ANCHOR_BOTTOM")
		end)
		if not ok then F.initError = tostring(err) end
	end
end

--- One tray: a clipping host we own, and in it the client's container.
local function BuildTray(def, F)
	local t = { key = def.key, unit = def.unit, above = def.above,
		debuff = def.debuff, cancel = def.cancel, groups = def.groups,
		mirror = (def.unit == "target"), failed = {} }
	t.corner = (t.above and "BOTTOM" or "TOP") .. (t.mirror and "RIGHT" or "LEFT")

	local host = CreateFrame("Frame", nil, UIParent)
	host:SetClipsChildren(true)
	-- Sized for a fight and left there: a rest row is a shorter line in the
	-- same host, so nothing here is resized in combat.
	host:SetSize(CLIP_PAD * 2 + COMBAT * SQ_STEP - SQ_GAP, CLIP_PAD * 2 + SQ)
	t.host = host

	local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not ok or not c then
		t.failed[#t.failed + 1] = "container: " .. tostring(c)
		return t
	end
	t.container = c

	-- The tray's own strength goes here, not on the host: the host's alpha
	-- belongs to the fader when the unit frames are off.
	c:SetAlpha(def.alpha or 1)
	c:SetSize(1, 1)
	c:SetPoint(t.corner, host, t.corner,
		t.mirror and -CLIP_PAD or CLIP_PAD, t.above and CLIP_PAD or -CLIP_PAD)
	local FD = AnchorUtil.FlowDirection
	c:SetFlowLayoutAnchorPoint(t.corner)
	c:SetFlowLayoutGrowthDirection(t.mirror and FD.Left or FD.Right,
		t.above and FD.Up or FD.Down)
	c:SetFlowLayoutMaximumLineSize(REST * SQ_STEP - SQ_GAP)

	for i, g in ipairs(def.groups) do
		local okG, err = pcall(c.AddAuraGroup, c, g.key, g.filter, {
			maxFrameCount = REST,
			initializeFrame = Initializer(g.look, t, F),
			layout = { elementSpacing = SQ_GAP, lineSpacing = WRAP_GAP,
				groupLineSpacing = WRAP_GAP, layoutIndex = i },
		})
		if not okG then t.failed[#t.failed + 1] = g.key .. ": " .. tostring(err) end
	end

	-- The unit LAST: it is what registers UNIT_AURA, for the groups there are.
	c:SetUnit(def.unit)
	c:UpdateAllAuras()
	return t
end

function Aur:BuildForever()
	local F = { trays = {}, paint = {}, tags = {}, timerRule = true }
	self.forever = F
	for _, def in ipairs(FOREVER_TRAYS) do
		local t = BuildTray(def, F)
		F.trays[#F.trays + 1] = t
		F[t.key] = t
	end
	if not Words().timerOpts then F.timerRule = false end
end

--- Room left under the PLAYER capsule for the class resource tray, which
--  hangs from the same lower edge the player's debuffs do. Fixed for the
--  character rather than following the tray, which comes and goes in a fight
--  that these rows cannot move in - see Modules/Resources.lua.
local function TrayRoom(t)
	if t.unit ~= "player" or t.above then return 0 end
	local RS = A:GetModule("resources")
	return (RS and RS.ReserveHeight) and RS:ReserveHeight() or 0
end

--- Place every tray again, on whichever path this client draws them with.
--  The resource tray calls this when the room it needs changes.
function Aur:Reanchor()
	if self.forever then self:AnchorForever() else self:AnchorTrays() end
end

--- Hang each host off its capsule, and switch trays and groups on and off.
function Aur:AnchorForever()
	local cfg = A.Config:Module("auras")
	local off = cfg.offset or 6
	local UFm = A:GetModule("unitframes")
	local inset = (UFm and UFm.BarsInset) and UFm:BarsInset() or 0

	for _, t in ipairs(self.forever.trays) do
		local host = t.host
		t.enabled = TrayEnabled(cfg, t)

		local capsule = CapsuleFor(t.unit)
		host:ClearAllPoints()
		if capsule then
			if host:GetParent() ~= capsule then
				host:SetParent(capsule)
				host:SetFrameLevel(capsule:GetFrameLevel() + 6)
			end
			host:SetScale(1)
			-- The row's first square sits at the bars' start; the host is
			-- CLIP_PAD bigger all round.
			local edge = t.mirror and "RIGHT" or "LEFT"
			local x = (inset - CLIP_PAD) * (t.mirror and -1 or 1)
			local y = t.above and (off + TAG_DROP - CLIP_PAD)
				or -(off + TrayRoom(t) - CLIP_PAD)
			host:SetPoint(t.corner, capsule, (t.above and "TOP" or "BOTTOM") .. edge, x, y)
			A.Fader:Unregister(host)
		else
			-- Unit frames off: a free-standing row, where the Era trays go.
			if host:GetParent() ~= UIParent then host:SetParent(UIParent) end
			host:SetScale(A.db.profile.scale)
			host:SetPoint(t.above and "BOTTOM" or "TOP", UIParent, "BOTTOM",
				t.unit == "target" and 200 or -200, t.above and 300 or 180)
			A.Fader:Register(host, {})
		end

		-- A hidden container stops listening, which is what off should cost.
		host:SetShown(t.enabled)
		local c = t.container
		if c then
			for _, g in ipairs(t.groups) do
				if g.theirs then
					pcall(c.SetAuraGroupEnabled, c, g.key,
						not (SideFor(cfg, t).onlyMine == true))
				end
			end
		end
	end
end

--- Rest or combat: three squares a row, or eight. Only the container's own
--  numbers change - no frame of ours moves or resizes in a fight.
function Aur:SetEnergy(combat)
	local F = self.forever
	if not F then return end
	F.combat = combat and true or false
	local n = combat and COMBAT or REST
	for _, t in ipairs(F.trays) do
		local c = t.container
		if c then
			pcall(c.SetFlowLayoutMaximumLineSize, c, n * SQ_STEP - SQ_GAP)
			for _, g in ipairs(t.groups) do
				pcall(c.SetAuraGroupMaxFrameCount, c, g.key, n)
			end
		end
	end
end

--- Repaint the edges and show or hide the tags. These are our own regions on
--  the client's buttons; while auras are secret that can be refused, so it
--  waits for the fight to end rather than half happening.
function Aur:RestyleForever()
	local F = self.forever
	if not F then return end
	if Aur.AurasRestricted() then F.restylePending = true return end
	F.restylePending = nil

	local c = Palette.c
	for _, p in ipairs(F.paint) do
		local col = c[p.token]
		if col then
			pcall(p.tex.SetVertexColor, p.tex, col[1], col[2], col[3], p.alpha or col[4] or 1)
		end
	end
	local cfg = A.Config:Module("auras")
	for _, tag in ipairs(F.tags) do
		pcall(tag.timer.SetShown, tag.timer, cfg.showTime ~= false)
		pcall(tag.stack.SetShown, tag.stack, cfg.showCount ~= false)
	end
end

function Aur:EnableForever()
	if not self.forever then self:BuildForever() end

	-- The containers follow UNIT_AURA themselves. A new target is not an aura
	-- event, so that one is ours to pass on.
	A:RegisterEvent(self, "PLAYER_TARGET_CHANGED", function()
		Aur:UpdateUnit("target")
	end)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		Aur:HideBlizzard()
		Aur:UpdateAll()
	end)
	A:RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
		Aur:SetEnergy(true)
	end)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
		Aur:SetEnergy(false)
		if Aur.forever.restylePending then Aur:RestyleForever() end
	end)

	self:HideBlizzard()
	self:OnConfigChanged()
end

function Aur:OnEnable()
	if Aur.ContainersAvailable() then return self:EnableForever() end

	local cfg = A.Config:Module("auras")

	-- One spec table shared by all four displays, mutated in place on a config
	-- change. Four trays that could disagree about icon size is four trays that
	-- eventually do.
	self.spec = self.spec or {}
	self.spec.showTime  = cfg.showTime ~= false
	self.spec.showCount = cfg.showCount ~= false

	if not self.trays then
		self.trays = {}
		for i, t in ipairs(TRAYS) do
			local d = NewDisplay(t.key, self.spec, {
				unit = t.unit, filter = t.filter, debuff = t.debuff,
				growUp = t.above, mirror = (t.unit == "target"),
				-- The handoff's looks: the target's buffs faint, your debuffs on
				-- the target first and lit, what you can dispel off yourself
				-- first and red.
				look = (t.unit == "target" and not t.debuff) and "faint" or "plain",
				-- And at 60 %, as Forever's tray is. On the squares: the tray's
				-- own alpha is the fader's when the unit frames are off.
				alpha = (t.unit == "target" and not t.debuff) and 0.6 or nil,
				mineFirst = (t.unit == "target" and t.debuff) or nil,
				dispelFirst = (t.unit == "player" and t.debuff) or nil,
				-- Right-click cancels, and only on your own buffs. Safe here
				-- because this display shows every helpful aura in order, so
				-- tile N is always aura index N.
				cancel = t.cancel,
				-- Every slot a fight can show, built and placed up front.
				max = COMBAT,
			})
			self.trays[i] = { key = t.key, unit = t.unit, above = t.above,
				debuff = t.debuff, display = d }
			self[t.key] = d
		end
	end

	A:RegisterEvent(self, "UNIT_AURA", function(_, _, unit)
		Aur:UpdateUnit(unit)
	end)
	A:RegisterEvent(self, "PLAYER_TARGET_CHANGED", function()
		Aur:UpdateUnit("target")
	end)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		Aur:HideBlizzard()
		Aur:UpdateAll()
		Aur:Resettle()
	end)

	-- Three a row at rest, eight in a fight: the slots are placed already, so
	-- a fight only shows more of them.
	-- Our own flag: the event runs before the client's lockdown starts, so
	-- InCombatLockdown would still say rest inside it.
	A:RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
		Aur.fighting = true
		Aur:UpdateAll()
	end)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
		Aur.fighting = false
		Aur:UpdateAll()
		if Aur._anchorPending then
			Aur._anchorPending = nil
			Aur:AnchorTrays()
		end
		for _, t in ipairs(Aur.trays) do
			if t.display._primePending then t.display:Prime() end
			-- Everything the fight refused. The tray has been showing the right
			-- auras all along - only its geometry was stale - so re-reading the
			-- unit is the honest way to catch up rather than replaying a queue of
			-- calls that may no longer describe anything.
			if t.display._layoutPending then
				t.display._layoutPending = nil
				Aur:UpdateUnit(t.unit)
			end
		end
	end)

	A:RegisterTicker(self, function()
		for _, t in ipairs(Aur.trays) do
			if t.enabled then t.display:Tick() end
		end
	end)

	self:HideBlizzard()
	self:OnConfigChanged()
end

--- Re-read every tray a few times over the first few seconds after a load.
--
--  On login and on a zone change the server has not finished telling the client
--  about your own auras: they come back with a duration of zero for several
--  seconds before the real numbers arrive. A zero duration is indistinguishable
--  from a permanent aura, so every buff was being marked timeless - and a
--  timeless tile is one the ticker deliberately never looks at again, so the
--  timers stayed missing until the next UNIT_AURA happened to fire.
--
--  No event announces "the aura data is real now", so this simply asks again for
--  a while. Six passes over twelve seconds costs nothing and covers a slow load.
--
--  This is no longer what actually guarantees a timer turns up - the per-tile
--  re-poll in Display:Tick does that, and it does not stop after twelve seconds.
--  Resettle stays because it refreshes the icon, the count and the tint as well,
--  which the re-poll deliberately does not touch.
function Aur:Resettle()
	if not C_Timer or not C_Timer.NewTicker then return end
	if self._settle then self._settle:Cancel() end

	-- Thirty passes at two seconds - a full minute - rather than six passes at
	-- two.
	--
	-- The reasoning, which is worth keeping because I got here the long way. A
	-- full `Update` is the one code path *known* to produce correct output: the
	-- symptom people report is "the timers turn up the moment anything about my
	-- buffs changes", and what that fires is UNIT_AURA, and what UNIT_AURA runs
	-- is `Update`. The per-tile re-poll added alongside this is more surgical and
	-- ought to be sufficient, and after two attempts at reasoning out why it was
	-- not, the honest answer is that I do not know - so this leans on the path
	-- that demonstrably works and simply runs it again for long enough that no
	-- plausible login can outlast it.
	--
	-- Thirty full tray reads over a minute, once per login. It costs nothing
	-- measurable and it is not clever, which at this point is a feature.
	local left = 30
	self._settle = C_Timer.NewTicker(2, function()
		Aur:UpdateAll()
		left = left - 1
		if left <= 0 and Aur._settle then
			Aur._settle:Cancel()
			Aur._settle = nil
		end
	end, 30)
end

--- What the API is actually saying, tile by tile.
--
--  Every diagnosis in this addon that turned out to be wrong was made by reading
--  a screenshot and reasoning about a plausible mechanism; every one that held
--  came from printing the numbers. This prints the numbers.
function Aur:Diagnose()
	local F = self.forever
	if F then
		A:Print(A.F(L.auras.diagnose.forever, F.combat and "combat" or "rest"))
		DEFAULT_CHAT_FRAME:AddMessage(string.format(
			"   timer under %ds: %s   init error: %s", TIMER_UNDER,
			F.timerRule and "yes" or "no, the client's own words", tostring(F.initError)))
		for _, t in ipairs(F.trays) do
			DEFAULT_CHAT_FRAME:AddMessage(string.format(
				"   " .. A.Hi("%s") .. "  enabled=%s  container=%s  groups=%d  failed=%s",
				t.key, tostring(t.enabled), tostring(t.container ~= nil), #t.groups,
				#t.failed > 0 and table.concat(t.failed, "; ") or "none"))
		end
		return
	end

	local now = GetTime()
	A:Print(A.F(L.auras.diagnose.aura_diagnostic_gettime_1f, now,
		(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex)
			and "C_UnitAuras" or "UnitAura"))

	for _, tray in ipairs(self.trays or {}) do
		local d = tray.display
		DEFAULT_CHAT_FRAME:AddMessage(string.format(
			"   " .. A.Hi("%s") .. "  enabled=%s active=%s showTime=%s",
			tray.key, tostring(tray.enabled), tostring(d and d.active),
			tostring(self.spec and self.spec.showTime)))
		if not d then break end

		for i = 1, (d.active or 0) do
			local t = d.tiles[i]
			local name, _, _, _, duration, expiration = GetAura(t.unit, t.index, t.filter)
			DEFAULT_CHAT_FRAME:AddMessage(string.format(
				"      %d %-22s api dur=%s exp=%s remain=%s",
				i, tostring(name):sub(1, 22),
				tostring(duration), tostring(expiration),
				(tonumber(expiration) and string.format("%.1f", expiration - now)) or "-"))
			DEFAULT_CHAT_FRAME:AddMessage(string.format(
				"        tile dur=%s exp=%s timeless=%s stale=%s noTime=%s poll=%s text='%s'",
				tostring(t._duration), tostring(t._expiration),
				tostring(t._timeless), tostring(t._stale), tostring(t._noTime),
				(t._nextPoll and string.format("%.1f", t._nextPoll - now)) or "-",
				tostring(t.time and t.time:GetText())))
		end
	end
end

function Aur:UpdateUnit(unit)
	if self.forever then
		for _, t in ipairs(self.forever.trays) do
			if t.unit == unit and t.container then pcall(t.container.UpdateAllAuras, t.container) end
		end
		return
	end
	for _, t in ipairs(self.trays or {}) do
		if t.unit == unit and t.enabled then t.display:Update() end
	end
end

function Aur:UpdateAll()
	if self.forever then
		for _, t in ipairs(self.forever.trays) do
			if t.container then pcall(t.container.UpdateAllAuras, t.container) end
		end
		return
	end
	for _, t in ipairs(self.trays or {}) do
		if t.enabled then t.display:Update() end
	end
end

--- Hang each tray off its capsule: buffs above, debuffs below, the row
--  starting where the capsule's bars start (the handoff's, as on Forever).
function Aur:AnchorTrays()
	local cfg = A.Config:Module("auras")
	local scale = A.db.profile.scale
	local offset = cfg.offset or 6
	local UFm = A:GetModule("unitframes")
	local inset = (UFm and UFm.BarsInset) and UFm:BarsInset() or 0

	for _, t in ipairs(self.trays or {}) do
		local d = t.display
		local f = d.frame
		local capsule = CapsuleFor(t.unit)
		local side = SideFor(cfg, t)

		t.enabled = TrayEnabled(cfg, t)

		d.opts.growUp   = t.above
		d.opts.onlyMine = (t.debuff and t.unit == "target") and side.onlyMine or false

		-- Every geometry call below is off limits for a tray whose tiles carry
		-- cancel buttons, not just the reparent - the restriction reaches the
		-- ancestors of a protected frame, so scale, points and size all go the
		-- same way as SetParent. The options either side of this are plain table
		-- writes and are set whatever the client will allow.
		local locked = d:Locked()
		if locked then self._anchorPending = true end

		if capsule then
			if not locked and f:GetParent() ~= capsule then
				f:SetParent(capsule)
				f:SetFrameLevel(capsule:GetFrameLevel() + 6)
			end
			if not locked then
				f:SetScale(1)
				f:ClearAllPoints()
				if t.above then
					-- The timer tag hangs under its square: a row above the
					-- capsule stands that much further off it.
					f:SetPoint("BOTTOMLEFT",  capsule, "TOPLEFT",  0, offset + TAG_DROP)
					f:SetPoint("BOTTOMRIGHT", capsule, "TOPRIGHT", 0, offset + TAG_DROP)
				else
					local below = offset + TrayRoom(t)
					f:SetPoint("TOPLEFT",  capsule, "BOTTOMLEFT",  0, -below)
					f:SetPoint("TOPRIGHT", capsule, "BOTTOMRIGHT", 0, -below)
				end
			end

			d.opts.fillWidth = true
			d.opts.inset = inset

			A.Fader:Unregister(f)
		else
			-- Unit frames off: nowhere to nest, so fall back to a free-standing
			-- block rather than leaving the tray anchored to a frame that is gone.
			if not locked and f:GetParent() ~= UIParent then
				f:SetParent(UIParent)
			end
			if not locked then
				f:SetScale(scale)
				f:ClearAllPoints()
				f:SetPoint(t.above and "BOTTOM" or "TOP", UIParent, "BOTTOM",
					t.unit == "target" and 200 or -200, t.above and 300 or 180)
			end
			d.opts.fillWidth = nil
			d.opts.inset = 0
			-- Detached, so it no longer inherits the capsule's fade.
			A.Fader:Register(f, {})
		end

		if not t.enabled then d:Clear() end
	end
end

function Aur:OnDisable()
	if self.forever then
		for _, t in ipairs(self.forever.trays) do
			t.host:Hide()
			A.Fader:Unregister(t.host)
		end
		return
	end
	if self._settle then self._settle:Cancel(); self._settle = nil end
	for _, t in ipairs(self.trays or {}) do
		t.display:Clear()
		A.Fader:Unregister(t.display.frame)
	end
end

function Aur:OnSkinChanged()
	if self.forever then self:RestyleForever() return end
	for _, t in ipairs(self.trays or {}) do t.display:ApplySkin() end
	-- The tiles need nothing here. A buff tile is dressed by token and a debuff
	-- tile by its school, which is semantic and the same in all four skins - so
	-- between the central sweep and the palette there is nothing left for this
	-- to do, and an UpdateAll here would be a second owner for the same fact.
end

function Aur:OnConfigChanged()
	if self.forever then
		self:AnchorForever()
		self:RestyleForever()
		self:SetEnergy(InCombatLockdown and InCombatLockdown())
		self:UpdateAll()
		A.Fader:Refresh()
		return
	end

	local cfg = A.Config:Module("auras")

	self.spec.showTime  = cfg.showTime ~= false
	self.spec.showCount = cfg.showCount ~= false

	self:AnchorTrays()
	self:UpdateAll()
	if self.playerBuffs then self.playerBuffs:Prime() end
	A.Fader:Refresh()
end
