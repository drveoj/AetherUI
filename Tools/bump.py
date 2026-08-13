#!/usr/bin/env python3
"""Bump the version and write the release notes, in one step.

    python Tools/bump.py --minor "Drag the rail to re-dock the Toolbox."
    python Tools/bump.py --build "Fix the chat grip on a docked window."
    python Tools/bump.py --major "The action bars land." "Keybind mode."

The two are one command deliberately. They were two hand-edits in two files,
and nothing checked that either had happened - so the drawer would confidently
show the previous release's news with no unread dot on it. The harness now
refuses a build whose newest changelog entry does not match ``## Version`` in
the .toc, which makes forgetting a failed test rather than a shipped bug.

major   a release with new features in it
minor   accumulated fixes and small enhancements
build   hotfixes between the two

Notes are written for the PLAYER, present tense, about what they can now do or
now see. "Refactored LayoutContent" is what the commit message is for.

Bytes in, bytes out: both files are CRLF and this must not rewrite the endings
of every line it did not touch.
"""

import argparse
import datetime
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOC = ROOT / "AetherUI.toc"
LOG = ROOT / "Core" / "Changelog.lua"

VERSION_RE = re.compile(rb"^(##\s*Version:\s*)(\S+)\s*$", re.MULTILINE)
ANCHOR = b"A.CHANGELOG = {\r\n"
ANCHOR_LF = b"A.CHANGELOG = {\n"


def read_version() -> tuple[int, int, int]:
    m = VERSION_RE.search(TOC.read_bytes())
    if not m:
        sys.exit("bump: no '## Version:' line in %s" % TOC)
    parts = m.group(2).decode("ascii").split(".")
    while len(parts) < 3:
        parts.append("0")
    try:
        return tuple(int(p) for p in parts[:3])  # type: ignore[return-value]
    except ValueError:
        sys.exit("bump: version %r is not major.minor.build" % m.group(2).decode())


def next_version(cur: tuple[int, int, int], part: str) -> str:
    major, minor, build = cur
    if part == "major":
        return "%d.0.0" % (major + 1)
    if part == "minor":
        return "%d.%d.0" % (major, minor + 1)
    return "%d.%d.%d" % (major, minor, build + 1)


def write_toc(new: str) -> None:
    data = TOC.read_bytes()
    data, n = VERSION_RE.subn(lambda m: m.group(1) + new.encode("ascii"), data, count=1)
    if n != 1:
        sys.exit("bump: could not rewrite the version line")
    TOC.write_bytes(data)


def write_changelog(new: str, date: str, lines: list[str]) -> None:
    data = LOG.read_bytes()
    anchor = ANCHOR if ANCHOR in data else ANCHOR_LF
    if anchor not in data:
        sys.exit("bump: no 'A.CHANGELOG = {' in %s" % LOG)
    eol = b"\r\n" if anchor is ANCHOR else b"\n"

    body = [b"\t{", b"\t\tversion = \"%s\"," % new.encode("ascii"),
            b"\t\tdate    = \"%s\"," % date.encode("ascii"),
            b"\t\tlines   = {"]
    for line in lines:
        # Escape only what Lua's short-string syntax cannot carry raw. The notes
        # are prose, so in practice this is quotes and the odd backslash.
        esc = line.replace("\\", "\\\\").replace('"', '\\"')
        body.append(b"\t\t\t\"%s\"," % esc.encode("utf-8"))
    body += [b"\t\t},", b"\t},"]

    entry = eol.join(body) + eol
    LOG.write_bytes(data.replace(anchor, anchor + entry, 1))


def main() -> None:
    ap = argparse.ArgumentParser(description="Bump the version and write the notes.")
    part = ap.add_mutually_exclusive_group(required=True)
    part.add_argument("--major", action="store_const", const="major", dest="part")
    part.add_argument("--minor", action="store_const", const="minor", dest="part")
    part.add_argument("--build", action="store_const", const="build", dest="part")
    ap.add_argument("notes", nargs="+", help="one or more note lines, player-facing")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD (default: today)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    cur = read_version()
    new = next_version(cur, args.part)
    date = args.date or datetime.date.today().isoformat()

    print("  %s   %d.%d.%d -> %s" % (TOC.name, cur[0], cur[1], cur[2], new))
    print("  %s   + entry, %d line%s"
          % (LOG.name, len(args.notes), "" if len(args.notes) == 1 else "s"))
    # ASCII, not a middle dot. The Windows console here is cp1252 and renders
    # anything else as a replacement character, which looks like the tool has
    # mangled the note it is about to write.
    for line in args.notes:
        print("      - %s" % line)

    if args.dry_run:
        print("  (dry run, nothing written)")
        return

    write_toc(new)
    write_changelog(new, date, args.notes)
    print("\nNow run the suite - it checks the two agree:\n"
          "  luajit Tools/harness.lua")


if __name__ == "__main__":
    main()
