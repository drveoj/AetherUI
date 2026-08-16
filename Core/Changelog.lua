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
		version = "0.9.0",
		date    = "2026-08-16",
		lines   = {
			"Your pet gets a frame of its own - portrait, name, health and power - and you can put it wherever you like. A hunter's pet wears its mood on the orb's rim: green happy, gold content, red unhappy.",
			"Pet bar tooltips are back. Every button on it had a working tooltip handler that quietly did nothing, because the name it needed was never reaching it.",
			"A hunter's character sheet has five tabs and the last one hung over the edge of the window. The tab lettering comes down two points and the row fits.",
			"The magazine reader is a sensible size. It was taking as much of the screen as it could get; it now draws the page at a fraction of its own size, with a setting to tune it, and the magnifier still goes to true actual size.",
			"The reader says what it is at the top - I.F.E.C. in the air, N.I.F.E.C. on the ground - instead of repeating the magazine's own title, which every page already carries.",
			"A middle dot in the Toolbox's mail hint and in the library's listing was drawing as a missing-glyph box and two digits. Both fixed.",
		},
	},
	{
		version = "0.8.0",
		date    = "2026-08-16",
		lines   = {
			"The Toolbox has a player in it. Season One's music plays on the ground, not just on a griffin - there is a transport on the rail with the drawer shut, and right-clicking it gives you stop, previous and next.",
			"A library, from the console in flight or from the Toolbox on the ground. Everything in season, grouped by season; click a row to add it to the programme or to take it back out.",
			"Magazines open and turn. A page at a time, at the size your screen allows, or at actual size with a drag to read the small print - and it remembers the page you were on.",
			"Skip actually skips. The transport used to stop the music and go dead at the end of a short flight; it now pulls the next thing out of the season and keeps the queue a step ahead of you.",
			"Pause and resume, at last. There is no pause in this game's sound engine, so Season One's tracks are cut into three-second pieces and crossfaded - you lose at most three seconds, and you should not be able to hear the joins.",
			"A programme that runs out says so, and offers you the music again, the last track again, or the view.",
			"The console can carry on after you land, if you ask it to. There is a switch for it, and one for the in-flight player itself - the flight timer, the route and the countdown stay either way.",
			"Reloading no longer leaves a track playing underneath everything, and the game's sound settings come back even if the client dies on a griffin.",
			"No more tooltips floating over an empty sky in flight, from buttons that are not on screen.",
		},
	},
	{
		version = "0.7.0",
		date    = "2026-08-15",
		lines   = {
			"A trainer's headings fold with our own marks, and every spell in a long list is in our lettering rather than just the first eleven.",
			"The trainer's Filter sits inside the window, and Train All is in one of our buttons.",
			"Every dropdown wears our chevron, and the list it opens is in glass instead of black stone.",
			"The flight master keeps his map: the parchment comes off, the map and the flight points on it stay.",
			"A quest an NPC offers is readable - its title was printed black for paper.",
		},
	},
	{
		version = "0.6.0",
		date    = "2026-08-15",
		lines   = {
			"The windows an NPC opens are in glass: the vendor, the quest giver, anyone you can talk to, and the trainer.",
			"Text printed for parchment is lifted so you can read it - and only that, so gold headings and reward names still mean what they meant.",
			"Buttons and tabs share one shape across the whole interface, with the tab you are on filled in like the chat's.",
			"Curved corners are drawn on whole pixels now, everywhere - they were landing half across one, which is what made them look rough.",
			"The +N more line on the quest tracker opens the quest log at the first quest it is standing in for.",
		},
	},
	{
		version = "0.5.5",
		date    = "2026-08-15",
		lines   = {
			"The guild and communities window is in glass, with its side tabs in our cells, its crest inside the frame and its lists in our lettering.",
			"Breath, fatigue and feign death are drawn as a cast bar without the icon, and which timer it is still reads in the colour.",
			"A specialist bag is a section of its own: the arrows in your quiver sit under QUIVER with the room it has left, rather than being filed as trade goods.",
			"The help window loses the stone band behind its title.",
			"/aether panels dump <FrameName> reads a window's parts into a box you can copy, for reporting one that still looks wrong.",
		},
	},
	{
		version = "0.5.4",
		date    = "2026-08-14",
		lines   = {
			"The talent tree is in glass: your talents wear the same cells as your spells, the branches between them are untouched, and a rim says whether you can spend a point there or have finished it.",
			"The chat window stays where you put it. Blizzard's Edit Mode was re-applying its own layout at login, which is why it only ever walked home on a new character.",
			"The error box scrolls, with a rail when there is more to read - a long report used to draw its last forty lines outside the window.",
			"/aether chat where says where the chat window is, where it should be, and what has moved it.",
		},
	},
	{
		version = "0.5.3",
		date    = "2026-08-14",
		lines   = {
			"The spellbook is in glass: your spells sit in the same cells as your bags, the schools run down the side, and its title, tabs and close button are ours.",
			"The bags count the slots you can actually use - a quiver's empty slots are named beside the free count rather than added to it, and get their own section in the grid.",
			"Addon buttons left loose beside the minimap are collected into the Toolbox, and one belonging to an addon already listed joins it rather than turning up twice.",
			"The last launcher in the Toolbox can be reached - with an odd number of them it sat one row below the fold with nowhere left to scroll.",
			"Check boxes in the client's windows are drawn as proper circles, with room between them and their labels.",
		},
	},
	{
		version = "0.5.2",
		date    = "2026-08-14",
		lines   = {
			"The main menu's title sits inside the window in our lettering, with the client's stone bar gone.",
		},
	},
	{
		version = "0.5.1",
		date    = "2026-08-14",
		lines   = {
			"The skill list fills the window - as many rows as there is room for, instead of the twelve the client draws.",
			"The character sheet is in our lettering throughout, at the sizes the client laid its rows out for.",
			"Its tabs sit as one even row in the middle of the window, and the one you are on reads brighter. No word gets shortened to fit.",
			"The trees' plus and minus marks are ours, and All sits at the head of the groups it governs.",
			"The skill list shows a rail when there is more to scroll to.",
			"Dialogs and the main menu are drawn at your scale, and the menu's buttons are ours.",
		},
	},
	{
		version = "0.5.0",
		date    = "2026-08-14",
		lines   = {
			"The character sheet is in glass: equipment slots wear the same cells as your bags, with a rim in the item's quality colour.",
			"Its tabs fit the window now, and the one you are on reads brighter than the rest.",
			"/aether errors opens the last Lua errors in a box you can select and copy, with the build already at the top of it.",
			"/aether errors diag puts the same report in that box, ready to paste.",
			"AetherUI says which build it is at login. /aether greet off if you would rather it did not.",
		},
	},
	{
		version = "0.4.11",
		date    = "2026-08-13",
		lines   = {
			"Tooling: cutting a version now runs the test suite first and refuses if anything is failing. A version number is a claim that the build works.",
		},
	},
	{
		version = "0.4.10",
		date    = "2026-08-13",
		lines   = {
			"New: the game's own windows - character, spellbook, talents, guild, map, menu and help - wear the same glass as everything else.",
			"What is inside them is untouched: item slots, spell buttons and map pins are still the game's own.",
		},
	},
	{
		version = "0.4.9",
		date    = "2026-08-13",
		lines   = {
			"Groundwork: the machinery that reskins the game's own dialogs now lives in one place, ready for the character sheet, spellbook and talents to use.",
		},
	},
	{
		version = "0.4.8",
		date    = "2026-08-13",
		lines   = {
			"Fixed: the dialog's own opaque background showed through the glass, so nothing looked translucent. It lives in a child frame rather than on the dialog itself, and was never being stripped.",
		},
	},
	{
		version = "0.4.7",
		date    = "2026-08-13",
		lines   = {
			"Fixed: clicking Yes or No on a skinned dialog flashed Blizzard's red button back, and it stayed for every dialog after.",
			"Fixed: the buttons kept their old art showing through the glass - the module could not find them on the newer dialogs at all.",
		},
	},
	{
		version = "0.4.6",
		date    = "2026-08-13",
		lines   = {
			"New: the game's own confirmation dialogs - 'do you want to destroy this?' and the like - wear the same glass as everything else.",
		},
	},
	{
		version = "0.4.5",
		date    = "2026-08-13",
		lines   = {
			"Fixed: NPC titles never appeared. A scanning tooltip has to be driven by the unit's GUID, not by its token, or it reads nothing back.",
			"The title is also read a line lower when colourblind mode is on, which would have broken it a second way.",
			"New: /aether debug turns the running commentary on and off - there was previously no way to reach it.",
		},
	},
	{
		version = "0.4.4",
		date    = "2026-08-13",
		lines   = {
			"Vendors, flight masters and anyone else with a job are drawn as names now whatever their reaction - the neutral goblin selling ammo reads the same as the innkeeper. Mobs standing next to them still get the capsule.",
		},
	},
	{
		version = "0.4.3",
		date    = "2026-08-13",
		lines   = {
			"Fixed: vendors, flight masters and anything else not fighting you had no nameplate at all, so none of our treatment reached them. The game only draws plates for your target and whatever is attacking you unless it is asked otherwise, and now it is asked.",
			"The V key still works: that toggle is set once and then left alone, rather than being forced back every time you press it.",
		},
	},
	{
		version = "0.4.2",
		date    = "2026-08-13",
		lines   = {
			"Fixed: a bank bag slot you had just bought would not take a bag, and offered to sell you the next one instead.",
		},
	},
	{
		version = "0.4.1",
		date    = "2026-08-13",
		lines   = {
			"The default UI scale is 1.0. If you like it smaller, set it before you next log in - /aether scale 0.71 - or it will come up at full size.",
			"New: vendors, innkeepers and flight masters get their title under their name again, read from the tooltip since a nameplate does not carry one.",
			"New: nameplates are asked to draw as far out as the client allows, which is what the change of lettering at a fixed distance was.",
			"Fixed: another addon hiding the world's text around a cutscene could leave our nameplate settings turned off afterwards. They get put back now, whoever moved them.",
		},
	},
	{
		version = "0.4.0",
		date    = "2026-08-13",
		lines   = {
			"Nameplates. Everything around you now wears one capsule: the level on a difficulty-coloured disc, the name in its reaction colour, and the health bar inside the pill.",
			"Your target comes up to full size with a rim glow in its reaction, and every other plate shrinks and dims out of its way.",
			"Your own debuffs ride under your target as timed chips - up to four, then a chip saying how many more. Only yours, and only on your target.",
			"A cast capsule slides in under anything that starts casting, with the spell name and a progress bar. Channels empty rather than fill.",
			"People are drawn as people: friendly players and NPCs get plain shadowed text with a class-coloured level pip and their guild underneath, no glass and no bar unless they are hurt. Whether something is a mob is decided by whether you can attack it, so a flight master is a name and a kodo is a capsule.",
			"Elite and rare mobs get a chip beside the name, and a neutral shows a name only until it is in a fight.",
			"All of it has its own options page, and Blizzard's plates go back the moment you turn it off.",
		},
	},
	{
		version = "0.3.26",
		date    = "2026-08-13",
		lines   = {
			"Fixed: NPCs you have no reputation with were drawn as mobs. Whether something is a mob is now decided by whether you can attack it, not by how it feels about you - so a flight master is a name and a wandering kodo is still a capsule.",
		},
	},
	{
		version = "0.3.25",
		date    = "2026-08-13",
		lines   = {
			"Fixed: with a bag window open, no key worked except Escape. A frame that captures the keyboard has to be told to pass everything else through, and the call that does it was being skipped as redundant.",
			"Fixed: your target's nameplate could stay dimmed until you clicked something, when a batch of plates came back at once.",
			"New: pets, imps and everything else somebody summoned get nameplates too, so they are not the only thing left in the client's own font.",
			"Removed: the minimap's button-drawer settings, which outlived the drawer itself and had not been read by anything since.",
		},
	},
	{
		version = "0.3.24",
		date    = "2026-08-13",
		lines   = {
			"New: nameplates have their own options page - size, the level disc, bar dimensions, whether friendlies are drawn as names, and party class colours.",
			"Nameplate settings no longer fight Zen: changing one mid-zen leaves the plates where zen put them.",
		},
	},
	{
		version = "0.3.23",
		date    = "2026-08-13",
		lines   = {
			"Fixed: friendly NPCs kept the client's yellow floating name instead of ours. The engine only makes a nameplate for a friendly unit when asked, so now we ask.",
			"Friendly names and guild lines come up a point - they sit on the world with no glass behind them, and read a size smaller than the same text inside a capsule.",
			"Level discs on nameplates are a little larger, so a two-digit level is not jammed against the rim.",
		},
	},
	{
		version = "0.3.22",
		date    = "2026-08-13",
		lines   = {
			"New: friendly players and NPCs are plain shadowed text now instead of a capsule - a class-coloured level pip, the name, and the guild in angle brackets underneath.",
			"A friendly's health bar only appears when they are actually hurt.",
			"Fixed: a friendly player whose level the client would not report showed a skull. That badge means 'too far above you to judge as a threat', which is nonsense about somebody who is not one.",
			"Party members can be class-coloured instead of blue, if you turn it on.",
		},
	},
	{
		version = "0.3.21",
		date    = "2026-08-13",
		lines   = {
			"New: a cast capsule slides in under a nameplate when something starts casting - icon, spell name and a progress bar. Channels empty rather than fill.",
			"Debuff chips move down out of its way while it is open.",
		},
	},
	{
		version = "0.3.20",
		date    = "2026-08-13",
		lines   = {
			"New: your own debuffs appear as timed chips under your target's nameplate - up to four, then a chip saying how many more.",
			"Only yours, and only on your target: somebody else's debuff on the same mob is not your business, and a row of them under every plate is clutter with a countdown on it.",
		},
	},
	{
		version = "0.3.19",
		date    = "2026-08-13",
		lines   = {
			"New: your target's nameplate comes up to full size with a rim glow in its reaction colour, and every other plate shrinks and dims out of the way.",
			"Target changes fade over about a sixth of a second rather than snapping.",
		},
	},
	{
		version = "0.3.18",
		date    = "2026-08-13",
		lines   = {
			"Fixed: nameplates ignored the UI scale and were drawn at full size. They follow profile scale now, with their own multiplier on top.",
			"Fixed: on a plate with no health bar the name hung high in the capsule. It centres, and moves up when the bar arrives.",
		},
	},
	{
		version = "0.3.17",
		date    = "2026-08-13",
		lines   = {
			"New: nameplates. One capsule carries the level badge, the name and a health bar, tinted by the unit's reaction, with Blizzard's own plate put away underneath.",
			"Elite and rare mobs get a chip next to the name; a neutral shows a name only until it is in a fight.",
			"Still to come: friendly names, the target's emphasis and debuff chips, and cast bars.",
		},
	},
	{
		version = "0.3.16",
		date    = "2026-08-13",
		lines   = {
			"Fixed: pressing a key in combat with the bag window open put \"attempted to call a protected function\" in your error log, once per keypress.",
			"The same call sat on Zen's keyboard-wake path and could do it too.",
		},
	},
	{
		version = "0.3.15",
		date    = "2026-08-13",
		lines   = {
			"The level disc's outer ring is thicker again, and its edge feathers properly.",
		},
	},
	{
		version = "0.3.14",
		date    = "2026-08-13",
		lines   = {
			"The level disc has no seam between its face and rim, and a thinner outer ring.",
		},
	},
	{
		version = "0.3.13",
		date    = "2026-08-13",
		lines   = {
			"The chat tab unread dot no longer appears on the tab you are already reading.",
		},
	},
	{
		version = "0.3.12",
		date    = "2026-08-13",
		lines   = {
			"Level discs now have a raised pale rim, a shaded class or reaction-tinted face, and crisp white level type.",
		},
	},
	{
		version = "0.3.11",
		date    = "2026-08-13",
		lines   = {
			"The level orb is a solid disc with a diagonal sheen and a thicker rim, and the number picks its own colour.",
		},
	},
	{
		version = "0.3.10",
		date    = "2026-08-13",
		lines   = {
			"The level orb is coloured like the tooltip's level badge - a tinted disc with the number in the class colour.",
		},
	},
	{
		version = "0.3.9",
		date    = "2026-08-13",
		lines   = {
			"The level orb is a flat disc in the class colour, with a lifted rim, and the health bar matches it.",
		},
	},
	{
		version = "0.3.8",
		date    = "2026-08-13",
		lines   = {
			"Class-coloured health bars are brighter, and a Rogue's no longer reads as olive.",
		},
	},
	{
		version = "0.3.7",
		date    = "2026-08-13",
		lines   = {
			"Long unit names collapse the detail line instead of running out of the frame.",
		},
	},
	{
		version = "0.3.6",
		date    = "2026-08-13",
		lines   = {
			"Settings tiles put their label beside the icon and wrap it, instead of leaving the middle empty.",
		},
	},
	{
		version = "0.3.5",
		date    = "2026-08-13",
		lines   = {
			"Zen no longer tilts the camera at all - the shot is zoom and CVars, like DialogueUI's.",
		},
	},
	{
		version = "0.3.4",
		date    = "2026-08-13",
		lines   = {
			"Zen no longer tilts the camera further each time it starts and stops.",
			"Quiet before zen is set in minutes, from one to five.",
		},
	},
	{
		version = "0.3.3",
		date    = "2026-08-13",
		lines   = {
			"The chat window keeps the size you dragged it to through a reload.",
		},
	},
	{
		version = "0.3.2",
		date    = "2026-08-13",
		lines   = {
			"The addon count sits on its own heading line instead of on the first row.",
			"Settings tile labels stay inside their tiles.",
			"Unlock frames reflects the real lock state, however it was changed.",
			"Tooltip level badges take the player's class colour.",
		},
	},
	{
		version = "0.3.1",
		date    = "2026-08-13",
		lines   = {
			"The What's new card fits its own Notes link instead of drawing through it.",
			"Re-docking the drawer re-lays what is inside it.",
		},
	},
	{
		version = "0.3.0",
		date    = "2026-08-13",
		lines   = {
			"The MAIL section is always there, saying 'No unread mail' when the box is empty.",
			"The addon list scrolls with the mouse wheel instead of just counting what it cut.",
		},
	},
	{
		version = "0.2.0",
		date    = "2026-08-13",
		lines   = {
			"Drag the Toolbox rail to any screen edge to re-dock it - unlock frames first.",
			"Docked top or bottom, the drawer lays its sections out as columns.",
			"Mail gets a column of its own there, so the addon list keeps its rows.",
			"Tooltips colour player names by class again.",
			"The chat window resizes by hand while frames are unlocked.",
		},
	},
	{
		version = "0.1.0",
		date    = "2026-08-01",
		lines   = {
			"The Toolbox has arrived: a drawer that docks to any screen edge, with"
				.. " your addon launchers on the rail beside it.",
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
