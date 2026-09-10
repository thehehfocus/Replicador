local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local IsServer = RunService:IsServer()

local Client: typeof(require("./Client")) = IsServer or require("./Client")
local Server: typeof(require("./Server")) = IsServer and require("./Server")
local Shared = require("./Shared")

return {
	new = function<T>(Identifier: string, Data: T, Player: Player?)
		Data = Shared.DeepCopy(Data)

		if IsServer and typeof(Player) == "Instance" and Player.ClassName == "Player" then
			Identifier ..= Player.UserId

			local Existing = Server.Get(Identifier)
			if Existing then
				return Existing
			end

			local Success = Server.WaitForReadyPlayer(Player)
			assert(Success, `{Identifier}: Wait for player {Player} failed.`)

			local Object = Server.Register({
				Identifier = Identifier,
				Data = Data,
			})
			Object:Subscribe(Player)

			return Object
		elseif not IsServer and not Player then
			Identifier ..= Players.LocalPlayer.UserId

			local Object = Client.Get(Identifier) or Client.AwaitFor(Identifier)

			return Object
		else
			error(`Invalid parameter 'Player' {Player} for RunContext {IsServer and "Server" or "Client"}, expected {IsServer and "Player" or nil}`)
		end
	end :: (<T>(Identifier: string, DataTemplate: T & {}) -> Shared.ClientClass<T>) & (<T>(Identifier: string, Data: T & {}, Player: Player) -> Shared.ServerClass<T>),

	get = function<T>(Identifier: string, DataTemplate: T?, Player: Player?)
		if Player and IsServer then 
			return Server.GetFromIdentifier(Identifier .. Player.UserId)
		elseif not IsServer then
			return Client.Get(Identifier .. Players.LocalPlayer.UserId)
		end
		
		return nil
	end :: (<T>(Identifier: string, DataTemplate: T?) -> Shared.ClientClass<T>?) & (<T>(Identifier: string, DataTemplate: T?, Player: Player) -> Shared.ServerClass<T>?),

	init = function()
		if IsServer then
			Server.Init()
		else
			Client.Init()
		end
	end,
}
