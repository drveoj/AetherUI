# Plan: Threat

Design source: `E:\AetherUI Design\design_handoff_threat\` (README.md,
`Threat.dc.html`, boards 16a–16d, four screenshots), with the skin rules in
`design_handoff_skins` and the role glyph from `design_handoff_party` (12a).

**Not started.** This is the review and the build order. Nothing below is
written yet.

The design is one idea applied to two surfaces: *what is my threat* on the unit
frames, and *which of these mobs is about to come at me* on the nameplates. It
is role-aware throughout — the same state is good for a tank and bad for
everyone else — and quiet by default: a DPS at low threat shows nothing at all.

---

## 1. What the client actually gives us

**The threat API works on 1.15.9, solo, with real numbers. Confirmed by probe
on 2026-08-21 — see §1.1.** No threat library, no combat-log inference.

That is now measured rather than inferred. The evidence below only ever said
the functions were *declared*, which is a different claim and one I stated too
strongly the first time:

- `Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` in this client's
  own export declares `UnitThreatSituation`, `UnitDetailedThreatSituation` and
  the `UnitThreatSituationUpdate` event.
- `Blizzard_UnitFrame/Classic/UnitFrame.lua:918` — the **Classic** variant, not
  a shared file — drives its threat indicator off them.
- **NKThreat 2.12.1**, installed live in this AddOns folder and declaring
  `## Interface-Vanilla: 11509`, uses `UnitDetailedThreatSituation` as its
  *only* source. No combat-log inference, no ThreatLib, no fallback.

The first draft of this section called those three lines "independent
confirmations" that the API was live. They are not. Every one says the function
is **declared**; not one says the **server answers it**. A declared-and-unwired
API is a documented hazard on this client — see the phantom dropdown globals —
and it is exactly what the first probe looked like. The conclusion turned out
right; the reasoning that reached it was not.

```lua
local isTanking, status, scaledPct, rawPct, rawThreat =
	UnitDetailedThreatSituation(unit, mobUnitToken)
```

`scaledPct` is **threat as a percentage of what it takes to pull**, with the
110% melee / 130% ranged rule already applied by the server. That is precisely
the number 16b calls "fill = threat ÷ pull threshold". The design's central
quantity arrives ready-made; we do not compute it, and we must not.

`status` is the 0–3 band: 0 not tanking and below the threshold, 1 not tanking
but over it, 2 tanking insecurely, 3 tanking securely.

### 1.1 The probes, 2026-08-21 — empty, then conclusive

Warlock, solo, **in combat**, targeting a Bloodtalon Taillasher his pet was
fighting. All three functions present. Every read, for both the player and the
pet, against all three tokens for that one mob: nothing back.

```
API: UnitDetailedThreatSituation=function  UnitThreatSituation=function
     UnitThreatPercentageOfLead=function
combat=true  group=0  raid=false
  you (player): nil - not on its table
  pet (pet):    nil - not on its table
```

Three readings survived this, and they led opposite ways:

1. **The player was not on that mob's table.** The pet had done the damage. If
   he had cast nothing, "nothing back" is the API being *correct*. This does not
   explain the pet also reading nothing, which is the part that worries me —
   unless a solo player's pet is not on a table the client is told about either.
2. **The server sends no threat data outside a group.** Threat broadcast is a
   group feature; solo, there is nobody to lose aggro to, which is also the
   design's own "no threat UI" case (16c, *true solo, no pet*). If this is it,
   the feature works exactly where it matters and the probe was run in the one
   situation where it should be silent.
3. **The API is declared and unwired on Era**, and the ring needs a threat
   meter of our own — a different module, several times the size, and a
   decision to take deliberately rather than discover in Phase 2. §1.2 is
   evidence against this one: a maintained meter ships for this client with no
   fallback at all.

**Reading 1 was right.** The second probe, same warlock, still solo, this time
against a boar his voidwalker was holding:

```
combat=true  group=0  raid=false  pet=true
UNIT_THREAT_LIST_UPDATE fired 33x  UNIT_THREAT_SITUATION_UPDATE 9x
                                             last unit=softenemy
Dire Mottled Boar  [target]   its combat=true  its target=Gakrin
  you (player): tanking=false status=0 scaled=6.2  raw=8.0   threat=400
  pet (pet):    tanking=true  status=3 scaled=100.0 raw=255.0 threat=4700
                                                       lead=1175.0%
```

The data arrives, solo, with no group at all. The first probe was simply taken
against a table the player was not on yet. **Readings 2 and 3 are dead** and
Phase 1 is unblocked.

Four things fall out of those numbers, and one of them changes the build.

**The server tells us the aggro modifier — we do not have to measure it.**
For a non-holder, `rawPercentage` is threat against the holder's and
`scaledPercentage` is threat against the *pull threshold*, which is the
holder's times 1.1 or 1.3. So

```
aggroMod = raw / scaled
```

and here that is `8.0 / 6.2 = 1.29` — the ranged 1.3, for a warlock stood at
range, straight from two numbers we are reading anyway. **This removes the
melee-range probe from Phase 1 entirely.** NKThreat measures it (§1.2): a
per-class spell's range through the spellbook, an item-range fallback, a 0.5s
cache per GUID, three APIs deep. It does not need to, and neither do we. It is
also *more* correct than measuring — it is the number the server used, rather
than our guess at which side of melee range we were on when it decided.

(The identity holds for non-holders, which is where the ring's fill lives. The
holder's own `raw` means something else — 255.0 here — and does not need to
mean anything to us: an aggro holder is a full ring by definition.)

**`UnitThreatPercentageOfLead` is the holder's margin over the runner-up.**
1175% is 4700/400 exactly. For 16a's tank warning that is the direct reading of
"someone is past 90% of your threat" — the tank is losing grip as this figure
approaches 111%.

**The event is not unit-filtered the way you would expect.**
`UNIT_THREAT_LIST_UPDATE` arrived 33 times with `last unit=softenemy`, not
`target`. NKThreat registers it unit-filtered on `target` and survives only
because it also polls. **Register it unfiltered** and treat it as "something
moved", or the ring will be driven entirely by the poll and the event will look
broken.

**Blizzard's own gate is off and it does not matter.**
`IsThreatWarningEnabled=false` with `cvar threatWarning=3`. The client's own
threat indicator is disabled on this character; the API answers regardless. Had
we taken the client's gate as a precondition — which its own unit frame does —
we would have drawn nothing and concluded the data was missing.

### 1.2 What NKThreat actually does — read, not copied

NKThreat 2.12.1 is a maintained threat meter shipping for this exact client.
Reading it settles several things the design leaves to us, and contradicts one
thing I had assumed.

**It has no fallback, on any flavour.** `COMBAT_LOG_EVENT_UNFILTERED` is
registered conditionally and only for the damage graph, taunt alerts and
announcements — `UpdateCLEURegistration` is explicit about it. Threat itself
comes from `UnitDetailedThreatSituation` and nothing else, on ERA as much as on
MISTS. Its `Flavor.lua` carries per-flavour tables for taunts, combat rezzes and
melee-range spells, and is current enough to include Season of Discovery runes —
so the absence of an Era threat fallback is a decision, not an oversight.

**It considers the role API unusable outside Mists.** `NKT.CAPS.hasRoleAPI =
FLAVOR == "MISTS"`. Independent corroboration of §2, from someone shipping to
these players.

**`scaledPercentage` has the aggro modifier baked in, and you can divide it
back out.** `Nameplates.lua` recovers the aggro holder's raw threat when no
group member is tanking:

```
tankThreat = threatVal * 100 / scaledPct / aggroMod
```

with `AGGRO_MOD_MELEE = 1.1` and `AGGRO_MOD_RANGED = 1.3`. **This is how we get
16a's "someone is past 90% of YOUR threat"** — the design's tank warning is
stated against the tank's own threat, and the API only gives percentages of the
pull threshold. Without this the tank's gold tier would have to fall back on
`status == 2`, which fires at 100% and is far too late to be an act-now window.

**Melee versus ranged is measured, not assumed.** `NKT.MELEE_RANGE_CANDIDATES`
holds a per-class spell whose range is probed through the spellbook, with an
item-range fallback, cached on a 0.5s window per GUID. The design says "110%
melee / 130% ranged" in six words; this is what those six words cost.

**And we do not have to pay it.** The probe (§1.1) shows `raw / scaled` IS the
modifier the server used — 1.29 for a warlock at range. Reading it beats
measuring it twice over: no spellbook probe, no cache, and it is the value the
server actually applied rather than our guess at where we were standing when it
decided. This is the one place the plan deliberately does something other than
what the reference addon does, and the probe is why.

**Per-plate threat is a direct query.** `UnitDetailedThreatSituation("player",
nameplateUnit)` on the slow path, with a fast path reusing the last tick's
numbers when the plate happens to be your current target. Board 16d needs
nothing more than this.

**Nothing to show is `scaledPct` nil or zero.** It returns early on both, and
the meter has an explicit empty state ("No threat data"). That is the same rule
as the design's quiet-by-default, arrived at from the other direction.

**Two useful details.** Target resolution falls back to `targettarget` when your
own target is friendly — which is exactly 16c's "targeting a mob attacking
someone else". And the update path is `UNIT_THREAT_LIST_UPDATE`, unit-filtered
on `target`, marking a dirty flag consumed by a polling loop — the event alone
does not cover a target change, so both are needed.

**The probe now counts that event from load**, because it is the decisive
signal and a readout taken after the fight cannot ask for it retrospectively. No
firings during a fight and the API is a stub here whatever the calls answer.

### The constraint that shapes everything: mobs need a unit token

`UnitDetailedThreatSituation`'s second argument is a **unit token**, not a
GUID — the generated docs name it `mobGUID` and type it `UnitToken`, which is
a trap worth writing down once. So we can only ask about mobs we have a token
for:

| Token | Gives us |
|---|---|
| `target` | your current target — the player's own ring |
| `nameplate1..N` | every hostile with a plate up — board 16d, all of it |
| `party1target`… | what each member is actually fighting |
| `pettarget` | what your pet is holding |

That covers every board. The one place it bites is the tank's "lost aggro on an
**engaged** enemy" (16a, bottom left): the set of engaged enemies we can see is
the set with a nameplate or a group member's target, which is not quite the same
set. In practice a mob attacking someone in your group has a plate; the honest
statement is that a mob with no plate and nobody targeting it is invisible to
us, and the plan accepts that rather than inferring from the combat log.

### The ring cannot be drawn as an arc — and that is already solved

Classic has no conic gradient and no arc primitive. `Core/Media.lua` already
carries the answer, built for the I.F.E.C. flight dial: `Media.dial` is a
**64-step baked sheet** with `Media:DialArc(fraction)` returning the tex coords
for the nearest step, generated by `Tools/generate_textures.py` from `_annulus`
(the band) and `_sweep` (clockwise from twelve o'clock — the design's exact
wording). One `SetTexCoord` per update, no mask stack.

The threat ring is the same shape at a different band width: a gauge filling
clockwise around a disc, which is the dial's whole job. **It gets generalised,
not re-invented** — `Media.dial` becomes a family keyed by name, `Media:DialArc`
takes which family, and the generator grows a second sheet at the threat ring's
3px band. A second arc mechanism beside the dial is not an option here. See §5.

### A vignette texture already exists

`Media.texture.vignette` — a full-screen elliptical edge falloff, generated by
`vignette()` in the texture tool and already used by Zen and the minimap. The
Tier 3 screen-edge pulse reuses it. Nothing new to author.

### There is no sound asset for the ping

`PlaySoundFile` is used by I.F.E.C. playback, but we ship no alert sound. The
ping should be a client `SOUNDKIT` id rather than a file we add — one less
asset, and it will already sit right against the game's own mix. Decision in §7.

---

## 2. The finding that breaks the design as written: role

16b says *"Role comes from the assigned role glyph (12a); no role assigned =
DPS rules."*

The first live probe (§1.1) confirms it on this character: **`assigned role:
NONE`**, solo. `Modules/PartyFrames.lua:93` already records why:

> a role on Classic Era is opt-in — set by answering a role poll or listing in
> the group finder — so for most players `UnitGroupRolesAssigned` answers
> `"NONE"`

Follow the design literally and **a warrior tanking correctly gets Tier 3
`AGGRO — ON YOU`, red border, red wash, screen vignette and an audio ping,
every pull, for doing their job.** The one state the design most wants to be
quiet becomes the loudest thing on screen. This is not a small mismatch; it is
the feature failing exactly backwards for the role it was designed around.

So the module needs an **effective role**, resolved once and in one place:

1. `UnitGroupRolesAssigned(unit)` when it answers anything but `NONE`.
2. Otherwise, for the **player only**, a live inference: Defensive Stance
   (warrior), Bear/Dire Bear Form (druid), Righteous Fury (paladin), Frost
   Presence-equivalents where the client has them. All are auras or stances we
   can read directly and all change the moment the player changes them.
3. Otherwise DPS rules, as the design says.
4. And an explicit **override in the settings** — Auto / Tank / DPS-Heal.
   Inference is a heuristic; the player knows.

For *other* group members we have only (1) and (3), which is acceptable: their
capsule ring is ambient information, and the alarms are the player's own state
only anyway.

This is a departure from the handoff. **Signed off 2026-08-21** — see
§7.1.

---

## 3. Where the ring goes, and what it collides with

**Party capsules** carry a level pip (`W.CreateBadge`, `PartyFrames.lua:177`) —
this is the design's "class pip", and the geometry matches: 44 outer / 38 pip.

**The player frame does not have a pip.** It has an orb (`W.CreateOrb`,
`UnitFrames.lua:102`) which already wears `Media.texture.orbRing` around it.
16b's "works at party-capsule and player-frame sizes alike" covers the scaling,
but the ring has to sit *outside* the orb's existing rim rather than replace it,
or the player frame gets two concentric rings arguing about the same edge.

**Both already have four decorators** — crown, raid marker, PvP, role — on a
`W.DecoratorLayer` above the disc. 16b: *"Leader crown and raid markers keep
their positions on top."* The threat ring therefore draws **between** the disc
and the decorator layer, not on it.

**The pet frame** takes the same treatment; pets get their own ring under the
pet rules in 16c.

### The nameplate collision, which is the real one

16d wants the plate's **border colour and glow**. `Modules/Nameplates.lua:587`
already owns both:

```lua
f:SetEdgeColor({ c[1], c[2], c[3], EDGE_OFF + (EDGE_ON - EDGE_OFF) * t })
f:SetRimGlow({ c[1], c[2], c[3], GLOW_ALPHA * t })
```

That is the deck's target emphasis — the targeted plate is full size, full
strength, with a rim glow, and the rest fade off. Two features, one pair of
properties, and whichever writes last wins. A priority rule is needed and
should be stated in the code, not discovered:

> **Threat owns the hue; the deck owns the strength.** The deck already
> computes `t` (how emphasised this plate is). Threat chooses the colour that
> goes in, the deck keeps scaling its alpha. A red plate you are not targeting
> is still dimmer than the one you are — which is what both features wanted.

That keeps one writer per property and needs no arbitration at the call site.
The party capsule has a smaller version of the same collision
(`PartyFrames.lua:996` tints fill and edge for its highlight state) and takes
the same rule.

---

## 4. Colours

| Design | Palette today | Verdict |
|---|---|---|
| Calm accent `#cdbcff` | `Palette.c.accent` — Midnight is exactly `#cdbcff` | direct hit; swaps per skin, which 16b asks for |
| Gold `#f0d9a8`, Dusk conditional | `Palette.c.semanticGold` — the exact hex, with the Dusk conditional already written | direct hit |
| Red `#f08a7a`, invariant | `Palette.c.danger` = `#ff8a8a`, already invariant (it is a `SEMANTIC`, no skin reaches it) | **decision needed** |

The red was the only open one, and it is 15 of red and 16 of blue away from the
design's. **Settled: we use `danger` as it stands and record the departure.**
It is already invariant, already a `SEMANTIC` no skin can reach, and already
means precisely this; a ninth red that close to the eighth would be a token
nobody could pick correctly at the call site.

---

## 5. Build order

Each phase ends green with its own harness coverage. The mock has no threat
API at all today, so every phase adds to it — and per the standing lesson, the
mock must be **no kinder than the client**: `UnitDetailedThreatSituation`
returns nothing at all out of combat and for units not on the mob's table, and
the mock must do the same from the start.

**Phase 0 — the probe.** `/aether threat probe`: dump
`UnitDetailedThreatSituation("player", "target")`, the same for each group
member and pet, plus `UnitGroupRolesAssigned` and the inferred role, into the
copy box. One pull on a live target settles what the docs and NKThreat imply,
and settles the role question with real numbers. Cheap, and everything after it
depends on the answer.

**Phase 1 — the engine. BUILT, 2026-08-21.** `Modules/Threat.lua`, and see
§5.1 for what changed on contact with the client.

Original scope: `Modules/Threat.lua`: one poller (NKThreat's cadence
is a useful reference for what is cheap), one state table keyed by unit, role
resolution per §2, threshold evaluation, and a single callback. **No drawing at
all in this phase.** The tier decision — which of the three a unit is in — lives
here and nowhere else, because 16c's "a capsule shows exactly one tier" is only
enforceable if one place decides it.

### 5.1 What Phase 1 actually found

Three things the plan above had wrong, all caught by the suite rather than in
game:

**`DAMAGER` must not beat the inference.** §2 assumed the assigned role would
read `NONE` and fall through. It does — *solo*. In a group the client calls
everyone who never answered a poll a `DAMAGER`, which the harness already knew
from an earlier screenshot of a real party. Take that at face value and every
real tank gets the DPS treatment, arriving through the one branch that looked
careful. Only an explicit `TANK` short-circuits now; everything else falls
through to the stance.

**The inference works for anybody, not only the player.** §2 restricted it on
the assumption that another unit's stance was not readable. A party member's
Defensive Stance is a buff like any other, so the restriction was protecting
nothing and cost the party capsules their correctness. Extended, deliberately.

**A pet never escalates.** 16c puts the alarm on your frame when a mob comes off
your pet; the pet losing it and you gaining it are one event, and the design
does not say the pet frame alarms too. Two alarms for one event is one too many,
so a pet is Tier 1 or nothing.

The engine also needed three mock fidelity fixes to be testable at all, each of
which was the mock being kinder than the client: the `*target` tokens were
absent entirely, `UnitThreatPercentageOfLead` was a stub returning the wrong
number, and there was no `GetSpellInfo` — so every spell id resolved to nothing
and "nobody is a tank" looked like a correct answer rather than a missing API.
The alias tokens had to resolve on every read rather than be snapshotted:
`__units.target` is reassigned throughout the nameplate tests, and a stale alias
gave the aliases a different GUID from the target, which reads as a whole group
of empty rings — i.e. as the design being quiet.

**Phase 2 — the ring. BUILT, 2026-08-21.** `Media.dial` is a family keyed by
name over one shared `Media.dialSheet`; the generator draws both bands from one
pair of functions (`_dial_track` / `_dial_arc`); `W.ThreatRing`,
`W.SetThreatRing` and `W.StepRingFade` are in `Core/Widgets.lua`; and
`TH:Draw` is the single subscriber that hangs one on whichever disc a unit's
frame carries — the party capsule's pip or the player and pet frames' orb, asked
of those modules' own `frames` lists rather than copied into them.

Three things worth recording:

- **No track behind the arc.** The console's dial has one because a flight has a
  length you are part way along. 16b describes an arc and nothing behind it, and
  below the floor it draws *nothing* — so a track would be a faint ring round
  every pip for the whole fight, which is what quiet-by-default is against. The
  generator no longer makes one.
- **The fade is a function, not an OnUpdate.** The suite delivers OnUpdate to
  one shared frame and not to every frame that asked for one, so a fade written
  straight into a `SetScript` is a fade nothing can watch — it would have
  shipped as "it looked right when I ran it". `W.StepRingFade(ring, dt)` is the
  step; the script is one line calling it.
- **A `tanking and 1` guard was unreachable and is gone.** The server reports a
  holder at a scaled 100, so the clamp already closes the ring. Removing the
  guard changed no check, which is how it was found.

**Phase 3 — escalation. BUILT, 2026-08-21.** `W.ThreatAlarm` /
`W.SetThreatAlarm` / `W.StepThreatAlarm` in `Core/Widgets.lua`, driven from
`TH:Draw` with the words and colours decided in `Modules/Threat.lua`. The chip
is `W.Pill` at a new `thChip` role, letter-spaced through `Media:Track`. The
pulse runs on the shared ticker (a tenth of a second is twelve steps across
1.2s) while the fade keeps its own frame; both are functions the suite can step.

Four things worth recording:

- **The alarm is a surface of OURS over the capsule**, not the capsule's own
  glass re-coloured. That glass already has owners — the party module tints it
  for offline and again for its highlight — and two writers on one property is
  a state that is right until the other one updates.
- **The chip hangs off the capsule's outer edge, not inside it.** 16c is
  explicit that the name, bars and role glyph all stay, and the design's capsule
  has no readout at its right end where ours does; inside, there is nowhere for
  it to go that is not on top of something. **This is the judgement call in
  Phase 3 and the first thing to look at in game.**
- **`Media:Track` was skipping any string with an em dash.** It bailed on any
  character whose lead byte was in the three-byte range, which is every
  three-byte sequence in UTF-8 — U+2014 included. Two of the four chips carry a
  real dash, so they came out untracked beside two that were. Now tested by code
  point against the actual CJK blocks. A shared helper, so this was wrong
  everywhere, quietly.
- **The failure chip's deeper red is derived, not a new token.** 16c gives it
  `#d9584a` against the border's `#f08a7a`; we keep the one red per §4 and
  deepen it where white type has to sit on it.

**Phase 4 — the alarms. BUILT, 2026-08-21.** `W.ScreenFlash` /
`W.StepScreenFlash`, fired from `TH:Alarm` on the *rising edge* into Tier 3 for
the player alone, rate-limited to one per six seconds, and gated on the
`alarms` setting. The ping is `SOUNDKIT.RAID_WARNING` (8959, in this flavour's
own constants file).

- **Its own texture, `Threat-Edge`.** `Media.texture.vignette` is authored
  BLACK — it darkens corners for Zen — and a vertex colour multiplies, so
  tinting it red gives black. The new one is white, with a square falloff so it
  hugs the four edges rather than making a circle in the middle of an ultrawide.
- **The rising edge is load-bearing and the rate limit hides it.** Fired from
  "is it true" rather than "did it just become true", holding aggro for seven
  seconds alarms twice for one event — invisible until the clock passes the
  limit. It took a check that advances time to catch.

This is still the phase most likely to be annoying in practice. Expect to tune
the beat length and the peak alpha in game.

**Phase 5 — nameplates. BUILT, 2026-08-21.** `TH:PlateFor` decides,
`TH:ScanPlates` caches it with the rest of the pass, and the deck's own
`ApplyEmphasis` reads it — **one writer on the border and the glow**, which is
the priority rule from §3 arriving as a single line rather than an arbitration.
Threat replaces the reaction colour and sets a floor under the emphasis; the
deck keeps scaling above it, so a red plate you are not targeting is still
dimmer than the one you are.

- **Cached, not queried per paint.** The deck repaints on its own animation
  frame; a threat call per plate per frame would be the most-called API in the
  addon. NKThreat caches the same lookups on a half-second window for the same
  reason. A colour is not a position.
- **Plates pulse at the warning tier's 1.2s even when red**, per 16d's "never
  faster than 1.2s" — a screen of plates beating at the capsule's 0.8s is a
  strobe.
- **A brightness pulse on a colour already at 1 in a channel is clamped there**,
  so red brightens by washing toward white. That is what a brightness ramp does
  and it reads correctly; it also means a check watching the red channel is
  watching nothing.

**Phase 6 — settings. BUILT with Phase 1**, because the suite's own guardrail
says a module with settings must be reachable from the panel and it would
otherwise have shipped unreachable. Four controls: enabled, display (rings and
warnings / rings only / nothing), the flash-and-ping toggle, and the role
override from §2. The 70 and 90 thresholds are *not* there and are not going to
be — a player who moves them has a ring that means something different from
everybody else's.

---

## 6. Risks worth naming now

- **The polling cost.** Threat is per unit *per mob*. A five-man group against
  eight plates is forty queries a tick if written naively. The engine must ask
  only what is being drawn: the player's own state every tick, plates on their
  own cadence, party members only while their capsule is up.
- **`scaledPct` out of combat and off-table returns nothing**, not zero. Every
  read needs the nil case, and "nil" means "show nothing", which is also the
  design's quiet default — so the two agree, but only if we never coerce nil to
  0 on the way in.
- **The pet rules in 16c are the fiddliest part of the design** and the hardest
  to test: they need a hunter or warlock, a pet, and a mob that breaks off.
  Expect them to be the last thing verified.
- **Tuning the pulse in game.** Every animation timing in the handoff is stated
  in CSS terms against a browser. 1.2s and .8s will transfer; brightness
  1 → 1.35 → 1 will need a look, because our glass is not a CSS filter.

## 7. Decisions taken

All four settled 2026-08-21, before any code was written.

1. **Role — assigned, then inferred, then DPS, with an override.** The scheme
   in §2 as written. `UnitGroupRolesAssigned` when it answers; otherwise, for
   the player only, Defensive Stance / Bear Form / Righteous Fury and their
   equivalents; otherwise DPS. Plus Auto / Tank / DPS-Heal in the settings,
   because inference is a heuristic and the player knows.

2. **Red is `Palette.c.danger`**, at its existing `#ff8a8a`. The design's
   `#f08a7a` is a departure, recorded here and nowhere else: `danger` is
   already a `SEMANTIC`, already invariant across skins, and already means
   exactly this. A ninth red 15/255 from the eighth is not worth the token.

3. **The ping is a client `SOUNDKIT` id.** No asset of ours, so it sits in the
   game's own mix and volume channels for free. Which id is a Phase 4 choice —
   short, non-diegetic, and not mistakable for a game event.

4. **A party member's ring measures against their own target**
   (`partyNtarget`), not yours. Each capsule is then true for what that person
   is actually fighting, which is the literal reading of "their own threat".
   The cost is accepted: in a split pull four rings can mean four mobs, and the
   ring is ambient information rather than a comparison table.

## 7a. Fixed on first contact with the game, 2026-08-21

Four faults, all from one screenshot, and three of them were things the suite
was asking the wrong question about.

**The ring never went away.** `W.SetThreatRing`'s clear path set the target
alpha and returned without starting the fade — so the ring was told to go and
nothing ever stepped it. It sat at full round the pip for the rest of the
session. The check beside it read `__aetherWant == 0`: it asked whether the ring
had been *told* to go, which is not the same question and is the easier one. It
now asserts the widget started the fade and that the ring is gone at the end
of it.

There was a second dead check under that one — it read `__aetherFading`, which
a fade earlier in the same block had set and which nothing in the suite ever
clears, so it was true whatever the code did.

**The ring was jagged, with gaps round the outer edge.** The generator
downsampled the dial with Lanczos, which has negative lobes and therefore
overshoots: the alpha through a full ring came back `0 1 0 17 237 255 255 188 0
2 0` — stray coverage *outside* the band on both sides, and a cliff from 188 to
nothing on the inner edge with no ramp. On a 3px band, minified again on screen,
that reads as a ring assembled out of segments. Now an area average, which is
the correct filter for a coverage mask and cannot ring, at a dial-local
supersample of 8.

**The ring sat a pixel up and left of the pip.** 44/38 of a 38 pip over the
0.875 inset is 50.3 units — a fractional number of pixels at any scale, so a
frame centred on another at that size puts its edges on half pixels. Snapped to
an *even* number of physical pixels, because half of an odd number is a half
pixel again.

**The chips vanished before they could be read.** 16c clears them within 500ms
of the state resolving and says nothing about a floor; in practice the state
does not linger — you cross the threshold and drop back — so you could tell
something had happened and had no idea what. A warning nobody can read is not a
warning. **Departure: the alarm holds itself up for three seconds** whatever the
state does, and a state that comes back during the wait cancels it rather than
letting it clear and flash up again. The pulse carries on while it waits: a
thing that stopped moving and then vanished reads as a glitch rather than as a
message ending. The **ring** is not held — it is the gauge and tracks the live
number.

And the chip moved: it now lies over the line beside the name ("Undead
Warlock", "Demon · Lv 8") rather than the readout. Called from the game, and better
one — that line does not change during a fight and is not what you are looking
at when a mob is coming for you.

## 7b. Two more departures, from playing it — 2026-08-21

Both from the same complaint, and it is a criticism of the design rather than of
the build: *"there isn't any real indication on my own frame until I'm basically
at 75% and in danger of pulling aggro. You're telling me what's happened, not
what's going to happen. I can't manage history."*

**Your own ring is always there.** 16b says a DPS below 70% shows nothing at
all. That is right for everybody else — four rings climbing across a party is a
wall of arithmetic and none of it is yours to act on — and wrong for you: a
gauge that appears once you are already in trouble is a report, and you cannot
pace something you cannot see. Your own ring now fills from zero, in the calm
accent, which is the colour 16b reserves for a role doing its job and is exactly
what a DPS under the floor is doing.

The halo still separates the two ambient states. A tank holding securely and a
DPS watching their own build share a tier and a colour; 16a gives the glow to
the one that is an achievement, and on a bar you are simply pacing it would say
something it does not mean.

**And the warning looks ahead.** 16c calls 70% "before the flip". It is not,
quite — a cast already in the air lands after the warning does, so at 70% and
climbing you are being told about something already decided. The module now
keeps a smoothed rate per unit and warns on `scaled + rate × 2.5s`, which is
about a cast: it turns "you are at seventy" into "the next one takes it".

Smoothed because threat arrives in lumps — a crit is a step, not a slope — and
projected **upward only**: threat does not fall except when somebody leaves the
table, and projecting a fall forward would cancel a warning at the exact moment
a tank taunted.

## 7c. Three more, from a second session — 2026-08-21

**The gauges disagreed with each other.** *"I was getting the 'losing aggro'
message on my pet, but no threat meter on my character... I just pulled aggro
from my pet and his gauge was still full."*

Each unit resolved its own mob: the player from `target`, the pet from
`pettarget`, each member from theirs. That is **two different threat tables**
the moment you are not targeting what your pet is fighting — two correct answers
to two different questions, which is the one thing a set of gauges must never
be. There is now one `FocusMob()` for the pass — your target, then its target,
then your pet's, then a member's — and everyone who is on that table is measured
against it. A unit that is not falls back to what it is fighting, which is
decision 7.4 and keeps a member off on their own from reading as idle.

**The warning arrived with the aggro.** *"I'm getting told I'm going to get
aggro, as I get aggro."* Averaging an increase is what made it late: at a fifth
of a second a sample, keeping 60% of the old rate takes about a second to catch
up with a climb that has already started. The rate now **attacks fast and
releases slow** — `max(instant, smoothed)` — so a climb is believed the moment
it is seen and a lull decays gently, which is the half the smoothing was ever
for. Lookahead raised from 2.5s to 3.

**And then it warned at eight per cent.** Two separate faults, and the second
guard hid the first well enough that the check for it had to be written twice:

- *No window.* Two points to eight in a fifth of a second is thirty per second,
  and three seconds of that projects to ninety-eight. A rate has a shortest
  stretch it may be measured over (0.75s) or it is a rounding error wearing a
  rate's clothes.
- *No near floor.* Early in a fight the holder's threat is small, so everybody's
  share of it moves fast — a projection on its own is arithmetically right and
  no use at all, because there is nothing to do about a number that far out. A
  projection may only warn once you are past **half** the floor.

## 7d. Who is tanking — the design's real gap

*"One of the things I'm missing is that it's not really clear who is tanking or
has aggro if the role hasn't been selected. Possibly a design flaw. What can we
do about it?"*

It is a design flaw, and §2 only half-answered it. 16b takes the role from the
assigned role glyph; Classic Era's roles are opt-in and almost nobody sets them,
so §2 added a stance inference — which covers a warrior, a druid and a paladin,
and nobody else. In a pick-up group nothing on screen said who was tanking.

**A third source, and on this client the best one: whoever has been holding the
fight.** The tank is not a setting, it is a fact about who the mob is
attacking, and that is a thing we are already reading every pass. Held time on
the current fight decides it, with two guards:

- **A settle of three seconds**, about a taunt cooldown, so a DPS who steals it
  for a moment is not promoted. If they were, the theft would come up in the
  calm accent and the whole feature would invert at the moment it is needed.
- **A margin of 1.5 seconds** over the next-longest holder, or the title changes
  hands on every trade, which is the opposite of what it is for.

**And before anybody is established, the holder is presumed to be doing their
job** — at the pull nothing has flipped yet, and the alternative is a red alarm
on the tank for the first three seconds of every fight.

The answer to "who is tanking" then falls out of the design's own language
without adding anything to it: the holder is a tank holding securely, which is
16a's one calm-accent state, so theirs is the capsule with the steady ring and
the halo on it. Everybody else under the floor shows nothing. The only lit ring
in the party is the tank's.

It also fixes a fault §2 had left behind: in a roleless group, whoever held
aggro was a "DPS" holding aggro, and got a red **AGGRO — ON YOU** chip for
tanking correctly.

## 7e. "I'm not sure I'd rely on it in combat" — 2026-08-21

Fair, and two of the three faults behind it were introduced by the fix in §7a.

**The capsule was telling two stories at once.** The dwell added in §7a holds
the chip and the wash up for three seconds after the state resolves; the ring
was left tracking live. So a chip reading AGGRO — ON YOU sat beside a gauge
already back down to two pips, and a "losing aggro" on the pet beside nothing at
all on the player. Both readings were true — of different moments. **The gauge
is now held with the message it belongs to**, and released when it is.

Two ordering traps in that, both caught by the suite and neither visible on
screen:

- Feeding the held record back into the *alarm* as well as the ring re-raises it
  from its own held state on every pass, cancelling the wait it is serving. It
  would have held for ever.
- `pending` is set **by** the call that decides the hold, so asking before it
  always read nil on the one pass that mattered — the ring cleared on exactly
  the frame the hold existed to cover, and the fix looked like it did nothing.

**And the gauge stopped being definitive about who has aggro** — which is §7d's
question again, and my own fault: §7b made your ring continuous, so a lit ring
no longer means "this one has it", it means "this one is a unit". The holder now
carries a **shield on the disc's fourth corner**, beside the crown, the raid mark
and the role glyph — said outright rather than implied by a colour that three
other states also use.

**Not yet explained:** "losing aggro on the pet with 0 gauge on my char" may be
entirely the two-stories fault above, or it may be a second thing. The next
report wants numbers rather than a description — extending `/aether threat
probe` to dump the module's own state per unit (mob, scaled, tier, reason, rate,
projection, plus the focus mob and who it thinks is tanking) is the cheap way to
get them, and is the next thing to do if it still feels wrong.

## 7f. The gauges still did not add up — 2026-08-21

*"I have 60% threat but the pet shows 100% still. We're not reducing their
threat by the amount I'm stealing."*

§7e mapped the holder's ring onto their **lead** — half again the runner-up's
threat counting as a full ring. That was far too generous and the picture proved
it: a warlock at 52% of the pull threshold already holds two thirds of the pet's
threat, and the pet still read 96%.

**The holder's ring is now the exact complement of the closest challenger's**,
and that means something precise rather than being a fudge. A challenger's ring
is their share of the *pull threshold* — at 1 they take it — so what is left of
the holder's is exactly how much headroom there is before somebody does. The two
sum to one. At 52%, the pet reads 48%.

Taken from the records for units we can see and from the server's own lead
figure when we cannot — somebody outside the group can be on the table, and
`100/lead` is the same reading one step earlier.

16b says the holder shows a full ring. They do, when there is nobody else on the
table. Below that this is the more useful reading, and it is what was asked for
twice.

## 8. What is left

All five phases are built and the suite is green. What remains is in game:

- **Look at the chip again.** It has moved to the line beside the name and it
  now holds for three seconds; both came out of the first look in game (§7a).
- **Tune the alarms.** Beat length, peak alpha, and whether `RAID_WARNING` is
  the right ping.
- **The pet rules (16c)** need a hunter or warlock, a pet, and a mob that breaks
  off it. They are the one part of the design that cannot be verified any other
  way — though the engine's pet cases are all covered by the suite.
- **A party run**, to see what `UnitGroupRolesAssigned` says about real group
  members and whether the stance inference picks up other people's tanks.

## 9. What was needed from the game

- **Nothing. Phase 1 is unblocked.** The probe answered on the second run
  (§1.1): the API works solo, with no group, and the numbers are good enough to
  build the ring's fill and both of 16a's tank thresholds straight off them.

  Worth one more run eventually, in a party, purely to see what
  `UnitGroupRolesAssigned` says about real group members — but that only
  affects other people's capsules, not your own, and §2 already assumes the
  worst there.
- **Tuning passes in game** for Phase 3's pulse and Phase 4's alarms. Both are
  stated in the handoff as CSS against a browser, and neither will transfer
  exactly.
- **A hunter or warlock, eventually.** The pet rules in 16c need a pet and a
  mob that breaks off it; they are the one part of the design that cannot be
  verified any other way.
