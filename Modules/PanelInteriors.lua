--[[--------------------------------------------------------------------------

	PanelInteriors.lua - the insides of the client's own windows.

	THE OTHER HALF OF Modules/Panels.lua, and split off it rather than
	designed apart. That file is the SHELL: it reads the entry table, puts
	glass behind a window, and lays out the four standard components - header
	band, body well, footer strip, tab rail. This file is the INSIDES: one
	dresser per window, each reaching into somebody else's frames by name.

	The two were one file until 2026-09-01, when it reached 7,400 lines and 193
	top-level locals. Lua 5.1 allows a function - and a chunk is a function -
	exactly 200, so it was seven names from refusing to load, and three windows
	in a row had been squeezed under the limit by folding their constants into
	a table that did not want them.

	THE SEAM WAS ALREADY THERE. `PN.INTERIORS` is a table keyed by frame name,
	read in exactly one place, so the dressers were never coupled to the shell:
	nothing in here is called from Panels.lua except through that table.

	WHERE THE LINE FALLS. Anything every window gets is the shell's - the tab
	rail lives there, not here, even though the character sheet was the first
	window to need one. Anything one window needs is a dresser's, and its
	measurements come with it.

	What this file borrows is published on PN where it is declared. If you add
	a borrowing, publish it there rather than reaching into Panels.lua's
	locals, which are not visible across files.

----------------------------------------------------------------------------]]

local ADDON, A = ...

-- GetModule, not NewModule: this is one module continued in a second file, and
-- NewModule asserts against a duplicate name. Modules/IFEC does the same
-- across Console, Player and Reader.
local PN = A:GetModule("panels")

local W, Palette, Reskin, Media = A.Widgets, A.Palette, A.Reskin, A.Media

-- The shell's own helpers, taken once rather than reached through PN at every
-- call site: some of these are used hundreds of times below.
local Part, Roled, CHAR = PN.Part, PN.Roled, PN.CHAR
local Dress, DressClose, CloseButton = PN.Dress, PN.DressClose, PN.CloseButton
local PANELS = PN.PANELS
local FONT_BUMP, SKILL_HEAD, SKILL_BAR_H = PN.FONT_BUMP, PN.SKILL_HEAD, PN.SKILL_BAR_H
local MAIL_TAB_DROP = PN.MAIL_TAB_DROP
local TabLabel, TabAt, StyleTabState = PN.TabLabel, PN.TabAt, PN.StyleTabState
local LayoutTabs, InstallTabHooks = PN.LayoutTabs, PN.InstallTabHooks

-- ---------------------------------------------------------------------------
-- Measurements and helpers the dressers use and the shell does not, moved
-- here with them: each was a name on the shell's locals list, paying rent
-- in the chunk that had run out of room.
-- ---------------------------------------------------------------------------

-- Letters on a page of the inbox. Seven, and the client pages rather than
-- scrolls: the postbox holds fifty and shows a page of these at a time, which
-- is what its Prev and Next are for.
local MAIL_ROWS     = 7

-- Item slots on a letter, which the client also places from Lua.
local MAIL_ATTACHMENTS = 16

-- Rows a side in the trade window. Six goods and the enchant slot, which is
-- the seventh and sits in a recess of its own below the other six.
local TRADE_ROWS    = 7

-- Rows the client hangs off the WINDOW for the two faux-scrolling lists here.
local IGNORE_ROWS      = 19

local WHO_ROWS         = 17

-- The who list's columns, each a sort control with its own stone tab art.
local WHO_COLUMNS      = 5

-- Ink below this is the client writing for parchment; ink above it is the
-- client meaning something - a gold subject, a red loss.
local RECEIPT_DARK  = 0.5

--- A page turn: two chevrons and the number between them.
--
--  ONE OF THESE, EVERYWHERE. Four windows page - the spellbook, the postbox,
--  a book you are reading and the vendor - and each had grown its own
--  answer. The spellbook's is the one to keep, so this is it: bare chevrons
--  on the buttons, the count between them in subtitle type, and nothing
--  round any of the three. 15c - a chevron means navigation, and navigation
--  reads as chrome rather than as an action you choose.
--
--  THE VENDOR'S WAS THE ODD ONE: its turns kept the client's words in a pill
--  of ours. The words are anchored OUTSIDE their own buttons - Prev's to the
--  right of it, Next's to the left - so both landed in the middle, on top of
--  the page number. Reskin.PageTurn takes them off, which is why it walks the
--  button's regions rather than asking for its label.
--
--  AND THE NUMBER IS CUT TO ITS WORDS. The client gives these strings a box
--  far wider than what is in them - 104 on the vendor, 192 in a book, for
--  "Page 1" - and a string draws centred in its box however little it says.
--  So a row that measures the WORDS, as the footer strip correctly does,
--  reserves forty units for something that paints a hundred and four, and the
--  ends of it slide under whatever is beside it.
local function DressPager(prev, nxt, label, store)
	Reskin.PageTurn(prev, "LEFT", store)
	Reskin.PageTurn(nxt, "RIGHT", store)
	if not label then return nil end

	Roled(label, "pnSub")
	W.Color(label, Palette.c.textDim)
	if label.SetWidth then label:SetWidth(0) end
	if label.SetJustifyH then label:SetJustifyH("CENTER") end
	return label
end

-- Between the vendor's two repair buttons. The client's own is TWO, which is
-- close enough that two surfaces with a rim on them read as one shape with a
-- seam down it - and looked, correctly, like an overlap.
local REPAIR_GAP      = 8

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
	-- WHICHEVER THING THE CONTROL IS. Era gives a faction header a row of its
	-- own, ReputationHeaderN, and the row IS the button. Cataclysm folded the
	-- headers into the ordinary rows, so on Mists the control is a child of
	-- ReputationBarN - and is hidden on every row that is not a header, which
	-- takes our mark with it exactly as it takes Blizzard's.
	for n = 1, (_G.NUM_FACTIONS_DISPLAYED or 0) do
		Reskin.Collapse(Part({ "ReputationHeader" .. n,
		                       "ReputationBar" .. n .. "ExpandOrCollapseButton" }))
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
	-- Cataclysm rebuilt the sheet. The attribute panes became one scrolling
	-- CharacterStatsPane of collapsible groups, the slots moved into a frame of
	-- their own, and the pet's numbers went to PetPaperDollPetInfo. None of
	-- those names exist on Era and none of Era's exist on Mists, so the list
	-- carries both and the loop takes whichever the client has.
	"CharacterStatsPane", "PaperDollItemsFrame", "PetPaperDollPetInfo",
}

--- The stat groups inside that pane, which carry their own stone.
--
--  Each group draws its own top, middle and bottom slice rather than
--  inheriting the pane's, so stripping the pane leaves seven banded blocks of
--  Blizzard's parchment down the side of our glass.
local STAT_GROUPS = 7

-- Where its own plus sat: Char-Stat-Plus is anchored 5 in from the group's
-- top-left and is 16 wide, so its middle is 13.
local STAT_GROUP_MARK_X = 13

-- The chevron on the sheet's expand arrow, inside a 32px button.
local EXPAND_CHEV = 11

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
--  WHATEVER THE CLIENT DRAWS THE DOLL IN. Era uses a PlayerModel called
--  CharacterModelFrame with the two turn buttons named off it. Cataclysm
--  replaced it with a ModelScene called CharacterModelScene and moved the
--  controls into a ControlFrame on it under parent keys - so the old names
--  find nothing on Mists and the sheet keeps Blizzard's stone backdrop behind
--  the character, which is the one thing on that window you actually look at.
--  The pet kept its PlayerModel on both.
local MODEL_HOSTS = {
	Character = { "CharacterModelScene", "CharacterModelFrame" },
	Pet       = { "PetModelFrame" },
}

--- The two buttons that turn one of those, WHEN THEY ARE OURS TO MOVE.
--
--  Only the pair the client leaves loose. A ModelScene keeps its five
--  controls - zoom in and out, turn left and right, reset - in one row that
--  ModelSceneControlFrameMixin:UpdateLayout anchors end to end and re-anchors
--  whenever it runs, so pulling two of the five into the model's corner both
--  breaks the row that is left and is undone by the client's next layout.
--  Blizzard's row is a coherent thing; ours would be two of its pieces.
local function ModelTurners(prefix)
	return _G[prefix .. "ModelFrameRotateLeftButton"],
	       _G[prefix .. "ModelFrameRotateRightButton"]
end

local function DressModel(prefix, store)
	local model = Part(MODEL_HOSTS[prefix] or (prefix .. "ModelFrame"))
	if not model then return end

	Reskin.Strip(model, store)
	local left, right = ModelTurners(prefix)
	for _, btn in ipairs({ right or false, left or false }) do
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

	W.RotatePair(model, left, right)

	-- AND THE ROW OF FIVE, WHERE THERE IS ONE. A ModelScene keeps zoom in and
	-- out, turn left and right, and reset in a ControlFrame that
	-- ModelSceneControlFrameMixin:UpdateLayout anchors end to end and re-anchors
	-- whenever it runs - which is why the pair above is not pulled out of it.
	--
	-- Not moving them is not the same as leaving them alone. Every one is a
	-- grey stone plate out of the common-button-square-gray atlas with the
	-- picture on a SEPARATE 16x16 Icon texture centred on it, so the plate can
	-- come off and the picture stay - the same division as the resistance
	-- chips' school icons and the spellbook's school tabs, and the same rule:
	-- the picture IS the information and the stone is not.
	--
	-- Left as they were, five stone squares sat on the glass over the one thing
	-- on that window you actually look at.
	local controls = model.ControlFrame
	if controls then
		for _, key in ipairs({ "zoomInButton", "zoomOutButton",
			"rotateLeftButton", "rotateRightButton", "resetButton" }) do
			local btn = controls[key]
			if btn and not Reskin.Forbidden(btn) then
				Reskin.ClearButton(btn)
				-- ITS OWN ICON KEPT, and nothing else: the plate is a normal
				-- texture and comes off above, but a control button can carry
				-- decoration in ordinary regions too.
				if type(store) == "table" then
					Reskin.StripExcept(btn, store, btn.Icon and { btn.Icon } or nil)
				end
			end
		end
	end
end

--- One of the client's own recesses, dressed as our well - and brought down to
--- meet the content if it is the one the header has to clear.
--
--  THE STANDARD ANSWER FOR A WINDOW WHOSE PANES ARE ALREADY RECESSES. The
--  trainer and the trade window have said so for months with `wells = false`;
--  Cataclysm's rebuilds - the character sheet, the spellbook - are the same
--  case and were each getting a body well of ours drawn round the client's,
--  with their content then moved out of the client's to line up with it.
--
--  ITS TOP CORNER ONLY, WHERE IT MOVES AT ALL. The far corner of one of these
--  can be the client's to hold: the character sheet's is rewritten by
--  UpdateSize on every tab change, pinned either a fixed width from the
--  window's LEFT edge or a margin from its RIGHT. Cached and put back it spans
--  the whole window and pushes whatever follows it off the glass.
--
--  Setting the same point twice costs nothing, which is what makes this safe
--  to call from a hook that runs whenever the client resizes.
local function ClientRecess(frame, path, x, y)
	local ins = Part(path)
	if not ins then return nil end

	ins.__aetherStore = ins.__aetherStore or {}
	Reskin.Strip(ins, ins.__aetherStore)
	Reskin.Well(ins, { corner = W.WELL_CORNER, inset = { 0, 0, 0, 0 },
		fill = "wellFill", edge = "wellEdge" })

	if frame and x and y and frame.__aetherBodyShift then
		PN.MoveRecess(ins, frame, x, y + frame.__aetherBodyShift)
	end
	return ins
end

--- Put one of the client's recesses where a well goes, keeping its far corner.
--
--  CLEARED AND RE-SET, NOT SET AGAIN. A frame accumulates anchors: setting
--  TOPLEFT a second time without clearing leaves the region spanned between
--  two of them, and every getter still answers about the FIRST - which reads
--  exactly like it worked. The harness says so where it records a point, and
--  the talent window's recess sat at the client's own 60 for a build because
--  of it.
--
--  The far corner is the client's business - on the character sheet UpdateSize
--  rewrites it per tab - so it is read back and re-applied rather than
--  invented.
--- Seat one of the client's recesses as our well, growing the window for it.
--
--  THE CLIENT'S CONTENT IS DRAWN TO THE SIZE OF ITS OWN RECESS. Insetting that
--  recess to our padding takes the difference away from content laid out at a
--  fixed size, and it is clipped rather than reflowed - which on the talent
--  window put Learn on top of the last two spells.
--
--  So the frame grows by exactly what our padding costs on each edge, and the
--  recess keeps at least the room the client gave it. Recorded, because this
--  runs on every dress and a growth applied twice walks the window off screen.
function PN.SeatRecess(ins, frame, top, bottom)
	if not (ins and frame and ins.ClearAllPoints) then return end
	bottom = bottom or W.PANEL_PAD
	local pad = W.PANEL_PAD

	-- THE SIZE THE CLIENT'S CONTENT WAS DRAWN FOR, remembered once. Not its
	-- INSETS: those are state, not a size. The four template helpers move this
	-- recess about between tabs, so "what the insets were" depends entirely on
	-- when you looked, and the growth computed from it came out different every
	-- time. The one thing that does not move is how much room the page needs.
	local want = frame.__aetherRecessWant
	if not want and ins.GetWidth and (ins:GetWidth() or 0) > 0 then
		want = { w = ins:GetWidth(), h = ins:GetHeight() }
		frame.__aetherRecessWant = want
	end

	-- GROW UNTIL IT FITS, EVERY TIME, rather than once behind a flag. A
	-- boolean guard cannot answer a requirement that CHANGES - putting Learn
	-- in a footer strip took another 44 units out of the recess and the window
	-- never grew for it, because it had already "been grown". Recomputed, this
	-- is naturally idempotent: once the room is there the growth is nought.
	if want and frame.SetWidth and frame.GetWidth then
		local haveW = (frame:GetWidth() or 0) - pad * 2
		local haveH = (frame:GetHeight() or 0) - top - bottom
		if want.w - haveW > 0.5 then
			frame:SetWidth(frame:GetWidth() + (want.w - haveW))
		end
		if want.h - haveH > 0.5 then
			frame:SetHeight(frame:GetHeight() + (want.h - haveH))
		end
	end

	ins:ClearAllPoints()
	ins:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -top)
	ins:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, bottom)

	-- ...AND THE CLIENT MOVES IT BACK, four different ways.
	--
	-- ButtonFrameTemplate_HideAttic and _ShowAttic re-anchor the Inset's
	-- TOPLEFT; _HideButtonBar and _ShowButtonBar re-anchor its BOTTOMRIGHT.
	-- Every tab on the talent window calls a different combination of them -
	-- the glyph tab hides the attic, hiding it shows the button bar - which is
	-- why each tab came out wrong in a DIFFERENT way and why every fix moved
	-- the problem somewhere else rather than ending it.
	--
	-- Seated once at dress time, our answer survives exactly until the player
	-- changes tab. So the four are hooked and the seat re-applied after them,
	-- for whichever frames we have seated. The growth is not repeated: that is
	-- guarded above.
	--
	-- THE GLYPH TAB IS LEFT ITS OWN RIGHT EDGE deliberately. GlyphFrame_OnShow
	-- narrows the Inset by 197 to make room for the glyph list beside it, and
	-- it does that AFTER calling HideAttic - so its BOTTOMRIGHT lands after
	-- ours and wins, while our TOPLEFT still holds. That is the correct
	-- outcome rather than an accident: the list needs the room.
	frame.__aetherRecessSeat = { top = top, bottom = bottom }
	if not PN.__atticHook and hooksecurefunc then
		PN.__atticHook = true
		for _, fn in ipairs({ "ButtonFrameTemplate_HideAttic",
			"ButtonFrameTemplate_ShowAttic",
			"ButtonFrameTemplate_HideButtonBar",
			"ButtonFrameTemplate_ShowButtonBar" }) do
			if type(_G[fn]) == "function" then
				hooksecurefunc(fn, function(self)
					local seat = self and self.__aetherRecessSeat
					if not (PN.enabled and seat and self.Inset) then return end
					pcall(PN.SeatRecess, self.Inset, self, seat.top, seat.bottom)
				end)
			end
		end
	end
end

function PN.MoveRecess(ins, frame, x, y)
	if not (ins and frame and ins.ClearAllPoints) then return end
	local far = { ins:GetPoint(2) }
	ins:ClearAllPoints()
	ins:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
	if far[1] then
		ins:SetPoint(far[1], far[2], far[3], far[4], far[5])
	end
end

--- The paper doll's sidebar, which only Mists has.
--
--  Three tabs down the right-hand recess - Stats, Titles, Equipment Manager -
--  and a pane behind each. None of it existed before Cataclysm and none of it
--  was touched here, so on that client the whole column was Blizzard's: three
--  stone tabs, two parchment panes and a pair of stone buttons under them.
--
--  THE TABS ARE NAMED AND THE PANES ARE NOT. PaperDollSidebarTab1..3 are
--  globals; the panes are parent keys on PaperDollFrame with no globals at
--  all, the same shape as the gossip window's scroll box - so they are reached
--  by path.
local SIDEBAR_PANES = {
	"PaperDollFrame.TitleManagerPane",
	"PaperDollFrame.EquipmentManagerPane",
}

local function DressSidebar(store)
	local bar = Part("PaperDollSidebarTabs")
	if bar then Reskin.Strip(bar, store) end

	for i = 1, 3 do
		local tab = Part("PaperDollSidebarTab" .. i)
		if tab then
			-- THE STONE OFF AND THE PICTURE KEPT, which is this sheet's third
			-- instance of the same division and the reason StripExcept is a
			-- primitive. A sidebar tab carries three textures and only the
			-- middle one is information: TabBg is the stone, Hider is a strip
			-- of art that covers the selected tab's bottom edge, and Icon is
			-- the picture - your own portrait on the first, an atlas cut on the
			-- other two. Swept whole, the column becomes three blank squares
			-- and nothing says which is which.
			Reskin.ClearButton(tab)
			if type(store) == "table" then
				Reskin.StripExcept(tab, store, tab.Icon and { tab.Icon } or nil)
			end
		end
	end

	for _, path in ipairs(SIDEBAR_PANES) do
		local pane = Part(path)
		if pane then
			Reskin.Strip(pane, store)
			Reskin.Fonts(pane, "pnBody")

			if pane.ScrollBar then Reskin.ScrollBar(pane.ScrollBar, store) end

			-- ITS ROWS ARE POOLED, as every ScrollBox's are: acquired during
			-- layout, so the set you can see now is not the set that will be
			-- there after the next update. Walked on every dress for the same
			-- reason the gossip window's options are.
			local box = pane.ScrollBox
			if box then
				local function lift(row)
					if row then Reskin.Fonts(row, "pnBody", 0, Palette.c.text) end
					if row and type(store) == "table" then
						Reskin.Strip(row, store)
					end
				end
				if box.ForEachFrame then
					if not pcall(box.ForEachFrame, box, lift) and box.GetFrames then
						local ok, rows = pcall(box.GetFrames, box)
						if ok and rows then for _, r in ipairs(rows) do lift(r) end end
					end
				elseif box.GetFrames then
					local ok, rows = pcall(box.GetFrames, box)
					if ok and rows then for _, r in ipairs(rows) do lift(r) end end
				end
			end

			-- Equip and Save under the list. Named off a parent that has no
			-- name of its own, so neither is a global either.
			--
			-- Spelled out rather than through DressWideButton, which is
			-- declared several hundred lines below this and would be nil here -
			-- the file runs top to bottom and a local is not hoisted.
			for _, key in ipairs({ "EquipSet", "SaveSet" }) do
				local btn = pane[key]
				if btn then
					Reskin.ClearButton(btn)
					Reskin.Strip(btn, store)
					Reskin.Button(btn, "pnBody")
				end
			end
		end
	end
end

--- Saving an equipment set: the name field and the icon picker.
--
--  THE LAST PIECE OF THIS SHEET, and the only part of it that is a DIALOG
--  rather than a panel - so it is treated the way the client's other dialogs
--  are, in Modules/Popups.lua: stripped, given glass of its own, and its
--  contents dressed in place. A PANELS entry would have wrapped it in a header
--  band and a footer strip, and it has neither a title nor a close button to
--  put in them.
--
--  It is a child of PaperDollFrame, so it is already at our scale and already
--  moves with the sheet. Nothing here re-anchors anything.
--- One icon in the picker, cell and all.
--
--  NOT Reskin.Slot, WHICH IS THE OBVIOUS ANSWER AND THE WRONG ONE. Slot clears
--  the button's states first and looks for the picture in an IconTexture or an
--  Icon region afterwards - which is right for every item button in the game,
--  and exactly backwards here: on these the picture IS the normal texture, so
--  Slot rubs it out and then draws a cell round the hole.
--
--  IconButton is the primitive that knows the difference - it skips whichever
--  state holds the picture - so the sequence is IconButton for the art and the
--  cell drawn afterwards with that same texture handed to it.
local function PickerIcon(btn, store)
	if not btn or Reskin.Forbidden(btn) then return end
	local icon = btn.GetNormalTexture and btn:GetNormalTexture()
	Reskin.IconButton(btn, store, { icon = icon })
	if not btn.__aetherSlot then
		W.DecorateSlot(btn, (btn.GetWidth and btn:GetWidth()) or 36,
			{ icon = icon, count = false })
		btn.__aetherSlot = true
	end
end

local function DressGearPopup(store)
	local popup = Part("GearManagerPopupFrame")
	if not popup then return end

	-- Its own backing is a plain black fill at eight tenths, not stone - a
	-- SCRIM, which is what a dialog over a window wants and what our glass
	-- already is. Left in place it sits behind the glass as a second darker
	-- pane and the frosting reads as muddy rather than translucent.
	Reskin.Strip(popup, store)
	Reskin.Panel(popup)

	local box = popup.BorderBox
	if not box then return end

	Reskin.Fonts(popup, "pnBody")

	-- OKAY AND CANCEL, which live on the border box rather than on the dialog.
	for _, key in ipairs({ "OkayButton", "CancelButton" }) do
		local btn = box[key]
		if btn then
			Reskin.ClearButton(btn)
			Reskin.Strip(btn, store)
			Reskin.Button(btn, "pnBody")
		end
	end

	-- THE ICON YOU HAVE CHOSEN. Its picture is the button's NORMAL texture
	-- here, not a separate region - so ClearButton would rub out the very
	-- thing the dialog is for. IconButton is the primitive that knows the
	-- difference: it keeps whichever texture is the picture and clears the
	-- states around it.
	local area = box.SelectedIconArea
	if area and area.SelectedIconButton then
		PickerIcon(area.SelectedIconButton, store)
	end

	-- THE NAME FIELD, whose border is three slices of the class trainer's
	-- filter art - which is why it looked like a dropdown rather than
	-- somewhere to type.
	if box.IconSelectorEditBox then
		Reskin.EditBox(box.IconSelectorEditBox)
	end

	-- THE KIND OF ICON FILTER. Reached through PN rather than through the
	-- local: DressDropdown is declared a thousand lines below this and a Lua
	-- local is not hoisted, so naming it here is naming nil. The sidebar's
	-- buttons hit the same wall a moment ago and were spelled out instead;
	-- a dropdown is too much to spell out twice.
	if box.IconTypeDropdown and PN.DressDropdown then
		PN.DressDropdown(box.IconTypeDropdown, store)
	end

	-- AND THE GRID. Its buttons are pooled by the scroll box, so they are
	-- walked on every dress for the same reason the saved sets are - and each
	-- one's picture is its normal texture, the same as the chosen icon above.
	local grid = popup.IconSelector
	local scroll = grid and (grid.ScrollBox or grid)
	if scroll then
		local function lift(btn) PickerIcon(btn, store) end
		if scroll.ForEachFrame then
			if not pcall(scroll.ForEachFrame, scroll, lift) and scroll.GetFrames then
				local ok, rows = pcall(scroll.GetFrames, scroll)
				if ok and rows then for _, b in ipairs(rows) do lift(b) end end
			end
		elseif scroll.GetFrames then
			local ok, rows = pcall(scroll.GetFrames, scroll)
			if ok and rows then for _, b in ipairs(rows) do lift(b) end end
		end
	end
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
	for n = 1, STAT_GROUPS do
		local group = Part("CharacterStatsPaneCategory" .. n)
		if group then
			Reskin.Strip(group, store)
			Reskin.Fonts(group, "pnBody")

			-- ITS MARK BACK, ON THE LEFT WHERE ITS OWN WAS. The group draws the
			-- plus and minus as two textures on ITSELF rather than on a button,
			-- so the strip above takes them and leaves the row with nothing
			-- saying it opens. The toolbar is the whole 169px header, so a glyph
			-- centred on it lands in the middle of the category's name.
			local bar = Part("CharacterStatsPaneCategory" .. n .. "Toolbar")
			-- AND IT HAS TO TELL US. A stat group carries `collapsed` only
			-- while it is shut: PaperDollFrame_ExpandStatCategory clears
			-- the field rather than setting it false, so an open group is
			-- a group with no state on it at all.
			local glyph = Reskin.Collapse(bar, nil, not group.collapsed)
			if glyph and bar then
				glyph:ClearAllPoints()
				glyph:SetPoint("LEFT", bar, "LEFT", STAT_GROUP_MARK_X, 0)
			end
		end
	end

	local rank = _G.CharacterLevelText
	if rank and rank.SetText then W.Color(rank, Palette.c.textDim) end

	-- AND THE CLIENT PUTS THE SUBTITLE BACK WHERE IT WANTS IT.
	--
	-- PaperDollFrame_SetLevel does not merely set the words: it re-anchors
	-- CharacterLevelText to TOP, -36, centred on the WINDOW - and nudges it ten
	-- either way depending on whether the stat panel is out. It runs on login
	-- and on every expand and collapse, so the band we had just put it in lasted
	-- until the first time the sheet changed width.
	--
	-- What that looked like: "Level 85 Affliction Warlock" printed below the
	-- header's hairline instead of inside the band, and sliding right across the
	-- gear when the stat panel opened. Centred on a window that had grown, it
	-- landed on the right-hand column of slots.
	--
	-- Third time on this window - the slot borders, the expand arrow, and now
	-- this - so it is the same answer: hook the thing that repaints.
	if not PN.__dollLevelHook and hooksecurefunc
		and type(_G.PaperDollFrame_SetLevel) == "function" then
		PN.__dollLevelHook = true
		hooksecurefunc("PaperDollFrame_SetLevel", function()
			if PN.enabled then pcall(PN.RefreshHeader, "CharacterFrame") end
		end)
	end

	-- AND THE PET TAB'S TITLE IS A CLIENT BUG WE HAVE TO REPAIR.
	--
	-- Cata\CharacterFrame.lua builds `characterFrameDisplayInfo` as a LOCAL
	-- table at file scope, and the pet's entry reads
	--
	--     ["PetPaperDollFrame"] = { title = UnitPVPName("pet"), ... }
	--
	-- which is evaluated ONCE, when Blizzard_CharacterFrame loads - before you
	-- have a pet, so it is empty for the rest of the session. Nothing ever
	-- refreshes it: the OnEvent handler updates `["Default"].title` on
	-- UNIT_NAME_UPDATE and PLAYER_PVP_RANK_CHANGED, and both branches skip
	-- outright while the pet pane is up.
	--
	-- PetPaperDollFrame_Update writes the real name over the top, and
	-- CharacterFrameMixin:UpdateTitle writes the stale blank back. Which of the
	-- two ran last is the whole difference between a title bar saying "Piptik"
	-- and one saying nothing, and it is not ours to order - RefreshDisplay
	-- calls UpdateSize, UpdateTabBounds, UpdatePortrait and UpdateTitle in a
	-- row, and anything that resizes this window reaches it.
	--
	-- So: after the client sets the title, if the pet pane is up and the pet
	-- has a name, put the name back. Not inventing a title - this is the exact
	-- string PetPaperDollFrame_Update itself writes, from the client's own API.
	--
	-- The band needs no telling. It REPARENTS this font string rather than
	-- copying it, and $parentTitleText inside the unnamed TitleContainer and
	-- the global CharacterFrameTitleText are ONE OBJECT - which `/aether panels
	-- measure` settled by marking both lines, after the XML had implied they
	-- were two.
	if frame and not PN.__petTitleHook and hooksecurefunc
		and type(frame.UpdateTitle) == "function" then
		PN.__petTitleHook = true
		hooksecurefunc(frame, "UpdateTitle", function()
			if not PN.enabled then return end
			local pane = _G.PetPaperDollFrame
			if not (pane and pane.IsShown and pane:IsShown()) then return end
			local name = UnitPVPName and UnitPVPName("pet")
			local title = _G.CharacterFrameTitleText
			if title and title.SetText and name and name ~= "" then
				title:SetText(name)
			end
		end)
	end


	-- THE ARROW THAT WIDENS THE SHEET, which only Mists has. It carries three
	-- states of Blizzard's spellbook page-turn art - up, down and disabled -
	-- and the picture and the plate are ONE texture here, unlike the model's
	-- controls, so there is nothing to keep: the button is cleared and given a
	-- chevron of ours, which is the right glyph for once. This one really is
	-- navigation - it turns the sheet from the narrow page to the wide one.
	local expand = _G.CharacterFrameExpandButton
	if expand and not expand.__aetherChevron then
		Reskin.ClearButton(expand)
		if type(store) == "table" then Reskin.Strip(expand, store) end

		-- AND SOMETHING PUT BACK, because a cleared button with nothing on it
		-- is an invisible button. The model's controls keep their own pictures;
		-- this one cannot - all three of its states are Blizzard's page-turn
		-- art with the arrow baked into the plate - so it gets a chevron of
		-- ours. Which is the right glyph for once: a chevron means navigation,
		-- and this genuinely turns the sheet from its narrow page to its wide
		-- one.
		local chev = expand:CreateTexture(nil, "OVERLAY")
		chev:SetTexture(Media.texture.chevron)
		chev:SetSize(EXPAND_CHEV, EXPAND_CHEV)
		chev:SetPoint("CENTER", expand, "CENTER", 0, 0)
		expand.__aetherChevron = chev
	end
	-- AND IT PAINTS ITSELF BACK. CharacterFrameMixin:Expand and :Collapse each
	-- set all three of this button's textures afresh, so clearing it once holds
	-- exactly until the first time the player uses it. Same shape as the slot
	-- borders below, and the same answer: hook the thing that repaints.
	--
	-- The hook also carries the layout. UpdateSize writes the window's WIDTH
	-- outright from the tab you are on, and it runs after us as often as
	-- before - so a window we had grown to fit our padding was put back to the
	-- client's number a moment later, and one we had not grown yet stayed too
	-- narrow. "Opens too wide, then when you open the character info panel it's
	-- not wide enough" is that race, seen from both sides. Re-laying it out
	-- from the client's own resize makes the order fixed instead of lucky.
	if frame and not PN.__charSizeHook and hooksecurefunc
		and type(frame.UpdateSize) == "function" then
		PN.__charSizeHook = true
		hooksecurefunc(frame, "UpdateSize", function(self)
			if not PN.enabled then return end
			pcall(PN.LayoutBody, self, PN.ENTRY and PN.ENTRY.CharacterFrame)
			local ins = _G.CharacterFrameInset
			if ins and self.__aetherBodyShift then
				ins:SetPoint("TOPLEFT", self, "TOPLEFT",
					CHAR.insetX, -(CHAR.insetY + self.__aetherBodyShift))
			end
			local btn = _G.CharacterFrameExpandButton
			if btn and btn.__aetherChevron then
				Reskin.ClearButton(btn)
				W.FaceChevron(btn.__aetherChevron,
					self.Expanded and "LEFT" or "RIGHT")
			end
		end)
	end

	if expand and expand.__aetherChevron then
		W.Color(expand.__aetherChevron, Palette.c.textDim)
		-- WHICH WAY IT POINTS IS WHICH WAY IT GOES. The client swaps its own
		-- art between next-page and prev-page in Expand and Collapse, so ours
		-- has to answer the same question - and the flag it sets is the honest
		-- place to ask it.
		W.FaceChevron(expand.__aetherChevron,
			(frame and frame.Expanded) and "LEFT" or "RIGHT")
	end

	EachEquipSlot(function(slot)
		Reskin.Slot(slot)
		SlotQuality(slot)
	end)

	LayoutTabs(frame, store)
	InstallTabHooks()

	ClientRecess(frame, "CharacterFrameInset", CHAR.insetX, CHAR.insetY)

	-- AND THE RECESS COMES DOWN TO MEET THE PANES.
	--
	-- ITS TOP CORNER ONLY, AND NEVER THROUGH THE BODY LIST. Putting the two
	-- insets in that list looked right and was not: the mover caches a pane's
	-- points the first time it touches one and re-applies them for ever, and
	-- CharacterFrameInset's BOTTOMRIGHT is not ours to cache - UpdateSize
	-- rewrites it on every tab change, pinning it either 338 from the window's
	-- LEFT edge (the doll and pet tabs, which want a fixed-width recess) or 6
	-- from its RIGHT (everything else). Frozen at the wrong one the recess
	-- spanned the whole window and pushed InsetRight, and with it the entire
	-- stat panel, clean off the glass.
	--
	-- So only the TOPLEFT is touched, which is static XML and nobody else's.
	-- InsetRight hangs off this one's TOPRIGHT and the expand arrow off its
	-- BOTTOMRIGHT, so both come with it, and setting the same point twice
	-- costs nothing - which is what makes this safe to run from a hook that
	-- fires whenever the client resizes.
	-- The stat panel's recess follows the first one's TOPRIGHT, so it needs no
	-- drop of its own - only the skin.
	ClientRecess(nil, "CharacterFrameInsetRight")

	-- AND THE STAT PANEL SCROLLS, on a MinimalScrollBar that had been left
	-- Blizzard's - a grey bar down our glass beside seven groups of numbers in
	-- our lettering.
	local statsPane = Part("CharacterStatsPane")
	if statsPane and statsPane.ScrollBar then
		Reskin.ScrollBar(statsPane.ScrollBar, store)
	end

	DressSidebar(store)
	DressGearPopup(store)

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
	--
	-- AND NOT $parentAtWarCheck, WHICH IS NOT A CHECK BOX. The name reads like
	-- one and it was reskinned as one; ReputationBarTemplate declares it
	--
	--   <Frame name="$parentAtWarCheck" hidden="true">
	--
	-- a 24x22 frame holding the crossed swords, shown when you are at war with
	-- that faction. An INDICATOR, with no OnClick and never any - so the hook
	-- inside Reskin.CheckBox threw:
	--
	--   ReputationBar15AtWarCheck:HookScript(): Doesn't have a "OnClick" script
	--
	-- and took the whole character sheet's dressing down with it. Once per
	-- open, too, rather than once ever: Toggle sets its hooked flag BEFORE it
	-- hooks, so each attempt died on the next bar that had not been reached
	-- yet, and the sheet came up undressed for as many opens as there are
	-- faction rows. Fifteen of them, which is the number in the report.
	--
	-- The swords are LEFT AS THEY ARE, for the same reason the resistance
	-- chips above keep their school icons: the picture is the information, and
	-- there is no glass equivalent of "at war".
	for n = 1, (_G.NUM_FACTIONS_DISPLAYED or 0) do
		local bar = _G["ReputationBar" .. n]
		if bar then Reskin.StatusBar(bar, store) end
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

--- Which panes this window has, asked of the client rather than written down.
--
--  Era's are the doll and Honor; Cataclysm dropped Honor for PVP and added
--  Talents and Guild. INSPECTFRAME_SUBFRAMES is what InspectFrameTab_OnClick
--  itself reads, so it is the honest source - and Era's list written here for
--  both flavours meant three of Mists' four pages were never swept.
--
--  The items frame is not a subframe and is not in that list: it is nested
--  inside the doll pane and carries the slots.
local function InspectPanes()
	local panes = { "InspectPaperDollItemsFrame" }
	local subs = _G.INSPECTFRAME_SUBFRAMES
	if type(subs) == "table" then
		for i = 1, #subs do panes[#panes + 1] = subs[i] end
	else
		panes[#panes + 1] = "InspectPaperDollFrame"
		panes[#panes + 1] = "InspectHonorFrame"
	end
	return panes
end

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
	for _, name in ipairs(InspectPanes()) do
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

	-- The rank progress bar, under whichever pane this client puts it on:
	-- Era draws it on the honour tab, Mists on the PVP one that replaced it.
	Reskin.StatusBar(_G.InspectHonorFrameProgressBar
		or _G.InspectPVPFrameProgressBar, store)

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
	-- ITS OWN RECESS IS STRIPPED AND NOT USED. ButtonFrameTemplate gives this
	-- window an Inset the way it gives the character sheet one, but nothing in
	-- the book is anchored to it - so its stone comes off and our own body well
	-- is drawn where a body well goes.
	local ins = Part("SpellBookFrame.Inset")
	if ins then
		ins.__aetherStore = ins.__aetherStore or {}
		Reskin.Strip(ins, ins.__aetherStore)
	end

	-- AND THE THREE NEW PAGES ARE PRINTED ON PARCHMENT.
	--
	-- Professions, Core Abilities and "What has changed?" are near-black
	-- throughout - headings, descriptions and all - because that is what reads
	-- on the paper the client drew them for. On glass it is a page you cannot
	-- read at all, which is what Joe was looking at: three tabs of dark grey on
	-- dark blue.
	--
	-- The lighten argument is the whole answer and it is already here: any
	-- string dark enough to have been meant for parchment is lifted, a gold
	-- heading is left saying what it was put there to say, and Reskin.Ink
	-- catches the ones whose black is an escape INSIDE the text rather than a
	-- colour on the font string.
	--
	-- FROM DEPTH NOUGHT, which is the deepest and not the shallowest: the
	-- third argument is where the walk STARTS and it stops at four, so a large
	-- number is less reach rather than more. Written as three first, on the
	-- reasoning that these nest a level or two - and it reached one level
	-- instead of four. A profession is a frame holding a heading, a
	-- description and a progress bar with text of its own.
	local function LiftPages()
		for _, page in ipairs(CHAR.pages) do
			local pane = Part(page)
			if pane then
				Reskin.Strip(pane, store)
				Reskin.Fonts(pane, "pnBody", 0, Palette.c.text)

				-- THE PAGE'S OWN NAME - "Affliction", "Warlock" - which the
				-- client draws in CoreAbilityFont, forty points of it, as a
				-- heading over the list. Lifted with everything else it came up
				-- white and enormous, shouting over the window's actual title
				-- two lines above it. It is a heading for the page, so it is
				-- roled as one and dimmed: our type, our size, quietly.
				local head = pane.SpecName or pane.ClassName
				if head then
					Roled(head, "pnSub")
					W.Color(head, Palette.c.textDim)

					-- AND INSIDE THE WELL, CLEAR OF ITS RIM. The client hangs
					-- it at the top of the page, which after the page has been
					-- moved down puts it hard on the recess's top line - so it
					-- reads as a label stuck to the edge rather than a heading
					-- over the list. Placed in the well at the well's own
					-- padding, which is where every other heading in this
					-- interface sits.
					local well = frame and frame.__aetherBody
					if well and head.ClearAllPoints then
						head:ClearAllPoints()
						head:SetPoint("TOP", well, "TOP", 0, -W.WELL_PAD)
					end
				end
			end
		end
	end
	LiftPages()

	-- AND AGAIN WHENEVER THE CLIENT BUILDS A ROW.
	--
	-- Both of these pages mint their contents LAZILY - SpellBook_GetCoreAbility
	-- and SpellBook_GetWhatChangedItem each CreateFrame on first use - so a
	-- sweep at dress time reaches whatever happened to exist at that moment,
	-- which was the first row and nothing else. That is exactly what Joe saw:
	-- one line lifted and the rest still on parchment.
	--
	-- Hooked on the two update functions rather than on the panes' OnShow: the
	-- rows are minted DURING the update, so a hook on show runs before half of
	-- them exist. Same shape as the gossip window's pooled options.
	if not PN.__bookPageHook and hooksecurefunc then
		PN.__bookPageHook = true
		for _, fn in ipairs({ "SpellBook_UpdateCoreAbilitiesTab",
			"SpellBook_UpdateWhatHasChangedTab" }) do
			if type(_G[fn]) == "function" then
				hooksecurefunc(fn, function()
					if PN.enabled then pcall(LiftPages) end
				end)
			end
		end
	end

	-- The page number, which the client draws in near-black because it is
	-- printing it on parchment. On glass that is a page number you cannot read.
	-- THE PAGE TURN, which is the one every other window's is copied from.
	local page = DressPager(_G.SpellBookPrevPageButton,
		_G.SpellBookNextPageButton, _G.SpellBookPageText, store)
	-- And between the two arrows rather than off in the bottom corner: the
	-- corner it was in is where the book's tabs sit now. Placement is this
	-- window's own - the vendor's three are laid out by the footer strip.
	if page and page.ClearAllPoints then
		page:ClearAllPoints()
		-- BESIDE THE ARROWS, WHERE THEY ARE. Era puts its pair at the foot of
		-- the book and the number reads as centred between them; Mists puts
		-- both hard in the BOTTOM RIGHT corner, so a number centred on the
		-- window's foot floated in the middle of the page with the arrows off
		-- in the corner on their own.
		local prev = _G.SpellBookPrevPageButton
		if A.isMists and prev then
			page:SetPoint("RIGHT", prev, "LEFT", -W.PANEL_GAP, 0)
		else
			page:SetPoint("CENTER", frame, "BOTTOM", 0, PAGE_TURNER_Y)
		end
	end

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

--- The talent window Mists rebuilt: six tiers of three, and two spec pages.
--
--  A DIFFERENT WINDOW UNDER THE SAME NAME. Era's is the parchment tree -
--  thirty talents with thirty branches and thirty arrows drawn between them -
--  and every name the Era dresser below reaches for describes something this
--  client does not build.
--
--  Its own recess is its well, because all three panes are anchored to
--  PlayerTalentFrameInsetBg rather than to the frame: the same case as the
--  character sheet's, and the reason `wells = false` is on this entry.
-- On PN rather than a local: this file's main chunk is at Lua 5.1's ceiling
-- of 200 locals in a function, and one more name will not load. See the note in
-- [[mists-port]] - the file needs splitting, not another squeeze.
function PN.DressMistsTalents(frame, store)
	-- THE RECESS IS THIS WINDOW'S WELL, so it is put where a well goes: a body
	-- padding below the header band. Everything on the window is anchored to
	-- it and follows it, which is why nothing here is in the body list.
	--
	-- Not ClientRecess's shift-by-__aetherBodyShift, which is for a window
	-- whose panes move too: with an empty body list there is no shift, and the
	-- client's own 60 leaves six units under a band of 54.
	local ins = ClientRecess(nil, "PlayerTalentFrame.Inset")
	if ins and frame then
		-- ALL FOUR SIDES, AND THE WINDOW GROWS TO PAY FOR THEM.
		--
		-- Seating only the TOP left the client's own 4, 6 and 26 on the other
		-- three, so there was room above the content and none beside or below.
		-- Seating all four without growing the frame is the other half of the
		-- same mistake: this window is 646 by 468 and the client's recess is
		-- 636 by 382, which is exactly what the specialization page is drawn
		-- to fill. Insetting that to our padding takes 26 across and 12 down
		-- AWAY from content laid out at a fixed size, so the page is clipped
		-- and Learn ends up over the last two spells.
		--
		-- Every other window in this module grows by what its shift costs.
		-- This one has an empty body list - its panes are anchored to the
		-- recess and must not move - so nothing was growing it. The recess is
		-- what moved, so the recess is what the window has to pay for.
		--
		-- Measured off the FRAME rather than the glass: the glass reaches 34
		-- below the frame to carry the tab row, so a padding taken from its
		-- bottom would put the recess on top of the tabs.
		-- ...AND STOPPING ABOVE THE FOOTER STRIP, which is where Learn now
		-- lives. Without that the recess ran down to the tab rail and the
		-- client's own action row sat in the gap between the two.
		PN.SeatRecess(ins, frame,
			(frame.__aetherHeadH or W.PANEL_HEAD_H) + W.PANEL_PAD,
			W.PANEL_FOOT_H + W.PANEL_PAD)
	end

	for _, name in ipairs({ "PlayerTalentFrameSpecialization",
		"PlayerTalentFramePetSpecialization", "PlayerTalentFrameTalents" }) do
		local pane = Part(name)
		if pane then
			Reskin.Strip(pane, store)
			Reskin.Fonts(pane, "pnBody", 0, Palette.c.text)
		end
	end

	-- SIX TIERS, reached as PlayerTalentFrameTalents["tier"..n]. Parent keys
	-- with no globals of their own, which is how the client's own code walks
	-- them - and a sweep that only knows globals reaches none of it.
	local talents = Part("PlayerTalentFrameTalents")
	for tier = 1, CHAR.tiers do
		local row = talents and talents["tier" .. tier]
		if row then
			-- The row's own furniture: a tiled backing, two caps, three
			-- separators and the two glow lines that mark the chosen tier.
			Reskin.Strip(row, store)

			-- WHAT LEVEL THE TIER UNLOCKS AT, which the client draws large and
			-- gold down the left of each row. It is a heading for the row, so
			-- it is roled as one rather than left shouting.
			if row.level then
				Roled(row.level, "pnSub")
				W.Color(row.level, Palette.c.textDim)
			end

			for col = 1, 3 do
				local b = row["talent" .. col]
				if b then
					-- THE PICTURE IS A REGION AND THE SLOT IS THE BORDER ROUND
					-- IT, the same division as the sidebar tabs and the model
					-- controls. Swept whole, every talent in the tree loses its
					-- icon and the window becomes eighteen empty boxes.
					-- NOT A CELL, WHICH IS THE MISTAKE THIS WINDOW INVITES. A
					-- talent is a WIDE ROW - 190 by 50, with a 40px icon at one
					-- end and the talent's name beside it - and Reskin.Slot
					-- sizes its cell from the BUTTON, so every icon came out
					-- stretched into an oval the width of the row.
					--
					-- Exactly the vendor's rows and the quest's reward items,
					-- both of which say so where they are dressed. The picture
					-- keeps the size the client gave it and gets a cell of its
					-- own around it, not around the row.
					Reskin.ClearButton(b)
					if type(store) == "table" then
						Reskin.StripExcept(b, store, b.icon and { b.icon } or nil)
					end
					-- ...AND NOT DECORATED AT ALL. DecorateSlot does
					-- icon:SetAllPoints(f) on the frame it is handed, so the
					-- size argument does not constrain it: a cell round this
					-- button stretches the picture across all 190 units however
					-- small a size it is given. The icon keeps the 40 the client
					-- gave it, which is what the vendor's rows do.
					if b.name then
						Roled(b.name, "pnBody")
						W.Color(b.name, Palette.c.text)
					end
				end
			end
		end
	end

	-- LEARN, on both specialization pages, under a parent key rather than a
	-- name - so neither is reachable as a global.
	-- ALL THREE PANES HAVE ONE, not just the two specialization pages: the
	-- talents pane declares its own $parentLearnButton the same way. Dressing
	-- two of the three left one Blizzard plate on the tab a player uses most.
	for _, name in ipairs({ "PlayerTalentFrameSpecialization",
		"PlayerTalentFramePetSpecialization", "PlayerTalentFrameTalents" }) do
		local pane = Part(name)
		local btn = pane and pane.learnButton
		if btn then
			Reskin.ClearButton(btn)
			Reskin.Strip(btn, store)
			Reskin.Button(btn, "pnBody")
		end
	end

	-- AND THE GLYPH PAGE, once its addon has turned up. Blizzard_GlyphUI is
	-- load-on-demand, so this is nothing on the first dress and everything on
	-- the one after PN:Skin runs for its ADDON_LOADED.
	--
	-- Hooked on the frame's own OnShow as well: its list rows are pooled and
	-- minted by the client's update, so a sweep at dress time reaches whatever
	-- happened to exist then.
	local gf = Part("GlyphFrame")
	if gf then
		PN.DressGlyphs(store)
		if gf.HookScript and not gf.__aetherGlyphWatch then
			gf.__aetherGlyphWatch = true
			gf:HookScript("OnShow", function()
				if not PN.enabled then return end
				pcall(PN.DressGlyphs, store)
				-- AND THE STRIP, because this page brings its own reagent line
				-- with it. GlyphFrame is not one of the window's panes - it is
				-- another addon's frame parented in - so WatchPanes never hears
				-- about it and the footer was never re-laid when it came up.
				pcall(PN.RefreshFooter, "PlayerTalentFrame")
			end)
		end
	end

	-- The spec tabs down the side, which this flavour actually uses.
	for i = 1, 3 do
		local tab = Part("PlayerSpecTab" .. i)
		if tab then
			Reskin.ClearButton(tab)
			if type(store) == "table" then
				Reskin.StripExcept(tab, store,
					tab.icon and { tab.icon } or nil)
			end
		end
	end
end

--- The glyph page, which is a second addon parented into the talent window.
--
--  Blizzard_GlyphUI is load-on-demand and GlyphFrame sets its OWN parent, size
--  and anchors: it fills PlayerTalentFrameInset +3/-3, and GlyphFrame_OnShow
--  narrows that recess by 197 to leave room for the list beside it. So this is
--  not a pane of the talent window in any sense our entry table understands,
--  and it gets dressed from here rather than declared there.
--
--  THE WHEEL STAYS. It is a picture the player is reading - which socket is
--  which, which are unlocked and at what level - and the six sockets are
--  positioned ON it. Sweeping it leaves six rings floating in the dark, which
--  is exactly what the flight map does and says so where it is dressed.
--  Everything AROUND the wheel is ours: the list beside it, its recess, the
--  search field, the filter and the reagent line under it.
-- The three units GlyphFrame is inset by inside the talent window's recess.
local GLYPH_PAD = 3

function PN.DressGlyphs(store)
	local gf = Part("GlyphFrame")
	if not gf then return end

	-- ITS NATURAL SIZE, AND NOT THE RECESS'S.
	--
	-- GlyphFrame is told to FILL PlayerTalentFrameInset, and everything on it
	-- is placed from a corner or from the middle of the frame rather than from
	-- the art:
	--
	--   the wheel   a FIXED 437x413 texture pinned TOPLEFT
	--   the sockets CENTER 110,43 / 0,156 / -155,-109 and so on
	--   the list    TOPLEFT to the frame's BOTTOMRIGHT, +4,358
	--
	-- So a frame bigger than the wheel moves its own centre away from the
	-- wheel's - the six rings drift out of their painted holes - and moves its
	-- bottom-right corner down, taking the search box, the filter and the whole
	-- list down with it. Growing the window for our padding did exactly that.
	--
	-- The frame is therefore sized to the wheel and anchored by its TOP LEFT
	-- alone. Then its centre IS the wheel's centre and its bottom-right is
	-- where the client drew it, whatever the recess round it is doing.
	local bg = gf.background
	if bg and bg.GetWidth and (bg:GetWidth() or 0) > 0 then
		local ins = Part("PlayerTalentFrame.Inset")
		if ins then
			gf:ClearAllPoints()
			gf:SetPoint("TOPLEFT", ins, "TOPLEFT", GLYPH_PAD, -GLYPH_PAD)
			-- Plus the one unit the wheel is inset by at each side, so the two
			-- centres coincide exactly.
			gf:SetSize(bg:GetWidth() + 2, bg:GetHeight())
		end
	end

	-- THE LIST'S OWN RECESS, dressed as a well the way the sheet's two are.
	if gf.sideInset then
		gf.sideInset.__aetherStore = gf.sideInset.__aetherStore or {}
		Reskin.Strip(gf.sideInset, gf.sideInset.__aetherStore)
		Reskin.Well(gf.sideInset, { corner = W.WELL_CORNER,
			inset = { 0, 0, 0, 0 }, fill = "wellFill", edge = "wellEdge" })
	end

	-- WHAT YOU ARE LOOKING FOR, and what you are looking through. The field
	-- carries the client's own magnifier, which is the picture rather than the
	-- border, so it is kept.
	local box = Part("GlyphFrameSearchBox")
	if box then
		Reskin.EditBox(box, { keep = box.searchIcon and { box.searchIcon } or nil })
	end
	if gf.FilterDropdown and PN.DressDropdown then
		PN.DressDropdown(gf.FilterDropdown, store)
	end

	local scroll = gf.scrollFrame
	if scroll then
		Reskin.ScrollFrame(scroll, store)
		if scroll.scrollBar then Reskin.ScrollBar(scroll.scrollBar, store) end
		if scroll.ScrollBar then Reskin.ScrollBar(scroll.ScrollBar, store) end

		-- ITS ROWS ARE POOLED by HybridScrollFrame_CreateButtons, so they are
		-- walked on every dress rather than once - the same as the spellbook's
		-- core abilities and the gossip window's options.
		for _, row in ipairs(scroll.buttons or {}) do
			-- A WIDE ROW, NOT A CELL: an icon at one end and the glyph's name
			-- beside it. The talent rows taught this three windows ago.
			Reskin.ClearButton(row)
			if type(store) == "table" then
				Reskin.StripExcept(row, store, row.icon and { row.icon } or nil)
			end
			Reskin.Fonts(row, "pnBody", 0, Palette.c.text)
		end
	end

	-- MAJOR AND MINOR, which are collapsing headers on Blizzard's own
	-- CollapsibleHeader art - three slices and a stone plus or minus.
	for _, header in ipairs(gf.headers or {}) do
		Reskin.ClearButton(header)
		if type(store) == "table" then Reskin.Strip(header, store) end
		Reskin.Fonts(header, "pnBody", 0, Palette.c.text)
		Reskin.Collapse(header, nil, header.expandedIcon
			and header.expandedIcon:IsShown())
	end
end

local function DressTalents(frame, store)
	-- MISTS REBUILT THIS WINDOW ENTIRELY. Everything below describes Era's
	-- parchment tree, and none of those names exist on the other client.
	if A.isMists then return PN.DressMistsTalents(frame, store) end

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

-- Panes whose contents are POOLED ROWS out of a modern scroll box.
--
--  A ScrollBox does not own its rows: it acquires them from a pool during its
--  own layout and hands them back when they scroll out, so what is in the list
--  when the window is dressed is not what is in it a moment later. Stripping
--  the PANE reaches none of them - a row's plaque is its own NORMAL TEXTURE,
--  setAllPoints, out of Interface\GuildFrame\GuildFrame - which is why the
--  roster came up as our glass with a column of the client's stone plaques on
--  it.
local COMM_LISTS = { "MemberList", "CommunitiesList", "ApplicantList" }

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
	local skin = Reskin.Button(btn, "pnBody")

	-- THE OLD DROPDOWN'S FRAME IS WIDER THAN THE BOX YOU CAN SEE.
	--
	-- UIDropDownMenuTemplate - the generation the group finder still uses, with
	-- Left, Middle and Right background regions - reserves a margin either side
	-- for art that overhangs its own bounds. So a backing drawn to the FRAME
	-- comes out fifteen units too wide at the left and six at the right, and
	-- that is the overrun: the box ran past the recess beside it.
	--
	-- The numbers are ElvUI's, from HandleHonorDropdown in its Mists PVP skin,
	-- which insets its backdrop by exactly this to sit on the visible box.
	-- Constants read off the template once, not a measurement.
	if skin and skin.ClearAllPoints and (btn.Left or btn.Middle or btn.Right) then
		skin:ClearAllPoints()
		skin:SetPoint("TOPLEFT", btn, "TOPLEFT", 14, -2)
		skin:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 10)
	end

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
-- Published so DressGearPopup can reach it: that runs a thousand lines
-- above this and a Lua local is not hoisted.
PN.DressDropdown = DressDropdown

--- One line of a roster.
--
--  KEEPING THE CLASS GLYPH AND THE VOICE LAMP. Both are regions of the row in
--  the same layer the plaque behind them is drawn in, so a plain strip takes
--  the two things the row is telling you along with the stone.
local function DressCommRow(row, store)
	if not row or not row.GetRegions then return end

	Reskin.ClearButton(row)
	row.__aetherStore = row.__aetherStore or {}
	Reskin.StripExcept(row, row.__aetherStore,
		{ "Class", "VoiceChatStatusIcon", "ExpandedIcon", "CollapsedIcon" })
	Reskin.Fonts(row, "pnBody", 1, Palette.c.text)
end

--- A pane's scroll box, where it has one.
local function CommBox(frame, key)
	local pane = Reskin.Element(frame, key)
	return pane and Reskin.Element(pane, "ScrollBox") or nil
end

--- Whatever each of those lists is SHOWING at this moment.
--
--  ForEachFrame first, for the reason the gossip window's rows use it:
--  GetFrames hands back a list, and a list obtained a moment too early is a
--  list of the rows that were there before the rebuild.
local function DressCommRows(frame, store)
	for _, key in ipairs(COMM_LISTS) do
		local box = CommBox(frame, key)
		if box then
			local function lift(row) DressCommRow(row, store) end
			local walked = false
			if box.ForEachFrame then
				walked = pcall(box.ForEachFrame, box, lift)
			end
			if not walked and box.GetFrames then
				local ok, rows = pcall(box.GetFrames, box)
				if ok and rows then
					for _, row in ipairs(rows) do lift(row) end
				end
			end
		end
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

	-- AND THE ROWS IN THE THREE LISTS, which stripping the panes never reached.
	DressCommRows(frame, store)

	-- ...AND AGAIN EVERY TIME ONE OF THEM IS LAID OUT. A ScrollBox acquires
	-- its rows from a pool during its OWN Update, after the window's has
	-- returned, and hands them back when they scroll out - so a row scrolled
	-- into view later is a row nobody has been near.
	--
	-- On the box's own Update, which is where the gossip window's rows are
	-- caught for exactly the same reason. Hooking the window instead reads the
	-- set that was there before layout, and looks intermittent rather than
	-- broken: whether a row was dressed depended on whether the pool happened
	-- to hand back one that already had been.
	for _, key in ipairs(COMM_LISTS) do
		local box = CommBox(frame, key)
		if hooksecurefunc and box and box.Update and not box.__aetherCommRows then
			box.__aetherCommRows = true
			hooksecurefunc(box, "Update", function()
				if PN.enabled then DressCommRows(frame, store) end
			end)
		end
	end

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

--- The vendor's two repair buttons, on the row the buyback slot is on.
--
--  THE LAST ROW OF THE GRID IS HALF EMPTY. The client hangs the buyback slot
--  53 below the tenth item, in the RIGHT column, and nothing is ever drawn
--  beside it - so the repair pair goes in the left half of that row, level
--  with it. What you can sell back and what you can repair read as one line,
--  and the strip below is left to the page turn and your purse.
--
--  The client pins them to the window's own bottom-left corner, which is
--  where our footer strip now is, so the pair sat across its hairline. And it
--  spaces them TWO units apart, which is close enough that two surfaces with
--  a rim on them read as one shape with a seam down it.
--
--  AGAIN AFTER THE CLIENT, EVERY TIME, AND IN THE CLIENT'S OWN DIRECTION.
--
--  MerchantFrame_UpdateRepairButtons runs on every merchant update and
--  re-places all three - and it does NOT clear their points first, so its
--  SetPoints are added to whatever is already there. Two things follow.
--
--  The first is that anchoring the pair the other way round is an ERROR, not
--  a cosmetic problem: the client anchors RepairItem off RepairAll, so ours
--  hanging RepairAll off RepairItem closed a loop and the client's own
--  SetPoint threw "Cannot anchor to a region dependent on it". So RepairAll
--  takes the row and RepairItem hangs off it, which is the client's
--  direction and cannot cycle whatever either of us does.
--
--  The second is that placing them once is not enough - the next update adds
--  the client's corners back alongside ours and stretches both buttons
--  between two anchors. So this runs from the dresser AND from a hook on
--  that function, and clears every point each time.
local function PlaceRepair()
	local buy = _G.MerchantBuyBackItem
	local col = _G.MerchantItem1 and _G.MerchantItem1.ItemButton
	local one, all = _G.MerchantRepairItemButton, _G.MerchantRepairAllButton
	if not (buy and col and one and all) then return false end

	-- MEASURED off the two frames rather than copied from the client's layout:
	-- they are the two columns of one grid, so the distance between them is the
	-- grid's own and stays true whatever the window is doing.
	local colX = col.GetLeft and col:GetLeft()
	local buyX = buy.GetLeft and buy:GetLeft()
	if not (colX and buyX) then return false end

	-- The right-hand button takes the row, and the left one hangs off it.
	local wide = (one.GetWidth and one:GetWidth()) or 36
	all:ClearAllPoints()
	all:SetPoint("TOPLEFT", buy, "TOPLEFT",
		(colX - buyX) + wide + REPAIR_GAP, 0)
	one:ClearAllPoints()
	one:SetPoint("RIGHT", all, "LEFT", -REPAIR_GAP, 0)

	-- AND THE LABEL UNDER THE PAIR IT NAMES. The client clears this one's
	-- points and puts it 14 in from the window's bottom-left corner, which is
	-- now the footer strip - so it has to be moved again here with them.
	local label = _G.MerchantRepairText
	if label and label.ClearAllPoints then
		label:ClearAllPoints()
		label:SetPoint("TOPLEFT", one, "BOTTOMLEFT", 0, -4)
		if label.SetJustifyH then label:SetJustifyH("LEFT") end
	end
	return true
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

	-- AND THEY GO ON THE ROW THE BUYBACK SLOT IS ON - see PlaceRepair, which
	-- has to run again after the client every time, and says why.
	PlaceRepair()
	if hooksecurefunc and _G.MerchantFrame_UpdateRepairButtons
		and not PN.__repairHook then
		PN.__repairHook = true
		hooksecurefunc("MerchantFrame_UpdateRepairButtons", function()
			if PN.enabled then PlaceRepair() end
		end)
	end

	local repairLabel = _G.MerchantRepairText
	if repairLabel then
		Reskin.Font(repairLabel, "pnBody", Palette.c.text)
		W.Color(repairLabel, Palette.c.textDim)
	end

	-- THE PAGE TURN, which is now the spellbook's like every other one.
	--
	-- It used to keep the client's words in a pill of ours, on the argument
	-- that "Prev" and "Next" already said which way they went. They did, and
	-- they said it in the wrong place: each word is anchored OUTSIDE its own
	-- button, so both landed in the middle - on top of the page number, which
	-- is what got reported. Two chevrons and the count between them.
	DressPager(_G.MerchantPrevPageButton, _G.MerchantNextPageButton,
		_G.MerchantPageText, store)

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
			-- AND A CARET, which the two fields above get through
			-- Reskin.EditBox and this one does not: the letter itself is a
			-- ScrollingEditBox and the box you type in is inside it.
			Reskin.Caret(eb)
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
	DressPager(_G.InboxPrevPageButton, _G.InboxNextPageButton, nil, store)

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

	Reskin.ScrollFrame(_G.ItemTextScrollFrame, store)

	-- The page turn, which is the spellbook's - see DressPager. ITS COUNT IS
	-- 192 WIDE AND SAYS "Page 1", which is the case that rule is written
	-- against.
	DressPager(_G.ItemTextPrevPageButton, _G.ItemTextNextPageButton,
		_G.ItemTextCurrentPage, store)
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

--- One line of the friends list.
--
--  KEEPING THE LAMP AND THE BADGE. A row's backing, the little online lamp and
--  the game badge are all regions of the same button in the same two layers,
--  so a plain strip takes the two things the row is actually telling you along
--  with the plaque behind them.
--
--  The backing goes. The client does not draw it from a file - it calls
--  SetColorTexture on it with a different colour for online, offline and
--  Battle.net - and what that colour says is said twice over anyway: the lamp
--  says online, and an offline name is printed grey. Hiding it holds, because
--  SetColorTexture paints a texture rather than showing one.
local function DressFriendRow(row, store)
	if not row or not row.GetRegions then return end

	Reskin.ClearButton(row)
	row.__aetherStore = row.__aetherStore or {}
	Reskin.StripExcept(row, row.__aetherStore, { "status", "gameIcon" })

	local name = Reskin.Element(row, "name")
	if name then
		Reskin.Font(name, "pnBody")
	end
end

--- A row in one of the two faux-scrolling lists - ignore, or who.
--
--  Not a friends row: these carry no art of their own beyond the client's
--  highlight, and the who row is five strings rather than one.
local function DressListRow(btn)
	if not btn then return end
	Reskin.ClearButton(btn)
	Reskin.Fonts(btn, "pnBody", 1, Palette.c.text)
end

--- The social window: friends, ignore, who, the guild and the raid.
--
--  FIVE PANES AND ONE ROW OF CHROME. Everything the player acts with lives on
--  the window rather than on the pane that owns it, so the strip and the tool
--  row are laid out from whatever is VISIBLE and the panes themselves are only
--  swept.
local function DressFriends(frame, store)
	-- ITS OWN FOUR TABS, AND FIRST. Nothing in here ever laid them out, so the
	-- only thing that reached them was the client's resize hook - and in
	-- between they were whatever the button sweep at the foot of this function
	-- had made of them, which is the pill every pressable thing in this
	-- interface wears. That is what "a different tab type" was: a tab drawn as
	-- a button, over the top of a tab.
	--
	-- FIRST rather than last, because the sweep skips anything already dressed
	-- as a tab and cannot skip what does not exist yet.
	LayoutTabs(frame, store)

	-- THE PANES, and the client's own recess behind them. FriendsFrameInset is
	-- moved by the client per tab - 83 down on Friends, 80 on Who, 60 on Raid
	-- - which is a stone box being re-placed inside our glass on every switch.
	for _, name in ipairs({ "FriendsListFrame", "IgnoreListFrame", "WhoFrame",
		"GuildFrame", "RaidFrame", "RaidFrameNotInRaid", "FriendsTabHeader",
		"FriendsFrameInset", "WhoFrameListInset", "FriendsFrameBattlenetFrame" }) do
		local pane = _G[name]
		if pane then
			pane.__aetherStore = pane.__aetherStore or {}
			Reskin.Strip(pane, pane.__aetherStore)
		end
	end

	-- THE FRIENDS TAB'S OWN TABS, which are tabs and are dressed as tabs -
	-- they are the same control the window's four are, one level in.
	for i = 1, 2 do
		local tab = _G["FriendsTabHeaderTab" .. i]
		if tab then
			tab.__aetherStore = tab.__aetherStore or {}
			Reskin.Tab(tab, tab.__aetherStore, "pnBody")
		end
	end

	-- THE THREE LISTS, each in a recess. The friends list is a hybrid scroll
	-- with its rows inside it; the other two are faux scrolls, which are a
	-- scroll BAR and nothing else.
	for _, name in ipairs({ "FriendsFrameFriendsScrollFrame",
		"FriendsFrameIgnoreScrollFrame", "WhoListScrollFrame" }) do
		Reskin.ScrollFrame(_G[name], store)
	end

	-- WHO IS IN THE LIST. The friends rows are pooled by the hybrid scroll and
	-- handed out as the list grows, so they are reached through it rather than
	-- by name; the other two lists' rows are named and fixed.
	local hybrid = _G.FriendsFrameFriendsScrollFrame
	for _, row in ipairs((hybrid and hybrid.buttons) or {}) do
		DressFriendRow(row, store)
	end
	for i = 1, IGNORE_ROWS do
		DressListRow(_G["FriendsFrameIgnoreButton" .. i])
	end
	for i = 1, WHO_ROWS do
		DressListRow(_G["WhoFrameButton" .. i])
	end

	-- AND THE HEADINGS OVER THE IGNORE LIST - Ignored, Blocked Invites, Muted
	-- - which are frames with one string in them.
	for _, name in ipairs({ "FriendsFrameIgnoredHeader",
		"FriendsFrameBlockedInviteHeader", "FriendsFrameMutedHeader" }) do
		local head = _G[name]
		if head then
			head.__aetherStore = head.__aetherStore or {}
			Reskin.Strip(head, head.__aetherStore)
			Reskin.Fonts(head, "pnHead", 1, Palette.c.textDim)
		end
	end

	-- THE WHO LIST'S FIVE COLUMNS, each a sort control drawn as three slices
	-- of WhoFrame-ColumnTabs. A column head is not an action you press, so it
	-- gets no surface - the art comes off and the word is re-inked, which is
	-- what every other list heading in this interface looks like.
	local columns = {}
	for i = 1, WHO_COLUMNS do
		local head = _G["WhoFrameColumnHeader" .. i]
		if head then
			columns[head] = true
			Reskin.ClearButton(head)
			head.__aetherStore = head.__aetherStore or {}
			local label = head.GetFontString and head:GetFontString()
			Reskin.StripExcept(head, head.__aetherStore,
				label and { label } or nil)
			if label then
				Reskin.Font(label, "pnHead")
				W.Color(label, Palette.c.textDim)
			end
		end
	end

	-- WHO YOU ARE ON BATTLE.NET: a status dropdown, your tag, and the button
	-- that sets what you are broadcasting. The dropdown is the modern
	-- WowStyle1 control the trade skill's filters are, so it takes the same
	-- dressing; the tag is a string in the client's Battle.net blue, which is
	-- a second accent nothing else in the window uses.
	DressDropdown(_G.FriendsFrameStatusDropdown, store)
	local bnet = _G.FriendsFrameBattlenetFrame
	if bnet then
		if bnet.Tag then
			Reskin.Font(bnet.Tag, "pnBody")
			W.Color(bnet.Tag, Palette.c.textDim)
		end
		-- THE BROADCAST BUTTON IS A PICTURE, not a word - so it gets the icon
		-- treatment rather than a surface with a label on it.
		Reskin.IconButton(bnet.BroadcastButton, store)
	end

	-- THE QUERY, which is a search box: three slices of border, a magnifying
	-- glass and a clear button. The glass is the FIELD's mark and stays.
	Reskin.EditBox(_G.WhoFrameEditBox, { keep = { "searchIcon" } })
	Reskin.EditBox(_G.FriendsFrameBroadcastInput)
	-- AND WHAT THE QUERY FOUND STAYS AT THE FOOT OF THE LIST, which is where
	-- the client has it and where a count of what you are looking at belongs.
	-- It is anchored to the SEARCH BOX rather than to the list - BOTTOM to the
	-- box's TOP - so moving the box into the tool row took the count up under
	-- the band with it, where it read as a subtitle for the window.
	--
	-- Off the footer's own hairline, not off the list: the list keeps the
	-- height the client gave it and stops well short of the body's floor, so a
	-- count hung under the list floats in the middle of the window.
	local totals = _G.WhoFrameTotals
	if totals then
		Reskin.Font(totals, "pnBody")
		W.Color(totals, Palette.c.textDim)
		local floor = frame.__aetherFootRule
		if floor and totals.ClearAllPoints then
			totals:ClearAllPoints()
			totals:SetPoint("BOTTOM", floor, "TOP", 0, W.PANEL_GAP)
		end
	end

	-- THE RAID TAB. A switch, a paragraph telling you what a raid is, and two
	-- buttons - one in the strip and one in the tool row.
	Reskin.CheckBox(_G.RaidFrameAllAssistCheckButton, store)
	local blurb = _G.RaidFrameRaidDescription
	if blurb then
		Reskin.Font(blurb, "pnBody")
		W.Color(blurb, Palette.c.textDim)
	end

	-- EVERY BUTTON ON EVERY PANE. They are children of the panes rather than
	-- of the window, so one sweep of the window reaches none of them.
	--
	-- BUT NOT THE COLUMN HEADS. Every one of the five is a Button with a label
	-- on it and a child of the who pane, which is exactly what this sweep
	-- looks for - so all five came back as pressable surfaces. A column head
	-- is something you read, the same argument that keeps a letter in the
	-- postbox from being drawn as a button.
	for _, name in ipairs({ "FriendsListFrame", "IgnoreListFrame", "WhoFrame",
		"RaidFrame", "FriendsFrame" }) do
		Reskin.Buttons(_G[name], "pnBody", columns)
	end

	-- AND AGAIN WHENEVER A LIST IS REFILLED, because the friends list GROWS
	-- ITS ROWS ON DEMAND and we are the reason it does.
	--
	-- HybridScrollFrame_CreateButtons makes as many rows as fit the box's
	-- height and adds more whenever that height changes - and changing it is
	-- precisely what this file does to every window it dresses. So the rows
	-- that exist when the dresser runs are not the rows the player ends up
	-- looking at, and the ones made afterwards would be the only stone left in
	-- the window.
	--
	-- The other two lists are refilled rather than grown, and are re-inked
	-- here for the same reason at no extra cost.
	-- THE WHOLE WINDOW AGAIN AFTER THE CLIENT HAS FINISHED SWAPPING PANES,
	-- because the pane hooks cannot see the end of that swap from inside it.
	--
	-- TWO SEPARATE FAULTS, ONE CAUSE. FriendsFrame_ShowSubFrame loops the
	-- five panes with `pairs`, so the order is arbitrary: the one going UP
	-- can be shown before the one coming DOWN is hidden. Our OnShow hook
	-- fires in that gap and lays the strip out from a window that is briefly
	-- showing two panes - which is Convert to Raid taking a slot in the
	-- friends list's strip and pushing its two buttons off both sides.
	--
	-- And the RAID pane never fires OnShow at all. RaidFrame is shown from
	-- the moment its addon loads - no `hidden` in its XML - so the client's
	-- own Show() on it is a no-op and no hook of ours runs. First visit to
	-- that tab came up with the blurb still under the band, Convert to Raid
	-- wherever the last pane had left it, and only the tool row correct,
	-- because that one is redrawn by the tab hook instead.
	--
	-- A POST-HOOK ON FriendsFrame_Update ANSWERS BOTH: it runs after the
	-- claim and after the swap, with exactly one pane up, every time the
	-- client changes its mind about which. Guarded because dressing a window
	-- is not something to do twice from inside itself.
	PN.__friendHooks = PN.__friendHooks or {}
	if hooksecurefunc and _G.FriendsFrame_Update
		and not PN.__friendHooks.FriendsFrame_Update then
		PN.__friendHooks.FriendsFrame_Update = true
		hooksecurefunc("FriendsFrame_Update", function()
			if not PN.enabled or PN.__friendSettling then return end
			-- The client calls this on a who result and on joining or leaving
			-- a group as well as on a tab, and none of that is worth a pass
			-- over a window nobody is looking at.
			local social = _G.FriendsFrame
			if not (social and social.IsShown and social:IsShown()) then return end
			PN.__friendSettling = true
			pcall(PN.Dress, social)
			PN.__friendSettling = nil
		end)
	end

	for _, fn in ipairs({ "FriendsList_Update", "IgnoreList_Update",
		"WhoList_Update" }) do
		if hooksecurefunc and _G[fn] and not PN.__friendHooks[fn] then
			PN.__friendHooks[fn] = true
			hooksecurefunc(fn, function()
				if not PN.enabled then return end
				local box = _G.FriendsFrameFriendsScrollFrame
				for _, row in ipairs((box and box.buttons) or {}) do
					DressFriendRow(row, store)
				end
				for i = 1, IGNORE_ROWS do
					DressListRow(_G["FriendsFrameIgnoreButton" .. i])
				end
				for i = 1, WHO_ROWS do
					DressListRow(_G["WhoFrameButton" .. i])
				end
			end)
		end
	end
end

-- ---------------------------------------------------------------------------
-- the group finder
-- ---------------------------------------------------------------------------
--
-- Two windows behind two tabs: the listing you post and the browse you search
-- with. Both panes are setAllPoints to LFGParentFrame, so neither has a point
-- to move by and every piece of content is hung off a pane at its own fixed
-- distance - the social window's shape exactly, one window on.
--
-- WHAT IS DIFFERENT is that this one is the OLD parchment build carrying
-- MODERN content: a WowScrollBoxList for its results and two WowStyle1
-- dropdowns for its filters, inside a frame whose background is three slabs
-- of UI-LFG-FRAME. So it wants the parchment margin trimmed like the quest
-- giver's AND the pooled-row treatment the gossip window needed.

--- One result in the browse list: who is looking, for what, and their roles.
--
--  A ROW IS A BUTTON WITH FIVE PICTURES AND THREE STRINGS, and two of the
--  pictures are the client's own highlight bars - a gold one for the row you
--  have picked and a blue one for the row under the cursor. Both go: a picked
--  row is marked the way every other list in this interface marks one.
local function DressLFGRow(row, store)
	if not row or not row.GetRegions then return end

	Reskin.ClearButton(row)
	row.__aetherStore = row.__aetherStore or {}
	-- THE PICTURES STAY AND THE BARS GO. The party, class and newcomer icons
	-- are what the row is telling you; ResultBG is a four-per-cent white wash
	-- doing the work our own row backing does, and the two atlas bars are a
	-- gold rope round a row.
	Reskin.StripExcept(row, row.__aetherStore,
		{ "PartyIcon", "ClassIcon", "NewPlayerFriendlyIcon" })
	Reskin.Fonts(row, "pnBody", 1, Palette.c.text)

	-- AND THE PICKED ROW WEARS THE ACCENT. Reskin.RowMark is the same wash the
	-- trade window's live column and the mail list's unread row wear, so a
	-- selection reads the same wherever the player meets one.
	if row.Selected and not row.__aetherPicked then
		row.__aetherPicked = true
		Reskin.RowMark(row, row.__aetherStore)
	end
end

--- The browse list's rows, however many it is holding right now.
--
--  POOLED. A ScrollBox acquires its rows during its OWN layout, after the
--  window's update has returned - so this runs from the box's Update rather
--  than from the dresser alone. Same lesson as the gossip window, and it is
--  ForEachFrame rather than GetFrames for the same reason: one walks what the
--  box is showing and the other hands back a list that can already be stale.
local function DressLFGRows(store)
	local box = _G.LFGBrowseFrameScrollBox
	if not box then return end
	local function lift(row) DressLFGRow(row, store) end
	if box.ForEachFrame and pcall(box.ForEachFrame, box, lift) then return end
	for _, row in ipairs(ScrollBoxFrames(box)) do lift(row) end
end

--- The group finder: a listing you post and a browse you search with.
local function DressGroupFinder(frame, store)
	-- ITS TWO TABS, AND FIRST. A tab is a Button with a label on it and a
	-- child of the window, which is exactly what the sweep at the foot of this
	-- function looks for - so they are dressed as tabs before anything can
	-- mistake them for buttons. The social window's lesson.
	LayoutTabs(frame, store)

	-- THE PANES AND THEIR PARCHMENT. Three slabs of UI-LFG-FRAME and a
	-- decorative atlas behind the list, all of them regions of the pane.
	for _, name in ipairs({ "LFGBrowseFrame", "LFGListingFrame",
		"LFGParentFramePortrait" }) do
		local pane = _G[name]
		if pane then
			pane.__aetherStore = pane.__aetherStore or {}
			Reskin.Strip(pane, pane.__aetherStore)
		end
	end

	-- THE TWO FILTERS, which are the WowStyle1 control the trade skill's are.
	DressDropdown(_G.LFGBrowseFrameCategoryDropdown, store)
	DressDropdown(_G.LFGBrowseFrameActivityDropdown, store)

	-- THE TWO GEARS ARE PICTURES, not words - so each keeps its own glyph
	-- and loses the plate behind it. IconButton is passed the icon
	-- explicitly because on both the NORMAL texture is the plate rather
	-- than the picture, and left to guess it would keep the stone and throw
	-- the glyph away.
	for _, name in ipairs({ "LFGBrowseFrameOptionsButton",
		"LFGListingFrameOptionsButton" }) do
		local btn = _G[name]
		if btn then
			Reskin.IconButton(btn, store, { icon = Reskin.Element(btn, "Icon") })
		end
	end

	-- AND SEARCH AGAIN IS OUR OWN CIRCULAR ARROW ON OUR OWN ROUND BUTTON.
	--
	-- The client's is a 16px glyph centred on a 32px stone square, and a
	-- slot cell sized to the button stretched it across the whole face. It
	-- is the same gesture the character sheet's model turners are - go round
	-- again - so it takes the same control, drawn from the same one drawing.
	local again = _G.LFGBrowseFrameRefreshButton
	if again then
		Reskin.ClearButton(again)
		again.__aetherStore = again.__aetherStore or {}
		Reskin.Strip(again, again.__aetherStore)
		if not again.__aetherRound then
			W.RoundButton(again, { attach = again })
		end
		A.Media:SetIcon(again.__aetherRound, "rotate")
		W.PaintRound(again, false)
	end

	-- ITS X HAS NO NAME AND NO PARENT KEY: the client declares an anonymous
	-- <Button inherits="UIPanelCloseButton"> and nothing can ask for it. It
	-- is the only nameless Button child this window has - the two tabs are
	-- named and everything else is a Frame - so it is found by that and
	-- handed to the same dresser every other window's X goes through.
	if frame.GetChildren then
		for _, kid in ipairs({ frame:GetChildren() }) do
			if kid.GetObjectType and kid:GetObjectType() == "Button"
				and not (kid.GetName and kid:GetName()) then
				DressClose(frame, store, kid)
				break
			end
		end
	end

	-- THE RESULTS LIST, and the bar beside it. The box is not a scroll FRAME -
	-- it clips with a ScrollTarget rather than a scroll child - so it is swept
	-- rather than handed to Reskin.ScrollFrame, and the recess round it is the
	-- body's own.
	local box = _G.LFGBrowseFrameScrollBox
	if box then
		box.__aetherStore = box.__aetherStore or {}
		Reskin.Strip(box, box.__aetherStore)
	end
	Reskin.ScrollBar(_G.LFGBrowseFrameScrollBar, store)
	DressLFGRows(store)

	-- AND AGAIN EVERY TIME THE BOX LAYS ITSELF OUT, because that is when it
	-- acquires its rows: a sweep from inside the WINDOW's update reads the set
	-- that was there before. Hooked on the box's own Update, which is the
	-- answer the gossip window arrived at after three guesses at timing.
	if hooksecurefunc and box and box.Update and not box.__aetherLFGHook then
		box.__aetherLFGHook = true
		hooksecurefunc(box, "Update", function()
			if PN.enabled then DressLFGRows(store) end
		end)
	end

	-- THE LISTING'S THREE VIEWS, one up at a time, and the strip of role
	-- buttons above them. The activity view carries a horizontal bar in three
	-- slices of the TRAINER's art, which is a divider and becomes a hairline.
	for _, name in ipairs({ "LFGListingFrameCategoryView",
		"LFGListingFrameActivityView", "LFGListingFrameLockedView",
		"LFGListingFrameSoloRoleButtons", "LFGListingFrameGroupRoleButtons",
		"LFGListingFrameNewPlayerFriendlyButton" }) do
		local part = _G[name]
		if part then
			part.__aetherStore = part.__aetherStore or {}
			Reskin.Strip(part, part.__aetherStore)
			Reskin.Fonts(part, "pnBody", 2, Palette.c.text)
		end
	end

	-- WHAT THE WINDOW SAYS WHEN IT HAS NOTHING TO SHOW, which is a line of
	-- type on empty glass and reads as the window having failed unless it is
	-- dimmed on purpose.
	for _, pair in ipairs({ { "LFGBrowseFrame", "NoResultsFound" },
		{ "LFGBrowseFrame", "SearchingSpinner" } }) do
		local host = _G[pair[1]]
		local part = host and Reskin.Element(host, pair[2])
		if part then
			if part.GetObjectType and part:GetObjectType() == "FontString" then
				Reskin.Font(part, "pnBody")
				W.Color(part, Palette.c.textDim)
			else
				Reskin.Fonts(part, "pnBody", 2, Palette.c.textDim)
			end
		end
	end

	-- AND THE WHOLE WINDOW AGAIN AFTER THE CLIENT HAS FINISHED SWAPPING.
	--
	-- LFGParentFrameTab1_OnClick shows the listing and THEN hides the
	-- browse, so anything hooked to the pane going up fires while the pane
	-- coming down is still visible - and the strip is laid out for four
	-- buttons instead of two, which is Back and List Self a button's width
	-- too far apart. The social window's fault exactly, in a window that
	-- reaches it by a different route.
	--
	-- A post-hook on the two click functions runs after both, with one pane
	-- up. Guarded, because dressing a window from inside its own dress is
	-- not something to do twice.
	PN.__lfgHooks = PN.__lfgHooks or {}
	for _, fn in ipairs({ "LFGParentFrameTab1_OnClick",
		"LFGParentFrameTab2_OnClick" }) do
		if hooksecurefunc and _G[fn] and not PN.__lfgHooks[fn] then
			PN.__lfgHooks[fn] = true
			hooksecurefunc(fn, function()
				if not PN.enabled or PN.__lfgSettling then return end
				local win = _G.LFGParentFrame
				if not (win and win.IsShown and win:IsShown()) then return end
				PN.__lfgSettling = true
				pcall(PN.Dress, win)
				PN.__lfgSettling = nil
			end)
		end
	end

	-- EVERY BUTTON ON EITHER PANE. They are children of the panes rather than
	-- of the window, so one sweep of the window reaches none of them - and the
	-- window's own two tabs are already dressed as tabs, so the sweep leaves
	-- them alone.
	for _, name in ipairs({ "LFGBrowseFrame", "LFGListingFrame",
		"LFGParentFrame" }) do
		Reskin.Buttons(_G[name], "pnBody")
	end
end
-- The two people, and the two halves of the window each owns.
local TRADE_SIDES = { "TradePlayer", "TradeRecipient" }

--- One line of the exchange: a plate, a strip of parchment, a name and a slot.
--
--  A ROW IS NOT A BUTTON. The client builds each of the fourteen as a FRAME
--  carrying three pieces of art in its own BACKGROUND layer - the empty-slot
--  plate, the quest giver's parchment name strip, and the item's name printed
--  on that parchment - with the pressable ItemButton laid on top. So a sweep
--  of the WINDOW reaches none of it, and fourteen stone-and-paper strips sat
--  in the recess.
local function DressTradeRow(name, store)
	local row = _G[name]
	if not row then return end

	row.__aetherStore = row.__aetherStore or {}
	Reskin.Strip(row, row.__aetherStore)

	-- The item's picture is a BUTTON inside the row, the way a letter's is in
	-- the postbox - so stripping the row is safe and the icon goes in a cell.
	Reskin.Slot(_G[name .. "ItemButton"], { store = store })

	-- AND ITS NAME, which was printed on that parchment in the near-black
	-- paper wanted and is a smudge on glass.
	local fs = _G[name .. "Name"]
	if fs then
		Reskin.Font(fs, "pnBody")
		W.Color(fs, Palette.c.text)
	end
end

--- A recess of the client's, in glass, at its own bounds.
--
--  The inset IS the recess here rather than a border drawn round content, so
--  ours goes exactly where theirs was instead of standing WELL_OUTSET proud
--  of a scroll frame the way the trainer's lists do.
local function TradeWell(name)
	local ins = _G[name]
	if not ins then return nil end
	ins.__aetherStore = ins.__aetherStore or {}
	Reskin.Strip(ins, ins.__aetherStore)
	return Reskin.Well(ins, { corner = W.WELL_CORNER, inset = { 0, 0, 0, 0 },
		fill = "wellFill", edge = "wellEdge" })
end

--- The two-player trade window.
--
--  IT IS TWO WINDOWS DRAWN AS ONE. The client marks the divide by stitching a
--  SECOND window onto the right half - its own portrait ring, its own left
--  border, its own bottom corner and a pale wash behind the lot - and every
--  one of those is a region of the frame, so the shell's strip has already
--  taken them. What is left is what hangs off the window rather than being
--  drawn on it: six recesses, fourteen rows, two purses and four highlights.
local function DressTrade(frame, store)
	-- THE SIX RECESSES, which are this window's wells. Two columns of goods,
	-- two enchant slots and two purses, and nothing in the window is outside
	-- one of them.
	for _, side in ipairs(TRADE_SIDES) do
		TradeWell(side .. "ItemsInset")
		TradeWell(side .. "EnchantInset")
	end

	-- THE TWO PURSES ARE NOT SYMMETRICAL AND SHOULD NOT LOOK IT. Yours is
	-- three fields you type in and theirs is a figure you read, so yours wears
	-- three pills and theirs one well - and the recess round each comes off,
	-- because a well inside a recess draws the same rim twice.
	--
	-- Theirs is wrapped TWICE by the client - the recess and a thin gold edge
	-- inside it, the same double wrap the postbox's total has - so the well
	-- goes on the inner of the two, which is the one sized to the number.
	for _, name in ipairs({ "TradePlayerInputMoneyInset",
		"TradeRecipientMoneyInset", "TradeRecipientMoneyBg" }) do
		local f = _G[name]
		if f then
			f.__aetherStore = f.__aetherStore or {}
			Reskin.Strip(f, f.__aetherStore)
		end
	end
	if _G.TradeRecipientMoneyBg then
		Reskin.Well(_G.TradeRecipientMoneyBg, { inset = { 0, 0, 0, 0 } })
	end

	-- AND YOURS IS OUT OF REACH, WHICH IS THE CLIENT'S DOING AND NOT A GAP
	-- HERE. TradeFrame_OnLoad calls SetForbidden on TradePlayerInputMoneyFrame,
	-- so every method on it and on its three fields throws from insecure code:
	-- it cannot be swept, welled or moved, and Send Mail's answer to the same
	-- template - three of our pills with the coin as the field's own mark -
	-- cannot be applied here at any price.
	--
	-- What CAN be done is the recess round it, which is a frame of the window
	-- like any other. So your purse sits in one of ours with the client's own
	-- field art still inside it, and theirs sits in one with our figure in it.
	-- The pair still reads as a pair.
	--
	-- This is also what killed the whole dresser: the frame is a child of the
	-- window, it is named in the body list, and the first thing that measured
	-- it took the footer strip and every line below this one down with it.
	-- Nothing in this file guarded for a forbidden frame; PN.Part does now.
	if _G.TradePlayerInputMoneyInset then
		Reskin.Well(_G.TradePlayerInputMoneyInset, { inset = { 0, 0, 0, 0 },
			corner = W.WELL_CORNER, fill = "wellFill", edge = "wellEdge" })
	end

	-- AND THEIRS IS A ROW OF BUTTONS, which is the trap in this window: a
	-- MoneyFrame prints gold, silver and copper on three Buttons with labels
	-- on them, and the sweep at the foot of this function finds buttons with
	-- labels. They are children of the money frame rather than of the window,
	-- so it never reaches them - but only by luck, so the ink is set here and
	-- the reason is written down.
	Reskin.Fonts(_G.TradeRecipientMoneyFrame, "pnBody", 2, Palette.c.text)

	-- FOURTEEN ROWS, seven a side. The seventh is the enchant slot.
	for _, side in ipairs(TRADE_SIDES) do
		for i = 1, TRADE_ROWS do
			DressTradeRow(side .. "Item" .. i, store)
		end
	end

	-- WHOSE NAME IS OVER WHICH COLUMN - AND THAT IS THIS WINDOW'S TITLE.
	--
	-- Every other panel says what it is in the band. This one says it twice,
	-- because what it is is two people and each name belongs over a column;
	-- one centred string cannot carry that. So both go in the band, at the
	-- title's own baseline, each centred over the goods it names.
	--
	-- CENTRED OVER THE COLUMN rather than where the client had them: its own
	-- offsets are 65 and 230 against columns whose middles are 85 and 256, so
	-- neither name sat over the goods it was naming.
	--
	-- The x comes from the column and the y from the glass, which is two
	-- points on one string - so it is ONE point, at an offset worked out from
	-- the column's middle. Two points on a font string stretch it.
	local host = frame.__aetherPanel
	for _, pair in ipairs({ { "TradeFramePlayerNameText",
		"TradePlayerItemsInset" }, { "TradeFrameRecipientNameText",
		"TradeRecipientItemsInset" } }) do
		local fs, column = _G[pair[1]], _G[pair[2]]
		if fs then
			Reskin.Font(fs, "pnTitle")
			W.Color(fs, Palette.c.text)
		end
		if fs and host and column and column.GetLeft and host.GetLeft
			and column:GetLeft() and host:GetLeft() then
			local middle = (column:GetLeft() + column:GetRight()) / 2
			local centre = (host:GetLeft() + host:GetRight()) / 2
			fs:ClearAllPoints()
			fs:SetPoint("CENTER", host, "TOP", middle - centre,
				-(frame.__aetherHeadH or W.PANEL_HEAD_H) / 2)
			if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
		end
	end
	for _, name in ipairs({ "TradeFramePlayerEnchantText",
		"TradeFrameRecipientEnchantText" }) do
		local fs = _G[name]
		if fs then
			Reskin.Font(fs, "pnBody")
			W.Color(fs, Palette.c.textDim)
		end
	end

	-- WHICH SIDE IS LIVE. Four frames, three slices of UI-TradeFrame-Highlight
	-- each, and the client shows the pair belonging to whoever is putting
	-- something in. That is a row being marked, so it is marked the way every
	-- other row in this interface is - a wash of the accent rather than a gold
	-- rope round it.
	--
	-- BEHIND THE GOODS. The wash fills the frame, and the frame covers the
	-- whole column, so at the level the client gave it the mark would be drawn
	-- over the seven items it is meant to be pointing at.
	for _, side in ipairs(TRADE_SIDES) do
		for _, tail in ipairs({ "", "Enchant" }) do
			local hi = _G["TradeHighlight" .. side:sub(6) .. tail]
			if hi then
				hi.__aetherStore = hi.__aetherStore or {}
				Reskin.RowMark(hi, hi.__aetherStore)
				if hi.SetFrameLevel and frame.GetFrameLevel then
					hi:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1))
				end
			end
		end
	end

	-- Trade and Cancel, which are the only two real buttons on the window.
	Reskin.Buttons(frame, "pnBody")
end

--- Interiors, by frame. A window with no entry gets the shell treatment only.
-- ---------------------------------------------------------------------------
-- the group finder Mists actually opens
--
-- PVEFrame, and it is not LFGParentFrame with different numbers - it is a
-- different window that does the same job. Blizzard_GroupFinder is gated
-- `wrath, cata, mists` and carries this one; the parchment one below is in
-- Blizzard_GroupFinder_VanillaStyle, load-on-demand, and is what Era opens.
--
-- A SECOND FRAME OF ART INSIDE THE FIRST. On top of the portrait template's
-- own chrome this window draws eleven textures of `Interface\Common\bluemenu-*`
-- around its left column - a background slab, four corners, two vertical
-- rules, two horizontal ones and two filigrees. They are regions of PVEFrame
-- itself, so the shell's own strip takes them; they are named here only so the
-- next person to read this knows they were accounted for rather than missed.
--
-- Its three tabs are load-on-demand panes - PVPQueueFrame comes with
-- Blizzard_PVPUI and ChallengesFrame with Blizzard_ChallengesUI, and
-- PVEFrame.lua's own `panels` table gates the third on being at the level cap
-- with challenge mode enabled. So every pane here is asked for and skipped
-- when absent rather than assumed.
-- The picture on a finder row, and the gap from the row's left edge to it.
-- Blizzard hangs its ring at LEFT -12 and centres a 66-pixel icon in it; ours
-- keeps the picture at that size and brings it inside the row.
local PVE_ROW_ICON = 44
local PVE_ROW_PAD  = 8

--- The finder rows on both of this window's tabs.
--
--  ONE FUNCTION FOR TWO TEMPLATES, AND THEY DIFFER BY CAPITAL LETTERS.
--  GroupFinderFrame's four are GroupFinderGroupButtonTemplate and spell their
--  parts `bg`, `ring`, `icon`, `name`; PVPQueueFrame's four are
--  PVPQueueFrameButtonTemplate and spell the same four parts `Background`,
--  `Ring`, `Icon`, `Name`. Same row, drawn twice, one letter apart.
--
--  That is not a detail to guess at: reaching for `btn.icon` on a PvP row gets
--  nil, which turns StripExcept into Strip and takes the picture away with the
--  plate. The first pass here dressed only the first tab's rows, which is why
--  the PvP tab still had four of Blizzard's gold discs down its side.
local function RowPart(btn, ...)
	for _, key in ipairs({ ... }) do
		local part = btn[key]
		if type(part) == "table" then return part end
	end
	return nil
end

local function GroupButtons(store)
	local rows = {}
	local pvp = _G.PVPQueueFrame
	for i = 1, 4 do
		rows[#rows + 1] = _G["GroupFinderFrameGroupButton" .. i]
		if pvp then rows[#rows + 1] = pvp["CategoryButton" .. i] end
	end

	for _, btn in ipairs(rows) do
		if not Reskin.Forbidden(btn) then
			local icon  = RowPart(btn, "icon", "Icon")
			local label = RowPart(btn, "name", "Name")

			Reskin.ClearButton(btn)
			-- StripExcept, because the picture is a region of the button
			-- exactly as the plate is, and taking the lot takes the one thing
			-- that says which finder the row opens.
			Reskin.StripExcept(btn, store, icon and { icon } or nil)

			-- THE PICTURE, at its own size and on the left where the ring was.
			if icon and icon.ClearAllPoints then
				icon:ClearAllPoints()
				icon:SetSize(PVE_ROW_ICON, PVE_ROW_ICON)
				icon:SetPoint("LEFT", btn, "LEFT", PVE_ROW_PAD, 0)
				icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				icon:Show()
			end

			-- A BACKING FOR THE ROW, once. Created rather than re-created on
			-- every pass: this runs again from the client's own repaint hook.
			if not btn.__aetherRowBack then
				local back = btn:CreateTexture(nil, "BACKGROUND")
				back:SetTexture(Media.texture.flat)
				back:SetAllPoints(btn)
				btn.__aetherRowBack = back
			end
			W.Tint(btn.__aetherRowBack, Palette:Track())

			-- `pnBody`, the role every other list label in these windows takes.
			-- Not a name invented here: Media.style has a fixed vocabulary and
			-- SetFont answers anything it does not know with unitSub, so a
			-- made-up role reads as styled and is the wrong size.
			if label then
				Roled(label, "pnBody")
				if label.ClearAllPoints then
					label:ClearAllPoints()
					label:SetPoint("LEFT", btn, "LEFT",
						PVE_ROW_PAD * 2 + PVE_ROW_ICON, 0)
					label:SetPoint("RIGHT", btn, "RIGHT", -PVE_ROW_PAD, 0)
				end
			end
		end
	end
end

--- A role's opt-in tick, drawn OVER the picture rather than behind it.
--
--  The checkbox is a child of the role button, and a child draws above its
--  parent's regions - but not above a SIBLING frame at the same level, and the
--  role's picture is on the button itself. Reported as "the checkboxes for
--  selecting role are behind the icons so can't be seen".
--
--  ElvUI's HandleRoleButton opens with `checkbox:OffsetFrameLevel(1)` for
--  exactly this. We have no such helper, so it is spelled out.
local function RaiseTick(tick, host)
	if not (tick and host and tick.SetFrameLevel and host.GetFrameLevel) then
		return
	end
	tick:SetFrameLevel((host:GetFrameLevel() or 1) + 2)
end

local function DressPVE(frame, store)
	-- THE TABS FIRST, for the reason the social window taught: a tab is a
	-- Button with a label that is a child of the window, which is what a
	-- button sweep would otherwise take it for.
	LayoutTabs(frame, store)

	-- EVERY RECESS ON THE WINDOW, and there is one per pane rather than one
	-- for the window. PVEFrame's own LeftInset holds the column of group
	-- buttons at a fixed 217 wide; each right-hand pane brings its own. That
	-- is what earns `wells = false` on the entry - a body well round the
	-- outside would draw a rim round these rims.
	--
	-- ASKED FOR BY PATH, because two of the three panes do not exist until
	-- their addon has been loaded once.
	for _, path in ipairs({
		"PVEFrame.Inset",
		"LFDParentFrame.Inset",
		"RaidFinderFrame.Inset", "RaidFinderFrameBottomInset",
		"ScenarioFinderFrame.Inset",
		"LFGListFrame.SearchPanel.ResultsInset",
		"LFGListFrame.CategorySelection.Inset",
		"LFGListFrame.EntryCreation.Inset",
		"LFGListFrame.ApplicationViewer.Inset",
	}) do
		ClientRecess(nil, path)
	end

	-- THE GOLD RULE DOWN THE MIDDLE, AT LAST.
	--
	-- It survived four passes and three wrong guesses off screenshots - a
	-- leftover bluemenu vertical, an inset's edge, a scroll bar - because it is
	-- not a region of PVEFrame at all. `PVEFrame.shadows` is a CHILD FRAME
	-- declared with a parentKey and no name, and Reskin.Strip walks a frame's
	-- own regions plus a fixed list of art-child keys; a nameless child under
	-- an unlisted key is outside both.
	--
	-- It carries three textures, and Blizzard's XML labels the first two
	-- `<!-- left line -->` and `<!-- right line -->`: two shadow covers off
	-- bluemenu-shadowcovers, and a 5 by 403 slice of bluemenu-vert at x=211 -
	-- exactly the seam between the 217-wide left column and the content. That
	-- last one is the rule.
	--
	-- STRIPPED RATHER THAN HIDDEN, because PVEFrame_ShowFrame calls
	-- `PVEFrame.shadows:Show()` on every pane change and would undo a hide.
	if frame.shadows then
		frame.shadows.__aetherStore = frame.shadows.__aetherStore or {}
		Reskin.Strip(frame.shadows, frame.shadows.__aetherStore)
	end

	-- THE PANES' OWN ART. Each is a plain frame over the window with its
	-- backing drawn on it, the way LFGBrowseFrame and LFGListingFrame are on
	-- the Era window.
	--
	-- THE QUEUE FRAMES ARE IN HERE TOO, and they are not the panes. LFDQueueFrame
	-- is a setAllPoints child of LFDParentFrame carrying the dungeon list's own
	-- backdrop; a sweep of the parent leaves that drawing, which is the black
	-- brick showing through the list in the screenshots.
	for _, name in ipairs({ "GroupFinderFrame", "PVPQueueFrame",
		"ChallengesFrame", "LFDParentFrame", "LFDQueueFrame",
		"RaidFinderFrame", "RaidFinderQueueFrame",
		"ScenarioFinderFrame", "ScenarioQueueFrame",
		"HonorQueueFrame", "ConquestQueueFrame", "WarGamesQueueFrame",
		"LFGListFrame" }) do
		local pane = _G[name]
		if pane then
			pane.__aetherStore = pane.__aetherStore or {}
			Reskin.Strip(pane, pane.__aetherStore)
		end
	end

	-- THE ROLE BUTTONS, AND NOT THROUGH Reskin.IconButton.
	--
	-- THE PICTURE IS AN ATLAS AND AN ATLAS CARRIES ITS OWN COORDINATES.
	-- LFGRoleButtonTemplate has no `icon` part at all: the role is the button's
	-- NORMAL texture, `<NormalTexture atlas="UI-LFG-RoleIcon-Generic"/>`, swapped
	-- per role. IconButton hands that to W.DecorateSlot, which trims every icon
	-- to `SetTexCoord(0.07, 0.93, 0.07, 0.93)` to cut the gutter Blizzard bakes
	-- into an icon FILE - and doing that to an atlas overwrites the coordinates
	-- that say WHICH slice of the sheet to draw. Two of the four came back as
	-- empty squares, which is what a trimmed atlas looks like.
	--
	-- So the picture is kept and left entirely alone: no cell, no trim. What
	-- goes is the stone plate behind it - `background` and `shortageBorder`
	-- from the WithBackground template - and the other three state textures.
	for _, name in ipairs({
		"LFDQueueFrameRoleButtonTank", "LFDQueueFrameRoleButtonHealer",
		"LFDQueueFrameRoleButtonDPS", "LFDQueueFrameRoleButtonLeader",
		"RaidFinderQueueFrameRoleButtonTank",
		"RaidFinderQueueFrameRoleButtonHealer",
		"RaidFinderQueueFrameRoleButtonDPS",
		"HonorFrameRoleInsetRoleButtonTank",
		"HonorFrameRoleInsetRoleButtonHealer",
		"HonorFrameRoleInsetRoleButtonDPS",
	}) do
		local btn = _G[name]
		if btn and not Reskin.Forbidden(btn) then
			local pic = btn.GetNormalTexture and btn:GetNormalTexture()
			local drawn = pic and ((pic:GetAtlas() or "") ~= ""
				or ((pic:GetTexture() or 0) ~= 0))

			-- A ROLE THIS CLASS CANNOT TAKE HAS NO PICTURE YET, and stripping
			-- it takes the button away rather than dressing it. The warlock
			-- that turned this up can only ever be damage, so tank and healer
			-- came back empty and then vanished altogether - twice, because
			-- StripExcept with nothing to keep IS Strip.
			--
			-- Left entirely alone until it has something to keep. Nothing is
			-- lost by waiting: the client fills it in when the role becomes
			-- available and the sweep runs again from the window's next dress.
			if drawn then
				Reskin.StripExcept(btn, store, { pic })
				for _, kind in ipairs({ "Pushed", "Highlight", "Disabled" }) do
					local set = btn["Set" .. kind .. "Texture"]
					if set then set(btn, 0) end
				end
				-- Its opt-in tick is a check box like any other.
				if btn.checkButton then
					Reskin.CheckBox(btn.checkButton, store)
				end
			end
		end
	end

	-- THE BUTTONS ALONG THE FOOT. The entry's `actions` list PLACES them and
	-- does not skin them - that is every dresser's own job here - so the first
	-- pass left Find Group, Join Battle and Join as Group standing in
	-- Blizzard's stone in a footer strip of ours.
	--
	-- MagicButtonTemplate, which is UIPanelButtonTemplate's shape: Left, Middle
	-- and Right BACKGROUND regions rather than state textures, so a plain
	-- ClearButton leaves the plate exactly where it was. Reskin.Button knows.
	-- EVERY BUTTON ON EVERY SUB-PANE, and the ones I had were a fraction of
	-- them. Each finder and each battleground mode brings its own pair, and on
	-- the premade and entry-creation panes they are PARENT KEYS rather than
	-- globals - the same trap as the PvP roles, one pane deeper.
	--
	-- AND EACH CARRIES A SEPARATOR. MagicButtonTemplate draws a hairline off
	-- one side to butt against its neighbour; left on, they stand either side
	-- of buttons that are ours now and belong to nothing.
	local acts = {}
	for _, name in ipairs({
		"LFDQueueFrameFindGroupButton",
		"RaidFinderQueueFrameFindRaidButton",
		"ScenarioQueueFrameFindGroupButton",
		"HonorQueueFrameSoloQueueButton", "HonorQueueFrameGroupQueueButton",
		"ConquestJoinButton", "WarGameStartButton",
	}) do
		acts[#acts + 1] = _G[name]
	end
	for _, path in ipairs({
		"LFGListFrame.CategorySelection.StartGroupButton",
		"LFGListFrame.CategorySelection.FindGroupButton",
		"LFGListFrame.EntryCreation.CancelButton",
		"LFGListFrame.EntryCreation.ListGroupButton",
		"LFGListFrame.SearchPanel.BackButton",
		"LFGListFrame.SearchPanel.SignUpButton",
		"LFGListFrame.ApplicationViewer.RemoveEntryButton",
		"LFGListFrame.ApplicationViewer.EditButton",
	}) do
		acts[#acts + 1] = Part(path)
	end
	for _, btn in ipairs(acts) do
		if not Reskin.Forbidden(btn) then
			Reskin.Button(btn, "pnBody")

			for _, side in ipairs({ "LeftSeparator", "RightSeparator" }) do
				if btn[side] then Reskin.Kill(btn[side], store) end
			end
			local flat = _G[(btn.GetName and btn:GetName() or "") .. "_"
				.. "LeftSeparator"]
			if flat then Reskin.Kill(flat, store) end
			flat = _G[(btn.GetName and btn:GetName() or "") .. "_RightSeparator"]
			if flat then Reskin.Kill(flat, store) end
		end
	end

	-- THE TYPE PICKER ON EACH FINDER, which the readout named and I had not:
	-- LFDQueueFrameTypeDropdown, still carrying
	-- `common-dropdown-classic-textholder` and its button arrow. It is the
	-- WowStyle control the trade skill's filters are, so it takes the same
	-- dresser they do.
	-- EVERY NAME HERE OFF ELVUI'S SKIN, and every one I had guessed was wrong:
	-- the battleground picker is HonorQueueFrameTypeDropDown, with a capital D
	-- on Down, and there is no HonorFrameTypeDropdown at all.
	for _, name in ipairs({ "LFDQueueFrameTypeDropdown",
		"HonorQueueFrameTypeDropDown" }) do
		local dd = _G[name]
		if dd then DressDropdown(dd, store) end
	end

	-- AND THE LISTS SCROLL IN OUR RAIL. MinimalScrollBar on this window, which
	-- is the generation whose track is a CHILD FRAME rather than three regions
	-- of the bar - see Reskin.ScrollBar for why that distinction matters.
	-- AND THE SCROLL BARS ARE PER SUB-PANE, NOT PER QUEUE FRAME. Every path
	-- here was a guess before and not one of them existed: there is no
	-- LFDQueueFrame.ScrollBar. The list you scroll on the dungeon tab belongs
	-- to LFDQueueFrameSpecific, the random pane has one of its own, and the
	-- battleground list's is a flat global with FrameScrollBar in the middle
	-- of it. Reported as "wrong scrollbar on Dungeons and Raids", and it was
	-- not the wrong one - it was Blizzard's, because ours reached nothing.
	for _, path in ipairs({
		"LFDQueueFrameSpecific.ScrollBar",
		"LFDQueueFrameRandomScrollFrame.ScrollBar",
		"RaidFinderQueueFrameScrollFrame.ScrollBar",
		"ScenarioQueueFrameSpecific.ScrollBar",
		"ScenarioQueueFrameRandomScrollFrame.ScrollBar",
		"LFGListFrame.SearchPanel.ScrollBar",
		"LFGListFrame.ApplicationViewer.ScrollBar",
		"HonorQueueFrameSpecificFrameScrollBar",
		-- THE WAR GAMES PANE HAS TWO - the game list and the description
		-- beside it - and both were still Blizzard's, which is what "wrong
		-- scrollbars" was pointing at.
		"WarGamesQueueFrameScrollFrameScrollBar",
		"WarGamesQueueFrameInfoScrollFrameScrollBar",
		"WarGamesQueueFrameInfoScrollFrame.ScrollBar",
	}) do
		local bar = Part(path)
		if bar then Reskin.ScrollBar(bar, store) end
	end

	-- THE PVP TAB'S ROLE STRIP, which is a RECESS with the three roles in it
	-- rather than three loose buttons: HonorQueueFrame.RoleInset, carrying a
	-- Background and a NineSlice of its own. That is the black slab across the
	-- top of that tab, and nothing here had touched it.
	--
	-- ITS ROLES ARE PARENT KEYS, NOT GLOBALS - TankIcon, HealerIcon, DPSIcon on
	-- the inset - so the names I guessed at (HonorFrameRoleInsetRoleButtonTank
	-- and the rest) reached nothing at all.
	local roleInset = Part("HonorQueueFrame.RoleInset")
	if roleInset then
		Reskin.Kill(roleInset.Background, store)
		if roleInset.NineSlice then
			roleInset.NineSlice.__aetherStore =
				roleInset.NineSlice.__aetherStore or {}
			Reskin.Strip(roleInset.NineSlice, roleInset.NineSlice.__aetherStore)
		end
		for _, key in ipairs({ "TankIcon", "HealerIcon", "DPSIcon" }) do
			local btn = roleInset[key]
			if btn and not Reskin.Forbidden(btn) then
				local pic = btn.GetNormalTexture and btn:GetNormalTexture()
				local drawn = pic and ((pic:GetAtlas() or "") ~= ""
					or ((pic:GetTexture() or 0) ~= 0))
				if drawn then
					Reskin.StripExcept(btn, store, { pic })
					if btn.checkButton then
						Reskin.CheckBox(btn.checkButton, store)
						RaiseTick(btn.checkButton, btn)
					end
				end
			end
		end
	end

	-- AND THE PIECES EITHER SIDE OF THE TWO JOIN BUTTONS, which are separator
	-- textures the client draws between them.
	for _, name in ipairs({ "HonorQueueFrameSoloQueueButton_RightSeparator",
		"HonorQueueFrameGroupQueueButton_LeftSeparator" }) do
		local sep = _G[name]
		if sep then
			sep.__aetherStore = sep.__aetherStore or {}
			Reskin.Strip(sep, sep.__aetherStore)
		end
	end
	if _G.ConquestQueueFrame and _G.ConquestQueueFrame.ShadowOverlay then
		Reskin.Kill(_G.ConquestQueueFrame.ShadowOverlay, store)
	end

	-- THE WAR GAMES PANE'S OWN FURNITURE: the rule across it, and the arrow
	-- caps on the description's bar, which our scroll dresser does not reach
	-- because they are textures on frames hanging off the bar.
	local wg = _G.WarGamesQueueFrame
	if wg then
		wg.__aetherStore = wg.__aetherStore or {}
		Reskin.Strip(wg, wg.__aetherStore)
		if wg.HorizontalBar then Reskin.Kill(wg.HorizontalBar, store) end
	end
	for _, path in ipairs({
		"WarGamesQueueFrameInfoScrollFrame.ScrollBar.Back.Texture",
		"WarGamesQueueFrameInfoScrollFrame.ScrollBar.Forward.Texture",
	}) do
		local t = Part(path)
		if t then Reskin.Kill(t, store) end
	end
	if _G.WarGamesQueueFrameDescription then
		Roled(_G.WarGamesQueueFrameDescription, "pnBody")
	end

	-- AND THE PREMADE PANES' RECESSES, which are parent keys on LFGListFrame.
	for _, path in ipairs({
		"LFGListFrame.CategorySelection.Inset",
		"LFGListFrame.EntryCreation.Inset",
	}) do
		local ins = Part(path)
		if ins then
			ins.__aetherStore = ins.__aetherStore or {}
			Reskin.Strip(ins, ins.__aetherStore)
		end
	end

	-- THAT PANE'S OWN HEADING, which is drawn in QuestFont_Huge and gold - the
	-- ornate face, on a window where everything else is ours. Reported as
	-- "the text that says Premade Groups is in the wrong font". It is
	-- CategorySelection.Label, a parentKey, so no list of globals finds it.
	local heading = Part("LFGListFrame.CategorySelection.Label")
	if heading then Roled(heading, "pnTitle") end

	-- AND ITS CATEGORY BUTTONS ARE PARCHMENT WITH A PICTURE ON. Same division
	-- as every other row on this window: the Icon says which category, the
	-- Cover and the parchment behind it say nothing.
	for _, btn in ipairs(Part("LFGListFrame.CategorySelection.CategoryButtons")
		or {}) do
		if not Reskin.Forbidden(btn) then
			Reskin.ClearButton(btn)
			Reskin.StripExcept(btn, store, btn.Icon and { btn.Icon } or nil)
			if btn.Cover then Reskin.Kill(btn.Cover, store) end
			local label = btn.GetFontString and btn:GetFontString() or btn.Label
			if label then Roled(label, "pnBody") end
		end
	end

	-- THE FOUR GROUP BUTTONS ARE ROWS, NOT SLOTS, and the first attempt at them
	-- treated them as slots. W.DecorateSlot does `icon:SetAllPoints(f)` and
	-- lays a shade, a gloss and an edge over the whole frame - which is right
	-- for a 36-square bag cell and wrong for a 203 by 60 row: the 66-pixel
	-- picture was stretched the full width of the button until it read as a
	-- white slab, with the client's label sitting on top of it. That is what
	-- the screenshots showed.
	--
	-- What they actually are: a bluemenu plate, a ring, and a PICTURE that is
	-- the information, laid out as a list row. So the plate and ring go, the
	-- picture keeps its own size in the place the ring held on the left, and
	-- the row gets a backing of ours behind the pair.
	GroupButtons(store)

	-- AND ITS PANES ARE MEASURED BEFORE THEY HAVE ANYTHING IN THEM.
	--
	-- The readout said it outright: `GroupFinderFrame ... saved=true top=100
	-- now=46`. The pane was measured when it held only the column of finder
	-- rows, whose first is 70 down; the role buttons and the type dropdown
	-- arrive with LFDParentFrame, which is load-on-demand and lands later at
	-- 46. A saved 100 says the pane already clears the header band, so nothing
	-- moves - and the content that arrived afterwards sits up in the title.
	--
	-- PVEFrame_ShowFrame is what puts a pane up, and every route into this
	-- window goes through it. Forgetting the measurement there and laying the
	-- body out again is the fix; recomputing beats a cached number the client
	-- can invalidate, which is the fourth time that has been true here.
	if not PN.__pveShowHook and hooksecurefunc
		and type(_G.PVEFrame_ShowFrame) == "function" then
		PN.__pveShowHook = true
		hooksecurefunc("PVEFrame_ShowFrame", function(name)
			if not PN.enabled then return end
			local entry = PN.ENTRY and PN.ENTRY.PVEFrame

			-- ONLY THE PANE BEING SHOWN, and forgetting all of them was the
			-- reason the window changed size on a tab click.
			--
			-- LayoutBody takes the LARGEST shift any pane needs and grows the
			-- window once for it. A pane that is down cannot be measured, so
			-- the number it contributes is the one CACHED from when it was up -
			-- and clearing every cache meant the only pane with a measurement
			-- was the one just shown. The maximum then swung between 34 and 58
			-- with the tab, and the window's height swung with it.
			--
			-- Forgetting one pane leaves the others' readings standing, so the
			-- maximum is still taken across all of them.
			local pane = name and _G[name]
			if pane then
				pane.__aetherTop, pane.__aetherLeft, pane.__aetherRight =
					nil, nil, nil
			end
			pcall(PN.LayoutBody, _G.PVEFrame, entry)
		end)
	end

	-- AND THE CLIENT RE-LETTERS THEM. GroupFinderFrameButton_SetEnabled calls
	-- `button.name:SetFontObject(...)` on every enable and disable - both
	-- branches, so a label dressed once is Blizzard's again the moment
	-- EvaluateButtonVisibility runs, which it does on LFG_UPDATE_RANDOM_INFO
	-- and PLAYER_LEVEL_CHANGED as well as on load. Ninth instance of the same
	-- thing; hook what repaints.
	if not PN.__pveButtonHook and hooksecurefunc
		and type(_G.GroupFinderFrameButton_SetEnabled) == "function" then
		PN.__pveButtonHook = true
		hooksecurefunc("GroupFinderFrameButton_SetEnabled", function()
			if PN.enabled then pcall(GroupButtons, store) end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- the achievement book
--
-- WRITTEN FROM ELVUI'S SKIN RATHER THAN FROM SCREENSHOTS, which is the whole
-- change of method: Game/Mists/Skins/Achievement.lua names every part, and two
-- of them would have cost a round trip each to find.
--
-- ITS FRAME IS TWELVE NAMED TEXTURES. AchievementFrame inherits
-- BackdropTemplate rather than any portrait or button template, and draws its
-- own wood and metal border as separate pieces - four wood corners and eight
-- metal edges - so there is no margin convention to trim to. They are regions
-- of the window, so the shell's own strip reaches them; they are listed anyway
-- because a reader looking for "where did the frame go" should find the answer
-- here rather than in Blizzard's XML.
--
-- AND ITS ROWS ARE MINTED LAZILY. HybridScrollFrame_CreateButtons makes them on
-- demand, so a dresser that runs once at open dresses however many happened to
-- exist that moment - the spellbook's lesson, on another window.
-- ---------------------------------------------------------------------------

local ACH_ICON = 36

--- One achievement row: the picture, the two lines, and the tracking box.
local function AchievementRow(row, store)
	if not row or Reskin.Forbidden(row) then return end

	-- NO PERMANENT "ALREADY DONE" FLAG, and the first draft had one. A mark
	-- that nothing clears makes the SECOND dress a no-op, so turning the module
	-- off - which hands the client its art back - and on again leaves the row
	-- in Blizzard's plate for good. That is the same fault as the status bars'
	-- `__aetherFill`, found and fixed a day earlier, and I wrote it again.
	--
	-- So: the strip and the kill run every pass and are idempotent, and the
	-- only thing guarded is the cell, whose mark is in REDRESS_MARKS where
	-- Reskin.Restore will clear it. The strip goes to the WINDOW's store for
	-- the same reason - that is the store Restore is given.
	Reskin.StripExcept(row, store,
		row.icon and row.icon.texture and { row.icon.texture } or nil)

	-- THE ICON'S RING AND ITS FLASH GO, and both are frames rather than
	-- regions - which is exactly what Reskin.Kill is for now. ElvUI kills the
	-- same two by name; the flash in particular is animated, so hiding it
	-- loses to the animation the next time a row is filled in.
	if row.icon then
		Reskin.Kill(row.icon.bling, store)
		Reskin.Kill(row.icon.frame, store)
		if row.icon.texture and not row.icon.__aetherCell then
			row.icon.__aetherCell = true
			row.icon:SetSize(ACH_ICON, ACH_ICON)
			W.DecorateSlot(row.icon, ACH_ICON,
				{ icon = row.icon.texture, count = false })
		end
	end

	if row.label then Roled(row.label, "pnBody") end
	if row.description then Roled(row.description, "pnSub") end
	if row.hiddenDescription then Roled(row.hiddenDescription, "pnSub") end
	if row.tracked then Reskin.CheckBox(row.tracked, store) end
end

local function DressAchievements(frame, store)
	LayoutTabs(frame, store)

	-- THE WOOD AND THE METAL NEED NOTHING HERE, and a first draft listed all
	-- twelve pieces by name to take them off. A mutation that stopped that loop
	-- working changed nothing, which is the tell: every one of them is a REGION
	-- of AchievementFrame, so the shell's own strip has already had them before
	-- this function runs.
	--
	-- ElvUI hides them by name too, immediately before calling StripTextures on
	-- the same frame - so the list is belt-and-braces there as well. Worth
	-- knowing rather than copying: read their skin for WHICH PARTS EXIST, not
	-- as a script to transcribe.

	-- ITS HEADER IS A FRAME with the ornate plate on it, the game menu's shape
	-- under another name.
	for _, name in ipairs({ "AchievementFrameHeader",
		"AchievementFrameCategories", "AchievementFrameSummary" }) do
		local pane = _G[name]
		if pane then
			pane.__aetherStore = pane.__aetherStore or {}
			Reskin.Strip(pane, pane.__aetherStore)
		end
	end

	-- FIVE LISTS, FIVE RECESSES. The categories column plus one per tab, each
	-- of which the client already draws a border round - which is what earns
	-- `wells = false` on the entry.
	for _, name in ipairs({
		"AchievementFrameCategoriesContainer",
		"AchievementFrameAchievementsContainer",
		"AchievementFrameStatsContainer",
		"AchievementFrameComparisonContainer",
		"AchievementFrameComparisonStatsContainer",
	}) do
		ClientRecess(nil, name)
		local bar = _G[name .. "ScrollBar"]
		if bar then Reskin.ScrollBar(bar, store) end
	end

	if _G.AchievementFrameFilterDropdown then
		DressDropdown(_G.AchievementFrameFilterDropdown, store)
	end

	-- AND EVERY ROW, WHENEVER IT IS MADE. HybridScrollFrame_CreateButtons mints
	-- them on demand, so this has to run after the client rather than once at
	-- open. Same shape as the spellbook's lazily built pages.
	if not PN.__achRowHook and hooksecurefunc
		and type(_G.HybridScrollFrame_CreateButtons) == "function" then
		PN.__achRowHook = true
		hooksecurefunc("HybridScrollFrame_CreateButtons", function(scroll)
			if not PN.enabled then return end
			for _, row in ipairs((scroll and scroll.buttons) or {}) do
				pcall(AchievementRow, row, store)
			end
		end)
	end
	for _, list in ipairs({ _G.AchievementFrameAchievementsContainer,
		_G.AchievementFrameStatsContainer }) do
		for _, row in ipairs((list and list.buttons) or {}) do
			AchievementRow(row, store)
		end
	end
end

local INTERIORS = {
	CharacterFrame    = DressCharacter,
	PVEFrame          = DressPVE,
	AchievementFrame  = DressAchievements,
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
	TradeFrame        = DressTrade,
	FriendsFrame      = DressFriends,
	LFGParentFrame    = DressGroupFinder,
	SettingsPanel     = DressSettings,
}

PN.INTERIORS = INTERIORS
