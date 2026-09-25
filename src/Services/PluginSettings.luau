--!strict
--[[
	PluginSettings
	Persistent preferences and per-experience memory (last store, recent
	stores, recent keys, favorites), stored with plugin:SetSetting.

	The storage object is injected so this module works with a fake in tests.
	Per-experience data is keyed by GameId so favorites from one game never
	show up in another.
]]

local StoreRef = require(script.Parent.Parent.Core.StoreRef)

export type Storage = {
	GetSetting: (self: any, key: string) -> any,
	SetSetting: (self: any, key: string, value: any) -> (),
}

type ExperienceState = {
	LastStore: StoreRef.StoreRef?,
	RecentStores: { StoreRef.StoreRef },
	RecentKeys: { [string]: { string } },
	Favorites: { [string]: { string } },
}

export type PluginSettings = {
	GetString: (self: PluginSettings, name: string, default: string) -> string,
	SetString: (self: PluginSettings, name: string, value: string) -> (),
	GetBoolean: (self: PluginSettings, name: string, default: boolean) -> boolean,
	SetBoolean: (self: PluginSettings, name: string, value: boolean) -> (),

	GetLastStore: (self: PluginSettings) -> StoreRef.StoreRef?,
	GetRecentStores: (self: PluginSettings) -> { StoreRef.StoreRef },
	RememberStore: (self: PluginSettings, ref: StoreRef.StoreRef) -> (),

	GetRecentKeys: (self: PluginSettings, ref: StoreRef.StoreRef) -> { string },
	RememberKey: (self: PluginSettings, ref: StoreRef.StoreRef, key: string) -> (),
	ForgetKey: (self: PluginSettings, ref: StoreRef.StoreRef, key: string) -> (),

	GetFavorites: (self: PluginSettings, ref: StoreRef.StoreRef) -> { string },
	IsFavorite: (self: PluginSettings, ref: StoreRef.StoreRef, key: string) -> boolean,
	ToggleFavorite: (self: PluginSettings, ref: StoreRef.StoreRef, key: string) -> boolean,
}

local SETTINGS_PREFIX = "EDSE."
local MAX_RECENT_STORES = 8
local MAX_RECENT_KEYS = 12
local MAX_FAVORITES = 100

local PluginSettings = {}

local function ReadSetting(storage: Storage, key: string): any
	-- GetSetting can fail if Studio's settings file is unreadable; treat that
	-- as "no saved value" rather than breaking the plugin.
	local ok, value = pcall(storage.GetSetting, storage, SETTINGS_PREFIX .. key)
	return if ok then value else nil
end

local function WriteSetting(storage: Storage, key: string, value: any)
	local ok, message = pcall(function()
		storage:SetSetting(SETTINGS_PREFIX .. key, value)
	end)
	if not ok then
		warn(`[EDSE] Couldn't save setting {key}: {message}`)
	end
end

local function SanitizeStoreRef(raw: any): StoreRef.StoreRef?
	if type(raw) ~= "table" or type(raw.Name) ~= "string" then
		return nil
	end
	return StoreRef.new(raw.Name, if type(raw.Scope) == "string" then raw.Scope else nil, raw.IsOrdered == true)
end

local function SanitizeStringList(raw: any): { string }
	local list: { string } = {}
	if type(raw) == "table" then
		for _, item in raw do
			if type(item) == "string" then
				table.insert(list, item)
			end
		end
	end
	return list
end

-- Moves `item` to the front of `list`, removing duplicates, capped at `limit`.
local function PushFront<T>(list: { T }, item: T, isSame: (T, T) -> boolean, limit: number): { T }
	local result = { item }
	for _, existing in list do
		if #result >= limit then
			break
		end
		if not isSame(existing, item) then
			table.insert(result, existing)
		end
	end
	return result
end

local function StringsEqual(left: string, right: string): boolean
	return left == right
end

function PluginSettings.new(storage: Storage, experienceId: string): PluginSettings
	local experienceKey = `Experience.{experienceId}`

	local function LoadExperience(): ExperienceState
		local raw = ReadSetting(storage, experienceKey)
		local state: ExperienceState = { LastStore = nil, RecentStores = {}, RecentKeys = {}, Favorites = {} }
		if type(raw) ~= "table" then
			return state
		end
		state.LastStore = SanitizeStoreRef(raw.LastStore)
		if type(raw.RecentStores) == "table" then
			for _, rawRef in raw.RecentStores do
				local ref = SanitizeStoreRef(rawRef)
				if ref then
					table.insert(state.RecentStores, ref)
				end
			end
		end
		for _, field in { "RecentKeys", "Favorites" } do
			local rawMap = raw[field]
			if type(rawMap) == "table" then
				for storeId, keys in rawMap do
					if type(storeId) == "string" then
						(state :: any)[field][storeId] = SanitizeStringList(keys)
					end
				end
			end
		end
		return state
	end

	local experience = LoadExperience()

	local function SaveExperience()
		WriteSetting(storage, experienceKey, experience)
	end

	local settings: PluginSettings
	settings = {
		GetString = function(_self: PluginSettings, name: string, default: string): string
			local value = ReadSetting(storage, name)
			return if type(value) == "string" then value else default
		end,

		SetString = function(_self: PluginSettings, name: string, value: string)
			WriteSetting(storage, name, value)
		end,

		GetBoolean = function(_self: PluginSettings, name: string, default: boolean): boolean
			local value = ReadSetting(storage, name)
			return if type(value) == "boolean" then value else default
		end,

		SetBoolean = function(_self: PluginSettings, name: string, value: boolean)
			WriteSetting(storage, name, value)
		end,

		GetLastStore = function(_self: PluginSettings): StoreRef.StoreRef?
			return experience.LastStore
		end,

		GetRecentStores = function(_self: PluginSettings): { StoreRef.StoreRef }
			return table.clone(experience.RecentStores)
		end,

		RememberStore = function(_self: PluginSettings, ref: StoreRef.StoreRef)
			experience.LastStore = ref
			experience.RecentStores = PushFront(experience.RecentStores, ref, StoreRef.Equals, MAX_RECENT_STORES)
			SaveExperience()
		end,

		GetRecentKeys = function(_self: PluginSettings, ref: StoreRef.StoreRef): { string }
			return table.clone(experience.RecentKeys[StoreRef.Id(ref)] or {})
		end,

		RememberKey = function(_self: PluginSettings, ref: StoreRef.StoreRef, key: string)
			local storeId = StoreRef.Id(ref)
			experience.RecentKeys[storeId] =
				PushFront(experience.RecentKeys[storeId] or {}, key, StringsEqual, MAX_RECENT_KEYS)
			SaveExperience()
		end,

		ForgetKey = function(_self: PluginSettings, ref: StoreRef.StoreRef, key: string)
			local storeId = StoreRef.Id(ref)
			for _, field in { "RecentKeys", "Favorites" } do
				local list = (experience :: any)[field][storeId]
				local index = if list then table.find(list, key) else nil
				if index then
					table.remove(list, index)
				end
			end
			SaveExperience()
		end,

		GetFavorites = function(_self: PluginSettings, ref: StoreRef.StoreRef): { string }
			return table.clone(experience.Favorites[StoreRef.Id(ref)] or {})
		end,

		IsFavorite = function(_self: PluginSettings, ref: StoreRef.StoreRef, key: string): boolean
			local favorites = experience.Favorites[StoreRef.Id(ref)]
			return favorites ~= nil and table.find(favorites, key) ~= nil
		end,

		ToggleFavorite = function(_self: PluginSettings, ref: StoreRef.StoreRef, key: string): boolean
			local storeId = StoreRef.Id(ref)
			local favorites = experience.Favorites[storeId] or {}
			local index = table.find(favorites, key)
			if index then
				table.remove(favorites, index)
			elseif #favorites < MAX_FAVORITES then
				table.insert(favorites, key)
				table.sort(favorites)
			else
				warn(`[EDSE] Favorites are limited to {MAX_FAVORITES} keys per store`)
				return false
			end
			experience.Favorites[storeId] = favorites
			SaveExperience()
			return index == nil
		end,
	}
	return settings
end

return PluginSettings
