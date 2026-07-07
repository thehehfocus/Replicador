local Module = {}

local RunService = game:GetService("RunService")
local IsServer = RunService:IsServer()

local RemoteFolder = script

export type CustomEvent<Send = any> = {
	send: (data: Send) -> (),
	sendTo: (data: Send, player: Player) -> (),
	listen: (callback: (data: Send, player: Player?) -> ()) -> RBXScriptConnection,
}
export type CustomFunction<Send = any, Receive = any> = {
	send: (data: Send) -> Receive,
	sendTo: (data: Send, player: Player) -> Receive,
	listen: (callback: (data: Receive, player: Player?) -> Receive) -> RBXScriptConnection,
}

function Module.RegisterEvent(Name: string) : CustomEvent
	if IsServer then
		local Event = Instance.new("RemoteEvent", RemoteFolder)
		Event.Name = Name
		return {
			sendTo = function(data, player)
				Event:FireClient(player, data)
			end,
			listen = function(callback)
				return Event.OnServerEvent:Connect(function(player, data)
					callback(data, player)
				end)
			end,
		}
	else
		local Event = RemoteFolder:WaitForChild(Name) :: RemoteEvent
		return {
			send = function(data)
				Event:FireServer(data)
			end,
			listen = function(callback)
				return Event.OnClientEvent:Connect(callback)
			end,
		}
	end
end

function Module.RegisterFunction(Name: string) : CustomFunction
	if IsServer then
		local Event = Instance.new("RemoteFunction", RemoteFolder)
		Event.Name = Name
		return {
			send = function(data, player)
				return Event:InvokeClient(player, data)
			end,
			listen = function(callback)
				Event.OnServerInvoke = function(player, data)
					return callback(data, player)
				end
			end,
		}
	else
		local Event = RemoteFolder:WaitForChild(Name) :: RemoteFunction
		return {
			send = function(data)
				return Event:InvokeServer(data)
			end,
			listen = function(callback)
				Event.OnClientInvoke = callback
			end,
		}
	end
end

return Module