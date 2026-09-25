--!strict
--[[
	Icons
	Every icon EDSE draws, in one place. Each defaults to one of Studio's own
	built-in icons (rbxasset://studio_svg_textures/..., which ships with every
	Studio install) so the plugin looks finished out of the box.

	To use your own art, replace an entry with "rbxassetid://<id>". Upload
	white (or light gray) glyphs on a transparent background: icons are tinted
	with the theme's colors, so light source art tints cleanly in both themes.
	Setting an entry to "rbxassetid://0" or "" hides that icon.
]]

local STUDIO_ICONS = "rbxasset://studio_svg_textures/"

local Icons: { [string]: string } = {
	-- Plugins-tab toolbar button. Studio shows it untinted, so there is one
	-- per Studio theme (light glyph for the dark theme and vice versa).
	ToolbarDark = STUDIO_ICONS .. "Shared/InsertableObjects/Dark/Standard/MemoryStoreService.png",
	ToolbarLight = STUDIO_ICONS .. "Shared/InsertableObjects/Light/Standard/MemoryStoreService.png",

	-- Header brand mark.
	Logo = STUDIO_ICONS .. "Shared/InsertableObjects/Dark/Standard/MemoryStoreService.png",

	Store = STUDIO_ICONS .. "Shared/InsertableObjects/Dark/Standard/MemoryStoreService.png",
	Key = STUDIO_ICONS .. "Shared/InsertableObjects/Dark/Standard/Value.png",
	Search = STUDIO_ICONS .. "Lua/DeveloperFramework/Dark/Standard/Search.png",
	Clear = STUDIO_ICONS .. "Lua/FindReplaceAll/Dark/Standard/ClearInput.png",
	Refresh = STUDIO_ICONS .. "Lua/FileSync/Dark/Standard/Refresh.png",
	Save = STUDIO_ICONS .. "Lua/Tutorials/Dark/Standard/Checkmark.png",
	Revert = STUDIO_ICONS .. "Shared/Clipboard/Dark/Standard/Undo.png",
	Add = STUDIO_ICONS .. "Shared/Navigation/Dark/Standard/AddNoBorder.png",
	Close = STUDIO_ICONS .. "Shared/Navigation/Dark/Standard/CloseWidget.png",
	Back = STUDIO_ICONS .. "Shared/Navigation/Dark/Standard/Back.png",
	Caret = STUDIO_ICONS .. "Shared/Navigation/Dark/Standard/ArrowRight.png",
	More = STUDIO_ICONS .. "Shared/Navigation/Dark/Standard/More.png",
	Favorite = STUDIO_ICONS .. "Shared/Utility/Dark/Standard/Bookmark.png",
	FavoriteFilled = STUDIO_ICONS .. "Shared/Utility/Dark/Standard/BookmarkFilled.png",
	Recent = STUDIO_ICONS .. "Shared/Utility/Dark/Standard/Recent.png",
	History = STUDIO_ICONS .. "Shared/WidgetIcons/Dark/Standard/ActivityHistory.png",
	Settings = STUDIO_ICONS .. "Shared/Navigation/Dark/Standard/Settings.png",
	Warning = STUDIO_ICONS .. "Shared/Alerts/Dark/Standard/Warning.png",
	ExpandAll = STUDIO_ICONS .. "Shared/Navigation/Dark/Standard/Expand.png",
	CollapseAll = STUDIO_ICONS .. "Shared/Navigation/Dark/Standard/Collapse.png",
	Copy = STUDIO_ICONS .. "Shared/Clipboard/Dark/Standard/Copy.png",
	Trash = STUDIO_ICONS .. "Lua/TagEditor/Dark/Standard/Tag_Delete.png",
	-- Output panel toggle: open (arrow up) and close (arrow down).
	PanelOpen = STUDIO_ICONS .. "Shared/Navigation/Dark/Standard/ArrowUp.png",
	PanelClose = STUDIO_ICONS .. "Shared/Navigation/Dark/Standard/ArrowDown.png",
}

local IconsModule = {
	Icons = Icons,
}

-- True when an icon is intentionally left blank.
function IconsModule.IsBlank(assetId: string): boolean
	return assetId == "" or assetId == "rbxassetid://0"
end

function IconsModule.Get(name: string): string
	local assetId = Icons[name]
	if assetId == nil then
		error(`Unknown icon "{name}"`, 2)
	end
	return assetId
end

-- The id to hand to Studio APIs that need an image (e.g. toolbar buttons).
function IconsModule.AssetOrBlank(name: string): string
	local assetId = IconsModule.Get(name)
	return if IconsModule.IsBlank(assetId) then "" else assetId
end

return IconsModule
