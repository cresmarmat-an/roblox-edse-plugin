--!strict
--[[
	Segmented
	A segmented control: a sunken glass track with a raised glass thumb that
	glides to the chosen option. Used for tabs, the theme switch and the
	store-type picker.
]]

local Create = require(script.Parent.Parent.Create)
local Motion = require(script.Parent.Parent.Motion)
local Surface = require(script.Parent.Parent.Surface)
local Theme = require(script.Parent.Parent.Parent.Theme.Theme)
local Tooltip = require(script.Parent.Tooltip)
local Typography = require(script.Parent.Parent.Typography)

export type SegmentOption = {
	Value: string,
	Label: string,
	Tooltip: string?,
}

export type SegmentedProps = {
	Name: string?,
	Options: { SegmentOption },
	Value: string,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	OnChanged: ((value: string) -> ())?,
	Parent: Instance?,
}

export type Segmented = {
	Root: Frame,
	SetValue: (self: Segmented, value: string, animate: boolean?) -> (),
	GetValue: (self: Segmented) -> string,
	SetOptionVisible: (self: Segmented, value: string, isVisible: boolean) -> (),
}

local TRACK_PADDING_VERTICAL = 0.1
local TRACK_PADDING_HORIZONTAL = 0.008
-- Label box inside each segment; the text shrinks to fit it, up to MAX.
local LABEL_WIDTH_SCALE = 0.86
local LABEL_HEIGHT_SCALE = 0.56
local MAX_LABEL_SIZE = 13

local SegmentedComponent = {}

function SegmentedComponent.new(props: SegmentedProps): Segmented
	local currentValue = props.Value
	local hiddenValues: { [string]: boolean } = {}

	local track = Surface.Inset({
		Name = props.Name or "Segmented",
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		CornerScale = 0.3,
	})
	local inner: Frame = Create("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Create("UIPadding", {
				PaddingTop = UDim.new(TRACK_PADDING_VERTICAL, 0),
				PaddingBottom = UDim.new(TRACK_PADDING_VERTICAL, 0),
				PaddingLeft = UDim.new(TRACK_PADDING_HORIZONTAL, 0),
				PaddingRight = UDim.new(TRACK_PADDING_HORIZONTAL, 0),
			}),
		},
		Parent = track.Content,
	})

	local thumb = Surface.Raised({
		Name = "Thumb",
		Size = UDim2.fromScale(1 / #props.Options, 1),
		CornerScale = 0.26,
		Elevation = "Low",
		Parent = inner,
	})

	local buttonRow: Frame = Create("Frame", {
		Name = "Options",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = inner,
	})

	type OptionView = { Button: TextButton, Label: TextLabel }
	local optionViews: { [string]: OptionView } = {}

	local segmented: Segmented

	local function VisibleOptions(): { SegmentOption }
		local visible = {}
		for _, option in props.Options do
			if not hiddenValues[option.Value] then
				table.insert(visible, option)
			end
		end
		return visible
	end

	local function Layout(animate: boolean)
		local visible = VisibleOptions()
		local count = math.max(#visible, 1)
		local selectedIndex = 1
		for index, option in visible do
			local view = optionViews[option.Value]
			view.Button.Size = UDim2.fromScale(1 / count, 1)
			view.Button.LayoutOrder = index
			local isSelected = option.Value == currentValue
			if isSelected then
				selectedIndex = index
			end
			Theme.Bind(view.Label, "TextColor3", if isSelected then "TextPrimary" else "TextSecondary")
			view.Label.FontFace = if isSelected then Typography.FONT_SEMIBOLD else Typography.FONT_MEDIUM
		end
		local goals = {
			Size = UDim2.fromScale(1 / count, 1),
			Position = UDim2.fromScale((selectedIndex - 1) / count, 0),
		}
		if animate then
			Motion.Tween(thumb.Root, Motion.BASE, goals)
		else
			thumb.Root.Size = goals.Size
			thumb.Root.Position = goals.Position
		end
	end

	for index, option in props.Options do
		local button: TextButton = Create("TextButton", {
			Name = option.Value,
			Size = UDim2.fromScale(1 / #props.Options, 1),
			LayoutOrder = index,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Parent = buttonRow,
		})
		local label: TextLabel = Create("TextLabel", {
			Name = "Label",
			Text = option.Label,
			Size = UDim2.fromScale(LABEL_WIDTH_SCALE, LABEL_HEIGHT_SCALE),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			FontFace = Typography.FONT_MEDIUM,
			Parent = button,
		})
		Typography.ScaleToFit(label, MAX_LABEL_SIZE)
		local view: OptionView = { Button = button, Label = label }
		if option.Tooltip then
			Tooltip.Attach(button, option.Tooltip)
		end
		button.Activated:Connect(function()
			if currentValue ~= option.Value then
				segmented:SetValue(option.Value, true)
				if props.OnChanged then
					props.OnChanged(option.Value)
				end
			end
		end)
		optionViews[option.Value] = view
	end

	segmented = {
		Root = track.Root,

		SetValue = function(_self: Segmented, value: string, animate: boolean?)
			currentValue = value
			Layout(animate == true)
		end,

		GetValue = function(_self: Segmented): string
			return currentValue
		end,

		SetOptionVisible = function(_self: Segmented, value: string, isVisible: boolean)
			if isVisible then
				hiddenValues[value] = nil
			else
				hiddenValues[value] = true
			end
			local view = optionViews[value]
			if view then
				view.Button.Visible = isVisible
			end
			Layout(false)
		end,
	}

	Layout(false)
	if props.Parent then
		track.Root.Parent = props.Parent
	end
	return segmented
end

return SegmentedComponent
