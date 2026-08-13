--!strict
local Shared = {}

-- Config

-- Change these if you have ByteNetMax.
--local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local BytenetMax = nil::any --require(Packages.ByteNetMax)
local IdType = BytenetMax and BytenetMax.uint16

-- Wrapper for remotes.
local RemoteWrapper = require("./RemoteWrapper")
local Signal = require("./Signal")

local Namespace

if BytenetMax then
	Namespace = BytenetMax.defineNamespace("__Replicador__", function()
		return {
			packets = {
				ObjectCreated = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = IdType,
						[2] = BytenetMax.unknown,
						[3] = BytenetMax.array(BytenetMax.string),
						[4] = BytenetMax.optional(BytenetMax.string),
					}
				}),
				ObjectDestroyed = BytenetMax.definePacket({
					value = IdType
				}),

				Set = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = IdType, 
						[2] = BytenetMax.array(BytenetMax.string),
						[3] = BytenetMax.optional(BytenetMax.unknown)
					}
				}),

				RequestData = BytenetMax.definePacket({
					value = BytenetMax.nothing,
				}),

				Insert = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = IdType,
						[2] = BytenetMax.array(BytenetMax.string),
						[3] = BytenetMax.optional( BytenetMax.unknown)
					}
				}),
				Remove = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = IdType,
						[2] = BytenetMax.array(BytenetMax.string),
					}
				}),

				Message = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = IdType,
						[2] = BytenetMax.unknown,
					},
					reliabilityType = "reliable",
				}),
				URMessage = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = IdType,
						[2] = BytenetMax.unknown
					},
					reliabilityType = "unreliable",
				}),
			},
		}
	end)
else
	Namespace = {
		packets = {
			ObjectCreated = RemoteWrapper.RegisterEvent("ObjectCreated"),
			ObjectDestroyed = RemoteWrapper.RegisterEvent("ObjectDestroyed"),

			Set = RemoteWrapper.RegisterEvent("Set"),
			RequestData = RemoteWrapper.RegisterEvent("RequestData"),

			Insert = RemoteWrapper.RegisterEvent("Insert"),
			Remove = RemoteWrapper.RegisterEvent("Remove"),

			Message = RemoteWrapper.RegisterEvent("Message"),
			URMessage = RemoteWrapper.RegisterEvent("URMessage", true),
		}
	}
end

Shared.Packets = Namespace.packets

Shared.NumberIdentifier = "◘"
Shared.TypeToString = function(Number: number|string) : string
	if typeof(Number) == "string" then
		return Number
	end
	return Shared.NumberIdentifier..Number
end
Shared.StringToType = function(String: string) : number|string
	if String:sub(0,3) == Shared.NumberIdentifier then
		return tonumber(String:sub(4,#String)) :: number
	end
	return String
end
Shared.PathToString = function(Path: PathType) : {string}
	for i,v in Path do
		local Type = type(v)
		if Type == "number" then
			Path[i] = Shared.NumberIdentifier..v
		elseif Type ~= "string" then
			error(`Path key {v} is not a valid path key.`)
		end
	end
	return Path :: any
end
Shared.PathToNormal = function(Path: {string}) : PathType
	for i,v in Path do
		if v:sub(0,3) == Shared.NumberIdentifier then
			Path[i] = tonumber(v:sub(4,#v)) :: any
		end
	end
	return Path :: any
end

export type PathType = {string}|{number}|{string|number}

export type Action = "Set"|"Insert"|"Remove"

type Disconnect = (Disconnect: nil) -> ()

export type Call<Data> = (
	(self: any) -> Data
) & (
	<A>(self: any, Set: Data&A) -> A
)
type Mt<T, Data> = {
	__index: T,
	__call: Call<Data>
}

type DictMethodsClient<Data = any, Key = any, Value = any> = {
	OnKeySet: (self: any, Callback: (Key: Key, Value: Value) -> ()) -> Disconnect,
	OnChange: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Disconnect,
}
type ArrayMethodsClient<Data = any, Value = any> = {
	OnKeySet: (self: any, Callback: (Key: number, Value: Value) -> ()) -> Disconnect,
	OnChange: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Disconnect,

	OnInsert: (self: any, Callback: (Value: Value, Index: number) -> ()) -> Disconnect,
	OnRemove: (self: any, Callback: (RemovedValue: Value, Index: number) -> ()) -> Disconnect
}
type ValueMethodsClient<Data> = {
	OnChange: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Disconnect,
}

export type function ComputeTypeClient(Type: type)
	local OrigType = types.copy(Type)
	local IsTable = Type:is("table")
	local Indexer = IsTable and Type:readindexer()
	local New = types.newtable()

	local MetatableType = nil

	if Indexer then
		New:setindexer(Indexer.index, ComputeTypeClient(Indexer.result))
		if Indexer.index:is("number") then
			MetatableType = ArrayMethodsClient(OrigType, Indexer.result)
		else
			MetatableType = DictMethodsClient(OrigType, Indexer.index, Indexer.result)
		end
	elseif not IsTable then
		MetatableType = ValueMethodsClient(OrigType)
	else
		MetatableType = DictMethodsClient(OrigType, types.any, types.any)
	end
	
	New:setmetatable(Mt(MetatableType, OrigType))

	if IsTable then
		for i,v in Type:properties() do
			if v.read then
				New:setreadproperty(i, ComputeTypeClient(v.read))
			end
			if v.write then
				New:setwriteproperty(i, v.read)
			end
		end
	end

	return New
end

export type ClientClass<T = any> = {
	Id: number,
	Data: ComputeTypeClient<T>,
	Tags: {string},
	Identifier: string?,

	--[[
		Whether the Object is being replicated.
	]]
	Active: boolean?,

	Set: (self: ClientClass<T>, Path: PathType, Value: any) -> (),
	Get: (self: ClientClass<T>, Path: PathType, IgnoreLast: number?) -> any,

	SignalDestroyed: Signal.Signal<ClientClass<T>>,

	--[[
		Send messages to server, as long as Object is active.
	]]
	Message: (self: ClientClass<T>, Message: any, Unreliable: boolean?) -> (),
	--[[
		Listen messages from server, as long as Object is active.
	]]
	OnMessage: (self: ClientClass<T>, Callback: (Message: any) -> (), Unreliable: boolean?) -> Signal.Connection,
}

type ArrayMethodsServer<T = any, Data = any> = {
	Insert: (self: any, Value: T, Index: number?) -> (),
	Remove: (self: any, Index: number?) -> (),
}

export type function ComputeTypeServer(Type: type)
	local OrigType = types.copy(Type)
	local IsTable = Type:is("table")
	local Indexer = IsTable and Type:readindexer()
	local New = types.newtable()

	local MetatableType = nil

	if Indexer then
		New:setindexer(Indexer.index, ComputeTypeServer(Indexer.result))
		if Indexer.index:is("number") then
			MetatableType = ArrayMethodsServer(OrigType, Indexer.result)
		else
			-- MetatableType = DictMethodsServer(OrigType, Indexer.index, Indexer.result)
		end
	elseif not IsTable then
		-- MetatableType = ValueMethodsServer(OrigType)
	else
		-- MetatableType = DictMethodsServer(OrigType, types.any, types.any)
	end
	
	New:setmetatable(Mt(MetatableType or types.newtable(), OrigType))

	if IsTable then
		for i,v in Type:properties() do
			if v.read then
				New:setreadproperty(i, ComputeTypeServer(v.read))
			end
			if v.write then
				New:setwriteproperty(i, v.read)
			end
		end
	end

	return New
end

export type ServerClass<T = any> = {
	Id: number,
	Data: ComputeTypeServer<T>,
	Tags: {string},
	Identifier: string?,

	--[[
		Whether the object is not destroyed.
	]]
	Active: boolean?,

	Set: (self: ServerClass<T>, Path: PathType, Value: any) -> (),
	Get: (self: ServerClass<T>, Path: PathType, IgnoreLast: number?) -> (),

	--[[
		If object is replicated to the player.
	]]
	IsTarget: (self: ServerClass<T>, Player: Player) -> boolean?,

	--[[
		Assigns a parent object, the child will copy parent's replication parameters.
	]]
	SetParent: (
		(self: ServerClass<T>, Parent: any, ChildIndex: any) -> ServerClass<T>
	) & (
		(self: ServerClass<T>) -> () -- Removes the parent.
	),

	--[[
		Replicates the Object to all Ready Players.
		Clears the Include/Exclude lists.
	]]
	Replicate: (self: ServerClass<T>) -> ServerClass<T>,
	--[[
		Adds the specified player to the replication.
	]]
	Subscribe: (self: ServerClass<T>, Player: Player) -> ServerClass<T>,

	--[[
		Removes replication from all players.
		Clears Include/Exclude lists.
	]]
	Unreplicate: (self: ServerClass<T>) -> (),
	--[[
		Removes the specified player from the replication.
	]]
	Unsubscribe: (self: ServerClass<T>, Player: Player) -> (),

	--[[
		Send a message to all replicated clients.
	]]
	Message: (self: ServerClass<T>, Message: any, Player: Player?, Unreliable: boolean?) -> (),
	--[[
		Listen to the messages of any of the replicated clients.
	]]
	OnMessage: (self: ServerClass<T>, Callback: (Player: Player, Message: any) -> (), Player: Player?, Unreliable: boolean?) -> Signal.Connection,

	--[[
		Iterates through all replicated players.
	]]
	IterateTargets: (self: ServerClass<T>, Callback: (Player: Player) -> ()) -> (),
	--[[
		Clears the replica and removes replication.
	]]
	Destroy: (self: ServerClass<T>) -> (),
}

return Shared
