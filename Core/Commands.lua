--[[--------------------------------------------------------------------------
	AetherUI :: Commands

	/aether — everything is reachable from chat. A proper options panel comes
	later; until then this is the whole control surface, which is honestly enough
	while the layout is still moving.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local function usage()
	A:Print(A.Hi("/aether") .. " on its own opens the options panel. Everything below"
		.. " still works and is quicker for one number.")
	local lines = {
		A.Hi("/aether config") .. "  ·  the options panel (or just " .. A.Hi("/aether") .. ")",
		A.Hi("/aether bind") .. "  ·  hover a button, press a key",
		A.Hi("/aether unlock") .. "  ·  drag frames into place",
		A.Hi("/aether lock"),
		A.Hi("/aether reset") .. "  ·  forget all frame positions",
		A.Hi("/aether skin") .. " <midnight|dawn|noon|dusk>",
		A.Hi("/aether scale") .. " <0.6-1.6|fit>  ·  fit = the size it was drawn",
		A.Hi("/aether fade") .. " <on|off|delay N|idle 0-1>  ·  stage one, the dim",
		A.Hi("/aether zen") .. " <on|off|delay N|afk on/off|test>  ·  stage two",
		A.Hi("/aether zen") .. " <frost|plates|audio|sit|camera> on/off  ·  the mode itself",
		A.Hi("/aether zen zoom") .. " N  ·  the shot, live",
		A.Hi("/aether zen") .. " <track NAME|preview>  ·  the music",
		A.Hi("/aether shadow") .. " <0-1>  ·  ambient shadow opacity",
		A.Hi("/aether health") .. " <class|deck>  ·  bar colour for players",
		A.Hi("/aether bar") .. " <list · N on/off · N buttons/rows/page/scale V · size/spacing/font N>",
		A.Hi("/aether quests") .. " <fold|auto|objectives|clear>  ·  the quest tracker",
		A.Hi("/aether module") .. " <name> <on|off>",
		A.Hi("/aether status"),
		A.Hi("/aether diag") .. "  ·  why is a Blizzard frame still on screen",
		A.Hi("/aether auras") .. " <refresh>  ·  what the aura API is actually saying",
		A.Hi("/aether chat") .. " <reskin · where · lines/badges on|off · whispers on|off>",
		A.Hi("/aether bags") .. " <open · sort · sell · junk on|off>  ·  what the container API is saying",
		A.Hi("/aether tooltips") .. " <cursor|anchor|badge|sweep>  ·  which tooltips got skinned",
		A.Hi("/aether toolbox") .. " <dock left/right/top/bottom · open · close · pin NAME>",
		A.Hi("/aether panels") .. " <dump NAME|measure [NAME]|diag>  ·  what a window is made of",
		A.Hi("/aether threat") .. " probe  ·  what the threat API answers, in a box you can copy",
		A.Hi("/aether resources") .. " demo  ·  step the class resource tray through every class",
		A.Hi("/aether ifec") .. " [reset]  ·  content packs, what is playing, forget history",
		A.Hi("/aether errors") .. " <diag|clear>  ·  errors, or diag, in a box you can copy out of",
	}
	for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("   " .. l) end
end

local function status()
	A:Print("v" .. A.version .. "  ·  skin " .. A.Val(A.Palette.current) .. "  ·  scale "
		.. string.format("%.2f", A.db.profile.scale)
		.. "  ·  pixel " .. string.format("%.3f", A.pixel))
	for name, m in A:IterateModules() do
		DEFAULT_CHAT_FRAME:AddMessage(string.format("   %s  %s%s",
			m.enabled and A.Good("on ") or A.Bad("off"), name,
			m.lastError and ("  " .. A.Bad(m.lastError)) or ""))
	end
end

local function say(fmt, ...)
	DEFAULT_CHAT_FRAME:AddMessage(select("#", ...) > 0 and string.format(fmt, ...) or fmt)
end

--- Walk a frame up to UIParent. This is the useful one: Blizzard has reshuffled
--  the action bar hierarchy across versions, so rather than trusting a list of
--  container names, ask a button what it is actually parented to.
local function ancestry(name)
	local f = _G[name]
	if not f then return A.Dim("absent") end
	local parts, cur, depth = {}, f, 0
	while cur and depth < 8 do
		local n = (cur.GetName and cur:GetName()) or "<anon>"
		local shown = cur.IsShown and cur:IsShown()
		parts[#parts + 1] = (shown and A.Bad or A.Good)(n)
		cur = cur.GetParent and cur:GetParent()
		depth = depth + 1
	end
	return table.concat(parts, " < ")
end

--- Where the chat window is, where it should be, and who last argued about it.
--
--  Its own function because it is wanted in two places: on its own from
--  `/aether chat where`, and inside the diag that goes in a box you can copy
--  out of - which is the one that gets pasted into a bug report.
function A:ChatWhere()
	local C = A:GetModule("chat")
	local cf = _G.ChatFrame1
	if not C or not cf then A:Print(L.cmd.chat_where.chat_window_report) return end

	local entry = A.Movers and A.Movers.registry and A.Movers.registry.chat
	local saved = A.db.profile.anchors and A.db.profile.anchors.chat
	local want = (saved and saved.point and saved) or (entry and entry.default)

	local point, _, relPoint, x, y = cf:GetPoint(1)
	say("   chat is at %s %s %.0f,%.0f", tostring(point), tostring(relPoint),
		x or 0, y or 0)
	if want then
		say("   we want   %s %s %.0f,%.0f  (%s)", tostring(want.point),
			tostring(want.relPoint or want.point), want.x or 0, want.y or 0,
			saved and "saved" or "default")
	end

	local moves = C.moves or {}
	if #moves == 0 then
		say("   nothing has moved it since login")
		return
	end

	say("   %d move%s caught, newest first:", #moves, #moves == 1 and "" or "s")
	for i, m in ipairs(moves) do
		say("      %d. to %s %.0f,%.0f  by %s", i, tostring(m.point),
			m.x or 0, m.y or 0, tostring(m.by))
	end
end

-- ---------------------------------------------------------------------------
-- what is this window made of
--
-- Every panel so far was built by reading Blizzard's own source for this
-- flavour, which is the only way to know what a frame's parts are called and
-- which of them carry the picture rather than the chrome.
--
-- That runs out when the source is not to hand: Blizzard_Communities is not in
-- the reference tree, and the guild window on this client is Communities and not
-- the FriendsFrame pane the old XML still defines. Guessing frame names is
-- exactly what this addon does not do, so it asks the client instead.
-- ---------------------------------------------------------------------------

local DUMP_DEPTH = 2

--- What its parent calls this part, if it calls it anything.
--
--  ALMOST NOTHING in a modern Blizzard window has a global name. A dump of
--  CommunitiesFrame came back with eight named things in six hundred lines and
--  <anonymous> for the rest, which is a report nobody can act on - you cannot
--  reach a frame you cannot name.
--
--  What they have instead is a parentKey, which the client assigns as a plain
--  field on the parent, so the field is what has to be reported. That is also
--  the key Reskin.Element takes, which makes the answer directly usable.
local function KeyOf(parent, part)
	if type(parent) ~= "table" then return nil end
	local ok, key = pcall(function()
		for k, v in pairs(parent) do
			if v == part and type(k) == "string" then return k end
		end
	end)
	return ok and key or nil
end

--- How to refer to something: its global name, or its parentKey, or neither.
local function Handle(parent, part, name)
	if name and name ~= "" then return name end
	local key = KeyOf(parent, part)
	return key and ("." .. key) or "<anonymous>"
end

--- One line about a region: what it is, which layer, and what it is drawing.
local function DumpRegions(frame, pad)
	if not frame.GetRegions then return end
	local got = { pcall(frame.GetRegions, frame) }
	if not got[1] then return end

	for i = 2, #got do
		local r = got[i]
		local kind = r.GetObjectType and r:GetObjectType() or "?"
		local who = Handle(frame, r, r.GetName and r:GetName())

		if kind == "Texture" or kind == "MaskTexture" then
			-- The ATLAS as well as the file. Modern art is nearly all atlases,
			-- and an atlas has a name a person can read where a file is a
			-- numeric id that tells you nothing at all.
			local okA, atlas = pcall(function() return r.GetAtlas and r:GetAtlas() end)
			local tex = r.GetTexture and r:GetTexture()
			say("%s. %s %s %s  %s%s", pad, kind,
				tostring((r.GetDrawLayer and r:GetDrawLayer()) or "?"), who,
				tostring((okA and atlas) or tex or "-"),
				(r.IsShown and not r:IsShown()) and "  (hidden)" or "")
		else
			say("%s. %s %s  %q", pad, kind, who,
				tostring((r.GetText and r:GetText()) or ""):sub(1, 40))
		end
	end
end

--- The frame, its regions and its children, as far down as DUMP_DEPTH.
local function DumpFrame(frame, pad, depth, parent)
	local name = frame.GetName and frame:GetName()
	local w = frame.GetWidth and frame:GetWidth() or 0
	local h = frame.GetHeight and frame:GetHeight() or 0

	say("%s%s  [%s]  %.0fx%.0f%s", pad, Handle(parent, frame, name),
		tostring(frame.GetObjectType and frame:GetObjectType() or "?"), w, h,
		(frame.IsShown and not frame:IsShown()) and "  (hidden)" or "")

	DumpRegions(frame, pad)

	if depth <= 0 or not frame.GetChildren then return end
	local kids = { pcall(frame.GetChildren, frame) }
	if not kids[1] then return end

	for i = 2, #kids do
		DumpFrame(kids[i], pad .. "   ", depth - 1, frame)
	end
end

--- Is this global a frame we can safely ask about?
--
--  pcall throughout: a forbidden frame errors on being asked anything at all,
--  and a sweep of _G meets several.
local function AsFrame(v)
	if type(v) ~= "table" then return nil end
	local ok, kind = pcall(function() return v.GetObjectType and v:GetObjectType() end)
	if not ok or not kind then return nil end
	local okf, forbidden = pcall(function() return v.IsForbidden and v:IsForbidden() end)
	if not okf or forbidden then return nil end
	return v
end

--- Find a frame by name, WITHOUT CARING ABOUT CASE, and offer near misses.
--
--  The dispatcher lower-cases every argument - every other command compares
--  words, so that is right for them and wrong here, because a frame name is a
--  case-sensitive global. `communitiesframe` found nothing and said so, which
--  read as "that window does not exist" rather than "you typed it in lower
--  case, as this addon required you to".
--
--  So the name is matched case-insensitively, and a fragment lists what it
--  could have meant - which is the more useful command anyway when the whole
--  question is what a window you cannot read the source of is called.
local function FindFrame(want)
	local exact = _G[want]
	if AsFrame(exact) then return exact, want end

	local lower = want:lower()
	local near = {}

	for key, value in pairs(_G) do
		if type(key) == "string" then
			local k = key:lower()
			if k == lower and AsFrame(value) then return value, key end
			if k:find(lower, 1, true) and AsFrame(value) then
				near[#near + 1] = key
			end
		end
	end

	table.sort(near)
	return nil, nil, near
end

--- What the panel layout can SEE of a window's rows, and what it makes of it.
--
--  The tree above says what the client built. This says what our own layout
--  thinks of it, which is a different question and the one that goes wrong:
--  a row is laid out from what is VISIBLE and OURS, and both of those can be
--  true of something you cannot see anywhere on the window.
--
--  The friends window is why it exists. Add Friend and Send Message came out
--  a button's width too far apart, one hanging off each side of the glass,
--  and a dump of the tree said nothing at all about it - because the widget
--  taking the room between them was RaidFrameConvertToRaidButton, whose pane
--  has no parent, is never drawn, and answers yes to IsVisible.
local function DumpRows(frame, name)
	local PN = A.GetModule and A:GetModule("panels")
	local entry = PN and PN.ENTRY and PN.ENTRY[name]
	if not entry then return end

	--- The first ancestor with a name, and whether the window is among them.
	local function lineage(w)
		local f, hops, ours = w, 0, false
		while f and hops < 8 do
			if f == frame then ours = true break end
			f = f.GetParent and f:GetParent()
			hops = hops + 1
		end
		local up = w.GetParent and w:GetParent()
		return ours, (up and up.GetName and up:GetName()) or "none"
	end

	local function row(tag, list)
		for _, key in ipairs(list or {}) do
			local w = type(key) == "string" and PN.Part(key) or nil
			if not w then
				say("   %-5s %-34s %s", tag, tostring(key), A.Dim("not found"))
			else
				local ours, up = lineage(w)
				local shown = w.IsShown and w:IsShown()
				local vis = w.IsVisible and w:IsVisible()
				say("   %-5s %-34s %.0fx%.0f  %s %s %s", tag, tostring(key),
					(w.GetWidth and w:GetWidth()) or 0,
					(w.GetHeight and w:GetHeight()) or 0,
					shown and "shown" or A.Dim("hidden"),
					vis and "visible" or A.Dim("unseen"),
					ours and L.cmd.dump_rows.ours or A.Bad(A.F(L.cmd.dump_rows.ours_parent_s, up)))
			end
		end
	end

	say(" ")
	say("what the layout can see  ·  a row takes only what is VISIBLE and OURS")
	for _, side in ipairs({ "left", "right", "mid" }) do
		row("row", entry.row and entry.row[side])
	end
	for _, side in ipairs({ "left", "right", "mid", "under" }) do
		row("strip", entry.actions and entry.actions[side])
	end
end

--- `/aether panels dump <FrameName>`, into the box you can copy out of.
function A:DumpPanel(name)
	name = (name or ""):gsub("%s", "")
	-- Recorded so the suite can prove a frame name reaches here with its
	-- capitals intact; the dispatcher used to fold the whole tail.
	A.__lastDumpName = name
	if name == "" then
		A:Print(A.Hi("/aether panels dump <FrameName>") .. "  ·  part of a name"
			.. " will do, and it will list what it could have meant.")
		return
	end

	local frame, found, near = FindFrame(name)

	if not frame then
		A:Print(A.F(L.cmd.dump_panel.frame_called_s_open,
			A.Val(name)))
		for i = 1, math.min(#(near or {}), 15) do
			say("   " .. A.Val("%s"), near[i])
		end
		if near and #near > 15 then
			say("   ...and %d more", #near - 15)
		end
		return
	end

	name = found

	local text = A.Errors:Capture(function()
		-- THE BUILD THAT PRODUCED IT, first line, like the error box's header.
		-- A dump ran against the copy still in memory once and the missing
		-- parentKeys read as "the client does not have them" rather than "you
		-- have not reloaded". Lua loads at reload; a file on disk is not a build
		-- that is running.
		say("%s  ·  AetherUI %s  ·  %s", name, tostring(A.version or "?"),
			date and date("%Y-%m-%d %H:%M") or "")
		say("a leading dot is a parentKey, which is what Reskin.Element takes")
		DumpFrame(frame, "", DUMP_DEPTH, frame.GetParent and frame:GetParent())
		DumpRows(frame, name)
	end)
	A.Errors:ShowText(text)
end

local function diag()
	A:Print(A.F(L.cmd.diag.diagnostics_s_s,
		A.Bad(L.cmd.diag.red_shown), A.Good(L.cmd.diag.green_hidden)))

	-- WHO IS ACTUALLY DELIVERING OTHER PEOPLE'S CASTS.
	--
	-- Classic Era has never fired UNIT_SPELLCAST_* for anything but the player,
	-- so everything else comes from LibClassicCasterino reading the combat log.
	-- Both paths are wired and native is tried first, which means the day the
	-- client starts reporting it the library stops mattering - silently. This is
	-- the line that says which of the two is true, after a fight.
	do
		local c = A.castSource or {}
		say("   casts for others  native %d  ·  library %d  ·  "
			.. "library ONLY %d", c.native or 0, c.lib or 0, c.only or 0)
	end

	for name, m in A:IterateModules() do
		say("   %s %s%s", m.enabled and A.Good("on ") or A.Bad("off"), name,
			m.lastError and ("  " .. A.Bad(m.lastError)) or "")
	end

	local AB = A:GetModule("actionbars")
	if AB then
		local abCfg = A.Config:Module("actionbars")
		say("   hideBlizzard = %s   bars built = %d",
			tostring(abCfg.hideBlizzard), #(AB.bars or {}))

		-- Nothing follows GetActionBarPage() any more, so there is no page state
		-- to report and no page drift to explain. Each bar names its own source.
		for _, bar in ipairs(AB.bars or {}) do
			say("      %s %-6s %s%d button%s · %d row%s",
				(bar.dock:IsShown() and A.Good or A.Dim)(
					string.format("%-7s", bar.id)), bar.kind,
				bar.kind == "action" and ("actions " .. ((bar.page - 1) * 12 + 1)
					.. "-" .. (bar.page * 12) .. " · ") or "",
				#bar.buttons, #bar.buttons == 1 and "" or "s",
				bar.rows or 1, (bar.rows or 1) == 1 and "" or "s")
		end

		-- Who actually owns the keys. If a row does not say CLICK AetherUI...,
		-- that key is going somewhere else.
		local bar1 = AB.bars and AB.bars[1]
		if GetBindingKey and GetBindingAction and bar1 then
			local mine, stolen = 0, {}
			for i = 1, #(bar1.buttons or {}) do
				local key = GetBindingKey("ACTIONBUTTON" .. i)
				if key and key ~= "" then
					local owner = GetBindingAction(key, true) or "?"
					if owner:find("AetherUI", 1, true) then
						mine = mine + 1
					else
						stolen[#stolen + 1] = key .. " -> " .. owner
					end
				end
			end
			say("   keys: %d of %d point at our buttons", mine, #(bar1.buttons or {}))
			for _, line in ipairs(stolen) do
				say("      " .. A.Bad("%s"), line)
			end
		end

	end

	-- The chat window's position, and anything that has argued about it. Here
	-- rather than only behind `/aether chat where` because this is the report
	-- that gets pasted into a bug report, and "it jumps back" has now cost four
	-- fixes for want of the name of whatever does it.
	local Cw = A:GetModule("chat")
	if Cw and Cw.enabled then A:ChatWhere() end

	local MMd = A:GetModule("minimap")
	if MMd then
		-- The collected-button dump moved to `/aether toolbox`, which is where
		-- the launchers live now. This module only clears Blizzard's furniture.
		if MMd.hideReport then
			local names = {}
			for k in pairs(MMd.hideReport) do names[#names + 1] = k end
			table.sort(names)
			for _, k in ipairs(names) do
				if MMd.hideReport[k] == "STILL SHOWN" then
					say("      " .. A.Bad("%s still shown"), k)
				end
			end
		end
	end

	local AU = A:GetModule("auras")
	if AU and AU.trays then
		for _, t in ipairs(AU.trays) do
			local d = t.display
			say("   %s: %s, %d shown, %d per row, cap %d",
				t.key, t.enabled and "on" or A.Dim("off"),
				d.active, d.opts.perRow or 0, d.opts.max or 0)
		end
	end
	if AU and AU.playerBuffs then
		local wired, failed, named = 0, 0, 0
		for _, p in ipairs(AU.playerBuffs.tiles) do
			if p.click then wired = wired + 1 end
			if p.clickFailed then failed = failed + 1 end
			if p.click and p.click._macroName then named = named + 1 end
		end
		say("   buff cancel: %d tiles, %d wired, %d with a macro, %d failed to build",
			#AU.playerBuffs.tiles, wired, named, failed)
		local p1 = AU.playerBuffs.tiles[1]
		if p1 and p1.click then
			say("      tile 1: type2=%s  macrotext2=%s",
				tostring(p1.click:GetAttribute("type2")),
				tostring(p1.click:GetAttribute("macrotext2")))
		end
	end

	if AB and AB.hideReport then
		say("   banish results:")
		local names = {}
		for n in pairs(AB.hideReport) do names[#names + 1] = n end
		table.sort(names)
		for _, n in ipairs(names) do
			local r = AB.hideReport[n]
			local ink = (r == "hidden") and A.Good or (r == "absent" and A.Dim or A.Bad)
			say("      %-34s %s", n, ink(r))
		end
	else
		say("   " .. A.Bad(L.common.banish_report_hideblizzard_never))
	end
end

--- What the client says about your party, and what we drew from it.
--
--  Written because three rounds went by guessing why a raid mark was not on
--  screen. The answers are all one-liners from the client and none of them can
--  be read from outside the game, so a report that puts them next to what we
--  actually drew turns a guessing game into one command.
local function partyDiag(say)
	local PF = A:GetModule("partyframes")
	if not PF then
		say("   " .. A.Bad(L.cmd.party_diag.party_module))
		return
	end

	say("   enabled: %s   stack: %s   members: %s",
		PF.enabled and A.Good("yes") or A.Bad("no"),
		PF.stack and A.Good("built") or A.Bad("none"),
		A.Val(tostring(GetNumGroupMembers and GetNumGroupMembers() or 0)))

	if PF.hideReport then
		say("   Blizzard's frames:")
		local names = {}
		for n in pairs(PF.hideReport) do names[#names + 1] = n end
		table.sort(names)
		for _, n in ipairs(names) do
			local r = PF.hideReport[n]
			local ink = (r == "hidden") and A.Good or (r == "absent" and A.Bad or A.Bad)
			say("      %-20s %s", n, ink(r))
		end
	else
		say("   " .. A.Bad(L.common.banish_report_hideblizzard_never))
	end

	-- Per member: what the client answers, and whether the mark is up. The two
	-- columns disagreeing is the whole diagnosis.
	say("   %-12s %-4s %-8s %-8s %-6s %s", "unit", "lead", "mark", "role", "pvp", "drawn")
	for _, f in ipairs(PF.frames or {}) do
		local u = f.unit
		if UnitExists(u) then
			local drawn = {}
			if f.crown and f.crown:IsShown()  then drawn[#drawn + 1] = "crown" end
			if f.marker and f.marker:IsShown() then drawn[#drawn + 1] = "mark" end
			if f.role and f.role:IsShown()    then drawn[#drawn + 1] = "role" end
			if f.pvp and f.pvp:IsShown()      then drawn[#drawn + 1] = "pvp" end
			say("   %-12s %-4s %-8s %-8s %-6s %s",
				u,
				tostring(UnitIsGroupLeader and UnitIsGroupLeader(u) or false),
				tostring(GetRaidTargetIndex and GetRaidTargetIndex(u)),
				tostring(UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)),
				tostring(UnitIsPVP and UnitIsPVP(u)),
				#drawn > 0 and A.Good(table.concat(drawn, ",")) or A.Dim("nothing"))
		end
	end

	-- And your own, which is a different frame and a different module.
	local UFm = A:GetModule("unitframes")
	local me = UFm and UFm.player
	if me then
		local drawn = {}
		if me.crown and me.crown:IsShown()  then drawn[#drawn + 1] = "crown" end
		if me.marker and me.marker:IsShown() then drawn[#drawn + 1] = "mark" end
		if me.pvp and me.pvp:IsShown()      then drawn[#drawn + 1] = "pvp" end
		say("   %-12s %-4s %-8s %-8s %-6s %s", "player",
			tostring(UnitIsGroupLeader and UnitIsGroupLeader("player") or false),
			tostring(GetRaidTargetIndex and GetRaidTargetIndex("player")),
			tostring(UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")),
			tostring(UnitIsPVP and UnitIsPVP("player")),
			#drawn > 0 and A.Good(table.concat(drawn, ",")) or A.Dim("nothing"))
	end
end

A.PartyDiag = partyDiag
--- Every window this addon claims to skin, and what became of it.
--
--  Written for the same reason /aether party was: a window that comes up in
--  the client's own stone tells you nothing about WHY. It may not exist yet, it
--  may exist under another name on this game version, it may have been dressed
--  and had its art put back. Those are three different bugs and they look
--  identical on screen.
local function panelsDiag(say)
	local PN = A:GetModule("panels")
	if not PN then
		say("   " .. A.Bad(L.cmd.panels_diag.panels_module))
		return
	end
	say("   enabled: %s", PN.enabled and A.Good("yes") or A.Bad("no"))
	say("   %-22s %-8s %-8s %s", "window", "present", "glass", "interior")

	for _, entry in ipairs(PN.PANELS or {}) do
		local f = _G[entry.frame]
		local present = f and A.Good("yes") or A.Dim("no")
		local glass = f and (f.__aetherPanel and A.Good("yes") or A.Bad("NO"))
			or A.Dim("-")
		local interior = (PN.INTERIORS and PN.INTERIORS[entry.frame])
			and "yes" or "-"
		-- The addon it arrives with, when it is one of the on-demand ones -
		-- because "not present" and "present and not dressed" are answers to
		-- completely different questions.
		local note = ""
		if entry.addon then
			local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
				and C_AddOns.IsAddOnLoaded(entry.addon)
				or (IsAddOnLoaded and IsAddOnLoaded(entry.addon))
			note = "  " .. (loaded and A.Dim(entry.addon)
				or A.Bad(entry.addon .. " not loaded"))
		end
		say("   %-22s %-8s %-8s %s%s", entry.frame, present, glass, interior, note)
		-- WHY, when a dresser threw. A window in our glass with untouched
		-- insides looks exactly like one nobody has written a dresser for.
		local why = PN.failures and PN.failures[entry.frame]
		if why then say("      " .. A.Bad(why)) end
	end
end

A.PanelsDiag = panelsDiag
local handlers = {}

handlers.diag = diag
handlers.hide = function()
	local AB = A:GetModule("actionbars")
	if not AB or not AB.enabled then A:Print(L.common.actionbars_module_enabled) return end
	AB:HideBlizzard()
	diag()
end

handlers.bind = function()
	local AB = A:GetModule("actionbars")
	if not AB or not AB.enabled then A:Print(L.common.actionbars_module_enabled) return end
	AB:ToggleBindMode()
end

handlers.config  = function(arg) A.Options:Open(arg) end
handlers.options = handlers.config
--- `/aether preset` - the three shipped arrangements of the HUD.
--
--  `capture` is the half that matters during development: an arrangement is a
--  design decision made by eye, in the game, at a real resolution - so the
--  numbers in Core\Presets.lua are captured from a layout somebody has
--  actually made rather than typed into a text editor. Lay the frames out,
--  run this, paste the answer.
--- The first run, on demand.
--
--  THE RE-RUN DOOR. The design puts it in the Toolbox under Help; this is
--  the same door before that page exists, and it is the one the finish card
--  names - so whatever else moves, this has to keep working.
handlers.tour = function()
	local OB = A.GetModule and A:GetModule("onboard")
	if not OB then A:Print(L.cmd.tour.tour_loaded) return end
	OB:Start()
end

handlers.preset = function(arg, rest)
	local P = A.Presets
	if not P then A:Print(L.cmd.preset.presets_loaded) return end

	if arg == "capture" then
		-- The key is a NAME and keeps its case, like every other tail here.
		local key = (rest or ""):gsub("%s", "")
		if key == "" then key = P:Current() or "PRESET" end
		local lines, count = P:Capture(key)

		-- INTO THE COPY BOX, which is the only thing in this client whose text
		-- can be selected - chat cannot be copied from at all, which is why
		-- that box exists.
		local text = table.concat(lines, "\n")
		A.Errors:ShowText(text)

		-- AND OUT TO THE DISK, which is the only route out of this client
		-- that carries the text intact. The box above is for reading.
		A.Errors:Export("preset_" .. key, text)
		A:Print(A.F(count == 1
			and "captured %d frame position as %s - the lines above are the"
				.. " thing to paste into Core\\Presets.lua"
			or "captured %d frame positions as %s - the lines above are the"
				.. " thing to paste into Core\\Presets.lua",
			count, A.Val(key)))
		return
	end

	if arg and P.list[arg] then
		if P:Apply(arg) then
			A:Print(A.F(L.cmd.preset.layout_s, A.Hi(P.list[arg].label)))
		else
			A:Print(A.F(L.cmd.preset.could_apply_s, A.Val(arg)))
		end
		return
	end

	-- No argument, or one nobody recognises: say what there is and which is on.
	local now = P:Current()
	A:Print(A.Hi("/aether preset <name>") .. "  ·  or "
		.. A.Hi("/aether preset capture <name>") .. " to record the one you have"
		.. " made")
	for _, key in ipairs(P.order) do
		local one = P.list[key]
		A:Print("   " .. (key == now and A.Good(key) or A.Val(key)) .. "  "
			.. one.label .. (key == now and "   (on now)" or ""))
	end
end

handlers.unlock = function() A.Movers:Unlock() end
handlers.lock   = function() A.Movers:Lock() end
handlers.reset  = function() A.Movers:ResetAll() end
handlers.status = status
handlers.help   = usage

handlers.skin = function(arg)
	if not arg or not A.Palette.skins[arg] then
		local names = {}
		for _, s in ipairs(A.Palette:List()) do names[#names + 1] = s.key end
		A:Print(A.F(L.cmd.skin.skins_s, table.concat(names, ", ")))
		return
	end
	A.db.profile.skin = arg
	A:Restyle()
	A:Print(A.F(L.cmd.skin.skin_s, A.Val(arg)))
end

handlers.scale = function(arg)
	-- FIT IS THE ONE THE ADDON WOULD HAVE PICKED. Every size here is a screen
	-- pixel measured off a real display, and this is what turns those into the
	-- client's virtual units - so a player who has moved the slider and wants
	-- the drawn sizes back has a way to ask for them rather than a number to
	-- guess at. It is also the only route back: a scale once saved is never
	-- fitted again on its own.
	if arg and arg:lower() == "fit" then
		A.db.profile.scale = A:FittedScale()
		A:Reconfigure()
		A:Print(A.F(L.cmd.scale.scale_2f, A.db.profile.scale))
		return
	end

	local v = tonumber(arg)
	if not v or v < 0.6 or v > 1.6 then
		A:Print(A.F(L.cmd.scale.scale_takes_0_6,
			A.db.profile.scale))
		return
	end
	A.db.profile.scale = v
	A:Reconfigure()
	A:Print(A.F(L.cmd.scale.scale_2f, v))
end

--- Turn the running commentary on. There was no way to reach this at all, which
--  made A:Debug a diagnostic nobody could read.
handlers.debug = function(arg)
	local want
	if arg == "on" then want = true
	elseif arg == "off" then want = false
	else want = not A.db.profile.debug end
	A.db.profile.debug = want
	A:Print(A.F(L.cmd.debug.debug_s, want and L.common.on or L.common.off))
end

handlers.shadow = function(arg)
	local v = tonumber(arg)
	if not v or v < 0 or v > 1 then
		A:Print(A.F(L.cmd.shadow.shadow_takes_0_1,
			tostring(A.db.profile.glass.shadow)))
		return
	end
	A.db.profile.glass.shadow = v
	A:Restyle()
end

handlers.fade = function(arg, rest)
	local cfg = A.db.profile.fader
	if arg == "on" or arg == "off" then
		cfg.enabled = (arg == "on")
		A.Fader:Refresh()
		A:Print(A.F(L.cmd.fade.idle_fade_s, arg))
	elseif arg == "delay" then
		local v = tonumber(rest)
		if not v or v < 0.5 or v > 60 then A:Print(L.cmd.fade.delay_takes_0_5) return end
		cfg.delay = v
		A:Print(A.F(L.cmd.fade.idle_delay_ss, v))
	elseif arg == "idle" then
		local v = tonumber(rest)
		if not v or v < 0 or v > 1 then A:Print(L.cmd.fade.idle_alpha_takes_0) return end
		cfg.idleAlpha = v
		A.Fader:Update()
		A:Print(A.F(L.cmd.fade.idle_alpha_s, v))
	else
		A:Print(A.F(L.cmd.fade.idle_fade_s_delay,
			cfg.enabled and L.common.on or L.common.off, cfg.delay, cfg.idleAlpha))
	end
end

--- The last Lua errors, selectable.
--
--  The chat frame cannot be selected, so an error you can read is still one you
--  cannot send anybody. `clear` empties the list; anything else opens the box.
--- What the in-flight console can see: packs, seasons, the queue, the audio.
--
--  This is the settings readout the brief asks for, in the one place it can be
--  read while a flight is happening. Every state it prints is one somebody has
--  actually had to diagnose from a screenshot.
handlers.ifec = function(arg)
	local IFEC = A.IFEC
	if not IFEC or not IFEC.Registry then
		A:Print(L.cmd.ifec.ifec_loaded)
		return
	end

	local R, C, P = IFEC.Registry, IFEC.Content, IFEC.Playback

	-- Everything already heard is skipped, which is right and makes the second
	-- test flight of an evening nothing but filler. This forgets it.
	if arg == "reset" then
		local cfg = A.Config:Module("ifec")
		local n = 0
		for _ in pairs(cfg.progress or {}) do n = n + 1 end
		-- The play counter goes with it. Only relative order is ever read off it,
		-- so leaving it would still work - but it counts the entries in a store
		-- that is now empty, and the two drifting apart is how a diagnostic
		-- readout starts lying.
		cfg.progress, cfg.playCount = {}, nil
		A:Print(A.F(n == 1
			and "ifec: forgot %d item of listening history"
			or "ifec: forgot %d items of listening history", n))
		return
	end
	local packs = R:Sorted()

	A:Print(A.F(L.cmd.ifec.ifec_content_api_s,
		tostring(R.API_MIN), tostring(R.API_MAX)))

	if #packs == 0 then
		A:Print(L.cmd.ifec.packs_registered)
	end
	for _, id in ipairs(packs) do
		local pack = R.packs[id]
		A:Print(("  " .. A.Val("%s") .. "  season %d  ·  %d items")
			:format(id, pack.seasonIndex or 0, #pack.items))
	end

	for _, fail in ipairs(R:Failures()) do
		A:Print("  " .. A.Bad("refused") .. " " .. fail.packId .. "  ·  " .. fail.reason)
	end

	if C then
		local avail = C:Available()
		A:Print(("  in season today: " .. A.Val("%d") .. " of %d  ·  %s")
			:format(#avail, #R:Catalogue(),
				C:IsDormant() and A.Bad("dormant") or "active"))
	end

	if P then
		A:Print(P.item
			and A.F(L.cmd.ifec.playback_s_s_seg,
				A.Val(tostring(P.state)), tostring(P.item.title),
				tostring(P.index), tostring(#(P.item.segments or {})))
			or A.F(L.cmd.ifec.playback_s, A.Val(tostring(P.state))))

		-- THE BOUNDARY, IN SECONDS. There is no playback-finished event on this
		-- client, so "the next segment did not start" and "the next segment
		-- started and nothing repainted" look identical from the outside. This
		-- is the only place the difference is visible.
		local seg = P.item and P.item.segments and P.item.segments[P.index or 1]
		if seg and P.segStart and GetTime then
			A:Print(("    next boundary in %.1fs  ·  timer %s  ·  %s")
				:format((P.segStart + (seg.duration or 0)) - GetTime(),
					P.timer and "armed" or A.Bad("none"),
					tostring(seg.file)))
		end

		if P.lastFail then
			A:Print("  " .. A.Bad(L.cmd.ifec.last_file_would_play) .. ": " .. tostring(P.lastFail))
		end
	end

	local PL = IFEC.Player
	if PL then
		A:Print(A.F(L.cmd.ifec.queue_d_items_s,
			#(PL.queue or {}), tostring(PL.at),
			A:GetModule("ifec"):HasRegion() and L.cmd.ifec.attached or L.cmd.ifec.absent))
		for i, item in ipairs(PL.queue or {}) do
			A:Print(("    %d. %s  ·  %s  ·  %ds")
				:format(i, tostring(item.title), tostring(item.type),
					item.duration or 0))
		end
	end
end

handlers.errors = function(arg)
	if not A.Errors then
		A:Print(L.cmd.errors.errors_catcher_loaded)
		return
	end

	-- /aether diag answers into the chat frame, which is the one place its
	-- answer cannot be selected. Same information, somewhere you can copy it.
	if arg == "diag" then
		local body = A.Errors:Capture(function()
			if handlers.diag then handlers.diag() end
		end)
		A.Errors:ShowText(A.Errors:Header() .. body)
		return
	end

	if arg == "clear" then
		for i = #A.Errors.log, 1, -1 do A.Errors.log[i] = nil end
		A:Print(L.cmd.errors.errors_cleared)
		return
	end

	local n = #A.Errors.log
	A.Errors:Show()
	A:Print(A.F(n == 1
		and "errors: %d caught - Ctrl+A then Ctrl+C to copy"
		or "errors: %d caught - Ctrl+A then Ctrl+C to copy", n))
end

handlers.error = handlers.errors

--- The login line, on or off.
handlers.greet = function(arg)
	if arg == "on" or arg == "off" then
		A.db.profile.greet = (arg == "on")
	elseif arg == "test" then
		A.__greeted = nil
		A:Greet()
		return
	end
	A:Print(A.F(L.cmd.greet.greeting_login_s,
		A.db.profile.greet and L.common.on or L.common.off))
end

handlers.zen = function(arg, rest)
	-- Keywords, so folded here; see the dispatcher.
	local key = rest and rest:lower() or nil
	local cfg = A.db.profile.modules.zen
	local cap = A.Fader.AFK_TIMEOUT

	if arg == "on" or arg == "off" then
		A:SetModuleEnabled("zen", arg == "on")
		A.Fader:Refresh()
		A:Print(A.F(L.cmd.zen.zen_mode_s, arg))
	elseif arg == "delay" then
		local v = tonumber(rest)
		if not v or v < 5 or v > cap then
			A:Print(A.F(L.cmd.zen.zen_delay_takes_5,
				cap, cap))
			return
		end
		cfg.delay = v
		A:Print(A.F(L.cmd.zen.zen_delay_ss, v))
	elseif arg == "afk" then
		cfg.onAFK = (key ~= "off")
		A:Print(A.F(L.cmd.zen.zen_going_away_s,
			cfg.onAFK and L.common.on or L.common.off))
	elseif arg == "frost" then
		cfg.frost = (key ~= "off")
		A:Print(A.F(L.cmd.zen.frosted_pane_s_s,
			cfg.frost and L.common.on or L.common.off,
			A.Hi(L.cmd.zen.pane_front_world_blur)))
	elseif arg == "plates" then
		cfg.hideNameplates = (key ~= "off")
		local Z = A:GetModule("zen")
		-- Turning it off mid-zen has to hand them straight back; the module only
		-- re-reads this on its next tick, and the next tick may be a fade away.
		if not cfg.hideNameplates and Z and Z.RestoreWorldText then Z:RestoreWorldText() end
		A:Print(A.F(L.cmd.zen.nameplates_s_go_zen,
			A.Hi(L.cmd.zen.names),
			cfg.hideNameplates and L.common.on or L.common.off,
			A.Hi(L.cmd.zen.two_separate_cvar_families)))
	elseif arg == "sit" then
		cfg.sit = (key ~= "off")
		local Z = A:GetModule("zen")
		if not cfg.sit and Z and Z.StandUp then Z:StandUp() end
		A:Print(A.F(L.cmd.zen.sit_down_zen_s, cfg.sit and L.common.on or L.common.off))
	elseif arg == "camera" then
		cfg.camera = (key ~= "off")
		local Z = A:GetModule("zen")
		-- Straight back if it is being switched off mid-shot. Leaving somebody
		-- zoomed in because they flipped a switch would be a setting that does
		-- the opposite of what it says.
		if not cfg.camera and Z and Z.RestoreCamera then Z:RestoreCamera() end
		A:Print(A.F(L.cmd.zen.move_camera_zen_s,
			cfg.camera and L.common.on or L.common.off))
	elseif arg == "zoom" then
		-- Live, because it cannot be reasoned about from a number: the only way
		-- to find a distance anybody likes is to try one, watch it, and try
		-- another. Reloading between each is what makes that unbearable.
		--
		-- `pitch` used to be here too. It is gone: there is no way to set the
		-- camera's pitch on this client, only to move it for a length of time at
		-- a rate the player's own Mouse Look Speed decides, so the same number
		-- was a different shot on every machine. See Modules/Zen.lua.
		local KEYS = {
			zoom = { key = "cameraZoom", lo = 0, hi = 15, what = "metres behind you" },
		}
		local k = KEYS[arg]

		local v = tonumber(rest)
		if not v then
			A:Print(A.F(L.common.zen_s_s_s,
				arg, A.Val(tostring(cfg[k.key])), k.what))
			local example = "zen " .. arg .. " " .. k.lo .. "-" .. k.hi
			A:Print(A.F(L.cmd.zen.s_change, A.Hi(example)))
			return
		end
		cfg[k.key] = math.max(k.lo, math.min(k.hi, v))
		A:Print(A.F(L.common.zen_s_s_s, arg, A.Val(cfg[k.key]), k.what))

		-- Re-stage it on the spot if the shot is up, so the new value is visible
		-- now rather than at the next zen. Restore first: the camera is set ONCE
		-- on the way in and `_cam` is what says it has been, so without putting
		-- the player's own back first the next zen would restore to a distance
		-- this preview had already moved them to.
		local Z = A:GetModule("zen")
		if Z and Z._cam and Z.RestoreCamera and Z.SetCamera then
			Z:RestoreCamera()
			Z:SetCamera(1)
		end
	elseif arg == "audio" then
		cfg.audio = (key ~= "off")
		local Z = A:GetModule("zen")
		if not cfg.audio and Z and Z.RestoreAudio then Z:RestoreAudio() end
		A:Print(A.F(L.cmd.zen.zen_audio_s, cfg.audio and L.common.on or L.common.off))
	elseif arg == "track" then
		local Z = A:GetModule("zen")
		local names = { "random" }
		for _, t in ipairs((Z and Z.TRACKS) or {}) do names[#names + 1] = t.key end
		local want = rest and rest:lower() or ""
		local found = false
		for _, k in ipairs(names) do if k == want then found = true break end end
		if not found then
			A:Print(A.F(L.cmd.zen.zen_track_takes_one,
				A.Val(table.concat(names, ", "))))
			return
		end
		cfg.track = want
		A:Print(A.F(L.cmd.zen.zen_track_s, want))
	elseif arg == "preview" then
		local Z = A:GetModule("zen")
		if not Z or not Z.PreviewTrack then A:Print(L.common.zen_module_enabled) return end
		local name = Z:PreviewTrack(rest and rest:lower() or cfg.track)
		A:Print(name and ("playing " .. A.Val(name) .. " · run it again to stop")
			or "stopped.")
	elseif arg == "test" then
		local Z = A:GetModule("zen")
		if not Z or not Z.enabled then A:Print(L.common.zen_module_enabled) return end
		if not A.db.profile.fader.enabled then
			A:Print(A.F(L.cmd.zen.idle_fade_off_so, A.Hi("/aether fade on")))
			return
		end
		A.Fader:ForceZen()
		A:Print(L.cmd.zen.zen_preview_move_mouse)
	else
		A:Print(string.format("zen %s · after %ds of quiet%s · state " .. A.Val("%s"),
			(A:GetModule("zen") or {}).enabled and "on" or "off",
			cfg.delay, cfg.onAFK ~= false and " or on going away" or "",
			A.Fader.state))
	end
end

handlers.auras = function(arg)
	local Au = A:GetModule("auras")
	if not Au or not Au.enabled then A:Print(L.cmd.auras.auras_module_enabled) return end
	if arg == "refresh" then
		Au:UpdateAll()
		A:Print(L.cmd.auras.all_four_trays_re)
		return
	end
	Au:Diagnose()
end

handlers.bags = function(arg, rest)
	-- Keywords, so folded here; see the dispatcher.
	local key = rest and rest:lower() or nil
	local B = A:GetModule("bags")
	if not B or not B.enabled then A:Print(L.cmd.bags.bags_module_enabled) return end

	if arg == "open" then
		B:Toggle()
		return
	elseif arg == "sort" then
		local f = B.frames and B.frames.bags
		if f then B:StartSort(f) end
		A:Print(L.cmd.bags.compacting_stacks)
		return
	elseif arg == "sell" then
		local list, value = B:JunkList()
		if #list == 0 then A:Print(L.cmd.bags.junk_sell) return end
		if not _G.MerchantFrame or not _G.MerchantFrame:IsShown() then
			A:Print((A.Val("%d") .. " junk item%s worth " .. A.Val("%s") .. " - open a merchant first.")
				:format(#list, #list == 1 and "" or "s",
					(_G.GetCoinTextureString and _G.GetCoinTextureString(value)) or (value .. "c")))
			return
		end
		-- Deliberately bypasses the junkAutoSell setting: this is an explicit
		-- instruction, not the automatic behaviour, and refusing to obey it
		-- because a checkbox is off would be obtuse.
		B.selling = { list = list, index = 1, worth = value, earned = 0, sold = 0 }
		B:SellStep()
		return
	elseif arg == "junk" then
		local cfg = A.Config:Module("bags")
		if key == "on" then cfg.junkAutoSell = true
		elseif key == "off" then cfg.junkAutoSell = false
		else cfg.junkAutoSell = not cfg.junkAutoSell end
		A:Print(cfg.junkAutoSell
			and A.F(L.cmd.bags.junk_auto_sell_s, A.Good(L.common.on))
			or A.F(L.cmd.bags.junk_auto_sell_s2, A.Dim(L.common.off)))
		B:Invalidate()
		return
	end

	B:Diagnose()
end

handlers.chat = function(arg, rest)
	local C = A:GetModule("chat")
	if not C or not C.enabled then A:Print(L.cmd.chat.chat_module_enabled) return end

	-- Two parameters, like every other multi-word handler here. The dispatcher
	-- splits into cmd/arg/rest and re-splitting `arg` gets a single word with an
	-- empty value, which is a switch that always reports and never sets.
	local what, value = arg or "", rest or ""
	local cfg = A.Config:Module("chat")

	if what == "reskin" then C:Reskin(); A:Print(L.cmd.chat.chat_re_skinned) return end

	if what == "where" then A:ChatWhere() return end

	--- The three line settings that are worth reaching for mid-session. The
	--  rest live in the options panel, where a setting with a paragraph of
	--  explanation belongs.
	local switches = {
		lines  = { key = "styleLines", label = L.cmd.chat.lines },
		badges = { key = "badges",     label = L.cmd.chat.badges },
	}
	local sw = switches[what]
	if sw then
		if value ~= "on" and value ~= "off" then
			A:Print(sw.label .. " is " .. A.Val((cfg[sw.key] ~= false and "on" or "off")) .. ".")
			return
		end
		cfg[sw.key] = (value == "on")
		A:Reconfigure()
		A:Print(sw.label .. " -> " .. A.Val(value))
		return
	end

	if what == "whispers" then
		if value ~= "on" and value ~= "off" then
			A:Print(A.F(L.cmd.chat.whispers_tab_s_opens,
				A.Val(cfg.whisperTab == true and L.common.on or L.common.off)))
			return
		end
		if C:SetWhisperTab(value == "on") then
			cfg.whisperTab = (value == "on")
		end
		return
	end

	C:Diagnose()
end

handlers.health = function(arg, rest)
	if arg ~= "class" and arg ~= "deck" then
		-- `class` and `deck` stay English: they are the words the command
		-- itself takes, so translating them would name a setting nobody can
		-- type.
		A:Print(A.F(L.cmd.health.health_bar_colour_s,
			A.Val(A.db.profile.classColorHealth and "class" or "deck")))
		A:Print(A.F(L.cmd.health.s_s_tune_two,
			A.Dim("/aether health lift N"), A.Dim("depth N")))
		return
	end
	A.db.profile.classColorHealth = (arg == "class")
	A:Restyle()
	A:Print(A.F(L.cmd.health.health_bar_colour_s2, A.Val(arg)))
end

--- Bars are independent, so the command surface is `/aether bar <id> <what> <n>`
--  with a handful of globals that apply to all of them.
local BAR_PROPS = {
	buttons = { min = 1,   max = 12,  int = true },
	rows    = { min = 1,   max = 12,  int = true },
	page    = { min = 1,   max = 10,  int = true, actionOnly = true },
	scale   = { min = 0.4, max = 2.0 },
}

local function BarList()
	local AB = A:GetModule("actionbars")
	local cfg = A.Config:Module("actionbars")
	A:Print(L.cmd.bar_list.bars)
	for _, b in ipairs(cfg.bars) do
		local live
		for _, built in ipairs(AB and AB.bars or {}) do
			if built.id == tostring(b.id) then live = built end
		end
		say("   %s %-8s %s%s%s",
			(b.enabled and A.Good or A.Bad)(string.format("%-7s", tostring(b.id))),
			b.kind or "action",
			(b.kind or "action") == "action"
				and string.format("page %d · %d buttons", b.page or 1, b.buttons or 12)
				or string.format("%d buttons", live and #live.buttons or 0),
			string.format(" · %d row%s", b.rows or 1, (b.rows or 1) == 1 and "" or "s"),
			string.format(" · scale %.2f", b.scale or 1))
	end
	say("   " .. A.Dim("/aether bar <id> on/off/buttons N/rows N/page N/scale N/backdrop"))
end

handlers.bar = function(arg, rest)
	local cfg = A.Config:Module("actionbars")
	local AB = A:GetModule("actionbars")

	if not arg or arg == "" or arg == "list" then return BarList() end

	-- WITH THE DRAWER OPEN. Every line of it is a getter, so it changes
	-- nothing and can be run in a fight. Four guesses at why a flyout slot
	-- will not take a click have each cost a reload and a report; this asks
	-- the client instead, which is how everything else here got settled.
	if arg == "flyout" then
		if AB and AB.DiagnoseFlyout then AB:DiagnoseFlyout()
		else A:Print("this build has no flyout drawer") end
		return
	end

	-- globals that apply to every bar --------------------------------------
	if arg == "size" or arg == "spacing" or arg == "font" then
		local v = tonumber(rest)
		local limits = {
			size    = { 24, 80,  "the concept draws 62px slots" },
			spacing = { 0,  30,  "gap between buttons" },
			font    = { -4, 8,   "points added to the keybind, count and cooldown text" },
		}
		local lo, hi, note = limits[arg][1], limits[arg][2], limits[arg][3]
		if not v or v < lo or v > hi then
			A:Print(("bar %s takes %s - %s. " .. A.Dim("%s")):format(arg, lo, hi, note))
			return
		end
		if arg == "font" then cfg.fontDelta = v else cfg[arg] = v end
		A:Reconfigure()
		A:Print(("bar %s -> %s"):format(arg, v))
		return
	end

	-- per-bar ---------------------------------------------------------------
	local barCfg = AB and AB.BarConfig and AB:BarConfig(arg)
	if not barCfg then
		A:Print(A.F(L.cmd.bar.bar_s, A.Val(tostring(arg))))
		BarList()
		return
	end

	local what, value = tostring(rest or ""):match("^(%S+)%s*(.*)$")
	if not what or what == "" then
		A:Print(("bar %s: %s, page %s, %d buttons, %d rows, scale %.2f, %s"):format(
			tostring(barCfg.id), barCfg.kind or "action", tostring(barCfg.page or "-"),
			barCfg.buttons or 0, barCfg.rows or 1, barCfg.scale or 1,
			barCfg.enabled and "on" or "off"))
		return
	end

	if what == "on" or what == "off" then
		if not AB or not AB.enabled then A:Print(L.common.actionbars_module_enabled) return end
		AB:SetBarEnabled(barCfg.id, what == "on")
		A:Print(("bar %s -> %s"):format(tostring(barCfg.id), what))
		return
	end

	if what == "backdrop" then
		barCfg.backdrop = not (barCfg.backdrop ~= false)
		A:Reconfigure()
		A:Print(("bar %s backdrop -> %s"):format(tostring(barCfg.id),
			barCfg.backdrop and "on" or "off"))
		return
	end

	local prop = BAR_PROPS[what]
	if not prop then
		A:Print("usage: /aether bar " .. tostring(barCfg.id)
			.. " on|off|buttons N|rows N|page N|scale N|backdrop")
		return
	end
	if prop.actionOnly and (barCfg.kind or "action") ~= "action" then
		A:Print(("a %s bar has no page - its buttons come from the game."):format(
			barCfg.kind))
		return
	end

	local v = tonumber(value)
	if not v or v < prop.min or v > prop.max then
		A:Print(("bar %s %s takes %s - %s."):format(tostring(barCfg.id), what,
			prop.min, prop.max))
		return
	end
	if prop.int then v = math.floor(v + 0.5) end

	if what == "buttons" and (barCfg.kind or "action") ~= "action" then
		A:Print(("a %s bar sizes itself - the game decides how many there are."):format(
			barCfg.kind))
		return
	end

	barCfg[what] = v
	A:Reconfigure()
	A:Print(("bar %s %s -> %s"):format(tostring(barCfg.id), what, v))
end

--- /aether tooltips
--
--  The diagnostic matters more here than in most modules. This one reskins
--  frames it does not own, alongside other addons that are doing the same thing,
--  so "which frames did you actually find" and "is the stone border really off"
--  are the two questions worth being able to answer without a screenshot.
handlers.toolbox = function(arg, rest)
	local TB = A:GetModule("toolbox")
	if not TB or not TB.enabled then
		A:Print(L.cmd.toolbox.toolbox_module_enabled)
		return
	end
	local cfg = A.Config:Module("toolbox")

	if arg == "dock" then
		if not TB:SetDock(rest or "") then
			A:Print(A.F(L.cmd.toolbox.dock_takes_s_s,
				A.Val("left"), A.Val("right"),
				A.Val("top"), A.Val("bottom")))
			return
		end
		A:Print(A.F(L.common.toolbox_docked_s, A.Val(TB:Dock():lower())))
		return
	elseif arg == "open" then
		TB:SetOpen(true)
		return
	elseif arg == "close" then
		TB:SetOpen(false)
		return
	elseif arg == "toggle" then
		TB:Toggle()
		return
	elseif arg == "pin" then
		if not rest or rest == "" then
			local p = TB:Pinned()
			A:Print(A.F(L.cmd.toolbox.pinned_s,
				#p > 0 and table.concat(p, ", ") or A.Dim(L.cmd.toolbox.nothing)))
			return
		end
		-- MATCHED WITHOUT REGARD TO CASE, because nobody types an addon's LDB
		-- name in its exact case from memory. Both sides are folded here: the
		-- dispatcher hands the tail over as typed now, since it is just as often
		-- a frame name, and a global in this client IS case sensitive.
		local want = tostring(rest):lower()
		local key
		if A.Launchers then
			for e in A.Launchers:Iterate() do
				if tostring(e.key):lower() == want then key = e.key break end
			end
		end
		if not key or not TB:TogglePin(key) then
			A:Print(A.F(L.cmd.toolbox.nothing_called_s_offers, A.Val(rest), A.Hi("/aether toolbox")))
			return
		end
		A:Print(A.F(L.cmd.toolbox.pin_s_s, key,
			TB:IsPinned(key) and L.common.on or L.common.off))
		return
	end

	-- the diagnostic
	A:Print(A.F(L.cmd.toolbox.toolbox_docked_s_s,
		A.Val(TB:Dock():lower()),
		TB:IsOpen() and L.common.open or L.cmd.toolbox.shut,
		tonumber(cfg.scrim) or 0.28))

	local w, h = TB:PanelSize(TB:Dock())
	local sc = A.db.profile.scale
	say("   panel %.0fx%.0f at scale %.2f = %.0fx%.0f on a %.0fx%.0f screen",
		w, h, sc, w * sc, h * sc,
		UIParent:GetWidth() or 0, UIParent:GetHeight() or 0)

	-- widgets: ours are LDB data sources like anybody else's, so this reports
	-- what the GRID is showing rather than what the module happens to compute.
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	local list = TB:WidgetList()
	say("   widgets: %d shown%s", #list, ldb and "" or " " .. A.Bad(L.cmd.toolbox.libdatabroker))
	for _, name in ipairs(list) do
		local obj = ldb and ldb:GetDataObjectByName(name)
		local big, small = TB:CardText(name, obj)
		say("      %-24s %-10s %s", name, tostring(big), tostring(small))
	end

	-- launchers: the whole point is that neither mechanism contains the other,
	-- so the counts are worth seeing separately.
	-- `LA`, NOT `L`. In this file `L` is the phrase table, and it is the phrase
	-- table in every file that has one - so a second thing called L, however
	-- local, is a trap: the next phrase written inside one of these functions
	-- would silently read a launcher record instead. Core/Launchers.lua keeps
	-- its own `L` because it has no phrases in it.
	local LA = A.Launchers
	if LA then
		local ldbN, iconN, mapN = 0, 0, 0
		for e in LA:Iterate() do
			if e.source == "ldb" then ldbN = ldbN + 1
			elseif e.source == "dbicon" then iconN = iconN + 1
			else mapN = mapN + 1 end
		end
		say("   launchers: %d total  ·  %d from LDB  ·  %d LibDBIcon  ·  %d hand-rolled",
			LA:Count(), ldbN, iconN, mapN)
		if LA.scanError then
			say("      " .. A.Bad(L.cmd.toolbox.minimap_scan_failed_s), tostring(LA.scanError))
		end
		for e in LA:Iterate() do
			local owner = LA:OwnerOf(e)
			say("      %-26s %-8s %s%s", tostring(e.key), tostring(e.source),
				owner == TB and A.Good("rail")
					or owner and A.Dim("drawer") or A.Dim("unclaimed"),
				TB:IsPinned(e.key) and "  " .. A.Hi("pinned") or "")
		end
	end

	-- the addon list is a SUPERSET: most rows have nothing behind them.
	local rows = TB:AddonRows()
	local live = 0
	for _, r in ipairs(rows) do if r.entry then live = live + 1 end end
	say("   addons: %d loaded, %d with something to click%s", #rows, live,
		(TB._addonsCut or 0) > 0 and (", " .. TB._addonsCut .. " cut for room") or "")

	-- micro menu: nine declared, eight ever on screen.
	local micro = TB:MicroList()
	local names = {}
	for _, m in ipairs(micro) do names[#names + 1] = m.key end
	say("   micro: %d of %d  ·  %s", #micro, #TB.MICRO, table.concat(names, " "))
	say("      " .. A.Dim("Social and Guild are exclusive on useClassicGuildUI (%s)"),
		tostring(GetCVarBool and GetCVarBool("useClassicGuildUI")))
end

--- What a dressed panel's header and body actually measured, in game.
--
--  The harness can say a hairline exists, is parented where we meant and is
--  anchored where we meant. It cannot say the window it is on came up 40
--  units taller than the glass you can see, which is the difference between
--  a band with a foot and a band without one - and four rounds of reading
--  screenshots did not settle which of those the vendor window was.
--- Where a window's parts actually are, in a box you can copy out of.
--
--  INTO THE ERROR BOX, not the chat frame. This is a wall of numbers whose
--  whole purpose is to be sent to somebody, and the chat frame is the one
--  place in the interface that cannot be selected - so every reading of it so
--  far has come back as a photograph of a screen.
local function MeasurePanels(arg)
	local PN = A:GetModule("panels")
	if not PN then A:Print(L.cmd.measure_panels.panels_module_loaded) return end

	-- Printed through a local rather than A:Print so the whole readout can be
	-- captured; falls back to the chat frame if the catcher is not loaded.
	local out = {}
	local function A_Print(line) out[#out + 1] = tostring(line) end

	local names = {}
	if arg and arg ~= "" then
		names[1] = arg
	else
		for name, f in pairs(PN.ENTRY or {}) do
			local frame = _G[name]
			if frame and frame.__aetherPanel and frame:IsShown() then
				names[#names + 1] = name
			end
			local _ = f
		end
		table.sort(names)
	end
	if #names == 0 then
		A:Print(L.cmd.measure_panels.dressed_panel_open_open)
		return
	end

-- WHAT A PANE MEASURES NOW, against what it measured when the window was
-- dressed. A pane that answers now and did not then was measured before it
-- had a rect to measure, which is the difference between a window laid out
-- wrongly and one laid out too early.
--
-- The cache is put back afterwards: a readout that changes what it is reading
-- is not a readout.
	local function remeasure(frame, pane)
		local PN2 = A:GetModule("panels")
		if not (PN2 and PN2.MeasureTop) then return "?" end
		local top, left, right =
			pane.__aetherTop, pane.__aetherLeft, pane.__aetherRight
		pane.__aetherTop, pane.__aetherLeft, pane.__aetherRight = nil, nil, nil
		local ok, got = pcall(PN2.MeasureTop, frame, pane)
		pane.__aetherTop, pane.__aetherLeft, pane.__aetherRight = top, left, right
		if not ok then return "threw: " .. tostring(got) end
		return got
	end

	local function box(f)
		if not (f and f.GetTop and f:GetTop()) then return "-" end
		return string.format("t%.0f l%.0f w%.0f h%.0f",
			f:GetTop(), f:GetLeft(), f:GetWidth(), f:GetHeight())
	end

	for _, name in ipairs(names) do
		local f = _G[name]
		if not f then
			A_Print(name .. ": no such frame")
		else
			local glass, rule = f.__aetherPanel, f.__aetherHeadRule
			A_Print(name .. "  head=" .. tostring(f.__aetherHeadH) ..
				"  shift=" .. tostring(f.__aetherBodyShift) ..
				-- HOW MANY TIMES the body has been laid out, and what the window
				-- could tell us the last time. One run, at login, against a window
				-- with no rect, looks on screen exactly like a run that got the
				-- wrong answer - and the two want opposite fixes.
				"  runs=" .. tostring(f.__aetherRuns) ..
				"  seen=" .. tostring(f.__aetherSeen))
			A_Print("  frame " .. box(f) .. "   glass " .. box(glass))
			A_Print("  chrome " .. box(f.__aetherChrome) ..
				"  lvl " .. tostring(f.__aetherChrome
				and f.__aetherChrome:GetFrameLevel()) ..
				" vs frame " .. tostring(f:GetFrameLevel()))
			-- IDENTITY, so an anchor printed below as "on table: ..." can be told
			-- apart from these two. The glass and the chrome layer have the same
			-- rect by construction, so a rect cannot tell them apart.
			A_Print("  glass=" .. tostring(glass) ..
				"  chrome=" .. tostring(f.__aetherChrome) ..
				"  strata " .. tostring(f.GetFrameStrata and f:GetFrameStrata()) ..
				"/" .. tostring(f.__aetherChrome and f.__aetherChrome.GetFrameStrata
				and f.__aetherChrome:GetFrameStrata()))

			-- ANYTHING OF THE CLIENT'S DRAWN OVER OUR CHROME. A child at a higher
			-- STRATA beats any frame level, and one that covers only the band would
			-- hide the band's hairline and leave the footer's alone - which is the
			-- exact shape of the complaint.
			local ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
				DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
			local layer = f.__aetherChrome
			if layer and f.GetChildren then
				local mine = (ORDER[layer:GetFrameStrata()] or 0) * 1000
					+ (layer:GetFrameLevel() or 0)
				local over = {}
				for _, kid in ipairs({ f:GetChildren() }) do
					if kid ~= layer and kid ~= glass and kid.IsShown and kid:IsShown() then
						local rank = (ORDER[kid:GetFrameStrata()] or 0) * 1000
							+ (kid:GetFrameLevel() or 0)
						if rank > mine then
							over[#over + 1] = (kid.GetName and kid:GetName() or tostring(kid))
								.. " " .. tostring(kid:GetFrameStrata()) .. ":" ..
								tostring(kid:GetFrameLevel()) .. " " .. box(kid)
						end
					end
				end
				if #over == 0 then
					A_Print("  over chrome: nothing")
				else
					for _, line in ipairs(over) do
						A_Print("  OVER CHROME " .. line)
					end
				end
			end
			if rule then
				local pt, rel, relP, x, y = rule:GetPoint(1)
				A_Print("  rule " .. box(rule) .. "  shown=" ..
					tostring(rule:IsShown()) .. " a=" ..
					string.format("%.2f", select(4, rule:GetVertexColor())) ..
					"  " .. tostring(pt) .. "->" .. tostring(relP) .. " " ..
					tostring(x) .. "," .. tostring(y) .. " on " ..
					tostring(rel and rel.GetName and rel:GetName() or rel))
			else
				A_Print("  rule MISSING")
			end
			A_Print("  body " .. box(f.__aetherBody))

			-- THE FOOT RULE AND THE STRIP, which is half of what goes wrong on a
			-- window now: the band and the strip are drawn by the same component
			-- and one of them turning up without the other says where to look.
			local foot = f.__aetherFootRule
			if foot then
				local fp, frel, frelP, fx, fy = foot:GetPoint(1)
				A_Print("  foot " .. box(foot) .. "  shown=" ..
					tostring(foot:IsShown()) .. "  " .. tostring(fp) .. "->" ..
					tostring(frelP) .. " " .. tostring(fx) .. "," .. tostring(fy) ..
					" on " .. tostring(frel and frel.GetName and frel:GetName() or frel))
			else
			A_Print("  foot none")
			end

			-- WHAT THE WINDOW SAYS ITS CONTENT IS, and where that content actually
			-- is. A pane measuring as nothing is a pane the walk could not reach.
			local entry = PN.ENTRY and PN.ENTRY[name]
			for _, part in ipairs(entry and entry.body or {}) do
				local pane = PN.Part and PN.Part(part)
				if not pane then
					A_Print("  body " .. part .. ": NOT FOUND")
				else
					local pt, rel, relP, x, y = pane:GetPoint(1)
					A_Print("  body " .. part .. " " .. box(pane) ..
						"  pts=" .. tostring(pane.GetNumPoints and pane:GetNumPoints()) ..
						-- Recorded by the mover the first time it touches a pane. Nil here
						-- says the pane never reached it - which is a lookup that failed
						-- when the window was dressed, not a measurement that went wrong.
						" saved=" .. tostring(pane.__aetherPts ~= nil) ..
						"  top=" .. tostring(pane.__aetherTop) ..
						" now=" .. tostring(remeasure(f, pane)) ..
						" l=" .. tostring(pane.__aetherLeft) ..
						" r=" .. tostring(pane.__aetherRight) ..
						"  " .. tostring(pt) .. "->" .. tostring(relP) .. " " ..
						tostring(x) .. "," .. tostring(y) .. " on " ..
						tostring(rel and rel.GetName and rel:GetName() or rel))
				end
			end

			-- AND WHAT IT SAYS IT DOES. An action that is shown but not VISIBLE is
			-- one whose pane is down, and the strip is laid out for what is up.
			for _, side in ipairs({ "left", "right", "mid" }) do
				for _, part in ipairs(entry and entry.actions
					and entry.actions[side] or {}) do
					local w = PN.Part and PN.Part(part)
					if not w then
						A_Print("  act " .. side .. " " .. part .. ": NOT FOUND")
					else
						local pt, rel, relP, x, y = w:GetPoint(1)
						A_Print("  act " .. side .. " " .. part .. " " .. box(w) ..
							"  shown=" .. tostring(w.IsShown and w:IsShown()) ..
							" vis=" .. tostring(w.IsVisible and w:IsVisible()) ..
							"  " .. tostring(pt) .. "->" .. tostring(relP) .. " " ..
							tostring(x) .. "," .. tostring(y) .. " on " ..
							tostring(rel and rel.GetName and rel:GetName() or rel))
					end
				end
			end

			local why = PN.failures and PN.failures[name]
			if why then A_Print("  interior FAILED: " .. why) end
		end
	end

	local text = table.concat(out, string.char(10))
	if A.Errors and A.Errors.ShowText then
		A.Errors:ShowText((A.Errors.Header and A.Errors:Header() or "") .. text)
	else
		for _, line in ipairs(out) do A:Print(line) end
	end
end

handlers.panels = function(arg, rest)
	if arg == "dump" then A:DumpPanel(rest) return end
	if arg == "measure" then MeasurePanels(rest) return end
	if arg == "diag" then
		A:Print(L.cmd.panels.panels)
		A.PanelsDiag(function(fmt, ...) A:Print(string.format(fmt, ...)) end)
		return
	end

	local P = A:GetModule("panels")
	A:Print(A.F(L.cmd.panels.panels_s_s_reads,
		A.Val((P and P.enabled) and L.common.on or L.common.off),
		A.Hi(L.cmd.panels.dump_framename), A.Hi("measure"), A.Hi("diag")))
end

handlers.tooltips = function(arg)
	local T = A:GetModule("tooltips")
	if not T or not T.enabled then A:Print(L.cmd.tooltips.tooltips_module_enabled) return end
	local cfg = A.Config:Module("tooltips")

	if arg == "cursor" then
		cfg.cursorItems = not cfg.cursorItems
		A:Print(cfg.cursorItems
			and A.F(L.common.item_spell_tooltips_s,
				A.Good(L.cmd.tooltips.follow_cursor))
			or A.F(L.common.item_spell_tooltips_s,
				A.Dim(L.cmd.tooltips.stay_where_whatever_opened)))
	elseif arg == "anchor" then
		cfg.unitAnchor = not cfg.unitAnchor
		A:Print(cfg.unitAnchor
			and L.cmd.tooltips.unit_tooltips_anchored_their
			or L.cmd.tooltips.unit_tooltips_back_blizzard)
	elseif arg == "badge" then
		cfg.levelBadge = not cfg.levelBadge
		A:Print(A.F(L.cmd.tooltips.level_badge_s_one, cfg.levelBadge and L.common.on or L.common.off))
	elseif arg == "sweep" then
		local n = T:Sweep()
		A:Print(("swept: " .. A.Val("%d") .. " new tooltip frame%s adopted.")
			:format(n, n == 1 and "" or "s"))
	else
		T:Diagnose()
		A:Print("usage: /aether tooltips cursor|anchor|badge|sweep")
	end
end

handlers.quests = function(arg)
	local QT = A:GetModule("questtracker")
	if not QT or not QT.enabled then A:Print(L.cmd.quests.questtracker_module_enabled) return end
	local cfg = A.Config:Module("questtracker")

	if arg == "fold" then
		QT:ToggleCollapsed()
		A:Print(QT.collapsed and L.cmd.quests.quest_tracker_folded
			or L.cmd.quests.quest_tracker_unfolded)
	elseif arg == "objectives" then
		cfg.showObjectives = not cfg.showObjectives
		QT:Refresh()
		A:Print(A.F(L.cmd.quests.objective_lines_s,
			cfg.showObjectives and L.common.on or L.common.off))
	elseif arg == "auto" then
		cfg.autoTrack = not (cfg.autoTrack ~= false)
		QT:Refresh()
		A:Print(cfg.autoTrack
			and "tracking every quest in the log; right-click a row to dismiss one."
			or "tracking only what you add; shift-click a quest in the log to track it.")
	elseif arg == "clear" then
		if A.db.char then
			A.db.char.tracked = {}
			A.db.char.untracked = {}
		end
		QT:Refresh()
		A:Print(L.cmd.quests.tracking_reset)
	else
		local n = QT.quests and #QT.quests or 0
		A:Print(string.format(
			"%s mode · showing %d quest%s%s  (usage: /aether quests fold|auto|objectives|clear)",
			(cfg.autoTrack ~= false) and "auto" or "manual", n, n == 1 and "" or "s",
			(QT.hidden or 0) > 0 and (" · " .. QT.hidden .. " did not fit") or ""))
	end
end


handlers.party = function(arg)
	local PF = A:GetModule("partyframes")
	
	-- Bare /aether party opens the controls, because that is the thing a
	-- player wants; the report is scaffolding and takes the sub-command.
	-- Until the dock handle exists this is the only way in.
	if arg == "reset" then
		if not PF then return end
		PF:ResetStack()
		A:Print(L.cmd.party.party_frames_back_dock)
		return
	end

	if arg ~= "diag" then
		if not PF or not PF.enabled then
			A:Print(L.cmd.party.party_frames_switched_off)
			return
		end
		local open = PF:TogglePanel()
		A:Print(A.F(L.cmd.party.party_controls_s_s,
			open and A.Good(L.common.open) or A.Dim(L.cmd.party.closed),
			A.Hi("/aether party diag")))
		return
	end
	
	A:Print(L.cmd.party.party)
	A.PartyDiag(function(fmt, ...)
		A:Print(string.format(fmt, ...))
	end)
end

-- ---------------------------------------------------------------------------
-- threat
--
-- PHASE 0 OF THE THREAT PLAN, and its whole job is evidence. Everything in
-- docs/PLAN-Threat.md says UnitDetailedThreatSituation answers on this client -
-- the generated docs declare it, Blizzard's own Classic unit frame drives off
-- it, and NKThreat 2.12.1 at Interface-Vanilla 11509 uses it as its only source
-- with no combat-log fallback. Nothing has SEEN it answer, and a design built
-- on a number nobody has read is a design built on a guess.
--
-- It also answers the second question in the plan, which is the one that
-- changes the shape of the thing: what UnitGroupRolesAssigned says about a real
-- party. If it says NONE for everyone - which is what Classic Era's opt-in
-- roles imply - then a tank gets the DPS treatment, and the DPS treatment for a
-- tank holding aggro is a red screen and an alarm for doing their job.
--
-- INTO THE ERROR BOX. Same reason /aether panels measure goes there: this is a
-- wall of numbers whose purpose is to come back to me, and the chat frame is
-- the one part of the interface that cannot be selected.
-- ---------------------------------------------------------------------------

-- HAS THE SERVER EVER SENT A THREAT TABLE. This is the decisive signal and a
-- readout taken after the fact cannot have it, so it is counted from load.
--
-- UNIT_THREAT_LIST_UPDATE is what the server fires when a mob's threat table
-- changes, and it is what NKThreat registers - unit-filtered on "target",
-- alongside a polling loop, because the event alone does not cover a target
-- change. If that event never fires during a fight then the API is a stub on
-- this client whatever it answers, and the ring needs a threat meter of our
-- own rather than a display onto somebody else's number.
--
-- TEMPORARY. This belongs to Phase 0 of docs/PLAN-Threat.md and goes when the
-- threat module lands and owns the event properly.
local threatSeen = { list = 0, situation = 0, unit = nil }
do
	local watch = CreateFrame("Frame")
	watch:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
	watch:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
	watch:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_THREAT_LIST_UPDATE" then
			threatSeen.list = threatSeen.list + 1
		else
			threatSeen.situation = threatSeen.situation + 1
		end
		threatSeen.unit = unit or threatSeen.unit
	end)
end

--- Every mob we can ask ABOUT, and what to call it in the readout.
--
--  Threat is queried per unit PER MOB, and the mob has to be a unit TOKEN -
--  the generated docs name that argument `mobGUID` and then type it UnitToken,
--  which is a trap worth falling into once and never again. So the set of mobs
--  we can see is exactly: your target, anything with a nameplate, and whatever
--  each group member and pet is swinging at.
local function ThreatMobs()
	local mobs, seen = {}, {}
	local function add(token, why)
		if not token or seen[token] then return end
		if not UnitExists(token) or UnitIsFriend("player", token) then return end
		if UnitIsDead and UnitIsDead(token) then return end
		seen[token] = true
		mobs[#mobs + 1] = { token = token, why = why,
			name = UnitName(token) or "?" }
	end

	add("target", "your target")
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, base in ipairs(C_NamePlate.GetNamePlates()) do
			add(base.unitToken, "nameplate")
		end
	end
	add("pettarget", "what your pet is on")
	for i = 1, 4 do add("party" .. i .. "target", "party" .. i .. "'s target") end
	return mobs
end

--- Everyone whose threat we would ever draw.
local function ThreatUnits()
	local units = { { token = "player", why = "you" } }
	if UnitExists("pet") then units[#units + 1] = { token = "pet", why = "pet" } end
	for i = 1, 4 do
		local u = "party" .. i
		if UnitExists(u) then
			units[#units + 1] = { token = u, why = UnitName(u) or u }
		end
	end
	return units
end

--- What the client thinks the player's role is, by each route the plan names.
--
--  Reported rather than decided. The plan's effective-role scheme picks between
--  these; this prints all of them side by side so the pick can be made against
--  what the client actually says rather than against what it ought to say.
local function ThreatRole(say)
	local assigned = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
	say("  assigned role: " .. tostring(assigned) ..
		(assigned == "NONE" and "   <- the case the plan is written for" or ""))

	-- The inference, per PLAN-Threat.md 2.2: a stance or a form or an aura, all
	-- of which the player changes deliberately and we can read directly.
	local form = GetShapeshiftForm and GetShapeshiftForm()
	if form and form > 0 and GetShapeshiftFormInfo then
		local icon, name = GetShapeshiftFormInfo(form)
		say("  stance/form " .. tostring(form) .. ": " ..
			tostring(name or icon or "?"))
	else
		say("  stance/form: none (" .. tostring(form) .. ")")
	end

	local tanking = {}
	for i = 1, 40 do
		local aura = UnitBuff and UnitBuff("player", i)
		if not aura then break end
		tanking[#tanking + 1] = aura
	end
	say("  buffs: " .. (#tanking > 0 and table.concat(tanking, ", ") or "none"))
end

local function ThreatProbe()
	local out = {}
	local function say(line) out[#out + 1] = tostring(line) end

	say("threat probe  ·  " .. tostring(A.version))
	say("API: UnitDetailedThreatSituation=" ..
		tostring(type(UnitDetailedThreatSituation)) ..
		"  UnitThreatSituation=" .. tostring(type(UnitThreatSituation)) ..
		"  UnitThreatPercentageOfLead=" ..
		tostring(type(UnitThreatPercentageOfLead)))
	say("combat=" .. tostring(UnitAffectingCombat("player")) ..
		"  group=" .. tostring(GetNumGroupMembers and GetNumGroupMembers() or 0) ..
		"  raid=" .. tostring(IsInRaid and IsInRaid()) ..
		"  pet=" .. tostring(UnitExists("pet")))

	-- THE CLIENT'S OWN GATE ON ITS OWN THREAT DISPLAY. Blizzard's Classic unit
	-- frame checks this before it draws anything, so a client with threat data
	-- and this switched off looks exactly like a client with no threat data.
	local okw, warn = pcall(function()
		return IsThreatWarningEnabled and IsThreatWarningEnabled()
	end)
	local okc, cvar = pcall(GetCVar, "threatWarning")
	say("IsThreatWarningEnabled=" .. tostring(okw and warn) ..
		"  cvar threatWarning=" .. tostring(okc and cvar))

	-- COUNTED SINCE LOGIN, not asked for now. If the server has never sent a
	-- threat table then nothing else in this readout matters.
	say("UNIT_THREAT_LIST_UPDATE fired " .. tostring(threatSeen.list) ..
		"x  UNIT_THREAT_SITUATION_UPDATE " .. tostring(threatSeen.situation) ..
		"x  last unit=" .. tostring(threatSeen.unit) ..
		(threatSeen.list == 0 and "   <- never, so far" or ""))
	say("")
	say("role, every route the plan considers:")
	ThreatRole(say)
	say("")

	if type(UnitDetailedThreatSituation) ~= "function" then
		say("NO THREAT API ON THIS CLIENT. Everything in PLAN-Threat.md 1 is")
		say("wrong and the module needs combat-log inference after all.")
	end

	local mobs, units = ThreatMobs(), ThreatUnits()
	say("units: " .. #units .. "   mobs with a token: " .. #mobs)
	if #mobs == 0 then
		say("")
		say("NOTHING TO ASK ABOUT. Threat is per unit PER MOB and the mob has to")
		say("be a unit token, so this wants a live target - or a nameplate up -")
		say("in combat. Out of combat every one of these reads nil, which is")
		say("also the right answer and not a fault.")
	else
		say("")
		say("READ IT LIKE THIS: rets=0 everywhere, while you are in combat with a")
		say("mob YOU have attacked yourself, AND the event count above is still")
		say("zero, means the call is present and the server is sending nothing -")
		say("and the ring needs a threat meter of our own rather than a display")
		say("onto somebody else's number. rets=0 while your PET has done all the")
		say("damage means only that you are not on its table, which is correct.")
		say("A non-zero event count with rets=0 means the data arrives and you")
		say("simply were not on that particular table.")
	end

	for _, mob in ipairs(mobs) do
		say("")
		say(mob.name .. "  [" .. mob.token .. ", " .. mob.why .. "]")
		say("   its combat=" .. tostring(UnitAffectingCombat(mob.token)) ..
			"  its target=" .. tostring(UnitName(mob.token .. "target")))
		for _, u in ipairs(units) do
			-- HOW MANY VALUES CAME BACK, not just what they were. The call is
			-- declared MayReturnNothing, and "returned five nils" and "returned
			-- nothing at all" are different faults wearing the same face: the
			-- first is a unit that is not on this mob's table, which is normal;
			-- the second is a function present and not wired, which is the whole
			-- feature.
			--
			-- pcall, because an API that is declared and not wired can also
			-- answer by throwing, and one probe throwing is not a reason to lose
			-- the rest of the readout.
			local packed = { pcall(UnitDetailedThreatSituation, u.token, mob.token) }
			local rets = #packed - 1
			local ok = packed[1]
			local tanking, status, scaled, raw, value =
				packed[2], packed[3], packed[4], packed[5], packed[6]

			-- AND THE SIMPLE CALL BESIDE THE DETAILED ONE. They are separate
			-- entry points onto the same data; one answering while the other
			-- does not would say precisely where the wiring stops.
			local oks, simple = pcall(UnitThreatSituation, u.token, mob.token)
			local plain = "  simple=" .. tostring(oks and simple)

			if not ok then
				say("  " .. u.why .. " (" .. u.token .. "): THREW " ..
					tostring(tanking))
			elseif scaled == nil and status == nil then
				say("  " .. u.why .. " (" .. u.token .. "): nothing back  rets=" ..
					tostring(rets) .. plain ..
					(rets == 0 and "   <- no return values at all"
						or "   <- returned nils"))
			else
				local lead = ""
				if tanking and UnitThreatPercentageOfLead then
					local okl, pct = pcall(UnitThreatPercentageOfLead, u.token,
						mob.token)
					if okl and pct then
						lead = "  lead=" .. string.format("%.1f", pct) .. "%"
					end
				end
				say(string.format(
					"  %s (%s): tanking=%s status=%s scaled=%s raw=%s threat=%s%s%s",
					u.why, u.token, tostring(tanking), tostring(status),
					scaled and string.format("%.1f", scaled) or "nil",
					raw and string.format("%.1f", raw) or "nil",
					value and string.format("%.0f", value) or "nil", plain, lead))
			end
		end
	end

	local text = table.concat(out, string.char(10))
	if A.Errors and A.Errors.ShowText then
		A.Errors:ShowText((A.Errors.Header and A.Errors:Header() or "") .. text)
	else
		for _, line in ipairs(out) do A:Print(line) end
	end
end

handlers.threat = function(arg)
	if arg == "probe" or arg == nil or arg == "" then
		ThreatProbe()
		return
	end
	A:Print(A.Hi("/aether threat probe") .. "  ·  what the threat API answers")
end

--- The class resource tray, and the preview that lets one character check all
--  of it.
--
--  NINE OF THE ELEVEN ROWS BELONG TO A CLASS OR A SPEC, and three of the
--  interesting ones are unreachable on any single character: the Death Knight
--  is the only stacked case, the only per-socket hue and the only recharging
--  fill, and eclipse is the only bar that runs both ways from a centre mark.
--  Checking those meant levelling alts, which is not a thing anybody does to
--  sign off a shelf thirty pixels tall.
--
--  The preview drives the REAL drawing from a script - the module's Rows
--  returns the scripted set and nothing downstream knows - so what is on screen
--  is the tray, not a picture of it.
handlers.resources = function(arg)
	local RSm = A:GetModule("resources")
	if not RSm then A:Print("this build has no resource tray") return end

	if arg == "demo" or arg == "preview" then RSm:Demo() return end
	if arg == "off" then RSm:Demo("off") return end
	if arg == "next" then RSm:Demo("next") return end

	-- WHAT THE CLIENT SAYS THIS CHARACTER HAS, which is the other half of the
	-- question and the one that answers "why is there no tray". Every row is a
	-- power the client either reports a maximum for or does not.
	local rows = RSm:Rows()
	if #rows == 0 then
		A:Print("no class resource on this character - "
			.. A.Dim("nothing reports a maximum"))
	else
		for _, row in ipairs(rows) do
			A:Print(("   %s  %s · %d socket%s"):format(
				A.Hi(row.key), row.kind,
				math.floor(row.max() or 0),
				math.floor(row.max() or 0) == 1 and "" or "s"))
		end
	end
	A:Print("   " .. A.Dim("/aether resources demo|next|off"))
end

handlers.module = function(arg, rest)
	-- Keywords, so folded here; see the dispatcher.
	local key = rest and rest:lower() or nil
	if not arg or not A.modules[arg] then
		local names = {}
		for name in A:IterateModules() do names[#names + 1] = name end
		A:Print(A.F(L.cmd.module.modules_s, table.concat(names, ", ")))
		return
	end
	if key ~= "on" and key ~= "off" then
		A:Print("usage: /aether module " .. arg .. " on|off")
		return
	end
	A:SetModuleEnabled(arg, key == "on")
	A:Print(A.F(L.cmd.module.module_s_s, arg, rest))
end

SLASH_AETHERUI1 = "/aether"
SLASH_AETHERUI2 = "/aetherui"

SlashCmdList["AETHERUI"] = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, arg, rest = msg:match("^(%S*)%s*(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()

	-- Bare /aether opens the panel now. The commands have not gone anywhere -
	-- they are still faster for one number - but there are too many of them to
	-- be the front door.
	if cmd == "" then
		if not A.Options:Open() then usage() end
		return
	end

	local fn = handlers[cmd]
	if fn then
		-- THE TAIL KEEPS ITS CASE. A sub-command is a keyword and folds down
		-- safely; what follows it is often a NAME - a frame, a music track, an
		-- addon - and a global in this client is case sensitive. Folded, every
		-- one of those came back "no such frame" for a frame that was on screen
		-- at the time, which is what happened to /aether panels dump.
		--
		-- Handlers that compare the tail to a keyword lower it themselves.
		fn(arg ~= "" and arg:lower() or nil, rest ~= "" and rest or nil)
	else
		A:Print(A.F(L.cmd.module.unknown_command_s, cmd))
		usage()
	end
end
