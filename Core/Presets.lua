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
Presets.order = { "classic", "centre", "corners" }

Presets.list = {
	classic = {
		label = "Classic corner",
		blurb = "Unit frames top-left, the way the game ships.",
		-- THE DEFAULT, and deliberately the one that changes least: somebody who
		-- has played this game before knows where to look, and a first run that
		-- moves their health bar somewhere new has spent its first decision
		-- making them hunt for it.
		anchors = {},
	},
	centre = {
		label = "Centre focus",
		blurb = "Frames hug the character, so your eyes stay in one place.",
		anchors = {},
	},
	corners = {
		label = "Bottom corners",
		blurb = "Frames flank the bars, keeping the middle of the screen clear.",
		anchors = {},
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
		if preset and self:Matches(preset.anchors, anchors) then return key end
	end
	return nil
end

--- Is every position in `want` the one `have` is currently at?
--
--  A preset names only what it moves - the shipped default is an empty table,
--  because "where the game puts them" is not a set of coordinates we own - so
--  a preset with nothing in it matches an untouched profile and nothing else.
function Presets:Matches(want, have)
	if type(want) ~= "table" or type(have) ~= "table" then return false end

	local named = 0
	for name, a in pairs(want) do
		named = named + 1
		local b = have[name]
		if not b then return false end
		if a.point ~= b.point or a.relPoint ~= b.relPoint then return false end
		if math.abs((a.x or 0) - (b.x or 0)) > 1 then return false end
		if math.abs((a.y or 0) - (b.y or 0)) > 1 then return false end
	end

	-- The empty preset is "untouched", so it matches only an untouched profile.
	if named == 0 then
		for _ in pairs(have) do return false end
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
	wipe(anchors)

	for name, a in pairs(preset.anchors) do
		anchors[name] = { point = a.point, relPoint = a.relPoint,
			x = a.x, y = a.y }
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
	local names = {}
	for name in pairs(anchors) do names[#names + 1] = name end
	table.sort(names)

	local out = {}
	out[#out + 1] = string.format("\t%s = {", key or "PRESET")
	out[#out + 1] = string.format("\t\tlabel = %q,", (self.list[key]
		and self.list[key].label) or "")
	out[#out + 1] = string.format("\t\tblurb = %q,", (self.list[key]
		and self.list[key].blurb) or "")
	out[#out + 1] = string.format("\t\tscale = %.2f,", A.db.profile.scale or 1)
	out[#out + 1] = "\t\tanchors = {"
	for _, name in ipairs(names) do
		local a = anchors[name]
		out[#out + 1] = string.format(
			"\t\t\t[%q] = { point = %q, relPoint = %q, x = %d, y = %d },",
			name, tostring(a.point), tostring(a.relPoint),
			math.floor((a.x or 0) + 0.5), math.floor((a.y or 0) + 0.5))
	end
	out[#out + 1] = "\t\t},"
	out[#out + 1] = "\t},"

	-- SPACES, and the list itself rather than one joined string. See above.
	for i, line in ipairs(out) do
		out[i] = line:gsub("\t", "    ")
	end
	return out, #names
end
