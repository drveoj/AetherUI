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

-- The design's header: 560 wide, 10/20/10/12 padding, 14 between things.
local WIDTH   = 560
local PAD_L, PAD_R, PAD_T, PAD_B = 12, 20, 10, 10
local GAP     = 14

-- 44 across the ring. The sheet insets the ring inside its cell so the frames
-- cannot bleed into each other, so the frame is a little larger than the ring.
local DIAL    = 44
local DIAL_FRAME = DIAL / (Media.dial and Media.dial.ring or 1)
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
	-- NO PARENT, the same as Zen's console and for the same reason: hiding the
	-- interface in flight is one UIParent:SetAlpha, and a child of UIParent
	-- would fade with everything else.
	local f = CreateFrame("Frame", "AetherUIIFEC")
	f:SetSize(WIDTH, HEIGHT)
	f:SetFrameStrata("MEDIUM")
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

	-- The minimise chevron. It folds the ACTIVE panel back to this capsule;
	-- there is no third, smaller state - v2 dropped v1's bare dial and calls
	-- this form complete in itself.
	local chev = CreateFrame("Button", nil, f)
	chev:SetSize(18, 18)
	chev:SetPoint("RIGHT", f, "RIGHT", -PAD_R, 0)
	chev.glyph = chev:CreateTexture(nil, "ARTWORK")
	chev.glyph:SetTexture(Media.texture.chevron)
	chev.glyph:SetAllPoints(chev)
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
	region:Show()

	f:SetHeight(HEIGHT + f.regionHeight)
	f.capsule:Hide()
	f.panel:Show()
	f.hairline:Show()
	return true
end

--- Back to the capsule. Complete in itself, not a panel with a hole in it.
function IF:DetachRegion()
	local f = self.frame
	if not f then return false end

	if f.region then f.region:Hide() end
	f.region, f.regionHeight = nil, 0

	f:SetHeight(HEIGHT)
	f.panel:Hide()
	f.hairline:Hide()
	f.capsule:Show()
	return true
end

function IF:HasRegion()
	return self.frame ~= nil and self.frame.region ~= nil
end

function IF:Restyle()
	local f = self.frame
	if not f then return end
	local c = Palette.c

	-- Drawn at the profile's scale like everything else of ours. Without this
	-- the console is the one thing on screen at 1.0 and reads enormous next to
	-- a HUD at 0.71.
	f:SetScale(A.db.profile.scale or 1)

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
		self:Refresh()
		self.frame:Show()
		self:HideInterface(true)
		A:RegisterTicker(self, function() IF:Refresh() end)
	else
		A:UnregisterTicker(self)
		self:HideInterface(false)
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
