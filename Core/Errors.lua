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

local function Build()
	if Errors.frame then return Errors.frame end

	local f = CreateFrame("Frame", ADDON .. "ErrorFrame", UIParent)
	f:SetSize(720, 420)
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
	title:SetText("Errors")
	W.Color(title, Palette.c.text)

	local hint = W.Text(f, "tbCardSub", "CENTER")
	hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
	hint:SetText("Ctrl+A then Ctrl+C. Escape closes.")
	W.Color(hint, Palette.c.textDim)

	-- An EditBox, because it is the only thing in this client whose text can be
	-- selected. Not editable in any useful sense - it is a clipboard with a
	-- window.
	local box = CreateFrame("EditBox", ADDON .. "ErrorBox", f)
	box:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -56)
	box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 18)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetTextInsets(4, 4, 4, 4)
	if box.SetFontObject then box:SetFontObject("ChatFontNormal") end
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		f:Hide()
	end)
	f.box = box

	local close = W.Text(f, "tbCardTitle", "CENTER")
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
	close:SetText("\195\151")
	W.Color(close, Palette.c.textDim)

	local hit = CreateFrame("Button", nil, f)
	hit:SetSize(24, 24)
	hit:SetPoint("CENTER", close, "CENTER", 0, 0)
	hit:SetScript("OnClick", function() f:Hide() end)

	Errors.frame = f
	return f
end

--- Show any text at all, ready to copy.
function Errors:ShowText(text)
	local f = Build()
	f.box:SetText(text or "")
	f.box:HighlightText()
	f:Show()
	f.box:SetFocus()
	return f
end

function Errors:Show()
	return self:ShowText(self:Text())
end

return Errors
