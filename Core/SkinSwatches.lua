--[[--------------------------------------------------------------------------
	AetherUI :: Skin swatches

	The skin picker, as the brief asks for it: four chips, each showing its own
	accent on its own glass. Not four screenshots, and not a dropdown reading
	"midnight / dawn / noon / dusk" - a list of words tells you the names of
	four skins and nothing about what choosing one would do.

	AN ACECONFIG SELECT, DRAWN DIFFERENTLY. This is registered as an AceGUI
	widget and named in the option's `dialogControl`, so the option itself is
	unchanged: same profile key, same get and set, same restyle afterwards.
	AceConfigDialog builds a Dropdown for a `select` unless it is told
	otherwise, and it asks a control for exactly four things - SetLabel,
	SetList, SetValue and an OnValueChanged callback. Meeting those four is the
	whole integration.

	EACH CHIP WEARS ITS OWN SKIN, not the live one: the whole point is to show
	what you would be getting. So the colours come from Palette.skins[key]
	rather than from Palette.c, and a skin change does not restyle them -
	there is nothing for it to change.

	The order is the day, not the alphabet. That belongs to the palette, and it
	is read from there rather than repeated here.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Type, Version = "AetherUISkinSwatches", 1
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI then return end
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

local CHIP    = 46      -- a chip is square
local GAP     = 10
local LABEL_H = 18
local PAD_B   = 6

-- ---------------------------------------------------------------------------
-- one chip
-- ---------------------------------------------------------------------------

--- Dressed from a NAMED skin, which is the reason this exists.
--
--  Selected is the accent at full strength on the rim, unselected the skin's
--  own quiet border. Nothing else moves: a chip that changed size or lifted on
--  selection would be four chips of different sizes, and the row is meant to
--  read as a set you are comparing.
local function DressChip(chip, key, selected)
	local skin = A.Palette.skins[key]
	if not skin then return end

	chip:SetFillColor(skin.glass)
	chip:SetEdgeColor(selected
		and { skin.accent[1], skin.accent[2], skin.accent[3], 1 }
		or skin.glassEdge)

	local a = skin.accent
	chip.dot:SetVertexColor(a[1], a[2], a[3], 1)

	-- The deep accent under it, so a chip carries the PAIR a skin is actually
	-- built from rather than one colour out of six. On Midnight those two are
	-- a violet and a deeper violet; on Dusk they are the difference between
	-- brass and gold, and one dot alone cannot show it.
	local d = skin.accentDeep
	chip.dotDeep:SetVertexColor(d[1], d[2], d[3], 1)

	chip.tick:SetShown(selected and true or false)
	if selected then
		local b = skin.bright or skin.text
		chip.tick:SetVertexColor(b[1], b[2], b[3], 1)
	end
end

local function BuildChip(parent)
	local chip = A.Glass.CreatePanel(parent, { corner = 8, frameType = "Button" })
	chip:SetSize(CHIP, CHIP)
	chip:EnableMouse(true)

	-- Accent and deep accent, side by side, filling most of the chip. Two bars
	-- rather than two dots: at 46 pixels a circle small enough to sit inside
	-- the rim is too small to judge a colour by.
	chip.dot = chip:CreateTexture(nil, "ARTWORK")
	chip.dot:SetTexture(A.Media.texture.flat)
	chip.dot:SetPoint("TOPLEFT", chip, "TOPLEFT", 9, -9)
	chip.dot:SetPoint("BOTTOMRIGHT", chip, "CENTER", -1, 9)

	chip.dotDeep = chip:CreateTexture(nil, "ARTWORK")
	chip.dotDeep:SetTexture(A.Media.texture.flat)
	chip.dotDeep:SetPoint("TOPLEFT", chip, "CENTER", 1, -9)
	chip.dotDeep:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", -9, 9)

	chip.tick = chip:CreateTexture(nil, "OVERLAY")
	chip.tick:SetTexture(A.Media.texture.flat)
	chip.tick:SetHeight(A:Px(2))
	chip.tick:SetPoint("BOTTOMLEFT", chip, "BOTTOMLEFT", 9, 5)
	chip.tick:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", -9, 5)
	chip.tick:Hide()

	chip.caption = A.Widgets.Text(parent, "tiny", "CENTER")
	chip.caption:SetPoint("TOP", chip, "BOTTOM", 0, -3)

	return chip
end

-- ---------------------------------------------------------------------------
-- the widget
-- ---------------------------------------------------------------------------

--- The order the chips are offered in.
--
--  The palette's, not ours and not the alphabet's. AceConfig hands us a
--  key->label table, which has no order at all; anything it holds that the
--  palette does not name is appended sorted, so a skin added without touching
--  Palette.order still appears rather than vanishing.
local function OrderedKeys(values)
	local out, seen = {}, {}
	for _, key in ipairs(A.Palette.order or {}) do
		if values[key] then out[#out + 1] = key seen[key] = true end
	end
	local rest = {}
	for key in pairs(values) do
		if not seen[key] then rest[#rest + 1] = key end
	end
	table.sort(rest)
	for _, key in ipairs(rest) do out[#out + 1] = key end
	return out
end

local methods = {
	OnAcquire = function(self)
		self:SetLabel()
		self:SetDisabled(false)
		self.value = nil
		self.list = nil
		self:SetHeight(LABEL_H + CHIP + LABEL_H + PAD_B)
		self:SetWidth(4 * CHIP + 3 * GAP)
	end,

	OnRelease = function(self)
		for _, chip in ipairs(self.chips) do
			chip:Hide()
			chip.caption:Hide()
		end
		self.list, self.value = nil, nil
	end,

	SetLabel = function(self, text)
		self.label:SetText(text or "")
	end,

	--- AceConfigDialog hands the key->label table here.
	SetList = function(self, values)
		self.list = values or {}
		self:Refresh()
	end,

	SetValue = function(self, key)
		self.value = key
		self:Refresh()
	end,

	GetValue = function(self)
		return self.value
	end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled and true or false
		for _, chip in ipairs(self.chips) do
			chip:SetAlpha(self.disabled and 0.4 or 1)
			chip:EnableMouse(not self.disabled)
		end
	end,

	--- Lay out whatever the list currently holds.
	--
	--  Chips are BUILT ONCE and reused. AceGUI pools its widgets, so a panel
	--  opened twenty times must not leave twenty rows of chips behind on the
	--  frame - and the pool hands this same widget back, so anything built per
	--  Refresh would accumulate for the life of the session.
	Refresh = function(self)
		local keys = OrderedKeys(self.list or {})

		for i, key in ipairs(keys) do
			local chip = self.chips[i]
			if not chip then
				chip = BuildChip(self.frame)
				chip:SetScript("OnClick", function(btn)
					if self.disabled then return end
					self:Fire("OnValueChanged", btn.__skinKey)
				end)
				self.chips[i] = chip
			end

			chip.__skinKey = key
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
				(i - 1) * (CHIP + GAP), -LABEL_H)
			DressChip(chip, key, key == self.value)

			-- The written name, not the key. "Midnight" is a skin; "midnight"
			-- is a table index that happens to be readable.
			local skin = A.Palette.skins[key]
			chip.caption:SetText((skin and skin.label) or self.list[key] or key)
			A.Widgets.Color(chip.caption,
				key == self.value and A.Palette.c.text or A.Palette.c.textDim)

			chip:Show()
			chip.caption:Show()
		end

		for i = #keys + 1, #self.chips do
			self.chips[i]:Hide()
			self.chips[i].caption:Hide()
		end
	end,
}

local function Constructor()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:Hide()

	local label = A.Widgets.Text(frame, "label", "LEFT")
	label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	A.Widgets.Color(label, A.Palette.c.text)

	local widget = {
		frame = frame,
		label = label,
		chips = {},
		type  = Type,
	}
	for method, func in pairs(methods) do widget[method] = func end

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
