--!strict
--[[
	Signal
	A minimal synchronous event. Handlers run in connection order on the
	firing thread. Connecting or disconnecting while a Fire is in progress
	only affects later fires, because Fire iterates over a snapshot.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	type Record = { Connection: Connection, Handler: (T...) -> () }
	local records: { Record } = {}

	local function Connect(_self: Signal<T...>, handler: (T...) -> ()): Connection
		local connection: Connection
		local record: Record

		connection = {
			Connected = true,
			Disconnect = function(_connection: Connection)
				if not connection.Connected then
					return
				end
				connection.Connected = false
				local index = table.find(records, record)
				if index then
					table.remove(records, index)
				end
			end,
		}
		record = { Connection = connection, Handler = handler }
		table.insert(records, record)
		return connection
	end

	local signal: Signal<T...>
	signal = {
		Connect = Connect,

		Once = function(self: Signal<T...>, handler: (T...) -> ()): Connection
			local connection: Connection
			connection = Connect(self, function(...: T...)
				connection:Disconnect()
				handler(...)
			end)
			return connection
		end,

		Fire = function(_self: Signal<T...>, ...: T...)
			for _, record in table.clone(records) do
				if record.Connection.Connected then
					record.Handler(...)
				end
			end
		end,

		DisconnectAll = function(_self: Signal<T...>)
			for _, record in table.clone(records) do
				record.Connection:Disconnect()
			end
		end,
	}
	return signal
end

return Signal
