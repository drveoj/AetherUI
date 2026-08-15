--[[--------------------------------------------------------------------------
	AetherUI :: IFEC player region

	What hangs under the console's header when there is something to play.

	The dependency points ONE WAY. This calls Console:AttachRegion and the
	console never reaches back, so the flight timer works with this file absent,
	erroring, or having nothing to show. That is the boundary the brief asks for.

	The two bars share an axis. The flight bar spans the whole journey and the
	programme bar spans the same seconds, so a landing line drawn across both
	means the same instant on each - which is the entire point of drawing them
	one above the other, and the reason the programme bar is measured in seconds
	rather than in items.
----------------------------------------------------------------------------]]

local ADDON, A = ...

A.IFEC = A.IFEC or {}
local Player = {}
A.IFEC.Player = Player

local W, Media, Palette = A.Widgets, A.Media, A.Palette
local Content, Playback, Taxi = A.IFEC.Content, A.IFEC.Playback, A.IFEC.Taxi

-- The design's player region. Sides match the header's, so the two read as one
-- window rather than as a panel with a panel in it.
local PAD_X, PAD_T, PAD_B = 16, 11, 14
local ROW_H     = 34          -- the now-playing row
local GLYPH     = 30          -- its channel mark
local BAR_H     = 7
local BAR_GAP   = 6           -- between the flight bar and the programme bar
local UPNEXT_H  = 26
local UPNEXT_MAX = 4          -- rows before the list stops growing the console

--- Channel colours, from the design's tints. Their own tokens rather than
--  borrowed ones: these say WHICH KIND of thing is playing, which is a
--  different job from any colour already in the palette.
local function tintFor(kind)
	local c = Palette.c
	if kind == "music"  then return c.ifecMusic end
	if kind == "gossip" then return c.ifecGossip end
	return c.ifecPodcast
end

local function clock(secs)
	if type(secs) ~= "number" then return "--:--" end
	if secs < 0 then secs = 0 end
	return string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
end

-- ---------------------------------------------------------------------------
-- construction
-- ---------------------------------------------------------------------------

local function BuildRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)

	row.glyph = row:CreateTexture(nil, "ARTWORK")
	row.glyph:SetSize(16, 16)
	row.glyph:SetPoint("LEFT", row, "LEFT", (GLYPH - 16) / 2, 0)

	row.title = W.Text(row, "ifecTitle", "LEFT", "OVERLAY")
	row.title:SetPoint("TOPLEFT", row, "TOPLEFT", GLYPH + 12, -1)

	row.meta = W.Text(row, "ifecMeta", "LEFT", "OVERLAY")
	row.meta:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)

	return row
end

local function BuildTransport(parent)
	local t = CreateFrame("Frame", nil, parent)
	t:SetSize(96, 34)

	local function mark(button, icon, size)
		button.glyph = button:CreateTexture(nil, "ARTWORK")
		button.glyph:SetSize(size, size)
		button.glyph:SetPoint("CENTER")
		Media:SetIcon(button.glyph, icon)
	end

	t.prev = CreateFrame("Button", nil, t)
	t.prev:SetSize(20, 20)
	t.prev:SetPoint("LEFT", t, "LEFT", 0, 0)
	mark(t.prev, "prev", 16)

	-- The one control with a surface behind it: it is the button people reach
	-- for without looking, and the design gives it a filled circle.
	t.toggle = W.CreateButton(t, { corner = 17 })
	t.toggle:SetSize(34, 34)
	t.toggle:SetPoint("CENTER", t, "CENTER", 0, 0)
	t.toggle:EnableMouse(true)
	mark(t.toggle, "play", 13)

	t.next = CreateFrame("Button", nil, t)
	t.next:SetSize(20, 20)
	t.next:SetPoint("RIGHT", t, "RIGHT", 0, 0)
	mark(t.next, "next", 16)

	return t
end

local function BuildUpNextRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(UPNEXT_H)

	row.grip = row:CreateTexture(nil, "ARTWORK")
	row.grip:SetSize(12, 12)
	row.grip:SetPoint("LEFT", row, "LEFT", 2, 0)
	Media:SetIcon(row.grip, "grip")

	row.glyph = row:CreateTexture(nil, "ARTWORK")
	row.glyph:SetSize(13, 13)
	row.glyph:SetPoint("LEFT", row.grip, "RIGHT", 8, 0)

	row.title = W.Text(row, "ifecUpNext", "LEFT", "OVERLAY")
	row.title:SetPoint("LEFT", row.glyph, "RIGHT", 9, 0)

	row.meta = W.Text(row, "ifecMeta", "RIGHT", "OVERLAY")
	row.meta:SetPoint("RIGHT", row, "RIGHT", -4, 0)

	return row
end

function Player:Build()
	if self.frame then return self.frame end

	local f = CreateFrame("Frame", nil, UIParent)
	f:Hide()

	f.now = BuildRow(f)
	f.now:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, -PAD_T)
	f.now:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_X - 104, -PAD_T)

	f.transport = BuildTransport(f)
	f.transport:SetPoint("RIGHT", f, "RIGHT", -PAD_X, 0)
	f.transport:SetPoint("TOP", f.now, "TOP", 0, 0)

	-- THE TWO BARS, ONE AXIS. Same width, same total, stacked.
	f.flight = W.CreateSegmentedBar(f, { height = BAR_H })
	f.flight:SetPoint("TOPLEFT", f.now, "BOTTOMLEFT", -0, -12)
	f.flight:SetPoint("RIGHT", f, "RIGHT", -PAD_X, 0)

	f.programme = W.CreateSegmentedBar(f, { height = BAR_H })
	f.programme:SetPoint("TOPLEFT", f.flight, "BOTTOMLEFT", 0, -BAR_GAP)
	f.programme:SetPoint("RIGHT", f.flight, "RIGHT", 0, 0)

	-- The landing line crosses both, which is the whole reason they share an
	-- axis: it is one instant, said once.
	f.landing = f:CreateTexture(nil, "OVERLAY")
	f.landing:SetWidth(2)
	f.landing:SetPoint("TOP", f.flight, "TOP", 0, 6)
	f.landing:SetPoint("BOTTOM", f.programme, "BOTTOM", 0, -2)

	f.landingLabel = W.Text(f, "ifecCaption", "RIGHT", "OVERLAY")
	f.landingLabel:SetPoint("BOTTOMRIGHT", f.landing, "TOPRIGHT", -3, 1)

	f.fills = W.Text(f, "ifecCaption", "LEFT", "OVERLAY")
	f.fills:SetPoint("TOPLEFT", f.programme, "BOTTOMLEFT", 0, -5)

	f.legend = W.Text(f, "ifecCaption", "RIGHT", "OVERLAY")
	f.legend:SetPoint("TOPRIGHT", f.programme, "BOTTOMRIGHT", 0, -5)

	-- UP NEXT, under its own rule.
	f.rule = f:CreateTexture(nil, "ARTWORK")
	f.rule:SetHeight(1)
	f.rule:SetPoint("TOPLEFT", f.fills, "BOTTOMLEFT", 0, -9)
	f.rule:SetPoint("TOPRIGHT", f.legend, "BOTTOMRIGHT", 0, -9)

	f.upNextLabel = W.Text(f, "ifecSection", "LEFT", "OVERLAY")
	f.upNextLabel:SetPoint("TOPLEFT", f.rule, "BOTTOMLEFT", 2, -6)
	f.upNextLabel:SetText("UP NEXT")

	f.rows = {}
	for i = 1, UPNEXT_MAX do
		local row = BuildUpNextRow(f)
		if i == 1 then
			row:SetPoint("TOPLEFT", f.upNextLabel, "BOTTOMLEFT", -2, -4)
		else
			row:SetPoint("TOPLEFT", f.rows[i - 1], "BOTTOMLEFT", 0, 0)
		end
		row:SetPoint("RIGHT", f, "RIGHT", -PAD_X, 0)
		f.rows[i] = row
	end

	-- PROGRAMME COMPLETE, which is the state v2 is designed around. One line
	-- and three chips, in place of everything above.
	f.done = W.Text(f, "ifecTitle", "LEFT", "OVERLAY")
	f.done:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, -PAD_T - 2)
	f.done:SetText("Programme complete.")
	f.done:Hide()

	f.chips = {}
	for i = 1, 3 do
		local chip = W.Pill(f, "ifecChip", { height = 24, padX = 13,
			frameType = "Button" })
		chip:EnableMouse(true)
		if i == 1 then
			chip:SetPoint("TOPLEFT", f.done, "BOTTOMLEFT", 0, -10)
		else
			chip:SetPoint("LEFT", f.chips[i - 1], "RIGHT", 8, 0)
		end
		chip:Hide()
		f.chips[i] = chip
	end

	self.frame = f
	self:Wire()
	return f
end

--- The controls, once.
function Player:Wire()
	local f = self.frame
	f.transport.prev:SetScript("OnClick", function() Playback:Previous() end)
	f.transport.next:SetScript("OnClick", function() Playback:Next() end)
	f.transport.toggle:SetScript("OnClick", function() Playback:Toggle() end)
end

-- ---------------------------------------------------------------------------
-- painting
-- ---------------------------------------------------------------------------

--- How tall the region wants to be in its current state.
function Player:Height()
	if self.complete then
		return PAD_T + 22 + 10 + 24 + PAD_B
	end
	local rows = math.min(#(self.queue or {}) - (self.at or 1), UPNEXT_MAX)
	if rows < 0 then rows = 0 end
	return PAD_T + ROW_H + 12 + BAR_H + BAR_GAP + BAR_H + 16 + 1
		+ 20 + rows * UPNEXT_H + PAD_B
end

function Player:Paint()
	local f = self.frame
	if not f then return end

	local flight = Taxi and Taxi.flight
	local total  = flight and flight.expected or 0
	local elapsed = flight and select(1, Taxi:Progress()) or 0

	-- THE FLIGHT BAR: one piece, filled as far as we have flown. Its legs are
	-- drawn as ticks over the top rather than as pieces, because a leg boundary
	-- is an instant and a piece is a duration.
	f.flight:SetPieces({ { seconds = total, colour = Palette.c.ifecDial, filled = true } }, total)

	-- THE PROGRAMME BAR: one piece per queued item, on the same axis. Played
	-- and playing are solid; queued is outlined.
	local pieces, filled = {}, 0
	for i, item in ipairs(self.queue or {}) do
		local secs = item.duration or 0
		pieces[#pieces + 1] = {
			seconds = secs,
			colour  = tintFor(item.type),
			filled  = i <= (self.at or 1),
		}
		filled = filled + secs
	end
	f.programme:SetPieces(pieces, total > 0 and total or filled)

	-- The landing line sits at the end of the flight, on both bars.
	f.landing:ClearAllPoints()
	f.landing:SetPoint("TOP", f.flight, "TOPLEFT", f.flight:XFor(total), 6)
	f.landing:SetPoint("BOTTOM", f.programme, "BOTTOMLEFT", f.flight:XFor(total), -2)
	f.landingLabel:SetText("LANDING " .. clock(total - elapsed))

	f.fills:SetText("programme fills " .. clock(filled) .. " of " .. clock(total))
	f.legend:SetText("outlined = queued")

	self:PaintNowPlaying()
	self:PaintUpNext()
end

function Player:PaintNowPlaying()
	local f = self.frame
	local item = Playback and Playback.item

	if not item then
		f.now.title:SetText("")
		f.now.meta:SetText("")
		return
	end

	Media:SetIcon(f.now.glyph, item.type)
	local tint = tintFor(item.type)
	f.now.glyph:SetVertexColor(tint[1], tint[2], tint[3])
	f.now.title:SetText(item.title or "")

	local left = (item.duration or 0) - (Playback:Elapsed() or 0)
	local nextItem = (self.queue or {})[(self.at or 1) + 1]
	local meta = clock(left) .. " left"
	if nextItem then meta = meta .. "  \194\183  then " .. (nextItem.title or "") end
	f.now.meta:SetText(meta)
	W.Color(f.now.meta, tint)

	Media:SetIcon(f.transport.toggle.glyph,
		Playback:IsPlaying() and "pause" or "play")
end

function Player:PaintUpNext()
	local f = self.frame
	local queue, at = self.queue or {}, self.at or 1

	for i, row in ipairs(f.rows) do
		local item = queue[at + i]
		if not item then
			row:Hide()
		else
			local tint = tintFor(item.type)
			Media:SetIcon(row.glyph, item.type)
			row.glyph:SetVertexColor(tint[1], tint[2], tint[3])
			row.title:SetText(item.title or "")

			-- "queued by you" is not a duration, and saying so is the whole
			-- point: a player pick is never overridden by auto-fill.
			if item.picked then
				row.meta:SetText("queued by you")
				W.Color(row.meta, Palette.c.textDim)
			else
				row.meta:SetText(clock(item.duration or 0) .. "  \194\183  auto")
				W.Color(row.meta, tint)
			end
			row:Show()
		end
	end
end

function Player:Restyle()
	local f = self.frame
	if not f then return end
	local c = Palette.c

	W.Color(f.now.title, c.text)
	W.Color(f.fills, c.textDim)
	W.Color(f.legend, c.textFaint)
	W.Color(f.upNextLabel, c.textDim)
	W.Color(f.done, c.text)

	f.landing:SetColorTexture(c.ifecLanding[1], c.ifecLanding[2], c.ifecLanding[3], 1)
	W.Color(f.landingLabel, c.ifecLanding)
	f.rule:SetColorTexture(c.glassEdge[1], c.glassEdge[2], c.glassEdge[3], 0.15)

	for _, row in ipairs(f.rows) do W.Color(row.title, c.text) end
	for _, t in ipairs({ f.transport.prev, f.transport.next }) do
		t.glyph:SetVertexColor(c.textDim[1], c.textDim[2], c.textDim[3], 0.85)
	end
	f.transport.toggle.glyph:SetVertexColor(c.text[1], c.text[2], c.text[3])
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

--- Decide whether there is a player region at all, and attach or detach.
--
--  DORMANCY IS ONE QUESTION. Three ways of having no content, one answer: the
--  region is absent rather than empty, and the console lays out as though it
--  were never there.
function Player:Refresh()
	local IF = A:GetModule("ifec")
	if not IF or not IF.frame then return end

	if not Content or Content:IsDormant() then
		if self.frame then IF:DetachRegion() end
		return
	end

	local f = self:Build()
	self:Restyle()
	self:Paint()
	IF:AttachRegion(f, self:Height())
end

--- Build a programme for this flight and start it.
function Player:OnBoard(flight)
	if not Content or Content:IsDormant() then return end

	local seconds = flight and flight.expected or 0
	local queue = Content:Programme(seconds, self.picks)
	self.queue, self.at, self.complete = queue, 1, nil

	self:Refresh()
	if Playback then Playback:Start(queue) end
end

function Player:OnLand()
	if Playback then Playback:Stop() end
	self.queue, self.at, self.complete = nil, nil, nil
	local IF = A:GetModule("ifec")
	if IF and IF.HasRegion and IF:HasRegion() then IF:DetachRegion() end
end

-- SELF-STARTING, in the same direction as everything else here: the player
-- listens to the flight, and the flight has never heard of the player.
--
-- The window in which content can appear or vanish is BETWEEN flights, which is
-- exactly when this asks - so a season starting, or a pack being installed and
-- reloaded, is picked up on the next boarding with no reload of ours.
if Taxi then
	Taxi:AddListener(function(event, flight)
		if event == "board" then
			Player:OnBoard(flight)
		else
			Player:OnLand()
		end
	end)
end

if Playback then
	Playback:AddListener(function(event, item, index)
		-- Whatever moved, the region says the same things about it.
		if event == "playing" or event == "segment" then
			for i, q in ipairs(Player.queue or {}) do
				if item and q.key == item.key then Player.at = i end
			end
		elseif event == "exhausted" then
			Player.complete = true
		end
		Player:Paint()
	end)
end
