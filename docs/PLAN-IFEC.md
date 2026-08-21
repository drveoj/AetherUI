# Plan: I.F.E.C. (In-Flight Entertainment Console)

Design source: `E:\AetherUI Design\design_handoff_ifec\` (v1) and
`design_handoff_ifec_v2\` (v2 deltas). Technical brief:
`E:\AetherUI Design\aetherui-inflight-technical-brief-v2-classic.md`.

v2 is deltas only — v1 still specifies everything v2 does not contradict.
Where they disagree, v2 wins.

A console that opens on every taxi flight. It always shows the route and a
flight timer; when content is installed and in season it also plays it. The
brief's own framing: **the console always exists, the content might not.**

---

## 1. Decisions taken before any code

**The console is a module inside AetherUI.** Decided 2026-08-15. Content seasons
ship as their own addons and are added to `## OptionalDeps` as they release.
This answers the brief's §4 open question.

**The brief's §11 questions, answered from the codebase:**

- Module pattern is **bespoke, not Ace3**. `A:NewModule(name)` at
  `Core/Core.lua:191`, lifecycle `OnInitialize` / `OnEnable` / `OnDisable` /
  `OnConfigChanged` / `OnSkinChanged`, events via `A:RegisterEvent(self, ...)`
  on one shared pump (`Core/Core.lua:241`). AceDB is used for saved variables
  and AceConfig for the options tree; there is no AceAddon and no AceEvent.
- SavedVariables is `AetherUIDB` via AceDB (`Core/Config.lua:901`). Per-module
  settings live at `A.Config:Module("ifec")` (`Core/Config.lua:912`), which
  lazily creates the table. Per-character data goes under `char`, shared under
  `profile`. Migration is a hand-written `Migrate(db)` keyed on which fields are
  present rather than on a schema version (`Core/Config.lua:829`).
- Frame positioning is **bespoke, not Edit Mode**. `A.Movers:Register(name,
  frame, default, label, opts)` (`Core/Movers.lua:507`) restores and persists
  to `A.db.profile.anchors[name]`. This settles the handoff's "register with
  Edit Mode if supported" note: we do not, because nothing else in AetherUI
  does, and one positioning system beats two.

---

## 2. Where this plan departs from the technical brief

### 2.1 Route durations are generated, as the brief wanted — and the spline correction is not needed

The three DB2 tables were supplied as CSV in the design folder,
for build **1.15.9.69109**, matching the client. So §5's plan is available after
all: 87 nodes, 294 paths, 9,582 path points.

**Taxi speed is a single constant.** Fitting `duration = length / v` against the
nine of the measured routes that are single paths:

    v = 30.122 yd/s      RMS error 0.34s      worst error 0.66s

A two-parameter fit adding a fixed takeoff/landing overhead does not earn its
keep — SSE 1.016 → 0.933 and the worst error is unchanged at 0.67s. Use one
parameter. This also answers the brief's "confirm vanilla taxi speed is a single
constant rather than having per-region modifiers": the nine legs span Durotar,
the Barrens, Mulgore, Ashenvale, Tirisfal and Silverpine and imply 30.00–30.31
yd/s. One constant.

**The spline correction the brief warns about is unnecessary.** Its concern was
that summing straight lines between nodes underestimates a curved path. That is
true of *sparse* node-to-node summation; `TaxiPathNode` is dense — 11 to 50
waypoints per path — so the polyline already traces the curve. Sub-second
residuals across nine routes confirm it. No correction factor is fitted.

**Flag 2 is real, and it is not on flight paths.** The brief asks whether any
taxi paths carry the "stop for Delay seconds" flag. Ten do, and every one is a
boat, zeppelin or ferry — Booty Bay–Ratchet, the Orgrimmar zeppelins, Menethil
ships, Rut'theran–Auberdine, Feathermoon, and Naxxramas — carrying 120s (60s for
Naxxramas). No flight-master route is affected. Delays are summed anyway, since
doing so costs one line and the data says when it matters.

**Coverage:** 281 usable directed legs from the 294 paths, over 87 nodes. 14
legs have no reverse counterpart, which is expected — Alterac Valley and
Naxxramas are one-way.

So the shipped table is generated, and runtime learning becomes what the brief
originally proposed: a telemetry path that records actuals, logs divergence, and
corrects the table between releases rather than driving the UI.

### 2.2 A multi-hop flight is the sum of its legs

Proved twice against real measured data in
`WTF\Account\JOEV\SavedVariables\CinematicTaxi.lua`:

    Ratchet→Crossroads   68  +  Crossroads→Orgrimmar  141  =  209  = Ratchet→Orgrimmar   (exact)
    Orgrimmar→Crossroads 109 +  Crossroads→Ratchet     51  =  160  vs Orgrimmar→Ratchet 161

So the route store holds **single-hop legs**, not whole routes. Learn N legs and
every multi-hop route composed of them is known for free. This also makes the
design's brass leg-boundary ticks *derived* rather than interpolated — if each
leg's duration is known, so is exactly where each boundary falls in time.

### 2.3 Legs are directional

    Orgrimmar→Ratchet 161   vs   Ratchet→Orgrimmar 209
    Crossroads→Ratchet  51   vs   Ratchet→Crossroads  68

A symmetric table would be wrong by 30–60s, well outside tolerance. Key on
ordered pairs.

### 2.4 `GetTaxiMapID` is not used by the client

The brief lists it among the relevant APIs. It appears nowhere in Blizzard's own
UI code for this build. Treat as unverified and do not depend on it. The
functions Blizzard's own `TaxiFrame.lua` actually uses are `NumTaxiNodes`,
`TaxiNodeGetType`, `TaxiNodeName`, `TaxiNodePosition`, `GetNumRoutes`,
`TaxiGetNodeSlot`, `TaxiNodeCost`, `TaxiIsDirectFlight`, `TakeTaxiNode`.

---

## 3. What the client gives us

**There is no taxi event.** Flight is bracketed by `PLAYER_CONTROL_LOST` /
`PLAYER_CONTROL_GAINED`, which also fire for stuns, fear and mind control.
Blizzard's own `UIParent.lua:663` disambiguates with `UnitOnTaxi("player")` and
so do we. Prior art additionally waits ~0.5s before trusting `UnitOnTaxi` on the
LOST edge, which suggests the state is not settled in the same frame.

**Control is lost and regained once for the whole journey**, not once per leg —
confirmed by the arithmetic in §2.2. Leg boundaries cannot be observed at
runtime; they are known in advance from `GetNumRoutes` / `TaxiGetNodeSlot`,
which are queryable at hover time, before boarding.

**Everything except duration is knowable at boarding**: origin (the node whose
`TaxiNodeGetType` is `"CURRENT"`), destination, leg count, every intermediate
node, and cost.

**`TaxiRequestEarlyLanding()` exists**, so a flight can end short of the node
that was clicked. Prior art does not guard against this and poisons its own
table with a short duration for a destination never reached. We discard any
sample where the landing node is not the booked destination.

---

## 4. Architecture

The brief requires an internal boundary: the timer path must work with the
content path disabled, erroring or absent, and must hold no references into it.
One 4,000-line module file cannot express that, so this is the first module in
AetherUI to get a folder.

Named IFEC rather than InFlight: an addon of that name already exists and its
author should not have to wonder.

    Modules/IFEC/Route.lua       leg store, learning, lookup      ─┐
    Modules/IFEC/Taxi.lua        detection, flight state machine   │  always
    Modules/IFEC/Console.lua     the frame, dormant + active shell ─┘

    Modules/IFEC/Registry.lua    pack registration, the merge     ─┐
    Modules/IFEC/Content.lua     filtering, queue building         │  hidden
    Modules/IFEC/Playback.lua    sequencing, handles, resume       │  when no
    Modules/IFEC/Player.lua      player region, transport, up-next │  content
    Modules/IFEC/Reader.lua      the two publications             ─┘

`Route`, `Taxi` and `Console` may not require any file in the second group.
Enforced by a harness check that loads the first group alone and drives a full
flight through it.

### Content packs

Separate addons, registering a manifest with the console. Both load orders must
work: a pack calls the engine's register function if it exists, otherwise
appends to a global pending table the engine drains on load. `OptionalDeps`
influences order but is not relied on for correctness.

Identity is composite `packId:itemId`; `packId` is the addon folder name, which
the client already guarantees unique. Item IDs need only be unique within a
pack, which the build lint can enforce. A second pack claiming a registered
`packId` is refused and reported.

**Packs cannot live inside this repo.** `E:\AetherUI` mirrors to
`Interface\AddOns\AetherUI`, so a pack folder inside it would deploy to the
wrong place. Packs need a sibling root and a second mirror step — see §8.

---

## 5. What Core needs that does not exist

The survey found three gaps. Two are new; one is a debt this feature should not
add to.

**Segmented progress bar** — does not exist. `W.CreateBar`
(`Core/Widgets.lua:273`) is a single continuous fill. The programme bar needs N
segments with 2px gaps, per-segment fill or dashed-border-on-tint, and outer
corners rounded only on the end segments. New: `W.CreateSegmentedBar`.

**Circular dial** — does not exist. `W.CreateOrb` / `W.CreateBadge` are filled
discs, not value-driven arcs, and there is no "fill a ring by angle" primitive.
Needs a new ring texture from `Tools/generate_textures.py` plus Lua to drive it.
The design's dial is 44px outer / 35px inner with a 2px brass rim.

**Scrolling list with frame reuse** — exists *twice*, copy-pasted, in
`Modules/QuestLog.lua:634,1151` and `Modules/Bags.lua:700,660`. Both carry the
same comment about WoW never freeing frames. Adding a third copy for the browse
list would be exactly what the DRY rule forbids, so this feature **extracts the
pattern into Core and migrates both existing callers in the same pass**. Not
optional and not deferred — half-migrating is the failure mode that has been
called out before.

Everything else is already there and should be reused rather than rebuilt:
`Glass.CreatePanel` for the panel, `W.Pill` for the dormant capsule and chips,
`W.CreateButton` / `W.SkinButton` for transport, `W.Divider` for the hairline,
`Media.style` roles for type, `Palette.c` tokens for colour.

### New palette tokens

The design's channel tints, masthead colours and settings-reason colours are not
in `Core/Palette.lua`. Per its own convention (own token, don't borrow) they get
`ifec*`-prefixed tokens written into **both** skins as they are added — cheap
now, expensive to retrofit, and Daylight stays untuned per the standing decision.

---

## 6. Phasing

Each phase is independently green and independently useful.

**Phase 1 — the console that always exists.** Route store and learning, taxi
detection and state machine, the dormant pill, the dial, Movers registration,
settings page. At the end of this phase the addon has a working flight timer for
every flight, which is what most users would ever see.

**Phase 2 — Core widgets.** Segmented bar, dial refinement, scroll-list
extraction and the migration of QuestLog and Bags onto it.

**Phase 3 — the content spine.** Registry, the merge, dormancy switching,
manifest contract, failure isolation. Provable with a dummy pack and no audio.

**Phase 4 — playback.** Sequencing off baked durations, `PlaySoundFile` on the
Music channel, `StopSound` on landing, resume at every segment boundary.

**Phase 5 — the active console.** Player region, programme bar, up-next,
queue-exhausted state.

**Phase 6 — the reader.** Both publications, `SimpleHTML` verified in a live
client first with a single-FontString fallback.

**Phase 7 — the authoring pipeline.** `Tools/content.py`, Markdown with
frontmatter, ffmpeg chaptering from Audacity label exports, the lore wordlist,
`/aether ifec preview <id>`.

---

## 7. Tooling

Present and verified: **ffmpeg and ffprobe 8.1.2** (split, encode to Ogg
Vorbis, probe durations), **numpy and Pillow** (the icon atlas).

Absent: **pyyaml**. The brief's manifest format uses YAML frontmatter plus
`episode.yaml` / `tracks.yaml`. Frontmatter is simple enough to parse in thirty
lines of stdlib; adding a dependency to a repo whose other tools are stdlib-only
is the worse trade. Hand-roll it.

Test material: the five Zen tracks in `Media/Audio/`, each exactly 60.000s.
Enough to exercise sequencing, queueing and resume with real files.

---

## 8. Known problems to solve before they bite

**Zen and the IFEC will fight over the Music channel.** Zen uses `PlayMusic`
*because* it loops (`Modules/Zen.lua:214`), and that call replaces whatever is
on the channel (`:1332`). The IFEC uses `PlaySoundFile(path, "Music")` plus
`StopSound(handle)`, per the brief.

**Decided** 2026-08-15: the console takes the channel. Zen's loop stops
on boarding and is restored on landing — the flight is the foreground activity
and its content is the point of the feature. Zen's own state must be recorded
before it is stopped so that "restore" means what Zen had, not what we guessed;
and a Zen timer firing mid-flight must not steal the channel back.

**Pack deployment.** The Stop hook mirrors `E:\AetherUI` to
`Interface\AddOns\AetherUI`.

**Decided:** packs live in a sibling root, `E:\AetherUI-Packs\<AddonName>`, each
its own addon folder under version control, with a second mirror step in the
deploy hook. The AetherUI repo stays one addon, which is what it is.

**`willPlay` is nil when the music channel is muted.** Detect and surface in the
UI rather than playing silence and appearing broken. The design already has a
state for this: the exhausted-queue chip becomes unread stories, and there is a
muted-speaker glyph and a "muted in settings" string.

**A new `.tga` may need a client restart, not just a `/reload`**
(`Core/Media.lua:88`). The icon atlas work should be front-loaded so the restart
is paid once.

---

## 9. Design questions still open

Twelve items came back unspecified from the design extraction. Most can take a
sensible default; these four change what gets built:

1. **What does minimise collapse to?** v1 had a bare 54px dial-only handle with
   hover-to-reveal. v2's dormant form is a full 560px pill described as complete
   in itself, and never mentions a bare dial. Proposed default: the chevron
   collapses the active panel to the dormant pill, and there is no third state.
2. **How do browse and programme relate?** v2 says v1's browse and library
   drill-in stand as designed, but no v2 screenshot shows the three-channel
   browse at all — only now-playing plus up-next. Is browse a tab, or does it
   appear only when nothing is queued?
3. **Fate of v1's price-line gag and "story N of M" counter** in the v2 reader,
   whose slot the new lede device now occupies.
4. **Queue scope.** The brief's §4c default is that autoplay stays within the
   pack the current item came from and stops rather than rolling into another
   season, and asks for this to be confirmed against the design. The design's
   auto-fill rule — current season before older ones, music as filler — reads as
   crossing packs. These conflict.

Defaults proposed for the rest: icons always render at every glyph size; the
fills-value in the programme headline is the generic accent rather than a
channel colour; the short bar caption is the persistent one; the reader is
hosted at the console's own 560px width.
