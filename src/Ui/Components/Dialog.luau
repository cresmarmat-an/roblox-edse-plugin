--!strict
--[[
	Dialog
	Modal dialogs that yield until the user picks an action:

	  local confirmed = Dialog.Confirm({ Title = "Delete key?", Message = "...", IsDanger = true })

	Clicking the dimmed backdrop dismisses (returns DismissResult). Only one
	dialog shows at a time; opening another resolves the current one with its
	DismissResult first.
]]

local Button = require(script.Parent.Button)
local Create = require(script.Parent.Parent.Create)
local Label = require(script.Parent.Label)
local Motion = require(script.Parent.Parent.Motion)
local Surface = require(script.Parent.Parent.Surface)
local Theme = require(script.Parent.Parent.Parent.Theme.Theme)
local Typography = require(script.Parent.Parent.Typography)

export type Action = {
	Text: string,
	Variant: Button.Variant?,
	Result: any,
}

export type DialogOptions = {
	Title: string,
	Message: string?,
	-- Card size as a fraction of the widget; clamped to a readable range.
	Size: UDim2?,
	-- Builds custom content. `resolve` closes the dialog with a result.
	BuildBody: ((body: Frame, resolve: (result: any) -> ()) -> ())?,
	Actions: { Action },
	DismissResult: any,
}

export type ConfirmOptions = {
	Title: string,
	Message: string,
	ConfirmText: string?,
	CancelText: string?,
	IsDanger: boolean?,
}

local DEFAULT_SIZE = UDim2.fromScale(0.6, 0.42)
-- Comfortable card size range in pixels. It is only used to pick the card's
-- *scale* for the current widget size, so a dialog is never cramped in a
-- small widget nor sprawling in a large one.
local COMFORTABLE_WIDTH = NumberRange.new(340, 640)
local COMFORTABLE_HEIGHT = NumberRange.new(200, 560)
-- A dialog never covers more than this much of the widget.
local MAX_SCALE = 0.94
local OPEN_SCALE = 0.96

-- The card's size as a fraction of the host, from the requested fraction
-- nudged into the comfortable pixel range.
local function CardScale(requested: UDim2, hostSize: Vector2): UDim2
	local function Axis(requestedScale: number, hostPixels: number, comfortable: NumberRange): number
		if hostPixels <= 0 then
			return requestedScale
		end
		local pixels = math.clamp(requestedScale * hostPixels, comfortable.Min, comfortable.Max)
		return math.min(pixels / hostPixels, MAX_SCALE)
	end
	return UDim2.fromScale(
		Axis(requested.X.Scale, hostSize.X, COMFORTABLE_WIDTH),
		Axis(requested.Y.Scale, hostSize.Y, COMFORTABLE_HEIGHT)
	)
end

local Dialog = {}

local host: GuiObject? = nil
local closeCurrent: (() -> ())? = nil

function Dialog.SetHost(newHost: GuiObject)
	host = newHost
end

function Dialog.IsOpen(): boolean
	return closeCurrent ~= nil
end

function Dialog.Show(options: DialogOptions): any
	local currentHost = host
	if currentHost == nil then
		return options.DismissResult
	end
	if closeCurrent then
		closeCurrent()
	end

	local thread = coroutine.running()
	local isResolved = false

	local overlay: Frame = Create("Frame", {
		Name = "DialogOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = currentHost,
	})
	local scrim: TextButton = Create("TextButton", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "Scrim" },
		Parent = overlay,
	})
	Motion.Tween(scrim, Motion.ENTER, { BackgroundTransparency = 1 - Theme.Current().ScrimOpacity })

	local cardScale: UIScale = Create("UIScale", { Scale = OPEN_SCALE })
	local card: Frame = Create("Frame", {
		Name = "Card",
		Size = CardScale(options.Size or DEFAULT_SIZE, currentHost.AbsoluteSize),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Children = { cardScale },
		Parent = overlay,
	})
	Motion.Tween(cardScale, Motion.ENTER, { Scale = 1 })

	local surface = Surface.Raised({
		Name = "Surface",
		Size = UDim2.fromScale(1, 1),
		CornerScale = 0.06,
		Elevation = "Floating",
		Parent = card,
	})
	-- Swallow clicks on the card so they don't reach the scrim.
	Create("TextButton", {
		Name = "Blocker",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Parent = surface.Content,
	})

	local layout: Frame = Create("Frame", {
		Name = "Layout",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Children = {
			Surface.Padding(0.05, 0.07),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.04, 0),
			}),
		},
		Parent = surface.Content,
	})

	Label.new({
		Name = "Title",
		Text = options.Title,
		Size = UDim2.fromScale(1, 0.13),
		Font = Typography.FONT_BOLD,
		Ratio = 0.8,
		MaxTextSize = 20,
		LayoutOrder = 1,
		Parent = layout,
	})

	local body: Frame = Create("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 0.5),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Children = { Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) },
		Parent = layout,
	})

	local actionRow: Frame = Create("Frame", {
		Name = "Actions",
		Size = UDim2.fromScale(1, 0.15),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.025, 0),
			}),
		},
		Parent = layout,
	})

	local function Resolve(result: any)
		if isResolved then
			return
		end
		isResolved = true
		closeCurrent = nil
		Motion.Tween(scrim, Motion.EXIT, { BackgroundTransparency = 1 })
		Motion.Tween(cardScale, Motion.EXIT, { Scale = OPEN_SCALE })
		card.Visible = false
		task.delay(Motion.EXIT.Time, function()
			overlay:Destroy()
		end)
		task.spawn(thread, result)
	end
	closeCurrent = function()
		Resolve(options.DismissResult)
	end
	scrim.Activated:Connect(function()
		Resolve(options.DismissResult)
	end)

	if options.Message then
		Label.new({
			Name = "Message",
			Text = options.Message,
			Size = UDim2.fromScale(1, 1),
			Color = "TextSecondary",
			Wrapped = true,
			YAlignment = Enum.TextYAlignment.Top,
			Ratio = 0.16,
			MinTextSize = 13,
			MaxTextSize = 15,
			Parent = body,
		})
	end
	if options.BuildBody then
		options.BuildBody(body, Resolve)
	end

	local actionCount = #options.Actions
	for index, action in options.Actions do
		Button.new({
			Name = action.Text,
			Text = action.Text,
			Variant = action.Variant or "Default",
			Size = UDim2.fromScale(math.min(0.3, 0.9 / actionCount), 1),
			LayoutOrder = index,
			OnActivated = function()
				Resolve(action.Result)
			end,
			Parent = actionRow,
		})
	end

	return coroutine.yield()
end

function Dialog.Confirm(options: ConfirmOptions): boolean
	local result = Dialog.Show({
		Title = options.Title,
		Message = options.Message,
		Size = UDim2.fromScale(0.5, 0.34),
		Actions = {
			{ Text = options.CancelText or "Cancel", Variant = "Ghost", Result = false },
			{
				Text = options.ConfirmText or "Confirm",
				Variant = if options.IsDanger then "Danger" else "Primary",
				Result = true,
			},
		},
		DismissResult = false,
	})
	return result == true
end

function Dialog.CloseAll()
	if closeCurrent then
		closeCurrent()
	end
end

return Dialog
