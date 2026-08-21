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
local MAIL_TAB_DROP = 40
-- Letters on a page of the inbox. Seven, and the client pages rather than
-- scrolls: the postbox holds fifty and shows a page of these at a time, which
-- is what its Prev and Next are for.
local MAIL_ROWS     = 7
-- Item slots on a letter, which the client also places from Lua.
local MAIL_ATTACHMENTS = 16
-- Ink below this is the client writing for parchment; ink above it is the
-- client meaning something - a gold subject, a red loss.
local RECEIPT_DARK  = 0.5

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
local SKILL_HEAD       = SKILL_ALL_H + 6 + SKILL_BAR_H + W.PANEL_GAP

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
	{ frame = "CharacterFrame", insets = { 10, -10, -30, 26 },
		title = "CharacterNameText", subtitle = "CharacterLevelText",
		panes = {
			{ pane = "PetPaperDollFrame",
				title = "PetNameText", subtitle = "PetLevelText" },
		},
		-- THE FIVE TABS. Every one is setAllPoints to the window, so moving
		-- the pane carries every slot, string and model hanging off it - and
		-- each is measured on its own, because they do not agree about where
		-- their content begins: the first equipment slot is 74 below the
		-- frame, the reputation columns are headed at 57 and the skill
		-- list's ALL tab sits at 49.
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
		title       = "SpellBookTitleText",
		close       = "SpellBookCloseButton",
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
	{ frame = "FriendsFrame" },

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
		-- A DOZEN PIECES, ALL HUNG OFF THE FRAME at their own fixed offsets: two
		-- names five units down, two purses at sixty, two columns of slots at
		-- eighty-nine. `together` because shifting each by what IT is short of
		-- squeezes the window: the names would travel eighty units and the slots
		-- eight, and what was a layout becomes a heap.
		together = true,
		body = { "TradeFramePlayerNameText", "TradeFrameRecipientNameText",
			"TradePlayerItemsInset", "TradeRecipientItemsInset",
			"TradePlayerInputMoneyInset", "TradeRecipientMoneyInset",
			"TradePlayerItem1", "TradeRecipientItem1",
			"TradePlayerInputMoneyFrame", "TradeRecipientMoneyFrame" },
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
	{ frame = "TaxiFrame",         insets = { 8, -8, -28, 22 },
	                               close = "TaxiCloseButton",
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
	return (entry and entry.close
		and ((frame[entry.close]) or _G[entry.close]))
		or Reskin.Element(frame, "CloseButton")
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
	if entry and entry.subtitle and _G[entry.subtitle] then
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
		local pane = _G[p.pane]
		-- ...and that brought a title with it. A pane can be up on a build
		-- where the string it names does not exist, and a header with no
		-- title at all is worse than one naming the wrong thing.
		if pane and pane.IsShown and pane:IsShown() and _G[p.title] then
			return _G[p.title], p.subtitle and _G[p.subtitle] or nil
		end
	end
	return entry and entry.title and _G[entry.title] or nil,
		entry and entry.subtitle and _G[entry.subtitle] or nil
end

--- The frame a panel entry means by a name.
--
--  A global, or a PATH through one - because the modern templates stopped
--  naming things globally. The gossip window's list of what you can say is
--  GossipFrame.GreetingPanel.ScrollBox and has no name of its own at all, so
--  a list of globals cannot reach a single part of it.
function PN.Part(name)
	if type(name) ~= "string" then return nil end
	local w
	for step in name:gmatch("[^.]+") do
		w = (w == nil) and _G[step] or (type(w) == "table" and w[step] or nil)
		if w == nil then return nil end
	end
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
local function RowLive(frame, list)
	for _, name in ipairs(list or {}) do
		local w = RowPart(frame, name)
		if w and w.IsVisible and w:IsVisible() then return true end
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

	local prev
	for _, name in ipairs(spec.left or {}) do
		local w = part(name)
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
		local w = part(name)
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
		if w and w.IsVisible and w:IsVisible() then
			shown[#shown + 1] = w
			total = total + span(w)
		end
	end
	for _, w in ipairs(frame.__aetherActions or {}) do
		if w.IsVisible and w:IsVisible() and w.ClearAllPoints then
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
		local fs = name and _G[name]
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
		local left = f.GetLeft and f:GetLeft()
		if left and left >= wall and (not side or left < side) then side = left end
		-- WHEREVER IT IS, including past the edge it should have stopped at. This
		-- used to ignore anything reaching beyond the boundary, which meant the
		-- one thing it could never measure was content that ALREADY overflows -
		-- so a window whose text runs out through the rim could not be widened to
		-- fit it. The spellbook's second column of spell names is that case: our
		-- lettering is wider than the client's, and the names ran under the
		-- school tabs.
		local right = f.GetRight and f:GetRight()
		if right and (not edge or right > edge) then edge = right end
	end

	local function walk(f, depth)
		if depth > 4 or ours[f] then return end
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
			-- NO `goto` HERE, and none anywhere else in this addon: the game runs
			-- Lua 5.1, which has no such statement. LuaJIT does, so the harness
			-- compiled it happily and the whole file failed to load in the client.
			if c ~= scrolled and not ours[c] and c.IsShown and c:IsShown() then
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
		local pane = _G[p.pane]
		if pane and pane.HookScript and not pane.__aetherWatched then
			pane.__aetherWatched = true
			pane:HookScript("OnShow", function()
				if not PN.enabled then return end
				PN.RefreshHeader(name)
				PN.RefreshFooter(name)
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
local function RowUp(spec)
	for _, side in ipairs({ "left", "right", "mid" }) do
		for _, name in ipairs(spec[side] or {}) do
			local w = Part(name)
			if w and w.IsShown and w:IsShown() then return true end
		end
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
	if entry and entry.row and RowUp(entry.row) then
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

	local grow = wide + tail
	local wasWide = frame.__aetherBodyGrow or 0
	if grow ~= wasWide and frame.SetWidth and frame.GetWidth then
		frame:SetWidth((frame:GetWidth() or 0) + (grow - wasWide))
	end
	frame.__aetherBodyInset = wide
	frame.__aetherBodyGrow = grow

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
		for _, shift in ipairs(shifts) do
			local pane = shift[1]
			local top = pane.GetTop and pane:GetTop()
			local low = pane.GetBottom and pane:GetBottom()
			if pane.GetScrollChild and top and low and low < floorY
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
local function DressClose(frame, store)
	local close = CloseButton(frame)
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
	local title = (entry and entry.title and _G[entry.title]) or nil
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

--- The nth tab of a window, under whatever name that window gives its tabs.
--
--  Most of them are $parentTab1..n. The spellbook is not, and asking for
--  SpellBookFrameTab1 finds nothing at all - which is a tab strip that quietly
--  never gets laid out rather than an error anybody would notice.
local function TabAt(name, i)
	local entry = PN.ENTRY and PN.ENTRY[name]
	return _G[(entry and entry.tabs or (name .. "Tab")) .. i]
end

--- Selected or not, in our own weight.
--
--  The client marks the open tab by DISABLING it - a disabled tab is the one
--  you are looking at, which reads backwards until you know it.
local function StyleTabState(tab)
	local enabled = (tab.IsEnabled == nil) or tab:IsEnabled()
	local selected = not enabled

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
end

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

-- The skill list's rows. Blizzard builds twelve of them in XML and reuses them
-- as you scroll, so the list is twelve rows tall whatever the window is - and
-- in a window of ours it ends halfway down with empty glass underneath and no
-- sign that there is more.
--
-- The rows come from two templates, the pitch between them is 18, and
-- SkillFrame_UpdateSkills fills however many SKILLS_TO_DISPLAY says there are.
-- So we add rows to its pool from its own templates and tell it the new count:
-- the client still owns what goes in them.
local SKILL_ROW_PITCH   = 18
local SKILL_FIRST_ROW_Y = 79     -- where the client puts row one, from the top
local SKILL_BOTTOM_KEEP = 78     -- the tab strip, and air above it
local SKILL_ROWS_MAX    = 40

local function GrowSkillRows()
	local frame, first = _G.SkillFrame, _G.SkillRankFrame1
	if not frame or not first or not CreateFrame then return end

	local host = _G.CharacterFrame or frame
	local height = host.GetHeight and host:GetHeight() or 0
	if height <= 0 then return end

	local have = _G.SKILLS_TO_DISPLAY or 12
	local room = height - SKILL_FIRST_ROW_Y - SKILL_BOTTOM_KEEP
	local want = math.floor(room / SKILL_ROW_PITCH)

	if want > SKILL_ROWS_MAX then want = SKILL_ROWS_MAX end
	if want <= have then return end

	for n = have + 1, want do
		if not _G["SkillRankFrame" .. n] then
			local prevBar = _G["SkillRankFrame" .. (n - 1)]
			local prevLabel = _G["SkillTypeLabel" .. (n - 1)]
			if not prevBar or not prevLabel then break end

			-- The client's own templates, so these are the same objects its
			-- update function expects to find - not lookalikes of ours.
			local bar = CreateFrame("StatusBar", "SkillRankFrame" .. n, frame,
				"SkillStatusBarTemplate")
			if bar.SetID then bar:SetID(n) end
			bar:SetPoint("TOPLEFT", prevBar, "BOTTOMLEFT", 0, -3)

			local label = CreateFrame("Button", "SkillTypeLabel" .. n, frame,
				"SkillLabelTemplate")
			label:SetPoint("LEFT", prevLabel, "LEFT", 0, -SKILL_ROW_PITCH)
		end
	end

	_G.SKILLS_TO_DISPLAY = want

	-- The viewport grows with them, or the wheel still scrolls twelve rows'
	-- worth over a list that is now twenty tall.
	local list = _G.SkillListScrollFrame
	if list and list.SetHeight then list:SetHeight(want * SKILL_ROW_PITCH) end

	if _G.SkillFrame_UpdateSkills then _G.SkillFrame_UpdateSkills() end
end

--- Every collapse control in the character sheet, in our marks.
--
--  Both trees use them: the skill list's group headers and the reputation
--  list's, plus the "All" control that governs the whole skill tree.
local function DressCollapses()
	for n = 1, (_G.SKILLS_TO_DISPLAY or 0) do
		Reskin.Collapse(_G["SkillTypeLabel" .. n])
	end
	for n = 1, (_G.NUM_FACTIONS_DISPLAYED or 0) do
		Reskin.Collapse(_G["ReputationHeader" .. n])
	end
	Reskin.Collapse(_G.SkillFrameCollapseAllButton)
end

--- Answer the client when it repaints those marks.
--
--  SkillFrame_UpdateSkills sets every header's normal texture back to a stone
--  plus or minus each time the list changes - which is every expand, every
--  collapse and every scroll. Ours has to go back on after it, not instead of
--  it.
local function InstallSkillHook()
	if PN.__skillHook or not hooksecurefunc then return end

	if _G.SkillFrame_UpdateSkills then
		PN.__skillHook = true
		hooksecurefunc("SkillFrame_UpdateSkills", function()
			if PN.enabled then DressCollapses() end
		end)
	end

	if _G.ReputationFrame_Update then
		hooksecurefunc("ReputationFrame_Update", function()
			if PN.enabled then DressCollapses() end
		end)
	end
end

--- Panes whose art comes off. Every one is a container the client draws a stone
--  frame around; the window's own glass is the only surface wanted behind them.
local CHAR_PANES = {
	"PaperDollFrame", "PetPaperDollFrame", "ReputationFrame", "SkillFrame",
	"HonorFrame", "CharacterAttributesFrame", "PetAttributesFrame",
	"ReputationListScrollFrame", "SkillListScrollFrame", "SkillDetailScrollFrame",
}

--- Art in one of those panes that is not the pane's own.
--
--  A sweep takes every texture on a frame, and some of these hold a picture
--  the player is reading among the stone: the PvP rank badge is a region of
--  the honour pane exactly as its parchment is, so taking the parchment took
--  the badge and left the rank with nothing beside it. Same shape as the
--  flight map, and named the same way.
local PANE_KEEP = {
	HonorFrame            = { "HonorFramePvPIcon" },
	InspectHonorFrame     = { "InspectHonorFramePvPIcon" },
	-- Shown in place of the model when the player is too far off to draw:
	-- their faction's crest, filling the box the doll would have stood in.
	InspectPaperDollFrame = { "InspectFaction" },
}

--- An equipped item's rim, in its quality colour.
--
--  Re-run on every slot update, because the client repaints its own border
--  whenever the item changes and ours has to answer.
--
--  The unit is asked for rather than assumed: the same slots and the same rim
--  serve the inspect window, and "player" there is your own gear colouring
--  somebody else's.
local function SlotQuality(btn, unit)
	if not btn or not btn.SetEdgeColor then return end

	local id = btn.GetID and btn:GetID()
	local q = id and GetInventoryItemQuality
		and GetInventoryItemQuality(unit or "player", id)
	local c = q and q > 1 and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]

	-- Common and poor get the ordinary rim: a white border on every empty slot
	-- is noise, and the point of the colour is that it stands out.
	btn:SetEdgeColor(c and { c.r, c.g, c.b, 1 } or Palette.c.glassEdge)
end

--- The doll's box, and the two buttons that turn it.
--
--  ON THE MODEL, BOTTOM-RIGHT, and not beside it. They were a picture of a
--  button - arrow and stone disc in one texture - and then, briefly, two
--  chevrons in the window's furniture, which is worse: a chevron means
--  NAVIGATION, a page or a carousel or a drawer, and a character model has no
--  pages. Turning it is manipulation, and manipulation belongs on the thing
--  being manipulated.
--
--  Blizzard names them from the MODEL's point of view rather than the
--  camera's and says so in its own XML, which is why RotateRightButton is the
--  one that turns it left.
local function DressModel(prefix, store)
	local model = _G[prefix .. "ModelFrame"]
	if not model then return end

	Reskin.Strip(model, store)
	for _, key in ipairs({ "RotateRightButton", "RotateLeftButton" }) do
		local btn = _G[prefix .. "ModelFrame" .. key]
		if btn then
			Reskin.ClearButton(btn)
			if type(store) == "table" then Reskin.Strip(btn, store) end
		end
	end

	-- THE BOX THE DOLL STANDS IN, DRAWN. Without it the model floats in the
	-- window and every asymmetry in it reads as OUR mistake: the imp on the
	-- pet tab looks pushed to the right, and the reason is that its own box -
	-- which the client centres it in - has whitespace on one side that nothing
	-- was marking. With a rim round it the whitespace is plainly whitespace.
	--
	-- Below the model rather than around it: a PlayerModel renders a scene
	-- with a transparent ground once the client's black overlay is off, so a
	-- recess behind it shows through exactly where the doll is not.
	local host = (model.GetParent and model:GetParent()) or model
	local well = model.__aetherModelWell
	if not well then
		well = W.ContentWell(host)
		well:SetAllPoints(model)
		well:SetFrameLevel(math.max(0, (model:GetFrameLevel() or 1) - 1))
		if well.EnableMouse then well:EnableMouse(false) end
		model.__aetherModelWell = well
	end
	well:ApplySkin("wellFill", "wellEdge")

	W.RotatePair(model,
		_G[prefix .. "ModelFrameRotateLeftButton"],
		_G[prefix .. "ModelFrameRotateRightButton"])
end

local function EachEquipSlot(fn)
	local items = _G.PaperDollItemsFrame
	if not items or not items.GetChildren then return end

	for _, slot in ipairs({ items:GetChildren() }) do
		-- ElvUI's test, and the reason for it: the frame holds more children
		-- than slots, and only a slot carries a Count.
		if slot and slot.Count and slot.GetID then fn(slot) end
	end
end

local function DressCharacter(frame, store)
	for _, name in ipairs(CHAR_PANES) do
		local pane = _G[name]
		if pane then
			Reskin.Strip(pane, store, PANE_KEEP[name])

			-- And every string in it into our lettering. The client's own
			-- sizes are kept: these sit in rows and columns it measured, and a
			-- size of ours reflows somebody else's window.
			Reskin.Fonts(pane, "pnBody")
		end
	end

	-- WHO YOU ARE is the window's TITLE and what you are is its subtitle,
	-- named as such in the panel list - so the shell has already roled and
	-- placed both by the time this runs. It used to do it here, one point
	-- larger than every other panel's title, which is exactly the drift the
	-- header band exists to end.
	local rank = _G.CharacterLevelText
	if rank and rank.SetText then W.Color(rank, Palette.c.textDim) end

	EachEquipSlot(function(slot)
		Reskin.Slot(slot)
		SlotQuality(slot)
	end)

	LayoutTabs(frame, store)
	InstallTabHooks()

	-- BOTH DOLLS. The pet has a model box of its own on its own tab, with its
	-- own pair of turn buttons under names of the same shape - and it had been
	-- left with the client's stone discs beside a sheet that is otherwise ours.
	DressModel("Character", store)
	DressModel("Pet", store)

	-- RESISTANCE CHIPS, and the school's own icon KEPT. These were stripped
	-- whole, which took the icon with them and left five bare numbers floating
	-- down the side of the sheet with nothing saying which school each one
	-- was - arcane, fire, nature, frost, shadow, and no way to tell.
	--
	-- The icon is unnamed and is the frame's only texture, so it is found by
	-- walking the regions rather than asked for by key. Same shape as the
	-- spellbook's school tabs: the picture IS the thing, and a sweep that
	-- takes every texture takes the thing.
	for _, prefix in ipairs({ "MagicResFrame", "PetMagicResFrame" }) do
		for n = 1, 5 do
			local chip = _G[prefix .. n]
			if chip and chip.GetRegions then
				local icon
				for _, r in ipairs({ chip:GetRegions() }) do
					if not icon and r.GetObjectType and r:GetObjectType() == "Texture"
						then icon = r end
				end
				Reskin.StripExcept(chip, store, icon and { icon } or nil)
			end
		end
	end

	-- Reputation: one bar per faction row, plus the list's scroll bar.
	for n = 1, (_G.NUM_FACTIONS_DISPLAYED or 0) do
		local bar = _G["ReputationBar" .. n]
		if bar then Reskin.StatusBar(bar, store) end

		local war = _G["ReputationBar" .. n .. "AtWarCheck"]
		if war then Reskin.CheckBox(war, store) end
	end

	-- More rows first, so the loop below skins the ones we just added too.
	GrowSkillRows()
	InstallSkillHook()

	-- Skills: same shape, different list, plus a border and a backing plate on
	-- every row that are separate objects from the bar itself.
	for n = 1, (_G.SKILLS_TO_DISPLAY or 0) do
		local bar = _G["SkillRankFrame" .. n]
		if bar then Reskin.StatusBar(bar, store) end

		for _, part in ipairs({ "Border", "Background" }) do
			local obj = _G["SkillRankFrame" .. n .. part]
			if obj then
				if obj.GetObjectType and obj:GetObjectType() == "Texture" then
					obj:SetTexture(0)
				else
					Reskin.Strip(obj, store)
				end
			end
		end

		local label = _G["SkillTypeLabel" .. n]
		if label and label.SetText then
			Roled(label.GetFontString and label:GetFontString() or label, "pnBody")
			W.Color(label, Palette.c.text)
		end
	end

	-- SPARE CLOSE BUTTONS, one per tab that has one, each doing exactly what
	-- the X in the corner already does: the skills list has one in the middle
	-- of it and the pet tab has one under the doll. Hidden rather than cleared,
	-- because they are whole buttons we do not want rather than art we are
	-- replacing - and clearing one leaves a live invisible button behind.
	for _, name in ipairs({ "SkillFrameCancelButton", "PetPaperDollCloseButton" }) do
		local spare = _G[name]
		if spare and spare.Hide and not spare.__aetherHidden then
			spare.__aetherHidden = spare:IsShown() and true or false
			spare:Hide()
		end
	end

	-- "ALL", which expands and collapses the whole tree - so it belongs at the
	-- head of it, on the left, above the groups it governs. The client hangs it
	-- off a little stone tab out to the right, which reads as a sibling of the
	-- groups rather than their parent. The tab's art comes off and the control
	-- moves to the left margin.
	local all = _G.SkillFrameCollapseAllButton
	if all then
		for _, part in ipairs({ "SkillFrameExpandTabLeft", "SkillFrameExpandTabMiddle",
			"SkillFrameExpandTabRight" }) do
			local art = _G[part]
			if art then
				if art.GetObjectType and art:GetObjectType() == "Texture" then
					art:SetTexture(0)
				elseif art.GetRegions then
					Reskin.Strip(art, store)
				end
			end
		end

		-- Above the first group and hard against the same left edge, which is
		-- what makes it read as the parent of them.
		local firstGroup = _G.SkillTypeLabel1
		if firstGroup and all.ClearAllPoints then
			all:ClearAllPoints()
			all:SetPoint("BOTTOMLEFT", firstGroup, "TOPLEFT", 0, 4)
		end

		local allText = all.GetFontString and all:GetFontString()
		if allText then Roled(allText, "pnBody") end
	end

	DressCollapses()

	for _, name in ipairs({
		"ReputationListScrollFrameScrollBar", "SkillListScrollFrameScrollBar",
		"SkillDetailScrollFrameScrollBar",
	}) do
		local sb = _G[name]
		if sb then Reskin.ScrollBar(sb, store) end
	end

	for _, name in ipairs({
		"ReputationDetailAtWarCheckbox", "ReputationDetailInactiveCheckbox",
		"ReputationDetailMainScreenCheckbox",
	}) do
		local box = _G[name]
		if box then Reskin.CheckBox(box, store) end
	end

	for _, name in ipairs({ "SkillDetailStatusBar", "HonorFrameProgressBar",
	                        "PetPaperDollFrameExpBar" }) do
		local bar = _G[name]
		if bar then Reskin.StatusBar(bar, store) end
	end

	-- The client repaints a slot's border whenever its item changes, so the
	-- quality rim has to be reapplied after it, not once at dress time.
	if not PN.__slotHook and hooksecurefunc and _G.PaperDollItemSlotButton_Update then
		PN.__slotHook = true
		hooksecurefunc("PaperDollItemSlotButton_Update", function(btn)
			if PN.enabled then SlotQuality(btn) end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- somebody else's character sheet
-- ---------------------------------------------------------------------------
--
-- The same paper doll and not one shared name, so the parts that are genuinely
-- the same - the model box, the quality rim - are asked for by prefix or by
-- unit and the rest is spelled out here.
--
-- Two things it does that ours does not. Its slots keep their STONE PLATE in a
-- background region rather than in the normal texture, the way a mail
-- attachment does, so the cell dresser only reaches it when it is handed a
-- store. And every slot on it belongs to somebody else, so the rim reads the
-- unit being inspected - "player" there is your own gear colouring their gear.

local INSPECT_PANES = {
	"InspectPaperDollFrame", "InspectHonorFrame", "InspectPaperDollItemsFrame",
}

-- Nineteen, in the client's own spelling. Not walked off the items frame the
-- way ours are: the ranged slot is hidden on a class that cannot use one, and
-- a hidden slot is still a slot with our cell on it.
local INSPECT_SLOTS = {
	"Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
	"Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0",
	"Trinket1", "MainHand", "SecondaryHand", "Ranged",
}

--- Who the window is looking at.
--
--  The client keeps it on the frame and clears it on hide, so this is asked
--  every time rather than remembered.
local function InspectUnit()
	return (_G.InspectFrame and _G.InspectFrame.unit) or "target"
end

local function DressInspect(frame, store)
	for _, name in ipairs(INSPECT_PANES) do
		local pane = _G[name]
		if pane then
			Reskin.Strip(pane, store, PANE_KEEP[name])
			Reskin.Fonts(pane, "pnBody")
		end
	end

	-- WHO YOU ARE LOOKING AT. The window's own title band is never filled in -
	-- the client puts the name in a little frame of its own instead - so this
	-- is the title of the window whatever the template calls it.
	local who = _G.InspectNameText
	if who then
		-- Measured at 109 wide for the client's twelve-point type, and ours is
		-- bigger: left at that width a name of any length comes out clipped.
		-- It is centred, so letting it size itself grows it evenly either way.
		if who.SetWidth then who:SetWidth(0) end
		Roled(who, "pnTitle")
		W.Color(who, Palette.c.text)
	end

	local rank = _G.InspectLevelText
	if rank then
		Roled(rank, "pnSub")
		W.Color(rank, Palette.c.textDim)
	end
	for _, name in ipairs({ "InspectTitleText", "InspectGuildText" }) do
		local fs = _G[name]
		if fs then W.Color(fs, Palette.c.textDim) end
	end

	DressModel("Inspect", store)

	local unit = InspectUnit()
	for _, slot in ipairs(INSPECT_SLOTS) do
		local btn = _G["Inspect" .. slot .. "Slot"]
		if btn then
			Reskin.Slot(btn, { store = store })
			SlotQuality(btn, unit)
		end
	end

	-- The honour tab's rank progress, which is the only bar in the window.
	Reskin.StatusBar(_G.InspectHonorFrameProgressBar, store)

	LayoutTabs(frame, store)
	InstallTabHooks()

	-- The client repaints a slot's border every time it is told what is in it,
	-- and on this window that is not only an item changing - the whole set
	-- arrives late, on INSPECT_READY, after we have already been past.
	if not PN.__inspectHook and hooksecurefunc
		and _G.InspectPaperDollItemSlotButton_Update then
		PN.__inspectHook = true
		hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(btn)
			if PN.enabled then SlotQuality(btn, InspectUnit()) end
		end)
	end
end

--- The main menu: a stack of buttons and nothing else.
--
--  Its shell was already in glass while every button inside it stayed a red
--  Blizzard plate, which is the worst of both. The buttons are not listed by
--  name because the client's set changes with the build - Edit Mode and Support
--  are there on one flavour and not another - so the frame is asked what it
--  has.
-- The gap between one button and the next, and between the title and the
-- first of them.
--
-- BLIZZARD SETS SPACING TO ZERO and gets away with it because its button art
-- carries a transparent margin - the rows look separated while the frames
-- touch. Ours is a drawn rectangle with no margin at all, so at zero the
-- buttons come out as one column of glass with lines of text in it.
--
-- The frame is a VerticalLayoutFrame: it reads `spacing` and `topPadding`
-- off itself every time it lays out, and Reset clears neither - so setting
-- them once holds for every open after.
local MENU_SPACING = 6

-- The TOP padding is not here. It is the header band's height plus the body
-- padding, which LayoutBody works out for every window in the interface - and
-- a private 44 in this file was a fourth copy of that sum, set AFTER the
-- shared one because interiors run last. On screen: the first button across
-- the hairline, on the one window that had already been told not to.

-- Forward-declared: it hooks InitButtons with a closure that calls itself,
-- and a `local function` cannot refer to its own name from inside.
local DressGameMenu
DressGameMenu = function(frame, store)
	if not frame.GetChildren then return end

	frame.spacing = MENU_SPACING

	-- ITS BUTTONS COME OUT OF A POOL, and the pool is refilled by
	-- InitButtons - which the client calls on OnShow and again on its own
	-- events, AFTER the OnShow hook that brought us here. A button the pool
	-- mints on one of those later passes has never been dressed, and the
	-- window comes back red with no error anywhere.
	--
	-- So the dressing is hung off InitButtons itself rather than done once
	-- on the way past. Hooked on the FRAME rather than on the mixin: the
	-- mixin is shared with every other window built on this template.
	if not frame.__aetherInit and hooksecurefunc and frame.InitButtons then
		frame.__aetherInit = true
		hooksecurefunc(frame, "InitButtons", function(self)
			if PN.enabled then DressGameMenu(self, store) end
		end)
	end

	for _, child in ipairs({ frame:GetChildren() }) do
		-- A button, by what it can do rather than what it is called.
		if child and child.SetNormalTexture and child.GetFontString then
			Reskin.Button(child)
			Reskin.Strip(child, store)
		end
	end

	-- LAID OUT AGAIN, or the new spacing is a number nobody has read. The
	-- client lays out when it is dirty; MarkDirty is how you say so.
	if frame.MarkDirty then frame:MarkDirty() end
	if frame.Layout then pcall(frame.Layout, frame) end
end

-- ---------------------------------------------------------------------------
-- the spellbook
-- ---------------------------------------------------------------------------
--
-- Twelve spell buttons in two columns, a column of school tabs down the right,
-- a page turner along the bottom and the book's own tabs under that. Shapes and
-- names read off the client's SpellBookFrame.xml and SpellBookFrame.lua for
-- this flavour rather than guessed at, because two of its parts keep their
-- picture in a region the usual sweeps would take: a spell keeps its icon
-- beside the ring, and a school tab keeps its icon AS the normal texture.

local SPELL_BUTTONS = 12         -- SPELLS_PER_PAGE
local SPELL_TABS    = 8          -- MAX_SKILLLINE_TABS

-- The school tabs down the right. Blizzard spaces them 17 apart because each
-- 32px button carries 64px of stone behind it and the stone has to clear its
-- neighbour; with the stone gone that gap reads as a column of unrelated icons.
local SIDE_TAB_GAP  = 6
-- The rail the schools sit on, and its width comes from the icon it has to
-- hold rather than from the handoff's 52 - the day somebody changes the icon
-- size, a number here stops fitting it.
local SIDE_TAB_ICON = 32
local SIDE_RAIL_W   = SIDE_TAB_ICON + SIDE_TAB_GAP * 2
local SIDE_TAB_TOP  = 62         -- below the title and the ranks check box

-- The page turner. Angle marks rather than Blizzard's engraved arrows: with
-- the art off there is nothing left on the button to click at all.
local GLYPH_PREV, GLYPH_NEXT = "\226\128\185", "\226\128\186"
local PAGE_TURNER_Y = 105        -- where the client puts both arrows

--- One of the client's buttons carrying a single character of ours.
local function MarkButton(btn, store, glyph)
	if not btn then return end

	Reskin.ClearButton(btn)
	if store then Reskin.Strip(btn, store) end

	local mark = btn.__aetherMark
	if not mark then
		mark = W.Text(btn, "pnTitle", "CENTER")
		mark:SetPoint("CENTER", btn, "CENTER", 0, 0)
		btn.__aetherMark = mark
	end
	mark:SetText(glyph)
	W.Color(mark, Palette.c.textDim)
	return mark
end

--- A spell's name and rank, and whether it is the one you have open.
--
--  Re-run rather than done once: SpellButtonMixin:UpdateButton sets the name's
--  colour on every refresh - gold for a spell you can cast, grey for a passive
--  - and puts its own white highlight square back on the button while it is at
--  it. Our type survives that; our colours do not.
local function StyleSpell(btn)
	local title = Reskin.Element(btn, "SpellName")
	if title then
		Reskin.Font(title, "pnBody")
		W.Color(title, btn.isPassive and Palette.c.textDim or Palette.c.text)
	end

	local sub = Reskin.Element(btn, "SpellSubName")
	if sub then
		Reskin.Font(sub, "pnBody")
		W.Color(sub, Palette.c.textFaint)
	end

	-- An open profession marks itself by checking the button. The client's mark
	-- for that is a white square over the icon; ours is the cell's own rim.
	if btn.SetEdgeColor then
		local on = btn.GetChecked and btn:GetChecked()
		btn:SetEdgeColor(on and Palette.c.accent or Palette.c.glassEdge)
	end
end

local function DressSpellButtons(store)
	for i = 1, SPELL_BUTTONS do
		local btn = _G["SpellButton" .. i]
		if btn then
			-- The icon is a region of the button and the ring is the normal
			-- texture. Strip would take both; ClearButton alone would leave the
			-- parchment disc behind the icon standing.
			Reskin.IconButton(btn, store, { icon = Reskin.Element(btn, "IconTexture") })
			StyleSpell(btn)

			if hooksecurefunc and btn.UpdateButton and not btn.__aetherSpellHook then
				btn.__aetherSpellHook = true
				hooksecurefunc(btn, "UpdateButton", function(self)
					if not PN.enabled then return end
					Reskin.ClearButton(self)
					StyleSpell(self)
				end)
			end
		end
	end
end

--- A column of icon tabs down the right-hand edge of a window.
--
--  The spellbook's schools and the talent frame's specs are the same widget
--  under two names - both are PlayerSpecTab-shaped 32px check buttons carrying
--  64px of stone, and both keep their picture as the normal texture.
--- The vertical half of the tab language: a column of pictures, not words.
--
--  Same rail, rotated. The schools are a SECONDARY filter within the book the
--  bottom rail has already chosen - two axes, one panel - so they get the
--  icon rail rather than a second row of words.
--
--  THE RAIL'S FAINT WASH IS NOT DECORATION. It is the only thing saying that
--  eight pictures in a column are one control rather than eight loose buttons,
--  which is what they read as before: the handoff calls it mandatory and it is
--  right. The hairline does that job for a row of words; a column of icons has
--  no words to gather.
--
--  An inactive icon DIMS AND DRAINS rather than going quiet, which is the
--  exact analogue of dim text - a picture cannot be made faint without losing
--  what it is a picture of.
local function DressSideTabs(frame, store, prefix, count)
	local name = frame.GetName and frame:GetName()
	local entry = name and PN.ENTRY and PN.ENTRY[name]
	local ins = entry and entry.insets or {}

	-- FROM UNDER THE HEADER TO THE FOOT OF THE PANEL. It used to be only as
	-- long as the icons on it, on the argument that a column of rail running
	-- past the last one reads as a control with empty slots. That is an
	-- argument about a WASH, which this no longer has - what is left is a
	-- hairline, and a hairline that stops halfway down the window is a line
	-- that has been cut off rather than an edge.
	--
	-- It eats the side padding and never the header: the title and the way out
	-- run the full width of the frame, exactly as they do on a window with no
	-- rail at all.
	local rail = W.TabRail(frame, "RIGHT")
	rail:ClearAllPoints()
	rail:SetPoint("TOPRIGHT", frame, "TOPRIGHT",
		(ins[3] or 0), (ins[2] or 0) - PN.HeaderHeight(name))
	rail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
		(ins[3] or 0), (ins[4] or 0))
	rail:SetWidth(SIDE_RAIL_W)

	local last, shown = nil, 0
	for i = 1, count do
		local tab = _G[prefix .. i]
		if not tab then break end

		-- No icon named: the school's picture IS this button's normal texture,
		-- which is what IconButton assumes when it is not told otherwise.
		Reskin.IconButton(tab, store)
		local art = tab.GetNormalTexture and tab:GetNormalTexture()
		W.Tab(tab, { icon = true, edge = "RIGHT", art = art, rail = rail })
		W.TabState(tab, tab.GetChecked and tab:GetChecked() or false, false)

		if tab.ClearAllPoints then
			tab:ClearAllPoints()
			if last then
				tab:SetPoint("TOP", last, "BOTTOM", 0, -SIDE_TAB_GAP)
			else
				tab:SetPoint("TOP", rail, "TOP", 0, -SIDE_TAB_TOP)
			end
		end

		-- Every one of them, shown or not. A hidden tab still holds its place in
		-- the chain, so anchoring only the visible ones leaves a gap the moment
		-- the player learns a profession and the ninth tab arrives.
		last = tab
		if not tab.IsShown or tab:IsShown() then shown = shown + 1 end
	end

	-- NO RAIL WITH NOTHING ON IT. A hairline down the side of a window with no
	-- schools behind it is a line dividing the content from nothing.
	rail:SetShown(shown > 0)
end

local function DressSpellBook(frame, store)
	-- The page number, which the client draws in near-black because it is
	-- printing it on parchment. On glass that is a page number you cannot read.
	local page = _G.SpellBookPageText
	if page then
		Roled(page, "pnSub")
		W.Color(page, Palette.c.textDim)

		-- And between the two arrows rather than off in the bottom corner: the
		-- corner it was in is where the book's tabs sit now.
		if page.ClearAllPoints then
			page:ClearAllPoints()
			page:SetPoint("CENTER", frame, "BOTTOM", 0, PAGE_TURNER_Y)
		end
		if page.SetJustifyH then page:SetJustifyH("CENTER") end
	end

	Reskin.PageTurn(_G.SpellBookPrevPageButton, "LEFT", store)
	Reskin.PageTurn(_G.SpellBookNextPageButton, "RIGHT", store)

	-- THE RANK SWITCH IS CONTENT, not chrome. It is a control over the list -
	-- the same thing an expand-all would be over a tree - so it belongs in the
	-- recess with the list. The client hangs it 38 below the frame, which is
	-- inside our header band, and it sat across the hairline.
	local ranks = _G.ShowAllSpellRanksCheckbox
	if ranks then
		Reskin.CheckBox(ranks, store)
		local label = _G.ShowAllSpellRanksCheckboxText
		if label then
			Roled(label, "pnBody")
			W.Color(label, Palette.c.textDim)
		end
		local body = frame.__aetherBody
		if body and ranks.ClearAllPoints then
			ranks:ClearAllPoints()
			ranks:SetPoint("TOPLEFT", body, "TOPLEFT",
				W.WELL_PAD, -W.WELL_PAD)
		end
	end

	DressSpellButtons(store)
	DressSideTabs(frame, store, "SpellBookSkillLineTab", SPELL_TABS)

	-- AND AGAIN WHENEVER THE CLIENT REBUILDS THAT COLUMN. Picking a school
	-- runs UpdateSkillLineTabs, which re-sets every icon and moves the check
	-- from one button to the next - so a mark drawn once at dress time stays
	-- on whichever school happened to be open when the window was first shown.
	if hooksecurefunc and not PN.__skillLineHook
		and frame.UpdateSkillLineTabs then
		PN.__skillLineHook = true
		hooksecurefunc(frame, "UpdateSkillLineTabs", function(self)
			if not PN.enabled or not self.__aetherArt then return end
			DressSideTabs(self, self.__aetherArt, "SpellBookSkillLineTab", SPELL_TABS)
		end)
	end

	-- No hook of its own on the client's rebuild of the BOOK tabs. Its update
	-- hides all three and shows the ones that apply, so the OnShow every hidden
	-- tab already carries answers it - and that is also what puts the label
	-- back in the middle, because enabling a tab is what moved it up.
	LayoutTabs(frame, store)
	InstallTabHooks()
end

-- ---------------------------------------------------------------------------
-- the talent tree
-- ---------------------------------------------------------------------------
--
-- Forty talent buttons on a scrolling parchment, with the tree's own branches
-- and arrows drawn over it, three tabs along the bottom and a points bar under
-- them. It shares the spellbook's side-tab column and the character sheet's
-- tab strip, so most of this is naming parts rather than new behaviour.
--
-- THE BRANCHES AND ARROWS STAY. PlayerTalentFrameBranch1..30 and Arrow1..30 are
-- regions of the scroll child and of the arrow frame, and they are the tree -
-- which way a talent depends on another is the only thing the layout says. A
-- strip of either frame would take them and leave forty unconnected icons.

local TALENT_BUTTONS = 40        -- MAX_NUM_TALENTS
local TALENT_SPECS   = 3         -- PlayerSpecTab1..3, all hidden on this flavour

-- Panes whose art comes off. The scroll frame carries the tree's parchment in
-- four pieces AND the stone trough its scroll bar runs in; the other three are
-- input borders and button borders around the points readings.
--
-- NOT PlayerTalentFrameScrollChildFrame and NOT PlayerTalentFrameArrowFrame.
-- The branches and arrows are regions of those two, and they are the tree.
local TALENT_PANES = {
	"PlayerTalentFrameScrollFrame", "PlayerTalentFrameStatusFrame",
	"PlayerTalentFramePointsBar", "PlayerTalentFramePreviewBar",
	"PlayerTalentFramePreviewBarFiller",
}

-- The rank chip in the corner of a talent. Blizzard draws a small stone plate
-- there with the number on it; ours is the same badge the tooltip's level chip
-- uses, with the client's own string still doing the counting on top of it.
local RANK_CHIP = 18

--- Which of the three states the client has just put a talent in.
--
--  Read off the SLOT's vertex colour rather than worked out again from
--  GetTalentInfo. The client has already decided this - it weighs the rank
--  against the maximum, whether the tier is unlocked, whether the prerequisites
--  are met and whether there is a point spare - and then says the answer in a
--  colour: green for "you can put a point here", gold for "this one is
--  finished", grey for neither. Re-deriving it would be a second set of rules
--  to keep in step with the client's, and they would disagree at the edges.
--
--  Classified by hue rather than matched exactly, because the exact triples are
--  Blizzard's to change and "greener than it is red" is the part that means
--  something.
local function TalentState(btn)
	local name = btn.GetName and btn:GetName()
	local slot = name and _G[name .. "Slot"]
	if not slot or not slot.GetVertexColor then return nil end

	local r, g, b = slot:GetVertexColor()
	if type(r) ~= "number" then return nil end

	local hi = math.max(r, g, b)
	local lo = math.min(r, g, b)
	if hi - lo < 0.1 then return nil end          -- grey: nothing to say
	if g > r then return "open" end
	return "full"
end

local function StyleTalent(btn)
	local state = TalentState(btn)

	if btn.SetEdgeColor then
		btn:SetEdgeColor(
			(state == "open" and Palette.c.talentOpen)
			or (state == "full" and Palette.c.talentFull)
			or Palette.c.glassEdge)
	end

	-- The client's own rank string, kept and re-roled. It counts; the chip
	-- behind it only has to be somewhere for it to sit.
	local rank = Reskin.Element(btn, "Rank")
	if rank and rank.SetText then
		Reskin.Font(rank, "pnBody")
		W.Color(rank, state == "full" and Palette.c.talentFull or Palette.c.text)
	end

	local chip = btn.__aetherRank
	if chip then
		chip:SetColors(Palette.c.glassStrong,
			(state == "full" and Palette.c.talentFull) or Palette.c.glassEdgeHi)
		-- Shown exactly when the client shows its own plate, which is its way of
		-- saying this talent has a rank worth reading.
		local border = Reskin.Element(btn, "RankBorder")
		chip:SetShown((not border) or border:IsShown())
	end
end

local function DressTalentButtons(store)
	for i = 1, TALENT_BUTTONS do
		local btn = _G["PlayerTalentFrameTalent" .. i]
		if btn then
			-- Same shape as a spell button: the icon is a region, the ring is
			-- the normal texture, and there is a third texture behind both - the
			-- Slot, which the client also uses to say what state the talent is
			-- in. Cleared like the rest; its colour is still readable.
			Reskin.IconButton(btn, store, { icon = Reskin.Element(btn, "IconTexture") })

			if not btn.__aetherRank then
				local chip = W.CreateBadge(btn, { size = RANK_CHIP })
				chip:SetPoint("CENTER", btn, "BOTTOMRIGHT", 0, 0)
				chip:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
				chip.label:Hide()          -- the client's own string sits on top
				btn.__aetherRank = chip
			end

			StyleTalent(btn)
		end
	end
end

--- Answer the client when it repaints the tree.
--
--  TalentFrame_Update runs on open, on every tab click and on every point
--  spent, and it re-sets the four background pieces from the spec's own art -
--  so the parchment we just took off comes straight back. It also re-colours
--  every Slot, which is where the states come from.
local function InstallTalentHooks(frame)
	if PN.__talentHooks or not hooksecurefunc or not _G.TalentFrame_Update then return end
	PN.__talentHooks = true

	hooksecurefunc("TalentFrame_Update", function()
		if not PN.enabled then return end
		local f = _G.PlayerTalentFrame
		local store = f and f.__aetherArt
		if not store then return end

		for _, name in ipairs(TALENT_PANES) do
			local pane = _G[name]
			if pane then Reskin.Strip(pane, store) end
		end
		for i = 1, TALENT_BUTTONS do
			local btn = _G["PlayerTalentFrameTalent" .. i]
			if btn then
				Reskin.ClearButton(btn)
				StyleTalent(btn)
			end
		end
	end)
end

local function DressTalents(frame, store)
	for _, name in ipairs(TALENT_PANES) do
		local pane = _G[name]
		if pane then Reskin.Strip(pane, store) end
	end

	-- The points bar's own reading, and the "N points spent in Beast Mastery"
	-- line above the tree.
	for _, name in ipairs({ "PlayerTalentFrameTalentPointsText",
	                        "PlayerTalentFrameSpentPointsText",
	                        "PlayerTalentFrameStatusText" }) do
		local fs = _G[name]
		if fs then
			Roled(fs, "pnSub")
			W.Color(fs, Palette.c.textDim)
		end
	end

	for _, name in ipairs({ "PlayerTalentFrameActivateButton",
	                        "PlayerTalentFrameResetButton",
	                        "PlayerTalentFrameLearnButton" }) do
		local btn = _G[name]
		if btn then
			Reskin.Button(btn, "pnBody")
			Reskin.Strip(btn, store)
		end
	end

	-- A second Close down in the corner of the tree, doing what the one in the
	-- window's corner already does. Hidden rather than cleared, exactly as the
	-- skills list's spare one is.
	local spare = _G.PlayerTalentFrameCancelButton
	if spare and spare.Hide and not spare.__aetherHidden then
		spare.__aetherHidden = spare:IsShown() and true or false
		spare:Hide()
	end

	local bar = _G.PlayerTalentFrameScrollFrameScrollBar
	if bar then Reskin.ScrollBar(bar, store) end

	DressTalentButtons(store)
	DressSideTabs(frame, store, "PlayerSpecTab", TALENT_SPECS)

	LayoutTabs(frame, store)
	InstallTabHooks()
	InstallTalentHooks(frame)
end

-- ---------------------------------------------------------------------------
-- guild and communities
-- ---------------------------------------------------------------------------
--
-- The one window here NOT built from Blizzard's source, because
-- Blizzard_Communities is not in the reference tree. It was read off the live
-- client instead, with `/aether panels dump CommunitiesFrame`, which is what
-- that command exists for.
--
-- So every name below is a parentKey observed on this build rather than one
-- read out of an XML file, and each is reached through Element - which answers
-- nil for a part this client does not have, so a build that renames something
-- loses that part's dressing and nothing else.
--
-- It is also a MODERN window, which makes it a different shape from the rest:
-- almost nothing has a global name, its panes are hidden until their tab is
-- picked, and its buttons are three-slice Left/Right/Middle rather than a
-- single normal texture.

-- The side tabs. Each keeps its picture in an Icon REGION - not as the normal
-- texture the spellbook's school tabs use - with a stone ring behind it.
local COMM_TABS = {
	"ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab",
}

-- Panes and the furniture in them. Stripped outright: none of these carries
-- anything but frame art, and what they hold is drawn by their own children.
local COMM_PANES = {
	"CommunitiesList", "MemberList", "ApplicantList", "Chat",
	"GuildBenefitsFrame", "GuildDetailsFrame", "CommunitiesControlFrame",
	"InvitationFrame", "TicketFrame", "GuildMemberDetailFrame",
}

-- Push buttons, dropdowns and the odd control, by the key their parent holds
-- them under. `where` is the pane to look inside, or nil for the window itself.
local COMM_BUTTONS = {
	{ nil, "InviteButton" }, { nil, "GuildLogButton" },
	{ nil, "AddToChatButton" },
	{ "CommunitiesControlFrame", "CommunitiesSettingsButton" },
	{ "CommunitiesControlFrame", "GuildControlButton" },
	{ "CommunitiesControlFrame", "GuildRecruitmentButton" },
	{ "GuildMemberDetailFrame", "RemoveButton" },
	{ "GuildMemberDetailFrame", "GroupInviteButton" },
	{ "InvitationFrame", "AcceptButton" }, { "InvitationFrame", "DeclineButton" },
	{ "TicketFrame", "AcceptButton" }, { "TicketFrame", "DeclineButton" },
}

local COMM_DROPDOWNS = {
	{ nil, "StreamDropdown" }, { nil, "GuildMemberListDropdown" },
	{ nil, "CommunityMemberListDropdown" }, { nil, "CommunitiesListDropdown" },
	{ "GuildMemberDetailFrame", "RankDropdown" },
}

-- The guild crest, drawn inside the window rather than hung off the corner.
local COMM_CREST, COMM_CREST_IN = 44, 8

--- Art off a whole subtree, for furniture with no picture anywhere in it.
--
--  A modern scroll bar is not a Slider with regions on it - it is a frame of
--  frames, with its track, its thumb and its two arrows each a child - so a
--  strip of the bar itself finds nothing and clears nothing. Nothing in one is
--  a picture, which is what makes sweeping the lot safe here and nowhere else.
local function StripTree(frame, store, depth)
	if not frame or depth < 0 then return end

	Reskin.Strip(frame, store)
	if frame.SetNormalTexture then Reskin.ClearButton(frame) end

	if not frame.GetChildren then return end
	for _, kid in ipairs({ frame:GetChildren() }) do
		StripTree(kid, store, depth - 1)
	end
end

--- A three-slice client button in one of our pills.
--
--  Left, Right and Middle rather than a normal texture, so ClearButton has
--  nothing to clear and the plate survives it. They are regions, so the strip
--  is what takes them.
local function DressWideButton(btn, store)
	if not btn then return end
	Reskin.ClearButton(btn)
	Reskin.Strip(btn, store)
	Reskin.Button(btn, "pnBody")
end

--- The list a dropdown opens, which is a window of its own.
--
--  Not a child of the dropdown and not built until the first click - the menu
--  manager pools these, so the same frame comes back later under a different
--  dropdown. Its art is two textures attached to the frame, an ornate atlas and
--  a black fill under it (MenuStyle1Mixin:Generate), so a strip takes both.
--
--  Its own store, because it belongs to no window: the frame outlives the
--  trainer that opened it.
--- The menu a dropdown opens. WE DO NOT TOUCH IT, and here is why.
--
--  THERE IS ONE OF THESE IN THE WHOLE INTERFACE. The menu system keeps a POOL
--  and hands the same frame to every dropdown, every right-click on a unit,
--  every context menu in the game. Dressing it is not dressing a window: it is
--  editing a frame that something else will be handed thirty seconds later,
--  and what we did to it stayed done.
--
--  Stripped and glassed, it came back as an empty black box - first on the
--  trade skill's filters, then on every context menu in the game, with no
--  error anywhere because nothing had gone wrong as far as Lua was concerned.
--
--  A pooled frame is not ours to keep. If these are ever to wear our glass it
--  has to be put back when the menu is released, and that is a mechanism
--  rather than a paint job - so until it is written, the client keeps its own.
local function DressMenu(menu)
	local _ = menu
end

-- The chevron on a dropdown. Ten against a control 24 tall, and eight in from
-- the right, because the client's is a 24px stone BUTTON drawn hard against the
-- edge - a picture of a control rather than a mark on one.
local DROP_CHEV, DROP_CHEV_IN = 10, 8

--- The two parts of a dropdown the client redraws for itself.
--
--  WowStyle1DropdownMixin:OnButtonStateChanged re-atlases the arrow and
--  re-colours the text on every hover, press and enable. Both have to be put
--  back after it, so they live here rather than inline in the dress.
local function DropdownMarks(btn)
	local arrow = Reskin.Element(btn, "Arrow")
	if arrow and arrow.SetTexture and Media and Media.texture then
		arrow:SetTexture(Media.texture.chevron)
		arrow:SetSize(DROP_CHEV, DROP_CHEV)
		if arrow.ClearAllPoints then
			arrow:ClearAllPoints()
			arrow:SetPoint("RIGHT", btn, "RIGHT", -DROP_CHEV_IN, 0)
		end
		local c = Palette.c.textDim
		if arrow.SetVertexColor then arrow:SetVertexColor(c[1], c[2], c[3]) end
		arrow:Show()
	end

	local text = Reskin.Element(btn, "Text")
	if text then W.Color(text, Palette.c.text) end
end

--- A dropdown: its stone holder off, our chevron for its arrow, text re-roled.
--
--  The arrow was kept and tinted once. That does not work: the atlas is a
--  blue-grey stone button, and a tint multiplies it rather than replacing it.
--  Chevron.tga points DOWN unrotated, which is the way a dropdown's arrow
--  points, so it goes on the client's own region and keeps the client's anchor.
local function DressDropdown(btn, store)
	if not btn then return end
	Reskin.ClearButton(btn)
	Reskin.Strip(btn, store)
	Reskin.Button(btn, "pnBody")

	DropdownMarks(btn)

	local text = Reskin.Element(btn, "Text")
	if text then Reskin.Font(text, "pnBody") end

	-- THE CLIENT REDRAWS BOTH ON EVERY STATE CHANGE, so ours go back after it
	-- rather than once here. Clicking the control was enough to get the stone
	-- arrow again.
	if hooksecurefunc and btn.OnButtonStateChanged and not btn.__aetherStateHook then
		btn.__aetherStateHook = true
		hooksecurefunc(btn, "OnButtonStateChanged", function(self)
			if PN.enabled then DropdownMarks(self) end
		end)
	end
	local label = Reskin.Element(btn, "Label")
	if label then
		Reskin.Font(label, "pnBody")
		W.Color(label, Palette.c.textDim)
	end

	-- The menu does not exist until this is clicked, so the answer goes on the
	-- opening. OpenMenu leaves the frame on the button as `menu`.
	if hooksecurefunc and btn.OpenMenu and not btn.__aetherMenuHook then
		btn.__aetherMenuHook = true
		hooksecurefunc(btn, "OpenMenu", function(self)
			if PN.enabled then DressMenu(self.menu) end
		end)
	end
end

local function DressCommunities(frame, store)
	for _, key in ipairs(COMM_TABS) do
		local tab = Reskin.Element(frame, key)
		if tab then
			-- The picture is a region called Icon, so it is named rather than
			-- assumed: IconButton takes the normal texture when it is not told,
			-- and on these that is empty.
			Reskin.IconButton(tab, store, { icon = Reskin.Element(tab, "Icon") })
		end
	end

	for _, key in ipairs(COMM_PANES) do
		local pane = Reskin.Element(frame, key)
		if pane then
			Reskin.Strip(pane, store)
			Reskin.Fonts(pane, "pnBody")

			-- The scroll bar goes SUBTREE. It is a frame of frames on this
			-- window - track, thumb and two arrows, each a child - so stripping
			-- the bar itself finds no regions and clears nothing, which is the
			-- stone bar still down the side of the list.
			StripTree(Reskin.Element(pane, "ScrollBar"), store, 3)

			local columns = Reskin.Element(pane, "ColumnDisplay")
			if columns then Reskin.Strip(columns, store) end

			local inset = Reskin.Element(pane, "InsetFrame")
			if inset then Reskin.Strip(inset, store) end
		end
	end

	-- THE CREST, INSIDE THE WINDOW. The portrait template hangs it off the
	-- top-left corner deliberately, to overlap a stone ring that framed it -
	-- the same trick the main menu's title plate plays. With the ring gone it is
	-- a disc floating outside the glass, so it comes in and is drawn smaller.
	--
	-- Its mask and the guild's tabard follow it. A mask left where the portrait
	-- used to be crops a circle out of empty air, and the crest is three
	-- textures stacked, not one.
	local overlay = Reskin.Element(frame, "PortraitOverlay")
	local crest = overlay and Reskin.Element(overlay, "Portrait")
	if crest and crest.ClearAllPoints then
		crest:ClearAllPoints()
		crest:SetSize(COMM_CREST, COMM_CREST)
		crest:SetPoint("TOPLEFT", frame, "TOPLEFT", COMM_CREST_IN, -COMM_CREST_IN)

		for _, key in ipairs({ "CircleMask", "TabardBackground", "TabardEmblem",
			"TabardBorder" }) do
			local part = Reskin.Element(overlay, key)
			if part and part.SetAllPoints then part:SetAllPoints(crest) end
		end
	end

	-- The big pane on the right, which is what you get when you are in no guild
	-- at all: a dark plate with the client's own art on it, under two named
	-- globals depending on which finder the build shows.
	for _, name in ipairs({ "ClubFinderGuildFinderFrame",
	                        "ClubFinderCommunityAndGuildFinderFrame" }) do
		local finder = _G[name]
		if finder then
			Reskin.Strip(finder, store)
			Reskin.Fonts(finder, "pnBody")

			for _, key in ipairs({ "DisabledFrame", "InsetFrame", "OptionsList" }) do
				local part = Reskin.Element(finder, key)
				if part then Reskin.Strip(part, store) end
			end
		end
	end

	-- The ornate frame around the community list, which is its own thing again:
	-- four corners and four bars in a separate overlay child.
	local list = Reskin.Element(frame, "CommunitiesList")
	if list then
		local filigree = Reskin.Element(list, "FilligreeOverlay")
		if filigree then Reskin.Strip(filigree, store) end
	end

	for _, entry in ipairs(COMM_BUTTONS) do
		local host = entry[1] and Reskin.Element(frame, entry[1]) or frame
		DressWideButton(host and Reskin.Element(host, entry[2]), store)
	end

	for _, entry in ipairs(COMM_DROPDOWNS) do
		local host = entry[1] and Reskin.Element(frame, entry[1]) or frame
		DressDropdown(host and Reskin.Element(host, entry[2]), store)
	end

	-- The roster's "show offline" box, and the corner control that shrinks the
	-- window to its chat pane.
	local roster = Reskin.Element(frame, "MemberList")
	if roster then
		local offline = Reskin.Element(roster, "ShowOfflineButton")
		if offline then Reskin.CheckBox(offline, store) end
	end

	local size = Reskin.Element(frame, "MaximizeMinimizeFrame")
	if size then
		for _, key in ipairs({ "MaximizeButton", "MinimizeButton" }) do
			local btn = Reskin.Element(size, key)
			if btn then Reskin.ClearButton(btn) end
		end
	end

	-- The chat pane's composer: three slices of stone around an edit box.
	local box = Reskin.Element(frame, "ChatEditBox")
	if box then Reskin.Strip(box, store) end

	-- A PANE ARRIVES WHEN ITS TAB IS PICKED, hidden until then and undressed
	-- with it. The four tabs are the only thing that changes which is showing,
	-- so that is where the answer goes - there is no global update function on
	-- this window to hook, and none we could name without its source.
	for _, key in ipairs(COMM_TABS) do
		local tab = Reskin.Element(frame, key)
		if tab and tab.HookScript and not tab.__aetherCommHook then
			tab.__aetherCommHook = true
			tab:HookScript("OnClick", function()
				if PN.enabled and frame.__aetherArt then
					DressCommunities(frame, frame.__aetherArt)
				end
			end)
		end
	end
end

-- ---------------------------------------------------------------------------
-- the windows an NPC opens
-- ---------------------------------------------------------------------------
--
-- A vendor, a quest giver and anyone you can talk to. Three windows built on
-- two different templates, and what they have in common is rows: a list of
-- things, each with an icon, a name and sometimes a price.
--
-- The icons are the thing to be careful with, as ever. A merchant row keeps
-- the item's picture on a button inside it, and a gossip row keeps a bullet -
-- or a quest mark - as a region of the row itself. Both are what the player is
-- reading; neither is chrome.

local MERCHANT_ROWS = 12        -- MERCHANT_ITEMS_PER_PAGE
local QUEST_ITEMS   = 6         -- MAX_REQUIRED_ITEMS

--- One of a vendor's rows: the empty-slot art and the label plate off, the
--  item's own button dressed as a cell, and the name and price re-roled.
local function DressMerchantRow(row, store)
	if not row then return end

	-- The row's own art: a 64px empty-slot disc behind the icon and the stone
	-- label plate beside it. Both are regions OF THE ROW, and the item's
	-- picture is not - it lives on the button inside, which is what makes
	-- stripping the row safe here.
	Reskin.Strip(row, store)

	local button = Reskin.Element(row, "ItemButton")
	if button then Reskin.Slot(button) end

	local name = Reskin.Element(row, "Name")
	if name then
		Reskin.Font(name, "pnBody")
		W.Color(name, Palette.c.text)
	end

	-- The price, which is its own frame of coin icons and numbers.
	local money = Reskin.Element(row, "MoneyFrame")
	if money then Reskin.Fonts(money, "pnBody", 2) end
end

local function DressMerchant(frame, store)
	for i = 1, MERCHANT_ROWS do
		DressMerchantRow(_G["MerchantItem" .. i], store)
	end
	DressMerchantRow(_G.MerchantBuyBackItem, store)

	-- Your purse, along the bottom, in three pieces of stone.
	for _, name in ipairs({ "MerchantMoneyInset", "MerchantMoneyBg",
	                        "MerchantMoneyFrame", "MerchantExtraCurrencyInset",
	                        "MerchantExtraCurrencyBg" }) do
		local part = _G[name]
		if part then
			Reskin.Strip(part, store)
			Reskin.Fonts(part, "pnBody", 2)
		end
	end

	-- REPAIR KEEPS EVERY REGION IT HAS. Its anvil is not the normal texture and
	-- it is not called anything we could ask for - MerchantRepairAllIcon on one
	-- button and nameless on the other - and it is cropped out of a shared sheet
	-- by texcoords, so a cell would re-crop it to the wrong part of that sheet.
	-- Dressing these as icon buttons cleared the anvils and left two empty
	-- squares. So: our surface behind them, and nothing else touched.
	for _, name in ipairs({ "MerchantRepairAllButton", "MerchantRepairItemButton",
	                        "MerchantGuildBankRepairButton" }) do
		local btn = _G[name]
		if btn then W.SkinButton(btn, {}) end
	end

	local repairLabel = _G.MerchantRepairText
	if repairLabel then
		Reskin.Font(repairLabel, "pnBody", Palette.c.text)
		W.Color(repairLabel, Palette.c.textDim)
	end

	-- The page turner says "Prev" and "Next" in words of its own, so it wants a
	-- pill rather than one of our marks - a glyph as well was a chevron sitting
	-- beside a word that already said the same thing.
	for _, name in ipairs({ "MerchantPrevPageButton", "MerchantNextPageButton" }) do
		local btn = _G[name]
		if btn then
			Reskin.ClearButton(btn)
			Reskin.Strip(btn, store)
			-- BY WALKING THE BUTTON, not by asking for $parentText. The client's
			-- label on these is a plain FontString region with no name and no
			-- ButtonText, so both of the usual ways to reach it answer nil and
			-- the restyle quietly did nothing at all - which is a page turner
			-- still in the client's gold.
			Reskin.Fonts(btn, "pnBody", 0, Palette.c.text)
			for _, region in ipairs({ btn:GetRegions() }) do
				if region.GetObjectType and region:GetObjectType() == "FontString" then
					W.Color(region, Palette.c.text)
				end
			end
		end
	end

	local page = _G.MerchantPageText
	if page then
		Roled(page, "pnSub")
		W.Color(page, Palette.c.textDim)
	end

	-- WHO YOU ARE BUYING FROM is this window's title, named as such in the
	-- panel list - so the shell has already roled and placed it. It used to be
	-- done here instead, in body type at a body size and left wherever the
	-- client's portrait art had put it, which is the fourth place this file
	-- was setting a title before the header band took the job.

	LayoutTabs(frame, store)
	InstallTabHooks()
end

--- The quest giver: four panels of the same window, one shown at a time.
local QUEST_PANES = {
	"QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel",
	"QuestFrameGreetingPanel",
	"QuestDetailScrollFrame", "QuestProgressScrollFrame",
	"QuestRewardScrollFrame", "QuestGreetingScrollFrame",
	"QuestProgressRequiredMoneyFrame",
}

local QUEST_BUTTONS = {
	"QuestFrameAcceptButton", "QuestFrameDeclineButton",
	"QuestFrameCompleteButton", "QuestFrameCompleteQuestButton",
	"QuestFrameGoodbyeButton", "QuestFrameCancelButton",
	"QuestFrameGreetingGoodbyeButton",
}

-- MAX_NUM_QUESTS in the client's own source, and a stop rather than a count:
-- the buttons above the number an NPC is offering are hidden, not absent.
local QUEST_TITLE_CAP = 25

--- The greeting: an NPC with more than one quest, listed under two headings.
--
--  ITS OWN DRESSER BECAUSE IT IS REDRAWN UNDER US. QuestFrameGreetingPanel_OnShow
--  is not only an OnShow - QuestFrame re-runs it on QUEST_LOG_UPDATE whenever
--  this panel is up, which is what happens the moment you accept one of the
--  quests on it. And it re-runs the whole thing:
--
--    QuestFrame_SetMaterial   puts the parchment back on the panel
--    QuestFrame_SetTextColor  puts the near-black back in the greeting
--    SetTitleTextColor        puts it back in both headings
--    SetFormattedText         re-embeds |cff000000 in every quest title
--    HorizontalBreak:Show     brings back the gold swirl between the sections
--
--  So accepting the first of three quests handed back a window with our glass,
--  our band and our well round a page of the client's own art in the client's
--  own near-black ink - which read as the interior never having been dressed
--  at all, and was in fact the interior being dressed and then overwritten.
local function DressQuestGreeting(store)
	local panel = _G.QuestFrameGreetingPanel
	if not panel then return end

	-- The parchment, which SetMaterial re-applies every time.
	Reskin.Strip(panel, store)

	-- AND THE SCROLL CHILD, which is where the page's art actually lives -
	-- including QuestGreetingFrameHorizontalBreak, the gold swirl between
	-- Current Quests and Available Quests. A sweep of the PANEL never reached
	-- it, and the client shows it again whenever there is at least one active
	-- quest, which is exactly the case that produced this. Our glass has one
	-- language for a divider and it is the hairline; filigree is the client's.
	local page = _G.QuestGreetingScrollChildFrame
	if page then Reskin.Strip(page, store) end

	for _, name in ipairs({ "GreetingText", "CurrentQuestsText",
		"AvailableQuestsText" }) do
		local fs = _G[name]
		if fs then Reskin.Font(fs, "pnBody", Palette.c.text) end
	end

	-- EVERY TITLE IN THE LIST. The black is not the string's COLOUR - the
	-- client formats each one through NORMAL_QUEST_DISPLAY, which is
	-- |cff000000%s|r, so the escape is inside the text and SetTextColor cannot
	-- reach it. Reskin.Font rewrites the escape; this is the same fault the
	-- gossip list has, one window along.
	for i = 1, QUEST_TITLE_CAP do
		local btn = _G["QuestTitleButton" .. i]
		if not btn then break end
		if btn.IsShown and btn:IsShown() then
			-- Its own art off but NOT its icon: the exclamation mark and the
			-- question mark are the only thing saying which quests are yours
			-- already and which are on offer.
			Reskin.ClearButton(btn)
			Reskin.StripExcept(btn, store, { _G["QuestTitleButton" .. i .. "QuestIcon"] })
			Reskin.Fonts(btn, "pnBody", 0, Palette.c.text)
		end
	end
end

local function DressQuest(frame, store)
	for _, name in ipairs(QUEST_PANES) do
		local pane = _G[name]
		if pane then
			Reskin.Strip(pane, store)
			-- LIFTED, because a quest is printed on paper. Its text is near
			-- black by design and on glass it is a dark smudge. Only the dark
			-- is lifted - the gold headings and the reward names mean what they
			-- say and come through untouched.
			Reskin.Fonts(pane, "pnBody", 2, Palette.c.text)
		end
	end

	-- The stone plate behind the name comes off, but the name itself is NOT
	-- swept with the panels: the sweep re-roles every string it finds to body
	-- type, and the band had already put this one in title type. Interiors run
	-- last, so the sweep won.
	local who = _G.QuestNpcNameFrame
	if who then Reskin.Strip(who, store) end

	-- WHO YOU ARE TALKING TO is this window's title, named as such in the panel
	-- list - so the band has already roled it and put it in the middle. It was
	-- done here instead, and by a lookup that never found the string: the name
	-- is QuestFrameNpcNameText and the frame it hangs off is QuestNpcNameFrame,
	-- so "frame name + Text" asked for QuestNpcNameFrameText. The quest giver
	-- has had no title of ours on it at all.

	for _, name in ipairs(QUEST_BUTTONS) do
		local btn = _G[name]
		if btn then
			Reskin.Button(btn, "pnBody")
			Reskin.Strip(btn, store)
		end
	end

	-- What the quest wants from you. NOT a cell: these are wide ROWS - an icon
	-- at one end and the item's name beside it - and a cell sizes its picture
	-- to the whole button, so the icon came out stretched the width of the row.
	--
	-- So the row's own art comes off and the icon is left exactly where the
	-- client put it, at the size the client drew it.
	for i = 1, QUEST_ITEMS do
		local item = _G["QuestProgressItem" .. i]
		if item then
			Reskin.ClearButton(item)
			Reskin.StripExcept(item, store, { "IconTexture" })
			Reskin.Fonts(item, "pnBody", 1, Palette.c.text)
		end
	end

	for _, name in ipairs({ "QuestDetailScrollFrameScrollBar",
	                        "QuestProgressScrollFrameScrollBar",
	                        "QuestRewardScrollFrameScrollBar",
	                        "QuestGreetingScrollFrameScrollBar" }) do
		local bar = _G[name]
		if bar then Reskin.ScrollBar(bar, store) end
	end

	DressQuestGreeting(store)

	-- AND AGAIN EVERY TIME THE CLIENT REDRAWS IT. Once is not enough here and
	-- the event that proves it is QUEST_LOG_UPDATE: accept one of an NPC's
	-- three quests and QuestFrame re-runs the whole OnShow, which repaints the
	-- parchment, re-inks the greeting and both headings, re-embeds the black in
	-- every title and shows the swirl again.
	--
	-- A GLOBAL FUNCTION, not a method, so it is hooked by name.
	if hooksecurefunc and not PN.__questGreetHook
		and _G.QuestFrameGreetingPanel_OnShow then
		PN.__questGreetHook = true
		hooksecurefunc("QuestFrameGreetingPanel_OnShow", function()
			if PN.enabled then DressQuestGreeting(store) end
		end)
	end
end

--- Anyone you can talk to. Built on the portrait template, so the shell is
--  already handled; what is left is the parchment behind the words and the
--  list of things to say.
--- Every row the gossip list is showing right now.
--
--  POOLED AND REBUILT. The list is a scroll box: its rows are acquired from a
--  pool when the data provider changes, which happens on open AND on every
--  option you pick. A row dressed once is a row that is right until you click
--  something, and the rows you have not scrolled to have never existed.
--
--  Swept whole rather than by shape. A row is an option, a quest or the NPC's
--  own words, and naming the string on each meant a quest title - which is not
--  reachable through GetFontString - kept our lettering from the first pass and
--  got its parchment ink back on every refresh.
local function GossipBox(frame)
	local panel = Reskin.Element(frame, "GreetingPanel")
	return panel and Reskin.Element(panel, "ScrollBox") or nil
end

local function DressGossipRows(frame)
	local box = GossipBox(frame)
	if not box then return end

	local function lift(row)
		if row then Reskin.Fonts(row, "pnBody", 0, Palette.c.text) end
	end

	-- ITS OWN ITERATOR, where it has one. ForEachFrame walks what the box is
	-- SHOWING at the moment you ask; GetFrames hands back a list, and a list
	-- obtained a moment too early is a list of the rows that were there before
	-- the rebuild. Both are on ScrollBoxListMixin, and only one of them cannot
	-- be stale.
	if box.ForEachFrame then
		if pcall(box.ForEachFrame, box, lift) then return end
	end
	if box.GetFrames then
		local ok, rows = pcall(box.GetFrames, box)
		if ok and rows then
			for _, row in ipairs(rows) do lift(row) end
		end
	end
end

local function DressGossip(frame, store)
	local panel = Reskin.Element(frame, "GreetingPanel")
	if panel then
		Reskin.Strip(panel, store)
		-- Lifted, for the reason the quest giver's text is: this is printed on
		-- the same paper and is the same near-black.
		Reskin.Fonts(panel, "pnBody", 0, Palette.c.text)

		local goodbye = Reskin.Element(panel, "GoodbyeButton")
		if goodbye then
			Reskin.Button(goodbye, "pnBody")
			Reskin.Strip(goodbye, store)
		end

		-- A modern scroll bar again: a frame of frames, so the bar itself has
		-- no regions to take.
		StripTree(Reskin.Element(panel, "ScrollBar"), store, 3)
	end

	local rep = Reskin.Element(frame, "FriendshipStatusBar")
	if rep then Reskin.StatusBar(rep, store) end

	DressGossipRows(frame)

	-- THE LIST IS REBUILT UNDER US, and not only when you pick something. The
	-- client re-runs it on QUEST_LOG_UPDATE whenever the NPC has an active
	-- quest - so accepting the first of three redraws the window into Current
	-- Quests, a divider and Available Quests, all in pooled rows nobody has
	-- lifted, and every word in it comes back in the near-black gossip is
	-- printed in.
	--
	-- ON THE SCROLL BOX'S OWN Update, not the window's. This hooked
	-- GossipFrame:Update and GossipFrame:UpdateScrollBox and then re-swept a
	-- second time from a zero-length timer, because a scroll box acquires its
	-- rows during LAYOUT - after the window's Update has returned - and a sweep
	-- from inside that hook reads the set that was there before. The timer was
	-- a guess at when layout would have happened, which is why it looked
	-- intermittent: whether a row was lifted depended on whether the pool
	-- happened to hand back one that already had been.
	--
	-- ScrollBoxListMixin:Update runs on the box itself, after its own layout,
	-- and there is nothing to guess. Found in ElvUI's gossip skin, which hooks
	-- exactly this - the symbol was the thing worth having, and it cost a look
	-- rather than another round of timing experiments.
	local box = GossipBox(frame)
	if hooksecurefunc and box and box.Update and not box.__aetherGossipHook then
		box.__aetherGossipHook = true
		hooksecurefunc(box, "Update", function()
			if PN.enabled then DressGossipRows(frame) end
		end)
		PN.__gossipHook = true
	end
end

-- ---------------------------------------------------------------------------
-- the trainer
-- ---------------------------------------------------------------------------
--
-- A list of what you can learn, a pane describing the one you picked, and a
-- price. Its rows are the character sheet's skill headers again - a button
-- whose NORMAL TEXTURE is the plus or minus - which is why the treatment for
-- those is a shared one and not something the character sheet owns.
--
-- What is different here is that the same eleven buttons are BOTH kinds. The
-- client fills them from one list: a header gets a plus or a minus, a skill
-- gets ClearNormalTexture and an indented name. So which a row is has to be
-- read on every refresh rather than decided once.

-- A stop, not a count. CLASS_TRAINER_SKILLS_DISPLAYED is 11 in Blizzard's own
-- source and this build draws more than that, so the number is asked of the
-- client by walking the buttons until they run out.
local TRAINER_ROW_CAP = 200

local TRAINER_PANES = {
	"ClassTrainerListScrollFrame", "ClassTrainerDetailScrollFrame",
	"ClassTrainerDetailScrollChildFrame", "ClassTrainerMoneyFrame",
	"ClassTrainerDetailMoneyFrame", "ClassTrainerExpandButtonFrame",
}

local TRAINER_TEXT = {
	"ClassTrainerNameText", "ClassTrainerGreetingText", "ClassTrainerSkillName",
	"ClassTrainerSubSkillName", "ClassTrainerSkillRequirements",
	"ClassTrainerCostLabel", "ClassTrainerSkillDescription",
}

--- A row is a header if the client left a plus or a minus on it.
--
--  The fallback only. This client resolves a texture path to a file ID, so
--  GetTexture answers a number and there is nothing to match - which is why
--  every row kept Blizzard's mark. Kept for a client that still answers with
--  the path, and for the harness.
local function TrainerRowMark(btn)
	local tex = btn.GetNormalTexture and btn:GetNormalTexture()
	local path = tex and tex.GetTexture and tex:GetTexture()
	if type(path) ~= "string" then return nil end
	if path:find("MinusButton", 1, true) then return "expanded" end
	if path:find("PlusButton", 1, true) then return "collapsed" end
	return nil
end

--- What the client says a row is, which beats guessing from its art.
--
--  The button carries the service index as its ID, so the same call the client
--  fills the row from answers both questions. Reused every refresh because
--  these buttons are both kinds: a row that was a heading a moment ago is a
--  spell now.
local function TrainerRowService(btn)
	local id = btn.GetID and btn:GetID()
	if not id or id <= 0 or not GetTrainerServiceInfo then return nil end
	local _, _, serviceType, isExpanded = GetTrainerServiceInfo(id)
	if not serviceType then return nil end
	return serviceType, isExpanded
end

local function DressTrainerRows()
	for i = 1, TRAINER_ROW_CAP do
		local btn = _G["ClassTrainerSkill" .. i]
		if not btn then break end

		local serviceType, isExpanded = TrainerRowService(btn)
		local header
		if serviceType then
			header = (serviceType == "header")
		else
			local mark = TrainerRowMark(btn)
			header, isExpanded = mark ~= nil, mark == "expanded"
		end

		if header then
			btn.isExpanded = isExpanded or nil
			Reskin.Collapse(btn)
			if btn.__aetherGlyph then btn.__aetherGlyph:Show() end
		else
			-- It is a spell this time round, not a heading. The client clears
			-- its own NORMAL texture here; ours has to go with it - and the
			-- template's other three states do not go with it, so a spell row
			-- still lit up with Blizzard's plus button when you hovered it.
			if btn.__aetherGlyph then btn.__aetherGlyph:Hide() end
			Reskin.ClearButton(btn)
		end

		local label = btn.GetFontString and btn:GetFontString()
		if label then Reskin.Font(label, "pnBody", Palette.c.text) end

		local sub = _G["ClassTrainerSkill" .. i .. "SubText"]
		if sub then Reskin.Font(sub, "pnBody") end
	end

	-- "All", which expands and collapses the lot. It keeps its own flag rather
	-- than a service index: 1 when collapsed, nil when not.
	local all = _G.ClassTrainerCollapseAllButton
	if all then
		all.isExpanded = (not all.collapsed) or nil
		Reskin.Collapse(all)
		local label = all.GetFontString and all:GetFontString()
		if label then Reskin.Font(label, "pnBody", Palette.c.text) end
	end
end

local function DressTrainer(frame, store)
	-- ITS TWO LISTS, IN WELLS. Every list in this interface sits in a recess;
	-- the trainer's skills and the detail beside them floated on bare glass
	-- with nothing marking where either began or ended.
	for _, name in ipairs({ "ClassTrainerListScrollFrame",
		"ClassTrainerDetailScrollFrame" }) do
		Reskin.ScrollFrame(_G[name], store)
	end

	for _, name in ipairs(TRAINER_PANES) do
		local pane = _G[name]
		if pane then
			Reskin.Strip(pane, store)
			Reskin.Fonts(pane, "pnBody", 2, Palette.c.text)
		end
	end

	-- WHICH ROW YOU ARE ON. The client keeps one highlight frame and slides it
	-- onto whatever you picked, with its blue listbox slice drawn on it. This
	-- was in the list of panes to strip, which left the window with nothing at
	-- all saying which skill was selected.
	Reskin.RowMark(_G.ClassTrainerSkillHighlightFrame, store)

	-- The little stone tab the All control hangs off, the same one the
	-- character sheet's skill list has.
	for _, name in ipairs({ "ClassTrainerExpandTabLeft", "ClassTrainerExpandTabMiddle",
	                        "ClassTrainerExpandTabRight" }) do
		local art = _G[name]
		if art and art.SetTexture then art:SetTexture(0) end
	end

	-- Who you are learning from, what they say, and the description of the
	-- thing you picked. All printed for parchment, so all lifted.
	for _, name in ipairs(TRAINER_TEXT) do
		local fs = _G[name]
		if fs then Reskin.Font(fs, "pnBody", Palette.c.text) end
	end

	local who = _G.ClassTrainerNameText
	if who then
		Roled(who, "pnSub")
		W.Color(who, Palette.c.text)
	end

	-- The spell you are being sold, in a cell. This one IS square - 37 by 37 -
	-- unlike the quest giver's rows.
	local icon = _G.ClassTrainerSkillIcon
	if icon then Reskin.Slot(icon) end

	-- Train, Close and TRAIN ALL. The third has no name of its own - it is an
	-- anonymous child whose label is ClassTrainerFrameText - so all three are
	-- found by shape instead. They are the client's three-slice push button and
	-- nothing else on this window carries Left, Middle and Right.
	--
	-- AND HANDED TO THE FOOTER STRIP, because a nameless button cannot be
	-- listed in the panel entry the way every other window's actions are. The
	-- client anchors all three 420 down from the window's TOPLEFT, in a frame
	-- that is no longer that tall, so they sat across the foot of both recesses.
	local acts = {}
	for _, kid in ipairs({ frame:GetChildren() }) do
		if kid.GetObjectType and kid:GetObjectType() == "Button"
			and Reskin.Element(kid, "Left")
			and Reskin.Element(kid, "Middle")
			and Reskin.Element(kid, "Right") then
			DressWideButton(kid, store)
			-- Train All carries its label twice, so the label is re-roled by
			-- sweeping the button rather than by asking for GetFontString.
			Reskin.Fonts(kid, "pnBody")
			acts[#acts + 1] = kid
		end
	end
	frame.__aetherActions = acts

	-- Interiors run LAST, so the strip was laid out before these were found.
	PN.LayoutFooter(frame, PN.ENTRY and PN.ENTRY["ClassTrainerFrame"])

	for _, name in ipairs({ "ClassTrainerListScrollFrameScrollBar",
	                        "ClassTrainerDetailScrollFrameScrollBar" }) do
		local bar = _G[name]
		if bar then Reskin.ScrollBar(bar, store) end
	end

	-- The filter, which is the same modern dropdown Communities uses: a stone
	-- holder, an arrow and a label, all regions of the button.
	local filter = Reskin.Element(frame, "FilterDropdown")
	DressDropdown(filter, store)

	-- AND PULLED INSIDE THE GLASS. The client hangs it 44 in from the frame's
	-- right edge, which is inside the parchment's margin and outside ours - the
	-- window is 714 wide and our panel stops 28 short of that. Only the across
	-- is changed; the client's height is where it belongs, level with the purse.
	if filter and filter.ClearAllPoints then
		local ins = (PN.ENTRY and PN.ENTRY.ClassTrainerFrame or {}).insets or {}
		filter:ClearAllPoints()
		filter:SetPoint("TOPRIGHT", frame, "TOPRIGHT", (ins[3] or 0) - 6, -67)
	end

	DressTrainerRows()

	-- The list is refilled every time you expand a heading, pick a skill or
	-- learn one - and every refresh puts the client's own plus and minus back.
	if hooksecurefunc and _G.ClassTrainerFrame_Update and not PN.__trainerHook then
		PN.__trainerHook = true
		hooksecurefunc("ClassTrainerFrame_Update", function()
			if PN.enabled then DressTrainerRows() end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- the flight master
-- ---------------------------------------------------------------------------
--
-- Almost nothing to do, because the map is the window - the entry's `keep`
-- spares it and the nodes are child buttons the sweep never reaches. What is
-- left is the portrait ring's picture and the flight master's name.

local function DressTaxi(frame, store)
	-- The portrait sat in a stone ring in the corner. The ring went with the
	-- parchment; the face has nothing to sit in.
	local portrait = _G.TaxiPortrait
	if portrait and portrait.SetTexture then portrait:SetTexture(0) end

	local who = _G.TaxiMerchant
	if who then
		Roled(who, "pnSub")
		W.Color(who, Palette.c.text)
	end
end


--- The game's own Options window: the shell our settings page lives inside.
--
--  Skinning the page and leaving the window around it in stone is the one
--  place a player sees both at once, side by side, and it made ours look like
--  the thing that did not belong.
--
--  Every part is a parentKey off the panel, which is what makes this a list
--  rather than a hunt: GameTab and AddOnsTab, CloseButton and ApplyButton,
--  CategoryList, and the SearchBox.
--- Every element a WowScrollBox has handed out, whatever it is holding.
--
--  POOLED AND REBUILT. A scroll box acquires its rows as you scroll and hands
--  them back when they leave, so anything dressed once is dressed for whatever
--  happened to be on screen at the time. Asked again on every pass, and the
--  dressers guard themselves.
-- The Options window's two tabs. MinimalTabTemplate sizes itself to its own
-- plate, and the plate is the first thing off - so both numbers are ours now
-- or one tab is the width of the word Game and the other of the word AddOns.
local SETTINGS_TAB_H   = 30
local SETTINGS_TAB_W   = 104
local SETTINGS_TAB_PAD = 16

local function ScrollBoxFrames(box)
	if not box then return {} end
	if box.GetFrames then
		local ok, frames = pcall(box.GetFrames, box)
		if ok and type(frames) == "table" then return frames end
	end
	if box.GetChildren then return { box:GetChildren() } end
	return {}
end

--- One heading in the category list - Gameplay, Accessibility, System.
--
--  Its own template with its own Background texture and GameFontHighlightMedium
--  on the label, so nothing the shell does reaches either: the sweep walks the
--  window's regions and these are regions of a pooled child three frames down.
local function DressCategoryHeader(el)
	if not el or el.__aetherHeader then return end
	el.__aetherHeader = true

	if el.Background then
		-- Not hidden. It is the only thing separating one group of rows from
		-- the next, so it becomes our own rule instead of somebody else's
		-- gold-edged plate.
		el.Background:SetTexture(A.Media.texture.flat)
		W.Tint(el.Background, A.Palette.c.glassEdge, 0.35)
	end
	if el.Label then
		Reskin.Font(el.Label, "qlZone")
		W.Color(el.Label, A.Palette.c.accent)
	end
end

--- One row in the category list.
local function DressCategoryRow(el)
	if not el then return end

	if not el.__aetherRow then
		el.__aetherRow = true
		Reskin.ClearButton(el)
	end

	-- THE SELECTION, ours. Blizzard's is a gold-bordered plate on the row's
	-- own Texture; ours is the interface's selection colour behind the words.
	if el.Texture then
		el.Texture:SetTexture(A.Media.texture.flat)
		W.Tint(el.Texture, A.Palette.c.rowSel)
	end
	if el.Label then
		Reskin.Font(el.Label, "qlRow")
		W.Color(el.Label, A.Palette.c.text)
	end

	-- THE EXPAND TOGGLE. Blizzard draws a plus and a minus out of
	-- Interface/Buttons - two plates with a gold rim on them - and this
	-- interface has one glyph for open-and-shut already: the chevron the
	-- Toolbox rail, the dropdowns and the quest log all use.
	local toggle = el.Toggle
	if toggle then
		Reskin.ClearButton(toggle)
		if not toggle.__aetherGlyph then
			local g = toggle:CreateTexture(nil, "OVERLAY")
			g:SetTexture(A.Media.texture.chevron)
			g:SetSize(9, 9)
			g:SetPoint("CENTER", toggle, "CENTER", 0, 0)
			toggle.__aetherGlyph = g
		end
		W.Tint(toggle.__aetherGlyph, A.Palette.c.textDim)
	end
end

--- Every ordinary button inside the settings pages - Defaults, and whatever
--  else a page puts on itself.
--
--  BY WHAT IT IS, not by name. The pages are built from data and their buttons
--  are named nothing at all, so the only question that can be asked is whether
--  a child is a button with a label on it.
local function DressPanelButtons(root, depth)
	if not root or not root.GetChildren or (depth or 0) > 4 then return end
	for _, child in ipairs({ root:GetChildren() }) do
		if child.GetObjectType and child:GetObjectType() == "Button"
			and child.GetFontString and child:GetFontString()
			and not child.__aetherSkin then
			-- UIPanelButtonTemplate draws with Left, Middle and Right
			-- BACKGROUND regions rather than state textures, which is why a
			-- plain ClearButton leaves the red plate exactly where it was.
			-- Reskin.Button knows that.
			Reskin.Button(child, "pnBody")
		end
		DressPanelButtons(child, (depth or 0) + 1)
	end
end

local function DressSettings(frame, store)
	-- The two tabs. MinimalTabTemplate, which sizes itself to its label - so
	-- the plate comes off and the SIZE has to be put back by hand, or one tab
	-- is the width of the word Game and the other of the word AddOns.
	-- ITS TWO TABS, on the same rail as every other tabbed surface here. They
	-- sit at the TOP of this window, so the line and the mark are on the
	-- bottom - the edge facing the settings they switch between.
	--
	-- This window says which one is open through SelectableButtonMixin rather
	-- than by disabling it the way the older panels do, and it moves the label
	-- and swaps the font object on every selection - so the state is read from
	-- IsSelected and re-asserted from a hook on OnSelected, or the first click
	-- hands the word back to Blizzard's own font.
	local first
	for _, key in ipairs({ "GameTab", "AddOnsTab" }) do
		local tab = frame[key]
		if tab then
			Reskin.Tab(tab, store, "pnBody", { edge = "TOP" })
			tab:SetHeight(SETTINGS_TAB_H)
			local label = tab.Text or (tab.GetFontString and tab:GetFontString())
			local wide = label and label.GetStringWidth
				and label:GetStringWidth() or 0
			tab:SetWidth(math.max(SETTINGS_TAB_W, wide + SETTINGS_TAB_PAD * 2))

			W.TabState(tab, tab.IsSelected and tab:IsSelected() or false, false)
			if hooksecurefunc and tab.OnSelected and not tab.__aetherSelHook then
				tab.__aetherSelHook = true
				hooksecurefunc(tab, "OnSelected", function(self, on)
					if not PN.enabled then return end
					local lb = self.Text
						or (self.GetFontString and self:GetFontString())
					if lb then
						Reskin.Font(lb, "pnBody")
						lb:ClearAllPoints()
						lb:SetPoint("CENTER", self, "CENTER", 0, 0)
					end
					W.TabState(self, on and true or false, false)
				end)
			end

			first = first or tab
		end
	end

	-- The rail under them, spanning the window and sitting on the row.
	if first then
		local rail = W.TabRail(frame, "TOP")
		rail:ClearAllPoints()
		rail:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 0)
		rail:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SETTINGS_TAB_PAD, 0)
		rail:SetHeight(SETTINGS_TAB_H)
	end

	-- The buttons along the bottom. CloseButton here is the one that says
	-- Close, not the X - that is ClosePanelButton, and the entry says so.
	for _, key in ipairs({ "CloseButton", "ApplyButton" }) do
		local btn = frame[key]
		if btn then Reskin.Button(btn, "pnBody") end
	end

	-- The category list down the left, and the search box above it. Both are
	-- frames of their own with their own art, so the shell strip never
	-- reached either.
	local list = frame.CategoryList
	if list then
		Reskin.Strip(list, store)
		if list.ScrollBox then Reskin.Strip(list.ScrollBox, store) end
		local bar = list.ScrollBar or (list.ScrollBox and list.ScrollBox.ScrollBar)
		if bar then
			bar.__aetherStore = bar.__aetherStore or {}
			Reskin.ScrollBar(bar, bar.__aetherStore)
		end

		-- THE ROWS AND THE HEADINGS, which are pooled elements inside the
		-- scroll box rather than children of anything the sweep walks.
		for _, el in ipairs(ScrollBoxFrames(list.ScrollBox)) do
			if el.Toggle ~= nil or el.Label and el.Texture then
				DressCategoryRow(el)
			elseif el.Background and el.Label then
				DressCategoryHeader(el)
			end
		end
	end

	local search = frame.SearchBox
	if search then
		Reskin.Strip(search, store)
		Reskin.Font(search, "pnBody")
		Reskin.Well(search, { inset = { 0, 0, 0, 0 } })
	end

	-- The panel that holds whichever page is open. Its own frame, its own art,
	-- its own scroll bar, and every button a page puts on itself.
	local container = frame.Container
	if container then
		Reskin.Strip(container, store)
		local sl = container.SettingsList
		if sl then
			sl.__aetherStore = sl.__aetherStore or {}
			Reskin.Strip(sl, sl.__aetherStore)
			if sl.Header then
				sl.Header.__aetherStore = sl.Header.__aetherStore or {}
				Reskin.Strip(sl.Header, sl.Header.__aetherStore)
				if sl.Header.Title then
					Reskin.Font(sl.Header.Title, "qlHeading")
					W.Color(sl.Header.Title, A.Palette.c.text)
				end
			end
			local sbar = sl.ScrollBar or (sl.ScrollBox and sl.ScrollBox.ScrollBar)
			if sbar then
				sbar.__aetherStore = sbar.__aetherStore or {}
				Reskin.ScrollBar(sbar, sbar.__aetherStore)
			end
		end
		DressPanelButtons(container, 0)
	end
end
--- The postbox: two panes behind two tabs, and the letter you are writing is
--- on paper like everything else an NPC hands you.
local function DressMail(frame, store)
	-- THE TABS HANG BELOW THE FRAME and the money row runs right down to its
	-- bottom edge, so the two overlap by a few pixels. They do in the client
	-- too - its own bottom border is drawn over the join and hides it - and
	-- taking that border off is what makes it visible.
	--
	-- Tab1 only: Tab2 is anchored to it, so moving the first moves both.
	local tab = _G.MailFrameTab1
	if tab and not tab.__aetherDropped then
		tab.__aetherDropped = true
		tab:ClearAllPoints()
		tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, -MAIL_TAB_DROP)
	end

	for _, name in ipairs({ "InboxFrame", "SendMailFrame", "OpenMailFrame" }) do
		local pane = _G[name]
		if pane then
			pane.__aetherStore = pane.__aetherStore or {}
			Reskin.Strip(pane, pane.__aetherStore)
			-- Lifted for the same reason the quest giver's is: this is printed
			-- on the same paper and is the same near-black.
			Reskin.Fonts(pane, "pnBody", 2, Palette.c.text)
		end
	end

	-- THE PANE'S OWN TITLE, which is not the window's. Inbox and Send Mail
	-- each carry one, in the client's gold, and the window has a title of its
	-- own above them - so this is the second word on screen saying the same
	-- thing in a different colour.
	for _, name in ipairs({ "InboxTitleText", "SendMailTitleText",
		"OpenMailTitleText" }) do
		local fs = _G[name]
		if fs then
			Reskin.Font(fs, "pnTitle")
			W.Color(fs, Palette.c.text)
		end
	end
	local page = _G.InboxCurrentPage
	if page then W.Color(page, Palette.c.textDim) end

	-- THE AUCTION HOUSE'S RECEIPT, which the client prints in a dark brown that
	-- reads on parchment and all but vanishes on glass. It is not black enough
	-- for the sweep to lift - that catches ink under 0.35 and this sits just
	-- over it - so the lines are named and given ours outright.
	--
	-- The labels take the dim ink and the amounts the full, which is the same
	-- pairing the rest of the deck uses for a name and its value.
	for _, name in ipairs({ "OpenMailInvoiceItemLabel", "OpenMailInvoiceBuyMode",
		"OpenMailInvoiceNotYetSent", "OpenMailInvoiceMoneyDelay" }) do
		local fs = _G[name]
		if fs then
			Reskin.Font(fs, "pnBody")
			W.Color(fs, Palette.c.textDim)
		end
	end
	for _, name in ipairs({ "OpenMailInvoicePurchaser", "OpenMailBodyText" }) do
		local fs = _G[name]
		if fs then
			Reskin.Font(fs, "pnBody")
			W.Color(fs, Palette.c.text)
		end
	end

	-- WHAT YOU CAME FOR, LIFTED OUT OF THE STRIP. The letter's attachment row
	-- and its label are placed by the CLIENT, from Lua, against the window's own
	-- BOTTOM edge - 31 units up - and re-placed on every update. Growing the
	-- window cannot help with that: the bottom edge takes them with it, so they
	-- stayed in the footer with Reply and Delete printed over them.
	--
	-- Hooked once, and it adds the room the strip takes rather than replacing
	-- the client's arithmetic - which depends on how many items the letter has
	-- and is none of our business.

	-- THE LETTER YOU ARE WRITING. A ScrollingEditBox with its parchment in
	-- its OWN background layer and its bar as a frame beside it - neither is a
	-- region of the pane, so the sweep above reaches neither.
	local editor = _G.MailEditBox
	if editor then
		editor.__aetherStore = editor.__aetherStore or {}
		Reskin.Strip(editor, editor.__aetherStore)
		local eb = editor.GetEditBox and editor:GetEditBox()
		if eb then
			Reskin.Font(eb, "pnBody")
			W.Color(eb, Palette.c.text)
		end
	end
	local ebar = _G.MailEditBoxScrollBar
	if ebar then
		ebar.__aetherStore = ebar.__aetherStore or {}
		Reskin.ScrollBar(ebar, ebar.__aetherStore)
	end

	-- THE FIELDS. Three slices of `Common-Input-Border` each, drawn as
	-- background regions of the box itself - so there is nothing to swap, only
	-- a sweep and one of our wells behind.
	for _, name in ipairs({ "SendMailNameEditBox", "SendMailSubjectEditBox" }) do
		Reskin.EditBox(_G[name])
	end

	-- The three money boxes, which keep their coin: it is a background region
	-- like the border is, and a sweep that takes both leaves the player typing
	-- gold, silver and copper into three identical nameless boxes.
	--
	-- And the coin is the FIELD's mark rather than a picture that happens to be
	-- near it, because the client puts gold's outside the box and the other two
	-- inside - so with its own border art gone the row wore its coins three
	-- different distances from three identical pills.
	for _, name in ipairs({ "SendMailMoneyGold", "SendMailMoneySilver",
		"SendMailMoneyCopper" }) do
		local box = _G[name]
		Reskin.EditBox(box, { keep = { "texture" }, unit = box and box.texture })
	end

	-- SEND MONEY OR C.O.D., which are one choice with two answers - so they
	-- are radio buttons, and a radio button is round. They were the client's
	-- own gold-rimmed disc, the last piece of its art left on this pane.
	local radios = { _G.SendMailSendMoneyButton, _G.SendMailCODButton }
	for _, box in ipairs(radios) do Reskin.Radio(box, store) end

	-- THE PAIR MOVES TOGETHER, and only one of them is ever clicked. The client
	-- turns the other off by calling SetChecked on it, and it does the same
	-- from its own update when an attachment rules C.O.D. out - so a mark
	-- refreshed from its own button's OnClick would leave the one you just
	-- left filled in. Both paths go through the one global, so that is the hook.
	local function Marks()
		for _, box in ipairs(radios) do
			W.CheckState(box, box.GetChecked and box:GetChecked())
		end
	end
	Marks()
	if not PN.__mailRadio and _G.SendMailRadioButton_OnClick then
		PN.__mailRadio = true
		hooksecurefunc("SendMailRadioButton_OnClick", Marks)
	end

	-- THE TOTAL, which the client wraps TWICE - a black inset and a thin gold
	-- edge, two surrounds for one number. Both come off and one well goes back
	-- on the inner of them, which is the one sized to the figure.
	for _, name in ipairs({ "SendMailMoneyInset", "SendMailMoneyBg" }) do
		local f = _G[name]
		if f then
			f.__aetherStore = f.__aetherStore or {}
			Reskin.Strip(f, f.__aetherStore)
		end
	end
	if _G.SendMailMoneyBg then
		Reskin.Well(_G.SendMailMoneyBg, { inset = { 0, 0, 0, 0 } })
	end

	-- THE LETTER ITSELF, which never had a border - the stationery behind it
	-- was the frame, and with that gone the words sit on bare glass with
	-- nothing saying where you may type. Its bar goes inside the well rather
	-- than beside it, so the field reads as one thing.
	if _G.MailEditBox then
		Reskin.Well(_G.MailEditBox, {
			corner = 6, inset = { 8, 16, 6, 8 }, to = _G.MailEditBoxScrollBar,
		})
	end

	-- THE ATTACHMENT SLOTS. Sixteen on each of two panes, and the plate is a
	-- background region rather than the normal texture, so the cell dresser
	-- has to be told to sweep as well as clear.
	for i = 1, 16 do
		Reskin.Slot(_G["SendMailAttachment" .. i], { store = store })
		Reskin.Slot(_G["OpenMailAttachmentButton" .. i], { store = store })
	end
	Reskin.Slot(_G.OpenMailLetterButton, { store = store })
	-- The scroll frames on the older panes, whose troughs are drawn on the
	-- FRAME rather than on the bar.
	for _, name in ipairs({ "SendMailScrollFrame", "OpenMailScrollFrame" }) do
		Reskin.ScrollFrame(_G[name], store)
	end

	-- THE PAGE TURNERS. The client draws these as a picture of a button -
	-- arrow and plate in one texture - so clearing the plate took the arrow
	-- with it and left two live controls with nothing drawn on them at all.
	--
	-- The same mark the spellbook's wear. These were a filled circle, which is
	-- the same control doing the same job one window apart in two different
	-- flavours.
	Reskin.PageTurn(_G.InboxPrevPageButton, "LEFT", store)
	Reskin.PageTurn(_G.InboxNextPageButton, "RIGHT", store)

	-- Send, Cancel, Reply, Delete, Open All and the rest. A dozen of them
	-- across three panes, so they are found the way the Options pages' are: a
	-- button with a label on it.
	--
	-- BUT NOT THE LETTERS. Every row in the inbox is a Button with a label on
	-- it and a child of the pane, so the sweep gave all seven a pressable
	-- surface - which is the panel behind each line in the list. A letter is a
	-- row you pick, not a button you press.
	-- EVERY LETTER IN THE LIST, and its own art off. The row is drawn as two
	-- slices of MailItemBorder plus a rule under it, all BACKGROUND regions of
	-- the row itself - so a sweep over the PANE reaches none of them and seven
	-- stone-and-parchment plaques sat in the recess.
	local letters = {}
	for i = 1, MAIL_ROWS do
		local row = _G["MailItem" .. i]
		if row then
			letters[row] = true
			row.__aetherStore = row.__aetherStore or {}
			Reskin.Strip(row, row.__aetherStore)

			-- The letter's picture is a BUTTON inside the row, the way a vendor's
			-- goods are - so stripping the row is safe and the icon goes in a cell.
			Reskin.Slot(_G["MailItem" .. i .. "Button"], { store = store })
		end
	end
	for _, name in ipairs({ "SendMailFrame", "OpenMailFrame", "InboxFrame" }) do
		Reskin.Buttons(_G[name], "pnBody", letters)
	end
end

--- A letter or a book out of your bags.
--
--  ITS PAGE IS FOUR TEXTURES, and they are regions of the frame itself - the
--  ARTWORK layer of ItemTextFrame - so the shell strip already takes them and
--  the module switching off puts them back. Hiding them again here would work
--  and would not be reversible, which is the worse of the two.
--
--  What is left is the words: near-black because they were printed on paper,
--  and a dark smudge on glass.
local function DressItemText(frame, store)
	local page = _G.ItemTextPageText
	if page then Reskin.Font(page, "pnBody", Palette.c.text) end

	local title = _G.ItemTextTitleText
	if title then W.Color(title, Palette.c.text) end
	local pageNo = _G.ItemTextCurrentPage
	if pageNo then W.Color(pageNo, Palette.c.textDim) end

	Reskin.ScrollFrame(_G.ItemTextScrollFrame, store)

	-- The page turners, art rather than words, and the same mark every other
	-- page turn in the interface wears.
	Reskin.PageTurn(_G.ItemTextPrevPageButton, "LEFT", store)
	Reskin.PageTurn(_G.ItemTextNextPageButton, "RIGHT", store)
end

--- The trade skill and craft windows - First Aid, cooking, enchanting, and a
--- hunter's beast training.
--
--  Two panes of the old hand-built shape: a list on the left with its own
--  black slab, a detail pane on the right with its own parchment, and a row of
--  red buttons along the bottom.
-- The two crafting windows are the same list twice: eight row buttons reused
-- down the page, a heading among them wearing the client's plus or minus as
-- its NORMAL texture, and an All control above them. What they do not share
-- is any of the names.
local SKILL_ROW_CAP = 30

local SKILL_WINDOWS = {
	TradeSkill = {
		row = "TradeSkillSkill", all = "TradeSkillCollapseAllButton",
		update = "TradeSkillFrame_Update", spinner = true,
		input = "TradeSkillInputBox",
		info = function(id)
			local name, kind, _, expanded = GetTradeSkillInfo(id)
			return name, kind, expanded
		end,
	},
	Craft = {
		row = "Craft", all = "CraftCollapseAllButton",
		update = "CraftFrame_Update",
		info = function(id)
			local name, _, kind, _, expanded = GetCraftInfo(id)
			return name, kind, expanded
		end,
	},
}

--- What the client says a row is, which beats reading it off the art.
--
--  The row carries its list index as its ID, so the same call the client
--  fills it from answers both questions. Asked rather than read, because this
--  client resolves a texture path to a file ID and leaves nothing to match on
--  - the trap that left every trainer row wearing Blizzard's mark.
local function SkillRowState(spec, btn)
	local id = btn.GetID and btn:GetID()
	if not id or id <= 0 then return nil end
	local ok, name, kind, expanded = pcall(spec.info, id)
	if not ok or not name then return nil end
	return kind == "header", expanded
end

--- The list, dressed again after every refill.
--
--  Refilled on every expand, every pick and every craft, and each refill puts
--  the client's own plus or minus straight back on.
local function DressSkillRows(prefix)
	local spec = SKILL_WINDOWS[prefix]
	if not spec then return end

	for i = 1, SKILL_ROW_CAP do
		local btn = _G[spec.row .. i]
		if not btn then break end

		local header, expanded = SkillRowState(spec, btn)
		if header then
			btn.isExpanded = expanded or nil
			Reskin.Collapse(btn)
			if btn.__aetherGlyph then btn.__aetherGlyph:Show() end
		else
		-- A row that was a heading a moment ago is a recipe now. The client
		-- clears its own NORMAL texture here; ours has to go with it - and the
		-- template's other three states do not go with it, so a recipe row
		-- still lit up with Blizzard's plus button when you hovered it.
		if btn.__aetherGlyph then btn.__aetherGlyph:Hide() end
		Reskin.ClearButton(btn)
		end
	end

	-- All, which expands and collapses the lot. It keeps its own flag rather
	-- than a list index: 1 when collapsed, nil when not.
	local all = _G[spec.all]
	if all then
		all.isExpanded = (not all.collapsed) or nil
		Reskin.Collapse(all)
	end
end

local function DressSkillWindow(prefix)
	return function(frame, store)
		-- THE LIST'S WELL REACHES UP over its own controls. The All switch and
		-- the progress bar are content - they act on the list, and there can be
		-- several bars - so they belong in the recess with it rather than
		-- floating between two wells on bare glass.
		Reskin.ScrollFrame(_G[prefix .. "ListScrollFrame"], store,
			{ headroom = SKILL_HEAD })
		Reskin.ScrollFrame(_G[prefix .. "DetailScrollFrame"], store)

		-- ...AND THEY ARE PLACED INSIDE IT, off the well rather than off the
		-- window: the well is the thing they belong to, and it moves.
		local listWell = _G[prefix .. "ListScrollFrame"]
			and _G[prefix .. "ListScrollFrame"].__aetherWell
		if listWell then
			local allBtn = _G[prefix .. "CollapseAllButton"]
			if allBtn and allBtn.ClearAllPoints then
				allBtn:ClearAllPoints()
				allBtn:SetPoint("TOPLEFT", listWell, "TOPLEFT",
					W.WELL_PAD, -W.WELL_PAD)
			end

			-- HOW FAR ALONG YOU ARE, in our own bar. The client's is its stone
			-- trough and a blue fill, which is the one thing on this window still
			-- wearing Blizzard's colours.
			local rank = Reskin.Element(frame, "RankFrame")
				or _G[prefix .. "RankFrame"]
			if rank and rank.ClearAllPoints then
				Reskin.StatusBar(rank, store)
				rank:ClearAllPoints()
				rank:SetPoint("TOPLEFT", allBtn or listWell,
					allBtn and "BOTTOMLEFT" or "TOPLEFT",
					allBtn and 0 or W.WELL_PAD, -6)
				rank:SetPoint("RIGHT", listWell, "RIGHT", -W.WELL_PAD, 0)
				if rank.SetHeight then rank:SetHeight(SKILL_BAR_H) end
			end
		end

		-- WHICH ROW YOU ARE ON, in our ink rather than Blizzard's blue - and
		-- neither of these two windows touched it at all, so the slice stayed
		-- lying across our glass on whichever recipe you had picked.
		Reskin.RowMark(_G[prefix .. "HighlightFrame"], store)

		-- THE LITTLE STONE TAB the All control hangs off - a trainer's left cap
		-- with a quest log's sort tab stretched across it. Its own frame, and
		-- not one the shell walks, so it sat behind All on our glass.
		Reskin.Strip(_G[prefix .. "ExpandButtonFrame"], store)

		-- ...AND THE FILTERS SIT OVER THE PANE THEY FILTER, right-aligned above
		-- the detail's recess and chained leftward from its corner. They were in a
		-- tool row across the whole window, which reads as being about the window
		-- rather than about what you are reading on the right.
		local detailWell = _G[prefix .. "DetailScrollFrame"]
			and _G[prefix .. "DetailScrollFrame"].__aetherWell
		if detailWell then
			local prev
			for _, key in ipairs({ "InvSlotDropdown", "SubClassDropdown" }) do
				local dd = Reskin.Element(frame, key)
				if dd and dd.ClearAllPoints then
					dd:ClearAllPoints()
					if prev then
						dd:SetPoint("RIGHT", prev, "LEFT", -W.PANEL_GAP, 0)
					else
						dd:SetPoint("BOTTOMRIGHT", detailWell, "TOPRIGHT", 0,
							W.PANEL_GAP)
					end
					prev = dd
				end
			end
		end

		-- THE FILTERS, which are the modern dropdown Communities uses: a stone
		-- holder, an arrow and a label, all regions of the button. None of them
		-- has a label of its own, so the sweep below - which finds a button by
		-- the words on it - goes straight past. Trade skills carry two, crafting
		-- one and Era's crafting none, so they are asked for by key.
		for _, key in ipairs({ "SubClassDropdown", "InvSlotDropdown", "Dropdown" }) do
			DressDropdown(Reskin.Element(frame, key), store)
		end

		-- THE COUNT SPINNER, and the box between the two of them. Both buttons
		-- are art with no words, so the sweep misses those as well.
		local spec = SKILL_WINDOWS[prefix]
		if spec and spec.spinner then
			Reskin.ArrowButton(_G[prefix .. "DecrementButton"], "LEFT", store)
			Reskin.ArrowButton(_G[prefix .. "IncrementButton"], "RIGHT", store)
			Reskin.EditBox(_G[spec.input])
		end

		-- Every button on it, by what it is: Create, Create All, Close, the
		-- filter dropdowns' arrows and the count spinner. They are named, and
		-- there are ten of them across two game versions of this window.
		--
		-- BUT NOT THE LIST. Every recipe in it is a Button with a font string on
		-- it and a child of the window - so a sweep by shape gave all thirty a
		-- pressable SURFACE, and the recipe list came up as thirty pills stacked
		-- on each other. A row in a list is not a button you press, it is a line
		-- you pick; nowhere else in this interface draws one that way, and the
		-- trainer - whose sweep looks for the client's three-slice plate rather
		-- than for words - never did.
		local rows = {}
		for i = 1, SKILL_ROW_CAP do
			local row = spec and spec.row and _G[spec.row .. i]
			if row then rows[row] = true end
		end
		local all = spec and spec.all and _G[spec.all]
		if all then rows[all] = true end

		Reskin.Buttons(frame, "pnBody", rows)

		-- The detail pane is printed on paper like a quest.
		local detail = _G[prefix .. "DetailScrollChildFrame"]
		if detail then Reskin.Fonts(detail, "pnBody", 2, Palette.c.text) end

		DressSkillRows(prefix)

		-- AND AGAIN AFTER EVERY REFILL. Expanding a heading, picking a recipe
		-- or making one all rebuild the list, and each rebuild puts the
		-- client's own mark back on every heading it draws.
		PN.__listHooks = PN.__listHooks or {}
		if hooksecurefunc and spec and _G[spec.update]
			and not PN.__listHooks[prefix] then
			PN.__listHooks[prefix] = true
			hooksecurefunc(spec.update, function()
				if PN.enabled then DressSkillRows(prefix) end
			end)
		end
	end
end
--- The letter you open, which is a window of its own.
--
--  ITS OWN DRESSER, not the postbox's. All of this used to run inside the
--  postbox's, reaching across into another window's globals - so anything
--  that threw earlier in THAT function took the letter with it, silently, and
--  the letter came up with its sender adrift and its receipt unreadable while
--  the postbox beside it looked perfect.
local function DressOpenMail(frame, store)
	local _ = frame

	-- Its own art off, and the words on it lifted: printed on stationery, like
	-- the quest giver's, and a dark smudge on glass.
	frame.__aetherStore = frame.__aetherStore or {}
	Reskin.Strip(frame, frame.__aetherStore)
	Reskin.Fonts(frame, "pnBody", 2, Palette.c.text)
	-- WHO IT IS FROM, OFF A BUTTON THIS CLIENT DOES NOT USE.
	--
	-- The sender's name lives in a frame pinned by TWO corners: its label on
	-- one side and the Report Player button on the other. That button is HIDDEN
	-- on this build - there is no reporting here - and never laid out, so the
	-- box came out with its bottom ABOVE its top: 239 wide and NOTHING tall,
	-- with the name drawn up beside the window's title instead of beside From.
	--
	-- So it hangs off its own label and carries a size of its own. Nothing that
	-- has to be visible should be pinned to something that is not.
	local who, label = _G.OpenMailSender, _G.OpenMailSenderLabel
	if who and label and who.ClearAllPoints and who.SetSize then
		who:ClearAllPoints()
		who:SetPoint("LEFT", label, "RIGHT", 5, 0)
		who:SetSize(239, label.GetHeight and label:GetHeight() or 16)
	end

	-- AND THE REST OF THE RECEIPT IS SWEPT RATHER THAN NAMED. Its labels -
	-- Sale Price, Deposit, Auction House Cut - are unnamed strings inside the
	-- invoice frame, and four of the lines are not text at all: the amounts are
	-- MoneyFrames, gold silver and copper each in a string of their own.
	--
	-- RED IS LEFT ALONE. The client prints the house's cut in red and means it,
	-- the way a quest heading's gold is meant - so a string that is markedly
	-- redder than it is anything else keeps what it was given.
	local function ReceiptInk(host, depth)
		if not host or (depth or 0) > 4 then return end
		for _, r in ipairs({ host.GetRegions and host:GetRegions() or {} }) do
			if r.GetObjectType and r:GetObjectType() == "FontString" then
				local red, green, blue = r:GetTextColor()
				local mean = (red and green and blue)
					and (red + green + blue) / 3 or 1

				-- RED IS MEANT AND SO IS GOLD. The client prints the house's cut in
				-- red and the subject in gold, the way a quest heading is gold - so
				-- only genuinely DARK ink is lifted. The receipt's labels sit around
				-- a third and gold sits above a half, which separates them.
				local meant = (red and green and blue
					and red > green + 0.2 and red > blue + 0.2)
					or mean >= RECEIPT_DARK
				Reskin.Font(r, "pnBody")
				if not meant then W.Color(r, Palette.c.text) end
			end
		end
		for _, kid in ipairs({ host.GetChildren and host:GetChildren() or {} }) do
			ReceiptInk(kid, (depth or 0) + 1)
		end
	end
	-- SWEPT WHEREVER IT IS. There is no invoice frame on this build at all: the
	-- receipt is printed inside the letter's own scrolling page, so naming a
	-- container out of the published source found nothing to lift.
	-- ON EVERY LETTER, not once. The receipt is BUILT when a letter is opened -
	-- an auction's lines do not exist until there is an auction to print - so a
	-- sweep at dress time finds an empty page and everything after it arrives
	-- in the client's own near-black.
	local function InkReceipt()
		if not PN.enabled then return end
		-- THE RECEIPT'S INK IS ON A FONT OBJECT, not on its strings.
		--
		-- Every line of it inherits InvoiceTextFontNormal or InvoiceTextFontSmall,
		-- and those carry a colour of their own - 0.18, 0.12, 0.06, near black,
		-- chosen for the parchment the letter used to be printed on. A string that
		-- takes its colour from an object does not keep one you set on the string,
		-- so painting them one at a time was never going to hold however many
		-- containers I swept.
		--
		-- Recorded before it is changed: these are the CLIENT's font objects,
		-- shared with anything else that might use them, so switching the module
		-- off has to give them back.
		local c = Palette.c.text
		for _, name in ipairs({ "InvoiceTextFontNormal", "InvoiceTextFontSmall" }) do
			local font = _G[name]
			if font and font.SetTextColor then
				PN.__invoiceInk = PN.__invoiceInk or {}
				if not PN.__invoiceInk[name] and font.GetTextColor then
					PN.__invoiceInk[name] = { font:GetTextColor() }
				end
				font:SetTextColor(c[1], c[2], c[3], c[4] or 1)
			end
		end

		-- ...and the sweep stays for what is NOT on those objects: the money
		-- frames print their own amounts and the client colours a loss red.
		ReceiptInk(_G.OpenMailFrame, 0)
	end

	local function LiftAttachments()
		if not PN.enabled then return end
		local up = W.PANEL_PAD + W.PANEL_FOOT_H

		-- AND IN FROM THE LEFT BY WHAT THE BODY MOVED. These hang off the
		-- window's BOTTOM LEFT corner, so they want both of the body's insets and
		-- not just the vertical one - "Take Attachments" sat outside the recess.
		local across = frame and frame.__aetherBodyInset or 0
		-- AND THE MONEY BUTTON AMONG THEM. What a letter carries is not always an
		-- attachment: coin arrives in OpenMailMoneyButton, which is placed the
		-- same way and was in none of the lists - so on an auction receipt the one
		-- icon on the window was the one that stayed in the footer.
		local moved = { _G.OpenMailAttachmentText, _G.OpenMailLetterButton,
			_G.OpenMailMoneyButton, _G.OpenMailHorizontalBarLeft }
		for i = 1, MAIL_ATTACHMENTS do
			moved[#moved + 1] = _G["OpenMailAttachmentButton" .. i]
		end
		-- AND THE SLOTS LINE UP UNDER THE WORDS. The client centres a single item
		-- across the whole width while leaving its label at the left margin, so
		-- the one attachment on a letter floated in the middle with nothing above
		-- it. A row and its heading start at the same place everywhere else here.
		local label = _G.OpenMailAttachmentText
		local first = _G.OpenMailLetterButton
		if first and not (first.IsShown and first:IsShown()) then
			first = _G.OpenMailMoneyButton
		end
		if first and not (first.IsShown and first:IsShown()) then
			first = _G.OpenMailAttachmentButton1
		end
		local shunt = 0
		if label and first and label.GetLeft and first.GetLeft
			and label:GetLeft() and first:GetLeft() then
			shunt = label:GetLeft() - first:GetLeft()
		end

		for _, part in ipairs(moved) do
			if part and part.GetPoint and part:GetNumPoints() > 0 then
				local pt, rel, relP, x, y = part:GetPoint(1)
				if relP == "BOTTOMLEFT" and not part.__aetherLifted then
					part.__aetherLifted = true
					part:ClearAllPoints()
					local mine = (part == label) and 0 or shunt
				part:SetPoint(pt, rel, relP, (x or 0) + across + mine,
					(y or 0) + up)
					part.__aetherLifted = nil
				end
			end
		end
	end

	-- BOTH DOORS. The row is placed by UpdateButtonPositions and the label by
	-- Update, and the client calls them from different places - hooking one of
	-- the two lifted the words and left the slots where they were.
	PN.__mailHooks = PN.__mailHooks or {}
	for _, fn in ipairs({ "OpenMail_Update",
		"OpenMailFrame_UpdateButtonPositions" }) do
		if hooksecurefunc and _G[fn] and not PN.__mailHooks[fn] then
			PN.__mailHooks[fn] = true
			hooksecurefunc(fn, function()
				LiftAttachments()
				InkReceipt()
			end)
		end
	end

	-- Once now for the letter already open, and on every one after it.
	InkReceipt()
end

--- Interiors, by frame. A window with no entry gets the shell treatment only.
local INTERIORS = {
	CharacterFrame    = DressCharacter,
	InspectFrame      = DressInspect,
	MailFrame         = DressMail,
	ItemTextFrame     = DressItemText,
	OpenMailFrame     = DressOpenMail,
	TradeSkillFrame   = DressSkillWindow("TradeSkill"),
	CraftFrame        = DressSkillWindow("Craft"),
	GameMenuFrame     = DressGameMenu,
	SpellBookFrame    = DressSpellBook,
	PlayerTalentFrame = DressTalents,
	CommunitiesFrame  = DressCommunities,
	MerchantFrame     = DressMerchant,
	QuestFrame        = DressQuest,
	GossipFrame       = DressGossip,
	ClassTrainerFrame = DressTrainer,
	TaxiFrame         = DressTaxi,
	SettingsPanel     = DressSettings,
}

PN.INTERIORS = INTERIORS

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
function PN:Skin()
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
