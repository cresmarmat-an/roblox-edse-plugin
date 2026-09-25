--!strict
--[[
	Theme
	Owns the active palette and keeps every bound instance in sync with it.

	Modes:
	  System - follows Studio's theme (by the luminance of its main background,
	           so custom or future Studio themes resolve correctly too)
	  Light / Dark - fixed

	Views never hard-code colors; they call Theme.Bind(instance, property,
	token) where token is a palette key or a function of the palette. When the
	palette changes, Color3 properties tween and everything else snaps.
]]

local TweenService = game:GetService("TweenService")

local Palette = require(script.Parent.Palette)
local Signal = require(script.Parent.Parent.Core.Signal)

export type Mode = "System" | "Light" | "Dark"
export type Token = string | (palette: Palette.Palette) -> any

local THEME_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LUMINANCE_DARK_THRESHOLD = 0.5

local Theme = {}

Theme.MODES = { "System", "Light", "Dark" } :: { Mode }
Theme.Changed = Signal.new() :: Signal.Signal<Palette.Palette>

local currentMode: Mode = "System"
local currentPalette: Palette.Palette = Palette.Light
local studioThemeConnection: RBXScriptConnection? = nil

-- instance -> property -> token. Weak keys let destroyed, unreferenced
-- instances be collected without explicit unbinding.
local bindings: { [Instance]: { [string]: Token } } = setmetatable({}, { __mode = "k" }) :: any

local function StudioPrefersDark(): boolean
	local ok, isDark = pcall(function(): boolean
		local studioTheme = (settings() :: any).Studio.Theme :: StudioTheme
		local background = studioTheme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
		local luminance = 0.2126 * background.R + 0.7152 * background.G + 0.0722 * background.B
		return luminance < LUMINANCE_DARK_THRESHOLD
	end)
	return ok and isDark
end

local function Resolve(token: Token, palette: Palette.Palette): any
	if type(token) == "function" then
		return token(palette)
	end
	local value = (palette :: any)[token]
	if value == nil then
		error(`Unknown theme token "{token}"`, 3)
	end
	return value
end

local function ApplyPalette(palette: Palette.Palette, animate: boolean)
	if palette == currentPalette and animate then
		return
	end
	currentPalette = palette
	for instance, properties in bindings do
		-- Unparented instances (pooled rows, closed dialogs) snap instead of
		-- tweening, so they are correct whenever they are shown again.
		local shouldTween = animate and instance.Parent ~= nil
		local tweenGoals: { [string]: any } = {}
		local hasTween = false
		for property, token in properties do
			local value = Resolve(token, palette)
			if shouldTween and (typeof(value) == "Color3" or typeof(value) == "number") then
				tweenGoals[property] = value
				hasTween = true
			else
				(instance :: any)[property] = value
			end
		end
		if hasTween then
			TweenService:Create(instance, THEME_TWEEN, tweenGoals):Play()
		end
	end
	Theme.Changed:Fire(palette)
end

local function PaletteForMode(mode: Mode): Palette.Palette
	if mode == "Light" then
		return Palette.Light
	elseif mode == "Dark" then
		return Palette.Dark
	end
	return if StudioPrefersDark() then Palette.Dark else Palette.Light
end

-- Whether Studio itself is using a dark theme (independent of EDSE's mode).
function Theme.StudioIsDark(): boolean
	return StudioPrefersDark()
end

-- Calls `callback` whenever Studio's own theme changes.
function Theme.OnStudioThemeChanged(callback: () -> ()): RBXScriptConnection?
	local ok, connection = pcall(function(): RBXScriptConnection
		return (settings() :: any).Studio.ThemeChanged:Connect(callback)
	end)
	return if ok then connection else nil
end

function Theme.Init(mode: Mode)
	currentMode = mode
	ApplyPalette(PaletteForMode(mode), false)

	local ok, connection = pcall(function(): RBXScriptConnection
		return (settings() :: any).Studio.ThemeChanged:Connect(function()
			if currentMode == "System" then
				ApplyPalette(PaletteForMode("System"), true)
			end
		end)
	end)
	studioThemeConnection = if ok then connection else nil
end

function Theme.GetMode(): Mode
	return currentMode
end

function Theme.SetMode(mode: Mode)
	currentMode = mode
	ApplyPalette(PaletteForMode(mode), true)
end

function Theme.Current(): Palette.Palette
	return currentPalette
end

function Theme.Get(token: Token): any
	return Resolve(token, currentPalette)
end

-- Applies `token` to `instance[property]` now and on every theme change.
-- Pass `deferApply` when the caller animates to the new value itself.
function Theme.Bind(instance: Instance, property: string, token: Token, deferApply: boolean?)
	local properties = bindings[instance]
	if properties == nil then
		properties = {}
		bindings[instance] = properties
	end
	properties[property] = token
	if not deferApply then
		(instance :: any)[property] = Resolve(token, currentPalette)
	end
end

-- Binds several properties at once: Theme.BindAll(frame, { BackgroundColor3 = "Background" }).
function Theme.BindAll(instance: Instance, tokens: { [string]: Token })
	for property, token in tokens do
		Theme.Bind(instance, property, token)
	end
end

function Theme.Destroy()
	if studioThemeConnection then
		studioThemeConnection:Disconnect()
		studioThemeConnection = nil
	end
	table.clear(bindings)
	Theme.Changed:DisconnectAll()
end

return Theme
