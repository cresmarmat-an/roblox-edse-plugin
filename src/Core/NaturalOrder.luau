--!strict
--[[
	NaturalOrder
	Human-friendly ordering for keys: case-insensitive, and digit runs compare
	by numeric value, so "Slot2" sorts before "Slot10".
]]

local NaturalOrder = {}

-- Compares two digit runs without converting to numbers, so arbitrarily long
-- runs (e.g. 30-digit ids) never lose precision.
local function CompareDigitRuns(leftDigits: string, rightDigits: string): number
	local leftTrimmed = string.gsub(leftDigits, "^0+", "")
	local rightTrimmed = string.gsub(rightDigits, "^0+", "")
	if #leftTrimmed ~= #rightTrimmed then
		return if #leftTrimmed < #rightTrimmed then -1 else 1
	end
	if leftTrimmed ~= rightTrimmed then
		return if leftTrimmed < rightTrimmed then -1 else 1
	end
	return 0
end

-- Returns true when `left` should sort before `right`.
function NaturalOrder.Less(left: string, right: string): boolean
	local leftIndex, rightIndex = 1, 1
	local leftLength, rightLength = #left, #right

	while leftIndex <= leftLength and rightIndex <= rightLength do
		local leftDigits = string.match(left, "^%d+", leftIndex)
		local rightDigits = string.match(right, "^%d+", rightIndex)

		if leftDigits and rightDigits then
			local comparison = CompareDigitRuns(leftDigits, rightDigits)
			if comparison ~= 0 then
				return comparison < 0
			end
			leftIndex += #leftDigits
			rightIndex += #rightDigits
		else
			local leftCharacter = string.lower(string.sub(left, leftIndex, leftIndex))
			local rightCharacter = string.lower(string.sub(right, rightIndex, rightIndex))
			if leftCharacter ~= rightCharacter then
				return leftCharacter < rightCharacter
			end
			leftIndex += 1
			rightIndex += 1
		end
	end

	local leftRemaining = leftLength - leftIndex
	local rightRemaining = rightLength - rightIndex
	if leftRemaining ~= rightRemaining then
		return leftRemaining < rightRemaining
	end
	-- Equal under natural rules ("a1" vs "A01"): fall back to raw bytes so the
	-- order is still total and deterministic.
	return left < right
end

-- Orders mixed table keys: numbers first (ascending), then strings naturally.
function NaturalOrder.LessKey(left: any, right: any): boolean
	local leftIsNumber = type(left) == "number"
	local rightIsNumber = type(right) == "number"
	if leftIsNumber and rightIsNumber then
		return left < right
	end
	if leftIsNumber ~= rightIsNumber then
		return leftIsNumber
	end
	return NaturalOrder.Less(tostring(left), tostring(right))
end

return NaturalOrder
