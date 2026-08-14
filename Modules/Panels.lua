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

local W, Palette, Reskin = A.Widgets, A.Palette, A.Reskin

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
local PANELS = {
	{ frame = "CharacterFrame", insets = { 10, -10, -30, 26 } },
	-- The spellbook names none of its parts the way the others do: its title is
	-- a global of its own rather than $parentTitleText, its close button is
	-- SpellBookCloseButton rather than $parentCloseButton, and its tabs are
	-- SpellBookFrameTabButton1..3. Naming them here is cheaper than three
	-- special cases in Dress, and the next window with its own spelling only
	-- needs a line.
	{
		frame  = "SpellBookFrame",
		insets = { 4, -4, -4, 24 },
		title  = "SpellBookTitleText",
		close  = "SpellBookCloseButton",
		tabs   = "SpellBookFrameTabButton",
	},
	{ frame = "PlayerTalentFrame", addon = "Blizzard_TalentUI" },
	{ frame = "TalentFrame",       addon = "Blizzard_TalentUI" },
	{ frame = "FriendsFrame" },
	{ frame = "GuildFrame",        addon = "Blizzard_GuildUI" },
	{ frame = "WorldMapFrame",     addon = "Blizzard_WorldMap" },
	{ frame = "GameMenuFrame" },
	{ frame = "HelpFrame",         addon = "Blizzard_HelpFrame" },
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
	return (entry and entry.close and _G[entry.close])
		or Reskin.Element(frame, "CloseButton")
end

PN.CloseButton = CloseButton

local function DressClose(frame, store)
	local close = CloseButton(frame)
	if not close then return end

	-- Into the corner of the glass. A window that names its own close button
	-- also placed it for its own art: the spellbook's sits 44 in from the right
	-- and 25 down, which is the middle of a stone rim that is no longer there,
	-- and reads as a stray cross floating in the page.
	local name = frame.GetName and frame:GetName()
	local entry = name and PN.ENTRY and PN.ENTRY[name]
	if entry and entry.close and close.ClearAllPoints then
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

	Reskin.Strip(frame, store)

	local name = frame.GetName and frame:GetName()
	local entry = name and PN.ENTRY and PN.ENTRY[name]
	Reskin.Panel(frame, { corner = 16, insets = entry and entry.insets })

	-- Drawn at the profile's scale, like everything else of ours - but never
	-- below the floor, because what is inside these is the client's own art at
	-- a fixed size and it stops being readable before it stops being small.
	if frame.SetScale then frame:SetScale(PanelScale()) end

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
		Roled(title, "pnTitle")
		W.Color(title, Palette.c.text)
		frame.__aetherTitle = title
	end

	DressClose(frame, store)

	-- The insides, where this window has a policy for them. Reached through PN
	-- rather than an upvalue: the interiors are defined below this, and a local
	-- declared later is not in scope here.
	local interior = name and PN.INTERIORS and PN.INTERIORS[name]
	if interior then interior(frame, store) end

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

	if tab.__aetherTab then tab.__aetherTab:SetAlpha(selected and 1 or 0.4) end

	local text = TabLabel(tab)
	if not text then return end

	W.Color(text, selected and Palette.c.text or Palette.c.textDim)

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

	local startX = left + (visible - total) / 2

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
local function DressGameMenu(frame, store)
	if not frame.GetChildren then return end

	for _, child in ipairs({ frame:GetChildren() }) do
		-- A button, by what it can do rather than what it is called.
		if child and child.SetNormalTexture and child.GetFontString then
			Reskin.Button(child)
			Reskin.Strip(child, store)
		end
	end
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

local function DressSideTabs(frame, store)
	local name = frame.GetName and frame:GetName()
	local entry = name and PN.ENTRY and PN.ENTRY[name]
	local ins = entry and entry.insets or {}

	local last
	for i = 1, SPELL_TABS do
		local tab = _G["SpellBookSkillLineTab" .. i]
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
	DressSideTabs(frame, store)

	-- No hook of its own on the client's rebuild. Its update hides all three
	-- tabs and shows the ones that apply, so the OnShow every hidden tab already
	-- carries answers it - and that is also what puts the label back in the
	-- middle of its pill, because enabling a tab is what moved it up.
	LayoutTabs(frame, store)
	InstallTabHooks()
end

--- Interiors, by frame. A window with no entry gets the shell treatment only.
local INTERIORS = {
	CharacterFrame = DressCharacter,
	GameMenuFrame  = DressGameMenu,
	SpellBookFrame = DressSpellBook,
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
end

function PN:OnConfigChanged() self:Skin() end
