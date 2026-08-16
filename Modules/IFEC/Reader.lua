--[[--------------------------------------------------------------------------
	AetherUI :: IFEC reader

	The magazine, opened. Gossip is READ, NOT PLAYED - it has no audio, no
	duration and no place in a running order, so it never enters the queue at
	all and the library opens it here instead. The music carries on underneath,
	which is the entire point of it taking no time.

	A PAGE IS AN IMAGE. An issue is eight 1024x1024 textures rather than copy in
	a frame, because a magazine is laid out - masthead, columns, pull-quotes,
	art - and reproducing that from strings would be writing a typesetter. So
	this file has no opinion whatever about what is ON a page. It turns them.

	NOT ANCHORED TO WHATEVER OPENED IT, unlike the library. A page is 1024 square
	and hung off the side of the Toolbox it would be mostly off the edge. It is
	centred, movable and parented outside UIParent, so it works on the ground
	and at altitude with the interface hidden.

	BUILT AROUND THE PAGE, not around the screen. It asked how much room there
	was and took all of it, which on a tall monitor is a magazine filling the
	monitor. The size is a fraction of the art's own, the screen only says no,
	and the fraction is a setting.

	FIT, AND 1:1. At that fraction the body copy falls under legibility, so
	there is a zoom: fitted to read the headlines, actual size with a drag to
	pan for the small print - and actual size means it, whatever the scale.
----------------------------------------------------------------------------]]

local ADDON, A = ...

A.IFEC = A.IFEC or {}
local Reader = {}
A.IFEC.Reader = Reader

local W, Media, Palette = A.Widgets, A.Media, A.Palette
local Glass = A.Glass
local Content = A.IFEC.Content

-- The page's own size. Every issue is authored square at this, which is what
-- lets the frame be square and the zoom be a single number.
local PAGE = 1024

-- How much of that to draw by default.
--
-- BUILT AROUND THE PAGE, not around the screen. The first version asked how
-- much room there was and took all of it, which on a 1600-tall monitor is a
-- magazine filling the monitor - a thing you project rather than a thing you
-- hold. The page is authored at a known size, so that is the number to start
-- from and this is the fraction of it.
--
-- 0.7 by the rule of thumb that the whole window - page, margin and the strip
-- under it - fits vertically on a 1080 screen with the interface still around
-- it. The screen is a CLAMP now rather than the source of the number.
local PAGE_DRAW = 0.7

local PAD    = 12          -- around the page inside the panel
local TOP_H  = 26          -- the strip over it: what this is, and the way out
local BAR_H  = 30          -- the strip under it: the pager and the zoom
local MARGIN = 48          -- the least the panel leaves of the screen

-- WHAT THIS IS, not what is in it. The window used to caption itself with the
-- issue's own title, which every page already carries in letters an inch high.
-- A masthead is the first thing a magazine says about itself, and repeating it
-- in our chrome is the console talking over the thing it is showing.
local TITLE = "I.F.E.C. MEDIA READER"

-- ---------------------------------------------------------------------------

local function glyphButton(parent, icon, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)
	b:EnableMouse(true)
	b.glyph = b:CreateTexture(nil, "OVERLAY")
	b.glyph:SetSize(size or 13, size or 13)
	b.glyph:SetPoint("CENTER")
	Media:SetIcon(b.glyph, icon)
	return b
end

function Reader:Build()
	if self.frame then return self.frame end

	-- OUTSIDE UIParent, under the console's own holder. Hiding the interface in
	-- flight is one UIParent:SetAlpha and a child of it would be read at zero.
	local IF = A:GetModule("ifec")
	local top = IF and IF.Top and IF:Top() or UIParent

	local f = Glass.CreatePanel(top, { corner = 18, fill = "glassStrong",
		edge = "glassEdge", shadow = A.db.profile.glass.shadow })

	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- Dragged once, it keeps where it was put rather than being re-centred
		-- by the next open.
		Reader._placed = true
	end)
	f:Hide()

	-- THE CHROME AT THE TOP: what the window is, and the way out of it. The page
	-- controls stay at the foot, where turning a page belongs.
	f.title = W.Text(f, "ifecSection", "LEFT", "OVERLAY")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 4, -PAD - 5)
	f.title:SetText(TITLE)

	-- A CROSS FROM THE SHEET, not the multiplication sign the older windows here
	-- type. Whether a font has U+00D7 is the font's business - Outfit does not
	-- carry it in every weight, and the one it landed in drew the notdef box
	-- followed by the digits of the escape.
	f.close = glyphButton(f, "close", 11)
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD - 2, -PAD)
	f.close:SetScript("OnClick", function() Reader:Close() end)

	-- THE PAGE, INSIDE A SCROLLFRAME. There is no reliable way to clip a plain
	-- frame's children on this client, and at actual size the page is bigger
	-- than the window it is in - so the one widget that does clip is the one
	-- that carries it, and panning is a scroll offset rather than a moved
	-- texture.
	local view = CreateFrame("ScrollFrame", nil, f)
	view:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(PAD + TOP_H))
	view:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD + BAR_H)
	f.view = view

	local sheet = CreateFrame("Frame", nil, view)
	view:SetScrollChild(sheet)
	f.sheet = sheet

	sheet.page = sheet:CreateTexture(nil, "ARTWORK")
	sheet.page:SetAllPoints(sheet)

	-- Drag ON THE PAGE pans it, and only when there is anywhere to pan to. The
	-- panel's own drag moves the window, so the two must not both be live: a
	-- window that walks off the screen while you are reading it is worse than
	-- one you cannot pan.
	view:EnableMouse(true)
	view:EnableMouseWheel(true)
	view:SetScript("OnMouseWheel", function(_, delta)
		Reader:Turn(delta > 0 and -1 or 1)
	end)
	view:SetScript("OnMouseDown", function(self)
		if not Reader.zoomed then return end
		local x, y = GetCursorPosition()
		self._drag = { x = x, y = y,
			h = self:GetHorizontalScroll() or 0, v = self:GetVerticalScroll() or 0 }
	end)
	view:SetScript("OnMouseUp", function(self) self._drag = nil end)
	view:SetScript("OnUpdate", function(self)
		local d = self._drag
		if not d then return end
		local x, y = GetCursorPosition()
		local s = self:GetEffectiveScale()
		if s <= 0 then s = 1 end
		Reader:ScrollTo(d.h - (x - d.x) / s, d.v + (y - d.y) / s)
	end)

	-- The strip along the bottom: which page, and the way through them.
	f.zoom = glyphButton(f, "zoom", 12)
	f.zoom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 2, PAD + 2)
	f.zoom:SetScript("OnClick", function() Reader:SetZoomed(not Reader.zoomed) end)

	f.next = glyphButton(f, "next", 13)
	f.next:SetPoint("RIGHT", f.zoom, "LEFT", -10, 0)
	f.next:SetScript("OnClick", function() Reader:Turn(1) end)

	f.pager = W.Text(f, "ifecCaption", "CENTER", "OVERLAY")
	f.pager:SetPoint("RIGHT", f.next, "LEFT", -6, 0)
	f.pager:SetWidth(58)

	f.prev = glyphButton(f, "prev", 13)
	f.prev:SetPoint("RIGHT", f.pager, "LEFT", -6, 0)
	f.prev:SetScript("OnClick", function() Reader:Turn(-1) end)

	-- ESCAPE CLOSES IT, on the frame rather than through UISpecialFrames:
	-- CloseSpecialWindows goes through HideUIPanel, which is combat-blocked for
	-- addons on this client and fails silently. Keyboard input is propagated so
	-- the one key we act on is the only one swallowed.
	f:EnableKeyboard(true)
	if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(true) end
	f:SetScript("OnKeyDown", function(self, key)
		if key ~= "ESCAPE" then return end
		if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
		Reader:Close()
	end)
	f:SetScript("OnShow", function(self)
		if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
	end)

	self.frame = f
	self:Size()
	self:Restyle()
	return f
end

--- As big as the screen will let it be, square, and never bigger.
--
--  MEASURED IN PHYSICAL PIXELS, then converted back into our own units. This
--  window lives under a parentless holder so it survives the interface being
--  hidden, and a parentless frame does not share UIParent's scale - so asking
--  UIParent how tall the screen is and then drawing that many units HERE is
--  asking one ruler and cutting with another. It came out half as big again as
--  the screen and hung off the top.
--
--  Not scaled by the profile either: everything else of ours is chrome and
--  shrinks with the HUD, and a photograph shrunk is just a worse photograph.
--
--  THE WHOLE WINDOW HAS TO FIT, not the page. The strip under it carries the
--  pager and the controls, and clamping the page alone put those over the edge.
function Reader:Size()
	local f = self.frame
	if not f then return end

	-- OUR GLOBAL SCALE, like every window of ours. Set BEFORE the fit is worked
	-- out, not after: the fit is computed in physical pixels through this
	-- frame's own effective scale, so the scale has to be true when it is asked
	-- for or the answer is one setting out of date.
	local want = (A.db and A.db.profile and A.db.profile.scale) or 1
	if want <= 0 then want = 1 end
	if math.abs((f:GetScale() or 1) - want) > 0.0001 then f:SetScale(want) end

	local mine = f.GetEffectiveScale and f:GetEffectiveScale() or 1
	if not mine or mine <= 0 then mine = 1 end
	local theirs = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
	if not theirs or theirs <= 0 then theirs = 1 end

	local screenW = (UIParent:GetWidth()  or 1365) * theirs
	local screenH = (UIParent:GetHeight() or 768)  * theirs

	local chromeW = PAD * 2
	local chromeH = PAD * 2 + TOP_H + BAR_H

	-- THE PAGE DECIDES, and the screen only says no. A fraction of the art's own
	-- size, tunable because how big a magazine wants to be is a matter of taste
	-- and eyesight rather than something this file can work out.
	local cfg = A.Config and A.Config:Module("ifec")
	local draw = (cfg and tonumber(cfg.readerScale)) or PAGE_DRAW
	if draw <= 0 then draw = PAGE_DRAW end

	local side = PAGE * draw

	-- Clamped to what there is, which on any ordinary screen does not bite.
	local room = math.min((screenH - MARGIN) / mine - chromeH,
	                      (screenW - MARGIN) / mine - chromeW)
	if side > room then side = room end
	if side < 200 then side = 200 end

	f:SetSize(side + chromeW, side + chromeH)
	if not self._placed then
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	self:Fit()
end

--- Lay the page out at whichever of the two sizes is current.
function Reader:Fit()
	local f = self.frame
	if not f then return end

	local w = math.max(f.view:GetWidth() or 1, 1)
	local h = math.max(f.view:GetHeight() or 1, 1)

	-- ACTUAL SIZE MEANS ACTUAL SIZE. The window follows the profile scale like
	-- everything else, so a page of PAGE units is PAGE times that many pixels -
	-- which at 0.71 is a "1:1" that is nothing of the kind. Zoomed, the sheet is
	-- sized so the art lands one texel to one screen pixel whatever the scale.
	local mine = f.GetEffectiveScale and f:GetEffectiveScale() or 1
	if not mine or mine <= 0 then mine = 1 end
	local side = self.zoomed and (PAGE / mine) or math.min(w, h)

	f.sheet:SetSize(side, side)
	-- Centred when it is smaller than the window, so a fitted page does not sit
	-- in the corner of its own frame.
	f.view:SetHorizontalScroll(0)
	f.view:SetVerticalScroll(0)
	if not self.zoomed then
		f.sheet:ClearAllPoints()
		f.sheet:SetPoint("CENTER", f.view, "CENTER", 0, 0)
	else
		f.sheet:ClearAllPoints()
		f.sheet:SetPoint("TOPLEFT", f.view, "TOPLEFT", 0, 0)
		self:ScrollTo((side - w) / 2, 0)
	end
end

function Reader:ScrollTo(h, v)
	local f = self.frame
	if not f then return end
	local maxH = math.max(0, (f.sheet:GetWidth() or 0) - (f.view:GetWidth() or 0))
	local maxV = math.max(0, (f.sheet:GetHeight() or 0) - (f.view:GetHeight() or 0))
	f.view:SetHorizontalScroll(math.max(0, math.min(h or 0, maxH)))
	f.view:SetVerticalScroll(math.max(0, math.min(v or 0, maxV)))
end

function Reader:SetZoomed(on)
	self.zoomed = on and true or nil
	self:Fit()
	self:Paint()
end

-- ---------------------------------------------------------------------------
-- pages
-- ---------------------------------------------------------------------------

function Reader:Pages()
	return (self.item and self.item.pages) or {}
end

--- Go `by` pages, and stop at the ends rather than wrapping.
--
--  A magazine is not a loop. Turning past the back cover onto the front again
--  is a thing no paper does, and it is how you lose your place in one.
function Reader:Turn(by)
	local pages = self:Pages()
	if #pages == 0 then return false end

	local want = (self.page or 1) + (by or 0)
	if want < 1 then want = 1 end
	if want > #pages then want = #pages end
	if want == self.page then return false end

	self.page = want
	self:Remember()
	self:Paint()
	return true
end

--- WHERE YOU GOT TO, in the same field an episode uses for its segment. A
--  half-read magazine and a half-heard episode are the same fact about the same
--  player, and the library reads both off one place.
function Reader:Remember()
	if not Content or not self.item then return end
	local pages = self:Pages()
	Content:Remember(self.item.key, self.page or 1, (self.page or 1) >= #pages)
end

function Reader:Paint()
	local f, item = self.frame, self.item
	if not f or not item then return end

	local pages = self:Pages()
	local n = math.max(1, math.min(self.page or 1, #pages))

	f.sheet.page:SetTexture(pages[n])
	f.pager:SetText(n .. " / " .. #pages)

	f.prev:SetAlpha(n > 1 and 1 or 0.3)
	f.next:SetAlpha(n < #pages and 1 or 0.3)

	local c = Palette.c
	f.zoom.glyph:SetVertexColor(
		self.zoomed and c.accent[1] or c.textDim[1],
		self.zoomed and c.accent[2] or c.textDim[2],
		self.zoomed and c.accent[3] or c.textDim[3], 1)
end

function Reader:Restyle()
	local f = self.frame
	if not f then return end
	local c = Palette.c
	-- The same reading fill the library uses. The page itself is opaque, but the
	-- margin around it and the strip under it are not, and a border you can see
	-- the world through is a page that looks like it is floating.
	f:SetFillColor(Palette:ReadingFill())
	W.Color(f.title, c.textDim)
	W.Color(f.pager, c.textDim)
	for _, b in ipairs({ f.prev, f.next, f.close }) do
		b.glyph:SetVertexColor(c.textDim[1], c.textDim[2], c.textDim[3], 0.85)
	end
	if self.item then self:Paint() end
end

-- ---------------------------------------------------------------------------

function Reader:IsOpen()
	return self.frame ~= nil and self.frame:IsShown()
end

--- Open `item`, at the page it was left on.
function Reader:Open(item)
	if not item or item.type ~= "gossip" then return false end
	if not item.pages or #item.pages == 0 then return false end

	local f = self:Build()
	if not f then return false end

	self.item = item
	self.zoomed = nil

	-- WHERE IT WAS LEFT, and the back page starts again. A finished magazine
	-- reopened at its last page is a magazine you cannot re-read.
	local p = Content and Content:Progress(item.key)
	local at = (p and not p.complete and p.segment or 0) + 0
	if at < 1 or at > #item.pages then at = 1 end
	self.page = at

	self:Size()
	self:Fit()
	self:Paint()
	self:Remember()
	f:Show()
	f:Raise()
	return true
end

function Reader:Close()
	if self.frame then self.frame:Hide() end
	self.item = nil
end

--- Kept for the library, which shuts whatever it opened when it closes itself.
function Reader:CloseFor()
	self:Close()
	return true
end
