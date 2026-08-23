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
}

-- The four a Button draws itself.
local BUTTON_STATES = { "Normal", "Pushed", "Highlight", "Disabled" }

-- How much of the accent a picked row takes. Enough to find at a glance and
-- not enough to fight the words printed on it.
local ROW_MARK_ALPHA = 0.14

-- How far in from an edit box's own edge its text starts. A box draws from
-- that edge, and the well we put round it has a rim there - so the caret and
-- the first character sat on the rim. The trade skill's count box is the one
-- that shows it plainly: a single digit hard against the side.
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
--  on it. Nothing in this file or in Panels.lua guarded for it, and the trade
--  window's dresser stopped dead the first time one was reached.
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
		if region.SetAtlas then pcall(region.SetAtlas, region, "") end
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
--
-- The panels are mostly not panels. A character sheet is item slots, tabs,
-- reputation bars, a scroll bar and a dozen check boxes, and each kind wants
-- the same treatment wherever it turns up. These are that treatment; a module
-- says which widgets, not how.

--- One of the client's item slots, wearing the cell our bags already use.
--
--  NOT stripped. Strip zeroes every texture region it finds, and on a slot one
--  of those regions is the ITEM'S OWN ICON - it would come back empty with the
--  border still gone. A slot's art is its border, which is the normal texture,
--  which is ClearButton's job.
function Reskin.Slot(btn, opts)
	if not btn or Reskin.Forbidden(btn) then return end
	opts = opts or {}

	-- THE ITEM'S OWN PICTURE, under any of the names the client gives it:
	-- `$parentIconTexture` on the old item button, `Icon` on the newer ones,
	-- `icon` once we have been past. Resolved FIRST, because the sweep and
	-- the cell both have to be talking about the same region - miss it and
	-- the sweep blanks the item and the cell draws an empty texture over
	-- the hole.
	local icon = opts.icon or Reskin.Element(btn, "IconTexture")
		or Reskin.Element(btn, "Icon")

	-- BEFORE the "already done" test, not after it. Switching the module off
	-- hands the client every texture back, and switching it on again runs this
	-- a second time - so a dresser that returns early on its own marker returns
	-- before it has taken the art it just gave back.
	Reskin.ClearButton(btn)

	-- SOME SLOTS KEEP THEIR PLATE IN A BACKGROUND REGION rather than in the
	-- normal texture - a mail attachment is one - and ClearButton cannot
	-- reach that. Given a store the regions come off too, sparing the
	-- picture, which is in the same layer.
	if type(opts.store) == "table" then
		Reskin.StripExcept(btn, opts.store, icon and { icon } or nil)
	end
	if btn.__aetherSlot then return end

	local size = opts.size or (btn.GetWidth and btn:GetWidth()) or 36
	A.Widgets.DecorateSlot(btn, size, { icon = icon, count = false })

	-- The client's own count, re-roled rather than replaced.
	local count = Reskin.Element(btn, "Count")
	if count and count.SetText then
		A.Widgets.Restyle(count, "stack")
		A.Widgets.Color(count, A.Palette.c.text)
	end

	btn.__aetherSlot = true
end

--- A glass surround for something the client drew a border round - or should
--- have and did not.
--
--  Every text field in the game is the same three slices of
--  `Common-Input-Border`, drawn as background regions of the box itself; and
--  the letter you write in the postbox has no border at all, because the
--  stationery behind it WAS the frame. Both want the same answer - one of our
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
--- A button whose picture is one of its own regions, in the same cell.
--
--  Slot cannot be used and neither can Strip. A spell button keeps its icon in
--  a region beside the ring, and a spellbook school tab keeps its icon AS the
--  normal texture - the client calls SetNormalTexture with the school's image
--  every time it refreshes them. So one sweep would blank the picture and the
--  other would blank it through the setter. This clears everything except the
--  picture and the checked mark, and dresses what is left as a cell.
--
--  `opts.icon` names the picture; without one the normal texture is taken to be
--  it, which is the school tab's case.
function Reskin.IconButton(btn, store, opts)
	if not btn then return end
	opts = opts or {}

	local icon = opts.icon or (btn.GetNormalTexture and btn:GetNormalTexture())
	local checked = btn.GetCheckedTexture and btn:GetCheckedTexture()

	local keep = {}
	if icon then keep[icon] = true end
	if checked then keep[checked] = true end

	if type(store) == "table" then ClearRegions(btn, store, keep) end

	-- The state textures through the setters as well, for the reason
	-- ClearButton exists: hiding the region loses to the client, which shows the
	-- pushed one on mousedown with nothing of ours in between. The one that is
	-- the picture is skipped, and the checked mark is kept and re-tinted - it is
	-- how an open profession says it is open.
	btn.__aetherState = btn.__aetherState or {}
	for _, kind in ipairs(BUTTON_STATES) do
		local get, set = btn["Get" .. kind .. "Texture"], btn["Set" .. kind .. "Texture"]
		local tex = get and get(btn)
		if set and (icon == nil or tex ~= icon) then
			if btn.__aetherState[kind] == nil then
				local path = tex and tex.GetTexture and tex:GetTexture()
				if path == 0 then path = nil end
				btn.__aetherState[kind] = path or false
			end
			set(btn, 0)
		end
	end

	-- The cell itself only once - the clearing above happens every time, because
	-- switching the module off gives the client its art back and switching it on
	-- again has to take it away a second time.
	if not btn.__aetherSlot then
		local size = opts.size or (btn.GetWidth and btn:GetWidth()) or 32
		A.Widgets.DecorateSlot(btn, size, { icon = icon, count = false })
		btn.__aetherSlot = true
	end

	if checked and checked.SetVertexColor then
		local c = A.Palette.c.accent
		checked:SetVertexColor(c[1], c[2], c[3], 0.55)
	end

	return btn
end

-- How big our chevron sits on a button whose whole job is the arrow. The
-- client's own art is around 20 across on a 23px button, and a mark that
-- size reads as a picture rather than as a direction.
local ARROW_GLYPH = 10

--- A button that is nothing but an arrow: a page turner, a count spinner.
--
--  The client draws these as a PICTURE OF A BUTTON - the arrow and the plate
--  it stands on are one texture - so taking the plate off takes the arrow
--  with it and leaves a live control with nothing at all drawn on it. Which
--  is what the postbox's page turners have been since they were skinned.
--
--  So both go, and one of our surfaces goes back with our own chevron on it.
--  `facing` is a plain compass direction, turned by the one piece of code
--  that owns which way a chevron points.
-- The two marks a page turn wears. Angle quotes rather than Blizzard's
-- engraved arrows: with the art off there is nothing left on the button to
-- click at all.
local GLYPH_PREV, GLYPH_NEXT = string.char(226, 128, 185), string.char(226, 128, 186)

--- Every button on a frame that is really a button, dressed as one.
--
--  Found by SHAPE - a Button with a label on it - because these windows carry
--  a dozen between them across three game versions and naming them all is a
--  list that goes stale. Create, Create All, Close, Send, Reply, Delete.
--
--  `skip` is the set that is NOT one, and it is the whole reason this is a
--  function rather than a loop written out three times. A LIST ROW is a Button
--  with a label on it too: every recipe in a trade skill, every letter in the
--  postbox. Swept by shape they all got a pressable surface, and the list came
--  up as a column of pills - which is not how a row is drawn anywhere else in
--  this interface. Three separate sweeps had the same bug because there were
--  three separate sweeps.
function Reskin.Buttons(frame, style, skip)
	if not (frame and frame.GetChildren) or Reskin.Forbidden(frame) then return end

	for _, child in ipairs({ frame:GetChildren() }) do
		-- ...AND NOT ONE THE CLIENT HAS PUT OUT OF REACH. A forbidden frame is
		-- still in its parent's child list, and asking it what kind of object
		-- it is throws - so this loop was the last statement in the trade
		-- window's dresser and the one that killed it.
		--
		-- ...AND NOT A TAB. A tab is a Button with a label on it and a child of
		-- the window, which is exactly what this sweep looks for - so on the
		-- social window all four of its tabs came back wearing the pill every
		-- pressable thing here wears, on top of the tab treatment they had
		-- already been given. See Reskin.Tab: a tab and a button are not the
		-- same control and are deliberately not drawn the same way.
		if not Reskin.Forbidden(child)
			and child.GetObjectType and child:GetObjectType() == "Button"
			and child.GetFontString and child:GetFontString()
			and not child.__aetherTab
			and not (skip and skip[child]) and not child.__aetherSkin then
			Reskin.Button(child, style)
		end
	end
end

--- A page turn: one mark on a bare button, and nothing round it.
--
--  ONE LOOK FOR ALL OF THEM. There were two: the spellbook's, which is a mark
--  on nothing, and the postbox's, which is a filled circle - and they are the
--  same control doing the same job one window apart. 15c: a chevron means
--  navigation, and navigation reads as chrome, not as an action you choose.
function Reskin.PageTurn(btn, facing, store)
	if not btn then return nil end

	Reskin.ClearButton(btn)
	if type(store) == "table" then Reskin.Strip(btn, store) end

	-- The circle comes off too, for a button that used to wear one.
	if btn.__aetherRound then btn.__aetherRound:Hide() end
	if btn.__aetherSkin then btn.__aetherSkin:Hide() end

	local mark = btn.__aetherMark
	if not mark then
		mark = A.Widgets.Text(btn, "pnTitle", "CENTER")
		mark:SetPoint("CENTER", btn, "CENTER", 0, 0)
		btn.__aetherMark = mark
	end
	-- AND THE WORD COMES OFF. The postbox's turns carry "Prev" and "Next", and
	-- each is anchored OUTSIDE its own button - Prev's to the right of it,
	-- Next's to the left - so two turns a chevron apart print one word over the
	-- other. The mark says which way it goes; saying it twice is what made it
	-- unreadable.
	--
	-- A REGION OF THE BUTTON, not the button's own label: it is an unnamed
	-- FontString in the artwork layer, so GetFontString never sees it and
	-- clearing that alone left both words exactly where they were.
	local word = btn.GetFontString and btn:GetFontString()
	if word and word.SetText then word:SetText("") end
	if btn.GetRegions then
		for _, r in ipairs({ btn:GetRegions() }) do
			-- Not our own mark, which is a region of the button too. It happens
			-- to be re-set a line later, but a sweep that relies on the order of
			-- the two is a sweep that breaks the day either moves.
			if r ~= mark and r.GetObjectType
				and r:GetObjectType() == "FontString" and r.SetText then
				r:SetText("")
			end
		end
	end

	mark:SetText(facing == "RIGHT" and GLYPH_NEXT or GLYPH_PREV)
	A.Widgets.Color(mark, A.Palette.c.textDim)
	mark:Show()
	return mark
end

function Reskin.ArrowButton(btn, facing, store)
	if not btn then return nil end

	Reskin.ClearButton(btn)
	if type(store) == "table" then Reskin.Strip(btn, store) end

	-- A CIRCLE, which is what a pager is in this interface. It was the shared
	-- button surface - a rounded rectangle, the same one Create and Send wear -
	-- and a page turner is not an action you read and choose, it is a direction.
	if not btn.__aetherArrow then
		A.Widgets.RoundButton(btn, { attach = btn, fill = "glassSoft" })
		btn.__aetherArrow = btn.__aetherRound
		btn.__aetherArrow:SetTexture(A.Media.texture.chevron)
		btn.__aetherArrow:SetSize(ARROW_GLYPH, ARROW_GLYPH)
	end

	A.Widgets.FaceChevron(btn.__aetherArrow, facing)
	A.Widgets.PaintRound(btn, false)
	return btn.__aetherArrow
end

--- A tab along the edge of a client panel.
--
--  Blizzard draws these in three pieces - left cap, stretched middle, right cap
--  - plus a disabled set of all three, so there is no single texture to swap.
--  All six come off, and what goes back is NOT a surface.
--
--  It was a pill, filled when selected, which is what every pressable thing in
--  this interface wears. That made a tab and a button look the same, and they
--  are not the same: a button does a thing, a tab changes which view of the
--  frame you are looking at. See W.Tab for the language they share instead -
--  bare text on a hairline, and a mark under the one you are on.
function Reskin.Tab(tab, store, style, opts)
	if not tab then return end
	opts = opts or {}

	Reskin.ClearButton(tab)
	if store then Reskin.Strip(tab, store) end

	local text = Reskin.Element(tab, "Text")
		or (tab.GetFontString and tab:GetFontString())

	local mark = A.Widgets.Tab(tab, {
		label = text, edge = opts.edge, icon = opts.icon, art = opts.art,
		rail = opts.rail,
	})
	tab.__aetherTab = mark

	if text and text.SetText then
		A.Widgets.Restyle(text, style or "tbCardTitle")
	end
	A.Widgets.TabState(tab, tab.__aetherSelected, false)
	return mark
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
--- An old scroll frame, whose TROUGH IS DRAWN ON THE FRAME.
--
--  UIPanelScrollBarTemplate carries only its two arrows and a thumb. The
--  rail behind them is $parentTop, $parentBottom and $parentMiddle, and
--  those are declared in the SCROLL FRAME's own layers - so reskinning the
--  bar leaves a black trough with stone caps exactly where it was, which is
--  most of what a scroll bar looks like.
--
--  Only the frame's REGIONS go. Its content is a child frame, not a region,
--  so there is nothing here that can take the thing you came to read.
--  `opts.headroom` reaches the well UP past the scroll frame, for a window
--  whose list carries a control or two above it - a collapse-all, a progress
--  bar. Those are content: they act on the list and belong in the recess with
--  it rather than floating between two wells on bare glass.
function Reskin.ScrollFrame(sf, store, opts)
	if not sf or Reskin.Forbidden(sf) then return nil end
	opts = opts or {}

	sf.__aetherStore = sf.__aetherStore or {}
	Reskin.Strip(sf, sf.__aetherStore)

	-- IN A WELL, like every other list in this interface. 15b: anything that
	-- can grow sits in a recess, and the recess is the ONLY scroll container.
	-- Our own windows have had this since the quest log was built; the
	-- client's never did, so a trade skill's recipe list and its detail pane
	-- floated on bare glass with nothing marking where either began or ended.
	--
	-- Below the scroll frame, not around it: the rows are children of the
	-- scrolling child and draw over anything at the scroll frame's own level.
	local well = sf.__aetherWell
	if not well then
		local host = (sf.GetParent and sf:GetParent()) or sf
		well = A.Widgets.ContentWell(host)
		well:SetFrameLevel(math.max(0, (sf:GetFrameLevel() or 1) - 1))
		if well.EnableMouse then well:EnableMouse(false) end
		sf.__aetherWell = well
	end

	-- RE-ANCHORED EVERY TIME, not only when the well is built: the headroom
	-- above a list is the room a control needs, and what is up there can change
	-- between one dress and the next.
	local out = well.__aetherWellOut or 0
	well:ClearAllPoints()
	well:SetPoint("TOPLEFT", sf, "TOPLEFT", -out, out + (opts.headroom or 0))
	well:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", out, -out)
	well:ApplySkin("wellFill", "wellEdge")

	local bar = Reskin.Element(sf, "ScrollBar")
	if bar then
		bar.__aetherStore = bar.__aetherStore or {}
		Reskin.ScrollBar(bar, bar.__aetherStore)
	end
	return bar
end

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

	if bar.Thumb then
		bar.Thumb.__aetherStore = bar.Thumb.__aetherStore or {}
		Reskin.Strip(bar.Thumb, bar.Thumb.__aetherStore)
		if not bar.Thumb.__aetherFill then
			local fill = bar.Thumb:CreateTexture(nil, "ARTWORK")
			fill:SetTexture(A.Media.texture.flat)
			fill:SetPoint("TOPLEFT", bar.Thumb, "TOPLEFT", 1, -1)
			fill:SetPoint("BOTTOMRIGHT", bar.Thumb, "BOTTOMRIGHT", -1, 1)
			bar.Thumb.__aetherFill = fill
		end
		A.Widgets.Tint(bar.Thumb.__aetherFill, A.Palette.c.text, 0.45)
	end

	bar.__aetherScroll = true
end

-- Air between a check box and the words beside it.
local CHECK_LABEL_GAP = 6

--- One of the client's toggles, in our own chip: its art off and ours on.
--
--  `round` makes it a radio rather than a check box. Both go through here
--  because everything below is the same for the two of them - the sweep, the
--  chip, the state, the label off the mark's edge - and the shape is the only
--  thing that differs. Written as two functions, the postbox's pair would have
--  been the third copy of a label anchor that had already drifted twice.
local function Toggle(box, store, round)
	if not box then return end

	Reskin.ClearButton(box)

	-- EVERYTHING, THE CLIENT'S TICK INCLUDED. It used to be spared, and the
	-- box carried Blizzard's own check mark: their art, in their weight, in
	-- the middle of a control that is otherwise entirely ours. The atlas has
	-- had a tick on it since the console's channel list needed one.
	if type(store) == "table" then Reskin.Strip(box, store) end


	-- THE SHAPE SAYS WHICH IT IS. Square is on or off; round is one of
	-- several. Blizzard draws BOTH as a round badge, so an independent toggle
	-- said the wrong thing about what pressing it does before anybody had read
	-- the label beside it - and it was drawn at the client's own button width,
	-- which is the hit area rather than the mark, so it came out the size of a
	-- bag slot.
	local chip = A.Widgets.CheckBox(box, { attach = box, round = round })
	A.Widgets.CheckState(box, box.GetChecked and box:GetChecked() or false)

	-- AND IT ANSWERS THE CLIENT. A check box is toggled by Blizzard's own
	-- OnClick as often as by ours, and a mark drawn once at dress time is a
	-- mark that is right until the first press.
	if box.HookScript and not box.__aetherCheckHook then
		box.__aetherCheckHook = true
		box:HookScript("OnClick", function(self)
			A.Widgets.CheckState(self, self.GetChecked and self:GetChecked())
		end)
		box:HookScript("OnShow", function(self)
			A.Widgets.CheckState(self, self.GetChecked and self:GetChecked())
		end)
	end

	-- AND ITS LABEL OFF THE EDGE OF THE MARK, not off the edge of the button.
	--
	-- Blizzard's check box is a small square inside a much larger transparent
	-- hit area, and its label is anchored flush to that - which clears the
	-- square by several pixels. Ours is the size of the MARK and centred in
	-- the hit area, so measuring the gap from the button's left edge put the
	-- words underneath it. The mark is the thing the words have to clear, so
	-- the mark is what they hang off.
	local label = Reskin.Element(box, "Text")
	if label and label.SetPoint then
		label:ClearAllPoints()
		label:SetPoint("LEFT", chip, "RIGHT", CHECK_LABEL_GAP, 0)
		box.__aetherBoxLabel = true
	end

	box.__aetherCheck = chip
	return chip
end

--- A check box: on or off, on its own.
function Reskin.CheckBox(box, store) return Toggle(box, store, false) end

--- A radio button: one of several, so a disc rather than a box.
--
--  The others in its group are turned off by the client CALLING SetChecked on
--  them rather than by anybody clicking them, so the hook above cannot see it
--  happen. Whatever drives the group has to say so - see the postbox, where
--  both paths go through one global and that is what is hooked.
function Reskin.Radio(box, store) return Toggle(box, store, true) end

-- A tree's disclosure marks, in type rather than in Blizzard's stone buttons.
-- U+2212, the real minus: a hyphen next to a full-height plus reads as a dash
-- that has lost something.
local GLYPH_PLUS, GLYPH_MINUS = "+", "\226\136\146"

--- One collapse control: its stone plus or minus off, ours on.
--
--  Safe to call repeatedly, and it HAS to be: the client re-sets the button's
--  normal texture every time it refreshes the list, so a mark applied once at
--  dress time is a mark you see until the first click.
function Reskin.Collapse(btn, style)
	if not btn or not btn.SetNormalTexture then return end

	Reskin.ClearButton(btn)

	local glyph = btn.__aetherGlyph
	if not glyph then
		glyph = A.Widgets.Text(btn, style or "pnBody", "CENTER")

		-- ON THE TEXTURE WE JUST EMPTIED, not in the middle of the button. A
		-- skill header's button is the whole 285px row with its mark at the far
		-- left and the group's name beside it, so a glyph centred on the button
		-- lands in the middle of the words. Clearing a texture does not move
		-- it: the region keeps the client's own anchors, which are exactly
		-- where the mark belongs.
		local slot = btn.GetNormalTexture and btn:GetNormalTexture()
		if slot and slot.GetObjectType then
			glyph:SetPoint("CENTER", slot, "CENTER", 0, 0)
		else
			glyph:SetPoint("CENTER", btn, "CENTER", 0, 0)
		end

		btn.__aetherGlyph = glyph
	end

	glyph:SetText(btn.isExpanded and GLYPH_MINUS or GLYPH_PLUS)
	A.Widgets.Color(glyph, A.Palette.c.textDim)
	return glyph
end

--- The bar the client slides onto whichever row is picked, in our own ink.
--
--  Every one of these windows keeps ONE highlight frame and moves it onto the
--  row you clicked, with Blizzard's blue listbox slice drawn on it. Stripping
--  it leaves the list with nothing at all saying which row you are on; leaving
--  it leaves somebody else's blue lying across our glass.
--
--  A wash rather than a slice: the accent at a low alpha across the whole
--  frame, which is what a selected row looks like everywhere else in this
--  interface.
function Reskin.RowMark(frame, store)
	if not frame then return nil end

	Reskin.Strip(frame, store)

	local wash = frame.__aetherRowMark
	if not wash then
		wash = frame:CreateTexture(nil, "BACKGROUND")
		wash:SetTexture(A.Media.texture.flat)
		wash:SetAllPoints(frame)
		frame.__aetherRowMark = wash
	end

	local c = A.Palette.c.accent
	wash:SetVertexColor(c[1], c[2], c[3], ROW_MARK_ALPHA)
	return wash
end

function Reskin.ReleaseCollapse(btn)
	if not btn then return end
	if btn.__aetherGlyph then
		btn.__aetherGlyph:Hide()
		btn.__aetherGlyph = nil
	end
	Reskin.RestoreButton(btn)
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

-- Font objects for strings we are not allowed to set a font on.
--
-- The menu system wraps its own font strings and forbids SetFont - READING the
-- key is enough to trip its assert, so nothing on that path may go near it -
-- but SetFontObject is permitted, and Media:SetFont takes an object as happily
-- as it takes a string. One object per role and size, because a font object
-- carries the size with it.
local lockedFonts, lockedCount = {}, 0

local function LockedFont(style, size)
	local key = tostring(style) .. ":" .. tostring(size)
	local obj = lockedFonts[key]
	if not obj and CreateFont then
		lockedCount = lockedCount + 1
		obj = CreateFont("AetherUILockedFont" .. lockedCount)
		A.Media:SetFont(obj, style, size)
		lockedFonts[key] = obj
	end
	return obj
end

--- Our lettering on a string that may only be styled through a font object.
--
--  The colour is read off first and put back after: a font object carries one
--  of its own, and these strings are green, red and grey for a reason.
function Reskin.FontObject(fs, style, lighten)
	if not fs or not fs.SetFontObject then return end

	local size
	if fs.GetFont then
		local _, got = fs:GetFont()
		if type(got) == "number" and got > 0 then size = math.floor(got + 0.5) end
	end

	local obj = LockedFont(style or "pnBody", size)
	if not obj then return end

	local r, g, b, a
	if fs.GetTextColor then r, g, b, a = fs:GetTextColor() end

	fs:SetFontObject(obj)
	fs._aetherStyle = style or "pnBody"
	fs._aetherSize = size

	if type(r) == "number" and fs.SetTextColor then
		fs:SetTextColor(r, g, b, a)
		if lighten and (r + g + b) / 3 < DARK_INK then
			fs:SetTextColor(lighten[1], lighten[2], lighten[3], lighten[4] or 1)
		end
	end
	if lighten then Reskin.Ink(fs, lighten) end
end

--- Every string inside a frame, ours. Colour is left alone.
--
--  The client colours these itself and means it: a stat that changed is green,
--  a label is gold, a resistance is its school's colour. Re-roling the type
--  without touching the colour keeps all of that and still gets rid of the
--  lettering from another interface.
--  `lighten` is passed straight down to Reskin.Font: give it a colour and any
--  string dark enough to have been meant for parchment is lifted to it.
--  `locked` says the strings belong to something that forbids SetFont.
function Reskin.Fonts(frame, style, depth, lighten, locked)
	if Reskin.Forbidden(frame) then return end
	if not frame or type(frame) ~= "table" then return end
	depth = depth or 0
	if depth > 4 then return end            -- deep enough for any of these

	if frame.GetRegions then
		for _, region in ipairs({ frame:GetRegions() }) do
			if region and region.GetObjectType and region:GetObjectType() == "FontString" then
				if locked then
					Reskin.FontObject(region, style, lighten)
				else
					Reskin.Font(region, style, lighten)
				end
			end
		end
	end

	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			Reskin.Fonts(child, style, depth + 1, lighten, locked)
		end
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
