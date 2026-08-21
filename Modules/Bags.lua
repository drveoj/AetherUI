--[[--------------------------------------------------------------------------
	AetherUI :: Bags

	Concept 5. One unified inventory panel, and a second one for the bank.

	This REPLACES Blizzard's bags rather than reskinning them. The reason is not
	taste: Blizzard draws five independent ContainerFrames that each remember
	their own position and each carry their own header, and there is no
	arrangement of those five that becomes a single categorised grid. So every
	route into the bag UI -- the B key, the bag bar, shift-click on the backpack,
	the merchant and mail windows opening your bags for you -- is funnelled into
	this module instead, and handed back intact when it is switched off.

	The shape of the thing:

	  Bags:frames.bags        the inventory window (backpack + bags 1..4)
	  Bags:frames.bank        the bank window, only alive at a banker
	  frame.flyout            equipped bags, and the keyring, on the bags window
	  frame.foot              money and free slots; on the bank, the bank bags

	Both windows are the same builder with a `kind` of "bags" or "bank". The
	bank is told apart by a blue accent and by what its footer carries, not by a
	different anatomy -- which is the deck's intent and also the only way two
	windows this similar stay in step.

	Three things here are load-bearing and non-obvious:

	  * Item buttons are Blizzard's ContainerFrameItemButtonTemplate and their
	    OnClick is NOT overridden. That template is not secure on Classic Era
	    (it inherits ItemButtonTemplate and nothing else), and its handlers give
	    us use / equip / pick-up / split / sell / shift-link for free. What they
	    need in return is a parent whose GetID() is the BAG and a SetID() that is
	    the SLOT -- see ItemPool.

	  * A button is pooled per (bag, slot) and never re-bound to another one.
	    Pooling by display position would mean a button's identity changes every
	    time a category empties, which is the whole stale-index bug the quest log
	    paid for, except this one moves items.

	  * The bank is only readable while the banker session is open, and closing
	    Blizzard's BankFrame is what tells the server you have left. So its frame
	    is kept logically shown and reparented out of sight rather than hidden,
	    and our own window's OnHide calls CloseBankFrame().
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Bags = A:NewModule("bags")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

-- ---------------------------------------------------------------------------
-- geometry
--
-- The deck's pixels, unchanged. The whole window is drawn at profile.scale
-- (0.71 = 768/1080), so these are its numbers and must not be "corrected" into
-- virtual units. 8 * 44 + 7 * 6 + 2 * 24 = 442, which is the panel width.
-- ---------------------------------------------------------------------------

-- Every framed panel in this interface, ours and the client's alike. It was
-- 28 here, 28 on the quest log, 28 on the Toolbox, 20 on the party controls
-- and 16 on the client's windows - three answers, and nobody sees all of
-- them at once to notice.
local WIN_CORNER    = W.PANEL_CORNER
local GRID_PAD_X    = 24

-- THE SHARED NUMBERS. 15a gives one header height and one body padding
-- for every panel in the interface, and a window of ours is a panel like
-- any other - the only reason these were local was that they were written
-- before there was anywhere to put them.
local HEAD_H        = W.PANEL_HEAD_H
local HEAD_PAD_X    = W.PANEL_PAD
local HEAD_GAP      = 10
local ICON_SIZE     = 17

-- The field in the header band. Its own height, because 34 fills a 54 band
-- corner to corner; 30 is the quest log's and leaves the band around it.
local SEARCH_H      = 30
local SEARCH_W      = 200
local SEARCH_PAD_X  = 20

local SEC_GAP       = 14   -- between one category and the next
local SEC_LABEL_H   = 15
local SEC_LABEL_GAP = 7    -- label baseline to the top of its grid
local GRID_TOP      = 12
local GRID_BOTTOM   = 16
local SCROLL_STEP   = 44   -- pixels per wheel click

local FOOT_H        = 44
local FOOT_PAD_X    = 24
local COIN_SIZE     = 13

local PANEL_GAP     = 28   -- bank to bags

local FLY_W         = 224
local FLY_TOP       = 64
local FLY_PAD       = 14
local FLY_CORNER    = 22
local FLY_ROW_H     = 42
local FLY_GAP       = 6

-- How far the clip window is opened out on the three sides that are NOT the
-- reveal line. The drawer's shadow reaches corner/2 outside it (Glass's
-- _LayoutPanelShadow), and a clip rect flush to the drawer would shave that off
-- the open drawer's own edges - which reads as the glass being cut with a
-- knife down the right-hand side.
local FLY_CLIP_PAD  = FLY_CORNER

-- 300ms in the handoff, as a rate so the slide reverses rather than queues.
local FLY_SLIDE_RATE = 1 / 0.30

-- The handle on the drawer's outer edge. Same shape and the same trick as the
-- Toolbox rail and the party dock's tab: overlapped INTO whatever it is
-- attached to by its own corner radius, so the inner curve disappears and the
-- two read as one shape rather than as a tab with a gap of shadow beside it.
--
-- Its LENGTH is derived rather than written down, the way the Toolbox rail's
-- width is. What it holds changes - the keyring section is a setting, and on a
-- game version without one there is nothing to count - and a number here would
-- leave a hole in the tab the day the keys stop being drawn.
local RAIL_CHEV     = 11
local RAIL_GLYPH    = 16
local RAIL_PAD      = 7
local RAIL_THICK    = RAIL_GLYPH + RAIL_PAD * 2
local RAIL_GAP      = 7    -- between one thing on the rail and the next
local RAIL_TIGHT    = 1    -- a count belongs TO its glyph, so it sits close
local RAIL_COUNT_H  = 11
local RAIL_CORNER   = 8
local RAIL_BITE     = RAIL_CORNER
local TILE          = 30   -- a bag glyph tile
local TILE_CORNER   = 10
local KEY_SLOT      = 34
local KEY_COLS      = 5

local CONFIRM_W       = 360
local CONFIRM_MIN_H   = 150
local CONFIRM_PAD     = 26
local BTN_H           = 30

-- Sorting and selling both move real items, and both are paced rather than
-- fired in a loop: the server locks a slot until it confirms a move, and a
-- second move on a locked slot is dropped silently rather than queued.
local SORT_STEP     = 0.05
local SELL_STEP     = 0.20

-- ---------------------------------------------------------------------------
-- the client
--
-- Resolved once, defensively, because the harness has no container API at all
-- and a module that throws at file scope takes the whole addon with it.
-- ---------------------------------------------------------------------------

local CT = _G.C_Container or {}

local function api(name)
	return CT[name] or _G[name]
end

local GetNumSlots      = api("GetContainerNumSlots")
local GetItemInfoAt    = api("GetContainerItemInfo")
local GetNumFreeSlots  = api("GetContainerNumFreeSlots")
local GetQuestInfoAt   = api("GetContainerItemQuestInfo")
local GetCooldownAt    = api("GetContainerItemCooldown")
local PickupItemAt     = api("PickupContainerItem")
local UseItemAt        = api("UseContainerItem")
local BagToInventory   = api("ContainerIDToInventoryID")

local CI = _G.C_Item or {}
local ItemInfo        = CI.GetItemInfo or _G.GetItemInfo
local ItemInfoInstant = CI.GetItemInfoInstant or _G.GetItemInfoInstant

-- Bag ids. Read from the client, never hardcoded -- Enum.BagIndex is the shared
-- modern enum and its BankBag_1 is 6, which is wrong here: it assumes a reagent
-- bag at 5 that Era does not have, and Era's bank bags start at 5.
local BACKPACK = _G.BACKPACK_CONTAINER or 0
local BANK     = _G.BANK_CONTAINER or -1
local KEYRING  = _G.KEYRING_CONTAINER or -2
local NUM_BAGS = _G.NUM_BAG_SLOTS or 4
local NUM_BANK_BAGS = _G.NUM_BANKBAGSLOTS or 6

local function InventoryBags()
	local t = {}
	for i = BACKPACK, NUM_BAGS do t[#t + 1] = i end
	return t
end

local function BankBags()
	local t = { BANK }
	for i = NUM_BAGS + 1, NUM_BAGS + NUM_BANK_BAGS do t[#t + 1] = i end
	return t
end

local function HasKeyring()
	return _G.HasKey and _G.HasKey() and true or false
end

local function KeyringSize()
	if not HasKeyring() then return 0 end
	return (_G.GetKeyRingSize and _G.GetKeyRingSize()) or 0
end

--- Slot count for a bag, tolerant of a client that has not answered yet.
--  Returns 0 for an unowned bank bag, which is what makes a plain loop safe.
local function SlotsIn(bag)
	if bag == KEYRING then return KeyringSize() end
	if not GetNumSlots then return 0 end
	local ok, n = pcall(GetNumSlots, bag)
	return (ok and tonumber(n)) or 0
end

-- ---------------------------------------------------------------------------
-- specialist bags
--
-- A quiver takes arrows and nothing else. So do herb bags, soul pouches and the
-- rest, and a window that counts their empty slots alongside the backpack's
-- promises room it has not got: a hunter with a full backpack and five empty
-- quiver slots was told "11 slots free" and could put six things away.
-- ---------------------------------------------------------------------------

-- The bitmask meanings are the ones two shipping addons on this client agree
-- on; anything unrecognised is reported as "restricted" rather than guessed at.
-- An ARRAY rather than a keyed table, and walked in order, because a bag
-- carrying two family bits must not describe itself differently between
-- sessions -- which is what pairs() over a keyed table would give.
local BAG_FAMILIES = {
	{ 0x00001, "quiver"         }, { 0x00002, "ammo"       },
	{ 0x00004, "soul shards"    }, { 0x00008, "leatherworking" },
	{ 0x00010, "inscription"    }, { 0x00020, "herbs"      },
	{ 0x00040, "enchanting"     }, { 0x00080, "engineering" },
	{ 0x00100, "keys"           }, { 0x00200, "gems"       },
	{ 0x00400, "mining"         }, { 0x08000, "fishing"    },
	{ 0x10000, "cooking"        },
}

--- What a family bitmask is called, in one word. nil for a general bag.
local function FamilyWord(family)
	local bit = _G.bit
	if not bit or type(family) ~= "number" or family == 0 then return nil end
	for _, entry in ipairs(BAG_FAMILIES) do
		if bit.band(family, entry[1]) > 0 then return entry[2] end
	end
	return "restricted"
end

--- What a bag will take. 0 means anything.
--
--  The family bitmask is the SECOND return of GetContainerNumFreeSlots, which
--  is the canonical way to ask it - there is no GetContainerFamily.
local function BagFamily(bag)
	if not GetNumFreeSlots then return 0 end
	local ok, _, family = pcall(GetNumFreeSlots, bag)
	return (ok and tonumber(family)) or 0
end

--- The one call that answers everything about a slot.
--
--  On this client it returns a TABLE, not the legacy tuple -- verified in
--  Blizzard's own Era source, in the generated API docs, and in two shipping
--  11509 addons. It carries iconFileID, stackCount, isLocked, quality,
--  isReadable, hasLoot, hyperlink, hasNoValue, itemID and isBound, which is
--  every field this module needs except the item's class. So the common path
--  makes no GetItemInfo call at all and never waits on the cache.
local function SlotInfo(bag, slot)
	if not GetItemInfoAt then return nil end
	local ok, info = pcall(GetItemInfoAt, bag, slot)
	if not ok then return nil end
	return info
end

-- ---------------------------------------------------------------------------
-- categories
--
-- Auto-assignment on classID, never on itemType/itemSubType: those two returns
-- are LOCALIZED STRINGS and comparing them to English literals works on exactly
-- one client. classID comes from GetItemInfoInstant, which is synchronous and
-- never misses, so categorising an item never has to wait for the item cache.
-- ---------------------------------------------------------------------------

local IC = _G.Enum and _G.Enum.ItemClass or {}

local CLASS_CATEGORY = {
	[IC.Weapon          or  2] = "equipment",
	[IC.Armor           or  4] = "equipment",
	[IC.Container       or  1] = "equipment",
	[IC.Consumable      or  0] = "consumable",
	[IC.Tradegoods      or  7] = "trade",
	[IC.Reagent         or  5] = "trade",
	[IC.Gem             or  3] = "trade",
	[IC.ItemEnhancement or  8] = "trade",
	[IC.Projectile      or  6] = "trade",
	[IC.Quiver          or 11] = "equipment",
	[IC.Recipe          or  9] = "trade",
	[IC.Questitem       or 12] = "quest",
	[IC.Key             or 13] = "misc",
	[IC.Miscellaneous   or 15] = "misc",
}

-- Order is the drawing order. `misc` sits above `junk` because "I have not
-- classified this" and "this is worthless" are different statements and a
-- player will look in the first for something they cannot find.
local CATEGORIES = {
	{ key = "equipment",  label = "EQUIPMENT"   },
	{ key = "consumable", label = "CONSUMABLES" },
	{ key = "trade",      label = "TRADE GOODS" },
	{ key = "quest",      label = "QUEST"       },
	{ key = "misc",       label = "MISCELLANEOUS" },
	{ key = "junk",       label = "JUNK"        },
}

-- The bank uses the SAME categories, and that is deliberate.
--
-- It did not to begin with. The concept describes the bank's sections as
-- "fewer, storage-oriented", so equipment, consumables and miscellaneous were
-- folded into one STORAGE heading -- which put a cooked Longjaw Mud Snapper,
-- an item whose entire purpose is that you eat it, under "storage".
--
-- The category is a fact about the ITEM, not about the room it is standing in.
-- Filing the same thing under two different headings depending on which panel
-- it is in means the player has to learn two schemes and translate between
-- them, which is the opposite of what a categorised bag is for.

--- itemID -> classID/subclassID/equipLoc, memoised.
--
--  GetItemInfoInstant is documented never to return nil for a valid id and
--  needs no cache round trip, so this table is a speed optimisation rather than
--  a correctness one -- which matters, because a cache that can hold a WRONG
--  answer is how a categorised grid quietly stops agreeing with itself.
local itemClass = {}

local function ClassOf(itemID)
	if not itemID then return nil end
	local cached = itemClass[itemID]
	if cached then return cached[1], cached[2], cached[3] end
	if not ItemInfoInstant then return nil end
	local ok, _, _, _, equipLoc, _, classID, subclassID = pcall(ItemInfoInstant, itemID)
	if not ok or classID == nil then return nil end
	itemClass[itemID] = { classID, subclassID, equipLoc }
	return classID, subclassID, equipLoc
end

--- Which section an item belongs in.
--
--  Quality wins over class. A poor-quality sword is junk, not equipment: the
--  player is looking at it to decide whether to sell it, and a grey item filed
--  under EQUIPMENT is a grey item they will carry for another twenty levels.
local function CategoryOf(info, bag, slot)
	if info.quality == 0 then return "junk" end

	if GetQuestInfoAt then
		local ok, q = pcall(GetQuestInfoAt, bag, slot)
		if ok and q and (q.isQuestItem or q.questID) then return "quest" end
	end

	local classID = ClassOf(info.itemID)
	return (classID and CLASS_CATEGORY[classID]) or "misc"
end

--- The item's name, for the search box.
--
--  itemName is declared on ContainerItemInfo for this build but nothing in
--  Blizzard's Era source or in either reference addon reads it, so it is not
--  trusted on its own. The hyperlink always carries the name in brackets and is
--  always present for a live slot, which makes it the reliable source.
local function NameOf(info)
	if type(info.itemName) == "string" and info.itemName ~= "" then
		return info.itemName
	end
	local link = info.hyperlink
	if type(link) == "string" then
		return link:match("%[(.-)%]") or link
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------

--- A one-pixel rule, snapped to the physical grid so it does not go soft.
-- Kept as a local for the call sites, but it is the shared one underneath:
-- one ink and one physical pixel, and the pixel is the part that was wrong.
-- See W.PaintHairline.
local function BuildHairline(parent, upright)
	return W.Hairline(parent, upright)
end

-- Declared here and defined with the rest of the skinning, because the build
-- runs it too - see BuildFrame.
local RestyleFrame

-- ONE INK, shared with every other line in the interface - see
-- W.PaintHairline. These carried their own fraction of glassEdge and came
-- out fainter than the tab rails, which is a separator you cannot see.
local function ColorHairline(t)
	W.PaintHairline(t)
end

--- Money, in the deck's treatment: the gold bright, the small change dimmed.
--
--  Assembled with |cff escapes rather than as three font strings, because three
--  strings means three anchors and a gap that changes with the digit count.
--  MoneyFrame is deliberately not used -- it taints, which is a real and
--  documented problem on this client, not a superstition.
local function MoneyText(copper)
	copper = tonumber(copper) or 0
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100

	local bright = Palette:Hex(Palette.c.text)
	local faint  = Palette:Hex(Palette.c.textDim)

	local function hi(fmt, ...) return Palette:InkHex(bright, fmt:format(...)) end
	local function lo(fmt, ...) return Palette:InkHex(faint, fmt:format(...)) end
	if g > 0 then
		return hi("%dg", g) .. " " .. lo("%ds %dc", s, c)
	elseif s > 0 then
		return hi("%ds", s) .. " " .. lo("%dc", c)
	end
	return hi("%dc", c)
end

--- The letter on a bag tile. There is no art for bag icons in this atlas and
--  the real item icon is a 64px square that reads as mud at 30px, so the deck
--  uses an initial instead. Code points, not bytes: a localized bag name split
--  on a byte boundary draws a replacement box.
local function GlyphFor(name)
	if type(name) ~= "string" or name == "" then return "?" end
	local b = name:byte(1)
	local len = 1
	if b >= 240 then len = 4 elseif b >= 224 then len = 3 elseif b >= 192 then len = 2 end
	local ch = name:sub(1, len)
	if len == 1 then ch = string.upper(ch) end
	return ch
end

-- ---------------------------------------------------------------------------
-- the item button
--
-- Blizzard's ContainerFrameItemButtonTemplate, wearing our chrome.
--
-- Its OnClick is left alone on purpose. On Classic Era that template inherits
-- ItemButtonTemplate and nothing else -- there is no SecureActionButtonTemplate
-- anywhere in the Era container UI -- so its handlers are ordinary Lua and give
-- us, for free and correctly: left-click to pick up, right-click to use or
-- equip or sell, shift-click to link, ctrl-click to dress up, drag, and
-- shift-drag to split a stack. Reimplementing that is a large amount of code
-- whose only possible outcome is being slightly wrong about one of them.
--
-- The contract it asks for in return is small and absolutely rigid:
--   * self:GetParent():GetID() must be the BAG id
--   * self:GetID() must be the SLOT index
--   * self.hasItem and self.readable must be kept up to date
--
-- Hence the proxy frames: one invisible frame per bag, carrying the bag's id,
-- covering the scroll child, and parenting that bag's buttons. The buttons are
-- ANCHORED to the grid but PARENTED to the proxy, which is legal and is the
-- only way to have both a per-bag id and a per-category layout.
-- ---------------------------------------------------------------------------

local itemButtonSeq = 0

local function BuildItemButton(proxy, bag, slot, size)
	itemButtonSeq = itemButtonSeq + 1
	local name = "AetherUIBagItem" .. itemButtonSeq

	-- ItemButton is the object type Blizzard uses for these on Era. If the
	-- template is missing -- an older client, or the harness -- fall back to a
	-- plain button so the module still builds and still draws; it loses the
	-- click behaviour, which is visible and reportable, rather than throwing at
	-- load and taking the whole addon down.
	local ok, b = pcall(CreateFrame, "ItemButton", name, proxy, "ContainerFrameItemButtonTemplate")
	if not ok or not b then
		b = CreateFrame("Button", name, proxy)
		b.__aetherPlain = true
	end

	b:SetSize(size, size)
	b:SetID(slot)
	b.bag, b.slot = bag, slot

	-- The template's own regions are retired rather than removed: they belong to
	-- Blizzard's handlers, some of which read them back. Ours are drawn on top.
	--
	-- Looked up BOTH ways on purpose. Some of these are `name="$parentX"` and
	-- resolve as a global; most are `parentKey="X"` with no name at all and
	-- resolve only as a field. Checking one way silently retires half of them,
	-- and BattlepayItemTexture -- the one that is NOT hidden by default in the
	-- template, only inside a ContainerFrame_Update we never call -- is in the
	-- half a name lookup misses.
	for _, key in ipairs({ "IconTexture", "icon", "Count", "count", "Stock",
		"IconBorder", "IconOverlay", "IconOverlay2", "IconQuestTexture",
		"NewItemTexture", "BattlepayItemTexture", "JunkIcon", "UpgradeIcon",
		"ItemContextOverlay", "SearchOverlay", "searchOverlay", "ExtendedSlot",
		"ExtendedOverlay", "ExtendedOverlay2", "BagStaticTopBorder",
		"BagStaticBottomBorder", "flash" }) do
		local r = _G[name .. key] or b[key]
		if type(r) == "table" and r.Hide and r.SetAlpha then
			pcall(r.SetAlpha, r, 0)
			pcall(r.Hide, r)
		end
	end
	if b.SetNormalTexture then
		-- SetNormalTexture(nil) THROWS on this client; ClearNormalTexture is what
		-- Blizzard's own Era quest log uses.
		if b.ClearNormalTexture then pcall(b.ClearNormalTexture, b)
		else pcall(b.SetNormalTexture, b, "") end
	end
	if b.SetPushedTexture then pcall(b.SetPushedTexture, b, "") end
	-- ItemButtonTemplate's HighlightTexture is a bare <HighlightTexture> with
	-- neither a name nor a parentKey, so no lookup above reaches it. Left in
	-- place it composites Blizzard's square ADD hilite over the rounded glass.
	if b.ClearHighlightTexture then
		pcall(b.ClearHighlightTexture, b)
	elseif b.GetHighlightTexture then
		local h = b:GetHighlightTexture()
		if h then pcall(h.SetTexture, h, nil) end
	end

	b._blizzCooldown = _G[name .. "Cooldown"] or b.Cooldown

	W.DecorateSlot(b, size)

	-- The deck puts the stack count on a dark pill. The OUTLINE on the `stack`
	-- role is what makes the digits legible over an arbitrary icon; the pill is
	-- what stops them reading as part of the artwork. It is sized to the text
	-- in UpdateItemButton, so an empty count draws nothing at all.
	local pill = b:CreateTexture(nil, "OVERLAY")
	pill:SetTexture(Media.texture.flat)
	local plate = Palette.c.countPill
	pill:SetVertexColor(plate[1], plate[2], plate[3], plate[4])
	pill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	pill:Hide()
	b.countPill = pill
	b.count:SetDrawLayer("OVERLAY", 1)

	-- A highlight of our own, since the template's went with the rest.
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(Media.texture.slotGloss)
	hl:SetAllPoints(b)
	hl:SetBlendMode("ADD")
	hl:SetAlpha(0.35)
	b.hl = hl

	if b.RegisterForClicks then pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp") end
	if b.RegisterForDrag then pcall(b.RegisterForDrag, b, "LeftButton") end

	-- The bank's 24 GENERIC slots are the one container Blizzard's own
	-- ContainerFrameItemButton_OnEnter gets wrong for us: it ends in
	-- GameTooltip:SetBagItem(-1, slot), and Blizzard's Era bank never calls
	-- that -- its own buttons use SetInventoryItem with BankButtonIDToInvSlotID,
	-- and both reference addons on this client route bag -1 the same way.
	--
	-- The keyring needs no such help: ContainerFrame_OnEnter special-cases
	-- KEYRING_CONTAINER itself.
	if bag == BANK then
		local function bankTooltip(self)
			-- Blizzard's own anchor helper reads self:GetRight() and errors if
			-- the button has no computed rect yet.
			if not self:GetRight() then return end
			local invSlot = _G.BankButtonIDToInvSlotID
				and _G.BankButtonIDToInvSlotID(self:GetID())
			if not invSlot then return end
			_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			pcall(_G.GameTooltip.SetInventoryItem, _G.GameTooltip, "player", invSlot)
			_G.GameTooltip:Show()
		end

		b:SetScript("OnEnter", bankTooltip)
		b:SetScript("OnLeave", function()
			if _G.GameTooltip_Hide then _G.GameTooltip_Hide() else _G.GameTooltip:Hide() end
			if _G.ResetCursor then _G.ResetCursor() end
		end)

		-- And `UpdateTooltip`, which is the half that matters.
		--
		-- GameTooltip's OnUpdate re-runs `owner:UpdateTooltip()` every
		-- TOOLTIP_UPDATE_TIME (0.2s) -- GameTooltip.lua:461. The template's
		-- OnLoad points that at ContainerFrameItemButton_OnEnter, which opens
		-- with SetOwner(ANCHOR_NONE) -- wiping the tooltip -- and then calls
		-- GameTooltip:SetBagItem(-1, slot).
		--
		-- Blizzard's own bank NEVER makes that call: BankFrameItemButton_OnEnter
		-- uses SetInventoryItem with BankButtonIDToInvSlotID. So the refresh
		-- emptied the tooltip and an empty tooltip hides itself -- which on
		-- screen is a tooltip that appears and then vanishes a fifth of a second
		-- later, whatever OnEnter did.
		--
		-- Overriding OnEnter alone is not enough. This is the one that repeats.
		b.UpdateTooltip = bankTooltip
	end

	return b
end

--- Draw one slot.
--
--  Everything here comes out of ContainerItemInfo except the category, so a
--  redraw costs one API call per slot and no cache lookups at all.
local function UpdateItemButton(b, cfg)
	local info = SlotInfo(b.bag, b.slot)
	local c = Palette.c

	-- Blizzard's handlers read these two off the button. Without them the
	-- tooltip fires on an empty slot and the right-click path misbehaves.
	b.hasItem  = info and info.itemID and true or nil
	b.readable = info and info.isReadable or nil
	b.info     = info

	if not info then
		b.icon:SetTexture(nil)
		b.icon:SetVertexColor(1, 1, 1, 1)
		b.count:SetText("")
		if b.countPill then b.countPill:Hide() end
		b.glow:Hide()
		b:SetAlpha(1)
		local e = c.glassEdge
		b.edge:SetVertexColor(e[1], e[2], e[3], (e[4] or 1) * 0.6)
		if b._blizzCooldown and b._blizzCooldown.Hide then b._blizzCooldown:Hide() end
		return nil
	end

	b.icon:SetTexture(info.iconFileID)

	local stack = tonumber(info.stackCount) or 1
	b.count:SetText(stack > 1 and tostring(stack) or "")
	if b.countPill then
		if stack > 1 then
			b.countPill:SetSize(math.ceil(b.count:GetStringWidth() or 0) + 7,
				math.ceil(b.count:GetStringHeight() or 0) + 1)
			b.countPill:Show()
		else
			b.countPill:Hide()
		end
	end

	-- Junk: dimmed and drained, not hidden. It stays clickable and stays where
	-- it is, so "sell this" remains one gesture and nobody has to hunt for the
	-- thing the panel has decided not to show them.
	-- LOCKED BEATS JUNK. A locked slot is an item that is currently somewhere
	-- else - on the cursor, or attached to a mail that has not been sent - and
	-- the client refuses to move it. Left at full strength it reads as still
	-- being in the bag, which is exactly what a bag full of things already
	-- attached to an open Send Mail looks like.
	--
	-- Drained rather than tinted: junk is a judgement about the item and dims to
	-- the junk colour, but this is a statement about where the item IS, so it
	-- keeps its own colours and simply steps back.
	local isJunk = cfg.dimJunk and info.quality == 0
	if info.isLocked then
		b.icon:SetVertexColor(1, 1, 1, 1)
		b:SetAlpha(0.35)
		if b.icon.SetDesaturated then pcall(b.icon.SetDesaturated, b.icon, true) end
	elseif isJunk then
		local j = c.junkTint
		b.icon:SetVertexColor(j[1], j[2], j[3], 1)
		b:SetAlpha(j[4] or 0.42)
		if b.icon.SetDesaturated then pcall(b.icon.SetDesaturated, b.icon, true) end
	else
		b.icon:SetVertexColor(1, 1, 1, 1)
		b:SetAlpha(1)
		if b.icon.SetDesaturated then pcall(b.icon.SetDesaturated, b.icon, false) end
	end

	-- Quality rim. `quality` is NILABLE on this build, so an unknown quality
	-- draws the neutral rim rather than indexing the table with nil.
	local q = cfg.qualityRim and info.quality and c.itemQuality and c.itemQuality[info.quality]
	if q then
		local e = q.edge
		b.edge:SetVertexColor(e[1], e[2], e[3], e[4] or 1)
		if q.glow then
			local g = q.glow
			b.glow:SetVertexColor(g[1], g[2], g[3], g[4] or 1)
			b.glow:Show()
		else
			b.glow:Hide()
		end
	else
		local e = c.glassEdge
		b.edge:SetVertexColor(e[1], e[2], e[3], e[4] or 1)
		b.glow:Hide()
	end

	-- Cooldown swipe, from the template's own frame. CooldownFrame_Set is
	-- Blizzard's and handles the "no cooldown" case itself.
	if b._blizzCooldown and GetCooldownAt and _G.CooldownFrame_Set then
		local ok, s, d, e2 = pcall(GetCooldownAt, b.bag, b.slot)
		if ok then pcall(_G.CooldownFrame_Set, b._blizzCooldown, s, d, e2) end
	end

	return info
end

-- ---------------------------------------------------------------------------
-- pools
--
-- W.Pool, the same as the quest log's rows. Labels are keyed by position, but
-- the items are keyed by (bag, slot): a slot's identity is fixed for the life
-- of the session, so a button is built once and only ever re-anchored -- which
-- means no button is ever pointing at an item other than the one it was built
-- for, and the whole class of stale-index bugs simply cannot occur.
-- ---------------------------------------------------------------------------

--- A window's three pools. The scroll child is read lazily, so this can run
--  before it exists.
local function BuildPools(frame)
	-- One proxy per bag, because the item template reads the bag off its
	-- parent's GetID() -- see the header.
	frame.proxies = W.Pool(function(bag)
		local p = CreateFrame("Frame", nil, frame.scroll.child)
		p:SetAllPoints(frame.scroll.child)
		p:SetID(bag)
		p.id = bag
		return p
	end)

	frame.buttons = W.Pool(function(bag, slot, size)
		return BuildItemButton(frame.proxies:Get(bag), bag, slot, size)
	end, 2)

	frame.labels = W.Pool(function()
		local row = CreateFrame("Frame", nil, frame.scroll.child)
		row:SetHeight(SEC_LABEL_H)

		row.text = W.Text(row, "bagLabel", "LEFT")
		row.text:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)

		row.count = W.Text(row, "bagCount", "LEFT")
		row.count:SetPoint("LEFT", row.text, "RIGHT", 8, 0)

		return row
	end)
end

local function ItemPool(frame, bag, slot, size)
	local b = frame.buttons:Get(bag, slot, size)
	if b:GetWidth() ~= size then
		b:SetSize(size, size)
		-- DecorateSlot draws the glow at twice the slot and centres it, so it
		-- has to be resized with the button or a rare item's bloom drifts out
		-- of proportion the moment the setting is touched.
		if b.glow then b.glow:SetSize(size * 2, size * 2) end
	end
	return b
end

-- ---------------------------------------------------------------------------
-- window chrome
-- ---------------------------------------------------------------------------

--- An icon drawn out of the atlas we have rather than one we do not.
--
--  The deck's header icons are lucide line drawings and there is no vector
--  drawing in the WoW UI. Rather than commission a texture per glyph, the sort
--  control is three descending rules -- which is what the lucide icon is, minus
--  the arrow -- and the close is the multiplication sign, as everywhere else in
--  this UI.
local function BuildIconButton(parent, kind, onClick, tip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)
	b._kind = kind
	b.bars = {}

	if kind == "close" then
		b.label = W.Text(b, "bagTitle", "CENTER")
		b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
		b.label:SetText("\195\151")            -- U+00D7 MULTIPLICATION SIGN
	else
		for i = 1, 3 do
			local t = b:CreateTexture(nil, "ARTWORK")
			t:SetTexture(Media.texture.flat)
			t:SetHeight(A:Px(2))
			t:SetWidth(ICON_SIZE - (i - 1) * 4)
			t:SetPoint("LEFT", b, "LEFT", 3, 6 - (i - 1) * 5)
			b.bars[i] = t
		end
	end

	function b:Restyle(over)
		local c = Palette.c
		local col = over and c.text or c.textDim
		if self.label then
			W.Color(self.label, col)
		else
			for _, t in ipairs(self.bars) do
				t:SetVertexColor(col[1], col[2], col[3], (col[4] or 1) * 0.9)
			end
		end
	end

	-- AND IT SAYS WHAT IT DOES. Three bars in a header is a picture of a
	-- list, not a promise about what pressing it will do to your bags - and
	-- this one moves every item you own.
	b:SetScript("OnEnter", function(self)
		self:Restyle(true)
		if not (tip and _G.GameTooltip) then return end
		_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		_G.GameTooltip:AddLine(tip[1])
		if tip[2] then
			local c = Palette.c.textDim
			_G.GameTooltip:AddLine(tip[2], c[1], c[2], c[3], true)
		end
		_G.GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self:Restyle(false)
		if _G.GameTooltip then _G.GameTooltip:Hide() end
	end)
	b:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
	b:Restyle(false)
	return b
end

local function BuildHeader(frame)
	local head = CreateFrame("Frame", nil, frame)
	head:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	head:SetHeight(HEAD_H)
	frame.head = head

	head.title = W.Text(head, "bagTitle", "LEFT")
	head.title:SetPoint("LEFT", head, "LEFT", HEAD_PAD_X, 0)
	head.title:SetText(frame.kind == "bank" and "Bank" or "Bags")

	head.count = W.Pill(head, "bagChip", { height = 20, padX = 9 })
	head.count:SetPoint("LEFT", head.title, "RIGHT", HEAD_GAP, 0)

	-- The shared way out, which every panel in this interface wears. It was
	-- one of four designs; see W.CloseButton.
	head.close = W.CloseButton(head, {
		onClick = function() Bags:CloseFrom(frame) end,
	})
	head.close:SetPoint("RIGHT", head, "RIGHT", -HEAD_PAD_X, 0)

	head.sort = BuildIconButton(head, "sort",
		function() Bags:StartSort(frame) end,
		{ "Combine", "Stack what can be stacked and move everything up, so the" .. " empty slots end up together at the bottom." })
	head.sort:SetPoint("RIGHT", head.close, "LEFT", -6, 0)

	-- THE HAIRLINE ALONG ITS FOOT, which is what makes this a header band
	-- rather than a row of controls floating over the grid. Every panel in the
	-- interface wears one; this window had one under its FOOTER and nothing
	-- under its head.
	head.rule = BuildHairline(head)
	head.rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", W.RULE_GAP, 0)
	head.rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -W.RULE_GAP, 0)

	return head
end

local function BuildSearch(frame)
	-- A ROUNDED RECTANGLE, not a capsule, for the reason the quest log's
	-- carries: a pill's two caps come out of a 256-texel texture and at this
	-- height they are minified past the point the client can resolve, with no
	-- mipmap behind them. Crunched ends on a field you look straight at.
	-- IN THE HEADER BAND, not on a row of its own under it. A search field is
	-- chrome - it acts on what the window is showing - and the quest log has
	-- carried it in the band since it was built. A whole strip of window given
	-- over to one field is the thing 15a's header exists to stop.
	local head = frame.head
	local search = Glass.CreatePanel(head, {
		corner = W.WELL_CORNER, fill = "glassSoft", edge = "glassEdge",
	})
	search:SetHeight(SEARCH_H)
	search:SetWidth(SEARCH_W)
	search:SetPoint("RIGHT", head.sort, "LEFT", -HEAD_GAP, 0)
	frame.search = search

	-- The deck's magnifier. There is no vector drawing in the WoW UI, so it is
	-- the ring texture at 11px with a rotated hairline for the handle -- which
	-- is what a magnifier is. Cheaper than a texture file for one glyph, and it
	-- tints with the skin for free.
	local lens = search:CreateTexture(nil, "ARTWORK")
	lens:SetTexture(Media.texture.ring)
	lens:SetSize(11, 11)
	lens:SetPoint("LEFT", search, "LEFT", 13, 1)
	search.lens = lens

	local handle = search:CreateTexture(nil, "ARTWORK")
	handle:SetTexture(Media.texture.flat)
	handle:SetSize(5, A:Px(2))
	handle:SetPoint("CENTER", lens, "CENTER", 5, -5)
	if handle.SetRotation then pcall(handle.SetRotation, handle, -0.785) end
	search.lensHandle = handle

	local box = CreateFrame("EditBox", nil, search)
	box:SetPoint("LEFT", search, "LEFT", 31, 0)
	box:SetPoint("RIGHT", search, "RIGHT", -12, 0)
	box:SetHeight(SEARCH_H)
	box:SetAutoFocus(false)
	Media:SetFont(box, "bagSearch")
	W.Color(box, Palette.c.text)
	-- Escape clears the search rather than closing the window, while the cursor
	-- is in it. Closing a window because somebody wanted to undo a filter is the
	-- kind of thing that gets an addon uninstalled.
	box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnTextChanged", function(self) Bags:SetFilter(frame, self:GetText()) end)
	search.box = box

	search.placeholder = W.Text(search, "bagSearch", "LEFT")
	search.placeholder:SetPoint("LEFT", box, "LEFT", 0, 0)
	search.placeholder:SetText(frame.kind == "bank"
		and "Search bank\226\128\166" or "Search items\226\128\166")   -- ellipsis

	search:EnableMouse(true)
	search:SetScript("OnMouseDown", function() box:SetFocus() end)

	return search
end

local function BuildFooter(frame)
	local foot = CreateFrame("Frame", nil, frame)
	foot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	foot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	foot:SetHeight(FOOT_H)
	frame.foot = foot

	foot.rule = BuildHairline(foot)
	foot.rule:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, 0)
	foot.rule:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, 0)

	if frame.kind == "bank" then
		-- BANK BAGS: the label, then the owned bag tiles, then the purchasable
		-- ones, all right-aligned. Built lazily in RefreshFooter because how many
		-- there are depends on what has been bought.
		foot.label = W.Text(foot, "bagLabel", "LEFT")
		foot.label:SetPoint("LEFT", foot, "LEFT", SEARCH_PAD_X, 0)
		foot.label:SetText(Media:Track("BANK BAGS", 1))
		foot.tiles = {}
		return foot
	end

	-- The coin. A flat texture behind a circle mask, tinted gold -- there is no
	-- radial gradient in this UI and a 13px dot does not need one.
	local coin = foot:CreateTexture(nil, "ARTWORK")
	coin:SetTexture(Media.texture.flat)
	coin:SetSize(COIN_SIZE, COIN_SIZE)
	coin:SetPoint("LEFT", foot, "LEFT", FOOT_PAD_X, 0)
	local gold = Palette.c.money
	coin:SetVertexColor(gold[1], gold[2], gold[3], 1)
	W.AddMask(coin, foot, Media.texture.circleMask, coin)
	foot.coin = coin

	foot.money = W.Text(foot, "bagMoney", "LEFT")
	foot.money:SetPoint("LEFT", coin, "RIGHT", 8, 0)

	foot.free = W.Text(foot, "bagFoot", "RIGHT")
	foot.free:SetPoint("RIGHT", foot, "RIGHT", -FOOT_PAD_X, 0)

	return foot
end

-- ---------------------------------------------------------------------------
-- the equipped-bags drawer, and the keyring under it
--
-- A DRAWER THAT SLIDES, not a wing that is always there. Shut, all you get is a
-- slim handle hugging the window's right edge - the same rail language as the
-- Toolbox and the party dock, so it is a control the player has already met.
--
-- CLIPPED, NEVER TUCKED BEHIND. This is the whole reason the drawer is not a
-- frame at a lower level that the window slides over, which is how you would
-- write it anywhere else:
--
--   our panels are TRANSLUCENT. A drawer parked behind the bags window reads
--   straight through the glass, so "shut" is a bag-shaped smear down the right
--   edge and the slide is that smear getting darker.
--
-- So the drawer lives inside a clip window whose LEFT edge sits exactly on the
-- bags panel's right edge. Anything left of that line is not drawn at all -
-- there is no level, no alpha and no strata involved, and nothing to show
-- through. The drawer TRANSLATES within it, which is why there is no fade: the
-- handoff's opacity ramp exists to stop a one-pixel sliver of glass popping in
-- when the container's WIDTH is what animates, and a drawer that emerges
-- whole from behind an edge has no sliver to hide.
--
-- Its left corners still sit under the panel by one corner radius. Our panels
-- have one radius on all four corners, so that overlap is what gives the deck's
-- flush, square-on-the-left edge without a second nine-slice - and now the clip
-- takes it rather than the panel merely covering it.
--
-- CLIPPING IS VISUAL ONLY. A clipped frame still takes the mouse, and shut, the
-- whole drawer is sitting over the item grid: an invisible bag row would eat
-- clicks meant for the bags underneath it and pop tooltips for a list nobody
-- can see. So the drawer is HIDDEN at rest and its controls are mouse-dead
-- while it is in transit; only a settled, fully open drawer is live.
-- ---------------------------------------------------------------------------

-- Forward-declared: BuildBagTile wires each tile as it makes one, and the
-- handlers are written below because they are the interesting part.
local WireBagTile

local function BuildBagTile(parent, size, corner)
	local tile = Glass.CreatePanel(parent, { corner = corner, frameType = "Button" })
	tile:SetSize(size, size)

	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetAllPoints(tile)
	tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	W.AddMask(tile.icon, tile, Media.texture.slotMask, tile.icon)

	tile.glyph = W.Text(tile, "bagGlyph", "CENTER")
	tile.glyph:SetPoint("CENTER", tile, "CENTER", 0, 0)

	tile.price = W.Text(tile, "bagPrice", "CENTER")
	tile.price:SetPoint("CENTER", tile, "CENTER", 0, 0)
	tile.price:Hide()

	WireBagTile(tile)
	return tile
end

--- Wire a tile up ONCE, at build time.
--
--  Drag and drop here needs no secure template: PickupBagFromSlot and
--  PutItemInBag are ordinary globals, and both reference addons on this client
--  drive them from a plain button. Dropping a bag on an equipped one swaps it
--  and puts the old one on the cursor, which is the client's own behaviour --
--  there is nothing to implement and no drop target to draw.
--
--  The handlers read self.bag / self.invSlot rather than closing over them, so
--  rebinding a tile to a different bag is two field writes. Installing six
--  closures per tile per redraw, on a path driven by ITEM_LOCK_CHANGED, is a
--  lot of garbage for a window that redraws ten times a second during a drag.
function WireBagTile(tile)
	tile:RegisterForDrag("LeftButton")
	tile:RegisterForClicks("AnyUp")

	-- Every handler asks the TILE what it currently is, rather than the layout
	-- pass swapping scripts around underneath it.
	--
	-- It used to swap them: a purchasable slot had its drag, drop and tooltip
	-- handlers torn off and a "buy" click put in their place. Tiles are recycled
	-- by index, and nothing put the handlers back when a slot was bought - so a
	-- freshly bought bank slot would not accept a bag and offered to sell you
	-- the NEXT one instead, which is exactly what it did in game, for 10g.
	tile:SetScript("OnDragStart", function(self)
		if self.invSlot and _G.PickupBagFromSlot then
			pcall(_G.PickupBagFromSlot, self.invSlot)
		end
	end)

	local function receive(self)
		if not _G.CursorHasItem or not _G.CursorHasItem() then return end
		if self.bag == BACKPACK then
			if _G.PutItemInBackpack then pcall(_G.PutItemInBackpack) end
		elseif self.bag == KEYRING then
			if _G.PutKeyInKeyRing then pcall(_G.PutKeyInKeyRing) end
		elseif self.invSlot and _G.PutItemInBag then
			pcall(_G.PutItemInBag, self.invSlot)
		end
	end

	tile:SetScript("OnReceiveDrag", receive)
	tile:SetScript("OnClick", function(self, button)
		-- Only the NEXT slot is buyable. Blizzard sells them in order and
		-- PurchaseSlot takes no argument, so a click on the one after would buy
		-- a different slot from the one whose price it is showing.
		if self.buyable then return Bags:AskBuyBankSlot() end
		if button == "LeftButton" then receive(self) end
	end)

	tile:SetScript("OnEnter", function(self)
		if not self.invSlot or not self:GetRight() then return end
		_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		pcall(_G.GameTooltip.SetInventoryItem, _G.GameTooltip, "player", self.invSlot)
		_G.GameTooltip:Show()
	end)
	tile:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
	return tile
end

--- Point an already-wired tile at a bag.
local function BindBagTile(tile, bag, invSlot)
	tile.bag, tile.invSlot = bag, invSlot
	-- A tile pointed at a bag is not a shop. THIS is the fix: the tile is
	-- recycled, so the bank footer's "buy" state has to be cleared by whatever
	-- gives it a bag, rather than by whatever set it.
	tile.buyable = nil
end

--- The tab you pull the drawer out by.
--
--  A SIBLING OF THE CLIP WINDOW, not a child of it: it is the one part that has
--  to still be there when everything else has been clipped away to nothing.
--  It travels with the drawer's outer edge, which is the Toolbox rail's rule -
--  a handle that stays behind while the thing it opens moves is a handle for
--  something else.
--
--  It also SAYS WHAT IS BEHIND IT, which is the party dock handle's idea: a
--  glyph with a number under it, so a shut drawer still tells you how many bags
--  you are carrying and how many keys are on the ring. A tab with nothing on it
--  but an arrow says only that something opens.
local function BuildRail(frame)
	local rail = Glass.CreatePanel(frame, {
		frameType = "Button",
		corner    = RAIL_CORNER,
		fill      = "glass",
		shadow    = A.db.profile.glass.shadow,
	})
	rail:SetWidth(RAIL_THICK)
	-- Above the window it is attached to AND above the drawer it opens, because
	-- it bites into both and has to be the thing on top at the join.
	rail:SetFrameLevel(frame:GetFrameLevel() + 8)
	frame.flyRail = rail

	local chev = rail:CreateTexture(nil, "OVERLAY")
	chev:SetSize(RAIL_CHEV, RAIL_CHEV)
	chev:SetTexture(Media.texture.chevron)
	-- Plain text at 75%, which is what the Toolbox rail's arrow is. Two docks
	-- whose arrows disagree is a detail nobody can name and everybody sees.
	W.Tint(chev, Palette.c.text, 0.75)
	rail.chev = chev

	-- The handoff's hairline under the arrow: the control above it, the
	-- readouts below. 18 in the deck, and the rail is only 16 across inside its
	-- padding - so it is the inner width, which is what "a rule across the tab"
	-- means at this size.
	rail.rule = BuildHairline(rail)

	-- One pair per thing the drawer holds. Both are drawn from the sheet rather
	-- than from a letter, because a "B" and a "K" on a tab this narrow read as
	-- a keybinding rather than as a picture of what is inside.
	for _, part in ipairs({ "bags", "keys" }) do
		local glyph = rail:CreateTexture(nil, "OVERLAY")
		glyph:SetSize(RAIL_GLYPH, RAIL_GLYPH)
		Media:SetIcon(glyph, part)
		W.Tint(glyph, Palette.c.text, 0.7)

		local count = W.Text(rail, "tiny", "CENTER")
		rail[part] = { glyph = glyph, count = count }
	end

	rail:EnableMouse(true)
	rail:RegisterForClicks("AnyUp")
	rail:SetScript("OnClick", function() Bags:ToggleDrawer() end)
	rail:SetScript("OnEnter", function(self)
		W.SetButtonState(self, false, true)
		if not _G.GameTooltip then return end
		_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		_G.GameTooltip:SetText("Equipped bags")
		_G.GameTooltip:Show()
	end)
	rail:SetScript("OnLeave", function(self)
		W.SetButtonState(self, false, false)
		if _G.GameTooltip then _G.GameTooltip:Hide() end
	end)

	return rail
end

local function BuildFlyout(frame)
	-- THE CLIP WINDOW. Its left edge is the reveal line, flush with the bags
	-- panel's right edge; the other three are opened out by the drawer's shadow
	-- reach so the clip does not shave it off. See the note above this section
	-- for why this exists at all.
	local clip = CreateFrame("Frame", nil, frame)
	clip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -FLY_TOP + FLY_CLIP_PAD)
	clip:SetSize(FLY_W + FLY_CLIP_PAD, FLY_CLIP_PAD * 2)
	if clip.SetClipsChildren then pcall(clip.SetClipsChildren, clip, true) end
	frame.flyClip = clip

	local fly = Glass.CreatePanel(clip, {
		corner = FLY_CORNER, fill = "glass", shadow = A.db.profile.glass.shadow,
	})
	fly:SetWidth(FLY_W + FLY_CORNER)
	frame.flyout = fly

	BuildRail(frame)

	fly.label = W.Text(fly, "bagLabel", "LEFT")
	fly.label:SetPoint("TOPLEFT", fly, "TOPLEFT", FLY_CORNER + FLY_PAD + 4, -FLY_PAD)
	fly.label:SetText(Media:Track("EQUIPPED BAGS", 1))

	fly.rows = {}
	fly.keys = {}

	fly.rule = BuildHairline(fly)
	fly.rule:SetPoint("LEFT", fly, "LEFT", FLY_CORNER + FLY_PAD, 0)
	fly.rule:SetPoint("RIGHT", fly, "RIGHT", -FLY_PAD, 0)

	-- THE KEY BESIDE THE KEYRING HEADING. A little flat square stood in
	-- for it until the sheet had a key on it; now that the handle needs
	-- one, both take the same drawing.
	fly.keyIcon = fly:CreateTexture(nil, "ARTWORK")
	Media:SetIcon(fly.keyIcon, "keys")
	fly.keyIcon:SetSize(11, 11)

	fly.keyLabel = W.Text(fly, "bagLabel", "LEFT")
	fly.keyLabel:SetText(Media:Track("KEYRING", 1))

	fly.keyCount = W.Text(fly, "bagCount", "RIGHT")

	return fly
end

local function FlyRowPool(fly, n)
	local row = fly.rows[n]
	if not row then
		row = CreateFrame("Frame", nil, fly)
		row:SetHeight(FLY_ROW_H)
		row:EnableMouse(true)

		row.bg = Glass.CreatePanel(row, { corner = 12, fill = "glass" })
		row.bg:SetAllPoints(row)
		row.bg:SetEdgeShown(false)
		row.bg:SetAlpha(0)

		row.tile = BuildBagTile(row, TILE, TILE_CORNER)
		row.tile:SetPoint("LEFT", row, "LEFT", 8, 0)

		row.name = W.Text(row, "bagBag", "LEFT")
		row.name:SetPoint("TOPLEFT", row.tile, "TOPRIGHT", 10, -1)
		row.name:SetWidth(FLY_W - TILE - 34)

		row.sub = W.Text(row, "bagBagSub", "LEFT")
		row.sub:SetPoint("BOTTOMLEFT", row.tile, "BOTTOMRIGHT", 10, 1)

		row:SetScript("OnEnter", function(self) self.bg:SetAlpha(1) end)
		row:SetScript("OnLeave", function(self) self.bg:SetAlpha(0) end)

		fly.rows[n] = row
	end
	return row
end

-- ---------------------------------------------------------------------------
-- opening and closing the drawer
-- ---------------------------------------------------------------------------

--- Under the cursor only when the drawer has arrived.
--
--  CLIPPING HIDES; IT DOES NOT DEAFEN. Shut, the drawer is sitting whole over
--  the item grid with nothing drawn of it - so an invisible bag row would take
--  the hover, pop a tooltip for a bag that is not on screen and swallow a click
--  meant for the item underneath. Hiding covers the resting state; this covers
--  the 300ms in between, where the drawer has to be drawn and must not be live.
local function SetDrawerLive(fly, live)
	if not fly or fly.__live == live then return end
	fly.__live = live

	for _, row in ipairs(fly.rows or {}) do
		row:EnableMouse(live)
		if row.tile then row.tile:EnableMouse(live) end
		-- A row hovered as the drawer starts closing keeps its highlight
		-- otherwise: OnLeave never fires for a frame that stops taking mouse.
		if not live and row.bg then row.bg:SetAlpha(0) end
	end
	for _, b in pairs(fly.keyButtons or {}) do b:EnableMouse(live) end
end

--- Whether the drawer is out, remembered per character.
--
--  Per character rather than per profile, and for the same reason the Toolbox's
--  dock is: whether you keep your bag list open is a habit somebody forms on
--  one character, not a look they picked.
function Bags:DrawerOpen()
	local c = A.db and A.db.char
	return (c and c.bags and c.bags.drawerOpen) and true or false
end

--- What the handle holds, and how long it has to be to hold it.
--
--  Sized from its contents rather than from a number, the way the Toolbox
--  rail's width is: the keyring is a setting, and on a game version with no
--  keyring there is nothing to count - so a fixed length would leave a hole in
--  the tab the day the keys stop being drawn.
--
--  The counts come off the last refresh rather than from the client, so this is
--  free to run on the animation frame.
function Bags:LayoutRail(frame)
	frame = frame or (self.frames and self.frames.bags)
	local rail, fly = frame and frame.flyRail, frame and frame.flyout
	if not (rail and fly) then return end

	local c = Palette.c
	local keys = fly.__nKeys or 0
	local pairs_ = { { rail.bags, fly.__nBags or 0 } }
	if keys > 0 then pairs_[#pairs_ + 1] = { rail.keys, keys } end

	local y = RAIL_PAD
	rail.chev:ClearAllPoints()
	rail.chev:SetPoint("TOP", rail, "TOP", 0, -y)
	y = y + RAIL_CHEV + RAIL_GAP

	rail.rule:ClearAllPoints()
	rail.rule:SetPoint("TOPLEFT", rail, "TOPLEFT", RAIL_PAD, -y)
	rail.rule:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -RAIL_PAD, -y)
	ColorHairline(rail.rule)
	y = y + 1 + RAIL_GAP

	for _, pair in ipairs(pairs_) do
		local part, n = pair[1], pair[2]
		part.glyph:ClearAllPoints()
		part.glyph:SetPoint("TOP", rail, "TOP", 0, -y)
		part.glyph:Show()
		W.Tint(part.glyph, c.text, 0.7)
		y = y + RAIL_GLYPH + RAIL_TIGHT

		part.count:ClearAllPoints()
		part.count:SetPoint("TOP", rail, "TOP", 0, -y)
		part.count:SetText(tostring(n))
		part.count:Show()
		W.Color(part.count, c.textDim)
		y = y + RAIL_COUNT_H + RAIL_GAP
	end

	if keys <= 0 then
		rail.keys.glyph:Hide()
		rail.keys.count:Hide()
	end

	-- The last gap is inside the tab rather than under the last thing in it.
	rail:SetHeight(y - RAIL_GAP + RAIL_PAD)
end

--- Put the drawer, the clip window and the handle where `_travel` says.
function Bags:LayoutDrawer(frame)
	frame = frame or (self.frames and self.frames.bags)
	local clip, fly, rail = frame and frame.flyClip, frame and frame.flyout,
		frame and frame.flyRail
	if not (clip and fly and rail) then return end

	-- Off entirely is off entirely: no handle either, or there is a control on
	-- screen for a thing the player has turned off.
	if A.Config:Module("bags").showFlyout == false then
		fly:Hide()
		clip:Hide()
		rail:Hide()
		return
	end
	clip:Show()
	rail:Show()

	local t = self._travel or 0
	-- EASE OUT: away from the edge quickly, settling into place. Over 300ms a
	-- linear travel reads as a panel being dragged rather than one let go of.
	local e = 1 - (1 - t) * (1 - t)

	local h = fly:GetHeight() or 0
	clip:SetHeight(h + FLY_CLIP_PAD * 2)

	-- Shut, the drawer's RIGHT edge lands exactly on the reveal line and none
	-- of it is drawn. Open, its left corners sit a radius past that line, under
	-- the panel, where the clip takes them.
	fly:ClearAllPoints()
	fly:SetPoint("TOPLEFT", clip, "TOPLEFT",
		-FLY_CORNER - (1 - e) * FLY_W, -FLY_CLIP_PAD)

	fly:SetShown(t > 0)
	SetDrawerLive(fly, t >= 1)

	-- The handle rides the drawer's outer edge, biting into it by its own
	-- corner radius so the two read as one shape. Centred on the drawer, which
	-- is a fixed place whether it is out or not.
	rail:ClearAllPoints()
	rail:SetPoint("LEFT", frame, "TOPRIGHT",
		e * FLY_W - RAIL_BITE, -(FLY_TOP + h / 2))

	-- THE ARROW POINTS THE WAY THE CLICK WILL SEND IT, and it follows the
	-- INTENT rather than where the drawer has got to - so reversing mid-slide
	-- turns it over at once instead of halfway through the journey back.
	W.FaceChevron(rail.chev, (self._want or 0) > 0.5 and "LEFT" or "RIGHT")
end

function Bags:SetDrawerOpen(open, instant)
	open = open and true or false

	local c = A.db and A.db.char
	if c then
		c.bags = c.bags or {}
		c.bags.drawerOpen = open
	end
	self._want = open and 1 or 0

	local frame = self.frames and self.frames.bags
	if not (frame and frame.flyClip) then
		self._travel = self._want
		return
	end

	if instant or not frame:IsShown() then
		self._travel = self._want
		W.StopSlide(frame.flyClip)
		self:LayoutDrawer(frame)
		return
	end

	-- Hung on the CLIP WINDOW because that is a frame which is on screen for
	-- the whole slide - the drawer inside it is not, being hidden at rest.
	W.DriveSlide(frame.flyClip, self, FLY_SLIDE_RATE, function(o)
		o:LayoutDrawer(frame)
	end)
end

function Bags:ToggleDrawer()
	self:SetDrawerOpen(not self:DrawerOpen())
	return self:DrawerOpen()
end

-- ---------------------------------------------------------------------------
-- building a window
-- ---------------------------------------------------------------------------

local function Metrics(cfg)
	local cols = math.max(4, math.min(16, tonumber(cfg.columns) or 8))
	local size = math.max(24, math.min(64, tonumber(cfg.slotSize) or 44))
	local gap  = math.max(0, math.min(16, tonumber(cfg.slotGap) or 6))
	local gridW = cols * size + (cols - 1) * gap
	return cols, size, gap, gridW, gridW + GRID_PAD_X * 2
end

local function BuildFrame(kind)
	local cfg = A.Config:Module("bags")
	local _, _, _, _, winW = Metrics(cfg)

	local frame = Glass.CreatePanel(UIParent, {
		name   = kind == "bank" and "AetherUIBank" or "AetherUIBags",
		corner = WIN_CORNER,
		shadow = A.db.profile.glass.shadow,
		fill   = "glassStrong",
	})
	-- A READING fill, not a control fill. This panel carries item names in
	-- tooltips, stack counts, a money string and five section headings over
	-- whatever the world is doing behind it, and at the control opacity the
	-- clutter behind competes with all of them. Chat and the quest log take the
	-- same helper, so the three cannot drift apart.
	frame:SetFillColor(Palette:ReadingFill())
	frame.kind = kind
	frame:SetWidth(winW)
	frame:SetHeight(400)
	frame:SetFrameStrata("HIGH")
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	frame:Hide()

	BuildPools(frame)
	frame.filter = ""

	BuildHeader(frame)
	BuildSearch(frame)
	BuildFooter(frame)

	-- IN A WELL. The grid is the thing on this window that grows, and it
	-- used to float in the frame with nothing marking where it began or
	-- ended. Ten out of the grid's own twenty-four leaves fourteen of air
	-- between the recess and the side of the window.
	local scroll = W.Scroller(frame, SCROLL_STEP, { outset = 10 })
	frame.scroll = scroll

	if kind == "bags" then BuildFlyout(frame) end

	-- AND PAINTED, HERE, rather than only when the skin changes. Every colour
	-- on this window - the title's ink, both hairlines, the search field's
	-- placeholder and its lens - was set in one function that OnSkinChanged
	-- was the only caller of. So a freshly built window wore whatever those
	-- pieces happened to default to until you switched skins and back, which
	-- is why it came up with no title and no line under its header.
	RestyleFrame(frame)

	-- ESC, handled on the frame rather than through UISpecialFrames.
	--
	-- UISpecialFrames is registered as well, because other addons walk it, but it
	-- cannot be the mechanism: CloseSpecialWindows closes through HideUIPanel,
	-- which is combat-blocked on this client and fails SILENTLY. Pressing escape
	-- mid-fight would leave the window open and blame the player's UI.
	--
	-- Propagation is restored for every key we do not act on. Setting it false
	-- once and leaving it there is a total input lockout -- no movement, no
	-- keybinds, no chat -- for as long as the window is open.
	--
	-- Through A:SetPropagate, never the widget method: it is protected in combat,
	-- and this handler runs on every keypress the window is open for. See the
	-- note there.
	-- Keyboard capture is armed in OnShow, not here, and only once propagation
	-- is actually established - see A:SetPropagate. A frame that captures but
	-- cannot pass keys on eats every one of them, and the call that would fix
	-- that is refused in combat. Arming it per-open rather than once at build
	-- means a window first opened mid-fight comes up without capture and picks
	-- it up the next time, instead of being stuck for the session.
	frame:SetScript("OnKeyDown", function(self, key)
		if key ~= "ESCAPE" then
			A:SetPropagate(self, true)
			return
		end
		A:SetPropagate(self, false)
		if self.search and self.search.box:HasFocus() then
			self.search.box:SetText("")
			self.search.box:ClearFocus()
		else
			Bags:CloseFrom(self)
		end
		-- And straight back on, rather than waiting for the next key to restore
		-- it. Clearing the search box leaves the window OPEN with propagation
		-- held: if a fight started before the player touched another key, the
		-- restore would be a protected call we are no longer allowed to make and
		-- the window would eat everything until they closed it.
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(0.1, function() A:SetPropagate(self, true) end)
		else
			A:SetPropagate(self, true)
		end
	end)

	frame:SetScript("OnShow", function(self)
		self:EnableKeyboard(A:SetPropagate(self, true))
		if self.dirty or not self.drawn then Bags:Rebuild(self) end
		-- THE DRAWER COMES BACK WHERE YOU LEFT IT, and without the slide. An
		-- animation on open is 300ms of the window still assembling itself in
		-- front of you every single time you press B.
		if self.kind == "bags" then
			Bags:SetDrawerOpen(Bags:DrawerOpen(), true)
		end
	end)
	frame:SetScript("OnHide", function(self)
		if self.search then self.search.box:ClearFocus() end
		-- A confirmation left floating over a closed window is a click waiting
		-- to spend gold on something nobody is looking at any more.
		Bags:CloseConfirm()
		-- Hung on OnHide rather than only on our own close paths, because this
		-- window is in UISpecialFrames and CloseSpecialWindows reaches it
		-- directly. A bank window that goes away without CloseBankFrame leaves
		-- the server believing the player is still standing at the banker.
		if self.kind == "bank" then Bags:HideBank() end
	end)

	return frame
end

--- The window a given kind draws from.
local function BagListFor(kind)
	if kind == "bank" then return BankBags() end
	return InventoryBags()
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------

--- Collect, bucket, then lay out. In that order, and never while hidden.
--
--  Nothing is drawn for a closed window. That is not only an economy: at a
--  banker the bank's containers answer for a session that can end at any
--  moment, and a restyle or a resolution change with the window shut would
--  otherwise walk every bank slot for a panel nobody can see.
function Bags:Rebuild(frame)
	if not frame or not frame:IsShown() then
		if frame then frame.dirty = true end
		return
	end
	if self.loading then frame.dirty = true return end

	local cfg = A.Config:Module("bags")
	local c = Palette.c
	local cols, size, gap, gridW = Metrics(cfg)
	local cats = CATEGORIES
	local child = frame.scroll.child

	local filter = frame.filter or ""
	local buckets, empties = {}, {}
	local used, total = 0, 0

	-- A SPECIALIST BAG IS ITS OWN SECTION, holding what is in it and the room
	-- it has left. Keyed by the word the family is called, with `order`
	-- remembering which turned up first so the sections do not shuffle between
	-- redraws the way pairs() would.
	--
	-- Its contents are NOT re-filed by what they are made of. Arrows are trade
	-- goods and were landing under TRADE GOODS next to the linen, which is true
	-- and useless: what matters about the four stacks in your quiver is that
	-- they are in the quiver. A bag that only takes one thing is a category the
	-- game has already made.
	local special, order = {}, {}

	local function Special(word)
		if not special[word] then
			special[word] = { items = {}, empties = {} }
			order[#order + 1] = word
		end
		return special[word]
	end

	for _, bag in ipairs(BagListFor(frame.kind)) do
		local n = SlotsIn(bag)
		total = total + n
		local word = FamilyWord(BagFamily(bag))
		for slot = 1, n do
			local b = ItemPool(frame, bag, slot, size)
			local info = UpdateItemButton(b, cfg)
			if info then
				used = used + 1

				if word then
					local s = Special(word)
					s.items[#s.items + 1] = b
				else
					local key = CategoryOf(info, bag, slot)
					buckets[key] = buckets[key] or {}
					buckets[key][#buckets[key] + 1] = b
				end

				-- Filtering DIMS rather than removes. A grid whose cells move
				-- under the cursor while you are typing is disorienting, and the
				-- thing you are hunting for keeps changing address as you narrow
				-- it down. Plain find, so a `-` or a `%` in the box is a
				-- character and not a pattern.
				if filter ~= "" then
					local name = NameOf(info)
					local hit = name and string.find(string.lower(name), filter, 1, true)
					if not hit then b:SetAlpha(0.25) end
				end
			elseif word then
				local s = Special(word)
				s.empties[#s.empties + 1] = b
				b:Hide()
			else
				empties[#empties + 1] = b
				b:Hide()
			end
		end
	end

	-- Retire every button that belongs to a bag this window no longer draws --
	-- a bank bag that was sold, or the keyring after the last key went.
	for bag, row in pairs(frame.buttons) do
		local n = SlotsIn(bag)
		for slot, b in pairs(row) do
			if slot > n then b:Hide() end
		end
	end

	local y = GRID_TOP
	local labelN = 0

	local function Section(label, list, note)
		if not list or #list == 0 then return end
		labelN = labelN + 1
		local lab = frame.labels:Get(labelN)
		if labelN > 1 then y = y + SEC_GAP end
		lab:ClearAllPoints()
		lab:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		lab:SetWidth(gridW)
		lab.text:SetText(Media:Track(label, 1))
		W.Color(lab.text, c.textDim)
		lab.count:SetText(note and (#list .. "  \194\183  " .. note) or tostring(#list))
		W.Color(lab.count, c.textFaint)
		lab:Show()
		y = y + SEC_LABEL_H + SEC_LABEL_GAP

		for i, b in ipairs(list) do
			local col = (i - 1) % cols
			local r = math.floor((i - 1) / cols)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", child, "TOPLEFT",
				col * (size + gap), -(y + r * (size + gap)))
			b:Show()
		end
		local rows = math.ceil(#list / cols)
		y = y + rows * size + (rows - 1) * gap
	end

	for _, cat in ipairs(cats) do
		local note = nil
		if cat.key == "junk" and cfg.junkAutoSell then note = "auto-sell" end
		Section(cat.label, buckets[cat.key], note)
	end
	-- The specialist bags, each under its own name, BEFORE the free block - they
	-- hold real items, so they belong with the other item sections rather than
	-- down among the empty cells.
	--
	-- The count says the bag's size and the note says what is left in it, which
	-- is the question a quiver actually raises.
	for _, word in ipairs(order) do
		local s = special[word]
		local list = {}
		for _, b in ipairs(s.items) do list[#list + 1] = b end
		if cfg.showEmpty then
			for _, b in ipairs(s.empties) do list[#list + 1] = b end
		end
		Section(word:upper(), list,
			#s.empties > 0 and (#s.empties .. " free") or nil)
	end

	-- FREE is the slots you can put ANYTHING in. A quiver's empty slots are not
	-- those, and shown in the same block they read as room the player has not
	-- got - which is why they went up there with the bag they belong to.
	if cfg.showEmpty then Section("FREE", empties) end

	frame.labels:HideFrom(labelN + 1)

	y = y + GRID_BOTTOM
	child:SetSize(gridW, math.max(1, y))
	frame.scroll:Clamp()

	-- Height hugs the contents, up to the budget. Past that the grid scrolls.
	frame.search:SetShown(cfg.showSearch and true or false)

	-- THE WELL'S RIM IS OUTSIDE THE SCROLL FRAME. The recess is drawn a little
	-- larger than the thing scrolling in it, so a window sized to the scroll
	-- frame alone is a window whose recess runs down into the footer - which
	-- is the line cutting through the money row.
	local out = W.WELL_OUTSET
	local budget = math.max(160, tonumber(cfg.maxHeight) or 720)
	local contentH = math.min(y, budget)
	frame.scroll:ClearAllPoints()
	frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT",
		GRID_PAD_X, -(HEAD_H + W.PANEL_PAD + out))
	frame.scroll:SetSize(gridW, contentH)
	frame:SetSize(gridW + GRID_PAD_X * 2,
		HEAD_H + W.PANEL_PAD + out + contentH + out + W.PANEL_PAD + FOOT_H)

	frame.used, frame.total = used, total

	-- What the footer can honestly promise. The general count is the one that
	-- matters - it is the number of things you can put away - and the rest is
	-- named rather than added to it.
	frame.freeOpen = #empties
	frame.freeSpecial = {}
	for _, word in ipairs(order) do
		local left = #special[word].empties
		if left > 0 then
			frame.freeSpecial[#frame.freeSpecial + 1] = { word, left }
		end
	end

	self:RefreshHeader(frame)
	self:RefreshFooter(frame)
	if frame.kind == "bags" then
		-- Contents first: the drawer's height comes out of that pass, and the
		-- clip window and the handle are both placed from it. The handle's
		-- own layout is in the middle because its LENGTH comes out of what it
		-- has to hold, and the drawer's placement centres it on that.
		self:RefreshFlyout(frame)
		self:LayoutRail(frame)
		self:LayoutDrawer(frame)
	end

	frame.drawn = true
	frame.dirty = false
end

--- The capacity chip. Its own function because nothing else in the header
--  changes, and the chip changes on every single item that moves.
function Bags:RefreshHeader(frame)
	local c = Palette.c
	local head = frame.head
	head.count:SetLabel(string.format("%d / %d", frame.used or 0, frame.total or 0))
	if frame.kind == "bank" then
		head.count:SetColors(c.bankAccent, c.btnFillText)
	else
		head.count:SetColors(c.btnFill, c.btnFillText)
	end
end

--- The footer. Split out because two things change it that are not a redraw:
--  PLAYER_MONEY, which must not rebuild eighty item buttons, and buying a bank
--  bag slot, which changes the tiles but not the grid.
function Bags:RefreshFooter(frame)
	local c = Palette.c
	local foot = frame.foot

	if frame.kind ~= "bank" then
		foot.money:SetText(MoneyText(_G.GetMoney and _G.GetMoney() or 0))
		-- THE SLOTS YOU CAN ACTUALLY USE, and then the ones you cannot. Counting
		-- every empty slot the same way told a hunter with a full backpack and
		-- five empty quiver slots that eleven were free, six of which existed.
		--
		-- Falls back to the plain subtraction only before the first redraw, when
		-- nothing has looked at which bag each slot is in yet.
		local free = frame.freeOpen
			or math.max(0, (frame.total or 0) - (frame.used or 0))

		local text = free == 1 and "1 slot free" or (free .. " slots free")
		for _, entry in ipairs(frame.freeSpecial or {}) do
			text = text .. " \194\183 " .. entry[2] .. " " .. entry[1]
		end
		foot.free:SetText(text)
		W.Color(foot.free, c.textDim)
		ColorHairline(foot.rule)
		return
	end

	-- BANK BAGS. Owned tiles first, then the next purchasable one carrying its
	-- price, then the one after it dimmer -- the deck's own progression, which
	-- reads as "this is what you have and this is what it costs to have more"
	-- without a word of explanation.
	W.Color(foot.label, c.textDim)
	ColorHairline(foot.rule)

	local owned = (_G.GetNumBankSlots and _G.GetNumBankSlots()) or 0
	local last = math.min(NUM_BANK_BAGS, owned + 2)
	local prev = nil

	for i = 1, NUM_BANK_BAGS do
		local bag = NUM_BAGS + i
		local tile = foot.tiles[i]
		if not tile then
			tile = BuildBagTile(foot, TILE, 9)
			foot.tiles[i] = tile
		end

		if i > last then
			tile:Hide()
		else
			tile:ClearAllPoints()
			-- Right to left, so the owned bags sit nearest the edge and the
			-- prices trail off inward, which is the deck's own reading order.
			if prev then
				tile:SetPoint("RIGHT", prev, "LEFT", -6, 0)
			else
				tile:SetPoint("RIGHT", foot, "RIGHT", -SEARCH_PAD_X, 0)
			end
			prev = tile

			if i <= owned then
				local invSlot = _G.BankButtonIDToInvSlotID
					and _G.BankButtonIDToInvSlotID(i, 1) or nil
				BindBagTile(tile, bag, invSlot)

				local link = invSlot and _G.GetInventoryItemLink
					and _G.GetInventoryItemLink("player", invSlot)
				local icon = invSlot and _G.GetInventoryItemTexture
					and _G.GetInventoryItemTexture("player", invSlot)

				tile.icon:SetTexture(icon)
				tile.icon:SetShown(icon and true or false)
				tile.glyph:SetShown(not icon)
				tile.glyph:SetText(GlyphFor(link and link:match("%[(.-)%]")
					or _G.BANK_BAG or "Bag"))
				W.Color(tile.glyph, c.text)
				tile.price:Hide()

				-- The fill is set explicitly rather than left alone, because a
				-- slot that was drawn as a purchasable outline a moment ago has
				-- a transparent one, and buying it must not leave a hole.
				tile:SetFillColor(c.glass)
				tile:SetEdgeShown(true)
				tile:SetEdgeColor(c.glassEdge)
				tile:SetAlpha(1)
			else
				-- Purchasable: an outline with a price in it, never a filled
				-- tile, so it cannot be mistaken for something already owned.
				-- The one after next is dimmer again -- "and then this".
				local later = (i > owned + 1)
				tile.icon:Hide()
				tile.glyph:Hide()
				tile.price:Show()
				tile.price:SetText(Bags:SlotPriceText(i))
				W.Color(tile.price, later and c.textFaint or c.textDim)

				tile:SetFillColor({ 0, 0, 0, 0 })
				tile:SetEdgeShown(true)
				local e = c.bankEdge or c.glassEdge
				tile:SetEdgeColor({ e[1], e[2], e[3],
					(e[4] or 1) * (later and 0.55 or 1) })
				tile:SetAlpha(later and 0.6 or 1)

				-- Not yours yet: no dragging, no dropping, no tooltip. Said as
				-- state rather than by removing the handlers, because the tile
				-- is recycled and whatever is removed here has to be put back
				-- the moment the slot is bought - which is precisely what did
				-- not happen.
				--
				-- Only the next one is buyable. The one after is drawn and inert:
				-- PurchaseSlot takes no argument, so clicking it would buy the
				-- slot before the one whose price it is showing.
				-- No bag behind it, so nothing to drag out or drop into: the
				-- handlers all read invSlot and there is none. Only the next one
				-- is buyable; the one after is drawn and inert, because
				-- PurchaseSlot takes no argument and would buy the slot before
				-- the one whose price it is showing.
				tile.bag, tile.invSlot = nil, nil
				tile.buyable = (not later) or nil
			end

			tile:Show()
		end
	end
end

--- What the next bank bag slot costs, as a short string.
--
--  Read fresh every time. The number changes the instant one is bought, and a
--  price captured when the panel was drawn is a price that can be wrong by the
--  time anybody clicks it.
function Bags:SlotPriceText(index)
	local owned = (_G.GetNumBankSlots and _G.GetNumBankSlots()) or 0
	local cost
	if _G.GetBankSlotCost then
		local ok, v = pcall(_G.GetBankSlotCost, index - 1)
		if ok then cost = v end
		if not cost then
			local ok2, v2 = pcall(_G.GetBankSlotCost)
			if ok2 then cost = v2 end
		end
	end
	cost = tonumber(cost) or 0
	local g = math.floor(cost / 10000)
	if g > 0 then return g .. "g" end
	local s = math.floor((cost % 10000) / 100)
	if s > 0 then return s .. "s" end
	return (cost % 100) .. "c"
end

-- ---------------------------------------------------------------------------
-- the flyout's contents
-- ---------------------------------------------------------------------------

function Bags:RefreshFlyout(frame)
	local fly = frame.flyout
	if not fly then return end
	local cfg = A.Config:Module("bags")
	local c = Palette.c

	W.Color(fly.label, c.textDim)

	local y = FLY_PAD + SEC_LABEL_H + 4
	local n = 0

	for _, bag in ipairs(InventoryBags()) do
		n = n + 1
		local row = FlyRowPool(fly, n)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", fly, "TOPLEFT", FLY_CORNER + FLY_PAD - 4, -y)
		row:SetPoint("TOPRIGHT", fly, "TOPRIGHT", -FLY_PAD + 4, -y)

		local invSlot = (bag > BACKPACK and BagToInventory) and BagToInventory(bag) or nil
		BindBagTile(row.tile, bag, invSlot)

		local link = invSlot and _G.GetInventoryItemLink
			and _G.GetInventoryItemLink("player", invSlot)
		local icon = invSlot and _G.GetInventoryItemTexture
			and _G.GetInventoryItemTexture("player", invSlot)
		local name = (link and link:match("%[(.-)%]"))
			or (bag == BACKPACK and (_G.BACKPACK_TOOLTIP or "Backpack"))
			or _G.EMPTY or "Empty"

		row.tile.icon:SetTexture(icon)
		row.tile.icon:SetShown(icon and true or false)
		row.tile.glyph:SetShown(not icon)
		row.tile.glyph:SetText(GlyphFor(name))
		W.Color(row.tile.glyph, c.text)
		row.tile:SetEdgeColor(c.glassEdge)
		row.tile.price:Hide()

		row.name:SetText(name)
		W.Color(row.name, c.text)

		-- "20 - herbs only" for a specialty bag. The family bitmask is the
		-- second return of GetContainerNumFreeSlots, which is the canonical way
		-- to ask; 0 means it takes anything.
		local slots = SlotsIn(bag)
		local sub = slots .. " slots"
		local named = self:FamilyName(BagFamily(bag))
		if named then sub = slots .. " \194\183 " .. named end
		row.sub:SetText(sub)
		W.Color(row.sub, c.textDim)
		row.bg:SetFillColor(c.rowHover)
		row.bg:SetAlpha(0)
		row:Show()

		y = y + FLY_ROW_H + FLY_GAP
	end

	for i = n + 1, #fly.rows do fly.rows[i]:Hide() end

	-- What the handle says while the drawer is shut. Kept here rather than
	-- asked for again in the handle's own layout, which runs on the animation
	-- frame: this is the pass that already knows.
	fly.__nBags = n

	-- The keyring, a fixed open section at the foot. Not swappable, not counted
	-- in bag capacity, and it grows downward with the key count -- no cap and no
	-- collapse, which is the handoff's instruction.
	local keys = cfg.showKeyring and KeyringSize() or 0
	fly.__nKeys = keys
	fly.rule:SetShown(keys > 0)
	fly.keyIcon:SetShown(keys > 0)
	fly.keyLabel:SetShown(keys > 0)
	fly.keyCount:SetShown(keys > 0)

	if keys > 0 then
		y = y + 6
		fly.rule:SetPoint("TOP", fly, "TOP", 0, -y)
		ColorHairline(fly.rule)
		y = y + 8

		fly.keyIcon:ClearAllPoints()
		fly.keyIcon:SetSize(11, 11)
		fly.keyIcon:SetPoint("TOPLEFT", fly, "TOPLEFT", FLY_CORNER + FLY_PAD + 4, -y - 3)
		fly.keyIcon:SetVertexColor(c.accent[1], c.accent[2], c.accent[3], 1)

		fly.keyLabel:ClearAllPoints()
		fly.keyLabel:SetPoint("LEFT", fly.keyIcon, "RIGHT", 8, 0)
		W.Color(fly.keyLabel, c.textDim)

		fly.keyCount:ClearAllPoints()
		fly.keyCount:SetPoint("RIGHT", fly, "RIGHT", -FLY_PAD - 4, 0)
		fly.keyCount:SetPoint("TOP", fly.keyLabel, "TOP", 0, 0)
		fly.keyCount:SetText(keys == 1 and "1 key" or (keys .. " keys"))
		W.Color(fly.keyCount, c.textFaint)

		y = y + SEC_LABEL_H + 6

		local proxy = fly.proxy
		if not proxy then
			proxy = CreateFrame("Frame", nil, fly)
			proxy:SetAllPoints(fly)
			proxy:SetID(KEYRING)
			proxy.id = KEYRING
			fly.proxy = proxy
			fly.keyButtons = {}
		end

		local left = FLY_CORNER + FLY_PAD + 4
		for slot = 1, keys do
			local b = fly.keyButtons[slot]
			if not b then
				b = BuildItemButton(proxy, KEYRING, slot, KEY_SLOT)
				fly.keyButtons[slot] = b
			end
			UpdateItemButton(b, cfg)
			local col = (slot - 1) % KEY_COLS
			local r = math.floor((slot - 1) / KEY_COLS)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", fly, "TOPLEFT",
				left + col * (KEY_SLOT + 6), -(y + r * (KEY_SLOT + 6)))
			b:Show()
		end
		for slot = keys + 1, #(fly.keyButtons or {}) do fly.keyButtons[slot]:Hide() end

		y = y + math.ceil(keys / KEY_COLS) * (KEY_SLOT + 6)
	elseif fly.keyButtons then
		for _, b in pairs(fly.keyButtons) do b:Hide() end
	end

	fly:SetHeight(y + FLY_PAD)
	fly:SetFillColor(Palette.c.glass)
end

--- A specialty bag's family, as the flyout says it: "quiver only".
function Bags:FamilyName(family)
	local word = FamilyWord(family)
	-- "restricted only" is not a sentence. An unrecognised family says what it
	-- can honestly say, which is that the bag will not take everything.
	if not word then return nil end
	return word == "restricted" and "restricted" or (word .. " only")
end

-- ---------------------------------------------------------------------------
-- taking over from Blizzard
--
-- The container frames are suppressed the way the quest log suppresses
-- QuestLogFrame: events off, hidden, and an OnShow hook gated on a FLAG rather
-- than on its own existence, because a HookScript can never be removed and one
-- left armed after the module is disabled looks exactly like "my bags stopped
-- opening" and survives until /reload.
--
-- BankFrame is the exception and gets the opposite treatment -- see below.
-- ---------------------------------------------------------------------------

-- Note what is NOT here: a list of BankFrame's events to tear off.
--
-- The quest log unregisters QuestLogFrame because its handler moves a global
-- selection cursor behind our back. BankFrame's handler does the opposite --
-- it is what keeps the banker session alive, and silencing it would leave the
-- server believing we are still standing there. It keeps its events.
local BAG_GLOBALS = {
	"ToggleAllBags", "OpenAllBags", "CloseAllBags",
	"ToggleBackpack", "OpenBackpack", "CloseBackpack",
	"ToggleBag", "OpenBag", "CloseBag",
}

function Bags:HideBlizzard()
	local cfg = A.Config:Module("bags")
	self.hideReport = {}
	if not cfg.hideBlizzard then return end

	local n = _G.NUM_CONTAINER_FRAMES or 13
	for i = 1, n do
		local f = _G["ContainerFrame" .. i]
		if not f then
			self.hideReport["ContainerFrame" .. i] = "absent"
		elseif f.IsForbidden and f:IsForbidden() then
			self.hideReport["ContainerFrame" .. i] = "forbidden"
		else
			f.__aetherSuppress = true
			-- One pcall per call. Bundling them means a throw on the first
			-- silently skips the rest and a frame stays on screen with no error.
			pcall(f.UnregisterAllEvents, f)
			pcall(f.Hide, f)
			if f.HookScript and not f.__aetherBagsHooked then
				f.__aetherBagsHooked = true
				pcall(f.HookScript, f, "OnShow", function(self2)
					if self2.__aetherSuppress then self2:Hide() end
				end)
			end
			self.hideReport["ContainerFrame" .. i] = f:IsShown() and "STILL SHOWN" or "hidden"
		end
	end

	-- BankFrame is NOT hidden, and that is deliberate.
	--
	-- Blizzard's own handler reads `if not self:IsShown() then CloseBankFrame() end`
	-- immediately after showing it, and its OnHide calls CloseBankFrame() too --
	-- and CloseBankFrame is what tells the SERVER you have walked away from the
	-- banker. Hiding it therefore ends the session the instant it starts, and
	-- the bank comes back empty. So it stays logically shown, its OnHide is
	-- neutralised, and it is reparented into a frame that is itself hidden, so
	-- nothing draws.
	local bank = _G.BankFrame
	if bank and not (bank.IsForbidden and bank:IsForbidden()) then
		if not self.hidden then
			self.hidden = CreateFrame("Frame", nil, UIParent)
			self.hidden:SetAllPoints(UIParent)
			self.hidden:Hide()
		end
		if bank.GetScript and bank.__aetherOnHide == nil then
			bank.__aetherOnHide = bank:GetScript("OnHide") or false
		end
		pcall(bank.SetScript, bank, "OnHide", nil)
		pcall(bank.SetParent, bank, self.hidden)
		self.hideReport["BankFrame"] = "parked"
	else
		self.hideReport["BankFrame"] = "absent"
	end

	-- Out of the panel manager, or the left slot stays reserved for a frame that
	-- will never be seen and the character sheet lands in the wrong place.
	if _G.UIPanelWindows and _G.UIPanelWindows["BankFrame"] and not self._panelWindow then
		self._panelWindow = _G.UIPanelWindows["BankFrame"]
		_G.UIPanelWindows["BankFrame"] = nil
	end

	-- The bag bar's own buttons keep working -- they call ToggleAllBags, which
	-- is ours now -- so they are left alone rather than hidden. Someone who
	-- wants them gone has the Zen module for that.
end

function Bags:RestoreBlizzard()
	local n = _G.NUM_CONTAINER_FRAMES or 13
	for i = 1, n do
		local f = _G["ContainerFrame" .. i]
		if f and not (f.IsForbidden and f:IsForbidden()) then
			f.__aetherSuppress = nil
		end
	end

	local bank = _G.BankFrame
	if bank and not (bank.IsForbidden and bank:IsForbidden()) then
		if bank.__aetherOnHide ~= nil then
			pcall(bank.SetScript, bank, "OnHide", bank.__aetherOnHide or nil)
			bank.__aetherOnHide = nil
		end
		pcall(bank.SetParent, bank, UIParent)
	end

	if self._panelWindow and _G.UIPanelWindows then
		_G.UIPanelWindows["BankFrame"] = self._panelWindow
		self._panelWindow = nil
	end
end

--- Replace the open/close funnel outright rather than hooking it.
--
--  Every one of these is a plain insecure Lua global and every route into the
--  bag UI goes through them: the B key (Bindings runs `ToggleAllBags();`), the
--  bag bar buttons, shift-click on the backpack, and the merchant, mail and
--  bank windows opening your bags for you.
--
--  Replacing beats hooking here for one specific reason: Blizzard's
--  ToggleAllBags internally calls OpenBackpack, which calls ToggleBackpack,
--  which calls ToggleBag, so a hook on all nine fires six times for one
--  keypress and the window toggles itself shut again. Replacing them means the
--  inner calls never happen at all, and the re-entrancy problem does not exist
--  rather than being filtered out afterwards.
function Bags:HookGlobals()
	if self._orig then return end
	self._orig = {}
	for _, name in ipairs(BAG_GLOBALS) do
		self._orig[name] = _G[name] or false
	end

	-- The bag id is not thrown away. Blizzard's bank calls ToggleBag(5..10) for
	-- its own bag slots, and answering that by toggling the INVENTORY window is
	-- how clicking a bank bag closes your bags.
	local function forBag(id)
		return type(id) == "number" and id > NUM_BAGS and "bank" or "bags"
	end

	_G.ToggleAllBags  = function() Bags:Toggle() end
	_G.ToggleBackpack = function() Bags:Toggle() end
	_G.ToggleBag      = function(id)
		if forBag(id) == "bank" then return end   -- the bank owns its own window
		Bags:Toggle()
	end
	_G.OpenBackpack   = function() Bags:Show() end
	_G.OpenBag        = function(id)
		if forBag(id) == "bank" then return end
		Bags:Show()
	end
	_G.CloseBackpack  = function() Bags:Hide() end
	_G.CloseBag       = function(id)
		if forBag(id) == "bank" then return end
		Bags:Hide()
	end

	-- OpenAllBags / CloseAllBags carry the opener, and Blizzard's own contract
	-- is that only the frame that opened the bags may close them. Keeping that
	-- is what stops the mail window closing bags the merchant opened.
	_G.OpenAllBags = function(frame)
		Bags._opener = frame and frame.GetName and frame:GetName() or nil
		Bags:Show()
	end
	_G.CloseAllBags = function(frame)
		local who = frame and frame.GetName and frame:GetName() or nil
		if Bags._opener and who and who ~= Bags._opener then return end
		Bags._opener = nil
		Bags:Hide()
	end
end

function Bags:RestoreGlobals()
	if not self._orig then return end
	for _, name in ipairs(BAG_GLOBALS) do
		_G[name] = self._orig[name] or nil
	end
	self._orig = nil
end

--- ESC routing. Registered as well as the OnKeyDown handler, because other
--  addons walk this list to decide what counts as a closable window -- but
--  never relied on, for the combat reason in BuildFrame.
local function SetSpecialFrame(on)
	if not _G.UISpecialFrames then return end
	for _, name in ipairs({ "AetherUIBags", "AetherUIBank" }) do
		for i = #_G.UISpecialFrames, 1, -1 do
			if _G.UISpecialFrames[i] == name then table.remove(_G.UISpecialFrames, i) end
		end
		if on then table.insert(_G.UISpecialFrames, name) end
	end
end

-- ---------------------------------------------------------------------------
-- visibility
-- ---------------------------------------------------------------------------

function Bags:Frame(kind)
	self.frames = self.frames or {}
	if not self.frames[kind] then
		self.frames[kind] = BuildFrame(kind)
		self.frames[kind]:SetScale(A.db.profile.scale)
	end
	return self.frames[kind]
end

function Bags:Show()
	local f = self:Frame("bags")
	if not f:IsShown() then
		if not f:GetPoint() then
			f:SetPoint("CENTER", UIParent, "CENTER", 160, 0)
		end
		f:Show()
	end
end

function Bags:Hide()
	if self.frames and self.frames.bags then self.frames.bags:Hide() end
	self:HideBank()
end

function Bags:Toggle()
	if self.frames and self.frames.bags and self.frames.bags:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

--- Closing either window closes both, because they are one workspace.
--  Closing the bank window while still standing at the banker would leave the
--  player with a session they cannot see and cannot use.
function Bags:CloseFrom()
	self:Hide()
end

function Bags:ShowBank()
	local bank = self:Frame("bank")
	self:Show()
	local bags = self:Frame("bags")

	-- Anchored to the bags window rather than to the screen, so dragging one
	-- moves the pair and the 28px gap the deck specifies is never lost.
	bank:ClearAllPoints()
	bank:SetPoint("TOPRIGHT", bags, "TOPLEFT", -PANEL_GAP, 0)
	bank.dirty = true
	self.atBank = true
	-- Show() runs OnShow, which draws it. Calling Rebuild here as well walks
	-- every bank slot twice for one event.
	bank:Show()
end

function Bags:HideBank()
	if self.frames and self.frames.bank and self.frames.bank:IsShown() then
		self.frames.bank:Hide()
	end
	-- Telling the server we have left. Without this the character stays flagged
	-- as being at the banker and the next BANKFRAME_OPENED does not arrive.
	if self.atBank then
		self.atBank = false
		if _G.CloseBankFrame then pcall(_G.CloseBankFrame) end
	end
end

--- Whether the drawer exists at all - which is not whether it is out.
--
--  It started life behind a click on the CAPACITY CHIP, which is what the first
--  deck described, and on screen that was a control nobody could find: no
--  affordance, no hover state, and the one time it appeared it was not clear
--  what had done it. So it was pinned open instead, on the argument that a
--  panel edge which is sometimes there is worse than one that always is.
--
--  The handoff answers that properly: a handle on the edge, the same one the
--  Toolbox and the party dock use. The objection was to a hidden control, not
--  to a drawer, so the drawer is back and this setting is now the coarser
--  question - is there a bag list on this window at all.
function Bags:SetFlyoutShown(shown)
	local cfg = A.Config:Module("bags")
	cfg.showFlyout = shown and true or false
	self:LayoutDrawer()
end

-- ---------------------------------------------------------------------------
-- refresh coalescing
--
-- BAG_UPDATE fires once per bag per change and ITEM_LOCK_CHANGED fires on every
-- pickup, so a redraw per event would rebuild the grid a dozen times for one
-- drag. Mark dirty, ride the shared 0.1s ticker, and never draw while closed.
-- ---------------------------------------------------------------------------

function Bags:Invalidate(kind)
	if not self.frames then return end
	for k, f in pairs(self.frames) do
		if not kind or k == kind then f.dirty = true end
	end
	if not self.loading then A:RegisterTicker(self, Bags.Flush) end
end

function Bags:Flush()
	A:UnregisterTicker(self)
	-- Re-checked here and not only in Invalidate: a rebuild can be queued a
	-- frame before a loading screen goes up, and running it on the other side
	-- reads the client's transient nils as real answers.
	if self.loading or not self.frames then return end
	for _, f in pairs(self.frames) do
		if f.dirty and f:IsShown() then self:Rebuild(f) end
	end
end

function Bags:SetFilter(frame, text)
	text = text and string.lower(text) or ""
	if text == (frame.filter or "") then return end
	frame.filter = text
	frame.search.placeholder:SetShown(text == "")
	self:Rebuild(frame)
end

-- ---------------------------------------------------------------------------
-- sort: compacting stacks
--
-- There is no SortBags on this client. The only occurrence in the whole Era
-- source tree is inside an XML comment on a button Blizzard disabled, so the
-- work has to be done here with PickupContainerItem pairs.
--
-- What it does NOT do is reorder anything. The grid is already sorted -- we
-- decide the order it is drawn in -- so shuffling the physical bags buys the
-- player nothing and costs them a hundred item moves they did not ask for.
-- What it does do is merge partial stacks, which is the part that actually
-- gives slots back.
--
-- The pacing matters. A move locks both slots until the server confirms, and a
-- second move on a locked slot is dropped silently rather than queued -- so
-- this runs one pass, waits, and runs again, stopping when a pass moves
-- nothing.
-- ---------------------------------------------------------------------------

function Bags:StartSort(frame)
	if self.sorting then return end
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		A:Print("not while you are in combat.")
		return
	end
	-- The pass timer cannot be cancelled once queued, so the run identifies
	-- itself and an orphaned timer finds a state that is no longer its own.
	-- Without this, stopping and restarting inside the 50ms step leaves two
	-- chains driving one run at double the rate the server will accept.
	self.sorting = { kind = frame.kind, passes = 0, token = {} }
	if _G.PlaySound and _G.SOUNDKIT and _G.SOUNDKIT.UI_BAG_SORTING_01 then
		pcall(_G.PlaySound, _G.SOUNDKIT.UI_BAG_SORTING_01)
	end
	self:SortPass()
end

function Bags:StopSort()
	self.sorting = nil
	self:Invalidate()
end

function Bags:SortPass(token)
	local state = self.sorting
	if not state then return end
	if token and state.token ~= token then return end

	if (_G.InCombatLockdown and _G.InCombatLockdown())
		or (_G.UnitIsDead and _G.UnitIsDead("player"))
		or not PickupItemAt then
		self:StopSort()
		return
	end

	-- A ceiling on passes. A pass that keeps finding work forever means an
	-- assumption here is wrong, and an addon that moves the player's items in a
	-- loop until they log out is much worse than one that gives up.
	state.passes = state.passes + 1
	if state.passes > 40 then
		-- Said out loud rather than swallowed. A sort that stops halfway in
		-- silence reads to the player as "sort is broken", and the cap being
		-- reached at all means an assumption in here is wrong.
		A:Print("stopped compacting after 40 passes - run it again if there is"
			.. " still work to do.")
		self:StopSort()
		return
	end

	local bags = BagListFor(state.kind)

	-- Partial stacks, grouped by item. Only stackable items can merge, and the
	-- maximum stack size is the one field here that GetItemInfo alone knows --
	-- an item it has not cached yet is skipped and picked up on a later pass
	-- rather than guessed at.
	local partial = {}
	for _, bag in ipairs(bags) do
		for slot = 1, SlotsIn(bag) do
			local info = SlotInfo(bag, slot)
			if info and info.itemID and not info.isLocked then
				local maxStack
				if ItemInfo then
					local ok, _, _, _, _, _, _, _, stack = pcall(ItemInfo, info.itemID)
					if ok then maxStack = tonumber(stack) end
				end
				if maxStack and maxStack > 1 and (info.stackCount or 1) < maxStack then
					local key = info.itemID
					partial[key] = partial[key] or {}
					partial[key][#partial[key] + 1] = {
						bag = bag, slot = slot,
						count = info.stackCount or 1, max = maxStack,
					}
				end
			end
		end
	end

	local moved = false

	for _, list in pairs(partial) do
		if #list > 1 then
			-- Largest first, and everything else poured into it. Topping up the
			-- biggest stack is what actually frees SLOTS; merging two small ones
			-- leaves both of them.
			table.sort(list, function(a, b) return a.count > b.count end)
			local target = list[1]
			for i = 2, #list do
				if target.count >= target.max then break end
				local from = list[i]

				-- Cleared before EVERY pair, not once per pass.
				--
				-- A merge that overflows -- 18 linen onto 15, max 20 -- leaves
				-- the remainder on the cursor, and the next pair's first pickup
				-- would then DROP that remainder into whatever slot it was
				-- reaching for and pick up what was there instead. Nothing is
				-- destroyed, but items land in slots nobody chose, which is
				-- precisely the reordering this routine promises not to do.
				if _G.ClearCursor then pcall(_G.ClearCursor) end
				pcall(PickupItemAt, from.bag, from.slot)
				pcall(PickupItemAt, target.bag, target.slot)
				target.count = math.min(target.max, target.count + from.count)
				moved = true
			end
		end
	end

	if _G.ClearCursor then pcall(_G.ClearCursor) end

	if moved then
		if _G.C_Timer and _G.C_Timer.After then
			local token = state.token
			_G.C_Timer.After(SORT_STEP, function() Bags:SortPass(token) end)
		else
			self:StopSort()
		end
	else
		self:StopSort()
	end
end

-- ---------------------------------------------------------------------------
-- junk auto-sell
--
-- Off by default, and it stays off until somebody asks for it, because this is
-- the only thing in the module that destroys value.
--
-- There is no SellItem API on this client: you sell by USING the item while a
-- merchant window is open, which is the same call the right-click path makes.
-- That means every guard has to be ours -- the merchant really being open, the
-- item really being poor quality, the item really having a value -- and it has
-- to be paced, because the server drops calls that arrive too fast.
-- ---------------------------------------------------------------------------

function Bags:JunkList()
	local out, value = {}, 0
	for _, bag in ipairs(InventoryBags()) do
		for slot = 1, SlotsIn(bag) do
			local info = SlotInfo(bag, slot)
			-- hasNoValue is the authoritative "this cannot be sold" flag and is
			-- not the same question as "sellPrice is zero".
			-- Quality wins over class when FILING an item, so a grey quest item
			-- shows under JUNK. It must not win when SELLING one: a quest
			-- starter sold by an automatic sweep is a quest the player cannot
			-- get back without hunting the mob again.
			local quest = false
			if info and GetQuestInfoAt then
				local ok, q = pcall(GetQuestInfoAt, bag, slot)
				quest = ok and q and (q.isQuestItem or q.questID) and true or false
			end
			if info and info.quality == 0 and not info.hasNoValue and info.itemID
				and not quest then
				local worth = 0
				if ItemInfo then
					local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(ItemInfo, info.itemID)
					if ok and tonumber(price) then
						worth = tonumber(price) * (info.stackCount or 1)
					end
				end
				-- The itemID is carried so the slot can be revalidated by
				-- IDENTITY later. "Whatever is in this slot is grey" is not the
				-- same question as "this is still the item I listed", and over a
				-- run of several seconds the player can loot into a slot that
				-- has already been walked past.
				out[#out + 1] = { bag = bag, slot = slot, worth = worth,
					itemID = info.itemID }
				value = value + worth
			end
		end
	end
	return out, value
end

function Bags:SellJunk()
	local cfg = A.Config:Module("bags")
	if not cfg.junkAutoSell then return end
	if not _G.MerchantFrame or not _G.MerchantFrame:IsShown() then return end
	if self.selling then return end

	local list, value = self:JunkList()
	if #list == 0 then return end

	-- `value` is what the whole list is worth; `earned` is what was actually
	-- sold. They are not the same number the moment anything interrupts the run,
	-- and reporting the first as if it were the second is a lie about money.
	self.selling = { list = list, index = 1, worth = value, earned = 0, sold = 0 }
	self:SellStep()
end

function Bags:SellStep()
	local s = self.selling
	if not s then return end

	-- Re-checked every step rather than once at the start. The merchant window
	-- can close mid-run -- the player walks away, or the NPC despawns -- and
	-- UseContainerItem with no merchant open USES the item instead of selling
	-- it, which on a stack of poor-quality food is merely silly and on anything
	-- else is destructive.
	if not _G.MerchantFrame or not _G.MerchantFrame:IsShown() or not UseItemAt then
		self:FinishSelling()
		return
	end

	local entry = s.list[s.index]
	if not entry then
		self:FinishSelling()
		return
	end
	s.index = s.index + 1

	-- Revalidated against the slot as it is NOW, not as it was when the list was
	-- built. Anything can have moved in the meantime, and selling the wrong slot
	-- because an index went stale is exactly the failure this codebase has paid
	-- for once already.
	local info = SlotInfo(entry.bag, entry.slot)
	local stillQuest = false
	if info and GetQuestInfoAt then
		local ok, q = pcall(GetQuestInfoAt, entry.bag, entry.slot)
		stillQuest = ok and q and (q.isQuestItem or q.questID) and true or false
	end

	if info and info.itemID == entry.itemID and info.quality == 0
		and not info.hasNoValue and not stillQuest then
		pcall(UseItemAt, entry.bag, entry.slot)
		s.sold = s.sold + 1
		s.earned = s.earned + (entry.worth or 0)
	end

	if _G.C_Timer and _G.C_Timer.After then
		_G.C_Timer.After(SELL_STEP, function() Bags:SellStep() end)
	else
		self:FinishSelling()
	end
end

function Bags:FinishSelling()
	local s = self.selling
	self.selling = nil
	if not s or s.sold == 0 then return end
	-- Kept so `/aether bags` can answer "what did that last run actually do",
	-- which is a question worth being able to ask about something that spends
	-- the player's items while they are looking somewhere else.
	self.lastSale = { sold = s.sold, earned = s.earned, listed = s.worth }
	A:Print(string.format("sold " .. A.Val("%d") .. " junk item%s for " .. A.Val("%s") .. ".",
		s.sold, s.sold == 1 and "" or "s",
		(_G.GetCoinTextureString and _G.GetCoinTextureString(s.earned))
			or (s.earned .. "c")))
	self:Invalidate()
end

-- ---------------------------------------------------------------------------
-- the confirmation
--
-- A modal is the one surface here that must NOT be glass. It sits over the
-- chrome rather than over the world, so it has nothing to be translucent
-- against: near-opaque fill, a full-screen scrim behind it, and the full shadow
-- regardless of the profile setting.
-- ---------------------------------------------------------------------------

local function BuildButton(parent, style, label)
	-- The shared button shape, for the reason the quest log's says: a capsule's
	-- caps are drawn from a 256-texel texture and come back crunchy at button
	-- height, and one shape in one place beats three that drifted apart.
	local b = W.CreateButton(parent, {})
	b:SetHeight(BTN_H)
	b._style = style

	b.label = W.Text(b, style == "filled" and "qlBtn" or "qlBtnAlt", "CENTER")
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)

	function b:Restyle()
		local c = Palette.c
		if self._style == "filled" then
			self:SetFillColor(self._over and c.btnFillHi or c.btnFill)
			self:SetEdgeShown(false)
			W.Color(self.label, c.btnFillText)
		else
			self:SetFillColor(self._over and c.btnHover or { 0, 0, 0, 0 })
			self:SetEdgeShown(true)
			self:SetEdgeColor(c.btnEdge)
			W.Color(self.label, c.textDim)
		end
	end

	function b:SetLabel(text)
		self.label:SetText(text or "")
		self:SetWidth(math.ceil(self.label:GetStringWidth() or 0) + 44)
	end

	function b:SetAction(fn)
		self._action = fn
		self:SetScript("OnClick", function(s) if s._action then s._action(s) end end)
	end

	b:SetScript("OnEnter", function(self) self._over = true self:Restyle() end)
	b:SetScript("OnLeave", function(self) self._over = false self:Restyle() end)
	b:SetLabel(label)
	b:Restyle()
	return b
end

local function BuildConfirm()
	local dim = CreateFrame("Frame", nil, UIParent)
	dim:SetAllPoints(UIParent)
	dim:SetFrameStrata("FULLSCREEN_DIALOG")
	dim:EnableMouse(true)

	dim.scrim = dim:CreateTexture(nil, "BACKGROUND")
	dim.scrim:SetTexture(Media.texture.flat)
	dim.scrim:SetAllPoints(dim)

	dim:SetScript("OnMouseDown", function(_, button)
		-- Left button only, or an aimed camera drag cancels the dialog under the
		-- cursor.
		if button == nil or button == "LeftButton" then Bags:CloseConfirm() end
	end)
	dim:Hide()

	local box = Glass.CreatePanel(dim, {
		corner = 16, shadow = 1, fill = "dialogFill", edge = "glassEdgeHi",
	})
	box:SetSize(CONFIRM_W, CONFIRM_MIN_H)
	box:EnableMouse(true)
	box:SetFrameStrata("FULLSCREEN_DIALOG")
	box:SetFrameLevel(dim:GetFrameLevel() + 10)
	dim.box = box

	box.text = W.Text(box, "qlObjName", "CENTER")
	box.text:SetPoint("TOPLEFT", box, "TOPLEFT", CONFIRM_PAD, -26)
	box.text:SetWidth(CONFIRM_W - CONFIRM_PAD * 2)
	box.text:SetJustifyV("TOP")
	if box.text.SetWordWrap then box.text:SetWordWrap(true) end
	if box.text.SetSpacing then box.text:SetSpacing(4) end

	box.yes = BuildButton(box, "filled", _G.YES or "Yes")
	box.yes:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -CONFIRM_PAD, 22)

	box.no = BuildButton(box, "outline", _G.NO or "No")
	box.no:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", CONFIRM_PAD, 22)

	box.no:SetAction(function() Bags:CloseConfirm() end)
	box.yes:SetAction(function() Bags:ConfirmBuyBankSlot() end)

	-- Escape closes it, and ONLY escape is swallowed. Setting propagation false
	-- once and leaving it there turns a dialog into a total input lockout.
	dim:EnableKeyboard(true)
	if dim.SetPropagateKeyboardInput then dim:SetPropagateKeyboardInput(true) end
	dim:SetScript("OnKeyDown", function(self, key)
		if key ~= "ESCAPE" then
			if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
			return
		end
		if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
		Bags:CloseConfirm()
	end)

	return dim
end

function Bags:CloseConfirm()
	if self.confirm then self.confirm:Hide() end
	self.pendingSlot = nil
end

function Bags:AskBuyBankSlot()
	local owned = (_G.GetNumBankSlots and _G.GetNumBankSlots()) or 0
	local money = (_G.GetMoney and _G.GetMoney()) or 0
	local cost = 0
	if _G.GetBankSlotCost then
		local ok, v = pcall(_G.GetBankSlotCost, owned)
		if ok then cost = tonumber(v) or 0 end
	end

	self.confirm = self.confirm or BuildConfirm()
	local c = Palette.c
	local box = self.confirm.box

	local price = (_G.GetCoinTextureString and _G.GetCoinTextureString(cost)) or MoneyText(cost)
	local body = "Buy another bank bag slot for " .. price .. "?"
	if money < cost then
		body = body .. "\n\n"
			.. Palette:Ink("dangerText", "You cannot afford this.")
	end
	box.text:SetText(body)
	-- Primary ink, not dim. It is a question that has to be read and answered.
	W.Color(box.text, c.text)
	box.yes:SetLabel(_G.YES or "Yes")
	box.no:SetLabel(_G.NO or "No")

	local textH = math.ceil(box.text:GetStringHeight() or 0)
	box:SetSize(CONFIRM_W, math.max(CONFIRM_MIN_H, 26 + textH + 24 + BTN_H + 22))

	-- Drawn at the profile scale, like the window it is covering; the offset is
	-- in the box's OWN units, so it is divided back through the scale or the
	-- dialog drifts toward centre as the scale comes down.
	local sc = A.db.profile.scale
	box:SetScale(sc)
	box:ClearAllPoints()
	box:SetPoint("CENTER", UIParent, "CENTER", 0, 60 / ((sc and sc > 0) and sc or 1))
	box:SetShadow(1)
	box:ApplySkin("dialogFill", "glassEdgeHi")

	local s = c.scrim
	self.confirm.scrim:SetVertexColor(s[1], s[2], s[3], s[4] or 0.45)
	box.yes:Restyle()
	box.no:Restyle()

	self.pendingSlot = owned + 1
	self.confirm:Show()
end

--- Buy it, having re-read the price at the moment of the click.
--
--  Never trust the number the dialog opened with. The world can change while a
--  modal sits there -- another slot bought on a second client, a patch, a
--  refund -- and BankFrame.nextSlotCost is what Blizzard's own purchase path
--  reads, so it is set here rather than at draw time.
function Bags:ConfirmBuyBankSlot()
	local want = self.pendingSlot
	self:CloseConfirm()
	if not want then return end

	local owned = (_G.GetNumBankSlots and _G.GetNumBankSlots()) or 0
	if owned + 1 ~= want then
		A:Print("the bank has changed since that was asked - nothing was bought.")
		self:Invalidate("bank")
		return
	end

	if _G.BankFrame and _G.GetBankSlotCost then
		local ok, v = pcall(_G.GetBankSlotCost, owned)
		if ok then _G.BankFrame.nextSlotCost = v end
	end
	if _G.PurchaseSlot then pcall(_G.PurchaseSlot) end
	self:Invalidate("bank")
end

-- ---------------------------------------------------------------------------
-- skin and config
-- ---------------------------------------------------------------------------

function RestyleFrame(frame)
	if not frame then return end
	local c = Palette.c

	frame:ApplySkin("glassStrong")
	frame:SetFillColor(Palette:ReadingFill())
	frame.search:ApplySkin("glassSoft")

	W.Color(frame.head.title, c.text)
	W.RepaintClose(frame.head.close)
	frame.head.sort:Restyle(false)
	W.Color(frame.search.placeholder, c.textFaint)
	if frame.search.lens then
		local t = c.textDim
		frame.search.lens:SetVertexColor(t[1], t[2], t[3], (t[4] or 1) * 0.9)
		frame.search.lensHandle:SetVertexColor(t[1], t[2], t[3], (t[4] or 1) * 0.9)
	end
	ColorHairline(frame.head.rule)
	ColorHairline(frame.foot.rule)

	if frame.foot.money then W.Color(frame.foot.free, c.textDim) end
	if frame.foot.label then W.Color(frame.foot.label, c.textDim) end

	if frame.flyout then
		frame.flyout:ApplySkin("glass")
		W.Color(frame.flyout.label, c.textDim)
		ColorHairline(frame.flyout.rule)
	end
	if frame.flyRail then
		frame.flyRail:ApplySkin("glass")
		W.Tint(frame.flyRail.chev, c.text, 0.75)
		Bags:LayoutRail(frame)
	end
end

function Bags:OnSkinChanged()
	if not self.frames then return end
	for _, f in pairs(self.frames) do
		RestyleFrame(f)
		if f:IsShown() then self:Rebuild(f) else f.dirty = true end
	end
	-- A dialog open across a skin change would otherwise keep the old skin's
	-- colours until it is closed and reopened. Its colours are applied on the
	-- show path, so the cheapest correct answer is to run that again.
	if self.confirm and self.confirm:IsShown() then self:AskBuyBankSlot() end
end

function Bags:OnConfigChanged()
	if not self.frames then return end
	local cfg = A.Config:Module("bags")
	for _, f in pairs(self.frames) do
		f:SetScale(A.db.profile.scale)
		f:SetShadow(A.db.profile.glass.shadow)
		if f.flyout then f.flyout:SetShadow(A.db.profile.glass.shadow) end
		if f.flyRail then f.flyRail:SetShadow(A.db.profile.glass.shadow) end
		f.dirty = true
	end
	-- hideBlizzard can be toggled at runtime. Turning it back on has to
	-- re-suppress frames that have been shown since; turning it OFF has to hand
	-- the toggle funnel back too, or Blizzard's frames are un-suppressed and
	-- still unreachable, because every route into them still opens our window
	-- and the setting appears to do nothing.
	if cfg.hideBlizzard then
		self:HideBlizzard()
		self:HookGlobals()
	else
		self:RestoreGlobals()
		self:RestoreBlizzard()
	end
	self:OnSkinChanged()
end

-- ---------------------------------------------------------------------------
-- diagnostics
-- ---------------------------------------------------------------------------

function Bags:Diagnose()
	A:Print("bags:")
	A:Print(("  api  " .. A.Val("%s") .. " container, " .. A.Val("%s") .. " item")
		:format(GetItemInfoAt and "yes" or "MISSING", ItemInfoInstant and "yes" or "MISSING"))

	local shape = "unknown"
	local probe = SlotInfo(BACKPACK, 1)
	if probe ~= nil then shape = type(probe) end
	A:Print(("  slot info returns " .. A.Val("%s") .. " (a table is correct on 1.15)")
		:format(shape))

	local total, used = 0, 0
	for _, bag in ipairs(InventoryBags()) do
		local n = SlotsIn(bag)
		total = total + n
		for slot = 1, n do if SlotInfo(bag, slot) then used = used + 1 end end
		A:Print(("  bag " .. A.Val("%d") .. "  %d slots"):format(bag, n))
	end
	if HasKeyring() then
		A:Print(("  keyring  " .. A.Val("%d") .. " slots"):format(KeyringSize()))
	end
	A:Print(("  " .. A.Val("%d") .. " / " .. A.Val("%d") .. " used"):format(used, total))
	A:Print(("  at bank: " .. A.Val("%s") .. "  bank slots bought: " .. A.Val("%d"))
		:format(self.atBank and "yes" or "no",
			(_G.GetNumBankSlots and _G.GetNumBankSlots()) or 0))

	for name, state in pairs(self.hideReport or {}) do
		local ink = (state == "STILL SHOWN") and A.Bad or A.Dim
		A:Print(("  %s  %s"):format(name, ink(state)))
	end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function Bags:OnEnable()
	self.frames = self.frames or {}

	-- Built at login, never in combat. Frame creation is the one thing here
	-- that cannot be deferred safely, and building the window the first time
	-- somebody presses B mid-fight is how that turns into a bug report.
	self:Frame("bags")

	self:HideBlizzard()
	self:HookGlobals()
	SetSpecialFrame(true)

	-- Reset the filter THROUGH the box. Setting frame.filter directly leaves
	-- stale text in a box that is no longer filtering by it.
	for _, f in pairs(self.frames) do
		if f.search then f.search.box:SetText("") end
	end

	A:RegisterEvent(self, "BAG_UPDATE_DELAYED", function() Bags:Invalidate() end)
	A:RegisterEvent(self, "BAG_UPDATE", function() Bags:Invalidate() end)
	A:RegisterEvent(self, "BAG_CLOSED", function() Bags:Invalidate() end)
	A:RegisterEvent(self, "BAG_UPDATE_COOLDOWN", function() Bags:Invalidate() end)
	A:RegisterEvent(self, "ITEM_LOCK_CHANGED", function() Bags:Invalidate() end)
	A:RegisterEvent(self, "QUEST_ACCEPTED", function() Bags:Invalidate() end)
	A:RegisterEvent(self, "UNIT_QUEST_LOG_CHANGED", function(_, unit)
		if unit == "player" then Bags:Invalidate() end
	end)

	A:RegisterEvent(self, "PLAYERBANKSLOTS_CHANGED", function() Bags:Invalidate("bank") end)
	A:RegisterEvent(self, "PLAYERBANKBAGSLOTS_CHANGED", function() Bags:Invalidate("bank") end)
	A:RegisterEvent(self, "BANKFRAME_OPENED", function() Bags:ShowBank() end)
	A:RegisterEvent(self, "BANKFRAME_CLOSED", function()
		Bags.atBank = false
		if Bags.frames and Bags.frames.bank then Bags.frames.bank:Hide() end
	end)

	-- Money moves the footer and nothing else. A full grid rebuild on every
	-- copper picked up would redraw eighty buttons for a two-character string.
	A:RegisterEvent(self, "PLAYER_MONEY", function()
		local f = Bags.frames and Bags.frames.bags
		if f and f:IsShown() then Bags:RefreshFooter(f) end
	end)

	-- Deferred by a frame. SellJunk returns immediately unless MerchantFrame is
	-- already shown, and that depends on Blizzard's handler for the same event
	-- having run first. It does today; relying on the registration order of
	-- somebody else's addon is not a thing worth relying on.
	A:RegisterEvent(self, "MERCHANT_SHOW", function()
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(0.1, function() Bags:SellJunk() end)
		else
			Bags:SellJunk()
		end
	end)
	A:RegisterEvent(self, "MERCHANT_CLOSED", function() Bags:FinishSelling() end)

	-- For several seconds after a loading screen the client answers nil for
	-- things that are not nil, so nothing is drawn and nothing is cached across
	-- that window.
	A:RegisterEvent(self, "LOADING_SCREEN_ENABLED", function() Bags.loading = true end)
	A:RegisterEvent(self, "LOADING_SCREEN_DISABLED", function() Bags.loading = false end)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		Bags.loading = false
		wipe(itemClass)
		Bags:HideBlizzard()
		Bags:Invalidate()
	end)

	self:OnConfigChanged()
end

function Bags:OnDisable()
	self:CloseConfirm()
	self:StopSort()
	self.selling = nil

	-- Hide before the bank session is closed, or the OnHide that closes it runs
	-- against a module that has already let go of its state.
	if self.frames then
		for _, f in pairs(self.frames) do pcall(f.Hide, f) end
	end
	if self.atBank then
		self.atBank = false
		if _G.CloseBankFrame then pcall(_G.CloseBankFrame) end
	end

	self:RestoreGlobals()
	self:RestoreBlizzard()
	SetSpecialFrame(false)
	wipe(itemClass)
	self.hideReport = nil
	-- Or a stale opener survives a disable/enable cycle and makes the first
	-- CloseAllBags from a different frame a no-op.
	self._opener = nil
end
