--[[--------------------------------------------------------------------------
	AetherUI :: IFEC content selection

	What is in season, what has been played, and what to queue for a flight of a
	given length.

	Content is seasonal and usually absent. When nothing is in season the console
	is dormant - and dormancy has one meaning here regardless of which of the
	three ways it arrived: no packs installed, packs that all refused, or packs
	whose windows have closed. They differ only in what the settings page says.

	THE WINDOW IS RE-READ ON EVERY BOARDING, never cached at login. A player
	logged in across a season boundary should get the new content on their next
	flight rather than having to relog for it.

	Not on the timer path.
----------------------------------------------------------------------------]]

local ADDON, A = ...

A.IFEC = A.IFEC or {}
local Content = {}
A.IFEC.Content = Content

local Registry = A.IFEC.Registry

--- Today as YYYYMMDD.
--
--  A plain number rather than an epoch: the windows are calendar dates written
--  by an author in a text file, and comparing them as dates avoids every
--  timezone and leap-second question an epoch conversion would invite.
local function today()
	local d = date and date("%Y%m%d")
	return tonumber(d) or 0
end

--- "2026-09-01" -> 20260901. Anything else is nil, which reads as "no bound".
local function stamp(s)
	if type(s) == "number" then return s end
	if type(s) ~= "string" then return nil end
	local y, m, d = s:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
	if not y then return nil end
	return tonumber(y .. m .. d)
end

--- Is this item in season on `when`?
--
--  Both bounds are optional and both are inclusive. An item with neither is
--  evergreen, which is a real and supported state - the settings page has a
--  word for it.
function Content:InSeason(item, when)
	when = when or today()
	local from, until_ = stamp(item.activeFrom), stamp(item.activeUntil)
	if from and when < from then return false end
	if until_ and when > until_ then return false end
	return true
end

local function moduleCfg()
	return A.Config and A.Config:Module("ifec")
end

local function progressStore()
	local cfg = moduleCfg()
	if not cfg then return nil end
	cfg.progress = cfg.progress or {}
	return cfg.progress
end

--- What we remember about an item, or nothing.
--
--  Keyed packId:itemId, so uninstalling one season cannot disturb another's
--  progress. State for an id we no longer know is IGNORED rather than deleted:
--  a season that expires and returns should pick up where it was left.
function Content:Progress(key)
	local store = progressStore()
	return store and store[key] or nil
end

--- A COUNTER, NOT JUST A DATE. `at` is a calendar day, so everything heard on
--  one afternoon ties - and the music rotation is decided by which was heard
--  longest ago. Without this it fell back to catalogue order every session and
--  a season of eleven tracks opened with the same one on every flight.
local function nextPlay()
	local cfg = moduleCfg()
	if not cfg then return 0 end
	cfg.playCount = (cfg.playCount or 0) + 1
	return cfg.playCount
end

function Content:Remember(key, segment, complete)
	local store = progressStore()
	if not store or type(key) ~= "string" then return false end
	store[key] = {
		segment  = segment or 0,
		complete = complete and true or nil,
		at       = today(),
		seq      = nextPlay(),
	}
	return true
end

--- Everything in season right now, in catalogue order.
function Content:Available(when)
	if not Registry then return {} end
	when = when or today()

	local out = {}
	for _, item in ipairs(Registry:Catalogue()) do
		if self:InSeason(item, when) then out[#out + 1] = item end
	end
	return out
end

--- THE ONE QUESTION THE CONSOLE ASKS. Three different causes, one answer: the
--  player region is absent rather than empty, and the console lays out as
--  though it were never there.
function Content:IsDormant(when)
	return #self:Available(when) == 0
end

--- WHY there is nothing to play, in a few words for a player.
--
--  IsDormant collapses three causes into one answer, which is right for LAYOUT
--  - the region is absent either way - and wrong for a MESSAGE. "No content
--  installed" printed while a pack sits in the addon list, ticked and using
--  memory, sends somebody looking for a file they already have. Reported from
--  the game.
--
--  The registry already knows all three; nothing here works anything out.
function Content:DormantReason()
	if not Registry then return "No content installed" end

	-- REFUSED FIRST, because it is the only one of the three that is a fault
	-- rather than a state, and the only one with somewhere to go and read more.
	local failed = Registry:Failures() or {}
	if #failed > 0 then
		return "A content pack was refused  ·  /aether ifec"
	end

	if #Registry:Catalogue() == 0 then return "No content installed" end

	-- Installed, registered, and not one item of it in season today.
	return "Nothing in season right now"
end

--- How long an item runs, for filling a programme.
--
--  PUBLIC, because the onboarding tour draws a real programme bar out of the
--  really installed content and needs the same answer. Asked rather than worked
--  out again: a second copy of "its duration, or the sum of its segments, or no
--  time at all because it is a magazine" is a second thing to get wrong.
function Content:Length(item)
	if not item then return 0 end
	if type(item.duration) == "number" and item.duration > 0 then return item.duration end
	local total = 0
	for _, seg in ipairs(item.segments or {}) do total = total + (seg.duration or 0) end
	-- Gossip is read, not played. It occupies no time on the programme bar.
	return total
end

local function lengthOf(item) return Content:Length(item) end

--- Catalogue order: NEWEST SEASON FIRST, but in the season's own order within
--  it. Walking the catalogue backwards got the seasons right and reversed the
--  episodes inside them, which is episode two before episode one.
--
--  Shared, because it is the tail of both the unplayed sort and the music one -
--  and a copy of it that drifts is two lists claiming different things about
--  which season is current.
local function byCatalogue(a, b)
	if (a.season or 0) ~= (b.season or 0) then
		return (a.season or 0) > (b.season or 0)
	end
	if a.packId ~= b.packId then return a.packId < b.packId end
	return (a.index or 0) < (b.index or 0)
end

--- Build a programme to fill `seconds` of flight.
--
--  The design's order: resume first, then unplayed with the current season
--  before older ones, then music as filler. That crosses packs, which the
--  technical brief left open and asked to have settled against the design -
--  and it has to, or a podcast season ending mid-flight could not be followed
--  by an ambient track and the console would fall silent with time to spare.
--
--  `picked` are the player's own choices. They go first and are never dropped,
--  even if they overrun: a queue that quietly removes what somebody asked for
--  is worse than one that runs long.
function Content:Programme(seconds, picked, when)
	local available = self:Available(when)
	local byKey = {}
	for _, item in ipairs(available) do byKey[item.key] = item end

	local queue, taken, filled = {}, {}, 0

	local function add(item)
		if not item or taken[item.key] then return end
		taken[item.key] = true
		queue[#queue + 1] = item
		filled = filled + lengthOf(item)
	end

	-- The player's picks, in the order they picked them. Gossip cannot be one:
	-- there is nothing to pick it with, and a stale key from an older build
	-- would otherwise still put a bulletin in the queue.
	for _, key in ipairs(picked or {}) do
		local item = byKey[key]
		if item and item.type ~= "gossip" then add(item) end
	end

	-- Anything part-played, oldest listening first so a half-finished episode
	-- is what greets you rather than something new.
	--
	-- A PODCAST, AND ONLY A PODCAST. It used to be everything that was not
	-- music, which is right about music and wrong about magazines.
	--
	-- NOT MUSIC. A song is not a thing you are part way through - you start it
	-- again - and the distinction only became visible once a track was CHUNKED
	-- to buy a pause: sixty segments means a stop halfway writes segment 30, and
	-- the track would then have been dragged to the front of every programme
	-- until somebody sat through the end of it.
	--
	-- AND NOT A MAGAZINE. Reader:Remember writes the PAGE you are on through
	-- the same Content:Remember a played segment goes through, so a magazine
	-- you had read three pages of looked exactly like a part-heard episode -
	-- and came back at the head of the programme. Everything below it steps
	-- past a bulletin correctly, so it never made a sound; it just sat in the
	-- playlist saying it was about to play. Gossip is READ, and the only thing
	-- that resumes into a running order is an episode.
	local resume = {}
	for _, item in ipairs(available) do
		local p = self:Progress(item.key)
		if item.type == "podcast" and p and not p.complete
			and (p.segment or 0) > 0 then
			resume[#resume + 1] = item
		end
	end
	table.sort(resume, function(a, b)
		local pa, pb = self:Progress(a.key), self:Progress(b.key)
		if (pa.at or 0) ~= (pb.at or 0) then return (pa.at or 0) > (pb.at or 0) end
		return a.key < b.key
	end)
	for _, item in ipairs(resume) do
		if filled >= seconds then break end
		add(item)
	end

	-- Then unplayed, in catalogue order.
	-- GOSSIP IS READ, NOT PLAYED, so it is not in a running order at all. It
	-- used to be queued and stepped straight past - occupying no time, which is
	-- true, but showing up in UP NEXT as something about to happen, which is
	-- not. The library opens it instead.
	local unplayed = {}
	for _, item in ipairs(available) do
		if item.type == "podcast" and not self:Progress(item.key) then
			unplayed[#unplayed + 1] = item
		end
	end
	table.sort(unplayed, byCatalogue)
	for _, item in ipairs(unplayed) do
		if filled >= seconds then break end
		add(item)
	end

	-- Music fills whatever is left, and keeps filling after everything else has
	-- run out. Silence over the Barrens is the failure this exists to prevent.
	--
	-- LONGEST AGO FIRST, so a season is heard through before anything repeats.
	-- Never-played sorts as seq 0 and comes first, in the pack's own order; the
	-- rest follow in the order they were last heard. Taken in catalogue order it
	-- was the same opening track on every single flight, which is a season of
	-- eleven behaving like a season of three.
	local music = {}
	for _, item in ipairs(available) do
		if item.type == "music" and not taken[item.key] then music[#music + 1] = item end
	end
	-- Two never-heard tracks fall through to catalogue order, which is also how
	-- a test pack stays out of the way: put one at season zero and its filler is
	-- what you get only once the real seasons have been heard.
	table.sort(music, function(a, b)
		local pa, pb = self:Progress(a.key), self:Progress(b.key)
		local sa, sb = pa and pa.seq or 0, pb and pb.seq or 0
		if sa ~= sb then return sa < sb end
		return byCatalogue(a, b)
	end)
	local m = 1
	while filled < seconds and #music > 0 do
		local item = music[m]
		if taken[item.key] then break end          -- been all the way round
		add(item)
		m = m + 1
		if m > #music then break end
	end

	return queue, filled
end

--- The whole catalogue in programme order: what would play if a flight never
--  ended.
--
--  Asked for as a programme long enough to hold everything rather than built
--  from a second copy of the ordering rules, which would drift from the first.
function Content:Everything(when)
	local seconds = 0
	for _, item in ipairs(self:Available(when)) do
		seconds = seconds + lengthOf(item)
	end
	return (self:Programme(seconds, nil, when))
end

--- The next thing to play after everything in `queue`, or nothing.
--
--  A programme is built to COVER the flight, so on a short hop it is a single
--  track - and then the skip button had nowhere to go and ended the programme,
--  which is a console falling silent with flight remaining. That is the one
--  failure the filler exists to prevent, arrived at by a different road.
function Content:NextAfter(queue, when)
	local queued = {}
	for _, item in ipairs(queue or {}) do queued[item.key] = true end

	for _, item in ipairs(self:Everything(when)) do
		if not queued[item.key] then return item end
	end
	return nil
end

--- Music only, in the order the filler would reach for it. The ambient shuffle
--  the complete state offers as its default action.
function Content:MusicQueue(when)
	local out = {}
	for _, item in ipairs(self:Everything(when)) do
		if item.type == "music" then out[#out + 1] = item end
	end
	return out
end
