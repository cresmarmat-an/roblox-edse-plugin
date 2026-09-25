--!strict
--[[
	Icon
	Draws an icon image from Theme/Icons, tinted with a theme color. Icons are
	always square, sized by height.
]]

local Create = require(script.Parent.Parent.Create)
local Icons = require(script.Parent.Parent.Parent.Theme.Icons)
local Surface = require(script.Parent.Parent.Surface)
local Theme = require(script.Parent.Parent.Parent.Theme.Theme)

export type IconProps = {
	Name: string,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Color: Theme.Token?,
	ZIndex: number?,
	Parent: Instance?,
}

export type Icon = {
	Root: ImageLabel,
	SetIcon: (self: Icon, name: string) -> (),
	SetColor: (self: Icon, color: Theme.Token) -> (),
}

local IconComponent = {}

function IconComponent.new(props: IconProps): Icon
	local root: ImageLabel = Create("ImageLabel", {
		Name = `Icon_{props.Name}`,
		Size = props.Size,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Children = { Surface.Aspect(1) },
	})

	local icon: Icon = {
		Root = root,

		SetIcon = function(_self: Icon, name: string)
			local assetId = Icons.Get(name)
			root.Image = if Icons.IsBlank(assetId) then "" else assetId
			root.Name = `Icon_{name}`
		end,

		SetColor = function(_self: Icon, color: Theme.Token)
			Theme.Bind(root, "ImageColor3", color)
		end,
	}

	icon:SetIcon(props.Name)
	icon:SetColor(props.Color or "Icon")
	if props.Parent then
		root.Parent = props.Parent
	end
	return icon
end

return IconComponent
