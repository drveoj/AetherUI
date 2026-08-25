# AetherUI

![A Glass user interface for World of Warcraft - Classic Era](https://raw.githubusercontent.com/drveoj/AetherUI/main/docs/brand/AetherUI-Logo.png)

A complete interface replacement for **WoW Classic Era**. Frosted glass, four
palettes, and a HUD that gets out of your way when nothing is happening.

One addon, no modules to install, no profile to import. It sets itself up the
first time you log in.

![A full screen: party frames and their controls, unit frames centred on the
character, quest tracker, minimap, chat and the action bars](https://raw.githubusercontent.com/drveoj/AetherUI/main/docs/screenshots/7-Layout.jpg)

---

## Install

Drop the `AetherUI` folder into:

```
World of Warcraft\_classic_era_\Interface\AddOns\
```

Then start the game.

## First time in

A short tour runs on your first character. Nine stops, takes about a minute, and 
every choice you make applies live on the real interface rather than in a preview.

![The tour's first stop: four palette swatches in a callout beside the real
player frame, with the world dimmed behind](https://raw.githubusercontent.com/drveoj/AetherUI/main/docs/screenshots/2-Tour.jpg)

The tour helps you make 4 choices:

- **Your palette** — Midnight, Dawn, Noon or Dusk. Select one and the whole
  interface recolours at once.
- **Your layout** — three starting arrangements: frames in the corner, frames 
   centred on your character, or frames flanking the action bars.
- **Where the Toolbox lives** — pick a screen edge.
- **How long before the interface goes Zen** — or never.

Everything after that is a demonstration. On an alt it offers to take the setup
you already chose and skip the questions.

Run it again any time with `/aether tour` (or from Config).

## What you get

**Unit frames** — you, your target, its target, and your pet, as glass capsules
with a class-coloured level orb. Buffs above, debuffs below.

![The HUD in combat: player, pet, target and its target, with a cast bar
and the target's debuffs on the frame rather than beside it](https://raw.githubusercontent.com/drveoj/AetherUI/main/docs/screenshots/1-HUD.jpg)

**Party frames** — four capsules in fixed slots that move as one block, with a
controls drawer for raid marks, ready check, role check and a countdown.

**Action bars** — six of them, independent, plus stance and pet bars. Cooldowns,
charges and range draw *on* the icons. `/aether bind` puts you in keybind mode: 
hover over a button, press a key.

![An action bar close up, one button counting down under its own icon](https://raw.githubusercontent.com/drveoj/AetherUI/main/docs/screenshots/6-Bar.png)

**The Toolbox** — a drawer that docks to any screen edge. Everything you'd
otherwise hunt for is in it: UI settings, useful widgets, your addon buttons, and 
a standard menu. It has a rail that stays on screen when the drawer is shut.

![The Toolbox drawer open on the left edge](https://raw.githubusercontent.com/drveoj/AetherUI/main/docs/screenshots/3-Toolbox.png)

**Bags** — all your bags in one panel, sorted into categories, with a automated
junk sale and repair (configurable) and your equipped bags in a drawer at the edge.

**Quest tracker and quest log** — the tracker folds itself away when a fight
starts and comes back when it ends. The log is a reimagined dual pane questlog 
rather than Blizzard's reskinned.

If you have the Questie and TomTom addons installed, you can right-click items in
the quest tracker to find a menu item saying: "Navigate with TomTom".

**Threat** — your own unitframe tells you before trouble arrives: a ring that fills,
gold when you're climbing, red when it's on you. What counts as trouble flips
with your role, so a tank is warned about the opposite thing.

**Nameplates, tooltips, chat, minimap** — all skinned to match, all optional.

**Zen mode** — stand still for a while and the interface fades out entirely,
leaving a slow breath, your health, the zone and the clock. Move and it's back.
Your character sits down and the camera pulls back for the view.

![Zen mode: the interface gone, a slow breath and a clock left behind](https://raw.githubusercontent.com/drveoj/AetherUI/main/docs/screenshots/4-Zen.jpg)

**I.F.E.C.** — the In-Flight Entertainment Console. If you have installed an
AetherUI Content Pack (seasonal) You will find music, stories and some 
thoroughly disreputable gossip rags to amuse yourself while in-flight. It is timed 
to your flight path and will stop automatically when you land unless you configure it 
to keep going. 

It plays on the ground too, from the Toolbox, where it is called N.I.F.E.C. for 
reasons I stand behind (note: The "N" stands for "Not").

![The console mid-flight, library open, counting down to landing](https://raw.githubusercontent.com/drveoj/AetherUI/main/docs/screenshots/5-IFEC.jpg)

## Moving things

`/aether unlock`, then drag. Scroll a frame to nudge it a pixel at a time; hold
shift to nudge sideways. Edges snap to a grid and to each other — hold alt to
place freely. Frames you can't normally see, like the pet bar, are held up while
you're unlocked so you can put them somewhere.

`/aether lock` when you're done, or click the lock button.

## Settings

`/aether` opens the options panel. Every setting has an explanation next to it; if
something isn't behaving the way you expect, the description usually says why.

The most useful ones from chat:

```
/aether skin midnight|dawn|noon|dusk
/aether scale 0.6-1.6            size everything, together
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

Classic Era only (interface 11509). It replaces some of Blizzard's interface
rather than skinning it, so it may argue with other addons that do the same
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

Translators welcome — contact on discord - https://discord.gg/drveoj
