--!strict
local RunService = game:GetService("RunService")
local IsServer = RunService:IsServer()

local Client = IsServer or require("@self/src/Client")
local Server = IsServer and require("@self/src/Server")
local Shared = require("@self/src/Shared")
local Singleton = require("@self/src/Singleton")

export type ClientClass<T = any> = Shared.ClientClass<T>
export type ServerClass<T = any> = Shared.ServerClass<T>

export type ComputeType<T, IsServer> = Shared.ComputeType<T, IsServer>
export type Callable<T> = Shared.Call<T>

local Lib = {
	--[=[
		ClientSide API for the library.
	]=]
	Client = Client or "Cannot access client on server.",

	--[=[
		ServerSide API for the library.
	]=]
	Server = Server or "Cannot access server on client.",

	--[=[
		Singleton one instance per-player wrapper
	]=]
	Singleton = Singleton,
}

return Lib
