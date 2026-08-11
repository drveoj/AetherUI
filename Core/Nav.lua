--[[--------------------------------------------------------------------------
	AetherUI :: Nav

	"Navigate with TomTom" on a quest: ask Questie where the quest wants you,
	hand the coordinates to TomTom, and own the waypoint we made.

	Neither addon is required. Nothing in here runs unless both are present, and
	every call into them is guarded, because both are somebody else's code that
	updates on its own schedule.

	Which halves of these APIs are actually promised
	------------------------------------------------
	TomTom's is public and documented: its README lists `AddWaypoint` and
	`RemoveWaypoint` under "Supported Addon API", the signature is
	`AddWaypoint(uiMapID, x, y, opts)` with x and y as 0-1 fractions, and it
	returns a uid table.

	Questie's is NOT. `Questie.API` is five things - `isReady`,
	`RegisterOnReady`, `RegisterForQuestUpdates`, an icon lookup and an enum
	table - and none of them knows a coordinate. Everything about quest
	locations lives behind `QuestieLoader:ImportModule`, and Questie's own
	Public/README says only what is on `Questie.API` should be considered
	stable. So this file uses internals, deliberately, and the whole design
	below is about that being survivable rather than pretending it is not.

	The path is the one Questie's own tracker menu takes:

	  QuestieDB.GetQuest(questID)                  -- the quest object
	  DistanceUtils.GetNearestSpawnForQuest(quest) -- spawn{x,y} 0-100, areaId, name
	  ZoneDB:GetUiMapIdByAreaId(areaId)            -- uiMapID
	  TomTom:AddWaypoint(uiMapID, x/100, y/100, ...)

	`GetNearestSpawnForQuest` already does the right thing per quest state: a
	quest that is complete returns its FINISHER, so a finished quest routes to
	the turn-in rather than back to the boars.

	Why this does not call Questie's own SetTomTomTarget
	---------------------------------------------------
	`TrackerUtils:SetTomTomTarget` does exactly this in four lines, and it is
	tempting. It also stores the waypoint handle in `Questie.db.char._tom_
	waypoint`, which Questie clears and overwrites from its map icons and its
	own tracker. Sharing that field means each addon silently deletes the
	other's waypoint, and it returns nothing, so we could not tell that it had.
	We keep our own handle.

	Four traps, all of them confirmed in their source
	-------------------------------------------------
	1. `ImportModule` NEVER fails. Given a name it does not know - a typo, or a
	   module renamed out from under us - it creates and returns an empty table,
	   and that same table is what the real module would later fill. So a wrong
	   name is not an error, it is a table whose every function is nil, failing
	   much later as "attempt to call a nil value". Every function we use is
	   therefore type-checked before it is called, once, in Ready().
	2. A uid must NOT be persisted. TomTom finds a waypoint's frames by table
	   IDENTITY but deletes its records by key, so a uid restored from saved
	   variables deletes the record while leaving the minimap pin registered
	   forever, orphaned and unreachable. Ours is a session-local upvalue, and
	   waypoints are created with `persistent = false` so TomTom does not
	   resurrect them either.
	3. AddWaypoint DEDUPLICATES on map/x/y/title and returns the existing uid
	   early - without re-pointing the crazy arrow. Clicking the same quest
	   twice would appear to do nothing. We always remove ours first.
	4. A nil uiMapID is not an error. TomTom creates the waypoint, arms the
	   arrow, and renders nothing at all, because the coordinate conversion
	   fails downstream and every drawing path returns early. It is the one
	   failure that looks like success, so the map id is checked for a number
	   before TomTom is called.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Nav = {}
A.Nav = Nav

-- Session-local, never saved. See trap 2 above. `routed` is the quest it was
-- made for, so it can be dropped when that quest goes away.
local waypoint, routed

-- ---------------------------------------------------------------------------
-- are they there?
-- ---------------------------------------------------------------------------

--- TomTom is a global from the moment its first file loads, but its methods are
--  unusable until its own ADDON_LOADED has built `profile` - AddWaypoint reads
--  `self.profile.persistence` on the way in. Questie's check is `TomTom and
--  TomTom.AddWaypoint`, which is necessary and not sufficient; this adds the
--  profile.
local function HasTomTom()
	return TomTom ~= nil
		and type(TomTom.AddWaypoint) == "function"
		and type(TomTom.RemoveWaypoint) == "function"
		and TomTom.profile ~= nil
end

--- Questie's modules, or nil.
--
--  Every function this file calls is verified here, because of trap 1: asking
--  for a module that does not exist hands back a plausible-looking empty table
--  rather than nil. `isReady` is Questie's own signal that its database has
--  finished loading; before it, QuestieDB's query function is not even assigned
--  and calling GetQuest raises.
local function Questie()
	if not QuestieLoader or type(QuestieLoader.ImportModule) ~= "function" then return nil end
	if not _G.Questie or not _G.Questie.API or not _G.Questie.API.isReady then return nil end

	local db   = QuestieLoader:ImportModule("QuestieDB")
	local dist = QuestieLoader:ImportModule("DistanceUtils")
	local zone = QuestieLoader:ImportModule("ZoneDB")

	if type(db.GetQuest) ~= "function" then return nil end
	if type(dist.GetNearestSpawnForQuest) ~= "function" then return nil end
	if type(dist.GetNearestSpawn) ~= "function" then return nil end
	if type(dist.GetNearestFinisherOrStarter) ~= "function" then return nil end
	if type(zone.GetUiMapIdByAreaId) ~= "function" then return nil end

	return db, dist, zone
end

--- Whether the feature can exist at all. The menu item is built only when this
--  is true, so a player with neither addon never sees a thing.
function Nav:Available()
	return HasTomTom() and Questie() ~= nil
end

-- ---------------------------------------------------------------------------
-- where does this quest want me?
-- ---------------------------------------------------------------------------

--- Questie's spawn tables are keyed by areaId and hold {x, y} in 0-100, with
--  {-1, -1} as the sentinel for "inside a dungeon".
--
--  DistanceUtils resolves that sentinel to the dungeon's entrance itself, so in
--  practice nothing out of range reaches here - I checked all 126,163 spawn
--  coordinates in the Classic NPC and object databases and every one is inside
--  0-100 apart from the 2,843 sentinels. This is belt and braces on somebody
--  else's data: TomTom does not range-check, it extrapolates past the edge of
--  the zone and points the arrow confidently at nowhere.
local function Fraction(spawn)
	if type(spawn) ~= "table" then return nil end
	local x, y = spawn[1], spawn[2]
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	if x < 0 or x > 100 or y < 0 or y > 100 then return nil end
	return x / 100, y / 100
end

--- The fallback, for a quest Questie has not populated objectives for.
--
--  `GetQuest` returns a quest whose `Objectives` are EMPTY. They are filled in
--  separately, from the player's quest log, which is fine for a tracked quest
--  and is exactly what `GetNearestSpawnForQuest` walks. But that population is
--  skipped when Questie's `hideUntrackedQuestsMapIcons` is on and the quest is
--  not one of Questie's tracked ones - and this addon replaces the tracker, so
--  Questie's idea of "tracked" is not ours and can legitimately be empty.
--
--  `ObjectiveData` is different: `GetQuest` fills it unconditionally from the
--  database, and it carries the ids we can look spawns up with directly. So
--  this route does not care about the quest log, the tracker, or that setting.
local function Entity(db, kind, id)
	if kind == "monster" and type(db.GetNPC) == "function" then
		local ok, npc = pcall(db.GetNPC, db, id)
		return ok and npc or nil
	elseif kind == "object" and type(db.GetObject) == "function" then
		local ok, object = pcall(db.GetObject, db, id)
		return ok and object or nil
	end
	return nil
end

local function FromDatabase(quest, db, dist)
	if type(quest.ObjectiveData) ~= "table" then return nil end

	local bestSpawn, bestZone, bestName, bestDist

	--- One candidate: rank it, keep it if it is the closest so far.
	local function Consider(entity, fallbackName)
		if not entity or type(entity.spawns) ~= "table" then return end
		local ok, spawn, zone, distance = pcall(dist.GetNearestSpawn, entity.spawns)
		-- `distance` is Questie's own ordering number - not yards, and not
		-- comparable across continents - and its "nothing found" value is
		-- 999999999 rather than nil. So it orders candidates and does nothing
		-- else. `type(distance) == "number"` rather than `distance or 0`: a nil
		-- there would make every later candidate win and quietly turn "nearest"
		-- into "last one in the table".
		if not ok or not spawn or type(distance) ~= "number" then return end
		if bestDist and distance >= bestDist then return end
		bestSpawn, bestZone, bestName, bestDist =
			spawn, zone, entity.name or fallbackName, distance
	end

	for _, objective in pairs(quest.ObjectiveData) do
		if objective.Type == "item" and type(db.GetItem) == "function" then
			-- "Collect 8 hides" is the most common quest shape in Classic and
			-- an item has no location of its own: what has a location is
			-- whatever drops it. Questie resolves that to a source list of
			-- NPCs and objects, which is what we can actually stand next to.
			local ok, item = pcall(db.GetItem, db, objective.Id)
			if ok and item and type(item.Sources) == "table" then
				for _, source in pairs(item.Sources) do
					Consider(Entity(db, source.Type, source.Id), objective.Text)
				end
			end
		else
			Consider(Entity(db, objective.Type, objective.Id), objective.Text)
		end
	end

	return bestSpawn, bestZone, bestName
end

--- Where to point for a quest, or nil with a reason.
--
--  Returns { map = uiMapID, x = 0-1, y = 0-1, name = string|nil }.
function Nav:Locate(questID)
	if not questID then return nil end

	local db, dist, zone = Questie()
	if not db then return nil end

	-- pcall around all of it: this is another addon's internals, and the one
	-- thing that must not happen is a right-click in our tracker raising an
	-- error that reads as ours.
	local ok, quest = pcall(db.GetQuest, questID)
	if not ok or type(quest) ~= "table" then return nil end

	local spawn, areaId, name
	local got, a, b, c = pcall(dist.GetNearestSpawnForQuest, quest)
	if got then spawn, areaId, name = a, b, c end

	-- Then the database, and ONLY THEN the turn-in. The order is the whole
	-- correctness of this function.
	--
	-- `GetQuest` fills `Finisher` unconditionally, for every quest it knows -
	-- so a `if not spawn and quest.Finisher` test before this point is true
	-- essentially always, and it would swallow the exact case the database
	-- fallback exists for: a quest whose objectives Questie never populated
	-- would route to the NPC you hand it IN to, across the zone from the mobs
	-- you still have to kill, with nothing on screen saying so. The turn-in is
	-- the answer when there is no other answer, not the first thing to try.
	if not spawn then
		spawn, areaId, name = FromDatabase(quest, db, dist)
	end

	if not spawn and type(quest.Finisher) == "table" then
		got, a, b, c = pcall(dist.GetNearestFinisherOrStarter, quest.Finisher)
		if got then spawn, areaId, name = a, b, c end
	end

	if not spawn or not areaId then return nil end

	local x, y = Fraction(spawn)
	if not x then return nil end

	-- Colon call: ZoneDB's is a method, where DistanceUtils' are not.
	local mapped, uiMapId = pcall(zone.GetUiMapIdByAreaId, zone, areaId)
	if not mapped or type(uiMapId) ~= "number" then return nil end

	return { map = uiMapId, x = x, y = y, name = name }
end

-- ---------------------------------------------------------------------------
-- the waypoint
-- ---------------------------------------------------------------------------

--- Point TomTom at this quest. Returns true, or false and a reason.
--
--  `loc` is optional: the menu has already worked out whether there is anywhere
--  to go in order to decide whether to grey the item, and asking Questie twice
--  in one click is both wasteful and racy - `GetNearestSpawn` ranks by distance
--  to the player, so two calls a second apart can pick different spawns.
function Nav:Route(questID, questTitle, loc)
	if not HasTomTom() then return false, "TomTom isn't loaded." end

	loc = loc or self:Locate(questID)
	if not loc then return false, "no location for that quest." end

	-- Ours goes first, always: AddWaypoint deduplicates on map/x/y/title and
	-- would hand back the old uid without re-pointing the arrow (trap 3).
	self:Clear()

	local title = loc.name or questTitle or "Quest"
	local ok, uid = pcall(TomTom.AddWaypoint, TomTom, loc.map, loc.x, loc.y, {
		title = title,
		from  = ADDON,
		-- Arm the arrow. It is the whole point of asking.
		crazy = true,
		-- Never written to TomTom's saved variables. See trap 2.
		persistent = false,
	})
	if not ok or type(uid) ~= "table" then return false, "TomTom refused the waypoint." end

	-- The other half of trap 3, and the one that is easy to miss: the duplicate
	-- AddWaypoint refuses to make may not be OURS. Questie builds its waypoints
	-- from the same call we do - same map, same coordinates, and the same spawn
	-- name as the title - so if the player set one from Questie's map first, the
	-- key matches and TomTom hands us back QUESTIE'S uid, unmodified and with
	-- the arrow untouched. Adopting it would mean our next Route deletes their
	-- waypoint, which is the exact cross-addon stomp this file exists to avoid.
	--
	-- `from` is stamped by AddWaypoint out of our own opts, so it is the honest
	-- test of who made it. When it is not ours we leave it alone and just point
	-- the arrow, which is all that was missing anyway.
	if uid.from ~= ADDON then
		if type(TomTom.SetCrazyArrow) == "function" then
			local arrival = TomTom.profile and TomTom.profile.arrow
				and TomTom.profile.arrow.arrival
			pcall(TomTom.SetCrazyArrow, TomTom, uid, arrival, title)
		end
		return true, loc.name
	end

	waypoint, routed = uid, questID
	return true, loc.name
end

--- Is this uid still the live waypoint TomTom knows about?
--
--  Not paranoia. TomTom removes a waypoint by itself once you walk within
--  `cleardistance` yards of it, so ours dies the moment you arrive and our
--  handle goes stale with nothing to tell us. RemoveWaypoint on that dead table
--  is worse than a no-op: it clears frames by table IDENTITY but deletes
--  records by KEY, so if a waypoint with the same map, coordinates and title
--  exists by then - Questie's, or a `/way` - we would delete ITS record while
--  leaving its pins registered, orphaned on the minimap until a reload.
--
--  If TomTom is too old to have the registry we look in, we say yes and accept
--  the old behaviour: the check is an improvement, not a prerequisite.
local function Live(uid)
	if type(TomTom.waypoints) ~= "table" or type(TomTom.GetKey) ~= "function" then
		return true
	end
	local byMap = TomTom.waypoints[uid[1]]
	if type(byMap) ~= "table" then return false end
	local ok, key = pcall(TomTom.GetKey, TomTom, uid)
	if not ok then return false end
	return byMap[key] == uid
end

--- Drop ours, if we still have one.
function Nav:Clear()
	if not waypoint then return end
	if HasTomTom() and Live(waypoint) then
		pcall(TomTom.RemoveWaypoint, TomTom, waypoint)
	end
	waypoint = nil
	routed = nil
end

--- Drop ours only if it belongs to this quest. Called when a quest leaves the
--  tracker - turned in, abandoned, or dismissed - because an arrow still
--  pointing at the boars of a quest you handed in twenty minutes ago is the
--  kind of thing you stop trusting the arrow over.
function Nav:ClearFor(questID)
	if questID and routed == questID then self:Clear() end
end

--- Which quest the live waypoint belongs to, or nil.
function Nav:Routed() return routed end

--- Test seam. The harness needs to see what we are holding, and nothing else
--  has any business knowing.
function Nav:Waypoint() return waypoint end
