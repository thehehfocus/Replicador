const RunService = game:GetService("RunService")
const Players = game:GetService("Players")
const IsServer = RunService:IsServer()

const Client = require("./Client")
const Server = require("./Server")
const Shared = require("./Shared")

const SingletonReplicationError = function()
	error(`Cannot add targets to a singleton.`)
end

return function<T>(Identifier: string, Data: T, Player: Player?)
	if IsServer then
		Identifier ..= Player.UserId

		local Existing = Server.GetFromIdentifier(Identifier)
		if Existing then
			return Existing
		end

		local Success = Server.WaitForReadyPlayer(Player)
		if not Success then
			warn(`Wait for player failed.`)
			return
		end

		local Object = Server.Register({
			Identifier = Identifier,
			Data = Data,
		})

		Object:Subscribe(Player)

		Object.Replicate = SingletonReplicationError
		Object.Subscribe = SingletonReplicationError

		return Object
	else
		Identifier ..= Players.LocalPlayer.UserId

		local Object = Client.Get(Identifier) or Client.AwaitFor(Identifier)

		return Object
	end
end :: (<T>(Id: string, DataTemplate: T) -> Shared.ClientClass<T>) & (<T>(Id: string, Data: T, Player: Player) -> Shared.ServerClass<T>?)
