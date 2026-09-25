--!strict
--[[
	StoreRef
	Identifies one data store: its name, scope, and whether it's ordered.
]]

export type StoreRef = {
	Name: string,
	Scope: string,
	IsOrdered: boolean,
}

local StoreRef = {}

StoreRef.DEFAULT_SCOPE = "global"

function StoreRef.new(name: string, scope: string?, isOrdered: boolean?): StoreRef
	local trimmedScope = if scope then string.match(scope, "^%s*(.-)%s*$") :: string else ""
	return {
		Name = name,
		Scope = if trimmedScope == "" then StoreRef.DEFAULT_SCOPE else trimmedScope,
		IsOrdered = isOrdered == true,
	}
end

-- Stable string id, used as a settings key for favorites and recents.
function StoreRef.Id(ref: StoreRef): string
	return `{if ref.IsOrdered then "ordered" else "standard"}|{ref.Scope}|{ref.Name}`
end

function StoreRef.Equals(left: StoreRef?, right: StoreRef?): boolean
	if left == nil or right == nil then
		return left == right
	end
	return left.Name == right.Name and left.Scope == right.Scope and left.IsOrdered == right.IsOrdered
end

function StoreRef.Describe(ref: StoreRef): string
	local scopeSuffix = if ref.Scope == StoreRef.DEFAULT_SCOPE then "" else ` · {ref.Scope}`
	return `{ref.Name}{scopeSuffix}{if ref.IsOrdered then " · ordered" else ""}`
end

-- Checks a store name the way Roblox will, so mistakes surface before a
-- request is spent. Returns an error message, or nil when valid.
function StoreRef.ValidateName(name: string): string?
	if name == "" then
		return "Enter a data store name"
	end
	if #name > 50 then
		return "Data store names can be at most 50 characters"
	end
	return nil
end

return StoreRef
