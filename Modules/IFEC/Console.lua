--[[--------------------------------------------------------------------------
	AetherUI :: IFEC console

	The window that opens on every flight. This file is the DORMANT form: a
	capsule carrying the dial, the route and the timer, and nothing else.

	That is not a stub. Content is seasonal and often absent, so the console has
	two forms and the flight timer is the permanent one - the design's words are
	"complete in itself; nothing reads as missing". The player region attaches
	below this same capsule when there is something to play, and the only
	geometry that changes is the corner radius.

	On the timer path: Route and Taxi only. Nothing here may reach into the
	content half, and the console must work with that half absent.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local IF = A:NewModule("ifec")

local W, Media, Palette = A.Widgets, A.Media, A.Palette
local Glass = A.Glass

A.IFEC = A.IFEC or {}
local Route, Taxi = A.IFEC.Route, A.IFEC.Taxi

-- The design fixes the header at 560. That is a 1920-wide screen's 560 and it
-- does not travel: at the minimum scale on a 1080p monitor it is still most of
-- a third of the screen, and on a route with two short names it is mostly empty
-- capsule. So 560 is the CEILING and the capsule is otherwise cut to its
-- contents, which is what the concept actually looks like.
local WIDTH_MAX = 560
local WIDTH_MIN = 240
local PAD_L, PAD_R, PAD_T, PAD_B = 10, 14, 8, 8
local GAP     = 12

-- 44 across the ring. The sheet insets the ring inside its cell so the frames
-- cannot bleed into each other, so the frame is a little larger than the ring.
local DIAL    = 44
local DIAL_FRAME = DIAL / (Media.dial and Media.dial.ring or 1)
local CHEV    = 18                     -- the fold control's box
local GLYPH_ROOM = 17                  -- the exit mark plus its gap, inside a pill
local DISC    = 35
local RIM     = 2

local HEIGHT  = PAD_T + DIAL + PAD_B

-- NOT AN ARROW. The design draws one, and Outfit has no U+2192 - it renders the
-- missing-glyph box, which is exactly what shipped and what it looked like.
-- Checked rather than guessed: the font rasterises it identically to notdef.
-- U+00BB is really in the face and says the same thing at this size.
local ROUTE_SEP = "  \194\187  "

--- mm:ss, and never a negative one - a flight that runs long counts to zero
--  and stays there rather than showing minus figures.
local function clock(secs)
	if type(secs) ~= "number" then return "--:--" end
	if secs < 0 then secs = 0 end
	local m = math.floor(secs / 60)
	local s = math.floor(secs % 60)
	return string.format("%d:%02d", m, s)
end

local function Build()
	-- UNDER OUR OWN HOLDER, not UIParent: hiding the interface in flight is one
	-- UIParent:SetAlpha, and a child of it would fade with everything else.
	local f = CreateFrame("Frame", "AetherUIIFEC", IF:Top())
	f:SetSize(WIDTH_MIN, HEIGHT)
	-- Above the interface the console hides, for the same reason the jump-off
	-- button is: a frame at zero alpha still takes the mouse, so anything of
	-- ours that expects a click has to sit over the top of all of it.
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:Hide()

	-- TWO SURFACES, ONE SHOWING. The dormant form is a capsule and the active
	-- one is a panel, and the only difference between them is the corner: 99
	-- against 24. Built together and swapped rather than rebuilt, because the
	-- change happens between flights and a rebuild would drop the dial's state
	-- and the mover's anchor with it.
	f.capsule = Glass.CreatePill(f, { fill = "glassStrong", edge = "glassEdge" })
	f.capsule:SetAllPoints(f)
	f.panel   = Glass.CreatePanel(f, { corner = 24, fill = "glassStrong", edge = "glassEdge" })
	f.panel:SetAllPoints(f)
	f.panel:Hide()

	-- The rule the player region hangs under. Inset 16 either side, per the
	-- design; it only exists when something is attached.
	f.hairline = f:CreateTexture(nil, "ARTWORK")
	f.hairline:SetHeight(1)
	f.hairline:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -HEIGHT)
	f.hairline:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -HEIGHT)
	f.hairline:Hide()

	-- THE DIAL. Three pieces: the track ring, the arc over it, and the disc in
	-- the middle carrying the numeral. The brass rim is a fourth, outside.
	local dial = CreateFrame("Frame", nil, f)
	dial:SetSize(DIAL_FRAME, DIAL_FRAME)
	dial:SetPoint("LEFT", f, "LEFT", PAD_L, 0)
	f.dial = dial

	-- Orb-Ring, not Ring: Ring is authored at 256 for the minimap and would be
	-- minified five times here, which is the rough edge its own notes describe.
	-- Orb-Ring is 128 for a 46px draw, which is what this is.
	dial.rim = dial:CreateTexture(nil, "BACKGROUND")
	dial.rim:SetTexture(Media.texture.orbRing)
	dial.rim:SetPoint("CENTER")
	dial.rim:SetSize(DIAL + RIM * 2, DIAL + RIM * 2)

	dial.track = dial:CreateTexture(nil, "BORDER")
	dial.track:SetTexture(Media.dial.track)
	dial.track:SetAllPoints(dial)

	dial.arc = dial:CreateTexture(nil, "ARTWORK")
	dial.arc:SetTexture(Media.dial.arc)
	dial.arc:SetAllPoints(dial)
	dial.arc:Hide()

	dial.disc = dial:CreateTexture(nil, "BORDER")
	dial.disc:SetTexture(Media.texture.chipDisc)
	dial.disc:SetPoint("CENTER")
	dial.disc:SetSize(DISC, DISC)

	dial.value = W.Text(dial, "ifecDial", "CENTER", "OVERLAY")
	dial.value:SetPoint("CENTER", dial, "CENTER", 0, 0)

	-- The route and the line under it, stacked against the dial.
	f.route = W.Text(f, "ifecRoute", "LEFT", "OVERLAY")
	f.route:SetPoint("BOTTOMLEFT", dial, "RIGHT", GAP, 1)

	f.sub = W.Text(f, "ifecSub", "LEFT", "OVERLAY")
	f.sub:SetPoint("TOPLEFT", f.route, "BOTTOMLEFT", 0, -2)

	-- The minimise chevron, which folds the ACTIVE panel back to this capsule.
	-- There is no third, smaller state - v2 dropped v1's bare dial and calls
	-- this form complete in itself.
	--
	-- HIDDEN UNTIL THERE IS SOMETHING TO FOLD. With no content there is no
	-- player region, so a chevron would be a control that does nothing - and it
	-- would say the console had a hidden half, which is the opposite of "nothing
	-- reads as missing".
	local chev = CreateFrame("Button", nil, f)
	chev:SetSize(CHEV, CHEV)
	chev:SetPoint("RIGHT", f, "RIGHT", -PAD_R, 0)
	chev:EnableMouse(true)
	chev.glyph = chev:CreateTexture(nil, "ARTWORK")
	chev.glyph:SetTexture(Media.texture.chevron)
	chev.glyph:SetAllPoints(chev)
	chev:SetScript("OnClick", function() IF:SetCollapsed(not IF.collapsed) end)
	chev:Hide()
	f.chevron = chev

	return f
end

--- Paint whatever the flight currently says. Safe to call with no flight.
function IF:Refresh()
	local f = self.frame
	if not f then return end

	local flight = Taxi and Taxi.flight
	if not flight then return end

	-- RE-ASSERTED, not set once. Zen drives the same UIParent alpha, and a zen
	-- fade landing mid-flight would put the interface back over the top of us.
	-- Last writer per frame wins, and while you are a passenger that is this.
	if self._hidUI then UIParent:SetAlpha(0) end

	local elapsed, remaining, fraction = Taxi:Progress()

	-- The numeral is time REMAINING, per the design. With no estimate there is
	-- no remaining, so it counts up instead of inventing one.
	f.dial.value:SetText(remaining and clock(remaining) or clock(elapsed))

	local file, l, r, t, b = Media:DialArc(fraction)
	if file then
		f.dial.arc:SetTexture(file)
		f.dial.arc:SetTexCoord(l, r, t, b)
		f.dial.arc:Show()
	else
		f.dial.arc:Hide()
	end

	if flight.from and flight.to then
		f.route:SetText(flight.from .. ROUTE_SEP .. flight.to)
	else
		f.route:SetText(UNKNOWN or "In flight")
	end

	-- "elapsed 2:01 - lands 4:12 - 2 legs". The middle clause needs an
	-- estimate; without one it is dropped rather than shown as --:--.
	local bits = { "elapsed " .. clock(elapsed) }
	if remaining then
		bits[#bits + 1] = "lands " .. clock(remaining)
	end
	local legs = flight.legs and #flight.legs or 0
	if legs > 1 then
		bits[#bits + 1] = legs .. " legs"
	end
	f.sub:SetText(table.concat(bits, "  \194\183  "))

	self:Fit()
	self:UpdateJumpOff(flight)
end

--- Cut the capsule to what is in it.
--
--  Called after the strings are set, because it measures them. A route with two
--  short names gets a short capsule; a long one grows to the design's 560 and
--  stops, after which the strings truncate rather than the window running off
--  the screen.
function IF:Fit()
	local f = self.frame
	if not f or f.region then return end          -- a panel keeps its width

	local text = 0
	for _, fs in ipairs({ f.route, f.sub }) do
		local w = fs.GetStringWidth and fs:GetStringWidth() or 0
		if w > text then text = w end
	end

	local want = PAD_L + DIAL_FRAME + GAP + text + GAP + CHEV + PAD_R
	if want < WIDTH_MIN then want = WIDTH_MIN end
	if want > WIDTH_MAX then want = WIDTH_MAX end

	-- Only when it actually moves. SetWidth on a frame the mover is holding is
	-- cheap but not free, and this runs on every tick of every flight.
	if math.abs((f:GetWidth() or 0) - want) > 0.5 then
		f:SetWidth(want)
	end
end

--- Hang something under the header, which is what makes this a panel.
--
--  The content half calls this; nothing here reaches the other way. That is the
--  boundary the brief asks for - the timer must work with the content modules
--  absent or broken, so the dependency only ever points at us.
--
--  Region changes belong BETWEEN flights, not during one. Nothing enforces that
--  here because nothing here can know; it is the caller's rule.
function IF:AttachRegion(region, height)
	local f = self.frame
	if not f or not region then return false end

	f.region, f.regionHeight = region, height or 0
	region:SetParent(f)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEIGHT)
	region:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEIGHT)

	self.collapsed = nil
	self:Lay()
	return true
end

--- Back to the capsule. Complete in itself, not a panel with a hole in it.
function IF:DetachRegion()
	local f = self.frame
	if not f then return false end

	if f.region then f.region:Hide() end
	f.region, f.regionHeight = nil, 0
	self.collapsed = nil
	self:Lay()
	return true
end

function IF:HasRegion()
	return self.frame ~= nil and self.frame.region ~= nil
end

--- Fold the player region away, or bring it back.
--
--  DISTINCT FROM HAVING NO REGION. Both end up looking like the capsule, but
--  one is "there is nothing to play" and the other is "you put it away" - and
--  the difference is whether there is a control to bring it back.
function IF:SetCollapsed(on)
	if not self:HasRegion() then return false end
	self.collapsed = on and true or nil
	self:Lay()
	return true
end

--- Whichever of the two forms the current state calls for.
function IF:Lay()
	local f = self.frame
	if not f then return end

	-- Plain booleans, not `open and X or Y`: that idiom cannot yield false, and
	-- it has now cost two bugs in one afternoon.
	local open = (self:HasRegion() and not self.collapsed) and true or false

	if f.region then f.region:SetShown(open) end
	f:SetHeight(HEIGHT + (open and f.regionHeight or 0))
	f.panel:SetShown(open)
	f.capsule:SetShown(not open)
	f.hairline:SetShown(open)

	-- The control only exists while there is something to fold. Pointing up
	-- once folded, because that is the way it will move.
	f.chevron:SetShown(self:HasRegion() and true or false)
	if f.chevron.glyph.SetRotation then
		f.chevron.glyph:SetRotation(self.collapsed and math.pi or 0)
	end

	if not open then self:Fit() end
end

function IF:Restyle()
	local f = self.frame
	if not f then return end
	local c = Palette.c

	-- Drawn at the profile's scale like everything else of ours, times its own
	-- multiplier. The console is read once a minute from across the screen
	-- rather than glanced at constantly, so it wants to be smaller than the HUD
	-- - the same argument the dock and the nameplates make for having one.
	local cfg = A.Config:Module("ifec")
	f:SetScale((A.db.profile.scale or 1) * (tonumber(cfg.scale) or 1))

	W.Color(f.route, c.text)
	W.Color(f.sub, c.textDim)
	W.Color(f.dial.value, c.text)

	f.dial.track:SetVertexColor(c.ifecTrack[1], c.ifecTrack[2], c.ifecTrack[3], c.ifecTrack[4])
	f.dial.arc:SetVertexColor(c.ifecDial[1], c.ifecDial[2], c.ifecDial[3])
	f.dial.rim:SetVertexColor(c.ifecBrass[1], c.ifecBrass[2], c.ifecBrass[3], c.ifecBrass[4])
	f.dial.disc:SetVertexColor(c.ifecDisc[1], c.ifecDisc[2], c.ifecDisc[3])
	f.chevron.glyph:SetVertexColor(c.textDim[1], c.textDim[2], c.textDim[3], 0.7)
	f.hairline:SetColorTexture(c.glassEdge[1], c.glassEdge[2], c.glassEdge[3], 0.18)
end

--- The console opens on boarding and closes on landing, both from the flight
--  itself rather than from a timer of our own.
function IF:OnFlight(event, flight)
	if not self.enabled then return end

	if event == "board" then
		if not self.frame then
			self.frame = Build()
			-- Well clear of the bottom. The design's 104 is measured on an
			-- unscaled 1080 screen; here the HUD is already down there, and the
			-- player region grows this frame upward from its own bottom edge,
			-- so it needs the room above rather than below.
			A.Movers:Register("ifec", self.frame,
				{ point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 260 }, "In-flight console")
			self:Restyle()
		end
		-- A new flight is a new chance to get off it.
		self._jumpAsked = nil
		self:Refresh()
		self.frame:Show()
		self:HideInterface(true)
		A:RegisterTicker(self, function() IF:Refresh() end)
	else
		A:UnregisterTicker(self)
		self:HideInterface(false)
		-- Refresh is what normally hides this, and Refresh returns early with no
		-- flight - so landing left the button on screen over the minimap.
		if self.jump then self.jump:Hide() end
		if self.frame then self.frame:Hide() end
	end
end

--- The rest of the interface, out of the way while you are a passenger.
--
--  One UIParent:SetAlpha, which is how Zen does it and covers everything
--  including addons we have never heard of. The console is parentless so it
--  survives; nothing else needs naming.
--
--  Never fights combat: you cannot be attacked on a griffin, but a flight that
--  ends in one - or a disconnect - must not leave the interface invisible, so
--  the restore also hangs off leaving combat and entering the world.
function IF:HideInterface(hide)
	local cfg = A.Config:Module("ifec")
	if cfg.hideUI == false then hide = false end

	if hide then
		if self._hidUI then return end
		self._hidUI = true
		self._uiAlpha = UIParent:GetAlpha() or 1
		UIParent:SetAlpha(0)
	else
		if not self._hidUI then return end
		self._hidUI = nil
		UIParent:SetAlpha(self._uiAlpha or 1)
		self._uiAlpha = nil
	end

	-- THE MAP STAYS. It is drawing the ground going past, which is the one part
	-- of the interface worth having while you are a passenger. Asked of the
	-- minimap module and skipped if there isn't one - a console that needed the
	-- map to exist would be a console with a new way to break.
	local MM = A:GetModule("minimap")
	if MM and MM.SetDetached and MM.enabled then
		MM:SetDetached(hide, self:Top())
	end
end

--- A parentless holder for anything that has to outlive UIParent's alpha.
--
--  CREATED parentless and kept, rather than reparenting things to nil when the
--  moment comes. The two are not the same: a frame moved to nil kept drawing
--  but stopped updating and stopped taking the mouse, which is a minimap with a
--  frozen clock and a button that ignores you.
function IF:Top()
	if not self.top then
		local t = CreateFrame("Frame", "AetherUIIFECTop")
		t:SetAllPoints(UIParent)
		t:SetFrameStrata("FULLSCREEN_DIALOG")
		self.top = t
	end
	return self.top
end

--- Get off at the next stop.
--
--  TaxiRequestEarlyLanding is live on this build - Blizzard's own vehicle-leave
--  button calls it, gated on UnitOnTaxi, with TAXI_CANCEL for its tooltip.
--
--  ONLY ON A MULTI-LEG JOURNEY. It puts you down at the NEXT flight master, so
--  on a single-hop flight that is the place you were going anyway and the
--  button is at best pointless. On a two-leg trip it is the whole point.
--
--  It hangs off the minimap rather than the console, where the concept puts it
--  and where the map is telling you what you would be getting off into. The
--  minimap module is asked for its frame and the button simply does not appear
--  if there is no minimap to hang it on.
function IF:UpdateJumpOff(flight)
	local legs = flight and flight.legs and #flight.legs or 0
	local wanted = legs > 1 and TaxiRequestEarlyLanding ~= nil

	if not wanted then
		if self.jump then self.jump:Hide() end
		return
	end

	if not self.jump then
		local MM = A:GetModule("minimap")
		local host = MM and MM.frame
		if not host then return end

		-- THE SAME PILL THE MAP ALREADY USES, as a Button. A second capsule of
		-- our own would only ever be a near-copy of this one, and it was landing
		-- on top of it.
		local b = W.Pill(host, "pnBody", { height = 24, padX = 12,
			frameType = "Button" })
		-- UNDER THE ZONE PILL, not under the map: the pill is anchored there
		-- already, so anchoring to the map put the two in the same place.
		b:SetPoint("TOP", MM.pill or host, "BOTTOM", 0, -6)
		b:EnableMouse(true)
		if b.RegisterForClicks then b:RegisterForClicks("AnyUp") end

		-- ABOVE THE INTERFACE WE JUST HID. Alpha does not stop a frame taking
		-- the mouse: everything under UIParent is still sitting there at zero
		-- alpha, catching clicks, and this button was underneath it. Hiding the
		-- interface is what put it there, so raising this is the other half of
		-- the same decision.
		b:SetFrameStrata("FULLSCREEN_DIALOG")
		b:SetToplevel(true)

		-- ITS OWN GLYPH, not the chevron. The chevron means "this opens"
		-- everywhere else in the interface - the toolbox rail, every dropdown -
		-- and borrowing it here would promise a window. This is an arrow onto a
		-- ground line: alight here.
		b.glyph = b:CreateTexture(nil, "ARTWORK")
		b.glyph:SetSize(11, 11)
		b.glyph:SetPoint("RIGHT", b.text, "LEFT", -6, 0)
		Media:SetIcon(b.glyph, "exit")

		-- The pill sizes itself to its text, so the glyph has to be paid for.
		b.label = b.text
		b.SetPillLabel = function(self, text)
			self:SetLabel(text)
			self:SetWidth((self:GetWidth() or 0) + GLYPH_ROOM)
			self.text:ClearAllPoints()
			self.text:SetPoint("CENTER", self, "CENTER", GLYPH_ROOM / 2, 0)
		end

		b:SetScript("OnClick", function() IF:RequestJumpOff() end)
		b:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if IF._jumpAsked then
				GameTooltip:SetText("Exit requested")
				GameTooltip:AddLine("Exiting early at the next available flight master.",
					1, 1, 1, true)
			else
				GameTooltip:SetText("Jump Off")
				GameTooltip:AddLine("Request exit at the next flight master.",
					1, 1, 1, true)
			end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

		self.jump = b
	end

	self:PaintJumpOff()
	self.jump:Show()
end

--- The button in whichever of its two states it is in.
--
--  Asking cannot be taken back - the client has no "actually, carry on" - so
--  once asked it stops being a control and becomes a readout.
function IF:PaintJumpOff()
	local b = self.jump
	if not b then return end

	-- ACCENT, NOT WHITE. It sits a few pixels under the pill's clock, and two
	-- white readouts stacked read as one block of text - the colour is what
	-- says these are different things.
	local c = Palette.c

	if self._jumpAsked then
		b:SetPillLabel("Exit requested")
		W.Color(b.label, c.textDim)
		b.glyph:SetVertexColor(c.textDim[1], c.textDim[2], c.textDim[3], 0.55)
	else
		b:SetPillLabel("Jump Off")
		W.Color(b.label, c.accent)
		b.glyph:SetVertexColor(c.accent[1], c.accent[2], c.accent[3], 1)
	end
	b:EnableMouse(true)              -- hoverable either way, for the tooltip
end

--- Ask to be put down at the next stop.
function IF:RequestJumpOff()
	if self._jumpAsked then return false end
	if not TaxiRequestEarlyLanding then return false end

	local ok = pcall(TaxiRequestEarlyLanding)
	if not ok then return false end

	self._jumpAsked = true
	self:PaintJumpOff()
	if GameTooltip and self.jump and GameTooltip:IsShown() then
		local enter = self.jump:GetScript("OnEnter")
		if enter then enter(self.jump) end
	end
	return true
end

--- Put the interface back if we are holding it hidden and are not flying.
--
--  A HIDDEN INTERFACE THAT STAYS HIDDEN is the worst thing this feature could
--  do, and a landing can be missed: a disconnect, a loading screen eating the
--  event. So this is not only wired to the flight ending - it also runs on
--  every world load, and it is safe to call at any time.
function IF:Recover()
	if not self._hidUI then return false end
	if UnitOnTaxi and UnitOnTaxi("player") then return false end
	self:HideInterface(false)
	return true
end

function IF:OnInitialize()
	if Taxi then
		Taxi:AddListener(function(event, flight) IF:OnFlight(event, flight) end)
	end

	-- A HIDDEN INTERFACE THAT STAYS HIDDEN is the worst thing this feature
	-- could do. If a flight ends any way we did not see - a disconnect, a
	-- loading screen - the next time the world loads it comes back.
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() IF:Recover() end)
end

function IF:OnEnable()
	if Taxi then Taxi:Start() end
	-- Boarding while the module was off is a real case: pick the flight up.
	if Taxi and Taxi:IsFlying() then self:OnFlight("board", Taxi.flight) end
end

function IF:OnDisable()
	A:UnregisterTicker(self)
	if Taxi then Taxi:Stop() end
	self:HideInterface(false)
	if self.frame then self.frame:Hide() end
end

function IF:OnSkinChanged()
	self:Restyle()
end

function IF:OnConfigChanged()
	self:Restyle()
	-- Switching the setting off mid-flight puts the interface back at once,
	-- rather than at the next landing.
	if self._hidUI then self:HideInterface(true) end
end
