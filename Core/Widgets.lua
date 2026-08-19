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
	-- Through W.Color rather than straight at the FontString, so the string is
	-- registered as ink and a skin change reaches it. Eighty strings sat outside
	-- the sweep because this line did the work itself.
	W.Color(fs, A.Palette.c.text)
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

--- Every string this has coloured FROM A TOKEN, so a skin change can reach
--  them. Same reasoning as the glass registry: frames are never destroyed,
--  and a string coloured with a computed value is not in here at all.
W.inked = {}

function W.Color(fs, c)
	if not fs or not c then return end
	-- Same reach-through as Restyle: a button carrying a label has no
	-- SetTextColor of its own.
	if not fs.SetTextColor and fs.GetFontString then
		fs = fs:GetFontString()
	end
	if not fs or not fs.SetTextColor then return end
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)

	-- WHICH token, if it was one. A caller handing over a mixed or dimmed
	-- colour owns it and re-applies it itself, exactly as a glass surface
	-- coloured by hand does - so the token is cleared rather than kept.
	local token = A.Palette.tokenOf and A.Palette.tokenOf[c]
	if token and not fs._aetherInk then
		W.inked[#W.inked + 1] = fs
	end
	fs._aetherInk = token
end

--- The texture half of the same idea.
--
--  A wash behind a bar, an icon tinted to a token: not text, not a glass
--  surface, and so in neither of the other two registries. Same rule - hand
--  it a palette table and it follows the skin, hand it a computed colour and
--  you own it.
W.tinted = {}

--- `alpha` overrides the colour's own, and is what gets remembered: a rail at
--  0.22 of the faint type and a thumb at 0.45 of the bright are the same two
--  tokens at two weights, and passing the palette's own table through keeps the
--  identity that makes the token findable.
--- The small marks that ride the level disc.
--
--  A DECORATOR IS NOT PART OF THE LAYOUT. Who leads, what somebody has been
--  marked with, what they do and whether they are flagged all answer the same
--  question - who is this - and the disc with their level in it is where that
--  question is already answered. So they sit ON it, one to a corner, and cost
--  the capsule no width at all.
--
--  That is not a detail. The role glyph used to have a well of its own at the
--  far right, and the width was reserved for it on every member whether or
--  not they had one - which was a strip of empty glass on most capsules. A
--  capsule that instead grew and shrank with its decorators would give a
--  ragged stack, which is worse than either.
--
--  ONE OF THESE, used by the player's capsule and by every party capsule.
--  Two drawings of a crown in two files is two places to disagree about where
--  it sits, and the second is always the one forgotten when the first moves.
--
--  opts: { glyph = <icon sheet name>, token = <palette token>, size = 13 }
--  No glyph is fine: the raid marker's art comes from the client's own sheet
--  and the PvP badge from the client's own file, and neither is ours to draw.
local DECORATOR_NUDGE = {
	TOPLEFT     = {  3, -2 },
	TOP         = {  0,  1 },
	BOTTOMRIGHT = { -3,  3 },
	BOTTOMLEFT  = {  3,  3 },
}

--- One raid target mark out of the client's sheet.
--
--  THE SHEET AND THE CELL, both. A texture given the file and no texcoord
--  draws all eight marks at once, which is unmistakable and has happened to
--  everybody once.
--
--  Written out rather than left to SetRaidTargetIconTexture. That call does
--  exactly this and is the obvious thing to use - but it is a global that
--  may or may not be there, and when it is not there it fails by drawing
--  nothing at all. One function that always works, and one place that knows
--  where the marks live.
local MARK_SHEET = [[Interface\TargetingFrame\UI-RaidTargetingIcons]]

function W.SetMarkIcon(tex, index)
	if not tex or not index or index < 1 or index > 8 then return false end
	tex:SetTexture(MARK_SHEET)
	local col, row = (index - 1) % 4, math.floor((index - 1) / 4)
	tex:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25)
	return true
end

--- The role a unit has said they play, when it is one worth showing.
--
--  NOT DAMAGER. This client answers DAMAGER for somebody who has never set a
--  role at all, so an arrow for it marks everybody and says nothing about any
--  of them. Tank and healer are the two that answer a question you ask.
--
--  ONE OF THESE for the party capsules and the player's and target's, so a
--  shield means the same thing wherever it turns up.
local ROLE_GLYPH = { TANK = "tank", HEALER = "healer" }

function W.SetRoleGlyph(tex, unit)
	if not tex then return false end
	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
	local glyph = ROLE_GLYPH[role or "NONE"]
	if glyph and A.Media:SetIcon(tex, glyph) then
		local c = A.Palette.c
		-- Through W.Tint, so it follows a skin change on its own.
		W.Tint(tex, (role == "TANK") and c.accent or c.friendly, 0.9)
		tex:Show()
		return true
	end
	tex:Hide()
	return false
end
--- The raid target mark on a decorator, in the client's own art.
--
--  A skull is a skull on every skin. SetRaidTargetIconTexture picks the cell
--  out of the sheet AND sets the texcoord; a texture given the file and no
--  coords draws all eight marks at once, which is unmistakable and has
--  happened to everybody once.
function W.SetRaidMark(tex, unit)
	if not tex then return false end
	local i = unit and GetRaidTargetIndex and GetRaidTargetIndex(unit)
	if i and W.SetMarkIcon(tex, i) then
		tex:Show()
		return true
	end
	tex:Hide()
	return false
end

--- The PvP flag, in the client's own faction art.
--
--  Faction identity is the game's, like a class colour and like the raid
--  marks - so this is Blizzard's own file, untinted. Neutral units have no
--  badge at all, which is why the faction is asked for rather than assumed
--  from a boolean.
function W.SetPvPMark(tex, unit)
	if not tex then return false end
	local flagged = UnitIsPVP and UnitIsPVP(unit)
	local faction = flagged and UnitFactionGroup and UnitFactionGroup(unit)
	if flagged and faction and faction ~= "Neutral" then
		tex:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
		tex:Show()
		return true
	end
	tex:Hide()
	return false
end
--- The layer decorators are drawn on: ABOVE THE DISC, whatever level it is.
--
--  This is the whole reason a decorator is not just a texture on the
--  capsule. The disc - a level pip, an orb, a nameplate badge - is a CHILD
--  FRAME of the capsule, and a child frame draws over every one of its
--  parent's regions whatever draw layer they are on. So a mark centred on
--  the disc's top edge had its lower half behind the disc and read as
--  nothing at all; the crown survived only because it hangs outside the
--  disc's bounds, which is why one of them looked fine and one did not.
--
--  A frame of our own, two levels above the disc, and they all sit on it.
--  Same fix as the aura marks in Modules/IFEC/Player.lua, and the same
--  rule as everywhere else in this interface: our surface has to BE the
--  thing it is decorating or sit over it, never beside it.
function W.DecoratorLayer(parent, disc)
	local layer = CreateFrame("Frame", nil, parent)
	layer:SetAllPoints(parent)
	local base = (disc and disc.GetFrameLevel and disc:GetFrameLevel())
		or (parent.GetFrameLevel and parent:GetFrameLevel()) or 0
	layer:SetFrameLevel(base + 2)
	return layer
end

function W.CreateDecorator(layer, anchorTo, corner, opts)
	opts = opts or {}
	local t = layer:CreateTexture(nil, "OVERLAY", nil, 7)
	local size = opts.size or 13
	t:SetSize(size, size)
	local nudge = DECORATOR_NUDGE[corner] or DECORATOR_NUDGE.TOPLEFT
	t:SetPoint("CENTER", anchorTo, corner, nudge[1], nudge[2])
	if opts.glyph then A.Media:SetIcon(t, opts.glyph) end
	-- Through W.Tint rather than SetVertexColor, so it follows a skin change
	-- on its own. The crown is the reserved semantic gold and Dusk is the one
	-- skin that moves it.
	if opts.token then W.Tint(t, A.Palette.c[opts.token]) end
	t:Hide()
	return t
end
function W.Tint(tex, c, alpha)
	if not tex or not c or not tex.SetVertexColor then return end
	alpha = alpha or c[4] or 1
	tex:SetVertexColor(c[1], c[2], c[3], alpha)
	-- By identity for a palette table, by name for a derived one - a wash
	-- from Palette:Track is built fresh each call and says so itself.
	local token = c.token or (A.Palette.tokenOf and A.Palette.tokenOf[c])
	if token and not tex._aetherTint then
		W.tinted[#W.tinted + 1] = tex
	end
	tex._aetherTint = token
	-- The weight the CALLER asked for, not the token's own: the XP bar wants
	-- a quieter wash than a status bar and must keep it across a restyle.
	tex._aetherTintAlpha = token and alpha or nil
end

--- Re-read the palette for every string or texture still coloured by token.
--  Returns how many it touched.
function W.RestyleInk()
	local n = 0
	for i = 1, #W.inked do
		local fs = W.inked[i]
		local c = fs._aetherInk and A.Palette.c[fs._aetherInk]
		if c then
			fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
			n = n + 1
		end
	end
	for i = 1, #W.tinted do
		local tex = W.tinted[i]
		local c = tex._aetherTint and A.Palette.c[tex._aetherTint]
		if c then
			tex:SetVertexColor(c[1], c[2], c[3],
				tex._aetherTintAlpha or c[4] or 1)
			n = n + 1
		end
	end
	return n
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

--- Through W.Tint, so a backdrop set from a token follows the skin and one set
--  from a computed colour does not - the same rule every other surface follows,
--  rather than a second way of colouring the same texture.
function Bar:SetBackdropColor(c, alpha)
	W.Tint(self.bg, c, alpha)
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
	W.Tint(bg, A.Palette:Track(opts.bgAlpha))
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
-- segmented bar
-- ---------------------------------------------------------------------------
--
-- A track cut into pieces along a shared time axis: one piece per item on the
-- programme, each as wide as it is long. Not a StatusBar - a StatusBar has one
-- fill and one value, and this has N of each.
--
-- WIDTH IS TIME. Every piece is placed by (seconds so far / total seconds), so
-- two bars given the same total share an axis exactly, which is what lets the
-- landing line drawn across both mean the same instant on each.

local SEG_GAP = 2                  -- the design's gap between pieces

local Segmented = {}

--- Lay pieces out across `total` seconds.
--
--  `pieces` is { { seconds, colour, filled }, ... } in order. A piece that is
--  not `filled` is drawn as an outline over the track tint: queued rather than
--  played. Anything past `total` is simply off the end - the caller decides
--  what to say about an overrun.
function Segmented:SetPieces(pieces, total)
	self._pieces, self._total = pieces or {}, total or 0

	local width = self:GetWidth() or 0
	if width <= 0 or self._total <= 0 then
		for _, p in ipairs(self.parts) do p:Hide() end
		return
	end

	local at, n = 0, 0
	for i, piece in ipairs(self._pieces) do
		local secs = piece.seconds or 0
		local w = (secs / self._total) * width - SEG_GAP
		if w > 1 then
			n = n + 1
			local part = self.parts[n]
			if not part then
				part = CreateFrame("Frame", nil, self)
				part.fill = part:CreateTexture(nil, "ARTWORK")
				part.fill:SetTexture(Media.texture.flat)
				part.fill:SetAllPoints(part)
				part.edge = A.Glass.CreatePill(part, { fill = "glass", edge = "glassEdge" })
				part.edge:SetAllPoints(part)
				self.parts[n] = part
			end

			part:ClearAllPoints()
			part:SetPoint("LEFT", self, "LEFT", (at / self._total) * width, 0)
			part:SetHeight(self:GetHeight())
			part:SetWidth(w)

			local c = piece.colour or { 1, 1, 1 }
			-- Filled is played or playing; outlined is queued. The design draws
			-- the queued state as a dashed border, and Classic has no dashed
			-- stroke - a tiling dash would have to rescale per segment. Hollow
			-- against solid says the same thing and survives any width.
			part.fill:SetVertexColor(c[1], c[2], c[3], piece.filled and 0.95 or 0.16)
			part.edge:SetShown(not piece.filled)
			if not piece.filled then
				part.edge:SetEdgeColor({ c[1], c[2], c[3], 0.55 })
			end
			part:Show()
		end
		at = at + secs
	end

	for i = n + 1, #self.parts do self.parts[i]:Hide() end
end

--- How far along `seconds` sits, in this bar's own pixels. What the landing
--  line and the leg ticks are placed with.
function Segmented:XFor(seconds)
	local width = self:GetWidth() or 0
	if width <= 0 or (self._total or 0) <= 0 then return 0 end
	local x = (seconds / self._total) * width
	if x < 0 then x = 0 end
	if x > width then x = width end
	return x
end

function W.CreateSegmentedBar(parent, opts)
	opts = opts or {}
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(opts.height or 7)

	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetTexture(Media.texture.flat)
	bar.bg:SetAllPoints(bar)
	W.Tint(bar.bg, A.Palette:Track(opts.bgAlpha))

	bar.parts = {}
	for k, v in pairs(Segmented) do bar[k] = v end
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
	-- OR THE BUTTON ITSELF, when it IS a surface rather than one that was
	-- handed a skin. The dock handles are built as glass panels with a button
	-- frame type - the Toolbox rail's, the party dock's, the bags drawer's -
	-- so they carry no __aetherSkin and this returned early on every one of
	-- them. Which is why the party handle had no hover state at all: the call
	-- was there, correct, and doing nothing.
	local skin = btn and (btn.__aetherSkin
		or (btn.SetFillColor and btn.SetEdgeShown and btn))
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
-- tabs
--
-- ONE TAB LANGUAGE, and it is not the button's.
--
-- A tab is BARE TEXT ON A SHARED HAIRLINE. Only the one you are standing on
-- carries anything: a 2px accent mark with a soft glow, sitting ON the
-- hairline, always on the edge that touches the content the tab switches. No
-- pill, no rim, no fill - nothing that reads as pressable.
--
-- That distinction is the whole point of the pattern. A BUTTON does a thing; a
-- TAB changes which view of the same frame you are looking at, and telling the
-- two apart at a glance is what this interface was failing at: every tabbed
-- surface in it - the client's panels, the chat dock, the spellbook's schools,
-- the console's library - had grown its own answer, and four of them were the
-- same filled pill that Create, Send and Accept wear.
--
-- THE MARK BELONGS TO THE TAB, not to the rail, which is the one place this
-- departs from the handoff's markup. A rail owning a sliding bar has to know
-- where every tab is - and these tabs are Blizzard's: re-anchored, re-sized
-- and re-parented by the client on every dock update and every tab click. A
-- mark hung off the tab cannot be left behind by any of that. The handoff's
-- slide between positions is optional in its own words, and this is what buys
-- it: there is nothing to slide.
--
-- The ink is this interface's own three-step ladder rather than the deck's
-- three literal alphas: textFaint for the tabs you are not on, textDim under
-- the cursor, text for the one you are. Same ordering, and it follows a skin
-- change on its own.
-- ---------------------------------------------------------------------------

-- The deck's numbers. A rail is FIXED: tabs give way, the frame never grows.
W.TAB_RAIL_H = 38          -- a horizontal rail's height; tabs fill it
W.TAB_RAIL_W = 52          -- a vertical icon rail's width

-- What gives, and in what order, when a row stops fitting: the padding either
-- side first, then a point off the lettering, and only then the words
-- themselves. A label shortened to three dots tells you less than the word did,
-- so it goes last and never without a tooltip carrying the whole of it.
W.TAB_PADS = { 16, 14, 10 }

-- TWO WASHES, and the whole point is that they are not the same wash.
--
-- `rowHover` is this interface's you-are-over-this fill, and both of these are
-- struck from it so a skin change reaches both. HOVER is that fill at half;
-- the RAIL's is a fraction of it - the deck says .07 and .04 against the same
-- hue, and they were briefly the same number here, which drew the spellbook's
-- whole school column looking permanently hovered.
local TAB_WASH      = 0.5
local TAB_RAIL_WASH = 0.28

local TAB_MARK    = 2      -- the indicator's thickness
local TAB_MARK_IN = 5      -- ...inset from each end of the tab it marks
local TAB_GLOW    = 12     -- how far its bloom reaches across the rail
local TAB_DOT     = 5

--- Which edge of a rail faces the content it switches.
--
--  A rail along the BOTTOM of a panel has its hairline and its mark on its
--  TOP, because that is the side the panel is on. Chat's rail is on top and
--  everything mirrors. Getting this backwards draws a tab attached to the
--  world rather than to its own window.
local TAB_FACE = {
	BOTTOM = "TOP", TOP = "BOTTOM", RIGHT = "LEFT", LEFT = "RIGHT",
}

local TAB_VERTICAL = { LEFT = true, RIGHT = true }

--- The line a row of tabs sits on.
--
--  One per host, kept on the frame, so a second call is a re-layout rather
--  than a second rail. Sizing and placing it is the caller's: only the caller
--  knows where its own tab row lives.
--
--  `tint` is a faint wash over the whole rail, and it is MANDATORY on a
--  vertical icon rail - it is the only thing that says four pictures in a
--  column are one control rather than four loose buttons. A row of words does
--  not need it; the hairline already gathers them.
function W.TabRail(host, edge, opts)
	if not host or not host.CreateTexture then return nil end
	opts = opts or {}

	local rail = host.__aetherRail
	if not rail then
		rail = CreateFrame("Frame", nil, host)
		rail.tint = rail:CreateTexture(nil, "BACKGROUND")
		rail.tint:SetTexture(Media.texture.flat)
		rail.tint:SetAllPoints(rail)
		rail.rule = rail:CreateTexture(nil, "BORDER")
		rail.rule:SetTexture(Media.texture.flat)
		host.__aetherRail = rail
	end

	rail._edge = TAB_FACE[edge] and edge or "BOTTOM"
	local face = TAB_FACE[rail._edge]

	rail.rule:ClearAllPoints()
	if TAB_VERTICAL[rail._edge] then
		rail.rule:SetPoint("TOP" .. face, rail, "TOP" .. face, 0, 0)
		rail.rule:SetPoint("BOTTOM" .. face, rail, "BOTTOM" .. face, 0, 0)
		rail.rule:SetWidth(A:Px(1))
	else
		rail.rule:SetPoint(face .. "LEFT", rail, face .. "LEFT", 0, 0)
		rail.rule:SetPoint(face .. "RIGHT", rail, face .. "RIGHT", 0, 0)
		rail.rule:SetHeight(A:Px(1))
	end

	local c = A.Palette.c
	local rule = c.glassEdge
	rail.rule:SetVertexColor(rule[1], rule[2], rule[3], rule[4] or 1)

	-- OFF UNLESS ASKED FOR. The handoff calls the vertical rail's wash
	-- mandatory, on the argument that it is the only thing saying a column
	-- of pictures is one control - and that argument is written against a
	-- FLAT background. Ours is frosted glass: a wash lands on top of a fill
	-- that is already semi-transparent and doubles it locally, so four per
	-- cent of lilac came out as a slab down the side of the spellbook and
	-- read as a column stuck permanently under the cursor.
	--
	-- The hairline runs the whole length of the column and gathers it
	-- perfectly well, which is exactly how the horizontal rail gathers a row
	-- of words. One mechanism for both, and no slab.
	local wash = opts.tint
	if wash then
		local h = c.rowHover
		rail.tint:SetVertexColor(h[1], h[2], h[3], (h[4] or 1) * TAB_RAIL_WASH)
		rail.tint:Show()
	else
		rail.tint:Hide()
	end

	return rail
end

--- Dress a button as a tab. Idempotent: the parts are made once.
--
--  `icon` says this is one of a vertical rail's pictures rather than a word,
--  which changes how the three states are drawn - a picture dims and drains
--  where a word goes quiet, being the exact analogue of dim text.
function W.Tab(tab, opts)
	if not tab or not tab.CreateTexture then return nil end
	opts = opts or {}

	if not tab.__aetherMark then
		-- UNDER the mark and wider than it, additively, so it brightens the
		-- hairline rather than painting a band over it.
		local glow = tab:CreateTexture(nil, "ARTWORK")
		glow:SetTexture(Media.texture.glow)
		glow:SetBlendMode("ADD")
		tab.__aetherMarkGlow = glow

		local mark = tab:CreateTexture(nil, "OVERLAY")
		mark:SetTexture(Media.texture.flat)
		tab.__aetherMark = mark

		-- The hover wash, the full height of the tab. No rim and no corner:
		-- the moment a tab has an outline it is a button again.
		local wash = tab:CreateTexture(nil, "BACKGROUND")
		wash:SetTexture(Media.texture.flat)
		wash:SetAllPoints(tab)
		wash:Hide()
		tab.__aetherWash = wash

		-- Something new on a tab you are not looking at. Never a flashing
		-- fill, which is what the client does and what this replaces.
		local dot = tab:CreateTexture(nil, "OVERLAY")
		dot:SetTexture(Media.texture.chipDisc)
		dot:SetSize(TAB_DOT, TAB_DOT)
		dot:Hide()
		tab.__aetherDot = dot
	end

	tab.__aetherTabIcon = opts.icon and true or nil
	tab.__aetherTabEdge = TAB_FACE[opts.edge] and opts.edge or nil
	-- WHICH RAIL'S LINE IT STANDS ON, handed in rather than looked up off
	-- the parent. A tab is not reliably a child of its rail's host: the
	-- spellbook's schools are children of SpellBookSideTabsFrame, a
	-- full-window frame of Blizzard's that exists only to hold them - so
	-- the parent lookup found nothing and the mark fell back to the
	-- icon's own edge, six pixels in from the line it belongs on.
	if opts.rail then tab.__aetherTabRail = opts.rail end

	if opts.label then tab.__aetherLabel = opts.label end
	if opts.art then tab.__aetherTabArt = opts.art end

	if tab.HookScript and not tab.__aetherTabHooked then
		tab.__aetherTabHooked = true
		tab:HookScript("OnEnter", function(self)
			W.TabState(self, self.__aetherSelected, true)
		end)
		tab:HookScript("OnLeave", function(self)
			W.TabState(self, self.__aetherSelected, false)
		end)
	end

	return tab.__aetherMark
end

--- Where a tab's own mark sits: on the rail's hairline, inset from both ends.
--- Where a tab's own mark sits: ON THE RAIL'S HAIRLINE, inset from both ends
--- of the tab it belongs to.
--
--  THREE POINTS, and they come from two different frames. The two that fix
--  its LENGTH are the tab's, because the mark is as long as the thing it
--  marks; the one that fixes which line it sits on is the RAIL's, because
--  that is the line.
--
--  Those were the same frame for a row of words - LayoutTabs makes each tab
--  the full height of its rail, so the tab's bottom edge IS the hairline. They
--  are not the same frame for a column of icons: a 32px picture in a 44px rail
--  leaves six either side, and a mark on the icon's own edge drew as a bar
--  stuck to the picture rather than as a marker on the rail.
local function PlaceMark(tab, edge, rail)
	local mark, glow = tab.__aetherMark, tab.__aetherMarkGlow
	if not mark then return end

	local face = TAB_FACE[edge]
	local line = rail or tab
	mark:ClearAllPoints()
	glow:ClearAllPoints()

	if TAB_VERTICAL[edge] then
		mark:SetPoint("TOP", tab, "TOP", 0, -TAB_MARK_IN)
		mark:SetPoint("BOTTOM", tab, "BOTTOM", 0, TAB_MARK_IN)
		mark:SetPoint(face, line, face, 0, 0)
		mark:SetWidth(TAB_MARK)
	else
		mark:SetPoint("LEFT", tab, "LEFT", TAB_MARK_IN, 0)
		mark:SetPoint("RIGHT", tab, "RIGHT", -TAB_MARK_IN, 0)
		mark:SetPoint(face, line, face, 0, 0)
		mark:SetHeight(TAB_MARK)
	end

	glow:SetPoint("TOPLEFT", mark, "TOPLEFT", -TAB_GLOW / 2, TAB_GLOW / 2)
	glow:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT",
		TAB_GLOW / 2, -TAB_GLOW / 2)
end

--- The three states, and nothing else draws them.
--
--  Selected is BRIGHT TEXT AND A MARK, not a filled surface - which is the
--  difference between this and W.SetButtonState, and the difference the player
--  is meant to read. A filled tab and a filled button say the same thing in an
--  interface where they mean two different things.
function W.TabState(tab, selected, hovered)
	if not tab or not tab.__aetherMark then return end
	local c = A.Palette.c
	tab.__aetherSelected = selected and true or false

	local host = tab.GetParent and tab:GetParent()
	local edge = tab.__aetherTabEdge
		or (host and host.__aetherRail and host.__aetherRail._edge)
		or "BOTTOM"
	-- UNLESS THE CALLER OWNS IT. A chat tab's own box is Blizzard's 32-tall
	-- art frame, three pixels taller than the dock it sits in and centred on
	-- a line that is not the hairline - and its width is rewritten twice per
	-- click - so that one anchors its own, to the LABEL for length and to the
	-- rail's line for the rest. Same rule, stated against different frames.
	if not tab.__aetherMarkOwn then
		PlaceMark(tab, edge, tab.__aetherTabRail)
	end

	local a = c.accent
	tab.__aetherMark:SetVertexColor(a[1], a[2], a[3], 1)
	tab.__aetherMark:SetShown(selected and true or false)
	tab.__aetherMarkGlow:SetVertexColor(a[1], a[2], a[3], 0.55)
	tab.__aetherMarkGlow:SetShown(selected and true or false)

	local h = c.rowHover
	tab.__aetherWash:SetVertexColor(h[1], h[2], h[3], (h[4] or 1) * TAB_WASH)
	-- NOT ON AN ICON. A picture's hover is the picture coming back - full
	-- colour, full strength - and a wash behind it as well is a second answer
	-- to the same question, laid over a rail that is already washed.
	tab.__aetherWash:SetShown((hovered and not selected
		and not tab.__aetherTabIcon) and true or false)

	-- A PICTURE DIMS AND DRAINS where a word goes quiet: same three steps,
	-- drawn the only way a coloured icon can carry them.
	if tab.__aetherTabIcon then
		local art = tab.__aetherTabArt
			or (tab.GetNormalTexture and tab:GetNormalTexture())
		if art then
			art:SetAlpha((selected or hovered) and 1 or 0.45)
			if art.SetDesaturated then
				pcall(art.SetDesaturated, art,
					(not selected and not hovered) or nil)
			end
		end
		return
	end

	local label = tab.__aetherLabel
		or (tab.GetFontString and tab:GetFontString())
	if not label or not label.SetTextColor then return end

	local ink = selected and c.text or (hovered and c.textDim or c.textFaint)
	label:SetTextColor(ink[1], ink[2], ink[3], ink[4] or 1)
	-- NO SHADOW ON ANY OF THEM. Blizzard bakes one into its tab fonts -
	-- GameFontNormalSmall inherits SystemFont_Shadow_Small, and SetFont does
	-- not clear it - and a black halo under a word on glass reads as a smudge
	-- rather than as depth. It used to be cleared on the SELECTED tab only,
	-- because that one had a pale fill behind it to be smudged against. There
	-- is no fill behind any of them now.
	if label.SetShadowOffset then label:SetShadowOffset(0, 0) end
	if label.SetShadowColor then label:SetShadowColor(0, 0, 0, 0) end
end

--- Something wants your attention on a tab you are not looking at.
--
--  `kind` is nil for nothing, "new" for ordinary traffic, and
--  "personal" for something addressed to you - a whisper, an
--  invite - which takes the reserved gold rather than the accent, the way
--  every other personal signal in this interface does.
function W.TabDot(tab, kind, anchorTo)
	local dot = tab and tab.__aetherDot
	if not dot then return end
	if not kind then return dot:Hide() end

	local c = A.Palette.c
	local col = (kind == "personal") and c.semanticGold or c.accent
	dot:SetVertexColor(col[1], col[2], col[3], 1)

	dot:ClearAllPoints()
	if tab.__aetherTabIcon then
		-- The icon's top-right corner, clear of the picture.
		dot:SetPoint("CENTER", tab, "TOPRIGHT", -1, -1)
	else
		local to = anchorTo or tab.__aetherLabel
			or (tab.GetFontString and tab:GetFontString())
		if to then
			dot:SetPoint("LEFT", to, "RIGHT", 6, 0)
		else
			dot:SetPoint("RIGHT", tab, "RIGHT", -4, 0)
		end
	end
	dot:Show()
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
-- context menu
--
-- Hand-rolled rather than UIDropDownMenu. Partly because a glass menu is the
-- house style and Blizzard's is not, but mostly because the dropdown-era
-- globals are GONE on this client - reaching for them fails silently, so
-- right-click does nothing and nothing errors. A menu we own outright cannot
-- disappear under us.
--
-- Here rather than in the module that first needed one: the quest tracker built
-- this, and the second thing that wanted a menu would otherwise have built a
-- near-copy with its own opinions about anchoring and its own bugs.
-- ---------------------------------------------------------------------------

local MENU_W, MENU_ROW = 150, 22

local Menu = {}

local function BuildMenu()
	local closer = CreateFrame("Frame", nil, UIParent)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:EnableMouse(true)
	closer:Hide()

	-- `dialogFill`, not glass, for the reason the palette gives that token: a
	-- surface you have to READ must not be frosted-on-frosted. A menu opens on
	-- top of a panel, so at the control-surface opacity it is two translucent
	-- layers over a lit world and the item text competes with whatever is
	-- showing through it.
	--
	-- `glassEdgeHi` with it: the brighter rim is what separates a pop-over from
	-- the panel underneath, and an opaque fill inside a dim rim reads as a hole.
	local menu = A.Glass.CreatePanel(UIParent, {
		corner = 8, shadow = A.db.profile.glass.shadow,
		fill = "dialogFill", edge = "glassEdgeHi",
	})
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(closer:GetFrameLevel() + 10)
	menu:SetWidth(MENU_W)
	menu:Hide()

	closer:SetScript("OnMouseDown", function()
		menu:Hide()
		closer:Hide()
	end)
	menu:SetScript("OnHide", function() closer:Hide() end)

	menu.closer = closer
	menu.items = {}
	return menu
end

local function MenuItem(menu, i)
	local item = menu.items[i]
	if item then return item end

	item = CreateFrame("Button", nil, menu)
	item:SetHeight(MENU_ROW)

	local hl = item:CreateTexture(nil, "BACKGROUND")
	hl:SetTexture(A.Media.texture.flat)
	hl:SetAllPoints(item)
	hl:Hide()
	item.hl = hl

	item.text = W.Text(item, "questLine", "LEFT")
	item.text:SetPoint("LEFT", item, "LEFT", 8, 0)

	item:SetScript("OnEnter", function(self) self.hl:Show() end)
	item:SetScript("OnLeave", function(self) self.hl:Hide() end)
	item:SetScript("OnClick", function(self)
		menu:Hide()
		if self.action then self.action() end
	end)

	menu.items[i] = item
	return item
end

--- Open a menu on `anchor`.
--
--  entries: { { text = "...", action = fn, danger = bool, disabled = bool } }
--  opts:    { point, relPoint, x, y } - where the menu's corner meets the
--           anchor's. Defaults to hanging under its left edge.
--
--  A disabled entry is SHOWN and does nothing. Dropping the row instead makes
--  the menu change shape from one opening to the next, so the third item is
--  sometimes the fourth - and a menu you cannot learn the shape of is worse
--  than one carrying a greyed line that says why.
--
--  ONE MENU FOR THE WHOLE INTERFACE. Two open at once is two closers covering
--  the screen, and whichever was raised last eats the click meant for the other.
function W.Menu(anchor, entries, opts)
	opts = opts or {}
	Menu.frame = Menu.frame or BuildMenu()
	local menu = Menu.frame
	local c = A.Palette.c

	local shown = 0
	for _, e in ipairs(entries or {}) do
		shown = shown + 1
		local item = MenuItem(menu, shown)
		item.text:SetText(e.text)
		if e.disabled then
			W.Color(item.text, c.textFaint)
		else
			W.Color(item.text, e.danger and c.danger or c.text)
		end
		-- No hover glow on a dead row either, or it still reads as clickable.
		item.hl:SetVertexColor(c.accent[1], c.accent[2], c.accent[3],
			e.disabled and 0 or 0.18)
		item.action = (not e.disabled) and e.action or nil
		item:ClearAllPoints()
		item:SetPoint("LEFT", menu, "LEFT", 6, 0)
		item:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
		item:SetPoint("TOP", menu, "TOP", 0, -(6 + (shown - 1) * MENU_ROW))
		item:Show()
	end
	for i = shown + 1, #menu.items do menu.items[i]:Hide() end

	menu:SetHeight(12 + shown * MENU_ROW)
	menu:SetScale(A.db.profile.scale)
	menu:ClearAllPoints()
	menu:SetPoint(opts.point or "TOPLEFT", anchor,
		opts.relPoint or "BOTTOMLEFT", opts.x or 6, opts.y or -2)
	menu.closer:Show()
	menu:Show()
	return menu
end

--- Raise the game tooltip on `owner`, and make sure it is on top.
--
--  THE STRATA IS ASSERTED, not assumed. The tooltip is a shared object anything
--  can reparent, and this addon does exactly that: the console moves it out of
--  UIParent for a flight so it can be read over a hidden interface, and hands
--  it back on landing. Anything that leaves it somewhere else - a landing
--  missed in combat, another addon with the same idea - leaves it drawing under
--  the chat log, which is where it was found.
--
--  Cheap, and idempotent: TOOLTIP is where the client puts it anyway, so
--  saying so again can never be wrong.
function W.Tooltip(owner, anchor, title, body)
	if not GameTooltip or not owner then return false end

	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	if GameTooltip.SetFrameStrata then GameTooltip:SetFrameStrata("TOOLTIP") end
	if GameTooltip.SetToplevel then GameTooltip:SetToplevel(true) end

	GameTooltip:SetText(title or "")
	if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
	GameTooltip:Show()
	return true
end

function W.HideTooltip()
	if GameTooltip then GameTooltip:Hide() end
end

function W.CloseMenu()
	if Menu.frame then Menu.frame:Hide() end
end

--- The one menu, or nothing if nobody has opened one yet. For anything that
--  needs to ask about it rather than drive it.
function W.MenuFrame()
	return Menu.frame
end

--- Re-skin it after the palette has changed under it.
--
--  ITS OWN JOB, not the caller's. While this lived in the quest tracker, the
--  tracker's OnSkinChanged re-applied it - and the second module to open a menu
--  would have inherited a surface that only follows the skin if the FIRST
--  module happens to be enabled.
--- The context menu belongs to no module - any of them can open it - so
--  nobody's OnSkinChanged is the right place for it, and the one that used to
--  do it left the menu following the skin only while that module happened to be
--  enabled. Core used to name it by hand instead; it subscribes now, which is
--  what the listener registry is for.
function W.RestyleMenu()
	if Menu.frame then Menu.frame:ApplySkin("dialogFill", "glassEdgeHi") end
end
A:OnSkinChanged(W.RestyleMenu)

-- ---------------------------------------------------------------------------
-- misc
-- ---------------------------------------------------------------------------

--- Point a chevron on a docked thing that opens and shuts.
--
--  ONE RULE, TWO USERS: the Toolbox rail and the party dock handle. Both are
--  a tab flush to a screen edge with a drawer behind them, and both have the
--  same answer - OPEN, the click retreats the drawer to its own edge; SHUT,
--  it emerges away from it. A second copy of that would be a second chance to
--  get one of the eight cases backwards.
--
--  Left and right docks get < and >, top and bottom get ^ and v. The drawer
--  moves along the axis it is docked on, so an arrow across that axis points
--  at nothing.
--
--  Rotation is counter-clockwise, and the art points DOWN at rest - so a
--  right-pointing arrow is +pi/2.
local CHEV_DOWN, CHEV_UP    = 0, math.pi
local CHEV_RIGHT, CHEV_LEFT = math.pi / 2, -math.pi / 2

local CHEV_TURN = {
	DOWN = CHEV_DOWN, UP = CHEV_UP, RIGHT = CHEV_RIGHT, LEFT = CHEV_LEFT,
}

local CHEV_FACING = {
	LEFT   = { open = "LEFT",  shut = "RIGHT" },
	RIGHT  = { open = "RIGHT", shut = "LEFT"  },
	TOP    = { open = "UP",    shut = "DOWN"  },
	BOTTOM = { open = "DOWN",  shut = "UP"    },
}

--- Point a chevron a plain compass direction.
--
--  The turning lives here and nowhere else. A page turner and a count
--  spinner want an arrow pointing a way, with no drawer and nothing to be
--  open or shut about - and a second table of radians is a second chance to
--  get one of them backwards.
function W.FaceChevron(tex, facing)
	local turns = CHEV_TURN[facing] or CHEV_DOWN
	if tex and tex.SetRotation then pcall(tex.SetRotation, tex, turns) end
	return turns
end

function W.PointChevron(tex, edge, open)
	local f = CHEV_FACING[edge] or CHEV_FACING.LEFT
	return W.FaceChevron(tex, open and f.open or f.shut)
end

--- One step of a reversible 0..1 slide. The scheduling is the caller's.
--
--  There are two drawers in this interface - the Toolbox and the bags' equipped
--  list - and both slide by chasing a single travel toward a target rather than
--  by remembering a start time and a duration. That shape is what makes them
--  INTERRUPTIBLE: clicking twice quickly reverses, because reversing is only
--  changing the target and the panel carries on from wherever it had got to.
--
--  Here rather than twice, because the trap is the same both times and it is
--  not obvious: a lerp written as `at + (want - at) * k` approaches its target
--  and never reaches it, so the drawer creeps for ever and the ticker never
--  stops. This one steps by a fixed rate and CLAMPS, and says when it has
--  arrived - exactly, not nearly.
--
--  `rate` is 1/seconds, so a 300ms slide is 1/0.30.
function W.StepTravel(at, want, rate, dt)
	at, want = at or 0, want or 0
	if math.abs(want - at) < 0.001 then return want, true end

	local step = (rate or 1) * (dt or 0)
	if want > at then
		at = math.min(want, at + step)
	else
		at = math.max(want, at - step)
	end
	return at, at == want
end

--- Walk `owner._travel` toward `owner._want`, once per frame, until it lands.
--
--  ON A FRAME rather than on the shared ticker in Core, which fires at 0.1s.
--  Ten steps a second is THREE of them across a 300ms slide, and three
--  positions over a couple of hundred pixels is a snap with two stops in it
--  rather than a movement. All three drawers here - the Toolbox, the party
--  controls and the bags' equipped list - used to look like that.
--
--  `host` is only somewhere to hang the script, but it must be a frame that is
--  SHOWN for the length of the slide: a hidden frame gets no OnUpdate and the
--  drawer would stop dead where it was. The script is taken off again the
--  moment it lands, so nothing polls while a drawer is sitting still.
function W.DriveSlide(host, owner, rate, onStep)
	if not (host and host.SetScript and owner) then return end

	host:SetScript("OnUpdate", function(self, dt)
		local at, arrived = W.StepTravel(owner._travel, owner._want, rate, dt)
		owner._travel = at
		if onStep then onStep(owner) end
		-- AFTER the step is drawn, not before: the last frame of a slide is
		-- the one that puts it exactly where it belongs.
		if arrived then self:SetScript("OnUpdate", nil) end
	end)
end

--- Stop one where it stands.
function W.StopSlide(host)
	if host and host.SetScript then host:SetScript("OnUpdate", nil) end
end

--- How far a drawer docked to `edge` has to move to be entirely off screen.
--
--  The other half of a slide: StepTravel says how far along it is, this says
--  how far along there is to go. Shared by the Toolbox drawer and the party
--  controls, which dock to the same four edges by the same rules.
function W.ClosedOffset(edge, w, h)
	if edge == "LEFT"  then return -w, 0 end
	if edge == "RIGHT" then return  w, 0 end
	if edge == "TOP"   then return  0, h end
	return 0, -h
end

--- Which screen edge a point belongs to.
--
--  BY FRACTION OF THE SCREEN, not by distance in pixels. On a wide monitor
--  the middle of the left-hand side is nearer the top and bottom edges in raw
--  pixels than it is to the left one - a thousand across versus seven hundred
--  up - and answering TOP for a point hard against the left side is nonsense
--  a player would report as the drag being broken.
--
--  Shared by the Toolbox rail and the party dock handle. Two copies of a rule
--  this easy to get subtly wrong is one copy too many.
function W.NearestEdge(x, y, w, h)
	w = w or (UIParent:GetWidth() or 0)
	h = h or (UIParent:GetHeight() or 0)
	if w <= 0 or h <= 0 then return nil end

	local fx, fy = x / w, y / h
	local best, dist = "LEFT", fx
	if (1 - fx) < dist then best, dist = "RIGHT", 1 - fx end
	if fy < dist then best, dist = "BOTTOM", fy end
	if (1 - fy) < dist then best, dist = "TOP", 1 - fy end
	return best
end

--- Which HALF of that edge, as a slot number.
--
--  Two anchor points per edge - a quarter along and three quarters - so two
--  things can share one side without either hunting for space. Slot 1 is the
--  upper half of a side edge and the left half of a top or bottom one, which
--  is the reading order in both directions.
function W.EdgeSlot(edge, x, y, w, h)
	w = w or (UIParent:GetWidth() or 0)
	h = h or (UIParent:GetHeight() or 0)
	if w <= 0 or h <= 0 then return 1 end
	if edge == "LEFT" or edge == "RIGHT" then
		return (y > h / 2) and 1 or 2
	end
	return (x < w / 2) and 1 or 2
end
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
