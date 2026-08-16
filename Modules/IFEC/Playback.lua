--[[--------------------------------------------------------------------------
	AetherUI :: IFEC playback

	Playing a programme across a flight.

	There is NO playback-finished callback for a file path on this client.
	PlaySoundFile returns willPlay and a handle; SOUNDKIT_FINISHED only fires for
	PlaySound with a kit ID. So the end of a segment is not observed, it is
	predicted from the duration the manifest baked in - which is why those
	durations are probed by tooling and never hand-written.

	NEVER ACCUMULATE OFFSETS. Each next fire is computed against GetTime, not
	added to the last one. A tenth of a second of timer slop per boundary is
	inaudible once and obvious after fifteen minutes of episode.

	PlayMusic is not used anywhere here: it loops, which is right for Zen and
	wrong for a programme. PlaySoundFile plus StopSound is - but NOT on the
	Music channel, which plays over the game's own zone music rather than
	replacing it. See the note above CHANNEL.

	Not on the timer path. The flight timer must work with every line of this
	absent.
----------------------------------------------------------------------------]]

local ADDON, A = ...

A.IFEC = A.IFEC or {}
local Playback = {}
A.IFEC.Playback = Playback

local Content = A.IFEC.Content

Playback.listeners = {}

--- "playing" | "paused" | "stopped" | "muted" | "exhausted"
Playback.state = "stopped"

-- What the player asked for by hand, keyed by item.
--
-- HERE RATHER THAN ON A SURFACE, because there are two of them now: the console
-- in flight and the mini-player on the ground, both looking at one queue. A set
-- rather than a flag on the item, because the registry hands the same table to
-- everybody who asks and anything written onto one outlives the session.
Playback.picked = {}

function Playback:AddListener(fn)
	if type(fn) == "function" then
		self.listeners[#self.listeners + 1] = fn
	end
end

local function announce(event, ...)
	for _, fn in ipairs(Playback.listeners) do
		pcall(fn, event, ...)
	end
end

local function now()
	return GetTime and GetTime() or 0
end

-- ---------------------------------------------------------------------------
-- the channel
-- ---------------------------------------------------------------------------

-- NOT THE MUSIC CHANNEL. The brief says to play on "Music" so the programme
-- follows the music slider, and on this client that plays OVER the game's own
-- zone music rather than replacing it - two things at once, which is what it
-- sounded like. The game's music is Sound_EnableMusic, and switching that off
-- would take our audio with it if we shared the channel.
--
-- So the game's music is silenced for the flight and the programme plays
-- somewhere else. The cost is that it follows the Ambience slider rather than
-- the Music one; the alternative was PlayMusic, which does replace the game's
-- music but loops, and a looping segment restarts audibly if the boundary
-- timer is a few frames late.
local CHANNEL = "Ambience"

-- The settings held for the duration of a flight, and what they should be while
-- we hold them. Both are put back on landing.
--
-- Sound_EnableSoundWhenGameIsInBG is here because of what the client does
-- without it: alt-tab away and every sounding handle is killed, and coming back
-- starts none of them again. There is no focus event to recover from - the
-- programme simply went quiet while our own timer carried on counting down a
-- track nobody could hear. Holding it for the flight is the only fix available.
local HELD = {
	Sound_EnableMusic = "0",
	Sound_EnableSoundWhenGameIsInBG = "1",
}

--- Where we put what the settings were, so a crash mid-flight can undo it.
--
--  IN THE SAVED VARIABLES, not only in memory. `_took` is a field on a table
--  that dies with the session, so a client that crashed or was killed on a
--  griffin left the game permanently silent with nothing anywhere saying why -
--  which is the exact failure the note above Recover calls the worst this could
--  leave behind, surviving the one event that stops every handler from running.
local function heldStore()
	local cfg = A.Config and A.Config:Module("ifec")
	if not cfg then return nil end
	cfg.held = cfg.held or {}
	return cfg.held
end

--- Take the channel, remembering what it was.
local function takeChannel()
	if Playback._took then return end
	Playback._took = true

	local store = heldStore()
	if GetCVar and SetCVar then
		for name, want in pairs(HELD) do
			local ok, was = pcall(GetCVar, name)
			if ok and was ~= nil then
				if store then store[name] = was end
				if was ~= want then pcall(SetCVar, name, want) end
			end
		end
	end
	-- And stop what it is playing this second: the CVar governs what starts
	-- next, not what is already sounding.
	if StopMusic then pcall(StopMusic) end

	-- Zen loops an ambient track and PlayMusic replaces whatever is on the
	-- channel, so the two would fight for a whole flight. The console wins
	-- while you are a passenger, and Zen is told to give the channel up rather
	-- than being talked over, so its own state stays true.
	local Z = A:GetModule("zen")
	if Z and Z.enabled and Z.RestoreAudio and not Playback._hadZen then
		Playback._hadZen = true
		pcall(Z.RestoreAudio, Z)
	end
end

local function giveChannelBack()
	Playback._took = nil

	-- Read back out of the save file rather than out of a field, so this is the
	-- same code path whether the flight ended a second ago or the client died
	-- on the griffin and this is the next login putting things right.
	local store = heldStore()
	if store and SetCVar then
		for name in pairs(HELD) do
			if store[name] ~= nil then
				pcall(SetCVar, name, store[name])
				store[name] = nil
			end
		end
	end

	if Playback._hadZen then
		Playback._hadZen = nil
		local Z = A:GetModule("zen")
		-- Only if zen is still up. Handing the channel back to something that
		-- has since ended would start a track nobody asked for.
		if Z and Z.enabled and Z._zen and Z.SetAudio then
			pcall(Z.SetAudio, Z, 1)
		end
	end
end

--- Put the player's sound settings back if we are still holding them and there
--  is no programme.
--
--  A SILENCED GAME is the worst thing this could leave behind - worse than the
--  hidden interface, because nothing on screen would say why. Hooked to world
--  load as well as to landing.
--
--  NOT GATED ON `_took`. That was a field on a live table, so the one case this
--  most needed to cover - a session that ended without ever reaching a landing
--  - was the one case it did nothing for. What is held is written down, so the
--  question is whether anything is written down.
function Playback:Recover()
	if self.state == "playing" then return false end

	local store = heldStore()
	local holding = false
	if store then
		for name in pairs(HELD) do
			if store[name] ~= nil then holding = true end
		end
	end
	if not holding and not self._took then return false end

	-- A GHOST FROM A SESSION THAT NEVER SAID GOODBYE. Reaching here with
	-- something written down means the last session ended without a stop -
	-- a crash, or the client killed - so its handle is gone and whatever it was
	-- playing may still be sounding with nothing able to name it.
	--
	-- The channel enable is the only lever left: switching it off stops what is
	-- on it, and it goes straight back on. Best effort, and only on the path
	-- that already knows something was left behind - a clean reload clears the
	-- store on the way out and never comes through here.
	if holding and GetCVar and SetCVar then
		local ok, was = pcall(GetCVar, "Sound_EnableAmbience")
		if ok and was == "1" then
			pcall(SetCVar, "Sound_EnableAmbience", 0)
			pcall(SetCVar, "Sound_EnableAmbience", 1)
		end
	end

	giveChannelBack()
	return true
end

-- ---------------------------------------------------------------------------
-- segments
-- ---------------------------------------------------------------------------

--- Everything we have started and not yet silenced.
--
--  A LIST, because chunked audio deliberately overlaps: the outgoing piece is
--  left to run out under the incoming one, so for a fraction of a second there
--  are two. Anything that means "silence" - a stop, a pause, a skip - has to
--  reach both, and a single field would leak the one it had just overwritten
--  and leave it playing under everything that followed.
Playback.handles = {}

local function stopHandle()
	if StopSound then
		for _, h in ipairs(Playback.handles) do pcall(StopSound, h) end
	end
	Playback.handles = {}
	Playback.handle = nil
end

--- Silence everything EXCEPT the one just handed over from.
--
--  At a chunk boundary the outgoing piece is fading out on its own and must be
--  left alone; anything older than it is finished and is only still in the list
--  because nothing has swept it. Bounded at two, so an hour of three-second
--  pieces does not accumulate twelve hundred dead handles.
local function keepLast()
	local keep = Playback.handles[#Playback.handles]
	if StopSound then
		for i = 1, #Playback.handles - 1 do
			pcall(StopSound, Playback.handles[i])
		end
	end
	Playback.handles = keep and { keep } or {}
end

local function cancelTimer()
	if Playback.timer and Playback.timer.Cancel then
		pcall(Playback.timer.Cancel, Playback.timer)
	end
	Playback.timer = nil
end

--- Start segment `index` of the current item.
--
--  Returns false when the channel is muted. willPlay comes back nil then, and
--  the difference between "muted" and "playing silence" is the difference
--  between a console that says what is wrong and one that looks broken.
--- `handover` is a natural boundary inside overlapping audio: the outgoing
--  piece has a fade of its own baked into its tail and is left to run out under
--  this one. Everywhere else - a skip, a resume, the start of a programme - the
--  channel is cleared first, because there is nothing to hand over from.
local function playSegment(index, handover)
	local item = Playback.item
	if not item or not item.segments then return false end

	local seg = item.segments[index]
	if not seg then return false end

	if handover and (item.overlap or 0) > 0 then
		keepLast()
	else
		stopHandle()
	end
	takeChannel()

	if not PlaySoundFile then return false end
	local willPlay, handle = PlaySoundFile(seg.file, CHANNEL)

	if not willPlay then
		-- The client says nil for a muted channel AND for a file it could not
		-- play, and does not distinguish them. Recorded either way, because a
		-- segment that quietly fails is a programme that stops for no stated
		-- reason - which is exactly what it looked like.
		Playback.state = "muted"
		Playback.lastFail = seg.file
		announce("muted", item)
		return false
	end
	Playback.lastFail = nil

	Playback.handles[#Playback.handles + 1] = handle
	Playback.handle   = handle
	Playback.index    = index
	Playback.segStart = now()
	Playback.state    = "playing"
	return true
end

--- What the clock says about where we are, in seconds into the current item.
function Playback:Elapsed()
	local item = self.item
	if not item or not item.segments then return 0 end

	local before = 0
	for i = 1, (self.index or 1) - 1 do
		before = before + (item.segments[i].duration or 0)
	end

	if self.state ~= "playing" then return before + (self.pausedAt or 0) end
	return before + (now() - (self.segStart or now()))
end

local advance   -- forward declaration: the timer body calls it

--- Schedule the end of the segment that is playing.
--
--  Computed against GetTime rather than by adding to the last fire: C_Timer is
--  not sample-accurate and the error is one-directional, so accumulating it
--  walks the boundaries later and later until a segment is audibly clipped.
local function scheduleNext()
	cancelTimer()
	if not C_Timer or not C_Timer.NewTimer then return end

	local item = Playback.item
	local seg  = item and item.segments and item.segments[Playback.index]
	if not seg then return end

	local due = (Playback.segStart or now()) + (seg.duration or 0)
	local wait = due - now()
	if wait < 0 then wait = 0 end

	Playback.timer = C_Timer.NewTimer(wait, function() advance() end)
end

--- The segment ended. Save, and go on.
--
--  Position is written at EVERY boundary rather than at landing: a disconnect
--  mid-flight is exactly when somebody most wants their place kept, and it is
--  the one moment no landing handler ever runs.
advance = function()
	local item = Playback.item
	if not item then return end

	local finished = (Playback.index or 1) >= #(item.segments or {})
	Content:Remember(item.key, Playback.index or 1, finished)

	if not finished then
		if playSegment((Playback.index or 1) + 1, true) then
			scheduleNext()
			announce("segment", item, Playback.index)
		else
			-- Said out loud. A segment that fails part way through an item used
			-- to end the programme in silence with nothing anywhere saying so.
			announce("stalled", item, Playback.index)
		end
		return
	end

	announce("finished", item)
	Playback:Next()
end

--- Is the boundary overdue with nothing having happened?
--
--  ONE TIMER IS THE WHOLE CHAIN. There is no playback-finished event on this
--  client, so if that timer is ever lost - an error thrown at a boundary
--  before it reschedules, a C_Timer that does not fire across a loading screen
--  - the programme stops dead and goes on saying "playing" while it does it.
--  Taxi keeps a ticker behind its events for exactly this reason.
--
--  TWO SECONDS OF GRACE, so ordinary timer slop is never mistaken for a
--  failure. Called from the player region's tick; costs a subtraction.
function Playback:Poll()
	if self.state ~= "playing" then return false end

	local seg = self.item and self.item.segments and self.item.segments[self.index or 1]
	if not seg then return false end
	if now() - (self.segStart or now()) < (seg.duration or 0) + 2 then return false end

	-- NOT AGAIN FOR THE SAME SEGMENT. If advance is what is throwing, retrying
	-- it every frame turns one broken boundary into a wall of errors.
	if self._polled == self.segStart then return false end
	self._polled = self.segStart

	cancelTimer()
	local ok, err = pcall(advance)
	if not ok then
		Playback.state = "stopped"
		A:Print("|cffff8a8aifec: the programme stopped at a boundary|r: " .. tostring(err))
	end
	return true
end

-- ---------------------------------------------------------------------------
-- the programme
-- ---------------------------------------------------------------------------

--- Load a queue and start it.
function Playback:Start(queue, from)
	self.queue = queue or {}
	self.at    = from or 1
	self.spent = nil
	self.stopped = nil
	return self:PlayAt(self.at)
end

--- Take over a queue whose first item is ALREADY SOUNDING.
--
--  The difference from Start is everything that is not done: no stopHandle, no
--  playSegment, no new segStart. Boarding with the mini-player running used to
--  build a programme and Start it, which cut a track off mid-bar to play a
--  track - there is one queue and one thing playing, and a flight is a length
--  to fill rather than a reason to begin again.
function Playback:Adopt(queue)
	if not self.item then return self:Start(queue) end

	self.queue = queue or { self.item }
	self.at = 1
	self.spent = nil
	self.stopped = nil

	-- The timer is still armed against the boundary it was armed for, which is
	-- the same boundary: the segment did not change.
	announce("queue")
	return true
end

--- How long queue position `n` actually ran for, which is its own length until
--  something cut it short.
function Playback:Spent(n, item)
	local cut = self.spent and self.spent[n]
	if cut and cut > 0 then return cut end
	return (item or (self.queue and self.queue[n]) or {}).duration or 0
end

--- Asked for one more item when the queue has run out, by whoever built it.
--
--  A hook rather than a call into content selection, so this file still knows
--  nothing about seasons and the programme can end simply by there being no
--  hook set.
Playback.refill = nil

function Playback:PlayAt(n)
	local item = self.queue and self.queue[n]

	-- A PROGRAMME IS BUILT TO COVER THE FLIGHT, not to be everything there is:
	-- one four-minute track covers a three-minute hop, so "next" had nowhere to
	-- go on most flights and ended the programme instead. A skip button that
	-- stops the music is not a skip button.
	if not item and self.refill and not self.stopped then
		local ok, extra = pcall(self.refill, n)
		if ok and extra and self.queue then
			self.queue[n] = extra
			item = extra
		end
	end

	if not item then
		-- SILENCE THE CHANNEL FIRST. Running off the end left the last track
		-- still sounding while the state said exhausted, the clock read zero and
		-- the button showed play - a console insisting nothing was playing over
		-- the sound of something playing.
		cancelTimer()
		stopHandle()
		self.item = nil
		self.state = "exhausted"
		announce("exhausted")
		return false
	end

	-- WHAT AN ITEM ACTUALLY GOT, before we leave it. A skipped track occupied
	-- the twenty seconds it played, not the three and a half minutes it was
	-- going to - and the programme bar is a timeline, so drawn at its full
	-- length everything after it sat in the wrong place and the headline
	-- claimed the queue filled six minutes of a four-minute flight.
	--
	-- Measured here rather than announced, because Elapsed reads state this is
	-- about to overwrite.
	if self.item and self.at and self.at ~= n then
		self.spent = self.spent or {}
		self.spent[self.at] = self:Elapsed()
	end

	self.at   = n
	self.item = item

	-- A BACKSTOP THAT SHOULD NEVER FIRE. Gossip is read rather than played and
	-- no longer enters a queue at all - content selection leaves it out, Pick
	-- refuses it and the library opens it instead. This stays because a queue is
	-- a table anybody can hand us, and the alternative to stepping past a
	-- bulletin is four minutes of silence with the console saying it is playing.
	if item.type == "gossip" then
		announce("reading", item)
		return self:Next()
	end

	-- RESUME WHERE IT WAS LEFT. The stored index is the last segment COMPLETED,
	-- so the next one is where to start; a finished item starts again.
	--
	-- EXCEPT MUSIC, which starts from the top. A song is not a thing you are
	-- part way through, and this only became visible once a track was CHUNKED to
	-- buy a pause - sixty segments instead of one means "where it was left" is
	-- suddenly a real position, and a song picking up at two minutes in because
	-- you landed there last week is not what anybody meant by resume.
	local p = Content:Progress(item.key)
	local start = 1
	if item.type ~= "music" and p and not p.complete and (p.segment or 0) > 0 then
		start = math.min((p.segment or 0) + 1, #(item.segments or {}))
	end

	if not playSegment(start) then return false end
	scheduleNext()
	announce("playing", item, start)
	return true
end

function Playback:Next()
	if self.stopped then return false end
	return self:PlayAt((self.at or 1) + 1)
end

function Playback:Previous()
	return self:PlayAt(math.max(1, (self.at or 1) - 1))
end

--- Pause where we are, keeping the position.
function Playback:Pause()
	if self.state ~= "playing" then return false end
	self.pausedAt = now() - (self.segStart or now())
	cancelTimer()
	stopHandle()
	self.state = "paused"
	announce("paused", self.item)
	return true
end

--- NEVER AGAINST AN EXPLICIT STOP. Resuming restarts the segment rather than
--  seeking into it - there is no seek on this client - so a pause costs at most
--  the part of one segment already heard.
function Playback:Resume()
	if self.state ~= "paused" then return false end
	if not playSegment(self.index or 1) then return false end
	self.pausedAt = nil
	scheduleNext()
	announce("playing", self.item, self.index)
	return true
end

--- EVERY OTHER STATE STILL HAS A PLAY BUTTON. This handled two of the five and
--  did nothing at all in the rest, so the moment anything went wrong - a file
--  that would not play, a skip off the end of the queue, the client killing the
--  sound while the window was in the background - the transport went dead with
--  no way back short of landing. Play means play: start whatever we are on.
function Playback:Toggle()
	if self.state == "playing" then return self:Pause() end
	if self.state == "paused" then return self:Resume() end

	self.stopped = nil
	return self:PlayAt(self.at or 1)
end

--- Everything down, at once.
--
--  On landing this must be immediate and without a fade: audio still going
--  after the player has control back is the worst failure this feature has.
function Playback:Stop(explicit)
	cancelTimer()
	stopHandle()

	if self.item and self.state == "playing" then
		Content:Remember(self.item.key, math.max((self.index or 1) - 1, 0), false)
	end

	self.stopped = explicit and true or nil
	self.item, self.queue, self.at = nil, nil, nil
	self.spent = nil
	self.index, self.segStart, self.pausedAt = nil, nil, nil
	self.state = "stopped"

	giveChannelBack()
	announce("stopped")
	return true
end

function Playback:IsPlaying()
	return self.state == "playing"
end

-- ---------------------------------------------------------------------------
-- building a queue by hand
--
-- Shared by both surfaces. The console builds a programme to fit a flight and
-- the mini-player builds one a track at a time, but a queue is a queue and the
-- rules for what may be taken out of one do not change with who is looking.
-- ---------------------------------------------------------------------------

--- Nothing is playing and nothing is paused: the queue is a list, not a state,
--  and every position in it is still ahead of you.
local function idle()
	return Playback.state ~= "playing" and Playback.state ~= "paused"
end

--- Where `item` is COMING UP, or nothing.
--
--  AHEAD, NOT ANYWHERE. The queue keeps what has already run - the programme
--  bar is a timeline and needs the past to draw it - so "is this in the queue"
--  and "is this still going to play" are two different questions, and answering
--  the first one when the second was asked is what left a skipped track drawn
--  as queued with no way to clear it. The LAST occurrence wins, so a track added
--  again after being skipped is found at the position it will next play.
function Playback:Ahead(item)
	if not item or not self.queue then return nil end
	local from = idle() and 0 or (self.at or 1)
	local found
	for i, q in ipairs(self.queue) do
		if q.key == item.key and i > from then found = i end
	end
	return found
end

--- Where `item` sits in the queue at all, ahead or behind.
function Playback:Queued(item)
	if not item or not self.queue then return nil end
	for i, q in ipairs(self.queue) do
		if q.key == item.key then return i end
	end
	return nil
end

--- Add an item to the programme, or take it back out. Says which it did.
--
--  APPENDED, never inserted over the top of what is playing. "Play this next"
--  and "stop playing that" are two different asks and the transport is where the
--  second one lives - a click in a list that cut a track off mid-bar would be a
--  list that punishes browsing.
--
--  Removal reaches only what is still COMING. Anything at or behind the current
--  position has already had its turn, and a click there means "again" rather
--  than "undo" - which is the only reading that leaves the row a working toggle
--  after a skip. Appending a second copy is right and not a bug: a queue is a
--  running order, and the same track twice in an evening is a normal thing to
--  ask for.
--
--  GOSSIP IS NOT QUEUED. It is read, not played, so it never enters a running
--  order at all - the library opens it instead.
function Playback:Pick(item)
	if not item or item.type == "gossip" then return nil end
	self.queue = self.queue or {}

	local at = self:Ahead(item)
	if at then
		table.remove(self.queue, at)
		if not self:Ahead(item) then self.picked[item.key] = nil end
		announce("queue")
		return "removed"
	end

	self.queue[#self.queue + 1] = item
	self.picked[item.key] = true
	announce("queue")
	return "added"
end

--- Music, least recently heard first. The one-press default everywhere it is
--  offered: the complete state's first chip, and the mini-player's play button
--  with nothing queued.
function Playback:Shuffle()
	local Content = A.IFEC.Content
	if not Content then return false end

	local queue = Content:MusicQueue()
	if #queue == 0 then return false end

	self.picked = {}
	self:Start(queue)
	return true
end

--- Play, from whatever state and with whatever is to hand.
--
--  The mini-player's button, and the difference between it and Toggle is the
--  empty case: on the ground there may be no queue at all yet, and a play button
--  that does nothing on the first press is a broken one.
function Playback:PlayOrShuffle()
	if self.state == "playing" or self.state == "paused" then
		return self:Toggle()
	end
	if self.queue and #self.queue > 0 then
		self.stopped = nil
		return self:PlayAt(math.min(self.at or 1, #self.queue))
	end
	return self:Shuffle()
end

-- Self-starting, like the registry: a world load puts the player's music
-- setting back if a flight ended in a way nothing else saw.
A:RegisterEvent(Playback, "PLAYER_ENTERING_WORLD", function() Playback:Recover() end)

-- AND A RELOAD IS NOT A STOP. Reloading throws away every Lua table in the
-- addon - including the sound handle - but it does NOT touch the client's sound
-- engine, so the track carries straight on with nothing left alive that knows
-- how to stop it. Playing anything afterwards played it OVER the ghost of the
-- last session.
--
-- PLAYER_LOGOUT is the one event that fires for a reload as well as for logging
-- out and quitting, and it runs before the saved variables are written - so
-- this both silences the handle and gets the player's place in the track, and
-- their sound settings, written down on the way past.
A:RegisterEvent(Playback, "PLAYER_LOGOUT", function() Playback:Stop() end)
