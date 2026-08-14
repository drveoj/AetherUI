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
	{ frame = "SpellBookFrame" },
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

-- ---------------------------------------------------------------------------
-- dressing
-- ---------------------------------------------------------------------------

--- The way out, in our own mark.
--
--  Blizzard's close button is a stone circle with an X baked into it, and with
--  its art stripped there is nothing left to click that looks like anything. So
--  it gets the same multiplication sign every window of ours already uses -
--  drawn on the client's own button, which keeps doing the closing.
local function DressClose(frame, store)
	local close = Reskin.Element(frame, "CloseButton")
	if not close or close.__aetherX then return end

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

	-- Drawn at the profile's scale, like everything else of ours. A window that
	-- ignores it is the one window on screen at the client's size.
	if frame.SetScale and A.db and A.db.profile then
		frame:SetScale(A.db.profile.scale or 1)
	end

	-- The window's own title, where it has one under a name we can find.
	local title = Reskin.Element(frame, "TitleText") or Reskin.Element(frame, "Title")
	if title and title.SetText then
		W.Restyle(title, "tbTitle")
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
local TAB_PAD, TAB_GAP, TAB_H, TAB_EDGE = 26, 6, 26, 8

local function TabLabel(tab)
	return Reskin.Element(tab, "Text") or (tab.GetFontString and tab:GetFontString())
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
	if text then W.Color(text, selected and Palette.c.text or Palette.c.textDim) end
end

--- How much room the tab row actually has: the visible window, less a margin.
local function StripWidth(frame, name)
	local w = (frame.GetWidth and frame:GetWidth()) or 0
	local entry = PN.ENTRY and PN.ENTRY[name]
	local ins = entry and entry.insets
	if ins then w = w + (ins[3] or 0) - (ins[1] or 0) end
	return w - TAB_EDGE * 2
end

local function LayoutTabs(frame, store)
	local name = frame.GetName and frame:GetName()
	if not name then return end

	-- Measure the whole row before placing any of it. Sizing each tab to its
	-- own label is only right while the row still fits the window - four tabs
	-- measured generously ran straight out past the right edge.
	local tabs, widths, natural = {}, {}, 0
	local n = 1
	while _G[name .. "Tab" .. n] do
		local tab = _G[name .. "Tab" .. n]
		tabs[n] = tab

		local text = TabLabel(tab)
		widths[n] = ((text and text.GetStringWidth and text:GetStringWidth()) or 60) + TAB_PAD
		natural = natural + widths[n]
		n = n + 1
	end
	if #tabs == 0 then return end

	natural = natural + TAB_GAP * (#tabs - 1)

	local room = StripWidth(frame, name)
	if room > 0 and natural > room then
		-- Equal shares. A row that overruns the window is worse than a row
		-- whose tabs are not each measured to their own label.
		local each = (room - TAB_GAP * (#tabs - 1)) / #tabs
		for i = 1, #tabs do widths[i] = each end
	end

	local last

	local i = 1
	while _G[name .. "Tab" .. i] do
		local tab = _G[name .. "Tab" .. i]
		Reskin.Tab(tab, store)

		local w = widths[i]
		if tab.SetSize then tab:SetSize(w, TAB_H) end

		-- Where the client had it, before we move it. Off has to put it back.
		if tab.__aetherAnchor == nil and tab.GetPoint then
			local p = { tab:GetPoint() }
			tab.__aetherAnchor = (p[1] and p) or false
			if tab.GetWidth then tab.__aetherSize = { tab:GetWidth(), tab:GetHeight() } end
		end

		-- Only the SPACING is ours. The first tab stays exactly where the client
		-- put it and the rest chain off it, so the row keeps the height the
		-- frame was built around - re-anchoring it to our glass moved the whole
		-- strip up into the weapon slots.
		if last then
			tab:ClearAllPoints()
			tab:SetPoint("LEFT", last, "RIGHT", TAB_GAP, 0)
		elseif tab.__aetherAnchor then
			-- Keep the client's HEIGHT, take our own LEFT. Blizzard's x suits
			-- its own tab widths; ours start where the glass does.
			local a = tab.__aetherAnchor
			local relPoint = a[3]
			local x = a[4]
			if type(relPoint) == "string" and relPoint:find("LEFT") then
				local entry = PN.ENTRY and PN.ENTRY[name]
				local ins = entry and entry.insets
				x = (ins and ins[1] or 0) + TAB_EDGE
			end
			tab:ClearAllPoints()
			tab:SetPoint(a[1], a[2], relPoint, x, a[5])
		else
			-- No anchor of its own to keep. Better a row in the right place
			-- than a row nowhere: without this the whole strip is unanchored.
			local entry = PN.ENTRY and PN.ENTRY[name]
			local ins = entry and entry.insets
			tab:ClearAllPoints()
			tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",
				(ins and ins[1] or 0) + TAB_EDGE, (ins and ins[4] or 0) + TAB_GAP)
		end
		last = tab

		StyleTabState(tab)

		-- The selection only changes on a click, so that is where it is worth
		-- answering. Hooked once per tab.
		if tab.HookScript and not tab.__aetherTabHook then
			tab.__aetherTabHook = true
			tab:HookScript("OnClick", function()
				if not PN.enabled then return end
				local n = 1
				while _G[name .. "Tab" .. n] do
					StyleTabState(_G[name .. "Tab" .. n])
					n = n + 1
				end
			end)
		end

		i = i + 1
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
		if pane then Reskin.Strip(pane, store) end
	end

	-- Who you are, above the sheet.
	local who = _G.CharacterNameText
	if who and who.SetText then
		W.Restyle(who, "tbTitle")
		W.Color(who, Palette.c.text)
	end
	local rank = _G.CharacterLevelText
	if rank and rank.SetText then
		W.Restyle(rank, "tbCardSub")
		W.Color(rank, Palette.c.textDim)
	end

	EachEquipSlot(function(slot)
		Reskin.Slot(slot)
		SlotQuality(slot)
	end)

	LayoutTabs(frame, store)

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
			W.Restyle(label, "tbCardTitle")
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

--- Interiors, by frame. A window with no entry gets the shell treatment only.
local INTERIORS = {
	CharacterFrame = DressCharacter,
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
			local close = Reskin.Element(frame, "CloseButton")
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
			while name and _G[name .. "Tab" .. n] do
				local tab = _G[name .. "Tab" .. n]
				if tab.__aetherAnchor then
					tab:ClearAllPoints()
					tab:SetPoint(unpack(tab.__aetherAnchor))
				end
				if tab.__aetherSize and tab.SetSize then
					tab:SetSize(tab.__aetherSize[1], tab.__aetherSize[2])
				end
				tab.__aetherAnchor, tab.__aetherSize = nil, nil
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
