#!/usr/bin/env python3
"""Give a phrase a name, and file its English.

    python Tools/rekey.py --dry     what it would call everything
    python Tools/rekey.py           rewrite the source and Locale/enUS.lua

Run after `Tools/i18n.py --wrap`, which finds bare strings and puts them in
`L["English"]` - a phrase with a placeholder where its name should be. This
turns those into `L.area.group.leaf` and adds the English to Locale/enUS.lua,
leaving every entry already in that file exactly as somebody edited it.

WHY THE ENGLISH WAS A BAD KEY. It is the CurseForge convention and it is wrong
for a project still being written: correcting a typo in a sentence CHANGES ITS
KEY, and every translation of it already submitted is orphaned by the fix. It
also puts two hundred characters of prose in the middle of a line of code.

WHERE A NAME COMES FROM. Not from the English - a slug of a sentence is the same
problem one step removed, and it moves when the sentence does. From WHERE THE
PHRASE LIVES: the file says the area, the enclosing function says the group, and
the table key on the line says the leaf.

    Core/Options.lua                          -> options
      local function MinimapGroup()           -> minimap
        ring = toggle("Border", nil, ...)     -> ring.name
                                                 options.minimap.ring.name

That is stable against every edit to the words themselves, which is the whole
point of the exercise.
"""
import argparse
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tools"))

import importlib.util
_spec = importlib.util.spec_from_file_location(
    "i18n", os.path.join(ROOT, "Tools", "i18n.py"))
i18n = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(i18n)

STR = i18n.STR

# ---------------------------------------------------------------------------
# the area, from the file
# ---------------------------------------------------------------------------

AREA = {
    "Core/Options.lua": "options",
    "Core/Commands.lua": "cmd",
    "Core/Core.lua": "core",
    "Core/Config.lua": "core",
    "Core/Errors.lua": "errors",
    "Core/Movers.lua": "movers",
    "Core/Presets.lua": "presets",
    "Core/Launchers.lua": "launchers",
    "Core/Nav.lua": "nav",
    "Modules/Onboard.lua": "tour",
    "Modules/Toolbox.lua": "toolbox",
    "Modules/Bags.lua": "bags",
    "Modules/Chat.lua": "chat",
    "Modules/QuestLog.lua": "questlog",
    "Modules/QuestTracker.lua": "tracker",
    "Modules/ActionBars.lua": "bars",
    "Modules/UnitFrames.lua": "units",
    "Modules/PartyFrames.lua": "party",
    "Modules/Tooltips.lua": "tooltips",
    "Modules/Nameplates.lua": "plates",
    "Modules/Minimap.lua": "minimap",
    "Modules/Auras.lua": "auras",
    "Modules/Threat.lua": "threat",
    "Modules/Zen.lua": "zen",
    "Modules/Panels.lua": "panels",
    "Modules/Conveniences.lua": "conveniences",
    "Modules/Timers.lua": "timers",
    "Modules/XPBar.lua": "xp",
    "Modules/Popups.lua": "popups",
    "Modules/Menus.lua": "menus",
    "Modules/Fonts.lua": "fonts",
    "Modules/OptionsSkin.lua": "options",
    "Modules/Reskin.lua": "reskin",
}


def area_of(rel):
    key = rel.replace(os.sep, "/")
    if key in AREA:
        return AREA[key]
    stem = os.path.splitext(os.path.basename(rel))[0]
    return re.sub(r'[^a-z0-9]', '', stem.lower())


# ---------------------------------------------------------------------------
# the group, from whatever encloses the line
# ---------------------------------------------------------------------------

ENCLOSING = [
    # local function MinimapGroup()  /  local function Announce()
    re.compile(r'^local function (\w+)'),
    # function TB:RefreshMicro()  /  function Bags:Diagnose()
    re.compile(r'^function [\w.]*[.:](\w+)'),
    # handlers.skin = function(arg)
    re.compile(r'^handlers\.(\w+)\s*='),
    # Mini:Paint = function ... and the odd `Foo = function(`
    re.compile(r'^(\w+)\s*=\s*function'),
]

# Words a group name does not need: every builder in Options.lua is called
# SomethingGroup, and every diagnostic is called Diagnose.
STRIP = re.compile(r'(Group|Page|Section|Options)$')


def snake(name):
    name = STRIP.sub('', name) or name
    name = re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()
    return identifier(re.sub(r'[^a-z0-9_]', '', name).strip('_'))


def groups(body):
    """Line number -> the name of whatever encloses it."""
    out, current = {}, None
    for n, line in enumerate(body.split("\n"), 1):
        for rx in ENCLOSING:
            m = rx.match(line)
            if m:
                current = snake(m.group(1))
                break
        out[n] = current
    return out


# ---------------------------------------------------------------------------
# the leaf, from the line itself
# ---------------------------------------------------------------------------

# `ring = toggle(L["Border"], nil, ...)` - the table key is the leaf, and which
# argument it is says whether this is the name or the description.
ASSIGNED = re.compile(r'^\s*(\w+)\s*=\s*(\w+)\(')
# `head = "..."` / `desc = "..."` - the field IS the leaf.
FIELD = re.compile(r'^\s*(\w+)\s*=\s*')

# Which argument of which builder is what.
BUILDER_ARG = {
    "toggle": ("name", "desc"), "range": ("name", "desc"),
    "choice": ("name", "desc"), "action": ("name", "desc"),
    "header": ("name",), "note": ("text",), "group": ("name",),
}

# A word too common to tell two phrases apart with.
DULL = set(("the a an and or of to in on for is are it its this that with"
            " you your as at by be no not from").split())


# A key is reached as `L.a.b.c`, so every part of it has to be a Lua
# identifier: `L.zen.delays.1_min` is a malformed number and `L.x.end` is a
# syntax error. Both of those are real - "1 min" is a phrase and `end` is a
# field name somebody will write one day.
KEYWORDS = set(("and break do else elseif end false for function goto if in"
                " local nil not or repeat return then true until while").split())


def identifier(part):
    if not part:
        return "text"
    if part[0].isdigit():
        part = "n" + part
    if part in KEYWORDS:
        part = part + "_"
    return part


def slug(text, words=4):
    bits = re.findall(r"[A-Za-z0-9]+", text.lower())
    keep = [b for b in bits if b not in DULL] or bits
    out = "_".join(keep[:words])
    out = re.sub(r'_+', '_', out).strip('_')[:40]
    return identifier(out)


def leaf_for(line, text, argno):
    m = ASSIGNED.match(line)
    if m:
        key, fn = snake(m.group(1)), m.group(2)
        names = BUILDER_ARG.get(fn)
        if names:
            if len(names) == 1:
                return key
            return key + "." + names[min(argno, len(names) - 1)]
        return key
    m = FIELD.match(line)
    if m and m.group(1) not in ("local", "return"):
        return snake(m.group(1))
    return slug(text)


# ---------------------------------------------------------------------------
# reading every phrase site that is already going through L
# ---------------------------------------------------------------------------

# L["English"] and A.F("English" .. " more", ...) - the two shapes the first
# pass produced. Both are read as a CHAIN, because most of the long ones are
# written across several joined lines.
LSITE = re.compile(r'\bL\[(?=")')
FSITE = re.compile(r'\bA\.F\(\s*(?=")')


def sites(rel):
    """Every phrase in one file, as (start, stop, text, line, kind)."""
    path = os.path.join(ROOT, rel)
    with io.open(path, encoding='utf-8') as fh:
        body = fh.read()

    mask = i18n.code_mask(body)
    out = []
    for rx, kind in ((LSITE, "L"), (FSITE, "F")):
        for m in rx.finditer(body):
            if not mask[m.start()]:
                continue
            stop, pieces, whole = i18n.chain(body, m.end())
            if not whole or not pieces:
                continue
            # WHAT GETS REPLACED IS NOT THE SAME SPAN FOR BOTH.
            #
            # `L["x"]` is replaced whole, brackets and all, by `L.key`. But
            # `A.F("x", n)` keeps its call - only the format string becomes the
            # key - so the replacement starts at the QUOTE and not at the `A`.
            # Taking the wider span for both dropped the `A.F(` and left its
            # closing bracket behind, and the file stopped parsing.
            if kind == "L":
                if body[stop:stop + 1] != "]":
                    continue
                stop += 1
                start = m.start()
            else:
                start = m.end()
            out.append((start, stop, i18n.unescape("".join(pieces)),
                        body.count("\n", 0, m.start()) + 1, kind))
    out.sort()
    return body, out


def argument_index(body, at):
    """Which argument of its call a phrase is, counting commas at depth 0."""
    line_start = body.rfind("\n", 0, at) + 1
    head = body[line_start:at]
    depth, count = 0, 0
    for ch in head:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 1:
            count += 1
    return count


def name_everything(files):
    """rel -> [(start, stop, key, text)] plus the whole key -> English map."""
    plan, english, used = {}, {}, {}

    # A PHRASE USED IN TWO PLACES IS ONE PHRASE. "on", "off", "read",
    # "nothing" - a key per call site means a translator is handed the same
    # word eight times and can render it eight ways, and every one of those is
    # a chance for two lines of the same readout to disagree with each other.
    #
    # Hoisted to `common` rather than to whichever area happened to be read
    # first, because it belongs to none of them.
    seen = {}
    for rel in files:
        for _s, _e, text, _line, _kind in sites(rel)[1]:
            seen[text] = seen.get(text, 0) + 1

    shared = {}
    for text, n in seen.items():
        if n < 2:
            continue
        key, i = "common." + slug(text), 1
        while shared.get(key) not in (None, text):
            i += 1
            key = "common.%s%d" % (slug(text), i)
        shared[text] = key
        english[key] = text

    for rel in files:
        body, found = sites(rel)
        by_line = groups(body)
        area = area_of(rel)
        edits = []

        for start, stop, text, line, kind in found:
            group = by_line.get(line) or "misc"
            line_text = body[body.rfind("\n", 0, start) + 1:
                             body.find("\n", start)]
            argno = argument_index(body, start) if kind == "L" else 0
            leaf = leaf_for(line_text, text, argno)

            key = shared.get(text) or ("%s.%s.%s" % (area, group, leaf))

            # THE SAME PHRASE GETS THE SAME KEY, so a word used twice is
            # translated once - and two DIFFERENT phrases that landed on one
            # name are told apart rather than silently merged.
            if english.get(key) not in (None, text):
                n = used.get(key, 1) + 1
                used[key] = n
                base = key
                while english.get("%s%d" % (base, n)) not in (None, text):
                    n += 1
                key = "%s%d" % (base, n)

            english[key] = text
            edits.append((start, stop, key, text))

        plan[rel] = edits

    return plan, english


# ---------------------------------------------------------------------------
# writing
# ---------------------------------------------------------------------------

HEADER = '''--[[--------------------------------------------------------------------------
	AetherUI :: enUS

	THE ENGLISH, AND THE FILE TO EDIT IT IN.

	This is not generated. Correct a typo, reword a description, sharpen a
	sentence - here, and nothing else moves: the KEY is what the source asks
	for, and the key does not change when the words do. That is the whole
	reason the keys are names rather than the sentences themselves.

	It is also the file to paste into CurseForge's phrase importer, once, which
	is how the phrases get created over there. After that a translation
	submitted on the website reaches a release through the @localization@ block
	in each of the other ten files; nothing comes back here.

	ADDING ONE: put it here, then use it as L.area.group.leaf. The suite fails
	on a key the source asks for and this file has not got, and reports the
	other way round as dead weight.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = A.Phrases("enUS")

'''


def read_english():
    """What Locale/enUS.lua already says, so a second pass adds rather than
    replaces.

    THE FILE IS EDITED BY HAND, which is the whole point of the scheme - so a
    tool that rewrites it from scratch throws away every correction anybody has
    made, and on the second run threw away the four hundred and seventy-two
    keys the first run had put there.
    """
    path = os.path.join(ROOT, "Locale", "enUS.lua")
    if not os.path.exists(path):
        return {}
    with io.open(path, encoding='utf-8') as fh:
        body = fh.read()

    out = {}
    for m in re.finditer(r'L\["([^"]+)"\]\s*=\s*', body):
        stop, pieces, whole = i18n.chain(body, m.end())
        if whole and pieces:
            out[m.group(1)] = i18n.unescape("".join(pieces))
    return out


def write_english(english):
    """Locale/enUS.lua, grouped by area with the paths spelled out."""
    merged = read_english()
    # WHAT IS ALREADY THERE WINS. The English in that file is the edited
    # English; what this pass knows is only what the source happened to say
    # before it was rewritten.
    for key, text in english.items():
        merged.setdefault(key, text)
    english = merged

    out = [HEADER]
    last_area, last_group = None, None
    for key in sorted(english):
        bits = key.split(".")
        area = bits[0]
        group = ".".join(bits[:2])
        if area != last_area:
            out.append("\n-- %s %s\n\n" % (area, "-" * (72 - len(area))))
            last_area, last_group = area, None
        elif group != last_group:
            out.append("\n")
        last_group = group

        text = english[key].replace("\\", "\\\\").replace('"', '\\"')
        line = 'L["%s"] = "%s"\n' % (key, text)
        if len(line) <= 80:
            out.append(line)
        else:
            # Long ones are wrapped the way the rest of this addon wraps a
            # sentence, so the file can be read and edited rather than scrolled.
            out.append('L["%s"] =\n' % key)
            words, cur = text.split(" "), ""
            chunks = []
            for w in words:
                if len(cur) + len(w) + 1 > 66:
                    chunks.append(cur)
                    cur = w
                else:
                    cur = (cur + " " + w) if cur else w
            if cur:
                chunks.append(cur)
            for i, chunk in enumerate(chunks):
                join = "\t" if i == 0 else "\t\t.. "
                tail = "" if i == len(chunks) - 1 else " "
                out.append('%s"%s%s"\n' % (join, chunk, tail))

    path = os.path.join(ROOT, "Locale", "enUS.lua")
    with io.open(path, 'w', encoding='utf-8', newline='') as fh:
        fh.write("".join(out))


def rewrite(rel, edits):
    path = os.path.join(ROOT, rel)
    with io.open(path, encoding='utf-8') as fh:
        body = fh.read()
    for start, stop, key, _text in reversed(edits):
        body = body[:start] + "L." + key + body[stop:]
    with io.open(path, 'w', encoding='utf-8', newline='') as fh:
        fh.write(body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    files = i18n.sources()
    plan, english = name_everything(files)

    if args.dry:
        for rel in files:
            if not plan[rel]:
                continue
            print("== " + rel)
            for _s, _e, key, text in plan[rel]:
                print("   %-52s %s" % (key, text[:50]))
        print("\n%d phrases, %d keys" %
              (sum(len(v) for v in plan.values()), len(english)))
        return 0

    for rel in files:
        if plan[rel]:
            rewrite(rel, plan[rel])
    write_english(english)
    print("%d phrases, %d keys" %
          (sum(len(v) for v in plan.values()), len(english)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
