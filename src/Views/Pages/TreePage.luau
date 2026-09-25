--!strict
--[[
	TreePage
	Structured editing of the draft value.

	  * Click a value to edit it in place; Enter or clicking away commits,
	    Escape cancels. Booleans flip on click.
	  * Click an object key to rename it.
	  * The More button (or right-click) offers add / insert / duplicate /
	    change type / delete.
	  * The filter shows only matching keys or values and their parents.

	Rows are virtualized, so large player-data blobs stay responsive.
]]

local Button = require(script.Parent.Parent.Parent.Ui.Components.Button)
local Context = require(script.Parent.Parent.Context)
local ContextMenu = require(script.Parent.Parent.Parent.Ui.ContextMenu)
local Create = require(script.Parent.Parent.Parent.Ui.Create)
local EntrySession = require(script.Parent.Parent.Parent.Core.EntrySession)
local Format = require(script.Parent.Parent.Parent.Core.Format)
local Icons = require(script.Parent.Parent.Parent.Theme.Icons)
local Json = require(script.Parent.Parent.Parent.Core.Json)
local Motion = require(script.Parent.Parent.Parent.Ui.Motion)
local Surface = require(script.Parent.Parent.Parent.Ui.Surface)
local TextField = require(script.Parent.Parent.Parent.Ui.Components.TextField)
local Theme = require(script.Parent.Parent.Parent.Theme.Theme)
local Log = require(script.Parent.Parent.Parent.Services.Log)
local TreeModel = require(script.Parent.Parent.Parent.Core.TreeModel)
local Typography = require(script.Parent.Parent.Parent.Ui.Typography)
local VirtualList = require(script.Parent.Parent.Parent.Ui.Components.VirtualList)

export type TreePageProps = {
	Context: Context.Context,
	Parent: Instance,
}

export type TreePage = {
	Root: Frame,
	SetSession: (self: TreePage, session: EntrySession.EntrySession?) -> (),
}

local SOURCE = "Tree"
local TARGET_ROW_HEIGHT = 24
-- Indent per depth level, as a fraction of the row height.
local INDENT_RATIO = 0.75
local MAX_INDENT_LEVELS = 8
-- The row's More button is always visible (quietly), and full-strength on hover.
local MORE_REST_TRANSPARENCY = 0.55
-- The key column's share of the row width.
local KEY_COLUMN_SCALE = 0.3
local CARET_HEIGHT_SCALE = 0.5
local MORE_HEIGHT_SCALE = 0.62
local AUTO_EXPAND_CHILD_LIMIT = 16

local KIND_COLOR: { [TreeModel.Kind]: string } = {
	String = "SyntaxString",
	Number = "SyntaxNumber",
	Boolean = "SyntaxBoolean",
	Null = "SyntaxNull",
	Object = "TextMuted",
	Array = "TextMuted",
}

local KIND_BY_NAME: { [string]: TreeModel.Kind } = {
	String = "String",
	Number = "Number",
	Boolean = "Boolean",
	Object = "Object",
	Array = "Array",
}

local TreePage = {}

local function DisplayValue(row: TreeModel.Row): string
	if row.Kind == "String" then
		local text = row.Value :: string
		-- Multi-line strings show escaped (and read-only here); edit them in JSON.
		return if string.find(text, "\n", 1, true) then Format.Truncate(string.gsub(text, "\n", "\\n"), 120) else text
	elseif row.Kind == "Number" then
		local ok, text = pcall(Json.FormatNumber, row.Value)
		return if ok then text else tostring(row.Value)
	elseif row.Kind == "Boolean" then
		return tostring(row.Value)
	elseif row.Kind == "Null" then
		return "null"
	end
	return Format.Preview(row.Value)
end

local function DisplayKey(row: TreeModel.Row): string
	if row.Key == nil then
		return "value"
	elseif type(row.Key) == "number" then
		return `[{row.Key}]`
	end
	return row.Key :: string
end

local function ParentPath(path: TreeModel.Path): TreeModel.Path
	local parent = table.clone(path)
	table.remove(parent)
	return parent
end

function TreePage.new(props: TreePageProps): TreePage
	local session: EntrySession.EntrySession? = nil
	local sessionConnection: { Disconnect: (any) -> () }? = nil
	local expanded: { [string]: boolean } = {}
	local filterText = ""
	local selectedId: string? = nil
	type PendingFocus = { Id: string, Field: "Key" | "Value" }
	local pendingFocus: PendingFocus? = nil

	local root: Frame = Create("Frame", {
		Name = "TreePage",
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

	local list: VirtualList.VirtualList
	local Rebuild: () -> ()

	local function Edit(mutate: (value: any) -> any): boolean
		local current = session
		if current == nil then
			return false
		end
		local ok, result = pcall(mutate, current.Draft.Value)
		if not ok then
			Log.Warning("That edit wasn't applied", tostring(result))
			return false
		end
		current:SetValue(result, SOURCE)
		return true
	end

	-- Toolbar ----------------------------------------------------------------
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
	local filterToken = 0
	local filterField = TextField.new({
		Name = "Filter",
		Size = UDim2.fromScale(0.5, 1),
		LayoutOrder = 1,
		Icon = "Search",
		Placeholder = "Filter",
		ShowClearButton = true,
		OnChanged = function(text: string)
			filterToken += 1
			local token = filterToken
			task.delay(0.15, function()
				if token == filterToken then
					filterText = text
					Rebuild()
				end
			end)
		end,
		Parent = toolbar,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = filterField.Root })

	Button.new({
		Name = "ExpandAll",
		Icon = "ExpandAll",
		Tooltip = "Expand all",
		Variant = "Ghost",
		Square = true,
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = 2,
		OnActivated = function()
			local current = session
			if current then
				expanded = TreeModel.ExpandedIdsToDepth(current.Draft.Value, math.huge)
				Rebuild()
			end
		end,
		Parent = toolbar,
	})
	Button.new({
		Name = "CollapseAll",
		Icon = "CollapseAll",
		Tooltip = "Collapse all",
		Variant = "Ghost",
		Square = true,
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = 3,
		OnActivated = function()
			expanded = {}
			Rebuild()
		end,
		Parent = toolbar,
	})

	-- Tree well ---------------------------------------------------------------
	local well = Surface.Inset({
		Name = "Well",
		Size = UDim2.fromScale(1, 0.9),
		LayoutOrder = 2,
		CornerScale = 0.03,
		Parent = root,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = well.Root })

	-- Menu actions -------------------------------------------------------------
	local function AddChild(row: TreeModel.Row, asArrayItem: boolean)
		local path = row.Path
		if asArrayItem then
			local array = row.Value :: { any }
			local last = array[#array]
			local newValue = if last == nil then "" else TreeModel.DefaultValue(TreeModel.GetKind(last))
			if Edit(function(value)
				return TreeModel.Insert(value, path, #array + 1, newValue)
			end) then
				local childPath = table.clone(path)
				table.insert(childPath, #array + 1)
				expanded[row.Id] = true
				pendingFocus = { Id = TreeModel.PathId(childPath), Field = "Value" }
			end
		else
			local key = TreeModel.UniqueKey(row.Value, "NewKey")
			local childPath = table.clone(path)
			table.insert(childPath, key)
			if Edit(function(value)
				return TreeModel.Set(value, childPath, "")
			end) then
				expanded[row.Id] = true
				pendingFocus = { Id = TreeModel.PathId(childPath), Field = "Key" }
			end
		end
		Rebuild()
	end

	local function ShowRowMenu(row: TreeModel.Row)
		local isRoot = #row.Path == 0
		local parentValue = if isRoot then nil else TreeModel.Get((session :: any).Draft.Value, ParentPath(row.Path))
		local isArrayItem = type(row.Key) == "number"
		local isEmptyTable = type(row.Value) == "table" and next(row.Value) == nil

		local items: { ContextMenu.MenuItem } = {}
		if row.Kind == "Object" or isEmptyTable then
			table.insert(items, { Id = "AddKey", Text = "Add key" })
		end
		if row.Kind == "Array" then
			table.insert(items, { Id = "AddItem", Text = "Add item" })
		end
		if isArrayItem then
			table.insert(items, { Id = "InsertAbove", Text = "Insert item above" })
			table.insert(items, { Id = "InsertBelow", Text = "Insert item below" })
		end
		if not isRoot then
			table.insert(items, { Id = "Duplicate", Text = "Duplicate" })
		end
		if type(row.Key) == "string" then
			table.insert(items, { Id = "Rename", Text = "Rename key" })
		end
		local typeItems: { ContextMenu.MenuItem } = {}
		for _, kind in TreeModel.KINDS do
			if kind ~= row.Kind then
				table.insert(typeItems, { Id = "Type:" .. kind, Text = kind })
			end
		end
		table.insert(items, { Text = "Change type", Items = typeItems })
		if not isRoot then
			table.insert(items, ContextMenu.SEPARATOR)
			table.insert(items, { Id = "Delete", Text = "Delete" })
		end

		local choice = ContextMenu.Show(props.Context.Plugin, items)
		if choice == nil then
			return
		end

		if choice == "AddKey" then
			AddChild(row, false)
		elseif choice == "AddItem" then
			AddChild(row, true)
		elseif choice == "InsertAbove" or choice == "InsertBelow" then
			local index = (row.Key :: number) + (if choice == "InsertBelow" then 1 else 0)
			local arrayPath = ParentPath(row.Path)
			if
				Edit(function(value)
					return TreeModel.Insert(value, arrayPath, index, TreeModel.DefaultValue(row.Kind))
				end)
			then
				local newPath = table.clone(arrayPath)
				table.insert(newPath, index)
				pendingFocus = { Id = TreeModel.PathId(newPath), Field = "Value" }
			end
		elseif choice == "Duplicate" then
			local copy = TreeModel.DeepCopy(row.Value)
			if isArrayItem then
				Edit(function(value)
					return TreeModel.Insert(value, ParentPath(row.Path), (row.Key :: number) + 1, copy)
				end)
			else
				local newKey = TreeModel.UniqueKey(parentValue, (row.Key :: string) .. "Copy")
				local newPath = ParentPath(row.Path)
				table.insert(newPath, newKey)
				if Edit(function(value)
					return TreeModel.Set(value, newPath, copy)
				end) then
					pendingFocus = { Id = TreeModel.PathId(newPath), Field = "Key" }
				end
			end
		elseif choice == "Rename" then
			pendingFocus = { Id = row.Id, Field = "Key" }
		elseif string.sub(choice, 1, 5) == "Type:" then
			local targetKind: TreeModel.Kind? = KIND_BY_NAME[string.sub(choice, 6)]
			if targetKind then
				local kind: TreeModel.Kind = targetKind
				Edit(function(value)
					return TreeModel.Set(value, row.Path, TreeModel.ConvertValue(row.Value, kind))
				end)
			end
		elseif choice == "Delete" then
			Edit(function(value)
				return TreeModel.Remove(value, row.Path)
			end)
		end
		Rebuild()
	end

	-- Rows ---------------------------------------------------------------------
	type RowView = {
		Root: TextButton,
		Hover: Frame,
		Selection: Frame,
		Indent: Frame,
		IndentAspect: UIAspectRatioConstraint,
		Caret: ImageButton,
		KeyBox: TextBox,
		Colon: TextLabel,
		ValueBox: TextBox,
		MoreButton: ImageButton,
		Row: TreeModel.Row?,
	}

	local function CreateRowView(): RowView
		local rowButton: TextButton = Create("TextButton", {
			Name = "TreeRow",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
		})
		local selection: Frame = Create("Frame", {
			Name = "Selection",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "Selection" },
			Parent = rowButton,
		})
		local hover: Frame = Create("Frame", {
			Name = "Hover",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "Hover" },
			Parent = rowButton,
		})
		local content: Frame = Create("Frame", {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Children = {
				Surface.Padding(0.012, 0),
				Create("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = rowButton,
		})

		local indentAspect: UIAspectRatioConstraint = Surface.Aspect(0.01)
		local indent: Frame = Create("Frame", {
			Name = "Indent",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Children = { indentAspect },
			Parent = content,
		})

		local caret: ImageButton = Create("ImageButton", {
			Name = "Caret",
			Size = UDim2.fromScale(1, CARET_HEIGHT_SCALE),
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Image = Icons.AssetOrBlank("Caret"),
			ScaleType = Enum.ScaleType.Fit,
			Theme = { ImageColor3 = "TextMuted" },
			Children = { Surface.Aspect(1) },
			Parent = content,
		})

		-- Keys get a fixed share of the row, so values line up in a column and a
		-- long key ends in "…" instead of pushing its value out of view.
		local keyBox: TextBox = Create("TextBox", {
			Name = "Key",
			Size = UDim2.fromScale(KEY_COLUMN_SCALE, 1),
			LayoutOrder = 3,
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			FontFace = Typography.FONT_MONO_MEDIUM,
			TextXAlignment = Enum.TextXAlignment.Left,
			Theme = { TextColor3 = "SyntaxKey" },
			Parent = content,
		})
		Typography.Fit(keyBox, 0.54, 12, 13)

		local colon: TextLabel = Create("TextLabel", {
			Name = "Colon",
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 4,
			BackgroundTransparency = 1,
			Text = " :  ",
			FontFace = Typography.FONT_MONO,
			Theme = { TextColor3 = "SyntaxPunctuation" },
			Parent = content,
		})
		Typography.Fit(colon, 0.54, 12, 13)

		local valueBox: TextBox = Create("TextBox", {
			Name = "Value",
			Size = UDim2.fromScale(0.4, 1),
			LayoutOrder = 5,
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			FontFace = Typography.FONT_MONO,
			TextXAlignment = Enum.TextXAlignment.Left,
			Children = { Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) },
			Parent = content,
		})
		Typography.Fit(valueBox, 0.54, 12, 13)

		local moreButton: ImageButton = Create("ImageButton", {
			Name = "More",
			Size = UDim2.fromScale(1, MORE_HEIGHT_SCALE),
			LayoutOrder = 6,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Image = Icons.AssetOrBlank("More"),
			ScaleType = Enum.ScaleType.Fit,
			ImageTransparency = MORE_REST_TRANSPARENCY,
			Theme = { ImageColor3 = "Icon" },
			Children = { Surface.Aspect(1) },
			Parent = content,
		})

		local view: RowView = {
			Root = rowButton,
			Hover = hover,
			Selection = selection,
			Indent = indent,
			IndentAspect = indentAspect,
			Caret = caret,
			KeyBox = keyBox,
			Colon = colon,
			ValueBox = valueBox,
			MoreButton = moreButton,
			Row = nil,
		}

		local function ToggleExpanded()
			local row = view.Row
			if row and TreeModel.IsContainerKind(row.Kind) and #row.Path > 0 then
				expanded[row.Id] = not row.IsExpanded
				Rebuild()
			end
		end

		local function Select()
			local row = view.Row
			if row then
				selectedId = row.Id
				list:Refresh()
			end
		end

		rowButton.MouseEnter:Connect(function()
			Motion.Tween(hover, Motion.FAST, { BackgroundTransparency = 1 - Theme.Current().HoverOpacity })
			Motion.Tween(moreButton, Motion.FAST, { ImageTransparency = 0 })
		end)
		rowButton.MouseLeave:Connect(function()
			Motion.Tween(hover, Motion.FAST, { BackgroundTransparency = 1 })
			Motion.Tween(moreButton, Motion.FAST, { ImageTransparency = MORE_REST_TRANSPARENCY })
		end)
		rowButton.Activated:Connect(function()
			Select()
			ToggleExpanded()
		end)
		caret.Activated:Connect(ToggleExpanded)
		rowButton.MouseButton2Click:Connect(function()
			local row = view.Row
			if row then
				Select()
				ShowRowMenu(row)
			end
		end)
		moreButton.Activated:Connect(function()
			local row = view.Row
			if row then
				Select()
				ShowRowMenu(row)
			end
		end)

		-- Edits capture the row they started on, because pooled rows can be
		-- rebound to another path while a box is focused (e.g. on scroll).
		local editingRow: TreeModel.Row? = nil

		keyBox.Focused:Connect(function()
			editingRow = view.Row
			Select()
		end)
		keyBox.FocusLost:Connect(function(_enterPressed: boolean, input: InputObject?)
			local row = editingRow
			editingRow = nil
			if row == nil or type(row.Key) ~= "string" then
				return
			end
			local newKey = keyBox.Text
			if (input and input.KeyCode == Enum.KeyCode.Escape) or newKey == row.Key then
				keyBox.Text = row.Key :: string
				return
			end
			if not Edit(function(value)
				return TreeModel.Rename(value, row.Path, newKey)
			end) then
				keyBox.Text = row.Key :: string
			end
		end)

		valueBox.Focused:Connect(function()
			local row = view.Row
			editingRow = row
			Select()
			if row == nil then
				return
			end
			if row.Kind == "Boolean" then
				valueBox:ReleaseFocus()
				Edit(function(value)
					return TreeModel.Set(value, row.Path, not row.Value)
				end)
			elseif TreeModel.IsContainerKind(row.Kind) then
				valueBox:ReleaseFocus()
				ToggleExpanded()
			end
		end)
		valueBox.FocusLost:Connect(function(_enterPressed: boolean, input: InputObject?)
			local row = editingRow
			editingRow = nil
			if row == nil or (row.Kind ~= "String" and row.Kind ~= "Number") then
				return
			end
			local text = valueBox.Text
			if input and input.KeyCode == Enum.KeyCode.Escape then
				valueBox.Text = DisplayValue(row)
				return
			end
			local newValue: any = text
			if row.Kind == "Number" then
				newValue = tonumber(text)
				if newValue == nil or newValue ~= newValue then
					Log.Warning(`"{text}" isn't a number`, `{TreeModel.FormatPath(row.Path)} keeps its previous value.`)
					valueBox.Text = DisplayValue(row)
					return
				end
			end
			if newValue ~= row.Value then
				Edit(function(value)
					return TreeModel.Set(value, row.Path, newValue)
				end)
			end
		end)

		return view
	end

	local function UpdateRowView(view: RowView, row: TreeModel.Row, _index: number)
		local previous = view.Row
		if previous and previous.Id ~= row.Id then
			-- Rebinding while editing: release focus (the capture above keeps
			-- the edit pointed at the right path).
			if view.KeyBox:IsFocused() then
				view.KeyBox:ReleaseFocus()
			end
			if view.ValueBox:IsFocused() then
				view.ValueBox:ReleaseFocus()
			end
		end
		view.Row = row

		local isContainer = TreeModel.IsContainerKind(row.Kind)
		local isSelected = row.Id == selectedId
		view.Selection.BackgroundTransparency = if isSelected then 1 - Theme.Current().SelectionOpacity else 1
		-- Past MAX_INDENT_LEVELS, deeper rows stop indenting further so the
		-- value and its More button always stay inside the row.
		view.IndentAspect.AspectRatio = math.max(0.01, math.min(row.Depth, MAX_INDENT_LEVELS) * INDENT_RATIO)
		view.Caret.ImageTransparency = if isContainer and #row.Path > 0 then 0 else 1
		view.Caret.Rotation = if row.IsExpanded then 90 else 0

		local keyIsEditable = type(row.Key) == "string"
		view.KeyBox.TextEditable = keyIsEditable
		view.KeyBox.Active = keyIsEditable
		if not view.KeyBox:IsFocused() then
			view.KeyBox.Text = DisplayKey(row)
		end
		Theme.Bind(view.KeyBox, "TextColor3", if type(row.Key) == "string" then "SyntaxKey" else "TextMuted")

		local isMultiline = row.Kind == "String" and string.find(row.Value, "\n", 1, true) ~= nil
		view.ValueBox.TextEditable = (row.Kind == "String" and not isMultiline) or row.Kind == "Number"
		if not view.ValueBox:IsFocused() then
			view.ValueBox.Text = DisplayValue(row)
		end
		Theme.Bind(view.ValueBox, "TextColor3", KIND_COLOR[row.Kind])
		view.ValueBox.FontFace = if isContainer then Typography.FONT_MEDIUM else Typography.FONT_MONO

		local focus = pendingFocus
		if focus and focus.Id == row.Id then
			pendingFocus = nil
			task.defer(function()
				local box = if focus.Field == "Key" then view.KeyBox else view.ValueBox
				if view.Row == row and box.TextEditable then
					box:CaptureFocus()
					box.SelectionStart = 1
					box.CursorPosition = #box.Text + 1
				end
			end)
		end
	end

	list = VirtualList.new({
		Name = "Rows",
		Size = UDim2.fromScale(0.985, 0.97),
		Position = UDim2.fromScale(0.0075, 0.015),
		TargetRowHeight = TARGET_ROW_HEIGHT,
		CreateRow = CreateRowView :: any,
		UpdateRow = UpdateRowView :: any,
		Parent = well.Content,
	})

	function Rebuild()
		local current = session
		if current == nil then
			list:SetItems({}, false)
			return
		end
		local rows = TreeModel.Flatten(current.Draft.Value, expanded, { Filter = filterText })
		list:SetItems(rows, true)
		local focus = pendingFocus
		if focus then
			for index, row in rows do
				if row.Id == focus.Id then
					list:ScrollToIndex(index)
					break
				end
			end
		end
	end

	local page: TreePage = {
		Root = root,

		SetSession = function(_self: TreePage, newSession: EntrySession.EntrySession?)
			if sessionConnection then
				sessionConnection:Disconnect()
				sessionConnection = nil
			end
			session = newSession
			selectedId = nil
			pendingFocus = nil
			filterText = ""
			filterField:SetText("")
			expanded = {}
			if newSession then
				-- Open small top-level containers so the shape is visible at once.
				local value = newSession.Draft.Value
				if type(value) == "table" then
					for key, child in value do
						if type(child) == "table" and TreeModel.CountChildren(child) <= AUTO_EXPAND_CHILD_LIMIT then
							expanded[TreeModel.PathId({ key })] = true
						end
					end
				end
				sessionConnection = newSession.Changed:Connect(function()
					Rebuild()
				end)
			end
			Rebuild()
		end,
	}
	return page
end

return TreePage
