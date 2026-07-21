--!optimize 2
local RunService = game:GetService("RunService")

local Module = {}

--== Dependencies ==--
local Shared = require("./Shared")
local Signal = require("./Signal")
local MakeProxy = require("./MakeProxy")

--== Variables ==--
local IsInit = false
local SignalKeys = {
	"SignalChanged",
	"SignalDestroyed",
	"SignalMessage",
}

local Class = {}
Class.__index = function(self, Key)
	local Existing = Class[Key]
	if Existing then
		return Existing
	elseif table.find(SignalKeys, Key) then
		local newSignal = Signal.new()
		self[Key] = newSignal
		return newSignal
	end
	return nil
end

local Objects = {} :: { [number]: Class }
local Tagged = {} :: { [string]: { Class } }
local Identifiers = {} :: { [string]: Object }

local ObjectAdded = Signal.new() :: Signal.Signal<Class>
local ObjectRemoved = Signal.new() :: Signal.Signal<Class>

type PathType = Shared.PathType
export type Class<T = {}> = Shared.ClientClass<T>

local function OnChange(
	self: Class,
	Path: PathType,
	Callback: (Value: any, Action: Shared.Action, Path: PathType) -> ()
): Signal.Connection
	return self.SignalChanged:Connect(function(SetPath, Value, Action)
		for i, v in Path do
			if v ~= SetPath[i] then
				return
			end
		end

		Callback(Value, Action, SetPath)
	end)
end

local function CheckImpl(SetPath, Action, TargetPath, TargetAction)
	if Action ~= TargetAction then
		return
	end

	local Len = #SetPath
	if Action == "Insert" or Action == "Remove" then
		Len -= 1 -- removing one, since its the index.
	end
	if Len ~= #TargetPath then
		return
	end
	for i, v in TargetPath do
		if v ~= SetPath[i] then
			return
		end
	end

	return true
end
local function OnSet(self: Class, Path: PathType, Callback: (Value: any) -> ()): Signal.Connection
	local Success, OldValue = pcall(self.Get, self, Path)
	OldValue = if Success then OldValue else nil
	return self.SignalChanged:Connect(function(SetPath, Value, Action)
		if not CheckImpl(SetPath, Action, Path, "Set") then
			return
		end
		Callback(Value, OldValue)
		OldValue = Value
	end)
end
local function OnInsert(self: Class, Path: PathType, Callback: (Value: any, Index: any) -> ()): Signal.Connection
	return self.SignalChanged:Connect(function(SetPath, Value, Action)
		if not CheckImpl(SetPath, Action, Path, "Insert") then
			return
		end
		Callback(Value, SetPath[#SetPath])
	end)
end
local function OnRemove(self: Class, Path: PathType, Callback: (Index: any) -> ()): Signal.Connection
	return self.SignalChanged:Connect(function(SetPath, Value, Action)
		if not CheckImpl(SetPath, Action, Path, "Remove") then
			return
		end
		Callback(SetPath[#SetPath])
	end)
end

local ProxyMethods = {
	OnChange = function(Proxy, Callback)
		local Object = Objects[MakeProxy.GetIdentifier(Proxy)]
		local Path = MakeProxy.TracePath(Proxy)
		return OnChange(Object, Path, Callback)
	end,
	OnSet = function(Proxy, Callback)
		local Object = Objects[MakeProxy.GetIdentifier(Proxy)]
		local Path = MakeProxy.TracePath(Proxy)
		return OnSet(Object, Path, Callback)
	end,
	OnInsert = function(Proxy, Callback)
		local Object = Objects[MakeProxy.GetIdentifier(Proxy)]
		local Path = MakeProxy.TracePath(Proxy)
		return OnInsert(Object, Path, Callback)
	end,
	OnRemove = function(Proxy, Callback)
		local Object = Objects[MakeProxy.GetIdentifier(Proxy)]
		local Path = MakeProxy.TracePath(Proxy)
		return OnRemove(Object, Path, Callback)
	end,
	GetRaw = MakeProxy.GetData,
}

--== Script ==--
local function Register(Id: number, Data: any, Tags: { string }, Identifier: string?)
	local Object = setmetatable({}, Class)
	Object.Id = Id
	Object.Data = MakeProxy.new(Data, {
		SetCallback = nil,
		IndexMethods = ProxyMethods,
		Identifier = Id,
		CallFunction = function(Proxy)
			return MakeProxy.GetValue(Proxy)
		end,
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

local function Destroy(Object: Class)
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

local function Init()
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
		if not Object then
			return
		end

		Destroy(Object)
	end)

	Shared.Packets.Set.listen(function(Info)
		local Id = Info[1]
		local Path = Info[2]
		local Value = Info[3]

		local Object = Objects[Id]
		if not Object then
			return
		end

		Path = Shared.PathToNormal(Path)
		local Pointer = Object:Get(Path, 1, true)

		Pointer[Path[#Path]] = Value

		local SignalChanged = rawget(Object, "SignalChanged")
		if SignalChanged then
			SignalChanged:FireDeferred(Path, Value, "Set")
		end
	end)

	Shared.Packets.Insert.listen(function(Info)
		local Id = Info[1]
		local Path = Info[2]
		local Value = Info[3]

		local Object = Objects[Id]
		if not Object then
			return
		end

		Path = Shared.PathToNormal(Path)

		local Index = Path[#Path]
		local Pointer = Object:Get(Path, 1, true)
		MakeProxy.Insert(Pointer, Value, Index)

		local SignalChanged = rawget(Object, "SignalChanged")
		if SignalChanged then
			SignalChanged:FireDeferred(Path, Value, "Insert")
		end
	end)
	Shared.Packets.Remove.listen(function(Info)
		local Id = Info[1]
		local Path = Info[2]

		local Object = Objects[Id]
		if not Object then
			return
		end

		Path = Shared.PathToNormal(Path)

		local Index = Path[#Path]
		local Pointer = Object:Get(Path, 1, true)
		MakeProxy.Remove(Pointer, Index)

		local SignalChanged = rawget(Object, "SignalChanged")
		if SignalChanged then
			SignalChanged:FireDeferred(Path, nil, "Remove")
		end
	end)

	Shared.Packets.Message.listen(function(Info)
		local Id = Info[1]
		local Message = Info[2]

		local Object = Objects[Id]
		if not Object then
			return
		end

		local SignalMessage = rawget(Object, "SignalMessage")
		if SignalMessage then
			Object.SignalMessage:Fire(Message, false)
		end
	end)
	Shared.Packets.URMessage.listen(function(Info)
		local Id = Info[1]
		local Message = Info[2]

		local Object = Objects[Id]
		if not Object then
			return
		end

		local SignalMessage = rawget(Object, "SignalMessage")
		if SignalMessage then
			Object.SignalMessage:Fire(Message, true)
		end
	end)

	task.wait()
	Shared.Packets.RequestData.send()
end
if RunService:IsClient() then
	Init()
end

Module.Get = function(Identifier: string): Class?
	return Identifiers[Identifier]
end
Module.GetTagged = function(Tag: string | { string }, Id: number?): Class | { Class }?
	if type(Tag) == "string" then
		return if type(Id) == "number" then Tagged[Tag] and Tagged[Tag][Id] else Tagged[Tag] or {}
	else
		local Result = {}
		for i, v in Tag do
			local Objects = Module.GetTagged(v, Id)
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
end :: ((Tag: string) -> { Class }) & ((Tags: { string }) -> { Class }) & ((Tag: string, Id: number) -> Class?)

local function IdentifierImpl(Identifier: string, Callback)
	return function(Class: Class)
		if Class.Identifier == Identifier then
			if Callback then
				Callback(Class)
			end
			return true
		end
		return false
	end
end
Module.OnNew = function(Identifier: string, Callback: (New: Class) -> (), CallOnExisting: boolean?): Signal.Connection
	local Existing = Module.Get(Identifier)
	if CallOnExisting and Existing then
		Callback(Existing)
	end

	return ObjectAdded:Connect(IdentifierImpl(Identifier, Callback))
end
Module.OnRemoved = function(Identifier: string, Callback: (Removed: Class) -> ()): Signal.Connection
	return ObjectRemoved:Connect(IdentifierImpl(Identifier, Callback))
end

local function TaggedImpl(Tags: string | { string }, Callback)
	if type(Tags) == "string" then
		return function(Class)
			if not Module.GetTagged(Tags, Class.Id) then
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
				Has = Module.GetTagged(v, Class.Id)
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
Module.OnNewTagged = function(
	Tags: string | { string },
	Callback: (New: Class) -> (),
	CallOnExisting: boolean?
): Signal.Connection
	local Handler = TaggedImpl(Tags, Callback)

	if CallOnExisting then
		for i, v in Module.GetTagged(Tags) do
			Handler(v)
		end
	end

	return ObjectAdded:Connect(Handler)
end
Module.OnRemovedTagged = function(Tags: string | { string }, Callback: (Removed: Class) -> ()): Signal.Connection
	local Handler = TaggedImpl(Tags, Callback)

	return ObjectRemoved:Connect(Handler)
end

Module.AwaitFor = function(Identifier: string)
	local Already = Module.Get(Identifier)
	if Already then
		return Already
	end

	return ObjectAdded:Wait(IdentifierImpl(Identifier))
end
Module.AwaitForTagged = function(Tags: string | { string }): Class
	local Already = Module.GetTagged(Tags)

	local _, _nextAlready = next(Already)
	if _nextAlready then
		return _nextAlready
	end

	return ObjectAdded:Wait(Tags, TaggedImpl(Tags))
end :: (Tags: string | { string }) -> Class

function Class.Get(self: Class, Path: PathType, IgnoreLast: number?, notraw: boolean?): any
	local Data = if notraw then self.Data else self._raw
	for i = 1, #Path - (IgnoreLast or 0) do
		Data = Data[Path[i]]
	end
	return Data
end

function Class.Message(self: Class, Message: any, Unreliable: boolean?)
	if not self.Active then
		warn(`Object is not replicated.`)
		warn(self)
		return
	end

	local Messager = Unreliable and Shared.Packets.URMessage or Shared.Packets.Message
	Messager.send({ self.Id, Message })
end
function Class.OnMessage(self: Class, Callback: (Message: any) -> (), Unreliable: boolean?)
	return self.SignalMessage:Connect(function(Message, IsUnreliable)
		if not IsUnreliable ~= not Unreliable then
			return
		end

		Callback(Message)
	end)
end

return Module
