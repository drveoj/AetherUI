# Plan: Tooltips

Design source: `E:\AetherUI Design\design_handoff_tooltips\` (README.md, `Tooltips.dc.html`,
screens 6a and 6b).

The brief has two halves and the second one is the hard one:

1. Make tooltips look like the rest of Aether UI.
2. Do not stop other addons putting things in them.

Joe runs MobInfo2, Pawn, VendorPricePlus, Bagnon/BagBrother, Questie and the whole
Auctioneer suite (Informant, Enchantrix, BeanCounter — all of which go through
LibExtraTip). Every one of them writes into `GameTooltip`. That constraint decides
the architecture before any of the visual decisions do.

---

## 1. What the client actually gives us

Verified against `E:\wow-ui-source-classic_era` (Interface 11509). Three findings
changed the plan:

**`TooltipDataProcessor` does not exist here.** `Blizzard_SharedXMLGame.toc:9` marks
`Tooltip\TooltipDataHandler.lua` as `[ExcludeLoadGameType vanilla]`, and
`TooltipUtil.lua` / `TooltipDataRules.lua` / `TooltipComparisonManager.lua` are all
`[AllowLoadGameType mainline]`. `C_TooltipInfo` is never called from the Classic
load path. Anything written against the retail data-processor API is nil here.

**The old script events are the supported mechanism.** `GameTooltip.xml:22-24`
wires `OnTooltipSetUnit` / `OnTooltipSetItem` / `OnTooltipSetSpell` directly.
`GameTooltip_OnTooltipSetUnit` (`GameTooltip.lua:498`) does nothing but recolour
line 1. So do we.

**There is no `SetBackdrop` on GameTooltip.** The template inherits
`TooltipBackdropTemplate`, not `BackdropTemplate` — the border is a
`NineSlice` child (`GameTooltipTemplate.xml:22`,
`SharedTooltipTemplates.xml:104-114`). `SetBackdropColor` and
`SetBackdropBorderColor` exist only as shims onto that NineSlice
(`SharedTooltipTemplates.lua:243-261`).

Three more facts that each cost a decision:

- `GameTooltip.StatusBar` is **nil** — the XML declares `$parentStatusBar` with no
  `parentKey` (`GameTooltipTemplate.xml:138`). Only the global
  `GameTooltipStatusBar` exists, it is 8px tall, and it is anchored **below** the
  tooltip's bottom edge, not inside it. Its colour is forced green by
  `HealthBar_OnValueChanged` (`HealthBar.lua:2-32`) unless `lockColor` is set.
- `SharedTooltip_SetBackdropStyle` re-applies the default NineSlice layout **and**
  the default centre colour on every `GameTooltip_OnHide` (`GameTooltip.lua:414`)
  and on every item tooltip via `GameTooltip_UpdateStyle` (`:505`). Suppressing the
  stock art once at login does not hold.
- `GameTooltipTextLeft1` is anchored `TOPLEFT 10,-10`
  (`GameTooltipTemplate.xml:25-29`). The tooltip's own box therefore already
  carries 10px of padding, which is what the glass card's insets are measured
  against.

---

## 2. The compatibility contract

This is the part worth being strict about. Each rule below exists because a
specific addon in Joe's folder would otherwise break.

### 2.1 `HookScript` only — never `SetScript`

MobInfo2 does this (`MI2_Events.lua:170-171`):

```lua
MI2_TT_SetItem = GameTooltip:GetScript("OnTooltipSetItem")
GameTooltip:SetScript("OnTooltipSetItem", MI2_OnTooltipSetItem)
```

LibExtraTip does the same thing (`LibExtraTip.lua:473`, via
`private.HookScriptBasic`). Both capture the previous handler and call it, so they
compose with a `HookScript` chain **in either load order** — but only as long as we
do not also replace the script. If AetherUI called `SetScript`, whichever of the
two loaded first would be silently dropped.

Same rule for globals: `hooksecurefunc("GameTooltip_SetDefaultAnchor", ...)`, never
a reassignment. Classic's version sets `tooltip.default = 1`
(`GameTooltip.lua:112`) and other addons read that flag.

### 2.2 Layout is driven by `OnSizeChanged`, not `OnShow`

Pawn `hooksecurefunc`s about thirty `GameTooltip:Set*Item` methods
(`Pawn.lua:252-309`) and adds its lines *after* the tooltip is already up.
VendorPricePlus and the LibExtraTip consumers do the same. A card sized once on
`OnShow` would be the wrong height for every tooltip those addons touch.

LibExtraTip itself hooks `OnSizeChanged` (`LibExtraTipHandler_HookSet.lua:879`)
for exactly this reason. We follow it.

### 2.3 The unit header does minimal, idempotent, order-independent surgery

MobInfo2 appends to line 2 (`MI2_Tooltip.lua:381-383` and `:408`):

```lua
GameTooltipTextLeft2:SetText( txt.." "..mobData.class )
```

The design's level badge needs `"Level 18"` out of that same line. So:

- We **strip only the leading level token** and keep the remainder verbatim.
  MobInfo2's addition lives at the *end* of the line, so it survives whichever of
  us runs first.
- The pattern is built from the client's own `UNIT_LEVEL_TEMPLATE` / `LEVEL`
  globals, not from an English literal, and it tolerates `??` for bosses.
- If the pattern does not match — different locale, another addon rewrote the line
  first — we **skip the badge and leave the line alone**. No badge is a much better
  failure than a mangled tooltip.
- The operation is idempotent, which matters: the tooltip's own `OnUpdate` re-runs
  `SetUnit` every `TOOLTIP_UPDATE_TIME` for a mouseover, so our hook fires roughly
  five times a second on fresh text.

We never delete a line, never hide a line, and never call `SetText` on a line we
did not first successfully parse.

### 2.3a …and appending is not the only thing MobInfo2 does to that line

This plan's first draft justified the strip on the grounds that MobInfo2 only
appends. That was wrong, and it is worth recording why rather than quietly
correcting it.

MobInfo2 also **reads the level back out of the line**, to find where a mob's
extra info starts (`MobInfo2.lua:2118-2131`):

```lua
levelInfo = tostring(mobLevel)
if not (issecretvalue and issecretvalue(ttLeft)) and string.find(ttLeft, levelInfo) then
    levelLine = idx
```

It is scanning for the level **number as a substring**. Take the number out and
the scan finds nothing, every following line falls through the same branch, and
the harvest comes back empty. That path is its shipped default —
`MobInfoConfig.UseGameTT == 0` (`MobInfo2.lua:670`).

There is no clever resolution: the digits are either in the line or in the badge.
So the module **yields**. `LevelReader()` detects the condition — by the setting
inside `MobInfoConfig`, not merely by the addon being loaded, since its
own-window mode does not do that scan — turns the strip off by itself, and says
so in `/aether tooltips`. `deferToLevelReaders = false` overrides it.

The general lesson, which the next module that touches somebody else's frame
should inherit: **grep the other addon for reads, not just writes.** "It only
appends" was an assumption drawn from one call site.

### 2.4 Padding may change; the right-hand column adapts

LibExtraTip re-lays the right column with
`local xofs = width - tooltip:GetPadding() - 20.5` (`LibExtraTip.lua:1222`). It
reads `GetPadding()` live, so changing the tooltip's padding is safe. Worth
recording because it is exactly the kind of thing that is *not* safe by default.

### 2.5 Font objects, not per-line fonts

Restyling `GameTooltipHeaderText` / `GameTooltipText` / `GameTooltipTextSmall`
(`Blizzard_Fonts_Shared\Shared\FontStyles.xml:314-320`) reaches every line in
every tooltip — including lines Pawn and MobInfo2 add later. That is the feature,
not a side effect: their lines come out in Outfit without either addon knowing.

---

## 3. Architecture

One module, `Modules/Tooltips.lua`, structured as five independent layers. Each
degrades on its own; turning one off does not disturb the others.

| Layer | What it does | Risk |
|---|---|---|
| 1 · Card | Glass panel behind each registered tooltip, sized from `OnSizeChanged`; stock NineSlice suppressed and re-suppressed after `SharedTooltip_SetBackdropStyle` | none — additive |
| 2 · Type | Outfit on the three tooltip font objects at the deck's sizes | none — inherited by everyone |
| 3 · Colour | Reaction-coloured name on `OnTooltipSetUnit`; quality-coloured title, rim tint and glow on `OnTooltipSetItem` | none — recolour only |
| 4 · Header | Level badge, ELITE chip, restyled health bar with `Health` / `1,240 / 1,240` labels | the line-2 surgery in §2.3 |
| 5 · Anchor | Default anchor routed to a Movers-registered frame; cursor-follow for default/world item and spell tooltips | scoped in §3.4 |

### 3.1 The card

`Glass.CreatePanel(tip, { corner, shadow })`, parented to the tooltip at
`frameLevel - 1`. Anchored to the tooltip's own bounds and pushed outward:

```
TOPLEFT      -(gutter + 8), +5
BOTTOMRIGHT  +8, -4
```

Those insets take the tooltip's built-in 10px text padding
(`GameTooltipTextLeft1` at `TOPLEFT 10,-10`) up to the deck's `padding: 15px 18px
14px`. `gutter` is 0 normally, and `26 + 9 = 35` when a level badge is showing —
which is how the badge gets room to the left of the name without touching a single
FontString anchor.

When `GameTooltipStatusBar` is visible the card's bottom follows the bar instead of
the tooltip, because the bar hangs below the tooltip's own box by Blizzard's design
and the deck draws it inside the card.

Suppression of the stock art happens in `StripArt(tip)`, called from: registration,
`OnShow`, `OnSizeChanged`, and a `hooksecurefunc` on
`SharedTooltip_SetBackdropStyle`. Four call sites because §1 says it comes back.

### 3.2 Typography

New `tt*` roles in `Media.style`, at the deck's own point sizes. The whole tooltip
is drawn at `profile.scale` (0.71 by default), exactly like the quest log and the
bags window, so the deck's 15px title lands where the deck put it. Half-points are
rounded — the rasteriser rounds anyway.

### 3.3 Colour

New token block in both skins. The deck introduces four colours the palette does
not have (`#f0ecff` title ink, `#e8d49a` lore gold, `#e8c86a` elite gold,
`#cdbcff` guild accent) and reuses several it does. Reaction name colours map onto
existing `hostile` / `neutral` / `cast[1]` values, but get their own `tt*` names so
retuning a cast bar cannot silently retune a tooltip — the same reasoning the bags
block records at `Palette.lua:106-114`.

Item quality reuses `Palette.c.itemQuality`, whose hues already match the deck's
scale to a digit.

### 3.4 Anchoring

**Unit tooltips** never follow the cursor. `hooksecurefunc` on
`GameTooltip_SetDefaultAnchor` re-points the tooltip at `TT.anchor`, a zero-size
frame registered with `A.Movers` under the name `tooltip`, default
`BOTTOMRIGHT -48, +48` (the deck's inset). The tooltip is anchored corner-to-corner
using the mover's saved point, so it grows away from whichever corner the anchor
sits in.

**Item and spell tooltips** follow the cursor at `+24, -22`, flipping near a screen
edge — but only when `tip.default == 1` or the owner is `UIParent`. A bag slot, a
merchant row or a quest reward that deliberately called `SetOwner(self,
"ANCHOR_RIGHT")` keeps its own anchor. This is the answer to "the tooltip jumped
away from the thing I was hovering".

### 3.5 Coverage

A registry, seeded from a name list and extended by a public
`A:GetModule("tooltips"):Register(frame)`:

```
GameTooltip · ItemRefTooltip · ShoppingTooltip1/2 · ItemRefShoppingTooltip1/2
EmbeddedItemTooltip · WorldMapTooltip · WorldMapCompareTooltip1/2
SmallTextTooltip · FriendsTooltip · PartyMemberBuffTooltip
PrivateAurasTooltip · ItemSocketingDescription
```

Absent names are skipped, not errors — `BattlePetTooltip` and friends genuinely do
not exist on this branch (`Blizzard_FrameXML_Vanilla.toc` omits them, and
Blizzard's own code guards with `if (BattlePetTooltip) then`).

LibExtraTip creates its tooltips lazily and names them
`LibExtraTip_<MAJOR>_<MINOR>Tooltip<n>` (`LibExtraTip.lua:63, 1112`), so they
cannot be in a static list. A delayed one-off sweep of `_G` for
`^LibExtraTip.*Tooltip%d+$` picks them up after the Auctioneer suite has loaded.

The pooled `TooltipStatusBarTemplate` / `TooltipProgressBarTemplate` frames
(`GameTooltip.lua:709, 751`) are created at runtime, so
`GameTooltip_ShowStatusBar` / `GameTooltip_ShowProgressBar` are hooked and the
returned bar is restyled on the way out.

---

## 4. Build order

1. `Core/Palette.lua` — `tt*` token block in both skins.
2. `Core/Media.lua` — `tt*` font roles.
3. `Modules/Tooltips.lua` — layers 1-5.
4. `Core/Config.lua` — `modules.tooltips` defaults.
5. `Core/Options.lua` — `TooltipsGroup()` + `PAGE_ORDER` slot.
6. `Core/Commands.lua` — `/aether tooltips` diagnostic.
7. `AetherUI.toc` — the new file in the Modules block.
8. `Tools/harness.lua` — mock growth and assertions.

## 5. Harness

The current `GameTooltip` mock (`harness.lua:837-891`) is deliberately thin:
`SetText` and `AddLine` are no-ops and `NumLines` returns 0 or 1. It needs the
line FontStrings, `NineSlice`, `GameTooltipStatusBar`, `SetPadding`, `GetLeftLine`,
the three font objects, and — importantly — **a `HookScript` that actually
chains**. The mock's current implementation is

```lua
function f:HookScript(s, fn) self.__scripts[s] = fn end
```

which replaces rather than chains, so it cannot see the class of bug this whole
module is designed to avoid.

Assertions to write, each of which should be mutation-tested (break it on purpose,
confirm red):

- the card resizes when a line is added after `Show` — the Pawn case
- the stock NineSlice is still suppressed after `SharedTooltip_SetBackdropStyle`
- a simulated MobInfo2 append to line 2 survives the level strip, **in both hook
  orders**
- the level strip is idempotent across repeated `SetUnit` calls
- a line that does not match the level pattern is left byte-identical
- the default anchor lands on the mover frame, and a tooltip that called `SetOwner`
  itself does not get cursor-followed
- every option path in the new options page resolves against the defaults

---

## 6. Known fidelity gaps

Honest list, so nobody re-litigates these from a screenshot:

- **No blur.** Same as every other Aether surface; the rim and the falloff carry it
  (`Core/Glass.lua` header).
- **The info line hangs under the name, not under the badge.** The deck aligns
  "Humanoid · Hostile" with the badge's left edge. Doing that in-game means
  re-anchoring every `TextLeftN`, which fights the C layout code and breaks
  LibExtraTip's column maths. The badge lives in a gutter to the left of the text
  block instead. This is the one deliberate departure from screen 6a.
- **Coin dots are Blizzard's coin textures**, not the deck's radial-gradient
  circles. The sell-price row is drawn by `GameTooltip_OnTooltipAddMoney` using
  inline `|T` escapes; replacing them would mean intercepting the money line, which
  is precisely the line BagBrother's `antiMoneyTaint.lua` warns about.
- **Item stats stay one-per-line.** The deck puts `+11 Stamina · +12 Intellect ·
  +11 Spirit` on a single line. Those are separate lines from the server and
  merging them means rewriting content, not styling it.
- **No hairline divider before the body or the sell-price row.** The deck draws
  one; drawing it means knowing where the client's own line groups end, which is
  content parsing rather than styling.
- **No level badge while MobInfo2 is running.** See §2.3a. The setting is there.

## 7. What the tests actually prove

`Tools/harness.lua` grew a real tooltip: line FontStrings under their global
names, a `NineSlice`, `GameTooltipStatusBar`, the three font objects, and a
`SetUnit` that clears, fills in the client's own line shapes and fires the
scripts in the client's order. Two mock fixes were needed first and both were
hiding things:

- `HookScript` **replaced** rather than chained, which made the mock blind to the
  one property this module is built around.
- `StatusBar:SetValue` did not fire `OnValueChanged`, which is the only hook a
  tooltip health bar has.

Three more mock fixes came out of the level-badge work, and each one had been
making a test vacuous rather than wrong:

- `GetEffectiveScale` returned the frame's own scale and never walked the parent
  chain, so a badge inside a tooltip at 0.71 reported 1 — and any assertion that
  a length was converted into the badge's units passed whether it was or not.
- `AddMaskTexture` validated its argument and recorded nothing, so "this region
  is *not* masked" could not fail.
- The badge test itself had to **pin** `GameTooltip:SetScale(0.71)`. By the time
  it runs, the options walker has flipped every toggle both ways and left the
  tooltip at scale 1, which is exactly the scale where snapping in the badge's
  own units and snapping in UIParent's give the same answer.

A fourth followed from a test, not from reading: the simulated MobInfo2
hook was installed once and left running, so it went on appending to line 2 for
every later block and quietly became part of their fixtures. It is now gated on
a flag — the same discipline the addon applies to its own hooks, and for the same
reason: a `HookScript` hook can never be removed.

Also added: `section(name, fn)`, which pcalls a block so an error inside becomes
one named failure instead of aborting the remaining ~800 checks. The suite is a
single straight-line chunk, so a stale assertion in the middle of it currently
takes everything after it down — which is precisely what a refactor in progress
looks like from the next person's chair. Existing `do ... end` blocks are fine to
convert as they are next touched.

Every assertion in the `tooltips:` blocks was mutation-tested — the behaviour
broken on purpose, the suite confirmed red, the break reverted. **29 mutations,
29 caught.** Seven of those were written only after a review pass found the
corresponding bugs, and three tests had to be rewritten because the mutation
stayed *green*: the item-title-ink check could not fail on Midnight, where the
quality rim and the title ink share an RGB, and had to move to Daylight where
they genuinely differ. A colour assertion on one skin proves nothing about the
other; a geometry assertion at scale 1 proves nothing about 0.71.

## 8. The level badge

Shipped first as `W.CreateOrb` at 26px and it looked rough on screen. Three
causes, all of them the same mistake in different clothes — asking the client to
anti-alias something at a size the art was not drawn for:

- The disc was cut out with a **MaskTexture**. `Tools/generate_textures.py`
  already records the consequence in `minimap_border()`: "a mask's edge is the
  client's to anti-alias and it does a poor job of it". At 46px with a portrait
  in it that is a fair trade; at 26 the stair-stepping *is* the shape.
- The rim sat **flush** with the disc rather than lapping over it, so the disc's
  own outer texel row showed from under a rim too thin to cover it — a second,
  rougher circle just outside the first. The same `minimap_border()` note says
  the border has to overlap rather than stop short.
- The diameter was **unsnapped**. 26 units inside a frame at 0.71 is 18.46
  physical pixels; the rim crosses a pixel boundary the whole way round and the
  client resolves that as a ring of half-lit greys.

Now `W.Widgets.CreateBadge`: the disc is `Circle-Mask` drawn as ordinary
ARTWORK (a 256px anti-aliased filled circle — drawing it rather than masking
with it puts the anti-aliasing back in our hands), the rim laps one physical
pixel proud on every side, and the diameter snaps to the grid in the badge's own
units via the new `A:PxIn(frame)` / `A:SnapIn(frame, v)`.

A pill at width == height would also have been a circle and would have brought
the snapping for free, but its two cap slices would meet with a zero-width
centre between them — the seam case `Core/Glass.lua`'s header warns about, and
the one place snapping cannot avoid it.

Separately, the badge was tinted by reaction for everything, which is not what
screen 6a draws. The deck tints only the three NPC variants and leaves the
anchored **player** card's badge in the skin's own purple. That reads as an
inconsistency and is not one: a player's reaction is friendly nearly every time
you see it, so tinting by it says nothing the name did not already say, and
spends the card's one accent saying it. A friendly player's badge came out a
washed grey-blue for exactly that reason.
