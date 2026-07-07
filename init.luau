local Client = require("@self/src/Client")
local Server = require("@self/src/Server")
local Shared = require("@self/src/Shared")

export type ClientClass<T = {}> = Client.Class<T>
export type ServerClass<T = {}, Children = {}> = Server.Class<T, Children>

return {
	Client = Client,
	Server = Server,
	Shared = Shared,
}