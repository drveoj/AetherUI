--[[--------------------------------------------------------------------------
	AetherUI :: QuestTracker

	The glass panel from concept 2a: a letter-spaced QUESTS heading with the log
	count on the right, then a row per tracked quest - a difficulty-tinted level
	chip, the title, objective lines, and a hairline progress bar - and the whole
	thing folds down to just the heading when you enter combat.

	The chip is the quest log's own widget and the quest log's own band colours,
	because the two lists are read together and one difficulty scheme drawn two
	ways is worse than either way on its own.

	Quest API on Classic Era
	------------------------
	All of it is the legacy global API; C_QuestLog is Retail's replacement and is
	not here. The one shape worth writing down, because it differs from every
	other flavour and is the thing that silently breaks if you assume Retail:

	  title, level, questTag, isHeader, isCollapsed, isComplete, frequency, questID
	      = GetQuestLogTitle(index)

	Eight returns, with questID last. That is not inferred from the wiki - it is
	how RXPGuides and Questie call it on this client, and questID was only added
	to that signature in 3.3.0, which is why Retail's ordering is different.

	  numEntries, numQuests = GetNumQuestLogEntries()
	  n                     = GetNumQuestLeaderBoards(index)
	  text, type, finished  = GetQuestLogLeaderBoard(objective, index)

	Note that log *indices* are not stable: accepting or abandoning a quest
	renumbers everything below it, and headers occupy indices too. So nothing
	here holds an index across a frame. The tracked set is keyed by questID and
	indices are resolved fresh on every scan.

	Why we keep our own tracked list
	--------------------------------
	Blizzard's watch list is capped - five quests, and shift-clicking a sixth in
	the quest log just fails. Rather than invent a new gesture, we let Blizzard
	take the shift-click, then adopt whatever landed in its list and clear it
	again on the next scan. Its five slots are therefore always empty, always
	available, and the list we actually draw from has no cap at all.

	The set lives in the *character* scope, not the profile: a quest log is per
	character, and sharing tracked quest IDs across an alt would be noise.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local QT = A:NewModule("questtracker")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- Panel geometry. The deck draws a 268x128 panel with type at 20/16 in from the
-- corner and rows on a 21px rhythm; these are those numbers.
local PAD_X, PAD_TOP, PAD_BOTTOM = 18, 14, 14
local HEADER_H  = 22
local ROW_GAP   = 10
local TITLE_H   = 16
-- The level chip. A point shorter than the quest log's 30x17 so it sits inside
-- the 16px title line rather than pushing the row rhythm out, and two narrower
-- to match, this panel being a third of the log's width.
local CHIP_W, CHIP_H = 28, 16
local CHIP_GAP  = 8
local LINE_H    = 14
local BAR_H     = 3
local BAR_GAP   = 5

-- ---------------------------------------------------------------------------
-- quest log adapter
-- ---------------------------------------------------------------------------

local function NumEntries()
	if not GetNumQuestLogEntries then return 0, 0 end
	local entries, quests = GetNumQuestLogEntries()
	return entries or 0, quests or 0
end

--- title, level, isHeader, isComplete, questID
local function LogTitle(index)
	if not GetQuestLogTitle then return nil end
	local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(index)
	if not title then return nil end

	-- questID is the eighth return here, but GetQuestIDFromLogIndex exists too
	-- and is what Blizzard's own Classic tracker uses. Either will do; take
	-- whichever answers, so a client that reorders the tuple still tracks.
	if not questID and GetQuestIDFromLogIndex then
		local ok, id = pcall(GetQuestIDFromLogIndex, index)
		if ok then questID = id end
	end

	return title, level, isHeader, isComplete, questID
end

--- Which of the five difficulty bands this quest's level falls in.
--
--  Difficulty is the fastest read on a quest list - grey means stop bothering,
--  red means come back later - and a tracker that threw that away would be
--  poorer for it. But it is carried by the *level chip*, exactly as the quest
--  log carries it, rather than by tinting the title: five colours of body text
--  stacked up the side of the screen is a list you have to decode, and the title
--  is the thing you are actually reading.
--
--  Delegated to the quest log rather than reimplemented. The two are on screen
--  together and a threshold that drifted between them would show the same quest
--  in two colours at once. QuestLog.lua loads AFTER this file, so it is resolved
--  per call rather than captured up top; the fallback is the neutral band, which
--  is what an unknown level gets in the log as well.
local function DifficultyBand(level)
	local QL = A:GetModule("questlog")
	if QL and QL.DifficultyBand then return QL.DifficultyBand(level) end
	return "difficult"
end

--- Objective lines plus a completion fraction.
--
--  The fraction prefers the numbers inside the objective text ("Empty Keg: 3/5")
--  over a simple finished/total count, because a kill quest that wants ten
--  boars should not sit at 0% until the tenth one dies.
local function Objectives(index)
	local lines, done, total = {}, 0, 0

	local n = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(index) or 0
	for j = 1, n do
		local text, _, finished = GetQuestLogLeaderBoard(j, index)
		if text then
			lines[#lines + 1] = { text = text, finished = finished and true or false }
			local cur, max = string.match(text, "(%d+)%s*/%s*(%d+)")
			if cur and max and tonumber(max) > 0 then
				done, total = done + math.min(tonumber(cur), tonumber(max)), total + tonumber(max)
			else
				done, total = done + (finished and 1 or 0), total + 1
			end
		end
	end

	return lines, (total > 0) and (done / total) or nil
end

-- ---------------------------------------------------------------------------
-- what counts as tracked
--
-- Two modes, and the default is the one Questie uses, because it is the only
-- one that is uncapped by construction rather than by trickery:
--
--   autoTrack  every quest in the log is shown, and `untracked` is a blacklist
--              of the ones you have dismissed. A new quest appears on its own;
--              there is no gesture to learn and no list to overflow.
--   manual     nothing is shown until you say so, and `tracked` is a whitelist.
--
-- Questie keeps exactly this pair - db.char.AutoUntrackedQuests alongside
-- db.char.TrackedQuests - and prunes both against the live quest log so they
-- cannot grow without bound. Same here, and for the same reason.
--
-- Both sets live in the *character* scope. A quest log belongs to a character,
-- and sharing tracked IDs with an alt would be noise.
-- ---------------------------------------------------------------------------

local EMPTY = {}

local function Sets()
	if not A.db or not A.db.char then return EMPTY, EMPTY end
	A.db.char.tracked = A.db.char.tracked or {}
	A.db.char.untracked = A.db.char.untracked or {}
	return A.db.char.tracked, A.db.char.untracked
end

local function AutoMode()
	return A.Config:Module("questtracker").autoTrack ~= false
end

local function IsTracked(questID)
	local tracked, untracked = Sets()
	if AutoMode() then return not untracked[questID] end
	return tracked[questID] and true or false
end

local function SetTracked(questID, on)
	local tracked, untracked = Sets()
	if AutoMode() then
		untracked[questID] = (not on) or nil
	else
		tracked[questID] = on or nil
	end
end

QT.IsTracked, QT.SetTracked = IsTracked, SetTracked

--- Move Blizzard's watch list into our whitelist, and empty it again.
--
--  Manual mode only. Blizzard caps its list at five, so shift-clicking a sixth
--  quest in the log simply fails - taking the entries and handing the slots back
--  is what keeps that gesture working past five. It is also a side effect on
--  someone else's state, which is why auto mode (the default) never does it:
--  there, nothing needs a gesture in the first place.
--
--  Iterating downward matters: RemoveQuestWatch renumbers the list under us, so
--  walking up would skip every other entry.
local function AdoptWatches()
	local cfg = A.Config:Module("questtracker")
	if AutoMode() or not cfg.adoptWatches then return end
	if not GetNumQuestWatches or not GetQuestIndexForWatch then return end

	local tracked = Sets()
	for i = GetNumQuestWatches(), 1, -1 do
		local index = GetQuestIndexForWatch(i)
		if index then
			local _, _, _, _, questID = LogTitle(index)
			if questID then tracked[questID] = true end
			if RemoveQuestWatch then pcall(RemoveQuestWatch, index) end
		end
	end
end

--- Tracked quests that are actually in the log right now, in log order.
--
--  Log order is zone order, so the rows come out grouped by zone for free.
local function Collect()
	local out, seen = {}, {}

	local entries, quests = NumEntries()
	for index = 1, entries do
		local title, level, isHeader, isComplete, questID = LogTitle(index)
		if title and not isHeader and questID then
			seen[questID] = true
			if IsTracked(questID) then
				local lines, pct = Objectives(index)
				local complete = (isComplete == 1) or (isComplete == true)
					or (pct ~= nil and pct >= 1)
				-- A quest with no objectives is a "go and talk to someone" quest.
				-- It gets no bar at all rather than one pinned at zero: an empty
				-- track reads as "no progress made", which is the wrong story for
				-- a quest that has no progress to make.
				if pct == nil and complete then pct = 1 end
				-- Say it in words as well as in colour. An objective-less quest
				-- that is ready to hand in has nothing else to show at all, and
				-- "all my objectives read 10/10" is a slower read than "Complete".
				if complete then
					lines[#lines + 1] = { text = "Complete", finished = true, done = true }
				end
				out[#out + 1] = {
					index = index, questID = questID, title = title, level = level,
					lines = lines, pct = pct, complete = complete,
					band = DifficultyBand(level),
				}
			end
		end
	end

	-- Forget IDs that are no longer in the log at all - turned in, abandoned, or
	-- belonging to another character. Left alone either set would grow forever.
	--
	-- But NOT while any zone header is collapsed. A collapsed header's quests are
	-- not in the log at all, so `seen` is missing them and the prune would read
	-- "hidden" as "gone" and delete them from the saved variables: in auto mode
	-- dismissed quests come back, and in whitelist mode tracked quests stop being
	-- tracked, permanently and with no message. The player collapsing a zone in
	-- Blizzard's log is enough to trigger it.
	local anyCollapsed = false
	for index = 1, entries do
		local _, _, _, isHeader, isCollapsed = GetQuestLogTitle(index)
		if isHeader and isCollapsed then anyCollapsed = true break end
	end

	if entries > 0 and not anyCollapsed then
		local tracked, untracked = Sets()
		for questID in pairs(tracked) do
			if not seen[questID] then tracked[questID] = nil end
		end
		for questID in pairs(untracked) do
			if not seen[questID] then untracked[questID] = nil end
		end
	end

	return out, quests
end

QT.Collect = Collect

-- ---------------------------------------------------------------------------
-- Blizzard frame removal
-- ---------------------------------------------------------------------------

function QT:HideBlizzard()
	local cfg = A.Config:Module("questtracker")
	if not cfg.hideBlizzard then return end
	for _, name in ipairs({ "QuestWatchFrame", "ObjectiveTrackerFrame" }) do
		local f = _G[name]
		if f and not (f.IsForbidden and f:IsForbidden()) then
			pcall(f.Hide, f)
			if f.HookScript and not f.__aetherHooked then
				f.__aetherHooked = true
				pcall(f.HookScript, f, "OnShow", function(self) self:Hide() end)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- context menu
--
-- Hand-rolled rather than UIDropDownMenu. Partly because a glass menu is the
-- house style and Blizzard's is not, but mostly because EasyMenu has been
-- removed on some flavours and a menu that silently does not open is a worse
-- failure than one we own outright.
-- ---------------------------------------------------------------------------

local MENU_W, MENU_ROW = 150, 22

local function BuildMenu()
	local closer = CreateFrame("Frame", nil, UIParent)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:EnableMouse(true)
	closer:Hide()

	-- `dialogFill`, not glass, for the reason the palette gives that token: a
	-- surface you have to READ must not be frosted-on-frosted. This one opens
	-- directly on top of the tracker's own panel, so at the control-surface
	-- opacity it was two translucent layers over a lit world and the item text
	-- had to compete with the quest titles showing through it. The abandon
	-- confirmation and the log's search box already sit on this same surface, so
	-- the menu now matches them rather than being a third treatment.
	--
	-- `glassEdgeHi` with it: the brighter rim is what separates a pop-over from
	-- the panel underneath, and an opaque fill inside a dim rim reads as a hole.
	local menu = Glass.CreatePanel(UIParent, {
		corner = 8, shadow = A.db.profile.glass.shadow,
		fill = "dialogFill", edge = "glassEdgeHi",
	})
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(closer:GetFrameLevel() + 10)
	menu:SetWidth(MENU_W)
	menu:Hide()

	closer:SetScript("OnMouseDown", function()
		menu:Hide()
		closer:Hide()
	end)
	menu:SetScript("OnHide", function() closer:Hide() end)

	menu.closer = closer
	menu.items = {}
	return menu
end

local function MenuItem(menu, i)
	local item = menu.items[i]
	if item then return item end

	item = CreateFrame("Button", nil, menu)
	item:SetHeight(MENU_ROW)
	item:SetPoint("LEFT", menu, "LEFT", 6, 0)
	item:SetPoint("RIGHT", menu, "RIGHT", -6, 0)

	local hl = item:CreateTexture(nil, "BACKGROUND")
	hl:SetTexture(Media.texture.flat)
	hl:SetAllPoints(item)
	hl:Hide()
	item.hl = hl

	item.text = W.Text(item, "questLine", "LEFT")
	item.text:SetPoint("LEFT", item, "LEFT", 8, 0)

	item:SetScript("OnEnter", function(self) self.hl:Show() end)
	item:SetScript("OnLeave", function(self) self.hl:Hide() end)
	item:SetScript("OnClick", function(self)
		menu:Hide()
		if self.action then self.action() end
	end)

	menu.items[i] = item
	return item
end

--- entries: { { text = "...", action = fn, danger = bool }, ... }
local function ShowMenu(anchor, entries)
	QT.menu = QT.menu or BuildMenu()
	local menu = QT.menu
	local c = Palette.c

	local shown = 0
	for _, e in ipairs(entries) do
		shown = shown + 1
		local item = MenuItem(menu, shown)
		item.text:SetText(e.text)
		W.Color(item.text, e.danger and c.danger or c.text)
		item.hl:SetVertexColor(c.accent[1], c.accent[2], c.accent[3], 0.18)
		item.action = e.action
		item:ClearAllPoints()
		item:SetPoint("LEFT", menu, "LEFT", 6, 0)
		item:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
		item:SetPoint("TOP", menu, "TOP", 0, -(6 + (shown - 1) * MENU_ROW))
		item:Show()
	end
	for i = shown + 1, #menu.items do menu.items[i]:Hide() end

	menu:SetHeight(12 + shown * MENU_ROW)
	menu:SetScale(A.db.profile.scale)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 6, -2)
	menu.closer:Show()
	menu:Show()
end

-- ---------------------------------------------------------------------------
-- row actions
-- ---------------------------------------------------------------------------

local function Untrack(questID)
	SetTracked(questID, false)
	QT:Refresh()
end

local function OpenLog(index)
	if QuestLog_OpenToQuest then
		if pcall(QuestLog_OpenToQuest, index) then return end
	end
	if SelectQuestLogEntry then pcall(SelectQuestLogEntry, index) end
	if ShowUIPanel and _G.QuestLogFrame then
		pcall(ShowUIPanel, _G.QuestLogFrame)
	elseif ToggleQuestLog then
		pcall(ToggleQuestLog)
	end
end

local function ShareQuest(index)
	if SelectQuestLogEntry then pcall(SelectQuestLogEntry, index) end
	if QuestLogPushQuest then pcall(QuestLogPushQuest) end
end

--- Abandon goes through Blizzard's own confirmation, never straight to
--  AbandonQuest. Losing a quest chain to a stray click in a tracker is not a
--  thing this addon is going to be responsible for.
local function AbandonQuestAt(index, title)
	if not SelectQuestLogEntry or not StaticPopup_Show then
		A:Print("can't abandon from here on this client - use the quest log.")
		return
	end
	pcall(SelectQuestLogEntry, index)
	if SetAbandonQuest then pcall(SetAbandonQuest) end
	if not pcall(StaticPopup_Show, "ABANDON_QUEST", title) then
		A:Print("can't abandon from here on this client - use the quest log.")
	end
end

local function RowClicked(row, button)
	if not row.questID then return end

	if button == "RightButton" then
		ShowMenu(row, {
			{ text = "Open quest log", action = function() OpenLog(row.index) end },
			{ text = "Stop tracking",  action = function() Untrack(row.questID) end },
			{ text = "Share quest",    action = function() ShareQuest(row.index) end },
			{ text = "Abandon quest",  danger = true,
			  action = function() AbandonQuestAt(row.index, row.questTitle) end },
		})
		return
	end

	if IsShiftKeyDown and IsShiftKeyDown() then
		Untrack(row.questID)
		return
	end

	OpenLog(row.index)
end

-- ---------------------------------------------------------------------------
-- panel construction
-- ---------------------------------------------------------------------------

local function BuildRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("LEFT", parent, "LEFT", 0, 0)
	row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	row:EnableMouse(true)
	row:SetScript("OnMouseUp", RowClicked)

	local hl = row:CreateTexture(nil, "BACKGROUND")
	hl:SetTexture(Media.texture.flat)
	hl:SetPoint("TOPLEFT", row, "TOPLEFT", -6, 2)
	hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 6, -2)
	hl:Hide()
	row.hl = hl

	row:SetScript("OnEnter", function(self) self.hl:Show() end)
	row:SetScript("OnLeave", function(self) self.hl:Hide() end)

	-- The level chip. Fixed width, so a column of them lines up and the titles
	-- start on one edge rather than stepping in and out with the digit count -
	-- which is the whole reason the quest log pins its own.
	--
	-- Sized DOWN from the title beside it rather than taken at the chip role's
	-- own 12. That role was drawn against the log's 14pt rows; here the title is
	-- 12, and a bold 12 chip next to a medium 12 title reads as the louder of the
	-- two - which inverts what the row is for.
	row.chip = W.Pill(row, "qlChip", {
		height = CHIP_H, size = math.max(9, Media:Size("questTitle") - 1),
	})
	row.chip:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.chip:Hide()

	-- No anchors here on purpose: Refresh sets all of them, because whether the
	-- left edge hangs off the chip or off the row changes with a setting.
	row.title = W.Text(row, "questTitle", "LEFT")
	row.title:SetHeight(TITLE_H)
	if row.title.SetWordWrap then row.title:SetWordWrap(false) end

	row.lines = {}

	row.bar = W.CreateBar(row, { height = BAR_H, smooth = false, bgAlpha = 0.10 })
	row.bar:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)

	return row
end

local function RowLine(row, i)
	local fs = row.lines[i]
	if fs then return fs end
	fs = W.Text(row, "questLine", "LEFT")
	fs:SetHeight(LINE_H)
	fs:SetPoint("LEFT", row, "LEFT", 10, 0)
	fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	row.lines[i] = fs
	return fs
end

local function Build()
	local cfg = A.Config:Module("questtracker")

	local panel = Glass.CreatePanel(UIParent, {
		corner = A.db.profile.glass.corner,
		shadow = A.db.profile.glass.shadow,
	})
	panel:SetSize(cfg.width, HEADER_H + PAD_TOP + PAD_BOTTOM)

	-- header: click to fold ---------------------------------------------------
	local header = CreateFrame("Button", nil, panel)
	header:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X, -PAD_TOP)
	header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD_X, -PAD_TOP)
	header:SetHeight(HEADER_H)
	header:RegisterForClicks("AnyUp")
	panel.header = header

	-- The deck sets the heading in letter-spaced caps. There is no letter-spacing
	-- in the WoW font engine, so the spaces are in the string.
	header.title = W.Text(header, "label", "LEFT")
	header.title:SetPoint("LEFT", header, "LEFT", 0, 0)
	header.title:SetText("Q U E S T S")

	header.count = W.Text(header, "tiny", "RIGHT")
	header.count:SetPoint("RIGHT", header, "RIGHT", 0, 0)

	header:SetScript("OnClick", function() QT:ToggleCollapsed() end)

	-- body --------------------------------------------------------------------
	local body = CreateFrame("Frame", nil, panel)
	body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	body:SetPoint("RIGHT", header, "RIGHT", 0, 0)
	body:SetHeight(1)
	panel.body = body

	panel.more = W.Text(body, "questLine", "LEFT")
	panel.more:SetHeight(LINE_H)
	panel.more:SetPoint("LEFT", body, "LEFT", 0, 0)
	panel.more:Hide()

	panel.rows = {}
	return panel
end

-- ---------------------------------------------------------------------------
-- layout
-- ---------------------------------------------------------------------------

local function RowHeight(quest, showObjectives)
	local h = TITLE_H
	if showObjectives then h = h + #quest.lines * LINE_H end
	if quest.pct ~= nil then h = h + BAR_GAP + BAR_H end
	return h
end

function QT:Refresh()
	local panel = self.panel
	if not panel then return end

	local cfg = A.Config:Module("questtracker")
	local c = Palette.c

	AdoptWatches()
	local quests, numQuests = Collect()

	panel.header.count:SetText(string.format("%d / %d", numQuests or 0,
		_G.MAX_QUESTLOG_QUESTS or _G.MAX_QUESTS or 20))
	W.Color(panel.header.count, c.textDim)
	W.Color(panel.header.title, c.text)

	-- Nothing tracked is not the same as nothing to show: the heading stays, so
	-- the panel does not blink out of existence between quests.
	local collapsed = self.collapsed

	-- With auto-track on you can have twenty quests, and twenty quests is most of
	-- the screen. Cut to a height budget rather than a row count, and say so in
	-- the panel - a tracker that silently drops the quest you are looking for is
	-- worse than one that admits it ran out of room.
	local budget = cfg.maxHeight or 420
	local shown, bodyH = 0, 0
	for i, q in ipairs(quests) do
		local h = RowHeight(q, cfg.showObjectives) + (i > 1 and ROW_GAP or 0)
		if i > (cfg.max or 20) or (shown > 0 and bodyH + h > budget) then break end
		shown, bodyH = i, bodyH + h
	end
	local hidden = #quests - shown

	for i = 1, shown do
		local q = quests[i]
		local row = panel.rows[i]
		if not row then
			row = BuildRow(panel.body)
			panel.rows[i] = row
		end

		row.index, row.questID, row.questTitle = q.index, q.questID, q.title

		-- Difficulty rides in the chip, the title stays white. Same treatment as a
		-- row in the quest log, and for the same reason: the colour is a property
		-- of the level, not of the name, and a column of white titles is a list
		-- you read rather than one you decode. Complete quests are no exception -
		-- the green bar and the Complete line below already say so.
		local band = c.questDiff[q.band] or c.questDiff.difficult

		-- Re-anchored rather than left pinned to a hidden chip: an anchor to a
		-- hidden region still resolves, so turning the level off would otherwise
		-- indent every title by the width of a chip that is not there.
		row.title:ClearAllPoints()
		row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
		if cfg.showLevel and q.level and q.level > 0 then
			row.chip:SetLabel(tostring(q.level), CHIP_W)
			row.chip:SetColors(band.bg, band.text)
			row.chip:Show()
			row.title:SetPoint("TOPLEFT", row.chip, "TOPRIGHT", CHIP_GAP, 0)
		else
			row.chip:Hide()
			row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
		end

		row.title:SetText(q.title)
		W.Color(row.title, c.text)
		row.hl:SetVertexColor(c.accent[1], c.accent[2], c.accent[3], 0.10)

		local y = TITLE_H
		for j = 1, #q.lines do
			local fs = RowLine(row, j)
			if cfg.showObjectives then
				fs:SetText(q.lines[j].text)
				W.Color(fs, q.lines[j].done and c.health[1]
					or (q.lines[j].finished and c.textFaint or c.textDim))
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -y)
				fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
				fs:Show()
				y = y + LINE_H
			else
				fs:Hide()
			end
		end
		for j = #q.lines + 1, #row.lines do row.lines[j]:Hide() end

		if q.pct ~= nil then
			row.bar:ClearAllPoints()
			row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(y + BAR_GAP))
			row.bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
			row.bar:SetMinMaxValues(0, 1)
			row.bar:SetValue(math.max(0.02, q.pct))
			row.bar:SetColors(q.complete and c.health or c.xp)
			row.bar:Show()
		else
			row.bar:Hide()
		end

		row:SetHeight(RowHeight(q, cfg.showObjectives))
		row:ClearAllPoints()
		row:SetPoint("LEFT", panel.body, "LEFT", 0, 0)
		row:SetPoint("RIGHT", panel.body, "RIGHT", 0, 0)
		if i == 1 then
			row:SetPoint("TOP", panel.body, "TOP", 0, 0)
		else
			row:SetPoint("TOP", panel.rows[i - 1], "BOTTOM", 0, -ROW_GAP)
		end
		if collapsed then row:Hide() else row:Show() end
	end

	for i = shown + 1, #panel.rows do panel.rows[i]:Hide() end

	if hidden > 0 and not collapsed then
		panel.more:SetText(string.format("+%d more", hidden))
		W.Color(panel.more, c.textFaint)
		panel.more:ClearAllPoints()
		panel.more:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -(bodyH + 4))
		panel.more:Show()
		bodyH = bodyH + 4 + LINE_H
	else
		panel.more:Hide()
	end

	if collapsed or bodyH <= 0 then
		panel.body:Hide()
		panel:SetHeight(PAD_TOP + HEADER_H + PAD_BOTTOM)
	else
		panel.body:Show()
		panel.body:SetHeight(bodyH)
		panel:SetHeight(PAD_TOP + HEADER_H + 6 + bodyH + PAD_BOTTOM)
	end

	panel:SetWidth(cfg.width)
	self.quests = quests
	self.hidden = hidden
end

function QT:SetCollapsed(v)
	self.collapsed = v and true or false
	self:Refresh()
end

function QT:ToggleCollapsed()
	-- Folding by hand during a fight means you wanted it open; do not let the
	-- combat restore undo that decision on the way out.
	self._preCombat = nil
	self:SetCollapsed(not self.collapsed)
end

-- ---------------------------------------------------------------------------
-- module lifecycle
-- ---------------------------------------------------------------------------

function QT:OnEnable()
	if not self.panel then self.panel = Build() end
	self.panel:Show()
	-- A real boolean from the start. Three places read this and one of them uses
	-- nil to mean something else entirely.
	if self.collapsed == nil then self.collapsed = false end

	-- growsDown: the panel gets taller as quests are tracked, so it has to stay
	-- pinned by its top edge whatever corner you drop it near.
	A.Movers:Register("quests", self.panel,
		{ point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -24, y = -140 }, "Quests",
		{ growsDown = true })

	local function refresh() QT:Refresh() end
	A:RegisterEvent(self, "QUEST_LOG_UPDATE", refresh)
	A:RegisterEvent(self, "QUEST_WATCH_UPDATE", refresh)
	A:RegisterEvent(self, "UNIT_QUEST_LOG_CHANGED", refresh)
	A:RegisterEvent(self, "QUEST_ACCEPTED", refresh)
	A:RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", refresh)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		QT:HideBlizzard()
		QT:Refresh()
	end)

	-- `and true or false`, and it is the whole bug rather than a tidy-up.
	--
	-- `collapsed` starts nil - nothing initialises it, and Refresh is happy to
	-- read nil as "not collapsed". So the first fight stored nil, and the restore
	-- below uses nil as its sentinel for "nothing to put back" and returned
	-- immediately. The tracker folded for combat and stayed folded, for the rest
	-- of the session and every fight after it, because the flag that says
	-- "remember to unfold" was indistinguishable from the state it was recording.
	A:RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
		local cfg = A.Config:Module("questtracker")
		if not cfg.combatCollapse then return end
		QT._preCombat = QT.collapsed and true or false
		QT:SetCollapsed(true)
	end)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
		local cfg = A.Config:Module("questtracker")
		if not cfg.combatCollapse then return end
		if QT._preCombat == nil then return end
		QT:SetCollapsed(QT._preCombat)
		QT._preCombat = nil
	end)

	A.Fader:Register(self.panel, {})

	self:HideBlizzard()
	self:OnConfigChanged()
end

function QT:OnDisable()
	if self.panel then
		self.panel:Hide()
		A.Fader:Unregister(self.panel)
	end
	if self.menu then self.menu:Hide() end
	A.Movers:Unregister("quests")
end

function QT:OnSkinChanged()
	if not self.panel then return end
	self.panel:ApplySkin()
	if self.menu then self.menu:ApplySkin("dialogFill", "glassEdgeHi") end
	self:Refresh()
end

function QT:OnConfigChanged()
	if not self.panel then return end
	local cfg = A.Config:Module("questtracker")

	self.panel:SetScale(A.db.profile.scale)
	self.panel:SetShadow(A.db.profile.glass.shadow)
	Glass.SetPanelCorner(self.panel, A.db.profile.glass.corner)
	self.panel:SetWidth(cfg.width)

	self:Refresh()
	A.Fader:Refresh()
end
