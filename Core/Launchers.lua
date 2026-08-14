--[[--------------------------------------------------------------------------
	AetherUI :: Launchers

	One place that knows how to find every "thing you can click to reach an
	addon", whatever shape it arrived in, and hands out a single list of entries
	that any surface can draw.

	Why this is a service and not part of a module
	----------------------------------------------
	The minimap drawer collected these first. The Toolbox rail wants the same
	set, and so does half the Toolbox's settings grid - three surfaces, one
	problem. Two copies of this code would drift the first time somebody fixed a
	bug in one of them, and two surfaces positioning the same borrowed frame is a
	fight nobody wins, so `Claim` exists to make exactly one of them the owner.

	There are two mechanisms and neither contains the other
	------------------------------------------------------
	"Launching an addon" is not a thing in WoW - an addon is loaded at login or
	it is not. What stands in for it:

	  * an LDB `launcher` object, the display-agnostic protocol Titan Panel and
	    friends consume;
	  * a minimap button, either made by LibDBIcon from an LDB object or rolled
	    by hand and parented onto Minimap.

	Plenty of addons offer one and not the other, and a great many offer neither.
	The dedupe key is the LDB object NAME, because that is what
	`LibDBIcon:Register(name, object, db)` keys `lib.objects[name]` on - so a
	button and an object of the same name are one addon, not two rows. Note that
	Register errors without `object.icon` and never inspects `object.type`, so a
	LibDBIcon button is not evidence that anything is a launcher.

	Four things about LDB that bite
	-------------------------------
	Read from the library (ninety lines) and from Titan's TitanLDB.lua, which is
	the most careful consumer on this machine.

	  * `pairs(dataobj)` RETURNS NOTHING. Every field lives in the library's
	    `attributestorage` behind an `__index` metamethod, and the metatable is
	    the string "access denied". Indexing works - `obj.icon` is served by the
	    metamethod - but walking one with plain `pairs` silently sees an empty
	    table. Use `ldb:pairs(obj)` if a walk is ever needed; nothing here needs
	    one, which is itself the safest answer.
	  * NEVER CACHE THE SCRIPTS. Titan re-reads `obj.OnClick` at the moment of
	    the click, deliberately: an addon that swaps its own handler after login
	    is normal, and a captured reference goes stale without ever erroring.
	  * Tooltip precedence is UNDEFINED in the spec - `.tooltip`, `OnTooltipShow`
	    and `OnEnter`/`OnLeave` all exist with no stated order, and Titan's own
	    comment says so. Their resolution is copied here rather than a new one
	    invented.
	  * `.tooltip` must not be a GameTooltip. Titan's header says so in four
	    exclamation marks.

	Everything foreign is pcall'd. These are other people's functions running
	inside our click handler; one throwing costs that row, not the drawer.

	An entry always has a frame
	---------------------------
	A launcher with no minimap button has nothing to position, so this file makes
	one - a plain Button carrying the object's icon. That keeps every consumer to
	a single job: place `entry.button`. `entry.owned` says whether the frame is
	ours, which decides whether it may be hidden: a borrowed button may carry a
	secure template and hiding a frame with a protected descendant is refused in
	combat, so borrowed ones move on alpha alone. Ours can do as they like.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = {}
A.Launchers = L

-- Skinning a borrowed button needs these, and they were locals in Minimap.lua
-- before the code moved. A pcall around the skin swallowed the nil and the
-- button simply kept its own bevel - which looked like the skin not applying
-- rather than like an error.
local W, Media, Palette = A.Widgets, A.Media, A.Palette

L.entries = {}     -- ordered, deterministic
L.byKey   = {}     -- key -> entry
L.owners  = {}     -- entry -> owner token
L.seen    = {}     -- frame -> entry, so a button is never collected twice

-- Widget methods captured unbound, so a collected button that has stomped its
-- own `SetPoint` - some do, to keep themselves welded to the ring - can still be
-- placed. Called as plain functions with the frame as the first argument. An
-- override on the button's own table cannot shadow a function we never look up
-- on it.
local RawSetParent, RawClearAllPoints, RawSetPoint, RawSetSize, RawGetName
do
	local probe = CreateFrame("Frame")
	RawSetParent      = probe.SetParent
	RawClearAllPoints = probe.ClearAllPoints
	RawSetPoint       = probe.SetPoint
	RawSetSize        = probe.SetSize
	RawGetName        = probe.GetName
end
L.RawSetParent, L.RawClearAllPoints = RawSetParent, RawClearAllPoints
L.RawSetPoint, L.RawSetSize, L.RawGetName = RawSetPoint, RawSetSize, RawGetName

local function Forbidden(f)
	if not f or not f.IsForbidden then return false end
	local ok, forbidden = pcall(f.IsForbidden, f)
	return (not ok) or forbidden
end

local function LDB()
	return LibStub and LibStub("LibDataBroker-1.1", true)
end

local function DBIcon()
	return LibStub and LibStub("LibDBIcon-1.0", true)
end

-- ---------------------------------------------------------------------------
-- what counts as somebody's minimap button
--
-- Lifted wholesale from Modules/Minimap.lua, where it was learned the hard way.
-- ---------------------------------------------------------------------------

-- Map pins are the hazard: Questie and HandyNotes put THOUSANDS of children on
-- the minimap and none of them is a button.
local PIN_PREFIX = {
	"^HandyNotes", "^TomTom", "^HereBeDragons", "^Questie", "^GatherMate",
	"^Routes", "^pin", "^Pin", "^Nx",
}

-- What an addon button tends to be called. Anything matching none of these is
-- assumed not to be one, which errs toward leaving things where they are.
--
-- MATCHED WITHOUT CASE, and written in lower case for it. There is no agreed
-- spelling of the word: Blizzard's own frames say MiniMapTracking and
-- MinimapBorder in the same interface, and addons follow whichever they read
-- first - SmartBuff's is SmartBuff_MiniMapButton, which every one of these
-- patterns missed. So it stayed on the ring beside the minimap while its own
-- broker launcher sat in the drawer, and the player had the same button twice.
local BUTTON_PATTERN = {
	"^libdbicon10_", "minimapbutton", "minimapframe", "minimapicon",
	"[%-_]minimap[%-_]", "minimap$", "^bt4",
}

local function Matches(name, list)
	for _, pat in ipairs(list) do
		if name:find(pat) then return true end
	end
	return false
end

--- Is this child of the minimap something we should collect?
local function IsAddonButton(frame, own)
	if type(frame) ~= "table" then return false end
	if own and own[frame] then return false end
	if L.seen[frame] then return false end
	if not frame.IsObjectType or not frame:IsObjectType("Frame") then return false end
	if Forbidden(frame) then return false end

	local ok, name = pcall(RawGetName, frame)
	if not ok or not name or name == "" then return false end

	-- Blizzard declares its globals securely and addons cannot, so this sorts
	-- the furniture from the arrivals without a list to keep up to date.
	if issecurevariable then
		local secure = select(1, issecurevariable(name))
		if secure then return false end
	end

	if Matches(name, PIN_PREFIX) then return false end
	-- Pins are numbered; buttons are not. A name ending in a digit is almost
	-- always the ninetieth copy of something.
	if name:find("%d$") and not name:find("^LibDBIcon10_") then return false end
	if not Matches(name:lower(), BUTTON_PATTERN) then return false end

	return true
end

-- ---------------------------------------------------------------------------
-- making a borrowed button placeable
-- ---------------------------------------------------------------------------

--- Stop a button putting itself back on the ring.
--
--  LibDBIcon's drag handlers recompute an angle from the cursor and re-anchor to
--  the minimap's centre every frame while held, and its own Show/Refresh do the
--  same on demand. `Lock` is the library's supported way to switch that off and
--  it survives a refresh, so use it when the library is there.
--- Stop somebody else's "hide until you hover the minimap" from following the
--  button onto our rail.
--
--  LibDBIcon carries a per-button `showOnMouseover` flag and a `fadeOut`
--  animation group. Any addon can turn it on for every registered button -
--  Leatrix Plus's "Hide addon buttons" does exactly that, and there is nothing
--  wrong with it: on a minimap, buttons that appear when you look at the ring
--  are a real preference. On a rail in a drawer they are just missing.
--
--  What made it look like OUR bug is that the library's own onEnter/onLeave and
--  its Minimap OnEnter/OnLeave hooks walk **every** button in lib.objects, not
--  the one under the cursor. So hovering anything, anywhere, faded ours back
--  out a second later - buttons that came back on hover, vanished again, and
--  survived just long enough after being pinned to look like a layout race.
--
--  Cleared rather than merely overridden: setting alpha back to 1 loses to the
--  next fadeOut:Play(), and the flag is the only thing gating that call. This is
--  what lib:ShowOnEnter(name, false) does, done directly because the button may
--  be one we found on the minimap without a registered LibDBIcon name.
local function Unfade(f)
	if f.showOnMouseover == nil and not f.fadeOut then return end
	f.showOnMouseover = false
	if f.fadeOut and f.fadeOut.Stop then pcall(f.fadeOut.Stop, f.fadeOut) end
	if f.SetAlpha then pcall(f.SetAlpha, f, 1) end
end

local function Pacify(button, ldbiName)
	local ldbi = DBIcon()
	if ldbi and ldbiName and ldbi.IsRegistered and ldbi:IsRegistered(ldbiName) then
		pcall(ldbi.Lock, ldbi, ldbiName)
	end
	if button.SetScript then
		pcall(button.SetScript, button, "OnDragStart", nil)
		pcall(button.SetScript, button, "OnDragStop", nil)
	end
	Unfade(button)
end

--- Let go of a strata and level the button is holding onto.
--
--  LibDBIcon pins both - SetFixedFrameStrata(true) and SetFixedFrameLevel(true) -
--  so that reparenting cannot shuffle its buttons around behind things. Good
--  hygiene for a library, and it means our own SetFrameStrata is quietly refused:
--  the button stays where it was while the surface sits higher, so the surface's
--  own art is painted over the top of it and the click never lands.
local function Unpin(f)
	if f.SetFixedFrameStrata then pcall(f.SetFixedFrameStrata, f, false) end
	if f.SetFixedFrameLevel then pcall(f.SetFixedFrameLevel, f, false) end
end

-- What a third-party button hangs off itself, none of which is ours to keep:
-- a bevelled ring, a tracking-border, a plate behind the icon. LibDBIcon names
-- its three parts, so those are exact; anything else is matched on the texture
-- path, because a *name* is what the addon chose to call it and a path is what
-- it actually drew.
local FURNITURE = {
	"MiniMap%-TrackingBorder", "MinimapButtonBorder", "MiniMapButtonBorder",
	"UI%-Minimap%-Border", "MinimapBorder", "Button%-Border",
}

--- Make somebody else's button look like it belongs here: the icon masked to a
--  circle with our ring around it, and everything else it arrived with off.
--
--  The first version matched the bevel by texture path against a list of the
--  usual suspects. That was too clever by half: an addon's border is whatever
--  file that addon happened to ship, and there is no list that covers "whatever
--  file that addon happened to ship". So the rule is inverted - **find the icon
--  and hide every other texture** - which needs no list and cannot go stale.
--
--  Finding the icon, in order of how much the answer can be trusted:
--    1. `b.icon`, which LibDBIcon sets by name and most hand-rolled buttons copy
--    2. a region named <button>Icon, the old FrameXML convention
--    3. the largest ARTWORK texture, which is what an icon almost always is
--
--  Light touch throughout, because these frames belong to other addons: regions
--  are hidden and their texture cleared, never removed, and nothing is renamed
--  or reparented beyond the one move into the drawer.
local function FindIcon(b, regions)
	if type(b.icon) == "table" and b.icon.SetTexCoord then return b.icon end

	local ok, name = pcall(RawGetName, b)
	if ok and name and _G[name .. "Icon"] then
		local r = _G[name .. "Icon"]
		if type(r) == "table" and r.SetTexCoord then return r end
	end

	local best, bestArea
	for _, r in ipairs(regions) do
		if r.GetObjectType and r:GetObjectType() == "Texture" then
			local okt, tex = pcall(r.GetTexture, r)
			local area = (r.GetWidth and (r:GetWidth() or 0) * (r:GetHeight() or 0)) or 0
			-- A texture with nothing in it is not the icon.
			if okt and tex and (not bestArea or area > bestArea) then
				best, bestArea = r, area
			end
		end
	end
	return best
end

--- Make somebody else's button look like it belongs here.
--
--  The flag is set at the END, not the start. It used to be set before the ring
--  was built, and when Palette turned out not to be in scope after this code
--  moved here the pcall around it swallowed the error - leaving a button marked
--  skinned, with its icon masked and no rim, and nothing anywhere saying so.
--  A "done" flag written before the work is a lie the next call believes.
function L.SkinButton(b)
	if b.__aetherSkinned then return end

	local got = { pcall(b.GetRegions, b) }
	if not got[1] then return end
	local regions = {}
	for i = 2, #got do regions[#regions + 1] = got[i] end

	local icon = FindIcon(b, regions)
	b.__aetherHidden = 0

	for _, r in ipairs(regions) do
		if r ~= icon and r.GetObjectType and r:GetObjectType() == "Texture" then
			pcall(r.SetTexture, r, nil)
			pcall(r.SetAlpha, r, 0)
			pcall(r.Hide, r)
			b.__aetherHidden = b.__aetherHidden + 1
		end
	end

	if icon then
		-- Trim the icon's own baked border before masking, the way every icon in
		-- this UI is trimmed, or the circle cuts through somebody's frame art.
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "TOPLEFT", b, "TOPLEFT", 2, -2)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
		pcall(icon.SetDrawLayer, icon, "ARTWORK")
		pcall(W.AddMask, icon, b, Media.texture.chipDisc, b)
		b.__aetherIcon = icon
	end

	if not b.__aetherRing then
		local ok, ring = pcall(b.CreateTexture, b, nil, "OVERLAY")
		if ok and ring then
			-- Chip-Rim, and lapped one PHYSICAL pixel proud of the icon rather
			-- than flush on it. Ring is 256 because the minimap magnifies it;
			-- these buttons are twenty-six across, so it was minified ten times
			-- and the rim fell under a pixel - the crunchy bezel that got
			-- reported. And flush over a masked icon leaves the mask's own
			-- stair-stepping showing outside the rim, which is the same note
			-- W.CreateBadge and minimap_border() both carry.
			ring:SetTexture(Media.texture.chipRim)
			local proud = A:PxIn(b)
			ring:SetPoint("TOPLEFT", b, "TOPLEFT", -proud, proud)
			ring:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", proud, -proud)
			local c = Palette.c.glassEdge
			ring:SetVertexColor(c[1], c[2], c[3], 0.9)
			b.__aetherRing = ring
		end
	end

	b.__aetherSkinned = true
end

--- Everything a consumer has to do to a borrowed frame before placing it.
--  Idempotent, because a re-claim after a module toggle is ordinary.
function L:Prepare(entry)
	if not entry or not entry.button or entry.owned then return end
	if entry._prepared then return end
	entry._prepared = true
	Pacify(entry.button, entry.ldbiName)
	Unpin(entry.button)

	-- Skinned HERE rather than by whichever surface claimed it. It used to
	-- happen inside the minimap drawer's Collect, which meant retiring the
	-- drawer would have left every button on the rail wearing whatever bevel
	-- its own addon shipped.
	if L.skinButtons ~= false then
		pcall(L.SkinButton, entry.button)
	end
end

-- ---------------------------------------------------------------------------
-- the proxy button
--
-- An LDB launcher with no minimap button has nothing to position. Rather than
-- making every consumer carry a "and if there is no frame..." branch, one is
-- made here. It is OURS, so it can be hidden freely - which a borrowed button
-- cannot be, since it may carry a secure template.
-- ---------------------------------------------------------------------------

local proxyCount = 0

local function MakeProxy(entry)
	proxyCount = proxyCount + 1
	local b = CreateFrame("Button", ADDON .. "Launcher" .. proxyCount, UIParent)
	b:SetSize(24, 24)
	b:RegisterForClicks("AnyUp")

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(b)
	b.icon = icon

	b:SetScript("OnClick", function(self, button) L:Click(entry, button) end)
	b:SetScript("OnEnter", function(self) L:ShowTooltip(self, entry) end)
	b:SetScript("OnLeave", function(self) L:HideTooltip(self, entry) end)

	entry.owned = true
	return b
end

--- Re-read the icon off the object. Cheap, and the object may have changed it.
function L:RefreshIcon(entry)
	if not entry or not entry.owned or not entry.button then return end
	local obj = entry.obj
	if not obj then return end
	local tex = obj.icon
	if tex then
		pcall(entry.button.icon.SetTexture, entry.button.icon, tex)
		local c = obj.iconCoords
		if type(c) == "table" and #c == 4 then
			pcall(entry.button.icon.SetTexCoord, entry.button.icon, c[1], c[2], c[3], c[4])
		end
		local r, g, bl = obj.iconR, obj.iconG, obj.iconB
		if r and g and bl then
			pcall(entry.button.icon.SetVertexColor, entry.button.icon, r, g, bl)
		end
	end
end

-- ---------------------------------------------------------------------------
-- clicking and tooltips - the LDB protocol, in one place
-- ---------------------------------------------------------------------------

--- Run whatever this entry does when clicked.
--
--  The script is read HERE rather than captured when the entry was built. Titan
--  does the same and says why: an addon is entitled to swap its own OnClick
--  after login, and a captured reference goes stale silently.
function L:Click(entry, button)
	if not entry then return false end
	button = button or "LeftButton"

	local obj = entry.obj
	if obj then
		local fn = obj.OnClick
		if type(fn) == "function" then
			return (pcall(fn, entry.button, button))
		end
	end

	-- No LDB object, or one with no OnClick: replay the frame's own handler.
	-- That is the whole of what a hand-rolled minimap button offers.
	local f = entry.button
	if f and not entry.owned and f.GetScript then
		local ok, fn = pcall(f.GetScript, f, "OnClick")
		if ok and type(fn) == "function" then
			return (pcall(fn, f, button))
		end
		local ok2, fn2 = pcall(f.GetScript, f, "OnMouseUp")
		if ok2 and type(fn2) == "function" then
			return (pcall(fn2, f, button))
		end
	end

	return false
end

--- The spec offers three tooltip mechanisms and no precedence between them.
--
--  Titan's comment: "The LDB spec is unclear on priority of method to choose!"
--  Their order is `.tooltip` first, then OnEnter/OnLeave, then OnTooltipShow,
--  and it is copied rather than re-derived - a display addon that disagrees with
--  the most-used display addon is the one that looks broken.
--
--  `.tooltip` is a frame the object owns and updates; we only place and show it.
--  Per Titan's header it must NOT be a GameTooltip, so it is shown rather than
--  filled.
function L:ShowTooltip(frame, entry)
	local obj = entry and entry.obj
	if not obj then return false end

	local tip = obj.tooltip
	if type(tip) == "table" and tip.Show then
		pcall(tip.SetOwner, tip, frame, "ANCHOR_NONE")
		pcall(tip.ClearAllPoints, tip)
		pcall(tip.SetPoint, tip, "TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
		pcall(tip.Show, tip)
		entry._tip = tip
		return true
	end

	local onEnter = obj.OnEnter
	if type(onEnter) == "function" then
		pcall(onEnter, frame)
		entry._usedOnEnter = true
		return true
	end

	local fill = obj.OnTooltipShow
	if type(fill) == "function" and GameTooltip then
		pcall(GameTooltip.SetOwner, GameTooltip, frame, "ANCHOR_NONE")
		pcall(GameTooltip.ClearAllPoints, GameTooltip)
		pcall(GameTooltip.SetPoint, GameTooltip, "TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
		pcall(GameTooltip.ClearLines, GameTooltip)
		pcall(fill, GameTooltip)
		pcall(GameTooltip.Show, GameTooltip)
		entry._tip = GameTooltip
		return true
	end

	return false
end

function L:HideTooltip(frame, entry)
	local obj = entry and entry.obj
	if entry and entry._usedOnEnter and obj and type(obj.OnLeave) == "function" then
		entry._usedOnEnter = nil
		pcall(obj.OnLeave, frame)
		return
	end
	if entry and entry._tip then
		pcall(entry._tip.Hide, entry._tip)
		entry._tip = nil
	end
end

-- ---------------------------------------------------------------------------
-- discovery
-- ---------------------------------------------------------------------------

local function Add(entry)
	L.entries[#L.entries + 1] = entry
	L.byKey[entry.key] = entry
	if entry.button then L.seen[entry.button] = entry end
	return entry
end

--- Attach a real minimap button to an entry that so far only had an object.
--  The button always wins over a proxy: it is what the addon actually made, and
--  it is the one carrying that addon's own click behaviour.
local function AdoptButton(entry, button, ldbiName)
	if entry.button and not entry.owned then return end
	if entry.button and entry.owned then
		-- Drop the proxy. It is ours, so this is free and safe anywhere.
		pcall(entry.button.Hide, entry.button)
		L.seen[entry.button] = nil
		entry._prepared = nil
	end
	entry.button   = button
	entry.owned    = false
	entry.ldbiName = ldbiName or entry.ldbiName
	L.seen[button] = entry
end

--- LDB launchers. `data source` objects are deliberately skipped: they are
--  readouts, not things to click, and the Toolbox puts them to a different use.
function L:ScanLDB()
	local ldb = LDB()
	if not ldb or not ldb.DataObjectIterator then return 0 end

	local found = 0

	-- THREE return values, not one. `DataObjectIterator` is `return
	-- pairs(self.proxystorage)`, and `pairs` answers with the iterator function,
	-- the table and the initial key. Catching only the first leaves the generic
	-- `for` with no state table, which fails as
	-- "bad argument #1 to '(for generator)' (table expected, got nil)" - the
	-- first thing this file did when it met the real library.
	local ok, iterFn, iterState, iterKey = pcall(ldb.DataObjectIterator, ldb)
	if not ok or type(iterFn) ~= "function" then return 0 end

	for name, obj in iterFn, iterState, iterKey do
		if type(obj) == "table" and obj.type == "launcher" then
			local entry = self.byKey[name]
			if not entry then
				entry = Add({
					key    = name,
					label  = obj.label or obj.tocname or name,
					source = "ldb",
					obj    = obj,
				})
				entry.button = MakeProxy(entry)
				self.seen[entry.button] = entry
				self:RefreshIcon(entry)
				found = found + 1
			elseif not entry.obj then
				entry.obj = obj
			end
		end
	end

	return found
end

--- LibDBIcon's buttons. Keyed by the same name as the LDB object, which is what
--  makes the dedupe work at all.
function L:ScanDBIcon()
	local ldbi = DBIcon()
	if not ldbi or not ldbi.GetButtonList then return 0 end

	local found = 0
	local ok, list = pcall(ldbi.GetButtonList, ldbi)
	for _, name in ipairs(ok and list or {}) do
		local b = ldbi:GetMinimapButton(name)
		if b then
			local entry = self.byKey[name]
			if entry then
				AdoptButton(entry, b, name)
			else
				entry = Add({
					key      = name,
					label    = name,
					source   = "dbicon",
					button   = b,
					owned    = false,
					ldbiName = name,
				})
				found = found + 1
			end
			-- The object may exist without having been seen as a launcher: an
			-- addon can register a `data source` and still give it an icon.
			local ldb = LDB()
			if ldb and not entry.obj and ldb.GetDataObjectByName then
				local okObj, obj = pcall(ldb.GetDataObjectByName, ldb, name)
				if okObj then entry.obj = obj end
			end
		end
	end

	return found
end

-- What an addon calls its own button: its name, then some spelling of "minimap
-- button". Strip that and what is left is the addon - which is the name its LDB
-- launcher is registered under, if it shipped one.
local OWNER_SUFFIX = {
	"[%-_]?minimapbutton$", "[%-_]?minimapicon$", "[%-_]?minimapframe$",
	"[%-_]?minimap$",
}

--- Which addon made this global, if the client will say.
--
--  issecurevariable's SECOND return is the addon that tainted the name. It is
--  the only thing in the game that knows a button called EnxMiniMapIcon belongs
--  to Enchantrix - nothing about the two names says so, and no amount of
--  stripping "minimap icon" off one end gets from "Enx" to "Enchantrix".
local function TaintedBy(name)
	if not issecurevariable or not name then return nil end
	local ok, secure, addon = pcall(issecurevariable, name)
	if not ok or secure then return nil end
	return type(addon) == "string" and addon ~= "" and addon or nil
end

local function EntryNamed(want)
	if not want or want == "" then return nil end
	want = want:lower()
	for k, entry in pairs(L.byKey) do
		if k:lower() == want then return entry end
	end
end

--- The entry a hand-rolled button already belongs to, if any.
--
--  Two addons showed this up. SmartBuff registers a launcher called "SmartBuff"
--  and builds SmartBuff_MiniMapButton, where the name alone is enough.
--  Enchantrix registers "Enchantrix" and builds EnxMiniMapIcon, where it is
--  not. Either way, collecting the button as an entry of its own puts the same
--  addon in the drawer twice - which reads as our bug just as much as leaving
--  it loose on the ring did.
local function OwnerEntry(key)
	-- Ask the client first. It knows; the name only sometimes does.
	local entry = EntryNamed(TaintedBy(key))
	if entry then return entry end

	local lower = key:lower()
	local base
	for _, pat in ipairs(OWNER_SUFFIX) do
		local stem = lower:gsub(pat, "")
		if stem ~= lower and stem ~= "" then
			base = stem
			break
		end
	end

	return EntryNamed(base)
end

--- Hand-rolled buttons parented onto the minimap.
function L:ScanMinimap(own)
	if not _G.Minimap or not _G.Minimap.GetChildren then return 0 end

	local found = 0
	-- With a pin addon running this vararg is enormous, and expanding it into a
	-- table has been known to throw outright. Nobody's day should end here.
	local results = { pcall(_G.Minimap.GetChildren, _G.Minimap) }
	if not results[1] then
		self.scanError = results[2]
		return 0
	end
	self.scanError = nil

	for i = 2, #results do
		local child = results[i]
		if IsAddonButton(child, own) then
			local okName, name = pcall(RawGetName, child)
			local key = (okName and name) or tostring(child)
			if not self.byKey[key] then
				-- Onto the addon's own launcher where it has one, the same way a
				-- LibDBIcon button joins the entry it was registered under.
				local owner = OwnerEntry(key)
				if owner then AdoptButton(owner, child) end

				-- And on its own if that did not take - an entry already holding
				-- a real button keeps it. Twice in the drawer is still better
				-- than loose on the ring.
				if not self.seen[child] then
					Add({
						key    = key,
						label  = (okName and name) or "?",
						source = "minimap",
						button = child,
						owned  = false,
					})
				end
				found = found + 1
			end
		end
	end

	return found
end

--- One sweep of all three sources. Order matters: LDB first so a launcher's
--  label and object are on the entry before LibDBIcon hands us its button for
--  the same name.
function L:Scan(own)
	local found = self:ScanLDB() + self:ScanDBIcon() + self:ScanMinimap(own)
	if found > 0 then self:Changed() end
	return found
end

--- Sweep repeatedly for a while after login.
--
--  There is no event for "a child was added to the minimap" - checked against
--  three addons that all solve it the same way - and an addon creates its button
--  whenever it happens to finish loading. So: sweep now, sweep again on a timer
--  for fifteen seconds, and subscribe to the two creation callbacks forever
--  after.
function L:StartScanning(own)
	self._own = own or self._own
	self:Scan(self._own)

	-- CallbackHandler's embed takes the REGISTERING object first, not the
	-- library: `lib.RegisterCallback(me, event, handler)`. Passing the library
	-- as `me` registers an event named after our own table and silently never
	-- fires - which is what happened when this moved out of Minimap.lua and left
	-- the comment behind.
	local ldb = LDB()
	if ldb and ldb.RegisterCallback and not self._ldbHooked then
		self._ldbHooked = true
		pcall(ldb.RegisterCallback, self, "LibDataBroker_DataObjectCreated",
			function() L:Scan(L._own) end)
	end

	local ldbi = DBIcon()
	if ldbi and ldbi.RegisterCallback and not self._ldbiHooked then
		self._ldbiHooked = true
		pcall(ldbi.RegisterCallback, self, "LibDBIcon_IconCreated",
			function() L:Scan(L._own) end)
	end

	if not C_Timer or not C_Timer.NewTicker then return end
	if self._ticker then return end
	local left = 7
	self._ticker = C_Timer.NewTicker(2, function()
		L:Scan(L._own)
		left = left - 1
		if left <= 0 and L._ticker then
			L._ticker:Cancel()
			L._ticker = nil
		end
	end, 7)
end

-- ---------------------------------------------------------------------------
-- ownership
--
-- Exactly one surface positions a given entry. Without this the minimap drawer
-- and the Toolbox rail would both anchor the same borrowed frame, and the answer
-- would be whichever ran last - which is a bug that only shows up for whoever
-- has both switched on.
-- ---------------------------------------------------------------------------

--- `force` is how a pin wins.
--
--  Ordinarily a claim on something somebody else holds is refused, which is the
--  whole point: two surfaces positioning one borrowed frame is a bug that only
--  appears for whoever has both switched on. But pinning an addon to the rail is
--  an explicit instruction to move it THERE, so the Toolbox takes it and the
--  previous owner is told the list changed and drops it on its next pass.
--
--  Deliberately not a priority number. A number invites a third surface to pick
--  a bigger one; a flag makes the caller say out loud that it is overriding.
function L:Claim(entry, owner, force)
	if not entry or not owner then return false end

	-- Unconditionally, and NOT left to Prepare, which runs once per entry and
	-- early-outs afterwards. LibDBIcon fires LibDBIcon_IconCreated to every
	-- listener, so an addon that hides buttons until mouseover is racing us for
	-- the same callback - and when it wins, the flag lands on a button we have
	-- already prepared and Prepare will never look at again. That is the "a new
	-- pin stays for a while, then goes" shape: nothing had gone wrong at pin
	-- time, and the loser of a callback race was us.
	if entry.button then Unfade(entry.button) end

	local held = self.owners[entry]
	if held and held ~= owner then
		if not force then return false end
		self.owners[entry] = owner
		self:Prepare(entry)
		self:Changed()
		return true
	end
	self.owners[entry] = owner
	self:Prepare(entry)
	self:Unpark(entry)
	return true
end

--- Undo Park. The new owner sets the position; this only restores what parking
--  took away, and only if parking took it.
function L:Unpark(entry)
	if not entry or not entry._parked then return end
	entry._parked = nil
	local b = entry.button
	if not b then return end
	if b.SetAlpha then pcall(b.SetAlpha, b, 1) end
	if b.EnableMouse then pcall(b.EnableMouse, b, true) end
end

--- Take a borrowed frame out of play without hiding it.
--
--  Never Hide: a collected button belongs to another addon and may carry a
--  secure template, and hiding a frame with a protected descendant is refused
--  in combat. Alpha, mouse and position only - the same parking the aura trays
--  and the minimap drawer already use.
--
--  Ten thousand units off to the left, which is where the aura tiles go. Far
--  enough that no resolution reaches it and no anchor chain drags it back.
function L:Park(entry)
	local b = entry and entry.button
	if not b then return end
	if b.SetAlpha then pcall(b.SetAlpha, b, 0) end
	if b.EnableMouse then pcall(b.EnableMouse, b, false) end
	pcall(RawClearAllPoints, b)
	pcall(RawSetPoint, b, "TOPLEFT", UIParent, "TOPLEFT", -10000, 0)
	entry._parked = true
end

--- Releasing does NOT just forget the owner.
--
--  It used to, and the frame stayed exactly where its last owner left it:
--  unpinning an addon took it off the rail's layout and left the button sitting
--  on the rail, on top of the settings gear. Nobody moved it because nobody
--  owned it - the drawer filters on ownership too, so an unowned button is laid
--  out by neither surface and simply persists wherever it was.
--
--  So an entry that ends up unowned is parked, and the change is announced so a
--  surface that wants it can claim it back on the spot.
function L:Release(entry, owner)
	if not entry then return end
	if owner and self.owners[entry] ~= owner then return end
	self.owners[entry] = nil
	self:Park(entry)
	self:Changed()
end

function L:ReleaseAll(owner)
	local any = false
	for entry, held in pairs(self.owners) do
		if held == owner then
			self.owners[entry] = nil
			self:Park(entry)
			any = true
		end
	end
	-- Announced once at the end rather than per entry: a listener that rescans
	-- would otherwise do it once for every button on the machine.
	if any then self:Changed() end
end

function L:OwnerOf(entry)
	return entry and self.owners[entry]
end

-- ---------------------------------------------------------------------------
-- consumers
-- ---------------------------------------------------------------------------

L.skinButtons = true
L.listeners = {}

function L:OnChanged(key, fn)
	self.listeners[key] = fn
end

function L:Changed()
	for _, fn in pairs(self.listeners) do pcall(fn) end
end

--- Deterministic order. `pairs` is not, and a drawer whose buttons shuffle
--  between sessions looks broken even when nothing moved.
function L:Sorted()
	local out = {}
	for _, e in ipairs(self.entries) do out[#out + 1] = e end
	table.sort(out, function(x, y)
		return tostring(x.label or x.key) < tostring(y.label or y.key)
	end)
	return out
end

--- Only the entries somebody can actually place: everything, since an entry
--  without a frame gets a proxy. Kept as a named idea anyway, because "which of
--  these are real buttons" is the question the minimap drawer used to ask.
function L:Iterate()
	local i, list = 0, self:Sorted()
	return function()
		i = i + 1
		return list[i]
	end
end

function L:Count()
	return #self.entries
end
