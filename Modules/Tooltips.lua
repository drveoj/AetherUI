--[[--------------------------------------------------------------------------
	AetherUI :: Tooltips

	Concepts 6a and 6b. Two families, deliberately different:

	  unit tooltips    anchored to a screen corner, never following the mouse.
	                   Reaction-coloured name, a level badge, an ELITE chip, and
	                   a live health hairline with its numbers under it.
	  spell / item     follow the cursor at +24 / -22, flipping at screen edges.
	                   Quality drives the title, the rim and an outer bloom.

	This module RESKINS Blizzard's tooltips. It does not replace them, and that
	is the single most important thing about it.
	--------------------------------------------------------------------------
	Why reskin rather than rebuild

	The test client runs MobInfo2, Pawn, VendorPricePlus, BagBrother, Questie and
	the whole Auctioneer suite. Every one of them writes into GameTooltip. A
	bespoke frame that reads UnitLevel and GetItemInfo itself would look exactly
	like the deck and would silently delete all of it - the mob's damage table,
	the item's Pawn score, its vendor price, its auction history. Nobody would
	report that as a bug in AetherUI; they would report the other addons as
	broken.

	So the client's own tooltip stays, with its own lines, its own layout engine
	and its own line count, and we draw a glass card behind it, restyle its font
	objects, recolour what it already wrote, and hang two decorations off the
	side. The rules that keeps workable are worth stating, because each one is
	here for a specific addon in that list:

	  1. HookScript, never SetScript. MobInfo2 (MI2_Events.lua:170) and
	     LibExtraTip (LibExtraTip.lua:473) both save the previous handler and
	     call it, so they compose with a hook chain in EITHER load order - but
	     only while we do not also replace the script. Same for globals:
	     hooksecurefunc, never a reassignment.

	  2. Size from OnSizeChanged, never from OnShow. Pawn hooksecurefuncs about
	     thirty GameTooltip:Set*Item methods (Pawn.lua:252-309) and adds its
	     lines AFTER the tooltip is already on screen. A card measured once at
	     show time is the wrong height for every tooltip Pawn touches.

	  3. The unit header does the smallest possible surgery, and it is
	     order-independent. MobInfo2 APPENDS to line 2 (MI2_Tooltip.lua:381):
	         GameTooltipTextLeft2:SetText( txt.." "..mobData.class )
	     We strip only the leading level token and keep the remainder verbatim,
	     so its addition survives whichever of us runs first. If the pattern
	     does not match - another locale, another addon got there first - we
	     skip the badge and leave the line untouched. No badge is a far better
	     failure than a mangled tooltip.

	  4. ...but appending is not the only thing an addon does to that line, and
	     assuming it was is a mistake this file made first. MobInfo2 also READS
	     the level back out of it, to find where a mob's extra info starts
	     (MobInfo2.lua:2118-2131):

	         levelInfo = tostring(mobLevel)
	         if ... string.find(ttLeft, levelInfo) then levelLine = idx

	     It is scanning for the level NUMBER as a substring. Take the number out
	     and the scan finds nothing, every following line falls through the same
	     branch, and MobInfo2's harvest comes back empty. That path is its
	     shipped default (MobInfoConfig.UseGameTT == 0, MobInfo2.lua:670).

	     There is no clever way to have this both ways: either the digits are in
	     the line or they are in the badge. So the module YIELDS. LevelReader()
	     below detects an addon that reads the line and turns the strip off by
	     itself, and says so in /aether tooltips. The setting is still there for
	     somebody who would rather have the badge - it is their tooltip - but
	     the default is that the addon which needs the text gets the text.

	  4. Nothing is ever deleted. No line is hidden, no line is removed, no line
	     is rewritten that we did not first successfully parse.

	--------------------------------------------------------------------------
	What Classic Era actually provides (Interface 11509, verified in source)

	There is NO TooltipDataProcessor and no C_TooltipInfo. Both are excluded
	from the vanilla load path (Blizzard_SharedXMLGame.toc:8-11). The old script
	events are not legacy here, they are the mechanism: GameTooltip.xml:22-24
	wires OnTooltipSetUnit / OnTooltipSetItem / OnTooltipSetSpell directly, and
	Blizzard's own OnTooltipSetUnit handler does nothing but recolour line 1.

	There is no SetBackdrop on GameTooltip either. The border is a NineSlice
	child (GameTooltipTemplate.xml:22), and SharedTooltip_SetBackdropStyle
	re-applies the default layout AND the default centre colour on every
	GameTooltip_OnHide (GameTooltip.lua:414) and on every item tooltip via
	GameTooltip_UpdateStyle (:505). Suppressing the stock art once does not
	hold; it is re-suppressed from four places below.

	GameTooltip.StatusBar is nil - the XML declares $parentStatusBar with no
	parentKey (GameTooltipTemplate.xml:138), so only the global exists. It is
	8px tall, it hangs BELOW the tooltip's own box, and HealthBar_OnValueChanged
	forces it green unless `lockColor` is set (HealthBar.lua:29).

	GameTooltipTextLeft1 is anchored TOPLEFT 10,-10, which is where the card's
	insets below come from: the tooltip's box already carries 10px of padding,
	and the deck asks for 15 top / 18 sides.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local TT = A:NewModule("tooltips")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- ---------------------------------------------------------------------------
-- geometry, in the deck's own pixels
-- ---------------------------------------------------------------------------

-- The card is drawn OUTSIDE the tooltip's own bounds by these amounts, which is
-- the difference between Blizzard's built-in 10px text padding and the deck's
-- `padding: 15px 18px 14px`.
local INSET_L, INSET_R = 8, 8
local INSET_T, INSET_B = 5, 4

local PAD_X    = 18      -- deck padding, measured from the card's own edge
local BADGE    = 26      -- level badge diameter
local BADGE_GAP = 9      -- badge to name
local CHIP_H   = 16      -- the ELITE pill

local BAR_H    = 7       -- health hairline
local BAR_GAP  = 5       -- tooltip bottom to bar top
-- Clear space between "Health" and the numbers. Not BAR_GAP, which is the
-- VERTICAL one - they are five apart in the source and reading the wrong one
-- would have let the two strings touch at exactly the width this is here to
-- prevent.
local BAR_LABEL_GAP = 24
local BAR_TEXT = 4       -- bar bottom to its labels

-- How much room under the tooltip the whole health block occupies, so the card
-- can reach past the tooltip's own bottom edge to cover it.
local BAR_BLOCK = BAR_GAP + BAR_H + BAR_TEXT + 12

local CURSOR_X, CURSOR_Y = 24, -22

-- ---------------------------------------------------------------------------
-- the tooltips we know about
-- ---------------------------------------------------------------------------

--- Resolved by name at enable time; anything absent is skipped rather than
--  errored. Several genuinely do not exist on this branch - BattlePetTooltip and
--  friends are omitted from Blizzard_FrameXML_Vanilla.toc, and Blizzard's own
--  code guards with `if (BattlePetTooltip) then` (GameTooltip.xml:19).
local KNOWN = {
	"GameTooltip",
	"ItemRefTooltip",
	"ShoppingTooltip1", "ShoppingTooltip2",
	"ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
	"EmbeddedItemTooltip", "EmbeddedItemTooltipTooltip",
	"WorldMapTooltip", "WorldMapCompareTooltip1", "WorldMapCompareTooltip2",
	"SmallTextTooltip",
	"FriendsTooltip",
	"PartyMemberBuffTooltip",
	"PrivateAurasTooltip",
	"ItemSocketingDescription",
	"QuickKeybindTooltip", "SettingsTooltip", "EventTraceTooltip",
	"LFGBrowseSearchEntryTooltip",
	-- Our own options panel's tooltips, which are real GameTooltipTemplate
	-- frames created by the Ace libraries (AceGUI-3.0.lua, AceConfigDialog-3.0).
	-- Leaving them out meant AetherUI's own config window was the one place in
	-- the UI still showing a stone border.
	"AceGUITooltip", "AceConfigDialogTooltip",
}

--- LibExtraTip - which is how Informant, Enchantrix, BeanCounter and the rest of
--  the Auctioneer suite reach a tooltip - creates its own GameTooltip frames
--  lazily and names them from its own version string:
--
--      local LIBSTRING = versions.LIBNAME.."_"..versions.MAJOR.."_"..versions.MINOR
--      CreateFrame("GameTooltip", LIBSTRING.."Tooltip"..n, UIParent, "GameTooltipTemplate")
--          -- LibExtraTip.lua:63, 1112
--
--  So the names carry a version number and cannot be in a static list. One
--  delayed sweep of _G catches them after the suite has finished loading; a
--  frame that appears later still gets picked up by the next sweep, and any
--  addon can hand us one directly with TT:Register(frame).
local FOREIGN = "^LibExtraTip.*Tooltip%d+$"

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------

local function cfg() return A.Config:Module("tooltips") end

--- 1240 -> "1,240". BreakUpLargeNumbers is localized and knows about lakh
--  grouping; the fallback is only for a client that lacks it.
local function Commas(n)
	n = math.floor(tonumber(n) or 0)
	if _G.BreakUpLargeNumbers then
		local ok, v = pcall(_G.BreakUpLargeNumbers, n)
		if ok and type(v) == "string" then return v end
	end
	local s = tostring(n)
	local out = (s:reverse():gsub("(%d%d%d)", "%1,"):reverse())
	return (out:gsub("^,", ""))
end

--- A left FontString by index, by GLOBAL name.
--
--  Both `GameTooltip.TextLeft1` (parentKey) and `GameTooltipTextLeft1` (global)
--  are valid on this branch, but only the first eight are declared in XML -
--  lines past that are created by the C engine at runtime and exist ONLY as
--  globals. So the global is the form that works for every line.
local function Left(tip, i)
	local name = tip.GetName and tip:GetName()
	if not name then return nil end
	return _G[name .. "TextLeft" .. i]
end

local function Right(tip, i)
	local name = tip.GetName and tip:GetName()
	if not name then return nil end
	return _G[name .. "TextRight" .. i]
end

local function Ink(fs, c)
	if fs and c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

--- Is this string currently drawn in Blizzard's plain white?
--
--  Used to decide whether a line is the client's own prose or something another
--  addon deliberately coloured. Recolouring only the white ones is what keeps
--  the lore-gold treatment from painting over Pawn's green score line.
local function IsPlainWhite(fs)
	if not fs or not fs.GetTextColor then return false end
	local r, g, b = fs:GetTextColor()
	if not r then return false end
	return r > 0.88 and g > 0.88 and b > 0.88
end

-- ---------------------------------------------------------------------------
-- the level token
-- ---------------------------------------------------------------------------

--- Build the "Level %d" matcher from the CLIENT's own string, not from English.
--
--  UNIT_LEVEL_TEMPLATE is what Blizzard's own code formats with (see
--  Blizzard_UIPanels_Game/Classic/PetStable.lua:88), so it is the same string
--  the tooltip's C code produces. LEVEL is the fallback, and the English
--  literal is the fallback's fallback - reached only on a client missing both,
--  where a wrong guess costs a badge and nothing else.
local levelPattern, levelPatternFor
local function LevelPattern()
	local fmt = _G.UNIT_LEVEL_TEMPLATE
	if type(fmt) ~= "string" or fmt == "" then
		fmt = ((_G.LEVEL and _G.LEVEL ~= "" ) and _G.LEVEL or "Level") .. " %d"
	end

	-- Keyed on the template STRING, not on a "have I run yet" flag. A flag has to
	-- be right about two things at once - that the work is done, and that nil is
	-- an answer rather than a gap - and it is also untestable, because nothing can
	-- ask for the pattern a second time under different conditions. The string is
	-- the actual input; caching against it can only ever be correct.
	if levelPatternFor == fmt then return levelPattern end
	levelPatternFor = fmt
	levelPattern = nil

	-- Escape every Lua pattern magic character, which turns the "%d" or "%s"
	-- placeholder into a literal "%%d", then reopen just that as a capture.
	local esc = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

	-- The substitution has to be CHECKED, not assumed. If the client's template
	-- carries a placeholder shape this does not know - a positional "%1$d", say -
	-- nothing is replaced, the pattern is left with a single trailing capture,
	-- and ParseLevelLine's two-value match returns the whole line as the level
	-- and nil as the remainder. Which then writes an empty string over the line.
	-- Failing to build a pattern has to look like failure, not like a match.
	local n
	esc, n = esc:gsub("%%%%[sd]", "(%%S+)")
	if n ~= 1 then return nil end

	levelPattern = "^%s*" .. esc .. "%s*(.*)$"
	return levelPattern
end

--- Classification words the client may put in front of the creature type, which
--  we take out only when the chip is already saying the same thing.
local function ClassWords()
	local out = {}
	for _, g in ipairs({ "ELITE", "RARE", "BOSS", "PLUS" }) do
		local s = _G[g]
		if type(s) == "string" and s ~= "" then out[#out + 1] = s end
	end
	return out
end

--- Take "Level 20 Elite Humanoid" apart into 20 and "Humanoid", leaving
--  anything MobInfo2 appended to the end of the line exactly where it was.
--
--  Returns nil when the line is not a level line at all, which is the signal to
--  leave it completely alone.
local function ParseLevelLine(text, dropClassWord)
	if type(text) ~= "string" then return nil end

	local pat = LevelPattern()
	if not pat then return nil end

	local lvl, rest = text:match(pat)
	if not lvl then return nil end
	-- A level is a number, or the skull the client draws for "far above you".
	-- Anything else means the pattern matched something it should not have.
	if not tonumber(lvl) and not lvl:find("%?") then return nil end

	rest = rest or ""
	if dropClassWord then
		-- Repeated, not once: a rare elite writes TWO of these words in front of
		-- the creature type ("Rare Elite Humanoid"), and breaking after the first
		-- left "Elite Humanoid" under a chip already saying "Rare+". Bounded by
		-- the word count so a pathological string cannot spin here.
		local passes = #ClassWords()
		for _ = 1, passes do
			local hit
			for _, word in ipairs(ClassWords()) do
				local stripped = rest:match("^"
					.. word:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
					.. "%s+(.*)$")
				if stripped then rest = stripped hit = true break end
			end
			if not hit then break end
		end
	end

	return lvl, (rest:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ---------------------------------------------------------------------------
-- reaction
-- ---------------------------------------------------------------------------

--- The deck's reaction scale, as tokens rather than as literals.
local function ReactionInk(unit)
	local c = Palette.c
	if not unit or not UnitExists(unit) then return c.ttTitle end

	if cfg().classColorNames ~= false then
		local cc = Palette:ClassColor(unit)
		if cc then return cc end
	end

	local reaction = UnitReaction(unit, "player")
	if reaction then
		if reaction <= 3 then return c.ttHostile end
		if reaction == 4 then return c.ttNeutral end
	end
	-- Friendly. The deck gives players a blue and NPCs a green, which is a real
	-- distinction to keep: "that is a person" is different information from
	-- "that is a quest giver", and at a glance the hue is what carries it.
	if UnitIsPlayer(unit) then return c.ttFriendly end
	return c.ttFriendlyNPC
end

--- The word the deck puts after the creature type: "Humanoid - Hostile".
local function ReactionWord(unit)
	if not unit or not UnitExists(unit) then return nil end
	local reaction = UnitReaction(unit, "player")
	if not reaction then return nil end
	if reaction <= 3 then return _G.FACTION_STANDING_LABEL2 or "Hostile" end
	if reaction == 4 then return _G.FACTION_STANDING_LABEL4 or "Neutral" end
	return _G.FACTION_STANDING_LABEL5 or "Friendly"
end

--- Classification -> the chip's label, or nil for an ordinary mob.
local function ClassificationChip(unit)
	if not unit or not UnitExists(unit) then return nil end
	local ok, class = pcall(UnitClassification, unit)
	if not ok or not class then return nil end

	-- Deliberately NOT uppercased. string.upper in this client is ASCII-only,
	-- so uppercasing a localized string leaves accented letters lowercase and
	-- does nothing at all on ruRU - a chip reading "Elite" on one locale and
	-- "элита" on another is correct; one reading "ELITE" and "элита" is not.
	if class == "worldboss" then return _G.BOSS or "Boss" end
	if class == "rareelite" then return ((_G.RARE or "Rare") .. "+") end
	if class == "rare"      then return _G.RARE or "Rare" end
	if class == "elite"     then return _G.ELITE or "Elite" end
	return nil
end

-- ---------------------------------------------------------------------------
-- the glass card
-- ---------------------------------------------------------------------------

TT.skinned = {}          -- [frame] = true
TT.order   = {}          -- registration order, for /aether tooltips

--- Suppress the stock stone border.
--
--  Called from FOUR places, and that is not belt-and-braces. Classic's
--  SharedTooltip_SetBackdropStyle re-applies the default NineSlice layout and
--  the default centre colour unconditionally, and it runs on every OnHide
--  (GameTooltip.lua:414) and on every item tooltip via GameTooltip_UpdateStyle
--  (:505). Doing this once at login lasts until the first item you hover.
--- The scale this tooltip is supposed to be drawn at.
--
--  profile.scale like every other module, times the tooltip's own multiplier -
--  a tooltip is the one surface people most often want a size apart from the
--  rest of the HUD.
local function WantScale()
	local profile = A.db and A.db.profile
	return (profile and profile.scale or 1) * (cfg().scale or 1)
end

--- ...and re-asserted on every show, because somebody else is writing to it.
--
--  Leatrix Plus's "Enhance tooltip" sets GameTooltip:SetScale (and the whole
--  family: ItemRef, Shopping, Embedded, NamePlate, LibDBIcon) from its own
--  slider at startup - Leatrix_Plus.lua:10309. Its default is 100%, so on a UI
--  at 0.71 it lands after us and the tooltip comes out forty per cent bigger
--  than everything around it. Ours is a 15pt title in a card sized to the deck;
--  a tooltip at a different scale from the HUD is not a preference, it is two
--  addons disagreeing in public.
--
--  Same rule and same reason as StripArt: SharedTooltip_SetBackdropStyle keeps
--  putting the stone border back, so it comes off again on every show. Setting
--  either one once at login lasts until the first thing you hover.
--
--  Cheap, and NOT a fight: Leatrix writes this at startup and when its slider
--  moves, not on show, so re-asserting here wins outright rather than ping-
--  ponging. It also means our own scale setting is the one that answers, which
--  it should be - we are the addon drawing the card.
local function ApplyScale(tip)
	if not tip or not tip.SetScale then return end
	local want = WantScale()
	if tip.GetScale then
		local ok, has = pcall(tip.GetScale, tip)
		-- Only when it has actually moved. SetScale re-lays out everything
		-- anchored to the frame, and this runs on every tooltip show.
		if ok and has and math.abs(has - want) < 0.001 then return end
	end
	pcall(tip.SetScale, tip, want)
end

local function StripArt(tip)
	local ns = tip.NineSlice
	if ns then
		if ns.SetAlpha then ns:SetAlpha(0) end
		if ns.Hide then ns:Hide() end
	end
	if tip.SetBackdropColor then pcall(tip.SetBackdropColor, tip, 0, 0, 0, 0) end
	if tip.SetBackdropBorderColor then pcall(tip.SetBackdropBorderColor, tip, 0, 0, 0, 0) end
	-- The two decorative overlays SharedTooltip_SetBackdropStyle also drives.
	for _, key in ipairs({ "TopOverlay", "BottomOverlay" }) do
		local o = tip[key]
		if o and o.Hide then o:Hide() end
	end
end

--- Size and place the card. This is the function that has to be cheap, because
--  it runs on every OnSizeChanged - which, with Pawn and LibExtraTip in the
--  mix, is several times per tooltip.
--- A tooltip is drawn over everything, on every show.
--
--  W.Tooltip says this too, but only for the tooltips WE raise - and most of
--  them are raised by the client: a quest reward, a merchant's wares, a bag
--  slot. A tooltip is a shared object anything can reparent or restrata, and
--  this addon does exactly that (the console takes it out of UIParent for a
--  flight so it can be read over a hidden interface). Anything that leaves it
--  somewhere else - a landing missed in combat, another addon with the same
--  idea - leaves it drawing UNDER a panel, which is where a quest reward's was
--  found: half of it behind the quest window.
--
--  Idempotent, and TOOLTIP is where the client puts it anyway, so saying so on
--  every show can never be wrong.
local function AssertStrata(tip)
	if tip.GetFrameStrata and tip:GetFrameStrata() ~= "TOOLTIP" then
		if tip.SetFrameStrata then tip:SetFrameStrata("TOOLTIP") end
	end
	if tip.SetToplevel then tip:SetToplevel(true) end
end

local function LayoutCard(tip)
	local card = tip.aetherCard
	if not card then return end

	local gutter = tip.aetherGutter or 0
	local bottom = INSET_B
	local bar = tip.aetherBar
	if bar and bar.IsShown and bar:IsShown() then bottom = bottom + BAR_BLOCK end

	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", tip, "TOPLEFT", -(gutter + INSET_L), INSET_T)
	card:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT", INSET_R, -bottom)

	-- Blizzard raises tooltip frame levels as it stacks compare tooltips, so the
	-- card cannot be levelled once at build time and left.
	local lvl = tip.GetFrameLevel and tip:GetFrameLevel() or 1
	if lvl < 1 then
		if tip.SetFrameLevel then tip:SetFrameLevel(1) end
		lvl = 1
	end
	if card.SetFrameLevel then card:SetFrameLevel(lvl - 1) end
end

TT.LayoutCard = LayoutCard

--- Put the card back to its resting appearance. Called from OnTooltipCleared,
--  which the client fires on every SetOwner - i.e. immediately before the
--  tooltip is refilled - so this and the OnTooltipSet* handlers below are one
--  clean cycle rather than two things racing.
local function ResetCard(tip)
	local card = tip.aetherCard
	if not card then return end

	local c = Palette.c
	card:SetEdgeColor(c.glassEdge)
	card:SetRimGlow(nil)

	tip.aetherGutter = 0
	tip.aetherStripped = nil
	if tip.aetherBadge then tip.aetherBadge:Hide() end
	if tip.aetherChip then tip.aetherChip:Hide() end
	if tip.aetherMinWidth and tip.SetMinimumWidth then
		-- The running maximum goes with it. Without this the widest unit you
		-- ever moused over sets the floor for every tooltip after it.
		tip.aetherWantW = nil
		pcall(tip.SetMinimumWidth, tip, 0)
		tip.aetherMinWidth = nil
	end

	LayoutCard(tip)
end

--- Build the card and hang the hooks off a tooltip. Idempotent; safe to call on
--  a frame that is already registered.
function TT:Register(tip)
	if type(tip) ~= "table" or TT.skinned[tip] then return false end
	if not tip.GetName or not tip.CreateTexture then return false end

	TT.skinned[tip] = true
	TT.order[#TT.order + 1] = tip

	local profile = A.db and A.db.profile
	local card = Glass.CreatePanel(tip, {
		corner = (profile and profile.glass.corner) or 12,
		shadow = (profile and profile.glass.shadow) or 1,
	})
	-- A tooltip is a reading surface: small type over whatever the world happens
	-- to be doing behind it. Same treatment as chat and the quest log, for the
	-- same reason - see Palette:ReadingFill.
	card:SetFillColor(Palette:ReadingFill())
	tip.aetherCard = card

	ApplyScale(tip)
	StripArt(tip)
	LayoutCard(tip)

	-- HookScript, never SetScript. See the header.
	tip:HookScript("OnShow", function(self)
		if not TT.enabled then return end
		ApplyScale(self)
		StripArt(self)
		LayoutCard(self)
		AssertStrata(self)
	end)

	-- The important one. Pawn, VendorPricePlus and every LibExtraTip consumer add
	-- their lines after the tooltip is already up, so this is what keeps the card
	-- the right height for them.
	tip:HookScript("OnSizeChanged", function(self)
		if not TT.enabled then return end
		LayoutCard(self)
	end)

	if tip.HasScript and tip:HasScript("OnTooltipCleared") then
		tip:HookScript("OnTooltipCleared", function(self)
			if not TT.enabled then return end
			ResetCard(self)
		end)
	end

	if tip.HasScript and tip:HasScript("OnTooltipSetUnit") then
		tip:HookScript("OnTooltipSetUnit", function(self)
			if TT.enabled then TT:OnUnit(self) end
		end)
	end
	if tip.HasScript and tip:HasScript("OnTooltipSetItem") then
		tip:HookScript("OnTooltipSetItem", function(self)
			if TT.enabled then TT:OnItem(self) end
		end)
	end
	if tip.HasScript and tip:HasScript("OnTooltipSetSpell") then
		tip:HookScript("OnTooltipSetSpell", function(self)
			if TT.enabled then TT:OnSpell(self) end
		end)
	end

	TT:AdoptStatusBar(tip)

	return true
end

-- ---------------------------------------------------------------------------
-- the health hairline
-- ---------------------------------------------------------------------------

--- Restyle the tooltip's status bar in place.
--
--  In place, rather than hidden and replaced, because the client drives this bar
--  from C when SetUnit runs - there is no Lua entry point that shows it, so a
--  replacement would have nothing to listen to. lockColor is the supported way
--  to stop HealthBar_OnValueChanged forcing it back to flat green
--  (Blizzard_GameTooltip/HealthBar.lua:29).
function TT:AdoptStatusBar(tip)
	local name = tip.GetName and tip:GetName()
	if not name then return end
	local bar = _G[name .. "StatusBar"]
	if not bar or bar.aetherStyled then return end

	bar.aetherStyled = true
	bar.lockColor = true
	tip.aetherBar = bar

	if bar.SetStatusBarTexture then bar:SetStatusBarTexture(Media.texture.bar) end
	if bar.SetHeight then bar:SetHeight(BAR_H) end

	-- Realigned with the text column. Blizzard insets it 2px from the tooltip's
	-- own edges; the deck runs it from the card's padding, which is where the
	-- name above it starts.
	if bar.ClearAllPoints then
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 10, -BAR_GAP)
		bar:SetPoint("TOPRIGHT", tip, "BOTTOMRIGHT", -10, -BAR_GAP)
	end

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(Media.texture.flat)
	bg:SetAllPoints(bar)
	bar.aetherBg = bg

	W.AddMask(bar:GetStatusBarTexture(), bar, Media.texture.barMask, bar)
	if bg.AddMaskTexture then
		local m = W.AddMask(bg, bar, Media.texture.barMask, bar)
		if not m then bar.aetherNoMask = true end
	end

	local label = W.Text(bar, "ttBarLabel", "LEFT")
	label:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -BAR_TEXT)
	label:SetText(_G.HEALTH or "Health")
	bar.aetherLabel = label

	local value = W.Text(bar, "ttBarLabel", "RIGHT")
	value:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -BAR_TEXT)
	bar.aetherValue = value

	TT:StyleStatusBar(bar)

	bar:HookScript("OnValueChanged", function(self)
		if TT.enabled then TT:UpdateStatusBar(self) end
	end)
	bar:HookScript("OnShow", function(self)
		if not TT.enabled then return end
		TT:UpdateStatusBar(self)
		LayoutCard(tip)
	end)
	bar:HookScript("OnHide", function()
		if TT.enabled then LayoutCard(tip) end
	end)
end

function TT:StyleStatusBar(bar)
	local c = Palette.c
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if tex then W.SetGradient(tex, "HORIZONTAL", c.ttHealth[1], c.ttHealth[2]) end
	if bar.aetherBg then
		local b = c.ttHealthBg
		bar.aetherBg:SetVertexColor(b[1], b[2], b[3], b[4] or 1)
	end
	W.Color(bar.aetherLabel, c.textDim)
	W.Color(bar.aetherValue, c.textDim)
end

function TT:UpdateStatusBar(bar)
	if not bar.aetherValue then return end
	if not cfg().healthValues then
		bar.aetherValue:SetText("")
		bar.aetherLabel:SetText("")
		return
	end
	bar.aetherLabel:SetText(_G.HEALTH or "Health")

	local cur = bar.GetValue and bar:GetValue() or 0

	-- `local _, max = bar.GetMinMaxValues and bar:GetMinMaxValues()` reads well
	-- and is wrong: an `and` expression is truncated to ONE value, so max comes
	-- back nil, the guard below decides the bar has no range, and the readout is
	-- blank for every unit. Guard the call, then take the pair.
	local max = 0
	if bar.GetMinMaxValues then
		local _, m = bar:GetMinMaxValues()
		max = m or 0
	end

	if max <= 0 then
		bar.aetherValue:SetText("")
		return
	end
	bar.aetherValue:SetText(Commas(cur) .. "  /  " .. Commas(max))

	-- ...and make the TOOLTIP wide enough for this row.
	--
	-- A tooltip sizes itself to its text LINES, and these two are not lines -
	-- they are our own FontStrings anchored under the bar, invisible to the
	-- client's own width maths. So "Health" and "1,003 / 1,003" would collide in
	-- the middle of a narrow tooltip while every real line fitted, which is
	-- exactly what a Stable Master looked like.
	--
	-- Requested as a MINIMUM rather than by resizing the tooltip: the client
	-- owns its own width and recomputes it constantly, and anything that sets
	-- the width directly is overwritten on the next SetUnit.
	local tip = bar:GetParent()
	if tip and tip.SetMinimumWidth and bar.aetherLabel.GetStringWidth then
		local need = (bar.aetherLabel:GetStringWidth() or 0)
			+ (bar.aetherValue:GetStringWidth() or 0)
			+ BAR_LABEL_GAP + PAD_X * 2 + (tip.aetherGutter or 0)
		-- Only ever raise it. The elite chip asks for room too, and whichever
		-- wants more should win rather than whichever ran last.
		local want = math.max(need, tip.aetherWantW or 0)
		tip.aetherWantW = want
		pcall(tip.SetMinimumWidth, tip, math.min(want, 420))
		tip.aetherMinWidth = true
	end
end

-- ---------------------------------------------------------------------------
-- the unit header
-- ---------------------------------------------------------------------------

local function EnsureBadge(tip)
	if tip.aetherBadge then return tip.aetherBadge end
	tip.aetherBadge = W.CreateBadge(tip, { size = BADGE, style = "ttBadge" })
	return tip.aetherBadge
end

--- What the badge is tinted with, which is not simply "the name's colour".
--
--  Screen 6a tints the three NPC variants from the reaction and leaves the
--  anchored PLAYER card's badge in the skin's own purple. That is easy to read
--  as an inconsistency in the deck and it is not one: a player's reaction is
--  friendly almost every time you see it, so tinting the badge by it says
--  nothing you did not already know from the name, and spends the card's one
--  accent on saying it. The first pass tinted everything by reaction and a
--  friendly player's badge came out a washed grey-blue for exactly that reason.
local function BadgeColors(unit, ink)
	local c = Palette.c
	if UnitIsPlayer(unit) then
		-- The badge follows the name here too, but ONLY when the name is a
		-- class colour.
		--
		-- The note above is about REACTION, and it is still right about
		-- reaction: a player is friendly almost every time you see one, so a
		-- badge tinted by that says nothing the name did not and comes out the
		-- washed grey-blue the first pass shipped. A CLASS colour is different
		-- information - it is the one thing on the card you cannot get from the
		-- name's wording - and tinting by it makes the rule uniform: the badge
		-- is the name's colour, whoever the name belongs to.
		--
		-- With class colours switched off the ink goes back to being a reaction,
		-- and so does the reason, so the badge goes back to the skin's purple.
		local cc = (cfg().classColorNames ~= false) and Palette:ClassColor(unit)
		if not cc then
			return c.ttBadgeBg, c.ttBadgeEdge, c.ttBadgeInk
		end
		ink = cc
	end
	-- The deck's recipe: the name's colour at .15 for the disc and .40 for the
	-- rim, so the badge is that colour rather than a second, competing one.
	return { ink[1], ink[2], ink[3], 0.15 },
	       { ink[1], ink[2], ink[3], 0.40 },
	       ink
end

local function EnsureChip(tip)
	if tip.aetherChip then return tip.aetherChip end
	local chip = W.Pill(tip, "ttChip", { height = CHIP_H, padX = 8 })
	tip.aetherChip = chip
	return chip
end

--- Is another addon reading the level back out of the tooltip line?
--
--  See rule 4 in the header. MobInfo2 finds where a mob's extra info starts by
--  scanning for the level NUMBER as a substring of each line
--  (MobInfo2.lua:2118-2131), and that scan is on its shipped default path
--  (MobInfoConfig.UseGameTT == 0, MobInfo2.lua:670). Take the digits out for the
--  badge and its harvest comes back empty.
--
--  Detected by the config table rather than by IsAddOnLoaded, because the
--  behaviour is conditional on a setting inside it - somebody running MobInfo2
--  in its own-window mode is not affected and should keep the badge.
--
--  Returns the addon's name, so the diagnostic can say WHY there is no badge.
--  A feature that silently does nothing is worse than one that is off.
local function LevelReader()
	local mi2 = _G.MobInfoConfig
	if type(mi2) == "table" and mi2.UseGameTT == 0 and _G.MI2_BuildTooltipMob then
		return "MobInfo2"
	end
	return nil
end

--- May we take the level out of the line at all?
local function CanStripLevel()
	local conf = cfg()
	if not conf.levelBadge then return false end
	if conf.deferToLevelReaders ~= false and LevelReader() then return false end
	return true
end

--- Which line carries the level, and what is left of it once the level is out.
--
--  Scanned rather than assumed, because the line moves: an NPC puts it on line
--  2, a guilded player puts the guild on 2 and the level on 3. Four lines is
--  enough for every shape the client produces and keeps this off the hot path.
local function StripLevel(tip, dropClassWord)
	local limit = math.min(tip.NumLines and tip:NumLines() or 0, 4)
	for i = 2, limit do
		local fs = Left(tip, i)
		local text = fs and fs.GetText and fs:GetText()
		local lvl, rest = ParseLevelLine(text, dropClassWord)
		if lvl then return i, fs, lvl, rest end
	end
	return nil
end

function TT:OnUnit(tip)
	local card = tip.aetherCard
	if not card then return end

	local c, conf = Palette.c, cfg()

	-- IsUnit is what Blizzard's own handler uses here (GameTooltip.lua:499);
	-- GetUnit exists on the live client but is called nowhere in the Classic
	-- source, so it is probed rather than trusted.
	local unit
	if tip.GetUnit then
		local ok, _, u = pcall(tip.GetUnit, tip)
		if ok then unit = u end
	end
	if not unit and tip.IsUnit and tip:IsUnit("mouseover") then unit = "mouseover" end
	if not unit or not UnitExists(unit) then return end

	-- 1. the name, in the reaction colour
	local ink = ReactionInk(unit)
	Ink(Left(tip, 1), ink)

	-- 1b. the guild, which the client writes as its own <bracketed> line. Matched
	--     on shape rather than on index because a guilded player puts it on line
	--     2 and an unguilded one has no such line at all.
	if UnitIsPlayer(unit) then
		for i = 2, math.min(tip.NumLines and tip:NumLines() or 0, 3) do
			local fs = Left(tip, i)
			local text = fs and fs.GetText and fs:GetText()
			if type(text) == "string" and text:match("^<.+>$") then
				Ink(fs, c.ttGuild)
				break
			end
		end
	end

	-- 2. the chip, which has to be decided before the level line is parsed,
	--    because it is what licenses taking the classification word out of it
	local chipText = conf.eliteChip and ClassificationChip(unit) or nil

	-- 3. the level badge
	local badgeShown = false
	if CanStripLevel() then
		local _, fs, lvl, rest = StripLevel(tip, chipText ~= nil)
		if lvl then
			-- Everything below happens only on a line we successfully parsed. A
			-- line that did not match is never touched.
			local word = conf.reactionWord and ReactionWord(unit) or nil
			if word and rest ~= "" and not rest:find(word, 1, true) then
				rest = rest .. "  \194\183  " .. word
			elseif word and rest == "" then
				rest = word
			end
			fs:SetText(rest)
			Ink(fs, c.textDim)

			local badge = EnsureBadge(tip)

			-- The unit's level, not the parsed token, whenever the client will
			-- give it: UnitLevel cannot be thrown off by a locale, by an addon
			-- that reformatted the line, or by a pattern that matched loosely.
			-- The parse decides WHICH LINE to strip; it does not also have to be
			-- the source of the number.
			local shown = UnitLevel and UnitLevel(unit)
			if not shown or shown <= 0 then shown = tonumber(lvl) end
			badge:SetLabel(shown and tostring(shown) or "??")
			-- Re-snapped every time rather than once at build: the UI scale, the
			-- profile scale and the tooltip's own multiplier can all move under it.
			badge:Resize(BADGE)
			badge:SetColors(BadgeColors(unit, ink))

			-- Remember that THIS fill has already been stripped.
			--
			-- Without it the handler is not safe to re-enter: run it twice over
			-- the same text and the second pass finds no level (correctly - we
			-- took it out), reads that as "no badge here", and hides the badge it
			-- drew a moment ago. Cleared by ResetCard, which the client runs on
			-- every refill, so a genuinely new unit always re-parses.
			tip.aetherStripped = unit

			local left1 = Left(tip, 1)
			if left1 then
				badge:ClearAllPoints()
				badge:SetPoint("RIGHT", left1, "LEFT", -BADGE_GAP, 0)
				badge:Show()
				-- The gutter is how the badge gets room: the CARD grows to the
				-- left, and not one FontString anchor is touched. Re-anchoring
				-- the text block instead would fight the C layout code and break
				-- LibExtraTip's right-column arithmetic (LibExtraTip.lua:1222).
				tip.aetherGutter = BADGE + BADGE_GAP
				badgeShown = true
			end
		end
	end
	-- Re-entry: the level is already out of the line, so nothing parsed - but the
	-- badge on screen is still correct for this unit and this fill. Keep it.
	if not badgeShown and tip.aetherStripped == unit
		and tip.aetherBadge and tip.aetherBadge:IsShown() then
		badgeShown = true
	end

	if not badgeShown and tip.aetherBadge then
		tip.aetherBadge:Hide()
		tip.aetherGutter = 0
	end

	-- 4. the chip itself, and the rim that goes with it
	if chipText then
		local chip = EnsureChip(tip)
		chip:SetLabel(Media:Track(chipText, 1))
		chip:SetColors(c.ttElite, c.ttEliteInk)

		local left1 = Left(tip, 1)
		local l1h = (left1 and left1.GetHeight and left1:GetHeight()) or 14
		chip:ClearAllPoints()
		-- INSET_T + 10 is the distance from the card's top edge to line 1's top:
		-- the card sits INSET_T above the tooltip, and GameTooltipTextLeft1 is
		-- anchored 10 below it (GameTooltipTemplate.xml:25-29).
		chip:SetPoint("TOPRIGHT", card, "TOPRIGHT",
			-PAD_X, -(INSET_T + 10) - math.max(0, (l1h - CHIP_H) / 2))
		chip:Show()

		-- Keep the name and the chip out of each other's way. The tooltip's width
		-- is text-driven, so without this a long name simply runs under the chip.
		if tip.SetMinimumWidth and left1 and left1.GetStringWidth then
			local want = left1:GetStringWidth() + chip:GetWidth() + PAD_X * 2 + 20
				+ (tip.aetherGutter or 0)
			-- Through the same running maximum as the health row, so the two
			-- requirements do not overwrite each other turn about.
			want = math.max(want, tip.aetherWantW or 0)
			tip.aetherWantW = want
			pcall(tip.SetMinimumWidth, tip, math.min(want, 420))
			tip.aetherMinWidth = true
		end

		card:SetEdgeColor({ c.ttElite[1], c.ttElite[2], c.ttElite[3], 0.40 })
		card:SetRimGlow({ c.ttElite[1], c.ttElite[2], c.ttElite[3], 0.15 })
	elseif tip.aetherChip then
		tip.aetherChip:Hide()
	end

	if tip.aetherBar then TT:UpdateStatusBar(tip.aetherBar) end
	LayoutCard(tip)
end

-- ---------------------------------------------------------------------------
-- items and spells
-- ---------------------------------------------------------------------------

--- Item quality, by whatever route the client will give it up.
--
--  GetItem is not called on a tooltip anywhere in the Classic source, so it is
--  probed rather than assumed. The fallback reads it back out of the colour
--  Blizzard already painted line 1 with, which is always the quality colour -
--  less direct, but it needs no API at all.
local function ItemQuality(tip)
	if tip.GetItem then
		local ok, _, link = pcall(tip.GetItem, tip)
		if ok and link and GetItemInfo then
			local ok2, _, _, q = pcall(GetItemInfo, link)
			if ok2 and q then return q end
		end
	end

	local fs = Left(tip, 1)
	if not fs or not fs.GetTextColor or not _G.ITEM_QUALITY_COLORS then return nil end
	local r, g, b = fs:GetTextColor()
	if not r then return nil end
	for q = 0, 7 do
		local qc = _G.ITEM_QUALITY_COLORS[q]
		if qc and math.abs(qc.r - r) < 0.03 and math.abs(qc.g - g) < 0.03
			and math.abs(qc.b - b) < 0.03 then
			return q
		end
	end
	return nil
end

function TT:OnItem(tip)
	local card = tip.aetherCard
	if not card or not cfg().qualityBorder then return end

	-- GameTooltip_UpdateStyle runs SharedTooltip_SetBackdropStyle on every item
	-- tooltip (GameTooltip.lua:505), which puts the stone border straight back.
	StripArt(tip)

	local q = ItemQuality(tip)
	local set = q and Palette.c.itemQuality and Palette.c.itemQuality[q]
	if not set then
		card:SetEdgeColor(Palette.c.glassEdge)
		card:SetRimGlow(nil)
		return
	end

	local e = set.edge
	card:SetEdgeColor({ e[1], e[2], e[3], math.max(e[4] or 1, 0.45) })
	card:SetRimGlow(set.glow and { set.glow[1], set.glow[2], set.glow[3], 0.18 } or nil)

	-- The title takes ttQuality, NOT the rim colour it is sitting inside. They
	-- look interchangeable on Midnight and are not: Daylight's rims are dark by
	-- design, and reusing one as ink drew a near-black item name on a pale panel
	-- where every other string was white. See the note in Core\Palette.lua.
	local qc = Palette.c.ttQuality and Palette.c.ttQuality[q]
	Ink(Left(tip, 1), qc or { e[1], e[2], e[3], 1 })

	LayoutCard(tip)
end

function TT:OnSpell(tip)
	local card = tip.aetherCard
	if not card then return end

	StripArt(tip)
	Ink(Left(tip, 1), Palette.c.ttTitle)

	-- The deck's lore gold on the body copy.
	--
	-- Only lines that are currently plain white are touched. Blizzard writes the
	-- spell description in white; anything another addon added has been given a
	-- colour on purpose, and painting over it is exactly the kind of thing this
	-- module exists not to do.
	if cfg().loreGold then
		local n = math.min(tip.NumLines and tip:NumLines() or 0, 12)
		for i = 2, n do
			local fs = Left(tip, i)
			if IsPlainWhite(fs) then Ink(fs, Palette.c.ttLore) end
		end
	end

	LayoutCard(tip)
end

-- ---------------------------------------------------------------------------
-- typography
-- ---------------------------------------------------------------------------

--- Restyle the three tooltip FONT OBJECTS.
--
--  This is the highest-leverage thing in the file. Every line in every tooltip
--  inherits from one of these three (Blizzard_Fonts_Shared/Shared/FontStyles.xml
--  :314-320), including lines Pawn and MobInfo2 add later - so their lines come
--  out in Outfit at the deck's sizes without either addon knowing we exist.
--
--  Colour is deliberately NOT set here. Blizzard passes explicit r,g,b to most
--  AddLine calls and those win regardless; setting it would only change the
--  handful of lines that do not, inconsistently.
local FONT_OBJECTS = {
	{ "GameTooltipHeaderText", "ttName"  },
	{ "GameTooltipText",       "ttBody"  },
	{ "GameTooltipTextSmall",  "ttSmall" },
}

function TT:ApplyFonts()
	if not cfg().restyleFonts then return self:RestoreFonts() end
	for _, pair in ipairs(FONT_OBJECTS) do
		local obj = _G[pair[1]]
		if obj and obj.SetFont then
			-- Keep the client's own face BEFORE overwriting it. Without this,
			-- unticking the option or disabling the module leaves every tooltip in
			-- the game in Outfit until a reload - a switch that appears to do
			-- nothing, which is worse than one that is not there.
			if not obj.__aetherFont and obj.GetFont then
				local ok, p, s, f = pcall(obj.GetFont, obj)
				if ok and p then obj.__aetherFont = { p, s, f } end
			end
			-- pcall: a font object is not a FontString, and a client that refuses
			-- the TTF here should cost us the typeface, not the module.
			pcall(Media.SetFont, Media, obj, pair[2])
		end
	end
end

function TT:RestoreFonts()
	for _, pair in ipairs(FONT_OBJECTS) do
		local obj = _G[pair[1]]
		local saved = obj and obj.__aetherFont
		if saved then pcall(obj.SetFont, obj, saved[1], saved[2], saved[3]) end
	end
end

-- ---------------------------------------------------------------------------
-- anchoring
-- ---------------------------------------------------------------------------

--- Where a unit tooltip lives. A zero-size frame so the mover has something to
--  hold, and so the tooltip's own growth direction is the only thing deciding
--  its size.
function TT:BuildAnchor()
	if self.anchor then return self.anchor end
	local f = CreateFrame("Frame", ADDON .. "TooltipAnchor", UIParent)
	f:SetSize(160, 40)
	f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -48, 48)
	self.anchor = f
	return f
end

--- The corner the tooltip should present to the anchor.
--
--  Derived from where the anchor actually SITS, not from the point string saved
--  with it. That string is not the answer it looks like: Movers re-anchors every
--  drag to BOTTOMLEFT of UIParent (Core\Movers.lua:347) and saves what it set,
--  so it reads BOTTOMRIGHT until the first drag and BOTTOMLEFT forever after -
--  never a TOP variant, whatever the player did with the frame.
--
--  A tooltip grows away from the corner it is pinned by, so getting this wrong
--  means one parked near the top of the screen grows off it. Screen position is
--  the only thing that actually knows.
local function AnchorPoint()
	local f = TT.anchor
	if not f or not f.GetCenter then return "BOTTOMRIGHT" end

	local cx, cy = f:GetCenter()
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	if not cx or not w or w <= 0 or h <= 0 then return "BOTTOMRIGHT" end

	return (cy > h / 2 and "TOP" or "BOTTOM") .. (cx > w / 2 and "RIGHT" or "LEFT")
end

function TT:ApplyDefaultAnchor(tip)
	-- A BUTTON THAT WANTS ITS TOOLTIP BESIDE IT says so, and gets it.
	--
	-- Pet and stance buttons carry the client's own OnEnter, which anchors
	-- by default; ours set an owner and do not. The result was one bar
	-- answering a different question from the rest of them.
	--
	-- SetOwner rather than a SetPoint of our own, deliberately: it is the
	-- same call an ordinary action button makes, so the two land in exactly
	-- the same place instead of in two places that look similar. Safe here
	-- because this hook runs BEFORE the caller sets any content - it fires
	-- from GameTooltip_SetDefaultAnchor, and SetPetAction comes after.
	local owner = tip.GetOwner and tip:GetOwner()
	if owner and owner.__aetherTipBesideOwner then
		tip:SetOwner(owner, "ANCHOR_RIGHT")
		return
	end

	if not cfg().unitAnchor or not self.anchor then return end
	local p = AnchorPoint()
	tip:ClearAllPoints()
	tip:SetPoint(p, self.anchor, p, 0, 0)
end

--- Cursor following, scoped.
--
--  Only tooltips that took the DEFAULT anchor, or whose owner is UIParent, get
--  moved. A bag slot, a merchant row or a quest reward that deliberately called
--  SetOwner(self, "ANCHOR_RIGHT") keeps the position it asked for - which is the
--  answer to "the tooltip jumped away from the thing I was pointing at".
local function WantsCursor(tip)
	if not cfg().cursorItems then return false end
	if tip.default == 1 or tip.default == true then return true end
	local owner = tip.GetOwner and tip:GetOwner()
	return owner == nil or owner == UIParent
end

--- One frame of cursor tracking.
--
--  All the arithmetic is done in the TOOLTIP's own coordinate space:
--  GetCursorPosition returns physical pixels, and SetPoint offsets are read in
--  the space of the frame being positioned, so dividing by the tooltip's
--  effective scale once at the top is the whole conversion. Doing it in UIParent
--  units instead means the tooltip lands at the wrong place the moment its scale
--  is not 1, which is always, because we scale it.
local function FollowCursor(tip)
	if not tip.aetherFollow then return end

	local s = tip.GetEffectiveScale and tip:GetEffectiveScale() or 1
	if not s or s <= 0 then return end

	local cx, cy = GetCursorPosition()
	if not cx then return end
	cx, cy = cx / s, cy / s

	local w = tip:GetWidth() or 0
	local h = tip:GetHeight() or 0
	local us = UIParent:GetEffectiveScale() or 1
	local sw = (UIParent:GetWidth() or 0) * us / s
	local sh = (UIParent:GetHeight() or 0) * us / s

	local x = cx + CURSOR_X
	local y = cy + CURSOR_Y
	-- Flip rather than clamp. Clamping slides the card under the cursor, which
	-- is worse than putting it on the other side.
	if x + w > sw then x = cx - CURSOR_X - w end
	if y - h < 0 then y = cy - CURSOR_Y + h end

	tip:ClearAllPoints()
	tip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

-- ---------------------------------------------------------------------------
-- discovery
-- ---------------------------------------------------------------------------

function TT:RegisterKnown()
	local n = 0
	for _, name in ipairs(KNOWN) do
		local f = _G[name]
		if f and TT:Register(f) then n = n + 1 end
	end
	return n
end

--- One pass over _G for tooltips whose names we cannot know in advance.
--
--  Deliberately a sweep and not a CreateFrame hook: hooking CreateFrame to catch
--  a frame at birth means running our code inside every single frame creation in
--  the session, for the sake of maybe four frames that all exist within a few
--  seconds of the Auctioneer suite loading.
function TT:Sweep()
	local n = 0
	for k, v in pairs(_G) do
		if type(k) == "string" and k:find(FOREIGN) and type(v) == "table"
			and not TT.skinned[v] then
			if TT:Register(v) then n = n + 1 end
		end
	end
	return n
end

-- ---------------------------------------------------------------------------
-- global hooks
--
-- Installed exactly once, and gated on TT.enabled from inside rather than being
-- removed on disable: a hooksecurefunc can never be taken off again, and a
-- HookScript hook cannot either. Both have to be able to become no-ops instead.
-- ---------------------------------------------------------------------------

function TT:InstallHooks()
	if self.hooked then return end
	self.hooked = true

	if _G.GameTooltip_SetDefaultAnchor then
		hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tip)
			if not TT.enabled or not TT.skinned[tip] then return end
			TT:ApplyDefaultAnchor(tip)
		end)
	end

	-- The one that keeps the stone border off. See StripArt.
	if _G.SharedTooltip_SetBackdropStyle then
		hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tip)
			if not TT.enabled or not TT.skinned[tip] then return end
			StripArt(tip)
		end)
	end

	-- The pooled bars are created lazily by the client (GameTooltip.lua:709,
	-- 751), so there is nothing to walk at login - they have to be caught as
	-- they are handed out.
	if _G.GameTooltip_ShowStatusBar then
		hooksecurefunc("GameTooltip_ShowStatusBar", function(tip)
			if not TT.enabled or not tip or not tip.statusBarPool then return end
			-- pcall around the ENUMERATION, not around each bar: the pool object
			-- is Blizzard's and EnumerateActive is not attested anywhere in the
			-- Classic source, so this may be a nil call rather than a loop. A
			-- pooled bar we never reach is a slightly wrong-looking progress bar;
			-- an error here would be thrown from inside the client's own tooltip
			-- code, every time one appeared.
			pcall(function()
				for bar in tip.statusBarPool:EnumerateActive() do
					if not bar.aetherStyled then
						bar.aetherStyled = true
						if bar.SetStatusBarTexture then
							bar:SetStatusBarTexture(Media.texture.bar)
						end
						local h = Palette.c.ttHealth
						local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
						if tex then W.SetGradient(tex, "HORIZONTAL", h[1], h[2]) end
					end
				end
			end)
		end)
	end

	local gt = _G.GameTooltip
	if gt and gt.HookScript then
		gt:HookScript("OnUpdate", function(self)
			if TT.enabled then FollowCursor(self) end
		end)
		-- The follow flag is decided once per tooltip rather than per frame, so
		-- WantsCursor's owner lookup is not on the hot path.
		for _, script in ipairs({ "OnTooltipSetItem", "OnTooltipSetSpell" }) do
			if gt:HasScript(script) then
				gt:HookScript(script, function(self)
					self.aetherFollow = TT.enabled and WantsCursor(self) or nil
				end)
			end
		end
		if gt:HasScript("OnTooltipCleared") then
			gt:HookScript("OnTooltipCleared", function(self)
				self.aetherFollow = nil
			end)
		end
	end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function TT:OnEnable()
	self:BuildAnchor()
	self:RegisterKnown()
	self:InstallHooks()
	self:ApplyFonts()

	A.Movers:Register("tooltip", self.anchor,
		{ point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -48, y = 48 },
		"Tooltip", { growsDown = false })

	-- Two late sweeps rather than one. The first catches an addon that built its
	-- tooltips at load; the second catches LibExtraTip, which does not build one
	-- until something first asks for a tooltip.
	if _G.C_Timer and _G.C_Timer.After then
		C_Timer.After(2, function() if TT.enabled then TT:Sweep() end end)
		C_Timer.After(12, function() if TT.enabled then TT:Sweep() end end)
	else
		TT:Sweep()
	end

	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() TT:RegisterKnown() end)

	self:OnConfigChanged()
end

function TT:OnDisable()
	-- Hooks cannot be removed, so disabling means going quiet, not going away:
	-- every hook body above tests TT.enabled, which A:EnableModule has already
	-- cleared by the time this runs. What is left is putting the client's own
	-- appearance back, so the tooltip is usable rather than invisible.
	for tip in pairs(self.skinned) do
		if tip.aetherCard then tip.aetherCard:Hide() end
		if tip.aetherBadge then tip.aetherBadge:Hide() end
		if tip.aetherChip then tip.aetherChip:Hide() end
		local ns = tip.NineSlice
		if ns then
			if ns.SetAlpha then ns:SetAlpha(1) end
			if ns.Show then ns:Show() end
		end
		if tip.SetScale then tip:SetScale(1) end

		-- The health bar is the easy one to forget, because hiding a card is
		-- visible and leaving an 8px bar at 7px with our labels under it is not.
		-- "Off" has to mean the client's tooltip, not a slightly haunted one.
		local bar = tip.aetherBar
		if bar then
			bar.lockColor = nil
			if bar.SetHeight then bar:SetHeight(8) end
			if bar.ClearAllPoints then
				bar:ClearAllPoints()
				bar:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 2, -1)
				bar:SetPoint("TOPRIGHT", tip, "BOTTOMRIGHT", -2, -1)
			end
			if bar.aetherBg then bar.aetherBg:Hide() end
			if bar.aetherLabel then bar.aetherLabel:Hide() end
			if bar.aetherValue then bar.aetherValue:Hide() end
		end
	end

	self:RestoreFonts()
	A.Movers:Unregister("tooltip")
end

function TT:OnSkinChanged()
	local c = Palette.c
	for tip in pairs(self.skinned) do
		local card = tip.aetherCard
		if card then
			card:ApplySkin()
			card:SetFillColor(Palette:ReadingFill())
		end
		if tip.aetherBar then TT:StyleStatusBar(tip.aetherBar) end
		if tip.aetherChip then tip.aetherChip:SetColors(c.ttElite, c.ttEliteInk) end
		if tip.aetherBadge then W.Restyle(tip.aetherBadge.label) end
	end
	self:ApplyFonts()
end

function TT:OnConfigChanged()
	local conf = cfg()
	local profile = A.db and A.db.profile

	for tip in pairs(self.skinned) do
		-- Re-enabling has to put the border back off. OnEnable's other steps all
		-- no-op on an already-registered frame, so without this the client's stone
		-- border sits under the card until the next time that tooltip is shown.
		StripArt(tip)

		local card = tip.aetherCard
		if card then
			card:Show()
			card:SetShadow(profile and profile.glass.shadow or 1)
			Glass.SetPanelCorner(card, conf.corner or 18)
			card:SetFillColor(Palette:ReadingFill())
		end
		ApplyScale(tip)

		-- And the health bar, which OnDisable handed back to the client. Symmetry
		-- here is the whole point: whatever the off path undid, the on path has to
		-- redo, or "off then on" is a third state neither of them describes.
		local bar = tip.aetherBar
		if bar then
			bar.lockColor = true
			if bar.SetHeight then bar:SetHeight(BAR_H) end
			if bar.ClearAllPoints then
				bar:ClearAllPoints()
				bar:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 10, -BAR_GAP)
				bar:SetPoint("TOPRIGHT", tip, "BOTTOMRIGHT", -10, -BAR_GAP)
			end
			if bar.aetherBg then bar.aetherBg:Show() end
			if bar.aetherLabel then bar.aetherLabel:Show() end
			if bar.aetherValue then bar.aetherValue:Show() end
			TT:StyleStatusBar(bar)
		end

		LayoutCard(tip)
	end

	self:ApplyFonts()
end

-- ---------------------------------------------------------------------------
-- diagnostics
-- ---------------------------------------------------------------------------

--- What /aether tooltips prints. Per-frame results rather than a single
--  pass/fail, so a tooltip we never found shows up as absent rather than as
--  silence - the lesson from /aether chat.
function TT:Diagnose()
	A:Print(("skinned " .. A.Val("%d") .. " tooltip frame%s.")
		:format(#self.order, #self.order == 1 and "" or "s"))

	local missing = {}
	for _, name in ipairs(KNOWN) do
		if not _G[name] then missing[#missing + 1] = name end
	end

	for _, tip in ipairs(self.order) do
		local name = tip.GetName and tip:GetName() or "?"
		A:Print(("  " .. A.Good("%s") .. "  card=%s bar=%s")
			:format(name,
				tip.aetherCard and "yes" or "no",
				tip.aetherBar and "yes" or "no"))
	end

	if #missing > 0 then
		A:Print(A.F("absent on this client: %s",
			A.Dim(table.concat(missing, ", "))))
	end

	A:Print(("anchor " .. A.Val("%s") .. "  ·  cursor-follow " .. A.Val("%s") .. "  ·  fonts " .. A.Val("%s"))
		:format(AnchorPoint(),
			cfg().cursorItems and "on" or "off",
			cfg().restyleFonts and "on" or "off"))

	-- Say WHY there is no badge. A feature that quietly does nothing is the
	-- thing this whole diagnostic exists to prevent.
	local reader = LevelReader()
	if cfg().levelBadge and reader and cfg().deferToLevelReaders ~= false then
		A:Print(("level badge " .. A.Dim("stood down") .. " - " .. A.Val("%s") .. " reads the level"
			.. " out of that line, and moving it into the badge would blind it."
			.. " " .. A.Hi("/aether config") .. ", Tooltips, to override."):format(reader))
	elseif cfg().levelBadge then
		A:Print(reader
			and A.F("level badge %s (override: %s is running and reads that"
				.. " line)", A.Good(L["on"]), A.Val(reader))
			or A.F("level badge %s", A.Good(L["on"])))
	end
end

-- Exposed for the harness and for anything that wants to hand us a tooltip.
TT.KNOWN = KNOWN
TT.ParseLevelLine = ParseLevelLine
TT.LevelPattern = LevelPattern
TT.WantsCursor = WantsCursor
TT.StripArt = StripArt
TT.ResetCard = ResetCard
