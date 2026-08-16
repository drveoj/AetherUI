--[[--------------------------------------------------------------------------
	AetherUI :: IFEC content registry

	Content ships as separate addons. This is where they announce themselves and
	where their manifests are merged into one catalogue.

	Assume several are installed at once. Players hoard seasons and there is no
	reason to stop them, so this is a merge from the start rather than a load
	that grew a second case.

	Nothing here is on the timer path. The console must open, count and land with
	this file absent, erroring, or having refused every pack it was given.
----------------------------------------------------------------------------]]

local ADDON, A = ...

A.IFEC = A.IFEC or {}
local Registry = {}
A.IFEC.Registry = Registry

-- The versions of the content contract this build can serve. A range rather
-- than a number: a season built against v1 and one built against v2 will be
-- installed together, and refusing the older one because the engine moved on
-- would break a pack that was working yesterday.
Registry.API_MIN, Registry.API_MAX = 1, 1

Registry.packs   = {}      -- packId -> manifest, accepted
Registry.order   = {}      -- accepted packIds, sorted
Registry.failed  = {}      -- { packId, reason } for the settings readout
Registry.dirty   = true

--- Why a pack was refused, in words a settings page can print.
local REASON = {
	malformed = "manifest is malformed",
	noId      = "manifest declares no packId",
	duplicate = "another pack is already registered under that name",
	tooOld    = "built for an older console",
	tooNew    = "needs a newer console",
	noItems   = "manifest carries no items",
}

local function refuse(packId, reason)
	Registry.failed[#Registry.failed + 1] = {
		packId = packId or "?",
		reason = REASON[reason] or reason,
	}
	return false, reason
end

--- Is this item well enough formed to be worth carrying?
--
--  Strict on purpose. A pack that half-loads is worse than one that is refused:
--  a browse list with a nameless row in it looks like our bug.
local function itemOk(item)
	if type(item) ~= "table" then return false end
	if type(item.id) ~= "string" or item.id == "" then return false end
	if type(item.title) ~= "string" or item.title == "" then return false end

	local kind = item.type
	if kind ~= "podcast" and kind ~= "music" and kind ~= "gossip" then return false end

	-- Optional, but not optional in its type. A number here would reach the
	-- console as "3" beside a song name and look like our bug rather than the
	-- pack's, so it is refused at the door with everything else.
	if item.artist ~= nil and type(item.artist) ~= "string" then return false end

	-- An overlap that is not a number would be compared against zero on every
	-- boundary of every piece, which is an error a second and a half.
	if item.overlap ~= nil and type(item.overlap) ~= "number" then return false end

	-- GOSSIP IS PAGES. A magazine is laid out - masthead, columns, pull-quotes,
	-- art - and rebuilding that from a string in a Lua frame would be writing a
	-- typesetter, so an issue is one 1024 texture a page and the reader's whole
	-- job is turning them. Refused without any, because a bulletin you cannot
	-- open is a row in the library that does nothing.
	if kind == "gossip" then
		if type(item.pages) ~= "table" or #item.pages == 0 then return false end
		for _, page in ipairs(item.pages) do
			if type(page) ~= "string" or page == "" then return false end
		end
	end

	-- The other two are audio and are useless without segments.
	if kind ~= "gossip" then
		if type(item.segments) ~= "table" or #item.segments == 0 then return false end
		for _, seg in ipairs(item.segments) do
			if type(seg) ~= "table" or type(seg.file) ~= "string" then return false end
			if type(seg.duration) ~= "number" or seg.duration <= 0 then return false end
		end
	end

	return true
end

--- Take a pack's manifest, or say why not.
--
--  Never raises. A pack is somebody else's code and its manifest is somebody
--  else's data; one bad one must not stop the next from registering, and none
--  of them may reach the flight timer.
function Registry:Register(manifest)
	if type(manifest) ~= "table" then return refuse(nil, "malformed") end

	local packId = manifest.packId
	if type(packId) ~= "string" or packId == "" then return refuse(nil, "noId") end

	-- NEVER SILENTLY OVERWRITE. packId is the addon folder name, which the
	-- client already guarantees unique, so a clash means two copies of the same
	-- pack or somebody has borrowed a name. Either way the player wants telling.
	if self.packs[packId] then return refuse(packId, "duplicate") end

	local api = manifest.apiVersion
	if type(api) ~= "number" then return refuse(packId, "malformed") end
	if api < self.API_MIN then return refuse(packId, "tooOld") end
	if api > self.API_MAX then return refuse(packId, "tooNew") end

	if type(manifest.items) ~= "table" or #manifest.items == 0 then
		return refuse(packId, "noItems")
	end

	-- Items are copied rather than referenced, and keyed pack-scoped. Two packs
	-- built independently will eventually ship the same item id, and only the
	-- composite is unique.
	local items = {}
	for i, item in ipairs(manifest.items) do
		if itemOk(item) then
			items[#items + 1] = {
				key      = packId .. ":" .. item.id,
				packId   = packId,
				-- Carried onto the item so the queue can order by season
				-- without asking the registry about every entry.
				season   = tonumber(manifest.seasonIndex) or 0,
				id       = item.id,
				type     = item.type,
				title    = item.title,
				artist   = item.artist,
				masthead = item.masthead,
				pages    = item.pages,
				segments = item.segments,
				-- How much of the NEXT segment is also in this one, for audio
				-- cut into crossfaded pieces. Absent - which is every ordinary
				-- item - the pieces are butted together and the outgoing one is
				-- stopped, which is right for a chaptered episode and a click at
				-- every boundary for anything cut every three seconds.
				overlap  = item.overlap,
				duration = item.totalDuration,
				activeFrom  = item.activeFrom,
				activeUntil = item.activeUntil,
				-- Where it sat in its own manifest, which is the tie-break
				-- inside a pack.
				index    = i,
			}
		end
	end

	if #items == 0 then return refuse(packId, "noItems") end

	self.packs[packId] = {
		packId      = packId,
		apiVersion  = api,
		seasonIndex = tonumber(manifest.seasonIndex) or 0,
		displayName = manifest.displayName or packId,
		items       = items,
	}
	self.dirty = true
	return true
end

--- The shared-table handshake, for packs that loaded before we did.
--
--  Load order is not guaranteed and OptionalDeps only nudges it, so a pack
--  calls our register function if it is there and otherwise leaves its manifest
--  in a global for us to collect. Both paths have to work or the pack that
--  happens to sort first stops existing.
function Registry:Drain()
	local pending = _G.AetherUI_IFEC_Pending
	if type(pending) ~= "table" then return 0 end

	local taken = 0
	for _, manifest in ipairs(pending) do
		-- pcall because this is the first time we touch a stranger's table.
		local ok = pcall(self.Register, self, manifest)
		if ok then taken = taken + 1 end
	end

	_G.AetherUI_IFEC_Pending = nil
	return taken
end

--- Publish the handshake so a pack loading after us can call straight in.
function Registry:Publish()
	_G.AetherUI_IFEC = _G.AetherUI_IFEC or {}
	_G.AetherUI_IFEC.Register = function(manifest)
		return Registry:Register(manifest)
	end
	_G.AetherUI_IFEC.apiVersion = Registry.API_MAX
end

--- Packs in a stable order.
--
--  ORDERING MUST NOT DEPEND ON REGISTRATION ORDER. Addon load order is not
--  guaranteed, so a list built in arrival order reshuffles between sessions for
--  no visible reason. seasonIndex decides it, and packId breaks ties so two
--  packs that forgot to set one still sort the same way every time.
function Registry:Sorted()
	if not self.dirty then return self.order end

	local ids = {}
	for packId in pairs(self.packs) do ids[#ids + 1] = packId end
	table.sort(ids, function(a, b)
		local pa, pb = self.packs[a], self.packs[b]
		if pa.seasonIndex ~= pb.seasonIndex then
			return pa.seasonIndex < pb.seasonIndex
		end
		return a < b
	end)

	self.order = ids
	self.dirty = false
	return ids
end

--- One catalogue from every pack.
--
--  Deduplicated on the resolved audio path: the same track legitimately appears
--  in two packs - an ambient set reissued, a best-of - and showing it twice
--  under two season headings reads as a bug. The first pack in sort order keeps
--  it, so which copy wins does not change between sessions.
--
--  ACROSS PACKS, NEVER WITHIN ONE. A pack that opens two of its own items on
--  the same file has done so deliberately - an episode whose first chapter is
--  the same ambient bed the pack also offers on its own is a real shape - and
--  dropping the second was a pack quietly serving fewer items than it declared,
--  with nothing anywhere saying so. Files are marked once the pack they came
--  from is finished with.
function Registry:Catalogue()
	local out, seenFile = {}, {}

	for _, packId in ipairs(self:Sorted()) do
		local pack, mine = self.packs[packId], {}
		for _, item in ipairs(pack.items) do
			local first = item.segments and item.segments[1]
			local file = first and first.file
			if file and seenFile[file] then
				-- already carried by an earlier pack
			else
				if file then mine[#mine + 1] = file end
				out[#out + 1] = item
			end
		end
		for _, file in ipairs(mine) do seenFile[file] = true end
	end

	return out
end

--- Everything installed but not serving, for the settings readout. The only
--  place dormancy is ever explained.
function Registry:Failures()
	return self.failed
end

function Registry:Reset()
	self.packs, self.order, self.failed, self.dirty = {}, {}, {}, true
end

-- SELF-STARTING, because the console may not reference this file. The handshake
-- goes up at load so a pack loading after us can call straight in, and the
-- pending table is drained at login for the ones that loaded before.
--
-- Drained on both events because a pack installed while the addon list is
-- already built can arrive either side of PLAYER_LOGIN; Drain clears the table
-- it reads, so the second call finds nothing and costs nothing.
Registry:Publish()
A:RegisterEvent(Registry, "PLAYER_LOGIN", function() Registry:Drain() end)
A:RegisterEvent(Registry, "PLAYER_ENTERING_WORLD", function() Registry:Drain() end)
