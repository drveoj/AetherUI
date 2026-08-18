# Plan: Party Frames

Design source: `E:\AetherUI Design\design_handoff_party\` (README.md, `Party Frames.dc.html`,
screens 12a/12b/12c), with the skin rules in `E:\AetherUI Design\design_handoff_skins\README.md`.

Nothing of the party frames is built yet. What **is** built, and is in this plan because
the design cannot be implemented correctly without it, is the semantic gold token — the
handoff names it as binding, and our palette got it wrong in a way that made one skin
strictly worse than the others.

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
| Convert to Raid | `C_PartyInfo.ConvertToRaid()` | also `C_PartyInfo.ConfirmConvertToRaid()` |

The design hides Ready Check, Role Check and Convert for non-leaders and keeps Countdown
visible for everyone. That matches the client exactly — worth recording, because it looks
like an oversight and is not one.

**Roles exist but are opt-in.** `Classic/RolePoll.lua` ships and `UnitGroupRolesAssigned`
is live, but a role is only set by answering a role poll or listing in the group finder.
For most Classic Era party members it returns `"NONE"`. The 22px role glyph is therefore
usually empty and the design specifies no empty state.

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

Needs building:

- Five glyphs. `Core/Media.lua` has `chipDisc` and `chevron` and nothing else the design
  asks for: crown, shield/lock (tank), life (healer), up-arrow (dps), resurrect.
- Dead / ghost / offline states. The brief has one dead state; `UnitIsDeadOrGhost` covers
  both and they should read the same. Offline is `UnitIsConnected`.

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

- The no-target state for the marker grid (§2).
- No confirm on Convert to Raid. It cannot be undone and it changes loot rules;
  `C_PartyInfo.ConfirmConvertToRaid()` exists for exactly this.
- No Leave Party or Disband, in a panel that replaces the Party Members flyout. Probably
  intentional, worth confirming.

The Convert-to-Raid glyph is a pencil in the render. A pencil reads as rename or edit.

---

## 5. Dock handle and placement (#12c)

The handle is the Toolbox handle — `Modules/Toolbox.lua` already has `_dockHandle`, the
edge constants and `db.char.docked`. Shared component, not a copy.

The stack is a different question. The brief says "position saved per character", but
`Core/Movers.lua` stores every anchor in `db.profile.anchors`. Toolbox's `db.char` is
precedent for the other choice, but the stack is a positioned HUD frame like every other
positioned HUD frame, and splitting placement across two scopes is how a profile switch
starts moving some things and not others. **Use Movers.**

The 8px grid snap does not exist in Movers. Either it goes in there for everything, or it
goes away — a snap that applies to one frame is a bug report waiting to happen.

---

## 6. Decisions needed

1. **The rest of the gold family in Dusk** (§1). `ifecGossip`, `ttElite`, `ttNeutral`,
   `petContent` are `#e8c86a` and Dusk's border is `#e8c86a`. `energy` is one step off and
   is a bar, so glyph shape cannot rescue it. Options: move Dusk's `deep`/`border` off
   `#e8c86a`; or move the four semantics; or accept it and let Dusk's power bars and elite
   chips read as chrome.
2. **Hurt health value** (§3). Gold by hue alone on a number. Suggest the neutral text
   token, and let the shrinking bar say "hurt".
3. **Crown vs raid marker** (§3). They occupy the same position on the pip and a marked
   leader is ordinary. One of them moves.
4. **Empty role state** (§2). It is the common case on Era.

---
## 7. Build order

1. ~~Semantic gold as a chrome token~~ — done.
2. Answer §6.1 and §6.2; both are palette edits and both block drawing a capsule.
3. Glyph textures (`Tools/generate_textures.py`).
4. The capsule as a widget, one unit, against `player` first so it can be looked at
   without a party.
5. Four fixed slots, secure children, unit watch, Movers anchor.
6. The controls panel.
7. The dock handle, shared with Toolbox.
