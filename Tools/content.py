"""Build an IFEC content pack from a folder of audio.

    python Tools/content.py E:\\src\\veoj\\AetherUI-Packs\\AetherUI_IFEC_Vanilla

THE CUT AUDIO IS DERIVED AND GIT-IGNORED, so a fresh clone of the packs repo
has the manifest, the magazines and no music at all - and nothing says so:
PlaySoundFile answers false for every segment and the console sits in its
muted state, which on screen is a play button that does nothing. Run this
after cloning. The Stop hook that deploys the packs checks for it too.

Reads pack.json from the pack folder, copies the declared audio in, probes every
file for its true length and writes Content.lua and the .toc. Run it again after
adding or replacing a track; the whole pack is regenerated from the source, so
the generated files are never edited by hand.

WHY THIS EXISTS AT ALL: the client has no playback-finished callback for a file
path, so the console predicts the end of a segment from the duration in the
manifest. A hand-typed number that is a second short clips the last second of
the track every time it plays, and a second long leaves a second of silence. The
granule position in the container is the only answer that is exactly right.

Item ids are derived from the source filename and are what saved progress is
keyed on, so RENAMING A SOURCE FILE FORGETS WHERE THE PLAYER WAS IN IT. That is
the right trade - the alternative is a hand-kept id list that drifts out of step
with the folder - but it is worth knowing before a tidy-up.
"""

import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oggprobe

def digest(path):
    """What a file actually contains, for deciding whether to copy it again.

    NOT ITS SIZE. Every uncompressed 1024x1024 TGA is exactly 3145772 bytes -
    the format has no compression and the dimensions do not change - so a size
    comparison across a folder of magazine pages compares a constant with
    itself and answers "unchanged" for a whole reissue. Sixteen new pages were
    already sitting in the source with the old ones still shipping.
    """
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def copy_if_changed(src, dest):
    """Copy `src` over `dest` unless they already hold the same bytes."""
    if os.path.exists(dest) and digest(src) == digest(dest):
        return False
    shutil.copy2(src, dest)
    return True


AUDIO_DIR = os.path.join("Media", "Audio")
MAG_DIR   = os.path.join("Media", "Magazines")

# The separator the CLIENT wants, which is not os.sep: this tool has to emit
# the same manifest whichever machine runs it, and a Lua texture path with
# forward slashes in it is a path the client will not resolve.
TEX_SEP = chr(92)


# ---------------------------------------------------------------------------
# naming
# ---------------------------------------------------------------------------

def split_name(filename):
    """"Big_Drum_Deep_Water-The Mudfoot Kings.ogg" -> title, artist.

    The convention the tracks arrive in: underscores are the title's spaces and
    the first hyphen ends the title. Split on the FIRST hyphen rather than the
    last, because an artist is far more likely to carry one than a title is.

    Capitalisation is left exactly as written. Title-casing it would have to
    guess at "and", "of", "the", and a guess that is wrong is wrong on the front
    of the console for a whole flight.
    """
    stem = os.path.splitext(os.path.basename(filename))[0]
    title, sep, artist = stem.partition("-")
    return title.replace("_", " ").strip(), (artist.strip() if sep else "")


def slug(text):
    """A filename and an id the client and the save file can both hold."""
    out = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    return out or "track"


# ---------------------------------------------------------------------------
# reading the folder
# ---------------------------------------------------------------------------

def collect_music(spec, seen_ids):
    """Every track in the source folder, probed, in filename order.

    Alphabetical rather than as the filesystem hands them over: the manifest
    order is the order the console plays them in when it is filling a programme,
    and an order that depends on when a file was written reshuffles a season for
    nobody's benefit.
    """
    source = spec["source"]
    if not os.path.isdir(source):
        raise SystemExit("no such music folder: " + source)

    overrides = spec.get("overrides", {})
    tracks = []

    for name in sorted(os.listdir(source)):
        if not name.lower().endswith(".ogg"):
            continue

        path = os.path.join(source, name)
        title, artist = split_name(name)
        fix = overrides.get(name, {})
        title = fix.get("title", title)
        artist = fix.get("artist", artist)

        item_id = fix.get("id") or slug(title)
        if item_id in seen_ids:
            raise SystemExit("two tracks want the id '%s' - one needs an "
                             "override in pack.json" % item_id)
        seen_ids.add(item_id)

        # Rounded DOWN to a whole second, not to the nearest. Ending a segment
        # a fraction early is a fraction of the tail lost under the next track's
        # opening; ending it late is audible silence, and the console has no way
        # to tell that apart from a programme that has stopped.
        seconds = int(oggprobe.duration(path))

        tracks.append({
            "id": item_id,
            "title": title,
            "artist": artist,
            "duration": seconds,
            "file": slug(title) + ".ogg",
            "source": path,
            # Set later, by the sync pass that actually cuts them: chunking
            # shells out to ffmpeg and this loop only reads the folder.
            "chunk": fix.get("chunk") or spec.get("chunk"),
            "overlap": fix.get("overlap") or spec.get("overlap"),
            "chunks": None,
        })

    if not tracks:
        raise SystemExit("no .ogg files in " + source)
    return tracks


# ---------------------------------------------------------------------------
# chunking
#
# THE ONLY WAY TO GET A PAUSE. There is no pause, no resume and no seek in this
# client's sound API - a handle supports exactly one verb, stop, and stopping is
# destructive. What there IS, because the console already needs it for
# chaptered episodes, is a scheduler that plays one file after another against a
# clock. Cut a track into three-second pieces and that scheduler synthesises all
# three missing verbs at three-second granularity: pause is stop-and-remember,
# resume is play-from-the-remembered-piece, and a seek is arithmetic.
#
# THE DURATIONS MUST KEEP THEIR DECIMALS. A whole track rounded down to the
# second loses at most a second, once. A chunk rounded down loses eight
# milliseconds SIXTY TIMES, each one a cut in the middle of the music.
#
# -reset_timestamps is not optional: without it ffmpeg's segment muxer leaves
# the ORIGINAL absolute timestamps in each piece's granule positions, so every
# chunk claims to end at its position in the source and every duration read off
# one is the elapsed time rather than the length.
# ---------------------------------------------------------------------------

CHUNK_Q = "6"          # libvorbis quality; ~10% larger than the source at 160k

# How much of the NEXT piece is also in this one. The pieces are crossfaded
# across this window rather than butted together.
#
# WHY A CROSSFADE AT ALL: butted together, every boundary is a step in the
# waveform and a step is a click. Sixty of them a track is a metronome. And the
# scheduler made it worse by stopping the outgoing handle to start the next -
# a hard cut mid-sample, which is the loudest kind of step there is.
#
# WHY IT IS TRANSPARENT: both pieces carry the SAME audio across the overlap, so
# a linear fade out and a linear fade in sum to exactly one. Not approximately -
# g + (1 - g) = 1 at every sample. There is nothing to hear.
#
# WHY IT IS THIS LONG: the client fires timers on frame boundaries, so the
# incoming piece can be a frame late - seven milliseconds at a hundred and forty
# frames, sixteen at sixty. Late, the two ramps no longer line up and the sum
# dips. The dip is that lateness divided by this window, so a quarter of a
# second turns a sixteen-millisecond slip into a six per cent wobble. A
# thirty-millisecond window would turn the same slip into a hole.
CHUNK_OVERLAP = 0.25


def chunk_track(source, dest_dir, seconds, overlap=CHUNK_OVERLAP):
    """Split `source` into crossfaded pieces under `dest_dir`.

    Returns [(filename, stride), ...] in playing order, where `stride` is when
    the NEXT piece starts rather than how long the file is - the file is
    `overlap` longer than that, and those last milliseconds are the fade the
    next piece fades up through.
    """
    if shutil.which("ffmpeg") is None:
        raise SystemExit("chunking needs ffmpeg on PATH")

    if os.path.isdir(dest_dir):
        for name in os.listdir(dest_dir):
            if name.lower().endswith(".ogg"):
                os.remove(os.path.join(dest_dir, name))
    os.makedirs(dest_dir, exist_ok=True)

    total = oggprobe.duration(source)

    # WALKED, not divided. Dividing the length by the stride leaves whatever is
    # left over as a final piece of any size - including two hundredths of a
    # second - and worse, leaves the piece BEFORE it without enough track behind
    # it to carry the overlap, so it comes out short and hands over into
    # silence. The last piece absorbs the remainder instead: it is between one
    # and two strides long and it is the only one with no fade to hand over to.
    starts, at = [], 0.0
    while total - at > seconds + overlap:
        starts.append(at)
        at = at + seconds
    starts.append(at)

    out = []
    for i, start in enumerate(starts):
        last = (i == len(starts) - 1)
        want = (total - start) if last else (seconds + overlap)
        if want <= 0:
            break

        fades = []
        if i > 0:
            fades.append("afade=t=in:st=0:d=%.4f:curve=tri" % overlap)
        if not last:
            fades.append("afade=t=out:st=%.4f:d=%.4f:curve=tri" % (seconds, overlap))

        name = "c-%03d.ogg" % i
        cmd = ["ffmpeg", "-v", "error", "-y",
               "-ss", "%.4f" % start, "-t", "%.4f" % want, "-i", source]

        if fades:
            cmd += ["-af", ",".join(fades)]
        cmd += ["-c:a", "libvorbis", "-q:a", CHUNK_Q,
                os.path.join(dest_dir, name)]
        subprocess.run(cmd, check=True)

        made = oggprobe.duration(os.path.join(dest_dir, name))
        # The stride is what was ASKED for, not what came back. Every file but
        # the last is a crossfade window longer than its share of the track, and
        # measuring it would schedule the next piece after the fade instead of
        # through it.
        out.append((name, made if last else float(seconds)))

    if not out:
        raise SystemExit("ffmpeg produced no chunks for " + source)
    return out


# ---------------------------------------------------------------------------
# magazines
# ---------------------------------------------------------------------------

def collect_magazines(spec, seen_ids):
    """Every issue under the source folder, as <publication>/<issue>/page-NN.tga.

    PAGES ARE IMAGES, not copy. A magazine is laid out - masthead, columns,
    pull-quotes, art - and rebuilding that from text in a Lua frame would be
    writing a typesetter. One 1024 texture a page is the whole design, and the
    reader's job shrinks to turning them.

    TGA ONLY. The client reads .tga and .blp for an addon texture and nothing
    else; the .png beside each one is the source the page was drawn from and has
    no business being shipped.
    """
    source = spec.get("source")
    if not source:
        return []
    if not os.path.isdir(source):
        raise SystemExit("no such magazine folder: " + source)

    titles = spec.get("titles", {})
    issues = []

    for pub in sorted(os.listdir(source)):
        pub_dir = os.path.join(source, pub)
        if not os.path.isdir(pub_dir):
            continue

        for issue in sorted(os.listdir(pub_dir)):
            issue_dir = os.path.join(pub_dir, issue)
            if not os.path.isdir(issue_dir):
                continue

            pages = sorted(n for n in os.listdir(issue_dir)
                           if n.lower().endswith(".tga"))
            if not pages:
                continue

            item_id = slug(issue)
            if item_id in seen_ids:
                raise SystemExit("two issues want the id '%s'" % item_id)
            seen_ids.add(item_id)

            issues.append({
                "id": item_id,
                "masthead": pub,
                "title": titles.get(issue) or issue.replace("_", " ").title(),
                "folder": issue,
                "pages": pages,
                "source": issue_dir,
            })

    return issues


def sync_magazines(pack_dir, issues):
    """Copy the pages in, and make the folder match what the manifest names."""
    root = os.path.join(pack_dir, MAG_DIR)
    wanted = set()

    for issue in issues:
        dest = os.path.join(root, issue["folder"])
        os.makedirs(dest, exist_ok=True)
        for page in issue["pages"]:
            wanted.add(os.path.join(issue["folder"], page))
            if copy_if_changed(os.path.join(issue["source"], page),
                               os.path.join(dest, page)):
                issue.setdefault("updated", 0)
                issue["updated"] += 1

    removed = []
    if os.path.isdir(root):
        for folder in sorted(os.listdir(root)):
            sub = os.path.join(root, folder)
            if not os.path.isdir(sub):
                continue
            for name in sorted(os.listdir(sub)):
                if os.path.join(folder, name) not in wanted:
                    os.remove(os.path.join(sub, name))
                    removed.append(os.path.join(folder, name))
            if not os.listdir(sub):
                os.rmdir(sub)
    return removed


# ---------------------------------------------------------------------------
# writing
# ---------------------------------------------------------------------------

def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_content(pack_dir, pack, tracks, mags):
    packId = pack["packId"]
    out = []
    w = out.append

    w("--[[--------------------------------------------------------------------------")
    w("\tAetherUI IFEC :: %s" % pack.get("displayName", packId))
    w("")
    w("\tGENERATED BY Tools/content.py. Do not edit: the next run overwrites it.")
    w("\tDurations are read from each file's Ogg granule position, which is the")
    w("\tsample count, so they are the file's own answer rather than an estimate.")
    w("----------------------------------------------------------------------------]]")
    w("")
    w("local AUDIO = [[Interface\\AddOns\\%s\\Media\\Audio\\]]" % packId)
    w("local MAGS  = [[Interface\\AddOns\\%s\\Media\\Magazines\\]]" % packId)
    w("")
    w("local manifest = {")
    w("\tpackId      = %s," % lua_string(packId))
    w("\tapiVersion  = %d," % pack.get("apiVersion", 1))
    w("\tseasonIndex = %d," % pack.get("seasonIndex", 1))
    w("\tdisplayName = %s," % lua_string(pack.get("displayName", packId)))
    w("")
    w("\titems = {")

    for t in tracks:
        w("\t\t{")
        w("\t\t\tid       = %s," % lua_string(t["id"]))
        w("\t\t\ttype     = \"music\",")
        w("\t\t\ttitle    = %s," % lua_string(t["title"]))
        if t["artist"]:
            w("\t\t\tartist   = %s," % lua_string(t["artist"]))
        w("\t\t\ttotalDuration = %d," % t["duration"])
        if t.get("chunks"):
            folder = os.path.splitext(t["file"])[0]
            w("\t\t\t-- CHUNKED, which is what buys a pause: there is no pause in")
            w("\t\t\t-- this client's sound API, so the console's own segment")
            w("\t\t\t-- chaining stands in for one at this granularity.")
            w("\t\t\t--")
            w("\t\t\t-- CROSSFADED, because butted together every boundary is a")
            w("\t\t\t-- step in the waveform and a step is a click. Each piece")
            w("\t\t\t-- carries the next one's first %.0fms with a fade baked" % (t["overlap"] * 1000))
            w("\t\t\t-- into it, and `duration` is when the NEXT piece starts")
            w("\t\t\t-- rather than how long this file is - so playback hands")
            w("\t\t\t-- over THROUGH the fade rather than after it.")
            w("\t\t\toverlap  = %.4f," % t["overlap"])
            w("\t\t\tsegments = {")
            for name, dur in t["chunks"]:
                w("\t\t\t\t{ file = AUDIO .. %s, duration = %.4f },"
                  % (lua_string(folder + TEX_SEP + name), dur))
            w("\t\t\t},")
        else:
            w("\t\t\tsegments = { { file = AUDIO .. %s, duration = %d } },"
              % (lua_string(t["file"]), t["duration"]))
        w("\t\t},")

    for m in mags:
        w("\t\t{")
        w("\t\t\tid       = %s," % lua_string(m["id"]))
        w('\t\t\ttype     = "gossip",')
        w("\t\t\tmasthead = %s," % lua_string(m["masthead"]))
        w("\t\t\ttitle    = %s," % lua_string(m["title"]))
        w("\t\t\tpages    = {")
        for page in m["pages"]:
            # NO EXTENSION on a texture path. The client resolves one without,
            # and Blizzard's own paths never carry it.
            stem = os.path.splitext(page)[0]
            w('				MAGS .. %s,' % lua_string(m['folder'] + TEX_SEP + stem))
        w("\t\t\t},")
        w("\t\t},")

    w("\t},")
    w("}")
    w("")
    w("-- THE HANDSHAKE, BOTH WAYS ROUND. Addon load order is not guaranteed and")
    w("-- OptionalDeps only nudges it: if the console is already up we register")
    w("-- straight into it, and if it is not we leave the manifest where it will look.")
    w("if AetherUI_IFEC and AetherUI_IFEC.Register then")
    w("\tAetherUI_IFEC.Register(manifest)")
    w("else")
    w("\tAetherUI_IFEC_Pending = AetherUI_IFEC_Pending or {}")
    w("\tAetherUI_IFEC_Pending[#AetherUI_IFEC_Pending + 1] = manifest")
    w("end")
    w("")

    path = os.path.join(pack_dir, "Content.lua")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out))
    return path


def write_credits(pack_dir, pack):
    """CREDITS.txt, from pack.json's `credits` block.

    A REQUIREMENT, not a courtesy. CurseForge's moderation policy: "Projects may
    include music only if the author owns it or has redistribution rights.
    Attribution must be provided when submitting the project." A pack is mostly
    audio, so the provenance of that audio travels with it rather than living
    only in a store description somebody has to go and find.

    Plain text rather than markdown: this sits in an addon folder next to a .toc
    and a .lua, and the person most likely to open it is doing so in whatever
    the operating system opens .txt with.

    Written only when pack.json has something to say. A generated file full of
    headings and no content is worse than no file.
    """
    credits = pack.get("credits")
    if not credits:
        return None

    name = pack.get("displayName", pack["packId"])
    out = ["%s" % name, "=" * len(name), ""]
    if credits.get("summary"):
        out += [credits["summary"], ""]
    for section in credits.get("sections", []):
        out += [section["title"], "-" * len(section["title"])]
        out += [line for line in section.get("lines", [])]
        out += [""]

    path = os.path.join(pack_dir, "CREDITS.txt")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out).rstrip() + "\n")
    return path


def write_toc(pack_dir, pack):
    packId = pack["packId"]
    lines = [
        "## Interface: %s" % pack.get("interface", "11509"),
        "## Title: Aether|cff9d7bffUI|r IFEC: %s" % pack.get("displayName", packId),
        "## Notes: %s" % pack.get("notes", "Content for the in-flight console."),
        "## Author: %s" % pack.get("author", "DrVeoj"),
        "## Version: %s" % pack.get("version", "1.0.0"),
        "## X-Category: Interface Enhancements",
    ]
    # The CurseForge project, when the pack has one. Each pack is its own
    # project over there - they are separate addons with separate folders - so
    # the id belongs in pack.json beside the rest of the pack's identity rather
    # than anywhere in here.
    if pack.get("curseProjectId"):
        lines += [
            "# The CurseForge project. The packager needs this to upload at all.",
            "## X-Curse-Project-ID: %s" % pack["curseProjectId"],
        ]
    lines += [
        "",
        "# A HARD DEPENDENCY. Without AetherUI this addon is a hundred and fifty",
        "# megabytes that do nothing at all - there is no console to play it in -",
        "# so the client should say so in the addon list rather than load it into",
        "# silence. Disabling AetherUI disables this with it, which is right.",
        "#",
        "# It is a load-order guarantee as well, but nothing depends on that: the",
        "# registration handshake in Content.lua works whichever loads first, and",
        "# has to, because a pack installed later arrives after login.",
        "## Dependencies: AetherUI",
        "",
        "Content.lua",
        "",
    ]
    path = os.path.join(pack_dir, packId + ".toc")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    return path


def sync_audio(pack_dir, tracks):
    """Copy what the manifest names, and remove what it no longer does.

    The folder is MADE TO MATCH rather than added to. A track dropped from a
    season otherwise stays on disk forever, and the next person to look at the
    folder cannot tell which files the pack actually serves.
    """
    dest = os.path.join(pack_dir, AUDIO_DIR)
    os.makedirs(dest, exist_ok=True)

    wanted = set()
    for t in tracks:
        if t.get("chunk"):
            # A FOLDER PER CHUNKED TRACK, so the pieces cannot be mistaken for
            # tracks of their own by anything walking this directory.
            folder = os.path.splitext(t["file"])[0]
            t["overlap"] = t.get("overlap") or CHUNK_OVERLAP
            t["chunks"] = chunk_track(t["source"],
                                      os.path.join(dest, folder), t["chunk"],
                                      t["overlap"])
            t["duration"] = int(sum(d for _, d in t["chunks"]))
            for name, _ in t["chunks"]:
                wanted.add(os.path.join(folder, name))
            continue

        wanted.add(t["file"])
        copy_if_changed(t["source"], os.path.join(dest, t["file"]))

    removed = []
    for name in sorted(os.listdir(dest)):
        full = os.path.join(dest, name)
        if os.path.isdir(full):
            # A chunk folder for a track that is no longer chunked, or no longer
            # here at all. chunk_track empties the ones it owns before it cuts.
            for piece in sorted(os.listdir(full)):
                if os.path.join(name, piece) not in wanted:
                    os.remove(os.path.join(full, piece))
                    removed.append(os.path.join(name, piece))
            if not os.listdir(full):
                os.rmdir(full)
        elif name.lower().endswith(".ogg") and name not in wanted:
            os.remove(full)
            removed.append(name)
    return removed


# ---------------------------------------------------------------------------
# checking what came out
# ---------------------------------------------------------------------------

def verify_chunks(pack_dir, tracks):
    """Every chunked track adds back up to the track it came from.

    RUN ON EVERY BUILD, not once by hand. Eight hundred pieces is not a thing
    anybody checks by listening, and the two ways this goes wrong are both
    silent: a seek that lands a few milliseconds out leaves a repeat or a hole
    at one boundary in the middle of one song, and a stride written as the file
    length instead of the overlap-less share of it plays every piece a quarter
    of a second late, cumulatively, for the whole track.
    """
    dest = os.path.join(pack_dir, AUDIO_DIR)
    bad = []

    for t in tracks:
        if not t.get("chunks"):
            continue

        folder = os.path.splitext(t["file"])[0]
        overlap = t["overlap"]
        strides = [d for _, d in t["chunks"]]
        covered = sum(strides)
        source = oggprobe.duration(t["source"])

        # A quarter of a frame at sixty. Anything looser and a real seek error
        # would pass; anything tighter and vorbis's own rounding would fail.
        if abs(covered - source) > 0.05:
            bad.append("%s: pieces cover %.4fs of a %.4fs track"
                       % (t["title"], covered, source))

        for i, (name, stride) in enumerate(t["chunks"]):
            path = os.path.join(dest, folder, name)
            if not os.path.exists(path):
                bad.append("%s: %s is in the manifest and not on disk"
                           % (t["title"], name))
                continue
            length = oggprobe.duration(path)
            want = stride + (0 if i == len(t["chunks"]) - 1 else overlap)
            if abs(length - want) > 0.05:
                bad.append("%s: %s is %.4fs, wanted %.4fs (stride %.4f + overlap %.4f)"
                           % (t["title"], name, length, want, stride, overlap))

    if bad:
        for line in bad[:12]:
            print("  !! " + line)
        raise SystemExit("%d chunk(s) do not add up - not shipping that" % len(bad))


# ---------------------------------------------------------------------------

def main(argv):
    if len(argv) != 2:
        raise SystemExit(__doc__)

    pack_dir = os.path.abspath(argv[1])
    spec = os.path.join(pack_dir, "pack.json")
    if not os.path.isfile(spec):
        raise SystemExit("no pack.json in " + pack_dir)

    with open(spec, encoding="utf-8") as fh:
        pack = json.load(fh)
    if not pack.get("packId"):
        raise SystemExit("pack.json declares no packId")

    # RELATIVE TO THE PACK, so a clone can rebuild. These used to be absolute
    # paths into a design folder and a generator's output directory, neither of
    # which was in version control - so the repository held a pack nobody could
    # make another one of, and the masters it came from could be lost without
    # anything noticing.
    for key in ("music", "magazines"):
        section = pack.get(key) or {}
        source = section.get("source")
        if source and not os.path.isabs(source):
            section["source"] = os.path.normpath(os.path.join(pack_dir, source))

    seen_ids = set()
    tracks = collect_music(pack.get("music", {}), seen_ids)
    mags   = collect_magazines(pack.get("magazines", {}), seen_ids)

    removed = sync_audio(pack_dir, tracks) + sync_magazines(pack_dir, mags)
    write_content(pack_dir, pack, tracks, mags)
    write_toc(pack_dir, pack)
    write_credits(pack_dir, pack)

    verify_chunks(pack_dir, tracks)

    total = sum(t["duration"] for t in tracks)
    for t in tracks:
        note = ""
        if t.get("chunks"):
            note = "  %d chunks of %ss" % (len(t["chunks"]), t["chunk"])
        print("  %-34s %-30s %d:%02d%s" % (t["title"], t["artist"] or "-",
                                           t["duration"] // 60, t["duration"] % 60,
                                           note))
    for m in mags:
        fresh = m.get("updated") or 0
        print("  %-34s %-30s %d pages%s"
              % (m["title"], m["masthead"], len(m["pages"]),
                 fresh and ("  %d updated" % fresh) or ""))
    for name in removed:
        print("  removed %s" % name)
    print("%s: %d tracks (%d:%02d of programme), %d issues"
          % (pack["packId"], len(tracks), total // 60, total % 60, len(mags)))


if __name__ == "__main__":
    main(sys.argv)
