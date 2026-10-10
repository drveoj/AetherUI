--[[--------------------------------------------------------------------------
	Lattice :: Options controls

	The options window's page body (options handoff 7b): the option tree's
	leaves drawn in the panel vocabulary, in two columns.

	  toggle       a 20 px diamond; on is accent with a glow, ON/OFF at the right
	  range        a strand with the filled part in accent and a diamond thumb
	  select       diamonds on a strand with their names under them; a dropdown
	               when the list is long; four skin chips for `control =
	               "swatches"`
	  color        a 20 px circle swatch, opening the game's colour picker
	  execute      a pill button; `confirm` wants a second click
	  input        a text field; Enter sets it
	  description  a paragraph
	  header       and inline groups: a junction-and-strand section heading

	Every leaf is read and written through its own get and set, with an info
	table carrying its type and arg, which is all the tree's accessors ask for.
	Nothing here knows what any setting means.

	Sections are kept whole and dealt to whichever column is shorter, so a
	long section never splits across the two.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = A.L
local W, Media, Palette = A.Widgets, A.Media, A.Palette

local C = {}
A.OptionsControls = C

C.COL_GAP = 36
C.GAP = 18
C.HEAD_GAP = 14
C.SECTION_GAP = 26

-- The node glass of the handoff (rgba(14,11,32,.9) on Midnight): the idle fill
-- of every diamond and swatch in the window, as on the trunks. Read through to
-- the live skin's nodeFill, so every use follows a skin change (Joe).
C.NODE_FILL = setmetatable({}, { __index = function(_, k) return Palette.c.nodeFill[k] end })

local TOGGLE, THUMB, SEG = 22, 13, 15
-- A desc longer than this goes in a tooltip rather than under the label: the
-- handoff's help line is one line.
local HELP_MAX = 80
-- Pressed once, a confirm button waits this long for the second press.
local CONFIRM_WAIT = 4
-- While a slider is dragged, its value is written at most this often.
local DRAG_WRITE = 0.15

-- ---------------------------------------------------------------------------
-- the tree
-- ---------------------------------------------------------------------------

local function Call(v, node)
	if type(v) == "function" then return v(C.Info(node)) end
	return v
end

function C.Info(node)
	return { type = node.type, arg = node.arg, option = node }
end

function C.Name(node)
	return tostring(Call(node.name, node) or "")
end

function C.Desc(node)
	local d = Call(node.desc, node)
	return d and tostring(d) or nil
end

function C.Hidden(node) return Call(node.hidden, node) and true or false end
function C.Disabled(node) return Call(node.disabled, node) and true or false end

function C.Value(node)
	if not node.get then return nil end
	return node.get(C.Info(node))
end

--- Write a leaf, then tell whoever is listening (the window, which repaints
--  the page: a name or a disabled state may follow from it).
function C.Write(node, ...)
	if node.set then node.set(C.Info(node), ...) end
	if C.onChange then C.onChange(node) end
end

--- A group's children, in order, without the hidden ones.
function C.Children(group)
	local list = {}
	for key, child in pairs(group and group.args or {}) do
		if type(child) == "table" and not C.Hidden(child) then
			list[#list + 1] = { key = key, node = child }
		end
	end
	table.sort(list, function(a, b)
		local oa, ob = a.node.order or 100, b.node.order or 100
		if oa ~= ob then return oa < ob end
		return a.key < b.key
	end)
	return list
end

--- The groups under a group that are pages of their own (the bars).
function C.Subs(group)
	local out = {}
	for _, e in ipairs(C.Children(group)) do
		if e.node.type == "group" and not e.node.inline then out[#out + 1] = e end
	end
	return out
end

local SETTING = { toggle = true, range = true, select = true, color = true,
	execute = true, input = true }

--- Every setting a group draws, inline groups included and its own sub-pages
--  not: what the hover card counts and the search looks through.
function C.Leaves(group, out)
	out = out or {}
	for _, e in ipairs(C.Children(group)) do
		local n = e.node
		if n.type == "group" then
			if n.inline then C.Leaves(n, out) end
		elseif SETTING[n.type] then
			out[#out + 1] = n
		end
	end
	return out
end

--- The page body as sections: a heading (or none, for what comes before the
--  first one) and the leaves under it.
function C.Sections(group)
	local sections, cur = {}, nil
	local function open(title, hint)
		cur = { title = title, hint = hint, items = {} }
		sections[#sections + 1] = cur
	end
	local function walk(g)
		for _, e in ipairs(C.Children(g)) do
			local n = e.node
			if n.type == "header" then
				open(C.Name(n))
			elseif n.type == "group" then
				if n.inline then
					open(C.Name(n), n.hint)
					walk(n)
					cur = nil
				end
			else
				if not cur then open(nil) end
				cur.items[#cur.items + 1] = n
			end
		end
	end
	walk(group)
	local kept = {}
	for _, s in ipairs(sections) do
		if #s.items > 0 then kept[#kept + 1] = s end
	end
	return kept
end

--- A select's choices as { key, label }: the palette's order for the skins,
--  otherwise by label.
function C.Choices(node)
	local values = Call(node.values, node) or {}
	local list = {}
	if node.control == "swatches" then
		local seen = {}
		for _, key in ipairs(Palette.order or {}) do
			if values[key] then
				list[#list + 1] = { key = key, label = tostring(values[key]) }
				seen[key] = true
			end
		end
		local rest = {}
		for key, label in pairs(values) do
			if not seen[key] then rest[#rest + 1] = { key = key, label = tostring(label) } end
		end
		table.sort(rest, function(a, b) return a.label < b.label end)
		for _, e in ipairs(rest) do list[#list + 1] = e end
		return list
	end
	for key, label in pairs(values) do list[#list + 1] = { key = key, label = tostring(label) } end
	table.sort(list, function(a, b) return a.label < b.label end)
	return list
end

--- A range's value as it reads beside its label.
function C.Format(node, v)
	if type(v) ~= "number" then return "" end
	if node.isPercent then return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
	if (node.step or 1) >= 1 then return ("%d"):format(math.floor(v + 0.5)) end
	return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
end

--- Snapped to the range's step and inside its ends.
function C.Snap(node, v)
	local lo, hi, step = node.min or 0, node.max or 1, node.step or 0
	if step > 0 then v = lo + math.floor((v - lo) / step + 0.5) * step end
	if v < lo then v = lo elseif v > hi then v = hi end
	return tonumber(("%.4f"):format(v))
end

-- ---------------------------------------------------------------------------
-- painting
-- ---------------------------------------------------------------------------

local function Diamond(parent, size, layer)
	local d = {}
	d.glow = parent:CreateTexture(nil, "BACKGROUND")
	d.glow:SetTexture(Media.texture.glow)
	d.glow:SetSize(size * 2.2, size * 2.2)
	d.fill = parent:CreateTexture(nil, layer or "ARTWORK")
	d.fill:SetTexture(Media.texture.diamond)
	d.fill:SetSize(size, size)
	d.rim = parent:CreateTexture(nil, layer or "ARTWORK", nil, 1)
	d.rim:SetTexture(Media.texture.diamondRim)
	d.rim:SetAllPoints(d.fill)
	d.glow:SetPoint("CENTER", d.fill, "CENTER")
	return d
end
C.Diamond = Diamond

--- On: accent with a glow. Off: node glass with a rim at `rim` (45 %).
local function PaintDiamond(d, on, rim)
	local a = Palette.c.accent
	if on then
		W.Tint(d.fill, a, 1)
		W.Tint(d.rim, a, 1)
		W.Tint(d.glow, a, 0.7)
		d.glow:Show()
	else
		W.Tint(d.fill, C.NODE_FILL, 0.9)
		W.Tint(d.rim, a, rim or 0.45)
		d.glow:Hide()
	end
end
C.PaintDiamond = PaintDiamond

local function Strand(parent, alpha, thick)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetTexture(Media.texture.flat)
	t:SetHeight(thick or 1)
	t.__alpha = alpha
	return t
end

local function PaintStrand(t, alpha)
	local a = Palette.c.accent
	t:SetVertexColor(a[1], a[2], a[3], alpha or t.__alpha or 0.3)
end

-- ---------------------------------------------------------------------------
-- rows
-- ---------------------------------------------------------------------------

local Row = {}

--- The hit wash a search lands on: a soft accent behind the whole row.
local function Hit(r)
	r.hit = r:CreateTexture(nil, "BACKGROUND", nil, -2)
	r.hit:SetTexture(Media.texture.flat)
	r.hit:SetPoint("TOPLEFT", r, "TOPLEFT", -8, 6)
	r.hit:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 8, -6)
	r.hit:SetAlpha(0)
end

local function Tip(r, node, always)
	r:SetScript("OnEnter", function(self)
		local d = C.Desc(node)
		if d and (always or #d > HELP_MAX) then W.Tooltip(self, "ANCHOR_RIGHT", C.Name(node), d) end
		if self.OnHover then self:OnHover(true) end
	end)
	r:SetScript("OnLeave", function(self)
		W.HideTooltip()
		if self.OnHover then self:OnHover(false) end
	end)
end

local function Base(parent, node, w, kind)
	local r = CreateFrame(kind or "Frame", nil, parent)
	r:SetWidth(w)
	r.node = node
	for k, v in pairs(Row) do r[k] = v end
	Hit(r)
	return r
end

function Row:Live()
	local off = C.Disabled(self.node)
	self:SetAlpha(off and 0.4 or 1)
	self.disabled = off
	return not off
end

-- toggle ------------------------------------------------------------------

local function ToggleRow(parent, node, w)
	local r = Base(parent, node, w, "Button")
	r.d = Diamond(r, TOGGLE)
	r.d.fill:SetPoint("LEFT", r, "LEFT", 0, 0)
	r.label = W.Text(r, "opControl", "LEFT")
	r.label:SetPoint("LEFT", r, "LEFT", TOGGLE + 12, 0)
	r.label:SetPoint("RIGHT", r, "RIGHT", -44, 0)
	r.label:SetWordWrap(false)
	r.state = W.Text(r, "opTag", "RIGHT")
	r.state:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	local d = C.Desc(node)
	if d and #d <= HELP_MAX then
		r.help = W.Text(r, "opHelp", "LEFT")
		r.help:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3)
		r.help:SetPoint("RIGHT", r, "RIGHT", -44, 0)
		r.help:SetWordWrap(false)
		r:SetHeight(36)
		r.label:ClearAllPoints()
		r.label:SetPoint("TOPLEFT", r, "TOPLEFT", TOGGLE + 12, -2)
		r.label:SetPoint("RIGHT", r, "RIGHT", -44, 0)
	else
		r:SetHeight(TOGGLE)
	end
	r:SetScript("OnClick", function(self)
		if self.disabled then return end
		C.Write(node, not C.Value(node))
	end)
	Tip(r, node)
	function r:Refresh()
		self:Live()
		local c = Palette.c
		local on = C.Value(node) and true or false
		self.label:SetText(C.Name(node))
		W.Color(self.label, c.text)
		if self.help then
			self.help:SetText(C.Desc(node) or "")
			W.Color(self.help, c.textDim)
		end
		PaintDiamond(self.d, on)
		self.state:SetText((on and L.common.on or L.common.off):upper())
		local a = c.accent
		W.Color(self.state, on and a or { a[1], a[2], a[3], 0.4 })
		self.on = on
	end
	return r
end

-- range -------------------------------------------------------------------

local function RangeRow(parent, node, w)
	local r = Base(parent, node, w)
	r:SetHeight(40)
	r.label = W.Text(r, "opControl", "LEFT")
	r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.label:SetPoint("RIGHT", r, "RIGHT", -70, 0)
	r.label:SetWordWrap(false)
	r.value = W.Text(r, "opControl", "RIGHT")
	r.value:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)

	local track = CreateFrame("Button", nil, r)
	track:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
	track:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
	track:SetHeight(18)
	r.track = track
	r.line = Strand(track, 0.3, 1.5)
	r.line:SetPoint("LEFT", track, "LEFT", 0, 0)
	r.line:SetPoint("RIGHT", track, "RIGHT", 0, 0)
	r.filled = Strand(track, 1, 1.5)
	r.filled:SetPoint("LEFT", track, "LEFT", 0, 0)
	r.d = Diamond(track, THUMB, "OVERLAY")

	--- Where along the strand `v` sits, 0 to 1.
	function r:Fraction(v)
		local lo, hi = node.min or 0, node.max or 1
		if hi <= lo then return 0 end
		return math.max(0, math.min(1, ((v or lo) - lo) / (hi - lo)))
	end

	--- The value under the cursor.
	function r:AtCursor()
		local x = GetCursorPosition() / (track:GetEffectiveScale() or 1)
		local left, width = track:GetLeft() or 0, track:GetWidth() or 1
		local f = width > 0 and (x - left) / width or 0
		f = math.max(0, math.min(1, f))
		return C.Snap(node, (node.min or 0) + f * ((node.max or 1) - (node.min or 0)))
	end

	function r:Show_(v)
		local f = self:Fraction(v)
		local width = track:GetWidth() or 0
		self.filled:SetWidth(math.max(0.01, width * f))
		self.d.fill:ClearAllPoints()
		self.d.fill:SetPoint("CENTER", track, "LEFT", width * f, 0)
		self.value:SetText(C.Format(node, v))
	end

	--- One step left or right (the window's arrow keys, over a hovered slider).
	function r:Step(dir)
		if self.disabled then return end
		local step = node.step or ((node.max or 1) - (node.min or 0)) / 20
		C.Write(node, C.Snap(node, (C.Value(node) or node.min or 0) + dir * step))
	end

	local function stop(self)
		if not r.dragging then return end
		r.dragging = nil
		track:SetScript("OnUpdate", nil)
		local v = r:AtCursor()
		if v ~= C.Value(node) then C.Write(node, v) else r:Refresh() end
	end
	track:SetScript("OnMouseDown", function()
		if r.disabled then return end
		r.dragging, r.since = true, 0
		r:Show_(r:AtCursor())
		track:SetScript("OnUpdate", function(_, dt)
			r.since = (r.since or 0) + (dt or 0)
			local v = r:AtCursor()
			r:Show_(v)
			if r.since >= DRAG_WRITE and v ~= C.Value(node) then
				r.since = 0
				C.Write(node, v)
			end
		end)
	end)
	track:SetScript("OnMouseUp", stop)
	track:SetScript("OnHide", stop)
	track:SetScript("OnEnter", function() r.hovered = true; if r.OnHover then r:OnHover(true) end end)
	track:SetScript("OnLeave", function() r.hovered = nil; if r.OnHover then r:OnHover(false) end end)
	Tip(r, node, true)
	r:EnableMouse(true)

	function r:Refresh()
		self:Live()
		local c = Palette.c
		self.label:SetText(C.Name(node))
		W.Color(self.label, c.text)
		W.Color(self.value, c.textDim)
		PaintStrand(self.line, 0.3)
		PaintStrand(self.filled, 1)
		PaintDiamond(self.d, true)
		if not self.dragging then self:Show_(C.Value(node)) end
	end
	r:SetScript("OnSizeChanged", function(self) if not self.dragging then self:Show_(C.Value(node)) end end)
	return r
end

-- select: nodes on a strand ------------------------------------------------

local function SegmentRow(parent, node, w, choices)
	local r = Base(parent, node, w)
	r:SetHeight(54)
	r.label = W.Text(r, "opControl", "LEFT")
	r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	local span = math.min(w, 120 * #choices)
	r.line = Strand(r, 0.3, 1)
	r.line:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -28)
	r.line:SetWidth(span - 16)
	r.opts = {}
	for i, ch in ipairs(choices) do
		local b = CreateFrame("Button", nil, r)
		b:SetSize(math.max(40, span / #choices), 34)
		local x = #choices > 1 and (8 + (i - 1) * (span - 16) / (#choices - 1)) or span / 2
		b:SetPoint("TOP", r, "TOPLEFT", x, -20)
		b.d = Diamond(b, SEG)
		b.d.fill:SetPoint("TOP", b, "TOP", 0, -1)
		b.text = W.Text(b, "opHelp", "CENTER")
		b.text:SetPoint("TOP", b.d.fill, "BOTTOM", 0, -6)
		b.key = ch.key
		b.text:SetText(ch.label)
		b:SetScript("OnClick", function()
			if r.disabled then return end
			C.Write(node, ch.key)
		end)
		r.opts[i] = b
	end
	Tip(r, node, true)
	r:EnableMouse(true)
	function r:Refresh()
		self:Live()
		local c = Palette.c
		self.label:SetText(C.Name(node))
		W.Color(self.label, c.text)
		PaintStrand(self.line, 0.3)
		local v = C.Value(node)
		for _, b in ipairs(self.opts) do
			local on = (b.key == v)
			PaintDiamond(b.d, on, 0.5)
			W.Restyle(b.text, on and "opHelpOn" or "opHelp")
			W.Color(b.text, on and c.text or c.textDim)
			b.on = on
		end
	end
	return r
end

-- select: the skins as chips, a labelled row per family ---------------------

local CHIP = 46
local CHIP_STEP = CHIP + 22
-- A family's row: its spaced name over a hairline, then its chips and their
-- names under them.
local FAMILY_HEAD = 14
local FAMILY_ROW = FAMILY_HEAD + 6 + CHIP + 22

-- Spelled out so the harness can see every one is used.
local FAMILY_NAME = {
	sky     = L.options.general.skin.sky,
	gem     = L.options.general.skin.gem,
	seasons = L.options.general.skin.seasons,
}

--- A skin chip's own look: its glass, nearly solid, its rim, its diamond.
--
--  THE TILE IS THE SKIN'S, not the live one's: the point is to show what
--  picking it would give. Its glass is raised to .88 (skins v2) so a Seasons
--  tile reads as the colour it is, and a gem's diamond glows where the other
--  two families' do not - the picker itself says which family is loud.
local function PaintChip(b, skin, on)
	local g, e, a = skin.nodeFill, skin.glassEdge, skin.accent
	b:SetFillColor({ g[1], g[2], g[3], 0.88 })
	b:SetEdgeColor(on and { a[1], a[2], a[3], 1 } or { e[1], e[2], e[3], 0.5 })
	b.dot:SetVertexColor(a[1], a[2], a[3], 1)
	if skin.family == "gem" then
		b.glow:SetVertexColor(a[1], a[2], a[3], 0.7)
		b.glow:Show()
	else
		b.glow:Hide()
	end
end
C.PaintChip = PaintChip

local function SwatchRow(parent, node, w, choices)
	local r = Base(parent, node, w)
	r.label = W.Text(r, "opControl", "LEFT")
	r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.chips, r.families = {}, {}

	-- Which row each chip goes in, from the palette's own families. A key the
	-- palette does not group goes in a last row of its own rather than nowhere.
	local rowOf, rows = {}, {}
	for i, fam in ipairs(Palette.families or {}) do
		for _, key in ipairs(fam.skins) do rowOf[key] = i end
		rows[i] = { key = fam.key, n = 0 }
	end
	for i, ch in ipairs(choices) do
		local at = rowOf[ch.key]
		if not at then
			at = #rows + 1
			rows[at] = { n = 0 }
			rowOf[ch.key] = at
		end
		local row = rows[at]
		row.used = true
		local top = -22 - (at - 1) * FAMILY_ROW
		local b = A.Glass.CreatePanel(r, { frameType = "Button", corner = 12 })
		b:SetSize(CHIP, CHIP)
		b:SetPoint("TOPLEFT", r, "TOPLEFT", row.n * CHIP_STEP, top - FAMILY_HEAD - 6)
		row.n = row.n + 1
		b.glow = b:CreateTexture(nil, "ARTWORK")
		b.glow:SetTexture(Media.texture.glow)
		b.glow:SetSize(34, 34)
		b.glow:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.glow:SetBlendMode("ADD")
		b.glow:Hide()
		b.dot = b:CreateTexture(nil, "OVERLAY")
		b.dot:SetTexture(Media.texture.diamond)
		b.dot:SetSize(16, 16)
		b.dot:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.text = W.Text(b, "opHelp", "CENTER")
		b.text:SetPoint("TOP", b, "BOTTOM", 0, -6)
		b.text:SetText(ch.label)
		b.key = ch.key
		b:SetScript("OnClick", function()
			if r.disabled then return end
			C.Write(node, ch.key)
		end)
		r.chips[i] = b
	end

	-- The heads: S K Y over a hairline that runs to the end of the row.
	local used = 0
	for i, row in ipairs(rows) do
		if row.used then
			used = i
			local top = -22 - (i - 1) * FAMILY_ROW
			local h = W.Text(r, "opSub", "LEFT")
			h:SetPoint("TOPLEFT", r, "TOPLEFT", 0, top)
			h:SetText(A.Trunk.Spaced(FAMILY_NAME[row.key] or ""))
			local line = Strand(r, 0.22)
			line:SetPoint("LEFT", h, "RIGHT", 8, 0)
			line:SetPoint("RIGHT", r, "RIGHT", 0, 0)
			r.families[#r.families + 1] = { key = row.key, label = h, line = line }
		end
	end
	r:SetHeight(22 + used * FAMILY_ROW)

	Tip(r, node, true)
	r:EnableMouse(true)
	function r:Refresh()
		self:Live()
		local c = Palette.c
		self.label:SetText(C.Name(node))
		W.Color(self.label, c.text)
		for _, fam in ipairs(self.families) do
			W.Color(fam.label, c.textDim)
			PaintStrand(fam.line)
		end
		local v = C.Value(node)
		for _, b in ipairs(self.chips) do
			local skin = Palette.skins and Palette.skins[b.key]
			local on = (b.key == v)
			if skin then PaintChip(b, skin, on) end
			W.Restyle(b.text, on and "opHelpOn" or "opHelp")
			W.Color(b.text, on and c.text or c.textDim)
			b.on = on
		end
	end
	return r
end

-- select: a dropdown for a long list --------------------------------------

local FIELD_W, FIELD_H = 260, 28

local function Field(r, w)
	local f = A.Glass.CreatePanel(r, { frameType = "Button", corner = 14 })
	f:SetSize(math.min(w, FIELD_W), FIELD_H)
	f:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -22)
	return f
end

local function PaintField(f)
	local c = Palette.c
	f:SetFillColor({ 1, 1, 1, 0.05 })
	f:SetEdgeColor({ c.accent[1], c.accent[2], c.accent[3], 0.25 })
end

local function DropdownRow(parent, node, w)
	local r = Base(parent, node, w)
	r:SetHeight(22 + FIELD_H)
	r.label = W.Text(r, "opControl", "LEFT")
	r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.field = Field(r, w)
	r.text = W.Text(r.field, "opControl", "LEFT")
	r.text:SetPoint("LEFT", r.field, "LEFT", 14, 0)
	r.text:SetPoint("RIGHT", r.field, "RIGHT", -28, 0)
	r.text:SetWordWrap(false)
	r.caret = r.field:CreateTexture(nil, "OVERLAY")
	r.caret:SetTexture(Media.texture.diamond)
	r.caret:SetSize(7, 7)
	r.caret:SetPoint("RIGHT", r.field, "RIGHT", -14, 0)
	r.field:SetScript("OnClick", function(self)
		if r.disabled then return end
		local entries = {}
		for _, ch in ipairs(C.Choices(node)) do
			entries[#entries + 1] = { text = ch.label, action = function() C.Write(node, ch.key) end }
		end
		W.Menu(self, entries, { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -4 })
	end)
	Tip(r, node, true)
	r:EnableMouse(true)
	function r:Refresh()
		self:Live()
		local c = Palette.c
		self.label:SetText(C.Name(node))
		W.Color(self.label, c.text)
		PaintField(self.field)
		local v, shown = C.Value(node), nil
		for _, ch in ipairs(C.Choices(node)) do
			if ch.key == v then shown = ch.label end
		end
		self.text:SetText(shown or "")
		W.Color(self.text, shown and c.text or c.textDim)
		W.Tint(self.caret, c.accent, 0.8)
	end
	return r
end

-- color -------------------------------------------------------------------

local function OpenPicker(node)
	local P = _G.ColorPickerFrame
	if not P then return false end
	local r, g, b, a = C.Value(node)
	local function now()
		local nr, ng, nb = P:GetColorRGB()
		local na = 1
		if node.hasAlpha then
			if P.GetColorAlpha then na = P:GetColorAlpha()
			elseif _G.OpacitySliderFrame then na = 1 - _G.OpacitySliderFrame:GetValue() end
		end
		C.Write(node, nr, ng, nb, na)
	end
	local function cancel() C.Write(node, r, g, b, a) end
	if P.SetFrameStrata then P:SetFrameStrata("FULLSCREEN_DIALOG") end
	if P.SetupColorPickerAndShow then
		P:SetupColorPickerAndShow({
			r = r, g = g, b = b, opacity = a, hasOpacity = node.hasAlpha,
			swatchFunc = now, opacityFunc = now, cancelFunc = cancel,
		})
	else
		P.func, P.opacityFunc, P.cancelFunc = now, now, cancel
		P.hasOpacity, P.opacity = node.hasAlpha, 1 - (a or 1)
		P.previousValues = { r, g, b, a }
		P:SetColorRGB(r, g, b)
		P:Hide()
		P:Show()
	end
	return true
end
C.OpenPicker = OpenPicker

local function ColorRow(parent, node, w)
	local r = Base(parent, node, w, "Button")
	r:SetHeight(22)
	r.swatch = r:CreateTexture(nil, "ARTWORK")
	r.swatch:SetTexture(Media.texture.chipDisc)
	r.swatch:SetSize(20, 20)
	r.swatch:SetPoint("LEFT", r, "LEFT", 1, 0)
	r.ring = r:CreateTexture(nil, "ARTWORK", nil, 1)
	r.ring:SetTexture(Media.texture.chipRim)
	r.ring:SetAllPoints(r.swatch)
	r.label = W.Text(r, "opControl", "LEFT")
	r.label:SetPoint("LEFT", r, "LEFT", TOGGLE + 12, 0)
	r:SetScript("OnClick", function(self)
		if self.disabled then return end
		OpenPicker(node)
	end)
	Tip(r, node, true)
	function r:Refresh()
		self:Live()
		local c = Palette.c
		self.label:SetText(C.Name(node))
		W.Color(self.label, c.text)
		local cr, cg, cb = C.Value(node)
		self.swatch:SetVertexColor(cr or 1, cg or 1, cb or 1, 1)
		W.Tint(self.ring, c.accent, 0.6)
	end
	return r
end

-- execute -----------------------------------------------------------------

local function ExecuteRow(parent, node, w)
	local r = Base(parent, node, w)
	r:SetHeight(30)
	local b = A.Glass.CreatePanel(r, { frameType = "Button", corner = 15 })
	b:SetHeight(30)
	b:SetPoint("LEFT", r, "LEFT", 0, 0)
	b.text = W.Text(b, "opButton", "CENTER")
	b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
	r.button = b
	b:SetScript("OnClick", function()
		if r.disabled then return end
		if node.confirm and not (r.armed and GetTime() - r.armed < CONFIRM_WAIT) then
			r.armed = GetTime()
			r:Refresh()
			return
		end
		r.armed = nil
		if node.func then node.func(C.Info(node)) end
		if C.onChange then C.onChange(node) end
	end)
	b:SetScript("OnEnter", function(self)
		self.over = true
		r:Refresh()
		local d = C.Desc(node)
		if d then W.Tooltip(self, "ANCHOR_RIGHT", C.Name(node), d) end
	end)
	b:SetScript("OnLeave", function(self)
		self.over = nil
		r:Refresh()
		W.HideTooltip()
	end)
	function r:Refresh()
		self:Live()
		local c = Palette.c
		local armed = node.confirm and self.armed and GetTime() - self.armed < CONFIRM_WAIT
		if not armed then self.armed = nil end
		b.text:SetText(armed and L.options.map.confirm or C.Name(node))
		b:SetWidth(math.ceil(b.text:GetStringWidth() or 60) + 36)
		local a = c.accent
		b:SetFillColor(b.over and { a[1], a[2], a[3], 0.12 } or { 1, 1, 1, 0.03 })
		b:SetEdgeColor(armed and c.danger or { a[1], a[2], a[3], 0.35 })
		W.Color(b.text, armed and c.danger or c.text)
	end
	return r
end

-- input -------------------------------------------------------------------

local function InputRow(parent, node, w)
	local r = Base(parent, node, w)
	r:SetHeight(22 + FIELD_H)
	r.label = W.Text(r, "opControl", "LEFT")
	r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.field = Field(r, w)
	local box = CreateFrame("EditBox", nil, r.field)
	box:SetPoint("LEFT", r.field, "LEFT", 14, 0)
	box:SetPoint("RIGHT", r.field, "RIGHT", -14, 0)
	box:SetHeight(FIELD_H)
	box:SetAutoFocus(false)
	Media:SetFont(box, "opControl")
	box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self)
		local text = self:GetText() or ""
		self:SetText("")
		self:ClearFocus()
		if not r.disabled and text ~= "" then C.Write(node, text) end
	end)
	r.field:SetScript("OnClick", function() box:SetFocus() end)
	r.box = box
	Tip(r, node, true)
	r:EnableMouse(true)
	function r:Refresh()
		self:Live()
		local c = Palette.c
		self.label:SetText(C.Name(node))
		W.Color(self.label, c.text)
		PaintField(self.field)
		W.Color(box, c.text)
	end
	return r
end

-- description -------------------------------------------------------------

local function NoteRow(parent, node, w)
	local r = Base(parent, node, w)
	r.text = W.Text(r, "opNote", "LEFT")
	r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.text:SetWidth(w)
	r.text:SetJustifyV("TOP")
	function r:Refresh()
		self.text:SetText(C.Name(node))
		W.Color(self.text, Palette.c.textDim)
		self:SetHeight(math.ceil(self.text:GetStringHeight() or 14))
	end
	r:Refresh()
	return r
end

--- The control for one leaf, `w` wide. Nil for a leaf this window does not
--  draw.
function C.Row(parent, node, w)
	local t = node.type
	if t == "toggle" then return ToggleRow(parent, node, w) end
	if t == "range" then return RangeRow(parent, node, w) end
	if t == "color" then return ColorRow(parent, node, w) end
	if t == "execute" then return ExecuteRow(parent, node, w) end
	if t == "input" then return InputRow(parent, node, w) end
	if t == "description" then return NoteRow(parent, node, w) end
	if t == "select" then
		local choices = C.Choices(node)
		if node.control == "swatches" then return SwatchRow(parent, node, w, choices) end
		local short = #choices >= 2 and #choices <= 4
		for _, ch in ipairs(choices) do
			if #ch.label > 18 then short = false end
		end
		if short then return SegmentRow(parent, node, w, choices) end
		return DropdownRow(parent, node, w)
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- a page body
-- ---------------------------------------------------------------------------

--- Draw `group` into `host`, `width` wide in two columns. Returns the view:
--  its frame, its height, its rows (row.node is the leaf) and Refresh.
function C.View(host, group, width)
	local view = { rows = {}, heads = {} }
	local f = CreateFrame("Frame", nil, host)
	f:SetWidth(width)
	view.frame = f
	-- Two columns, or one where the page reads down (What's new).
	local one = group.columns == 1
	local colW = one and width or math.floor((width - C.COL_GAP) / 2)
	view.colW = colW

	local cols = { 0, 0 }
	for _, s in ipairs(C.Sections(group)) do
		-- Built first and measured, then dealt to the shorter column.
		local parts, h = {}, 0
		if s.title then
			local head = A.Trunk.Head(f)
			head:SetWidth(colW)
			head:Set(s.title, s.hint or "")
			parts[#parts + 1] = { frame = head, h = 14, gap = C.HEAD_GAP }
			view.heads[#view.heads + 1] = head
		end
		for _, n in ipairs(s.items) do
			local row = C.Row(f, n, colW)
			if row then
				row:Refresh()
				parts[#parts + 1] = { frame = row, h = row:GetHeight() or 20, gap = C.GAP }
				view.rows[#view.rows + 1] = row
			end
		end
		for i, p in ipairs(parts) do h = h + p.h + (i < #parts and p.gap or 0) end
		local col = (not one and cols[2] < cols[1]) and 2 or 1
		local y = cols[col] > 0 and (cols[col] + C.SECTION_GAP) or 0
		local x = (col - 1) * (colW + C.COL_GAP)
		for _, p in ipairs(parts) do
			p.frame:ClearAllPoints()
			p.frame:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
			y = y + p.h + p.gap
		end
		cols[col] = y - (#parts > 0 and parts[#parts].gap or 0)
	end
	view.height = math.max(cols[1], cols[2])
	f:SetHeight(math.max(1, view.height))

	function view:Refresh()
		for _, row in ipairs(self.rows) do row:Refresh() end
		for _, head in ipairs(self.heads) do head:Paint() end
	end

	--- The row drawing `node`, for the search's landing.
	function view:RowFor(node)
		for _, row in ipairs(self.rows) do
			if row.node == node then return row end
		end
	end
	return view
end
