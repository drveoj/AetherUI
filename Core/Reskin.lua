--[[--------------------------------------------------------------------------
	AetherUI :: Reskin

	Taking a frame the client built and dressing it in ours, reversibly.

	This is Modules\Popups.lua's engine, lifted out because the character sheet,
	the spellbook and the talent panes want exactly the same thing and none of
	them should have to learn the same three lessons again. Every one of those
	three cost a shipped build:

	  1. A FRAME IS NOT ITS OWN REGIONS. Its backdrop hangs off it as a CHILD
	     FRAME - NineSlice, Border, Bg, Inset - and GetRegions() never returns
	     one. Strip only the regions and the thing you can actually see survives.

	  2. HIDING IS NOT CLEARING. A hidden texture is one the client can show
	     again, and does: a button's pushed art appears on mousedown, and there
	     is no moment of ours in between. A texture with nothing in it draws
	     nothing whoever shows it.

	  3. A BUTTON'S STATE ART IS NOT A REGION YOU CAN REACH. Normal, pushed,
	     highlight and disabled go through the setters, cleared with 0.

	And one about finding things at all: two naming conventions are live on this
	client at once. A reworked frame carries its parts as fields and resolves
	them through a MIXIN, so rawget answers nil for every one of them; an older
	frame names them globally. Element tries both.

	Reversible throughout. Every module here is a reskin rather than a
	replacement, and switching one off has to hand the client's own frame back
	whole - so what was taken away is recorded, not merely overwritten.

	What this does NOT do
	---------------------
	It does not move frames, resize them, or reparent them. Blizzard's panels
	are positioned by the UIPanel system, several carry secure children, and
	HideUIPanel is combat-blocked and fails silently. Making one movable is a
	separate argument with that system and does not belong in a paint job.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Reskin = {}
A.Reskin = Reskin

-- Art a frame keeps in child frames rather than in its own regions. ElvUI's
-- list, because it is the one maintained against every flavour of this client
-- for a decade.
local ART_CHILDREN = {
	"Inset", "inset", "InsetFrame", "LeftInset", "RightInset",
	"NineSlice", "BG", "Bg", "border", "Border", "Background", "BorderFrame",
	"BorderBox", "bottomInset", "BottomInset", "bgLeft", "bgRight",
}

-- The four a Button draws itself.
local BUTTON_STATES = { "Normal", "Pushed", "Highlight", "Disabled" }

-- ---------------------------------------------------------------------------
-- finding
-- ---------------------------------------------------------------------------

--- A named part of a client frame, under either convention.
--
--  `frame.button1` / `frame.Button1` first, then the global the older layout
--  gives it. PLAIN INDEXING, never rawget: the reworked frames are mixin
--  objects and resolve their parts through __index, so rawget finds a frame
--  and none of its pieces.
function Reskin.Element(frame, key)
	if type(frame) ~= "table" or type(key) ~= "string" then return nil end

	local lower = key:gsub("^%w", string.lower)
	local el = frame[lower] or frame[key]
	if el ~= nil then return el end

	local name = frame.GetName and frame:GetName()
	return name and _G[name .. key] or nil
end

-- ---------------------------------------------------------------------------
-- stripping
-- ---------------------------------------------------------------------------

--- Take the client's art off `frame`, recording enough to put it back.
--
--  `store` is the caller's table, one per skinned frame, and holds everything
--  taken from that frame AND from the child frames its art hides in. Pass the
--  same store every time: this runs again on every show, because art the client
--  reveals later has to be taken down too.
function Reskin.Strip(frame, store)
	if not frame or not frame.GetRegions or type(store) ~= "table" then return end

	local known = store[frame]
	if not known then
		known = {}
		for _, region in ipairs({ frame:GetRegions() }) do
			if region and region.GetObjectType and region:GetObjectType() == "Texture" then
				known[#known + 1] = {
					region,
					region.IsShown and region:IsShown(),
					region.GetTexture and region:GetTexture() or nil,
				}
			end
		end
		store[frame] = known
	end

	for _, entry in ipairs(known) do
		local region = entry[1]
		if region.SetTexture then region:SetTexture(0) end
		if region.SetAtlas then pcall(region.SetAtlas, region, "") end
		if region.Hide then region:Hide() end
	end

	local name = frame.GetName and frame:GetName()
	for _, key in ipairs(ART_CHILDREN) do
		local child = frame[key] or (name and _G[name .. key])
		if child and child ~= frame and child.GetRegions then
			Reskin.Strip(child, store)
		end
	end

	-- Some carry a backdrop rather than textures. Only touched when there is
	-- one, because zeroing it is not reversible from here.
	if frame.SetBackdropColor then pcall(frame.SetBackdropColor, frame, 0, 0, 0, 0) end
	if frame.SetBackdropBorderColor then
		pcall(frame.SetBackdropBorderColor, frame, 0, 0, 0, 0)
	end
end

--- Everything in a store, back the way it was found.
function Reskin.Restore(store)
	if type(store) ~= "table" then return end
	for _, known in pairs(store) do
		for _, entry in ipairs(known) do
			local region, wasShown, path = entry[1], entry[2], entry[3]
			if path and region.SetTexture then region:SetTexture(path) end
			if wasShown and region.Show then region:Show() end
		end
	end
	wipe(store)
end

-- ---------------------------------------------------------------------------
-- buttons
-- ---------------------------------------------------------------------------

--- Clear a button's four state textures through the setters.
--
--  The only thing that works. Hiding the regions loses to the client, which
--  shows the pushed one on mousedown with nothing of ours in between.
function Reskin.ClearButton(btn)
	if not btn then return end
	btn.__aetherState = btn.__aetherState or {}

	for _, kind in ipairs(BUTTON_STATES) do
		local get, set = btn["Get" .. kind .. "Texture"], btn["Set" .. kind .. "Texture"]
		if get and set then
			if btn.__aetherState[kind] == nil then
				local tex = get(btn)
				local path = tex and tex.GetTexture and tex:GetTexture()
				btn.__aetherState[kind] = path or false
			end
			set(btn, 0)
		end
	end
end

function Reskin.RestoreButton(btn)
	local saved = btn and btn.__aetherState
	if not saved then return end
	for kind, path in pairs(saved) do
		local set = btn["Set" .. kind .. "Texture"]
		if set and path then set(btn, path) end
	end
	btn.__aetherState = nil
end

-- ---------------------------------------------------------------------------
-- dressing
-- ---------------------------------------------------------------------------

--- Put one of our surfaces behind a client frame.
--
--  BEHIND: a child at a lower frame level, filling the frame. The frame itself
--  is not moved, resized or reparented, so where the client puts it and what it
--  does when clicked remain entirely the client's business.
function Reskin.Panel(frame, opts)
	if not frame or frame.__aetherPanel then return frame and frame.__aetherPanel end
	opts = opts or {}

	local profile = A.db and A.db.profile
	local panel = A.Glass.CreatePanel(frame, {
		corner = opts.corner or 16,
		shadow = opts.shadow or (profile and profile.glass.shadow) or 1,
		fill = opts.fill or "dialogFill",
		edge = opts.edge or "glassEdgeHi",
	})
	panel:SetAllPoints(frame)
	panel:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))

	frame.__aetherPanel = panel
	return panel
end

--- A pill behind one of the client's buttons, and its label in our type.
function Reskin.Button(btn, style)
	if not btn or btn.__aetherPill then return end

	Reskin.ClearButton(btn)

	local pill = A.Glass.CreatePill(btn, { fill = "glass", edge = "glassEdgeHi" })
	pill:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
	pill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
	pill:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
	btn.__aetherPill = pill

	local label = btn.GetFontString and btn:GetFontString()
	if label then
		A.Widgets.Restyle(label, style or "tbCardTitle")
		A.Widgets.Color(label, A.Palette.c.text)
	end
	return pill
end

function Reskin.ReleaseButton(btn)
	if not btn then return end
	if btn.__aetherPill then
		btn.__aetherPill:Hide()
		btn.__aetherPill = nil
	end
	Reskin.RestoreButton(btn)
end

--- Hand the client its frame back: our surface away, its art returned.
function Reskin.Release(frame, store)
	if not frame then return end
	if frame.__aetherPanel then
		frame.__aetherPanel:Hide()
		frame.__aetherPanel = nil
	end
	Reskin.Restore(store)
end
