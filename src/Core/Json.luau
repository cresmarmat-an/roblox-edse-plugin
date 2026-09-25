--!strict
--[[
	Json
	A JSON codec tuned for DataStore editing. HttpService:JSONEncode gives no
	pretty-printing or stable key order, and JSONDecode gives no line/column on
	errors, so the editor needs its own.

	Decode is deliberately a little lenient where it helps people typing by
	hand: trailing commas are accepted, and `null` object members are dropped
	(a DataStore can't hold them anyway). `null` inside an array is rejected,
	because it would leave a hole that DataStores can't store.
]]

local Json = {}

export type EncodeOptions = {
	-- Indentation unit. nil produces compact single-line output.
	Indent: string?,
	-- Ordering for object keys. Defaults to plain byte order.
	KeyLess: ((left: string, right: string) -> boolean)?,
	-- Arrays of scalars that fit within this many characters stay on one line
	-- when pretty-printing. 0 disables inlining.
	InlineArrayWidth: number?,
}

export type DecodeError = {
	Message: string,
	Line: number,
	Column: number,
	Position: number,
}

local MAX_DEPTH = 200
local DEFAULT_INLINE_ARRAY_WIDTH = 72
local MAX_SAFE_INTEGER = 2 ^ 53

local ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local UNESCAPES: { [string]: string } = {
	['"'] = '"',
	["\\"] = "\\",
	["/"] = "/",
	["b"] = "\b",
	["f"] = "\f",
	["n"] = "\n",
	["r"] = "\r",
	["t"] = "\t",
}

-- True for a table whose keys are exactly 1..n. Empty tables count as arrays,
-- matching HttpService:JSONEncode({}) == "[]".
function Json.IsArray(value: { [any]: any }): boolean
	local count = 0
	for key in value do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end
		count += 1
	end
	return count == #value
end

function Json.EscapeString(text: string): string
	local escaped = string.gsub(text, '[%c"\\]', function(character: string): string
		return ESCAPES[character] or string.format("\\u%04x", string.byte(character))
	end)
	return '"' .. escaped .. '"'
end

function Json.FormatNumber(number: number): string
	if number ~= number then
		error("NaN can't be stored in a DataStore", 0)
	end
	if number == math.huge or number == -math.huge then
		error("Infinity can't be stored in a DataStore", 0)
	end
	if number % 1 == 0 and math.abs(number) < MAX_SAFE_INTEGER then
		return string.format("%d", number)
	end
	local text = string.format("%.14g", number)
	if tonumber(text) ~= number then
		text = string.format("%.17g", number)
	end
	return text
end

local function DescribePath(path: { string }): string
	return if #path == 0 then "the root" else table.concat(path)
end

-- Encodes `value` as JSON. Errors (with a readable message) on values a
-- DataStore can't hold: cycles, NaN/Infinity, mixed tables, non-JSON types.
function Json.Encode(value: any, options: EncodeOptions?): string
	local indentUnit = if options then options.Indent else nil
	local keyLess = if options and options.KeyLess then options.KeyLess else nil
	local inlineWidth = if options and options.InlineArrayWidth
		then options.InlineArrayWidth
		else DEFAULT_INLINE_ARRAY_WIDTH
	local isPretty = indentUnit ~= nil and indentUnit ~= ""

	local visiting: { [any]: boolean } = {}
	local path: { string } = {}
	local output: { string } = {}

	local EncodeValue: (value: any, depth: number) -> ()

	local function Newline(depth: number)
		if isPretty then
			table.insert(output, "\n" .. string.rep(indentUnit :: string, depth))
		end
	end

	local function TryInlineArray(array: { any }): string?
		if not isPretty or inlineWidth <= 0 then
			return nil
		end
		local parts = table.create(#array)
		local width = 2
		for index, item in array do
			local itemType = type(item)
			if itemType == "table" then
				return nil
			end
			local text = if itemType == "string"
				then Json.EscapeString(item)
				elseif itemType == "number" then Json.FormatNumber(item)
				elseif itemType == "boolean" then tostring(item)
				else nil
			if text == nil then
				return nil
			end
			width += #text + (if index > 1 then 2 else 0)
			if width > inlineWidth then
				return nil
			end
			parts[index] = text
		end
		return "[" .. table.concat(parts, ", ") .. "]"
	end

	local function EncodeTable(tableValue: { [any]: any }, depth: number)
		if visiting[tableValue] then
			error(`Cycle detected at {DescribePath(path)}`, 0)
		end
		if depth > MAX_DEPTH then
			error(`Nesting is deeper than {MAX_DEPTH} levels at {DescribePath(path)}`, 0)
		end
		visiting[tableValue] = true

		if Json.IsArray(tableValue) then
			if #tableValue == 0 then
				table.insert(output, "[]")
			else
				local inline = TryInlineArray(tableValue)
				if inline then
					table.insert(output, inline)
				else
					table.insert(output, "[")
					for index, item in ipairs(tableValue) do
						if index > 1 then
							table.insert(output, ",")
						end
						Newline(depth + 1)
						table.insert(path, `[{index}]`)
						EncodeValue(item, depth + 1)
						table.remove(path)
					end
					Newline(depth)
					table.insert(output, "]")
				end
			end
		else
			local keys: { string } = {}
			for key in tableValue do
				if type(key) ~= "string" then
					error(
						`Mixed or sparse table at {DescribePath(path)}: key {tostring(key)} isn't a string, and DataStores only store arrays or string-keyed objects`,
						0
					)
				end
				table.insert(keys, key)
			end
			table.sort(keys, keyLess)

			table.insert(output, "{")
			for index, key in keys do
				if index > 1 then
					table.insert(output, ",")
				end
				Newline(depth + 1)
				table.insert(output, Json.EscapeString(key))
				table.insert(output, if isPretty then ": " else ":")
				table.insert(path, `.{key}`)
				EncodeValue(tableValue[key], depth + 1)
				table.remove(path)
			end
			Newline(depth)
			table.insert(output, "}")
		end

		visiting[tableValue] = nil
	end

	function EncodeValue(item: any, depth: number)
		local itemType = type(item)
		if item == nil then
			table.insert(output, "null")
		elseif itemType == "boolean" then
			table.insert(output, tostring(item))
		elseif itemType == "number" then
			local ok, text = pcall(Json.FormatNumber, item)
			if not ok then
				error(`{text} (at {DescribePath(path)})`, 0)
			end
			table.insert(output, text)
		elseif itemType == "string" then
			table.insert(output, Json.EscapeString(item))
		elseif itemType == "table" then
			EncodeTable(item, depth)
		else
			error(`A {typeof(item)} at {DescribePath(path)} can't be stored in a DataStore`, 0)
		end
	end

	EncodeValue(value, 0)
	return table.concat(output)
end

local function LocatePosition(text: string, position: number): (number, number)
	local line = 1
	local lineStart = 1
	local searchFrom = 1
	while true do
		local newlineAt = string.find(text, "\n", searchFrom, true)
		if newlineAt == nil or newlineAt >= position then
			break
		end
		line += 1
		lineStart = newlineAt + 1
		searchFrom = newlineAt + 1
	end
	return line, position - lineStart + 1
end

-- Decodes JSON text. Returns (true, value) or (false, DecodeError).
-- A top-level `null` decodes to (true, nil).
function Json.Decode(text: string): (boolean, any)
	local position = 1
	local length = #text

	local function Fail(message: string, at: number?): never
		local failPosition = math.clamp(at or position, 1, math.max(length, 1))
		local line, column = LocatePosition(text, failPosition)
		error({ Message = message, Line = line, Column = column, Position = failPosition } :: DecodeError, 0)
	end

	local function SkipWhitespace()
		local _, finish = string.find(text, "^[ \t\r\n]*", position)
		position = (finish :: number) + 1
	end

	local function Peek(): string
		return string.sub(text, position, position)
	end

	local function DescribeFound(): string
		if position > length then
			return "end of input"
		end
		local character = Peek()
		return if character == "\n" then "a line break" else `'{character}'`
	end

	local DecodeValue: (depth: number) -> any

	local function DecodeString(): string
		local start = position
		position += 1 -- opening quote
		local parts: { string } = {}
		while true do
			local specialAt = string.find(text, '["\\%c]', position)
			if specialAt == nil then
				Fail("Unterminated string", start)
			end
			local specialAtIndex = specialAt :: number
			table.insert(parts, string.sub(text, position, specialAtIndex - 1))
			local character = string.sub(text, specialAtIndex, specialAtIndex)
			if character == '"' then
				position = specialAtIndex + 1
				return table.concat(parts)
			elseif character == "\\" then
				local escape = string.sub(text, specialAtIndex + 1, specialAtIndex + 1)
				if escape == "u" then
					local hex = string.match(text, "^%x%x%x%x", specialAtIndex + 2)
					if hex == nil then
						Fail("Expected 4 hex digits after \\u", specialAtIndex)
					end
					local codepoint = tonumber(hex, 16) :: number
					position = specialAtIndex + 6
					if codepoint >= 0xD800 and codepoint <= 0xDBFF then
						local lowHex = string.match(text, "^\\u(%x%x%x%x)", position)
						local low = if lowHex then tonumber(lowHex, 16) :: number else nil
						if low == nil or low < 0xDC00 or low > 0xDFFF then
							Fail("Unpaired UTF-16 surrogate in \\u escape", specialAtIndex)
						end
						codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + ((low :: number) - 0xDC00)
						position += 6
					end
					table.insert(parts, utf8.char(codepoint))
				else
					local replacement = UNESCAPES[escape]
					if replacement == nil then
						Fail(`Invalid escape '\\{escape}'`, specialAtIndex)
					end
					table.insert(parts, replacement)
					position = specialAtIndex + 2
				end
			else
				Fail(
					if character == "\n"
						then 'Line break inside a string (use \\n, or close the string with ")'
						else "Control character inside a string",
					specialAtIndex
				)
			end
		end
	end

	local function DecodeNumber(): number
		local start = position
		local integerPart = string.match(text, "^-?%d+", position)
		if integerPart == nil then
			Fail(`Unexpected {DescribeFound()}`)
		end
		position += #(integerPart :: string)
		local fraction = string.match(text, "^%.%d+", position)
		if fraction then
			position += #fraction
		elseif Peek() == "." then
			Fail("Expected digits after the decimal point")
		end
		local exponent = string.match(text, "^[eE][-+]?%d+", position)
		if exponent then
			position += #exponent
		end
		local number = tonumber(string.sub(text, start, position - 1))
		if number == nil or number ~= number or number == math.huge or number == -math.huge then
			Fail("Number is out of range", start)
		end
		return number :: number
	end

	local function ExpectLiteral(word: string, result: any): any
		if string.sub(text, position, position + #word - 1) ~= word then
			Fail(`Unexpected {DescribeFound()}`)
		end
		position += #word
		return result
	end

	local function DecodeArray(depth: number): { any }
		local array = {}
		position += 1 -- [
		SkipWhitespace()
		if Peek() == "]" then
			position += 1
			return array
		end
		while true do
			SkipWhitespace()
			if Peek() == "]" then -- trailing comma
				position += 1
				return array
			end
			local itemStart = position
			local item = DecodeValue(depth + 1)
			if item == nil then
				Fail("null can't be stored inside an array (it would leave a hole)", itemStart)
			end
			table.insert(array, item)
			SkipWhitespace()
			local separator = Peek()
			if separator == "," then
				position += 1
			elseif separator == "]" then
				position += 1
				return array
			else
				Fail(`Expected ',' or ']' but found {DescribeFound()}`)
			end
		end
	end

	local function DecodeObject(depth: number): { [string]: any }
		local object: { [string]: any } = {}
		local seen: { [string]: boolean } = {}
		position += 1 -- {
		while true do
			SkipWhitespace()
			local character = Peek()
			if character == "}" then
				position += 1
				return object
			end
			if character ~= '"' then
				Fail(`Expected a "quoted" key but found {DescribeFound()}`)
			end
			local keyStart = position
			local key = DecodeString()
			if seen[key] then
				Fail(`Duplicate key "{key}"`, keyStart)
			end
			seen[key] = true
			SkipWhitespace()
			if Peek() ~= ":" then
				Fail(`Expected ':' after key "{key}" but found {DescribeFound()}`)
			end
			position += 1
			object[key] = DecodeValue(depth + 1)
			SkipWhitespace()
			local separator = Peek()
			if separator == "," then
				position += 1
			elseif separator == "}" then
				position += 1
				return object
			else
				Fail(`Expected ',' or '}' but found {DescribeFound()}`)
			end
		end
	end

	function DecodeValue(depth: number): any
		if depth > MAX_DEPTH then
			Fail(`Nesting is deeper than {MAX_DEPTH} levels`)
		end
		SkipWhitespace()
		local character = Peek()
		if character == "{" then
			return DecodeObject(depth)
		elseif character == "[" then
			return DecodeArray(depth)
		elseif character == '"' then
			return DecodeString()
		elseif character == "t" then
			return ExpectLiteral("true", true)
		elseif character == "f" then
			return ExpectLiteral("false", false)
		elseif character == "n" then
			return ExpectLiteral("null", nil)
		elseif character == "-" or string.match(character, "%d") then
			return DecodeNumber()
		elseif position > length then
			Fail("Expected a value but the text is empty")
		end
		return Fail(`Unexpected {DescribeFound()}`)
	end

	local ok, result = pcall(function()
		local value = DecodeValue(0)
		SkipWhitespace()
		if position <= length then
			Fail(`Unexpected {DescribeFound()} after the value`)
		end
		return value
	end)

	if ok then
		return true, result
	end
	if type(result) == "table" then
		return false, result
	end
	-- A non-table error means a bug in this decoder rather than bad input.
	return false, { Message = `Internal decoder error: {tostring(result)}`, Line = 1, Column = 1, Position = 1 }
end

return Json
