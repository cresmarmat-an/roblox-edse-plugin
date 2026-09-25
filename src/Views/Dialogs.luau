--!strict
--[[
	Dialogs
	The editor's modal flows, built on Ui/Components/Dialog:
	  ConfirmSave   - review the diff before writing
	  ResolveConflict - the key changed on a live server since you loaded it
	  Export / Import - move JSON in and out (Studio plugins can't reach the
	                    clipboard, so export pre-selects the text for Ctrl+C)
	  NewKey        - name a key and choose its starting shape
	  Settings      - plugin preferences
]]

local CodeView = require(script.Parent.Parent.Ui.Components.CodeView)
local Create = require(script.Parent.Parent.Ui.Create)
local Dialog = require(script.Parent.Parent.Ui.Components.Dialog)
local Diff = require(script.Parent.Parent.Core.Diff)
local EntrySession = require(script.Parent.Parent.Core.EntrySession)
local Format = require(script.Parent.Parent.Core.Format)
local Json = require(script.Parent.Parent.Core.Json)
local JsonPage = require(script.Parent.Pages.JsonPage)
local Label = require(script.Parent.Parent.Ui.Components.Label)
local PluginSettings = require(script.Parent.Parent.Services.PluginSettings)
local Segmented = require(script.Parent.Parent.Ui.Components.Segmented)
local Surface = require(script.Parent.Parent.Ui.Surface)
local TextField = require(script.Parent.Parent.Ui.Components.TextField)
local Theme = require(script.Parent.Parent.Theme.Theme)
local Toggle = require(script.Parent.Parent.Ui.Components.Toggle)
local TreeModel = require(script.Parent.Parent.Core.TreeModel)
local Typography = require(script.Parent.Parent.Ui.Typography)
local VirtualList = require(script.Parent.Parent.Ui.Components.VirtualList)

export type ConflictChoice = "Reload" | "Overwrite" | "Cancel"
export type NewKeyRequest = { Key: string, Value: any }

local Dialogs = {}

Dialogs.SETTING_CONFIRM_SAVES = "ConfirmSaves"
Dialogs.SETTING_OUTPUT_OPEN_ON_ERROR = "OutputOpenOnError"
Dialogs.SETTING_OUTPUT_MIRROR = "OutputMirror"

local COPY_HINT = "Selected. Press Ctrl+C (Cmd+C on Mac) to copy."
Dialogs.SETTING_LIVE_INTERVAL = "LiveIntervalSeconds"
Dialogs.LIVE_INTERVAL_OPTIONS = { "5", "10", "30" }

local CHANGE_COLORS: { [Diff.ChangeType]: string } = {
	Added = "Success",
	Removed = "Danger",
	Changed = "Accent",
}
local CHANGE_SYMBOLS: { [Diff.ChangeType]: string } = {
	Added = "+",
	Removed = "-",
	Changed = "~",
}

type DiffLine = { Type: Diff.ChangeType, Text: string }

local function DiffLines(changes: EntrySession.Changes): { DiffLine }
	local lines: { DiffLine } = {}
	local function AddChanges(prefix: string, list: { Diff.Change })
		for _, change in list do
			local path = prefix .. TreeModel.FormatPath(change.Path)
			local text = if change.Type == "Added"
				then `{path}  =  {Format.Preview(change.After, 48)}`
				elseif change.Type == "Removed" then `{path}  (was {Format.Preview(change.Before, 48)})`
				else `{path}  {Format.Preview(change.Before, 32)}  →  {Format.Preview(change.After, 32)}`
			table.insert(lines, { Type = change.Type, Text = text })
		end
	end
	AddChanges("", changes.Value)
	if changes.IsValueTruncated then
		table.insert(lines, { Type = "Changed", Text = "… more changes not shown" })
	end
	if changes.UserIdsChanged then
		table.insert(lines, { Type = "Changed", Text = "User IDs changed" })
	end
	AddChanges("metadata.", changes.Metadata)
	return lines
end

local function DiffList(parent: Instance, lines: { DiffLine })
	local well = Surface.Inset({ Name = "Changes", Size = UDim2.fromScale(1, 1), CornerScale = 0.05, Parent = parent })
	type Row = { Root: Frame, Label: TextLabel }
	local list = VirtualList.new({
		Name = "Lines",
		Size = UDim2.fromScale(0.96, 0.92),
		Position = UDim2.fromScale(0.02, 0.04),
		TargetRowHeight = 24,
		CreateRow = function(): Row
			local rowFrame: Frame = Create("Frame", { Name = "Line", BackgroundTransparency = 1 })
			local label = Label.new({
				Name = "Text",
				Text = "",
				Size = UDim2.fromScale(1, 1),
				Font = Typography.FONT_MONO,
				RichText = true,
				Ratio = 0.52,
				MaxTextSize = 13,
				Parent = rowFrame,
			})
			return { Root = rowFrame, Label = label }
		end :: any,
		UpdateRow = function(row: Row, line: DiffLine)
			local color = Theme.Get(CHANGE_COLORS[line.Type]) :: Color3
			row.Label.Text = Typography.ColorTag(CHANGE_SYMBOLS[line.Type] .. " ", color)
				.. Typography.EscapeRichText(line.Text)
		end :: any,
		Parent = well.Content,
	})
	list:SetItems(lines)
end

function Dialogs.ConfirmSave(session: EntrySession.EntrySession): boolean
	local changes = session:GetChanges()
	local lines = DiffLines(changes)
	local isNewKey = not session.Original.Exists
	local summary = if isNewKey
		then `Create "{session.Key}" in {session.StoreRef.Name}.`
		else `{Format.Plural(#lines, "change")} to "{session.Key}". This goes live immediately.`
	local result = Dialog.Show({
		Title = if isNewKey then "Create key?" else "Save changes?",
		Size = UDim2.fromScale(0.7, 0.62),
		BuildBody = function(body: Frame)
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.03, 0),
				Parent = body,
			})
			Label.new({
				Name = "Summary",
				Text = summary,
				Size = UDim2.fromScale(1, 0.12),
				Color = "TextSecondary",
				Ratio = 0.6,
				MaxTextSize = 14,
				LayoutOrder = 1,
				Parent = body,
			})
			local holder: Frame = Create("Frame", {
				Name = "DiffHolder",
				Size = UDim2.fromScale(1, 0.84),
				LayoutOrder = 2,
				BackgroundTransparency = 1,
				Parent = body,
			})
			DiffList(holder, lines)
		end,
		Actions = {
			{ Text = "Cancel", Variant = "Ghost", Result = false },
			{ Text = if isNewKey then "Create" else "Save", Variant = "Primary", Result = true },
		},
		DismissResult = false,
	})
	return result == true
end

function Dialogs.ResolveConflict(key: string): ConflictChoice
	local result = Dialog.Show({
		Title = "Changed on a live server",
		Message = `"{key}" was modified after you loaded it (probably by a running game server). Reload to get the latest value and lose your edits, or overwrite it with your version.`,
		Size = UDim2.fromScale(0.58, 0.38),
		Actions = {
			{ Text = "Cancel", Variant = "Ghost", Result = "Cancel" },
			{ Text = "Overwrite", Variant = "Danger", Result = "Overwrite" },
			{ Text = "Reload", Variant = "Primary", Result = "Reload" },
		},
		DismissResult = "Cancel",
	})
	return result :: ConflictChoice
end

-- Shows `text` pre-selected so it can be copied with Ctrl+C (Studio plugins
-- can't write to the clipboard directly).
function Dialogs.ShowText(title: string, text: string)
	Dialog.Show({
		Title = title,
		Size = UDim2.fromScale(0.72, 0.72),
		BuildBody = function(body: Frame)
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.025, 0),
				Parent = body,
			})
			Label.new({
				Name = "Hint",
				Text = COPY_HINT,
				Size = UDim2.fromScale(1, 0.08),
				Color = "Accent",
				Font = Typography.FONT_MEDIUM,
				Ratio = 0.6,
				MaxTextSize = 13,
				LayoutOrder = 1,
				Parent = body,
			})
			local codeView = CodeView.new({
				Name = "Text",
				Size = UDim2.fromScale(1, 0.88),
				LayoutOrder = 2,
				Text = text,
				IsPlainText = true,
				Parent = body,
			})
			task.defer(function()
				codeView:SelectAll()
			end)
		end,
		Actions = { { Text = "Done", Variant = "Primary", Result = true } },
		DismissResult = false,
	})
end

function Dialogs.Export(session: EntrySession.EntrySession)
	local function Render(includeInfo: boolean): string
		local payload: any = session.Draft.Value
		if includeInfo then
			payload = {
				Key = session.Key,
				Value = session.Draft.Value,
				UserIds = session.Draft.UserIds,
				Metadata = session.Draft.Metadata,
			}
		end
		local ok, text = JsonPage.EncodeForEditing(payload)
		return if ok then text else `// {text}`
	end

	Dialog.Show({
		Title = `Export "{session.Key}"`,
		Size = UDim2.fromScale(0.72, 0.72),
		BuildBody = function(body: Frame)
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.025, 0),
				Parent = body,
			})
			local optionsRow: Frame = Create("Frame", {
				Name = "Options",
				Size = UDim2.fromScale(1, 0.09),
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				Children = {
					Create("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0.02, 0),
					}),
				},
				Parent = body,
			})
			local codeView: CodeView.CodeView
			Toggle.new({
				Name = "IncludeInfo",
				Size = UDim2.fromScale(1, 0.8),
				LayoutOrder = 1,
				IsOn = false,
				OnChanged = function(isOn: boolean)
					codeView:SetText(Render(isOn))
					codeView:SelectAll()
				end,
				Parent = optionsRow,
			})
			Label.new({
				Name = "IncludeInfoLabel",
				Text = "Include key, user IDs and metadata",
				Size = UDim2.fromScale(0.6, 1),
				Color = "TextSecondary",
				Ratio = 0.5,
				MaxTextSize = 13,
				LayoutOrder = 2,
				Parent = optionsRow,
			})
			local hint = Label.new({
				Name = "Hint",
				Text = COPY_HINT,
				Size = UDim2.fromScale(0.35, 1),
				Color = "Accent",
				Font = Typography.FONT_MEDIUM,
				XAlignment = Enum.TextXAlignment.Right,
				Ratio = 0.5,
				MaxTextSize = 13,
				LayoutOrder = 3,
				Parent = optionsRow,
			})
			Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = hint })
			codeView = CodeView.new({
				Name = "Export",
				Size = UDim2.fromScale(1, 0.88),
				LayoutOrder = 2,
				Text = Render(false),
				Parent = body,
			})
			task.defer(function()
				codeView:SelectAll()
			end)
		end,
		Actions = { { Text = "Done", Variant = "Primary", Result = true } },
		DismissResult = false,
	})
end

-- Returns the imported value, or nil when cancelled.
function Dialogs.Import(key: string): (boolean, any)
	local parsedValue: any = nil
	local isValid = false
	local result = Dialog.Show({
		Title = `Import into "{key}"`,
		Size = UDim2.fromScale(0.72, 0.72),
		BuildBody = function(body: Frame)
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.025, 0),
				Parent = body,
			})
			local status = Label.new({
				Name = "Status",
				Text = "Paste JSON below. It replaces the draft; nothing is saved until you press Save.",
				Size = UDim2.fromScale(1, 0.08),
				Color = "TextSecondary",
				Ratio = 0.55,
				MaxTextSize = 13,
				LayoutOrder = 1,
				Parent = body,
			})
			local codeView = CodeView.new({
				Name = "Import",
				Size = UDim2.fromScale(1, 0.88),
				LayoutOrder = 2,
				Placeholder = "Paste JSON here",
				OnTextChanged = function(text: string)
					local ok, value = Json.Decode(text)
					isValid = ok and value ~= nil
					parsedValue = if ok then value else nil
					if not ok then
						local failure = value :: Json.DecodeError
						status.Text = `Line {failure.Line}, column {failure.Column}: {failure.Message}`
					elseif value == nil then
						status.Text = "That's null. Paste a value to import."
					else
						status.Text = `Valid JSON · {Format.Bytes(Format.EncodedSize(value) or #text)}`
					end
					Theme.Bind(status, "TextColor3", if isValid then "Success" else "Danger")
				end,
				Parent = body,
			})
			task.defer(function()
				codeView.TextBox:CaptureFocus()
			end)
		end,
		Actions = {
			{ Text = "Cancel", Variant = "Ghost", Result = false },
			{ Text = "Load into editor", Variant = "Primary", Result = true },
		},
		DismissResult = false,
	})
	if result == true and isValid then
		return true, parsedValue
	end
	return false, nil
end

local NEW_KEY_SHAPES: { [string]: () -> any } = {
	Object = function()
		return {}
	end,
	Array = function()
		return {}
	end,
	String = function()
		return ""
	end,
	Number = function()
		return 0
	end,
}

function Dialogs.NewKey(isOrdered: boolean, validateKey: (string) -> string?): NewKeyRequest?
	local keyName = ""
	local shape = if isOrdered then "Number" else "Object"
	local result = Dialog.Show({
		Title = "New key",
		Size = UDim2.fromScale(0.5, 0.4),
		BuildBody = function(body: Frame, resolve: (any) -> ())
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.08, 0),
				Parent = body,
			})
			local field: TextField.TextField
			field = TextField.new({
				Name = "KeyName",
				Size = UDim2.fromScale(1, 0.3),
				LayoutOrder = 1,
				Icon = "Key",
				Placeholder = "Key name, e.g. Player_123456",
				OnChanged = function(text: string)
					keyName = text
					field:SetInvalid(false)
				end,
				OnSubmit = function()
					resolve(true)
				end,
				Parent = body,
			})
			if not isOrdered then
				Segmented.new({
					Name = "Shape",
					Options = {
						{ Value = "Object", Label = "Object" },
						{ Value = "Array", Label = "Array" },
						{ Value = "String", Label = "Text" },
						{ Value = "Number", Label = "Number" },
					},
					Value = shape,
					Size = UDim2.fromScale(1, 0.28),
					LayoutOrder = 2,
					OnChanged = function(value: string)
						shape = value
					end,
					Parent = body,
				})
			end
			task.defer(function()
				field:Focus()
			end)
		end,
		Actions = {
			{ Text = "Cancel", Variant = "Ghost", Result = false },
			{ Text = "Create", Variant = "Primary", Result = true },
		},
		DismissResult = false,
	})
	if result ~= true then
		return nil
	end
	local key = string.match(keyName, "^%s*(.-)%s*$") :: string
	local problem = validateKey(key)
	if problem then
		return Dialogs.NewKeyError(problem, isOrdered, validateKey)
	end
	return { Key = key, Value = NEW_KEY_SHAPES[shape]() }
end

function Dialogs.NewKeyError(problem: string, isOrdered: boolean, validateKey: (string) -> string?): NewKeyRequest?
	local retry = Dialog.Confirm({ Title = "Can't use that key", Message = problem, ConfirmText = "Try again" })
	if retry then
		return Dialogs.NewKey(isOrdered, validateKey)
	end
	return nil
end

function Dialogs.Settings(settings: PluginSettings.PluginSettings)
	Dialog.Show({
		Title = "Settings",
		Size = UDim2.fromScale(0.58, 0.62),
		BuildBody = function(body: Frame)
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.04, 0),
				Parent = body,
			})
			local function SettingRow(order: number, title: string, detail: string): Frame
				local row: Frame = Create("Frame", {
					Name = title,
					Size = UDim2.fromScale(1, 0.21),
					LayoutOrder = order,
					BackgroundTransparency = 1,
					Children = {
						Create("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0.03, 0),
						}),
					},
					Parent = body,
				})
				local text: Frame = Create("Frame", {
					Name = "Text",
					Size = UDim2.fromScale(0.6, 1),
					LayoutOrder = 1,
					BackgroundTransparency = 1,
					Children = { Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) },
					Parent = row,
				})
				Label.new({
					Name = "Title",
					Text = title,
					Size = UDim2.fromScale(1, 0.5),
					Font = Typography.FONT_SEMIBOLD,
					Ratio = 0.62,
					MaxTextSize = 15,
					Parent = text,
				})
				Label.new({
					Name = "Detail",
					Text = detail,
					Size = UDim2.fromScale(1, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Color = "TextSecondary",
					Ratio = 0.56,
					MaxTextSize = 13,
					Parent = text,
				})
				return row
			end

			local function BooleanSetting(order: number, name: string, title: string, detail: string, default: boolean)
				Toggle.new({
					Name = name,
					Size = UDim2.fromScale(1, 0.62),
					LayoutOrder = 2,
					IsOn = settings:GetBoolean(name, default),
					OnChanged = function(isOn: boolean)
						settings:SetBoolean(name, isOn)
					end,
					Parent = SettingRow(order, title, detail),
				})
			end

			BooleanSetting(
				1,
				Dialogs.SETTING_CONFIRM_SAVES,
				"Review before saving",
				"Show the diff and ask before every write.",
				true
			)

			local liveRow = SettingRow(2, "Live refresh interval", "How often Live checks the open key (seconds).")
			Segmented.new({
				Name = "LiveInterval",
				Options = {
					{ Value = "5", Label = "5s" },
					{ Value = "10", Label = "10s" },
					{ Value = "30", Label = "30s" },
				},
				Value = settings:GetString(Dialogs.SETTING_LIVE_INTERVAL, "10"),
				Size = UDim2.fromScale(0.3, 0.66),
				LayoutOrder = 2,
				OnChanged = function(value: string)
					settings:SetString(Dialogs.SETTING_LIVE_INTERVAL, value)
				end,
				Parent = liveRow,
			})

			BooleanSetting(
				3,
				Dialogs.SETTING_OUTPUT_OPEN_ON_ERROR,
				"Open Output on errors",
				"Show the log automatically when something fails.",
				true
			)
			BooleanSetting(
				4,
				Dialogs.SETTING_OUTPUT_MIRROR,
				"Copy messages to Studio's Output",
				"Also print every message in Studio's Output window.",
				false
			)
		end,
		Actions = { { Text = "Done", Variant = "Primary", Result = true } },
		DismissResult = true,
	})
end

return Dialogs
