#!/usr/bin/env python3
"""Find the words we wrote, and put them where a translator can reach them.

    python Tools/i18n.py --report            what is left, by file
    python Tools/i18n.py --report Core/Options.lua   ... for one file
    python Tools/i18n.py --wrap  Core/Options.lua    rewrite one file's phrases
    python Tools/i18n.py --export            regenerate Locale/enUS.lua

WHY A TOOL AND NOT A SED. There are ten thousand quoted strings in this addon
and perhaps a tenth of them are words a human reads; the rest are frame names,
event names, texture paths, config keys, format specifiers and Lua identifiers.
Telling those apart by looking at the STRING is hopeless - "Bags" is a heading,
a module name and a saved-variable key, and it is spelled the same way in all
three. Telling them apart by their CALL SITE is not: a string being handed to
SetText is a string somebody reads, and a string being handed to GetModule is
not.

So this matches on the site rather than on the text, and it is deliberately
conservative: a site it does not recognise is left alone and reported, rather
than guessed at. A wrong guess here is a frame name run through a translation
table, which is a nil at some distance from the mistake.

THE KEY IS THE ENGLISH, which is the CurseForge and BigWigs packager
convention - see Core/Locale.lua.
"""
import argparse
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------------------
# what to read
# ---------------------------------------------------------------------------

# The changelog is release notes rather than interface: written fresh every
# version, and asking volunteers to translate a paragraph that will be replaced
# on Tuesday is how a translation project dies.
#
# Media and Palette are texture paths, font files and colour names. Locale is
# the phrase list itself.
SKIP_FILES = {
    os.path.join("Core", "Changelog.lua"),
    os.path.join("Core", "Media.lua"),
    os.path.join("Core", "Palette.lua"),
    os.path.join("Core", "Locale.lua"),
}


def sources():
    out = []
    for folder in ("Core", "Modules", os.path.join("Modules", "IFEC")):
        d = os.path.join(ROOT, folder)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if not name.endswith(".lua"):
                continue
            rel = os.path.join(folder, name)
            if rel in SKIP_FILES:
                continue
            out.append(rel)
    return out


# ---------------------------------------------------------------------------
# what counts as a phrase
# ---------------------------------------------------------------------------

# A Lua string literal in double quotes, with escapes. Single-quoted strings
# and [[long brackets]] are deliberately not matched: this addon does not use
# them for user text, and matching them would drag in every texture path.
STR = r'"((?:[^"\\]|\\.)*)"'

# THE CALL SITES THAT PUT WORDS ON A SCREEN.
#
# Each of these is a place where the argument named is read by a person. They
# are listed rather than inferred, and anything not on this list is reported
# instead of wrapped.
SITES = [
    # Drawing text
    (r'(:SetText\(\s*)' + STR, "SetText"),
    (r'(:SetFormattedText\(\s*)' + STR, "SetFormattedText"),
    (r'(:SetLabel\(\s*)' + STR, "SetLabel"),
    (r'(:Say\(\s*)' + STR, "Say"),
    (r'(:SetTooltip\(\s*)' + STR, "SetTooltip"),

    # Chat
    (r'(A:Print\(\s*)' + STR, "Print"),
    (r'(A\.Hi\(\s*)' + STR, "Hi"),
    (r'(A\.Val\(\s*)' + STR, "Val"),
    (r'(A\.Bad\(\s*)' + STR, "Bad"),
    (r'(A\.Gold\(\s*)' + STR, "Gold"),

    # Options tables, tour stops, tiles, cards - the fields that carry prose.
    (r'(\bname\s*=\s*)' + STR, "name"),
    (r'(\bdesc\s*=\s*)' + STR, "desc"),
    (r'(\blabel\s*=\s*)' + STR, "label"),
    (r'(\btip\s*=\s*)' + STR, "tip"),
    (r'(\bblurb\s*=\s*)' + STR, "blurb"),
    (r'(\bhead\s*=\s*)' + STR, "head"),
    (r'(\bbody\s*=\s*)' + STR, "body"),
    (r'(\bhint\s*=\s*)' + STR, "hint"),
    (r'(\btitle\s*=\s*)' + STR, "title"),
    (r'(\bword\s*=\s*)' + STR, "word"),
]

# AND THE SITES THAT ARE A POSITION RATHER THAN A NAME.
#
# Core/Options.lua does not write `name = "Scale"` four hundred times; it calls
# `toggle("Scale", "How big everything is", path)`, and the field is filled in
# by the builder. That is better for this than a literal field would be - the
# six builders can put their own arguments through L and no call site changes at
# all - but the master list still has to FIND the words, so the tool is told
# which arguments of which function are prose.
#
# Scoped per file, because `group` and `note` are ordinary enough words that a
# global rule would rewrite somebody else's function.
POSITIONAL = {
    os.path.join("Core", "Options.lua"): {
        "toggle": (1, 2), "range": (1, 2), "choice": (1, 2),
        "action": (1, 2), "header": (1,), "note": (1,), "group": (1,),
    },
}


def positional_sites(rel):
    """(regex, label) for each phrase argument of each builder in this file."""
    out = []
    for fn, positions in POSITIONAL.get(rel, {}).items():
        for pos in positions:
            # The opening paren, then pos-1 arguments we do not touch, then
            # ours. Each skipped argument is "anything that is not a comma or a
            # bracket", which is enough for the literal-first calls here.
            skip = r'(?:[^,()"]*,\s*)' * (pos - 1)
            out.append((r'(\b' + fn + r'\(\s*' + skip + r')' + STR,
                        "%s#%d" % (fn, pos)))
    return out


# AND WHAT A PHRASE IS NOT, whatever site it turns up at.
#
# These are the false positives the site list still lets through: a `name =` in
# an options table is prose, and a `name = "AetherUIPlayerFrame"` beside it is a
# frame. The rules are shape rules rather than a list of exceptions, so a new
# frame name does not need adding here.
NOT_A_PHRASE = [
    (re.compile(r'^\s*$'), "empty"),
    (re.compile(r'^[%|\\]'), "an escape or a colour code on its own"),
    # A single word with no spaces that is also an identifier: module keys,
    # option keys, frame names, event names, anchor points.
    (re.compile(r'^[A-Za-z0-9_]+$'), "one bare identifier"),
    (re.compile(r'^[A-Z][A-Za-z0-9_]*$'), "a name in CamelCase"),
    (re.compile(r'^[A-Z0-9_]+$'), "SHOUTING_CASE"),
    # Paths and files.
    (re.compile(r'[\\/]'), "a path"),
    (re.compile(r'\.(tga|blp|ttf|ogg|lua|xml)$', re.I), "a file"),
    # Format specifiers and markup with nothing else in them.
    (re.compile(r'^[%%\d\.\-\+ sdfxq]*$'), "nothing but a format specifier"),
    (re.compile(r'^\W+$'), "punctuation"),

    # A FRAGMENT IS REFUSED BY SHAPE, NOT BY SPELLING, and that is the rule
    # that matters most here - see `chain` below. This addon builds a lot of
    # chat output by concatenation, `A:Print("skin -> " .. name)`, and taking
    # the literal half of that gives a translator half a sentence with a
    # dangling arrow and no idea what follows it. Ninety-seven went through on
    # the first pass and every one was wrong.
    #
    # It was briefly done here instead, by refusing anything that ended in
    # whitespace or an arrow, and that was worse than useless: it refused the
    # fragments AND hid them, so the count of what still needed doing by hand
    # read six when it was a hundred. Whether a string is a fragment is a fact
    # about what is glued to it, which is a question about the source and not
    # about the string.
]

# Anything shorter than this is a fragment rather than a phrase: "on", "of",
# "s". Translating fragments is the mistake that makes a translated interface
# read like a ransom note.
MIN_LEN = 4


def is_phrase(text):
    if len(text) < MIN_LEN:
        return False, "shorter than %d characters" % MIN_LEN
    for rx, why in NOT_A_PHRASE:
        if rx.search(text):
            return False, why
    # It has to contain a letter of its OWN. Format specifiers are stripped
    # first, or the `s` in `%s` counts: `'%s'` is a helper that puts quotation
    # marks round something, it has no words in it at all, and it went into the
    # phrase list as one.
    if not re.search(r'[A-Za-z]', re.sub(r'%[-+ #0-9.]*[a-zA-Z]', '', text)):
        return False, "no words of its own - only format specifiers"
    return True, None


# ---------------------------------------------------------------------------
# reading a concatenation
# ---------------------------------------------------------------------------

COMMENT = re.compile(r'^\s*--')

# One Lua string literal, anchored wherever we start looking.
ONE = re.compile(STR)
# The join between two pieces, and any whitespace, newline or comment across it.
JOIN = re.compile(r'\s*(?:--[^\n]*\n\s*)*\.\.\s*(?:--[^\n]*\n\s*)*')


def unescape(text):
    """What the string actually says, for the phrase list."""
    return text.replace('\\"', '"')


def chain(body, at):
    """Read the concatenation that starts with a literal at `at`.

    Returns (end offset, [pieces], whole) where `whole` is True when every
    piece was a literal - which is the only case that can become one key.
    """
    pieces = []
    i = at
    while True:
        m = ONE.match(body, i)
        if not m:
            return i, pieces, False
        pieces.append(m.group(1))
        i = m.end()

        j = JOIN.match(body, i)
        if not j:
            return i, pieces, True
        # Something is glued on. Another literal continues the sentence;
        # anything else is a hole in it.
        if not ONE.match(body, j.end()):
            return i, pieces, False
        i = j.end()


def preceded_by_join(body, at):
    """Is this literal the tail of a concatenation rather than its head?

    The head is where a chain is read from, so a tail found on its own is one
    already accounted for - or one whose head was an expression, in which case
    it is part of a sentence with a hole in it either way.
    """
    before = body[max(0, at - 200):at]
    stripped = re.sub(r'--[^\n]*\n', '\n', before)
    return re.search(r'\.\.\s*$', stripped) is not None


def in_comment(body, at):
    line_start = body.rfind("\n", 0, at) + 1
    return COMMENT.match(body[line_start:at + 1]) is not None


def code_mask(body):
    """True at every offset that is real Lua rather than inside a string.

    WITHOUT THIS THE TOOL READS ITS OWN PATTERNS OUT OF STRING LITERALS. The
    field rules look for `head=` followed by a quote; a diagnostic that PRINTS
    "  head=" has exactly that shape, so the rule matched the CLOSING quote of
    that literal and took everything up to the next one - `.. tostring(x) ..` -
    as a phrase. Wrapping it wrote L[" into the middle of a string and the file
    stopped parsing, which is at least loud. The quieter version of the same
    mistake is a phrase list with Lua in it.

    One pass over the file, because "is this offset inside a string" is not a
    question a regex over a window can answer: it depends on every quote before
    it.
    """
    mask = bytearray(b"\x01" * len(body))
    i, n = 0, len(body)
    while i < n:
        c = body[i]
        if body.startswith("--", i):
            if body.startswith("--[[", i):
                stop = body.find("]]", i)
                stop = n if stop < 0 else stop + 2
            else:
                stop = body.find("\n", i)
                stop = n if stop < 0 else stop
            for k in range(i, stop):
                mask[k] = 0
            i = stop
        elif c == '"' or c == "'":
            quote, j = c, i + 1
            while j < n:
                if body[j] == "\\":
                    j += 2
                    continue
                if body[j] == quote or body[j] == "\n":
                    break
                j += 1
            # The quotes themselves stay code - the site regexes end on the
            # opening one - and what is between them does not.
            for k in range(i + 1, min(j, n)):
                mask[k] = 0
            i = j + 1
        elif body.startswith("[[", i):
            stop = body.find("]]", i)
            stop = n if stop < 0 else stop + 2
            for k in range(i, stop):
                mask[k] = 0
            i = stop
        else:
            i += 1
    return mask


def find(rel):
    """Every phrase site in one file.

    Yields (start, end, prefix_len, joined_text, whole). `whole` False means the
    site is a sentence with an expression in it and wants A.F by hand.
    """
    path = os.path.join(ROOT, rel)
    with io.open(path, encoding='utf-8') as fh:
        body = fh.read()

    mask = code_mask(body)

    seen = []
    for rx, site in SITES + positional_sites(rel):
        for m in re.finditer(rx, body):
            at = m.start(2) - 1          # the opening quote
            # THE SITE ITSELF HAS TO BE CODE. See code_mask: a diagnostic that
            # prints "  head=" has the shape of a field assignment, and reading
            # it as one wrote L[" into the middle of a string literal.
            if not mask[m.start(1)]:
                continue
            if in_comment(body, at):
                continue
            if preceded_by_join(body, at):
                continue
            stop, pieces, whole = chain(body, at)
            text = unescape("".join(pieces))
            ok, why = is_phrase(text)
            if not ok:
                continue
            seen.append((at, stop, m.start(1), text, whole, site))

    # A site can match two rules - `label = "x"` is both a field and, in
    # Options.lua, an argument - so the same span is found twice.
    seen.sort()
    out, last = [], -1
    for entry in seen:
        if entry[0] >= last:
            out.append(entry)
            last = entry[1]
    return body, out


def scan(rel):
    """The phrases in one file that a wrap would take, as (line, site, text)."""
    body, sites = find(rel)
    out = []
    for at, _stop, _pre, text, whole, site in sites:
        if not whole:
            continue
        out.append((body.count("\n", 0, at) + 1, site, text))
    return out


def holes(rel):
    """The sites that are a sentence with an expression in them."""
    body, sites = find(rel)
    out = []
    for at, _stop, _pre, text, whole, site in sites:
        if whole:
            continue
        out.append((body.count("\n", 0, at) + 1, site, text))
    return out


def wrapped(rel):
    """The phrases in one file that are already going through L."""
    path = os.path.join(ROOT, rel)
    with io.open(path, encoding='utf-8') as fh:
        body = fh.read()
    keys = set(unescape(k) for k in re.findall(r'\bL\[' + STR + r'\]', body))
    keys |= set(unescape(k) for k in re.findall(r'\bA\.F\(\s*' + STR, body))
    return keys


# ---------------------------------------------------------------------------
# writing
# ---------------------------------------------------------------------------

def wrap_file(rel):
    """Put every whole phrase in one file through L, in place."""
    body, sites = find(rel)

    edits = [(at, stop, text) for at, stop, _pre, text, whole, _site in sites
             if whole]
    if not edits:
        return 0

    # Back to front, so an earlier offset is still an earlier offset.
    for at, stop, text in reversed(edits):
        body = body[:at] + 'L["' + text.replace('"', '\\"') + '"]' + body[stop:]

    # AND L HAS TO BE IN SCOPE. Every file in this addon opens with the same
    # two-value vararg; the phrase table goes on the line after it, once,
    # wherever it is not there already.
    if not re.search(r'^local L\s*=\s*A\.L\s*$', body, re.M):
        m = re.search(r'^local ADDON, A = \.\.\.\s*$', body, re.M)
        if not m:
            raise SystemExit("%s: no `local ADDON, A = ...` to hang L off" % rel)
        body = body[:m.end()] + "\n\nlocal L = A.L" + body[m.end():]

    path = os.path.join(ROOT, rel)
    with io.open(path, 'w', encoding='utf-8', newline='') as fh:
        fh.write(body)
    return len(edits)


HEADER = '''--[[--------------------------------------------------------------------------
	AetherUI :: enUS

	GENERATED BY Tools/i18n.py --export. Do not edit: the next run overwrites it.

	THE MASTER LIST, and the file to paste into CurseForge's phrase importer -
	which is how the phrases get created over there, once. After that a
	translation submitted on the website reaches a release through the
	@localization@ block in each of the other ten files; nothing comes back
	here.

	Every entry maps a phrase to itself, and that is not redundant. A key with no
	entry falls back to its own English in Core/Locale.lua, so this file changes
	nothing at runtime - it exists so that the English is a LIST rather than
	something you have to grep the source for, and so the suite can check that
	the two agree.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = A.L

'''


def export():
    keys = set()
    for rel in sources():
        keys |= wrapped(rel)
    out = [HEADER]
    for key in sorted(keys):
        # RE-ESCAPED ON THE WAY OUT. The keys are held unescaped so that two
        # spellings of the same phrase compare equal; written back raw, a
        # phrase with a quotation mark in it closes its own string and the
        # whole file stops parsing.
        lit = key.replace("\\", "\\\\").replace('"', '\\"')
        out.append('L["%s"] = "%s"\n' % (lit, lit))
    path = os.path.join(ROOT, "Locale", "enUS.lua")
    with io.open(path, 'w', encoding='utf-8', newline='') as fh:
        fh.write("".join(out))
    return len(keys)


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--wrap", action="store_true")
    ap.add_argument("--export", action="store_true")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args()

    files = args.files or sources()

    if args.export:
        print("Locale/enUS.lua: %d phrases" % export())
        return 0

    if args.wrap:
        total = 0
        for rel in files:
            n = wrap_file(rel)
            total += n
            if n:
                print("%5d  %s" % (n, rel))
        print("%5d  total" % total)
        return 0

    grand, done, hand = 0, 0, 0
    for rel in files:
        left = scan(rel)
        gaps = holes(rel)
        have = wrapped(rel)
        grand += len(left)
        done += len(have)
        hand += len(gaps)
        if left or gaps:
            print("%5d left  %4d by hand  %4d done   %s"
                  % (len(left), len(gaps), len(have), rel))
            if args.files:
                for n, site, text in left:
                    print("   wrap %5d %-14s %s" % (n, site, text[:66]))
                for n, site, text in gaps:
                    print("   A.F  %5d %-14s %s" % (n, site, text[:66]))
    print("%5d left  %4d by hand  %4d done   TOTAL" % (grand, hand, done))
    return 0


if __name__ == "__main__":
    sys.exit(main())
