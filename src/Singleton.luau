const RunService = game:GetService("RunService")
const Players = game:GetService("Players")
const IsServer = RunService:IsServer()

const Client = require("./Client")
const Server = require("./Server")
const Shared = require("./Shared")

const SingletonReplicationError = function()
	if IsServer then
		error(`Cannot replicate a singleton to more than one player.`)
	else
		error(`Got multiple instances of a singleton on client.`)
	end
end

const SingletonIdentifier = "•S-ton•"
const Singletons = {} :: {[Player]: {[string]: Shared.ServerClass<any>}}
if IsServer then
	Server.SignalPlayerRemoved:Connect(function(Player)
		Singletons[Player] = nil
	end)
end

return function<T>(Id: string, Data: T, Player: Player?)
	Id ..= SingletonIdentifier

	if IsServer then
		Id ..= Player.UserId

		local Success = Server.WaitForReadyPlayer(Player)
		if not Success then
			return 
		end

		if Singletons[Player] and Singletons[Player][Id] then
			return Singletons[Player][Id]
		elseif not Singletons[Player] then
			Singletons[Player] = {}
		end

		local Object = Server.Register(Data, Id)
		Object.Replicate = SingletonReplicationError

		local Subscribe = Object.Subscribe
		Object.Subscribe = function(self, Player)
			if #Object.IncludeList >= 1 then
				SingletonReplicationError()
			end
			return Subscribe(Object, Player)
		end
		Singletons[Player][Id] = Object
		
		Object:Subscribe(Player)

		return Object
	else
		Id ..= Players.LocalPlayer.UserId
		local Existing = Client.GetTagged(Id)
		if Existing and #Existing > 1 then
			SingletonReplicationError()
		end
		
		local Object = (Existing and Existing[1]) or Client.AwaitForTagged(Id)

		return Object
	end
end :: (
	<T>(Id: string, DataTemplate: T?) -> Shared.ClientClass<T>
) & (
	<T>(Id: string, Data: T, Player: Player) -> Shared.ServerClass<T>?
)
