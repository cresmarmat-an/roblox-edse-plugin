--!strict
--[[
	DataStoreGateway
	The only module that talks to DataStoreService. Every call:
	  * waits (briefly) for request budget instead of failing when throttled,
	  * retries transient failures (throttling, 5xx) with backoff,
	  * returns a Result instead of throwing, with a human hint for common
	    setup problems (unpublished place, Studio API access disabled).

	Writes go through UpdateAsync with a version check, so saving never
	silently overwrites a change a live server made after you loaded the key.
	All functions yield; call them from a spawned thread.
]]

local DataStoreService = game:GetService("DataStoreService")

local EntrySession = require(script.Parent.Parent.Core.EntrySession)
local Json = require(script.Parent.Parent.Core.Json)
local Log = require(script.Parent.Log)
local StoreRef = require(script.Parent.Parent.Core.StoreRef)

export type GatewayError = {
	Code: number?,
	Message: string,
	Hint: string?,
}

export type Result<T> = { Ok: true, Value: T } | { Ok: false, Error: GatewayError }

export type Pager<T> = {
	IsFinished: (self: Pager<T>) -> boolean,
	LoadNext: (self: Pager<T>) -> Result<{ T }>,
}

export type StoreListing = { Name: string, UpdatedTime: number }
export type KeyListing = { Key: string, Value: number? } -- Value only for ordered stores
export type VersionListing = { Version: string, CreatedTime: number, IsDeleted: boolean }

export type WriteOutcome = {
	Conflict: boolean,
	Entry: EntrySession.Entry?,
}

local DataStoreGateway = {}

DataStoreGateway.MAX_KEY_LENGTH = 50
DataStoreGateway.MAX_VALUE_CHARACTERS = 4194304
DataStoreGateway.KEY_PAGE_SIZE = 50
DataStoreGateway.STORE_PAGE_SIZE = 50
DataStoreGateway.VERSION_PAGE_SIZE = 25

local MAX_ATTEMPTS = 3
local RETRY_BASE_DELAY_SECONDS = 1
local BUDGET_POLL_SECONDS = 0.5
local BUDGET_WAIT_LIMIT_SECONDS = 12

-- Request categories. Each lists enum names newest-first; the first one this
-- Studio build supports is used, so the plugin works across budget models.
type BudgetCategory = "Read" | "Write" | "List" | "Sorted"
local BUDGET_REQUEST_TYPES: { [BudgetCategory]: { string } } = {
	Read = { "StandardRead", "GetAsync" },
	Write = { "StandardWrite", "SetIncrementAsync" },
	List = { "StandardList", "ListAsync" },
	Sorted = { "OrderedList", "GetSortedAsync" },
}

local resolvedRequestTypes: { [BudgetCategory]: Enum.DataStoreRequestType | false } = {}

local function ResolveRequestType(category: BudgetCategory): Enum.DataStoreRequestType?
	local cached = resolvedRequestTypes[category]
	if cached == false then
		return nil
	elseif cached ~= nil then
		return cached :: Enum.DataStoreRequestType
	end
	for _, enumName in BUDGET_REQUEST_TYPES[category] do
		local ok, requestType = pcall(function()
			local item = (Enum.DataStoreRequestType :: any)[enumName] :: Enum.DataStoreRequestType
			DataStoreService:GetRequestBudgetForRequestType(item)
			return item
		end)
		if ok then
			resolvedRequestTypes[category] = requestType
			return requestType
		end
	end
	resolvedRequestTypes[category] = false
	return nil
end

-- Current budget for a category, or nil when Studio can't report it.
function DataStoreGateway.GetBudget(category: BudgetCategory): number?
	local requestType = ResolveRequestType(category)
	if requestType == nil then
		return nil
	end
	local ok, budget = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, requestType)
	return if ok then budget else nil
end

local function WaitForBudget(category: BudgetCategory)
	local waited = 0
	while waited < BUDGET_WAIT_LIMIT_SECONDS do
		local budget = DataStoreGateway.GetBudget(category)
		if budget == nil or budget > 0 then
			if waited > 0 then
				Log.Info(`Request budget available again after {string.format("%.1f", waited)}s`)
			end
			return
		end
		if waited == 0 then
			Log.Warning(
				`Out of DataStore {string.lower(category)} budget; waiting for it to refill`,
				"Roblox limits requests per minute. EDSE waits instead of failing."
			)
		end
		waited += task.wait(BUDGET_POLL_SECONDS)
	end
	-- Out of patience: let the request go and let Roblox queue or reject it.
	Log.Warning(
		`Still no {string.lower(category)} budget after {BUDGET_WAIT_LIMIT_SECONDS}s; sending the request anyway`
	)
end

local function ParseError(raw: any): GatewayError
	local message = tostring(raw)
	local code = tonumber(string.match(message, "^(%d+):"))
	local lowered = string.lower(message)
	local hint: string? = nil

	if string.find(lowered, "publish", 1, true) then
		hint = "Publish this place first (File → Publish to Roblox). DataStores only exist for published experiences."
	elseif
		string.find(lowered, "studioaccesstoapis", 1, true)
		or string.find(lowered, "api access", 1, true)
		or string.find(lowered, "403", 1, true)
		or string.find(lowered, "forbidden", 1, true)
	then
		hint = "Turn on Game Settings → Security → Enable Studio Access to API Services, then try again."
	elseif code == 101 or code == 102 then
		hint = `Keys must be 1–{DataStoreGateway.MAX_KEY_LENGTH} characters.`
	elseif code == 105 then
		hint = "The value is larger than the 4 MB DataStore limit."
	elseif code and code >= 301 and code <= 306 then
		hint = "Roblox is throttling requests. Wait a moment and try again."
	end

	return { Code = code, Message = message, Hint = hint }
end

local function IsRetriable(failure: GatewayError): boolean
	local code = failure.Code
	if code == nil then
		return false
	end
	return (code >= 301 and code <= 306) or code >= 500
end

-- Runs `operation` with budget waiting and retries. `operation` may yield.
local function Invoke<T>(category: BudgetCategory, operation: () -> T): Result<T>
	local lastError: GatewayError = { Message = "Request didn't run" }
	for attempt = 1, MAX_ATTEMPTS do
		WaitForBudget(category)
		local ok, value = pcall(operation)
		if ok then
			return { Ok = true, Value = value }
		end
		lastError = ParseError(value)
		if not IsRetriable(lastError) or attempt == MAX_ATTEMPTS then
			break
		end
		local delaySeconds = RETRY_BASE_DELAY_SECONDS * 2 ^ (attempt - 1)
		Log.Warning(
			`Request failed; retrying in {delaySeconds}s (attempt {attempt + 1} of {MAX_ATTEMPTS})`,
			lastError.Message
		)
		task.wait(delaySeconds)
	end
	return { Ok = false, Error = lastError }
end

local function Fail<T>(message: string, hint: string?): Result<T>
	return { Ok = false, Error = { Message = message, Hint = hint } }
end

function DataStoreGateway.ValidateKey(key: string): string?
	if key == "" then
		return "Enter a key"
	end
	if #key > DataStoreGateway.MAX_KEY_LENGTH then
		return `Keys can be at most {DataStoreGateway.MAX_KEY_LENGTH} characters`
	end
	return nil
end

local function GetStandardStore(ref: StoreRef.StoreRef): DataStore
	return DataStoreService:GetDataStore(ref.Name, ref.Scope)
end

local function GetOrderedStore(ref: StoreRef.StoreRef): OrderedDataStore
	return DataStoreService:GetOrderedDataStore(ref.Name, ref.Scope)
end

-- Wraps a Roblox Pages object. The first LoadNext fetches page one; later
-- calls advance. `fetch` creates the Pages object (a yielding request).
local function CreatePager<T>(category: BudgetCategory, fetch: () -> Pages, mapItem: (any) -> T?): Pager<T>
	local pages: Pages? = nil
	local isFinished = false

	local pager: Pager<T>
	pager = {
		IsFinished = function(_self: Pager<T>): boolean
			return isFinished
		end,

		LoadNext = function(_self: Pager<T>): Result<{ T }>
			if isFinished then
				return { Ok = true, Value = {} }
			end
			local result = Invoke(category, function(): { any }
				if pages == nil then
					pages = fetch()
				else
					(pages :: Pages):AdvanceToNextPageAsync()
				end
				return (pages :: Pages):GetCurrentPage()
			end)
			if not result.Ok then
				return result :: any
			end
			isFinished = (pages :: Pages).IsFinished
			local items: { T } = {}
			for _, rawItem in result.Value do
				local item = mapItem(rawItem)
				if item ~= nil then
					table.insert(items, item)
				end
			end
			return { Ok = true, Value = items }
		end,
	}
	return pager
end

function DataStoreGateway.ListStores(prefix: string): Pager<StoreListing>
	return CreatePager("List", function(): Pages
		return DataStoreService:ListDataStoresAsync(prefix, DataStoreGateway.STORE_PAGE_SIZE)
	end, function(info: DataStoreInfo): StoreListing
		return { Name = info.DataStoreName, UpdatedTime = info.UpdatedTime }
	end)
end

-- Standard stores list keys by prefix. Ordered stores list by value (the
-- prefix is ignored because Roblox can't filter ordered stores by key).
function DataStoreGateway.ListKeys(ref: StoreRef.StoreRef, prefix: string, isAscending: boolean?): Pager<KeyListing>
	if ref.IsOrdered then
		return CreatePager("Sorted", function(): Pages
			return GetOrderedStore(ref):GetSortedAsync(isAscending == true, DataStoreGateway.KEY_PAGE_SIZE)
		end, function(item: any): KeyListing
			return { Key = item.key, Value = item.value }
		end)
	end
	return CreatePager("List", function(): Pages
		return GetStandardStore(ref):ListKeysAsync(prefix, DataStoreGateway.KEY_PAGE_SIZE, "", true)
	end, function(keyInstance: DataStoreKey): KeyListing
		return { Key = keyInstance.KeyName }
	end)
end

local function EntryFromKeyInfo(value: any, keyInfo: DataStoreKeyInfo?): EntrySession.Entry
	if keyInfo == nil then
		local entry = EntrySession.EmptyEntry()
		entry.Exists = value ~= nil
		entry.Value = value
		return entry
	end
	local info = keyInfo :: DataStoreKeyInfo
	return {
		Exists = true,
		Value = value,
		UserIds = info:GetUserIds(),
		Metadata = info:GetMetadata(),
		Version = info.Version,
		CreatedTime = info.CreatedTime,
		UpdatedTime = info.UpdatedTime,
	}
end

-- Reads the live value, bypassing Studio's read cache.
function DataStoreGateway.ReadEntry(ref: StoreRef.StoreRef, key: string): Result<EntrySession.Entry>
	local keyProblem = DataStoreGateway.ValidateKey(key)
	if keyProblem then
		return Fail(keyProblem)
	end
	if ref.IsOrdered then
		return Invoke("Read", function(): EntrySession.Entry
			local value = GetOrderedStore(ref):GetAsync(key)
			return EntryFromKeyInfo(value, nil)
		end)
	end
	return Invoke("Read", function(): EntrySession.Entry
		local options = Instance.new("DataStoreGetOptions")
		options.UseCache = false
		local value, keyInfo = GetStandardStore(ref):GetAsync(key, options)
		return EntryFromKeyInfo(value, keyInfo)
	end)
end

-- Checks a draft before any request is spent on it.
function DataStoreGateway.ValidateDraft(ref: StoreRef.StoreRef, draft: EntrySession.Snapshot): string?
	if draft.Value == nil then
		return "The value is empty. Use Delete to remove a key."
	end
	if ref.IsOrdered then
		if type(draft.Value) ~= "number" or draft.Value % 1 ~= 0 then
			return "Ordered data stores only hold whole numbers."
		end
		return nil
	end
	local ok, encoded = pcall(Json.Encode, draft.Value)
	if not ok then
		return tostring(encoded)
	end
	if #encoded > DataStoreGateway.MAX_VALUE_CHARACTERS then
		return `The value is {#encoded} characters; the limit is {DataStoreGateway.MAX_VALUE_CHARACTERS}.`
	end
	for _, userId in draft.UserIds do
		if type(userId) ~= "number" or userId % 1 ~= 0 or userId <= 0 then
			return `User ID {tostring(userId)} isn't a positive whole number.`
		end
	end
	return nil
end

--[[
	Saves `draft` if the key is still at `expectedVersion` (nil = the key
	didn't exist when loaded). On a mismatch nothing is written and the outcome
	reports Conflict = true. Pass `force` to write regardless.
	Ordered stores have no versions, so there the loaded value is compared.
]]
function DataStoreGateway.WriteEntry(
	ref: StoreRef.StoreRef,
	key: string,
	draft: EntrySession.Snapshot,
	loaded: EntrySession.Entry,
	force: boolean
): Result<WriteOutcome>
	local problem = DataStoreGateway.ValidateKey(key) or DataStoreGateway.ValidateDraft(ref, draft)
	if problem then
		return Fail(problem)
	end

	if ref.IsOrdered then
		return Invoke("Write", function(): WriteOutcome
			local conflict = false
			-- Returning nil from the transform cancels the write; Roblox's type
			-- definitions don't model that, hence the cast.
			local transform = function(current: number?): number?
				conflict = not force and current ~= loaded.Value
				if conflict then
					return nil
				end
				return draft.Value
			end
			local newValue = GetOrderedStore(ref):UpdateAsync(key, transform :: any)
			if conflict then
				return { Conflict = true, Entry = nil }
			end
			return { Conflict = false, Entry = EntryFromKeyInfo(newValue, nil) }
		end)
	end

	return Invoke("Write", function(): WriteOutcome
		local conflict = false
		local newValue, keyInfo = GetStandardStore(ref):UpdateAsync(
			key,
			function(_current: any, currentInfo: DataStoreKeyInfo?): (any, { number }?, { [string]: any }?)
				local currentVersion = if currentInfo then currentInfo.Version else nil
				-- The transform can run more than once (Roblox retries it), so
				-- the flag is recomputed on every call.
				conflict = not force and currentVersion ~= loaded.Version
				if conflict then
					return nil
				end
				-- Always return user ids and metadata explicitly so they're kept
				-- (or edited) rather than depending on UpdateAsync's defaults.
				return draft.Value, draft.UserIds, draft.Metadata
			end
		)
		if conflict then
			return { Conflict = true, Entry = nil }
		end
		return { Conflict = false, Entry = EntryFromKeyInfo(newValue, keyInfo) }
	end)
end

function DataStoreGateway.RemoveEntry(ref: StoreRef.StoreRef, key: string): Result<boolean>
	local keyProblem = DataStoreGateway.ValidateKey(key)
	if keyProblem then
		return Fail(keyProblem)
	end
	return Invoke("Write", function(): boolean
		if ref.IsOrdered then
			GetOrderedStore(ref):RemoveAsync(key)
		else
			GetStandardStore(ref):RemoveAsync(key)
		end
		return true
	end)
end

-- Adds `delta` to an ordered entry atomically and returns the new value.
function DataStoreGateway.Increment(ref: StoreRef.StoreRef, key: string, delta: number): Result<number>
	return Invoke("Write", function(): number
		return GetOrderedStore(ref):IncrementAsync(key, delta)
	end)
end

function DataStoreGateway.ListVersions(ref: StoreRef.StoreRef, key: string): Pager<VersionListing>
	return CreatePager("List", function(): Pages
		return GetStandardStore(ref):ListVersionsAsync(
			key,
			Enum.SortDirection.Descending,
			0,
			0,
			DataStoreGateway.VERSION_PAGE_SIZE
		)
	end, function(info: DataStoreObjectVersionInfo): VersionListing
		return { Version = info.Version, CreatedTime = info.CreatedTime, IsDeleted = info.IsDeleted }
	end)
end

function DataStoreGateway.ReadVersion(ref: StoreRef.StoreRef, key: string, version: string): Result<EntrySession.Entry>
	return Invoke("Read", function(): EntrySession.Entry
		local value, keyInfo = GetStandardStore(ref):GetVersionAsync(key, version)
		return EntryFromKeyInfo(value, keyInfo)
	end)
end

return DataStoreGateway
