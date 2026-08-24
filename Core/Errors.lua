--[[--------------------------------------------------------------------------
	AetherUI :: Errors

	The last few Lua errors, in a box you can select and copy out of.

	WoW's chat frame cannot be selected. Not a setting - the client simply does
	not allow it, so an error you can read is still an error you cannot send to
	anybody. An EditBox CAN be selected, so the text goes in one of those and
	Ctrl+A, Ctrl+C does the rest.

	CHAINED, NEVER REPLACED
	-----------------------
	Something was almost certainly the error handler before we were: the client's
	own, or BugSack, or whatever the player installed to do exactly this job
	better. Ours records and then hands the error straight on. Swallowing it
	would make every other tool on the machine blind, and the one thing worse
	than an error you cannot copy is an error nothing reports at all.

	And our handler must never raise. It runs INSIDE the client's error path, so
	an error thrown here arrives back at the handler that threw it - which is a
	loop the client does not break for you. Recording is wrapped accordingly.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local Errors = {}
A.Errors = Errors

local W, Palette = A.Widgets, A.Palette

--- How many to keep. Enough to catch a cascade - the first error is usually the
--  real one and the rest are its wreckage - without holding a session's worth.
local MAX = 12

local log = {}
Errors.log = log

local previous

-- ---------------------------------------------------------------------------
-- catching
-- ---------------------------------------------------------------------------

local function Record(msg)
	local text = tostring(msg or "")

	-- Same error twice in a row is a tick loop, not two failures. Count it
	-- rather than filling the box with one line repeated twelve times.
	local newest = log[1]
	if newest and newest.text == text then
		newest.count = (newest.count or 1) + 1
		return
	end

	table.insert(log, 1, {
		text  = text,
		when  = (date and date("%H:%M:%S")) or "",
		stack = (debugstack and debugstack(3)) or nil,
		count = 1,
	})

	for i = #log, MAX + 1, -1 do log[i] = nil end
end

function Errors:Install()
	if self.installed or not seterrorhandler then return false end
	self.installed = true

	previous = geterrorhandler and geterrorhandler() or nil

	seterrorhandler(function(msg)
		-- pcall: an error raised in here comes straight back to here.
		pcall(Record, msg)
		if previous then return previous(msg) end
	end)

	return true
end

--- Who and what, at the top of anything copied out of here.
--
--  A bug report without a version is a bug report about some build or other.
--  This costs four lines and removes the first question every time.
function Errors:Header()
	local build, _, _, iface = GetBuildInfo and GetBuildInfo()
	local skin = A.Palette and A.Palette.current or "?"
	local scale = A.db and A.db.profile and A.db.profile.scale or 1

	return table.concat({
		("AetherUI %s  ·  skin %s  ·  scale %.2f"):format(A.version or "?", skin, scale),
		("client %s (interface %s)  ·  %s"):format(
			tostring(build or "?"), tostring(iface or "?"),
			(date and date("%Y-%m-%d %H:%M")) or "?"),
		"",
	}, "\n")
end

--- Run something and collect what it would have printed to chat.
--
--  /aether diag answers in the chat frame, which is the one place its answer
--  cannot be selected. This borrows the two ways anything here writes a line,
--  and puts them back afterwards whatever happens.
function Errors:Capture(fn)
	local out = {}

	local realPrint = A.Print
	local chat = _G.DEFAULT_CHAT_FRAME
	local realAdd = chat and chat.AddMessage

	A.Print = function(_, msg, ...) out[#out + 1] = tostring(msg or "") end
	if chat then
		chat.AddMessage = function(_, msg, ...) out[#out + 1] = tostring(msg or "") end
	end

	local ok, err = pcall(fn)

	A.Print = realPrint
	if chat then chat.AddMessage = realAdd end

	if not ok then out[#out + 1] = "capture failed: " .. tostring(err) end

	-- Colour codes are for a chat frame, not for a paste into a bug report.
	local text = table.concat(out, "\n")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return text
end

--- Everything caught, oldest last, as one block of text.
function Errors:Text()
	if #log == 0 then
		return self:Header() .. "No errors caught since login."
	end

	local out = { self:Header() }
	for i, e in ipairs(log) do
		out[#out + 1] = ("[%d] %s%s"):format(
			i, e.when ~= "" and (e.when .. "  ") or "",
			e.count and e.count > 1 and ("(x%d) "):format(e.count) or "")
		out[#out + 1] = e.text
		if e.stack and e.stack ~= "" then out[#out + 1] = e.stack end
		out[#out + 1] = ""
	end
	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- the box
-- ---------------------------------------------------------------------------

local DIALOG_W, DIALOG_H = 720, 420
-- The scroll child's width: the dialog, less the left inset, less the right one
-- and the rail's channel.
local BOX_W    = DIALOG_W - 18 - 26 - 8
local RAIL_MIN = 24        -- a thumb shorter than this is not a grip
local RAIL_STEP = 44       -- one wheel notch

local function Build()
	if Errors.frame then return Errors.frame end

	local f = CreateFrame("Frame", ADDON .. "ErrorFrame", UIParent)
	f:SetSize(DIALOG_W, DIALOG_H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:Hide()

	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)

	local panel = A.Glass.CreatePanel(f, { corner = 16, fill = "dialogFill", edge = "glassEdgeHi" })
	panel:SetAllPoints(f)
	panel:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
	f.panel = panel

	local title = W.Text(f, "tbTitle", "CENTER")
	title:SetPoint("TOP", f, "TOP", 0, -14)
	title:SetText(L.errors.build.errors)
	W.Color(title, Palette.c.text)

	local hint = W.Text(f, "tbCardSub", "CENTER")
	hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
	hint:SetText(L.errors.build.export_writes_savedvariables_aetherui)
	W.Color(hint, Palette.c.textDim)

	-- A SCROLL FRAME AROUND IT, because a diag runs to eighty lines.
	--
	-- The box used to be anchored straight to the dialog, so everything past
	-- the fortieth line was drawn outside it: selected by Ctrl+A and copied
	-- correctly, and invisible. Which is the worst way for this to fail - the
	-- report you paste is complete and the one you can read is not.
	local scroll = CreateFrame("ScrollFrame", ADDON .. "ErrorScroll", f)
	scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -56)
	scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 18)
	f.scroll = scroll

	-- An EditBox, because it is the only thing in this client whose text can be
	-- selected. Not editable in any useful sense - it is a clipboard with a
	-- window.
	local box = CreateFrame("EditBox", ADDON .. "ErrorBox", scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetTextInsets(4, 4, 4, 4)
	-- A SCROLL CHILD HAS TO BE TOLD ITS WIDTH. It is not anchored to anything,
	-- so it has none of its own, and a multiline box with no width puts the
	-- whole report on one line.
	box:SetWidth(BOX_W)
	if box.SetFontObject then box:SetFontObject("ChatFontNormal") end
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		f:Hide()
	end)

	-- AND ON THE WAY OUT, HOWEVER IT GOES. This box takes the keyboard when it
	-- opens so that Ctrl+A works the moment you look at it - and Escape was the
	-- only thing giving it back. Closed by its own cross, or hidden by anything
	-- else, it kept the keyboard while invisible: every key went into a box
	-- nobody could see and the chat frame took nothing at all.
	f:HookScript("OnHide", function()
		if box.ClearFocus then box:ClearFocus() end
	end)
	scroll:SetScrollChild(box)
	f.box = box

	-- The rail. Drawn rather than borrowed: this is a dialog of ours and there
	-- is no client scroll bar in it to reskin. Same reasoning as the skill
	-- list's - a surface you can scroll with no sign of it reads as one that
	-- ends where the text stops, and here that is the difference between "the
	-- diag says this" and "the diag says this, and more".
	local track = f:CreateTexture(nil, "ARTWORK")
	track:SetTexture(A.Media.texture.flat)
	track:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -56)
	track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 18)
	track:SetWidth(A:Px(4))
	A.Widgets.Tint(track, Palette.c.textFaint, 0.22)
	f.track = track

	local thumb = f:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(A.Media.texture.flat)
	thumb:SetWidth(A:Px(4))
	A.Widgets.Tint(thumb, Palette.c.text, 0.45)
	f.thumb = thumb

	--- Where the rail's thumb goes, and whether there is a rail at all.
	local function UpdateRail()
		local view = scroll:GetHeight() or 0
		local full = box:GetHeight() or 0
		local range = full - view

		-- Nothing to scroll to is nothing to draw. A rail on a five-line report
		-- is a control that does not do anything.
		if range <= 1 or view <= 0 then
			track:Hide()
			thumb:Hide()
			return
		end
		track:Show()
		thumb:Show()

		local h = math.max(RAIL_MIN, view * (view / full))
		thumb:SetHeight(h)

		local at = math.min(1, math.max(0, (scroll:GetVerticalScroll() or 0) / range))
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", track, "TOP", 0, -(view - h) * at)
	end
	f.UpdateRail = UpdateRail

	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, (box:GetHeight() or 0) - (self:GetHeight() or 0))
		local v = (self:GetVerticalScroll() or 0) - delta * RAIL_STEP
		if v < 0 then v = 0 elseif v > max then v = max end
		self:SetVerticalScroll(v)
		UpdateRail()
	end)

	-- OnScrollRangeChanged rather than a call after SetText: a multiline box's
	-- height is worked out by the client when it lays the text out, which is not
	-- the moment we hand it the string. This is the event that says it has.
	scroll:SetScript("OnScrollRangeChanged", UpdateRail)
	scroll:SetScript("OnVerticalScroll", UpdateRail)

	local close = W.Text(f, "tbCardTitle", "CENTER")
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
	close:SetText("\195\151")
	W.Color(close, Palette.c.textDim)

	local hit = CreateFrame("Button", nil, f)
	hit:SetSize(24, 24)
	hit:SetPoint("CENTER", close, "CENTER", 0, 0)
	hit:SetScript("OnClick", function() f:Hide() end)

	-- EXPORT, WHICH DOES NOT GO THROUGH THE CLIPBOARD.
	--
	-- There is no way to copy out of this client that works. Ctrl+A, Ctrl+C
	-- takes what the EditBox LAID OUT rather than the string it was handed,
	-- and a twenty-five line capture that read correctly in the box - and
	-- counted correctly in chat at 1683 characters and 25 lines - arrived in
	-- Windows as thousands of lines.
	--
	-- CopyToClipboard would have stepped over the box entirely, and it IS in
	-- this client: Blizzard_Console, the API browser and the Edit Mode layout
	-- export all call it, and OsDocumentation declares it. It is also
	-- forbidden to addons, which the documentation says as HasRestrictions
	-- and the client says as "attempted to call a forbidden function from a
	-- tainted execution path". A pcall catches it and the error is reported
	-- anyway, so there is not a quiet version of that attempt either.
	--
	-- What is left is the saved variables file: a text file on the disk that
	-- holds what it is given, flushed on /reload or logout. Slower than a
	-- clipboard and the only one of the three that works.
	local copy = W.CreateButton(f, { corner = 8 })
	copy:SetSize(84, 22)
	copy:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)

	local copyText = W.Text(copy, "tbCardSub", "CENTER")
	copyText:SetPoint("CENTER")
	copyText:SetText(L.errors.build.export)
	W.Color(copyText, Palette.c.text)
	copy.__label = copyText

	copy:SetScript("OnEnter", function(self) W.SetButtonState(self, false, true) end)
	copy:SetScript("OnLeave", function(self) W.SetButtonState(self, false, false) end)
	copy:SetScript("OnClick", function()
		Errors:Export("last", f.__text or "")
	end)
	f.copy = copy

	Errors.frame = f
	return f
end

--- Put text where it can be read from outside the game.
--
--  THE SAVED VARIABLES FILE, because nothing else in this client works. See
--  the Export button above for the two routes that do not.
--
--  NOT FLUSHED UNTIL /reload OR LOGOUT. The client writes that file when it
--  feels like it and never on demand, so saying so is part of the job - a
--  player who alt-tabs straight to the file finds the last one there and
--  concludes this is broken.
function Errors:Export(key, text)
	if not A.db then return false end
	A.db.global.export = A.db.global.export or {}
	A.db.global.export[key or "last"] = tostring(text or "")

	A:Print(("exported %d characters as %s - /reload, then open"):format(
		#tostring(text or ""), A.Val(key or "last"))
		.. " " .. A.Hi("WTF\\Account\\<account>\\SavedVariables\\"
			.. "AetherUI.lua") .. " and look under " .. A.Val("export"))
	return true
end

--- Show any text at all, ready to read.
function Errors:ShowText(text)
	local f = Build()

	-- SHOWN FIRST, THEN FILLED. A multiline EditBox lays its text out when
	-- it is on screen, and a hidden one has no laid-out lines to put a string
	-- into - so text handed over while it was down came back as its first
	-- line and, depending on the run, a great many empty ones after it. Two
	-- captures were reported that way before this was the suspect, and the
	-- string handed over was verified correct both times.
	f:Show()
	-- KEPT AS HANDED, for the Copy button. What is in the box after this is
	-- the box's version of it, and the two turned out not to be the same.
	f.__text = text or ""
	f.box:SetText(text or "")
	f.box:HighlightText()
	-- Back to the top. A second report opened where the last one was left
	-- scrolled to, which reads as a box that has lost its first ten lines.
	f.scroll:SetVerticalScroll(0)
	f.box:SetFocus()
	if f.UpdateRail then f.UpdateRail() end

	-- WHAT WENT IN, in numbers, beside what came out on screen. A box that
	-- shows one line of an eight-line report looks exactly like a report that
	-- had one line in it, and telling those apart from the outside took two
	-- builds. Now it is one line of chat.
	local lines = 1 + select(2, tostring(text or ""):gsub("\n", ""))
	A:Print(("copy box: %d characters, %d lines"):format(#(text or ""),
		lines))
	return f
end

function Errors:Show()
	return self:ShowText(self:Text())
end

return Errors
