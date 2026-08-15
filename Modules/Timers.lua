--[[--------------------------------------------------------------------------
	AetherUI :: Timers

	The client's mirror timers - the bar that counts your breath down underwater,
	your fatigue out at sea, and the seconds you have left feigning death.

	A RESKIN, like the dialogs and the windows. The client owns these entirely:
	it decides when one appears, which of its three frames is free to use, and
	how far along the bar has run, all from an OnUpdate reading
	GetMirrorTimerProgress. Nothing here shows one, hides one or moves one. The
	stone comes off, glass goes behind, the fill is ours and the word on it is
	in our lettering.

	WHICH TIMER IT IS, IN THE COLOUR. Blizzard says breath in blue, fatigue in
	yellow and death in orange, and that is worth keeping - the colour is how
	you know which bar has appeared before you have read the word. The hues are
	ours rather than its, the way the talent tree's rims are: same meaning, this
	interface's palette.

	And it has to be re-applied. MirrorTimer_Show sets the bar's colour from
	MirrorTimerColors every single time a timer starts, so a colour set once at
	login is a colour you see until the first time you go underwater.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local TM = A:NewModule("timers")

local W, Palette, Reskin = A.Widgets, A.Palette, A.Reskin

-- Three, fixed by the client. MIRRORTIMER_NUMTIMERS is its own name for it and
-- is read where it exists, because a flavour that ships four should get four.
local function NumTimers() return _G.MIRRORTIMER_NUMTIMERS or 3 end

local function cfg() return A.Config:Module("timers") end

-- The cast bar's proportions, which is what this is: a capsule with a word on
-- the left and a fill running out beside it. Ours is 44 tall with a 7px bar in
-- it; the client's frame is 26, so the bar keeps its height and the capsule
-- takes the frame's.
local BAR_H  = 7
local PAD_X  = 12       -- from the ends of the capsule
local GAP    = 10       -- between the word and the fill

-- What each timer means, in our colours rather than Blizzard's.
--
-- Its own table rather than a re-tint of MirrorTimerColors: that one is a
-- global any addon may write to, and reading it would make our palette depend
-- on whatever else is loaded. The KEYS are the client's, because they are what
-- the timer is called.
--
-- POWER rather than CAST for breath. Both are blue and the cast blue is the
-- paler of the two, which over bright water came back reading as a white bar
-- with a grey end. Breath is a pool running out, which is what `power` is for.
local function TimerColor(kind)
	local c = Palette.c
	if kind == "BREATH" then return c.power[1] end
	if kind == "EXHAUSTION" then return c.energy[1] end
	if kind == "DEATH" or kind == "FEIGNDEATH" then return c.focus[1] end
	return c.accent
end

-- ---------------------------------------------------------------------------
-- dressing
-- ---------------------------------------------------------------------------

--- Paint one timer's fill for the kind of timer it is.
--
--  Split out because it runs twice: once when the frame is dressed, and again
--  every time the client starts a timer on it and re-colours the bar itself.
local function Recolor(frame)
	local name = frame.GetName and frame:GetName()
	local bar = name and _G[name .. "StatusBar"]
	if not bar or not bar.GetStatusBarTexture then return end

	local fill = bar:GetStatusBarTexture()
	if not fill or not fill.SetVertexColor then return end

	local c = TimerColor(frame.timer)
	fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

TM.Recolor = Recolor

local function Dress(frame)
	if not frame or not frame.GetRegions then return end

	local store = frame.__aetherArt
	if not store then
		store = {}
		frame.__aetherArt = store
	end

	-- The stone: a casting-bar border laid over the top, and a flat black plate
	-- behind the fill. Both are regions of the frame itself.
	Reskin.Strip(frame, store)

	if frame.SetScale then frame:SetScale(A.db.profile.scale) end

	local name = frame.GetName and frame:GetName()
	local bar  = name and _G[name .. "StatusBar"]
	local text = name and _G[name .. "Text"]

	-- THE CAPSULE IS THE FRAME. Behind the bar alone it was a sliver two
	-- pixels taller than the fill, which is not a capsule - it is a rim.
	local pill = frame.__aetherPill
	if not pill then
		pill = A.Glass.CreatePill(frame, {
			fill   = "glassStrong",
			edge   = "castEdge",
			shadow = A.db.profile.glass.shadow,
		})
		pill:SetAllPoints(frame)
		pill:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
		frame.__aetherPill = pill
	end

	-- The word first, on the left, because the fill is anchored to its right
	-- edge and has to know where that is. "Feign Death" is half again the width
	-- of "Breath", so the fill gives way rather than the word being clipped.
	if text and text.SetText then
		W.Restyle(text, "castName")
		W.Color(text, Palette.c.text)

		if text.ClearAllPoints then
			text:ClearAllPoints()
			text:SetPoint("LEFT", frame, "LEFT", PAD_X, 0)
		end
		if text.SetJustifyH then text:SetJustifyH("LEFT") end
		frame.__aetherText = text
	end

	if bar then
		Reskin.StatusBar(bar, store)

		-- ABOVE THE GLASS. The template lowers this bar's frame level in its
		-- own OnLoad - LowerFrameLevel(self) - so a capsule put behind the
		-- frame is drawn over the top of the fill, which is the bar coming back
		-- as a pale block with a grey end and no capsule anywhere.
		bar:SetFrameLevel(pill:GetFrameLevel() + 1)

		bar:ClearAllPoints()
		bar:SetHeight(BAR_H)
		if text then
			bar:SetPoint("LEFT", text, "RIGHT", GAP, 0)
		else
			bar:SetPoint("LEFT", frame, "LEFT", PAD_X, 0)
		end
		bar:SetPoint("RIGHT", frame, "RIGHT", -PAD_X, 0)

		Recolor(frame)
	end

	return true
end

TM.Dress = Dress

--- Answer the client when it starts a timer.
--
--  MirrorTimer_Show picks whichever of the three frames is free, sets the bar's
--  colour from MirrorTimerColors and shows it. So the frame that appears is not
--  necessarily one that was on screen a moment ago, and its colour is Blizzard's
--  again whatever we did at login. Hooked by name: this one IS a global.
local function InstallHooks()
	if TM.__hooked or not hooksecurefunc or not _G.MirrorTimer_Show then return end
	TM.__hooked = true

	hooksecurefunc("MirrorTimer_Show", function()
		if not TM.enabled then return end
		TM:Skin()
	end)
end

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

function TM:Skin()
	for i = 1, NumTimers() do
		local frame = _G["MirrorTimer" .. i]
		if frame then Dress(frame) end
	end
	InstallHooks()
end

function TM:OnEnable()
	self:Skin()
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() TM:Skin() end)
end

function TM:OnDisable()
	A:UnregisterAllEvents(self)

	for i = 1, NumTimers() do
		local frame = _G["MirrorTimer" .. i]
		if frame and frame.__aetherArt then
			Reskin.Restore(frame.__aetherArt)
			frame.__aetherArt = nil

			if frame.__aetherPill then
				frame.__aetherPill:Hide()
				frame.__aetherPill = nil
			end
			if frame.SetScale then frame:SetScale(1) end
		end
	end
end

function TM:OnSkinChanged()
	for i = 1, NumTimers() do
		local frame = _G["MirrorTimer" .. i]
		if frame and frame.__aetherPill then
			frame.__aetherPill:ApplySkin("glassStrong", "castEdge")
			Recolor(frame)
			if frame.__aetherText then W.Color(frame.__aetherText, Palette.c.text) end
		end
	end
end

function TM:OnConfigChanged() self:Skin() end
