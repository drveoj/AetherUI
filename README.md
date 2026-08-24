# AetherUI

A complete interface replacement for **WoW Classic Era**. Frosted glass, four
palettes, and a HUD that gets out of your way when nothing is happening.

One addon, no modules to install, no profile to import. It sets itself up the
first time you log in.

<!-- SCREENSHOT: the HUD in Midnight, mid-combat, target selected -->

---

## Install

Drop the `AetherUI` folder into:

```
World of Warcraft\_classic_era_\Interface\AddOns\
```

Then start the game. That's it — no `/reload`, no setup step.

## First time in

A short tour runs on your first character. Nine stops, about a minute, and every
choice you make applies live on the real interface rather than in a preview.
Skip it whenever you like; it never asks twice.

<!-- SCREENSHOT: the tour, stop 1 - the palette swatches beside the player frame -->

It asks you four things:

- **Your palette** — Midnight, Dawn, Noon or Dusk. Tap one and the whole
  interface recolours at once.
- **Your layout** — three arrangements: frames in the corner, frames centred on
  your character, or frames flanking the bars.
- **Where the Toolbox lives** — pick a screen edge.
- **How long before the interface goes quiet** — or never.

Everything after that is a demonstration. On an alt it offers to take the setup
you already chose and skip the questions.

Run it again any time with `/aether tour`.

## What you get

**Unit frames** — you, your target, its target, and your pet, as glass capsules
with a class-coloured level orb. Buffs above, debuffs below.

**Party frames** — four capsules in fixed slots that move as one block.

**Action bars** — six of them, independent, plus stance and pet bars. Cooldowns,
charges and range draw *on* the icon, not in widgets around it. `/aether bind`
puts you in keybind mode: hover a button, press a key.

<!-- SCREENSHOT: an action bar close up, one button mid-cooldown -->

**The Toolbox** — a drawer that docks to any screen edge. Everything you'd
otherwise hunt for is in it: quests, bags, settings, your addon list, and a
menu of the places the game sends you. It has a rail that stays on screen when
the drawer is shut.

<!-- SCREENSHOT: the Toolbox drawer open on the left edge -->

**Bags** — all your bags in one panel, sorted into categories, with a one-click
junk sale and your equipped bags in a drawer at the edge.

**Quest tracker and quest log** — the tracker folds itself away when a fight
starts and comes back when it ends. The log is a proper window rather than
Blizzard's reskinned.

**Threat** — your own frame tells you before trouble arrives: a ring that fills,
gold when you're climbing, red when it's on you. What counts as trouble flips
with your role, so a tank is warned about the opposite thing.

**Nameplates, tooltips, chat, minimap** — all skinned to match, all optional.

**Zen mode** — stand still for a while and the interface fades out entirely,
leaving a slow breath, your health, the zone and the clock. Move and it's back.
Your character sits down and the camera pulls back for the view.

<!-- SCREENSHOT: zen mode -->

**I.F.E.C.** — the In-Flight Entertainment Console. Music, stories and a
thoroughly disreputable gossip rag, timed to your flight path, boarding
automatically at takeoff. It plays on the ground too, from the Toolbox, where it
is called N.I.F.E.C. for reasons I stand behind.

<!-- SCREENSHOT: the console, mid-flight -->

## Moving things

`/aether unlock`, then drag. Scroll a frame to nudge it a pixel at a time; hold
shift to nudge sideways. Edges snap to a grid and to each other — hold alt to
place freely. Frames you can't normally see, like the pet bar, are held up while
you're unlocked so you can put them somewhere.

`/aether lock` when you're done, or click the lock button.

## Settings

`/aether` opens the panel. Every setting has an explanation next to it; if
something isn't behaving the way you expect, the description usually says why.

The most useful ones from chat:

```
/aether skin midnight|dawn|noon|dusk
/aether scale 0.6-1.6            everything, together
/aether unlock                   drag frames into place
/aether bind                     keybind mode
/aether zen off                  stop the interface fading
/aether tour                     run the first-run tour again
/aether help                     everything else
```

## Something wrong?

`/aether errors` collects anything that has gone wrong into a box you can copy
out of. Paste that into a bug report and I'll have what I need.

`/aether status` says which parts are running and which have fallen over.

## Compatibility

Classic Era only (interface 11509). It replaces most of Blizzard's interface
rather than skinning it, so it will argue with other addons that do the same
thing to the same frames. It gets along fine with the ones that don't — Questie,
Leatrix, SmartBuff and the rest are all welcome, and anything with a minimap
button gets collected into the Toolbox automatically.

## Help and bugs

Discord: **discord.gg/drveoj**

## Credits

Built by **DrVeoj**.

Typeface is [Outfit](https://github.com/Outfitio/Outfit-Fonts), SIL Open Font
Licence. Uses LibStub, Ace3, LibSharedMedia and LibClassicCasterino; licences
included.

Translators welcome — see [docs/I18N.md](docs/I18N.md).
