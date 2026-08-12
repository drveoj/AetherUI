--[[--------------------------------------------------------------------------
	AetherUI :: Commands

	/aether — everything is reachable from chat. A proper options panel comes
	later; until then this is the whole control surface, which is honestly enough
	while the layout is still moving.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local function usage()
	A:Print("|cff9d7bff/aether|r on its own opens the options panel. Everything below"
		.. " still works and is quicker for one number.")
	local lines = {
		"|cff9d7bff/aether config|r  ·  the options panel (or just |cff9d7bff/aether|r)",
		"|cff9d7bff/aether bind|r  ·  hover a button, press a key",
		"|cff9d7bff/aether unlock|r  ·  drag frames into place",
		"|cff9d7bff/aether lock|r",
		"|cff9d7bff/aether reset|r  ·  forget all frame positions",
		"|cff9d7bff/aether skin|r <midnight|daylight>",
		"|cff9d7bff/aether scale|r <0.6-1.6>  ·  0.71 = the concept deck's proportions",
		"|cff9d7bff/aether fade|r <on|off|delay N|idle 0-1>  ·  stage one, the dim",
		"|cff9d7bff/aether zen|r <on|off|delay N|afk on/off|test>  ·  stage two",
		"|cff9d7bff/aether zen|r <frost|plates|audio|sit|camera> on/off  ·  the mode itself",
		"|cff9d7bff/aether zen|r <track NAME|preview>  ·  the music",
		"|cff9d7bff/aether shadow|r <0-1>  ·  ambient shadow opacity",
		"|cff9d7bff/aether health|r <class|deck>  ·  bar colour for players",
		"|cff9d7bff/aether bar|r <list · N on/off · N buttons/rows/page/scale V · size/spacing/font N>",
		"|cff9d7bff/aether quests|r <fold|auto|objectives|clear>  ·  the quest tracker",
		"|cff9d7bff/aether module|r <name> <on|off>",
		"|cff9d7bff/aether status|r",
		"|cff9d7bff/aether diag|r  ·  why is a Blizzard frame still on screen",
		"|cff9d7bff/aether auras|r <refresh>  ·  what the aura API is actually saying",
		"|cff9d7bff/aether chat|r <reskin · lines/badges on|off · whispers on|off>",
		"|cff9d7bff/aether bags|r <open · sort · sell · junk on|off>  ·  what the container API is saying",
		"|cff9d7bff/aether tooltips|r <cursor|anchor|badge|sweep>  ·  which tooltips got skinned",
	}
	for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("   " .. l) end
end

local function status()
	A:Print("v" .. A.version .. "  ·  skin |cffece6ff" .. A.Palette.current .. "|r  ·  scale "
		.. string.format("%.2f", A.db.profile.scale)
		.. "  ·  pixel " .. string.format("%.3f", A.pixel))
	for name, m in A:IterateModules() do
		DEFAULT_CHAT_FRAME:AddMessage(string.format("   %s  %s%s",
			m.enabled and "|cff9fe8b4on |r" or "|cffff8a8aoff|r", name,
			m.lastError and ("  |cffff8a8a" .. m.lastError .. "|r") or ""))
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
	if not f then return "|cff888888absent|r" end
	local parts, cur, depth = {}, f, 0
	while cur and depth < 8 do
		local n = (cur.GetName and cur:GetName()) or "<anon>"
		local shown = cur.IsShown and cur:IsShown()
		parts[#parts + 1] = (shown and "|cffff8a8a" or "|cff9fe8b4") .. n .. "|r"
		cur = cur.GetParent and cur:GetParent()
		depth = depth + 1
	end
	return table.concat(parts, " < ")
end

local function diag()
	A:Print("diagnostics  (|cffff8a8ared = shown|r, |cff9fe8b4green = hidden|r)")

	for name, m in A:IterateModules() do
		say("   %s %s%s", m.enabled and "|cff9fe8b4on |r" or "|cffff8a8aoff|r", name,
			m.lastError and ("  |cffff8a8a" .. m.lastError .. "|r") or "")
	end

	local AB = A:GetModule("actionbars")
	if AB then
		local abCfg = A.Config:Module("actionbars")
		say("   hideBlizzard = %s   bars built = %d",
			tostring(abCfg.hideBlizzard), #(AB.bars or {}))

		-- Nothing follows GetActionBarPage() any more, so there is no page state
		-- to report and no page drift to explain. Each bar names its own source.
		for _, bar in ipairs(AB.bars or {}) do
			say("      %s%-7s|r %-6s %s%d button%s · %d row%s",
				bar.dock:IsShown() and "|cff9fe8b4" or "|cff888888",
				bar.id, bar.kind,
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
				say("      |cffff8a8a%s|r", line)
			end
		end

	end

	local MMd = A:GetModule("minimap")
	if MMd and MMd.buttons then
		local n = 0
		for _ in pairs(MMd.buttons) do n = n + 1 end
		for _, b in ipairs(MMd.buttonOrder or {}) do
			local pt, _, _, x, y = b:GetPoint(1)
			local strataOK = b.GetFrameStrata
				and b:GetFrameStrata() == MMd.drawer:GetFrameStrata()
			say("      %-28s %s  %s %s,%s  %s lvl %s  %sx%s  hid %s  %s",
				tostring(b:GetName()), b:IsShown() and "shown" or "|cff888888hidden|r",
				tostring(pt), tostring(x and math.floor(x)), tostring(y and math.floor(y)),
				(strataOK and "" or "|cffff8a8a") .. tostring(b.GetFrameStrata and b:GetFrameStrata())
					.. (strataOK and "" or "|r"),
				tostring(b.GetFrameLevel and b:GetFrameLevel()),
				tostring(b.GetWidth and math.floor(b:GetWidth() or 0)),
				tostring(b.GetHeight and math.floor(b:GetHeight() or 0)),
				tostring(b.__aetherHidden), tostring(b.__aetherIcon and "icon ok" or "|cffff8a8ano icon found|r"))
		end
		say("   minimap drawer: %d buttons collected%s", n,
			MMd.scanError and (" |cffff8a8a(scan failed: " .. tostring(MMd.scanError) .. ")|r") or "")
		if MMd.hideReport then
			local names = {}
			for k in pairs(MMd.hideReport) do names[#names + 1] = k end
			table.sort(names)
			for _, k in ipairs(names) do
				if MMd.hideReport[k] == "STILL SHOWN" then
					say("      |cffff8a8a%s still shown|r", k)
				end
			end
		end
	end

	local AU = A:GetModule("auras")
	if AU and AU.trays then
		for _, t in ipairs(AU.trays) do
			local d = t.display
			say("   %s: %s, %d shown, %d per row, cap %d",
				t.key, t.enabled and "on" or "|cff888888off|r",
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
			local colour = (r == "hidden") and "|cff9fe8b4" or (r == "absent" and "|cff888888" or "|cffff8a8a")
			say("      %-34s %s%s|r", n, colour, r)
		end
	else
		say("   |cffff8a8ano banish report - HideBlizzard never ran|r")
	end
end

local handlers = {}

handlers.diag = diag
handlers.hide = function()
	local AB = A:GetModule("actionbars")
	if not AB or not AB.enabled then A:Print("actionbars module is not enabled.") return end
	AB:HideBlizzard()
	diag()
end

handlers.bind = function()
	local AB = A:GetModule("actionbars")
	if not AB or not AB.enabled then A:Print("actionbars module is not enabled.") return end
	AB:ToggleBindMode()
end

handlers.config  = function(arg) A.Options:Open(arg) end
handlers.options = handlers.config
handlers.unlock = function() A.Movers:Unlock() end
handlers.lock   = function() A.Movers:Lock() end
handlers.reset  = function() A.Movers:ResetAll() end
handlers.status = status
handlers.help   = usage

handlers.skin = function(arg)
	if not arg or not A.Palette.skins[arg] then
		local names = {}
		for _, s in ipairs(A.Palette:List()) do names[#names + 1] = s.key end
		A:Print("skins: " .. table.concat(names, ", "))
		return
	end
	A.db.profile.skin = arg
	A:Restyle()
	A:Print("skin -> |cffece6ff" .. arg .. "|r")
end

handlers.scale = function(arg)
	local v = tonumber(arg)
	if not v or v < 0.6 or v > 1.6 then
		A:Print("scale takes 0.6 - 1.6 (currently " .. string.format("%.2f", A.db.profile.scale)
			.. "). Module geometry is written in the concept deck's 1920px pixels; 0.71 maps"
			.. " those onto WoW's virtual space one-for-one.")
		return
	end
	A.db.profile.scale = v
	A:Reconfigure()
	A:Print("scale -> " .. string.format("%.2f", v))
end

handlers.shadow = function(arg)
	local v = tonumber(arg)
	if not v or v < 0 or v > 1 then
		A:Print("shadow takes 0 - 1 (currently " .. tostring(A.db.profile.glass.shadow)
			.. "). It is an opacity, not a distance - the geometry is derived from"
			.. " the shape so the shadow's hole matches its corner.")
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
		A:Print("idle fade -> " .. arg)
	elseif arg == "delay" then
		local v = tonumber(rest)
		if not v or v < 0.5 or v > 60 then A:Print("delay takes 0.5 - 60 seconds") return end
		cfg.delay = v
		A:Print("idle delay -> " .. v .. "s")
	elseif arg == "idle" then
		local v = tonumber(rest)
		if not v or v < 0 or v > 1 then A:Print("idle alpha takes 0 - 1") return end
		cfg.idleAlpha = v
		A.Fader:Update()
		A:Print("idle alpha -> " .. v)
	else
		A:Print(string.format("idle fade %s · delay %.1fs · idle alpha %.2f",
			cfg.enabled and "on" or "off", cfg.delay, cfg.idleAlpha))
	end
end

handlers.zen = function(arg, rest)
	local cfg = A.db.profile.modules.zen
	local cap = A.Fader.AFK_TIMEOUT

	if arg == "on" or arg == "off" then
		A:SetModuleEnabled("zen", arg == "on")
		A.Fader:Refresh()
		A:Print("zen mode -> " .. arg)
	elseif arg == "delay" then
		local v = tonumber(rest)
		if not v or v < 5 or v > cap then
			A:Print("zen delay takes 5 - " .. cap .. " seconds. The client flags you"
				.. " away at " .. cap .. ", and zen follows it there regardless.")
			return
		end
		cfg.delay = v
		A:Print("zen delay -> " .. v .. "s")
	elseif arg == "afk" then
		cfg.onAFK = (rest ~= "off")
		A:Print("zen on going away -> " .. (cfg.onAFK and "on" or "off"))
	elseif arg == "frost" then
		cfg.frost = (rest ~= "off")
		A:Print("the frosted pane -> " .. (cfg.frost and "on" or "off")
			.. " |cff9d7bff(a pane in front of the world, not a blur of it -"
			.. " nothing can blur the world)|r")
	elseif arg == "plates" then
		cfg.hideNameplates = (rest ~= "off")
		local Z = A:GetModule("zen")
		-- Turning it off mid-zen has to hand them straight back; the module only
		-- re-reads this on its next tick, and the next tick may be a fade away.
		if not cfg.hideNameplates and Z and Z.RestoreWorldText then Z:RestoreWorldText() end
		A:Print("nameplates |cff9d7bffand names|r go with zen -> "
			.. (cfg.hideNameplates and "on" or "off")
			.. " |cff9d7bff(two separate CVar families; one switch drives both)|r")
	elseif arg == "sit" then
		cfg.sit = (rest ~= "off")
		local Z = A:GetModule("zen")
		if not cfg.sit and Z and Z.StandUp then Z:StandUp() end
		A:Print("sit down in zen -> " .. (cfg.sit and "on" or "off"))
	elseif arg == "camera" then
		cfg.camera = (rest ~= "off")
		local Z = A:GetModule("zen")
		-- Straight back if it is being switched off mid-shot. Leaving somebody
		-- zoomed in over their own shoulder because they flipped a switch would
		-- be a setting that does the opposite of what it says.
		if not cfg.camera and Z and Z.RestoreCamera then Z:RestoreCamera() end
		A:Print("move the camera in zen -> " .. (cfg.camera and "on" or "off"))
	elseif arg == "audio" then
		cfg.audio = (rest ~= "off")
		local Z = A:GetModule("zen")
		if not cfg.audio and Z and Z.RestoreAudio then Z:RestoreAudio() end
		A:Print("zen audio -> " .. (cfg.audio and "on" or "off"))
	elseif arg == "track" then
		local Z = A:GetModule("zen")
		local names = { "random" }
		for _, t in ipairs((Z and Z.TRACKS) or {}) do names[#names + 1] = t.key end
		local want = rest and rest:lower() or ""
		local found = false
		for _, k in ipairs(names) do if k == want then found = true break end end
		if not found then
			A:Print("zen track takes one of: |cffece6ff" .. table.concat(names, ", ") .. "|r")
			return
		end
		cfg.track = want
		A:Print("zen track -> " .. want)
	elseif arg == "preview" then
		local Z = A:GetModule("zen")
		if not Z or not Z.PreviewTrack then A:Print("zen module is not enabled.") return end
		local name = Z:PreviewTrack(rest and rest:lower() or cfg.track)
		A:Print(name and ("playing |cffece6ff" .. name .. "|r · run it again to stop")
			or "stopped.")
	elseif arg == "test" then
		local Z = A:GetModule("zen")
		if not Z or not Z.enabled then A:Print("zen module is not enabled.") return end
		if not A.db.profile.fader.enabled then
			A:Print("idle fade is off, so there is no stage two to preview."
				.. " |cff9d7bff/aether fade on|r first.")
			return
		end
		A.Fader:ForceZen()
		A:Print("zen preview · move the mouse or press a key")
	else
		A:Print(string.format("zen %s · after %ds of quiet%s · state |cffece6ff%s|r",
			(A:GetModule("zen") or {}).enabled and "on" or "off",
			cfg.delay, cfg.onAFK ~= false and " or on going away" or "",
			A.Fader.state))
	end
end

handlers.auras = function(arg)
	local Au = A:GetModule("auras")
	if not Au or not Au.enabled then A:Print("auras module is not enabled.") return end
	if arg == "refresh" then
		Au:UpdateAll()
		A:Print("all four trays re-read.")
		return
	end
	Au:Diagnose()
end

handlers.bags = function(arg, rest)
	local B = A:GetModule("bags")
	if not B or not B.enabled then A:Print("bags module is not enabled.") return end

	if arg == "open" then
		B:Toggle()
		return
	elseif arg == "sort" then
		local f = B.frames and B.frames.bags
		if f then B:StartSort(f) end
		A:Print("compacting stacks.")
		return
	elseif arg == "sell" then
		local list, value = B:JunkList()
		if #list == 0 then A:Print("no junk to sell.") return end
		if not _G.MerchantFrame or not _G.MerchantFrame:IsShown() then
			A:Print(("|cffece6ff%d|r junk item%s worth |cffece6ff%s|r - open a merchant first.")
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
		if rest == "on" then cfg.junkAutoSell = true
		elseif rest == "off" then cfg.junkAutoSell = false
		else cfg.junkAutoSell = not cfg.junkAutoSell end
		A:Print("junk auto-sell " .. (cfg.junkAutoSell
			and "|cff9fe8b4on|r - poor-quality items go the moment a merchant opens."
			or "|cff888888off|r."))
		B:Invalidate()
		return
	end

	B:Diagnose()
end

handlers.chat = function(arg, rest)
	local C = A:GetModule("chat")
	if not C or not C.enabled then A:Print("chat module is not enabled.") return end

	-- Two parameters, like every other multi-word handler here. The dispatcher
	-- splits into cmd/arg/rest and re-splitting `arg` gets a single word with an
	-- empty value, which is a switch that always reports and never sets.
	local what, value = arg or "", rest or ""
	local cfg = A.Config:Module("chat")

	if what == "reskin" then C:Reskin(); A:Print("chat re-skinned.") return end

	--- The three line settings that are worth reaching for mid-session. The
	--  rest live in the options panel, where a setting with a paragraph of
	--  explanation belongs.
	local switches = {
		lines  = { key = "styleLines", label = "message line styling" },
		badges = { key = "badges",     label = "channel badges" },
	}
	local sw = switches[what]
	if sw then
		if value ~= "on" and value ~= "off" then
			A:Print(sw.label .. " is |cffece6ff"
				.. (cfg[sw.key] ~= false and "on" or "off") .. "|r.")
			return
		end
		cfg[sw.key] = (value == "on")
		A:Reconfigure()
		A:Print(sw.label .. " -> |cffece6ff" .. value .. "|r")
		return
	end

	if what == "whispers" then
		if value ~= "on" and value ~= "off" then
			A:Print("whispers tab is |cffece6ff"
				.. (cfg.whisperTab == true and "on" or "off") .. "|r. It opens a"
				.. " real chat window and moves the whisper message groups onto"
				.. " it - which Blizzard saves, and keeps saved with this addon"
				.. " off.")
			return
		end
		if C:SetWhisperTab(value == "on") then
			cfg.whisperTab = (value == "on")
		end
		return
	end

	C:Diagnose()
end

handlers.health = function(arg)
	if arg ~= "class" and arg ~= "deck" then
		A:Print("health bar colour is |cffece6ff"
			.. (A.db.profile.classColorHealth and "class" or "deck")
			.. "|r. 'class' colours players by class; 'deck' uses the concept's"
			.. " green and reserves colour for reaction.")
		return
	end
	A.db.profile.classColorHealth = (arg == "class")
	A:Restyle()
	A:Print("health bar colour -> |cffece6ff" .. arg .. "|r")
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
	A:Print("bars:")
	for _, b in ipairs(cfg.bars) do
		local live
		for _, built in ipairs(AB and AB.bars or {}) do
			if built.id == tostring(b.id) then live = built end
		end
		say("   %s%-7s|r %-8s %s%s%s",
			b.enabled and "|cff9fe8b4" or "|cffff8a8a", tostring(b.id),
			b.kind or "action",
			(b.kind or "action") == "action"
				and string.format("page %d · %d buttons", b.page or 1, b.buttons or 12)
				or string.format("%d buttons", live and #live.buttons or 0),
			string.format(" · %d row%s", b.rows or 1, (b.rows or 1) == 1 and "" or "s"),
			string.format(" · scale %.2f", b.scale or 1))
	end
	say("   |cff888888/aether bar <id> on|off|buttons N|rows N|page N|scale N|backdrop|r")
end

handlers.bar = function(arg, rest)
	local cfg = A.Config:Module("actionbars")
	local AB = A:GetModule("actionbars")

	if not arg or arg == "" or arg == "list" then return BarList() end

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
			A:Print(("bar %s takes %s - %s. |cff888888%s|r"):format(arg, lo, hi, note))
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
		A:Print("no bar |cffece6ff" .. tostring(arg) .. "|r.")
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
		if not AB or not AB.enabled then A:Print("actionbars module is not enabled.") return end
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
handlers.tooltips = function(arg)
	local T = A:GetModule("tooltips")
	if not T or not T.enabled then A:Print("tooltips module is not enabled.") return end
	local cfg = A.Config:Module("tooltips")

	if arg == "cursor" then
		cfg.cursorItems = not cfg.cursorItems
		A:Print("item and spell tooltips " .. (cfg.cursorItems
			and "|cff9fe8b4follow the cursor|r."
			or "|cff888888stay where whatever opened them put them|r."))
	elseif arg == "anchor" then
		cfg.unitAnchor = not cfg.unitAnchor
		A:Print("unit tooltips " .. (cfg.unitAnchor
			and "anchored to their corner - /aether unlock to move it."
			or "back on Blizzard's default anchor."))
	elseif arg == "badge" then
		cfg.levelBadge = not cfg.levelBadge
		A:Print("level badge " .. (cfg.levelBadge and "on" or "off")
			.. " - this is the one setting that rewrites tooltip text.")
	elseif arg == "sweep" then
		local n = T:Sweep()
		A:Print(("swept: |cffece6ff%d|r new tooltip frame%s adopted.")
			:format(n, n == 1 and "" or "s"))
	else
		T:Diagnose()
		A:Print("usage: /aether tooltips cursor|anchor|badge|sweep")
	end
end

handlers.quests = function(arg)
	local QT = A:GetModule("questtracker")
	if not QT or not QT.enabled then A:Print("questtracker module is not enabled.") return end
	local cfg = A.Config:Module("questtracker")

	if arg == "fold" then
		QT:ToggleCollapsed()
		A:Print("quest tracker " .. (QT.collapsed and "folded" or "unfolded") .. ".")
	elseif arg == "objectives" then
		cfg.showObjectives = not cfg.showObjectives
		QT:Refresh()
		A:Print("objective lines " .. (cfg.showObjectives and "on" or "off") .. ".")
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
		A:Print("tracking reset.")
	else
		local n = QT.quests and #QT.quests or 0
		A:Print(string.format(
			"%s mode · showing %d quest%s%s  (usage: /aether quests fold|auto|objectives|clear)",
			(cfg.autoTrack ~= false) and "auto" or "manual", n, n == 1 and "" or "s",
			(QT.hidden or 0) > 0 and (" · " .. QT.hidden .. " did not fit") or ""))
	end
end

handlers.module = function(arg, rest)
	if not arg or not A.modules[arg] then
		local names = {}
		for name in A:IterateModules() do names[#names + 1] = name end
		A:Print("modules: " .. table.concat(names, ", "))
		return
	end
	if rest ~= "on" and rest ~= "off" then
		A:Print("usage: /aether module " .. arg .. " on|off")
		return
	end
	A:SetModuleEnabled(arg, rest == "on")
	A:Print("module " .. arg .. " -> " .. rest)
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
		fn(arg ~= "" and arg:lower() or nil, rest ~= "" and rest:lower() or nil)
	else
		A:Print("unknown command '" .. cmd .. "'")
		usage()
	end
end
