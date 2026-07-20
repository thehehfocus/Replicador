local Client = require("@self/src/Client")
local Server = require("@self/src/Server")
local Singleton = require("@self/src/Singleton")

export type ClientClass<T = {}> = Client.Class<T>
export type ServerClass<T = {}, Children = {}> = Server.Class<T, Children>

local Lib = {
	Client = Client,
	Server = Server,
	
	--[=[
		Example usage.

		* Server:
		```lua
		local Data = Utils.Data
		local Object = Singleton("Example", Data, Player)
		assert(Object)

		Object.Data.Property = Value
		Object.Data.Array:Insert(Value, Index)
		```

		* Client:
		```lua
		local Data = Utils.Data
		local Object = Singleton("Example", Data)

		Object.Data.Property:OnSet(function(Value)
			-- ...
		end)
		```
		@param Identifier string - Singleton string, must not overlap with other singletons.
		@param Data T - The data replicated to the player. / It is required that Data table has same signature on both client and server, and does not contain nil values.
		@param Player Player? - Target of the singleton. On server only.
		@return ClientClass - Client object.
		@return ServerClass - An object with locked replication properties, targeted on one player. 
	]=]
	Singleton = Singleton,
}

return Lib
