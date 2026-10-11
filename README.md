# Lattice

*Formerly AetherUI. Same addon, new name.*

![A Glass-Lattice user interface for World of Warcraft - Classic/Forever](https://raw.githubusercontent.com/drveoj/Lattice/main/docs/brand/Lattice-Logo.png)

A glass HUD for **WoW Classic Era & WoW: Forever** where everything is a node in a lattice.  
Unit frames, action bars, chat, minimap, quests and bags in frosted glass, twelve skins, 
and an interface that focuses on what's important in game. 

Our focus is on the "chrome" (the interface you use all the time). The default panels (character sheet, spellbook etc.) are left as Blizzard designed them.

One addon, no modules to install, no profile to import. It sets itself up the
first time you log in.

![A full screen: party frames and their controls, unit frames centred on the
character, quest tracker, minimap, chat and the action bars](https://raw.githubusercontent.com/drveoj/Lattice/main/docs/screenshots/7-Layout.jpg)

---

## Install

Drop the `Lattice` folder into your game's AddOns folder:

```
World of Warcraft\<your game's folder>\Interface\AddOns\
```

The game's folder is `_classic_era_` for Classic Era, and WoW: Forever has its
own (`_classic_beta_` for the WoW: Forever Beta - will update when Forever releases).

Coming from AetherUI? Remove the old `AetherUI` folder. Lattice starts with fresh
settings, and the tour sets you up again in about a minute. If both are
installed, Lattice offers to switch the old one off.

Then start the game.

## First time in

A short tour runs on your first character. Your screen starts with just your own
frame, and each of eight stops adds the next piece and asks one thing about it.
It takes about a minute, and every choice applies live on the real interface
rather than in a preview.

Along the way you pick:

- **Your pet and target-of-target frames** — on or off.
- **Your bars** — three starting shapes: Rows, Block or Split.
- **Your skin** — twelve of them: Midnight, Dawn, Noon and Dusk; Amethyst,
  Sapphire, Emerald and Ruby; Winter, Spring, Summer and Autumn. Hover one to try
  it on.

It also shows you the two trunks, what a fight looks like, the settings map, and
how to share your layout. On an alt it offers to keep the setup you already
chose and skip the questions.

Run it again any time with `/lattice tour`, or from Settings > Take the tour.

## What you get

**Unit frames** — you, your target, its target, and your pet, as glass capsules
with a class-coloured level orb. Buffs above, debuffs below.

![The HUD in combat: player, pet, target and its target, with a cast bar
and the target's debuffs on the frame rather than beside it](https://raw.githubusercontent.com/drveoj/Lattice/main/docs/screenshots/1-HUD.jpg)

**Party frames** — four capsules in fixed slots that move as one block. Raid
marks, ready check, role check and a countdown are on the Party branch of the
Toolbox, there while you're in a group.

**Action bars** — six of them (nine on WoW: Forever), independent, plus stance,
pet and extra bars. Cooldowns, charges and range draw *on* the icons. Reshape any
bar from its corner in unlock: rows, columns, uneven shapes, wrapping down
instead of across. Drag one bar's edge against another's to join them into a
block. Each bar can rest dimmer out of a fight, show only on hover, and show its
keybinds. `/lattice bind` puts you in keybind mode: hover over a button, press a
key.

![An action bar close up, one button counting down under its own icon](https://raw.githubusercontent.com/drveoj/Lattice/main/docs/screenshots/6-Bar.png)

**The Toolbox** — a trunk down the left of your screen. Everything you'd
otherwise hunt for branches off it: a menu of the game's windows, useful widgets,
your addon buttons, quick settings, what's new, and Party while you're in a
group. Pin an addon's button and it sits on the trunk.

**Bags** — all your bags in one panel, sorted into categories, with a automated
junk sale and repair (configurable) and your equipped bags in a drawer at the edge.

**The World trunk** — hangs from the minimap. Your tracked quests sit on it with
their item buttons, alongside Mail, Tracking, the Calendar and the music player.
In a fight it draws up out of the way and leaves your active quest showing.

**Quest log** — a reimagined dual pane questlog rather than Blizzard's
reskinned.

If you have the Questie and TomTom addons installed, you can right-click a quest
on the World trunk to find a menu item saying: "Navigate with TomTom".

**Threat** — your own unitframe tells you before trouble arrives: a ring that fills,
gold when you're climbing, red when it's on you. What counts as trouble flips
with your role, so a tank is warned about the opposite thing.

**Nameplates, tooltips, chat, minimap** — all skinned to match, all optional.

**Zen mode** — stand still for a while and the interface fades out entirely,
leaving a slow breath, your health, the zone and the clock. Move and it's back.
Your character sits down and the camera pulls back for the view.

![Zen mode: the interface gone, a slow breath and a clock left behind](https://raw.githubusercontent.com/drveoj/Lattice/main/docs/screenshots/4-Zen.jpg)

**I.F.E.C.** — the In-Flight Entertainment Console. If you have installed an
Lattice Content Pack (seasonal) You will find music, stories and some 
thoroughly disreputable gossip rags to amuse yourself while in-flight. It is timed 
to your flight path and will stop automatically when you land unless you configure it 
to keep going. 

It works on Classic Era and WoW: Forever, each with its own flight times.

It plays on the ground too, from its node on the World trunk, where it is called
N.I.F.E.C. for reasons I stand behind (note: The "N" stands for "Not").

![The console mid-flight, library open, counting down to landing](https://raw.githubusercontent.com/drveoj/Lattice/main/docs/screenshots/5-IFEC.jpg)

## Moving things

Frames hang from each other: the target from you, your bars from the line
between you and your target. Move one and what hangs from it comes too.

`/lattice unlock`, then drag. Unlock shows how things connect: a dot field to
snap to, the lines between frames, and an inspector. A frame snaps to its
parent's centre lines first, then to other frames and the dots; hold shift while
dragging to place freely. Drop a frame on another's junction to hang it from
that one. Scroll a frame to nudge it a pixel at a time; hold shift to nudge
sideways. Frames you can't normally see, like the pet bar, are held up while
you're unlocked so you can put them somewhere.

`/lattice lock` when you're done, or click the lock button.

Your whole layout can be saved (and shared) as one line of text. `/lattice layout` opens it to copy,
share or paste someone else's back.

## Settings

`/lattice` opens the settings: a map of your own screen. Point at the thing you
want to change, or press `/` and search. Every setting has an explanation next to
it; if something isn't behaving the way you expect, the description usually says
why. You can also find it under Options → AddOns → Lattice.

The most useful ones from chat:

```
/lattice skin <name>             midnight, dawn, amethyst, winter... (all twelve)
/lattice scale 0.6-1.6           size everything, together
/lattice unlock                  drag frames into place
/lattice layout                  your layout as one line, to copy or share
/lattice bind                    keybind mode
/lattice zen off                 stop the interface fading
/lattice tour                    run the first-run tour again
/lattice help                    everything else
```

`/aether` still works for now, so old macros keep going.

## Something wrong?

`/lattice errors` collects anything that has gone wrong into a box you can copy
out of. Paste that into a bug report and I'll have what I need.

`/lattice status` says which parts are running and which have fallen over.

## Compatibility

Classic Era (interface 11509) and WoW: Forever (16001). It replaces some of
Blizzard's interface rather than skinning it, so it may argue with other addons
that do the same thing to the same frames. It gets along fine with the ones that don't. 
Questie, TomTom, Leatrix and SmartBuff are known to be compatible. 
Anything with a minimap button gets collected into the Toolbox automatically.

## Help and bugs

Discord: **discord.gg/drveoj**

## Credits

Built by **DrVeoj**.

Typeface is [Outfit](https://github.com/Outfitio/Outfit-Fonts), SIL Open Font
Licence. Uses LibStub, Ace3, LibSharedMedia and LibClassicCasterino; licences
included.

Translators welcome — contact on discord - https://discord.gg/drveoj