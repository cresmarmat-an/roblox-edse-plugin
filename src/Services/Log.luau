--!strict
--[[
	Log
	Everything EDSE reports (loads, saves, conflicts, warnings, errors,
	retries) is recorded here with a timestamp, and shown in the Output
	panel. Unlike a toast, nothing is lost or cut off: long messages keep
	their full text and optional detail lines, and the last MAX_ENTRIES
	entries stay browsable.

	Pure Luau (no Roblox APIs), so it is unit-tested outside Studio.
]]

local Signal = require(script.Parent.Parent.Core.Signal)

export type Level = "Info" | "Success" | "Warning" | "Error"

export type Entry = {
	Id: number,
	Time: number, -- os.time()
	Level: Level,
	Message: string,
	Detail: string?,
}

export type Counts = { Info: number, Success: number, Warning: number, Error: number }

-- Anything shaped like a gateway error (a message plus an optional hint).
export type ErrorLike = { Message: string, Hint: string? }

local Log = {}

Log.MAX_ENTRIES = 500
Log.LEVELS = { "Info", "Success", "Warning", "Error" } :: { Level }

Log.Added = Signal.new() :: Signal.Signal<Entry>
Log.Cleared = Signal.new() :: Signal.Signal<>

local LEVEL_TAGS: { [Level]: string } = {
	Info = "INFO",
	Success = "DONE",
	Warning = "WARN",
	Error = "ERROR",
}

local entries: { Entry } = {}
local nextId = 0
local mirror: ((entry: Entry) -> ())? = nil

function Log.Add(level: Level, message: string, detail: string?): Entry
	nextId += 1
	local entry: Entry = {
		Id = nextId,
		Time = os.time(),
		Level = level,
		Message = message,
		Detail = if detail == nil or detail == "" then nil else detail,
	}
	table.insert(entries, entry)
	while #entries > Log.MAX_ENTRIES do
		table.remove(entries, 1)
	end
	if mirror then
		-- A failing mirror (e.g. output throttling) must never break logging.
		pcall(mirror, entry)
	end
	Log.Added:Fire(entry)
	return entry
end

function Log.Info(message: string, detail: string?): Entry
	return Log.Add("Info", message, detail)
end

function Log.Success(message: string, detail: string?): Entry
	return Log.Add("Success", message, detail)
end

function Log.Warning(message: string, detail: string?): Entry
	return Log.Add("Warning", message, detail)
end

function Log.Error(message: string, detail: string?): Entry
	return Log.Add("Error", message, detail)
end

-- Logs `summary` as an error, with the underlying message and hint as detail.
function Log.Failure(summary: string, failure: ErrorLike): Entry
	local detail = if failure.Hint then `{failure.Message}\n{failure.Hint}` else failure.Message
	return Log.Error(summary, detail)
end

function Log.Entries(): { Entry }
	return table.clone(entries)
end

function Log.Counts(): Counts
	local counts: Counts = { Info = 0, Success = 0, Warning = 0, Error = 0 }
	for _, entry in entries do
		local level = entry.Level
		if level == "Info" then
			counts.Info += 1
		elseif level == "Success" then
			counts.Success += 1
		elseif level == "Warning" then
			counts.Warning += 1
		else
			counts.Error += 1
		end
	end
	return counts
end

function Log.Clear()
	table.clear(entries)
	Log.Cleared:Fire()
end

function Log.Tag(level: Level): string
	return LEVEL_TAGS[level]
end

function Log.FormatTime(entry: Entry): string
	return os.date("%H:%M:%S", entry.Time)
end

-- One entry as plain text: "[12:03:44] ERROR  message" plus indented detail.
function Log.FormatEntry(entry: Entry): string
	local line = `[{Log.FormatTime(entry)}] {LEVEL_TAGS[entry.Level]}  {entry.Message}`
	if entry.Detail then
		line ..= "\n    " .. string.gsub(entry.Detail, "\n", "\n    ")
	end
	return line
end

function Log.ToText(): string
	local lines = table.create(#entries)
	for index, entry in entries do
		lines[index] = Log.FormatEntry(entry)
	end
	return table.concat(lines, "\n")
end

-- Also send every entry somewhere else (e.g. Studio's Output window).
function Log.SetMirror(callback: ((entry: Entry) -> ())?)
	mirror = callback
end

return Log
