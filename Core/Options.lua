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


local L = A.L
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
	-- A slider whose UNITS are not the stored value's. Seconds are the right
	-- thing to keep and the wrong thing to show when the useful range is
	-- minutes: a 10-to-300 slider spends nine tenths of its travel on values
	-- shorter than the idle fade, which is a control that mostly cannot be used.
	local s = info.arg and info.arg.scale
	if s and type(v) == "number" then return v / s end
	return v
end

local function Set(info, value)
	local t, k = Resolve(info.arg and info.arg.path)
	if not t then return end
	-- Back into the units the rest of the addon reads. See the note in Get.
	local s = info.arg and info.arg.scale
	if s and type(value) == "number" then value = value * s end
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
		arg = { path = path, after = opts.after, scale = opts.scale },
	}
end

local function choice(name, desc, path, values, opts)
	opts = opts or {}
	return {
		type = "select", name = name, desc = desc, order = next_(),
		values = values, width = opts.width, get = Get, set = Set,
		-- AceConfigDialog builds a Dropdown for a select unless it is told
		-- otherwise. Naming a control here is the whole of drawing one
		-- differently; everything else about the option stays put.
		dialogControl = opts.control,
		arg = { path = path, after = opts.after },
	}
end

--- `name` may be a STRING or a FUNCTION returning one.
--
--  Ace resolves a function member when the page is built
--  (AceConfigDialog-3.0.lua:187), which is what lets a button that leaves a
--  mode running name what it will do NEXT rather than what it did first. See
--  `unlock` and `bind`.
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

--- key -> WRITTEN NAME.
--
--  `s.name` was nil - Palette:List answers `label` - so every skin fell
--  through to its key and the picker read midnight/dawn/noon/dusk in
--  lower case. Harmless-looking, and it is the difference between a
--  written name and a table index.
local function SkinValues()
	local out = {}
	for _, s in ipairs(A.Palette:List()) do out[s.key] = s.label or s.key end
	return out
end

--- Built from the module's own track list rather than written out again here,
--  so dropping a file into Media\Audio and adding one line to Modules\Zen.lua is
--  the whole job. Resolved at open time: the module may not exist yet when the
--  tree is built.
local function TrackValues()
	local out = { random = "Random" }
	local Z = A:GetModule("zen")
	for _, t in ipairs((Z and Z.TRACKS) or {}) do out[t.key] = t.name end
	return out
end

local function GeneralGroup()
	return group("General", {
		-- FOUR CHIPS, NOT A DROPDOWN. Each shows its own accent on its own
		-- glass, which is the only thing that tells you what picking it
		-- would do - a list of four words does not. The option is unchanged
		-- underneath: same profile key, same setter, same restyle after.
		skin = choice("Skin", L.options.general.skin.desc,
			{ "skin" }, SkinValues,
			{ after = "restyle", control = "AetherUISkinSwatches" }),
		scale = range("Scale", L.options.general.scale.desc, { "scale" }, 0.6, 1.6, 0.01),
		classColorHealth = toggle(L.options.general.class_color_health.name,
			L.options.general.off_uses_concept_s,
			{ "classColorHealth" }, { after = "restyle" }),

		glassHeader = header("Glass"),
		shadow = range(L.options.general.shadow.name, L.options.general.shadow.desc,
			{ "glass", "shadow" }, 0, 1, 0.05, { after = "restyle" }),
		corner = range(L.options.general.corner.name, nil, { "glass", "corner" }, 4, 24, 1,
			{ after = "restyle" }),
		readOpacity = range(L.options.general.read_opacity.name,
			L.options.general.how_much_deeper_chat,
			{ "glass", "readOpacity" }, 0, 1, 0.05,
			{ after = "restyle", percent = true }),

		posHeader = header(L.options.general.pos_header),
		-- BOTH of these name what pressing them will DO, not what they did the
		-- first time. They are toggles wearing a button's clothes: each one
		-- closes this panel and leaves a mode running, so the next time anybody
		-- opens this page the mode is already on and a button still offering to
		-- turn it on is a button lying about the state of the screen.
		--
		-- Ace calls a `name` that is a function (AceConfigDialog-3.0.lua:187,
		-- via GetOptionsMemberValue), and it calls it when the page is BUILT -
		-- which is the moment that matters, because the panel is shut for the
		-- whole time the mode is on.
		bind = action(function()
				local AB = A:GetModule("actionbars")
				return (AB and AB.enabled and AB.bindMode)
					and "Leave keybind mode" or "Keybind mode"
			end,
			"Hover a button and press a key. Keys go into Blizzard's own binding"
			.. " set, so they survive this addon being disabled and show up in the"
			.. " keybinding panel.",
			function()
				local AB = A:GetModule("actionbars")
				if AB and AB.enabled then A.Options:Close(); AB:ToggleBindMode() end
			end),
		unlock = action(function()
				return A.Movers.unlocked and "Lock frames" or "Unlock frames"
			end,
			"Drag to move, scroll to nudge. Also on a tile in the Toolbox.",
			function() A.Options:Close(); A.Movers:Toggle() end),
		reset = action(L.options.general.reset.name, L.options.general.reset.desc,
			function() A.Movers:ResetAll() end),

		gridHeader = header(L.options.general.grid_header),
		gridNote = note(L.options.general.grid_note),
		grid = toggle(L.options.general.grid.name, nil, { "movers", "grid" }, { after = "grid" }),
		gridSize = range(L.options.general.grid_size.name, L.options.general.grid_size.desc,
			{ "movers", "gridSize" }, 4, 64, 2, { after = "grid" }),
		snap = toggle(L.options.general.snap.name, nil, { "movers", "snap" }, { after = "grid" }),
		snapDistance = range(L.options.general.snap_distance.name, L.options.general.snap_distance.desc,
			{ "movers", "snapDistance" }, 2, 30, 1, { after = "grid" }),
	})
end

local function OnboardGroup()
	return group(L.options.onboard.first_run, {
		desc = note("Eight stops over the real HUD, where the tour IS the setup:"
			.. " the world dims, one element at a time is lifted out of the dim,"
			.. " and the callout beside it carries that stop's control."
			.. "\n\nNothing is staged. Every choice writes straight into the"
			.. " system that owns it the moment you touch it, so there is no"
			.. " Apply at the end and quitting half way through costs nothing."
			.. "\n\nWhether it has run is remembered per "
			.. A.Hi("character") .. ", not per profile - the tour teaches an"
			.. " interface rather than a profile, and somebody who has seen it"
			.. " on their main has seen it."),
		enabled = toggle(L.options.onboard.enabled.name, nil,
			{ "modules", "onboard", "enabled" }, { defaultTrue = true }),

		runHeader = header(L.options.onboard.run_header),
		runNote = note(A.F(L.options.onboard.run_note,
			A.Hi(L.options.onboard.already_done))),
		run = action(L.common.take_tour, nil, function()
			local OB = A.GetModule and A:GetModule("onboard")
			if OB then OB:Start() end
		end),
	})
end

local function ToolboxGroup()
	return group("Toolbox", {
		desc = note("A drawer that docks to the centre of any screen edge, with a"
			.. " rail that stays on screen when the drawer is shut."
			.. "\n\nTo move it, " .. A.Hi(L.options.toolbox.unlock_frames) .. " and drag the rail: four"
			.. " targets appear, one per edge, and the one nearest the cursor is"
			.. " the one you get. It has four legal places rather than a"
			.. " position, because each edge is a different layout."
			.. "\n\nThe edge it is docked to and whether it is open are remembered"
			.. " per " .. A.Hi("character") .. " rather than per profile - a drawer edge"
			.. " is a habit somebody forms on one character."),
		enabled = toggle("Enabled", nil, { "modules", "toolbox", "enabled" },
			{ defaultTrue = true }),

		widgetsHeader = header("Widgets"),
		widgetsNote = note(A.F(L.options.toolbox.widgets_note, A.Hi(L.options.toolbox.libdatabroker_data_sources))
			.. "\n\n"
			.. L.options.toolbox.only_latency_fps_polled),
		widgetColumns = range(L.options.toolbox.widget_columns.name, nil,
			{ "modules", "toolbox", "widgetColumns" }, 1, 6, 1, { after = "reconfigure" }),

		gridHeader = header("Grids"),
		tileColumns = range(L.options.toolbox.tile_columns.name, nil,
			{ "modules", "toolbox", "tileColumns" }, 1, 4, 1, { after = "reconfigure" }),
		addonColumns = range(L.options.toolbox.addon_columns.name, nil,
			{ "modules", "toolbox", "addonColumns" }, 1, 4, 1, { after = "reconfigure" }),

		lookHeader = header(L.options.toolbox.look_header),
		lookNote = note(A.F(L.options.toolbox.look_note,
			A.Hi(L.options.toolbox.over))),
		scrim = range(L.options.toolbox.scrim.name, nil,
			{ "modules", "toolbox", "scrim" }, 0, 1, 0.02, { after = "reconfigure" }),
	})
	-- No order argument: group()'s third parameter is `opts`, and the page order
	-- is applied to the whole tree from PAGE_ORDER afterwards. Passing a number
	-- there indexes it as a table and takes Build() down with it.
end

local function FaderGroup()
	-- The client's own auto-AFK delay, from Core\Fader.lua. Read here rather than
	-- written twice so the slider and the state machine cannot drift apart.
	local ZEN_MAX = (A.Fader and A.Fader.AFK_TIMEOUT) or 300
	return group(L.options.fader.idle_fade, {
		desc = note(L.options.fader.desc),
		enabled = toggle("Enabled", nil, { "fader", "enabled" }, { after = "none" }),
		idleAlpha = range(L.options.fader.idle_alpha.name, nil, { "fader", "idleAlpha" }, 0, 1, 0.05,
			{ after = "none" }),
		activeAlpha = range(L.options.fader.active_alpha.name, nil, { "fader", "activeAlpha" }, 0.2, 1, 0.05,
			{ after = "none" }),
		delay = range(L.options.fader.delay.name, L.options.fader.delay.desc, { "fader", "delay" }, 0.5, 60, 0.5,
			{ after = "none" }),
		fadeOut = range(L.options.fader.fade_out.name, nil, { "fader", "fadeOut" }, 0, 3, 0.05,
			{ after = "none" }),
		fadeIn = range(L.options.fader.fade_in.name, nil, { "fader", "fadeIn" }, 0, 3, 0.05,
			{ after = "none" }),
		keepHeader = header(L.options.fader.keep_header),
		keepOnTarget = toggle(L.options.fader.keep_on_target.name, nil, { "fader", "keepOnTarget" },
			{ after = "none" }),
		keepOnHurt = toggle(L.options.fader.keep_on_hurt.name, nil, { "fader", "keepOnHurt" },
			{ after = "none" }),
		keepOnMouse = toggle(L.options.fader.keep_on_mouse.name, nil, { "fader", "keepOnMouse" },
			{ after = "none" }),

		zenHeader = header("Zen"),
		zenNote = note("Stage two. The whole interface goes and a single capsule"
			.. " takes its place along the bottom edge - health, power, and a slow"
			.. " breath - with the zone and the time in the corner. Anything you do"
			.. " brings it back, including a keypress, which is the one thing stage"
			.. " one cannot see."
			.. "\n\n" .. A.Hi(L.options.fader.only_hard_signals_hold) .. ": combat, casting,"
			.. " and the cursor sitting on the HUD. Having a target or being below"
			.. " full health keeps stage one awake but not this one, because"
			.. " neither is evidence that you are still in the chair."),
		zenEnabled = toggle("Enabled", nil, { "modules", "zen", "enabled" },
			{ after = "none" }),
		zenOnAFK = toggle(L.options.fader.zen_on_a_f_k.name,
			L.options.fader.client_flags_away_itself,
			{ "modules", "zen", "onAFK" }, { after = "none", defaultTrue = true }),
		zenDelay = range(L.options.fader.zen_delay.name,
			L.options.fader.minutes_least_one_so,
			{ "modules", "zen", "delay" }, 1, ZEN_MAX / 60, 0.5,
			{ after = "none", scale = 60 }),
		zenFadeOut = range(L.options.fader.zen_fade_out.name, nil, { "modules", "zen", "fadeOut" },
			0.2, 6, 0.1, { after = "none" }),
		zenFadeIn = range(L.options.fader.zen_fade_in.name, nil, { "modules", "zen", "fadeIn" },
			0.05, 2, 0.05, { after = "none" }),
		zenKeys = toggle(L.options.fader.zen_keys.name,
			L.options.fader.adds_frame_listens_keys,
			{ "modules", "zen", "keyboardWake" }, { after = "none", defaultTrue = true }),

		zenLookHeader = header(L.options.fader.zen_look_header),
		zenDimUI = toggle(L.options.fader.zen_dim_u_i.name,
			L.options.fader.fades_uiparent_which_everything,
			{ "modules", "zen", "dimUI" }, { after = "none", defaultTrue = true }),
		zenMapArt = toggle(L.options.fader.zen_map_art.name,
			L.options.fader.corner_block_shows_circle,
			{ "modules", "zen", "showMapArt" }, { defaultTrue = true }),
		zenGlyph = range(L.options.fader.zen_glyph.name, nil, { "modules", "zen", "glyphSize" },
			10, 48, 1),
		zenKeepMap = toggle(L.options.fader.zen_keep_map.name,
			L.options.fader.map_survives_zen_zone,
			{ "modules", "zen", "keepMinimap" }),
		zenWidth = range(L.options.fader.zen_width.name, nil, { "modules", "zen", "width" },
			160, 600, 5),
		zenY = range(L.options.fader.zen_y.name, nil, { "modules", "zen", "yOffset" },
			0, 200, 2),
		zenCaption = toggle(L.options.fader.zen_caption.name, nil, { "modules", "zen", "showCaption" },
			{ defaultTrue = true }),
		zenDots = toggle(L.options.fader.zen_dots.name,
			L.options.fader.row_dots_they_carry,
			{ "modules", "zen", "showDots" }, { defaultTrue = true }),
		zenPill = toggle(L.options.fader.zen_pill.name, nil, { "modules", "zen", "showPill" },
			{ defaultTrue = true }),

		zenFrostHeader = header(L.options.fader.zen_frost_header),
		zenFrostNote = note("A pane of frosted glass drawn in front of the world"
			.. " while zen is on."
			.. "\n\n" .. A.Hi(L.options.fader.blur_cannot) .. ". The client gives"
			.. " addons no way to read or filter the 3D scene - no render-to-texture,"
			.. " no shader, no post-process hook - so the world behind stays sharp."
			.. " What frosted glass actually is, though, is a surface in front of a"
			.. " sharp scene."
			.. "\n\nIt gets " .. A.Hi("brighter") .. ", not darker. Frosted glass scatters"
			.. " light, so it is brighter than what is behind it and what it destroys"
			.. " is contrast. A dark pane leaves every edge in the scene perfectly"
			.. " crisp and simply turns the lights off."),
		zenFrost = toggle("Enabled", nil, { "modules", "zen", "frost" },
			{ after = "none", defaultTrue = true }),
		zenFrostOpacity = range(L.options.fader.zen_frost_opacity.name,
			L.options.fader.how_much_world_glass,
			{ "modules", "zen", "frostOpacity" }, 0, 0.95, 0.05,
			{ after = "restyle", percent = true }),
		zenFrostBrightness = range(L.options.fader.zen_frost_brightness.name,
			L.options.fader.how_far_skin_s,
			{ "modules", "zen", "frostBrightness" }, 0, 1, 0.05,
			{ after = "restyle", percent = true }),
		zenFrostScatter = range("Scatter",
			L.options.fader.layer_doing_actual_work,
			{ "modules", "zen", "frostScatter" }, 0, 1, 0.05,
			{ after = "restyle", percent = true }),
		zenFrostVignette = range("Vignette",
			L.options.fader.darker_toward_edges_so,
			{ "modules", "zen", "frostVignette" }, 0, 1, 0.05,
			{ after = "restyle", percent = true }),
		zenFrostDrift = range("Drift",
			L.options.fader.screens_per_second_two,
			{ "modules", "zen", "frostDrift" }, 0, 0.1, 0.005,
			{ after = "none" }),

		zenQuietHeader = header("Distractions"),
		zenNameplates = toggle(L.options.fader.zen_nameplates.name,
			"The one thing fading the interface does not reach: nameplates and the"
			.. " floating unit names are drawn against the world rather than"
			.. " composited into the interface, so they are left hanging over an"
			.. " empty hillside otherwise."
			.. "\n\nThese are " .. A.Hi(L.options.fader.two_separate_systems) .. " in the client - the"
			.. " bars and the text have unrelated settings - so this drives both."
			.. " Taking the bars away and leaving every name, guild tag and pet"
			.. " label floating looks like a fault rather than a choice. Everything"
			.. " is turned off at the bottom of the fade and turned back on the"
			.. " moment you come out, including on the way to a logout."
			.. "\n\nTooltips need nothing: they belong to the interface and go with"
			.. " it.",
			{ "modules", "zen", "hideNameplates" },
			{ after = "none", defaultTrue = true }),

		zenShotHeader = header(L.options.fader.zen_shot_header),
		zenShotNote = note("Zen sets up a camera rather than just clearing the"
			.. " screen: the character settles, and the view pulls back over their"
			.. " shoulder."
			.. "\n\nThe zoom is exact and exactly reversible - the game will tell us"
			.. " the current distance, so yours is put back rather than guessed at."
			.. " " .. A.Hi(L.options.fader.tilt) .. ": the client offers no way to read the"
			.. " camera's pitch, only to move it, so the way back is the same"
			.. " movement reversed for the same time."),
		zenSit = toggle(L.options.fader.zen_sit.name,
			L.options.fader.skipped_while_mounted_taxi,
			{ "modules", "zen", "sit" }, { after = "none", defaultTrue = true }),
		zenCamera = toggle(L.options.fader.zen_camera.name, nil, { "modules", "zen", "camera" },
			{ after = "none", defaultTrue = true }),
		zenCameraZoom = range(L.options.fader.zen_camera_zoom.name,
			L.options.fader.roughly_metres_camera_glides,
			{ "modules", "zen", "cameraZoom" }, 0, 15, 0.5, { after = "none" }),


		zenAudioHeader = header(L.options.fader.zen_audio_header),
		zenAudioNote = note("Zen borrows the sound channels while it is on screen"
			.. " and gives them back when it ends."
			.. "\n\nThe three sliders below are " .. A.Hi(L.options.fader.fractions_own_settings)
			.. ", not volumes. 5% of an effects channel you keep at 80%"
			.. " is 4%; at 20% it is 1%. Your master volume is never touched, and a"
			.. " channel you change by hand during zen is left where you put it"
			.. " rather than being handed a stale value back."),
		zenAudio = toggle("Enabled", L.options.fader.zen_audio.desc,
			{ "modules", "zen", "audio" }, { after = "none", defaultTrue = true }),
		zenTrack = choice("Track", L.options.fader.zen_track.desc,
			{ "modules", "zen", "track" }, TrackValues, { after = "none" }),
		zenPreview = action(L.options.fader.zen_preview.name,
			L.options.fader.plays_now_so_can,
			function()
				local Z = A:GetModule("zen")
				if not Z then return end
				local name = Z:PreviewTrack(A.db.profile.modules.zen.track)
				if name then A:Print(A.F(L.options.fader.playing_s, A.Val(name))) end
			end),
		zenMusicFloor = range(L.options.fader.zen_music_floor.name,
			L.options.fader.one_channel_zen_raises,
			{ "modules", "zen", "musicFloor" }, 0, 1, 0.05,
			{ after = "none", percent = true }),
		zenDuckSFX = range(L.options.fader.zen_duck_s_f_x.name,
			nil, { "modules", "zen", "duckSFX" }, 0, 1, 0.01,
			{ after = "none", percent = true }),
		zenDuckAmbience = range(L.options.fader.zen_duck_ambience.name,
			L.options.fader.kept_higher_than_others,
			{ "modules", "zen", "duckAmbience" }, 0, 1, 0.01,
			{ after = "none", percent = true }),
		zenDuckDialog = range(L.options.fader.zen_duck_dialog.name,
			nil, { "modules", "zen", "duckDialog" }, 0, 1, 0.01,
			{ after = "none", percent = true }),
	})
end

local function UnitFramesGroup()
	local m = { "modules", "unitframes" }
	local function at(k) return { "modules", "unitframes", k } end
	return group(L.options.unit_frames.unit_frames, {
		enabled = toggle("Enabled", nil, at("enabled")),
		hideBlizzard = toggle(L.options.unit_frames.hide_blizzard.name, nil, at("hideBlizzard")),
		clickTarget = toggle(L.common.click_target,
			L.common.left_click_targets_right, at("clickTarget")),

		sizeHeader = header("Capsule"),
		width = range("Width", nil, at("width"), 240, 520, 1),
		height = range("Height", nil, at("height"), 48, 96, 1),
		gap = range(L.options.unit_frames.gap.name, nil, at("gap"), 0, 200, 1),
		orbSize = range(L.options.unit_frames.orb_size.name, nil, at("orbSize"), 28, 72, 1),
		barWidth = range(L.common.bar_width, nil, at("barWidth"), 120, 380, 1),
		showPower = toggle(L.common.show_power_bar, nil, at("showPower")),
		showPortrait = toggle(L.options.unit_frames.show_portrait.name,
			L.options.unit_frames.off_draws_class_tinted,
			at("showPortrait")),

		castHeader = header(L.options.unit_frames.cast_header),
		showPet = toggle(L.options.unit_frames.show_pet.name,
			L.options.unit_frames.capsule_pet_own_place, at("showPet")),
		petScale = range(L.options.unit_frames.pet_scale.name, L.options.unit_frames.pet_scale.desc,
			at("petScale"), 0.6, 1.2, 0.05, { after = "both" }),

		showCastBar = toggle(L.options.unit_frames.show_cast_bar.name, nil, at("showCastBar")),
		showTargetCastBar = toggle(L.options.unit_frames.show_target_cast_bar.name,
			L.options.unit_frames.classic_era_does_report,
			at("showTargetCastBar")),
		castNote = note(A.F(L.options.unit_frames.cast_note, A.Hi("/aether unlock"))),
		castWidth = range(L.options.unit_frames.cast_width.name, nil, at("castWidth"), 160, 520, 1),
		reactionTint = toggle(L.options.unit_frames.reaction_tint.name,
			L.options.unit_frames.target_s_capsule_rim,
			at("reactionTint"), { defaultTrue = true, after = "restyle" }),
	})
end

local function AurasGroup()
	local function at(...) return { "modules", "auras", ... } end
	return group("Auras", {
		enabled = toggle("Enabled", nil, at("enabled")),
		hideBlizzard = toggle(L.options.auras.hide_blizzard.name,
			L.options.auras.takes_weapon_enchant_icons,
			at("hideBlizzard"), { defaultTrue = true }),

		desc = note(L.options.auras.desc),

		tileHeader = header("Tiles"),
		tileNote = note(L.options.auras.tile_note),
		size = range(L.options.auras.size.name, nil, at("size"), 12, 48, 1),
		spacing = range("Spacing", nil, at("spacing"), 0, 16, 1),
		offset = range(L.options.auras.offset.name, nil, at("offset"), 0, 40, 1),
		showTime = toggle(L.options.auras.show_time.name, nil, at("showTime"), { defaultTrue = true }),
		showCount = toggle(L.options.auras.show_count.name, nil, at("showCount"), { defaultTrue = true }),
		align = choice(L.options.auras.align.name,
			L.options.auras.centred_splits_slack_row,
			at("align"), { CENTER = "Centred", MIRROR = "Mirrored" }),
		perRow = range(L.options.auras.per_row.name,
			L.options.auras.n0_fits_many_frame,
			at("perRow"), 0, 16, 1),

		buffs = group("Buffs", {
			enabled = toggle("Enabled", nil, at("buffs", "enabled")),
			player = toggle(L.common.player, nil, at("buffs", "player")),
			target = toggle(L.common.target, nil, at("buffs", "target")),
			max = range(L.common.most_show, nil, at("buffs", "max"), 1, 40, 1),
			maxRows = range(L.common.rows_most, nil, at("buffs", "maxRows"), 1, 4, 1),
		}, { inline = true }),

		debuffs = group("Debuffs", {
			enabled = toggle("Enabled", nil, at("debuffs", "enabled")),
			player = toggle(L.common.player, nil, at("debuffs", "player")),
			target = toggle(L.common.target, nil, at("debuffs", "target")),
			onlyMine = toggle(L.options.auras.only_mine.name,
				L.options.auras.yourself_every_debuff_matters,
				at("debuffs", "onlyMine")),
			max = range(L.common.most_show, nil, at("debuffs", "max"), 1, 40, 1),
			maxRows = range(L.common.rows_most, nil, at("debuffs", "maxRows"), 1, 4, 1),
		}, { inline = true }),
	})
end

local function MinimapGroup()
	local function at(...) return { "modules", "minimap", ... } end
	return group("Minimap", {
		enabled = toggle("Enabled", nil, at("enabled")),
		desc = note(A.F(L.options.minimap.desc,
			A.Bad(L.options.minimap.combat))),
		size = range("Size", nil, at("size"), 120, 320, 1),
		ring = toggle("Border", nil, at("ring"), { defaultTrue = true }),
		showNorth = toggle(L.options.minimap.show_north.name, nil, at("showNorth"), { defaultTrue = true }),
		pillOffset = range(L.options.minimap.pill_offset.name, nil, at("pillOffset"), 0, 40, 1),
		border = range(L.options.minimap.border.name,
			L.options.minimap.dark_band_around_inside,
			at("border"), 0, 1, 0.05),

		pillHeader = header(L.options.minimap.pill_header),
		showZone = toggle(L.options.minimap.show_zone.name, nil, at("showZone"), { defaultTrue = true }),
		showCoords = toggle("Coordinates",
			L.options.minimap.unavailable_inside_instance_where,
			at("showCoords"), { defaultTrue = true }),
		showClock = toggle("Clock", nil, at("showClock"), { defaultTrue = true }),
		blizzHeader = header(L.options.minimap.blizz_header),
		hideBlizzard = toggle(L.options.minimap.hide_blizzard.name,
			"Zoom, tracking, the day/night dial, the battleground eye, the border"
			.. " art and the toggle tab. Zoom moves to the mouse wheel and tracking"
			.. " to right-clicking the map, so nothing is actually lost.",
			at("hideBlizzard"), { defaultTrue = true }),

		-- The button drawer's three controls used to live here. The drawer went
		-- when addon buttons moved to the Toolbox rail - see the note at the top
		-- of Modules/Minimap.lua - and the switches outlived it: two of them
		-- wrote keys nothing has read since, and the third sized a gap in a thing
		-- that is not drawn.
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
			rows = range("Rows", L.options.bar_pages.rows.desc, at("rows"), 1, 12, 1),
			scale = range("Scale", L.common.top_global_scale, at("scale"), 0.4, 2.0, 0.05),
			backdrop = toggle(L.options.bar_pages.backdrop.name, L.options.bar_pages.backdrop.desc,
				at("backdrop"), { defaultTrue = true }),
		}

		if kind == "action" then
			args.buttons = range("Buttons", nil, at("buttons"), 1, 12, 1)
			args.page = range("Page",
				L.options.bar_pages.bar_n_owns_page,
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
		hideBlizzard = toggle(L.options.action_bars.hide_blizzard.name, nil, at("hideBlizzard")),
		scale = range(L.options.action_bars.scale.name, nil, at("scale"), 0.4, 1.5, 0.05),
		size = range(L.options.action_bars.size.name, L.options.action_bars.size.desc, at("size"), 24, 80, 1),
		spacing = range("Spacing", nil, at("spacing"), 0, 30, 1),
		padding = range(L.options.action_bars.padding.name, nil, at("padding"), 0, 30, 1),
		fontDelta = range(L.options.action_bars.font_delta.name,
			L.options.action_bars.points_added_keybind_count,
			at("fontDelta"), -4, 8, 1),
		showKeybinds = toggle(L.options.action_bars.show_keybinds.name, nil, at("showKeybinds")),
		tooltips = toggle("Tooltips", nil, at("tooltips")),
		lockButtons = toggle(L.options.action_bars.lock_buttons.name,
			L.options.action_bars.require_modified_click_pick, at("lockButtons")),
		emptyAlpha = range(L.options.action_bars.empty_alpha.name, nil, at("emptyAlpha"), 0, 1, 0.05),
	}

	local args = {
		shared = group("Shared", shared, { inline = true }),
		pagingNote = note(A.Hi(L.options.action_bars.paging_note) .. " Every bar names its own"
			.. " source once and never changes it. The page Blizzard tracks is a"
			.. " number this addon does not own and could not keep still, and"
			.. " following it is what made the dock empty itself."),
	}

	for id, page in pairs(BarPages()) do
		args["bar" .. id] = page
	end

	return group(L.options.action_bars.action_bars, args, { childGroups = "tab" })
end

local function QuestGroup()
	local function at(k) return { "modules", "questtracker", k } end
	return group(L.options.quest.quest_tracker, {
		enabled = toggle("Enabled", nil, at("enabled")),
		hideBlizzard = toggle(L.options.quest.hide_blizzard.name, nil, at("hideBlizzard")),
		-- The LOG, which is a different module and a different window, but
		-- the same subject - and it had no control anywhere at all, which
		-- made it a feature nobody could switch off.
		questlog = toggle(L.options.quest.questlog.name,
			L.options.quest.replaces_game_s_own,
			{ "modules", "questlog", "enabled" }),
		autoTrack = toggle(L.options.quest.auto_track.name,
			L.options.quest.tracker_shows_every_quest, at("autoTrack"), { defaultTrue = true }),
		combatCollapse = toggle(L.options.quest.combat_collapse.name,
			L.options.quest.shrinks_heading_when_fight, at("combatCollapse")),
		showObjectives = toggle(L.options.quest.show_objectives.name, nil, at("showObjectives")),
		showLevel = toggle(L.options.quest.show_level.name,
			L.options.quest.tinted_chip_front_each,
			at("showLevel")),

		sizeHeader = header("Size"),
		width = range("Width", nil, at("width"), 180, 420, 1),
		maxHeight = range(L.common.height_budget,
			L.options.quest.whatever_does_fit_reported, at("maxHeight"), 120, 900, 10),
		max = range(L.options.quest.max.name, nil, at("max"), 1, 20, 1),

		trackHeader = header("Tracking"),
		adoptWatches = toggle(L.options.quest.adopt_watches.name,
			L.options.quest.whitelist_mode_only_blizzard, at("adoptWatches")),
		clear = action(L.options.quest.clear.name, L.options.quest.clear.desc,
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
		desc = note(L.options.bags.desc),
		hideBlizzard = toggle(L.options.bags.hide_blizzard.name, nil, at("hideBlizzard")),

		gridHeader = header("Grid"),
		columns = range("Columns",
			L.options.bags.window_wide_grid_eight, at("columns"), 4, 16, 1),
		slotSize = range(L.options.bags.slot_size.name, nil, at("slotSize"), 24, 64, 1),
		slotGap = range(L.options.bags.slot_gap.name, nil, at("slotGap"), 0, 16, 1),
		maxHeight = range(L.common.height_budget,
			L.options.bags.panel_hugs_contents_up,
			at("maxHeight"), 200, 1200, 10),

		lookHeader = header("Look"),
		showSearch = toggle(L.options.bags.show_search.name,
			L.options.bags.typing_dims_what_does,
			at("showSearch"), { defaultTrue = true }),
		qualityRim = toggle(L.options.bags.quality_rim.name, nil, at("qualityRim"),
			{ defaultTrue = true }),
		dimJunk = toggle(L.options.bags.dim_junk.name, nil, at("dimJunk"),
			{ defaultTrue = true }),
		showFlyout = toggle(L.options.bags.show_flyout.name,
			L.options.bags.drawer_off_right_edge,
			at("showFlyout"), { defaultTrue = true }),
		showKeyring = toggle(L.options.bags.show_keyring.name, nil, at("showKeyring"),
			{ defaultTrue = true }),
		showEmpty = toggle(L.options.bags.show_empty.name,
			L.options.bags.free_section_foot_grid,
			at("showEmpty"), { defaultTrue = true }),

		sellHeader = header("Junk"),
		junkAutoSell = toggle(L.options.bags.junk_auto_sell.name,
			L.options.bags.sells_every_poor_quality, at("junkAutoSell")),
	})
end

local function ChatGroup()
	local function at(k) return { "modules", "chat", k } end
	return group("Chat", {
		enabled = toggle("Enabled", nil, at("enabled")),
		desc = note(L.options.chat.desc),

		lookHeader = header("Look"),
		fontDelta = range(L.options.chat.font_delta.name,
			L.options.chat.added_whatever_size_blizzard,
			at("fontDelta"), -4, 8, 1),
		showZone = toggle(L.options.chat.show_zone.name, nil, at("showZone"),
			{ defaultTrue = true }),
		unlocked = toggle(L.options.chat.unlocked.name,
			L.options.chat.unlocks_blizzard_s_own,
			at("unlocked"), { defaultTrue = true }),
		resizable = toggle(L.options.chat.resizable.name, nil, at("resizable"),
			{ defaultTrue = true }),
		hideButtons = toggle(L.options.chat.hide_buttons.name,
			L.options.chat.scroll_arrows_resize_grip,
			at("hideButtons"), { defaultTrue = true }),

		linesHeader = header(L.options.chat.lines_header),
		linesNote = note("The name is class-coloured and its realm dimmed, the"
			.. " \"says:\" becomes an em dash, and the channel gets a badge."
			.. "\n\n" .. A.Hi(L.options.chat.none_rewrites_author) .. " Blizzard hands"
			.. " out the decorated name and builds the player link around what"
			.. " comes back, so whispers, ignore and the right-click menu are out"
			.. " of reach rather than carefully avoided."),
		styleLines = toggle(L.options.chat.style_lines.name,
			L.options.chat.master_switch_everything_below,
			at("styleLines"), { defaultTrue = true }),
		classColorNames = toggle(L.options.chat.class_color_names.name,
			L.options.chat.sender_s_guid_which,
			at("classColorNames"), { defaultTrue = true }),
		hideRealm = toggle(L.options.chat.hide_realm.name,
			L.options.chat.default_rare_classic_era,
			at("hideRealm"), { defaultTrue = true }),
		emDash = toggle(L.options.chat.em_dash.name,
			nil, at("emDash"), { defaultTrue = true }),
		badges = toggle(L.options.chat.badges.name,
			"A pill carrying the channel, in whatever colour your own chat"
			.. " settings give that channel.\n\nThe words are baked into a"
			.. " texture, so the four channels a Classic Era character actually"
			.. " joins have one and anything else gets its own name as text.",
			at("badges"), { defaultTrue = true }),
		badgeSize = range(L.options.chat.badge_size.name, nil, at("badgeSize"), 8, 20, 1),
		badgeOffset = range(L.options.chat.badge_offset.name,
			"The client already centres a badge on its line, so zero is normally"
			.. " right. Negative sinks it, positive raises it.\n\nOnly new lines"
			.. " take a change - a chat line is a string with the badge baked into"
			.. " it, so the log above keeps whatever it was printed with.",
			at("badgeOffset"), -8, 4, 1),
		channelPrefix = toggle(L.options.chat.channel_prefix.name,
			L.options.chat.off_concept_badge_what,
			at("channelPrefix")),
		dimSystem = toggle(L.options.chat.dim_system.name,
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
		whisperTab = toggle(L.options.chat.whisper_tab.name,
			A.Bad(L.options.chat.one_outlives_addon) .. " It opens a real Blizzard"
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
		fade = toggle(L.options.chat.fade.name,
			L.options.chat.chat_dims_everything_else,
			at("fade"), { defaultTrue = true, after = "none" }),
		fadeMessages = toggle(L.options.chat.fade_messages.name,
			L.options.chat.blizzard_s_own_message,
			at("fadeMessages")),
		timeVisible = range(L.options.chat.time_visible.name, nil, at("timeVisible"), 10, 600, 10),
	})
end

--- Two small things the game makes you wait for.
local function ConveniencesGroup()
	local function at(k) return { "modules", "conveniences", k } end
	return group("Conveniences", {
		enabled = toggle("Enabled", nil, at("enabled")),

		instantQuestText = toggle(L.options.conveniences.instant_quest_text.name,
			"Quest text appears at once instead of being typed out."
			.. "\n\nThis is the game's OWN setting - Interface, Controls, Instant"
			.. " Quest Text - set for you. Off puts it back the way you had it,"
			.. " which is why it is off here to begin with: you may have chosen the"
			.. " typing on purpose.",
			at("instantQuestText"), { after = "reconfigure" }),

		autoRepair = toggle(L.options.conveniences.auto_repair.name,
			"Repairs everything the moment you open a merchant who can."
			.. "\n\nOFF by default, because it SPENDS YOUR MONEY. It will not"
			.. " repair when you cannot afford it - it tells you instead, rather"
			.. " than half-repairing - and every repair prints what it cost, so"
			.. " nothing leaves your purse quietly.",
			at("autoRepair")),
	})
end

--- WHAT THE GAME DRAWS, redressed.
--
--  Five switches that were five pages, each holding one checkbox and nothing
--  else. A page per module is the right shape while a module has settings; for
--  the ones that only answer yes or no it puts five clicks between the player
--  and five related decisions, and pads the list they scan to find anything
--  else.
--
--  They belong together anyway: every one is the same promise in a different
--  place - the game's own thing, in this interface's clothes, and switching it
--  off gives Blizzard's back whole.
local function GameOwnGroup()
	local function at(m) return { "modules", m, "enabled" } end
	return group(L.options.game_own.game_s_own, {
		note = note(L.options.game_own.note),

		lettering = toggle("Lettering", "The game's own type in this interface's letters"
			.. " - every panel, every tooltip, every menu, and \"You can't do that yet\"."
			.. "\n\nA change of FACE only: sizes stay as the game had them, so nothing"
			.. " moves; outlines stay, because text drawn over the world needs them;"
			.. " and colours stay, because a colour is the game telling you something."
			.. "\n\nOTHER ADDONS COME WITH IT. Anything drawn with the game's own type"
			.. " reads as part of the same interface without its author doing anything."
			.. " One that chose its own lettering keeps it.",
			at("fonts")),

		windows = toggle("Windows", L.options.game_own.windows.desc,
			at("panels")),

		dialogs = toggle("Dialogs", L.options.game_own.dialogs.desc, at("popups")),

		menus = toggle("Menus", L.options.game_own.menus.desc, at("menus")),

		timers = toggle("Timers", L.options.game_own.timers.desc,
			at("timers")),

		settings = toggle(L.options.game_own.settings.name, L.options.game_own.settings.desc, at("optionsskin")),
	})
end

local function XPGroup()
	local function at(k) return { "modules", "xpbar", k } end
	return group(L.options.x_p.xp_hairline, {
		enabled = toggle("Enabled", nil, at("enabled")),
		height = range("Height", nil, at("height"), 1, 12, 1),
		showText = toggle(L.options.x_p.show_text.name, nil, at("showText")),
		textSide = choice(L.options.x_p.text_side.name,
			L.options.x_p.which_end_hairline_readout, at("textSide"),
			{ LEFT = "Left", RIGHT = "Right" }),
	})
end

--- The in-flight console. The dormancy readout the design describes is still to
--  come; these are the switches that exist because somebody asked for them.
--
--  `player` is also the Toolbox's I.F.E.C. tile - one flag, two places to press
--  it, which is the rule every mode in this addon follows.
local function IFECGroup()
	local function at(k) return { "modules", "ifec", k } end
	return group(L.options.i_f_e_c.flight_console, {
		enabled = toggle("Enabled", L.options.i_f_e_c.enabled.desc, at("enabled")),
		player = toggle(L.options.i_f_e_c.player.name,
			L.options.i_f_e_c.music_stories_while_passenger,
			at("player")),
		playOn = toggle(L.options.i_f_e_c.play_on.name,
			L.options.i_f_e_c.programme_carries_into_toolbox, at("playOn")),
		readerScale = range(L.options.i_f_e_c.reader_scale.name, L.options.i_f_e_c.reader_scale.desc, at("readerScale"), 0.4, 1, 0.05,
			{ after = "both" }),
		hideUI = toggle(L.options.i_f_e_c.hide_u_i.name,
			L.options.i_f_e_c.passenger_console_stays, at("hideUI")),
		scale = range("Size", L.options.i_f_e_c.scale.desc, at("scale"), 0.5, 1.5, 0.05, { after = "both" }),
		note = note(A.F(L.options.i_f_e_c.note, A.Hi("/aether unlock"))),
	})
end

--- Nameplates. Grouped by what you are looking at rather than by data type: the
--  capsule that hostiles wear, the plain text a friendly gets instead, and the
--  two things that hang under whichever of them is your target.
local function NameplatesGroup()
	local function at(k) return { "modules", "nameplates", k } end
	return group("Nameplates", {
		enabled = toggle("Enabled", L.options.nameplates.enabled.desc,
			at("enabled")),
		scale = range("Size", L.options.nameplates.scale.desc, at("scale"), 0.6, 1.6, 0.05,
			{ after = "reconfigure" }),
		alwaysShow = toggle(L.options.nameplates.always_show.name, L.options.nameplates.always_show.desc,
			at("alwaysShow"), { after = "reconfigure" }),
		maxDistance = range("Range", L.options.nameplates.max_distance.desc,
			at("maxDistance"), 20, 41, 1, { after = "reconfigure" }),
		hideBlizzard = toggle(L.options.nameplates.hide_blizzard.name, L.options.nameplates.hide_blizzard.desc,
			at("hideBlizzard"), { after = "reconfigure" }),

		capsule = header(L.options.nameplates.capsule),
		badgeSize = range(L.options.nameplates.badge_size.name, nil, at("badgeSize"), 18, 40, 1,
			{ after = "reconfigure" }),
		barWidth = range(L.options.nameplates.bar_width.name, nil, at("barWidth"), 80, 260, 5,
			{ after = "reconfigure" }),
		barHeight = range(L.options.nameplates.bar_height.name, nil, at("barHeight"), 2, 12, 1,
			{ after = "reconfigure" }),
		neutralBarInCombat = toggle(L.options.nameplates.neutral_bar_in_combat.name,
			L.options.nameplates.yellow_plate_means_my, at("neutralBarInCombat"), { after = "reconfigure" }),

		friendly = header("Friendlies"),
		friendlyNames = toggle(L.options.nameplates.friendly_names.name,
			L.options.nameplates.plain_shadowed_text_rather,
			at("friendlyNames"), { after = "reconfigure" }),
		partyClassColors = toggle(L.options.nameplates.party_class_colors.name,
			L.options.nameplates.off_friendly_player_s,
			at("partyClassColors"), { after = "reconfigure" }),
	})
end

--- Top-level page order, set explicitly rather than left to the running counter.
--
--  The counter is fine inside a page - it just needs to increase in declaration
--  order - but across pages it lands in the hundreds, which made "put profiles
--  last" a matter of guessing a bigger number. These are the numbers instead.
--- Tooltips. Grouped by what a switch actually does rather than by which part of
--  the card it touches, because the honest division here is "styling" versus
--  "changes the words" - and the second group is the one somebody debugging an
--  interaction with MobInfo2 or Pawn will want to reach first.
local function TooltipsGroup()
	local function at(k) return { "modules", "tooltips", k } end
	return group("Tooltips", {
		enabled = toggle("Enabled", nil, at("enabled")),
		scale = range("Size", L.common.top_global_scale, at("scale"), 0.6, 1.6, 0.05,
			{ after = "reconfigure" }),
		corner = range(L.options.tooltips.corner.name, nil, at("corner"), 4, 24, 1, { after = "reconfigure" }),
		restyleFonts = toggle(L.options.tooltips.restyle_fonts.name, L.options.tooltips.restyle_fonts.desc, at("restyleFonts"), { after = "reconfigure" }),

		anchoring = group("Anchoring", {
			unitAnchor = toggle(L.options.tooltips.unit_anchor.name, L.options.tooltips.unit_anchor.desc,
				at("unitAnchor")),
			cursorItems = toggle(L.options.tooltips.cursor_items.name,
				L.options.tooltips.only_where_nothing_else, at("cursorItems")),
		}, { inline = true }),

		content = group(L.options.tooltips.content, {
			-- Named, not positional. An AceConfig args table is keyed by STRING;
			-- a bare note() lands in the array part and the registry rejects the
			-- whole tree, taking every page down with it.
			caution = note(A.Hi(L.options.tooltips.caution) .. ", not just its"
				.. " colour. Everything else on this page is styling. If a tooltip"
				.. " ever reads oddly alongside MobInfo2 or another mob addon,"
				.. " this is the group to turn off first."),
			levelBadge = toggle(L.options.tooltips.level_badge.name, L.options.tooltips.level_badge.desc, at("levelBadge")),
			deferToLevelReaders = toggle(L.options.tooltips.defer_to_level_readers.name,
				"MobInfo2 finds a mob's extra info by looking for the level NUMBER in"
				.. " the tooltip line. Move it into the badge and it finds nothing."
				.. " Leave this on and the badge stands down while MobInfo2 is"
				.. " running; /aether tooltips will tell you it has.",
				at("deferToLevelReaders"), { defaultTrue = true }),
			eliteChip = toggle(L.options.tooltips.elite_chip.name, nil, at("eliteChip")),
			reactionWord = toggle(L.options.tooltips.reaction_word.name, L.options.tooltips.reaction_word.desc, at("reactionWord")),
			healthValues = toggle(L.options.tooltips.health_values.name, nil, at("healthValues")),
		}, { inline = true }),

		colour = group("Colour", {
			qualityBorder = toggle(L.options.tooltips.quality_border.name, nil, at("qualityBorder")),
			loreGold = toggle(L.options.tooltips.lore_gold.name, L.options.tooltips.lore_gold.desc,
				at("loreGold")),
			classColorNames = toggle(L.options.tooltips.class_color_names.name, L.options.tooltips.class_color_names.desc,
				at("classColorNames"), { defaultTrue = true }),
		}, { inline = true }),
	})
end

local function PartyFramesGroup()
	local function at(k) return { "modules", "partyframes", k } end
	return group(L.options.party_frames.party_frames, {
		enabled = toggle("Enabled",
			L.options.party_frames.four_capsules_party_same, at("enabled"), { defaultTrue = true }),
		hideBlizzard = toggle(L.options.party_frames.hide_blizzard.name, nil,
			at("hideBlizzard")),
		clickTarget = toggle(L.common.click_target,
			L.common.left_click_targets_right, at("clickTarget")),

		sizeHeader = header("Capsule"),
		width = range("Width", nil, at("width"), 240, 460, 1),
		height = range("Height", nil, at("height"), 40, 80, 1),
		gap = range(L.options.party_frames.gap.name, nil, at("gap"), 0, 40, 1),
		barWidth = range(L.common.bar_width, nil, at("barWidth"), 100, 300, 1),
		showPower = toggle(L.common.show_power_bar, nil, at("showPower")),

		placement = note(A.F(L.options.party_frames.placement,
			A.Hi("/aether unlock"))
			.. "\n\n"
			.. L.options.party_frames.slot_whose_member_has),
	})
end
--- Threat. Three controls and no thresholds: the 70 and the 90 are the
--  handoff's and are deliberately not a setting - a player who moves them is a
--  player whose ring means something different from everybody else's.
local function ThreatGroup()
	local function at(k) return { "modules", "threat", k } end
	return group("Threat", {
		enabled = toggle("Enabled", L.options.threat.enabled.desc, at("enabled")),
		display = choice("Show", L.options.threat.display.desc, at("display"), {
				full  = "Rings and warnings",
				rings = "Rings only",
				off   = "Nothing",
			}),
		alarms = toggle(L.options.threat.alarms.name, L.options.threat.alarms.desc,
			at("alarms")),

		role = choice(L.options.threat.role.name, L.options.threat.role.desc,
			at("role"), {
				auto   = "Automatic",
				tank   = "Tank",
				damage = "Damage or healing",
			}),
	})
end
local PAGE_ORDER = {
	general = 1, unitframes = 2, partyframes = 3, auras = 4, actionbars = 5,
	minimap = 6, quests = 7, bags = 8, chat = 9, tooltips = 10,
	toolbox = 11, fader = 12, xpbar = 13, nameplates = 14, ifec = 15,
	threat = 15.5,
	conveniences = 16, gameown = 17,
	onboard = 17.5,   -- after the modules it introduces, before the changelog
	changelog = 90,    -- after the modules, before profiles
	profiles = 99,     -- last, always
}

--- What's new, built from Core/Changelog.lua rather than written out again
--  here. This is where the Notes link on the Toolbox card lands.
--
--  Every release, not only the current one: the card shows the first couple of
--  lines of the newest entry, and this is the rest of it plus everything
--  before. A history nobody can reach is a history nobody keeps.
local function ChangelogGroup()
	local args = {
		-- TWO SENTENCES, TWO PHRASES, and the second one whole. Split at the
		-- placeholder it would leave a translator holding "Numbering is %s - a
		-- major for a" with the rest of the paragraph glued on outside, which
		-- is the fragment this whole pass exists to stop making.
		running = note(A.F(L.options.changelog.running,
				A.Hi(A.F(L.common.aether_ui_s, A.version or "?")))
			.. "\n\n"
			.. A.F(L.options.changelog.numbering_s_major_release,
				A.Val(L.options.changelog.major_minor_build))),
	}

	local history = A.NotesHistory and A:NotesHistory() or {}
	for i, entry in ipairs(history) do
		local body = {}
		for j, line in ipairs(entry.lines or {}) do
			body[j] = "\194\183 " .. line
		end
		-- Keyed by index rather than by version: a version string carries dots,
		-- and AceConfig treats the key as a path segment.
		args["rel" .. i] = group(
			(entry.version or "?") .. (entry.date and ("   " .. A.Dim(entry.date)) or ""),
			{ body = note(#body > 0 and table.concat(body, "\n") or "No notes.") },
			{ inline = true })
	end

	return group(L.common.what_s_new, args)
end

--- Build the whole tree. Pure: no libraries, no frames, no side effects.
function Options:Build()
	order = 0
	local tree = {
		type = "group",
		name = "Aether" .. A.Hi("UI"),
		args = {
			general = GeneralGroup(),
			unitframes = UnitFramesGroup(),
			partyframes = PartyFramesGroup(),
			auras = AurasGroup(),
			minimap = MinimapGroup(),
			actionbars = ActionBarsGroup(),
			quests = QuestGroup(),
			bags = BagsGroup(),
			chat = ChatGroup(),
			tooltips = TooltipsGroup(),
			toolbox = ToolboxGroup(),
			onboard = OnboardGroup(),
			fader = FaderGroup(),
			xpbar = XPGroup(),
			ifec = IFECGroup(),
			nameplates = NameplatesGroup(),
			threat = ThreatGroup(),
			conveniences = ConveniencesGroup(),
			gameown = GameOwnGroup(),
			changelog = ChangelogGroup(),
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
		A:Print(A.F(L.options.open.options_panel_needs_ace3,
			A.Dim("/aether help")))
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
