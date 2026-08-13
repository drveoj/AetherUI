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
local PANELS = {
	{ frame = "CharacterFrame" },
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
	Reskin.Panel(frame, { corner = 16 })

	-- The window's own title, where it has one under a name we can find.
	local title = Reskin.Element(frame, "TitleText") or Reskin.Element(frame, "Title")
	if title and title.SetText then
		W.Restyle(title, "tbTitle")
		W.Color(title, Palette.c.text)
		frame.__aetherTitle = title
	end

	DressClose(frame, store)
	return true
end

PN.Dress = Dress

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
