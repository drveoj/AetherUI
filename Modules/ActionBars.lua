--[[--------------------------------------------------------------------------
	AetherUI :: ActionBars

	The floating dock from concept 2a: a glass panel of rounded-square slots with
	keybinds, cooldown sweeps and an active glow.

	This is the first module that has to be *secure*. Casting a spell is a
	protected action, so the buttons are real SecureActionButtonTemplate widgets
	and anything that changes what they do has to go through either an
	out-of-combat SetAttribute or a restricted snippet. Three consequences shape
	the whole file:

	  1. Bar paging (stances, druid forms, the 1-6 page keys) cannot be done in
	     Lua, because the page can change mid-combat. It runs as a secure state
	     driver on a SecureHandlerStateTemplate header, which pushes the new page
	     down to every child button via control:ChildUpdate. Lua only *reads* the
	     resulting action id back to refresh the artwork.

	  2. Keybinds are override bindings pointed at our buttons rather than a
	     reliance on Blizzard's, because we hide Blizzard's bars and its binding
	     handlers operate on those specific buttons. SetOverrideBindingClick only
	     works out of combat, so rebinding is deferred if it lands during a fight.

	  3. Every structural change - resize, reposition, rebuild - is gated on
	     InCombatLockdown() and replayed on PLAYER_REGEN_ENABLED.

	Geometry is the concept's own pixel values (62px slots, 9px gaps, 10px
	padding). The deck was drawn at 1920x1080; A.db.profile.scale maps those onto
	WoW's virtual coordinate space, which is why it defaults to 0.71.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local AB = A:NewModule("actionbars")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

AB.bars = {}

local NUM_ACTIONS_PER_PAGE = 12

-- Bars are independent. There is no paging anywhere in this module and that is
-- the point of the design, not an omission.
--
-- Paging meant one dock whose twelve buttons pointed at a different block of
-- actions depending on GetActionBarPage() - a number this addon does not own and
-- cannot keep still. Anything can write it, an unfilled page shows an empty
-- dock, and when it moved there was no way to tell whether the bar or the page
-- was at fault. Every bar now names its own source once, at build time, and
-- never changes it. A button's `action` attribute is written when it is created
-- and never written again, which also means nothing here needs the restricted
-- environment or a state driver to survive combat.
--
-- Form and stance bars are not lost by this: pages 7-10 *are* the bonus bars, so
-- a druid points a bar at page 7 and simply sees their Bear abilities all the
-- time rather than having a bar swap under them.

local MAX_ACTION_PAGE = 10   -- 10 x 12 = the 120 action slots Classic Era has
local PET_SLOTS       = 10
local STANCE_SLOTS    = 10

--- Bindings the client already knows about, so a bar picks up the keys you
--  have always used for that block of actions.
-- Bar 2 is the one page Blizzard never named a binding for; ours is declared in
-- Bindings.xml so a key has something to be assigned to. See that file.
local BINDING_FOR_PAGE = {
	[1] = "ACTIONBUTTON",
	[2] = "AETHERUI_BAR2BUTTON",
	[3] = "MULTIACTIONBAR3BUTTON",    -- MultiBarRight
	[4] = "MULTIACTIONBAR4BUTTON",    -- MultiBarLeft
	[5] = "MULTIACTIONBAR2BUTTON",    -- MultiBarBottomRight
	[6] = "MULTIACTIONBAR1BUTTON",    -- MultiBarBottomLeft
}
local BINDING_FOR_KIND = {
	stance = "SHAPESHIFTBUTTON",
	pet    = "BONUSACTIONBUTTON",
}

-- Labels for Blizzard's key binding panel. Harmless if it never opens.
_G.BINDING_HEADER_AETHERUI = "Aether" .. A.Hi("UI")
for i = 1, NUM_ACTIONS_PER_PAGE do
	_G["BINDING_NAME_AETHERUI_BAR2BUTTON" .. i] = "Bar 2 Button " .. i
end

local function BindingPrefix(barCfg)
	if barCfg.binding then return barCfg.binding end
	if barCfg.kind ~= "action" then return BINDING_FOR_KIND[barCfg.kind] end
	return BINDING_FOR_PAGE[barCfg.page or 1]
end

--- How many buttons a bar of this kind can hold.
local function SlotCount(barCfg)
	if barCfg.kind == "pet" then return PET_SLOTS end
	if barCfg.kind == "stance" then
		local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
		return math.min(n, STANCE_SLOTS)
	end
	return math.max(1, math.min(barCfg.buttons or 12, NUM_ACTIONS_PER_PAGE))
end

-- ---------------------------------------------------------------------------
-- keybind text
-- ---------------------------------------------------------------------------

-- Ordered, not a hash: pairs() order is undefined, and "MOUSEWHEELUP" has to be
-- consumed before anything could nibble at its tail.
local KEY_SHORT = {
	{ "MOUSEWHEELUP", "wu" }, { "MOUSEWHEELDOWN", "wd" },
	{ "BACKSPACE", "bs" }, { "CAPSLOCK", "cl" }, { "SPACE", "sp" },
	{ "INSERT", "ins" }, { "DELETE", "del" }, { "HOME", "hm" },
	{ "PAGEUP", "pu" }, { "PAGEDOWN", "pd" },
	{ "NUMPAD", "n" }, { "BUTTON", "m" },
	-- THE NUMPAD'S NAMED KEYS, after the prefix that carries them. NUMPADPLUS
	-- shortened to the prefix alone and left the word: the slot read NPLUS,
	-- five letters where the point of this table is two. ASCII, because the
	-- typographic minus is one of the glyphs Outfit does not carry.
	{ "PLUS", "+" }, { "MINUS", "-" }, { "DIVIDE", "/" },
	{ "MULTIPLY", "*" }, { "DECIMAL", "." },
	{ "ALT%-", "a" }, { "CTRL%-", "c" }, { "SHIFT%-", "s" },
}

--- "SHIFT-BUTTON4" -> "SM4". Full binding text is unreadable at 9pt in a corner.
local function ShortKey(key)
	if not key or key == "" then return "" end
	local out = key:upper()
	for _, pair in ipairs(KEY_SHORT) do
		out = out:gsub(pair[1], pair[2])
	end
	return out:upper()
end

-- ---------------------------------------------------------------------------
-- button state
-- ---------------------------------------------------------------------------

local cooldownWatch = {}   -- button -> true, for the countdown text ticker

local function ButtonAction(b)
	return tonumber(b:GetAttribute("action")) or 0
end

--- Which way a flyout opens off this button: AWAY FROM THE NEARER EDGE.
--
--  Blizzard's template defaults to DOWN and its own bars override that from
--  the bar the button sits on. Ours are placed by the player, so the button
--  is asked where it is rather than told: a slot in the lower half of the
--  screen opens upward, which is every bar anybody docks along the bottom.
--
--  Off the BUTTON, not the bar, because the button is the thing the popup is
--  anchored to and it knows its own position without a reference to thread.
local function FlyoutDirection(b)
	local okH, h = pcall(UIParent.GetHeight, UIParent)
	if not okH or not h or h <= 0 then return "UP" end
	local ok, _, y = pcall(b.GetCenter, b)
	if not ok or not y then return "UP" end
	return (y < h * 0.5) and "UP" or "DOWN"
end

--- THE MARK THAT SAYS A SLOT HAS MORE BEHIND IT.
--
--  Blizzard's arrow came free with FlyoutButtonTemplate and went when the
--  template did - and it went for a good reason, since that template's OnClick
--  took every button's action with it. But the arrow was the ONLY thing saying
--  a slot opens rather than casts, and a summon slot that looks like every
--  other slot is a slot you press once and wonder about.
--
--  Media.texture.chevron, which is already this addon's arrow: the dropdowns
--  use it, the bag rail uses it, the Toolbox rail uses it. Not a new texture -
--  those need a client RESTART rather than a reload, and a shared one is the
--  standing instruction anyway.
--
--  It points the way the drawer opens, on the edge the drawer opens from. The
--  chevron is authored pointing DOWN, so up is the same picture flipped.
local function FlyoutMark(b, dir, on, open)
	if not on then
		if b.flyoutMark then b.flyoutMark:Hide() end
		return
	end

	if not b.flyoutMark then
		-- SUBLEVEL 7, not the default 0. The slot's rim is an OVERLAY texture
		-- covering the whole button, and two textures on the same layer at the
		-- same sublevel are sorted by creation order - which is a rule that
		-- happens to favour this one today and is not something to rely on.
		-- Said outright instead.
		local t = b:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetTexture(Media.texture.chevron)
		-- 10, not 8. Eight units on a 36-unit slot, in a corner, at 75% - the
		-- suite said it was drawn and the screen said it was not, and "too
		-- small to see" and "not there" look identical from here.
		t:SetSize(10, 10)
		b.flyoutMark = t
	end

	local m = b.flyoutMark
	m:ClearAllPoints()

	-- OUTSIDE THE SLOT, NOT INSIDE IT. At TOP(0,-2) it sat two units in from
	-- the top edge, which is exactly where the rim and the gloss are - the
	-- client reported it shown, white, at 75%, and it could not be seen. A
	-- mark drawn under the art that decorates the thing it marks is a mark
	-- nobody looks at.
	--
	-- Just clear of the edge instead, the way Blizzard's own arrow sits. The
	-- drawer opens from that edge and covers it while open, which is right:
	-- the mark says "there is more here", and while the more is on screen it
	-- has nothing to say.
	-- THE EDGE IS THE DRAWER'S; THE GLYPH IS THE STATE.
	--
	-- Where it sits says which way the drawer opens and does not change. Which
	-- way it POINTS says whether the drawer is open: shut, it points the way
	-- the drawer will go; open, it points back at the button, which is the way
	-- clicking again will send it. Blizzard's arrow does exactly this and the
	-- gesture is older than this addon.
	--
	-- The chevron is authored pointing DOWN, so "points up" is the flipped
	-- texcoord and "points down" is the plain one.
	local up = (dir == "UP")
	if open then up = not up end

	if dir == "UP" then
		m:SetPoint("BOTTOM", b, "TOP", 0, 1)
	else
		m:SetPoint("TOP", b, "BOTTOM", 0, -1)
	end
	if up then m:SetTexCoord(0, 1, 1, 0) else m:SetTexCoord(0, 1, 0, 1) end
	-- The same weight as the other two rails' arrows. Three arrows in one
	-- interface that disagree about how dark an arrow is is a thing nobody can
	-- name and everybody sees.
	W.Tint(m, Palette.c.text, 0.75)
	m:Show()
end

--- The popup this slot owns, if the slot is a flyout at all.
--
--  Blizzard's own buttons do this in ActionBarActionButtonDerivedMixin when
--  the action changes; ours do not run that code, so it is done here, from the
--  same trigger. A slot that stops being a flyout gives the popup back, or the
--  next click on it opens the demons that used to be there.
local function UpdateFlyout(b)
	if not b.SetPopupDirection then return end
	local dir = FlyoutDirection(b)
	b.__flyoutDir = dir
	pcall(b.SetPopupDirection, b, dir)

	-- AND WHERE THE SNIPPET CAN READ IT. The mixin keeps the direction on a
	-- plain field, which the restricted environment cannot see; an attribute
	-- is the only channel it can. Written out of combat like every other
	-- attribute here - a bar that moves mid-fight opens its drawer the way it
	-- would have a moment ago, which is better than not opening it.
	if not InCombatLockdown() then
		pcall(b.SetAttribute, b, "aetherFlyoutDirection", dir)
	end

	local action = ButtonAction(b)
	local kind = HasAction(action) and GetActionInfo and GetActionInfo(action)
	if kind == "flyout" and _G.SpellFlyout then
		if b.SetPopup then pcall(b.SetPopup, b, _G.SpellFlyout) end
	elseif b.ClearPopup then
		pcall(b.ClearPopup, b)
	end
	FlyoutMark(b, dir, kind == "flyout", b.__flyoutOpen == true)
end

local function UpdateIcon(b)
	local action = ButtonAction(b)
	UpdateFlyout(b)
	local texture = HasAction(action) and GetActionTexture(action)

	if texture then
		b.icon:SetTexture(texture)
		b.icon:Show()
		b:SetAlpha(1)
	else
		b.icon:Hide()
		b:SetAlpha(A.Config:Module("actionbars").emptyAlpha or 0.25)
	end

	-- Ask for the count only when there is something there to count. An emptied
	-- slot can still answer GetActionCount with the number the departed stack
	-- had, which is how a moved item left its "5" behind on the button.
	local count = HasAction(action) and GetActionCount(action) or 0
	if count and count > 1 then
		b.count:SetText(count)
	else
		b.count:SetText("")
	end
end

--- The rim an EMPTY slot wears.
--
--  Every state painter below returns early on a slot with nothing in it,
--  which left the rim at whatever colour it was built with - and an empty
--  slot is still on screen, at a quarter alpha. On a skin change the whole
--  stance bar and every gap in the action bars kept the old skin's rim.
--
--  Dressed on the way out rather than skipped, so there is no path through
--  these three functions that leaves a rim unsaid.
local function PlainRim(b)
	local c = Palette.c.glassEdge
	if b.edge then b.edge:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
end

local function UpdateUsable(b)
	local action = ButtonAction(b)
	if not HasAction(action) then PlainRim(b) return end

	local usable, noMana = IsUsableAction(action)
	local inRange = IsActionInRange(action)
	local c = Palette.c

	if inRange == false then
		-- Out of range: tint the rim rather than the icon. Classic reddens the
		-- whole button, which fights the glass look and is hard to read against
		-- warm terrain anyway.
		b.icon:SetVertexColor(1, 1, 1)
		b.icon:SetDesaturated(false)
		b.edge:SetVertexColor(c.danger[1], c.danger[2], c.danger[3], 0.9)
	elseif noMana then
		b.icon:SetVertexColor(c.iconNoMana[1], c.iconNoMana[2], c.iconNoMana[3])
		b.icon:SetDesaturated(false)
		b.edge:SetVertexColor(c.power[1][1], c.power[1][2], c.power[1][3], 0.7)
	elseif not usable then
		b.icon:SetVertexColor(c.iconUnusable[1], c.iconUnusable[2], c.iconUnusable[3])
		b.icon:SetDesaturated(true)
		b.edge:SetVertexColor(c.glassEdge[1], c.glassEdge[2], c.glassEdge[3], (c.glassEdge[4] or 1) * 0.5)
	else
		b.icon:SetVertexColor(1, 1, 1)
		b.icon:SetDesaturated(false)
		if IsEquippedAction(action) then
			b.edge:SetVertexColor(c.friendly[1], c.friendly[2], c.friendly[3], 0.85)
		else
			b.edge:SetVertexColor(c.glassEdge[1], c.glassEdge[2], c.glassEdge[3], c.glassEdge[4] or 1)
		end
	end
end

local function UpdateState(b)
	local action = ButtonAction(b)
	local active = HasAction(action) and (IsCurrentAction(action) or IsAutoRepeatAction(action))
	b:SetChecked(active and true or false)
	b:SetActive(active and true or false, Palette.c.cast[1])
end

local function UpdateCooldown(b)
	local action = ButtonAction(b)
	if not HasAction(action) then
		b.cooldown:Hide()
		cooldownWatch[b] = nil
		b.cdText:SetText("")
		return
	end

	local start, duration, enable = GetActionCooldown(action)
	if start and duration and duration > 0 and enable and enable ~= 0 then
		b.cooldown:SetCooldown(start, duration)
		b.cooldown:Show()
		-- Only draw our own countdown for real cooldowns. Painting a number for
		-- every 1.5s global would strobe the whole dock on every cast.
		if duration > 2 then
			cooldownWatch[b] = { start = start, duration = duration }
		else
			cooldownWatch[b] = nil
			b.cdText:SetText("")
		end
	else
		b.cooldown:Hide()
		cooldownWatch[b] = nil
		b.cdText:SetText("")
	end
end

local function UpdateBinding(b)
	local cfg = A.Config:Module("actionbars")
	b.hotkey:SetText(cfg.showKeybinds and ShortKey(b._keyText) or "")
end

local function UpdateAllOn(b)
	UpdateIcon(b)
	UpdateUsable(b)
	UpdateState(b)
	UpdateCooldown(b)
	UpdateBinding(b)
end

-- ---------------------------------------------------------------------------
-- countdown text + range polling, on the shared ticker
-- ---------------------------------------------------------------------------

local rangeAccum = 0

local function Tick(_, dt)
	-- Defined further down the file, so reached through the module table.
	if AB.UpdateExtraBars then AB.UpdateExtraBars() end
	local now = GetTime()

	for b, cd in pairs(cooldownWatch) do
		local remain = cd.start + cd.duration - now
		if remain <= 0 then
			b.cdText:SetText("")
			cooldownWatch[b] = nil
		else
			b.cdText:SetText(W.Duration(remain))
		end
	end

	-- Range is polled, not evented: there is no "unit moved" event, and this is
	-- what every action bar addon does. 0.2s is imperceptible and cheap.
	rangeAccum = rangeAccum + dt
	if rangeAccum >= 0.2 then
		rangeAccum = 0
		-- Action bars only: range has no meaning for a form, a pet command or
		-- an adopted Blizzard button, and only our own buttons carry an icon.
		for _, bar in ipairs(AB.bars) do
			if bar.kind == "action" then
				for _, b in ipairs(bar.buttons) do
					if b.icon and b.icon:IsShown() then UpdateUsable(b) end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- button construction
-- ---------------------------------------------------------------------------

local function UseKeyDown()
	if GetCVarBool then
		local ok, v = pcall(GetCVarBool, "ActionButtonUseKeyDown")
		if ok then return v end
	end
	return false
end

--- Keybind, stack count and cooldown text, all offset by cfg.fontDelta. Called
--  on build and again on every relayout so the knob takes effect live.
local function ApplyButtonFonts(b, size)
	local cfg = A.Config:Module("actionbars")
	local d = cfg.fontDelta or 0
	Media:SetFont(b.hotkey, "keybind", math.max(6, Media:Size("keybind") + d))
	Media:SetFont(b.count,  "stack",   math.max(6, Media:Size("stack") + d))
	-- The cooldown number is sized off the button rather than the role, so it
	-- keeps filling the slot as the slot changes size.
	Media:SetFont(b.cdText, "stack",   math.max(10, size * 0.24 + d))
end

--- Stop the pickup modifier from casting.
--
--  With "use on key down" the click fires on mouse-*down*, which lands before
--  any drag can start - so shift-dragging an action cast it instead of picking
--  it up. The fix is to give the modified click nothing to do: the secure
--  handler looks for `shift-type1` before `type`, and an empty string there
--  makes it return without acting, leaving the drag to happen.
--
--  Which modifier that is belongs to the player, not to us: GetModifiedClick
--  answers, and it is theirs to change in Blizzard's own key bindings.
local function PickupModifier()
	local mod = GetModifiedClick and GetModifiedClick("PICKUPACTION") or "SHIFT"
	if not mod or mod == "" or mod == "NONE" then return nil end
	return mod:lower()
end

local function ApplyPickupModifier(b)
	if InCombatLockdown() then return end
	for _, mod in ipairs({ "shift", "ctrl", "alt" }) do
		pcall(b.SetAttribute, b, mod .. "-type1", nil)
	end
	local mod = PickupModifier()
	if mod then pcall(b.SetAttribute, b, mod .. "-type1", "") end
end


-- ---------------------------------------------------------------------------
-- the flyout drawer
--
-- OURS, BECAUSE BLIZZARD'S DOES NOT SERVE AN ADDON'S BUTTONS ON THIS CLIENT.
--
-- SpellFlyout inherits SecureFrameTemplate, and its AttachToButton reparents
-- it onto the button that was clicked and shows it. Coming off one of our
-- buttons that whole call is tainted, so the Show does not take: the arrow
-- flipped to "open" - that part is ours and insecure - and no drawer appeared.
--
-- This is not a guess about taint. LibActionButton, which is what ElvUI and
-- Bartender4 both run on, decides it in one line:
--
--   local UseCustomFlyout = FlyoutButtonMixin and not ActionButton_UpdateFlyout
--
-- Both of our clients have the mixin and neither has the old function, so
-- every serious bar addon on this client generation builds its own. Ours is
-- the same shape as theirs, because the shape is forced: the drawer's buttons
-- cast spells, so they are secure, so they can only be armed and shown from
-- inside the restricted environment - otherwise the whole thing is dead in
-- combat, which is when you summon anything.
--
-- WHAT IS NOT VERIFIED. The harness cannot run a restricted-environment
-- snippet, so FLYOUT_SNIPPET below is the first thing in this addon that
-- ships unchecked. Everything around it is covered: the table it reads, the
-- buttons it moves, the direction it is given, the wrap that calls it. The
-- snippet's own arithmetic is not, and that is worth knowing rather than
-- discovering.
-- ---------------------------------------------------------------------------

local FLYOUT_GAP     = 4    -- between one drawer slot and the next
local FLYOUT_INSET   = 7    -- from the drawer's edge to the first slot
local FLYOUT_MAX     = 12   -- slots we will ever build; no flyout is near this

--- What the drawer does when a slot is clicked, IN THE SECURE ENVIRONMENT.
--
--  Reads AETHER_FLYOUTS, which the insecure half loads with Execute out of
--  combat, and moves buttons that already exist. Nothing here creates a frame
--  or reads the game's spell tables: both are things the restricted
--  environment will not do, and both are done outside it beforehand.
local FLYOUT_SNIPPET = [==[
	local parent = self:GetAttribute("owner")
	if not parent then return end

	-- A SECOND CLICK ON THE SAME SLOT SHUTS IT. Blizzard's own flyout works
	-- this way and the muscle memory is older than this addon.
	if self:IsShown() and self:GetParent() == parent then
		self:Hide()
		return
	end

	local id = ...
	local info = AETHER_FLYOUTS and AETHER_FLYOUTS[id]
	if not info then return end

	self:SetParent(parent)

	-- AND ITS BAND BACK. SetParent takes the strata with it: the drawer is
	-- built at DIALOG and came up at MEDIUM, level 4, in the same band as the
	-- bar it is opening off - with its own glass at level 5 and its slots at
	-- level 5 beside it rather than above it. Reported by the client itself
	-- when finally asked. A drawer is a thing that opens OVER the interface,
	-- so it says so again here, every time, because every open reparents it.
	self:SetFrameStrata("DIALOG")
	self:SetFrameLevel(20)

	local dir  = parent:GetAttribute("aetherFlyoutDirection") or "UP"
	local size = self:GetAttribute("slotSize") or 36
	local gap  = self:GetAttribute("slotGap") or 4
	local pad  = self:GetAttribute("slotInset") or 7

	local used, prev = 0, nil
	for i, slot in ipairs(info) do
		if slot.known then
			used = used + 1
			local b = self:GetFrameRef("slot" .. used)
			if b then
				b:SetAttribute("type", "spell")
				b:SetAttribute("spell", slot.spell)
				b:CallMethod("AetherPaintSlot", slot.icon or slot.spell)
				b:SetWidth(size)
				b:SetHeight(size)
				-- ABOVE THE GLASS, not level with it. The panel behind these
				-- is a sibling, and a slot that ties with it is a slot the
				-- client is free to sort underneath.
				b:SetFrameLevel(30)
				b:ClearAllPoints()
				if dir == "UP" then
					if prev then b:SetPoint("BOTTOM", prev, "TOP", 0, gap)
					else b:SetPoint("BOTTOM", self, "BOTTOM", 0, pad) end
				elseif dir == "DOWN" then
					if prev then b:SetPoint("TOP", prev, "BOTTOM", 0, -gap)
					else b:SetPoint("TOP", self, "TOP", 0, -pad) end
				elseif dir == "LEFT" then
					if prev then b:SetPoint("RIGHT", prev, "LEFT", -gap, 0)
					else b:SetPoint("RIGHT", self, "RIGHT", -pad, 0) end
				else
					if prev then b:SetPoint("LEFT", prev, "RIGHT", gap, 0)
					else b:SetPoint("LEFT", self, "LEFT", pad, 0) end
				end
				b:Show()
				prev = b
			end
		end
	end

	-- DISARMED, NOT JUST HIDDEN. A slot left holding a spell is a slot that
	-- casts it the next time the drawer opens shorter than it did before.
	for i = used + 1, self:GetAttribute("slots") or 0 do
		local b = self:GetFrameRef("slot" .. i)
		if b then
			b:Hide()
			b:SetAttribute("type", nil)
			b:SetAttribute("spell", nil)
		end
	end

	if used == 0 then self:Hide() return end

	local extent = pad * 2 + used * size + (used - 1) * gap
	local across = pad * 2 + size

	self:ClearAllPoints()
	if dir == "UP" then
		self:SetWidth(across) self:SetHeight(extent)
		self:SetPoint("BOTTOM", parent, "TOP", 0, 0)
	elseif dir == "DOWN" then
		self:SetWidth(across) self:SetHeight(extent)
		self:SetPoint("TOP", parent, "BOTTOM", 0, 0)
	elseif dir == "LEFT" then
		self:SetWidth(extent) self:SetHeight(across)
		self:SetPoint("RIGHT", parent, "LEFT", 0, 0)
	else
		self:SetWidth(extent) self:SetHeight(across)
		self:SetPoint("LEFT", parent, "RIGHT", 0, 0)
	end

	self:Show()
]==]

--- The click wrap that sends a flyout slot here INSTEAD of to Blizzard.
--
--  `return false` is the important word: without it the wrapped script runs on
--  into SECURE_ACTIONS.action, which calls the SpellFlyout:Toggle that does not
--  work off our buttons.
--
--  IT RETURNS EARLY, WITH NOTHING, FOR EVERY CLICK THAT IS NOT A FLYOUT. Three
--  guards before it touches anything, and no branch that runs on an ordinary
--  action. The first version of this had a tail that ran on every click in the
--  game to close the drawer, and while it was not what broke the bars, a wrap
--  on every action button is not the place to be doing work that is not
--  strictly necessary. The drawer closes from its own slots instead.
--
--  No Keybind translation, unlike LibActionButton's: it binds with a virtual
--  button of that name and we bind with SetOverrideBindingClick(..., "LeftButton"),
--  so a keypress arrives here as an ordinary left click and needs no rewriting.
local FLYOUT_WRAP = [==[
	if self:GetAttribute("type") ~= "action" then return end
	local kind, id = GetActionInfo(self:GetAttribute("action"))
	if kind ~= "flyout" then return end

	local handler = owner:GetFrameRef("aetherFlyout")
	if not handler then return end

	handler:SetAttribute("owner", self)
	handler:RunAttribute("HandleFlyout", id)
	return false
]==]

-- (A post body that shut the drawer after a cast lived here. It is gone until
--  the slots are known to be clickable without it.)

--- The flyout contract, WITHOUT THE TEMPLATE THAT CARRIES IT.
--
--  SpellFlyout:Toggle asks a button for its direction and then asks it to
--  toggle its popup. Blizzard's own buttons answer because
--  ActionButtonTemplate inherits FlyoutButtonTemplate - and that template also
--  declares an OnClick, which replaces the secure action handler and kills the
--  button. Ours are given the answers and none of the scripts.
--
--  Deliberately not Mixin(b, FlyoutButtonMixin) either: that mixin's
--  TogglePopup runs on into UpdateArrowRotation, which reads a self.Arrow the
--  template would have made and we have not. Six small methods that do only
--  what is asked of them, and no arrow of Blizzard's on our glass.
local function ArmFlyoutContract(b)
	b.popupOffset, b.popupCrossAxisSize = -3, 38
	function b:GetPopupDirection() return self.__popupDir or "UP" end
	function b:SetPopupDirection(d) self.__popupDir = d end
	function b:SetPopup(p) self.__popup = p end
	function b:ClearPopup() self.__popup = nil end
	function b:HasPopup() return self.__popup ~= nil end
	function b:IsPopupOpen()
		local p = self.__popup
		return p and p.IsAttachedToButton and p:IsAttachedToButton(self) or false
	end
	function b:TogglePopup() self.__popupOpen = not self.__popupOpen end
	function b:ClosePopup() self.__popupOpen = false end
end

-- REACHABLE FROM THE SUITE. These two are strings, and a string of Lua is
-- something a test can load and run - so the control flow through them is
-- checkable even though the restricted environment they really run in is not
-- reproducible here. What is NOT covered by that is the environment's own
-- rules: what it will let a frame do, and when. The arithmetic and the
-- branching are.
AB.__flyoutWrap    = FLYOUT_WRAP
AB.__flyoutSnippet = FLYOUT_SNIPPET

local flyout

--- Paint one drawer slot. Called from the snippet by name, so it is insecure
--  code doing the one thing the snippet cannot: reading the spell's icon.
local function PaintSlot(b, spellID)
	b.__shown = spellID
	local tex = spellID and GetSpellTexture and GetSpellTexture(spellID)
	if b.icon then
		b.icon:SetTexture(tex or "")
		b.icon:SetShown(tex and true or false)
	end
end

--- The drawer, built once.
local function FlyoutHandler()
	if flyout then return flyout end
	if not _G.SecureHandlerBaseTemplate and not CreateFrame then return nil end

	flyout = CreateFrame("Frame", "AetherUIFlyout", UIParent,
		"SecureHandlerBaseTemplate")
	flyout:SetFrameStrata("DIALOG")
	flyout:SetSize(1, 1)
	flyout:Hide()

	-- The same glass as everything else, and BEHIND the slots rather than
	-- around them: the drawer is one panel with holes in it, not a row of
	-- separate buttons floating over the world.
	flyout.panel = Glass.CreatePanel(flyout, {
		corner = A.db.profile.glass.corner + 2,
		shadow = A.db.profile.glass.shadow,
	})
	flyout.panel:SetAllPoints(flyout)

	-- WHEN IT OPENS AND SHUTS, so the mark on the button can say so. Both
	-- scripts are insecure and only read the parent, which the snippet has
	-- already set - nothing here is protected work.
	local function tellOwner(self2, open)
		local b = self2:GetParent()
		if b and b.flyoutMark and b.__flyoutDir then
			b.__flyoutOpen = open
			FlyoutMark(b, b.__flyoutDir, true, open)
		end
	end
	flyout:SetScript("OnShow", function(self2) tellOwner(self2, true) end)
	flyout:SetScript("OnHide", function(self2) tellOwner(self2, false) end)

	flyout:SetAttribute("slots", 0)
	flyout:SetAttribute("HandleFlyout", FLYOUT_SNIPPET)

	-- THE NUMBERS THE SNIPPET LAYS OUT WITH. It reads them off attributes and
	-- falls back to 36/4/7, which is right only while the slot size is the
	-- default - so a player who had changed it got a drawer built to somebody
	-- else's measurements. The size itself is written by SyncFlyouts, because
	-- it is a setting and settings change.
	flyout:SetAttribute("slotGap", FLYOUT_GAP)
	flyout:SetAttribute("slotInset", FLYOUT_INSET)
	flyout.slots = {}
	return flyout
end

--- Enough drawer slots for the biggest flyout this character knows.
--
--  Built out of combat and never destroyed: creating a secure button while a
--  fight is on is not allowed, and the drawer that could not grow is the
--  drawer that opens empty at exactly the wrong moment.
local function EnsureSlots(n, size)
	local f = FlyoutHandler()
	if not f or InCombatLockdown() then return end

	for i = #f.slots + 1, math.min(n, FLYOUT_MAX) do
		local b = CreateFrame("CheckButton", "AetherUIFlyoutSlot" .. i, f,
			"SecureActionButtonTemplate")
		b:SetSize(size, size)

		-- ONE EDGE, the same one the bar's own slots use. Both were registered
		-- while the click was being chased, on the grounds that one more way
		-- in could not hurt - and it can: the secure handler runs on each
		-- edge, so a press was dispatching the cast twice. It only ever looked
		-- harmless because the first edge hid the drawer and the second landed
		-- on a hidden button.
		b.__clicks = UseKeyDown() and "AnyDown" or "AnyUp"
		b:RegisterForClicks(b.__clicks)

		-- COUNTED, NOT INTERCEPTED. HookScript runs after the template's own
		-- handler instead of replacing it, so this says whether the click
		-- arrives at all without being able to eat it. That distinction is the
		-- measurement: a click that never fires is a different fault from one
		-- that fires and cast nothing.
		b:HookScript("OnClick", function(self2, btn)
			self2.__clicked = (self2.__clicked or 0) + 1
			self2.__lastBtn = btn

			-- NO CLOSE HERE. There was an insecure one for as long as the
			-- secure post body was not firing; it worked out of combat and was
			-- refused in one, because the drawer inherits SecureFrameTemplate
			-- and is explicitly protected. The post body does both now, so a
			-- second route that only covers half the cases is a second thing
			-- to keep true.
		end)
		b:HookScript("OnMouseDown", function(self2)
			self2.__pressed = (self2.__pressed or 0) + 1
		end)
		W.DecorateSlot(b, size)
		b.AetherPaintSlot = PaintSlot

		-- A NAME ON IT. There was no OnEnter on a drawer slot at all - not
		-- broken, never written - so hovering one said nothing while the same
		-- spell in the spell book says plenty.
		--
		-- It doubles as the answer to whether the mouse reaches these at all:
		-- a slot that will not show a tooltip is a slot the cursor is not
		-- getting to, and that is a different problem from a click that does
		-- not cast.
		b:SetScript("OnEnter", function(self2)
			-- The spell as DRAWN, not as cast: a glyphed summon casts 691 and
			-- is called Summon Observer, and the name on the picture is the
			-- one the player is looking for.
			local id = self2.__shown or self2:GetAttribute("spell")
			if not id or not GameTooltip then return end
			GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
			if GameTooltip.SetSpellByID then
				pcall(GameTooltip.SetSpellByID, GameTooltip, tonumber(id))
			end
			GameTooltip:Show()
			self2.__hovered = true
		end)
		b:SetScript("OnLeave", function(self2)
			if GameTooltip then GameTooltip:Hide() end
		end)

		b:Hide()

		-- ...AND THE DRAWER SHUTS BEHIND IT.
		--
		-- A POST body, so the spell goes off first: in the pre body this would
		-- be hiding the frame the click is still travelling through. It was
		-- taken off while the click was being hunted and is back now that the
		-- click is understood - the fault was the spell id, not this.
		--
		-- Secure rather than insecure, because the drawer is a
		-- SecureHandlerBaseTemplate and therefore protected: hiding it from
		-- ordinary Lua works out of combat and silently does not in one, which
		-- is the worst of both.
		-- SHUT AFTER THE CAST. Through the slot's own parent rather than
		-- through `owner`: the drawer IS the header here, so the two are the
		-- same frame, but a post body that names the thing it is standing in
		-- does not depend on which of them the wrap binds. An empty pre body
		-- is a real body that returns nothing, which is what is wanted.
		-- WRAPPED, AND THE FAILURE KEPT. This was a bare pcall, so two
		-- attempts at the secure close failed silently and looked installed -
		-- the drawer stayed open in combat and nothing said why.
		--
		-- `owner` rather than self:GetParent(): owner is the documented name
		-- for the header inside a wrap body, and the header here IS the
		-- drawer. GetParent goes through a handle for no reason.
		if f.WrapScript then
			-- IT LEAVES A MARK. The wrap is accepted - the client says so - and
			-- the drawer still stands open in a fight, so the question is
			-- whether the body RUNS and its Hide is refused, or whether it
			-- never runs at all. Those need opposite fixes and nothing here
			-- could tell them apart.
			--
			-- An attribute, because that is the one thing a snippet can leave
			-- behind for ordinary Lua to read.
			-- THE PRE BODY HAS TO RETURN A MESSAGE OR THE POST BODY IS NEVER
			-- RUN. From SecureHandlers.lua's own wrapper:
			--
			--   if (postBody and message ~= nil) then
			--
			-- The pre handler returns (button, message), and the message is
			-- what arms the post. Returning nil from it - which is what this
			-- did, twice - leaves a wrap the client accepts, reports no error
			-- for, and never fires half of. The diagnostic said ran=nil
			-- against a slot with two counted clicks, which is that line
			-- exactly.
			--
			-- LibActionButton carries the same discovery in a comment:
			-- "we also need some phony message, or it won't work =/".
			local ok, err = pcall(f.WrapScript, f, b, "OnClick",
				[==[ return nil, "aether-flyout" ]==],
				[==[
					owner:SetAttribute("aetherPostRan", 1)
					owner:Hide()
				]==])
			f.__wrapOk, f.__wrapErr = ok, err
		else
			f.__wrapOk, f.__wrapErr = false, "no WrapScript method"
		end

		f.slots[i] = b
		f:SetFrameRef("slot" .. i, b)
	end
	-- ...AND THE ONES ALREADY BUILT FOLLOW THE SETTING. They are made once and
	-- kept, so a drawer built before the slot size was changed stayed at the
	-- old size for the rest of the session - 36 beside a bar of 44, which the
	-- suite caught the moment it compared the two rather than assuming.
	for _, b in ipairs(f.slots) do
		if b:GetWidth() ~= size then
			b:SetSize(size, size)
			if b.edge then b.edge:SetAllPoints(b) end
		end
	end

	if #f.slots > 0 then f:SetAttribute("slots", #f.slots) end
end

--- Load the restricted environment with what this character can summon.
--
--  Out of combat only, and rebuilt whole rather than patched: the table is
--  small, and a partial update is how a drawer ends up offering a pet that
--  was untrained three levels ago.
function AB:SyncFlyouts()
	local f = FlyoutHandler()
	if not f or InCombatLockdown() then return end
	if not GetNumFlyouts or not GetFlyoutInfo or not GetFlyoutSlotInfo then return end

	local cfg = A.Config:Module("actionbars")
	local most, data = 0, { "AETHER_FLYOUTS = newtable()" }

	for i = 1, (GetNumFlyouts() or 0) do
		local id = GetFlyoutID and GetFlyoutID(i)
		if id then
			local _, _, numSlots, isKnown = GetFlyoutInfo(id)
			if isKnown and numSlots and numSlots > 0 then
				data[#data + 1] = ("AETHER_FLYOUTS[%d] = newtable()"):format(id)
				local kept = 0
				for slot = 1, numSlots do
					local spellID, overrideID, slotKnown = GetFlyoutSlotInfo(id, slot)
					if spellID then
						kept = kept + 1
						-- TWO IDS, AND THEY ARE NOT INTERCHANGEABLE.
						--
						-- GetFlyoutSlotInfo returns the spell the character
						-- KNOWS and the spell it currently RESOLVES TO. A
						-- glyphed warlock knows Summon Felhunter, 691, and it
						-- shows as Summon Observer, 112866.
						--
						-- This stored the override and cast it, so the drawer
						-- asked the client to cast a spell nobody has: clicks
						-- arrived - 7 presses, 14 clicks, the diagnostic
						-- counted them - and cast nothing, silently, which is
						-- exactly what casting an unknown spell id does.
						--
						-- Cast the base, draw the override. That is the split
						-- LibActionButton makes too, in as many words.
						data[#data + 1] = ("local s = newtable() "
							.. "AETHER_FLYOUTS[%d][%d] = s "
							.. "s.spell = %d s.icon = %d s.known = %s")
							:format(id, kept, spellID, overrideID or spellID,
								slotKnown and "true" or "false")
					end
				end
				if kept > most then most = kept end
			end
		end
	end

	EnsureSlots(most, cfg.size)
	f:SetAttribute("slotSize", cfg.size)
	f:Execute(table.concat(data, "\n"))
end

--- WHAT THE CLIENT SAYS ABOUT THE DRAWER, with it open.
--
--  Four guesses in, and each one cost a reload and a report. This asks the
--  question instead: it is the same move as AetherProbe, at the scale of one
--  frame. Open a flyout, run /aether bars flyout, and it prints what the
--  client thinks is true about the drawer and its first slot.
--
--  Everything here is a getter. It changes nothing, so it is safe to run in
--  combat or out, and safe to leave in the shipped file.
function AB:DiagnoseFlyout()
	local f = flyout
	if not f then A:Print(L.bars.diagnose_flyout.flyout_drawer_built) return end

	-- INTO THE TEXT BOX, NOT THE CHAT FRAME. /aether errors diag has done this
	-- since it was written, for the reason written there: the chat frame is
	-- the one place an answer cannot be selected. This printed to chat anyway
	-- and cost four screenshots of text that was never copyable.
	--
	-- Chat gets one line saying where to look, because a command that appears
	-- to do nothing is worse than a verbose one.
	local lines = {}
	local function say(...) lines[#lines + 1] = table.concat({ ... }, " ") end
	local function box(fr, label)
		if not fr then say(label .. ": nil") return end
		say(("%s: shown=%s mouse=%s strata=%s level=%s size=%.0fx%.0f alpha=%.2f")
			:format(label,
				tostring(fr:IsShown()),
				tostring(fr.IsMouseEnabled and fr:IsMouseEnabled()),
				tostring(fr.GetFrameStrata and fr:GetFrameStrata()),
				tostring(fr.GetFrameLevel and fr:GetFrameLevel()),
				fr:GetWidth() or 0, fr:GetHeight() or 0,
				fr:GetAlpha() or 0))
	end

	box(f, "drawer")
	local prot, explicit = false, false
	if f.IsProtected then prot, explicit = f:IsProtected() end
	say(("drawer protected=%s explicit=%s  (explicit is what WrapScript"
		.. " demands of a header)"):format(tostring(prot), tostring(explicit)))
	say(("drawer slot wrap: ok=%s err=%s"):format(tostring(f.__wrapOk),
		tostring(f.__wrapErr)))
	-- Kept. One attribute per cast, and it is the difference between reading
	-- one line and spending another evening: ran=nil says the post body is not
	-- firing, which is the failure this whole drawer spent longest on and the
	-- one the API reports no error for.
	say(("post body ran: %s  (nil after a cast means the pre body stopped"
		.. " returning a message)"):format(
			tostring(f:GetAttribute("aetherPostRan"))))
	say("drawer parent: " .. tostring(f:GetParent() and f:GetParent():GetName()))
	box(f.panel, "drawer glass")

	-- EVERY SLOT, not the first one. The last dump said slot 1 had never been
	-- hovered and had seen no clicks, which was true and useless: the drawer
	-- shows five and the one under the cursor was not that one. A measurement
	-- that only looks where the fault is not will keep saying nothing is
	-- wrong.
	local shown, press, click, hover = 0, 0, 0, 0
	for i, sl in ipairs(f.slots or {}) do
		if sl:IsShown() then
			shown = shown + 1
			say(("slot %d: spell=%s level=%s mouse=%s pressed=%s clicked=%s"
				.. " last=%s hovered=%s size=%.0fx%.0f")
				:format(i, tostring(sl:GetAttribute("spell")),
					tostring(sl.GetFrameLevel and sl:GetFrameLevel()),
					tostring(sl.IsMouseEnabled and sl:IsMouseEnabled()),
					tostring(sl.__pressed or 0), tostring(sl.__clicked or 0),
					tostring(sl.__lastBtn), tostring(sl.__hovered == true),
					sl:GetWidth() or 0, sl:GetHeight() or 0))
		end
		press = press + (sl.__pressed or 0)
		click = click + (sl.__clicked or 0)
		hover = hover + ((sl.__hovered == true) and 1 or 0)
	end
	say(("across all slots: shown=%d pressed=%d clicked=%d hovered=%d")
		:format(shown, press, click, hover))

	local b = f.slots and f.slots[1]
	if b then
		say(("slot 1 attrs: type=%s type1=%s unit=%s protected=%s ownOnClick=%s")
			:format(tostring(b:GetAttribute("type")),
				tostring(b:GetAttribute("type1")),
				tostring(b:GetAttribute("unit")),
				tostring(b.IsProtected and select(1, b:IsProtected())),
				tostring(b:GetScript("OnClick") ~= nil)))
	end
	-- THE MARK, READ OFF OUR OWN BUTTON RATHER THAN THROUGH THE DRAWER.
	--
	-- The last version asked f:GetAttribute("owner"), which is what the secure
	-- snippet stored - and a frame put into an attribute from in there comes
	-- back as a restricted HANDLE. A handle answers method calls, which is why
	-- owner:GetName() gave the right name, and hides plain fields, so
	-- owner.flyoutMark read nil whether or not there was one. The measurement
	-- said "never created" about a table it could not see into.
	--
	-- So: walk our own bars, which are ordinary Lua, and report every slot the
	-- client calls a flyout.
	local marked = 0
	for _, bar in ipairs(AB.bars or {}) do
		for _, btn in ipairs(bar.buttons or {}) do
			local act = tonumber(btn:GetAttribute("action")) or 0
			local kind = HasAction(act) and GetActionInfo and GetActionInfo(act)
			if kind == "flyout" then
				marked = marked + 1
				local m = btn.flyoutMark
				if not m then
					say(("%s (action %d): NO MARK - never created")
						:format(btn:GetName() or "?", act))
				else
					local pt, _, _, ox, oy = m:GetPoint(1)
					local r, g, bl, a = 1, 1, 1, 1
					if m.GetVertexColor then r, g, bl, a = m:GetVertexColor() end
					local mx, my = 0, 0
					if m.GetCenter then mx, my = m:GetCenter() end
					local bx, by = 0, 0
					if btn.GetCenter then bx, by = btn:GetCenter() end
					say(("%s (action %d): mark shown=%s tex=%s %.0fx%.0f"
						.. " point=%s(%s,%s) rgba=%.2f,%.2f,%.2f,%.2f")
						:format(btn:GetName() or "?", act,
							tostring(m:IsShown()), tostring(m:GetTexture()),
							m:GetWidth() or 0, m:GetHeight() or 0,
							tostring(pt), tostring(ox), tostring(oy),
							r, g, bl, a))
					-- WHERE IT ACTUALLY IS, against where the button is. A
					-- mark that reports itself shown and sits under the slot's
					-- own rim reads exactly like a mark that is not there.
					say(("  ...mark at %.0f,%.0f  button at %.0f,%.0f"
						.. "  buttonShown=%s btnAlpha=%.2f")
						:format(mx or 0, my or 0, bx or 0, by or 0,
							tostring(btn:IsShown()), btn:GetAlpha() or 0))
				end
				say(("  ...contract=%s dirAttr=%s")
					:format(tostring(btn.SetPopupDirection ~= nil),
						tostring(btn:GetAttribute("aetherFlyoutDirection"))))
			end
		end
	end
	say("flyout slots found on our bars: " .. marked)

	say("mouse focus: " .. tostring(GetMouseFocus and GetMouseFocus()
		and (GetMouseFocus():GetName() or "unnamed")))
	say("slots built: " .. tostring(f.slots and #f.slots)
		.. "  attr slots=" .. tostring(f:GetAttribute("slots"))
		.. "  size=" .. tostring(f:GetAttribute("slotSize")))

	local body = table.concat(lines, "\n")
	if A.Errors and A.Errors.ShowText then
		A.Errors:ShowText((A.Errors.Header and A.Errors:Header() or "")
			.. "flyout\n\n" .. body)
		A:Print(L.bars.diagnose_flyout.flyout_text_window_ctrl)
	else
		-- No error catcher on this build, so chat is all there is. Still
		-- better than saying nothing.
		for _, line in ipairs(lines) do A:Print(line) end
	end
end

--- Point a bar's buttons at the drawer.
--
--  The frame reference goes on the HEADER, because that is the frame the wrap
--  runs as `owner` - and it is set once per bar rather than once per button,
--  which is the only reason this is a function of its own.
local function WireFlyout(bar)
	local f = FlyoutHandler()
	if not f or not bar.header or InCombatLockdown() then return end
	if not bar.header.SetFrameRef then return end
	pcall(bar.header.SetFrameRef, bar.header, "aetherFlyout", f)
end

local function WrapFlyoutClick(bar, b)
	if not bar.header or not bar.header.WrapScript or InCombatLockdown() then return end
	pcall(bar.header.WrapScript, bar.header, b, "OnClick", FLYOUT_WRAP)
end

local function BuildButton(bar, index)
	local cfg = A.Config:Module("actionbars")
	local name = ("AetherUIBar%sButton%d"):format(bar.id, index)

	-- ...AND NOT FlyoutButtonTemplate, WHICH TAKES THE CLICK WITH IT.
	--
	-- This said SecureActionButtonTemplate was "exactly what Blizzard's own
	-- ActionBarButtonTemplate is". It is not. That template is
	-- ActionButtonTemplate plus ActionBarButtonCodeTemplate, and the first of
	-- those inherits FlyoutButtonTemplate - the mixin that answers
	-- GetPopupDirection and owns the popup.
	--
	-- Without it, clicking a flyout slot took the click down with it, because
	-- SecureTemplates hands OUR button to SpellFlyout:Toggle and Toggle asks
	-- the button which way to open:
	--
	--   SpellFlyout.lua:235: attempt to call a nil value ('GetPopupDirection')
	--
	-- Summon Demon, Call Pet, the mage's portals. One shared file, so both
	-- clients, since the bars were written - it only surfaced now because
	-- vanilla has few flyouts and Mists gives one to everybody.
	--
	-- INHERITING IT COST EVERY BUTTON ITS ACTION. Flyout.xml declares
	--
	--   <OnClick method="Flyout_OnClick"/>
	--
	-- on that template, and an inherited OnClick replaces the one
	-- SecureActionButtonTemplate installs - so every button on every bar
	-- stopped doing anything at all, by click or by keybind, in combat and
	-- out, while the single flyout slot went on working because toggling a
	-- popup is exactly what Flyout_OnClick does.
	--
	-- So the contract is supplied directly instead, below: the methods
	-- SpellFlyout:Toggle asks for, and not one script.
	--
	-- The checked state still carries "this toggle is on"; that part was right.
	local b = CreateFrame("CheckButton", name, bar.header,
		"SecureActionButtonTemplate")
	ArmFlyoutContract(b)
	b:SetSize(cfg.size, cfg.size)
	b:RegisterForClicks(UseKeyDown() and "AnyDown" or "AnyUp")
	b:RegisterForDrag("LeftButton")

	W.DecorateSlot(b, cfg.size)

	-- Any stock CheckButton artwork would draw over the glass. Note that
	-- Button:SetNormalTexture(nil) *throws* on Classic Era ("bad argument #2 to
	-- '?': Usage: Texture(asset [, blendMode])") - it will not accept nil the way
	-- Retail does. SecureActionButtonTemplate ships no artwork anyway, so ask for
	-- each region and hide whatever actually exists.
	for _, getter in ipairs({ "GetNormalTexture", "GetHighlightTexture",
		"GetPushedTexture", "GetCheckedTexture", "GetDisabledTexture" }) do
		if b[getter] then
			local ok, tex = pcall(b[getter], b)
			if ok and tex then tex:SetAlpha(0); tex:Hide() end
		end
	end

	local hotkey = W.Text(b, "keybind", "RIGHT")
	hotkey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, -4)
	W.Color(hotkey, Palette.c.text)
	b.hotkey = hotkey

	-- Cooldown sweep. SetSwipeTexture with our rounded-square mask is what keeps
	-- the sweep inside the slot silhouette instead of clipping it into a square.
	local cd = CreateFrame("Cooldown", name .. "Cooldown", b, "CooldownFrameTemplate")
	cd:SetAllPoints(b)
	pcall(cd.SetSwipeTexture, cd, Media.texture.slotMask)
	pcall(cd.SetSwipeColor, cd, 0.02, 0.01, 0.06, 0.72)
	pcall(cd.SetDrawEdge, cd, false)
	pcall(cd.SetDrawBling, cd, false)
	-- We draw our own countdown in Outfit; Blizzard's would be in the game font.
	pcall(cd.SetHideCountdownNumbers, cd, true)
	b.cooldown = cd

	local cdText = W.Text(b, "stack", "CENTER")
	cdText:SetPoint("CENTER", b, "CENTER", 0, 0)
	W.Color(cdText, Palette.c.text)
	b.cdText = cdText

	ApplyButtonFonts(b, cfg.size)

	b:SetAttribute("type", "action")
	b:SetAttribute("aetherIndex", index)
	-- Written once, here, and never again. That is the whole design: no state
	-- driver, no restricted snippet, nothing to go wrong mid-combat, and the
	-- attribute Lua reads to paint the icon is the same one the click uses.
	b:SetAttribute("action", (bar.page - 1) * NUM_ACTIONS_PER_PAGE + index)
	ApplyPickupModifier(b)

	-- Non-secure scripts are fine on a secure button as long as they do not try
	-- to change what it casts.
	b:SetScript("OnEnter", function(self)
		if not A.Config:Module("actionbars").tooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetAction(ButtonAction(self))
		self.icon:SetVertexColor(1.15, 1.15, 1.15)
	end)
	b:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		UpdateUsable(self)
	end)
	b:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		local cfgNow = A.Config:Module("actionbars")
		if cfgNow.lockButtons and not IsModifiedClick("PICKUPACTION") then return end
		PickupAction(ButtonAction(self))
		UpdateAllOn(self)
	end)
	b:SetScript("OnReceiveDrag", function(self)
		if InCombatLockdown() then return end
		PlaceAction(ButtonAction(self))
		UpdateAllOn(self)
	end)

	-- A FLYOUT SLOT GOES TO OUR DRAWER RATHER THAN TO BLIZZARD'S.
	--
	-- Back on, with the cause of the dead bars found and fixed elsewhere - it
	-- was the inherited template's OnClick, not this - and with this rewritten
	-- to return early and empty-handed for every click that is not a flyout.
	WrapFlyoutClick(bar, b)

	return b
end

-- ---------------------------------------------------------------------------
-- bar construction
-- ---------------------------------------------------------------------------

--- Stance and pet buttons come from Blizzard's own templates.
--
--  Not laziness: those templates carry the secure click behaviour for actions
--  that are protected on this client, and reproducing it by hand means guessing
--  at attribute names that are not written down anywhere. We take the button and
--  drive the *look* ourselves - stock artwork hidden, our glass chrome on top -
--  which is the same split the action buttons already use.
local function BuildSpecialButton(bar, index, template)
	local cfg = A.Config:Module("actionbars")
	local name = ("AetherUIBar%sButton%d"):format(bar.id, index)

	local ok, b = pcall(CreateFrame, "CheckButton", name, bar.header, template)
	if not ok or not b then return nil end

	b:SetID(index)
	b:SetSize(cfg.size, cfg.size)
	pcall(b.RegisterForClicks, b, UseKeyDown() and "AnyDown" or "AnyUp")

	-- The template's regions are named after the button and would draw over the
	-- glass. Hide rather than remove: the template's own code may still reference
	-- them, and a nil where it expects a texture is an error you would only ever
	-- see on a druid.
	for _, suffix in ipairs({ "Icon", "NormalTexture2", "Cooldown", "AutoCastable",
		"Shine", "Flash", "HotKey", "Count", "Name", "Border", "FloatingBG" }) do
		local region = _G[name .. suffix]
		if region then
			if region.SetAlpha then region:SetAlpha(0) end
			if region.Hide then pcall(region.Hide, region) end
		end
	end
	for _, getter in ipairs({ "GetNormalTexture", "GetHighlightTexture",
		"GetPushedTexture", "GetCheckedTexture", "GetDisabledTexture" }) do
		if b[getter] then
			local gok, tex = pcall(b[getter], b)
			if gok and tex then tex:SetAlpha(0); tex:Hide() end
		end
	end

	W.DecorateSlot(b, cfg.size)

	local cd = CreateFrame("Cooldown", name .. "Sweep", b, "CooldownFrameTemplate")
	cd:SetAllPoints(b)
	if cd.SetDrawEdge then cd:SetDrawEdge(false) end
	if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
	if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, Media.texture.slotMask) end
	if cd.SetSwipeColor then pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0.65) end
	b.cd = cd

	local cdText = W.Text(b, "stack", "CENTER")
	cdText:SetPoint("CENTER", b, "CENTER", 0, 0)
	W.Color(cdText, Palette.c.text)
	b.cdText = cdText

	b.hotkey = W.Text(b, "keybind", "RIGHT")
	b.hotkey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3, -3)

	ApplyButtonFonts(b, cfg.size)

	b.aether = { kind = bar.kind, index = index }

	-- TOOLTIP BESIDE THE BUTTON, like every other button on a bar.
	--
	-- An ordinary action button sets its own owner and gets a tooltip next
	-- to itself. A pet or stance button carries the client's OnEnter, which
	-- calls GameTooltip_SetDefaultAnchor - so its tooltip went wherever the
	-- player had put the anchor, and the pet bar was the one bar in the
	-- interface that answered a different question from the rest.
	--
	-- Flagged rather than re-implemented: the client's handler does the
	-- flyout, the quick-keybind and the tooltip content, and none of that is
	-- ours to own. Tooltips reads the flag when the anchor is applied.
	b.__aetherTipBesideOwner = true
	return b
end

-- ---------------------------------------------------------------------------
-- stance and pet updates
-- ---------------------------------------------------------------------------

local function UpdateStanceButton(b)
	local id = b.aether.index
	-- Before the guard, not after: on a client with no stance API at all the
	-- button is still built, still on screen, and still needs a rim of the
	-- skin somebody is actually running.
	PlainRim(b)
	if not GetShapeshiftFormInfo then return end

	local texture, isActive, isCastable = GetShapeshiftFormInfo(id)
	if not texture then
		b.icon:Hide()
		b:SetAlpha(A.Config:Module("actionbars").emptyAlpha or 0.25)
		PlainRim(b)
		return
	end

	b:SetAlpha(1)
	b.icon:Show()
	b.icon:SetTexture(texture)
	b.icon:SetDesaturated(not isCastable)
	b:SetActive(isActive and true or false, Palette.c.accent)

	if GetShapeshiftFormCooldown then
		local start, duration, enable = GetShapeshiftFormCooldown(id)
		if start and duration and duration > 0 and enable and enable > 0 then
			b.cd:SetCooldown(start, duration)
			b._cdEnd = start + duration
		else
			b.cd:SetCooldown(0, 0)
			b._cdEnd = nil
			b.cdText:SetText("")
		end
	end
end

local function UpdatePetButton(b)
	local id = b.aether.index
	if not GetPetActionInfo then return end

	local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID =
		GetPetActionInfo(id)

	-- A "token" action reports the *name of a global* rather than a texture path.
	local icon = texture
	if isToken and type(texture) == "string" then icon = _G[texture] or texture end

	-- THE TOOLTIP IS OURS TO SET, and the name was being thrown away.
	--
	-- The button comes from PetActionButtonTemplate, so it already carries the
	-- client's own OnEnter - but that reads `self.tooltipName` and RETURNS if it
	-- is not there. The only thing that sets it is PetActionBarMixin:Update,
	-- walking Blizzard's own buttons, and ours replaced those. So every pet
	-- button had a working tooltip handler that quietly did nothing.
	--
	-- The name is a global's NAME for a token action, exactly as the icon is;
	-- Blizzard's own Update makes the same substitution two lines apart.
	if isToken and type(name) == "string" then
		b.tooltipName = _G[name] or name
	else
		b.tooltipName = name
	end

	-- The subtext - "Basic Attack", the rank of a trained ability - arrives with
	-- the spell rather than with the action, so it is asked for asynchronously
	-- the way the client asks. Absent, the tooltip is simply a line shorter.
	b.tooltipSubtext = nil
	if spellID and Spell and Spell.CreateFromSpellID then
		local ok, spell = pcall(Spell.CreateFromSpellID, Spell, spellID)
		if ok and spell and spell.ContinueWithCancelOnSpellLoad then
			pcall(spell.ContinueWithCancelOnSpellLoad, spell, function()
				b.tooltipSubtext = spell:GetSpellSubtext()
			end)
		end
	end

	local cfg = A.Config:Module("actionbars")
	if not icon then
		b.icon:Hide()
		b:SetActive(false)
		b:SetAlpha(cfg.emptyAlpha or 0.25)
		PlainRim(b)
		return
	end

	b:SetAlpha(1)
	b.icon:Show()
	b.icon:SetTexture(icon)
	local usable = (not GetPetActionsUsable) or GetPetActionsUsable()
	b.icon:SetDesaturated(not usable)
	b:SetActive(isActive and true or false, Palette.c.accent)

	-- Auto-cast reads on the rim we already own rather than as a second spinning
	-- overlay on top of the glass.
	local c = Palette.c
	if autoCastEnabled then
		b.edge:SetVertexColor(c.xp[2][1], c.xp[2][2], c.xp[2][3], 1)
	elseif autoCastAllowed then
		b.edge:SetVertexColor(c.accent[1], c.accent[2], c.accent[3], 0.55)
	else
		b.edge:SetVertexColor(c.glassEdge[1], c.glassEdge[2], c.glassEdge[3],
			c.glassEdge[4] or 1)
	end

	if GetPetActionCooldown then
		local start, duration, enable = GetPetActionCooldown(id)
		if start and duration and duration > 0 and enable and enable > 0 then
			b.cd:SetCooldown(start, duration)
			b._cdEnd = start + duration
		else
			b.cd:SetCooldown(0, 0)
			b._cdEnd = nil
			b.cdText:SetText("")
		end
	end
end

local function UpdateSpecialButton(b)
	if b.aether.kind == "pet" then UpdatePetButton(b) else UpdateStanceButton(b) end
	UpdateBinding(b)
end

-- ---------------------------------------------------------------------------
-- bar construction
-- ---------------------------------------------------------------------------

--- Rows is the honest control and columns fall out of it. "Three rows of ten"
--  giving 4/4/2 is what people mean; "four columns of ten" gives the same shape
--  but makes you do the arithmetic first.
local function LayoutBar(bar)
	local cfg = A.Config:Module("actionbars")
	local n = #bar.buttons
	if n == 0 then
		-- A bar with nothing in it still needs a body while you are placing it -
		-- the mover handle takes its size from the frame, and you cannot grab a
		-- 1x1 square. One button's worth is enough to aim at.
		local size = math.max(16, math.floor((bar.cfg.size or cfg.size) + 0.5))
		bar.dock:SetSize(size + cfg.padding * 2, size + cfg.padding * 2)
		bar.rows, bar.cols = 0, 0
		return
	end

	local rows = math.max(1, math.min(bar.cfg.rows or 1, n))
	local cols = math.ceil(n / rows)
	rows = math.ceil(n / cols)

	local size = math.max(16, math.floor((bar.cfg.size or cfg.size) + 0.5))
	local gap, pad = cfg.spacing, cfg.padding

	for i, b in ipairs(bar.buttons) do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		-- An adopted Blizzard button is protected; moving it mid-fight is not
		-- ours to do. It keeps its last position until the fight ends.
		if not (b.__aetherAdopted and InCombatLockdown()) then
			pcall(b.SetSize, b, size, size)
			pcall(b.ClearAllPoints, b)
			pcall(b.SetPoint, b, "TOPLEFT", bar.header, "TOPLEFT",
				col * (size + gap), -row * (size + gap))
		end
		if b.glow then b.glow:SetSize(size * 2, size * 2) end
		if not b.__aetherAdopted then ApplyButtonFonts(b, size) end
	end

	bar.header:SetSize(cols * size + (cols - 1) * gap, rows * size + (rows - 1) * gap)
	bar.dock:SetSize(bar.header:GetWidth() + pad * 2, bar.header:GetHeight() + pad * 2)
	bar.header:ClearAllPoints()
	bar.header:SetPoint("CENTER", bar.dock, "CENTER", 0, 0)
	bar.rows, bar.cols = rows, cols
end

--- Blizzard buttons we host rather than replace.
--
--  Both of these fire protected actions - TaxiRequestEarlyLanding on the taxi
--  button, whatever a quest has bound to the extra action - so there is no
--  recreating them the way the action buttons are recreated. We adopt the real
--  frame, put it on a glass dock and leave its click behaviour alone.
--
--  Each entry is a list of names to try, because the same button has been
--  renamed across flavours and only one of them will exist.
--- `relevant` is the load-bearing part, and the first version not having it is
--  what put an empty gold square on screen permanently.
--
--  Reparenting a frame does not change its own shown state. Blizzard's taxi
--  button is :Show()n from the start and is invisible only because the bar it
--  hangs off is hidden - so the moment we adopted it onto a dock of our own it
--  appeared, empty, and stayed. Asking the *game* whether the button has a job
--  to do is the only reliable signal; the frame's own IsShown is not one.
local ADOPTED = {
	{
		label = "taxi",
		names = { "VehicleLeaveButton", "MainMenuBarVehicleLeaveButton" },
		relevant = function()
			if UnitOnTaxi and UnitOnTaxi("player") then return true end
			if CanExitVehicle and CanExitVehicle() then return true end
			return false
		end,
	},
	{
		label = "extra",
		names = { "ExtraActionButton1" },
		relevant = function()
			return HasExtraActionBar and HasExtraActionBar() or false
		end,
	},
}

--- Take over one of Blizzard's own buttons.
--
--  Reparenting a protected frame is itself protected, so this only ever runs out
--  of combat; the caller replays it on PLAYER_REGEN_ENABLED. Everything is
--  guarded because the whole point is that we do not know which of these names
--  this client actually has.
local function AdoptButton(bar, spec)
	local f
	for _, name in ipairs(spec.names) do
		if _G[name] then f = _G[name] break end
	end
	if not f then return nil end
	if InCombatLockdown() then return nil end

	local cfg = A.Config:Module("actionbars")
	if not pcall(f.SetParent, f, bar.header) then return nil end
	pcall(f.ClearAllPoints, f)
	pcall(f.SetSize, f, cfg.size, cfg.size)

	-- The extra action button wears a large ornate ring that reads as a foreign
	-- object on the glass. Take it off if it is there; keep the icon.
	for _, key in ipairs({ "style", "Style", "NormalTexture" }) do
		local region = f[key]
		if region and region.SetTexture then pcall(region.SetTexture, region, nil) end
		if region and region.Hide then pcall(region.Hide, region) end
	end
	local ring = _G[(f.GetName and f:GetName() or "") .. "Style"]
	if ring and ring.Hide then pcall(ring.Hide, ring) end

	-- Its own textures as well as its named regions: the gold square that ended
	-- up floating on screen was the button's plain NormalTexture, left behind
	-- after the ornate ring was taken off.
	for _, getter in ipairs({ "GetNormalTexture", "GetHighlightTexture",
		"GetPushedTexture", "GetCheckedTexture", "GetDisabledTexture" }) do
		if f[getter] then
			local gok, tex = pcall(f[getter], f)
			if gok and tex then
				pcall(tex.SetAlpha, tex, 0)
				pcall(tex.Hide, tex)
			end
		end
	end

	-- Adopted down. Nothing here is on screen until the game says it has a job.
	pcall(f.Hide, f)
	f.__aetherAdopted = true
	f.__aetherWanted = false
	return f
end

local function BuildBar(barCfg)
	local bar = {
		id = tostring(barCfg.id),
		cfg = barCfg,
		kind = barCfg.kind or "action",
		page = math.max(1, math.min(barCfg.page or 1, MAX_ACTION_PAGE)),
		buttons = {},
	}

	bar.dock = Glass.CreatePanel(UIParent, {
		corner = A.db.profile.glass.corner + 2,
		shadow = A.db.profile.glass.shadow,
	})

	-- Still a secure handler frame, but now only as the owner of the override
	-- bindings and, for the pet bar, a visibility driver. Nothing pages.
	bar.header = CreateFrame("Frame", ("AetherUIBar%sHeader"):format(bar.id),
		bar.dock, "SecureHandlerStateTemplate")

	-- The drawer, reachable from this bar's snippets. Once per bar: the wrap
	-- below runs with the header as `owner`, and a frame reference is a
	-- property of the header rather than of each button on it.
	WireFlyout(bar)

	if bar.kind == "extra" then
		bar.specs = {}
		for _, spec in ipairs(ADOPTED) do
			local b = AdoptButton(bar, spec)
			if b then
				bar.buttons[#bar.buttons + 1] = b
				bar.specs[#bar.buttons] = spec
				bar.adopted = (bar.adopted or 0) + 1
			end
		end
		LayoutBar(bar)
		-- Down until the game says otherwise. The ticker brings it up.
		bar.dock:Hide()
		bar.__shown = false
		return bar
	end

	for i = 1, SlotCount(barCfg) do
		local b
		if bar.kind == "pet" then
			b = BuildSpecialButton(bar, i, "PetActionButtonTemplate")
		elseif bar.kind == "stance" then
			b = BuildSpecialButton(bar, i, "StanceButtonTemplate")
		else
			b = BuildButton(bar, i)
		end
		if b then bar.buttons[#bar.buttons + 1] = b end
	end

	-- The pet bar comes and goes with the pet, and that has to keep working in
	-- combat - so it is a secure visibility driver rather than a Lua Show/Hide.
	if bar.kind == "pet" and RegisterStateDriver then
		pcall(RegisterStateDriver, bar.dock, "visibility", "[pet] show; hide")
		bar.visibilityDriven = true
	end

	LayoutBar(bar)
	return bar
end

--- The adopted buttons decide for themselves when they are relevant - Blizzard
--  shows the taxi button when you board a flight path and hides it when you land
--  - so the dock follows them rather than the other way round.
local function UpdateExtraBars()
	for _, bar in ipairs(AB.bars) do
		if bar.kind == "extra" then
			-- Late adoption: ExtraActionButton1 in particular may not exist until
			-- its addon loads, so keep trying until we have them.
			if (bar.adopted or 0) < #ADOPTED and not InCombatLockdown() then
				for _, spec in ipairs(ADOPTED) do
					local already = false
					for _, b in ipairs(bar.buttons) do
						for _, n in ipairs(spec.names) do
							if _G[n] and b == _G[n] then already = true end
						end
					end
					if not already then
						local b = AdoptButton(bar, spec)
						if b then
							bar.buttons[#bar.buttons + 1] = b
							bar.specs = bar.specs or {}
							bar.specs[#bar.buttons] = spec
							bar.adopted = (bar.adopted or 0) + 1
							LayoutBar(bar)
						end
					end
				end
			end

			-- `if not preview`, not an early return: this loop has other bars to
			-- get to, and Lua 5.1 has no continue.
			if not bar.__preview then
				-- Ask the game, not the frame. And only act on a change: this runs
				-- ten times a second and Show/Hide is not free on a protected frame.
				local any = false
				for i, b in ipairs(bar.buttons) do
					local spec = bar.specs and bar.specs[i]
					local want = (spec and spec.relevant) and spec.relevant() or false
					if want then any = true end
					if b.__aetherWanted ~= want and not InCombatLockdown() then
						b.__aetherWanted = want
						if want then pcall(b.Show, b) else pcall(b.Hide, b) end
					end
				end
				if any ~= bar.__shown then
					bar.__shown = any
					if any then bar.dock:Show() else bar.dock:Hide() end
				end
			end
		end
	end
end
AB.UpdateExtraBars = UpdateExtraBars

-- ---------------------------------------------------------------------------
-- keybinds
-- ---------------------------------------------------------------------------

--- Read the key(s) bound to Blizzard's binding for this slot and redirect them at
--  our button. We cannot lean on Blizzard's own handling because its bars are
--  hidden and its binding functions act on those specific buttons.
function AB:ApplyBindings()
	if InCombatLockdown() then
		AB._bindingsPending = true
		return
	end
	AB._bindingsPending = nil

	-- Theirs first, then ours. Blizzard's bar re-points the ACTIONBUTTON keys at
	-- its own buttons whenever it updates, and whoever writes last wins.
	--
	-- Reached through the module table rather than as an upvalue: the helper is
	-- defined further down the file, so the local does not exist yet at the point
	-- this function is compiled.
	if AB.ClearBlizzardBindings then AB.ClearBlizzardBindings() end

	for _, bar in ipairs(AB.bars) do
		ClearOverrideBindings(bar.header)

		local prefix = BindingPrefix(bar.cfg)
		for i, b in ipairs(bar.buttons) do
			if not prefix then break end
			local bindingName = prefix .. i
			local key1, key2 = GetBindingKey(bindingName)
			b._keyText = key1 or key2

			for _, key in ipairs({ key1, key2 }) do
				if key and key ~= "" then
					SetOverrideBindingClick(bar.header, false, key, b:GetName(), "LeftButton")
				end
			end
			UpdateBinding(b)
		end
	end
end

-- ---------------------------------------------------------------------------
-- keybind mode
--
-- Hover a button, press a key, done. The key goes into *Blizzard's* binding set
-- against the binding name that bar uses - ACTIONBUTTON3, MULTIACTIONBAR1BUTTON7,
-- our own AETHERUI_BAR2BUTTON1 - and ApplyBindings then points it at our button
-- exactly as it does for a key you set in Blizzard's own panel.
--
-- Storing keys in our saved variables would have been less work and worse: they
-- would not survive the addon being disabled, they would not show up in the
-- keybinding panel, and there would be two places a key could come from.
-- ---------------------------------------------------------------------------

local IGNORED_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, UNKNOWN = true,
}

--- Build the binding string for a key press, with whatever modifiers are held.
local function KeyString(key)
	if not key or IGNORED_KEYS[key] then return nil end
	local prefix = ""
	if IsAltKeyDown() then prefix = prefix .. "ALT-" end
	if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
	if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
	return prefix .. key
end

local function BindingNameFor(bar, index)
	local prefix = BindingPrefix(bar.cfg)
	return prefix and (prefix .. index) or nil
end

local function BindOverlayText(overlay)
	local name = overlay.bindingName
	if not name then
		overlay.text:SetText("-")
		W.Color(overlay.text, Palette.c.textFaint)
		return
	end
	local key = GetBindingKey(name)
	overlay.text:SetText(key and ShortKey(key) or "?")
	W.Color(overlay.text, key and Palette.c.text or Palette.c.textFaint)
end

local function SetBindingTo(overlay, keyString)
	if InCombatLockdown() then
		A:Print(A.Bad(L.common.can_t_change_bindings))
		return
	end
	local name = overlay.bindingName
	if not name then return end

	-- Take the key off whatever had it, or you end up with two owners and the
	-- one the client picks is not the one you meant.
	local previous = GetBindingAction and GetBindingAction(keyString)
	if previous and previous ~= "" and previous ~= name then
		A:Print((A.Dim("%s taken from %s")):format(ShortKey(keyString), previous))
	end

	if not SetBinding(keyString, name) then
		A:Print(A.Bad(L.bars.set_binding_to.key_can_t_bound))
		return
	end
	A:Print((A.Good("%s") .. " -> %s"):format(ShortKey(keyString), name))
	if SaveBindings and GetCurrentBindingSet then
		pcall(SaveBindings, GetCurrentBindingSet())
	end
	AB:ApplyBindings()
	AB:RefreshAll()
	for _, o in ipairs(AB.bindOverlays or {}) do BindOverlayText(o) end
end

local function ClearBindingOn(overlay)
	if InCombatLockdown() then
		A:Print(A.Bad(L.common.can_t_change_bindings))
		return
	end
	local name = overlay.bindingName
	if not name then return end
	local k1, k2 = GetBindingKey(name)
	for _, k in ipairs({ k1, k2 }) do
		if k then SetBinding(k, nil) end
	end
	if SaveBindings and GetCurrentBindingSet then
		pcall(SaveBindings, GetCurrentBindingSet())
	end
	AB:ApplyBindings()
	AB:RefreshAll()
	for _, o in ipairs(AB.bindOverlays or {}) do BindOverlayText(o) end
end

--- Stop a keypress here rather than letting it reach the binding system too.
--
--  Has to be called from inside the handler that is dealing with the press: the
--  client resets propagation for every keyboard event, so a single call on
--  OnEnter covers exactly nothing.
local function Swallow(frame, propagate)
	if not frame.SetPropagateKeyboardInput then return end
	pcall(frame.SetPropagateKeyboardInput, frame, propagate and true or false)
end

local function BuildBindOverlay(button, bindingName)
	local o = Glass.CreatePanel(UIParent, { corner = 6, fill = "glassStrong" })
	o:SetFrameStrata("FULLSCREEN_DIALOG")
	o:SetAllPoints(button)
	o:EnableMouse(true)
	o:EnableMouseWheel(true)
	o:Hide()

	o.button, o.bindingName = button, bindingName

	o.text = W.Text(o, "keybind", "CENTER")
	o.text:SetPoint("CENTER")

	local c = Palette.c
	o:SetFillColor({ c.accent[1], c.accent[2], c.accent[3], 0.30 })
	o:SetEdgeColor({ c.accent[1], c.accent[2], c.accent[3], 0.9 })

	-- Keyboard focus follows the mouse: enable it on enter, drop it on leave, so
	-- exactly one overlay is listening and it is the one under the cursor.
	o:SetScript("OnEnter", function(self)
		self:EnableKeyboard(true)
		Swallow(self)
		self:SetEdgeColor({ c.accentDeep[1], c.accentDeep[2], c.accentDeep[3], 1 })
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.bindingName or "no binding", 1, 1, 1)
		GameTooltip:AddLine("Press a key to bind it here.", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Escape clears it. Right-click leaves bind mode.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	o:SetScript("OnLeave", function(self)
		self:EnableKeyboard(false)
		Swallow(self, true)
		self:SetEdgeColor({ c.accent[1], c.accent[2], c.accent[3], 0.9 })
		GameTooltip:Hide()
	end)

	-- Swallowed *here*, not only on enter, and this is the whole of the bug that
	-- made bind mode look broken. `SetPropagateKeyboardInput` is reset by the
	-- client for each keyboard event, so setting it once on OnEnter left the
	-- press going to our handler *and* on to the binding system. Binding ctrl-1
	-- onto bar 3 therefore also fired whatever ctrl-1 already did - hence "it
	-- says I need a target" - and on bars 1 and 2, where the old binding had
	-- already been cleared, it just felt like the first press was swallowed.
	o:SetScript("OnKeyDown", function(self, key)
		Swallow(self)
		if key == "ESCAPE" then ClearBindingOn(self) return end
		local s = KeyString(key)
		if s then SetBindingTo(self, s) end
	end)

	-- The key-up half of the same press would otherwise propagate on its own.
	o:SetScript("OnKeyUp", function(self) Swallow(self) end)

	o:SetScript("OnMouseDown", function(self, button_)
		if button_ == "RightButton" then
			AB:SetBindMode(false)
			return
		end
		-- Mouse buttons past the first two are perfectly good keys.
		if button_ == "MiddleButton" or button_ == "Button4" or button_ == "Button5" then
			local s = KeyString(button_ == "MiddleButton" and "BUTTON3"
				or (button_ == "Button4" and "BUTTON4" or "BUTTON5"))
			if s then SetBindingTo(self, s) end
		end
	end)

	o:SetScript("OnMouseWheel", function(self, delta)
		local s = KeyString(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
		if s then SetBindingTo(self, s) end
	end)

	return o
end

--- Bind mode covers every button on every visible bar with a target you can
--  hover and type at.
function AB:SetBindMode(on)
	if on and InCombatLockdown() then
		A:Print(A.Bad(L.bars.set_bind_mode.can_t_rebind_combat))
		return
	end

	AB.bindOverlays = AB.bindOverlays or {}
	AB.bindMode = on and true or false

	if not on then
		for _, o in ipairs(AB.bindOverlays) do
			o:EnableKeyboard(false)
			Swallow(o, true)
			o:Hide()
		end
		A:Print(L.bars.set_bind_mode.keybind_mode_off)
		return
	end

	local n = 0
	for _, bar in ipairs(AB.bars) do
		if bar.cfg.enabled ~= false then
			for i, b in ipairs(bar.buttons) do
				-- Adopted Blizzard buttons keep whatever binding Blizzard gave
				-- them; they are not ours to rebind.
				if not b.__aetherAdopted then
					n = n + 1
					local o = AB.bindOverlays[n]
					if not o then
						o = BuildBindOverlay(b, BindingNameFor(bar, i))
						AB.bindOverlays[n] = o
					end
					o.button, o.bindingName = b, BindingNameFor(bar, i)
					o:SetAllPoints(b)
					BindOverlayText(o)
					o:Show()
				end
			end
		end
	end
	for i = n + 1, #AB.bindOverlays do AB.bindOverlays[i]:Hide() end

	-- Bind mode is entered from a slash command or the options panel, so the
	-- cursor is wherever it already was. If that happens to be over a button, no
	-- OnEnter will ever fire and that overlay never takes keyboard focus - which
	-- is the "I had to hover off and back on again before it would take" report.
	-- Hand focus to whatever is already underneath.
	for i = 1, n do
		local o = AB.bindOverlays[i]
		if o:IsShown() and o:IsMouseOver() then
			local enter = o:GetScript("OnEnter")
			if enter then enter(o) end
			break
		end
	end

	A:Print(A.F(L.bars.set_bind_mode.keybind_mode_s_hover,
		A.Good(L.common.on)) .. "  "
		.. A.Dim(L.bars.set_bind_mode.escape_clears_right_click))
end

function AB:ToggleBindMode()
	AB:SetBindMode(not AB.bindMode)
end

-- ---------------------------------------------------------------------------
-- Blizzard bars
-- ---------------------------------------------------------------------------

local hider
local function GetHider()
	if not hider then
		hider = CreateFrame("Frame", ADDON .. "ActionHider", UIParent)
		hider:Hide()
	end
	return hider
end

--- Frames we try to remove. Exposed so /aether diag can report on them.
--- Classic Era 1.15 runs the *modern* action bar system - the UIParent child
--  list has MainActionBar, PetActionBar, PossessActionBar and an
--  EditModeManagerFrame, not the old MainMenuBar layout. The legacy names are
--  kept below because they still exist on some builds and cost nothing when
--  they don't; "absent" in /aether diag just means that one wasn't here.
AB.blizzardFrames = {
	-- 1.15 / modern
	"MainActionBar", "MicroMenu", "MicroMenuContainer", "BagsBar",
	"StatusTrackingBarManager", "MainStatusTrackingBarContainer",
	-- legacy
	"MainMenuBar", "MainMenuBarArtFrame", "MainMenuBarArtFrameBackground",
	"MainMenuExpBar", "ReputationWatchBar", "MicroButtonAndBagsBar",
	"ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPageNumber",
	"OverrideActionBar",
	-- NOT MainMenuBarVehicleLeaveButton. Classic Era has no vehicles, but it
	-- reuses that button for "land at the next flight master" on a taxi, and
	-- TaxiRequestEarlyLanding is protected - so there is no recreating it. It is
	-- adopted onto the "extra" bar instead. Hiding it cost you the only way off
	-- a flight path early.
	-- multibars (same names either way)
	"MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
	-- stance and pet. Both have replacements now, so both go. Possess (mind
	-- control) keeps Blizzard's bar: it is rare, it is temporary, and there is
	-- no vehicle UI on this client for it to share code with.
	"StanceBar", "StanceBarFrame",
	"PetActionBar", "PetActionBarFrame",
}

--- Blizzard's own action buttons, which outlive their bars.
--
--  Hiding the containers is not enough and this is the bug it caused: the dock
--  showed page 1 while pressing the key fired page 6. Two things were still
--  alive underneath us.
--
--  * ActionButton2 itself. It is still a working secure button, and it resolves
--    its action from the live GetActionBarPage() - so whenever the key reached
--    it instead of ours, you got whatever page Blizzard thought it was on.
--  * MainActionBar's own *override* bindings. Classic Era runs the modern bar
--    code, whose ActionBarMixin re-points the ACTIONBUTTON keys at its own
--    buttons whenever it updates. Last writer wins, and it was not always us.
--
--  Bartender4 does exactly this on this client: Hide, UnregisterAllEvents, and
--  statehidden so the secure show/hide drivers leave them down for good.
local BLIZZARD_BUTTON_PREFIXES = {
	"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
	"MultiBarLeftButton", "MultiBarRightButton",
	"PetActionButton", "StanceButton", "ShapeshiftButton",
}

--- Frames whose override bindings must be cleared, not merely hidden.
local BLIZZARD_BINDING_OWNERS = {
	"MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
	"MultiBarLeft", "MultiBarRight", "OverrideActionBar",
}

--- Blizzard marks some frames "forbidden"; *any* method call on one raises
--  "calling '?' on bad self (Usage: local name = self:GetName())". Check before
--  touching anything, and treat a failed check as forbidden.
local function Forbidden(f)
	if not f or not f.IsForbidden then return false end
	local ok, forbidden = pcall(f.IsForbidden, f)
	return (not ok) or forbidden
end

local function Banish(frameName)
	local f = _G[frameName]
	if not f then return "absent" end
	if Forbidden(f) then return "forbidden" end

	-- One pcall each, not one around the lot. Bundling them meant a throw on the
	-- first call silently skipped the other two, which is exactly how a frame
	-- ends up still on screen with no error to show for it.
	pcall(f.UnregisterAllEvents, f)
	pcall(f.Hide, f)
	pcall(f.SetParent, f, GetHider())

	-- Belt and braces. Blizzard's bar code re-shows these from handlers we can't
	-- unregister (they fire on a parent, or run out of UIParent_ManageFramePositions),
	-- so catch the show and put it back. Out of combat only: Hide() on a
	-- protected frame mid-fight is itself protected.
	if not f.__aetherHooked and f.HookScript then
		f.__aetherHooked = true
		pcall(f.HookScript, f, "OnShow", function(self)
			if not InCombatLockdown() then self:Hide() end
		end)
	end

	local shown = f.IsShown and f:IsShown()
	return shown and "STILL SHOWN" or "hidden"
end

--- Take a Blizzard action button out of service.
--
--  statehidden is the important one: it is what Blizzard's own secure visibility
--  drivers check before showing a button again, so setting it keeps the button
--  down without us having to fight for it every frame.
local function BanishButton(b)
	if not b or Forbidden(b) then return end
	pcall(b.UnregisterAllEvents, b)
	pcall(b.Hide, b)
	if not InCombatLockdown() then
		pcall(b.SetAttribute, b, "statehidden", true)
	end
end

--- Drop any override bindings Blizzard's bars own, so the ACTIONBUTTON keys are
--  ours alone. Doing this before we set our own is what makes the order
--  deterministic instead of a race.
local function ClearBlizzardBindings()
	if not ClearOverrideBindings or InCombatLockdown() then return 0 end
	local cleared = 0
	for _, name in ipairs(BLIZZARD_BINDING_OWNERS) do
		local f = _G[name]
		if f and not Forbidden(f) then
			if pcall(ClearOverrideBindings, f) then cleared = cleared + 1 end
		end
	end
	return cleared
end
AB.ClearBlizzardBindings = ClearBlizzardBindings

function AB:HideBlizzard()
	local cfg = A.Config:Module("actionbars")
	if not cfg.hideBlizzard then return end
	if InCombatLockdown() then
		AB._hidePending = true
		return
	end
	AB._hidePending = nil

	-- Note: MainMenuBar owns the micro menu and the bag buttons, so hiding it
	-- takes those with it. That is a deliberate gap, not an oversight - they get
	-- a proper home in a later chrome module rather than a reparenting hack here.
	-- Until then they are reachable by keybind (B, C, P, K, L...).
	local report = {}

	-- 1. the names we know
	for _, n in ipairs(AB.blizzardFrames) do
		report[n] = Banish(n)
	end

	-- 1a. and the buttons themselves. Hiding the bar is not enough: the buttons
	--     outlive it, still resolve their action from the live page, and are
	--     still what Blizzard's keys point at. See BanishButton.
	local buttons = 0
	for _, prefix in ipairs(BLIZZARD_BUTTON_PREFIXES) do
		for i = 1, 12 do
			local b = _G[prefix .. i]
			if b then
				BanishButton(b)
				buttons = buttons + 1
			end
		end
	end
	report["<blizzard buttons>"] = buttons .. " silenced"
	report["<blizzard bindings>"] = ClearBlizzardBindings() .. " owners cleared"

	-- 2. the micro menu, from Blizzard's own list rather than ours. MICRO_BUTTONS
	--    is maintained by the client, so it survives the renames that keep
	--    catching a hard-coded list out.
	if type(_G.MICRO_BUTTONS) == "table" then
		for _, n in ipairs(_G.MICRO_BUTTONS) do
			if report[n] == nil then report[n] = Banish(n) end
		end
	end

	-- 3. anything holding an action button that we did not name. Walk up from the
	--    buttons themselves instead of trusting a list of container names.
	for i = 1, 12 do
		local b = _G["ActionButton" .. i]
		local p = b and not Forbidden(b) and b.GetParent and b:GetParent()
		while p and p ~= UIParent and p ~= GetHider() and not Forbidden(p) do
			local okName, pn = pcall(p.GetName, p)
			pn = okName and pn or nil
			if pn and report[pn] == nil then
				report[pn] = Banish(pn) .. " (via ActionButton" .. i .. ")"
			end
			p = p.GetParent and p:GetParent()
		end
	end

	-- 4. a net for the stragglers: sweep UIParent's descendants two levels deep
	--    and take anything whose name says it belongs to the old bar. This is
	--    what finally catches the pager and any micro button that moved house,
	--    without me having to be right about the name up front.
	local PATTERNS = {
		"^MainActionBar", "^MainMenuBar", "^ActionBarUpButton$",
		"^ActionBarDownButton$", "^ActionBarPage", "^MultiBar",
		"MicroButton$", "^MicroButtonAndBagsBar$", "^MicroMenu",
		"^BagsBar$", "^StanceBar", "^PossessBar", "^StatusTrackingBar",
	}

	local function sweep(frame, depth)
		if depth > 2 or Forbidden(frame) or not frame.GetChildren then return end

		local ok, children = pcall(function() return { frame:GetChildren() } end)
		if not ok then return end

		for _, child in ipairs(children) do
			-- UIParent's children include forbidden frames (the in-game shop,
			-- among others). Reading so much as a name off one throws, so this
			-- guard has to come before every single access.
			if not Forbidden(child) then
				local okName, n = pcall(child.GetName, child)
				n = okName and n or nil

				-- never touch our own frames
				if n and not n:find("^" .. ADDON) and report[n] == nil then
					for _, pat in ipairs(PATTERNS) do
						if n:find(pat) then
							report[n] = Banish(n) .. " (swept)"
							break
						end
					end
				end

				if child ~= GetHider() then sweep(child, depth + 1) end
			end
		end
	end
	sweep(UIParent, 0)

	AB.hideReport = report
end

-- ---------------------------------------------------------------------------
-- refresh
-- ---------------------------------------------------------------------------

--- Repaint a button, whichever sort it is.
--
--  An adopted button is Blizzard's, and Blizzard keeps it painted. We gave it a
--  position and nothing else, so there is nothing here to update - and it has
--  none of the regions our own buttons carry.
local function Repaint(b)
	if b.__aetherAdopted then return end
	if b.aether then UpdateSpecialButton(b) else UpdateAllOn(b) end
end
AB.Repaint = Repaint

function AB:RefreshAll()
	for _, bar in ipairs(AB.bars) do
		for _, b in ipairs(bar.buttons) do Repaint(b) end
	end
end

--- Only the action bars; stance and pet buttons do not answer to action events.
local function ForEachAction(fn)
	for _, bar in ipairs(AB.bars) do
		if bar.kind == "action" then
			for _, b in ipairs(bar.buttons) do
				if not b.__aetherAdopted then fn(b) end
			end
		end
	end
end

local function ForEachOfKind(kind, fn)
	for _, bar in ipairs(AB.bars) do
		if bar.kind == kind then
			for _, b in ipairs(bar.buttons) do fn(b) end
		end
	end
end

local function ForEachButton(fn)
	for _, bar in ipairs(AB.bars) do
		for _, b in ipairs(bar.buttons) do fn(b) end
	end
end

--- Bars whose button count is decided by the game rather than by config.
local function RebuildDynamicBars()
	if InCombatLockdown() then
		AB._rebuildPending = true
		return
	end
	AB._rebuildPending = nil
	for _, bar in ipairs(AB.bars) do
		if bar.kind == "stance" then
			local want = SlotCount(bar.cfg)
			-- Frames cannot be destroyed, so grow once and hide the surplus.
			for i = #bar.buttons + 1, want do
				local b = BuildSpecialButton(bar, i, "StanceButtonTemplate")
				if b then bar.buttons[#bar.buttons + 1] = b end
			end
			for i = 1, #bar.buttons do
				if i <= want then bar.buttons[i]:Show() else bar.buttons[i]:Hide() end
			end
			bar.shown = want
			if want == 0 and not bar.__preview then
				bar.dock:Hide()
			else
				bar.dock:Show()
			end
			LayoutBar(bar)
		end
	end
end
AB.RebuildDynamicBars = RebuildDynamicBars

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

--- Hold a conditionally-visible bar up while its position is being set.
--
--  The pet bar is hidden by a secure driver when you have no pet; the extra bar
--  is down unless the game says the taxi or extra-action button has a job; a
--  stance bar has nothing in it on a class with no forms. All three are
--  impossible to place, because you cannot drag a frame you can never see.
local function BarPreview(bar)
	return function(show)
		bar.__preview = show or nil

		if show then
			-- The pet bar's visibility belongs to a secure driver, so previewing
			-- means taking the driver off rather than arguing with it.
			if bar.visibilityDriven and UnregisterStateDriver and not InCombatLockdown() then
				pcall(UnregisterStateDriver, bar.dock, "visibility")
				bar.visibilityDriven = false
			end
			LayoutBar(bar)
			bar.dock:Show()
			bar.__shown = true
			return
		end

		bar.__shown = nil
		if bar.kind == "pet" and not bar.visibilityDriven and RegisterStateDriver
			and not InCombatLockdown() then
			pcall(RegisterStateDriver, bar.dock, "visibility", "[pet] show; hide")
			bar.visibilityDriven = true
		end
		if bar.kind == "stance" then RebuildDynamicBars() end
		if bar.kind == "extra" and AB.UpdateExtraBars then AB.UpdateExtraBars() end
	end
end

--- Park a bar that has no natural home of its own beside the first action bar
--  rather than in the middle of the screen.
--
--  Computed rather than written down, because "beside bar 1" depends on how wide
--  bar 1 currently is - button count, button size, its own scale. Only used when
--  there is no saved position, so moving it once settles it for good.
local function DefaultAnchor(bar)
	local d = bar.cfg
	local fallback = { point = d.point, relPoint = d.point, x = d.x or 0, y = d.y or 26 }
	if not d.beside then return fallback end

	local main
	for _, other in ipairs(AB.bars) do
		if other.kind == "action" and other.id == tostring(d.beside) then main = other end
	end
	if not main or not main.dock:GetWidth() then return fallback end

	local us = UIParent:GetEffectiveScale() or 1
	local ms = main.dock:GetEffectiveScale() or us
	local es = bar.dock:GetEffectiveScale() or us
	if us <= 0 or es <= 0 then return fallback end

	local mainPoint, _, _, mainX = main.dock:GetPoint(1)
	local centre = (mainPoint == "BOTTOM" and (mainX or 0) * ms / us) or 0

	-- All in UIParent units, then back into the frame's own space for SetPoint.
	local half = (main.dock:GetWidth() * ms / us) / 2
	local ours = (bar.dock:GetWidth() * es / us) / 2
	local side = (d.side == "left") and -1 or 1
	local x = centre + side * (half + 14 + ours)

	return { point = "BOTTOM", relPoint = "BOTTOM", x = x * us / es, y = d.y or 26 }
end

AB.DefaultAnchor = DefaultAnchor

function AB:OnEnable()
	local cfg = A.Config:Module("actionbars")

	if #AB.bars == 0 then
		for _, barCfg in ipairs(cfg.bars) do
			if barCfg.enabled then
				AB.bars[#AB.bars + 1] = BuildBar(barCfg)
			end
		end
	end

	for _, bar in ipairs(AB.bars) do
		-- An extra bar's visibility is derived, not ours to assert. Showing it
		-- here and letting the ticker sort it out later is how it ended up on
		-- screen with nothing in it.
		if bar.kind == "extra" then
			bar.dock:Hide()
			bar.__shown = nil    -- nil, so the first tick always decides
		else
			bar.dock:Show()
		end
		if bar.kind == "pet" and bar.visibilityDriven == nil and RegisterStateDriver then
			pcall(RegisterStateDriver, bar.dock, "visibility", "[pet] show; hide")
			bar.visibilityDriven = true
		end
		A.Movers:Register("bar" .. bar.id, bar.dock, DefaultAnchor(bar),
			bar.cfg.label or ("Bar " .. bar.id), { preview = BarPreview(bar) })
		A.Fader:Register(bar.dock, {})
	end

	self:OnConfigChanged()
	self:RegisterEvents()
	A:RegisterTicker(self, Tick)

	self:HideBlizzard()
	self:ApplyBindings()
	RebuildDynamicBars()
	self:RefreshAll()
end

function AB:RegisterEvents()
	local function refresh() AB:RefreshAll() end

	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		AB:HideBlizzard()
		AB:ApplyBindings()
		AB:RefreshAll()
		AB:SyncFlyouts()
	end)

	-- WHAT THE DRAWER CAN OFFER, and when that changes: a spell learned, a
	-- talent taken, a pet trained. Out of combat only - the sync builds secure
	-- buttons and writes the restricted environment, and neither is allowed
	-- with a fight on - so the end of one is a sync point too. A drawer that
	-- is one summon out of date until the fight ends is the trade, and it is
	-- the same one every bar addon on this client makes.
	for _, e in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
		"PLAYER_TALENT_UPDATE", "PLAYER_REGEN_ENABLED" }) do
		A:RegisterEvent(self, e, function() AB:SyncFlyouts() end)
	end

	A:RegisterEvent(self, "ACTIONBAR_SLOT_CHANGED", function(_, _, slot)
		if not slot or slot == 0 then return AB:RefreshAll() end
		ForEachAction(function(b)
			if ButtonAction(b) == slot then UpdateAllOn(b) end
		end)
	end)

	A:RegisterEvent(self, "ACTIONBAR_UPDATE_COOLDOWN", function()
		ForEachAction(UpdateCooldown)
	end)
	A:RegisterEvent(self, "SPELL_UPDATE_COOLDOWN", function()
		ForEachAction(UpdateCooldown)
	end)
	A:RegisterEvent(self, "ACTIONBAR_UPDATE_USABLE", function()
		ForEachAction(UpdateUsable)
	end)
	A:RegisterEvent(self, "ACTIONBAR_UPDATE_STATE", function()
		ForEachAction(UpdateState)
	end)
	A:RegisterEvent(self, "UPDATE_BINDINGS", function()
		AB:ApplyBindings()
		-- The pickup modifier lives in Blizzard's own bindings, so it can change
		-- under us at any time.
		ForEachAction(ApplyPickupModifier)
	end)

	-- No ACTIONBAR_PAGE_CHANGED handler, deliberately. Nothing here follows the
	-- page any more, so the event is not ours to care about.
	A:RegisterEvent(self, "PLAYER_TARGET_CHANGED", function() ForEachAction(UpdateUsable) end)
	A:RegisterEvent(self, "UNIT_INVENTORY_CHANGED", refresh)
	A:RegisterEvent(self, "BAG_UPDATE", refresh)
	A:RegisterEvent(self, "BAG_UPDATE_COOLDOWN", function() ForEachAction(UpdateCooldown) end)
	A:RegisterEvent(self, "LEARNED_SPELL_IN_TAB", refresh)

	-- stance -----------------------------------------------------------------
	local function stanceUpdate() ForEachOfKind("stance", UpdateSpecialButton) end
	A:RegisterEvent(self, "UPDATE_SHAPESHIFT_FORM", stanceUpdate)
	A:RegisterEvent(self, "UPDATE_SHAPESHIFT_COOLDOWN", stanceUpdate)
	A:RegisterEvent(self, "UPDATE_SHAPESHIFT_USABLE", stanceUpdate)
	A:RegisterEvent(self, "UPDATE_SHAPESHIFT_FORMS", function()
		-- The *number* of forms changed, so the bar itself has to be rebuilt.
		RebuildDynamicBars()
		stanceUpdate()
	end)

	-- pet --------------------------------------------------------------------
	local function petUpdate() ForEachOfKind("pet", UpdateSpecialButton) end
	A:RegisterEvent(self, "PET_BAR_UPDATE", petUpdate)
	A:RegisterEvent(self, "PET_BAR_UPDATE_COOLDOWN", petUpdate)
	A:RegisterEvent(self, "PET_SPECIALIZATION_CHANGED", petUpdate)
	A:RegisterEvent(self, "UNIT_PET", petUpdate)
	A:RegisterEvent(self, "PLAYER_CONTROL_LOST", petUpdate)
	A:RegisterEvent(self, "PLAYER_CONTROL_GAINED", petUpdate)
	A:RegisterEvent(self, "PLAYER_FARSIGHT_FOCUS_CHANGED", petUpdate)

	-- Anything we had to defer because it landed mid-fight.
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
		if AB._hidePending then AB:HideBlizzard() end
		if AB._bindingsPending then AB:ApplyBindings() end
		if AB._rebuildPending then RebuildDynamicBars() end
		if AB._layoutPending then AB:OnConfigChanged() end
	end)

	-- Picking an action up and putting it down. HIDEGRID in particular is the
	-- one that fires once the cursor is empty again, which is when a slot that
	-- has just been vacated needs repainting.
	A:RegisterEvent(self, "ACTIONBAR_SHOWGRID", refresh)
	A:RegisterEvent(self, "ACTIONBAR_HIDEGRID", refresh)
	A:RegisterEvent(self, "CURSOR_UPDATE", refresh)

	A:RegisterEvent(self, "CVAR_UPDATE", function(_, _, name)
		if name == "ActionButtonUseKeyDown" and not InCombatLockdown() then
			ForEachButton(function(b)
				pcall(b.RegisterForClicks, b, UseKeyDown() and "AnyDown" or "AnyUp")
				if not b.aether and not b.__aetherAdopted then ApplyPickupModifier(b) end
			end)
		end
	end)
end

function AB:OnDisable()
	for _, bar in ipairs(AB.bars) do
		if not InCombatLockdown() then
			ClearOverrideBindings(bar.header)
			if bar.visibilityDriven and UnregisterStateDriver then
				pcall(UnregisterStateDriver, bar.dock, "visibility")
				bar.visibilityDriven = nil
			end
		end
		bar.dock:Hide()
		A.Fader:Unregister(bar.dock)
		A.Movers:Unregister("bar" .. bar.id)
	end
	wipe(cooldownWatch)
end

--- The dock's own surface, honouring a bar that asked for no backdrop.
local function ApplyDockSkin(bar)
	if bar.cfg.backdrop == false then
		bar.dock:SetFillColor({ 0, 0, 0, 0 })
		bar.dock:SetEdgeShown(false)
		bar.dock:SetShadow(0)
	else
		bar.dock:ApplySkin()
		bar.dock:SetEdgeShown(true)
		bar.dock:SetShadow(A.db.profile.glass.shadow)
	end
end

function AB:OnSkinChanged()
	for _, bar in ipairs(AB.bars) do
		ApplyDockSkin(bar)
		for _, b in ipairs(bar.buttons) do
			-- An adopted Blizzard button has none of our regions - no hotkey, no
			-- count, no icon - because we only ever gave it a position. It is not
			-- ours to skin, and reaching for regions it never had is what turned
			-- one config toggle into a restyle error.
			if not b.__aetherAdopted then
				W.Color(b.hotkey, Palette.c.text)
				W.Color(b.cdText, Palette.c.text)
				W.Color(b.count, Palette.c.text)
				Repaint(b)
			end
		end
	end
end

--- Grow or shrink a configured bar in place.
--
--  Frames cannot be destroyed in this API, so a bar only ever grows; asking for
--  fewer buttons hides the surplus rather than leaking a second set of them.
local function ResizeBar(bar)
	if bar.kind ~= "action" then return end
	local want = SlotCount(bar.cfg)
	for i = #bar.buttons + 1, want do
		bar.buttons[i] = BuildButton(bar, i)
	end
	for i = 1, #bar.buttons do
		if i <= want then bar.buttons[i]:Show() else bar.buttons[i]:Hide() end
	end
	bar.shown = want
end

--- Re-point a bar at a different page without rebuilding it.
local function RepageBar(bar)
	if bar.kind ~= "action" then return end
	local page = math.max(1, math.min(bar.cfg.page or 1, MAX_ACTION_PAGE))
	if page == bar.page then return end
	bar.page = page
	for i, b in ipairs(bar.buttons) do
		b:SetAttribute("action", (page - 1) * NUM_ACTIONS_PER_PAGE + i)
	end
end

--- Bring the built bars in line with the config.
--
--  This lives here rather than in the enable/disable command because there are
--  two ways to flip a bar on - the slash command and the options panel - and
--  only one of them used to build it. Ticking "Enabled" in the panel set the
--  flag, ran a reconfigure, and reconfigure only ever looked at bars that
--  already existed. The bar was on and nowhere.
--- Point every built bar at the LIVE config entry for its id.
--
--  A bar holds its own config table by reference, and AceDB empties the
--  old profile's tables when the player switches away - so the reference
--  is not stale, it is hollow. Re-resolved by id rather than by position:
--  a profile with a different set of bars in it would otherwise hand bar 3
--  the settings for bar 4.
--
--  Returns how many it could not find, which is the interesting number:
--  a bar built under a profile that names it and switched to one that does
--  not is a bar with nothing to read.
local function BindConfigs()
	local cfg = A.Config:Module("actionbars")
	local byId, orphans = {}, 0
	for _, barCfg in ipairs(cfg.bars or {}) do byId[tostring(barCfg.id)] = barCfg end
	for _, bar in ipairs(AB.bars) do
		local live = byId[tostring(bar.id)]
		if live then bar.cfg = live else orphans = orphans + 1 end
	end
	return orphans
end
AB.BindConfigs = BindConfigs

local function SyncBars()
	local cfg = A.Config:Module("actionbars")
	-- Before anything reads a bar's settings, including the enabled flag
	-- three lines down. Both branches below need it, so it is done once
	-- here rather than in the one of them that happened to be noticed.
	BindConfigs()
	local built = {}
	for _, bar in ipairs(AB.bars) do built[bar.id] = bar end

	for _, barCfg in ipairs(cfg.bars) do
		local id = tostring(barCfg.id)
		local bar = built[id]

		if barCfg.enabled then
			if not bar then
				if InCombatLockdown() then
					AB._layoutPending = true
				else
					bar = BuildBar(barCfg)
					AB.bars[#AB.bars + 1] = bar
					built[id] = bar
				end
			end
			-- An extra bar decides its own visibility; everything else is simply on.
			if bar and bar.kind ~= "extra" then bar.dock:Show() end
		elseif bar then
			bar.dock:Hide()
			A.Movers:Unregister("bar" .. id)
		end
	end
end

AB.SyncBars = SyncBars

--- A different profile is in force. Re-resolve before anything reads a bar.
--
--  This runs BEFORE the restyle and the reconfigure - see A:ProfileChanged.
--  The restyle reads bar.cfg for the dock skin and the per-bar scale, so
--  re-binding inside OnConfigChanged alone was already too late.
function AB:OnProfileChanged()
	local orphans = BindConfigs()
	if orphans > 0 then
		A:Debug("actionbars: " .. orphans .. " bar(s) the new profile does not name")
	end
end

function AB:OnConfigChanged()
	if InCombatLockdown() then
		AB._layoutPending = true
		return
	end
	AB._layoutPending = nil

	local cfg = A.Config:Module("actionbars")

	SyncBars()

	for _, bar in ipairs(AB.bars) do
		if bar.cfg.enabled ~= false then
			-- Per-bar scale on top of the global one, so a pet bar can be small
			-- without dragging the main dock down with it.
			bar.dock:SetScale(A.db.profile.scale * (cfg.scale or 1) * (bar.cfg.scale or 1))
			ApplyDockSkin(bar)
			Glass.SetPanelCorner(bar.dock, A.db.profile.glass.corner + 2)

			ResizeBar(bar)
			RepageBar(bar)
			LayoutBar(bar)

			A.Movers:Register("bar" .. bar.id, bar.dock, DefaultAnchor(bar),
				bar.cfg.label or ("Bar " .. bar.id), { preview = BarPreview(bar) })
		end
	end

	RebuildDynamicBars()
	AB:ApplyBindings()
	AB:RefreshAll()
	A.Fader:Refresh()
end


--- Turn a configured bar on or off without a reload.
function AB:SetBarEnabled(id, on)
	local barCfg = AB:BarConfig(id)
	if not barCfg then return false end
	barCfg.enabled = on and true or false
	AB:OnConfigChanged()
	return true
end

--- The bar config for an id, or nil.
function AB:BarConfig(id)
	for _, barCfg in ipairs(A.Config:Module("actionbars").bars) do
		if tostring(barCfg.id) == tostring(id) then return barCfg end
	end
end
