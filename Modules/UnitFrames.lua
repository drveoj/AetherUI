--[[--------------------------------------------------------------------------
	AetherUI :: UnitFrames

	Player and target capsules plus the player cast bar, built to the geometry in
	concept 2a.

	Reading the concept as a spec:

	  player capsule   pill, 300x64, padding 9/24/9/10
	    orb            46px, class-tinted, level inside
	    name           SemiBold 15.5   +   race/class Light 12, baseline aligned
	    health         200x7
	    power          200x5
	    values         right aligned, health over power

	  target capsule   the same thing mirrored, rim tinted by reaction

	  cast bar         pill, 300 wide, icon + name + 300x7 bar + "1.4 / 2.5s"

	Sizes are the concept's own numbers. The deck was drawn at 1920x1080 with a
	1:1 UI, which is roughly a 0.71 UI scale on 1440p - i.e. these land close to
	right out of the box, and everything is in the config if they do not.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local UF = A:NewModule("unitframes")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

UF.frames = {}

-- ---------------------------------------------------------------------------
-- Blizzard frame removal
-- ---------------------------------------------------------------------------

local hider
local function GetHider()
	if not hider then
		hider = CreateFrame("Frame", ADDON .. "Hider", UIParent)
		hider:Hide()
	end
	return hider
end

local function Banish(frame)
	if not frame then return end
	if InCombatLockdown() then return end
	pcall(function()
		frame:UnregisterAllEvents()
		frame:Hide()
		frame:SetParent(GetHider())
	end)
end

function UF:HideBlizzard()
	local cfg = A.Config:Module("unitframes")
	if not cfg.hideBlizzard then return end

	Banish(_G.PlayerFrame)
	Banish(_G.TargetFrame)
	Banish(_G.TargetFrameToT)
	Banish(_G.ComboFrame)
	if cfg.showPet ~= false then Banish(_G.PetFrame) end

	if cfg.showCastBar then
		Banish(_G.CastingBarFrame)
		Banish(_G.PlayerCastingBarFrame)
	end
end

-- ---------------------------------------------------------------------------
-- capsule construction
-- ---------------------------------------------------------------------------

--- Narrowest capsule that still fits orb + bars + readout without collisions.
--  Mirrors the anchor chain in BuildCapsule; keep the two in step.
local function MinWidth(cfg)
	return 10 + cfg.orbSize + 13 + cfg.barWidth + 12 + 40 + 24
end


--- mirror = true builds the target variant: orb on the right, text right-aligned.
local function BuildCapsule(unit, mirror)
	local cfg = A.Config:Module("unitframes")

	-- The capsule is two frames.
	--
	--   f      the layout core. Plain Frame, never protected. Movers, the fader
	--          and the aura trays attach here, and every child anchors to it.
	--   glass  the visible capsule, filling the core exactly.
	--
	-- The capsule's height is now fixed: auras live outside it, above and below,
	-- so nothing ever grows. That was not always true - debuffs used to sit in a
	-- tray inside the glass and push it downward - and the split is what made
	-- that possible mid-combat, because `SetHeight` is protected on a frame
	-- carrying a secure template and the click-catcher covers the core. The
	-- split stays: it keeps the one frame with a secure template on it at a
	-- fixed size for its whole life, which is a promise worth not breaking.
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(cfg.width, cfg.height)
	f.unit = unit
	f.mirror = mirror

	local glass = Glass.CreatePill(f, { shadow = A.db.profile.glass.shadow })
	glass:SetAllPoints(f)
	glass:_Resize()
	f.glass = glass

	local padInner = 10
	local orbSize = cfg.orbSize

	-- Everything below parents to the *glass* so it draws above the glass's own
	-- textures, but anchors to the *core* so it ignores the glass's height.
	-- orb -------------------------------------------------------------------
	local orb = W.CreateOrb(glass, { size = orbSize, portrait = cfg.showPortrait })
	if mirror then
		orb:SetPoint("RIGHT", f, "RIGHT", -padInner, 0)
	else
		orb:SetPoint("LEFT", f, "LEFT", padInner, 0)
	end
	f.orb = orb

	-- text + bars block -----------------------------------------------------
	local block = CreateFrame("Frame", nil, glass)
	block:SetWidth(cfg.barWidth)
	block:SetPoint("TOP", f, "TOP", 0, -11)
	block:SetPoint("BOTTOM", f, "BOTTOM", 0, 11)
	if mirror then
		block:SetPoint("RIGHT", orb, "LEFT", -13, 0)
	else
		block:SetPoint("LEFT", orb, "RIGHT", 13, 0)
	end
	f.block = block

	local justify = mirror and "RIGHT" or "LEFT"
	local anchor  = mirror and "TOPRIGHT" or "TOPLEFT"

	local name = W.Text(block, "unitName", justify)
	name:SetPoint(anchor, block, anchor, 0, 0)
	-- Never wraps, on any path. The health bar is anchored to this line's
	-- bottom edge, so a name that took two lines would push the bars down out of
	-- the capsule - and the whole point of the collapse chain is that the frame
	-- does not change shape for a long name.
	name:SetWordWrap(false)
	f.name = name

	local sub = W.Text(block, "unitSub", justify)
	if mirror then
		sub:SetPoint("RIGHT", name, "LEFT", -8, 0)
	else
		sub:SetPoint("LEFT", name, "RIGHT", 8, 0)
	end
	W.Color(sub, Palette.c.textDim)
	f.sub = sub

	local health = W.CreateBar(block, { height = 7 })
	health:SetPoint(mirror and "TOPRIGHT" or "TOPLEFT", name, mirror and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -4)
	health:SetWidth(cfg.barWidth)
	health:SetReverseFill(mirror and true or false)
	f.health = health

	local power = W.CreateBar(block, { height = 5 })
	power:SetPoint(mirror and "TOPRIGHT" or "TOPLEFT", health, mirror and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -4)
	power:SetWidth(cfg.barWidth)
	power:SetReverseFill(mirror and true or false)
	f.power = power
	if not cfg.showPower then power:Hide() end

	-- readout ---------------------------------------------------------------
	-- Each number is anchored to *its own bar*, vertically centred on it.
	--
	-- Stacking them from the top of a fixed-height frame instead is what put the
	-- target's "100%" too high: that layout reserves room for two lines, so on a
	-- unit with no power bar the single line sits where the first of two would
	-- have been rather than beside the one bar that exists. Anchoring per bar is
	-- self-correcting - hide the power bar and the health number stays put.
	local hpText = W.Text(glass, "unitValue", mirror and "LEFT" or "RIGHT")
	hpText:SetWidth(40)
	if mirror then
		hpText:SetPoint("RIGHT", health, "LEFT", -12, 0)
	else
		hpText:SetPoint("LEFT", health, "RIGHT", 12, 0)
	end
	f.hpText = hpText

	local mpText = W.Text(glass, "unitValueAlt", mirror and "LEFT" or "RIGHT")
	mpText:SetWidth(40)
	if mirror then
		mpText:SetPoint("RIGHT", power, "LEFT", -12, 0)
	else
		mpText:SetPoint("LEFT", power, "RIGHT", 12, 0)
	end
	f.mpText = mpText

	-- interaction -----------------------------------------------------------
	-- A secure unit button so left-click targets and right-click opens the unit
	-- menu. It covers the core exactly, which keeps it clear of the aura trays
	-- above and below - those carry their own mouse-enabled tiles - and it stays
	-- a fixed size for its whole life.
	if cfg.clickTarget then
		local click = CreateFrame("Button",
			ADDON .. (mirror and "TargetFrame" or "PlayerFrame"),
			f, "SecureUnitButtonTemplate")
		click:SetAllPoints(f)
		click:SetAttribute("unit", unit)
		click:SetAttribute("*type1", "target")
		-- TOGGLEMENU, NOT MENU. "menu" calls the button's own menu-function
		-- attribute, which Blizzard's frames set and we never did - so
		-- right-click did nothing at all, silently, and with it went Leave
		-- Party, Set Focus and the raid target icons. Before that we were
		-- reaching for a PlayerFrameDropDown global that has not existed on
		-- this client for years.
		--
		-- "togglemenu" is the client's own generic opener: it works out which
		-- menu the unit wants - self, pet, vehicle, in raid, in party,
		-- cooperable, hostile - and opens it. Nine branches we do not keep a
		-- copy of, and no closure of ours in the path. It is also what oUF,
		-- ShadowedUnitFrames and PitBull4 all use, which is the reason the
		-- action is still there: Blizzard's own note calls it unused by their
		-- code and retained for addons.
		click:SetAttribute("*type2", "togglemenu")
		click:RegisterForClicks("AnyUp")
		click:EnableMouse(true)

		f.click = click
		f.secure = true

		-- The state driver owns the *button's* visibility, so no protected call
		-- is ever needed in combat. The glass around it is ours to show and hide
		-- freely, which is what UpdateAll does.
		if RegisterUnitWatch then
			RegisterUnitWatch(click)
			f.unitWatched = true
		end
	end

	return f
end


-- ---------------------------------------------------------------------------
-- cast bar
-- ---------------------------------------------------------------------------

local function BuildCastBar(unit)
	local cfg = A.Config:Module("unitframes")

	local f = Glass.CreatePill(UIParent, {
		fill   = "glassStrong",
		edge   = "castEdge",
		shadow = A.db.profile.glass.shadow,
	})
	f:SetSize(cfg.castWidth + 130, 44)
	f:Hide()
	f.unit = unit
	f.state = { active = false }

	local icon = W.CreateSlot(f, { size = 30 })
	icon:SetPoint("LEFT", f, "LEFT", 7, 0)
	-- The concept shows the cast icon as a circle, not a rounded square.
	if icon.icon.AddMaskTexture then
		W.AddMask(icon.icon, icon, Media.texture.circleMask, icon)
	end
	icon.edge:SetTexture(Media.texture.ring)
	icon.shade:Hide()
	icon.gloss:Hide()
	f.icon = icon

	local name = W.Text(f, "castName", "LEFT")
	name:SetPoint("LEFT", icon, "RIGHT", 12, 0)
	name:SetWidth(110)
	name:SetWordWrap(false)
	f.spellName = name

	local time = W.Text(f, "castTime", "RIGHT")
	time:SetPoint("RIGHT", f, "RIGHT", -20, 0)
	W.Color(time, Palette.c.textDim)
	f.time = time

	local bar = W.CreateBar(f, { height = 7, smooth = false })
	bar:SetPoint("LEFT", name, "RIGHT", 12, 0)
	bar:SetPoint("RIGHT", time, "LEFT", -12, 0)
	f.bar = bar

	-- The bloom under the fill is what makes it read as "channelled magic"
	-- rather than "progress bar".
	local glow = f:CreateTexture(nil, "OVERLAY")
	glow:SetTexture(Media.texture.barGlow)
	glow:SetBlendMode("ADD")
	glow:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPLEFT")
	glow:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
	f.glow = glow

	return f
end

-- ---------------------------------------------------------------------------
-- updates
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- fitting the name row
--
-- The name and the subtitle share one line exactly as wide as the bars under
-- it, and neither had a width - so "Innkeeper Boorand Plainswind" simply drew
-- past the end of the capsule and out over the world. The frame cannot be
-- allowed to grow: it is one of a mirrored pair, and a target frame that got
-- wider every time you clicked a long-named NPC is a HUD that moves while you
-- read it.
--
-- So the row COLLAPSES, in a fixed order, and the order is about what each
-- piece is for:
--
--   1. the level, out of the subtitle    the badge on the orb already says it
--   2. the race                          "Undead Mage" -> "Mage"
--   3. an NPC's leading title            "Innkeeper Boorand Plainswind" ->
--                                        "Boorand Plainswind"; the person's own
--                                        name stays whole
--   4. the creature type                 kept as long as anything can be, and
--                                        given up last, because it is the one
--                                        thing here that changes what you DO -
--                                        polymorph works on a humanoid and not
--                                        on a beast
--   5. truncate the name                 which should be unreachable
--
-- Every step is measured rather than guessed: the row is rebuilt at each and
-- the first one that fits wins.
-- ---------------------------------------------------------------------------

local NAME_GAP = 8      -- between the name and the subtitle

--- The subtitle's forms, richest first, always ending in nothing at all.
local function SubForms(unit, levelText)
	if UnitIsPlayer(unit) then
		local race, class = UnitRace(unit), UnitClass(unit)
		if race and class then return { race .. " " .. class, class, "" } end
		return { class or race or "", "" }
	end
	local t = UnitCreatureType(unit)
	if t then return { t .. " \194\183 Lv " .. levelText, t, "" } end
	return { "Lv " .. levelText, "" }
end

--- The name's forms. One, for now, and the reason is worth having written down.
--
--  The design asks for an NPC's leading TITLE to be dropped here - "Innkeeper
--  Boorand Plainswind" to "Boorand Plainswind" - which is right, and cannot be
--  done by looking at the words. The first version tried: drop the leading word
--  when at least two remain. That turns "Savannah Highmane Prowler" into
--  "Highmane Prowler", and Adjective-Noun is the shape of most Classic mob
--  names, so the guess is wrong far more often than it is right.
--
--  The title is real and it is knowable - it is the `<Innkeeper>` line in the
--  unit's tooltip - but reading it means a hidden scanning tooltip, which is a
--  piece of machinery rather than a line of code. Until that exists the name is
--  left alone, because a name shortened wrongly is worse than one shortened by
--  the truncation at the end of the chain.
local function NameForms(unit)
	return { UnitName(unit) or "" }
end

--- Name form i with subtitle form j, clamped to what exists.
local function Pair(names, subs, i, j)
	return names[math.min(i, #names)], subs[math.min(j, #subs)]
end

--- Does this pair fit the bar's width?
--
--  Measured with the name's own width CLEARED first. A FontString that has been
--  given a width reports the truncated string's extent, so leaving last update's
--  clamp on would have every step "fit" and the row would never uncollapse.
local function Fits(f, name, sub, room)
	f.name:SetWidth(0)
	f.name:SetText(name)
	f.sub:SetText(sub)
	local w = f.name:GetStringWidth() or 0
	if sub ~= "" then w = w + NAME_GAP + (f.sub:GetStringWidth() or 0) end
	return w <= room, w
end

local function UpdateName(f)
	local unit = f.unit
	if not UnitExists(unit) then return end

	local level = UnitLevel(unit)
	local levelText = (level and level > 0) and tostring(level) or "??"
	f.orb:SetLabel(levelText)

	local names = NameForms(unit)
	local subs  = SubForms(unit, levelText)
	local room  = f.block and f.block:GetWidth() or 0
	if room <= 0 then room = A.Config:Module("unitframes").barWidth or 200 end

	-- The order from the note above, expressed as which form of each to try.
	-- Step 3 is a no-op on a player (one name form) and step 2 is a no-op on an
	-- NPC with no creature type, so the same sequence serves both without
	-- either having to know which it is.
	local order = { { 1, 1 }, { 1, 2 }, { 2, 2 }, { 2, 3 } }

	local lastName, lastSub, lastW
	for _, step in ipairs(order) do
		local name, sub = Pair(names, subs, step[1], step[2])
		local ok, w = Fits(f, name, sub, room)
		lastName, lastSub, lastW = name, sub, w
		if ok then
			f._nameStep = _
			f._nameTruncated = false
			return
		end
	end

	-- Nothing fit. The name is given the room that is left and the client
	-- truncates it, which is the last resort and should be unreachable: by here
	-- the subtitle is gone and the name alone is wider than the bars.
	f._nameStep = #order
	f._nameTruncated = true
	local spare = room
	if lastSub ~= "" then spare = spare - NAME_GAP - (f.sub:GetStringWidth() or 0) end
	-- Wrapping is off from construction, so there is nothing to switch off here:
	-- the name must never take two lines on any path, because the health bar
	-- hangs off this line's bottom edge.
	f.name:SetWidth(math.max(20, spare))
end

--- Dead is dead, whatever the last health event said.
local function IsDead(unit)
	if UnitIsDeadOrGhost then
		local ok, dead = pcall(UnitIsDeadOrGhost, unit)
		if ok then return dead and true or false end
	end
	if UnitIsDead and UnitIsDead(unit) then return true end
	if UnitIsGhost and UnitIsGhost(unit) then return true end
	return false
end

local function UpdateHealth(f)
	local unit = f.unit
	if not UnitExists(unit) then return end

	local cur, max = UnitHealth(unit), UnitHealthMax(unit)
	if not max or max <= 0 then max = 1 end

	-- Killing something does not reliably deliver a final UNIT_HEALTH of zero on
	-- this client: the mob dies and the bar keeps whatever sliver it was on, so
	-- the target frame sat reading "10%" over a corpse. Ask the API instead of
	-- trusting the last event, and let Reconcile below catch the moment it flips.
	local dead = IsDead(unit)
	if dead then cur = 0 end
	f._lastHealth = cur

	f.health:SetMinMaxValues(0, max)
	f.health:SetSmoothValue(cur)
	f.health:SetColors(Palette:HealthColor(unit))

	local c = Palette.c
	if dead then
		f.hpText:SetText(_G.DEAD or "Dead")
		W.Color(f.hpText, c.textFaint)
	elseif f.mirror then
		-- The concept puts a percentage on the target, an absolute on the player.
		f.hpText:SetText(string.format("%d%%", math.floor(cur / max * 100 + 0.5)))
		W.Color(f.hpText, c.targetText)
	else
		f.hpText:SetText(W.Short(cur))
		W.Color(f.hpText, { c.health[2][1], c.health[2][2], c.health[2][3], 1 })
	end
end

local function UpdatePower(f)
	local cfg = A.Config:Module("unitframes")
	local unit = f.unit
	if not cfg.showPower or not UnitExists(unit) then return end

	local cur, max = UnitPower(unit), UnitPowerMax(unit)
	if not max or max <= 0 then
		f.power:Hide()
		f.mpText:SetText("")
		f._lastPower = nil
		return
	end
	if IsDead(unit) then cur = 0 end
	f._lastPower = cur
	f.power:Show()
	f.power:SetMinMaxValues(0, max)
	f.power:SetSmoothValue(cur)

	local colors = Palette:PowerColor(unit)
	f.power:SetColors(colors)

	if f.mirror then
		f.mpText:SetText("")
	else
		f.mpText:SetText(W.Short(cur))
		local tail = colors[2] or colors
		W.Color(f.mpText, { tail[1], tail[2], tail[3], 0.85 })
	end
end

--- A hunter's pet has a mood, and it changes its damage.
--
--  ON THE RIM, not as a fourth icon. The capsule is small and already carries a
--  portrait, a name, two bars and two numbers; a face beside all that is one
--  more thing to look past. The rim is a mark this interface already makes -
--  the console says auto-cast the same way - and it is only ever coloured for
--  the one kind of pet that has a mood.
--
--  GATED ON isHunterPet, which is the client's own test. A warlock's imp
--  reports no happiness at all, and a rim tinted from a nil is a rim tinted
--  from whatever the last hunter left behind.
local function HappinessColor()
	if not GetPetHappiness or not HasPetUI then return nil end
	local _, isHunterPet = HasPetUI()
	if not isHunterPet then return nil end

	local happiness = GetPetHappiness()
	local c = Palette.c
	if happiness == 3 then return c.petHappy end
	if happiness == 2 then return c.petContent end
	if happiness == 1 then return c.petUnhappy end
	return nil
end

local function UpdateOrb(f)
	local unit = f.unit
	if not UnitExists(unit) then return end

	local face, rim, ink, faceHi, rimHi = Palette:OrbColors(unit)
	if unit == "pet" then
		local mood = HappinessColor()
		if mood then rim, rimHi = mood, mood end
	end
	f.orb:SetColors(face, rim, ink, faceHi, rimHi)

	if f.orb.portrait then
		SetPortraitTexture(f.orb.portrait, unit)
	end
end

local function UpdateSkin(f)
	local c = Palette.c
	local tint = A.Config:Module("unitframes").reactionTint ~= false
	if f.mirror then
		f.glass:SetFillColor(c.targetGlass)
		f.glass:SetEdgeColor(tint and Palette:ReactionEdge(f.unit) or c.glassEdge)
		W.Color(f.name, c.targetText)
	else
		f.glass:SetFillColor(c.glass)
		f.glass:SetEdgeColor(c.glassEdge)
		W.Color(f.name, c.text)
	end
	W.Color(f.sub, c.textDim)
	-- The skin's track white, not the literal one. These two were the last pair
	-- of hardcoded colours on the HUD proper, and being a raw table they also
	-- sat outside the skin-change sweep - so a capsule kept the wash it was
	-- built with for as long as the frame lived.
	f.health:SetBackdropColor(Palette:Track())
	f.power:SetBackdropColor(Palette:Track())
end

--- Show or hide a capsule - by way of its *glass*, never the core.
--
--  The comment that used to sit here claimed the core was safe to hide because
--  protection is per-object and the core is a plain Frame. That is true of
--  `SetPoint` and `SetHeight`. It is not true of `Hide`: hiding a frame changes
--  the effective visibility of everything under it, and the client refuses when
--  something under it is protected. The core parents the secure click-catcher,
--  so losing your target mid-fight produced
--
--      ADDON BLOCKED: Frame:Hide()  UnitFrames.lua: SetVisible
--
--  Nothing actually needed the core hidden. The click-catcher's visibility is
--  already driven by RegisterUnitWatch, which is secure and works in combat; the
--  aura trays collapse themselves when their unit stops existing; and the glass
--  - which is everything you can see - has no protected descendants at all.
local function SetVisible(f, shown)
	if shown then f.glass:Show() else f.glass:Hide() end
end

local function UpdateAll(f)
	if not UnitExists(f.unit) then
		SetVisible(f, false)
		return
	end
	SetVisible(f, true)
	UpdateName(f)
	UpdateHealth(f)
	UpdatePower(f)
	UpdateOrb(f)
	UpdateSkin(f)
end

UF.UpdateAll = UpdateAll

--- 10Hz reconciliation between what the bars show and what the API says.
--
--  Events stay the primary path - this does no work at all when they agree. It
--  exists because the client does not always send the update that matters most:
--  the final zero when something dies. Two UnitHealth calls a tick is nothing
--  next to a target frame that lies about whether the thing in front of you is
--  still alive.
local function Reconcile()
	for _, f in ipairs(UF.frames) do
		local unit = f.unit
		if f:IsShown() and UnitExists(unit) then
			local want = IsDead(unit) and 0 or (UnitHealth(unit) or 0)
			if f._lastHealth ~= want then UpdateHealth(f) end

			if f.power:IsShown() then
				local wantPower = IsDead(unit) and 0 or (UnitPower(unit) or 0)
				if f._lastPower ~= wantPower then UpdatePower(f) end
			end
		end
	end
end

UF.Reconcile = Reconcile

-- ---------------------------------------------------------------------------
-- cast bar updates
-- ---------------------------------------------------------------------------

--- Classic Era keeps the old argument-less `CastingInfo()` / `ChannelInfo()`
--  alongside the unit-taking versions, and both ShadowedUnitFrames and Gnosis
--  use the old pair for the player on this client. Try the modern call first and
--  fall back, rather than betting on either.
local function PlayerCastingInfo()
	if UnitCastingInfo then
		local a, b, c, d, e = UnitCastingInfo("player")
		if a then return a, b, c, d, e end
	end
	if CastingInfo then return CastingInfo() end
end

local function PlayerChannelInfo()
	if UnitChannelInfo then
		local a, b, c, d, e = UnitChannelInfo("player")
		if a then return a, b, c, d, e end
	end
	if ChannelInfo then return ChannelInfo() end
end

--- Cast data for a unit.
--
--  Classic Era only reports this natively for the player. Everything else comes
--  from LibClassicCasterino, which infers casts from the combat log - the same
--  library ShadowedUnitFrames and Gnosis both ship, for the same reason. Native
--  is tried first regardless, so if Blizzard ever does expose it the library
--  quietly stops being the source.
local LibCC = LibStub and LibStub("LibClassicCasterino", true)

local function CastInfo(unit, channel)
	if unit == "player" then
		if channel then return PlayerChannelInfo() end
		return PlayerCastingInfo()
	end

	local fn = channel and UnitChannelInfo or UnitCastingInfo
	if fn then
		local a, b, c, d, e = fn(unit)
		if a then return a, b, c, d, e end
	end
	if LibCC then
		-- Spelt out rather than `channel and X() or Y()`: an and/or expression
		-- truncates to a single value, so that form silently returned the spell
		-- name and dropped the start/end times, and the bar never started.
		if channel then
			local a, b, c, d, e = LibCC:UnitChannelInfo(unit)
			if a then return a, b, c, d, e end
		else
			local a, b, c, d, e = LibCC:UnitCastingInfo(unit)
			if a then return a, b, c, d, e end
		end
	end
end

-- Shared with the nameplate cast capsule, which needs exactly this fallback and
-- should not grow a second copy of it.
UF.CastInfo = CastInfo

local function CastStop(f)
	if not f then return end
	f.state.active = false
	f:Hide()
	f:SetScript("OnUpdate", nil)
end

--- Runs per frame, not on the shared 0.1s ticker.
--
--  Everything else in the suite is happy at 10Hz - health ticks are discrete,
--  cooldown text only needs whole seconds. A cast bar is the exception: it is a
--  continuously moving object, and at 10Hz a 2.5s cast advances in 25 visible
--  steps. That reads as stutter next to Blizzard's, which updates every frame.
local function CastTick(f)
	local st = f.state
	if not st.active then return end

	local now = GetTime() * 1000
	local pct
	if st.channel then
		pct = (st.endTime - now) / (st.endTime - st.startTime)
	else
		pct = (now - st.startTime) / (st.endTime - st.startTime)
	end
	pct = math.max(0, math.min(1, pct))

	f.bar:SetValue(pct)

	local elapsed = (now - st.startTime) / 1000
	local total   = (st.endTime - st.startTime) / 1000
	f.time:SetText(string.format("%.1f / %.1fs", math.max(0, math.min(elapsed, total)), total))

	if now >= st.endTime then CastStop(f) end
end

local function CastStart(f, channel)
	if not f then return end

	local name, _, texture, startTime, endTime = CastInfo(f.unit, channel)
	if not name or not startTime or not endTime then
		CastStop(f)
		return
	end

	local st = f.state
	st.active, st.channel = true, channel
	st.startTime, st.endTime = startTime, endTime

	local c = Palette.c
	-- Whose bar is this? Yours stays blue; anyone else's takes their reaction, so
	-- the two stacked capsules are answerable at a glance instead of by reading
	-- the spell name.
	local tint = A.Config:Module("unitframes").reactionTint ~= false
	local barColor = tint and Palette:CastColor(f.unit) or c.cast
	local edge     = tint and Palette:CastEdge(f.unit) or c.castEdge
	-- The glow takes the bar's head, whatever that turned out to be. Leaving it
	-- on castGlow would have put a blue halo around a red bar.
	local head = (type(barColor[1]) == "table") and barColor[1] or barColor

	f.spellName:SetText(name)
	W.Color(f.spellName, c.text)
	f.icon:SetIcon(texture)
	f.icon:SetEdgeColor(edge)
	f.bar:SetMinMaxValues(0, 1)
	f.bar:SetColors(barColor)
	f.glow:SetVertexColor(head[1], head[2], head[3], c.castGlow[4] or 0.5)
	f:SetEdgeColor(edge)

	f:Show()
	f:SetScript("OnUpdate", CastTick)
	CastTick(f)
end

UF.CastStart, UF.CastStop = CastStart, CastStop

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------

--- Both cast bars float free, well above the cluster, each on its own mover.
--
--  Neither one can be attached to a capsule any more, and the reason is that
--  every edge of a capsule is now spoken for: buffs grow upward off the top,
--  debuffs downward off the bottom, on both units. A bar tied to either edge
--  would be shoved around by whatever auras happened to be up.
--
--  Floating is not a compromise here. A cast bar is on screen only while you are
--  casting, so the space it occupies costs nothing the rest of the time, and
--  putting it up near where you are actually looking is where it wants to be
--  anyway. The target's sits above the player's, because that is the order the
--  two things are happening in front of you.
--
--  Both are ordinary movers, so `/aether unlock` and they go wherever you like.
--  Unlock previews them, since a bar you can only see mid-cast is a bar you
--  could never place.
function UF:AnchorCastBar()
	local function preview(bar, label)
		return function(show)
			local casting = bar.state and bar.state.active
			if not show then
				if not casting then bar:Hide() end
				return
			end
			if casting then return end
			-- Something to aim at: an empty pill with no bar in it is hard to
			-- judge a position by.
			bar.spellName:SetText(label)
			bar.bar:SetMinMaxValues(0, 1)
			bar.bar:SetValue(0.55)
			bar.time:SetText("")
			bar:Show()
		end
	end

	if self.cast then
		A.Movers:Register("cast", self.cast,
			{ point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 360 }, "Cast bar",
			{ preview = preview(self.cast, "Cast bar") })
	end

	if self.targetCast then
		A.Movers:Register("targetcast", self.targetCast,
			{ point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 412 }, "Target cast bar",
			{ preview = preview(self.targetCast, "Target cast bar") })
	end
end

function UF:RegisterEvents()
	local function unitEvent(handler)
		return function(_, _, unit)
			for _, f in ipairs(UF.frames) do
				if f.unit == unit then handler(f) end
			end
		end
	end

	A:RegisterEvent(self, "UNIT_HEALTH",       unitEvent(UpdateHealth))
	A:RegisterEvent(self, "UNIT_MAXHEALTH",    unitEvent(UpdateHealth))
	A:RegisterEvent(self, "UNIT_POWER_UPDATE", unitEvent(UpdatePower))
	A:RegisterEvent(self, "UNIT_MAXPOWER",     unitEvent(UpdatePower))
	A:RegisterEvent(self, "UNIT_DISPLAYPOWER", unitEvent(UpdatePower))
	A:RegisterEvent(self, "UNIT_NAME_UPDATE",  unitEvent(UpdateName))
	A:RegisterEvent(self, "UNIT_LEVEL",        unitEvent(UpdateName))
	A:RegisterEvent(self, "UNIT_FACTION",      unitEvent(UpdateOrb))

	-- A PET COMES AND GOES, and neither arrival nor dismissal is a unit event on
	-- the pet itself - UNIT_PET fires on the OWNER. Without this the capsule sat
	-- on the last pet's name and health until something else happened to
	-- refresh it.
	A:RegisterEvent(self, "UNIT_PET", function()
		if UF.pet then UpdateAll(UF.pet) end
	end)
	A:RegisterEvent(self, "UNIT_HAPPINESS", function()
		if UF.pet and UnitExists("pet") then UpdateOrb(UF.pet) end
	end)
	A:RegisterEvent(self, "PET_UI_UPDATE", function()
		if UF.pet then UpdateAll(UF.pet) end
	end)

	A:RegisterEvent(self, "PLAYER_TARGET_CHANGED", function()
		UpdateAll(UF.target)
		if UF.targetCast then
			CastStop(UF.targetCast)
			-- a target may already be mid-cast when you click it
			if UnitExists("target") then
				if CastInfo("target", false) then CastStart(UF.targetCast, false)
				elseif CastInfo("target", true) then CastStart(UF.targetCast, true) end
			end
		end
	end)
	A:RegisterEvent(self, "PLAYER_LEVEL_UP", function()
		UpdateName(UF.player)
	end)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		UF:HideBlizzard()
		UpdateAll(UF.player)
		UpdateAll(UF.target)
	end)

	-- Cast events. The native UNIT_SPELLCAST_* events only fire for the player on
	-- Classic Era; LibClassicCasterino re-broadcasts the same event names for
	-- everyone else through its own callback registry, so the handlers are shared
	-- and just get pointed at two different sources.
	if self.cast or self.targetCast then
		local function barFor(unit)
			if unit == "player" then return UF.cast end
			if unit == "target" then return UF.targetCast end
		end

		local function onStart(_, _, unit)
			local f = barFor(unit)
			if f then CastStart(f, false) end
		end
		local function onChannel(_, _, unit)
			local f = barFor(unit)
			if f then CastStart(f, true) end
		end
		local function onDelayed(_, _, unit)
			local f = barFor(unit)
			if f and f.state.active then CastStart(f, f.state.channel) end
		end
		local function onStop(_, _, unit)
			CastStop(barFor(unit))
		end

		A:RegisterEvent(self, "UNIT_SPELLCAST_START", onStart)
		A:RegisterEvent(self, "UNIT_SPELLCAST_DELAYED", onDelayed)
		A:RegisterEvent(self, "UNIT_SPELLCAST_CHANNEL_START", onChannel)
		A:RegisterEvent(self, "UNIT_SPELLCAST_CHANNEL_UPDATE", onDelayed)
		A:RegisterEvent(self, "UNIT_SPELLCAST_STOP", onStop)
		A:RegisterEvent(self, "UNIT_SPELLCAST_FAILED", onStop)
		A:RegisterEvent(self, "UNIT_SPELLCAST_INTERRUPTED", onStop)
		A:RegisterEvent(self, "UNIT_SPELLCAST_CHANNEL_STOP", onStop)

		if self.targetCast and LibCC and not self._ccHooked then
			self._ccHooked = true
			local function relay(event, unit)
				if unit ~= "target" then return end
				if event == "UNIT_SPELLCAST_CHANNEL_START" then
					CastStart(UF.targetCast, true)
				elseif event == "UNIT_SPELLCAST_START" then
					CastStart(UF.targetCast, false)
				elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
					if UF.targetCast.state.active then
						CastStart(UF.targetCast, UF.targetCast.state.channel)
					end
				else
					CastStop(UF.targetCast)
				end
			end
			for _, e in ipairs({
				"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED",
				"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
				"UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
				"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
			}) do
				-- CallbackHandler embeds RegisterCallback with the *target* as the
				-- first argument: lib.RegisterCallback(target, event, handler).
				pcall(LibCC.RegisterCallback, UF, e, relay)
			end
		end
	end
end
-- ---------------------------------------------------------------------------
-- module lifecycle
-- ---------------------------------------------------------------------------

--- The capsules' movers, plus whichever cast bars exist. Idempotent, because
--  both the first-build path and the come-back-from-disabled path call it.
function UF:RegisterMovers()
	local cfg = A.Config:Module("unitframes")
	local half = (math.max(cfg.width, MinWidth(cfg)) + cfg.gap) / 2
	A.Movers:Register("player", self.player,
		{ point = "BOTTOM", relPoint = "BOTTOM", x = -half, y = 190 }, "Player")
	A.Movers:Register("target", self.target,
		{ point = "BOTTOM", relPoint = "BOTTOM", x = half, y = 190 }, "Target")
	if self.pet then
		-- Under the player by default, which is where one is looked for - but
		-- its OWN entry, so it can be put anywhere. A pet frame you cannot move
		-- is one you end up turning off.
		A.Movers:Register("pet", self.pet,
			{ point = "BOTTOM", relPoint = "BOTTOM", x = -half, y = 140 }, "Pet")
	end
	self:AnchorCastBar()
end

function UF:OnEnable()
	local cfg = A.Config:Module("unitframes")

	-- Toggling the module off and on again must not build a second set of
	-- frames on top of the first. WoW has no way to destroy a frame, so
	-- rebuilding leaks them permanently and you end up with ghost capsules.
	if self.player then
		for _, f in ipairs(self.frames) do SetVisible(f, true) end
		if self.cast then self.cast:Hide() end
		self:OnConfigChanged()
		-- OnDisable took these away, so coming back has to put them back. This
		-- used to live only in the first-build path below, which meant the very
		-- first disable/enable cycle left the capsules unmovable for the rest of
		-- the session - invisible until you happened to /aether unlock afterwards.
		self:RegisterMovers()
		A.Fader:Register(self.player, {})
		A.Fader:Register(self.target, {})
		if self.pet then A.Fader:Register(self.pet, {}) end
		A.Fader:Refresh()
		self:RegisterEvents()
		A:RegisterTicker(self, Reconcile)
		UpdateAll(self.player)
		UpdateAll(self.target)
		if self.pet then UpdateAll(self.pet) end
		return
	end

	self.player = BuildCapsule("player", false)
	self.target = BuildCapsule("target", true)
	self.frames = { self.player, self.target }

	-- THE PET, at a size of its own. Everything the capsule builder makes is
	-- driven from one config, so a smaller pet frame is a scale rather than a
	-- second set of measurements to keep in step - the same argument the
	-- console and the nameplates make for having their own multiplier.
	--
	-- In `frames` like the other two, which is what gives it health, power and
	-- name updates: the unit events walk that list and match on f.unit.
	if cfg.showPet ~= false then
		self.pet = BuildCapsule("pet", false)
		self.frames[#self.frames + 1] = self.pet
	end

	if cfg.showCastBar then
		self.cast = BuildCastBar("player")
		if cfg.showTargetCastBar then
			self.targetCast = BuildCastBar("target")
		end
	end

	self:OnConfigChanged()

	-- movers ----------------------------------------------------------------
	self:RegisterMovers()

	-- fader -----------------------------------------------------------------
	A.Fader:Register(self.player, {})
	A.Fader:Register(self.target, {})
	if self.pet then A.Fader:Register(self.pet, {}) end
	A.Fader:Refresh()

	self:RegisterEvents()
	A:RegisterTicker(self, Reconcile)

	self:HideBlizzard()
	UpdateAll(self.player)
	UpdateAll(self.target)
	if self.pet then UpdateAll(self.pet) end
end

function UF:OnDisable()
	A:UnregisterTicker(self)
	for _, f in ipairs(self.frames or {}) do
		A.Fader:Unregister(f)
		if f.unitWatched and UnregisterUnitWatch then
			UnregisterUnitWatch(f.click)
			f.unitWatched = nil
		end
		-- The glass, not the core - see SetVisible. Disabling a module mid-fight
		-- is unusual but perfectly possible from the options panel.
		SetVisible(f, false)
	end
	if self.cast then self.cast:Hide() end
	if self.targetCast then self.targetCast:Hide() end
	A.Movers:Unregister("player")
	A.Movers:Unregister("target")
	A.Movers:Unregister("cast")
	A.Movers:Unregister("targetcast")
end

function UF:OnSkinChanged()
	for _, f in ipairs(self.frames or {}) do
		f.glass:ApplySkin()
		UpdateSkin(f)
		UpdateHealth(f)
		UpdatePower(f)
		UpdateOrb(f)
	end
	if self.cast then self.cast:ApplySkin("glassStrong", "castEdge") end
end

function UF:OnConfigChanged()
	local cfg = A.Config:Module("unitframes")
	local scale = A.db.profile.scale
	local width = math.max(cfg.width, MinWidth(cfg))

	for _, f in ipairs(self.frames or {}) do
		-- ON TOP OF THE PROFILE'S, not instead of it - the same arrangement the
		-- console and the nameplates have. Set here rather than only at build,
		-- because this loop runs on every config change and would otherwise put
		-- the pet back to the size of the other two.
		f:SetScale(scale * ((f == self.pet and (cfg.petScale or 0.85)) or 1))
		f:SetSize(width, cfg.height)
		-- The glass fills the core, so resizing the core has already resized it;
		-- _Resize just rebuilds the caps and the shadow on this frame rather than
		-- the next one.
		f.glass:_Resize()
		f.health:SetWidth(cfg.barWidth)
		f.power:SetWidth(cfg.barWidth)
		f.block:SetWidth(cfg.barWidth)
		f.orb:Resize(cfg.orbSize)
		f.glass:SetShadow(A.db.profile.glass.shadow)
		if cfg.showPower then f.power:Show() else f.power:Hide() end
		UpdateAll(f)
	end

	if self.cast then
		self.cast:SetScale(scale)
		self.cast:SetSize(cfg.castWidth + 130, 44)
		self.cast:SetShadow(A.db.profile.glass.shadow)
	end
	if self.targetCast then
		self.targetCast:SetScale(scale)
		self.targetCast:SetSize(cfg.castWidth + 130, 44)
		self.targetCast:SetShadow(A.db.profile.glass.shadow)
	end
	self:AnchorCastBar()

	A.Fader:Refresh()
end
