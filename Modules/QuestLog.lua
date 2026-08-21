--[[--------------------------------------------------------------------------
	AetherUI :: QuestLog

	Concept 3b: a 1240x820 glass window replacing Blizzard's quest log entirely.
	Header (book mark, title, count chip, search), a 430-wide list pane grouped by
	zone with difficulty-coloured level chips, and a detail pane carrying the
	title, its pills, the summary, an objective card and the description.

	This is a replacement, not a reskin. Blizzard's QuestLogFrame is a 353x424
	single-pane frame; there is no arrangement of it that becomes this.

	Reading the quest log on Classic Era
	------------------------------------
	  numEntries, numQuests = GetNumQuestLogEntries()
	  title, level, questTag, isHeader, isCollapsed, isComplete, frequency, questID
	      = GetQuestLogTitle(index)

	Three things about that tuple that are easy to get wrong and that produce
	plausible-looking bad UI rather than an error:

	  * `isComplete` is a NUMBER, not a boolean: 1 complete, -1 failed, nil or 0
	    in progress. `if isComplete then` is true for a *failed* quest.
	  * `questTag` (third) is a LOCALIZED STRING - "Dungeon", "Elite", "PvP" - not
	    a numeric group size. It is display-ready, which is exactly what the tag
	    pill in the concept wants, so it is shown verbatim rather than mapped.
	  * headers are entries in the same list and carry a junk `level`. Branch on
	    isHeader before touching anything else.

	Selection is global mutable state, and it is not ours
	----------------------------------------------------
	`SelectQuestLogEntry` sets one hidden client-side cursor that Blizzard's own
	code also writes - `QuestLog_OnEvent` fires on every QUEST_LOG_UPDATE and is
	NOT gated on the frame being visible, so it can move the selection out from
	under us even with its frame hidden. That is why HideBlizzard below calls
	UnregisterAllEvents rather than just Hide.

	Belt and braces on top of that: the list is built entirely from the
	INDEX-TAKING getters, which need no selection at all -

	  GetNumQuestLeaderBoards(questIndex)
	  GetQuestLogLeaderBoard(objectiveIndex, questIndex)

	Only the description needs the selection, because `GetQuestLogQuestText` has
	no confirmed indexed form on 1.15. So exactly one quest - the selected one -
	is ever read that way, in one synchronous pass, and never in a loop.

	  questDescription, questObjectives = GetQuestLogQuestText()

	Note the order: description FIRST. Blizzard's own frame reads it the other way
	round into confusingly-named font strings, which is a good way to talk
	yourself into the wrong one.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local QL = A:NewModule("questlog")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- ---------------------------------------------------------------------------
-- geometry, in the concept deck's 1920-wide pixels
--
-- The whole window is drawn at profile.scale (0.71 = 768/1080), so these are the
-- deck's numbers unchanged. Do not "correct" them to virtual units.
-- ---------------------------------------------------------------------------

local WIN_W, WIN_H     = 1240, 820
local WIN_CORNER       = W.PANEL_CORNER   -- shared; see Core/Widgets.lua

-- THE SHARED NUMBERS. 15a gives one header height and one body padding
-- for every panel in the interface, and a window of ours is a panel like
-- any other - the only reason these were local was that they were written
-- before there was anywhere to put them.
local HEAD_H           = W.PANEL_HEAD_H
local HEAD_PAD_X       = W.PANEL_PAD
local HEAD_GAP         = 14

local LIST_W           = 430
local LIST_PAD_L, LIST_PAD_R = 18, 12
local LIST_PAD_Y       = 16
local ZONE_GAP         = 14          -- between zone groups
local ZONE_H           = 22
local ROW_H            = 31
local ROW_GAP          = 3
local ROW_PAD_X        = 12
local ROW_CORNER       = 14
local CHIP_W, CHIP_H   = 30, 17

local DET_PAD_X, DET_PAD_Y = 32, 26
-- How far the reading well reaches outside its scroll frame. Named because
-- the footer has to be told about it: the buttons sit a block's gap below
-- the well's edge, not below the scroll frame's.
local DET_WELL_OUT = 12
local DET_GAP          = 18
local CARD_CORNER      = 16
local CARD_PAD_X, CARD_PAD_Y = 18, 14
local BAR_H            = 4

local SEARCH_W, SEARCH_H = 220, 30
local SCROLL_STEP      = 42          -- pixels per wheel click

local CONFIRM_W, CONFIRM_MIN_H, CONFIRM_PAD = 420, 170, 24
local CARD_H, CARD_ICON = 50, 34
local CARD_GAP, CARD_RADIUS = 10, 14
local FOOT_H, FOOT_PAD, BTN_H = 34, 14, 34
local BTN_GAP = 10

-- ---------------------------------------------------------------------------
-- quest log adapter
-- ---------------------------------------------------------------------------

local function NumEntries()
	if not GetNumQuestLogEntries then return 0, 0 end
	local entries, quests = GetNumQuestLogEntries()
	return entries or 0, quests or 0
end

--- title, level, questTag, isHeader, isCollapsed, isComplete, questID
local function LogTitle(index)
	if not GetQuestLogTitle then return nil end
	local title, level, questTag, isHeader, isCollapsed, isComplete, _, questID =
		GetQuestLogTitle(index)
	if not title then return nil end

	if not questID and GetQuestIDFromLogIndex then
		local ok, id = pcall(GetQuestIDFromLogIndex, index)
		if ok then questID = id end
	end

	return title, level, questTag, isHeader, isCollapsed, isComplete, questID
end

--- Which of Blizzard's five difficulty bands a quest level falls in.
--
--  The bands live in Palette now that the nameplate badge asks the same question
--  - see Palette:DifficultyBand for the thresholds and why they are not
--  GetQuestDifficultyColor's. Kept as a local and as QL.DifficultyBand because
--  the tracker resolves through the latter and the log calls it per row.
local function DifficultyBand(level)
	return A.Palette:DifficultyBand(level)
end

QL.DifficultyBand = DifficultyBand

--- Objective lines plus a completion fraction, read WITHOUT touching the
--  selection. Both getters take the quest index as their last argument.
--
--  Blizzard guards both returns for nil and so do we: during a zone transition
--  the client hands back empty text and a nil `finished` for objectives that are
--  perfectly fine a second later.
local function Objectives(index)
	local lines, done, total = {}, 0, 0
	if not GetNumQuestLeaderBoards or not GetQuestLogLeaderBoard then
		return lines, nil
	end

	local n = GetNumQuestLeaderBoards(index) or 0
	for j = 1, n do
		local text, objType, finished = GetQuestLogLeaderBoard(j, index)
		if text and text ~= "" then
			lines[#lines + 1] = {
				text = text,
				kind = objType,
				finished = finished and true or false,
			}
			local cur, max = string.match(text, "(%d+)%s*/%s*(%d+)")
			cur, max = tonumber(cur), tonumber(max)
			if cur and max and max > 0 then
				done, total = done + math.min(cur, max), total + max
			else
				done, total = done + (finished and 1 or 0), total + 1
			end
		end
	end

	return lines, (total > 0) and (done / total) or nil
end

--- Every header is expanded before a scan, because a collapsed one hides its
--  quests from GetQuestLogTitle entirely and this window groups by zone itself -
--  a collapsed header would simply lose quests with nothing on screen to say so.
--
--  Guarded three ways, because ExpandQuestHeader fires QUEST_LOG_UPDATE and this
--  runs *from* a QUEST_LOG_UPDATE handler: only when something is actually
--  collapsed, never re-entrantly, and iterating downward because expanding a
--  header renumbers everything below it.
--  The player's own collapsed zones are remembered and put back when the window
--  closes. That state is shared with Blizzard's log and with Questie, so leaving
--  every zone expanded would be reaching into someone else's UI and changing it
--  permanently for the sake of ours.
local expanding = false

local function ExpandAll()
	if expanding or not ExpandQuestHeader then return false end

	local entries = NumEntries()
	local collapsed = {}
	for index = 1, entries do
		local title, _, _, isHeader, isCollapsed = LogTitle(index)
		if isHeader and isCollapsed then collapsed[#collapsed + 1] = title end
	end
	if #collapsed == 0 then return false end

	-- Restored in a `pcall` epilogue rather than after the loop. A throw inside
	-- the loop but outside the inner pcall would otherwise wedge the guard on for
	-- the session, and every later open would silently skip expanding.
	expanding = true
	pcall(function()
		-- Downward: expanding a header renumbers everything below it.
		for index = entries, 1, -1 do
			local _, _, _, isHeader, isCollapsed = LogTitle(index)
			if isHeader and isCollapsed then pcall(ExpandQuestHeader, index) end
		end
	end)
	expanding = false

	QL._collapsedZones = collapsed
	return true
end

local function RestoreHeaders()
	local zones = QL._collapsedZones
	-- Cleared *after* the guard, not before: a re-entrant call that bailed out
	-- would otherwise throw the pending restore away and leave the player's zones
	-- expanded for good.
	if not zones or #zones == 0 or not CollapseQuestHeader or expanding then return end
	QL._collapsedZones = nil

	local wanted = {}
	for _, name in pairs(zones) do wanted[name] = true end

	expanding = true
	pcall(function()
		local entries = NumEntries()
		for index = entries, 1, -1 do
			local title, _, _, isHeader = LogTitle(index)
			if isHeader and wanted[title] then pcall(CollapseQuestHeader, index) end
		end
	end)
	expanding = false
end

--- What identifies a quest across a rebuild.
--
--  The questID, which on 1.15 is the eighth return of GetQuestLogTitle. The
--  index fallback exists because the module already spends a pcall on
--  GetQuestIDFromLogIndex for clients that answer differently, and a selection
--  model that compares `nil == nil` is worse than useless: EnsureSelection would
--  declare the selection valid, RefreshList would light nothing, RefreshDetail
--  would draw a quest anyway, and every row would become unclickable. One helper
--  in all six places, so the comparison can never be accidentally nil-on-nil.
local function SelKey(e)
	if not e then return nil end
	local id = e.questID
	if id ~= nil then return id end
	local i = e.index or e.questIndex
	return i and ("i" .. tostring(i)) or nil
end

--- The whole log as a flat display list: zone rows and quest rows interleaved,
--  in log order, which is already zone order.
--
--  `filter` is the search string, lowercased. A zone whose every quest is
--  filtered out drops its header too, or the list ends up as a column of empty
--  headings.
local function Collect(filter)
	local out = {}
	local entries, quests = NumEntries()

	local pendingZone, zoneCount = nil, 0

	for index = 1, entries do
		local title, level, questTag, isHeader, _, isComplete, questID = LogTitle(index)
		if title then
			if isHeader then
				pendingZone = title
				zoneCount = 0
			else
				local match = true
				if filter and filter ~= "" then
					match = string.find(string.lower(title), filter, 1, true) ~= nil
				end
				if match then
					if pendingZone then
						out[#out + 1] = { kind = "zone", name = pendingZone }
						pendingZone = nil
					end
					zoneCount = zoneCount + 1
					-- isComplete is 1 / -1 / nil-or-0, never a boolean.
					local complete = (isComplete == 1)
					local failed   = (type(isComplete) == "number" and isComplete < 0)
					local lines, pct = Objectives(index)
					if pct == nil and complete then pct = 1 end
					out[#out + 1] = {
						kind     = "quest",
						index    = index,
						questID  = questID,
						title    = title,
						level    = level,
						tag      = questTag,
						complete = complete,
						failed   = failed,
						lines    = lines,
						pct      = pct,
						band     = DifficultyBand(level),
					}
					out[#out].key = SelKey(out[#out])
				end
			end
		end
	end

	return out, quests
end

--- The description, which is the one thing that needs the selection.
--
--  One quest, one synchronous pass, no loop. Returns description and the
--  objective summary in Blizzard's order, which is description FIRST.
--  Cached per selection key, and the cursor is only moved when the quest being read
--  actually changes. Without the cache every rebuild - and there is one per
--  keystroke in the search box - would drag the client's one global selection
--  somewhere new for no reason.
local textCache = {}

local function DetailText(index, key)
	key = key or ("i" .. tostring(index))
	local hit = textCache[key]
	if hit then return hit[1], hit[2] end

	-- The caller has already put the cursor on this quest. Selecting again here
	-- would move it a second time for a cache hit that needs no cursor at all.
	if not GetQuestLogQuestText then return nil, nil end
	local ok, description, summary = pcall(GetQuestLogQuestText)
	if not ok then return nil, nil end

	-- Only a real answer is cached. A successful call can still return nil for
	-- several seconds after a loading screen, and caching that pins the quest to
	-- an empty description for as long as the cache lives - which is exactly the
	-- window the first rebuild after LOADING_SCREEN_DISABLED lands in.
	if type(description) == "string" and description ~= "" then
		textCache[key] = { description, summary }
	end
	return description, summary
end

--- Quest text never changes for a given quest, but the *log* does, so the cache
--  is dropped whenever the set of quests might have.
local function DropTextCache()
	textCache = {}
end

--- The log index a quest is at RIGHT NOW, or nil if it is no longer there.
--
--  Everything that leaves the draw and comes back later - the footer buttons,
--  a reward card's tooltip, the abandon confirmation - has to go through this.
--  `entries` is a draw-scoped snapshot and the `.index` on it is only valid
--  until the next renumber, which any accepted or turned-in quest causes. A
--  stale index does not error: it silently addresses a different quest, or a
--  zone header, and the failure is Share pushing the wrong quest or an abandon
--  dialog naming one quest while destroying another.
--  `title` is the identity of last resort, and it is not optional padding: with
--  no questID to compare, `id == nil` alone would validate ANY quest sitting at
--  the stale index, which is the whole wrong-quest bug wearing a guard's hat.
local function IndexForQuest(questID, fallback, title)
	local function isOurs(i)
		if not i or i <= 0 then return false end
		local t, _, _, isHeader, _, _, id = LogTitle(i)
		if not t or isHeader then return false end
		if id ~= nil and questID ~= nil then return id == questID end
		return title ~= nil and t == title
	end

	if questID and GetQuestLogIndexByID then
		local ok, i = pcall(GetQuestLogIndexByID, questID)
		if ok and isOurs(i) then return i end
	end
	return isOurs(fallback) and fallback or nil
end

--- Move the client's cursor onto a quest. Everything in the reward block below
--  reads the selection and none of it takes an index, so this has to happen
--  first and nothing may run between it and the reads.
local function SelectQuest(index)
	if not SelectQuestLogEntry or not index then return false end
	return (pcall(SelectQuestLogEntry, index))
end

--- Everything the quest gives, read from the SELECTED quest.
--
--  Two categories, and they are not the same thing: `choices` is the pick-one
--  set the concept draws as cards, `rewards` is the always-given set. A quest
--  can have either, both or neither, and Classic quests routinely have only the
--  second - so drawing only the choices leaves those quests with an empty
--  reward area, which reads as a bug rather than as "no choice to make".
--
--  Deliberately no XP field. Blizzard commented `GetQuestLogRewardXP()` out in
--  their own Classic source with the note "Don't show XP rewards in Classic",
--  and the code path the Era log actually runs has no XP concept at all. The
--  only way to show it is to ship a per-questID database, which is not worth it.
--
--  Honor and player title are TBC-gated in Blizzard's own reward pass, so they
--  are skipped too: on Era they would be two permanently empty rows.
local function Rewards(questID)
	local r = { choices = {}, rewards = {}, money = 0, required = 0, spell = nil }

	local function readInto(list, count, getter, kind)
		if not count or not getter then return end
		for i = 1, count do
			-- numItems is pre-seeded to 1 by Blizzard before the call, because the
			-- client leaves it alone for a single item rather than returning 1.
			local ok, name, texture, numItems, quality, isUsable = pcall(getter, i)
			if ok and (name or texture) then
				list[#list + 1] = {
					index   = i,
					kind    = kind,          -- "choice" | "reward", the index space
					name    = name,
					texture = texture,
					count   = (numItems and numItems > 1) and numItems or nil,
					quality = quality,
					usable  = isUsable ~= false,
				}
			end
		end
	end

	if GetNumQuestLogChoices then
		readInto(r.choices, GetNumQuestLogChoices() or 0, GetQuestLogChoiceInfo, "choice")
	end
	if GetNumQuestLogRewards then
		readInto(r.rewards, GetNumQuestLogRewards() or 0, GetQuestLogRewardInfo, "reward")
	end

	if GetQuestLogRewardMoney then
		local ok, m = pcall(GetQuestLogRewardMoney)
		if ok and type(m) == "number" then r.money = m end
	end
	if GetQuestLogRequiredMoney then
		local ok, m = pcall(GetQuestLogRequiredMoney)
		if ok and type(m) == "number" then r.required = m end
	end

	-- Spell rewards moved to C_QuestInfoSystem and take a questID, not an index.
	-- Classic has at most one per quest, which is Blizzard's own comment.
	if questID and C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardSpells then
		local ok, spells = pcall(C_QuestInfoSystem.GetQuestRewardSpells, questID)
		local id = ok and spells and spells[1]
		if id and C_QuestInfoSystem.GetQuestRewardSpellInfo then
			local ok2, info = pcall(C_QuestInfoSystem.GetQuestRewardSpellInfo, questID, id)
			if ok2 and info then
				r.spell = { spellID = id, name = info.name, texture = info.texture }
			end
		end
	end

	return r
end

--- Copper as the client would draw it. GetCoinTextureString gives the inline
--  coin icons, which is what every other money readout in the game looks like.
local function Money(copper)
	if not copper or copper <= 0 then return nil end
	if GetCoinTextureString then
		local ok, s = pcall(GetCoinTextureString, copper)
		if ok and s then return s end
	end
	local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. "g" end
	if sv > 0 then out[#out + 1] = sv .. "s" end
	if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
	return table.concat(out, " ")
end

-- ---------------------------------------------------------------------------
-- Blizzard frame removal
--
-- Hiding is not enough, and this is the single most expensive thing to get
-- wrong here. QuestLog_OnEvent is registered on QuestLogFrame itself and runs on
-- every QUEST_LOG_UPDATE whether or not the frame is visible; it calls
-- QuestLog_Update, which calls QuestLog_SetFirstValidSelection whenever the
-- selection is 0, which calls SelectQuestLogEntry. A hidden frame quietly
-- moving the selection cursor is how you get a wrong-quest bug that never
-- reproduces on demand.
--
-- Deliberately NOT reparenting to a hider. Reparenting changes a frame's
-- coordinate space and this client has Edit Mode, which persists positions;
-- unregistering plus hiding plus the OnShow hook achieves the same thing without
-- touching anyone's parents.
--
-- The QuestLog_* globals are left intact on purpose. Questie calls
-- QuestLog_Update() and QuestLog_UpdateQuestDetails() unconditionally after
-- opening the log, and a nil global there is an error in someone else's addon.
-- ---------------------------------------------------------------------------

--- The events Blizzard's own QuestLog_OnLoad registers. Saved before they are
--  torn off so turning this module back off gives the player a working quest log
--  rather than an inert one.
local BLIZZ_QUESTLOG_EVENTS = {
	"QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UPDATE_FACTION",
	"UNIT_QUEST_LOG_CHANGED", "GROUP_ROSTER_UPDATE", "PARTY_MEMBER_ENABLE",
	"PARTY_MEMBER_DISABLE", "PLAYER_LOGIN", "PLAYER_LEVEL_UP",
}

function QL:HideBlizzard()
	local f = _G.QuestLogFrame
	if not f or (f.IsForbidden and f:IsForbidden()) then return end

	-- Remember what was on before tearing it off. UnregisterAllEvents is the only
	-- thing that actually stops QuestLog_OnEvent, but it is also irreversible
	-- unless the list is written down first - and an addon that leaves the player
	-- with no quest log after being switched off is worse than one that never
	-- replaced it.
	if not self._blizzEvents then
		local saved = {}
		for _, e in pairs(BLIZZ_QUESTLOG_EVENTS) do
			local ok, on = pcall(f.IsEventRegistered, f, e)
			if ok and on then saved[#saved + 1] = e end
		end
		self._blizzEvents = saved
	end

	-- The OnShow hook can never be removed once installed, so it is gated on a
	-- flag rather than on its own existence. Without this, disabling the module
	-- leaves a frame that hides itself the instant anything shows it - which
	-- looks exactly like "the L key stopped working" and survives until /reload.
	f.__aetherSuppress = true

	-- One pcall per call. Bundling these meant a throw on the first silently
	-- skipped the rest, and the frame stayed on screen with no error to show for
	-- it.
	pcall(f.UnregisterAllEvents, f)
	pcall(f.Hide, f)

	if f.HookScript and not f.__aetherQuestLogHooked then
		f.__aetherQuestLogHooked = true
		pcall(f.HookScript, f, "OnShow", function(self)
			if self.__aetherSuppress then self:Hide() end
		end)
	end

	-- Take it out of the panel manager, or the left slot stays reserved for a
	-- frame that will never be shown and the character sheet lands in the wrong
	-- place. ShowUIPanel/HideUIPanel short-circuit to a plain Show/Hide once a
	-- frame has no "area" attribute.
	if _G.UIPanelWindows and _G.UIPanelWindows["QuestLogFrame"] then
		self._panelWindow = _G.UIPanelWindows["QuestLogFrame"]
		_G.UIPanelWindows["QuestLogFrame"] = nil
	end
end

function QL:RestoreBlizzard()
	local f = _G.QuestLogFrame
	if f and not (f.IsForbidden and f:IsForbidden()) then
		f.__aetherSuppress = nil
		for _, e in pairs(self._blizzEvents or {}) do
			pcall(f.RegisterEvent, f, e)
		end
		self._blizzEvents = nil
	end

	if self._panelWindow and _G.UIPanelWindows then
		_G.UIPanelWindows["QuestLogFrame"] = self._panelWindow
		self._panelWindow = nil
	end
end

--- Take over every route into the quest log at once.
--
--  ToggleQuestLog is a plain insecure Lua global and it is the single funnel for
--  all three: the L key (Bindings.xml runs `ToggleQuestLog();`), the
--  QuestLogMicroButton's OnClick, and any other addon that wants the log open.
--  Replacing it captures all of them.
--
--  Chosen over SetOverrideBindingClick specifically because binding overrides
--  are protected and hard-blocked in combat, and a quest log you cannot open
--  mid-fight is a worse bug than the one this avoids.
function QL:HookToggle()
	if self._origToggle then return end
	self._origToggle = _G.ToggleQuestLog or false
	_G.ToggleQuestLog = function() QL:Toggle() end
end

function QL:RestoreToggle()
	if self._origToggle == nil then return end
	_G.ToggleQuestLog = self._origToggle or nil
	self._origToggle = nil
end

--- The micro button's lit state is driven by UpdateMicroButtons reading
--  QuestLogFrame:IsVisible(). Ours is a different frame, so nothing would ever
--  light it again unless we do it ourselves.
local function SetMicroButtonState(shown)
	local b = _G.QuestLogMicroButton
	if not b or not b.SetButtonState then return end
	if b.IsForbidden and b:IsForbidden() then return end
	pcall(b.SetButtonState, b, shown and "PUSHED" or "NORMAL", shown and 1 or nil)
end

--- ...and it has to be reasserted, not just set once on show.
--
--  UpdateMicroButtons runs on a great many unrelated events - bag changes, level
--  up, any panel opening - and every one of them reads QuestLogFrame:IsVisible(),
--  which is now permanently false. Without this the button lights up when the
--  window opens and then goes dark on its own a moment later.
function QL:HookMicroButtons()
	if self._microHooked or not hooksecurefunc then return end
	if not _G.UpdateMicroButtons then return end
	local ok = pcall(hooksecurefunc, "UpdateMicroButtons", function()
		if not QL.enabled then return end
		SetMicroButtonState(QL.win and QL.win:IsShown())
	end)
	-- Flagged only on success, or a failed install is never retried.
	self._microHooked = ok
end

-- ---------------------------------------------------------------------------
-- small parts
-- ---------------------------------------------------------------------------

--- A tinted capsule carrying short text: the level chip, the count chip, the
--  type pill. It lives in Widgets because the quest tracker wears the same level
--  chip, and one that drifted between the two would read as two widgets.
local BuildPill = W.Pill

--- A one-pixel rule. Hairlines are everywhere in this concept and they are the
--  first thing to go blurry, so they are snapped to the physical grid.
-- Kept as a local for the call sites, but it is the shared one underneath:
-- one ink and one physical pixel, and the pixel is the part that was wrong.
-- See W.PaintHairline.
local function BuildHairline(parent, upright)
	return W.Hairline(parent, upright)
end

-- ONE INK, shared with every other line in the interface - see
-- W.PaintHairline. These carried their own fraction of glassEdge and came
-- out fainter than the tab rails, which is a separator you cannot see.
local function ColorHairline(t)
	W.PaintHairline(t)
end

-- ---------------------------------------------------------------------------
-- window construction
-- ---------------------------------------------------------------------------

local function BuildHeader(win)
	local head = CreateFrame("Frame", nil, win)
	head:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
	head:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
	head:SetHeight(HEAD_H)
	win.head = head

	-- The concept's book glyph. There is no vector drawing in the WoW UI and no
	-- icon in our atlas for it, so it is the chevron rotated into a bookmark:
	-- a mark at the left edge of the header reads as "this is the log" the same
	-- way, and inventing a whole icon texture for one glyph is not worth a
	-- texture-cache round trip.
	local mark = head:CreateTexture(nil, "ARTWORK")
	mark:SetTexture(Media.texture.flat)
	mark:SetSize(3, 20)
	mark:SetPoint("LEFT", head, "LEFT", HEAD_PAD_X, 0)
	head.mark = mark

	head.title = W.Text(head, "qlHeading", "LEFT")
	head.title:SetPoint("LEFT", mark, "RIGHT", HEAD_GAP - 2, 0)
	head.title:SetText("Quest Log")

	head.count = BuildPill(head, "qlCount", { height = 22, padX = 13 })
	head.count:SetPoint("LEFT", head.title, "RIGHT", HEAD_GAP, 0)

	-- close ---------------------------------------------------------------
	-- The shared one. It was 22 square with its own hover here, 28 on the
	-- bags, 18 on the Toolbox and a bare cross on the client's windows.
	local close = W.CloseButton(head, { onClick = function() QL:Hide() end })
	close:SetPoint("RIGHT", head, "RIGHT", -HEAD_PAD_X, 0)
	head.close = close

	-- search ---------------------------------------------------------------
	-- A ROUNDED RECTANGLE, not a capsule. A pill's two caps come out of a
	-- 256-texel texture, and at thirty pixels tall they are minified more
	-- than eight times with no mipmap behind them - which is the crunch on
	-- the ends of this field. The same fix the chat tabs and the check box
	-- already carry.
	local search = Glass.CreatePanel(head, {
		corner = W.WELL_CORNER, fill = "glassSoft", edge = "glassEdge",
	})
	search:SetSize(SEARCH_W, SEARCH_H)
	search:SetPoint("RIGHT", close, "LEFT", -HEAD_GAP, 0)
	head.search = search

	local box = CreateFrame("EditBox", nil, search)
	box:SetPoint("LEFT", search, "LEFT", 15, 0)
	box:SetPoint("RIGHT", search, "RIGHT", -12, 0)
	box:SetHeight(SEARCH_H)
	box:SetAutoFocus(false)
	Media:SetFont(box, "qlSearch")
	W.Color(box, Palette.c.text)
	-- Escape must close the search, not the window, while the cursor is in it.
	box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnTextChanged", function(self) QL:SetFilter(self:GetText()) end)
	search.box = box

	search.placeholder = W.Text(search, "qlSearch", "LEFT")
	search.placeholder:SetPoint("LEFT", box, "LEFT", 0, 0)
	search.placeholder:SetText("Search quests\226\128\166")   -- ellipsis

	search:EnableMouse(true)
	search:SetScript("OnMouseDown", function() box:SetFocus() end)

	head.rule = BuildHairline(head)
	head.rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
	head.rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)

	return head
end

--- The link for a reward, which is nil more often than you would like: the
--  client returns nothing for an item it has not cached yet, and ElvUI guards
--  for exactly this on this client.
local function RewardLink(card)
	if card.rewardType == "spell" then
		if not GetSpellLink or not card.spellID then return nil end
		local ok, link = pcall(GetSpellLink, card.spellID)
		return ok and link or nil
	end
	if not GetQuestLogItemLink or not card.kind or not card.itemIndex then return nil end
	local ok, link = pcall(GetQuestLogItemLink, card.kind, card.itemIndex)
	return ok and link or nil
end

local function RewardCardEnter(self)
	if not GameTooltip then return end
	-- Both tooltip calls read the global cursor, so put it back on this quest
	-- first - and resolve the index now rather than trusting the one this card
	-- was drawn with, which a renumber since the draw would have invalidated.
	local index = IndexForQuest(self.questID, self.questIndex, self.questTitle)
	if not index then return end
	SelectQuest(index)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.rewardType == "spell" then
		if GameTooltip.SetSpellByID and self.spellID then
			pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID)
		end
	elseif GameTooltip.SetQuestLogItem then
		pcall(GameTooltip.SetQuestLogItem, GameTooltip, self.kind, self.itemIndex)
	end
	GameTooltip:Show()
	self:SetEdgeColor(Palette.c.cardEdgeHi)
end

local function RewardCardLeave(self)
	if GameTooltip then GameTooltip:Hide() end
	self:SetEdgeColor(Palette.c.cardEdge)
end

--- Shift to link, ctrl to preview - via IsModifiedClick rather than a raw
--  IsShiftKeyDown, so the player's own modifier bindings are respected. Both
--  branches are what Blizzard's own reward buttons do.
local function RewardCardClick(self)
	-- Nothing here moves the cursor until a modifier says we are actually going
	-- to read something. A plain left-click on a reward does nothing, and doing
	-- nothing should not reach into the client's global selection to do it.
	if not IsModifiedClick then return end
	local dressup, chatlink = IsModifiedClick("DRESSUP"), IsModifiedClick("CHATLINK")
	if not dressup and not chatlink then return end

	local index = IndexForQuest(self.questID, self.questIndex, self.questTitle)
	if not index then return end
	SelectQuest(index)

	if dressup then
		if self.rewardType ~= "spell" and DressUpItemLink then
			local link = RewardLink(self)
			if link then pcall(DressUpItemLink, link) end
		end
		return
	end

	if chatlink then
		local link = RewardLink(self)
		if not link then
			-- The client has not cached the item yet. Saying so beats a click that
			-- silently does nothing.
			A:Print("that reward is still loading - try again in a moment.")
			return
		end
		local insert = _G.ChatEdit_InsertLink
			or (_G.ChatFrameUtil and _G.ChatFrameUtil.InsertLink)
		if insert then pcall(insert, link) end
	end
end

local function BuildRewardCard(parent)
	local card = Glass.CreatePanel(parent, {
		frameType = "Button", corner = CARD_RADIUS, fill = "glassSoft",
	})
	card:SetHeight(CARD_H)

	card.slot = W.CreateSlot(card, { size = CARD_ICON })
	card.slot:SetPoint("LEFT", card, "LEFT", 8, 0)

	card.label = W.Text(card, "qlObjName", "LEFT")
	card.label:SetPoint("LEFT", card.slot, "RIGHT", CARD_GAP, 0)
	if card.label.SetWordWrap then card.label:SetWordWrap(false) end

	card:SetScript("OnEnter", RewardCardEnter)
	card:SetScript("OnLeave", RewardCardLeave)
	card:SetScript("OnClick", RewardCardClick)
	return card
end

--- A footer button. `style` is "filled", "outline" or "danger"; the three the
--  concept draws, and the only three.
local function BuildButton(parent, style, label)
	-- W.CreateButton, not CreatePill. A capsule's two caps come out of a
	-- 256-texel texture, so at this height they are minified more than ten
	-- times and the client does not mipmap - the same crunch the tooltip badge
	-- and the check box both had. And it is the shape every other pressable
	-- thing in this interface uses, which is the point of it living in one place.
	local b = W.CreateButton(parent, {})
	b:SetHeight(BTN_H)
	b._style = style

	b.label = W.Text(b, style == "filled" and "qlBtn" or "qlBtnAlt", "CENTER")
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)

	function b:Restyle()
		local c = Palette.c
		if self._style == "filled" then
			self:SetFillColor(self._over and c.btnFillHi or c.btnFill)
			self:SetEdgeShown(false)
			W.Color(self.label, c.btnFillText)
		elseif self._style == "danger" then
			self:SetFillColor(self._over and c.dangerHover or { 0, 0, 0, 0 })
			self:SetEdgeShown(true)
			self:SetEdgeColor(c.dangerEdge)
			W.Color(self.label, c.dangerText)
		else
			self:SetFillColor(self._over and c.btnHover or { 0, 0, 0, 0 })
			self:SetEdgeShown(true)
			self:SetEdgeColor(c.btnEdge)
			W.Color(self.label, c.text)
		end

		-- A BUTTON YOU CANNOT PRESS IS STILL A BUTTON YOU CAN READ. This dimmed
		-- the whole frame to 0.4, which multiplies the LABEL as well - and an
		-- outline button's label is already the dim ink, so 0.55 by 0.4 is 0.22
		-- and Share simply vanished over anything bright. Share is off more
		-- often than it is on: you have to be grouped for it.
		--
		-- So the frame stays at full strength and the INK goes quiet instead -
		-- one step down the ladder, not two. It went to textFaint, which is the
		-- soft ink at 0.38, and over the footer's own glass that is a button
		-- with a border and no word in it. Enabled is the bright ink and
		-- disabled is the dim one: still a word, plainly not for pressing.
		if self._disabled then W.Color(self.label, c.textDim) end
	end

	function b:SetLabel(text)
		self.label:SetText(text or "")
		self:SetWidth(math.ceil(self.label:GetStringWidth() or 0) + 44)
	end

	function b:SetDisabled(off)
		self._disabled = off and true or false
		if self.Disable then
			if off then self:Disable() else self:Enable() end
		end
		self:Restyle()
	end

	--- Clicks go through here rather than through SetScript directly, so the
	--  disabled state is enforced by us. Relying on the client to suppress
	--  OnClick means the guard lives somewhere this codebase cannot test.
	function b:SetAction(fn)
		self._action = fn
		self:SetScript("OnClick", function(self2)
			if self2._disabled then return end
			if self2._action then self2._action(self2) end
		end)
	end

	b:SetScript("OnEnter", function(self) self._over = true self:Restyle() end)
	b:SetScript("OnLeave", function(self) self._over = false self:Restyle() end)

	b:SetLabel(label)
	b:Restyle()
	return b
end

-- Defined further down with the rest of the list rows; the pane owning their
-- pools is built up here.
local BuildZoneRow, BuildQuestRow

local function BuildPanes(win)
	local list = CreateFrame("Frame", nil, win)
	list:SetPoint("TOPLEFT", win.head, "BOTTOMLEFT", 0, 0)
	list:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
	list:SetWidth(LIST_W)
	win.list = list

	-- UPRIGHT, so the shared one knows which way to be a pixel thick.
	list.rule = BuildHairline(list, true)
	list.rule:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
	list.rule:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)

	-- Six, because this column has only twelve to its right before the
	-- divider between the list and the detail.
	local scroll = W.Scroller(list, SCROLL_STEP, { outset = 6 })
	scroll:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_PAD_L, -LIST_PAD_Y)
	scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -LIST_PAD_R, LIST_PAD_Y)
	scroll.child:SetWidth(LIST_W - LIST_PAD_L - LIST_PAD_R)
	list.scroll = scroll

	-- Two pools, one per row type, each keyed by its own display position.
	--
	-- A single pool indexed by display position cannot work: a slot's *kind*
	-- alternates as zone headings come and go under a filter, so every keystroke
	-- in the search box would retire a built row and construct another.
	list.zoneRows  = W.Pool(function() return BuildZoneRow(scroll.child) end)
	list.questRows = W.Pool(function() return BuildQuestRow(scroll.child) end)

	local detail = CreateFrame("Frame", nil, win)
	detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 0, 0)
	detail:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
	win.detail = detail

	-- A PAGE OF READING, which is what the well was invented for: the
	-- description ran to the edges of the pane with nothing saying where it
	-- stopped. Twelve, out of this pane's own thirty-two.
	local dscroll = W.Scroller(detail, SCROLL_STEP, { outset = DET_WELL_OUT })
	dscroll:SetPoint("TOPLEFT", detail, "TOPLEFT", DET_PAD_X, -DET_PAD_Y)
	-- The scroll region stops above the footer. The footer is pinned rather than
	-- scrolled with the content: it is the same three actions wherever you are in
	-- a long description, and a Abandon button that scrolls off is a Abandon
	-- button you cannot find.
	-- AND CLEARS THE BUTTONS. The well's own edge is what separates the two
	-- now, so the reading has to stop a block's gap above the row of
	-- actions - it used to stop two pixels above them, which reads as the
	-- buttons being part of the description.
	dscroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -DET_PAD_X,
		DET_PAD_Y + FOOT_H + DET_WELL_OUT + W.PANEL_GAP)
	local dw = WIN_W - LIST_W - DET_PAD_X * 2
	dscroll.child:SetWidth(dw)
	detail.scroll = dscroll
	detail.width = dw

	local body = dscroll.child

	detail.title = W.Text(body, "qlTitle", "LEFT")
	detail.title:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	detail.title:SetHeight(30)

	detail.levelPill = BuildPill(body, "qlChip", { edge = true, padX = 10 })
	detail.typePill  = BuildPill(body, "qlTag",  { edge = true, padX = 10 })

	detail.summary = W.Text(body, "qlSummary", "LEFT")
	detail.summary:SetPoint("LEFT", body, "LEFT", 0, 0)
	detail.summary:SetWidth(dw)
	detail.summary:SetJustifyV("TOP")
	if detail.summary.SetSpacing then detail.summary:SetSpacing(4) end

	-- objective card ------------------------------------------------------
	local card = Glass.CreatePanel(body, { corner = CARD_CORNER, fill = "glassSoft" })
	card:SetWidth(dw)
	card.rows = {}
	detail.card = card

	detail.descLabel = W.Text(body, "qlLabel", "LEFT")
	detail.descLabel:SetText(Media:Track("DESCRIPTION", 1))

	detail.desc = W.Text(body, "qlBody", "LEFT")
	detail.desc:SetWidth(dw)
	detail.desc:SetJustifyV("TOP")
	if detail.desc.SetSpacing then detail.desc:SetSpacing(5) end

	-- reward section, inside the scroll ------------------------------------
	detail.rewardLabel = W.Text(body, "qlLabel", "LEFT")
	detail.rewardCards = {}
	detail.giveLabel = W.Text(body, "qlLabel", "LEFT")
	detail.giveCards = {}
	detail.money = W.Text(body, "qlObjName", "LEFT")
	detail.required = W.Text(body, "qlObjName", "LEFT")

	-- footer, pinned ---------------------------------------------------------
	local foot = CreateFrame("Frame", nil, detail)
	foot:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", DET_PAD_X, DET_PAD_Y)
	foot:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -DET_PAD_X, DET_PAD_Y)
	foot:SetHeight(FOOT_H)
	detail.foot = foot

	-- NO RULE ABOVE THE BUTTONS. There was one, and with the description now
	-- sitting in a well of its own the two draw as a doubled line with a
	-- sliver between them - a stray hairline across the foot of the pane.
	-- The well's bottom edge is the separation.

	foot.track = BuildButton(foot, "filled", "Track quest")
	foot.track:SetPoint("LEFT", foot, "LEFT", 0, 0)
	foot.track:SetAction(function() QL:ToggleTracked() end)

	foot.share = BuildButton(foot, "outline", "Share")
	foot.share:SetPoint("LEFT", foot.track, "RIGHT", BTN_GAP, 0)
	foot.share:SetAction(function() QL:ShareQuest() end)

	foot.abandon = BuildButton(foot, "danger", "Abandon")
	foot.abandon:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
	foot.abandon:SetAction(function() QL:AskAbandon() end)

	detail.empty = W.Text(body, "qlSummary", "CENTER")
	detail.empty:SetWidth(dw)
	detail.empty:SetText("No quest selected.")
	detail.empty:Hide()

	return list, detail
end

local function Build()
	local win = Glass.CreatePanel(UIParent, {
		name   = "AetherUIQuestLog",
		corner = WIN_CORNER,
		shadow = A.db.profile.glass.shadow,
		fill   = "glassStrong",
	})
	-- ...then deepened to a READING fill. The window carries a quest description
	-- and a list of twenty titles over whatever the world is doing behind it, and
	-- at the control-surface opacity the clutter competes with every line. Chat
	-- has always sat deeper than the bars and capsules for exactly this reason;
	-- this is the same helper, so the two stay in step.
	win:SetFillColor(Palette:ReadingFill())
	win:SetSize(WIN_W, WIN_H)
	win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	win:SetFrameStrata("HIGH")
	win:EnableMouse(true)                -- swallow clicks; do not click the world through it
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", function(self) self:StartMoving() end)
	win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	win:Hide()

	BuildHeader(win)
	BuildPanes(win)

	-- Every route into the window goes through OnShow, including ones we do not
	-- own, so both the expansion and the refresh live here rather than in
	-- QL:Show.
	--
	-- ExpandAll and RestoreHeaders MUST be on the same pair of scripts. With
	-- expand on the function and restore on the frame they stop alternating, and
	-- two things break: a window opened by Questie or a /run draws a log that
	-- still has collapsed headers, so whole zones are missing; and hiding UIParent
	-- for a cinematic fires OnHide - which re-collapses - while IsShown() stays
	-- true, so the rebuild that follows renders against the collapsed log and the
	-- zones do not come back.
	win:SetScript("OnShow", function()
		SetMicroButtonState(true)
		if QL.dirty or not QL.entries then QL:Refresh() end
	end)
	win:SetScript("OnHide", function()
		SetMicroButtonState(false)
		win.head.search.box:ClearFocus()
		RestoreHeaders()
		-- A confirmation left floating over a closed window is a click waiting to
		-- abandon something the player has stopped looking at.
		QL:CloseConfirm()
	end)

	-- ESC, handled on the frame rather than through UISpecialFrames.
	--
	-- UISpecialFrames is registered as well, because other things walk it, but it
	-- cannot be the mechanism: CloseSpecialWindows closes through HideUIPanel,
	-- which is combat-blocked for addons on this client and fails *silently* with
	-- an "Interface action blocked" message. Pressing escape mid-fight would
	-- leave the window open and blame the player's UI. A direct Hide() is the
	-- only combat-safe close, which is the same reason nothing here goes near
	-- ShowUIPanel.
	--
	-- Keyboard input is propagated by default and only swallowed for the one key
	-- we act on, or the window would eat every movement key while it is open.
	win:EnableKeyboard(true)
	if win.SetPropagateKeyboardInput then win:SetPropagateKeyboardInput(true) end
	win:SetScript("OnKeyDown", function(self, key)
		if key ~= "ESCAPE" then
			self:SetPropagateKeyboardInput(true)
			return
		end
		-- Swallowed either way. Handing ESC onward reaches CloseSpecialWindows,
		-- which closes through the combat-blocked HideUIPanel - so mid-fight the
		-- window would stay open and the player would get an "Interface action
		-- blocked" message instead.
		self:SetPropagateKeyboardInput(false)
		if self.head.search.box:HasFocus() then
			self.head.search.box:ClearFocus()
		else
			QL:Hide()
		end
	end)

	return win
end

-- ---------------------------------------------------------------------------
-- list rows
-- ---------------------------------------------------------------------------

-- A fill of zero alpha rather than hiding the nine fill textures: a row changes
-- selection state on every refresh, and nine SetShown calls a row buys nothing
-- over one vertex colour.
local CLEAR = { 0, 0, 0, 0 }

function BuildZoneRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ZONE_H)

	row.text = W.Text(row, "qlZone", "LEFT")
	row.text:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 6)

	row.rule = BuildHairline(row)
	row.rule:SetPoint("LEFT", row.text, "RIGHT", 8, 0)
	row.rule:SetPoint("RIGHT", row, "RIGHT", -2, 0)

	row.kind = "zone"
	return row
end

local function QuestRowClicked(row)
	if row.selKey then QL:Select(row.selKey) end
end

function BuildQuestRow(parent)
	local row = Glass.CreatePanel(parent, { corner = ROW_CORNER, fill = "glass" })
	row:SetHeight(ROW_H)
	row:SetEdgeShown(false)
	row:EnableMouse(true)
	row:SetScript("OnMouseUp", QuestRowClicked)

	row.chip = BuildPill(row, "qlChip", { height = CHIP_H })
	row.chip:SetPoint("LEFT", row, "LEFT", ROW_PAD_X, 0)

	row.title = W.Text(row, "qlRow", "LEFT")
	row.title:SetPoint("LEFT", row.chip, "RIGHT", 10, 0)
	if row.title.SetWordWrap then row.title:SetWordWrap(false) end

	row.tag = BuildPill(row, "qlTag", { height = 16, edge = true, padX = 9 })
	row.tag:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD_X, 0)
	row.tag:Hide()

	row:SetScript("OnEnter", function(self)
		if not self._selected then
			self:SetFillColor(Palette.c.rowHover)
		end
	end)
	row:SetScript("OnLeave", function(self)
		self:SetFillColor(self._selected and Palette.c.rowSel or CLEAR)
	end)

	row.kind = "quest"
	return row
end

-- ---------------------------------------------------------------------------
-- the three actions
-- ---------------------------------------------------------------------------

--- Track routes through QuestTracker's own set rather than Blizzard's watch
--  list. Blizzard's caps at five and refuses a quest with no objectives; ours
--  is uncapped by construction, and the tracker is the thing actually drawing
--  the rows, so it is the one that has to agree with this button.
--- The shown quest's current index, re-resolved rather than remembered.
function QL:ShownIndex()
	local q = self.shown
	if not q then return nil end
	return IndexForQuest(q.questID, q.index, q.title)
end

function QL:ToggleTracked()
	local quest = self.shown
	if not quest or not quest.questID then return end
	local QT = A:GetModule("questtracker")
	if not QT or not QT.SetTracked then return end

	QT.SetTracked(quest.questID, not QT.IsTracked(quest.questID))
	if QT.enabled and QT.Refresh then pcall(QT.Refresh, QT) end
	self:RefreshFooter()
end

function QL:ShareQuest()
	if not QuestLogPushQuest then return end
	local index = self:ShownIndex()
	if not index then return end
	-- Selection-scoped, like everything else in the action set.
	if not SelectQuest(index) then return end
	pcall(QuestLogPushQuest)
end

-- ---------------------------------------------------------------------------
-- abandon
--
-- The dangerous sequence in the whole module, so it is written out longhand.
--
--   SelectQuestLogEntry(index)  -- put the cursor on the quest
--   SetAbandonQuest()           -- LATCH it; nothing after this moves the target
--   GetAbandonQuestName()       -- valid only after the latch
--   GetAbandonQuestItems()      -- nil, or a preformatted string of item names
--   AbandonQuest()              -- acts on the latch, not on the live cursor
--
-- Two things about that which are not obvious and which decide the design:
--
--   * SetAbandonQuest LATCHES. Blizzard's own flow puts unbounded user
--     think-time between the latch and AbandonQuest - their confirm popup - and
--     QUEST_LOG_UPDATE fires freely in that gap. So the cursor moving after the
--     latch is safe. The dangerous window is between Select and SetAbandonQuest,
--     which is why those two are adjacent with nothing at all in between.
--   * Blizzard's popup has NO OnCancel. Clicking No leaves the latch armed. A
--     bare AbandonQuest() later would then act on a stale latch, and the failure
--     mode is abandoning a quest the player never chose. So the confirm path
--     re-latches from the stored questID immediately before firing, rather than
--     trusting the latch it set when the dialog opened.
-- ---------------------------------------------------------------------------

local function BuildConfirm()
	local dim = CreateFrame("Frame", nil, UIParent)
	dim:SetAllPoints(UIParent)
	dim:SetFrameStrata("FULLSCREEN_DIALOG")
	-- Clicks outside the box are swallowed AND cancel. Swallowing without
	-- cancelling would leave the player unable to click anything on screen while
	-- a modal they may have opened by accident sits in the middle of it.
	dim:EnableMouse(true)

	-- The scrim. It is what makes the dialog legible - a translucent panel over a
	-- translucent window over a lit world has nothing to sit against - and it is
	-- also what says "this is modal" without a word.
	dim.scrim = dim:CreateTexture(nil, "BACKGROUND")
	dim.scrim:SetTexture(Media.texture.flat)
	dim.scrim:SetAllPoints(dim)

	dim:SetScript("OnMouseDown", function(_, button)
		-- Left button only. Click-outside-to-dismiss firing on a right-click means
		-- an aimed camera drag cancels the dialog under the cursor.
		if button == nil or button == "LeftButton" then QL:CloseConfirm() end
	end)
	dim:Hide()

	local box = Glass.CreatePanel(dim, {
		corner = 16, shadow = 1, fill = "dialogFill", edge = "glassEdgeHi",
	})
	box:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	box:SetSize(CONFIRM_W, CONFIRM_MIN_H)
	box:EnableMouse(true)                -- or a click on the box cancels it
	box:SetFrameStrata("FULLSCREEN_DIALOG")
	box:SetFrameLevel(dim:GetFrameLevel() + 10)
	dim.box = box

	box.text = W.Text(box, "qlObjName", "CENTER")
	box.text:SetPoint("TOPLEFT", box, "TOPLEFT", CONFIRM_PAD, -26)
	-- One anchor plus an explicit width, not an anchor pair AND a width: the two
	-- compute to the same number today and can silently drift apart tomorrow.
	box.text:SetWidth(CONFIRM_W - CONFIRM_PAD * 2)
	box.text:SetJustifyV("TOP")
	if box.text.SetWordWrap then box.text:SetWordWrap(true) end
	if box.text.SetSpacing then box.text:SetSpacing(4) end

	box.yes = BuildButton(box, "danger", "Abandon")
	box.yes:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -CONFIRM_PAD, 22)

	box.no = BuildButton(box, "outline", "Cancel")
	box.no:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", CONFIRM_PAD, 22)

	box.no:SetAction(function() QL:CloseConfirm() end)
	box.yes:SetAction(function() QL:ConfirmAbandon() end)

	-- Escape closes it. ONLY escape is swallowed.
	--
	-- Setting SetPropagateKeyboardInput(false) once and leaving it there turned
	-- this into a total input lockout: no movement, no keybinds, no chat, for as
	-- long as a dialog reachable mid-fight was on screen. Blizzard's own
	-- StaticPopup swallows nothing but the keys it acts on, and neither does this.
	dim:EnableKeyboard(true)
	if dim.SetPropagateKeyboardInput then dim:SetPropagateKeyboardInput(true) end
	dim:SetScript("OnKeyDown", function(self, key)
		if key ~= "ESCAPE" then
			if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
			return
		end
		if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
		QL:CloseConfirm()
	end)

	return dim
end

function QL:CloseConfirm()
	if self.confirm then self.confirm:Hide() end
	-- Both, not just the id. ConfirmAbandon's identity guard was wrapped in
	-- `if questID then`, so an index left armed here would have been fired at
	-- with no check at all on a client that returns no questID.
	--
	-- The client's own abandon latch is deliberately NOT cleared - there is no
	-- API to clear it, which is precisely why ConfirmAbandon re-latches rather
	-- than trusting the one AskAbandon set.
	self.abandonID, self.abandonIndex, self.abandonTitle = nil, nil, nil
end

function QL:AskAbandon()
	local quest = self.shown
	if not quest or not SetAbandonQuest then return end

	local index = self:ShownIndex()
	if not index then
		A:Print("that quest is no longer in your log.")
		return
	end
	if not SelectQuest(index) then return end
	pcall(SetAbandonQuest)                       -- adjacent to the Select, always

	local name = quest.title
	if GetAbandonQuestName then
		local ok, n = pcall(GetAbandonQuestName)
		if ok and n and n ~= "" then name = n end
	end

	local items
	if GetAbandonQuestItems then
		local ok, i = pcall(GetAbandonQuestItems)
		if ok then items = i end
	end

	self.abandonID = quest.questID
	self.abandonIndex = index
	-- The title from OUR snapshot, not from GetAbandonQuestName. That call reads
	-- the latch, which was set from the index we are trying to validate - so
	-- comparing the two would be comparing a wrong answer against itself.
	self.abandonTitle = quest.title

	self.confirm = self.confirm or BuildConfirm()
	local c = Palette.c
	local body = "Abandon " .. Palette:Ink("text", name) .. "?"
	if items then
		body = body .. "\n\nYou will lose: "
			.. Palette:Ink("dangerText", items)
	end
	local box = self.confirm.box
	box.text:SetText(body)
	-- Primary text, not dim. It is a question the player has to read and answer.
	W.Color(box.text, c.text)

	-- Grow to fit. A fixed height meant a quest with a long "you will lose" list
	-- drew its text straight through the buttons.
	local textH = math.ceil(box.text:GetStringHeight() or 0)
	box:SetSize(CONFIRM_W, math.max(CONFIRM_MIN_H,
		26 + textH + 24 + BTN_H + 22))

	-- Drawn at the profile scale, like the window it is covering. Without this it
	-- renders ~40% larger than everything under it.
	box:SetScale(A.db.profile.scale)
	-- The offset is in the box's OWN units, so it has to be divided back through
	-- the scale or the dialog drifts toward centre as the scale comes down.
	local sc = A.db.profile.scale
	box:ClearAllPoints()
	box:SetPoint("CENTER", UIParent, "CENTER", 0, 60 / ((sc and sc > 0) and sc or 1))
	-- Full shadow regardless of the profile setting: this one has to lift off the
	-- window behind it, and the profile value governs ambient chrome, not modals.
	box:SetShadow(1)
	box:ApplySkin("dialogFill", "glassEdgeHi")

	local sc2 = Palette.c.scrim
	self.confirm.scrim:SetVertexColor(sc2[1], sc2[2], sc2[3], sc2[4] or 0.45)
	box.yes:Restyle()
	box.no:Restyle()
	self.confirm:Show()
end

function QL:ConfirmAbandon()
	local questID, index, title = self.abandonID, self.abandonIndex, self.abandonTitle
	self:CloseConfirm()
	if not AbandonQuest or not index then return end

	-- Re-latch from the stored questID rather than trusting the one set when the
	-- dialog opened. The log can renumber while the dialog is up - a quest turned
	-- in by a party member, an escort completing - so the index is resolved fresh
	-- from the ID, and Select/SetAbandonQuest stay adjacent.
	-- One resolver, which already refuses a header, a nil title, an id mismatch
	-- and - with no id - a title mismatch. Better a refused abandon than a
	-- confident wrong one.
	local fresh = IndexForQuest(questID, index, title)
	if not fresh then
		A:Print("that quest is no longer in your log - nothing was abandoned.")
		return
	end

	if not SelectQuest(fresh) then return end
	if SetAbandonQuest then pcall(SetAbandonQuest) end
	pcall(AbandonQuest)

	if PlaySound and _G.SOUNDKIT and _G.SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST then
		pcall(PlaySound, _G.SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST)
	end

	DropTextCache()
	self.selectedID = nil
	self:Invalidate()
	self:Flush()
end

-- ---------------------------------------------------------------------------
-- refresh
-- ---------------------------------------------------------------------------

function QL:RefreshList()
	local win = self.win
	if not win then return end

	local c = Palette.c
	local list = win.list
	local child = list.scroll.child
	local width = LIST_W - LIST_PAD_L - LIST_PAD_R

	local entries = self.entries or {}

	win.head.count:SetLabel(string.format("%d / %d", self.numQuests or 0,
		_G.MAX_QUESTLOG_QUESTS or _G.MAX_QUESTS or 20))
	win.head.count:SetColors(c.rowSel, c.textDim)

	local y, zoneN, questN = 0, 0, 0
	for i = 1, #entries do
		local e = entries[i]
		local row
		if e.kind == "zone" then
			zoneN = zoneN + 1
			row = list.zoneRows:Get(zoneN)
		else
			questN = questN + 1
			row = list.questRows:Get(questN)
		end
		-- Draw-scoped only. Rows are pooled and `entries` is rebuilt wholesale on
		-- every draw, so a handle held across a refresh points at a row that now
		-- belongs to a different quest.
		e.row = row
		row:ClearAllPoints()
		row:SetWidth(width)
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)

		if e.kind == "zone" then
			-- string.upper is ASCII-only in the client's locale, so uppercasing a
			-- localized zone name leaves accented letters lowercase in the middle
			-- of a tracked capital heading, and does nothing at all on ruRU.
			local name = e.name
			if not name:find("[\128-\255]") then name = string.upper(name) end
			row.text:SetText(Media:Track(name, 1))
			W.Color(row.text, c.textDim)
			ColorHairline(row.rule)
			-- Groups after the first get the gap above them; the first sits flush
			-- with the top padding or the pane looks unbalanced.
			if i > 1 then
				row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(y + ZONE_GAP))
				y = y + ZONE_GAP
			end
			y = y + ZONE_H
		else
			local band = c.questDiff[e.band] or c.questDiff.difficult
			row.chip:SetLabel(tostring(e.level or "?"), CHIP_W)
			row.chip:SetColors(band.bg, band.text)

			row.title:SetText(e.title)

			-- The title's right edge is re-anchored rather than left pinned to the
			-- tag pill. An anchor to a hidden frame still resolves, so leaving it
			-- there would clip every untagged title at whatever width the pill
			-- happened to have the last time it was used.
			row.title:ClearAllPoints()
			row.title:SetPoint("LEFT", row.chip, "RIGHT", 10, 0)
			if e.tag and e.tag ~= "" then
				row.tag:SetLabel(e.tag)
				row.tag:SetColors(c.infoBg, c.info)
				row.tag:SetEdgeColor(c.infoEdge)
				row.tag:Show()
				row.title:SetPoint("RIGHT", row.tag, "LEFT", -8, 0)
			else
				row.tag:Hide()
				row.title:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD_X, 0)
			end

			local selected = (self.selectedID ~= nil and e.key == self.selectedID)
			row._selected = selected
			row:SetFillColor(selected and c.rowSel or CLEAR)
			W.Restyle(row.title, selected and "qlRowSel" or "qlRow")
			-- A failed quest is the one state the concept has no swatch for, and
			-- it is the one you most need to see. It takes the danger colour;
			-- everything else reads as normal body text, selected or not.
			W.Color(row.title, e.failed and c.danger or (selected and c.text or c.textDim))
			row.questIndex, row.questID, row.selKey = e.index, e.questID, e.key
			y = y + ROW_H + ROW_GAP
		end

		row:Show()
	end

	list.zoneRows:HideFrom(zoneN + 1)
	list.questRows:HideFrom(questN + 1)

	child:SetSize(width, math.max(1, y))
	list.scroll:Clamp()
end

local function CardRow(card, i, width)
	local row = card.rows[i]
	if row then return row end

	row = CreateFrame("Frame", nil, card)
	row:SetHeight(20)
	row.name = W.Text(row, "qlObjName", "LEFT")
	row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.count = W.Text(row, "qlObjCount", "RIGHT")
	row.count:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.name:SetPoint("RIGHT", row.count, "LEFT", -10, 0)
	if row.name.SetWordWrap then row.name:SetWordWrap(false) end

	card.rows[i] = row
	return row
end

function QL:RefreshDetail()
	local win = self.win
	if not win then return end

	local c = Palette.c
	local d = win.detail
	local dw = d.width

	local quest
	local entries = self.entries or {}
	for i = 1, #entries do
		local e = entries[i]
		if e.kind == "quest" and e.key ~= nil and e.key == self.selectedID then quest = e break end
	end

	self.shown = quest

	if not quest then
		d.title:Hide() d.levelPill:Hide() d.typePill:Hide()
		d.summary:Hide() d.card:Hide() d.descLabel:Hide() d.desc:Hide()
		d.rewardLabel:Hide() d.giveLabel:Hide() d.money:Hide() d.required:Hide()
		-- `cd`, not `c`: `c` is the palette three lines below, and a loop variable
		-- shadowing it in a function this long is a landmine.
		for _, cd in pairs(d.rewardCards) do cd:Hide() end
		for _, cd in pairs(d.giveCards) do cd:Hide() end
		d.foot:Hide()
		d.empty:ClearAllPoints()
		d.empty:SetPoint("TOP", d.scroll.child, "TOP", 0, -60)
		W.Color(d.empty, c.textFaint)
		d.empty:Show()
		d.scroll.child:SetHeight(120)
		return
	end
	d.empty:Hide()

	local y = 0

	-- title row -----------------------------------------------------------
	d.title:SetText(quest.title)
	W.Color(d.title, c.text)
	d.title:ClearAllPoints()
	d.title:SetPoint("TOPLEFT", d.scroll.child, "TOPLEFT", 0, -y)
	d.title:Show()

	local band = c.questDiff[quest.band] or c.questDiff.difficult
	d.levelPill:SetLabel("Lv " .. tostring(quest.level or "?"))
	d.levelPill:SetColors(band.bg, band.text)
	d.levelPill:SetEdgeColor({ band.text[1], band.text[2], band.text[3], 0.35 })
	d.levelPill:ClearAllPoints()
	d.levelPill:SetPoint("LEFT", d.title, "LEFT",
		math.ceil(d.title:GetStringWidth() or 0) + 12, 0)
	d.levelPill:Show()

	if quest.tag and quest.tag ~= "" then
		d.typePill:SetLabel(quest.tag)
		d.typePill:SetColors(c.infoBg, c.info)
		d.typePill:SetEdgeColor(c.infoEdge)
		d.typePill:ClearAllPoints()
		d.typePill:SetPoint("LEFT", d.levelPill, "RIGHT", 8, 0)
		d.typePill:Show()
	else
		d.typePill:Hide()
	end
	y = y + 30 + DET_GAP

	-- Everything below reads the client's global cursor and none of it takes an
	-- index, so it moves here ONCE and nothing is allowed to run in between.
	SelectQuest(quest.index)

	local description, summary = DetailText(quest.index, quest.key)

	if summary and summary ~= "" then
		d.summary:SetText(summary)
		W.Color(d.summary, c.textDim)
		d.summary:ClearAllPoints()
		d.summary:SetPoint("TOPLEFT", d.scroll.child, "TOPLEFT", 0, -y)
		d.summary:SetWidth(dw)
		d.summary:Show()
		y = y + math.ceil(d.summary:GetStringHeight() or 0) + DET_GAP
	else
		d.summary:Hide()
	end

	-- objective card ------------------------------------------------------
	local lines = quest.lines or {}
	if #lines > 0 or quest.pct then
		local inner = dw - CARD_PAD_X * 2
		local cy = 0
		for j = 1, #lines do
			local row = CardRow(d.card, j, inner)
			local text, count = lines[j].text, nil
			-- "Kill 5 boars: 3/5" reads better split: the thing on the left, the
			-- count right-aligned on the other side of the card, as drawn.
			local head, cur, max = string.match(lines[j].text, "^(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
			if head then text, count = head, cur .. " / " .. max end

			row.name:SetText(text)
			W.Color(row.name, lines[j].finished and c.textFaint or c.text)
			row.count:SetText(count or (lines[j].finished and "done" or ""))
			W.Color(row.count, lines[j].finished and c.health[1] or c.textDim)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", d.card, "TOPLEFT", CARD_PAD_X, -(CARD_PAD_Y + cy))
			row:SetPoint("RIGHT", d.card, "RIGHT", -CARD_PAD_X, 0)
			row:Show()
			cy = cy + 20
		end
		for j = #lines + 1, #d.card.rows do d.card.rows[j]:Hide() end

		if quest.pct then
			if not d.card.bar then
				d.card.bar = W.CreateBar(d.card, { height = BAR_H, smooth = false, bgAlpha = 0.12 })
			end
			d.card.bar:ClearAllPoints()
			d.card.bar:SetPoint("TOPLEFT", d.card, "TOPLEFT", CARD_PAD_X, -(CARD_PAD_Y + cy + 6))
			d.card.bar:SetPoint("RIGHT", d.card, "RIGHT", -CARD_PAD_X, 0)
			d.card.bar:SetMinMaxValues(0, 1)
			d.card.bar:SetValue(math.max(0.02, quest.pct))
			d.card.bar:SetColors(quest.complete and c.health or c.xp)
			d.card.bar:Show()
			cy = cy + 6 + BAR_H
		elseif d.card.bar then
			d.card.bar:Hide()
		end

		d.card:ClearAllPoints()
		d.card:SetPoint("TOPLEFT", d.scroll.child, "TOPLEFT", 0, -y)
		d.card:SetWidth(dw)
		d.card:SetHeight(cy + CARD_PAD_Y * 2)
		d.card:Show()
		y = y + cy + CARD_PAD_Y * 2 + DET_GAP
	else
		d.card:Hide()
	end

	-- description ---------------------------------------------------------
	if description and description ~= "" then
		W.Color(d.descLabel, c.textDim)
		d.descLabel:ClearAllPoints()
		d.descLabel:SetPoint("TOPLEFT", d.scroll.child, "TOPLEFT", 0, -y)
		d.descLabel:Show()
		y = y + 18

		d.desc:SetText(description)
		W.Color(d.desc, c.textDim)
		d.desc:ClearAllPoints()
		d.desc:SetPoint("TOPLEFT", d.scroll.child, "TOPLEFT", 0, -y)
		d.desc:SetWidth(dw)
		d.desc:Show()
		-- The trailing gap is NOT optional, even though it looks like it. Every
		-- other section here adds one; the description did not, and got away with
		-- it for exactly as long as it was the last thing on the page. Pass two
		-- put the reward cards after it and the omission became a heading sitting
		-- on top of the final line of prose.
		y = y + math.ceil(d.desc:GetStringHeight() or 0) + DET_GAP
	else
		d.descLabel:Hide()
		d.desc:Hide()
	end

	-- rewards -------------------------------------------------------------
	local rw = Rewards(quest.questID)

	-- The spell reward rides along with the guaranteed items: it is something the
	-- quest gives you, not something you choose between.
	local gives = rw.rewards
	if rw.spell then
		gives = { unpack(rw.rewards) }
		gives[#gives + 1] = {
			rewardType = "spell", spellID = rw.spell.spellID,
			name = rw.spell.name, texture = rw.spell.texture,
		}
	end

	local function drawCards(pool, list, labelFS, labelText)
		if #list == 0 then
			labelFS:Hide()
			for _, cd in pairs(pool) do cd:Hide() end
			return
		end

		W.Color(labelFS, c.textDim)
		labelFS:SetText(Media:Track(labelText, 1))
		labelFS:ClearAllPoints()
		labelFS:SetPoint("TOPLEFT", d.scroll.child, "TOPLEFT", 0, -y)
		labelFS:Show()
		y = y + 18

		local x, rowTop = 0, y
		for i = 1, #list do
			local item = list[i]
			local card = pool[i]
			if not card then
				card = BuildRewardCard(d.scroll.child)
				pool[i] = card
			end

			card.questIndex = quest.index
			card.questID    = quest.questID
			card.questTitle = quest.title
			card.kind       = item.kind
			card.itemIndex  = item.index
			card.rewardType = item.rewardType or "item"
			card.spellID    = item.spellID

			card.slot:SetIcon(item.texture)
			card.label:SetText(item.name or "")
			-- Blizzard tints an unusable reward's icon red rather than hiding it,
			-- because "you cannot use this" is information, not a reason to omit.
			card.slot.icon:SetVertexColor(item.usable == false and 0.9 or 1,
				item.usable == false and 0.3 or 1, item.usable == false and 0.3 or 1)
			card.slot.count:SetText(item.count and tostring(item.count) or "")
			card:SetFillColor(c.cardBg)
			card:SetEdgeColor(c.cardEdge)
			W.Color(card.label, c.text)

			local w = 8 + CARD_ICON + CARD_GAP
				+ math.ceil(card.label:GetStringWidth() or 0) + 16
			-- The wrap test cannot fire for the first card in a row, so a single
			-- name wider than the pane would run off the edge and be clipped by
			-- the scroll frame. Clamp instead, and let the label truncate.
			if w > dw then w = dw end
			if x > 0 and x + w > dw then
				x, rowTop = 0, rowTop + CARD_H + CARD_GAP
			end
			card:SetWidth(w)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", d.scroll.child, "TOPLEFT", x, -rowTop)
			card:Show()
			x = x + w + CARD_GAP
		end
		for i = #list + 1, #pool do pool[i]:Hide() end

		y = rowTop + CARD_H + DET_GAP
	end

	drawCards(d.rewardCards, rw.choices, d.rewardLabel, "CHOOSE A REWARD")
	drawCards(d.giveCards,  gives,       d.giveLabel,   "YOU WILL RECEIVE")

	local moneyText = Money(rw.money)
	if moneyText then
		d.money:SetText("Reward: " .. moneyText)
		W.Color(d.money, c.textDim)
		d.money:ClearAllPoints()
		d.money:SetPoint("TOPLEFT", d.scroll.child, "TOPLEFT", 0, -y)
		d.money:Show()
		y = y + 20
	else
		d.money:Hide()
	end

	local reqText = Money(rw.required)
	if reqText then
		d.required:SetText("Required: " .. reqText)
		-- Red when you cannot afford it, which is Blizzard's own treatment and
		-- the one field here whose absence could actually cost the player gold.
		local short = GetMoney and (GetMoney() or 0) < rw.required
		W.Color(d.required, short and c.danger or c.textDim)
		d.required:ClearAllPoints()
		d.required:SetPoint("TOPLEFT", d.scroll.child, "TOPLEFT", 0, -y)
		d.required:Show()
		y = y + 20
	else
		d.required:Hide()
	end

	d.scroll.child:SetSize(dw, math.max(1, y))
	d.scroll:Clamp()

	self:RefreshFooter()
end

--- The footer's three states. Split out because two things other than a redraw
--  change them: tracking a quest, and the party you are in.
function QL:RefreshFooter()
	local win = self.win
	if not win then return end
	local d, quest = win.detail, self.shown
	if not quest then d.foot:Hide() return end
	d.foot:Show()

	local index = self:ShownIndex()
	if not index then
		-- All three, not two. Leaving Track bright is the only button on screen
		-- claiming an action it cannot carry out.
		d.foot.track:SetDisabled(true)
		d.foot.share:SetDisabled(true)
		d.foot.abandon:SetDisabled(true)
		return
	end

	local QT = A:GetModule("questtracker")
	local tracked = QT and QT.IsTracked and quest.questID
		and QT.IsTracked(quest.questID)
	d.foot.track:SetLabel(tracked and "Untrack" or "Track quest")
	d.foot.track:SetDisabled(false)

	-- GetQuestLogPushable is selection-scoped, and this runs from GROUP_ROSTER_UPDATE
	-- as well as from a redraw - by which time the snapshot's index may address
	-- something else entirely - which is why the index above is re-resolved
	-- rather than remembered, and why the cursor only moves after it validates.
	SelectQuest(index)

	-- Blizzard's own gate is pushable AND in a group - the call answers "can this
	-- quest ever be shared", not "can it be shared right now". Without the group
	-- half the button looks live while solo and silently does nothing.
	local pushable = false
	if GetQuestLogPushable then
		local ok, v = pcall(GetQuestLogPushable)
		pushable = ok and v and true or false
	end
	local grouped = IsInGroup and IsInGroup() or false
	d.foot.share:SetDisabled(not (pushable and grouped))

	d.foot.abandon:SetDisabled(false)
end

--- Collect, settle the selection, THEN draw.
--
--  The order is the whole point. Drawing the list before the selection is
--  settled means an auto-chosen quest - first open of a session, or the one
--  after the selected quest is turned in - is shown in full on the right with no
--  row highlighted on the left, because the highlight was painted against a
--  selection that had not been decided yet.
--
--  Nothing is drawn while the window is closed. That is not only an economy: the
--  detail pane moves the client's global selection cursor to read a description,
--  and a restyle or a resolution change with the window shut would otherwise
--  reach out and move it for a window nobody can see.
function QL:Refresh()
	if not self.win then return end
	if not self.win:IsShown() then
		self.dirty = true
		return
	end

	-- Expansion sits here rather than on OnShow so that it covers a rebuild too:
	-- a header collapsed by Blizzard's log or by Questie while our window is open
	-- would otherwise take a whole zone off screen until it was reopened. It
	-- early-returns when nothing is collapsed, so the usual cost is one scan.
	ExpandAll()

	self.entries, self.numQuests = Collect(self.filter)
	self:EnsureSelection()
	self:RefreshList()
	self:RefreshDetail()
	self.dirty = false
end

--- Rebuilds are coalesced onto the shared 0.1s ticker and skipped entirely while
--  the window is closed.
--
--  QUEST_LOG_UPDATE fires constantly - Questie's own source calls it out as
--  "this event fires very often" and wraps a whole suppression machine around
--  it. Since this window is shut most of the time, the cheapest correct answer
--  is to mark it dirty and rebuild when it next opens.
function QL:Invalidate()
	self.dirty = true
	if self.win and self.win:IsShown() and not self.loading then
		A:RegisterTicker(self, QL.Flush)
	end
end

function QL:Flush()
	A:UnregisterTicker(self)
	-- `loading` is re-checked here and not only in Invalidate. A rebuild can be
	-- queued a frame before the loading screen goes up, and running it on the
	-- other side would read the client's transient nil completion flags as real.
	if self.loading then return end
	if self.dirty and self.win and self.win:IsShown() then self:Refresh() end
end

-- ---------------------------------------------------------------------------
-- selection and visibility
-- ---------------------------------------------------------------------------

--- Selection is held as a questID, never as a log index.
--
--  Log indices are not stable: accepting, abandoning or turning in a quest
--  renumbers everything below it, and headers occupy indices too. Holding an
--  index across a rebuild means that the moment you accept a quest in a zone
--  that sorts above the one you were reading, the detail pane silently switches
--  to a different quest with no interaction from you. The index is resolved
--  fresh from the questID on every draw.
function QL:Select(key)
	self.selectedID = key
	self:RefreshList()
	self:RefreshDetail()
end

--- Pick something sensible when the window opens with nothing chosen, or when
--  whatever was chosen has been turned in or filtered away.
function QL:EnsureSelection()
	local entries = self.entries or {}
	if self.selectedID ~= nil then
		for i = 1, #entries do
			local e = entries[i]
			if e.kind == "quest" and e.key == self.selectedID then return end
		end
	end

	self.selectedID = nil
	for i = 1, #entries do
		if entries[i].kind == "quest" then
			self.selectedID = entries[i].key
			return
		end
	end
end

function QL:SetFilter(text)
	text = text and string.lower(text) or ""
	if text == (self.filter or "") then return end
	self.filter = text
	if self.win then
		self.win.head.search.placeholder:SetShown(text == "")
		self:Refresh()
	end
end

--- Deliberately thin. Expanding and refreshing hang off the frame's own OnShow,
--  so a window opened by anything else - Questie resolving ClassicQuestLog and
--  calling ShowUIPanel on it, a /run, another addon - gets the same treatment
--  rather than showing whatever was last drawn, or nothing at all.
function QL:Show()
	if not self.win then return end
	self.win:Show()
end

function QL:Hide()
	if not self.win then return end
	self.win:Hide()
end

function QL:Toggle()
	if not self.win then return end
	if self.win:IsShown() then self:Hide() else self:Show() end
end

-- ---------------------------------------------------------------------------
-- module lifecycle
-- ---------------------------------------------------------------------------

--- ESC routing. Registered as well as the OnKeyDown handler, because other
--  addons walk this list to decide what counts as a closable window - but never
--  relied on, for the combat reason in Build().
local function SetSpecialFrame(on)
	if not _G.UISpecialFrames then return end
	for i = #_G.UISpecialFrames, 1, -1 do
		if _G.UISpecialFrames[i] == "AetherUIQuestLog" then
			if on then return end
			table.remove(_G.UISpecialFrames, i)
		end
	end
	if on then table.insert(_G.UISpecialFrames, "AetherUIQuestLog") end
end

function QL:OnEnable()
	if not self.win then self.win = Build() end

	self:HideBlizzard()
	self:HookToggle()
	self:HookMicroButtons()
	SetSpecialFrame(true)

	-- Through the box, not by assigning self.filter. Setting the field directly
	-- would leave stale text sitting in a search box that is no longer filtering
	-- anything, so the next keystroke would jump to a result set the visible text
	-- does not explain.
	self.win.head.search.box:SetText("")
	self:SetFilter("")

	-- Questie resolves `QuestLogExFrame or ClassicQuestLog or QuestLogFrame` and
	-- then calls ShowUIPanel on whatever it finds. Answering to ClassicQuestLog
	-- means its "open quest log" opens ours instead of popping Blizzard's dead
	-- frame over the top of it. Claimed on every enable rather than once at
	-- build, or turning the module off and on again would leave it unclaimed.
	if not _G.ClassicQuestLog then _G.ClassicQuestLog = self.win end

	A:RegisterEvent(self, "QUEST_LOG_UPDATE", function() QL:Invalidate() end)
	A:RegisterEvent(self, "QUEST_WATCH_UPDATE", function() QL:Invalidate() end)
	-- These three change *which* quests exist, so the cached descriptions go with
	-- them. QUEST_LOG_UPDATE alone does not: it fires constantly for objective
	-- progress, and dropping the cache on every one would defeat it entirely.
	A:RegisterEvent(self, "QUEST_ACCEPTED", function() DropTextCache() QL:Invalidate() end)
	A:RegisterEvent(self, "QUEST_REMOVED", function() DropTextCache() QL:Invalidate() end)
	A:RegisterEvent(self, "QUEST_TURNED_IN", function() DropTextCache() QL:Invalidate() end)
	A:RegisterEvent(self, "UNIT_QUEST_LOG_CHANGED", function(_, _, unit)
		if unit == "player" then QL:Invalidate() end
	end)

	-- For several seconds after a loading screen the client hands back nil
	-- completion flags and zero objective counts for quests that are perfectly
	-- fine. Rebuilding on that produces a window full of wrong progress, so the
	-- gate stays shut until the world is up.
	-- Blizzard recomputes its own Share button on this event, and omitting it is a
	-- bug that only reproduces in a group: the button stays greyed out after the
	-- player joins a party and nothing on screen explains why.
	A:RegisterEvent(self, "GROUP_ROSTER_UPDATE", function()
		if QL.win and QL.win:IsShown() then QL:RefreshFooter() end
	end)

	A:RegisterEvent(self, "LOADING_SCREEN_ENABLED", function() QL.loading = true end)
	A:RegisterEvent(self, "LOADING_SCREEN_DISABLED", function() QL.loading = false QL:Invalidate() end)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		QL.loading = false
		DropTextCache()
		QL:HideBlizzard()
		QL:Invalidate()
	end)

	self:OnConfigChanged()
end

function QL:OnDisable()
	self:CloseConfirm()
	self:Hide()
	self:RestoreToggle()
	self:RestoreBlizzard()
	SetSpecialFrame(false)
	DropTextCache()
	if _G.ClassicQuestLog == self.win then _G.ClassicQuestLog = nil end
end

function QL:OnSkinChanged()
	if not self.win then return end
	local win = self.win
	win:ApplySkin("glassStrong")
	win:SetFillColor(Palette:ReadingFill())
	win.head.search:ApplySkin("glassSoft")
	win.detail.card:ApplySkin("glassSoft")

	local c = Palette.c
	W.Color(win.head.title, c.text)
	W.RepaintClose(win.head.close)
	W.Color(win.head.search.placeholder, c.textFaint)
	for _, b in pairs({ win.detail.foot.track, win.detail.foot.share,
		win.detail.foot.abandon }) do b:Restyle() end
	win.head.mark:SetVertexColor(c.accent[1], c.accent[2], c.accent[3], 1)
	ColorHairline(win.head.rule)
	ColorHairline(win.list.rule)

	self:Refresh()
end

function QL:OnConfigChanged()
	if not self.win then return end
	self.win:SetScale(A.db.profile.scale)
	self.win:SetShadow(A.db.profile.glass.shadow)
	self:OnSkinChanged()
end
