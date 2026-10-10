--[[--------------------------------------------------------------------------
	Lattice :: Mail

	The World trunk's Mail node (Lattice 6a): an envelope, empty or full, with
	a small dot while there is mail, and a branch beside it saying who from.
	It took over from the Toolbox's rail envelope and drawer section.

	WHAT THE CLIENT WILL TELL US, which is very little:

	  HasNewMail()            -> boolean. That is the whole of it.
	  GetLatestThreeSenders() -> up to three sender NAMES. No subject, no count.
	                             Capped at three by the client, not by us.
	  UPDATE_PENDING_MAIL     -> fires when either of the above changes.

	There is no unread count away from a mailbox. GetLatestThreeSenders only
	knows mail that arrived while you were logged in, and it can come back
	empty while HasNewMail is true: auction house and NPC mail carries no name.
	So "you have mail" with no list is a real state, not a bug.

	At a mailbox GetInboxHeaderInfo says everything, so the inbox is read there
	and remembered per character, and shown as "last visit": a different claim
	from "in the box now", and the branch says which one it is making. The
	record stays at db.char.toolbox.mail, where the Toolbox kept it.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local W, Palette, Glass = A.Widgets, A.Palette, A.Glass
local L = A.L

local Mail = { ROWS = 3 }
A.Mail = Mail

-- The branch, in HUD units.
local WIDTH, PAD, HEAD_H, NOTE_H = 230, 14, 22, 18
local ROW_H, ROW_GAP, CHIP = 30, 5, 24
local CORNER = 12

local function Char()
	if not (A.db and A.db.char) then return nil end
	A.db.char.toolbox = A.db.char.toolbox or {}
	return A.db.char.toolbox
end

local function Trunk() return A.Trunk:Get("world") end

--- The section headings are letter-spaced, baked into the string: the client
--  has no letter-spacing.
local function Spaced(s)
	return (s:gsub("(.)", "%1 "):gsub(" $", ""))
end

-- ---------------------------------------------------------------------------
-- what the client knows
-- ---------------------------------------------------------------------------

--- Read the inbox while standing at one, and remember what it held unread.
--  MAIL_INBOX_UPDATE also fires when the box is emptied, so every way out of
--  here repaints.
function Mail:ReadInbox()
	local c = Char()
	local okN, n
	if c and GetInboxNumItems and GetInboxHeaderInfo then okN, n = pcall(GetInboxNumItems) end
	if okN and n then
		local seen, senders, unread = {}, {}, 0
		for i = 1, n do
			-- wasRead is nine returns deep: an inbox is a list of mail, not of
			-- unread mail.
			local ok, _, _, sender, _, _, _, _, _, wasRead = pcall(GetInboxHeaderInfo, i)
			if ok and not wasRead then
				unread = unread + 1
				local who = (type(sender) == "string" and sender ~= "") and sender
					or (_G.UNKNOWN or "Unknown")
				if not seen[who] then
					seen[who] = true
					senders[#senders + 1] = who
				end
			end
		end
		-- An empty box clears the record rather than leaving zeroes behind.
		if unread == 0 then
			c.mail = nil
		else
			c.mail = { senders = senders, unread = unread, at = (_G.time and _G.time()) or 0 }
		end
	end
	self:Changed()
end

--- What this character last saw in its mailbox, or nil.
function Mail:Record()
	local c = Char()
	return c and c.mail or nil
end

--- `has`, the senders, a true unread count if there is one, and whether that
--  came from the record rather than from the client. Read at call time: the
--  live senders change under us.
function Mail:State()
	local has = HasNewMail and HasNewMail() and true or false
	if not has then return false, {}, nil, false end

	local senders = {}
	if GetLatestThreeSenders then
		-- pcall: it can be asked before the client has finished logging in.
		local ok, a, b, c = pcall(GetLatestThreeSenders)
		if ok then
			for _, s in ipairs({ a, b, c }) do
				if type(s) == "string" and s ~= "" then senders[#senders + 1] = s end
			end
		end
	end
	-- The client's answer wins: it is about now, the record about last time.
	if #senders > 0 then return true, senders, nil, false end

	local rec = self:Record()
	if rec and rec.senders and #rec.senders > 0 then
		local out = {}
		for i, who in ipairs(rec.senders) do out[i] = who end
		return true, out, rec.unread, true
	end
	return true, {}, nil, false
end

function Mail:Has() return (self:State()) end

-- ---------------------------------------------------------------------------
-- the branch
-- ---------------------------------------------------------------------------

--- The first LETTER of a name, not the first byte: half a multi-byte
--  character draws as a box. The lead byte says how many follow.
local function Initial(who)
	local b1 = who:byte(1) or 0
	local n = (b1 < 0x80 and 1) or (b1 < 0xE0 and 2) or (b1 < 0xF0 and 3) or 4
	local s = who:sub(1, n)
	return n == 1 and s:upper() or s
end

--- A chip saying the branch does not have a sender to show: quiet fill, rim.
local function QuietChip(chip, text)
	local c = Palette.c
	chip.label:SetText(text)
	local q = c.cardBg
	chip.disc:SetVertexColor(q[1], q[2], q[3], q[4] or 1)
	chip.ring:Show()
	local e = c.glassEdge
	chip.ring:SetVertexColor(e[1], e[2], e[3], 0.9)
	W.Color(chip.label, c.textDim)
end

function Mail:Build()
	if self.panel then return self.panel end
	local t = Trunk()
	local p = Glass.CreatePanel(t:Frame(), {
		corner = CORNER, shadow = A.db.profile.glass.shadow, name = ADDON .. "MailBranch",
	})
	p:SetFrameLevel(t:Frame():GetFrameLevel() + 20)
	p:SetWidth(WIDTH)
	p:EnableMouse(true)
	p:Hide()

	p.head = W.Text(p, "tbSection", "LEFT")
	p.head:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -PAD)
	p.head:SetText(Spaced(L.mail.heading))
	p.hint = W.Text(p, "tbLabel", "RIGHT")
	p.hint:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -PAD)

	p.rows = {}
	for i = 1, self.ROWS do
		local row = CreateFrame("Frame", nil, p)
		row:SetSize(WIDTH - PAD * 2, ROW_H)
		row:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(PAD + HEAD_H + (i - 1) * (ROW_H + ROW_GAP)))
		-- The sender's initial in a chip: it varies down the list, the name
		-- beside it does the rest.
		row.chip = W.CreateBadge(row, { size = CHIP, style = "tbChip" })
		row.chip:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.name = W.Text(row, "tbCardTitle", "LEFT")
		row.name:SetPoint("LEFT", row.chip, "RIGHT", 10, 0)
		row.name:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		p.rows[i] = row
	end
	p.note = W.Text(p, "tbLabel", "LEFT")
	p.note:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", PAD, PAD)

	-- However it shuts - its node, another branch, Escape - the node follows.
	p:SetScript("OnShow", function() Trunk():Paint() end)
	p:SetScript("OnHide", function() Trunk():Paint() end)
	if _G.UISpecialFrames then table.insert(_G.UISpecialFrames, p:GetName()) end

	self.panel = p
	self:Skin()
	return p
end

--- The reading fill, again after anything that puts the glass tint back.
function Mail:Skin()
	local p = self.panel
	if not p then return end
	p:ApplySkin()
	p:SetFillColor(Palette:ReadingFill())
	W.Color(p.head, Palette.c.text)
	W.Color(p.note, Palette.c.textDim)
	self:Fill()
end

--- Write the rows, the hint and the note, and size the branch to them.
function Mail:Fill()
	local p = self.panel
	if not p then return end
	local c = Palette.c
	local has, senders, unread, stale = self:State()
	-- Mail with no name on it gets one row saying why; an empty box one row
	-- saying so. Neither is a sender.
	local explain = has and #senders == 0
	local n = (has and not explain) and #senders or 1
	self.rowCount = n

	for i, row in ipairs(p.rows) do
		local who = senders[i]
		row:SetShown(i <= n)
		if i > n then
			row.name:SetText("")
		elseif not has then
			QuietChip(row.chip, "0")
			row.name:SetText(L.mail.none)
			W.Color(row.name, c.textDim)
		elseif explain then
			QuietChip(row.chip, "?")
			row.name:SetText(L.mail.after_mailbox)
			W.Color(row.name, c.textDim)
		else
			row.chip.label:SetText(Initial(who))
			local fill = c.btnFill
			row.chip.disc:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1)
			-- Filled chip, no rim: a bright ring on a bright disc is no edge.
			row.chip.ring:Hide()
			W.Color(row.chip.label, c.btnFillText)
			row.name:SetText(who)
			W.Color(row.name, c.text)
		end
	end

	-- Which claim the hint makes: the client's count of senders (capped at
	-- three, so three reads "3+"), a true count from the last mailbox visit,
	-- or only "you have mail".
	if not has then
		p.hint:SetText("")
	elseif explain then
		p.hint:SetText(_G.HAVE_MAIL or "")
		W.Color(p.hint, c.textDim)
	elseif unread then
		p.hint:SetText(A.F(L.mail.unread_last_visit_d, unread))
		W.Color(p.hint, c.textDim)
	else
		local capped = #senders >= self.ROWS
		p.hint:SetText(A.F(capped and L.mail.new_more_d or L.mail.new_d, #senders))
		W.Color(p.hint, c.accent or c.text)
	end

	-- At the client's cap, say so: three might be nine.
	local capped = has and not stale and #senders >= self.ROWS
	p.note:SetText(capped and L.mail.only_three or "")
	p.note:SetShown(capped)
	p:SetHeight(PAD + HEAD_H + n * (ROW_H + ROW_GAP) - ROW_GAP + (capped and NOTE_H or 0) + PAD)
end

function Mail:Open()
	local p = self:Build()
	self:Fill()
	if not Trunk():Place("mail", p) then return end
	p:Show()
end

function Mail:Close()
	if self.panel then self.panel:Hide() end
end

function Mail:IsOpen()
	return self.panel and self.panel:IsShown() and true or false
end

--- Something about the mail changed: the node's envelope and dot, and the
--  branch if it is open.
function Mail:Changed()
	if not self.attached then return end
	Trunk():Paint()
	if self:IsOpen() then
		self:Fill()
		Trunk():Place("mail", self.panel)
	end
end

-- ---------------------------------------------------------------------------
-- the node
-- ---------------------------------------------------------------------------

--- Put the Mail node on the World trunk. Called by the minimap, which owns it.
function Mail:Attach()
	Trunk():AddNode("mail", {
		icon = function() return Mail:Has() and "mailfull" or "mail" end,
		badge = function() return Mail:Has() end,
		label = L.trunk.mail, order = 400,
		-- Goes when the trunk retracts: a branch beside nothing.
		transient = true,
		isOpen = function() return Mail:IsOpen() end,
		open = function() Mail:Open() end,
		close = function() Mail:Close() end,
	})
	self.attached = true
	if not self.listening then
		self.listening = true
		for _, ev in ipairs({ "UPDATE_PENDING_MAIL", "MAIL_CLOSED", "PLAYER_ENTERING_WORLD" }) do
			A:RegisterEvent(Mail, ev, function() Mail:Changed() end)
		end
		-- The one moment the client says everything. Read even while the node
		-- is down, so the record is right when it comes back.
		A:RegisterEvent(Mail, "MAIL_INBOX_UPDATE", function() Mail:ReadInbox() end)
	end
	self:Changed()
end

function Mail:Detach()
	self.attached = false
	self:Close()
end
