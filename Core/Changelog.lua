--[[--------------------------------------------------------------------------
	AetherUI :: Changelog

	What changed, newest first. This file is the source of two things that were
	previously written by hand in two places and drifted:

	  * the What's new card in the Toolbox, which showed a paragraph somebody
	    remembered to edit, marked read against a version number somebody else
	    remembered to bump;
	  * the full history behind the card's Notes link, which did not exist.

	The version is NOT written here. `## Version` in AetherUI.toc is the single
	source of truth - it is what the client shows in its own addon list, what
	CurseForge reads, and what A.version already carries - so an entry here
	claiming a different one would be a second answer to a question that has
	one. What this file does is name the version each entry BELONGS to, and the
	harness refuses a build whose newest entry does not match the .toc. That is
	the check that makes "remember to write the notes" not a thing to remember.

	Numbering is major.minor.build:

	  major   a release with new features in it
	  minor   accumulated fixes and small enhancements
	  build   hotfixes between the two

	Use Tools/bump.py rather than editing by hand - it writes the .toc and this
	file together, which is the whole point of them being one step.

	Style: each line is a sentence, present tense, about what the PLAYER can now
	do or now sees. Not "refactored LayoutContent" - that is what the commit
	message is for, and nobody reading a drawer wants it.
----------------------------------------------------------------------------]]

local ADDON, A = ...

--- Newest first. The harness enforces both that order and the match with the
--  .toc, so a hand-edit that puts an entry in the wrong place fails the build
--  rather than showing yesterday's news as today's.
A.CHANGELOG = {
	{
		version = "2.0.0",
		date    = "2026-10-06",
		lines   = {
			"AetherUI is now called Lattice. Same addon, new name. Your settings start fresh, and /lattice tour sets everything up again in about a minute.",
			"Full support for WoW Forever as it launches on November 4th, alongside Classic Era.",
			"The settings window is a map of your own screen: point at the thing you want to change, or search with /.",
			"Frames hang from each other now: the target from the player, your bars from the line between you and your target. Move one and what hangs from it comes too.",
			"Unlock mode shows how things connect: a dot field to snap to, the lines between frames, and an inspector. Drop a frame on another's junction to hang it from that one.",
			"Every action bar can be reshaped from its corner in unlock: any number of rows or columns, uneven shapes, wrapping down instead of across. Drag a bar's edge against another's to join them into one block.",
			"Each bar has its own opacity at rest and in a fight, can show only on hover, and can show its keybinds on its buttons. Hide a bar by dragging it to the row along the bottom in unlock; click it there to bring it back.",
			"Your whole layout is one line of text you can copy, share and paste back. Three starting layouts come with it: Rows, Block and Split.",
			"The quest tracker is now the World trunk under the minimap: your quests with their item buttons, and Mail, Tracking, Calendar and the music player as nodes. In a fight it draws up out of the way and leaves your active quest showing.",
			"The Toolbox is now the left trunk: Menu, Widgets, Addons, Settings, What's new, and Party while you're in a group. It can sit on the right instead, and the minimap swaps sides with it.",
			"Eight new skins: Amethyst, Sapphire, Emerald and Ruby, and Winter, Spring, Summer and Autumn, alongside Midnight, Dawn, Noon and Dusk. Pick one under Theme or on the tour's first stop.",
			"Cast bars are lanes on the line between you and your target, and breath and fatigue run along it too. Combo points and other class resources sit in a tray under your frame.",
			"Shields such as Power Word: Shield now show on your unit and party health bars, with a switch and a colour picker under Unit frames.",
			"/lattice is the command now. /aether still works for this version.",
			"Fixed: with the game's chat timestamps on, \"Keep Blizzard's [1. General]\" switched off did nothing. The channel name now comes off as it should.",
			"Fixed: several settings descriptions showed a stray \"\\n\\n\" instead of a paragraph break.",
		},
	},
	{
		version = "1.1.0",
		date    = "2026-10-05",
		lines   = {
			"AetherUI now runs on the WoW Forever beta as well as Classic Era, and will support the full release when it launches on November 4th.",
			"AetherUI no longer restyles the game's own windows. The character sheet, spellbook, talents, vendors, mail and the rest are back to Blizzard's look. The work now goes into the HUD, bags, quest log, Toolbox, Zen and the flight console.",
			"The flight console isn't available on WoW Forever yet.",
			"Settings have a window of their own. Options > AddOns > AetherUI has a button that opens it.",
			"Action bars now use the game's own button size. If you never picked a slot size yourself, yours moves with it; one you chose is kept.",
			"The quest tracker no longer empties itself when a zone is folded in the quest log, and says so when quests are hidden behind one.",
			"Scrolling a list no longer throws an error.",
			"The Talents button is hidden below level 10 rather than offered and doing nothing, and appears the moment you reach it.",
			"Menu glyphs shrink with their row instead of overlapping each other on a narrow dock.",
			"Right-clicking the minimap cancels your tracking again.",
			"Turning a module off and on again puts its look back properly, rather than leaving Blizzard's art on top of ours.",
			"Numpad keybinds read as symbols - the numpad plus shows as N+ rather than NPLUS.",
			"Bug reports now carry the interface version they were taken on.",
		},
	},
	{
		version = "1.0.0",
		date    = "2026-08-25",
		lines   = {
			"Initial public release",
		},
	},
}

--- The entry the running build belongs to.
--
--  Matched by VERSION rather than assumed to be the first: the .toc is the
--  source of truth, and a build shipped from a working tree whose changelog was
--  not bumped should show the notes for what is actually running - which is the
--  older entry - rather than the notes for a version nobody has.
--
--  Falls back to the newest entry, because the alternative is a card with
--  nothing in it, and an empty card is a worse answer than a slightly early one.
function A:Notes(version)
	local list = A.CHANGELOG
	if not list or #list == 0 then return nil end
	version = version or A.version
	for _, entry in ipairs(list) do
		if entry.version == version then return entry end
	end
	return list[1]
end

--- Every entry, newest first. A function rather than the table itself so
--  callers cannot sort it out from under the harness's ordering check.
function A:NotesHistory()
	local out = {}
	for i, entry in ipairs(A.CHANGELOG or {}) do out[i] = entry end
	return out
end

--- "1.2.3" -> 1, 2, 3. Anything unparseable is zero, which sorts below every
--  real version rather than throwing.
function A:ParseVersion(s)
	if type(s) ~= "string" then return 0, 0, 0 end
	local a, b, c = s:match("^(%d+)%.(%d+)%.(%d+)")
	if not a then
		a, b = s:match("^(%d+)%.(%d+)")
		c = 0
	end
	return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

--- Is `a` a later version than `b`? Component-wise, so 0.10.0 beats 0.9.9 -
--  a string compare gets that backwards and is the classic way this goes wrong.
function A:VersionNewer(a, b)
	local a1, a2, a3 = A:ParseVersion(a)
	local b1, b2, b3 = A:ParseVersion(b)
	if a1 ~= b1 then return a1 > b1 end
	if a2 ~= b2 then return a2 > b2 end
	return a3 > b3
end
