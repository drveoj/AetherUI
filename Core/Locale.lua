--[[--------------------------------------------------------------------------
	AetherUI :: Locale

	Every word this addon puts on a screen, in one place per language.

	THE KEY IS THE ENGLISH. `L["Take the tour"]` rather than `L.TOUR_TAKE`, which
	is the convention CurseForge and the BigWigs packager are both built around:
	a phrase's key IS its English text, so a translator sees the sentence they
	are translating rather than a name somebody invented for it, and a string
	with no translation falls back to something readable rather than to a
	shouty identifier.

	It has one more property that matters more than it looks: a key that is
	missing is a key that still READS. See the metatable below.

	HOW A TRANSLATION GETS HERE
	---------------------------
	Locale/enUS.lua is generated from the source by `Tools/i18n.py --export` and
	is the master list. It is also the file to paste into CurseForge's phrase
	importer, once, which is how the phrases get created over there.

	Locale/deDE.lua and its nine siblings carry nothing but an @localization@
	block. The BigWigs packager replaces that block with the translations
	CurseForge holds at the moment the zip is built - so a translation submitted
	on the website is in the next release without anybody editing a file. In the
	repository those files are empty of strings, which is correct: the
	repository is not where translations live.

	See docs/I18N.md for the whole arrangement, and the packager's own wiki page
	on Localization Substitution for the block's parameters.

	WHAT IS NOT IN HERE
	-------------------
	Anything the CLIENT says. Spell names, zone names, item names, class names
	and the rest already arrive in the player's language; putting them through
	this would be translating a translation. The rule is: if we wrote the words,
	they belong here, and if Blizzard wrote them, they do not.

	Nor the changelog. It is release notes rather than interface, it is written
	fresh every version, and asking volunteers to translate a paragraph that
	will be replaced on Tuesday is how a translation project dies.
----------------------------------------------------------------------------]]

local ADDON, A = ...

--- Every word this addon wrote, by the English of it.
--
--  A MISSING KEY IS ITS OWN ENGLISH, which is the whole reason the key is the
--  English. The alternatives are both worse: nil reaches SetText and draws
--  nothing, so a phrase somebody forgot to add is an empty label nobody
--  notices, and an error turns a missing translation into a broken addon for
--  the one player whose language is furthest behind.
--
--  So a phrase with no entry at all still reads correctly in English, and a
--  language that is half translated is half translated rather than half blank.
--  That is exactly what `handle-unlocalized="english"` does at package time;
--  this is the same rule at runtime, for the keys the packager never saw.
--
--  NOTHING IS COLLECTED AT RUNTIME to check this. Whether every key the source
--  asks for has an entry is a question about the SOURCE, so the suite answers
--  it by reading the files - see the `== phrases ==` block in the harness.
--  Counting lookups in game would be a thousand-entry table built for a
--  question nobody asks from inside the client.
local L = setmetatable({}, {
	__index = function(_, key) return key end,
})

A.L = L

--- One phrase, formatted.
--
--  `A.F("Step %d of %d", 3, 9)` - the format string is the phrase, so a
--  translator gets the whole sentence with its placeholders in it and can move
--  them, which is the entire point of translating a sentence rather than the
--  words in it. String.format on a translated string is the one place this
--  addon must not build a sentence out of pieces.
function A.F(key, ...)
	local ok, out = pcall(string.format, L[key], ...)
	-- A TRANSLATION WITH THE WRONG PLACEHOLDERS IN IT DOES NOT TAKE THE ADDON
	-- DOWN. `%s` where the English had `%d` throws, and it is submitted by a
	-- volunteer on a website rather than reviewed here - so the failure lands
	-- on the phrase and nowhere else, and what draws is the English.
	if ok then return out end
	local fallback = select(2, pcall(string.format, key, ...))
	return fallback or key
end

return L
