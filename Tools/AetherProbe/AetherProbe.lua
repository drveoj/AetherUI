--[[--------------------------------------------------------------------------
	AetherProbe  -  what this client actually has

	A throwaway addon for the Mists port. It answers, from inside the running
	client, the questions no amount of reading Blizzard's source can settle, and
	it writes the answers into SavedVariables because that is the only way text
	leaves this game.

	NOT PART OF AetherUI. It lives under Tools/, which both builders ignore, and
	it is copied into Interface\AddOns by hand. Nothing in AetherUI reads it and
	nothing here writes to AetherUI's database.

	WHAT IT DOES
	------------
	  * on login, records the build, the project id, and whether each name on a
	    curated list exists - frames, functions and templates that the port
	    turns on;
	  * hooks the windows whose anatomy changed and dumps the SHAPE of each one
	    the first time you open it, which is the measurement Panels.lua needs
	    and cannot be taken from the source tree;
	  * times a flight, so the taxi generator's yards-per-second can be
	    re-fitted rather than assumed;
	  * runs one deliberate experiment on combat protection.

	HOW TO USE IT
	-------------
	  1. Enable it, log in, and play normally for a bit. Open your character
	     sheet, spellbook, talents, a vendor, a trainer, the flight master.
	  2. Take a flight, any flight.
	  3. /aprobe          what has been collected so far
	     /aprobe dump X   dump a frame by name, right now
	     /aprobe reset    start again
	  4. Log out - SavedVariables is only written on logout - and read
	     WTF\Account\<ACCOUNT>\SavedVariables\AetherProbe.lua

	WHY A DUMP RATHER THAN A LIST OF ANSWERS. The four questions in the port
	analysis are the ones known to be open. The shape dumps are for the ones
	that are not known yet: a window's real child names, sizes and anchor points
	are what Panels.lua is made of, and every one of them currently comes from
	reading XML for a client nobody has run.
----------------------------------------------------------------------------]]

local ADDON = ...

-- ---------------------------------------------------------------------------
-- the record, BOUND ON ADDON_LOADED AND NOT BEFORE
--
-- This was two lines at file scope:
--
--     AetherProbeDB = AetherProbeDB or {}
--     local DB = AetherProbeDB
--
-- and it is the oldest trap in SavedVariables. The client loads an addon's Lua
-- FIRST, restores its saved table over the global SECOND, and fires
-- ADDON_LOADED THIRD. So those two lines run while the global is still nil,
-- make a fresh table, point both the global and DB at it - and are then
-- overwritten: the global becomes the restored table and DB is left holding an
-- orphan nothing will ever save.
--
-- Every write went into the orphan. It looked like it worked exactly once,
-- because on the very first run there was no saved file to restore and the
-- global stayed where we put it. From the second run on, the file was rewritten
-- byte-for-byte identical every logout and no new field ever appeared - which
-- is the worst shape a bug can take in a tool whose whole job is to come back
-- with a record.
-- ---------------------------------------------------------------------------

local DB

-- ---------------------------------------------------------------------------
-- the list of names to ask about
--
-- ONE FLAT LIST, not a per-flavour pair. The point is the difference between
-- the two clients, so every name is asked on both and the record says which
-- answered - a list that only asked Mists about Mists' names could not show
-- that Era has QuestWatchFrame where Mists has WatchFrame.
-- ---------------------------------------------------------------------------

local NAMES = {
	-- the tracker, and the whole reason step 2 existed
	"QuestWatchFrame", "WatchFrame", "WatchFrameScenarioFrame",
	"ObjectiveTrackerFrame", "WatchFrameLines",

	-- QUESTION ONE: is the vanilla-style group finder real here, or does MoP
	-- show PVEFrame and leave LFGParentFrame loaded but never used? Its .toc
	-- carries no AllowLoadGameType, so the source tree cannot say.
	"LFGParentFrame", "LFGParentFrameTab1", "PVEFrame", "LFDParentFrame",
	"RaidFinderFrame", "ScenarioFinderFrame", "LFGListFrame",

	-- QUESTION TWO: does Mists REPLACE the spellbook or extend it? Both
	-- flavours load Classic/SpellBookFrame.lua; Mists loads Mists/SpellBookFrame
	-- on top. If SpellBookTitleText is still here, the entry mostly survives.
	"SpellBookFrame", "SpellBookTitleText", "SpellBookCloseButton",
	"SpellBookFrameTabButton1", "SpellBookSpellIconsFrame",
	"SpellBookProfessionFrame", "SpellBookCoreAbilitiesFrame",

	-- the character sheet, where Cata rebuilt the stats pane
	"CharacterFrame", "CharacterNameText", "CharacterLevelText",
	"CharacterAttributesFrame", "CharacterStatsPane", "MagicResFrame",
	"PaperDollFrame", "PetPaperDollFrame", "PetNameText", "PetAttributesFrame",
	"ReputationFrame", "ReputationHeader", "TokenFrame", "SkillFrame",
	"HonorFrame", "PVPFrame",

	-- talents and glyphs, the one entry with nothing to carry over
	"PlayerTalentFrame", "PlayerTalentFrameSpentPointsText",
	"PlayerTalentFramePointsBar", "PlayerTalentFrameTalents",
	"PlayerSpecTab1", "GlyphFrame", "TalentFrame",

	-- the moved-file windows
	"MerchantFrame", "MerchantNameText", "MerchantMoneyFrame",
	"QuestFrame", "QuestFrameDetailPanel", "QuestFrameNpcNameText",
	"TradeSkillFrame", "TradeSkillListScrollFrame", "CraftFrame",
	"TaxiFrame", "TaxiMap", "TaxiRouteMap", "TaxiFrameCloseButton",
	"WorldMapFrame", "QuestMapFrame", "QuestLogFrame", "InspectFrame",
	"BankFrame", "ContainerFrame1", "RaidFrame", "ClassTrainerFrame",

	-- windows AetherUI has never heard of
	"AchievementFrame", "CollectionsJournal", "EncounterJournal",
	"GuildBankFrame", "ReforgingFrame", "ItemUpgradeFrame",
	"ArchaeologyFrame", "ChallengesFrame", "PetBattleFrame",
	"AuctionHouseFrame", "AuctionFrame", "LevelUpDisplay", "VoidStorageFrame",
	"BlackMarketFrame",

	-- the HUD, where nothing is expected to have moved
	"PlayerFrame", "TargetFrame", "TargetFrameToT", "PetFrame", "ComboFrame",
	"MainMenuBar", "MultiBarBottomLeft", "StanceBarFrame", "PetActionBarFrame",
	"OverrideActionBar", "ExtraActionBarFrame", "VehicleSeatIndicator",
	"MultiCastActionBarFrame", "PossessBarFrame", "DurabilityFrame",
	"Minimap", "MiniMapTracking", "GameTimeFrame", "MiniMapMailFrame",
	"BuffFrame", "TemporaryEnchantFrame", "ConsolidatedBuffs",

	-- MoP's class resource bars, none of which AetherUI names
	"RuneFrame", "TotemFrame", "ShardBar", "EclipseBarFrame",
	"PaladinPowerBar", "MonkHarmonyBar", "MonkStaggerBar", "PriestBar",
	"PlayerFrameAlternateManaBar",

	-- API that the port leans on
	"GetQuestLogTitle", "GetNumQuestLogEntries", "SelectQuestLogEntry",
	"GetQuestIDFromLogIndex", "UnitCastingInfo", "UnitChannelInfo",
	"UnitThreatSituation", "GetSpecialization", "GetTalentInfo",
	"GetMaxPlayerLevel", "ToggleCharacter", "ToggleSpellBook",
	"ToggleTalentFrame", "ToggleQuestLog", "ToggleWorldMap", "ToggleGuildFrame",
	"ToggleHelpFrame", "ToggleAllBags", "TaxiNodeName", "NumTaxiNodes",
	"TakeTaxiNode", "UnitAura", "C_Container", "C_QuestLog", "C_Spell",
	"C_UnitAuras", "C_NamePlate", "SetPortraitTexture", "MAX_PLAYER_LEVEL",
	"NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "WOW_PROJECT_MISTS_CLASSIC",
}

-- The windows worth measuring, and the addon each is load-on-demand from.
-- A LoD window does not exist at login, which is why this is a hook rather
-- than a scan: the shape is taken the first time you open it.
local WINDOWS = {
	"CharacterFrame", "PetPaperDollFrame", "ReputationFrame", "SkillFrame",
	"HonorFrame", "TokenFrame", "PVPFrame",
	"SpellBookFrame", "PlayerTalentFrame", "GlyphFrame", "TalentFrame",
	"MerchantFrame", "QuestFrame", "GossipFrame", "TradeFrame",
	"TradeSkillFrame", "CraftFrame", "ClassTrainerFrame",
	"TaxiFrame", "QuestLogFrame", "WorldMapFrame", "InspectFrame",
	"BankFrame", "MailFrame", "OpenMailFrame", "ItemTextFrame",
	"FriendsFrame", "RaidFrame", "LFGParentFrame", "PVEFrame",
	"AchievementFrame", "CollectionsJournal", "EncounterJournal",
	"GuildBankFrame", "ArchaeologyFrame", "AuctionHouseFrame", "AuctionFrame",
}

-- ---------------------------------------------------------------------------
-- reading a frame
-- ---------------------------------------------------------------------------

local function num(v)
	if type(v) ~= "number" then return v end
	-- Two decimals. A frame's size comes back with a long tail of float noise
	-- and none of it is a measurement.
	return math.floor(v * 100 + 0.5) / 100
end

--- Everything about one region or frame that a reskin would need to know.
local function describe(obj, depth)
	local out = {}
	local ok, kind = pcall(obj.GetObjectType, obj)
	out.kind = ok and kind or "?"

	ok = pcall(function() out.name = obj:GetName() end)
	pcall(function() out.shown = obj:IsShown() and true or false end)
	pcall(function()
		local w, h = obj:GetSize()
		out.w, out.h = num(w), num(h)
	end)

	-- ANCHORS, AND ALL OF THEM. A frame with two points is a frame that
	-- stretches, and which of its edges is pinned is exactly the thing an
	-- inset is measured against.
	pcall(function()
		-- obj.GetNumPoints, not obj:GetNumPoints - a colon is call syntax and
		-- is not an expression you can test for existence.
		local n = obj.GetNumPoints and obj:GetNumPoints() or 0
		if n > 0 then
			out.points = {}
			for i = 1, n do
				local p, rel, rp, x, y = obj:GetPoint(i)
				local relName = "?"
				if rel == nil then relName = "nil"
				elseif rel.GetName then relName = rel:GetName() or "<unnamed>" end
				out.points[i] = string.format("%s -> %s.%s  %s,%s",
					tostring(p), relName, tostring(rp), tostring(num(x)),
					tostring(num(y)))
			end
		end
	end)

	if out.kind == "FontString" then
		pcall(function() out.text = obj:GetText() end)
		pcall(function()
			local f, s = obj:GetFont()
			out.font = tostring(f) .. " " .. tostring(num(s))
		end)
	elseif out.kind == "Texture" then
		-- THE PATH COMES BACK AS A FILE ID on this client more often than not,
		-- and a number is still the answer - it is what SetTexture takes.
		pcall(function() out.texture = obj:GetTexture() end)
		pcall(function() out.atlas = obj:GetAtlas() end)
	end

	if depth > 0 then
		pcall(function()
			local regions = { obj:GetRegions() }
			if #regions > 0 then
				out.regions = {}
				for i = 1, math.min(#regions, 40) do
					out.regions[i] = describe(regions[i], depth - 1)
				end
			end
		end)
		pcall(function()
			local kids = { obj:GetChildren() }
			if #kids > 0 then
				out.children = {}
				for i = 1, math.min(#kids, 40) do
					out.children[i] = describe(kids[i], depth - 1)
				end
			end
		end)
	end

	return out
end

-- ---------------------------------------------------------------------------
-- collecting
-- ---------------------------------------------------------------------------

--- Is this addon enabled, asked in whichever way THIS client spells it.
--
--  TWO SIGNATURES, and they take their arguments in opposite orders:
--
--    GetAddOnEnableState(character, index)   the old one
--    GetAddOnEnableState(name [, character]) Mists 5.5.4, and it THROWS on the
--                                            other order rather than returning
--                                            nil
--
--  That throw took the whole login handler down on the first run and cost a
--  session's worth of collection. Try the new spelling, fall back to the old,
--  and give up quietly rather than raising - this is one field on a diagnostic,
--  and no field is worth losing the diagnostic over.
local function enableState(api, name, index)
	if not api.GetAddOnEnableState then return nil end
	local ok, v = pcall(api.GetAddOnEnableState, name)
	if ok then return v end
	ok, v = pcall(api.GetAddOnEnableState, nil, index)
	if ok then return v end
	return nil
end

local function say(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	DEFAULT_CHAT_FRAME:AddMessage("|cff9d7bffAetherProbe|r: "
		.. table.concat(parts, " "))
end

local function scanNames()
	DB.names = DB.names or {}
	for _, n in ipairs(NAMES) do
		local v = _G[n]
		if v == nil then
			-- Recorded as the string "absent" rather than left out: a missing
			-- key and a key that was never asked are the same thing in a Lua
			-- table, and only one of them is a finding.
			if DB.names[n] == nil then DB.names[n] = "absent" end
		else
			local t = type(v)
			if t == "table" and v.GetObjectType then
				local ok, kind = pcall(v.GetObjectType, v)
				t = ok and kind or "table"
			end
			DB.names[n] = t
		end
	end
end

local dumped = {}

local function dump(name, why)
	local f = _G[name]
	if not f or not f.GetObjectType then return false end
	DB.windows = DB.windows or {}
	DB.windows[name] = describe(f, 3)
	DB.windows[name].dumpedBecause = why
	dumped[name] = true
	return true
end

--- Take a window's shape the first time it is opened, and only then.
--
--  ON FIRST SHOW rather than on a timer: a window measured while hidden
--  reports the size it was built at, and several of these are laid out by
--  their own OnShow. A LoD window does not exist until something opens it
--  either, so there is nothing to hook before then.
local function watch(name)
	local f = _G[name]
	if not f or dumped[name] or not f.HookScript then return end
	if f.__aetherProbeHooked then return end
	f.__aetherProbeHooked = true
	f:HookScript("OnShow", function(self)
		if dumped[name] then return end
		-- One frame later: OnShow fires before the client's own handler has
		-- finished arranging the window, and the arrangement is the point.
		C_Timer.After(0.1, function()
			if dump(name, "first opened") then
				say("recorded the shape of " .. name)
			end
		end)
	end)
end

local function watchAll()
	for _, n in ipairs(WINDOWS) do watch(n) end
end

-- ---------------------------------------------------------------------------
-- QUESTION THREE: how fast does a taxi actually fly here
--
-- Tools/taxidata.py fits yards-per-second against measured flights, and the
-- 30.122 it holds was fitted on Era. Whether that carries to Mists is not
-- something the DB2 tables can answer - the tables give distance, and only a
-- stopwatch gives time.
--
-- FROM AND TO ARE BOTH RECORDED, and the route may be multi-hop. The generator
-- sums single legs, so a flight whose endpoints are not adjacent is still
-- useful: it checks the sum.
-- ---------------------------------------------------------------------------

local flight
local standingAt

--- Where you are, read WHILE THE MAP IS OPEN.
--
--  This used to run at PLAYER_CONTROL_LOST, which is the moment the flight
--  starts - and by then the taxi map has closed, NumTaxiNodes() answers 0 and
--  the loop finds nothing. Both recorded flights came back with "?" as their
--  origin, which makes a duration useless: without knowing the route you cannot
--  tell a slower client from a longer path.
local function noteWhereWeAre()
	for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
		if TaxiNodeGetType and TaxiNodeGetType(i) == "CURRENT" then
			standingAt = TaxiNodeName and TaxiNodeName(i)
		end
	end
end

local function flightStart()
	flight = { from = standingAt or "?", start = GetTime() }
end

local function flightEnd()
	if not flight then return end
	local secs = GetTime() - flight.start
	-- Under ten seconds is a taxi you cancelled, not a flight.
	if secs > 10 then
		DB.flights = DB.flights or {}
		DB.flights[#DB.flights + 1] = {
			from = flight.from,
			to = GetSubZoneText and GetSubZoneText() or "",
			zone = GetZoneText and GetZoneText() or "",
			seconds = num(secs),
		}
		say(string.format("flight recorded: %s -> %s, %.1fs",
			flight.from, GetSubZoneText and GetSubZoneText() or "?", secs))
	end
	flight = nil
end

-- ---------------------------------------------------------------------------
-- QUESTION FOUR: does protection still spread sideways along an anchor
--
-- The party dock's five ADDON BLOCKED errors came from a rule the client never
-- documents: a plain frame that a PROTECTED frame is anchored TO is restricted
-- with it, so moving or resizing the plain one in combat is refused. That is
-- client behaviour, not source, and Mists' secure templates are not Era's.
--
-- ENTIRELY OUR OWN FRAMES. Nothing here touches a Blizzard frame, so the
-- experiment cannot taint one - the secure frame is created here, anchored
-- here, and left alone afterwards.
-- ---------------------------------------------------------------------------

local host, guest

local function buildProtectionTest()
	if host then return end
	host = CreateFrame("Frame", "AetherProbeHost", UIParent)
	host:SetSize(50, 50)
	host:SetPoint("CENTER")
	guest = CreateFrame("Button", "AetherProbeGuest", UIParent,
		"SecureUnitButtonTemplate")
	guest:SetSize(10, 10)
	-- THE ANCHOR IS THE EXPERIMENT: guest is protected and hangs off host, so
	-- host is in a protected family without carrying a template itself.
	guest:SetPoint("TOPLEFT", host, "BOTTOMLEFT")
end

local function runProtectionTest()
	buildProtectionTest()
	local result = {}

	result.inCombat = InCombatLockdown() and true or false
	result.hostIsProtected = host:IsProtected() and true or false
	result.guestIsProtected = guest:IsProtected() and true or false

	local ok, err = pcall(host.SetHeight, host, 60)
	result.setHeightOnHost = ok and "allowed" or ("refused: " .. tostring(err))

	ok, err = pcall(host.SetPoint, host, "CENTER", UIParent, "CENTER", 1, 0)
	result.setPointOnHost = ok and "allowed" or ("refused: " .. tostring(err))

	local loose = CreateFrame("Frame", nil, UIParent)
	loose:SetPoint("CENTER")
	ok, err = pcall(loose.SetHeight, loose, 60)
	result.setHeightOnLooseFrame = ok and "allowed" or ("refused: " .. tostring(err))

	DB.protection = DB.protection or {}
	DB.protection[result.inCombat and "inCombat" or "outOfCombat"] = result
	if result.inCombat then
		say("protection test ran in combat - see AetherProbeDB.protection")
	end
end

--- Every blocked call this session, ours or anybody's.
--
--  PCALL DOES NOT SEE THESE. A blocked call is not a Lua error - the client
--  refuses it, raises ADDON_ACTION_BLOCKED and returns as though nothing
--  happened, which is why the party dock bug was five error popups and zero
--  caught exceptions. The event is the only honest instrument.
--
--  Third-party addons are recorded too. It is one line each and knowing that
--  something ELSE is blocking on this client is worth having when a report
--  arrives.
local function recordBlocked(addon, func)
	DB.blocked = DB.blocked or {}
	local key = tostring(addon) .. " :: " .. tostring(func)
	DB.blocked[key] = (DB.blocked[key] or 0) + 1
end

-- ---------------------------------------------------------------------------
-- wiring
-- ---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("TAXIMAP_OPENED")
f:RegisterEvent("PLAYER_CONTROL_LOST")
f:RegisterEvent("PLAYER_CONTROL_GAINED")
f:RegisterEvent("ADDON_ACTION_BLOCKED")
f:RegisterEvent("ADDON_ACTION_FORBIDDEN")

--- Run one phase of collection, and survive it failing.
--
--  THE WHOLE POINT OF THIS ADDON is to come back with a record from a client
--  nobody has run it on, so a single bad call must not take the rest of the
--  record with it. One did: GetAddOnEnableState threw on the first Mists login,
--  and because the handler was a straight run of statements, everything after
--  it - the name scan, the window hooks, the protection experiment - never
--  happened and the session collected nothing.
--
--  The failure is RECORDED rather than swallowed. A phase that did not run
--  leaves a note saying so, which is the difference between "this client does
--  not have it" and "we never asked".
local function phase(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		DB.errors = DB.errors or {}
		DB.errors[name] = tostring(err)
		say("|cffff6666" .. name .. " failed|r: " .. tostring(err))
	end
	return ok
end

f:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "PLAYER_LOGIN" then
	  phase("client", function()
		local build, buildNo, buildDate, iface = GetBuildInfo()
		DB.client = {
			build = build, buildNumber = buildNo, buildDate = buildDate,
			interface = iface,
			project = WOW_PROJECT_ID,
			projectIsMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC,
			projectIsEra = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC,
			locale = GetLocale(),
			maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel())
				or MAX_PLAYER_LEVEL,
			playerLevel = UnitLevel("player"),
			class = select(2, UnitClass("player")),
		}
	  end)

	  phase("addOns", function()
		-- EVERY ADDON, WITH WHY IT DID OR DID NOT LOAD.
		--
		-- The first version recorded only names beginning Blizzard_, and only
		-- whether they were loaded. That answered neither question it was
		-- written for: it found four addons on Era and seven on Mists, because
		-- what it was really recording was "which load-on-demand addons this
		-- session happened to open" - and it could say nothing at all about
		-- AetherUI, which was sitting in the folder NOT LOADING and left no
		-- trace anywhere on disk to say why.
		--
		-- GetAddOnInfo's fourth and fifth returns are the diagnostic:
		-- `loadable` and, when it is false, a `reason` - DISABLED,
		-- INTERFACE_VERSION, MISSING, DEP_DISABLED, BANNED. That is the
		-- difference between "the client refused it" and "it loaded and died",
		-- which cannot be told apart from outside the game.
		DB.addOns = {}
		DB.blizzardAddOns = {}
		local api = C_AddOns or _G
		local count = (api.GetNumAddOns and api.GetNumAddOns()) or 0
		for i = 1, count do
			local n, title, _notes, loadable, reason = api.GetAddOnInfo(i)
			if n then
				local loaded = api.IsAddOnLoaded and api.IsAddOnLoaded(i)
				DB.addOns[n] = {
					title = title,
					loaded = loaded and true or false,
					loadable = loadable and true or false,
					reason = reason,
					enabled = enableState(api, n, i),
					interface = api.GetAddOnMetadata
						and api.GetAddOnMetadata(n, "Interface") or nil,
				}
				if n:find("^Blizzard_") then
					DB.blizzardAddOns[n] = loaded and "loaded" or "on demand"
				end
			end
		end

		-- AND WHAT AetherUI ITSELF THINKS. If it is loaded, its own namespace
		-- carries the flavour it decided on and the last module that failed to
		-- enable - which is the answer to "did it load and die" in one line.
		local A = _G.AetherUI
		DB.aether = A and {
			version = A.version,
			project = A.project,
			flavourName = A.flavourName,
			isEra = A.isEra,
			isMists = A.isMists,
			lastFailure = A.lastFailure,
			moduleCount = A.moduleOrder and #A.moduleOrder or 0,
		} or "AetherUI is not loaded"
	  end)

	  phase("names", scanNames)
	  phase("windows", watchAll)
	  phase("protection", runProtectionTest)
	  say("recording. Open some windows, take a flight, then log out and read"
		  .. " SavedVariables\\AetherProbe.lua")

	elseif event == "ADDON_LOADED" and arg1 == ADDON then
		-- OURS. The saved table has been restored by now, so this is the first
		-- moment DB can be bound to something that will actually be written
		-- back out again. Nothing above may touch DB before this fires.
		AetherProbeDB = AetherProbeDB or {}
		DB = AetherProbeDB
		DB.runs = (DB.runs or 0) + 1

	elseif event == "ADDON_LOADED" then
		-- A load-on-demand addon has just brought its frames into being.
		if DB and arg1 and arg1:find("^Blizzard_") then
			DB.blizzardAddOns = DB.blizzardAddOns or {}
			DB.blizzardAddOns[arg1] = "loaded"
			scanNames()
			watchAll()
		end

	elseif event == "PLAYER_REGEN_DISABLED"
		or event == "PLAYER_REGEN_ENABLED" then
		runProtectionTest()

	elseif event == "TAXIMAP_OPENED" then
		dump("TaxiFrame", "taxi map opened")
		noteWhereWeAre()

	elseif event == "PLAYER_CONTROL_LOST" then
		flightStart()

	elseif event == "PLAYER_CONTROL_GAINED" then
		flightEnd()

	elseif event == "ADDON_ACTION_BLOCKED"
		or event == "ADDON_ACTION_FORBIDDEN" then
		recordBlocked(arg1, arg2)
	end
end)

-- ---------------------------------------------------------------------------
-- /aprobe
-- ---------------------------------------------------------------------------

SLASH_AETHERPROBE1 = "/aprobe"
SlashCmdList.AETHERPROBE = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S*)%s*(.*)$")

	if cmd == "reset" then
		AetherProbeDB = {}
		DB = AetherProbeDB
		dumped = {}
		say("cleared. /reload to start collecting again.")
		return
	end

	if cmd == "dump" and rest ~= "" then
		if dump(rest, "asked for") then
			say("recorded the shape of " .. rest)
		else
			say("no frame called " .. rest .. " here")
		end
		return
	end

	local absent, present = 0, 0
	for _, v in pairs(DB.names or {}) do
		if v == "absent" then absent = absent + 1 else present = present + 1 end
	end
	local shapes = 0
	for _ in pairs(DB.windows or {}) do shapes = shapes + 1 end

	say(("%s, interface %s, project %s"):format(
		tostring(DB.client and DB.client.build),
		tostring(DB.client and DB.client.interface),
		tostring(DB.client and DB.client.project)))
	say(("names: %d present, %d absent  ·  shapes: %d  ·  flights: %d"):format(
		present, absent, shapes, #(DB.flights or {})))

	local missing = {}
	for _, n in ipairs(WINDOWS) do
		if not dumped[n] then missing[#missing + 1] = n end
	end
	if #missing > 0 then
		say("not opened yet: " .. table.concat(missing, ", "))
	else
		say("every window on the list has been recorded.")
	end

	local blocked = 0
	for _, n in pairs(DB.blocked or {}) do blocked = blocked + n end
	if blocked > 0 then
		say(("%d blocked call(s) seen this session - see AetherProbeDB.blocked")
			:format(blocked))
	end
end
