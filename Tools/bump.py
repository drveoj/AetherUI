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

THE SUITE MUST BE GREEN. This runs it first and writes nothing if it is not. A
version is a claim that the build works, and 0.4.10 was cut while a core file
had a syntax error that would have stopped the addon loading at all - the
harness caught it a second later, by which time the version was already
written. --force exists for exactly one case: the harness refuses a build whose
.toc and changelog disagree, and this is the tool that repairs that.

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
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOC = ROOT / "AetherUI.toc"
LOG = ROOT / "Core" / "Changelog.lua"

MD = ROOT / "CHANGELOG.md"


def write_markdown() -> None:
    """Render Core/Changelog.lua to CHANGELOG.md at the repository root.

    A THIRD FILE, and not for taste. BigWigsMods/packager builds a GitHub
    release's body from the git log since the previous tag unless a manual
    changelog is set in .pkgmeta - and with every pre-1.0 tag deleted, "since
    the previous tag" was all three hundred and seven commits. That came to more
    than the 125,000 characters GitHub accepts and the release failed outright.

    It is also not what belongs on a public release page. Those messages are
    working notes, written to the next person to open the file.

    GENERATED, never edited, for exactly the reason the .toc and Changelog.lua
    are written together: a version that has to be typed into three places is a
    version that will be wrong in one of them.
    """
    data = LOG.read_text(encoding="utf-8")
    entries = re.findall(
        r'\{\s*version\s*=\s*"([^"]+)",\s*date\s*=\s*"([^"]+)",'
        r'\s*lines\s*=\s*\{(.*?)\n\t\t\},',
        data, re.S)

    out = ["# AetherUI", ""]
    for version, date, body in entries:
        out += ["## %s - %s" % (version, date), ""]
        for line in re.findall(r'"((?:[^"\\]|\\.)*)"', body):
            out.append("- " + line.replace('\\"', '"').replace("\\\\", "\\"))
        out.append("")

    MD.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8", newline="\n")


VERSION_RE = re.compile(rb"^(##\s*Version:\s*)(\S+)\s*$", re.MULTILINE)
ANCHOR = b"A.CHANGELOG = {\r\n"
ANCHOR_LF = b"A.CHANGELOG = {\n"


def suite_is_green() -> tuple[bool, str]:
    """Run the harness and say whether it passed.

    A version is a claim that this build works. Cutting one over a red suite
    puts that claim in the .toc, in the changelog, and in front of the player -
    and it has happened: 0.4.10 was written while Core/Options.lua had a syntax
    error in it, which meant the addon would not have loaded at all. The
    harness caught it a second later. The version had already been bumped.
    """
    lua = shutil.which("luajit") or shutil.which("lua")
    if not lua:
        return False, ("no luajit on PATH, so the suite cannot be run - and a"
                       " version nobody checked is exactly what this guards")

    try:
        done = subprocess.run([lua, "Tools/harness.lua"], cwd=ROOT,
                              capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        return False, "the suite did not finish"

    out = (done.stdout or "") + (done.stderr or "")
    if done.returncode == 0 and "ALL CHECKS PASSED" in out:
        return True, ""

    # The last few lines are the failures, or the parse error that stopped it.
    tail = [ln for ln in out.splitlines() if ln.strip()][-12:]
    return False, chr(10).join("    " + ln for ln in tail)


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
    write_markdown()


def main() -> None:
    ap = argparse.ArgumentParser(description="Bump the version and write the notes.")
    part = ap.add_mutually_exclusive_group(required=True)
    part.add_argument("--major", action="store_const", const="major", dest="part")
    part.add_argument("--minor", action="store_const", const="minor", dest="part")
    part.add_argument("--build", action="store_const", const="build", dest="part")
    ap.add_argument("notes", nargs="+", help="one or more note lines, player-facing")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD (default: today)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true",
                    help="bump over a RED suite. For the one case that would"
                         " otherwise deadlock: the harness refuses a build whose"
                         " .toc and changelog disagree, and this is the tool"
                         " that repairs that. Nothing else.")
    args = ap.parse_args()

    # GREEN FIRST, before a byte is written. A version is a claim that the
    # build works, and this tool has already put one in front of a player over
    # a core file that did not parse.
    if not args.dry_run:
        ok, why = suite_is_green()
        if not ok and not args.force:
            print("bump: REFUSED - the suite is not green.", file=sys.stderr)
            print("", file=sys.stderr)
            print(why, file=sys.stderr)
            print("", file=sys.stderr)
            print("  Fix it, or pass --force if the failure IS the version"
                  " being out of step -", file=sys.stderr)
            print("  which is the one thing this tool is needed to repair.",
                  file=sys.stderr)
            sys.exit(1)
        if not ok:
            print("  !! FORCED over a red suite. These notes are a claim that"
                  " nothing has checked.")
            print("")

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
    print("")
    print("The suite was green before this. Run it once more before you push -")
    print("it also checks that these two files agree:")
    print("  luajit Tools/harness.lua")


if __name__ == "__main__":
    main()
