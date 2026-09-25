--!strict
--[[
	KeyList
	The sidebar of keys in the open store.

	  * With an empty search: Favorites, then Recent, then every key (paged in
	    automatically as you scroll).
	  * Typing searches by prefix on the server (standard stores), debounced.
	  * Enter opens exactly what you typed, even if listing hasn't caught up
	    (key listings are eventually consistent).
	  * Ordered stores list by value, highest first (toggle to lowest first).
]]

local Button = require(script.Parent.Parent.Ui.Components.Button)
local Context = require(script.Parent.Context)
local ContextMenu = require(script.Parent.Parent.Ui.ContextMenu)
local Create = require(script.Parent.Parent.Ui.Create)
local DataStoreGateway = require(script.Parent.Parent.Services.DataStoreGateway)
local Format = require(script.Parent.Parent.Core.Format)
local Icon = require(script.Parent.Parent.Ui.Components.Icon)
local Label = require(script.Parent.Parent.Ui.Components.Label)
local Log = require(script.Parent.Parent.Services.Log)
local Motion = require(script.Parent.Parent.Ui.Motion)
local Segmented = require(script.Parent.Parent.Ui.Components.Segmented)
local StoreRef = require(script.Parent.Parent.Core.StoreRef)
local Surface = require(script.Parent.Parent.Ui.Surface)
local TextField = require(script.Parent.Parent.Ui.Components.TextField)
local Theme = require(script.Parent.Parent.Theme.Theme)
local Typography = require(script.Parent.Parent.Ui.Typography)
local VirtualList = require(script.Parent.Parent.Ui.Components.VirtualList)

export type KeyAction = "Favorite" | "Delete"

export type KeyListProps = {
	Context: Context.Context,
	LayoutOrder: number,
	OnOpenKey: (key: string) -> (),
	OnCreateKey: () -> (),
	OnKeyAction: (action: KeyAction, key: string) -> (),
	Parent: Instance,
}

export type KeyList = {
	Root: Frame,
	SetStore: (self: KeyList, ref: StoreRef.StoreRef?) -> (),
	SetSelectedKey: (self: KeyList, key: string?) -> (),
	Reload: (self: KeyList) -> (),
	FocusSearch: (self: KeyList) -> (),
	RefreshSections: (self: KeyList) -> (),
	RemoveKey: (self: KeyList, key: string) -> (),
	SetKeyValue: (self: KeyList, key: string, value: number?) -> (),
	SetCompact: (self: KeyList, isCompact: boolean) -> (),
}

type ItemKind = "Header" | "Key" | "OpenExact" | "Status"
type Item = {
	Kind: ItemKind,
	Text: string,
	Value: number?,
	Section: string?,
}

local SEARCH_DEBOUNCE_SECONDS = 0.35
local TARGET_ROW_HEIGHT = 26

local KeyList = {}

function KeyList.new(props: KeyListProps): KeyList
	local settings = props.Context.Settings
	local storeRef: StoreRef.StoreRef? = nil
	local selectedKey: string? = nil
	local searchText = ""
	local isAscending = false

	local loadedKeys: { { Key: string, Value: number? } } = {}
	local pager: DataStoreGateway.Pager<DataStoreGateway.KeyListing>? = nil
	local isLoading = false
	local loadError: DataStoreGateway.GatewayError? = nil
	local loadToken = 0
	local searchToken = 0

	local root: Frame = Create("Frame", {
		Name = "KeyList",
		Size = UDim2.fromScale(0.27, 1),
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		Parent = props.Parent,
	})
	local card = Surface.Raised({ Name = "Card", Size = UDim2.fromScale(1, 1), CornerScale = 0.035, Parent = root })
	local column: Frame = Create("Frame", {
		Name = "Column",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Surface.Padding(0.03, 0.014),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.012, 0),
			}),
		},
		Parent = card.Content,
	})

	local list: VirtualList.VirtualList
	local Rebuild: () -> ()
	local LoadNextPage: () -> ()
	local Reload: () -> ()

	local searchField = TextField.new({
		Name = "Search",
		Size = UDim2.fromScale(1, 0.06),
		LayoutOrder = 1,
		Icon = "Search",
		Placeholder = "Search keys",
		ShowClearButton = true,
		OnChanged = function(text: string)
			-- Programmatic resets (SetStore) already reloaded; don't do it twice.
			if text == searchText then
				return
			end
			searchText = text
			searchToken += 1
			local token = searchToken
			task.delay(SEARCH_DEBOUNCE_SECONDS, function()
				if token ~= searchToken then
					return
				end
				if storeRef and not storeRef.IsOrdered then
					Reload()
				else
					Rebuild()
				end
			end)
		end,
		OnSubmit = function(text: string)
			local key = string.match(text, "^%s*(.-)%s*$") :: string
			if key ~= "" and storeRef then
				props.OnOpenKey(key)
			end
		end,
		Parent = column,
	})

	-- Toolbar: count, sort (ordered only), refresh, new key.
	local toolbar: Frame = Create("Frame", {
		Name = "Toolbar",
		Size = UDim2.fromScale(1, 0.05),
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.025, 0),
			}),
		},
		Parent = column,
	})
	local countLabel = Label.new({
		Name = "Count",
		Text = "",
		Size = UDim2.fromScale(0.4, 0.8),
		Color = "TextMuted",
		Font = Typography.FONT_MEDIUM,
		Ratio = 0.62,
		MaxTextSize = 13,
		LayoutOrder = 1,
		Parent = toolbar,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = countLabel })

	local sortSwitch = Segmented.new({
		Name = "Sort",
		Options = {
			{ Value = "Desc", Label = "High", Tooltip = "Highest values first" },
			{ Value = "Asc", Label = "Low", Tooltip = "Lowest values first" },
		},
		Value = "Desc",
		Size = UDim2.fromScale(0.34, 1),
		LayoutOrder = 2,
		OnChanged = function(value: string)
			isAscending = value == "Asc"
			Reload()
		end,
		Parent = toolbar,
	})
	sortSwitch.Root.Visible = false

	local refreshButton = Button.new({
		Name = "Reload",
		Icon = "Refresh",
		Tooltip = "Reload keys",
		Variant = "Ghost",
		Square = true,
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = 3,
		Parent = toolbar,
	})
	local newKeyButton = Button.new({
		Name = "NewKey",
		Icon = "Add",
		Tooltip = "New key",
		Variant = "Ghost",
		Square = true,
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = 4,
		OnActivated = props.OnCreateKey,
		Parent = toolbar,
	})

	-- Rows -----------------------------------------------------------------
	type Row = {
		Root: TextButton,
		Selection: Frame,
		Hover: Frame,
		Icon: Icon.Icon,
		Text: TextLabel,
		Value: TextLabel,
		Item: Item?,
	}

	local function CreateRow(): Row
		local rowButton: TextButton = Create("TextButton", {
			Name = "Row",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
		})
		local selection: Frame = Create("Frame", {
			Name = "Selection",
			Size = UDim2.fromScale(1, 0.88),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "Selection" },
			Children = { Create("UICorner", { CornerRadius = UDim.new(0.3, 0) }) },
			Parent = rowButton,
		})
		local hover: Frame = Create("Frame", {
			Name = "Hover",
			Size = selection.Size,
			AnchorPoint = selection.AnchorPoint,
			Position = selection.Position,
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "Hover" },
			Children = { Create("UICorner", { CornerRadius = UDim.new(0.3, 0) }) },
			Parent = rowButton,
		})
		local content: Frame = Create("Frame", {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Children = {
				Surface.Padding(0.03, 0),
				Create("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0.025, 0),
				}),
			},
			Parent = rowButton,
		})
		local icon = Icon.new({ Name = "Recent", Size = UDim2.fromScale(1, 0.5), LayoutOrder = 1, Parent = content })
		local text = Label.new({
			Name = "Text",
			Text = "",
			Size = UDim2.fromScale(0.6, 1),
			Font = Typography.FONT_MEDIUM,
			Ratio = 0.5,
			MaxTextSize = 13,
			LayoutOrder = 2,
			Parent = content,
		})
		Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = text })
		local value = Label.new({
			Name = "Value",
			Text = "",
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Typography.FONT_MONO,
			Color = "TextSecondary",
			Ratio = 0.42,
			MaxTextSize = 13,
			XAlignment = Enum.TextXAlignment.Right,
			LayoutOrder = 3,
			Parent = content,
		})

		local row: Row = {
			Root = rowButton,
			Selection = selection,
			Hover = hover,
			Icon = icon,
			Text = text,
			Value = value,
			Item = nil,
		}

		rowButton.MouseEnter:Connect(function()
			local item = row.Item
			if item and item.Kind ~= "Header" and item.Kind ~= "Status" then
				Motion.Tween(hover, Motion.FAST, { BackgroundTransparency = 1 - Theme.Current().HoverOpacity * 1.5 })
			end
		end)
		rowButton.MouseLeave:Connect(function()
			Motion.Tween(hover, Motion.FAST, { BackgroundTransparency = 1 })
		end)
		rowButton.Activated:Connect(function()
			local item = row.Item
			if item and (item.Kind == "Key" or item.Kind == "OpenExact") then
				props.OnOpenKey(item.Text)
			end
		end)
		rowButton.MouseButton2Click:Connect(function()
			local item = row.Item
			local currentStore = storeRef
			if item == nil or item.Kind ~= "Key" or currentStore == nil then
				return
			end
			local isFavorite = settings:IsFavorite(currentStore, item.Text)
			local choice = ContextMenu.Show(props.Context.Plugin, {
				{ Id = "Open", Text = "Open" },
				{ Id = "Favorite", Text = if isFavorite then "Remove from favorites" else "Add to favorites" },
				ContextMenu.SEPARATOR,
				{ Id = "Delete", Text = "Delete key…" },
			})
			if choice == "Open" then
				props.OnOpenKey(item.Text)
			elseif choice == "Favorite" or choice == "Delete" then
				props.OnKeyAction(choice :: KeyAction, item.Text)
			end
		end)
		return row
	end

	local function UpdateRow(row: Row, item: Item, _index: number)
		row.Item = item
		row.Hover.BackgroundTransparency = 1
		local isHeader = item.Kind == "Header"
		local isStatus = item.Kind == "Status"
		local isSelected = item.Kind == "Key" and item.Text == selectedKey

		row.Selection.BackgroundTransparency = if isSelected then 1 - Theme.Current().SelectionOpacity else 1
		-- Plain keys stay icon-free for a clean list; only special rows get one.
		local isPlainKey = item.Kind == "Key" and item.Section == "All"
		row.Icon.Root.Visible = not isHeader and not isStatus and not isPlainKey
		if item.Kind == "OpenExact" then
			row.Icon:SetIcon("Caret")
			row.Icon:SetColor("Accent")
			row.Text.Text = `Open "{item.Text}"`
		elseif item.Kind == "Key" then
			if not isPlainKey then
				local isFavorite = item.Section == "Favorites"
				row.Icon:SetIcon(if isFavorite then "FavoriteFilled" else "Recent")
				row.Icon:SetColor(if isSelected then "Accent" elseif isFavorite then "Warning" else "TextMuted")
			end
			row.Text.Text = item.Text
		else
			row.Text.Text = if isHeader then string.upper(item.Text) else item.Text
		end

		Theme.Bind(
			row.Text,
			"TextColor3",
			if isHeader or isStatus then "TextMuted" elseif isSelected then "Accent" else "TextPrimary"
		)
		row.Text.FontFace = if isHeader then Typography.FONT_BOLD else Typography.FONT_MEDIUM
		row.Value.Text = if item.Value ~= nil then Format.Preview(item.Value) else ""
		row.Value.Visible = item.Value ~= nil
	end

	list = VirtualList.new({
		Name = "Keys",
		Size = UDim2.fromScale(1, 0.8),
		LayoutOrder = 3,
		TargetRowHeight = TARGET_ROW_HEIGHT,
		CreateRow = CreateRow :: any,
		UpdateRow = UpdateRow :: any,
		Parent = column,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = list.Root })

	local function UpdateCount()
		local currentStore = storeRef
		if currentStore == nil then
			countLabel.Text = ""
			return
		end
		local suffix = if pager and not pager:IsFinished() then "+" else ""
		countLabel.Text = `{Format.Plural(#loadedKeys, "key")}{suffix}`
	end

	function Rebuild()
		local items: { Item } = {}
		local currentStore = storeRef
		if currentStore == nil then
			table.insert(items, { Kind = "Status", Text = "Open a data store to list its keys." })
			list:SetItems(items, true)
			UpdateCount()
			return
		end

		local trimmedSearch = string.match(searchText, "^%s*(.-)%s*$") :: string
		local loweredSearch = string.lower(trimmedSearch)
		local shown: { [string]: boolean } = {}

		if trimmedSearch ~= "" then
			table.insert(items, { Kind = "OpenExact", Text = trimmedSearch })
		else
			for _, section in { "Favorites", "Recent" } do
				local keys: { string } = if section == "Favorites"
					then settings:GetFavorites(currentStore)
					else settings:GetRecentKeys(currentStore)
				local sectionItems: { Item } = {}
				for _, key in keys do
					if not shown[key] then
						shown[key] = true
						table.insert(sectionItems, { Kind = "Key", Text = key, Section = section })
					end
				end
				if #sectionItems > 0 then
					table.insert(items, { Kind = "Header", Text = section })
					table.move(sectionItems, 1, #sectionItems, #items + 1, items)
				end
			end
			if #items > 0 then
				table.insert(
					items,
					{ Kind = "Header", Text = if currentStore.IsOrdered then "By value" else "All keys" }
				)
			end
		end

		for _, listing in loadedKeys do
			-- Ordered stores can't search by prefix on the server; filter here.
			local matches = trimmedSearch == ""
				or not currentStore.IsOrdered
				or string.find(string.lower(listing.Key), loweredSearch, 1, true) ~= nil
			if matches then
				table.insert(items, { Kind = "Key", Text = listing.Key, Value = listing.Value, Section = "All" })
			end
		end

		if isLoading then
			table.insert(items, { Kind = "Status", Text = "Loading…" })
		elseif loadError then
			table.insert(items, { Kind = "Status", Text = loadError.Hint or loadError.Message })
		elseif #loadedKeys == 0 then
			table.insert(items, {
				Kind = "Status",
				Text = if trimmedSearch ~= "" then "No keys with this prefix." else "This store has no keys yet.",
			})
		end

		list:SetItems(items, true)
		UpdateCount()
	end

	function LoadNextPage()
		local currentPager = pager
		if currentPager == nil or isLoading or currentPager:IsFinished() then
			return
		end
		isLoading = true
		loadError = nil
		Rebuild()
		local token = loadToken
		local result = currentPager:LoadNext()
		if token ~= loadToken then
			return -- store or search changed while loading
		end
		isLoading = false
		local currentStore = storeRef
		local storeName = if currentStore then StoreRef.Describe(currentStore) else "the store"
		if result.Ok then
			local isFirstPage = #loadedKeys == 0
			for _, listing in result.Value do
				table.insert(loadedKeys, { Key = listing.Key, Value = listing.Value })
			end
			-- Log once per listing (not every page scrolled in) to keep the log readable.
			if isFirstPage then
				local prefix = string.match(searchText, "^%s*(.-)%s*$") :: string
				local filter = if prefix ~= ""
						and currentStore
						and not currentStore.IsOrdered
					then ` starting with "{prefix}"`
					else ""
				local more = if currentPager:IsFinished() then "" else " (more load as you scroll)"
				Log.Info(`Listed {Format.Plural(#result.Value, "key")}{filter} in {storeName}{more}`)
			end
		else
			loadError = result.Error
			Log.Failure(`Couldn't list keys in {storeName}`, result.Error)
		end
		Rebuild()
	end

	function Reload()
		loadToken += 1
		loadedKeys = {}
		loadError = nil
		isLoading = false
		local currentStore = storeRef
		if currentStore == nil then
			pager = nil
			Rebuild()
			return
		end
		local prefix = if currentStore.IsOrdered then "" else string.match(searchText, "^%s*(.-)%s*$") :: string
		pager = DataStoreGateway.ListKeys(currentStore, prefix, isAscending)
		list:SetItems({}, false)
		task.spawn(LoadNextPage)
	end

	list:SetOnNearEnd(function()
		LoadNextPage()
	end)
	refreshButton.Activated:Connect(function()
		Reload()
	end)

	local keyList: KeyList = {
		Root = root,

		SetStore = function(_self: KeyList, ref: StoreRef.StoreRef?)
			storeRef = ref
			selectedKey = nil
			searchText = ""
			searchField:SetText("")
			isAscending = false
			sortSwitch:SetValue("Desc", false)
			sortSwitch.Root.Visible = ref ~= nil and ref.IsOrdered
			newKeyButton:SetEnabled(ref ~= nil)
			refreshButton:SetEnabled(ref ~= nil)
			Reload()
		end,

		SetSelectedKey = function(_self: KeyList, key: string?)
			selectedKey = key
			list:Refresh()
		end,

		Reload = function(_self: KeyList)
			Reload()
		end,

		FocusSearch = function(_self: KeyList)
			searchField:Focus()
		end,

		RefreshSections = function(_self: KeyList)
			Rebuild()
		end,

		RemoveKey = function(_self: KeyList, key: string)
			for index, listing in loadedKeys do
				if listing.Key == key then
					table.remove(loadedKeys, index)
					break
				end
			end
			Rebuild()
		end,

		SetCompact = function(_self: KeyList, isCompact: boolean)
			root.Size = UDim2.fromScale(if isCompact then 1 else 0.27, 1)
		end,

		SetKeyValue = function(_self: KeyList, key: string, value: number?)
			for _, listing in loadedKeys do
				if listing.Key == key then
					listing.Value = value
					list:Refresh()
					return
				end
			end
			-- A brand-new key: show it right away rather than waiting for the
			-- (eventually consistent) listing to include it.
			table.insert(loadedKeys, 1, { Key = key, Value = value })
			Rebuild()
		end,
	}

	newKeyButton:SetEnabled(false)
	refreshButton:SetEnabled(false)
	Rebuild()
	return keyList
end

return KeyList
