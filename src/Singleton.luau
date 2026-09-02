local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local IsServer = RunService:IsServer()

local Client = IsServer or require("./Client")
local Server = IsServer and require("./Server")
local Shared = require("./Shared")

function SingletonReplicationError()
	error(`Cannot add targets to a singleton.`)
end

return {
	new = function<T>(Identifier: string, Data: T, Player: Player?)
		if IsServer then
			Identifier ..= Player.UserId

			local Existing = Server.Get(Identifier)
			if Existing then
				return Existing
			end

			local Success = Server.WaitForReadyPlayer(Player)
			assert(Success, "Wait for player failed.")

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
	end :: (<T>(Identifier: string, DataTemplate: T & {}) -> Shared.ClientClass<T>) & (<T>(Identifier: string, Data: T & {}, Player: Player) -> Shared.ServerClass<T>),

	get = function<T>(Identifier: string, DataTemplate: T?, Player: Player?)
		return if Player
			then Server.GetFromIdentifier(Identifier .. Player.UserId)
			else Client.Get(Identifier .. Players.LocalPlayer.UserId)
	end :: (<T>(Identifier: string, DataTemplate: T?) -> Shared.ClientClass<T>?) & (<T>(Identifier: string, DataTemplate: T?, Player: Player) -> Shared.ServerClass<T>?),
}
