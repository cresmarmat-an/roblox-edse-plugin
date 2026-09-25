--!strict
--[[
	Typography
	Fonts, plus text that scales with its container. Instead of TextScaled
	(which shrinks long strings to different sizes and can't truncate), Fit
	derives TextSize from the label's own scaled height, so every label of the
	same height shares one size and long text truncates with "…".
]]

local Typography = {}

Typography.FONT_REGULAR = Font.fromName("BuilderSans", Enum.FontWeight.Regular)
Typography.FONT_MEDIUM = Font.fromName("BuilderSans", Enum.FontWeight.Medium)
Typography.FONT_SEMIBOLD = Font.fromName("BuilderSans", Enum.FontWeight.SemiBold)
Typography.FONT_BOLD = Font.fromName("BuilderSans", Enum.FontWeight.Bold)
Typography.FONT_MONO = Font.fromName("RobotoMono", Enum.FontWeight.Regular)
Typography.FONT_MONO_MEDIUM = Font.fromName("RobotoMono", Enum.FontWeight.Medium)

-- Readable bounds for fitted text, in points.
Typography.MIN_TEXT_SIZE = 12
Typography.MAX_TEXT_SIZE = 22

-- Height ratios for common roles (TextSize = height * ratio).
Typography.RATIO_BODY = 0.5
Typography.RATIO_LABEL = 0.62
Typography.RATIO_TITLE = 0.66

-- Monospace size for the code editor, whose box grows with its content and
-- therefore can't derive its size from its own height.
Typography.CODE_TEXT_SIZE = 14

-- Keeps `textObject.TextSize` at `ratio` of its height, clamped to a
-- readable range. Returns the connection so callers can disconnect.
-- Accepts any TextLabel, TextButton or TextBox.
function Typography.Fit(textObject: GuiObject, ratio: number, minSize: number?, maxSize: number?): RBXScriptConnection
	local lower = minSize or Typography.MIN_TEXT_SIZE
	local upper = maxSize or Typography.MAX_TEXT_SIZE
	local function Update()
		local height = textObject.AbsoluteSize.Y
		if height > 0 then
			(textObject :: any).TextSize = math.clamp(math.round(height * ratio), lower, upper)
		end
	end
	Update()
	return textObject:GetPropertyChangedSignal("AbsoluteSize"):Connect(Update)
end

-- Makes text shrink to fit its box (both width and height), never
-- overflowing or clipping, capped at `maxSize` so it stays consistent with
-- surrounding text. Best for short labels in fixed boxes and wrapped
-- paragraphs; single-line text in lists should truncate with Fit instead.
function Typography.ScaleToFit(textObject: GuiObject, maxSize: number, minSize: number?)
	(textObject :: any).TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxSize
	constraint.MinTextSize = minSize or 1
	constraint.Parent = textObject
end

-- Escapes text for RichText labels.
function Typography.EscapeRichText(text: string): string
	return (
		string.gsub(text, "[<>&\"']", {
			["<"] = "&lt;",
			[">"] = "&gt;",
			["&"] = "&amp;",
			['"'] = "&quot;",
			["'"] = "&apos;",
		})
	)
end

function Typography.ColorTag(text: string, color: Color3): string
	return `<font color="#{color:ToHex()}">{text}</font>`
end

return Typography
