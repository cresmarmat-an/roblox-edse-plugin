--!strict
--[[
	App
	Builds the widget's UI and wires the views together.

	Layout (all scale-sized), over a backdrop of soft color glows that the
	glass panels show through:
	  Header     brand · store picker · theme switch · settings
	             (when narrow, the store picker drops to its own row)
	  Body       KeyList | EntryEditor   (side by side when wide; one at a
	                                      time with a back button when narrow)
	  Output     a recorded log of everything EDSE does, with connection and
	             request budget in its bar (collapsible)
]]

local Context = require(script.Parent.Views.Context)
local Create = require(script.Parent.Ui.Create)
local DataStoreGateway = require(script.Parent.Services.DataStoreGateway)
local Dialog = require(script.Parent.Ui.Components.Dialog)
local Dialogs = require(script.Parent.Views.Dialogs)
local Palette = require(script.Parent.Theme.Palette)
local EntryEditor = require(script.Parent.Views.EntryEditor)
local Header = require(script.Parent.Views.Header)
local KeyList = require(script.Parent.Views.KeyList)
local PluginSettings = require(script.Parent.Services.PluginSettings)
local OutputPanel = require(script.Parent.Views.OutputPanel)
local StoreBar = require(script.Parent.Views.StoreBar)
local StoreRef = require(script.Parent.Core.StoreRef)
local Surface = require(script.Parent.Ui.Surface)
local Theme = require(script.Parent.Theme.Theme)
local Log = require(script.Parent.Services.Log)
local Tooltip = require(script.Parent.Ui.Components.Tooltip)

export type AppProps = {
	Plugin: Plugin,
	Widget: DockWidgetPluginGui,
	Settings: PluginSettings.PluginSettings,
}

export type App = {
	Save: (self: App) -> (),
	Refresh: (self: App) -> (),
	FocusSearch: (self: App) -> (),
	ToggleOutput: (self: App) -> (),
	Destroy: (self: App) -> (),
}

-- Below this width the key list and editor take turns instead of sharing.
local COMPACT_WIDTH = 660
-- Below this width the store picker gets its own row instead of sharing the
-- header, so its fields never get cramped.
local STORE_INLINE_MIN_WIDTH = 900
local BUDGET_REFRESH_SECONDS = 3
local SETTING_THEME_MODE = "ThemeMode"

local App = {}

function App.ReadThemeMode(settings: PluginSettings.PluginSettings): Theme.Mode
	local saved = settings:GetString(SETTING_THEME_MODE, "System")
	return if saved == "Light" or saved == "Dark" then saved else "System"
end

-- Soft radial color glows behind everything: glass needs something to
-- show through. Sizes and positions are scale; each glow stays circular.
local GLOWS: { { Token: string, Size: number, Position: UDim2 } } = {
	{ Token = "Glow1", Size = 0.9, Position = UDim2.fromScale(0.08, 0.1) },
	{ Token = "Glow2", Size = 0.75, Position = UDim2.fromScale(0.92, 0.3) },
	{ Token = "Glow3", Size = 0.7, Position = UDim2.fromScale(0.45, 1) },
}

function App.CreateBackdrop(parent: Instance)
	local backdrop: Frame = Create("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = parent,
	})
	for index, glow in GLOWS do
		local gradient = Create("UIGradient", {
			Type = Enum.GradientType.Radial,
		})
		Theme.Bind(gradient, "Transparency", function(palette: Palette.Palette): NumberSequence
			local peak = 1 - palette.GlowOpacity
			return NumberSequence.new({
				NumberSequenceKeypoint.new(0, peak),
				NumberSequenceKeypoint.new(0.45, 1 - palette.GlowOpacity * 0.45),
				NumberSequenceKeypoint.new(1, 1),
			})
		end)
		Create("Frame", {
			Name = `Glow{index}`,
			Size = UDim2.fromScale(glow.Size, glow.Size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = glow.Position,
			Theme = { BackgroundColor3 = glow.Token },
			Children = { Surface.Aspect(1, Enum.DominantAxis.Width), gradient },
			Parent = backdrop,
		})
	end
end

local function IsPublished(): boolean
	return game.GameId ~= 0
end

function App.new(props: AppProps): App
	local context: Context.Context = { Plugin = props.Plugin, Settings = props.Settings }
	local settings = props.Settings
	local currentStore: StoreRef.StoreRef? = nil
	local isCompact = false
	local isShowingEditor = false
	local isAlive = true

	local root: Frame = Create("Frame", {
		Name = "EDSE",
		Size = UDim2.fromScale(1, 1),
		Theme = { BackgroundColor3 = "Background" },
		Parent = props.Widget,
	})
	Tooltip.SetHost(root)
	Dialog.SetHost(root)
	App.CreateBackdrop(root)

	local main: Frame = Create("Frame", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Children = {
			Create("UIPadding", {
				PaddingLeft = UDim.new(0.01, 0),
				PaddingRight = UDim.new(0.01, 0),
				PaddingTop = UDim.new(0.012, 0),
				PaddingBottom = UDim.new(0.006, 0),
			}),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.01, 0),
			}),
		},
		Parent = root,
	})

	local header = Header.new({
		LayoutOrder = 1,
		OnThemeModeChanged = function(mode: Theme.Mode)
			Theme.SetMode(mode)
			settings:SetString(SETTING_THEME_MODE, mode)
		end,
		OnSettings = function()
			Dialogs.Settings(settings)
		end,
		Parent = main,
	})

	-- The store picker's own glass row, used only when the widget is narrow.
	local storeRow = Surface.Raised({
		Name = "StoreRow",
		Size = UDim2.fromScale(1, Header.BAR_HEIGHT_SCALE),
		LayoutOrder = 2,
		CornerScale = 0.24,
		Parent = main,
	})
	storeRow.Root.Visible = false
	local storeRowSlot: Frame = Create("Frame", {
		Name = "Slot",
		Size = UDim2.fromScale(0.98, Header.CONTROL_HEIGHT_SCALE),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = storeRow.Content,
	})

	local body: Frame = Create("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 0.7),
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Children = {
			Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.008, 0),
			}),
		},
		Parent = main,
	})

	local output = OutputPanel.new({ Settings = settings, LayoutOrder = 4, Parent = main })

	-- Optionally echo every message to Studio's own Output window.
	Log.SetMirror(function(entry: Log.Entry)
		if settings:GetBoolean(Dialogs.SETTING_OUTPUT_MIRROR, false) then
			local line = "[EDSE] " .. Log.FormatEntry(entry)
			if entry.Level == "Warning" or entry.Level == "Error" then
				warn(line)
			else
				print(line)
			end
		end
	end)

	local keyList: KeyList.KeyList
	local editor: EntryEditor.EntryEditor

	local function ApplyLayout()
		keyList.Root.Visible = not isCompact or not isShowingEditor
		editor.Root.Visible = not isCompact or isShowingEditor
	end

	local function ShowEditor(show: boolean)
		isShowingEditor = show
		ApplyLayout()
	end

	local function DescribeConnection()
		local store = currentStore
		if not IsPublished() then
			output:SetConnection("Place not published", true)
		elseif store then
			output:SetConnection(StoreRef.Describe(store), false)
		else
			output:SetConnection("No store open", false)
		end
	end

	local function ReportPublishState()
		if IsPublished() then
			Log.Info("Ready. Data stores for this experience are available.")
		else
			Log.Warning(
				"This place isn't published, so it has no data stores yet",
				"Publish it (File → Publish to Roblox), then turn on Game Settings → Security → Enable Studio Access to API Services."
			)
		end
	end

	local storeBar = StoreBar.new({
		Context = context,
		OverlayHost = root,
		OnOpen = function(ref: StoreRef.StoreRef)
			task.spawn(function()
				if not editor:ConfirmDiscard() then
					return
				end
				currentStore = ref
				Log.Info(`Opened {StoreRef.Describe(ref)}`)
				keyList:SetStore(ref)
				editor:SetStore(ref)
				ShowEditor(false)
				DescribeConnection()
			end)
		end,
		Parent = header.StoreSlot,
	})

	local function OpenKey(key: string)
		if editor:GetKey() == key then
			ShowEditor(true)
			return
		end
		task.spawn(function()
			if not editor:ConfirmDiscard() then
				return
			end
			keyList:SetSelectedKey(key)
			editor:Open(key)
			ShowEditor(true)
		end)
	end

	keyList = KeyList.new({
		Context = context,
		LayoutOrder = 1,
		OnOpenKey = OpenKey,
		OnCreateKey = function()
			local store = currentStore
			if store == nil then
				return
			end
			task.spawn(function()
				local request = Dialogs.NewKey(store.IsOrdered, DataStoreGateway.ValidateKey)
				if request == nil or not editor:ConfirmDiscard() then
					return
				end
				keyList:SetSelectedKey(request.Key)
				editor:OpenNew(request.Key, request.Value)
				ShowEditor(true)
			end)
		end,
		OnKeyAction = function(action: KeyList.KeyAction, key: string)
			local store = currentStore
			if store == nil then
				return
			end
			if action == "Favorite" then
				settings:ToggleFavorite(store, key)
				keyList:RefreshSections()
				editor:RefreshChrome()
			elseif action == "Delete" then
				editor:Delete(key)
			end
		end,
		Parent = body,
	})

	editor = EntryEditor.new({
		Context = context,
		LayoutOrder = 2,
		OnBack = function()
			ShowEditor(false)
		end,
		OnKeyLoaded = function()
			keyList:RefreshSections()
		end,
		OnKeySaved = function(key: string, entry)
			local store = currentStore
			keyList:SetKeyValue(key, if store and store.IsOrdered then entry.Value else nil)
			keyList:RefreshSections()
		end,
		OnKeyDeleted = function(key: string)
			local store = currentStore
			if store then
				settings:ForgetKey(store, key)
			end
			keyList:RemoveKey(key)
		end,
		OnFavoritesChanged = function()
			keyList:RefreshSections()
		end,
		Parent = body,
	})

	-- Responsive layout ---------------------------------------------------------
	local isStoreInline: boolean? = nil
	local function UpdateCompact()
		local width = root.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local storeInline = width >= STORE_INLINE_MIN_WIDTH
		if storeInline ~= isStoreInline then
			isStoreInline = storeInline
			header:SetStoreInline(storeInline)
			storeRow.Root.Visible = not storeInline
			storeBar.Root.Parent = if storeInline then header.StoreSlot else storeRowSlot
			storeBar:SetCompact(not storeInline)
		end
		local compact = width < COMPACT_WIDTH
		if compact == isCompact then
			return
		end
		isCompact = compact
		header:SetCompact(compact)
		keyList:SetCompact(compact)
		editor:SetCompact(compact)
		output:SetCompact(compact)
		ApplyLayout()
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateCompact)
	task.defer(UpdateCompact)

	-- Publishing a place mid-session changes its GameId.
	local gameIdConnection = game:GetPropertyChangedSignal("GameId"):Connect(function()
		DescribeConnection()
		ReportPublishState()
	end)

	-- Budget readout ------------------------------------------------------------
	task.spawn(function()
		while isAlive do
			if props.Widget.Enabled then
				output:RefreshBudgets()
			end
			task.wait(BUDGET_REFRESH_SECONDS)
		end
	end)

	ReportPublishState()

	-- Reopen where you left off (one list request).
	local lastStore = settings:GetLastStore()
	if lastStore and IsPublished() then
		Log.Info(`Reopened {StoreRef.Describe(lastStore)} from last time`)
		storeBar:SetStore(lastStore)
		currentStore = lastStore
		keyList:SetStore(lastStore)
		editor:SetStore(lastStore)
	end
	DescribeConnection()
	ApplyLayout()

	return {
		Save = function(_self: App)
			editor:Save()
		end,
		Refresh = function(_self: App)
			editor:Refresh()
		end,
		FocusSearch = function(_self: App)
			if isCompact then
				ShowEditor(false)
			end
			keyList:FocusSearch()
		end,
		ToggleOutput = function(_self: App)
			output:Toggle()
		end,
		Destroy = function(_self: App)
			isAlive = false
			gameIdConnection:Disconnect()
			editor:Destroy()
			Dialog.CloseAll()
			output:Destroy()
			Log.SetMirror(nil)
			Tooltip.Destroy()
			root:Destroy()
		end,
	}
end

return App
