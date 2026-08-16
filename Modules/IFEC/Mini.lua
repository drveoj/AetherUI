--[[--------------------------------------------------------------------------
	AetherUI :: N.I.F.E.C - the Not-In-Flight Entertainment Console

	The same programme, on the ground. A compact region the Toolbox hangs at the
	foot of its drawer, plus a transport chip on the rail so the thing can be
	paused without opening anything.

	ONE QUEUE, TWO SURFACES. Everything about what is playing lives on Playback;
	this and the in-flight player region are both views onto it, and neither owns
	the other. That is why picking a track in the library while parked and
	picking one at ten thousand feet are the same code path.

	WHAT IT IS NOT is a second player. Starting a flight hands the audio to the
	console's region, which builds a programme shaped like the journey; landing
	hands it back. Both call the same Playback, so nothing has to be handed over
	- there is only ever one thing playing.

	Not on the timer path, and the Toolbox works with this file absent: it asks
	for a region and lays out without one if it does not get it.
----------------------------------------------------------------------------]]

local ADDON, A = ...

A.IFEC = A.IFEC or {}
local Mini = {}
A.IFEC.Mini = Mini

local W, Media, Palette = A.Widgets, A.Media, A.Palette
-- The library is reached through A.IFEC at call time rather than captured here:
-- it is the one thing on this list that may not have loaded yet, and it is only
-- ever wanted after somebody has clicked something.
local Content, Playback = A.IFEC.Content, A.IFEC.Playback

local PAD_X   = 12
local PAD_Y   = 10
local ROW_H   = 32            -- title over artist
local GLYPH   = 14
local BAR_H   = 3
local BTN     = 22
local TOGGLE  = 28

--- How tall the region wants to be. The Toolbox asks before it lays out, so
--  this is said once and both sides add up the same stack.
Mini.HEIGHT = PAD_Y + ROW_H + 8 + BAR_H + 10 + TOGGLE + PAD_Y

local function tintFor(kind)
	local c = Palette.c
	if kind == "music"  then return c.ifecMusic end
	if kind == "gossip" then return c.ifecGossip end
	return c.ifecPodcast
end

local function clock(secs)
	if type(secs) ~= "number" or secs < 0 then secs = 0 end
	return string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
end

-- ---------------------------------------------------------------------------
-- construction
-- ---------------------------------------------------------------------------

local function glyphButton(parent, icon, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(BTN, BTN)
	b:EnableMouse(true)
	b.glyph = b:CreateTexture(nil, "ARTWORK")
	b.glyph:SetSize(size or 14, size or 14)
	b.glyph:SetPoint("CENTER")
	Media:SetIcon(b.glyph, icon)
	return b
end

function Mini:Build(parent)
	if self.frame then
		if parent and self.frame:GetParent() ~= parent then
			self.frame:SetParent(parent)
		end
		return self.frame
	end
	if not parent then return nil end

	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(self.HEIGHT)

	f.glyph = f:CreateTexture(nil, "OVERLAY")
	f.glyph:SetSize(GLYPH, GLYPH)
	f.glyph:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, -PAD_Y - 2)

	-- BOTH SIDES ANCHORED, so the strings have a width to be cut to. A title is
	-- as long as its author made it, and this column is the narrowest place in
	-- the interface that one is ever drawn.
	f.title = W.Text(f, "ifecUpNext", "LEFT", "OVERLAY")
	f.title:SetPoint("TOPLEFT", f.glyph, "TOPRIGHT", 8, 2)
	f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_X, -PAD_Y)
	f.title:SetWordWrap(false)

	f.meta = W.Text(f, "ifecCaption", "LEFT", "OVERLAY")
	f.meta:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
	f.meta:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -2)
	f.meta:SetWordWrap(false)

	-- ONE BAR, and it is the item rather than a journey. There is no flight to
	-- lay a second one against out here, and a lone bar drawn where the console
	-- draws two would be claiming a landing that is not coming.
	f.bar = W.CreateSegmentedBar(f, { height = BAR_H })
	f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, -(PAD_Y + ROW_H + 8))
	f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_X, -(PAD_Y + ROW_H + 8))

	local row = CreateFrame("Frame", nil, f)
	row:SetHeight(TOGGLE)
	row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, -(PAD_Y + ROW_H + 8 + BAR_H + 10))
	row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_X, -(PAD_Y + ROW_H + 8 + BAR_H + 10))
	f.controls = row

	f.prev = glyphButton(row, "prev", 13)
	f.prev:SetPoint("LEFT", row, "LEFT", 0, 0)

	-- The one control with a surface behind it, the same as the console's: it is
	-- the button people reach for without looking.
	f.toggle = W.CreateButton(row, { corner = TOGGLE / 2 })
	f.toggle:SetSize(TOGGLE, TOGGLE)
	f.toggle:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
	f.toggle:EnableMouse(true)
	f.toggle.glyph = f.toggle:CreateTexture(nil, "OVERLAY")
	f.toggle.glyph:SetSize(11, 11)
	f.toggle.glyph:SetPoint("CENTER")
	Media:SetIcon(f.toggle.glyph, "play")

	f.next = glyphButton(row, "next", 13)
	f.next:SetPoint("LEFT", f.toggle, "RIGHT", 4, 0)

	-- The library, at the far end. Same glyph as the console's, because it opens
	-- the same drawer.
	f.library = glyphButton(row, "library", 13)
	f.library:SetPoint("RIGHT", row, "RIGHT", 0, 0)

	self.frame = f
	self:Wire()
	self:Restyle()
	return f
end

function Mini:Wire()
	local f = self.frame

	f.prev:SetScript("OnClick", function() if Playback then Playback:Previous() end end)
	f.next:SetScript("OnClick", function() if Playback then Playback:Next() end end)

	-- PLAY MEANS PLAY, even from a standing start. On the ground there may be no
	-- queue at all yet, and a play button that does nothing on the first press
	-- is a broken one - so it falls through to the ambient shuffle, which is the
	-- same one-press default the console's complete state offers.
	f.toggle:SetScript("OnClick", function()
		if not Playback then return end
		Playback:PlayOrShuffle()
		Mini:Paint()
	end)

	f.library:SetScript("OnClick", function()
		if A.IFEC.Library then A.IFEC.Library:ToggleOpen(f) end
		Mini:Paint()
	end)

	local function tip(button, title, body)
		button:SetScript("OnEnter", function(self)
			W.Tooltip(self, "ANCHOR_RIGHT", title, body)
		end)
		button:SetScript("OnLeave", W.HideTooltip)
	end
	tip(f.library, "Library", "Everything in season. Click a row to add it, or to"
		.. " take it back out.")
	tip(f.toggle, "Play", "With nothing queued this starts the music, least"
		.. " recently heard first.")
end

-- ---------------------------------------------------------------------------
-- painting
-- ---------------------------------------------------------------------------

--- Is there anything to be a player for?
function Mini:HasContent()
	return Content ~= nil and not Content:IsDormant()
end

function Mini:Paint()
	local f = self.frame
	if not f or not Playback then return end

	local item = Playback.item
	local playing = Playback:IsPlaying()
	local c = Palette.c

	Media:SetIcon(f.toggle.glyph, playing and "pause" or "play")

	if not item then
		-- NOT AN EMPTY ROW. Silence has something to say - what pressing play
		-- will do - and a blank line where a title goes reads as a player that
		-- failed rather than one that is waiting.
		Media:SetIcon(f.glyph, "music")
		f.glyph:SetVertexColor(c.textFaint[1], c.textFaint[2], c.textFaint[3], 0.8)
		f.title:SetText("Nothing playing")
		W.Color(f.title, c.textDim)
		f.meta:SetText(self:HasContent() and "Press play for the season's music"
			or "No content installed")
		W.Color(f.meta, c.textFaint)
		f.bar:SetPieces({}, 1)
		return
	end

	local tint = tintFor(item.type)
	Media:SetIcon(f.glyph, item.type)
	f.glyph:SetVertexColor(tint[1], tint[2], tint[3])

	f.title:SetText(item.title or "")
	W.Color(f.title, c.text)

	local elapsed = Playback:Elapsed() or 0
	local total   = item.duration or 0
	local bits = {}
	if item.artist and item.artist ~= "" then bits[#bits + 1] = item.artist end
	bits[#bits + 1] = clock(math.max(total - elapsed, 0)) .. " left"
	if Playback.state == "paused" then bits[#bits + 1] = "paused" end
	f.meta:SetText(table.concat(bits, "  \194\183  "))
	W.Color(f.meta, tint)

	-- ONE PIECE, filled to where we are. The console's bar is a programme
	-- against a flight; this one is a track against itself, which is the only
	-- span that means anything with no journey under it.
	f.bar:SetPieces({ { seconds = math.min(elapsed, total), colour = tint,
		filled = true } }, math.max(total, 1))
end

function Mini:Restyle()
	local f = self.frame
	if not f then return end
	local c = Palette.c

	for _, b in ipairs({ f.prev, f.next, f.library }) do
		b.glyph:SetVertexColor(c.textDim[1], c.textDim[2], c.textDim[3], 0.85)
	end
	f.toggle.glyph:SetVertexColor(c.text[1], c.text[2], c.text[3])
	self:Paint()
end

-- ---------------------------------------------------------------------------
-- the rail chip
--
-- The one control that has to be reachable with the drawer SHUT, which is the
-- same argument that put the mail envelope on the rail. Everything else about
-- the player can wait for the drawer to open; "stop this" cannot.
-- ---------------------------------------------------------------------------

--- Dress a button the Toolbox built for its rail. The Toolbox owns where it
--  goes and how big it is; this owns what it says and what it does.
function Mini:AdoptRailChip(button)
	if not button or button.__ifec then return button end
	button.__ifec = true

	-- LEFT PLAYS, RIGHT OPENS THE REST. The chip is one icon wide and the whole
	-- point of it is not having to open the drawer, so the three controls that
	-- do not fit go on the menu rather than nowhere.
	if button.RegisterForClicks then
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	end
	button:SetScript("OnClick", function(self, mouse)
		if not Playback then return end
		if mouse == "RightButton" then
			Mini:ShowRailMenu(self)
			return
		end
		Playback:PlayOrShuffle()
		Mini:PaintRailChip(self)
		Mini:Paint()
	end)
	button:SetScript("OnEnter", function(self)
		local item = Playback and Playback.item
		W.Tooltip(self, "ANCHOR_RIGHT",
			item and (item.title or "Playing") or "Play",
			item and item.artist ~= "" and item.artist or nil)
	end)
	button:SetScript("OnLeave", W.HideTooltip)

	self.railChip = button
	self:PaintRailChip(button)
	return button
end

--- The transport, for a chip with room for one glyph.
--
--  DISABLED RATHER THAN ABSENT when there is nothing to do: a menu that changes
--  shape between openings is one you cannot learn, and "Stop" greyed says more
--  than "Stop" missing.
--
--  Placement is the Toolbox's, because the rail can be docked on any of four
--  edges and only the Toolbox knows which - a menu that always hung downwards
--  ran off the bottom on a rail docked there.
function Mini:RailEntries()
	local playing = Playback and (Playback.state == "playing"
		or Playback.state == "paused")
	local queue = (Playback and Playback.queue) or {}

	return {
		{ text = "Stop", disabled = not playing,
		  action = function()
			if Playback then Playback:Stop(true) end
			Mini:Paint()
			Mini:PaintRailChip()
		  end },
		{ text = "Previous", disabled = (Playback and (Playback.at or 1) or 1) <= 1,
		  action = function()
			if Playback then Playback:Previous() end
		  end },
		{ text = "Next", disabled = #queue == 0,
		  action = function()
			if Playback then Playback:Next() end
		  end },
	}
end

function Mini:ShowRailMenu(button, opts)
	if not W.Menu then return false end
	W.Menu(button, self:RailEntries(), opts or self.railMenuOpts)
	return true
end

function Mini:PaintRailChip(button)
	button = button or self.railChip
	if not button or not Playback then return end

	local playing = Playback:IsPlaying()
	Media:SetIcon(button.glyph, playing and "pause" or "play")

	-- LIT WHILE SOMETHING IS SOUNDING. This is the only thing on screen saying
	-- so with the drawer shut, so the colour is doing the work the title would.
	local c = Palette.c
	local item = Playback.item
	local tint = playing and (item and tintFor(item.type) or c.accent) or c.textDim
	button.glyph:SetVertexColor(tint[1], tint[2], tint[3], playing and 1 or 0.7)
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

--- Is the programme ours to drive?
--
--  ONE POLLER, NOT TWO. Poll is the backstop for a chain that has no
--  playback-finished event to fall back on, and it refuses to fire twice for
--  the same segment - so with the console's region and this one both calling
--  it, whichever ran first consumed the recovery and the other saw nothing.
--  Whoever owns the programme owns the poll: in flight that is the region, and
--  the region has a queue exactly while it is flying.
local function ours()
	local P = A.IFEC.Player
	return not (P and P.queue)
end

--- Repaint on its own tick while something is playing, and stop when it stops.
--
--  The countdown and the bar both move between playback events, and a playback
--  event happens once a track at best - which is the same trap the console's
--  region fell into and sat frozen on the last boundary for four minutes.
--
--  Nothing to paint is nothing to tick for. Neither surface exists until the
--  Toolbox asks for one, and a ticker running against no frames is work done
--  for a screen nobody is looking at.
function Mini:SetTicking(on)
	if on and not (self.frame or self.railChip) then on = false end

	if on and not self._ticking then
		self._ticking = true
		A:RegisterTicker(self, function()
			if Playback and ours() then Playback:Poll() end
			Mini:Paint()
			Mini:PaintRailChip()
		end)
	elseif not on and self._ticking then
		self._ticking = nil
		A:UnregisterTicker(self)
	end
end

if Playback then
	Playback:AddListener(function(event)
		Mini:Paint()
		Mini:PaintRailChip()
		Mini:SetTicking(Playback:IsPlaying())

		-- The library is a list of what is queued as much as what exists, so it
		-- redraws with the queue rather than only when it is opened.
		local LB = A.IFEC.Library
		if LB and LB:IsOpen() then LB:Paint() end
	end)
end
