--!strict
--[[
	StoreBar
	Pick a data store: type its name (with suggestions from recent stores and,
	on demand, every store in the experience), optionally a scope, choose
	Standard or Ordered, and open it. Enter in the name field opens directly.
]]

local Button = require(script.Parent.Parent.Ui.Components.Button)
local Context = require(script.Parent.Context)
local Create = require(script.Parent.Parent.Ui.Create)
local DataStoreGateway = require(script.Parent.Parent.Services.DataStoreGateway)
local Format = require(script.Parent.Parent.Core.Format)
local Label = require(script.Parent.Parent.Ui.Components.Label)
local Motion = require(script.Parent.Parent.Ui.Motion)
local Segmented = require(script.Parent.Parent.Ui.Components.Segmented)
local StoreRef = require(script.Parent.Parent.Core.StoreRef)
local Surface = require(script.Parent.Parent.Ui.Surface)
local TextField = require(script.Parent.Parent.Ui.Components.TextField)
local Theme = require(script.Parent.Parent.Theme.Theme)
local Log = require(script.Parent.Parent.Services.Log)
local Typography = require(script.Parent.Parent.Ui.Typography)

export type StoreBarProps = {
	Context: Context.Context,
	OverlayHost: GuiObject,
	OnOpen: (ref: StoreRef.StoreRef) -> (),
	Parent: Instance,
}

export type StoreBar = {
	Root: Frame,
	SetStore: (self: StoreBar, ref: StoreRef.StoreRef) -> (),
	SetCompact: (self: StoreBar, isCompact: boolean) -> (),
	FocusName: (self: StoreBar) -> (),
}

type Suggestion = { Name: string, IsOrdered: boolean?, Scope: string?, Section: string }

-- Control widths as fractions of the store picker's width.
-- "Wide" is the picker sharing the header bar; "compact" is its own row.
local WIDE_SCOPE_WIDTH = 0.15
local WIDE_TYPE_WIDTH = 0.26
local WIDE_OPEN_WIDTH = 0.12
local COMPACT_SCOPE_WIDTH = 0.18
local COMPACT_TYPE_WIDTH = 0.26
local COMPACT_OPEN_WIDTH = 0.13

local MAX_SUGGESTIONS = 8
local MAX_STORE_PAGES = 4
local HIDE_DELAY_SECONDS = 0.2

local StoreBar = {}

function StoreBar.new(props: StoreBarProps): StoreBar
	local settings = props.Context.Settings
	local isOrdered = false
	local allStoreNames: { string }? = nil
	local isLoadingStores = false

	-- Fills whatever hosts it: the header's store slot when the widget is
	-- wide, or its own glass row when compact.
	local root: Frame = Create("Frame", {
		Name = "StoreBar",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = props.Parent,
	})
	local primaryRow: Frame = Create("Frame", {
		Name = "Row",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.01, 0),
			}),
		},
		Parent = root,
	})

	-- Suggestions popover (declared early; wired below).
	local popover: Frame
	local popoverList: Frame
	local ShowSuggestions: (filter: string) -> ()
	local hideToken = 0

	local function HideSuggestions()
		hideToken += 1
		popover.Visible = false
	end

	local nameField: TextField.TextField
	local scopeField: TextField.TextField

	local function OpenCurrent()
		local name = string.match(nameField:GetText(), "^%s*(.-)%s*$") :: string
		local problem = StoreRef.ValidateName(name)
		if problem then
			nameField:SetInvalid(true)
			Log.Warning("Can't open that data store", problem)
			return
		end
		nameField:SetInvalid(false)
		HideSuggestions()
		local ref = StoreRef.new(name, scopeField:GetText(), isOrdered)
		settings:RememberStore(ref)
		props.OnOpen(ref)
	end

	nameField = TextField.new({
		Name = "StoreName",
		Size = UDim2.fromScale(0.4, 1),
		LayoutOrder = 1,
		Icon = "Store",
		Placeholder = "Data store name",
		ShowClearButton = true,
		OnChanged = function(text: string)
			nameField:SetInvalid(false)
			if nameField.TextBox:IsFocused() then
				ShowSuggestions(text)
			end
		end,
		OnSubmit = function()
			OpenCurrent()
		end,
		OnFocusChanged = function(isFocused: boolean)
			if isFocused then
				ShowSuggestions(nameField:GetText())
			else
				hideToken += 1
				local token = hideToken
				task.delay(HIDE_DELAY_SECONDS, function()
					if token == hideToken then
						popover.Visible = false
					end
				end)
			end
		end,
		Parent = primaryRow,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = nameField.Root })

	scopeField = TextField.new({
		Name = "Scope",
		Size = UDim2.fromScale(WIDE_SCOPE_WIDTH, 1),
		LayoutOrder = 2,
		Placeholder = StoreRef.DEFAULT_SCOPE,
		OnSubmit = function()
			OpenCurrent()
		end,
		Parent = primaryRow,
	})

	local typeSwitch = Segmented.new({
		Name = "StoreType",
		Options = {
			{
				Value = "Standard",
				Label = "Standard",
				Tooltip = "Regular data store (JSON values, versions, metadata)",
			},
			{ Value = "Ordered", Label = "Ordered", Tooltip = "OrderedDataStore (whole numbers, sorted)" },
		},
		Value = "Standard",
		Size = UDim2.fromScale(WIDE_TYPE_WIDTH, 1),
		LayoutOrder = 3,
		OnChanged = function(value: string)
			isOrdered = value == "Ordered"
		end,
		Parent = primaryRow,
	})

	local browseButton = Button.new({
		Name = "Browse",
		Icon = "More",
		Tooltip = "Browse every data store in this experience",
		Variant = "Ghost",
		Square = true,
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = 4,
		Parent = primaryRow,
	})

	local openButton = Button.new({
		Name = "Open",
		Text = "Open",
		Variant = "Primary",
		Size = UDim2.fromScale(WIDE_OPEN_WIDTH, 1),
		LayoutOrder = 5,
		OnActivated = OpenCurrent,
		Parent = primaryRow,
	})

	-- Popover ------------------------------------------------------------
	popover = Create("Frame", {
		Name = "StoreSuggestions",
		Size = UDim2.fromScale(0.4, 0.4),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 30,
		Parent = props.OverlayHost,
	})
	local popoverScale: UIScale = Create("UIScale", { Parent = popover })
	local popoverCard = Surface.Raised({
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		CornerScale = 0.04,
		Elevation = "Floating",
		Parent = popover,
	})
	popoverList = Create("Frame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Surface.Padding(0.02, 0.03),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = popoverCard.Content,
	})

	local function PositionPopover(rowCount: number)
		local host = props.OverlayHost
		local hostSize = host.AbsoluteSize
		if hostSize.X <= 0 or hostSize.Y <= 0 then
			return
		end
		local anchor = nameField.Root
		local relative = anchor.AbsolutePosition - host.AbsolutePosition
		local rowPixels = math.max(26, anchor.AbsoluteSize.Y * 0.8)
		-- Measure in pixels, then express as scale, keeping the whole popover
		-- inside the widget so nothing is cut off.
		local width = math.min(math.max(anchor.AbsoluteSize.X, 240), hostSize.X * 0.96)
		local top = relative.Y + anchor.AbsoluteSize.Y * 1.25
		local height = math.min(rowCount * rowPixels * 1.06 + rowPixels * 0.3, hostSize.Y - top - 8)
		local left = math.clamp(relative.X, 0, math.max(0, hostSize.X - width))
		popover.Position = UDim2.fromScale(left / hostSize.X, top / hostSize.Y)
		popover.Size = UDim2.fromScale(width / hostSize.X, math.max(height, rowPixels) / hostSize.Y)
	end

	local function ClearPopover()
		for _, child in popoverList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function AddSectionLabel(text: string, order: number, rowScale: number)
		Label.new({
			Name = "Section",
			Text = string.upper(text),
			Size = UDim2.fromScale(1, rowScale * 0.8),
			Color = "TextMuted",
			Font = Typography.FONT_BOLD,
			Ratio = 0.5,
			MaxTextSize = 12,
			LayoutOrder = order,
			Parent = popoverList,
		})
	end

	local function AddSuggestionRow(suggestion: Suggestion, order: number, rowScale: number)
		local row: TextButton = Create("TextButton", {
			Name = suggestion.Name,
			Size = UDim2.fromScale(1, rowScale),
			LayoutOrder = order,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "Selection" },
			Children = {
				Create("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
				Surface.Padding(0.03, 0),
			},
			Parent = popoverList,
		})
		local detail = if suggestion.Scope and suggestion.Scope ~= StoreRef.DEFAULT_SCOPE
			then `  ·  {suggestion.Scope}`
			else ""
		local orderedTag = if suggestion.IsOrdered then "  ·  ordered" else ""
		Label.new({
			Name = "Text",
			Text = `{Typography.EscapeRichText(suggestion.Name)}{Typography.ColorTag(
				Typography.EscapeRichText(detail .. orderedTag),
				Theme.Current().TextMuted
			)}`,
			RichText = true,
			Size = UDim2.fromScale(1, 1),
			Ratio = 0.46,
			MaxTextSize = 15,
			Parent = row,
		})
		row.MouseEnter:Connect(function()
			Motion.Tween(row, Motion.FAST, { BackgroundTransparency = 1 - Theme.Current().SelectionOpacity })
		end)
		row.MouseLeave:Connect(function()
			Motion.Tween(row, Motion.FAST, { BackgroundTransparency = 1 })
		end)
		row.Activated:Connect(function()
			nameField:SetText(suggestion.Name)
			if suggestion.Scope then
				scopeField:SetText(if suggestion.Scope == StoreRef.DEFAULT_SCOPE then "" else suggestion.Scope)
			end
			if suggestion.IsOrdered ~= nil then
				isOrdered = suggestion.IsOrdered
				typeSwitch:SetValue(if isOrdered then "Ordered" else "Standard", true)
			end
			OpenCurrent()
		end)
	end

	function ShowSuggestions(filter: string)
		local loweredFilter = string.lower(filter)
		local suggestions: { Suggestion } = {}
		local seen: { [string]: boolean } = {}

		for _, ref in settings:GetRecentStores() do
			if #suggestions < MAX_SUGGESTIONS and string.find(string.lower(ref.Name), loweredFilter, 1, true) then
				table.insert(
					suggestions,
					{ Name = ref.Name, Scope = ref.Scope, IsOrdered = ref.IsOrdered, Section = "Recent" }
				)
				seen[ref.Name] = true
			end
		end
		local knownNames: { string } = allStoreNames or {}
		for _, name in knownNames do
			if #suggestions >= MAX_SUGGESTIONS then
				break
			end
			if not seen[name] and string.find(string.lower(name), loweredFilter, 1, true) then
				table.insert(suggestions, { Name = name, Section = "All stores" })
				seen[name] = true
			end
		end

		ClearPopover()
		local statusText: string? = nil
		if isLoadingStores then
			statusText = "Loading data stores…"
		elseif #suggestions == 0 then
			statusText = if allStoreNames == nil
				then "No recent stores yet. Use Browse to list every store."
				else "No matching data stores."
		end

		local sectionCount = 0
		local lastSection: string? = nil
		for _, suggestion in suggestions do
			if suggestion.Section ~= lastSection then
				sectionCount += 1
				lastSection = suggestion.Section
			end
		end
		local rowCount = #suggestions + sectionCount + (if statusText then 1 else 0)
		local rowScale = 1 / math.max(rowCount, 1)

		local order = 0
		lastSection = nil
		for _, suggestion in suggestions do
			if suggestion.Section ~= lastSection then
				order += 1
				AddSectionLabel(suggestion.Section, order, rowScale)
				lastSection = suggestion.Section
			end
			order += 1
			AddSuggestionRow(suggestion, order, rowScale)
		end
		if statusText then
			Label.new({
				Name = "Status",
				Text = statusText,
				Size = UDim2.fromScale(1, rowScale),
				Color = "TextMuted",
				Ratio = 0.44,
				MaxTextSize = 13,
				LayoutOrder = order + 1,
				Parent = popoverList,
			})
		end

		PositionPopover(rowCount)
		hideToken += 1
		if not popover.Visible then
			popover.Visible = true
			popoverScale.Scale = 0.97
			Motion.Tween(popoverScale, Motion.FAST, { Scale = 1 })
		end
	end

	local function LoadAllStores()
		if isLoadingStores then
			return
		end
		isLoadingStores = true
		ShowSuggestions(nameField:GetText())
		local names: { string } = {}
		local pager = DataStoreGateway.ListStores("")
		local failure: DataStoreGateway.GatewayError? = nil
		for _ = 1, MAX_STORE_PAGES do
			local result = pager:LoadNext()
			if not result.Ok then
				failure = result.Error
				break
			end
			for _, listing in result.Value do
				table.insert(names, listing.Name)
			end
			if pager:IsFinished() then
				break
			end
		end
		isLoadingStores = false
		if failure then
			Log.Failure("Couldn't list this experience's data stores", failure)
		else
			Log.Info(`Found {Format.Plural(#names, "data store")} in this experience`)
			table.sort(names, function(left: string, right: string): boolean
				return string.lower(left) < string.lower(right)
			end)
			allStoreNames = names
		end
		ShowSuggestions(nameField:GetText())
	end

	browseButton.Activated:Connect(function()
		nameField:Focus()
		task.spawn(LoadAllStores)
	end)

	local storeBar: StoreBar = {
		Root = root,

		SetStore = function(_self: StoreBar, ref: StoreRef.StoreRef)
			nameField:SetText(ref.Name)
			scopeField:SetText(if ref.Scope == StoreRef.DEFAULT_SCOPE then "" else ref.Scope)
			isOrdered = ref.IsOrdered
			typeSwitch:SetValue(if ref.IsOrdered then "Ordered" else "Standard", false)
		end,

		SetCompact = function(_self: StoreBar, isCompact: boolean)
			scopeField.Root.Size = UDim2.fromScale(if isCompact then COMPACT_SCOPE_WIDTH else WIDE_SCOPE_WIDTH, 1)
			typeSwitch.Root.Size = UDim2.fromScale(if isCompact then COMPACT_TYPE_WIDTH else WIDE_TYPE_WIDTH, 1)
			openButton.Root.Size = UDim2.fromScale(if isCompact then COMPACT_OPEN_WIDTH else WIDE_OPEN_WIDTH, 1)
		end,

		FocusName = function(_self: StoreBar)
			nameField:Focus()
		end,
	}
	return storeBar
end

return StoreBar
