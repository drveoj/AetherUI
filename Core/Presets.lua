--[[--------------------------------------------------------------------------
	AetherUI :: Presets

	Three arrangements of the HUD, shipped, and the two things you do with one:
	apply it, or capture the one you have made into a form that can be shipped.

	A PRESET IS ONE TABLE. Every frame this addon lets you move is registered
	with Core\Movers.lua, which writes `db.profile.anchors[name]` as
	{ point, relPoint, x, y } and nothing else. So an arrangement is a copy of
	that table, and applying one is writing it back and telling the movers to
	look again. There is no second mechanism here and no second place a position
	can live - which is the whole reason this is small.

	THE NUMBERS ARE NOT WRITTEN BY HAND. An arrangement is a design decision made
	by eye, in the game, at a real resolution - so the three below were captured
	from a profile somebody had actually laid out. `/aether preset capture` is
	how: it prints the current profile's anchors as a Lua table ready to paste in
	here. Guessing coordinates in a text editor is how you get a layout that is
	plausible in every dimension and right in none.

	AND THE NUMBERS ARE FRACTIONS OF THE SCREEN, not pixels.

	An arrangement made on a 3840x1600 monitor and shipped in pixels is an
	arrangement for that monitor. The client's UI is 768 units tall whatever the
	display - so the vertical numbers carry over untouched - but its WIDTH is
	768 x the aspect ratio: 1843 units on a 2.4:1 ultrawide and 1365 on a
	16:9 1920x1080. A frame placed 596 units in from the left edge is a third
	of the way across one screen and nearly half way across the other, and a
	"bottom corners" layout quietly becomes "bottom middle".

	So a preset stores `fx` and `fy`: where the frame sits as a fraction of
	UIParent, and Apply multiplies them by the screen actually in front of the
	player. `x` and `y` are still read if a preset has them, because a hand
	written one is easier to reason about in units - but nothing captured is
	written that way.

	SCALE TRAVELS WITH THE LAYOUT. Frames hugging the character want to be
	smaller than frames along the bottom of an ultrawide, and a preset that moved
	everything and left the size alone would be half an arrangement.

	WHAT A PRESET DOES NOT TOUCH: which modules are on, colours, fonts, or
	anything a player has chosen about behaviour. It is where things are, and
	that is all it is.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Presets = {}
A.Presets = Presets

--- The shipped arrangements, in the order they are offered.
--
--  `key` is what is stored and what the tour passes about; `label` is what a
--  player reads and is the design's own wording. `blurb` is the one line under
--  the wireframe on the tour's card.
--- UIParent's size, in the units an anchor offset is written in.
--
--  A SetPoint offset is in the FRAME's own coordinate space, and every frame
--  this addon draws is at `db.profile.scale` - so an offset of 100 on a 0.71
--  frame moves it 71 UIParent units. Dividing the screen by that same scale
--  puts both sides of the sum in one space.
--
--  Which also means the scale cancels: a preset carries its own scale and Apply
--  sets it, so the fraction captured on one machine is the fraction applied on
--  the next.
local function ScreenIn(scale)
	scale = (type(scale) == "number" and scale > 0) and scale or 1
	local w = (UIParent and UIParent:GetWidth()) or 0
	local h = (UIParent and UIParent:GetHeight()) or 0
	if w <= 0 or h <= 0 then return 0, 0 end
	return w / scale, h / scale
end

--- One stored anchor, resolved against the screen that is actually here.
--
--  `fx`/`fy` are fractions of UIParent and are what a capture writes. `x`/`y`
--  are units and are what a hand written preset may still say; they are taken
--  as-is, which is right for one written for this display and wrong for one
--  copied off somebody else's - hence the capture.
local function Resolve(a, scale)
	local sw, sh = ScreenIn(scale)
	local x = a.x
	local y = a.y
	if a.fx and sw > 0 then x = a.fx * sw end
	if a.fy and sh > 0 then y = a.fy * sh end
	return {
		point = a.point, relPoint = a.relPoint,
		x = math.floor((x or 0) + 0.5), y = math.floor((y or 0) + 0.5),
	}
end

Presets.order = { "corner", "centre", "bottom" }

-- STILL IN UNITS, not fractions. These three were laid out by eye on a
-- 3840x1600 display and pasted in as captured, so they are right on that
-- display and approximately right elsewhere. Converting them here would mean
-- guessing what UIParent measured at the time; re-capturing them does not.
-- Apply each, run `/aether preset capture <name>`, paste the answer back.
Presets.list = {
	corner = {
		label = "Classic Corner",
		blurb = "Unitframes in the top left corner as they're laid out in the classic UI.",
		scale = 0.71,
		-- OFFERED FIRST, and deliberately the one that surprises least:
		-- somebody who has played this game before knows where to look, and a
		-- first run that moves their health bar somewhere new has spent its
		-- first decision making them hunt for it.
		anchors = {
			["bar1"] = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 20 },
			["bar2"] = { point = "BOTTOM", relPoint = "BOTTOM", x = 442, y = 17 },
			["bar3"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -13, y = 66 },
			["bar4"] = { point = "BOTTOM", relPoint = "BOTTOM", x = 444, y = 127 },
			["bar5"] = { point = "RIGHT", relPoint = "RIGHT", x = -4, y = -67 },
			["bar6"] = { point = "RIGHT", relPoint = "RIGHT", x = -553, y = -219 },
			["barextra"] = { point = "BOTTOM", relPoint = "BOTTOM", x = 471, y = 17 },
			["cast"] = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 42, y = -214 },
			["chat"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 16, y = 54 },
			["party"] = { point = "LEFT", relPoint = "LEFT", x = 66, y = 76 },
			["pet"] = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 27, y = -324 },
			["player"] = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 127, y = -80 },
			["quests"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -8, y = -330 },
			["target"] = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 541, y = -80 },
			["targetcast"] = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 541, y = -214 },
			["targettarget"] = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 839, y = -324 },
			["tooltip"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -193, y = -17 },
		},
	},

	centre = {
		label = "Centre focus",
		blurb = "Unitframes in the center where most of the action is.",
		scale = 0.71,
		-- No party and no player frame for the music deck: neither was placed
		-- when this was laid out, so both keep the position their own module
		-- ships with. A preset names what it moves.
		anchors = {
			["bar1"] = { point = "BOTTOM", relPoint = "BOTTOM", x = -441, y = 17 },
			["bar2"] = { point = "BOTTOM", relPoint = "BOTTOM", x = 442, y = 17 },
			["bar3"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -13, y = 66 },
			["bar4"] = { point = "BOTTOM", relPoint = "BOTTOM", x = 444, y = 127 },
			["bar5"] = { point = "RIGHT", relPoint = "RIGHT", x = -4, y = -67 },
			["bar6"] = { point = "RIGHT", relPoint = "RIGHT", x = -553, y = -219 },
			["barextra"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -692, y = 17 },
			["cast"] = { point = "CENTER", relPoint = "CENTER", x = -306, y = -22 },
			["chat"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 16, y = 54 },
			["pet"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 839, y = 437 },
			["player"] = { point = "CENTER", relPoint = "CENTER", x = -264, y = -143 },
			["quests"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -8, y = -330 },
			["target"] = { point = "CENTER", relPoint = "CENTER", x = 263, y = -143 },
			["targetcast"] = { point = "CENTER", relPoint = "CENTER", x = 305, y = -24 },
			["targettarget"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -839, y = 437 },
			["tooltip"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -193, y = -17 },
		},
	},

	bottom = {
		label = "Bottom Corners",
		blurb = "Unitframes positioned towards the bottom and out to the corners.",
		scale = 0.71,
		anchors = {
			["bar1"] = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 20 },
			["bar2"] = { point = "BOTTOM", relPoint = "BOTTOM", x = 442, y = 17 },
			["bar3"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -13, y = 66 },
			["bar4"] = { point = "BOTTOM", relPoint = "BOTTOM", x = 444, y = 127 },
			["bar5"] = { point = "RIGHT", relPoint = "RIGHT", x = -4, y = -67 },
			["bar6"] = { point = "RIGHT", relPoint = "RIGHT", x = -553, y = -219 },
			["barextra"] = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 187 },
			["cast"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 737, y = 242 },
			["chat"] = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 26, y = -52 },
			["ifec"] = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 394 },
			["party"] = { point = "LEFT", relPoint = "LEFT", x = 66, y = 76 },
			["pet"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 487, y = 106 },
			["player"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 737, y = 86 },
			["quests"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -8, y = -330 },
			["target"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -737, y = 86 },
			["targetcast"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -742, y = 242 },
			["targettarget"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -452, y = 106 },
			["tooltip"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -193, y = -17 },
		},
	},
}
--- Which preset is closest to what is on screen, or nothing.
--
--  ANSWERED FROM THE ANCHORS, not from a note somebody wrote down. A stored
--  "you picked centre" goes stale the first time a frame is dragged, and then
--  the tour re-opened would show a card ticked that no longer describes the
--  screen. There is one source of truth for where things are, and this reads it.
function Presets:Current()
	local anchors = A.db and A.db.profile and A.db.profile.anchors
	if not anchors then return nil end

	for _, key in ipairs(self.order) do
		local preset = self.list[key]
		if preset and self:Matches(preset.anchors, anchors, preset.scale) then
			return key
		end
	end
	return nil
end

--- Is every position in `want` the one `have` is currently at?
--
--  A preset names only what it moves - the shipped default is an empty table,
--  because "where the game puts them" is not a set of coordinates we own - so
--  a preset with nothing in it matches an untouched profile and nothing else.
--  AND COMPARED IN UNITS. `want` is in fractions of the screen and `have` is
--  what the movers wrote, which is units - so the fractions are resolved
--  against the screen that is here before anything is compared. Comparing the
--  two directly makes every preset read as "not this one" on every display.
function Presets:Matches(want, have, scale)
	if type(want) ~= "table" or type(have) ~= "table" then return false end

	local named = 0
	for name, raw in pairs(want) do
		named = named + 1
		local a = Resolve(raw, scale)
		local b = have[name]
		if not b then return false end
		if a.point ~= b.point or a.relPoint ~= b.relPoint then return false end
		if math.abs((a.x or 0) - (b.x or 0)) > 1 then return false end
		if math.abs((a.y or 0) - (b.y or 0)) > 1 then return false end
	end

	-- The empty preset is "untouched", so it matches only an untouched profile -
	-- and the lock button being somewhere does not make a profile touched.
	if named == 0 then
		for name in pairs(have) do
			if not tostring(name):find("^__") then return false end
		end
	end
	return true
end

--- Put an arrangement on screen.
--
--  WIPED, NOT MERGED. A preset is a whole arrangement, and merging one over
--  another leaves whatever the previous one moved that this one does not
--  mention - which is two layouts at once and belongs to neither.
function Presets:Apply(key)
	local preset = self.list[key]
	if not preset or not A.db then return false end

	local anchors = A.db.profile.anchors
	if type(anchors) ~= "table" then
		anchors = {}
		A.db.profile.anchors = anchors
	end
	-- EXCEPT THE ONES THAT ARE NOT POSITIONS. `__lockButton` is where the
	-- player shoved the button that hides the handles; no arrangement has an
	-- opinion about it, so wiping it puts that button back in the middle of
	-- the screen every time somebody tries a preset on.
	local keep = {}
	for name, a in pairs(anchors) do
		if tostring(name):find("^__") then keep[name] = a end
	end
	wipe(anchors)
	for name, a in pairs(keep) do anchors[name] = a end

	-- RESOLVED AGAINST THIS SCREEN. The stored numbers are fractions of
	-- UIParent; what the movers read is units. See the file header.
	--
	-- The preset's own scale, not the profile's, because the profile's is
	-- about to become the preset's two lines down - and resolving against
	-- the scale on the way out puts every frame in the wrong place by the
	-- ratio between them.
	local scale = preset.scale or A.db.profile.scale
	for name, a in pairs(preset.anchors) do
		anchors[name] = Resolve(a, scale)
	end

	if preset.scale then A.db.profile.scale = preset.scale end

	-- AND EVERY FRAME LOOKS AGAIN. The movers put a frame back from the store on
	-- demand rather than watching it, so writing the table is only half of it.
	if A.Movers and A.Movers.RestoreAll then A.Movers:RestoreAll() end
	A:Reconfigure()
	return true
end

--- The current arrangement, as a Lua table ready to paste into this file.
--
--  The other half of "the numbers are not written by hand": lay the frames out
--  in the game, run this, and the answer is the thing you paste.
--
--  A LIST OF LINES, not one string with newlines in it. The copy box is fed
--  through Errors:Capture, which collects what goes to the chat frame - the
--  same path the panel dump uses and the only one known to arrive whole.
--
--  AND INDENTED WITH SPACES. A tab is not reliably carried through a chat
--  frame and out through the clipboard, and this text exists to be pasted.
function Presets:Capture(key)
	local anchors = A.db and A.db.profile and A.db.profile.anchors or {}

	-- SORTED, so two captures of the same layout are the same text. An
	-- unsorted pairs() walk makes every capture a different diff and hides the
	-- one line that really changed.
	-- THE LOCK BUTTON IS NOT PART OF AN ARRANGEMENT. It is the button that
	-- hides the handles, parked wherever it was last shoved out of the way -
	-- Movers keeps its spot in this same table under `__lockButton` precisely
	-- because it is NOT a mover entry. Capturing it would ship one player's
	-- idea of where that button goes to everybody, and would make Current()
	-- stop recognising its own preset the moment somebody dragged it.
	local names = {}
	for name in pairs(anchors) do
		if not tostring(name):find("^__") then names[#names + 1] = name end
	end
	table.sort(names)

	local out = {}
	out[#out + 1] = string.format("\t%s = {", key or "PRESET")
	out[#out + 1] = string.format("\t\tlabel = %q,", (self.list[key]
		and self.list[key].label) or "")
	out[#out + 1] = string.format("\t\tblurb = %q,", (self.list[key]
		and self.list[key].blurb) or "")
	out[#out + 1] = string.format("\t\tscale = %.2f,", A.db.profile.scale or 1)
	-- WHAT IT WAS MADE ON, written down. An arrangement is a judgement made by
	-- eye at one aspect ratio, and the fractions below say where things went
	-- but not whether they still compose at 16:9. This is the line that tells
	-- somebody reading the diff which question is still open.
	local sw, sh = ScreenIn(A.db.profile.scale)
	out[#out + 1] = string.format("\t\t-- captured on a %d x %d screen",
		math.floor(sw + 0.5), math.floor(sh + 0.5))
	out[#out + 1] = "\t\tanchors = {"
	for _, name in ipairs(names) do
		local a = anchors[name]
		-- FRACTIONS OF THE SCREEN, not units. See the file header: the
		-- client's UI is 768 tall on every display and its width is not, so
		-- a layout shipped in units is a layout for one monitor.
		--
		-- Five places. A frame is placed to about a unit and the screen is
		-- around two thousand of them wide, so four is visibly coarse and
		-- six is noise in the diff.
		out[#out + 1] = string.format(
			"\t\t\t[%q] = { point = %q, relPoint = %q, fx = %.5f, fy = %.5f },",
			name, tostring(a.point), tostring(a.relPoint),
			sw > 0 and ((a.x or 0) / sw) or 0,
			sh > 0 and ((a.y or 0) / sh) or 0)
	end
	out[#out + 1] = "\t\t},"
	out[#out + 1] = "\t},"

	-- SPACES, and the list itself rather than one joined string. See above.
	for i, line in ipairs(out) do
		out[i] = line:gsub("\t", "    ")
	end
	return out, #names
end
