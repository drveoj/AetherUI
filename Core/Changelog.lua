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
