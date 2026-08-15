--[[--------------------------------------------------------------------------
	AetherUI :: Widgets

	The small parts every module builds out of: bars, orbs, text, icon slots.
	Nothing here knows about units or combat; it is all pure presentation.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local W = {}
A.Widgets = W

local Media = A.Media

-- ---------------------------------------------------------------------------
-- gradients
--
-- The colour-gradient API was reshaped in 10.0: SetGradientAlpha(orientation,
-- r,g,b,a, r,g,b,a) became SetGradient(orientation, ColorMixin, ColorMixin).
-- Classic Era has been rebased onto the newer one, but pinned/older clients and
-- some private builds still expose the old shape, so probe once and cache.
-- ---------------------------------------------------------------------------

local gradientMode

local function SetGradient(tex, orientation, c1, c2)
	local r1, g1, b1, a1 = c1[1], c1[2], c1[3], c1[4] or 1
	local r2, g2, b2, a2 = c2[1], c2[2], c2[3], c2[4] or 1

	if gradientMode == nil then
		if tex.SetGradient and CreateColor then
			local ok = pcall(tex.SetGradient, tex, orientation,
				CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
			gradientMode = ok and "new" or false
			if ok then return end
		end
		if tex.SetGradientAlpha then
			local ok = pcall(tex.SetGradientAlpha, tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
			gradientMode = ok and "old" or false
			if ok then return end
		end
		gradientMode = false
	end

	if gradientMode == "new" then
		tex:SetGradient(orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
	elseif gradientMode == "old" then
		tex:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	else
		-- No gradient support at all: fall back to the mean of the two stops.
		tex:SetVertexColor((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
	end
end

W.SetGradient = SetGradient

-- ---------------------------------------------------------------------------
-- masks
--
-- Classic Era does have MaskTexture, but guard anyway: an addon that hard-errors
-- on a client without it is worse than one that renders square corners.
-- ---------------------------------------------------------------------------

local function AddMask(region, owner, maskPath, anchorTo)
	if not region or not region.AddMaskTexture or not owner.CreateMaskTexture then return nil end
	local ok, mask = pcall(function()
		local m = owner:CreateMaskTexture()
		m:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		m:SetAllPoints(anchorTo or region)
		region:AddMaskTexture(m)
		return m
	end)
	return ok and mask or nil
end

W.AddMask = AddMask

-- ---------------------------------------------------------------------------
-- text
-- ---------------------------------------------------------------------------

--- `size` overrides the role's own point size without inventing a new role.
--  Media:Size exists for the same reason - a caller that needs to deviate
--  OFFSETS from a role rather than hard-coding a face, so the roles stay the
--  single source of truth for weight and family.
function W.Text(parent, style, justify, layer, size)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	Media:SetFont(fs, style, size)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetJustifyV("MIDDLE")
	-- A soft shadow is the only thing keeping light type legible against the
	-- Barrens at midday. The concepts lean on text-shadow for exactly this, and
	-- both skins draw light type, so this is a constant rather than a skin token.
	--
	-- ONE PHYSICAL PIXEL, not one frame unit. Everything here is drawn at
	-- profile.scale, so a flat -1 is 0.71 of a pixel at the default: the shadow
	-- lands between rows and the client resolves it by smearing the glyph's
	-- underside across two of them. On body text at nine pixels that reads as
	-- the type being badly rendered - or as an outline nobody asked for - rather
	-- than as a shadow.
	--
	-- A:PxIn converts a real screen pixel into the frame's own units, which is
	-- the same correction the tooltip badge needed for its rim.
	fs:SetShadowColor(0, 0, 0, 0.55)
	fs:SetShadowOffset(0, -(A.PxIn and A:PxIn(parent) or 1))
	local c = A.Palette.c.text
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	fs._aetherStyle = style
	return fs
end


-- Both of these are nil-tolerant on purpose. They are called from skin and
-- config passes that walk whole collections of widgets, and not every member of
-- a collection has every region - an adopted Blizzard button has none of ours at
-- all. A missing font string there is a fact about the widget, not a bug worth
-- taking the whole restyle down for.
-- An explicit size override (W.Pill's `size`) outlives a restyle. It was set
-- because the role's own number was wrong for where the string sits, and that is
-- still true after a skin change.
-- Naming a style RE-ROLES the string, rather than applying that font once. The
-- skin pass calls this with no style at all and means "the role you already
-- have"; a caller that names one is changing what the string IS - a nameplate's
-- name swaps between the capsule's role and the friendly one as the plate's form
-- changes. Left unrecorded, the next skin change quietly put the original role
-- back and the string shrank for no visible reason.
function W.Restyle(fs, style)
	if not fs then return end

	-- A client "label" is often a BUTTON with a string on it, not the string:
	-- the skill tree's collapse headers are buttons, and they answer SetText
	-- like a FontString while having no SetFont at all. Reach through to the
	-- string rather than handing a button to the font setter.
	if not fs.SetFont and fs.GetFontString then
		fs = fs:GetFontString() or fs
	end
	if not fs.SetFont then return end

	if style then fs._aetherStyle = style end
	Media:SetFont(fs, style or fs._aetherStyle, fs._aetherSize)
end

function W.Color(fs, c)
	if not fs or not c then return end
	-- Same reach-through as Restyle: a button carrying a label has no
	-- SetTextColor of its own.
	if not fs.SetTextColor and fs.GetFontString then
		fs = fs:GetFontString()
	end
	if not fs or not fs.SetTextColor then return end
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- ---------------------------------------------------------------------------
-- pills
-- ---------------------------------------------------------------------------

--- A tinted capsule carrying short text: a level chip, a count, a type tag.
--
--  Lives here rather than in the quest log because the tracker wears the same
--  chip, and a level chip that drifted between the two lists - a different
--  height, a different pad, a different set of band colours - would read as two
--  unrelated widgets sitting one above the other on the same screen.
--
--  opts: { height, padX, edge, size }. The edge is OFF by default: the concept's
--  level chip has none, and it is the type tag that is the exception. `size`
--  overrides the role's own point size, for a chip sitting beside body text that
--  is smaller than the text the role was drawn for - a label bigger than the
--  thing it labels is the one thing it must never be.
local PILL_H = 19

function W.Pill(parent, style, opts)
	opts = opts or {}
	-- `frameType` so a pill can be a Button. Everything else about a pill that
	-- happens to be clickable is identical, and the alternative is a second
	-- capsule that only looks like this one.
	local pill = A.Glass.CreatePill(parent, {
		fill = "glass", edge = "glassEdge", frameType = opts.frameType })
	pill:SetHeight(opts.height or PILL_H)
	if not opts.edge then pill:SetEdgeShown(false) end

	pill.text = W.Text(pill, style, "CENTER")
	if opts.size then
		Media:SetFont(pill.text, style, opts.size)
		-- Recorded, or the next W.Restyle quietly puts the role's own size back.
		pill.text._aetherSize = opts.size
	end
	pill.text:SetPoint("CENTER", pill, "CENTER", 0, 0)
	pill._padX = opts.padX or 10

	--- Pills size to their text unless the caller pinned a width (the level
	--  chip is a fixed width so a column of them lines up).
	function pill:SetLabel(text, fixedWidth)
		self.text:SetText(text or "")
		if fixedWidth then
			self:SetWidth(fixedWidth)
		else
			local w = math.ceil(self.text:GetStringWidth() or 0)
			self:SetWidth(w + self._padX * 2)
		end
	end

	--- The ink decides the shadow.
	--
	--  W.Text gives every string the soft black shadow that is the only thing
	--  keeping light type legible against the Barrens at midday. A chip inverts
	--  that: on Daylight the band colours are DARK ink on a near-opaque pale
	--  fill, and there the same shadow is not legibility, it is mud around every
	--  glyph. Chat's tab labels hit this first and turn it off by hand; this is
	--  the same rule, applied where the colour is actually known.
	function pill:SetColors(bg, fg)
		if bg then self:SetFillColor(bg) end
		if fg then
			W.Color(self.text, fg)
			if self.text.SetShadowColor then
				local lum = 0.299 * fg[1] + 0.587 * fg[2] + 0.114 * fg[3]
				self.text:SetShadowColor(0, 0, 0, lum < 0.5 and 0 or 0.55)
			end
		end
	end

	return pill
end

-- ---------------------------------------------------------------------------
-- bars
-- ---------------------------------------------------------------------------

local Bar = {}

--- colors: either {r,g,b} or a { {r,g,b}, {r,g,b} } gradient pair.
function Bar:SetColors(colors)
	if not colors then return end
	local tex = self:GetStatusBarTexture()
	if type(colors[1]) == "table" then
		SetGradient(tex, "HORIZONTAL", colors[1], colors[2] or colors[1])
	else
		tex:SetVertexColor(colors[1], colors[2], colors[3], colors[4] or 1)
	end
	self._colors = colors
end

function Bar:SetBackdropColor(c)
	if self.bg then self.bg:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
end

--- Smooth value changes so a health tick does not snap. Cheap lerp on the
--  shared ticker rather than a per-bar OnUpdate.
function Bar:SetSmoothValue(v)
	self._target = v
	if not self._smooth then
		self:SetValue(v)
		return
	end
	if not self._animating then
		self._animating = true
		A:RegisterTicker(self, Bar._Step)
	end
end

function Bar:_Step(dt)
	local cur = self:GetValue() or 0
	local target = self._target or cur
	local diff = target - cur
	local _, max = self:GetMinMaxValues()
	local epsilon = math.max((max or 1) * 0.002, 0.0001)
	if math.abs(diff) <= epsilon then
		self:SetValue(target)
		self._animating = false
		A:UnregisterTicker(self)
		return
	end
	self:SetValue(cur + diff * math.min(1, dt * 9))
end

--- opts: { height, rounded = true, smooth = true, bgAlpha = 0.14 }
function W.CreateBar(parent, opts)
	opts = opts or {}
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(Media.texture.bar)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	if opts.height then bar:SetHeight(opts.height) end

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(Media.texture.flat)
	bg:SetAllPoints(bar)
	bg:SetVertexColor(1, 1, 1, opts.bgAlpha or 0.14)
	bar.bg = bg

	for k, v in pairs(Bar) do bar[k] = v end
	bar._smooth = opts.smooth ~= false

	if opts.rounded ~= false then
		-- One mask anchored to the bar's full extent, shared by fill and
		-- background. The fill keeps a square leading edge as it depletes, which
		-- is what you want: a rounded head would read as "nearly empty".
		local m = AddMask(bar:GetStatusBarTexture(), bar, Media.texture.barMask, bar)
		if m and bg.AddMaskTexture then
			pcall(bg.AddMaskTexture, bg, m)
			bar._mask = m
		end
	end

	return bar
end

-- ---------------------------------------------------------------------------
-- orb (portrait / level badge)
-- ---------------------------------------------------------------------------

-- Where the level orb's rim band begins, as a fraction of the orb's width.
--
-- Orb-Face.tga draws it from r 21.4 of 23, so 1.6px of a 46px orb - and this is
-- a hair under that, so the face reaches the rim without covering it. The face
-- sits above the disc, so overlapping would hide the very thing it is meeting.
local ORB_RIM_FRAC = 0.038

local Orb = {}

--- Give the level disc independent face, rim, and ink colours. The face has a
--  restrained vertical lift while the source art contributes only a raised rim.
function Orb:SetColors(face, rim, ink, faceHi, rimHi)
	if face then W.SetGradient(self.face, "VERTICAL", faceHi or face, face) end
	if rim then self.disc:SetVertexColor(rim[1], rim[2], rim[3], rim[4] or 1) end
	if rimHi then self.ring:SetVertexColor(rimHi[1], rimHi[2], rimHi[3], rimHi[4] or 1) end
	if ink then W.Color(self.label, ink) end
end

function Orb:SetRingColor(c)
	self.ring:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

function Orb:SetLabel(text)
	self.label:SetText(text or "")
end

--- Resize the disc and refit the label with it. The level number is ~26% of the
--  orb in the concept; hard-coding a point size means it stops fitting the
--  moment orbSize is changed.
function Orb:Resize(size)
	self:SetSize(size, size)
	Media:SetFont(self.label, "level", math.max(9, math.floor(size * 0.26 + 0.5)))
	-- The face runs UP TO the rim.
	--
	-- At 0.085 it stopped about two pixels short, and the disc's own face showed
	-- through the gap in the rim's colour - a ring between the middle and the
	-- edge, which is the seam that got reported. ORB_RIM_FRAC is where the
	-- texture's rim band starts, so insetting by less than that leaves nothing
	-- of the disc visible between them.
	local inset = math.max(A.PxIn and A:PxIn(self) or 1, size * ORB_RIM_FRAC)
	self.face:ClearAllPoints()
	self.face:SetPoint("TOPLEFT", self, "TOPLEFT", inset, -inset)
	self.face:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -inset, inset)

	-- Flush, not proud. Lapping it outward added its whole width to the rim the
	-- texture already draws, so the two together read as one thick ring.
	self.ring:ClearAllPoints()
	self.ring:SetAllPoints(self)
	if self.glow then self.glow:SetSize(size * 2, size * 2) end
end

function Orb:SetGlow(shown, c)
	if not self.glow then
		if not shown then return end
		local g = self:CreateTexture(nil, "BACKGROUND", nil, -1)
		g:SetTexture(Media.texture.ringGlow)
		g:SetBlendMode("ADD")
		g:SetPoint("CENTER")
		self.glow = g
	end
	if shown then
		local s = self:GetWidth() * 2
		self.glow:SetSize(s, s)
		c = c or A.Palette.c.accent
		self.glow:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		self.glow:Show()
	else
		self.glow:Hide()
	end
end

--- opts: { size = 46, portrait = false }
function W.CreateOrb(parent, opts)
	opts = opts or {}
	local size = opts.size or 46
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)

	-- The source's outer anti-aliasing and fine reflection make a clean raised
	-- rim. Its centre is deliberately covered by `face` below, so it no longer
	-- decides the colour, contrast, and finish of the whole level disc at once.
	local disc = f:CreateTexture(nil, "ARTWORK")
	disc:SetTexture(Media.texture.orbFace)
	disc:SetAllPoints(f)
	f.disc = disc

	-- A white source plus a round mask gives us a face whose two gradient stops
	-- can be tinted independently from the rim. The mask follows THIS inset
	-- texture, not the parent, otherwise a square centre would peek through.
	local face = f:CreateTexture(nil, "ARTWORK", nil, 1)
	face:SetTexture(Media.texture.flat)
	W.AddMask(face, f, Media.texture.circleMask, face)
	f.face = face

	if opts.portrait then
		local p = f:CreateTexture(nil, "ARTWORK", nil, 1)
		p:SetAllPoints(f)
		AddMask(p, f, Media.texture.circleMask, f)
		f.portrait = p
	end

	-- The fine top ring catches the light above the broader coloured rim. It is
	-- always on: a target's relationship is already encoded in the face colour,
	-- so this completes the physical disc instead of competing with it.
	local ring = f:CreateTexture(nil, "OVERLAY")
	-- Orb-Ring, not Ring: the latter is authored at 256 for the minimap and
	-- the portrait, and at 46px its anti-aliasing compresses to half a pixel
	-- and the edge goes jagged. See orb_ring() in the generator.
	ring:SetTexture(Media.texture.orbRing)
	f.ring = ring

	local label = W.Text(f, "level", "CENTER")
	label:SetPoint("CENTER", f, "CENTER", 0, 0)
	-- The face is intentionally dark enough for white type on every class, but
	-- the one physical-pixel shadow keeps it intact over the top highlight too.
	-- This reads as depth, not the heavy outline that a multi-pixel stroke would.
	label:SetShadowColor(2 / 255, 2 / 255, 8 / 255, 0.92)
	label:SetShadowOffset(0, -(A.PxIn and A:PxIn(f) or 1))
	f.label = label

	for k, v in pairs(Orb) do f[k] = v end
	f:Resize(size)
	return f
end

-- ---------------------------------------------------------------------------
-- badge (a small circular chip carrying a number)
-- ---------------------------------------------------------------------------

local Badge = {}

function Badge:SetLabel(text)
	self.label:SetText(text or "")
end

--- fill, edge and ink, in that order. All three, because at this size the three
--  have to be chosen together - a rim at 40% of a colour the disc is also 15% of
--  is a different thing from a rim at 40% over nothing.
function Badge:SetColors(fill, edge, ink)
	if fill then self.disc:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1) end
	if edge then self.ring:SetVertexColor(edge[1], edge[2], edge[3], edge[4] or 1) end
	if ink then W.Color(self.label, ink) end
end

function Badge:Resize(size)
	-- Snapped in the BADGE's own units, not UIParent's. A tooltip runs at 0.71,
	-- so a 26-unit disc is 18.46 physical pixels: its rim lands across a pixel
	-- boundary all the way round and the client resolves that as a ring of half
	-- -lit greys. That is the whole of what "janky" looked like on screen.
	local snapped = A:SnapIn(self, size)
	self:SetSize(snapped, snapped)

	-- And the rim laps OVER the disc rather than sitting flush inside it.
	--
	-- This is the lesson minimap_border() in Tools/generate_textures.py already
	-- records: an edge the client anti-aliases is an edge that stair-steps, so
	-- the border has to overlap it rather than stop short and leave the fringe
	-- showing. Flush, the disc's own outer texel row peeked out from under a rim
	-- too thin to cover it, which read as a second, rougher circle.
	local proud = A:PxIn(self)
	self.ring:ClearAllPoints()
	self.ring:SetPoint("TOPLEFT", self, "TOPLEFT", -proud, proud)
	self.ring:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", proud, -proud)
end

--- A small circular chip: a tinted disc, a rim, and a number.
--
--  Deliberately NOT W.CreateOrb at a smaller size, and not a pill either.
--
--  CreateOrb cuts its disc out with a MaskTexture, which is right at 46px with a
--  portrait in it and wrong at 26: a mask edge is the client's to anti-alias and
--  it does that poorly, so at this size the mask's stair-stepping is a visible
--  part of the shape. Here the disc is drawn from Circle-Mask as ordinary
--  ARTWORK instead - it is a 256px anti-aliased filled circle, and drawing it
--  rather than masking with it puts the anti-aliasing back in our hands.
--
--  A pill at width == height would also be a circle, and would bring the pixel
--  snapping for free, but its two cap slices would meet in the middle with a
--  zero-width centre between them - the seam case Core\Glass.lua's header warns
--  about, and the one place it cannot be avoided by snapping.
--
--  opts: { size = 26, style = "ttBadge" }
function W.CreateBadge(parent, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", nil, parent)

	-- Chip-Disc and Chip-Rim, not Circle-Mask and Ring. Those are 256 because
	-- the minimap MAGNIFIES them; a badge is 26-32 across, so drawing them here
	-- minifies eight times and the client does not mipmap UI textures - the
	-- anti-aliasing ramp compresses under a texel and the edge comes back
	-- crunchy. Same shapes at 64, for the opposite job.
	local disc = f:CreateTexture(nil, "ARTWORK")
	disc:SetTexture(Media.texture.chipDisc)
	disc:SetAllPoints(f)
	f.disc = disc

	local ring = f:CreateTexture(nil, "OVERLAY")
	ring:SetTexture(Media.texture.chipRim)
	f.ring = ring

	local label = W.Text(f, opts.style or "ttBadge", "CENTER")
	label:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.label = label

	for k, v in pairs(Badge) do f[k] = v end
	f:Resize(opts.size or 26)
	return f
end

-- ---------------------------------------------------------------------------
-- the button
--
-- ONE of them, for every button this interface puts its hands on.
--
-- There were three before this: a pill behind a client button, a pill behind a
-- client tab, and a pill built as a button in the quest log. All three drew a
-- CAPSULE - ends rounded to half the height - because CreatePill was the
-- nearest thing to hand. That is the wrong shape and it was wrong in three
-- places at once: a capsule reads as a chip or a token, and every surface in
-- this interface that is meant to be pressed - the tooltip's card, the
-- toolbox's tiles, the nameplate's chips - is a rounded RECTANGLE at the
-- deck's own radius.
--
-- So the shape lives here now, once, and the selected state with it. Getting
-- the curve right is then a one-line change rather than a hunt.
-- ---------------------------------------------------------------------------

-- The deck's button radius. Smaller than a panel's twelve, because a button is
-- a small object and a corner that reads as generous at 300px reads as a
-- lozenge at 80.
local BUTTON_CORNER = 8

--- What a button looks like when it is the one you are on.
--
--  Taken from the chat tab, which had the only correct version of this: a
--  FILLED surface with dark type on it, exactly inverted from everything else
--  in the interface. That inversion is the whole signal, and doing it any other
--  way - a brighter rim, a lighter fill - reads as "hovered" rather than "here".
--
--  No rim when filled. A filled shape already has an edge, its own boundary,
--  and drawing a second one in the same colour on top doubles the value there
--  and comes back as a bright outline rather than a solid.
function W.SetButtonState(btn, selected, hovered)
	local skin = btn and btn.__aetherSkin
	if not skin then return end

	local c = A.Palette.c
	skin:SetEdgeShown(not selected)

	if selected then
		skin:SetFillColor(c.accent)
		skin:SetAlpha(1)
	elseif hovered then
		skin:SetFillColor(c.glassSoft)
		skin:SetAlpha(1)
	elseif btn.__aetherQuiet then
		-- NOTHING AT ALL when it is not the one you are on. The chat tabs are
		-- built this way on purpose: they sit over the world rather than in a
		-- window, and a row of glass chips along the top of the log is four
		-- objects competing with the thing you are reading. The selected fill
		-- is the only mark that row needs.
		skin:SetAlpha(0)
	else
		skin:SetFillColor(c.glass)
		skin:SetAlpha(1)
	end

	local label = btn.__aetherLabel
		or (btn.GetFontString and btn:GetFontString())
	if not label or not label.SetTextColor then return end

	if selected then
		-- At FULL alpha. `glass` is the panel fill and carries alpha .55;
		-- passing it straight through draws the label at 55% over the accent
		-- while its shadow stays opaque, so the smudge is darker than the
		-- letters casting it.
		W.Color(label, { c.glass[1], c.glass[2], c.glass[3], 1 })
		if label.SetShadowColor then label:SetShadowColor(0, 0, 0, 0) end
	else
		W.Color(label, hovered and c.text or c.textDim)
		if label.SetShadowColor then label:SetShadowColor(0, 0, 0, 0.6) end
	end
end

--- One of OURS, built as a button rather than put behind one.
--
--  The other half of the same shape. The quest log and the bags each built
--  their buttons out of CreatePill, which is a horizontal capsule: its two caps
--  come out of a 256-texel texture, so at a 22px button they are minified more
--  than ten times and the client does not mipmap. That is the same crunch the
--  tooltip badge and the check box both had, and the same fix - art drawn at
--  the size it is used, which for a rounded rectangle is the panel's corner.
function W.CreateButton(parent, opts)
	opts = opts or {}
	local b = A.Glass.CreatePanel(parent, {
		frameType = "Button",
		template  = opts.template,
		corner    = opts.corner or BUTTON_CORNER,
		fill      = opts.fill or "glass",
		edge      = opts.edge or "glassEdgeHi",
		shadow    = opts.shadow,
	})
	b.__aetherSkin = b            -- it IS its own surface, so state works on it
	return b
end

--- Put our surface behind a button, whoever made the button.
--
--  The button itself is untouched beyond this: not resized, not reparented, not
--  rescripted. What it does when pressed stays entirely its own business, which
--  is what lets this be used on the client's buttons as well as ours.
function W.SkinButton(btn, opts)
	if not btn then return nil end
	if btn.__aetherSkin then return btn.__aetherSkin end
	opts = opts or {}

	local skin = A.Glass.CreatePanel(btn, {
		corner = opts.corner or BUTTON_CORNER,
		fill   = opts.fill or "glass",
		edge   = opts.edge or "glassEdgeHi",
	})
	-- Filling the button is the usual case and not the only one: a chat tab's
	-- surface is measured from its LABEL rather than from the tab, because the
	-- client rewrites that tab's width twice per click and a surface measured
	-- from it drifts away from the word it is wrapping. `anchor = false` hands
	-- the caller that job and keeps everything else shared.
	if opts.anchor ~= false then skin:SetAllPoints(btn) end
	skin:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
	if skin.EnableMouse then skin:EnableMouse(false) end
	btn.__aetherSkin = skin
	btn.__aetherLabel = opts.label
	btn.__aetherQuiet = opts.quiet

	-- Hover, where the button will tell us. A client button that takes no mouse
	-- scripts simply never lights up, which is correct rather than broken.
	if btn.HookScript and not opts.static then
		btn:HookScript("OnEnter", function(self)
			W.SetButtonState(self, self.__aetherSelected, true)
		end)
		btn:HookScript("OnLeave", function(self)
			W.SetButtonState(self, self.__aetherSelected, false)
		end)
	end

	W.SetButtonState(btn, false, false)
	return skin
end

-- ---------------------------------------------------------------------------
-- icon slot (aura icons now, action buttons later)
-- ---------------------------------------------------------------------------

local Slot = {}

function Slot:SetIcon(texture)
	self.icon:SetTexture(texture)
end

function Slot:SetActive(shown, c)
	if shown then
		c = c or A.Palette.c.cast[1]
		self.glow:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		self.glow:Show()
	else
		self.glow:Hide()
	end
end

function Slot:SetEdgeColor(c)
	self.edge:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

--- Attach the slot layer stack to an existing frame.
--
--  Split out from CreateSlot because an action button has to *be* a secure
--  CheckButton created from a template - we cannot wrap one in a plain frame and
--  keep the click behaviour. So the chrome is applied to whatever frame the
--  caller already has.
--
--  Layer stack, bottom to top, mirroring the concept's CSS order:
--    icon           masked to a rounded square
--    inner shadow   inset 0 0 14px rgba(0,0,10,.45)
--    top gloss      linear-gradient(180deg, rgba(255,255,255,.16), transparent 45%)
--    1px rim        border: 1px solid ...
--    glow           active state, drawn at 2x and centred
function W.DecorateSlot(f, size, opts)
	opts = opts or {}

	-- When the caller hands us the client's own icon we dress that one. Making
	-- a second would leave Blizzard's underneath ours, still drawing.
	local icon = opts.icon
	if not icon then
		icon = f:CreateTexture(nil, "ARTWORK")
	end
	icon:SetAllPoints(f)
	-- Trim the 1px transparent gutter Blizzard bakes into every icon file.
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	AddMask(icon, f, Media.texture.slotMask, f)
	f.icon = icon

	local shade = f:CreateTexture(nil, "ARTWORK", nil, 1)
	shade:SetTexture(Media.texture.slotShade)
	shade:SetAllPoints(f)
	f.shade = shade

	local gloss = f:CreateTexture(nil, "ARTWORK", nil, 2)
	gloss:SetTexture(Media.texture.slotGloss)
	gloss:SetAllPoints(f)
	gloss:SetBlendMode("ADD")
	f.gloss = gloss

	local edge = f:CreateTexture(nil, "OVERLAY")
	edge:SetTexture(Media.texture.slotEdge)
	edge:SetAllPoints(f)
	local e = A.Palette.c.glassEdge
	edge:SetVertexColor(e[1], e[2], e[3], e[4] or 1)
	f.edge = edge

	local glow = f:CreateTexture(nil, "OVERLAY", nil, 1)
	glow:SetTexture(Media.texture.slotGlow)
	glow:SetBlendMode("ADD")
	glow:SetPoint("CENTER")
	glow:SetSize(size * 2, size * 2)
	glow:Hide()
	f.glow = glow

	-- A client button already has a count of its own, kept and re-roled by the
	-- caller. Ours would sit on top of it, both showing the same number.
	if opts.count ~= false then
		local count = W.Text(f, "stack", "RIGHT")
		count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
		f.count = count
	end

	for k, v in pairs(Slot) do f[k] = v end
	return f
end

function W.CreateSlot(parent, opts)
	opts = opts or {}
	local size = opts.size or 30
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	return W.DecorateSlot(f, size, opts)
end

-- ---------------------------------------------------------------------------
-- scrolling lists
-- ---------------------------------------------------------------------------

--- A scroll frame with no visible bar, because the concept has none. The wheel
--  is the only way to move it, which is what the design implies. `step` is how
--  far one wheel click moves it.
function W.Scroller(parent, step)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	scroll.child = child

	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, (self.child:GetHeight() or 0) - (self:GetHeight() or 0))
		local v = (self:GetVerticalScroll() or 0) - delta * step
		if v < 0 then v = 0 elseif v > max then v = max end
		self:SetVerticalScroll(v)
	end)

	--- Re-clamp after a rebuild, or a shorter list leaves the view scrolled past
	--  its own end and the pane reads as empty.
	function scroll:Clamp()
		local max = math.max(0, (self.child:GetHeight() or 0) - (self:GetHeight() or 0))
		if (self:GetVerticalScroll() or 0) > max then self:SetVerticalScroll(max) end
	end

	return scroll
end

-- ---------------------------------------------------------------------------
-- frame pools
--
-- WoW never frees a frame or a texture, so the key decides whether a list is
-- cheap or leaks by the hundred. Anything that changes under the caller's feet
-- retires a built frame and constructs another on every refresh -- a quest row
-- is three frames and thirty-three regions, and a zone heading comes and goes
-- with every keystroke in the search box. So the key is whatever is actually
-- stable: display position with one pool per row kind, or an identity like
-- (bag, slot), which additionally means no frame can ever point at the wrong
-- thing.
-- ---------------------------------------------------------------------------

local Pool = {}

--- The frame for `key`, built the first time it is asked for. A two-deep pool
--  takes both parts of the key and nests: pool[a][b].
function Pool:Get(...)
	local meta = getmetatable(self)
	local store, key = self, ...
	if meta.depth == 2 then
		store = rawget(self, key)
		if not store then store = {} rawset(self, key, store) end
		key = select(2, ...)
	end

	local f = rawget(store, key)
	if not f then
		f = meta.build(...)
		store[key] = f
	end
	return f
end

--- Hide everything from `n` on, for the pools keyed by position.
function Pool:HideFrom(n)
	for i = n, #self do self[i]:Hide() end
end

--- A pool of frames built on demand by `build(key...)`, `depth` key parts deep.
--
--  The pool IS its store -- pool[key] is the frame -- so `#pool` and `pairs`
--  read as they did when these were bare tables. Its own state lives on the
--  metatable for that reason: a builder sat in the table would turn up in
--  pairs() as a frame.
function W.Pool(build, depth)
	return setmetatable({}, { __index = Pool, build = build, depth = depth or 1 })
end

-- ---------------------------------------------------------------------------
-- misc
-- ---------------------------------------------------------------------------

--- Faint hairline used between stacked rows.
function W.Divider(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetTexture(Media.texture.divider)
	t:SetHeight(A:Px(1))
	local c = A.Palette.c.textFaint
	t:SetVertexColor(c[1], c[2], c[3], 0.25)
	return t
end

--- Short numbers, Classic style: 12.4k rather than 12400.
function W.Short(n)
	if not n then return "" end
	if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
	if n >= 10000 then return string.format("%.0fk", n / 1000) end
	if n >= 1000 then return string.format("%.1fk", n / 1000) end
	return tostring(math.floor(n + 0.5))
end

--- Aura clocks read differently from cooldowns: the concept shows "6m" and
--  "4s", i.e. a unit is always present and precision drops as the number grows.
--  Returns "" for a permanent aura so the pill just omits the field.
function W.AuraTime(expiration, duration)
	if not expiration or expiration == 0 or not duration or duration == 0 then return "" end
	local remain = expiration - GetTime()
	if remain <= 0 then return "" end
	if remain >= 3600 then return string.format("%dh", math.floor(remain / 3600 + 0.5)) end
	if remain >= 60 then return string.format("%dm", math.floor(remain / 60 + 0.5)) end
	if remain >= 1 then return string.format("%ds", math.floor(remain)) end
	return string.format("%.1fs", remain)
end

function W.Duration(sec)
	if not sec or sec <= 0 then return "" end
	if sec >= 3600 then return string.format("%dh", math.floor(sec / 3600 + 0.5)) end
	if sec >= 60 then return string.format("%dm", math.floor(sec / 60 + 0.5)) end
	if sec >= 10 then return string.format("%d", math.floor(sec)) end
	return string.format("%.1f", sec)
end
