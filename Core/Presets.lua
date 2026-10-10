--[[--------------------------------------------------------------------------
	AetherUI :: Presets

	The shipped arrangements of the HUD, and the two things you do with one:
	apply it, or capture the one you have made into a form that can be shipped.

	A PRESET IS A LAYOUT STRING (Core/Layout.lua; Joe's decision 5). The same
	one line a player shares, so there is one format for an arrangement and one
	path that puts it on screen - Layout:Apply - whether it came from here or
	from somebody's paste. The string carries which numbered bars are on (every
	other is switched off) and each node's place: hung from its parent, or from
	the screen, in HUD units. Never the HUD scale, which is the player's.

	THE NUMBERS COME FROM A DESIGN OR A CAPTURE, NEVER A GUESS. An arrangement
	laid out by eye in the game is read back with `/lattice preset capture`,
	which gives the string ready to paste in here. One taken from the design is
	worked out from the board's own pixels and then applied in the harness at
	the board's resolution, and every frame read back against the board.
	Coordinates typed in a text editor give a layout that is plausible in every
	dimension and right in none.

	THE DESIGN'S WAY (Joe, 2026-10-08): no whole-HUD presets to choose between,
	but the one reference layout of the Lattice handoff and the bar seeds of
	onboarding stop 3 - Rows, Block, Split. The reference IS the Rows seed: the
	strands brief makes the handoff's bar positions the defaults of Rows. The
	three 1.x arrangements (corner, centre, bottom) are gone.

	WHAT A PRESET STILL DOES NOT TOUCH: the HUD scale, any other module,
	colours, fonts, or anything else a player has chosen about behaviour.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local Presets = {}
A.Presets = Presets

Presets.order = { "rows", "block", "split" }

-- `label` is what a player reads; `blurb` is the line under the wireframe on
-- the tour's card.
Presets.list = {
	rows = {
		label = L.presets.rows.label,
		blurb = L.presets.rows.blurb,
		-- FROM THE BOARD: Lattice handoff 3a at 1920 x 1080. Every offset in HUD
		-- units, which at the scale fitted to the monitor is a pixel on any
		-- screen, whatever the player's bar size or pet and ToT scales. No
		-- scale: that is the player's. The spine on the screen's centre line,
		-- bond 216; bar 1 12 x 44 with its top at y 968, bar 2 12 x 34 at
		-- y 1032, both hung from the spine's middle; ToT over the target's
		-- right edge at y 760; chat's glass 24 / 24 from the bottom left. The
		-- party at 210, 400, not the board's 60, 420: at 60 it sat under the
		-- Toolbox trunk's stubs and labels (6a draws the trunk and no party),
		-- and 20 higher it clears the pet's slot over the player.
		-- Chat's size is in its own units, which its text and its smallest
		-- size are in: 210 x 120, so its glass clears the stance bar at 1080.
		-- Its size travels with it, or a wider window runs under the stance bar
		-- and the player.
		-- The minimap in the top-right corner, its disc one field unit (24)
		-- clear of both edges plus its rim: centre 124 in and 124 down (Joe,
		-- 2026-10-10, over 6a's 110, 230, which sat it too low). The World
		-- trunk under its pill. Hung by its centre, so the disc's size does
		-- not move it. The tracker is the trunk now; old
		-- strings naming `quests` still load, and it places nothing.
		-- Where the board and this addon differ:
		--   the capsules are 345 x 64, not 332 x 60, so the bond and the
		--   centre line are kept rather than the board's x;
		--   there is no focus frame, and the pet capsule is too tall for the
		--   strip under the player, so the pet takes the focus slot above it,
		--   mirroring the ToT;
		--   the stance, pet and extra bars hang from BAR 1, not from the player
		--   and the pet as the strands brief has it: actions are bonded to
		--   actions (Joe, 2026-10-07, held over the brief). Stance is a row of
		--   30 off bar 1's left end, written 12 x 1 so it is one row whatever
		--   the class has; the extra button sits over its right end; the pet
		--   bar is a row of 30 off bar 1's right end. Hung from bar 1's EDGES,
		--   not its centre, so they stay 8 off its ends whatever its width.
		-- Bars 3 and 4 are off: the Rows seed is bars 1 and 2. The tooltip and
		-- the music deck are not on the board and keep their own defaults.
		layout = "LAT1;b=1,2;bar1=spine,TOP,CENTER,0,-98,12x1,44;bar2=spine,TOP,CENTER,0,-162,12x1,34;barextra=bar1,BOTTOMRIGHT,TOPLEFT,-8,0;barpet=bar1,LEFT,RIGHT,8,0,10x1,30;barstance=bar1,RIGHT,LEFT,-8,0,12x1,30;chat=screen,BOTTOMLEFT,BOTTOMLEFT,24,24,210x120;minimap=screen,CENTER,TOPRIGHT,-124,-124;party=screen,TOPLEFT,TOPLEFT,210,-400;pet=player,TOPLEFT,CENTER,-172,110;player=screen,CENTER,CENTER,-280,-330;target=player,LEFT,RIGHT,216,0;targettarget=target,TOPRIGHT,CENTER,172,110",
	},
	block = {
		label = L.presets.block.label,
		blurb = L.presets.block.blurb,
		-- The Block seed (strands brief 9a, 9c): bars 1 and 2 as 3 x 4 of 44,
		-- bar 2 braided onto bar 1's right edge into one 6 x 4 block, key chips
		-- on. From board 9a: the spine raised to y 810 to make room (the player
		-- 60 higher than rows), the block's top at 852. Bar 1 hangs by its top
		-- right, 2 right of the spine's centre: half the braid's seam overlap
		-- (pad - gap / 2), which puts the block's centre on the spine's.
		-- Stance off bar 1's left end as in rows. The pet bar off BAR 2's right
		-- end: off bar 1's it would sit on bar 2 - still bonded to an action
		-- strand. The extra button over the stance row's right end, under the
		-- player. Everything else is rows'.
		layout = "LAT1;b=1,2;k=1,2;bar1=spine,TOPRIGHT,CENTER,2,-42,3x4,44;bar2=bar1,TOPLEFT,TOPRIGHT,-5,0,3x4,44,braid;barextra=barstance,BOTTOMRIGHT,TOPRIGHT,0,8;barpet=bar2,LEFT,RIGHT,8,0,10x1,30;barstance=bar1,RIGHT,LEFT,-8,0,12x1,30;chat=screen,BOTTOMLEFT,BOTTOMLEFT,24,24,210x120;minimap=screen,CENTER,TOPRIGHT,-124,-124;party=screen,TOPLEFT,TOPLEFT,210,-340;pet=player,TOPLEFT,CENTER,-172,110;player=screen,CENTER,CENTER,-280,-270;target=player,LEFT,RIGHT,216,0;targettarget=target,TOPRIGHT,CENTER,172,110",
	},
	split = {
		label = L.presets.split.label,
		blurb = L.presets.split.blurb,
		-- The Split seed (strands brief 9c): bar 1 as in rows; bar 2 a 1 x 12
		-- column off the player's left edge, bar 3 its mirror off the target's
		-- right, 28 px, 18 off the capsule as on board 9a. Centred on it, because
		-- 9a's top-aligned column runs off a 1080 screen under our lower spine;
		-- at 34 px even a centred one did (Joe, 2026-10-08).
		-- Stance and pet go UNDER bar 1, in the row bar 2 left empty: off its
		-- ends they ran into the columns. Still bonded to bar 1.
		-- The party starts at 300, not 420, to clear bar 2's column.
		-- Everything else is rows'.
		layout = "LAT1;b=1,2,3;bar1=spine,TOP,CENTER,0,-98,12x1,44;bar2=player,RIGHT,LEFT,-18,0,1x12,28;bar3=target,LEFT,RIGHT,18,0,1x12,28;barextra=bar1,BOTTOMRIGHT,TOPLEFT,-8,0;barpet=bar1,TOPRIGHT,BOTTOMRIGHT,0,-8,10x1,30;barstance=bar1,TOPLEFT,BOTTOMLEFT,0,-8,12x1,30;chat=screen,BOTTOMLEFT,BOTTOMLEFT,24,24,210x120;minimap=screen,CENTER,TOPRIGHT,-124,-124;party=screen,TOPLEFT,TOPLEFT,210,-300;pet=player,TOPLEFT,CENTER,-172,110;player=screen,CENTER,CENTER,-280,-330;target=player,LEFT,RIGHT,216,0;targettarget=target,TOPRIGHT,CENTER,172,110",
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
