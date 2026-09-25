--!strict
--[[
	CodeView
	A multi-line monospace JSON editor/viewer with line numbers and syntax
	highlighting.

	Highlighting uses an overlay: a RichText label with identical font and
	layout sits over the TextBox. While the box isn't focused its own text is
	transparent and the colored overlay shows; on focus the overlay hides so
	the caret and selection behave natively.

	The canvas is sized in scale from the text's measured bounds, so the text
	box always covers the whole visible area (click anywhere to edit) and grows
	with its content.
]]

local Create = require(script.Parent.Parent.Create)
local JsonHighlight = require(script.Parent.Parent.Parent.Core.JsonHighlight)
local Palette = require(script.Parent.Parent.Parent.Theme.Palette)
local Surface = require(script.Parent.Parent.Surface)
local Theme = require(script.Parent.Parent.Parent.Theme.Theme)
local Typography = require(script.Parent.Parent.Typography)

export type CodeViewProps = {
	Name: string?,
	Size: UDim2,
	Position: UDim2?,
	LayoutOrder: number?,
	Text: string?,
	IsReadOnly: boolean?,
	-- Plain text (e.g. the output log): no JSON syntax colors.
	IsPlainText: boolean?,
	Placeholder: string?,
	OnTextChanged: ((text: string) -> ())?,
	OnFocusLost: (() -> ())?,
	Parent: Instance?,
}

export type CodeView = {
	Root: Frame,
	TextBox: TextBox,
	SetText: (self: CodeView, text: string) -> (),
	GetText: (self: CodeView) -> string,
	SelectAll: (self: CodeView) -> (),
	FocusAt: (self: CodeView, position: number) -> (),
	IsFocused: (self: CodeView) -> boolean,
}

-- Highlighting very large documents costs more than it helps.
local MAX_HIGHLIGHT_CHARACTERS = 60000
-- Extra canvas beyond the text so the last line/column isn't flush with the edge.
local CANVAS_SLACK_PIXELS = 24
local SCROLLBAR_THICKNESS = 6

local CodeViewComponent = {}

local function ColorsFor(palette: Palette.Palette): JsonHighlight.Colors
	return {
		Key = palette.SyntaxKey:ToHex(),
		String = palette.SyntaxString:ToHex(),
		Number = palette.SyntaxNumber:ToHex(),
		Boolean = palette.SyntaxBoolean:ToHex(),
		Null = palette.SyntaxNull:ToHex(),
		Punctuation = palette.SyntaxPunctuation:ToHex(),
	}
end

local function LineNumbers(text: string): string
	local _, newlineCount = string.gsub(text, "\n", "")
	local lines = table.create(newlineCount + 1)
	for line = 1, newlineCount + 1 do
		lines[line] = tostring(line)
	end
	return table.concat(lines, "\n")
end

function CodeViewComponent.new(props: CodeViewProps): CodeView
	local isReadOnly = props.IsReadOnly == true
	local isFocused = false

	local root: Frame = Create("Frame", {
		Name = props.Name or "CodeView",
		Size = props.Size,
		Position = props.Position or UDim2.fromScale(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
	})
	local well = Surface.Inset({ Name = "Well", Size = UDim2.fromScale(1, 1), CornerScale = 0.03, Parent = root })

	local scroller: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Scroller",
		Size = UDim2.fromScale(0.97, 0.94),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.fromScale(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.XY,
		ScrollBarThickness = SCROLLBAR_THICKNESS,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Theme = { ScrollBarImageColor3 = "Scrollbar" },
		Parent = well.Content,
	})

	local gutter: TextLabel = Create("TextLabel", {
		Name = "Gutter",
		Size = UDim2.fromScale(0.05, 1),
		BackgroundTransparency = 1,
		FontFace = Typography.FONT_MONO,
		TextSize = Typography.CODE_TEXT_SIZE,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "1",
		Theme = { TextColor3 = "TextMuted" },
		Parent = scroller,
	})

	local textBox: TextBox = Create("TextBox", {
		Name = "Code",
		Size = UDim2.fromScale(0.9, 1),
		BackgroundTransparency = 1,
		MultiLine = true,
		ClearTextOnFocus = false,
		TextEditable = not isReadOnly,
		TextWrapped = false,
		FontFace = Typography.FONT_MONO,
		TextSize = Typography.CODE_TEXT_SIZE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		PlaceholderText = props.Placeholder or "",
		Text = props.Text or "",
		Theme = { TextColor3 = "TextPrimary", PlaceholderColor3 = "TextMuted" },
		Parent = scroller,
	})

	local overlay: TextLabel = Create("TextLabel", {
		Name = "Highlight",
		Size = textBox.Size,
		BackgroundTransparency = 1,
		RichText = true,
		FontFace = Typography.FONT_MONO,
		TextSize = Typography.CODE_TEXT_SIZE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 2,
		Active = false,
		Parent = scroller,
	})

	local function CanHighlight(): boolean
		return not props.IsPlainText and #textBox.Text <= MAX_HIGHLIGHT_CHARACTERS and textBox.Text ~= ""
	end

	local function RefreshHighlight()
		local showOverlay = not isFocused and CanHighlight()
		overlay.Visible = showOverlay
		textBox.TextTransparency = if showOverlay then 1 else 0
		if showOverlay then
			overlay.Text = JsonHighlight.ToRichText(textBox.Text, ColorsFor(Theme.Current()))
		end
	end

	-- Converts measured pixel bounds into scale sizes for the canvas and
	-- its children.
	local function Layout()
		local window = scroller.AbsoluteWindowSize
		local frameSize = scroller.AbsoluteSize
		if window.X <= 0 or window.Y <= 0 or frameSize.X <= 0 or frameSize.Y <= 0 then
			return
		end
		local gutterWidth = gutter.TextBounds.X + Typography.CODE_TEXT_SIZE
		local textBounds = textBox.TextBounds
		local contentWidth = math.max(window.X, gutterWidth + textBounds.X + CANVAS_SLACK_PIXELS)
		local contentHeight = math.max(window.Y, textBounds.Y + CANVAS_SLACK_PIXELS)
		scroller.CanvasSize = UDim2.fromScale(contentWidth / frameSize.X, contentHeight / frameSize.Y)

		local gutterScale = gutterWidth / contentWidth
		gutter.Size = UDim2.fromScale(gutterScale - Typography.CODE_TEXT_SIZE * 0.5 / contentWidth, 1)
		textBox.Position = UDim2.fromScale(gutterScale, 0)
		textBox.Size = UDim2.fromScale(1 - gutterScale, 1)
		overlay.Position = textBox.Position
		overlay.Size = textBox.Size
	end

	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		gutter.Text = LineNumbers(textBox.Text)
		if not isFocused then
			RefreshHighlight()
		end
		if props.OnTextChanged then
			props.OnTextChanged(textBox.Text)
		end
	end)
	textBox:GetPropertyChangedSignal("TextBounds"):Connect(Layout)
	gutter:GetPropertyChangedSignal("TextBounds"):Connect(Layout)
	scroller:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(Layout)
	textBox.Focused:Connect(function()
		isFocused = true
		RefreshHighlight()
	end)
	textBox.FocusLost:Connect(function()
		isFocused = false
		RefreshHighlight()
		if props.OnFocusLost then
			props.OnFocusLost()
		end
	end)
	local themeConnection = Theme.Changed:Connect(function()
		if root.Parent then
			RefreshHighlight()
		end
	end)
	root.Destroying:Connect(function()
		themeConnection:Disconnect()
	end)

	local codeView: CodeView = {
		Root = root,
		TextBox = textBox,

		SetText = function(_self: CodeView, text: string)
			textBox.Text = text
			gutter.Text = LineNumbers(text)
			RefreshHighlight()
		end,

		GetText = function(_self: CodeView): string
			return textBox.Text
		end,

		SelectAll = function(_self: CodeView)
			textBox:CaptureFocus()
			textBox.SelectionStart = 1
			textBox.CursorPosition = #textBox.Text + 1
		end,

		FocusAt = function(_self: CodeView, position: number)
			textBox:CaptureFocus()
			textBox.SelectionStart = -1
			textBox.CursorPosition = math.clamp(position, 1, #textBox.Text + 1)
		end,

		IsFocused = function(_self: CodeView): boolean
			return isFocused
		end,
	}

	gutter.Text = LineNumbers(textBox.Text)
	RefreshHighlight()
	task.defer(Layout)
	if props.Parent then
		root.Parent = props.Parent
	end
	return codeView
end

return CodeViewComponent
