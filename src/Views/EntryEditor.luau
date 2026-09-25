--!strict
--[[
	EntryEditor
	Everything about one open key: loading it, the Tree / JSON / Versions /
	Info tabs (or the number editor for ordered stores), and the actions:
	Save (diff review + conflict-safe write), Revert, Refresh, Delete,
	Export / Import, Favorite, and Live (poll the key and pull in changes
	made by running servers).
]]

local Button = require(script.Parent.Parent.Ui.Components.Button)
local Context = require(script.Parent.Context)
local ContextMenu = require(script.Parent.Parent.Ui.ContextMenu)
local Create = require(script.Parent.Parent.Ui.Create)
local DataStoreGateway = require(script.Parent.Parent.Services.DataStoreGateway)
local Dialog = require(script.Parent.Parent.Ui.Components.Dialog)
local Dialogs = require(script.Parent.Dialogs)
local EntrySession = require(script.Parent.Parent.Core.EntrySession)
local Feedback = require(script.Parent.Parent.Ui.Components.Feedback)
local Format = require(script.Parent.Parent.Core.Format)
local InfoPage = require(script.Parent.Pages.InfoPage)
local JsonPage = require(script.Parent.Pages.JsonPage)
local Label = require(script.Parent.Parent.Ui.Components.Label)
local Log = require(script.Parent.Parent.Services.Log)
local OrderedPage = require(script.Parent.Pages.OrderedPage)
local Segmented = require(script.Parent.Parent.Ui.Components.Segmented)
local Signal = require(script.Parent.Parent.Core.Signal)
local StoreRef = require(script.Parent.Parent.Core.StoreRef)
local Surface = require(script.Parent.Parent.Ui.Surface)
local Theme = require(script.Parent.Parent.Theme.Theme)
local Toggle = require(script.Parent.Parent.Ui.Components.Toggle)
local TreePage = require(script.Parent.Pages.TreePage)
local Typography = require(script.Parent.Parent.Ui.Typography)
local VersionsPage = require(script.Parent.Pages.VersionsPage)

export type EntryEditorProps = {
	Context: Context.Context,
	LayoutOrder: number,
	OnBack: () -> (),
	OnKeyLoaded: (key: string) -> (),
	OnKeySaved: (key: string, entry: EntrySession.Entry) -> (),
	OnKeyDeleted: (key: string) -> (),
	OnFavoritesChanged: () -> (),
	Parent: Instance,
}

export type EntryEditor = {
	Root: Frame,
	SetStore: (self: EntryEditor, ref: StoreRef.StoreRef?) -> (),
	Open: (self: EntryEditor, key: string) -> (),
	OpenNew: (self: EntryEditor, key: string, value: any) -> (),
	Save: (self: EntryEditor) -> (),
	Refresh: (self: EntryEditor) -> (),
	Delete: (self: EntryEditor, key: string?) -> (),
	-- Asks before throwing away unsaved edits. Returns true to proceed.
	ConfirmDiscard: (self: EntryEditor) -> boolean,
	GetKey: (self: EntryEditor) -> string?,
	-- Re-reads favorite state etc. after changes made elsewhere.
	RefreshChrome: (self: EntryEditor) -> (),
	SetCompact: (self: EntryEditor, isCompact: boolean) -> (),
	Destroy: (self: EntryEditor) -> (),
}

type TabName = "Tree" | "Json" | "Versions" | "Info"

local SETTING_LIVE = "LiveWatch"
local DEFAULT_LIVE_INTERVAL_SECONDS = 10

local EntryEditor = {}

function EntryEditor.new(props: EntryEditorProps): EntryEditor
	local settings = props.Context.Settings
	local storeRef: StoreRef.StoreRef? = nil
	local session: EntrySession.EntrySession? = nil
	local sessionConnection: Signal.Connection? = nil
	local openToken = 0
	local isBusy = false
	local activeTab: TabName = "Tree"
	local isLive = settings:GetBoolean(SETTING_LIVE, false)
	local liveToken = 0
	local isCompactLayout = false
	-- Created further down (it needs the live loop); declared here for RefreshChrome.
	local liveToggle: Toggle.Toggle

	local root: Frame = Create("Frame", {
		Name = "EntryEditor",
		Size = UDim2.fromScale(0.68, 1),
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		Children = { Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) },
		Parent = props.Parent,
	})
	local card = Surface.Raised({ Name = "Card", Size = UDim2.fromScale(1, 1), CornerScale = 0.025, Parent = root })
	local column: Frame = Create("Frame", {
		Name = "Column",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Surface.Padding(0.014, 0.016),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.014, 0),
			}),
		},
		Parent = card.Content,
	})

	-- Header -------------------------------------------------------------------
	local header: Frame = Create("Frame", {
		Name = "Header",
		Size = UDim2.fromScale(1, 0.075),
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.01, 0),
			}),
		},
		Parent = column,
	})

	local backButton = Button.new({
		Name = "Back",
		Icon = "Back",
		Tooltip = "Back to keys",
		Variant = "Ghost",
		Square = true,
		Size = UDim2.fromScale(1, 0.78),
		LayoutOrder = 1,
		OnActivated = props.OnBack,
		Parent = header,
	})
	backButton.Root.Visible = false

	local titleBlock: Frame = Create("Frame", {
		Name = "Title",
		Size = UDim2.fromScale(0.3, 1),
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Children = { Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) },
		Parent = header,
	})
	local titleLabel = Label.new({
		Name = "Key",
		Text = "No key open",
		Size = UDim2.fromScale(1, 0.56),
		Font = Typography.FONT_SEMIBOLD,
		Ratio = 0.72,
		MaxTextSize = 15,
		Parent = titleBlock,
	})
	local metaLabel = Label.new({
		Name = "Meta",
		Text = "",
		Size = UDim2.fromScale(1, 0.4),
		Position = UDim2.fromScale(0, 0.58),
		Color = "TextMuted",
		Font = Typography.FONT_MEDIUM,
		Ratio = 0.7,
		MaxTextSize = 12,
		Parent = titleBlock,
	})

	local liveLabel = Label.new({
		Name = "LiveLabel",
		Text = "Live ",
		Size = UDim2.fromScale(0, 0.62),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Typography.FONT_SEMIBOLD,
		Color = "TextSecondary",
		Ratio = 0.62,
		MaxTextSize = 13,
		LayoutOrder = 3,
		Parent = header,
	})

	local function HeaderIcon(name: string, icon: string, tooltip: string, order: number): Button.Button
		return Button.new({
			Name = name,
			Icon = icon,
			Tooltip = tooltip,
			Variant = "Ghost",
			Square = true,
			Size = UDim2.fromScale(1, 0.78),
			LayoutOrder = order,
			Parent = header,
		})
	end
	local favoriteButton = HeaderIcon("Favorite", "Favorite", "Favorite this key", 5)
	local refreshButton = HeaderIcon("Refresh", "Refresh", "Reload from the data store", 6)
	local moreButton = HeaderIcon("More", "More", "Export, import, delete", 7)

	local revertButton = Button.new({
		Name = "Revert",
		Text = "Revert",
		Icon = "Revert",
		Variant = "Ghost",
		Size = UDim2.fromScale(0.11, 0.78),
		LayoutOrder = 8,
		Tooltip = "Discard your edits",
		Parent = header,
	})
	local saveButton = Button.new({
		Name = "Save",
		Text = "Save",
		Icon = "Save",
		Variant = "Primary",
		Size = UDim2.fromScale(0.13, 0.78),
		LayoutOrder = 9,
		Tooltip = "Write your changes to the live data store",
		Parent = header,
	})

	-- Tabs + status -----------------------------------------------------------
	local tabRow: Frame = Create("Frame", {
		Name = "TabRow",
		Size = UDim2.fromScale(1, 0.058),
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.02, 0),
			}),
		},
		Parent = column,
	})
	local SelectTab: (tab: TabName) -> ()
	local tabs = Segmented.new({
		Name = "Tabs",
		Options = {
			{ Value = "Tree", Label = "Tree" },
			{ Value = "Json", Label = "JSON" },
			{ Value = "Versions", Label = "Versions" },
			{ Value = "Info", Label = "Info" },
		},
		Value = "Tree",
		Size = UDim2.fromScale(0.6, 1),
		LayoutOrder = 1,
		OnChanged = function(value: string)
			SelectTab(value :: TabName)
		end,
		Parent = tabRow,
	})
	local dirtyLabel = Label.new({
		Name = "Dirty",
		Text = "",
		Size = UDim2.fromScale(0.3, 1),
		Font = Typography.FONT_SEMIBOLD,
		Color = "Warning",
		XAlignment = Enum.TextXAlignment.Right,
		Ratio = 0.42,
		MaxTextSize = 13,
		LayoutOrder = 2,
		Parent = tabRow,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = dirtyLabel })

	-- Banner (live changes, missing key) ---------------------------------------
	local banner: Frame = Create("Frame", {
		Name = "Banner",
		Size = UDim2.fromScale(1, 0.058),
		LayoutOrder = 3,
		Visible = false,
		BackgroundTransparency = 0.88,
		Theme = { BackgroundColor3 = "Warning" },
		Children = {
			Create("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
			Surface.Padding(0.015, 0.12),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.012, 0),
			}),
		},
		Parent = column,
	})
	local bannerText = Label.new({
		Name = "Text",
		Text = "",
		Size = UDim2.fromScale(0.6, 1),
		Font = Typography.FONT_MEDIUM,
		Color = "Warning",
		Ratio = 0.5,
		MaxTextSize = 13,
		LayoutOrder = 1,
		Parent = banner,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = bannerText })
	local bannerAction = Button.new({
		Name = "Action",
		Text = "Reload",
		Variant = "Primary",
		Size = UDim2.fromScale(0.16, 1),
		LayoutOrder = 2,
		Parent = banner,
	})
	local bannerDismiss = Button.new({
		Name = "Dismiss",
		Icon = "Close",
		Variant = "Ghost",
		Square = true,
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = 3,
		Parent = banner,
	})
	local bannerHandler: (() -> ())? = nil

	local function ShowBanner(text: string, actionText: string, onAction: () -> ())
		bannerText.Text = text
		bannerAction:SetText(actionText)
		bannerHandler = onAction
		banner.Visible = true
	end
	local function HideBanner()
		banner.Visible = false
		bannerHandler = nil
	end
	bannerAction.Activated:Connect(function()
		local handler = bannerHandler
		HideBanner()
		if handler then
			handler()
		end
	end)
	bannerDismiss.Activated:Connect(HideBanner)

	-- Pages -------------------------------------------------------------------
	local pageHost: Frame = Create("Frame", {
		Name = "Pages",
		Size = UDim2.fromScale(1, 0.8),
		LayoutOrder = 4,
		BackgroundTransparency = 1,
		Children = { Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) },
		Parent = column,
	})
	local function PageFrame(name: string): Frame
		return Create("Frame", {
			Name = name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = pageHost,
		})
	end
	local pageFrames: { [string]: Frame } = {
		Tree = PageFrame("Tree"),
		Json = PageFrame("Json"),
		Versions = PageFrame("Versions"),
		Info = PageFrame("Info"),
		Ordered = PageFrame("Ordered"),
	}
	local treePage = TreePage.new({ Context = props.Context, Parent = pageFrames.Tree })
	local jsonPage = JsonPage.new({ Parent = pageFrames.Json })
	local versionsPage = VersionsPage.new({ Parent = pageFrames.Versions })
	local infoPage = InfoPage.new({ Parent = pageFrames.Info })
	local orderedPage = OrderedPage.new({ Parent = pageFrames.Ordered })

	local stateFrame: Frame = Create("Frame", {
		Name = "State",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = pageHost,
	})
	local emptyState = Feedback.EmptyState({
		Icon = "Key",
		Title = "No key open",
		Body = "Pick a key on the left, or type one in the search box and press Enter.",
		Parent = stateFrame,
	})
	local loadingDots: Frame? = nil

	local function ShowState(title: string?, body: string?, isLoading: boolean?)
		if loadingDots then
			loadingDots:Destroy()
			loadingDots = nil
		end
		if title == nil and not isLoading then
			stateFrame.Visible = false
			return
		end
		stateFrame.Visible = true
		emptyState.Root.Visible = not isLoading
		if isLoading then
			local dots = Feedback.LoadingDots(UDim2.fromScale(0.3, 0.08), stateFrame)
			dots.AnchorPoint = Vector2.new(0.5, 0.5)
			dots.Position = UDim2.fromScale(0.5, 0.45)
			loadingDots = dots
		else
			emptyState:Set(title :: string, body)
		end
	end

	-- State rendering -----------------------------------------------------------
	local function IsOrderedSession(): boolean
		local current = session
		return current ~= nil and current.StoreRef.IsOrdered
	end

	local function RefreshChrome()
		local current = session
		local hasSession = current ~= nil
		local isDirty = current ~= nil and current:IsDirty()
		local hasErrors = jsonPage:IsInvalid() or infoPage:IsInvalid()

		titleLabel.Text = if current then current.Key else "No key open"
		if current then
			local original = current.Original
			local parts: { string } = { StoreRef.Describe(current.StoreRef) }
			if not original.Exists then
				table.insert(parts, "new key")
			end
			if original.UpdatedTime then
				table.insert(
					parts,
					`updated {Format.RelativeTime(original.UpdatedTime, DateTime.now().UnixTimestampMillis)}`
				)
			end
			local size = Format.EncodedSize(current.Draft.Value)
			if size then
				table.insert(parts, Format.Bytes(size))
			end
			metaLabel.Text = table.concat(parts, "  ·  ")
		else
			metaLabel.Text = ""
		end

		dirtyLabel.Text = if hasErrors then "Fix errors to save" elseif isDirty then "Unsaved changes" else ""
		saveButton:SetEnabled(hasSession and not isBusy and (isDirty or not (current :: any).Original.Exists))
		revertButton.Root.Visible = isDirty
		for _, button in { favoriteButton, refreshButton, moreButton } do
			button:SetEnabled(hasSession and not isBusy)
		end
		local isFavorite = current ~= nil and settings:IsFavorite(current.StoreRef, current.Key)
		favoriteButton:SetIcon(if isFavorite then "FavoriteFilled" else "Favorite")
		favoriteButton:SetSelected(isFavorite)
		tabs.Root.Visible = hasSession and not IsOrderedSession()
		liveLabel.Visible = hasSession and not isCompactLayout
		liveToggle.Root.Visible = hasSession
	end

	function SelectTab(tab: TabName)
		activeTab = tab
		local isOrdered = IsOrderedSession()
		for name, frame in pageFrames do
			frame.Visible = if isOrdered then name == "Ordered" else name == tab
		end
		if tab == "Versions" and not isOrdered then
			versionsPage:Activate()
		end
	end

	local function AttachSession(newSession: EntrySession.EntrySession?)
		if sessionConnection then
			sessionConnection:Disconnect()
			sessionConnection = nil
		end
		local previous = session
		if previous and previous ~= newSession then
			previous:Destroy()
		end
		session = newSession
		HideBanner()
		if newSession then
			sessionConnection = newSession.Changed:Connect(function()
				RefreshChrome()
			end)
		end
		local isOrdered = newSession ~= nil and newSession.StoreRef.IsOrdered
		treePage:SetSession(if isOrdered then nil else newSession)
		jsonPage:SetSession(if isOrdered then nil else newSession)
		versionsPage:SetSession(if isOrdered then nil else newSession)
		infoPage:SetSession(if isOrdered then nil else newSession)
		orderedPage:SetSession(if isOrdered then newSession else nil)
		SelectTab(activeTab)
		RefreshChrome()
	end

	jsonPage.InvalidChanged:Connect(RefreshChrome)
	infoPage.InvalidChanged:Connect(RefreshChrome)

	local function ShowMissingKeyBanner(current: EntrySession.EntrySession)
		if current.Original.Exists or current.Draft.Value ~= nil then
			return
		end
		ShowBanner(
			"This key doesn't exist yet. Give it a value and Save to create it.",
			if current.StoreRef.IsOrdered then "Start at 0" else "Start as { }",
			function()
				if session == current then
					current:SetValue(if current.StoreRef.IsOrdered then 0 else {}, "Banner")
				end
			end
		)
	end

	-- Loading ------------------------------------------------------------------
	local LogLoaded: (key: string, entry: EntrySession.Entry) -> ()

	local function DescribeEntry(entry: EntrySession.Entry): string
		local parts: { string } = {}
		if entry.Version then
			table.insert(parts, `version {entry.Version}`)
		end
		local size = Format.EncodedSize(entry.Value)
		if size then
			table.insert(parts, Format.Bytes(size))
		end
		if #entry.UserIds > 0 then
			table.insert(parts, Format.Plural(#entry.UserIds, "user ID"))
		end
		return table.concat(parts, " · ")
	end

	function LogLoaded(key: string, entry: EntrySession.Entry)
		if entry.Exists then
			Log.Info(`Loaded "{key}"`, DescribeEntry(entry))
		else
			Log.Info(`"{key}" doesn't exist yet`, "Give it a value and Save to create it.")
		end
	end

	local function Load(key: string)
		local currentStore = storeRef
		if currentStore == nil then
			return
		end
		openToken += 1
		local token = openToken
		AttachSession(nil)
		titleLabel.Text = key
		metaLabel.Text = "Loading…"
		ShowState(nil, nil, true)

		local result = DataStoreGateway.ReadEntry(currentStore, key)
		if token ~= openToken then
			return
		end
		if not result.Ok then
			ShowState("Couldn't load this key", result.Error.Hint or result.Error.Message)
			metaLabel.Text = ""
			Log.Failure(`Couldn't load "{key}" from {StoreRef.Describe(currentStore)}`, result.Error)
			return
		end
		ShowState(nil)
		LogLoaded(key, result.Value)
		local newSession = EntrySession.new(currentStore, key, result.Value)
		AttachSession(newSession)
		settings:RememberKey(currentStore, key)
		ShowMissingKeyBanner(newSession)
		props.OnKeyLoaded(key)
	end

	-- Live watch ------------------------------------------------------------------
	local function LiveInterval(): number
		local seconds =
			tonumber(settings:GetString(Dialogs.SETTING_LIVE_INTERVAL, tostring(DEFAULT_LIVE_INTERVAL_SECONDS)))
		return seconds or DEFAULT_LIVE_INTERVAL_SECONDS
	end

	local function HasRemoteChange(current: EntrySession.EntrySession, latest: EntrySession.Entry): boolean
		if current.StoreRef.IsOrdered then
			return latest.Value ~= current.Original.Value
		end
		return latest.Version ~= current.Original.Version
	end

	local function StartLiveLoop()
		liveToken += 1
		local token = liveToken
		-- The remote version we already told the user about, so a dismissed
		-- banner doesn't reappear on every poll for the same change.
		local notifiedMarker: string? = nil
		task.spawn(function()
			while token == liveToken do
				task.wait(LiveInterval())
				local current = session
				if token ~= liveToken or current == nil or isBusy or Dialog.IsOpen() then
					continue
				end
				local result = DataStoreGateway.ReadEntry(current.StoreRef, current.Key)
				if token ~= liveToken or session ~= current or not result.Ok then
					continue
				end
				local latest = result.Value
				if not HasRemoteChange(current, latest) then
					continue
				end
				if current:IsDirty() then
					local marker = latest.Version or tostring(latest.Value)
					if marker == notifiedMarker then
						continue
					end
					notifiedMarker = marker
					Log.Warning(
						`"{current.Key}" changed on a live server while you have unsaved edits`,
						"Saving now would stop with a conflict. Reload to start from the latest value."
					)
					ShowBanner("Changed on a live server. Saving now would conflict.", "Reload", function()
						if session == current then
							current:Reset(latest, "Live")
						end
					end)
				else
					current:Reset(latest, "Live")
					Log.Info(`"{current.Key}" was updated by a live server`, DescribeEntry(latest))
				end
			end
		end)
	end

	local function UpdateLiveLabel()
		liveLabel.Text = "Live "
		Theme.Bind(liveLabel, "TextColor3", if isLive then "Success" else "TextSecondary")
	end

	liveToggle = Toggle.new({
		Name = "LiveToggle",
		Size = UDim2.fromScale(1, 0.56),
		LayoutOrder = 4,
		IsOn = isLive,
		Tooltip = "Live: re-check this key every few seconds and pull in changes from running servers",
		OnChanged = function(isOn: boolean)
			isLive = isOn
			settings:SetBoolean(SETTING_LIVE, isOn)
			UpdateLiveLabel()
			if isOn then
				StartLiveLoop()
			else
				liveToken += 1
			end
		end,
		Parent = header,
	})

	-- Actions -----------------------------------------------------------------------
	local editor: EntryEditor

	local function Write(current: EntrySession.EntrySession, force: boolean)
		isBusy = true
		saveButton:SetBusy(true, "Saving…")
		RefreshChrome()
		local result =
			DataStoreGateway.WriteEntry(current.StoreRef, current.Key, current.Draft, current.Original, force)
		isBusy = false
		saveButton:SetBusy(false)
		if session ~= current then
			return
		end
		if not result.Ok then
			Log.Failure(`Couldn't save "{current.Key}"`, result.Error)
			RefreshChrome()
			return
		end
		local outcome = result.Value
		if outcome.Conflict then
			Log.Warning(
				`Save stopped: "{current.Key}" changed on a live server after you loaded it`,
				"Nothing was written. Reload to get the latest value, or overwrite it with your version."
			)
			RefreshChrome()
			local choice = Dialogs.ResolveConflict(current.Key)
			if choice == "Reload" then
				Load(current.Key)
			elseif choice == "Overwrite" then
				Log.Warning(`Overwriting "{current.Key}" with your version`)
				Write(current, true)
			end
			return
		end
		local saved = outcome.Entry :: EntrySession.Entry
		local changes = current:GetChanges()
		local changeCount = #changes.Value + #changes.Metadata + (if changes.UserIdsChanged then 1 else 0)
		current:Reset(saved, "Save")
		HideBanner()
		Log.Success(`Saved "{current.Key}"`, `{Format.Plural(changeCount, "change")} written · {DescribeEntry(saved)}`)
		props.OnKeySaved(current.Key, saved)
	end

	local function Save()
		local current = session
		if current == nil or isBusy then
			return
		end
		if jsonPage:IsInvalid() then
			tabs:SetValue("Json", true)
			SelectTab("Json")
			Log.Warning("Save blocked: the JSON has errors", "The JSON tab shows the line and column.")
			return
		end
		if infoPage:IsInvalid() then
			tabs:SetValue("Info", true)
			SelectTab("Info")
			Log.Warning("Save blocked: the metadata isn't a valid JSON object", "Fix it in the Info tab.")
			return
		end
		if not current:IsDirty() and current.Original.Exists then
			Log.Info(`No changes to save in "{current.Key}"`)
			return
		end
		local problem = DataStoreGateway.ValidateDraft(current.StoreRef, current.Draft)
		if problem then
			Log.Warning(`Can't save "{current.Key}"`, problem)
			return
		end
		if settings:GetBoolean(Dialogs.SETTING_CONFIRM_SAVES, true) and not Dialogs.ConfirmSave(current) then
			return
		end
		if session == current then
			Write(current, false)
		end
	end

	local function Delete(key: string?)
		local currentStore = storeRef
		local targetKey = key or (if session then (session :: EntrySession.EntrySession).Key else nil)
		if currentStore == nil or targetKey == nil or isBusy then
			return
		end
		local recoverable = if currentStore.IsOrdered
			then "Ordered data stores keep no history, so this can't be undone."
			else "Its previous versions stay available under Versions for a while (about 30 days), so you can restore it."
		if
			not Dialog.Confirm({
				Title = `Delete "{targetKey}"?`,
				Message = `This removes the key from the live data store. {recoverable}`,
				ConfirmText = "Delete",
				IsDanger = true,
			})
		then
			return
		end
		isBusy = true
		RefreshChrome()
		local result = DataStoreGateway.RemoveEntry(currentStore, targetKey)
		isBusy = false
		if not result.Ok then
			Log.Failure(`Couldn't delete "{targetKey}"`, result.Error)
			RefreshChrome()
			return
		end
		Log.Success(
			`Deleted "{targetKey}"`,
			if currentStore.IsOrdered
				then nil
				else "Earlier versions remain under Versions for a while if you need them."
		)
		props.OnKeyDeleted(targetKey)
		local current = session
		if current and current.Key == targetKey then
			Load(targetKey)
		end
	end

	saveButton.Activated:Connect(Save)
	revertButton.Activated:Connect(function()
		local current = session
		if current then
			current:Revert()
			HideBanner()
			ShowMissingKeyBanner(current)
		end
	end)
	refreshButton.Activated:Connect(function()
		editor:Refresh()
	end)
	favoriteButton.Activated:Connect(function()
		local current = session
		if current then
			local isFavorite = settings:ToggleFavorite(current.StoreRef, current.Key)
			Log.Info(
				if isFavorite then `Added "{current.Key}" to favorites` else `Removed "{current.Key}" from favorites`
			)
			RefreshChrome()
			props.OnFavoritesChanged()
		end
	end)
	moreButton.Activated:Connect(function()
		local current = session
		if current == nil then
			return
		end
		local choice = ContextMenu.Show(props.Context.Plugin, {
			{ Id = "Export", Text = "Export JSON…" },
			{ Id = "Import", Text = "Import JSON…" },
			ContextMenu.SEPARATOR,
			{ Id = "Delete", Text = "Delete key…" },
		})
		if choice == "Export" then
			Log.Info(`Exported "{current.Key}"`)
			Dialogs.Export(current)
		elseif choice == "Import" then
			local ok, value = Dialogs.Import(current.Key)
			if ok and session == current then
				current:SetValue(value, "Import")
				Log.Info(`Imported JSON into "{current.Key}"`, "It's in the editor as a draft. Save to write it.")
			end
		elseif choice == "Delete" then
			Delete(current.Key)
		end
	end)

	editor = {
		Root = root,

		SetStore = function(_self: EntryEditor, ref: StoreRef.StoreRef?)
			storeRef = ref
			openToken += 1
			AttachSession(nil)
			if ref == nil then
				ShowState("No data store open", "Type a data store name above and press Open.")
			else
				ShowState("No key open", "Pick a key on the left, or type one in the search box and press Enter.")
			end
		end,

		Open = function(_self: EntryEditor, key: string)
			task.spawn(Load, key)
		end,

		OpenNew = function(_self: EntryEditor, key: string, value: any)
			local currentStore = storeRef
			if currentStore == nil then
				return
			end
			openToken += 1
			ShowState(nil)
			local newSession = EntrySession.new(currentStore, key, EntrySession.EmptyEntry())
			AttachSession(newSession)
			newSession:SetValue(value, "New")
			tabs:SetValue("Tree", false)
			SelectTab("Tree")
			Log.Info(`New key "{key}" in {StoreRef.Describe(currentStore)}`, "Not saved yet. Save to create it.")
		end,

		Save = function(_self: EntryEditor)
			task.spawn(Save)
		end,

		Refresh = function(self: EntryEditor)
			local current = session
			if current == nil then
				return
			end
			task.spawn(function()
				if self:ConfirmDiscard() and session == current then
					Load(current.Key)
				end
			end)
		end,

		Delete = function(_self: EntryEditor, key: string?)
			task.spawn(Delete, key)
		end,

		ConfirmDiscard = function(_self: EntryEditor): boolean
			local current = session
			if current == nil or not current:IsDirty() then
				return true
			end
			return Dialog.Confirm({
				Title = "Discard unsaved changes?",
				Message = `Your edits to "{current.Key}" haven't been saved.`,
				ConfirmText = "Discard",
				IsDanger = true,
			})
		end,

		GetKey = function(_self: EntryEditor): string?
			return if session then (session :: EntrySession.EntrySession).Key else nil
		end,

		RefreshChrome = function(_self: EntryEditor)
			RefreshChrome()
		end,

		SetCompact = function(_self: EntryEditor, isCompact: boolean)
			backButton.Root.Visible = isCompact
			isCompactLayout = isCompact
			RefreshChrome()
			versionsPage:SetCompact(isCompact)
		end,

		Destroy = function(_self: EntryEditor)
			liveToken += 1
			openToken += 1
			AttachSession(nil)
		end,
	}

	UpdateLiveLabel()
	if isLive then
		StartLiveLoop()
	end
	editor:SetStore(nil)
	return editor
end

return EntryEditor
