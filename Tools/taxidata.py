#!/usr/bin/env python3
"""Generate the flight-leg duration table from the client's own DB2 export.

Reads TaxiNodes / TaxiPath / TaxiPathNode as CSV and writes
Modules/IFEC/Routes.lua.

A leg's duration is the length of its waypoint polyline divided by the taxi
speed, plus any waypoint delays. TaxiPathNode carries 11-50 waypoints per path,
so the polyline already traces the curve - the "splines make point-to-point
summation underestimate" correction is not needed and is not applied. Fitted
against nine real flights the residuals are under a second.

TWO CLIENTS, TWO TABLES. Cataclysm renamed flight points - Era's
"Crossroads, The Barrens" is "The Crossroads, Northern Barrens" on Mists -
and the tables are keyed on the name TaxiNodeName returns, so one table
cannot serve both. Each build in data/taxi gets its own generated file and
each file refuses to build its table on the client it is not for.

    python Tools/taxidata.py [--csv DIR] [--build 5.5.4.69383] [--dry-run]
"""

import argparse
import csv
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

# IN THE REPOSITORY, not in a design folder beside it. Routes.lua is generated
# from these three files, and while they lived outside version control the
# generated file could not be reproduced by anyone who had only the repository -
# including this machine after a tidy-up.
DEFAULT_CSV = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "data", "taxi")
# Which client a build belongs to, and where its table is written. Keyed on
# the leading version so a new build of either flavour needs no edit here.
FLAVOURS = {
    "1.15": ("era",   "A.isMists",     "Routes.lua"),
    "5.5":  ("mists", "not A.isMists", "Routes_Mists.lua"),
}
OUTDIR = os.path.join(REPO, "Modules", "IFEC")

# Yards per second. Fitted against nine measured flights spanning six zones;
# they imply 30.00-30.31 and the fit lands at 30.122 with a worst error of
# 0.66s. A second parameter for takeoff overhead does not improve it.
TAXI_SPEED = 30.122

# Nodes that are not flight-master nodes: the boats, zeppelins and ferries, and
# the invisible aiming points they use. TaxiNodeName never returns these for a
# flight, and they are the only paths carrying the flag-2 stop delays.
PSEUDO_PREFIXES = ("Transport,", "Generic,")


def builds(csv_dir):
    """Every build the CSV directory holds, by the stamp in the filename.

    TaxiNodes.1.15.9.69109.csv -> 1.15.9.69109, and the other two tables are
    expected under the same stamp.
    """
    found = sorted(f[len("TaxiNodes."):-len(".csv")]
                   for f in os.listdir(csv_dir)
                   if f.startswith("TaxiNodes.") and f.endswith(".csv"))
    if not found:
        sys.exit("no TaxiNodes CSV in %s" % csv_dir)
    return found


def flavour(build_id):
    for prefix, spec in FLAVOURS.items():
        if build_id.startswith(prefix + "."):
            return spec
    sys.exit("no flavour known for build %s - add it to FLAVOURS" % build_id)


def read(csv_dir, table, build_id):
    """The CSV for `table` at this build."""
    path = os.path.join(csv_dir, "%s.%s.csv" % (table, build_id))
    if not os.path.exists(path):
        sys.exit("missing %s" % path)
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def build(csv_dir, build_id):
    node_rows = read(csv_dir, "TaxiNodes", build_id)
    path_rows = read(csv_dir, "TaxiPath", build_id)
    point_rows = read(csv_dir, "TaxiPathNode", build_id)

    names = {}
    for r in node_rows:
        names[int(r["ID"])] = r["Name_lang"]

    points = {}
    for r in point_rows:
        points.setdefault(int(r["PathID"]), []).append(r)
    for pid in points:
        points[pid].sort(key=lambda r: int(r["NodeIndex"]))

    legs, skipped, delayed = {}, 0, 0
    for r in path_rows:
        pid = int(r["ID"])
        a = names.get(int(r["FromTaxiNode"]))
        b = names.get(int(r["ToTaxiNode"]))
        if not a or not b:
            skipped += 1
            continue
        if a.startswith(PSEUDO_PREFIXES) or b.startswith(PSEUDO_PREFIXES):
            skipped += 1
            continue

        ps = points.get(pid, [])
        length = 0.0
        for p, q in zip(ps, ps[1:]):
            dx = float(q["Loc_0"]) - float(p["Loc_0"])
            dy = float(q["Loc_1"]) - float(p["Loc_1"])
            dz = float(q["Loc_2"]) - float(p["Loc_2"])
            length += math.sqrt(dx * dx + dy * dy + dz * dz)
        delay = sum(float(p["Delay"]) for p in ps)
        if delay:
            delayed += 1

        legs.setdefault((a, b), []).append(length / TAXI_SPEED + delay)

    # SOME LEGS HAVE TWO PATHS. Nine do, all of them into the neutral hubs both
    # factions share - Moonglade, Cenarion Hold, Marshal's Refuge - and they are
    # not near-copies: Cenarion Hold to Gadgetzan differs by 52 seconds between
    # the two. Almost certainly one path per faction, but TaxiPath carries no
    # column saying which, so there is nothing to choose on.
    #
    # The mean halves the worst case a guess could produce, and the leg is named
    # in IFEC_LEGS_FUZZY so the runtime learner knows to trust a measured value
    # over the table for it.
    fuzzy, out = [], {}
    for key, secs in legs.items():
        out[key] = sum(secs) / len(secs)
        if len(secs) > 1 and (max(secs) - min(secs)) > 1.0:
            fuzzy.append(key)

    return out, skipped, delayed, sorted(fuzzy)


def emit(build_id, legs, fuzzy, guard):
    by_from = {}
    for (a, b), secs in legs.items():
        by_from.setdefault(a, {})[b] = secs

    out = []
    w = out.append
    w("--[[--------------------------------------------------------------------------")
    w("\tAetherUI :: IFEC route table  -  GENERATED, DO NOT EDIT")
    w("")
    w("\tWritten by Tools/taxidata.py from the client's own DB2 export, build")
    w("\t%s. Edit the generator, not this file." % build_id)
    w("")
    w("\tONE CLIENT\'S TABLE. Cataclysm renamed flight points, and these")
    w("\tare keyed on the name TaxiNodeName returns - so the other flavour")
    w("\thas a file of its own, and this one stands down when it is not it.")
    w("")
    w("\tSeconds per SINGLE-HOP leg, keyed [from][to] on the names TaxiNodeName")
    w("\treturns. A multi-hop journey is the sum of its legs - proved against")
    w("\tmeasured flights, and the reason only legs are stored.")
    w("")
    w("\tDirectional: the same two nodes take different times each way.")
    w("----------------------------------------------------------------------------]]")
    w("")
    w("local ADDON, A = ...")
    w("")
    # NOT THIS CLIENT'S TABLE, so it is never built. The file is in the list
    # on both flavours - one .toc, see AetherUI.toc - and the whole cost of
    # the one that does not apply is compiling a chunk that returns at once.
    w("if %s then return end" % guard)
    w("")
    w("A.IFEC_ROUTE_BUILD = %s" % lua_str(build_id))
    # Recorded rather than used: the durations below are already baked.
    w("A.IFEC_TAXI_SPEED  = %.3f" % TAXI_SPEED)
    w("")
    w("A.IFEC_LEGS = {")
    for a in sorted(by_from):
        w("\t[%s] = {" % lua_str(a))
        for b in sorted(by_from[a]):
            w("\t\t[%s] = %s," % (lua_str(b), fmt(by_from[a][b])))
        w("\t},")
    w("}")
    w("")
    w("--- Legs the client has two paths for, one per faction, differing by more")
    w("--  than a second. The stored value is their mean; a measured one beats it.")
    w("A.IFEC_LEGS_FUZZY = {")
    fuzzy_by_from = {}
    for a, b in fuzzy:
        fuzzy_by_from.setdefault(a, []).append(b)
    for a in sorted(fuzzy_by_from):
        w("\t[%s] = {" % lua_str(a))
        for b in sorted(fuzzy_by_from[a]):
            w("\t\t[%s] = true," % lua_str(b))
        w("\t},")
    w("}")
    w("")
    return "\n".join(out)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def fmt(x):
    return ("%.1f" % x).rstrip("0").rstrip(".") or "0"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--csv", default=DEFAULT_CSV, help="directory holding the CSVs")
    ap.add_argument("--build", help="one build stamp; default is every build present")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for build_id in ([args.build] if args.build else builds(args.csv)):
        name, guard, out_file = flavour(build_id)
        legs, skipped, delayed, fuzzy = build(args.csv, build_id)
        text = emit(build_id, legs, fuzzy, guard)

        froms = len({a for a, _ in legs})
        oneway = sum(1 for (a, b) in legs if (b, a) not in legs)
        print("  build      %s  (%s)" % (build_id, name))
        print("  legs       %d  (from %d origin nodes)" % (len(legs), froms))
        print("  skipped    %d  (boats, zeppelins and their aiming points)"
              % skipped)
        print("  with delay %d" % delayed)
        print("  two-path   %d  (mean taken, learner overrides)" % len(fuzzy))
        print("  speed      %s yd/s" % fmt(TAXI_SPEED))
        print("  one-way    %d" % oneway)

        if args.dry_run:
            print("  (dry run, nothing written)")
        else:
            # LF, like every other file here - .gitattributes says the tree
            # is authored with LF and copied verbatim into the AddOns folder,
            # and this generator was the one thing writing CRLF into it.
            os.makedirs(OUTDIR, exist_ok=True)
            out = os.path.join(OUTDIR, out_file)
            with open(out, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            print("  wrote      %s" % os.path.relpath(out, REPO))
        print("")


if __name__ == "__main__":
    main()
