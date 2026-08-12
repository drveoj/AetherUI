# Plan: Toolbox

Design source: `E:\AetherUI Design\design_handoff_toolbox\` (README.md, `Toolbox.dc.html`,
screens 4a / 4b / 4c).

A slide-out drawer docked to the centre of a screen edge, with a slim rail that stays
on screen when the drawer is closed. Five things inside it: a What's-new card, six
live game widgets, an addon launcher with pin-to-rail, a grid of UI setting tiles,
and — not in the handoff, added deliberately — **Blizzard's micro menu**.

The handoff is marked high-fidelity, so colours, spacing, type and copy are final
intent. Two of its five sections turn out to be the hard ones, and neither is hard
for a visual reason: the addon launcher and the micro menu are both about owning
frames that belong to somebody else.

---

## 1. What the client actually gives us

Verified against `E:\wow-ui-source-classic_era` (Interface 11509) and against the
addons actually installed in `_classic_era_\Interface\AddOns`.

### 1.1 The micro menu is nine buttons, and they are not secure

`Blizzard_MicroMenu/Vanilla/MicroMenuContainerOverrides.lua` names the exact set
Era builds, in order:

```
CharacterMicroButton  SpellbookMicroButton  TalentMicroButton
QuestLogMicroButton   SocialsMicroButton    GuildMicroButton
WorldMapMicroButton   MainMenuMicroButton   HelpMicroButton
```

The XML declares sixteen `*MicroButton` frames, but the seven others
(`Achievement`, `Collections`, `EJ`, `LFG`, `PVP`, `Store`, `MainMenuBar`) are
never added on this flavour. **Take the list from the nine, probe each, and skip
what is absent** — the same rule the action bar sweep already follows.

Two facts decide the whole design of this section:

- **`MainMenuBarMicroButton` is a plain `<Button>`.** Not
  `SecureActionButtonTemplate`, not any `Secure*` inherit — the only inherits in
  that XML are `GameFontHighlightLeft`, `GlowBox*`, `MicroButtonAlertTemplate` and
  `UIPanelCloseButton`. So reparenting, moving and resizing them is unprotected
  and legal in combat.
- **Blizzard reparents them itself.** `MicroMenuMixin:AddButton` is literally
  `button:SetParent(self)`. The README's standing objection — *"reparenting
  Blizzard's own buttons onto a holder frame is the kind of hack that breaks
  quietly on a patch"* — is weaker than it looks: the supported container does
  exactly that, every login.

This is why the micro menu belongs here and not in a separate chrome module. It
is the one piece of banished furniture that is cheap and safe to adopt, and the
Toolbox is the surface with room for it.

### 1.2 `UpdateMicroButtons` is the state machine, and we already fight it once

`UpdateMicroButtons()` (`Classic/MainMenuBarMicroButtons.lua:565`) runs on a great
many unrelated events and re-derives every button's enabled/pushed state.

`Modules/QuestLog.lua` **already hooks it** (`QL:HookMicroButtons`) because
`QuestLogMicroButton`'s lit state is driven by `QuestLogFrame:IsVisible()`, which
is permanently false now that our log replaced it. That hook has to keep working
after the Toolbox adopts the button; it is a `hooksecurefunc` on a global, so it
composes, but the two must not both decide where the button lives.

**Ownership rule: QuestLog owns the button's *state*, Toolbox owns its *position*.**

### 1.3 The action bar sweep currently banishes the micro menu

`HideBlizzard` iterates Blizzard's own micro button table and hides the lot. That
is the current answer to "no micro menu or bag buttons" in the README's
deliberate-omissions list. The Toolbox has to *take* those buttons rather than
find them hidden, so the sweep needs an exclusion the same way the taxi button
already has one — and `/aether diag` should say which module owns them.

### 1.4 There is no such thing as "launching" an addon — there are two things that stand in for it

The design calls this an addon launcher, and the WoW model has nothing to launch:
an addon is loaded at login or it is not. Two mechanisms stand in, and the Toolbox
supports **both**, because plenty of addons offer one and not the other:

1. **An LDB `launcher` object** — `LibDataBroker-1.1`, the display-agnostic
   protocol Titan Panel, Bazooka, ChocolateBar and friends all consume.
2. **A minimap button** — either created by `LibDBIcon-1.0` from an LDB object, or
   hand-rolled and parented onto `Minimap`. This is the set
   `Modules/Minimap.lua` already collects.

They overlap heavily but neither contains the other, which is the whole problem:

| the addon has | what we can do | example population |
|---|---|---|
| LDB launcher **and** a LibDBIcon button | one entry, from the LDB object | most modern Ace3 addons |
| a hand-rolled minimap button, no LDB | one entry, replay the button's own `OnClick` | older addons |
| an LDB launcher, no minimap button | one entry — **this is what the current collector misses entirely** | addons whose button the user hid |
| neither | listed, not actionable (§3.3) | a great many |

**Dedupe key is the LDB object name.** `LibDBIcon:Register(name, object, db)` keys
`lib.objects[name]` by exactly that, and `lib:GetButtonList()` returns those names
— so a button and an object with the same name are one addon, not two entries.
Worth noting `Register` **errors** without `object.icon` and never inspects
`object.type`, so a LibDBIcon button is not proof of a launcher.

Two LibDBIcon copies are installed here (Questie's and TomTom's), so that path is
live on this machine.

**This is the single biggest architectural decision in the feature**, and §3.3
takes it seriously: the rail and the minimap drawer are the same idea drawn in two
places, and the launcher registry is a third source neither of them reads yet.

### 1.4a The LDB spec, and four things about it that bite

Read from `LibDataBroker-1.1.lua` (90 lines, definitive) and from Titan's
`TitanLDB.lua`, which is the most careful consumer on this machine.

The registry:

```lua
ldb:DataObjectIterator()          -- name -> dataobj
ldb:GetDataObjectByName(name)
ldb:GetNameByDataObject(obj)
ldb.RegisterCallback(self, "LibDataBroker_DataObjectCreated", handler)
ldb.RegisterCallback(self, "LibDataBroker_AttributeChanged__icon", handler)
```

Two object types, and only the first is wanted for the addon list:

- **`launcher`** — `type`, `icon`, `OnClick` required; `label`, `tocname` optional.
- **`data source`** — `type` and `text` (or `value` + `suffix`) required; `icon`,
  `OnClick`, `label`, `OnEnter`/`OnLeave`, `tooltip`, `OnTooltipShow` optional.
  Not an addon launcher, and §3.7 puts it to a different use.

And four traps:

- **`pairs(dataobj)` returns nothing.** Every field lives in the library's
  `attributestorage`, reached through an `__index` metamethod, and the metatable
  is `"access denied"`. Iterate with `ldb:pairs(obj)`; index with `obj.icon`,
  which the metamethod serves. Anything that walks a dataobj with plain `pairs`
  silently sees an empty table.
- **Read the scripts at call time, never cache them.** Titan always re-reads
  `obj.OnClick` when the click happens, deliberately: *"allows the LDB to update
  its scripts as needed"*. An addon that swaps its own `OnClick` after login is
  normal, and a captured reference goes stale without ever erroring.
- **Tooltip method is genuinely ambiguous in the spec** — `.tooltip` (a frame),
  `OnTooltipShow(tt)` (fill one we pass), and `OnEnter`/`OnLeave` (full control)
  all exist with no stated precedence. Titan's own comment says the spec "is
  unclear on priority of method to choose". Its resolution, which we should copy
  rather than invent: `.tooltip` → `OnEnter`/`OnLeave` → `OnTooltipShow`.
- **`.tooltip` must not be a `GameTooltip`.** Titan's header says so in four
  exclamation marks, having been bitten.

Everything is `pcall`ed. These are other people's functions running inside our
click handler, and one throwing must cost that row, not the drawer.

### 1.5 Addon metadata is thin, and the design's placeholder is the right answer

`C_AddOns.GetNumAddOns` / `GetAddOnInfo` / `GetAddOnMetadata` all exist on 1.15
(`Blizzard_PerformanceBar/PerformanceBar.lua:125-156`).

But **only 13 of the 24 addons installed here declare `## IconTexture`**. Just
over half. The handoff says "Addon glyph tiles are placeholder letter-on-gradient;
in-game use real addon icons" — that instruction cannot be followed for the other
eleven, and a grid where half the tiles are a question mark looks broken.

So the letter-on-gradient tile is **not** a placeholder here, it is the base case:
use the declared icon where there is one, fall back to the initial on a gradient
derived from the addon name, which is what the mock already draws.

### 1.6 The six widgets are all reachable

| widget | API | note |
|---|---|---|
| Gold | `GetMoney()` | format with the deck's `14g 32s` |
| Bag space | `C_Container.GetContainerNumFreeSlots(i)` over 0–4 | free/total |
| Durability | `GetInventoryItemDurability(slot)` over the 17 equip slots | min or mean — pick one and say which |
| XP / hr | none | **must be computed**; see §3.5 |
| Latency | `GetNetStats()` → 3rd/4th return | the client refreshes it about every 30s, so polling faster is a lie |
| FPS | `GetFramerate()` | |

XP/hr is the only one with no API behind it at all.

But the shape they are *delivered* in is a separate question from where the
numbers come from, and §3.7 answers it differently from the handoff.

### 1.7 Settings tiles: four map, two do not

| tile | binds to | |
|---|---|---|
| Zen | `modules.zen.enabled` | exists |
| Combat collapse | `modules.questtracker.combatCollapse` | exists (`Config.lua:267`) |
| Keybind chips | `modules.actionbars.showKeybinds` | exists (`Config.lua:134`) |
| Damage numbers | CVar `floatingCombatTextCombatDamage` | **not ours** — a client setting, so borrow/give-back like `Zen` |
| Damage meter | — | **not a setting at all** — an addon launcher; see §6.2 |
| Daylight skin | `profile.skin` | **not built** — see §6.3 |

Four of the six are not the same kind of thing, which is the finding: two config
paths, one CVar, one launcher, one deferred. A grid of six hard-coded tiles would
have had to pretend otherwise.

---

## 2. The compatibility contract

Fewer rules than Tooltips needed, but the ones there are matter more, because this
module *takes possession* of frames rather than decorating them.

### 2.1 Every adopted frame is borrowed, and borrowing means giving back

The micro buttons and the collected addon buttons both belong to somebody else.
`OnDisable` has to return them — parent, position, scale, and for the addon
buttons the drag scripts LibDBIcon owns. This is the same contract
`Modules/Zen.lua` applies to CVars, and it should reuse the shape: record what was
there, write ours, put theirs back only if ours is still what is set.

### 2.2 Never `Hide` a collected button, ever

`Modules/Minimap.lua` already learned this and the README records it twice: a
collected button may carry a secure template, and hiding a frame with a protected
descendant is refused in combat. The drawer and the rail open and close on
**alpha and `EnableMouse`**. The Toolbox inherits the rule wholesale — and it is
sharper here, because a drawer is a thing people open mid-fight.

The micro buttons are exempt (§1.1, plain Buttons) but should follow the same path
rather than being the one thing in the module that does it differently.

### 2.3 `LibDBIcon:Lock()` before moving anything

Its drag handlers recompute an angle from the cursor and re-anchor to the
minimap's centre every frame. `ldbi:Lock(name)` is the supported off switch and
survives a refresh; a hand-rolled button gets its drag scripts removed instead.
Already solved in `Minimap.lua`; do not solve it again differently.

### 2.4 Widget polling gets one ticker, and it is the shared one

Six widgets, none of which needs to be right more than about once a second.
`A:RegisterTicker` exists precisely so modules do not each grow an `OnUpdate`.
FPS and latency are the only ones worth even 1 Hz; gold, bags and durability are
event-driven (`PLAYER_MONEY`, `BAG_UPDATE`, `UPDATE_INVENTORY_DURABILITY`) and
should not poll at all.

**A drawer that is closed polls nothing.** The rail shows no numbers.

---

## 3. Architecture

One module, `Modules/Toolbox.lua`, plus one shared service extracted from
`Minimap.lua` (§3.3). Six sections, each of which degrades on its own.

| Layer | What it does | Risk |
|---|---|---|
| 1 · Frame | Drawer + rail, dock edge, open/close slide, scrim | none — all ours |
| 2 · Widgets | Six LDB `data source` objects we publish, displayed by a grid that will show anyone's (§3.7) | we become a provider |
| 3 · Addons | List, pin toggle, rail icons — on the shared collector | **the collector move, §3.3** |
| 4 · Settings | Data-driven tiles: config path, CVar or launcher (§6.2) | mixed entry kinds |
| 5 · Micro menu | Adopt the nine, lay them out, hand them back | **ownership vs QuestLog + ActionBars** |
| 6 · What's new | Version chip, unread dot, notes text | none — static content |

### 3.1 Geometry, and the one number to check first

The deck is 1920×1080; the addon draws at `profile.scale` 0.71 like every other
module. So:

- vertical drawer **388×910** deck px → **276×646** virtual units, against a 768
  virtual screen height. Fits, with 122 to spare.
- horizontal drawer **1280 wide** → **909** of 1365. Fits.

Both are close enough to the edges that the *first* thing to build is the empty
panel at both docks, at 0.71 and at 1.0, before any content goes in it. The quest
log and bags both hard-code a size; this one has two.

Rail: the screenshots put it at roughly 52 deck px wide — 34px icons at radius 11
plus padding. Derive it from the icon size rather than writing 52 down.

### 3.2 Docking is not a Mover

Every other placeable frame in this addon uses `Core/Movers.lua`. The Toolbox
should **not**, and it is worth saying why up front so nobody wires it in later:
a mover expresses "anywhere, remembered against the nearest corner", and this
drawer has exactly four legal positions, each of which changes the panel's
*layout* rather than its offset.

What it needs instead is a drag on the rail that lights four ghost targets and
snaps to whichever is nearest on release. The snapping maths in `Movers.lua`
(`GetCursorPosition` in true screen pixels, divided by UIParent's effective scale
and never the frame's) is the part worth reading before writing this — it is the
one trap the drop maths already fell into once.

`docked` and `open` persist in **`db.char`**, per the handoff. Character scope is
right: a drawer edge is a per-character habit the way tracked quests are.

### 3.3 The collector has to move, and this is the decision to take first

`Core/Launchers.lua` has to merge **three** sources into one deduped list (§1.4):
the LDB launcher registry, LibDBIcon's buttons, and hand-rolled minimap buttons.
Only the last two exist today.

`Modules/Minimap.lua` owns three overlapping passes that find every addon button
on the machine — the LibDBIcon registry, a filtered walk of `Minimap:GetChildren()`,
both retried on a timer for fifteen seconds — plus the `issecurevariable` filter
that sorts Blizzard's furniture from third-party arrivals, the pin-addon
exclusions, and the unbound `RawSetPoint` trick for buttons that stomp their own
methods.

That is a lot of hard-won behaviour, and the Toolbox rail needs all of it — plus
the launcher registry it has never read, plus the dedupe between them.

**What an entry looks like** matters more than where it came from:

```
{ key, name, label, icon, click(), source = "ldb" | "dbicon" | "minimap" }
```

`click()` is the thing that differs: an LDB object's own `OnClick`, re-read at
call time (§1.4a); or a replay of the collected button's `OnClick`. Everything
above it — the list, the rail, the pin state — sees one shape.

**And the addon list is a superset of the actionable set.** `C_AddOns` knows every
loaded addon; only some of them offer a launcher or a button. A row with neither
is still worth listing — the player wants to know what is loaded — but it has no
click and no pin, and must *look* like it has none rather than silently doing
nothing when clicked. That is the single most common case (§1.4's fourth row), so
it is the case to design first, not last.

Three options, and the recommendation is the third:

1. **Toolbox reads `Minimap.buttonOrder`.** Cheapest, and wrong: it makes a
   headline feature depend on a module the user can switch off, and two modules
   would be positioning the same frames.
2. **Toolbox runs its own scan.** Duplicates ~200 lines of the subtlest code in
   the addon, and the two copies drift the first time somebody fixes a bug in one.
3. **Extract `Core/Launchers.lua`.** A service that owns discovery and hands out a
   stable ordered list, with `Claim(button, owner)` / `Release(button)` so exactly
   one surface positions a given button at a time. Minimap and Toolbox both become
   consumers; whichever is enabled claims, and if both are, the Toolbox wins and
   the minimap drawer reports it in `/aether diag`.

Option 3 is more work up front and is the only one that does not leave a bug
waiting. It is also settled by §6.1 — the drawer retires and the rail takes over —
which makes the service the migration path rather than a nicety, and by §6.2,
which puts a third consumer (the settings grid) on the same data.

### 3.4 The micro menu inside the drawer

Not on the rail. The rail is for things you reach for constantly and its slots are
spoken for by pinned addons; the micro menu is nine buttons you want occasionally
and want to *find*, which is a job for the drawer.

Placement: a row under the header, above What's-new — it is chrome, not content,
and putting it at the bottom means scrolling past the addon list to reach the
character sheet.

Mechanics:

- Adopt on enable, out of combat is unnecessary (§1.1) but harmless to prefer.
- `SetParent` onto a holder, `ClearAllPoints`, lay out on our own grid, and
  **leave every script alone**. Their OnClick already does the right thing and
  reproducing `ToggleCharacter("PaperDollFrame")` by hand is how you get it subtly
  wrong for one of the nine.
- The stock artwork is the same problem the action buttons solved: hide the
  Blizzard textures, draw our own glass chrome, keep the button. `MicroButtonAlert`
  (the tutorial popups) should be suppressed while adopted.
- `UpdateMicroButtons` will keep re-deriving state. That is fine and wanted — it
  is what makes the quest log button light up. Only ever *read* it.
- Give the buttons back on disable, and put them back where the ActionBars sweep
  would have left them, which is hidden.

The interlock with §1.2 and §1.3 is the only genuinely fiddly part of this module,
and `/aether toolbox` should print, for each of the nine: present, adopted,
enabled, and who owns its state.

### 3.5 XP/hr has no API and must not lie

Session-tracked: sample `UnitXP("player")` and `GetTime()` at enable, recompute on
`PLAYER_XP_UPDATE`, and rate = gained / elapsed. Three things it has to get right,
all of which are ways of showing a confident wrong number:

- **A level-up resets the numerator, not the session.** `UnitXPMax` changes and
  `UnitXP` drops to near zero; the delta across that boundary is
  `(max - before) + after`, not `after - before`.
- **Rested XP inflates the rate** and is not sustainable. Either say so or ignore
  it; do not quietly report a rate nobody can reproduce.
- **The first sample is not a rate.** Under some seconds of elapsed time it should
  read `—`, not a number computed from a two-second window. Same discipline as the
  aura tile that refuses to print a timer it does not have yet.

### 3.7 The widgets are LDB data sources, and the grid is a display for anybody's

The handoff draws six fixed cards. Instead, AetherUI **registers each widget as an
LDB `data source`** and the grid is a display that renders whatever data sources
the player has chosen — ours first, because ours are the six that ship.

This costs almost nothing and buys three things:

- **Other people can write widgets.** A data source is ten lines and needs no
  knowledge of this addon. That is the entire point of the protocol, and it is the
  half of LDB the addon list has no use for.
- **The grid stops being a layout and becomes a list**, exactly like the settings
  tiles (§6.2) and `pinnedAddons`. Same storage conventions, same reordering.
- **Our numbers show up in Titan, Bazooka and ChocolateBar for free**, because
  publishing is publishing. Somebody running Titan gets AetherUI's XP/hr in their
  bar without us doing anything, which is a better outcome than a sixth private
  implementation of gold-per-hour.

The mapping from a data source to the deck's card is where the care goes. The card
has a **big value** and a **small label**; LDB offers `text`, or `value` + `suffix`,
plus `label`:

| the object provides | big | small |
|---|---|---|
| `value` + `suffix` (+ `label`) | `value .. suffix` | `label` |
| `text` only (+ `label`) | `text` | `label` |
| `text` only | `text` | the object's registered name |

Ours are written to the first row, because that is the shape the deck draws. Third
party sources overwhelmingly use the second — often with colour escapes baked into
`text` — so the card must tolerate a `text` that is already formatted and must not
try to parse it. **Render it, do not interpret it.**

Updates come from `LibDataBroker_AttributeChanged__text` / `__value` / `__icon`
callbacks rather than polling, which also disposes of §2.4 for third-party
widgets: their author decides the update rate, not us. Ours keep the event-driven
sources from §1.6 and only FPS and latency tick.

`Libs/` already carries `CallbackHandler-1.0`, which LDB requires.
**`LibDataBroker-1.1` itself has to be added** — 90 lines, and the same
permissive redistribution story as Ace3.

One consequence to be honest about: registering a data source means the name is
global and permanent for the session. `AetherUI_Gold` and friends want a prefix
that cannot collide, and once published the name is a contract with whoever is
displaying it.

### 3.8 The scrim

`linear-gradient from rgba(0,0,0,.28)` over the strip the drawer covers. In-game
that is a texture with a vertical or horizontal gradient — `Media/Textures` has no
plain gradient yet, so this is one new asset from
`Tools/generate_textures.py`, or a `SetGradient` on a solid, which Classic Era
does support and costs no file. Prefer the latter: a new `.tga` needs a client
restart, not a `/reload`.

---

## 4. Build order

1. `Core/Palette.lua` — any `tb*` tokens the deck introduces beyond the existing set.
2. `Core/Media.lua` — `tb*` font roles.
3. `Libs/LibDataBroker-1.1` — bundle it; `CallbackHandler-1.0` is already there.
4. **`Core/Launchers.lua`** — extract discovery from `Minimap.lua`, add the LDB
   launcher registry as a third source, dedupe by LDB name; make Minimap a
   consumer; prove the drawer still works unchanged. **No Toolbox code yet.**
   The drawer gaining launcher-only entries it never had is the proof the merge
   works, and it is visible without any Toolbox at all.
5. `Modules/Toolbox.lua` layer 1 — panel and rail at all four docks, open/close,
   scrim, persistence. Empty inside.
6. Layer 6 (What's new), then layer 2 (widgets) as LDB data sources (§3.7) — cheapest content, exercises layout.
7. Layer 4 (settings tiles).
8. Layer 3 (addons) on the service from step 4.
9. Layer 5 (micro menu), with the ActionBars exclusion and the QuestLog interlock.
10. `Core/Config.lua`, `Core/Options.lua`, `Core/Commands.lua` — defaults, options
   page, `/aether toolbox` diagnostic.
11. `AetherUI.toc`.
12. `Tools/harness.lua` throughout, not at the end.
13. **Separately, after the rail has shipped**: default `minimap.drawer` to off
    (§6.1). Not part of the Toolbox commit — a rail that turns out wrong must be
    revertible without taking addon-button access with it.

Step 4 before step 5 is the whole point of the ordering: the refactor lands while
the only consumer is the module that already works, so a regression is visible
immediately instead of being tangled up with new code.

## 5. Harness

The mock needs: `C_AddOns.*`, `GetAddOnMetadata` returning an icon for some addons
and nil for others (§1.5 is a real branch), the nine micro buttons as plain frames
with scripts that record being clicked, `GetMoney`, `GetNetStats`, `GetFramerate`,
`GetInventoryItemDurability`, and a fake LibDBIcon registry.

Assertions worth writing, each mutation-tested:

- the drawer lays out at all four docks, at scale 0.71 **and** 1.0, and stays
  inside the screen at both
- opening and closing in combat never calls `Hide` on a collected button
- a claimed button has exactly one owner; enabling both Minimap and Toolbox does
  not leave two surfaces positioning it
- `OnDisable` returns every micro button and every collected button to where it
  came from — parent, point, scale
- an addon with no `IconTexture` gets the letter tile, not a blank
- XP/hr across a simulated level-up reports the crossing correctly, and reports
  `—` before enough time has passed
- a dataobj is never walked with plain `pairs` — the mock's LDB must use the real
  metatable trick, or that bug cannot be caught here at all
- a launcher whose `OnClick` is swapped after registration gets the NEW one called
- an addon with a launcher and a LibDBIcon button appears ONCE
- an addon with neither is listed, not clickable, and looks it
- a third-party data source with only `text` renders, and its formatting is not
  parsed
- every option path in the new page resolves
- the ActionBars sweep does not hide a micro button the Toolbox has adopted
- `QuestLog`'s micro-button state hook still fires after adoption

The trap to watch, given how this module works: **a test that asserts we called
`SetParent` proves nothing about whether the button is visible or clickable.**
Prefer asserting the end state — parent, points, shown, mouse-enabled — the way
the aura tray tests do.

## 6. Decisions taken

The three open questions, answered 2026-08-12. None of them changes a pixel; all
three change a module boundary, which is why they were worth asking first.

### 6.1 The rail replaces the minimap button drawer

`Modules/Minimap.lua`'s drawer retires once the rail is real. That makes
`Core/Launchers.lua` (§3.3) not an optimisation but the actual shape of the
feature — and it upgrades step 3 from a refactor to a migration:

- the drawer stays working through steps 3–7, on the service, so there is never a
  point where addon buttons are unreachable;
- it comes out in its own commit *after* the rail ships, not as part of it, so a
  rail that turns out wrong can be reverted without taking button access with it;
- `minimap.drawer` becomes a setting that defaults **off** rather than code that
  is deleted, until a version has shipped with the rail.

The pill's hover chevron, the mail pill's side-picking and the "nothing left in
it, so the chevron goes" logic all belong to the drawer and go with it. Nothing
else in `Minimap.lua` is affected.

### 6.2 The settings tiles are data-driven

"Damage meter" is not a setting this addon owns and was never meant to be one — it
stands for *an addon that exposes an LDB launcher or a minimap button*. So the
grid is a list, not a layout, and it has two kinds of entry:

| kind | source | click does |
|---|---|---|
| `setting` | a config path, as §1.7 | writes the path, runs its `after` |
| `cvar` | a CVar name | `SetCVar`, borrowed and given back like `Zen` does |
| `launcher` | `Core/Launchers.lua` | invokes that launcher's own `OnClick`, re-read at call time (§1.4a) |

Which means the same discovery service feeds the addon list, the rail *and* half
the settings grid — three surfaces, one collector, which is the strongest argument
yet for doing §3.3 first.

Two consequences worth stating:

- **A launcher tile has no On/Off state to show.** LDB launchers are buttons, not
  toggles; a `data source` feed can carry text, but a launcher cannot answer "are
  you on". So launcher tiles draw the addon's icon and name with no state chip,
  and the chip is reserved for entries that genuinely have two states. Drawing a
  fake one would be the tooltip-badge mistake in a different costume.
- **The set is per-character and reorderable**, since it is a list. That is the
  same shape as `pinnedAddons`, and the two should share their storage
  conventions.

### 6.3 Daylight is deferred, so the skin tile is not built

The Daylight skin is on hold until everything currently being reworked is
finished; a full pass happens then. So the handoff's sixth tile is **not built**,
rather than built and hidden.

This does not change how modules are written. Tokens still go into **both** skins
as each surface is built — that costs nothing at the time and is expensive to
retrofit, and the harness's existing Daylight assertions stay exactly as they are.
Several of them exist because a colour check on Midnight alone proved nothing.
What is deferred is *tuning and judging* against Daylight, not writing it down.

When it does come back it should not return as a boolean: a tile reading `On/Off`
is the wrong shape the moment there is a third skin, and the palette is built so a
skin costs only a colour table.

## 7. Known fidelity gaps

Honest list up front, so they are not re-litigated from a screenshot:

- **No blur.** Same as every other Aether surface; the rim and the falloff carry
  it (`Core/Glass.lua` header).
- **No CSS `backdrop-filter` on the rail either** — the deck gives it its own
  28px blur at a different tint from the panel. Two glass treatments that differ
  only by blur radius will look identical in-game; the rail should be
  differentiated by *tint and rim* instead, or it will read as a seam.
- **Slide animation is ours to fake.** There is no transition system; an
  `OnUpdate` lerp over 300–400ms, and it must be interruptible — clicking the
  chevron twice quickly should reverse, not queue.
- **Addon icons for the eleven that declare none** are initials on a gradient
  (§1.5), which is a deliberate departure from "use real addon icons".
- **The unread dot needs a notion of "read".** Persist the last version whose
  notes were seen; without that it is either always lit or never.
