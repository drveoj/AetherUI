--[[--------------------------------------------------------------------------
	AetherUI :: Locale

	Every word this addon puts on a screen, in one place per language.

	A KEY NAMES THE PHRASE; IT IS NOT THE PHRASE.

		desc = note(A.F(L.options.minimap.desc, A.Bad(L.common.inCombat))),

	The first version of this used the English itself as the key, which is the
	CurseForge convention and is wrong for a project that is still being
	written: correcting a typo in a sentence CHANGES ITS KEY, and every
	translation of it already submitted is orphaned by the fix. It also puts two
	hundred characters of prose in the middle of a line of code.

	So a key is a name. The English lives in Locale/enUS.lua, which is a file
	you EDIT - it is the source of truth for the English text, not a generated
	echo of the source. Fix wording there and no translation is disturbed,
	because the key did not move.

	NESTED, THOUGH THE STORAGE IS FLAT. `L.options.minimap.desc` reads as what
	it is; underneath it is one table keyed `"options.minimap.desc"`, because
	that is the shape the packager writes and a nested table is not. The walk
	from one to the other is the metatable below, and it costs a table lookup
	per level on paths that are resolved once and drawn from thereafter.

	TWO LAYERS. The player's language sits on top of English, so a phrase
	nobody has translated yet draws correctly rather than blank - and a language
	that is half done is half done rather than half missing. A key missing from
	BOTH draws its own path, which is loud on purpose: that is a coding mistake
	rather than a translation gap, and it should look like one.

	HOW A TRANSLATION GETS HERE
	---------------------------
	Locale/enUS.lua is the master list and the file to paste into CurseForge's
	phrase importer, once, which is how the phrases get created over there.

	Locale/deDE.lua and its nine siblings carry nothing but an @localization@
	block. The BigWigs packager replaces that block with the translations
	CurseForge holds at the moment the zip is built - so a translation submitted
	on the website is in the next release without anybody editing a file. In the
	repository those files are empty of strings, which is correct: the
	repository is not where translations live.

	See docs/I18N.md, and the packager's own wiki page on Localization
	Substitution for the block's parameters.

	WHAT IS NOT IN HERE
	-------------------
	Anything the CLIENT says. Spell names, zone names, item names, class names
	and the rest already arrive in the player's language; putting them through
	this would be translating a translation. The rule is: if we wrote the words,
	they belong here, and if Blizzard wrote them, they do not.

	Nor the changelog. It is release notes rather than interface, it is written
	fresh every version, and asking volunteers to translate a paragraph that
	will be replaced on Tuesday is how a translation project dies.

	Nor a slash command, an option key or a value the command itself takes -
	`/aether unlock`, `left`, `class`. You have to be able to type them.
----------------------------------------------------------------------------]]

local ADDON, A = ...

-- The English, and the player's language over the top of it. Both flat, both
-- keyed by the dotted path.
local EN, LOC = {}, {}

--- Where a locale file writes its phrases.
--
--  ASKED FOR BY NAME rather than handed out as one table, because there are two
--  and they are not interchangeable: English is the floor everything else
--  stands on, and it has to stay reachable when a translation is loaded on top.
function A.Phrases(locale)
	return (locale == "enUS") and EN or LOC
end

-- ---------------------------------------------------------------------------
-- the walk from L.a.b.c to "a.b.c"
-- ---------------------------------------------------------------------------

-- One proxy per path, built on first use and kept. Without the cache every
-- `L.options.minimap.desc` in a layout pass allocates two tables for the two
-- branches it passes through.
local nodes = {}

local Node

--- The value at a path, or nil.
local function value(path)
	local v = LOC[path]
	if v ~= nil then return v end
	return EN[path]
end

local meta = {
	__index = function(self, key)
		local path = self.__path .. "." .. tostring(key)
		local v = value(path)
		if v ~= nil then return v end
		return Node(path)
	end,

	-- A PATH USED AS A STRING IS THE PATH. Reaching here means the phrase is in
	-- neither table, so what draws is `options.minimap.desc` - which nobody
	-- will mistake for a sentence, and which says exactly what is missing.
	__tostring = function(self) return self.__path end,
	__concat = function(a, b)
		if type(a) == "table" and a.__path then a = a.__path end
		if type(b) == "table" and b.__path then b = b.__path end
		return a .. b
	end,
	__len = function(self) return #self.__path end,
}

Node = function(path)
	local n = nodes[path]
	if not n then
		n = setmetatable({ __path = path }, meta)
		nodes[path] = n
	end
	return n
end

--- Every word this addon wrote, reached by name.
A.L = setmetatable({}, {
	__index = function(_, key)
		local v = value(key)
		if v ~= nil then return v end
		return Node(tostring(key))
	end,
})

-- ---------------------------------------------------------------------------

--- One phrase, formatted.
--
--  `A.F(L.tour.step, 3, 9)` - the format string is the phrase, so a translator
--  gets the whole sentence with its placeholders in it and can move them, which
--  is the entire point of translating a sentence rather than the words in it.
--  Building a sentence out of pieces is the one thing this addon must not do.
--
--  A TRANSLATION WITH THE WRONG PLACEHOLDERS IN IT DOES NOT TAKE THE ADDON
--  DOWN. `%d` where the English had `%s` throws, and these arrive from
--  volunteers on a website rather than through review here - so the failure
--  lands on the one phrase and what draws is the format string itself,
--  unformatted. Ugly, and legible, and not an error.
function A.F(fmt, ...)
	fmt = tostring(fmt)
	local ok, out = pcall(string.format, fmt, ...)
	if ok then return out end
	return fmt
end

return A.L
