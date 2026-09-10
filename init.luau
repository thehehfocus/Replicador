--!strict
local RunService = game:GetService("RunService")
local IsServer = RunService:IsServer()

local Server = if IsServer then require("@self/src/Server") else `Cannot access server library on client.`
local Client = if not IsServer then require("@self/src/Client") else `Cannot access client library on server.`

local Shared = require("@self/src/Shared")
local Singleton = require("@self/src/Singleton")

export type ServerClass<T = any> = Shared.ServerClass<T>
export type ClientClass<T = any> = Shared.ClientClass<T>

export type ComputeType<T, IsServer> = Shared.ComputeType<T, IsServer>

type Client = typeof(require("@self/src/Client"))
type Server = typeof(require("@self/src/Server"))

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
		Singleton one instance per-player wrapper, single function simplicity.
	]=]
	Singleton = Singleton,
} :: {
	Client: Client,
	Server: Server,
	Singleton: typeof(Singleton),
}

return Lib
