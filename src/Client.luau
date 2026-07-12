--!optimize 2
local RunService = game:GetService("RunService")

const Module = {}

--== Dependencies ==--
const Shared = require("./Shared")
const Signal = require("./Signal")

--== Variables ==--
local IsInit = false
const SignalKeys = {
	"SignalChanged",
	"SignalDestroyed",
	"SignalMessage",
}

const Class = {}
Class.__index = function(self, Key)
	local Existing = rawget(self, Key) or Class[Key]
	if Existing then
		return Existing
	elseif table.find(SignalKeys, Key) then
		local newSignal = Signal.new()
		self[Key] = newSignal
		return newSignal
	end
	return nil
end

const Objects = {} :: { [number]: Class }
const Tagged = {} :: { [string]: { Class } }
const Identifiers = {} :: { [string]: Object }

const ObjectAdded = Signal.new() :: Signal.Signal<Class>
const ObjectRemoved = Signal.new() :: Signal.Signal<Class>

type PathType = Shared.PathType
export type Class<T = {}> = Shared.ClientClass<T>

--== Script ==--
local function Register(Id: number, Data: any, Tags: { string }, Identifier: string?)
	local Object = setmetatable({}, Class)
	Object.Id = Id
	Object.Data = Data
	Object.Tags = Tags
	Object.Identifier = Identifier

	Object.Active = true

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
	Object.Active = nil

	if rawget(Object, "SignalDestroyed") then
		Object.SignalDestroyed:Fire(Object)
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
		local Id = Info[1]

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
		local Pointer = Object:Get(Path, 1)

		if #Path == 0 then
			Object.Data = Value
		else
			Pointer[Path[#Path]] = Value
		end

		if rawget(Object, "SignalChanged") then
			Object.SignalChanged:FireDeferred(Path, Value, "Set")
		end
	end)
	Shared.Packets.SetValues.listen(function(Info)
		local Id = Info[1]
		local Path = Info[2]
		local Values = Info[3]

		local Object = Objects[Id]
		if not Object then
			return
		end

		Path = Shared.PathToNormal(Path)
		local Pointer = Object:Get(Path)

		local SignalValues = {}
		for Key, Value in Values do
			Key = Shared.StringToType(Key)
			Pointer[Key] = Value
			SignalValues[Key] = Value
		end

		if rawget(Object, "SignalChanged") then
			Object.SignalChanged:FireDeferred(Path, SignalValues, "SetValues")
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
		local Pointer = Object:Get(Path, 1)
		table.insert(Pointer, Index, Value)

		if rawget(Object, "SignalChanged") then
			Object.SignalChanged:FireDeferred(Path, Value, "Insert")
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

		local Pointer = Object:Get(Path, 1)
		table.remove(Pointer, Index)

		if rawget(Object, "SignalChanged") then
			Object.SignalChanged:FireDeferred(Path, nil, "Remove")
		end
	end)

	Shared.Packets.Message.listen(function(Info)
		local Id = Info[1]
		local Message = Info[2]

		local Object = Objects[Id]
		if not Object then
			return
		end

		Object.SignalMessage:Fire(Message, false)
	end)
	Shared.Packets.URMessage.listen(function(Info)
		local Id = Info[1]
		local Message = Info[2]

		local Object = Objects[Id]
		if not Object then
			return
		end

		Object.SignalMessage:Fire(Message, true)
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
Module.AwaitForTagged = function(Tags: string | { string }, Count: number?): Class | { Class }
	local Already = Module.GetTagged(Tags)

	if Count then
		local Objects = {}

		for i, v in Already do
			table.insert(Objects, v)
			if #Objects >= Count then
				return Objects
			end
		end

		local Conn = Module.OnNewTagged(Tags, function(New)
			table.insert(Objects, New)
		end)

		while #Objects < Count do
			task.wait()
		end
		Conn:Disconnect()

		return Objects
	else
		local _, _nextAlready = next(Already)
		if _nextAlready then
			return _nextAlready
		end

		return ObjectAdded:Wait(Tags, TaggedImpl(Tags))
	end
end :: ((Tags: string | { string }) -> Class) & ((Tags: string | { string }, Count: number) -> { Class })

function Class.Get(self: Class, Path: PathType, IgnoreLast: number?): any
	local Data = self.Data
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

function Class.OnChange(
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
function Class.OnSet(self: Class, Path: PathType, Callback: (Value: any) -> ()): Signal.Connection
	return self.SignalChanged:Connect(function(SetPath, Value, Action)
		if Action ~= "Set" then
			return
		end
		if #SetPath ~= #Path then
			return
		end
		for i, v in Path do
			if v ~= SetPath[i] then
				return
			end
		end

		Callback(Value)
	end)
end

return Module
