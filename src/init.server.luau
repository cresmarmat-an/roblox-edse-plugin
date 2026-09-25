--!strict
--[[
	EDSE: edit live Roblox DataStores without leaving Studio.

	Plugin entry point: toolbar button, dock widget, and bindable shortcuts.
	The UI is built lazily the first time the widget opens, so the plugin
	costs nothing until you use it.
]]

local RunService = game:GetService("RunService")

-- Plugins load in every DataModel (edit, play server, play client). EDSE is an
-- edit-time tool; running it once avoids duplicate widgets during play tests.
if not RunService:IsEdit() then
	return
end

local App = require(script.App)
local Icons = require(script.Theme.Icons)
local PluginSettings = require(script.Services.PluginSettings)
local Theme = require(script.Theme.Theme)

local WIDGET_ID = "EDSE_DataStoreEditor"
local WIDGET_TITLE = "EDSE Easy DataStore Editor"
local TOOLBAR_NAME = "EDSE"
local BUTTON_TEXT = "EDSE"
local BUTTON_TOOLTIP = "EDSE Easy DataStore Editor: browse and edit live DataStores"
-- Initial floating window size and minimum size, in pixels (window chrome,
-- not UI layout; everything inside the widget is scale-sized).
local WIDGET_INFO = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 1000, 660, 420, 380)

-- Plugin satisfies the Storage shape (GetSetting/SetSetting); the cast bridges
-- the method signatures, which the type checker models differently.
local settings = PluginSettings.new(plugin :: any, tostring(game.GameId))
Theme.Init(App.ReadThemeMode(settings))

-- Studio shows toolbar icons untinted, so pick the variant for its theme.
local function ToolbarIcon(): string
	return Icons.AssetOrBlank(if Theme.StudioIsDark() then "ToolbarDark" else "ToolbarLight")
end

local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
local toggleButton = toolbar:CreateButton("EDSE_Toggle", BUTTON_TOOLTIP, ToolbarIcon(), BUTTON_TEXT)
toggleButton.ClickableWhenViewportHidden = true
local studioThemeConnection = Theme.OnStudioThemeChanged(function()
	toggleButton.Icon = ToolbarIcon()
end)

local widget = plugin:CreateDockWidgetPluginGuiAsync(WIDGET_ID, WIDGET_INFO)
widget.Title = WIDGET_TITLE
widget.Name = "EDSE"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local app: App.App? = nil

local function EnsureApp(): App.App
	if app == nil then
		app = App.new({ Plugin = plugin, Widget = widget, Settings = settings })
	end
	return app :: App.App
end

local function SyncWidgetState()
	toggleButton:SetActive(widget.Enabled)
	if widget.Enabled then
		EnsureApp()
	end
end

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(SyncWidgetState)
SyncWidgetState()

-- Bindable shortcuts: assign keys in File → Advanced → Customize Shortcuts
-- (search for "EDSE").
local function BindAction(id: string, text: string, statusTip: string, handler: (App.App) -> ())
	local action = plugin:CreatePluginAction(id, text, statusTip, "", true)
	action.Triggered:Connect(function()
		if widget.Enabled then
			handler(EnsureApp())
		end
	end)
end

BindAction("EDSE_Save", "EDSE: Save entry", "Save the open DataStore entry", function(currentApp)
	currentApp:Save()
end)
BindAction("EDSE_Refresh", "EDSE: Reload entry", "Reload the open entry from the data store", function(currentApp)
	currentApp:Refresh()
end)
BindAction("EDSE_FocusSearch", "EDSE: Search keys", "Jump to the key search box", function(currentApp)
	currentApp:FocusSearch()
end)
BindAction("EDSE_ToggleOutput", "EDSE: Toggle output", "Show or hide the output log", function(currentApp)
	currentApp:ToggleOutput()
end)
plugin
	:CreatePluginAction("EDSE_ToggleWindow", "EDSE: Toggle window", "Show or hide EDSE", "", true).Triggered
	:Connect(function()
		widget.Enabled = not widget.Enabled
	end)

plugin.Unloading:Connect(function()
	if studioThemeConnection then
		studioThemeConnection:Disconnect()
	end
	if app then
		app:Destroy()
		app = nil
	end
	Theme.Destroy()
end)
