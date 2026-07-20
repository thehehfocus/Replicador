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

type ProxyMethodsClient<Data = any> = {
	__index: {
		OnSet: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Signal.Connection,
		OnChange: (self: any, Callback: (Value: any, Action: Action, Path: PathType) -> ()) -> Signal.Connection,
	},
	__call: (
		(any) -> Data
	)
}
type ArrayProxyMethodsClient<T = any, Data = any> = {
	__index: {
		OnSet: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Signal.Connection,
		OnChange: (self: any, Callback: (Value: any, Action: Action, Path: PathType) -> ()) -> Signal.Connection,
		OnInsert: (self: any, Callback: (Value: T, Index: number) -> ()) -> Signal.Connection,
		OnRemove: (self: any, Callback: (Index: number) -> ()) -> Signal.Connection,
	},
	__call: (
		(any) -> Data
	)
}
type ProxyValueMethodsClient<Data> = {
	__index: {
		OnSet: (self: any, Callback: (Value: Data, OldValue: Data) -> ()) -> Signal.Connection,
	},
	__call: (
		(any) -> Data
	),
}
type ValueBaseClient<Data> = (any) -> Data
type function ComputeTypeClient(Origin: type)
	local function Do(Type: type)
		local Indexer = Type:is("table") and Type:readindexer()
		local New = types.newtable()

		if Indexer then
			New:setindexer(Indexer.index, Do(Indexer.result))
			New:setmetatable(ArrayProxyMethodsClient(Indexer.result, Type))
		elseif not Type:is("table") then
			New:setmetatable(ProxyValueMethodsClient(Type))
		else
			New:setmetatable(ProxyMethodsClient(Type))
		end

		if not Type:is("table") then
			return New
		end

		for i,v in Type:properties() do
			if v.read then
				New:setreadproperty(i, Do(v.read))
			end
			--if v.write then
			--	New:setwriteproperty(i, v.write)
			--end
		end

		return New
	end

	return Do(Origin)
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

	Get: (self: ClientClass<T>, Path: PathType, IgnoreLast: number?) -> any,

	SignalChanged: Signal.Signal<PathType, any, Action>,
	SignalDestroyed: Signal.Signal<ClientClass<T>>,
	SignalMessage: Signal.Signal<any, boolean>,

	--[[
		Send messages to server, as long as Object is active.
	]]
	Message: (self: ClientClass<T>, Message: any, Unreliable: boolean?) -> (),
	--[[
		Listen messages from server, as long as Object is active.
	]]
	OnMessage: (self: ClientClass<T>, Callback: (Message: any) -> (), Unreliable: boolean?) -> Signal.Connection,

	_raw: {},
}

type ProxyMethodsServer<Data = any> = {
	__call: (
		(any) -> Data
	),
}
type ArrayProxyMethodsServer<T = any, Data = any> = {
	__index: {
		Insert: (self: any, Value: T, Index: number?) -> (),
		Remove: (self: any, Index: number?) -> (),
	},
	__call: (
		(any) -> Data
	),
}

type function ComputeTypeServer(Origin: type)
	local function Do(Type: type)
		local Indexer = Type:is("table") and Type:readindexer()
		local New = types.newtable()

		if Indexer then
			New:setindexer(Indexer.index, Do(Indexer.result))
			New:setmetatable(ArrayProxyMethodsServer(Indexer.result, Type))
		else
			New:setmetatable(ProxyMethodsServer(Type))
		end

		if not Type:is("table") then
			return Type
		end

		for i,v in Type:properties() do
			if v.read then
				New:setreadproperty(i, Do(v.read))
			end
			if v.write then
				New:setwriteproperty(i, v.write)
			end
		end

		return New
	end

	return Do(Origin)
end

export type ServerClass<T = any, Children = {}> = {
	Id: number,
	Data: ComputeTypeServer<T>,
	Tags: {string},
	Identifier: string?,

	--[[
		Whether the object is not destroyed.
	]]
	Active: boolean?,

	IncludeList: {[Player]: boolean},
	ExcludeList: {[Player]: boolean},

	Parent: any?,
	Children: Children,

	ReplicateMode: "All"|"None",

	SignalMessage: Signal.Signal<any, boolean, Player>,
	IsTarget: (self: ServerClass<T, Children>, Player: Player) -> boolean?,

	--[[
		Assigns a parent object, the child will copy parent's replication parameters.
	]]
	SetParent: (
		(self: ServerClass<T, Children>, Parent: any, ChildIndex: any) -> ServerClass<T, Children>
	) & (
		(self: ServerClass<T, Children>) -> () -- Removes the parent.
	),

	--[[
		Replicates the Object to all Ready Players.
		Clears the Include/Exclude lists.
	]]
	Replicate: (self: ServerClass<T, Children>) -> ServerClass<T, Children>,
	--[[
		Adds the specified player to the replication.
	]]
	Subscribe: (self: ServerClass<T, Children>, Player: Player) -> ServerClass<T, Children>,

	--[[
		Removes replication from all players.
		Clears Include/Exclude lists.
	]]
	Unreplicate: (self: ServerClass<T, Children>) -> (),
	--[[
		Removes the specified player from the replication.
	]]
	Unsubscribe: (self: ServerClass<T, Children>, Player: Player) -> (),

	--[[
		Send a message to all replicated clients.
	]]
	Message: (self: ServerClass<T, Children>, Message: any, Player: Player?, Unreliable: boolean?) -> (),
	--[[
		Listen to the messages of any of the replicated clients.
	]]
	OnMessage: (self: ServerClass<T, Children>, Callback: (Player: Player, Message: any) -> (), Player: Player?, Unreliable: boolean?) -> Signal.Connection,

	--[[
		Iterates through all replicated players.
	]]
	IterateTargets: (self: ServerClass<T, Children>, Callback: (Player: Player) -> ()) -> (),
	--[[
		Clears the replica and removes replication.
	]]
	Destroy: (self: ServerClass<T, Children>) -> (),

	_creation: {},
	_raw: {},
}

return Shared
