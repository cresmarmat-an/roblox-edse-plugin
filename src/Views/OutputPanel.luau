--!strict
--[[
	OutputPanel
	The bottom panel: a record of everything EDSE did or reported (see
	Services/Log). Replaces pop-up notifications, which could cut long
	messages off or vanish before you read them.

	Collapsed, it is a single bar: an Output toggle, warning/error counts,
	the latest message, the connection, and the DataStore request budget.
	Expanded, it adds a scrollable, timestamped log with full, wrapped
	messages and their details. It opens by itself when an error arrives
	(configurable), and Copy puts the whole log in a selectable box.
]]

local Button = require(script.Parent.Parent.Ui.Components.Button)
local Create = require(script.Parent.Parent.Ui.Create)
local DataStoreGateway = require(script.Parent.Parent.Services.DataStoreGateway)
local Dialogs = require(script.Parent.Dialogs)
local Label = require(script.Parent.Parent.Ui.Components.Label)
local Log = require(script.Parent.Parent.Services.Log)
local Palette = require(script.Parent.Parent.Theme.Palette)
local PluginSettings = require(script.Parent.Parent.Services.PluginSettings)
local Surface = require(script.Parent.Parent.Ui.Surface)
local Theme = require(script.Parent.Parent.Theme.Theme)
local Typography = require(script.Parent.Parent.Ui.Typography)

export type OutputPanelProps = {
	Settings: PluginSettings.PluginSettings,
	LayoutOrder: number,
	Parent: Instance,
}

export type OutputPanel = {
	Root: Frame,
	SetConnection: (self: OutputPanel, text: string, isWarning: boolean) -> (),
	RefreshBudgets: (self: OutputPanel) -> (),
	SetExpanded: (self: OutputPanel, isExpanded: boolean) -> (),
	Toggle: (self: OutputPanel) -> (),
	SetCompact: (self: OutputPanel, isCompact: boolean) -> (),
	Destroy: (self: OutputPanel) -> (),
}

-- Heights as fractions of the main column.
local COLLAPSED_HEIGHT_SCALE = 0.05
local EXPANDED_HEIGHT_SCALE = 0.32
local COLLAPSED_CORNER_SCALE = 0.26
local EXPANDED_CORNER_SCALE = 0.05
-- Log text has a fixed point size because each entry's height grows with
-- its wrapped text (the list scrolls, so nothing is ever clipped).
local ENTRY_TEXT_SIZE = 13
local ENTRY_LINE_HEIGHT = 1.25
local LOW_BUDGET = 5
local STICK_TO_BOTTOM_TOLERANCE = 4
-- Below this bar width (px) the connection label steps aside so the latest
-- message keeps its room.
local CONNECTION_MIN_BAR_WIDTH = 900

local LEVEL_COLOR: { [Log.Level]: string } = {
	Info = "Accent",
	Success = "Success",
	Warning = "Warning",
	Error = "Danger",
}

local OutputPanel = {}

OutputPanel.SETTING_EXPANDED = "OutputExpanded"

local function Hex(token: string): string
	return (Theme.Get(token) :: Color3):ToHex()
end

local function EntryMarkup(entry: Log.Entry): string
	local escape = Typography.EscapeRichText
	local text = `<font color="#{Hex("TextMuted")}">{Log.FormatTime(entry)}</font>   `
		.. `<font color="#{Hex(LEVEL_COLOR[entry.Level])}"><b>{Log.Tag(entry.Level)}</b></font>   `
		.. `<font color="#{Hex("TextPrimary")}">{escape(entry.Message)}</font>`
	if entry.Detail then
		text ..= `\n<font color="#{Hex("TextSecondary")}">{escape(entry.Detail)}</font>`
	end
	return text
end

function OutputPanel.new(props: OutputPanelProps): OutputPanel
	local settings = props.Settings
	local isExpanded = settings:GetBoolean(OutputPanel.SETTING_EXPANDED, false)
	local isCompact = false
	local stickToBottom = true
	local entryLabels: { [number]: TextLabel } = {}
	local entryOrder: { number } = {}

	local root: Frame = Create("Frame", {
		Name = "Output",
		Size = UDim2.fromScale(1, COLLAPSED_HEIGHT_SCALE),
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		Parent = props.Parent,
	})
	local card = Surface.Raised({
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		CornerScale = COLLAPSED_CORNER_SCALE,
		Parent = root,
	})

	-- Bar --------------------------------------------------------------------
	local bar: Frame = Create("Frame", {
		Name = "Bar",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Surface.Padding(0.006, 0.14),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.008, 0),
			}),
		},
		Parent = card.Content,
	})

	local toggleButton = Button.new({
		Name = "Toggle",
		Text = "Output",
		Icon = "PanelOpen",
		Variant = "Ghost",
		Size = UDim2.fromScale(0.1, 1),
		LayoutOrder = 1,
		Tooltip = "Show or hide the output log",
		Parent = bar,
	})

	local countsLabel = Label.new({
		Name = "Counts",
		Text = "",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Typography.FONT_SEMIBOLD,
		RichText = true,
		Ratio = 0.62,
		MaxTextSize = 13,
		LayoutOrder = 2,
		Parent = bar,
	})

	-- The latest message; clicking it opens the log.
	local latestButton: TextButton = Create("TextButton", {
		Name = "Latest",
		Size = UDim2.fromScale(0.4, 1),
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		RichText = true,
		Text = "",
		FontFace = Typography.FONT_MEDIUM,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextSecondary" },
		Children = { Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) },
		Parent = bar,
	})
	Typography.Fit(latestButton, 0.62, Typography.MIN_TEXT_SIZE, 13)

	local connectionLabel = Label.new({
		Name = "Connection",
		Text = "",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Color = "TextMuted",
		Font = Typography.FONT_MEDIUM,
		Ratio = 0.62,
		MaxTextSize = 13,
		LayoutOrder = 4,
		Parent = bar,
	})

	local budgetLabel = Label.new({
		Name = "Budget",
		Text = "",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Color = "TextMuted",
		Font = Typography.FONT_MONO,
		RichText = true,
		Ratio = 0.6,
		MaxTextSize = 12,
		LayoutOrder = 5,
		Parent = bar,
	})

	local copyButton = Button.new({
		Name = "Copy",
		Icon = "Copy",
		Variant = "Ghost",
		Square = true,
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = 6,
		Tooltip = "Copy the whole log",
		Parent = bar,
	})
	local clearButton = Button.new({
		Name = "Clear",
		Icon = "Trash",
		Variant = "Ghost",
		Square = true,
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = 7,
		Tooltip = "Clear the output",
		Parent = bar,
	})

	-- Log ----------------------------------------------------------------------
	local well = Surface.Inset({
		Name = "Log",
		Size = UDim2.fromScale(0.99, 0.8),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		CornerScale = 0.04,
		Parent = card.Content,
	})
	local scroller: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Scroller",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		ScrollBarThickness = 6,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Theme = { ScrollBarImageColor3 = "Scrollbar" },
		Parent = well.Content,
	})
	local entryList: Frame = Create("Frame", {
		Name = "Entries",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Children = {
			Create("UIPadding", {
				PaddingLeft = UDim.new(0.012, 0),
				PaddingRight = UDim.new(0.012, 0),
			}),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = scroller,
	})
	local emptyLabel: TextLabel = Create("TextLabel", {
		Name = "Empty",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 0,
		BackgroundTransparency = 1,
		Text = "No messages yet. Everything EDSE does is recorded here.",
		TextSize = ENTRY_TEXT_SIZE,
		LineHeight = 2,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Typography.FONT_MEDIUM,
		Theme = { TextColor3 = "TextMuted" },
		Parent = entryList,
	})

	-- Rendering ------------------------------------------------------------------
	local function RenderCounts()
		local counts = Log.Counts()
		local parts: { string } = {}
		if counts.Error > 0 then
			table.insert(
				parts,
				Typography.ColorTag(
					`{counts.Error} {if counts.Error == 1 then "error" else "errors"}`,
					Theme.Current().Danger
				)
			)
		end
		if counts.Warning > 0 then
			table.insert(
				parts,
				Typography.ColorTag(
					`{counts.Warning} {if counts.Warning == 1 then "warning" else "warnings"}`,
					Theme.Current().Warning
				)
			)
		end
		countsLabel.Text = table.concat(parts, "  ")
		countsLabel.Visible = #parts > 0
	end

	local function RenderLatest()
		local entries = Log.Entries()
		local latest = entries[#entries]
		if latest == nil then
			latestButton.Text = ""
			return
		end
		latestButton.Text = `<font color="#{Hex(LEVEL_COLOR[latest.Level])}"><b>{Log.Tag(latest.Level)}</b></font>  `
			.. Typography.EscapeRichText(latest.Message)
	end

	local function ScrollToBottom()
		local maxY = math.max(0, scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y)
		scroller.CanvasPosition = Vector2.new(0, maxY)
	end

	local function AddEntryLabel(entry: Log.Entry)
		local label: TextLabel = Create("TextLabel", {
			Name = `Entry{entry.Id}`,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = entry.Id,
			BackgroundTransparency = 1,
			RichText = true,
			Text = EntryMarkup(entry),
			TextSize = ENTRY_TEXT_SIZE,
			LineHeight = ENTRY_LINE_HEIGHT,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			FontFace = Typography.FONT_MEDIUM,
			Parent = entryList,
		})
		entryLabels[entry.Id] = label
		table.insert(entryOrder, entry.Id)
		while #entryOrder > Log.MAX_ENTRIES do
			local oldestId = table.remove(entryOrder, 1) :: number
			local oldest = entryLabels[oldestId]
			entryLabels[oldestId] = nil
			if oldest then
				oldest:Destroy()
			end
		end
		emptyLabel.Visible = false
	end

	local function RerenderAll()
		for _, entry in Log.Entries() do
			local label = entryLabels[entry.Id]
			if label then
				label.Text = EntryMarkup(entry)
			end
		end
		RenderCounts()
		RenderLatest()
	end

	local panel: OutputPanel

	local function ApplyExpanded()
		root.Size = UDim2.fromScale(1, if isExpanded then EXPANDED_HEIGHT_SCALE else COLLAPSED_HEIGHT_SCALE)
		card:SetCornerScale(if isExpanded then EXPANDED_CORNER_SCALE else COLLAPSED_CORNER_SCALE)
		-- Keep the bar the same height in both states.
		local barScale = if isExpanded then COLLAPSED_HEIGHT_SCALE / EXPANDED_HEIGHT_SCALE else 1
		bar.Size = UDim2.fromScale(1, barScale)
		well.Root.Size = UDim2.fromScale(0.99, 1 - barScale - 0.03)
		well.Root.Visible = isExpanded
		toggleButton:SetIcon(if isExpanded then "PanelClose" else "PanelOpen")
		latestButton.Visible = not isExpanded or not isCompact
		if isExpanded then
			stickToBottom = true
			task.defer(ScrollToBottom)
		end
	end

	-- Wiring -------------------------------------------------------------------
	local addedConnection = Log.Added:Connect(function(entry: Log.Entry)
		AddEntryLabel(entry)
		RenderCounts()
		RenderLatest()
		if
			entry.Level == "Error"
			and not isExpanded
			and settings:GetBoolean(Dialogs.SETTING_OUTPUT_OPEN_ON_ERROR, true)
		then
			panel:SetExpanded(true)
		end
	end)
	local clearedConnection = Log.Cleared:Connect(function()
		for _, label in entryLabels do
			label:Destroy()
		end
		table.clear(entryLabels)
		table.clear(entryOrder)
		emptyLabel.Visible = true
		RenderCounts()
		RenderLatest()
	end)
	local themeConnection = Theme.Changed:Connect(function(_palette: Palette.Palette)
		RerenderAll()
	end)

	local function UpdateConnectionVisibility()
		connectionLabel.Visible = not isCompact and bar.AbsoluteSize.X >= CONNECTION_MIN_BAR_WIDTH
	end
	bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateConnectionVisibility)

	scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local maxY = scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y
		stickToBottom = scroller.CanvasPosition.Y >= maxY - STICK_TO_BOTTOM_TOLERANCE
	end)
	scroller:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		if stickToBottom then
			ScrollToBottom()
		end
	end)

	toggleButton.Activated:Connect(function()
		panel:Toggle()
	end)
	latestButton.Activated:Connect(function()
		panel:SetExpanded(true)
	end)
	clearButton.Activated:Connect(function()
		Log.Clear()
	end)
	copyButton.Activated:Connect(function()
		Dialogs.ShowText("Output log", if #Log.Entries() == 0 then "(empty)" else Log.ToText())
	end)

	panel = {
		Root = root,

		SetConnection = function(_self: OutputPanel, text: string, isWarning: boolean)
			connectionLabel.Text = text
			Theme.Bind(connectionLabel, "TextColor3", if isWarning then "Warning" else "TextMuted")
		end,

		RefreshBudgets = function(_self: OutputPanel)
			local function Format(name: string, budget: number?): string
				if budget == nil then
					return `{name} -`
				end
				local text = `{name} {budget}`
				return if budget <= LOW_BUDGET then Typography.ColorTag(text, Theme.Current().Warning) else text
			end
			local names = if isCompact then { "R", "W", "L" } else { "read", "write", "list" }
			budgetLabel.Text = table.concat({
				Format(names[1], DataStoreGateway.GetBudget("Read")),
				Format(names[2], DataStoreGateway.GetBudget("Write")),
				Format(names[3], DataStoreGateway.GetBudget("List")),
			}, "  ")
		end,

		SetExpanded = function(_self: OutputPanel, expanded: boolean)
			if isExpanded == expanded then
				return
			end
			isExpanded = expanded
			settings:SetBoolean(OutputPanel.SETTING_EXPANDED, expanded)
			ApplyExpanded()
		end,

		Toggle = function(self: OutputPanel)
			self:SetExpanded(not isExpanded)
		end,

		SetCompact = function(_self: OutputPanel, compact: boolean)
			isCompact = compact
			UpdateConnectionVisibility()
			toggleButton.Root.Size = UDim2.fromScale(if compact then 0.2 else 0.1, 1)
			ApplyExpanded()
		end,

		Destroy = function(_self: OutputPanel)
			addedConnection:Disconnect()
			clearedConnection:Disconnect()
			themeConnection:Disconnect()
		end,
	}

	for _, entry in Log.Entries() do
		AddEntryLabel(entry)
	end
	RenderCounts()
	RenderLatest()
	ApplyExpanded()
	return panel
end

return OutputPanel
