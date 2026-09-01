--[[--------------------------------------------------------------------------
	AetherUI :: enUS

	THE ENGLISH, AND THE FILE TO EDIT IT IN.

	This is not generated. Correct a typo, reword a description, sharpen a
	sentence - here, and nothing else moves: the KEY is what the source asks
	for, and the key does not change when the words do. That is the whole
	reason the keys are names rather than the sentences themselves.

	It is also the file to paste into CurseForge's phrase importer, once, which
	is how the phrases get created over there. After that a translation
	submitted on the website reaches a release through the @localization@ block
	in each of the other ten files; nothing comes back here.

	ADDING ONE: put it here, then use it as L.area.group.leaf. The suite fails
	on a key the source asks for and this file has not got, and reports the
	other way round as dead weight.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = A.Phrases("enUS")


-- auras -------------------------------------------------------------------

L["auras.diagnose.aura_diagnostic_gettime_1f"] =
	"aura diagnostic  ·  GetTime %.1f  ·  source %s"

-- bags --------------------------------------------------------------------

L["bags.ask_buy_bank_slot.buy_another_bank_bag"] =
	"Buy another bank bag slot for %s?"
L["bags.ask_buy_bank_slot.cannot_afford"] = "You cannot afford this."

L["bags.build_rail.equipped_bags"] = "Equipped bags"

L["bags.confirm_buy_bank_slot.bank_has_changed_since"] =
	"the bank has changed since that was asked - nothing was bought."

L["bags.diagnose.bags"] = "bags:"

L["bags.slot_info.trade_goods"] = "TRADE GOODS"

L["bags.sort_pass.stopped_compacting_after_40"] =
	"stopped compacting after 40 passes - run it again if there is "
		.. "still work to do."

L["bags.start_sort.while_combat"] = "not while you are in combat."

-- bars --------------------------------------------------------------------

L["bars.diagnose_flyout.flyout_drawer_built"] = "flyout: no drawer built"
L["bars.diagnose_flyout.flyout_text_window_ctrl"] =
	"flyout: in the text window - Ctrl+A then Ctrl+C to copy"

L["bars.set_bind_mode.can_t_rebind_combat"] = "can't rebind in combat."
L["bars.set_bind_mode.escape_clears_right_click"] =
	"Escape clears, right-click or /aether bind again to finish."
L["bars.set_bind_mode.keybind_mode_off"] = "keybind mode off."
L["bars.set_bind_mode.keybind_mode_s_hover"] =
	"keybind mode %s - hover a button and press a key."

L["bars.set_binding_to.key_can_t_bound"] = "that key can't be bound."

-- chat --------------------------------------------------------------------

L["chat.diagnose.anchors"] = "anchors:"
L["chat.diagnose.composers_screen_s"] = "composers on screen: %s"
L["chat.diagnose.composers_screen_s_s"] = "composers on screen: %s (%s)"
L["chat.diagnose.edit_box_found"] = "no edit box found."
L["chat.diagnose.edit_box_s"] = "edit box: %s"
L["chat.diagnose.left_text_inset_s"] = "left text inset: %s"
L["chat.diagnose.points_all"] = "no points at all"
L["chat.diagnose.screen"] = "ON SCREEN"

L["chat.diagnose_lines.message_lines"] = "message lines:"

L["chat.on_disable.chat_skin_off_s"] =
	"chat skin off. %s to get Blizzard's frames back."

L["chat.set_whisper_tab.client_has_s_whispers"] =
	"this client has no %s - no whispers tab."
L["chat.set_whisper_tab.could_open_new_chat"] =
	"could not open a new chat window: %s"
L["chat.set_whisper_tab.could_open_new_chat2"] =
	"could not open a new chat window."
L["chat.set_whisper_tab.whispers_back_main_window"] =
	"whispers are back in the main window. You can now close the "
		.. "emptytab."
L["chat.set_whisper_tab.whispers_back_main_window2"] =
	"whispers are back in the main window."
L["chat.set_whisper_tab.whispers_now_go_s"] = "whispers now go to %s."
L["chat.set_whisper_tab.whispers_tab_exists_but"] =
	"the whispers tab exists but no message group would move to it."

-- cmd ---------------------------------------------------------------------

L["cmd.auras.all_four_trays_re"] = "all four trays re-read."
L["cmd.auras.auras_module_enabled"] = "auras module is not enabled."

L["cmd.bags.bags_module_enabled"] = "bags module is not enabled."
L["cmd.bags.compacting_stacks"] = "compacting stacks."
L["cmd.bags.junk_auto_sell_s"] =
	"junk auto-sell %s - poor-quality items go the moment you talk toa "
		.. "merchant."
L["cmd.bags.junk_auto_sell_s2"] = "junk auto-sell %s."
L["cmd.bags.junk_sell"] = "no junk to sell."

L["cmd.bar.bar_s"] = "no bar %s."
L["cmd.bar.build_has_flyout_drawer"] = "this build has no flyout drawer"

L["cmd.bar_list.bars"] = "bars:"

L["cmd.chat.badges"] = "channel badges"
L["cmd.chat.chat_module_enabled"] = "chat module is not enabled."
L["cmd.chat.chat_re_skinned"] = "chat re-skinned."
L["cmd.chat.lines"] = "message line styling"
L["cmd.chat.whispers_tab_s_opens"] =
	"whispers tab is %s. It opens a real chat window and moves the "
		.. "whisper message groups onto it - which Blizzard saves, and keeps "
		.. "saved even with this addon off."

L["cmd.chat_where.chat_window_report"] = "no chat window to report on."

L["cmd.debug.debug_s"] = "debug -> %s"

L["cmd.diag.diagnostics_s_s"] = "diagnostics  (%s, %s)"
L["cmd.diag.green_hidden"] = "green = hidden"
L["cmd.diag.red_shown"] = "red = shown"

L["cmd.dump_panel.frame_called_s_open"] =
	"no frame called %s. Open the window first - half of these arrive "
		.. "with their own addon the first time you use them."

L["cmd.dump_rows.ours"] = "ours"
L["cmd.dump_rows.ours_parent_s"] = "NOT OURS, parent %s"

L["cmd.errors.errors_catcher_loaded"] = "errors: the catcher is not loaded"
L["cmd.errors.errors_cleared"] = "errors: cleared"

L["cmd.fade.delay_takes_0_5"] = "delay takes 0.5 - 60 seconds"
L["cmd.fade.idle_alpha_s"] = "idle alpha -> %s"
L["cmd.fade.idle_alpha_takes_0"] = "idle alpha takes 0 - 1"
L["cmd.fade.idle_delay_ss"] = "idle delay -> %ss"
L["cmd.fade.idle_fade_s"] = "idle fade -> %s"
L["cmd.fade.idle_fade_s_delay"] =
	"idle fade %s · delay %.1fs · idle alpha %.2f"

L["cmd.greet.greeting_login_s"] = "greeting at login -> %s"

L["cmd.health.health_bar_colour_s"] =
	"health bar colour is %s. 'class' colours players by class; 'deck' "
		.. "uses green and reserves colour for reaction."
L["cmd.health.health_bar_colour_s2"] = "health bar colour -> %s"
L["cmd.health.s_s_tune_two"] =
	"%s and %s tune the two ends of a class-coloured bar."

L["cmd.ifec.absent"] = "absent"
L["cmd.ifec.attached"] = "attached"
L["cmd.ifec.ifec_content_api_s"] = "ifec  ·  content API %s-%s"
L["cmd.ifec.ifec_loaded"] = "ifec: not loaded"
L["cmd.ifec.ifec_route_lookup_loaded"] = "ifec: the route lookup is not loaded"
L["cmd.ifec.last_file_would_play"] = "last file that would not play"
L["cmd.ifec.packs_registered"] = "  no packs registered"
L["cmd.ifec.playback_s"] = "  playback: %s"
L["cmd.ifec.playback_s_s_seg"] = "  playback: %s  ·  %s seg %s of %s"
L["cmd.ifec.queue_d_items_s"] = "  queue: %d items  ·  at %s  ·  region %s"

L["cmd.measure_panels.dressed_panel_open_open"] =
	"no dressed panel is open - open one, or name it"
L["cmd.measure_panels.panels_module_loaded"] = "panels module not loaded"

L["cmd.module.module_s_s"] = "module %s -> %s"
L["cmd.module.modules_s"] = "modules: %s"
L["cmd.module.unknown_command_s"] = "unknown command '%s'"

L["cmd.panels.dump_framename"] = "dump <FrameName>"
L["cmd.panels.panels"] = "panels"
L["cmd.panels.panels_s_s_reads"] =
	"panels is %s.  %s reads a window's parts into a box you can copy "
		.. "out of, %s reports what its header and body actually came out as, "
		.. "%s says why one is still wearing its own art."

L["cmd.panels_diag.panels_module"] = "no panels module"

L["cmd.party.closed"] = "closed"
L["cmd.party.party"] = "party"
L["cmd.party.party_controls_s_s"] = "party controls %s  ·  %s for the report"
L["cmd.party.party_frames_back_dock"] =
	"party frames back on the dock. Drag them again to place them where "
		.. "you want."
L["cmd.party.party_frames_switched_off"] = "party frames are switched off."

L["cmd.party_diag.party_module"] = "no party module"

L["cmd.preset.could_apply_s"] = "could not apply %s."
L["cmd.preset.layout_s"] = "layout: %s"
L["cmd.preset.presets_loaded"] = "presets are not loaded."

L["cmd.quests.objective_lines_s"] = "objective lines %s."
L["cmd.quests.quest_tracker_folded"] = "quest tracker folded."
L["cmd.quests.quest_tracker_unfolded"] = "quest tracker unfolded."
L["cmd.quests.questtracker_module_enabled"] =
	"questtracker module is not enabled."
L["cmd.quests.tracking_reset"] = "tracking reset."

L["cmd.resources.no_maximum"] = "nothing reports a maximum"
L["cmd.resources.no_tray"] = "this build has no resource tray"
L["cmd.resources.none_s"] = "no class resource on this character - %s"

L["cmd.scale.scale_2f"] = "scale -> %.2f"
L["cmd.scale.scale_takes_0_6"] =
	"scale takes 0.6 - 1.6, or fit (currently %.2f). Every size in "
		.. "AetherUI is a screen pixel measured off a real display; fit is the "
		.. "scale that draws them at exactly that size on yours, and is what a "
		.. "new profile starts at."

L["cmd.shadow.shadow_takes_0_1"] =
	"shadow takes 0 - 1 (currently %s). It is an opacity, not a "
		.. "distance - the geometry is derived from the shape so the shadow's "
		.. "hole matches its corner."

L["cmd.skin.skin_s"] = "skin -> %s"
L["cmd.skin.skins_s"] = "skins: %s"

L["cmd.toolbox.dock_takes_s_s"] = "dock takes %s, %s, %s or %s."
L["cmd.toolbox.libdatabroker"] = "(no LibDataBroker!)"
L["cmd.toolbox.minimap_scan_failed_s"] = "minimap scan failed: %s"
L["cmd.toolbox.nothing"] = "nothing"
L["cmd.toolbox.nothing_called_s_offers"] =
	"nothing called %s offers a launcher. %s lists what does."
L["cmd.toolbox.pin_s_s"] = "pin %s -> %s"
L["cmd.toolbox.pinned_s"] = "pinned: %s"
L["cmd.toolbox.shut"] = "shut"
L["cmd.toolbox.toolbox_docked_s_s"] =
	"toolbox  ·  docked %s  ·  %s  ·  scrim %.2f"
L["cmd.toolbox.toolbox_module_enabled"] = "toolbox module is not enabled."

L["cmd.tooltips.follow_cursor"] = "follow the cursor"
L["cmd.tooltips.level_badge_s_one"] =
	"level badge %s - this is the one setting that rewrites tooltip "
		.. "text."
L["cmd.tooltips.stay_where_whatever_opened"] =
	"stay where whatever opened them put them"
L["cmd.tooltips.tooltips_module_enabled"] = "tooltips module is not enabled."
L["cmd.tooltips.unit_tooltips_anchored_their"] =
	"unit tooltips anchored to their corner - /aether unlock to move "
		.. "it."
L["cmd.tooltips.unit_tooltips_back_blizzard"] =
	"unit tooltips back on Blizzard's default anchor."

L["cmd.tour.tour_loaded"] = "the tour is not loaded."

L["cmd.zen.frosted_pane_s_s"] = "the frosted pane -> %s %s"
L["cmd.zen.idle_fade_off_so"] =
	"idle fade is off, so there is no stage two to preview. %s first."
L["cmd.zen.move_camera_zen_s"] = "move the camera in zen -> %s"
L["cmd.zen.nameplates_s_go_zen"] = "nameplates %s go with zen -> %s %s"
L["cmd.zen.names"] = "and names"
L["cmd.zen.pane_front_world_blur"] =
	"(a pane in front of the world, not a blur of it - nothing can blur "
		.. "the world)"
L["cmd.zen.s_change"] = "%s to change it"
L["cmd.zen.sit_down_zen_s"] = "sit down in zen -> %s"
L["cmd.zen.two_separate_cvar_families"] =
	"(two separate CVar families; one switch drives both)"
L["cmd.zen.zen_audio_s"] = "zen audio -> %s"
L["cmd.zen.zen_delay_ss"] = "zen delay -> %ss"
L["cmd.zen.zen_delay_takes_5"] =
	"zen delay takes 5 - %d seconds. The client flags you away at %d, "
		.. "and zen follows it there regardless."
L["cmd.zen.zen_going_away_s"] = "zen on going away -> %s"
L["cmd.zen.zen_mode_s"] = "zen mode -> %s"
L["cmd.zen.zen_preview_move_mouse"] =
	"zen preview · move the mouse or press a key"
L["cmd.zen.zen_track_s"] = "zen track -> %s"
L["cmd.zen.zen_track_takes_one"] = "zen track takes one of: %s"

-- common ------------------------------------------------------------------

L["common.actionbars_module_enabled"] = "actionbars module is not enabled."

L["common.aether_ui_s"] = "Aether UI %s"

L["common.banish_report_hideblizzard_never"] =
	"no banish report - HideBlizzard never ran"

L["common.bar_width"] = "Bar width"

L["common.brighter"] = "brighter"

L["common.can_t_abandon_here"] =
	"can't abandon from here on this client - use the quest log."

L["common.can_t_change_bindings"] = "can't change bindings in combat."

L["common.capsule"] = "Capsule"

L["common.character"] = "character"

L["common.click_target"] = "Click to target"

L["common.enabled"] = "Enabled"

L["common.height"] = "Height"

L["common.height_budget"] = "Height budget"

L["common.i_f_e_c"] = "I.F.E.C."

L["common.item_spell_tooltips_s"] = "item and spell tooltips %s."

L["common.left_click_targets_right"] =
	"Left-click targets, right-click opens the unit menu."

L["common.lock_frames"] = "Lock frames"

L["common.look"] = "Look"

L["common.most_show"] = "Most to show"

L["common.off"] = "off"

L["common.on"] = "on"

L["common.open"] = "open"

L["common.player"] = "On the player"

L["common.rows_most"] = "Rows at most"

L["common.scale"] = "Scale"

L["common.show_power_bar"] = "Show power bar"

L["common.size"] = "Size"

L["common.spacing"] = "Spacing"

L["common.take_tour"] = "Take the tour"

L["common.target"] = "On the target"

L["common.toolbox"] = "Toolbox"

L["common.toolbox_docked_s"] = "toolbox docked -> %s"

L["common.tooltips"] = "Tooltips"

L["common.top_global_scale"] = "On top of the global scale."

L["common.what_s_new"] = "What's new"

L["common.width"] = "Width"

L["common.zen_module_enabled"] = "zen module is not enabled."

L["common.zen_s_s_s"] = "zen %s -> %s  ·  %s"

-- conveniences ------------------------------------------------------------

L["conveniences.repair.enough_repairs"] = "not enough for repairs:"
L["conveniences.repair.repaired_s"] = "repaired for %s"

-- core --------------------------------------------------------------------

L["core.boot.init_s"] = "init '%s':"

L["core.enable_module.full_picture"] = "for the full picture."
L["core.enable_module.module_s_failed_enable"] =
	"module '%s' failed to enable:"

L["core.fire_skin_changed.skin_listener_failed"] = "a skin listener failed:"

L["core.misc.label"] = "Bar 1"
L["core.misc.label2"] = "Bar 2"
L["core.misc.label3"] = "Bar 3"
L["core.misc.label4"] = "Bar 4"
L["core.misc.label5"] = "Bar 5"
L["core.misc.label6"] = "Bar 6"

L["core.pump.event"] = "event '%s':"
L["core.pump.ticker"] = "ticker:"

-- errors ------------------------------------------------------------------

L["errors.build.errors"] = "Errors"
L["errors.build.export"] = "Export"
L["errors.build.export_writes_savedvariables_aetherui"] =
	"Export writes it to SavedVariables\\\\\\\\AetherUI.lua. Escape "
		.. "closes."

-- library -----------------------------------------------------------------

L["library.build.library"] = "LIBRARY"

L["library.paint.d_pages"] = "%d pages"
L["library.paint.nothing_kind_season"] = "Nothing of that kind this season."
L["library.paint.page_d_d"] = "page %d of %d"
L["library.paint.playing"] = "playing"
L["library.paint.queued"] = "queued"
L["library.paint.read"] = "read"

-- mini --------------------------------------------------------------------

L["mini.paint.nothing_playing"] = "Nothing playing"

-- movers ------------------------------------------------------------------

L["movers.create_handle.can_t_move_frames"] = "can't move frames in combat."

L["movers.lock.frames_locked"] = "frames locked."

L["movers.reset_all.frame_positions_reset"] = "frame positions reset."

L["movers.unlock.frames_unlocked_drag_move"] =
	"frames unlocked - drag to move, scroll to nudge (hold shift for "
		.. "horizontal). Press %s, or %s, when done."

-- options -----------------------------------------------------------------

L["options.action_bars.action_bars"] = "Action bars"
L["options.action_bars.empty_alpha.name"] = "Empty slot opacity"
L["options.action_bars.font_delta.name"] = "Text size offset"
L["options.action_bars.hide_blizzard.name"] = "Hide Blizzard's bars"
L["options.action_bars.lock_buttons.name"] = "Lock buttons"
L["options.action_bars.padding.name"] = "Panel padding"
L["options.action_bars.paging_note"] = "There is no paging."
L["options.action_bars.points_added_keybind_count"] =
	"Points added to the keybind, count and cooldown text."
L["options.action_bars.require_modified_click_pick"] =
	"Require a modified click to pick an action up."
L["options.action_bars.scale.name"] = "Scale (all bars)"
L["options.action_bars.shared"] = "Shared"
L["options.action_bars.show_keybinds.name"] = "Show keybinds"
L["options.action_bars.size.desc"] = "The size of the button slots."
L["options.action_bars.size.name"] = "Button size"

L["options.auras.align.name"] = "Row alignment"
L["options.auras.auras"] = "Auras"
L["options.auras.buffs"] = "Buffs"
L["options.auras.centred_splits_slack_row"] =
	"Centred splits the slack a row cannot fill into two margins. "
		.. "Mirrored follows the unit's own name and readout - left on the "
		.. "player, right on the target - which puts all of it on one side."
L["options.auras.debuffs"] = "Debuffs"
L["options.auras.desc"] =
	"Buffs above each capsule, debuffs below, on the player and the "
		.. "target alike."
L["options.auras.hide_blizzard.name"] = "Hide Blizzard's buff row"
L["options.auras.n0_fits_many_frame"] =
	"0 fits as many as the frame is wide enough for, which is what "
		.. "keeps a tray inside the unit it belongs to. Set a number to use "
		.. "fewer."
L["options.auras.offset.name"] = "Gap from the capsule"
L["options.auras.only_mine.name"] = "Only mine, on the target"
L["options.auras.per_row.name"] = "Cap the columns"
L["options.auras.show_count.name"] = "Show stack counts"
L["options.auras.show_time.name"] = "Show timers"
L["options.auras.size.name"] = "Icon size"
L["options.auras.takes_weapon_enchant_icons"] =
	"Takes the weapon-enchant icons with it, and nothing replaces those "
		.. "yet."
L["options.auras.tile_header"] = "Tiles"
L["options.auras.tile_note"] =
	"A tile is an icon and a timer, with no name - the name is on the "
		.. "tooltip. Right-click one of your own buffs to cancel it, in combat "
		.. "as well as out of it."
L["options.auras.yourself_every_debuff_matters"] =
	"On yourself every debuff matters whoever cast it."

L["options.bags.bags"] = "Bags"
L["options.bags.columns.name"] = "Columns"
L["options.bags.desc"] =
	"One window for the backpack and your four bags, sorted into "
		.. "categories, with the equipped bags and the keyring on a flyout off "
		.. "the right edge. At a banker the bank opens beside it. This "
		.. "replaces Blizzard's bags rather than reskinning them; turning it "
		.. "off gives them back, including the B key."
L["options.bags.dim_junk.name"] = "Dim poor-quality items"
L["options.bags.drawer_off_right_edge"] =
	"A drawer off the right edge carrying your equipped bags and, under "
		.. "it, the keyring. Drag a new bag onto one to swap it. The handle on "
		.. "the window's edge slides it out; whether it is out is remembered "
		.. "per character."
L["options.bags.free_section_foot_grid"] =
	"A FREE section at the foot of the grid. It is not a category, and "
		.. "it is not sorted. It is for whatever you want to keep handy, and "
		.. "it is remembered per character."
L["options.bags.grid_header"] = "Grid"
L["options.bags.hide_blizzard.name"] = "Hide Blizzard's bags"
L["options.bags.junk_auto_sell.name"] = "Sell junk at a merchant"
L["options.bags.panel_hugs_contents_up"] =
	"The panel hugs its contents up to this, then the grid scrolls on "
		.. "the wheel. There is no scroll bar."
L["options.bags.quality_rim.name"] = "Colour slots by quality"
L["options.bags.sell_header"] = "Junk"
L["options.bags.sells_every_poor_quality"] =
	"Sells every poor-quality item that has a value the moment you open "
		.. "any merchant, one item at a time, and tells you what it made. Off "
		.. "by default: this is the only thing here that sells your items for "
		.. "you."
L["options.bags.show_empty.name"] = "Show free slots"
L["options.bags.show_flyout.name"] = "Show the equipped-bags drawer"
L["options.bags.show_keyring.name"] = "Show the keyring"
L["options.bags.show_search.name"] = "Show the search box"
L["options.bags.slot_gap.name"] = "Gap between slots"
L["options.bags.slot_size.name"] = "Slot size"
L["options.bags.typing_dims_what_does"] =
	"Typing dims what does not match rather than removing it, so "
		.. "nothing moves under the cursor while you narrow it down."
L["options.bags.window_wide_grid_eight"] =
	"The window is as wide as the grid: eight columns of 44 is the "
		.. "default."

L["options.bar_pages.backdrop.desc"] = "Off leaves the buttons bare."
L["options.bar_pages.backdrop.name"] = "Glass panel"
L["options.bar_pages.bar_n_owns_page"] =
	"Bar N owns page N. Pages 7-10 are the bonus bars a druid or rogue "
		.. "gets in a form - point a bar at one and you simply see those "
		.. "abilities rather than having a bar swap under you."
L["options.bar_pages.buttons"] = "Buttons"
L["options.bar_pages.page"] = "Page"
L["options.bar_pages.rows.desc"] = "Columns fall out of this."
L["options.bar_pages.rows.name"] = "Rows"

L["options.changelog.major_minor_build"] = "major.minor.build"
L["options.changelog.numbering_s_major_release"] =
	"Numbering is %s - a major for a release with new features in it, a "
		.. "minor for accumulated fixes and small enhancements, and a build "
		.. "for hotfixes."
L["options.changelog.running"] = "Running %s."

L["options.chat.added_whatever_size_blizzard"] =
	"Added to whatever size Blizzard's own chat settings say, so that "
		.. "stays the setting and this is the nudge."
L["options.chat.badge_offset.name"] = "Badge baseline nudge"
L["options.chat.badge_size.name"] = "Badge height"
L["options.chat.badges.name"] = "Channel badges"
L["options.chat.behave_header"] = "Behaviour"
L["options.chat.blizzard_s_own_message"] =
	"Blizzard's own message fade, which empties the log rather than "
		.. "dimming the frame. Different thing from the setting above."
L["options.chat.channel_prefix.name"] = "Keep Blizzard's [1. General]"
L["options.chat.chat"] = "Chat"
L["options.chat.chat_dims_everything_else"] =
	"Chat dims with everything else when you go idle, and goes "
		.. "altogether in zen mode. Off leaves it fully readable at all times."
L["options.chat.class_color_names.name"] = "Class-colour names"
L["options.chat.client_already_centres_badge"] =
	"The client already centres a badge on its line, so zero is "
		.. "normally right. Negative sinks it, positive raises "
		.. "it.\\\\n\\\\nOnly new lines take a change - a chat line is a "
		.. "string with the badge baked into it, so the log above keeps "
		.. "whatever it was printed with."
L["options.chat.default_rare_classic_era"] =
	"On by default: it is rare on Classic Era and never what you are "
		.. "reading a line for. Off dims it instead of losing it. Either way "
		.. "the player link still carries the full name, so whispering and "
		.. "right-clicking work on a cross-realm name you cannot see."
L["options.chat.desc"] =
	"Blizzard's chat frames, skinned in place. One frosted panel, tabs "
		.. "as pills along the top with the zone beside them, and the edit box "
		.. "inset into the bottom edge with a channel tag and a send glyph."
L["options.chat.dim_system.name"] = "Dim system lines"
L["options.chat.em_dash.name"] = "Em dash instead of \"says:\""
L["options.chat.fade.name"] = "Breathes with the HUD"
L["options.chat.fade_messages.name"] = "Fade old lines out"
L["options.chat.font_delta.name"] = "Text size"
L["options.chat.hide_buttons.name"] = "Lose the buttons"
L["options.chat.hide_realm.name"] = "Drop the realm entirely"
L["options.chat.lines_header"] = "Message lines"
L["options.chat.lines_note"] =
	"The name is class-coloured and its realm dimmed, the \"says:\" "
		.. "becomes an em dash, and the channel gets a badge.\\\\n\\\\n%s "
		.. "Blizzard hands out the decorated name and builds the player link "
		.. "around what comes back, so whispers, ignore and the right-click "
		.. "menu are out of reach rather than carefully avoided."
L["options.chat.master_switch_everything_below"] =
	"The master switch. Everything below hangs off one filter and one "
		.. "set of format strings, and half of them on is a line that reads as "
		.. "neither Blizzard's nor ours."
L["options.chat.none_rewrites_author"] = "None of this rewrites the author."
L["options.chat.off_concept_badge_what"] =
	"Off is the concept: the badge is what replaces it. Blizzard builds "
		.. "that bracket after the line is formatted, so it comes off the "
		.. "finished string rather than through a filter."
L["options.chat.one_outlives_addon"] = "This one outlives the addon."
L["options.chat.pill_carrying_channel_whatever"] =
	"A pill carrying the channel, in whatever colour your own chat "
		.. "settings give that channel.\\\\n\\\\nThe words are baked into a "
		.. "texture, so the four channels a Classic Era character actually "
		.. "joins have one and anything else gets its own name as text."
L["options.chat.resizable.name"] = "Show the resize corner"
L["options.chat.scroll_arrows_resize_grip"] =
	"The scroll arrows, the resize grip and the menu buttons down the "
		.. "side. Scrolling still works on the wheel."
L["options.chat.sender_s_guid_which"] =
	"From the sender's GUID, which is what Blizzard's own class "
		.. "colouring uses - so it is right for two people with the same name "
		.. "on different realms."
L["options.chat.show_zone.name"] = "Zone beside the tabs"
L["options.chat.style_lines.name"] = "Style the lines"
L["options.chat.time_visible.name"] = "Seconds a line stays"
L["options.chat.unlocked.name"] = "Movable and resizable"
L["options.chat.unlocks_blizzard_s_own"] =
	"Unlocks Blizzard's own move and resize, which is also what saves "
		.. "them - drag a tab to move it, drag the corner to resize. Locked is "
		.. "the client's default and it ignores both."
L["options.chat.whisper_header"] = "Whispers"
L["options.chat.whisper_tab.name"] = "Whispers get their own tab"

L["options.conveniences.auto_repair.name"] = "Repair at a vendor automatically"
L["options.conveniences.conveniences"] = "Conveniences"
L["options.conveniences.instant_quest_text.name"] = "Instant quest text"
L["options.conveniences.quest_text_appears_once"] =
	"Quest text appears at once instead of being typed "
		.. "out.\\\\n\\\\nThis is the game's OWN setting - Interface, "
		.. "Controls, Instant Quest Text - set for you. Off puts it back the "
		.. "way you had it, which is why it is off here to begin with: you may "
		.. "have chosen the typing on purpose."
L["options.conveniences.repairs_everything_moment_open"] =
	"Repairs everything the moment you open a merchant who "
		.. "can.\\\\n\\\\nOFF by default, because it SPENDS YOUR MONEY. It "
		.. "will not repair when you cannot afford it - it tells you instead, "
		.. "rather than half-repairing - and every repair prints what it cost, "
		.. "so nothing leaves your purse quietly."

L["options.fader.active_alpha.name"] = "Active opacity"
L["options.fader.adds_frame_listens_keys"] =
	"Adds a frame that listens for keys while zen is on screen and "
		.. "passes every one of them straight through. It is only listening "
		.. "while zen is up."
L["options.fader.blur_cannot"] = "It is not a blur, and it cannot be"
L["options.fader.client_flags_away_itself"] =
	"The client flags you away by itself after five minutes without "
		.. "input, so this fires even if the timer below is longer than that."
L["options.fader.corner_block_shows_circle"] =
	"The corner block shows a circle of the zone's own map art around "
		.. "where you are standing, with the accent dot marking you. It is the "
		.. "world map's art rather than the minimap's view - nothing can "
		.. "capture what the minimap renders - and being static suits a calm "
		.. "mode better. Off, or anywhere there is no art, it falls back to a "
		.. "plain glass disc."
L["options.fader.darker_toward_edges_so"] =
	"Darker toward the edges, so the pane has a shape rather than being "
		.. "an even wash. Kept low - this was doing most of the darkening the "
		.. "pane used to be blamed for."
L["options.fader.delay.desc"] = "Seconds."
L["options.fader.delay.name"] = "Quiet before fading"
L["options.fader.desc"] =
	"The HUD fades out when nothing is happening. Idle is inferred "
		.. "rather than observed: Classic gives addons no general keypress "
		.. "hook, so this watches consequences - combat, casting, having a "
		.. "target, being below full health or mana, cursor movement - and "
		.. "treats their absence as idle."
L["options.fader.fade_in.name"] = "Fade in time"
L["options.fader.fade_out.name"] = "Fade out time"
L["options.fader.fades_uiparent_which_everything"] =
	"Fades UIParent, which is everything: the minimap, the chat frame, "
		.. "the XP hairline, nameplates, and anything any other addon has put "
		.. "on screen. Off leaves only AetherUI's own frames fading, which "
		.. "means everything else stays up."
L["options.fader.fractions_own_settings"] = "fractions of your own settings"
L["options.fader.how_far_skin_s"] =
	"How far the skin's glass colour is lifted toward white. Low values "
		.. "give you the skin's own hue at full strength, which on a dark skin "
		.. "means a dark pane - legible, but it reads as the lights going out "
		.. "rather than as glass."
L["options.fader.how_much_world_glass"] =
	"How much of the world the glass keeps. Past about 85% it stops "
		.. "being a window and becomes opaque."
L["options.fader.idle_alpha.name"] = "Idle opacity"
L["options.fader.idle_fade"] = "Idle fade"
L["options.fader.keep_header"] = "Stay awake while"
L["options.fader.keep_on_hurt.name"] = "Health or mana is down"
L["options.fader.keep_on_mouse.name"] = "The cursor is over a frame"
L["options.fader.keep_on_target.name"] = "You have a target"
L["options.fader.kept_higher_than_others"] =
	"Kept higher than the others on purpose: a little wind and water "
		.. "under the music is the difference between a quiet world and a dead "
		.. "one."
L["options.fader.layer_doing_actual_work"] =
	"The layer doing the actual work, in two parts: visible patches of "
		.. "thicker and thinner glass, and an additive light over them that "
		.. "lifts the darks without touching the brights. That second part is "
		.. "what flattens the contrast of the world behind the pane, and "
		.. "contrast is most of what a real blur takes away."
L["options.fader.map_survives_zen_zone"] =
	"On, the map survives zen and the zone and clock move under it - "
		.. "the one part of the HUD still telling you something while you are "
		.. "not playing. Off, which is the default, it goes with everything "
		.. "else and the block draws a small glass disc beside the zone in its "
		.. "place."
L["options.fader.minutes_least_one_so"] =
	"Minutes. At least one, so zen always comes after the HUD has faded "
		.. "- the fade waits up to a minute. Capped at five, because that is "
		.. "when the client flags you away and zen would happen anyway."
L["options.fader.one_channel_zen_raises"] =
	"The one channel zen raises rather than lowers, and only if it is "
		.. "under this already. A meditation track played through a music "
		.. "channel somebody left at zero is a feature that silently does "
		.. "nothing. Set it to 0 to leave the music channel completely alone."
L["options.fader.one_thing_fading_interface"] =
	"The one thing fading the interface does not reach: nameplates and "
		.. "the floating unit names are drawn against the world rather than "
		.. "composited into the interface, so they are left hanging over an "
		.. "empty hillside otherwise.\\\\n\\\\nThese are %s in the client - "
		.. "the bars and the text have unrelated settings - so this drives "
		.. "both. Taking the bars away and leaving every name, guild tag and "
		.. "pet label floating looks like a fault rather than a choice. "
		.. "Everything is turned off at the bottom of the fade and turned back "
		.. "on the moment you come out, including on the way to a "
		.. "logout.\\\\n\\\\nTooltips need nothing: they belong to the "
		.. "interface and go with it."
L["options.fader.only_hard_signals_hold"] =
	"Only the hard signals hold this off"
L["options.fader.playing_s"] = "playing %s"
L["options.fader.plays_now_so_can"] =
	"Plays it now so you can choose without waiting out the timer. "
		.. "Press again to stop. A preview changes no volumes."
L["options.fader.roughly_metres_camera_glides"] =
	"Roughly metres. The camera glides there at the client's own pace. "
L["options.fader.row_dots_they_carry"] =
	"The row of dots. They carry no information - they are a slow "
		.. "pulse."
L["options.fader.screens_per_second_two"] =
	"Screens per second the two scatter layers slide past each other, "
		.. "in opposite directions. Far too slow to read as movement - it is "
		.. "there for the parallax against a world that is not moving. Set it "
		.. "to 0 to stop it dead."
L["options.fader.skipped_while_mounted_taxi"] =
	"Skipped while you are mounted, on a taxi, in combat or dead - a "
		.. "refused emote puts a red error across the middle of a screen whose "
		.. "whole point is being quiet. You are stood back up when zen ends."
L["options.fader.tilt"] = "The tilt is not"
L["options.fader.two_separate_systems"] = "two separate systems"
L["options.fader.zen_audio.desc"] =
	"Nothing happens at all if you have the game's sound switched off "
		.. "entirely."
L["options.fader.zen_audio_header"] = "The audio profile"
L["options.fader.zen_audio_note"] =
	"Zen borrows the sound channels while it is on screen and gives "
		.. "them back when it ends.\\\\n\\\\nThe three sliders below are %s, "
		.. "not volumes. 5%% of an effects channel you keep at 80%% is 4%%; at "
		.. "20%% it is 1%%. Your master volume is never touched, and a channel "
		.. "you change by hand during zen is left where you put it rather than "
		.. "being handed a stale value back."
L["options.fader.zen_camera.name"] = "Move the camera"
L["options.fader.zen_camera_zoom.name"] = "Distance behind you"
L["options.fader.zen_caption.name"] = "Show the caption"
L["options.fader.zen_delay.name"] = "Quiet before zen"
L["options.fader.zen_dim_u_i.name"] = "Take the whole interface with it"
L["options.fader.zen_dots.name"] = "Show the breath"
L["options.fader.zen_duck_ambience.name"] = "Ambience, as a fraction of yours"
L["options.fader.zen_duck_dialog.name"] = "Dialogue, as a fraction of yours"
L["options.fader.zen_duck_s_f_x.name"] = "Effects, as a fraction of yours"
L["options.fader.zen_fade_in.name"] = "Time to come back"
L["options.fader.zen_fade_out.name"] = "Time to sink into it"
L["options.fader.zen_frost_brightness.name"] = "Pane brightness"
L["options.fader.zen_frost_drift.name"] = "Drift"
L["options.fader.zen_frost_header"] = "The frosted pane"
L["options.fader.zen_frost_note"] =
	"A pane of frosted glass drawn in front of the world while zen is "
		.. "on.\\\\n\\\\n%s. The client gives addons no way to read or filter "
		.. "the 3D scene - no render-to-texture, no shader, no post-process "
		.. "hook - so the world behind stays sharp. What frosted glass "
		.. "actually is, though, is a surface in front of a sharp "
		.. "scene.\\\\n\\\\nIt gets %s, not darker. Frosted glass scatters "
		.. "light, so it is brighter than what is behind it and what it "
		.. "destroys is contrast. A dark pane leaves every edge in the scene "
		.. "perfectly crisp and simply turns the lights off."
L["options.fader.zen_frost_opacity.name"] = "Pane opacity"
L["options.fader.zen_frost_scatter.name"] = "Scatter"
L["options.fader.zen_frost_vignette.name"] = "Vignette"
L["options.fader.zen_glyph.name"] = "Glyph size"
L["options.fader.zen_keep_map.name"] = "Keep the minimap"
L["options.fader.zen_keys.name"] = "A keypress wakes it"
L["options.fader.zen_look_header"] = "Zen readout"
L["options.fader.zen_map_art.name"] = "Draw the map glyph"
L["options.fader.zen_music_floor.name"] = "Lift the music channel to at least"
L["options.fader.zen_nameplates.name"] = "Take the nameplates and names away"
L["options.fader.zen_note"] =
	"Stage two. The whole interface goes and a single capsule takes its "
		.. "place along the bottom edge - health, power, and a slow breath - "
		.. "with the zone and the time in the corner. Anything you do brings "
		.. "it back, including a keypress, which is the one thing stage one "
		.. "cannot see.\\\\n\\\\n%s: combat, casting, and the cursor sitting "
		.. "on the HUD. Having a target or being below full health keeps stage "
		.. "one awake but not this one, because neither is evidence that you "
		.. "are still in the chair."
L["options.fader.zen_on_a_f_k.name"] = "When you go away"
L["options.fader.zen_pill.name"] = "Show the zone and time"
L["options.fader.zen_preview.name"] = "Preview the track"
L["options.fader.zen_quiet_header"] = "Distractions"
L["options.fader.zen_shot_header"] = "The shot"
L["options.fader.zen_shot_note"] =
	"Zen sets up a camera rather than just clearing the screen: the "
		.. "character settles, and the view pulls back over their "
		.. "shoulder.\\\\n\\\\nThe zoom is exact and exactly reversible - the "
		.. "game will tell us the current distance, so yours is put back "
		.. "rather than guessed at. %s: the client offers no way to read the "
		.. "camera's pitch, only to move it, so the way back is the same "
		.. "movement reversed for the same time."
L["options.fader.zen_sit.name"] = "Sit down"
L["options.fader.zen_track.desc"] =
	"Looped on the music channel for as long as zen lasts. Random picks "
		.. "once each time zen begins, not once per session."
L["options.fader.zen_track.name"] = "Track"
L["options.fader.zen_width.name"] = "Capsule width"
L["options.fader.zen_y.name"] = "Height above the bottom edge"

L["options.game_own.dialogs.desc"] =
	"The confirmation boxes - \"do you want to destroy this?\" and the "
		.. "like."
L["options.game_own.dialogs.name"] = "Dialogs"
L["options.game_own.game_s_own"] = "Game panels"
L["options.game_own.lettering.desc"] =
	"The game's own type in this interface's letters - every panel, "
		.. "every tooltip, every menu, and \"You can't do that "
		.. "yet\".\\\\n\\\\nA change of FACE only: sizes stay as the game had "
		.. "them, so nothing moves; outlines stay, because text drawn over the "
		.. "world needs them; and colours stay, because a colour is the game "
		.. "telling you something.\\\\n\\\\nOTHER ADDONS COME WITH IT. "
		.. "Anything drawn with the game's own type reads as part of the same "
		.. "interface without its author doing anything. One that chose its "
		.. "own lettering keeps it."
L["options.game_own.lettering.name"] = "Lettering"
L["options.game_own.menus.desc"] =
	"The right-click menus - the one on your portrait, your pet's, a "
		.. "chat tab's. One hook rather than a list of frames, so it covers "
		.. "every menu the game opens."
L["options.game_own.menus.name"] = "Menus"
L["options.game_own.note"] =
	"Everything here is the GAME panels, redressed rather than "
		.. "replaced. Each switch is the same: off gives you Blizzard's back "
		.. "whole, art and all."
L["options.game_own.settings.desc"] =
	"These settings, in the same glass as the rest of it. Off leaves "
		.. "the options panel looking like Blizzard's."
L["options.game_own.settings.name"] = "This panel"
L["options.game_own.timers.desc"] =
	"The breath, fatigue and feign-death bars. Which timer it is stays "
		.. "in the colour - blue for breath, yellow for fatigue, orange for "
		.. "death - in this interface's colours."
L["options.game_own.timers.name"] = "Timers"
L["options.game_own.windows.desc"] =
	"The game's windows - character, spellbook, talents, guild, map, "
		.. "menu and help. What is inside them is left alone: item slots, "
		.. "spell buttons and map pins are still the default."
L["options.game_own.windows.name"] = "Windows"

L["options.general.class_color_health.name"] = "Class-coloured health"
L["options.general.corner.name"] = "Panel corner radius"
L["options.general.general"] = "General"
L["options.general.glass_header"] = "Glass"
L["options.general.grid.name"] = "Show grid"
L["options.general.grid_header"] = "While frames are unlocked"
L["options.general.grid_note"] =
	"Edges and centres snap to the grid and to the other frames on "
		.. "screen, which is what actually gets two bars lined up. Another "
		.. "frame always wins over the grid, and holding alt while you drag "
		.. "turns the whole thing off for that one placement."
L["options.general.grid_size.desc"] = "Every fourth line is drawn brighter."
L["options.general.grid_size.name"] = "Grid spacing"
L["options.general.how_much_deeper_chat"] =
	"How much deeper chat, the quest log and other readable frames sit "
		.. "than the rest of the UI. 0% matches the action bars and capsules; "
		.. "100% is solid. They carry paragraphs of small text over moving "
		.. "scenery, so they need more opacity."
L["options.general.off_uses_concept_s"] =
	"Off uses green and reserves colour for reaction."
L["options.general.pos_header"] = "Positions and keys"
L["options.general.read_opacity.name"] = "Reading panel opacity"
L["options.general.reset.desc"] = "Forget every saved anchor."
L["options.general.reset.name"] = "Reset positions"
L["options.general.scale.desc"] =
	"Scales everything at once onto WoW's virtual space one-for-one."
L["options.general.shadow.desc"] =
	"Opacity, not a distance - the shadow's geometry is derived from "
		.. "the shape it sits under so it lines up with that shape's own "
		.. "curves."
L["options.general.shadow.name"] = "Shadow opacity"
L["options.general.skin.desc"] =
	"Each one is its own accent on its own glass. The change is live - "
		.. "no reload."
L["options.general.skin.name"] = "Skin"
L["options.general.snap.name"] = "Snap to edges"
L["options.general.snap_distance.desc"] =
	"How close an edge has to come before it is caught. Much above 20 "
		.. "and you can no longer put a frame where you actually meant to."
L["options.general.snap_distance.name"] = "Snap distance"

L["options.i_f_e_c.enabled.desc"] =
	"A flight timer on every taxi, and the I.F.E.C. for content when a "
		.. "content pack is installed."
L["options.i_f_e_c.flight_console"] = "In-flight Entertainment Console"
L["options.i_f_e_c.hide_u_i.name"] = "Hide the interface in flight"
L["options.i_f_e_c.music_stories_while_passenger"] =
	"The music and stories while you are a passenger. The flight timer, "
		.. "the route and the countdown are separate and stay either way."
L["options.i_f_e_c.note"] = "Move it with %s."
L["options.i_f_e_c.passenger_console_stays"] =
	"You are a passenger. The console stays."
L["options.i_f_e_c.play_on.name"] = "Keep playing after landing"
L["options.i_f_e_c.player.name"] = "Play a programme in flight"
L["options.i_f_e_c.programme_carries_into_toolbox"] =
	"The programme carries on into the Toolbox's N.I.F.E.C. instead of "
		.. "stopping with the flight."
L["options.i_f_e_c.reader_scale.desc"] =
	"How much of a page to draw, against the 1024 it is drawn at. The "
		.. "magnifier still goes to actual size whatever this says."
L["options.i_f_e_c.reader_scale.name"] = "Magazine size"
L["options.i_f_e_c.scale.desc"] =
	"On top of the interface scale, like the action bars have their "
		.. "own."

L["options.minimap.blizz_header"] = "Blizzard's"
L["options.minimap.border.name"] = "Border strength"
L["options.minimap.combat"] = "In combat"
L["options.minimap.dark_band_around_inside"] =
	"The dark band around the inside of the map's edge, and the "
		.. "hairline on it. One texture, so one number."
L["options.minimap.desc"] =
	"A round map with a frosted rim, and a glass pill under it carrying "
		.. "the zone, your coordinates and the time - which swaps for a red "
		.. "dot and %s in a fight."
L["options.minimap.hide_blizzard.name"] = "Hide the minimap furniture"
L["options.minimap.minimap"] = "Minimap"
L["options.minimap.pill_header"] = "The pill"
L["options.minimap.pill_offset.name"] = "Gap below the map"
L["options.minimap.ring.name"] = "Border"
L["options.minimap.show_clock.name"] = "Clock"
L["options.minimap.show_coords.name"] = "Coordinates"
L["options.minimap.show_north.name"] = "North marker"
L["options.minimap.show_zone.name"] = "Zone name"
L["options.minimap.unavailable_inside_instance_where"] =
	"Unavailable inside an instance, where the pill simply drops them."

L["options.nameplates.always_show.desc"] =
	"Off, the game only draws a nameplate for your target and for "
		.. "whatever is fighting you - everything else keeps its own floating "
		.. "name in the game's font. This is what the V key toggles."
L["options.nameplates.always_show.name"] = "Always show them"
L["options.nameplates.badge_size.name"] = "Level disc"
L["options.nameplates.bar_height.name"] = "Health bar height"
L["options.nameplates.bar_width.name"] = "Health bar width"
L["options.nameplates.capsule"] = "The capsule"
L["options.nameplates.enabled.desc"] =
	"Turn this off and Blizzard's own plates come back - the module "
		.. "reskins them, it does not replace them."
L["options.nameplates.friendly"] = "Friendlies"
L["options.nameplates.friendly_names.name"] = "Draw friendlies as names"
L["options.nameplates.hide_blizzard.desc"] =
	"The one underneath ours. Off is the way back if a plate ever fails "
		.. "to draw."
L["options.nameplates.hide_blizzard.name"] = "Hide Blizzard's plate"
L["options.nameplates.max_distance.desc"] =
	"How far out the client bothers to make a nameplate. Past this "
		.. "there is no plate at all and the game draws its own floating name "
		.. "instead, so the boundary shows up as the lettering changing at a "
		.. "fixed distance. Twenty to forty-one is all the client offers."
L["options.nameplates.max_distance.name"] = "Range"
L["options.nameplates.nameplates"] = "Nameplates"
L["options.nameplates.neutral_bar_in_combat.name"] =
	"Neutral bars only in combat"
L["options.nameplates.off_friendly_player_s"] =
	"Off, a friendly player's name is blue - which is what 'friendly "
		.. "player' looks like everywhere else in this UI. On, your party take "
		.. "their class colours. Your party only."
L["options.nameplates.party_class_colors.name"] = "Class-colour party names"
L["options.nameplates.plain_shadowed_text_rather"] =
	"Plain shadowed text rather than a capsule: a class-coloured level "
		.. "pip and the name for a player, the name alone for an NPC. Off "
		.. "gives them the same capsule everything else wears. Either way the "
		.. "client is asked to show friendly nameplates at all, which it does "
		.. "not do by default."
L["options.nameplates.scale.desc"] =
	"On top of the global scale. A plate is read at thirty yards and "
		.. "the HUD at arm's length, so the size that suits one need not suit "
		.. "the other."
L["options.nameplates.yellow_plate_means_my"] =
	"A yellow plate means 'not my problem yet'. Off shows their health "
		.. "all the time."

L["options.onboard.already_done"] = "already done"
L["options.onboard.desc"] =
	"A tour of the interface, with a card for each stop. The rest of "
		.. "the world dims, one element at a time is lifted out of the dim, "
		.. "and the callout beside it explains what it is and how to use "
		.. "it.Every choice writes straight into your configuration the "
		.. "whenyou change it, so there is no Apply at the end and quitting "
		.. "half way through costs nothing.\\\\n\\\\nWhether it has run is "
		.. "remembered per %s, not per profile - the tour teaches the "
		.. "interface rather than a profile, and somebody who has seen it on "
		.. "their main has seen it."
L["options.onboard.enabled.name"] = "Offer it on a new character"
L["options.onboard.first_run"] = "First run"
L["options.onboard.run_header"] = "Run it now"
L["options.onboard.run_note"] =
	"Re-running clears this character's %s mark and starts at the "
		.. "welcome card. Your current palette, layout and Toolbox edge are "
		.. "untouched until you pick something else."

L["options.open.options_panel_needs_ace3"] =
	"the options panel needs the Ace3 libraries, which are missing from "
		.. "this install. %s still lists everything."

L["options.party_frames.four_capsules_party_same"] =
	"Four capsules for your party, in the same glass as your own frame."
L["options.party_frames.gap.name"] = "Gap between members"
L["options.party_frames.hide_blizzard.name"] = "Hide Blizzard's party frames"
L["options.party_frames.party_frames"] = "Party frames"
L["options.party_frames.placement"] =
	"The four slots are fixed and the group moves as one: unlock with "
		.. "%s and drag any part of the stack."
L["options.party_frames.slot_whose_member_has"] =
	"A slot whose member has gone leaves a gap rather than closing up. "
		.. "Re-anchoring a frame you can click to target is refused by the "
		.. "game in combat, which is often when somebody drops group - so the "
		.. "slots stay where you put them."

L["options.quest.adopt_watches.name"] = "Adopt Blizzard's watch list"
L["options.quest.auto_track.name"] = "Track everything automatically"
L["options.quest.clear.desc"] = "Forget every dismissed and tracked quest."
L["options.quest.clear.name"] = "Reset tracking"
L["options.quest.combat_collapse.name"] = "Fold in combat"
L["options.quest.hide_blizzard.name"] = "Hide Blizzard's tracker"
L["options.quest.max.name"] = "Most quests to show"
L["options.quest.quest_tracker"] = "Quest tracker"
L["options.quest.questlog.name"] = "Our quest log"
L["options.quest.replaces_game_s_own"] =
	"Replaces the game's quest log window. Off gives you Blizzard's "
		.. "back."
L["options.quest.show_level.name"] = "Show quest level"
L["options.quest.show_objectives.name"] = "Show objective lines"
L["options.quest.shrinks_heading_when_fight"] =
	"Shrinks to the heading when a fight starts."
L["options.quest.tinted_chip_front_each"] =
	"A tinted chip in front of each title, coloured by difficulty the "
		.. "same way the quest log colours it. Off, the titles start at the "
		.. "edge."
L["options.quest.track_header"] = "Tracking"
L["options.quest.tracker_shows_every_quest"] =
	"On, the tracker shows every quest in your log and you dismiss the "
		.. "ones you do not want. Off, it shows nothing until you shift-click "
		.. "a quest in the log."
L["options.quest.whatever_does_fit_reported"] =
	"Whatever does not fit is reported as '+N more' rather than "
		.. "silently dropped."
L["options.quest.whitelist_mode_only_blizzard"] =
	"Whitelist mode only. Blizzard caps its list at five."

L["options.resources.display.desc"] =
	"The shelf under your own frame carrying shards, runes, chi, combo "
		.. "points and the rest. In combat only drops the three-second grace "
		.. "after a change and the dimmed full-bar state with it."
L["options.resources.display.name"] = "Show the resource tray"
L["options.resources.enabled.desc"] =
	"Off removes the tray entirely. Characters with no secondary "
		.. "resource never have one either way."
L["options.resources.enabled.name"] = "Class resources"
L["options.resources.header"] = "Class resources"

L["options.threat.alarms.desc"] =
	"On your own state only, and never more than once every six "
		.. "seconds. This is the one that stops you from learning you have "
		.. "pulled aggro by getting hit."
L["options.threat.alarms.name"] = "Screen flash and ping"
L["options.threat.display.desc"] =
	"Rings only keeps the ring and drops the warnings written on the "
		.. "capsule - quieter, and it still tells you the number at a glance."
L["options.threat.display.name"] = "Show"
L["options.threat.enabled.desc"] =
	"The ring round your class pip, the warning on the capsule when a "
		.. "state is about to flip, and the disposition colour on a hostile "
		.. "nameplate."
L["options.threat.role.desc"] =
	"Everything here inverts on role: holding a mob is the good state "
		.. "for a tank and the bad one for everybody else. Classic Era's "
		.. "assigned roles are opt-in and usually say nothing at all, so "
		.. "Automatic reads your stance, form or aura instead.However, you can "
		.. "force this here."
L["options.threat.role.name"] = "Your role"
L["options.threat.threat"] = "Threat"

L["options.toolbox.addon_columns.name"] = "Addon list columns"
L["options.toolbox.desc"] =
	"A drawer that docks to the centre of any screen edge, with a rail "
		.. "that stays on screen when the drawer is shut.\\\\n\\\\nTo move it, "
		.. "%s and drag the rail: four targets appear, one per edge, and the "
		.. "one nearest the cursor is the one you get. It has four legal "
		.. "places rather than a position, because each edge is a different "
		.. "layout.\\\\n\\\\nThe edge it is docked to and whether it is open "
		.. "are remembered per %s rather than per profile - a drawer edge is a "
		.. "habit somebody forms on one character."
L["options.toolbox.grid_header"] = "Grids"
L["options.toolbox.libdatabroker_data_sources"] = "LibDataBroker data sources"
L["options.toolbox.look_header"] = "The overlay"
L["options.toolbox.look_note"] =
	"The drawer slides out %s the HUD. Nothing underneath moves or "
		.. "resizes; the covered strip is dimmed instead, so it reads as being "
		.. "behind rather than merely dark."
L["options.toolbox.only_latency_fps_polled"] =
	"Only latency and FPS are polled, and only while the drawer is "
		.. "open; the rest follow their own events."
L["options.toolbox.over"] = "over"
L["options.toolbox.scrim.name"] = "Dim the covered strip"
L["options.toolbox.tile_columns.name"] = "Setting tile columns"
L["options.toolbox.unlock_frames"] = "unlock frames"
L["options.toolbox.widget_columns.name"] = "Widget columns"
L["options.toolbox.widgets_header"] = "Widgets"
L["options.toolbox.widgets_note"] =
	"The six widgets are published as %s rather than drawn straight "
		.. "onto the panel. Two consequences: anything that displays LDB - "
		.. "Titan, Bazooka, ChocolateBar - shows AetherUI's numbers without "
		.. "being told, and anyone can write a widget in about ten lines."

L["options.tooltips.anchoring"] = "Anchoring"
L["options.tooltips.caution"] = "These four change the tooltip's text"
L["options.tooltips.class_color_names.desc"] =
	"On by default, to agree with the unit frames. Off is the deck's "
		.. "own treatment: one blue for every friendly player."
L["options.tooltips.class_color_names.name"] = "Class-colour player names"
L["options.tooltips.colour"] = "Colour"
L["options.tooltips.content"] = "Unit header"
L["options.tooltips.corner.name"] = "Corner radius"
L["options.tooltips.cursor_items.name"] =
	"Item and spell tooltips follow the cursor"
L["options.tooltips.defer_to_level_readers.name"] =
	"...unless an addon is reading that line"
L["options.tooltips.elite_chip.name"] = "Elite chip"
L["options.tooltips.health_values.name"] = "Health numbers"
L["options.tooltips.level_badge.desc"] =
	"Moves the level out of the type line and into a disc beside the "
		.. "name. Declines silently if the line does not parse."
L["options.tooltips.level_badge.name"] = "Level badge"
L["options.tooltips.lore_gold.desc"] =
	"Only lines the client left white - anything another addon coloured "
		.. "keeps its colour."
L["options.tooltips.lore_gold.name"] = "Lore gold on spell text"
L["options.tooltips.only_where_nothing_else"] =
	"Only where nothing else asked for a position - a bag slot or a "
		.. "merchant row keeps the anchor it chose."
L["options.tooltips.quality_border.name"] = "Quality rim on items"
L["options.tooltips.reaction_word.desc"] =
	"\"Humanoid\" becomes \"Humanoid - Hostile\"."
L["options.tooltips.reaction_word.name"] = "Append the reaction"
L["options.tooltips.restyle_fonts.desc"] =
	"Restyles the client's tooltip fonts, so every line - including "
		.. "lines other addons add - comes out in Outfit."
L["options.tooltips.restyle_fonts.name"] = "Aether typography"
L["options.tooltips.unit_anchor.desc"] =
	"World mouseovers go to the corner instead of following the mouse. "
		.. "Drag it in unlock mode. Only affects tooltips that took the "
		.. "default anchor."
L["options.tooltips.unit_anchor.name"] = "Anchor unit tooltips"

L["options.unit_frames.capsule_pet_own_place"] =
	"A capsule for your pet, with its own place on screen. A hunter's "
		.. "pet also wears its mood on the orb's rim."
L["options.unit_frames.cast_header"] = "Cast bars"
L["options.unit_frames.cast_note"] =
	"Both cast bars float free on their own movers."
L["options.unit_frames.cast_width.name"] = "Cast bar width"
L["options.unit_frames.classic_era_does_report"] =
	"Classic Era now reports other units' casts natively."
L["options.unit_frames.gap.name"] = "Gap between player and target"
L["options.unit_frames.hide_blizzard.name"] = "Hide Blizzard's frames"
L["options.unit_frames.off_draws_class_tinted"] =
	"Off draws the class-tinted level disc the concept uses."
L["options.unit_frames.orb_size.name"] = "Orb size"
L["options.unit_frames.pet_scale.desc"] =
	"On top of the interface scale, the way the console and the "
		.. "nameplates have their own."
L["options.unit_frames.pet_scale.name"] = "Pet frame size"
L["options.unit_frames.reaction_tint.name"] = "Colour the target by reaction"
L["options.unit_frames.show_cast_bar.name"] = "Player cast bar"
L["options.unit_frames.show_pet.name"] = "Pet frame"
L["options.unit_frames.show_portrait.name"] = "Portrait in the orb"
L["options.unit_frames.show_target_cast_bar.name"] = "Target cast bar"
L["options.unit_frames.target_s_capsule_rim"] =
	"The target's capsule rim, orb ring and cast bar take their "
		.. "reaction - red for hostile, amber for neutral, green for friendly."
L["options.unit_frames.unit_frames"] = "Unit frames"

L["options.x_p.show_text.name"] = "Show the readout"
L["options.x_p.text_side.name"] = "Readout corner"
L["options.x_p.which_end_hairline_readout"] =
	"Which end of the hairline the readout sits above."
L["options.x_p.xp_hairline"] = "XP hairline"

-- party -------------------------------------------------------------------

L["party.build_handle.party_dock_s"] = "party dock -> %s"
L["party.build_handle.slot_s"] = "slot %s"

L["party.is_leader.key"] = "Role Check"

-- playback ----------------------------------------------------------------

L["playback.poll.ifec_programme_stopped_boundary"] =
	"ifec: the programme stopped at a boundary"

-- player ------------------------------------------------------------------

L["player.build.programme_complete"] = "Programme complete."
L["player.build.up_next"] = "UP NEXT"

L["player.paint.landing_s"] = "LANDING %s"
L["player.paint.outlined_queued"] = "outlined = queued"
L["player.paint.programme_fills_s_s"] = "programme fills %s of %s"

L["player.paint_up_next.queued"] = "queued by you"

-- presets -----------------------------------------------------------------

L["presets.set_bars.blurb"] =
	"Unitframes in the top left corner as they're laid out in the "
		.. "classic UI."
L["presets.set_bars.blurb2"] =
	"Unitframes in the center where most of the action is."
L["presets.set_bars.blurb3"] =
	"Unitframes positioned towards the bottom and out to the corners."
L["presets.set_bars.label"] = "Classic Corner"
L["presets.set_bars.label2"] = "Centre focus"
L["presets.set_bars.label3"] = "Bottom Corners"

-- questlog ----------------------------------------------------------------

L["questlog.ask_abandon.abandon_s"] = "Abandon %s?"
L["questlog.ask_abandon.quest_longer_log"] =
	"that quest is no longer in your log."
L["questlog.ask_abandon.will_lose_s"] = "You will lose: %s"

L["questlog.build_header.quest_log"] = "Quest Log"

L["questlog.build_panes.quest_selected"] = "No quest selected."

L["questlog.confirm_abandon.quest_longer_log_nothing"] =
	"that quest is no longer in your log - nothing was abandoned."

L["questlog.frequency.daily"] = "Daily"
L["questlog.frequency.daily_s"] = "Daily %s"
L["questlog.frequency.weekly"] = "Weekly"
L["questlog.frequency.weekly_s"] = "Weekly %s"

L["questlog.refresh_detail.required_s"] = "Required: %s"
L["questlog.refresh_detail.reward_s"] = "Reward: %s"

L["questlog.reward_card_click.reward_still_loading_try"] =
	"that reward is still loading - try again in a moment."

-- questtracker ------------------------------------------------------------

L["questtracker.behind_fold_d"] = "%d hidden by a folded zone in the quest log"

-- resources ---------------------------------------------------------------

L["resources.demo.chi"] = "Monk · chi"
L["resources.demo.combo"] = "Rogue · combo points"
L["resources.demo.eclipse"] = "Druid · eclipse"
L["resources.demo.embers"] = "Warlock · burning embers"
L["resources.demo.fury"] = "Warlock · demonic fury"
L["resources.demo.holy"] = "Paladin · holy power"
L["resources.demo.off"] = "resource preview off"
L["resources.demo.orbs"] = "Priest · shadow orbs"
L["resources.demo.runes"] = "Death Knight · runes and runic power"
L["resources.demo.shards"] = "Warlock · soul shards"
L["resources.demo.showing_s"] = "resource preview: %s"

-- toolbox -----------------------------------------------------------------

L["toolbox.build.aetherui_settings"] = "AetherUI settings"

L["toolbox.build_content.notes"] = "Notes"

L["toolbox.build_dock_handle.can_t_re_dock"] =
	"can't re-dock the toolbox in combat."
L["toolbox.build_dock_handle.toolbox"] = "TOOLBOX"

L["toolbox.on_config_changed.bag_space"] = "Bag space"

L["toolbox.refresh_addons.quest_log"] = "Quest log"

L["toolbox.refresh_mail_rows.senders_show_after_mailbox"] =
	"Senders show after a mailbox visit"
L["toolbox.refresh_mail_rows.unread_mail"] = "No unread mail"

L["toolbox.refresh_widgets.keybind_mode"] = "Keybind mode"
L["toolbox.refresh_widgets.tip"] =
	"Fades the interface away when you stand still, and brings it back "
		.. "the when something happens. Your character sits down and the "
		.. "camera pulls back for the a Zen moment."
L["toolbox.refresh_widgets.tip2"] =
	"Plays your installed packs' music and stories while you are a "
		.. "passenger. The flight timer, the route and the countdown are "
		.. "separate and stay either way."
L["toolbox.refresh_widgets.tip3"] =
	"Hover an action button and press a key to bind it. Keys go into "
		.. "Blizzard's own binding set, so they survive this addon being "
		.. "disabled and show up in the keybinding panel."
L["toolbox.refresh_widgets.unlock_frames"] = "Unlock frames"

-- tooltips ----------------------------------------------------------------

L["tooltips.diagnose.absent_client_s"] = "absent on this client: %s"
L["tooltips.diagnose.level_badge_s"] = "level badge %s"
L["tooltips.diagnose.level_badge_s_override"] =
	"level badge %s (override: %s is running and reads that line)"

-- tour --------------------------------------------------------------------

L["tour.adopt_from.body"] =
	"One palette colours your interface — tap to try each live; "
		.. "everything recolours at once."
L["tour.adopt_from.body2"] =
	"Three starting layouts — watch the unit frames move as you tap. "
		.. "You can fine-tune every frame later."
L["tour.adopt_from.body3"] =
	"Addons, settings and N.I.F.E.C. — all present from the Toolbox. "
		.. "Pick which edge it lives on."
L["tour.adopt_from.body4"] =
	"After a while of quiet the HUD fades to a calm Zen state,Leaving "
		.. "only a clock and the zone you are in. Pick how long before it "
		.. "starts — or never."
L["tour.adopt_from.body5"] =
	"Cooldowns, charges and range all draw ON the bar icons."
L["tour.adopt_from.body6"] =
	"The tracker folds itself away the moment combat starts and returns "
		.. "when it ends — like this."
L["tour.adopt_from.body7"] =
	"All your bags pour into one organised panel — gear, potions, trade "
		.. "goods, junk, each under its own heading."
L["tour.adopt_from.body8"] =
	"Manage your threat BEFORE trouble: gold means act now, red means "
		.. "you've pulled. What counts as trouble flips with your role.(i.e "
		.. "Tank vs DPS & Healer.)"
L["tour.adopt_from.body9"] =
	"Music, podcasts and some truly disreputable gossip rags, timed to "
		.. "your route. Boards at takeoff — and N.I.F.E.C. plays it on the "
		.. "ground, from the Toolbox."
L["tour.adopt_from.head"] = "Choose the colour scheme you like."
L["tour.adopt_from.head2"] = "Where should everything live?"
L["tour.adopt_from.head3"] = "A useful place to keep tools."
L["tour.adopt_from.head4"] = "Take a moment of meditation."
L["tour.adopt_from.head5"] = "Your bars tell you what you need."
L["tour.adopt_from.head6"] = "Tracking quests when you need them."
L["tour.adopt_from.head7"] = "One organised and tidy bag."
L["tour.adopt_from.head8"] = "Manage your threat."
L["tour.adopt_from.head9"] = "Long flight? We've got you."
L["tour.adopt_from.name"] = "YOUR PALETTE"
L["tour.adopt_from.name2"] = "YOUR LAYOUT"
L["tour.adopt_from.name3"] = "THE TOOLBOX"
L["tour.adopt_from.name4"] = "ZEN MODE"
L["tour.adopt_from.name5"] = "ACTION BARS"
L["tour.adopt_from.name6"] = "QUEST TRACKER"

L["tour.build_nav.back"] = "Back"
L["tour.build_nav.next"] = "Next"

L["tour.build_skip.skip_tour_keep_defaults"] = "Skip tour — keep defaults"

L["tour.build_toast.resume"] = "Resume"

L["tour.ifec_demo.nothing_installed_yet"] = "Nothing installed yet"

L["tour.layout_control.n1_min"] = "1 min"
L["tour.layout_control.n5_min"] = "5 min"

L["tour.quests_demo.combat_folded"] = "in combat — folded"
L["tour.quests_demo.tracking"] = "tracking"
L["tour.quests_demo.wanted_hogger"] = "Wanted: Hogger"

L["tour.show_finish.all_set"] = "ALL SET"
L["tour.show_finish.done"] = "Done"
L["tour.show_finish.hud_way_go_break"] = "Your UI is ready. Go try it out."

L["tour.show_welcome.n1_minute"] = "~1 minute"
L["tour.show_welcome.quieter_glassier_way_play"] =
	"A modern UI for Classic WoW"
L["tour.show_welcome.skip_tour"] = "Skip the tour"
L["tour.show_welcome.whole_interface_rebuilt_calm"] =
	"A modern UI rebuilt as calm dark glass."

L["tour.start.during_fight_try_again"] =
	"not during a fight - try again when it is over."

L["tour.threat_demo.eased_off_quiet_again"] = "eased off — quiet again"
L["tour.threat_demo.trouble_coming"] = "trouble coming"

L["tour.toolbox_control.tap_edge"] = "tap an edge"

-- tracker -----------------------------------------------------------------

L["tracker.build.q_u_e_s"] = "Q U E S T S"

L["tracker.diagnose.quest_tracker_text_window"] =
	"quest tracker: in the text window - Ctrl+A then Ctrl+C to copy"

L["tracker.navigate.can_t_route_quest"] = "can't route to that quest."
L["tracker.navigate.quest"] = "the quest"
L["tracker.navigate.routing_s"] = "routing to %s."

-- zen ---------------------------------------------------------------------

L["zen.tick.zen_failed_put_interface"] =
	"zen failed and put the interface back:"
