--[[--------------------------------------------------------------------------
	AetherUI :: XPBar

	The hairline along the very bottom of the screen from concepts 1a and 2a -
	a 4px sliver of accent colour, with "14% to Level 16" tucked into a corner.

	Small module, but it is the reason the concepts can delete Blizzard's whole
	bottom bar without losing anything: the one piece of information that bar
	actually carried is right there in the frame of the screen.

	Rested experience gets a second, dimmer fill behind the main one, in the same
	place Blizzard puts it, so the "you have rest banked" signal survives.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local XP = A:NewModule("xpbar")

local W, Media, Palette = A.Widgets, A.Media, A.Palette

local function MaxLevel()
	-- GetMaxPlayerLevel exists on modern clients; Classic Era also exposes
	-- MAX_PLAYER_LEVEL. Fall back to 60 rather than guessing wrong and hiding
	-- the bar for everyone.
	if GetMaxPlayerLevel then
		local ok, v = pcall(GetMaxPlayerLevel)
		if ok and v then return v end
	end
	return _G.MAX_PLAYER_LEVEL or 60
end

--- Which corner the readout sits in.
--
--  RE-ANCHORED RATHER THAN REBUILT, because the setting can change at any time
--  and a FontString keeps whatever anchors it was last given: setting the new
--  corner without clearing the old one leaves it spanned between the two and
--  justified to neither.
local function PlaceText(f, cfg)
	local left = (cfg.textSide == "LEFT")

	f.text:ClearAllPoints()
	if left then
		f.text:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 14, 4)
	else
		f.text:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -14, 4)
	end
	if f.text.SetJustifyH then f.text:SetJustifyH(left and "LEFT" or "RIGHT") end
end

local function Build()
	local cfg = A.Config:Module("xpbar")

	local f = CreateFrame("Frame", ADDON .. "XPBar", UIParent)
	f:SetHeight(cfg.height)
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(Media.texture.flat)
	bg:SetAllPoints(f)
	f.bg = bg

	-- Rested sits behind the fill and extends past it, exactly like Blizzard's.
	local rested = W.CreateBar(f, { rounded = false, smooth = false, bgAlpha = 0 })
	rested:SetAllPoints(f)
	f.rested = rested

	local bar = W.CreateBar(f, { rounded = false, smooth = true, bgAlpha = 0 })
	bar:SetAllPoints(f)
	f.bar = bar

	local glow = f:CreateTexture(nil, "OVERLAY")
	glow:SetTexture(Media.texture.barGlow)
	glow:SetBlendMode("ADD")
	glow:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPLEFT")
	glow:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
	f.glow = glow

	local text = W.Text(f, "xpText", "RIGHT")
	f.text = text
	PlaceText(f, cfg)

	return f
end

local function Update()
	local f = XP.frame
	if not f then return end

	local cfg = A.Config:Module("xpbar")
	local level = UnitLevel("player") or 1

	if level >= MaxLevel() then
		f:Hide()
		return
	end
	f:Show()

	local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
	if max <= 0 then max = 1 end

	local c = Palette.c
	f.bar:SetMinMaxValues(0, max)
	f.bar:SetSmoothValue(cur)
	f.bar:SetColors(c.xp)
	f.glow:SetVertexColor(c.xp[2][1], c.xp[2][2], c.xp[2][3], 0.45)

	local exhaustion = GetXPExhaustion and GetXPExhaustion()
	if exhaustion and exhaustion > 0 then
		f.rested:Show()
		f.rested:SetMinMaxValues(0, max)
		f.rested:SetValue(math.min(max, cur + exhaustion))
		f.rested:SetColors({
			{ c.xp[1][1], c.xp[1][2], c.xp[1][3], 0.35 },
			{ c.xp[2][1], c.xp[2][2], c.xp[2][3], 0.35 },
		})
	else
		f.rested:Hide()
	end

	f.bg:SetVertexColor(1, 1, 1, 0.10)

	if cfg.showText then
		-- WHAT IS LEFT, not what is done. "10% Level 11" is two facts about
		-- where you have been; "90% to Level 12" is one fact about where you are
		-- going, and it counts down, which is what anybody watching this line is
		-- actually watching.
		--
		-- Rounded UP, so it never reads 0% while there is still experience to
		-- earn - the one number a countdown must not show early.
		-- MULTIPLIED BEFORE DIVIDING, and nudged before rounding. 1400/10000*100
		-- is 14.000000000000002 in doubles, and a ceiling on that reads 15% -
		-- so the line said fifteen at exactly fourteen. Doing the multiply first
		-- keeps the whole numbers whole; the epsilon covers everything else.
		local left = math.ceil((max - cur) * 100 / max - 1e-9)
		if left < 0 then left = 0 elseif left > 100 then left = 100 end
		f.text:SetText(string.format("%d%% to Level %d", left, level + 1))
		W.Color(f.text, c.textDim)
		f.text:Show()
	else
		f.text:Hide()
	end
end

XP.Update = Update

function XP:OnEnable()
	if not self.frame then self.frame = Build() end
	self.frame:Show()

	A:RegisterEvent(self, "PLAYER_XP_UPDATE", Update)
	A:RegisterEvent(self, "PLAYER_LEVEL_UP", Update)
	A:RegisterEvent(self, "UPDATE_EXHAUSTION", Update)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", Update)

	self:OnConfigChanged()
end

function XP:OnDisable()
	if self.frame then self.frame:Hide() end
end

function XP:OnSkinChanged() Update() end

function XP:OnConfigChanged()
	local cfg = A.Config:Module("xpbar")
	if self.frame then
		self.frame:SetHeight(cfg.height)
		PlaceText(self.frame, cfg)
	end
	Update()
end
