--!strict
--[[
	EntrySession
	The editing state of one open key: the snapshot loaded from the data store
	(Original) and the working copy (Draft). Every editor panel reads the draft
	and writes through the Set* methods, tagging each write with its source so
	a panel can skip re-rendering the change it just made itself (the JSON
	editor must not reset the text you are typing, for example).
]]

local Diff = require(script.Parent.Diff)
local Signal = require(script.Parent.Signal)
local StoreRef = require(script.Parent.StoreRef)
local TreeModel = require(script.Parent.TreeModel)

export type Snapshot = {
	Value: any,
	UserIds: { number },
	Metadata: { [string]: any },
}

export type Entry = {
	Exists: boolean,
	Value: any,
	UserIds: { number },
	Metadata: { [string]: any },
	Version: string?,
	CreatedTime: number?,
	UpdatedTime: number?,
}

export type Changes = {
	Value: { Diff.Change },
	IsValueTruncated: boolean,
	UserIdsChanged: boolean,
	Metadata: { Diff.Change },
	IsEmpty: boolean,
}

export type EntrySession = {
	StoreRef: StoreRef.StoreRef,
	Key: string,
	Original: Entry,
	Draft: Snapshot,
	-- Fires after any draft or original change, with the source tag.
	Changed: Signal.Signal<string>,

	SetValue: (self: EntrySession, value: any, source: string) -> (),
	SetUserIds: (self: EntrySession, userIds: { number }, source: string) -> (),
	SetMetadata: (self: EntrySession, metadata: { [string]: any }, source: string) -> (),
	IsDirty: (self: EntrySession) -> boolean,
	GetChanges: (self: EntrySession) -> Changes,
	Revert: (self: EntrySession) -> (),
	Reset: (self: EntrySession, entry: Entry, source: string) -> (),
	Destroy: (self: EntrySession) -> (),
}

local EntrySession = {}

EntrySession.SOURCE_LOAD = "Load"
EntrySession.SOURCE_REVERT = "Revert"

function EntrySession.EmptyEntry(): Entry
	return { Exists = false, Value = nil, UserIds = {}, Metadata = {} }
end

local function SnapshotOf(entry: Entry): Snapshot
	return {
		Value = entry.Value,
		UserIds = table.clone(entry.UserIds),
		Metadata = table.clone(entry.Metadata),
	}
end

function EntrySession.new(storeRef: StoreRef.StoreRef, key: string, entry: Entry): EntrySession
	local changed = Signal.new() :: Signal.Signal<string>
	local isDirty = false
	local session: EntrySession

	local function Recompute(source: string)
		isDirty = not TreeModel.DeepEqual(session.Draft.Value, session.Original.Value)
			or not TreeModel.DeepEqual(session.Draft.UserIds, session.Original.UserIds)
			or not TreeModel.DeepEqual(session.Draft.Metadata, session.Original.Metadata)
		changed:Fire(source)
	end

	session = {
		StoreRef = storeRef,
		Key = key,
		Original = entry,
		Draft = SnapshotOf(entry),
		Changed = changed,

		SetValue = function(self: EntrySession, value: any, source: string)
			self.Draft.Value = value
			Recompute(source)
		end,

		SetUserIds = function(self: EntrySession, userIds: { number }, source: string)
			self.Draft.UserIds = userIds
			Recompute(source)
		end,

		SetMetadata = function(self: EntrySession, metadata: { [string]: any }, source: string)
			self.Draft.Metadata = metadata
			Recompute(source)
		end,

		IsDirty = function(_self: EntrySession): boolean
			return isDirty
		end,

		GetChanges = function(self: EntrySession): Changes
			local valueChanges, isTruncated = Diff.Compute(self.Original.Value, self.Draft.Value)
			local metadataChanges = Diff.Compute(self.Original.Metadata, self.Draft.Metadata)
			local userIdsChanged = not TreeModel.DeepEqual(self.Original.UserIds, self.Draft.UserIds)
			return {
				Value = valueChanges,
				IsValueTruncated = isTruncated,
				UserIdsChanged = userIdsChanged,
				Metadata = metadataChanges,
				IsEmpty = #valueChanges == 0 and #metadataChanges == 0 and not userIdsChanged,
			}
		end,

		Revert = function(self: EntrySession)
			self.Draft = SnapshotOf(self.Original)
			Recompute(EntrySession.SOURCE_REVERT)
		end,

		Reset = function(self: EntrySession, newEntry: Entry, source: string)
			self.Original = newEntry
			self.Draft = SnapshotOf(newEntry)
			Recompute(source)
		end,

		Destroy = function(_self: EntrySession)
			changed:DisconnectAll()
		end,
	}
	return session
end

return EntrySession
