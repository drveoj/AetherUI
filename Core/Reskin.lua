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

--- Take the client's art off `frame`, recording enough to put it back.
--
--  `store` is the caller's table, one per skinned frame, and holds everything
--  taken from that frame AND from the child frames its art hides in. Pass the
--  same store every time: this runs again on every show, because art the client
--  reveals later has to be taken down too.
function Reskin.Strip(frame, store)
	if not frame or not frame.GetRegions or type(store) ~= "table" then return end

	ClearRegions(frame, store, nil)

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
	if not frame or not frame.GetRegions or type(store) ~= "table" then return end

	local keep = {}
	for _, key in ipairs(names or {}) do
		local region = Reskin.Element(frame, key)
		if type(region) == "table" then keep[region] = true end
	end

	ClearRegions(frame, store, keep)
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
	if not btn then return end
	opts = opts or {}

	-- BEFORE the "already done" test, not after it. Switching the module off
	-- hands the client every texture back, and switching it on again runs this
	-- a second time - so a dresser that returns early on its own marker returns
	-- before it has taken the art it just gave back.
	Reskin.ClearButton(btn)
	if btn.__aetherSlot then return end

	local icon = Reskin.Element(btn, "IconTexture") or btn.icon
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

--- A tab along the bottom of a client panel.
--
--  Blizzard draws these in three pieces - left cap, stretched middle, right cap
--  - plus a disabled set of all three, so there is no single texture to swap.
--  All six come off and a pill goes behind.
function Reskin.Tab(tab, store, style)
	if not tab or tab.__aetherTab then return end

	Reskin.ClearButton(tab)
	if store then Reskin.Strip(tab, store) end

	local pill = A.Glass.CreatePill(tab, { fill = "glass", edge = "glassEdgeHi" })
	pill:SetPoint("TOPLEFT", tab, "TOPLEFT", 2, -2)
	pill:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 2)
	pill:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
	tab.__aetherTab = pill

	local text = Reskin.Element(tab, "Text")
		or (tab.GetFontString and tab:GetFontString())
	if text and text.SetText then
		-- The caller's role where it has one: a tab in a client window wants
		-- outlined type, because its label sits over whatever that window is
		-- showing rather than over an even fill of ours.
		A.Widgets.Restyle(text, style or "tbCardTitle")
		A.Widgets.Color(text, A.Palette.c.text)
	end
	return pill
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
	bg:SetVertexColor(1, 1, 1, opts.bgAlpha or 0.14)

	bar.__aetherFill = bg
	return bg
end

--- A scroll bar: rail and arrows stripped, thumb down to a hairline.
function Reskin.ScrollBar(bar, store)
	if not bar or bar.__aetherScroll then return end

	if store then Reskin.Strip(bar, store) end

	for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
		local btn = Reskin.Element(bar, key)
		if btn then
			Reskin.ClearButton(btn)
			if store then Reskin.Strip(btn, store) end
		end
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
		local f = A.Palette.c.textFaint
		track:SetVertexColor(f[1], f[2], f[3], 0.22)
		bar.__aetherTrack = track
	end

	local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
	if thumb then
		thumb:SetTexture(A.Media.texture.flat)
		local c = A.Palette.c.text
		thumb:SetVertexColor(c[1], c[2], c[3], 0.45)
		if thumb.SetWidth then thumb:SetWidth(A:Px(6)) end
	end

	bar.__aetherScroll = true
end

-- Air between a check box and the words beside it.
local CHECK_LABEL_GAP = 6

--- A check box: box art off, the tick kept and re-tinted.
--
--  The tick is the one part worth keeping - it reads as a tick at any size and
--  nothing of ours would read better. Only the box around it goes.
function Reskin.CheckBox(box, store)
	if not box then return end

	Reskin.ClearButton(box)

	-- EVERYTHING BUT THE TICK. The tick is a region of the button like the box
	-- around it, so a plain strip takes both - and a check box with no tick in
	-- it is a check box that never looks checked, whatever the client thinks its
	-- state is.
	local checked = box.GetCheckedTexture and box:GetCheckedTexture()
	if type(store) == "table" then
		ClearRegions(box, store, checked and { [checked] = true } or nil)
	end

	if checked and checked.SetVertexColor then
		local c = A.Palette.c.text
		checked:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	end

	-- AND ITS LABEL OFF THE EDGE OF IT. Blizzard's check box art is a small
	-- square inside a larger transparent button, so a label anchored flush to
	-- that button still cleared the box by several pixels. Ours fills the
	-- button, and the words ended up touching it.
	local label = Reskin.Element(box, "Text")
	if label and label.SetPoint and not box.__aetherBoxLabel then
		box.__aetherBoxLabel = true
		label:ClearAllPoints()
		label:SetPoint("LEFT", box, "RIGHT", CHECK_LABEL_GAP, 0)
	end

	-- The chip once; the clearing above on every pass, for the same reason
	-- Slot re-clears - off gives the client its art back.
	if box.__aetherCheck then
		box.__aetherCheck:SetColors(A.Palette.c.glass, A.Palette.c.glassEdgeHi)
		return box.__aetherCheck
	end

	-- A BADGE, NOT A PILL. A pill whose width equals its height is a circle made
	-- of two cap slices meeting in the middle with a zero-width centre between
	-- them - the seam Core\Glass.lua's header warns about, and the one place
	-- snapping cannot save it. That came back as the jagged ring reported around
	-- this box, and W.CreateBadge exists because the tooltip's level chip and
	-- Zen's corner glyph both learned it first: chip art authored at 64 for a
	-- disc drawn near 26, rather than a shape stretched into a circle.
	local size = (box.GetWidth and box:GetWidth()) or 26
	local chip = A.Widgets.CreateBadge(box, { size = size })
	chip:SetPoint("CENTER", box, "CENTER", 0, 0)
	chip:SetFrameLevel(math.max(0, box:GetFrameLevel() - 1))
	chip:SetColors(A.Palette.c.glass, A.Palette.c.glassEdgeHi)

	-- A badge carries a number. This one carries the client's own tick, which is
	-- a region of the button above it.
	chip.label:Hide()

	box.__aetherCheck = chip
	return chip
end

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
function Reskin.Font(fs, style)
	if not fs or not fs.GetFont or not fs.SetFont then return end

	local _, size = fs:GetFont()
	if type(size) == "number" and size > 0 then
		fs._aetherSize = math.floor(size + 0.5)
	end
	A.Widgets.Restyle(fs, style or "pnBody")
end

--- Every string inside a frame, ours. Colour is left alone.
--
--  The client colours these itself and means it: a stat that changed is green,
--  a label is gold, a resistance is its school's colour. Re-roling the type
--  without touching the colour keeps all of that and still gets rid of the
--  lettering from another interface.
function Reskin.Fonts(frame, style, depth)
	if not frame or type(frame) ~= "table" then return end
	depth = depth or 0
	if depth > 4 then return end            -- deep enough for any of these

	if frame.GetRegions then
		for _, region in ipairs({ frame:GetRegions() }) do
			if region and region.GetObjectType and region:GetObjectType() == "FontString" then
				Reskin.Font(region, style)
			end
		end
	end

	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			Reskin.Fonts(child, style, depth + 1)
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
