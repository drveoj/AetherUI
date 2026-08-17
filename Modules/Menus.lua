--[[--------------------------------------------------------------------------
	AetherUI :: Menus

	The client's own right-click menus - the one on your portrait, your pet's,
	the one on a chat tab - in this interface's glass and lettering.

	TWO CHOKE POINTS, NOT A HUNDRED FRAMES. Everything the game opens with a
	right-click goes through Blizzard_Menu, and that addon builds each menu the
	same way every time:

	  * `MenuStyle1Mixin:Generate` draws the panel. It is mixed into the menu
	    frame on every acquire, not once at creation, so replacing the function
	    reaches every menu opened afterwards - including ones the pool has
	    already handed out before.

	So this module is ONE hook and no per-frame list, which is the whole reason
	it is worth doing at all.

	The TEXT is not here. A menu line is given GameFontHighlight by the
	compositor on every acquire, and Modules\Fonts.lua has already remapped that
	object - so the lettering follows without this module knowing anything about
	it. A hook here would be a second owner for the same fact, and one more of
	our functions running inside the menu's own generation path.

	WHAT WE MAY AND MAY NOT DO TO A MENU FRAME. The menus are pooled and handed
	round by a compositor that forbids some calls on the frames it owns:

	  * `CreateTexture` and `CreateFontString` are disallowed on the menu frame
	    itself - the compositor has to know about every region it will later
	    have to recycle. So the glass is a CHILD FRAME of the menu rather than
	    textures on it: our own frame, built by our own constructor, and the
	    compositor neither sees it nor has to.

	The panel is remembered in a table of ours rather than on the frame, because
	the compositor discards value changes on a frame when it reclaims it - a
	note left there would be gone by the next open and we would build a second
	panel every time.

	COLOURS ARE STILL THE CLIENT'S. A player's name is their class colour, a
	heading is gold, a disabled line is grey; the menu code sets those per line
	and means them. Only the FACE and the panel behind it are ours.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local MN = A:NewModule("menus")

local Glass, Palette = A.Glass, A.Palette

local function cfg() return A.Config:Module("menus") end

--- The glass behind each pooled menu frame, kept by us.
--
--  Not weak. There are a handful of these for the life of the session - the
--  pool is small and never grows without bound - and a weak table here would
--  let a panel be collected while its frame is still in the pool, which reads
--  as the skin randomly failing to apply.
local panels = {}

-- What we replaced, so switching the module off puts it back.
local originalGenerate

-- ---------------------------------------------------------------------------
-- the panel
-- ---------------------------------------------------------------------------

--- The glass for one menu frame, built once and reused with it.
local function PanelFor(menu)
	local panel = panels[menu]
	if panel then return panel end

	panel = Glass.CreatePanel(menu, {
		corner = A.db.profile.glass.corner,
		shadow = A.db.profile.glass.shadow,
	})
	-- BELOW THE ENTRIES. A child frame draws above its parent's own regions,
	-- and the menu's buttons are children too - so this has to sit at the
	-- menu's own level to end up behind them rather than over the text.
	if panel.SetFrameLevel and menu.GetFrameLevel then
		panel:SetFrameLevel(math.max(0, (menu:GetFrameLevel() or 1) - 1))
	end
	panel:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
	panel:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 0)

	panels[menu] = panel
	return panel
end

--- Our Generate: the glass, and none of Blizzard's art.
--
--  Blizzard's own is not called at all. It attaches an atlas and a black fill
--  to the frame, and both would sit on top of - or behind, depending on the
--  draw layer it happened to pick - a panel that is already saying the same
--  thing. Two backgrounds is not a skin.
local function Generate(self)
	local panel = PanelFor(self)
	panel:ApplySkin("dialogFill", "glassEdgeHi")
	panel:Show()
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

--- Is the client's menu system the one we know how to dress?
--
--  Asked rather than assumed. Blizzard_Menu is present on 1.15.9 and this is
--  written against it, but a module whose absence should cost a skin must not
--  cost the interface on a build that does not have it.
function MN:Available()
	return type(_G.MenuStyle1Mixin) == "table"
		and type(_G.MenuStyle1Mixin.Generate) == "function"
end

function MN:OnEnable()
	if not self:Available() then
		self.absent = true
		return
	end
	self.absent = nil

	originalGenerate = originalGenerate or _G.MenuStyle1Mixin.Generate
	_G.MenuStyle1Mixin.Generate = Generate
end

function MN:OnDisable()
	if originalGenerate then _G.MenuStyle1Mixin.Generate = originalGenerate end

	-- The panels go with it. Hidden rather than destroyed - this API cannot
	-- destroy a frame - and left in the table, so switching back on reuses them
	-- instead of building a second set behind the first.
	for _, panel in pairs(panels) do panel:Hide() end
end

--- The glass follows the skin like every other surface.
--
--  Through ApplySkin, so the central sweep in A:Restyle finds these too - they
--  are ordinary panels of ours and there is nothing special about them.
function MN:OnSkinChanged()
	if not self.enabled or self.absent then return end
	for _, panel in pairs(panels) do
		panel:ApplySkin("dialogFill", "glassEdgeHi")
	end
end

function MN:OnConfigChanged()
	if not self.enabled or self.absent then return end
	for _, panel in pairs(panels) do
		Glass.SetPanelCorner(panel, A.db.profile.glass.corner)
		panel:SetShadow(A.db.profile.glass.shadow)
	end
end
