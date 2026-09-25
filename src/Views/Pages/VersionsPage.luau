--!strict
--[[
	VersionsPage
	A key's version history (newest first). Select a version to preview it,
	then "Restore into editor" to load it as the draft. Nothing is written
	until you Save, and saving shows the diff first, so a rollback is always
	reviewed before it goes live.
]]

local Button = require(script.Parent.Parent.Parent.Ui.Components.Button)
local CodeView = require(script.Parent.Parent.Parent.Ui.Components.CodeView)
local Create = require(script.Parent.Parent.Parent.Ui.Create)
local DataStoreGateway = require(script.Parent.Parent.Parent.Services.DataStoreGateway)
local EntrySession = require(script.Parent.Parent.Parent.Core.EntrySession)
local Format = require(script.Parent.Parent.Parent.Core.Format)
local JsonPage = require(script.Parent.JsonPage)
local Label = require(script.Parent.Parent.Parent.Ui.Components.Label)
local Motion = require(script.Parent.Parent.Parent.Ui.Motion)
local Surface = require(script.Parent.Parent.Parent.Ui.Surface)
local Theme = require(script.Parent.Parent.Parent.Theme.Theme)
local Log = require(script.Parent.Parent.Parent.Services.Log)
local Typography = require(script.Parent.Parent.Parent.Ui.Typography)
local VirtualList = require(script.Parent.Parent.Parent.Ui.Components.VirtualList)

export type VersionsPageProps = {
	Parent: Instance,
}

export type VersionsPage = {
	Root: Frame,
	SetSession: (self: VersionsPage, session: EntrySession.EntrySession?) -> (),
	-- Loads history the first time the tab is shown (saves request budget).
	Activate: (self: VersionsPage) -> (),
	SetCompact: (self: VersionsPage, isCompact: boolean) -> (),
}

type Item = {
	Kind: "Version" | "Status",
	Text: string,
	Listing: DataStoreGateway.VersionListing?,
}

local SOURCE = "Versions"
local TARGET_ROW_HEIGHT = 34
local SHORT_VERSION_LENGTH = 12

local VersionsPage = {}

function VersionsPage.new(props: VersionsPageProps): VersionsPage
	local session: EntrySession.EntrySession? = nil
	local pager: DataStoreGateway.Pager<DataStoreGateway.VersionListing>? = nil
	local listings: { DataStoreGateway.VersionListing } = {}
	local isLoading = false
	local loadError: string? = nil
	local loadToken = 0
	local selectedVersion: string? = nil
	local previewEntry: EntrySession.Entry? = nil
	local previewToken = 0
	local hasActivated = false

	local root: Frame = Create("Frame", {
		Name = "VersionsPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = props.Parent,
	})
	local layout: UIListLayout = Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.015, 0),
		Parent = root,
	})

	local listWell = Surface.Inset({
		Name = "History",
		Size = UDim2.fromScale(0.36, 1),
		LayoutOrder = 1,
		CornerScale = 0.04,
		Parent = root,
	})

	local previewColumn: Frame = Create("Frame", {
		Name = "Preview",
		Size = UDim2.fromScale(0.62, 1),
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Children = {
			Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.015, 0),
			}),
		},
		Parent = root,
	})

	local previewHeader: Frame = Create("Frame", {
		Name = "Header",
		Size = UDim2.fromScale(1, 0.075),
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.015, 0),
			}),
		},
		Parent = previewColumn,
	})
	local previewTitle = Label.new({
		Name = "Title",
		Text = "Select a version to preview it",
		Size = UDim2.fromScale(0.5, 1),
		Font = Typography.FONT_MEDIUM,
		Color = "TextSecondary",
		Ratio = 0.44,
		MaxTextSize = 14,
		LayoutOrder = 1,
		Parent = previewHeader,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = previewTitle })

	local restoreButton = Button.new({
		Name = "Restore",
		Text = "Restore",
		Icon = "History",
		Variant = "Primary",
		Size = UDim2.fromScale(0.3, 1),
		LayoutOrder = 2,
		Tooltip = "Load this version into the editor as a draft. Review it, then Save to make it live.",
		Parent = previewHeader,
	})
	restoreButton:SetEnabled(false)

	local preview = CodeView.new({
		Name = "Code",
		Size = UDim2.fromScale(1, 0.9),
		LayoutOrder = 2,
		IsReadOnly = true,
		Parent = previewColumn,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = preview.Root })

	local list: VirtualList.VirtualList
	local Rebuild: () -> ()

	local function SelectVersion(listing: DataStoreGateway.VersionListing)
		local current = session
		if current == nil then
			return
		end
		selectedVersion = listing.Version
		previewEntry = nil
		restoreButton:SetEnabled(false)
		list:Refresh()
		previewTitle.Text = `{Format.DateTime(listing.CreatedTime)} · loading…`
		previewToken += 1
		local token = previewToken

		if listing.IsDeleted then
			previewTitle.Text = `{Format.DateTime(listing.CreatedTime)} · deleted`
			preview:SetText("// The key was deleted at this point.")
			return
		end

		local result = DataStoreGateway.ReadVersion(current.StoreRef, current.Key, listing.Version)
		if token ~= previewToken or session ~= current then
			return
		end
		if not result.Ok then
			previewTitle.Text = "Couldn't load this version"
			preview:SetText("")
			Log.Failure(`Couldn't load a version of "{current.Key}"`, result.Error)
			return
		end
		previewEntry = result.Value
		local ok, text = JsonPage.EncodeForEditing(result.Value.Value)
		preview:SetText(if ok then text else `// {text}`)
		previewTitle.Text = `{Format.DateTime(listing.CreatedTime)} · {Format.RelativeTime(
			listing.CreatedTime,
			DateTime.now().UnixTimestampMillis
		)}`
		restoreButton:SetEnabled(result.Value.Value ~= nil)
	end

	type Row = {
		Root: TextButton,
		Selection: Frame,
		Title: TextLabel,
		Detail: TextLabel,
		Item: Item?,
	}

	local function CreateRow(): Row
		local rowButton: TextButton = Create("TextButton", {
			Name = "VersionRow",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
		})
		local selection: Frame = Create("Frame", {
			Name = "Selection",
			Size = UDim2.fromScale(0.96, 0.9),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "Selection" },
			Children = { Create("UICorner", { CornerRadius = UDim.new(0.25, 0) }) },
			Parent = rowButton,
		})
		local title = Label.new({
			Name = "Title",
			Text = "",
			Size = UDim2.fromScale(0.9, 0.48),
			Position = UDim2.fromScale(0.06, 0.06),
			Font = Typography.FONT_MEDIUM,
			Ratio = 0.72,
			MaxTextSize = 14,
			ZIndex = 2,
			Parent = rowButton,
		})
		local detail = Label.new({
			Name = "Detail",
			Text = "",
			Size = UDim2.fromScale(0.9, 0.38),
			Position = UDim2.fromScale(0.06, 0.54),
			Font = Typography.FONT_MONO,
			Color = "TextMuted",
			Ratio = 0.72,
			MaxTextSize = 12,
			ZIndex = 2,
			Parent = rowButton,
		})
		local row: Row = { Root = rowButton, Selection = selection, Title = title, Detail = detail, Item = nil }
		rowButton.MouseEnter:Connect(function()
			local item = row.Item
			if item and item.Listing and item.Listing.Version ~= selectedVersion then
				Motion.Tween(selection, Motion.FAST, { BackgroundTransparency = 1 - Theme.Current().HoverOpacity * 2 })
			end
		end)
		rowButton.MouseLeave:Connect(function()
			list:Refresh()
		end)
		rowButton.Activated:Connect(function()
			local item = row.Item
			if item and item.Listing then
				SelectVersion(item.Listing)
			end
		end)
		return row
	end

	local function UpdateRow(row: Row, item: Item, index: number)
		row.Item = item
		local listing = item.Listing
		if listing == nil then
			row.Title.Text = item.Text
			row.Detail.Text = ""
			row.Selection.BackgroundTransparency = 1
			Theme.Bind(row.Title, "TextColor3", "TextMuted")
			return
		end
		local isSelected = listing.Version == selectedVersion
		row.Selection.BackgroundTransparency = if isSelected then 1 - Theme.Current().SelectionOpacity else 1
		local relative = Format.RelativeTime(listing.CreatedTime, DateTime.now().UnixTimestampMillis)
		local badge = if index == 1 and not listing.IsDeleted
			then "  · current"
			elseif listing.IsDeleted then "  · deleted"
			else ""
		row.Title.Text = relative .. badge
		row.Detail.Text =
			`{Format.DateTime(listing.CreatedTime)}  {string.sub(listing.Version, 1, SHORT_VERSION_LENGTH)}`
		Theme.Bind(
			row.Title,
			"TextColor3",
			if listing.IsDeleted then "Danger" elseif isSelected then "Accent" else "TextPrimary"
		)
	end

	list = VirtualList.new({
		Name = "Versions",
		Size = UDim2.fromScale(0.96, 0.96),
		Position = UDim2.fromScale(0.02, 0.02),
		TargetRowHeight = TARGET_ROW_HEIGHT,
		CreateRow = CreateRow :: any,
		UpdateRow = UpdateRow :: any,
		Parent = listWell.Content,
	})

	function Rebuild()
		local items: { Item } = {}
		for _, listing in listings do
			table.insert(items, { Kind = "Version", Text = listing.Version, Listing = listing })
		end
		if isLoading then
			table.insert(items, { Kind = "Status", Text = "Loading history…" })
		elseif loadError then
			table.insert(items, { Kind = "Status", Text = loadError })
		elseif #listings == 0 then
			table.insert(items, { Kind = "Status", Text = "No versions yet." })
		end
		list:SetItems(items, true)
	end

	local function LoadNextPage()
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
			return
		end
		isLoading = false
		if result.Ok then
			table.move(result.Value, 1, #result.Value, #listings + 1, listings)
		else
			loadError = result.Error.Hint or result.Error.Message
			local current = session
			Log.Failure(
				`Couldn't load the version history{if current then ` of "{current.Key}"` else ""}`,
				result.Error
			)
		end
		Rebuild()
	end

	local function Reset()
		loadToken += 1
		previewToken += 1
		listings = {}
		isLoading = false
		loadError = nil
		selectedVersion = nil
		previewEntry = nil
		hasActivated = false
		restoreButton:SetEnabled(false)
		previewTitle.Text = "Select a version to preview it"
		preview:SetText("")
		local current = session
		pager = if current and not current.StoreRef.IsOrdered
			then DataStoreGateway.ListVersions(current.StoreRef, current.Key)
			else nil
		Rebuild()
	end

	list:SetOnNearEnd(function()
		if hasActivated then
			LoadNextPage()
		end
	end)

	restoreButton.Activated:Connect(function()
		local current = session
		local entry = previewEntry
		if current == nil or entry == nil then
			return
		end
		current:SetValue(entry.Value, SOURCE)
		current:SetUserIds(table.clone(entry.UserIds), SOURCE)
		current:SetMetadata(table.clone(entry.Metadata), SOURCE)
		Log.Info(
			`Restored a version of "{current.Key}" into the editor`,
			`{if entry.Version then "Version " .. entry.Version else "Earlier version"}. It's a draft: review it, then Save to make it live.`
		)
	end)

	return {
		Root = root,

		SetSession = function(_self: VersionsPage, newSession: EntrySession.EntrySession?)
			session = newSession
			Reset()
		end,

		Activate = function(_self: VersionsPage)
			if hasActivated or session == nil then
				return
			end
			hasActivated = true
			task.spawn(LoadNextPage)
		end,

		SetCompact = function(_self: VersionsPage, isCompact: boolean)
			layout.FillDirection = if isCompact then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
			listWell.Root.Size = if isCompact then UDim2.fromScale(1, 0.34) else UDim2.fromScale(0.36, 1)
			previewColumn.Size = if isCompact then UDim2.fromScale(1, 0.62) else UDim2.fromScale(0.62, 1)
		end,
	}
end

return VersionsPage
