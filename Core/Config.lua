--[[--------------------------------------------------------------------------
	AetherUI :: Config

	AceDB-backed saved variables. Profiles come free, which matters as soon as
	you have an alt on a different class.

	Layout rules of thumb:
	  * anything a module owns lives under profile.modules.<name>
	  * anything shared (skin, scale, fader timings) lives at the top level
	  * frame positions live under profile.anchors, keyed by mover name, so a
	    module can be rewritten without losing where the player put things
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Config = {}
A.Config = Config

Config.defaults = {
	-- A quest log belongs to a character, not to a profile. Tracked quest IDs
	-- shared across an alt would just be noise in everybody's tracker.
	char = {
		-- Which edge the Toolbox is docked to and whether it is open. Per
		-- character rather than per profile, per the handoff: a drawer edge is a
		-- habit somebody forms on one character, the way tracked quests are.
		toolbox   = { docked = "LEFT", open = false },

		-- The chat window's size, in ITS own units. Per character for the same
		-- reason Blizzard keeps its own copy per character, and ours exists
		-- because Blizzard's does not survive: the dock re-flows ChatFrame1 to
		-- its own idea of the size on every restore, so a window you resized
		-- comes back the shape it was. See Modules/Chat.lua.
		chat      = { w = nil, h = nil },

		tracked   = {},   -- whitelist, used when autoTrack is off
		untracked = {},   -- blacklist, used when autoTrack is on
	},

	profile = {
		skin        = "midnight",
		-- 1.0, which is what a 1920x1080 screen wants.
		--
		-- This was 0.71, under a comment deriving it from the deck: the deck is
		-- 1920 wide, WoW's virtual space is 1365 at 16:9, and 1365/1920 = 0.711
		-- maps one onto the other. That arithmetic is sound ABOUT THE DECK and
		-- was never a claim about what a player should get - but it read like
		-- one, and shipped as the default on the strength of it. 0.71 is a
		-- taste, and a taste for one particular monitor at that.
		--
		-- Anyone who wants it smaller has a slider and /aether scale.
		scale       = 1.0,
		debug       = false,

		-- One line at login saying which build this is. On by default: the
		-- point of it is that a player reporting a bug can say what they are
		-- running without being asked, and a greeting nobody sees does not do
		-- that. /aether greet off for anyone who keeps a quiet chat frame.
		greet       = true,

		-- The concept deck draws player health green and reserves colour for
		-- reaction. Class colouring is the common preference and reads faster in
		-- a group, so it wins by default - but it is one switch either way, and
		-- it lives at profile level because nameplates will want the same answer.
		classColorHealth = true,

		-- shared surface treatment
		glass = {
			-- Opacity 0..1, not a distance: the shadow's geometry is derived from
			-- the shape it sits under so its hole lines up with the shape's own
			-- curve. See Core\Glass.lua.
			shadow  = 1.0,
			corner  = 12,      -- panel corner radius
			-- How much deeper a READING surface sits than a control surface.
			--
			-- Chat and the quest log carry paragraphs of small text over moving
			-- scenery; the bars and capsules are glanced at. 0 makes them match
			-- the rest of the HUD, 1 makes them solid. Exposed because how much
			-- background clutter a person can read through is a matter of eyes
			-- and taste, not a number anyone can pick for them.
			readOpacity = 0.35,
		},

		-- the "HUD breathes out" behaviour from concept 1c / 2b
		fader = {
			enabled       = true,
			-- 0.35 was too far. The whole design is a translucent fill under a
			-- bright rim, and multiplying both by a third does not dim it so
			-- much as wash it out - the fill stops reading as a surface and the
			-- rim stops reading as an edge. At 0.6 the HUD still visibly steps
			-- back when nothing is happening, and still looks like itself.
			idleAlpha     = 0.60,
			activeAlpha   = 1.0,
			delay         = 6.0,   -- seconds of quiet before fading out
			fadeOut       = 0.75,
			fadeIn        = 0.25,
			keepOnTarget  = true,
			keepOnHurt    = true,
			keepOnMouse   = true,
		},

		anchors = {},

		-- Unlock-mode placement aids. gridSize is in UIParent units, the same
		-- space anchors are saved in, so "16" means the same thing at any
		-- resolution. snapDistance is how near an edge has to come before it is
		-- caught; much above ~20 and you can no longer put a frame where you
		-- actually meant to.
		movers = {
			grid         = true,
			gridSize     = 16,
			snap         = true,
			snapDistance = 12,
		},

		modules = {
			unitframes = {
				enabled  = true,
				-- 10 pad + 46 orb + 13 + 200 bars + 12 + 40 readout + 24 pad
				width    = 345,
				height   = 64,
				gap      = 18,       -- space between player and target capsules
				orbSize  = 46,
				barWidth = 200,
				showPower     = true,
				showPortrait  = false,   -- false = class-tinted level disc, as drawn
				showCastBar   = true,
				-- Needs LibClassicCasterino: Classic Era does not report other
				-- units' casts natively.
				showTargetCastBar = true,
				-- Both cast bars float free on their own movers, well above the
				-- cluster. Every edge of a capsule now belongs to an aura tray,
				-- and a bar that is only on screen mid-cast costs nothing by
				-- sitting where you are already looking.
				castWidth     = 300,
				hideBlizzard  = true,
				clickTarget   = true,
				-- The target's capsule rim, orb ring and cast bar follow their
				-- reaction. Two identically blue cast bars stacked one above the
				-- other are unreadable in a fight.
				reactionTint  = true,
			},

			actionbars = {
				enabled      = true,
				-- Multiplier on profile.scale, just for the dock. The concept's
				-- 62px slots are generous on a wide, high-DPI display, and the
				-- dock is the one element people most want to tune independently
				-- of the unit frames.
				scale        = 1.0,
				size         = 62,      -- concept 2a: 62px slots, 17px radius
				spacing      = 9,
				padding      = 10,
				-- Points added to the button text roles (keybind, count, cooldown).
				-- Offset rather than absolute so the type roles stay the single
				-- source of truth. Note the dock is drawn at profile.scale, so
				-- +2 here lands at roughly +1.4 on screen at the default 0.71.
				fontDelta    = 4,
				showKeybinds = true,
				tooltips     = true,
				lockButtons  = true,    -- require a modified click to pick up
				emptyAlpha   = 0.25,
				hideBlizzard = true,
				-- Every bar is its own thing with a fixed source. Bars 1-6 map onto
				-- the six action pages (bar N owns actions (N-1)*12+1 upward), and 7-10
				-- are the bonus bars a druid or rogue gets in a form - point a bar at
				-- page 7 and you simply *see* your Bear abilities instead of having a
				-- bar swap under you. Nothing pages, ever.
				--
				-- rows is the control and columns fall out of it. binding is derived
				-- from the page unless you name one, so bar 6 picks up the
				-- MULTIACTIONBAR1 keys you have always used for it.
				bars = {
					{ id = "1", kind = "action", page = 1, enabled = true,
					  buttons = 12, rows = 1, scale = 1.0, backdrop = true,
					  label = "Bar 1", point = "BOTTOM", x = 0, y = 26 },
					{ id = "2", kind = "action", page = 2, enabled = false,
					  buttons = 12, rows = 1, scale = 1.0, backdrop = true,
					  label = "Bar 2", point = "BOTTOM", x = 0, y = 118 },
					{ id = "3", kind = "action", page = 3, enabled = false,
					  buttons = 12, rows = 12, scale = 0.85, backdrop = true,
					  label = "Bar 3", point = "RIGHT", x = -24, y = 0 },
					{ id = "4", kind = "action", page = 4, enabled = false,
					  buttons = 12, rows = 12, scale = 0.85, backdrop = true,
					  label = "Bar 4", point = "RIGHT", x = -88, y = 0 },
					{ id = "5", kind = "action", page = 5, enabled = false,
					  buttons = 12, rows = 1, scale = 0.85, backdrop = true,
					  label = "Bar 5", point = "BOTTOM", x = 0, y = 190 },
					{ id = "6", kind = "action", page = 6, enabled = false,
					  buttons = 12, rows = 1, scale = 0.85, backdrop = true,
					  label = "Bar 6", point = "BOTTOM", x = 0, y = 250 },

					-- Button count comes from the game, not from config: however many
					-- forms you have, and the ten pet slots.
					{ id = "stance", kind = "stance", enabled = true,
					  rows = 1, scale = 0.8, backdrop = true,
					  label = "Stances", point = "BOTTOMLEFT", x = 24, y = 220 },
					{ id = "pet", kind = "pet", enabled = true,
					  rows = 1, scale = 0.8, backdrop = true,
					  label = "Pet", point = "BOTTOM", x = 0, y = 118 },

					-- Blizzard's own taxi "land at the next flight master" button and
					-- the extra action button, adopted rather than rebuilt: both fire
					-- protected actions, so the real frames are the only ones that work.
					-- Shows itself only when one of them does.
					-- `beside` parks it next to that bar rather than at a fixed screen
					-- position, because "beside bar 1" depends on how wide bar 1 happens
					-- to be. Only used when there is no saved position - move it once and
					-- that wins from then on.
					{ id = "extra", kind = "extra", enabled = true,
					  rows = 1, scale = 1.0, backdrop = true,
					  label = "Extra", beside = "1", side = "right",
					  point = "BOTTOM", x = 0, y = 26 },
				},
			},

			-- Four trays: buffs above each capsule, debuffs below, on the player
			-- and the target alike. Nothing lives inside a capsule any more, so the
			-- frames never resize and the two are always the same shape.
			auras = {
				enabled = true,
				-- Blizzard's own buff row, and the weapon-enchant icons that hang
				-- off it. Off means the stock icons stay, showing the same auras
				-- a second time above ours.
				hideBlizzard = true,

				-- Tile geometry is shared by all four trays. Identical trays are
				-- most of what makes the player and the target read as a pair.
				--
				-- A tile is the deck's buff pill without the name in the middle:
				-- icon left, timer right. `size` is the icon; the pill is 8 taller
				-- and wide enough for a fixed timer field. Columns are not
				-- configured at all - they are derived from how wide the capsule
				-- is, which is the whole of "a tray never exceeds the frame it
				-- belongs to".
				size      = 22,
				spacing   = 4,
				offset    = 6,     -- capsule edge -> first row
				showTime  = true,
				showCount = true,
				perRow    = 0,     -- 0 = as many as the frame is wide enough for
				-- CENTER or MIRROR. A row of pills almost never divides evenly
				-- into a capsule - four across a 345px frame leave ~49 over - and
				-- pushed onto one side that slack reads as a fifth pill that
				-- failed to load. Centred per row, it reads as margin.
				align     = "CENTER",

				buffs = {
					enabled = true,
					player  = true,
					target  = true,
					max     = 24,
					-- Three rows rather than two: at four pills across, two rows
					-- is eight buffs, and a raid-buffed character has more.
					maxRows = 3,
				},
				debuffs = {
					enabled = true,
					player  = true,
					target  = true,
					max     = 16,
					maxRows = 2,
					-- Target only. On yourself every debuff matters whoever cast it;
					-- on the target, yours are the ones you act on.
					onlyMine = true,
				},
			},

			-- Concept 4. Layer 1 only for now - the drawer, the rail and the
			-- dock. What goes INSIDE it (widgets, addons, settings tiles, the
			-- micro menu) lands in later layers; see docs/PLAN-Toolbox.md.
			toolbox = {
				enabled = true,

				-- How dark the covered strip goes. The deck's own 0.28. Zero
				-- turns it off entirely for anyone who would rather read what
				-- is behind the drawer than have it dimmed.
				scrim   = 0.28,

				-- Columns in the two grids. The deck draws three widget cards
				-- and two of everything else, and the numbers are here rather
				-- than in the module because a wide dock at a low UI scale has
				-- room for more.
				widgetColumns = 3,
				tileColumns   = 2,
				addonColumns  = 2,
			},

			questtracker = {
				enabled        = true,
				width          = 268,     -- the deck's panel width
				-- Show every quest in the log and let you dismiss the ones you do
				-- not want, rather than making you opt each one in. This is
				-- Questie's model, and it is the only one that is uncapped by
				-- construction instead of by working around Blizzard's cap.
				-- Turn it off for a whitelist you build by shift-clicking.
				autoTrack      = true,
				-- Cut the list to a height budget, not a row count, and say how
				-- many did not fit. 20 quests would be most of the screen.
				maxHeight      = 420,
				max            = 20,
				showObjectives = true,
				-- The level rides in a difficulty-tinted chip in front of the
				-- title, exactly as it does in the quest log: grey-means-stop and
				-- red-means-later is the fastest read on a list, and putting it in
				-- the chip leaves the titles themselves white and readable. Off,
				-- the difficulty is not shown at all - it has nowhere else to go.
				showLevel      = true,
				-- Fold to just the heading when a fight starts, per concept 2a,
				-- and unfold again after - unless you folded it yourself mid-fight,
				-- in which case that decision wins.
				combatCollapse = true,
				-- Whitelist mode only. Blizzard caps its watch list at five, so
				-- taking the entries and handing the slots straight back is what
				-- keeps shift-click working past the fifth quest. Auto mode never
				-- does this - it has no need of a gesture, and writing to another
				-- addon's state for no reason is how you break someone's day.
				adoptWatches   = true,
				hideBlizzard   = true,
			},

			-- The full log window from concept 3b, which REPLACES Blizzard's
			-- rather than reskinning it. Turning this off restores the stock
			-- quest log, including the L key and the micro button.
			questlog = {
				enabled = true,
			},

			-- Concept 5. One window for the backpack, the four bags and, at a
			-- banker, the bank and its own bags beside them. A replacement, not a
			-- reskin: Blizzard draws five independent ContainerFrames that each
			-- remember their own position, and there is no arrangement of those
			-- that turns into a single categorised grid.
			bags = {
				enabled      = true,
				hideBlizzard = true,

				-- Eight columns of 44 is what makes the panel 442 wide, which is
				-- the deck's number. Changing columns changes the window width;
				-- nothing else has to move.
				columns      = 8,
				slotSize     = 44,
				slotGap      = 6,

				-- The panel hugs its contents, up to this. Past it the grid
				-- scrolls on the wheel -- there is no bar, the concept has none.
				maxHeight    = 720,

				-- Which physical bag holds an item is invisible by design. This
				-- puts it back for anyone who wants to see it, at the cost of the
				-- whole idea.
				grouped      = false,

				showSearch   = true,
				qualityRim   = true,
				dimJunk      = true,

				-- The equipped bags and the keyring, on a rail off the right
				-- edge. Permanently open rather than behind a handle: the deck
				-- opens it from the capacity chip, and on screen that was a
				-- control nobody could find. A panel edge that is sometimes
				-- there is worse than one that always is.
				showFlyout   = true,
				showKeyring  = true,

				-- A FREE section at the foot of the grid. The concept does not
				-- draw one -- it reports "22 slots free" in the footer and stops
				-- there -- but with no empty slot on screen there is nowhere to
				-- drop an item you are carrying, and moving something out of the
				-- bank becomes impossible by drag. So it is drawn, and it is a
				-- setting for anyone who wants the concept's grid exactly.
				showEmpty    = true,

				-- Off by default, and it stays off until it is asked for. This
				-- setting sells things. The dimmed JUNK section is honest about
				-- what would go without it, so nobody has to switch it on to find
				-- out what it would have done.
				junkAutoSell = false,
			},

			-- A round map with a frosted rim and a glass pill under it carrying
			-- the zone, your coordinates and the time. Everything Blizzard hangs off
			-- the minimap goes, except mail: zoom moves to the wheel and tracking to
			-- right-click, so the two that were doing real work survive without any
			-- chrome to show for it.
			minimap = {
				enabled      = true,
				size         = 190,
				ring         = true,
				showNorth    = true,
				showZone     = true,
				showCoords   = true,
				showClock    = true,
				pillOffset   = 10,
				-- Opacity of the whole border - the dark band around the inside
				-- of the map's edge plus the hairline on it. One texture, so one
				-- number.
				border       = 1.0,
				hideBlizzard = true,
			},

			chat = {
				enabled     = true,
				-- Blizzard's own message fade, which is a different thing from
				-- our fader: it fades the *lines*, not the frame. Off, because a
				-- chat log that empties itself is the single most complained
				-- about default in the game.
				fadeMessages = false,
				timeVisible  = 120,
				-- Chat breathes with the rest of the HUD. It is text you might be
				-- reading, so this is the one element where "dims with everything
				-- else" is a real choice rather than an obvious one.
				fade         = true,
				-- Points added to whatever size Blizzard's own chat settings say.
				-- Offset rather than absolute so the size stays a real setting
				-- with a real menu behind it and we only own the face.
				-- Blizzard's chat default is 14, which is set for a 1080p screen
				-- with the stock font. Outfit at that size next to the rest of
				-- this UI is a good two points too loud, and this is the one
				-- element there is a lot of on screen at once.
				fontDelta    = -5,
				showZone     = true,
				-- Unlocking is what makes the frame movable *and* resizable, both
				-- through Blizzard's own machinery, which is also what saves them.
				-- Locked is the client's default, and it ignores the resize grip
				-- and the tab drag alike.
				unlocked     = true,
				resizable    = true,
				-- The scroll buttons, the resize grip and the menu buttons down
				-- the side. The concept has none of them.
				hideButtons  = true,

				-- The message lines. One master switch, because they are one
				-- mechanism: everything below hangs off the sender-name filter
				-- and the format strings, and half of them on is a line that
				-- reads as neither Blizzard's nor ours.
				styleLines      = true,
				classColorNames = true,
				-- Dropped. It is rare on Classic Era, it is never what you are
				-- reading a chat line for, and "Turdinand" is who you are
				-- talking to whichever realm the client thinks he is on. The
				-- code to dim it instead is still there behind this flag,
				-- because the name is only ever split - never rebuilt - so
				-- keeping the realm costs one concatenation, and the player
				-- link is built from the full name either way.
				hideRealm       = true,
				emDash          = true,
				badges          = true,
				-- Rendered height in pixels. The pill's width follows from it -
				-- every badge is the same shape, which is what keeps the names
				-- after them lined up.
				badgeSize       = 16,
				-- Zero, and confirmed on screen rather than reasoned about: the
				-- client already centres an inline texture on the line it sits
				-- in, so a pill needs no help to straddle the baseline. The
				-- assumption that it stands *on* the baseline - and therefore
				-- wanted lifting - is what put the first two defaults below the
				-- text. Negative sinks it, positive raises it; it is here as a
				-- nudge for a font this was not tuned against, not as a
				-- correction that every badge needs.
				badgeOffset     = 0,
				-- Blizzard's "[1. General - The Barrens]". False means gone: the
				-- badge is what replaces it.
				channelPrefix   = false,
				dimSystem       = true,

				-- Off, and it stays off until asked for out loud. Unlike
				-- everything else here this writes into *Blizzard's* saved
				-- variables - the window, its name and its message groups
				-- persist, and they persist with AetherUI turned off.
				whisperTab      = false,
				whisperTabName  = "Whispers",
			},

			-- The client's own StaticPopup dialogs, reskinned in place. A
			-- switch, because every module here is a reskin rather than a
			-- replacement and turning one off has to give Blizzard's back.
			popups = {
				enabled = true,
			},

			-- The client's own windows - character, spellbook, talents, guild,
			-- map, menu, help - reskinned in place. Same switch, same promise:
			-- off hands Blizzard's back.
			panels = {
				enabled = true,

				-- On top of profile.scale, because these windows are not ours.
				-- Everything inside them is the client's own furniture at a
				-- fixed pixel size - item icons, the paper doll, its stat rows
				-- - so a profile scale that suits our frames shrinks a Blizzard
				-- window past the point where you can read it.
				scale   = 1.0,
			},

			-- The client's mirror timers: breath underwater, fatigue at sea,
			-- the seconds left feigning death. Reskinned in place like the rest,
			-- and switchable for the same reason.
			timers = {
				enabled = true,
			},

			xpbar = {
				enabled  = true,
				height   = 4,
				showText = true,
			},

			-- The in-flight console. `learned` is durations we timed ourselves,
			-- keyed [from][to] like the shipped table and beating it - the
			-- shipped figures for the neutral hubs both factions share are a
			-- mean of two paths, so a measured one is worth more there.
			ifec = {
				enabled = true,
				-- THE PLAYER HALF, separately from the console. Flight tracking
				-- - the dial, the route, the countdown - is the permanent part
				-- and is not what this switches: off, a flight still opens the
				-- capsule and still counts you down, it just does not hang a
				-- programme under it. The mini-player on the Toolbox is
				-- unaffected, because it is not in flight.
				player  = true,
				-- KEEP PLAYING AFTER LANDING. Off, the programme stops with the
				-- flight, which is right for somebody who wants the console to
				-- be a thing that happens on a griffin. On, the queue simply
				-- carries on into the mini-player - it is the same queue and the
				-- same audio, and landing stops being an interruption.
				--
				-- Default off: audio still going after the player has control
				-- back is the worst failure this feature has, and it should be
				-- something asked for rather than something that happens.
				playOn  = false,
				hideUI  = true,
				-- On top of profile.scale, not instead of it, the way the dock
				-- and the nameplates have their own. The console is read once a
				-- minute from across the screen rather than glanced at
				-- constantly, so it wants to sit smaller than the HUD does.
				scale   = 0.8,
				learned = {},
			},

			-- Nameplates (concept 7a / 7b). The deck's own measurements: an 8/7
			-- /18/7 padding box, a 26 badge, a 10 gap to the right column, and a
			-- 160x5 bar under the name.
			nameplates = {
				enabled    = true,
				-- On top of profile.scale, not instead of it, the way the tooltip's
				-- own multiplier works. A plate is read at thirty yards and the
				-- HUD is read at arm's length, so the size that suits one is not
				-- automatically the size that suits the other.
				scale      = 1,
				-- The deck's 26. Three more, because at 26 a two-digit level sits
				-- hard against the rim and the disc reads as a ring with a number
				-- jammed in it rather than a number on a disc.
				badgeSize  = 29,
				barWidth   = 160,
				barHeight  = 5,
				-- Neutral units carry a name and nothing else until they are in a
				-- fight. A yellow plate is "not my problem yet", and a health bar
				-- on it is a row of numbers that means nothing.
				neutralBarInCombat = true,
				-- How far out the client bothers to make a plate at all. Past it
				-- there is no plate and the engine falls back to its own floating
				-- name text, which is the other system and wears the client's
				-- font - so the boundary is visible as a change of typeface at a
				-- fixed distance. 41 is the ceiling Blizzard's own slider stops
				-- at on this flavour; 20 is where it starts.
				maxDistance = 41,
				-- The client's "always show nameplates" - what the V key toggles.
				-- OFF, it only makes a plate for something in combat with you or
				-- for your target, and everything else in the world keeps the
				-- engine's own floating name in the engine's own font. A vendor
				-- standing at her counter is the obvious case: no plate, so
				-- nothing of ours ever runs on her.
				alwaysShow  = true,
				-- Blizzard's own plate underneath. Off is the whole point, but it
				-- is a switch because a plate we failed to draw is worse than
				-- theirs and this is the way back.
				hideBlizzard = true,
				-- Friendlies get plain text rather than a capsule, and a health
				-- bar only when they are hurt. A street of full green bars over
				-- a city is noise with nothing in it.
				friendlyNames = true,
				-- Off by default: a friendly player's name is blue because that
				-- is what "friendly player" looks like everywhere else in this
				-- UI, and a street of nine class colours says something you did
				-- not ask. On, it applies to your PARTY only.
				partyClassColors = false,
			},

			-- Tooltips (concept 6a / 6b).
			--
			-- Every one of these is a switch on a RESKIN. The module never
			-- replaces the client's tooltip, so turning any of them off returns
			-- that piece to Blizzard's behaviour rather than removing it - see
			-- the header of Modules\Tooltips.lua for why that distinction is the
			-- whole design.
			tooltips = {
				enabled      = true,
				-- On top of profile.scale, not instead of it. A tooltip is the
				-- surface people most often want a size apart from the HUD,
				-- because it is the one they read at arm's length.
				scale        = 1.0,
				corner       = 18,      -- the deck's radius; panels default to 12

				-- Restyle GameTooltipHeaderText / GameTooltipText /
				-- GameTooltipTextSmall. Reaches every line in every tooltip
				-- INCLUDING lines other addons add, which is the point rather
				-- than a side effect. Off leaves the client's own faces alone.
				restyleFonts = true,

				-- Take over the default anchor, so a world mouseover lands in the
				-- corner rather than following the mouse. Only the DEFAULT anchor;
				-- anything that called SetOwner itself is untouched either way.
				unitAnchor   = true,

				-- Cursor-follow for item and spell tooltips, at the deck's
				-- +24/-22. Scoped to tooltips that took the default anchor or
				-- whose owner is UIParent - a bag slot keeps the position it
				-- asked for. Widening this is the fastest way to make every
				-- other addon's tooltips feel broken.
				cursorItems  = true,

				-- The level badge, and with it the only text surgery in the
				-- module: the leading "Level 18" token comes off whichever line
				-- carries it so the number can go in the disc. Order-independent
				-- and idempotent, and it declines rather than guesses when the
				-- line does not parse. Off means the line reads as Blizzard
				-- wrote it and no badge is drawn.
				levelBadge   = true,
				-- ...and the guard that makes that default safe.
				--
				-- MobInfo2 does not only append to the level line, it READS the
				-- level number back out of it to find where a mob's extra info
				-- starts (MobInfo2.lua:2118-2131), on its shipped default path.
				-- Take the digits out for the badge and its harvest comes back
				-- empty. There is no having this both ways - the number is either
				-- in the line or in the disc - so the badge yields, and says so in
				-- /aether tooltips rather than silently doing nothing.
				--
				-- Turn this off to keep the badge anyway. It is your tooltip.
				deferToLevelReaders = true,
				eliteChip    = true,
				-- Append the reaction to the creature type: "Humanoid - Hostile".
				-- Content rather than styling, which is why it is separable.
				reactionWord = true,

				-- Numbers under the health hairline. The bar itself is always
				-- restyled when it appears; this is only its readout.
				healthValues = true,

				-- Quality-coloured title, rim and bloom on items.
				qualityBorder = true,
				-- The deck's lore gold on a spell's body copy. Only lines the
				-- client left plain white are touched - anything another addon
				-- coloured on purpose keeps its colour.
				loreGold     = true,

				-- The deck colours a friendly player's name #8ec8ff rather than
				-- by class, and that is what this defaulted to. It was wrong on
				-- its own terms: the unit frames class-colour by default, so the
				-- same player was blue in a tooltip and their own colour in the
				-- capsule beside it, and the tooltip read as having LOST class
				-- colours rather than as expressing a preference. One deck,
				-- one answer. The switch is still here for the deck's version.
				classColorNames = true,
			},

			-- Stage two of the fader. The timings live here rather than under
			-- `fader` because the module owning the readout is also the thing
			-- that decides whether zen is available at all - one enabled flag
			-- for "is there a stage two", not two that can disagree.
			zen = {
				enabled     = true,
				onAFK       = true,
				-- Seconds of quiet before zen. Capped at Fader.AFK_TIMEOUT (300)
				-- because the client flags you away at five minutes and going
				-- AFK triggers zen anyway - a longer timer could never fire.
				delay       = 60,
				-- Named for what the HUD does, not for what the readout does:
				-- fadeOut is the HUD leaving, which is the slow, deliberate one.
				fadeOut     = 2.5,
				fadeIn      = 0.30,
				hudAlpha    = 0,
				-- Fade UIParent itself rather than chasing individual frames.
				-- See the note at the top of Modules\Zen.lua: the list of things
				-- that were still on screen otherwise had no end to it.
				dimUI       = true,
				-- Off: zen takes the minimap with everything else, and the
				-- corner block draws a small glass disc beside the zone and the
				-- clock in its place.
				--
				-- The live map was tried and is the better argument on paper --
				-- it is the one part of the HUD still saying something while you
				-- are not playing. On screen it is not what zen is for. Joe,
				-- having seen both: "I preferred that even if it was imperfect."
				-- A quiet screen beats an informative one here.
				keepMinimap = false,
				-- The corner glyph draws the zone's own map art, cropped to a
				-- circle around where you are standing, with the accent dot in
				-- the middle marking you.
				--
				-- It is the WORLD map's art, not the minimap's view. Nothing can
				-- capture what the minimap renders - the client exposes no
				-- render-to-texture and no frame capture to an addon. The zone
				-- art is the one picture of your surroundings we can hold, and
				-- being static suits a calm mode better than the live one would.
				showMapArt  = true,
				glyphSize   = 22,
				width       = 250,   -- the capsule holding both bars
				yOffset     = 14,    -- above the screen's bottom edge
				showCaption = true,
				showDots    = true,
				showPill    = true,
				keyboardWake = true,

				-- The frosted pane
				-- ---------------
				-- Nothing here blurs anything. It cannot: the client gives addons
				-- no render-to-texture, no shader hook and no post-process stage,
				-- so the 3D scene behind the HUD is the one surface this addon can
				-- never touch the pixels of. What it *can* do is put a pane in
				-- front of it, which is what frosted glass is anyway - the world
				-- stays sharp underneath, and every cue that says "frosted" (a
				-- tint, a grain, a darkening at the edges) is on the pane.
				--
				-- Four layers, because one is not convincing. See the note in
				-- Modules\Zen.lua for what each one is for.
				frost         = true,
				-- 0.70/0.75 was the first pass at "brighter", and it overshot -
				-- on screen it read as fog rather than as glass. These are the
				-- numbers after seeing it: still unmistakably a lit, scattering
				-- surface, but you can make out the room through it.
				frostOpacity  = 0.58,
				-- How far the skin's glass colour is lifted toward white. This
				-- is the setting that was wrong in the first pass, which capped
				-- the tint's brightness instead of raising it and so dragged a
				-- near-black sheet across the screen on Midnight.
				--
				-- Frosted glass scatters light: it is BRIGHTER than what is
				-- behind it, and what it takes away is contrast, not brightness.
				-- A dark pane leaves every edge in the scene perfectly crisp and
				-- just turns the lights off.
				frostBrightness = 0.62,
				-- Strength of both Frost.tga layers - the visible patches and
				-- the additive light that flattens the world's contrast.
				frostScatter  = 0.35,
				-- Low. At 0.45 this was doing most of the darkening the pane as
				-- a whole was being blamed for.
				frostVignette = 0.15,
				-- Screens per second the two scatter layers slide, in opposite
				-- directions. Far too slow to read as movement; it is there for
				-- the parallax against a world that is not moving, which is what
				-- makes the pane feel like a surface rather than a decal. 0 stops
				-- it dead.
				frostDrift    = 0.01,

				-- Nameplates AND the floating unit names, which are two entirely
				-- separate CVar families and the one distraction UIParent's
				-- alpha does not reach - both are rendered against the world
				-- rather than composited into the interface. One switch, because
				-- taking away the bars and leaving the names looks like a fault
				-- rather than a choice.
				--
				-- Named for the plates alone because that is what it was called
				-- when it only did half the job, and renaming a profile key
				-- silently resets it for everybody who already has one.
				--
				-- Tooltips need nothing: they are children of UIParent and they
				-- go with it.
				hideNameplates = true,

				-- The shot
				-- --------
				-- Sitting uses the emote rather than SitStandOrDescendStart,
				-- which is what the keybind runs and is a TOGGLE - on somebody
				-- already sitting it stands them up, which is the wrong way
				-- round on exactly the players most likely to be idle.
				--
				-- Skipped outright while mounted, on a taxi, in combat or dead:
				-- a refused emote puts a red error across the middle of a screen
				-- whose entire purpose is being quiet.
				sit           = true,

				-- Metres behind the character. Exact and exactly reversible -
				-- GetCameraZoom reads the current distance, so the player's own
				-- is put back rather than guessed at.
				camera        = true,
				cameraZoom    = 3.0,
				-- Seconds of DOWNWARD movement, NOT an angle. Pitch has no
				-- getter and no setter in this client; the only control is
				-- movement over time, so an amount can be asked for and never
				-- measured. The way back is the same movement reversed for the
				-- same duration.
				--
				-- Down, because the shot is the player looking OUT at the world
				-- from about where they are sitting. The first pass moved the
				-- camera up, which points it at the top of the character's head
				-- and frames the floor around them.
				--
				-- Relative, so where it ends up depends on where the player's
				-- camera already was. Tune it live with `/aether zen pitch N`
				-- rather than by reloading - the client's rate for this is not
				-- documented anywhere and 1.0 is a guess at its units.
				--
				-- The over-the-shoulder offset is GONE. It needed
				-- test_cameraOverShoulder, which the client treats as
				-- experimental and puts a confirmation dialog in front of on
				-- every write - so the feature cost a modal each way for a
				-- composition the mode never wanted. Removed rather than
				-- defaulted off: an option nobody can use without being
				-- interrogated is not an option.

				-- The audio profile
				-- -----------------
				-- Zen borrows the sound channels for as long as it is on screen
				-- and gives them back. Master is never touched - if somebody has
				-- turned the game down, they have turned the game down.
				--
				-- The duck ratios are FRACTIONS OF WHAT THE PLAYER ALREADY HAD,
				-- not absolute volumes, so this never needs to know what anyone's
				-- normal settings are and never flattens a careful mix into one
				-- of ours. 0.05 of an SFX channel at 80% is 4%; at 20% it is 1%.
				audio        = true,
				-- A key from Zen.TRACKS, or "random" to pick one per session.
				track        = "random",
				duckSFX      = 0.05,
				duckAmbience = 0.15,
				duckDialog   = 0.10,
				-- Music is the one channel that is raised rather than lowered,
				-- and only ever to a floor: playing a meditation track through a
				-- music channel somebody left at zero is a feature that silently
				-- does nothing. Above the floor already, this does nothing. Set
				-- it to 0 to leave the music channel completely alone.
				musicFloor   = 0.40,
			},
		},
	},
}

--- One-shot migrations for profiles written by an older layout.
--
--  Kept deliberately small and deliberately loud in the code: a config that
--  silently half-applies is worse than one that resets.
local function Migrate(db)
	local m = db.profile.modules
	if not m then return end

	-- The over-the-shoulder camera is gone: it needed test_cameraOverShoulder,
	-- which the client calls experimental and puts a confirmation dialog in
	-- front of on every write. Removed rather than defaulted off - an option
	-- nobody can use without being interrogated is not an option. Its two keys
	-- go with it so they cannot be read back by anything.
	if m.zen then
		m.zen.cameraShoulder = nil
		m.zen.cameraShoulderSide = nil
	end

	-- The in-flight console was called `inflight` for an afternoon. Renamed to
	-- avoid colliding with an existing addon of that name; the learned flight
	-- durations under it are real measurements and worth carrying across.
	if m.inflight then
		m.ifec = m.ifec or {}
		for k, v in pairs(m.inflight) do
			if m.ifec[k] == nil then m.ifec[k] = v end
		end
		m.inflight = nil
	end
	if db.profile.anchors and db.profile.anchors.inflight then
		db.profile.anchors.ifec = db.profile.anchors.ifec or db.profile.anchors.inflight
		db.profile.anchors.inflight = nil
	end

	-- Auras came out of the capsules. Everything the old in-capsule tray needed
	-- to describe itself is now either derived from the frame's width or shared
	-- across all four trays, so the old keys have no meaning to carry forward -
	-- they are removed rather than mapped, because a stale `perRow = 2` silently
	-- capping a tray at two icons would be worse than no setting at all.
	local au = m.auras
	if au then
		if au.buffs then
			au.buffs.attach, au.buffs.offset, au.buffs.perRow = nil, nil, nil
			au.buffs.spacing, au.buffs.maxWidth = nil, nil
			au.buffs.player = au.buffs.player ~= false
			au.buffs.target = au.buffs.target ~= false
		end
		if au.debuffs then
			au.debuffs.perRow, au.debuffs.minColumn, au.debuffs.spacing = nil, nil, nil
		end
	end

	-- The cast bars can no longer be attached to anything.
	-- The minimap border was a rim texture plus a separately-gated inner
	-- vignette; it is one texture now, and a profile carrying `shadow = 0` from
	-- the version where the ring was off by default would otherwise hide it.
	local mm = m.minimap
	if mm then mm.shadow = nil end

	local uf = m.unitframes
	if uf then
		uf.castAttach, uf.castOffset = nil, nil
	end

	-- Nothing to map for zen - it is a new key and the defaults metatable serves
	-- it - but a hand-edited saved variable can carry a delay past the point
	-- where the client's own AFK flag makes it unreachable, and a setting that
	-- can never fire looks like a broken feature rather than a bad number.
	local zen = m.zen
	if zen then
		if zen.delay and zen.delay > 300 then zen.delay = 300 end
		-- yOffset used to be measured up from the centre of the screen, because
		-- the readout used to float above the player. It is measured up from the
		-- bottom edge now, so an old value is not a different preference - it is
		-- the same number meaning something else, and it would put the readout
		-- somewhere nobody asked for. Dropped rather than converted.
		if zen.yOffset and zen.yOffset > 200 then zen.yOffset = nil end
		-- The frosted pane's grain became its scatter: a different texture at a
		-- different scale doing a different job, on a slider whose useful range
		-- is three times as wide. An old `frostGrain = 0.07` carried forward as
		-- a scatter value would be a pane with nothing visible on it, which is
		-- the exact complaint the rework was for. Dropped rather than converted.
		zen.frostGrain = nil
	end

	local ab = m.actionbars
	if not ab then return end

	-- The bars used to be a paged set described by `columns`; they are now
	-- independent and described by `rows`. Both carried the same information.
	ab.paging = nil
	for _, bar in ipairs(ab.bars or {}) do
		if bar.columns and not rawget(bar, "rows") then
			local n = bar.buttons or 12
			bar.rows = math.max(1, math.ceil(n / math.max(1, bar.columns)))
		end
		bar.columns = nil
		-- "primary" was the old name for "follow the action page".
		if bar.page == "primary" then bar.page = 1 end
	end
end

function Config:Initialize()
	local AceDB = LibStub("AceDB-3.0")
	A.db = AceDB:New("AetherUIDB", Config.defaults, true)
	Migrate(A.db)

	A.db.RegisterCallback(A, "OnProfileChanged", function() A:Restyle(); A:Reconfigure() end)
	A.db.RegisterCallback(A, "OnProfileCopied",  function() A:Restyle(); A:Reconfigure() end)
	A.db.RegisterCallback(A, "OnProfileReset",   function() A:Restyle(); A:Reconfigure() end)
end

--- Convenience accessor: A.Config:Module("unitframes")
function Config:Module(name)
	local m = A.db.profile.modules[name]
	if not m then
		m = {}
		A.db.profile.modules[name] = m
	end
	return m
end
