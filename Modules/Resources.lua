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
	handoff describes it. There is no shared border in this API. It is drawn as
	its own rounded surface with its top edge suppressed and its top four pixels
	behind the capsule, which reads as one shape and is two.

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

--- HOW FAR THE TRAY'S TOP HIDES BEHIND THE CAPSULE, and it is not a constant.
--
--  Two goes at this were wrong for the same reason and neither was arithmetic
--  anybody could have argued with: the number was picked to look right and it
--  did not. What is actually in the way is the CAPSULE'S OWN SHADOW. A pill
--  draws its shadow at a spread of height/4 - Core/Glass.lua says so, and says
--  the geometry is fixed because the hole in the shadow has to line up with the
--  shape - so a 64-tall capsule casts sixteen units of shade below its foot,
--  and any tray whose top edge appears inside that band appears through a dark
--  wash. That reads as a gap, which is exactly what was reported: twice.
--
--  So the tuck clears the shadow rather than guessing at it, and it tracks the
--  capsule height, which is a setting between 48 and 96.
local function TuckFor(host)
	local h = (host and host:GetHeight()) or 64
	return math.floor(h / 4) + 2
end

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

--- Pips read straight off a power: how many are lit, and how many sockets.
local function PipsFrom(name)
	return {
		max  = function() return PowerMax(name) end,
		fill = function() return Power(name) end,
	}
end

RS.TABLE = {
	WARLOCK = {
		-- SPEC-GATED, because all three of these report a maximum at once and
		-- Blizzard's own ShardBar picks between them the same way.
		{ key = "shards", kind = "pips", hue = "soulShard",
		  spec = "SPEC_WARLOCK_AFFLICTION",
		  max  = function() return PowerMax("SoulShards") end,
		  fill = function() return Power("SoulShards") end },

		{ key = "fury", kind = "flow", hue = "demonicFury",
		  spec = "SPEC_WARLOCK_DEMONOLOGY",
		  max  = function() return PowerMax("DemonicFury") end,
		  fill = function() return Power("DemonicFury") end,
		  -- Metamorphosis, which is what the bar is for. A fraction of the
		  -- maximum rather than a spelled number: the cost is the client's and
		  -- the maximum is the client's, and one of the two moving without the
		  -- other is not a case that exists.
		  threshold = function() return PowerMax("DemonicFury") * 0.4 end },

		-- TENTHS, NOT EMBERS. The unmodified flag is what makes a part-filled
		-- ember drawable; without it this is four steps and the design's
		-- partial fill has nothing to fill with.
		{ key = "embers", kind = "pips", hue = "burningEmber", partial = true,
		  spec = "SPEC_WARLOCK_DESTRUCTION",
		  unit = 10,
		  max  = function() return PowerMax("BurningEmbers", true) end,
		  fill = function() return Power("BurningEmbers", true) end },
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

	MONK    = { { key = "chi",   kind = "pips", hue = "chi",
	              max = function() return PowerMax("Chi") end,
	              fill = function() return Power("Chi") end } },

	PALADIN = { { key = "holy",  kind = "pips", hue = "holyPower",
	              max = function() return PowerMax("HolyPower") end,
	              fill = function() return Power("HolyPower") end } },

	PRIEST  = { { key = "orbs",  kind = "pips", hue = "shadowOrb",
	              max = function() return PowerMax("ShadowOrbs") end,
	              fill = function() return Power("ShadowOrbs") end } },

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

	local tray = CreateFrame("Frame", "AetherUIResourceTray", host)

	-- BEHIND THE CAPSULE, WHICH IS THE WHOLE OF THE TUCK WORKING.
	--
	-- A child draws above its parent by default, so the overlapping top of the
	-- tray was being drawn ON TOP of the capsule's foot - a rounded lip across
	-- the bottom of the player frame, which is exactly the seam the tuck exists
	-- to hide. One level below the capsule and the capsule covers it instead.
	tray:SetFrameStrata(host:GetFrameStrata())
	tray:SetFrameLevel(math.max(0, (host:GetFrameLevel() or 1) - 1))

	-- Its own surface, not the capsule's - there is no shared border in this
	-- API. The handoff's 0 0 16 16 is a corner of 16 with the top two hidden
	-- behind the capsule, and NO SHADOW: the capsule already casts one, and a
	-- second from a frame overlapping it draws a dark band across the seam.
	--  DARKER THAN THE CAPSULE, not the same. The handoff's tray is rgba(12,10,
	--  28,.6) against a capsule that is lighter, and the default panel surface
	--  came out as a pale slab under a dark frame - the panel art carries a
	--  top-light falloff in its alpha, which is flattering at a window's size
	--  and washes out a shelf thirty pixels tall. glassStrong is the token for
	--  a surface that has to stay readable, and it is the nearest to the
	--  handoff's own alpha.
	tray.glass = Glass.CreatePanel(tray, { corner = 16, shadow = false })
	tray.glass:SetAllPoints(tray)
	tray.glass:ApplySkin("glassStrong", "glassEdge")

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
	if row.unit then n = math.floor(n / row.unit) end
	if n <= 0 then return 0, 0, nextPip end

	local value = row.fill and (row.fill() or 0) or 0
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
		elseif row.partial then
			-- Tenths: this pip is full, empty, or the one being filled.
			local unit = row.unit or 1
			local mine = value - (i - 1) * unit
			local state = mine / unit
			if state < 0 then state = 0 elseif state > 1 then state = 1 end
			PaintPip(p, row.hue, state)
		else
			PaintPip(p, row.hue, i <= value and 1 or 0)
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

	-- CONTENT STARTS BELOW THE TUCK, and the version that did not is the one
	-- that put the pips inside the player frame.
	--
	-- The tray's frame is taller than the shelf you see: its top edge is up
	-- behind the capsule, clear of the shadow that capsule casts. So a row
	-- placed one padding down from the TOP OF THE FRAME is placed one padding
	-- down from a point well above the capsule's foot - which is exactly where
	-- four soul shards were last seen, tucked up under the health bar.
	--
	-- Everything below measures from the top of the VISIBLE shelf instead.
	local host = self:Host()
	local tuck = TuckFor(host)
	local widest, y = 0, tuck + TRAY_PAD_Y

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

	-- ANCHORED HERE rather than at build, because the tuck follows the capsule
	-- height and that is a setting the player can move.
	tray:ClearAllPoints()
	tray:SetPoint("TOP", host, "BOTTOM", 0, tuck)
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
