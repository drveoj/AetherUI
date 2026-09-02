--[[--------------------------------------------------------------------------
	AetherUI :: Panels

	The client's own windows - character, spellbook, talents, guild, map, menu,
	help - in our glass. Everything the Toolbox rail can open, so opening one
	does not land you in a different interface.

	Policy only. The mechanics are Core\Reskin.lua's: what a frame's art
	actually is, why hiding it is not enough, and where it hides. This file
	says WHICH frames and leaves the rest alone.

	Load on demand
	--------------
	Half of these do not exist at login. Talents, the guild window, the map and
	the help frame arrive with their own addon the first time you open them, so
	the list is walked again on ADDON_LOADED rather than once at startup - a
	frame that is not there yet is not a frame that does not want skinning.

	What is deliberately NOT done
	-----------------------------
	Nothing is moved, resized or reparented. These are placed by the UIPanel
	system, several carry secure children, and HideUIPanel is combat-blocked and
	fails silently - which is why the bag window handles its own escape key.
	Making them movable is an argument with that system and is not this.

	The insides are left alone as well. A character sheet's item slots, a
	spellbook's buttons and the map's pins are the client's furniture, and each
	wants its own pass. This is the window: its frame, its background, its
	title and the way out.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local PN = A:NewModule("panels")

local W, Palette, Reskin, Media = A.Widgets, A.Palette, A.Reskin, A.Media

--- The windows, and the addon each arrives with when it is not there at login.
--
--  Both talent frame names are listed because the client has used both and
--  which one you get depends on the flavour; the missing one simply never
--  turns up and costs nothing.
--  `insets` trims our glass back to the window you can actually see. These
--  frames carry wide transparent margins in their art, and room below for the
--  tab strip, so glass at the frame's full extent reads as a slab of padding
--  down the right and underneath.
--
--  Measured off the frame, not taken from anywhere: { left, top, right, bottom }
--  as SetPoint offsets, and expected to want a nudge by eye.
-- How far the postbox's tabs hang below its bottom edge. Blizzard's own is
-- 30, which puts their top edge inside the money row - hidden in the
-- client by the stone border drawn over the join, and not hidden once that
-- border is off. The glass follows it down, or the tabs sit outside.
--- The two Cataclysm-rebuilt windows' own numbers, in one table.
--
--  ONE LOCAL RATHER THAN THREE. This file's main chunk is within a few names
--  of Lua's ceiling of 200 locals in a function, and the game runs 5.1 - three
--  constants took it over and the whole module stopped loading.
--
--  `tabDrop` is how far their tabs hang below their own bottom edge, the same
--  arrangement as the vendor's and the postbox's. `insetX`/`insetY` are where
--  the recess starts on both - TOPLEFT 4, -60, out of ButtonFrameTemplate.
--  Only that corner is ours to move; see ClientRecess.
--  `schoolCol` is the column of school tabs the Mists spellbook hangs off its
--  own RIGHT edge - 32 wide, plus air.
--  `pages` are the three the same rebuild added to the spellbook, which Era
--  has none of - every one setAllPoints to the window, like the spell page.
--  `tiers` is how many talent rows Mists draws - six, where Cataclysm had
--  seven.
local CHAR = { tabDrop = 34, insetX = 4, insetY = 60, schoolCol = 40, tiers = 6,
	pages = { "SpellBookProfessionFrame", "SpellBookCoreAbilitiesFrame",
		"SpellBookWhatHasChanged" } }
PN.CHAR = CHAR

local MAIL_TAB_DROP = 40
PN.MAIL_TAB_DROP = MAIL_TAB_DROP

-- WHERE THE SOCIAL WINDOW'S TABS HANG: below its own bottom edge, outside its
-- art, the way the postbox's and the vendor's do.
local FRIENDS_TAB_DROP = 31
-- The Friends tab has TABS OF ITS OWN - Friends and Ignore - 36 above the list
-- they switch between. Reserved over that list rather than measured, so the
-- pair and the list travel by the same amount and keep the gap the client left
-- between them.
local FRIENDS_SUBTABS  = 36
-- Same shape one pane along: the who list's five column headers sit 30 above
-- the list they head.
local WHO_HEAD         = 30
-- Room reserved over the group finder listing's three views, for the strip of
-- role buttons the client puts above them. Reserved rather than measured, for
-- the reason the social window's sub-tabs are: measured, the role strip travels
-- 74 and the views travel 6, so the strip lands on top of them.
local LFG_ROLE_ROW     = 62

-- How far PVEFrame's three tabs hang below its bottom edge. Blizzard's own
-- number, from the BOTTOMLEFT offset on $parentTab1 in Classic\PVEFrame.xml.
local PVE_TAB_DROP     = 30

-- The achievement book's three, which hang off its BOTTOMLEFT the same way.
local ACH_TAB_DROP     = 30

-- The rank switch's row at the top of the spellbook's well: the switch, and
-- the gap to the first spell under it. The well's own padding is not in here -
-- LayoutBody puts every window's content inside that already.
local RANKS_ROW        = 22 + W.PANEL_GAP

-- Room kept at the top of a crafting window's LIST well, INSIDE the recess,
-- for the All control and the progress bar under it. Two lines, the gap
-- between them, then the body's own gap down to the first recipe.
--
-- DECLARED HERE, above the panel list that uses it. Written below, it was nil
-- when the table was built - so the entry carried an empty lead and the list
-- never made room for anything. That is the fourth constant this file has had
-- read before it existed.
local SKILL_ALL_H      = 22
local SKILL_BAR_H      = 16
PN.SKILL_BAR_H = SKILL_BAR_H
local SKILL_HEAD       = SKILL_ALL_H + 6 + SKILL_BAR_H + W.PANEL_GAP
PN.SKILL_HEAD = SKILL_HEAD

-- And room over the DETAIL pane for the two filters, which belong to it: they
-- change what the list shows and the list is what the detail is read from.
-- OUTSIDE its well rather than in it - a filter is chrome, and chrome does not
-- go in a recess. So the recess on that side starts this much lower.
local SKILL_FILTER_H   = 26
local SKILL_FILTERS    = SKILL_FILTER_H + W.PANEL_GAP

local PANELS = {
	-- ITS TITLE IS THE NAME AND ITS SUBTITLE IS THE CLASS LINE. Neither is
	-- the frame's own $parentTitleText, which this window never fills in.
	--
	-- AND THE PET TAB BRINGS ITS OWN PAIR. The window is one frame with five
	-- panes in it, and on that pane the thing the header is naming is not you.
	--
	-- ON MISTS NEITHER NAME EXISTS. That sheet is built on the portrait
	-- template and puts your name in the title bar as CharacterFrameTitleText,
	-- with no second line at all - so the Era name is tried first and the
	-- Mists one answers when it is absent. See PN.Part.
	{ frame = "CharacterFrame", insets = { 10, -10, -30, 26 },
		title = { "CharacterNameText", "CharacterFrameTitleText" },
		subtitle = "CharacterLevelText",
		panes = {
			-- AND THE PET'S NAME IS NOT IN THE SAME PLACE EITHER. Era's
			-- Wrath\PetPaperDollFrame.lua gives the pane its own string and
			-- fills it - `PetNameText:SetText(UnitName("pet"))`. Cata's, which
			-- Mists loads, has no such string at all: it writes the name into
			-- the WINDOW'S title instead, `CharacterFrameTitleText:SetText(
			-- UnitPVPName("pet"))`, from inside PetPaperDollFrame_Update.
			--
			-- So the band came up blank on Mists while "Level 1 Imp" sat in the
			-- pane below it, which is PetLevelText - the one string the two
			-- clients do agree on.
			{ pane = "PetPaperDollFrame",
				title = { "PetNameText", "CharacterFrameTitleText" },
				subtitle = "PetLevelText" },
		},
		-- THE FIVE TABS. Every one is setAllPoints to the window, so moving
		-- the pane carries every slot, string and model hanging off it - and
		-- each is measured on its own, because they do not agree about where
		-- their content begins: the first equipment slot is 74 below the
		-- frame, the reputation columns are headed at 57 and the skill
		-- list's ALL tab sits at 49.
		--
		-- WRITTEN BY THE CLIENT, not by us - see below the table. Era's five
		-- are Character, Pet, Reputation, Skills and Honour; Cataclysm dropped
		-- the last two and added Currency, and both clients publish the answer
		-- as CHARACTERFRAME_SUBFRAMES. Era's list stood here for both, so on
		-- Mists the Currency tab was never measured and never moved: its list
		-- is anchored to the client's own recess and sat wherever that put it.
		body = { "PaperDollFrame", "PetPaperDollFrame", "ReputationFrame",
			"SkillFrame", "HonorFrame" } },
	-- SOMEBODY ELSE'S, which is not the same window and not the same shape.
	-- The character sheet is the old parchment build with a wide margin; this
	-- one is ButtonFrameTemplate, so tight - and its two tabs hang off the
	-- bottom edge outside its own art the way the vendor's do, which is what
	-- the negative inset is for.
	{ frame = "InspectFrame", addon = "Blizzard_InspectUI", tight = true,
		insets = { 0, 0, 0, -34 },
		title = "InspectNameText", subtitle = "InspectLevelText",
		-- Its two tabs, moved into the recess the way the character sheet's four
		-- are. Same shape, same problem: every one of them starts in the strip
		-- the stone title plate used to need.
		body = { "InspectPaperDollFrame", "InspectHonorFrame" } },
	-- The spellbook names none of its parts the way the others do: its title is
	-- a global of its own rather than $parentTitleText, its close button is
	-- SpellBookCloseButton rather than $parentCloseButton, and its tabs are
	-- SpellBookFrameTabButton1..3. Naming them here is cheaper than three
	-- special cases in Dress, and the next window with its own spelling only
	-- needs a line.
	{
		frame       = "SpellBookFrame",
		insets      = { 4, -4, -4, 24 },
		-- Mists spells both the ordinary way, after the frame.
		title       = { "SpellBookTitleText", "SpellBookFrameTitleText" },
		close       = { "SpellBookCloseButton", "SpellBookFrameCloseButton" },
		tabs        = "SpellBookFrameTabButton",
		-- The rank switch sits above the spells in the recess, which is
		-- RANKS_ROW of reserved room over whatever the page measures at.
		lead        = RANKS_ROW,
		body        = { "SpellBookSpellIconsFrame" },
	},
	{
		frame       = "PlayerTalentFrame",
		addon       = "Blizzard_TalentUI",
		insets      = { 4, -4, -4, 24 },
		-- "Points spent in Fire Talents: 0" is a status line about the tab
		-- you are on - the same shape as the character sheet's class line
		-- under your name, and it changes with the tab exactly as the pet's
		-- does. So it is this window's SUBTITLE, which gives it the taller
		-- band and a place of its own instead of a line jammed against the
		-- title above and the talent grid below.
		subtitle    = "PlayerTalentFrameSpentPointsText",
	},
	{ frame = "TalentFrame",       addon = "Blizzard_TalentUI" },
	-- THE SOCIAL WINDOW: four tabs over five panes, and every pane is
	-- setAllPoints to the window. So moving a pane moves nothing at all - a
	-- setAllPoints frame has no points to offset - and everything in here is
	-- hung off the WINDOW at its own fixed distance instead.
	--
	-- ButtonFrameTemplate, so tight; and its tabs hang off the bottom edge
	-- outside its own art the way the postbox's do, which is what the negative
	-- inset is for.
	{ frame = "FriendsFrame", tight = true,
		insets = { 0, 0, 0, -FRIENDS_TAB_DROP - 8 },
		tabs = "FriendsFrameTab",
		-- ITS TITLE IS PER TAB and the client writes it: Friends List, Ignore
		-- List, Who, the guild's name, Raid. The frame's own $parentTitleText
		-- IS that string here, unusually - it is just never given a fixed word.
		title = "FriendsFrameTitleText",
		-- Five panels, one up at a time, and the window's tab says which -
		-- named so the band and the strip are redrawn when the client swaps
		-- them, the way the quest giver's four are.
		panes = {
			{ pane = "FriendsListFrame" },
			{ pane = "IgnoreListFrame" },
			{ pane = "WhoFrame" },
			{ pane = "GuildFrame" },
			{ pane = "RaidFrame" },
		},
		-- WHAT ACTS ON THE LIST YOU ARE LOOKING AT. A query over the who list,
		-- the raid's assist switch, and Raid Info at the other end. Every one
		-- of them was in the band or under the strip: the query is anchored to
		-- the window's BOTTOM edge, which is where the footer now is, and the
		-- other two are 23 and 24 down from the top.
		--
		-- ONE ROW SERVES ALL FIVE PANES because only one pane is ever up, and
		-- the row is laid out from what is VISIBLE rather than from what is
		-- shown - a hidden pane's children still report themselves shown.
		--
		-- AND WHO YOU ARE ON BATTLE.NET IS THE SAME KIND OF THING. The client
		-- hangs your status dropdown, your tag and the broadcast button 26 and
		-- 27 down from the window's TOP edge - which is the middle of our
		-- header band, so all three came up sitting on the window's title with
		-- the tag reading as a second, fainter title. They belong at the top of
		-- the CONTENT, which is what this row is.
		--
		-- All three are children of FriendsTabHeader, and the client shows that
		-- only on the Friends tab - so the visible test sorts them from the who
		-- query and the raid's switch at no cost.
		row = {
			left  = { "FriendsFrameStatusDropdown",
				"FriendsFrameBattlenetFrame",
				"WhoFrameEditBox", "RaidFrameAllAssistCheckButton" },
			right = { "FriendsFrameBattlenetFrame.BroadcastButton",
				"RaidFrameRaidInfoButton" },
		},
		-- ROOM RESERVED OVER TWO OF THE LISTS, for the row of controls the
		-- client puts immediately above each. Reserved rather than measured so
		-- that the header and its list are short of the band by the SAME
		-- amount and travel together; measured, the sub-tabs would move 36
		-- further than the list under them and land on top of it.
		lead = {
			FriendsFrameFriendsScrollFrame = FRIENDS_SUBTABS,
			FriendsFrameIgnoreScrollFrame  = FRIENDS_SUBTABS,
			WhoListScrollFrame             = WHO_HEAD,
		},
		body = { "FriendsTabHeaderTab1",
			"FriendsFrameFriendsScrollFrame", "FriendsFrameIgnoreScrollFrame",
			"WhoFrameColumnHeader1", "WhoListScrollFrame",
			"RaidFrameRaidDescription" },
		-- AND THE ROWS THAT BELONG TO THE TWO FAUX-SCROLLING LISTS, which are
		-- not in them: the client hangs them off the WINDOW and scrolls by
		-- refilling, exactly as the trainer does.
		inside = {
			FriendsFrameIgnoreButton1 = "FriendsFrameIgnoreScrollFrame",
			WhoFrameButton1           = "WhoListScrollFrame",
		},
		-- Every list in here gets a recess of its own, so no seventh one round
		-- the outside.
		wells = false,
		footer = W.PANEL_FOOT_H,
		-- All four panes' worth: the strip is laid out for whatever is UP.
		actions = { mid = {
			"FriendsFrameAddFriendButton", "FriendsFrameSendMessageButton",
			"FriendsFrameIgnorePlayerButton", "FriendsFrameUnsquelchButton",
			"WhoFrameWhoButton", "WhoFrameAddFriendButton",
			"WhoFrameGroupInviteButton", "RaidFrameConvertToRaidButton",
		} } },

	-- THE SAME JOB ON MISTS, AND A DIFFERENT WINDOW ENTIRELY.
	--
	-- Era opens LFGParentFrame below; Wrath onward opens PVEFrame, and the two
	-- share nothing but their purpose. Blizzard_GroupFinder is gated
	-- `wrath, cata, mists` and carries PVEFrame; Blizzard_GroupFinder_
	-- VanillaStyle is load-on-demand and carries the parchment one. So the port
	-- dressed the window Era shows and left the window Mists shows in Blizzard's
	-- stone - the only whole window in the interface that was still theirs.
	--
	-- BOTH ENTRIES STAND, ungated. Neither frame exists on the other's client
	-- and an entry whose frame never appears never fires, which is how every
	-- load-on-demand window here already works.
	--
	-- PORTRAIT FRAME, SO TIGHT, and its three tabs hang 30 below the bottom
	-- edge outside its own art - the character sheet's case exactly, so the
	-- glass reaches past the frame to carry them rather than stopping at it.
	-- THE ACHIEVEMENT BOOK, which Mists has and Era does not: the addon is
	-- gated `mists` outright, so this entry never fires on the other client.
	--
	-- READ ELVUI'S SKIN FIRST, which is the point of the exercise -
	-- Game/Mists/Skins/Achievement.lua. Two things came straight off it and
	-- neither is obvious from the XML: the window is bordered by TWELVE named
	-- texture pieces rather than a template's nine-slice, and its rows are
	-- minted lazily by HybridScrollFrame_CreateButtons, so a dresser that runs
	-- once at open dresses however many rows happen to exist that moment.
	--
	-- NOT A PORTRAIT FRAME AND NOT ButtonFrameTemplate. It inherits
	-- BackdropTemplate and carries its own wood and metal frame, so there is no
	-- margin convention to trim to - the pieces come off and the glass takes
	-- their place.
	{ frame = "AchievementFrame", addon = "Blizzard_AchievementUI",
		insets = { 0, 0, 0, -ACH_TAB_DROP },
		tabs = "AchievementFrameTab",
		-- ITS HEADER IS A FRAME OF ITS OWN with the two strings on it, which is
		-- why neither is $parentTitleText and why the portrait fallback would
		-- never have found them.
		title = "AchievementFrameHeaderTitle",
		subtitle = "AchievementFrameHeaderPoints",
		-- WELLS = FALSE, EARNED. Every list on this window is already in a
		-- container the client draws a border round - the categories column and
		-- one per tab - and ElvUI gives each its own backdrop for the same
		-- reason. A body well would be a rim round five rims.
		wells = false,
		body = { "AchievementFrameAchievements", "AchievementFrameStats",
			"AchievementFrameSummary", "AchievementFrameComparison" } },

	{ frame = "PVEFrame", addon = "Blizzard_GroupFinder", tight = true,
		insets = { 0, 0, 0, -PVE_TAB_DROP },
		tabs = "PVEFrameTab",
		-- WELLS = FALSE, AND EARNED. Every pane on this window puts its content
		-- inside a recess of the client's own: PVEFrame's LeftInset holds the
		-- column of group buttons, and each right-hand pane brings one more -
		-- LFDParentFrameInset, RaidFinderFrameRoleInset and its BottomInset,
		-- ScenarioFinderFrameInset, and LFGListFrame's several. A body well
		-- round the outside would be a rim drawn round rims.
		wells = false,
		-- AND EVERY PANE TAKES THE SAME SHIFT. Without this each tab moves its
		-- own pane down by its own amount - 34 for the group finder, 58 for the
		-- battlegrounds - so the content jumps as you click between them even
		-- when the window itself holds still. `together` gives them all the
		-- largest, which is what the client does by keeping this window one
		-- fixed size across all three tabs.
		together = true,
		-- AND IT IS NEVER WIDENED. The condition `keepWidth` documents is
		-- exactly this window's: every pane's content is already inside a recess
		-- of the client's own, so shifting it across moves it out of the recess
		-- drawn for it, and growing the window to pay for that shift makes it too
		-- wide for what is in it.
		--
		-- Without this the width swung by six units on every tab click, for the
		-- same reason the height swung by twenty-four: the growth is the largest
		-- any pane asks for, and which panes can be measured changes with which
		-- one is up. The client keeps PVEFrame one fixed size across all three
		-- tabs and so do we.
		keepWidth = true,
		-- AND ITS CONTENT TOP IS A CONSTANT, NOT A MEASUREMENT.
		--
		-- This window changed height on every tab click through three attempts
		-- to fix it, and each attempt added machinery: cache the readings, take
		-- the largest, make the largest monotonic. All of it was chasing the
		-- same fact - a pane that is DOWN has no rect, so it cannot be measured,
		-- so the largest shift is only ever the VISIBLE tab's and it changes as
		-- you click.
		--
		-- ELVUI HAS NO SUCH PROBLEM BECAUSE IT MEASURES NOTHING. Its whole
		-- PVEFrame skin is HandlePortraitFrame plus shadows:Kill(), and every
		-- Point() in that file is a fixed number read off the window once. There
		-- is nothing in it that can differ between two clicks.
		--
		-- We do need the content moved down for the header band, so we cannot
		-- copy that outright - but we can take the principle, and the key for it
		-- was already here. `contentTop` says where this window's content begins
		-- and stops LayoutBody asking. 22 is the smallest any of its panes
		-- measured, so it is the figure that clears the band for all of them.
		contentTop = 22,
		-- THE THREE TABS' PANES, in the order PVEFrame.lua's own `panels`
		-- table lists them. Two are load-on-demand and simply are not there
		-- until opened, which the dresser has to survive rather than assume.
		body = { "GroupFinderFrame", "PVPQueueFrame", "ChallengesFrame" },
		-- NO FOOTER STRIP, AND THAT WAS A WRONG TURN WORTH RECORDING.
		--
		-- One was added here on the reasoning that Find Group and the two
		-- battleground buttons are the actions of the window. They are not:
		-- every one of them is already anchored INSIDE its own pane's recess -
		-- `BOTTOM->BOTTOM 0,4 on LFDQueueFrame` - which is where the client
		-- draws them and where they belong, because each belongs to one finder
		-- rather than to the window.
		--
		-- What a strip cost was height. The window grew to make room for a row
		-- nothing stood in, the body shift went from 58 to 128, and the readout
		-- showed the result plainly: 556 tall with an empty hand's width under
		-- the list. They are skinned where they stand instead; see
		-- PanelInteriors.
		--
		-- A FOOTER IS FOR ACTIONS THAT BELONG TO THE WINDOW. Where the client
		-- has already put a button inside a recess, that is its answer to the
		-- same question and there is nothing to move.
	},

	-- THE GROUP FINDER, which is two windows behind two tabs: the listing you
	-- post and the browse you search with. LFGParentFrame is the old parchment
	-- build - 384 by 512, an eye where a portrait goes, its close button 26 in
	-- from the rim - so it wants the margin trimmed the way the quest giver and
	-- the trainer do, and its tabs sit INSIDE that margin rather than below it.
	--
	-- ITS ADDON LOADS ON DEMAND. Nothing here exists until the player opens the
	-- window once, which is what `addon` is for.
	{ frame = "LFGParentFrame", addon = "Blizzard_GroupFinder_VanillaStyle",
		insets = { 4, -4, -26, 22 },
		-- ITS TITLE IS PER PANE, and both panes carry one saying the same thing:
		-- the client prints LFG_TITLE inside the pane rather than in the band, the
		-- way the postbox prints INBOX and SEND MAIL inside its two.
		--
		-- TAB ONE IS THE LISTING AND TAB TWO IS THE BROWSE, which reads backwards
		-- until you look: LFGParentFrameTab1_OnClick shows LFGListingFrame.
		panes = {
			{ pane = "LFGListingFrame", title = "LFGListingFrameFrameTitle" },
			{ pane = "LFGBrowseFrame",  title = "LFGBrowseFrameFrameTitle" },
		},
		-- NEITHER PANE IS IN THE BODY LIST. Both are setAllPoints to the window,
		-- and a setAllPoints frame has NO POINTS - so moving one moves nothing
		-- while reporting that it had. The social window's lesson, one window on.
		--
		-- WHAT FILTERS THE LIST GOES IN THE TOOL ROW: the category and activity
		-- dropdowns and the refresh beside them, with the options gear at the far
		-- end. The client hangs all four at their own fixed offsets from the
		-- window's top - 94 for the dropdowns, 44 for the gear - which is our
		-- header band and a line under it.
		--
		-- ONE ROW SERVES BOTH PANES, laid out from what is VISIBLE and OURS: only
		-- one pane is ever up, and each carries a gear of its own.
		row = {
			left  = { "LFGBrowseFrameCategoryDropdown",
				"LFGBrowseFrameActivityDropdown", "LFGBrowseFrameRefreshButton" },
			right = { "LFGBrowseFrameOptionsButton",
				"LFGListingFrameOptionsButton" },
		},
		-- THE CONTENT OF BOTH PANES. Browse is one scroll box; the listing swaps
		-- between three views of the same size and place, with the role buttons
		-- and the newcomer switch in a strip above them.
		-- ROOM RESERVED OVER THE LISTING'S THREE VIEWS for the strip of role
		-- buttons the client puts above them. Reserved rather than measured,
		-- for the reason the social window's sub-tabs are: measured, the role
		-- strip travels 74 and the views travel 6, so the strip lands on top
		-- of them. Browse has nothing above its list and takes none.
		lead = {
			LFGListingFrameCategoryView = LFG_ROLE_ROW,
			LFGListingFrameActivityView = LFG_ROLE_ROW,
			LFGListingFrameLockedView   = LFG_ROLE_ROW,
		},
		-- AND THE CONTENT REACHES THE FLOOR OF THE RECESS. Every one of these
		-- is a fixed 324 by 282 in a frame the client made 512 tall; ours is
		-- half as tall again, so left alone the list sits in a recess with a
		-- hand's width of empty glass under it and shows fewer results than
		-- there is room for.
		fill = {
			LFGBrowseFrameScrollBox     = true,
			LFGListingFrameCategoryView = true,
			LFGListingFrameActivityView = true,
			LFGListingFrameLockedView   = true,
		},
		body = { "LFGBrowseFrameScrollBox",
			"LFGListingFrameCategoryView", "LFGListingFrameActivityView",
			"LFGListingFrameLockedView",
			"LFGListingFrameSoloRoleButtons", "LFGListingFrameGroupRoleButtons",
			"LFGListingFrameNewPlayerFriendlyButton" },
		footer = W.PANEL_FOOT_H,
		-- BOTH PANES' WORTH: the strip is laid out for whatever is up.
		actions = { mid = { "LFGBrowseFrameSendMessageButton",
			"LFGBrowseFrameGroupInviteButton", "LFGListingFrameBackButton",
			"LFGListingFramePostButton" } } },

	-- The windows an NPC opens, and WHICH TEMPLATE EACH IS BUILT ON, because
	-- that is what decides whether it wants trimming at all.
	--
	-- Gossip, the vendor and the trade window are ButtonFrameTemplate: modern,
	-- tight, no transparent margin to take back. Insetting one of those cuts
	-- into the window - the vendor's buyback row and your purse ended up
	-- outside the glass, which is what "sizing and alignment issues" looked
	-- like. The quest giver, the trainer and the flight master are the old
	-- parchment shape and do want it.
	--
	-- `tight` says which: no margin to trim, and a title band twenty pixels
	-- tall that our own title role overhangs. Set per window from its own XML
	-- rather than sniffed at runtime, because "does this frame have a
	-- TitleContainer" is true of windows on both templates and answers a
	-- different question.
	{ frame = "GossipFrame",   tight = true,
		-- WHAT YOU CAN SAY, which is a scroll box with no name of its own - the
		-- modern templates stopped naming things globally, so it is reached by
		-- the path through the window instead. The client hangs it off the WINDOW
		-- at 8 in and 65 down: the strip its stone title plate used to need, and
		-- neither our band nor our padding.
		body = { "GossipFrame.GreetingPanel.ScrollBox" },
		-- Goodbye sat in the window's bottom right corner, four up from the glass
		-- and under the recess. 15a: actions live in a strip of their own.
		footer = W.PANEL_FOOT_H,
		actions = { mid = { "GossipFrame.GreetingPanel.GoodbyeButton" } },
		-- HOW WELL THIS ONE KNOWS YOU, where they are somebody who keeps track.
		-- Most are not, so the row is empty on nearly every NPC in the game - and
		-- an empty row still cost the body forty-two units until it was measured
		-- rather than declared.
		row = { left = { "GossipFrame.FriendshipStatusBar" } } },
	-- The vendor's glass reaches BELOW the frame, which is the one place an
	-- inset goes negative. Blizzard hangs this window's tabs off the bottom
	-- edge, outside its own art - so trimmed to the frame the tab row landed on
	-- top of the buyback row, the repair buttons and your purse all at once.
	-- Thirty-four is the tab strip plus air.
	-- ITS TITLE IS WHO YOU ARE BUYING FROM. The frame's own $parentTitleText
	-- says "Merchant", which is what the window plainly is; the vendor's name
	-- is the thing worth putting in the band, and the client hangs it off its
	-- portrait rather than naming it after the frame.
	{ frame = "MerchantFrame", tight = true, insets = { 0, 0, 0, -34 },
		title = "MerchantNameText",
		-- ITS REPAIR BUTTONS AND YOUR PURSE ARE A FOOTER. Both are anchored
		-- to the window's bottom edge, so the recess has to stop above them
		-- rather than run down through the money row.
		footer = W.PANEL_FOOT_H,
		-- ITS PAGE TURNERS GO IN THE FOOTER. 15c: a page turn is chrome and
		-- never floats in the body. These sat inside the recess, over the last
		-- row of what you were being sold - and they are laid out by the same
		-- line as every other window's actions rather than by a page-turn one.
		actions = { mid = { "MerchantPrevPageButton", "MerchantPageText",
			"MerchantNextPageButton" } },
		-- AND IT HAS NO PANE. Its ten rows are children of the window itself,
		-- but only the FIRST is anchored to it - the other nine chain off that
		-- one - so moving it moves the grid and leaves the page turners and
		-- the money row where they belong, on the window's own edges.
		body = { "MerchantItem1" } },
	{ frame = "TradeFrame",    tight = true,
		-- THE GLASS REACHES PAST THE FRAME ON BOTH SIDES, and nothing in this
		-- window moves sideways at all. That is forced by one piece: the
		-- client's own SetForbidden on TradePlayerInputMoneyFrame means your
		-- purse cannot be moved a single unit, in either direction. Everything
		-- else moving in by twenty-two to reach the body's margin left the
		-- purse behind, and a recess with nothing in it above a row of fields
		-- with nothing round them is what that looked like.
		--
		-- So the margin is made by widening the GLASS instead of by moving the
		-- content: the client's insets sit 4 in from the frame on the left and
		-- 6 on the right, and 22 and 20 of glass outside those puts every one
		-- of them the standard 26 in from the rim without touching a point.
		-- MeasureTop measures against the glass, so this also makes the
		-- sideways shift measure zero rather than needing a flag of its own.
		insets = { -22, 0, 20, 0 },
		-- ROOM RESERVED FOR THE PURSES, which are the one row that cannot
		-- travel. The client puts them 58 to 90 down - four below our header
		-- rule - so they read as a strip of their own under the band, and the
		-- body starts a gap below the deepest of them rather than at the usual
		-- 80. Without it the names came down on top of them.
		lead = 24,
		-- A DOZEN PIECES, ALL HUNG OFF THE FRAME at their own fixed offsets: two
		-- names five units down, two purses at sixty, two columns of slots at
		-- eighty-nine. `together` because shifting each by what IT is short of
		-- squeezes the window: the names would travel eighty units and the slots
		-- eight, and what was a layout becomes a heap.
		together = true,
		-- AND NOT THE TWO NAMES EITHER, which are in the BAND. See DressTrade:
		-- this window's title is who is trading with whom, and it takes two
		-- strings to say it because each names a column. Leaving them in the
		-- body cost twice over - a line of type where the title should be, and
		-- a shift of 99 driven by strings five units down that dropped a
		-- hand's width of empty glass under the purses.
		--
		-- EVERYTHING HUNG OFF THE WINDOW, and nothing that is chained off
		-- something already here. Item 1 brings the other six with it; the
		-- recipient's enchant label is anchored to the player's. The two
		-- ENCHANT recesses and the second wrap round their purse are NOT
		-- chained off anything - the client pins all three to the window's own
		-- corners - so left out of this list they stayed where they were while
		-- the rest of the window moved down past them.
		body = { "TradePlayerItemsInset", "TradeRecipientItemsInset",
			"TradePlayerEnchantInset", "TradeRecipientEnchantInset",
			"TradePlayerItem1", "TradeRecipientItem1",
			"TradeFramePlayerEnchantText",
			"TradeHighlightPlayer", "TradeHighlightRecipient" },
		-- AND NOT ONE PIECE OF THE MONEY ROW - not your fields, not their
		-- figure, and not either recess round them.
		--
		-- TradeFrame_OnLoad calls SetForbidden on TradePlayerInputMoneyFrame,
		-- so your own purse cannot be moved at all. Moving the four pieces
		-- that CAN move only separates them from the one that cannot: the
		-- recesses travelled down with the rest of the window and the fields
		-- stayed at 61, which put your gold, silver and copper above the two
		-- players' names in the header band with an empty recess a hundred
		-- units below them.
		--
		-- So the whole row stays where the client put it and the rest of the
		-- window is laid out around it - see `lead` above. One immovable piece
		-- sets the shape, which is the honest answer and the only one.
		-- ITS CONTENT IS ALREADY IN RECESSES - six of them, and every piece of
		-- this window is inside one. A body well round the outside would be a
		-- second rim round the first, which is the trainer's case exactly.
		wells = false,
		-- Trade and Cancel sat in the bottom right corner, five up from the
		-- glass and under the recess.
		footer = W.PANEL_FOOT_H,
		actions = { mid = { "TradeFrameTradeButton",
			"TradeFrameCancelButton" } } },
	-- 62 at the foot, because that is where this window's buttons are: Accept,
	-- Complete Quest and Cancel all sit 72 up from the bottom edge, and the art
	-- below them is margin. Trimmed to 22 the glass ran a hand's width past the
	-- last thing in the window.
	{ frame = "QuestFrame",        insets = { 8, -8, -28, 62 },
		-- WHO IS TALKING is the title, and this window never had one: its name
		-- string is QuestFrameNpcNameText, hung off a frame called
		-- QuestNpcNameFrame - so the "name + Text" that finds every other
		-- window's title looks up QuestNpcNameFrameText and finds nothing. It
		-- was being roled by hand in the interior below instead, which is why it
		-- sat where the parchment wanted it rather than in the band.
		title = "QuestFrameNpcNameText",
		-- Four panels, one up at a time, and no tab anywhere to say which. Named
		-- so the band and the strip are redrawn when the client swaps them.
		panes = {
			{ pane = "QuestFrameDetailPanel" },
			{ pane = "QuestFrameProgressPanel" },
			{ pane = "QuestFrameRewardPanel" },
			{ pane = "QuestFrameGreetingPanel" },
		},
		-- ACCEPT AT ONE END AND DECLINE AT THE OTHER. Every one of these is
		-- anchored to a bottom CORNER of a window 384 across, with the whole
		-- quest between them. 15a puts them in the strip, together.
		footer = W.PANEL_FOOT_H,
		actions = { mid = {
			"QuestFrameAcceptButton", "QuestFrameDeclineButton",
			"QuestFrameCompleteButton", "QuestFrameGoodbyeButton",
			"QuestFrameCompleteQuestButton", "QuestFrameCancelButton",
			"QuestFrameGreetingGoodbyeButton",
		} },
		-- The quest itself. Each panel prints it in a scroll frame anchored to
		-- the WINDOW rather than to the panel, 23 in and 81 down - the margin the
		-- parchment used to need.
		body = { "QuestDetailScrollFrame", "QuestProgressScrollFrame",
			"QuestRewardScrollFrame", "QuestGreetingScrollFrame" } },
	{ frame = "ClassTrainerFrame", addon = "Blizzard_TrainerUI",
		insets = { 8, -8, -28, 22 },
		-- The filter over the list it filters. Your purse is NOT up here with it:
		-- what it says is what the thing you are about to buy will leave you
		-- with, so it belongs beside the Train button, in the strip.
		row = {
			right = { "ClassTrainerFrameFilterDropDown" },
		},
		-- TRAIN, TRAIN ALL AND CLOSE, centred in the strip, with the purse pinned
		-- to its left end. The client puts all four at fixed offsets from the
		-- window's TOPLEFT, 420 down a frame that is no longer that tall - so they
		-- sat across the foot of both recesses.
		--
		-- Train All has no name of its own, so it cannot be listed: it is an
		-- anonymous child whose label is ClassTrainerFrameText. The window's own
		-- dresser finds all three by shape and registers them.
		actions = { left = { "ClassTrainerMoneyFrame" } },
		-- The two lists, so they clear the band and the body padding.
		body = { "ClassTrainerListScrollFrame", "ClassTrainerDetailScrollFrame" },
		-- AND THE ROWS THAT GO IN THE LIST, which are not in it: this is a faux
		-- scroll frame - the client hangs eleven row buttons off the WINDOW and
		-- scrolls them by refilling. So the list moved into the recess and left
		-- every skill behind, printed on the glass above an empty box.
		inside = { ClassTrainerSkill1 = "ClassTrainerListScrollFrame" },
		-- ...which are wells in their own right, so no recess round the pair.
		wells = false,
		footer = W.PANEL_FOOT_H },
	-- The flight map IS a region of the frame, so the sweep that takes the
	-- parchment takes the map with it and leaves the nodes floating in the
	-- dark. Its close button is TaxiCloseButton, not TaxiFrameCloseButton,
	-- which is why it kept the client's red X.
	--
	-- ON MISTS IT NAMES NOTHING. That flight map is built on
	-- BasicFrameTemplateWithInset, which carries its title and its X as parent
	-- keys and gives neither a global - so the second name here is a path
	-- through the window rather than a global of its own.
	{ frame = "TaxiFrame",         insets = { 8, -8, -28, 22 },
	                               close = { "TaxiCloseButton",
	                                         "TaxiFrame.CloseButton" },
	                               title = { "TaxiFrame.TitleText" },
	                               keep  = { "TaxiMap" },
		-- THE MAP AND THE ROUTES DRAWN OVER IT, moved together - two pieces at
		-- the same offset, and a shift measured per piece would part them. The
		-- flight points themselves are anchored to the MAP's own corner by the
		-- client, so every node comes with it.
		together = true,
		body = { "TaxiMap", "TaxiRouteMap" } },

	-- NOT GuildFrame. The old FriendsFrame XML still defines a GuildFrame pane,
	-- setAllPoints inside the social window, and this list used to name it as a
	-- window of its own - so it got glass of its own behind a pane that already
	-- had some, and a scale of its own inside a frame already scaled. Nobody
	-- sees it either way: the guild button on this client opens Communities.
	{ frame = "CommunitiesFrame",  addon = "Blizzard_Communities" },
	{ frame = "WorldMapFrame",     addon = "Blizzard_WorldMap" },
	-- IT LAYS ITSELF OUT. A VerticalLayoutFrame places its buttons from
	-- layoutIndex on every show, so nudging one is undone before you see it -
	-- and its first button, Options, sat straight across the header's hairline.
	{ frame = "GameMenuFrame", layout = true },
	{ frame = "HelpFrame",         addon = "Blizzard_HelpFrame" },
	-- The Options window itself. Our own settings page lives inside it, and
	-- skinning the page while leaving the frame around it in stone is the
	-- one place a player sees both at once.
	{ frame = "SettingsPanel", close = "ClosePanelButton" },

	-- THE POSTBOX. ButtonFrameTemplate, so tight - but its tabs hang off the
	-- bottom edge outside its own art the way the vendor's do, and trimmed to
	-- the frame the Inbox and Send Mail tabs land outside the glass.
	{ frame = "MailFrame", tight = true, insets = { 0, 0, 0, -MAIL_TAB_DROP - 8 },
		tabs = "MailFrameTab",
		-- ITS TITLE IS PER TAB. The frame's own $parentTitleText is never
		-- filled in; the words are INBOX and SEND MAIL, one on each pane, and
		-- the client prints them inside the pane rather than in the band. Same
		-- shape as the character sheet's pet tab, so the same mechanism.
		panes = {
			{ pane = "InboxFrame",    title = "InboxTitleText" },
			{ pane = "SendMailFrame", title = "SendMailTitleText" },
		},
		-- AND BOTH PANES ARE MOVED, which they never were: this window had no
		-- body at all, so everything the client hangs off either pane stayed in
		-- the strip its stone title plate used to need. On the inbox that is only
		-- the first row; on Send Mail it is the whole form, which came up with To,
		-- Subject, the letter, the attachments and the money row overlapping.
		body = { "InboxFrame", "SendMailFrame" },
		-- ITS ACTIONS WERE IN THE BODY, hard against the last letter in the list -
		-- the client hangs all four 114 up from the window's bottom edge, which in
		-- a window this shape is inside the recess. 15a: they go in a strip, and
		-- the strip is what keeps them clear of the content above.
		--
		-- Both panes' worth, because the strip is laid out for whatever is UP: the
		-- page turns and Open All while you are reading, Send and Cancel while you
		-- are writing.
		footer = W.PANEL_FOOT_H,
		actions = {
			mid   = { "InboxPrevPageButton", "InboxNextPageButton",
				"SendMailMailButton", "SendMailCancelButton" },
			-- Open All is an ACTION and the turns either side of it are
			-- NAVIGATION. On one line they read as three of a kind; under them it
			-- reads as the thing you do to the page you are looking at.
			--
			-- The turns stay even though this client's inbox also scrolls: they are
			-- the client's own, they still work, and replacing a list that works with
			-- one of ours to be rid of two buttons is not a trade worth making.
			under = { "OpenAllMail" },
		} },

	-- A LETTER OR A BOOK out of your bags. Also ButtonFrameTemplate, and
	-- what is inside it is printed on paper - so its text is lifted the way
	-- the quest giver's is.
	-- THE LETTER ITSELF, which is a window of its own and was in none of these
	-- lists - so it came up in the client's own stone beside a postbox in
	-- glass. ButtonFrameTemplate, like the postbox, and its three actions are
	-- chained off the bottom right corner the same way.
	{ frame = "OpenMailFrame", tight = true,
		title = "OpenMailTitleText",
		-- AS TALL AS THE POSTBOX BESIDE IT. The client hangs this off the inbox's
		-- top right corner and gives it a height of its own, so the pair came up
		-- as two windows of different sizes side by side.
		matchHeight = "MailFrame",
		-- WHO IT IS FROM AND WHAT IT IS ABOUT are body content: the client hangs
		-- both off the window's own TOPLEFT, 33 and 55 down, which is inside our
		-- band - so they were printed across the window's title.
		body = { "OpenMailSenderLabel", "OpenMailSubjectLabel",
			"OpenMailScrollFrame" },
		-- All three by the same amount: they are one block of header, and
		-- measuring each against its own top would stagger them.
		together = true,
		footer = W.PANEL_FOOT_H,
		actions = { mid = { "OpenMailReplyButton", "OpenMailDeleteButton",
			"OpenMailCancelButton" } } },

	{ frame = "ItemTextFrame", tight = true,
		-- The page itself, which starts 63 down - the strip the stone title plate
		-- used to need, and neither our band nor our padding.
		body = { "ItemTextScrollFrame" },
		-- ITS PAGE TURNS ARE IN THE BAND, one at each end of the window with the
		-- book's title between them, and the count under the title. 15c: a page
		-- turn is chrome and lives in the footer, as a group.
		footer = W.PANEL_FOOT_H,
		actions = { mid = { "ItemTextPrevPageButton", "ItemTextCurrentPage",
			"ItemTextNextPageButton" } } },

	-- THE TRADE SKILLS. Two windows, not one: TradeSkillFrame is First Aid,
	-- cooking, blacksmithing and the rest, and CraftFrame is enchanting and
	-- a hunter's beast training. Neither inherits a template - they are the
	-- old hand-built shape with their own art and a wide margin, so they
	-- want trimming like the trainer rather than tight like the modern ones.
	{ frame = "TradeSkillFrame", addon = "Blizzard_TradeSkillUI",
		insets = { 8, -8, -28, 22 },
		-- A TOOL ROW, not a subtitle. The rank bar reads like one - it says how
		-- far along this window's subject you are - but it is three hundred
		-- across, and a band is one line of type wide: put it there and the two
		-- filters land on top of it. So it shares a row of its own with them,
		-- under the hairline and above the lists.
		-- THE FILTERS ARE CHROME and the rank bars are NOT. A filter changes what
		-- the list is showing; a bar says how far along the thing in the list you
		-- are, and there can be several of them - first aid, fishing, riding. That
		-- is a column of content, so it goes in the recess WITH the list, and the
		-- All control over it goes there too.
		--
		-- NOT IN A TOOL ROW UNDER THE TITLE EITHER. They filter what you are
		-- reading on the RIGHT, so they belong over that pane and nowhere else -
		-- put across the whole window they read as being about the window.
		lead = {
			TradeSkillListScrollFrame   = SKILL_HEAD,
			TradeSkillDetailScrollFrame = SKILL_FILTERS,
		},
		-- The two lists, so they clear the band and the body padding.
		body = { "TradeSkillListScrollFrame", "TradeSkillDetailScrollFrame" },
		-- AND THE ROWS THAT GO IN THE LIST, which are not in it: the client hangs
		-- eight buttons off the WINDOW and scrolls them by refilling, so the list
		-- moved into the recess and left every recipe behind, above it.
		inside = { TradeSkillSkill1 = "TradeSkillListScrollFrame" },
		-- ...which are wells in their own right, so no recess round the pair.
		wells = false,
		footer = W.PANEL_FOOT_H,
		-- Create, Create All and Close, centred in the strip. The client puts
		-- them 422 down from the window's TOPLEFT, which is below the foot of a
		-- window this shape no longer has.
		-- ...AND THE COUNT SPINNER WITH THEM. How many to make is part of making
		-- them: left out of the strip it stayed where the client had put it,
		-- which is on top of Create.
		actions = { mid = { "TradeSkillCreateAllButton", "TradeSkillDecrementButton",
			"TradeSkillInputBox", "TradeSkillIncrementButton",
			"TradeSkillCreateButton", "TradeSkillCancelButton" } } },
	-- ENCHANTING AND A HUNTER'S BEAST TRAINING, which is the trade skill window
	-- again under a second set of names: same margins, same two lists, same
	-- rows hung off the window rather than off the list, same buttons 422 down
	-- a frame that is not that tall any more.
	{ frame = "CraftFrame", addon = "Blizzard_CraftUI",
		insets = { 8, -8, -28, 22 },
		lead = { CraftListScrollFrame = SKILL_HEAD },
		body = { "CraftListScrollFrame", "CraftDetailScrollFrame" },
		inside = { Craft1 = "CraftListScrollFrame" },
		wells = false,
		footer = W.PANEL_FOOT_H,
		actions = { mid = { "CraftCreateButton", "CraftCancelButton" } } },
}

PN.PANELS = PANELS

--- The same list, by frame name, for the things Dress needs mid-flight.
PN.ENTRY = {}
for _, entry in ipairs(PANELS) do PN.ENTRY[entry.frame] = entry end

-- WHICH PANES A TABBED WINDOW HAS, FROM THE CLIENT ITSELF.
--
-- Two windows in this list have panes that differ between the flavours, and
-- both are cases where guessing is unnecessary: the client publishes the
-- answer and then uses it itself.
--
--   CHARACTERFRAME_SUBFRAMES  Era: Character, Pet, Reputation, Skills, Honour
--                             MoP: Character, Pet, Reputation, Currency
--   INSPECTFRAME_SUBFRAMES    Era: PaperDoll, Honor
--                             MoP: PaperDoll, PVP, Talents, Guild
--
-- ToggleCharacter, ShowSubFrame, InspectFrameTab_OnClick and each window's own
-- hide sweep all read these, so taking them rather than restating them means a
-- tab Blizzard adds is measured the day it appears and a tab they remove stops
-- being asked for.
--
-- THE INSPECT WINDOW IS WHY THIS IS A LOOP. Era's list was written into the
-- table for both flavours, so on Mists its Talents, PVP and Guild pages were
-- never measured and never moved - and InspectHonorFrame, which that client
-- does not build, was asked for on every open.
--
-- The table above keeps Era's lists as the written answer for when a global is
-- missing: a .toc that failed to load one of these frames, chiefly, where half
-- a body list is better than none.
do
	for frame, global in pairs({
		CharacterFrame = "CHARACTERFRAME_SUBFRAMES",
		InspectFrame   = "INSPECTFRAME_SUBFRAMES",
	}) do
		local subs = _G[global]
		if type(subs) == "table" and #subs > 0 and PN.ENTRY[frame] then
			local body = {}
			for i = 1, #subs do body[i] = subs[i] end
			PN.ENTRY[frame].body = body
		end
	end

	-- AND IT IS NOT THE SAME SHAPE OF WINDOW EITHER.
	--
	-- Era's character sheet is the old parchment build: a wide transparent
	-- margin round the art, which is what the insets in the table above trim
	-- back. Cataclysm rebuilt it on ButtonFrameTemplate - modern, tight, no
	-- margin at all - and trimming ten off each side, thirty off the top and
	-- twenty-six off the foot of a window with nothing to spare CUTS INTO IT.
	--
	-- That is the whole of "the window doesn't encompass all the elements":
	-- both columns of gear hung outside the glass, the stat panel and the
	-- sidebar sat beyond its right edge, and the X went off the top corner as
	-- soon as the sheet was widened. This module's own vendor entry says so in
	-- as many words - "Insetting one of those cuts into the window ... which is
	-- what sizing and alignment issues looked like" - and this window was in
	-- the other list.
	--
	-- Its tabs hang off the BOTTOM edge outside its own art, the way the
	-- vendor's and the postbox's do, so the glass reaches below the frame to
	-- carry them rather than stopping at it.
	if A.isMists then
		local ch = PN.ENTRY.CharacterFrame
		ch.tight  = true
		ch.insets = { 0, 0, 0, -CHAR.tabDrop }

		-- AND IT ALREADY HAS ITS OWN RECESSES - two of them. CharacterFrameInset
		-- holds the doll and the gear; CharacterFrameInsetRight holds the stat
		-- panel and the sidebar's panes. Every piece of content on this window
		-- is inside one of them, which makes it the trainer's case and the trade
		-- window's: a body well round the outside would be a second rim round
		-- the first. They are dressed as our wells instead.
		ch.wells = false

		-- EVERY PANE BY THE SAME AMOUNT. This window anchors its content two
		-- ways at once - the gear hangs off the PANE, the stat panel off the
		-- RECESS - so a per-pane shift slides the gear out of the box drawn
		-- round it. The recess is brought down to match in DressCharacter; it
		-- is NOT in this list, for the reason written there.
		ch.together = true

		-- AND NOTHING MOVES SIDEWAYS, which is the part that was making a mess.
		--
		-- The inset shift exists for windows whose content the client hung
		-- against the frame's own edge, with nothing drawn round it - the
		-- vendor's rows are the case it was written for. This window is the
		-- opposite: its content is ALREADY inside two recesses of the client's
		-- own, correctly placed within them, and every horizontal relationship
		-- on it is already right.
		--
		-- Shifting it across broke that in two ways at once. The gear moved and
		-- the recess behind it did not, so both columns ended up outside the
		-- well; and the window then grew to pay for an inset it did not need,
		-- which is the "opens too wide" half of the report. The stat panel and
		-- the sidebar hang off the RIGHT-hand recess, so they went the other
		-- way and left the glass entirely.
		ch.keepWidth = true
		-- ITS X NEEDS NO ENTRY. ButtonFrameTemplate carries the close button as
		-- frame.CloseButton with no name of its own, where Era's sheet declares
		-- CharacterFrameCloseButton - but CloseButton() already falls back to
		-- Reskin.Element(frame, "CloseButton"), which finds a parent key. It was
		-- never lost; it was OUTSIDE THE GLASS, sitting at the top corner of a
		-- window our insets had trimmed thirty units in from. Naming it here
		-- would have looked like the fix and changed nothing.

		-- AND THE SPELLBOOK IS THE SAME WINDOW A SECOND TIME. Cataclysm rebuilt
		-- that one on ButtonFrameTemplate as well - tight, 550 wide, with an
		-- Inset of its own that everything in the book sits inside - where
		-- Era's is the old parchment volume at 384. Same four answers, for the
		-- same reasons; the comments above are the long version of each.
		local sb = PN.ENTRY.SpellBookFrame
		sb.tight     = true
		-- AND ITS SCHOOL TABS HANG OFF THE RIGHT EDGE, which Era's do not:
		-- Era anchors the column 32 INSIDE the window, Mists puts it hard on
		-- the outside, the same arrangement as the vendor's bottom tabs. So the
		-- glass reaches past the frame on that side to carry them, exactly as
		-- it reaches below to carry the row along the foot.
		-- POSITIVE, because the glass's width is the frame's plus insets[3]
		-- less insets[1]: a negative there pulls the edge IN, which is what
		-- Era's -30 does. Reaching PAST the frame wants a positive one.
		sb.insets    = { 0, 0, CHAR.schoolCol, -CHAR.tabDrop }
		-- ...BUT NOT `wells = false`, WHICH THE CHARACTER SHEET DOES NEED.
		--
		-- That distinction is about ANCHORING, not about the template. The
		-- sheet's stat panel and sidebar hang off CharacterFrameInsetRight, so
		-- its content cannot be moved away from the client's recesses and they
		-- have to be the wells. NOTHING in the book anchors to SpellBookFrame's
		-- Inset - every page is setAllPoints to the window and every spell is
		-- placed from the page's corner - so the book takes our own body well,
		-- with our padding, stopping at the rails, like every other window.
		--
		-- Adopting the client's recess here gave us the client's margins: four
		-- units at one side, six at the other and the foot of it against the
		-- tab rail.
		sb.together  = true

		-- TWO MORE PAGES, which Era's book has no equivalent of: your
		-- professions, and the abilities the client thinks define your spec.
		-- Both are setAllPoints to the window like the spell page, so both want
		-- measuring and moving with it.
		-- THREE, not two: "What has changed?" is a page of this book as well,
		-- and setAllPoints to the window like the rest.
		local sbody = sb.body
		for _, page in ipairs(CHAR.pages) do sbody[#sbody + 1] = page end

		-- AND NO ROOM RESERVED FOR THE RANK SWITCH. Mists has no spell ranks,
		-- so ShowAllSpellRanksCheckbox does not exist and the lead reserved
		-- over the page was a band of empty glass above every spell in the
		-- book.
		sb.lead = nil

		-- AND THE TALENT WINDOW IS A REWRITE, not a re-measure.
		--
		-- Era's is the old parchment tree: thirty talents, thirty branches and
		-- thirty arrows drawn between them. Mists threw the lot away for six
		-- tiers of three, plus a specialization page and a pet one - so the
		-- names our dresser reaches for describe a window this client does not
		-- build at all.
		--
		-- ButtonFrameTemplate again, 646x468, with its three tabs hanging off
		-- the bottom edge outside its own art. Third window in a row with the
		-- same shape; see ClientRecess and [[standard-components-first]].
		local tal = PN.ENTRY.PlayerTalentFrame
		tal.tight  = true
		tal.insets = { 0, 0, 0, -CHAR.tabDrop }

		-- WELLS = FALSE, AND EARNED THIS TIME. All three panes are anchored to
		-- PlayerTalentFrameInsetBg - the Bg texture of the client's own Inset -
		-- so their content cannot be moved away from that recess, exactly as
		-- the character sheet's stat panel cannot leave InsetRight. That is the
		-- test: an ANCHOR, not a template. The spellbook looks identical from
		-- the outside and takes our own well, because nothing in it is anchored
		-- to its Inset.
		tal.wells    = false
		tal.together = true

		-- ITS SUBTITLE IS ERA'S ONLY. "Points spent in Fire Talents: 0" belongs
		-- to a tree that no longer exists; PlayerTalentFrameSpentPointsText is
		-- declared in Classic/Blizzard_TalentUI.xml and nowhere else, so on
		-- Mists the band was reserving a second line for a string the client
		-- never creates.
		tal.subtitle = nil

		-- AND NOTHING IN THE BODY LIST, WHICH IS THE POINT.
		--
		-- The body list is for content the client hung off the WINDOW, which we
		-- then move down and in to clear our band. Every pane here is anchored
		-- to PlayerTalentFrameInsetBg instead - to the recess - so it is
		-- already correctly placed WITHIN that recess, and shifting it moves it
		-- out of the box drawn for it.
		--
		-- Listing them moved the content twice: once because the recess came
		-- down, and again because each pane was offset inside it. The dump
		-- showed all three reading "TOPLEFT->TOPLEFT 22,-20 on
		-- PlayerTalentFrameInsetBg" - twenty-two units out of a recess whose
		-- own measured inset was four.
		--
		-- So the recess is placed where a well goes and the panes are left
		-- alone; they follow it because they are tied to it. Nothing to measure
		-- means nothing to list.
		tal.body = {}

		-- AND LEARN IS AN ACTION, so it goes in a footer strip like every other
		-- window's. The client hangs it off the BOTTOM of whichever pane is up,
		-- 22 units BELOW that pane's own edge - so with the recess seated to
		-- our padding it landed between the content and the tab rail, in the
		-- gap rather than in a strip.
		--
		-- One per pane and all three listed, because the strip is laid out for
		-- whatever is VISIBLE - the same as the quest giver's seven and the
		-- postbox's four. They are parent keys with no globals of their own,
		-- which the entry reaches by path.
		-- AND THE PANES ARE DECLARED so their OnShow re-lays the strip.
		--
		-- WatchPanes hooks each named pane and refreshes the header, the footer
		-- and the tab row when one comes up. This entry had no `panes` key at
		-- all - its body list is empty on purpose, and I took that to mean the
		-- window had no panes to watch - so switching tab never re-laid the
		-- strip, and only the FIRST Learn button ever reached it. Joe's dump
		-- said so exactly: one reading "on the strip" and two still at the
		-- client's own "BOTTOM 0,-22" on their own panes.
		--
		-- Declaring a pane and listing it in `body` are different questions:
		-- one is "tell me when this comes up", the other is "measure and move
		-- this". These want the first and not the second.
		tal.panes = {
			{ pane = "PlayerTalentFrameSpecialization" },
			{ pane = "PlayerTalentFramePetSpecialization" },
			{ pane = "PlayerTalentFrameTalents" },
		}

		tal.footer  = W.PANEL_FOOT_H
		tal.actions = {
			mid = {
				"PlayerTalentFrameSpecialization.learnButton",
				"PlayerTalentFramePetSpecialization.learnButton",
				"PlayerTalentFrameTalents.learnButton",
			},
			-- THE REAGENT, AT THE LEFT END OF THE SAME STRIP. The client hangs
			-- it off the talents pane's BOTTOM LEFT corner, 8 in and 2 down -
			-- so with the recess seated it sat in the gap above the tab rail,
			-- on no line at all, while Learn stood in the strip beside it.
			--
			-- It says what undoing a talent will cost you, which is a fact
			-- about the button next to it. Same shape as the trainer's purse,
			-- which sits at the left end of the strip its Train button is
			-- centred in - and only the talents pane has one.
			-- TWO OF THEM, one per page that can undo something: the talents
			-- pane has a reagent line and so does the glyph frame. Only one is
			-- ever visible, and the strip lays out what is VISIBLE.
			left = { "PlayerTalentFrameTalents.clearInfo",
				"GlyphFrame.clearInfo" },
		}
	end
end

local function cfg() return A.Config:Module("panels") end

--- PANELS ARE A LITTLE TIGHTER THAN THE HUD, and never larger than it.
--
--  This was a FLOOR of 0.85, on the argument that the client's own furniture
--  - the paper doll, the item icons, its stat rows - is fixed pixel art that
--  stops being readable below about there. The argument is real and the floor
--  was the wrong shape for it: at a profile scale of 0.71 it drew every panel
--  at 0.85, which is a fifth larger than everything else on screen. The
--  windows did not look readable, they looked oversized - which is what was
--  reported.
--
--  So panels ride the profile's own scale, A TENTH ABOVE IT.
--
--  The panel package asks for its metrics at 0.92, on the grounds that they
--  were measured for review at a size that reads a tenth too generous. That is
--  a fair rule about the metrics THAT PACKAGE OWNS, and these windows are not
--  those: what is inside them is Blizzard's own furniture at a fixed pixel
--  size - a paper doll, item icons, stat rows - and none of it gets smaller
--  when our numbers do. It only gets more cramped.
--
--  0.92, then parity, then this, each step on the strength of looking at it,
--  which is the only test this one has. It is not derived from anything and
--  the comment should not pretend otherwise.
local PANEL_TIGHTEN = 1.1

--  The floor stays, an order lower, and it is now about the one thing it was
--  ever really about: below this the client's own art is not small, it is
--  gone. Nothing a player would choose comes near it.
local PANEL_MIN_SCALE = 0.45

--- A point on top of our usual sizes, for the same reason.
--
--  These windows are wide and their text sits in the client's own layout, with
--  its spacing, at its line heights - and our type at HUD sizes reads small in
--  that company.
local FONT_BUMP = 1
PN.FONT_BUMP = FONT_BUMP

local function PanelScale()
	local profile = A.db and A.db.profile
	local s = (profile and profile.scale or 1) * (cfg().scale or 1)
	return math.max(s * PANEL_TIGHTEN, PANEL_MIN_SCALE)
end

PN.Scale = PanelScale

--- Restyle a client string in one of ours, a point up.
local function Roled(fs, style)
	if not fs then return end
	local base = (A.Media.style[style] or {})[2]
	if base then fs._aetherSize = base + FONT_BUMP end
	W.Restyle(fs, style)
end
-- Published for Modules/PanelInteriors.lua, the other half of this module.
PN.Roled = Roled


-- ---------------------------------------------------------------------------
-- dressing
-- ---------------------------------------------------------------------------

--- The way out, in our own mark.
--
--  Blizzard's close button is a stone circle with an X baked into it, and with
--  its art stripped there is nothing left to click that looks like anything. So
--  it gets the same multiplication sign every window of ours already uses -
--  drawn on the client's own button, which keeps doing the closing.
--- A window's close button, under either spelling.
local function CloseButton(frame)
	local name = frame.GetName and frame:GetName()
	local entry = name and PN.ENTRY and PN.ENTRY[name]
	-- BY PARENT KEY OR BY GLOBAL. Most windows name their X as a global;
	-- the Options window keeps it as frame.ClosePanelButton and uses the
	-- name CloseButton for the ordinary button along the bottom - so the
	-- generic answer put our X on the wrong one, behind the word Close, and
	-- left the client's red one where it was.
	-- ...OR UNDER ANY OF SEVERAL, because the two clients spell some of these
	-- differently. First one the client has wins; see PN.Part.
	for _, alias in ipairs(entry and (type(entry.close) == "table"
		and entry.close or { entry.close }) or {}) do
		local btn = type(alias) == "string"
			and (frame[alias] or PN.Part(alias)) or nil
		if btn then return btn end
	end
	return Reskin.Element(frame, "CloseButton")
end

PN.CloseButton = CloseButton

-- Where the title sits inside the header band: centred in it on a plain
-- window, and lifted to make room when a subtitle follows. UP HERE because
-- DressHeader is written above the tab-strip metrics and a `local` used before
-- its declaration resolves to a GLOBAL - which is nil, and errors on the first
-- window dressed.
local HEAD_TITLE_Y     = W.PANEL_HEAD_H / 2
local HEAD_TITLE_Y_SUB = W.PANEL_HEAD_SUB / 2 - 7
-- Under the title, and not against it. One pixel was the handoff's number
-- and it is a number about 12pt type in a browser; at our sizes the two
-- lines touched.
local HEAD_SUB_GAP     = 4

-- How far above the window the chrome layer sits.
--
-- MEASURED, NOT DECLARED. Twenty was picked off the old hand-built windows,
-- whose panes sit a level or two above the frame. A modern one is nothing
-- like that: the gossip window carries children at 400, 500 and 510, so a
-- chrome layer at 21 was UNDER the client's own furniture and the band's
-- hairline was drawn behind the window it belongs to.
local CHROME_LIFT      = 20

-- How many times a window that cannot be measured is asked again. Bounded,
-- because one that never gets a rect must not be asked about it once a frame
-- for the rest of the session.
local SETTLE_TRIES     = 8


--- A level clear of everything the client has put in this window.
local function ChromeLevel(frame)
	local top = (frame.GetFrameLevel and frame:GetFrameLevel()) or 1

	-- NOT { frame.GetChildren and frame:GetChildren() }. An `and` in a table
	-- constructor is an expression, so it keeps the FIRST child and throws the
	-- rest away - which measured this window by whatever happened to be built
	-- first and put the chrome layer two levels above the frame again.
	local kids = frame.GetChildren and { frame:GetChildren() } or {}
	for _, kid in ipairs(kids) do
		-- OURS DO NOT COUNT. The chrome layer is a child of the window too, so
		-- measuring against it would push itself one lift higher on every dress
		-- until it ran out of levels.
		if kid ~= frame.__aetherChrome and kid ~= frame.__aetherPanel then
			-- PCALLED. A FORBIDDEN frame answers nothing at all - asking it for
			-- its own frame level throws "calling '?' on bad self" - and one of
			-- these windows has one among its children. Unguarded it took the
			-- whole module down with it at login: every panel in the interface
			-- came up in Blizzard's own art with no sign of why.
			local ok, lvl = pcall(kid.GetFrameLevel, kid)
			if ok and lvl and lvl > top then top = lvl end
		end
	end
	return top + CHROME_LIFT
end

-- Room kept clear at the right-hand end of a header band for the way out.
-- The row of controls under a header band, where a window has one: a filter,
-- a rank bar, a page count. Tall enough for the client's own dropdowns.
local TOOL_ROW         = 28
-- Between two actions in the footer. 15a's strip sets its own gap rather
-- than taking the body's 14 - a pair of buttons is not two blocks of
-- content.
local FOOT_GAP        = 12
-- How far up a chain we look for the window a widget belongs to. Two is
-- the deepest any of these actually is - a button on a pane on the window -
-- and the cap is there so a parent cycle cannot hang the layout.
local ROW_OWN_DEPTH   = 8
-- A row of chrome in the footer. A window with two of them - a page turn and
-- an action under it - GROWS by one rather than splitting the 52 between
-- them: split, each row got 26 and a 22 tall button has two pixels of air
-- under it, so Open All sat on the postbox's tab rule. 15a's 52 is what ONE
-- row needs; a second row needs its own.
local FOOT_ROW        = W.PANEL_FOOT_H / 2


-- ---------------------------------------------------------------------------
-- the header band
--
-- EVERY PANEL WEARS THE SAME ONE: a fixed band at the top with the title
-- centred in it and a hairline along its foot, and the way out in the corner.
-- The client's windows had none of it - each one put its title wherever its
-- own art wanted it, and nothing separated the title from what was under it,
-- so the two ran together on every window that has content near the top.
--
-- Taller when there is a subtitle. That is the one variation, and it is the
-- handoff's: a character sheet says who you are and then what you are, and the
-- second line needs somewhere to be.
-- ---------------------------------------------------------------------------

--- How tall this window's header is: the plain band, or the taller one.
function PN.HeaderHeight(name)
	local frame = name and _G[name]
	if frame and frame.__aetherHeadH then return frame.__aetherHeadH end
	local entry = name and PN.ENTRY and PN.ENTRY[name]
	if entry and PN.Part(entry.subtitle) then
		return W.PANEL_HEAD_SUB
	end
	return W.PANEL_HEAD_H
end

--- A string in the header band, in the header band's type.
--
--  NO BUMP, unlike every other client string here. The point is added because
--  these sit in rows and columns the client measured for its own smaller type;
--  a title has the width of the window to itself and does not need it.
local function HeadType(fs, style, colour)
	if not fs then return end
	-- NOT ALWAYS LETTERING. A window's second line can be a thing rather than
	-- a sentence: the trade skill's rank bar and the trainer's purse both sit
	-- under the title saying what this window is about, and both are frames.
	-- They get the place; the type is for strings.
	if not fs.SetFont then return end
	fs._aetherSize = nil
	W.Restyle(fs, style)
	W.Color(fs, colour)
end

--- Which pair of strings this window's header is naming right now.
--
--  Usually the entry's own. A window with panes in it can hand the band over
--  on one of them: the character sheet's pet tab is still CharacterFrame, but
--  the name at the top of it is the pet's.
function PN.HeaderPair(entry)
	for _, p in ipairs(entry and entry.panes or {}) do
		local pane = PN.Part(p.pane)
		-- ...and that brought a title with it. A pane can be up on a build
		-- where the string it names does not exist, and a header with no
		-- title at all is worse than one naming the wrong thing.
		local title = pane and pane.IsShown and pane:IsShown()
			and PN.Part(p.title) or nil
		if title then return title, PN.Part(p.subtitle) end
	end
	local title = entry and PN.Part(entry.title) or nil

	-- A TITLE WITH NO WORDS IN IT IS NOT THE TITLE.
	--
	-- The portrait chain gives a window TWO strings called TitleText: one on
	-- the frame from PortraitFrameTemplateNoCloseButton, one inside
	-- PortraitFrameBaseTemplate's unnamed TitleContainer. Only one of them is
	-- ever filled in, and which is not something to guess at.
	--
	-- The frame-level one has a global, so a lookup by name finds it, reports
	-- success, and hands the band an EMPTY string - while the client's own
	-- title goes on drawing in its own place, in its own gold. That is what
	-- "the title bar isn't being honoured" looked like on the spellbook, and
	-- why naming the container as a fallback fixed nothing: the fallback was
	-- never reached.
	if title and title.GetText and (title:GetText() or "") == "" then
		title = nil
	end

	-- ...AND THE PORTRAIT TEMPLATE'S TITLE HAS NO NAME AT ALL.
	--
	-- PortraitFrameBaseTemplate keeps it as $parentTitleText inside a
	-- TitleContainer - and that container is declared with a parentKey and NO
	-- name, so the string it holds is given no global either. Every window
	-- Cataclysm rebuilt on ButtonFrameTemplate is in this position, and a list
	-- of globals cannot reach one of them.
	--
	-- Which is why the band came up empty on the spellbook while the client's
	-- own gold title sat above it, in its own place, in its own lettering: the
	-- header component was working perfectly on a title it had never been
	-- handed. Tried last, so a window that DOES name its title keeps whichever
	-- string its entry asked for.
	if not title and entry and entry.frame then
		local f = _G[entry.frame]
		-- BOTH SHAPES, because the chain gives a window both and which one the
		-- client actually fills is not something to guess at.
		-- PortraitFrameBaseTemplate puts the string in an unnamed
		-- TitleContainer; PortraitFrameTemplateNoCloseButton declares another
		-- at frame level. Either way it is `TitleText` on the thing that holds
		-- it, so both are asked and the one carrying words wins.
		--
		-- SPELLED OUT RATHER THAN LOOPED. Written as ipairs over a two-element
		-- table it read fine and did nothing: a hole at index one ends an ipairs
		-- immediately, so a window with no frame-level string never reached the
		-- container's - which is every window this fallback exists for.
		local c = f and f.TitleContainer
		local own, inner = f and f.TitleText, c and c.TitleText
		local function worded(fs)
			return fs and fs.GetText and (fs:GetText() or "") ~= "" and fs or nil
		end
		-- The one carrying words first, then either - a window whose title is
		-- genuinely blank still wants a string in the band to write into.
		title = worded(own) or worded(inner) or own or inner
	end

	return title, entry and PN.Part(entry.subtitle) or nil
end

--- The frame a panel entry means by a name.
--
--  A global, or a PATH through one - because the modern templates stopped
--  naming things globally. The gossip window's list of what you can say is
--  GossipFrame.GreetingPanel.ScrollBox and has no name of its own at all, so
--  a list of globals cannot reach a single part of it.
function PN.Part(name)
	-- OR ANY OF SEVERAL NAMES. The same part of the same window is spelled
	-- differently across the two clients this addon serves - the spell book's
	-- title is SpellBookTitleText on Era and SpellBookFrameTitleText on Mists -
	-- so an entry may give a LIST, and the first name the client has wins.
	-- That keeps the flavour difference in the ENTRY table, where the rest of
	-- the anatomy lives, rather than in a branch at every place a part is read.
	if type(name) == "table" then
		for _, alias in ipairs(name) do
			local found = PN.Part(alias)
			if found then return found end
		end
		return nil
	end
	if type(name) ~= "string" then return nil end
	local w
	for step in name:gmatch("[^.]+") do
		w = (w == nil) and _G[step] or (type(w) == "table" and w[step] or nil)
		if w == nil then return nil end
	end
	-- ...AND NOT ONE THE CLIENT HAS PUT OUT OF REACH. Every name this file
	-- resolves is handed straight to something that measures or moves it, and
	-- every method on a forbidden frame throws - so the guard belongs here,
	-- once, rather than at each of the dozen places a part is used.
	--
	-- The trade window's own money field is one: TradeFrame_OnLoad calls
	-- SetForbidden on it, it is named in that window's body list, and the
	-- first pass that measured it took the footer and the whole interior down
	-- with it.
	if Reskin.Forbidden(w) then return nil end
	return w
end
local Part = PN.Part

--- ONE THING IN A ROW, UNDER ANY OF THE NAMES IT MIGHT HAVE.
--
--  These windows are named three ways across the game versions this client
--  carries: a global, a parentKey on the window, or a global under a different
--  spelling again. The trade skill's filters are
--  TradeSkillFrame.SubClassDropdown here and TradeSkillSubClassDropDown in the
--  source Blizzard published - and an entry that named one of them put neither
--  filter in the row, so both stayed where the client's own art had left them,
--  across the window's title.
local function RowPart(frame, name)
	if type(name) == "table" then
		for _, alias in ipairs(name) do
			local found = RowPart(frame, alias)
			if found then return found end
		end
		return nil
	end
	local w = Part(name) or Reskin.Element(frame, name)
	return w and w.ClearAllPoints and w or nil
end

--- Is there anything in this list for the pane that is up?
--
--  VISIBLE, not shown - see ChromeRow. Every one of the postbox's actions is a
--  child of the pane it belongs to and carries its own flag the whole time;
--  what the client hides is the PANE.
--- Is this widget actually a part of the window being laid out?
--
--  VISIBLE IS NOT ENOUGH, and the social window is why. RaidFrame carries
--  no parent in its XML - "Parent set dynamically, see ClaimRaidFrame" - and
--  it is not hidden either, so from the moment its addon loads it is a shown
--  frame with nothing above it. A frame outside UIParent's hierarchy is never
--  DRAWN, but IsVisible walks the parent chain and a chain that simply ends
--  has no hidden link in it: every child of it answers yes.
--
--  So Convert to Raid took a slot in the friends window's strip, 115 wide,
--  and drew nothing in it - which is Add Friend and Send Message a button's
--  width further apart than they should be, one of them hanging off each
--  side of the glass. It only appears after the raid tab has been visited
--  once, because until then the button does not exist at all.
--
--  The client makes the same test itself: FriendsFrame_ShowSubFrame hides
--  RaidFrame only `if RaidFrame:GetParent() == FriendsFrame`. A pane that
--  has been claimed by somebody else is not this window's to hide, and its
--  buttons are not this window's to place.
local function Owns(frame, w)
	local f = w
	for _ = 1, ROW_OWN_DEPTH do
		if f == frame then return true end
		f = f.GetParent and f:GetParent()
		if not f then return false end
	end
	return false
end

--- Up, and ours: the two questions every one of these rows asks.
local function RowUsable(frame, w)
	return w and w.IsVisible and w:IsVisible() and Owns(frame, w) or false
end

local function RowLive(frame, list)
	for _, name in ipairs(list or {}) do
		if RowUsable(frame, RowPart(frame, name)) then return true end
	end
	return false
end

--- A row of chrome: a group pinned to each end, a group centred between.
--
--  The tool row under the band and the footer strip along the bottom are the
--  same shape at two heights, so they are one function - the row's version
--  had already drifted, and it anchored from the layer's LEFT. A frame's LEFT
--  is its vertical MIDDLE: the trainer's purse ended up two thirds of the way
--  down the window with the skill list drawn over the top of it.
--
--  `edge` is TOP or BOTTOM, `y` is from that edge, and `gap` is what goes
--  between two things in the row.
local function ChromeRow(frame, spec, anchor, edge, y, gap)
	if not spec then return end

	-- WHAT A THING TAKES UP in a row. A font string's declared width is the
	-- BOX the client reserved for it and not the words in it - the page count
	-- in a book is 192 wide and says "Page 1" - so measuring the box pushed
	-- the two page turns to opposite ends of the strip.
	local function span(w)
		if w.GetStringWidth and w.GetObjectType
			and w:GetObjectType() == "FontString" then
			local words = w:GetStringWidth()
			if words and words > 0 then return words end
		end
		return (w.GetWidth and w:GetWidth()) or 0
	end

	local part = function(name) return RowPart(frame, name) end

	-- VISIBLE, the way the middle group below already is. These two chains
	-- used to place everything named whether it was up or not, which is fine
	-- for a window whose row belongs to one pane and wrong for one whose row
	-- serves five: the social window's query field would hold the first slot
	-- on the raid tab and push the raid's own switch along behind it.
	local function live(name)
		local w = part(name)
		if RowUsable(frame, w) then return w end
		return nil
	end

	local prev
	for _, name in ipairs(spec.left or {}) do
		local w = live(name)
		if w then
			w:ClearAllPoints()
			if prev then
				w:SetPoint("LEFT", prev, "RIGHT", gap, 0)
			else
				w:SetPoint("LEFT", anchor, edge .. "LEFT", W.PANEL_PAD, y)
			end
			prev = w
		end
	end

	prev = nil
	for _, name in ipairs(spec.right or {}) do
		local w = live(name)
		if w then
			w:ClearAllPoints()
			if prev then
				w:SetPoint("RIGHT", prev, "LEFT", -gap, 0)
			else
				w:SetPoint("RIGHT", anchor, edge .. "RIGHT", -W.PANEL_PAD, y)
			end
			prev = w
		end
	end

	-- THE MIDDLE GROUP is measured rather than chained off an end, because it
	-- is centred on the window: where it starts depends on how wide the whole
	-- group is, and which of its members are up changes with the pane.
	--
	-- VISIBLE, not shown. Every one of the quest giver's seven buttons is a
	-- child of the panel it belongs to and carries its own flag the whole
	-- time; what the client hides is the PANEL. Asking IsShown put all seven
	-- in the strip on top of each other.
	local shown, total = {}, 0
	for _, name in ipairs(spec.mid or {}) do
		local w = part(name)
		if RowUsable(frame, w) then
			shown[#shown + 1] = w
			total = total + span(w)
		end
	end
	for _, w in ipairs(frame.__aetherActions or {}) do
		if RowUsable(frame, w) and w.ClearAllPoints then
			shown[#shown + 1] = w
			total = total + span(w)
		end
	end
	if #shown == 0 then return end
	total = total + gap * (#shown - 1)

	-- IN THE ORDER THE CLIENT HAD THEM, left to right. Some of these have no
	-- name to declare - the trainer's Train All is an anonymous child - so
	-- they are found by shape, and where they were is the only thing that
	-- says which of them the player reads first.
	table.sort(shown, function(a, b)
		return ((a.GetLeft and a:GetLeft()) or 0) < ((b.GetLeft and b:GetLeft()) or 0)
	end)

	local x = -total / 2
	for _, w in ipairs(shown) do
		w:ClearAllPoints()
		w:SetPoint("LEFT", anchor, edge, x, y)
		x = x + span(w) + gap
	end
end

--- The band's hairline, and the title placed in it.
--
--  `title` and `sub` are passed rather than looked up, because one frame can
--  carry more than one of each: the character sheet's header says who YOU are
--  on its first tab and who your PET is on its second, out of two different
--  pairs of strings that the client owns.
function PN.DressHeader(frame, entry, title, sub)
	local ins = entry and entry.insets or {}
	local name = frame.GetName and frame:GetName()
	local h = (sub and W.PANEL_HEAD_SUB) or W.PANEL_HEAD_H
	frame.__aetherHeadH = h

	-- ON THE CHROME LAYER, which is the only place a hairline is safe.
	--
	-- It was a texture of the WINDOW first, and a frame's own textures always
	-- draw under its children - so the glass, which is a child, painted over
	-- it on every panel. Moving it onto the glass fixed the windows whose
	-- content starts below the band and not the ones whose content starts in
	-- it: the client's panes are children of the window too, so they draw over
	-- the glass and over anything on it. The vendor window lost its hairline
	-- that way while the character sheet kept one.
	--
	-- The band is CHROME. Nothing the client draws is allowed above it, so it
	-- gets a layer of its own with a level well clear of the panes'.
	local host = frame.__aetherPanel or frame
	local layer = frame.__aetherChrome
	if not layer then
		layer = CreateFrame("Frame", nil, frame)
		if layer.EnableMouse then layer:EnableMouse(false) end
		frame.__aetherChrome = layer
	end
	layer:ClearAllPoints()
	layer:SetAllPoints(host)
	if layer.SetFrameLevel and frame.GetFrameLevel then
		layer:SetFrameLevel(ChromeLevel(frame))
	end
	layer:Show()

	-- THROUGH THE COMPONENT, like every other hairline in the interface. This
	-- one was the last hand-rolled copy - its own CreateTexture, its own layer,
	-- its own texture - which is exactly the arrangement that had four private
	-- versions of a one-pixel line drifting apart from each other.
	local rule = frame.__aetherHeadRule
	if not rule or rule.__aetherHost ~= layer then
		rule = W.Hairline(layer)
		rule.__aetherHost = layer
		frame.__aetherHeadRule = rule
	end

	-- Across the GLASS, which is already trimmed to the window you can see -
	-- so there are no insets to apply a second time here.
	rule:ClearAllPoints()
	rule:SetPoint("TOPLEFT", layer, "TOPLEFT", W.RULE_GAP, -h)
	rule:SetPoint("TOPRIGHT", layer, "TOPRIGHT", -W.RULE_GAP, -h)
	W.PaintHairline(rule)
	rule:Show()

	-- AND THE TOOL ROW, under the band rather than in it.
	--
	-- These are the things that act on what the window is SHOWING - a filter, a
	-- rank bar, a page count. Chrome, so they do not belong in the recess; but
	-- a band is one line of type wide and they do not fit beside a title
	-- either. The trade skill proved it: its rank bar is three hundred across
	-- and its two filters were laid over the top of it.
	ChromeRow(frame, entry and entry.row, layer, "TOP",
		-(h + W.PANEL_PAD + TOOL_ROW / 2), W.PANEL_GAP)
	-- CENTRED IN THE BAND, and centred across the window. Every one of these
	-- put its title where its own art wanted it - the spellbook's six pixels
	-- right of centre, because the page it was printed on was not centred in
	-- the frame either.
	if title and title.ClearAllPoints then
		title:ClearAllPoints()
		title:SetPoint("TOP", host, "TOP", 0,
			-(sub and HEAD_TITLE_Y_SUB or HEAD_TITLE_Y))
		if title.SetJustifyH then title:SetJustifyH("CENTER") end
	end

	if sub and sub.ClearAllPoints then
		sub:ClearAllPoints()
		sub:SetPoint("TOP", title or host, title and "BOTTOM" or "TOP", 0,
			title and -HEAD_SUB_GAP or -HEAD_TITLE_Y_SUB)
		if sub.SetJustifyH then sub:SetJustifyH("CENTER") end
	end
	return h
end

local DressHeader = PN.DressHeader

--- Redraw a window's header for whatever pane it is showing now.
function PN.RefreshHeader(name)
	local frame, entry = _G[name], PN.ENTRY and PN.ENTRY[name]
	if not (frame and entry and frame.__aetherPanel) then return end
	local title, sub = PN.HeaderPair(entry)
	title = title or frame.__aetherTitle
	-- RECORDED, because on a window with panes the band's title is not the
	-- one Dress found: the postbox's own $parentTitleText is never filled in
	-- and the words that name the tab live inside the pane. Everything that
	-- asks what this window is called reads this.
	frame.__aetherTitle = title
	HeadType(title, "pnTitle", Palette.c.text)
	HeadType(sub, "pnSub", Palette.c.textDim)
	DressHeader(frame, entry, title, sub)
end

-- ---------------------------------------------------------------------------
-- the body
--
-- ONE WELL, ON EVERY PANEL. 15a: a panel is header, then body, then footer or
-- tab rail; the body is the padding in from the glass on all four sides, and
-- everything bounded inside it sits in a recess - background black at 0.22,
-- the skin's border at 0.13, corner 14. This was being drawn per window, on
-- whatever that window's dresser happened to think was content: a well round
-- the character model and nothing at all round the rest of the sheet.
--
-- THE CLIENT'S CONTENT DOES NOT START WHERE OUR BODY DOES. Every one of these
-- windows left a strip at the top for the stone title plate it used to wear -
-- the character sheet's first slot is anchored 74 below the frame, which is 64
-- below the glass - and that strip is close to our header band but not the
-- same, and has no room in it for the body padding. So the body is placed
-- first and the client's panes are moved DOWN by whatever they are short of
-- it, and the window grows by the same amount so nothing anchored to its
-- bottom edge falls out.
--
-- The panes are the containers the client hangs a whole tab off, and they are
-- setAllPoints to the window - so moving the pane carries every slot, string
-- and model in it, and nothing inside needs to know.
-- ---------------------------------------------------------------------------

--- A rail on one edge of this window, if there is one up.
--
--  Returned rather than measured, because the body stops AT the rail and the
--  rail already knows where it is - a width would be a second copy of a number
--  the tab code owns, and the two would drift the first time either moved.
local function RailOn(frame, edge)
	local rail = frame.__aetherRails and frame.__aetherRails[edge]
	if rail and rail:IsShown() then return rail end
	return nil
end

--- Everything on this window that belongs to US and not to the client.
--
--  Wanted for measuring: the walk below is looking for the client's content
--  and our own glass, hairline and recess are all children of the same frame.
local function OurParts(frame)
	local ours = {}
	for _, key in ipairs({ "__aetherPanel", "__aetherChrome", "__aetherBody",
		"__aetherTitle", "__aetherClose" }) do
		if frame[key] then ours[frame[key]] = true end
	end
	for _, rail in pairs(frame.__aetherRails or {}) do ours[rail] = true end
	-- EVERY TITLE THE ENTRY NAMES, not merely the one the band is carrying.
	--
	-- A window with panes has a title string per pane, and the ones belonging
	-- to the panes that are DOWN are still strings sitting near the top of the
	-- window. Send Mail's is four units below the glass, so measuring the pane
	-- while the inbox was up said its content started there - and the form was
	-- pushed down by eighty-four units to clear a band it was already clear of,
	-- leaving a hand's width of nothing at the top of the recess.
	local entry = frame.GetName and PN.ENTRY and PN.ENTRY[frame:GetName()]
	local function spare(name)
		local fs = PN.Part(name)
		if fs then ours[fs] = true end
	end
	spare(entry and entry.title)
	spare(entry and entry.subtitle)
	for _, pane in ipairs(entry and entry.panes or {}) do
		spare(pane.title)
		spare(pane.subtitle)
	end
	return ours
end

--- Where the client's own content starts, in units below the top of the glass.
--
--  MEASURED, NOT DECLARED. This started as a number per window read out of
--  Blizzard's XML, and every window turned out to need a different one - the
--  character sheet's first slot at 74, the reputation columns at 57, the skill
--  list's ALL tab at 49, the talent frame's points line somewhere else again -
--  and the character sheet alone needs four, because each of its tabs starts
--  at its own height. Four rounds of screenshots found four of them.
--
--  Only frames and lettering count. A stripped texture still has the size the
--  art had, so a window whose parchment we took off would measure as content
--  starting at its very top edge; and a container anchored to the whole window
--  says nothing about where what is IN it begins, so those are walked through
--  rather than counted.
local function MeasureTop(frame, pane)
	if pane.__aetherTop then
		return pane.__aetherTop, pane.__aetherLeft, pane.__aetherRight
	end
	local host = frame.__aetherPanel or frame
	local ceiling = host.GetTop and host:GetTop()
	local wall = host.GetLeft and host:GetLeft()
	local far = host.GetRight and host:GetRight()

	-- AND THE FAR EDGE IS THE RAIL WHERE THERE IS ONE. The recess stops at the
	-- tab column, not at the glass - so a window measured against the glass
	-- thinks its content has a hand's width of room it does not have, and the
	-- spellbook's second column of spell names ran out through the rim and
	-- under the school tabs.
	local side = RailOn(frame, "RIGHT")
	local rail = side and side.GetLeft and side:GetLeft()
	if rail and (not far or rail < far) then far = rail end

	if not (ceiling and wall and far) then return nil end

	local ours = OurParts(frame)
	local best, side, edge
	-- NOTHING WITH NO ANCHORS. A frame the client has not placed has no rect
	-- at all, and taking one from it is measuring a coordinate that does not
	-- exist - which lands at the window's own corner and reads as content
	-- starting there.
	local function placed(f)
		return f.GetNumPoints and (f:GetNumPoints() or 0) > 0
	end

	local function note(f)
		if not placed(f) then return end
		local top = f.GetTop and f:GetTop()
		if top and top < ceiling and (not best or top > best) then best = top end
		-- WHEREVER IT IS, at BOTH ends, including past the edge it should have
		-- stopped at. This used to ignore anything reaching beyond the boundary,
		-- which meant the one thing it could never measure was content that
		-- ALREADY overflows - so a window whose text runs out through the rim
		-- could not be widened to fit it. The spellbook's second column of spell
		-- names is that case: our lettering is wider than the client's, and the
		-- names ran under the school tabs.
		--
		-- THE LEFT KEPT ITS GUARD FOR A YEAR AFTER THE RIGHT LOST ITS OWN, and a
		-- guard on one end only is worse than one on both: `left >= wall`
		-- discards content that starts OUTSIDE the glass, and discarding it
		-- leaves `side` nil, which reads as "nothing to measure" and moves the
		-- pane not at all. So the one arrangement it could never fix - content
		-- already out through the rim - was the one arrangement that most needed
		-- fixing, and it failed by doing nothing, which looks like a window
		-- nobody laid out rather than one laid out wrongly.
		--
		-- The quest giver on Mists is exactly that. Blizzard gates the templates
		-- per flavour, and its scroll frames sit 23 in on Era but FIVE on Mists
		-- against glass inset 8 - so every word of every quest was printed hard
		-- against the window's edge, outside the recess drawn for it.
		--
		-- A negative `left` is not a special case: `inner - left` simply asks for
		-- a larger shift, which is the right answer for content that starts
		-- further out.
		local left = f.GetLeft and f:GetLeft()
		if left and (not side or left < side) then side = left end
		local right = f.GetRight and f:GetRight()
		if right and (not edge or right > edge) then edge = right end
	end

	local function walk(f, depth)
		-- NOTHING THE CLIENT HAS PUT OUT OF REACH. It is still in its parent's
		-- child list and every method on it throws, so a walk that asks each
		-- child for its rect would die on the first one it met.
		--
		-- BELT AND BRACES, and said so plainly: PN.Part already refuses to
		-- hand one of these out, so no window we know of reaches this line
		-- with a forbidden frame - the trade window's money field is a child
		-- of the WINDOW rather than of anything measured. Kept because the
		-- next one might not be, and the cost is one call.
		if depth > 4 or ours[f] or Reskin.Forbidden(f) then return end
		-- NOT { (f:GetRegions()) }. Parentheses round a call truncate it to one
		-- value, so a walk written that way sees the first region and the first
		-- child of every frame and nothing else - which measured three of the
		-- character sheet's tabs correctly by luck and the fourth not at all.
		local regs = f.GetRegions and { f:GetRegions() } or {}
		for _, r in ipairs(regs) do
			-- Lettering with something in it. A texture is either art we have
			-- already taken off - which keeps its rect - or a decoration.
			if not ours[r] and r.GetText and r:IsShown()
				and (r:GetText() or "") ~= "" then
				note(r)
			end
		end
		-- WHAT A SCROLL FRAME HOLDS IS NOT PART OF THE WINDOW'S SHAPE. The page
		-- inside one is CLIPPED by it and can be any size at all - a trade
		-- skill's detail page is the whole recipe - so measuring it grew the
		-- window by a hand's width of empty glass. The scroll frame's own rect is
		-- the honest answer and it has already been taken.
		local scrolled = f.GetScrollChild and f:GetScrollChild()
		local kids = f.GetChildren and { f:GetChildren() } or {}
		for _, c in ipairs(kids) do
			if Reskin.Forbidden(c) then c = nil end
			-- NO `goto` HERE, and none anywhere else in this addon: the game runs
			-- Lua 5.1, which has no such statement. LuaJIT does, so the harness
			-- compiled it happily and the whole file failed to load in the client.
			if c and c ~= scrolled and not ours[c] and c.IsShown and c:IsShown() then
				local top = c.GetTop and c:GetTop()
				-- A CONTAINER SAYS NOTHING. One anchored to the whole window
				-- reaches the top edge whatever is inside it, so it is walked
				-- through instead of counted.
				if top and top < ceiling then note(c) end
				-- AND KEEP GOING. The widest thing on the vendor's window is not the
				-- row - its template is a good deal wider than the name and price
				-- printed in it - so stopping at the row measures a box with air in
				-- it and pads the window out to fit the air.

				walk(c, depth + 1)
			end
		end
	end
	-- The mover may BE the content rather than contain it: a window with no
	-- pane at all is moved by its first item, and everything the client chains
	-- off that comes with it. Anything sitting at the top edge is a container,
	-- so it is walked into instead.
	local own = pane.GetTop and pane:GetTop()
	if own and own < ceiling then note(pane) end
	walk(pane, 0)

	if not best then return nil end
	pane.__aetherTop = ceiling - best
	pane.__aetherLeft = side and (side - wall) or nil
	pane.__aetherRight = edge and (far - edge) or nil
	return pane.__aetherTop, pane.__aetherLeft, pane.__aetherRight
end
--- How far up the body has to stop for this window's footer.
--
--  THE STRIP ITSELF AND NOTHING UNDER IT. 15a puts a fixed 52 above the
--  window's bottom edge - or above the tab rail, where one replaces it - with
--  the body's padding only on TOP of it. Inset by the padding at both ends it
--  read as a row of buttons pushed up, with a third of the strip's height of
--  empty glass beneath them and nothing in it.
--- How many rows of chrome the footer carries. One, unless the entry declares
--  something to go under them.
local function FootRows(entry)
	local acts = entry and entry.actions
	return (acts and acts.under and #acts.under > 0) and 2 or 1
end

local function FootStrip(entry)
	local strip = (entry and entry.footer) or 0
	if strip <= 0 then return 0 end
	return strip + (FootRows(entry) - 1) * FOOT_ROW
end

--- The hairline along the top of the footer strip.
--
--  15a draws one: the strip is bounded above the way the header band is
--  bounded below, and without it the actions read as floating in the glass
--  under the recess rather than standing in a strip of their own.
local function FootRule(frame, host, foot, strip)
	local rule = frame.__aetherFootRule
	if strip <= 0 then
		if rule then rule:Hide() end
		return
	end

	-- ON THE CHROME LAYER, for the same reason the header's is: a texture on
	-- the window draws under the window's children, and the client's panes are
	-- children of it - so a rule drawn anywhere else is under whatever the
	-- window is showing.
	local layer = frame.__aetherChrome or host
	if not rule or rule.__aetherHost ~= layer then
		rule = W.Hairline(layer)
		rule.__aetherHost = layer
		frame.__aetherFootRule = rule
	end
	W.PaintHairline(rule)

	-- OFF THE RAIL WHERE THERE IS ONE. The strip sits above the tabs, not on
	-- the window's bottom edge - 15e: a rail replaces the footer, and where a
	-- window has both the client put them there, they stack in that order.
	local anchor = foot or host
	local edge = foot and "TOP" or "BOTTOM"
	rule:ClearAllPoints()
	rule:SetPoint("BOTTOMLEFT", anchor, edge .. "LEFT", W.RULE_GAP, strip)
	rule:SetPoint("BOTTOMRIGHT", anchor, edge .. "RIGHT", -W.RULE_GAP, strip)
	rule:Show()
end

--- The panes of a window that swaps them without a tab to say so.
--
--  A tabbed window tells us through PanelTemplates_UpdateTabs. The quest
--  giver has no tabs at all: it swaps between reading a quest, handing one in
--  and being thanked for it by showing one of four panels, and both the band
--  and the footer strip say something different on each.
--
--  HOOKED ONCE. A dresser runs again on every skin change, and a second hook
--  on the same pane is a second pass over the same buttons.
local function WatchPanes(frame, entry)
	local name = frame.GetName and frame:GetName()
	if not name then return end

	-- THE WINDOW ITSELF TOO. A pane fires OnShow only on the way from hidden
	-- to shown, and the client puts the panel up before it puts the window up
	-- - so on the first quest of a session the strip was laid out while
	-- nothing in it was visible yet, and stayed where the client left it.
	if frame.HookScript and not frame.__aetherPaneWatch then
		frame.__aetherPaneWatch = true
		frame:HookScript("OnShow", function()
			if not PN.enabled then return end
			PN.RefreshFooter(name)
		end)
	end

	for _, p in ipairs(entry and entry.panes or {}) do
		local pane = PN.Part(p.pane)
		if pane and pane.HookScript and not pane.__aetherWatched then
			pane.__aetherWatched = true
			pane:HookScript("OnShow", function()
				if not PN.enabled then return end
				PN.RefreshHeader(name)
				PN.RefreshFooter(name)
				-- AND THE TABS, for a window whose panes move them. See
				-- PN.RefreshTabs: the group finder re-anchors both of its
				-- tabs from each pane's OnShow, and that lands them off the
				-- rail they are meant to be standing on.
				PN.RefreshTabs(name)
			end)
		end
	end
end

-- Reachable for the diagnostic, which needs to ask what a pane measures at
-- RIGHT NOW rather than what it measured whenever the window was last
-- dressed. The two being different is the whole question when a window comes
-- up laid out for a rect it did not have yet.
PN.MeasureTop = MeasureTop

--- Does this pane FILL the window, corner to corner?
--
--  A pane that does is a container, not a box: the client hangs things off
--  its top for the ones that read down the page and off its BOTTOM for the
--  ones that sit along the foot. The character sheet's weapon row is the
--  second kind - 127 up from the pane's bottom edge - so shifting the whole
--  pane down moved it twice: once with the pane and once more when the window
--  grew underneath it. It ended up through the foot of the recess and across
--  the tab rail, on the character sheet and on the inspect window both.
local function Fills(frame, pts)
	-- ONE CORNER IS ENOUGH when it is the window's own and carries no offset:
	-- the postbox's two panes are 384 by 512 pinned to the top left of a window
	-- exactly that size, which is a page by any reading. They are not pinned by
	-- both corners, so nothing held their feet and the money block Send Mail
	-- hangs off its bottom went down the window with the rest of the pane and
	-- landed on top of Send and Cancel.
	if #pts == 1 then
		local pt = pts[1]
		return pt[1] == "TOPLEFT" and pt[2] == frame and pt[3] == "TOPLEFT"
			and (pt[4] or 0) == 0 and (pt[5] or 0) == 0, true
	end
	if #pts < 2 then return false end
	local top, bottom = false, false
	for _, pt in ipairs(pts) do
		if pt[2] == frame and (pt[4] or 0) == 0 and (pt[5] or 0) == 0 then
			if pt[1] == "TOPLEFT" and pt[3] == "TOPLEFT" then top = true end
			if pt[1] == "BOTTOMRIGHT" and pt[3] == "BOTTOMRIGHT" then
				bottom = true
			end
		end
	end
	return top and bottom
end

--- Rows that belong to a list but are not in it.
--
--  A faux scroll frame is a scroll BAR and nothing else: the client hangs the
--  rows off the WINDOW and scrolls them by refilling. So moving the list into
--  the recess left every row exactly where it was - printed on the glass
--  above an empty box, which is what the trainer and both crafting windows
--  looked like.
--
--  Re-anchored to the list rather than offset alongside it, and ONCE: the
--  offset is measured off where the CLIENT had the two of them, so a second
--  pass would be measuring our own work.
local function Inside(entry)
	for who, host in pairs(entry and entry.inside or {}) do
		local w, h = Part(who), Part(host)
		if w and h and not w.__aetherInside and w.GetLeft and h.GetLeft
			and w:GetLeft() and h:GetLeft() and w:GetTop() and h:GetTop() then
			w.__aetherInside = true
			local dx = w:GetLeft() - h:GetLeft()
			local dy = h:GetTop() - w:GetTop()
			w:ClearAllPoints()
			w:SetPoint("TOPLEFT", h, "TOPLEFT", dx, -dy)
		end
	end
end

--- Is there anything in this window's tool row right now?
--
--  VISIBLE, NOT SHOWN, which is the same distinction the footer's middle
--  group is written round: what the client hides when it swaps panes is the
--  PANE, and every child of it goes on reporting itself shown the whole time.
--  The social window is why it matters here - one row serves five panes, and
--  asked whether they were shown, all five panes' worth answered yes.
local function RowUp(frame, spec)
	for _, side in ipairs({ "left", "right", "mid" }) do
		if RowLive(frame, spec[side]) then return true end
	end
	return false
end

--- The recess, and the client's content moved into it.
function PN.LayoutBody(frame, entry)
	local host = frame.__aetherPanel
	if not host then return end


	-- HOW MANY TIMES THIS HAS RUN, and what the window was able to tell us
	-- each time. A window laid out once, at login, while it had no rect is
	-- indistinguishable on screen from one laid out wrongly - and the two want
	-- opposite fixes. The readout prints both.
	frame.__aetherRuns = (frame.__aetherRuns or 0) + 1
	frame.__aetherSeen = host.GetTop and host:GetTop()

	-- AND ANOTHER GO IF THERE WAS NOTHING TO MEASURE. A window has no rect at
	-- all until the panel system places it, which happens after it is shown, so
	-- the first answer is nil and the window keeps it.
	--
	-- WATCHED ON OUR OWN LAYER RATHER THAN ON A HOOK OF THE CLIENT'S. Three
	-- hooks were tried before this and not one of them fired on the gossip
	-- window: OnShow does not come round again for a window that was already up
	-- when the addon loaded, and not every window goes up through the panel
	-- system's front door. The chrome layer is a CHILD of the window, so its
	-- OnUpdate runs exactly when there is a window on screen to measure and
	-- never otherwise - no hook to miss, and nothing ticking while it is shut.
	local watch = frame.__aetherChrome
	if frame.__aetherSeen then
		frame.__aetherTries = nil
		if watch and watch.SetScript then watch:SetScript("OnUpdate", nil) end
	elseif watch and watch.SetScript then
		watch:SetScript("OnUpdate", function(self)
			self:SetScript("OnUpdate", nil)
			if not PN.enabled then return end
			frame.__aetherTries = (frame.__aetherTries or 0) + 1
			if frame.__aetherTries > SETTLE_TRIES then return end
			local ok, err = pcall(PN.Dress, frame)
			if not ok then
				PN.failures = PN.failures or {}
				local who = frame.GetName and frame:GetName()
				if who then PN.failures[who] = "on watch: " .. tostring(err) end
			end
		end)
	end

	Inside(entry)
	local headH = frame.__aetherHeadH or W.PANEL_HEAD_H
	local pad   = W.PANEL_PAD

	-- SHIFT FIRST, because the well is placed off the header and the header is
	-- the thing the content has to clear.
	--
	-- PER PANE, because a window with tabs has a different answer on each of
	-- them: the character sheet's first equipment slot, its reputation column
	-- headings and its skill list's ALL tab all start at different heights, and
	-- one number for the window put two of the three across the hairline.
	--
	-- `lead` is room reserved INSIDE the well, above the client's content, for
	-- something of the window's own that is content rather than chrome - the
	-- spellbook's rank switch is the case: it is a control over the list, the
	-- same as a tree's expand-all would be, so it belongs in the recess with
	-- the list and not floating in the band above it.
	-- BOTH AXES. The vendor's rows are anchored eleven in from the window and
	-- the body is eighteen, so its icons hung out of the recess on the left and
	-- its prices out of it on the right - the same seven units at each end.
	--
	-- AND INSIDE THE WELL'S OWN PADDING, not against its rim. 15b gives a well
	-- sixteen on all four sides; content moved only as far as the body's edge
	-- is content jammed into the corner of the recess, which is where the
	-- reputation columns ended up - touching the top rail and the left one.
	-- A WINDOW WHOSE PANES ARE ALREADY WELLS is inset by what its own rim
	-- costs rather than by the well padding: the recess round a client scroll
	-- frame is drawn WELL_OUTSET outside it, so a list moved in by the full
	-- padding puts its RIM that far inside the body, and the two windows of
	-- this shape wore a wider margin than everything else in the interface.
	local inner = pad + ((entry and entry.wells == false)
		and W.WELL_OUTSET or W.WELL_PAD)
	-- PER PANE WHERE IT HAS TO BE. A number reserves the room above every pane
	-- in the body; a table names the one pane it belongs to. The trade skill
	-- window is why: its All control and its progress bars sit over the LIST,
	-- and the detail pane beside it must not move down to match.
	local leads = entry and entry.lead
	if type(leads) ~= "table" then leads = nil end
	local lead = (type(entry and entry.lead) == "number" and entry.lead) or 0
	-- ...AND ONLY IF THERE IS ANYTHING IN IT. The gossip window's row is one
	-- reputation bar and most of the people you talk to do not have one, so a
	-- window that always reserved the row wore an empty band on every NPC in
	-- the game bar a handful.
	if entry and entry.row and RowUp(frame, entry.row) then
		lead = lead + TOOL_ROW + W.PANEL_GAP
	end
	-- HOW FAR UP THE BODY STOPS, wanted before anything is moved: a pane that
	-- fills the window has its foot lifted clear of the strip, and that is part
	-- of placing it rather than something done to it afterwards.
	local strip = FootStrip(entry)

	-- WHAT THE STRIP TAKES: its own height and the body's padding over it.
	-- Nought where the window has no strip.
	local ins = entry and entry.insets or {}
	local room = strip > 0 and (pad + strip) or 0

	-- HOW FAR A PAGE'S FOOT COMES UP off the WINDOW's own edge to sit on the
	-- body's floor. Not the same number as the room: the glass does not end
	-- where the window does - the postbox's reaches 48 BELOW it to carry the
	-- tabs - and this one is measured from the window while the room is
	-- measured from the glass.
	local lift = strip > 0 and ((ins[4] or 0) + room) or 0

	local want = headH + inner + lead
	-- MEASURED FIRST AND MOVED AFTER, in two passes, because a window can want
	-- ONE answer for all of its content rather than a per-pane one. The trade
	-- window is a dozen pieces all hung off the frame at their own offsets -
	-- names at the top, two columns of slots, two purses - and shifting each by
	-- what IT is short of squeezes the layout together: the names travel eighty
	-- units and the slots eight. `together` moves the lot by the deepest.
	local most, wide, tail = 0, 0, 0
	local shifts = {}
	for _, name in ipairs(entry and entry.body or {}) do
		local pane = Part(name)
		if pane and pane.ClearAllPoints then
			local top, left, right = MeasureTop(frame, pane)
			top = (entry and entry.contentTop) or top
			local mine = want + ((leads and leads[name]) or 0)
			local down = top and math.max(0, mine - top) or 0
			local over = left and math.max(0, inner - left) or 0
			local back = right and math.max(0, inner - right) or over
			-- A WINDOW WHOSE CONTENT IS ALREADY INSIDE THE CLIENT'S OWN
			-- RECESSES does not want moving across. See `keepWidth` on the
			-- character sheet's entry: shifting one of those moves the content
			-- out of the recess drawn for it, and growing the window to pay for
			-- the shift makes it too wide for what is in it.
			if entry and entry.keepWidth then over, back = 0, 0 end
			if down > most then most = down end
			if over > wide then wide = over end
			if back > tail then tail = back end
			shifts[#shifts + 1] = { pane, down, over }
		end
	end

	for _, shift in ipairs(shifts) do
		local pane, down, over = shift[1], shift[2], shift[3]
		if entry and entry.together then down, over = most, wide end
		-- MOVED BY OFFSETTING THE ANCHORS IT ALREADY HAS, rather than by being
		-- re-anchored to the window. A pane fills the frame and a rewrite is
		-- harmless; the vendor has no pane and is moved by its first item, which
		-- the other nine hang off - and rewriting THAT to the window's corners
		-- would stretch one row across the window.
		local pts = pane.__aetherPts
		if not pts then
			pts = {}
			for i = 1, (pane.GetNumPoints and pane:GetNumPoints() or 0) do
				pts[i] = { pane:GetPoint(i) }
			end
			pane.__aetherPts = pts
		end
		-- A PANE THAT FILLS THE WINDOW IS MOVED BY ITS TOP CORNER ONLY. Its
		-- bottom stays on the window's bottom, so what the client hangs off the
		-- FOOT of the page stays at the foot of the page instead of travelling
		-- down twice and out through the recess.
		--
		-- ...EXCEPT THAT THE FOOT OF THE PAGE IS NOT THE FOOT OF THE WINDOW when
		-- there is a strip down there. Send Mail hangs its money field, its two
		-- radio buttons and your purse off the bottom of its pane, and with Send
		-- and Cancel moved into the strip the rest of that block was left sitting
		-- on top of them. So the pane's bottom comes UP by the strip and the body
		-- padding, which makes its box the BODY's box rather than the window's.
		--
		-- Only where there IS a strip: a window without one has its foot in the
		-- right place already, and the character sheet's weapon row is hung off
		-- exactly this edge.
		local corner = Fills(frame, pts)
		if #pts > 0 then
			pane:ClearAllPoints()
			for _, pt in ipairs(pts) do
				if corner and pt[1] ~= "TOPLEFT" then
					pane:SetPoint(pt[1], pt[2], pt[3], pt[4] or 0,
						(pt[5] or 0) + lift)
				else
					-- SIDEWAYS ONLY WHERE SIDEWAYS MEANS INWARD. `over` moves content in
					-- from the LEFT edge, so adding it to a point pinned to the RIGHT one
					-- pushes that piece OUTWARD instead - the letter's spam button went
					-- fourteen units past the glass and took the sender's box, which is
					-- stretched between it and the label, with it.
					local sideways = pt[3] and pt[3]:find("RIGHT") and 0 or over
					pane:SetPoint(pt[1], pt[2], pt[3],
						(pt[4] or 0) + sideways, (pt[5] or 0) - down)
				end
			end
		end
	end

	-- AND THE WINDOW GROWS TO TAKE IT. Down by the DEEPEST of the panes -
	-- growing per tab would have the frame jump every time you changed one, so
	-- the tab needing most room sets the height and the rest have air under
	-- them. Across by what EACH SIDE is short, added together: moving the
	-- content in from the left puts it that much closer to the right, and the
	-- two edges do not have to be short by the same amount. Doubling the left
	-- was an assumption that the client centred its content, and the vendor's
	-- rows are not centred in its window.
	-- ...AND BY WHAT THE STRIP TAKES AT THE OTHER END.
	--
	-- The client laid a page's insides out for a window with no strip in it, so
	-- everything it hangs off the page's foot - Send Mail's attachment row, its
	-- money field, your purse - sits where the strip now is. Growing by the
	-- strip's own height and the padding over it moves the window's foot down
	-- past the lot of them, which is the same answer as shortening the page
	-- reached without touching a number the client owns.
	-- RECORDED ONLY WHERE IT WAS APPLIED. The note of how much this window has
	-- grown is what the NEXT pass measures against, so writing it down after a
	-- growth that did not happen makes every later pass believe in room the
	-- window has not got.
	local taller = most + room
	local applied = frame.__aetherBodyShift or 0
	-- NOT THE SAME TEST AS THE WIDTH BELOW, deliberately. A window's HEIGHT is
	-- changed from outside on purpose - matchHeight has the letter reach the
	-- postbox's height every time either is laid out - so "taller than we left
	-- it" is a normal state here and not evidence that our growth is gone.
	if frame.SetHeight and frame.GetHeight then
		if taller ~= applied then
			frame:SetHeight((frame:GetHeight() or 0) + (taller - applied))
		end
		frame.__aetherBodyShift = taller
	end

	-- AND A WINDOW TOLD TO MATCH ANOTHER TAKES THE TALLER OF THE TWO.
	--
	-- Standing beside something is not a reason to be too short for your own
	-- insides: skipping the growth outright left the letter with no room made
	-- for its strip at all, and its attachment row sat under Delete. So it
	-- grows for what it needs first, and then reaches its twin's height if that
	-- is the greater - which is the case that made the pair look mismatched.
	local twin2 = entry and entry.matchHeight and _G[entry.matchHeight]
	if twin2 and twin2.GetHeight and frame.SetHeight then
		local reach = twin2:GetHeight()
		if reach and reach > (frame:GetHeight() or 0) then
			frame:SetHeight(reach)
		end
	end

	local grow = (entry and entry.keepWidth) and 0 or (wide + tail)
	local wasWide = frame.__aetherBodyGrow or 0

	-- IS THE GROWTH STILL THERE? Every other window in this list is whatever
	-- size we last left it, so "how much have we added" and "how much is
	-- present" are the same question and one number answered both.
	--
	-- THE CHARACTER SHEET ON MISTS IS NOT. CharacterFrameMixin:UpdateSize sets
	-- the window's width OUTRIGHT from the tab you are on - 338 for the doll,
	-- 540 with the stat panel out, 400 for reputation - and it runs on every
	-- tab click, every expand and every collapse. So the width we added to pay
	-- for the body padding is discarded, while our note of having added it
	-- survives; the next pass compares what it wants against that note, finds
	-- them equal, and adds nothing. The window sits at the client's own width
	-- with our padding still expected inside it and the content back out
	-- through the rim it had just been moved in from.
	--
	-- So the note records the WIDTH WE LEFT IT AT as well as the amount. A
	-- window that is no longer that width was resized by somebody else, and
	-- whatever we added went with it.
	if frame.__aetherBodyWidth and frame.GetWidth
		and math.abs((frame:GetWidth() or 0) - frame.__aetherBodyWidth) > 0.5 then
		wasWide = 0
	end

	if grow ~= wasWide and frame.SetWidth and frame.GetWidth then
		frame:SetWidth((frame:GetWidth() or 0) + (grow - wasWide))
	end
	frame.__aetherBodyInset = wide
	frame.__aetherBodyGrow = grow
	if frame.GetWidth then frame.__aetherBodyWidth = frame:GetWidth() end

	-- A WINDOW THAT LAYS ITSELF OUT gets told the padding instead of having
	-- its children moved. The game menu is a VerticalLayoutFrame: its buttons
	-- are placed by the client from layoutIndex and re-placed on every show, so
	-- moving one is undone before you see it. LayoutFrame reads topPadding and
	-- bottomPadding off the frame, which is exactly the question being asked.
	if entry and entry.layout and frame.Layout then
		frame.topPadding = headH + inner
		frame.bottomPadding = inner + ((entry.footer or 0) > 0
			and (entry.footer + pad) or 0)
		frame.leftPadding = inner
		frame.rightPadding = inner
		pcall(frame.Layout, frame)
	end

	-- ONE RECESS DEEP. A window whose content is ALREADY in wells does not get
	-- another one round the outside: the trainer and the trade skills each
	-- carry two client scroll frames, and every one of those is in a recess of
	-- its own now. A body well behind them is a second rim round the first and
	-- a second helping of the same black - the recess reads as twice as deep
	-- wherever the two overlap, which is everywhere.
	-- THE STRIP FIRST, and whether or not the body gets a recess: the trade
	-- skills and the trainer are in wells already and still have a footer.
	PN.LayoutFooter(frame, entry)

	-- A SCROLL FRAME STOPS WHERE THE RECESS DOES.
	--
	-- ONE CLIPS AT ITS OWN BOUNDS and nowhere else, so moving it down the
	-- window without shortening it moves where the clipping happens too: the
	-- quest giver's text carried on past the foot of the well, over the
	-- hairline and under Accept and Decline. The trade skill's two lists did
	-- the same thing forty units past their own rims.
	--
	-- SHORTENED, NEVER STRETCHED. A pane already above the floor is one in a
	-- window that stacks its lists rather than setting them side by side, and
	-- pulling that one down would drag it through the list beneath it.
	--
	-- SCROLL FRAMES, AND PAGES PINNED BY ONE CORNER. A page pinned by BOTH is
	-- held at the foot already and must not be touched: the character sheet's
	-- is a page and a footer at once, with the weapon row hung off its bottom
	-- edge, and shortening that one cuts the row off. A page pinned by one
	-- corner has nothing holding its foot, so shortening it IS what holds it -
	-- which is what keeps Send Mail's money block out of the strip.
	-- SCROLL FRAMES ONLY, and this is a rule that had to be learned twice.
	--
	-- A PAGE'S DECLARED HEIGHT IS PART OF THE CLIENT'S ARITHMETIC. Send Mail's
	-- pane is 512 tall inside a window 424 tall, deliberately: the client
	-- anchors the attachment row a fixed distance ABOVE the pane's bottom and
	-- places it from Lua on every update. Shortening the pane to fit the body
	-- dragged that row eighty-eight units up into the middle of the letter.
	--
	-- Nothing needs shortening there anyway: growing the window at both ends
	-- moves the window's foot down past the block, which is the same answer
	-- reached without touching a number the client owns.
	local base = (host.GetBottom and host:GetBottom())
	if base then
		local floorY = base + strip + inner
		local fills = entry and entry.fill
		for _, shift in ipairs(shifts) do
			local pane = shift[1]
			local top = pane.GetTop and pane:GetTop()
			local low = pane.GetBottom and pane:GetBottom()
			local who = pane.GetName and pane:GetName()
			-- ...AND STRETCHED, WHERE THE ENTRY ASKS FOR IT.
			--
			-- The rule above is right for a page the client sized for its own
			-- window and wrong for a box it sized for a window SHORTER than
			-- ours. The group finder's list is a fixed 324 by 282 in a frame
			-- 512 tall; ours is half as tall again, because the band, the tool
			-- row and the footer strip all cost height and the window grows to
			-- take them. Left at 282 it sits in a recess with a hand's width of
			-- empty glass under it and shows fewer results than there is room
			-- for.
			--
			-- NAMED, never guessed. Send Mail's pane is 512 tall inside a
			-- window of 424 deliberately - the client hangs the attachment row
			-- a fixed distance above its BOTTOM - so a rule that stretched
			-- everything to the floor would drag that row down through the
			-- letter. Only a window that says so gets it.
			if fills and who and fills[who] and top and pane.SetHeight then
				pane:SetHeight(math.max(1, top - floorY))
				-- A MODERN SCROLL BOX RE-READS ITS HEIGHT WHEN IT NEXT LAYS
				-- OUT, and asking is cheaper than waiting for whatever happens
				-- to make it. Pcalled because only some of these are boxes; the
				-- rest are plain containers with nothing to do.
				if pane.FullUpdate then pcall(pane.FullUpdate, pane) end
			elseif pane.GetScrollChild and top and low and low < floorY
				and pane.SetHeight then
				pane:SetHeight(math.max(1, top - floorY))
			end
		end
	end

	if entry and entry.wells == false then
		if frame.__aetherBody then frame.__aetherBody:Hide() end
		return
	end

	local well = frame.__aetherBody
	if not well or well.__aetherHost ~= host then
		well = W.ContentWell(host)
		well.__aetherHost = host
		frame.__aetherBody = well
	end

	-- BEHIND THE CLIENT'S OWN FRAMES. The panes are children of the WINDOW
	-- and the glass is another child of it, so the panes draw over the glass
	-- whatever level the well takes - which is what a recess wants anyway.
	if well.SetFrameLevel and host.GetFrameLevel then
		well:SetFrameLevel(math.max(0, (host:GetFrameLevel() or 1)))
	end

	-- IT STOPS AT THE RAILS, on the edges that have one. A recess that runs
	-- under the tab column reads as the tabs floating on the content rather
	-- than standing beside it.
	-- ONE POINT PER EDGE, and each edge stops at whatever is beside it. A
	-- recess running under the tab column or behind the tab row reads as the
	-- tabs floating on the content rather than standing next to it.
	local side = RailOn(frame, "RIGHT")
	local foot = RailOn(frame, "BOTTOM")
	well:ClearAllPoints()
	well:SetPoint("TOPLEFT", host, "TOPLEFT", pad, -(headH + pad))
	if side then
		well:SetPoint("RIGHT", side, "LEFT", -pad, 0)
	else
		well:SetPoint("RIGHT", host, "RIGHT", -pad, 0)
	end
	-- A FOOTER, where the window keeps one. 15a: actions live in a strip above
	-- the bottom edge, never scattered in the body - and some of the client's
	-- windows already have one whether we asked or not. The vendor's repair
	-- buttons and your purse are anchored to its bottom edge, so a body that
	-- reached the tab rail ran its recess straight through both of them.
	if foot then
		well:SetPoint("BOTTOM", foot, "TOP", 0, pad + strip)
	else
		well:SetPoint("BOTTOM", host, "BOTTOM", 0, pad + strip)
	end
	well:Show()
end

--- The footer strip: its hairline, its page turn and what the window does.
--
--  Its own pass, because the strip changes while the window stays open and
--  the body does not: the quest giver swaps one pair of buttons for another
--  every time you turn a page of a quest, and re-laying the whole window for
--  that would move content that has not moved.
function PN.LayoutFooter(frame, entry)
	local host = frame and frame.__aetherPanel
	if not host then return end
	local foot = RailOn(frame, "BOTTOM")
	local strip = FootStrip(entry)
	FootRule(frame, host, foot, strip)
	if strip <= 0 then return end

	-- THE SAME ROW THE TOOL ROW IS, at the other end of the window: a purse
	-- pinned to one side, and what the window DOES centred between. 15a is
	-- specific that actions live here and never in the body, and 15c that a
	-- page turn is one of them - the vendor's Prev, Page 1 and Next sat inside
	-- the recess, over the last row of what you were being sold.
	local anchor = foot or host
	local edge = foot and "TOP" or "BOTTOM"
	local acts = entry and entry.actions

	-- ONE ROW OR TWO, each centred in its own equal share of the strip - and
	-- the strip is a row taller for the second, so the share does not shrink.
	-- The postbox reads as a page turn with Open All under it, both with the
	-- air round them a single row gets, rather than three on one line or two
	-- pressed against the rule at either end.
	--
	-- COUNTED FROM WHAT IS UP, not from what the entry declares. The strip's
	-- HEIGHT is the declared count, so the window is the same size whichever
	-- pane you are on - but the postbox's second row belongs to the inbox, and
	-- on Send Mail there is nothing in it. Laid out as two rows regardless,
	-- Send and Cancel took the upper half and sat with an empty row's worth of
	-- glass under them.
	local rows = (acts and RowLive(frame, acts.under)) and 2 or 1
	local slice = strip / rows
	ChromeRow(frame, acts, anchor, edge, strip - slice / 2, FOOT_GAP)
	if rows > 1 then
		ChromeRow(frame, { mid = acts.under }, anchor, edge, slice / 2, FOOT_GAP)
	end
end

--- Redraw a window's footer for whatever pane it is showing now.
function PN.RefreshFooter(name)
	local frame, entry = _G[name], PN.ENTRY and PN.ENTRY[name]
	if frame and entry then PN.LayoutFooter(frame, entry) end
end
--- `btn` is for a window whose X has no name and no parentKey at all.
--
--  The group finder's is an anonymous <Button inherits="UIPanelCloseButton">
--  and nothing can ask for it by name, so its dresser finds it by shape and
--  hands it over rather than a second copy of these six lines being written.
local function DressClose(frame, store, btn)
	local close = btn or CloseButton(frame)
	if not close then return end

	-- INTO THE CORNER OF THE GLASS, always, at the shared inset - where the
	-- window put its own well inside its art. The spellbook's and the talent
	-- frame's both sit 44 in from the right and 25 down, the middle of a stone
	-- rim that is no longer there, and read as a stray cross in the page.
	--
	-- It used to be per-window, behind a `closeCorner` flag, which is how the
	-- vendor's and the postbox's ended up at a different inset from the
	-- spellbook's. One inset, and the flag is gone.
	local name = frame.GetName and frame:GetName()
	local entry = name and PN.ENTRY and PN.ENTRY[name]
	W.PlaceClose(close, frame, entry and entry.insets)

	if close.__aetherClose then return end

	-- State textures first, then the regions: ClearButton wants to see the
	-- client's own paths, and Strip empties them. Reskin.ClearButton copes with
	-- either order now, but reading it in this one costs nothing.
	Reskin.ClearButton(close)
	Reskin.Strip(close, store)

	-- ON THE CLIENT'S OWN BUTTON. It is still the thing that closes the
	-- window; nothing here is rebuilt or rewired, only dressed.
	W.CloseButton(close, { attach = close })
end
PN.DressClose = DressClose

--- Art off, glass behind, title re-roled. Safe to call repeatedly.
local function Dress(frame)
	if not frame or not frame.GetRegions then return end

	local store = frame.__aetherArt
	if not store then
		store = {}
		frame.__aetherArt = store
	end

	local name = frame.GetName and frame:GetName()
	local entry = name and PN.ENTRY and PN.ENTRY[name]

	-- `keep` before the strip, not after: the sweep records what it found the
	-- first time and clears that same list on every show afterwards, so a
	-- region spared later has already gone.
	Reskin.Strip(frame, store, entry and entry.keep)

	Reskin.Panel(frame, { corner = W.PANEL_CORNER,
		insets = entry and entry.insets })

	-- Drawn at the profile's scale, like everything else of ours - but never
	-- below the floor, because what is inside these is the client's own art at
	-- a fixed size and it stops being readable before it stops being small.
	if frame.SetScale then frame:SetScale(PanelScale()) end

	-- AND THE GLASS RE-SNAPPED AFTER IT. A corner is snapped to whole physical
	-- pixels, which depends on the frame's effective scale - and SetScale fires
	-- no size change, so nothing else would ever ask the surface to look again.
	-- Change the scale and every curve in the window goes soft until something
	-- happens to resize it.
	if frame.__aetherPanel and frame.__aetherPanel._Relayout then
		frame.__aetherPanel:_Relayout()
	end

	-- The window's own title, where it has one under a name we can find. Three
	-- places, because the client uses three: an older frame names it globally,
	-- a reworked one carries it as a field, and anything built on the shared
	-- dialog template keeps it inside a Header child alongside the stone plate.
	local header = Reskin.Element(frame, "Header")
	local moved = nil
	local title = (entry and PN.Part(entry.title)) or nil
	if title then
		-- Named here because the client did not name it after its frame, and
		-- placed by the client for art we have just taken off - so it moves.
		moved = true
	else
		title = Reskin.Element(frame, "TitleText") or Reskin.Element(frame, "Title")
	end
	if not title and header then
		title = header.Text or Reskin.Element(header, "Text")
		moved = title and true or nil
	end

	-- WHERE IT GOES is the header band's business now, not this line's - see
	-- DressHeader. It used to be moved only for a window whose title we had to
	-- name ourselves, and left where the client put it otherwise, which is why
	-- no two of them lined up.
	if title and title.SetText then
		-- ONE TITLE SIZE, on every panel in the interface, and 16 is the
		-- ceiling. This branched: a window on the modern template kept the
		-- CLIENT's size, because its title band is twenty tall and ours at
		-- nineteen filled it corner to corner; an old one took ours plus the
		-- point every client string here gets, for nineteen.
		--
		-- At 16 neither problem exists, and a title that is one size on the
		-- gossip window and another on the spellbook is the thing the panel
		-- package is for. The bump is for text sitting in the client's own
		-- rows and columns; a title has the width of the window to itself.
		frame.__aetherTitle = title
	end

	-- THE BAND, on every window: a hairline along its foot and the title
	-- centred in it. The subtitle too, where the window has one. ONE PLACE,
	-- because this was being done three times over - here, in DressCharacter
	-- and again wherever a window's own dresser felt like moving its title.
	frame.__aetherTitle = title
	PN.RefreshHeader(frame:GetName())

	DressClose(frame, store)

	-- THE BODY, on every window: one recess, the same padding, and the
	-- client's own content moved down into it where it would otherwise sit
	-- across the header band.
	PN.LayoutBody(frame, entry)
	WatchPanes(frame, entry)

	-- The insides, where this window has a policy for them. Reached through PN
	-- rather than an upvalue: the interiors are defined below this, and a local
	-- declared later is not in scope here.
	local interior = name and PN.INTERIORS and PN.INTERIORS[name]
	if interior then
		-- PCALLED, AND THE FAILURE KEPT. These reach into somebody else's
		-- frames by name, and the names change between game versions - so a
		-- dresser CAN throw, and until now a throw took the rest of the
		-- window with it: the shell had already run, so the window came up
		-- in our glass with every one of its insides untouched.
		--
		-- Which is indistinguishable, on screen, from a dresser that never
		-- ran at all or was never written. Three separate reports this
		-- session looked like the fix not being deployed.
		PN.failures = PN.failures or {}
		local ok, err = pcall(interior, frame, store)
		if ok then
			PN.failures[name] = nil
		else
			PN.failures[name] = tostring(err)
			A.lastFailure = "panels " .. name .. ": " .. tostring(err)
			A:Debug("panel interior failed:", name, err)
		end
	end

	return true
end

PN.Dress = Dress

-- ---------------------------------------------------------------------------
-- the character sheet
-- ---------------------------------------------------------------------------
--
-- The first interior, and the one that meets nearly every kind of widget the
-- others use: item slots, tabs, stat rows, resistance chips, two scrolling
-- lists, check boxes and three status bars. Names verified against ElvUI's
-- Classic skin, which is maintained against this client - the character frame's
-- own source is not in the Blizzard dump.

-- THE TAB STRIP. One language for every tabbed surface in this interface, and
-- it lives in W.Tab / W.TabRail - bare text on a hairline, with a mark under
-- the one you are standing on. What is left here is the LAYOUT: how a row of
-- somebody else's buttons is measured into a rail that must not grow.
--
-- Blizzard's tabs are sized for art with wide transparent margins and are
-- meant to overlap, the art hiding the join. With the art off there is no
-- join to hide, so each one is measured to its own word and they sit flush.
local TAB_H = W.TAB_RAIL_H


-- Each tab HUGS ITS OWN LABEL now. It used to be one width for all of them,
-- on the argument that a row of pills at five different widths reads as
-- sprung - which was true of pills and is not true of words. With no
-- container to be uneven, the even row was only wasting the rail.
local TAB_PADS = W.TAB_PADS

-- And after the padding, a point or two off the lettering. Still not the word:
-- a shade smaller reads fine, three dots in place of three letters does not.
local TAB_STYLE = 'pnTab'
local TAB_FONT_STEPS = 2

-- Last of all, and only when nothing else has bought the room: the words
-- themselves, cut with an ellipsis and the whole of it moved to a tooltip.
local TAB_MIN_LABEL = 34

local function TabLabel(tab)
	return Reskin.Element(tab, "Text") or (tab.GetFontString and tab:GetFontString())
end
PN.TabLabel = TabLabel

--- The nth tab of a window, under whatever name that window gives its tabs.
--
--  Most of them are $parentTab1..n. The spellbook is not, and asking for
--  SpellBookFrameTab1 finds nothing at all - which is a tab strip that quietly
--  never gets laid out rather than an error anybody would notice.
local function TabAt(name, i)
	local entry = PN.ENTRY and PN.ENTRY[name]
	return _G[(entry and entry.tabs or (name .. "Tab")) .. i]
end
PN.TabAt = TabAt

--- Selected or not, in our own weight.
--
--  The client marks the open tab by DISABLING it - a disabled tab is the one
--  you are looking at, which reads backwards until you know it.
local function StyleTabState(tab)
	-- WHICH TAB IS UP IS THE FRAME'S ANSWER, NOT THE BUTTON'S.
	--
	-- The client marks the selected tab by DISABLING it, so "disabled" reads
	-- as "selected" - and that was the test here. But it disables a tab that is
	-- not AVAILABLE by exactly the same means, and the two are indistinguishable
	-- from the button alone.
	--
	-- Joe found it on the inspect window: clicking Guild on a character with no
	-- guild left the mark under Guild AND under the tab that was actually up,
	-- because the client had disabled the unavailable one and never changed
	-- which pane was showing.
	--
	-- PanelTemplates_SetTab records the answer as `selectedTab` on the WINDOW,
	-- and PanelTemplates_GetSelectedTab is the client reading its own note. So
	-- the note is what we ask, and the enabled test is kept only for a window
	-- that has no note to read.
	local host = tab.GetParent and tab:GetParent()
	for _ = 1, 2 do
		if host and host.selectedTab then break end
		host = host and host.GetParent and host:GetParent() or nil
	end

	local selected
	if host and host.selectedTab and tab.GetID then
		selected = tab:GetID() == host.selectedTab
	else
		selected = not ((tab.IsEnabled == nil) or tab:IsEnabled())
	end

	-- BRIGHT TEXT AND A MARK, never a fill. See W.TabState: a filled tab is
	-- indistinguishable from Create, Send or Accept, and those do things
	-- rather than change what you are looking at.
	W.TabState(tab, selected, tab.IsMouseOver and tab:IsMouseOver())

	local text = TabLabel(tab)
	if not text then return end

	-- AND PUT THE LABEL BACK WHERE WE PUT IT. Selecting a tab moves its text:
	-- the client nudges it up into the raised part of its own stone art, which
	-- is right for that art and wrong for a flat rail. It does this on every
	-- selection, so it has to be answered on every selection.
	if text.ClearAllPoints then
		text:ClearAllPoints()
		text:SetPoint("CENTER", tab, "CENTER", 0, 0)
	end
	if text.SetJustifyH then text:SetJustifyH("CENTER") end

	-- ...AND TELL THE CLIENT WHERE WE PUT IT, rather than putting it back
	-- afterwards for ever.
	--
	-- PanelTemplates_SelectTab and _DeselectTab each re-anchor the label
	-- themselves - CENTER at `selectedTextY or -3` when a tab goes down, at
	-- `deselectedTextY or 2` when it comes up - because Blizzard's selected tab
	-- art physically sits lower and the words move with it. Ours is a flat
	-- rail, so both numbers are wrong for us.
	--
	-- Answering it in this function only covers the selections WE hear about.
	-- Paging a tab re-runs the client's own update, which re-selects the tab
	-- without anything of ours running - so the label dropped three pixels and
	-- stayed there until the next time the player changed tabs, which is
	-- exactly what Joe saw and on every multi-page tab.
	--
	-- Those four offsets are read off the tab, so they are ours to set. Nought
	-- on both states makes the client's own re-anchor land where we want it and
	-- there is nothing left to fight.
	tab.selectedTextX, tab.selectedTextY = 0, 0
	tab.deselectedTextX, tab.deselectedTextY = 0, 0
end
PN.StyleTabState = StyleTabState

--- How much room the tab row actually has: the visible window, and no more.
--
--  THE RAIL IS SET BY THE FRAME, never the reverse. This used to grow the
--  window by up to 48 units when a row would not fit, which is a panel that
--  changes shape because of how many tabs it happens to have.
local function StripWidth(frame, name)
	local w = (frame.GetWidth and frame:GetWidth()) or 0
	local entry = PN.ENTRY and PN.ENTRY[name]
	local ins = entry and entry.insets
	if ins then w = w + (ins[3] or 0) - (ins[1] or 0) end
	return w
end

--- Measure every tab's label, at a given font size.
--
--  Always from a reset: a label told not to wrap reports its TRUNCATED width,
--  so measuring one still clamped from an earlier pass measures our own squeeze
--  and the row creeps narrower every time it is laid out.
local function MeasureTabs(tabs, size)
	local widths, textSum = {}, 0

	for i, tab in ipairs(tabs) do
		local text = TabLabel(tab)
		if text then
			if text.SetWordWrap then text:SetWordWrap(true) end
			if text.SetWidth then text:SetWidth(0) end
			text._aetherSize = size
			W.Restyle(text, TAB_STYLE)
		end

		local w = (text and text.GetStringWidth and text:GetStringWidth()) or 60
		widths[i] = w
		textSum = textSum + w
	end

	return widths, textSum
end

--- The row, and the rail it sits on.
--
--  THE RAIL NEVER GROWS. What gives, in order, is the padding either side of
--  each word, then a point or two off the lettering, and only then the words
--  themselves - cut with an ellipsis, with the whole of it on a tooltip. That
--  order is the handoff's and it is a ranking of how much each costs the
--  player: white space costs nothing, a smaller word costs a little, half a
--  word costs a lot.
local function LayoutTabs(frame, store)
	local name = frame.GetName and frame:GetName()
	if not name then return end

	-- ONLY THE ONES YOU CAN SEE.
	--
	-- The character sheet's second tab is the pet, and a character without a
	-- pet has it hidden. Laying out every tab the client defined gave that
	-- hidden one a slot of its own - so the row had a hole in it between
	-- Character and Reputation, exactly the width of a tab, with nothing in it.
	local tabs, hidden = {}, {}
	local n = 1
	while TabAt(name, n) do
		local tab = TabAt(name, n)
		if not tab.IsShown or tab:IsShown() then
			tabs[#tabs + 1] = tab
		else
			hidden[#hidden + 1] = tab
		end
		n = n + 1
	end

	-- BEFORE the early return, not after it. The spellbook opens with all three
	-- of its tabs hidden and shows the ones that apply from its own update, so
	-- the first dress sees an empty row - and a row that gives up before it has
	-- asked to be told when a tab appears never lays itself out at all.
	for _, tab in ipairs(hidden) do
		if tab.HookScript and not tab.__aetherShowHook then
			tab.__aetherShowHook = true
			tab:HookScript("OnShow", function()
				if PN.enabled and frame.__aetherArt then
					LayoutTabs(frame, frame.__aetherArt)
				end
			end)
		end
	end

	if #tabs == 0 then return end

	local entry = PN.ENTRY and PN.ENTRY[name]
	local ins = entry and entry.insets or {}
	local left, right = ins[1] or 0, ins[3] or 0

	-- THE RAIL: a hairline across the foot of the window, on the edge that
	-- faces the content the tabs switch. Every panel here keeps WoW's
	-- bottom-tab convention, so the line and the marks are on its top.
	local rail = W.TabRail(frame, "BOTTOM")
	rail:ClearAllPoints()
	rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left, ins[4] or 0)
	-- AND ITS RIGHT EDGE STOPS AT THE COLUMN, where there is one. The two
	-- hairlines are the same line at ninety degrees to each other, and running
	-- one through the other draws a cross in the corner of the window - which
	-- is a join nothing is joining.
	local side = frame.__aetherRails and frame.__aetherRails.RIGHT
	if side and side:IsShown() then
		rail:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", 0, 0)
	else
		rail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, ins[4] or 0)
	end
	rail:SetHeight(TAB_H)
	rail:Show()

	local room = StripWidth(frame, name)
	local base = (A.Media.style[TAB_STYLE] or {})[2]
	base = base and (base + FONT_BUMP)

	--- What the row costs at a given padding and size, and the widths with it.
	local function fit(pad, size)
		local widths = MeasureTabs(tabs, size)
		local total = 0
		for _, w in ipairs(widths) do total = total + w + pad * 2 end
		return total, widths
	end

	local pad, size, widths, cap
	for step = 0, TAB_FONT_STEPS do
		local try = base and (base - step) or nil
		for _, p in ipairs(TAB_PADS) do
			local total, ws = fit(p, try)
			if room <= 0 or total <= room then
				pad, size, widths = p, try, ws
				break
			end
		end
		if pad then break end
		if not base then break end
	end

	-- NOTHING FITTED, so the words give. Every tab gets the same share of what
	-- is left after the padding, floored so a cut label is still a word rather
	-- than an ellipsis on its own - below that the row overhangs, which is the
	-- honest answer and better than a rail of dots.
	if not pad then
		pad = TAB_PADS[#TAB_PADS]
		size = base and (base - TAB_FONT_STEPS) or nil
		widths = MeasureTabs(tabs, size)
		cap = math.max(TAB_MIN_LABEL,
			math.floor(room / #tabs) - pad * 2)
	end

	-- LEFT, not centred. A row of tabs is a list of places you can go, and a
	-- list starts at the left edge of the thing it belongs to. Centred, the row
	-- moved every time a tab appeared or went away: a hunter's pet tab arriving
	-- slid Character, Skills and Reputation sideways under the cursor, which is
	-- a window that will not sit still.
	local last

	for i, tab in ipairs(tabs) do
		Reskin.Tab(tab, store, TAB_STYLE, { rail = rail })

		local label = TabLabel(tab)
		local w = (widths[i] or 60)
		if cap and w > cap then w = cap end

		if tab.SetSize then tab:SetSize(w + pad * 2, TAB_H) end

		-- AND ITS CLICKABLE AREA BACK. The spellbook's tabs are 128x64 in the
		-- client's art with a hit rect inset 13 from the top and 15 from the
		-- bottom, to keep the clicks off the transparent margin. Resize that tab
		-- and the two insets meet in the middle: the tab is drawn, reads
		-- correctly, highlights on hover - and cannot be clicked. The client's
		-- own values are recorded so switching off puts them back.
		if tab.SetHitRectInsets then
			if tab.__aetherHit == nil and tab.GetHitRectInsets then
				tab.__aetherHit = { tab:GetHitRectInsets() }
			end
			tab:SetHitRectInsets(0, 0, 0, 0)
		end

		if label then
			-- CUT ONLY AS A LAST RESORT, and never silently: the whole word
			-- goes on a tooltip, because three dots in place of three letters
			-- tells the player less than the word did.
			if cap then
				if label.SetWordWrap then label:SetWordWrap(false) end
				if label.SetWidth then label:SetWidth(cap) end
				tab.__aetherCut = (widths[i] or 0) > cap and label:GetText() or nil
			else
				if label.SetWordWrap then label:SetWordWrap(true) end
				if label.SetWidth then label:SetWidth(0) end
				tab.__aetherCut = nil
			end

			-- Centred in the tab, not where Blizzard's art wanted it: its own
			-- offsets were written for a raised stone tab whose face sat above
			-- the middle, and with the stone gone the word reads high.
			if label.ClearAllPoints then
				label:ClearAllPoints()
				label:SetPoint("CENTER", tab, "CENTER", 0, 0)
			end

			-- Centred by JUSTIFICATION as well as by anchor. The client sets
			-- these labels to justify left for its own tab art, and a string
			-- that ever picks up a width - the client's own resize hands it one
			-- - then draws hard against the left of that width whatever its
			-- anchor says. Both, or it only looks centred until it does not.
			if label.SetJustifyH then label:SetJustifyH("CENTER") end
		end

		-- Where the client had it, before we move it. Off has to put it back.
		if tab.__aetherAnchor == nil and tab.GetPoint then
			local pt = { tab:GetPoint() }
			tab.__aetherAnchor = (pt[1] and pt) or false
			if tab.GetWidth then
				tab.__aetherSize = { tab:GetWidth(), tab:GetHeight() }
			end
		end

		-- ONE ANCHOR, OURS, in a shape we control. The client's anchor is not
		-- used at all: a tab anchored by its CENTRE takes an x meaning "where
		-- the middle goes", so an offset written for a left edge hangs half the
		-- tab off the side of the screen. It is still RECORDED, because
		-- switching the module off has to put it back where the client had it.
		tab:ClearAllPoints()
		if last then
			tab:SetPoint("BOTTOMLEFT", last, "BOTTOMRIGHT", 0, 0)
		else
			tab:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 0, 0)
		end
		last = tab

		StyleTabState(tab)

		-- The whole word, for a tab whose label had to be cut. Hooked once and
		-- reading __aetherCut, so a row that stops needing it stops showing it.
		if tab.HookScript and not tab.__aetherTabTip then
			tab.__aetherTabTip = true
			tab:HookScript("OnEnter", function(self)
				if not PN.enabled or not self.__aetherCut then return end
				if not _G.GameTooltip then return end
				_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
				_G.GameTooltip:SetText(self.__aetherCut)
				_G.GameTooltip:Show()
			end)
			tab:HookScript("OnLeave", function()
				if _G.GameTooltip then _G.GameTooltip:Hide() end
			end)
		end

		-- The selection only changes on a click, so that is where it is worth
		-- answering. Hooked once per tab.
		if tab.HookScript and not tab.__aetherTabHook then
			tab.__aetherTabHook = true
			tab:HookScript("OnClick", function()
				if not PN.enabled then return end
				local k = 1
				while TabAt(name, k) do
					StyleTabState(TabAt(name, k))
					k = k + 1
				end
			end)
		end
	end
end
PN.LayoutTabs = LayoutTabs

PN.LayoutTabs = LayoutTabs

--- Lay a window's tab row out again, for a client that has moved it.
--
--  THE GROUP FINDER MOVES ITS OWN TABS FROM EACH PANE'S OnShow, with a hard
--  SetPoint and the comment "Baby hack... the selected tab texture doesn't
--  blend well with the LFG texture, so move it down a hair when it's
--  selected". Two hairs, in fact: 45 up from the frame on one pane and 43 on
--  the other. Neither is where our rail is, so the row jumped off the rail
--  and sat above it the moment a tab was clicked.
--
--  Nothing calls PanelTemplates_TabResize on that path, so the hook below
--  never fires for it. This is the one that does.
function PN.RefreshTabs(name)
	local frame = _G[name]
	if not (frame and frame.__aetherArt and PN.enabled) then return end
	-- AGAIN, never for the first time. A window whose tabs nothing has
	-- dressed has no rail, and laying its row out from here would be this
	-- function deciding for the whole interface which windows have a tab
	-- rail - the postbox's row, which sits below its own bottom edge on the
	-- client's anchors, moved onto a rail it never had.
	local rail = frame.__aetherRails and frame.__aetherRails.BOTTOM
	if not (rail and rail:IsShown()) then return end
	LayoutTabs(frame, frame.__aetherArt)
end

--- Answer the client when it re-sizes or re-selects its own tabs.
--
--  PanelTemplates_TabResize sets a tab's width from its label and its side
--  caps, and the client calls it on show and on every tab click. A width we set
--  once at dress time survives until the player touches the window - which is
--  to say, it does not survive at all. Same for the selected state, which the
--  client rewrites through PanelTemplates_UpdateTabs.
local function InstallTabHooks()
	if PN.__tabHooks or not hooksecurefunc then return end
	PN.__tabHooks = true

	local function OwnedBy(frame)
		local name = frame and frame.GetName and frame:GetName()
		if not name or not PN.ENTRY[name] then return nil end
		return name
	end

	if _G.PanelTemplates_TabResize then
		hooksecurefunc("PanelTemplates_TabResize", function(tab)
			if not PN.enabled or PN.__relaying or not tab or not tab.GetParent then return end

			local parent = tab:GetParent()
			if not OwnedBy(parent) or not parent.__aetherArt then return end

			-- Re-entry guard, not an optimisation: laying the row out touches
			-- every tab in it, and the client may be part way through its own
			-- loop over the same tabs.
			PN.__relaying = true
			LayoutTabs(parent, parent.__aetherArt)
			PN.__relaying = false
		end)
	end

	if _G.PanelTemplates_UpdateTabs then
		hooksecurefunc("PanelTemplates_UpdateTabs", function(frame)
			if not PN.enabled then return end
			local name = OwnedBy(frame)
			if not name then return end

			local n = 1
			while TabAt(name, n) do
				StyleTabState(TabAt(name, n))
				n = n + 1
			end

			-- AND THE HEADER, because on a window with panes in it the tab is
			-- what decides whose name the band is carrying.
			PN.RefreshHeader(name)
		end)
	end
end
PN.InstallTabHooks = InstallTabHooks

-- ---------------------------------------------------------------------------
-- the interiors
-- ---------------------------------------------------------------------------
--
-- One dresser per window, in Modules/PanelInteriors.lua - this file was
-- seven names from Lua's 200-local ceiling. They register themselves into
-- PN.INTERIORS, which Dress reads by frame name; nothing here calls one
-- directly.


-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

--- Dress it again once the client has finished putting it up.
--
--  A WINDOW HAS NO RECT WHEN IT TELLS YOU IT HAS OPENED. ShowUIPanel clears a
--  panel's anchors and places it AFTER its OnShow has run, so everything this
--  file measures - where the client's content starts, how far in from the
--  glass it is - is being asked of a frame that is not anywhere yet, and comes
--  back nil. The window then sits there laid out for the answer it got at
--  login, which is the same nil.
--
--  The client is also still working on the window at that point: the title
--  goes back where its own template wants it and a button anchored to a
--  corner goes back to that corner, both after our pass has run.
--
--  So: once more on the next frame, when there is something to measure and the
--  client has finished. Once, not on a ticker - a window that is up is not
--  changing shape underneath us.

function PN.Settle(frame)
	if frame.__aetherSettling or not C_Timer or not C_Timer.After then return end
	if not (frame.IsShown and frame:IsShown()) then return end
	frame.__aetherTries = (frame.__aetherTries or 0) + 1
	if frame.__aetherTries > SETTLE_TRIES then return end
	frame.__aetherSettling = true
	C_Timer.After(0, function()
		frame.__aetherSettling = nil
		if not (PN.enabled and frame.IsShown and frame:IsShown()) then return end
		local ok, err = pcall(Dress, frame)
		if not ok then
			PN.failures = PN.failures or {}
			local name = frame.GetName and frame:GetName()
			if name then PN.failures[name] = "on settle: " .. tostring(err) end
		end
	end)
end

--- Skin whatever exists now. Called again whenever more of it might.
-- ---------------------------------------------------------------------------
-- the toolbox gutter
-- ---------------------------------------------------------------------------
--
-- The client docks its own windows against the left edge of the screen, and
-- the Toolbox's rail lives there too - so the character sheet opened on top of
-- the handle and the handle could not be reached without shutting the sheet.
--
-- NOT BY DETACHING THEM. Taking a window out of the panel system is a
-- supported thing to do - clear its `area` attribute and ShowUIPanel hands it
-- straight to Show() - but CheckProtectedFunctionsAllowed runs BEFORE that
-- bail-out, so every open and close in combat becomes a visible blocked-action
-- error unless every path is rerouted. It also forfeits whileDead, checkFit
-- and bottomClampOverride. That was researched and dropped; nothing here
-- revisits it.
--
-- WHAT MOVES THEM IS THE PANEL SYSTEM'S OWN NUMBER. A left-area window is
-- placed at `leftOffset + xoffset`, and xoffset is a per-frame attribute:
-- SetUIPanelAttribute stamps UIPanelLayout-defined on the frame, after which
-- GetUIPanelAttribute reads the FRAME and never the global UIPanelWindows
-- table again for it. So nothing of ours is written into a table the client
-- reads inside secure code, `area` is untouched, and every reason the detach
-- was dropped stays untouched with it.

-- Air between the rail and the window's edge. The rail is a handle you have to
-- be able to hit, and a window flush against it reads as one object.
local GUTTER_AIR = 8

-- The areas the panel system pins to the LEFT of the screen, which are the
-- only ones the rail can be under. A centred window deliberately ignores
-- xoffset - see UIParentPanelManager - so listing it here would do nothing.
local LEFT_AREAS = { left = true, doublewide = true }

--- How far in from the screen's left edge the Toolbox's rail reaches.
--
--  MEASURED, NOT DECLARED. The rail is drawn at the profile's scale and the
--  panel system's offsets are in UIParent's, so a constant here would be
--  right at one scale and wrong at every other. Nought when the Toolbox is
--  off or docked anywhere else: there is nothing to clear.
local function ToolboxGutter()
	local TB = A.GetModule and A:GetModule("toolbox")
	if not (TB and TB.enabled and TB.rail) then return 0 end
	if TB.Dock and TB:Dock() ~= "LEFT" then return 0 end

	local rail = TB.rail
	local wide = rail.GetWidth and rail:GetWidth()
	if not wide or wide <= 0 then return 0 end

	local mine = rail.GetEffectiveScale and rail:GetEffectiveScale() or 1
	local theirs = UIParent and UIParent.GetEffectiveScale
		and UIParent:GetEffectiveScale() or 1
	if theirs <= 0 then return 0 end
	return wide * mine / theirs + GUTTER_AIR
end

--- Push one window clear of the rail, or put it back where the client had it.
--
--  THE CLIENT'S OWN NUMBER IS ALWAYS READABLE, because UIPanelWindows is never
--  written to - only the frame's attribute is. So the original is not
--  something to record and risk losing; it is simply still there.
local function ApplyGutter(name, frame, gutter)
	if not (SetUIPanelAttribute and _G.UIPanelWindows) then return false end
	local decl = _G.UIPanelWindows[name]
	if not (decl and LEFT_AREAS[decl.area]) then return false end

	-- IT BAILS WITHOUT AN ENTRY, so this can only run while one exists - which
	-- is after the window's own addon has loaded. PN:Skin is called on
	-- ADDON_LOADED for exactly that reason.
	local ok = pcall(SetUIPanelAttribute, frame, "xoffset",
		(decl.xoffset or 0) + gutter)
	return ok
end

--- Every window we dress, moved clear of the rail. Reachable for the checks.
function PN:LayoutGutter(gutter)
	gutter = gutter or ToolboxGutter()
	local moved = 0
	for _, entry in ipairs(PANELS) do
		local frame = _G[entry.frame]
		if frame and ApplyGutter(entry.frame, frame, gutter) then
			moved = moved + 1
		end
	end
	return moved
end

function PN:Skin()
	-- CLEAR OF THE TOOLBOX'S HANDLE FIRST. The offset is read by the panel
	-- system when it PLACES a window, so setting it before dressing means a
	-- window opened during this pass is already in the right place.
	self:LayoutGutter()

	for _, entry in ipairs(PANELS) do
		local frame = _G[entry.frame]
		if frame and frame.GetRegions then
			-- PCALLED, AND THE FAILURE KEPT, per window. A throw in here used to
			-- come out of OnEnable, which turns the WHOLE MODULE off - and the
			-- windows already dressed by the time it threw keep their glass. So
			-- the interface came up looking skinned, with every hook, refresh and
			-- re-measure in the module dead, and nothing on screen saying so.
			--
			-- One forbidden frame among one window's children did exactly that.
			-- The interiors have been guarded this way for the same reason; the
			-- shell was the half that was not.
			PN.failures = PN.failures or {}
			local ok, err = pcall(Dress, frame)
			if ok then
				PN.failures[entry.frame] = nil
			else
				PN.failures[entry.frame] = tostring(err)
				A.lastFailure = "panels " .. entry.frame .. ": " .. tostring(err)
				A:Debug("panel shell failed:", entry.frame, err)
			end

			if frame.HookScript and not frame.__aetherHooked then
				frame.__aetherHooked = true
				-- Re-dressed on every show. These windows rebuild parts of
				-- themselves as they open - a tab's art, a background swapped
				-- for another - and art the client puts back has to come off
				-- again. See Core\Reskin.lua on hiding versus clearing.
				frame:HookScript("OnShow", function(self)
					if not PN.enabled then return end
					-- PCALLED, AND THE FAILURE KEPT, for the same reason the interiors
					-- are: a throw in here is swallowed by the client's own handler and
					-- the window simply stays as it was dressed at login, which looks
					-- exactly like a layout that ran and got the wrong answer.
					local ok, err = pcall(Dress, self)
					if not ok then
						PN.failures = PN.failures or {}
						PN.failures[entry.frame] = "on show: " .. tostring(err)
					end
					PN.Settle(self)
				end)
			end
		end
	end
end

--- The panel system putting a window UP, which is a later moment than OnShow.
--
--  OnShow fires from Show(), and ShowUIPanel clears the window's anchors and
--  places it AFTER that - so being told a window has opened is being told
--  about a frame that is not anywhere yet, and everything measured off it
--  comes back nil. This fires when the panel system has finished, which is
--  the first moment there is anything to measure.
--
--  Hooked once, on the shared entry point rather than per window: every one of
--  these windows goes up through it.
function PN:WatchPanelSystem()
	if PN.__panelHook or not hooksecurefunc or not ShowUIPanel then return end
	PN.__panelHook = true
	hooksecurefunc("ShowUIPanel", function(frame)
		if not PN.enabled or type(frame) ~= "table" then return end
		local name = frame.GetName and frame:GetName()
		if not (name and PN.ENTRY and PN.ENTRY[name]) then return end
		local ok, err = pcall(Dress, frame)
		if not ok then
			PN.failures = PN.failures or {}
			PN.failures[name] = "on panel show: " .. tostring(err)
		end
	end)
end

function PN:OnEnable()
	self:Skin()
	self:WatchPanelSystem()

	-- The load-on-demand half. Each arrives with its own addon the first time
	-- it is opened, so this runs again rather than only at login.
	A:RegisterEvent(self, "ADDON_LOADED", function() PN:Skin() end)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() PN:Skin() end)
end

function PN:OnDisable()
	A:UnregisterAllEvents(self)

	-- THE CLIENT'S OWN PLACE BACK. The gutter is an offset of ours on top of
	-- the client's number, and a nought gutter is that number on its own.
	self:LayoutGutter(0)

	-- THE CLIENT'S OWN FONT OBJECTS, HANDED BACK. The postbox's receipt takes
	-- its ink from InvoiceTextFontNormal and InvoiceTextFontSmall rather than
	-- from its own strings, so lifting it means editing something shared - and
	-- a module that switches off has to leave the interface as it found it.
	for name, was in pairs(PN.__invoiceInk or {}) do
		local font = _G[name]
		if font and font.SetTextColor and was[1] then
			font:SetTextColor(was[1], was[2], was[3], was[4] or 1)
		end
	end
	PN.__invoiceInk = nil

	for _, entry in ipairs(PANELS) do
		local frame = _G[entry.frame]
		if frame and frame.__aetherPanel then
			local close = CloseButton(frame)
			if close and close.__aetherClose then
				close.__aetherClose:Hide()
				close.__aetherClose = nil
				if close.__aetherCloseWash then
					close.__aetherCloseWash:Hide()
					close.__aetherCloseWash = nil
				end
			end

			-- Regions first, buttons after: a button's state textures are also
			-- regions on it, recorded after they were cleared, so restoring
			-- regions last would undo the restore. Same trap as Popups.
			Reskin.Release(frame, frame.__aetherArt or {})
			frame.__aetherArt = nil
			if close then Reskin.RestoreButton(close) end

			-- Its own size back, and its tabs where the client had them.
			if frame.SetScale then frame:SetScale(1) end

			local name = frame.GetName and frame:GetName()
			local n = 1
			while name and TabAt(name, n) do
				local tab = TabAt(name, n)
				if tab.__aetherAnchor then
					tab:ClearAllPoints()
					tab:SetPoint(unpack(tab.__aetherAnchor))
				end
				if tab.__aetherSize and tab.SetSize then
					tab:SetSize(tab.__aetherSize[1], tab.__aetherSize[2])
				end
				if tab.__aetherHit and tab.SetHitRectInsets then
					tab:SetHitRectInsets(unpack(tab.__aetherHit))
				end
				tab.__aetherAnchor, tab.__aetherSize, tab.__aetherHit = nil, nil, nil
				if tab.__aetherTab then
					tab.__aetherTab:Hide()
					tab.__aetherTab = nil
				end
				Reskin.RestoreButton(tab)
				n = n + 1
			end
		end
	end
end

function PN:OnSkinChanged()
	for _, entry in ipairs(PANELS) do
		local frame = _G[entry.frame]
		if frame and frame.__aetherPanel then
			frame.__aetherPanel:ApplySkin("dialogFill", "glassEdgeHi")
			if frame.__aetherTitle then W.Color(frame.__aetherTitle, Palette.c.text) end
		end
	end

	-- And everything INSIDE them. The shell is a surface and answers ApplySkin;
	-- a talent's rim, a rank chip and a check box are colours read off the
	-- palette at dress time, and nothing re-reads them on their own. Skin is
	-- safe to run again - it is what /aether config already does on any change.
	self:Skin()
end

function PN:OnConfigChanged() self:Skin() end
