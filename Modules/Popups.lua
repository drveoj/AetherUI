--[[--------------------------------------------------------------------------
	AetherUI :: Popups

	The client's StaticPopup dialogs - "Do you want to destroy Sunscale
	Feather?", "Really abandon this quest?" - wearing the same glass as
	everything else instead of a stone frame and two red buttons.

	A RESKIN, not a replacement. These dialogs are how the game asks you things
	it cannot un-ask, the client owns their lifecycle, and several of them run
	protected actions. Nothing here builds a dialog, moves one, or reparents
	one: the art comes off, a glass panel goes behind, the type is re-roled, and
	all of it is reversible. Switch the module off and Blizzard's own dialog
	comes back whole.

	The mechanics live in Core\Reskin.lua - finding parts under either naming
	convention, clearing art that hides in child frames, taking a button's state
	textures off through the setters. Each of those cost a shipped build here
	first, and the header there records why.

	What is left to this module is the policy: which frames, which type roles,
	and that the warning triangle goes with the stone it was drawn for.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local PP = A:NewModule("popups")

local W, Palette, Reskin = A.Widgets, A.Palette, A.Reskin

-- How many the client keeps. Fixed by the client, not by us.
local NUM_POPUPS = 4

local function cfg() return A.Config:Module("popups") end

-- Exposed for the suite, and for anything else that wants a dialog's parts.
PP.Element = function(popup, key) return Reskin.Element(popup, key) end

-- ---------------------------------------------------------------------------
-- dressing
-- ---------------------------------------------------------------------------

--- Every button the dialog has, however many that is.
--
--  Button1 upward until the client runs out. The number varies by dialog, so
--  hard-coding three would miss the fourth and dress a nil on the ones with
--  two.
local function EachButton(popup, fn)
	local i = 1
	while true do
		local btn = Reskin.Element(popup, "Button" .. i)
		if not btn then return end
		fn(btn)
		i = i + 1
	end
end

--- Art off, glass behind, question re-roled. Safe to call repeatedly.
local function Dress(popup)
	if not popup then return end

	local store = popup.__aetherArt
	if not store then
		store = {}
		popup.__aetherArt = store
	end

	Reskin.Strip(popup, store)

	-- The warning triangle goes with the stone it was drawn for. What the
	-- dialog is asking is in the words, and a yellow exclamation from another
	-- interface on frosted glass reads as something that failed to load.
	local alert = Reskin.Element(popup, "AlertIcon")
	if alert and alert.Hide then
		alert:Hide()
		popup.__aetherAlert = alert
	end

	Reskin.Panel(popup)

	-- At the profile's scale, like every other frame of ours. A dialog left at
	-- the client's size is enormous beside the interface that raised it - and
	-- it is the one window that appears without being asked for.
	if popup.SetScale and A.db and A.db.profile then
		popup:SetScale(A.db.profile.scale or 1)
	end

	local text = Reskin.Element(popup, "Text")
	if text and text.SetText then
		W.Restyle(text, "qlObjName")
		W.Color(text, Palette.c.text)
		popup.__aetherText = text
	end

	EachButton(popup, function(btn)
		Reskin.Button(btn)
		Reskin.Strip(btn, store)
	end)

	local close = Reskin.Element(popup, "CloseButton")
	if close then Reskin.Strip(close, store) end
end

PP.Dress = Dress

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

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
				-- Re-dressed on every show, because the client puts art back: a
				-- button's pushed texture, a flash on a timed dialog. See the
				-- note in Core\Reskin.lua on hiding versus clearing.
				popup:HookScript("OnShow", function(self)
					if not PP.enabled then return end
					Dress(self)
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
			-- REGIONS FIRST, buttons after. A button's state textures are also
			-- regions on it, and they were recorded by Strip AFTER ClearButton
			-- had already emptied them - so restoring regions last would put
			-- the cleared value back over the path ReleaseButton just returned.
			Reskin.Release(popup, popup.__aetherArt or {})
			popup.__aetherArt = nil
			EachButton(popup, Reskin.ReleaseButton)

			if popup.__aetherAlert then popup.__aetherAlert:Show() end
			popup.__aetherAlert = nil

			if popup.SetScale then popup:SetScale(1) end
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
