--[[--------------------------------------------------------------------------
	AetherUI :: Resources - the class resource tray

	Round 17, ported from the Mists branch (archive/mop) to Classic Era and WoW
	Forever on 2026-10-07, because a rogue reported the combo points missing:
	UnitFrames hides the client's ComboFrame and nothing had taken its place.

	A slim glass shelf hung under the PLAYER capsule carrying whatever
	secondary resource this character has. On Era and Forever that is combo
	points - a rogue's, and a druid's in Cat Form - and the rest of the table
	(soul shards, runes, chi, holy power, eclipse, demonic fury, burning
	embers, shadow orbs) stays in, each row switching itself off on a client
	that reports no maximum for it.

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

	THE DEBUFFS UNDER IT. The player's debuff row hangs from the same lower edge
	of the capsule, so a character who can have a tray has the debuffs hung one
	tray lower - always, whether the tray is up or not. They cannot follow the
	tray up and down: it comes and goes with combat and a target, and the debuff
	rows are not ours to move in a fight (the containers on Forever, the cancel
	buttons on Era). See ReserveHeight, and Auras' player debuff anchor.

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
	ours: on Mists all three of that class's powers report a maximum, and
	Blizzard's own ShardBar picks between them with GetSpecialization. So a row
	may name a spec - but only where the client defines that spec's constant.
	A client with specs and no such constant decides by the maximum alone, and
	a client with no spec API drops the row.

	WHERE THE CLIENTS DIFFER
	------------------------
	  * COMBO POINTS are the TARGET'S on Era (and on Mists): read with
	    GetComboPoints("player", "target"), gone - not stale - when the target
	    is. On WoW Forever they are the PLAYER'S own power, as on the modern
	    client it is built on, and read with UnitPower. To be confirmed in game
	    on a Forever rogue.
	  * A DRUID'S COMBO POINTS are a Cat Form thing. The row is shown in Cat
	    Form only, asked of the form rather than of the maximum, which neither
	    client was ever seen to drop to zero outside it.
	  * WOW FOREVER MAY HIDE A POWER IN COMBAT (a secret value). A pip compares
	    numbers and a secret cannot be compared, so a secret reading draws the
	    sockets empty rather than erroring ten times a second.
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

local L = A.L
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

-- The client's Cat Form, as GetShapeshiftFormID answers it on both clients.
local CAT_FORM = 1

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

--- A reading as a plain number, or nil for a SECRET one - which WoW Forever
--  may hand us in combat, and which cannot be compared or summed.
local function Plain(v)
	if A.IsSecret and A.IsSecret(v) then return nil end
	return tonumber(v)
end

local function PowerMax(name, unmodified)
	local t = PowerType(name)
	if t == nil or not _G.UnitPowerMax then return 0 end
	local ok, v = pcall(_G.UnitPowerMax, "player", t, unmodified)
	return (ok and Plain(v)) or 0
end

local function Power(name, unmodified)
	local t = PowerType(name)
	if t == nil or not _G.UnitPower then return 0 end
	local ok, v = pcall(_G.UnitPower, "player", t, unmodified)
	return (ok and Plain(v)) or 0
end

--- This character's spec index, or nil where the client has no such notion.
local function Spec()
	local S = _G.C_SpecializationInfo
	if not S or not S.GetSpecialization then return nil end
	local ok, i = pcall(S.GetSpecialization)
	return ok and i or nil
end

--- Combo points: the target's on Era, the player's own on WoW Forever.
local function ComboPoints()
	if A.isCamelot then return Power("ComboPoints") end
	if not _G.GetComboPoints then return 0 end
	local ok, n = pcall(_G.GetComboPoints, "player", "target")
	return (ok and Plain(n)) or 0
end

--- Is this druid a cat? A client that cannot say gets the row on the
--  maximum's word alone, which is how the Mists build drew it.
local function InCatForm()
	if not _G.GetShapeshiftFormID then return true end
	local ok, id = pcall(_G.GetShapeshiftFormID)
	return ok and id == CAT_FORM
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
--  A CLIENT THAT WILL NOT ANSWER the fine question gets a unit of one, which is
--  the discrete drawing and never worse than what was there before.
local function Pips(key, hue, name, spec, token)
	return {
		key = key, kind = "pips", hue = hue, spec = spec, token = token,
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

local function Combo(form)
	return { key = "combo", kind = "pips", hue = "comboPoint", form = form,
		token = "COMBO_POINTS",
		max = function() return PowerMax("ComboPoints") end,
		fill = ComboPoints }
end

RS.TABLE = {
	WARLOCK = {
		-- SPEC-GATED on Mists, because all three of these report a maximum at
		-- once there and Blizzard's own ShardBar picks between them the same way.
		Pips("shards", "soulShard", "SoulShards", "SPEC_WARLOCK_AFFLICTION", "SOUL_SHARDS"),

		{ key = "fury", kind = "flow", hue = "demonicFury",
		  spec = "SPEC_WARLOCK_DEMONOLOGY", token = "DEMONIC_FURY",
		  max  = function() return PowerMax("DemonicFury") end,
		  fill = function() return Power("DemonicFury") end,
		  -- Metamorphosis, which is what the bar is for. A fraction of the
		  -- maximum rather than a spelled number: the cost is the client's and
		  -- the maximum is the client's, and one of the two moving without the
		  -- other is not a case that exists.
		  threshold = function() return PowerMax("DemonicFury") * 0.4 end },

		-- Ten units to an ember, which Pips works out from the client rather
		-- than being told - see there.
		Pips("embers", "burningEmber", "BurningEmbers", "SPEC_WARLOCK_DESTRUCTION",
			"BURNING_EMBERS"),
	},

	DEATHKNIGHT = {
		-- THE ONE STACKED CASE. Pips above, bar below, tray grows downward.
		{ key = "runes", kind = "pips", recharge = true,
		  max  = function() return _G.MAX_RUNES or 6 end,
		  -- Hue and fill are per socket here rather than per row, which is what
		  -- `each` means: a rune's colour is its type and its fill is its own
		  -- cooldown, and no two are necessarily the same.
		  each = Rune },

		{ key = "runicPower", kind = "flow", hue = "runicPower", token = "RUNIC_POWER",
		  max  = function() return PowerMax("RunicPower") end,
		  fill = function() return Power("RunicPower") end,
		  threshold = function() return 30 end },
	},

	MONK    = { Pips("chi",  "chi",       "Chi",        nil, "CHI") },
	PALADIN = { Pips("holy", "holyPower", "HolyPower",  nil, "HOLY_POWER") },
	PRIEST  = { Pips("orbs", "shadowOrb", "ShadowOrbs", nil, "SHADOW_ORBS") },

	-- COMBO POINTS, the one row Era and Forever actually draw. The cap is a
	-- power maximum; the value is the target's on Era and the player's on
	-- Forever. A rogue with no target on Era has five sockets and none lit,
	-- which is correct and is what the client means.
	ROGUE   = { Combo() },

	DRUID   = {
		-- In Cat Form only - see InCatForm.
		Combo("cat"),

		-- ECLIPSE. Centre-anchored, so `signed` says the fill runs out from the
		-- middle rather than up from the left, and the hue is chosen per draw
		-- from the direction rather than fixed on the row.
		{ key = "eclipse", kind = "flow", signed = true, hue = "eclipseSun",
		  token = "ECLIPSE",
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

-- ---------------------------------------------------------------------------
-- the preview
--
-- WHY THIS EXISTS. Most rows in the table above belong to a class or a spec
-- that is not on this client at all, and signing off how they LOOK otherwise
-- means levelling alts. The Death Knight is the only stacked case, the only
-- per-socket hue and the only recharging fill, and eclipse is the only bar that
-- runs both ways from a centre mark.
--
-- So the preview drives the tray from a script instead of from the client.
-- Every row is drawn by the SAME code the game drives - Rows returns these
-- instead of the real ones and nothing downstream knows the difference - so
-- what you are looking at is the drawing, not a mock-up of it.
--
-- NOTHING IS WRITTEN TO THE CLIENT and nothing is written to the profile.
-- ---------------------------------------------------------------------------

local DEMO_HOLD = 4.0      -- seconds on each set before moving to the next
local DEMO_STEP = 0.05     -- how often the scripted values move

--- The scripted value, 0..1, sawtooth: it climbs across the hold and starts
--  again, so a part-filled socket and a moving bar are visible.
local function DemoRamp()
	local t = ((GetTime and GetTime() or 0) % DEMO_HOLD) / DEMO_HOLD
	return t
end

--- Every set the preview walks, in the order it walks them. THE COUNTS AND
--  GRAINS ARE THE REAL ONES - four embers of ten units, six runes, three orbs.
local function DemoSets()
	local function pips(key, hue, n, unit)
		return {
			key = key, kind = "pips", hue = hue,
			max  = function() return n end,
			unit = function() return unit or 1 end,
			fill = function() return DemoRamp() * n * (unit or 1) end,
		}
	end

	local function flow(key, hue, max, tick, signed)
		return {
			key = key, kind = "flow", hue = hue, signed = signed,
			max  = function() return max end,
			fill = function()
				if signed then return (DemoRamp() * 2 - 1) * max end
				return DemoRamp() * max
			end,
			threshold = tick and function() return tick end or nil,
		}
	end

	return {
		{ name = L.resources.demo.combo,    rows = { pips("combo", "comboPoint", 5) } },
		{ name = L.resources.demo.shards,   rows = { pips("shards", "soulShard", 4) } },
		{ name = L.resources.demo.embers,
		  rows = { pips("embers", "burningEmber", 4, 10) } },
		{ name = L.resources.demo.fury,
		  rows = { flow("fury", "demonicFury", 1000, 400) } },
		-- THE ONE STACKED CASE.
		{ name = L.resources.demo.runes, rows = {
			{ key = "runes", kind = "pips",
			  max = function() return 6 end,
			  -- Per socket, as the real one is: two of each type, and one of
			  -- them part way through its recharge so the liquid fill is
			  -- actually on screen rather than merely possible.
			  each = function(i)
				local hue = RUNE_HUE[math.ceil(i / 2)] or "runeBlood"
				if i == 2 then return hue, DemoRamp() end
				return hue, 1
			  end },
			flow("runicPower", "runicPower", 100, 30),
		} },
		{ name = L.resources.demo.chi,      rows = { pips("chi", "chi", 4) } },
		{ name = L.resources.demo.holy,     rows = { pips("holy", "holyPower", 3) } },
		{ name = L.resources.demo.orbs,     rows = { pips("orbs", "shadowOrb", 3) } },
		{ name = L.resources.demo.eclipse,
		  rows = { flow("eclipse", "eclipseSun", 100, nil, true) } },
	}
end

--- Start, stop, or step the preview.
function RS:Demo(what)
	if what == "off" or (self._demo and what ~= "next") then
		self._demo = nil
		if self._demoTicker then
			self._demoTicker:Cancel()
			self._demoTicker = nil
		end
		self:Refresh()
		A:Print(L.resources.demo.off)
		return
	end

	if what == "next" and self._demo then
		self._demo.at = (self._demo.at % #self._demo.sets) + 1
	else
		self._demo = { sets = DemoSets(), at = 1, from = GetTime and GetTime() or 0 }
	end

	-- A TICKER, not an OnUpdate on the tray. The tray is hidden between sets on
	-- a character whose real rows are empty, and a script on a hidden frame does
	-- not run - which is how the first version of this appeared to do nothing at
	-- all on a warrior.
	if not self._demoTicker and C_Timer and C_Timer.NewTicker then
		self._demoTicker = C_Timer.NewTicker(DEMO_STEP, function() RS:DemoTick() end)
	end

	self:DemoTick(true)
	A:Print(A.F(L.resources.demo.showing_s,
		A.Hi(self._demo.sets[self._demo.at].name))
		.. "  ·  " .. A.Dim("/lattice resources demo off"))
end

function RS:DemoTick(announce)
	local d = self._demo
	if not d then return end

	local now = GetTime and GetTime() or 0
	if not announce and (now - d.from) >= DEMO_HOLD then
		d.at = (d.at % #d.sets) + 1
		d.from = now
		A:Print(A.F(L.resources.demo.showing_s, A.Hi(d.sets[d.at].name)))
	end

	self:Refresh()
end

--- Does a row's spec gate let it through?
--
--  A named spec has to match where the client defines that spec's constant
--  (Mists). Where it does not, but the client has specs (Forever), the
--  maximum alone decides. A client with no spec API drops the row - those
--  rows are all Mists ones.
local function SpecOk(row, spec)
	if not row.spec then return true end
	local want = _G[row.spec]
	if want ~= nil then return spec ~= nil and spec == want end
	return spec ~= nil
end

--- Every row this character actually has, in tray order.
function RS:Rows()
	-- THE PREVIEW STANDS IN HERE AND NOWHERE ELSE.
	if self._demo then return self._demo.sets[self._demo.at].rows end

	local _, class = UnitClass("player")
	local rows = self.TABLE[class or ""]
	if not rows then return {} end

	local spec = Spec()
	local out = {}
	for _, row in ipairs(rows) do
		local formOk = (row.form ~= "cat") or InCatForm()
		if SpecOk(row, spec) and formOk and (row.max() or 0) > 0 then
			out[#out + 1] = row
		end
	end
	return out
end

--- The rows this character CAN show, whatever form it is in right now - which
--  is what the debuffs make room for. A druid has room for the combo row in
--  every form, because shifting into Cat in a fight cannot move the debuffs.
function RS:PossibleRows()
	local _, class = UnitClass("player")
	local rows = self.TABLE[class or ""]
	if not rows then return {} end

	local spec = Spec()
	local out = {}
	for _, row in ipairs(rows) do
		if SpecOk(row, spec) and (row.form or (row.max() or 0) > 0) then
			out[#out + 1] = row
		end
	end
	return out
end

--- How much room the tray takes under the player capsule, in the capsule's
--  own units - which Auras adds to the player's debuff row so the two never
--  overlap. Zero when this character can never have a tray, the module is off,
--  or the tray is set never to show.
--
--  FIXED, NOT FOLLOWING THE TRAY. The tray comes and goes with combat and a
--  target; the debuff row cannot be moved in a fight. So the room is kept
--  whether the tray is up or not, for any character who can have one.
function RS:ReserveHeight()
	if not self.enabled then return 0 end
	if (cfg().display or "on") == "off" then return 0 end

	local h, n = 0, 0
	for _, row in ipairs(self:PossibleRows()) do
		n = n + 1
		h = h + ((row.kind == "pips") and PIP_SIZE or FLOW_H)
	end
	if n == 0 then return 0 end
	return TRAY_PAD_Y * 2 + h + ROW_GAP * (n - 1)
end

--- Tell the debuffs when the room they must leave has changed. Only ever a
--  change of character state (level, spec, settings) - never mid-fight in
--  practice, and Auras defers its own re-anchoring if it is.
function RS:Reserve()
	local h = self:ReserveHeight()
	if h == self._reserve then return end
	self._reserve = h
	local Aur = A:GetModule("auras")
	if Aur and Aur.enabled and Aur.Reanchor then Aur:Reanchor() end
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

	-- THE ORB, AND IT IS ONE TEXTURE WITH A GRADIENT ACROSS IT. A flat texture
	-- under a circle mask with a vertical gradient run across it, which is what
	-- the level disc does. A smaller light disc in the corner read on sight as
	-- a second dot sitting on the pip rather than light falling on it.
	p.orb = p:CreateTexture(nil, "ARTWORK")
	p.orb:SetTexture(Media.texture.flat)
	p.orb:SetAllPoints(p)
	W.AddMask(p.orb, p, Media.texture.circleMask, p.orb)

	-- THE RECHARGE FILL, which is a rune's and the ember's. Bottom-up, so it is
	-- a liquid level rather than a sweep: the handoff is explicit that there
	-- are no radial cooldowns anywhere in this interface.
	p.fill = p:CreateTexture(nil, "ARTWORK")
	p.fill:SetTexture(Media.texture.chipDisc)
	p.fill:Hide()

	p:SetAlpha(1)
	return p
end

--- Paint one pip. `state` is 0..1: 0 an empty socket, 1 a lit orb, and anything
--  between a socket filling up.
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

	-- CLIPPED, NEVER TUCKED BEHIND. Our panels are TRANSLUCENT, so a frame
	-- parked behind one reads straight through it. The tray is a clip window
	-- whose top edge is the reveal line, flush with the capsule's lower edge.
	-- Anything above it is not drawn at all. The glass inside is one corner
	-- radius taller than the window, so its top corners are cut off square and
	-- the shelf meets the capsule flush.
	local tray = CreateFrame("Frame", "AetherUIResourceTray", host)
	tray:SetPoint("TOP", host, "BOTTOM", 0, 0)   -- re-anchored in Refresh
	if tray.SetClipsChildren then pcall(tray.SetClipsChildren, tray, true) end

	-- ABOVE the capsule rather than below it: the clip does the hiding, and
	-- being above keeps the capsule's own shadow off the top of the shelf.
	tray:SetFrameStrata(host:GetFrameStrata())
	tray:SetFrameLevel((host:GetFrameLevel() or 1) + 1)

	-- THE CAPSULE'S OWN SURFACE, `glass` and not `glassStrong`, and NO SHADOW:
	-- the clip would cut it off, and the capsule above already casts one.
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
			-- ONE PATH FOR FULL, EMPTY AND FILLING. At a grain of one this is
			-- lit-or-not; at anything finer the socket fills instead of
			-- blinking on, so a shard still regenerating does not read as one
			-- you can spend.
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
		-- a name it has not got; until the generator pass draws them the
		-- readout stands in, which says the same thing in the same place.
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
	-- brightens and nothing else happens.
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

	-- AND ARRIVING IS NOT THE SAME AS TRAVELLING: in eclipse is one of two buffs.
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
	-- carry.
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

	-- THE TRAY HUGS ITS CONTENT AND NEVER EXCEEDS THE CAPSULE.
	local capW = host and host:GetWidth() or (widest + TRAY_PAD_X * 2)
	local want = widest + TRAY_PAD_X * 2

	-- ONE PHYSICAL PIXEL of overlap with the capsule closes the hairline two
	-- soft edges leave between them.
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
-- rather than vanishing - a full bar you cannot see is information lost.
-- ---------------------------------------------------------------------------

--- One of the tray's OWN resources changed: keep it up for the grace period,
--  and look again when that runs out.
--
--  THE LOOK AGAIN IS THE HALF THAT WAS MISSING. Nothing else re-checks once the
--  three seconds pass - visibility is only asked on an event - so a tray
--  touched as a fight ended stayed up until something else happened, which on
--  WoW Forever was indefinitely (reported, 2026-10-07). Only the newest timer
--  counts: a burst of changes is one wait from the last of them, not a queue.
function RS:Touch()
	self._changed = GetTime and GetTime() or 0
	self:UpdateVisibility()
	if _G.C_Timer and _G.C_Timer.After then
		local mark = {}
		self._graceMark = mark
		_G.C_Timer.After(GRACE + 0.05, function()
			if RS._graceMark == mark then RS:UpdateVisibility() end
		end)
	end
end

--- Is `token` - the power a UNIT_POWER event names - one of this tray's?
--  ENERGY IS NOT. A rogue's energy ticks the whole time it is short, and every
--  tick used to restart the grace period, so the tray never went away.
function RS:Owns(token)
	if not token then return false end
	for _, row in ipairs(self:Rows()) do
		if row.token == token then return true end
	end
	return false
end

--- On screen at `alpha`, cancelling any fade that was under way.
local function Appear(tray, alpha)
	if tray.__fading then
		tray:SetScript("OnUpdate", nil)
		tray.__fading = nil
	end
	tray:Show()
	tray:SetAlpha(alpha)
end

--- Off screen, now: no rows, or switched off. Nothing to ease out of.
local function Vanish(tray)
	if tray.__fading then
		tray:SetScript("OnUpdate", nil)
		tray.__fading = nil
	end
	tray:Hide()
end

--- Off screen, eased: the tray LEAVING because nothing is happening any more,
--  over the 0.3 seconds the handoff gives it, rather than blinking out.
local function FadeAway(tray)
	if not tray:IsShown() or tray.__fading then return end
	tray.__fading = true
	local from, t = tray:GetAlpha() or 1, 0
	tray:SetScript("OnUpdate", function(self, dt)
		t = t + (dt or 0)
		local p = math.min(1, t / FADE_TIME)
		self:SetAlpha(from * (1 - p))
		if p >= 1 then
			self:SetScript("OnUpdate", nil)
			self.__fading = nil
			self:Hide()
			self:SetAlpha(1)
		end
	end)
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
	if not self._rows or #self._rows == 0 then Vanish(tray) return end

	-- The preview ignores every rule below, including "off".
	if self._demo then
		Appear(tray, 1)
		return
	end

	local mode = cfg().display or "on"
	if mode == "off" then Vanish(tray) return end

	local combat = _G.InCombatLockdown and InCombatLockdown() or false
	local target = UnitExists and UnitExists("target") or false

	if combat or target then
		Appear(tray, 1)
		return
	end

	-- COMBAT ONLY takes the player at their word: no grace period and no idle
	-- state, because both of those are the tray being visible out of combat.
	if mode == "combat" then FadeAway(tray) return end

	local now = GetTime and GetTime() or 0
	if self._changed and (now - self._changed) < GRACE then
		Appear(tray, 1)
		return
	end

	if self:AllFull() then
		Appear(tray, IDLE_ALPHA)
		return
	end

	FadeAway(tray)
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function RS:OnEnable()
	if not self.tray then self:Build() end
	if not self.tray then return end

	-- UNIT_POWER_FREQUENT is the one that matters and the one Blizzard's own
	-- bars use: UNIT_POWER_UPDATE is throttled.
	--
	-- EVERY POWER REDRAWS, ONLY OURS KEEPS IT UP. The event names the power that
	-- moved, and only a change to one of the tray's own resources starts the
	-- grace period - energy ticking, mana coming back, rage decaying do not.
	for _, ev in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE",
		"UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
		A:RegisterEvent(self, ev, function(_, _, unit, token)
			if unit ~= "player" then return end
			RS:Refresh()
			if RS:Owns(token) then RS:Touch() end
		end)
	end

	-- Runes report on their own events; a rune coming back is not a power
	-- change and nothing above would hear it.
	for _, ev in ipairs({ "RUNE_POWER_UPDATE", "RUNE_TYPE_UPDATE" }) do
		A:RegisterEvent(self, ev, function() RS:Touch() RS:Refresh() end)
	end

	-- Combo points live on the target on Era, so changing target changes them
	-- - and the same event turns the tray on under the visibility rule.
	A:RegisterEvent(self, "PLAYER_TARGET_CHANGED", function()
		RS:Touch() RS:Refresh()
	end)

	-- Which ROW is live can change: a respec, a druid entering or leaving Cat
	-- Form. Which rows are POSSIBLE - the room the debuffs leave - changes only
	-- with level, spec and settings.
	A:RegisterEvent(self, "UPDATE_SHAPESHIFT_FORM", function() RS:Touch() RS:Refresh() end)
	for _, ev in ipairs({ "PLAYER_TALENT_UPDATE", "PLAYER_SPECIALIZATION_CHANGED",
		"PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP" }) do
		A:RegisterEvent(self, ev, function() RS:Refresh() RS:Reserve() end)
	end

	A:RegisterEvent(self, "ECLIPSE_DIRECTION_CHANGE", function()
		RS:Touch() RS:Refresh()
	end)

	for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		A:RegisterEvent(self, ev, function() RS:UpdateVisibility() end)
	end

	self:Refresh()
	self:Reserve()
end

function RS:OnDisable()
	if self.tray then self.tray:Hide() end
	-- The room under the capsule goes back to the debuffs.
	self:Reserve()
end

function RS:OnConfigChanged()
	if not self.tray then return end
	self:Refresh()
	self:Reserve()
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
