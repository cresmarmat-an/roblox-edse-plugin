--!strict
--[[
	Label
	A themed single-line (or wrapped) TextLabel whose text size follows its
	scaled height. See Typography.Fit.
]]

local Create = require(script.Parent.Parent.Create)
local Theme = require(script.Parent.Parent.Parent.Theme.Theme)
local Typography = require(script.Parent.Parent.Typography)

export type LabelProps = {
	Name: string?,
	Text: string,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Font: Font?,
	Color: Theme.Token?,
	-- TextSize as a fraction of the label's height (single-line labels).
	-- Wrapped labels instead shrink to fit, up to MaxTextSize.
	Ratio: number?,
	MinTextSize: number?,
	MaxTextSize: number?,
	XAlignment: Enum.TextXAlignment?,
	YAlignment: Enum.TextYAlignment?,
	Wrapped: boolean?,
	RichText: boolean?,
	AutomaticSize: Enum.AutomaticSize?,
	ZIndex: number?,
	Parent: Instance?,
}

-- Floor for wrapped text shrinking to fit: small enough that text never
-- spills out of its box, large enough to stay legible.
local WRAPPED_MIN_TEXT_SIZE = 10

local Label = {}

function Label.new(props: LabelProps): TextLabel
	local label: TextLabel = Create("TextLabel", {
		Name = props.Name or "Label",
		Text = props.Text,
		Size = props.Size,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
		FontFace = props.Font or Typography.FONT_REGULAR,
		TextXAlignment = props.XAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = props.YAlignment or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrapped == true,
		TextTruncate = if props.Wrapped then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		RichText = props.RichText == true,
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		ZIndex = props.ZIndex or 1,
	})
	Theme.Bind(label, "TextColor3", props.Color or "TextPrimary")
	if props.Wrapped then
		-- Wrapped paragraphs shrink to fit their box rather than spill past it.
		Typography.ScaleToFit(label, props.MaxTextSize or 14, WRAPPED_MIN_TEXT_SIZE)
	else
		-- Single lines keep a steady size and end with "…" when too long.
		Typography.Fit(label, props.Ratio or Typography.RATIO_BODY, props.MinTextSize, props.MaxTextSize)
	end
	if props.Parent then
		label.Parent = props.Parent
	end
	return label
end

return Label
