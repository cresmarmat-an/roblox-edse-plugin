--!strict
--[[
	Tooltip
	One shared tooltip for the whole widget. Plugin widgets have no native
	tooltips for GuiObjects, so hovering an attached element for a moment
	shows a small floating label beneath it.
]]

local Create = require(script.Parent.Parent.Create)
local Motion = require(script.Parent.Parent.Motion)
local Typography = require(script.Parent.Parent.Typography)

local SHOW_DELAY_SECONDS = 0.45
local TOOLTIP_TEXT_SIZE = 13
-- The bubble sizes itself to its text, so breathing room comes from the
-- text itself (line height and padding spaces) rather than pixel padding.
local TOOLTIP_LINE_HEIGHT = 1.8
local TOOLTIP_TEXT_PADDING = "   "
-- Gap between the element and its tooltip, as a fraction of the host height.
local GAP_SCALE = 0.008

local Tooltip = {}

local host: GuiObject? = nil
local bubble: Frame? = nil
local bubbleLabel: TextLabel? = nil
local hoverToken = 0

local function EnsureBubble(): (Frame, TextLabel)
	if bubble and bubbleLabel then
		return bubble, bubbleLabel
	end
	local label: TextLabel = Create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		FontFace = Typography.FONT_MEDIUM,
		TextSize = TOOLTIP_TEXT_SIZE,
		LineHeight = TOOLTIP_LINE_HEIGHT,
		Theme = { TextColor3 = "TooltipText" },
	})
	local frame: Frame = Create("Frame", {
		Name = "Tooltip",
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		ZIndex = 1000,
		Theme = { BackgroundColor3 = "TooltipBackground" },
		Children = {
			Create("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
			label,
		},
		Parent = host,
	})
	label.ZIndex = 1001
	bubble, bubbleLabel = frame, label
	return frame, label
end

function Tooltip.SetHost(newHost: GuiObject)
	host = newHost
	if bubble then
		bubble.Parent = newHost
	end
end

local function Hide()
	hoverToken += 1
	if bubble then
		bubble.Visible = false
	end
end

local function Show(target: GuiObject, text: string)
	local currentHost = host
	if currentHost == nil or text == "" then
		return
	end
	local frame, label = EnsureBubble()
	label.Text = TOOLTIP_TEXT_PADDING .. text .. TOOLTIP_TEXT_PADDING
	local hostSize = currentHost.AbsoluteSize
	if hostSize.X <= 0 or hostSize.Y <= 0 then
		return
	end
	local relative = target.AbsolutePosition - currentHost.AbsolutePosition
	local belowY = (relative.Y + target.AbsoluteSize.Y) / hostSize.Y + GAP_SCALE
	-- Center under the element, then slide horizontally so the whole bubble
	-- stays inside the widget (it is never cut off at an edge).
	-- The bubble auto-sizes to its text; TextBounds is current even before
	-- the bubble's own size has updated.
	local bubbleWidth = math.min(math.max(frame.AbsoluteSize.X, label.TextBounds.X), hostSize.X)
	local centerX = relative.X + target.AbsoluteSize.X / 2
	local halfWidth = bubbleWidth / 2
	local clampedCenter = math.clamp(centerX, halfWidth, math.max(halfWidth, hostSize.X - halfWidth))
	-- Flip above the element when it sits near the bottom edge.
	if belowY > 0.9 then
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position = UDim2.fromScale(clampedCenter / hostSize.X, relative.Y / hostSize.Y - GAP_SCALE)
	else
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Position = UDim2.fromScale(clampedCenter / hostSize.X, belowY)
	end
	frame.BackgroundTransparency = 1
	label.TextTransparency = 1
	frame.Visible = true
	Motion.Tween(frame, Motion.FAST, { BackgroundTransparency = 0.04 })
	Motion.Tween(label, Motion.FAST, { TextTransparency = 0 })
end

-- Shows `text` (or the result of calling it) after hovering `target`.
function Tooltip.Attach(target: GuiObject, text: string | () -> string)
	target.MouseEnter:Connect(function()
		hoverToken += 1
		local token = hoverToken
		task.delay(SHOW_DELAY_SECONDS, function()
			if token == hoverToken and target.Parent ~= nil and target.Visible then
				Show(target, if type(text) == "function" then text() else text)
			end
		end)
	end)
	target.MouseLeave:Connect(Hide)
	target.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Hide()
		end
	end)
end

Tooltip.Hide = Hide

function Tooltip.Destroy()
	Hide()
	if bubble then
		bubble:Destroy()
	end
	bubble, bubbleLabel, host = nil, nil, nil
end

return Tooltip
