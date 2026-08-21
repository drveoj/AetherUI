# Panels — parked state

Stacked away 2026-08-21, mid-clean-up, at **0.18.0 + uncommitted work**. The
suite is green (3,754 checks) and nothing here is broken; this is a list of
what has not been looked at yet, not a list of faults.

## What is left to build

1. **`FriendsFrame`** — Friends / Who / Raid tabs. Shell only, no interior.
2. **`TradeFrame`** — the two-player trade window. Shell only. Confirmed with
   2026-08-21; the client's `TargetFrame` is a different thing and is not
   in this list.
3. **`CommunitiesFrame`** — the guild panes. Written from a live dump and never
   seen, because there was no guild to look at when they were built.

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
- **Stage D** (size classes S 360 / M 520 / L 760 / XL 1040) and **Stage E**
  (UIPanel detach and movability) of the panels handoff are unstarted.
- **Nothing is committed since 0.18.0.** 25 changed files. `Tools/bump.py
  --minor` when the working state is ready to bank.

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
