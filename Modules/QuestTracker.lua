--[[--------------------------------------------------------------------------
	Lattice :: QuestTracker

	The tracked quests, as nodes on the World trunk (Lattice 6a): one 18 px
	diamond per quest under the Quest Log node, its title beside it, and its
	state in the diamond - in progress, active, complete (TURN IN), elsewhere,
	failed. Compact (Joe, 2026-10-10): the active quest shows its objectives,
	and any quest's pop out while the cursor is on it. The floating glass panel
	of 1.x is gone; this module is the data, the nodes and the quest items
	beside them.

	The outline takes the quest log's own difficulty colours, because the two
	lists are read together and one scheme drawn two ways is worse than either.

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


local L = A.L
local QT = A:NewModule("questtracker")

local W, Palette = A.Widgets, A.Palette

-- ---------------------------------------------------------------------------
-- quest log adapter
-- ---------------------------------------------------------------------------

-- THROUGH A.Quest, which is where both of these live now.
--
-- This file carried its own copies of the same three readers the quest log had,
-- and WoW Forever is what made that cost real: it keeps NONE of the old
-- quest-log API, so each copy would have needed the same second client taught
-- to it separately. One shim in Core\Core.lua, used by both windows - which is
-- also why it is in Core rather than in QuestLog.lua, since this file loads
-- first.
local NumEntries = A.Quest.NumEntries

--- title, level, isHeader, isComplete, questID
--
--  A.Quest.Title hands back the questTag as its third value, which this window
--  has no use for - the level chip carries difficulty here. Dropped on the way
--  through rather than by giving the shim a second shape.
local function LogTitle(index)
	local title, level, _, isHeader, _, isComplete, questID = A.Quest.Title(index)
	if not title then return nil end
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
--  The numbers come from the API where it has them: WoW Forever returns
--  numFulfilled/numRequired outright, and matching them back out of display
--  text is only the fallback the old client leaves us.
local function Objectives(index)
	local lines, done, total = {}, 0, 0

	for _, line in ipairs(A.Quest.Objectives(index)) do
		local finished = line.finished
		lines[#lines + 1] = { text = line.text, finished = finished }

		local cur, max = line.fulfilled, line.required
		if not (cur and max) then
			cur, max = string.match(line.text, "(%d+)%s*/%s*(%d+)")
			cur, max = tonumber(cur), tonumber(max)
		end
		if cur and max and max > 0 then
			done, total = done + math.min(cur, max), total + max
		else
			done, total = done + (finished and 1 or 0), total + 1
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

--- A COLLAPSED ZONE HEADER EMPTIES THIS TRACKER, and nothing said so.
--
--  Reported as the tracker closing itself and not opening again when clicked,
--  and /aether quests diag answered it in one line: one entry in the log, one
--  quest, tracker holds zero, one collapsed zone. A collapsed header does not
--  merely fold its quests on screen - it removes them from GetQuestLogTitle
--  entirely, so the walk below sees a header and nothing else, draws no rows,
--  and the body collapses to nothing. Clicking the header then toggles a fold
--  state over an empty list, which is why it appeared dead.
--
--  ONCE, AT LOGIN, AND NEVER AGAIN. The first attempt at this expanded from
--  the scan itself, which meant collapsing a zone anywhere - in Questie, in
--  anything - was undone in the same frame, because ExpandQuestHeader fires
--  QUEST_LOG_UPDATE and the scan runs from that. That is not a policy, it is a
--  fight.
--
--  So: one sweep when the tracker starts, which clears the state that caused
--  the report - collapsed in some earlier session, invisible ever since,
--  because this interface has no collapsed-zone concept and nowhere to undo
--  one. After that the player's own collapses stand, and the tracker SAYS SO
--  rather than emptying silently; see the hidden count in Collect.
--
--  Downward, because expanding a header renumbers everything below it.
local expanding = false

local function ExpandCollapsedZones()
	if expanding or not ExpandQuestHeader then return false end

	-- THROUGH THE CLIENT'S OWN TUPLE, not through LogTitle: that helper drops
	-- isCollapsed, because nothing else here has ever needed it. Reading the
	-- fifth return directly is the same call one field wider.
	local entries = NumEntries()
	local found = false
	for index = 1, entries do
		local _, _, _, isHeader, isCollapsed = A.Quest.Title(index)
		if isHeader and isCollapsed then found = true break end
	end
	if not found then return false end

	expanding = true
	pcall(function()
		for index = entries, 1, -1 do
			local _, _, _, isHeader, isCollapsed = A.Quest.Title(index)
			if isHeader and isCollapsed then pcall(ExpandQuestHeader, index) end
		end
	end)
	expanding = false
	return true
end

--- Tracked quests that are actually in the log right now, in log order.
--
--  Log order is zone order, so the rows come out grouped by zone for free.
local function Collect()
	local out, seen = {}, {}

	-- WHAT THE COLLAPSE IS HIDING. GetNumQuestLogEntries answers a count of
	-- ENTRIES and a count of QUESTS, and only the first is affected by a folded
	-- header - so the two disagreeing is the client telling us, for free, that
	-- there are quests it will not name. Without this the tracker simply drew
	-- nothing and looked broken, which is exactly how it was reported.
	local entries, quests = NumEntries()
	local visible = 0
	-- The zone a quest is listed under: the last header above it. Compared with
	-- where you are, it is what draws a quest elsewhere faint (Lattice 6a).
	local zone

	for index = 1, entries do
		local title, level, isHeader, isComplete, questID = LogTitle(index)
		if title and isHeader then zone = title end
		if title and not isHeader then visible = visible + 1 end
		if title and not isHeader and questID then
			seen[questID] = true
			if IsTracked(questID) then
				local lines, pct = Objectives(index)
				-- -1 IS FAILED, and `if isComplete` is true for it (the shim's
				-- tri-state). It was drawn as in progress; it is its own state now.
				local failed = (isComplete == -1)
				local complete = not failed and ((isComplete == 1) or (isComplete == true)
					or (pct ~= nil and pct >= 1))
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
					lines = lines, pct = pct, complete = complete, failed = failed,
					band = DifficultyBand(level), zone = zone,
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
		local _, _, _, isHeader, isCollapsed = A.Quest.Title(index)
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

	-- The third return is the client's own two counts disagreeing: it will admit
	-- to `quests` quests and name only `visible` of them, and the difference is
	-- what a folded zone is holding back.
	return out, quests, math.max(0, (quests or 0) - visible)
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
-- row actions
-- ---------------------------------------------------------------------------

local function Untrack(questID)
	SetTracked(questID, false)
	QT:Refresh()
end

--- Open OUR quest log at this quest, and only fall back to Blizzard's when
--  there isn't one.
--
--  Every route this used to take - `QuestLog_OpenToQuest`, then
--  `ShowUIPanel(QuestLogFrame)` - reaches for the frame `Modules/QuestLog.lua`
--  exists to replace, so clicking a row opened the window this addon spends a
--  module hiding. It also threw on the way:
--
--    QuestLogFrame.lua:343: bad argument #1 to 'SetVertexColor'
--
--  `QuestLog_OnShow` calls `QuestLog_SetSelection` BEFORE `QuestLog_Update`, and
--  the selection path reads `titleButton.r` - which only Update ever writes. On
--  a frame nobody has drawn, because we replaced it, that is
--  `SetVertexColor(nil)`.
--
--  Note the `pcall` around `ShowUIPanel` never stood a chance of catching it:
--  the error is raised inside the frame's own OnShow, which the C `Show()` runs,
--  so it goes to the global error handler rather than back through our pcall. A
--  pcall around a call that shows a frame protects nothing that happens in that
--  frame's scripts.
local function OpenLog(index, questID)
	local QL = A:GetModule("questlog")
	if QL and QL.enabled and QL.win and QL.Show then
		-- Show first, then select. Showing populates the entry list from its own
		-- OnShow, and Select matches against that list - the other order picks a
		-- key out of whatever happened to be there last time.
		QL:Show()
		-- The same key shape the log builds its own entries with: the questID
		-- where the client gave us one, and the index otherwise. Log indices
		-- renumber whenever a quest is accepted or abandoned, so the fallback is
		-- the weaker of the two on purpose.
		local key = questID or (index and ("i" .. tostring(index)))
		if key ~= nil and QL.Select then pcall(QL.Select, QL, key) end
		return
	end

	-- Blizzard's, for a client where our own log is switched off. The update is
	-- forced BEFORE the show for the ordering reason above: on a frame that has
	-- never been drawn, selecting first is the crash.
	A.Quest.Select(index)
	if _G.QuestLogFrame and QuestLog_Update then pcall(QuestLog_Update) end
	if QuestLog_OpenToQuest then
		if pcall(QuestLog_OpenToQuest, index) then return end
	end
	if ShowUIPanel and _G.QuestLogFrame then
		pcall(ShowUIPanel, _G.QuestLogFrame)
	elseif ToggleQuestLog then
		pcall(ToggleQuestLog)
	end
end

local function ShareQuest(index)
	A.Quest.Push(index)
end

--- Abandon goes through Blizzard's own confirmation, never straight to
--  AbandonQuest. Losing a quest chain to a stray click in a tracker is not a
--  thing this addon is going to be responsible for.
local function AbandonQuestAt(index, title)
	-- THE LATCH is what has to work here: Blizzard's popup abandons whatever is
	-- latched, so showing it without one asks "abandon?" and then does nothing,
	-- or abandons a quest latched earlier. That is exactly what happened on WoW
	-- Forever, where the latch is C_QuestLog.SetAbandonQuest and the global this
	-- checked for does not exist. A.Quest.SetAbandon selects and latches on
	-- either client, and refuses rather than guessing.
	if not StaticPopup_Show or not A.Quest.SetAbandon(index) then
		A:Print(L.common.can_t_abandon_here)
		return
	end
	if not pcall(StaticPopup_Show, "ABANDON_QUEST", title) then
		A:Print(L.common.can_t_abandon_here)
	end
end

--- Hand the quest to TomTom, by way of Questie. See Core/Nav.lua for why that
--  sentence is three paragraphs of caveats.
--
--  `loc` is the one the menu already resolved to decide whether to grey the
--  item. Passing it on rather than asking again keeps a single click to a
--  single trip through Questie.
local function Navigate(questID, title, loc)
	local ok, detail = A.Nav:Route(questID, title, loc)
	if ok then
		A:Print(A.F(L.tracker.navigate.routing_s, detail or title or L.tracker.navigate.quest))
	else
		A:Print(detail or L.tracker.navigate.can_t_route_quest)
	end
end

local function RowClicked(row, button)
	if not row.questID then return end

	if button == "RightButton" then
		local entries = {
			{ text = "Open quest log", action = function() OpenLog(row.index, row.questID) end },
		}

		-- FOCUS, where the client has it (WoW Forever), worded and placed the
		-- way Blizzard's own tracker menu has it. Absent on Classic Era rather
		-- than greyed: there is nothing there it could ever do.
		if A.Quest.CanFocus() then
			local questID = row.questID
			local focused = A.Quest.FocusedID() == questID
			entries[#entries + 1] = {
				text = focused and L.questtracker.menu.stop_focus
					or L.questtracker.menu.focus,
				action = function() A.Quest.Focus(focused and 0 or questID) end,
			}
		end

		entries[#entries + 1] = { text = "Stop tracking", action = function() Untrack(row.questID) end }
		entries[#entries + 1] = { text = "Share quest",   action = function() ShareQuest(row.index) end }

		-- Only when BOTH addons are actually there. A menu item that exists to
		-- tell you an addon is missing is an advert, not a feature - and this
		-- one would be on screen for every player who has neither.
		if A.Nav:Available() then
			local questID, title = row.questID, row.questTitle
			local loc = A.Nav:Locate(questID)
			entries[#entries + 1] = {
				text = loc and "Navigate with TomTom" or "No location known",
				disabled = (loc == nil),
				action = function() Navigate(questID, title, loc) end,
			}
		end

		entries[#entries + 1] = { text = "Abandon quest", danger = true,
			action = function() AbandonQuestAt(row.index, row.questTitle) end }

		W.Menu(row, entries)
		return
	end

	if IsShiftKeyDown and IsShiftKeyDown() then
		Untrack(row.questID)
		return
	end

	-- AN OBJECTIVE LINE FOCUSES THE QUEST; the title still opens the log. The
	-- line is text on the row rather than a button of its own, so the row asks
	-- which of its lines is under the cursor. Focus only - a second click on a
	-- focused quest leaves it focused; stopping is the menu's job.
	if A.Quest.CanFocus() then
		for _, fs in ipairs(row.lines) do
			if fs:IsShown() and fs.IsMouseOver and fs:IsMouseOver() then
				A.Quest.Focus(row.questID)
				return
			end
		end
	end

	OpenLog(row.index, row.questID)
end

-- ---------------------------------------------------------------------------
-- on the World trunk (Lattice 6a)
--
-- One item node per tracked quest, its text beside it on the screen-centre
-- side, ending 8 short of the node. COMPACT (Joe, 2026-10-10): a title
-- line each; the active quest shows its objectives under its title, and any
-- quest's objectives pop out beside it while the cursor is on it.
--
-- The text is sized to the WORDS, not to a column: the trunk sits over the
-- world, where a stray click costs you the thing you were aiming at.
-- ---------------------------------------------------------------------------

local TITLE_H, LINE_H = 16, 14
local STEP = 32          -- a title-only quest's share of the strand
-- 8 short of the node's edge, as the branch labels are (Joe, in game: 68
-- from its centre read as detached).
local TEXT_GAP = 8
local TEXT_W = 240       -- a longer title is cut short, not wrapped
local TAG_GAP = 6
local MORE = "questmore"

local function Trunk() return A.Trunk:Get("world") end

--- The popout: every objective, beside the quest's text.
local function ShowObjectives(holder)
	local q = holder and holder.quest
	if not (q and GameTooltip) then return end
	local c = Palette.c
	GameTooltip:SetOwner(holder, "ANCHOR_NONE")
	-- Nothing left over from whatever had the tooltip last.
	GameTooltip:ClearLines()
	GameTooltip:ClearAllPoints()
	if (Trunk().side or -1) < 0 then
		GameTooltip:SetPoint("RIGHT", holder, "LEFT", -12, 0)
	else
		GameTooltip:SetPoint("LEFT", holder, "RIGHT", 12, 0)
	end
	GameTooltip:AddLine(q.title, c.text[1], c.text[2], c.text[3])
	for _, line in ipairs(q.lines) do
		local col = line.done and c.health[1] or (line.finished and c.textFaint or c.textDim)
		GameTooltip:AddLine(line.text, col[1], col[2], col[3])
	end
	GameTooltip:Show()
	holder.popped = true
end

local function HideObjectives(holder)
	if holder and holder.popped and GameTooltip then GameTooltip:Hide() end
	if holder then holder.popped = nil end
end

local function BuildHolder(parent)
	local h = CreateFrame("Button", nil, parent)
	h:EnableMouse(true)
	h:SetScript("OnMouseUp", RowClicked)
	h:SetScript("OnEnter", ShowObjectives)
	h:SetScript("OnLeave", HideObjectives)
	h.title = W.Text(h, "questTitle", "RIGHT")
	h.title:SetHeight(TITLE_H)
	if h.title.SetWordWrap then h.title:SetWordWrap(false) end
	-- TURN IN or FAILED, between the title and the node.
	h.tag = W.Text(h, "label", "RIGHT")
	h.tag:Hide()
	h.lines = {}
	h:Hide()
	return h
end

local function HolderLine(h, i)
	local fs = h.lines[i]
	if fs then return fs end
	fs = W.Text(h, "questLine", "RIGHT")
	fs:SetHeight(LINE_H)
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	h.lines[i] = fs
	return fs
end

-- ---------------------------------------------------------------------------
-- quest items
--
-- A quest with an item to use - the blackjack for the lazy peons - gets it as
-- a button beside its node, on the side away from the text.
--
-- Using an item is protected, so the button is a SecureActionButton, and a
-- fight locks it: no showing, hiding, moving or re-aiming. So it hangs off
-- UIParent at a measured point, never off the trunk - a secure frame anchored
-- to the trunk would lock the trunk in a fight as well - and whatever changes
-- mid-fight waits for the fight to end. It stays usable meanwhile.
--
-- Which item: the client's own answer where it has one
-- (GetQuestLogSpecialItemInfo, which Blizzard's tracker reads on WoW
-- Forever), then Questie's database, the way Questie's tracker does it on
-- Classic Era: kept only if it is in the bags and has a use.
-- ---------------------------------------------------------------------------

local Items = { size = 22, gap = 6 }

function Items.Count(id)
	local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
	if not fn then return 0 end
	local ok, n = pcall(fn, id)
	return ok and tonumber(n) or 0
end

--- Whether using it does anything: a spell on it, or something to put on.
function Items.Usable(id)
	local spell = C_Item and C_Item.GetItemSpell
	if spell and spell(id) then return true end
	local equip = C_Item and C_Item.IsEquippableItem
	return equip and equip(id) and true or false
end

function Items.Icon(id)
	if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
	return GetItemInfoInstant and select(5, GetItemInfoInstant(id)) or nil
end

--- The item to show for a quest, or nil: its id and icon.
function Items.For(q)
	if GetQuestLogSpecialItemInfo and q.index then
		local ok, link, icon, _, whenComplete = pcall(GetQuestLogSpecialItemInfo, q.index)
		local id = ok and type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id and (not q.complete or whenComplete) and Items.Count(id) > 0 then
			return id, icon or Items.Icon(id)
		end
	end
	-- The database's items are for doing the quest, not for handing it in.
	if q.complete or q.failed then return nil end
	for _, id in ipairs(A.Nav:SourceItems(q.questID)) do
		if Items.Count(id) > 0 and Items.Usable(id) then return id, Items.Icon(id) end
	end
end

--- Count and cooldown. Neither is protected, so this runs in a fight too.
function Items.Paint(b)
	local id = b.itemID
	if not id then return end
	local n = Items.Count(id)
	b.count:SetText(n > 1 and tostring(n) or "")
	local cd = C_Container and C_Container.GetItemCooldown
	local ok, start, duration = false, nil, nil
	if cd then ok, start, duration = pcall(cd, id) end
	if ok and start and duration and duration > 0 then
		pcall(b.cooldown.SetCooldown, b.cooldown, start, duration)
		b.cooldown:Show()
	else
		b.cooldown:Hide()
	end
end

local function ItemEnter(b)
	if not (b.itemID and GameTooltip) then return end
	GameTooltip:SetOwner(b, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	if (Trunk().side or -1) < 0 then
		GameTooltip:SetPoint("RIGHT", b, "LEFT", -8, 0)
	else
		GameTooltip:SetPoint("LEFT", b, "RIGHT", 8, 0)
	end
	GameTooltip:SetHyperlink("item:" .. b.itemID)
	GameTooltip:Show()
end

local function ItemLeave()
	if GameTooltip then GameTooltip:Hide() end
end

--- A quest node's item button, made on first ask, out of a fight only.
function Items.Button(node)
	if node.itemButton then return node.itemButton end
	local b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	b:SetSize(Items.size, Items.size)
	b:SetFrameStrata("MEDIUM")
	W.DecorateSlot(b, Items.size)
	b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints(b)
	b.cooldown:Hide()
	-- Both phases. The secure handler acts on the one the player's
	-- cast-on-key-down setting asks for, so a button registered for one alone
	-- does nothing for anyone on the other (EllesmereUIQuestTracker_QoL.lua:217).
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetScript("OnEnter", ItemEnter)
	b:SetScript("OnLeave", ItemLeave)
	b:Hide()
	-- Fades with the trunk. Alpha is not protected.
	if A.Fader then A.Fader:Register(b) end
	node.itemButton = b
	return b
end

--- Put a quest node's item beside it, or take it away. Retracted, only the
--  active quest's item stays, beside the tail's diamond.
--
--  In a fight it is left as it is and marked, and the fight's end puts it
--  right - except inside the fight's first event (Items.window), where a
--  secure frame can still be moved: HazeBuffBars does it there on Classic Era
--  (Bars.lua:25), and EllesmereUI on WoW Forever, where InCombatLockdown
--  already answers true by then (EllesmereUI_PartyMode.lua:726).
function Items.Place(node)
	local q = node.quest
	local anchor, id = node.button, nil
	if A.Trunk.flying then
		-- In flight: no item, not even the active quest's (Joe).
	elseif QT.collapsed then
		local tq = QT.Tail.active
		if q and tq and q.questID == tq.questID then anchor, id = Trunk():Tail().node, q.itemID end
	elseif q and node.button and node.button:IsVisible() then
		id = q.itemID
	end
	local b = node.itemButton
	if not id and not b then return end
	if not Items.window and InCombatLockdown and InCombatLockdown() then
		if not b or b.itemID ~= id or b.anchor ~= anchor then Items.dirty = true end
		return
	end
	b = b or Items.Button(node)

	local x, y
	if id and anchor:IsVisible() then x, y = A.Movers.PointAt(anchor, "CENTER") end
	if not (x and y) then
		b:Hide()
		b:SetAttribute("type1", nil)
		b:SetAttribute("item1", nil)
		b.itemID, b.anchor = nil, nil
		return
	end

	-- The trunk's scale, so it sits with the trunk's nodes; placed in its own
	-- units, measured from UIParent's corner.
	local s = Trunk():Frame():GetEffectiveScale() / UIParent:GetEffectiveScale()
	local out = -(Trunk().side or -1)
	local d = (anchor:GetWidth() / 2 + Items.gap + Items.size / 2) * s
	b.anchor = anchor
	b:SetScale(s)
	b:ClearAllPoints()
	b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (x + out * d) / s, y / s)
	b:SetAttribute("type1", "item")
	b:SetAttribute("item1", "item:" .. id)
	b.itemID = id
	b.icon:SetTexture(q.itemIcon)
	Items.Paint(b)
	b:Show()
end

QT.Items = Items

-- ---------------------------------------------------------------------------
-- retracted (6b)
--
-- In a fight the World trunk goes up into the pill and one thing stays out:
-- the active quest, on the trunk's tail, its title and count beside it. An
-- objective that moves in the fight takes the tail for 2 s with its count
-- flashing, then the active quest has it back.
-- ---------------------------------------------------------------------------

local Tail = { seen = {}, flashFor = 2 }
QT.Tail = Tail

--- A quest's objective lines by index, the Complete line left out.
local function LineTexts(q)
	local out = {}
	for i, line in ipairs(q.lines) do
		if not line.done then out[i] = line.text end
	end
	return out
end

--- The first objective line that moved since the last look, as { q, line },
--  or nil. Remembers what it saw either way, and forgets quests that went.
--  Through a loading screen it only remembers: the client hands back stale
--  and then fresh lines there, which is not progress.
function Tail.Diff(quests)
	local moved, seen = nil, {}
	for _, q in ipairs(quests) do
		local now, was = LineTexts(q), Tail.seen[q.questID]
		if was and not Tail.loading and not moved then
			for i, text in pairs(now) do
				if was[i] ~= nil and was[i] ~= text then
					moved = { q = q, line = i }
					break
				end
			end
		end
		seen[q.questID] = now
	end
	Tail.seen = seen
	return moved
end

--- "3/5" from the line that moved, or the first one not yet done.
function Tail.Count(q, i)
	local line = i and q.lines[i]
	if not line then
		for _, l in ipairs(q.lines) do
			if not l.finished and not l.done then line = l break end
		end
	end
	return line and line.text:match("(%d+%s*/%s*%d+)") or nil
end

--- The count pulses while a tick has the tail, then the tail goes back.
local function TailUpdate(t, dt)
	local f = Tail.flash
	if not f then t:SetScript("OnUpdate", nil) return end
	f.left = f.left - (dt or 0)
	if f.left <= 0 then
		Tail.flash = nil
		t:SetScript("OnUpdate", nil)
		Tail.Draw()
		return
	end
	t.count:SetAlpha(0.55 + 0.45 * math.abs(math.cos(f.left * math.pi)))
end

--- Fill the tail and show it, or put it away.
function Tail.Draw()
	local t = Trunk():Tail()
	local f = Tail.flash
	local q = f and f.q or Tail.active
	-- No tail in flight: the active quest is no use on a griffin (Joe).
	t:SetShown(QT.enabled and QT.collapsed and q ~= nil and not A.Trunk.flying or false)
	if not t:IsShown() then return end
	if not t.title then
		t.title = W.Text(t, "questTitle", "RIGHT")
		if t.title.SetWordWrap then t.title:SetWordWrap(false) end
		t.count = W.Text(t, "label", "RIGHT")
	end
	local c = Palette.c
	local left = (Trunk().side or -1) < 0
	local just = left and "RIGHT" or "LEFT"
	t.count:SetText(Tail.Count(q, f and f.line) or "")
	t.count:SetAlpha(1)
	W.Color(t.count, c.accent)
	t.title:SetText(q.title or "")
	W.Color(t.title, c.text)
	t.title:SetWidth(math.max(1, math.min(math.ceil(t.title:GetStringWidth() or 0), TEXT_W)))
	t.title:SetJustifyH(just)
	t.count:ClearAllPoints()
	t.title:ClearAllPoints()
	local gap = (t.count:GetText() ~= "") and TAG_GAP or 0
	if left then
		t.count:SetPoint("RIGHT", t.node, "LEFT", -TEXT_GAP, 0)
		t.title:SetPoint("RIGHT", t.count, "LEFT", -gap, 0)
	else
		t.count:SetPoint("LEFT", t.node, "RIGHT", TEXT_GAP, 0)
		t.title:SetPoint("LEFT", t.count, "RIGHT", gap, 0)
	end
	if f then t:SetScript("OnUpdate", TailUpdate) end
end

-- ---------------------------------------------------------------------------
-- layout
-- ---------------------------------------------------------------------------

--- Whether a quest's objectives sit under its title: the active one only.
local function Expanded(q)
	return q and q.active and A.Config:Module("questtracker").showObjectives ~= false
end

--- A quest's share of the strand: its title, and its lines when expanded.
local function StepOf(q)
	return STEP + (Expanded(q) and #q.lines * LINE_H or 0)
end

--- Lay out and colour one quest node and its text, from the quest it holds.
--  Called by the trunk on every paint, so a skin change re-reads it all.
local function Decorate(node)
	local h, b, q = node.holder, node.button, node.quest
	if not (h and b) then return end
	-- First: it has to go with the node, text or none.
	Items.Place(node)
	h:SetShown(b:IsShown() and (q ~= nil or node.text ~= nil))
	if not h:IsShown() then return end

	local c = Palette.c
	local left = (Trunk().side or -1) < 0
	local just = left and "RIGHT" or "LEFT"

	-- The words first, so they can be measured.
	h.title:SetText(q and q.title or node.text or "")
	local tag
	if q and q.complete then tag = L.trunk.turn_in
	elseif q and q.failed then tag = L.trunk.failed end
	h.tag:SetText(tag and tag:upper() or "")
	h.tag:SetShown(tag ~= nil)
	local tagW = tag and math.ceil(h.tag:GetStringWidth() or 0) or 0
	local titleW = math.min(math.ceil(h.title:GetStringWidth() or 0), TEXT_W - tagW)
	h.title:SetWidth(math.max(1, titleW))
	local width = titleW + (tag and (TAG_GAP + tagW) or 0)

	local lines = Expanded(q) and q.lines or {}
	for i, line in ipairs(lines) do
		local fs = HolderLine(h, i)
		fs:SetText(line.text)
		W.Color(fs, line.done and c.health[1] or (line.finished and c.textFaint or c.textDim))
		local lw = math.min(math.ceil(fs:GetStringWidth() or 0), TEXT_W)
		fs:SetWidth(math.max(1, lw))
		fs:SetJustifyH(just)
		fs:ClearAllPoints()
		fs:SetPoint("TOP" .. just, h, "TOP" .. just, 0, -(TITLE_H + (i - 1) * LINE_H))
		fs:Show()
		width = math.max(width, lw)
	end
	for i = #lines + 1, #h.lines do h.lines[i]:Hide() end

	-- The tag nearest the node, then the title.
	h.tag:ClearAllPoints()
	h.title:ClearAllPoints()
	h.title:SetJustifyH(just)
	if left then
		h.tag:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -2)
		h.title:SetPoint("TOPRIGHT", h, "TOPRIGHT", tag and -(tagW + TAG_GAP) or 0, 0)
	else
		h.tag:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -2)
		h.title:SetPoint("TOPLEFT", h, "TOPLEFT", tag and (tagW + TAG_GAP) or 0, 0)
	end
	h:SetSize(math.max(1, width), TITLE_H + #lines * LINE_H)
	h:ClearAllPoints()
	if left then
		h:SetPoint("TOPRIGHT", b, "LEFT", -TEXT_GAP, TITLE_H / 2)
	else
		h:SetPoint("TOPLEFT", b, "RIGHT", TEXT_GAP, TITLE_H / 2)
	end

	-- The node's state (6a): outline in progress, bright outline active, green
	-- complete, faint elsewhere; failed is ours - red, hollow. The outline takes
	-- the quest's difficulty colour, as the quest log's chip does.
	local glass = { 14 / 255, 11 / 255, 32 / 255 }
	local band = q and (c.questDiff[q.band] or c.questDiff.difficult)
	local diff = band and band.bg or c.textFaint
	b.glow:Hide()
	if not q then
		W.Tint(b.fill, glass, 0.85)
		W.Tint(b.rim, c.textFaint, 0.6)
		W.Color(h.title, c.textFaint)
	elseif q.complete then
		W.Tint(b.fill, c.friendly, 1)
		W.Tint(b.rim, c.friendly, 1)
		W.Tint(b.glow, c.friendly, 0.55)
		b.glow:Show()
		W.Color(h.title, c.text)
		W.Color(h.tag, c.friendly)
	elseif q.failed then
		W.Tint(b.fill, glass, 0.85)
		W.Tint(b.rim, c.danger, 1)
		W.Color(h.title, c.text)
		W.Color(h.tag, c.danger)
	elseif q.active then
		W.Tint(b.fill, glass, 0.85)
		W.Tint(b.rim, c.accent, 1)
		W.Tint(b.glow, c.accent, 0.3)
		b.glow:Show()
		W.Color(h.title, c.text)
	elseif q.elsewhere then
		W.Tint(b.fill, glass, 0.85)
		W.Tint(b.rim, diff, 0.3)
		W.Color(h.title, { c.text[1], c.text[2], c.text[3], 0.55 })
	else
		W.Tint(b.fill, glass, 0.85)
		W.Tint(b.rim, diff, 0.7)
		W.Color(h.title, c.text)
	end
end

--- Click on the overflow node: the log, at the first quest it stands for.
local function MoreClicked(node, button)
	local q = node.moreQuest
	if q and button ~= "RightButton" then OpenLog(q.index, q.questID) end
end

local function ItemNode(key, order)
	local node = Trunk():AddNode(key, {
		kind = "item", order = order,
		available = function() return QT.enabled and (QT.nodesShown or {})[key] and true or false end,
		decorate = Decorate,
		onEnter = function(n) ShowObjectives(n.holder) end,
		onLeave = function(n) HideObjectives(n.holder) end,
		-- The retract fades the text with its node.
		setAlpha = function(n, a)
			n.holder:SetAlpha(a)
			n.holder:EnableMouse(a > 0.5)
		end,
	})
	node.holder = node.holder or BuildHolder(Trunk():Frame())
	return node
end

function QT:Refresh()
	local cfg = A.Config:Module("questtracker")
	local c = Palette.c

	AdoptWatches()
	local quests, numQuests, behindFold = Collect()
	self.behindFold = behindFold

	-- A waypoint outlives its quest otherwise. Turned in, abandoned or just
	-- dismissed, the quest drops out of this list and nothing else would ever
	-- retire the arrow - and an arrow still pointing at the boars of a quest you
	-- handed in half an hour ago is how you stop trusting the arrow at all.
	-- This is the one place that sees all three of those happen.
	local routed = A.Nav:Routed()
	if routed then
		local live = false
		for _, q in ipairs(quests) do
			if q.questID == routed then live = true break end
		end
		if not live then A.Nav:Clear() end
	end

	-- ACTIVE: the quest you focused (WoW Forever), or on Classic Era the one
	-- TomTom is routing to - there is nothing else there that means it.
	-- Read again: the block above may just have cleared the route.
	local activeID = A.Quest.FocusedID() or A.Nav:Routed()
	-- Elsewhere: listed under a zone that is not this one.
	local here = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText())
	if here == "" then here = nil end
	for _, q in ipairs(quests) do
		q.active = (activeID ~= nil and q.questID == activeID)
		q.elsewhere = (here ~= nil and q.zone ~= nil and q.zone ~= here)
	end

	-- RETRACTED, the tail carries the active quest, or for 2 s one whose
	-- objective just moved. The quests stay laid out on the strand underneath,
	-- so coming back down is the same trunk that went up.
	local moved = Tail.Diff(quests)
	Tail.active = nil
	for _, q in ipairs(quests) do
		if q.active then Tail.active = q end
	end
	if moved and self.collapsed then
		Tail.flash = { q = moved.q, line = moved.line, left = Tail.flashFor }
	elseif Tail.flash then
		-- The same quest, fresh from this scan; gone if it left the list.
		local id = Tail.flash.q.questID
		Tail.flash.q = nil
		for _, q in ipairs(quests) do
			if q.questID == id then Tail.flash.q = q end
		end
		if not Tail.flash.q then Tail.flash = nil end
	end
	if not self.collapsed then Tail.flash = nil end
	Tail.Draw()

	-- THE ROOM ON THE STRAND, not just a count. Ten is the design's most, and
	-- the screen can be shorter than ten quests (6a's own spacing ran ten off a
	-- 1080 screen); what does not fit folds into one "+n" node, with room kept
	-- for it - a tracker that silently drops the quest you are looking for is
	-- worse than one that admits it ran out of room.
	-- The overflow node exists before the room is asked: the Quest Log node
	-- above an item takes less of the strand, and the trunk can only see that
	-- with one there.
	local more = self.more or ItemNode(MORE, 290)
	self.more = more
	local room = Trunk():Room()
	local shown, used = 0, 0
	for i, q in ipairs(quests) do
		local s = StepOf(q)
		local reserve = (i < #quests) and STEP or 0
		-- Not even the first if it would run off the screen: then the
		-- "+n" node is all there is, which still opens the log.
		if i > (cfg.max or 10) or (room and used + s + reserve > room) then break end
		shown, used = i, used + s
	end
	local hidden = #quests - shown

	self.nodes = self.nodes or {}
	self.nodesShown = {}
	for i = 1, math.max(shown, #self.nodes) do
		local key = "quest" .. i
		local node = self.nodes[i]
		if not node and i <= shown then
			node = ItemNode(key, 200 + i)
			node.onClick = function(n, button) RowClicked(n.holder, button) end
			self.nodes[i] = node
		end
		if node then
			local q = (i <= shown) and quests[i] or nil
			if q then q.itemID, q.itemIcon = Items.For(q) end
			node.quest, node.text = q, nil
			local h = node.holder
			h.quest, h.index, h.questID, h.questTitle = q, q and q.index, q and q.questID, q and q.title
			node.step = q and StepOf(q) or STEP
			self.nodesShown[key] = q ~= nil
		end
	end

	-- QUESTS THE CLIENT WOULD NOT NAME, or the ones that did not fit. A folded
	-- zone header hides its quests from GetQuestLogTitle entirely, so the trunk
	-- would show nothing and look broken; say it instead. The overflow opens the
	-- log at the FIRST quest it stands for, held rather than recomputed on the
	-- click, because log indices renumber as quests come and go.
	more.onClick = MoreClicked
	more.quest, more.moreQuest, more.step = nil, nil, STEP
	more.holder.quest = nil
	if shown == 0 and (behindFold or 0) > 0 then
		more.text = A.F(L.questtracker.behind_fold_d, behindFold)
		self.nodesShown[MORE] = true
	elseif hidden > 0 then
		more.text = A.F(L.trunk.more_d, hidden)
		more.moreQuest = quests[shown + 1]
		self.nodesShown[MORE] = true
	else
		more.text = nil
	end

	self.quests = quests
	self.hidden = hidden
	self.shown = shown
	Trunk():Refresh()
end

--- Retract the World trunk into the pill (true), or bring it back down. A
--  fight does this, and so do `/lattice world retract` and the tour.
function QT:SetCollapsed(v)
	self.collapsed = v and true or false
	if not self.collapsed then Tail.flash = nil end
	self:Refresh()
	Trunk():SetRetracted(self.collapsed)
end

function QT:ToggleCollapsed()
	-- Bringing it down by hand during a fight means you wanted it out; do not
	-- let the combat restore undo that decision on the way out.
	self._preCombat = nil
	self:SetCollapsed(not self.collapsed)
end

-- ---------------------------------------------------------------------------
-- module lifecycle
-- ---------------------------------------------------------------------------

function QT:OnEnable()
	-- A real boolean from the start. Three places read this and one of them uses
	-- nil to mean something else entirely.
	if self.collapsed == nil then self.collapsed = false end

	-- No mover of its own: the quests are nodes on the World trunk, which goes
	-- where the minimap goes. A layout string that still names `quests` loads,
	-- and the name is ignored (Core/Layout.lua keeps it known).

	local function refresh() QT:Refresh() end
	-- Taking off and landing: the tail and the item buttons go and come back.
	A.Trunk:OnFlight("questtracker", function() if QT.enabled then QT:Refresh() end end)
	A:RegisterEvent(self, "QUEST_LOG_UPDATE", refresh)
	A:RegisterEvent(self, "QUEST_WATCH_UPDATE", refresh)
	A:RegisterEvent(self, "UNIT_QUEST_LOG_CHANGED", refresh)
	-- Focus changes from anywhere - our menu, an objective click, Blizzard's own
	-- map - and the strip has to follow. An unknown event on Classic Era is
	-- refused quietly by A:RegisterEvent.
	A:RegisterEvent(self, "SUPER_TRACKING_CHANGED", refresh)
	A:RegisterEvent(self, "QUEST_ACCEPTED", refresh)
	A:RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", refresh)
	-- Which quests are "elsewhere" changes with the subzone too.
	A:RegisterEvent(self, "ZONE_CHANGED", refresh)

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
		-- The one moment in a fight a secure frame can still move: the active
		-- quest's item goes to the tail now or not at all. See Items.Place.
		Items.window = true
		local ok, err = pcall(QT.SetCollapsed, QT, true)
		Items.window = nil
		if not ok then error(err, 0) end
	end)
	-- Changes across a loading screen are the client catching up, not
	-- objectives moving (the Quest Log keeps the same gate).
	A:RegisterEvent(self, "LOADING_SCREEN_ENABLED", function() Tail.loading = true end)
	A:RegisterEvent(self, "LOADING_SCREEN_DISABLED", function()
		Tail.loading = false
		QT:Refresh()
	end)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
		local cfg = A.Config:Module("questtracker")
		if cfg.combatCollapse and QT._preCombat ~= nil then
			Items.dirty = nil
			QT:SetCollapsed(QT._preCombat)
			QT._preCombat = nil
		elseif Items.dirty then
			-- An item that changed in the fight, put right now it is over.
			Items.dirty = nil
			QT:Refresh()
		end
	end)
	-- An item picked up, used up or handed over.
	A:RegisterEvent(self, "BAG_UPDATE_DELAYED", refresh)
	A:RegisterEvent(self, "BAG_UPDATE_COOLDOWN", function()
		for _, node in ipairs(QT.nodes or {}) do
			if node.itemButton and node.itemButton:IsShown() then Items.Paint(node.itemButton) end
		end
	end)

	-- ONE SWEEP AT THE START. A zone folded in some earlier session - before this
	-- addon, or in Questie - is invisible here and cannot be undone here, and it
	-- empties the tracker. Cleared once, on the way in and after each loading
	-- screen; never from the scan itself, which would undo the player's own
	-- folds in the same frame that they made them.
	--
	-- ONE REGISTRATION for the loading screen. There were two, and an owner gets
	-- one handler per event, so the second replaced the first and Blizzard's
	-- tracker was never hidden again after a loading screen.
	ExpandCollapsedZones()
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		QT:HideBlizzard()
		ExpandCollapsedZones()
		QT:Refresh()
	end)

	self:HideBlizzard()
	self:OnConfigChanged()
end

function QT:OnDisable()
	-- `enabled` is already false, so every quest node reads unavailable.
	for _, node in ipairs(self.nodes or {}) do HideObjectives(node.holder) end
	W.CloseMenu()
	-- The rest of the trunk is not ours to leave up in the pill.
	self.collapsed, self._preCombat, Tail.flash = false, nil, nil
	Tail.Draw()
	Trunk():Refresh()
	Trunk():SetRetracted(false, true)
end

function QT:OnSkinChanged()
	self:Refresh()
end

function QT:OnConfigChanged()
	self:Refresh()
end
