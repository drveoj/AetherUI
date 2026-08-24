--[[--------------------------------------------------------------------------
	AetherUI :: IFEC library

	The drawer you pick from. Slides out from the side of the console and lists
	everything in season, grouped by the pack it came from.

	A SLIDE-OUT RATHER THAN A WINDOW, and a child of the console rather than of
	UIParent. Two reasons, and both of them are the interface being hidden: a
	window under UIParent would be drawn at zero alpha for the whole flight, and
	one anchored to the console but parented elsewhere would have to be moved,
	shown, hidden and scaled alongside it forever. As a child it inherits the
	lot, including the mover.

	The dependency points the same way everything else here does: this calls the
	console and the player region, and neither has heard of it. The flight timer
	works with this file absent.

	FRAME REUSE, not a frame per item. Five seasons of episodes and gossip is
	comfortably a hundred entries, and building a hundred frames when the drawer
	opens is a hitch at exactly the wrong moment.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
A.IFEC = A.IFEC or {}
local Library = {}
A.IFEC.Library = Library

local W, Media, Palette = A.Widgets, A.Media, A.Palette
local Glass = A.Glass
local Content, Playback, Registry = A.IFEC.Content, A.IFEC.Playback, A.IFEC.Registry

local WIDTH   = 300
local HEIGHT  = 320
local GAP     = 8              -- between the console and the drawer
-- THE SHARED NUMBERS. 15a gives one header height and one body padding
-- for every panel in the interface, and a window of ours is a panel like
-- any other - the only reason these were local was that they were written
-- before there was anywhere to put them.
local PAD_X   = W.PANEL_PAD
local PAD_T   = W.PANEL_PAD
local PAD_B   = W.PANEL_PAD
local ROW_H   = 30
local HEAD_H  = 20             -- a season heading
local TAB_H   = 22
local SCROLL_STEP = ROW_H * 2

-- The three channels, in the design's order. `word` is what the filter says;
-- the glyph is the same one the now-playing row uses, so a row and its filter
-- are unmistakably the same kind of thing.
local KINDS = {
	{ key = "podcast", word = "Stories" },
	{ key = "music",   word = "Music" },
	{ key = "gossip",  word = "Gossip" },
}

local function tintFor(kind)
	local c = Palette.c
	if kind == "music"  then return c.ifecMusic end
	if kind == "gossip" then return c.ifecGossip end
	return c.ifecPodcast
end

local function clock(secs)
	if type(secs) ~= "number" or secs <= 0 then return "" end
	return string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
end

-- ---------------------------------------------------------------------------
-- construction
-- ---------------------------------------------------------------------------

local function BuildHeading(parent)
	local h = CreateFrame("Frame", nil, parent)
	h:SetHeight(HEAD_H)
	h.text = W.Text(h, "ifecSection", "LEFT", "OVERLAY")
	h.text:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 2, 3)
	return h
end

local function BuildRow(parent)
	local row = W.CreateButton(parent, { corner = 6, fill = "glass" })
	row:SetHeight(ROW_H)
	row:EnableMouse(true)

	row.glyph = row:CreateTexture(nil, "OVERLAY")
	row.glyph:SetSize(12, 12)
	row.glyph:SetPoint("LEFT", row, "LEFT", 8, 0)

	row.meta = W.Text(row, "ifecCaption", "RIGHT", "OVERLAY")
	row.meta:SetPoint("RIGHT", row, "RIGHT", -8, 0)

	-- Stops where the duration starts rather than running underneath it. A
	-- title is as long as its author made it.
	row.title = W.Text(row, "ifecUpNext", "LEFT", "OVERLAY")
	row.title:SetPoint("LEFT", row.glyph, "RIGHT", 8, 0)
	row.title:SetPoint("RIGHT", row.meta, "LEFT", -8, 0)
	row.title:SetWordWrap(false)

	row:HookScript("OnEnter", function(self)
		W.SetButtonState(self, self.__aetherSelected, true)
	end)
	row:HookScript("OnLeave", function(self)
		W.SetButtonState(self, self.__aetherSelected, false)
	end)
	row:SetScript("OnClick", function(self)
		if self.item then Library:Toggle(self.item) end
	end)

	return row
end

--- One of the drawer's filters. A TAB, not a button: it changes which of the
--- library you are looking at rather than doing anything, and the interface
--- draws that distinction the same way everywhere now - see W.Tab.
local function BuildTab(parent, kind, rail)
	local t = CreateFrame("Button", nil, parent)
	t:SetHeight(TAB_H)
	t:EnableMouse(true)
	t.kind = kind

	t.label = W.Text(t, "ifecCaption", "CENTER", "OVERLAY")
	t.label:SetPoint("CENTER", t, "CENTER", 0, 0)

	-- Its rail is above the list it filters, so the line and the mark are on
	-- the bottom - the edge facing the thing they switch. The rail is handed
	-- over rather than looked up: nothing here promises a tab is a child of
	-- the frame that owns its rail, and on the spellbook it is not.
	W.Tab(t, { edge = "TOP", label = t.label, rail = rail })
	t:SetScript("OnClick", function(self)
		Library.filter = self.kind
		Library:Paint()
	end)

	return t
end

function Library:Build(host)
	if self.frame then return self.frame end
	if not host then return nil end

	local f = Glass.CreatePanel(host, { corner = 20, fill = "glassStrong",
		edge = "glassEdge" })
	f:SetSize(WIDTH, HEIGHT)
	f:EnableMouse(true)          -- swallow clicks; do not click the world through it
	f:Hide()

	f.title = W.Text(f, "ifecSection", "LEFT", "OVERLAY")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, -PAD_T)
	f.title:SetText(L.library.build.library)

	f.count = W.Text(f, "ifecCaption", "RIGHT", "OVERLAY")
	f.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_X, -PAD_T + 1)

	-- THE FILTERS, LEFT-ALIGNED, one per channel that has anything in it - plus
	-- All once there is more than one. A tab onto an empty list is worse than no
	-- tab, and with a single channel installed the whole row says nothing the
	-- list does not already say, so it is not built at all.
	-- The rail they stand on, above the list they filter - so its line and
	-- their marks are on its bottom, the edge facing that list.
	f.rail = W.TabRail(f, "TOP")
	f.rail:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", -2, -8)
	f.rail:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_X, -(PAD_T + 18 + 8))
	f.rail:SetHeight(TAB_H)

	f.tabs = {}
	for i, kind in ipairs({ "all", "podcast", "music", "gossip" }) do
		local t = BuildTab(f, kind, f.rail)
		if i == 1 then
			t:SetPoint("BOTTOMLEFT", f.rail, "BOTTOMLEFT", 0, 0)
		else
			t:SetPoint("BOTTOMLEFT", f.tabs[i - 1], "BOTTOMRIGHT", 0, 0)
		end
		f.tabs[i] = t
	end

	-- Two: this drawer is narrow and its list already sits ten from the
	-- edge, so a deeper recess would put its rim through the frame's rim.
	f.list = W.Scroller(f, SCROLL_STEP, { outset = 2 })
	f.list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD_X - 4), PAD_B)

	f.rows     = W.Pool(function() return BuildRow(f.list.child) end)
	f.headings = W.Pool(function() return BuildHeading(f.list.child) end)

	-- A BROWSE LIST SHOWING NOTHING IS WORSE THAN NO BROWSE LIST, which is the
	-- brief's phrase. It cannot happen from dormancy - the control that opens
	-- this is not there when there is no content - but a filter can empty it.
	f.empty = W.Text(f, "ifecCaption", "CENTER", "OVERLAY")
	f.empty:SetPoint("CENTER", f.list, "CENTER", 0, 0)
	f.empty:Hide()

	self.frame = f
	self.filter = self.filter or "all"
	self:Restyle()
	return f
end

-- ---------------------------------------------------------------------------
-- what is in the queue
-- ---------------------------------------------------------------------------

--- Add it to the programme, or take it back out.
--
--  The queue rules live on Playback, because there are two surfaces looking at
--  one queue now and "what may be taken out of a queue" does not change with
--  who is looking. This is the part that is the library's own: what a click
--  MEANS here, which includes starting something when nothing is playing.
function Library:Toggle(item)
	if not Playback then return false end

	-- GOSSIP IS READ, NOT PLAYED. It has no audio and no duration, so it never
	-- enters a running order - it opens beside the list instead, and the music
	-- carries on underneath it, which is the entire point of the thing.
	if item and item.type == "gossip" then
		local Reader = A.IFEC.Reader
		if not Reader then return false end
		Reader:Open(item)
		self:Paint()
		return true
	end

	local did = Playback:Pick(item)
	if not did then return false end

	local Player = A.IFEC.Player
	if did == "added" then
		if Player and Player.complete then
			-- A programme that had already run out has something to play again.
			Player.complete = nil
			Player:Refresh()
			Playback:PlayAt(#Playback.queue)
		elseif Playback.state ~= "playing" and Playback.state ~= "paused" then
			-- ON THE GROUND, a click IS the play button. Queueing something into
			-- silence and leaving it silent is a list that looks broken.
			Playback.stopped = nil
			Playback:PlayAt(#Playback.queue)
		end
	end

	if Player then Player:Paint() end
	self:Paint()
	return true
end

-- ---------------------------------------------------------------------------
-- painting
-- ---------------------------------------------------------------------------

--- Everything in season, grouped by pack, newest season first.
--
--  The same direction the programme fills in, so the top of this list is what
--  the console would have reached for anyway.
local function grouped()
	if not Content or not Registry then return {} end

	local byPack, order = {}, {}
	for _, item in ipairs(Content:Available()) do
		if not byPack[item.packId] then
			byPack[item.packId] = {}
			order[#order + 1] = item.packId
		end
		local list = byPack[item.packId]
		list[#list + 1] = item
	end

	table.sort(order, function(a, b)
		local pa, pb = Registry.packs[a], Registry.packs[b]
		local sa, sb = pa and pa.seasonIndex or 0, pb and pb.seasonIndex or 0
		if sa ~= sb then return sa > sb end
		return a < b
	end)

	local out = {}
	for _, packId in ipairs(order) do
		local pack = Registry.packs[packId]
		out[#out + 1] = {
			name  = pack and pack.displayName or packId,
			items = byPack[packId],
		}
	end
	return out
end

--- Which channels are actually installed, so the filter row can say only what
--  is true.
local function kindsPresent()
	local seen, n = {}, 0
	for _, item in ipairs(Content and Content:Available() or {}) do
		if not seen[item.type] then seen[item.type] = true n = n + 1 end
	end
	return seen, n
end

function Library:PaintTabs()
	local f = self.frame
	local seen, n = kindsPresent()

	-- ONE CHANNEL IS NO CHOICE. With music alone the row would be "All" and
	-- "Music" side by side, which are the same list twice.
	--
	-- The list takes the room back rather than leaving a gap where a filter row
	-- would have been, which is why the top anchor is set here and not once at
	-- build time.
	local top = PAD_T + 18 + 8
	if n < 2 then
		for _, t in ipairs(f.tabs) do t:Hide() end
		f.rail:Hide()
		self.filter = "all"
	else
		f.rail:Show()
		top = top + TAB_H + 8
	end
	f.list:ClearAllPoints()
	f.list:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X - 4, -top)
	f.list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD_X - 4), PAD_B)
	if n < 2 then return false end

	local prev
	for _, t in ipairs(f.tabs) do
		local show = t.kind == "all" or seen[t.kind]
		t:SetShown(show)
		if not show then
			if self.filter == t.kind then self.filter = "all" end
		else
			local word = "All"
			for _, k in ipairs(KINDS) do
				if k.key == t.kind then word = k.word end
			end
			t.label:SetText(word)
			t:SetWidth(math.ceil(t.label:GetStringWidth() or 0) + 20)

			-- Re-anchored to the last one SHOWING, so a hidden channel closes
			-- the gap rather than leaving a hole in the row.
			t:ClearAllPoints()
			if prev then
				t:SetPoint("LEFT", prev, "RIGHT", 4, 0)
			else
				t:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", -2, -8)
			end
			prev = t

			t.__aetherSelected = (self.filter == t.kind) or nil
			W.TabState(t, t.__aetherSelected, false)
		end
	end
	return true
end

function Library:Paint()
	local f = self.frame
	if not f then return end

	local c = Palette.c
	-- What is SOUNDING, not merely what the queue index points at. With nothing
	-- playing there is no current item, and a row that called itself "playing"
	-- in silence would be the console insisting again.
	local nowKey = (Playback and (Playback.state == "playing"
		or Playback.state == "paused") and Playback.item) and Playback.item.key or nil

	self:PaintTabs()

	local y, rows, heads, shown = 0, 0, 0, 0
	for _, group in ipairs(grouped()) do
		-- The heading is drawn only if something under it survives the filter,
		-- so a season of stories does not leave an empty title behind on the
		-- music tab.
		local wanted = {}
		for _, item in ipairs(group.items) do
			if self.filter == "all" or item.type == self.filter then
				wanted[#wanted + 1] = item
			end
		end
		if #wanted > 0 then
			heads = heads + 1
			local h = f.headings:Get(heads)
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", f.list.child, "TOPLEFT", 4, -y)
			h:SetPoint("TOPRIGHT", f.list.child, "TOPRIGHT", -4, -y)
			h.text:SetText(group.name:upper())
			W.Color(h.text, c.textFaint)
			h:Show()
			y = y + HEAD_H

			for _, item in ipairs(wanted) do
				rows = rows + 1
				shown = shown + 1
				local row = f.rows:Get(rows)
				row.item = item
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", f.list.child, "TOPLEFT", 0, -y)
				row:SetPoint("TOPRIGHT", f.list.child, "TOPRIGHT", 0, -y)

				local tint = tintFor(item.type)
				Media:SetIcon(row.glyph, item.type)
				row.glyph:SetVertexColor(tint[1], tint[2], tint[3])

				-- The artist belongs to the title here. There is no second line
				-- to put it on and "Big Drum Deep Water" alone is half a name.
				local label = item.title or ""
				if item.artist and item.artist ~= "" then
					label = label .. "  \194\183  " .. item.artist
				end
				row.title:SetText(label)

				-- AHEAD, NOT ANYWHERE IN THE QUEUE. The queue keeps what has
				-- already run so the programme bar can draw it as a timeline, so a
				-- track you skipped past was still "in the queue" - drawn filled,
				-- refusing to be clicked: a toggle stuck on with no way to clear it.
				local ahead = Playback and Playback:Ahead(item)
				local progress = Content and Content:Progress(item.key)
				local playing = item.key == nowKey

				if item.type == "gossip" then
					-- Read, not played. It has no place in a running order and no
					-- duration to put here; what it has is how far through it you
					-- are, which is the same fact an episode keeps and is kept in
					-- the same field.
					local pages = #(item.pages or {})
					local read = progress and progress.complete
					local at = progress and progress.segment or 0
					if read then
						row.meta:SetText(L.library.paint.read)
					elseif at > 0 then
						row.meta:SetText(A.F(L.library.paint.page_d_d, at, pages))
					else
						row.meta:SetText(A.F(L.library.paint.d_pages, pages))
					end
					W.Color(row.meta, read and c.textFaint or tint)
				elseif playing then
					row.meta:SetText(L.library.paint.playing)
					W.Color(row.meta, tint)
				elseif ahead then
					row.meta:SetText(L.library.paint.queued)
					W.Color(row.meta, tint)
				elseif progress and progress.complete then
					row.meta:SetText("heard  \194\183  " .. clock(item.duration))
					W.Color(row.meta, c.textFaint)
				else
					row.meta:SetText(clock(item.duration))
					W.Color(row.meta, c.textFaint)
				end

				-- COMING UP IS THE SELECTED STATE, drawn filled - the same signal a
				-- selected tab makes, said once in SetButtonState. Gossip is never
				-- selected: it is a thing you open, not a thing you cue.
				row.__aetherSelected = (item.type ~= "gossip"
					and (ahead ~= nil or playing)) or nil
				W.SetButtonState(row, row.__aetherSelected, false)
				if not row.__aetherSelected then W.Color(row.title, c.text) end
				row:Show()
				y = y + ROW_H
			end
		end
	end

	f.rows:HideFrom(rows + 1)
	f.headings:HideFrom(heads + 1)
	f.list.child:SetHeight(math.max(y, 1))
	f.list.child:SetWidth(f.list:GetWidth() or WIDTH)
	f.list:Clamp()

	f.empty:SetShown(shown == 0)
	if shown == 0 then f.empty:SetText(L.library.paint.nothing_kind_season) end
	f.count:SetText(shown > 0 and (shown .. (shown == 1 and " item" or " items")) or "")
end

function Library:Restyle()
	local f = self.frame
	if not f then return end
	local c = Palette.c
	-- A READING FILL, not the control-surface one: a column of titles read over
	-- whatever the world is doing behind it, which is the same argument the
	-- quest log and the chat log make - at the opacity a button uses, the
	-- clutter behind competes with every line.
	--
	-- HERE AND NOWHERE ELSE. Build calls this, and a restyle is what changes the
	-- skin underneath - so setting it at construction as well was a second owner
	-- for one fact, and either could be deleted with nothing noticing.
	f:SetFillColor(Palette:ReadingFill())
	W.Color(f.title, c.textDim)
	W.Color(f.count, c.textFaint)
	W.Color(f.empty, c.textFaint)
end

-- ---------------------------------------------------------------------------
-- opening and closing
-- ---------------------------------------------------------------------------

--- Hang the drawer off `host`, wherever that is.
--
--  TWO SURFACES CAN OPEN THIS: the console in flight and the mini-player on the
--  Toolbox. A child of whichever asked, rather than a window of its own, so it
--  inherits that host's scale, its mover and - in the console's case - the fact
--  that it lives outside UIParent and survives the interface being hidden.
--
--  MEASURED EVERY TIME IT OPENS, not once. A host is a thing somebody drags: a
--  drawer that decided its side at build time hung off the edge of the screen
--  the first time the console went to the right of the middle.
function Library:Place(host)
	local f = self.frame
	if not f or not host then return end

	if f:GetParent() ~= host then f:SetParent(host) end

	-- Above the host's own surface. A glass panel is a sibling frame and frames
	-- sort by level rather than by draw layer, so this is the difference between
	-- a drawer and a drawer drawn underneath the thing it came out of.
	if host.GetFrameLevel then
		f:SetFrameLevel((host:GetFrameLevel() or 0) + 10)
	end

	f:ClearAllPoints()

	-- WHICH WAY IS THE HOST'S TO SAY, when it knows. "Beside the host" is only
	-- right while the host sits at a screen edge with open screen next to it -
	-- which is true of the console, and of the Toolbox docked as a column. With
	-- the Toolbox docked ACROSS THE TOP the mini-player is one column of a wide
	-- strip, and beside it is the middle of that strip: the list opened over the
	-- settings tiles it had come out from under.
	--
	-- The Toolbox knows which edge it is on and nothing here can work it out, so
	-- it says. Anything that does not say gets the old rule, which is right for
	-- everything that is not in a strip.
	local from = host.__aetherLibraryFrom
	if from == "BELOW" then
		f:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, -GAP)
		return
	elseif from == "ABOVE" then
		f:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", 0, GAP)
		return
	elseif from == "LEFT" then
		f:SetPoint("BOTTOMRIGHT", host, "BOTTOMLEFT", -GAP, 0)
		return
	elseif from == "RIGHT" then
		f:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", GAP, 0)
		return
	end

	local mid  = (host:GetLeft() or 0) + (host:GetWidth() or 0) / 2
	local room = (UIParent:GetWidth() or 0) / 2

	-- Top-aligned with a tall host, bottom-aligned with a short one. The
	-- mini-player is two lines at the foot of the Toolbox and a drawer hung from
	-- ITS top would be a 320-tall panel starting an inch off the bottom of the
	-- screen.
	local tall = (host:GetHeight() or 0) >= HEIGHT
	local mine = tall and "TOP" or "BOTTOM"

	if mid > room then
		f:SetPoint(mine .. "RIGHT", host, mine .. "LEFT", -GAP, 0)
	else
		f:SetPoint(mine .. "LEFT", host, mine .. "RIGHT", GAP, 0)
	end
end

function Library:IsOpen()
	return self.frame ~= nil and self.frame:IsShown()
end

--- `host` is the frame the drawer hangs off. Remembered, so a repaint or a
--  re-place does not need telling again.
function Library:SetOpen(on, host)
	if on then
		host = host or self.host
		local f = self:Build(host)
		if not f then return false end
		self.host = host
		self:Place(host)
		self:Paint()
		f:Show()
	elseif self.frame then
		self.frame:Hide()
	end
	return true
end

function Library:ToggleOpen(host)
	return self:SetOpen(not self:IsOpen(), host)
end

--- Shut it and forget the filter. Called when whatever opened it goes away.
--- THE PAPER STAYS. It came out of this list, but it is a window of its own
--  now rather than a panel hanging off one - and reading a magazine while the
--  Toolbox is shut and the music carries on is the whole reason it takes no
--  time. It was closed with the list while it was still a panel beside it.
function Library:Close()
	self.filter = "all"
	if self.frame then self.frame:Hide() end
end

--- Shut it only if THIS host is the one it is hanging off.
--
--  The console closing must not shut a drawer the Toolbox opened, and the other
--  way round. Landing fires the console's close whether or not it ever had one.
function Library:CloseFor(host)
	if self.host and self.host ~= host then return false end
	self:Close()
	return true
end
