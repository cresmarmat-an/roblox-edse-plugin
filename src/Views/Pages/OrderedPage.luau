--!strict
--[[
	OrderedPage
	Editing an OrderedDataStore entry: one whole number, with quick step
	buttons. Saving uses the same conflict check as standard stores (the
	value must still be what you loaded).
]]

local Button = require(script.Parent.Parent.Parent.Ui.Components.Button)
local Create = require(script.Parent.Parent.Parent.Ui.Create)
local EntrySession = require(script.Parent.Parent.Parent.Core.EntrySession)
local Label = require(script.Parent.Parent.Parent.Ui.Components.Label)
local Signal = require(script.Parent.Parent.Parent.Core.Signal)
local Surface = require(script.Parent.Parent.Parent.Ui.Surface)
local TextField = require(script.Parent.Parent.Parent.Ui.Components.TextField)
local Log = require(script.Parent.Parent.Parent.Services.Log)
local Typography = require(script.Parent.Parent.Parent.Ui.Typography)

export type OrderedPageProps = {
	Parent: Instance,
}

export type OrderedPage = {
	Root: Frame,
	SetSession: (self: OrderedPage, session: EntrySession.EntrySession?) -> (),
}

local SOURCE = "Ordered"
local STEPS = { -100, -10, -1, 1, 10, 100 }

local OrderedPage = {}

function OrderedPage.new(props: OrderedPageProps): OrderedPage
	local session: EntrySession.EntrySession? = nil
	local sessionConnection: Signal.Connection? = nil

	local root: Frame = Create("Frame", {
		Name = "OrderedPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			Surface.Padding(0.08, 0.1),
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.04, 0),
			}),
		},
		Parent = props.Parent,
	})

	Label.new({
		Name = "Caption",
		Text = "VALUE",
		Size = UDim2.fromScale(1, 0.05),
		Font = Typography.FONT_BOLD,
		Color = "TextMuted",
		XAlignment = Enum.TextXAlignment.Center,
		Ratio = 0.8,
		MaxTextSize = 12,
		LayoutOrder = 1,
		Parent = root,
	})

	local valueField: TextField.TextField
	local function Commit(text: string)
		local current = session
		if current == nil then
			return
		end
		local number = tonumber(text)
		if number == nil or number % 1 ~= 0 then
			Log.Warning(`"{text}" isn't a whole number`, "Ordered data stores hold whole numbers only.")
			valueField:SetText(if current.Draft.Value ~= nil then tostring(current.Draft.Value) else "")
			return
		end
		current:SetValue(number, SOURCE)
	end

	valueField = TextField.new({
		Name = "Value",
		Size = UDim2.fromScale(0.7, 0.16),
		LayoutOrder = 2,
		IsMonospace = true,
		Placeholder = "0",
		CornerScale = 0.25,
		OnSubmit = Commit,
		OnFocusChanged = function(isFocused: boolean)
			if not isFocused then
				Commit(valueField:GetText())
			end
		end,
		Parent = root,
	})
	valueField.TextBox.TextXAlignment = Enum.TextXAlignment.Center
	Typography.Fit(valueField.TextBox, 0.5, 16, 34)

	local stepRow: Frame = Create("Frame", {
		Name = "Steps",
		Size = UDim2.fromScale(0.9, 0.1),
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Children = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.02, 0),
			}),
		},
		Parent = root,
	})
	for index, step in STEPS do
		Button.new({
			Name = `Step{step}`,
			Text = if step > 0 then `+{step}` else tostring(step),
			Size = UDim2.fromScale(0.14, 1),
			LayoutOrder = index,
			OnActivated = function()
				local current = session
				if current then
					local base = if type(current.Draft.Value) == "number" then current.Draft.Value else 0
					current:SetValue(base + step, SOURCE)
				end
			end,
			Parent = stepRow,
		})
	end

	Label.new({
		Name = "Hint",
		Text = "Whole numbers only. Save writes it back, and refuses if a live server changed it since you loaded it.",
		Size = UDim2.fromScale(0.9, 0.12),
		Color = "TextSecondary",
		XAlignment = Enum.TextXAlignment.Center,
		YAlignment = Enum.TextYAlignment.Top,
		Wrapped = true,
		Ratio = 0.3,
		MinTextSize = 12,
		MaxTextSize = 14,
		LayoutOrder = 4,
		Parent = root,
	})

	local function Render()
		local current = session
		if current and not valueField.TextBox:IsFocused() then
			valueField:SetText(if current.Draft.Value ~= nil then tostring(current.Draft.Value) else "")
		end
	end

	return {
		Root = root,
		SetSession = function(_self: OrderedPage, newSession: EntrySession.EntrySession?)
			if sessionConnection then
				sessionConnection:Disconnect()
				sessionConnection = nil
			end
			session = newSession
			if newSession then
				sessionConnection = newSession.Changed:Connect(Render)
			end
			Render()
		end,
	}
end

return OrderedPage
