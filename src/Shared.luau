--!strict
const Shared = {}

-- Config

-- Change these if you have ByteNetMax.
--const Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
const BytenetMax = nil::any --require(Packages.ByteNetMax)
const IdType = BytenetMax and BytenetMax.uint16

-- Wrapper for remotes.
const RemoteWrapper = require("./RemoteWrapper")
const Signal = require("./Signal")

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
				SetValues = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = IdType,
						[2] = BytenetMax.array(BytenetMax.string),
						[3] = BytenetMax.map(BytenetMax.string, BytenetMax.unknown)
					},
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
			SetValues = RemoteWrapper.RegisterEvent("SetValues"),
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

export type Action = "Set"|"Insert"|"Remove"|"SetValues"

type ClientProxyType = {
	OnChange: (self: ClientProxyType, Callback: (Value: any, Action: Action, Path: PathType) -> ()) -> Signal.Connection,
	OnSet: (self: ClientProxyType, Callback: (Value: any) -> ()) -> Signal.Connection,
}

export type ClientClass<T = any> = {
	Id: number,
	Data: T,
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
	
	--[[
		Listen to any changes related to the path.
	]]
	OnChange: (self: ClientClass<T>, Path: PathType, Callback: (Value: any, Action: Action, Path: PathType) -> ()) -> Signal.Connection,
	
	--[[
		Listen to only changes on this path.	
	]]
	OnSet: (self: ClientClass<T>, Path: PathType, Callback: (Value: any) -> ()) -> Signal.Connection,

	GetPathProxy: (self: ClientClass<T>, Path: PathType?) -> ClientProxyType,
}

type ProxyType = {
	Insert: (self: ProxyType, Value: any, Index: number?) -> (),
	Remove: (self: ProxyType, Index: number?) -> (),
	SetValues: (self: ProxyType, Values: {[PathType]: any}) -> ()
}
type ProxyTypeAny = {
	Insert: (self: ProxyTypeAny, Value: any, Index: number?) -> (),
	Remove: (self: ProxyTypeAny, Index: number?) -> (),
	SetValues: (self: ProxyTypeAny, Values: {[PathType]: any}) -> (),
	[any]: any,
}

export type ServerClass<T = any, Children = {}> = {
	Id: number,
	Data: T,
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
	
	Set: (self: ServerClass<T, Children>, Path: PathType, Value: any) -> (),
	--[[
		Sets the key-value 'Values' pairs at the provided path.
	]]
	SetValues: (self: ServerClass<T, Children>, Path: PathType, Values: {[PathType]: any}) -> (),
	Get: (self: ServerClass<T, Children>, Path: PathType, IgnoreLast: number?) -> any,
	
	--[[
		Returns a shallow table proxy which intercepts reads/writes, applying changes at the given path.
	]]
	GetShallowProxy: (
		<A>(self: ServerClass<T, Children>, Path: PathType?, TypeofValue: A) -> ProxyType & A
	) & (
		<A>(self: ServerClass<T, Children>, Path: PathType) -> ProxyTypeAny
	) & (
		(self: ServerClass<T, Children>) -> ProxyType & T
	),

	IsTarget: (self: ServerClass<T, Children>, Player: Player) -> boolean?,
	
	--[[
		Assigns a parent object, the child will copy parent's replication parameters.
	]]
	SetParent: (
		(self: ServerClass<T, Children>, Parent: any, ChildIndex: any) -> ServerClass<T, Children>
	) & (
		(self: ServerClass<T, Children>) -> () -- Removes the parent.
	),
	
	Insert: (self: ServerClass<T, Children>, Path: PathType, Value: any, Index: number?) -> (),
	Remove: (self: ServerClass<T, Children>, Path: PathType, Index: number?) -> (),
	
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
}

return Shared
