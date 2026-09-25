--!strict
--[[
	Button
	A glass push button. Hover brightens it, pressing scales it to 97% for
	100 ms so feedback feels immediate.

	Variants:
	  Default - raised glass, primary text
	  Primary - accent fill, for the one main action in a view
	  Danger  - danger fill, for confirming destructive actions
	  Ghost   - no fill until hovered, for low-emphasis actions in dense rows
]]

local Create = require(script.Parent.Parent.Create)
local Icon = require(script.Parent.Icon)
local Motion = require(script.Parent.Parent.Motion)
local Signal = require(script.Parent.Parent.Parent.Core.Signal)
local Surface = require(script.Parent.Parent.Surface)
local Theme = require(script.Parent.Parent.Parent.Theme.Theme)
local Tooltip = require(script.Parent.Tooltip)
local Typography = require(script.Parent.Parent.Typography)

export type Variant = "Default" | "Primary" | "Danger" | "Ghost"

export type ButtonProps = {
	Name: string?,
	Text: string?,
	Icon: string?,
	Variant: Variant?,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	-- Icon-only buttons: width follows height (square).
	Square: boolean?,
	CornerScale: number?,
	Tooltip: string?,
	-- Overrides the icon/text color token (e.g. "Danger" for a delete icon).
	Color: Theme.Token?,
	OnActivated: (() -> ())?,
	Parent: Instance?,
}

export type Button = {
	Root: TextButton,
	Activated: Signal.Signal<>,
	SetEnabled: (self: Button, isEnabled: boolean) -> (),
	SetText: (self: Button, text: string) -> (),
	SetIcon: (self: Button, name: string) -> (),
	SetBusy: (self: Button, isBusy: boolean, busyText: string?) -> (),
	-- A "latched" look for toggle buttons (accent tint and icon).
	SetSelected: (self: Button, isSelected: boolean) -> (),
	SetVariant: (self: Button, variant: Variant) -> (),
	IsEnabled: (self: Button) -> boolean,
}

local LABEL_RATIO = 0.44
local MAX_LABEL_SIZE = 14
-- Smallest size a label may shrink to before an icon button hides it.
local MIN_FITTED_LABEL_SIZE = 10
-- Breathing room inside the button on each side, as a fraction of its width.
local HORIZONTAL_PADDING_SCALE = 0.08
local ICON_HEIGHT_SCALE = 0.54
-- Icon-to-label gap as a fraction of the button height.
local CONTENT_GAP_RATIO = 0.2
local DEFAULT_CORNER_SCALE = 0.26
local DISABLED_TRANSPARENCY = 0.45

local ButtonComponent = {}

local function ForegroundToken(variant: Variant, override: Theme.Token?, isSelected: boolean): Theme.Token
	if variant == "Primary" or variant == "Danger" then
		return "TextOnAccent"
	end
	if isSelected then
		return "Accent"
	end
	return override or "TextPrimary"
end

function ButtonComponent.new(props: ButtonProps): Button
	local variant: Variant = props.Variant or "Default"
	local cornerScale = props.CornerScale or DEFAULT_CORNER_SCALE
	local isEnabled = true
	local isBusy = false
	local isSelected = false
	local isHovered = false
	local idleText = props.Text or ""

	local root: TextButton = Create("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	})
	if props.Square then
		Surface.Aspect(1).Parent = root
	end
	local scale: UIScale = Create("UIScale", { Parent = root })

	local surface = Surface.Raised({
		Name = "Glass",
		Size = UDim2.fromScale(1, 1),
		CornerScale = cornerScale,
		Elevation = if variant == "Ghost" then "Flat" else "Low",
		Parent = root,
	})

	-- Hover and selection share one tint layer above the glass.
	local tint: Frame = Create("Frame", {
		Name = "Tint",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = { Create("UICorner", { CornerRadius = UDim.new(cornerScale, 0) }) },
		Parent = surface.Content,
	})

	local row: Frame = Create("Frame", {
		Name = "Row",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = surface.Content,
	})

	local icon: Icon.Icon? = nil
	if props.Icon then
		icon = Icon.new({
			Name = props.Icon,
			Size = UDim2.fromScale(1, ICON_HEIGHT_SCALE),
			LayoutOrder = 0,
			Parent = row,
		})
	end

	local gap: Frame = Create("Frame", {
		Name = "Gap",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Visible = props.Icon ~= nil and idleText ~= "",
		Children = { Surface.Aspect(CONTENT_GAP_RATIO) },
		Parent = row,
	})

	local label: TextLabel = Create("TextLabel", {
		Name = "Label",
		Text = idleText,
		Visible = idleText ~= "",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = Typography.FONT_MEDIUM,
		LayoutOrder = 2,
		Parent = row,
	})

	--[[
		Sizes the label so the button's content always fits inside it:
		  1. text size follows the button's height (like every other label),
		  2. if the icon + text is wider than the button, the text shrinks,
		  3. if it would have to shrink below a readable size, an icon button
		     drops its label (the tooltip still names it) instead of clipping.
	]]
	local function FitContent()
		local width = root.AbsoluteSize.X
		local height = root.AbsoluteSize.Y
		local hasText = label.Text ~= ""
		if width <= 0 or height <= 0 or not hasText then
			label.Visible = hasText
			gap.Visible = icon ~= nil and hasText
			return
		end
		label.Visible = true
		gap.Visible = icon ~= nil
		local baseSize = math.clamp(math.round(height * LABEL_RATIO), Typography.MIN_TEXT_SIZE, MAX_LABEL_SIZE)
		label.TextSize = baseSize
		local reserved = if icon then height * (ICON_HEIGHT_SCALE + CONTENT_GAP_RATIO) else 0
		local available = width * (1 - 2 * HORIZONTAL_PADDING_SCALE) - reserved
		local needed = label.TextBounds.X
		if needed <= available or needed <= 0 then
			return
		end
		local fittedSize = math.floor(baseSize * available / needed)
		if fittedSize < MIN_FITTED_LABEL_SIZE and icon then
			label.Visible = false
			gap.Visible = false
		else
			label.TextSize = math.max(fittedSize, MIN_FITTED_LABEL_SIZE)
		end
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(FitContent)
	task.defer(FitContent)

	local function Restyle()
		local foreground = ForegroundToken(variant, props.Color, isSelected)
		Theme.Bind(label, "TextColor3", foreground)
		if icon then
			local iconColor: Theme.Token = if variant == "Default"
					and not isSelected
					and props.Color == nil
				then "Icon"
				else foreground
			icon:SetColor(iconColor)
			icon.Root.ImageTransparency = if isEnabled then 0 else DISABLED_TRANSPARENCY
		end
		label.TextTransparency = if isEnabled then 0 else DISABLED_TRANSPARENCY
		surface:SetFill(if variant == "Primary" then "Accent" elseif variant == "Danger" then "Danger" else "Surface")
		surface:SetElevation(if variant == "Ghost" then "Flat" else "Low")

		local tintToken = if isSelected then "Selection" else "Hover"
		local opacityToken = if isSelected then "SelectionOpacity" else "HoverOpacity"
		local isTinted = isSelected or (isHovered and isEnabled)
		Theme.Bind(tint, "BackgroundColor3", tintToken)
		Theme.Bind(tint, "BackgroundTransparency", Surface.TintTransparency(opacityToken, isTinted), true)
		local target = if isTinted then 1 - (Theme.Current() :: any)[opacityToken] else 1
		Motion.Tween(tint, Motion.FAST, { BackgroundTransparency = target })
	end

	local activated = Signal.new() :: Signal.Signal<>

	local function Release()
		Motion.Tween(scale, Motion.FAST, { Scale = 1 })
		surface:SetPressed(false)
	end

	root.MouseEnter:Connect(function()
		isHovered = true
		Restyle()
	end)
	root.MouseLeave:Connect(function()
		isHovered = false
		Release()
		Restyle()
	end)
	root.MouseButton1Down:Connect(function()
		if isEnabled and not isBusy then
			Motion.Tween(scale, Motion.FAST, { Scale = Motion.PRESSED_SCALE })
			surface:SetPressed(true)
		end
	end)
	root.MouseButton1Up:Connect(Release)
	root.Activated:Connect(function()
		if isEnabled and not isBusy then
			activated:Fire()
		end
	end)
	if props.OnActivated then
		activated:Connect(props.OnActivated)
	end
	if props.Tooltip then
		Tooltip.Attach(root, props.Tooltip)
	end

	local button: Button
	button = {
		Root = root,
		Activated = activated,

		SetEnabled = function(_self: Button, enabled: boolean)
			if isEnabled == enabled then
				return
			end
			isEnabled = enabled
			root.Active = enabled
			Restyle()
		end,

		SetText = function(_self: Button, text: string)
			idleText = text
			if not isBusy then
				label.Text = text
			end
			FitContent()
		end,

		SetIcon = function(_self: Button, name: string)
			if icon then
				icon:SetIcon(name)
			end
		end,

		SetBusy = function(_self: Button, busy: boolean, busyText: string?)
			isBusy = busy
			label.Text = if busy and busyText then busyText else idleText
			root.Active = isEnabled and not busy
			FitContent()
		end,

		SetSelected = function(_self: Button, selected: boolean)
			isSelected = selected
			Restyle()
		end,

		SetVariant = function(_self: Button, newVariant: Variant)
			variant = newVariant
			Restyle()
		end,

		IsEnabled = function(_self: Button): boolean
			return isEnabled
		end,
	}

	Restyle()
	if props.Parent then
		root.Parent = props.Parent
	end
	return button
end

return ButtonComponent
