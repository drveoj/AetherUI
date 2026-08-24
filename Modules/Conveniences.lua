--[[--------------------------------------------------------------------------
	AetherUI :: Conveniences

	Two small things the game makes you wait for, and a switch each. Both are
	OFF by default and both say why in the options, because neither is the kind
	of thing to do to somebody without being asked:

	  * INSTANT QUEST TEXT overrides a setting the client already has, under
	    Interface, which the player may have chosen deliberately.
	  * AUTO-REPAIR SPENDS YOUR MONEY. An addon that quietly empties a pocket
	    is not a convenience.

	Neither is clever. Instant quest text is a CVar the client reads itself -
	`instantQuestText`, "1" for instant - so all this does is set it and put it
	back when switched off. The repair is CanMerchantRepair and RepairAllItems,
	which is the same pair the client's own button uses.

	WHAT IT WILL NOT DO: repair when you cannot afford it, and repair silently.
	Both are the same rule - your money is yours and you should be able to see
	where it went - and the second is why every repair prints what it cost.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local CV = A:NewModule("conveniences")

local function cfg() return A.Config:Module("conveniences") end

-- What `instantQuestText` was before we touched it, so switching off is a
-- restore rather than a guess. Recorded once, on the first change.
local questTextWas

-- ---------------------------------------------------------------------------
-- instant quest text
-- ---------------------------------------------------------------------------

--- The client's own setting, set for you.
--
--  Nothing is hooked and nothing is redrawn: QuestFrame reads this CVar itself
--  every time it opens a page, so writing it is the whole feature. Doing it any
--  other way - hooking the fade, forcing the alpha - would be a second owner
--  for a thing the client already decides.
function CV:ApplyQuestText()
	local want = cfg().instantQuestText and "1" or nil

	if want then
		if questTextWas == nil then
			questTextWas = GetCVar("instantQuestText") or "0"
		end
		if GetCVar("instantQuestText") ~= "1" then
			pcall(SetCVar, "instantQuestText", "1")
		end
	elseif questTextWas ~= nil then
		-- Back to what it was, once. A restore that runs twice would record our
		-- own value the second time and have nothing to put back.
		pcall(SetCVar, "instantQuestText", questTextWas)
		questTextWas = nil
	end
end

-- ---------------------------------------------------------------------------
-- repairing
-- ---------------------------------------------------------------------------

--- Money as the client writes it, with a plain fallback.
local function Coins(amount)
	if GetCoinTextureString then
		local ok, text = pcall(GetCoinTextureString, amount)
		if ok and text then return text end
	end
	local g = math.floor(amount / 10000)
	local s = math.floor((amount % 10000) / 100)
	local c = amount % 100
	if g > 0 then return ("%dg %ds %dc"):format(g, s, c) end
	if s > 0 then return ("%ds %dc"):format(s, c) end
	return ("%dc"):format(c)
end

--- Repair everything, if this merchant can and you can afford it.
--
--  Returns what it did, which is what the suite reads: "repaired", "broke" for
--  cannot afford, or nil for nothing to do. A function that only had a side
--  effect would be testable solely through the money, and the money moving is
--  the one thing that must not happen while working it out.
function CV:Repair()
	if not cfg().autoRepair then return end
	if not (CanMerchantRepair and CanMerchantRepair()) then return end

	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return end

	-- CANNOT AFFORD IT, and said so. RepairAllItems on too little money is a
	-- no-op in the client, so an addon that fired blind would look like it had
	-- repaired and leave you in a fight with a broken weapon.
	local purse = GetMoney and GetMoney() or 0
	if purse < cost then
		A:Print(A.Bad(L["not enough for repairs:"]) .. " " .. Coins(cost)
			.. " needed, " .. Coins(purse) .. " on you")
		return "broke"
	end

	RepairAllItems()
	A:Print(A.F("repaired for %s", A.Val(Coins(cost))))
	return "repaired"
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function CV:OnEnable()
	self:ApplyQuestText()

	-- MERCHANT_SHOW rather than the frame's OnShow: the event is the game
	-- saying a merchant is open, and it arrives whether or not anything has
	-- drawn a window for it yet.
	A:RegisterEvent(self, "MERCHANT_SHOW", function() CV:Repair() end)
end

function CV:OnDisable()
	A:UnregisterAllEvents(self)

	-- The CVar goes back. Switching this module off is the player saying they
	-- want the game's own behaviour, and leaving the setting flipped would be
	-- the addon's last word on the subject.
	local want = cfg().instantQuestText
	cfg().instantQuestText = false
	self:ApplyQuestText()
	cfg().instantQuestText = want
end

function CV:OnConfigChanged()
	if not self.enabled then return end
	self:ApplyQuestText()
end
