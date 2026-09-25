--!strict
--[[
	Surface
	Glassmorphism surfaces built only from scale-sized frames.

	A glass surface is:
	  * a translucent fill with a gentle top-to-bottom sheen (UIGradient),
	  * a 1px border (a UIGradient on the UIStroke) that, in the dark theme,
	    is brightest along the top edge the way light catches a pane of glass,
	  * a soft shadow of stacked, fading strokes on floating layers (dialogs,
	    popovers) and, in the light theme, on panels, so white glass still
	    separates from a light background.

	Tints and opacities come from the palette (see Palette.luau), which is
	contrast-checked against these exact layers.
]]

local Create = require(script.Parent.Create)
local Motion = require(script.Parent.Motion)
local Palette = require(script.Parent.Parent.Theme.Palette)
local Theme = require(script.Parent.Parent.Theme.Theme)

-- Flat: no fill until something tints it (ghost buttons).
-- Low: control glass (buttons, thumbs). Raised: panel glass (cards, bars).
-- Floating: dialogs, popovers.
export type Elevation = "Flat" | "Low" | "Raised" | "Floating"
export type Fill = "Surface" | "Accent" | "Danger" | "Inset"

export type SurfaceProps = {
	Name: string?,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	-- Corner radius as a fraction of the shorter side (0.5 = pill).
	CornerScale: number?,
	Elevation: Elevation?,
	Fill: Fill?,
	Parent: Instance?,
}

export type RaisedSurface = {
	Root: Frame,
	-- Put children here, not in Root: Root also holds the border and shadow
	-- layers, which a UIListLayout in Root would otherwise try to lay out.
	Content: Frame,
	SetElevation: (self: RaisedSurface, elevation: Elevation) -> (),
	SetPressed: (self: RaisedSurface, isPressed: boolean) -> (),
	SetFill: (self: RaisedSurface, fill: Fill) -> (),
	-- Corner radius is a fraction of the shorter side, so a pane that
	-- changes shape (e.g. the Output panel expanding) updates it.
	SetCornerScale: (self: RaisedSurface, cornerScale: number) -> (),
}

export type InsetSurface = {
	Root: Frame,
	Content: Frame,
}

-- Shadow stroke thickness (px) per layer, innermost first. Stroke widths are
-- line weights, not layout sizes.
local SHADOW_LAYERS = { 2, 6, 12 }
local SHADOW_FALLOFF = 0.3
local SOLID_FILL_OPACITY = 0.96
local PRESSED_OPACITY_BOOST = 0.06
local DEFAULT_CORNER_SCALE = 0.22

local Surface = {}

local function CreateContent(parent: Instance): Frame
	return Create("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = parent,
	})
end

local function FillColors(fill: Fill, elevation: Elevation): (palette: Palette.Palette) -> ColorSequence
	return function(palette: Palette.Palette): ColorSequence
		if fill == "Accent" then
			return ColorSequence.new(palette.AccentHigh, palette.AccentLow)
		elseif fill == "Danger" then
			return ColorSequence.new(palette.Danger:Lerp(Color3.new(1, 1, 1), 0.1), palette.Danger)
		elseif fill == "Inset" then
			return ColorSequence.new(palette.Inset)
		elseif elevation == "Floating" then
			return ColorSequence.new(palette.FloatingTint)
		elseif elevation == "Raised" then
			return ColorSequence.new(palette.PanelTint)
		end
		return ColorSequence.new(palette.ControlTint)
	end
end

local function FillOpacity(palette: Palette.Palette, fill: Fill, elevation: Elevation): number
	if fill == "Accent" or fill == "Danger" then
		return SOLID_FILL_OPACITY
	elseif fill == "Inset" then
		return palette.InsetOpacity
	elseif elevation == "Flat" then
		return 0
	elseif elevation == "Low" then
		return palette.ControlOpacity
	elseif elevation == "Floating" then
		return palette.FloatingOpacity
	end
	return palette.PanelOpacity
end

local function CreateBorder(parent: Instance): UIStroke
	local gradient = Create("UIGradient", { Rotation = 90 })
	Theme.Bind(gradient, "Color", function(palette: Palette.Palette): ColorSequence
		return ColorSequence.new(palette.Border)
	end)
	Theme.Bind(gradient, "Transparency", function(palette: Palette.Palette): NumberSequence
		local topOpacity = palette.BorderOpacity
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1 - topOpacity),
			NumberSequenceKeypoint.new(1, 1 - topOpacity * palette.BorderFade),
		})
	end)
	return Create("UIStroke", {
		Name = "Border",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Color3.new(1, 1, 1),
		Thickness = 1,
		Children = { gradient },
		Parent = parent,
	})
end

local function CreateShadowLayer(parent: Instance, cornerScale: number, layerIndex: number): (UIStroke, UICorner)
	local stroke: UIStroke = Create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = SHADOW_LAYERS[layerIndex],
		Transparency = 1,
	})
	Theme.Bind(stroke, "Color", "Shadow")
	local corner: UICorner = Create("UICorner", { CornerRadius = UDim.new(cornerScale, 0) })
	Create("Frame", {
		Name = `Shadow{layerIndex}`,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Children = { corner :: Instance, stroke },
		Parent = parent,
	})
	return stroke, corner
end

--[[
	A glass pane. Children go in `Content`. Keep Root's ClipsDescendants off
	for panels and floating panes, or their shadow is clipped away.
]]
function Surface.Raised(props: SurfaceProps): RaisedSurface
	local cornerScale = props.CornerScale or DEFAULT_CORNER_SCALE
	local elevation: Elevation = props.Elevation or "Raised"
	local fill: Fill = props.Fill or "Surface"
	local isPressed = false

	local fillGradient = Create("UIGradient", { Rotation = 90 })
	local rootCorner: UICorner = Create("UICorner", { CornerRadius = UDim.new(cornerScale, 0) })
	-- Every corner that must follow SetCornerScale: the pane's and its shadow's.
	local corners: { UICorner } = { rootCorner }
	local root: Frame = Create("Frame", {
		Name = props.Name or "Glass",
		Size = props.Size,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Children = { rootCorner, fillGradient },
	})
	local border = CreateBorder(root)
	-- Created on first use: only panels and floating panes cast a shadow, so
	-- buttons skip these instances entirely.
	local shadowStrokes: { UIStroke } = {}

	local function Apply(animate: boolean)
		Theme.Bind(fillGradient, "Color", FillColors(fill, elevation))
		Theme.Bind(fillGradient, "Transparency", function(palette: Palette.Palette): NumberSequence
			local sheen = if elevation == "Raised" and fill == "Surface" then palette.PanelSheen else 0
			return NumberSequence.new(0, sheen)
		end)

		local function TargetTransparency(palette: Palette.Palette): number
			local opacity = FillOpacity(palette, fill, elevation)
			if isPressed and fill == "Surface" then
				opacity = math.min(1, opacity + PRESSED_OPACITY_BOOST)
			end
			return 1 - opacity
		end
		Theme.Bind(root, "BackgroundTransparency", TargetTransparency, animate)
		if animate then
			Motion.Tween(root, Motion.FAST, { BackgroundTransparency = TargetTransparency(Theme.Current()) })
		end

		border.Enabled = elevation ~= "Flat" or fill ~= "Surface"

		local castsShadow = elevation == "Raised" or elevation == "Floating"
		if castsShadow and #shadowStrokes == 0 then
			for layerIndex = 1, #SHADOW_LAYERS do
				local stroke, corner = CreateShadowLayer(root, cornerScale, layerIndex)
				shadowStrokes[layerIndex] = stroke
				table.insert(corners, corner)
			end
		end
		for layerIndex, stroke in shadowStrokes do
			Theme.Bind(stroke, "Transparency", function(palette: Palette.Palette): number
				local opacity = if elevation == "Floating"
					then palette.ShadowOpacity
					elseif elevation == "Raised" then palette.PanelShadowOpacity
					else 0
				return 1 - opacity * (1 - (layerIndex - 1) * SHADOW_FALLOFF)
			end)
		end
	end

	local surface: RaisedSurface = {
		Root = root,
		Content = CreateContent(root),

		SetElevation = function(_self: RaisedSurface, newElevation: Elevation)
			if elevation ~= newElevation then
				elevation = newElevation
				Apply(true)
			end
		end,

		SetPressed = function(_self: RaisedSurface, pressed: boolean)
			if isPressed ~= pressed then
				isPressed = pressed
				Apply(true)
			end
		end,

		SetFill = function(_self: RaisedSurface, newFill: Fill)
			if fill ~= newFill then
				fill = newFill
				Apply(false)
			end
		end,

		SetCornerScale = function(_self: RaisedSurface, newCornerScale: number)
			cornerScale = newCornerScale
			for _, corner in corners do
				corner.CornerRadius = UDim.new(newCornerScale, 0)
			end
		end,
	}

	Apply(false)
	if props.Parent then
		root.Parent = props.Parent
	end
	return surface
end

-- A sunken field (inputs, wells, tracks). Children go in `Content`.
function Surface.Inset(props: SurfaceProps): InsetSurface
	local cornerScale = props.CornerScale or DEFAULT_CORNER_SCALE
	local root: Frame = Create("Frame", {
		Name = props.Name or "Inset",
		Size = props.Size,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Theme = {
			BackgroundColor3 = "Inset",
			BackgroundTransparency = function(palette: Palette.Palette): number
				return 1 - palette.InsetOpacity
			end,
		},
		Children = {
			Create("UICorner", { CornerRadius = UDim.new(cornerScale, 0) }),
		},
	})
	local stroke: UIStroke = Create("UIStroke", {
		Name = "Border",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = 1,
		Parent = root,
	})
	Theme.BindAll(stroke, {
		Color = "InsetBorder",
		Transparency = function(palette: Palette.Palette): number
			return 1 - palette.InsetBorderOpacity
		end,
	})
	local content = CreateContent(root)
	if props.Parent then
		root.Parent = props.Parent
	end
	return { Root = root, Content = content }
end

-- A theme token for the transparency of a translucent highlight (hover,
-- selection): Theme.Bind(frame, "BackgroundTransparency",
-- Surface.TintTransparency("SelectionOpacity", isSelected)).
function Surface.TintTransparency(opacityToken: string, isVisible: boolean): (palette: Palette.Palette) -> number
	return function(palette: Palette.Palette): number
		return if isVisible then 1 - (palette :: any)[opacityToken] else 1
	end
end

-- Layout helpers return `any` so they mix freely in Create's Children lists.
-- Scale-based padding: each value is a fraction of the parent's size.
function Surface.Padding(horizontal: number, vertical: number): any
	return Create("UIPadding", {
		PaddingLeft = UDim.new(horizontal, 0),
		PaddingRight = UDim.new(horizontal, 0),
		PaddingTop = UDim.new(vertical, 0),
		PaddingBottom = UDim.new(vertical, 0),
	})
end

-- Keeps an element at a fixed width:height ratio, sized from its height.
function Surface.Aspect(ratio: number, dominantAxis: Enum.DominantAxis?): any
	return Create("UIAspectRatioConstraint", {
		AspectRatio = ratio,
		DominantAxis = dominantAxis or Enum.DominantAxis.Height,
		AspectType = Enum.AspectType.ScaleWithParentSize,
	})
end

return Surface
