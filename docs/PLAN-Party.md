# Plan: Party Frames

Design source: `E:\AetherUI Design\design_handoff_party\` (README.md, `Party Frames.dc.html`,
screens 12a/12b/12c), with the skin rules in `E:\AetherUI Design\design_handoff_skins\README.md`.

**Built.** This started as a review and became the record of what was built and where the
brief and the client disagreed. §1 is the palette work the design could not be
implemented correctly without; §7 lists every departure.

---

## 1. Semantic gold, and why it came first

The brief reserves a gold that carries **meaning** rather than chrome: the leader crown,
the dock-handle arrow, the Convert-to-Raid cue, the I.F.E.C. landing warning, the
quest-tracker golds. Its rule is that gold is constant in three skins and remapped in
Dusk, because Dusk's own chrome is gold.

In our palette it was not remapped at all, and the collision was not "same hue" — it was
**exact identity**:

| Was | Value | Dusk chrome it equalled |
|---|---|---|
| `SEMANTIC.ifecLanding` | `#f0d9a8` | `dusk.accent` — the same three bytes |
| `SEMANTIC.ifecGossip` | `#e8c86a` | `dusk.deep` **and** `dusk.border` |
| `SEMANTIC.ttElite`, `ttNeutral`, `petContent` | `#e8c86a` | same |

So on Dusk the console's landing warning was painted in the console's own rim colour.

### What shipped

`Palette.c.semanticGold` and `Palette.c.semanticGoldDim`, chosen by one conditional in
one place in `Core/Palette.lua`:

```lua
local function Gold(skin)
	if skin == "dusk" then return DUSK_GOLD, DUSK_GOLD end
	return GOLD, GOLD_DIM
end
```

Midnight, Dawn and Noon are untouched at `#f0d9a8`. Dusk goes one shade deeper to
`#ffcf66`. Nothing else in the palette moved.

It is not a `CHROME` token. The six a skin remaps are chrome; this one carries meaning
and happens to need one exception, so it sits with the meanings and the exception is
stated once. `SEMANTIC` itself stays a shared copy no skin can reach — that rule is what
would have stopped the rejected Daylight skin moving health green.

`ifecLanding` is gone as a name: it was a second name for the same colour, which is the
drift the brief's "route every read through the one token" rule exists to prevent.
`Modules/IFEC/Player.lua` reads `c.semanticGold`.

### Still open: the rest of the gold family

The brief's gold list is crown, arrows, Convert, landing, quest-tracker. Our palette has
five more colours in the same family that the list does not cover, all in `SEMANTIC` and
therefore identical in all four skins:

- `ifecGossip` `#e8c86a` — **the skins README lists this under "what NEVER changes", and
  Dusk's border is the same three bytes.** The document contradicts itself; one of the two
  has to give.
- `ttElite`, `ttNeutral`, `petContent` `#e8c86a` — same collision, same skin.
- `energy` `#ffe082`→`#e8be50` — a rogue's or druid's power bar, one step off Dusk's deep
  accent. This one matters most for the party capsules, because it is a **bar**: the
  brief's escape hatch ("gold semantics always ride a distinct glyph shape or position,
  never hue alone") cannot apply to a 4px strip of colour.

These are separate tokens from semantic gold and the brief says nothing about them. See
§6.

---

## 2. What the client actually gives us

Verified against `D:\Blizzard\World of Warcraft\_classic_era_\BlizzardInterfaceCode`
(Interface 11509), not from memory.

**All four control-panel actions are real on Era.** Three of them are namespaced:

| Action | Call | Gated? |
|---|---|---|
| Ready Check | `C_PartyInfo.DoReadyCheck()` | leader or assistant — the client's own slash command checks |
| Countdown | `C_PartyInfo.DoCountdown(n)` | **not** gated client-side; `n <= Constants.PartyCountdownConstants.MaxCountdownSeconds` |
| Role Check | `InitiateRolePoll()` | bare global; used by `Blizzard_GroupFinder_VanillaStyle` |
| Convert to Raid | **`ConvertToRaid()`** — the bare global | not gated; see below |

The design hides Ready Check, Role Check and Convert for non-leaders and keeps Countdown
visible for everyone. That matches the client exactly — worth recording, because it looks
like an oversight and is not one.

**Convert to Raid took two wrong calls to get right, and both were assumptions.**
`C_PartyInfo.ConvertToRaid` is the Mainline spelling; `Blizzard_UnitPopup_Vanilla.toc`
loads `Classic/UnitPopupButtons_Shared.lua`, whose menu item calls the bare global.
And `ConfirmConvertToRaid` is **not** an ask-first version of it, whatever the name
suggests — the group finder calls it inside a popup's `OnAccept`, *after* the player has
answered. Called cold it does nothing, silently. There is no ask-first API here and the
client's own menu does not confirm, so neither do we. A raid can also be turned back
into a party (`ConvertToParty()`), so "it cannot be undone" was wrong as well.

**Roles exist but nobody sets them — and the API does not say so.** `Classic/RolePoll.lua`
ships and `UnitGroupRolesAssigned` is live, but a role is only set by answering a role
poll or listing in the group finder. It does **not** answer `"NONE"` for somebody who
never did: they come back as `DAMAGER`. So the dps arrow marked everybody and meant
nothing, and the empty-glyph branch was unreachable. Tank and healer only.

**Markers are target-relative.** `SetRaidTarget("target", i)`. The grid's wells are inert
with no target, and the "active assignment" focus ring has to track
`GetRaidTargetIndex("target")` on `PLAYER_TARGET_CHANGED` and `RAID_TARGET_UPDATE`. None
of that is in the brief.

**Combat is the constraint that shapes the stack.** Capsules must be click-targetable, so
each needs a `SecureUnitButtonTemplate` child plus `RegisterUnitWatch`, exactly as
`Modules/UnitFrames.lua:202-233` already does. `RegisterUnitWatch` shows and hides
securely in combat; *re-anchoring* does not. "Members join/leave by growing the stack from
its anchored top edge" is a protected reposition and will be refused mid-fight.

The shape that survives: **fixed slots for `party1`–`party4`**, anchored once, shown and
hidden by the unit watch, re-flowed only out of combat. A gap where an absent member was
is the price, and it is also exactly what "a placed stack never creeps" asks for.

---

## 3. The member capsule (#12a)

Reuse rather than rebuild:

- The 38px class-coloured level pip is the nameplate level disc. `Palette:ClassColor(unit)`
  and the disc recipe are already in `Core/Palette.lua:510-545`. Same component.
- Health and power bars are the existing bar widget; `barTrack` is already a composed
  token.
- Type styles go through `Reskin.Font`, not per-string sizes.

Built: four new glyphs (crown, healer, dps, resurrect — the tank shield is an alias of
`guild` and the handle's figures of `social`, not second drawings), and dead / ghost /
offline states. `UnitIsDeadOrGhost` covers dead and ghost and they read the same.

Corrections to the brief:

- "Stack … up to 5" — the render shows **four** capsules for a party of five. It is four,
  and the plan should say the player is not in the stack (we already draw a player frame).
- "healers additionally see a resurrect glyph" keys off a viewer role that is usually
  `"NONE"` on Era. Key it off the viewer's **class** instead.
- "health value gold when hurt" is semantic gold carried by hue alone on a number, which
  breaks the brief's own companion rule, and on Dusk it is the accent colour. See §6.

---

## 4. Controls panel (#12b)

320px glass panel, hairline rules, marker grid, four action rows. Straightforward against
what we have — `Glass.CreatePanel`, `Reskin.Button`, the Toolbox row styling — with three
gaps:

- The no-target state for the marker grid (§2) — built: the wells are inert and dimmed
  with nothing targeted.
- The marks are laid out **highest index first** — skull, cross, square, moon, triangle,
  diamond, circle, star. That is the order the client's own grid has always used and the
  one everybody reaches into without looking. 1-to-8 puts the star top-left.
- No Leave Party or Disband, in a panel that replaces the Party Members flyout. Still
  worth confirming.

The Convert-to-Raid glyph is a pencil in the render. A pencil reads as rename or edit, so
it is the gear.

---

## 5. Dock handle and placement (#12c)

Built. A slim glass tab flush to a screen edge - party glyph, count, gold arrow -
dockable to any of the four, at a quarter or three quarters along it rather than the
middle, because the Toolbox rail owns the middle and both default to LEFT. The chain
is handle to panel to stack, so re-docking moves all three.

Same shape as the Toolbox rail by the same *trick* rather than the same code: the tab
bites into the panel by its own corner radius so the inner curve hides behind it. What
is genuinely shared is `W.PointChevron` - eight cases of which way the arrow faces,
owned once for the rail and the handle both.

**Movement is Movers, and only Movers.** The brief's unlock mode - a dashed accent
outline round the stack and an 8px grid snap - is not built and will not be. Nothing
else in this interface moves that way: every positioned frame is dragged by the same
handle, with the same guides and the same snapping, and a stack that had its own
gesture would be one frame behaving unlike the other thirty. It reads well in the
design and does not fit the thing it is being added to.

The brief also says "position saved per character". It is in `db.profile.anchors` with
every other anchor - splitting placement across two scopes is how a profile switch
starts moving some things and not others.

Where the stack STARTS is the part worth keeping: attached to the dock until you drag
it once, `/aether party reset` to hand it back.

---
## 6. Decisions needed

1. **The rest of the gold family in Dusk** (§1). `ifecGossip`, `ttElite`, `ttNeutral`,
   `petContent` are `#e8c86a` and Dusk's border is `#e8c86a`. `energy` is one step off and
   is a bar, so glyph shape cannot rescue it. Options: move Dusk's `deep`/`border` off
   `#e8c86a`; or move the four semantics; or accept it and let Dusk's power bars and elite
   chips read as chrome.
2. **Empty role state** (§2) — settled by implementation, overrule if wrong: no role, no
   glyph, nothing reflows. It is the common case on Era.

Two more were settled the same way while building §3, and both departed from the brief:

- **Hurt health value.** The brief turns it gold, which is semantic gold carried by hue
  alone on a number — the one thing its own companion rule forbids — and on Dusk that
  gold is a step from the chrome. It is ordinary text now, and red under 20%. The bar
  beside it is already shrinking and already going green to red.
- **Crown vs raid marker.** The brief puts both on the same spot on the pip and a marked
  leader is ordinary. The marker keeps the top, where the game's own frames put it; the
  crown takes the top-left.

---

## 7. Build order

1. ~~Semantic gold, one conditional in one place~~
2. ~~crown, healer, dps, resurrect glyphs~~ (tank and party are aliases, not drawings)
3. ~~The capsule, four fixed secure slots, one mover, its own options page, and the
   client's own four banished~~
4. ~~The controls panel~~ - marks on your target, the four actions, leader rows hidden
5. ~~The dock handle~~ - and `CompactRaidFrameManager`, the flyout it replaces, banished
   with the rest
6. ~~Decorators~~ - crown, mark, role and PvP flag, one to a corner of the level disc,
   on the party capsules, the player and target capsules and the nameplates

The design is built. What remains is §6.1, which is a palette question rather than a
party one.

### Departures from the brief, all deliberate

- No dps role glyph. This client answers `DAMAGER` for somebody who never set a role,
  so it marked everybody and meant nothing.
- The hurt health number is not gold. Semantic gold by hue alone on a number is the one
  thing the brief's own companion rule forbids.
- The crown and the raid mark get a corner each rather than sharing one.
- Fixed slots, not a growing stack: re-anchoring a frame with secure children is
  refused in combat, which is exactly when a member leaves.
- No unlock mode of its own (§5).
- The role glyph rides the disc rather than a well of its own at the far right, which
  reserved width on every capsule for a mark most members do not have.
