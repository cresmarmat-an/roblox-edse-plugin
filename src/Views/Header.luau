--!strict
--[[
	Header
	One compact glass bar: brand, the store picker (placed into StoreSlot by
	App when the widget is wide), the Auto / Light / Dark theme switch and
	settings.
]]

local Button = require(script.Parent.Parent.Ui.Components.Button)
local Create = require(script.Parent.Parent.Ui.Create)
local Icon = require(script.Parent.Parent.Ui.Components.Icon)
local Label = require(script.Parent.Parent.Ui.Components.Label)
local Palette = require(script.Parent.Parent.Theme.Palette)
local Segmented = require(script.Parent.Parent.Ui.Components.Segmented)
local Surface = require(script.Parent.Parent.Ui.Surface)
local Theme = require(script.Parent.Parent.Theme.Theme)
local Typography = require(script.Parent.Parent.Ui.Typography)

export type HeaderProps = {
	LayoutOrder: number,
	OnThemeModeChanged: (mode: Theme.Mode) -> (),
	OnSettings: () -> (),
	Parent: Instance,
}

export type Header = {
	Root: Frame,
	-- Where the store picker lives while the widget is wide.
	StoreSlot: Frame,
	SetCompact: (self: Header, isCompact: boolean) -> (),
	-- Whether the store picker sits in this bar (wide widgets) or its own row.
	SetStoreInline: (self: Header, isInline: boolean) -> (),
}

-- Bar height as a fraction of the main column, and control height as a
-- fraction of the bar.
local BAR_HEIGHT_SCALE = 0.058
local CONTROL_HEIGHT_SCALE = 0.74

local Header = {}

Header.BAR_HEIGHT_SCALE = BAR_HEIGHT_SCALE
Header.CONTROL_HEIGHT_SCALE = CONTROL_HEIGHT_SCALE

function Header.new(props: HeaderProps): Header
	local card = Surface.Raised({
		Name = "Header",
		Size = UDim2.fromScale(1, BAR_HEIGHT_SCALE),
		LayoutOrder = props.LayoutOrder,
		CornerScale = 0.24,
		Parent = props.Parent,
	})

	local row: Frame = Create("Frame", {
		Name = "Row",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Surface.Padding(0.008, 0),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.008, 0),
			}),
		},
		Parent = card.Content,
	})

	Icon.new({
		Name = "Logo",
		Size = UDim2.fromScale(1, 0.56),
		LayoutOrder = 1,
		Color = "Accent",
		Parent = row,
	})

	local brand: Frame = Create("Frame", {
		Name = "Brand",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = row,
	})
	Label.new({
		Name = "Wordmark",
		Text = "EDSE ",
		Size = UDim2.fromScale(0, 0.62),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Typography.FONT_BOLD,
		Ratio = 0.8,
		MaxTextSize = 16,
		LayoutOrder = 1,
		Parent = brand,
	})
	local subtitle = Label.new({
		Name = "Subtitle",
		Text = "Easy DataStore Editor",
		Size = UDim2.fromScale(0, 0.62),
		AutomaticSize = Enum.AutomaticSize.X,
		Color = "TextSecondary",
		Font = Typography.FONT_MEDIUM,
		Ratio = 0.7,
		MaxTextSize = 13,
		LayoutOrder = 2,
		Parent = brand,
	})

	-- A thin divider between the brand and the store picker.
	local divider: Frame = Create("Frame", {
		Name = "Divider",
		Size = UDim2.fromScale(0.0015, 0.5),
		LayoutOrder = 3,
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = function(palette: Palette.Palette): number
				return 1 - palette.DividerOpacity
			end,
		},
		Parent = row,
	})

	local storeSlot: Frame = Create("Frame", {
		Name = "StoreSlot",
		Size = UDim2.fromScale(0.5, CONTROL_HEIGHT_SCALE),
		LayoutOrder = 4,
		BackgroundTransparency = 1,
		Children = { Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) },
		Parent = row,
	})

	Segmented.new({
		Name = "ThemeSwitch",
		Options = {
			{ Value = "System", Label = "Auto", Tooltip = "Follow Studio's theme" },
			{ Value = "Light", Label = "Light", Tooltip = "Light theme" },
			{ Value = "Dark", Label = "Dark", Tooltip = "Dark theme" },
		},
		Value = Theme.GetMode(),
		Size = UDim2.fromScale(0.17, CONTROL_HEIGHT_SCALE),
		LayoutOrder = 5,
		OnChanged = function(value: string)
			props.OnThemeModeChanged(value :: Theme.Mode)
		end,
		Parent = row,
	})

	Button.new({
		Name = "Settings",
		Icon = "Settings",
		Tooltip = "Settings",
		Variant = "Ghost",
		Square = true,
		Size = UDim2.fromScale(1, CONTROL_HEIGHT_SCALE),
		LayoutOrder = 6,
		OnActivated = props.OnSettings,
		Parent = row,
	})

	return {
		Root = card.Root,
		StoreSlot = storeSlot,
		SetCompact = function(_self: Header, isCompact: boolean)
			subtitle.Visible = not isCompact
		end,

		SetStoreInline = function(_self: Header, isInline: boolean)
			divider.Visible = isInline
			storeSlot.Visible = isInline
		end,
	}
end

return Header
