--[[--------------------------------------------------------------------------
	AetherUI :: IFEC flight detection

	When a flight starts, what it is, and when it ends.

	THERE IS NO TAXI EVENT. Flight is bracketed by PLAYER_CONTROL_LOST and
	PLAYER_CONTROL_GAINED, which also fire for stuns, fear and mind control, so
	both edges are gated on UnitOnTaxi("player"). Blizzard's own UIParent.lua
	does exactly this disambiguation for the same reason.

	The journey is read at BOOKING, not at takeoff: GetNumRoutes and
	TaxiGetNodeSlot only answer while the flight map is open, and it is shut by
	the time control is lost. TakeTaxiNode is hooked to catch that moment.

	Control is lost and regained ONCE for a whole multi-hop journey - there is no
	signal at an intermediate stop - which is why the leg breakdown has to come
	from the route table rather than from watching.

	On the timer path: no reference to anything in the content half.
----------------------------------------------------------------------------]]

local ADDON, A = ...

A.IFEC = A.IFEC or {}
local Taxi = {}
A.IFEC.Taxi = Taxi

local Route = A.IFEC.Route

-- UnitOnTaxi is not reliably true in the frame PLAYER_CONTROL_LOST fires, so
-- the check is deferred. Prior art uses the same half-second for the same
-- reason. Re-checked a few times rather than once, because a single miss would
-- silently cost the whole flight.
local SETTLE, RETRIES = 0.35, 4

Taxi.listeners = {}

--- Anyone wanting to know. Called (event, flight) where event is "board",
--  "land" or "cancel".
function Taxi:AddListener(fn)
	if type(fn) == "function" then
		self.listeners[#self.listeners + 1] = fn
	end
end

local function announce(event, flight)
	for _, fn in ipairs(Taxi.listeners) do
		-- One bad listener must not cost the others, or the flight timer.
		pcall(fn, event, flight)
	end
end

--- The node the player is standing at, which the client marks CURRENT.
local function currentNode()
	if not NumTaxiNodes or not TaxiNodeGetType or not TaxiNodeName then return nil end
	for i = 1, NumTaxiNodes() do
		if TaxiNodeGetType(i) == "CURRENT" then return TaxiNodeName(i) end
	end
	return nil
end

--- Every node the journey touches, in order, read while the map is still open.
--
--  TaxiGetNodeSlot gives the slot at each end of each leg; the names come back
--  through TaxiNodeName. A one-leg trip is {from, to}.
local function journeyNodes(index)
	local from = currentNode()
	if not from then return nil end

	local nodes = { from }

	local hops = GetNumRoutes and GetNumRoutes(index) or 1
	if type(hops) ~= "number" or hops < 1 then hops = 1 end

	if TaxiGetNodeSlot and TaxiNodeName and hops > 1 then
		for leg = 1, hops do
			local slot = TaxiGetNodeSlot(index, leg, false)
			local name = slot and TaxiNodeName(slot)
			if name then nodes[#nodes + 1] = name end
		end
	else
		local name = TaxiNodeName and TaxiNodeName(index)
		if name then nodes[#nodes + 1] = name end
	end

	if #nodes < 2 then return nil end
	return nodes
end

--- Remember what was booked. The map closes immediately after this.
function Taxi:Booked(index)
	local nodes = journeyNodes(index)
	if not nodes then
		self.booked = nil
		return
	end

	local total, legs, complete = Route:Journey(nodes)
	self.booked = {
		nodes    = nodes,
		from     = nodes[1],
		to       = nodes[#nodes],
		legs     = legs,
		expected = total,
		known    = complete,
		bookedAt = GetTime and GetTime() or 0,
	}
	self.earlyLanding = nil
end

--- The player asked to be put down before the booked stop.
--
--  Hooked rather than inferred: a flight cut short would otherwise be recorded
--  as "this route takes 40 seconds" for a trip nobody completed. Prior art
--  misses this and poisons its own table with it.
function Taxi:EarlyLandingRequested()
	if self.flight then self.earlyLanding = true end
end

local function begin()
	if Taxi.flight then return end

	local booked = Taxi.booked
	-- A flight we did not see booked is still a flight: the console opens and
	-- counts up, it just has no route or estimate to show.
	Taxi.flight = {
		nodes    = booked and booked.nodes,
		from     = booked and booked.from,
		to       = booked and booked.to,
		legs     = booked and booked.legs,
		expected = booked and booked.expected,
		known    = booked and booked.known or false,
		startedAt = GetTime and GetTime() or 0,
	}
	Taxi.booked = nil
	announce("board", Taxi.flight)
end

local function settle(tries)
	if Taxi.flight then return end
	if UnitOnTaxi and UnitOnTaxi("player") then
		begin()
		return
	end
	if tries > 0 and C_Timer and C_Timer.After then
		C_Timer.After(SETTLE, function() settle(tries - 1) end)
	end
end

function Taxi:ControlLost()
	settle(RETRIES)
end

--- Land, once the client agrees we are off the griffin.
--
--  UnitOnTaxi IS STILL TRUE IN THE FRAME CONTROL COMES BACK, the same lag as on
--  the way out. Requiring it false here and giving up meant the console stayed
--  up for the rest of the session: the one event that says the flight ended had
--  already been and gone. So it is re-checked rather than trusted once, and if
--  it never clears the flight is ended anyway - control coming back is the
--  authority, UnitOnTaxi only says how soon to believe it.
function Taxi:ControlGained(tries)
	local flight = self.flight
	if not flight then return end

	tries = tries or RETRIES
	if UnitOnTaxi and UnitOnTaxi("player") and tries > 0 then
		if C_Timer and C_Timer.After then
			C_Timer.After(SETTLE, function() Taxi:ControlGained(tries - 1) end)
			return
		end
	end

	self.flight = nil
	flight.endedAt = GetTime and GetTime() or 0
	flight.actual  = flight.endedAt - flight.startedAt

	-- LEARN ONLY FROM A CLEAN SINGLE-HOP FLIGHT. A multi-hop trip teaches
	-- nothing about its legs, since the boundaries are not observable, and an
	-- early landing did not go where it was booked to go.
	if not self.earlyLanding and flight.nodes and #flight.nodes == 2 then
		flight.learned = Route:Learn(flight.nodes, flight.actual)
	end

	self.earlyLanding = nil
	announce("land", flight)
end

--- How far through, for anything drawing a dial. Elapsed is always real; the
--  fraction needs an estimate and is nil without one.
function Taxi:Progress()
	local flight = self.flight
	if not flight then return nil end

	local now = GetTime and GetTime() or 0
	local elapsed = now - flight.startedAt
	if elapsed < 0 then elapsed = 0 end

	local fraction, remaining
	if flight.expected and flight.expected > 0 then
		remaining = flight.expected - elapsed
		if remaining < 0 then remaining = 0 end
		fraction = elapsed / flight.expected
		if fraction > 1 then fraction = 1 end
	end

	return elapsed, remaining, fraction
end

function Taxi:IsFlying()
	return self.flight ~= nil
end

--- Hooks and events. Called by the module rather than at load, so the timer
--  path starts and stops with it.
function Taxi:Start()
	if not self.hooked and hooksecurefunc then
		if TakeTaxiNode then
			hooksecurefunc("TakeTaxiNode", function(index) Taxi:Booked(index) end)
		end
		if TaxiRequestEarlyLanding then
			hooksecurefunc("TaxiRequestEarlyLanding", function() Taxi:EarlyLandingRequested() end)
		end
		self.hooked = true
	end

	A:RegisterEvent(self, "PLAYER_CONTROL_LOST",   function() Taxi:ControlLost() end)
	A:RegisterEvent(self, "PLAYER_CONTROL_GAINED", function() Taxi:ControlGained() end)

	-- A BACKSTOP. Control coming back is the signal, but if it is ever missed -
	-- a disconnect, a loading screen swallowing the event - the console would
	-- sit there for the session. Anything that says we are no longer on a taxi
	-- ends the flight.
	A:RegisterTicker(self, function()
		if Taxi.flight and UnitOnTaxi and not UnitOnTaxi("player") then
			Taxi:ControlGained(0)
		end
	end)

	-- Logging in already airborne is a real state: a disconnect mid-flight puts
	-- you back on the griffin. No booking to recover, so no estimate.
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		if UnitOnTaxi and UnitOnTaxi("player") then begin() end
	end)
end

function Taxi:Stop()
	A:UnregisterAllEvents(self)
	A:UnregisterTicker(self)
	if self.flight then
		local flight = self.flight
		self.flight = nil
		announce("cancel", flight)
	end
end
