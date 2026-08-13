--!strict
local Client = require("@self/src/Client")
local Server = require("@self/src/Server")
local Shared = require("@self/src/Shared")
local Singleton = require("@self/src/Singleton")

export type ClientClass<T = any> = Shared.ClientClass<T>
export type ServerClass<T = any> = Shared.ServerClass<T>

export type ComputeTypeClient<T> = Shared.ComputeTypeClient<T>
export type ComputeTypeServer<T> = Shared.ComputeTypeServer<T>

export type Callable<T> = Shared.Call<T>

local Lib = {
	--[=[
		ClientSide API for the library.
	]=]
	Client = Client,

	--[=[
		ServerSide API for the library.
	]=]
	Server = Server,
	
	--[=[
		Singleton one instance per-player wrapper
	]=]
	Singleton = Singleton,
}

return Lib
