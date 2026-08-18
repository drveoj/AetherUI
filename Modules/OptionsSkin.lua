--[[--------------------------------------------------------------------------
	AetherUI :: Options skin

	Our own settings, in our own interface. They were the one thing this addon
	drew that still looked like somebody else's - stone borders, a red Blizzard
	button, a blue gradient on the selected row.

	ONE HOOK, DISPATCHED BY TYPE. Every control in the panel comes out of
	AceGUI:Create, so wrapping that one function reaches all of them - the ones
	Ace ships, the ones AceDBOptions adds for the profile page, and any built
	later. There is no list of frames here and there does not need to be.

	The dressing itself is POLICY, not mechanism: Core\Reskin.lua already knows
	how to take a Blizzard button's art off, put glass behind a frame, re-role a
	check box's tick and rebuild a scroll bar, because the client's own windows
	needed all of that first. This module says which of those a Slider gets.

	WIDGETS ARE POOLED, and that shapes everything here. AceGUI hands the same
	widget back for the next panel that needs one, so:

	  * the art comes off ONCE, guarded by a mark on the frame. Stripping again
	    on every acquire would record our own emptied regions as the originals
	    and make switching the module off a no-op.
	  * the COLOURS are re-applied on every acquire, because a pooled widget
	    goes through OnAcquire again and Ace resets several of them there.

	Reversible like every other reskin: Reskin.Restore puts the client's regions
	back, and the panel is Blizzard's again.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local OS = A:NewModule("optionsskin")

local W, Glass, Palette, Reskin = A.Widgets, A.Glass, A.Palette, A.Reskin

local function cfg() return A.Config:Module("optionsskin") end

-- Every widget we have dressed, so a skin change can reach them and switching
-- off can undress them. Pooled and never destroyed, exactly like the glass
-- registry in Core\Glass.lua.
local dressed = {}

-- The strip across the top of the standalone window you grab it by.
local TITLE_H = 26

local original            -- AceGUI.Create, before us

-- Forward-declared. A slider owns a number box and the window owns a Close
-- button, so the dressers refer to each other and cannot all be written first.
--
-- Worth the two lines: a `local function` used before its declaration resolves
-- to a GLOBAL instead, which is nil, and the call dies inside the pcall that
-- guards these - so the window came out with its title moved, its status line
-- dressed, and no glass on it at all, in silence.
local DressEditBoxFrame
local DressButton

-- ---------------------------------------------------------------------------
-- the pieces
-- ---------------------------------------------------------------------------

--- Glass behind a container, in place of its own border art.
--- THE BOX YOU CAN SEE IS NOT ALWAYS THE WIDGET'S FRAME.
--
--  An InlineGroup's `frame` is invisible chrome. What is drawn - the dark
--  fill and the thin stone border - is a CHILD frame carrying a
--  BackdropTemplate, and the group's contents are children of THAT. AceGUI
--  keeps it as a local and never puts it on the widget, so there is one way
--  to reach it: it is the content's parent.
--
--  Dressing `frame` instead stripped nothing anybody could see and put glass
--  behind a box that was still drawing its own.
local function VisibleBox(widget)
	local frame = widget.frame
	local content = widget.content
	if content and content.GetParent then
		local host = content:GetParent()
		if host and host ~= frame then return host end
	end
	return frame
end

local function DressContainer(widget, opts)
	local frame = VisibleBox(widget)
	if not frame then return end

	-- INSIDE THE BOX, which is safe now that we dress the right one: `content`
	-- is a child of the visible box, so glass placed inside at a lower level
	-- sits under the contents and hides when the box hides, for nothing.
	opts = opts or {}

	-- STRIPPED ON EVERY PASS, recorded on the first.
	--
	-- ClearRegions keeps its record per frame and only takes it once, so
	-- calling this again is cheap and correct - and it has to be called
	-- again, because a pooled widget goes back through OnAcquire and Ace
	-- puts its backdrop colours back. Guarding the CLEAR as well as the
	-- recording is what let the stone box return the second time a page was
	-- opened.
	frame.__aetherStripped = frame.__aetherStripped or {}
	Reskin.Strip(frame, frame.__aetherStripped)
	local panel = Reskin.Panel(frame, opts)

	-- THE CONTENT GOES ABOVE THE GLASS, and it has to be said explicitly.
	--
	-- Reskin.Panel puts the panel a level below its frame, which is right for a
	-- client window whose insides are regions of it. An Ace group keeps its
	-- contents in a CHILD frame, and two children of the same frame at the same
	-- level draw in creation order - so the panel, made last, went over the top
	-- of every control in the group. The text was still there, behind a sheet of
	-- 97% glass.
	if panel and widget.content and widget.content.SetFrameLevel then
		widget.content:SetFrameLevel((panel:GetFrameLevel() or 0) + 2)
	end

	if widget.titletext then
		Reskin.Font(widget.titletext, "qlZone")
		W.Color(widget.titletext, Palette.c.accent)
	end
end


--- The standalone window: a title bar, a status line and a size grip, none of
--  which a plain container has.
--
--  Its own dresser rather than a line in DressContainer, because every part of
--  it is anchored to art we have just taken off - the title hangs from a header
--  texture that sits ABOVE the frame, so with the texture gone the words end up
--  against the top edge with nothing above them.
local function DressWindow(widget)
	local frame = widget.frame
	if not frame then return end

	-- THE TITLE, RE-ANCHORED TO THE FRAME. Blizzard's header art is anchored
	-- TOP +12, hanging over the edge, and the words hang another 14 below that
	-- - so they land exactly on the border once the art is gone.
	-- THE DRAG HANDLE MOVES WITH IT, and that is why the header art is
	-- re-anchored rather than the words. The invisible frame you grab the
	-- window by is SetAllPoints on `titlebg` and is not exposed on the widget
	-- at all - so moving the text alone would leave the grab area hanging in
	-- the empty screen above the window.
	--
	-- One point, not two: SetTitle sizes titlebg to the text on every call, and
	-- a frame pinned by both edges has no width left to set.
	if widget.titlebg then
		widget.titlebg:ClearAllPoints()
		widget.titlebg:SetPoint("TOP", frame, "TOP", 0, -4)
		widget.titlebg:SetHeight(TITLE_H)
	end
	if widget.titletext then
		widget.titletext:ClearAllPoints()
		widget.titletext:SetPoint("CENTER", widget.titlebg or frame, "CENTER", 0, 0)
		Reskin.Font(widget.titletext, "qlHeading")
		W.Color(widget.titletext, Palette.c.text)
	end

	-- THE STATUS LINE AND THE CLOSE BUTTON are both children of the window
	-- and NEITHER IS ON THE WIDGET - AceGUI keeps them as locals and only
	-- hangs `obj` back-references on them. So they are reached the one way
	-- that is left: the status text IS a child of the status bar, and the
	-- close button is the other templated Button under the frame.
	--
	-- Worth saying plainly because the first pass read widget.statusbg, found
	-- nil, and did nothing at all - silently, since there is no error in
	-- skipping a part that is not there.
	local statusbg = widget.statustext and widget.statustext:GetParent()
	if statusbg then
		local sb = statusbg
		if sb.SetBackdrop then pcall(sb.SetBackdrop, sb, nil) end
		if not sb.__aetherPill then
			sb.__aetherPill = Glass.CreatePill(sb, { fill = "glassSoft", edge = "glassEdge" })
			sb.__aetherPill:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
			sb.__aetherPill:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
			sb.__aetherPill:SetFrameLevel(math.max(0, (sb:GetFrameLevel() or 1) - 1))
		end
		sb.__aetherPill:ApplySkin("glassSoft", "glassEdge")
	end
	if widget.statustext then
		Reskin.Font(widget.statustext, "tiny")
		W.Color(widget.statustext, Palette.c.textDim)
	end

	-- THE SIZE GRIP. Three little textures out of the tooltip border atlas,
	-- children of the sizer frame rather than regions of the window - so they
	-- survive the strip and read as a scrap of somebody else's art in the
	-- corner. Re-tinted rather than removed: it is the only thing telling you
	-- the window resizes at all.
	for _, key in ipairs({ "sizer_se", "sizer_s", "sizer_e" }) do
		local sizer = widget[key]
		if sizer and sizer.GetRegions then
			for _, region in ipairs({ sizer:GetRegions() }) do
				if region.SetVertexColor then
					W.Tint(region, Palette.c.textFaint, 0.55)
				end
			end
		end
	end

	-- The Close button, which is an ordinary templated button and the last
	-- red thing on the window. Found by elimination rather than by name:
	-- the status bar is a Button too, and the sizers are not.
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			if child ~= statusbg and child.GetObjectType
				and child:GetObjectType() == "Button" and child.GetFontString
				and child:GetFontString() then
				DressButton({ frame = child })
			end
		end
	end

	DressContainer(widget, { corner = 16 })
end

--- A button, a check box, a slider: the three the panel is mostly made of.
DressButton = function(widget)
	local frame = widget.frame
	if not frame or frame.__aetherSkin then return end
	Reskin.Button(frame, "qlBtnAlt")
end

local function DressCheckBox(widget)
	local box = widget.checkbg and widget.checkbg:GetParent() or widget.frame
	if widget.checkbg and not widget.frame.__aetherCheck then
		widget.frame.__aetherCheck = true
		-- The box art off, the tick kept and re-coloured. A check box with no
		-- tick in it never looks checked, whatever its state says.
		widget.checkbg:SetTexture(A.Media.texture.chipDisc)
		widget.checkbg:SetVertexColor(Palette.c.glassStrong[1], Palette.c.glassStrong[2],
			Palette.c.glassStrong[3], 0.9)
	end
	if widget.checkbg then
		local g = Palette.c.glassStrong
		widget.checkbg:SetVertexColor(g[1], g[2], g[3], 0.9)
	end
	if widget.check then
		local a = Palette.c.accent
		widget.check:SetVertexColor(a[1], a[2], a[3], 1)
	end
	if widget.highlight then
		local h = Palette.c.rowHover
		widget.highlight:SetVertexColor(h[1], h[2], h[3], 1)
	end
	if widget.text then
		Reskin.Font(widget.text, "qlRow")
		W.Color(widget.text, Palette.c.text)
	end
end

--- A slider is a groove, a thumb and a number box, and all three are art.
local function DressSlider(widget)
	local slider = widget.slider
	if slider and not slider.__aetherSlider then
		slider.__aetherSlider = true
		if slider.SetBackdrop then pcall(slider.SetBackdrop, slider, nil) end

		-- The groove, drawn rather than textured: a hairline the width of the
		-- control, so the thumb has something to sit on that is not a trench.
		local track = slider:CreateTexture(nil, "BACKGROUND")
		track:SetTexture(A.Media.texture.flat)
		track:SetHeight(A:Px(2))
		track:SetPoint("LEFT", slider, "LEFT", 0, 0)
		track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
		slider.__aetherTrack = track
	end
	if slider and slider.__aetherTrack then
		W.Tint(slider.__aetherTrack, Palette.c.textFaint, 0.35)
	end

	local thumb = slider and slider.GetThumbTexture and slider:GetThumbTexture()
	if thumb then
		thumb:SetTexture(A.Media.texture.chipDisc)
		W.Tint(thumb, Palette.c.accent)
		if thumb.SetSize then thumb:SetSize(A:Px(12), A:Px(12)) end
	end

	for _, key in ipairs({ "label", "lowtext", "hightext" }) do
		local fs = widget[key]
		if fs then
			Reskin.Font(fs, key == "label" and "qlLabel" or "tiny")
			W.Color(fs, key == "label" and Palette.c.text or Palette.c.textDim)
		end
	end
	if widget.editbox then DressEditBoxFrame(widget.editbox) end
end

--- The number box under a slider, and the standalone one.
--
--  The same field the client's own windows are full of, and the recipe is
--  Reskin's rather than this module's for exactly that reason.
DressEditBoxFrame = function(box)
	Reskin.EditBox(box)
end

local function DressEditBox(widget)
	DressEditBoxFrame(widget.editbox)
	if widget.label then
		Reskin.Font(widget.label, "qlLabel")
		W.Color(widget.label, Palette.c.text)
	end
	if widget.button then DressButton({ frame = widget.button }) end
end


--- A dropdown is a template frame, an arrow button and a line of text, and
--  the template is drawn with a great deal of padding around all three.
--
--  Its own dresser rather than the edit box's: handing the whole
--  UIDropDownMenuTemplate frame to that one wrapped a pill round the ART, not
--  round the control, which is why they came out half again too tall.
local DROP_H = 22

local function DressDropdown(widget)
	local dd = widget.dropdown
	if not dd then return end

	if not dd.__aetherStripped then
		dd.__aetherStripped = {}
		Reskin.Strip(dd, dd.__aetherStripped)
	end

	-- Sized to the TEXT ROW rather than to the frame. The template pads about
	-- sixteen pixels each side for its own corner art, and all of that is gone.
	if not dd.__aetherPill then
		dd.__aetherPill = Glass.CreatePill(dd, { fill = "glassSoft", edge = "glassEdge" })
		dd.__aetherPill:SetHeight(DROP_H)
		dd.__aetherPill:SetPoint("LEFT", dd, "LEFT", 16, 0)
		dd.__aetherPill:SetPoint("RIGHT", dd, "RIGHT", -16, 0)
		dd.__aetherPill:SetFrameLevel(math.max(0, (dd:GetFrameLevel() or 1) - 1))
	end
	dd.__aetherPill:ApplySkin("glassSoft", "glassEdge")

	-- THE ARROW. Blizzard's is a gold plate with a down-chevron baked into it;
	-- ours is the chevron on its own, which is all it ever said.
	local btn = widget.button or (dd.GetName and dd:GetName() and _G[dd:GetName() .. "Button"])
	if btn then
		Reskin.ClearButton(btn)
		if not btn.__aetherGlyph then
			local glyph = btn:CreateTexture(nil, "OVERLAY")
			glyph:SetTexture(A.Media.texture.chevron)
			glyph:SetSize(10, 10)
			glyph:SetPoint("CENTER", btn, "CENTER", 0, 0)
			btn.__aetherGlyph = glyph
		end
		W.Tint(btn.__aetherGlyph, Palette.c.accent)
	end

	for _, key in ipairs({ "text", "label" }) do
		local fs = widget[key] or (dd.GetName and dd:GetName()
			and _G[dd:GetName() .. (key == "text" and "Text" or "")])
		if fs and fs.SetText then
			Reskin.Font(fs, key == "label" and "qlLabel" or "qlRow")
			W.Color(fs, key == "label" and Palette.c.text or Palette.c.text)
		end
	end
end


--- One row of the category list.
--
--  A row is an OptionsListButtonTemplate and the selection is Blizzard's blue
--  gradient, drawn by LockHighlight on the button's own highlight texture. So
--  the art comes off and we draw the selection ourselves - which also means
--  reading `selected` rather than relying on a texture we just took away.
local function DressTreeRow(b)
	if not b then return end

	if not b.__aetherRow then
		b.__aetherRow = true
		Reskin.ClearButton(b)

		-- The selection, ours. BACKGROUND so the label and the expand toggle
		-- stay over it; a highlight on top of its own row is a row you cannot
		-- read while it is the one you have chosen.
		local sel = b:CreateTexture(nil, "BACKGROUND")
		sel:SetTexture(A.Media.texture.flat)
		sel:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -1)
		sel:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 1)
		b.__aetherSel = sel
	end

	-- Re-tinted every pass: the row is reused for whatever line the tree is
	-- showing at that position, and the skin may have changed under it.
	W.Tint(b.__aetherSel, Palette.c.rowSel)
	b.__aetherSel:SetShown(b.selected and true or false)

	if b.text then
		Reskin.Font(b.text, "qlRow")
		W.Color(b.text, b.selected and Palette.c.text or Palette.c.textDim)
	end

	-- The expand toggle is a plus/minus plate. Cleared and given the chevron,
	-- which is the same glyph the menus and the dropdowns use.
	local toggle = b.toggle
	if toggle then
		Reskin.ClearButton(toggle)
		if not toggle.__aetherGlyph then
			local g = toggle:CreateTexture(nil, "OVERLAY")
			g:SetTexture(A.Media.texture.chevron)
			g:SetSize(8, 8)
			g:SetPoint("CENTER", toggle, "CENTER", 0, 0)
			toggle.__aetherGlyph = g
		end
		W.Tint(toggle.__aetherGlyph, Palette.c.textDim)
	end
end

--- The category list down the left.
local function DressTree(widget)
	if widget.border then
		if not widget.border.__aetherStripped then
			widget.border.__aetherStripped = {}
			Reskin.Strip(widget.border, widget.border.__aetherStripped)
		end
		Reskin.Panel(widget.border, { corner = 10 })
	end
	if widget.treeframe then
		if not widget.treeframe.__aetherStripped then
			widget.treeframe.__aetherStripped = {}
			Reskin.Strip(widget.treeframe, widget.treeframe.__aetherStripped)
		end
		Reskin.Panel(widget.treeframe, { corner = 10 })
	end
	if widget.scrollbar then
		widget.scrollbar.__aetherStore = widget.scrollbar.__aetherStore or {}
		Reskin.ScrollBar(widget.scrollbar, widget.scrollbar.__aetherStore)
	end

	-- THE ROWS ARE MADE LATER, and remade as the tree is filtered or a
	-- branch opens - so dressing whatever exists now would cover the first
	-- page and nothing after it. RefreshTree is what builds and repaints
	-- them, so it is wrapped once and the rows are dressed on the way out.
	if not widget.__aetherRefresh and widget.RefreshTree then
		widget.__aetherRefresh = widget.RefreshTree
		widget.RefreshTree = function(self, ...)
			self.__aetherRefresh(self, ...)
			for _, row in ipairs(self.buttons or {}) do
				pcall(DressTreeRow, row)
			end
		end
	end
	for _, row in ipairs(widget.buttons or {}) do DressTreeRow(row) end
end

--- A heading is a rule with a word on it.
local function DressHeading(widget)
	if widget.label then
		Reskin.Font(widget.label, "qlZone")
		W.Color(widget.label, Palette.c.accent)
	end
	for _, key in ipairs({ "left", "right" }) do
		local t = widget[key]
		if t then
			t:SetTexture(A.Media.texture.flat)
			W.Tint(t, Palette.c.glassEdge, 0.5)
			if t.SetHeight then t:SetHeight(A:Px(1)) end
		end
	end
end

local function DressLabel(widget)
	if widget.label then W.Color(widget.label, Palette.c.textDim) end
end

-- ---------------------------------------------------------------------------
-- the dispatch
-- ---------------------------------------------------------------------------

--- What each widget type gets. The list IS the policy.
local BY_TYPE = {
	Frame          = DressWindow,
	Window         = DressWindow,
	InlineGroup    = function(w) DressContainer(w, { corner = 10 }) end,
	SimpleGroup    = function() end,   -- no art of its own
	-- ITS SCROLL BAR, which is a UIPanelScrollBarTemplate and arrives with
	-- Blizzard's arrows on it. Only visible once the window is resized small
	-- enough to need one, which is exactly when nobody is looking for it.
	ScrollFrame    = function(w)
		if w.scrollbar then
			w.scrollbar.__aetherStore = w.scrollbar.__aetherStore or {}
			Reskin.ScrollBar(w.scrollbar, w.scrollbar.__aetherStore)
		end
	end,
	TabGroup       = function(w) DressContainer(w, { corner = 10 }) end,
	TreeGroup      = DressTree,
	Button         = DressButton,
	CheckBox       = DressCheckBox,
	Slider         = DressSlider,
	EditBox        = DressEditBox,
	MultiLineEditBox = DressEditBox,
	Heading        = DressHeading,
	Label          = DressLabel,
	InteractiveLabel = DressLabel,
	Dropdown       = DressDropdown,
	LSM30_Font     = DressDropdown,
}

local function Dress(widget)
	if not widget or not widget.type then return end
	local fn = BY_TYPE[widget.type]
	if not fn then return end

	-- pcall because these are somebody else's frames, built by a library that
	-- may change shape between versions, and a settings panel that errors is
	-- worse than one that looks like Blizzard's.
	local ok, err = pcall(fn, widget)
	if not ok then
		A.lastFailure = "optionsskin " .. tostring(widget.type) .. ": " .. tostring(err)
		return
	end
	dressed[widget] = true
end

OS.Dress = Dress

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function OS:Available()
	local gui = LibStub and LibStub("AceGUI-3.0", true)
	return gui ~= nil and type(gui.Create) == "function"
end

function OS:OnEnable()
	local gui = LibStub and LibStub("AceGUI-3.0", true)
	if not gui then
		self.absent = true
		return
	end
	self.absent = nil

	original = original or gui.Create
	gui.Create = function(selfGui, widgetType)
		local widget = original(selfGui, widgetType)
		if OS.enabled then Dress(widget) end
		return widget
	end
end

function OS:OnDisable()
	local gui = LibStub and LibStub("AceGUI-3.0", true)
	if gui and original then gui.Create = original end

	-- The art back. Only what we recorded, and only once - Restore empties the
	-- store, so a second pass would put nothing back over the top of nothing.
	for widget in pairs(dressed) do
		-- The DRAWN box among them, which for a group is not the widget's frame.
		-- Undressing the frame and leaving the box glassed is how "off" leaves
		-- half the panel ours.
		local box = widget.content and widget.content.GetParent
			and widget.content:GetParent()
		for _, part in ipairs({ widget.frame, box, widget.border,
			widget.treeframe, widget.editbox }) do
			if part and part.__aetherStripped then
				Reskin.Restore(part.__aetherStripped)
				part.__aetherStripped = nil
			end
			if part and part.__aetherPanel then part.__aetherPanel:Hide() end
			if part and part.__aetherPill then part.__aetherPill:Hide() end
		end
		if widget.frame then Reskin.ReleaseButton(widget.frame) end
	end
	dressed = {}
end

--- The panel follows the skin like everything else.
function OS:OnSkinChanged()
	if not self.enabled or self.absent then return end
	for widget in pairs(dressed) do Dress(widget) end
end
