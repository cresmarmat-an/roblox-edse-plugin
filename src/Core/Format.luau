--!strict
--[[
	Format
	Small, pure text formatters shared by the views.
]]

local Json = require(script.Parent.Json)

local Format = {}

local BYTES_PER_KILOBYTE = 1024
local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = 3600
local SECONDS_PER_DAY = 86400
local SECONDS_PER_MONTH = 30 * SECONDS_PER_DAY
local MILLISECONDS_PER_SECOND = 1000

function Format.Bytes(byteCount: number): string
	if byteCount < BYTES_PER_KILOBYTE then
		return `{byteCount} B`
	elseif byteCount < BYTES_PER_KILOBYTE ^ 2 then
		return string.format("%.1f KB", byteCount / BYTES_PER_KILOBYTE)
	end
	return string.format("%.2f MB", byteCount / BYTES_PER_KILOBYTE ^ 2)
end

-- "just now", "5m ago", "3h ago", "2d ago", then a calendar date.
function Format.RelativeTime(epochMilliseconds: number, nowMilliseconds: number): string
	local seconds = math.max(0, (nowMilliseconds - epochMilliseconds) / MILLISECONDS_PER_SECOND)
	if seconds < 45 then
		return "just now"
	elseif seconds < SECONDS_PER_HOUR then
		return `{math.max(1, math.round(seconds / SECONDS_PER_MINUTE))}m ago`
	elseif seconds < SECONDS_PER_DAY then
		return `{math.floor(seconds / SECONDS_PER_HOUR)}h ago`
	elseif seconds < SECONDS_PER_MONTH then
		return `{math.floor(seconds / SECONDS_PER_DAY)}d ago`
	end
	return Format.Date(epochMilliseconds)
end

function Format.Date(epochMilliseconds: number): string
	return os.date("%Y-%m-%d", math.floor(epochMilliseconds / MILLISECONDS_PER_SECOND))
end

function Format.DateTime(epochMilliseconds: number): string
	return os.date("%Y-%m-%d %H:%M:%S", math.floor(epochMilliseconds / MILLISECONDS_PER_SECOND))
end

function Format.Plural(count: number, singular: string, plural: string?): string
	return `{count} {if count == 1 then singular else plural or singular .. "s"}`
end

-- Shortens `text` to at most `maxLength` characters, ending with "…".
function Format.Truncate(text: string, maxLength: number): string
	local characterCount = utf8.len(text)
	if characterCount == nil then
		-- Not valid UTF-8: fall back to cutting by bytes.
		return if #text <= maxLength then text else string.sub(text, 1, maxLength - 1) .. "…"
	end
	if characterCount <= maxLength then
		return text
	end
	-- Cut on a character boundary so multi-byte characters never split.
	local cutAt = utf8.offset(text, maxLength) :: number
	return string.sub(text, 1, cutAt - 1) .. "…"
end

-- One-line summary of any value, for lists, diffs and tooltips.
function Format.Preview(value: any, maxLength: number?): string
	local limit = maxLength or 60
	local valueType = type(value)
	if value == nil then
		return "null"
	elseif valueType == "string" then
		return Format.Truncate(Json.EscapeString(value), limit)
	elseif valueType == "number" then
		local ok, text = pcall(Json.FormatNumber, value)
		return if ok then text else tostring(value)
	elseif valueType == "table" then
		local count = 0
		for _ in value do
			count += 1
		end
		if Json.IsArray(value) then
			return if count == 0 then "[ ]" else `[ {Format.Plural(count, "item")} ]`
		end
		return `\{ {Format.Plural(count, "key")} }`
	end
	return tostring(value)
end

-- Encoded size as a DataStore would count it (compact JSON, UTF-8 bytes).
function Format.EncodedSize(value: any): number?
	local ok, text = pcall(Json.Encode, value)
	return if ok then #text else nil
end

return Format
