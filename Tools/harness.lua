--[[--------------------------------------------------------------------------
	A small mock of the WoW UI API, enough to load AetherUI end to end outside the
	game and drive it through a realistic session.

	This is not a re-implementation of WoW. It exists to catch the class of bug
	you cannot see by reading: nil field access, methods that do not exist on the
	widget type you used, ordering problems between files, anchors referencing
	regions that were not built yet.

	Run:  lua5.1 Tools/harness.lua
----------------------------------------------------------------------------]]

local FAIL = {}

local function fail(msg)
	FAIL[#FAIL + 1] = msg
	print("  !! " .. msg)
end

-- ---------------------------------------------------------------------------
-- widget mock
-- ---------------------------------------------------------------------------

local time = 1000.0
local cursorX, cursorY = 500, 400

local function widgetBase(kind)
	local o = {
		__kind = kind,
		__points = {},
		__scripts = {},
		__shown = true,
		__alpha = 1,
		__scale = 1,
		__w = 0, __h = 0,
		__children = {},
		__regions = {},
	}

	function o:SetPoint(p, rel, relP, x, y)
		if type(p) ~= "string" then fail(kind .. ":SetPoint got non-string point " .. tostring(p)) end
		self.__points[#self.__points + 1] = { p, rel, relP, x or 0, y or 0 }
	end
	function o:GetPoint(i)
		local pt = self.__points[i or 1]
		if not pt then return nil end
		return pt[1], pt[2], pt[3], pt[4], pt[5]
	end
	function o:ClearAllPoints() self.__points = {} end
	function o:SetAllPoints(other) self.__points = { { "ALL", other } } end

	function o:SetSize(w, h) self.__w, self.__h = w, h end
	function o:SetWidth(w) self.__w = w end
	function o:SetHeight(h) self.__h = h end
	-- SetAllPoints really does size the frame, so a mock that ignored that would
	-- report 0 for anything that fills its parent. Resolved lazily rather than
	-- copied, so a later resize of the parent still propagates.
	local function allTarget(self)
		local pt = self.__points[1]
		return pt and pt[1] == "ALL" and pt[2] or nil
	end
	function o:GetWidth()
		local t = allTarget(self)
		return t and t:GetWidth() or self.__w
	end
	function o:GetHeight()
		local t = allTarget(self)
		return t and t:GetHeight() or self.__h
	end
	function o:GetSize() return self:GetWidth(), self:GetHeight() end
	-- Geometry getters report in the FRAME's own coordinate space, which is the
	-- whole point of the mover test below; __geom lets a test place a frame.
	function o:SetGeom(g) self.__geom = g end
	function o:GetCenter()
		local g = self.__geom
		return g and g.cx or 500, g and g.cy or 300
	end
	function o:GetLeft()   return self.__geom and self.__geom.left   or 100 end
	function o:GetRight()  return self.__geom and self.__geom.right  or 400 end
	function o:GetTop()    return self.__geom and self.__geom.top    or 400 end
	function o:GetBottom() return self.__geom and self.__geom.bottom or 100 end

	function o:Show() self.__shown = true end
	function o:Hide() self.__shown = false end
	function o:IsShown() return self.__shown end
	function o:IsVisible() return self.__shown end
	function o:SetShown(v) self.__shown = v and true or false end

	function o:SetAlpha(a) self.__alpha = a end
	function o:GetAlpha() return self.__alpha end
	function o:SetScale(s) self.__scale = s end
	function o:GetScale() return self.__scale end
	function o:GetEffectiveScale() return self.__scale end

	function o:SetID(id) self.__id = id end
	function o:GetID() return self.__id or 0 end
	-- The client resets this for every keyboard event, which is exactly what the
	-- first version of bind mode got wrong. Modelled: the test drives OnKeyDown
	-- directly and asserts the handler set it, not some earlier OnEnter.
	o.__propagate = true
	function o:SetPropagateKeyboardInput(v) self.__propagate = v and true or false end
	-- Buttons are Frames, which is the check every button collector leans on.
	function o:GetObjectType() return self.__kind end
	function o:IsObjectType(t)
		return t == self.__kind or (t == "Frame" and self.__kind ~= "Texture"
			and self.__kind ~= "FontString")
	end
	function o:SetParent(p)
		local old = self.__parent
		if old and old.__children then
			for i, c in ipairs(old.__children) do
				if c == self then table.remove(old.__children, i) break end
			end
		end
		self.__parent = p
		if p and p.__children then p.__children[#p.__children + 1] = self end
	end
	function o:GetParent() return self.__parent end

	return o
end

-- ---------------------------------------------------------------------------
-- how the client reads a string
--
-- Colour codes and hyperlinks contribute no width and no characters; an inline
-- texture contributes its declared width and no characters. The one that
-- matters is the last case: `|T...|t` takes eleven arguments in every client,
-- and fourteen - the extra three being a vertex colour - in clients that
-- support tinting an inline texture. A client that does *not* fails by drawing
-- the whole escape as literal text, which is the failure Modules/Chat.lua
-- probes for. Flip MOCK_TEXTURE_VERTEX_COLOR to model the other client.
-- ---------------------------------------------------------------------------

MOCK_TEXTURE_VERTEX_COLOR = true

function MEASURE(text)
	local width = 0
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("|T(.-)|t", function(body)
		local parts = {}
		for p in (body .. ":"):gmatch("([^:]*):") do parts[#parts + 1] = p end
		-- path + height + width + 8 more is the short form; three beyond that is
		-- the vertex colour. Unparsed markup stays in the string as text.
		if #parts > 11 and not MOCK_TEXTURE_VERTEX_COLOR then return nil end
		width = width + (tonumber(parts[3]) or 0)
		return ""
	end)
	return text, width
end

local function newTexture(owner, layer, sub)
	local t = widgetBase("Texture")
	t.__layer, t.__sub = layer, sub
	function t:SetTexture(path) self.__tex = path end
	function t:GetTexture() return self.__tex end
	function t:GetTexCoord()
		local c = self.__texcoord or { 0, 1, 0, 1 }
		return c[1], c[2], c[3], c[4]
	end
	function t:SetTexCoord(a, b, c, d)
		self.__texcoord = { a, b, c, d }
		for _, v in ipairs({ a, b, c, d }) do
			if type(v) ~= "number" then fail("SetTexCoord got " .. tostring(v)) end
		end
		self.__coord = { a, b, c, d }
	end
	-- A nine-slice's pieces each round their own edges to the pixel grid unless
	-- this is turned off, which is what puts a bright or dark hairline exactly
	-- where the arc meets the straight edge.
	function t:SetSnapToPixelGrid(v) self.__snap = v end
	function t:SetTexelSnappingBias(v) self.__bias = v end
	function t:SetVertexColor(r, g, b, a)
		if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
			fail("SetVertexColor got non-number (" .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b) .. ")")
		end
		self.__color = { r, g, b, a }
	end
	function t:GetVertexColor()
		local c = self.__color or { 1, 1, 1, 1 }
		return c[1], c[2], c[3], c[4]
	end
	function t:SetBlendMode(m) self.__blend = m end
	function t:SetDesaturated() end
	function t:SetGradient(orient, c1, c2)
		if type(orient) ~= "string" then fail("SetGradient orientation " .. tostring(orient)) end
		if type(c1) ~= "table" then fail("SetGradient c1 not a colour object") end
	end
	function t:AddMaskTexture(m)
		if not m or m.__kind ~= "MaskTexture" then fail("AddMaskTexture got " .. tostring(m and m.__kind)) end
	end
	function t:SetRotation() end
	return t
end

local function newFontString(owner, layer)
	local f = widgetBase("FontString")
	function f:SetFont(path, size, flags)
		if type(path) ~= "string" then fail("SetFont path " .. tostring(path)) return false end
		if type(size) ~= "number" then fail("SetFont size " .. tostring(size)) return false end
		self.__font = { path, size, flags }
		return true
	end
	function f:SetText(s) self.__text = s end
	function f:GetText() return self.__text end
	function f:GetName() return self.__name end
	function f:SetJustifyH() end
	function f:SetJustifyV() end
	function f:SetShadowColor() end
	function f:SetShadowOffset() end
	function f:SetTextColor(r, g, b, a)
		if type(r) ~= "number" then fail("SetTextColor got " .. tostring(r)) end
		self.__color = { r, g, b, a }
	end
	function f:GetTextColor()
		local c = self.__color or { 1, 1, 1, 1 }
		return c[1], c[2], c[3], c[4]
	end
	function f:SetWordWrap() end
	function f:SetVertexColor() end
	-- crude but proportional: enough for layout maths to be exercised.
	--
	-- Markup is modelled rather than counted, because Modules/Chat.lua asks this
	-- function a real question: it probes whether this client's inline texture
	-- escape takes the three vertex-colour arguments by rendering the same badge
	-- with and without them and comparing widths. Counting characters would
	-- answer "no" on a client that supports it perfectly well, and a mock that
	-- answers a probe wrongly is worse than no mock at all.
	function f:GetStringWidth()
		local size = (self.__font and self.__font[2]) or 11
		local text, textures = MEASURE(self.__text or "")
		return textures + #text * size * 0.52
	end
	function f:GetStringHeight() return (self.__font and self.__font[2]) or 11 end
	return f
end

local frames = {}

--- Protection, modelled properly enough to catch the class of bug that made
--- losing a target mid-fight throw ADDON BLOCKED.
---
--- A frame built from a secure template is protected, and so is anything under
--- it. `Hide()` on a frame with a protected descendant is refused in combat -
--- hiding it would change that descendant's effective visibility - and that is
--- *not* the same rule as SetPoint/SetHeight, which really are per-object.
local function HasProtectedDescendant(f)
	if f.__protected then return f end
	for _, c in ipairs(f.__children or {}) do
		local hit = HasProtectedDescendant(c)
		if hit then return hit end
	end
	return nil
end

function CreateFrame(kind, name, parent, template)
	local f = widgetBase(kind)
	f.__parent = parent
	f.__name = name
	f.__template = template
	if template and template:find("Secure") then f.__protected = true end
	if parent and parent.__children then
		parent.__children[#parent.__children + 1] = f
	end
	if name then _G[name] = f end
	frames[#frames + 1] = f

	function f:IsProtected() return HasProtectedDescendant(self) ~= nil end

	function f:Hide()
		if _G.__inCombat then
			local p = HasProtectedDescendant(self)
			if p then
				fail(("ADDON BLOCKED: Hide() on %s, which has a protected"
					.. " descendant (%s) - refused in combat")
					:format(tostring(self.__name or self.__kind),
						tostring(p.__name or p.__template or "?")))
			end
		end
		self.__shown = false
	end
	function f:Show()
		if _G.__inCombat then
			local p = HasProtectedDescendant(self)
			if p and not self.__shown then
				fail(("ADDON BLOCKED: Show() on %s, which has a protected"
					.. " descendant (%s) - refused in combat")
					:format(tostring(self.__name or self.__kind),
						tostring(p.__name or p.__template or "?")))
			end
		end
		self.__shown = true
	end

	-- Geometry is refused in combat for the same reason Hide is, and on the same
	-- frames: the restriction reaches every *ancestor* of a protected frame, not
	-- just the frame itself. This harness modelled Hide and Show and not these,
	-- which is exactly how a tray of secure buff tiles shipped calling SetPoint
	-- on itself four times per aura change in a fight.
	local function blocked(self, method)
		if not _G.__inCombat then return false end
		local p = HasProtectedDescendant(self)
		if not p then return false end
		fail(("ADDON BLOCKED: %s() on %s, which has a protected descendant (%s)"
			.. " - refused in combat")
			:format(method, tostring(self.__name or self.__kind),
				tostring(p.__name or p.__template or "?")))
		return true
	end

	for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetSize",
		"SetHeight", "SetWidth", "SetScale", "SetParent", "EnableMouse" }) do
		local orig = f[method]
		if orig then
			f[method] = function(self, ...)
				if blocked(self, method) then return end
				return orig(self, ...)
			end
		end
	end

	function f:CreateTexture(n, layer, tmpl, sub)
		local t = newTexture(self, layer, sub)
		self.__regions[#self.__regions + 1] = t
		return t
	end
	function f:GetRegions() return unpack(self.__regions or {}) end
	function f:CreateFontString(n, layer)
		local fs = newFontString(self, layer)
		-- Honour the name. Anonymous versus named is a real distinction on an
		-- edit box: the FontString that draws what you are typing has no name,
		-- and everything we want to silence does.
		if n then
			fs.__name = n
			_G[n] = fs
		end
		self.__regions[#self.__regions + 1] = fs
		return fs
	end
	function f:CreateMaskTexture(n, layer)
		local t = newTexture(self, layer)
		t.__kind = "MaskTexture"
		return t
	end

	f.__events = {}
	function f:RegisterEvent(e)
		if type(e) ~= "string" then error("bad event") end
		-- pretend a couple of retail-only events do not exist here
		if e == "UNIT_POWER_FREQUENT" then error("unknown event") end
		self.__events[e] = true
	end
	function f:UnregisterEvent(e) self.__events[e] = nil end
	function f:UnregisterAllEvents() self.__events = {} end
	function f:IsEventRegistered(e) return self.__events[e] end

	function f:SetScript(s, fn) self.__scripts[s] = fn end
	function f:GetScript(s) return self.__scripts[s] end
	function f:HookScript(s, fn) self.__scripts[s] = fn end

	f.__attrs = {}
	function f:SetAttribute(k, v) self.__attrs[k] = v end
	function f:GetAttribute(k) return self.__attrs[k] end
	function f:GetName() return self.__name end

	function f:RegisterForClicks(...) self.__clicks = { ... } end
	function f:SetChecked(v) self.__checked = v and true or false end
	function f:GetChecked() return self.__checked end
	function f:SetHighlightTexture() end
	function f:SetPushedTexture() end
	function f:SetCheckedTexture() end
	function f:SetNormalTexture() end
	function f:SetButtonState() end

	function f:EnableMouse() end
	function f:EnableMouseWheel() end
	function f:EnableKeyboard(v) self.__keyboard = v and true or false end
	function f:IsKeyboardEnabled() return self.__keyboard or false end
	function f:SetMovable() end
	function f:SetResizable() end
	function f:RegisterForDrag() end
	function f:StartMoving() end
	function f:StopMovingOrSizing() end
	function f:SetClampedToScreen() end
	-- Strata and level are modelled rather than swallowed: the last minimap bug
	-- was purely an ordering one, and a mock that forgets both cannot see it.
	function f:SetFrameStrata(v)
		if self.__fixedStrata then return end
		self.__strata = v
	end
	function f:GetFrameStrata() return self.__strata or "MEDIUM" end
	function f:SetFixedFrameStrata(v) self.__fixedStrata = v and true or false end
	function f:SetFrameLevel(v)
		if self.__fixedLevel then return end
		self.__level = v
	end
	function f:SetFixedFrameLevel(v) self.__fixedLevel = v and true or false end
	function f:GetFrameLevel() return self.__level or 1 end
	function f:IsMouseOver() return self.__mouseOver or false end
	function f:SetHitRectInsets() end
	function f:IsForbidden() return self.__forbidden or false end
	-- __kids is a curated list a test has pinned on (the UIParent dump); every
	-- other frame reports its real children, which is what the minimap's button
	-- scan walks.
	function f:GetChildren() return unpack(self.__kids or self.__children or {}) end
	function f:RegisterUnitEvent(e) self:RegisterEvent(e) end

	if kind == "Cooldown" then
		function f:SetCooldown(start, duration) self.__cd = { start, duration } end
		function f:GetCooldownTimes() return 0, 0 end
		function f:SetSwipeTexture(t) self.__swipe = t end
		function f:SetSwipeColor() end
		function f:SetDrawEdge() end
		function f:SetDrawBling() end
		function f:SetEdgeTexture() end
		function f:SetHideCountdownNumbers() end
		function f:SetReverse() end
	end

	if kind == "StatusBar" then
		f.__min, f.__max, f.__value = 0, 1, 1
		f.__barTex = newTexture(f, "ARTWORK")
		function f:SetStatusBarTexture(t)
			if type(t) == "string" then self.__barTex.__tex = t else self.__barTex = t end
		end
		function f:GetStatusBarTexture() return self.__barTex end
		function f:SetStatusBarColor(r, g, b, a) self.__barTex:SetVertexColor(r, g, b, a) end
		function f:SetMinMaxValues(a, b) self.__min, self.__max = a, b end
		function f:GetMinMaxValues() return self.__min, self.__max end
		function f:SetValue(v)
			if type(v) ~= "number" then fail("StatusBar:SetValue got " .. tostring(v)) return end
			self.__value = v
		end
		function f:GetValue() return self.__value end
		function f:SetReverseFill() end
		function f:SetOrientation() end
	end

	return f
end

-- ---------------------------------------------------------------------------
-- globals
-- ---------------------------------------------------------------------------

_G = _G or getfenv(0)

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1024, 768)

WorldFrame = CreateFrame("Frame", "WorldFrame")

DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) print("    | " .. tostring(msg)) end }

STANDARD_TEXT_FONT = [[Fonts\FRIZQT__.TTF]]

function GetTime() return time end
function GetCursorPosition() return cursorX, cursorY end
function GetPhysicalScreenSize() return 2560, 1440 end
function InCombatLockdown() return _G.__inCombat or false end
function IsShiftKeyDown() return _G.__shift or false end
_G.__pageBindings = {}
function GetQuestDifficultyColor(level)
    local d = (level or 1) - (_G.__units.player.level or 1)
    if d >= 5 then return { r = 1.00, g = 0.24, b = 0.24 } end
    if d >= 3 then return { r = 1.00, g = 0.60, b = 0.30 } end
    if d >= -2 then return { r = 1.00, g = 0.94, b = 0.45 } end
    if d >= -8 then return { r = 0.51, g = 0.86, b = 0.51 } end
    return { r = 0.62, g = 0.62, b = 0.62 }
end
function GetQuestGreenRange() return 8 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a, GetRGBA = function(s) return s.r, s.g, s.b, s.a end } end
function SetPortraitTexture() end

SlashCmdList = {}

-- action bar / binding / secure mocks ---------------------------------------

local actions = {}          -- slot -> {texture, count, cd={start,duration}, ...}
for i = 1, 12 do
	actions[i] = { texture = 130000 + i, count = (i == 8) and 20 or 0 }
end
actions[3].cd = { start = 990, duration = 30 }     -- a real cooldown
actions[5].cd = { start = 999, duration = 1.5 }    -- a global; must NOT get text
actions[2].usable, actions[2].noMana = false, true
actions[4].inRange = false
actions[6].current = true
actions[7].equipped = true
actions[11] = nil                                   -- an empty slot
-- A couple of slots on page 2 (13-24), so "is this page empty" is a question
-- with two different answers to test against.
actions[13] = { texture = "Icons\\Page2A", count = 0, usable = true, inRange = true }
actions[14] = { texture = "Icons\\Page2B", count = 0, usable = true, inRange = true }
_G.__actions = actions

function HasAction(s) return actions[s] ~= nil end
function GetActionTexture(s) return actions[s] and actions[s].texture end

-- The game answers GetActionCount for a slot that no longer holds anything with
-- whatever the departed stack last counted. Slot 11 is empty and models exactly
-- that, which is the whole reason the button reads HasAction first.
_G.__staleCounts = { [11] = 20 }
function GetActionCount(s)
	if actions[s] then return actions[s].count or 0 end
	return _G.__staleCounts[s] or 0
end
function GetActionCooldown(s)
	local a = actions[s]
	if a and a.cd then return a.cd[1], a.cd[2], 1 end
	return 0, 0, 0
end
function IsUsableAction(s)
	local a = actions[s]
	if not a then return false, false end
	if a.usable == false then return false, a.noMana and true or false end
	return true, false
end
function IsActionInRange(s)
	local a = actions[s]
	if a and a.inRange == false then return false end
	return true
end
function IsCurrentAction(s) return actions[s] and actions[s].current or false end
function IsAutoRepeatAction(s) return false end
function IsEquippedAction(s) return actions[s] and actions[s].equipped or false end
function PickupAction(s) _G.__picked = s end
function PlaceAction(s) _G.__placed = s end
function GetActionBarPage() return _G.__actionPage or 1 end

-- stance and pet -------------------------------------------------------------
-- Two forms and a three-slot pet, so the bars that size themselves have
-- something to size themselves to.
_G.__forms = {
	{ texture = "Icons\\Bear",   active = false, castable = true },
	{ texture = "Icons\\Cat",    active = true,  castable = true },
}
function GetNumShapeshiftForms() return #_G.__forms end
function GetShapeshiftFormInfo(i)
	local f = _G.__forms[i]
	if not f then return nil end
	return f.texture, f.active, f.castable
end
function GetShapeshiftFormCooldown() return 0, 0, 0 end

_G.__petActions = {
	{ name = "Attack",  texture = "Icons\\PetAttack", token = false, active = true },
	{ name = "Follow",  texture = "Icons\\PetFollow", token = false, active = false },
	{ name = "Growl",   texture = "PET_TOKEN_GROWL",   token = true,  active = false,
	  autoAllowed = true, autoEnabled = true },
}
_G.PET_TOKEN_GROWL = "Icons\\PetGrowl"
function GetPetActionInfo(i)
	local a = _G.__petActions[i]
	if not a then return nil end
	return a.name, a.texture, a.token, a.active, a.autoAllowed, a.autoEnabled
end
function GetPetActionsUsable() return true end
function GetPetActionCooldown() return 0, 0, 0 end
_G.__pageHooks = {}
function ChangeActionBarPage(page)
    _G.__actionPage = page
    for _, fn in ipairs(_G.__pageHooks) do fn(page) end
end
-- Both shapes. The object form - hooksecurefunc(obj, "Method", fn) - is what
-- takes ownership of a widget method away from whatever else is setting it, and
-- the chat tabs depend on it: Blizzard fades docked tabs out and the only way to
-- keep them on screen is to be called after every SetAlpha.
function hooksecurefunc(a, b, c)
    if type(a) == "table" then
        local obj, name, fn = a, b, c
        local orig = obj[name]
        if type(orig) ~= "function" then return end
        obj[name] = function(self, ...)
            local r = { orig(self, ...) }
            fn(self, ...)
            return unpack(r)
        end
        return
    end
    local name, fn = a, b
    if name == "ChangeActionBarPage" then
        _G.__pageHooks[#_G.__pageHooks + 1] = fn
        return
    end
    -- Genuinely wrap the global. Swallowing these made the harness agree with any
    -- amount of "we hooked the function that puts Blizzard's look back", which is
    -- exactly the claim that most needs testing.
    local orig = _G[name]
    if type(orig) ~= "function" then return end
    _G[name] = function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end
end
function debugstack() return "Blizzard_ActionBar/ActionBar.lua:412\nFrameXML/MainMenuBar.lua:88" end
function IsModifiedClick() return true end
function GetCVarBool() return false end

local bindings = { ACTIONBUTTON1 = "1", ACTIONBUTTON2 = "SHIFT-BUTTON4", ACTIONBUTTON3 = "NUMPAD7" }
_G.__bindingSet = bindings
function GetBindingKey(name) return bindings[name] end
function GetBindingText(k) return k end

-- SetBinding writes into the *account* binding set, which is why keys assigned
-- in our bind mode survive the addon being turned off. A key can only mean one
-- thing, so assigning it moves it off whatever had it before - the same
-- behaviour Blizzard's own keybinding panel has.
_G.__savedBindingSet = nil
function SetBinding(key, action)
	for name, k in pairs(bindings) do
		if k == key then bindings[name] = nil end
	end
	if action then bindings[action] = key end
	return true
end
function GetCurrentBindingSet() return 1 end
function SaveBindings(which) _G.__savedBindingSet = which end

_G.__modifiedClick = { PICKUPACTION = "SHIFT", SELFCAST = "ALT" }
function GetModifiedClick(name) return _G.__modifiedClick[name] end
function IsAltKeyDown() return _G.__alt or false end
function IsControlKeyDown() return _G.__ctrl or false end

-- Override bindings belong to an *owner*; ClearOverrideBindings(owner) drops
-- only that owner's. Modelling that matters here, because the fix for the dock
-- firing the wrong page is precisely "clear Blizzard's, then set ours".
_G.__overrides = {}
_G.__overrideOwner = {}
_G.__clearedOverrides = {}

function SetOverrideBindingClick(owner, priority, key, button, mouse)
    _G.__overrides[key] = button
    _G.__overrideOwner[key] = owner
end

function ClearOverrideBindings(owner)
    if owner and owner.GetName and owner:GetName() then
        _G.__clearedOverrides[owner:GetName()] = true
    end
    for key, o in pairs(_G.__overrideOwner) do
        if o == owner then
            _G.__overrides[key] = nil
            _G.__overrideOwner[key] = nil
        end
    end
end

function GetBindingAction(key, checkOverride)
    if checkOverride and _G.__overrides[key] then
        return "CLICK " .. _G.__overrides[key] .. ":LeftButton"
    end
    return _G.__bindings and _G.__bindings[key] or ""
end
_G.__stateDrivers = {}
function RegisterStateDriver(frame, state, values) _G.__stateDrivers[state] = values end
function UnregisterStateDriver(frame, state) _G.__stateDrivers[state] = nil end

_G.__unitWatched = {}
function RegisterUnitWatch(f)
	_G.__unitWatched[f] = true
	f.__unitWatch = true
	f.__protected = true          -- the state driver owns its visibility now
end
function UnregisterUnitWatch(f) _G.__unitWatched[f] = nil; f.__unitWatch = nil end

GameTooltip = CreateFrame("Frame", "GameTooltip")
function GameTooltip:SetOwner() end
function GameTooltip:SetAction() end
function GameTooltip:SetText() end
function GameTooltip:AddLine() end

function ToggleDropDownMenu() end
PlayerFrameDropDown = CreateFrame("Frame", "PlayerFrameDropDown")
TargetFrameDropDown = CreateFrame("Frame", "TargetFrameDropDown")

MICRO_BUTTONS = { "CharacterMicroButton", "SpellbookMicroButton" }

-- Classic Era 1.15 names, taken from a real UIParent child dump.
UIParent.__kids = {}
local function uiChild(name, forbidden)
	local f = CreateFrame("Frame", name, UIParent)
	f.__forbidden = forbidden or false
	UIParent.__kids[#UIParent.__kids + 1] = f
	return f
end
uiChild("MainActionBar")
uiChild("MicroMenu")
uiChild("PetActionBar")
-- The in-game shop is forbidden: any method call on it throws in the real
-- client, which is exactly what crashed the first sweep.
local shop = uiChild("CatalogShopFrame", true)
shop.GetName = function() error("calling '?' on bad self") end
shop.IsForbidden = function() return true end
for _, n in ipairs(MICRO_BUTTONS) do CreateFrame("Button", n, UIParent) end
-- Blizzard's own action buttons. They outlive their bars on this client, which
-- is the whole reason HideBlizzard has to reach them individually.
for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton",
	"MultiBarBottomRightButton", "MultiBarLeftButton", "MultiBarRightButton" }) do
	for i = 1, 12 do
		local b = CreateFrame("CheckButton", prefix .. i, UIParent)
		b:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
		b:Show()
	end
end
for _, n in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "MainMenuBar",
	"MultiBarBottomLeft", "MultiBarRight", "PetActionBar", "StanceBar" }) do
	CreateFrame("Frame", n, UIParent)
end
-- Classic Era has no vehicles, but it reuses the vehicle-leave button for
-- "land at the next flight master" on a taxi. It fires a protected action, so
-- the real frame is the only one that works - we adopt it, never rebuild it.
-- Shown from the start, like Blizzard's really is: it is invisible only because
-- the bar it hangs off is hidden. Reparenting it onto a dock of our own is what
-- made it appear, and is why visibility has to come from the game rather than
-- from the frame.
_G.__taxiButton = CreateFrame("Button", "MainMenuBarVehicleLeaveButton", UIParent)
_G.__taxiButton:Show()
_G.__onTaxi = false
function UnitOnTaxi(u) return u == "player" and _G.__onTaxi or false end
function HasExtraActionBar() return false end

-- auras ---------------------------------------------------------------------
-- Classic Era 1.15 signature, no `rank`: name, texture, count, auraType,
-- duration, expirationTime, caster, ..., castByPlayer (13th).
-- Keyed by filter as well as unit: debuffs now come from both units, and a mock
-- that ignored the filter would have handed the player's buffs back as debuffs
-- and quietly "passed".
_G.__auras = {
	player = {
		HELPFUL = {
			{ "Frost Armor",      135843, 0, nil, 1800, nil, "player", true },
			{ "Arcane Intellect", 135932, 0, nil, 1800, nil, "player", true },
			{ "Ice Barrier",      135988, 3, nil,   60, nil, "player", true },
			{ "Well Fed",         133905, 0, nil,    0, nil, nil,      false },  -- permanent
		},
		HARMFUL = {
			{ "Rend",            132155, 0, nil,      12, nil, "boss1", false },
			{ "Curse of Agony",  136139, 0, "Curse",  24, nil, "boss1", false },
		},
	},
	target = {
		HELPFUL = {
			{ "Blessing of Might", 135906, 0, nil, 300, nil, "party1", false },
			{ "Renew",             135953, 0, nil,  15, nil, "player", true },
		},
		HARMFUL = {
			{ "Chilled",           135834, 0, "Magic",  8, nil, "player", true },
			{ "Bleeding",          132090, 2, nil,     12, nil, "boss1",  false },
			{ "Frostbite",         135842, 0, "Magic",  5, nil, "player", true },
			{ "Amplify Curse Of Doom And Everlasting Regret",
			                       136122, 0, "Curse", 60, nil, "player", true },
		},
	},
}
_G.__cancelled = nil
function CancelUnitBuff(unit, index, filter)
    _G.__cancelled = { unit = unit, index = index, filter = filter }
end
function CancelSpellByName(name) _G.__cancelled = { name = name } end

function UnitAura(unit, index, filter)
    local byUnit = _G.__auras[unit]
    local list = byUnit and byUnit[filter or "HELPFUL"]
    if not list then return nil end
    local a = list[index]
    if not a then return nil end
    -- a[9], when present, is an explicit expirationTime. The client hands out
    -- nonsense here for a few seconds after a login: sometimes a duration with a
    -- zero expiry, sometimes both zero. Setting it lets the tests reproduce both.
    local expiration = a[9]
    if expiration == nil then
        expiration = (a[5] and a[5] > 0) and (GetTime() + a[5]) or 0
    end
    return a[1], a[2], a[3], a[4], a[5], expiration, a[7],
           nil, nil, nil, nil, nil, a[8]
end

-- minimap --------------------------------------------------------------------
-- The real Minimap is a widget type the client draws into and cannot be
-- recreated, so the module reshapes Blizzard's. Everything it touches on that
-- object is modelled here, plus the furniture it banishes.
Minimap = CreateFrame("Frame", "Minimap")
Minimap:SetSize(140, 140)
function Minimap:SetMaskTexture(t) self.__mask = t end
function Minimap:GetZoom() return self.__zoom or 0 end
function Minimap:SetZoom(z) self.__zoom = z end
function Minimap_ZoomInClick() Minimap:SetZoom(math.min(5, Minimap:GetZoom() + 1)) end
function Minimap_ZoomOutClick() Minimap:SetZoom(math.max(0, Minimap:GetZoom() - 1)) end
function Minimap_OnClick() _G.__minimapPinged = true end

MinimapCluster = CreateFrame("Frame", "MinimapCluster")
function MinimapCluster:EnableMouse(v) self.__mouse = v end
Minimap:SetParent(MinimapCluster)

-- MinimapBackdrop is the parent of the round-edge buttons on this client, not
-- the cluster - which is why the sweep has to recurse rather than stop at the
-- top.
MinimapBackdrop = CreateFrame("Frame", "MinimapBackdrop", MinimapCluster)
for _, n in ipairs({
	"MinimapZoomIn", "MinimapZoomOut", "MiniMapTracking",
	"MiniMapBattlefieldFrame", "GameTimeFrame", "MiniMapMailFrame",
}) do
	CreateFrame("Frame", n, MinimapBackdrop)
end
for _, n in ipairs({
	"MinimapBorder", "MinimapBorderTop", "MinimapNorthTag",
	"MinimapToggleButton", "MinimapZoneTextButton", "MinimapCompassTexture",
}) do
	CreateFrame("Frame", n, MinimapCluster)
end
-- MiniMapWorldMapButton is deliberately absent: it is Wrath+ only, and a module
-- that reached for it here would be reaching for it in the game too.

-- An anonymous texture on the cluster, and an addon's frame sitting on it. The
-- sweep has to take the first and leave the second.
_G.__clusterArt = MinimapCluster:CreateTexture(nil, "OVERLAY")
CreateFrame("Frame", "SomeAddonOnTheCluster", MinimapCluster)

MiniMapTrackingDropDown = CreateFrame("Frame", "MiniMapTrackingDropDown")
function ToggleDropDownMenu() _G.__trackingMenu = true end

-- The client's `date` is Lua's, and the sandbox this runs in has os stripped.
date = date or function(fmt) return "18:41" end
function GetMinimapZoneText() return _G.__zoneText or "The Barrens" end
function GetZoneText() return "The Barrens" end
function GetSubZoneText() return _G.__zoneText or "" end
GetZonePVPInfo = function() return _G.__pvpType end
function HasNewMail() return _G.__mail or false end
HAVE_MAIL = "You have unread mail"

-- C_Map has two separate ways to answer "nowhere": no map for the unit, and a
-- map with no position on it - which is what an instance does.
C_Map = {
	GetBestMapForUnit = function() return _G.__uiMap end,
	GetPlayerMapPosition = function(uiMap, unit)
		if not uiMap or not _G.__playerPos then return nil end
		return { x = _G.__playerPos[1], y = _G.__playerPos[2] }
	end,
}
_G.__uiMap = 1413
_G.__playerPos = { 0.45, 0.58 }

-- Blizzard's globals are secure and an addon's are not; the module leans on that
-- to sort furniture from arrivals without a hardcoded list.
_G.__secureNames = {}
for _, n in ipairs({
	"Minimap", "MinimapCluster", "MinimapBorder", "MinimapBorderTop",
	"MinimapNorthTag", "MinimapZoomIn", "MinimapZoomOut", "MinimapToggleButton",
	"MinimapZoneTextButton", "MiniMapTracking", "MiniMapBattlefieldFrame",
	"GameTimeFrame", "MinimapCompassTexture", "MiniMapMailFrame",
	"MinimapBackdrop",
}) do
	_G.__secureNames[n] = true
end
function issecurevariable(a, b)
	local name = b or a
	return _G.__secureNames[name] or false
end

C_Timer = C_Timer or {}
_G.__tickers = {}
function C_Timer.NewTicker(interval, fn, iterations)
	local t = { fn = fn, left = iterations, cancelled = false }
	function t:Cancel() self.cancelled = true end
	_G.__tickers[#_G.__tickers + 1] = t
	return t
end
function C_Timer.After(_, fn) fn() end
--- Run every live ticker once, the way the client would.
function _G.__tick()
	for _, t in ipairs(_G.__tickers) do
		if not t.cancelled then t.fn() end
	end
end

-- quests ---------------------------------------------------------------------
-- Classic Era's legacy quest API. GetQuestLogTitle has EIGHT returns here with
-- questID last, which is the shape RXPGuides and Questie use on this client and
-- is not Retail's ordering. Headers occupy log indices too, and indices shift
-- when a quest is accepted or abandoned - both are modelled, because the tracker
-- must never hold an index across a frame.
_G.__questLog = {
	{ header = true,  title = "The Barrens" },
	{ id = 861,  title = "Chen's Empty Keg",        level = 15,
	  objectives = { { "Empty Keg: 0/1", "item", false } } },
	{ id = 1069, title = "Harpy Raiders",           level = 16, complete = 1,
	  objectives = { { "Witchwing Harpy slain: 10/10", "monster", true } } },
	{ header = true,  title = "Stonetalon Mountains" },
	{ id = 4901, title = "Prowlers of the Barrens", level = 17,
	  objectives = { { "Savannah Prowler slain: 3/8",  "monster", false },
	                 { "Savannah Huntress slain: 1/4", "monster", false } } },
	{ id = 5041, title = "Lost in Battle",          level = 18,
	  objectives = {} },
}
_G.__watches = {}          -- Blizzard's watch list: log indices
_G.MAX_QUESTS = 20

function GetNumQuestLogEntries()
	local quests = 0
	for _, q in ipairs(_G.__questLog) do
		if not q.header then quests = quests + 1 end
	end
	return #_G.__questLog, quests
end

function GetQuestLogTitle(index)
	local q = _G.__questLog[index]
	if not q then return nil end
	-- title, level, questTag, isHeader, isCollapsed, isComplete, frequency, questID
	return q.title, q.level, nil, q.header or false, false, q.complete, nil, q.id
end

function GetNumQuestLeaderBoards(index)
    local q = _G.__questLog[index]
    return (q and q.objectives) and #q.objectives or 0
end

function GetQuestLogLeaderBoard(j, index)
    local q = _G.__questLog[index]
    local o = q and q.objectives and q.objectives[j]
    if not o then return nil end
    return o[1], o[2], o[3]
end

function GetNumQuestWatches() return #_G.__watches end
function GetQuestIndexForWatch(i) return _G.__watches[i] end
function AddQuestWatch(index) _G.__watches[#_G.__watches + 1] = index end
function RemoveQuestWatch(index)
    for i = #_G.__watches, 1, -1 do
        if _G.__watches[i] == index then table.remove(_G.__watches, i) end
    end
end

_G.__questLogOpenedTo, _G.__questSelected, _G.__questShared, _G.__abandonPopup = nil, nil, nil, nil
function QuestLog_OpenToQuest(index) _G.__questLogOpenedTo = index end
function SelectQuestLogEntry(index) _G.__questSelected = index end
function QuestLogPushQuest() _G.__questShared = _G.__questSelected end
function SetAbandonQuest() end
function StaticPopup_Show(which) _G.__abandonPopup = which end
function ShowUIPanel() end

-- xp ------------------------------------------------------------------------
_G.__xp, _G.__xpMax, _G.__rested = 8600, 10000, 1200
function UnitXP() return _G.__xp end
function UnitXPMax() return _G.__xpMax end
function GetXPExhaustion() return _G.__rested end
function GetMaxPlayerLevel() return 60 end
MAX_PLAYER_LEVEL = 60

-- WoW exposes the string/table library as bare globals; libs rely on them.
strmatch, strfind, strsub, strlower, strupper, strrep, strjoin, strsplit =
	string.match, string.find, string.sub, string.lower, string.upper, string.rep, nil, nil
format, gsub, strtrim = string.format, string.gsub, function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
tinsert, tremove, tsort = table.insert, table.remove, table.sort
max, min, abs, floor, ceil = math.max, math.min, math.abs, math.floor, math.ceil
function geterrorhandler() return function(e) fail("errorhandler: " .. tostring(e)) end end
-- CallbackHandler dispatches through this; the real client provides it.
function securecallfunction(fn, ...) return fn(...) end
function securecall(fn, ...) return fn(...) end

function GetRealmName() return "Nethergarde Keep" end
function GetLocale() return "enGB" end
function GetSpecialization() return nil end
function GetNumClasses() return 9 end
function UnitFactionGroup() return "Horde", "Horde" end
function UnitRace2() end
function GetCurrentRegion() return 3 end
function UnitSex() return 2 end

RAID_CLASS_COLORS = {
	MAGE  = { r = 0.41, g = 0.80, b = 0.94 },
	ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
}

-- unit state -----------------------------------------------------------------

local units = {
	player = {
		exists = true, name = "Palabras", level = 15, isPlayer = true,
		race = "Undead", class = "Mage", classToken = "MAGE",
		hp = 208, hpMax = 371, power = 480, powerMax = 1000,
		powerType = 0, powerToken = "MANA", reaction = 5,
	},
	target = {
		exists = true, name = "Savannah Prowler", level = 16, isPlayer = false,
		creature = "Beast", hp = 640, hpMax = 1000,
		power = 0, powerMax = 0, powerType = 0, powerToken = "MANA", reaction = 2,
	},
}
_G.__units = units

function UnitExists(u) return units[u] and units[u].exists or false end
function UnitName(u) return units[u] and units[u].name end
function UnitLevel(u) return units[u] and units[u].level or 0 end
function UnitIsPlayer(u) return units[u] and units[u].isPlayer or false end
function UnitIsDeadOrGhost(u) return units[u] and units[u].dead or false end
function UnitRace(u) return units[u] and units[u].race end
function UnitClass(u) local d = units[u]; return d and d.class, d and d.classToken end
function UnitCreatureType(u) return units[u] and units[u].creature end
function UnitHealth(u) return units[u] and units[u].hp or 0 end
function UnitHealthMax(u) return units[u] and units[u].hpMax or 0 end
function UnitPower(u) return units[u] and units[u].power or 0 end
function UnitPowerMax(u) return units[u] and units[u].powerMax or 0 end
function UnitPowerType(u) local d = units[u]; return d and d.powerType or 0, d and d.powerToken or "MANA" end
function UnitReaction(u) return units[u] and units[u].reaction end
-- PLAYER_FLAGS_CHANGED carries the unit whose flags moved, and the client
-- sets this by itself after five minutes without input.
function UnitIsAFK(u) return units[u] and units[u].afk or false end
function UnitIsDND(u) return units[u] and units[u].dnd or false end

local castState
function UnitCastingInfo(u)
	if u ~= "player" or not castState or castState.channel then return nil end
	return castState.name, castState.name, castState.icon, castState.startTime, castState.endTime
end
function UnitChannelInfo(u)
	if u ~= "player" or not castState or not castState.channel then return nil end
	return castState.name, castState.name, castState.icon, castState.startTime, castState.endTime
end

C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }

-- ---------------------------------------------------------------------------
-- loading
-- ---------------------------------------------------------------------------

local ADDON = "AetherUI"
local A = {}

local function load(path)
	local chunk, err = loadfile(path)
	if not chunk then
		fail("load " .. path .. ": " .. tostring(err))
		return
	end
	local ok, e = pcall(chunk, ADDON, A)
	if not ok then fail("run " .. path .. ": " .. tostring(e)) end
end

-- real libs, so the AceDB defaults merge is exercised for real
load("Libs/LibStub/LibStub.lua")
load("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
load("Libs/AceDB-3.0/AceDB-3.0.lua")

-- LibClassicCasterino bails on any non-Classic client, and the mock is not one,
-- so stand in for it. The point under test is our wiring, not the library.
WOW_PROJECT_ID, WOW_PROJECT_CLASSIC = 2, 2
do
	local lib = LibStub:NewLibrary("LibClassicCasterino", 37)
	lib.callbacks = LibStub("CallbackHandler-1.0"):New(lib)
	_G.__ccCasts = {}
	function lib:UnitCastingInfo(unit)
		local c = _G.__ccCasts[unit]
		if c and not c.channel then return c.name, nil, c.icon, c.start, c.finish end
	end
	function lib:UnitChannelInfo(unit)
		local c = _G.__ccCasts[unit]
		if c and c.channel then return c.name, nil, c.icon, c.start, c.finish end
	end
    _G.__ccFire = function(event, unit) lib.callbacks:Fire(event, unit) end
end

-- A stand-in LibDBIcon, because the real one belongs to whichever addon on the
-- machine shipped a copy. Only the surface the module actually uses.
do
	local ldbi = LibStub:NewLibrary("LibDBIcon-1.0", 56)
	ldbi.objects = {}
	ldbi.callbacks = LibStub("CallbackHandler-1.0"):New(ldbi)
	function ldbi:GetButtonList()
		local out = {}
		for name in pairs(self.objects) do out[#out + 1] = name end
		table.sort(out)
		return out
	end
	function ldbi:GetMinimapButton(name) return self.objects[name] end
	function ldbi:IsRegistered(name) return self.objects[name] ~= nil end
	function ldbi:Lock(name)
		local b = self.objects[name]
		if b then b.__locked = true end
	end
	--- Make one the way an addon would, and announce it.
	function _G.__makeDBIcon(name)
		local b = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
		b:SetSize(31, 31)
		-- The real library pins both, so that reparenting cannot shuffle its
		-- buttons behind something. It also means an outside SetFrameStrata is
		-- quietly refused until the pin is released.
		b:SetFrameStrata("MEDIUM")
		b:SetFrameLevel(8)
		b.__fixedStrata, b.__fixedLevel = true, true
		-- the real library gives every button these three, by name
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.border = b:CreateTexture(nil, "OVERLAY")
		b.background = b:CreateTexture(nil, "BACKGROUND")
		b:SetScript("OnDragStart", function() end)
		b:SetScript("OnDragStop", function() end)
		ldbi.objects[name] = b
		ldbi.callbacks:Fire("LibDBIcon_IconCreated", b, name)
		return b
	end
end



-- chat -----------------------------------------------------------------------
--
-- Enough of Blizzard's chat furniture to skin. The names matter: CHAT_FRAMES
-- holds name *strings*, the backdrop regions are `<frame><suffix>` globals, and
-- the tab art has global names that do not match its parentKeys - all three are
-- things Modules/Chat.lua has to get right and all three are silent when wrong.
CHAT_FRAME_TEXTURES = {
	"Background",
	"TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
}
CHAT_FRAMES = {}

GeneralDockManager = CreateFrame("Frame", "GeneralDockManager")
GeneralDockManager:SetSize(400, 20)
GeneralDockManager.selected = 1
GeneralDockManager.DOCKED_CHAT_FRAMES = {}

-- Modelled the way Blizzard actually ships it on Classic Era, because the shape
-- of it is the bug. The real function is a *mixin method*, copied onto every edit
-- box when the frame is created; the familiar `ChatEdit_UpdateHeader` global is a
-- dead snapshot taken once at load in Blizzard_DeprecatedChatInfo and is never
-- called by anything. Hooking that global installs cleanly, fires never, and
-- reports nothing - which is exactly how two attempts at this silently did
-- nothing at all.
ChatFrameEditBoxMixin = {}
function ChatFrameEditBoxMixin:UpdateHeader()
	self.header:SetText("Say:")
	self.header:SetAlpha(1)
	self:SetTextInsets(46, 0, 0, 0)
end
ChatEdit_UpdateHeader = ChatFrameEditBoxMixin.UpdateHeader

local function MakeChatFrame(id)
	local name = "ChatFrame" .. id
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(430, 180)
	f.__id = id
	function f:GetID() return self.__id end
	function f:SetFading(v) self.__fading = v end
	function f:SetTimeVisible(v) self.__timeVisible = v end
	function f:SetFont(path, size, flags)
		self.__font = { path, size, flags }
	end
	function f:GetFont() return (self.__font or {})[1], (self.__font or {})[2] or 13 end
	function f:SetShadowColor() end
	function f:SetShadowOffset() end

	for _, suffix in ipairs(CHAT_FRAME_TEXTURES) do
		local t = f:CreateTexture(name .. suffix)
		_G[name .. suffix] = t
	end

	f.ScrollToBottomButton = CreateFrame("Button", nil, f)
	f.buttonFrame = CreateFrame("Frame", name .. "ButtonFrame", f)
	_G[name .. "ButtonFrame"] = f.buttonFrame
	f.ResizeButton = CreateFrame("Button", name .. "ResizeButton", f)
	_G[name .. "ResizeButton"] = f.ResizeButton

	local tab = CreateFrame("Button", name .. "Tab", GeneralDockManager)
	tab.__id = id
	function tab:GetID() return self.__id end
	for _, set in ipairs({ "", "Selected", "Highlight" }) do
		for _, piece in ipairs({ "Left", "Middle", "Right" }) do
			_G[name .. "Tab" .. set .. piece] = tab:CreateTexture()
		end
	end
	_G[name .. "TabGlow"] = tab:CreateTexture()
	_G[name .. "TabFlash"] = tab:CreateTexture()
	local txt = tab:CreateFontString(name .. "TabText")
	txt:SetText("Chat " .. id)
	_G[name .. "TabText"] = txt
	function tab:GetFontString() return txt end

	-- The real one is a ScrollingMessageFrame method that Modules/Chat.lua wraps
	-- to take Blizzard's channel bracket off the front of a finished line, so it
	-- has to exist before the addon loads.
	f.__lines = {}
	-- The signature matters: the handler calls
	-- `self:AddMessage(outMsg, info.r, info.g, info.b, info.id, ...)`, and that
	-- id is the only thing that says what a finished line *is*. Modules/Chat.lua
	-- reads it to dim system lines without touching a single event argument.
	function f:AddMessage(text, r, g, b, id)
		self.__last = text
		self.__lastID = id
		self.__lines[#self.__lines + 1] = text
	end
	function f:Clear() self.__lines = {} end

	-- Message groups are *methods* on Classic Era; the familiar
	-- ChatFrame_AddMessageGroup globals are aliases in
	-- Blizzard_DeprecatedChatInfo, behind a cvar, and are deliberately not
	-- defined anywhere in this harness for exactly that reason.
	f.__groups = {}
	function f:AddMessageGroup(g) self.__groups[g] = true end
	function f:RemoveMessageGroup(g) self.__groups[g] = nil end
	function f:ContainsMessageGroup(g) return self.__groups[g] == true end
	function f:RemoveAllMessageGroups() self.__groups = {} end
	function f:RemoveAllChannels() end
	function f:ReceiveAllPrivateMessages() end

	local eb = CreateFrame("EditBox", name .. "EditBox", f)
	eb.__attrs = {}
	function eb:GetAttribute(k) return self.__attrs[k] end
	function eb:SetAttribute(k, v) self.__attrs[k] = v end
	function eb:GetText() return self.__text or "" end
	function eb:SetTextInsets() end
	function eb:SetFont(path, size, flags) self.__font = { path, size, flags } end
	eb:SetAttribute("chatType", "CHANNEL")
	for _, suffix in ipairs({ "Left", "Right", "Mid",
		"FocusLeft", "FocusRight", "FocusMid" }) do
		_G[name .. "EditBox" .. suffix] = eb:CreateTexture()
	end
	for k, v in pairs(ChatFrameEditBoxMixin) do eb[k] = v end   -- XML mixin= copy
	function eb:ClearHistory() end
	eb.header = eb:CreateFontString(name .. "EditBoxHeader")
	eb.prompt = eb:CreateFontString(name .. "EditBoxPrompt")
	eb.header:SetText("Say:")
	function eb:SetTextInsets(l) self.__insetL = l end
	f.editBox = eb

	-- Docked is the default, and it is what decides whether this window's edit
	-- box capsule belongs on the shared panel or on the window itself.
	f.isDocked = true

	-- The general window subscribes to whispers by default, which is the thing
	-- the whispers tab moves off it.
	if id == 1 then
		for _, g in ipairs({ "SAY", "YELL", "GUILD", "PARTY", "CHANNEL",
			"WHISPER", "BN_WHISPER" }) do
			f.__groups[g] = true
		end
	end

	CHAT_FRAMES[#CHAT_FRAMES + 1] = name
	GeneralDockManager.DOCKED_CHAT_FRAMES[#GeneralDockManager.DOCKED_CHAT_FRAMES + 1] = f
	return f
end

MakeChatFrame(1)
MakeChatFrame(2)

--- id, name, instanceID. ChannelLabel takes the second return.
function GetChannelName(target)
	return 1, "General", 0
end

function FCF_GetChatWindowInfo(id)
	return "Chat " .. tostring(id), 14, 1, 1, 1, 1, true, false, true, false
end
function FCFTab_UpdateColors() end
function FCFDock_SelectWindow() end
function FCFDock_UpdateTabs() end
function FloatingChatFrame_Update() end
function FCF_SetChatWindowFontSize() end
function FCF_OpenTemporaryWindow() end
function FCF_SetButtonSide() end
function FCF_FadeInChatFrame() end

-- ---------------------------------------------------------------------------
-- the message lines
--
-- Modelled on Blizzard_ChatFrameBase, not invented, because the whole point of
-- the line work is *where* each piece of a line is assembled - and a mock that
-- puts the pieces together in a different order would prove nothing about the
-- addon that runs against the real one.
--
--   Shared/ChatFrameFilters.lua   the two filter registries
--   Shared/ChatFrameUtil.lua      GetDecoratedSenderName, GetOutMessageFormatKey
--   Classic/ChatFrameOverrides.lua  the handler that puts a line together
-- ---------------------------------------------------------------------------

ChatFrameUtil = {}

do
	local senderFilters, eventFilters = {}, {}

	function ChatFrameUtil.AddSenderNameFilter(cb)
		for _, f in ipairs(senderFilters) do if f == cb then return end end
		senderFilters[#senderFilters + 1] = cb
	end

	function ChatFrameUtil.RemoveSenderNameFilter(cb)
		for i, f in ipairs(senderFilters) do
			if f == cb then table.remove(senderFilters, i) return end
		end
	end

	--- Faithful to the real one in the way that matters: a callback returning
	--  nil leaves the name alone rather than blanking it, and the chain carries
	--  the running value forward.
	function ChatFrameUtil.ProcessSenderNameFilters(event, name, ...)
		for _, cb in ipairs(senderFilters) do
			local ok, replacement = pcall(cb, event, name, ...)
			if ok and replacement ~= nil then name = replacement end
		end
		return name
	end

	function ChatFrameUtil.AddMessageEventFilter(event, cb)
		eventFilters[event] = eventFilters[event] or {}
		local list = eventFilters[event]
		for _, f in ipairs(list) do if f == cb then return end end
		list[#list + 1] = cb
	end

	function ChatFrameUtil.RemoveMessageEventFilter(event, cb)
		local list = eventFilters[event]
		if not list then return end
		for i, f in ipairs(list) do if f == cb then table.remove(list, i) return end end
	end

	function ChatFrameUtil.ProcessMessageEventFilters(frame, event, ...)
		local args = { ... }
		local n = select("#", ...)
		for _, cb in ipairs(eventFilters[event] or {}) do
			local out = { pcall(cb, frame, event, unpack(args, 1, n)) }
			if out[1] then
				if out[2] then return true end            -- discard, stop the chain
				if out[3] ~= nil then
					for i = 1, n do args[i] = out[i + 2] end
				end
			end
		end
		return false, unpack(args, 1, n)
	end

	function ChatFrameUtil.GetSenderNameFilters() return senderFilters end
end

--- Reads _G["CHAT_"..subtype.."_GET"] and asserts the key exists, which is why
--  Modules/Chat.lua reshapes these strings rather than clearing them.
function ChatFrameUtil.GetOutMessageFormatKey(subtype)
	local key = _G["CHAT_" .. subtype .. "_GET"]
	if key == nil then fail("no CHAT_" .. subtype .. "_GET") end
	return key or ""
end

function ChatFrameUtil.ResolvePrefixedChannelName(name) return name end

--- The order here is the fact the whole module leans on: Blizzard class-colours
--  the name, *then* runs the sender-name filters, and only afterwards does the
--  caller wrap the result in a player link. So a filter's return value becomes
--  link display text and never the link target.
function ChatFrameUtil.GetDecoratedSenderName(event, ...)
	local _, senderName, _, _, _, _, _, _, _, _, _, senderGUID = ...
	local chatType = event:sub(10)
	local name = senderName

	local info = ChatTypeInfo[chatType]
	if senderGUID and info and info.colorNameByClass then
		local _, class = GetPlayerInfoByGUID(senderGUID)
		local c = class and RAID_CLASS_COLORS[class]
		if c then
			name = string.format("|cff%02x%02x%02x%s|r",
				c.r * 255, c.g * 255, c.b * 255, name)
		end
	end

	return ChatFrameUtil.ProcessSenderNameFilters(event, name, ...)
end

CHAT_SAY_GET             = "%s says: "
CHAT_YELL_GET            = "%s yells: "
CHAT_WHISPER_GET         = "%s whispers: "
CHAT_WHISPER_INFORM_GET  = "To %s: "
CHAT_BN_WHISPER_GET      = "%s whispers: "
CHAT_BN_WHISPER_INFORM_GET = "To %s: "
CHAT_PARTY_GET           = "%s: "
CHAT_PARTY_LEADER_GET    = "%s: "
CHAT_RAID_GET            = "%s: "
CHAT_RAID_LEADER_GET     = "%s: "
CHAT_RAID_WARNING_GET    = "%s: "
CHAT_GUILD_GET           = "%s: "
CHAT_OFFICER_GET         = "%s: "
CHAT_CHANNEL_GET         = "%s: "
-- Two format arguments, so it must be left exactly as it is. If the reshaping
-- in Modules/Chat.lua ever stops checking, this is what breaks first.
CHAT_CHANNEL_NOTICE_GET  = "[%d. %s] "

-- `id` is the chat type index the handler hands to AddMessage alongside the
-- text. Real entries carry one; it is what makes a finished line identifiable.
ChatTypeInfo = setmetatable({
	SAY     = { id = 1,  r = 1.00, g = 1.00, b = 1.00, colorNameByClass = true },
	YELL    = { id = 2,  r = 1.00, g = 0.25, b = 0.25, colorNameByClass = true },
	PARTY   = { id = 3,  r = 0.66, g = 0.66, b = 1.00, colorNameByClass = true },
	GUILD   = { id = 4,  r = 0.25, g = 1.00, b = 0.25, colorNameByClass = true },
	OFFICER = { id = 5,  r = 0.25, g = 0.75, b = 0.25, colorNameByClass = true },
	WHISPER = { id = 6,  r = 1.00, g = 0.50, b = 1.00, colorNameByClass = true },
	WHISPER_INFORM = { id = 7, r = 1.00, g = 0.50, b = 1.00 },
	CHANNEL = { id = 8,  r = 1.00, g = 0.75, b = 0.75 },
	SYSTEM  = { id = 9,  r = 1.00, g = 1.00, b = 0.00 },
	CHANNEL_NOTICE      = { id = 10, r = 1.00, g = 0.75, b = 0.75 },
	CHANNEL_NOTICE_USER = { id = 11, r = 1.00, g = 0.75, b = 0.75 },
}, { __index = function(t, k)
	-- CHANNEL1..10 are real keys on a live client and the module asks for them
	-- by index, so a missing one is a nil access rather than a fallback.
	if type(k) == "string" and k:match("^CHANNEL%d+$") then return t.CHANNEL end
	return nil
end })

-- Added to, not replaced: the unit frame tests upstream already lean on what is
-- in there.
RAID_CLASS_COLORS.WARLOCK = { r = 0.58, g = 0.51, b = 0.79 }
RAID_CLASS_COLORS.WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }

local GUID_CLASS = {
	["Player-4700-0000A1"] = "MAGE",
	["Player-4700-0000B2"] = "WARLOCK",
}

function GetPlayerInfoByGUID(guid)
	local class = GUID_CLASS[guid]
	if not class then return nil end
	return class:sub(1, 1) .. class:sub(2):lower(), class
end

function Ambiguate(name) return name end

--- The link is built *around* the display text, from the raw sender name. That
--  is the whole safety argument for the sender-name filter, so the harness
--  builds it the same way and the assertions read the target back out.
function GetPlayerLink(name, displayText, lineID)
	return "|Hplayer:" .. name .. ":" .. tostring(lineID or 0) .. "|h"
		.. tostring(displayText) .. "|h"
end

GENERAL, TRADE, LOOKING_FOR_GROUP = "General", "Trade", "LookingForGroup"
LOCAL_DEFENSE, WORLD_DEFENSE = "LocalDefense", "WorldDefense"

--- One chat message, assembled the way Classic/ChatFrameOverrides.lua does it.
function DeliverChatMessage(frame, event, ...)
	local discard, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 =
		ChatFrameUtil.ProcessMessageEventFilters(frame, event, ...)
	if discard then return nil end

	local kind = event:sub(10)
	local info = ChatTypeInfo[kind] or ChatTypeInfo.SYSTEM

	-- The reassignment that decides what a channel *notice* is tagged with. The
	-- handler tests `strsub(type, 1, 7) == "CHANNEL"`, which catches
	-- CHANNEL_NOTICE and CHANNEL_NOTICE_USER as well as chat, and swaps in the
	-- channel's own info - so a notice reaches AddMessage carrying the
	-- channel's id, never the notice type's. Modelled here because without it
	-- the harness would happily pass a DIM_TYPES list that dims nothing in game.
	if kind:sub(1, 7) == "CHANNEL" and kind ~= "CHANNEL_LIST" and a8 and a8 ~= 0 then
		info = ChatTypeInfo["CHANNEL" .. a8] or info
	end

	local out

	if kind == "SYSTEM" then
		out = a1
	elseif kind == "CHANNEL_NOTICE" or kind == "CHANNEL_NOTICE_USER" then
		-- arg1 here is a *token*, not a message: the handler turns it into a
		-- global-string key. Anything that colours or otherwise rewrites it
		-- produces a nil lookup and a Lua error on every login, which is what
		-- an earlier version of the system-line dimming did.
		local globalstring = _G["CHAT_" .. tostring(a1) .. "_NOTICE"]
		if type(globalstring) ~= "string" then
			fail("CHAT_" .. tostring(a1) .. "_NOTICE is nil - arg1 was rewritten")
			return nil
		end
		out = string.format(globalstring, ChatFrameUtil.ResolvePrefixedChannelName(a4))
	else
		local coloredName = ChatFrameUtil.GetDecoratedSenderName(event,
			a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
		-- `playerLinkDisplayText = ("[%s]"):format(coloredName)` for everything
		-- that is not an emote. The brackets are added after the sender-name
		-- filter has run, so the badge lands inside them.
		local display = kind == "EMOTE" and coloredName or ("[" .. coloredName .. "]")
		local playerLink = GetPlayerLink(a2, display, a11)
		out = string.format(ChatFrameUtil.GetOutMessageFormatKey(kind) .. a1, playerLink)
		if a4 and a4 ~= "" then
			out = "|Hchannel:channel:" .. tostring(a8) .. "|h["
				.. ChatFrameUtil.ResolvePrefixedChannelName(a4) .. "]|h " .. out
		end
	end

	frame:AddMessage(out, info.r, info.g, info.b, info.id)
	return frame.__last
end

CHAT_YOU_CHANGED_NOTICE = "Changed Channel: %s"
CHAT_YOU_JOINED_NOTICE  = "Joined Channel: %s"

--- Opens a window, docks it, names it. `noDefaultChannels` is the argument that
--  makes the difference between a whispers tab and a second general window.
function FCF_OpenNewWindow(name, noDefaultChannels)
	local f = MakeChatFrame(#CHAT_FRAMES + 1)
	f.name = name
	f.isDocked = true
	if not noDefaultChannels then
		for _, g in ipairs({ "SAY", "YELL", "GUILD", "PARTY", "CHANNEL" }) do
			f:AddMessageGroup(g)
		end
	end
	return f, f:GetID()
end
-- Blizzard rewrites the header every time the box is focused or the channel
-- changes. Blanking it once at skin time was only ever going to hold until the
-- next keystroke, which is what put the grey text back on screen.


print("== loading addon files ==")
for _, f in ipairs({
	"Core/Core.lua", "Core/Media.lua", "Core/Palette.lua", "Core/Glass.lua",
	"Core/Widgets.lua", "Core/Config.lua", "Core/Movers.lua", "Core/Fader.lua",
	"Core/Commands.lua", "Core/Options.lua",
	"Modules/UnitFrames.lua", "Modules/ActionBars.lua", "Modules/Auras.lua",
	"Modules/QuestTracker.lua", "Modules/Minimap.lua", "Modules/XPBar.lua",
	"Modules/Chat.lua",
	"Modules/Zen.lua",
}) do
	load(f)
end

-- ---------------------------------------------------------------------------
-- drive a session
-- ---------------------------------------------------------------------------

local pump = A.pump

local function fire(event, ...)
	local fn = pump:GetScript("OnEvent")
	if fn then
		local ok, err = pcall(fn, pump, event, ...)
		if not ok then fail("event " .. event .. ": " .. tostring(err)) end
	end
end

local function tick(dt)
	time = time + dt
	local fn = pump:GetScript("OnUpdate")
	if fn then
		local ok, err = pcall(fn, pump, dt)
		if not ok then fail("OnUpdate: " .. tostring(err)) end
	end
end

print("== boot ==")
AetherUIDB = nil
fire("ADDON_LOADED", ADDON)
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")

print("== assertions ==")

local function check(cond, msg)
	if cond then
		print("  ok  " .. msg)
	else
		fail(msg)
	end
end

local UF = A:GetModule("unitframes")
check(UF and UF.enabled, "unitframes module enabled")
check(UF.player and UF.target, "player and target capsules built")
check(UF.cast ~= nil, "cast bar built")
check(A.db and A.db.profile.skin == "midnight", "db initialised with default skin")
check(#UF.player.glass._fill == 3, "player capsule uses the 3-slice pill")
do
	-- Both caps must come out the same width. The frame's left and right edges
	-- sit at different sub-pixel phases, so `left + cap` and `right - cap` round
	-- in opposite directions unless cap is a whole number of physical pixels -
	-- one cap a pixel wider than the other, and the join between the arc and the
	-- straight edge a pixel out of true on that side.
	local L = UF.player.glass._fill[1]:GetWidth()
	local R = UF.player.glass._fill[3]:GetWidth()
	check(L == R, ("the two cap slices are the same width (%s vs %s)")
		:format(tostring(L), tostring(R)))
	local step = (A.pixel or 1) * (UIParent:GetEffectiveScale() or 1)
		/ (UF.player.glass:GetEffectiveScale() or 1)
	check(math.abs(L / step - math.floor(L / step + 0.5)) < 1e-6,
		"and land on a whole number of physical pixels")
end
do
	-- Pixel snapping stays ON. Turning it off was tried and made it worse; see
	-- the note at the top of Core/Glass.lua.
	local bad
	for _, set in ipairs({ UF.player.glass._fill, UF.player.glass._edge }) do
		for _, tex in ipairs(set) do
			if tex.__snap ~= nil then bad = true end
		end
	end
	check(not bad,
		"and none of them touches pixel snapping. These slices abut, so snapped"
		.. " they land on the same integer pixel and tile; unsnapped they land on"
		.. " the same fractional one, the boundary pixel is covered by both, and"
		.. " the rim there gets blended twice - a bright dot at every corner")
end
check(UF.player.glass._noise == nil and UF.player.glass.SetNoiseStrength == nil,
	"no runtime noise layer: grain is baked into the fill textures")
check(UF.player.glass._shadow and #UF.player.glass._shadow == 3,
	"pill gets the capsule-shaped 3-slice shadow")
check(UF.player.glass ~= UF.player and UF.player.glass.SetHeight ~= nil,
	"the glass is a separate frame from the layout core, so it can grow in combat")
do
	local panel = A.Glass.CreatePanel(UIParent, { shadow = 10 })
	check(panel._shadow and #panel._shadow == 9, "panel gets the rectangular 9-slice shadow")
end
do
	local cfg = A.db.profile.modules.unitframes
	local need = 10 + cfg.orbSize + 13 + cfg.barWidth + 12 + 40 + 24
	check(cfg.width >= need, "default capsule width fits its contents ("
		.. cfg.width .. " >= " .. need .. ")")
end
check(UF.player.name:GetText() == "Palabras", "player name populated")
check(UF.target.name:GetText() == "Savannah Prowler", "target name populated")
check(UF.player.orb.label:GetText() == "15", "player level in the orb")
check(UF.target.sub:GetText() == "Beast · Lv 16", "target subtitle from creature type")
check(UF.player.hpText:GetText() == "208", "player health readout")
check(UF.target.hpText:GetText() == "64%", "target health shown as a percentage")
do
	local hp, hrel = UF.player.hpText:GetPoint(1)
	local mp, mrel = UF.player.mpText:GetPoint(1)
	check(hrel == UF.player.health and mrel == UF.player.power,
		"each readout is anchored to its own bar, so a missing power bar cannot"
		.. " leave the health number floating high")
	check(hp == "LEFT" and mp == "LEFT", "player readouts sit to the right of the bars")
	local thp, threl = UF.target.hpText:GetPoint(1)
	check(thp == "RIGHT" and threl == UF.target.health, "target readout mirrors")
end

print("== health / power churn ==")
_G.__units.player.hp = 120
fire("UNIT_HEALTH", "player")
for i = 1, 40 do tick(0.1) end
check(math.abs(UF.player.health:GetValue() - 120) < 1, "smoothed health converges on the new value")
check(UF.player.hpText:GetText() == "120", "health text follows")

_G.__units.player.power = 90
fire("UNIT_POWER_UPDATE", "player")
check(UF.player.power:GetValue() ~= nil, "power bar accepted a value")

print("== death empties the bar ==")
do
	-- The client does not reliably send a final UNIT_HEALTH of zero when
	-- something dies, so the target frame sat reading "10%" over a corpse. Kill
	-- the target *without* firing anything and let the reconcile ticker find it.
	_G.__units.target.hp = 110
	fire("UNIT_HEALTH", "target")
	for i = 1, 20 do tick(0.1) end
	check(UF.target.health:GetValue() > 1, "target bar holds a sliver while alive")

	_G.__units.target.dead = true          -- no event at all
	for i = 1, 20 do tick(0.1) end
	check(UF.target.health:GetValue() < 1,
		"the bar empties anyway (got " .. string.format("%.2f", UF.target.health:GetValue())
		.. ") - events are the fast path, not the only path")
	check(UF.target.hpText:GetText() == "Dead",
		"and it says so rather than showing a stale percentage (got "
		.. tostring(UF.target.hpText:GetText()) .. ")")

	_G.__units.target.dead = false
	_G.__units.target.hp = 640
	for i = 1, 20 do tick(0.1) end
	check(UF.target.hpText:GetText():find("%%") ~= nil,
		"and it comes back when the next thing is targeted")
end

print("== target switching ==")
check(UF.target.unitWatched and _G.__unitWatched[UF.target.click],
	"the secure click button is what the unit watch drives, not the capsule")
check(UF.target.click:GetAttribute("unit") == "target"
	and UF.target.click:GetAttribute("*type1") == "target"
	and UF.target.click:GetAttribute("*type2") == "menu",
	"target capsule carries the secure click attributes")
_G.__units.target.exists = false
fire("PLAYER_TARGET_CHANGED")
check(not UF.target.glass:IsShown(),
	"dropping the target hides the capsule's *glass*")
check(UF.target:IsShown(),
	"but never the core - it parents the secure click-catcher, and hiding a"
	.. " frame with a protected descendant is refused in combat")
check(_G.__unitWatched[UF.target.click],
	"the secure button stays under its unit watch either way")

do  -- the bug this replaced: it only ever showed up mid-fight
	_G.__inCombat = true
	_G.__units.target.exists = true
	fire("PLAYER_TARGET_CHANGED")
	_G.__units.target.exists = false
	fire("PLAYER_TARGET_CHANGED")
	check(not UF.target.glass:IsShown(),
		"losing a target in combat hides the glass without a blocked call")
	_G.__inCombat = false
end
_G.__units.target.exists = true
fire("PLAYER_TARGET_CHANGED")
check(UF.target:IsShown() and UF.target.name:GetText() == "Savannah Prowler",
	"target capsule repopulates after retargeting")

print("== casting ==")
do
	-- Both cast bars float free now. Every edge of a capsule belongs to an aura
	-- tray - buffs above, debuffs below - so a bar tied to one would be shoved
	-- around by whatever auras happened to be up.
	local entry = A.Movers.registry.cast
	check(entry ~= nil, "the player cast bar is a mover of its own")
	check(select(2, UF.cast:GetPoint(1)) == UIParent,
		"anchored to the screen, not to a capsule")
	check(entry.preview ~= nil,
		"and unlock previews it - a bar you only ever see mid-cast is a bar you"
		.. " could never aim at")
	entry.preview(true)
	check(UF.cast:IsShown() and UF.cast.spellName:GetText() == "Cast bar",
		"the preview puts something in it to aim at")
	entry.preview(false)
	check(not UF.cast:IsShown(), "and takes it away again on lock")
end
castState = { name = "Frostbolt", icon = 135846, channel = false,
	startTime = time * 1000, endTime = (time + 2.5) * 1000 }
fire("UNIT_SPELLCAST_START", "player")
check(UF.cast:IsShown(), "cast bar shows on cast start")
check(UF.cast:GetScript("OnUpdate") ~= nil,
	"cast bar drives itself per frame, not off the 10Hz shared ticker")

-- advance it the way the client would: many small frames, via its own OnUpdate
local function castFrames(n, dt)
	for _ = 1, n do
		time = time + dt
		UF.cast:GetScript("OnUpdate")(UF.cast, dt)
	end
end
castFrames(60, 1 / 60)
check(UF.cast.spellName:GetText() == "Frostbolt", "cast bar names the spell")
check(UF.cast.bar:GetValue() > 0, "cast bar progresses")
local midway = UF.cast.bar:GetValue()
castFrames(1, 1 / 60)
check(UF.cast.bar:GetValue() > midway,
	"a single 60fps frame advances the bar (smooth, not stepped)")
castState = nil
fire("UNIT_SPELLCAST_STOP", "player")
check(not UF.cast:IsShown(), "cast bar hides on stop")
check(UF.cast:GetScript("OnUpdate") == nil, "cast bar stops updating when hidden")

print("== target cast bar (LibClassicCasterino) ==")
check(UF.targetCast ~= nil, "target cast bar built")
do
	check(A.Movers.registry.targetcast ~= nil,
		"the target cast bar has its own mover too")
	check(select(2, UF.targetCast:GetPoint(1)) == UIParent,
		"also anchored to the screen")
	check(A.db.profile.anchors.targetcast == nil
		and A.Movers.registry.targetcast.default.y > A.Movers.registry.cast.default.y,
		"and defaults above the player's, which is the order the two things are"
		.. " happening in front of you")

	_G.__ccCasts.target = { name = "Shadow Bolt", icon = 136197, channel = false,
		start = time * 1000, finish = (time + 3) * 1000 }
	_G.__ccFire("UNIT_SPELLCAST_START", "target")
	check(UF.targetCast:IsShown(), "library callback starts the target cast bar")
	check(UF.targetCast.spellName:GetText() == "Shadow Bolt", "target spell named")

	time = time + 1
	UF.targetCast:GetScript("OnUpdate")(UF.targetCast, 1)
	check(UF.targetCast.bar:GetValue() > 0.2, "target cast progresses")

	_G.__ccCasts.target = nil
	_G.__ccFire("UNIT_SPELLCAST_STOP", "target")
	check(not UF.targetCast:IsShown(), "library callback stops it")

	-- a player-unit event must never drive the target's bar and vice versa
	_G.__ccCasts.target = { name = "Fear", icon = 1, channel = false,
		start = time * 1000, finish = (time + 3) * 1000 }
	_G.__ccFire("UNIT_SPELLCAST_START", "target")
	check(not UF.cast:IsShown(), "target cast does not leak onto the player bar")
	_G.__ccCasts.target = nil
	_G.__ccFire("UNIT_SPELLCAST_STOP", "target")
end

print("== idle fader ==")
A.db.profile.fader.delay = 1
A.Fader:Touch()
_G.__units.player.hp = _G.__units.player.hpMax
_G.__units.player.power = _G.__units.player.powerMax   -- mana below max is treated as activity
_G.__units.target.exists = false
fire("PLAYER_TARGET_CHANGED")
for i = 1, 40 do tick(0.1) end
check(UF.player:GetAlpha() < 0.9, "HUD breathes out when idle (alpha "
	.. string.format("%.2f", UF.player:GetAlpha()) .. ")")
cursorX = cursorX + 25
for i = 1, 5 do tick(0.1) end   -- stay inside the 1s idle delay we set above
check(UF.player:GetAlpha() > 0.9, "HUD breathes back in on cursor movement")

print("== combat keeps it awake ==")
_G.__inCombat = true
fire("PLAYER_REGEN_DISABLED")
for i = 1, 30 do tick(0.1) end
check(UF.player:GetAlpha() > 0.95, "combat overrides the idle fade")
_G.__inCombat = false

print("== zen: stage two ==")
do
	local Z = A:GetModule("zen")
	local zcfg = A.db.profile.modules.zen
	check(Z and Z.enabled, "zen module enabled")
	check(Z.frame and Z.frame:GetAlpha() == 0, "the readout starts parked at nothing")
	check(Z.frame:IsShown(), "and parked rather than hidden - it can still be on"
		.. " screen when combat starts, and Hide is refused then")

	zcfg.delay, zcfg.fadeOut, zcfg.fadeIn = 3, 0.1, 0.1
	A.db.profile.fader.delay = 1

	-- Soft signals hold stage one and must not hold stage two. A stale target
	-- and a half-empty health bar say something is worth looking at; neither is
	-- evidence that anybody is still in the chair.
	_G.__units.target.exists = true
	_G.__units.player.hp = math.floor(_G.__units.player.hpMax / 2)
	fire("PLAYER_TARGET_CHANGED")
	for i = 1, 12 do tick(0.1) end
	check(A.Fader.state == "awake", "a target keeps stage one awake past its delay")
	for i = 1, 40 do tick(0.1) end
	check(A.Fader.state == "zen", "and does not keep stage two awake (state "
		.. A.Fader.state .. ")")
	-- Our own frames deliberately stop at the stage-one dim: with dimUI on, the
	-- interface-wide fade is the single authority for the HUD going away, and
	-- driving both would multiply two fades together.
	check(math.abs(UF.player:GetAlpha() - A.db.profile.fader.idleAlpha) < 0.02,
		"our frames rest at the stage-one dim and let the interface fade carry"
		.. " them (alpha " .. string.format("%.2f", UF.player:GetAlpha()) .. ")")
	check(Z.frame:GetAlpha() > 0.9, "and the readout has taken its place")
	check(math.abs(Z.frame.hp:GetValue() - 0.5) < 0.02,
		"the health bar reads half, not none and not all of it")
	check(Z.frame.corner.zone:GetText() == "The Barrens"
		and Z.frame.corner.clock:GetText() == "18:41",
		"the corner pill carries the zone and the time")
	check(UIParent:GetAlpha() < 0.05,
		"and the whole interface has gone with it - the minimap, the chat frame,"
		.. " the XP hairline and anything another addon put on screen (UIParent "
		.. string.format("%.2f", UIParent:GetAlpha()) .. ")")
	check(Z.frame.__parent == nil,
		"which only works because the readout lives outside UIParent")
	check(Minimap:GetAlpha() < 0.05,
		"including the minimap, which is driven by hand: it is a widget the client"
		.. " renders into, and the map surface ignores the alpha it inherits even"
		.. " though our module parents it into a frame under UIParent")
	check(Z.keys and Z.keys:IsKeyboardEnabled(), "the key watcher is listening")

	local k = Z.keys
	k:GetScript("OnKeyDown")(k, "W")
	check(k.__propagate == true,
		"and swallows nothing - propagation is set inside the handler, because the"
		.. " client clears it for every keyboard event")
	tick(0.1)
	check(A.Fader.state == "awake", "a keypress brings the HUD back")
	-- Comfortably longer than the 0.1s fade set above and comfortably shorter
	-- than the 3s zen delay, or this walks straight back into zen and the next
	-- two checks measure the wrong transition.
	for i = 1, 12 do tick(0.1) end
	check(Z.frame:GetAlpha() < 0.05, "and the readout goes away again")
	check(UIParent:GetAlpha() == 1 and Minimap:GetAlpha() == 1,
		"with the interface, and the minimap, put back")
	check(not k:IsKeyboardEnabled(),
		"the key watcher stops listening the moment it is not needed")

	-- going away trips it whatever the timer says
	zcfg.delay = 300
	A.Fader:Touch()
	for i = 1, 5 do tick(0.1) end
	check(A.Fader.state ~= "zen", "nowhere near the timer")
	_G.__units.player.afk = true
	fire("PLAYER_FLAGS_CHANGED", "player")
	check(A.Fader.state == "zen", "going away drops straight into zen anyway")

	_G.__units.player.afk = false
	fire("PLAYER_FLAGS_CHANGED", "player")
	check(A.Fader.state == "awake",
		"and clearing the flag wakes it - which is the one keyboard signal the"
		.. " client hands out for free, since autoClearAFK is on by default")

	fire("PLAYER_FLAGS_CHANGED", "party1")
	check(A.Fader.state == "awake", "somebody else going away is not our business")

	-- combat is a hard block, and leaving zen in combat must not reach for Hide
	_G.__units.player.afk = true
	fire("PLAYER_FLAGS_CHANGED", "player")
	for i = 1, 20 do tick(0.1) end
	check(A.Fader.state == "zen", "back in zen")
	_G.__inCombat = true
	fire("PLAYER_REGEN_DISABLED")
	check(A.Fader.state == "awake", "combat pulls it straight out")
	for i = 1, 40 do tick(0.1) end
	check(UIParent:GetAlpha() == 1,
		"and the whole interface comes back mid-fight without a single Hide")
	check(Z.frame:GetAlpha() < 0.05, "with the readout gone")
	_G.__inCombat = false
	_G.__units.player.afk = false
	fire("PLAYER_REGEN_ENABLED")

	-- the configurable delay stops where the client's own flag takes over
	check(A.Fader.AFK_TIMEOUT == 300,
		"the client's five-minute auto-AFK delay is written down once")
	SlashCmdList["AETHERUI"]("zen delay 900")
	check(zcfg.delay ~= 900, "a delay past that is refused - it could never fire")
	SlashCmdList["AETHERUI"]("zen delay 45")
	check(zcfg.delay == 45, "and a reachable one is taken")
	local slider = A.Options:Build().args.fader.args.zenDelay
	check(slider.max == A.Fader.AFK_TIMEOUT,
		"the slider stops in the same place the state machine does")

	-- and with the module off there is no stage two at all
	SlashCmdList["AETHERUI"]("zen off")
	zcfg.delay = 2
	A.Fader:Touch()
	for i = 1, 40 do tick(0.1) end
	check(A.Fader.state ~= "zen", "module off means no stage two (state "
		.. A.Fader.state .. ")")
	check(not Z.keys:IsKeyboardEnabled(), "and nothing left listening for keys")
	SlashCmdList["AETHERUI"]("zen on")

	-- hiding the interface by hand takes the readout with it, even though the
	-- readout is not underneath it
	SlashCmdList["AETHERUI"]("zen delay 5")
	A.Fader:Touch()
	for i = 1, 70 do tick(0.1) end
	check(A.Fader.state == "zen" and Z.frame:GetAlpha() > 0.5, "in zen again")
	UIParent.__shown = false
	tick(0.1)
	check(Z.frame:GetAlpha() == 0 and UIParent:GetAlpha() == 1
		and Minimap:GetAlpha() == 1,
		"Alt-Z parks it and puts UIParent's alpha back, since nothing else will"
		.. " tell us - we are outside UIParent on purpose")
	UIParent.__shown = true

	-- and a bug in the tick must never leave somebody staring at nothing
	for i = 1, 70 do tick(0.1) end
	check(UIParent:GetAlpha() < 0.05, "back in zen, interface down")
	local realUpdate = Z.UpdateBars
	Z.UpdateBars = function() error("deliberate") end
	A.lastFailure = nil
	tick(0.1)
	Z.UpdateBars = realUpdate
	check(UIParent:GetAlpha() == 1 and Minimap:GetAlpha() == 1,
		"an error inside the tick puts the interface back rather than leaving it"
		.. " invisible until a reload")
	check((A.lastFailure or ""):find("zen"), "and says so")
	A.lastFailure = nil
	A.Fader:Touch()
	A.Fader:Update()
	for i = 1, 20 do tick(0.1) end

	-- put the world back
	zcfg.delay, zcfg.fadeOut, zcfg.fadeIn = 60, 2.5, 0.30
	A.db.profile.fader.delay = 6
	_G.__units.player.hp = _G.__units.player.hpMax
	_G.__units.target.exists = false
	fire("PLAYER_TARGET_CHANGED")
	A.Fader:Touch()
	for i = 1, 30 do tick(0.1) end
end


print("== chat: Blizzard's frames, skinned in place ==")
do
	local C = A:GetModule("chat")
	check(C and C.enabled, "chat module enabled")
	check(C.panel ~= nil, "the glass panel is built")

	-- Hidden, not merely blanked. Blizzard's two fade loops walk
	-- CHAT_FRAME_TEXTURES and skip anything that is not shown, so a region left
	-- shown with a nil texture stays in both loops and keeps having its alpha
	-- animated back. Hiding is what gets it out of them for good.
	local stillShown = {}
	for _, suffix in ipairs(CHAT_FRAME_TEXTURES) do
		local r = _G["ChatFrame1" .. suffix]
		if r and r:IsShown() then stillShown[#stillShown + 1] = suffix end
	end
	check(#stillShown == 0,
		"every backdrop region is hidden rather than blanked"
		.. (#stillShown > 0 and ("  -- still shown: " .. table.concat(stillShown, ", ")) or ""))

	local tabArt = {}
	for _, set in ipairs({ "", "Selected", "Highlight" }) do
		for _, piece in ipairs({ "Left", "Middle", "Right" }) do
			local r = _G["ChatFrame1Tab" .. set .. piece]
			if r and r:IsShown() then tabArt[#tabArt + 1] = set .. piece end
		end
	end
	check(#tabArt == 0, "and so is every piece of tab artwork"
		.. (#tabArt > 0 and ("  -- " .. table.concat(tabArt, ", ")) or ""))

	local tab1, tab2 = _G.ChatFrame1Tab, _G.ChatFrame2Tab
	check(tab1._pill and tab2._pill, "each tab gets a pill of its own")
	check(tab1._pill:GetAlpha() > 0.9 and tab2._pill:GetAlpha() == 0,
		"and only the selected one is filled in - that inversion is the signal")
	check(not tab1._pill._edge[1]:IsShown(),
		"with no extra bright rim around the selected tab")
	check(_G.ChatFrame1TabText._aetherStyle == "chatTab", "tab type is ours")

	-- The edit box sits *inside* the panel's bottom edge, not hanging off
	-- underneath it. A positive y offset from BOTTOMLEFT is the whole test:
	-- Blizzard's own anchor puts it below the frame at a negative one.
	local eb = _G.ChatFrame1EditBox
	check(eb._pill ~= nil, "the edit box gets its own capsule")
	local point, rel, relPoint, _, y = eb._pill:GetPoint(1)
	check(point == "BOTTOMLEFT" and rel == C.panel and relPoint == "BOTTOMLEFT" and y > 0,
		"anchored inside the panel rather than below it (got " .. tostring(point)
		.. " -> " .. tostring(relPoint) .. " at y=" .. tostring(y) .. ")")
	local ebShown = {}
	for _, suffix in ipairs({ "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" }) do
		local r = _G["ChatFrame1EditBox" .. suffix]
		if r and r:IsShown() then ebShown[#ebShown + 1] = suffix end
	end
	check(#ebShown == 0, "with Blizzard's border gone"
		.. (#ebShown > 0 and ("  -- " .. table.concat(ebShown, ", ")) or ""))
	-- The capsule and the code in it are sized from the typing font, not from a
	-- fixed number and not from the tab role's own 11 - which put a label beside
	-- the text that was bigger than the text.
	local typeSize = C:FontSize(_G.ChatFrame1)
	check(eb._tagText.__font and eb._tagText.__font[2] == typeSize,
		"the channel code reads at the size you type at (got "
		.. tostring(eb._tagText.__font and eb._tagText.__font[2])
		.. ", want " .. typeSize .. ")")
	-- A panel's corner is fixed at creation and does not track its frame. Testing
	-- it at the size it was built at proves nothing, because those agree by
	-- construction - the bug only appears once the height changes under it, which
	-- is exactly what happens when the chat font size does.
	local wasDelta = A.db.profile.modules.chat.fontDelta
	A.db.profile.modules.chat.fontDelta = wasDelta + 6
	A:Reconfigure()
	check(eb._tag._corner == math.floor(eb._tag:GetHeight() / 2),
		"the capsule's corner follows its height, so a font change gives a bigger"
		.. " capsule rather than a different shape (corner "
		.. tostring(eb._tag._corner) .. ", height "
		.. tostring(eb._tag:GetHeight()) .. ")")
	A.db.profile.modules.chat.fontDelta = wasDelta
	A:Reconfigure()
	typeSize = C:FontSize(_G.ChatFrame1)

	check(eb._tag:GetHeight() < eb._pill:GetHeight(),
		"and its capsule sits inside the composer rather than filling it ("
		.. tostring(eb._tag:GetHeight()) .. " vs "
		.. tostring(eb._pill:GetHeight()) .. ")")

	check(eb._tag ~= nil and eb._tagText and eb._tagText:GetText() ~= "",
		"the channel is a short code in a capsule of its own (got '"
		.. tostring(eb._tagText and eb._tagText:GetText()) .. "')")
	check(eb._pill._kind == "panel", "the edit box surface is a panel")
	check(eb._pill._edgeColor == A.Palette.c.glassEdge,
		"and that hairline uses the same colour as the chat panel rim")
	check(A.Movers.registry.chat ~= nil,
		"chat registers a mover, so /aether unlock moves it like everything else")

	-- the grey "CE_TEXT": Blizzard puts its own header back on focus and on every
	-- channel change, so blanking it once was never going to hold
	eb:UpdateHeader()
	check(eb.header:GetText() == "" and eb.header:GetAlpha() == 0,
		"Blizzard's header is re-silenced after it rewrites it (got '"
		.. tostring(eb.header:GetText()) .. "')")
	check(eb.prompt:GetText() == "",
		"and so is everything else on the box - every FontString, not a list of"
		.. " the three we happened to know about")
	-- the "VOICE_TEXT" case: an unresolved localised global, on a child frame
	-- rather than on the box itself, which is why the first sweep never saw it
	local ghost = CreateFrame("Frame", nil, eb)
	local gfs = ghost:CreateFontString("AetherTestGhostFS")
	gfs:SetText("VOICE_TEXT")
	eb:UpdateHeader()
	check(gfs:GetText() == "",
		"an unresolved global is swept off a child frame too (got '"
		.. tostring(gfs:GetText()) .. "')")
	local keep = ghost:CreateFontString()
	keep:SetText("Turdinand-Firemaw")
	eb:UpdateHeader()
	check(keep:GetText() == "Turdinand-Firemaw",
		"and real text next to it is left alone - the sweep matches the shape of a"
		.. " missing global, not everything it can reach")
	check(pcall(function() SlashCmdList["AETHERUI"]("chat") end),
		"and the chat diagnostic runs")

	-- the edit box's own text renderer is an *anonymous* FontString sitting
	-- directly in the EditBox element (ChatFrameEditBox.xml:99). Blanking every
	-- FontString on the box made typing invisible.
	local typed = eb:CreateFontString()
	typed:SetText("hello this is what I am typing")
	eb.header:SetText("VOICE_TEXT")
	eb.header:SetAlpha(1)
	for i = 1, 5 do tick(0.1) end
	check(typed:GetText() == "hello this is what I am typing" and typed:GetAlpha() == 1,
		"the anonymous FontString that draws what you type is left alone")
	check(eb.header:GetText() == "",
		"while the watchdog catches a header that came back by some route we are"
		.. " not hooked onto (got '" .. tostring(eb.header:GetText()) .. "')")

	-- VOICE_TEXT: the client sets it as a *sticky* type and ResetChatType has no
	-- case for it, so nothing ever puts it back. That is why the header was
	-- asking for CHAT_VOICE_TEXT_SEND, a string this client does not have.
	eb:SetAttribute("chatType", "VOICE_TEXT")
	eb:UpdateHeader()
	check(eb:GetAttribute("chatType") == "SAY",
		"a stranded VOICE_TEXT chat type is put back to SAY (got "
		.. tostring(eb:GetAttribute("chatType")) .. ")")
	check(eb:GetAttribute("stickyType") == "SAY",
		"and so is the sticky type, or it would come straight back on the next"
		.. " message")

	_G.VoiceTranscription_GetChatTypeAndInfo = function() end
	eb:SetAttribute("chatType", "VOICE_TEXT")
	eb:UpdateHeader()
	check(eb:GetAttribute("chatType") == "VOICE_TEXT",
		"but a client that really has voice transcription is left alone")
	_G.VoiceTranscription_GetChatTypeAndInfo = nil
	eb:SetAttribute("chatType", "SAY")

	-- A slash command sets the attribute after the text-change handler has run,
	-- so without the hook on SetAttribute the badge keeps saying SAY.
	eb:SetAttribute("chatType", "SAY")
	eb:SetAttribute("chatType", "CHANNEL")
	check(eb._tagText:GetText() == "GEN",
		"switching to /1 updates the badge immediately instead of leaving SAY"
		.. " underneath it (got '" .. tostring(eb._tagText:GetText()) .. "')")
	eb:SetAttribute("chatType", "SAY")

	-- The capsule is ours and parented to UIParent, so it does not inherit
	-- Blizzard's "only the active box is shown". With one window that is
	-- invisible; this client has ten, and ten capsules were being drawn in the
	-- same place with ten channel labels across each other.
	local composers = {}
	C.EachFrame(function(cf)
		local box = cf.editBox or _G[(cf:GetName() or "") .. "EditBox"]
		if box and box._pill and box._pill:IsShown() then
			composers[#composers + 1] = cf:GetName()
		end
	end)
	check(#composers == 1, "exactly one composer is on screen however many chat"
		.. " windows there are (got " .. #composers .. ": "
		.. table.concat(composers, ", ") .. ")")

	-- The label is our own FontString, so an unresolved chat type printed
	-- straight into the composer - which is why every sweep for a stray
	-- Blizzard string came back clean while the text stayed on screen.
	eb:SetAttribute("chatType", "VOICE_TEXT")
	C:UpdateEditBox(eb)
	check(eb._tagText:GetText() == "SAY",
		"an unrecognised chat type never prints its own key as the label (got '"
		.. tostring(eb._tagText:GetText()) .. "')")
	eb:SetAttribute("chatType", "SAY")
	C:UpdateEditBox(eb)

	check(eb.__insetL == 0,
		"with the text inset back to zero, so what you type is not pushed right by"
		.. " the width of a header that is no longer there")
	check(eb.__font and eb.__font[2] == C:FontSize(_G.ChatFrame1),
		"the edit box types at the same size the messages are read at (got "
		.. tostring(eb.__font and eb.__font[2]) .. ", want "
		.. tostring(C:FontSize(_G.ChatFrame1)) .. ")")
	check(C:FontSize(_G.ChatFrame1) == 14 + A.db.profile.modules.chat.fontDelta,
		"which is Blizzard's own size plus our offset, not a number of our own")
	local exLeft = select(4, eb:GetPoint(1))
	check(exLeft and exLeft < 20,
		"and the text starts near the left edge (inset " .. tostring(exLeft) .. ")")

	-- Parked, not hidden: Blizzard re-shows the button frame from several places
	-- and moving it off screen is a fight nobody has to win.
	local bf = _G.ChatFrame1ButtonFrame
	local _, _, _, bx = bf:GetPoint(1)
	check(bx and bx < -1000, "the buttons are parked off screen rather than hidden")
	check(bf:IsShown(), "which means nothing has to keep hiding them")
	check(_G.ChatFrame1ResizeButton:IsShown(),
		"but the resize corner stays - it is what makes the frame resizable, and"
		.. " Blizzard's own version is what saves the new size")
	check(tab1:GetAlpha() == 1 and tab2:GetAlpha() == 1,
		"every tab is on screen, not just the hovered one")
	tab2:SetAlpha(0.4)
	check(tab2:GetAlpha() == 1,
		"and stays there - Blizzard fades docked tabs out by default, so the"
		.. " alpha is owned rather than merely set once")

	-- font size stays Blizzard's, face is ours
	check(_G.ChatFrame1.__font
		and _G.ChatFrame1.__font[2] == C:FontSize(_G.ChatFrame1),
		"the size is read back from Blizzard's own setting, not remembered")
	check((_G.ChatFrame1.__font[1] or ""):find("Outfit"), "the face is ours")

	print("== chat: it breathes with everything else ==")
	check(A.Fader.watched[C.panel] ~= nil and A.Fader.watched[_G.ChatFrame1] ~= nil,
		"the panel and the message frame are both registered with the fader")
	A.db.profile.fader.delay = 1
	A.Fader:Touch()
	_G.__units.player.hp = _G.__units.player.hpMax
	_G.__units.player.power = _G.__units.player.powerMax
	_G.__units.target.exists = false
	fire("PLAYER_TARGET_CHANGED")
	for i = 1, 30 do tick(0.1) end
	check(_G.ChatFrame1:GetAlpha() < 0.9,
		"so chat dims when the HUD does (alpha "
		.. string.format("%.2f", _G.ChatFrame1:GetAlpha()) .. ")")
	cursorX = cursorX + 30
	for i = 1, 5 do tick(0.1) end
	check(_G.ChatFrame1:GetAlpha() > 0.9, "and comes back with it")
	A.db.profile.fader.delay = 6

	-- Blizzard calls these to put its own look back; we are hooked onto them, so
	-- running the whole skin twice has to be safe.
	A.lastFailure = nil
	C:Reskin()
	C:Reskin()
	check(A.lastFailure == nil and not _G.ChatFrame1Background:IsShown(),
		"re-skinning is idempotent, which it has to be - every hook calls it")
end

print("== chat: the message lines ==")
do
	local C = A:GetModule("chat")
	local f = _G.ChatFrame1

	-- A say from a mage with a realm suffix: the case that exercises every part
	-- of the sender-name filter at once.
	local line = DeliverChatMessage(f, "CHAT_MSG_SAY",
		"where is everyone", "Palabras-Firemaw", "", "", "", "", 0, 0, "", 0,
		77, "Player-4700-0000A1")

	-- The one that matters. The link target is built from the raw sender name,
	-- which the filter never sees written to - so whispers, ignore and the
	-- right-click menu survive whatever we did to the display text.
	local target = line:match("|Hplayer:([^:|]+)")
	check(target == "Palabras-Firemaw",
		"the player link still points at the real sender (got "
		.. tostring(target) .. ")")
	check(select(2, line:gsub("|H", "")) == 1,
		"and there is exactly one hyperlink in the line - a nested |H is the one"
		.. " thing that would break it")
	local display = line:match("|Hplayer:[^|]*|h(.-)|h")
	check(display and display:find("Palabras", 1, true) ~= nil,
		"the name is inside the link, not beside it (got '"
		.. tostring(display) .. "')")

	local mage = RAID_CLASS_COLORS.MAGE
	local mageHex = A.Palette:Hex({ mage.r, mage.g, mage.b })
	check(line:find("|cff" .. mageHex .. "Palabras|r", 1, true) ~= nil,
		"the name carries the class colour and stops at the hyphen")
	-- The display text, not the whole line: the realm is meant to survive in the
	-- link target and only that, so testing the line as a whole would pass for
	-- the wrong reason or fail for one.
	check(display and not display:find("-Firemaw", 1, true),
		"and the realm is gone from what you read (got '" .. tostring(display) .. "')")
	check(line:match("|Hplayer:([^:|]+)") == "Palabras-Firemaw",
		"but not from the link, so a cross-realm name you cannot see is still"
		.. " one you can whisper and right-click")

	-- The realm is only ever split off, never rebuilt, so keeping it is one
	-- concatenation and the setting is real rather than decorative.
	A.db.profile.modules.chat.hideRealm = false
	local kept = DeliverChatMessage(f, "CHAT_MSG_SAY",
		"still here", "Palabras-Firemaw", "", "", "", "", 0, 0, "", 0, 85,
		"Player-4700-0000A1")
	check(kept:find("|cff" .. A.Palette:Hex(A.Palette.c.textFaint) .. "-Firemaw", 1, true) ~= nil,
		"turning it off dims the realm rather than dropping it")
	A.db.profile.modules.chat.hideRealm = true

	check(line:find("\226\128\148", 1, true) ~= nil and not line:find("says:", 1, true),
		"\"says:\" is an em dash (got '" .. tostring(line) .. "')")
	check(line:find("|TInterface", 1, true) ~= nil, "with a badge in front of it")

	-- Badges are one atlas, addressed by row. Wrong row is a silent bug - it
	-- draws *a* pill, just the wrong word - so the row is read back and checked.
	local top = line:match("|T[^|]-:%d+:%d+:%-?%d+:%-?%d+:%d+:%d+:%d+:%d+:(%d+):")
	check(tonumber(top) == A.Media.badges.index.SAY * A.Media.badges.row,
		"pointing at the SAY row of the atlas (texel " .. tostring(top)
		.. ", want " .. tostring(A.Media.badges.index.SAY * A.Media.badges.row) .. ")")

	check(C:MarkupSupport() == true,
		"the client takes the coloured form of the texture escape")

	-- A channel line: Blizzard's bracket is prepended after formatting, so this
	-- is the one piece no filter can reach.
	local ch = DeliverChatMessage(f, "CHAT_MSG_CHANNEL",
		"LFM SM lib", "Turdinand", "", "1. General - Durotar", "", "", 0, 1,
		"General", 0, 78, "Player-4700-0000B2")
	check(not ch:find("|Hchannel:", 1, true),
		"the channel bracket is off the front of the line (got '" .. ch .. "')")
	check(ch:find("|Hplayer:Turdinand", 1, true) ~= nil,
		"while the player link in the same line is untouched")
	local chTop = ch:match("|T[^|]-:%d+:%d+:%-?%d+:%-?%d+:%d+:%d+:%d+:%d+:(%d+):")
	check(tonumber(chTop) == A.Media.badges.index.GENERAL * A.Media.badges.row,
		"and General got its own pill rather than the generic one")

	-- The badge takes its colour from Blizzard's own chat settings rather than
	-- inventing a second scheme beside them.
	local ci = ChatTypeInfo.CHANNEL1
	check(ch:find(string.format(":%d:%d:%d|t",
			math.floor(ci.r * 255 + 0.5), math.floor(ci.g * 255 + 0.5),
			math.floor(ci.b * 255 + 0.5)), 1, true) ~= nil,
		"tinted with whatever colour the player's own chat settings give that"
		.. " channel")

	-- A channel with no pill baked for it falls back to its own name as text,
	-- because a word baked into a texture cannot be invented at runtime.
	local odd = DeliverChatMessage(f, "CHAT_MSG_CHANNEL",
		"anyone about", "Turdinand", "", "5. Goldshire RP", "", "", 0, 5,
		"Goldshire RP", 0, 79, "Player-4700-0000B2")
	check(not odd:find("|TInterface", 1, true)
		and odd:find("GOLDSHIRE RP", 1, true) ~= nil,
		"an unknown channel gets its name as text instead of the wrong badge")

	-- WHISPER_INFORM: the "To" is in the format string and the badge already
	-- says it, so the lead-in comes off rather than printing twice.
	local to = DeliverChatMessage(f, "CHAT_MSG_WHISPER_INFORM",
		"on my way", "Turdinand", "", "", "", "", 0, 0, "", 0, 80,
		"Player-4700-0000B2")
	check(not to:find("To ", 1, true),
		"\"To\" is left to the badge rather than printed next to it (got '"
		.. to .. "')")

	-- System lines are identified by the chat type id AddMessage is handed,
	-- not by a filter - so nothing has to touch an event argument to dim one.
	local sys = DeliverChatMessage(f, "CHAT_MSG_SYSTEM",
		"Turdinand has come online.", "", "", "", "", "", 0, 0, "", 0, 81)
	check(sys:find("|cff" .. A.Palette:Hex(A.Palette.c.textDim), 1, true) == 1,
		"system lines are dimmed (got '" .. sys .. "')")

	-- The regression that matters most on this module. `arg1` on a channel
	-- notice is a token the handler looks up as CHAT_<token>_NOTICE - colouring
	-- it means a nil global string and a red error on every single login, since
	-- joining General fires YOU_CHANGED. DeliverChatMessage fails outright if
	-- the token comes through changed, so this is a real assertion.
	A.lastFailure = nil
	local notice = DeliverChatMessage(f, "CHAT_MSG_CHANNEL_NOTICE",
		"YOU_CHANGED", "", "", "1. General - Durotar", "", "", 0, 1, "General", 0, 83)
	check(A.lastFailure == nil and notice
		and notice:find("Changed Channel", 1, true) ~= nil,
		"a channel notice's token survives intact - no filter here rewrites an"
		.. " event argument (got '" .. tostring(notice) .. "')")
	-- And it is *not* dimmed, which is the honest outcome rather than the one
	-- that would look right in a list: the handler has already swapped `info`
	-- for the channel's, so a notice never carries CHANNEL_NOTICE's id. Listing
	-- the notice types in DIM_TYPES would report "3 of 3" and do nothing.
	check(f.__lastID == ChatTypeInfo.CHANNEL1.id,
		"a notice arrives tagged with the channel's id, not the notice type's -"
		.. " which is why DIM_TYPES is SYSTEM alone (got "
		.. tostring(f.__lastID) .. ")")

	-- The strip has to be conditional on the badge that replaces it actually
	-- going on. Every path where the filter declines used to delete
	-- "[1. General]" and put nothing in its place.
	A.db.profile.modules.chat.badges = false
	A:Reconfigure()
	local noBadge = DeliverChatMessage(f, "CHAT_MSG_CHANNEL",
		"still here", "Turdinand", "", "2. Trade - City", "", "", 0, 2, "Trade",
		0, 84, "Player-4700-0000B2")
	check(noBadge:find("|Hchannel:", 1, true) ~= nil,
		"with badges off the channel bracket stays, because nothing replaced it"
		.. " (got '" .. noBadge .. "')")
	A.db.profile.modules.chat.badges = true
	A:Reconfigure()

	-- Every early exit in the filter returns nil, which means "leave it alone".
	A.db.profile.modules.chat.styleLines = false
	A:Reconfigure()
	local plain = DeliverChatMessage(f, "CHAT_MSG_SAY",
		"back to normal", "Palabras-Firemaw", "", "", "", "", 0, 0, "", 0, 82,
		"Player-4700-0000A1")
	check(plain:find("says:", 1, true) ~= nil and not plain:find("|TInterface", 1, true),
		"turning the line work off gives Blizzard's own line back, furniture and"
		.. " all (got '" .. plain .. "')")
	A.db.profile.modules.chat.styleLines = true
	A:Reconfigure()

	-- The reshaping must never touch a format string with two arguments in it.
	check(_G.CHAT_CHANNEL_NOTICE_GET == "[%d. %s] ",
		"a two-argument format is left exactly as Blizzard wrote it")

	-- A client without the coloured escape draws the long form as literal text,
	-- which would put forty characters of file path in every line.
	C._markup = nil
	MOCK_TEXTURE_VERTEX_COLOR = false
	check(C:MarkupSupport() == false,
		"a client that cannot tint an inline texture is detected rather than"
		.. " assumed")
	local untinted = C:Badge("SAY", "ff0000")
	check(untinted and not untinted:find(":255:0:0", 1, true)
		and select(2, untinted:gsub(":", "")) == 10,
		"and falls back to the eleven-argument form (got '"
		.. tostring(untinted) .. "')")
	MOCK_TEXTURE_VERTEX_COLOR = true
	C._markup = nil
	C:MarkupSupport()

	-- The dispatcher splits a command into cmd/arg/rest and hands over two.
	-- A handler that takes one gets the switch and never the value, so every
	-- branch falls through to "here is the current setting" and nothing is ever
	-- set - which is silent, because printing the old value looks like an answer.
	SlashCmdList["AETHERUI"]("chat badges off")
	check(A.db.profile.modules.chat.badges == false,
		"/aether chat badges off actually turns them off")
	SlashCmdList["AETHERUI"]("chat badges on")
	check(A.db.profile.modules.chat.badges == true, "and on again")

	-- Blizzard brackets the display text, so the badge lands inside `[...]` and
	-- the opening bracket reads as part of the pill. It has to come off after
	-- the fact, because it is added after every filter has run.
	local brackets = DeliverChatMessage(f, "CHAT_MSG_SAY",
		"no brackets please", "Palabras-Firemaw", "", "", "", "", 0, 0, "", 0, 86,
		"Player-4700-0000A1")
	check(not brackets:find("|h[", 1, true) and not brackets:find("]|h", 1, true),
		"the brackets Blizzard puts round the name are gone (got '"
		.. brackets .. "')")
	check(brackets:match("|Hplayer:([^:|]+)") == "Palabras-Firemaw"
		and select(2, brackets:gsub("|H", "")) == 1,
		"and the link itself is untouched - one hyperlink, still pointing at the"
		.. " real sender")

	check(pcall(function() SlashCmdList["AETHERUI"]("chat") end),
		"the line diagnostic runs")
end

print("== chat: the whispers tab ==")
do
	local C = A:GetModule("chat")
	local general = _G.ChatFrame1

	check(general.__groups.WHISPER == true,
		"whispers start in the general window, which is Blizzard's default")
	check(C:WhisperFrame() == nil and A.db.profile.modules.chat.whisperTab == false,
		"and there is no tab until it is asked for - this one writes into"
		.. " Blizzard's saved variables and outlives the addon")

	check(C:SetWhisperTab(true), "/aether chat whispers on creates it")
	local wf = C:WhisperFrame()
	check(wf ~= nil, "and it can be found again by name")
	check(wf.__groups.WHISPER and wf.__groups.BN_WHISPER,
		"both whisper groups moved onto it")
	check(not general.__groups.WHISPER and not general.__groups.BN_WHISPER,
		"and off the general window, or they would land in both")
	check(not wf.__groups.SAY and not wf.__groups.CHANNEL,
		"noDefaultChannels: without it this is a second general window rather"
		.. " than a whispers tab")
	check(wf._aetherAddMessage ~= nil,
		"the new window is skinned like the rest - AddMessage wrapped and all")

	-- Message groups are frame *methods* on Classic Era. The ChatFrame_ globals
	-- are aliases behind the loadDeprecationFallbacks cvar, so this harness does
	-- not define them at all: if the module ever reaches for the global first,
	-- this is what catches it.
	check(_G.ChatFrame_AddMessageGroup == nil,
		"and none of that went through a ChatFrame_ global, because there is not"
		.. " one here to go through")

	check(C:SetWhisperTab(false), "turning it off puts them back")
	check(general.__groups.WHISPER and not wf.__groups.WHISPER,
		"whispers return to the general window")
	check(C:WhisperFrame() ~= nil,
		"and the empty window is left standing rather than closed out from under"
		.. " the player")
end

print("== a module toggle in the panel actually toggles the module ==")
do
	-- It used to write the flag and nothing else, so switching a module off in
	-- the panel left it running and switching it on left it dead until a reload.
	-- Recognised by path shape in Options.Set, so every page gets it.
	local tree = A.Options:Build()
	local opt = tree.args.unitframes.args.enabled
	local info = { arg = opt.arg, type = "toggle" }

	opt.set(info, false)
	check(not A:GetModule("unitframes").enabled, "off in the panel disables it")
	opt.set(info, true)
	check(A:GetModule("unitframes").enabled, "and on enables it")
	check(A.Movers.registry.player and A.Movers.registry.target,
		"and it comes back with its movers - the come-back path used to skip them,"
		.. " leaving the capsules unmovable for the rest of the session")

	local zopt = tree.args.fader.args.zenEnabled
	local zinfo = { arg = zopt.arg, type = "toggle" }
	zopt.set(zinfo, false)
	check(not A:GetModule("zen").enabled, "the same for zen, from the fader page")
	zopt.set(zinfo, true)
	check(A:GetModule("zen").enabled, "and back")

	-- nested sub-toggles must not be mistaken for module switches
	local sub = tree.args.auras.args.buffs.args.enabled
	check(#sub.arg.path == 4,
		"a nested enabled toggle has a longer path and is left alone")
end

print("== health bar colour ==")
do
	local UFm = A:GetModule("unitframes")
	A.db.profile.classColorHealth = true
	SlashCmdList["AETHERUI"]("health class")
	local classPair = A.Palette:HealthColor("player")
	SlashCmdList["AETHERUI"]("health deck")
	local deckPair = A.Palette:HealthColor("player")
	check(A.db.profile.classColorHealth == false, "deck mode recorded")
	check(deckPair == A.Palette.c.health, "deck mode falls back to the concept's green")
	check(classPair ~= deckPair, "class mode returns a different pair")
	SlashCmdList["AETHERUI"]("health class")
	check(A.db.profile.classColorHealth == true, "switched back to class colours")
end

print("== skins ==")
A.lastFailure = nil
SlashCmdList["AETHERUI"]("skin daylight")
check(A.Palette.current == "daylight", "skin switched to daylight")
SlashCmdList["AETHERUI"]("skin midnight")
check(A.Palette.current == "midnight", "skin switched back")
check(A.lastFailure == nil,
	"and no module errored on the way through: " .. tostring(A.lastFailure))

print("== every toggle survives a restyle and a reconfigure ==")
do
	-- The bug this catches: flipping one toggle raised an error inside the action
	-- bars, and because Restyle pcalls each module it only ever showed up as a
	-- line in chat. A pcall that just prints is a test that never fails.
	--
	-- So: walk every toggle in the options tree, flip it both ways, and demand
	-- that nothing reports a failure. 60-odd of them, and it takes no time.
	local tree = A.Options:Build()
	local flipped, failures = 0, {}

	local function exercise(node, trail)
		for key, opt in pairs(node.args or {}) do
			local where = trail .. "." .. key
			if opt.type == "group" then
				exercise(opt, where)
			elseif opt.type == "toggle" and opt.arg and opt.arg.path then
				local info = { arg = opt.arg, type = "toggle" }
				local before = opt.get(info)
				for _, v in ipairs({ not before, before }) do
					A.lastFailure = nil
					local ok, err = pcall(opt.set, info, v)
					if not ok then
						failures[#failures + 1] = where .. " threw: " .. tostring(err)
					elseif A.lastFailure then
						failures[#failures + 1] = where .. " -> " .. A.lastFailure
					end
				end
				flipped = flipped + 1
			end
		end
	end
	exercise(tree, "root")

	check(flipped > 40, "flipped " .. flipped .. " toggles both ways")
	check(#failures == 0, "none of them errored"
		.. (#failures > 0 and ("  -- " .. failures[1]
			.. (#failures > 1 and ("  (+" .. (#failures - 1) .. " more)") or "")) or ""))

	-- put the world back
	A.lastFailure = nil
	A:Restyle()
	A:Reconfigure()
	check(A.lastFailure == nil, "and the suite is left in a working state")
end

print("== movers: scale ==")
do
	-- Our frames run at profile.scale (0.71), and every getter here reports in a
	-- different coordinate space. Mixing them is what made a dragged frame leap
	-- to a corner: GetRight() is frame-space, UIParent:GetWidth() is UIParent
	-- space, and SetPoint's offset is read back in frame space again.
	UIParent:SetSize(1000, 600)
	UIParent.__scale = 1

	SlashCmdList["AETHERUI"]("unlock")
	local entry = A.Movers.registry.quests
	check(entry ~= nil, "the quest tracker registers a mover")

	local f = entry.frame
	f.__scale = 0.5
	-- a frame whose right and top edges sit exactly on UIParent's
	f:SetGeom({ cx = 1800, cy = 1100, left = 1200, right = 2000, bottom = 400, top = 1200 })

	local h = entry.handle
	h:GetScript("OnDragStart")(h)
	h:GetScript("OnDragStop")(h)

	local point, _, relPoint, x, y = f:GetPoint(1)
	check(point == "TOPRIGHT" and relPoint == "TOPRIGHT",
		"dropped in the top-right third, it anchors by TOPRIGHT (got "
		.. tostring(point) .. ")")
	check(math.abs(x) < 0.01 and math.abs(y) < 0.01,
		"a frame flush with the screen corner gets a zero offset, not one inflated"
		.. " by its own scale (got " .. string.format("%.1f, %.1f", x, y) .. ")")

	-- growsDown pins by the top edge wherever it lands vertically
	f:SetGeom({ cx = 1800, cy = 600, left = 1200, right = 2000, bottom = 200, top = 1000 })
	h:GetScript("OnDragStart")(h)
	h:GetScript("OnDragStop")(h)
	check(select(1, f:GetPoint(1)) == "TOPRIGHT",
		"a frame that grows downward stays pinned by its top edge even when it is"
		.. " dropped in the middle band (got " .. tostring(select(1, f:GetPoint(1))) .. ")")

	f.__geom = nil
	f.__scale = 1
	SlashCmdList["AETHERUI"]("lock")
end

print("== movers ==")
SlashCmdList["AETHERUI"]("unlock")
check(A.Movers.unlocked, "movers unlocked")
local entry = A.Movers.registry.player
check(entry and entry.handle and entry.handle:IsShown(), "player mover handle visible")
local h = entry.handle
h:GetScript("OnDragStart")(h)
h:GetScript("OnDragStop")(h)
check(A.db.profile.anchors.player ~= nil, "drag persisted a position")
SlashCmdList["AETHERUI"]("lock")
check(not A.Movers.unlocked, "movers locked")
SlashCmdList["AETHERUI"]("reset")
check(next(A.db.profile.anchors) == nil, "reset cleared saved anchors")

print("== other commands ==")
for _, cmd in ipairs({ "", "status", "diag", "hide", "scale 1.2", "shadow 14", "noise 0.5",
	"fade off", "fade on", "fade delay 4", "fade idle 0.2",
	"bar", "bar list", "bar 1 scale 0.8", "bar size 44", "bar 1 rows 2", "bar size 999",
	"bar font 3", "bar 1", "bar nope", "bar 1 bogus", "bar stance buttons 4",
	"bar stance page 2", "bar 1 backdrop", "bar 1 backdrop",
	"module unitframes off", "module unitframes on", "bogus" }) do
	local ok, err = pcall(SlashCmdList["AETHERUI"], cmd)
	if not ok then fail("/aether " .. cmd .. ": " .. tostring(err)) end
end
check(A:GetModule("unitframes").enabled, "module toggled back on cleanly")
check(UF.player == A:GetModule("unitframes").player and #UF.frames == 2,
	"toggling the module reuses its frames instead of leaking a second set")
check(UF.player:IsShown() and UF.player.name:GetText() == "Palabras",
	"reused frames repopulate after a toggle")

print("== ui scale change ==")
fire("UI_SCALE_CHANGED")
fire("DISPLAY_SIZE_CHANGED")
check(A.pixel > 0 and A.pixel < 4, "pixel scale sane after a resolution change ("
	.. string.format("%.3f", A.pixel) .. ")")

-- ---------------------------------------------------------------------------
print("== action bars ==")

local AB = A:GetModule("actionbars")
check(AB and AB.enabled, "actionbars module enabled"
	.. (AB and AB.lastError and ("  -- " .. AB.lastError) or ""))
--- Bars are never destroyed - WoW has no way to - so a disabled one stays in the
--- list, built and hidden. Count what is actually on, not what exists.
local function EnabledBars()
	local n, ids = 0, {}
	for _, b in ipairs(AB.bars) do
		if b.cfg.enabled ~= false then n = n + 1; ids[#ids + 1] = b.id end
	end
	table.sort(ids)
	return n, table.concat(ids, ", ")
end

do
	local n, ids = EnabledBars()
	check(n == 4, "bar 1 plus stance, pet and extra are on; 2-6 off (" .. ids .. ")")
end

local bar = AB.bars[1]
check(#bar.buttons == 12, "12 buttons in the dock")
check(bar.buttons[1]:GetAttribute("type") == "action", "buttons are secure action buttons")
check(bar.buttons[1]:GetAttribute("action") == 1
	and bar.buttons[12]:GetAttribute("action") == 12,
	"page 1 maps button i to action i")

-- The paging snippets are restricted Lua we cannot execute here, but a typo in
-- one is silent and only shows up as "my druid's bar stopped working". Parsing
-- them is cheap insurance.
for _, snippet in ipairs({
	bar.header:GetAttribute("_onstate-page"),
	bar.buttons[1]:GetAttribute("_childupdate-actionpage"),
}) do
	check(type(snippet) == "string" and loadstring(snippet) ~= nil,
		"secure snippet is syntactically valid Lua")
end
check(_G.__stateDrivers.page == nil,
	"no page driver: bars name their own source once and never change it")

check(AB.hideReport ~= nil, "HideBlizzard produced a per-frame report")
check(AB.hideReport.MainMenuBar == "hidden", "MainMenuBar reported hidden")
check(AB.hideReport.MultiBarBottomLeft == "hidden", "multibars reported hidden")
check(AB.hideReport.CharacterMicroButton == "hidden",
	"micro buttons hidden from Blizzard's own MICRO_BUTTONS list")
check(AB.hideReport.MainActionBar == "hidden",
	"MainActionBar (the real 1.15 container) hidden")
check(AB.hideReport.MicroMenu == "hidden", "MicroMenu hidden")
check(AB.hideReport.CatalogShopFrame == nil,
	"forbidden frames are skipped, not touched")
check(AB.hideReport.PetActionBar ~= nil,
	"Blizzard's pet bar goes now that we have one of our own")
check(AB.hideReport.MainMenuBarVehicleLeaveButton == nil,
	"the taxi early-landing button is NOT banished - it is the only way off a"
	.. " flight path early, and TaxiRequestEarlyLanding cannot be recreated")
check(AB.hideReport.PossessBarFrame ~= nil or AB.hideReport.PossessBarFrame == nil,
	"possess keeps Blizzard's bar - rare, temporary, and no vehicle UI here")
check(_G.MainMenuBar:GetParent() ~= UIParent, "banished frames are reparented off UIParent")
SlashCmdList["AETHERUI"]("diag")   -- must not error with a live report

check(bar.buttons[1].icon:GetTexture() == 130001, "action icon painted")
check(bar.buttons[8].count:GetText() == 20, "stack count shown")
check(bar.buttons[11].icon:IsShown() == false, "empty slot hides its icon")
check(bar.buttons[11].count:GetText() == "",
	"an emptied slot shows no count - the game keeps answering GetActionCount"
	.. " with the departed stack's number, so HasAction is asked first")
check(bar.buttons[6]:GetChecked() == true, "current action reads as active")
check(bar.buttons[6].glow:IsShown(), "active action lights its glow")

check(_G.__overrides["1"] == "AetherUIBar1Button1"
	and _G.__overrides["SHIFT-BUTTON4"] == "AetherUIBar1Button2",
	"override bindings point Blizzard's keys at our buttons")
check(bar.buttons[2].hotkey:GetText() == "SM4", "keybind text abbreviated")
check(bar.buttons[3].hotkey:GetText() == "N7", "numpad keybind abbreviated")

print("== dock sizing ==")
do
	local dock = bar.dock
	A.db.profile.scale = 1.0
	SlashCmdList["AETHERUI"]("bar 1 scale 0.8")
	check(math.abs(dock:GetScale() - 0.8) < 0.001,
		"per-bar scale multiplies that dock only (got " .. dock:GetScale() .. ")")
	SlashCmdList["AETHERUI"]("bar size 40")
	check(bar.buttons[1]:GetWidth() == 40, "bar size resizes the buttons")
	SlashCmdList["AETHERUI"]("bar 1 rows 1")
	local wide = dock:GetWidth()
	SlashCmdList["AETHERUI"]("bar 1 rows 2")
	check(dock:GetWidth() < wide, "two rows makes a narrower dock")
	SlashCmdList["AETHERUI"]("bar 1 rows 1")
	SlashCmdList["AETHERUI"]("bar size 62")
	SlashCmdList["AETHERUI"]("bar 1 scale 1")

	-- font offset reaches all three button font strings, live
	local function pt(fs) return fs.__font and fs.__font[2] end
	SlashCmdList["AETHERUI"]("bar font 0")
	local base = pt(bar.buttons[1].hotkey)
	SlashCmdList["AETHERUI"]("bar font 2")
	check(pt(bar.buttons[1].hotkey) == base + 2,
		"bar font offsets the keybind text (" .. base .. " -> " .. pt(bar.buttons[1].hotkey) .. ")")
	check(pt(bar.buttons[1].count) == A.Media:Size("stack") + 2,
		"bar font offsets the stack count")
	SlashCmdList["AETHERUI"]("bar font -9")
	check(pt(bar.buttons[1].hotkey) == base + 2, "out-of-range font offset is rejected")
end

print("== independent bars ==")
do
	local cfg = A.db.profile.modules.actionbars

	-- Bar 1 plus the two that size themselves. Bars 2-6 are off by default.
	local onCount, onIds = EnabledBars()
	check(onCount == 4, "bar 1, stance, pet and extra on; 2-6 off (" .. onIds .. ")")

	local byId = {}
	for _, b in ipairs(AB.bars) do byId[b.id] = b end
	check(byId["1"] and byId["stance"] and byId["pet"] and byId["extra"],
		"and they are the ones expected")

	-- no paging anywhere, which is the entire point
	check(_G.__stateDrivers.page == nil,
		"no page state driver exists at all - a bar's source is fixed at build time")
	check(byId["1"].buttons[1]:GetAttribute("_childupdate-actionpage") == nil,
		"and no restricted snippet rewrites a button's action behind our back")

	-- each bar owns a fixed block of actions
	check(byId["1"].buttons[1]:GetAttribute("action") == 1
		and byId["1"].buttons[12]:GetAttribute("action") == 12,
		"bar 1 owns actions 1-12")

	-- Enabling from the *options panel* has to build the bar, not just set a
	-- flag. Reconfigure only ever looked at bars that already existed, so ticking
	-- Enabled in the panel left the bar on and nowhere.
	do
		local tree = A.Options:Build()
		local opt = tree.args.actionbars.args.bar2.args.enabled
		local info = { arg = opt.arg, type = "toggle" }
		opt.set(info, true)
		local bar2
		for _, b in ipairs(AB.bars) do if b.id == "2" then bar2 = b end end
		check(bar2 ~= nil and bar2.dock:IsShown(),
			"ticking Enabled in the options panel builds the bar and shows it")
		check(bar2 and bar2.buttons[1]:GetAttribute("action") == 13,
			"and it owns actions 13-24")
		opt.set(info, false)
		check(bar2 and not bar2.dock:IsShown(), "unticking hides it again")
	end

	-- turning on bar 3 gives it actions 25-36, live
	AB:SetBarEnabled("3", true)
	local bar3
	for _, b in ipairs(AB.bars) do if b.id == "3" then bar3 = b end end
	check(bar3 ~= nil, "bar 3 can be switched on without a reload")
	check(bar3.buttons[1]:GetAttribute("action") == 25
		and bar3.buttons[12]:GetAttribute("action") == 36,
		"and owns actions 25-36, because bar N is page N")

	-- rows is the control; columns fall out of it
	SlashCmdList["AETHERUI"]("bar 3 rows 3")
	check(bar3.rows == 3 and bar3.cols == 4,
		"3 rows of 12 buttons lays out 4 wide (got " .. tostring(bar3.rows) .. "x"
		.. tostring(bar3.cols) .. ")")
	SlashCmdList["AETHERUI"]("bar 3 buttons 6")
	check(#bar3.buttons >= 6 and bar3.shown == 6, "buttons can be reduced to 6")
	check(bar3.buttons[7] and not bar3.buttons[7]:IsShown(),
		"the surplus is hidden, not leaked - frames cannot be destroyed")
	SlashCmdList["AETHERUI"]("bar 3 buttons 12")
	check(bar3.shown == 12, "and grown again")

	-- pointing a bar at another page re-addresses it in place
	SlashCmdList["AETHERUI"]("bar 3 page 7")
	check(bar3.buttons[1]:GetAttribute("action") == 73,
		"a bar can point at a bonus page (7-10), which is how a druid sees their"
		.. " form abilities without anything swapping under them")
	SlashCmdList["AETHERUI"]("bar 3 page 3")

	-- per-bar scale
	SlashCmdList["AETHERUI"]("bar 3 scale 0.5")
	local other = byId["1"].dock:GetScale()
	check(bar3.dock:GetScale() < other,
		"scale is per bar, so a side bar can shrink without dragging bar 1 with it")

	AB:SetBarEnabled("3", false)
	check(not bar3.dock:IsShown(), "and off again")
end

print("== stance and pet bars ==")
do
	local byId = {}
	for _, b in ipairs(AB.bars) do byId[b.id] = b end

	local stance = byId["stance"]
	check(#stance.buttons == 2,
		"the stance bar sizes itself from GetNumShapeshiftForms (got "
		.. #stance.buttons .. ")")
	check(stance.buttons[1]:GetID() == 1 and stance.buttons[2]:GetID() == 2,
		"buttons carry their form id, which is what Blizzard's template clicks on")
	check(stance.buttons[1].icon:GetTexture() == "Icons\\Bear", "form icon painted")
	check(stance.buttons[2].glow:IsShown(), "the active form is lit")

	-- learning a form has to grow the bar
	_G.__forms[3] = { texture = "Icons\\Travel", active = false, castable = true }
	fire("UPDATE_SHAPESHIFT_FORMS")
	check(#stance.buttons == 3, "learning a form grows the bar")
	_G.__forms[3] = nil
	fire("UPDATE_SHAPESHIFT_FORMS")
	check(stance.shown == 2, "and unlearning shrinks it back")

	local pet = byId["pet"]
	check(#pet.buttons == 10, "the pet bar always has its ten slots")
	check(pet.buttons[1].icon:GetTexture() == "Icons\\PetAttack", "pet icon painted")
	check(pet.buttons[3].icon:GetTexture() == "Icons\\PetGrowl",
		"a token action resolves through the global it names, rather than being"
		.. " used as a texture path")
	check(pet.buttons[5]:GetAlpha() < 1, "an empty pet slot dims")

	-- the pet bar's visibility is secure, because a pet can be dismissed in combat
	check(_G.__stateDrivers.visibility and _G.__stateDrivers.visibility:find("%[pet%]"),
		"pet bar visibility is a secure driver - a pet comes and goes mid-fight")
end

print("== adopted buttons ==")
do
	local extra
	for _, b in ipairs(AB.bars) do if b.kind == "extra" then extra = b end end
	check(extra ~= nil, "the extra bar exists")
	check(#extra.buttons == 1 and extra.buttons[1] == _G.MainMenuBarVehicleLeaveButton,
		"and has adopted Blizzard's own taxi button rather than building one")
	check(extra.buttons[1]:GetParent() == extra.header, "it is reparented onto our dock")
	check(extra.buttons[1].__aetherAdopted, "and marked, so layout leaves it alone in combat")

	-- Visibility comes from the game, not from the frame. Blizzard's button is
	-- :Show()n from the start and only invisible because its bar is hidden, so
	-- trusting IsShown() put an empty square on screen permanently.
	check(_G.__taxiButton:IsShown() == false,
		"adoption puts the button down rather than leaving it wherever it was")
	tick(0.1)
	check(not extra.dock:IsShown(),
		"and the dock stays down while you are not on a flight path, however the"
		.. " button itself feels about it")

	_G.__onTaxi = true
	tick(0.1)
	check(extra.dock:IsShown() and _G.__taxiButton:IsShown(),
		"boarding a taxi brings both up")

	_G.__onTaxi = false
	tick(0.1)
	check(not extra.dock:IsShown() and not _G.__taxiButton:IsShown(),
		"and landing puts them away again")

	-- a shown-but-irrelevant button must not drag the dock up with it
	_G.__taxiButton:Show()
	tick(0.1)
	check(not extra.dock:IsShown(),
		"a button that shows itself for its own reasons does not open the dock")

	-- it has to be placeable, which means visible while you are placing it
	check(A.Movers.registry.barextra ~= nil, "the extra bar has a mover like any other")
	check(extra.dock:GetWidth() > 1,
		"and a body to grab even with nothing in it (" .. extra.dock:GetWidth() .. ")")

	SlashCmdList["AETHERUI"]("unlock")
	check(extra.dock:IsShown(),
		"unlocking holds it up - you cannot drag a frame you can never see")
	tick(0.1)
	check(extra.dock:IsShown(), "and the ticker leaves it alone while you place it")
	SlashCmdList["AETHERUI"]("lock")
	tick(0.1)
	check(not extra.dock:IsShown(), "locking hands it back to the game")

	-- the pet bar has the same problem for a class with no pet out
	local pet
	for _, b in ipairs(AB.bars) do if b.kind == "pet" then pet = b end end
	SlashCmdList["AETHERUI"]("unlock")
	check(pet.visibilityDriven == false,
		"previewing the pet bar takes its secure visibility driver off rather than"
		.. " arguing with it")
	SlashCmdList["AETHERUI"]("lock")
	check(pet.visibilityDriven == true, "and puts it back on lock")

	-- and it parks beside bar 1 rather than in the middle of the screen
	local d = AB.DefaultAnchor(extra)
	check(d.point == "BOTTOM" and d.x > 0,
		"its default position is to the right of bar 1, computed from bar 1's"
		.. " actual width (x " .. math.floor(d.x) .. ")")
	extra.cfg.side = "left"
	check(AB.DefaultAnchor(extra).x < 0, "and to the left when asked")
	extra.cfg.side = "right"
end

print("== cooldowns ==")
-- Anchor the mock cooldowns to *now*: the session has been running for a while
-- by this point and anything set at load time has long since expired.
_G.__actions[3].cd = { time, 30 }
_G.__actions[5].cd = { time, 1.5 }
fire("SPELL_UPDATE_COOLDOWN")
tick(0.1)
check(bar.buttons[3].cdText:GetText() ~= "" and bar.buttons[3].cdText:GetText() ~= nil,
	"real cooldown draws a countdown (" .. tostring(bar.buttons[3].cdText:GetText()) .. ")")
check((bar.buttons[5].cdText:GetText() or "") == "",
	"1.5s global does not paint a countdown")
_G.__actions[3].cd = nil
fire("SPELL_UPDATE_COOLDOWN")
tick(0.1)
check((bar.buttons[3].cdText:GetText() or "") == "", "countdown clears when the cooldown ends")

print("== drag and drop ==")
local b = bar.buttons[4]
b:GetScript("OnDragStart")(b)
check(_G.__picked == 4, "dragging picks up the right action")
b:GetScript("OnReceiveDrag")(b)
check(_G.__placed == 4, "dropping places into the right action")


print("== the target's cast bar is not your cast bar ==")
do
	-- Two capsules stacked one above the other, both the concept's blue, was
	-- unreadable mid-fight: the only thing distinguishing them was the spell
	-- name, which is the slowest thing on either bar to read.
	local UFm = A:GetModule("unitframes")
	_G.__units.target.exists = true
	_G.__units.target.reaction = 2          -- hostile

	time = time + 1
	_G.__ccCasts.target = { name = "Lightning Bolt", icon = 1, channel = false,
		start = time * 1000, finish = (time + 3) * 1000 }
	_G.__ccFire("UNIT_SPELLCAST_START", "target")
	local theirs = UFm.targetCast.bar._colors
	check(theirs == A.Palette.c.hostileBar,
		"a hostile caster's bar takes the hostile colours")

	castState = { name = "Fireball", icon = 135812, channel = false,
		startTime = time * 1000, endTime = (time + 2.5) * 1000 }
	fire("UNIT_SPELLCAST_START", "player")
	local yours = UFm.cast.bar._colors
	check(yours == A.Palette.c.cast, "and yours stays the concept's blue")
	check(yours ~= theirs, "so the two stacked bars are tellable apart at a glance")

	-- the glow follows the bar rather than staying blue around a red capsule
	local head = theirs[1]
	local gr, gg, gb = UFm.targetCast.glow:GetVertexColor()
	check(math.abs(gr - head[1]) < 0.01 and math.abs(gg - head[2]) < 0.01
		and math.abs(gb - head[3]) < 0.01,
		"and the glow takes the bar's head, not a blue halo round a red bar")

	-- friendly and neutral are their own answers, not just "not hostile"
	_G.__units.target.reaction = 4
	check(A.Palette:CastColor("target") ~= A.Palette.c.hostileBar, "neutral differs")
	_G.__units.target.reaction = 5
	check(A.Palette:CastColor("target") == A.Palette.c.cast,
		"a friendly caster is not painted as a threat")

	-- your own frame is never a reaction
	check(A.Palette:ReactionEdge("player") == A.Palette.c.glassEdge,
		"and the player's own rim never picks up friendly green off"
		.. " UnitReaction('player', 'player')")

	-- the toggle really turns it off
	A.db.profile.modules.unitframes.reactionTint = false
	_G.__units.target.reaction = 2
	_G.__ccCasts.target = { name = "Lightning Bolt", icon = 1, channel = false,
		start = time * 1000, finish = (time + 3) * 1000 }
	_G.__ccFire("UNIT_SPELLCAST_START", "target")
	check(UFm.targetCast.bar._colors == A.Palette.c.cast,
		"turning the tint off puts both bars back to blue")
	A.db.profile.modules.unitframes.reactionTint = true

	_G.__ccCasts.target = nil
	_G.__ccFire("UNIT_SPELLCAST_STOP", "target")
	castState = nil
	fire("UNIT_SPELLCAST_STOP", "player")
	_G.__units.target.reaction = 2
	_G.__units.target.exists = false
	fire("PLAYER_TARGET_CHANGED")
end

print("== auras: four trays of icon tiles ==")
-- the idle-fader section above dropped the target; put it back
_G.__units.target.exists = true
fire("PLAYER_TARGET_CHANGED")

local AU = A:GetModule("auras")
check(AU and AU.enabled, "auras module enabled"
	.. (AU and AU.lastError and ("  -- " .. AU.lastError) or ""))
check(#AU.trays == 4, "four trays: buffs and debuffs, player and target")

local PB, PD = AU.playerBuffs, AU.playerDebuffs
local TB, TD = AU.targetBuffs, AU.targetDebuffs

check(PB.active == 4, "four player buffs (got " .. PB.active .. ")")
check(PD.active == 2, "two player debuffs (got " .. PD.active .. ")")
check(TB.active == 2, "target buffs are shown at all now (got " .. TB.active .. ")")
check(TD.active == 3,
	"and only the player's own target debuffs (got " .. TD.active .. ")")

do  -- a tile is an icon and a timer, and nothing else
	local t = PB.tiles[1]
	check(t.name == nil, "no name field on a tile - the name is on the tooltip")
	check(t.art.icon:GetTexture() == 135843, "the icon is painted")
	check(t.time:GetText() == "30m", "the timer reads in minutes at this range")
	-- A mount, a Well Fed, most things a player walks around with. The field is
	-- fixed width either way, so an empty one read as a pill that had failed to
	-- load rather than one with nothing to say.
	check(PB.tiles[4].time:GetText() == "n/a",
		"a permanent aura says so rather than leaving the timer field blank")
	do
		-- On login the server has not finished sending aura data and everything
		-- comes back with a zero duration, which is indistinguishable from a
		-- permanent aura - so every buff was marked timeless, and a timeless tile
		-- is one the ticker never looks at again.
		local saved = _G.__auras.player.HELPFUL
		_G.__auras.player.HELPFUL = {
			{ "Frost Armor", 135843, 0, nil, 0, nil, "player", true },
		}
		fire("PLAYER_ENTERING_WORLD")
		check(PB.tiles[1].time:GetText() == "n/a", "a zero duration reads as timeless")
		_G.__auras.player.HELPFUL = saved
		_G.__tick()                       -- the settle pass the load kicked off
		check(PB.tiles[1].time:GetText() ~= "n/a",
			"and the settle pass picks up the real numbers when they arrive,"
			.. " without needing a UNIT_AURA to happen along")
	end
	check(PB.tiles[4]:GetWidth() == PB.tiles[1]:GetWidth(),
		"and keeps the same width as a timed one")
	check(PB.tiles[3].count:GetText() == 3, "a stack shows its count")
	check(PB.tiles[1].count:GetText() == "", "and a single application does not")

	local spec = AU.spec
	check(t:GetWidth() > spec.size * 2,
		"the pill is wide enough for the icon and a timer beside it")
	check(t:GetHeight() == spec.size + 8,
		"and only a little taller than the icon it wraps, the way the deck draws it")
	check(t.time:GetWidth() == 30,
		"the timer field is fixed width, so a ticking timer cannot resize the pill")
	check(PB.tiles[1]:GetWidth() == PB.tiles[4]:GetWidth(),
		"a permanent aura's pill is the same width as a timed one - the grid has"
		.. " to stay a grid")
end

print("== no tray exceeds the frame it belongs to ==")
do
	local cfg = A.db.profile.modules.auras
	local ufcfg = A.db.profile.modules.unitframes

	for _, t in ipairs(AU.trays) do
		local d = t.display
		local rowW = d.opts.perRow * (AU:TileWidth() + cfg.spacing) - cfg.spacing
		check(rowW <= UF.player:GetWidth(),
			("%s: a full row is %d wide, the capsule is %d")
				:format(t.key, rowW, UF.player:GetWidth()))
	end

	-- Columns are derived, not configured: widen the capsule and every tray gets
	-- wider on its own.
	local before = PB.opts.perRow
	local savedW, savedBar = ufcfg.width, ufcfg.barWidth
	ufcfg.width, ufcfg.barWidth = 500, 340
	A:Reconfigure()
	check(PB.opts.perRow > before,
		("a wider capsule gets more columns without touching the config (%d -> %d)")
			:format(before, PB.opts.perRow))
	ufcfg.width, ufcfg.barWidth = savedW, savedBar
	A:Reconfigure()
	check(PB.opts.perRow == before, "and loses them again when it narrows")

	-- perRow is a cap, not the source
	cfg.perRow = 3
	AU:OnConfigChanged()
	check(PB.opts.perRow == 3, "setting a column cap uses it")
	cfg.perRow = 0
	AU:OnConfigChanged()
	check(PB.opts.perRow == before, "and 0 goes back to whatever fits")
end

print("== the capsules never resize ==")
do
	local cfg = A.db.profile.modules.unitframes

	check(UF.player.tray == nil and UF.target.tray == nil,
		"there is no in-capsule tray any more")
	check(UF.player.glass:GetHeight() == cfg.height
		and UF.target.glass:GetHeight() == cfg.height,
		"both capsules sit at their designed height")
	check(select(1, UF.player.glass:GetPoint(1)) == "ALL",
		"the glass fills the core exactly rather than being pinned to its top edge")

	-- The complaint that started this: one unit with a debuff and one without
	-- used to be two frames of different heights side by side.
	local savedP = _G.__auras.player.HARMFUL
	_G.__auras.player.HARMFUL = {}
	fire("UNIT_AURA", "player")
	check(PD.active == 0 and TD.active > 0, "player clean, target debuffed")
	check(UF.player.glass:GetHeight() == UF.target.glass:GetHeight(),
		"the two capsules are still exactly the same height - which is the whole"
		.. " point of taking the auras out of them")
	_G.__auras.player.HARMFUL = savedP
	fire("UNIT_AURA", "player")
end

print("== tray placement ==")
do
	local cfg = A.db.profile.modules.auras

	local bp, brel, brelP = PB.frame:GetPoint(1)
	check(bp == "BOTTOMLEFT" and brel == UF.player and brelP == "TOPLEFT",
		"player buffs hang off the top of the player capsule (got "
		.. tostring(bp) .. " -> " .. tostring(brelP) .. ")")
	local dp, drel, drelP = PD.frame:GetPoint(1)
	check(dp == "TOPLEFT" and drel == UF.player and drelP == "BOTTOMLEFT",
		"player debuffs off the bottom")
	check(select(2, TB.frame:GetPoint(1)) == UF.target
		and select(2, TD.frame:GetPoint(1)) == UF.target,
		"and the target's two hang off the target, the same way round")

	check(PB.opts.growUp and not PD.opts.growUp,
		"rows grow away from the capsule, so the row nearest the frame stays put")
	check(PB.frame:GetParent() == UF.player,
		"a tray is a child of its capsule, so it inherits the fade and the scale")
	check(PB.frame:GetScale() == 1,
		"and takes no scale of its own - the capsule is already scaled")

	-- Centred, because a row of pills almost never divides evenly into a capsule
	-- and the slack pushed onto one side reads as a pill that failed to load.
	check(PB.opts.align == "CENTER" and TD.opts.align == "CENTER",
		"rows are centred on their frame by default")
	do
		local n, tw, gap = PB.active, AU:TileWidth(), cfg.spacing
		local rowW = n * tw + (n - 1) * gap
		local p, rel, relP, x = PB.tiles[1]:GetPoint(1)
		check(p == "BOTTOM" and relP == "BOTTOM" and rel == PB.frame,
			"a centred tile is anchored on the frame's centre line")
		check(math.abs(x - (-rowW / 2 + tw / 2)) < 0.01,
			("the first pill sits half a row left of centre (%.1f)"):format(x))
		-- and the row is symmetric about it
		local _, _, _, xn = PB.tiles[n]:GetPoint(1)
		check(math.abs(x + xn) < 0.01,
			("the last pill mirrors it (%.1f vs %.1f)"):format(x, xn))
	end

	-- ...and mirrored is still there for anyone who wants it
	cfg.align = "MIRROR"
	AU:OnConfigChanged()
	check(PB.opts.align == "LEFT" and TD.opts.align == "RIGHT",
		"mirrored follows the unit's own name and readout - left on the player,"
		.. " right on the target")
	check(select(1, TD.tiles[1]:GetPoint(1)) == "TOPRIGHT",
		"so a half-full target row is measured back from the right edge")
	cfg.align = "CENTER"
	AU:OnConfigChanged()

	-- second row
	local savedB = _G.__auras.player.HELPFUL
	local many = {}
	for i = 1, PB.opts.perRow + 2 do
		many[i] = { "Buff " .. i, 130000 + i, 0, nil, 60, nil, "player", true }
	end
	_G.__auras.player.HELPFUL = many
	fire("UNIT_AURA", "player")
	check(PB.active == PB.opts.perRow + 2, "a full row plus two")
	local _, _, _, _, y1 = PB.tiles[1]:GetPoint(1)
	local _, _, _, _, y2 = PB.tiles[PB.opts.perRow + 1]:GetPoint(1)
	check(y2 > y1, "the second row stacks upward, away from the capsule")
	_G.__auras.player.HELPFUL = savedB
	fire("UNIT_AURA", "player")
end

print("== timers ==")
do
	local before = PB.tiles[1]:GetWidth()
	time = time + 120
	PB:Tick()
	check(PB.tiles[1].time:GetText() == "28m", "the timer ticks down")
	check(PB.tiles[1]:GetWidth() == before,
		"and cannot reflow anything - every tile is the same size whatever its"
		.. " timer says")

	-- an aura about to fall off says so
	local saved = _G.__auras.player.HELPFUL
	_G.__auras.player.HELPFUL = {
		{ "Ice Barrier", 135988, 0, nil, 30, nil, "player", true },
	}
	fire("UNIT_AURA", "player")
	PB:Tick()
	check(PB.tiles[1]._urgent == false, "a healthy timer is not urgent")
	time = time + 27
	PB:Tick()
	check(PB.tiles[1]._urgent == true, "under five seconds it turns urgent")
	_G.__auras.player.HELPFUL = saved
	fire("UNIT_AURA", "player")
	PB:Tick()
	check(PB.tiles[1]._urgent ~= true, "and back again when it is replaced")
end


print("== auras: a timer that has not arrived yet is never a blank field ==")
do
	local saved = _G.__auras.player.HELPFUL

	-- Case one, as the client actually reports it for the first few seconds
	-- after a login: a real duration with an expiry of zero. This used to come
	-- out of W.AuraTime as an empty string, get written to a fixed-width field,
	-- and stay empty for the rest of the session because the tile was not
	-- flagged timeless and the ticker just kept writing the same nothing.
	_G.__auras.player.HELPFUL = {
		{ "Arcane Intellect", 135932, 0, nil, 1800, nil, "player", true, 0 },
	}
	fire("UNIT_AURA", "player")
	local t = PB.tiles[1]
	check(t.time:GetText() == "n/a",
		"a duration with no expiry reads n/a rather than going blank (got '"
		.. tostring(t.time:GetText()) .. "')")
	check(t._stale == true and t._timeless == false,
		"and is marked stale, not permanent - the difference is whether we ever"
		.. " ask again")

	-- the server catches up. No UNIT_AURA fires, because nothing changed as far
	-- as the client is concerned - the re-poll is the only thing that can notice.
	_G.__auras.player.HELPFUL[1][9] = nil
	for i = 1, 15 do tick(0.1) end
	check(t.time:GetText() == "30m",
		"and the tile picks the real timer up on its own, with no UNIT_AURA to"
		.. " prompt it (got '" .. tostring(t.time:GetText()) .. "')")
	check(t._stale == false, "and stops asking")

	-- Case two: duration zero, which is what a permanent aura and an aura the
	-- server has not described yet both look like.
	_G.__auras.player.HELPFUL = {
		{ "Frost Armor", 135843, 0, nil, 0, nil, "player", true },
	}
	fire("UNIT_AURA", "player")
	t = PB.tiles[1]
	check(t.time:GetText() == "n/a" and t._timeless == true,
		"duration zero reads n/a and is believed permanent")

	_G.__auras.player.HELPFUL[1][5] = 1800
	for i = 1, 15 do tick(0.1) end
	check(t.time:GetText() == "30m",
		"but the belief is re-tested, so a buff that turns out to have a timer"
		.. " gets one (got '" .. tostring(t.time:GetText()) .. "')")

	-- and a re-poll must not read a neighbour's clock when indices shift
	_G.__auras.player.HELPFUL = {
		{ "Well Fed", 133905, 0, nil, 0, nil, nil, false },
	}
	fire("UNIT_AURA", "player")
	t = PB.tiles[1]
	check(t._timeless == true and t._name == "Well Fed", "a genuinely permanent aura")
	_G.__auras.player.HELPFUL = {
		{ "Ice Barrier", 135988, 0, nil, 60, nil, "player", true },
	}
	for i = 1, 15 do tick(0.1) end   -- no UNIT_AURA: the tile still thinks it is Well Fed
	check(t.time:GetText() == "n/a",
		"whose tile refuses to take a duration from whatever now sits at its"
		.. " index, because the name no longer matches")

	-- The sequence actually seen in game. The buff is a real thirty-minute one
	-- with time left on it, but at login the client hands out an expiry that is
	-- only a few seconds away. The tile counts that down, reaches zero, and -
	-- before this - printed an empty string into a fixed-width field and kept
	-- printing it, because a tile only ever re-formats the numbers it cached at
	-- the last Update and UNIT_AURA never fires again if nothing changes.
	_G.__auras.player.HELPFUL = {
		{ "Arcane Intellect", 135932, 0, nil, 1800, nil, "player", true,
		  GetTime() + 3 },
	}
	fire("UNIT_AURA", "player")
	t = PB.tiles[1]
	check(t.time:GetText() == "3s", "a bad expiry from the server counts down")
	for i = 1, 40 do tick(0.1) end
	check(t.time:GetText() ~= "",
		"and when it runs out the field never goes blank (got '"
		.. tostring(t.time:GetText()) .. "')")

	_G.__auras.player.HELPFUL[1][9] = nil   -- the client finally has it right
	for i = 1, 15 do tick(0.1) end
	check(t.time:GetText() == "30m",
		"the tile re-reads and picks up the real remaining time, with no"
		.. " UNIT_AURA and long after Resettle has given up (got '"
		.. tostring(t.time:GetText()) .. "')")

	-- the diagnostic has to survive whatever state the trays are in, because the
	-- one time anybody runs it is when something is wrong
	_G.__auras.player.HELPFUL = {
		{ "Arcane Intellect", 135932, 0, nil, 1800, nil, "player", true, 0 },
		{ "Well Fed", 133905, 0, nil, 0, nil, nil, false },
	}
	fire("UNIT_AURA", "player")
	local printed = 0
	local realAdd = DEFAULT_CHAT_FRAME.AddMessage
	DEFAULT_CHAT_FRAME.AddMessage = function(self, msg)
		printed = printed + 1
		realAdd(self, msg)
	end
	local ok, err = pcall(function() SlashCmdList["AETHERUI"]("auras") end)
    DEFAULT_CHAT_FRAME.AddMessage = realAdd
	check(ok, "the aura diagnostic runs: " .. tostring(err))
	check(printed > 8,
		"and prints what the API says next to what the tile believes, which is the"
		.. " only way any of these has ever actually been found (" .. printed
		.. " lines)")

	_G.__auras.player.HELPFUL = saved
	fire("UNIT_AURA", "player")
end

print("== an empty tray takes up no room ==")
do
	local tall = PB.frame:GetHeight()
	local saved = _G.__auras.player.HELPFUL
	_G.__auras.player.HELPFUL = {}
	fire("UNIT_AURA", "player")
	check(PB.frame:GetHeight() < tall and PB.active == 0,
		"an empty tray collapses instead of holding its last size")
	check(PB.tiles[1]:GetAlpha() == 0,
		"and its tiles are parked rather than hidden - hiding one would be"
		.. " refused in combat, since they carry secure cancel buttons")
	_G.__auras.player.HELPFUL = saved
	fire("UNIT_AURA", "player")

	_G.__units.target.exists = false
	fire("PLAYER_TARGET_CHANGED")
	check(TB.active == 0 and TD.active == 0, "both target trays clear with no target")
	_G.__units.target.exists = true
	fire("PLAYER_TARGET_CHANGED")
	check(TD.active == 1 or TD.active == 3, "and come back with one")
end

print("== turning a tray off ==")
do
	local cfg = A.db.profile.modules.auras
	cfg.buffs.target = false
	AU:OnConfigChanged()
	check(not AU.trays[3].enabled and TB.active == 0,
		"target buffs off empties that tray and only that tray")
	check(TD.active > 0, "the target's debuffs are untouched")
	cfg.buffs.target = true
	AU:OnConfigChanged()
	check(TB.active > 0, "and back on again")
end

print("== right-click to cancel ==")
do
	local cfg = A.db.profile.modules.auras.buffs

	check(AU.playerBuffs.tiles[PB.opts.max] ~= nil,
		"every buff tile is built up front, not lazily (" .. PB.opts.max .. " of them)")

	local bad = nil
	for i = 1, PB.opts.max do
		local c = PB.tiles[i] and PB.tiles[i].click
		if not c or c:GetAttribute("type2") ~= "macro" then bad = i break end
	end
	check(bad == nil, "every tile carries a secure macro button"
		.. (bad and (" (tile " .. bad .. " does not)") or ""))

	-- "cancelaura" as a secure action type does not dispatch on Classic Era -
	-- right-click did nothing. /cancelaura via a macro does.
	local m = {}
	for i = 1, PB.active do m[i] = PB.tiles[i].click:GetAttribute("macrotext2") end
	check(m[1] == "/cancelaura Frost Armor" and m[3] == "/cancelaura Ice Barrier",
		"the macro cancels by name (got " .. tostring(m[3]) .. ")")

	check(select(1, PB.tiles[1].click:GetPoint(1)) == "ALL",
		"the cancel button tracks the tile with SetAllPoints, so resizing the tile"
		.. " in combat never touches the secure frame")
	check(PB.tiles[1].click:GetScript("PreClick") == nil,
		"nothing insecure sits *before* the secure dispatch - a PreClick hook taints"
		.. " it and the cancel gets refused in combat")
	check(PB.tiles[1].click:GetScript("PostClick") ~= nil,
		"but PostClick does the out-of-combat cancel, after the dispatch")

	check(PD.tiles[1] and PD.tiles[1].click == nil and PD.tiles[1]._auraName == nil,
		"debuff tiles get no cancel wiring at all - debuffs cannot be cancelled")
	check(TB.tiles[1] and TB.tiles[1].click == nil,
		"and neither do the target's buffs - they are not yours to drop")

	-- the actual cancel, both routes
	do
		_G.__cancelled = nil
		PB.tiles[2].click:GetScript("PostClick")(PB.tiles[2].click, "RightButton")
		check(_G.__cancelled ~= nil and _G.__cancelled.index == 2,
			"right-click out of combat cancels the buff that tile is showing")

		_G.__cancelled = nil
		PB.tiles[2].click:GetScript("PostClick")(PB.tiles[2].click, "LeftButton")
		check(_G.__cancelled == nil, "left-click does not")

		_G.__inCombat = true
		_G.__cancelled = nil
		PB.tiles[2].click:GetScript("PostClick")(PB.tiles[2].click, "RightButton")
		check(_G.__cancelled == nil,
			"and in combat the insecure route stands down - only the macro can act")
		_G.__inCombat = false

		-- the tile underneath covers the case where the secure button never built
		_G.__cancelled = nil
		local orphan = PB.tiles[3]
		orphan:GetScript("OnMouseUp")(orphan, "RightButton")
		check(_G.__cancelled ~= nil and _G.__cancelled.index == 3,
			"the tile's own OnMouseUp is the same handler, for when there is no"
			.. " secure button on top of it")
	end

	-- raising the cap mid-fight has to defer, then land
	-- The cap is min(configured max, columns x rows), so raising it means
	-- raising the row count, not the number - which is itself worth asserting.
	local cols, wasMax, wasRows = PB.opts.perRow, PB.opts.max, cfg.maxRows
	-- Tiles are never destroyed, only parked, and an earlier section ran with the
	-- unit frames off - where a tray has no capsule to size itself against and
	-- takes the configured max instead. Start this one from an empty display so
	-- "was it built during the fight" means what it says.
	for i = #PB.tiles, 1, -1 do PB.tiles[i] = nil end
	PB.active = 0
	_G.__inCombat = true
	cfg.maxRows = wasRows + 2
	AU:OnConfigChanged()
	local want = math.min(cfg.max, cols * cfg.maxRows)
	check(PB.opts.max == want and want > wasMax,
		("the cap is columns x rows, capped by the configured max (%d)"):format(want))
	check(PB._primePending, "raising the buff cap in combat defers the wiring")
	check(PB.tiles[want] == nil or PB.tiles[want].click == nil,
		"and writes no secure attribute while locked")
	_G.__inCombat = false
	fire("PLAYER_REGEN_ENABLED")
	check(PB.tiles[want] and PB.tiles[want].click
		and PB.tiles[want].click:GetAttribute("type2") == "macro",
		"the deferred wiring lands when the fight ends")
	check(not PB._primePending, "and the pending flag clears")
	cfg.maxRows = wasRows
	AU:OnConfigChanged()

	-- The one this whole section was missing. The tray's tiles carry secure
	-- buttons, so the tray *and every tile in it* is off limits for geometry in
	-- combat - the restriction reaches ancestors, not just the protected frame.
	-- Buffs coming and going mid-fight is the most ordinary thing there is, and
	-- it produced fourteen blocked-action reports per fight.
	local savedBuffs = _G.__auras.player.HELPFUL
	_G.__inCombat = true
	A.lastFailure = nil

	_G.__auras.player.HELPFUL = {
		{ "Arcane Intellect", "T1", 0, nil, 1800, GetTime() + 1500, true },
		{ "Ice Armor",        "T2", 0, nil, 1800, GetTime() + 900,  true },
		{ "Evocation",        "T3", 3, nil,    8, GetTime() + 6,    true },
	}
	fire("UNIT_AURA", "player")
	_G.__auras.player.HELPFUL = {
		{ "Arcane Intellect", "T1", 0, nil, 1800, GetTime() + 1500, true },
	}
	fire("UNIT_AURA", "player")

	check(A.lastFailure == nil,
		"buffs coming and going mid-fight ask the client for nothing it will"
		.. " refuse (" .. tostring(A.lastFailure) .. ")")
	check(PB.active == 1, "and the tray still tracks what is actually up")
	check(PB.tiles[1]:GetAlpha() == 1 and PB.tiles[2]:GetAlpha() == 0,
		"the ones that dropped go to alpha rather than being moved or hidden")
	check(PB._layoutPending, "with the layout owed until the fight ends")

	-- A tile that has never been on screen still has a home, or a buff gained
	-- mid-fight would land nowhere: a frame with no points does not draw.
	check(PB.tiles[PB.opts.max] and PB.tiles[PB.opts.max]:GetPoint(1) ~= nil,
		"every slot was placed up front, so a new buff mid-fight has somewhere"
		.. " to appear")

	_G.__inCombat = false
	fire("PLAYER_REGEN_ENABLED")
	check(not PB._layoutPending, "and the layout is settled when it does")

	_G.__auras.player.HELPFUL = savedBuffs
	fire("UNIT_AURA", "player")
end

print("== quest tracker ==")

local QT = A:GetModule("questtracker")
check(QT and QT.enabled, "questtracker module enabled"
	.. (QT and QT.lastError and ("  -- " .. QT.lastError) or ""))
check(QT.panel and QT.panel.header, "glass panel with a header built")

do
	-- The fader section above entered combat and never left it, so the tracker
	-- is legitimately folded by the time we get here. Start from a known state.
	_G.__inCombat = false
	QT._preCombat = nil
	QT:SetCollapsed(false)
	A.db.char.tracked, A.db.char.untracked = {}, {}
	QT:Refresh()

	-- auto mode is the default: everything in the log, nothing to opt in to
	check(#QT.quests == 4,
		"auto-track shows every quest in the log with no gesture at all (got "
		.. #QT.quests .. ")")
	check(GetNumQuestWatches() == 0 and #_G.__watches == 0,
		"and never touches Blizzard's watch list to do it")
	check(QT.panel.header.count:GetText() == "4 / 20",
		"the heading counts quests in the log, not headers in it (got "
		.. tostring(QT.panel.header.count:GetText()) .. ")")

	-- dismissing one is a blacklist entry, and it has to stick across a refresh
	QT.SetTracked(1069, false)
	QT:Refresh()
	check(#QT.quests == 3 and A.db.char.untracked[1069],
		"dismissing a quest blacklists it rather than rebuilding a whitelist")
	local stillThere = false
	for _, q in ipairs(QT.quests) do
		if q.questID == 1069 then stillThere = true end
	end
	check(not stillThere, "and it stays gone across a refresh")

	-- a newly accepted quest appears on its own
	table.insert(_G.__questLog, { id = 7777, title = "A Fresh Errand", level = 20,
		objectives = { { "Errand run: 0/1", "event", false } } })
	QT:Refresh()
	check(#QT.quests == 4, "a newly accepted quest shows up without being tracked")
	table.remove(_G.__questLog)

	QT.SetTracked(1069, true)
	QT:Refresh()
	check(#QT.quests == 4 and A.db.char.untracked[1069] == nil, "and can be brought back")
end

do  -- both sets are pruned against the live log, the way Questie prunes its two
	A.db.char.untracked[999999] = true
	A.db.char.tracked[888888] = true
	QT:Refresh()
	check(A.db.char.untracked[999999] == nil and A.db.char.tracked[888888] == nil,
		"IDs that are not in the log are dropped from both sets - neither can grow"
		.. " without bound")
end

print("== quest tracker: manual mode ==")
do
	A.db.profile.modules.questtracker.autoTrack = false
	A.db.char.tracked, A.db.char.untracked = {}, {}
	QT:Refresh()
	check(#QT.quests == 0, "manual mode starts empty - it is a whitelist")
	local bare = QT.panel:GetHeight()

	-- shift-clicking in Blizzard's quest log puts an index in ITS watch list;
	-- we adopt it and hand the slot straight back, which is the only way that
	-- gesture keeps working past Blizzard's five-quest cap
	AddQuestWatch(2)
	AddQuestWatch(3)
	QT:Refresh()
	check(GetNumQuestWatches() == 0,
		"Blizzard's watch list is emptied again, so its five-slot cap never bites")
	check(A.db.char.tracked[861] and A.db.char.tracked[1069],
		"and both quests landed in our own set, keyed by questID")
	check(#QT.quests == 2, "two rows now (got " .. #QT.quests .. ")")
	check(QT.panel:GetHeight() > bare, "the panel grew to fit them")
end

do
	local row = QT.panel.rows[1]
	check(row.questTitle == "Chen's Empty Keg", "row 1 is the first tracked quest in log order")
	check(row.lines[1]:GetText() == "Empty Keg: 0/1", "objective text rendered")
	check(math.abs(QT.quests[1].pct - 0) < 0.01,
		"progress comes from the numbers in the objective text")
	check(QT.quests[2].complete and math.abs(QT.quests[2].pct - 1) < 0.01,
		"a finished quest reads as complete")
end

do  -- indices shift when the log changes; the tracker must not hold one
	table.insert(_G.__questLog, 2, { id = 99, title = "A New Quest", level = 12, objectives = {} })
	QT:Refresh()
	local row = QT.panel.rows[1]
	check(row.questTitle == "Chen's Empty Keg" and row.index == 3,
		"the same quest is still row 1, now at log index " .. tostring(row.index)
		.. " - tracking is by questID, not by index")
	table.remove(_G.__questLog, 2)
	QT:Refresh()
end

do  -- partial progress across two objectives: 3/8 and 1/4 is 4/12
	AddQuestWatch(5)
	QT:Refresh()
	local q
	for _, entry in ipairs(QT.quests) do
		if entry.questID == 4901 then q = entry end
	end
	check(q and math.abs(q.pct - (4 / 12)) < 0.001,
		"progress sums the counters across every objective (got "
		.. string.format("%.3f", q and q.pct or -1) .. ")")
	check(#QT.panel.rows[3].lines >= 2, "both objective lines drawn")
end

do  -- a quest with no objectives falls back to isComplete rather than showing 0%
	AddQuestWatch(6)
	QT:Refresh()
	local q
	for _, entry in ipairs(QT.quests) do
		if entry.questID == 5041 then q = entry end
	end
	check(q and #q.lines == 0 and q.pct == nil,
		"an objective-less quest gets no bar at all, rather than one pinned at zero")
end

print("== quest tracker: height budget ==")
do
	local cfg = A.db.profile.modules.questtracker
	local saved = cfg.maxHeight
	cfg.maxHeight = 80
	QT:Refresh()
	check(QT.hidden > 0, "a tight height budget drops rows (" .. QT.hidden .. " of them)")
	check(QT.panel.more:IsShown() and QT.panel.more:GetText() == "+" .. QT.hidden .. " more",
		"and the panel says so rather than silently truncating (got "
		.. tostring(QT.panel.more:GetText()) .. ")")
	local tight = QT.panel:GetHeight()
	cfg.maxHeight = saved
	QT:Refresh()
	check(not QT.panel.more:IsShown() and QT.panel:GetHeight() > tight,
		"restoring the budget brings them back")
end

print("== quest tracker: clicks ==")
do
	local row = QT.panel.rows[1]

	_G.__questLogOpenedTo = nil
	row:GetScript("OnMouseUp")(row, "LeftButton")
	check(_G.__questLogOpenedTo == row.index, "left-click opens the log to that quest")

	-- shift-click untracks
	_G.__shift = true
	local before = #QT.quests
	row:GetScript("OnMouseUp")(row, "LeftButton")
	check(#QT.quests == before - 1, "shift-click stops tracking it")
	check(A.db.char.tracked[861] == nil, "and it leaves our set")
	_G.__shift = false
	AddQuestWatch(2)
	QT:Refresh()

	-- right-click menu
	local r = QT.panel.rows[1]
	r:GetScript("OnMouseUp")(r, "RightButton")
	check(QT.menu and QT.menu:IsShown(), "right-click opens the menu")
	check(#QT.menu.items >= 4, "menu has open / untrack / share / abandon")
	check(QT.menu.items[1].text:GetText() == "Open quest log", "first item opens the log")

	_G.__questShared = nil
	QT.menu.items[3]:GetScript("OnClick")(QT.menu.items[3])
	check(_G.__questShared == r.index, "share quest routes through SelectQuestLogEntry")
	check(not QT.menu:IsShown(), "and the menu closes behind it")

	_G.__abandonPopup = nil
	r:GetScript("OnMouseUp")(r, "RightButton")
	QT.menu.items[4]:GetScript("OnClick")(QT.menu.items[4])
	check(_G.__abandonPopup == "ABANDON_QUEST",
		"abandon goes through Blizzard's confirmation, never straight to AbandonQuest")
end

print("== quest tracker: combat fold ==")
do
	-- Start from what a fresh load actually looks like. `collapsed` is nil until
	-- something sets it, and every check below used to begin by setting it -
	-- which is why the bug survived: the state that breaks the restore was the
	-- one state the test never used. First fight of a session folds it and it
	-- never comes back.
	QT.collapsed = nil
	QT._preCombat = nil
	_G.__inCombat = true
	fire("PLAYER_REGEN_DISABLED")
	_G.__inCombat = false
	fire("PLAYER_REGEN_ENABLED")
	check(not QT.collapsed,
		"the first fight after a load gives the tracker back afterwards - nil is"
		.. " a state, not the absence of one")

	QT:SetCollapsed(false)
	local open = QT.panel:GetHeight()
	check(QT.panel.body:IsShown(), "body visible out of combat")

	_G.__inCombat = true
	fire("PLAYER_REGEN_DISABLED")
	check(QT.collapsed and not QT.panel.body:IsShown(), "folds to the heading in combat")
	local folded = QT.panel:GetHeight()
	check(folded < open, "and the panel is shorter for it ("
		.. math.floor(folded) .. " < " .. math.floor(open) .. ")")

	-- unfolding by hand mid-fight has to survive the end of the fight
	QT:ToggleCollapsed()
	check(not QT.collapsed, "you can unfold it by hand during the fight")
	_G.__inCombat = false
	fire("PLAYER_REGEN_ENABLED")
	check(not QT.collapsed, "and leaving combat does not fold it back on you")

	_G.__inCombat = true
	fire("PLAYER_REGEN_DISABLED")
	_G.__inCombat = false
	fire("PLAYER_REGEN_ENABLED")
	check(not QT.collapsed, "an untouched fight restores whatever state it found")
end

do  -- turning a quest in should drop it from the tracked set
	local saved = _G.__questLog[2]
	table.remove(_G.__questLog, 2)
	QT:Refresh()
	check(A.db.char.tracked[861] == nil,
		"a quest that has left the log stops being tracked - the set cannot grow forever")
	table.insert(_G.__questLog, 2, saved)
	QT:Refresh()
end

A.db.profile.modules.questtracker.autoTrack = true
QT:Refresh()
check(#QT.quests == 4, "back in auto mode the whole log is tracked again")

print("== quest tracker: difficulty ==")
do
	-- player is level 15 in the mock; the log spans 15 to 18
	local byId = {}
	for _, q in ipairs(QT.quests) do byId[q.questID] = q end

	check(byId[861] and byId[861].difficulty, "quests carry a difficulty colour")
	check(byId[5041] and byId[5041].difficulty
		and byId[5041].difficulty[1] > byId[861].difficulty[3],
		"a level-18 quest reads redder than a level-15 one for a level-15 player")

	-- and it must move with the player, not be baked in at build time
	local before = QT.quests[1].difficulty
	_G.__units.player.level = 40
	QT:Refresh()
	local after = QT.quests[1].difficulty
	check(after[1] ~= before[1] or after[2] ~= before[2],
		"levelling up recolours the list - the same quest is grey now")
	_G.__units.player.level = 15
	QT:Refresh()

	local row = QT.panel.rows[1]
	check(row.level:IsShown() and row.level:GetText() == "[15]",
		"the level is shown in front of the title (got " .. tostring(row.level:GetText()) .. ")")

	-- a complete quest says so in words, not only in colour
	local complete
	for i, q in ipairs(QT.quests) do
		if q.complete then complete = q end
	end
	check(complete and complete.lines[#complete.lines].text == "Complete",
		"a complete quest gets a Complete line, so an objective-less one is not silent")
end

print("== options tree ==")
do
	local tree = A.Options:Build()
	check(type(tree) == "table" and tree.type == "group", "the tree builds")

	-- Walking it and checking every path is the whole reason Build() is pure.
	-- A typo in a path is otherwise a control that silently does nothing, and
	-- you find it a month later.
	local leaves, bad, kinds = 0, {}, {}
	local function walk(node, trail)
		for key, opt in pairs(node.args or {}) do
			local where = trail .. "." .. key
			if opt.type == "group" then
				walk(opt, where)
			elseif opt.arg and opt.arg.path then
				leaves = leaves + 1
				kinds[opt.type] = (kinds[opt.type] or 0) + 1
				local t, k = A.Options.Resolve(opt.arg.path)
				if not t then
					bad[#bad + 1] = where .. " (no table at " .. table.concat(opt.arg.path, ".") .. ")"
				elseif t[k] == nil then
					bad[#bad + 1] = where .. " -> " .. table.concat(opt.arg.path, ".") .. " is nil"
				end
			end
		end
	end
	walk(tree, "root")

	check(leaves > 50, "it has a real number of controls in it (" .. leaves .. ")")
	check(#bad == 0, "every control's path resolves to something that exists"
		.. (#bad > 0 and ("  -- " .. table.concat(bad, "; ")) or ""))
	check((kinds.toggle or 0) > 0 and (kinds.range or 0) > 0 and (kinds.select or 0) > 0,
		"toggles, ranges and selects all present")

	-- and the accessors round-trip through the real db
	local widthOpt = tree.args.unitframes.args.width
	local before = widthOpt.get({ arg = widthOpt.arg, type = "range" })
	check(before == A.db.profile.modules.unitframes.width, "get reads the live value")
	widthOpt.set({ arg = widthOpt.arg, type = "range" }, 360)
	check(A.db.profile.modules.unitframes.width == 360, "set writes it back")
	widthOpt.set({ arg = widthOpt.arg, type = "range" }, before)

	-- a nil-means-true toggle has to report true, or the checkbox lies
	local hb = tree.args.auras.args.hideBlizzard
	A.db.profile.modules.auras.hideBlizzard = nil
	check(hb.get({ arg = hb.arg, type = "toggle" }) == true,
		"a toggle that defaults to nil-means-true reports true, not nil")
	A.db.profile.modules.auras.hideBlizzard = true

	-- bar pages are generated from the config, so a bar added later gets controls
	local bars = tree.args.actionbars.args
	local pages = 0
	for k in pairs(bars) do if k:find("^bar") then pages = pages + 1 end end
	check(pages == #A.db.profile.modules.actionbars.bars,
		"one page per configured bar, generated rather than hard-coded (got "
		.. pages .. " for " .. #A.db.profile.modules.actionbars.bars .. " bars)")
	check(bars.barstance.args.page == nil,
		"a stance bar gets no page control - its buttons come from the game")
	check(bars.bar1.args.page ~= nil, "an action bar does")

	-- profiles go last, and that has to be a decision rather than a guess: the
	-- running order counter lands in the hundreds by the end of the tree
	local tops = {}
	for key, opt in pairs(tree.args) do
		if opt.type == "group" and opt.order then tops[key] = opt.order end
	end
	check(tops.general == 1, "General is the first page")
	local maxOther = 0
	for key, n in pairs(tops) do
		if key ~= "profiles" then maxOther = math.max(maxOther, n) end
	end
	check(A.Options.PAGE_ORDER.profiles > maxOther,
		"and profiles sorts after every other page (" .. A.Options.PAGE_ORDER.profiles
		.. " > " .. maxOther .. ")")

	-- registration degrades rather than erroring when Ace3 is absent
	check(A.Options:Register() == false,
		"Register reports false without the Ace libraries instead of throwing")
	SlashCmdList["AETHERUI"]("")
	check(true, "and bare /aether falls back to the command list")
end

print("== minimap ==")

local MMm = A:GetModule("minimap")
check(MMm and MMm.enabled, "minimap module enabled"
	.. (MMm and MMm.lastError and ("  -- " .. MMm.lastError) or ""))
check(MMm.frame and MMm.pill and MMm.drawer, "map holder, zone pill and drawer built")

do  -- Blizzard's Minimap is reshaped, not replaced: it cannot be recreated
	local cfg = A.db.profile.modules.minimap
	check(Minimap:GetParent() == MMm.frame,
		"the real Minimap is reparented into our holder rather than rebuilt")
	check(Minimap.__mask ~= nil, "and masked round")
	check(Minimap:GetWidth() == cfg.size, "sized from the config")
	-- Layering: an earlier version hung a soft ring off the holder as a plain
	-- BACKGROUND region meaning to put it behind the map, and a region draws at
	-- its own frame's strata - so it landed on top instead.
	check(MMm.frame.border ~= nil and MMm.frame.vignette == nil and MMm.frame.rim == nil,
		"the whole edge is one texture - a rim plus a separately-gated vignette"
		.. " was two draw orders and two switches, and the bug was in the seam"
		.. " between them every single time")
	check(MMm.frame.border:GetAlpha() == 1,
		"drawn at full alpha rather than behind a config value that could be 0")
	do
		-- Same hue as every pill's rim. The band survives the multiply because
		-- it is baked dark, which is why the tones are luminance and not colour.
		local r = select(1, MMm.frame.border:GetVertexColor())
		check(math.abs(r - A.Palette.c.glassEdge[1]) < 0.001,
			"and tinted with glassEdge, so the map's border and the zone pill"
			.. " under it are the same colour")
	end
	check(MMm.frame.top:GetFrameStrata() == "MEDIUM"
		and Minimap:GetFrameStrata() == "LOW",
		"and on a whole strata above the map, not merely a higher level - the"
		.. " Minimap is a widget the client renders into, and it does not"
		.. " composite against a sibling at its own strata")
	do
		local _, rel, _, x = MMm.frame.border:GetPoint(1)
		check(rel == MMm.frame and x < 0,
			"and drawn proud of the map, not flush with it - a mask edge is the"
			.. " client's to anti-alias and it stair-steps, so the border has to"
			.. " lap over it rather than stop short")
	end
	check(A.db.profile.modules.minimap.shadow == nil,
		"the old shadow key is migrated away - a profile carrying 0 from the"
		.. " version where it was off by default would hide the border")
	check(Minimap:GetFrameStrata() == "LOW",
		"with the map itself left in Blizzard's own band, where other addons"
		.. " expect to find it")
	check(MinimapCluster.__mouse == false,
		"the cluster's mouse is off - it is a rectangle much bigger than the map"
		.. " and it swallows clicks meant for what is behind it")
end

do  -- the furniture
	local r = MMm.hideReport
	check(r.MinimapBorder == "hidden" and r.MinimapZoomIn == "hidden"
		and r.MiniMapTracking == "hidden" and r.GameTimeFrame == "hidden",
		"the border, zoom, tracking and day/night dial are all banished")
	check(_G.MinimapZoomIn:GetParent() ~= MinimapCluster,
		"banished frames are reparented off the cluster, so another addon calling"
		.. " Show() on one cannot put it back")
	check(r.MiniMapWorldMapButton == nil,
		"MiniMapWorldMapButton is never touched - it is Wrath+ only and does not"
		.. " exist on this client")

	-- The named list is not the whole job: some of the art up there is an
	-- anonymous region with no global to put in a list, which is what left a
	-- border bar and a toggle tab sitting above the map first time round.
	check(not _G.__clusterArt:IsShown() and _G.__clusterArt:GetAlpha() == 0,
		"an unnamed region of the cluster is swept too")
	check(not _G.MinimapZoneTextButton:IsShown(),
		"and a named Blizzard child is banished whether it was listed or not")
	check(_G.SomeAddonOnTheCluster:IsShown(),
		"but an addon's own frame on the cluster is left exactly where it is -"
		.. " issecurevariable tells the two apart")
	check(r.MinimapBackdrop == "swept",
		"the backdrop is recursed into rather than carried off, so a third-party"
		.. " button parented there does not go with it")

	-- the two that were doing real work survive without any chrome
	_G.__minimapPinged, _G.__trackingMenu = nil, nil
	Minimap:GetScript("OnMouseWheel")(Minimap, 1)
	check(Minimap:GetZoom() == 1, "the wheel zooms in")
	Minimap:GetScript("OnMouseWheel")(Minimap, -1)
	check(Minimap:GetZoom() == 0, "and out")
	Minimap:GetScript("OnMouseUp")(Minimap, "RightButton")
	check(_G.__trackingMenu, "right-click opens the tracking menu the hidden"
		.. " button used to own")
	Minimap:GetScript("OnMouseUp")(Minimap, "LeftButton")
	check(_G.__minimapPinged, "and left-click still pings")
end

print("== the zone pill ==")
do
	local cfg = A.db.profile.modules.minimap
	MMm:UpdateZone()
	check(MMm.pill.zone:GetText() == "The Barrens", "zone named")
	check(MMm.pill.coords:GetText() == "45 · 58",
		"coordinates read out of C_Map (got " .. tostring(MMm.pill.coords:GetText()) .. ")")
	check(MMm.pill.clock:GetText() ~= "", "and the clock is in there too")

	-- Coordinates walk a digit at a time as you move and the clock ticks over
	-- every minute. Measured to their content, either one nudges the whole block
	-- sideways while you are standing still looking at it.
	do
		local before = MMm.pill:GetWidth()
		_G.__playerPos = { 0.07, 0.09 }        -- "7 . 9" - much narrower
		MMm:UpdateZone()
		check(MMm.pill:GetWidth() == before,
			"the block does not move when the coordinates change width")
		check(MMm.pill.coordW and MMm.pill.coordW > 0
			and MMm.pill.coordW < MMm.pill:GetWidth(),
			"and the fixed field is *measured* from the font rather than guessed"
			.. " - the guess was half again too wide and pushed the block off the"
			.. " side of the screen (" .. tostring(MMm.pill.coordW) .. ")")
		_G.__playerPos = { 0.45, 0.58 }
		MMm:UpdateZone()
	end
	check(not MMm.pill.dot:IsShown(), "no combat dot out of combat")

	-- tinted by zone type, the same colours the rest of the game uses
	_G.__pvpType = "contested"
	MMm:UpdateZone()
	local r = select(1, MMm.pill.zone:GetTextColor())
	check(math.abs(r - 1.0) < 0.01, "a contested zone is tinted")
	_G.__pvpType = nil

	-- an instance has a map but no position on it, which is a different nil
	-- from having no map at all - both have to mean "no coordinates"
	_G.__playerPos = nil
	MMm:UpdateZone()
	check(MMm.pill.coords:GetText() == "",
		"an instance drops the coordinates rather than showing nils")
	_G.__playerPos = { 0.45, 0.58 }
	_G.__uiMap = nil
	MMm:UpdateZone()
	check(MMm.pill.coords:GetText() == "", "and so does having no map at all")
	_G.__uiMap = 1413

	-- in combat the pill says so
	_G.__inCombat = true
	MMm:UpdateZone()
	check(MMm.pill.dot:IsShown() and MMm.pill.zone:GetText() == "In combat",
		"in a fight the pill swaps for a dot and 'In combat'")
	check(select(2, MMm.pill.zone:GetPoint(1)) == MMm.pill.dot,
		"and the label moves out of the dot's way - both were anchored 14 in from"
		.. " the same edge, so the dot was drawn on top of the first word")
	check(MMm.pill.clock:GetText() ~= "", "the clock stays either way")
	check(MMm.pill.coords:GetWidth() == 0,
		"and the empty coordinate field collapses - a fixed-width field with"
		.. " nothing in it still takes up its width in the anchor chain, which"
		.. " pushed the clock out past the end of the pill")
	_G.__inCombat = false
	MMm:UpdateZone()
	check(MMm.pill.zone:GetText() == "The Barrens", "and comes back afterwards")
end

print("== mail ==")
do
	_G.__mail = false
	MMm:UpdateMail()
	check(MMm.mail:GetAlpha() == 0, "no mail, no pill")
	_G.__mail = true
	fire("UPDATE_PENDING_MAIL")
	check(MMm.mail:GetAlpha() == 1, "unread mail puts the pill up")
	check(select(2, MMm.mail:GetPoint(1)) == MMm.pill,
		"beside the zone block, not on the map")
	-- The map's default home is the top right of the screen, so a pill hung off
	-- the block's right edge is a pill hung off the screen.
	MMm.frame:SetGeom({ cx = 880, cy = 600, left = 800, right = 960,
		bottom = 520, top = 680 })
	MMm._mailLeft = nil
	MMm:AnchorMail()
	local mp, _, mrel = MMm.mail:GetPoint(1)
	check(mp == "RIGHT" and mrel == "LEFT",
		"and on the inboard side - with the map top right the pill goes to the"
		.. " left of the block, where there is room for it (got "
		.. tostring(mp) .. " -> " .. tostring(mrel) .. ")")

	MMm.frame:SetGeom({ cx = 120, cy = 600, left = 40, right = 200,
		bottom = 520, top = 680 })
	MMm:AnchorMail()
	check(select(1, MMm.mail:GetPoint(1)) == "LEFT",
		"drag the map to the other side of the screen and it flips")
	MMm.frame.__geom = nil
	-- Alpha rather than Show: this flips mid-fight and there is no reason to
	-- have that argument with the client.
	_G.__inCombat = true
	_G.__mail = false
	fire("UPDATE_PENDING_MAIL")
	check(MMm.mail:GetAlpha() == 0, "and drops it again mid-combat without a"
		.. " blocked call")
	_G.__inCombat = false
end

print("== the button drawer ==")
do
	local cfg = A.db.profile.modules.minimap

	-- three arrivals: one through LibDBIcon's registry, one addon rolling its
	-- own button, and one map pin that must be left where it is
	local dbi = _G.__makeDBIcon("BigWigs")
	local own = CreateFrame("Button", "SomeAddonMinimapButton", Minimap)
	local pin = CreateFrame("Button", "QuestieMinimapPin42", Minimap)
	MMm:Scan()

	check(MMm.buttons[dbi], "a LibDBIcon button is collected")
	check(MMm.buttons[own], "and so is an addon that rolled its own")
	check(not MMm.buttons[pin],
		"but a map pin is not - it is not a button, and there can be thousands")
	check(not MMm.buttons[_G.MinimapZoomIn],
		"and neither is Blizzard's own furniture, which issecurevariable sorts"
		.. " out without a list to keep up to date")

	check(dbi.__locked, "LibDBIcon buttons are Locked through the library, which"
		.. " is what stops its drag handler yanking them back onto the ring")
	check(own:GetScript("OnDragStart") == nil,
		"and a hand-rolled one has its drag handlers taken off")
	check(dbi:GetParent() == MMm.drawer.tray, "collected buttons live in the drawer")
	MMm:LayoutDrawer()
	check(dbi:GetFrameStrata() == MMm.drawer:GetFrameStrata(),
		"and are brought up to the drawer's strata - LibDBIcon pins its buttons"
		.. " with SetFixedFrameStrata, so ours was refused and the drawer's own"
		.. " panel art was painted over the top of them (" .. dbi:GetFrameStrata() .. ")")
	check(dbi.__aetherRing ~= nil and dbi.__aetherSkinned,
		"and are skinned to match the rest of the UI - icon masked to a circle,"
		.. " our ring around it")
	check(dbi.border == nil or not dbi.border:IsShown(),
		"with whatever bevel they arrived with switched off")
	do
		-- The rule is "keep the icon, hide every other texture", not "match the
		-- bevel against a list of known files" - an addon's border is whatever
		-- file that addon shipped, and no list covers that.
		local kept, hidden = 0, 0
		for _, r in ipairs(dbi.__regions or {}) do
			if r == dbi.__aetherIcon then kept = kept + 1
			elseif r ~= dbi.__aetherRing and not r:IsShown() then hidden = hidden + 1 end
		end
		check(kept == 1 and hidden >= 2,
			("the icon is kept and everything else is hidden (%d kept, %d hidden)")
				:format(kept, hidden))
	end
	MMm:LayoutDrawer()
	do
		-- Each button gets its own column. They arrive owning a frame level -
		-- LibDBIcon pins its own at 8 - and one sitting below the drawer's panel
		-- art is drawn over and cannot be clicked.
		local seen, clash = {}, nil
		for _, b in ipairs(MMm.buttonOrder) do
			if b:IsShown() then
				local _, _, _, x = b:GetPoint(1)
				if seen[x] then clash = x end
				seen[x] = true
				if b:GetFrameLevel() <= MMm.drawer.tray:GetFrameLevel() then clash = -1 end
			end
		end
		check(clash == nil,
			"every collected button gets its own column and a frame level above"
			.. " the drawer's own art (clash at " .. tostring(clash) .. ")")
	end

	-- a button created later still gets picked up
	local late = _G.__makeDBIcon("Later")
	check(MMm.buttons[late],
		"a button created after the sweep arrives through LibDBIcon's callback -"
		.. " there is no event for 'a child was added to the minimap'")

	-- the drawer itself
	-- A drawer with no handle is a drawer nobody opens.
	check(MMm.pill.hint:IsShown(),
		"the zone pill shows a chevron once there is something in the drawer")
	check(MMm.drawer:GetAlpha() == 0, "the drawer is closed to start with")
	MMm.pill:GetScript("OnEnter")(MMm.pill)
	check(MMm.drawer.open, "hovering the zone pill opens it")
	check(select(3, MMm.pill.hint:GetTexCoord()) == 1,
		"and the chevron turns over while it is open")
	MMm:SetDrawerOpen(true, true)
	check(MMm.drawer:GetAlpha() == 1, "and it fades up")
	check(MMm.drawer:GetWidth() > cfg.buttonSize, "sized to what is in it")

	-- travelling from the pill to the drawer must not close it on the way
	MMm.pill:GetScript("OnLeave")(MMm.pill)
	MMm:CheckHover()
	check(MMm.drawer.open,
		"leaving the pill does not shut it immediately - there is a gap to cross")
	MMm._hoverUntil = 0
	MMm:CheckHover()
	check(not MMm.drawer.open, "but it does close once the cursor is gone")

	-- Alpha and mouse, never Show/Hide: a collected button belongs to another
	-- addon and may carry a secure template, and hovering a pill is exactly the
	-- sort of thing you do mid-fight.
	_G.__inCombat = true
	MMm:TouchDrawer()
	MMm:SetDrawerOpen(true, true)
	MMm:SetDrawerOpen(false, true)
	check(MMm.drawer:GetAlpha() == 0 and MMm.drawer:IsShown(),
		"opening and closing in combat never hides a frame - alpha and mouse only")
	_G.__inCombat = false

	-- a button that hides itself drops out of the layout
	local before = MMm.drawer:GetWidth()
	own:Hide()
	MMm:LayoutDrawer()
	check(MMm.drawer:GetWidth() <= before, "a hidden button leaves the layout")
	do
		local saved = MMm.buttonOrder
		MMm.buttonOrder = {}
		MMm:LayoutDrawer()
		check(not MMm.pill.hint:IsShown(),
			"and with nothing left in it the chevron goes too - it is a promise"
			.. " that there is something behind it")
		MMm.buttonOrder = saved
		MMm:LayoutDrawer()
	end
	own:Show()
	MMm:LayoutDrawer()
end

print("== xp hairline ==")
local XPm = A:GetModule("xpbar")
check(XPm and XPm.enabled and XPm.frame, "xpbar module built")
check(XPm.frame:IsShown(), "xp bar visible below max level")
check(XPm.frame.text:GetText() == "86%  ·  Level 15", "xp readout matches the concept's wording")
check(XPm.frame.rested:IsShown(), "rested overlay shown when rest is banked")
_G.__units.player.level = 60
fire("PLAYER_LEVEL_UP")
check(not XPm.frame:IsShown(), "xp bar hides at max level")
_G.__units.player.level = 15
fire("PLAYER_LEVEL_UP")

print("== combat gating ==")
_G.__inCombat = true
A.db.profile.scale = 1.0
AB:OnConfigChanged()
check(AB._layoutPending, "layout changes are deferred while in combat")
AB:ApplyBindings()
check(AB._bindingsPending, "rebinding is deferred while in combat")
_G.__inCombat = false
fire("PLAYER_REGEN_ENABLED")
check(not AB._layoutPending and not AB._bindingsPending,
	"deferred work replays when combat ends")
check(_G.__overrides["1"] == "AetherUIBar1Button1", "bindings survive the replay")

print("== blizzard buttons stay silenced ==")
do
	-- The dock showed page 1 while the key fired page 6, because Blizzard's own
	-- ActionButton2 was still alive underneath and still reading the live page.
	AB:HideBlizzard()
	local b = _G.ActionButton2
	check(b ~= nil, "Blizzard's ActionButton2 exists in the mock")
	check(b:GetAttribute("statehidden") == true,
		"it is marked statehidden, so Blizzard's own visibility drivers leave it down")
	check(not b:IsShown(), "and it is hidden")
	check(next(b.__events) == nil, "and deaf")

	check(AB.hideReport["<blizzard buttons>"] ~= nil,
		"the button sweep is reported in /aether diag")
	check(_G.__clearedOverrides.MainActionBar,
		"Blizzard's bar has its override bindings cleared - the modern bar code"
		.. " re-points the ACTIONBUTTON keys at its own buttons, and last writer wins")

	check(GetBindingAction("1", true):find("AetherUI", 1, true) ~= nil,
		"and key 1 resolves to our button, not theirs (got "
		.. GetBindingAction("1", true) .. ")")
end

print("== shift-drag picks up instead of casting ==")
do
	-- RegisterForClicks("AnyDown") fires the click on mouse-down, which lands
	-- before a drag can start - so shift-dragging an action cast it. The secure
	-- handler consults `shift-type1` before `type`, and an empty string there is
	-- a click with nothing to do, which leaves the drag alone.
	local b = bar.buttons[1]
	check(b:GetAttribute("shift-type1") == "",
		"the pickup modifier's click is neutered on our buttons")
	check(b:GetAttribute("type") == "action",
		"and the unmodified click still casts")
	check(b:GetAttribute("ctrl-type1") == nil and b:GetAttribute("alt-type1") == nil,
		"only the one modifier is touched")

	-- Which modifier is the player's business, not ours.
	_G.__modifiedClick.PICKUPACTION = "CTRL"
	fire("UPDATE_BINDINGS")
	check(b:GetAttribute("ctrl-type1") == "" and b:GetAttribute("shift-type1") == nil,
		"changing PICKUPACTION in Blizzard's settings moves it, and clears the old one")

	_G.__modifiedClick.PICKUPACTION = "NONE"
	fire("UPDATE_BINDINGS")
	check(b:GetAttribute("ctrl-type1") == nil,
		"'none' leaves every modified click alone")

	_G.__modifiedClick.PICKUPACTION = "SHIFT"
	fire("UPDATE_BINDINGS")
end

print("== keybind mode ==")
do
	AB:SetBindMode(true)
	check(AB.bindMode == true, "bind mode on")
	local o = AB.bindOverlays and AB.bindOverlays[1]
	check(o ~= nil and o:IsShown(), "every button gets an overlay you can hover")
	check(o.bindingName == "ACTIONBUTTON1",
		"bar 1 binds through Blizzard's own ACTIONBUTTON names (" ..
		tostring(o.bindingName) .. ")")

	-- Bar 2 is the one action page Blizzard never named a binding for, which is
	-- why Bindings.xml declares one. Without it the bar is unreachable by key.
	local bar2
	A.Config:Module("actionbars").bars[2].enabled = true
	AB:SyncBars()
	AB:SetBindMode(true)
	for _, x in ipairs(AB.bars) do if x.id == "2" then bar2 = x end end
	local name2
	for _, ov in ipairs(AB.bindOverlays or {}) do
		if ov:IsShown() and bar2 and ov.button == bar2.buttons[1] then name2 = ov.bindingName end
	end
	check(name2 == "AETHERUI_BAR2BUTTON1",
		"bar 2 uses our own declared binding header (" .. tostring(name2) .. ")")
	A.Config:Module("actionbars").bars[2].enabled = false
	AB:SyncBars()
	AB:SetBindMode(true)

	-- A key press goes into Blizzard's account binding set, not our saved
	-- variables, so it survives the addon being turned off.
	_G.__shift = true
	o:GetScript("OnKeyDown")(o, "F")
	_G.__shift = false
	check(_G.__bindingSet.ACTIONBUTTON1 == "SHIFT-F",
		"the pressed key, with its modifiers, lands on the binding (" ..
		tostring(_G.__bindingSet.ACTIONBUTTON1) .. ")")
	check(_G.__savedBindingSet == 1, "and the binding set is saved, not left dirty")
	check(_G.__overrides["SHIFT-F"] == "AetherUIBar1Button1",
		"the override binding follows immediately, without a reload")
	check(o.text:GetText() == "SF", "the overlay shows the new key back")

	-- The bug that made bind mode look broken on bars 3-6: the press reached our
	-- handler *and* went on to the binding system, so binding ctrl-1 also fired
	-- whatever ctrl-1 already did. Propagation is reset by the client for every
	-- keyboard event, so it has to be turned off inside the handler dealing with
	-- the press - not once on OnEnter.
	-- LSHIFT on purpose: it binds nothing, so this asserts the swallow happens
	-- for *every* press rather than only the ones we act on.
	o.__propagate = true
	o:GetScript("OnKeyDown")(o, "LSHIFT")
	check(o.__propagate == false,
		"the handler itself swallows the press rather than relying on OnEnter")
	o.__propagate = true
	o:GetScript("OnKeyUp")(o)
	check(o.__propagate == false, "and the key-up half of the same press too")

	-- Modifier keys on their own are not bindings.
	o:GetScript("OnKeyDown")(o, "LSHIFT")
	check(_G.__bindingSet.ACTIONBUTTON1 == "SHIFT-F",
		"pressing shift by itself does not bind shift")

	-- Taking a key that something else owns takes it, rather than leaving two
	-- owners and letting the client choose.
	local o2 = AB.bindOverlays[2]
	o2:GetScript("OnKeyDown")(o2, "F")
	check(_G.__bindingSet.ACTIONBUTTON1 == "SHIFT-F"
		and _G.__bindingSet.ACTIONBUTTON2 == "F",
		"a plain F and a shift-F are different keys and coexist")

	o:GetScript("OnMouseWheel")(o, 1)
	check(_G.__bindingSet.ACTIONBUTTON1 == "MOUSEWHEELUP",
		"the wheel is a key too")

	o:GetScript("OnKeyDown")(o, "ESCAPE")
	check(_G.__bindingSet.ACTIONBUTTON1 == nil, "escape clears the binding")
	check(o.text:GetText() == "?", "and the overlay says so")

	-- Right-click leaves, and combat refuses.
	o:GetScript("OnMouseDown")(o, "RightButton")
	check(AB.bindMode == false, "right-click leaves bind mode")
	check(not AB.bindOverlays[1]:IsShown(), "and the overlays go away")

	_G.__inCombat = true
	AB:SetBindMode(true)
	check(AB.bindMode == false, "bind mode refuses to open in combat")
	_G.__inCombat = false

	-- Bind mode opens from a slash command or the options panel, so the cursor is
	-- wherever it already was. Over a button, no OnEnter ever fires and that
	-- overlay never takes keyboard focus - which is the "I had to hover off and
	-- back on before it would take" report.
	AB.bindOverlays[1].__mouseOver = true
	AB:SetBindMode(true)
	check(AB.bindOverlays[1].__propagate == false,
		"an overlay already under the cursor when bind mode opens is given focus"
		.. " without waiting for the mouse to move")
	AB.bindOverlays[1].__mouseOver = nil
	AB:SetBindMode(false)

	SetBinding("1", "ACTIONBUTTON1")
	AB:ApplyBindings()
end

print("== unlock grid and snapping ==")
do
	local M = A.Movers
	M:Unlock()

	local g = _G.AetherUIMoverGrid
	check(g ~= nil and g:IsShown(), "the grid appears with the handles")
	check(#g.lines > 0, "and has lines in it")

	A.db.profile.movers.grid = false
	M:RefreshGrid()
	check(not g:IsShown(), "turning it off hides it without locking first")
	A.db.profile.movers.grid = true
	M:RefreshGrid()
	check(g:IsShown(), "and back on again")

	-- A controlled screen: one frame being dragged, one frame to catch on. The
	-- real registry has a dozen entries whose edges would make "did it snap to
	-- the thing I meant" unanswerable.
	UIParent:SetSize(1000, 600)
	UIParent.__scale = 1

	local entry = M.registry.quests
	check(entry ~= nil, "the quest tracker registers a mover")
	local f, h = entry.frame, entry.handle
	f.__scale = 0.5                      -- so frame space is 2x UIParent's
	f:SetSize(200, 100)                  -- 100 x 50 in UIParent units

	local target = CreateFrame("Frame", "AetherUISnapTarget", UIParent)
	target.__scale = 1
	target:SetGeom({ cx = 550, cy = 275, left = 400, right = 700, bottom = 200, top = 350 })

	local saved = M.registry
	M.registry = { quests = entry, __t = { name = "__t", frame = target } }
	A.db.profile.movers.gridSize = 20
	A.db.profile.movers.snapDistance = 12

	-- Everything below is expressed in UIParent units and converted at the
	-- boundary, exactly as the mover does. GetPoint hands back what was written,
	-- in the frame's own space, so the expected value carries the /fs.
	local function place(uiLeft, uiBottom)
		f:SetGeom({ cx = uiLeft * 2 + 100, cy = uiBottom * 2 + 50,
			left = uiLeft * 2, right = uiLeft * 2 + 200,
			bottom = uiBottom * 2, top = uiBottom * 2 + 100 })
	end
	local function droppedX()
		local _, _, _, x = f:GetPoint(1)
		return x * 0.5                    -- frame space -> UIParent units
	end

	cursorX, cursorY = 500, 500

	-- five pixels short of the target's left edge, which is as close as anyone
	-- gets with a mouse
	place(405, 100)
	h:GetScript("OnDragStart")(h)
	check(h:GetScript("OnUpdate") ~= nil, "dragging tracks the cursor by hand"
		.. " - StartMoving owns the position and cannot be nudged mid-drag")
	h:GetScript("OnUpdate")(h)
	check(math.abs(droppedX() - 400) < 0.01,
		("a near-miss lands on the other frame's edge (405 -> %.1f, wanted 400)")
			:format(droppedX()))

	-- our right edge against theirs, from the other side
	place(295, 100)                      -- right edge at 395, theirs at 400
	h:GetScript("OnDragStart")(h)
	h:GetScript("OnUpdate")(h)
	check(math.abs(droppedX() - 300) < 0.01,
		("the frame's own right edge counts too (%.1f)"):format(droppedX()))

	place(405, 100)
	h:GetScript("OnDragStart")(h)
	_G.__alt = true
	h:GetScript("OnUpdate")(h)
	_G.__alt = false
	check(math.abs(droppedX() - 405) < 0.01,
		("holding alt places it exactly where the cursor says (%.1f)"):format(droppedX()))

	-- Far from anything, the grid is what is left.
	place(803, 100)
	h:GetScript("OnDragStart")(h)
	h:GetScript("OnUpdate")(h)
	check(math.abs(droppedX() - 800) < 0.01,
		("with nothing near, the grid catches it (803 -> %.1f)"):format(droppedX()))

	-- ...but another frame always outranks it: 405 is 5 from the frame edge and
	-- 5 from the grid line at 400 too, so this only proves the order if the grid
	-- is somewhere else entirely.
	A.db.profile.movers.gridSize = 26
	place(405, 100)
	h:GetScript("OnDragStart")(h)
	h:GetScript("OnUpdate")(h)
	check(math.abs(droppedX() - 400) < 0.01,
		("a frame edge beats a nearer grid line (%.1f)"):format(droppedX()))
	A.db.profile.movers.gridSize = 20

	A.db.profile.movers.snap = false
	place(803, 100)
	h:GetScript("OnDragStart")(h)
	h:GetScript("OnUpdate")(h)
	check(math.abs(droppedX() - 803) < 0.01,
		("snapping off means nothing is caught at all (%.1f)"):format(droppedX()))
	A.db.profile.movers.snap = true

	h:GetScript("OnDragStop")(h)
	check(h:GetScript("OnUpdate") == nil, "and the tracker stops when you let go")

	M.registry = saved
	f.__geom, f.__scale = nil, 1
	M:Lock()
	check(not g:IsShown(), "the grid goes away with the handles")

	-- A snap on one axis only leaves the other guide's slot nil, and `ipairs`
	-- stops at the hole - so the line that was actually drawn was the one that
	-- never got hidden, and it stayed lying across the screen after locking.
	A.Movers:Unlock()
	A.Movers.__test_resetGuides()
	A.Movers.__test_drawGuide(2, false, 400)
	check(A.Movers.__test_guideShown(2), "a horizontal snap guide is drawn")
	A.Movers:Lock()
	check(not A.Movers.__test_guideShown(2),
		"and it is cleared on lock even though no vertical guide was ever made -"
		.. " the case ipairs skipped")
	A:Reconfigure()
end

print("")
if #FAIL == 0 then
	print("ALL CHECKS PASSED")
else
	print(#FAIL .. " FAILURE(S):")
	for _, m in ipairs(FAIL) do print("  - " .. m) end
	os.exit(1)
end
