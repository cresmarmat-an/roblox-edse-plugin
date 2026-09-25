--!strict
--[[
	JsonPage
	Raw JSON editing of the draft value. Typing is parsed shortly after you
	pause; valid JSON updates the draft (and the tree), invalid JSON shows the
	exact line and column with a jump-to-error button, and Save stays blocked
	until it's fixed.
]]

local Button = require(script.Parent.Parent.Parent.Ui.Components.Button)
local CodeView = require(script.Parent.Parent.Parent.Ui.Components.CodeView)
local Create = require(script.Parent.Parent.Parent.Ui.Create)
local EntrySession = require(script.Parent.Parent.Parent.Core.EntrySession)
local Format = require(script.Parent.Parent.Parent.Core.Format)
local Json = require(script.Parent.Parent.Parent.Core.Json)
local Label = require(script.Parent.Parent.Parent.Ui.Components.Label)
local NaturalOrder = require(script.Parent.Parent.Parent.Core.NaturalOrder)
local Signal = require(script.Parent.Parent.Parent.Core.Signal)
local Theme = require(script.Parent.Parent.Parent.Theme.Theme)
local TreeModel = require(script.Parent.Parent.Parent.Core.TreeModel)
local Typography = require(script.Parent.Parent.Parent.Ui.Typography)

export type JsonPageProps = {
	Parent: Instance,
}

export type JsonPage = {
	Root: Frame,
	-- Fires with true while the text is invalid (Save must wait).
	InvalidChanged: Signal.Signal<boolean>,
	SetSession: (self: JsonPage, session: EntrySession.EntrySession?) -> (),
	IsInvalid: (self: JsonPage) -> boolean,
}

local SOURCE = "Json"
local PARSE_DEBOUNCE_SECONDS = 0.3
-- Past this size the text editor gets sluggish; the tree still works.
local MAX_EDITABLE_CHARACTERS = 200000
local INDENT = "  "

local JsonPage = {}

function JsonPage.EncodeForEditing(value: any): (boolean, string)
	if value == nil then
		return true, ""
	end
	return pcall(Json.Encode, value, { Indent = INDENT, KeyLess = NaturalOrder.Less })
end

function JsonPage.new(props: JsonPageProps): JsonPage
	local session: EntrySession.EntrySession? = nil
	local sessionConnection: Signal.Connection? = nil
	local parseToken = 0
	local isInvalid = false
	local errorPosition: number? = nil
	local isApplyingText = false
	local invalidChanged = Signal.new() :: Signal.Signal<boolean>

	local root: Frame = Create("Frame", {
		Name = "JsonPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.015, 0),
			}),
		},
		Parent = props.Parent,
	})

	local toolbar: Frame = Create("Frame", {
		Name = "Toolbar",
		Size = UDim2.fromScale(1, 0.075),
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.012, 0),
			}),
		},
		Parent = root,
	})

	local codeView: CodeView.CodeView
	local Parse: () -> ()

	local formatButton = Button.new({
		Name = "Format",
		Text = "Format",
		Size = UDim2.fromScale(0.14, 1),
		LayoutOrder = 1,
		Tooltip = "Re-indent and sort keys",
		Parent = toolbar,
	})

	local status = Label.new({
		Name = "Status",
		Text = "",
		Size = UDim2.fromScale(0.5, 1),
		Font = Typography.FONT_MEDIUM,
		Color = "TextMuted",
		Ratio = 0.44,
		MaxTextSize = 13,
		LayoutOrder = 2,
		Parent = toolbar,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = status })

	local jumpButton = Button.new({
		Name = "GoToError",
		Text = "Go to error",
		Icon = "Warning",
		Color = "Danger",
		Size = UDim2.fromScale(0.2, 1),
		LayoutOrder = 3,
		Parent = toolbar,
	})
	jumpButton.Root.Visible = false

	local function SetInvalid(invalid: boolean)
		if isInvalid ~= invalid then
			isInvalid = invalid
			invalidChanged:Fire(invalid)
		end
		jumpButton.Root.Visible = invalid
		Theme.Bind(status, "TextColor3", if invalid then "Danger" else "TextMuted")
	end

	local function ShowText(text: string)
		isApplyingText = true
		codeView:SetText(text)
		isApplyingText = false
	end

	local function LoadFromDraft()
		parseToken += 1
		local current = session
		if current == nil then
			ShowText("")
			status.Text = ""
			SetInvalid(false)
			return
		end
		local ok, text = JsonPage.EncodeForEditing(current.Draft.Value)
		if not ok then
			ShowText("")
			status.Text = `Can't show as JSON: {text}`
			SetInvalid(false)
			return
		end
		local isTooLarge = #text > MAX_EDITABLE_CHARACTERS
		codeView.TextBox.TextEditable = not isTooLarge
		ShowText(if isTooLarge then string.sub(text, 1, MAX_EDITABLE_CHARACTERS) else text)
		status.Text = if isTooLarge
			then `Read-only preview: this value is {Format.Bytes(#text)}. Edit it in the Tree tab.`
			elseif current.Draft.Value == nil then "Empty. Type JSON to create a value."
			else `Valid JSON · {Format.Bytes(Format.EncodedSize(current.Draft.Value) or #text)}`
		SetInvalid(false)
	end

	function Parse()
		local current = session
		-- A read-only preview of a huge value is truncated; never parse it.
		if current == nil or not codeView.TextBox.TextEditable then
			return
		end
		local text = codeView:GetText()
		if string.match(text, "^%s*$") then
			-- An empty editor means "no value yet" (e.g. a brand-new key), not
			-- a syntax error. Save will explain that a value is required.
			errorPosition = nil
			SetInvalid(false)
			status.Text = "Empty. Type JSON to create a value."
			if current.Draft.Value ~= nil then
				current:SetValue(nil, SOURCE)
			end
			return
		end
		local ok, result = Json.Decode(text)
		if not ok then
			local failure = result :: Json.DecodeError
			errorPosition = failure.Position
			status.Text = `Line {failure.Line}, column {failure.Column}: {failure.Message}`
			SetInvalid(true)
			return
		end
		errorPosition = nil
		SetInvalid(false)
		status.Text = if result == nil
			then "Empty value (null)"
			else `Valid JSON · {Format.Bytes(Format.EncodedSize(result) or 0)}`
		if not TreeModel.DeepEqual(result, current.Draft.Value) then
			current:SetValue(result, SOURCE)
		end
	end

	codeView = CodeView.new({
		Name = "Editor",
		Size = UDim2.fromScale(1, 0.9),
		LayoutOrder = 2,
		Placeholder = "{ }",
		OnTextChanged = function()
			if isApplyingText then
				return
			end
			parseToken += 1
			local token = parseToken
			task.delay(PARSE_DEBOUNCE_SECONDS, function()
				if token == parseToken then
					Parse()
				end
			end)
		end,
		OnFocusLost = function()
			-- Commit immediately when leaving the editor rather than waiting
			-- for the debounce, so Save always sees the latest text.
			parseToken += 1
			Parse()
		end,
		Parent = root,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = codeView.Root })

	formatButton.Activated:Connect(function()
		Parse()
		if not isInvalid then
			LoadFromDraft()
		end
	end)
	jumpButton.Activated:Connect(function()
		if errorPosition then
			codeView:FocusAt(errorPosition)
		end
	end)

	local page: JsonPage = {
		Root = root,
		InvalidChanged = invalidChanged,

		SetSession = function(_self: JsonPage, newSession: EntrySession.EntrySession?)
			if sessionConnection then
				sessionConnection:Disconnect()
				sessionConnection = nil
			end
			session = newSession
			if newSession then
				sessionConnection = newSession.Changed:Connect(function(source: string)
					if source ~= SOURCE then
						LoadFromDraft()
					end
				end)
			end
			LoadFromDraft()
		end,

		IsInvalid = function(_self: JsonPage): boolean
			return isInvalid
		end,
	}
	return page
end

return JsonPage
