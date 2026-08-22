# Panels — parked state

Stacked away 2026-08-21, mid-clean-up, at **0.18.0 + uncommitted work**. The
suite is green (3,754 checks) and nothing here is broken; this is a list of
what has not been looked at yet, not a list of faults.

## What is left to build

1. ~~**`FriendsFrame`**~~ — **built 2026-08-22**, see below.
2. ~~**`TradeFrame`**~~ — **built 2026-08-22**, see below.
3. **`CommunitiesFrame`** — the guild panes. Written from a live dump and never
   seen, because there was no guild to look at when they were built. The two
   suspicions recorded at the time were both real and are **fixed 2026-08-22**,
   see below; the window still wants a look from inside a guild.
4. **`Blizzard_GroupFinder_VanillaStyle`** — the LFG window. Asked for
   2026-08-22, not started. Source at
   `_classic_era_\BlizzardInterfaceCode\Interface\AddOns\Blizzard_GroupFinder_VanillaStyle`.

`SettingsPanel`, `HelpFrame` and `WorldMapFrame` are **signed off at shell
depth** — 2026-08-21: *"we're not touching those any more than they are
now."* Bags, the quest log and the Toolbox are bespoke and out of scope.

## What TradeFrame needs, when we get to it

The shell is done: glass, header band, title, body shift, and a footer strip
with Trade and Cancel in it. `Reskin.Strip` also clears the frame's own regions,
which disposes of the fake SECOND window border the client stitches onto the
right half (`TradeRecipientPortraitFrame`, `TradeRecipientLeftBorder`,
`TradeRecipientBotLeftCorner`, `TradeRecipientBG`, both portraits).

Still Blizzard's, all of it children rather than regions:

- Six stone recesses — `TradePlayerItemsInset`, `TradeRecipientItemsInset`, the
  two `…EnchantInset`s and the two money insets — plus `TradeRecipientMoneyBg`,
  a `ThinGoldEdgeTemplate` (the same double wrap the postbox's total had).
- Fourteen item rows. Each `TradeItemTemplate` is three pieces: a
  `UI-EmptySlot` plate, a `UI-QuestItemNameFrame` parchment strip behind the
  name, and an `ItemButton` on top. That parchment is the same art the quest
  giver's rewards wear, so `DressQuest` already has the recipe.
- `TradePlayerInputMoneyFrame` — the same `MoneyInputFrameTemplate` as Send
  Mail, so it has the identical three-coins-at-three-distances problem, and
  `Reskin.EditBox`'s `unit` option already answers it.
- The two player names, the two Enchant labels, and four
  `UI-TradeFrame-Highlight` frames marking the live slot.

It opens solo for a look: `/run ShowUIPanel(TradeFrame)` puts it up empty,
which covers every piece of art except the highlight.

## Fixed — the Communities roster's rows (2026-08-22)

Both suspicions recorded when this window was written blind turned out to be
right, and the source confirms them without needing a guild to look at:

- **A row's plaque is its own `NormalTexture`** — `setAllPoints`, out of
  `Interface\GuildFrame\GuildFrame`. Stripping the *pane* reaches nothing of
  it, so the roster came up as our glass with a column of the client's stone
  plaques on it. The class glyph and the voice lamp are regions of the same
  button in the same layer, so they are spared by name.
- **Nothing hooked the roster's scroll.** These lists are modern `ScrollBox`es:
  they take rows from a pool during their **own** `Update`, after the window's
  has returned, and hand them back when they scroll out. So a row scrolled into
  view later was a row nobody had been near. Hooked on the box's `Update`,
  which is exactly where the gossip window's rows are caught and for exactly
  the same reason.

Applied to `MemberList`, `CommunitiesList` and `ApplicantList`. Three mutations
are caught. A fourth — dropping `Reskin.ClearButton` — is not, because the
mock's state textures are ordinary regions and the strip blanks them either
way; `ClearButton` stays because it is the primitive that survives the client
re-showing a pushed state, which is what its own docstring is about.

## Fixed — the toolbox's Social/Guild button (2026-08-22)

Reported from the game: the toolbox's micro row carried a **Guild** button —
which opens Communities, a window this flavour reaches by keypress and never
from the menu — where the client's own menu carries **Social**.

Blizzard's two micro buttons are mutually exclusive and both decide it from
`useClassicGuildUI`, but they read it through
`CVarCallbackRegistry:GetCVarValueBool` and this file was reading it through
`GetCVarBool`. Three things were wrong with that:

1. **The buttons themselves are the answer** and were never asked. They have
   run their own `UpdateVisibility`; a getter has not. Believed only where one
   of them is genuinely up — both down is our own action bar sweep having
   banished them, which says nothing.
2. **The registry is the getter the client uses**, and the two do not have to
   agree.
3. **Nothing at all is not false.** `GetCVarBool` answers false for a CVar that
   is simply absent, and false is a real answer meaning *the other button*. The
   string getter is asked whether there is a CVar to read before its answer is
   believed, and Social is what is left — because Social is what this flavour's
   menu has.

Four mutations are caught, including the reported case.

## Built — the social window's interior (2026-08-22)

`DressFriends`, plus a full entry where there had been `{ frame =
"FriendsFrame" }` and nothing else. Four tabs over five panes — friends,
ignore, who, guild, raid.

**The fact the whole window turns on: every pane is `setAllPoints` to the
window.** A `setAllPoints` frame has *no points*, so the body mover has nothing
to offset and a body list of panes would move nothing while reporting that it
had. Everything the player looks at is hung off the **window** at its own fixed
distance instead, so the body list is the content and never the panes.

- **Two lists have a control row immediately above them** — the Friends tab's
  own Friends/Ignore sub-tabs, 36 up, and the who list's five column heads, 30
  up. Measured against the band each on its own, the header travels further
  than the list under it and lands on top of it. The room is **reserved over
  the list** with `lead` instead, which makes header and list short of the band
  by the same amount so they travel together. Same trick the trade skill window
  uses for its rank bars.
- **One tool row serves five panes**, and that forced a real fix: `ChromeRow`
  placed everything named whether it was up or not, and `RowUp` asked `IsShown`.
  What the client hides when it swaps tabs is the **pane** — every child of it
  goes on reporting itself shown — so the who query held the row's first slot
  on the raid tab and pushed the raid's own switch along behind it. Both now
  ask `IsVisible`, which is the distinction the footer's middle group was
  already written round and had documented.
- **The who query is chrome.** The client hangs it off the window's *bottom*
  edge, which is where the footer strip now is, so it sat under Refresh and Add
  Friend. It is a filter over the list it filters — the trainer's rule — so it
  goes in the tool row, and it keeps its magnifying glass, which is in the same
  layer as the border that came off.
- **The five column heads are headings, not buttons.** Each is a `Button` with
  a label on it and a child of the who pane, which is exactly what
  `Reskin.Buttons` looks for, so all five came back as pressable surfaces. Same
  argument that keeps a letter in the postbox from being drawn as a button —
  and it had to be made a second time here.
- **The two faux-scrolling lists** (ignore, who) hang their rows off the window
  and scroll by refilling, so they need `inside`, exactly as the trainer does.
- **A friend's row keeps its lamp and its badge.** Backing, lamp and badge are
  all regions of the same button in the same two layers. The backing goes: the
  client paints it a different colour for online, offline and Battle.net, and
  what that says is said twice over by the lamp and by an offline name being
  grey.
- **The friends list grows its rows on demand, and we are the reason it does.**
  `HybridScrollFrame_CreateButtons` makes as many rows as fit the box and adds
  more whenever the box's height changes — which is precisely what dressing a
  window does to it. So the rows that exist when the dresser runs are not the
  rows the player ends up looking at. Hooked on `FriendsList_Update`,
  `IgnoreList_Update` and `WhoList_Update`.

**The mock had a bare shell and nothing else** — no panes, no tabs, no lists,
no rows. Thirteen mutations are caught. One check written first could not fail:
it asserted the row backing "stays off when the client repaints it", and
`SetColorTexture` paints a texture rather than showing one, so hiding it once
always holds. The hook's real justification is the growing pool above, and the
check now tests that instead — the comment claiming otherwise was wrong and is
gone.

## Fixed — the trade window's forbidden money frame (2026-08-22)

Reported from the game: Trade and Cancel were neither in the footer strip nor
styled, while the rest of the window looked right.

**`TradeFrame_OnLoad` calls `TradePlayerInputMoneyFrame:SetForbidden()`.** That
is a real call on an ordinary window — not something reserved for the in-game
shop — and from insecure code every method on a forbidden frame throws. The
frame is a child of the window and was named in that window's body list, so the
first pass that measured it took `LayoutBody` down, and with it the footer strip
and the whole interior dresser. **Nothing in `Panels.lua` or `Reskin.lua`
guarded for a forbidden frame anywhere.**

- `Reskin.Forbidden` is the one place that asks, and it pcalls `IsForbidden`
  because a throw asking the question is itself an answer.
- `PN.Part` refuses to hand one out. Every name this file resolves goes
  straight to something that measures or moves it, so one guard there covers
  the dozen places a part is used.
- `Strip`, `StripExcept`, `ClearButton`, `Button`, `Buttons`, `Slot`, `Well`,
  `EditBox`, `ScrollFrame` and `Fonts` each refuse one too. `Buttons` is the
  one that matters most: a forbidden frame is still in its parent's child list,
  and asking it what kind of object it is throws.

**Your own purse cannot be dressed at all**, and that is the client's decision
rather than a gap here. Send Mail's answer to the identical
`MoneyInputFrameTemplate` — three of our pills with the coin as the field's own
mark — cannot be applied at any price. What can be done is the recess round it,
which is an ordinary frame of the window: your purse now sits in one of ours
with the client's own fields inside it, and theirs in one with our figure. The
pair still reads as a pair.

**The mock had no notion of a forbidden frame** — the shop was faked by making
one method throw. It now has `__forbid`, which replaces every method on a frame
and its whole subtree, and `TradePlayerInputMoneyFrame` is marked with it. That
is the seventh time the mock being kinder than the client hid a shipped bug.

## Built — the trade window's interior (2026-08-22)

`DressTrade`, and the entry gained `wells = false` and six more names in its
body list. What was found on the way:

- **Three pieces were never moving at all.** The two enchant recesses and the
  thin gold edge round the other person's purse are pinned to the WINDOW's own
  corners rather than chained off anything above them, so with the window's
  content shifted down past them they stayed where the client had put them.
  The body list is the only thing that moves a piece, and they were not in it.
  Neither were the two highlights or the enchant label.
- **The recesses ARE this window's wells.** Every piece of content in it sits
  in one of the six, which is the trainer's case exactly — so no body recess
  round the outside, and ours go at each inset's own bounds rather than
  `WELL_OUTSET` proud of it: the inset is the recess, not a border round
  content.
- **A row is a frame, not a button.** Each of the fourteen carries the
  empty-slot plate, the quest giver's parchment name strip and the item's name
  in its own BACKGROUND layer, with the pressable `ItemButton` laid on top — so
  a sweep of the window reached none of it. The name is a FontString in that
  same layer, so the sweep has to spare it or the row comes up empty.
- **The two purses are not symmetrical and should not look it.** Yours is three
  fields of `MoneyInputFrameTemplate` — the same template Send Mail uses, with
  the same three coins at three different distances from three identical boxes
  — and theirs is a figure you only read, wrapped twice by the client. Three
  pills against one well.
- **Their coin readout is three Buttons with labels on them**, which is exactly
  what `Reskin.Buttons` looks for. They are children of the money frame rather
  than of the window so the sweep never reaches them, but only by luck, and
  that is now written down beside the sweep.
- **The live-side highlight is a row being marked**, so it is marked the way
  every row in this interface is — `Reskin.RowMark` — and dropped a level,
  because the wash fills a frame covering the whole column and at the client's
  own level it draws over the seven items it is pointing at.

**The mock had none of it.** It had four insets, twelve rows built as bare
Buttons, two empty money frames and two buttons with no labels on them. Every
one of those was kinder than the client. Seven mutations are now caught, and
two of the first checks written could not fail: one compared a frame with its
own grandchild's level, which parenting settles either way, and one checked the
coin's ANCHOR when the client already writes that anchor — only the offset
moves.

## Fixed after parking — the quest greeting page (2026-08-21)

Reported as a GossipFrame bug: talk to an NPC with three quests, accept one,
and the window comes back with our glass, band and well around a page of the
client's own art in the client's own near-black ink.

**It is `QuestFrame`, not `GossipFrame`.** The page is
`QuestFrameGreetingPanel`, and `QuestFrame:OnEvent` re-runs
`QuestFrameGreetingPanel_OnShow` on **QUEST_LOG_UPDATE** whenever that page is
up — which is precisely what accepting one of the quests does. That one
function repaints the parchment, re-inks the greeting and both headings,
re-embeds `|cff000000` in every title through `NORMAL_QUEST_DISPLAY`, and shows
`QuestGreetingFrameHorizontalBreak` again. Every fault in the screenshot, from
one call, on one event.

Fixed with `DressQuestGreeting`, hooked to that global. The swirl turned out to
be a region of `QuestGreetingScrollChildFrame`, which the pane sweep never
reached — the pane list had the panel and not its scroll child.

Two other things came out of it:

- **The gossip rebuild hook was in the wrong place.** It hooked
  `GossipFrame:Update` and re-swept from a zero-length timer, guessing at when
  layout would have happened. `GossipFrameSharedMixin:Update` hands the box a
  data provider and returns; the box acquires its rows during its **own**
  `Update`, at layout. Hooking `ScrollBox:Update` removes the guess — which is
  where ElvUI's gossip skin hooks, and what made the old version intermittent
  rather than broken.
- **The mock modelled the wrong entry point** for that rebuild and had no
  greeting page at all, so both faults were invisible in the suite. Both now
  follow the client, and four mutations are caught.

## Other known outstanding

- **Mail unread rows** — bold when unread, regular when read. Asked for, never
  written. Row backgrounds are already gone; this needs a hook on the client's
  inbox refresh.
- **Client dropdown menus** still wear Blizzard's art. They can wear ours only
  with a restore-on-release: the menu frame is POOLED and the one frame serves
  every context menu in the game. Dressing it once broke all of them.
- **Trade skill detail pane** does not stretch to fill the window — about 30
  units of slack down the right. We move the client's panes; we do not resize
  them.
- **Stage D** (size classes S 360 / M 520 / L 760 / XL 1040) is unstarted.
  **Stage E** (UIPanel detach and movability) was researched and **decided
  against** — `ShowUIPanel` refuses in combat from insecure code before it
  reaches the bail-out, so every combat toggle becomes a visible error unless
  every open and close path is rerouted. The mechanism is recorded in memory if
  it is ever revisited.

---

# Audit list — panels pass (uncommitted, after 0.18.0)

Everything below is covered by the suite, but the suite is a mock. These are the
windows to open in game and look at. `/reload` first.

## 1. Quest giver (QuestFrame) — NEW
- Title: the NPC's name, centred in the band. It has never had one before.
- Accept/Decline (and Continue/Goodbye, Complete Quest/Cancel) now sit together,
  centred in a 52 footer strip with a hairline along its top.
- The quest text should clear the band and sit inside the well.
- Check the pair swaps correctly as you read → hand in → get rewarded.

## 2. Class trainer (ClassTrainerFrame)
- Skill list rows now live INSIDE the left well (they hung off the window).
- Your purse is pinned to the LEFT of the footer strip (was mid-window).
- Train All / Train / Close centred in the strip, clear of the wells.
- The lists are inset by their rim rather than by the full well padding, so the
  margin should now match every other window.

## 3. Trade skills (TradeSkillFrame) and Craft (CraftFrame - enchanting, beast
   training)
- Same four changes as the trainer.
- CraftFrame had NO layout entry at all before this pass.

## 4. Gossip (any NPC you talk to)
- The list of things you can say now sits in the content well (it started
  inside the header band).
- Goodbye moved from the window's bottom-right corner into a centred footer
  strip.
- NPCs with a reputation bar (Argent Dawn quartermasters etc.) get a tool row
  under the band; everyone else gets no wasted space.

## 5. Everywhere — the tool row moved
- A bug: the tool row anchored from the layer's LEFT, which is its vertical
  MIDDLE. The trade skill rank bar and the trainer's purse were being placed
  from the middle of the window with a y measured from the top. Anything in a
  tool row will have moved.

## 6. Books and letters (ItemTextFrame)
- The page turns moved out of the header band (one hung off each top corner,
  with the title between them) into a centred footer strip: ‹ Page 1 ›.
- The page itself now clears the band and sits in the well.

## 7. Trade window (TradeFrame) — LEAST VERIFIED, look hardest here
- Had no mock at all before this pass, so nothing about it had ever been
  checked. It is a hand-built window with a dozen pieces hung off the frame at
  fixed offsets.
- Everything now moves down/right by ONE amount so the layout keeps its shape,
  and the whole window grows to take it.
- Trade and Cancel moved from the bottom-right corner into a centred footer.
- If something on this window is left behind above or beside the rest, tell me
  the name showing in `/aether panels measure TradeFrame` and I will add it to
  the list of movers.

## 8. Flight master (TaxiFrame)
- The map and the route lines over it now clear the header band and sit in the
  well. The flight points hang off the map, so they should travel with it — if
  any node is off its city, that is the thing to report.

## 9. Inspect (somebody else's character sheet)
- Both tabs — the doll and the honour page — now clear the band and sit in the
  well, the way your own character sheet already does.

## 10. List rows — trainer, trade skills, enchanting
- The selected row is now marked with our own accent wash. The trainer's mark
  was being STRIPPED (nothing said which skill you were on); the two crafting
  windows never touched theirs, so Blizzard's blue listbox slice lay across the
  glass.
- Hovering a non-heading row no longer shows Blizzard's plus-button glow: the
  client only ever clears a row's NORMAL texture, and the template carries a
  highlight and a disabled one too.

## Not touched, and why
- Bags, quest log, toolbox — bespoke, working, left alone.
- FriendsFrame, SettingsPanel, HelpFrame, WorldMapFrame, CommunitiesFrame —
  five panes and a sub-tab header between them, too much to change without
  being able to look at it. Next up if you want them.
- Size classes (S 360 / M 520 / L 760 / XL 1040) and the UIPanel detach are
  both still unstarted.

## The suite
- Green, ~3700 checks. Every new check above was mutation-tested.
- Nothing committed; still sitting on 0.18.0.

## 17. Mail, two adjustments (2026-08-21)

**Open All against the tab rule.** The footer strip was splitting 15a's fixed 52
between its two rows, so each row got 26 — and a 22 tall button centred in 26
has two pixels of air under it. A footer that declares a second row now GROWS
by a row (78 for the postbox) and both rows are centred in an equal share of it.
Open All gets 8.5 of air instead of 1, the page turns the same above it, and the
window grows 26 rather than the inbox losing 26.

  - **Audit:** the postbox is 26 taller than it was. Check it still sits where
    you expect on screen and that the letter window beside it (which matches its
    height) came with it.

**The coin row.** All three coins now sit at the field's right text inset. The
client hangs gold's 2 units OUTSIDE its box and silver's and copper's 8 INSIDE
theirs — because its own border art stops ten short on the narrow pair — so with
that art gone and identical wells behind all three, the row wore its coins at
three different distances. Outside was not available: the gap to the next field
is 16 and a coin is 13, so silver's would have landed on copper's well.
Implemented as `Reskin.EditBox`'s `unit` option, not as three SetPoints in the
mail dresser.

**Send Money / C.O.D.** Now round chips of ours rather than Blizzard's gold
disc. `W.CheckBox` gained a `round` shape and `Reskin.Radio` sits beside
`Reskin.CheckBox` on one shared body — square is on-or-off, round is one-of-
several, which is the rule the check box comment already stated. Filled with the
accent when chosen, no tick.

  - **Audit:** click between them; the mark should swap both ways. Then drop an
    item into an attachment slot and take it out again — the client forces Send
    Money from its own update without either button being clicked, and that path
    is hooked separately.

Suite green; five mutations tried (strip not growing, coin left alone, radio
drawn square, group hook removed, client's disc left on) and each one caught.

## 17b. Mail, the two follow-ups (2026-08-21)

**The radios were too big.** `W.RADIO_SIZE` is 12, not the check box's 18, and
the corner is derived as half the size less one so it draws as round as the
nine-slice safely allows. The client stacks that pair FIFTEEN apart (its own
button is 16 with a ring of about 12 inside it), so 18 overlapped by 3. The mock
had them at 20x20 and could not show it; they are 16x16 now, as the template is.

**Send and Cancel sat high in the footer.** The strip was laying out for two
rows on both tabs, but the second row is the INBOX's — Open All is a child of
that pane — so on Send Mail it was empty and the actions took the upper half.
Rows are now counted from what is VISIBLE; the strip's HEIGHT still comes from
the declared count, so the window does not jump 26 units every time you change
tab.

  - **Audit:** switch tabs both ways a few times. Send/Cancel centred on one,
    the page turns with Open All under them on the other, and the window the
    same height throughout.
