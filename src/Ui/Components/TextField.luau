--!strict
--[[
	TextField
	A sunken glass input with an optional leading icon and a clear button.
	Focus draws a thin accent ring; an invalid state turns it red.
]]

local Create = require(script.Parent.Parent.Create)
local Icon = require(script.Parent.Icon)
local Icons = require(script.Parent.Parent.Parent.Theme.Icons)
local Motion = require(script.Parent.Parent.Motion)
local Surface = require(script.Parent.Parent.Surface)
local Theme = require(script.Parent.Parent.Parent.Theme.Theme)
local Typography = require(script.Parent.Parent.Typography)

export type TextFieldProps = {
	Name: string?,
	Size: UDim2,
	Position: UDim2?,
	LayoutOrder: number?,
	Placeholder: string?,
	Text: string?,
	Icon: string?,
	IsMonospace: boolean?,
	ShowClearButton: boolean?,
	CornerScale: number?,
	OnChanged: ((text: string) -> ())?,
	OnSubmit: ((text: string) -> ())?,
	OnFocusChanged: ((isFocused: boolean) -> ())?,
	Parent: Instance?,
}

export type TextField = {
	Root: Frame,
	TextBox: TextBox,
	SetText: (self: TextField, text: string) -> (),
	GetText: (self: TextField) -> string,
	Focus: (self: TextField) -> (),
	SetInvalid: (self: TextField, isInvalid: boolean) -> (),
}

local TEXT_RATIO = 0.46
local ICON_HEIGHT_SCALE = 0.48
local CLEAR_HEIGHT_SCALE = 0.44
local FOCUS_RING_THICKNESS = 1
local FOCUS_RING_TRANSPARENCY = 0.2
-- Inner horizontal padding as a fraction of the field's width.
local HORIZONTAL_PADDING_SCALE = 0.025

local TextFieldComponent = {}

function TextFieldComponent.new(props: TextFieldProps): TextField
	local cornerScale = props.CornerScale or 0.26
	local isFocused = false
	local isInvalid = false

	local root: Frame = Create("Frame", {
		Name = props.Name or "TextField",
		Size = props.Size,
		Position = props.Position or UDim2.fromScale(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
	})

	local well =
		Surface.Inset({ Name = "Well", Size = UDim2.fromScale(1, 1), CornerScale = cornerScale, Parent = root })

	local ring: UIStroke = Create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = FOCUS_RING_THICKNESS,
		Transparency = 1,
	})
	Create("Frame", {
		Name = "FocusRing",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Children = { Create("UICorner", { CornerRadius = UDim.new(cornerScale, 0) }), ring },
		Parent = root,
	})

	local row: Frame = Create("Frame", {
		Name = "Row",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Create("UIPadding", {
				PaddingLeft = UDim.new(HORIZONTAL_PADDING_SCALE, 0),
				PaddingRight = UDim.new(HORIZONTAL_PADDING_SCALE * 0.6, 0),
			}),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.015, 0),
			}),
		},
		Parent = well.Content,
	})

	if props.Icon then
		Icon.new({
			Name = props.Icon,
			Size = UDim2.fromScale(1, ICON_HEIGHT_SCALE),
			LayoutOrder = 1,
			Color = "TextMuted",
			Parent = row,
		})
	end

	local textBox: TextBox = Create("TextBox", {
		Name = "Input",
		Size = UDim2.fromScale(0.5, 1),
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Text = props.Text or "",
		PlaceholderText = props.Placeholder or "",
		FontFace = if props.IsMonospace then Typography.FONT_MONO else Typography.FONT_REGULAR,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.None,
		ClipsDescendants = true,
		Theme = { TextColor3 = "TextPrimary", PlaceholderColor3 = "TextMuted" },
		Children = { Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) },
		Parent = row,
	})
	Typography.Fit(textBox, TEXT_RATIO, 12, 15)

	local clearButton: ImageButton = Create("ImageButton", {
		Name = "Clear",
		Size = UDim2.fromScale(1, CLEAR_HEIGHT_SCALE),
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Image = Icons.AssetOrBlank("Clear"),
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		Theme = { ImageColor3 = "TextMuted" },
		Children = { Surface.Aspect(1) },
		Parent = if props.ShowClearButton then row else nil,
	})

	local function UpdateRing()
		local isVisible = isFocused or isInvalid
		Theme.Bind(ring, "Color", if isInvalid then "Danger" else "Accent")
		Motion.Tween(ring, Motion.FAST, { Transparency = if isVisible then FOCUS_RING_TRANSPARENCY else 1 })
	end

	textBox.Focused:Connect(function()
		isFocused = true
		UpdateRing()
		if props.OnFocusChanged then
			props.OnFocusChanged(true)
		end
	end)
	textBox.FocusLost:Connect(function(enterPressed: boolean)
		isFocused = false
		UpdateRing()
		if props.OnFocusChanged then
			props.OnFocusChanged(false)
		end
		if enterPressed and props.OnSubmit then
			props.OnSubmit(textBox.Text)
		end
	end)
	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		clearButton.Visible = textBox.Text ~= ""
		if props.OnChanged then
			props.OnChanged(textBox.Text)
		end
	end)
	clearButton.Activated:Connect(function()
		textBox.Text = ""
		textBox:CaptureFocus()
	end)

	local field: TextField = {
		Root = root,
		TextBox = textBox,

		SetText = function(_self: TextField, text: string)
			textBox.Text = text
		end,

		GetText = function(_self: TextField): string
			return textBox.Text
		end,

		Focus = function(_self: TextField)
			textBox:CaptureFocus()
		end,

		SetInvalid = function(_self: TextField, invalid: boolean)
			isInvalid = invalid
			UpdateRing()
		end,
	}

	UpdateRing()
	if props.Parent then
		root.Parent = props.Parent
	end
	return field
end

return TextFieldComponent
