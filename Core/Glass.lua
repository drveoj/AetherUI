--[[--------------------------------------------------------------------------
	AetherUI :: Glass

	The frosted-glass surface, which is the whole visual identity of the concept
	deck, rebuilt with the tools Classic Era actually gives us.

	What we cannot do
	-----------------
	The concepts use CSS `backdrop-filter: blur()`. There is no runtime blur in
	the WoW UI at all: no shader hooks, no render-to-texture for arbitrary frames.
	Nothing will ever sample and blur the world behind a frame.

	What sells it instead
	---------------------
	Frosted glass reads from four cues, and blur is only one of them:
	  1. translucency          -> a tinted, partly transparent fill
	  2. a bright catching rim -> a separate edge texture, tinted apart
	  3. a top-light falloff   -> baked into the fill's alpha ramp
	  4. fine surface grain    -> baked into the fill's ALPHA channel
	Three of those four survive intact. In motion the missing blur is genuinely
	hard to notice; what people actually recognise is the rim and the falloff.

	The grain is baked into the fill textures rather than layered at runtime, and
	it lives in alpha rather than RGB. Both of those are the result of getting it
	wrong first: a separate noise texture can only be anchored to the centre
	slice, which left a visibly brighter rectangle between the rounded caps with
	hard seams at both ends; and RGB variation is multiplied away to nothing once
	a white texture is tinted with a dark colour, so only alpha variation - more
	or less of the world showing through per texel - actually reads as frost.

	Geometry
	--------
	Panels are 9-slice, pills are 3-slice, both driven from a single texture with
	SetTexCoord. Slice fractions come from Core\Media.lua and are guaranteed by
	Tools/generate_textures.py:
	  * Glass-Panel  128x128, corner 32  -> 0.25
	  * Glass-Pill   256x128, cap    64  -> 0.25
	  * Glass-Shadow 128x128, corner 48  -> 0.375   (wider: blur spill must fit)

	A pill's caps must stay circular, so their width is always half the pill's
	height and is recomputed on resize.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Glass = {}
A.Glass = Glass

local Media = A.Media

local TL, T, TR, L, C, R, BL, B, BR = 1, 2, 3, 4, 5, 6, 7, 8, 9

--- Pixel snapping is left ON, and that is deliberate. Do not turn it off here.
--
--  It was turned off once, on the reasoning that nine pieces each rounding their
--  own edges to the grid must be what seams a nine-slice. That reasoning has it
--  exactly backwards, and the result was worse rather than better.
--
--  These slices *abut*: the centre's left edge is the left cap's right edge.
--  Snapped, both land on the same integer pixel and the shape tiles seamlessly.
--  Unsnapped, they land on the same *fractional* pixel - so the boundary pixel
--  is partially covered by both quads, and the rim there gets alpha-blended
--  twice. Two 50% fragments compose to 75%, not 50%, which is a bright dot in
--  the rim wherever a seam crosses it.
--
--  A 3-slice pill's seam runs vertically at x = cap, which is precisely where
--  the cap's arc becomes the straight top and bottom edge. Four seam crossings,
--  four bright dots, one at each corner. Snapping is what prevents that, and it
--  is the whole reason the feature exists.
--
--  If a seam ever does show, the fix is in the *texture* - a rim wide enough and
--  soft enough to survive a pixel of misalignment - not in the snapping.

-- ---------------------------------------------------------------------------
-- low level: build and lay out a nine-piece texture set
-- ---------------------------------------------------------------------------

local function Build9(frame, texPath, layer, sub)
	local t = {}
	for i = 1, 9 do
		local tex = frame:CreateTexture(nil, layer, nil, sub)
		tex:SetTexture(texPath)
		t[i] = tex
	end
	return t
end

--- `size` is {width, height} of the source texture. Internal slice boundaries
--  are pulled in by half a texel so no slice can sample its neighbour; the outer
--  edges are left alone, since clamping already handles those.
local function ApplyTexCoords(t, q, size)
	local a, b = q, 1 - q
	local hx = size and (0.5 / size[1]) or 0
	local hy = size and (0.5 / size[2]) or 0

	local aL, aR = a - hx, a + hx      -- left/right side of the vertical seam at a
	local bL, bR = b - hx, b + hx
	local aT, aB = a - hy, a + hy      -- top/bottom side of the horizontal seam
	local bT, bB = b - hy, b + hy

	t[TL]:SetTexCoord(0,  aL, 0,  aT)
	t[T ]:SetTexCoord(aR, bL, 0,  aT)
	t[TR]:SetTexCoord(bR, 1,  0,  aT)
	t[L ]:SetTexCoord(0,  aL, aB, bT)
	t[C ]:SetTexCoord(aR, bL, aB, bT)
	t[R ]:SetTexCoord(bR, 1,  aB, bT)
	t[BL]:SetTexCoord(0,  aL, bB, 1)
	t[B ]:SetTexCoord(aR, bL, bB, 1)
	t[BR]:SetTexCoord(bR, 1,  bB, 1)
end

--- Anchor the nine pieces around `anchorTo`, expanded outward by `pad`.
local function Layout9(t, anchorTo, corner, pad)
	pad = pad or 0

	t[TL]:ClearAllPoints()
	t[TL]:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", -pad, pad)
	t[TL]:SetSize(corner, corner)

	t[TR]:ClearAllPoints()
	t[TR]:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", pad, pad)
	t[TR]:SetSize(corner, corner)

	t[BL]:ClearAllPoints()
	t[BL]:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMLEFT", -pad, -pad)
	t[BL]:SetSize(corner, corner)

	t[BR]:ClearAllPoints()
	t[BR]:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", pad, -pad)
	t[BR]:SetSize(corner, corner)

	t[T]:ClearAllPoints()
	t[T]:SetPoint("TOPLEFT", t[TL], "TOPRIGHT")
	t[T]:SetPoint("BOTTOMRIGHT", t[TR], "BOTTOMLEFT")

	t[B]:ClearAllPoints()
	t[B]:SetPoint("TOPLEFT", t[BL], "TOPRIGHT")
	t[B]:SetPoint("BOTTOMRIGHT", t[BR], "BOTTOMLEFT")

	t[L]:ClearAllPoints()
	t[L]:SetPoint("TOPLEFT", t[TL], "BOTTOMLEFT")
	t[L]:SetPoint("BOTTOMRIGHT", t[BL], "TOPRIGHT")

	t[R]:ClearAllPoints()
	t[R]:SetPoint("TOPLEFT", t[TR], "BOTTOMLEFT")
	t[R]:SetPoint("BOTTOMRIGHT", t[BR], "TOPRIGHT")

	t[C]:ClearAllPoints()
	t[C]:SetPoint("TOPLEFT", t[TL], "BOTTOMRIGHT")
	t[C]:SetPoint("BOTTOMRIGHT", t[BR], "TOPLEFT")
end

local function Tint(t, c)
	local r, g, b, a = c[1], c[2], c[3], c[4] or 1
	for i = 1, #t do t[i]:SetVertexColor(r, g, b, a) end
end

local function ShowAll(t, show)
	for i = 1, #t do
		if show then t[i]:Show() else t[i]:Hide() end
	end
end

-- ---------------------------------------------------------------------------
-- three-piece (pill) variant
-- ---------------------------------------------------------------------------

--- Round a length in a *frame's* own units onto the physical pixel grid.
--
--  A.pixel is in UIParent units; a frame at profile scale is not, so the step
--  has to be converted across. Without this a pill's two cap quads round to
--  different widths - the frame's left edge and its right edge sit at different
--  sub-pixel phases, so `left + cap` and `right - cap` round in opposite
--  directions and one cap comes out a pixel wider than the other. That is the
--  "right border is wider than the left", and it also drags the join between
--  the arc and the straight edge a pixel out of true on one side.
local function SnapIn(frame, v)
	local us = UIParent:GetEffectiveScale() or 1
	local fs = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or us
	local step = (A.pixel or 1) * us / (fs > 0 and fs or 1)
	if not step or step <= 0 or step ~= step then return v end
	return math.floor(v / step + 0.5) * step
end

local PL, PC, PR = 1, 2, 3

local function Build3(frame, texPath, layer, sub, frac, size)
	local t = {}
	for i = 1, 3 do
		local tex = frame:CreateTexture(nil, layer, nil, sub)
		tex:SetTexture(texPath)
		t[i] = tex
	end
	local q = frac or 0.25
	local hx = size and (0.5 / size[1]) or 0   -- see ApplyTexCoords
	t[PL]:SetTexCoord(0, q - hx, 0, 1)
	t[PC]:SetTexCoord(q + hx, 1 - q - hx, 0, 1)
	t[PR]:SetTexCoord(1 - q + hx, 1, 0, 1)
	return t
end

local function Layout3(t, anchorTo, cap, pad)
	pad = pad or 0

	t[PL]:ClearAllPoints()
	t[PL]:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", -pad, pad)
	t[PL]:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMLEFT", -pad, -pad)
	t[PL]:SetWidth(cap)

	t[PR]:ClearAllPoints()
	t[PR]:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", pad, pad)
	t[PR]:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", pad, -pad)
	t[PR]:SetWidth(cap)

	t[PC]:ClearAllPoints()
	t[PC]:SetPoint("TOPLEFT", t[PL], "TOPRIGHT")
	t[PC]:SetPoint("BOTTOMRIGHT", t[PR], "BOTTOMLEFT")
end

-- ---------------------------------------------------------------------------
-- surface object
-- ---------------------------------------------------------------------------

local Surface = {}

-- What the fill ART can carry on its own. Glass-Panel's alpha holds the
-- top-light falloff as well as the shape, so it is this in the middle and less
-- at the foot - and a vertex tint MULTIPLIES that, so no colour however solid
-- can push the surface past it. "Reading panel opacity 100%" landed here.
local ART_ALPHA = 227 / 255

--- A flat plate of the same shape, behind the fill, for a surface asked to be
--  more opaque than its own art can be.
--
--  BUILT ON DEMAND. Almost nothing asks - the HUD's surfaces are meant to be
--  seen through - so nine textures per panel for a case that does not arise
--  would be nine textures per panel wasted.
local function EnsureBacking(self)
	if self._backing or self._kind ~= "panel" then return self._backing end

	self._backing = Build9(self, Media.texture.panelSolid, "BACKGROUND", -1)
	ApplyTexCoords(self._backing, Media.slice.panel, Media.textureSize.panel)
	if self._Relayout then self:_Relayout() end
	return self._backing
end

function Surface:SetFillColor(c)
	self._fillColor = c
	Tint(self._fill, c)

	-- HOW MUCH IS MISSING, and put a plate behind for exactly that. Composited,
	-- plate + art gives back what was asked for; at a request of 1 the plate is
	-- opaque on its own and the answer is exact.
	local want = c[4] or 1
	if want > ART_ALPHA + 0.001 then
		local have = ART_ALPHA * want
		local need = (want - have) / (1 - have)
		local b = EnsureBacking(self)
		if b then
			Tint(b, { c[1], c[2], c[3], math.min(1, math.max(0, need)) })
			ShowAll(b, true)
		end
	elseif self._backing then
		ShowAll(self._backing, false)
	end
end

function Surface:SetEdgeColor(c)
	self._edgeColor = c
	Tint(self._edge, c)
end

function Surface:SetEdgeShown(show)
	ShowAll(self._edge, show)
end

--- Ambient drop shadow. `opacity` is 0..1; 0 turns it off.
--
--  Note that the *geometry* is not configurable, and that is deliberate. Both
--  shadow textures are authored for one fixed relationship to the shape they sit
--  under, because that is the only way the hole in the shadow can line up with
--  the shape's own curve:
--
--    panels  drawn with a corner piece of 2*corner, offset corner/2 outward.
--            At that ratio the hole renders at exactly the panel's corner radius.
--    pills   drawn at spread = height/4, which puts the body edge on texel 21
--            and the cap on texel 64 regardless of the pill's size.
--
--  Letting the caller pick a free spread distance is what produced the original
--  bug: the hole ended up near-square under a 14px rounded corner, leaving a
--  transparent notch at each corner with no panel and no shadow in it.
function Surface:SetShadow(opacity)
	opacity = opacity and math.min(1, opacity) or 0
	if opacity <= 0 then
		if self._shadow then ShowAll(self._shadow, false) end
		self._shadowOpacity = nil
		return
	end

	self._shadowOpacity = opacity

	if self._kind == "pill" then
		if not self._shadow then
			self._shadow = Build3(self, Media.texture.pillShadow, "BACKGROUND", -8, Media.slice.pillShadow, Media.textureSize.pillShadow)
		end
		self:_LayoutPillShadow()
	else
		if not self._shadow then
			self._shadow = Build9(self, Media.texture.shadow, "BACKGROUND", -8)
			ApplyTexCoords(self._shadow, Media.slice.shadow, Media.textureSize.shadow)
		end
		self:_LayoutPanelShadow()
	end

	local c = A.Palette.c.shadow
	Tint(self._shadow, { c[1], c[2], c[3], (c[4] or 1) * opacity })
	ShowAll(self._shadow, true)
end

function Surface:_LayoutPanelShadow()
	if not self._shadow then return end
	local c = SnapIn(self, self._corner or 12)
	Layout9(self._shadow, self, c * 2, c / 2)
end

function Surface:_LayoutPillShadow()
	if not self._shadow then return end
	local h = self:GetHeight() or 0
	if h <= 0 then return end
	local s = SnapIn(self, h / 4)
	Layout3(self._shadow, self, SnapIn(self, (h + 2 * s) / 2), s)
end

--- An outer bloom in an arbitrary colour: the deck's `box-shadow: 0 0 24px <c>`.
--
--  Distinct from SetShadow, which is the ambient drop shadow every surface wears
--  and is always the skin's near-black. This one is a *signal* - an elite mob, an
--  epic item - so the caller picks the colour, and it draws additively so it
--  brightens what is behind it rather than tinting it.
--
--  It reuses the shadow texture rather than Glow-Soft deliberately. Glow-Soft is
--  a radial blob, which stretched across a 300x120 tooltip card reads as an oval
--  hovering behind a rectangle. The shadow art is the panel's own silhouette,
--  blurred, so its bloom follows the corner radius the way a real one would.
--
--  Sub-layer -7: above the drop shadow at -8, below the fill at 0.
function Surface:SetRimGlow(color)
	if not color then
		if self._rim then ShowAll(self._rim, false) end
		self._rimColor = nil
		return
	end

	if not self._rim then
		self._rim = Build9(self, Media.texture.shadow, "BACKGROUND", -7)
		ApplyTexCoords(self._rim, Media.slice.shadow, Media.textureSize.shadow)
		for i = 1, 9 do self._rim[i]:SetBlendMode("ADD") end
	end

	self._rimColor = color
	self:_LayoutRimGlow()
	Tint(self._rim, color)
	ShowAll(self._rim, true)
end

function Surface:_LayoutRimGlow()
	if not self._rim then return end
	local c = SnapIn(self, self._corner or 12)
	Layout9(self._rim, self, c * 2, c / 2)
end

function Surface:ApplySkin(fillToken, edgeToken)
	local c = A.Palette.c
	self:SetFillColor(c[fillToken or "glass"] or c.glass)
	self:SetEdgeColor(c[edgeToken or "glassEdge"] or c.glassEdge)
	if self._shadowOpacity then self:SetShadow(self._shadowOpacity) end
end

-- ---------------------------------------------------------------------------
-- constructors
-- ---------------------------------------------------------------------------

local function Adopt(frame)
	for k, v in pairs(Surface) do frame[k] = v end
	return frame
end

--- Surfaces are usually plain Frames, but a unit capsule or a dock has to be a
--  real Button carrying a secure template. opts.frameType / opts.template let a
--  caller ask for that without duplicating the whole constructor.
local function NewSurfaceFrame(parent, opts)
	return CreateFrame(opts.frameType or "Frame", opts.name, parent or UIParent, opts.template)
end

--- Rounded rectangle panel (quest tracker, dock, tooltips).
--  opts: { corner, shadow, fill, edge, frameType, template, name }
function Glass.CreatePanel(parent, opts)
	opts = opts or {}
	local f = NewSurfaceFrame(parent, opts)
	Adopt(f)

	f._kind   = "panel"
	f._corner = opts.corner or 12

	f._fill = Build9(f, Media.texture.panel, "BACKGROUND", 0)
	ApplyTexCoords(f._fill, Media.slice.panel, Media.textureSize.panel)

	f._edge = Build9(f, Media.texture.panelEdge, "BORDER", 0)
	ApplyTexCoords(f._edge, Media.slice.panel, Media.textureSize.panel)

	--- THE CORNER, SNAPPED TO WHOLE PHYSICAL PIXELS.
	--
	--  The pill has always done this to its caps and the panel never did to its
	--  corners, which is the difference between a curve that reads as a curve
	--  and one that reads as a staircase.
	--
	--  A panel drawn at a scale - 0.71 for the HUD, 0.85 for a client window -
	--  has a 12-unit corner land on 8.5 physical pixels. The arc's outer edge
	--  then falls across a pixel boundary the whole way round and the client
	--  resolves that as a ring of half-lit greys. It is the same fault
	--  W.CreateBadge records for its rim, and it is worst on small shapes,
	--  which is why a button showed it first: the smaller the radius, the larger
	--  the fraction of it that half-pixel is.
	--
	--  Re-run on size AND scale changes, because the snap depends on both.
	local function layout(self)
		local c = SnapIn(self, self._corner or 12)
		if c <= 0 then return end
		Layout9(self._fill, self, c, 0)
		Layout9(self._edge, self, c, 0)
		if self._backing then Layout9(self._backing, self, c, 0) end
		self:_LayoutPanelShadow()
		self:_LayoutRimGlow()
	end
	f._Relayout = layout
	f:HookScript("OnSizeChanged", layout)

	layout(f)

	f:ApplySkin(opts.fill, opts.edge)
	if opts.shadow then f:SetShadow(opts.shadow) end

	return f
end

function Glass.SetPanelCorner(f, corner)
	f._corner = corner
	if f._Relayout then f:_Relayout() end
end

--- Capsule (unit frames, buffs, cast bar, nameplates).
--  Cap width tracks height automatically so the ends stay circular.
--  Same opts as CreatePanel, minus corner.
function Glass.CreatePill(parent, opts)
	opts = opts or {}
	local f = NewSurfaceFrame(parent, opts)
	Adopt(f)

	f._kind = "pill"

	f._fill = Build3(f, Media.texture.pill, "BACKGROUND", 0, Media.slice.pill, Media.textureSize.pill)
	f._edge = Build3(f, Media.texture.pillEdge, "BORDER", 0, Media.slice.pill, Media.textureSize.pill)

	--- A pill is a HORIZONTAL capsule: the caps sit left and right and their
	--  width comes from the height, so the ends stay circular however wide the
	--  frame is. That holds only while the frame is at least as wide as it is
	--  tall.
	--
	--  Taller than wide, the two caps are each half the HEIGHT and are anchored
	--  to opposite edges of a narrower frame - so they overlap through the
	--  middle and the whole thing renders as one enormous circle bulging out of
	--  its own bounds. A vertical rail built with CreatePill came out looking
	--  like a black balloon.
	--
	--  Clamped rather than asserted, because the failure is silent and the
	--  degraded shape is the right one anyway: at w < h the cap becomes w/2 and
	--  the pill is a rounded rectangle with semicircular sides, which is what
	--  anybody asking for a tall capsule meant. Anything genuinely wanting a
	--  tall rounded shape should use CreatePanel with a corner radius.
	local function resize(self)
		local h, w = self:GetHeight() or 0, self:GetWidth() or 0
		local cap = SnapIn(self, math.min(h, w) / 2)
		if cap <= 0 then return end
		Layout3(self._fill, self, cap, 0)
		Layout3(self._edge, self, cap, 0)
		self:_LayoutPillShadow()
	end
	f._Resize = resize
	f:SetScript("OnSizeChanged", resize)

	-- Lay out once now in case the caller sized the frame before this point.
	resize(f)

	f:ApplySkin(opts.fill, opts.edge)
	if opts.shadow then f:SetShadow(opts.shadow) end

	return f
end
