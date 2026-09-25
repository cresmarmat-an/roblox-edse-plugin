--!strict
--[[
	VirtualList
	A scrolling list that only creates rows for what's on screen, so key lists
	and trees with thousands of entries stay fast. Rows are pooled and reused
	as you scroll.

	Sizing is all scale: row height is a fraction of the visible window,
	chosen so roughly `TargetRowHeight` pixels per row fit (more rows on a
	taller widget, never cramped on a short one). Positions and sizes are then
	written as fractions of the canvas.
]]

local Create = require(script.Parent.Parent.Create)

export type RowHandle = { Root: GuiObject }

export type VirtualListProps = {
	Name: string?,
	Size: UDim2,
	Position: UDim2?,
	LayoutOrder: number?,
	TargetRowHeight: number,
	CreateRow: () -> RowHandle,
	UpdateRow: (row: RowHandle, item: any, index: number) -> (),
	Parent: Instance?,
}

export type VirtualList = {
	Root: ScrollingFrame,
	SetItems: (self: VirtualList, items: { any }, preserveScroll: boolean?) -> (),
	GetItems: (self: VirtualList) -> { any },
	ScrollToIndex: (self: VirtualList, index: number) -> (),
	Refresh: (self: VirtualList) -> (),
	-- Called when the user scrolls within `threshold` rows of the end.
	SetOnNearEnd: (self: VirtualList, callback: (() -> ())?) -> (),
}

local MIN_ROWS_PER_PAGE = 4
local OVERSCAN_ROWS = 2
local NEAR_END_ROWS = 6
local SCROLLBAR_THICKNESS = 6

local VirtualListComponent = {}

function VirtualListComponent.new(props: VirtualListProps): VirtualList
	local items: { any } = {}
	local pool: { RowHandle } = {}
	local rowPixelHeight = props.TargetRowHeight
	local onNearEnd: (() -> ())? = nil
	local nearEndArmed = true

	local root: ScrollingFrame = Create("ScrollingFrame", {
		Name = props.Name or "VirtualList",
		Size = props.Size,
		Position = props.Position or UDim2.fromScale(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
		CanvasSize = UDim2.fromScale(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR_THICKNESS,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		ClipsDescendants = true,
		Theme = { ScrollBarImageColor3 = "Scrollbar" },
	})

	local function Render()
		local windowHeight = root.AbsoluteWindowSize.Y
		local canvasHeight = root.AbsoluteCanvasSize.Y
		if windowHeight <= 0 or canvasHeight <= 0 or rowPixelHeight <= 0 then
			return
		end

		local rowScale = rowPixelHeight / canvasHeight
		local firstIndex = math.max(1, math.floor(root.CanvasPosition.Y / rowPixelHeight) + 1 - OVERSCAN_ROWS)
		local visibleCount = math.ceil(windowHeight / rowPixelHeight) + OVERSCAN_ROWS * 2
		local lastIndex = math.min(#items, firstIndex + visibleCount - 1)

		local poolIndex = 0
		for index = firstIndex, lastIndex do
			poolIndex += 1
			local row = pool[poolIndex]
			if row == nil then
				row = props.CreateRow()
				row.Root.Parent = root
				pool[poolIndex] = row
			end
			row.Root.Size = UDim2.fromScale(1, rowScale)
			row.Root.Position = UDim2.fromScale(0, (index - 1) * rowScale)
			row.Root.Visible = true
			props.UpdateRow(row, items[index], index)
		end
		for unusedIndex = poolIndex + 1, #pool do
			pool[unusedIndex].Root.Visible = false
		end

		if onNearEnd and #items > 0 then
			local isNearEnd = lastIndex >= #items - NEAR_END_ROWS
			if isNearEnd and nearEndArmed then
				nearEndArmed = false
				task.spawn(onNearEnd)
			elseif not isNearEnd then
				nearEndArmed = true
			end
		end
	end

	local function Layout()
		local windowHeight = root.AbsoluteWindowSize.Y
		local frameHeight = root.AbsoluteSize.Y
		if windowHeight <= 0 or frameHeight <= 0 then
			return
		end
		local rowsPerPage = math.max(MIN_ROWS_PER_PAGE, math.floor(windowHeight / props.TargetRowHeight + 0.5))
		rowPixelHeight = windowHeight / rowsPerPage
		-- CanvasSize's scale is relative to the frame; the canvas never ends
		-- up smaller than the window, which Render accounts for by reading
		-- the real AbsoluteCanvasSize.
		root.CanvasSize = UDim2.fromScale(0, #items * rowPixelHeight / frameHeight)
		Render()
	end

	root:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(Layout)
	root:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(Render)
	root:GetPropertyChangedSignal("CanvasPosition"):Connect(Render)

	local list: VirtualList = {
		Root = root,

		SetItems = function(_self: VirtualList, newItems: { any }, preserveScroll: boolean?)
			items = newItems
			nearEndArmed = true
			if not preserveScroll then
				root.CanvasPosition = Vector2.zero
			end
			Layout()
		end,

		GetItems = function(_self: VirtualList): { any }
			return items
		end,

		ScrollToIndex = function(_self: VirtualList, index: number)
			local top = (index - 1) * rowPixelHeight
			local bottom = index * rowPixelHeight
			local windowHeight = root.AbsoluteWindowSize.Y
			local current = root.CanvasPosition.Y
			if top < current then
				root.CanvasPosition = Vector2.new(0, top)
			elseif bottom > current + windowHeight then
				root.CanvasPosition = Vector2.new(0, bottom - windowHeight)
			end
		end,

		Refresh = function(_self: VirtualList)
			Render()
		end,

		SetOnNearEnd = function(_self: VirtualList, callback: (() -> ())?)
			onNearEnd = callback
			nearEndArmed = true
		end,
	}

	if props.Parent then
		root.Parent = props.Parent
	end
	task.defer(Layout)
	return list
end

return VirtualListComponent
