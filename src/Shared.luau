--!strict
local Shared = {}

-- Wrapper for remotes.
local RemoteWrapper = require("./RemoteWrapper")
local Signal = require("./Signal")

local Namespace = {
	packets = {
		ObjectCreated = RemoteWrapper.RegisterEvent("ObjectCreated"),
		ObjectDestroyed = RemoteWrapper.RegisterEvent("ObjectDestroyed"),

		Set = RemoteWrapper.RegisterEvent("Set"),
		RequestData = RemoteWrapper.RegisterEvent("RequestData"),

		Insert = RemoteWrapper.RegisterEvent("Insert"),
		Remove = RemoteWrapper.RegisterEvent("Remove"),
	}
}

--[[
local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local BytenetMax = require(Packages.ByteNetMax)
local _IdType = BytenetMax and BytenetMax.uint8

if BytenetMax then
	Namespace = BytenetMax.defineNamespace("__replicador__", function()
		return {
			packets = {
				ObjectCreated = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = _IdType,
						[2] = BytenetMax.unknown,
						[3] = BytenetMax.array(BytenetMax.unknown),
						[4] = BytenetMax.optional(BytenetMax.string),
					}
				}),
				ObjectDestroyed = BytenetMax.definePacket({
					value = _IdType
				}),

				Set = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = _IdType, 
						[2] = BytenetMax.array(BytenetMax.unknown),
						[3] = BytenetMax.optional(BytenetMax.unknown)
					}
				}),
				RequestData = BytenetMax.definePacket({
					value = BytenetMax.nothing,
				}),

				Insert = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = _IdType,
						[2] = BytenetMax.array(BytenetMax.string),
						[3] = BytenetMax.optional(BytenetMax.unknown)
					}
				}),
				Remove = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = _IdType,
						[2] = BytenetMax.array(BytenetMax.string),
					}
				}),
			},
		}
	end)
end
--]]

Shared.Packets = Namespace.packets

function Shared.DeepCopy<T>(Original: T, MTSave: boolean?, Visited: {[{}]: {}}?) : T
	if type(Original) ~= "table" then
		return Original
	end

	Visited = Visited or {}
	if Visited[Original] then
		return Visited[Original]
	end

	local Copy = {}
	Visited[Original] = Copy

	if MTSave then
		local mt = getmetatable(Original)
		if type(mt) == "table" then
			setmetatable(Copy, mt)
		end
	end

	for Key, Value in Original :: any do
		(Copy::any)[Shared.DeepCopy(Key, MTSave, Visited)] = Shared.DeepCopy(Value, MTSave, Visited)
	end

	return Copy
end

export type PathType = {any}
export type Action = "Set"|"Insert"|"Remove"

type Disconnect = (Disconnect: nil) -> ()

export type Call<Data> = (self: any, Set: (Data | (Data) -> Data)?) -> Data

type Mt<T, A = nil> = {
	__index: T,
	__call: A,
}

type DictMethodsServer<Data = any, Key = any, Value = any> = ValueMethodsServer<Data>
type DictMethodsClient<Data = any, Key = any, Value = any> = {
	OnKeyChange: (self: any, Callback: (Key: Key, Value: Value, OldValue: Value) -> ()) -> Disconnect,

	-- ValueMethodsClient
	OnChange: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Disconnect,
	Get: (self: any) -> Data,
	Set: (self: any, Data: Data) -> (),
}

type ArrayMethodsServer<T = any, Data = any> = {
	Insert: (self: any, Value: Data, Index: number?) -> (),
	Remove: (self: any, Index: number?) -> (),
	
	-- ValueMethodsServer
	Get: (self: any) -> Data,
	Set: (self: any, Data: Data) -> (),
}
type ArrayMethodsClient<Data = any, Value = any> = {
	OnKeyChange: (self: any, Callback: (Key: number, Value: Value, OldValue: Value) -> ()) -> Disconnect,
	OnInsert: (self: any, Callback: (Value: Value, Index: number) -> ()) -> Disconnect,
	OnRemove: (self: any, Callback: (RemovedValue: Value, Index: number) -> ()) -> Disconnect,

	-- ValueMethodsClient
	OnChange: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Disconnect,
	Get: (self: any) -> Data,
	Set: (self: any, Data: Data) -> (),
}

type ValueMethodsServer<Data> = {
	Get: (self: any) -> Data,
	Set: (self: any, Data: Data) -> (),
}
type ValueMethodsClient<Data> = {
	OnChange: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Disconnect,

	Get: (self: any) -> Data,
	Set: (self: any, Data: Data) -> (),
}

export type function ComputeType(Type: type, IsServer: type)
	local IsTable = Type:is("table") 
	local IsServerValue = IsServer:value()
	
	local New = types.newtable()
	local MetatableType = nil

	if IsTable then
		for i,v in Type:properties() do
			New:setproperty(i, ComputeType(v.read, IsServer))
		end

		local DictMethods = if IsServerValue then DictMethodsServer else DictMethodsClient
		local ArrayMethods = if IsServerValue then ArrayMethodsServer else ArrayMethodsClient

		local Indexer = IsTable and Type:readindexer()
		if Indexer then
			New:setindexer(Indexer.index, ComputeType(Indexer.result, IsServer))
			
			MetatableType = if Indexer.index:is("number") then
				ArrayMethods and ArrayMethods(Type, Indexer.result)
			else
				DictMethods and DictMethods(Type, Indexer.index, Indexer.result)
		else
			MetatableType = DictMethods and DictMethods(Type, types.any, types.any)
		end
	else
		local ValueMethods = if IsServerValue then ValueMethodsServer else ValueMethodsClient

		MetatableType = ValueMethods and ValueMethods(Type)
	end
		
	if MetatableType then
		New:setmetatable(Mt(MetatableType, Call(Type)))
	end
	--New = types.intersectionof(New, Call(Type))

	return New
end

export type ClientClass<T = any> = {
	Id: number,
	read Data: ComputeType<T, false>,
	Tags: {string},
	Identifier: string?,

	SignalChanged: Signal.Signal<PathType, any, Action>,
	SignalDestroyed: Signal.Signal<ClientClass<T>>,

	--[[
		Whether the Object is being replicated.
	]]
	Active: boolean?,

	PathSet: (self: ClientClass<T>, Path: PathType, Value: any) -> (),
	PathGet: (self: ClientClass<T>, Path: PathType, IgnoreLast: number?) -> any,
}

export type ServerClass<T = any> = {
	Id: number,
	read Data: ComputeType<T, true>,
	Tags: {string},
	Identifier: string?,

	SignalChanged: Signal.Signal<PathType, any, Action>,

	--[[
		Whether the object is not destroyed.
	]]
	Active: boolean?,

	PathSet: (self: ServerClass<T>, Path: PathType, Value: any) -> (),
	PathGet: (self: ServerClass<T>, Path: PathType, IgnoreLast: number?) -> (),

	--[[
		If object is replicated to the player.
	]]
	IsTarget: (self: ServerClass<T>, Player: Player) -> boolean?,
	--[[
		Iterates through all replicated players.
	]]
	IterateTargets: (self: ServerClass<T>, Callback: (Player: Player) -> ()) -> (),

	--[[
		Replicates the Object to all Ready Players.
		Clears the Include/Exclude lists.
	]]
	Replicate: (self: ServerClass<T>) -> ServerClass<T>,
	--[[
		Removes replication from all players.
		Clears Include/Exclude lists.
	]]
	Unreplicate: (self: ServerClass<T>) -> ServerClass<T>,
	
	--[[
		Adds the specified player to the replication.
	]]
	Subscribe: (self: ServerClass<T>, Player: Player) -> ServerClass<T>,
	--[[
		Removes the specified player from the replication.
	]]
	Unsubscribe: (self: ServerClass<T>, Player: Player) -> ServerClass<T>,
	
	--[[
		Clears the replica and removes replication.
	]]
	Destroy: (self: ServerClass<T>) -> (),
}

return Shared
