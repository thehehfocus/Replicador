--!strict
local Shared = {}

-- Config
type _ntvst = false -- non table proxy server toggle
local __ntvst = false

-- Change these if you have ByteNetMax.
--local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local BytenetMax = nil::any --require(Packages.ByteNetMax)
local IdType = BytenetMax and BytenetMax.uint16

local MakeProxy = require("./MakeProxy")
MakeProxy._ntvst = __ntvst

-- Wrapper for remotes.
local RemoteWrapper = require("./RemoteWrapper")
local Signal = require("./Signal")

local Namespace

if BytenetMax then
	Namespace = BytenetMax.defineNamespace("__replicador__", function()
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
		}
	}
end

Shared.Packets = Namespace.packets

local NumberIdentifier = "◘"
local NumberSize = 3 :: number

Shared.PathToString = function(Path: PathType) : {string}
	for i,v in Path do
		local Type = type(v)

		if Type == "number" then
			Path[i] = NumberIdentifier..v
		elseif Type ~= "string" then
			error(`Path key {v} is not a valid path key.`)
		end
	end
	return Path :: any
end
Shared.PathToNormal = function(Path: {string}) : PathType
	for i,v in Path do
		if v:sub(0, NumberSize) == NumberIdentifier then
			Path[i] = tonumber(v:sub(NumberSize+1,#v)) :: any
		end
	end
	return Path :: any
end

export type PathType = {string}|{number}|{string|number}
export type Action = "Set"|"Insert"|"Remove"

type Disconnect = (Disconnect: nil) -> ()

export type Call<Data> = (
	() -> Data
) & (
	(Set: Data) -> ()
) & (
	(Set: (Data) -> Data) -> ()
)
type Mt<T> = {
	__index: T,
}

type DictMethodsClient<Data = any, Key = any, Value = any> = {
	OnKeySet: (self: any, Callback: (Key: Key, Value: Value) -> ()) -> Disconnect,
	OnChange: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Disconnect,
}

type ArrayMethodsServer<T = any, Data = any> = {
	Insert: (self: any, Value: Data, Index: number?) -> (),
	Remove: (self: any, Index: number?) -> (),
}
type ArrayMethodsClient<Data = any, Value = any> = {
	OnKeySet: (self: any, Callback: (Key: number, Value: Value) -> ()) -> Disconnect,
	OnChange: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Disconnect,

	OnInsert: (self: any, Callback: (Value: Value, Index: number) -> ()) -> Disconnect,
	OnRemove: (self: any, Callback: (RemovedValue: Value, Index: number) -> ()) -> Disconnect,
}

type ValueMethodsClient<Data> = {
	OnChange: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Disconnect,
}

export type function ComputeType(Type: type, IsServer: type)
	local IsTable = Type:is("table") 
	local IsServerValue = IsServer:value()
	
	if IsServerValue and not IsTable and not _ntvst:value() then
		return Type
	end

	local Indexer = IsTable and Type:readindexer()
	local New = types.newtable()
	if IsTable then
		for i,v in Type:properties() do
			if v.read then
				New:setreadproperty(i, ComputeType(v.read, IsServer))
			end
			if v.write then
				New:setwriteproperty(i, v.read)
			end
		end
	end

	local MetatableType = nil

	local DictMethods = if IsServerValue then nil else DictMethodsClient
	local ArrayMethods = if IsServerValue then ArrayMethodsServer else ArrayMethodsClient
	local ValueMethods = if IsServerValue then nil else ValueMethodsClient

	if Indexer then
		New:setindexer(Indexer.index, ComputeType(Indexer.result, IsServer))
		
		if Indexer.index:is("number") then
			MetatableType = ArrayMethods and ArrayMethods(Type, Indexer.result)
		else
			MetatableType = DictMethods and DictMethods(Type, Indexer.index, Indexer.result)
		end
	elseif IsTable then
		MetatableType = DictMethods and DictMethods(Type, types.any, types.any)
	else
		MetatableType = ValueMethods and ValueMethods(Type)
	end
	
	if MetatableType then
		New:setmetatable(Mt(MetatableType))
	end
	New = types.intersectionof(New, Call(Type))

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

	Set: (self: ClientClass<T>, Path: PathType, Value: any) -> (),
	Get: (self: ClientClass<T>, Path: PathType, IgnoreLast: number?) -> any,
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

	Set: (self: ServerClass<T>, Path: PathType, Value: any) -> (),
	Get: (self: ServerClass<T>, Path: PathType, IgnoreLast: number?) -> (),

	--[[
		If object is replicated to the player.
	]]
	IsTarget: (self: ServerClass<T>, Player: Player) -> boolean?,
	--[[
		Iterates through all replicated players.
	]]
	IterateTargets: (self: ServerClass<T>, Callback: (Player: Player) -> ()) -> (),

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
		Removes replication from all players.
		Clears Include/Exclude lists.
	]]
	Unreplicate: (self: ServerClass<T>) -> (),
	
	--[[
		Adds the specified player to the replication.
	]]
	Subscribe: (self: ServerClass<T>, Player: Player) -> ServerClass<T>,
	--[[
		Removes the specified player from the replication.
	]]
	Unsubscribe: (self: ServerClass<T>, Player: Player) -> (),
	
	--[[
		Clears the replica and removes replication.
	]]
	Destroy: (self: ServerClass<T>) -> (),
}
	
return Shared
