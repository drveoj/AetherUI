--[[--------------------------------------------------------------------------
	Lattice :: Trunk

	A trunk is a strand down a screen edge with branch nodes on it (Lattice
	handoff, "Trunks", boards 6a and 5b): the World trunk hangs from the
	minimap's info pill, and the Toolbox trunk will be the same piece on the
	other edge. Our own plain frames throughout - nothing on a trunk is
	protected, so it can open, close and (later) retract in combat.

	A node is a 24 px diamond holding a 14 px icon, with an 80 px stub toward
	the centre of the screen and a label above the stub. Lit while its branch
	is open. One branch open at a time per trunk: opening one closes the other.
	A module adds a node and says how to open, close and tell whether it is
	open; the trunk draws, lays out and lights.

	    local t = A.Trunk:Get("world")
	    t:SetRoot(pill)
	    t:AddNode("questlog", { icon = "quests", label = L.trunk.questlog,
	        order = 100, open = fn(node), close = fn(node), isOpen = fn(),
	        available = fn() })

	An ITEM node (kind = "item") is the other kind: an 18 px diamond with no
	icon and no stub, one per tracked quest. Its owner draws the text beside it
	and its state (decorate), handles its clicks (onClick) and says how much
	of the strand it needs below it (step), which is how a quest showing its
	objectives gets the room for them.

	In a fight the World trunk retracts into its top end-cap (6b), leaving
	only a tail - a dotted stub and a small diamond - for its owner to write
	the active objective beside.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local W, Media, Palette = A.Widgets, A.Media, A.Palette
local Trunk = { list = {} }
A.Trunk = Trunk

-- The handoff's numbers, in HUD units (a pixel at the fitted scale).
local NODE, ICON, STEP, STUB = 24, 14, 72, 80
local ITEM = 18
local BADGE = 7
-- A branch node's room when a quest hangs straight under it: 72 left the
-- first quest adrift of its Quest Log node (Joe, in game).
local LEAD = 36
-- Kept clear under the trunk's last node: the screen's bottom edge, where the
-- chat and the bars live.
local FLOOR = 24
local CAP, CAP_GAP, FIRST, LAST = 10, 30, 40, 36
local JUNCTION = 11
-- A label ends this far short of its node, over the stub.
local LABEL_GAP = 8
-- Retracted (6b): a dotted stub this long under the top end-cap, ending in a
-- diamond this size; the strand goes up and comes down over RETRACT seconds.
local TAIL, TAIL_NODE, RETRACT = 30, 14, 0.3
local DASH, DASH_GAP = 2, 4
-- How far past a node the strand's end has to be before it is all there.
local FADE = 24

local Proto = {}
Proto.__index = Proto

-- Whose settings hold a trunk's label choice (Joe, 2026-10-10: an option for
-- the labels to hide, each popping out while the cursor is over its node).
-- The World trunk is the quest tracker's page in the options map.
local LABEL_OWNER = { world = "questtracker", toolbox = "toolbox" }

local function ByOrder(x, y) return (x.order or 0) < (y.order or 0) end

--- The room a node takes below it: an item node what its owner asks for, a
--  branch node 72, or LEAD when the node under it is an item.
local function StepOf(node, below)
	if node.step then return node.step end
	return (below and below.kind == "item") and LEAD or STEP
end

--- The trunk called `name`, made on first ask.
function Trunk:Get(name)
	local t = Trunk.list[name]
	if not t then
		t = setmetatable({ name = name, nodes = {} }, Proto)
		Trunk.list[name] = t
	end
	return t
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------

local function Build(t)
	local f = CreateFrame("Frame", ADDON .. "Trunk" .. t.name, UIParent)
	f:SetFrameStrata("MEDIUM")
	f:SetSize(NODE, NODE)
	f:Hide()
	f.strand = f:CreateTexture(nil, "BACKGROUND")
	f.strand:SetTexture(Media.texture.flat)
	f.capTop = f:CreateTexture(nil, "ARTWORK")
	f.capTop:SetTexture(Media.texture.diamond)
	f.capBottom = f:CreateTexture(nil, "ARTWORK")
	f.capBottom:SetTexture(Media.texture.diamond)
	t.frame = f
	if A.Fader then A.Fader:Register(f) end
	return f
end

--- An item node: the diamond only. Its owner paints it and takes its clicks.
--  `size` for another size; `bare` for no diamond at all, when the owner hangs
--  something of its own there (the Toolbox's pinned addons).
local function BuildItem(t, node)
	local size = node.size or ITEM
	local b = CreateFrame("Button", nil, t.frame)
	b:SetSize(size, size)
	b:RegisterForClicks("AnyUp")
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetTexture(Media.texture.glow)
	b.glow:SetPoint("CENTER")
	b.glow:SetSize(size * 2.4, size * 2.4)
	b.glow:Hide()
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetTexture(Media.texture.diamond)
	b.fill:SetAllPoints(b)
	b.rim = b:CreateTexture(nil, "ARTWORK", nil, 1)
	b.rim:SetTexture(Media.texture.diamondRim)
	b.rim:SetAllPoints(b)
	if node.bare then
		b.fill:Hide()
		b.rim:Hide()
	end
	b:SetScript("OnClick", function(_, button)
		if node.onClick then node.onClick(node, button) end
	end)
	b:SetScript("OnEnter", function() if node.onEnter then node.onEnter(node) end end)
	b:SetScript("OnLeave", function() if node.onLeave then node.onLeave(node) end end)
	node.button = b
	return b
end

local function BuildNode(t, node)
	if node.kind == "item" then return BuildItem(t, node) end
	local f = t.frame
	local b = CreateFrame("Button", nil, f)
	b:SetSize(NODE, NODE)
	b:RegisterForClicks(node.onRightClick and "AnyUp" or "LeftButtonUp")
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetTexture(Media.texture.glow)
	b.glow:SetPoint("CENTER")
	b.glow:SetSize(NODE * 2.2, NODE * 2.2)
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetTexture(Media.texture.diamond)
	b.fill:SetAllPoints(b)
	b.rim = b:CreateTexture(nil, "ARTWORK", nil, 1)
	b.rim:SetTexture(Media.texture.diamondRim)
	b.rim:SetAllPoints(b)
	b.icon = b:CreateTexture(nil, "OVERLAY")
	b.icon:SetPoint("CENTER")
	b.icon:SetSize(ICON, ICON)
	-- The node's own news, such as mail waiting: a dot off its top corner.
	b.dot = b:CreateTexture(nil, "OVERLAY", nil, 2)
	b.dot:SetTexture(Media.texture.chipDisc)
	b.dot:SetSize(BADGE, BADGE)
	b.dot:SetPoint("CENTER", b, "TOPRIGHT", -4, -4)
	b.dot:Hide()
	b.stub = f:CreateTexture(nil, "BACKGROUND")
	b.stub:SetTexture(Media.texture.flat)
	b.junction = f:CreateTexture(nil, "ARTWORK")
	b.junction:SetTexture(Media.texture.diamond)
	b.junction:SetSize(JUNCTION, JUNCTION)
	b.label = W.Text(f, "label", "RIGHT")
	-- A node's own news under its stub, and its stub filling as a lane does:
	-- the N.I.F.E.C.'s track and how far through it (Joe's option D).
	b.sub = W.Text(f, "opSub", "RIGHT")
	b.sub:SetWordWrap(false)
	b.sub:Hide()
	b.lane = f:CreateTexture(nil, "ARTWORK")
	b.lane:SetTexture(Media.texture.flat)
	b.lane:SetHeight(1.5)
	b.lane:Hide()
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			if node.onRightClick then node.onRightClick(node) end
			return
		end
		t:Toggle(node.key)
	end)
	-- Over its node, a hidden label pops out.
	b:SetScript("OnEnter", function() node.hover = true t:Extend() end)
	b:SetScript("OnLeave", function() node.hover = nil t:Extend() end)
	node.button = b
	return b
end

-- The subtitle's widest, as a quest's text block is.
local SUB_W = 170

--- A node's subtitle and lane, from its owner's subtitle() and progress():
--  text or nil, 0 to 1 or nil. Cheap enough for the owner to call on a tick.
function Proto:Decorate(key)
	local node = self:Node(key)
	local b = node and node.button
	if not (b and b.sub and b:IsShown()) then
		if b and b.sub then b.sub:Hide() b.lane:Hide() end
		return
	end
	local text = node.subtitle and node.subtitle() or nil
	local p = node.progress and node.progress() or nil
	local a = Palette.c.accent
	b.sub:SetText(text or "")
	b.sub:SetWidth(math.max(1, math.min(SUB_W, math.ceil(b.sub:GetStringWidth() or 0))))
	W.Color(b.sub, Palette.c.textDim)
	b.sub:SetShown(text ~= nil and text ~= "")
	b.lane:SetVertexColor(a[1], a[2], a[3], 1)
	b.lane:SetWidth(math.max(0.01, STUB * math.max(0, math.min(1, p or 0))))
	b.lane:SetShown(p ~= nil)
end

--- Labels shown only over their node, or always (the default).
function Proto:LabelsOnHover()
	local owner = LABEL_OWNER[self.name]
	local cfg = owner and A.Config:Module(owner)
	return cfg and cfg.labelsOnHover and true or false
end

--- Every node's lit or idle look, from its owner's isOpen.
function Proto:Paint()
	local f = self.frame
	if not f then return end
	local c = Palette.c
	local a = c.accent
	f.strand:SetVertexColor(a[1], a[2], a[3], 0.55)
	W.Tint(f.capTop, a, 0.4)
	W.Tint(f.capBottom, a, 0.4)
	for _, node in ipairs(self.nodes) do
		local b = node.button
		if b and node.kind == "item" then
			if node.decorate then node.decorate(node) end
		elseif b then
			-- Lit while its branch is open, or while it is active (music playing).
			local lit = (node.isOpen and node.isOpen()) or (node.active and node.active())
			lit = lit and true or false
			node.lit = lit
			-- Open, not merely active: a playing node's name still tucks away.
			node.branchOpen = (node.isOpen and node.isOpen()) and true or false
			Media:SetIcon(b.icon, type(node.icon) == "function" and node.icon() or node.icon)
			local dot = node.badge and node.badge() and true or false
			b.dot:SetShown(dot)
			-- The design's info blue (README: Mail's and What's new's dots); in
			-- the text colour on a lit node, which is accent all over.
			if dot then W.Tint(b.dot, lit and c.text or (c.info or a), 1) end
			if lit then
				W.Tint(b.fill, a, 1)
				W.Tint(b.rim, a, 1)
				b.icon:SetVertexColor(20 / 255, 16 / 255, 31 / 255, 1)
				W.Tint(b.glow, a, 0.8)
				b.glow:Show()
				b.stub:SetVertexColor(a[1], a[2], a[3], 1)
				W.Tint(b.junction, a, 1)
				b.junction:Show()
			else
				-- Through W.Tint too, which drops the accent token the lit look
				-- left on it: otherwise a skin change repaints an idle node lit.
				W.Tint(b.fill, { 14 / 255, 11 / 255, 32 / 255 }, 0.85)
				W.Tint(b.rim, a, 0.6)
				b.icon:SetVertexColor(1, 1, 1, 0.8)
				b.glow:Hide()
				b.stub:SetVertexColor(a[1], a[2], a[3], 0.35)
				b.junction:Hide()
			end
			b.stub:SetHeight(lit and 1.5 or 1)
			W.Color(b.label, { a[1], a[2], a[3], 0.5 })
		end
	end
	self:PaintTail()
	-- A branch opening or shutting shows or tucks its stub (labels on hover).
	if self:LabelsOnHover() then self:Extend() end
end

--- Which way the stubs point: toward the middle of the screen, from wherever
--  the root is. -1 is left, as on the right-hand edge.
function Proto:Side()
	local r = self.root
	-- From its edges, in UIParent units, as everything placed is measured.
	local x = r and A.Movers.PointAt(r, "CENTER")
	if not x then return -1 end
	return (x > (UIParent:GetWidth() or 0) / 2) and -1 or 1
end

--- Lay the trunk out again: the nodes that are available, in order, 72 apart
--  (36 above a quest) under the root, the strand between its two end-caps.
function Proto:Refresh()
	local f = self.frame or Build(self)
	local r = self.root
	if not (r and r:IsShown()) then
		f:Hide()
		-- Item owners may have hung things beside their nodes that are not
		-- the trunk's children; they hear of it too.
		for _, node in ipairs(self.nodes) do
			if node.kind == "item" and node.decorate and node.button then node.decorate(node) end
		end
		return
	end
	f:SetScale(A.db.profile.scale or 1)
	f:ClearAllPoints()
	f:SetPoint("TOP", r, "BOTTOM", 0, -(self.capGap or CAP_GAP))

	local side = self:Side()
	self.side = side
	table.sort(self.nodes, ByOrder)
	-- Which are up first: a node's room below it depends on the next one up.
	local up, below, after = {}, {}, nil
	for i, node in ipairs(self.nodes) do
		up[i] = not node.available or node.available()
	end
	for i = #self.nodes, 1, -1 do
		below[i] = after
		if up[i] then after = self.nodes[i] end
	end
	local y, shown, lastY = -CAP / 2 - FIRST, 0, nil
	for i, node in ipairs(self.nodes) do
		local b = node.button or BuildNode(self, node)
		local on = up[i]
		b:SetShown(on)
		if on then
			shown, lastY = shown + 1, y
			b:ClearAllPoints()
			b:SetPoint("CENTER", f, "TOP", 0, y)
			node.y = y
			y = y - StepOf(node, below[i])
		end
		if node.kind ~= "item" then
			b.stub:SetShown(on)
			b.label:SetShown(on)
		end
		if on and node.kind ~= "item" then
			b.stub:ClearAllPoints()
			b.stub:SetWidth(STUB)
			if side < 0 then
				b.stub:SetPoint("RIGHT", b, "LEFT", 0, 0)
				b.junction:SetPoint("CENTER", b.stub, "LEFT", 0, 0)
				b.label:SetJustifyH("RIGHT")
				b.label:ClearAllPoints()
				-- Close to its node, not out at the stub's far end as the board
				-- has it: there it read as detached from the trunk (Joe, in game).
				b.label:SetPoint("BOTTOMRIGHT", b.stub, "TOPRIGHT", -LABEL_GAP, 4)
				b.sub:SetJustifyH("RIGHT")
				b.sub:ClearAllPoints()
				b.sub:SetPoint("TOPRIGHT", b.stub, "BOTTOMRIGHT", -LABEL_GAP, -4)
				b.lane:ClearAllPoints()
				b.lane:SetPoint("RIGHT", b.stub, "RIGHT", 0, 0)
			else
				b.stub:SetPoint("LEFT", b, "RIGHT", 0, 0)
				b.junction:SetPoint("CENTER", b.stub, "RIGHT", 0, 0)
				b.label:SetJustifyH("LEFT")
				b.label:ClearAllPoints()
				b.label:SetPoint("BOTTOMLEFT", b.stub, "TOPLEFT", LABEL_GAP, 4)
				b.sub:SetJustifyH("LEFT")
				b.sub:ClearAllPoints()
				b.sub:SetPoint("TOPLEFT", b.stub, "BOTTOMLEFT", LABEL_GAP, -4)
				b.lane:ClearAllPoints()
				b.lane:SetPoint("LEFT", b.stub, "LEFT", 0, 0)
			end
			b.label:SetText(tostring(type(node.label) == "function" and node.label() or node.label or ""):upper())
			self:Decorate(node.key)
		elseif node.kind ~= "item" then
			b.junction:Hide()
			b.sub:Hide()
			b.lane:Hide()
		end
	end
	local bottom = lastY and (lastY - LAST) or (-CAP / 2 - FIRST)
	self.bottom = bottom
	f.capTop:SetSize(CAP, CAP)
	f.capTop:ClearAllPoints()
	f.capTop:SetPoint("CENTER", f, "TOP", 0, -CAP / 2)
	f.capBottom:SetSize(CAP, CAP)
	f.strand:SetWidth(1.5)
	f:SetHeight(-bottom + CAP / 2)
	f:Show()
	self:Paint()
	self:Extend()
end

-- ---------------------------------------------------------------------------
-- the retract (6b)
--
-- In a fight the strand goes up into the top end-cap and each node, label and
-- line fades as the strand's end passes it; out of it, it comes back down.
-- Alpha and length on our own plain frames, so it runs in combat.
-- ---------------------------------------------------------------------------

--- Draw the strand out to how far it is extended now (`_travel`, 0 to 1).
function Proto:Extend()
	local f = self.frame
	if not (f and self.bottom) then return end
	local e = self._travel or 1
	local top = -CAP / 2
	local endY = top + (self.bottom - top) * e
	local onHover = self:LabelsOnHover()
	f.capBottom:ClearAllPoints()
	f.capBottom:SetPoint("CENTER", f, "TOP", 0, endY)
	f.capBottom:SetShown(e > 0)
	f.strand:ClearAllPoints()
	f.strand:SetPoint("TOP", f.capTop, "BOTTOM", 0, 0)
	f.strand:SetPoint("BOTTOM", f.capBottom, "TOP", 0, 0)
	f.strand:SetShown(e > 0)
	for _, node in ipairs(self.nodes) do
		local b = node.button
		if b and node.y then
			local a = math.max(0, math.min(1, (node.y - endY) / FADE))
			node.alpha = a
			b:SetAlpha(a)
			-- Nothing to click while it is gone.
			b:EnableMouse(a > 0.5)
			if node.kind ~= "item" then
				-- Quiet (the Toolbox trunk in a fight): nodes only, no labels.
				-- On hover only: a label and its stub show while the node is under
				-- the cursor, or while its branch is open - the stub is what joins
				-- the branch to its node (Joe).
				local tucked = onHover and not (node.hover or node.branchOpen)
				b.label:SetAlpha((self.quiet or tucked) and 0 or a)
				b.stub:SetAlpha(tucked and 0 or a)
				b.junction:SetAlpha(tucked and 0 or a)
				-- A subtitle and lane are news, not names: they stay out when
				-- the labels are tucked (Joe: what's playing, without a hover).
				b.sub:SetAlpha(self.quiet and 0 or a)
				b.lane:SetAlpha(a)
			elseif node.setAlpha then
				node.setAlpha(node, a)
			end
		end
	end
end

--- Up into the end-cap (true) or back down (false), over 300 ms; `instant`
--  for no slide. In flight it stays up whatever its owner asks, and comes
--  back to what was asked on landing.
function Proto:SetRetracted(on, instant)
	self.asked = on and true or false
	on = self.asked or Trunk.flying
	self.retracted = on and true or false
	self._want = on and 0 or 1
	-- A transient branch goes with its node rather than float beside nothing.
	if on then
		for _, node in ipairs(self.nodes) do
			if node.transient and node.close and node.isOpen and node.isOpen() then node.close(node) end
		end
	end
	local f = self.frame
	if instant or not (f and f:IsShown()) then
		W.StopSlide(f)
		self._travel = self._want
		self:Extend()
		return
	end
	W.DriveSlide(f, self, 1 / RETRACT, function(t) t:Extend() end)
end

-- ---------------------------------------------------------------------------
-- in flight
--
-- On a taxi every trunk goes up out of the way, as the World trunk does in a
-- fight - and with no tail: the active quest is no use on a griffin (Joe,
-- 2026-10-10). Watched here rather than through the I.F.E.C.'s flight
-- detection, which runs only while that module is on: UnitOnTaxi on the shared
-- tick, so both edges are caught, a disconnect mid-flight included.
-- ---------------------------------------------------------------------------

Trunk.flying = false
Trunk.flightListeners = {}

--- Told (true / false) when a flight starts or ends, keyed by owner.
function Trunk:OnFlight(key, fn)
	if type(fn) == "function" then Trunk.flightListeners[key] = fn end
end

function Trunk:SetFlying(on)
	on = on and true or false
	if on == Trunk.flying then return false end
	Trunk.flying = on
	for _, t in pairs(Trunk.list) do t:SetRetracted(t.asked or false) end
	for _, fn in pairs(Trunk.flightListeners) do pcall(fn, on) end
	return true
end

A:RegisterTicker(Trunk, function()
	Trunk:SetFlying(UnitOnTaxi and UnitOnTaxi("player") or false)
end)

--- The other combat energy (README "Two energies for trunks", the left
--  trunk): the nodes stay, the labels go and an open transient branch closes.
function Proto:SetQuiet(on)
	self.quiet = on and true or false
	if on then
		for _, node in ipairs(self.nodes) do
			if node.transient and node.close and node.isOpen and node.isOpen() then node.close(node) end
		end
	end
	self:Extend()
end

--- The tail: what stays out while retracted, a dotted stub under the top
--  end-cap ending in a small diamond. Its owner writes beside it and shows it.
function Proto:Tail()
	if self.tail then return self.tail end
	local f = self:Frame()
	local t = CreateFrame("Frame", nil, f)
	t:SetSize(TAIL_NODE, CAP + TAIL + TAIL_NODE)
	t:SetPoint("TOP", f, "TOP", 0, -CAP)
	t.dashes = {}
	for i = 0, math.floor(TAIL / (DASH + DASH_GAP)) - 1 do
		local d = t:CreateTexture(nil, "BACKGROUND")
		d:SetTexture(Media.texture.flat)
		d:SetSize(1.5, DASH)
		d:SetPoint("TOP", t, "TOP", 0, -i * (DASH + DASH_GAP))
		t.dashes[#t.dashes + 1] = d
	end
	local b = CreateFrame("Frame", nil, t)
	b:SetSize(TAIL_NODE, TAIL_NODE)
	b:SetPoint("CENTER", t, "TOP", 0, -TAIL - TAIL_NODE / 2)
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetTexture(Media.texture.diamond)
	b.fill:SetAllPoints(b)
	b.rim = b:CreateTexture(nil, "ARTWORK", nil, 1)
	b.rim:SetTexture(Media.texture.diamondRim)
	b.rim:SetAllPoints(b)
	t.node = b
	t:Hide()
	self.tail = t
	self:PaintTail()
	return t
end

--- The tail's ink: dots in the accent, the diamond hollow with an accent rim.
function Proto:PaintTail()
	local t = self.tail
	if not t then return end
	local a = Palette.c.accent
	for _, d in ipairs(t.dashes) do d:SetVertexColor(a[1], a[2], a[3], 0.55) end
	W.Tint(t.node.fill, { 14 / 255, 11 / 255, 32 / 255 }, 0.9)
	W.Tint(t.node.rim, a, 1)
end

-- ---------------------------------------------------------------------------
-- nodes and branches
-- ---------------------------------------------------------------------------

--- The trunk's own frame, made if it is not yet: owners parent what they
--  draw beside their nodes to it, so it scales and fades with the trunk.
function Proto:Frame()
	return self.frame or Build(self)
end

--- How much strand is left for item nodes, in the trunk's units: from its
--  first node to FLOOR above the screen's bottom, less the room every shown
--  branch node takes. Nil while the trunk is not up.
--
--  Asked before the items are placed, so a branch node counts LEAD when an
--  item node is next in order at all: the room only matters when one shows.
function Proto:Room()
	local f = self.frame
	if not (f and self.root and self.root:IsShown()) then return nil end
	local _, top = A.Movers.PointAt(self.root, "BOTTOM")
	if not top then return nil end
	local k = (UIParent:GetEffectiveScale() or 1) / (f:GetEffectiveScale() or 1)
	local room = (top * k) - (self.capGap or CAP_GAP) - CAP / 2 - FIRST - LAST - FLOOR * k
	table.sort(self.nodes, ByOrder)
	local nodes = self.nodes
	for i, node in ipairs(nodes) do
		if node.kind ~= "item" and (not node.available or node.available()) then
			local nxt
			for j = i + 1, #nodes do
				local n = nodes[j]
				if n.kind == "item" or not n.available or n.available() then nxt = n break end
			end
			room = room - StepOf(node, nxt)
		end
	end
	return room
end

--- The frame the trunk hangs from, or nil to take it down.
function Proto:SetRoot(frame)
	self.root = frame
	self:Refresh()
end

--- Add, or replace, a node. opts: icon (name or function), label (text or
--  function), order, open(node), close(node), isOpen(), available(); badge()
--  for a dot on the node, menu for a node that opens a menu rather than a
--  branch, transient for a branch that closes when the trunk retracts,
--  active() to light it with no branch open, onRightClick(node).
function Proto:AddNode(key, opts)
	local node
	for _, n in ipairs(self.nodes) do
		if n.key == key then node = n end
	end
	if not node then
		node = { key = key }
		self.nodes[#self.nodes + 1] = node
	end
	for k, v in pairs(opts) do node[k] = v end
	if self.frame then self:Refresh() end
	return node
end

function Proto:Node(key)
	for _, n in ipairs(self.nodes) do
		if n.key == key then return n end
	end
end
--- Open a node's branch, closing whichever other one is open; or close it
--  if it is the open one.
function Proto:Toggle(key)
	local node = self:Node(key)
	if not node then return end
	-- A menu is not a branch: it leaves the open one alone.
	if node.menu then
		if node.open then node.open(node) end
		return
	end
	if node.isOpen and node.isOpen() then
		if node.close then node.close(node) end
	else
		for _, other in ipairs(self.nodes) do
			if other ~= node and other.isOpen and other.isOpen() and other.close then
				other.close(other)
			end
		end
		if node.open then node.open(node) end
	end
	self:Paint()
end

--- Put a branch panel beside a node: its trunk-side edge at the stub's end,
--  centred on the node, kept on the screen.
function Proto:Place(key, panel)
	local node = self:Node(key)
	local b = node and node.button
	if not (b and b:IsShown() and panel) then return false end
	-- Kept on the screen by working it out, not by the client's clamp: a
	-- branch off a low node at a big HUD scale would hang off the bottom.
	local dy = 0
	local _, ny = A.Movers.PointAt(b, "CENTER")
	if ny then
		local k = (panel:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
		local half, h = (panel:GetHeight() or 0) * k / 2, UIParent:GetHeight() or 0
		local MARGIN = 8
		if ny - half < MARGIN then
			dy = MARGIN - (ny - half)
		elseif ny + half > h - MARGIN then
			dy = (h - MARGIN) - (ny + half)
		end
		dy = dy / k
	end
	panel:ClearAllPoints()
	if (self.side or -1) < 0 then
		panel:SetPoint("RIGHT", b.stub, "LEFT", -JUNCTION / 2, dy)
	else
		panel:SetPoint("LEFT", b.stub, "RIGHT", JUNCTION / 2, dy)
	end
	if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
	return true
end

-- ---------------------------------------------------------------------------
-- branch panels, and the panel vocabulary's heading
-- ---------------------------------------------------------------------------

-- README "Trunks": a branch panel is glass at r 22 with a shadow.
local BRANCH_CORNER = 22

--- A branch panel for this trunk, `width` wide and hidden. A child of the
--  trunk's frame, so it scales and fades with it. Escape closes it, and its
--  node repaints however it opens or shuts; an owner adding its own OnShow or
--  OnHide hooks them rather than setting them.
function Proto:Branch(name, width)
	local f = self:Frame()
	local p = A.Glass.CreatePanel(f, {
		corner = BRANCH_CORNER, shadow = A.db.profile.glass.shadow, name = ADDON .. name,
	})
	p:SetFrameLevel(f:GetFrameLevel() + 20)
	p:SetWidth(width)
	p:EnableMouse(true)
	p:Hide()
	local t = self
	p:SetScript("OnShow", function() t:Paint() end)
	p:SetScript("OnHide", function() t:Paint() end)
	if _G.UISpecialFrames then table.insert(_G.UISpecialFrames, p:GetName()) end
	Trunk.SkinBranch(p)
	return p
end

--- The reading fill, again after anything that puts the glass tint back.
function Trunk.SkinBranch(p)
	p:ApplySkin()
	p:SetFillColor(Palette:ReadingFill())
end

local Head = {}

--- Its label and the hint on the strand's end ("" for none).
--- Upper case and letter-spaced, a whole UTF-8 character at a time, with any
--  colour escape (|cAARRGGBB, |r) passed through whole: spaced or upper-cased
--  it stops being one and prints as text (Joe, on What's new).
local function Spaced(s)
	local out, i, chars = {}, 1, 0
	while i <= #s do
		local esc = s:match("^|c%x%x%x%x%x%x%x%x", i) or s:match("^|r", i)
		if esc then
			out[#out + 1] = esc
			i = i + #esc
		else
			local ch = s:match("^[%z\1-\127\194-\244][\128-\191]*", i) or s:sub(i, i)
			-- A space between characters, never beside an escape's edge.
			out[#out + 1] = (chars > 0 and " " or "") .. ch:upper()
			chars = chars + 1
			i = i + #ch
		end
	end
	return table.concat(out)
end
Trunk.Spaced = Spaced

function Head:Set(label, hint)
	-- Letter-spaced in the string: the client has no letter-spacing.
	self.label:SetText(Spaced(tostring(label or "")))
	self.hint:SetText(hint or "")
	self.strand:ClearAllPoints()
	self.strand:SetPoint("LEFT", self.label, "RIGHT", 8, 0)
	if (hint or "") ~= "" then
		self.strand:SetPoint("RIGHT", self.hint, "LEFT", -8, 0)
	else
		self.strand:SetPoint("RIGHT", self, "RIGHT", 0, 0)
	end
	self:Paint()
end

--- Filled junction, or hollow for a section played down (README: Junk).
function Head:Paint(hollow)
	if hollow ~= nil then self.hollow = hollow end
	local a = Palette.c.accent
	self.dot:SetTexture(self.hollow and Media.texture.diamondRim or Media.texture.diamond)
	self.dot:SetVertexColor(a[1], a[2], a[3], self.hollow and 0.5 or 1)
	W.Color(self.label, { a[1], a[2], a[3], self.hollow and 0.5 or 0.7 })
	self.strand:SetVertexColor(a[1], a[2], a[3], self.hollow and 0.15 or 0.25)
	W.Color(self.hint, Palette.c.textDim)
end

--- A section heading in the panel vocabulary (README "Panel vocabulary"): a
--  7 px junction, the label, and a 1 px strand out to the right edge with a
--  count or hint on its end. Anchor its LEFT and RIGHT; it is 14 tall.
function Trunk.Head(parent)
	local h = CreateFrame("Frame", nil, parent)
	h:SetHeight(14)
	h.dot = h:CreateTexture(nil, "ARTWORK")
	h.dot:SetSize(7, 7)
	h.dot:SetPoint("LEFT", h, "LEFT", 0, 0)
	h.label = W.Text(h, "tbSection", "LEFT")
	h.label:SetPoint("LEFT", h.dot, "RIGHT", 8, 0)
	h.hint = W.Text(h, "tbLabel", "RIGHT")
	h.hint:SetPoint("RIGHT", h, "RIGHT", 0, 0)
	h.strand = h:CreateTexture(nil, "ARTWORK")
	h.strand:SetTexture(Media.texture.flat)
	h.strand:SetHeight(1)
	for k, v in pairs(Head) do h[k] = v end
	h:Set("", "")
	return h
end
