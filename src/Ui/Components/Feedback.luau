--!strict
--[[
	Feedback
	Loading and empty states: a three-dot pulse for work in progress, and a
	centered message (with an optional action) for empty or error views.
]]

local Button = require(script.Parent.Button)
local Create = require(script.Parent.Parent.Create)
local Icon = require(script.Parent.Icon)
local Label = require(script.Parent.Label)
local Surface = require(script.Parent.Parent.Surface)
local Typography = require(script.Parent.Parent.Typography)

export type EmptyStateProps = {
	Name: string?,
	Icon: string?,
	Title: string,
	Body: string?,
	ActionText: string?,
	OnAction: (() -> ())?,
	Parent: Instance?,
}

export type EmptyState = {
	Root: Frame,
	Set: (self: EmptyState, title: string, body: string?) -> (),
}

local DOT_COUNT = 3
local PULSE_SECONDS = 0.42

local Feedback = {}

-- Three dots that pulse in sequence. Destroy the returned frame to stop.
function Feedback.LoadingDots(size: UDim2, parent: Instance?): Frame
	local root: Frame = Create("Frame", {
		Name = "LoadingDots",
		Size = size,
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.06, 0),
			}),
		},
	})
	for index = 1, DOT_COUNT do
		local dot: Frame = Create("Frame", {
			Name = `Dot{index}`,
			Size = UDim2.fromScale(1, 0.34),
			LayoutOrder = index,
			BackgroundTransparency = 0.7,
			Theme = { BackgroundColor3 = "Accent" },
			Children = { Surface.Aspect(1), Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) },
			Parent = root,
		})
		local pulse = TweenInfo.new(
			PULSE_SECONDS,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true,
			(index - 1) * PULSE_SECONDS / DOT_COUNT
		)
		game:GetService("TweenService"):Create(dot, pulse, { BackgroundTransparency = 0.05 }):Play()
	end
	if parent then
		root.Parent = parent
	end
	return root
end

function Feedback.EmptyState(props: EmptyStateProps): EmptyState
	local root: Frame = Create("Frame", {
		Name = props.Name or "EmptyState",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Surface.Padding(0.08, 0.1),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.025, 0),
			}),
		},
	})

	if props.Icon then
		Icon.new({
			Name = props.Icon,
			Size = UDim2.fromScale(1, 0.12),
			LayoutOrder = 1,
			Color = "TextMuted",
			Parent = root,
		}).Root.Name =
			"Illustration"
	end

	local title = Label.new({
		Name = "Title",
		Text = props.Title,
		Size = UDim2.fromScale(1, 0.07),
		Font = Typography.FONT_SEMIBOLD,
		XAlignment = Enum.TextXAlignment.Center,
		Ratio = 0.7,
		MaxTextSize = 18,
		LayoutOrder = 2,
		Parent = root,
	})
	local body = Label.new({
		Name = "Body",
		Text = props.Body or "",
		Size = UDim2.fromScale(1, 0.16),
		Color = "TextSecondary",
		XAlignment = Enum.TextXAlignment.Center,
		YAlignment = Enum.TextYAlignment.Top,
		Wrapped = true,
		Ratio = 0.22,
		MinTextSize = 12,
		MaxTextSize = 14,
		LayoutOrder = 3,
		Parent = root,
	})
	body.Visible = props.Body ~= nil

	if props.ActionText and props.OnAction then
		Button.new({
			Name = "Action",
			Text = props.ActionText,
			Variant = "Primary",
			Size = UDim2.fromScale(0.36, 0.08),
			LayoutOrder = 4,
			OnActivated = props.OnAction,
			Parent = root,
		})
	end

	local emptyState: EmptyState = {
		Root = root,
		Set = function(_self: EmptyState, newTitle: string, newBody: string?)
			title.Text = newTitle
			body.Text = newBody or ""
			body.Visible = newBody ~= nil
		end,
	}

	if props.Parent then
		root.Parent = props.Parent
	end
	return emptyState
end

return Feedback
