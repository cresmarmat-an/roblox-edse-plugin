--!strict
--[[
	Diff
	Structural diff between two JSON-shaped values, reported as a flat list of
	leaf-level changes ordered by path. Used for the save confirmation and for
	comparing versions.
]]

local NaturalOrder = require(script.Parent.NaturalOrder)
local TreeModel = require(script.Parent.TreeModel)

export type ChangeType = "Added" | "Removed" | "Changed"

export type Change = {
	Path: TreeModel.Path,
	Type: ChangeType,
	Before: any,
	After: any,
}

local Diff = {}

local DEFAULT_LIMIT = 500

-- Returns the changes and whether the list was cut off at `limit`.
function Diff.Compute(before: any, after: any, limit: number?): ({ Change }, boolean)
	local maxChanges = limit or DEFAULT_LIMIT
	local changes: { Change } = {}
	local isTruncated = false

	local function Record(path: TreeModel.Path, changeType: ChangeType, beforeValue: any, afterValue: any)
		if #changes >= maxChanges then
			isTruncated = true
			return
		end
		table.insert(changes, { Path = path, Type = changeType, Before = beforeValue, After = afterValue })
	end

	local function Walk(beforeValue: any, afterValue: any, path: TreeModel.Path)
		if isTruncated or beforeValue == afterValue then
			return
		end
		if beforeValue == nil then
			Record(path, "Added", nil, afterValue)
			return
		end
		if afterValue == nil then
			Record(path, "Removed", beforeValue, nil)
			return
		end
		if type(beforeValue) ~= "table" or type(afterValue) ~= "table" then
			Record(path, "Changed", beforeValue, afterValue)
			return
		end

		-- Both are tables: compare key by key so a single edit deep inside a
		-- large object is reported as one precise change.
		local keySet: { [any]: boolean } = {}
		for key in beforeValue do
			keySet[key] = true
		end
		for key in afterValue do
			keySet[key] = true
		end
		local keys = {}
		for key in keySet do
			table.insert(keys, key)
		end
		table.sort(keys, NaturalOrder.LessKey)

		for _, key in keys do
			local childPath = table.clone(path)
			table.insert(childPath, key)
			Walk(beforeValue[key], afterValue[key], childPath)
		end
	end

	Walk(before, after, {})
	return changes, isTruncated
end

return Diff
