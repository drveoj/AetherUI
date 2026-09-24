--[[--------------------------------------------------------------------------
	AetherUI :: Reskin

	Taking a frame the client built and dressing it in ours, reversibly.

	This is Modules\Popups.lua's engine, lifted out because the timers and our
	own options panel want exactly the same thing and none of them should have
	to learn the same three lessons again. Every one of those three cost a
	shipped build:

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

-- Art a frame keeps in child frames rather than in its own regions. These are
-- Blizzard's own field names - what the client calls the parts of its frames -
-- collected by looking at what actually turns up on them.
local ART_CHILDREN = {
	"Inset", "inset", "InsetFrame", "LeftInset", "RightInset",
	"NineSlice", "BG", "Bg", "border", "Border", "Background", "BorderFrame",
	"BorderBox", "bottomInset", "BottomInset", "bgLeft", "bgRight",
	-- The shared dialog template keeps its title bar in one of these: a Header
	-- child carrying the stone plate as its BG and the title as its Text. The
	-- game menu uses it, and without this its ornate bar outlives the strip.
	"Header", "header",
	-- And the portrait template keeps ITS title bar in a TitleContainer, which
	-- is the same idea under a second name. The help window's stone band was
	-- the last thing left drawing on it, and every other part of that frame had
	-- come off - which is how a bar with nothing above or below it survives.
	"TitleContainer",
	-- FROM ELVUI'S OWN LIST, which is the same idea arrived at independently
	-- and a few names longer. `StripTexturesBlizzFrames` in its Toolkit.lua
	-- carries 23 keys against our 20, and these are the ones we did not have.
	-- Consulting it first would have been cheaper than finding them one
	-- screenshot at a time.
	"FilligreeOverlay", "PortraitOverlay", "ArtOverlayFrame",
	"Portrait", "portrait",
	"ScrollFrameBorder", "ScrollUpBorder", "ScrollDownBorder",
	-- AND ONE NEITHER OF US LISTS. PVEFrame keeps two shadow covers and the
	-- rule down its seam on a nameless `shadows` child; ElvUI handles it in
	-- that window's own skin with a comment saying why. It is a general enough
	-- name to be worth having here.
	"shadows", "Shadows",
}

-- The four a Button draws itself.
local BUTTON_STATES = { "Normal", "Pushed", "Highlight", "Disabled" }

-- How far in from an edit box's own edge its text starts. A box draws from
-- that edge, and the well we put round it has a rim there - so the caret and
-- the first character sat on the rim, which on a box one digit wide is the
-- whole of what you see.
local EDIT_INSET = 8

-- ---------------------------------------------------------------------------
-- finding
-- ---------------------------------------------------------------------------

--- A named part of a client frame, under either convention.
--
--  `frame.button1` / `frame.Button1` first, then the global the older layout
--  gives it. PLAIN INDEXING, never rawget: the reworked frames are mixin
--  objects and resolve their parts through __index, so rawget finds a frame
--  and none of its pieces.
--- Has the client put this frame out of reach?
--
--  SetForbidden is real, and this game uses it on ORDINARY WINDOWS rather than
--  only on the shop: TradeFrame_OnLoad calls it on TradePlayerInputMoneyFrame.
--  From insecure code every method on such a frame throws, the answer is
--  inherited by its children, and the frame is still in its parent's child
--  list - so any sweep that walks children and asks each one a question dies
--  on it. Nothing in this file guarded for it, and the trade window's dresser
--  stopped dead the first time one was reached.
--
--  IsForbidden is the one question you are allowed to ask, and even that is
--  pcalled: a throw asking it is itself an answer.
function Reskin.Forbidden(f)
	if type(f) ~= "table" or not f.IsForbidden then return false end
	local ok, forbidden = pcall(f.IsForbidden, f)
	return (not ok) or (forbidden and true or false)
end

function Reskin.Element(frame, key)
	if type(frame) ~= "table" or type(key) ~= "string" then return nil end

	local lower = key:gsub("^%w", string.lower)

	-- A PART, NEVER A VALUE. Some templates keep a plain string under the same
	-- name as the region we want - a FriendsFrame tab has `text = "FRIENDS"`
	-- sitting beside its Text fontstring - and handing that back means the
	-- caller sets a field on a string and the window fails to open. Each
	-- candidate is skipped rather than returned, so the next one still gets a
	-- look in.
	local el = frame[lower]
	if type(el) ~= "table" then el = frame[key] end
	if type(el) == "table" then return el end

	local name = frame.GetName and frame:GetName()
	el = name and _G[name .. key]
	return type(el) == "table" and el or nil
end

-- ---------------------------------------------------------------------------
-- stripping
-- ---------------------------------------------------------------------------

--- Every texture region on a frame, emptied and recorded - bar the ones named.
--
--  `keep` is a set of regions to leave alone. It exists for buttons whose art
--  and whose PICTURE are both regions of the same button: a spell icon and a
--  spellbook school tab both carry the image the player is looking for as a
--  region, so a sweep that takes every texture takes the picture with the
--  plate. Strip passes nothing and clears the lot.
local function ClearRegions(frame, store, keep)
	local known = store[frame]
	if not known then
		known = {}
		for _, region in ipairs({ frame:GetRegions() }) do
			if region and region.GetObjectType and region:GetObjectType() == "Texture"
				and not (keep and keep[region]) then
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
		-- NIL, NOT AN EMPTY STRING. `SetAtlas("")` leaves the region carrying an
		-- atlas NAMED "" rather than none, and the client reads that name back:
		-- MinimalScrollBar's own Update calls C_Texture.GetAtlasInfo on it and
		-- throws "bad argument #1", every time a list is scrolled.
		--
		-- ElvUI passes '' here and gets away with it because it does not strip
		-- that bar; we do, so we have to clear the atlas the way the API means
		-- it to be cleared.
		if region.SetAtlas then pcall(region.SetAtlas, region, nil) end
		if region.Hide then region:Hide() end
	end
end

--- Regions to spare, from keys or from the regions themselves.
--
--  A base-UI region often carries a global name of its own rather than a
--  $parent one - TaxiFrame's map is `TaxiMap` - so a bare global is accepted
--  as a last resort, and only when it really is a part of this frame.
local function KeepSet(frame, names)
	if not names then return nil end

	local keep = {}
	for _, key in ipairs(names) do
		local region = key
		if type(key) == "string" then
			region = Reskin.Element(frame, key)

			-- Matched against the frame's own regions rather than trusted from
			-- _G, so a global of that name belonging to something else cannot
			-- spare a piece of art here.
			local global = not region and _G[key]
			if type(global) == "table" and frame.GetRegions then
				for _, r in ipairs({ frame:GetRegions() }) do
					if r == global then region = global break end
				end
			end
		end
		if type(region) == "table" then keep[region] = true end
	end
	return keep
end

--- Take the client's art off `frame`, recording enough to put it back.
--
--  `store` is the caller's table, one per skinned frame, and holds everything
--  taken from that frame AND from the child frames its art hides in. Pass the
--  same store every time: this runs again on every show, because art the client
--  reveals later has to be taken down too.
--
--  `keep` names regions to leave alone, for a window whose picture is one of
--  its own regions. It applies to this frame only - the art children below are
--  swept whole, which is what they are in the list for.
function Reskin.Strip(frame, store, keep)
	if Reskin.Forbidden(frame) then return end
	if not frame or not frame.GetRegions or type(store) ~= "table" then return end

	ClearRegions(frame, store, KeepSet(frame, keep))

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

--- Take a frame's art off, KEEPING the parts named.
--
--  The third shape of this problem, so it is a primitive now rather than a
--  special case each time. A frame's art and the thing the player is looking at
--  are both regions of it: a spell keeps its icon beside the ring, a check box
--  keeps its tick beside the box, a friends row keeps the little online lamp and
--  the game badge beside its backing. Strip takes the lot.
--
--  `names` are keys Element understands - a parentKey or a $parent global - so
--  the caller names the parts to keep the way the client names them.
function Reskin.StripExcept(frame, store, names)
	if Reskin.Forbidden(frame) then return end
	if not frame or not frame.GetRegions or type(store) ~= "table" then return end

	ClearRegions(frame, store, KeepSet(frame, names))
end

--- Everything in a store, back the way it was found.
--- Marks that make a SECOND dress do nothing, and the surface each stands for.
--
--  Reskin.StatusBar and Reskin.ScrollBar both open with `if bar.__aetherX then
--  return end` and only strip AFTER it. That is right while a module stays on
--  and wrong the moment one is turned off: Restore hands the client its art
--  back, the mark stays behind, and the re-dress returns at the first line
--  without stripping the art that just came back. The bar then draws Blizzard's
--  panelling with our fill still sitting under it.
--
--  Found on the pet's XP bar, whose two UI-MainMenuBar-Dwarf textures came
--  back after its module was switched off and on and could not be swept again. It
--  was never about that bar: every status bar and scroll bar in the interface
--  did it, which is why the fix is here rather than in either function.
--
--  That mistake has now been made three times in this module, so the rule is:
--  any "already done" mark belongs in this list the moment it is written. The
--  names not yet used here are listed anyway - a mark that is absent costs one
--  nil lookup, and a mark that is added later and forgotten costs a bug.
local REDRESS_MARKS = { "__aetherFill", "__aetherScroll", "__aetherCell",
	"__aetherLifted", "__aetherFloored", "__aetherRailed" }

function Reskin.Restore(store)
	if type(store) ~= "table" then return end
	for frame, known in pairs(store) do
		for _, entry in ipairs(known) do
			local region, wasShown, path = entry[1], entry[2], entry[3]
			if path and region.SetTexture then region:SetTexture(path) end
			if wasShown and region.Show then region:Show() end
		end

		-- OUR SURFACE GOES WITH IT. The fill was created after the strip, so it
		-- is not in the store and Restore above cannot reach it - it would go on
		-- drawing over the client's returned art.
		if type(frame) == "table" then
			for _, mark in ipairs(REDRESS_MARKS) do
				local ours = frame[mark]
				if type(ours) == "table" and ours.Hide then ours:Hide() end
				frame[mark] = nil
			end
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
	if not btn or Reskin.Forbidden(btn) then return end
	btn.__aetherState = btn.__aetherState or {}

	for _, kind in ipairs(BUTTON_STATES) do
		local get, set = btn["Get" .. kind .. "Texture"], btn["Set" .. kind .. "Texture"]
		if get and set then
			if btn.__aetherState[kind] == nil then
				local tex = get(btn)
				local path = tex and tex.GetTexture and tex:GetTexture()
				-- 0 means somebody has already emptied it - Strip, most likely,
				-- if the caller happened to run that first. Recording THAT
				-- would make the restore put "cleared" back, which is not a
				-- restore. Order-independent on purpose: both orders are
				-- reasonable and each has already been written once.
				if path == 0 then path = nil end
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
	-- A client frame is bigger than the window you can see. Blizzard's art has
	-- wide transparent margins baked into it - and room below for the tab strip
	-- - so glass at the frame's full extent reads as a slab of padding on the
	-- right and underneath. `insets` is { left, top, right, bottom } as SetPoint
	-- offsets, per frame, because every one of them is padded differently.
	local i = opts.insets
	if i then
		panel:SetPoint("TOPLEFT", frame, "TOPLEFT", i[1] or 0, i[2] or 0)
		panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", i[3] or 0, i[4] or 0)
	else
		panel:SetAllPoints(frame)
	end
	panel:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))

	frame.__aetherPanel = panel

	--- A CHILD HIDES WITH ITS PARENT, and that is the whole reason the panel
	--  is one. A `behind` option was tried - glass as a SIBLING of the frame,
	--  to sidestep a draw-order problem that turned out to be us dressing the
	--  wrong frame - and it put two sheets across the screen at login twice.
	--  AceGUI parents its widget frames to UIParent, so behind meant parented
	--  to UIParent, and glass whose visibility is tracked by hand outlives the
	--  frame it was drawn for the moment anything hides that frame by a path
	--  that does not fire OnHide.
	--
	--  Removed rather than left switched off: an option nobody uses is one
	--  somebody will.

	return panel
end

--- Our surface behind one of the client's buttons, and its label in our type.
--
--  THE SHAPE IS NOT DECIDED HERE. W.SkinButton owns it, and so does the tab
--  below, and so does anything else that puts a pressable surface on screen -
--  see the note above it for what three separate versions of this cost.
function Reskin.Button(btn, style)
	if not btn or Reskin.Forbidden(btn) then return end

	Reskin.ClearButton(btn)

	local label = btn.GetFontString and btn:GetFontString()

	-- THE ART IS NOT ALWAYS A STATE TEXTURE. UIPanelButtonTemplate - which is
	-- what the client and every options library build ordinary buttons from -
	-- draws itself with THREE BACKGROUND REGIONS called Left, Middle and
	-- Right, and ClearButton above only empties the normal/pushed/highlight
	-- set. So a button came back with our glass behind it and Blizzard's red
	-- still painted on top.
	--
	-- Keeping the LABEL, which is a region of the button like the art around
	-- it: a plain strip takes the words off with the stone.
	-- Cleared every pass, recorded on the first: ClearRegions keeps its own
	-- record per frame, and a button handed back out of a pool has had its
	-- art put back on it.
	btn.__aetherArt = btn.__aetherArt or {}
	btn.__aetherStripped = true
	ClearRegions(btn, btn.__aetherArt, label and { [label] = true } or nil)
	local skin = A.Widgets.SkinButton(btn, { label = label })

	if label then
		A.Widgets.Restyle(label, style or "tbCardTitle")
		A.Widgets.Color(label, A.Palette.c.text)
	end
	return skin
end

function Reskin.ReleaseButton(btn)
	if not btn then return end

	-- The three background regions first, and only once: Restore empties the
	-- store, so a second pass would put nothing back over the top of nothing.
	if btn.__aetherArt then
		Reskin.Restore(btn.__aetherArt)
		btn.__aetherArt, btn.__aetherStripped = nil, nil
	end
	if btn.__aetherSkin then
		btn.__aetherSkin:Hide()
		btn.__aetherSkin = nil
	end
	if btn.__aetherPill then
		btn.__aetherPill:Hide()
		btn.__aetherPill = nil
	end
	Reskin.RestoreButton(btn)
end

-- ---------------------------------------------------------------------------
-- elements
-- ---------------------------------------------------------------------------

--- A glass surround for something the client drew a border round - or should
--- have and did not.
--
--  Every text field in the game is the same three slices of
--  `Common-Input-Border`, drawn as background regions of the box itself; and
--  some fields have no border at all. Both want the same answer - one of our
--  surfaces sitting behind the thing - so it is one function.
--
--  The surface is remembered on the frame under the name every other well in
--  this interface uses, so a skin change re-dresses the one already there.
--  `opts.inset` is how far it stands PROUD on each side, left, top, right,
--  bottom; the default hugs, because a field is 20 tall and a border four
--  pixels out on every side reads as a control half again the size of the one
--  being typed in. `opts.to` names a frame the far corner hangs off instead,
--  for a field whose scroll bar belongs inside the same well. `opts.corner`
--  asks for a rounded panel rather than a capsule, which is what anything
--  taller than a single line wants.
function Reskin.Well(frame, opts)
	if not frame or Reskin.Forbidden(frame) or not frame.GetFrameLevel then
		return nil
	end
	opts = opts or {}

	local fill, edge = opts.fill or "glassSoft", opts.edge or "glassEdge"
	if not frame.__aetherPill then
		local pad = opts.inset or { 2, 0, 2, 0 }
		local far = opts.to or frame
		local well = opts.corner
			and A.Glass.CreatePanel(frame, { corner = opts.corner, fill = fill, edge = edge })
			or A.Glass.CreatePill(frame, { fill = fill, edge = edge })
		well:SetPoint("TOPLEFT", frame, "TOPLEFT", -(pad[1] or 0), pad[2] or 0)
		well:SetPoint("BOTTOMRIGHT", far, "BOTTOMRIGHT", pad[3] or 0, -(pad[4] or 0))

		-- BELOW what it surrounds. It is a child of the thing, so without this
		-- it draws over the words in the box.
		well:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1))
		frame.__aetherPill = well
	end

	frame.__aetherPill:ApplySkin(fill, edge)
	return frame.__aetherPill
end

--- One of the client's text fields, in glass.
--
--  `opts.keep` names regions the sweep must spare: a money box carries its
--  coin in the same background layer its border is drawn in, so a plain sweep
--  takes the coin as well and the player is typing gold into a nameless box.
-- The caret: how wide, how fast it blinks, and how tall when the client
-- declines to say. One unit, because a text cursor is a hairline - and 0.53,
-- which is the client's own blink for its own boxes.
local CARET_W, CARET_BLINK, CARET_H = 1, 0.53, 12

--- A text cursor for an edit box, drawn by us.
--
--  THE CLIENT DRAWS ONE AND IT IS NOT VISIBLE ON A DRESSED BOX. Reported as
--  a letter you can type into with nothing saying where you are.
--
--  WHAT IT IS NOT: nothing this file does can hide the engine's caret. It is
--  not a region, so no sweep reaches it; the well behind the box is a frame
--  level below the box's own; and the text drawn beside it is perfectly
--  legible, so neither the ink nor the font is missing. Beyond that the
--  engine does not say, and there is no API to ask - there is no
--  SetCursorColor on this client and no cursor region in any template.
--
--  So rather than keep guessing at somebody else's renderer, the caret is
--  OURS: drawn, placed and blinked here, where it can be seen, coloured and
--  checked. That is the same answer this addon reaches for
--  every other mark it needs: drawn at the accent, snapped to a whole unit,
--  and placed from the one thing the client tells us - OnCursorChanged hands
--  over the caret's x, y and HEIGHT in the box's own coordinates, which is
--  exactly the question and saves measuring the text ourselves.
function Reskin.Caret(box)
	if not box or box.__aetherCaret then return box and box.__aetherCaret end
	if not (box.CreateTexture and box.HookScript) then return nil end

	local caret = box:CreateTexture(nil, "OVERLAY")
	caret:SetTexture(A.Media.texture.flat)
	caret:SetWidth(CARET_W)
	caret:SetHeight(CARET_H)
	caret:Hide()
	box.__aetherCaret = caret

	--- Where the client says the cursor is. y is NEGATIVE downward from the
	--  box's top-left, which is already the sign SetPoint wants.
	local function place(_, x, y, _, h)
		caret:ClearAllPoints()
		caret:SetPoint("TOPLEFT", box, "TOPLEFT", x or 0, y or 0)
		if h and h > 0 then caret:SetHeight(h) end
	end
	box:HookScript("OnCursorChanged", place)

	-- ONLY WHILE THE BOX HAS FOCUS. A cursor in a field you are not typing in
	-- is a field claiming to be the one you are typing in - and with four of
	-- them on a letter, four of those.
	box:HookScript("OnEditFocusGained", function()
		caret.__aetherOn = 0
		caret:SetAlpha(1)
		caret:Show()
	end)
	box:HookScript("OnEditFocusLost", function() caret:Hide() end)

	-- AND IT BLINKS, because a cursor that does not is hard to find in a line
	-- of type and easy to mistake for a letter. On the box's own OnUpdate: it
	-- is on screen exactly when there is a caret to blink.
	box:HookScript("OnUpdate", function(_, elapsed)
		if not caret:IsShown() then return end
		caret.__aetherOn = (caret.__aetherOn or 0) + (elapsed or 0)
		if caret.__aetherOn >= CARET_BLINK then
			caret.__aetherOn = 0
			caret:SetAlpha(caret:GetAlpha() > 0.5 and 0 or 1)
		end
	end)

	Reskin.PaintCaret(box)
	return caret
end

--- The caret in the current skin's accent. Re-asserted on a restyle, which
--  is what changes what the accent IS.
function Reskin.PaintCaret(box)
	local caret = box and box.__aetherCaret
	if not caret then return end
	local a = A.Palette.c.accent
	caret:SetVertexColor(a[1], a[2], a[3], 1)
end

function Reskin.EditBox(box, opts)
	if not box or Reskin.Forbidden(box) then return nil end
	opts = opts or {}

	box.__aetherStripped = box.__aetherStripped or {}
	Reskin.StripExcept(box, box.__aetherStripped, opts.keep)

	local well = Reskin.Well(box, opts)

	-- A UNIT MARK AT THE FIELD'S RIGHT EDGE, where the field has one.
	--
	-- The client hangs the coin off the OUTSIDE of the gold box and the INSIDE
	-- of the silver and copper ones - +2 against -8 - because its own border
	-- art stops ten short on the narrow pair and the overhang had to be filled.
	-- With that art gone and one of our pills drawn to the box's real bounds,
	-- the row came up with one coin clear of its field and two sitting in
	-- theirs. Where the mark goes is the FIELD's business, not each coin's.
	--
	-- At the text inset, so the mark begins exactly where the digits stop -
	-- there is no room to put it outside, the gap to the next field is sixteen
	-- and a coin is thirteen.
	local pad = opts.inset or EDIT_INSET
	local mark = opts.unit
	if mark and mark.ClearAllPoints then
		mark:ClearAllPoints()
		mark:SetPoint("LEFT", box, "RIGHT", -pad, 0)
	end
	if box.SetTextInsets then
		box:SetTextInsets(pad, pad, 0, 0)
	end
	Reskin.Font(box, opts.style or "qlRow")
	A.Widgets.Color(box, A.Palette.c.text)

	-- AND SOMETHING SAYING WHERE YOU ARE IN IT. See Reskin.Caret: the
	-- client's own is one physical pixel and vanishes at the profile's
	-- scale, so this one is ours.
	Reskin.Caret(box)
	return well
end

--- One of the client's status bars in our fill.
function Reskin.StatusBar(bar, store, opts)
	if not bar or bar.__aetherFill then return end
	opts = opts or {}

	if store then Reskin.Strip(bar, store) end

	-- After the strip: the strip empties the fill texture along with the rest.
	if bar.SetStatusBarTexture then bar:SetStatusBarTexture(A.Media.texture.bar) end

	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if fill and opts.color and fill.SetVertexColor then
		local c = opts.color
		fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	end

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(A.Media.texture.flat)
	bg:SetAllPoints(bar)
	A.Widgets.Tint(bg, A.Palette:Track(opts.bgAlpha))

	bar.__aetherFill = bg
	return bg
end

--- A scroll bar: rail and arrows stripped, thumb down to a hairline.
function Reskin.ScrollBar(bar, store)
	if not bar or bar.__aetherScroll then return end

	if store then Reskin.Strip(bar, store) end

	-- TWO GENERATIONS OF SCROLL BAR, one function. The old one names its
	-- arrows ScrollUpButton and ScrollDownButton; MinimalScrollBar - which
	-- is what the Options window and everything else modern uses - calls
	-- them Back and Forward and puts its rail in a CHILD FRAME called Track.
	-- A sweep that only walks the bar's own regions leaves that rail drawing,
	-- which is three atlas slices of somebody else's grey down the side of
	-- our list.
	for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton",
		"Back", "Forward" }) do
		local btn = Reskin.Element(bar, key)
		if btn then
			Reskin.ClearButton(btn)
			if store then Reskin.Strip(btn, store) end
		end
	end

	if bar.Track then
		bar.Track.__aetherStore = bar.Track.__aetherStore or {}
		Reskin.Strip(bar.Track, bar.Track.__aetherStore)
	end

	-- A TRACK, always drawn. The thumb alone tells you a list scrolls only
	-- while you can see the thumb; a list you can scroll with no visible sign
	-- of it reads as a list that ends where the rows stop. The rail is the sign.
	if not bar.__aetherTrack then
		local track = bar:CreateTexture(nil, "BACKGROUND")
		track:SetTexture(A.Media.texture.flat)
		track:SetPoint("TOP", bar, "TOP", 0, -2)
		track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 2)
		track:SetWidth(A:Px(4))
		A.Widgets.Tint(track, A.Palette.c.textFaint, 0.22)
		bar.__aetherTrack = track
	end

	-- THE THUMB IS A TEXTURE on the old bar and a FRAME on the new one, and
	-- the frame's art is its own regions. Both, so one function covers both.
	local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
	if thumb then
		thumb:SetTexture(A.Media.texture.flat)
		A.Widgets.Tint(thumb, A.Palette.c.text, 0.45)
		if thumb.SetWidth then thumb:SetWidth(A:Px(6)) end
	end

	-- ...AND ON THE NEW ONE THE THUMB IS NOT THE BAR'S CHILD. MinimalScrollBar
	-- puts Thumb inside TRACK, so `bar.Thumb` is nil on every one of them and
	-- this dressed nothing at all - the Options window and the sidebar's panes
	-- kept Blizzard's grey thumb sliding down our rail. Both spellings, first
	-- one the bar has.
	local grip = bar.Thumb or (bar.Track and bar.Track.Thumb)
	if grip then
		grip.__aetherStore = grip.__aetherStore or {}
		Reskin.Strip(grip, grip.__aetherStore)
		if not grip.__aetherFill then
			-- OVERLAY, NOT ARTWORK, which is where the client draws its own
			-- three slices. MinimalScrollBarThumbScriptsMixin paints them again
			-- from its KeyValues on every enter, leave and press, so a fill in
			-- the same layer is covered the first time the pointer touches it.
			local fill = grip:CreateTexture(nil, "OVERLAY")
			fill:SetTexture(A.Media.texture.flat)
			fill:SetPoint("TOPLEFT", grip, "TOPLEFT", 1, -1)
			fill:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1, 1)
			grip.__aetherFill = fill
		end
		A.Widgets.Tint(grip.__aetherFill, A.Palette.c.text, 0.45)
	end

	bar.__aetherScroll = true
end

--- Our lettering on a client string, AT THE SIZE THE CLIENT CHOSE.
--
--  The size is kept deliberately. These strings sit in the client's own layout,
--  in rows and columns it measured for them, and handing them a size of ours
--  reflows somebody else's window - labels collide, numbers wrap, a stat row
--  goes to two lines. The family and the outline are ours; the metrics stay
--  theirs.
-- Below this, ink was chosen to be read on parchment. See Reskin.Font.
local DARK_INK = 0.35

--- Ink baked INTO the string rather than set on the font string.
--
--  A gossip quest title is `|cff000000<name>|r`: the black is an escape inside
--  the text, so GetTextColor answers the font object's colour and never sees
--  it, and SetTextColor cannot reach it either. Same test as below - an escape
--  dark enough to have been meant for parchment is rewritten, and a gold one is
--  left saying what it was put there to say.
function Reskin.Ink(fs, colour)
	if not fs or not fs.GetText or not fs.SetText or type(colour) ~= "table" then
		return
	end

	local text = fs:GetText()
	if type(text) ~= "string" or not text:find("|c", 1, true) then return end

	local hex = string.format("%02x%02x%02x",
		math.floor((colour[1] or 0) * 255 + 0.5),
		math.floor((colour[2] or 0) * 255 + 0.5),
		math.floor((colour[3] or 0) * 255 + 0.5))

	local inked = text:gsub("|c(%x%x)(%x%x)(%x%x)(%x%x)", function(a, r, g, b)
		local mean = (tonumber(r, 16) + tonumber(g, 16) + tonumber(b, 16)) / (3 * 255)
		if mean < DARK_INK then return "|c" .. a .. hex end
	end)

	if inked ~= text then fs:SetText(inked) end
end

--- A SimpleHTML is not a FontString, whatever it looks like.
--
--  It holds a font PER TEXT TYPE - P, H1, H2, H3 - so GetFont and SetFont
--  and SetTextColor all take the type as their first argument, and calling
--  them the FontString way is an outright error rather than a no-op:
--  "bad argument #1 to GetFont". That threw inside the book reader's
--  dresser and took the rest of the window with it.
--
--  The page of a quest item is one of these, which is why it is worth
--  knowing about at all.
local HTML_TYPES = { "P", "H1", "H2", "H3" }

local function IsSimpleHTML(fs)
	return fs.GetObjectType and fs:GetObjectType() == "SimpleHTML"
end

--- Our face and our ink on every text type it has.
function Reskin.SimpleHTML(fs, style, lighten)
	if not fs or not IsSimpleHTML(fs) then return false end

	for _, kind in ipairs(HTML_TYPES) do
		local ok, file, size, flags = pcall(fs.GetFont, fs, kind)
		if ok and type(size) == "number" and size > 0 then
			local want = A.Media and A.Media.FontFor and A.Media:FontFor(style)
			if want then pcall(fs.SetFont, fs, kind, want, size, flags) end
		end
		if lighten then
			-- No reading first. GetTextColor on one of these answers for a
			-- type too, and a page printed on paper is dark in every type it
			-- has - there is nothing here that was coloured to mean
			-- something, the way a gold quest heading is.
			pcall(fs.SetTextColor, fs, kind, lighten[1], lighten[2], lighten[3],
				lighten[4] or 1)
		end
	end
	return true
end

function Reskin.Font(fs, style, lighten)
	if not fs or not fs.GetFont or not fs.SetFont then return end

	-- A STRING, NOT A FRAME. Four of the lines on the postbox's receipt LOOK
	-- like text and are MoneyFrames - gold, silver and copper each in a string
	-- of their own - and a caller naming them alongside the real strings is a
	-- caller who has not looked. Nothing is styled by being the wrong shape.
	if fs.GetObjectType then
		local kind = fs:GetObjectType()
		if kind ~= "FontString" and kind ~= "SimpleHTML" then return end
	end
	if Reskin.SimpleHTML(fs, style, lighten) then return end

	local _, size = fs:GetFont()
	if type(size) == "number" and size > 0 then
		fs._aetherSize = math.floor(size + 0.5)
	end
	A.Widgets.Restyle(fs, style or "pnBody")

	-- INK CHOSEN FOR PARCHMENT, and only that.
	--
	-- The rule everywhere else is that the client's colours are meant and are
	-- left alone: a stat that went up is green, a label is gold, a resistance is
	-- its school's colour. That rule is right for a window whose background we
	-- did not change, and wrong for the ones an NPC opens - a quest's text and a
	-- gossip option are near-black because they were printed on paper, and on
	-- glass they are a dark smudge.
	--
	-- So the test is the colour itself rather than the window: anything DARK was
	-- chosen for paper and is lifted; anything else was chosen to mean something
	-- and is not. Gold headings and item-quality names come through untouched.
	if lighten and fs.GetTextColor then
		local r, g, b = fs:GetTextColor()
		if type(r) == "number" and (r + g + b) / 3 < DARK_INK then
			fs:SetTextColor(lighten[1], lighten[2], lighten[3], lighten[4] or 1)
		end

		-- The other half of the same rule: some of this text carries its colour
		-- inside itself, where neither the test above nor SetTextColor reaches.
		Reskin.Ink(fs, lighten)
	end
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
