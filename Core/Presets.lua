--[[--------------------------------------------------------------------------
	AetherUI :: Presets

	Three arrangements of the HUD, shipped, and the two things you do with one:
	apply it, or capture the one you have made into a form that can be shipped.

	A PRESET IS A LAYOUT STRING (Core/Layout.lua; Joe's decision 5). The same
	one line a player shares, so there is one format for an arrangement and one
	path that puts it on screen - Layout:Apply - whether it came from here or
	from somebody's paste. The string carries the HUD scale, which numbered bars
	are on (every other is switched off), and each node's place: on the screen
	as fractions of it, or bonded to its parent in its own units.

	THE NUMBERS ARE NOT WRITTEN BY HAND. An arrangement is a design decision made
	by eye, in the game, at a real resolution - so each of these was laid out in
	the game and read back with `/lattice preset capture`, which prints the
	string ready to paste in here. Guessing coordinates in a text editor is how
	you get a layout that is plausible in every dimension and right in none.

	THE THREE BELOW ARE 1.x's, converted to strings as they were. They predate
	the player-target spine, and two of them stretch it across the screen. Three
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
		layout = "LAT1;s=0.71;b=1;bar1=S,BOTTOM,BOTTOM,0.00000,0.01664;bar2=S,BOTTOM,BOTTOM,0.15323,0.01414;bar3=S,BOTTOMRIGHT,BOTTOMRIGHT,-0.00451,0.05491;bar4=S,BOTTOM,BOTTOM,0.15393,0.10567;bar5=S,RIGHT,RIGHT,-0.00139,-0.05575;bar6=S,RIGHT,RIGHT,-0.19171,-0.18221;barextra=S,BOTTOM,BOTTOM,0.16329,0.01414;chat=S,BOTTOMLEFT,BOTTOMLEFT,0.00555,0.04493;party=S,LEFT,LEFT,0.02288,0.06323;pet=S,TOPLEFT,TOPLEFT,0.00936,-0.26958;player=S,TOPLEFT,TOPLEFT,0.04403,-0.06656;quests=S,TOPRIGHT,TOPRIGHT,-0.00277,-0.27457;target=S,TOPLEFT,TOPLEFT,0.18755,-0.06656;targettarget=S,TOPLEFT,TOPLEFT,0.29086,-0.26958;tooltip=S,TOPRIGHT,TOPRIGHT,-0.06691,-0.01414",
	},
	centre = {
		label = L.presets.set_bars.label2,
		blurb = L.presets.set_bars.blurb2,
		-- captured on a 2885 x 1202 screen
		layout = "LAT1;s=0.71;b=1,2;bar1=S,BOTTOM,BOTTOM,-0.15289,0.01414;bar2=S,BOTTOM,BOTTOM,0.15323,0.01414;bar3=S,BOTTOMRIGHT,BOTTOMRIGHT,-0.00451,0.05491;bar4=S,BOTTOM,BOTTOM,0.15393,0.10567;bar5=S,RIGHT,RIGHT,-0.00139,-0.05575;bar6=S,RIGHT,RIGHT,-0.19171,-0.18221;barextra=S,BOTTOMRIGHT,BOTTOMRIGHT,-0.23990,0.01414;chat=S,BOTTOMLEFT,BOTTOMLEFT,0.00555,0.04493;pet=S,BOTTOMLEFT,BOTTOMLEFT,0.29086,0.36360;player=S,CENTER,CENTER,-0.09152,-0.11898;quests=S,TOPRIGHT,TOPRIGHT,-0.00277,-0.27457;target=S,CENTER,CENTER,0.09118,-0.11898;targettarget=S,BOTTOMRIGHT,BOTTOMRIGHT,-0.29086,0.36360;tooltip=S,TOPRIGHT,TOPRIGHT,-0.06691,-0.01414",
	},
	bottom = {
		label = L.presets.set_bars.label3,
		blurb = L.presets.set_bars.blurb3,
		-- captured on a 2885 x 1202 screen. The only one that places the music
		-- deck, which is why it is the only one naming `ifec`.
		layout = "LAT1;s=0.71;b=1,2;bar1=S,BOTTOM,BOTTOM,0.00000,0.01664;bar2=S,BOTTOM,BOTTOM,0.00000,0.08903;bar3=S,BOTTOMRIGHT,BOTTOMRIGHT,-0.00451,0.05491;bar4=S,BOTTOM,BOTTOM,0.15393,0.10567;bar5=S,RIGHT,RIGHT,-0.00139,-0.05575;bar6=S,RIGHT,RIGHT,-0.19171,-0.18221;barextra=S,BOTTOM,BOTTOM,0.00000,0.20634;barpet=S,BOTTOM,BOTTOM,0.00000,0.17223;chat=S,TOPLEFT,TOPLEFT,0.00901,-0.04327;ifec=S,BOTTOM,BOTTOM,0.00000,0.32782;party=S,LEFT,LEFT,0.02288,0.06323;pet=S,BOTTOMLEFT,BOTTOMLEFT,0.16883,0.08820;player=S,BOTTOMLEFT,BOTTOMLEFT,0.25550,0.07155;quests=S,TOPRIGHT,TOPRIGHT,-0.00277,-0.27457;target=S,BOTTOMRIGHT,BOTTOMRIGHT,-0.25550,0.07155;targettarget=S,BOTTOMRIGHT,BOTTOMRIGHT,-0.15670,0.08820;tooltip=S,TOPRIGHT,TOPRIGHT,-0.06691,-0.01414",
	},
}

-- DECODED ONCE, here, and a shipped string that does not decode is a bug in
-- this file - so it is said, not swallowed. The tour's cards draw a thumbnail
-- from `anchors` and `bars`, which are read off the decoded string so there is
-- still only the one source.
for key, preset in pairs(Presets.list) do
	local layout, err = A.Layout:Decode(preset.layout)
	if not layout then
		error(("preset %s does not decode: %s"):format(key, tostring(err)))
	end
	preset.decoded = layout
	preset.scale = layout.scale
	preset.anchors, preset.bars = {}, {}
	for name, r in pairs(layout.records) do
		if r.kind == "S" then
			preset.anchors[name] = { point = r.point, relPoint = r.relPoint, fx = r.fx, fy = r.fy }
		end
	end
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

--- Put an arrangement on screen, through the one path a pasted string takes.
function Presets:Apply(key)
	local preset = self.list[key]
	if not preset then return false end
	return (A.Layout:Apply(preset.decoded))
end

--- The current arrangement, as the line to paste into this file.
--
--  A LIST OF LINES, because the copy box is fed through Errors:Capture, which
--  collects what goes to the chat frame - the same path the panel dump uses.
--  AND INDENTED WITH SPACES: a tab is not reliably carried through a chat frame
--  and out through the clipboard, and this text exists to be pasted.
function Presets:Capture(key)
	local text = A.Layout:Encode()
	local count = 0
	for _ in text:gmatch(";[%w_]+=[SB],") do count = count + 1 end
	-- WHAT IT WAS MADE ON, written down. An arrangement is a judgement made by
	-- eye at one aspect ratio, and the fractions say where things went but not
	-- whether they still compose at 16:9.
	local sw, sh = A.Layout.ScreenIn(A.db.profile.scale)
	local out = {
		("    %s = {"):format(key or "PRESET"),
		("        -- captured on a %d x %d screen"):format(math.floor(sw + 0.5), math.floor(sh + 0.5)),
		("        layout = %q,"):format(text),
		"    },",
	}
	return out, count
end
