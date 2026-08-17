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

local original            -- AceGUI.Create, before us

-- Forward-declared: a slider owns a number box, so the two dressers refer to
-- each other and one of them has to be named before it is written.
local DressEditBoxFrame

-- ---------------------------------------------------------------------------
-- the pieces
-- ---------------------------------------------------------------------------

--- Glass behind a container, in place of its own border art.
local function DressContainer(widget, opts)
	local frame = widget.frame
	if not frame then return end

	if not frame.__aetherStripped then
		frame.__aetherStripped = {}
		Reskin.Strip(frame, frame.__aetherStripped)
	end
	Reskin.Panel(frame, opts)

	if widget.titletext then
		Reskin.Font(widget.titletext, "qlZone")
		W.Color(widget.titletext, Palette.c.accent)
	end
end

--- A button, a check box, a slider: the three the panel is mostly made of.
local function DressButton(widget)
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
DressEditBoxFrame = function(box)
	if not box then return end
	if not box.__aetherStripped then
		box.__aetherStripped = {}
		Reskin.Strip(box, box.__aetherStripped)
		local pill = Glass.CreatePill(box, { fill = "glassSoft", edge = "glassEdge" })
		pill:SetPoint("TOPLEFT", box, "TOPLEFT", -4, 2)
		pill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 4, -2)
		pill:SetFrameLevel(math.max(0, (box:GetFrameLevel() or 1) - 1))
		box.__aetherPill = pill
	end
	if box.__aetherPill then box.__aetherPill:ApplySkin("glassSoft", "glassEdge") end
	Reskin.Font(box, "qlRow")
	W.Color(box, Palette.c.text)
end

local function DressEditBox(widget)
	DressEditBoxFrame(widget.editbox)
	if widget.label then
		Reskin.Font(widget.label, "qlLabel")
		W.Color(widget.label, Palette.c.text)
	end
	if widget.button then DressButton({ frame = widget.button }) end
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
	Frame          = function(w) DressContainer(w, { corner = 16 }) end,
	Window         = function(w) DressContainer(w, { corner = 16 }) end,
	InlineGroup    = function(w) DressContainer(w, { corner = 10 }) end,
	SimpleGroup    = function() end,   -- no art of its own
	ScrollFrame    = function() end,
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
	Dropdown       = function(w)
		if w.dropdown then DressEditBoxFrame(w.dropdown) end
		if w.label then W.Color(w.label, Palette.c.text) end
	end,
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
		for _, part in ipairs({ widget.frame, widget.border, widget.treeframe,
			widget.editbox }) do
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
