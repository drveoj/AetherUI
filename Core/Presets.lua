--[[--------------------------------------------------------------------------
	AetherUI :: Presets

	Three arrangements of the HUD, shipped, and the two things you do with one:
	apply it, or capture the one you have made into a form that can be shipped.

	A PRESET IS A LAYOUT STRING (Core/Layout.lua; Joe's decision 5). The same
	one line a player shares, so there is one format for an arrangement and one
	path that puts it on screen - Layout:Apply - whether it came from here or
	from somebody's paste. The string carries the HUD scale, which numbered bars
	are on (every other is switched off), and each node's place: hung from its
	parent, or from the screen, in units.

	THE NUMBERS ARE NOT WRITTEN BY HAND. An arrangement is a design decision made
	by eye, in the game, at a real resolution - so each of these was laid out in
	the game and read back with `/lattice preset capture`, which prints the
	string ready to paste in here. Guessing coordinates in a text editor is how
	you get a layout that is plausible in every dimension and right in none.

	THE THREE BELOW ARE 1.x's, converted to strings as they were - and then to
	the relative form (2026-10-08) by applying each with the code of the day on
	its capture screen and reading back the bonds it measured, so each still
	lands where it did. They predate the player-target spine, and two of them
	stretch it across the screen. Three
	arrangements designed for the spine replace them (decision 5): low and
	centred, hugging the character, and raised above the bars.

	WHAT A PRESET STILL DOES NOT TOUCH: any other module, colours, fonts, or
	anything else a player has chosen about behaviour.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local Presets = {}
A.Presets = Presets

Presets.order = { "corner", "centre", "bottom" }

-- CAPTURED, NOT WRITTEN. Each of these was laid out by eye in the game and read
-- back with a capture - never typed. `label` is what a player reads; `blurb`
-- is the line under the wireframe on the tour's card.
Presets.list = {
	corner = {
		-- OFFERED FIRST, and deliberately the one that surprises least:
		-- somebody who has played this game before knows where to look, and a
		-- first run that moves their health bar somewhere new has spent its
		-- first decision making them hunt for it.
		label = L.presets.set_bars.label,
		blurb = L.presets.set_bars.blurb,
		-- captured on a 2885 x 1202 screen
		layout = "LAT1;s=0.71;b=1;bar1=spine,BOTTOM,CENTER,-16,-452;bar2=screen,BOTTOM,BOTTOM,442,17;bar3=screen,BOTTOMRIGHT,BOTTOMRIGHT,-13,66;bar4=screen,BOTTOM,BOTTOM,444,127;bar5=screen,RIGHT,RIGHT,-4,-67;bar6=screen,RIGHT,RIGHT,-553,-219;barextra=bar1,BOTTOM,CENTER,470,-40;chat=screen,BOTTOMLEFT,BOTTOMLEFT,16,54;party=screen,LEFT,LEFT,66,76;pet=player,TOPLEFT,CENTER,-325,-192;player=screen,TOPLEFT,TOPLEFT,127,-80;quests=screen,TOPRIGHT,TOPRIGHT,-8,-330;target=player,LEFT,RIGHT,69,0;targettarget=target,TOPLEFT,CENTER,0,-192;tooltip=screen,TOPRIGHT,TOPRIGHT,-193,-17",
	},
	centre = {
		label = L.presets.set_bars.label2,
		blurb = L.presets.set_bars.blurb2,
		-- captured on a 2885 x 1202 screen
		layout = "LAT1;s=0.71;b=1,2;bar1=spine,BOTTOM,CENTER,495,-1073;bar2=spine,BOTTOM,CENTER,1378,-1073;bar3=screen,BOTTOMRIGHT,BOTTOMRIGHT,-13,66;bar4=screen,BOTTOM,BOTTOM,444,127;bar5=screen,RIGHT,RIGHT,-4,-67;bar6=screen,RIGHT,RIGHT,-553,-219;barextra=bar1,BOTTOMRIGHT,CENTER,1192,-37;chat=screen,BOTTOMLEFT,BOTTOMLEFT,16,54;pet=player,BOTTOMLEFT,CENTER,-547,-102;player=screen,CENTER,CENTER,-264,-143;quests=screen,TOPRIGHT,TOPRIGHT,-8,-330;target=player,LEFT,RIGHT,182,0;targettarget=target,BOTTOMRIGHT,CENTER,549,-102;tooltip=screen,TOPRIGHT,TOPRIGHT,-193,-17",
	},
	bottom = {
		label = L.presets.set_bars.label3,
		blurb = L.presets.set_bars.blurb3,
		-- captured on a 2885 x 1202 screen. The only one that places the music
		-- deck, which is why it is the only one naming `ifec`.
		layout = "LAT1;s=0.71;b=1,2;bar1=spine,BOTTOM,CENTER,1,-438;bar2=spine,BOTTOM,CENTER,1,-351;bar3=screen,BOTTOMRIGHT,BOTTOMRIGHT,-13,66;bar4=screen,BOTTOM,BOTTOM,444,127;bar5=screen,RIGHT,RIGHT,-4,-67;bar6=screen,RIGHT,RIGHT,-553,-219;barextra=bar1,BOTTOM,CENTER,-1,191;barpet=bar1,BOTTOM,CENTER,-1,136;chat=screen,TOPLEFT,TOPLEFT,26,-52;ifec=screen,BOTTOM,BOTTOM,0,394;party=screen,LEFT,LEFT,66,76;pet=player,BOTTOMLEFT,CENTER,-583,-33;player=screen,BOTTOMLEFT,BOTTOMLEFT,737,86;quests=screen,TOPRIGHT,TOPRIGHT,-8,-330;target=player,LEFT,RIGHT,721,0;targettarget=target,BOTTOMRIGHT,CENTER,618,-33;tooltip=screen,TOPRIGHT,TOPRIGHT,-193,-17",
	},
}

-- DECODED ONCE, here, and a shipped string that does not decode is a bug in
-- this file - so it is said, not swallowed. The tour's cards draw a thumbnail
-- from Layout:Resolve on the decoded string, so there is still only the one
-- source.
for key, preset in pairs(Presets.list) do
	local layout, err = A.Layout:Decode(preset.layout)
	if not layout then
		error(("preset %s does not decode: %s"):format(key, tostring(err)))
	end
	preset.decoded = layout
	preset.scale = layout.scale
	preset.bars = {}
	for id in pairs(layout.bars) do preset.bars[id] = true end
end

--- Which preset is on screen now, or nothing.
--
--  ANSWERED FROM THE STORE, not from a note somebody wrote down. A stored "you
--  picked centre" goes stale the first time a frame is dragged, and then the
--  tour re-opened would show a card ticked that no longer describes the screen.
function Presets:Current()
	for _, key in ipairs(self.order) do
		local preset = self.list[key]
		if preset and A.Layout:Matches(preset.decoded) then return key end
	end
	return nil
end

--- The preset a player typed, whatever case and whichever spelling of centre.
--
--  "center" and "centre" are the same word to whoever is typing it (Joe,
--  2026-10-08), so both are folded to one before comparing, anywhere in the
--  name, along with case.
local function Fold(s)
	return (tostring(s):lower():gsub("center", "centre"))
end

function Presets:Find(name)
	if type(name) ~= "string" or name == "" then return nil end
	if self.list[name] then return name end
	local want = Fold(name)
	for key in pairs(self.list) do
		if Fold(key) == want then return key end
	end
	return nil
end

--- Put an arrangement on screen, through the one path a pasted string takes.
function Presets:Apply(key)
	local preset = self.list[key]
	if not preset then return false end
	return (A.Layout:Apply(preset.decoded))
end

--- The current arrangement, as the bare readable string: the same thing the
--  layout box takes, so a capture can be pasted straight back in. Wrapping it
--  into a table here is for whoever puts it in this file.
--
--  Returns the string, how many nodes it places, and the screen it was made
--  on - an arrangement is a judgement made by eye at one aspect ratio, and a
--  block laid out across an ultrawide is wider in units than a 16:9 screen,
--  however it is anchored.
function Presets:Capture()
	local text = A.Layout:Encode()
	local count = 0
	for _ in text:gmatch(";[%w_]+=[%w_]+,") do count = count + 1 end
	local sw, sh = A.Layout.ScreenIn(A.db.profile.scale)
	return text, count, ("%d x %d"):format(math.floor(sw + 0.5), math.floor(sh + 0.5))
end
