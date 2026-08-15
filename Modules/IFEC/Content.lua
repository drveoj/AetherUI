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

local function progressStore()
	local cfg = A.Config and A.Config:Module("ifec")
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

function Content:Remember(key, segment, complete)
	local store = progressStore()
	if not store or type(key) ~= "string" then return false end
	store[key] = {
		segment  = segment or 0,
		complete = complete and true or nil,
		at       = today(),
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

--- How long an item runs, for filling a programme.
local function lengthOf(item)
	if type(item.duration) == "number" and item.duration > 0 then return item.duration end
	local total = 0
	for _, seg in ipairs(item.segments or {}) do total = total + (seg.duration or 0) end
	-- Gossip is read, not played. It occupies no time on the programme bar.
	return total
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

	-- The player's picks, in the order they picked them.
	for _, key in ipairs(picked or {}) do
		add(byKey[key])
	end

	-- Anything part-played, oldest listening first so a half-finished episode
	-- is what greets you rather than something new.
	local resume = {}
	for _, item in ipairs(available) do
		local p = self:Progress(item.key)
		if p and not p.complete and (p.segment or 0) > 0 then
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

	-- Then unplayed. Catalogue order already has the current season last, so it
	-- is walked backwards: newest season first, older ones behind it.
	for i = #available, 1, -1 do
		local item = available[i]
		if filled >= seconds then break end
		if item.type ~= "music" and not self:Progress(item.key) then add(item) end
	end

	-- Music fills whatever is left, and keeps filling after everything else has
	-- run out. Silence over the Barrens is the failure this exists to prevent.
	local music = {}
	for _, item in ipairs(available) do
		if item.type == "music" and not taken[item.key] then music[#music + 1] = item end
	end
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
