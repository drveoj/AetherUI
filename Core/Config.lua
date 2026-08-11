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
		tracked   = {},   -- whitelist, used when autoTrack is off
		untracked = {},   -- blacklist, used when autoTrack is on
	},

	profile = {
		skin        = "midnight",
		-- Module geometry is written in the concept deck's own pixel values. The
		-- deck is 1920 wide; WoW's virtual space is 768 tall, so 1365 wide at
		-- 16:9. 1365/1920 = 0.711 maps one onto the other, which is why this is
		-- not 1.0. Raise it if you want everything larger than the deck.
		scale       = 0.71,
		debug       = false,

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
				showMail     = true,
				pillOffset   = 10,
				-- Opacity of the whole border - the dark band around the inside
				-- of the map's edge plus the hairline on it. One texture, so one
				-- number.
				border       = 1.0,
				hideBlizzard = true,
				-- Addon buttons are collected into a drawer that slides out of the
				-- zone pill on hover and is otherwise not on screen at all.
				drawer        = true,
				drawerColumns = 6,
				buttonSize    = 24,
				buttonSpacing = 6,
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

			xpbar = {
				enabled  = true,
				height   = 4,
				showText = true,
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
				width       = 250,   -- the capsule holding both bars
				yOffset     = 14,    -- above the screen's bottom edge
				showCaption = true,
				showDots    = true,
				showPill    = true,
				keyboardWake = true,
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
