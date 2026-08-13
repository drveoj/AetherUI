--[[--------------------------------------------------------------------------
	AetherUI :: Popups

	The client's StaticPopup dialogs - "Do you want to destroy Sunscale
	Feather?", "Really abandon this quest?" - wearing the same glass as
	everything else instead of a stone frame and two red buttons.

	A RESKIN, not a replacement, for the same reason Modules\Tooltips.lua is
	one. These dialogs are how the game asks you things it cannot un-ask, they
	are created by the client with its own lifecycle, and several of them run
	protected actions. So nothing here builds a dialog, moves one, or reparents
	one: the art is hidden, a glass panel goes behind, the type is re-roled, and
	every bit of that is reversible. Switch the module off and Blizzard's own
	dialog comes back whole.

	Finding the pieces
	------------------
	Two naming conventions are live at once. The reworked dialog carries its
	parts as fields - `popup.Button1`, `popup.text` - and the older one names
	them globally, `StaticPopup1Button1`. Element() tries both, which is
	ElvUI's approach and is there because guessing one costs you every dialog
	the other kind draws.

	Buttons are DRESSED, never rebuilt. A button that runs a protected action is
	still an ordinary Button object; what is protected is what it calls. Hiding
	its textures and putting a pill behind it touches neither.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local PP = A:NewModule("popups")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- How many the client keeps. Fixed by the client, not by us.
local NUM_POPUPS = 4

local BTN_PAD = 10

local function cfg() return A.Config:Module("popups") end

-- ---------------------------------------------------------------------------
-- finding the pieces
-- ---------------------------------------------------------------------------

--- A named part of a dialog, under either convention.
--
--  `popup.button1` / `popup.Button1` first, then the global the older layout
--  gives it. Both are live on this client depending on which dialog you get,
--  and a module that knows only one silently skins half of them.
local function Element(popup, key)
	if type(popup) ~= "table" then return nil end

	local lower = key:gsub("^%w", string.lower)
	local el = rawget(popup, lower) or rawget(popup, key)
	if el ~= nil then return el end

	local name = popup.GetName and popup:GetName()
	return name and _G[name .. key] or nil
end

PP.Element = Element

-- ---------------------------------------------------------------------------
-- hiding what the client drew
-- ---------------------------------------------------------------------------

--- Every texture the frame owns, remembered so it can be put back.
--
--  Remembered per frame rather than re-derived, because the answer has to
--  survive until somebody switches the module off - and by then the frame may
--  have grown regions we never hid and must not show.
local function StripArt(frame, store)
	if not frame or not frame.GetRegions then return end
	if store[frame] then return end

	local hidden = {}
	for _, region in ipairs({ frame:GetRegions() }) do
		if region and region.GetObjectType and region:GetObjectType() == "Texture"
			and region.IsShown and region:IsShown() then
			hidden[#hidden + 1] = region
			region:Hide()
		end
	end
	store[frame] = hidden
end

local function RestoreArt(store)
	for _, hidden in pairs(store) do
		for _, region in ipairs(hidden) do
			if region.Show then region:Show() end
		end
	end
	wipe(store)
end

-- ---------------------------------------------------------------------------
-- dressing
-- ---------------------------------------------------------------------------

--- A glass pill behind one of the client's buttons.
--
--  Behind, and sized to it - the button itself is not moved, resized or
--  reparented. Its own art is hidden and its label re-roled, so what you click
--  and what happens when you do are entirely the client's.
local function DressButton(btn, art)
	if not btn or btn.__aetherPill then return end

	StripArt(btn, art)

	local pill = Glass.CreatePill(btn, { fill = "glass", edge = "glassEdgeHi" })
	pill:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
	pill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
	pill:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
	btn.__aetherPill = pill

	local label = btn.GetFontString and btn:GetFontString()
	if label then
		W.Restyle(label, "tbCardTitle")
		W.Color(label, Palette.c.text)
		btn.__aetherLabel = label
	end
end

--- The dialog itself: art off, glass behind, question re-roled.
local function Dress(popup)
	if not popup or popup.__aetherPanel then return end

	local art = {}
	popup.__aetherArt = art
	StripArt(popup, art)

	-- The warning triangle goes with the stone it was drawn for. What the
	-- dialog is asking is in the words, and a yellow exclamation from another
	-- interface sitting on frosted glass reads as something that failed to load.
	local alert = Element(popup, "AlertIcon")
	if alert and alert.Hide then
		alert:Hide()
		popup.__aetherAlert = alert
	end

	local profile = A.db and A.db.profile
	local panel = Glass.CreatePanel(popup, {
		corner = 16,
		shadow = (profile and profile.glass.shadow) or 1,
		fill = "dialogFill",
		edge = "glassEdgeHi",
	})
	panel:SetAllPoints(popup)
	panel:SetFrameLevel(math.max(0, popup:GetFrameLevel() - 1))
	popup.__aetherPanel = panel

	local text = Element(popup, "Text")
	if text and text.SetText then
		W.Restyle(text, "qlObjName")
		W.Color(text, Palette.c.text)
		popup.__aetherText = text
	end

	-- Button1 upward until the client runs out, the way ElvUI walks them: the
	-- number varies by dialog and hard-coding three would miss the fourth and
	-- dress a nil on the dialogs that have two.
	local i = 1
	while true do
		local btn = Element(popup, "Button" .. i)
		if not btn then break end
		DressButton(btn, art)
		i = i + 1
	end

	local close = Element(popup, "CloseButton")
	if close then StripArt(close, art) end
end

PP.Dress = Dress

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

--- Every dialog the client keeps, dressed once and hooked so it stays dressed.
--
--  Hooked rather than done once, because the client rebuilds parts of a dialog
--  as it shows it - a button that was hidden last time comes back with its own
--  art on. Same reason the tooltip card re-strips on every OnShow.
function PP:Skin()
	for i = 1, NUM_POPUPS do
		local popup = _G["StaticPopup" .. i]
		if popup then
			-- Dressed every time this runs; hooked only once. Gating the
			-- dressing on the hook meant off-then-on left every dialog bare
			-- until the next time one happened to be shown.
			Dress(popup)
			if popup.HookScript and not popup.__aetherHooked then
				popup.__aetherHooked = true
				popup:HookScript("OnShow", function(self)
					if not PP.enabled then return end
					Dress(self)
					StripArt(self, self.__aetherArt or {})
					if self.__aetherAlert then self.__aetherAlert:Hide() end
				end)
			end
		end
	end
end

function PP:OnEnable()
	self:Skin()
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() PP:Skin() end)
end

function PP:OnDisable()
	A:UnregisterAllEvents(self)

	for i = 1, NUM_POPUPS do
		local popup = _G["StaticPopup" .. i]
		if popup and popup.__aetherPanel then
			popup.__aetherPanel:Hide()
			popup.__aetherPanel = nil

			-- Everything hidden goes back, including the buttons' own art -
			-- their regions were recorded in the dialog's store.
			RestoreArt(popup.__aetherArt or {})
			popup.__aetherArt = nil

			if popup.__aetherAlert then popup.__aetherAlert:Show() end
			popup.__aetherAlert = nil

			local i2 = 1
			while true do
				local btn = Element(popup, "Button" .. i2)
				if not btn then break end
				if btn.__aetherPill then
					btn.__aetherPill:Hide()
					btn.__aetherPill = nil
				end
				i2 = i2 + 1
			end
		end
	end
end

function PP:OnSkinChanged()
	for i = 1, NUM_POPUPS do
		local popup = _G["StaticPopup" .. i]
		if popup and popup.__aetherPanel then
			popup.__aetherPanel:ApplySkin("dialogFill", "glassEdgeHi")
			if popup.__aetherText then W.Color(popup.__aetherText, Palette.c.text) end
		end
	end
end

function PP:OnConfigChanged() self:Skin() end
