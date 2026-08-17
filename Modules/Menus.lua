--[[--------------------------------------------------------------------------
	AetherUI :: Menus

	The client's own right-click menus - the one on your portrait, your pet's,
	the one on a chat tab - in this interface's glass and lettering.

	TWO CHOKE POINTS, NOT A HUNDRED FRAMES. Everything the game opens with a
	right-click goes through Blizzard_Menu, and that addon builds each menu the
	same way every time:

	  * `Generate` on a STYLE MIXIN draws the panel. It is mixed into the menu
	    frame on every acquire, not once at creation, so replacing the function
	    reaches every menu opened afterwards - including ones the pool has
	    already handed out before.

	So this module is a hook per style and no per-frame list, which is the whole
	reason it is worth doing at all.

	THERE ARE TWO STYLES, and the difference cost a build. MenuStyle1Mixin is
	the one a dropdown BUTTON opens - a setting in a panel. A right-click
	CONTEXT menu, which is the one on your portrait and your pet's and the one
	anybody actually notices, is MenuStyle2Mixin: MenuVariants
	.GetDefaultContextMenuMixin returns it on this game type. Hooking only the
	first changed nothing anyone would ever see, and the suite was green about
	it because the mock modelled the mixin that had been hooked rather than the
	one the client reaches for.

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

--- Every menu frame we have dressed, so a skin change can reach them.
--
--  A plain list. The pool is small and a frame is never destroyed, so nothing
--  in here can become garbage.
local menus = {}

-- What we replaced, per style, so switching the module off puts it back.
local originals = {}

--- Every style whose panel is ours.
--
--  Both, rather than the context one alone: a dropdown in the options panel
--  and a right-click menu on a unit frame are the same control to look at,
--  and one of them being Blizzard's reads as a bug rather than as a choice.
local STYLES = { "MenuStyle1Mixin", "MenuStyle2Mixin" }

-- ---------------------------------------------------------------------------
-- the panel
-- ---------------------------------------------------------------------------

--- Our Generate: the menu frame IS the glass, and none of Blizzard's art.
--
--  THE MENU BECOMES THE PANEL rather than getting one inside it. A panel added
--  as a child is a sibling of the menu's own entries, and then which draws on
--  top rests on level, strata and creation order all at once - which came out
--  as an empty sheet of glass with every line hidden behind it.
--
--  A frame's own textures are always under its children, so there is nothing
--  left to get wrong. It is also what Blizzard's Generate does, and the reason
--  Glass asks a frame how to make a texture: this one forbids CreateTexture
--  and offers AttachTexture, because the compositor has to know about every
--  region it will later recycle.
--
--  Blizzard's own Generate is not called at all - it would attach an atlas and
--  a black fill over the top of what we have just drawn, and two backgrounds
--  is not a skin.
local function Generate(self)
	A.Glass.MakePanel(self, {
		corner = A.db.profile.glass.corner,
		shadow = A.db.profile.glass.shadow,
	})
	self:ApplySkin("dialogFill", "glassEdgeHi")
	menus[self] = true
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
	for _, name in ipairs(STYLES) do
		local mixin = _G[name]
		if type(mixin) == "table" and type(mixin.Generate) == "function" then
			return true
		end
	end
	return false
end

function MN:OnEnable()
	if not self:Available() then
		self.absent = true
		return
	end
	self.absent = nil

	for _, name in ipairs(STYLES) do
		local mixin = _G[name]
		if type(mixin) == "table" and type(mixin.Generate) == "function" then
			originals[name] = originals[name] or mixin.Generate
			mixin.Generate = Generate
		end
	end
end

function MN:OnDisable()
	for name, was in pairs(originals) do
		local mixin = _G[name]
		if type(mixin) == "table" then mixin.Generate = was end
	end

	-- The glass stays on the frames already dressed: it IS those frames now,
	-- and a menu is only ever drawn while it is open. The next one the client
	-- opens gets Blizzard's own Generate again, which is what "off" means here.
end

--- The glass follows the skin like every other surface.
--
--  Through ApplySkin, so the central sweep in A:Restyle finds these too - they
--  are ordinary panels of ours and there is nothing special about them.
function MN:OnSkinChanged()
	if not self.enabled or self.absent then return end
	for menu in pairs(menus) do
		if menu.ApplySkin then menu:ApplySkin("dialogFill", "glassEdgeHi") end
	end
end

function MN:OnConfigChanged()
	if not self.enabled or self.absent then return end
	for menu in pairs(menus) do
		if menu._kind then
			Glass.SetPanelCorner(menu, A.db.profile.glass.corner)
			menu:SetShadow(A.db.profile.glass.shadow)
		end
	end
end
