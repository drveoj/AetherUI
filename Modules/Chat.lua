--[[--------------------------------------------------------------------------
	AetherUI :: Chat

	The concept's chat: one frosted panel, tabs as pills along the top with the
	zone right-aligned beside them, a divider, and the edit box sitting inside the
	panel's bottom edge with a channel tag and a send glyph.

	Blizzard's chat frames are skinned in place rather than replaced. A
	replacement would break every chat addon on the machine, the whisper and
	hyperlink plumbing, and half of what the client does with a ScrollingMessageFrame.

	What is here
	------------
	Two halves. Everything above the fold is frame work: panel, tabs, type, edit
	box, buttons. Below it are the message lines - class-coloured names with the
	realm dimmed, an em dash where Blizzard says "says:", a channel badge, dimmed
	system lines and an optional whispers tab.

	The line work never touches the author string. Blizzard hands us the
	*decorated* name and builds the player hyperlink around what we hand back,
	from an argument we never see written to - so whispers, ignore and the
	right-click menu are structurally out of reach rather than carefully avoided.
	The long comment above `the message lines` has the source that says so.

	Facts this leans on, from Blizzard's own Classic Era source
	----------------------------------------------------------
	* `CHAT_FRAMES` holds frame **name strings**, not frames, and it grows and
	  shrinks as temporary windows come and go. It is the only correct way to
	  enumerate. `NUM_CHAT_WINDOWS` is not used by Blizzard's own Era code.
	* `CHAT_FRAME_TEXTURES` is the canonical list of backdrop region suffixes.
	* **Hiding a backdrop region matters more than clearing its texture.** Both
	  `FCF_FadeInChatFrame` and `FCF_FadeOutChatFrame` walk `CHAT_FRAME_TEXTURES`
	  and skip anything that is not shown. `SetTexture(nil)` leaves the region
	  shown, so it stays in the fade loops and the client keeps animating an
	  invisible thing - and keeps putting its alpha back. Hide it and it drops out
	  of both loops for good. That one fact is the difference between a skin that
	  holds and a skin that needs re-applying on a timer.
	* The button frame is **parked off-screen with clipping on**, not hidden.
	  Blizzard re-shows it from several places; moving it out of the panel is a
	  fight nobody has to win.
	* `frame.ScrollToBottomButton` has a parentKey and **no global name**.
	  `_G["ChatFrame1ScrollToBottomButton"]` is nil.
	* There is no scrollbar on Classic Era - the `<Slider>` is commented out in
	  Blizzard's XML - so there is nothing to skin.
	* Tabs have no `Active` texture set on Classic Era; that is retail-only. The
	  global names are `<tab>Left`-style while the parentKeys are `leftTexture`-
	  style, which is why both are tried.
	* `QuickJoinToastButton` and the voice toggles are retail-only.

	Hook points, for the same reason: these are the functions that put Blizzard's
	look back after we have taken it off.
--------------------------------------------------------------------------]]

local ADDON, A = ...

local Chat = A:NewModule("chat")

local W, Media, Palette, Glass = A.Widgets, A.Media, A.Palette, A.Glass

local PAD      = 10    -- panel inset around the chat frame
-- The band the tab row is allowed to occupy, NOT the tab's own height. A docked
-- ChatFrameTab is 32 tall (ChatTabArtTemplate, `<Size x="64" y="32"/>`) and the
-- dock it sits in is 26 (DockManagerTemplate), so the tab overhangs the dock by
-- 3px top and bottom. The divider is placed from this number.
local TAB_H    = 20
local TAB_PAD  = 10    -- horizontal padding either side of a tab's word
local EDIT_H   = 26
-- The resize grip's hit target. Bigger than the mark drawn inside it, because a
-- corner grip is found with a cursor rather than read.
local GRIP     = 20
local EDIT_GAP = 6
-- The channel capsule inside the composer is sized from the typing font rather
-- than fixed - see Chat:TagHeight. This is the padding around the code in it.
local TAG_PAD_Y = 5

-- Chat is a READING surface - see Palette:ReadingFill. It sits over moving,
-- high-contrast scenery and carries paragraphs of small text, so it takes more
-- opacity than a control surface does. The quest log takes the same treatment
-- and from the same helper, so the two cannot drift apart.
local function ChatFill(c)
	return Palette:ReadingFill(c)
end

-- Blizzard's own list, with a fallback for the unlikely case of it being absent.
local BACKDROP = _G.CHAT_FRAME_TEXTURES or {
	"Background",
	"TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
}

-- The three-piece sets on a tab. "Active" is retail-only and resolves to nil
-- here, which is why this walks a list rather than naming them.
local TAB_SETS   = { "", "Selected", "Highlight" }
local TAB_PIECES = { "Left", "Middle", "Right" }

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------

--- Hide a region and stop it drawing. Hide first: see the note about the fade
--  loops at the top - it is the Hide that gets it out of them, not the texture.
local function Kill(region)
	if not region then return end
	if region.Hide then pcall(region.Hide, region) end
	if region.SetTexture then pcall(region.SetTexture, region, nil) end
	if region.SetAlpha then pcall(region.SetAlpha, region, 0) end
end

--- A named region of a frame, by global name first and parentKey second,
--  because Blizzard's two naming schemes for tab art do not agree.
local function Region(frame, globalSuffix, key)
	local name = frame.GetName and frame:GetName()
	local r = name and _G[name .. globalSuffix]
	if r then return r end
	return key and frame[key] or nil
end

--- Every real chat frame. CHAT_FRAMES holds names, and it moves.
local function EachFrame(fn)
	local list = _G.CHAT_FRAMES
	if not list then return end
	for _, frameName in ipairs(list) do
		local f = _G[frameName]
		if f then fn(f, frameName) end
	end
end

Chat.EachFrame = EachFrame

-- ---------------------------------------------------------------------------
-- the panel
-- ---------------------------------------------------------------------------

local function BuildPanel()
	local p = Glass.CreatePanel(UIParent, {
		corner = 14,
		shadow = A.db.profile.glass.shadow,
		name   = ADDON .. "ChatPanel",
	})
	p:SetFillColor(ChatFill(Palette.c))
	p:SetFrameStrata("BACKGROUND")
	p:EnableMouse(false)

	-- The zone, right-aligned on the tab row, as drawn.
	p.zone = W.Text(p, "tiny", "RIGHT")

	p.divider = p:CreateTexture(nil, "ARTWORK")
	p.divider:SetTexture(Media.texture.divider)

	return p
end

function Chat:AnchorPanel()
	local p, cf = self.panel, _G.ChatFrame1
	if not p or not cf then return end
	local dock = _G.GeneralDockManager

	p:ClearAllPoints()
	if dock then
		p:SetPoint("TOPLEFT", dock, "TOPLEFT", -PAD, PAD)
	else
		p:SetPoint("TOPLEFT", cf, "TOPLEFT", -PAD, PAD + TAB_H)
	end
	p:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", PAD, -(EDIT_H + EDIT_GAP + PAD))

	p.zone:ClearAllPoints()
	p.zone:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD - 4, -PAD - 2)

	p.divider:ClearAllPoints()
	p.divider:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(PAD + TAB_H + 4))
	p.divider:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -(PAD + TAB_H + 4))
	W.PaintHairline(p.divider)

	self:UpdateZone()
end

function Chat:UpdateZone()
	local p = self.panel
	if not p then return end
	local cfg = A.Config:Module("chat")
	if cfg.showZone == false then p.zone:SetText("") return end
	local zone = (GetMinimapZoneText and GetMinimapZoneText()) or ""
	if zone == "" then zone = (GetZoneText and GetZoneText()) or "" end
	p.zone:SetText(zone)
end

-- ---------------------------------------------------------------------------
-- tabs
-- ---------------------------------------------------------------------------

local function TabText(tab)
	return Region(tab, "Text", "Text")
		or (tab.GetFontString and tab:GetFontString())
end

--- Strip a tab's artwork and give it our pill. Idempotent: Blizzard rebuilds
--  and re-colours tabs from several places and we are hooked onto all of them.
function Chat:SkinTab(tab)
	if not tab then return end

	if not tab._aether then
		tab._aether = true

		-- A TAB, WHICH IS NOT A BUTTON. It was a filled pill - the same surface
		-- Send, Accept and Create wear - and that is exactly the confusion the
		-- tab language exists to end: a button does a thing, a tab changes
		-- which view of the frame you are looking at.
		--
		-- Chat's rail is on TOP of the window, so its line and its marks are on
		-- the bottom - the edge facing the log they switch between. And the
		-- mark is placed HERE rather than by the shared code, because a chat
		-- tab's own frame is Blizzard's 32-tall art box, three pixels taller
		-- than the dock and centred on a line that is not the hairline.
		W.Tab(tab, { edge = "TOP", label = TabText(tab) })
		tab.__aetherMarkOwn = true

		tab:HookScript("OnEnter", function(t) Chat:StyleTab(t) end)
		tab:HookScript("OnLeave", function(t) Chat:StyleTab(t) end)

		-- Blizzard keeps docked tabs invisible until you hover the chat frame -
		-- `ChatTabArtTemplate` starts at alpha 0.4 and `FCFTab_UpdateAlpha` takes
		-- it to `noMouseAlpha` from there, and the fade functions animate it on
		-- top of that. The concept has every tab on screen all the time, so this
		-- takes ownership of the tab's alpha outright: anything that tries to
		-- lower it gets it put straight back.
		if tab.SetAlpha and _G.hooksecurefunc then
			pcall(hooksecurefunc, tab, "SetAlpha", function(t, a)
				if t._alphaLock or not Chat.enabled then return end
				if a ~= 1 then
					t._alphaLock = true
					t:SetAlpha(1)
					t._alphaLock = false
				end
			end)
		end
	end

	-- A fade already in flight would keep setting alpha behind the hook.
	if _G.UIFrameFadeRemoveFrame then pcall(_G.UIFrameFadeRemoveFrame, tab) end
	tab:SetAlpha(1)

	for _, set in ipairs(TAB_SETS) do
		for _, piece in ipairs(TAB_PIECES) do
			Kill(Region(tab, set .. piece, string.lower(piece)
				.. (set == "" and "Texture" or (set .. "Texture"))))
		end
	end
	Kill(Region(tab, "Glow", "glow"))
	Kill(Region(tab, "Flash", nil))
	Kill(tab.conversationIcon)

	local fs = TabText(tab)
	if fs then
		Media:SetFont(fs, "chatTab")
		-- Adopted font strings do not come from W.Text, so nothing has recorded
		-- which role they are playing. W.Restyle reads this, and without it a
		-- skin change would leave Blizzard's own font strings behind.
		fs._aetherStyle = "chatTab"
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", tab, "CENTER", 0, 0)
	end

	self:StyleTab(tab)
end

--- Which chat frame the dock currently has selected, as an ID.
--
--  `dock.selected` is a FRAME, not an index. Blizzard's own
--  `FCFDock_SelectWindow` ends with `dock.selected = chatFrame`, and
--  `FCFDock_GetSelectedWindow` hands that straight back. Comparing it to
--  `tab:GetID()` is comparing a table to a number, which is never equal - so
--  the selected tab never lit up in game, and the harness's mock stored a
--  number and let it pass offline for weeks.
--
--  Both shapes are accepted here: a frame is asked for its id, a number is
--  taken as one. That costs nothing and means a client that ships the other
--  shape does not silently lose the highlight again.
local function SelectedChatID(dock)
	-- Called with a colon, `dock` is the module table: non-nil, no `.selected`,
	-- and every tab quietly goes unselected with no error to show for it.
	if dock == Chat then dock = nil end
	dock = dock or _G.GeneralDockManager
	if not dock then return nil end

	local sel = dock.selected
	if _G.FCFDock_GetSelectedWindow then
		local ok, w = pcall(_G.FCFDock_GetSelectedWindow, dock)
		if ok and w ~= nil then sel = w end
	end

	if type(sel) == "table" and sel.GetID then
		local ok, id = pcall(sel.GetID, sel)
		if ok and type(id) == "number" then return id end
	end
	if type(sel) == "number" then return sel end
	return nil
end

Chat.SelectedChatID = SelectedChatID

--- Should this tab read as the one you are looking at?
--
--  Three answers, in order of how much they know:
--
--  1. `FCFTab_UpdateColors(tab, selected)` is Blizzard telling us directly, and
--     it is right for docked and undocked windows alike. The hook stashes it.
--     `SkinAllTabs` clears the stash first so a stale flag cannot strand a pill
--     on a tab the dock has since moved away from.
--  2. An undocked window is not *in* the dock, so it can never be the dock's
--     selection - but it is the window you are reading, and Blizzard's own
--     colour logic treats it as selected. Without this, undocking the combat
--     log left its tab permanently dimmed.
--
--     `not f.isDocked`, NOT `f.isDocked == false`. The client only ever writes
--     `1` or `nil` (FloatingChatFrame.lua:1787 and :1821 are the only two
--     assignments in the file), and its own predicate at :135 and :534 reads
--     `not chatFrame.isDocked`. Written as `== false` this tier never fired on
--     a real client at all - it only fired in the harness, against a value the
--     game does not use, which is the most flattering kind of wrong.
--
--     `IsShown` matters because a CLOSED window is undocked too: FCF_Close
--     leaves it in CHAT_FRAMES with `isDocked = nil` forever.
--  3. Otherwise ask the dock.
local function TabIsSelected(tab, alt)
	-- Called with a colon, `tab` is the module table. Same trap `SelectedChatID`
	-- grew a guard for one function ago; no sense leaving it open here.
	if tab == Chat then tab = alt end
	if not tab then return false end

	if tab._aetherSelected ~= nil then
		return tab._aetherSelected and true or false
	end

	local id = tab.GetID and tab:GetID()
	if not id then return false end   -- else `nil == nil` lights an unknown tab

	local f = _G["ChatFrame" .. id]
	if f and not f.isDocked and f.IsShown and f:IsShown() then return true end

	return SelectedChatID() == id
end

Chat.TabIsSelected = TabIsSelected

--- Colour a tab for its current state and size it to its word.
function Chat:StyleTab(tab)
	if not tab or not tab._aether then return end
	local fs = TabText(tab)
	local selected = TabIsSelected(tab)
	local hovered = tab.IsMouseOver and tab:IsMouseOver()

	if fs then
		-- Hand the label back its own dimensions before measuring it.
		--
		-- PanelTemplates_TabResize runs twice per click (FCF_SelectDockFrame
		-- then FCFDock_UpdateTabs) and leaves the string a hard width, and on
		-- the selected tab it also leaves the string a fixed height of 8 that
		-- nothing ever clears.
		--
		-- A FontString with a hard width narrower than its text WRAPS, and a
		-- rect that is not the size of its own text is what makes "CENTER"
		-- stop meaning centred. Both are why the label drifted off the middle
		-- after the first click and stayed there.
		if fs.SetWidth then fs:SetWidth(0) end
		if fs.SetHeight then fs:SetHeight(0) end
		if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end

		local w = (fs:GetStringWidth() or 30) + TAB_PAD * 2
		tab:SetWidth(w)
	end

	-- THE THREE STATES, and they are the interface's, not this file's: bright
	-- for the tab you are reading, dim under the cursor, faint for the rest.
	tab.__aetherLabel = fs
	W.TabState(tab, selected, hovered)

	-- THE MARK ON THE RAIL'S OWN LINE. Measured from the LABEL for its width
	-- and from the divider for its height, which is the only way it can be
	-- right: the tab is not ours - PanelTemplates_TabResize overwrites its
	-- width on every dock update, to `dynTabSize` for a dynamic tab and to a
	-- hard 32 of Blizzard's own art padding for ChatFrame1's - so anything
	-- measured from the tab drifts away from the word it belongs to. And the
	-- tab's box is 32 tall against a 26 dock, so its bottom edge is nowhere
	-- near the hairline the mark is supposed to sit on.
	local mark = tab.__aetherMark
	local rule = self.panel and self.panel.divider
	if mark and fs and rule then
		mark:ClearAllPoints()
		mark:SetPoint("LEFT", fs, "LEFT", -4, 0)
		mark:SetPoint("RIGHT", fs, "RIGHT", 4, 0)
		mark:SetPoint("BOTTOM", rule, "BOTTOM", 0, 0)
		mark:SetHeight(2)

		local glow = tab.__aetherMarkGlow
		if glow then
			glow:ClearAllPoints()
			glow:SetPoint("TOPLEFT", mark, "TOPLEFT", -6, 6)
			glow:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 6, -6)
		end
	end

end

--- Is this window one you get spoken to in?
--
--  The handoff reserves the GOLD dot for something addressed to you - a
--  whisper, an invite - and leaves the accent for ordinary traffic. Blizzard's
--  flash says only that something arrived, so the window is asked what it is
--  registered to carry instead.
local function IsPersonal(frame)
	if not frame or not _G.ChatFrame_ContainsMessageGroup then return false end
	for _, group in ipairs({ "WHISPER", "BN_WHISPER" }) do
		local ok, yes = pcall(_G.ChatFrame_ContainsMessageGroup, frame, group)
		if ok and yes then return true end
	end
	return false
end

--- The unread dot. Blizzard's flash texture is the signal; it is driven by an
--  animation rather than an event, so this reads it on the shared ticker rather
--  than trying to find a hook that does not exist.
function Chat:UpdateFlashes()
	EachFrame(function(f)
		local tab = _G[(f:GetName() or "") .. "Tab"]
		if not tab or not tab.__aetherDot then return end

		local flash = Region(tab, "Flash", nil)
		local lit = flash and flash.IsShown and flash:IsShown()

		-- Never on the tab you are reading. Blizzard's flash runs with
		-- flashDuration -1, so it stays shown until something stops it, and
		-- selecting a tab is not always that something - which put an unread
		-- marker on the window whose contents were in front of you.
		if TabIsSelected(tab) then lit = false end

		W.TabDot(tab, lit and (IsPersonal(f) and "personal" or "new") or nil,
			TabText(tab))
	end)
end

function Chat:SkinAllTabs()
	EachFrame(function(f)
		local name = f:GetName()
		local tab = name and _G[name .. "Tab"]
		if not tab then return end
		-- Drop what Blizzard last told us about this tab. This runs when the
		-- selection has just moved, so the flag from the previous selection is
		-- exactly the thing that would leave two pills lit at once.
		tab._aetherSelected = nil
		Chat:SkinTab(tab)
	end)
end

-- ---------------------------------------------------------------------------
-- the frame itself
-- ---------------------------------------------------------------------------

function Chat:SkinFrame(f)
	if not f then return end
	local cfg = A.Config:Module("chat")
	local name = f:GetName()

	for _, suffix in ipairs(BACKDROP) do
		Kill(name and _G[name .. suffix] or nil)
		Kill(f[suffix])
	end

	-- Message fading is the client's own and separate from the frame artwork.
	-- Both are ScrollingMessageFrame methods and both exist on Classic Era.
	if f.SetFading then pcall(f.SetFading, f, cfg.fadeMessages == true) end
	if f.SetTimeVisible then pcall(f.SetTimeVisible, f, cfg.timeVisible or 120) end

	if f.SetClampRectInsets then pcall(f.SetClampRectInsets, f, 0, 0, 0, 0) end
	if f.SetMaxResize then pcall(f.SetMaxResize, f, 2000, 2000) end
	if f.SetMinResize then pcall(f.SetMinResize, f, 120, 40) end

	self:SetFrameFont(f)
	self:ParkButtons(f)
	self:SkinEditBox(f)
	self:SkinResize(f)
	self:SetUnlocked(f)
	-- Once per frame and idempotent, so a temporary window that appears later -
	-- or the whispers tab, which is created after everything else - gets the
	-- same treatment without this having to know when that happened.
	self:WrapAddMessage(f)
end

--- The size stays Blizzard's - it is a real setting with a real UI behind it -
--  and we own the face and the outline. Read back rather than remembered, so
--  changing the size in Blizzard's own menu is not fought with.
--
--  One function so the edit box can ask the same question: typing at one size
--  and reading the result back at another is the sort of thing you cannot
--  un-notice.
function Chat:FontSize(f)
	local size
	if _G.FCF_GetChatWindowInfo and f and f.GetID then
		local ok, _, s = pcall(_G.FCF_GetChatWindowInfo, f:GetID())
		if ok and s and s > 0 then size = s end
	end
	if not size and f and f.GetFont then size = select(2, f:GetFont()) end
	return math.max(6, (size or 13) + (A.Config:Module("chat").fontDelta or 0))
end

--- The composer's channel capsule, sized from what you are typing at.
--
--  It used to be a fixed 16 with the `chatTab` role's own 11pt type inside it,
--  which meant the code in the capsule was *larger* than the text beside it and
--  the capsule was two thirds the height of the whole composer. Both now follow
--  `FontSize`, so the capsule stays in proportion at any chat font size instead
--  of being right at one of them.
function Chat:TagHeight(f)
	return math.min(EDIT_H - 6, self:FontSize(f) + TAG_PAD_Y * 2)
end

function Chat:ChatFontPath()
	return Media.font[(Media.style.chatText or {})[1] or "regular"] or Media.font.regular
end

function Chat:SetFrameFont(f)
	if not f or not f.SetFont then return end
	pcall(f.SetFont, f, self:ChatFontPath(), self:FontSize(f), "")
	if f.SetShadowColor then
		pcall(f.SetShadowColor, f, 0, 0, 0, 0.6)
		pcall(f.SetShadowOffset, f, 1, -1)
	end
end

--- The scroll buttons and the resize grip. Parked rather than hidden, because
--  Blizzard re-shows this frame from several places and moving it somewhere
--  nobody can see costs nothing to lose.
function Chat:ParkButtons(f)
	local cfg = A.Config:Module("chat")
	if cfg.hideButtons == false then return end

	local bf = f.buttonFrame or _G[(f:GetName() or "") .. "ButtonFrame"]
	if bf then
		if bf.SetClipsChildren then pcall(bf.SetClipsChildren, bf, true) end
		pcall(bf.ClearAllPoints, bf)
		pcall(bf.SetPoint, bf, "TOPLEFT", UIParent, "TOPLEFT", -10000, 0)
	end

	-- parentKey only; there is no global for this one
	Kill(f.ScrollToBottomButton)
end

-- ---------------------------------------------------------------------------
-- moving and resizing
-- ---------------------------------------------------------------------------

--- Blizzard's own grip, stripped and moved to our corner.
--
--  Its own drag scripts are left alone deliberately. Driving StartSizing by hand
--  would mean re-implementing the clamping, the minimum size and the save, and
--  Blizzard's version already persists into its own saved variables where the
--  rest of the chat settings live - so a resize survives this addon being turned
--  off, which a private copy of the number would not.
--- Tell BLIZZARD where the chat frame ended up, as well as ourselves.
--
--  ChatFrame1 is not ours. It belongs to the FCF dock, which keeps its own
--  per-character record of position and size and re-applies it on events we do
--  not all hear - and it has no idea we moved anything, because we drag it
--  directly rather than through its tab.
--
--  On a character that has been played, Blizzard's record is near enough to
--  where you had things that nothing looks wrong. On a NEW one it is the
--  default, so a chat window you have just dragged goes back to the corner a
--  few seconds later and it reads as our position not having saved. Ours had
--  saved; theirs simply disagreed and got the last word.
--
--  Written THROUGH Blizzard's own function rather than into its saved variables,
--  which is the same rule as locking a LibDBIcon button through the library: the
--  supported call knows about the parts of the record we do not.
--
--  Guarded and pcalled. This is the same treatment FCF_SetLocked gets a few
--  lines below, for the same reason - a client without it should cost us the
--  handshake, not the drag.
local function SaveToBlizzard(f)
	if not f or not f.GetID then return end
	if not _G.FCF_SavePositionAndDimensions then return end

	-- pcall, and NOT a docked check.
	--
	-- The obvious reading of the crash report was "never call this on a docked
	-- frame", and that is wrong here: ChatFrame1 is itself docked in the default
	-- layout, so the guard would switch off the handshake in the only case it
	-- exists for. The crash was Blizzard's OWN handler running on ChatFrame2 -
	-- a window we should never have been showing a grip on - and it is fixed by
	-- not showing those grips, which is where the fix belongs.
	--
	-- If the client cannot save a docked window's position, this quietly does
	-- nothing, which is what it did before and no worse. What actually holds our
	-- position is the hook on FCF_RestorePositionAndDimensions.
	pcall(_G.FCF_SavePositionAndDimensions, f)
end

-- ---------------------------------------------------------------------------
-- who keeps moving the chat window
--
-- Four fixes have been aimed at this and it still walks home on a new
-- character. Every one of them named a function - tell the dock, hook the
-- restore, tell the dock on the restore path too - and naming functions only
-- works if you can name them all. This one asks the frame instead, and writes
-- down the answer so the next report can name the culprit rather than the
-- symptom.
-- ---------------------------------------------------------------------------

--- What moved it, most recent first. Read out by `/aether chat where`.
Chat.moves = {}

local MAX_MOVES = 8
local reanchoring = false

--- The anchor we believe in: what the player saved, or our own default.
local function WantedAnchor()
	local entry = A.Movers and A.Movers.registry and A.Movers.registry.chat
	if not entry then return nil end
	local saved = A.db and A.db.profile.anchors and A.db.profile.anchors.chat
	if saved and saved.point then return saved end
	return entry.default
end

--- The first line of the call stack that names somebody we can go and look at.
--
--  Two kinds of frame get skipped, and the second one cost a round trip.
--
--  Ours, because every frame between the SetPoint and whoever asked for it is
--  this file, so reporting the top of the stack names this addon every time.
--
--  And `[C]:` frames, because the widget method itself is one: the stack from
--  inside this hook reads OUR hook, then `[C]: in function 'SetPoint'`, and only
--  THEN the Lua that called it. The first report back said "by [C]: in function
--  'SetPoint'" three times, which is the truth and tells nobody anything - it is
--  the function we hooked, not the one that called it.
local function Culprit()
	if type(_G.debugstack) ~= "function" then return "?" end
	local ok, s = pcall(_G.debugstack, 2, 10, 0)
	if not ok or type(s) ~= "string" then return "?" end

	for line in s:gmatch("[^\r\n]+") do
		local trimmed = line:gsub("^%s+", "")
		if not trimmed:find("AetherUI", 1, true)
			and not trimmed:find("^%[C%]:") then
			return trimmed:sub(1, 110)
		end
	end
	return (s:gsub("[\r\n]+", " "):sub(1, 110))
end

--- Is the window where we put it? If not, put it back and say who moved it.
function Chat:WatchPosition(f)
	if reanchoring or not f or f ~= _G.ChatFrame1 then return end

	-- Not while the player is arranging things. Our own drag IS a SetPoint on
	-- every frame of it, so a watcher that answers back is a window that cannot
	-- be moved at all.
	if A.Movers and A.Movers.unlocked then return end

	local want = WantedAnchor()
	if not want then return end

	local point, rel, relPoint, x, y = f:GetPoint(1)
	if point == want.point
		and relPoint == (want.relPoint or want.point)
		and rel == _G.UIParent
		and math.abs((x or 0) - (want.x or 0)) < 0.5
		and math.abs((y or 0) - (want.y or 0)) < 0.5 then
		return
	end

	table.insert(self.moves, 1, {
		by    = Culprit(),
		point = point or "?",
		x     = x or 0,
		y     = y or 0,
	})
	for i = #self.moves, MAX_MOVES + 1, -1 do table.remove(self.moves, i) end

	reanchoring = true
	if A.Movers and A.Movers.registry.chat then A.Movers:Restore("chat") end
	reanchoring = false
end

-- ---------------------------------------------------------------------------
-- the size, which is ours to remember
-- ---------------------------------------------------------------------------

local MIN_W, MIN_H = 200, 90

local function ChatChar()
	if not A.db or not A.db.char then return nil end
	A.db.char.chat = A.db.char.chat or {}
	return A.db.char.chat
end

--- Write down what the window is now, in its own units.
function Chat:SaveSize(f)
	f = f or _G.ChatFrame1
	local c = ChatChar()
	if not c or not f or not f.GetWidth then return false end
	local w, h = f:GetWidth(), f:GetHeight()
	if not w or not h or w < MIN_W or h < MIN_H then return false end
	c.w, c.h = math.floor(w + 0.5), math.floor(h + 0.5)
	return true
end

--- ...and put it back.
--
--  Called after the client has finished restoring, not instead of it. Blizzard
--  applies its own saved dimensions and then the dock re-flows the window, so
--  anything we do first is overwritten by the thing we were trying to correct.
--
--  Bounded by the same minimum the grip enforces, because a saved variable is a
--  file somebody can edit and a 12px chat window is unrecoverable from inside
--  the game.
function Chat:RestoreSize(f)
	f = f or _G.ChatFrame1
	local c = ChatChar()
	if not c or not f or not f.SetSize then return false end
	local w, h = tonumber(c.w), tonumber(c.h)
	if not w or not h then return false end
	w = math.max(MIN_W, w)
	h = math.max(MIN_H, h)
	if math.abs((f:GetWidth() or 0) - w) < 0.5
		and math.abs((f:GetHeight() or 0) - h) < 0.5 then
		return false                       -- already right; do not churn the dock
	end
	pcall(f.SetSize, f, w, h)
	-- The dock has to be told, or it puts its own answer back at the next thing
	-- that makes it think - which is the same reason the drag itself calls this.
	if _G.FCF_DockUpdate then pcall(_G.FCF_DockUpdate) end
	self:AnchorPanel()
	return true
end

--- A grip of OUR OWN, for a client that has not got one to borrow.
--
--  The first version of this leaned entirely on Blizzard's button and said so:
--  driving StartSizing by hand means owning the clamping, the minimum size and
--  the save. That reasoning was right and the premise was wrong - on this
--  client there is no button to find, in any of the four places it could be, so
--  "use Blizzard's" resolved to "there is no way to resize the chat window".
--
--  So the three things that reasoning was protecting are done explicitly:
--
--    clamping   SetResizeBounds, guarded - the call is 10.x and later, and a
--               client without it has its own bounds from the XML template
--    sizing     StartSizing / StopMovingOrSizing, which is what Blizzard's own
--               grip calls; we are not reimplementing the drag, only starting it
--    the save   FCF_SavePositionAndDimensions on release, so the new size lands
--               in Blizzard's saved variables where the rest of the chat
--               settings live and survives this addon being turned off
function Chat:BuildGrip(f)
	local p = self.panel
	if not p or self._grip then return self._grip end

	local g = CreateFrame("Button", ADDON .. "ChatGrip", p)
	g:SetSize(GRIP, GRIP)
	g:EnableMouse(true)
	g:RegisterForDrag("LeftButton")

	local dots = g:CreateTexture(nil, "OVERLAY")
	dots:SetTexture(Media.texture.chevron)
	-- The chevron on its side reads as a corner grip, and it is already in the
	-- pack. A second asset for a corner mark would be silly.
	-- +45, not -45. Chevron.tga points DOWN, and rotation is counter-clockwise,
	-- so (0,-1) at +45 becomes (0.707,-0.707) - down and to the RIGHT, which is
	-- the corner this sits in. At -45 it pointed down-LEFT, across the window it
	-- is meant to be dragging outward, which is the "weirdly oriented".
	dots:SetRotation(math.rad(45))
	dots:SetSize(GRIP - 6, GRIP - 6)
	dots:SetPoint("CENTER", g, "CENTER", 0, 0)
	g._dots = dots

	-- SIZED BY HAND, not with StartSizing.
	--
	-- StartSizing hands the frame to the cursor and lets the client resize it,
	-- which is what Blizzard's own grip does - and on a DOCKED window the dock
	-- re-flows the frame immediately afterwards, so the drag did nothing you
	-- could see. That is "I can see it now on both tabs but it does nothing".
	--
	-- Setting the size directly and then telling the dock about it is the way
	-- round that: the dock is the thing that decides, so it has to be the thing
	-- that is told.
	--
	-- The minimum is the file-local above, not a second copy here. The drag
	-- clamps to it and RestoreSize clamps to it, and two numbers that have to
	-- agree are two numbers that can stop agreeing - the failure being a saved
	-- size the grip would refuse to produce.

	local function Drag(self2)
		local cf = g._frame
		if not cf or InCombatLockdown() then return self2:SetScript("OnUpdate", nil) end
		local us = UIParent:GetEffectiveScale() or 1
		local fs = cf:GetEffectiveScale() or 1
		if us <= 0 or fs <= 0 then return end

		local mx, my = GetCursorPosition()
		mx, my = mx / fs, my / fs

		-- The corner is dragged; the TOPLEFT stays where the dock put it.
		local w = math.max(MIN_W, g._w0 + (mx - g._x0))
		local h = math.max(MIN_H, g._h0 - (my - g._y0))
		pcall(cf.SetSize, cf, w, h)
		Chat:AnchorPanel()
	end

	local function Start()
		local cf = g._frame
		if not cf or InCombatLockdown() then return end
		if cf.SetResizable then pcall(cf.SetResizable, cf, true) end
		local mx, my = GetCursorPosition()
		local fs = cf:GetEffectiveScale() or 1
		if fs <= 0 then return end
		g._x0, g._y0 = mx / fs, my / fs
		g._w0, g._h0 = cf:GetWidth(), cf:GetHeight()
		g._sizing = true
		g:SetScript("OnUpdate", Drag)
	end

	local function Stop()
		if not g._sizing then return end
		g._sizing = nil
		g:SetScript("OnUpdate", nil)
		local cf = g._frame
		if not cf then return end

		-- The dock owns the layout of every window docked into it, so a size we
		-- set behind its back lasts until the next thing that makes it think.
		if _G.FCF_DockUpdate then pcall(_G.FCF_DockUpdate) end

		-- Dimensions, not position: a docked window has no position of its own,
		-- which is the call that was erroring. This one takes the numbers we
		-- already have.
		if _G.SetChatWindowSavedDimensions then
			pcall(_G.SetChatWindowSavedDimensions, cf:GetID(),
				cf:GetWidth(), cf:GetHeight())
		end

		-- ...and OUR own copy, which is the one that survives.
		--
		-- Blizzard's record is written above and does not come back: the dock
		-- owns the layout of every window docked into it, and on login it
		-- re-flows ChatFrame1 to the dock's own idea of the size after the
		-- saved dimensions have been applied. So a window you resized was the
		-- right shape until you reloaded and the wrong shape afterwards, which
		-- is exactly what the position did before it was hooked.
		--
		-- Same answer as the position, then: keep our own number and put it
		-- back after the client has finished restoring.
		Chat:SaveSize(cf)
		Chat:Reskin()
	end

	g:SetScript("OnMouseDown", Start)
	g:SetScript("OnMouseUp", Stop)
	g:SetScript("OnDragStart", Start)
	g:SetScript("OnDragStop", Stop)
	g:SetScript("OnHide", Stop)

	g:HookScript("OnEnter", function(self2)
		local a = Palette.c.accent or Palette.c.text
		self2._dots:SetVertexColor(a[1], a[2], a[3], 1)
	end)
	g:HookScript("OnLeave", function(self2) Chat:GripInk(self2) end)

	self._grip = g
	return g
end

--- ONE grip, ours, on the window our panel is wrapped around.
--
--  Blizzard's resize buttons are left entirely alone now, and the reason is in
--  the error report this came from:
--
--    FloatingChatFrame.lua:1026: attempt to perform arithmetic on a nil value
--    FCF_SavePositionAndDimensions(ChatFrame2)   -- isDocked = 1
--
--  Blizzard hides those buttons on DOCKED windows, because a docked window
--  cannot be resized on its own and its own save path errors if you try. We were
--  showing every chat frame's button and anchoring all of them to the same
--  corner of our panel - so the General tab and the Combat Log tab each had one
--  stacked in the same place, whichever tab was up decided which you saw, and
--  clicking the Combat Log's ran Blizzard's handler on a docked frame and took
--  the chat window with it.
--
--  Our own grip has none of that trouble: it drives StartSizing on ChatFrame1,
--  which is the window the panel is drawn around, and the dock follows it.
function Chat:SkinResize(f)
	local cfg = A.Config:Module("chat")
	-- Every other chat frame is somebody else's business. Blizzard shows or
	-- hides their grips according to whether they are docked, and it is right.
	if f ~= _G.ChatFrame1 then return end

	local grip = self._grip or self:BuildGrip(f)
	if not grip then return end
	grip._frame = f

	if cfg.resizable == false then
		grip:Hide()
		return
	end

	-- SHOW **AND** ALPHA. Kill() in this file is Hide + SetTexture(nil) +
	-- SetAlpha(0), and a grip that comes back Shown and transparent is exactly
	-- as useful as no grip - which is what the first three attempts at this were
	-- looking at without knowing it.
	grip:SetAlpha(1)
	grip:EnableMouse(true)
	grip:SetSize(GRIP, GRIP)

	grip:ClearAllPoints()
	local p = self.panel
	-- The bottom-right of the MESSAGE AREA, not of the panel. The panel's own
	-- corner is level with the composer capsule, which spans the full width
	-- inset by PAD - so a grip there is jammed against the SAY box and taking
	-- clicks that were meant for it.
	grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
	-- ABOVE THE MOVER HANDLE, which is the only other thing on screen when this
	-- is - and which covers the entire chat frame at DIALOG strata, so at MEDIUM
	-- the grip was drawn under it and every click on it went to the handle. That
	-- is "grabbing the grip just drags the window": the grip was never grabbed.
	--
	-- FULLSCREEN_DIALOG rather than TOOLTIP, so a tooltip still draws over it.
	-- Safe to sit this high because it is only on screen while frames are
	-- unlocked, which is a mode, not a state you play in.
	grip:SetFrameStrata("FULLSCREEN_DIALOG")
	self:ShowGrip(A.Movers and A.Movers.unlocked)
end

--- Shown only while frames are unlocked.
--
--  Resizing the chat window is a thing you do while arranging the interface,
--  not while reading it, and a permanent mark in the corner of a reading
--  surface is one more thing on screen for the ninety-nine per cent of the time
--  nobody is dragging it. /aether unlock already means "I am moving things".
--
--  Driven from the mover's `preview` callback, which Movers calls on unlock and
--  on lock for exactly this - a frame that is only on screen when the UI says
--  so. Nothing new had to be invented to hear about it.
function Chat:ShowGrip(show)
	local g = self._grip
	if not g then return end
	local cfg = A.Config:Module("chat")
	g:SetShown(show and cfg.resizable ~= false and true or false)
	self:GripInk(g)
end

--- The grip's resting colour: brighter while frames are unlocked, because that
--  is when somebody is arranging things and looking for exactly this.
function Chat:GripInk(grip)
	if not grip or not grip._dots then return end
	local c = Palette.c
	-- Quiet. It only appears while you are arranging things, so it does not have
	-- to shout to be found - and at 0.9 accent it was the brightest thing on a
	-- reading surface, which is the opposite of what a corner mark is for.
	local col = c.textDim or c.text
	grip._dots:SetVertexColor(col[1], col[2], col[3], 0.5)
end

--- Unlocking is what makes the frame movable *and* resizable, both through
--  Blizzard's own machinery, which is also what saves them. A locked chat frame
--  ignores its own resize grip and its tab drag alike, and locked is the default
--  - which is the whole reason neither worked.
--
--  Drag a tab to move it. The tabs are on screen at all times now, so there is
--  something to grab.
function Chat:SetUnlocked(f)
	local cfg = A.Config:Module("chat")
	if not _G.FCF_SetLocked or not f.GetID then return end
	pcall(_G.FCF_SetLocked, f, cfg.unlocked == false)
	if f.SetResizable then pcall(f.SetResizable, f, cfg.resizable ~= false) end
	if f.SetMovable then pcall(f.SetMovable, f, cfg.unlocked ~= false) end

	-- FCF_SetLocked is what SHOWS Blizzard's resize button, and on a docked
	-- window that button is broken by Blizzard's own code: its OnMouseUp calls
	-- FCF_SavePositionAndDimensions, which does arithmetic on a saved position
	-- a docked frame has not got. FloatingChatFrame.lua:1026, every time.
	--
	-- Leaving them alone was the last attempt and it put a working-looking
	-- control inside the Combat Log that took the chat window down when
	-- clicked. So on a DOCKED frame it is hidden - not because it is Blizzard's
	-- furniture and we are restyling, but because it errors. An undocked window
	-- keeps its own, where it works and where our panel is not drawn anyway.
	local bz = f.ResizeButton or _G[(f:GetName() or "") .. "ResizeButton"]
	if bz and f.isDocked then
		pcall(bz.Hide, bz)
		pcall(bz.EnableMouse, bz, false)
	end
end

-- ---------------------------------------------------------------------------
-- edit box
-- ---------------------------------------------------------------------------

function Chat:SkinEditBox(f)
	local eb = f.editBox or _G[(f:GetName() or "") .. "EditBox"]
	if not eb then return end

	local name = eb:GetName()

	-- Every texture on the box, not a list of the ones we know about. Naming
	-- them got Left/Right/Mid and the focus set and left something else behind -
	-- the same lesson the minimap buttons taught: matching by name can never
	-- cover "whatever this template happens to ship". FontStrings are left alone
	-- here and dealt with below, because one of them is the text you are typing.
	if eb.GetRegions then
		local ok, regions = pcall(function() return { eb:GetRegions() } end)
		if ok then
			for _, r in ipairs(regions) do
				if r and r.GetObjectType and r:GetObjectType() == "Texture" then
					Kill(r)
				end
			end
		end
	end
	for _, suffix in ipairs({ "Left", "Right", "Mid",
		"FocusLeft", "FocusRight", "FocusMid" }) do
		Kill(name and _G[name .. suffix] or nil)
	end
	Kill(eb.focusLeft) Kill(eb.focusRight) Kill(eb.focusMid)

	Chat:StripNative(eb)

	-- The language button - the little 'A' for Common/Orcish. Hiding the button
	-- is enough to take it off screen, but its label is a FontString on the
	-- button rather than on the edit box, so the diagnostic could not tell a
	-- hidden one from a visible one. Blanked as well, so there is nothing left to
	-- wonder about. Nothing in the concept has a language selector, and /say
	-- still speaks whatever your race speaks.
	local lang = eb.language or (name and _G[name .. "Language"])
	if lang then
		Kill(lang)
		if lang.GetRegions then
			local ok, regions = pcall(function() return { lang:GetRegions() } end)
			if ok then
				for _, r in ipairs(regions) do
					if r and r.GetObjectType and r:GetObjectType() == "FontString" then
						pcall(r.SetText, r, "")
						pcall(r.SetAlpha, r, 0)
					end
				end
			end
		end
	end

	-- Hooked on the box itself. Whether the method arrived by mixin copy or from
	-- a metatable, this is the one that runs.
	if not eb._headerHooked and type(eb.UpdateHeader) == "function" then
		eb._headerHooked = true
		pcall(hooksecurefunc, eb, "UpdateHeader", function(self)
			if not Chat.enabled then return end
			Chat:StripNative(self)
			Chat:UpdateEditBox(self)
		end)
	end

	-- Slash commands change this attribute after the edit box's text-change
	-- handler has run. Watching it keeps `/1`, `/p`, and reply shortcuts in sync
	-- instead of leaving the previous channel badge on screen.
	if not eb._chatTypeHooked and eb.SetAttribute and _G.hooksecurefunc then
		eb._chatTypeHooked = true
		pcall(hooksecurefunc, eb, "SetAttribute", function(self, key)
			if Chat.enabled and (key == "chatType" or key == "stickyType") then
				Chat:UpdateEditBox(self)
			end
		end)
	end

	if not eb._aether then
		eb._aether = true

		-- A panel, not a pill, and that is the point. The outer frame and the
		-- divider are both drawn from the panel edge asset; a pill edge is a
		-- different texture with a different feather, so no amount of picking an
		-- alpha was ever going to make the two agree. Same asset and the same
		-- skin tokens means it matches the border round the whole thing because
		-- it *is* that border, not because a number was tuned to look like it.
		local pill = Glass.CreatePanel(UIParent, {
			corner = math.floor(EDIT_H / 2),
			shadow = A.db.profile.glass.shadow,
		})
		pill:SetFrameStrata("BACKGROUND")
		pill:EnableMouse(false)
		eb._pill = pill

		-- Which channel you are typing into. Blizzard's own header said this and
		-- was hidden because our tag was printing on top of it; the answer was
		-- never to lose the information, it was to say it once, in our type.
		--
		-- A capsule with a short code rather than a word: it is read at a
		-- glance, it does not change width every time you switch channel, and it
		-- reads as part of the composer rather than as text you might have typed.
		local tag = Glass.CreatePanel(pill, {
			corner = math.floor(Chat:TagHeight(f) / 2),
			shadow = 0,
		})
		tag:EnableMouse(false)
		eb._tag = tag
		eb._tagText = W.Text(tag, "chatTab", "CENTER")
		eb._tagText:SetAllPoints(tag)

		local send = pill:CreateTexture(nil, "OVERLAY")
		send:SetTexture(Media.texture.send)
		eb._send = send

		eb:HookScript("OnEditFocusGained", function(e) Chat:UpdateEditBox(e) end)
		eb:HookScript("OnEditFocusLost", function(e) Chat:UpdateEditBox(e) end)
		eb:HookScript("OnTextChanged", function(e) Chat:UpdateEditBox(e) end)
		-- Blizzard re-anchors the edit box when it activates, and our points are
		-- only applied at skin time - so between a reskin and the next keypress
		-- the box can walk back to wherever the client wants it while the
		-- capsule stays on the panel. Re-asserted on every show.
		eb:HookScript("OnShow", function(e)
			Chat:AnchorEditBox(e)
			Chat:UpdateComposers()
		end)
		eb:HookScript("OnHide", function() Chat:UpdateComposers() end)
	end

	self:StyleEditBox(eb)
	self:AnchorEditBox(eb)
	self:UpdateEditBox(eb)
end

--- The edit box lives *inside* the panel, inset from its bottom edge, not
--  hanging off underneath it. The panel is already sized to leave room for it -
--  see AnchorPanel, which extends the bottom past the chat frame by exactly this
--  row plus its gaps - so the two cannot drift apart.
--
--  Blizzard's own anchors put it below the chat frame at (-5, -2) / (5, -2), and
--  those are simply replaced: the edit box is not protected, and leaving it
--  where Blizzard put it would have it floating outside the glass.
-- There is no channel tag on the left any more. It duplicated Blizzard's own
-- "Say:" header, which is what printed the two on top of each other, and once
-- the header was gone the tag was saying something the placeholder already says.
-- What is left is the text, starting near the left edge as it should.
local TEXT_X = 14
local SEND_W = 28    -- room for the send glyph on the right

function Chat:AnchorEditBox(eb)
	local p = self.panel
	if not p or not eb then return end

	local pill = eb._pill
	if pill then
		pill:ClearAllPoints()
		pill:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", PAD, PAD)
		pill:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -PAD, PAD)
		pill:SetHeight(EDIT_H)

		eb._send:ClearAllPoints()
		eb._send:SetPoint("RIGHT", pill, "RIGHT", -12, 0)
		eb._send:SetSize(12, 12)
	end

	if pill and eb._tag then
		local th = self:TagHeight(eb.chatFrame or _G.ChatFrame1)
		eb._tag:ClearAllPoints()
		eb._tag:SetPoint("LEFT", pill, "LEFT", TEXT_X - 4, 0)
		eb._tag:SetHeight(th)
		-- The corner has to follow the height or the capsule stops being one. A
		-- panel's corner is set at creation and does not track its frame, so a
		-- chip sized from the font with a radius left at half the *composer's*
		-- height gets a curve wider than it is tall - which is not a smaller
		-- capsule, it is a different shape.
		Glass.SetPanelCorner(eb._tag, math.floor(th / 2))
		-- The width follows the code inside it, which is only known once it has
		-- text - see UpdateEditBox, which is also what moves the text entry out
		-- of its way.
	end

	local anchor = pill or p
	eb:ClearAllPoints()
	eb:SetPoint("RIGHT", anchor, "RIGHT", -SEND_W, 0)
	eb:SetHeight(EDIT_H)
	if eb.SetTextInsets then pcall(eb.SetTextInsets, eb, 0, 0, 0, 0) end
	-- The left edge follows the label, so it moves when the label does. Done in
	-- UpdateEditBox because the label's width is only known once it has text.
	self:UpdateEditBox(eb)
end

--- Blizzard's own header, suffix and prompt, silenced.
--
--  Every FontString on the box rather than a list of three parentKeys. An
--  EditBox draws the text you are typing itself - that is the widget, not a
--  child region - so *every* FontString on it is decoration and can go. Naming
--  `header`, `headerSuffix` and `prompt` left something else behind, which is
--  what the grey "CE_TEXT" was; this is the same inversion the minimap buttons
--  and the edit box's own textures already needed.
--
--  Our label lives on the capsule, not on the box, so it is not in this sweep.
--
--  Text insets go back to zero at the same time. Blizzard sets a left inset the
--  width of its header so the typed text clears it - with the header gone that
--  inset is a gap in front of what you type for no reason.
--- Text that is obviously the *name* of a missing localised global rather than
--  anything anybody meant to read: all caps, underscores, no spaces. "VOICE_TEXT"
--  is one - a Classic Era client that has no such string, so whatever set it got
--  the key back instead of a value.
--
--  Matched by shape rather than by a list, because the point is that we do not
--  know which one it will be. Real chat furniture never looks like this.
local function LooksLikeAMissingGlobal(text)
	if not text or text == "" then return false end
	return text:find("_") ~= nil and text:upper() == text and text:find("%s") == nil
end

--- Walk children looking for that, and only that.
--
--  Deliberately narrow. Blanking every FontString under the edit box would take
--  the autocomplete list's entries with it, and those are text somebody is
--  supposed to read.
local function SweepMissingGlobals(frame, depth)
	if not frame or (depth or 0) > 2 then return end

	if frame.GetRegions then
		local ok, regions = pcall(function() return { frame:GetRegions() } end)
		if ok then
			for _, r in ipairs(regions) do
				-- Named only. `ChatFrameEditBox.xml:99` is a bare
				-- `<FontString inherits="ChatFontNormal"/>` sitting directly in
				-- the EditBox element, and that anonymous one is not decoration -
				-- it is the widget that draws the text you are typing. Blanking
				-- every FontString on the box made typing invisible, which is a
				-- far worse bug than the one it was chasing. Everything we
				-- actually want gone is named.
				if r and r.GetObjectType and r:GetObjectType() == "FontString"
					and r.GetName and r:GetName()
					and LooksLikeAMissingGlobal(r.GetText and r:GetText()) then
					pcall(r.SetText, r, "")
					pcall(r.SetAlpha, r, 0)
				end
			end
		end
	end

	if frame.GetChildren then
		local ok, kids = pcall(function() return { frame:GetChildren() } end)
		if ok then
			for _, kid in ipairs(kids) do
				SweepMissingGlobals(kid, (depth or 0) + 1)
			end
		end
	end
end

--- Get the edit box out of VOICE_TEXT, which it cannot get itself out of.
--
--  `ChatFrameEditBoxMixin:OnEnterPressed` sets both the chat type and the
--  *sticky* type to "VOICE_TEXT" whenever `IsVoiceTranscription` is true for the
--  selected frame, so the box returns to voice after each message. That is fine
--  in a voice tab and stranded anywhere else, because `ResetChatType` - the
--  function whose whole job is putting an impossible chat type back to SAY -
--  has cases for PARTY, RAID, GUILD, OFFICER and INSTANCE_CHAT and **no case for
--  VOICE_TEXT**. Once the sticky type lands there nothing in the client takes it
--  back, and every UpdateHeader after that asks for `CHAT_VOICE_TEXT_SEND`,
--  which this client does not have.
--
--  So: if the type is VOICE_TEXT and the transcription frame is not even loaded,
--  it is not a state anybody chose. Put it back to SAY.
local function UnstickVoiceText(eb)
	if eb._unsticking then return end

	local kind = (eb.GetChatType and select(2, pcall(eb.GetChatType, eb)))
		or (eb.GetAttribute and eb:GetAttribute("chatType"))
	if kind ~= "VOICE_TEXT" then return end

	-- If voice transcription really is present, leave it alone - somebody may
	-- genuinely be typing into a voice tab.
	if _G.VoiceTranscription_GetChatTypeAndInfo then return end

	eb._unsticking = true
	if eb.SetChatType then pcall(eb.SetChatType, eb, "SAY") end
	if eb.SetStickyType then pcall(eb.SetStickyType, eb, "SAY") end
	if eb.SetAttribute then
		pcall(eb.SetAttribute, eb, "chatType", "SAY")
		pcall(eb.SetAttribute, eb, "stickyType", "SAY")
	end
	eb._unsticking = false
end

Chat.UnstickVoiceText = UnstickVoiceText

--- UpdateHeader is not the only path that writes Blizzard's transient labels.
--  Neutralising the FontString itself closes the remaining race with the native
--  `SAY` header without hiding the edit box's actual typed text renderer.
local function SilenceNativeText(fs)
	if not fs or fs._aetherSilencing then return end
	fs._aetherSilencing = true
	pcall(fs.SetText, fs, "")
	pcall(fs.SetAlpha, fs, 0)
	if fs.SetWidth then pcall(fs.SetWidth, fs, 0.001) end
	fs._aetherSilencing = false
end

function Chat:StripNative(eb)
	if not eb then return end

	UnstickVoiceText(eb)

	SweepMissingGlobals(eb, 0)

	-- By parentKey and by global name: UpdateHeader resolves these by *global*
	-- name (`_G[self:GetName().."Header"]`) and bails if one is missing, so both
	-- spellings have to be reached.
	--
	-- Blanked and made transparent, never hidden. Classic's own override runs
	-- `self.prompt:SetShown(not self.header:IsShown())` - hiding the header is
	-- what makes the prompt appear in its place.
	local ebName = eb.GetName and eb:GetName()
	for _, key in ipairs({ "header", "headerSuffix", "prompt" }) do
		local fs = eb[key]
			or (ebName and _G[ebName .. key:gsub("^%l", string.upper)])
		if fs then
			-- Hooked once per FontString, so whatever route Blizzard writes to
			-- it by - and there is more than one - the write is undone on the
			-- spot rather than waited for. This is what the watchdog was
			-- covering for and could only catch three times a second.
			if not fs._aetherSilenceHooked and fs.SetText and _G.hooksecurefunc then
				fs._aetherSilenceHooked = true
				pcall(hooksecurefunc, fs, "SetText", function(fontString)
					if not Chat.enabled then return end
					SilenceNativeText(fontString)
					Chat:UpdateEditBox(eb)
				end)
			end
			SilenceNativeText(fs)
		end
	end
	if eb.SetTextInsets then pcall(eb.SetTextInsets, eb, 0, 0, 0, 0) end
end

--- Colours for the edit box capsule.
--
--  Its own pass rather than Glass's defaults, for two reasons. The rim at the
--  usual 0.32 was a hard bright outline round a 26px capsule - most of what you
--  could see of it was rim, which is not what the concept draws. And it was
--  never being re-coloured on a skin change at all, so switching to daylight
--  left midnight's violet sitting on a pale panel.
function Chat:StyleEditBox(eb)
	if not eb or not eb._pill then return end
	local c = Palette.c

	-- The composer uses the same muted rim as the chat panel, rather than a
	-- separate bright-purple accent.
	eb._pill:ApplySkin()
	eb._pill:SetEdgeColor(c.glassEdge)
	eb._pill:SetEdgeShown(true)
	eb._pill:SetFillColor({ c.text[1], c.text[2], c.text[3], 0.07 })

	if eb._tag then
		-- A smaller version of the composer: the channel is conveyed by crisp
		-- white type, not a competing coloured fill.
		eb._tag:SetFillColor({ c.text[1], c.text[2], c.text[3], 0.06 })
		eb._tag:SetEdgeColor(c.glassEdge)
		eb._tag:SetEdgeShown(true)
	end

	-- The code reads at the size you type at. The `chatTab` role is 10 and the
	-- typing size here is 9, so taking the role's own number put a label next to
	-- the text that was visibly bigger than the text - which is the one thing a
	-- label should never be.
	local f = eb.chatFrame or _G.ChatFrame1
	if eb._tagText then
		Media:SetFont(eb._tagText, "chatTab", Chat:FontSize(f))
	end

	-- The same face and the same size as the messages above it. Media:SetFont
	-- would have used the role's own 12 and left you typing at one size and
	-- reading it back at another.
	if eb.SetFont then pcall(eb.SetFont, eb, Chat:ChatFontPath(), Chat:FontSize(f), "") end
	if eb.SetTextColor then pcall(eb.SetTextColor, eb, c.text[1], c.text[2], c.text[3], 1) end
end

--- The channel you are typing into, as a word.
--
--  Blizzard's own localised globals where they exist, because "Party" is not
--  "Party" everywhere and a hard-coded English list would be wrong for most of
--  the people who could ever read it.
local function ChannelLabel(eb)
	local kind = eb.GetAttribute and eb:GetAttribute("chatType") or "SAY"

	if kind == "CHANNEL" and _G.GetChannelName then
		local target = eb:GetAttribute("channelTarget")
		local ok, _, name = pcall(_G.GetChannelName, target or 0)
		if ok and name and name ~= "" then return name end
	end
	if kind == "WHISPER" then
		local target = eb:GetAttribute("tellTarget")
		if target and target ~= "" then return target end
	end

	local fallback = {
		SAY = "Say", YELL = "Yell", PARTY = "Party", RAID = "Raid",
		RAID_WARNING = "Warning", GUILD = "Guild", OFFICER = "Officer",
		WHISPER = "Whisper", EMOTE = "Emote", CHANNEL = "Channel",
	}
	local g = _G[kind]
	if type(g) == "string" and g ~= "" and not LooksLikeAMissingGlobal(g) then
		return g
	end
	if fallback[kind] then return fallback[kind] end

	-- Never the attribute itself. `kind` is a key, not a label, and returning it
	-- is what printed VOICE_TEXT into the composer - our own FontString, drawn
	-- from our own code, which is why every sweep for a stray Blizzard string
	-- came back clean and the text stayed on screen anyway. A chat type nobody
	-- anticipated says "Say", which is where an unrecognised type sends a
	-- message anyway.
	return _G.SAY or "Say"
end

--- The channel as a short code: `SAY`, `GEN`, `PAR`, or the first characters of
--  a whisper target.
--
--  Three *characters*, not three bytes. `sub(1, 3)` on a localised label cuts a
--  multi-byte character in half and the client draws the remains as a question
--  mark, which is the sort of thing that only ever shows up on somebody else's
--  machine.
local function ShortCode(label)
	if type(label) ~= "string" or label == "" then return "" end
	local out, count = "", 0
	for char in label:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		out = out .. char
		count = count + 1
		if count == 3 then break end
	end
	return out:upper()
end

--- Exactly one composer, whatever the number of chat windows.
--
--  The capsule is a frame of ours parented to UIParent, not to the edit box, so
--  it does not inherit Blizzard's "only the active box is shown" behaviour: it
--  is simply always visible. With one chat window that is invisible; this
--  client has ten, and ten capsules and ten channel labels were being drawn on
--  top of each other in the same place, which is what put two labels side by
--  side at the bottom of the panel.
--
--  The winner is the box that is actually open if there is one, and ChatFrame1's
--  otherwise - so the composer is on screen at all times the way the concept
--  draws it, rather than appearing only while typing.
function Chat:UpdateComposers()
	local active

	local function boxOf(f)
		return f.editBox or _G[(f:GetName() or "") .. "EditBox"]
	end

	EachFrame(function(f)
		if active then return end
		local eb = boxOf(f)
		if eb and eb._pill and eb.IsShown and eb:IsShown() then active = eb end
	end)

	-- Nothing is focused, so preview the box pressing Enter would actually open,
	-- and that is ChatFrame1's - NOT the dock's selected window.
	--
	-- This used to consult the selection first, written as
	-- `selected == id or f == ChatFrame1` inside a loop over CHAT_FRAMES; since
	-- ChatFrame1 is first in that list the fallback always won on iteration one
	-- and the selection test decided nothing, ever. Promoting the selection to
	-- its own pass ahead of the fallback made it decide - and made it wrong,
	-- which is worse than dead.
	--
	-- Era's OPENCHAT binding is `ChatFrameUtil.OpenChat("")` with no frame, and
	-- ChooseBoxForSend's FIRST branch is
	-- `if GetCVar("chatStyle") == "classic" then return DEFAULT_CHAT_FRAME.editBox`,
	-- which ignores the dock entirely. Selecting the guild tab changes which
	-- window you READ, not where your typing goes, so a capsule that followed
	-- the selection would advertise a channel you are not about to type in.
	--
	-- Under `chatStyle = "im"` the answer does move - but there the previous box
	-- is hidden and the new one shown, so the loop above already has it.
	if not active then
		local eb = boxOf(_G.ChatFrame1)
		if eb and eb._pill then active = eb end
	end

	EachFrame(function(f)
		local eb = boxOf(f)
		if eb and eb._pill then
			if eb == active then eb._pill:Show() else eb._pill:Hide() end
		end
	end)

	if active then self:UpdateEditBox(active) end
end

function Chat:UpdateEditBox(eb)
	if not eb or not eb._aether then return end
	local c = Palette.c

	local tagW = 0
	if eb._tag and eb._tagText then
		eb._tagText:SetText(ShortCode(ChannelLabel(eb)))
		W.Color(eb._tagText, c.text)
		-- A floor as well as a fit: a two-character code should not give a
		-- visibly narrower capsule than a three-character one.
		tagW = math.max(30, (eb._tagText:GetStringWidth() or 0) + 14)
		eb._tag:SetWidth(tagW)
	end

	eb:SetPoint("LEFT", eb._pill or self.panel, "LEFT", TEXT_X + tagW + 10, 0)

	local typing = (eb:GetText() or "") ~= ""
	local sendAlpha = (c.glassEdge[4] or 1) * (typing and 1 or 0.55)
	eb._send:SetVertexColor(c.glassEdge[1], c.glassEdge[2], c.glassEdge[3], sendAlpha)
end

-- ---------------------------------------------------------------------------
-- the message lines
--
-- Four things happen to a line: the sender's name is class-coloured and its
-- realm dimmed, the furniture between the name and the message becomes an em
-- dash, a channel badge is prepended, and system lines are dimmed.
--
-- Where each one has to be done is not a style choice, it is dictated by where
-- Blizzard assembles that part of the line. From
-- Blizzard_ChatFrameBase/Classic/ChatFrameOverrides.lua:
--
--     local coloredName = ChatFrameUtil.GetDecoratedSenderName(event, arg1, ...)
--     local playerLink  = GetPlayerLink(arg2, playerLinkDisplayText, arg11)
--     outMsg = format(ChatFrameUtil.GetOutMessageFormatKey(type)..message,
--                     pflag..playerLink)
--     if (channelLength > 0) then
--         outMsg = "|Hchannel:channel:"..arg8.."|h["
--                  ..ChatFrameUtil.ResolvePrefixedChannelName(arg4).."]|h "..outMsg
--     end
--
-- Read that top to bottom and the three levers fall out of it:
--
-- 1. **The name** is `GetDecoratedSenderName`'s return, and that runs the
--    sender-name filters last thing before returning. So a filter's output
--    becomes the *display text* of `GetPlayerLink` - the link is built around
--    what we return, from `arg2`, which we never touch. Whispers, ignore and
--    the right-click menu all hang off `arg2` and cannot be harmed from here.
--    The one rule is that we must never emit a `|H` ourselves: a hyperlink
--    nested inside a hyperlink is the thing that would break them.
--
-- 2. **The furniture** is `CHAT_<type>_GET`, fetched through
--    `GetOutMessageFormatKey`, which `assertsafe`s that the key exists - so
--    these are reshaped, never cleared.
--
-- 3. **The channel bracket is not in the format string.** It is concatenated on
--    afterwards, outside `format`, from `arg4` and `arg8`. No amount of
--    rewriting `CHAT_CHANNEL_GET` can remove it, which is what an earlier plan
--    for this assumed. It comes off in a wrapper around the frame's own
--    `AddMessage` instead: one anchored gsub on a hyperlink we are deliberately
--    dropping, applied to the finished string, touching neither the routing
--    arguments nor the player link.
--
-- One thing from the concept is not implementable and is not attempted:
-- **system lines cannot be italic.** There is no italic escape sequence - the
-- markup language has `|c`, `|T`, `|H` and `|A` and nothing for slant - and a
-- ScrollingMessageFrame draws every line in one font, so a second face is no
-- answer either. They are dimmed instead, which was the intent behind the
-- italics: to say "this is not somebody talking".
-- ---------------------------------------------------------------------------

-- U+2014, written as bytes so that no editor, transfer or diff between here and
-- the game folder can quietly turn it into something else.
local EM_DASH = "\226\128\148"

--- Chat types that get a badge, mapped to the word baked into the atlas.
--  Leader variants share their group's pill: the distinction is already carried
--  by Blizzard's own colour for the type.
local TYPE_BADGE = {
	SAY = "SAY", YELL = "YELL",
	PARTY = "PARTY", PARTY_LEADER = "PARTY",
	RAID = "RAID", RAID_LEADER = "RAID", RAID_WARNING = "RAID",
	GUILD = "GUILD", OFFICER = "OFFICER",
	WHISPER = "WHISPER", BN_WHISPER = "WHISPER",
	WHISPER_INFORM = "TO", BN_WHISPER_INFORM = "TO",
	EMOTE = "EMOTE",
}

--- Types whose `CHAT_<type>_GET` is reshaped to an em dash.
local FORMAT_TYPES = {
	"SAY", "YELL", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
	"RAID_WARNING", "GUILD", "OFFICER", "WHISPER", "WHISPER_INFORM",
	"BN_WHISPER", "BN_WHISPER_INFORM", "CHANNEL",
}

--- The line types that get dimmed: nobody is talking in any of them.
--
--  **SYSTEM only, and that is not laziness.** Channel notices - joined, left,
--  owner changed - look like they belong here and cannot be reached. The
--  handler's channel branch tests `strsub(type, 1, 7) == "CHANNEL"`, which
--  matches `CHANNEL_NOTICE` and `CHANNEL_NOTICE_USER` as well as chat, and
--  reassigns `info = ChatTypeInfo["CHANNEL"..arg8]` - so by the time AddMessage
--  is called a notice carries the *channel's* id, not the notice type's.
--  Listing the notice types here would look right, report "3 of 3" in the
--  diagnostic and dim nothing; adding the channel ids instead would grey out
--  every word anyone says in General.
--
--  Identified by chat *type id* rather than by event, because that is what
--  `AddMessage` is handed - the handler calls
--  `self:AddMessage(outMsg, info.r, info.g, info.b, info.id, ...)` - and it is
--  the only way to know what a finished line is without a filter.
--
--  The alternative, and the first version of this, was a message-event filter
--  that wrapped `arg1` in a colour code. It was wrong twice over. On
--  `CHAT_MSG_CHANNEL_NOTICE` and `CHAT_MSG_CHANNEL_NOTICE_USER` `arg1` is not a
--  message at all - it is a token like `YOU_CHANGED` that the handler turns
--  into a global-string key, so colouring it produced
--  `_G["CHAT_|cffdcd2ffYOU_CHANGED|r_NOTICE"]`, which is nil, which is a Lua
--  error on every login and a channel notice that never prints. And even on
--  `CHAT_MSG_SYSTEM`, where it worked, it handed every filter downstream of
--  ours a string that no longer matched their patterns.
--
--  So: **no filter in this module ever changes an event argument.** The one
--  that exists returns a name, which is its contract. Everything else reads a
--  finished line.
local DIM_TYPES = { "SYSTEM" }

--- Anchored, and it matches exactly the hyperlink Blizzard prepends above.
local CHANNEL_PREFIX = "^|Hchannel:channel:%d+|h%[.-%]|h "

--- The square brackets Blizzard puts round a player link's *display text*.
--
--      playerLinkDisplayText = coloredName
--      if ( usingDifferentLanguage or not usingEmote ) then
--          playerLinkDisplayText = ("[%s]"):format(coloredName)
--      end
--
--  which is every line except an emote. They are added after the sender-name
--  filter has run, so no filter can prevent them, and the badge we prepend to
--  the name lands *inside* them - `[BADGE Turdinand]`, with the opening bracket
--  hard against the pill. Anchored to the link so nothing else in the line can
--  match: a name cannot contain `]` and neither can our markup.
local LINK_BRACKETS = {
	"(|Hplayer:[^|]*|h)%[(.-)%](|h)",
	"(|HBNplayer:[^|]*|h)%[(.-)%](|h)",
}

-- ---------------------------------------------------------------------------

--- Six hex digits for a player's class, or nil.
--
--  `GetPlayerInfoByGUID` rather than the name, because a name is ambiguous
--  across realms and the GUID is what Blizzard's own class colouring uses two
--  lines above where we are called. CUSTOM_CLASS_COLORS first so that anyone
--  running a colour-blind or ClassColors addon gets their own answer here too.
local function ClassHex(guid)
	if not guid or guid == "" or type(_G.GetPlayerInfoByGUID) ~= "function" then
		return nil
	end
	local ok, _, class = pcall(_G.GetPlayerInfoByGUID, guid)
	if not ok or type(class) ~= "string" then return nil end
	local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
	local c = colors and colors[class]
	if not c or not c.r then return nil end
	return Palette:Hex({ c.r, c.g, c.b })
end

--- The colour Blizzard's own chat settings give this type, so the badge agrees
--  with whatever the player has chosen in the chat colour picker rather than
--  inventing a second scheme next to it.
local function TypeHex(infoType)
	local info = _G.ChatTypeInfo and _G.ChatTypeInfo[infoType]
	if info and type(info.r) == "number" then
		return Palette:Hex({ info.r, info.g, info.b })
	end
	return Palette:Hex(Palette.c.accent)
end

--- What each baked channel pill answers to, lowercased, nils dropped, built
--  once on first use.
--
--  Built rather than written as a literal, and that is the whole point. The
--  English strings are the safety net for a client whose localised global is
--  missing, and `{ _G.GENERAL, "General" }` with no `_G.GENERAL` is a table
--  with a hole at index 1 - which `ipairs` stops at, making the fallback
--  unreachable in exactly the case it exists for. Filtering as they go in means
--  the list is dense however many of them turned out to be nil, and there is no
--  hard-coded upper bound for the next person to trip over when they add a
--  fifth name to a row.
--
--  On first use rather than at load, because a global string is not guaranteed
--  to exist when this file is parsed.
local CHANNEL_SETS
local function ChannelSets()
	if CHANNEL_SETS then return CHANNEL_SETS end
	local raw = {
		{ key = "GENERAL", _G.GENERAL, "General" },
		{ key = "TRADE",   _G.TRADE, "Trade" },
		{ key = "LFG",     _G.LOOKING_FOR_GROUP, "LookingForGroup", "Looking For Group" },
		{ key = "DEFENSE", _G.LOCAL_DEFENSE, _G.WORLD_DEFENSE,
			"LocalDefense", "WorldDefense" },
	}
	CHANNEL_SETS = {}
	for _, entry in ipairs(raw) do
		local names = {}
		-- `next`, not `ipairs`: the holes are the reason this function exists.
		for i = 1, 8 do
			local candidate = entry[i]
			if type(candidate) == "string" and candidate ~= "" then
				names[#names + 1] = candidate:lower()
			end
		end
		if #names > 0 then
			CHANNEL_SETS[#CHANNEL_SETS + 1] = { key = entry.key, names = names }
		end
	end
	return CHANNEL_SETS
end

--- Which baked pill, if any, a channel gets.
--
--  Matched against Blizzard's own localised globals rather than an English
--  list, and it fails to nil rather than guessing - a word baked into a texture
--  cannot be localised or invented at runtime, so a channel nobody anticipated
--  gets its name as text instead of the wrong pill.
local function ChannelBadgeKey(baseName)
	if type(baseName) ~= "string" or baseName == "" then return nil end
	local sets = ChannelSets()
	local name = baseName:lower()
	for _, entry in ipairs(sets) do
		for _, candidate in ipairs(entry.names) do
			if name:find(candidate, 1, true) then return entry.key end
		end
	end
	return nil
end

--- Does this client's `|T` escape take the three vertex-colour arguments?
--
--  It is documented and it has worked for a long time, but "documented" is what
--  `ChatEdit_UpdateHeader` was as well, and the failure mode here is worse than
--  a wrong colour: a markup string the parser does not understand is drawn as
--  *literal text*, so every chat line would carry forty characters of path.
--
--  So it is asked rather than assumed, and asked in the only way a string
--  markup can be: render the same badge twice, once with the colour arguments
--  and once without, and measure. If the long form parsed, both are one texture
--  of the same width. If it did not, the long form is a sentence.
function Chat:MarkupSupport()
	if self._markup ~= nil then return self._markup end
	local b = Media.badges

	local plain = string.format("|T%s:12:55:0:0:%d:%d:0:%d:0:%d|t",
		b.file, b.width, b.height, b.width, b.row)
	local colored = plain:sub(1, -3) .. ":255:255:255|t"

	local fs = self._probe
	if not fs then
		fs = UIParent:CreateFontString(nil, "BACKGROUND")
		if not fs then self._markup = false return false end
		pcall(fs.SetFont, fs, Media.font.regular, 12, "")
		fs:Hide()
		self._probe = fs
	end

	local function widthOf(s)
		fs:SetText(s)
		return tonumber(fs:GetStringWidth()) or 0
	end

	local a, c = widthOf(plain), widthOf(colored)
	fs:SetText("")

	-- A zero width means the question cannot be answered yet - the font may not
	-- have loaded - so say no and leave the cache unset to ask again. Bounded,
	-- because "ask again" on a client that always answers zero would mean two
	-- string measurements per chat line for the rest of the session.
	if a <= 0 then
		self._probes = (self._probes or 0) + 1
		if self._probes < 20 then return false end
		self._markup = false
		return false
	end

	self._markup = math.abs(c - a) <= 2
	return self._markup
end

--- One badge as inline markup, trailing space included.
function Chat:Badge(key, hex)
	local b = Media.badges
	local row = b.index[key]
	if row == nil then return nil end

	local cfg = A.Config:Module("chat")
	local h = cfg.badgeSize or 16
	-- Every pill is the same width, so the aspect is fixed and the badges all
	-- render at one size whatever the code inside them - which is what keeps the
	-- names after them lined up down the left of the log.
	local w = math.floor(h * b.pill / b.row + 0.5)
	local top = row * b.row

	local markup = string.format("|T%s:%d:%d:0:%d:%d:%d:0:%d:%d:%d",
		b.file, h, w, cfg.badgeOffset or 0,
		b.width, b.height, b.pill, top, top + b.row)

	if hex and self:MarkupSupport() then
		markup = markup .. string.format(":%d:%d:%d",
			tonumber(hex:sub(1, 2), 16) or 255,
			tonumber(hex:sub(3, 4), 16) or 255,
			tonumber(hex:sub(5, 6), 16) or 255)
	end
	return markup .. "|t "
end

--- The badge, or the channel's own name as text when there is no pill for it.
function Chat:LineTag(event, channelName, channelBaseName, channelIndex)
	local cfg = A.Config:Module("chat")
	if cfg.badges == false then return nil end

	local kind = type(event) == "string" and event:sub(10) or ""

	if kind == "CHANNEL" then
		local hex = TypeHex(channelIndex and ("CHANNEL" .. channelIndex) or "CHANNEL")
		local key = ChannelBadgeKey(channelBaseName or channelName)
		if key then return self:Badge(key, hex) end
		local label = (channelBaseName or channelName or ""):gsub("%s+", " ")
		if label == "" then return nil end
		return Palette:InkHex(hex, label:upper()) .. " "
	end

	local key = TYPE_BADGE[kind]
	if not key then return nil end
	return self:Badge(key, TypeHex(kind))
end

--- The sender-name filter itself.
--
--  Registered with ChatFrameUtil.AddSenderNameFilter. Returning nil means "no
--  opinion" and leaves the name exactly as Blizzard decorated it, which is what
--  every early exit here does - so the worst case of anything below going wrong
--  is Blizzard's own line, not a broken one.
local function SenderNameFilter(event, name, ...)
	-- First statement, before any way out. `RewriteLine` reads this to decide
	-- whether Blizzard's channel bracket has a replacement to make way for, and
	-- a stale answer is a channel line with nothing identifying it at all. The
	-- two run microseconds apart in one call stack - this is the last thing
	-- `GetDecoratedSenderName` does and `AddMessage` is the last thing the
	-- handler does - so it is a handshake between two points in one function,
	-- not state that has to survive anything.
	Chat._tag = nil

	if not Chat.enabled then return nil end
	if type(name) ~= "string" or name == "" then return nil end

	local cfg = A.Config:Module("chat")
	if cfg.styleLines == false then return nil end

	-- The one hard rule. This becomes the display text of a player link, and a
	-- hyperlink inside a hyperlink is what would break whispers and the
	-- right-click menu - so if something upstream has already put one here, it
	-- is left alone rather than reasoned about.
	if name:find("|H", 1, true) then return nil end

	local _, _, _, channelName, _, _, _, channelIndex, channelBaseName,
		_, _, senderGUID = ...

	-- Blizzard may have class-coloured it already. Unwrap so the realm split
	-- below sees the name rather than the escape, and keep the colour to put
	-- back if we have no better one of our own.
	local prefix = name:match("^(|c%x%x%x%x%x%x%x%x)")
	local inner = name:match("^|c%x%x%x%x%x%x%x%x(.-)|r$")
	-- Both halves or neither. An opening escape with no closing one is not a
	-- wrapped name, and treating it as one put the escape back in front of a
	-- string that still had it.
	if not inner or inner == "" then prefix, inner = nil, name end

	-- A character name cannot contain a hyphen and a realm can, so the split is
	-- on the first one, not the last.
	local base, realm = inner:match("^([^%-]+)%-(.+)$")
	base = base or inner

	local hex = (cfg.classColorNames ~= false) and ClassHex(senderGUID) or nil
	local out
	if hex then
		out = Palette:InkHex(hex, base)
	elseif prefix then
		out = prefix .. base .. "|r"
	else
		out = base
	end

	if realm and realm ~= "" and cfg.hideRealm ~= true then
		out = out .. Palette:Ink("textFaint", "-" .. realm)
	end

	-- The badge goes on the *name*, which puts it inside the player link and
	-- makes it part of what you click. That is deliberate and it has a
	-- precedent: Blizzard's own `TimerunningUtil.AddSmallIcon` prepends an
	-- inline texture to the decorated name in exactly this position, four lines
	-- above where we are called. The alternative - baking the markup into
	-- `CHAT_<type>_GET`, which sits outside the link - works for the nine fixed
	-- types and cannot work for channels, where the badge depends on which
	-- channel it is. One path that handles every line beats two that disagree
	-- about where a badge lives.
	local tag = Chat:LineTag(event, channelName, channelBaseName, channelIndex)
	if tag then
		out = tag .. out
		Chat._tag = tag
	end

	return out
end

Chat.SenderNameFilter = SenderNameFilter

--- The chat type ids that get dimmed, resolved once per session.
--
--  `ChatTypeInfo` is keyed by name and every entry carries the numeric id the
--  handler passes to AddMessage. If a client turns out not to have the ids, the
--  set comes back empty and the dimming quietly does nothing rather than
--  guessing - which `/aether chat` reports rather than leaving to be noticed.
function Chat:DimIDs()
	if self._dimIDs then return self._dimIDs end
	local ids = {}
	for _, kind in ipairs(DIM_TYPES) do
		local info = _G.ChatTypeInfo and _G.ChatTypeInfo[kind]
		-- Greater than zero, not merely a number. `GetChatTypeIndex` answers 0
		-- for anything that is not a real chat type, and the UI-only
		-- pseudo-types - REPLY, CHANNEL1..CHANNEL10 - are exactly the ones every
		-- channel line is tagged with. Zero is truthy in Lua, so one entry
		-- resolving to it would quietly grey out the whole of General.
		if info and type(info.id) == "number" and info.id > 0 then
			ids[info.id] = true
		end
	end
	self._dimIDs = ids
	return ids
end

-- ---------------------------------------------------------------------------

local function Reshapable(fmt)
	if type(fmt) ~= "string" or fmt == "" then return false end
	-- Positional arguments (`%1$s`) in some locales, and the two-argument
	-- notice formats, are left exactly as Blizzard wrote them.
	if fmt:find("$", 1, true) then return false end
	if select(2, fmt:gsub("%%[%-%d%.]*s", "")) ~= 1 then return false end
	if select(2, fmt:gsub("%%[%-%d%.]*[dfiquxX]", "")) ~= 0 then return false end
	return true
end

--- "%s says: " -> "%s (em dash) ", and "To %s: " -> "%s (em dash) " when the
--  TO badge is already saying "To".
--
--  The two halves are independent, because the settings behind them are. With
--  the em dash off and badges on, only the lead-in goes: keeping the separator
--  and dropping "To" is right, and reshaping nothing would print "To" twice -
--  once as a word and once as a pill.
local function Reshape(fmt, dropLeadIn, emDash)
	local lead, spec, tail = fmt:match("^(.-)(%%[%-%d%.]*s)(.*)$")
	if not spec then return nil end
	if dropLeadIn then lead = "" end
	if emDash then tail = " " .. EM_DASH .. " " end
	return lead .. spec .. tail
end

--- Reshape or restore every `CHAT_<type>_GET` this module owns.
--
--  The originals are captured the first time and never re-captured, so turning
--  the setting off and on again cannot end up reshaping a reshaped string. A
--  type this client does not have is stored as `false` and skipped, which is
--  also what keeps `GetOutMessageFormatKey`'s assertsafe quiet: a key that was
--  nil stays nil rather than becoming ours.
function Chat:ApplyFormats()
	local cfg = A.Config:Module("chat")
	local emDash = cfg.emDash ~= false
	local badges = cfg.badges ~= false
	-- Either setting on is a reason to reshape. Only both off means these go
	-- back to being Blizzard's.
	local on = self.enabled and cfg.styleLines ~= false and (emDash or badges)

	self._formats = self._formats or {}
	for _, kind in ipairs(FORMAT_TYPES) do
		local key = "CHAT_" .. kind .. "_GET"
		if self._formats[key] == nil then self._formats[key] = _G[key] or false end

		local orig = self._formats[key]
		if orig then
			if on and Reshapable(orig) then
				local dropLeadIn = badges and kind:find("INFORM$") ~= nil
				_G[key] = Reshape(orig, dropLeadIn, emDash) or orig
			else
				_G[key] = orig
			end
		end
	end
end

function Chat:RestoreFormats()
	for key, orig in pairs(self._formats or {}) do
		if orig then _G[key] = orig end
	end
end

-- ---------------------------------------------------------------------------

--- Everything that can only be done to a line once it is finished.
--
--  Two things end up here for the same reason: neither is reachable from a
--  filter. The channel bracket is concatenated on *after* `format`, and a
--  line's type is not knowable from its text - it arrives as the `id` argument
--  alongside it.
--
--  **The bracket only comes off if the badge that replaces it went on.** That
--  is what the tag handshake is for. `Chat._tag` is whatever the sender-name
--  filter emitted for this line, and the strip is conditional on that exact
--  string being present in the finished text. Without it, every path where the
--  filter declines - badges switched off, a channel with no pill and no name to
--  fall back on, another addon's filter having already put a hyperlink in the
--  name, a server-originated message with no author at all - would delete
--  `[1. General]` and put nothing in its place, and every channel would read
--  the same.
function Chat:RewriteLine(text, id)
	local cfg = A.Config:Module("chat")
	if cfg.styleLines == false then return text end

	-- Strip first, dim second, and the order is load-bearing rather than
	-- arbitrary: CHANNEL_PREFIX is anchored at `^`, so wrapping the line in a
	-- colour code first would put two characters in front of the anchor and the
	-- bracket could never be matched again. Today no dimmable line carries a
	-- bracket, but that is a coincidence of which types are in DIM_TYPES, and
	-- the next person to add one should not have to discover this.
	if cfg.channelPrefix == false then
		local tag = self._tag
		if tag and text:find(tag, 1, true) then
			local stripped, n = text:gsub(CHANNEL_PREFIX, "", 1)
			if n > 0 then text = stripped end
		end
	end

	-- The concept has no brackets round a name, the em dash is what separates it
	-- from the message, and with a badge in front the opening one reads as part
	-- of the pill. Done here rather than in the filter because it has to be:
	-- Blizzard adds them afterwards.
	for _, pattern in ipairs(LINK_BRACKETS) do
		text = text:gsub(pattern, "%1%2%3", 1)
	end

	if cfg.dimSystem ~= false and id and self:DimIDs()[id]
		and text:sub(1, 2) ~= "|c" then
		text = Palette:Ink("textDim", text)
	end

	return text
end

function Chat:WrapAddMessage(f)
	if not f or f._aetherAddMessage then return end
	local orig = f.AddMessage
	if type(orig) ~= "function" then return end

	local wrapper
	wrapper = function(frame, text, r, g, b, id, ...)
		if Chat.enabled and type(text) == "string" then
			text = Chat:RewriteLine(text, id)
		end
		return orig(frame, text, r, g, b, id, ...)
	end

	f._aetherAddMessage = orig
	f._aetherWrapper = wrapper
	f.AddMessage = wrapper
end

--- Put the original back, but only if ours is still the one installed.
--
--  Prat, WIM, Chatter and ElvUI's chat all wrap this too, and anything that
--  loaded after us wrapped *our* wrapper. Assigning the original back over the
--  top of theirs would uninstall them silently for the rest of the session,
--  which is a worse thing to do to somebody than leaving one wrapper in place
--  that checks `Chat.enabled` on every call and does nothing.
function Chat:UnwrapAddMessage(f)
	if not f or not f._aetherAddMessage then return end
	if f.AddMessage == f._aetherWrapper then
		f.AddMessage = f._aetherAddMessage
		f._aetherAddMessage, f._aetherWrapper = nil, nil
	end
end

-- ---------------------------------------------------------------------------

function Chat:InstallLineFilters()
	if self._lineFilters then return end
	local U = _G.ChatFrameUtil

	-- ChatFrameUtil, and no fallback to a `ChatFrame_` global. That is not an
	-- oversight: the globals are aliases assigned in Blizzard_DeprecatedChatInfo,
	-- and that whole file returns early unless the `loadDeprecationFallbacks`
	-- cvar is set. There has never been a sender-name filter under an old name
	-- to fall back to anyway - this API is newer than the deprecation layer.
	if U and type(U.AddSenderNameFilter) == "function" then
		if pcall(U.AddSenderNameFilter, SenderNameFilter) then
			self._senderFilter = true
		end
	end

	self._lineFilters = true
end

function Chat:RemoveLineFilters()
	local U = _G.ChatFrameUtil
	if self._senderFilter and U and type(U.RemoveSenderNameFilter) == "function" then
		pcall(U.RemoveSenderNameFilter, SenderNameFilter)
	end
	self._senderFilter, self._lineFilters = nil, nil
end

-- ---------------------------------------------------------------------------
-- the whispers tab
-- ---------------------------------------------------------------------------

local WHISPER_GROUPS = { "WHISPER", "BN_WHISPER" }

--- Add or remove a message group. **The method is the real thing here.**
--
--  `ChatFrame_AddMessageGroup` and friends are aliases onto `ChatFrameMixin`
--  assigned in Blizzard_DeprecatedChatInfo, behind the same cvar as everything
--  else in that file. The frame method exists either way. This is the same
--  shape of trap that `ChatEdit_UpdateHeader` set three times on the edit box,
--  and it is worth stating plainly: reach for the method, keep the global as
--  the fallback, never the reverse.
local function Group(frame, action, group)
	if not frame then return false end
	local method = frame[action]
	if type(method) == "function" and pcall(method, frame, group) then return true end
	local global = _G["ChatFrame_" .. action]
	if type(global) == "function" then return (pcall(global, frame, group)) end
	return false
end

function Chat:WhisperFrame()
	local want = (A.Config:Module("chat").whisperTabName or "Whispers"):lower()
	local found
	EachFrame(function(f)
		if found then return end
		local n = f.name
		if n == nil and _G.FCF_GetChatWindowInfo and f.GetID then
			n = select(1, _G.FCF_GetChatWindowInfo(f:GetID()))
		end
		if type(n) == "string" and n:lower() == want then found = f end
	end)
	return found
end

--- Move the whisper message groups onto a tab of their own, or back again.
--
--  This is the answer to the one line of the concept's annotation that is not
--  buildable as drawn - "LFM lines and whispers stay bright" while the rest
--  dims. A ScrollingMessageFrame has a single alpha for the whole frame and
--  there is no per-message alpha to reach, so the only way to let whispers
--  survive a dim that the rest of chat does not is to put them in a different
--  frame.
--
--  It is off by default and it says what it did, because unlike everything else
--  in this addon it writes into *Blizzard's* saved variables: the window, its
--  name and its message groups persist, and they persist with AetherUI turned
--  off. Something that outlives the addon should be asked for out loud.
function Chat:SetWhisperTab(on)
	local cfg = A.Config:Module("chat")
	local name = cfg.whisperTabName or "Whispers"
	local frame = self:WhisperFrame()

	if on then
		if not frame then
			if type(_G.FCF_OpenNewWindow) ~= "function" then
				A:Print("this client has no " .. A.Val("FCF_OpenNewWindow") .. " - no whispers tab.")
				return false
			end
			-- noDefaultChannels. Without it the new window subscribes to SAY,
			-- YELL, GUILD, PARTY and CHANNEL as well, which is a second general
			-- window rather than a whispers tab.
			local ok, f = pcall(_G.FCF_OpenNewWindow, name, true)
			if not ok or not f then
				A:Print("could not open a new chat window" ..
					(type(f) == "string" and (": " .. f) or "."))
				return false
			end
			frame = f
		end

		local moved = 0
		for _, g in ipairs(WHISPER_GROUPS) do
			if Group(frame, "AddMessageGroup", g) then moved = moved + 1 end
			Group(_G.ChatFrame1, "RemoveMessageGroup", g)
		end
		self:Reskin()

		if moved == 0 then
			A:Print("the whispers tab exists but no message group would move to it.")
			return false
		end
		A:Print("whispers now go to " .. A.Val(name) .. ".")
		return true
	end

	for _, g in ipairs(WHISPER_GROUPS) do
		Group(_G.ChatFrame1, "AddMessageGroup", g)
		if frame then Group(frame, "RemoveMessageGroup", g) end
	end
	-- The window itself is left standing. Closing somebody's chat window because
	-- a setting changed is a bigger thing than the setting, and Blizzard's own
	-- close is on the tab's right-click menu, which is where anyone would look.
	A:Print("whispers are back in the main window."
		.. (frame and " The empty tab is yours to close." or ""))
	return true
end

-- ---------------------------------------------------------------------------
-- keeping it
-- ---------------------------------------------------------------------------

local hooked = false

--- Everything Blizzard calls that puts its own look back. Hooked once, for the
--  life of the session: a hooksecurefunc cannot be undone, so the handlers check
--  whether the module is still enabled rather than trying to unhook.
local function InstallHooks()
	if hooked then return end
	hooked = true

	local function live() return Chat.enabled end

	-- WHENEVER Blizzard restores its own idea of where the chat window goes,
	-- ours goes back on top of it.
	--
	-- Telling the FCF dock where we put the frame was necessary and turned out
	-- not to be sufficient - the window still walked home on a new character.
	-- The reason a fix aimed at one event was never going to hold is that this
	-- is not one event: FCF_RestorePositionAndDimensions is called from the
	-- dock, from UPDATE_FLOATING_CHAT_WINDOWS, from window open and close, and
	-- from Blizzard's own settings panel. Listening for the triggers means
	-- finding all of them and staying found.
	--
	-- So the hook is on the ACT rather than on its causes. hooksecurefunc runs
	-- after the original, so whatever position Blizzard just applied, ours is
	-- the one left on the frame - and there is no trigger to have missed.
	--
	-- Chat:Reskin still restores too. That covers the reskin path, which has
	-- other reasons to run; this covers everything else.
	if _G.FCF_RestorePositionAndDimensions then
		hooksecurefunc("FCF_RestorePositionAndDimensions", function(f)
			if not live() then return end
			if f ~= _G.ChatFrame1 then return end
			-- The SIZE as well as the position, and for the same reason. The
			-- client applies its own saved dimensions in the call we are hooked
			-- to and the dock then re-flows the window to its own idea of them,
			-- so ours has to go back afterwards or a resized window comes home
			-- the shape it started.
			Chat:RestoreSize(f)
			if not (A.Movers and A.Movers.registry.chat) then return end
			A.Movers:Restore("chat")
		end)
	end

	-- ...AND WHATEVER ELSE IT IS, because that has now been four fixes.
	--
	-- Telling the dock, hooking the restore, telling the dock on the restore
	-- path as well as the drag path: each was necessary, none was sufficient,
	-- and the window still walks home on a new character. Every one of those
	-- aimed at a function BY NAME, which only works if you can name them all.
	--
	-- So this asks the frame instead. Every way of moving a frame - the dock,
	-- the panel manager, a reset, an addon, Blizzard's own settings - ends at
	-- the frame's own SetPoint, so that is where the question goes: is the chat
	-- window where we put it, and if not, WHO just moved it. Ours goes back, and
	-- the caller is written down, because the next report should be able to name
	-- the thing rather than describe it. `/aether chat where` reads it out, and
	-- so does `/aether errors diag`.
	--
	-- Off while frames are unlocked: dragging IS a SetPoint every frame, and a
	-- watcher that fights it is a window you cannot move.
	if _G.ChatFrame1 and _G.ChatFrame1.SetPoint then
		hooksecurefunc(_G.ChatFrame1, "SetPoint", function(f)
			if live() then Chat:WatchPosition(f) end
		end)
	end

	if _G.FCFTab_UpdateColors then
		hooksecurefunc("FCFTab_UpdateColors", function(tab, selected)
			if live() then
				-- The second argument is the answer, handed to us for free, and
				-- it is right for undocked windows too. The old hook declared
				-- `function(tab)` and threw it away.
				if tab then tab._aetherSelected = selected and true or false end
				Chat:SkinTab(tab)
			end
		end)
	end
	if _G.FCFDock_SelectWindow then
		hooksecurefunc("FCFDock_SelectWindow", function()
			if live() then
				Chat:SkinAllTabs()
				-- NOT because the composer follows the selection - it does not,
				-- see UpdateComposers. Under `chatStyle = "im"` selecting a tab
				-- hides one edit box and shows another, and this is where we
				-- find out.
				Chat:UpdateComposers()
			end
		end)
	end
	if _G.FCFDock_UpdateTabs then
		hooksecurefunc("FCFDock_UpdateTabs", function()
			if live() then Chat:SkinAllTabs() end
		end)
	end
	if _G.FloatingChatFrame_Update then
		hooksecurefunc("FloatingChatFrame_Update", function()
			if live() then Chat:Reskin() end
		end)
	end
	if _G.FCF_SetChatWindowFontSize then
		hooksecurefunc("FCF_SetChatWindowFontSize", function(_, f)
			if live() then Chat:SetFrameFont(f or _G.ChatFrame1) end
		end)
	end
	if _G.FCF_OpenTemporaryWindow then
		hooksecurefunc("FCF_OpenTemporaryWindow", function()
			if live() then Chat:Reskin() end
		end)
	end
	if _G.FCF_SetButtonSide then
		hooksecurefunc("FCF_SetButtonSide", function(f)
			if live() then Chat:ParkButtons(f or _G.ChatFrame1) end
		end)
	end
	-- The fade loops skip anything that is not shown, so a hidden backdrop stays
	-- out of them - but a *temporary* window is built after we skinned the rest,
	-- and these are where it shows up.
	-- The one that put the header back, and the reason two attempts at this did
	-- nothing at all.
	--
	-- `ChatEdit_UpdateHeader` **exists** on Classic Era, so the hook installed
	-- without complaint - but it is a dead snapshot taken once at load in
	-- Blizzard_DeprecatedChatInfo (`ChatEdit_UpdateHeader = ChatFrameEditBoxMixin.UpdateHeader`).
	-- Nothing ever calls it. The runtime goes through `self:UpdateHeader()` on the
	-- mixin, so hooking the global succeeded, fired never, and reported nothing.
	-- A hook that silently does not run is worse than one that errors.
	--
	-- The mixin is the real thing, and hooking a *table method* hooks it for every
	-- edit box at once.
	-- and not the mixin *table* either. XML `mixin="ChatFrameEditBoxMixin"` copies
	-- the methods onto each frame when it is created, so `eb.UpdateHeader` is a
	-- direct reference to the original function and replacing the table entry
	-- afterwards changes nothing for any box that already exists. The instance is
	-- the only thing that is definitely the one being called - see SkinEditBox,
	-- which hooks each box as it skins it.
	-- ChatFrameUtil.ActivateChat re-Shows the header on every focus gain before
	-- UpdateHeader runs, so this catches the same moment from the other side.
	if _G.ChatFrameUtil and _G.ChatFrameUtil.ActivateChat then
		hooksecurefunc(_G.ChatFrameUtil, "ActivateChat", function(eb)
			if not live() then return end
			Chat:StripNative(eb)
			Chat:UpdateEditBox(eb)
		end)
	end
	if _G.EventRegistry and _G.EventRegistry.RegisterCallback then
		pcall(function()
			_G.EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusGained",
				function(_, eb) if live() then Chat:StripNative(eb) end end, Chat)
		end)
	end
	if _G.FCF_FadeInChatFrame then
		hooksecurefunc("FCF_FadeInChatFrame", function(f)
			if live() then Chat:SkinFrame(f) end
		end)
	end
end

function Chat:Reskin()
	EachFrame(function(f) Chat:SkinFrame(f) end)
	self:SkinAllTabs()
	-- Blizzard restores its own idea of where the chat frame goes from several of
	-- the functions that land us here, so ours is re-applied afterwards rather
	-- than set once and hoped for.
	if A.Movers and A.Movers.registry.chat then A.Movers:Restore("chat") end
	self:AnchorPanel()
	self:UpdateComposers()
end

--- Belt and braces, three times a second, and it is here on merit.
--
--  Three separate hook targets for the header have now been tried - the
--  deprecated global alias (a dead snapshot, never called), the mixin table
--  (copied per-frame by XML `mixin=`, so existing boxes keep the original), and
--  the instance method. Each one installed without complaint and at least two of
--  them fired never. That is the failure mode that has cost the most time on
--  this module by a wide margin, and no amount of reading gets me a guarantee
--  that the third is different on every client.
--
--  So this asks the question directly instead of waiting to be told: is the
--  header showing text, and is the chat type stranded? Two string compares per
--  chat frame, three times a second. It cannot silently not run.
function Chat:Watchdog()
	if not self.enabled then return end
	EachFrame(function(f)
		local eb = f.editBox or _G[(f:GetName() or "") .. "EditBox"]
		if not eb or not eb._aether then return end

		UnstickVoiceText(eb)

		local ebName = eb.GetName and eb:GetName()
		for _, key in ipairs({ "header", "headerSuffix", "prompt" }) do
			local fs = eb[key]
				or (ebName and _G[ebName .. key:gsub("^%l", string.upper)])
			if fs and fs.GetText and (fs:GetText() or "") ~= "" then
				Chat:StripNative(eb)
				return
			end
		end
	end)
end

--- Everything drawing text anywhere near the edit box, with where it lives.
--
--  For the next one of these, and there will be a next one: rather than another
--  round of "it must be the header", this says what the thing is, what it says,
--  who its parent is and whether it is on screen.
function Chat:Diagnose()
	local eb = _G.ChatFrame1 and (_G.ChatFrame1.editBox or _G.ChatFrame1EditBox)
	if not eb then A:Print("no edit box found.") return end
	A:Print("edit box: " .. tostring(eb:GetName()))

	local function walk(frame, depth, path)
		if not frame or depth > 3 then return end
		local ok, regions = pcall(function() return { frame:GetRegions() } end)
		if ok then
			for _, r in ipairs(regions) do
				if r and r.GetObjectType and r:GetObjectType() == "FontString" then
					local txt = r.GetText and r:GetText()
					if txt and txt ~= "" then
						-- Effective visibility, not IsShown. IsShown is per-object:
						-- a FontString on a hidden parent still reports true, which
						-- made the last dump impossible to read.
						local visible = r.IsVisible and r:IsVisible()
						DEFAULT_CHAT_FRAME:AddMessage(string.format(
							"   %s%s  " .. A.Val("'%s'") .. "  alpha=%.2f %s",
							string.rep("  ", depth), path,
							tostring(txt), r:GetAlpha() or 1,
							visible and A.Bad("ON SCREEN") or A.Good("not drawn")))
					end
				end
			end
		end
		local ok2, kids = pcall(function() return { frame:GetChildren() } end)
		if ok2 then
			for i, kid in ipairs(kids) do
				walk(kid, depth + 1,
					tostring(kid.GetName and kid:GetName() or ("child " .. i)))
			end
		end
	end

	walk(eb, 0, tostring(eb:GetName()))
	local insets = eb.GetTextInsets and select(1, eb:GetTextInsets())
	A:Print("left text inset: " .. tostring(insets))

	-- Where each piece actually is, because "the composer is not attached to the
	-- chat window" is a question about anchors and nothing else in this dump
	-- answers it. Blizzard re-anchors the edit box on activation, so what we set
	-- at skin time is not necessarily what is on the frame now.
	A:Print("anchors:")
	local function report(label, frame)
		if not frame then
			DEFAULT_CHAT_FRAME:AddMessage("   " .. label .. "  " .. A.Bad("absent"))
			return
		end
		local n = (frame.GetNumPoints and frame:GetNumPoints()) or 0
		if n == 0 then
			DEFAULT_CHAT_FRAME:AddMessage("   " .. label
				.. "  " .. A.Bad("no points at all"))
			return
		end
		for i = 1, n do
			local point, rel, relPoint, x, y = frame:GetPoint(i)
			local relName = rel and (rel.GetName and rel:GetName()) or tostring(rel)
			DEFAULT_CHAT_FRAME:AddMessage(string.format(
				"   %-14s %s -> %s of " .. A.Val("%s") .. "  (%.0f, %.0f)%s",
				i == 1 and label or "", tostring(point), tostring(relPoint),
				tostring(relName), x or 0, y or 0,
				frame.IsShown and not frame:IsShown() and "  " .. A.Dim("hidden") or ""))
		end
	end
	report("chat frame", _G.ChatFrame1)
	report("panel", self.panel)
	report("capsule", eb._pill)
	report("edit box", eb)

	local shown = {}
	EachFrame(function(f)
		local box = f.editBox or _G[(f:GetName() or "") .. "EditBox"]
		if box and box._pill and box._pill:IsShown() then
			shown[#shown + 1] = f:GetName() or "?"
		end
	end)
	A:Print("composers on screen: " .. A.Val(#shown) .. " "
		.. (#shown > 0 and ("(" .. table.concat(shown, ", ") .. ")") or ""))

	self:DiagnoseLines()
end

--- What the line work actually managed to install.
--
--  Same principle as the frame diagnostic above and as `/aether diag`: every
--  one of these can fail by not being there, and a hook that quietly never runs
--  has cost more time on this module than every other kind of bug put together.
--  So each one is asked and answered by name.
function Chat:DiagnoseLines()
	local U = _G.ChatFrameUtil

	local function say(label, ok, detail)
		DEFAULT_CHAT_FRAME:AddMessage(string.format("   %-22s %s%s",
			label,
			ok and A.Good("yes") or A.Bad("no"),
			detail and ("  " .. A.Dim(detail)) or ""))
	end

	A:Print("message lines:")
	say("ChatFrameUtil", U ~= nil)
	say("sender filter", self._senderFilter == true,
		U and type(U.AddSenderNameFilter) == "function"
			and "AddSenderNameFilter present" or "no AddSenderNameFilter")

	-- No pipe in this label. A literal "|T" opens a texture escape that never
	-- closes, and the parser would eat the rest of the line - so the one row
	-- that says whether markup works would be the one row you cannot read.
	local ids = 0
	for _ in pairs(self:DimIDs()) do ids = ids + 1 end
	say("dimmable type ids", ids > 0, ids .. " of " .. #DIM_TYPES)
	say("texture tinting", self:MarkupSupport() == true,
		self:MarkupSupport() and "vertex colour accepted"
			or "falling back to untinted badges")

	local reshaped, kept = {}, {}
	for _, kind in ipairs(FORMAT_TYPES) do
		local key = "CHAT_" .. kind .. "_GET"
		local orig = (self._formats or {})[key]
		if orig == nil then
			kept[#kept + 1] = kind .. "(untouched)"
		elseif orig == false then
			kept[#kept + 1] = kind .. "(absent)"
		elseif _G[key] ~= orig then
			reshaped[#reshaped + 1] = kind
		else
			kept[#kept + 1] = kind
		end
	end
	say("formats reshaped", #reshaped > 0, table.concat(reshaped, " "))
	if #kept > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("   "
			.. A.Dim("left as Blizzard's: " .. table.concat(kept, " ")))
	end

	local wrapped = 0
	EachFrame(function(f) if f._aetherAddMessage then wrapped = wrapped + 1 end end)
	say("AddMessage wrapped", wrapped > 0, wrapped .. " frame(s)")

	local wf = self:WhisperFrame()
	say("whispers tab", wf ~= nil, wf and (wf:GetName() or "?") or "not created")
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function Chat:OnEnable()
	if not _G.ChatFrame1 then return end

	if not self.panel then self.panel = BuildPanel() end
	self.panel:Show()

	InstallHooks()
	-- Once for the life of the session, like the hooks: a filter registered with
	-- Blizzard's registry is removable, but re-registering it on every reskin
	-- would be pointless churn. `Reskin` runs from six different events.
	self:InstallLineFilters()

	-- `/aether unlock` moves everything else in this UI, so it moves this too.
	-- Blizzard's own tab drag still works and still saves into Blizzard's saved
	-- variables; this is the one that matches the rest of the addon, which is
	-- what anyone would reach for first.
	A.Movers:Register("chat", _G.ChatFrame1,
		{ point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 34, y = 66 }, "Chat",
		{ onPlaced = SaveToBlizzard,
		  -- Movers calls this on unlock and on lock. It exists for frames that
		  -- are only on screen when the game says so; the grip is one that is
		  -- only on screen when the PLAYER says so, and the hook is the same.
		  preview = function(show) Chat:ShowGrip(show) end })

	self:Reskin()
	self:RestoreSize()

	for _, e in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS",
		"PLAYER_ENTERING_WORLD" }) do
		A:RegisterEvent(self, e, function()
			Chat:Reskin()
			-- Every one of these is a moment the client has just decided what
			-- the chat windows look like, which is every moment ours can be
			-- overwritten. FCF_RestorePositionAndDimensions is not called on
			-- all of them - UPDATE_CHAT_WINDOWS fires on its own at login on
			-- some clients - and RestoreSize is a no-op when the size is
			-- already right, so asking on each costs nothing.
			Chat:RestoreSize()
		end)
	end
	for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
		"ZONE_CHANGED_NEW_AREA" }) do
		A:RegisterEvent(self, e, function() Chat:UpdateZone() end)
	end

	-- One ticker for the unread dots. There is no event for "Blizzard started
	-- flashing a tab" - it is an animation - so this is read rather than waited
	-- for, at a rate nobody can feel.
	self._accum = 0
	A:RegisterTicker(self, function(_, dt)
		Chat._accum = (Chat._accum or 0) + dt
		if Chat._accum < 0.3 then return end
		Chat._accum = 0
		Chat:UpdateFlashes()
		Chat:Watchdog()
	end)

	self:RegisterFader()
	self:OnConfigChanged()

	-- Deliberately after OnConfigChanged, and deliberately only when it is
	-- already on: this creates a Blizzard chat window, which is not something to
	-- do as a side effect of loading. A reload finds the window already there
	-- and only re-asserts where the message groups live.
	if A.Config:Module("chat").whisperTab == true then
		self:SetWhisperTab(true)
	end
end

--- Chat breathes with everything else. It is registered as three things rather
--  than one because the panel, the message frame and the edit box's capsule are
--  siblings, not a family - the chat frame is Blizzard's and stays where
--  Blizzard put it.
function Chat:RegisterFader()
	local cfg = A.Config:Module("chat")
	if cfg.fade == false then return end
	A.Fader:Register(self.panel, {})
	EachFrame(function(f) A.Fader:Register(f, {}) end)
	local eb = _G.ChatFrame1 and (_G.ChatFrame1.editBox or _G.ChatFrame1EditBox)
	if eb and eb._pill then A.Fader:Register(eb._pill, {}) end
	A.Fader:Refresh()
end

function Chat:UnregisterFader()
	if self.panel then A.Fader:Unregister(self.panel) end
	EachFrame(function(f) A.Fader:Unregister(f) end)
	A.Fader:Refresh()
end

function Chat:OnDisable()
	A:UnregisterTicker(self)
	A.Movers:Unregister("chat")
	self:UnregisterFader()
	if self.panel then self.panel:Hide() end

	-- The line work *does* come off cleanly, unlike the frame skin below: a
	-- filter can be removed, a format string put back and a wrapped method
	-- unwrapped. Lines already in the log keep the colours they were built with,
	-- because a line is a string that was assembled once.
	self:RemoveLineFilters()
	self:RestoreFormats()
	EachFrame(function(f) Chat:UnwrapAddMessage(f) end)
	-- Blizzard's own look does not come back without a reload, and saying so is
	-- better than pretending: every region we hid is hidden, and the functions
	-- that would re-show them are the ones we are hooked onto.
	A:Print("chat skin off. " .. A.Hi("/reload") .. " to get Blizzard's frames back.")
end

function Chat:OnSkinChanged()
	if not self.enabled then return end
	local c = Palette.c
	if self.panel then
		self.panel:ApplySkin("glassStrong")
		self.panel:SetFillColor(ChatFill(c))
		W.Color(self.panel.zone, c.textFaint)
		self.panel.divider:SetVertexColor(c.glassEdge[1], c.glassEdge[2],
			c.glassEdge[3], 0.5)
	end
	self:SkinAllTabs()
	EachFrame(function(f)
		Chat:SetFrameFont(f)
		Chat:StyleEditBox(f.editBox or _G[(f:GetName() or "") .. "EditBox"])
		Chat:SkinResize(f)
	end)
	-- Nothing here re-colours the lines already in the log, and nothing can. A
	-- chat line is a string that was assembled once, with its colours written
	-- into it as escape sequences; there is no region left to call SetTextColor
	-- on. New lines take the new skin from here on.
end

function Chat:OnConfigChanged()
	if not self.enabled then return end
	local cfg = A.Config:Module("chat")
	if self.panel then
		self.panel:SetShadow(A.db.profile.glass.shadow)
		self.panel:SetAlpha(1)
	end
	EachFrame(function(f) Chat:SkinFrame(f) end)
	self:SkinAllTabs()
	self:AnchorPanel()
	self:ApplyFormats()
	self:OnSkinChanged()
	if cfg.fade == false then
		self:UnregisterFader()
	else
		self:RegisterFader()
	end
end
