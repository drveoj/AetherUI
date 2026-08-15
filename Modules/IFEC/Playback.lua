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
	wrong for a programme. PlaySoundFile on the Music channel plus StopSound is.

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

--- Take the Music channel, remembering who had it.
--
--  Zen loops an ambient track on the same channel and PlayMusic replaces
--  whatever is playing, so the two would fight for a whole flight. The console
--  wins while you are a passenger - the flight is the foreground activity and
--  its content is the point - and Zen is told to give it up rather than being
--  talked over, so its own state stays true.
local function takeChannel()
	local Z = A:GetModule("zen")
	if Z and Z.enabled and Z.RestoreAudio and not Playback._hadZen then
		Playback._hadZen = true
		pcall(Z.RestoreAudio, Z)
	end
end

local function giveChannelBack()
	if not Playback._hadZen then return end
	Playback._hadZen = nil
	local Z = A:GetModule("zen")
	-- Only if zen is still up. Handing the channel back to something that has
	-- since ended would start a track nobody asked for.
	if Z and Z.enabled and Z._zen and Z.SetAudio then
		pcall(Z.SetAudio, Z, 1)
	end
end

-- ---------------------------------------------------------------------------
-- segments
-- ---------------------------------------------------------------------------

local function stopHandle()
	if Playback.handle and StopSound then
		pcall(StopSound, Playback.handle)
	end
	Playback.handle = nil
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
local function playSegment(index)
	local item = Playback.item
	if not item or not item.segments then return false end

	local seg = item.segments[index]
	if not seg then return false end

	stopHandle()
	takeChannel()

	if not PlaySoundFile then return false end
	local willPlay, handle = PlaySoundFile(seg.file, "Music")

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
		if playSegment((Playback.index or 1) + 1) then
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

-- ---------------------------------------------------------------------------
-- the programme
-- ---------------------------------------------------------------------------

--- Load a queue and start it.
function Playback:Start(queue, from)
	self.queue = queue or {}
	self.at    = from or 1
	self.stopped = nil
	return self:PlayAt(self.at)
end

function Playback:PlayAt(n)
	local item = self.queue and self.queue[n]
	if not item then
		self.state = "exhausted"
		announce("exhausted")
		return false
	end

	self.at   = n
	self.item = item

	-- Gossip is read, not played. It occupies no time on the channel, so the
	-- programme moves past it rather than sitting in silence for its duration.
	if item.type == "gossip" then
		announce("reading", item)
		return self:Next()
	end

	-- RESUME WHERE IT WAS LEFT. The stored index is the last segment COMPLETED,
	-- so the next one is where to start; a finished item starts again.
	local p = Content:Progress(item.key)
	local start = 1
	if p and not p.complete and (p.segment or 0) > 0 then
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

function Playback:Toggle()
	if self.state == "playing" then return self:Pause() end
	if self.state == "paused" then return self:Resume() end
	return false
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
	self.index, self.segStart, self.pausedAt = nil, nil, nil
	self.state = "stopped"

	giveChannelBack()
	announce("stopped")
	return true
end

function Playback:IsPlaying()
	return self.state == "playing"
end
