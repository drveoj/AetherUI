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
4. ~~**`Blizzard_GroupFinder_VanillaStyle`**~~ — the LFG window. Asked for
   2026-08-22, **built 2026-08-23**, see below. Not yet seen in game; its
   insets are a first guess and will want a nudge by eye.

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

## Fixed — the social window's tabs and its Battle.net header (2026-08-23)

Reported from the game against the built window: the tabs were "a different tab
type", and your name, availability dropdown and broadcast button sat in the
title bar rather than at the top of the content.

**Nothing in `DressFriends` ever laid the window's four tabs out.** `LayoutTabs`
is called by five interiors — the character sheet, inspect, the spellbook, the
talent frame and the vendor — and by nothing else. So the only thing that ever
reached this window's tabs was the hook on the client's own
`PanelTemplates_TabResize`, and in the gap before that fired they were whatever
`Reskin.Buttons(_G.FriendsFrame, ...)` had made of them: **the pill every
pressable thing in this interface wears.** A tab drawn as a button, over the top
of a tab. That is the "different tab type".

- `DressFriends` calls `LayoutTabs` **first**, before its own sweeps.
- `Reskin.Buttons` now skips anything carrying `__aetherTab`. A tab is a
  `Button` with a label on it and a child of the window, which is exactly what
  that sweep looks for — the same trap the who list's five column heads fell
  into, and the general rule rather than a third skip list.
- With the tabs laid out the window has a **rail**, so `LayoutFooter` stacks the
  action strip above it instead of on the window's own bottom edge. 15e, and the
  reason the strip and the tabs no longer share a band.

**The Battle.net header is chrome and belongs in the tool row.** The client hangs
`FriendsFrameStatusDropdown` at 56, `FriendsFrameBattlenetFrame` at 109 and its
`BroadcastButton` off the tag's right edge, all 26 or 27 down from the window's
*top* — which is the middle of our header band, so all three came up printed
across the window's own title with the tag reading as a second, fainter one.
They go in `row` with the who query and the raid's switch: the client shows
`FriendsTabHeader` only on the Friends tab, so the `IsVisible` test that already
sorts one row across five panes sorts these too at no cost. The dropdown takes
the same dressing the trade skill's filters do, and the tag is re-inked out of
Battle.net's blue — a second accent nothing else in the interface uses.

**A bound on the action strip was added here and taken out again in 0.21.3.**
It clamped a middle group wider than the strip so it crowded rather than hanging
off the side. It was written for a symptom that could not be reproduced — Add
Friend and Send Message measure correctly centred on the Friends pane — and the
next build in the game showed Send Message almost entirely outside the window,
with its position fitting the clamped arithmetic and nothing else. A guess that
makes the thing it was guessing about worse comes out; the cause is still
unknown. See below.

Five mutations are caught.

## Built — the group finder (2026-08-23)

`LFGParentFrame`, from `Blizzard_GroupFinder_VanillaStyle`: two windows behind
two tabs, the listing you post and the browse you search with. Item 4 on the
list, asked for on the 22nd and deferred until the trade and social work had
been seen.

**What is unusual about it is that it is the OLD parchment build carrying MODERN
content.** Three slabs of `UI-LFG-FRAME` and an eye for a portrait, wrapped
round a `WowScrollBoxList` for its results and two `WowStyle1Dropdown`s for its
filters. So it wants the parchment margin trimmed like the quest giver's *and*
the pooled-row treatment the gossip window needed, in the same window.

- **Both panes are `setAllPoints`**, so neither is in the body list — the social
  window's shape one window on, and the same reason. Everything the player looks
  at is hung off a pane at its own fixed distance and is named individually.
- **Tab one is the listing and tab two is the browse**, which reads backwards
  until you look at `LFGParentFrameTab1_OnClick`.
- **Its title is per pane.** The frame's own is never filled in; each pane prints
  `LFG_TITLE` inside itself, the way the postbox prints INBOX and SEND MAIL.
- **The two filters and the refresh are chrome** and go in the tool row — the
  client hangs them 94 down from the window's top, which is our header band and
  a line under it. The options gear takes the far end of the same row.
- **Refresh and both gears are pictures, not words**, and on all three the
  *normal* texture is the square stone plate while the glyph is a region of its
  own. `Reskin.IconButton` is told which region the picture is; left to guess it
  keeps the plate and throws the glyph away.
- **The listing's three views sit under a strip of role buttons.** Measured
  against the band each on its own, the role strip travels 74 and the views
  travel 6 — and the strip lands on top of them. `lead` reserves the room over
  the views instead, which is the social window's sub-tab trick again.
- **The results list is pooled**, so it is dressed from the box's own `Update`
  rather than from the dresser alone. Third window to need this after the gossip
  window and Communities.

**One new thing in the mover: `fill`.** The rule up to now was *shortened, never
stretched* — right for a page the client sized for its own window, wrong for a
box it sized for a window **shorter** than ours. Every one of the group finder's
content boxes is a fixed 324 by 282 in a frame 512 tall; ours is 656, because the
band, the tool row and the footer strip all cost height and the window grows to
take them. Left alone the list sits in a recess with a hand's width of empty
glass under it and shows fewer results than there is room for. `fill` names the
parts whose height follows the body's floor — named rather than guessed, because
Send Mail's pane is 512 tall inside a window of 424 *deliberately*, and a rule
that stretched everything would drag its attachment row down through the letter.

**The insets are a first guess** — `{ 4, -4, -26, 22 }`, measured off the
client's own numbers rather than off the art, and expected to want a nudge by
eye.

Six mutations are caught. The mock is a full one: both panes, both tabs through
the client's own `LFGParentFrameTab1_OnClick`, the pooled box with a row minted
during layout and another acquired after the dresser has been past.

## Fixed — Add Friend and Send Message off the sides (2026-08-23)

Reported three times, guessed at twice, and finally reproduced: the friends
window's two buttons are correct when it is first opened, and a button's width
too far apart after switching tabs and coming back — one hanging off each side of
the glass.

**`RaidFrame` carries no parent in its XML** — *"Parent set dynamically. See
ClaimRaidFrame()"* — **and is not hidden either.** So from the moment its addon
loads it is a shown frame with nothing above it. A frame outside UIParent's
hierarchy is never *drawn*, but `IsVisible` walks the parent chain and **a chain
that simply ends has no hidden link in it**: every child of it answers yes. So
`RaidFrameConvertToRaidButton` took a slot in the friends window's strip, 115
wide, and drew nothing in it. It only appears after the raid tab has been visited
once, because until then the button does not exist at all.

Visible is not enough. **A row now takes only what is visible AND a descendant of
the window being laid out** — `RowUsable`, used by `ChromeRow`'s three groups,
its anonymous actions, and `RowUp`. The client makes the same test itself:
`FriendsFrame_ShowSubFrame` hides `RaidFrame` only `if RaidFrame:GetParent() ==
FriendsFrame`. A pane somebody else has claimed is not this window's to hide, and
its buttons are not this window's to place.

**Two earlier attempts at this were wrong and are recorded as such.** 0.21.2 added
a clamp on the strip's width, which was a guess at a symptom and made it worse;
0.21.3 took it out again. Neither could be made to fail in the harness, because
the harness's `RaidFrame` was a well-behaved hidden child of the window. It is
now parentless and shown, as the client's is.

**And `/aether panels dump` now reports what the layout can SEE.** A dump of this
window while it was wrong said nothing at all about it: the tree describes what
the client built, and the question was what our own row filter makes of it. Each
member of `row` and `actions` is listed with its size, shown, visible, and whether
it belongs to this window — the last marked **NOT OURS** with the parent it does
belong to. That one line is the whole answer, and it took three builds to get it
without one.

**And the same cause again from the other side (0.21.6).** Fixing the filter was
not enough, because on two of the client's own paths nothing of ours ran at all:

- **`FriendsFrame_ShowSubFrame` loops the five panes with `pairs`**, so the order
  is arbitrary and the pane going *up* can be shown before the one coming *down*
  is hidden. Our pane `OnShow` hook fires in that gap and lays the strip out from
  a window that is briefly showing two panes — which put Convert to Raid back in
  the friends list's strip on the way home from the raid tab.
- **The raid pane never fires `OnShow` at all.** It is shown from the moment its
  addon loads, so the client's own `Show()` on it is a no-op. The first visit to
  that tab came up with the blurb still under the band, Convert to Raid wherever
  the last pane had left it, and only the tool row correct — because that one is
  redrawn by the tab hook instead.

A **post-hook on `FriendsFrame_Update`** answers both: it runs after the claim and
after the swap, with exactly one pane up, every time the client changes its mind
about which. Guarded against re-entry, and skipped while the window is down —
the client calls it on a who result and on joining a group too.

The harness now performs the swap the way the client does, in the worst order on
purpose: `FriendsFrame_Update`, `FriendsFrame_ShowSubFrame` and `ClaimRaidFrame`
are modelled, the checks change tabs through them rather than hiding panes by
hand, and the raid pane starts parentless and shown. Removing the settle hook
reproduces all three screenshots exactly.

Six mutations are caught.

## Fixed — the trade window's money row (2026-08-23)

Reported from the game: your gold, silver and copper were at the top left of the
window, above both players' names, with the recess meant for them a hundred units
lower.

**One piece of this window cannot move, and it turns out that sets the shape of
the whole thing.** `TradeFrame_OnLoad` forbids `TradePlayerInputMoneyFrame`, so
your own purse cannot be moved a single unit in either direction. The four pieces
around it — both recesses, the wrap behind their figure, and their money frame —
can move, and did: they travelled down with the rest of the window while the
fields stayed at 61. Moving what can move is worse than moving nothing when the
result is a recess with nothing in it and a row of fields with nothing round them.

So the whole money row now stays exactly where the client put it, and the rest of
the window is laid out around it:

- **`lead = 24`** reserves room down to 90, where the purses end, so the body
  starts below them instead of at the usual 80. The names came down on top of the
  purses otherwise. The row ends up four units under the header rule and reads as
  a strip of its own — which is as much air as there is to give.
- **`insets = { -22, 0, 20, 0 }`** — the glass reaches past the frame on both
  sides, and nothing travels sideways at all. The client's insets sit 4 in from
  the frame on the left and 6 on the right; 22 and 20 of glass outside those puts
  every one of them the standard 26 in from the rim without touching a point.
  `MeasureTop` measures against the glass, so this makes the sideways shift come
  out as zero rather than needing a flag of its own.

**The two names are this window's title, and they now sit in the band
(2026-08-23).** Every other panel says what it is in the band; this one says it
twice, because what it is is two people and each name belongs over a column — one
centred string cannot carry that. They are centred over the middle of the goods
they name rather than at the client's own 65 and 230, which were over neither.

Taking them out of the body list fixed the second half of the same report as a
side effect. They were the topmost thing in it, five units down, and `together`
hands the deepest shift to everything — so a shift computed for two strings in
the header band was applied to the goods as well, and dropped a hand's width of
empty glass under the purses. Measured from the columns instead, the shift is 21
and the goods start exactly one gap below the money row.

Seven mutations are caught.

## Fixed — the who list's count, and a guess withdrawn (2026-08-23)

**"0 People Found" was under the header band.** The client anchors
`WhoFrameTotals` to the search box — BOTTOM to its TOP — and the search box is
chrome, so it went into the tool row and took the count with it, where it read as
a subtitle for the window. It now hangs off the footer's own hairline, at the foot
of the body where the client has it. Not off the list: the list keeps the height
the client gave it and stops well short of the body's floor, so a count hung under
the list floats in the middle of the window.

**And the action-strip clamp added in 0.21.2 is gone.** It was written for a
report that could not be reproduced in the harness or measured in the screenshot
that came with it. In the next build Send Message was almost entirely outside the
window: Add Friend's position fits `x = -room / 2` with a `room` far smaller than
the window, and the step to Send Message fits the clamped gap of 4 with a third
member in the row. Both of those are the clamp's arithmetic and neither happens
without it. The row is centred with no bound again, which is what it was in
0.21.1, and the original report needs a `/aether panels dump FriendsFrame` before
anything else is written for it.

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
