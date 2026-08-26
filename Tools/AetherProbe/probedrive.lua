--[[--------------------------------------------------------------------------
	Drive AetherProbe against a small mock, because "it parses" is not "it runs".

	The probe walks frames it has never seen and asks each region for methods
	that only some object types have - GetText on a Texture, GetAtlas on a
	FontString. Every one of those is wrapped in pcall, and a pcall that is
	wrapping the WRONG line still reports success. This loads the file for real,
	fires the events it listens for, and then INSPECTS WHAT IT WROTE: an empty
	table is the failure mode a pcall cannot show you.

		luajit probedrive.lua
----------------------------------------------------------------------------]]

local fails = 0
local function check(cond, msg)
	if cond then print("  ok  " .. msg)
	else fails = fails + 1 print("  !!  " .. msg) end
end

-- --------------------------------------------------------------------------
-- a client, roughly
-- --------------------------------------------------------------------------

local frames = {}
-- EVERY widget, named or not. The probe's own event frame is created with no
-- name and no parent, so neither _G nor UIParent's child list can find it.
local created = {}

local function widget(kind, name, parent)
	local o = {
		__kind = kind, __name = name, __parent = parent,
		__shown = true, __w = 0, __h = 0,
		__points = {}, __kids = {}, __regions = {}, __scripts = {},
	}
	function o:GetObjectType() return self.__kind end
	function o:GetName() return self.__name end
	function o:IsShown() return self.__shown end
	function o:Show() self.__shown = true
		local s = self.__scripts.OnShow if s then s(self) end end
	function o:Hide() self.__shown = false end
	function o:GetSize() return self.__w, self.__h end
	function o:SetSize(w, h) self.__w, self.__h = w, h end
	function o:SetHeight(h) self.__h = h end
	function o:SetWidth(w) self.__w = w end
	function o:GetNumPoints() return #self.__points end
	function o:GetPoint(i)
		local p = self.__points[i]
		if p then return p[1], p[2], p[3], p[4], p[5] end
	end
	function o:SetPoint(p, rel, rp, x, y)
		self.__points[#self.__points + 1] = { p, rel, rp, x or 0, y or 0 }
	end
	function o:GetChildren() return unpack(self.__kids) end
	function o:GetRegions() return unpack(self.__regions) end
	function o:GetParent() return self.__parent end
	function o:IsProtected() return self.__protected or false end
	function o:RegisterEvent(e) self.__events = self.__events or {}
		self.__events[e] = true end
	function o:UnregisterAllEvents() self.__events = {} end
	function o:SetScript(n, fn) self.__scripts[n] = fn end
	function o:GetScript(n) return self.__scripts[n] end
	function o:HookScript(n, fn)
		local prev = self.__scripts[n]
		self.__scripts[n] = function(...) if prev then prev(...) end fn(...) end
	end
	created[#created + 1] = o
	if parent and parent.__kids then parent.__kids[#parent.__kids + 1] = o end
	if name then _G[name] = o frames[name] = o end
	return o
end

function CreateFrame(kind, name, parent, template)
	return widget(kind, name, parent)
end

UIParent = widget("Frame", "UIParent", nil)

--- A window shaped roughly like one of Blizzard's: a title, a close button, a
--  backdrop texture and a pane. Enough for describe() to walk.
local function window(name)
	local f = widget("Frame", name, UIParent)
	f:SetSize(384, 512)
	f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -104)

	local title = widget("FontString", name .. "TitleText", f)
	function title:GetText() return name .. " title" end
	function title:GetFont() return "Fonts\\FRIZQT__.TTF", 12 end
	title:SetSize(200, 14)
	title:SetPoint("TOP", f, "TOP", 0, -18)
	f.__regions[#f.__regions + 1] = title

	local bg = widget("Texture", name .. "Bg", f)
	function bg:GetTexture() return 130834 end
	function bg:GetAtlas() return nil end
	bg:SetSize(384, 512)
	f.__regions[#f.__regions + 1] = bg

	-- A region that answers NOTHING it is asked, which is the shape the probe
	-- has to survive: a forbidden or stripped region on a live client.
	local awkward = widget("Texture", nil, f)
	awkward.GetTexture = nil
	awkward.GetAtlas = nil
	f.__regions[#f.__regions + 1] = awkward

	local close = widget("Button", name .. "CloseButton", f)
	close:SetSize(32, 32)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
	return f
end

-- --------------------------------------------------------------------------
-- the rest of the client surface the probe touches
-- --------------------------------------------------------------------------

DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("      | " .. m) end }
SlashCmdList = {}
C_Timer = { After = function(_, fn) fn() end }

local now = 1000
function GetTime() return now end
function GetBuildInfo() return "5.5.0", "69497", "2026-08-20", 50504 end
function GetLocale() return "enGB" end
function GetMaxPlayerLevel() return 90 end
function UnitLevel() return 90 end
function UnitClass() return "Monk", "MONK" end
function InCombatLockdown() return _G.__combat or false end
function GetZoneText() return "Valley of the Four Winds" end
function GetSubZoneText() return "Halfhill" end
function NumTaxiNodes() return 3 end
function TaxiNodeGetType(i) return i == 2 and "CURRENT" or "REACHABLE" end
function TaxiNodeName(i) return "Node " .. i end

WOW_PROJECT_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 2, 19
WOW_PROJECT_ID = WOW_PROJECT_MISTS_CLASSIC
MAX_PLAYER_LEVEL, NUM_BAG_SLOTS, NUM_BANKBAGSLOTS = 90, 4, 7

local ADDONS = {
	{ "Blizzard_TalentUI", true }, { "Blizzard_TradeSkillUI", false },
	{ "Blizzard_AchievementUI", false }, { "AetherUI", true },
}
C_AddOns = {
	GetNumAddOns = function() return #ADDONS end,
	GetAddOnInfo = function(i) return ADDONS[i] and ADDONS[i][1] end,
	IsAddOnLoaded = function(i) return ADDONS[i] and ADDONS[i][2] end,
}

-- The windows the probe will find. Deliberately a MIXTURE: some present, most
-- absent, because "absent" is the answer the record has to be able to carry.
for _, n in ipairs({ "CharacterFrame", "SpellBookFrame", "MerchantFrame",
	"WatchFrame", "PlayerFrame", "TaxiFrame", "PVEFrame" }) do window(n) end
UnitCastingInfo = function() end
GetQuestLogTitle = function() end

-- --------------------------------------------------------------------------

print("== loading the probe ==")
local chunk, err = loadfile("Tools/AetherProbe/AetherProbe.lua")
if not chunk then print("  !!  " .. tostring(err)) os.exit(1) end
local ok, e = pcall(chunk, "AetherProbe")
check(ok, "the file loads" .. (ok and "" or (": " .. tostring(e))))
if not ok then os.exit(1) end

-- The probe's own event frame: the only one here that listens for login.
local pump
for _, f in ipairs(created) do
	if f.__events and f.__events.PLAYER_LOGIN then pump = f break end
end

print("== login ==")
check(pump ~= nil, "the probe built an event frame that listens for login")
if not pump then os.exit(1) end
local fire = pump:GetScript("OnEvent")
ok, e = pcall(fire, pump, "PLAYER_LOGIN")
check(ok, "PLAYER_LOGIN runs clean" .. (ok and "" or (": " .. tostring(e))))

check(AetherProbeDB.client ~= nil, "it recorded the client")
check(AetherProbeDB.client.interface == 50504, "with the interface number (50504)")
check(AetherProbeDB.client.projectIsMists == true, "and it knows this is Mists")
check(AetherProbeDB.client.maxLevel == 90, "and the level cap (90)")

local present, absent = 0, 0
for _, v in pairs(AetherProbeDB.names or {}) do
	if v == "absent" then absent = absent + 1 else present = present + 1 end
end
check(present > 0 and absent > 0,
	("names recorded both ways - %d present, %d absent"):format(present, absent))
check(AetherProbeDB.names.WatchFrame == "Frame",
	"a frame that exists is recorded by its OBJECT TYPE, not just `true`")
check(AetherProbeDB.names.QuestWatchFrame == "absent",
	"and one that does not is recorded as absent rather than left out")
check(AetherProbeDB.names.GetQuestLogTitle == "function",
	"a function is recorded as a function")
check(AetherProbeDB.blizzardAddOns.Blizzard_TradeSkillUI == "on demand",
	"a load-on-demand Blizzard addon is listed as such")

print("== opening a window ==")
CharacterFrame:Show()
local shape = AetherProbeDB.windows and AetherProbeDB.windows.CharacterFrame
check(shape ~= nil, "opening a window records its shape")
if shape then
	check(shape.w == 384 and shape.h == 512, "with its size (384x512)")
	check(shape.points and shape.points[1]:find("TOPLEFT"), "and its anchor")
	local title, tex, awkward
	for _, r in ipairs(shape.regions or {}) do
		if r.kind == "FontString" then title = r end
		if r.kind == "Texture" and r.texture then tex = r end
		if r.kind == "Texture" and not r.texture then awkward = r end
	end
	check(title and title.text == "CharacterFrame title",
		"the title string, with its text")
	check(title and title.font and title.font:find("FRIZQT"),
		"and the font it is set in")
	check(tex and tex.texture == 130834,
		"a texture's path, which comes back as a FILE ID on this client")
	check(awkward ~= nil,
		"and a region that answers nothing is still recorded rather than"
		.. " taking the walk down with it")
	local close
	for _, k in ipairs(shape.children or {}) do
		if k.name == "CharacterFrameCloseButton" then close = k end
	end
	check(close ~= nil, "children are walked too")
end

print("== a second show does not re-record ==")
local before = AetherProbeDB.windows.CharacterFrame
CharacterFrame:Hide() CharacterFrame:Show()
check(AetherProbeDB.windows.CharacterFrame == before,
	"the shape is taken once, on first open")

print("== a flight ==")
pcall(fire, pump, "PLAYER_CONTROL_LOST")
now = now + 212.5
pcall(fire, pump, "PLAYER_CONTROL_GAINED")
check(AetherProbeDB.flights and #AetherProbeDB.flights == 1, "a flight is timed")
if AetherProbeDB.flights and AetherProbeDB.flights[1] then
	local fl = AetherProbeDB.flights[1]
	check(fl.seconds == 212.5, "to a tenth of a second (" .. tostring(fl.seconds) .. ")")
	check(fl.from == "Node 2", "from the node marked CURRENT")
	check(fl.to == "Halfhill", "to where you landed")
end

print("== a taxi that was cancelled is not a flight ==")
pcall(fire, pump, "PLAYER_CONTROL_LOST")
now = now + 3
pcall(fire, pump, "PLAYER_CONTROL_GAINED")
check(#AetherProbeDB.flights == 1, "three seconds is a dismount, not a journey")

print("== protection ==")
_G.__combat = true
ok, e = pcall(fire, pump, "PLAYER_REGEN_DISABLED")
check(ok, "the combat experiment runs" .. (ok and "" or (": " .. tostring(e))))
check(AetherProbeDB.protection and AetherProbeDB.protection.inCombat,
	"and records what happened in combat")
check(AetherProbeDB.protection.outOfCombat,
	"with the out-of-combat control alongside it")
_G.__combat = false

print("== blocked calls ==")
pcall(fire, pump, "ADDON_ACTION_BLOCKED", "SomeAddon", "SetPoint()")
pcall(fire, pump, "ADDON_ACTION_BLOCKED", "SomeAddon", "SetPoint()")
check(AetherProbeDB.blocked
	and AetherProbeDB.blocked["SomeAddon :: SetPoint()"] == 2,
	"a blocked call is counted, and counted per addon and function")

print("== /aprobe ==")
ok, e = pcall(SlashCmdList.AETHERPROBE, "")
check(ok, "the summary runs" .. (ok and "" or (": " .. tostring(e))))
ok = pcall(SlashCmdList.AETHERPROBE, "dump SpellBookFrame")
check(ok and AetherProbeDB.windows.SpellBookFrame ~= nil,
	"and dumps a window on demand")
ok = pcall(SlashCmdList.AETHERPROBE, "dump NoSuchFrame")
check(ok, "and says so for a frame that is not here rather than erroring")

print("")
if fails == 0 then print("ALL CHECKS PASSED")
else print(fails .. " FAILED") os.exit(1) end
