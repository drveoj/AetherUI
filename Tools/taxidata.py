#!/usr/bin/env python3
"""Generate the flight-leg duration table from the client's own DB2 export.

Reads TaxiNodes / TaxiPath / TaxiPathNode as CSV, once per client, and writes
Modules/IFEC/Routes.lua carrying one table per client.

ONE TABLE PER CLIENT. WoW Forever's taxi data is not Era's: it has nodes Era
does not (Riverglades, Mount Hyjal), and some shared legs fly a different path.
Each client's CSVs live in a folder named for its flavour (A.flavour in
Core.lua), and Routes.lua picks its own at load.

A leg's duration is the length of its waypoint polyline divided by the taxi
speed, plus any waypoint delays. TaxiPathNode carries 11-50 waypoints per path,
so the polyline already traces the curve - the "splines make point-to-point
summation underestimate" correction is not needed and is not applied. Fitted
against nine real flights the residuals are under a second.

    python Tools/taxidata.py [--data DIR] [--dry-run]
"""

import argparse
import csv
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

# IN THE REPOSITORY, not in a design folder beside it. Routes.lua is generated
# from these files, and while they lived outside version control the generated
# file could not be reproduced by anyone who had only the repository -
# including this machine after a tidy-up.
DEFAULT_DATA = os.path.join(HERE, "data", "taxi")
OUT = os.path.join(REPO, "Modules", "IFEC", "Routes.lua")

# One folder of three CSVs under DEFAULT_DATA per client, named exactly as
# A.flavour names that client, because the name is the key Routes.lua picks by.
FLAVOURS = ("era", "camelot")

# Yards per second. Fitted against nine measured flights spanning six zones;
# they imply 30.00-30.31 and the fit lands at 30.122 with a worst error of
# 0.66s. A second parameter for takeoff overhead does not improve it.
TAXI_SPEED = 30.122

# Nodes that are not flight-master nodes: the boats, zeppelins and ferries, and
# the invisible aiming points they use. TaxiNodeName never returns these for a
# flight, and they are the only paths carrying the flag-2 stop delays.
PSEUDO_PREFIXES = ("Transport,", "Generic,")


def read(csv_dir, table):
    """The one CSV for `table`, whatever build suffix it carries."""
    hits = [f for f in os.listdir(csv_dir)
            if f.startswith(table + ".") and f.endswith(".csv")]
    if not hits:
        sys.exit("no CSV for %s in %s" % (table, csv_dir))
    if len(hits) > 1:
        sys.exit("more than one CSV for %s: %s" % (table, ", ".join(sorted(hits))))
    with open(os.path.join(csv_dir, hits[0]), encoding="utf-8-sig", newline="") as f:
        return hits[0], list(csv.DictReader(f))


def build(csv_dir):
    nodes_file, node_rows = read(csv_dir, "TaxiNodes")
    _, path_rows = read(csv_dir, "TaxiPath")
    _, point_rows = read(csv_dir, "TaxiPathNode")

    # The build stamp is in the filename: TaxiNodes.1.15.9.69109.csv
    build_id = nodes_file[len("TaxiNodes."):-len(".csv")]

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

    return build_id, out, skipped, delayed, sorted(fuzzy)


def emit(tables):
    """tables: (flavour, build_id, legs, fuzzy) for each client, in order."""
    out = []
    w = out.append
    w("--[[--------------------------------------------------------------------------")
    w("\tAetherUI :: IFEC route table  -  GENERATED, DO NOT EDIT")
    w("")
    w("\tWritten by Tools/taxidata.py from each client's own DB2 export:")
    for flavour, build_id, _, _ in tables:
        w("\t    %-8s %s" % (flavour, build_id))
    w("\tEdit the generator, not this file.")
    w("")
    w("\tSeconds per SINGLE-HOP leg, keyed [from][to] on the names TaxiNodeName")
    w("\treturns. A multi-hop journey is the sum of its legs - proved against")
    w("\tmeasured flights, and the reason only legs are stored.")
    w("")
    w("\tDirectional: the same two nodes take different times each way.")
    w("")
    w("\tOne table per client, picked by A.flavour at the bottom. A client with no")
    w("\ttable gets none rather than another client's: the console still opens")
    w("\tand counts up, it just cannot say when you land.")
    w("----------------------------------------------------------------------------]]")
    w("")
    w("local ADDON, A = ...")
    w("")
    # Recorded rather than used: the durations below are already baked.
    w("A.IFEC_TAXI_SPEED  = %.3f" % TAXI_SPEED)
    w("")
    w("local ROUTES = {}")

    for flavour, build_id, legs, fuzzy in tables:
        by_from = {}
        for (a, b), secs in legs.items():
            by_from.setdefault(a, {})[b] = secs

        w("")
        w("ROUTES.%s = {" % flavour)
        w("\tbuild = %s," % lua_str(build_id))
        w("")
        w("\tlegs = {")
        for a in sorted(by_from):
            w("\t\t[%s] = {" % lua_str(a))
            for b in sorted(by_from[a]):
                w("\t\t\t[%s] = %s," % (lua_str(b), fmt(by_from[a][b])))
            w("\t\t},")
        w("\t},")
        w("")
        w("\t--- Legs the client has two paths for, one per faction, differing by")
        w("\t--  more than a second. The stored value is their mean; a measured one")
        w("\t--  beats it.")
        w("\tfuzzy = {")
        fuzzy_by_from = {}
        for a, b in fuzzy:
            fuzzy_by_from.setdefault(a, []).append(b)
        for a in sorted(fuzzy_by_from):
            w("\t\t[%s] = {" % lua_str(a))
            for b in sorted(fuzzy_by_from[a]):
                w("\t\t\t[%s] = true," % lua_str(b))
            w("\t\t},")
        w("\t},")
        w("}")

    w("")
    w("local mine = A.flavour and ROUTES[A.flavour]")
    w("A.IFEC_ROUTE_BUILD = mine and mine.build")
    w("A.IFEC_LEGS        = mine and mine.legs")
    w("A.IFEC_LEGS_FUZZY  = mine and mine.fuzzy")
    w("")
    return "\n".join(out)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def fmt(x):
    return ("%.1f" % x).rstrip("0").rstrip(".") or "0"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", default=DEFAULT_DATA,
                    help="directory holding one folder of three CSVs per client")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    tables = []
    for flavour in FLAVOURS:
        build_id, legs, skipped, delayed, fuzzy = build(os.path.join(args.data, flavour))
        tables.append((flavour, build_id, legs, fuzzy))

        froms = len({a for a, _ in legs})
        oneway = sum(1 for (a, b) in legs if (b, a) not in legs)
        print("%s" % flavour)
        print("  build      %s" % build_id)
        print("  legs       %d  (from %d origin nodes)" % (len(legs), froms))
        print("  skipped    %d  (boats, zeppelins and their aiming points)" % skipped)
        print("  with delay %d" % delayed)
        print("  two-path   %d  (mean taken, learner overrides)" % len(fuzzy))
        print("  one-way    %d" % oneway)

    print("speed        %s yd/s" % fmt(TAXI_SPEED))
    text = emit(tables)

    if args.dry_run:
        print("  (dry run, nothing written)")
        return

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    # LF, as every file in the repository is (.gitattributes): the harness
    # counts a CR as a stray control byte.
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("  wrote      %s" % os.path.relpath(OUT, REPO))


if __name__ == "__main__":
    main()
