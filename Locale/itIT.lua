--[[--------------------------------------------------------------------------
	AetherUI :: itIT

	NOTHING BUT A SUBSTITUTION BLOCK, and that is not an oversight. The BigWigs
	packager replaces the line below with whatever translations CurseForge holds
	at the moment the zip is built, so a phrase translated on the website is in
	the next release without anybody editing this file. Translations submitted
	into the repository instead would be overwritten by the next package.

	`handle-unlocalized="ignore"` leaves an untranslated phrase OUT rather than
	writing the English into it. There is no need: a key with no entry falls
	back to its own English in Core/Locale.lua, so a half-translated language
	reads half in itIT and half in English rather than carrying a second copy
	of every English string in every one of ten files.

	`escape-non-ascii="false"` because these files are UTF-8 and the client reads
	UTF-8. Escaping would turn every accented character into a byte sequence
	nobody can proofread.
----------------------------------------------------------------------------]]

local ADDON, A = ...

-- The player's client, not their account: one language is loaded and the other
-- nine cost a file read and an early return.
if GetLocale() ~= "itIT" then return end

local L = A.Phrases("itIT")

--@localization(locale="itIT", format="lua_additive_table", handle-unlocalized="ignore", escape-non-ascii="false", table-name="L")@
