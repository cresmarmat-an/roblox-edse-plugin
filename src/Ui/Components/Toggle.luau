--!strict
--[[
	Toggle
	A switch: a sunken glass pill track and a solid round knob. The track
	fills with the accent color when on, and the knob glides across.
]]

local Create = require(script.Parent.Parent.Create)
local Motion = require(script.Parent.Parent.Motion)
local Surface = require(script.Parent.Parent.Surface)
local Tooltip = require(script.Parent.Tooltip)

export type ToggleProps = {
	Name: string?,
	Size: UDim2,
	LayoutOrder: number?,
	IsOn: boolean,
	Tooltip: string?,
	OnChanged: ((isOn: boolean) -> ())?,
	Parent: Instance?,
}

export type Toggle = {
	Root: TextButton,
	SetOn: (self: Toggle, isOn: boolean, animate: boolean?) -> (),
	IsOn: (self: Toggle) -> boolean,
}

local TRACK_ASPECT = 1.75
local KNOB_HEIGHT_SCALE = 0.72
local KNOB_EDGE_SCALE = 0.08

local ToggleComponent = {}

function ToggleComponent.new(props: ToggleProps): Toggle
	local isOn = props.IsOn

	local root: TextButton = Create("TextButton", {
		Name = props.Name or "Toggle",
		Size = props.Size,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Children = { Surface.Aspect(TRACK_ASPECT) },
	})

	local track = Surface.Inset({ Name = "Track", Size = UDim2.fromScale(1, 1), CornerScale = 0.5, Parent = root })
	local fill: Frame = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "Accent" },
		Children = { Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) },
		Parent = track.Content,
	})

	local knob: Frame = Create("Frame", {
		Name = "Knob",
		Size = UDim2.fromScale(1, KNOB_HEIGHT_SCALE),
		ZIndex = 2,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Children = {
			Surface.Aspect(1),
			Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			-- A faint outline keeps the white knob visible on light tracks.
			Create("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Thickness = 1,
				Transparency = 0.8,
				Theme = { Color = "Shadow" },
			}),
		},
		Parent = track.Content,
	})

	local toggle: Toggle
	toggle = {
		Root = root,

		SetOn = function(_self: Toggle, on: boolean, animate: boolean?)
			isOn = on
			local goals = {
				AnchorPoint = Vector2.new(if on then 1 else 0, 0.5),
				Position = UDim2.fromScale(if on then 1 - KNOB_EDGE_SCALE else KNOB_EDGE_SCALE, 0.5),
			}
			local fillTransparency = if on then 0 else 1
			if animate then
				Motion.Tween(knob, Motion.BASE, goals)
				Motion.Tween(fill, Motion.BASE, { BackgroundTransparency = fillTransparency })
			else
				knob.AnchorPoint = goals.AnchorPoint
				knob.Position = goals.Position
				fill.BackgroundTransparency = fillTransparency
			end
		end,

		IsOn = function(_self: Toggle): boolean
			return isOn
		end,
	}

	root.Activated:Connect(function()
		toggle:SetOn(not isOn, true)
		if props.OnChanged then
			props.OnChanged(isOn)
		end
	end)
	if props.Tooltip then
		Tooltip.Attach(root, props.Tooltip)
	end

	toggle:SetOn(isOn, false)
	if props.Parent then
		root.Parent = props.Parent
	end
	return toggle
end

return ToggleComponent
