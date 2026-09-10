--!optimize 2
local Client = {}

--== Dependencies ==--
local Shared = require("./Shared")
local Signal = require("./Signal")
local MakeProxy = require("./MakeProxy")

--== Variables ==--
local SignalKeys = {
	"SignalChanged",
	"SignalDestroyed",
}

local Objects = {} :: { [number]: InternalClass }
local Tagged = {} :: { [string]: { InternalClass } }
local Identifiers = {} :: { [string]: Object }

local ObjectAdded = Signal.new() :: Signal.Signal<InternalClass>
local ObjectRemoved = Signal.new() :: Signal.Signal<InternalClass>

local Class = {}
function Class.__index(self: InternalClass, Key)
	local Existing = Class[Key]
	if Existing then
		return Existing
	elseif table.find(SignalKeys, Key) then
		local newSignal = Signal.new()
		self[Key] = newSignal

		if Key == "SignalChanged" then
			self._changetrack = true
		end

		return newSignal
	end

	return nil
end

type PathType = Shared.PathType
export type InternalClass<T = {}> = Shared.ClientClass<T> & {
	_raw: {},
	_changetrack: boolean?,
}

type Disconnect = (Disconnect: nil) -> ()
local ProxyMethods = {
	OnChange = function(Proxy, Callback: (Value: any, OldValue: any) -> ()): Disconnect
		local OldValue = MakeProxy.GetValue(Proxy)
		return MakeProxy.Connect(Proxy, function(Action)
			if Action ~= "Set" then
				return
			end

			local NewValue = MakeProxy.GetValue(Proxy)
			if NewValue ~= OldValue then
				Callback(NewValue, OldValue)
				OldValue = NewValue
			end
		end)
	end,
	OnInsert = function(Proxy, Callback: (Value: any, Index: any) -> ()): Disconnect
		return MakeProxy.Connect(Proxy, function(Action, NewValue, Index)
			if Action ~= "Insert" then
				return
			end

			Callback(NewValue, Index)
		end)
	end,
	OnRemove = function(Proxy, Callback: (RemovedValue: any, Index: any) -> ()): Disconnect
		return MakeProxy.Connect(Proxy, function(Action, RemovedValue, Index)
			if Action ~= "Remove" then
				return
			end

			Callback(RemovedValue, Index)
		end)
	end,
	OnKeyChange = function(Proxy, Callback: (Key: any, Value: any) -> ()): Disconnect
		return MakeProxy.Connect(Proxy, function(Action, Key, Value, OldValue)
			if Action ~= "DescendantChange" then
				return
			end
			
			if Value == OldValue then
				return
			end

			Callback(Key, Value, OldValue)
		end)
	end,

	Get = MakeProxy.GetValue,
	Set = function(Proxy, Value)
		if type(Value) == "function" then
			Value = Value(MakeProxy.GetValue(Proxy))
		end

		local Parent = MakeProxy.GetParent(Proxy)
		local Key = MakeProxy.GetKey(Proxy)

		Parent[Key] = Value

		return nil
	end,
}

--== Script ==--
local function Register(Id: number, Data: any, Tags: { string }, Identifier: string?)
	local Object = setmetatable({}, Class) :: InternalClass
	Object.Id = Id
	Object.Data = MakeProxy.new(Data, {
		CallFunction = function(Proxy, ...)
			if select("#", ...) > 0 then
				local Value = ...
				if type(Value) == "function" then
					Value = Value(MakeProxy.GetValue(Proxy))
				end

				local Parent = MakeProxy.GetParent(Proxy)
				local Key = MakeProxy.GetKey(Proxy)

				Parent[Key] = Value

				return nil
			else
				return MakeProxy.GetValue(Proxy)
			end
		end,
		IndexMethods = ProxyMethods,
		Identifier = Id,
	})
	Object.Tags = Tags
	Object.Identifier = Identifier

	Object.Active = true
	Object._raw = Data

	Objects[Id] = Object
	if Identifier then
		Identifiers[Identifier] = Object
	end

	for i, Tag in Tags do
		if not Tagged[Tag] then
			Tagged[Tag] = {}
		end
		Tagged[Tag][Id] = Object
	end

	ObjectAdded:Fire(Object)

	return Object
end
local function Destroy(Object: InternalClass)
	Object.Active = false

	local SignalDestroyed = rawget(Object, "SignalDestroyed")
	if SignalDestroyed then
		SignalDestroyed:Fire(Object)
	end
	ObjectRemoved:Fire(Object)

	Objects[Object.Id] = nil
	if Object.Identifier then
		Identifiers[Object.Identifier] = nil
	end

	for i, Tag in Object.Tags do
		local TagMap = Tagged[Tag]
		if TagMap then
			TagMap[Object.Id] = nil
			if not next(TagMap) then
				Tagged[Tag] = nil
			end
		end
	end

	for i, v in SignalKeys do
		local destroySignal = rawget(Object, v)
		if destroySignal then
			destroySignal:Destroy()
		end
	end
end

local IsInit = false
function Client.Init()
	if IsInit then
		return
	end
	IsInit = true

	Shared.Packets.ObjectCreated.listen(function(Info)
		local Id = Info[1]
		local Data = Info[2]
		local Tags = Info[3]
		local Identifier = Info[4]

		if Objects[Id] then
			return
		end

		Register(Id, Data, Tags, Identifier)
	end)
	Shared.Packets.ObjectDestroyed.listen(function(Info)
		local Id = Info

		local Object = Objects[Id]
		if Object == nil then
			return
		end

		Destroy(Object)
	end)

	Shared.Packets.Set.listen(function(Info)
		local Id = Info[1]
		local Path = Info[2]
		local Value = Info[3]

		local Object = Objects[Id]
		if Object == nil then
			return
		end

		local Pointer = Object:PathGet(Path, 1, true)
		Pointer[Path[#Path]] = Value

		if Object._changetrack then
			Object.SignalChanged:Fire(Path, Value, "Set")
		end
	end)

	Shared.Packets.Insert.listen(function(Info)
		local Id = Info[1]
		local Path = Info[2]
		local Value = Info[3]

		local Object = Objects[Id]
		if Object == nil then
			return
		end

		local Index = Path[#Path]
		local Pointer = Object:PathGet(Path, 1, true)

		MakeProxy.Insert(Pointer, Value, Index)

		if Object._changetrack then
			Object.SignalChanged:Fire(Path, Value, "Insert")
		end
	end)
	Shared.Packets.Remove.listen(function(Info)
		local Id = Info[1]
		local Path = Info[2]

		local Object = Objects[Id]
		if not Object then
			return
		end

		local Index = Path[#Path]
		local Pointer = Object:PathGet(Path, 1, true)
		MakeProxy.Remove(Pointer, Index)

		if Object._changetrack then
			Object.SignalChanged:Fire(Path, nil, "Remove")
		end
	end)

	task.wait()
	Shared.Packets.RequestData.send()
end

function Client.Get<T>(Identifier: string, DataTemplate: T?): Shared.ClientClass<T>?
	return Identifiers[Identifier]
end
Client.GetTagged = function(Tag: string | { string }, Id: number?): Shared.ClientClass | { Shared.ClientClass }?
	if type(Tag) == "string" then
		return if type(Id) == "number" then Tagged[Tag] and Tagged[Tag][Id] else Tagged[Tag] or {}
	else
		local Result = {}
		for i, v in Tag do
			local Objects = Client.GetTagged(v, Id)
			if not Objects then
				continue
			end

			for i, v in Objects do
				if table.find(Result, v) then
					continue
				end

				table.insert(Result, v)
			end
		end
		return Result
	end
end :: ((Tag: string) -> { Shared.ClientClass }) & ((Tags: { string }) -> { Shared.ClientClass }) & ((Tag: string, Id: number) -> Shared.ClientClass?)

local function IdentifierImpl(Identifier: string, Callback)
	return function(Class: InternalClass)
		if Class.Identifier == Identifier then
			if Callback then
				Callback(Class)
			end
			return true
		end
		return false
	end
end
function Client.OnNew(
	Identifier: string,
	Callback: (New: Shared.ClientClass) -> (),
	CallOnExisting: boolean?
): Signal.Connection
	local Existing = Client.Get(Identifier)
	if CallOnExisting and Existing then
		Callback(Existing)
	end

	return ObjectAdded:Connect(IdentifierImpl(Identifier, Callback))
end
function Client.OnRemoved(Identifier: string, Callback: (Removed: Shared.ClientClass) -> ()): Signal.Connection
	return ObjectRemoved:Connect(IdentifierImpl(Identifier, Callback))
end

local function TaggedImpl(Tags: string | { string }, Callback)
	if type(Tags) == "string" then
		return function(Class)
			if not Client.GetTagged(Tags, Class.Id) then
				return false
			end

			if Callback then
				Callback(Class)
			end
			return true
		end
	else
		return function(Class)
			local Has = true
			for i, v in Tags do
				Has = Client.GetTagged(v, Class.Id)
				if not Has then
					return false
				end
			end

			if Callback then
				Callback(Class)
			end
			return true
		end
	end
end
function Client.OnNewTagged(
	Tags: string | { string },
	Callback: (New: InternalClass) -> (),
	CallOnExisting: boolean?
): Signal.Connection
	local Handler = TaggedImpl(Tags, Callback)

	if CallOnExisting then
		for i, v in Client.GetTagged(Tags) do
			Handler(v)
		end
	end

	return ObjectAdded:Connect(Handler)
end
function Client.OnRemovedTagged(
	Tags: string | { string },
	Callback: (Removed: Shared.ClientClass) -> ()
): Signal.Connection
	local Handler = TaggedImpl(Tags, Callback)

	return ObjectRemoved:Connect(Handler)
end

function Client.AwaitFor<T>(Identifier: string, DataTemplate: T?): Shared.ClientClass<T>
	local Already = Client.Get(Identifier)
	if Already then
		return Already
	end

	return ObjectAdded:Wait(IdentifierImpl(Identifier))
end
function Client.AwaitForTagged<T>(Tags: string | { string }, DataTemplate: T?): Shared.ClientClass<T>
	local Already = Client.GetTagged(Tags)

	local _, _nextAlready = next(Already)
	if _nextAlready then
		return _nextAlready
	end

	return ObjectAdded:Wait(Tags, TaggedImpl(Tags))
end

function Class.PathSet(self: InternalClass, Path: { PathType }, Value: any)
	local Data = self:PathGet(Path, nil, true)
	Data[Path[#Path]] = Value
end
function Class.PathGet(self: InternalClass, Path: PathType, IgnoreLast: number?, notraw: boolean?): any
	local Data = if notraw then self.Data else self._raw
	for i = 1, #Path - (IgnoreLast or 0) do
		Data = Data[Path[i]]
	end
	return Data
end

return Client
