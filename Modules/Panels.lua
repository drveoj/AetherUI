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

local PANELS = {
	{ frame = "CharacterFrame", insets = { 10, -10, -30, 26 } },
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
		closeCorner = true,
		tabs        = "SpellBookFrameTabButton",
	},
	-- The talent frame names its parts the usual way, but it puts its close
	-- button 44 in and 25 down like the spellbook does - in the middle of a
	-- stone rim that comes off with the rest of the art.
	{
		frame       = "PlayerTalentFrame",
		addon       = "Blizzard_TalentUI",
		insets      = { 4, -4, -4, 24 },
		closeCorner = true,
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
	{ frame = "GossipFrame",   tight = true },
	-- The vendor's glass reaches BELOW the frame, which is the one place an
	-- inset goes negative. Blizzard hangs this window's tabs off the bottom
	-- edge, outside its own art - so trimmed to the frame the tab row landed on
	-- top of the buyback row, the repair buttons and your purse all at once.
	-- Thirty-four is the tab strip plus air.
	{ frame = "MerchantFrame", tight = true, insets = { 0, 0, 0, -34 } },
	{ frame = "TradeFrame",    tight = true },
	-- 62 at the foot, because that is where this window's buttons are: Accept,
	-- Complete Quest and Cancel all sit 72 up from the bottom edge, and the art
	-- below them is margin. Trimmed to 22 the glass ran a hand's width past the
	-- last thing in the window.
	{ frame = "QuestFrame",        insets = { 8, -8, -28, 62 } },
	{ frame = "ClassTrainerFrame", addon = "Blizzard_TrainerUI",
	                               insets = { 8, -8, -28, 22 } },
	-- The flight map IS a region of the frame, so the sweep that takes the
	-- parchment takes the map with it and leaves the nodes floating in the
	-- dark. Its close button is TaxiCloseButton, not TaxiFrameCloseButton,
	-- which is why it kept the client's red X.
	{ frame = "TaxiFrame",         insets = { 8, -8, -28, 22 },
	                               close = "TaxiCloseButton",
	                               keep  = { "TaxiMap" } },

	-- NOT GuildFrame. The old FriendsFrame XML still defines a GuildFrame pane,
	-- setAllPoints inside the social window, and this list used to name it as a
	-- window of its own - so it got glass of its own behind a pane that already
	-- had some, and a scale of its own inside a frame already scaled. Nobody
	-- sees it either way: the guild button on this client opens Communities.
	{ frame = "CommunitiesFrame",  addon = "Blizzard_Communities" },
	{ frame = "WorldMapFrame",     addon = "Blizzard_WorldMap" },
	{ frame = "GameMenuFrame" },
	{ frame = "HelpFrame",         addon = "Blizzard_HelpFrame" },
	-- The Options window itself. Our own settings page lives inside it, and
	-- skinning the page while leaving the frame around it in stone is the
	-- one place a player sees both at once.
	{ frame = "SettingsPanel", close = "ClosePanelButton" },

	-- THE POSTBOX. ButtonFrameTemplate, so tight - but its tabs hang off the
	-- bottom edge outside its own art the way the vendor's do, and trimmed to
	-- the frame the Inbox and Send Mail tabs land outside the glass.
	{ frame = "MailFrame", tight = true, insets = { 0, 0, 0, -MAIL_TAB_DROP - 8 },
		tabs = "MailFrameTab" },

	-- A LETTER OR A BOOK out of your bags. Also ButtonFrameTemplate, and
	-- what is inside it is printed on paper - so its text is lifted the way
	-- the quest giver's is.
	{ frame = "ItemTextFrame", tight = true },

	-- THE TRADE SKILLS. Two windows, not one: TradeSkillFrame is First Aid,
	-- cooking, blacksmithing and the rest, and CraftFrame is enchanting and
	-- a hunter's beast training. Neither inherits a template - they are the
	-- old hand-built shape with their own art and a wide margin, so they
	-- want trimming like the trainer rather than tight like the modern ones.
	{ frame = "TradeSkillFrame", addon = "Blizzard_TradeSkillUI",
		insets = { 8, -8, -28, 22 } },
	{ frame = "CraftFrame", addon = "Blizzard_CraftUI",
		insets = { 8, -8, -28, 22 } },
}

PN.PANELS = PANELS

--- The same list, by frame name, for the things Dress needs mid-flight.
PN.ENTRY = {}
for _, entry in ipairs(PANELS) do PN.ENTRY[entry.frame] = entry end

local function cfg() return A.Config:Module("panels") end

--- A floor under how small these windows may be drawn.
--
--  Ours are drawn at profile.scale and look right there, because everything in
--  them is ours and sized for it. These are not ours: the paper doll, the item
--  icons and the client's own stat rows are fixed pixel art, and below about
--  this they stop being readable rather than merely small. A profile scale that
--  suits our HUD is not automatically one that suits a Blizzard window.
local PANEL_MIN_SCALE = 0.85

--- A point on top of our usual sizes, for the same reason.
--
--  These windows are wide and their text sits in the client's own layout, with
--  its spacing, at its line heights - and our type at HUD sizes reads small in
--  that company.
local FONT_BUMP = 1

local function PanelScale()
	local profile = A.db and A.db.profile
	local s = (profile and profile.scale or 1) * (cfg().scale or 1)
	return math.max(s, PANEL_MIN_SCALE)
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

local function DressClose(frame, store)
	local close = CloseButton(frame)
	if not close then return end

	-- Into the corner of the glass, where the window put its own well inside the
	-- art. The spellbook's and the talent frame's both sit 44 in from the right
	-- and 25 down - the middle of a stone rim that is no longer there - and read
	-- as a stray cross floating in the page.
	local name = frame.GetName and frame:GetName()
	local entry = name and PN.ENTRY and PN.ENTRY[name]
	if entry and entry.closeCorner and close.ClearAllPoints then
		local ins = entry.insets or {}
		close:ClearAllPoints()
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", (ins[3] or 0) - 2, (ins[2] or 0) - 2)
	end

	if close.__aetherX then return end

	-- State textures first, then the regions: ClearButton wants to see the
	-- client's own paths, and Strip empties them. Reskin.ClearButton copes with
	-- either order now, but reading it in this one costs nothing.
	Reskin.ClearButton(close)
	Reskin.Strip(close, store)

	local x = W.Text(close, "tbCardTitle", "CENTER")
	x:SetPoint("CENTER", close, "CENTER", 0, 0)
	x:SetText("\195\151")          -- U+00D7, the same one our own panels use
	W.Color(x, Palette.c.textDim)
	close.__aetherX = x
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

	Reskin.Panel(frame, { corner = 16, insets = entry and entry.insets })

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

	-- A header from that template STRADDLES the top edge on purpose: the stone
	-- plate is meant to overhang the frame, so its words sit half outside. Take
	-- the plate away and they hang over the rim, so they come inside.
	if moved and title.ClearAllPoints then
		local ins = entry and entry.insets
		title:ClearAllPoints()
		title:SetPoint("TOP", frame, "TOP", 0, (ins and ins[2] or 0) - 14)
	end
	if title and title.SetText then
		-- A TITLE IN A BAND KEEPS THE CLIENT'S SIZE. The modern template hands
		-- its title a band twenty pixels tall, and our pnTitle at nineteen
		-- fills it corner to corner and overhangs the ends - which is the
		-- gossip window's name reading as though it had been shouted.
		--
		-- The old windows have the whole width to themselves and no such band,
		-- so those keep the bigger role. Same reasoning as Reskin.Font's: where
		-- the client measured a space for the words, the metrics stay theirs.
		if entry and entry.tight then
			Reskin.Font(title, "pnTitle")
		else
			Roled(title, "pnTitle")
		end
		W.Color(title, Palette.c.text)
		frame.__aetherTitle = title
	end

	DressClose(frame, store)

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

-- The tab strip. Blizzard's tabs are sized for art with wide transparent
-- margins and are meant to overlap - the art hides the join. Strip the art and
-- the overlap is all you can see, so they are measured to their own label and
-- chained with a gap of ours.
local TAB_PAD, TAB_GAP, TAB_H, TAB_EDGE = 26, 6, 26, 16

-- What to give up, in order, when the row is too wide for the window. Padding
-- first and the gap second, because both are ours to spend; the label's own
-- width is not, and a tab squeezed narrower than the word inside it just spills
-- the word out over both ends of the pill.
local TAB_PADS = { 26, 22, 18, 14 }
local TAB_GAPS = { 6, 4, 2 }

-- And after both of those, a point or two off the lettering. Still not the
-- word: a shade smaller reads fine, three dots in place of three letters does
-- not.
local TAB_STYLE = "pnTab"
-- Three, because the row starts a point up: this spends the bump and one more
-- besides before it gives up and lets the row overhang.
local TAB_FONT_STEPS = 3

-- The most glass we will add either side to stop a row overhanging. A few
-- pixels is the point; a window stretched around whatever it is given is not.
local TAB_GROW_MAX = 48

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

	-- FILLED, the way the chat's selected tab is - dark type on the accent,
	-- inverted from everything else on screen. That inversion is the whole
	-- signal, and a tab that was merely BRIGHTER than its neighbours read as
	-- hovered rather than as the one you are standing on. One rule for every
	-- tab in the interface now, and it lives on the shared button surface.
	tab.__aetherSelected = selected
	W.SetButtonState(tab, selected, tab.IsMouseOver and tab:IsMouseOver())

	local text = TabLabel(tab)
	if not text then return end

	-- AND PUT THE LABEL BACK IN THE MIDDLE. Selecting a tab moves its text: the
	-- client nudges it up into the raised part of its own stone art, which is
	-- right for that art and wrong for a flat pill. It does this on every
	-- selection, so it has to be answered on every selection.
	if text.ClearAllPoints then
		text:ClearAllPoints()
		text:SetPoint("CENTER", tab, "CENTER", 0, 0)
	end
	if text.SetJustifyH then text:SetJustifyH("CENTER") end
end

--- How much room the tab row actually has: the visible window, less a margin.
local function StripWidth(frame, name)
	local w = (frame.GetWidth and frame:GetWidth()) or 0
	local entry = PN.ENTRY and PN.ENTRY[name]
	local ins = entry and entry.insets
	if ins then w = w + (ins[3] or 0) - (ins[1] or 0) end
	return w - TAB_EDGE * 2
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

	local room = StripWidth(frame, name)
	local base = (A.Media.style[TAB_STYLE] or {})[2]
	base = base and (base + FONT_BUMP)

	local gap = TAB_GAP
	local widths = MeasureTabs(tabs, base)

	local function widest(ws)
		local m = 0
		for _, w in ipairs(ws) do if w > m then m = w end end
		return m
	end

	-- EVERY TAB THE SAME WIDTH, sharing the row out evenly.
	--
	-- Sizing each one to its own word instead leaves the strip looking sprung:
	-- "Character" is half again the width of "Skills", so the space between the
	-- pills lands differently at every join and the row reads as a mistake. One
	-- width for all of them is what makes it a row.
	--
	-- It only works while the widest word still fits its share. When it does
	-- not, a point or two off the lettering buys the room - and if even that is
	-- not enough, each tab takes its own width back, because a word that will
	-- not fit its pill is worse than an uneven row.
	-- The width every tab gets is the WIDEST word plus padding: that is the
	-- narrowest one width that fits all of them. If the row of those is too
	-- wide for the window, the padding gives, then the gap, then a point or two
	-- of the lettering - and a smaller font makes the widest word narrower,
	-- which is what buys the room back.
	local even
	for stepIndex = 0, TAB_FONT_STEPS do
		if stepIndex > 0 then
			if not base then break end
			widths = MeasureTabs(tabs, base - stepIndex)
		end

		local word = widest(widths)
		for _, g in ipairs(TAB_GAPS) do
			for _, p in ipairs(TAB_PADS) do
				if room <= 0 or (word + p) * #tabs + g * (#tabs - 1) <= room then
					even, gap = word + p, g
					break
				end
			end
			if even then break end
		end

		if even then break end
	end

	-- Nothing fitted: tightest of everything and the row is wider than the
	-- window. Still one width, because an even row that overhangs reads as a
	-- row; an uneven one reads as a mistake.
	if not even then
		even, gap = widest(widths) + TAB_PADS[#TAB_PADS], TAB_GAPS[#TAB_GAPS]
	end

	-- The group, and where it goes: measured end to end, then centred in the
	-- window. If it is wider than the window even at the tightest of
	-- everything, the WINDOW gives - a few pixels of glass either side costs
	-- nothing and is better than a row that hangs over the edge.
	local total = even * #tabs + gap * (#tabs - 1)
	local entry = PN.ENTRY and PN.ENTRY[name]
	local ins = entry and entry.insets or {}
	local left, right = ins[1] or 0, ins[3] or 0

	local visible = (frame.GetWidth and frame:GetWidth() or 0) + right - left
	if total + TAB_EDGE * 2 > visible then
		-- Capped, because this is meant to be the few pixels that stop a row
		-- from overhanging - not a way to stretch a window around anything you
		-- put in it. Past the cap the row overhangs and that is the honest
		-- answer.
		local grow = math.min(total + TAB_EDGE * 2 - visible, TAB_GROW_MAX)
		right = right + grow
		visible = visible + grow

		-- Both corners, from clear: setting one anchor again leaves the old one
		-- in place on some paths, and then the panel has two right edges.
		local panel = frame.__aetherPanel
		if panel and panel.ClearAllPoints then
			panel:ClearAllPoints()
			panel:SetPoint("TOPLEFT", frame, "TOPLEFT", left, ins[2] or 0)
			panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, ins[4] or 0)
		end
	end

	-- LEFT, not centred. A row of tabs is a list of places you can go, and a
	-- list starts at the left edge of the thing it belongs to - the same edge
	-- everything else in the window starts at. Centred, the row moved every
	-- time a tab appeared or went away: a hunter's pet tab arriving slid
	-- Character, Skills and Reputation sideways under the cursor, which is a
	-- window that will not sit still.
	local startX = left + TAB_EDGE

	local last

	for i, tab in ipairs(tabs) do
		Reskin.Tab(tab, store, TAB_STYLE)

		-- One width, the same for every tab in the row.
		local w = even
		if tab.SetSize then tab:SetSize(w, TAB_H) end

		-- AND ITS CLICKABLE AREA BACK. The spellbook's tabs are 128x64 in the
		-- client's art with a hit rect inset 13 from the top and 15 from the
		-- bottom, to keep the clicks off the transparent margin. Resize that tab
		-- to 26 high and the two insets meet in the middle: the tab is drawn,
		-- reads correctly, highlights on hover - and cannot be clicked. The
		-- client's own values are recorded so switching off puts them back.
		if tab.SetHitRectInsets then
			if tab.__aetherHit == nil and tab.GetHitRectInsets then
				tab.__aetherHit = { tab:GetHitRectInsets() }
			end
			tab:SetHitRectInsets(0, 0, 0, 0)
		end

		-- Keep the label inside its pill. Measured from zero every time: a
		-- width set on a previous pass would otherwise be what we measure, and
		-- the label would ratchet narrower on every re-layout.
		local label = TabLabel(tab)
		if label then
			-- NEVER TRUNCATED. Shortening "Character" to "Charac..." trades
			-- three letters for three dots and tells the player less than the
			-- word did. If a row is tight the padding gives way, not the word.
			if label.SetWordWrap then label:SetWordWrap(true) end
			if label.SetWidth then label:SetWidth(0) end

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
			local p = { tab:GetPoint() }
			tab.__aetherAnchor = (p[1] and p) or false
			if tab.GetWidth then tab.__aetherSize = { tab:GetWidth(), tab:GetHeight() } end
		end

		-- ONE ANCHOR, OURS, in a shape we control. The client's anchor is not
		-- used at all: a tab anchored by its CENTRE takes an x meaning "where
		-- the middle goes", so an offset written for a left edge hangs half the
		-- tab off the side of the screen. It is still RECORDED, because
		-- switching the module off has to put it back where the client had it.
		if last then
			tab:ClearAllPoints()
			tab:SetPoint("LEFT", last, "RIGHT", gap, 0)
		else
			tab:ClearAllPoints()
			tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", startX, (ins[4] or 0) + TAB_EDGE)
		end
		last = tab

		StyleTabState(tab)

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

--- An equipped item's rim, in its quality colour.
--
--  Re-run on every slot update, because the client repaints its own border
--  whenever the item changes and ours has to answer.
local function SlotQuality(btn)
	if not btn or not btn.SetEdgeColor then return end

	local id = btn.GetID and btn:GetID()
	local q = id and GetInventoryItemQuality and GetInventoryItemQuality("player", id)
	local c = q and q > 1 and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]

	-- Common and poor get the ordinary rim: a white border on every empty slot
	-- is noise, and the point of the colour is that it stands out.
	btn:SetEdgeColor(c and { c.r, c.g, c.b, 1 } or Palette.c.glassEdge)
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
			Reskin.Strip(pane, store)

			-- And every string in it into our lettering. The client's own
			-- sizes are kept: these sit in rows and columns it measured, and a
			-- size of ours reflows somebody else's window.
			Reskin.Fonts(pane, "pnBody")
		end
	end

	-- Who you are, above the sheet.
	local who = _G.CharacterNameText
	if who and who.SetText then
		Roled(who, "pnTitle")
		W.Color(who, Palette.c.text)
	end
	local rank = _G.CharacterLevelText
	if rank and rank.SetText then
		Roled(rank, "pnSub")
		W.Color(rank, Palette.c.textDim)
	end

	EachEquipSlot(function(slot)
		Reskin.Slot(slot)
		SlotQuality(slot)
	end)

	LayoutTabs(frame, store)
	InstallTabHooks()

	local model = _G.CharacterModelFrame
	if model then
		Reskin.Strip(model, store)
		for _, key in ipairs({ "RotateLeftButton", "RotateRightButton" }) do
			local btn = _G["CharacterModelFrame" .. key]
			if btn then Reskin.ClearButton(btn) end
		end
	end

	-- Resistance chips down the side, and the pet's set on its own tab.
	for _, prefix in ipairs({ "MagicResFrame", "PetMagicResFrame" }) do
		for n = 1, 5 do
			local chip = _G[prefix .. n]
			if chip then Reskin.Strip(chip, store) end
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

	-- A second close button, in the middle of the skills list, doing exactly
	-- what the one in the corner already does. Hidden rather than cleared: it
	-- is a whole button we do not want, not art we are replacing.
	local spare = _G.SkillFrameCancelButton
	if spare and spare.Hide and not spare.__aetherHidden then
		spare.__aetherHidden = spare:IsShown() and true or false
		spare:Hide()
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
local MENU_TOP_PAD = 44   -- 32 in the template, and the title sits in it

-- Forward-declared: it hooks InitButtons with a closure that calls itself,
-- and a `local function` cannot refer to its own name from inside.
local DressGameMenu
DressGameMenu = function(frame, store)
	if not frame.GetChildren then return end

	frame.spacing = MENU_SPACING
	frame.topPadding = MENU_TOP_PAD

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
local SIDE_TAB_EDGE = 6          -- in from the glass
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
local function DressSideTabs(frame, store, prefix, count)
	local name = frame.GetName and frame:GetName()
	local entry = name and PN.ENTRY and PN.ENTRY[name]
	local ins = entry and entry.insets or {}

	local last
	for i = 1, count do
		local tab = _G[prefix .. i]
		if not tab then break end

		-- No icon named: the school's picture IS this button's normal texture,
		-- which is what IconButton assumes when it is not told otherwise.
		Reskin.IconButton(tab, store)

		if tab.ClearAllPoints then
			tab:ClearAllPoints()
			if last then
				tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -SIDE_TAB_GAP)
			else
				tab:SetPoint("TOPRIGHT", frame, "TOPRIGHT",
					(ins[3] or 0) - SIDE_TAB_EDGE, (ins[2] or 0) - SIDE_TAB_TOP)
			end
		end

		-- Every one of them, shown or not. A hidden tab still holds its place in
		-- the chain, so anchoring only the visible ones leaves a gap the moment
		-- the player learns a profession and the ninth tab arrives.
		last = tab
	end
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

	MarkButton(_G.SpellBookPrevPageButton, store, GLYPH_PREV)
	MarkButton(_G.SpellBookNextPageButton, store, GLYPH_NEXT)

	local ranks = _G.ShowAllSpellRanksCheckbox
	if ranks then
		Reskin.CheckBox(ranks, store)
		local label = _G.ShowAllSpellRanksCheckboxText
		if label then
			Roled(label, "pnBody")
			W.Color(label, Palette.c.textDim)
		end
	end

	DressSpellButtons(store)
	DressSideTabs(frame, store, "SpellBookSkillLineTab", SPELL_TABS)

	-- No hook of its own on the client's rebuild. Its update hides all three
	-- tabs and shows the ones that apply, so the OnShow every hidden tab already
	-- carries answers it - and that is also what puts the label back in the
	-- middle of its pill, because enabling a tab is what moved it up.
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
local function DressMenu(menu)
	if not menu or not menu.GetRegions then return end

	local store = menu.__aetherArt
	if not store then
		store = {}
		menu.__aetherArt = store
	end

	Reskin.Strip(menu, store)
	Reskin.Panel(menu, { corner = 12 })

	-- LOCKED STRINGS. The menu wraps its own font strings and forbids SetFont -
	-- reading the key is enough to trip its assert - so these are re-roled
	-- through a font object instead. Colour is left alone either way: green, red
	-- and grey are the client saying whether you can learn the thing, which is
	-- what the filter is for.
	Reskin.Fonts(menu, "pnBody", 0, nil, true)
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

	-- Who you are buying from.
	local who = _G.MerchantNameText
	if who then
		Roled(who, "pnSub")
		W.Color(who, Palette.c.text)
	end

	LayoutTabs(frame, store)
	InstallTabHooks()
end

--- The quest giver: four panels of the same window, one shown at a time.
local QUEST_PANES = {
	"QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel",
	"QuestFrameGreetingPanel", "QuestNpcNameFrame",
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

	-- Who you are talking to, above the parchment.
	local who = _G.QuestNpcNameFrame
	local whoText = who and Reskin.Element(who, "Text")
	if whoText then
		Roled(whoText, "pnTitle")
		W.Color(whoText, Palette.c.text)
	end

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
local function DressGossipRows(frame)
	local panel = Reskin.Element(frame, "GreetingPanel")
	local box = panel and Reskin.Element(panel, "ScrollBox")
	if not box then return end

	local rows
	if box.GetFrames then
		local ok, got = pcall(box.GetFrames, box)
		rows = ok and got or nil
	end
	if not rows then return end

	for _, row in ipairs(rows) do
		Reskin.Fonts(row, "pnBody", 0, Palette.c.text)
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

	-- The list is rebuilt on open and on every option you pick. Two entry
	-- points, and BOTH of them, because they are not the same thing:
	-- Update rebuilds the data and UpdateScrollBox rebuilds the box.
	--
	-- AND AGAIN ON THE NEXT FRAME, which is the part that matters. The
	-- greeting and every option are POOLED ELEMENTS of a scroll box, and a
	-- scroll box acquires its frames during LAYOUT - after Update has
	-- returned. Asking GetFrames from inside the hook answers the set that
	-- was there before, so the new rows are never lifted and the window
	-- comes up in the near-black the client prints gossip in.
	--
	-- Which is also why it looked intermittent: whether a row had been
	-- lifted depended on whether the pool happened to hand back one that
	-- had.
	if hooksecurefunc and not PN.__gossipHook then
		local function relift(self)
			if not PN.enabled then return end
			DressGossipRows(self)
			if C_Timer and C_Timer.After then
				C_Timer.After(0, function()
					if PN.enabled then DressGossipRows(self) end
				end)
			end
		end
		local hooked = false
		for _, name in ipairs({ "Update", "UpdateScrollBox" }) do
			if frame[name] then
				hooksecurefunc(frame, name, relift)
				hooked = true
			end
		end
		PN.__gossipHook = hooked
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
	"ClassTrainerSkillHighlightFrame",
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
		elseif btn.__aetherGlyph then
			-- It is a spell this time round, not a heading. The client
			-- clears its own mark here; ours has to go with it.
			btn.__aetherGlyph:Hide()
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
	for _, name in ipairs(TRAINER_PANES) do
		local pane = _G[name]
		if pane then
			Reskin.Strip(pane, store)
			Reskin.Fonts(pane, "pnBody", 2, Palette.c.text)
		end
	end

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
	for _, kid in ipairs({ frame:GetChildren() }) do
		if kid.GetObjectType and kid:GetObjectType() == "Button"
			and Reskin.Element(kid, "Left")
			and Reskin.Element(kid, "Middle")
			and Reskin.Element(kid, "Right") then
			DressWideButton(kid, store)
			-- Train All carries its label twice, so the label is re-roled by
			-- sweeping the button rather than by asking for GetFontString.
			Reskin.Fonts(kid, "pnBody")
		end
	end

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
	for _, key in ipairs({ "GameTab", "AddOnsTab" }) do
		local tab = frame[key]
		if tab then
			Reskin.Tab(tab, store, "pnBody")
			tab:SetHeight(SETTINGS_TAB_H)
			local label = tab.Text or (tab.GetFontString and tab:GetFontString())
			local wide = label and label.GetStringWidth and label:GetStringWidth() or 0
			tab:SetWidth(math.max(SETTINGS_TAB_W, wide + SETTINGS_TAB_PAD * 2))
		end
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
	for _, name in ipairs({ "SendMailMoneyGold", "SendMailMoneySilver",
		"SendMailMoneyCopper" }) do
		Reskin.EditBox(_G[name], { keep = { "texture" } })
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

	-- THE PAGE TURNERS. Art buttons rather than words, so the plate comes off
	-- and the arrow on it stays - it is the only thing saying which way.
	for _, name in ipairs({ "InboxPrevPageButton", "InboxNextPageButton" }) do
		local btn = _G[name]
		if btn then
			Reskin.ClearButton(btn)
			btn.__aetherStore = btn.__aetherStore or {}
			Reskin.Strip(btn, btn.__aetherStore)
			Reskin.Fonts(btn, "pnBody", 0, Palette.c.text)
		end
	end

	-- Send, Cancel, Reply, Delete, Open All and the rest. A dozen of them
	-- across three panes, so they are found the way the Options pages' are: a
	-- button with a label on it.
	for _, name in ipairs({ "SendMailFrame", "OpenMailFrame", "InboxFrame" }) do
		local pane = _G[name]
		if pane and pane.GetChildren then
			for _, child in ipairs({ pane:GetChildren() }) do
				if child.GetObjectType and child:GetObjectType() == "Button"
					and child.GetFontString and child:GetFontString()
					and not child.__aetherSkin then
					Reskin.Button(child, "pnBody")
				end
			end
		end
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

	-- The page turners, which are art rather than words.
	for _, name in ipairs({ "ItemTextPrevPageButton", "ItemTextNextPageButton" }) do
		local btn = _G[name]
		if btn then
			Reskin.ClearButton(btn)
			Reskin.Strip(btn, store)
		end
	end
end

--- The trade skill and craft windows - First Aid, cooking, enchanting, and a
--- hunter's beast training.
--
--  Two panes of the old hand-built shape: a list on the left with its own
--  black slab, a detail pane on the right with its own parchment, and a row of
--  red buttons along the bottom.
local function DressSkillWindow(prefix)
	return function(frame, store)
		for _, suffix in ipairs({ "ListScrollFrame", "DetailScrollFrame" }) do
			Reskin.ScrollFrame(_G[prefix .. suffix], store)
		end

		-- Every button on it, by what it is: Create, Create All, Close, the
		-- filter dropdowns' arrows and the count spinner. They are named, and
		-- there are ten of them across two game versions of this window.
		if frame.GetChildren then
			for _, child in ipairs({ frame:GetChildren() }) do
				if child.GetObjectType and child:GetObjectType() == "Button"
					and child.GetFontString and child:GetFontString()
					and not child.__aetherSkin then
					Reskin.Button(child, "pnBody")
				end
			end
		end

		-- The detail pane is printed on paper like a quest.
		local detail = _G[prefix .. "DetailScrollChildFrame"]
		if detail then Reskin.Fonts(detail, "pnBody", 2, Palette.c.text) end
	end
end
--- Interiors, by frame. A window with no entry gets the shell treatment only.
local INTERIORS = {
	CharacterFrame    = DressCharacter,
	MailFrame         = DressMail,
	ItemTextFrame     = DressItemText,
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

--- Skin whatever exists now. Called again whenever more of it might.
function PN:Skin()
	for _, entry in ipairs(PANELS) do
		local frame = _G[entry.frame]
		if frame and frame.GetRegions then
			Dress(frame)

			if frame.HookScript and not frame.__aetherHooked then
				frame.__aetherHooked = true
				-- Re-dressed on every show. These windows rebuild parts of
				-- themselves as they open - a tab's art, a background swapped
				-- for another - and art the client puts back has to come off
				-- again. See Core\Reskin.lua on hiding versus clearing.
				frame:HookScript("OnShow", function(self)
					if not PN.enabled then return end
					Dress(self)
				end)
			end
		end
	end
end

function PN:OnEnable()
	self:Skin()

	-- The load-on-demand half. Each arrives with its own addon the first time
	-- it is opened, so this runs again rather than only at login.
	A:RegisterEvent(self, "ADDON_LOADED", function() PN:Skin() end)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() PN:Skin() end)
end

function PN:OnDisable()
	A:UnregisterAllEvents(self)

	for _, entry in ipairs(PANELS) do
		local frame = _G[entry.frame]
		if frame and frame.__aetherPanel then
			local close = CloseButton(frame)
			if close and close.__aetherX then
				close.__aetherX:Hide()
				close.__aetherX = nil
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
