--[[--------------------------------------------------------------------------
	Lattice :: the N.I.F.E.C. node

	The N.I.F.E.C. on the World trunk (Joe, 2026-10-07, decision 2 of the prune
	audit): a node with the world tools, lit while something plays, whose branch
	holds the mini-player. It took over from the Toolbox's rail chip and the
	drawer's NOW PLAYING section. While a track is on, its title sits under the
	stub and the stub fills as a lane does (Joe's option D, 2026-10-10).

	Right-click the node for Stop, Previous and Next. The trunk retracts in a
	fight, so pausing mid-fight is the "Play / pause" key binding.

	Absent with no content installed, the same question the console asks. The
	minimap attaches the node only if this file loaded.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = A.L
local W = A.Widgets

A.IFEC = A.IFEC or {}
local Node = {}
A.IFEC.Node = Node

local WIDTH, PAD, HEAD_H = 280, 16, 20

local function Trunk() return A.Trunk:Get("world") end
local function Mini() return A.IFEC.Mini end
local function Playback() return A.IFEC.Playback end

function Node:Available()
	local M = Mini()
	return (M ~= nil and M:HasContent()) and true or false
end

function Node:Playing()
	local P = Playback()
	return (P ~= nil and P:IsPlaying()) and true or false
end

--- The track, playing or paused; nil with nothing on.
local function Current()
	local P = Playback()
	if not P or not (P.state == "playing" or P.state == "paused") then return nil end
	return P.item, P
end

function Node:Title()
	local item = Current()
	return item and item.title or nil
end

--- How far through the track, 0 to 1; nil with nothing on.
function Node:Progress()
	local item, P = Current()
	if not item then return nil end
	local total = item.duration or 0
	if total <= 0 then return 0 end
	return math.max(0, math.min(1, (P:Elapsed() or 0) / total))
end

function Node:Build()
	if self.panel then return self.panel end
	local p = Trunk():Branch("NowPlayingBranch", WIDTH)

	p.head = A.Trunk.Head(p)
	p.head:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -PAD)
	p.head:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -PAD)
	p.head:Set(L.nowplaying.heading, "")

	p:HookScript("OnHide", function()
		-- The library hangs off the mini-player; it goes with the branch.
		local M, LB = Mini(), A.IFEC.Library
		if LB and M and M.frame then LB:CloseFor(M.frame) end
	end)

	self.panel = p
	self:Skin()
	return p
end

function Node:Skin()
	local p = self.panel
	if not p then return end
	A.Trunk.SkinBranch(p)
	p.head:Paint()
	local M = Mini()
	if M and M.frame then M:Restyle() end
end

--- Hang the mini-player in the branch. It is one frame; Build re-parents it.
function Node:Fill()
	local p, M = self.panel, Mini()
	if not (p and M) then return end
	local f = M:Build(p)
	if not f then return end
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -(PAD + HEAD_H))
	f:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -(PAD + HEAD_H))
	f:SetHeight(M.HEIGHT)
	f:Show()
	-- The library opens away from the trunk.
	f.__aetherLibraryFrom = ((Trunk().side or -1) < 0) and "LEFT" or "RIGHT"
	p:SetHeight(PAD + HEAD_H + M.HEIGHT)
	M:Paint()
end

function Node:Open()
	local p = self:Build()
	self:Fill()
	if not Trunk():Place("nowplaying", p) then return end
	p:Show()
end

function Node:Close()
	if self.panel then self.panel:Hide() end
end

function Node:IsOpen()
	return self.panel and self.panel:IsShown() and true or false
end

--- Stop, Previous and Next on a right-click, opening away from the trunk.
function Node:Menu(button)
	local M = Mini()
	if not (M and W.Menu) then return end
	local left = (Trunk().side or -1) < 0
	W.Menu(button, M:TransportEntries(), {
		point = left and "TOPRIGHT" or "TOPLEFT",
		relPoint = left and "BOTTOMLEFT" or "BOTTOMRIGHT",
		x = 0, y = -4,
	})
end

--- Playing started or stopped, or content came or went: the node's light, its
--  presence, and the branch if it is open.
function Node:Changed()
	if not self.attached then return end
	local up = self:Available()
	if up ~= self.wasUp then
		self.wasUp = up
		if not up then self:Close() end
		Trunk():Refresh()
	else
		Trunk():Paint()
	end
end

function Node:Attach()
	Trunk():AddNode("nowplaying", {
		icon = "music", label = L.trunk.nifec, order = 950,
		transient = true,
		available = function() return Node:Available() end,
		isOpen = function() return Node:IsOpen() end,
		-- Lit while something plays, open or not.
		active = function() return Node:Playing() end,
		open = function() Node:Open() end,
		close = function() Node:Close() end,
		onRightClick = function(node) Node:Menu(node.button) end,
		-- What is playing, under the stub, and the stub filling as it plays
		-- (Joe's option D). Paused counts: it is still where you are.
		subtitle = function() return Node:Title() end,
		progress = function() return Node:Progress() end,
	})
	self.attached = true
	-- The lane moves on its own, ten times a second, only while there is a
	-- track to follow.
	A:RegisterTicker(self, function()
		if not Node.attached then return end
		local live = Node:Title() ~= nil
		if live or Node.wasLive then Trunk():Decorate("nowplaying") end
		Node.wasLive = live
	end)
	self.wasUp = self:Available()
	if not self.listening then
		self.listening = true
		local P = Playback()
		if P then P:AddListener(function() Node:Changed() end) end
		local R = A.IFEC.Registry
		if R then R.onChange = function() Node:Changed() end end
	end
end

function Node:Detach()
	self.attached = false
	self:Close()
	A:UnregisterTicker(self)
end

-- The key binding, for pausing when the trunk is retracted in a fight.
_G.BINDING_NAME_LATTICE_PLAYPAUSE = L.nowplaying.binding
function _G.Lattice_PlayPause()
	local P = Playback()
	if P then P:PlayOrShuffle() end
end
