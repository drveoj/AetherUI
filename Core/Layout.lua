--[[--------------------------------------------------------------------------
	Lattice :: Layout

	THE LAYOUT STRING: a whole arrangement of the HUD as one line of text, to
	share, keep, or ship as a preset (parent model phase C; Joe's decision 5).

	    LAT1;b=1,2;bar1=spine,BOTTOM,CENTER,0,-96;chat=screen,BOTTOMLEFT,...

	  LAT1      the version. Anything else is refused, not guessed at.
	  b=        the numbered action bars that are on. Every other is OFF: a
	            layout made around two bars has nothing to say about a third,
	            and leaving one on where the last layout put it is two layouts
	            at once.
	  k=        of the bars b= switches on, the ones showing key chips; the
	            rest show none. Left out, a layout says nothing about chips
	            and leaves them as they are. The Block seed says so (strands
	            brief 9c).
	  name=parent,point,relPoint,x,y
	            EVERY node, the same way: its `point` at x,y units from its
	            parent's `relPoint`. The top of every tree hangs from `screen` -
	            the main block from its centre, chat and the trunks from their
	            edge - so nothing is a position on the canvas.
	            HUD UNITS, every one: units at the player's own HUD scale,
	            whatever the node's own scale (Joe, 2026-10-08). At the scale
	            fitted to the monitor (A:FittedScale) a HUD unit is a pixel, on
	            any screen. A node's own units carry settings the string does
	            not - a bar's base size, the pet's scale, chat at UIParent's - so
	            in those the same string landed differently on two profiles.

	            NO SCALE IN THE STRING. The HUD scale is the player's: the
	            monitor's arithmetic, or their own slider, and never overwritten
	            (54d8cab). The first version carried it and set 0.71 on everyone,
	            which on a 1690-tall screen drew the whole HUD half as big again
	            (Joe, 2026-10-08).
	  barN=parent,point,relPoint,x,y,CxR,px
	            a bar adds its SHAPE (columns x rows over its buttons) and its
	            button SIZE in px, as it is drawn - the strands brief's seeds are
	            parents and shapes, and a string without them cannot say one.
	            Not the extra-action button: it is one button.
	  barN=...,CxR,px,down
	            a bar whose buttons run down its columns rather than across its
	            rows. Without it, C is the row length; with it, R is the column
	            length - the line that keeps its length when the button count
	            changes (Fit). Cells past the button count are blanks.
	  barN=...,CxR,px,braidS
	            a bar braided onto the bar it hangs from, S buttons along its
	            edge (left off for 0). Its x, y are written but not obeyed: the
	            seat follows from the sizes (Core/Braids.lua). After `down`
	            where both are written; either order reads.
	  chat=parent,point,relPoint,x,y,WxH
	            the chat window adds its SIZE. It is the one node whose size is
	            the player's to set, and a layout that placed it without its size
	            promised nothing about the corner it sits in: a wide window ran
	            under the capsule block (Joe, 2026-10-08).
	            Its size is in ITS OWN units, not HUD units: its text, its edit
	            box and its smallest size are all in UIParent's, so the same
	            numbers show the same lines on any screen. And its position is
	            the GLASS you see, not ChatFrame1 inside it - the panel and the
	            edit box hang below the frame, and 24 from the bottom put them
	            off the screen.

	TWO FORMS OF ONE STRING (Joe, 2026-10-08). The readable one above is the
	truth - Decode, Matches and the presets in Core/Presets.lua are written in
	it, so a preset can be read and diffed. What a player SHARES is the same
	text Deflated and Base64'd behind `!LAT1!`, through the client's own
	C_EncodingUtil - the pipeline Blizzard's Cooldown Viewer share string and
	ElvUI's `!E2!` use, without the CBOR step: our own text is already compact,
	and it is what gets validated. Import takes either form; the version in
	the prefix refuses another one before anything is unpacked.

	WHY UNITS AND NOT FRACTIONS (Joe, 2026-10-08). The first version stored a
	screen node as fractions of the screen and its children in units. On a
	narrower screen the player then slid in towards the centre by its fraction
	while the target stayed the same 349 units to its right, and the whole
	block went lopsided. One unit throughout keeps a block rigid; the anchor is
	what ties it to the right part of the screen. Being set free of the parent
	a module would give a node is just naming `screen`.

	Records come out sorted, so the same arrangement is always the same text.

	REFUSED, WHOLE: a string of another version, one naming a node this addon
	has never had, one whose bonds would loop, one hanging the target off
	anything but the player - the two are one piece - and anything during
	combat, where re-anchoring frames with secure children is protected.
	Nothing is half applied.

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

--- The top of every tree. Not a node: nothing hangs it anywhere.
local SCREEN = "screen"

--- Nodes that are one piece with another and can only hang from it.
local PAIRED = { target = "player" }

local function round(v) return math.floor((v or 0) + 0.5) end

--- A number, and a finite one. "nan" and "inf" parse; neither is a position.
local function Num(v)
	local n = tonumber(v)
	if n and n == n and n ~= math.huge and n ~= -math.huge then return n end
	return nil
end

--- How big one of a node's own units is against a HUD unit - a unit at the
--  HUD scale, which is what the string is written in. The store and SetPoint
--  work in the node's own units, which carry every scale the string does not:
--  the bars' base size and their module's scale, the pet's and the ToT's own,
--  chat at UIParent's. Written in those, one string landed differently for two
--  players with different sliders. 1 for a node with no frame to ask.
local function Ratio(name)
	local e = A.Movers.registry[name]
	local f = (e and e.frame) or (A.Movers.nodes and A.Movers.nodes[name])
	local fe = f and f:GetEffectiveScale()
	local ue = UIParent and UIParent:GetEffectiveScale()
	local s = A.db and A.db.profile.scale or 1
	if not (fe and ue and fe > 0 and ue > 0 and s > 0) then return 1 end
	return fe / (ue * s)
end
Layout.Ratio = Ratio

--- UIParent's size in HUD units: the HUD's frames are at `scale`, so the
--  screen is divided by it. Only Resolve and the capture note need it now.
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

--- Of the bars that are on, which show their key chips, as the profile has
--  it now.
local function KeysNow()
	local AB = A.GetModule and A:GetModule("actionbars")
	if not AB or not AB.KeysShown then return {} end
	local out, on = {}, BarsNow() or {}
	for _, id in ipairs(Bars()) do
		if on[id] then out[id] = AB:KeysShown(id) end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- a bar's shape and size
--
-- ROWS IS WHAT A BAR STORES and columns fall out of it (ActionBars LayoutBar),
-- so a shape is written C x R from the bar's button count and applied as R.
--
-- SIZE IS THE BUTTON AS DRAWN: the bar's base size times its scale, and the
-- scale is the dock's - buttons, gap and pad together. So Apply sets the
-- SCALE that gives the stated px and leaves the base size alone; setting the
-- size and a scale of 1 would draw the same buttons with different gaps.
-- ---------------------------------------------------------------------------

local function BarId(name)
	local id = type(name) == "string" and name:match("^bar(%w+)$")
	if id and id ~= "extra" then return id end
	return nil
end

--- The bar's config, its live button count, and the base size its scale
--  multiplies. Nil when the bars module has no such bar.
local function BarParts(id)
	local AB = A.GetModule and A:GetModule("actionbars")
	local cfg = AB and AB.BarConfig and AB:BarConfig(id)
	if not cfg then return nil end
	local n
	-- The buttons SHOWING, as LayoutBar counts them: a bar keeps surplus
	-- buttons hidden when it is asked for fewer.
	for _, bar in ipairs(AB.bars or {}) do
		if tostring(bar.id) == tostring(id) and bar.buttons and #bar.buttons > 0 then
			n = math.min(#bar.buttons, bar.shown or #bar.buttons)
		end
	end
	n = n or cfg.buttons or 12
	local base = cfg.size or A.Config:Module("actionbars").size or 36
	return cfg, n, base
end

--- The cols and rows n buttons are drawn in (strands brief: cols x rows with a
--  wrap). The line in the wrap's direction keeps its length as n changes:
--  across keeps cols, down keeps rows, and the other falls out, so a stance
--  bar written as a column of 12 is a column of 3 on three forms. Cells past
--  n are blanks; a wholly empty row or column is never made. A config from
--  before cols has only rows, and asks for that many rows.
local function Fit(n, cols, rows, wrap)
	-- A bar with nothing showing - a class with no forms - is drawn as one
	-- button's worth to aim at (LayoutBar), so it has a shape of one.
	n = math.max(1, n or 1)
	local function clamp(v) return math.max(1, math.min(v, n)) end
	if wrap == "down" then
		rows = clamp(rows or math.ceil(n / clamp(cols or 1)))
		return math.ceil(n / rows), rows
	end
	cols = clamp(cols or math.ceil(n / clamp(rows or 1)))
	return cols, math.ceil(n / cols)
end
Layout.Fit = Fit

--- Nodes whose record carries a size, WxH in the node's OWN units: the chat
--  window, whose text and smallest size are in UIParent's.
local SIZED = { chat = true }

--- A sized node's size now, in its own units, or nil.
local function NodeSize(name)
	local e = SIZED[name] and A.Movers.registry[name]
	local f = e and e.frame
	local w, h = f and f:GetWidth(), f and f:GetHeight()
	if not (w and h and w > 0 and h > 0) then return nil end
	return round(w), round(h)
end

--- How far the glass a player sees reaches past a node's frame, as the
--  offset from the frame's `point` to the glass's, in the node's own units.
--  The chat's panel and edit box hang off ChatFrame1 - ten either side and
--  forty-two below - and a record places what is seen. 0, 0 for any other
--  node, or a chat with no panel to measure.
local function Glass(name, point)
	if name ~= "chat" then return 0, 0 end
	local CM = A.GetModule and A:GetModule("chat")
	if not (CM and CM.panel and CM.Insets) then return 0, 0 end
	local l, b, r, t = CM:Insets()
	local dx = point:find("LEFT") and -l or point:find("RIGHT") and r or (r - l) / 2
	local dy = point:find("BOTTOM") and -b or point:find("TOP") and t or (t - b) / 2
	return dx, dy
end

--- The shape a bar is drawn in, its button px and its wrap, now. A braided
--  bar is drawn at its braid root's size, so that is its px.
local function BarShape(id)
	local cfg, n, base = BarParts(id)
	if not cfg then return nil end
	local wrap = cfg.wrap == "down" and "down" or "across"
	local cols, rows = Fit(n, cfg.cols, cfg.rows, wrap)
	local AB = A.GetModule and A:GetModule("actionbars")
	local px = AB and AB.ButtonPx and AB:ButtonPx(id) or base * (cfg.scale or 1)
	return cols, rows, round(px), wrap
end
Layout.BarShape = BarShape

-- ---------------------------------------------------------------------------
-- the share form
-- ---------------------------------------------------------------------------

local SHARE = "^!(LAT%d+)!(.*)$"

--- The string out of whatever came with it. A layout copied from a forum post,
--  a Discord message or a preset table arrives in quotes, after `layout =`,
--  under a comment - and the player cannot see that as a different thing from
--  the string. Packed first: its Base64 holds no `;`, the readable form no `!`.
--  Nothing that looks like either comes back as it was, to be refused as such.
local function Lift(text)
	return text:match("!LAT%d+![%w+/=]*")
		or text:match("LAT%d+;[%w;=,%._%-]*")
		or text
end

--- The readable string, Deflated and Base64'd behind its version. Plain text
--  back on a client without the encoder - every one this ships for has it.
function Layout:Pack(text)
	local E = C_EncodingUtil
	if type(text) ~= "string" or not (E and E.CompressString and E.EncodeBase64) then
		return text
	end
	local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
	local ok, packed = pcall(function()
		return E.EncodeBase64(E.CompressString(text, method))
	end)
	if not ok or type(packed) ~= "string" or packed == "" then return text end
	return "!" .. Layout.VERSION .. "!" .. packed
end

--- Back to the readable form. A string that is not packed comes back as it
--  is; one that is packed and will not open is refused, saying why.
function Layout:Unpack(text)
	if type(text) ~= "string" then return text end
	local version, body = text:match(SHARE)
	if not version then return text end
	if version ~= Layout.VERSION then
		return nil, A.F(L.layout.err.version, ("!" .. version .. "!"):sub(1, 12))
	end
	local E = C_EncodingUtil
	if not (E and E.DecodeBase64 and E.DecompressString) then
		return nil, L.layout.err.packed
	end
	local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
	local ok, plain = pcall(function()
		local raw = E.DecodeBase64(body)
		return raw and E.DecompressString(raw, method)
	end)
	if not ok or type(plain) ~= "string" or plain == "" then
		return nil, L.layout.err.packed
	end
	return plain
end

-- ---------------------------------------------------------------------------
-- the string
-- ---------------------------------------------------------------------------

--- The arrangement on screen now, as one line.
function Layout:Encode()
	local profile = A.db.profile
	local anchors = profile.anchors or {}

	local parts = { Layout.VERSION }
	local on, bars = {}, BarsNow() or {}
	for _, id in ipairs(Bars()) do
		if bars[id] then on[#on + 1] = id end
	end
	parts[#parts + 1] = "b=" .. table.concat(on, ",")
	local keys, chips = {}, KeysNow()
	for _, id in ipairs(on) do
		if chips[id] then keys[#keys + 1] = id end
	end
	parts[#parts + 1] = "k=" .. table.concat(keys, ",")

	-- Only nodes this addon has. `__` entries are not positions - the lock
	-- pill's spot is one - and a profile can still hold one for a frame that is
	-- gone: the floating cast bars left `cast` and `targetcast` behind when the
	-- lanes replaced them. Written out, those made a string Decode refuses.
	local names, seen = {}, {}
	for name in pairs(anchors) do
		if KNOWN[name] then names[#names + 1] = name; seen[name] = true end
	end
	-- AND EVERY BAR ON SCREEN, moved or not. A bar nobody has dragged has no
	-- record, and leaving it out would leave its shape out - a seed made of
	-- untouched bars would say nothing at all.
	for name in pairs(A.Movers.registry) do
		if not seen[name] and KNOWN[name] and BarId(name) then names[#names + 1] = name end
	end
	table.sort(names)

	-- The bond where there is one; otherwise the node hangs from the screen,
	-- and its saved point and offset are already that. Offsets out of the
	-- node's own units into HUD units, from the glass a player sees. A bar
	-- adds its shape and button size.
	for _, name in ipairs(names) do
		local a = anchors[name]
		local lat = a and type(a.lat) == "table" and a.lat
		local r = Ratio(name)
		local function Out(parent, point, relPoint, x, y)
			local gx, gy = Glass(name, point)
			return ("%s=%s,%s,%s,%d,%d"):format(name, parent, point, relPoint,
				round((x + gx) * r), round((y + gy) * r))
		end
		local rec
		if lat and lat.parent and not a.free then
			rec = Out(lat.parent, tostring(lat.point), tostring(lat.relPoint), lat.x, lat.y)
		elseif a and a.point then
			rec = Out(SCREEN, a.point, a.relPoint or a.point, a.x, a.y)
		elseif not a then
			local parent, point, relPoint, x, y = A.Movers:Measure(name)
			if parent then rec = Out(parent, point, relPoint, x, y) end
		end
		if rec then
			local id = BarId(name)
			if id then
				local cols, rows, px, wrap = BarShape(id)
				if cols then
					rec = rec .. (",%dx%d,%d"):format(cols, rows, px)
					-- Down, said; across is what a shape means without it.
					if wrap == "down" then rec = rec .. ",down" end
					-- A braid: the slot along its host's edge, left off when 0.
					local slot = a and lat and not a.free and a.braid
					if slot then rec = rec .. ",braid" .. (slot ~= 0 and tostring(slot) or "") end
				end
			end
			local w, h = NodeSize(name)
			if w then rec = rec .. (",%dx%d"):format(w, h) end
			parts[#parts + 1] = rec
		end
	end
	return table.concat(parts, ";")
end

--- Read a string back, in either form. Returns the layout, or nil and the
--  reason in words.
function Layout:Decode(text)
	if type(text) ~= "string" then return nil, L.layout.err.empty end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil, L.layout.err.empty end
	local why
	text, why = Layout:Unpack(Lift(text))
	if not text then return nil, why end

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

			if k == "b" then
				for id in v:gmatch("[^,]+") do
					if not id:match("^%d$") then return bad(f) end
					out.bars[id] = true
				end
			elseif k == "k" then
				if out.keys then return bad(f) end
				out.keys = {}
				for id in v:gmatch("[^,]+") do
					if not id:match("^%d$") then return bad(f) end
					out.keys[id] = true
				end
			else
				if not KNOWN[k] then return nil, A.F(L.layout.err.unknown, k) end
				if out.records[k] then return bad(f) end
				local p = {}
				for x in (v .. ","):gmatch("([^,]*),") do p[#p + 1] = x end

				-- parent,point,relPoint,x,y - and for a bar, CxR,px after it, then
				-- `down` and a braid in either order - and nothing else. A canvas
				-- position from the first version (S or B in front) is refused
				-- here too.
				local isBar = BarId(k) ~= nil
				if not (#p == 5 or (isBar and #p >= 7 and #p <= 9) or (SIZED[k] and #p == 6)) then
					return bad(f)
				end
				local parent, x, y = p[1], Num(p[4]), Num(p[5])
				if not (parent == SCREEN or KNOWN[parent] or OWNED[parent]) then
					return nil, A.F(L.layout.err.unknown, parent)
				end
				if not (valid[p[2]] and valid[p[3]] and x and y) then return bad(f) end
				if PAIRED[k] and parent ~= PAIRED[k] then return bad(f) end
				local rec = { parent = parent, point = p[2], relPoint = p[3],
					x = round(x), y = round(y) }
				for j = 8, #p do
					local slot = p[j]:match("^braid(%-?%d*)$")
					if p[j] == "down" and not rec.wrap then
						rec.wrap = "down"
					elseif slot and rec.braid == nil then
						-- A BRAID: onto another strand, on one of the four seats.
						if not (BarId(parent) and A.Braids and A.Braids.EdgeOf(p[2], p[3])) then
							return bad(f)
						end
						rec.braid = tonumber(slot) or 0
					else
						return bad(f)
					end
				end
				if #p >= 7 then
					-- THE LIMITS ARE OPTIONS', so nothing Export writes is refused
					-- here: up to twelve buttons a bar, and a base size of 24-80 at
					-- a bar scale of 0.4-2.0 draws a button 10 to 160 px across.
					local cols, rows = p[6]:match("^(%d+)x(%d+)$")
					cols, rows = tonumber(cols), tonumber(rows)
					local px = Num(p[7])
					if not (cols and rows and cols >= 1 and rows >= 1 and cols <= 12
						and rows <= 12 and px and px >= 9 and px <= 160) then
						return bad(f)
					end
					rec.cols, rec.rows, rec.px = cols, rows, round(px)
				elseif #p == 6 then
					-- A window's size, in its own units. Bounded only by sense:
					-- the chat module clamps it to the smallest it can draw.
					local w, h = p[6]:match("^(%d+)x(%d+)$")
					w, h = tonumber(w), tonumber(h)
					if not (w and h and w >= 1 and h >= 1 and w <= 4000 and h <= 4000) then
						return bad(f)
					end
					rec.w, rec.h = w, h
				end
				out.records[k] = rec
			end
		end
	end

	-- Chips only on a bar the string switches on: a chip on a bar it leaves
	-- off says nothing anyone would see.
	for id in pairs(out.keys or {}) do
		if not out.bars[id] then return bad("k=" .. id) end
	end

	-- NO LOOPS. A node bonded to its own descendant is an anchor loop, which
	-- the client refuses - and through the spine, which belongs to the player.
	for name in pairs(out.records) do
		local p, hops = out.records[name].parent, 0
		while p and p ~= SCREEN and hops < 24 do
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

	-- SHAPES BEFORE THE BARS GO ON, so the one rebuild lays them out once. The
	-- scale is the one that draws the stated px over the bar's own base size.
	for name, r in pairs(layout.records) do
		local id = r.rows and BarId(name)
		if id then
			local cfg, _, base = BarParts(id)
			if cfg and base and base > 0 then
				cfg.cols, cfg.rows, cfg.wrap = r.cols, r.rows, r.wrap or "across"
				cfg.scale = r.px / base
			end
		end
	end

	-- Key chips, where the string says: on for the bars it names, off for the
	-- other bars it switches on. Painted by the rebuild below.
	if layout.keys then
		local AB = A.GetModule and A:GetModule("actionbars")
		for id in pairs(layout.bars) do
			local cfg = AB and AB.BarConfig and AB:BarConfig(id)
			if cfg then cfg.keys = layout.keys[id] and true or false end
		end
	end

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

	-- On the screen, a node its module would hang from another one is set free
	-- of it - that is what naming `screen` means. One it would not is simply
	-- placed; a node whose module is off now is taken at its word as well.
	local registry = A.Movers.registry
	for name, r in pairs(layout.records) do
		if r.parent == SCREEN then
			local e = registry[name]
			anchors[name] = { point = r.point, relPoint = r.relPoint, x = r.x, y = r.y,
				free = (not e or e.defaultParent) and true or nil }
		else
			anchors[name] = { lat = { parent = r.parent, point = r.point,
				relPoint = r.relPoint, x = r.x, y = r.y }, braid = r.braid }
		end
	end

	-- Every node on its new parent BEFORE anything is re-registered: a module
	-- re-registering a parent re-places its children, and one still on its old
	-- parent would be measured against that and lose the layout's bond. Then
	-- the bar scales onto the frames, then every node to its record. The HUD
	-- scale is the player's, and a layout leaves it alone.
	A.Movers:ResolveParents()
	A:Reconfigure()
	-- The chat window's size, through the chat module's own record of it, in
	-- the window's own units - before its glass is measured below.
	local rc = layout.records.chat
	local CM = rc and rc.w and A.GetModule and A:GetModule("chat")
	if CM and CM.RestoreSize and A.db.char then
		A.db.char.chat = A.db.char.chat or {}
		A.db.char.chat.w, A.db.char.chat.h = rc.w, rc.h
		CM:RestoreSize()
	end
	-- INTO EACH NODE'S OWN UNITS, now Reconfigure has put every scale on its
	-- frame, and from the glass a player sees to the frame inside it - before
	-- AdoptLayout places anything by them. Not rounded: a whole number of a
	-- node's own units reads back as another whole number of HUD units (160 of
	-- chat's is 113.6; 114 is 161).
	for name in pairs(layout.records) do
		local a, r = anchors[name], Ratio(name)
		local h = a and (a.lat or a)
		if h then
			local gx, gy = Glass(name, h.point)
			h.x, h.y = h.x / r - gx, h.y / r - gy
		end
	end
	A.Movers:AdoptLayout()
	-- Last: a braid's seat comes from its host's size, not the string's x, y,
	-- and only now is every bar its size and on its parent.
	if A.Braids then A.Braids:Refresh() end
	return true
end

--- Is the layout on screen now this one? The tour and the preset list ask.
--  Within a unit, because a bond measured back after placing can come back a
--  rounding away.
function Layout:Matches(layout)
	if not layout or not A.db then return false end
	local now = BarsNow()
	if now then
		for id, on in pairs(now) do
			if on ~= (layout.bars[id] and true or false) then return false end
		end
	end
	if layout.keys then
		for id, shown in pairs(KeysNow()) do
			if shown ~= (layout.keys[id] and true or false) then return false end
		end
	end

	local anchors = A.db.profile.anchors or {}
	local named = 0
	for name, r in pairs(layout.records) do
		named = named + 1
		local b = anchors[name]
		-- The record as the string would write it: its bond, or the screen - or,
		-- for a node with nothing saved, where it is measured to sit, the way
		-- Encode writes an untouched bar.
		local parent, h
		if b then
			local lat = type(b.lat) == "table" and b.lat.parent and not b.free and b.lat
			parent, h = lat and lat.parent or SCREEN, lat or b
		else
			local p, point, relPoint, x, y = A.Movers:Measure(name)
			if not p then return false end
			parent, h = p, { point = point, relPoint = relPoint, x = x, y = y }
		end
		if parent ~= r.parent or h.point ~= r.point or (h.relPoint or h.point) ~= r.relPoint then
			return false
		end
		-- A braid is its edge and slot; its offset follows from the sizes.
		local braid = b and b.braid
		if braid ~= r.braid then return false end
		-- In HUD units, from the glass a player sees, as the string has it.
		local k = Ratio(name)
		local gx, gy = Glass(name, h.point)
		if not braid and (math.abs(((h.x or 0) + gx) * k - r.x) > 1
			or math.abs(((h.y or 0) + gy) * k - r.y) > 1) then
			return false
		end
		-- A bar in another shape or size is another arrangement, wherever it is.
		-- The written shape fitted to the buttons the bar has NOW: a stance bar
		-- written as a column of 12 is a column of 3 for a warrior, and of 6
		-- for a druid, and is still the same arrangement.
		if r.rows then
			local id = BarId(name)
			local cols, rows, px, wrap = BarShape(id)
			local _, n = BarParts(id)
			local wantC, wantR = Fit(n or (r.cols * r.rows), r.cols, r.rows, r.wrap)
			if cols ~= wantC or rows ~= wantR or wrap ~= (r.wrap or "across")
				or math.abs((px or 0) - r.px) > 1 then
				return false
			end
		end
		-- A window of another size is another arrangement too.
		if r.w then
			local w, h = NodeSize(name)
			if not w or math.abs(w - r.w) > 2 or math.abs(h - r.h) > 2 then return false end
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

--- -1, 0 or 1 on each axis for one of the nine points.
local function Sides(point)
	local hx = point:find("LEFT") and -1 or point:find("RIGHT") and 1 or 0
	local vy = point:find("BOTTOM") and -1 or point:find("TOP") and 1 or 0
	return hx, vy
end

--- Where each node of a layout would sit on THIS screen, without placing
--  anything: its centre as x, y units from the screen's centre, and the
--  screen's size in the same units. For the tour's thumbnails, which used to
--  read the fractions straight off the string and have nothing to read now.
--
--  Sizes come from the live frames, so a node whose module is off counts as
--  a point. The spine runs from the player's right edge to the target's left.
function Layout:Resolve(layout)
	if not layout then return {}, 0, 0 end
	local sw, sh = ScreenIn(A.db and A.db.profile.scale)
	local registry, nodes = A.Movers.registry, A.Movers.nodes or {}
	-- In HUD units, like the offsets: a pet at 0.85 is 0.85 of its own width.
	-- A sized node's record is in its own units. (Chat's glass is not added:
	-- the thumbnails draw the capsules and the bars, not chat.)
	local function Size(name)
		local rec = layout.records[name]
		local k = Ratio(name)
		if rec and rec.w then return rec.w * k, rec.h * k end
		local e = registry[name]
		local f = (e and e.frame) or nodes[name]
		if not f then return 0, 0 end
		return (f:GetWidth() or 0) * k, (f:GetHeight() or 0) * k
	end

	local at, busy = {}, {}
	local function Place(name)
		if at[name] then return at[name] end
		if busy[name] then return nil end
		busy[name] = true

		local pos
		if OWNED[name] then
			-- Only the spine is owned, and it starts at the player's right edge.
			local p = Place(OWNED[name])
			if p then
				local pw = Size(OWNED[name])
				local t = layout.records.target
				local len = (t and t.parent == OWNED[name] and t.x) or Size(name)
				pos = { x = p.x + pw / 2 + len / 2, y = p.y }
			end
		else
			local r = layout.records[name]
			if r then
				local ax, ay
				if r.parent == SCREEN then
					local hx, vy = Sides(r.relPoint)
					ax, ay = hx * sw / 2, vy * sh / 2
				else
					local p = Place(r.parent)
					if p then
						local pw, ph = Size(r.parent)
						local hx, vy = Sides(r.relPoint)
						ax, ay = p.x + hx * pw / 2, p.y + vy * ph / 2
					end
				end
				if ax then
					local w, h = Size(name)
					local hx, vy = Sides(r.point)
					pos = { x = ax + r.x - hx * w / 2, y = ay + r.y - vy * h / 2 }
				end
			end
		end

		busy[name] = nil
		at[name] = pos
		return pos
	end

	for name in pairs(layout.records) do Place(name) end
	return at, sw, sh
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
		A.Errors:Export("layout", Layout:Pack(Layout:Encode()))
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
	if Layout.frame then Layout.frame.box:SetText(Layout:Pack(Layout:Encode())) end
	Say(L.layout.window.applied, true)
	return true
end

--- The window, with the arrangement on screen now in the box, selected.
function Layout:Show()
	local f = Build()
	f:SetScale(A.db.profile.scale or 1)
	-- The share form: this box is what a player copies to give to somebody.
	f.box:SetText(Layout:Pack(Layout:Encode()))
	Say("")
	f:Show()
	f:Raise()
	f.box:SetFocus()
	f.box:HighlightText()
end
