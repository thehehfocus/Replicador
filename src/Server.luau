--!optimize 2

local Module = {}

--== Services ==--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--== Dependencies ==--
local Shared = require("./Shared")
local Signal = require("./Signal")
local MakeProxy = require("./MakeProxy")

--== Variables ==--
local Ids = 0
local IsInit = false

local SignalKeys = {
	"SignalMessage",
}
local TableKeys = {
	"Children",
	"IncludeList",
	"ExcludeList",
}

local Class = {}
Class.__index = function(self, Key)
	local Existing = Class[Key]
	if Existing then
		return Existing
	elseif table.find(TableKeys, Key) then
		local newTable = {}
		self[Key] = newTable
		return newTable
	elseif table.find(SignalKeys, Key) then
		local newSignal = Signal.new()
		self[Key] = newSignal
		return newSignal
	end
	return nil
end

type PathType = Shared.PathType
export type Class<T = {}, Children = {}> = Shared.ServerClass<T, Children>

local ReadyPlayers = {} :: { [Player]: boolean }
local Objects = {} :: { [number]: Class }
local Identifiers = {} :: { [string]: Class }

Module.SignalPlayerAdded = Signal.new() :: Signal.Signal<Player>
Module.SignalPlayerRemoved = Signal.new() :: Signal.Signal<Player>

--== Script ==--
local function CreateForPlayer(Creation, Player: Player)
	Shared.Packets.ObjectCreated.sendTo(Creation, Player)
end
local function DestroyForPlayer(Id: number, Player: Player)
	Shared.Packets.ObjectDestroyed.sendTo(Id, Player)
end

local function OnPlayerAdded(Player: Player)
	ReadyPlayers[Player] = true

	for i, v in Objects do
		if v.ReplicateMode == "All" then
			local Info = v._creation
			CreateForPlayer(Info, Player)
		end
	end

	Module.SignalPlayerAdded:Fire(Player)
end
local function OnPlayerRemoving(Player: Player)
	ReadyPlayers[Player] = nil

	for i, v in Objects do
		v.IncludeList[Player] = nil
		v.ExcludeList[Player] = nil
	end

	Module.SignalPlayerRemoved:Fire(Player)
end

local function IterateGroup(self: Class, Func: (self: Class) -> ())
	Func(self)

	local Children = rawget(self, "Children")
	if Children then
		for _, Child in Children do
			IterateGroup(Child, Func)
		end
	end
end

local function Get(self: Class, Path: PathType, IgnoreLast: number?, notraw: boolean?): any
	local Data = if notraw then self.Data else self._raw
	for i = 1, #Path - (IgnoreLast or 0) do
		Data = Data[Path[i]]
	end
	return Data
end
local function Set(self: Class, Path: PathType, Value: any)
	local Pointer = Get(self, Path, 1)
	Pointer[Path[#Path]] = Value

	Path = Shared.PathToString(Path)
	Value = type(Value) == "table" and table.clone(Value) or Value -- Ensuring Value is immutable.
	local Info = { self.Id, Path, Value }

	self:IterateTargets(function(Player)
		Shared.Packets.Set.sendTo(Info, Player)
	end)
end
local function Insert(self: Class, Path: PathType, Value: any, Index: number?)
	local Table = Get(self, Path)

	Index = Index or #Table + 1
	table.insert(Table, Index, Value)

	table.insert(Path, Index)
	Path = Shared.PathToString(Path)

	Value = type(Value) == "table" and table.clone(Value) or Value
	local Info = { self.Id, Path, Value }

	self:IterateTargets(function(Player)
		Shared.Packets.Insert.sendTo(Info, Player)
	end)
end
local function Remove(self: Class, Path: PathType, Index: number?)
	local Table = Get(self, Path)
	Index = Index or #Table

	table.remove(Table, Index)

	table.insert(Path, Index)
	Path = Shared.PathToString(Path)

	local Info = { self.Id, Path }

	self:IterateTargets(function(Player)
		Shared.Packets.Remove.sendTo(Info, Player)
	end)
end

local function Init()
	if IsInit then
		return
	end
	IsInit = true

	Shared.Packets.RequestData.listen(function(_, Player)
		if ReadyPlayers[Player] then
			return
		end

		OnPlayerAdded(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player)
		if not ReadyPlayers[Player] then
			return
		end

		OnPlayerRemoving(Player)
	end)

	Shared.Packets.Message.listen(function(Info, Player)
		local Id = Info[1]
		local Message = Info[2]

		local Object = Objects[Id]
		if not Object then
			return
		end

		Object.SignalMessage:Fire(Message, false, Player)
	end)
	Shared.Packets.URMessage.listen(function(Info, Player)
		local Id = Info[1]
		local Message = Info[2]

		local Object = Objects[Id]
		if not Object then
			return
		end

		Object.SignalMessage:Fire(Message, true, Player)
	end)
end
if RunService:IsServer() then
	Init()
end

function Module.WaitForReadyPlayer(Player: Player): boolean?
	while not ReadyPlayers[Player] and Player.Parent do
		task.wait()
	end
	return ReadyPlayers[Player]
end

local ProxyMethods = {
	Insert = function(Proxy, Value, Index)
		local Object = Objects[MakeProxy.GetIdentifier(Proxy)]
		local Path = MakeProxy.TracePath(Proxy)
		return Insert(Object, Path, Value, Index)
	end,
	Remove = function(Proxy, Index)
		local Object = Objects[MakeProxy.GetIdentifier(Proxy)]
		local Path = MakeProxy.TracePath(Proxy)
		return Remove(Object, Path, Index)
	end,
}

--== Class ==--
function Module.Register<T>(Props: {
	Data: T,
	Identifier: string?,
	Tags: string | { string }?,
	[string]: any,
}): Class<T>
	local Identifier = Props.Identifier
	local Data = Props.Data
	local Tags = Props.Tags

	assert(not (Identifier and Identifiers[Identifier]), `Object with identifier {Identifier} already exists.`)
	assert(type(Data) == "table", "Data is required to be a table.")
	if type(Tags) == "string" then
		Tags = { Tags }
	end

	Ids += 1

	local NewObject = setmetatable({}, Class)
	NewObject.Id = Ids
	NewObject.Identifier = Props.Identifier
	NewObject.Data = Data
	NewObject.Tags = Tags or {}

	NewObject.Data = MakeProxy.new(Data, {
		SetCallback = function(Parent, Key, Value)
			local Path = MakeProxy.TracePath(Parent)
			table.insert(Path, Key)
			Set(NewObject, Path, Value)
		end,
		IndexMethods = ProxyMethods,
		CallFunction = function(Proxy)
			return MakeProxy.GetValue(Proxy)
		end,
		Identifier = NewObject.Id,
		IgnoreNonTableValues = true,
	})

	NewObject.Active = true
	NewObject.ReplicateMode = "None"

	NewObject._raw = Data
	NewObject._creation = { NewObject.Id, NewObject._raw, NewObject.Tags, NewObject.Identifier }

	Objects[Ids] = NewObject
	if Identifier then
		Identifiers[Identifier] = NewObject
	end

	return NewObject
end

function Module.GetFromIdentifier(Identifier: string): Class?
	return Identifiers[Identifier]
end

function Module.Is(Object: any): Class | false
	return type(Object) == "table" and getmetatable(Object) == Class and Object
end

--== Utility ==--
function Class.IterateTargets(self: Class, Callback: (Player: Player) -> ())
	if self.ReplicateMode == "All" then
		for i, v in ReadyPlayers do
			if self.ExcludeList[i] then
				continue
			end

			Callback(i)
		end
	else
		for i, v in self.IncludeList do
			Callback(i)
		end
	end
end

function Class.IsTarget(self: Class, Player: Player): boolean?
	return ReadyPlayers[Player]
		and if self.ReplicateMode == "All" then not self.ExcludeList[Player] else self.IncludeList[Player]
end

--== Hierarchy ==--
function Class.SetParent(self: Class, Parent: Class?, ChildIndex: any?)
	if not Parent and not ChildIndex then
		for i, v in self.Parent.Children do
			if v == self then
				self.Parent.Children[i] = nil
			end
		end

		self.Parent = nil
		self.IncludeList = {}
		self.ExcludeList = {}
		self.ReplicateMode = "None"

		return
	elseif not Parent and ChildIndex then
		error(`Parent is nil.`)
	end

	assert(self.Parent == nil, `Child is already parented`)
	assert(Parent.Children[ChildIndex] == nil, `Child with name '{ChildIndex}' already exists`)

	local RecursiveCheck = Parent
	while RecursiveCheck do
		RecursiveCheck = RecursiveCheck.Parent
		assert(RecursiveCheck ~= self, `Child is parented to a descendant`)
	end

	Parent.Children[ChildIndex] = self
	self.Parent = Parent

	self:IterateTargets(function(Player)
		if not Parent:IsTarget(Player) then
			DestroyForPlayer(self.Id, Player)
		end
	end)

	IterateGroup(self, function(Object)
		Object.IncludeList = Parent.IncludeList
		Object.ExcludeList = Parent.ExcludeList
		Object.ReplicateMode = Parent.ReplicateMode
	end)

	local Info = self._creation
	self:IterateTargets(function(Player)
		CreateForPlayer(Info, Player)
	end)

	return self
end

--== Replication ==--
function Class.Replicate(self: Class)
	if self.Parent then
		warn(`Cannot change replication properties of a child object`)
		return
	end

	self.ReplicateMode = "All"
	table.clear(self.IncludeList)
	table.clear(self.ExcludeList)

	IterateGroup(self, function(Object)
		Object.ReplicateMode = self.ReplicateMode

		local Info = self._creation
		Object:IterateTargets(function(Player)
			CreateForPlayer(Info, Player)
		end)
	end)

	return self
end
function Class.Subscribe(self: Class, Player: Player)
	if self.Parent then
		warn(`Cannot change replication properties of a child object`)
		return
	end
	if Player and not ReadyPlayers[Player] then
		warn(`Player {Player} is not ready`)
		return
	end
	if self.IncludeList[Player] then
		return
	end

	if self.ReplicateMode ~= "All" then
		self.IncludeList[Player] = true
	end
	self.ExcludeList[Player] = nil

	IterateGroup(self, function(Object)
		local Info = self._creation
		CreateForPlayer(Info, Player)
	end)

	return self
end
function Class.Unreplicate(self: Class)
	if self.Parent then
		warn(`Cannot change replication properties of a child object`)
		return
	end

	IterateGroup(self, function(Object)
		local Info = Object.Id
		Object:IterateTargets(function(Player)
			DestroyForPlayer(Info, Player)
		end)

		if Object == self then
			self.ReplicateMode = "None"
			table.clear(self.IncludeList)
			table.clear(self.ExcludeList)

			return
		end

		Object.ReplicateMode = self.ReplicateMode
	end)
end
function Class.Unsubscribe(self: Class, Player: Player)
	if self.Parent then
		warn(`Cannot change replication properties of a child object`)
		return
	end
	if Player and not ReadyPlayers[Player] then
		warn(`Player {Player} is not ready`)
		return
	end
	if self.ExcludeList[Player] then
		return
	end

	self.IncludeList[Player] = nil
	if self.ReplicateMode == "All" then
		self.ExcludeList[Player] = true
	end

	IterateGroup(self, function(Object)
		local Info = Object.Id
		DestroyForPlayer(Info, Player)
	end)
end

--== Messaging ==--
function Class.Message(self: Class, Message: any, Player: Player?, Unreliable: boolean?)
	local FoundPlayer = self.IncludeList[Player] or self.ReplicateMode == "All" and not self.ExcludeList[Player]
	if not FoundPlayer then
		warn(`Player {Player} is not subscribed to the object`)
		warn(self)
		return
	end

	local Messager = Unreliable and Shared.Packets.URMessage or Shared.Packets.Message
	if Player then
		Messager.sendTo({ self.Id, Message }, Player)
	else
		self:IterateTargets(function(Player)
			Messager.sendTo({ self.Id, Message }, Player)
		end)
	end
end
function Class.OnMessage(
	self: Class,
	Callback: (Player: Player, Message: any) -> (),
	Player: Player?,
	Unreliable: boolean?
)
	return self.SignalMessage:Connect(function(Message, IsUnreliable, ThePlayer)
		if not IsUnreliable ~= not Unreliable then
			return
		end
		if Player and Player ~= ThePlayer then
			return
		end

		Callback(ThePlayer, Message)
	end)
end

--== Destruction ==--
function Class.Destroy(self: Class)
	IterateGroup(self, function(self)
		self.Active = nil

		self:Unreplicate()

		for i, v in SignalKeys do
			local destroySignal = rawget(self, v)
			if destroySignal then
				destroySignal:Destroy()
			end
		end

		Objects[self.Id] = nil
		if self.Identifier then
			Identifiers[self.Identifier] = nil
		end

		table.clear(self)
		setmetatable(self, nil)
	end)
end

return Module
