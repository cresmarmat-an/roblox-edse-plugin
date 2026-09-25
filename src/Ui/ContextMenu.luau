--!strict
--[[
	ContextMenu
	Shows a native Studio context menu (PluginMenu) and returns the id of the
	chosen item, or nil if dismissed. Native menus are keyboard-navigable and
	never clip at the widget's edges, which makes them the right tool for
	right-click actions.
]]

local HttpService = game:GetService("HttpService")

export type MenuItem = {
	Id: string?,
	Text: string?,
	IsSeparator: boolean?,
	Items: { MenuItem }?, -- a submenu
}

local ContextMenu = {}

ContextMenu.SEPARATOR = { IsSeparator = true } :: MenuItem

-- Yields until the menu closes.
function ContextMenu.Show(plugin: Plugin, items: { MenuItem }): string?
	local actionToId: { [Instance]: string } = {}
	local createdMenus: { PluginMenu } = {}

	local function Build(menuItems: { MenuItem }, title: string): PluginMenu
		local menu = plugin:CreatePluginMenu(HttpService:GenerateGUID(false), title)
		table.insert(createdMenus, menu)
		for _, item in menuItems do
			if item.IsSeparator then
				menu:AddSeparator()
			elseif item.Items then
				menu:AddMenu(Build(item.Items, item.Text or ""))
			elseif item.Id and item.Text then
				local action = menu:AddNewAction(HttpService:GenerateGUID(false), item.Text)
				actionToId[action] = item.Id
			end
		end
		return menu
	end

	local rootMenu = Build(items, "")
	local chosen = rootMenu:ShowAsync()
	local chosenId = if chosen then actionToId[chosen] else nil
	for _, menu in createdMenus do
		menu:Destroy()
	end
	return chosenId
end

return ContextMenu
