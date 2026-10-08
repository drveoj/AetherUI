--[[--------------------------------------------------------------------------
	Lattice :: Layout

	THE LAYOUT STRING: a whole arrangement of the HUD as one line of text, to
	share, keep, or ship as a preset (parent model phase C; Joe's decision 5).

	    LAT1;s=0.71;b=1,2;bar1=B,spine,BOTTOM,CENTER,0,-96;chat=S,BOTTOMLEFT,...

	  LAT1      the version. Anything else is refused, not guessed at.
	  s=        the HUD scale, which travels with the layout.
	  b=        the numbered action bars that are on. Every other is OFF: a
	            layout made around two bars has nothing to say about a third,
	            and leaving one on where the last layout put it is two layouts
	            at once.
	  name=S,point,relPoint,fx,fy[,F]
	            a node on the SCREEN, as fractions of it, because a screen
	            position in units is a position for one monitor. F: set free of
	            the parent its module would give it.
	  name=B,parent,point,relPoint,x,y
	            a node BONDED to another, as its offset in its own units.
	            Those do not depend on the screen at all, which is what lets
	            a layout travel.

	Records come out sorted, so the same arrangement is always the same text.

	REFUSED, WHOLE: a string of another version, one naming a node this addon
	has never had, one whose bonds would loop, and anything during combat -
	re-anchoring frames with secure children is protected. Nothing is half
	applied.

	GETTING IT OUT. This client cannot copy reliably: the multi-line copy box
	hands over what it LAID OUT rather than the string, and CopyToClipboard is
	forbidden to addons (see Core/Errors.lua). Pasting in works. So the window
	shows the string in a single-line box, which may copy where the multi-line
	one does not, and Export writes it to the saved variables file, which is
	the one route out known to carry text intact.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = A.L
local W, Palette = A.Widgets, A.Palette
local Layout = {}
A.Layout = Layout

Layout.VERSION = "LAT1"

--- Every node a module registers with the movers, by the name it registers.
--  A layout naming anything else is refused: it was made by something that is
--  not this addon, or by a version of it with nodes this one does not have.
local NODES = {
	"player", "target", "pet", "targettarget", "party", "chat", "minimap",
	"quests", "tooltip", "ifec", "barstance", "barpet", "barextra",
	"bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8", "bar9",
}
local KNOWN = {}
for _, n in ipairs(NODES) do KNOWN[n] = true end
Layout.KNOWN = KNOWN

--- Nodes that can be a parent but are never placed themselves, and the node
--  each belongs to - which is where a loop through one really goes.
local OWNED = { spine = "player" }

local function round(v) return math.floor((v or 0) + 0.5) end

--- A number, and a finite one. "nan" and "inf" parse; neither is a position.
local function Num(v)
	local n = tonumber(v)
	if n and n == n and n ~= math.huge and n ~= -math.huge then return n end
	return nil
end

--- UIParent's size in the units a screen record is written in. An offset is
--  in the frame's own space, and the HUD's frames are at `scale`, so the screen
--  is divided by it - and a layout carries its scale, so the fraction captured
--  on one machine is the fraction applied on the next.
local function ScreenIn(scale)
	scale = (type(scale) == "number" and scale > 0) and scale or 1
	local w = (UIParent and UIParent:GetWidth()) or 0
	local h = (UIParent and UIParent:GetHeight()) or 0
	if w <= 0 or h <= 0 then return 0, 0 end
	return w / scale, h / scale
end
Layout.ScreenIn = ScreenIn

-- ---------------------------------------------------------------------------
-- the numbered action bars
--
-- THE NUMBERED BARS AND NOTHING ELSE. The stance, pet, taxi and extra-action
-- bars are not layout choices - the game gives you one or it does not, by
-- class and by circumstance.
-- ---------------------------------------------------------------------------

--- The numbered bars this client has: six, and WoW Forever's three more.
local function Bars()
	local out = { "1", "2", "3", "4", "5", "6" }
	if A.isCamelot then out[7], out[8], out[9] = "7", "8", "9" end
	return out
end
Layout.Bars = Bars

--- Which are on, as the profile has it now.
local function BarsNow()
	local AB = A.GetModule and A:GetModule("actionbars")
	if not AB or not AB.BarConfig then return nil end
	local out = {}
	for _, id in ipairs(Bars()) do
		local cfg = AB:BarConfig(id)
		if cfg then out[id] = cfg.enabled and true or false end
	end
	return out
end
Layout.BarsNow = BarsNow

--- Exactly these on and every other off, with ONE rebuild: SetBarEnabled
--  rebuilds every button on the screen per call.
local function SetBars(on)
	local AB = A.GetModule and A:GetModule("actionbars")
	if not AB or not AB.BarConfig or type(on) ~= "table" then return end
	local changed = false
	for _, id in ipairs(Bars()) do
		local cfg = AB:BarConfig(id)
		local want = on[id] and true or false
		if cfg and (cfg.enabled and true or false) ~= want then
			cfg.enabled = want
			changed = true
		end
	end
	if changed and AB.OnConfigChanged then AB:OnConfigChanged() end
end

-- ---------------------------------------------------------------------------
-- the string
-- ---------------------------------------------------------------------------

--- The arrangement on screen now, as one line.
function Layout:Encode()
	local profile = A.db.profile
	local anchors = profile.anchors or {}
	local scale = profile.scale or 1
	local sw, sh = ScreenIn(scale)

	local parts = { Layout.VERSION, ("s=%.2f"):format(scale) }
	local on, bars = {}, BarsNow() or {}
	for _, id in ipairs(Bars()) do
		if bars[id] then on[#on + 1] = id end
	end
	parts[#parts + 1] = "b=" .. table.concat(on, ",")

	-- Only nodes this addon has. `__` entries are not positions - the lock
	-- pill's spot is one - and a profile can still hold one for a frame that is
	-- gone: the floating cast bars left `cast` and `targetcast` behind when the
	-- lanes replaced them. Written out, those made a string Decode refuses.
	local names = {}
	for name in pairs(anchors) do
		if KNOWN[name] then names[#names + 1] = name end
	end
	table.sort(names)

	for _, name in ipairs(names) do
		local a = anchors[name]
		local lat = type(a.lat) == "table" and a.lat
		if lat and lat.parent and not a.free then
			parts[#parts + 1] = ("%s=B,%s,%s,%s,%d,%d"):format(name, lat.parent,
				tostring(lat.point), tostring(lat.relPoint), round(lat.x), round(lat.y))
		elseif a.point then
			parts[#parts + 1] = ("%s=S,%s,%s,%.5f,%.5f%s"):format(name,
				a.point, a.relPoint or a.point,
				sw > 0 and (a.x or 0) / sw or 0, sh > 0 and (a.y or 0) / sh or 0,
				a.free and ",F" or "")
		end
	end
	return table.concat(parts, ";")
end

--- Read a string back. Returns the layout, or nil and the reason in words.
function Layout:Decode(text)
	if type(text) ~= "string" then return nil, L.layout.err.empty end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil, L.layout.err.empty end

	local fields = {}
	for f in (text .. ";"):gmatch("([^;]*);") do fields[#fields + 1] = f end
	if fields[1] ~= Layout.VERSION then
		return nil, A.F(L.layout.err.version, tostring(fields[1]):sub(1, 12))
	end

	local valid = A.Movers.VALID_POINTS
	local out = { bars = {}, records = {} }
	local function bad(f) return nil, A.F(L.layout.err.bad, tostring(f):sub(1, 32)) end

	for i = 2, #fields do
		local f = fields[i]
		if f ~= "" then
			local k, v = f:match("^([%w_]+)=(.*)$")
			if not k then return bad(f) end

			if k == "s" then
				local s = Num(v)
				if not s or s < 0.3 or s > 2 then return bad(f) end
				out.scale = s
			elseif k == "b" then
				for id in v:gmatch("[^,]+") do
					if not id:match("^%d$") then return bad(f) end
					out.bars[id] = true
				end
			else
				if not KNOWN[k] then return nil, A.F(L.layout.err.unknown, k) end
				if out.records[k] then return bad(f) end
				local p = {}
				for x in (v .. ","):gmatch("([^,]*),") do p[#p + 1] = x end

				if p[1] == "S" and (#p == 5 or (#p == 6 and p[6] == "F")) then
					local fx, fy = Num(p[4]), Num(p[5])
					if not (valid[p[2]] and valid[p[3]] and fx and fy) then return bad(f) end
					out.records[k] = { kind = "S", point = p[2], relPoint = p[3],
						fx = fx, fy = fy, free = (p[6] == "F") or nil }
				elseif p[1] == "B" and #p == 6 then
					local parent, x, y = p[2], Num(p[5]), Num(p[6])
					if not (KNOWN[parent] or OWNED[parent]) then
						return nil, A.F(L.layout.err.unknown, parent)
					end
					if not (valid[p[3]] and valid[p[4]] and x and y) then return bad(f) end
					out.records[k] = { kind = "B", parent = parent, point = p[3],
						relPoint = p[4], x = round(x), y = round(y) }
				else
					return bad(f)
				end
			end
		end
	end
	if not out.scale then return bad("s=") end

	-- NO LOOPS. A node bonded to its own descendant is an anchor loop, which
	-- the client refuses - and through the spine, which belongs to the player.
	for name in pairs(out.records) do
		local p, hops = out.records[name].parent, 0
		while p and hops < 24 do
			if p == name then return nil, A.F(L.layout.err.loop, name) end
			if OWNED[p] then
				p = OWNED[p]
			else
				p = out.records[p] and out.records[p].parent
			end
			hops = hops + 1
		end
	end
	return out
end

--- Put a decoded layout on screen. WIPED, NOT MERGED: a layout is a whole
--  arrangement, and merging one over another leaves whatever the last one
--  moved that this one does not mention. Returns true, or false and why.
function Layout:Apply(layout)
	if not layout or not A.db then return false, L.layout.err.empty end
	if InCombatLockdown() then return false, L.layout.err.combat end

	-- THE BARS FIRST: a bar that is off has no frame and no mover, so a record
	-- written for it before it is on is a record for nothing.
	SetBars(layout.bars)

	local profile = A.db.profile
	local anchors = profile.anchors
	if type(anchors) ~= "table" then
		anchors = {}
		profile.anchors = anchors
	end
	local keep = {}
	for name, a in pairs(anchors) do
		if tostring(name):find("^__") then keep[name] = a end
	end
	wipe(anchors)
	for name, a in pairs(keep) do anchors[name] = a end

	-- The layout's own scale: it is about to be the profile's, and resolving
	-- the fractions against the old one puts everything out by the ratio.
	local scale = layout.scale or profile.scale
	local sw, sh = ScreenIn(scale)
	for name, r in pairs(layout.records) do
		if r.kind == "S" then
			anchors[name] = { point = r.point, relPoint = r.relPoint,
				x = round(r.fx * sw), y = round(r.fy * sh), free = r.free }
		else
			anchors[name] = { lat = { parent = r.parent, point = r.point,
				relPoint = r.relPoint, x = r.x, y = r.y } }
		end
	end
	profile.scale = scale

	-- Every node on its new parent BEFORE anything is re-registered: a module
	-- re-registering a parent re-places its children, and one still on its old
	-- parent would be measured against that and lose the layout's bond. Then
	-- the scale onto the frames, then every node to its record.
	A.Movers:ResolveParents()
	A:Reconfigure()
	A.Movers:AdoptLayout()
	return true
end

--- Is the layout on screen now this one? The tour and the preset list ask.
--  Within a unit, because a fraction resolved on one screen and saved on it
--  comes back a rounding away.
function Layout:Matches(layout)
	if not layout or not A.db then return false end
	local now = BarsNow()
	if now then
		for id, on in pairs(now) do
			if on ~= (layout.bars[id] and true or false) then return false end
		end
	end

	local anchors = A.db.profile.anchors or {}
	local sw, sh = ScreenIn(layout.scale or A.db.profile.scale)
	local named = 0
	for name, r in pairs(layout.records) do
		named = named + 1
		local b = anchors[name]
		if not b then return false end
		if r.kind == "S" then
			if b.point ~= r.point or b.relPoint ~= r.relPoint then return false end
			if math.abs(r.fx * sw - (b.x or 0)) > 1 or math.abs(r.fy * sh - (b.y or 0)) > 1 then
				return false
			end
		else
			local lat = b.lat
			if type(lat) ~= "table" or lat.parent ~= r.parent or lat.point ~= r.point
				or lat.relPoint ~= r.relPoint then return false end
			if math.abs((lat.x or 0) - r.x) > 1 or math.abs((lat.y or 0) - r.y) > 1 then
				return false
			end
		end
	end

	-- The empty layout is "untouched", so it matches only an untouched profile.
	-- Untouched as far as nodes go: a leftover position for a frame that is
	-- gone moves nothing, so it does not count.
	if named == 0 then
		for name in pairs(anchors) do
			if KNOWN[name] then return false end
		end
	end
	return true
end

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

local WIN_W, WIN_H = 640, 168

local function Button(parent, text, w)
	local b = W.CreateButton(parent, { corner = 8 })
	b:SetSize(w, 24)
	local label = W.Text(b, "tbCardSub", "CENTER")
	label:SetPoint("CENTER")
	label:SetText(text)
	W.Color(label, Palette.c.text)
	b.__aetherLabel = label
	b:SetScript("OnEnter", function(self) W.SetButtonState(self, false, true) end)
	b:SetScript("OnLeave", function(self) W.SetButtonState(self, false, false) end)
	return b
end

local function Build()
	if Layout.frame then return Layout.frame end

	local f = CreateFrame("Frame", ADDON .. "LayoutFrame", UIParent)
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()

	local panel = A.Glass.CreatePanel(f, { corner = 16, fill = "dialogFill", edge = "glassEdgeHi" })
	panel:SetAllPoints(f)
	panel:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))

	f.title = W.Text(f, "tbTitle", "CENTER")
	f.title:SetPoint("TOP", f, "TOP", 0, -14)
	f.title:SetText(L.layout.window.title)
	W.Color(f.title, Palette.c.text)

	f.hint = W.Text(f, "tbCardSub", "CENTER")
	f.hint:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
	f.hint:SetText(L.layout.window.hint)
	W.Color(f.hint, Palette.c.textDim)

	local well = A.Glass.CreatePanel(f, { corner = 8 })
	well:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -58)
	well:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -58)
	well:SetHeight(28)

	-- ONE LINE. The multi-line copy box hands Ctrl+C what it laid out rather
	-- than the string; a single-line box has nothing to lay out.
	local box = CreateFrame("EditBox", ADDON .. "LayoutBox", well)
	box:SetPoint("TOPLEFT", well, "TOPLEFT", 8, 0)
	box:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -8, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	if box.SetFontObject then box:SetFontObject("ChatFontNormal") end
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
	box:SetScript("OnEnterPressed", function() Layout:ApplyText(box:GetText()) end)
	f:HookScript("OnHide", function() box:ClearFocus() end)
	f.box = box

	f.status = W.Text(f, "tbCardSub", "LEFT")
	f.status:SetPoint("TOPLEFT", well, "BOTTOMLEFT", 2, -10)
	f.status:SetPoint("RIGHT", f, "RIGHT", -18, 0)

	f.apply = Button(f, L.layout.window.apply, 120)
	f.apply:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
	f.apply:SetScript("OnClick", function() Layout:ApplyText(box:GetText()) end)

	f.export = Button(f, L.layout.window.export, 140)
	f.export:SetPoint("RIGHT", f.apply, "LEFT", -8, 0)
	f.export:SetScript("OnClick", function()
		A.Errors:Export("layout", Layout:Encode())
	end)

	f.close = Button(f, L.layout.window.close, 90)
	f.close:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 16)
	f.close:SetScript("OnClick", function() f:Hide() end)

	Layout.frame = f
	return f
end

local function Say(text, good)
	local f = Layout.frame
	if not f then return end
	f.status:SetText(text or "")
	W.Color(f.status, good and Palette.c.friendly or Palette.c.danger)
end

--- Apply what is in the box: decoded, checked, and on screen - or the reason
--  it was not, in the window where it was pasted.
function Layout:ApplyText(text)
	local layout, err = Layout:Decode(text)
	if not layout then Say(err) return false end
	local ok, why = Layout:Apply(layout)
	if not ok then Say(why) return false end
	if Layout.frame then Layout.frame.box:SetText(Layout:Encode()) end
	Say(L.layout.window.applied, true)
	return true
end

--- The window, with the arrangement on screen now in the box, selected.
function Layout:Show()
	local f = Build()
	f:SetScale(A.db.profile.scale or 1)
	f.box:SetText(Layout:Encode())
	Say("")
	f:Show()
	f:Raise()
	f.box:SetFocus()
	f.box:HighlightText()
end
