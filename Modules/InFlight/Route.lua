--[[--------------------------------------------------------------------------
	AetherUI :: IFEC route lookup

	How long a flight takes. The table in Routes.lua is generated from the
	client's own DB2 export and holds SINGLE-HOP legs only; a journey is the sum
	of its legs. That is not an approximation - it was checked against measured
	flights and the arithmetic is exact:

	    Ratchet->Crossroads 68 + Crossroads->Orgrimmar 141 = 209 = Ratchet->Orgrimmar

	Storing legs rather than routes means every multi-hop journey made of known
	legs is known too, and it is what makes the leg-boundary ticks derived
	rather than guessed.

	Legs are DIRECTIONAL. Orgrimmar->Ratchet is 161s and Ratchet->Orgrimmar is
	209s; a symmetric table would be wrong by half a minute.

	This file is on the timer path, so it must not reference anything in the
	content half of the module.
----------------------------------------------------------------------------]]

local ADDON, A = ...

A.IFEC = A.IFEC or {}
local Route = {}
A.IFEC.Route = Route

--- Where a duration came from, worst to best.
local FROM_NONE, FROM_TABLE, FROM_LEARNED = nil, "table", "learned"

local function learnedStore()
	local cfg = A.Config and A.Config:Module("inflight")
	if not cfg then return nil end
	cfg.learned = cfg.learned or {}
	return cfg.learned
end

--- Seconds for one leg, and where the number came from.
--
--  A measured value always beats the table. That matters most for the eight
--  legs the client has two paths for - the neutral hubs both factions share,
--  where the two differ by up to 52 seconds and nothing in the data says which
--  is ours. Those are stored as a mean and flagged in IFEC_LEGS_FUZZY.
function Route:Leg(from, to)
	if type(from) ~= "string" or type(to) ~= "string" then return nil end

	local learned = learnedStore()
	local seen = learned and learned[from] and learned[from][to]
	if seen then return seen, FROM_LEARNED end

	local legs = A.IFEC_LEGS
	local row = legs and legs[from]
	local secs = row and row[to]
	if secs then return secs, FROM_TABLE end

	return nil, FROM_NONE
end

--- True if the table's figure for this leg is a mean of two faction paths.
function Route:IsFuzzy(from, to)
	local fuzzy = A.IFEC_LEGS_FUZZY
	local row = fuzzy and fuzzy[from]
	return (row and row[to]) == true
end

--- A whole journey, as a list of node names in order.
--
--  Returns the total, a per-leg breakdown for the boundary ticks, and whether
--  every leg was known. An unknown leg does not fail the journey - the console
--  still opens and still counts up, it just cannot say when you land.
function Route:Journey(nodes)
	if type(nodes) ~= "table" or #nodes < 2 then return nil, nil, false end

	local total, legs, complete, at = 0, {}, true, 0
	for i = 1, #nodes - 1 do
		local from, to = nodes[i], nodes[i + 1]
		local secs, source = self:Leg(from, to)

		if secs then
			at = at + secs
			total = total + secs
		else
			complete = false
		end

		legs[#legs + 1] = {
			from    = from,
			to      = to,
			seconds = secs,
			source  = source,
			-- Where this leg ENDS on the journey's timeline, which is what the
			-- brass ticks are drawn at. nil once a leg is unknown, because
			-- everything after it has moved by an unknown amount.
			at      = complete and at or nil,
			fuzzy   = self:IsFuzzy(from, to),
		}
	end

	return (complete and total or nil), legs, complete
end

--- Record a flight we actually timed.
--
--  Only ever called with a whole journey the player completed, and only when
--  the landing node is the one that was booked - TaxiRequestEarlyLanding lets a
--  player step off early, and a truncated flight recorded against the booked
--  destination would poison the table with a number for a trip nobody took.
--
--  A multi-hop journey teaches us nothing about its individual legs, since we
--  cannot see the boundaries. So only single-hop flights are learned from.
function Route:Learn(nodes, seconds)
	if type(nodes) ~= "table" or #nodes ~= 2 then return false end
	if type(seconds) ~= "number" or seconds <= 5 then return false end

	local from, to = nodes[1], nodes[2]
	if type(from) ~= "string" or type(to) ~= "string" then return false end

	local learned = learnedStore()
	if not learned then return false end

	learned[from] = learned[from] or {}
	learned[from][to] = seconds
	return true
end

--- What the shipped table said before we learned better, for the divergence
--  report. The brief asks for this: correct the table between releases.
function Route:Divergence()
	local learned, out = learnedStore(), {}
	if not learned then return out end

	for from, row in pairs(learned) do
		for to, secs in pairs(row) do
			local shipped = A.IFEC_LEGS and A.IFEC_LEGS[from] and A.IFEC_LEGS[from][to]
			if shipped then
				out[#out + 1] = {
					from = from, to = to,
					measured = secs, shipped = shipped,
					delta = secs - shipped,
					fuzzy = self:IsFuzzy(from, to),
				}
			end
		end
	end

	table.sort(out, function(a, b)
		return math.abs(a.delta) > math.abs(b.delta)
	end)
	return out
end
