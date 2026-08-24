--[[--------------------------------------------------------------------------
	AetherUI :: Auras

	Four trays, one per unit per kind, all built from the same tile.

	  player buffs     above the player capsule, growing upward
	  player debuffs   below it, growing downward
	  target buffs     above the target capsule
	  target debuffs   below it

	A tile is the deck's buff pill with the name taken out of the middle: a
	frosted capsule holding a circular icon on the left, a stack count on its
	corner and the time remaining on the right.

	Why it looks like this
	----------------------
	The first design put debuff pills *inside* the capsule, under the bars, and
	grew the capsule downward to wrap them. It worked, and it was wrong: the
	frames resized constantly, and a player with a debuff next to a target
	without one gave you two frames of different heights sitting side by side.
	The fix is to take the auras out of the capsule entirely. Nothing grows, the
	two capsules are always the same shape, and the trays extend into empty space
	above and below where a changing height costs nothing.

	Dropping the aura *name* falls out of the same decision. A named pill is
	~100px wide and three of them already overflow a capsule; without the name
	the same pill is ~70 and four fit. The name is on the tooltip, which is where
	you go when you do not already recognise the icon - and if you do recognise
	it, the name was only ever taking up room the timer wanted.

	Nothing here is ever Hidden. See ParkTile: the player's buff tiles carry
	secure cancel buttons, and hiding a frame with a protected descendant is
	refused in combat, which is exactly when auras come and go.

	Every tray is capped to its own frame's width. Columns are derived from how
	wide the capsule actually is rather than configured, so widening the frames
	widens the trays and nothing ever hangs off the side of the unit it belongs
	to.

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
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local Aur = A:NewModule("auras")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- ---------------------------------------------------------------------------
-- aura source
-- ---------------------------------------------------------------------------

--- Returns: name, texture, count, auraType, duration, expirationTime, isMine
--
--  "Is this mine" comes from isFromPlayerOrPlayerPet / castByPlayer rather than
--  comparing sourceUnit to "player", because sourceUnit is nil for a fair few
--  auras and the comparison then quietly reports every one of them as someone
--  else's. Falls back to the comparison only when the flag is absent.
local function GetAura(unit, index, filter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local d = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
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

-- Debuff schools live in the palette - the ring is the only thing left that
-- says what kind of thing is on you, and the nameplate chips read the same
-- table. Resolved per call rather than cached, so a skin change reaches it.

-- Seconds left at which the timer turns red. Long enough to react to, short
-- enough that it is not on most of the time.
local URGENT = 5

-- What goes in the timer field of an aura that has no timer - a mount, a Well
-- Fed, most things a player is walking around with. The field is fixed width so
-- the pill keeps its size either way, and leaving it blank made the pill look
-- like it had failed to load rather than like it had nothing to say.
local NO_TIMER = "n/a"

-- How often a tile that claims to have no timer asks again. One API call for one
-- index, so a player walking around with five permanent buffs costs five calls a
-- second - nothing - and in exchange no tile can be wrong for ever.
local RECHECK = 1.0

--- Write a tile's timer field, and record whether what we wrote can be trusted.
--
--  There are three states here, not two, and collapsing them to two is what made
--  buff timers go missing after a login.
--
--    a real time            -> print it
--    duration 0             -> a permanent aura. "n/a", and believed.
--    duration, no future    -> neither. The server has not finished telling us
--    expiry                    about this aura yet, which lasts for several
--                              seconds after a login or a zone change.
--
--  That third case used to fall out of W.AuraTime as an empty string, which was
--  then written to the field and left there: the tile was not flagged timeless,
--  so the ticker kept running, and the ticker kept writing the same empty string
--  for the rest of the session. An empty field on a fixed-width pill is exactly
--  what "the timer never showed up" looks like.
--
--  Both of the last two set a flag that puts the tile on the re-poll list below.
--  A permanent aura is re-checked too, because "duration 0" and "the server has
--  not said yet" are the same value.
local function SetTimerText(t, c)
	if t._noTime then
		t.time:SetText("")
		t._timeless, t._stale = false, false
		return
	end

	local dur, exp = t._duration or 0, t._expiration or 0
	local text = (dur > 0 and exp > 0) and W.AuraTime(exp, dur) or ""

	if text == "" then
		t.time:SetText(NO_TIMER)
		t._timeless = (dur <= 0)
		t._stale    = (dur > 0)
		W.Color(t.time, c.textFaint)
	else
		t.time:SetText(text)
		t._timeless, t._stale = false, false
		W.Color(t.time, c.textDim)
	end
end

--- Ask the API again about one tile, cheaply.
--
--  This is the only thing standing between "the server had not told us the
--  duration yet" and a pill that reads n/a for the rest of the session, and it
--  costs one call for one index. It never rewrites anything but the clock: the
--  icon, the count and the tint all belong to Update.
local function Repoll(t, c)
	if not t.unit or not t.index then return end
	local name, _, _, _, duration, expiration = GetAura(t.unit, t.index, t.filter)
	if not name or name ~= t._name then return end
	if duration == t._duration and expiration == t._expiration then return end
	t._duration, t._expiration, t._urgent = duration, expiration, nil
	SetTimerText(t, c)
end

-- ---------------------------------------------------------------------------
-- the tile
-- ---------------------------------------------------------------------------

-- The deck's own buff pill, with the name taken out of the middle: icon on the
-- left, timer on the right, and the glass capsule around both. A timer *under*
-- the icon was the first attempt and it read badly - the pills stopped looking
-- like pills, and the number sat far enough from the icon that a row of them
-- scanned as two separate rows of things.
local PAD    = 4     -- pill edge -> icon
local GAP    = 7     -- icon -> timer field
local TAIL   = 8     -- timer field -> pill edge, past the rounded cap
local TIME_W = 30    -- fixed: a ticking timer must not resize the pill

--- Every pill is the same width whatever its timer says, so the grid stays a
--  grid and a permanent aura does not come out narrower than the rest.
local function TileWidth(spec)
	if not spec.showTime then return PAD + spec.size + TAIL end
	return PAD + spec.size + GAP + TIME_W + TAIL
end

--- The capsule is a little taller than the icon it wraps - the deck draws a 20px
--  icon in a 28px pill.
local function TileHeight(spec)
	return spec.size + 8
end

local function MakeIcon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(f)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	W.AddMask(icon, f, Media.texture.circleMask, f)
	f.icon = icon

	local ring = f:CreateTexture(nil, "OVERLAY")
	ring:SetTexture(Media.texture.ring)
	ring:SetAllPoints(f)
	f.ring = ring

	return f
end

--- Tooltip scripts live on whichever frame is actually on top: the tile itself,
--  or the secure cancel button covering it on the player's buff tray.
local function TileEnter(self)
	local p = self.__tile or self
	-- A parked tile keeps its slot and its mouse - moving it or disabling its
	-- mouse are both refused in combat - so "is this one on screen" is asked
	-- here, in Lua, where nothing can refuse it.
	if p._parked then return end
	if not p.unit or not p.index then return end
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

local function CreateTile(parent, spec)
	local t = Glass.CreatePill(parent, { shadow = A.db.profile.glass.shadow })

	t.art = MakeIcon(t, spec.size)
	t.art:SetPoint("LEFT", t, "LEFT", PAD, 0)

	-- Right-aligned against the pill's own edge rather than hung off the icon, so
	-- the timers line up in a column down the tray whatever they say.
	t.time = W.Text(t, "auraTime", "RIGHT")
	t.time:SetPoint("RIGHT", t, "RIGHT", -TAIL, 0)
	t.time:SetWidth(TIME_W)

	-- Overhanging the icon slightly is deliberate: a two-digit stack on a small
	-- circle has nowhere else to go, and the pill's padding is empty there.
	t.count = W.Text(t, "stack", "RIGHT")
	t.count:SetPoint("BOTTOMRIGHT", t.art, "BOTTOMRIGHT", 3, -1)

	t:EnableMouse(true)
	t:SetScript("OnEnter", TileEnter)
	t:SetScript("OnLeave", TileLeave)
	-- Inert unless the display sets _auraName, and unreachable while the secure
	-- button is covering the tile. See AddCancel.
	t:SetScript("OnMouseUp", CancelClicked)

	return t
end

--- Size is re-applied on every update rather than only at creation, so changing
--  the icon size in the options takes effect without rebuilding anything.
local function SizeTile(t, spec)
	t:SetSize(TileWidth(spec), TileHeight(spec))
	t.art:SetSize(spec.size, spec.size)
	if spec.showTime then t.time:Show() else t.time:Hide() end
	if spec.showCount then t.count:Show() else t.count:Hide() end
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
	t:SetAlpha(1)
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
	d.frame:SetSize(spec.size, spec.size)
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

--- A plain grid. Every tile is the same width now, which is what made this
--  simple: the old flow layout existed to pack pills of different widths, and
--  a row of identical squares needs nothing but multiplication.
--
--  Rows fill away from the capsule, so the row nearest the frame stays put as
--  auras come and go. Columns fill away from the unit's own leading edge - left
--  to right on the player, right to left on the mirrored target - so a half-full
--  row sits under the bars it belongs to rather than drifting under the orb.
--- Place the tiles.
--
--  `count` is how many slots to lay out and defaults to what is on screen. Prime
--  passes the display's maximum instead, so that every tile has a home before
--  combat starts and a buff gained mid-fight lands somewhere sensible rather
--  than nowhere at all - a frame that has never been given a point does not
--  draw, so without that pass a frozen tray would simply swallow anything new.
function Display:Arrange(count)
	if self:Locked() then
		-- Replayed on PLAYER_REGEN_ENABLED. Until then the tray keeps the layout
		-- it entered the fight with, which is the whole of what freezing costs.
		self._layoutPending = true
		return
	end

	local spec, opts = self.spec, self.opts
	local slots = count or self.active
	local gap = opts.spacing or 4
	local cols = math.max(1, opts.perRow or 1)
	local tw, th = TileWidth(spec), TileHeight(spec)
	local step = th + gap

	local vp = opts.growUp and "BOTTOM" or "TOP"
	local align = opts.align or "CENTER"

	local rows = math.ceil(slots / cols)
	for i = 1, slots do
		local r = math.ceil(i / cols)
		local c = (i - 1) % cols
		local y = opts.growUp and ((r - 1) * step) or (-(r - 1) * step)
		local t = self.tiles[i]
		if not t then break end
		t:ClearAllPoints()

		if align == "LEFT" then
			t:SetPoint(vp .. "LEFT", self.frame, vp .. "LEFT", c * (tw + gap), y)
		elseif align == "RIGHT" then
			t:SetPoint(vp .. "RIGHT", self.frame, vp .. "RIGHT", -c * (tw + gap), y)
		else
			-- Centred, and centred *per row* rather than as a block.
			--
			-- Mirroring the unit's own name and readout was the first answer and
			-- it looked wrong for a reason worth writing down: a row of pills
			-- almost never divides evenly into a capsule. Four pills across a
			-- 345px frame leave ~49px over, and pushed entirely onto one side
			-- that gap reads as a fifth pill that failed to load. Split in two it
			-- reads as margin.
			local n = math.min(cols, slots - (r - 1) * cols)
			local rowW = n * tw + (n - 1) * gap
			t:SetPoint(vp, self.frame, vp, -rowW / 2 + c * (tw + gap) + tw / 2, y)
		end
	end

	local h = math.max(1, rows * step - gap)
	if opts.fillWidth then
		-- Width comes from the capsule it spans, or LEFT and RIGHT alignment
		-- would both mean the same thing.
		self.frame:SetHeight(h)
	else
		self.frame:SetSize(math.max(1, math.min(slots, cols) * (tw + gap) - gap), h)
	end
end

--- The colour of one tile. Buffs are quiet; debuffs are the thing you are meant
--  to notice, so they take the school colour at full strength.
local function TintTile(t, debuff, auraType)
	local c = Palette.c
	local tint = auraType and c.debuffSchool[auraType]
	if debuff then
		tint = tint or { c.danger[1], c.danger[2], c.danger[3] }
		t:SetFillColor({ tint[1] * 0.35, tint[2] * 0.35, tint[3] * 0.35, 0.5 })
		t:SetEdgeColor({ tint[1], tint[2], tint[3], 0.45 })
		W.Tint(t.art.ring, tint, 0.95)
	else
		-- BY TOKEN, not by colour. A buff tile is plain glass, and saying so in
		-- the palette's own words is what puts it on the skin-change sweep -
		-- including the tiles currently out of play, which are parked off screen
		-- rather than hidden and come back the moment an aura lands.
		t:ApplySkin("glass", "glassEdge")
		tint = tint or c.accent
		W.Tint(t.art.ring, tint, 0.55)
	end
end

function Display:Update()
	local opts, spec = self.opts, self.spec
	local unit = opts.unit
	if not UnitExists(unit) then
		self:Clear()
		return
	end

	local c = Palette.c
	local shown = 0

	for index = 1, 40 do
		if shown >= (opts.max or 0) then break end

		local name, texture, count, auraType, duration, expiration, mine =
			GetAura(unit, index, opts.filter)
		if not name then break end

		if not opts.onlyMine or mine then
			shown = shown + 1
			local t = self:Acquire(shown)

			t.unit, t.index, t.filter = unit, index, opts.filter
			t.art.icon:SetTexture(texture)
			if opts.cancel then SetCancelName(t, name) end

			if not self:Locked() then SizeTile(t, spec) end
			t.count:SetText((spec.showCount and count and count > 1) and count or "")
			W.Color(t.count, c.text)

			-- The name is kept so a re-poll can prove it is still reading the same
			-- aura: indices shift as auras come and go, and pulling a neighbour's
			-- duration onto this tile would be worse than showing nothing.
			t._name = name
			t._expiration, t._duration, t._urgent = expiration, duration, nil
			t._noTime = (spec.showTime == false)
			t._nextPoll = GetTime() + RECHECK
			SetTimerText(t, c)

			TintTile(t, opts.debuff, auraType)
		end
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
	local c = Palette.c
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
				Repoll(t, c)
			end

		elseif t._expiration then
			local text = W.AuraTime(t._expiration, t._duration)
			if text == "" then
				-- Ran out from under us, or the expiry we were given has gone
				-- stale. Never leave the field blank; re-classify, then go back
				-- and ask. Nothing else in this branch applies once that has
				-- happened - in particular the urgent recolour would undo the
				-- colour SetTimerText just chose.
				SetTimerText(t, c)
				t._nextPoll = now + RECHECK
			else
				if text ~= t.time:GetText() then t.time:SetText(text) end

				-- Recoloured only on the crossing, not every tick: this runs ten
				-- times a second across four trays.
				local urgent = (t._expiration - now) <= URGENT
				if urgent ~= t._urgent then
					t._urgent = urgent
					W.Color(t.time, urgent and c.danger or c.textDim)
				end
			end
		end
	end
end

function Display:ApplySkin()
	local shadow = A.db.profile.glass.shadow
	for _, t in ipairs(self.tiles) do t:SetShadow(shadow) end
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

--- Exposed so the harness can assert a full row fits inside its capsule without
--  re-deriving the pill geometry and getting to agree with itself by accident.
function Aur:TileWidth() return TileWidth(self.spec) end
function Aur:TileHeight() return TileHeight(self.spec) end

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

function Aur:OnEnable()
	local cfg = A.Config:Module("auras")

	-- One spec table shared by all four displays, mutated in place on a config
	-- change. Four trays that could disagree about icon size is four trays that
	-- eventually do.
	self.spec = self.spec or {}
	self.spec.size      = cfg.size or 24
	self.spec.showTime  = cfg.showTime ~= false
	self.spec.showCount = cfg.showCount ~= false

	if not self.trays then
		self.trays = {}
		for i, t in ipairs(TRAYS) do
			local d = NewDisplay(t.key, self.spec, {
				unit = t.unit, filter = t.filter, debuff = t.debuff,
				growUp = t.above, spacing = cfg.spacing,
				-- Right-click cancels, and only on your own buffs. Safe here
				-- because this display shows every helpful aura in order, so
				-- tile N is always aura index N.
				cancel = t.cancel,
				max = 1,
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

	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
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
	local now = GetTime()
	A:Print(A.F("aura diagnostic  ·  GetTime %.1f  ·  source %s", now,
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
	for _, t in ipairs(self.trays or {}) do
		if t.unit == unit and t.enabled then t.display:Update() end
	end
end

function Aur:UpdateAll()
	for _, t in ipairs(self.trays or {}) do
		if t.enabled then t.display:Update() end
	end
end

--- Hang each tray off its capsule: buffs above, debuffs below.
--
--  Columns are derived, not configured. The tray spans the capsule exactly, so
--  "how many fit" is arithmetic on the frame's real width - which means the
--  answer is right after a resolution change, a scale change or a wider capsule
--  without anybody having to remember to update a number. It is also the whole
--  of "never wider than the frame it belongs to": there is no width to exceed,
--  because the width is where the column count came from.
function Aur:AnchorTrays()
	local cfg = A.Config:Module("auras")
	local scale = A.db.profile.scale
	local gap = cfg.spacing or 4
	local offset = cfg.offset or 6

	for _, t in ipairs(self.trays or {}) do
		local d = t.display
		local f = d.frame
		local capsule = CapsuleFor(t.unit)
		local side = SideFor(cfg, t)

		t.enabled = TrayEnabled(cfg, t)

		d.opts.spacing  = gap
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
					f:SetPoint("BOTTOMLEFT",  capsule, "TOPLEFT",  0, offset)
					f:SetPoint("BOTTOMRIGHT", capsule, "TOPRIGHT", 0, offset)
				else
					f:SetPoint("TOPLEFT",  capsule, "BOTTOMLEFT",  0, -offset)
					f:SetPoint("TOPRIGHT", capsule, "BOTTOMRIGHT", 0, -offset)
				end
			end

			-- The pill, not the icon: a tile is icon + timer + padding, and
			-- sizing the grid off the icon alone is how this first came out at
			-- thirteen columns in a frame with room for four.
			local tw = TileWidth(self.spec)
			local avail = math.max(tw, capsule:GetWidth() or tw)
			local cols = math.max(1, math.floor((avail + gap) / (tw + gap)))
			if (cfg.perRow or 0) > 0 then cols = math.min(cols, cfg.perRow) end

			d.opts.fillWidth = true
			d.opts.align   = (cfg.align == "MIRROR")
				and (capsule.mirror and "RIGHT" or "LEFT") or "CENTER"
			d.opts.perRow  = cols
			d.opts.max     = math.min(side.max or 16, cols * (side.maxRows or 2))

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
			d.opts.align   = "CENTER"
			d.opts.perRow  = cfg.perRow and cfg.perRow > 0 and cfg.perRow or 8
			d.opts.max     = side.max or 16
			-- Detached, so it no longer inherits the capsule's fade.
			A.Fader:Register(f, {})
		end

		if not t.enabled then d:Clear() end
	end
end

function Aur:OnDisable()
	if self._settle then self._settle:Cancel(); self._settle = nil end
	for _, t in ipairs(self.trays or {}) do
		t.display:Clear()
		A.Fader:Unregister(t.display.frame)
	end
end

function Aur:OnSkinChanged()
	for _, t in ipairs(self.trays or {}) do t.display:ApplySkin() end
	-- The tiles need nothing here. A buff tile is dressed by token and a debuff
	-- tile by its school, which is semantic and the same in all four skins - so
	-- between the central sweep and the palette there is nothing left for this
	-- to do, and an UpdateAll here would be a second owner for the same fact.
end

function Aur:OnConfigChanged()
	local cfg = A.Config:Module("auras")

	self.spec.size      = cfg.size or 24
	self.spec.showTime  = cfg.showTime ~= false
	self.spec.showCount = cfg.showCount ~= false

	self:AnchorTrays()
	self:UpdateAll()
	if self.playerBuffs then self.playerBuffs:Prime() end
	A.Fader:Refresh()
end
