--[[--------------------------------------------------------------------------
	AetherUI :: Options

	The AceConfig option tree. `/aether` on its own now opens this; the slash
	commands in Commands.lua still work and are still the fast way to nudge one
	number, but they had grown past the point where anyone could hold them in
	their head.

	Two things are worth knowing about how this is written.

	**The tree is data, and building it does not need the libraries.** `Build()`
	returns a plain table and touches nothing but the config, so the harness can
	walk every option and check that its path actually resolves - which is the
	failure mode of a hand-written option tree. A typo in a path is otherwise a
	control that silently does nothing, and you find it a month later.

	**Every leaf carries its own path and its own follow-up.** Rather than a
	getter and setter per option, each one says where it lives
	(`arg.path = { "modules", "unitframes", "width" }`) and what to do afterwards
	(`arg.after = "reconfigure"`). One pair of accessors serves the lot.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local Options = {}
A.Options = Options

local APP = "AetherUI"

-- ---------------------------------------------------------------------------
-- accessors
-- ---------------------------------------------------------------------------

--- Walk a path down profile and hand back the table plus the final key, so the
--  caller can read or write it. Returns nil if any step is missing, which is
--  what the harness's path check leans on.
local function Resolve(path)
	local t = A.db and A.db.profile
	if not t or not path then return nil end
	for i = 1, #path - 1 do
		t = t[path[i]]
		if type(t) ~= "table" then return nil end
	end
	return t, path[#path]
end

Options.Resolve = Resolve

local function Apply(after)
	if after == "restyle" then
		A:Restyle()
	elseif after == "both" then
		A:Restyle()
		A:Reconfigure()
	elseif after == "grid" then
		-- Placement aids only. Reconfiguring every module because the grid
		-- spacing changed would rebuild the whole HUD under the player's cursor
		-- while they are in the middle of dragging something.
		if A.Movers and A.Movers.RefreshGrid then A.Movers:RefreshGrid() end
	elseif after ~= "none" then
		A:Reconfigure()
	end
end

local function Get(info)
	local t, k = Resolve(info.arg and info.arg.path)
	if not t then return nil end
	local v = t[k]
	-- AceConfig wants a real boolean from a toggle, and a few of ours default to
	-- nil-means-true.
	if info.type == "toggle" and info.arg.defaultTrue then return v ~= false end
	return v
end

local function Set(info, value)
	local t, k = Resolve(info.arg and info.arg.path)
	if not t then return end
	t[k] = value

	-- `modules.<name>.enabled` is not just a flag: a module being switched off
	-- has to be told to tear itself down, and one switched on has to be built.
	-- Recognised by the shape of the path rather than by a marker on each leaf,
	-- so every module page gets this - including the ones that have been quietly
	-- writing `enabled = false` and carrying on regardless - and so a new module
	-- page cannot forget it. The three-element test is what keeps it off nested
	-- sub-toggles like `modules.auras.buffs.enabled`.
	local p = info.arg.path
	if #p == 3 and p[1] == "modules" and p[3] == "enabled" and A.modules[p[2]] then
		A:SetModuleEnabled(p[2], value and true or false)
	end

	-- A few settings are not just a number somebody reads later - flipping them
	-- has to *do* something that no amount of reconfiguring will do on its own,
	-- like opening a chat window. Those carry their own action, and a leaf that
	-- returns false has its write rolled back: a switch that says "on" while the
	-- thing it names did not happen is worse than one that refuses.
	local onSet = info.arg.onSet
	if onSet and onSet(value) == false then
		t[k] = not value
		return
	end

	Apply(info.arg.after)
end

-- ---------------------------------------------------------------------------
-- little constructors, so the tree below reads as a spec rather than as syntax
-- ---------------------------------------------------------------------------

local order = 0
local function next_() order = order + 1 return order end

local function toggle(name, desc, path, opts)
	opts = opts or {}
	return {
		type = "toggle", name = name, desc = desc, order = next_(),
		width = opts.width, get = Get, set = Set,
		arg = { path = path, after = opts.after, defaultTrue = opts.defaultTrue,
			onSet = opts.onSet },
	}
end

local function range(name, desc, path, min, max, step, opts)
	opts = opts or {}
	return {
		type = "range", name = name, desc = desc, order = next_(),
		min = min, max = max, step = step, isPercent = opts.percent,
		width = opts.width, get = Get, set = Set,
		arg = { path = path, after = opts.after },
	}
end

local function choice(name, desc, path, values, opts)
	opts = opts or {}
	return {
		type = "select", name = name, desc = desc, order = next_(),
		values = values, width = opts.width, get = Get, set = Set,
		arg = { path = path, after = opts.after },
	}
end

local function action(name, desc, fn)
	return {
		type = "execute", name = name, desc = desc, order = next_(), func = fn,
	}
end

local function header(name)
	return { type = "header", name = name, order = next_() }
end

local function note(text)
	return { type = "description", name = text, order = next_(), fontSize = "medium" }
end

local function group(name, args, opts)
	opts = opts or {}
	return {
		type = "group", name = name, order = next_(), args = args,
		inline = opts.inline, childGroups = opts.childGroups,
	}
end

-- ---------------------------------------------------------------------------
-- the tree
-- ---------------------------------------------------------------------------

local function SkinValues()
	local out = {}
	for _, s in ipairs(A.Palette:List()) do out[s.key] = s.name or s.key end
	return out
end

local function GeneralGroup()
	return group("General", {
		skin = choice("Skin", "Midnight is the concept deck's own palette.",
			{ "skin" }, SkinValues, { after = "restyle" }),
		scale = range("Scale", "Everything at once. 0.71 maps the deck's 1920px"
			.. " geometry onto WoW's virtual space one-for-one, which is why it is"
			.. " not 1.0.", { "scale" }, 0.6, 1.6, 0.01),
		classColorHealth = toggle("Class-coloured health",
			"Off uses the concept's green and reserves colour for reaction.",
			{ "classColorHealth" }, { after = "restyle" }),

		glassHeader = header("Glass"),
		shadow = range("Shadow opacity", "An opacity, not a distance - the shadow's"
			.. " geometry is derived from the shape it sits under so its hole lines"
			.. " up with that shape's own curve.",
			{ "glass", "shadow" }, 0, 1, 0.05, { after = "restyle" }),
		corner = range("Panel corner radius", nil, { "glass", "corner" }, 4, 24, 1,
			{ after = "restyle" }),
		readOpacity = range("Reading panel opacity",
			"How much deeper chat and the quest log sit than the rest of the HUD."
			.. " 0% matches the action bars and capsules; 100% is solid. They"
			.. " carry paragraphs of small text over moving scenery, so they need"
			.. " more than a surface you only glance at - how much more depends on"
			.. " your eyes.",
			{ "glass", "readOpacity" }, 0, 1, 0.05,
			{ after = "restyle", percent = true }),

		posHeader = header("Positions and keys"),
		bind = action("Keybind mode",
			"Hover a button and press a key. Keys go into Blizzard's own binding"
			.. " set, so they survive this addon being disabled and show up in the"
			.. " keybinding panel.",
			function()
				local AB = A:GetModule("actionbars")
				if AB and AB.enabled then A.Options:Close(); AB:ToggleBindMode() end
			end),
		unlock = action("Unlock frames", "Drag to move, scroll to nudge.",
			function() A.Options:Close(); A.Movers:Toggle() end),
		reset = action("Reset positions", "Forget every saved anchor.",
			function() A.Movers:ResetAll() end),

		gridHeader = header("While frames are unlocked"),
		gridNote = note("Edges and centres snap to the grid and to the other frames"
			.. " on screen, which is what actually gets two bars lined up. Another"
			.. " frame always wins over the grid, and holding alt while you drag"
			.. " turns the whole thing off for that one placement."),
		grid = toggle("Show grid", nil, { "movers", "grid" }, { after = "grid" }),
		gridSize = range("Grid spacing", "Every fourth line is drawn brighter.",
			{ "movers", "gridSize" }, 4, 64, 2, { after = "grid" }),
		snap = toggle("Snap to edges", nil, { "movers", "snap" }, { after = "grid" }),
		snapDistance = range("Snap distance", "How close an edge has to come before"
			.. " it is caught. Much above 20 and you can no longer put a frame where"
			.. " you actually meant to.",
			{ "movers", "snapDistance" }, 2, 30, 1, { after = "grid" }),
	})
end

local function FaderGroup()
	-- The client's own auto-AFK delay, from Core\Fader.lua. Read here rather than
	-- written twice so the slider and the state machine cannot drift apart.
	local ZEN_MAX = (A.Fader and A.Fader.AFK_TIMEOUT) or 300
	return group("Idle fade", {
		desc = note("The HUD breathes out when nothing is happening. Idle is"
			.. " inferred rather than observed: Classic gives addons no general"
			.. " keypress hook, so this watches consequences - combat, casting,"
			.. " having a target, being below full health or mana, cursor movement -"
			.. " and treats their absence as idle."),
		enabled = toggle("Enabled", nil, { "fader", "enabled" }, { after = "none" }),
		idleAlpha = range("Idle opacity", nil, { "fader", "idleAlpha" }, 0, 1, 0.05,
			{ after = "none" }),
		activeAlpha = range("Active opacity", nil, { "fader", "activeAlpha" }, 0.2, 1, 0.05,
			{ after = "none" }),
		delay = range("Quiet before fading", "Seconds.", { "fader", "delay" }, 0.5, 60, 0.5,
			{ after = "none" }),
		fadeOut = range("Fade out time", nil, { "fader", "fadeOut" }, 0, 3, 0.05,
			{ after = "none" }),
		fadeIn = range("Fade in time", nil, { "fader", "fadeIn" }, 0, 3, 0.05,
			{ after = "none" }),
		keepHeader = header("Stay awake while"),
		keepOnTarget = toggle("You have a target", nil, { "fader", "keepOnTarget" },
			{ after = "none" }),
		keepOnHurt = toggle("Health or mana is down", nil, { "fader", "keepOnHurt" },
			{ after = "none" }),
		keepOnMouse = toggle("The cursor is over a frame", nil, { "fader", "keepOnMouse" },
			{ after = "none" }),

		zenHeader = header("Zen"),
		zenNote = note("Stage two. The whole interface goes and a single capsule"
			.. " takes its place along the bottom edge - health, power, and a slow"
			.. " breath - with the zone and the time in the corner. Anything you do"
			.. " brings it back, including a keypress, which is the one thing stage"
			.. " one cannot see."
			.. "\n\n|cff9d7bffOnly the hard signals hold this off|r: combat, casting,"
			.. " and the cursor sitting on the HUD. Having a target or being below"
			.. " full health keeps stage one awake but not this one, because"
			.. " neither is evidence that you are still in the chair."),
		zenEnabled = toggle("Enabled", nil, { "modules", "zen", "enabled" },
			{ after = "none" }),
		zenOnAFK = toggle("When you go away",
			"The client flags you away by itself after five minutes without input,"
			.. " so this fires even if the timer below is longer than that.",
			{ "modules", "zen", "onAFK" }, { after = "none", defaultTrue = true }),
		zenDelay = range("Quiet before zen",
			"Seconds. Capped at five minutes, because that is when the client"
			.. " flags you away and zen would happen anyway.",
			{ "modules", "zen", "delay" }, 10, ZEN_MAX, 5, { after = "none" }),
		zenFadeOut = range("Time to sink into it", nil, { "modules", "zen", "fadeOut" },
			0.2, 6, 0.1, { after = "none" }),
		zenFadeIn = range("Time to come back", nil, { "modules", "zen", "fadeIn" },
			0.05, 2, 0.05, { after = "none" }),
		zenKeys = toggle("A keypress wakes it",
			"Adds a frame that listens for keys while zen is on screen and passes"
			.. " every one of them straight through. It is only listening while"
			.. " zen is up.",
			{ "modules", "zen", "keyboardWake" }, { after = "none", defaultTrue = true }),

		zenLookHeader = header("Zen readout"),
		zenDimUI = toggle("Take the whole interface with it",
			"Fades UIParent, which is everything: the minimap, the chat frame, the"
			.. " XP hairline, nameplates, and anything any other addon has put on"
			.. " screen. Off leaves only AetherUI's own frames fading, which means"
			.. " everything else stays up.",
			{ "modules", "zen", "dimUI" }, { after = "none", defaultTrue = true }),
		zenWidth = range("Capsule width", nil, { "modules", "zen", "width" },
			160, 600, 5),
		zenY = range("Height above the bottom edge", nil, { "modules", "zen", "yOffset" },
			0, 200, 2),
		zenCaption = toggle("Show the caption", nil, { "modules", "zen", "showCaption" },
			{ defaultTrue = true }),
		zenDots = toggle("Show the breath",
			"The row of dots. They carry no information - they are a slow pulse,"
			.. " so a still screen still looks alive.",
			{ "modules", "zen", "showDots" }, { defaultTrue = true }),
		zenPill = toggle("Show the zone and time", nil, { "modules", "zen", "showPill" },
			{ defaultTrue = true }),
	})
end

local function UnitFramesGroup()
	local m = { "modules", "unitframes" }
	local function at(k) return { "modules", "unitframes", k } end
	return group("Unit frames", {
		enabled = toggle("Enabled", nil, at("enabled")),
		hideBlizzard = toggle("Hide Blizzard's frames", nil, at("hideBlizzard")),
		clickTarget = toggle("Click to target",
			"Left-click targets, right-click opens the unit menu.", at("clickTarget")),

		sizeHeader = header("Capsule"),
		width = range("Width", nil, at("width"), 240, 520, 1),
		height = range("Height", nil, at("height"), 48, 96, 1),
		gap = range("Gap between player and target", nil, at("gap"), 0, 200, 1),
		orbSize = range("Orb size", nil, at("orbSize"), 28, 72, 1),
		barWidth = range("Bar width", nil, at("barWidth"), 120, 380, 1),
		showPower = toggle("Show power bar", nil, at("showPower")),
		showPortrait = toggle("Portrait in the orb",
			"Off draws the class-tinted level disc the concept uses.",
			at("showPortrait")),

		castHeader = header("Cast bars"),
		showCastBar = toggle("Player cast bar", nil, at("showCastBar")),
		showTargetCastBar = toggle("Target cast bar",
			"Classic Era does not report other units' casts natively; this reads"
			.. " them from the combat log via LibClassicCasterino.",
			at("showTargetCastBar")),
		castNote = note("Both cast bars float free on their own movers, well above"
			.. " the cluster: every edge of a capsule now belongs to an aura tray."
			.. "  |cff9d7bff/aether unlock|r to place them - they are held up while"
			.. " you do, since a bar you only ever see mid-cast is a bar you could"
			.. " never aim at."),
		castWidth = range("Cast bar width", nil, at("castWidth"), 160, 520, 1),
		reactionTint = toggle("Colour the target by reaction",
			"The target's capsule rim, orb ring and cast bar take their reaction -"
			.. " red for hostile, amber for neutral, green for friendly. Yours stay"
			.. " the concept's blue, which is what makes the two stacked cast bars"
			.. " tellable apart mid-fight.",
			at("reactionTint"), { defaultTrue = true, after = "restyle" }),
	})
end

local function AurasGroup()
	local function at(...) return { "modules", "auras", ... } end
	return group("Auras", {
		enabled = toggle("Enabled", nil, at("enabled")),
		hideBlizzard = toggle("Hide Blizzard's buff row",
			"Takes the weapon-enchant icons with it, and nothing replaces those yet.",
			at("hideBlizzard"), { defaultTrue = true }),

		desc = note("Four trays: buffs above each capsule, debuffs below, on the"
			.. " player and the target alike. Nothing sits inside a capsule, so the"
			.. " frames never resize and the two are always the same shape."),

		tileHeader = header("Tiles"),
		tileNote = note("A tile is an icon and a timer, with no name - the name is on"
			.. " the tooltip, and dropping it takes a row from three across a capsule"
			.. " to a dozen. Right-click one of your own buffs to cancel it, in combat"
			.. " as well as out of it."),
		size = range("Icon size", nil, at("size"), 12, 48, 1),
		spacing = range("Spacing", nil, at("spacing"), 0, 16, 1),
		offset = range("Gap from the capsule", nil, at("offset"), 0, 40, 1),
		showTime = toggle("Show timers", nil, at("showTime"), { defaultTrue = true }),
		showCount = toggle("Show stack counts", nil, at("showCount"), { defaultTrue = true }),
		align = choice("Row alignment",
			"Centred splits the slack a row cannot fill into two margins. Mirrored"
			.. " follows the unit's own name and readout - left on the player,"
			.. " right on the target - which puts all of it on one side.",
			at("align"), { CENTER = "Centred", MIRROR = "Mirrored" }),
		perRow = range("Cap the columns",
			"0 fits as many as the frame is wide enough for, which is what keeps a"
			.. " tray inside the unit it belongs to. Set a number to use fewer.",
			at("perRow"), 0, 16, 1),

		buffs = group("Buffs", {
			enabled = toggle("Enabled", nil, at("buffs", "enabled")),
			player = toggle("On the player", nil, at("buffs", "player")),
			target = toggle("On the target", nil, at("buffs", "target")),
			max = range("Most to show", nil, at("buffs", "max"), 1, 40, 1),
			maxRows = range("Rows at most", nil, at("buffs", "maxRows"), 1, 4, 1),
		}, { inline = true }),

		debuffs = group("Debuffs", {
			enabled = toggle("Enabled", nil, at("debuffs", "enabled")),
			player = toggle("On the player", nil, at("debuffs", "player")),
			target = toggle("On the target", nil, at("debuffs", "target")),
			onlyMine = toggle("Only mine, on the target",
				"On yourself every debuff matters whoever cast it.",
				at("debuffs", "onlyMine")),
			max = range("Most to show", nil, at("debuffs", "max"), 1, 40, 1),
			maxRows = range("Rows at most", nil, at("debuffs", "maxRows"), 1, 4, 1),
		}, { inline = true }),
	})
end

local function MinimapGroup()
	local function at(...) return { "modules", "minimap", ... } end
	return group("Minimap", {
		enabled = toggle("Enabled", nil, at("enabled")),
		desc = note("A round map with a frosted rim, and a glass pill under it"
			.. " carrying the zone, your coordinates and the time - which swaps for"
			.. " a red dot and |cffff8a8aIn combat|r in a fight."),
		size = range("Size", nil, at("size"), 120, 320, 1),
		ring = toggle("Border", nil, at("ring"), { defaultTrue = true }),
		showNorth = toggle("North marker", nil, at("showNorth"), { defaultTrue = true }),
		pillOffset = range("Gap below the map", nil, at("pillOffset"), 0, 40, 1),
		border = range("Border strength",
			"The dark band around the inside of the map's edge, and the hairline"
			.. " on it. One texture, so one number.",
			at("border"), 0, 1, 0.05),

		pillHeader = header("The pill"),
		showZone = toggle("Zone name", nil, at("showZone"), { defaultTrue = true }),
		showCoords = toggle("Coordinates",
			"Unavailable inside an instance, where the pill simply drops them.",
			at("showCoords"), { defaultTrue = true }),
		showClock = toggle("Clock", nil, at("showClock"), { defaultTrue = true }),
		showMail = toggle("Mail pill",
			"A small pill beside the block, and only when you have unread mail.",
			at("showMail"), { defaultTrue = true }),

		blizzHeader = header("Blizzard's own"),
		hideBlizzard = toggle("Hide the minimap furniture",
			"Zoom, tracking, the day/night dial, the battleground eye, the border"
			.. " art and the toggle tab. Zoom moves to the mouse wheel and tracking"
			.. " to right-clicking the map, so nothing is actually lost.",
			at("hideBlizzard"), { defaultTrue = true }),

		drawerHeader = header("Button drawer"),
		drawerNote = note("Buttons other addons park on the minimap are collected"
			.. " into a drawer that slides out of the zone pill when you hover it."
			.. "  |cff888888Map pins are left alone - they are not buttons, and there"
			.. " can be thousands of them.|r"),
		drawer = toggle("Collect addon buttons", nil, at("drawer"), { defaultTrue = true }),
		drawerColumns = range("Buttons per row", nil, at("drawerColumns"), 1, 12, 1),
		skinButtons = toggle("Skin them",
			"Mask each icon to a circle, ring it like the rest of the UI, and"
			.. " switch off whatever bevel it arrived with.",
			at("skinButtons"), { defaultTrue = true }),
		buttonSize = range("Button size", nil, at("buttonSize"), 16, 40, 1),
		buttonSpacing = range("Spacing", nil, at("buttonSpacing"), 0, 16, 1),
	})
end

--- One page per configured bar, built from the config rather than hard-coded, so
--  a bar added later gets its controls for free.
local function BarPages()
	local pages = {}
	local cfg = A.Config:Module("actionbars")

	for i, barCfg in ipairs(cfg.bars or {}) do
		local id = tostring(barCfg.id)
		local kind = barCfg.kind or "action"
		local function at(k) return { "modules", "actionbars", "bars", i, k } end

		local args = {
			enabled = toggle("Enabled", nil, at("enabled")),
			source = note(kind == "action"
				and ("Actions " .. (((barCfg.page or 1) - 1) * 12 + 1) .. "-"
					.. ((barCfg.page or 1) * 12) .. ".")
				or (kind == "extra"
					and "Blizzard's taxi and extra-action buttons, adopted rather than"
						.. " rebuilt - they fire protected actions, so the real frames"
						.. " are the only ones that work."
					or ("Sized by the game: however many " .. kind
						.. " slots you have."))),
			rows = range("Rows", "Columns fall out of this.", at("rows"), 1, 12, 1),
			scale = range("Scale", "On top of the global scale.", at("scale"), 0.4, 2.0, 0.05),
			backdrop = toggle("Glass panel", "Off leaves the buttons bare.",
				at("backdrop"), { defaultTrue = true }),
		}

		if kind == "action" then
			args.buttons = range("Buttons", nil, at("buttons"), 1, 12, 1)
			args.page = range("Page",
				"Bar N owns page N. Pages 7-10 are the bonus bars a druid or rogue"
				.. " gets in a form - point a bar at one and you simply see those"
				.. " abilities rather than having a bar swap under you.",
				at("page"), 1, 10, 1)
		end

		pages[id] = group(barCfg.label or ("Bar " .. id), args)
	end

	return pages
end

local function ActionBarsGroup()
	local function at(k) return { "modules", "actionbars", k } end

	local shared = {
		enabled = toggle("Enabled", nil, at("enabled")),
		hideBlizzard = toggle("Hide Blizzard's bars", nil, at("hideBlizzard")),
		scale = range("Scale (all bars)", nil, at("scale"), 0.4, 1.5, 0.05),
		size = range("Button size", "The concept draws 62px slots.", at("size"), 24, 80, 1),
		spacing = range("Spacing", nil, at("spacing"), 0, 30, 1),
		padding = range("Panel padding", nil, at("padding"), 0, 30, 1),
		fontDelta = range("Text size offset",
			"Points added to the keybind, count and cooldown text.",
			at("fontDelta"), -4, 8, 1),
		showKeybinds = toggle("Show keybinds", nil, at("showKeybinds")),
		tooltips = toggle("Tooltips", nil, at("tooltips")),
		lockButtons = toggle("Lock buttons",
			"Require a modified click to pick an action up.", at("lockButtons")),
		emptyAlpha = range("Empty slot opacity", nil, at("emptyAlpha"), 0, 1, 0.05),
	}

	local args = {
		shared = group("Shared", shared, { inline = true }),
		pagingNote = note("|cff9d7bffThere is no paging.|r Every bar names its own"
			.. " source once and never changes it. The page Blizzard tracks is a"
			.. " number this addon does not own and could not keep still, and"
			.. " following it is what made the dock empty itself."),
	}

	for id, page in pairs(BarPages()) do
		args["bar" .. id] = page
	end

	return group("Action bars", args, { childGroups = "tab" })
end

local function QuestGroup()
	local function at(k) return { "modules", "questtracker", k } end
	return group("Quest tracker", {
		enabled = toggle("Enabled", nil, at("enabled")),
		hideBlizzard = toggle("Hide Blizzard's tracker", nil, at("hideBlizzard")),
		autoTrack = toggle("Track everything automatically",
			"On, the tracker shows every quest in your log and you dismiss the ones"
			.. " you do not want. Off, it shows nothing until you shift-click a"
			.. " quest in the log.", at("autoTrack"), { defaultTrue = true }),
		combatCollapse = toggle("Fold in combat",
			"Shrinks to the heading when a fight starts. Folding it by hand"
			.. " mid-fight wins over the automatic restore.", at("combatCollapse")),
		showObjectives = toggle("Show objective lines", nil, at("showObjectives")),
		showLevel = toggle("Show quest level",
			"A tinted chip in front of each title, coloured by difficulty the same"
			.. " way the quest log colours it. Off, the titles start at the edge.",
			at("showLevel")),

		sizeHeader = header("Size"),
		width = range("Width", nil, at("width"), 180, 420, 1),
		maxHeight = range("Height budget",
			"Whatever does not fit is reported as '+N more' rather than silently"
			.. " dropped.", at("maxHeight"), 120, 900, 10),
		max = range("Most quests to show", nil, at("max"), 1, 20, 1),

		trackHeader = header("Tracking"),
		adoptWatches = toggle("Adopt Blizzard's watch list",
			"Whitelist mode only. Blizzard caps its list at five, so taking the"
			.. " entries and handing the slots back is what keeps shift-click"
			.. " working past the fifth quest.", at("adoptWatches")),
		clear = action("Reset tracking", "Forget every dismissed and tracked quest.",
			function()
				if A.db.char then
					A.db.char.tracked, A.db.char.untracked = {}, {}
				end
				local QT = A:GetModule("questtracker")
				if QT and QT.Refresh then QT:Refresh() end
			end),
	})
end

local function BagsGroup()
	local function at(k) return { "modules", "bags", k } end
	return group("Bags", {
		enabled = toggle("Enabled", nil, at("enabled")),
		desc = note("One window for the backpack and your four bags, sorted into"
			.. " categories, with the equipped bags and the keyring on a flyout"
			.. " off the right edge. At a banker the bank opens beside it. This"
			.. " replaces Blizzard's bags rather than reskinning them; turning it"
			.. " off gives them back, including the B key."),
		hideBlizzard = toggle("Hide Blizzard's bags", nil, at("hideBlizzard")),

		gridHeader = header("Grid"),
		columns = range("Columns",
			"The window is as wide as the grid: eight columns of 44 is the"
			.. " concept's 442px panel.", at("columns"), 4, 16, 1),
		slotSize = range("Slot size", nil, at("slotSize"), 24, 64, 1),
		slotGap = range("Gap between slots", nil, at("slotGap"), 0, 16, 1),
		maxHeight = range("Height budget",
			"The panel hugs its contents up to this, then the grid scrolls on"
			.. " the wheel. There is no scroll bar; the concept has none.",
			at("maxHeight"), 200, 1200, 10),

		lookHeader = header("Look"),
		showSearch = toggle("Show the search box",
			"Typing dims what does not match rather than removing it, so nothing"
			.. " moves under the cursor while you narrow it down.",
			at("showSearch"), { defaultTrue = true }),
		qualityRim = toggle("Colour slots by quality", nil, at("qualityRim"),
			{ defaultTrue = true }),
		dimJunk = toggle("Dim poor-quality items", nil, at("dimJunk"),
			{ defaultTrue = true }),
		showKeyring = toggle("Show the keyring", nil, at("showKeyring"),
			{ defaultTrue = true }),
		showEmpty = toggle("Show free slots",
			"A FREE section at the foot of the grid. Off, the panel is the"
			.. " concept's exactly - but with no empty slot on screen there is"
			.. " nowhere to drop something you are carrying.",
			at("showEmpty"), { defaultTrue = true }),

		sellHeader = header("Junk"),
		junkAutoSell = toggle("Sell junk at a merchant",
			"Sells every poor-quality item that has a value the moment you open"
			.. " any merchant, one item at a time, and tells you what it made."
			.. " Off by default: this is the only thing here that spends your"
			.. " items for you.", at("junkAutoSell")),
	})
end

local function ChatGroup()
	local function at(k) return { "modules", "chat", k } end
	return group("Chat", {
		enabled = toggle("Enabled", nil, at("enabled")),
		desc = note("Blizzard's chat frames, skinned in place. One frosted panel,"
			.. " tabs as pills along the top with the zone beside them, and the"
			.. " edit box inset into the bottom edge with a channel tag and a send"
			.. " glyph."),

		lookHeader = header("Look"),
		fontDelta = range("Text size",
			"Added to whatever size Blizzard's own chat settings say, so that"
			.. " stays the setting and this is the nudge.",
			at("fontDelta"), -4, 8, 1),
		showZone = toggle("Zone beside the tabs", nil, at("showZone"),
			{ defaultTrue = true }),
		unlocked = toggle("Movable and resizable",
			"Unlocks Blizzard's own move and resize, which is also what saves"
			.. " them - drag a tab to move it, drag the corner to resize. Locked is"
			.. " the client's default and it ignores both.",
			at("unlocked"), { defaultTrue = true }),
		resizable = toggle("Show the resize corner", nil, at("resizable"),
			{ defaultTrue = true }),
		hideButtons = toggle("Lose the buttons",
			"The scroll arrows, the resize grip and the menu buttons down the"
			.. " side. Scrolling still works on the wheel.",
			at("hideButtons"), { defaultTrue = true }),

		linesHeader = header("Message lines"),
		linesNote = note("The name is class-coloured and its realm dimmed, the"
			.. " \"says:\" becomes an em dash, and the channel gets a badge."
			.. "\n\n|cff9d7bffNone of this rewrites the author.|r Blizzard hands"
			.. " out the decorated name and builds the player link around what"
			.. " comes back, so whispers, ignore and the right-click menu are out"
			.. " of reach rather than carefully avoided."),
		styleLines = toggle("Style the lines",
			"The master switch. Everything below hangs off one filter and one set"
			.. " of format strings, and half of them on is a line that reads as"
			.. " neither Blizzard's nor ours.",
			at("styleLines"), { defaultTrue = true }),
		classColorNames = toggle("Class-colour names",
			"From the sender's GUID, which is what Blizzard's own class colouring"
			.. " uses - so it is right for two people with the same name on"
			.. " different realms.",
			at("classColorNames"), { defaultTrue = true }),
		hideRealm = toggle("Drop the realm entirely",
			"On by default: it is rare on Classic Era and never what you are"
			.. " reading a line for. Off dims it instead of losing it. Either"
			.. " way the player link still carries the full name, so whispering"
			.. " and right-clicking work on a cross-realm name you cannot see.",
			at("hideRealm"), { defaultTrue = true }),
		emDash = toggle("Em dash instead of \"says:\"",
			nil, at("emDash"), { defaultTrue = true }),
		badges = toggle("Channel badges",
			"A pill carrying the channel, in whatever colour your own chat"
			.. " settings give that channel.\n\nThe words are baked into a"
			.. " texture, so the four channels a Classic Era character actually"
			.. " joins have one and anything else gets its own name as text.",
			at("badges"), { defaultTrue = true }),
		badgeSize = range("Badge height", nil, at("badgeSize"), 8, 20, 1),
		badgeOffset = range("Badge baseline nudge",
			"The client already centres a badge on its line, so zero is normally"
			.. " right. Negative sinks it, positive raises it.\n\nOnly new lines"
			.. " take a change - a chat line is a string with the badge baked into"
			.. " it, so the log above keeps whatever it was printed with.",
			at("badgeOffset"), -8, 4, 1),
		channelPrefix = toggle("Keep Blizzard's [1. General]",
			"Off is the concept: the badge is what replaces it. Blizzard builds"
			.. " that bracket after the line is formatted, so it comes off the"
			.. " finished string rather than through a filter.",
			at("channelPrefix")),
		dimSystem = toggle("Dim system lines",
			"The concept draws these in italics. There is no italic escape"
			.. " sequence in the game's markup and a chat frame draws every line"
			.. " in one font, so dimming carries the same intent: this is not"
			.. " somebody talking.\n\nIt catches anything the game tags as a"
			.. " system line, not just the system chat event - so \"/played\","
			.. " a lost connection and most addons' own output dim too. That is"
			.. " wider than the concept drew, and it is the right reading of what"
			.. " the line is.",
			at("dimSystem"), { defaultTrue = true }),

		whisperHeader = header("Whispers"),
		whisperTab = toggle("Whispers get their own tab",
			"|cffff8a8aThis one outlives the addon.|r It opens a real Blizzard"
			.. " chat window and moves the whisper message groups onto it, and"
			.. " Blizzard saves all of that - including with AetherUI turned off."
			.. "\n\nIt is also the only answer to the concept's \"whispers stay"
			.. " bright\" while the rest dims: a chat frame has one alpha for the"
			.. " whole frame, so a different frame is the only way to give them a"
			.. " different one.",
			at("whisperTab"), { after = "none", onSet = function(value)
				local C = A:GetModule("chat")
				if not C or not C.enabled then return false end
				return C:SetWhisperTab(value and true or false)
			end }),

		behaveHeader = header("Behaviour"),
		fade = toggle("Breathes with the HUD",
			"Chat dims with everything else when you go idle, and goes altogether"
			.. " in zen. Off leaves it fully readable at all times.",
			at("fade"), { defaultTrue = true, after = "none" }),
		fadeMessages = toggle("Fade old lines out",
			"Blizzard's own message fade, which empties the log rather than"
			.. " dimming the frame. Different thing from the setting above.",
			at("fadeMessages")),
		timeVisible = range("Seconds a line stays", nil, at("timeVisible"), 10, 600, 10),
	})
end

local function XPGroup()
	local function at(k) return { "modules", "xpbar", k } end
	return group("XP hairline", {
		enabled = toggle("Enabled", nil, at("enabled")),
		height = range("Height", nil, at("height"), 1, 12, 1),
		showText = toggle("Show the readout", nil, at("showText")),
	})
end

--- Top-level page order, set explicitly rather than left to the running counter.
--
--  The counter is fine inside a page - it just needs to increase in declaration
--  order - but across pages it lands in the hundreds, which made "put profiles
--  last" a matter of guessing a bigger number. These are the numbers instead.
local PAGE_ORDER = {
	general = 1, unitframes = 2, auras = 3, actionbars = 4, minimap = 5,
	quests = 6, bags = 7, chat = 8, fader = 9, xpbar = 10,
	profiles = 99,     -- last, always
}

--- Build the whole tree. Pure: no libraries, no frames, no side effects.
function Options:Build()
	order = 0
	local tree = {
		type = "group",
		name = "Aether|cff9d7bffUI|r",
		args = {
			general = GeneralGroup(),
			unitframes = UnitFramesGroup(),
			auras = AurasGroup(),
			minimap = MinimapGroup(),
			actionbars = ActionBarsGroup(),
			quests = QuestGroup(),
			bags = BagsGroup(),
			chat = ChatGroup(),
			fader = FaderGroup(),
			xpbar = XPGroup(),
		},
	}
	for key, n in pairs(PAGE_ORDER) do
		if tree.args[key] then tree.args[key].order = n end
	end
	return tree
end

Options.PAGE_ORDER = PAGE_ORDER

-- ---------------------------------------------------------------------------
-- registration
-- ---------------------------------------------------------------------------

--- Everything here is optional. If the Ace libraries are missing the addon still
--  runs and the slash commands still work - the panel is the thing you lose, not
--  the HUD.
function Options:Register()
	if self.registered then return true end

	local Config = LibStub and LibStub("AceConfig-3.0", true)
	local Registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
	local Dialog = LibStub and LibStub("AceConfigDialog-3.0", true)
	if not (Config and Registry and Dialog) then return false end

	local tree = self:Build()

	-- Profiles come free with AceDB, and are the one part of this worth having
	-- somebody else maintain.
	local DBO = LibStub("AceDBOptions-3.0", true)
	if DBO and A.db then
		local profiles = DBO:GetOptionsTable(A.db)
		profiles.order = PAGE_ORDER.profiles
		tree.args.profiles = profiles
	end

	Config:RegisterOptionsTable(APP, tree)
	self.dialog = Dialog
	self.registry = Registry

	-- A standalone window rather than a page buried in Blizzard's settings. The
	-- Blizzard registration is attempted too, but it is the one that has been
	-- rewritten twice in recent memory, so it is not allowed to be load-bearing.
	pcall(function()
		self.blizPanel = Dialog:AddToBlizOptions(APP, "AetherUI")
	end)

	Dialog:SetDefaultSize(APP, 760, 560)
	self.registered = true
	return true
end

--- Rebuild and tell the dialog. Needed when the *shape* changes rather than a
--  value - a bar being added, say.
function Options:Refresh()
	if not self.registered then return end
	local Config = LibStub("AceConfig-3.0", true)
	if Config then Config:RegisterOptionsTable(APP, self:Build()) end
	if self.registry then pcall(self.registry.NotifyChange, self.registry, APP) end
end

function Options:Open(section)
	if not self:Register() then
		A:Print("the options panel needs the Ace3 libraries, which are missing from"
			.. " this install. |cff888888/aether help|r still lists everything.")
		return false
	end
	if section then
		self.dialog:SelectGroup(APP, section)
	end
	self.dialog:Open(APP)
	return true
end

function Options:Close()
	if self.registered and self.dialog then self.dialog:Close(APP) end
end

function Options:Toggle(section)
	if self.registered and self.dialog
		and self.dialog.OpenFrames and self.dialog.OpenFrames[APP] then
		self:Close()
	else
		self:Open(section)
	end
end
