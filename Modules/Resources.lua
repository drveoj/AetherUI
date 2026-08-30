--[[--------------------------------------------------------------------------
	AetherUI :: Resources - the class resource tray

	Round 17. A slim glass shelf hung under the PLAYER capsule carrying whatever
	secondary resource this character has: soul shards, runes, chi, holy power,
	combo points, eclipse, demonic fury, burning embers, shadow orbs.

	TWO PRIMITIVES AND NO MORE, which is the handoff's first hard rule.

	  pips  countable and spendable. Sockets always drawn, so "3 of 5" is READ
	        rather than inferred - a row that shrinks as you spend tells you the
	        number you have and hides the number you could have.
	  flow  continuous, builds and drains. One bar, a numeric readout, and a
	        threshold tick at the value that matters.

	Every resource in the game maps onto one of them. The Death Knight is the
	only character who gets both at once, and that is a second row in the tray
	rather than a third kind of drawing.

	THE CAPSULE NEVER CHANGES SHAPE. The tray is a separate frame tucked under
	the capsule's lower edge, not a region inside it. That is not only a design
	rule: the player capsule carries a secure click-catcher, and SetHeight on a
	frame with a secure template is protected. A tray that grew the capsule
	would be a tray that could not appear mid-fight, which is the only time
	anybody is looking at it.

	Nor can the tray literally share the capsule's border, which is how the
	handoff describes it. There is no shared border in this API.

	CLIPPED, NEVER TUCKED BEHIND, which the bags drawer had already written down
	and which took three goes to read: our panels are TRANSLUCENT, so a frame
	parked behind one shows straight through it. The tray is a clip window whose
	top edge is flush with the capsule's foot; anything above that line is not
	drawn at all. The glass inside reaches a corner radius higher, so its top two
	corners are cut off square and the shelf meets the capsule flush - the
	handoff's "0 0 16 16" out of a nine-slice with one radius on all four.

	ONLY THE PLAYER. Not the party capsules - not even your own - not the target,
	not a nameplate. One place to look.

	WHAT IS TABLE-DRIVEN AND WHAT IS NOT
	------------------------------------
	The table below says, per resource: which primitive, which hue, and where
	the threshold sits. It does NOT say how many sockets. That number comes from
	UnitPowerMax every time it is drawn, because the client already accounts for
	the things that move it - Ascension takes chi from four to five, Boundless
	Conviction takes holy power from three to five, and the ember count is
	literally the maximum divided by ten. A count written down here is a number
	that can disagree with the game, and the handoff's own note says to verify
	them in implementation. The strongest version of that is not to hold them.

	WHICH ROW IS LIVE is the same question asked the same way: a resource whose
	UnitPowerMax is zero is a resource this character has not got. That is the
	probe idiom the rest of this addon uses, and it needs no spec API at all.

	The warlock is the exception, and it is Blizzard's exception rather than
	ours: all three of that class's powers report a maximum, and Blizzard's own
	ShardBar picks between them with C_SpecializationInfo.GetSpecialization().
	So a row may name a spec, and only the warlock's three do.

	THREE THINGS THE CLIENT SAYS DIFFERENTLY FROM THE HANDOFF
	--------------------------------------------------------
	  * COMBO POINTS ARE NOT ON YOU. On this client they are read with
	    GetComboPoints("player", "target") and they live on the TARGET. Lose the
	    target and they are gone - not stale, gone - so the row empties rather
	    than holding its last value, and UnitPower would answer zero all day.
	  * BURNING EMBERS NEED THE UNMODIFIED FLAG. UnitPower(unit, embers, true)
	    counts in tenths; without the third argument you get whole embers and
	    the partial fill the design asks for cannot be drawn at all.
	  * ECLIPSE'S SUN AND MOON ARE AURAS. The bar's position is the Balance
	    power, but WHICH eclipse you are in is buff 48517 or 48518, and the
	    direction of travel is GetEclipseDirection(). Three sources for one row.

	And two resources the handoff's table does not mention. Arcane charges are
	in the client's enum and are not a Mists thing. Brewmaster stagger is - it
	has a bar of its own - but it is a pool of damage owed rather than something
	built and spent, and putting it here would make the tray mean two things.
	Left out on purpose; see docs if it is ever wanted.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local RS = A:NewModule("resources")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

local function cfg() return A.Config:Module("resources") end

-- ---------------------------------------------------------------------------
-- geometry, in the handoff's pixels
-- ---------------------------------------------------------------------------

local PIP_SIZE   = 13
local PIP_GAP    = 7
local FLOW_W     = 190
local FLOW_H     = 6
local FLOW_GAP   = 8         -- bar to its numeric readout
local READOUT_W  = 34

local TRAY_PAD_X = 14
local TRAY_PAD_Y = 7
local ROW_GAP    = 7         -- between the two rows a Death Knight gets

-- The corner, and it is also how far the glass reaches up past the clip so its
-- top two corners are cut off square. See the clip window in Build.
local TRAY_CORNER = 16

-- 150ms pop on a pip arriving, 120ms fade on one spent. Both from the handoff.
local POP_TIME   = 0.15
local POP_SCALE  = 1.25
local SPEND_TIME = 0.12

local FADE_TIME  = 0.30      -- the tray leaving
local GRACE      = 3.0       -- how long a change keeps it on screen
local IDLE_ALPHA = 0.40      -- full resources, out of combat, on a builder

-- ---------------------------------------------------------------------------
-- reading the client
-- ---------------------------------------------------------------------------

--- The power enum, by name, or nil on a client that has not got that power.
--
--  BY NAME AND NOT BY NUMBER. Enum.PowerType is the client's own table and the
--  numbers in it are stable, but writing 14 in this file means nothing to
--  anybody reading it and means the wrong thing on a client that renumbers.
local function PowerType(name)
	local E = _G.Enum and _G.Enum.PowerType
	return E and E[name] or nil
end

local function PowerMax(name, unmodified)
	local t = PowerType(name)
	if t == nil or not _G.UnitPowerMax then return 0 end
	local ok, v = pcall(_G.UnitPowerMax, "player", t, unmodified)
	return (ok and tonumber(v)) or 0
end

local function Power(name, unmodified)
	local t = PowerType(name)
	if t == nil or not _G.UnitPower then return 0 end
	local ok, v = pcall(_G.UnitPower, "player", t, unmodified)
	return (ok and tonumber(v)) or 0
end

--- This character's spec index, or nil where the client has no such notion.
--
--  Era answers nil and always will, which is why nothing outside the warlock
--  rows asks - a table that needed a spec would be a table with no Era rows in
--  it at all.
local function Spec()
	local S = _G.C_SpecializationInfo
	if not S or not S.GetSpecialization then return nil end
	local ok, i = pcall(S.GetSpecialization)
	return ok and i or nil
end

--- Combo points, which are the target's and not the player's.
local function ComboPoints()
	if not _G.GetComboPoints then return 0 end
	local ok, n = pcall(_G.GetComboPoints, "player", "target")
	return (ok and tonumber(n)) or 0
end

-- Rune type -> the hue that rune is drawn in. The client's own numbering, from
-- RuneFrame_Shared: 1 blood, 2 frost, 3 unholy, 4 death.
local RUNE_HUE = { "runeBlood", "runeFrost", "runeUnholy", "runeDeath" }

--- One rune: its hue, and how far through its recharge it is.
--
--  READY IS NOT "COOLDOWN FINISHED". GetRuneCooldown answers a start and a
--  duration for a rune that is spent and a third value saying whether it is
--  usable; a rune that has never been spent this session answers a start of
--  zero, and dividing by that duration is how a full bar of runes came out
--  half lit in the first draft of this.
local function Rune(i)
	local hue = "runeBlood"
	if _G.GetRuneType then
		local ok, t = pcall(_G.GetRuneType, i)
		if ok and RUNE_HUE[t] then hue = RUNE_HUE[t] end
	end

	if not _G.GetRuneCooldown then return hue, 1 end
	local ok, start, duration, ready = pcall(_G.GetRuneCooldown, i)
	if not ok then return hue, 1 end
	if ready or not start or not duration or duration <= 0 then return hue, 1 end

	local now = GetTime and GetTime() or 0
	local done = (now - start) / duration
	if done < 0 then done = 0 elseif done > 1 then done = 1 end
	return hue, done
end

-- ---------------------------------------------------------------------------
-- the table
--
-- One entry per class. Each row says what to draw and how to read it; `max`
-- deciding zero is what takes the row out of the tray, so a character who has
-- respecced out of a resource loses its row without anything being told.
-- ---------------------------------------------------------------------------

--- A row of pips read off one power.
--
--  HOW FINE THE CLIENT COUNTS IS THE CLIENT'S ANSWER, not a fact written down
--  per resource. UnitPower takes an `unmodified` flag; with it the client
--  reports in its own smallest units, and the ratio between the two maxima IS
--  the size of one pip:
--
--    burning embers   40 / 4 = 10    a pip is ten units, and part-fills
--    anything 1:1      4 / 4 =  1    a pip is one unit, and never part-fills
--
--  Written as `unit = 10` on the ember row alone, which is what this was, the
--  code says "embers are the resource that builds up" - and that was wrong on
--  screen. A shard that is regenerating lit its socket the moment the rounded
--  number ticked over, so the second pip claimed to be spendable while it was
--  still filling. Asking the client instead means any resource with a grain
--  finer than one gets the fill for free, and any that has not is unaffected:
--  the arithmetic collapses to "lit or not" at a unit of one.
--
--  A CLIENT THAT WILL NOT ANSWER the fine question gets a unit of one, which is
--  the discrete drawing and never worse than what was there before.
local function Pips(key, hue, name, spec)
	return {
		key = key, kind = "pips", hue = hue, spec = spec,
		max  = function() return PowerMax(name) end,
		fill = function() return Power(name, true) end,
		unit = function()
			local whole = PowerMax(name)
			local fine  = PowerMax(name, true)
			if whole <= 0 or fine <= 0 then return 1 end
			local u = fine / whole
			return (u >= 1) and u or 1
		end,
	}
end

RS.TABLE = {
	WARLOCK = {
		-- SPEC-GATED, because all three of these report a maximum at once and
		-- Blizzard's own ShardBar picks between them the same way.
		Pips("shards", "soulShard", "SoulShards", "SPEC_WARLOCK_AFFLICTION"),

		{ key = "fury", kind = "flow", hue = "demonicFury",
		  spec = "SPEC_WARLOCK_DEMONOLOGY",
		  max  = function() return PowerMax("DemonicFury") end,
		  fill = function() return Power("DemonicFury") end,
		  -- Metamorphosis, which is what the bar is for. A fraction of the
		  -- maximum rather than a spelled number: the cost is the client's and
		  -- the maximum is the client's, and one of the two moving without the
		  -- other is not a case that exists.
		  threshold = function() return PowerMax("DemonicFury") * 0.4 end },

		-- Ten units to an ember, which Pips works out from the client rather
		-- than being told - see there.
		Pips("embers", "burningEmber", "BurningEmbers", "SPEC_WARLOCK_DESTRUCTION"),
	},

	DEATHKNIGHT = {
		-- THE ONE STACKED CASE. Pips above, bar below, tray grows downward.
		{ key = "runes", kind = "pips", recharge = true,
		  max  = function() return _G.MAX_RUNES or 6 end,
		  -- Hue and fill are per socket here rather than per row, which is what
		  -- `each` means: a rune's colour is its type and its fill is its own
		  -- cooldown, and no two are necessarily the same.
		  each = Rune },

		{ key = "runicPower", kind = "flow", hue = "runicPower",
		  max  = function() return PowerMax("RunicPower") end,
		  fill = function() return Power("RunicPower") end,
		  threshold = function() return 30 end },
	},

	MONK    = { Pips("chi",  "chi",       "Chi") },
	PALADIN = { Pips("holy", "holyPower", "HolyPower") },
	PRIEST  = { Pips("orbs", "shadowOrb", "ShadowOrbs") },

	-- COMBO POINTS ARE THE ONE ROW ERA ALSO GETS, and the one whose count and
	-- fill come from different places: the cap is a power maximum, the value is
	-- the target's. A rogue with no target has five sockets and none lit, which
	-- is correct and is what the client means.
	ROGUE   = { { key = "combo", kind = "pips", hue = "comboPoint",
	              max = function() return PowerMax("ComboPoints") end,
	              fill = ComboPoints } },

	DRUID   = {
		{ key = "combo", kind = "pips", hue = "comboPoint",
		  max = function() return PowerMax("ComboPoints") end,
		  fill = ComboPoints },

		-- ECLIPSE. Centre-anchored, so `signed` says the fill runs out from the
		-- middle rather than up from the left, and the hue is chosen per draw
		-- from the direction rather than fixed on the row.
		{ key = "eclipse", kind = "flow", signed = true, hue = "eclipseSun",
		  max  = function() return PowerMax("Balance") end,
		  fill = function() return Power("Balance") end },
	},
}

-- The two eclipse buffs, which are what "in eclipse" means. The bar's own value
-- says where you are travelling; these say whether you have arrived.
local ECLIPSE_LUNAR, ECLIPSE_SOLAR = 48518, 48517

local function HasAura(spellID)
	local C = _G.C_UnitAuras
	if not C or not C.GetPlayerAuraBySpellID then return false end
	local ok, aura = pcall(C.GetPlayerAuraBySpellID, spellID)
	return (ok and aura) and true or false
end

--- Every row this character actually has, in tray order.
function RS:Rows()
    local _, class = UnitClass("player")
	local rows = self.TABLE[class or ""]
	if not rows then return {} end

	local spec = Spec()
	local out = {}
	for _, row in ipairs(rows) do
		-- A named spec has to match; an unnamed one is decided by the maximum
		-- alone. A client with no spec API fails the first test and drops every
		-- row that names one, which is exactly right - those are all Mists rows.
		local specOk = true
		if row.spec then specOk = (spec ~= nil and spec == _G[row.spec]) end
		if specOk and (row.max() or 0) > 0 then out[#out + 1] = row end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- primitive 1: the pip
--
-- A socket that is always there, and an orb that lights inside it. Drawn as
-- three textures rather than one so the socket survives the orb being hidden -
-- the count is the thing being communicated, and it must not blink.
-- ---------------------------------------------------------------------------

local function BuildPip(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(PIP_SIZE, PIP_SIZE)

	-- the socket: a flat disc and a rim, the rim in the resource hue
	p.socket = p:CreateTexture(nil, "BACKGROUND")
	p.socket:SetTexture(Media.texture.chipDisc)
	p.socket:SetAllPoints(p)

	p.rim = p:CreateTexture(nil, "BORDER")
	p.rim:SetTexture(Media.texture.chipRim)
	p.rim:SetAllPoints(p)

	-- the glow, drawn at twice the pip and centred, which is how every other
	-- glow in this interface is drawn
	p.glow = p:CreateTexture(nil, "BACKGROUND", nil, -1)
	p.glow:SetTexture(Media.texture.ringGlow)
	p.glow:SetPoint("CENTER", p, "CENTER")
	p.glow:SetSize(PIP_SIZE * 2, PIP_SIZE * 2)
	p.glow:Hide()

	-- THE ORB, AND IT IS ONE TEXTURE WITH A GRADIENT ACROSS IT.
	--
	-- The handoff asks for a radial gradient lit from up and left. The first
	-- version of this drew the deep hue as a disc and put a smaller light disc
	-- into that corner, which is what a radial gradient is made of - and at
	-- thirteen pixels the highlight read as a SECOND DOT sitting on the pip
	-- rather than as light falling on it. Reported from the game on sight.
	--
	-- The level disc had already solved this and nobody looked: a flat texture
	-- under a circle mask with a vertical gradient run across it, which is
	-- W.SetGradient and Orb:SetColors. Not a radial gradient, and near enough
	-- at this size that the difference is not visible - which the two dots
	-- most certainly were.
	p.orb = p:CreateTexture(nil, "ARTWORK")
	p.orb:SetTexture(Media.texture.flat)
	p.orb:SetAllPoints(p)
	W.AddMask(p.orb, p, Media.texture.circleMask, p.orb)

	-- THE RECHARGE FILL, which is a rune's and nothing else's. Bottom-up, so it
	-- is a liquid level rather than a sweep: the handoff is explicit that there
	-- are no radial cooldowns anywhere in this interface.
	p.fill = p:CreateTexture(nil, "ARTWORK")
	p.fill:SetTexture(Media.texture.chipDisc)
	p.fill:Hide()

	p:SetAlpha(1)
	return p
end

--- Paint one pip. `state` is 0..1: 0 an empty socket, 1 a lit orb, and anything
--  between a socket filling up.
--
--  ONE FUNCTION FOR ALL THREE STATES rather than three, because the states are
--  a continuum and the two that are not were being drawn by separate code that
--  disagreed about the rim.
local function PaintPip(p, hue, state)
	local c = Palette.c.resource[hue] or Palette.c.resource.soulShard
	local light, deep = c[1], c[2]

	W.Tint(p.socket, Palette.c.resource.socket)
	W.Tint(p.rim, deep, 0.30)

	if state >= 1 then
		p.orb:Show()
		p.fill:Hide()
		-- Light at the top, deep at the bottom, which is the same lift the
		-- level disc gets and for the same reason: it reads as a lit sphere
		-- rather than as a coloured circle.
		W.SetGradient(p.orb, "VERTICAL", light, deep)
		p.glow:Show()
		W.Tint(p.glow, deep, 0.70)
	else
		p.orb:Hide()
		p.glow:Hide()
		if state > 0 then
			-- Bottom-up: the texture is cropped from the bottom of the disc and
			-- anchored there, so it rises rather than growing from the middle.
			p.fill:Show()
			W.Tint(p.fill, deep, 0.45)
			p.fill:ClearAllPoints()
			p.fill:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT")
			p.fill:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT")
			p.fill:SetHeight(PIP_SIZE * state)
			p.fill:SetTexCoord(0, 1, 1 - state, 1)
		else
			p.fill:Hide()
		end
	end
end

-- ---------------------------------------------------------------------------
-- primitive 2: the flow bar
-- ---------------------------------------------------------------------------

local function BuildFlow(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(FLOW_W + FLOW_GAP + READOUT_W, FLOW_H)

	f.bar = W.CreateBar(f, { height = FLOW_H, smooth = true })
	f.bar:SetWidth(FLOW_W)
	f.bar:SetPoint("LEFT", f, "LEFT")

	-- THE TICK, and it is drawn OVER the bar and past it at both ends. Two
	-- pixels of gold at the value that matters, standing three pixels proud so
	-- it is findable on a bar that is nearly full.
	f.tick = f:CreateTexture(nil, "OVERLAY")
	f.tick:SetTexture(Media.texture.flat)
	f.tick:SetSize(2, FLOW_H + 6)
	f.tick:Hide()

	f.readout = W.Text(f, "tbLabel", "RIGHT")
	f.readout:SetPoint("LEFT", f.bar, "RIGHT", FLOW_GAP, 0)
	f.readout:SetWidth(READOUT_W)

	-- The end glyph, which only the eclipse row has: sun or moon, swapping with
	-- the direction of travel.
	f.glyph = f:CreateTexture(nil, "OVERLAY")
	f.glyph:SetSize(12, 12)
	f.glyph:SetPoint("LEFT", f.bar, "RIGHT", FLOW_GAP, 0)
	f.glyph:Hide()

	return f
end

-- ---------------------------------------------------------------------------
-- the tray
-- ---------------------------------------------------------------------------

function RS:Build()
	local host = self:Host()
	if not host then return nil end

	-- CLIPPED, NEVER TUCKED BEHIND - and the bags drawer had already written
	-- this down, in a comment I did not read until the third go at this seam:
	--
	--   our panels are TRANSLUCENT. A drawer parked behind the bags window
	--   reads straight through the glass.
	--
	-- Which is exactly what was on screen. Three attempts at hiding the tray's
	-- top edge behind the capsule - four pixels, then ten, then clear of the
	-- capsule's shadow - and every one was the wrong IDEA rather than the wrong
	-- number, because a translucent capsule hides nothing. What was reported
	-- each time was the tray showing THROUGH the player frame.
	--
	-- So the tray is a clip window whose top edge is the reveal line, flush
	-- with the capsule's lower edge. Anything above it is not drawn at all: no
	-- level, no alpha, no strata, nothing to show through. The glass inside is
	-- one corner radius taller than the window, so its top corners are cut off
	-- square and the shelf meets the capsule flush - which is the handoff's
	-- "0 0 16 16" without a second nine-slice to draw it with.
	local tray = CreateFrame("Frame", "AetherUIResourceTray", host)
	tray:SetPoint("TOP", host, "BOTTOM", 0, 0)   -- re-anchored in Refresh
	if tray.SetClipsChildren then pcall(tray.SetClipsChildren, tray, true) end


	-- ABOVE the capsule now rather than below it. Below was only ever an
	-- attempt to hide the overlap; the clip does that, and being above means
	-- the capsule's own shadow no longer washes the top of the shelf - which
	-- is what read as a gap between the two.
	tray:SetFrameStrata(host:GetFrameStrata())
	tray:SetFrameLevel((host:GetFrameLevel() or 1) + 1)

	-- THE CAPSULE'S OWN SURFACE, which is `glass` and not `glassStrong`.
	--
	-- glassStrong is the token for a surface that has to stay READABLE - a cast
	-- bar, a tooltip - and it is a third more opaque. Reaching for it here was
	-- an over-correction to the tray looking pale, which was really the panel
	-- art's top-light falloff being clipped away; with the top gone the two
	-- tokens are simply two different greys, and the handoff says the tray's
	-- chrome is the capsule's. It is one object with the frame above it.
	--
	-- NO SHADOW. It would be cut off by the clip on the one side that matters,
	-- and the capsule above is already casting one.
	tray.glass = Glass.CreatePanel(tray, { corner = TRAY_CORNER, shadow = false })
	tray.glass:SetPoint("TOPLEFT", tray, "TOPLEFT", 0, TRAY_CORNER)
	tray.glass:SetPoint("BOTTOMRIGHT", tray, "BOTTOMRIGHT", 0, 0)
	tray.glass:ApplySkin("glass", "glassEdge")

	tray.pips = {}
	tray.flows = {}
	tray:Hide()

	self.tray = tray
	return tray
end

--- The frame the tray hangs from: the player capsule, and nothing else ever.
function RS:Host()
	local UF = A:GetModule("unitframes")
	if not UF or not UF.enabled then return nil end
	return UF.player
end

--- One pooled pip, built on demand and kept.
local function PipAt(tray, i)
	local p = tray.pips[i]
	if not p then
		p = BuildPip(tray)
		tray.pips[i] = p
	end
	return p
end

local function FlowAt(tray, i)
	local f = tray.flows[i]
	if not f then
		f = BuildFlow(tray)
		tray.flows[i] = f
	end
	return f
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------

--- Lay one pips row out and paint it. Returns its width and height.
local function DrawPips(tray, row, nextPip, y)
	local n = math.floor(row.max() or 0)
	if n <= 0 then return 0, 0, nextPip end

	local value = row.fill and (row.fill() or 0) or 0
	local unit  = (row.unit and row.unit()) or 1
	if unit <= 0 then unit = 1 end
	local width = n * PIP_SIZE + (n - 1) * PIP_GAP
	local x = -width / 2 + PIP_SIZE / 2

	for i = 1, n do
		local p = PipAt(tray, nextPip)
		nextPip = nextPip + 1
		p:ClearAllPoints()
		p:SetPoint("CENTER", tray, "TOP", x + (i - 1) * (PIP_SIZE + PIP_GAP),
			-(y + PIP_SIZE / 2))
		p:Show()

		if row.each then
			-- Per socket: a rune's hue and fill are its own.
			local hue, state = row.each(i)
			PaintPip(p, hue, state)
		else
			-- ONE PATH FOR FULL, EMPTY AND FILLING. There used to be two, and
			-- the discrete one lit a socket the instant the client's rounded
			-- count ticked over - so a shard still regenerating read as one you
			-- could spend. At a grain of one this is exactly the old arithmetic;
			-- at anything finer the socket fills instead of blinking on.
			local mine = value - (i - 1) * unit
			local state = mine / unit
			if state < 0 then state = 0 elseif state > 1 then state = 1 end
			PaintPip(p, row.hue, state)
		end
	end

	return width, PIP_SIZE, nextPip
end

--- Lay one flow row out and paint it.
local function DrawFlow(tray, row, nextFlow, y)
	local f = FlowAt(tray, nextFlow)
	nextFlow = nextFlow + 1

	local max = row.max() or 0
	local value = row.fill() or 0
	if max <= 0 then max = 1 end

	f:ClearAllPoints()
	f:SetPoint("TOP", tray, "TOP", 0, -y)
	f:Show()

	local hue = row.hue
	if row.signed then
		-- ECLIPSE. Which way you are heading decides the colour and the glyph,
		-- and the direction is the client's own answer rather than the sign of
		-- the value - a bar sitting at zero is still travelling somewhere.
		local dir = _G.GetEclipseDirection and _G.GetEclipseDirection() or nil
		hue = (dir == "moon") and "eclipseMoon" or "eclipseSun"

		-- NO SUN AND NO MOON ON THE SHEET YET. Media:SetIcon answers false for
		-- a name it has not got, and drawing on regardless would put the WHOLE
		-- atlas in a twelve-pixel square - unmistakable, but not what anybody
		-- wants shipped. Until the generator pass draws them the readout stands
		-- in, which says the same thing in the same place: a signed number is a
		-- direction and a distance.
		if Media:SetIcon(f.glyph, (dir == "moon") and "moon" or "sun") then
			f.glyph:Show()
			W.Tint(f.glyph, Palette.c.resource[hue][1], 0.9)
			f.readout:Hide()
		else
			f.glyph:Hide()
			f.readout:Show()
			f.readout:SetText(tostring(math.floor(value)))
		end
	else
		f.glyph:Hide()
		f.readout:Show()
		f.readout:SetText(tostring(math.floor(value)))
	end

	local c = Palette.c.resource[hue] or Palette.c.resource.runicPower
	W.Color(f.readout, c[1])

	if row.signed then
		-- Centre-anchored: the fill grows out of the middle, so the bar is
		-- driven by the ABSOLUTE value and re-anchored by the sign.
		local frac = math.abs(value) / max
		if frac > 1 then frac = 1 end
		f.bar:SetMinMaxValues(0, 1)
		f.bar:SetValue(frac)
		f.bar:SetReverseFill(value < 0)
		f.bar:ClearAllPoints()
		f.bar:SetPoint(value < 0 and "RIGHT" or "LEFT", f, "CENTER", 0, 0)
		f.bar:SetWidth(FLOW_W / 2)
	else
		f.bar:ClearAllPoints()
		f.bar:SetPoint("LEFT", f, "LEFT")
		f.bar:SetWidth(FLOW_W)
		f.bar:SetMinMaxValues(0, max)
		f.bar:SetValue(value)
	end

	-- CROSSING THE TICK IS THE READY SIGNAL, and it is the only one: the fill
	-- brightens and nothing else happens. No badge, no pulse - a resource that
	-- announces itself is a resource you cannot ignore when you want to.
	local past = false
	if row.threshold then
		local t = row.threshold() or 0
		past = value >= t
		f.tick:Show()
		W.Tint(f.tick, Palette.c.semanticGold, 1)
		f.tick:ClearAllPoints()
		f.tick:SetPoint("CENTER", f.bar, "LEFT", FLOW_W * (t / max), 0)
	elseif row.signed then
		-- The neutral centre mark takes the tick's place on a bidirectional
		-- bar: there is no threshold to cross, only a middle to be off.
		f.tick:Show()
		W.Tint(f.tick, Palette.c.textDim, 0.8)
		f.tick:ClearAllPoints()
		f.tick:SetPoint("CENTER", f, "CENTER", 0, 0)
	else
		f.tick:Hide()
	end

	-- AND ARRIVING IS NOT THE SAME AS TRAVELLING. On the eclipse row the bar's
	-- value says where you are heading; whether you are actually IN an eclipse
	-- is one of two buffs. That is the brightening, in place of a threshold
	-- there is no room for on a bar with a centre mark.
	if row.signed then
		past = HasAura(ECLIPSE_LUNAR) or HasAura(ECLIPSE_SOLAR)
	end

	f.bar:SetStatusBarColor(c[1][1], c[1][2], c[1][3], past and 1 or 0.8)

	return FLOW_W + FLOW_GAP + READOUT_W, FLOW_H, nextFlow
end

--- Rebuild the whole tray from the table. Cheap enough to run on every change:
--  it places frames it already has and paints them.
function RS:Refresh()
	local tray = self.tray
	if not tray then return end

	local rows = self:Rows()
	if #rows == 0 then
		tray:Hide()
		self._rows = rows
		return
	end

	local nextPip, nextFlow = 1, 1

	-- The clip window IS the visible shelf, so one padding down from its top is
	-- one padding down from the capsule's lower edge and there is no offset to
	-- carry. The version that had one put four soul shards up inside the health
	-- bar, and every check in the suite passed while it did.
	local host = self:Host()
	local widest, y = 0, TRAY_PAD_Y

	for i, row in ipairs(rows) do
		if i > 1 then y = y + ROW_GAP end
		local w, h
		if row.kind == "pips" then
			w, h, nextPip = DrawPips(tray, row, nextPip, y)
		else
			w, h, nextFlow = DrawFlow(tray, row, nextFlow, y)
		end
		if w > widest then widest = w end
		y = y + h
	end

	for i = nextPip, #tray.pips do tray.pips[i]:Hide() end
	for i = nextFlow, #tray.flows do tray.flows[i]:Hide() end

	-- THE TRAY HUGS ITS CONTENT AND NEVER EXCEEDS THE CAPSULE, which is the
	-- handoff's rule and also the only thing keeping a six-rune row from
	-- sticking out from under a narrow player frame.
	local capW = host and host:GetWidth() or (widest + TRAY_PAD_X * 2)
	local want = widest + TRAY_PAD_X * 2

	-- FLUSH IS NOT QUITE FLUSH. Both surfaces carry a soft edge of their own,
	-- and two of them meeting on the same line leave a hairline of background
	-- showing between - small, and the last thing on screen still saying these
	-- are two objects.
	--
	-- ONE PHYSICAL PIXEL of overlap closes it. Physical rather than a frame
	-- unit because everything here is drawn at profile scale: a flat 1 is 0.71
	-- of a pixel at the default and lands between rows, which is the same
	-- correction the type shadow and the tooltip rim already make.
	tray:ClearAllPoints()
	tray:SetPoint("TOP", host, "BOTTOM", 0, (A.PxIn and A:PxIn(tray)) or 1)
	tray:SetSize(math.min(want, capW), y + TRAY_PAD_Y)

	self._rows = rows
	self:UpdateVisibility()
end

-- ---------------------------------------------------------------------------
-- visibility
--
-- In combat, or with a target, or within three seconds of a change. Otherwise
-- gone. The exception is a full builder out of combat, which fades to 40%
-- rather than vanishing - a full bar you cannot see is information lost, and
-- that is the one state where the answer matters and nothing is happening.
-- ---------------------------------------------------------------------------

function RS:Touch()
	self._changed = GetTime and GetTime() or 0
	self:UpdateVisibility()
end

--- Is every row of this character's tray full?
function RS:AllFull()
	for _, row in ipairs(self._rows or {}) do
		local max = row.max() or 0
		if row.each then
			for i = 1, math.floor(max) do
				local _, state = row.each(i)
				if state < 1 then return false end
			end
		else
			local value = row.fill and (row.fill() or 0) or 0
			if row.signed then return false end
			if value < max then return false end
		end
	end
	return true
end

function RS:UpdateVisibility()
	local tray = self.tray
	if not tray then return end
	if not self._rows or #self._rows == 0 then tray:Hide() return end

	local mode = cfg().display or "on"
	if mode == "off" then tray:Hide() return end

	local combat = _G.InCombatLockdown and InCombatLockdown() or false
	local target = UnitExists and UnitExists("target") or false

	if combat or target then
		tray:Show()
		tray:SetAlpha(1)
		return
	end

	-- COMBAT ONLY takes the player at their word: no grace period and no idle
	-- state, because both of those are the tray being visible out of combat and
	-- that is the thing being switched off.
	if mode == "combat" then tray:Hide() return end

	local now = GetTime and GetTime() or 0
	if self._changed and (now - self._changed) < GRACE then
		tray:Show()
		tray:SetAlpha(1)
		return
	end

	if self:AllFull() then
		tray:Show()
		tray:SetAlpha(IDLE_ALPHA)
		return
	end

	tray:Hide()
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function RS:OnEnable()
	if not self.tray then self:Build() end
	if not self.tray then return end

	-- UNIT_POWER_FREQUENT is the one that matters and the one Blizzard's own
	-- bars use: UNIT_POWER_UPDATE is throttled and a chi pip that lights a
	-- quarter-second late is a chi pip you spent without seeing.
	for _, ev in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE",
		"UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
		A:RegisterEvent(self, ev, function(_, _, unit)
			if unit == "player" then RS:Touch() RS:Refresh() end
		end)
	end

	-- Runes report on their own events; a rune coming back is not a power
	-- change and nothing above would hear it.
	for _, ev in ipairs({ "RUNE_POWER_UPDATE", "RUNE_TYPE_UPDATE" }) do
		A:RegisterEvent(self, ev, function() RS:Touch() RS:Refresh() end)
	end

	-- Combo points live on the target, so changing target changes them - and
	-- the same event is what turns the tray on under the visibility rule.
	A:RegisterEvent(self, "PLAYER_TARGET_CHANGED", function()
		RS:Touch() RS:Refresh()
	end)

	-- Which ROW is live can change: a respec moves a warlock between three
	-- different resources, and a druid leaving cat form has no combo points.
	for _, ev in ipairs({ "PLAYER_TALENT_UPDATE", "PLAYER_SPECIALIZATION_CHANGED",
		"UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP" }) do
		A:RegisterEvent(self, ev, function() RS:Refresh() end)
	end

	A:RegisterEvent(self, "ECLIPSE_DIRECTION_CHANGE", function()
		RS:Touch() RS:Refresh()
	end)

	for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		A:RegisterEvent(self, ev, function() RS:UpdateVisibility() end)
	end

	self:Refresh()
end

function RS:OnDisable()
	if self.tray then self.tray:Hide() end
end

function RS:OnConfigChanged()
	if not self.tray then return end
	self:Refresh()
end

function RS:OnSkinChanged()
	-- The tray's chrome follows the skin; the resource hues do not, which is
	-- why Refresh repaints everything and none of it reads Palette.c.accent.
	if not self.tray then return end
	if self.tray.glass and self.tray.glass.ApplySkin then
		self.tray.glass:ApplySkin("glass")
	end
	self:Refresh()
end
