--!strict
--[[
	TreeModel
	Pure operations on a JSON-shaped Luau value addressed by paths, plus
	flattening into rows for the virtualized tree editor.

	Every edit is copy-on-write along the edited path: the original value is
	never mutated, so the loaded snapshot stays intact for diffs and reverts,
	and unchanged subtrees are shared rather than copied.
]]

local Json = require(script.Parent.Json)
local NaturalOrder = require(script.Parent.NaturalOrder)

export type PathSegment = string | number
export type Path = { PathSegment }
export type Kind = "Object" | "Array" | "String" | "Number" | "Boolean" | "Null"

export type Row = {
	Id: string,
	Path: Path,
	Depth: number,
	Key: PathSegment?,
	Kind: Kind,
	Value: any,
	ChildCount: number,
	IsExpanded: boolean,
	IsMatch: boolean,
}

export type FlattenOptions = {
	-- Case-insensitive text; when set, only matching rows and their
	-- ancestors are listed, and those ancestors are expanded automatically.
	Filter: string?,
}

local TreeModel = {}

local KINDS: { Kind } = { "String", "Number", "Boolean", "Object", "Array" }
TreeModel.KINDS = KINDS

function TreeModel.GetKind(value: any): Kind
	local valueType = type(value)
	if valueType == "table" then
		return if Json.IsArray(value) then "Array" else "Object"
	elseif valueType == "string" then
		return "String"
	elseif valueType == "number" then
		return "Number"
	elseif valueType == "boolean" then
		return "Boolean"
	end
	return "Null"
end

function TreeModel.IsContainerKind(kind: Kind): boolean
	return kind == "Object" or kind == "Array"
end

-- Stable identifier for a path, used as the key for expansion state.
function TreeModel.PathId(path: Path): string
	local parts = table.create(#path)
	for index, segment in path do
		parts[index] = if type(segment) == "number"
			then `[{segment}]`
			else "." .. string.gsub(segment :: string, "[%.%[\\]", "\\%0")
	end
	return table.concat(parts)
end

-- Human-readable path, e.g. `Inventory[3].Name` or `Stats["max hp"]`.
function TreeModel.FormatPath(path: Path): string
	if #path == 0 then
		return "(root)"
	end
	local parts = table.create(#path)
	for index, segment in path do
		if type(segment) == "number" then
			parts[index] = `[{segment}]`
		elseif string.match(segment :: string, "^[%a_][%w_]*$") then
			parts[index] = if index == 1 then segment :: string else "." .. (segment :: string)
		else
			parts[index] = `[{Json.EscapeString(segment :: string)}]`
		end
	end
	return table.concat(parts)
end

function TreeModel.SortedKeys(container: { [any]: any }): { PathSegment }
	if Json.IsArray(container) then
		local indices = table.create(#container)
		for index = 1, #container do
			indices[index] = index
		end
		return indices
	end
	local keys: { PathSegment } = {}
	for key in container do
		table.insert(keys, key)
	end
	table.sort(keys, NaturalOrder.LessKey)
	return keys
end

function TreeModel.CountChildren(value: any): number
	if type(value) ~= "table" then
		return 0
	end
	local count = 0
	for _ in value do
		count += 1
	end
	return count
end

function TreeModel.DeepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = TreeModel.DeepCopy(child)
	end
	return copy
end

function TreeModel.DeepEqual(left: any, right: any): boolean
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
	for key, leftChild in left do
		if not TreeModel.DeepEqual(leftChild, right[key]) then
			return false
		end
	end
	for key in right do
		if left[key] == nil then
			return false
		end
	end
	return true
end

function TreeModel.Get(root: any, path: Path): any
	local node = root
	for _, segment in path do
		if type(node) ~= "table" then
			return nil
		end
		node = node[segment]
	end
	return node
end

-- Walks to the parent of `path`, cloning each table on the way, and hands the
-- cloned parent to `mutate`. Returns the new root.
local function EditParent(root: any, path: Path, mutate: (parent: { [any]: any }, key: PathSegment) -> ()): any
	assert(#path > 0, "EditParent needs a non-root path")
	local function Walk(node: any, depth: number): any
		if type(node) ~= "table" then
			error(`Path {TreeModel.FormatPath(path)} doesn't exist`, 0)
		end
		local copy = table.clone(node)
		local segment = path[depth]
		if depth == #path then
			mutate(copy, segment)
		else
			copy[segment] = Walk(node[segment], depth + 1)
		end
		return copy
	end
	return Walk(root, 1)
end

-- Returns a new root with the value at `path` replaced. Use Remove to delete.
function TreeModel.Set(root: any, path: Path, value: any): any
	assert(value ~= nil, "TreeModel.Set can't store nil; use TreeModel.Remove")
	if #path == 0 then
		return value
	end
	return EditParent(root, path, function(parent, key)
		parent[key] = value
	end)
end

-- Removes the value at `path`. Array items shift down so the array stays a
-- proper sequence (DataStores can't store holes).
function TreeModel.Remove(root: any, path: Path): any
	if #path == 0 then
		return nil
	end
	return EditParent(root, path, function(parent, key)
		if type(key) == "number" and Json.IsArray(parent) then
			table.remove(parent, key)
		else
			parent[key] = nil
		end
	end)
end

-- Renames an object key in place of `path`'s last segment.
function TreeModel.Rename(root: any, path: Path, newKey: string): any
	if newKey == "" then
		error("Key can't be empty", 0)
	end
	return EditParent(root, path, function(parent, oldKey)
		if oldKey == newKey then
			return
		end
		if parent[newKey] ~= nil then
			error(`Key "{newKey}" already exists`, 0)
		end
		parent[newKey] = parent[oldKey]
		parent[oldKey] = nil
	end)
end

-- Inserts `value` into the array at `arrayPath` so it ends up at `index`.
function TreeModel.Insert(root: any, arrayPath: Path, index: number, value: any): any
	local array = TreeModel.Get(root, arrayPath)
	if type(array) ~= "table" or not Json.IsArray(array) then
		error(`{TreeModel.FormatPath(arrayPath)} isn't an array`, 0)
	end
	local copy = table.clone(array)
	table.insert(copy, math.clamp(index, 1, #copy + 1), value)
	return if #arrayPath == 0 then copy else TreeModel.Set(root, arrayPath, copy)
end

-- Picks a key like "NewKey", "NewKey2", ... that isn't used in `object`.
function TreeModel.UniqueKey(object: { [any]: any }, base: string): string
	if object[base] == nil then
		return base
	end
	local suffix = 2
	while object[base .. suffix] ~= nil do
		suffix += 1
	end
	return base .. suffix
end

function TreeModel.DefaultValue(kind: Kind): any
	if kind == "String" then
		return ""
	elseif kind == "Number" then
		return 0
	elseif kind == "Boolean" then
		return false
	elseif kind == "Object" or kind == "Array" then
		return {}
	end
	return nil
end

-- Best-effort conversion used by "Change type". Scalars convert by text;
-- anything that can't convert falls back to the kind's default.
function TreeModel.ConvertValue(value: any, kind: Kind): any
	local currentKind: Kind = TreeModel.GetKind(value)
	if currentKind == kind then
		return value
	end
	if kind == "String" and not TreeModel.IsContainerKind(currentKind) then
		return if value == nil then "" else tostring(value)
	elseif kind == "Number" then
		return tonumber(value) or (if value == true then 1 else 0)
	elseif kind == "Boolean" then
		return value == true or value == "true" or (type(value) == "number" and value ~= 0)
	elseif kind == "Array" and currentKind == "Object" then
		-- Keep the values, drop the keys, in natural key order.
		local array = {}
		for _, key in TreeModel.SortedKeys(value) do
			table.insert(array, value[key])
		end
		return array
	elseif kind == "Object" and currentKind == "Array" then
		local object = {}
		for index, item in value do
			object[tostring(index)] = item
		end
		return object
	end
	return TreeModel.DefaultValue(kind)
end

local function ScalarText(value: any): string
	return if type(value) == "table" then "" else tostring(value)
end

-- Flattens the visible part of the tree into rows. The root is always row 1.
function TreeModel.Flatten(root: any, expanded: { [string]: boolean }, options: FlattenOptions?): { Row }
	local rows: { Row } = {}
	local filter = if options and options.Filter and options.Filter ~= "" then string.lower(options.Filter) else nil

	local function Matches(key: PathSegment?, value: any): boolean
		if filter == nil then
			return false
		end
		if key ~= nil and string.find(string.lower(tostring(key)), filter, 1, true) then
			return true
		end
		return string.find(string.lower(ScalarText(value)), filter, 1, true) ~= nil
	end

	-- With a filter, a subtree is visible only if something inside matches.
	local subtreeMatches: { [any]: boolean } = {}
	local function MarkMatches(key: PathSegment?, value: any): boolean
		local found = Matches(key, value)
		if type(value) == "table" then
			for childKey, child in value do
				if MarkMatches(childKey, child) then
					found = true
				end
			end
			subtreeMatches[value] = found
		end
		return found
	end
	if filter then
		MarkMatches(nil, root)
	end

	local function Visit(key: PathSegment?, value: any, path: Path, depth: number)
		local kind: Kind = TreeModel.GetKind(value)
		local id = TreeModel.PathId(path)
		local isContainer = TreeModel.IsContainerKind(kind)
		local isExpanded = if filter
			then isContainer and subtreeMatches[value] == true
			else isContainer and (depth == 0 or expanded[id] == true)

		table.insert(rows, {
			Id = id,
			Path = path,
			Depth = depth,
			Key = key,
			Kind = kind,
			Value = value,
			ChildCount = TreeModel.CountChildren(value),
			IsExpanded = isExpanded,
			IsMatch = Matches(key, value),
		})

		if not isExpanded then
			return
		end
		for _, childKey in TreeModel.SortedKeys(value) do
			local child = value[childKey]
			local childMatters = filter == nil
				or Matches(childKey, child)
				or (type(child) == "table" and subtreeMatches[child] == true)
			if childMatters then
				local childPath = table.clone(path)
				table.insert(childPath, childKey)
				Visit(childKey, child, childPath, depth + 1)
			end
		end
	end

	Visit(nil, root, {}, 0)
	return rows
end

-- Collects expansion ids for every container up to `maxDepth` levels deep.
function TreeModel.ExpandedIdsToDepth(root: any, maxDepth: number): { [string]: boolean }
	local expanded: { [string]: boolean } = {}
	local function Visit(value: any, path: Path, depth: number)
		if type(value) ~= "table" or depth > maxDepth then
			return
		end
		expanded[TreeModel.PathId(path)] = true
		for key, child in value do
			local childPath = table.clone(path)
			table.insert(childPath, key)
			Visit(child, childPath, depth + 1)
		end
	end
	Visit(root, {}, 0)
	return expanded
end

return TreeModel
