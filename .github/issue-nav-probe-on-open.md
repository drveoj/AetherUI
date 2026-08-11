# Opening the tracker's row menu can print a Questie `[ERROR]` line to chat

**Component:** `Core/Nav.lua`, `Modules/QuestTracker.lua`
**Introduced in:** 83d3d20 ("tracker: Navigate with TomTom, by way of Questie")
**Severity:** cosmetic, but it attributes our behaviour to another addon
**Environment:** Classic Era 1.15 (11509), Questie 11.33.2, TomTom v4.3.8-release

## What happens

Right-clicking a quest in the AetherUI tracker can print a red line into the
player's chat that looks like a Questie bug:

```
[ERROR] No dungeon location found for zoneId: <id> Please report this on Github or Discord!
```

Nothing is broken — the menu opens, every item works — but the player is being
told to go and file a bug against Questie, at a moment when the only thing they
did was open our menu.

## Steps to reproduce

1. Run with both Questie and TomTom loaded.
2. Track a quest whose objective sits inside a dungeon for which Questie has no
   entrance mapping (`ZoneDB:GetDungeonLocation(zoneId)` returns nothing).
3. Right-click that quest's row in the tracker. Do not click anything.
4. The `[ERROR]` line appears in chat.

Once per `zoneId` per session — Questie keeps an `alreadyErroredZoneIds` table —
so it is easy to miss and easy to dismiss as someone else's problem.

## Why it happens

To decide whether the menu item reads "Navigate with TomTom" or a greyed
"No location known", `RowClicked` calls `A.Nav:Locate(questID)` **when the menu
is built**. `Locate` goes through `DistanceUtils.GetNearestSpawnForQuest` →
`GetNearestObjective` → `GetNearestSpawn`, and `GetNearestSpawn` is where the
message comes from (`Questie/Modules/Libs/DistanceUtils.lua`, ~line 29):

```lua
if spawn[1] == -1 or spawn[2] == -1 then
    local dungeonLocation = ZoneDB:GetDungeonLocation(zoneId)
    if (not dungeonLocation) and (not alreadyErroredZoneIds[zoneId]) then
        alreadyErroredZoneIds[zoneId] = true
        Questie:Error("No dungeon location found for zoneId:", zoneId, "Please report this on Github or Discord!")
    end
```

`{-1, -1}` is Questie's sentinel for "this spawn is inside a dungeon", which it
normally resolves to the dungeon's outdoor entrance. There are roughly 2,800 of
those pairs in the Classic NPC and object databases. `Questie:Error` is
`Questie:Print("|cffff0000[ERROR]|r", ...)` (`Questie.lua:178`) — unconditional,
not gated behind a debug setting, so there is no way for us to ask it to be
quiet.

**The difference from Questie's own tracker is when it runs.** Questie reaches
this code only when the player *clicks* "Set TomTom Target". We reach it when
the player *opens* the menu, because the greyed-out state has to be decided
before anything is clicked.

## Options

**A. Don't probe on open.** Always show "Navigate with TomTom" as a live item;
resolve the location on click and print our own line if there isn't one. This is
exactly what Questie does, and it makes the message a consequence of asking to
navigate rather than of opening a menu. Cost: the menu no longer tells you in
advance that a quest can't be routed. *Recommended.*

**B. Cache `Locate` per questID for the session.** Keeps the greyed state and
means each zone can only ever produce the line once, on the first menu open for
a quest in it. Cheaper to accept, but it does not remove the behaviour, and a
cached location goes stale — `GetNearestSpawn` ranks by distance to the player,
so a cached answer can send you to a spawn that is no longer the nearest.

**C. Silence `Questie:Error` around our probe.** Swap the function out, call,
put it back. Rejected: it suppresses a diagnostic the Questie authors
deliberately made unconditional, and it would hide the message for the rest of
Questie too if our restore ever failed to run.

**D. Screen out dungeon objectives before probing.** There is no cheap way to
know an objective is in a dungeon without doing the same spawn walk that
produces the message.

## What this is not

- Not a Questie bug. The missing dungeon mapping is worth reporting to them
  separately, and the message is doing its job; the problem is that we trigger
  it on a gesture that isn't a request for navigation.
- Not a waypoint problem. Routing itself is unaffected — the quest still routes
  correctly if the player clicks the item.
- Not related to the `nil` uiMapID guard, which is a different failure and is
  already handled.

## Acceptance

Opening the tracker's row menu produces no output in chat, for any quest, with
Questie and TomTom loaded. Whatever route is chosen, `Tools/harness.lua` should
gain a check that pins it: the mocks already count calls into Questie, so
"opening the menu does not call `GetNearestSpawn`" is a one-line assertion.
