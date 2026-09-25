--!strict
--[[
	Context
	What every view is handed: the plugin (for native menus) and persistent
	settings.
]]

local PluginSettings = require(script.Parent.Parent.Services.PluginSettings)

export type Context = {
	Plugin: Plugin,
	Settings: PluginSettings.PluginSettings,
}

-- Types only; the table keeps `require` happy at runtime.
return {}
