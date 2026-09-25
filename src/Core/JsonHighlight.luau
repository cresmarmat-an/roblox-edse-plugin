--!strict
--[[
	JsonHighlight
	Turns JSON text into RichText markup with syntax colors. It tokenizes
	leniently (it must render half-typed, invalid JSON without complaint), and
	every character of the input appears in the output exactly once, so the
	highlighted overlay lines up with the editable text beneath it.
]]

export type Colors = {
	Key: string, -- hex without "#", e.g. "2b3445"
	String: string,
	Number: string,
	Boolean: string,
	Null: string,
	Punctuation: string,
}

local JsonHighlight = {}

local RICH_TEXT_ESCAPES = {
	["<"] = "&lt;",
	[">"] = "&gt;",
	["&"] = "&amp;",
	['"'] = "&quot;",
	["'"] = "&apos;",
}

local function Escape(text: string): string
	return (string.gsub(text, "[<>&\"']", RICH_TEXT_ESCAPES))
end

local function Wrap(text: string, color: string): string
	return `<font color="#{color}">{Escape(text)}</font>`
end

-- Returns the end index of the string literal starting at `start` (a quote),
-- or the end of the line when it's unterminated.
local function ScanString(text: string, start: number): number
	local index = start + 1
	local length = #text
	while index <= length do
		local character = string.sub(text, index, index)
		if character == "\\" then
			index += 2
		elseif character == '"' then
			return index
		elseif character == "\n" then
			return index - 1
		else
			index += 1
		end
	end
	return length
end

function JsonHighlight.ToRichText(text: string, colors: Colors): string
	local output: { string } = {}
	local index = 1
	local length = #text

	while index <= length do
		local character = string.sub(text, index, index)

		if character == '"' then
			local finish = ScanString(text, index)
			-- A string followed by a colon is an object key.
			local afterString = string.match(text, "^%s*(.)", finish + 1)
			local color = if afterString == ":" then colors.Key else colors.String
			table.insert(output, Wrap(string.sub(text, index, finish), color))
			index = finish + 1
		elseif string.match(character, "[%-%d]") then
			local number = string.match(text, "^%-?[%d%.eE%+%-]*", index) :: string
			table.insert(output, Wrap(number, colors.Number))
			index += #number
		elseif string.match(character, "%a") then
			local word = string.match(text, "^%a+", index) :: string
			local color = if word == "true" or word == "false"
				then colors.Boolean
				elseif word == "null" then colors.Null
				else colors.Punctuation
			table.insert(output, Wrap(word, color))
			index += #word
		elseif string.match(character, "[{}%[%],:]") then
			table.insert(output, Wrap(character, colors.Punctuation))
			index += 1
		else
			-- Whitespace and anything unexpected pass through, escaped.
			local run = string.match(text, '^[^"%-%d%a{}%[%],:]+', index) :: string
			table.insert(output, Escape(run))
			index += #run
		end
	end

	return table.concat(output)
end

-- Strips the markup again; used by tests to prove no text is lost.
function JsonHighlight.StripRichText(markup: string): string
	local plain = string.gsub(markup, "<[^>]*>", "")
	plain = string.gsub(plain, "&lt;", "<")
	plain = string.gsub(plain, "&gt;", ">")
	plain = string.gsub(plain, "&quot;", '"')
	plain = string.gsub(plain, "&apos;", "'")
	plain = string.gsub(plain, "&amp;", "&")
	return plain
end

return JsonHighlight
