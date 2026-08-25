# -*- coding: utf-8 -*-
"""Zip an addon folder the way CurseForge wants it.

    python Tools/package.py E:\\src\\veoj\\AetherUI
    python Tools/package.py E:\\src\\veoj\\AetherUI-Packs\\AetherUI_IFEC_Vanilla

WHY THIS EXISTS WHEN .github/workflows/release.yml ALREADY BUILDS ONE.
CurseForge will not moderate a project until a file has been uploaded to it, and
it will not accept an upload from the API until it has been moderated. The only
way through that is to upload the first file BY HAND, and to do that you need a
zip on disk rather than one attached to a GitHub release that does not exist
yet - releases are deliberately manual here so that 1.0.0 can be the first one.

IT IS NOT A REPLACEMENT FOR THE PACKAGER. BigWigsMods/packager also rewrites
@project-version@, strips @debug@ blocks and resolves the @localization@ blocks
in Locale/ from the CurseForge phrase list. This does none of that, and does not
need to: nothing shipped carries a version or debug token (checked), and the
localization blocks are Lua comments that resolve to nothing - which is exactly
what ships today, unsubstituted, by choice. The day translations exist, the
workflow is what builds the release.

IT BUILDS FROM THE WORKING TREE, and the packager builds from a git checkout.
That difference is the one thing to keep in mind here: a file git ignores is
simply absent for the packager and is sitting right there for this, so anything
ignored-but-present must ALSO be named in .pkgmeta. Media/Screenshots was not,
and thirty-eight megabytes of full-size PNG shipped inside the addon.

WHAT SHIPS is `.pkgmeta`'s ignore list where there is one, and a plain sensible
default where there is not. Both always drop version-control furniture and the
build inputs, because a zip a player unpacks into Interface\\AddOns should hold
what the client loads and nothing else.
"""
import os
import re
import sys
import zipfile

# Never shipped, whatever the .pkgmeta says. VCS furniture, editor droppings,
# and pack.json - which is the INPUT Tools/content.py reads, not something the
# client has any use for.
ALWAYS = {
    ".git", ".github", ".claude", ".gitignore", ".gitattributes",
    ".pkgmeta", "pack.json", "__pycache__", ".DS_Store", "Thumbs.db",
    "desktop.ini",
}


def pkgmeta(folder):
    """`package-as` and `ignore` from a .pkgmeta beside or inside the folder.

    Read by hand rather than with a YAML parser: this file has two keys in it,
    and a dependency for two keys is a dependency to install on every machine
    that ever builds a zip.
    """
    path = os.path.join(folder, ".pkgmeta")
    if not os.path.isfile(path):
        return os.path.basename(folder.rstrip("\\/")), set()

    name, ignore, in_ignore = os.path.basename(folder.rstrip("\\/")), set(), False
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.strip().startswith("#") or not line.strip():
                continue
            m = re.match(r"package-as:\s*(\S+)", line)
            if m:
                name, in_ignore = m.group(1), False
                continue
            if re.match(r"ignore:\s*$", line.strip()):
                in_ignore = True
                continue
            m = re.match(r"\s+-\s*(\S+)", line)
            if in_ignore and m:
                ignore.add(m.group(1).strip("/\\").replace(chr(92)+chr(92), "/"))
                continue
            if not line[:1].isspace():
                in_ignore = False
    return name, ignore


def join(rel, name):
    return name if not rel else rel + "/" + name


def ignored(rel, drop):
    """Is this path, relative to the addon root, on the drop list?

    TWO SHAPES OF ENTRY, because .pkgmeta uses both. A bare name like `Tools` or
    `.git` matches wherever it appears; a path like `Media/Screenshots` matches
    only from the root, which is the whole point of writing it that way.

    The first version of this compared single path COMPONENTS, so a two-part
    entry could never match anything and `Media/Screenshots` was silently
    ignored - which is a drop list that quietly does not drop, the worst
    possible failure for this particular file.
    """
    parts = rel.split("/")
    if parts[-1] in drop:
        return True
    return any("/".join(parts[:i + 1]) in drop for i in range(len(parts)))


def build(folder, out_dir):
    folder = os.path.abspath(folder)
    name, ignore = pkgmeta(folder)
    drop = ALWAYS | ignore

    toc = os.path.join(folder, name + ".toc")
    version = "0.0.0"
    if os.path.isfile(toc):
        with open(toc, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"##\s*Version:\s*(\S+)", line)
                if m:
                    version = m.group(1)
                    break
    else:
        sys.exit("no %s.toc in %s - is that an addon folder?" % (name, folder))

    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "%s-%s.zip" % (name, version))

    files, raw = [], 0
    for root, dirs, names in os.walk(folder):
        rel = os.path.relpath(root, folder).replace("\\", "/")
        rel = "" if rel == "." else rel
        dirs[:] = sorted(d for d in dirs if not ignored(join(rel, d), drop))
        for f in sorted(names):
            if ignored(join(rel, f), drop):
                continue
            full = os.path.join(root, f)
            files.append(full)
            raw += os.path.getsize(full)

    # DEFLATED, and it is worth it even here: the audio is already compressed
    # and will not budge, but the magazine pages are uncompressed 32-bit TGA and
    # halve.
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for full in files:
            arc = os.path.join(name, os.path.relpath(full, folder))
            z.write(full, arc.replace("\\", "/"))

    size = os.path.getsize(out)
    print("  %s" % out)
    print("  %s %s - %d files, %.1f MB packed (%.1f MB on disk)"
          % (name, version, len(files), size / 1048576.0, raw / 1048576.0))
    # CurseForge refuses anything over 200 MB through the web uploader.
    if size > 200 * 1048576:
        print("  !! over CurseForge's 200 MB limit for a single file")
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.environ.get("AETHER_DIST") or os.path.join(
        os.path.dirname(root), "dist")
    for folder in sys.argv[1:]:
        build(folder, out_dir)


if __name__ == "__main__":
    main()
