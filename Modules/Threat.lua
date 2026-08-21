--[[--------------------------------------------------------------------------
	AetherUI :: Threat - the engine

	WHAT EACH UNIT'S THREAT IS, AND WHICH OF THREE TIERS THAT PUTS IT IN.
	Nothing here draws. The ring, the chips, the washes and the screen alarm all
	read this and are built on top of it - see docs/PLAN-Threat.md, phases 2-5.

	It is one place on purpose. The handoff's hard rule is that a capsule shows
	EXACTLY ONE tier at a time, and that is only enforceable if one piece of code
	decides which; spread across the player frame, the party capsules and the
	nameplates it becomes three sets of thresholds that agree until they do not.

	THE NUMBERS ARE THE SERVER'S. UnitDetailedThreatSituation answers on this
	client - measured, not assumed, and the first draft of the plan got that
	wrong by treating "the function is declared" as "the server answers it".
	Its scaledPercentage IS the design's "threat divided by pull threshold", with
	the 110% melee / 130% ranged rule already applied. We do not compute it and
	we must not.

	AND THE AGGRO MODIFIER COMES FREE WITH IT. For a unit that is not holding
	aggro, rawPercentage is measured against the holder's threat and
	scaledPercentage against the pull threshold, which is the holder's times 1.1
	or 1.3 - so raw/scaled IS the modifier the server used. NKThreat measures the
	same thing by probing a per-class spell's range through the spellbook with an
	item-range fallback and a half-second cache; it does not have to, and reading
	it is the better answer anyway. Measuring tells you where you were standing
	when you asked. This tells you what the server decided.

	NOTHING IS NOT ZERO. The call returns NOTHING for a unit that is not on that
	mob's table, which is most units most of the time. Coerce that to zero and a
	DPS who has cast nothing reads as a DPS at the bottom of the ring's travel -
	and the design's whole quiet-by-default rule turns into a ring that is always
	on. Every read here keeps nil as nil.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local TH = A:NewModule("threat")

local function cfg() return A.Config:Module("threat") end

-- ---------------------------------------------------------------------------
-- the shape of the answer
-- ---------------------------------------------------------------------------

-- 16c: three tiers, strictly ordered, one at a time.
--
--   NONE  nothing drawn at all, which is the common case and the good one
--   RING  ambient - the ring alone, and only a tank holding securely gets it
--   WARN  gold: the state is about to flip, and this is the act-now window
--   FAIL  red: it has flipped
TH.TIER = { NONE = 0, RING = 1, WARN = 2, FAIL = 3 }
local TIER = TH.TIER

-- 16b, and the handoff is explicit that these are NOT user-configurable.
--
-- RING_FLOOR is where a non-holder's ring appears and where its warning fires
-- together - 16a shows the two happening at the same moment, and a ring that
-- appeared silently before the chip would be a fourth state nobody asked for.
local RING_FLOOR = 70

-- A TANK IS LOSING GRIP WHEN THE RUNNER-UP IS PAST 90% OF THEIR THREAT, which
-- is what the design says and is NOT what `status` reports: status turns 2 at
-- 100%, by which time the act-now window has closed. UnitThreatPercentageOfLead
-- gives the holder's threat as a percentage of the runner-up's - 1175% when the
-- holder has 4700 against 400 - so 90% of yours is 1/0.9 of theirs.
local GRIP_LEAD = 100 / 0.90

-- How often the table is re-read. The events below say "something moved" and a
-- poll covers what they do not: UNIT_THREAT_LIST_UPDATE arrives naming
-- `softenemy` rather than `target` on this client, and neither event fires when
-- you simply change target.
local POLL = 0.2

-- HOW FAR AHEAD THE WARNING LOOKS, in seconds.
--
-- 16b warns a non-tank at 70% of the pull threshold and 16c calls that "before
-- the flip". It is not, quite: a cast already in the air lands after the
-- warning does, so at 70% and climbing you are told about a thing that is
-- already decided. Two and a half seconds is about a cast, which is the unit of
-- decision - it turns "you are at seventy" into "the next one takes it".
local LOOKAHEAD = 3

-- How much of the old rate survives a new sample. Threat arrives in lumps - a
-- crit is a step, not a slope - and an unsmoothed rate would warn on every
-- large hit and then take it back.
--
-- SMOOTHED ON THE WAY DOWN ONLY. Averaging an increase is what made the warning
-- late: at a fifth of a second a sample, keeping 60% of the old rate takes about
-- a second to catch up with a climb that has already started - so a warning
-- meant to arrive three seconds early arrived two, and against a spike it
-- arrived with the aggro. Reported from the game, in those words: "I'm getting
-- told I'm going to get aggro, as I get aggro."
--
-- So the rate ATTACKS FAST and RELEASES SLOW. A climb is believed the instant
-- it is seen, and a lull decays gently - which is the half the smoothing was
-- ever for: stopping the warning flapping off between two hits.
local TREND_KEEP = 0.6

-- THE SHORTEST STRETCH A RATE MAY BE MEASURED OVER.
--
-- At a fifth of a second a sample, four points of movement reads as twenty per
-- second - and three seconds of that is sixty points of projection out of
-- nothing. The window is not a smoothing; it is the difference between a rate
-- and a rounding error.
local TREND_WINDOW = 0.75

-- AND HOW NEAR YOU HAVE TO BE BEFORE A PROJECTION IS ALLOWED TO SHOUT.
--
-- Reported from the game twice. First as high-threat warnings at eight per
-- cent: early in a fight the holder's threat is small, so everybody's share of
-- it moves fast and a projection on its own always fires at the pull -
-- correctly, and uselessly, because there is nothing to do about a number that
-- far out. Then at forty-five, which is the same complaint with a smaller
-- number: "it should be over 50% AND RISING."
--
-- Both halves of that are conditions. Over half way is this one; rising is
-- TREND_RISING below, and it is the half that was missing - the rate attacks
-- fast and releases slow, so a share that has stopped climbing still carries a
-- decaying rate for a second or two, and a projection off that reads as a
-- warning about something already over.
local WARN_NEAR = 50

-- HOW LONG SOMEBODY HAS TO HOLD A FIGHT BEFORE IT IS THEIRS.
--
-- Long enough that a steal is not a promotion, short enough that the answer is
-- there before the pull is over. Three seconds is about a taunt cooldown.
local TANK_SETTLE = 3

-- And how far ahead of the next-longest holder. Without a margin the title
-- changes hands on every trade, which is the opposite of what it is for.
local TANK_MARGIN = 1.5

-- A HOLDER'S RING IS THE HEADROOM LEFT, AND IT IS THE EXACT COMPLEMENT OF THE
-- CLOSEST CHALLENGER'S.
--
-- The holder used to sit at a flat full, because the server reports whoever is
-- holding at a scaled 100 by definition - so as somebody climbed toward them,
-- nothing on their capsule moved at all. Reported from the game: "when I'm
-- gaining 40% aggro on my gauge, they should be missing 40% on theirs."
--
-- The first attempt at that mapped their LEAD onto the ring - half again the
-- runner-up's threat being full - and it was far too generous: a warlock at 52%
-- of the pull threshold already holds two thirds of the pet's threat, and the
-- pet still read 96%. Reported again, with the picture: "I have 60% threat but
-- the pet shows 100% still."
--
-- So it is the complement, and it means something exact. A challenger's ring is
-- their share of the PULL THRESHOLD - at 1 they take it - so what is left of
-- the holder's is precisely how much headroom there is before somebody does.
-- The two sum to one, they move against each other, and the moment of a steal
-- is one ring closing as the other opens.
--
-- 16b says the holder shows a full ring. They do, when there is nobody else on
-- the table; below that this is the more useful reading and it is what was
-- asked for twice.

-- Never quite nothing, though. A ring that vanishes at the moment it matters
-- most reads as the module having given up rather than as a lead having gone.
local LEAD_FLOOR = 0.03

-- 16c: the screen flash and the ping fire at most once every six seconds. Not
-- a throttle for the sake of it - a chaotic pull flips this state repeatedly,
-- and an alarm that can strobe is an alarm people switch off.
local ALARM_GAP = 6

-- Every unit whose threat is ever drawn. Party pets are not in it: the handoff
-- gives a ring to the player frame, the party capsules and YOUR pet frame, and
-- nothing draws somebody else's pet.
local UNITS = { "player", "pet", "party1", "party2", "party3", "party4" }

-- ---------------------------------------------------------------------------
-- role
-- ---------------------------------------------------------------------------

-- WHAT MAKES SOMEBODY A TANK ON THIS CLIENT. 16b says the role comes from the
-- assigned role glyph, and on Classic Era a role is opt-in - answered to a role
-- poll or set in the group finder - so UnitGroupRolesAssigned says NONE for
-- almost everybody. Confirmed by probe on this client: NONE.
--
-- Taken literally that is not a small mismatch. Every rule here inverts on
-- role, so a warrior tanking correctly would get the DPS treatment: red border,
-- red wash, a screen vignette and an audio ping, every pull, for doing their
-- job. The one state the design most wants silent becomes the loudest thing on
-- the screen.
--
-- So the role is inferred where the client will not say, from the stance or
-- form or aura the player chose deliberately and can change at any moment.
-- NKThreat reaches the same conclusion from the other end: its capability flag
-- is `hasRoleAPI = FLAVOR == "MISTS"`.
local TANK_SPELLS = {
	71,     -- Defensive Stance (warrior)
	5487,   -- Bear Form (druid)
	9634,   -- Dire Bear Form
	25780,  -- Righteous Fury (paladin)
}

--- A spell's name, under whichever API this client has.
local function SpellName(id)
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, id)
		return ok and info and info.name or nil
	end
	if GetSpellInfo then
		local ok, name = pcall(GetSpellInfo, id)
		return ok and name or nil
	end
	return nil
end

--- Is this unit wearing one of them?
--
--  BY NAME, resolved from the spell id at enable, because the aura APIs answer
--  with a localised name and a table of English strings would make this work in
--  one locale. Read through the auras module's own reader rather than a second
--  copy of the two-API fallback.
function TH:WearsTankAura(unit)
	local names = self.__tankAuras
	if not names or not next(names) then return false end

	local aur = A:GetModule("auras")
	local get = aur and aur.GetAura
	if not get then return false end

	for i = 1, 40 do
		local name = get(unit, i, "HELPFUL")
		if not name then break end
		if names[name] then return true end
	end
	return false
end

--- Who has actually been holding this fight.
--
--  THE THIRD SOURCE, AND ON THIS CLIENT THE BEST ONE. 16b takes the role from
--  the assigned role glyph; Classic Era's roles are opt-in and almost nobody
--  sets them, so in a real group nothing on screen says who is tanking - which
--  Put plainly from the game: "it's not really clear who is tanking or has
--  aggro."
--
--  A stance or a form answers it for three classes. This answers it for all of
--  them, and answers it from the thing that actually matters: the tank is
--  whoever the mob has been attacking. Held time on the current fight, with a
--  settle and a margin so that a DPS who steals it for two seconds is not
--  promoted - because if they were, the theft would come up in the calm accent
--  and the whole feature would invert at the moment it is needed.
--
--  BEFORE ANYBODY IS ESTABLISHED, THE HOLDER IS PRESUMED TO BE DOING THEIR JOB.
--  At the pull nothing has flipped yet, so the alternative is a red alarm on
--  the tank for the first three seconds of every fight.
function TH:NoteHolder(key, holder, at)
	local h = self.__held
	if not h or h.key ~= key then
		h = { key = key, time = {}, at = at }
		self.__held = h
	end

	local dt = math.max(0, math.min(at - (h.at or at), 1))
	h.at = at
	if holder then h.time[holder] = (h.time[holder] or 0) + dt end

	local best, bestT, nextT = nil, 0, 0
	for unit, t in pairs(h.time) do
		if t > bestT then best, nextT, bestT = unit, bestT, t
		elseif t > nextT then nextT = t end
	end

	if best and bestT >= TANK_SETTLE and (bestT - nextT) >= TANK_MARGIN then
		self.__tank = best
	elseif not self.__tank then
		self.__tank = holder
	end
	return self.__tank
end

--- What this unit counts as: "tank" or "damage".
--
--  A HEALER IS "damage" HERE, and that is not a slight: every threat rule in
--  the handoff splits tank from not-tank, and healer and DPS are treated
--  identically throughout it. Two names for one set of rules would be two
--  things to keep in step for no gain.
function TH:RoleOf(unit)
	-- A PET IS ALWAYS THE TANK. 16c: "the pet counts as your tank" - a
	-- voidwalker holding a boar is the good state, and asking the assigned-role
	-- API about a pet answers nothing anyway.
	if unit == "pet" then return "tank" end

	-- The override, and it is the player's own. Inference is a heuristic; the
	-- player knows.
	if unit == "player" then
		local want = cfg().role
		if want == "tank" or want == "damage" then return want end
	end

	-- ONLY AN EXPLICIT TANK SHORT-CIRCUITS. DAMAGER must fall through to the
	-- inference below, and that is not a nicety - it is the difference between
	-- this working and not.
	--
	-- The two live readings disagree and both are right. The threat probe,
	-- solo: `assigned role: NONE`. An earlier screenshot, in a party where
	-- nobody had answered a poll: every capsule wearing the DPS arrow. So a
	-- player alone reads NONE and a party member reads DAMAGER, and DAMAGER is
	-- what almost every real tank in a real group answers. Take it at face
	-- value and a warrior in Defensive Stance gets the DPS treatment - red, a
	-- screen flash and a ping, every pull, for doing their job - which is the
	-- exact failure this whole section exists to prevent, arriving through the
	-- one branch that looked like it was being careful.
	local assigned = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
	if assigned == "TANK" then return "tank" end

	-- INFERRED FOR ANYONE, not only for the player. The plan restricted this to
	-- the player on the assumption that another unit's stance was not readable;
	-- it is - a party member's Defensive Stance is a buff like any other - and
	-- the restriction was protecting nothing. It makes the party capsules right
	-- as well as your own, which is the whole of the change.
	if self:WearsTankAura(unit) then return "tank" end

	-- AND FINALLY, WHOEVER HAS BEEN HOLDING IT. See NoteHolder: on a client
	-- where nobody sets a role and only three classes wear a readable stance,
	-- this is the only thing that answers "who is tanking" for a paladin, a
	-- shaman tanking a five-man, or anybody at all in a pick-up group.
	if self.__tank == unit then return "tank" end
	return "damage"
end

-- ---------------------------------------------------------------------------
-- reading the table
-- ---------------------------------------------------------------------------

--- Something we could have threat on.
local function Hostile(unit)
	if not unit or not UnitExists(unit) then return false end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return false end
	return UnitCanAttack("player", unit) and true or false
end

--- Is this unit on that mob's table at all?
local function Reads(unit, mob)
	if not (unit and mob) or type(UnitDetailedThreatSituation) ~= "function" then
		return false
	end
	local ok, _, _, scaled = pcall(UnitDetailedThreatSituation, unit, mob)
	return (ok and scaled ~= nil) and true or false
end

--- One unit against one mob, or nothing.
--
--  NOTHING, not zeroes. See the header: the call is declared MayReturnNothing
--  and the case it returns nothing for is the ordinary one.
local function Read(unit, mob)
	if not (unit and mob) or type(UnitDetailedThreatSituation) ~= "function" then
		return nil
	end
	local ok, tanking, status, scaled, raw, threat =
		pcall(UnitDetailedThreatSituation, unit, mob)
	if not ok or scaled == nil then return nil end
	return (tanking and true or false), status, scaled, raw, threat
end

--- The aggro modifier the server used, from two numbers we already have.
--
--  Only meaningful for a unit that is NOT holding: for the holder, raw means
--  something else and does not need to mean anything to us, because a holder is
--  a full ring by definition.
--
--  Bounded, because a ratio of two rounded percentages near zero is noise. 1.1
--  and 1.3 are the only two values the server uses.
local function AggroMod(tanking, raw, scaled)
	if tanking or not raw or not scaled or scaled <= 0 then return nil end
	local mod = raw / scaled
	if mod < 1.05 or mod > 1.4 then return nil end
	return mod
end

--- How fast this unit's share is climbing, in percent of the threshold per
--- second, and where it will be LOOKAHEAD from now.
--
--  Kept per unit and reset when the mob changes: a rate carried across targets
--  is a rate measured against a different denominator.
function TH:Trend(unit, key, scaled, at)
	self.__trend = self.__trend or {}
	local was = self.__trend[unit]

	--- Where this rate says you will be. ONLY WHILE IT IS ACTUALLY CLIMBING:
	--  the rate attacks fast and releases slow, so a share that has stopped
	--  moving carries a decaying rate for a second or two afterwards - and a
	--  projection off that is a warning about something that is already over.
	--  At or under the threshold and falling is not high threat.
	local function ahead(rate, rising)
		if not rising then return scaled end
		return scaled + math.max(0, rate) * LOOKAHEAD
	end

	-- A new mob is a new denominator, so nothing carries across.
	if not was or was.key ~= key then
		self.__trend[unit] = { key = key, scaled = scaled, at = at, rate = 0 }
		return 0, scaled
	end

	-- NOT LONG ENOUGH TO MEASURE ANYTHING. Keep the rate we had rather than
	-- recomputing it out of a fifth of a second of noise; the sample we are
	-- holding stays put, so the next window is measured from where this one
	-- started.
	local dt = at - was.at
	if dt < TREND_WINDOW then
		return was.rate or 0, ahead(was.rate or 0, was.rising)
	end

	local raw = (scaled - was.scaled) / dt
	local eased = (was.rate or 0) * TREND_KEEP + raw * (1 - TREND_KEEP)
	local rate = math.max(raw, eased)

	-- MEASURED, NOT SMOOTHED. Whether it is climbing is a fact about the last
	-- window; the smoothing exists to steady the SIZE of the climb, and letting
	-- it decide the direction as well is what let a falling share go on warning.
	local rising = raw > 0

	self.__trend[unit] = { key = key, scaled = scaled, at = at, rate = rate,
		rising = rising }
	return rate, ahead(rate, rising)
end

--- The fight everyone is measured against, where there is one.
--
--  ONE TABLE, OR THE GAUGES DISAGREE. This used to resolve a mob per unit -
--  the player from `target`, the pet from `pettarget`, each member from their
--  own - and that is two different threat tables the moment you are not
--  targeting what your pet is fighting. Reported from the game: a "losing
--  aggro" warning on the pet with no reading at all on the player, and then the
--  player pulling it off him with the pet's gauge still full. Two correct
--  answers to two different questions, which is the one thing a set of gauges
--  must never be.
--
--  A UNIT TOKEN, NOT A GUID. The generated documentation names this argument
--  `mobGUID` and then types it UnitToken, which is a trap worth falling into
--  once. So the set of mobs we can reach is the set we hold a token for.
local function FocusMob()
	-- What you are looking at wins: it is the one choice the player made.
	if Hostile("target") then return "target" end
	-- 16c's "targeting a mob attacking someone else", and NKThreat resolves the
	-- same question the same way.
	if Hostile("targettarget") then return "targettarget" end
	-- Then whatever the people beside you are actually fighting. Your pet
	-- first, because a pet class spends most of a fight with the pet on the mob
	-- and nothing selected at all.
	if Hostile("pettarget") then return "pettarget" end
	for i = 1, 4 do
		local own = "party" .. i .. "target"
		if Hostile(own) then return own end
	end
	return nil
end

--- The mob a given unit's threat is measured against.
--
--  The focus first, so everyone on that table is reading the same numbers.
--  A unit that is not on it falls back to what IT is fighting, which is decision
--  7.4 and is what keeps a member off on their own from reading as idle.
local function MobFor(unit, focus)
	if focus and Reads(unit, focus) then return focus end
	if unit == "player" then return nil end
	local own = unit .. "target"
	return Hostile(own) and own or nil
end

--- How far ahead of the runner-up a holder is, as a percentage.
local function Lead(unit, mob)
	if type(UnitThreatPercentageOfLead) ~= "function" then return nil end
	local ok, pct = pcall(UnitThreatPercentageOfLead, unit, mob)
	if not ok then return nil end
	return pct
end

-- ---------------------------------------------------------------------------
-- the judgement
-- ---------------------------------------------------------------------------

--- Which tier this record is, and why.
--
--  THE ONLY PLACE THAT DECIDES. `crowd` is how many of the units we can see are
--  on this mob's table, which is what answers the design's quietest rule.
local function Judge(unit, r, crowd)
	-- NOBODY TO LOSE IT TO. 16c: solo, with no pet, a mob attacking you is the
	-- normal state of the world and nothing is shown at all. The threat UI
	-- exists only when there is somebody to lose aggro TO, and the only honest
	-- test we have for that is how many entries we can see on the table.
	if (crowd or 1) < 2 then return TIER.NONE end

	local role = TH:RoleOf(unit)

	if role == "tank" then
		if not r.tanking then
			-- A PET NEVER ESCALATES. When a mob comes off your voidwalker the
			-- design puts the alarm on YOUR frame - 16c - and the pet losing it
			-- is the same event seen from the other side. Two alarms for one
			-- thing is one alarm too many.
			if unit == "pet" then return TIER.NONE end
			return TIER.FAIL, "lost"
		end
		local lead = r.lead
		if lead and lead < GRIP_LEAD then return TIER.WARN, "losing" end
		-- GOOD NEWS NEVER ESCALATES. A tank holding securely stays here for as
		-- long as the fight lasts.
		return TIER.RING, "holding"
	end

	if r.tanking then return TIER.FAIL, "aggro" end

	-- WHERE IT IS GOING, not only where it is. See LOOKAHEAD: warning at 70%
	-- and climbing tells you about a cast that has already left, and there is
	-- nothing to do with that but read it.
	--
	-- BUT ONLY ONCE YOU ARE NEAR IT. See WARN_NEAR: a projection on its own
	-- fires at the pull, when the holder's threat is small and everybody's
	-- share of it is moving fast. That is arithmetically true and no use at
	-- all - it warned at eight per cent.
	if r.scaled >= RING_FLOOR
		or (r.scaled > WARN_NEAR and (r.ahead or 0) >= RING_FLOOR)
	then
		return TIER.WARN, "high"
	end

	-- AND BELOW THAT, ON YOUR OWN FRAME, THE RING IS STILL THERE.
	--
	-- 16b says a DPS below the floor shows nothing at all, and for everybody
	-- else that is right: four rings climbing across a party is a wall of
	-- arithmetic and none of it is yours to act on. Your own is different.
	-- A gauge that appears when you are already in trouble is a report; you
	-- cannot pace something you cannot see, and pacing it is the whole job.
	--
	-- In the calm accent, because a DPS under the floor IS their role doing its
	-- job - which is exactly what 16b reserves that colour for.
	if unit == "player" then return TIER.RING, "building" end
	return TIER.NONE
end

-- ---------------------------------------------------------------------------
-- the pass
-- ---------------------------------------------------------------------------

TH.state = {}          -- unit -> record, for whatever is drawing
TH.plates = {}         -- nameplate token -> disposition, for 16d
TH.watchers = {}       -- fn -> true

--- Tell me when a unit's threat state changes.
--
--  `fn(unit, record)` - and the record is nil when there is nothing to draw,
--  which is a state worth hearing about rather than an absence.
function TH:Subscribe(fn)
	if type(fn) == "function" then self.watchers[fn] = true end
	return fn
end

function TH:Unsubscribe(fn) self.watchers[fn] = nil end

local function Announce(unit, r)
	for fn in pairs(TH.watchers) do
		local ok, err = pcall(fn, unit, r)
		if not ok then A:Debug("threat watcher:", err) end
	end
end

--- Has anything a drawing needs actually moved?
--
--  The fill is a float that trembles every tick; announcing that is announcing
--  every tick. A hundredth of the ring is under a pixel at either size the
--  design draws it at.
local function Same(a, b)
	if a == nil or b == nil then return a == b end

	-- ON THE FILL, NOT ON THE SHARE. A holder's scaled percentage is 100 by
	-- definition and never moves, while their ring drains as the runner-up
	-- closes on them - so comparing shares said "nothing has changed" for the
	-- whole of a tank losing their lead, and the one gauge that had something
	-- to say was the one that never redrew.
	return a.tier == b.tier and a.reason == b.reason and a.mob == b.mob
		and math.abs((a.fill or 0) - (b.fill or 0)) < 0.01
end

function TH:Poll()
	local was, now = self.state, {}

	-- IN COMBAT ONLY. 16b, and it is the cheapest gate there is: out of combat
	-- the call returns nothing for everyone anyway, so this saves the asking.
	if UnitAffectingCombat("player") then
		local crowd = {}
		local pending = {}

		local focus = FocusMob()
		for _, unit in ipairs(UNITS) do
			if UnitExists(unit) then
				local mob = MobFor(unit, focus)
				-- AND ONLY AGAINST ENGAGED ENEMIES. A mob standing there not
				-- fighting anybody has a threat table of nothing much, and a
				-- ring against it would be a ring for walking past.
				if mob and UnitAffectingCombat(mob) then
					local tanking, status, scaled, raw, threat = Read(unit, mob)
					if scaled ~= nil then
						local key = UnitGUID(mob) or mob
						crowd[key] = (crowd[key] or 0) + 1
						pending[#pending + 1] = {
							unit = unit, mob = mob, key = key,
							tanking = tanking, status = status,
							scaled = scaled, raw = raw, threat = threat,
							mod = AggroMod(tanking, raw, scaled),
						}
					end
				end
			end
		end

		-- SECOND PASS, because the quietest rule in the handoff needs the whole
		-- table before it can answer: whether there is anybody to lose aggro to
		-- is not a property of any one unit.
		local at = (GetTime and GetTime()) or 0

		-- WHO IS HOLDING THE FOCUS, before anything is judged: every rule below
		-- inverts on role and the role now depends on this.
		local key, holder = nil, nil
		for _, r in ipairs(pending) do
			if focus and r.mob == focus then
				key = r.key
				if r.tanking then holder = r.unit end
			end
		end
		if key then self:NoteHolder(key, holder, at) end

		for _, r in ipairs(pending) do
			r.rate, r.ahead = self:Trend(r.unit, r.key, r.scaled or 0, at)
			if r.tanking then r.lead = Lead(r.unit, r.mob) end
			r.tier, r.reason = Judge(r.unit, r, crowd[r.key])

			r.fill = math.min(1, (r.scaled or 0) / 100)
			if r.tier ~= TIER.NONE then now[r.unit] = r end
		end

		-- AND THE HOLDER'S RING IS WHAT IS LEFT OF IT. A second pass, because
		-- the answer is a fact about the whole table rather than about any one
		-- unit: the closest challenger's share is what the holder has left to
		-- give away.
		--
		-- FROM THE RECORDS WHERE WE HAVE THEM, from the lead where we do not -
		-- somebody outside the group can be on the table and we cannot see
		-- them, but the server's own lead figure counts them. 100/lead is the
		-- runner-up's share of the holder's threat, which is the same reading
		-- one step earlier.
		for _, r in ipairs(pending) do
			if r.tanking then
				local top = 0
				for _, o in ipairs(pending) do
					if o.key == r.key and o.unit ~= r.unit then
						top = math.max(top, math.min(1, (o.scaled or 0) / 100))
					end
				end
				if top <= 0 and r.lead and r.lead > 0 then
					top = math.min(1, 100 / r.lead)
				end
				r.fill = math.max(LEAD_FLOOR, 1 - top)
			end
		end
	end

	-- ON THE WAY IN, not while it is true. The flash is an event - "this just
	-- happened" - and firing it from the drawing would repeat it every pass for
	-- as long as the mob stayed on you. Read here because this is the only
	-- place that knows both the old state and the new one.
	local before, after = was.player, now.player
	if after and after.tier == TIER.FAIL
		and (not before or before.tier ~= TIER.FAIL) then
		self:Alarm()
	end

	for unit, r in pairs(now) do
		if not Same(r, was[unit]) then Announce(unit, r) end
	end
	for unit in pairs(was) do
		if not now[unit] then Announce(unit, nil) end
	end
	if not next(now) then
		self.__trend, self.__held, self.__tank = nil, nil, nil
	end
	self.state = now
	self:ScanPlates()
end

--- What this unit's threat is right now, or nil for nothing to draw.
function TH:For(unit) return self.state[unit] end

-- ---------------------------------------------------------------------------
-- the ring
--
-- Tier 1, and the only part of the design that is drawn here: the engine above
-- decides, this hangs one arc on the disc each unit already has. The chips, the
-- washes and the screen alarm are phases 3 and 4 and will read the same state.
-- ---------------------------------------------------------------------------

--- What colour a tier means, which is 16b's rule and is role-aware by having
--- been decided already: the tier IS the role reading.
--
--  Resolved per call rather than cached, so a skin change reaches it - accent
--  and semantic gold both move between skins, and red is invariant.
local function TierColour(tier)
	local c = A.Palette.c
	if tier == TIER.RING then return c.accent end
	if tier == TIER.WARN then return c.semanticGold end
	if tier == TIER.FAIL then return c.danger end
	return nil
end

-- WHAT THE CHIP SAYS, which is 16c's copy and is final design intent - the
-- wording is the whole of the warning and paraphrasing it would be inventing a
-- second one. An em dash in AGGRO - ON YOU, spelled as its bytes because this
-- file is read by people in editors that are not all the same.
local EM_DASH = "\226\128\148"
local CHIP = {
	tank   = { [TIER.WARN] = "LOSING AGGRO", [TIER.FAIL] = "LOST AGGRO" },
	damage = { [TIER.WARN] = "HIGH THREAT",
		[TIER.FAIL] = "AGGRO " .. EM_DASH .. " ON YOU" },
}

--- The chip's words for this unit, with the live figure where 16c asks for it.
--
--  ON YOUR OWN FRAME ONLY. The design puts the percentage on the player's chip
--  and not on anybody else's, and it is right: your own number is something you
--  can act on, and four of them across a party is a row of arithmetic nobody
--  reads in the second they have.
local function ChipText(unit, r, role)
	local say = (CHIP[role] or CHIP.damage)[r.tier]
	if not say then return nil end
	if unit == "player" and r.tier == TIER.WARN and role ~= "tank" then
		return say .. " " .. EM_DASH .. " " ..
			string.format("%d%%", math.floor((r.scaled or 0) + 0.5))
	end
	return say
end

--- How deep to take a colour before white type will sit on it.
--
--  16c gives the failure chip a deeper red than its border - #d9584a against
--  #f08a7a - so the white on it reads. We keep ONE red token (see the plan's
--  colour decision) and deepen it here rather than adding a ninth red to a
--  palette that has eight.
local function Deepen(c, t)
	return { c[1] * (1 - t), c[2] * (1 - t), c[3] * (1 - t), c[4] or 1 }
end

--- The alarm's whole appearance for a tier, or nil for the tiers that have none.
local function AlarmSpec(unit, r, role)
	if r.tier ~= TIER.WARN and r.tier ~= TIER.FAIL then return nil end

	local c = A.Palette.c
	local colour = TierColour(r.tier)
	local warn = (r.tier == TIER.WARN)

	-- CHIPS COME OFF ON "RINGS ONLY" AND THE BORDER STAYS. That is what the
	-- setting says: quieter, and it still tells you the number at a glance.
	local label = (cfg().display ~= "rings") and ChipText(unit, r, role) or nil

	return {
		colour  = colour,
		period  = warn and A.Widgets.PULSE_WARN or A.Widgets.PULSE_FAIL,
		label   = label,
		-- Gold takes dark ink; red is deepened so white will sit on it.
		chipBg  = warn and colour or Deepen(colour, 0.35),
		chipInk = warn and (c.btnFillText or c.bg or c.text) or { 1, 1, 1, 1 },
	}
end

--- The disc this unit's ring goes round.
--
--  ASKED OF THE FRAMES RATHER THAN DUPLICATED. The party capsule carries a
--  level pip and the player and pet frames carry an orb; both are the disc the
--  design means by "the class pip", both are already the thing everybody
--  watches, and both modules keep a frames list keyed by unit. Reaching for
--  them here keeps ONE ring implementation with one subscriber, rather than a
--  copy of it in each module that would drift the first time a threshold moved.
local function DiscFor(unit)
	for _, mod in ipairs({ A:GetModule("unitframes"), A:GetModule("partyframes") }) do
		for _, f in ipairs((mod and mod.frames) or {}) do
			if f.unit == unit and f:IsShown() then
				local disc = f.orb or f.pip
				if disc then return f, disc end
			end
		end
	end
	return nil
end

--- Put this unit's state on its frame, or take it off.
function TH:Draw(unit, r)
	local host, disc = DiscFor(unit)
	if not host then return end

	local ring = A.Widgets.ThreatRing(host, disc)
	if not ring then return end
	-- The disc is resized by its own module on a config change, and a ring left
	-- at the size it was born at ends up inside or outside the rim.
	A.Widgets.SizeThreatRing(ring, disc:GetWidth())

	-- THE SIDE AWAY FROM THE DISC, so the chip never crosses the thing the ring
	-- is drawn on. The player frame can be mirrored; the disc's own position
	-- inside the capsule is the only honest way to ask which side that is.
	local alarm = A.Widgets.ThreatAlarm(host, {
		side = (disc:GetCenter() or 0) > (host:GetCenter() or 0)
			and "LEFT" or "RIGHT",
		-- The line beside the name - "Undead Warlock", "Demon - Lv 8", "Mage".
		-- It is the least load-bearing text on the capsule: it does not change
		-- during a fight and it is not what you are looking at when a mob is
		-- coming for you. Nothing is hidden - the chip lies over it.
		--
		-- BOTH NAMES FOR IT. The unit frames call it `sub` and the party
		-- capsules call it `class`, and asking only for `sub` fell through to
		-- the readout - which on a party capsule is out past the bars, so the
		-- chip anchored to it hung off the end of the frame entirely.
		over = host.sub or host.class or host.hpText,
	})

	-- ONE MOMENT, ONE STORY - FOR THE GAUGE, and only the gauge.
	--
	-- The alarm holds itself up for a few seconds after the state resolves so
	-- that it can be read; the ring did not, so the capsule ended up saying two
	-- things about two different moments - a chip reading AGGRO - ON YOU beside
	-- a gauge already back down to two pips. Reported from the game as jerky
	-- and inconsistent, and it was.
	-- THE ALARM DECIDES FIRST, because whether the gauge is held depends on
	-- whether the message is - and `pending` is set BY this call. Asking before
	-- it always read nil on the pass that mattered, so the ring cleared on the
	-- one frame the hold existed to cover and the fix looked like it did
	-- nothing.
	--
	-- OFF THE LIVE STATE. Fed its own held record back, the alarm re-raises
	-- itself every pass, cancels the wait it is serving and stays up for ever.
	local spec = r and AlarmSpec(unit, r, self:RoleOf(unit)) or nil
	if spec then alarm.record = r end
	A.Widgets.SetThreatAlarm(alarm, spec)

	-- ONE MOMENT, ONE STORY - FOR THE GAUGE, and only the gauge.
	--
	-- The alarm holds itself up for a few seconds after the state resolves so
	-- that it can be read; the ring did not, so the capsule ended up saying two
	-- things about two different moments: a chip reading AGGRO - ON YOU beside
	-- a gauge already back down to two pips. Reported from the game as jerky
	-- and inconsistent, and it was.
	local shown = (alarm.pending and alarm.record) or r

	if not shown or cfg().display == "off" then
		A.Widgets.SetThreatRing(ring, nil, nil, false)
		return
	end

	-- THE HOLDER SHOWS A FULL RING, which 16b says explicitly - and there is
	-- nothing here doing it, deliberately. The server reports the holder at a
	-- scaled 100, so the clamp in the pass has already closed the ring. A
	-- `tanking and 1` guard beside it looked like it was enforcing the rule and
	-- was in fact unreachable: removing it changed no check, which is how it
	-- was found.
	--
	-- The steady soft glow belongs to one state and one only: a role doing its
	-- job. See 16a - it is the single thing on this ring that never animates
	-- and never means "act now".
	A.Widgets.SetThreatRing(ring, shown.fill, TierColour(shown.tier),
		shown.tier == TIER.RING and shown.reason == "holding")

	-- AND THE SHIELD ON WHOEVER IS ACTUALLY HOLDING IT.
	A.Widgets.SetThreatHolder(ring, shown.tanking, TierColour(shown.tier))
end

-- ---------------------------------------------------------------------------
-- nameplate disposition
--
-- 16d, and it is a DIFFERENT QUESTION from everything above. The unit frames
-- answer "what is my number"; in a multi-mob pull the plates answer "which of
-- these is about to come at me". Border and glow only - no rings, no chips, no
-- size change, and never the screen flash: a plate that could fire that would
-- fire it once per mob in a pack.
--
-- Role-aware like the frames, and by the same rule: red means "this mob is
-- where it should not be" for YOUR role.
-- ---------------------------------------------------------------------------

-- How much of the emphasis a plate carrying a disposition keeps whatever the
-- deck is doing with it. The deck dims everything that is not your target to
-- .62 and lifts the rim only on the one you are looking at; 16d wants EVERY
-- engaged plate to carry its colour, targeted or not, so this is the floor the
-- deck may raise but not go under.
local PLATE_FLOOR = 0.55

--- What this hostile plate should be wearing, or nil for the client's own.
--
--  Returns colour, and whether it pulses. Read off the same call everything
--  else here uses: the plate token IS a unit token, so a mob with a plate is a
--  mob we can ask about.
function TH:PlateFor(unit)
	if not unit or cfg().display == "off" then return nil end

	-- THE TWO COMBAT GATES ARE FOR THE ASKING, NOT FOR THE ANSWER. Out of
	-- combat, and against a mob that is not fighting anybody, the call returns
	-- nothing anyway and the nil below would do the job - so removing these
	-- fails no check. They stay because this runs per plate, and a pack of ten
	-- is ten API calls a pass to be told what we already knew.
	if not UnitAffectingCombat("player") then return nil end
	if not (UnitExists(unit) and UnitAffectingCombat(unit)) then return nil end

	local tanking, _, scaled = Read("player", unit)
	if scaled == nil then return nil end

	local c = A.Palette.c
	if self:RoleOf("player") == "tank" then
		-- COMING AT THE WRONG PERSON means anyone who is not you.
		if not tanking then return c.danger, true end
		-- Or somebody else on its table is rising, which is the plate to act on.
		local lead = Lead("player", unit)
		if lead and lead < GRIP_LEAD then return c.semanticGold, false end
		return nil
	end

	-- On its proper target: quiet. On YOU: the triage list.
	if tanking then return c.danger, true end
	if scaled >= RING_FLOOR then return c.semanticGold, false end
	return nil
end

--- Every plate's disposition, refreshed with the rest of the pass.
--
--  A TABLE READ BY THE PLATE, not a call made from it. The deck repaints on its
--  own animation frame and a threat query per plate per frame is the API called
--  as often as anything in this addon - NKThreat caches the same lookups on a
--  half-second window for exactly this reason. A colour is not a position; a
--  fifth of a second late is invisible.
function TH:ScanPlates()
	local seen = {}
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, base in ipairs(C_NamePlate.GetNamePlates()) do
			local token = base.unitToken
			if token then
				local colour, pulse = self:PlateFor(token)
				if colour then seen[token] = { colour = colour, pulse = pulse } end
			end
		end
	end
	self.plates = seen
end

--- What a plate should wear now: colour, the floor it keeps, and its pulse.
function TH:Plate(unit)
	local d = unit and self.plates and self.plates[unit]
	if not d then return nil end
	local k = 1
	if d.pulse then
		-- 16d: never faster than 1.2s, and never anything else - the plates get
		-- the warning tier's rate even for the failure colour, because a screen
		-- of plates beating at 0.8s is a strobe.
		k = 1 + 0.35 * (0.5 - 0.5 * math.cos(
			((self.__pulseAt or 0) % A.Widgets.PULSE_WARN)
			/ A.Widgets.PULSE_WARN * 2 * math.pi))
	end
	local c = d.colour
	return { math.min(1, c[1] * k), math.min(1, c[2] * k),
		math.min(1, c[3] * k), c[4] or 1 }, PLATE_FLOOR
end

--- The screen flash and the ping, which are the player's own state alone.
--
--  16c gives these to Tier 3 on YOUR frame and to nothing else: not to a party
--  member's capsule, and explicitly never to a nameplate - a plate that could
--  fire this would fire it once per mob in a pack.
--
--  A CLIENT SOUND RATHER THAN ONE OF OURS. RAID_WARNING is short, is not a
--  sound anything in the world makes, already means "look at this now" to
--  anybody who has played this game, and sits in the client's own mix and
--  volume channels for free.
function TH:Alarm()
	if not cfg().alarms or cfg().display == "off" then return end

	local now = (GetTime and GetTime()) or 0
	if self.__lastAlarm and (now - self.__lastAlarm) < ALARM_GAP then return end
	self.__lastAlarm = now

	A.Widgets.ScreenFlash(A.Palette.c.danger)
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
		pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
	end
end

--- One step of every live alarm's pulse.
--
--  ON THE SHARED TICKER at a tenth of a second, which is twelve steps across a
--  1.2s pulse - smooth enough for a brightness ramp, where the ring's 300ms
--  fade needed its own frame.
function TH:Pulse(dt)
	self.__pulseAt = (self.__pulseAt or 0) + (dt or 0)

	-- AND THE PLATES, which have no animation of their own: the deck's runs
	-- only while a plate is growing or shrinking, so a pulsing border needs
	-- somebody to ask for it. Nothing to do when no plate is carrying one.
	if next(self.plates or {}) then
		local np = A:GetModule("nameplates")
		if np and np.RepaintThreat then np:RepaintThreat(self.plates) end
	end

	for _, unit in ipairs(UNITS) do
		local host = DiscFor(unit)
		local alarm = host and host.__aetherAlarm
		if alarm then
			local held = alarm.spec
			A.Widgets.StepThreatAlarm(alarm, dt)
			-- ITS TIME SERVED. The gauge was frozen with it, so somebody has
			-- to put it back on the live number - and only this knows the
			-- moment the hold ended.
			if held and not alarm.spec then
				alarm.record = nil
				self:Draw(unit, self.state[unit])
			end
		end
	end
end

--- Every ring, from scratch. For a skin change or a frame rebuild, where the
--- state has not moved but what is drawing it has.
function TH:Redraw()
	for _, unit in ipairs(UNITS) do
		self:Draw(unit, self.state[unit])
	end
end

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

function TH:Moved() self.__dirty = true end

function TH:OnEnable()
	-- The spell names, once. They cannot be resolved before the client has its
	-- spell data, which is why this is not a file-scope table.
	self.__tankAuras = {}
	for _, id in ipairs(TANK_SPELLS) do
		local name = SpellName(id)
		if name then self.__tankAuras[name] = true end
	end

	-- UNFILTERED, deliberately. NKThreat registers UNIT_THREAT_LIST_UPDATE
	-- filtered on "target" and survives only because it also polls: on this
	-- client the event arrives naming `softenemy`, so a filter on "target"
	-- would never deliver it. Ours is a hint that something moved, and a hint
	-- that never arrives is worse than no hint at all.
	for _, event in ipairs({
		"UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
		"PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED",
		"PLAYER_REGEN_ENABLED", "UNIT_PET", "GROUP_ROSTER_UPDATE",
	}) do
		A:RegisterEvent(self, event, "Moved")
	end

	-- THE ONE SUBSCRIBER. Everything drawn is drawn from here, and it is a
	-- subscriber rather than a call at the end of Poll so that phases 3 to 5
	-- can attach beside it without the engine learning about any of them.
	self.__drawer = self.__drawer or function(unit, r) TH:Draw(unit, r) end
	self:Subscribe(self.__drawer)

	self.__accum, self.__dirty = 0, true
	A:RegisterTicker(self, function(owner, dt)
		-- The pulse runs on every tick and the poll on its own throttle: an
		-- animation that only moved when the numbers did would stutter through
		-- exactly the moment it is there to be noticed in.
		owner:Pulse(dt)
		A.Widgets.StepScreenFlash(dt)

		owner.__accum = (owner.__accum or 0) + dt
		if not owner.__dirty and owner.__accum < POLL then return end
		owner.__accum, owner.__dirty = 0, false
		owner:Poll()
	end)
end

function TH:OnDisable()
	A:UnregisterAllEvents(self)
	A:UnregisterTicker(self)
	-- The announcement is what takes the rings off: every watcher hears nil for
	-- every unit, which is the same path a fight ending goes down.
	for unit in pairs(self.state) do Announce(unit, nil) end
	self.state = {}
	-- The plates go back to the client's own colours the moment this is empty:
	-- the deck reads it every time it paints.
	self.plates = {}
	local np = A:GetModule("nameplates")
	if np and np.RepaintThreat then np:RepaintThreat(nil) end
	if self.__drawer then self:Unsubscribe(self.__drawer) end
end

--- A skin change moves the accent and the gold; a frame rebuild moves the disc.
function TH:OnSkinChanged() self:Redraw() end
