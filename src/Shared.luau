--!strict
const Shared = {}

-- CONFIG
--const Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
const BytenetMax = nil::any --require(Packages.ByteNetMax)
const IdType = BytenetMax.uint16

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
						[3] = BytenetMax.array(BytenetMax.string)
					}
				}),
				ObjectDestroyed = BytenetMax.definePacket({
					value = BytenetMax.struct{
						[1] = IdType
					}
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
			URMessage = RemoteWrapper.RegisterEvent("URMessage"),
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
export type ClientClass<T> = {
	Id: number,
	Data: T,
	Tags: {string},
	
	Active: boolean?,
	
	Get: (self: ClientClass<T>, Path: PathType, IgnoreLast: number?) -> any,
	
	SignalChanged: Signal.Signal<PathType, any, Action>,
	SignalDestroyed: Signal.Signal<ClientClass<T>>,
	SignalMessage: Signal.Signal<any, boolean>,
	
	Message: (self: ClientClass<T>, Message: any, Unreliable: boolean?) -> (),
	OnMessage: (self: ClientClass<T>, Callback: (Message: any) -> (), Unreliable: boolean?) -> Signal.Connection,
	
	OnChange: (self: ClientClass<T>, Path: PathType, Callback: (Value: any, Action: Action, Path: PathType) -> ()) -> Signal.Connection,
	OnSet: (self: ClientClass<T>, Path: PathType, Callback: (Value: any) -> ()) -> Signal.Connection,
}

type ProxyType = {
	Insert: (self: ProxyType, Value: any, Index: number?) -> (),
	Remove: (self: ProxyType, Index: number?) -> (),
}
type ProxyTypeAny = {
	Insert: (self: ProxyTypeAny, Value: any, Index: number?) -> (),
	Remove: (self: ProxyTypeAny, Index: number?) -> (),
	[any]: any,
}

export type ServerClass<T, Children = {}> = {
	Id: number,
	Data: T,
	Tags: {string},
	
	Active: boolean?,
	
	IncludeList: {[Player]: boolean},
	ExcludeList: {[Player]: boolean},
	
	Parent: any?,
	Children: Children,
	
	ReplicateMode: "All"|"None",
	
	SignalMessage: Signal.Signal<any, boolean, Player>,
	
	Set: (self: ServerClass<T, Children>, Path: PathType, Value: any) -> (),
	SetValues: (self: ServerClass<T, Children>, Path: PathType, Values: {[PathType]: any}) -> (),
	Get: (self: ServerClass<T, Children>, Path: PathType, IgnoreLast: number?) -> any,
	
	GetShallowProxy: (
		<A>(self: ServerClass<T, Children>, Path: PathType?, TypeofValue: A) -> ProxyType & A
	) & (
		<A>(self: ServerClass<T, Children>, Path: PathType) -> ProxyTypeAny
	) & (
		(self: ServerClass<T, Children>) -> ProxyType & T
	),
	
	AssignChildren: (self: ServerClass<T, Children>, ChildMap: {[string]: any}) -> (),
	
	Insert: (self: ServerClass<T, Children>, Path: PathType, Value: any, Index: number?) -> (),
	Remove: (self: ServerClass<T, Children>, Path: PathType, Index: number?) -> (),
	
	Replicate: (self: ServerClass<T, Children>) -> ServerClass<T, Children>,
	Subscribe: (self: ServerClass<T, Children>, Player: Player) -> ServerClass<T, Children>,
	Unreplicate: (self: ServerClass<T, Children>) -> (),
	Unsubscribe: (self: ServerClass<T, Children>, Player: Player) -> (),
	
	Message: (self: ServerClass<T, Children>, Message: any, Player: Player?, Unreliable: boolean?) -> (),
	OnMessage: (self: ServerClass<T, Children>, Callback: (Player: Player, Message: any) -> (), Player: Player?, Unreliable: boolean?) -> Signal.Connection,
	
	IterateTargets: (self: ServerClass<T, Children>, Callback: (Player: Player) -> ()) -> (),
	Destroy: (self: ServerClass<T, Children>) -> (),
}

return Shared
