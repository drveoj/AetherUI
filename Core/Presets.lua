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
	arrangement for that monitor. UIParent is measured in UI units, and how many
	of them there are depends on BOTH the aspect ratio and the player's UI Scale
	slider: the capture these three came from reports 2885 x 1202 in the units a
	preset is written in, and 768-tall is only what you get at the default scale.

	So neither axis can be assumed. A frame placed 596 units in from the left
	edge is a third of the way across one screen and nearly half way across
	another, and a "bottom corners" layout quietly becomes "bottom middle".

	So a preset stores `fx` and `fy`: where the frame sits as a fraction of
	UIParent, and Apply multiplies them by the screen actually in front of the
	player. `x` and `y` are still read if a preset has them, because a hand
	written one is easier to reason about in units - but nothing captured is
	written that way.

	SCALE TRAVELS WITH THE LAYOUT. Frames hugging the character want to be
	smaller than frames along the bottom of an ultrawide, and a preset that moved
	everything and left the size alone would be half an arrangement.

	AND IT OWNS THE ACTION BARS, on and off both.

	An arrangement that places bar 5 on a profile where bar 5 is switched off
	places nothing, and a layout designed around six bars has a hole in it with
	two. So a preset records which of the six numbered bars are on and sets them
	exactly - a bar it does not use is switched OFF, because leaving one on where
	the last arrangement put it is two layouts at once, which is the same reason
	the anchors are wiped rather than merged.

	THE SIX NUMBERED BARS AND NOTHING ELSE. The stance, pet, taxi and extra-action
	bars are not layout choices - the game gives you one or it does not, by class
	and by circumstance - and a preset captured by a mage that switched off a
	druid's stance bar would be reaching well past where things go.

	WHAT A PRESET STILL DOES NOT TOUCH: any other module, colours, fonts, or
	anything else a player has chosen about behaviour.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
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

--- The six numbered action bars, and nothing else. See the file header.
local BARS = { "1", "2", "3", "4", "5", "6" }

--- Which of them are on, as the profile has it now.
local function BarsNow()
	local AB = A.GetModule and A:GetModule("actionbars")
	if not AB or not AB.BarConfig then return nil end

	local out = {}
	for _, id in ipairs(BARS) do
		local cfg = AB:BarConfig(id)
		if cfg then out[id] = cfg.enabled and true or false end
	end
	return out
end

--- Set them, and rebuild once rather than once per bar.
--
--  ONE REBUILD. SetBarEnabled is the per-bar door and it calls OnConfigChanged
--  itself, so six of them is six teardowns of every button on the screen for
--  one click.
local function SetBars(want)
	local AB = A.GetModule and A:GetModule("actionbars")
	if not AB or not AB.BarConfig or type(want) ~= "table" then return end

	local changed = false
	for _, id in ipairs(BARS) do
		local on = want[id]
		if on ~= nil then
			local cfg = AB:BarConfig(id)
			if cfg and (cfg.enabled and true or false) ~= (on and true or false) then
				cfg.enabled = on and true or false
				changed = true
			end
		end
	end
	if changed and AB.OnConfigChanged then AB:OnConfigChanged() end
end

Presets.order = { "corner", "centre", "bottom" }

-- CAPTURED, NOT WRITTEN. Each of these was laid out by eye in the game and
-- read back out with `/aether preset capture`, which is the only way the
-- numbers are ever produced - guessing coordinates in a text editor gives a
-- layout that is plausible in every dimension and right in none.
Presets.list = {
	corner = {
		-- OFFERED FIRST, and deliberately the one that surprises least:
		-- somebody who has played this game before knows where to look, and a
		-- first run that moves their health bar somewhere new has spent its
		-- first decision making them hunt for it.
		label = L.presets.set_bars.label,
		blurb = L.presets.set_bars.blurb,
		scale = 0.71,
		bars = { ["1"] = true, ["2"] = false, ["3"] = false, ["4"] = false, ["5"] = false, ["6"] = false },
		-- captured on a 2885 x 1202 screen
		anchors = {
			["bar1"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.00000, fy = 0.01664 },
			["bar2"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.15323, fy = 0.01414 },
			["bar3"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", fx = -0.00451, fy = 0.05491 },
			["bar4"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.15393, fy = 0.10567 },
			["bar5"] = { point = "RIGHT", relPoint = "RIGHT", fx = -0.00139, fy = -0.05575 },
			["bar6"] = { point = "RIGHT", relPoint = "RIGHT", fx = -0.19171, fy = -0.18221 },
			["barextra"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.16329, fy = 0.01414 },
			["cast"] = { point = "TOPLEFT", relPoint = "TOPLEFT", fx = 0.01456, fy = -0.17805 },
			["chat"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", fx = 0.00555, fy = 0.04493 },
			["party"] = { point = "LEFT", relPoint = "LEFT", fx = 0.02288, fy = 0.06323 },
			["pet"] = { point = "TOPLEFT", relPoint = "TOPLEFT", fx = 0.00936, fy = -0.26958 },
			["player"] = { point = "TOPLEFT", relPoint = "TOPLEFT", fx = 0.04403, fy = -0.06656 },
			["quests"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", fx = -0.00277, fy = -0.27457 },
			["target"] = { point = "TOPLEFT", relPoint = "TOPLEFT", fx = 0.18755, fy = -0.06656 },
			["targetcast"] = { point = "TOPLEFT", relPoint = "TOPLEFT", fx = 0.18755, fy = -0.17805 },
			["targettarget"] = { point = "TOPLEFT", relPoint = "TOPLEFT", fx = 0.29086, fy = -0.26958 },
			["tooltip"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", fx = -0.06691, fy = -0.01414 },
		},
	},
	centre = {
		label = L.presets.set_bars.label2,
		blurb = L.presets.set_bars.blurb2,
		scale = 0.71,
		bars = { ["1"] = true, ["2"] = true, ["3"] = false, ["4"] = false, ["5"] = false, ["6"] = false },
		-- captured on a 2885 x 1202 screen
		anchors = {
			["bar1"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = -0.15289, fy = 0.01414 },
			["bar2"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.15323, fy = 0.01414 },
			["bar3"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", fx = -0.00451, fy = 0.05491 },
			["bar4"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.15393, fy = 0.10567 },
			["bar5"] = { point = "RIGHT", relPoint = "RIGHT", fx = -0.00139, fy = -0.05575 },
			["bar6"] = { point = "RIGHT", relPoint = "RIGHT", fx = -0.19171, fy = -0.18221 },
			["barextra"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", fx = -0.23990, fy = 0.01414 },
			["cast"] = { point = "CENTER", relPoint = "CENTER", fx = -0.10608, fy = -0.01830 },
			["chat"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", fx = 0.00555, fy = 0.04493 },
			["pet"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", fx = 0.29086, fy = 0.36360 },
			["player"] = { point = "CENTER", relPoint = "CENTER", fx = -0.09152, fy = -0.11898 },
			["quests"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", fx = -0.00277, fy = -0.27457 },
			["target"] = { point = "CENTER", relPoint = "CENTER", fx = 0.09118, fy = -0.11898 },
			["targetcast"] = { point = "CENTER", relPoint = "CENTER", fx = 0.10574, fy = -0.01997 },
			["targettarget"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", fx = -0.29086, fy = 0.36360 },
			["tooltip"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", fx = -0.06691, fy = -0.01414 },
		},
	},
	bottom = {
		-- The only one that places the music deck, which is why it is the only
		-- one with an `ifec` line. A preset names what it moves.
		label = L.presets.set_bars.label3,
		blurb = L.presets.set_bars.blurb3,
		scale = 0.71,
		bars = { ["1"] = true, ["2"] = true, ["3"] = false, ["4"] = false, ["5"] = false, ["6"] = false },
		-- captured on a 2885 x 1202 screen
		anchors = {
			["bar1"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.00000, fy = 0.01664 },
			["bar2"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.00000, fy = 0.08903 },
			["bar3"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", fx = -0.00451, fy = 0.05491 },
			["bar4"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.15393, fy = 0.10567 },
			["bar5"] = { point = "RIGHT", relPoint = "RIGHT", fx = -0.00139, fy = -0.05575 },
			["bar6"] = { point = "RIGHT", relPoint = "RIGHT", fx = -0.19171, fy = -0.18221 },
			["barextra"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.00000, fy = 0.20634 },
			["barpet"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.00000, fy = 0.17223 },
			["cast"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", fx = 0.25550, fy = 0.20135 },
			["chat"] = { point = "TOPLEFT", relPoint = "TOPLEFT", fx = 0.00901, fy = -0.04327 },
			["ifec"] = { point = "BOTTOM", relPoint = "BOTTOM", fx = 0.00000, fy = 0.32782 },
			["party"] = { point = "LEFT", relPoint = "LEFT", fx = 0.02288, fy = 0.06323 },
			["pet"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", fx = 0.16883, fy = 0.08820 },
			["player"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", fx = 0.25550, fy = 0.07155 },
			["quests"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", fx = -0.00277, fy = -0.27457 },
			["target"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", fx = -0.25550, fy = 0.07155 },
			["targetcast"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", fx = -0.25724, fy = 0.20135 },
			["targettarget"] = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", fx = -0.15670, fy = 0.08820 },
			["tooltip"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", fx = -0.06691, fy = -0.01414 },
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
		if preset and self:Matches(preset.anchors, anchors, preset.scale)
			and self:BarsMatch(preset.bars) then
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

--- Are the action bars switched the way this preset wants them?
--
--  PART OF THE ARRANGEMENT, so part of the question. Two presets that place the
--  same frames and differ only in how many bars are under them are two different
--  layouts, and one that answered "yes, this is the one you have" while three of
--  its bars were missing would be telling the player something plainly untrue.
function Presets:BarsMatch(want)
	if type(want) ~= "table" then return true end
	local now = BarsNow()
	if not now then return true end

	for id, on in pairs(want) do
		if now[id] ~= nil and now[id] ~= (on and true or false) then return false end
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
	-- THE BARS FIRST, because a bar that is switched off has no frame and no
	-- mover registered - so anchors written before it is on are anchors for
	-- something that is not there yet, and RestoreAll walks straight past it.
	SetBars(preset.bars)

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

	-- AND WHICH BARS ARE UNDER IT. An arrangement designed around six has a
	-- hole in it with two, and one that places bar 5 on a profile where bar 5
	-- is off places nothing at all.
	local bars = BarsNow()
	if bars then
		local on = {}
		for _, id in ipairs(BARS) do
			on[#on + 1] = string.format("[%q] = %s", id,
				bars[id] and "true" or "false")
		end
		out[#out + 1] = "\t\tbars = { " .. table.concat(on, ", ") .. " },"
	end
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
