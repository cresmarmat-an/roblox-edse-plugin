--!strict
--[[
	InfoPage
	Key facts (version, timestamps, size) plus the two pieces of key data
	that aren't the value: associated UserIds (used for GDPR erasure
	requests) and custom metadata.
]]

local CodeView = require(script.Parent.Parent.Parent.Ui.Components.CodeView)
local Create = require(script.Parent.Parent.Parent.Ui.Create)
local EntrySession = require(script.Parent.Parent.Parent.Core.EntrySession)
local Format = require(script.Parent.Parent.Parent.Core.Format)
local Json = require(script.Parent.Parent.Parent.Core.Json)
local Icon = require(script.Parent.Parent.Parent.Ui.Components.Icon)
local JsonPage = require(script.Parent.JsonPage)
local Label = require(script.Parent.Parent.Parent.Ui.Components.Label)
local Palette = require(script.Parent.Parent.Parent.Theme.Palette)
local Signal = require(script.Parent.Parent.Parent.Core.Signal)
local StoreRef = require(script.Parent.Parent.Parent.Core.StoreRef)
local TextField = require(script.Parent.Parent.Parent.Ui.Components.TextField)
local Theme = require(script.Parent.Parent.Parent.Theme.Theme)
local Log = require(script.Parent.Parent.Parent.Services.Log)
local TreeModel = require(script.Parent.Parent.Parent.Core.TreeModel)
local Typography = require(script.Parent.Parent.Parent.Ui.Typography)

export type InfoPageProps = {
	Parent: Instance,
}

export type InfoPage = {
	Root: Frame,
	InvalidChanged: Signal.Signal<boolean>,
	SetSession: (self: InfoPage, session: EntrySession.EntrySession?) -> (),
	IsInvalid: (self: InfoPage) -> boolean,
}

local SOURCE = "Info"
local STAT_NAMES = { "Key", "Store", "Version", "Created", "Updated", "Size" }

local InfoPage = {}

local function SectionTitle(text: string, order: number, parent: Instance)
	Label.new({
		Name = text,
		Text = string.upper(text),
		Size = UDim2.fromScale(1, 0.045),
		Font = Typography.FONT_BOLD,
		Color = "TextMuted",
		Ratio = 0.7,
		MaxTextSize = 12,
		LayoutOrder = order,
		Parent = parent,
	})
end

function InfoPage.new(props: InfoPageProps): InfoPage
	local session: EntrySession.EntrySession? = nil
	local sessionConnection: Signal.Connection? = nil
	local isInvalid = false
	local isApplyingMetadata = false
	local invalidChanged = Signal.new() :: Signal.Signal<boolean>

	local root: Frame = Create("Frame", {
		Name = "InfoPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.012, 0),
			}),
		},
		Parent = props.Parent,
	})

	-- Stats grid: two columns of label/value pairs.
	SectionTitle("Details", 1, root)
	local statsGrid: Frame = Create("Frame", {
		Name = "Stats",
		Size = UDim2.fromScale(1, 0.24),
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Children = {
			Create("UIGridLayout", {
				CellSize = UDim2.fromScale(0.49, 0.3),
				CellPadding = UDim2.fromScale(0.02, 0.05),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = root,
	})
	local statValues: { [string]: TextLabel } = {}
	for index, name in STAT_NAMES do
		local cell: Frame = Create("Frame", {
			Name = name,
			LayoutOrder = index,
			BackgroundTransparency = 1,
			Parent = statsGrid,
		})
		Label.new({
			Name = "Name",
			Text = name,
			Size = UDim2.fromScale(0.3, 1),
			Color = "TextMuted",
			Font = Typography.FONT_MEDIUM,
			Ratio = 0.46,
			MaxTextSize = 13,
			Parent = cell,
		})
		statValues[name] = Label.new({
			Name = "Value",
			Text = "—",
			Size = UDim2.fromScale(0.7, 1),
			Position = UDim2.fromScale(0.3, 0),
			Font = if name == "Version" then Typography.FONT_MONO else Typography.FONT_MEDIUM,
			Ratio = 0.46,
			MaxTextSize = 13,
			Parent = cell,
		})
	end

	-- UserIds: removable chips plus an add field.
	SectionTitle("User IDs", 3, root)
	local userIdRow: Frame = Create("Frame", {
		Name = "UserIds",
		Size = UDim2.fromScale(1, 0.16),
		LayoutOrder = 4,
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Wraps = true,
				Padding = UDim.new(0.012, 0),
			}),
		},
		Parent = root,
	})

	local RenderUserIds: () -> ()

	local addField: TextField.TextField
	addField = TextField.new({
		Name = "AddUserId",
		Size = UDim2.fromScale(0.3, 0.45),
		LayoutOrder = 100000,
		Icon = "Add",
		IsMonospace = true,
		Placeholder = "Add user ID",
		OnSubmit = function(text: string)
			local current = session
			if current == nil then
				return
			end
			local userId = tonumber(text)
			if userId == nil or userId % 1 ~= 0 or userId <= 0 then
				Log.Warning(`"{text}" isn't a valid user ID`, "User IDs are positive whole numbers.")
				return
			end
			if table.find(current.Draft.UserIds, userId) then
				Log.Info(`User ID {userId} is already listed`)
				return
			end
			local userIds = table.clone(current.Draft.UserIds)
			table.insert(userIds, userId)
			current:SetUserIds(userIds, SOURCE)
			addField:SetText("")
			RenderUserIds()
		end,
		Parent = userIdRow,
	})

	local function UserIdChip(userId: number, order: number)
		-- The trailing spaces leave room for the remove icon, which sits over
		-- them so the chip can still size itself to its text.
		local chip: TextButton = Create("TextButton", {
			Name = `User{userId}`,
			Size = UDim2.fromScale(0, 0.4),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = order,
			Text = `  {userId}       `,
			AutoButtonColor = false,
			FontFace = Typography.FONT_MONO,
			TextXAlignment = Enum.TextXAlignment.Left,
			Theme = {
				BackgroundColor3 = "ControlTint",
				BackgroundTransparency = function(palette: Palette.Palette): number
					return 1 - palette.ControlOpacity
				end,
				TextColor3 = "TextPrimary",
			},
			Children = {
				Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			},
			Parent = userIdRow,
		})
		Typography.Fit(chip, 0.5, 12, 13)
		local removeIcon = Icon.new({
			Name = "Close",
			Size = UDim2.fromScale(1, 0.46),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.94, 0.5),
			Color = "TextMuted",
			Parent = chip,
		})
		chip.MouseEnter:Connect(function()
			removeIcon:SetColor("Danger")
		end)
		chip.MouseLeave:Connect(function()
			removeIcon:SetColor("TextMuted")
		end)
		chip.Activated:Connect(function()
			local current = session
			if current == nil then
				return
			end
			local userIds = table.clone(current.Draft.UserIds)
			local index = table.find(userIds, userId)
			if index then
				table.remove(userIds, index)
				current:SetUserIds(userIds, SOURCE)
				RenderUserIds()
			end
		end)
	end

	function RenderUserIds()
		for _, child in userIdRow:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		local current = session
		if current == nil then
			return
		end
		for index, userId in current.Draft.UserIds do
			UserIdChip(userId, index)
		end
	end

	-- Metadata: a small JSON editor for an object.
	SectionTitle("Metadata", 5, root)
	local metadataStatus: TextLabel
	local metadataView = CodeView.new({
		Name = "Metadata",
		Size = UDim2.fromScale(1, 0.3),
		LayoutOrder = 6,
		Placeholder = "{ }",
		OnTextChanged = function(text: string)
			local current = session
			if current == nil or isApplyingMetadata then
				return
			end
			local trimmed = string.match(text, "^%s*(.-)%s*$") :: string
			local ok, result = Json.Decode(if trimmed == "" then "{}" else trimmed)
			local isObject = ok and type(result) == "table" and (next(result) == nil or not Json.IsArray(result))
			local invalid = not isObject
			if invalid ~= isInvalid then
				isInvalid = invalid
				invalidChanged:Fire(invalid)
			end
			if not ok then
				local failure = result :: Json.DecodeError
				metadataStatus.Text = `Line {failure.Line}, column {failure.Column}: {failure.Message}`
			elseif not isObject then
				metadataStatus.Text = 'Metadata must be a JSON object, e.g. { "Reason": "refund" }'
			else
				metadataStatus.Text = "Custom metadata saved with the key"
				if not TreeModel.DeepEqual(result, current.Draft.Metadata) then
					current:SetMetadata(result, SOURCE)
				end
			end
			Theme.Bind(metadataStatus, "TextColor3", if invalid then "Danger" else "TextMuted")
		end,
		Parent = root,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = metadataView.Root })
	metadataStatus = Label.new({
		Name = "MetadataStatus",
		Text = "",
		Size = UDim2.fromScale(1, 0.05),
		Color = "TextMuted",
		Ratio = 0.6,
		MaxTextSize = 12,
		LayoutOrder = 7,
		Parent = root,
	})

	local function RenderStats()
		local current = session
		if current == nil then
			for _, label in statValues do
				label.Text = "—"
			end
			return
		end
		local original = current.Original
		local now = DateTime.now().UnixTimestampMillis
		statValues.Key.Text = current.Key
		statValues.Store.Text = StoreRef.Describe(current.StoreRef)
		statValues.Version.Text = original.Version or (if original.Exists then "—" else "not saved yet")
		statValues.Created.Text = if original.CreatedTime
			then `{Format.DateTime(original.CreatedTime)} ({Format.RelativeTime(original.CreatedTime, now)})`
			else "—"
		statValues.Updated.Text = if original.UpdatedTime
			then `{Format.DateTime(original.UpdatedTime)} ({Format.RelativeTime(original.UpdatedTime, now)})`
			else "—"
		local size = Format.EncodedSize(current.Draft.Value)
		statValues.Size.Text = if size then Format.Bytes(size) else "—"
	end

	local function RenderMetadata()
		local current = session
		isApplyingMetadata = true
		if current == nil or next(current.Draft.Metadata) == nil then
			metadataView:SetText("")
		else
			local ok, text = JsonPage.EncodeForEditing(current.Draft.Metadata)
			metadataView:SetText(if ok then text else "")
		end
		isApplyingMetadata = false
		metadataStatus.Text = "Custom metadata saved with the key"
		Theme.Bind(metadataStatus, "TextColor3", "TextMuted")
		if isInvalid then
			isInvalid = false
			invalidChanged:Fire(false)
		end
	end

	local page: InfoPage = {
		Root = root,
		InvalidChanged = invalidChanged,

		SetSession = function(_self: InfoPage, newSession: EntrySession.EntrySession?)
			if sessionConnection then
				sessionConnection:Disconnect()
				sessionConnection = nil
			end
			session = newSession
			if newSession then
				sessionConnection = newSession.Changed:Connect(function(source: string)
					RenderStats()
					if source ~= SOURCE then
						RenderUserIds()
						RenderMetadata()
					end
				end)
			end
			RenderStats()
			RenderUserIds()
			RenderMetadata()
		end,

		IsInvalid = function(_self: InfoPage): boolean
			return isInvalid
		end,
	}
	return page
end

return InfoPage
