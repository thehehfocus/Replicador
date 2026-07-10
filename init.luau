local Client = require("@self/src/Client")
local Server = require("@self/src/Server")
local Singleton = require("@self/src/Singleton")

export type ClientClass<T = {}> = Client.Class<T>
export type ServerClass<T = {}, Children = {}> = Server.Class<T, Children>

local Lib = {
	Client = Client,
	Server = Server,

	Singleton = Singleton,
}

return Lib
