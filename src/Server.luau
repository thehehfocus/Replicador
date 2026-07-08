--!optimize 2

const Module = {}

--== Services ==--
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

--== Dependencies ==--
const Shared = require("./Shared")
const Signal = require("./Signal")

--== Variables ==--
local Ids = 0
local IsInit = false

const SignalKeys = {
	"SignalMessage",
}
const TableKeys = {
	"Children",
	"IncludeList",
	"ExcludeList",
}

const Class = {}
Class.__index = function(self, Key)
	local Existing = rawget(self, Key) or Class[Key]
	if Existing then
		return Existing
	elseif table.find(TableKeys, Key) then
		local newTable = {}
		self[Key] = newTable
		return newTable
	elseif table.find(SignalKeys, Key) then
		print(Key)
		local newSignal = Signal.new()
		self[Key] = newSignal
		return newSignal
	end
	return nil
end

type PathType = Shared.PathType
export type Class<T = {}, Children = {}> = Shared.ServerClass<T, Children>

const ReadyPlayers = {} :: { [Player]: boolean }
const Objects = {} :: { [number]: Class }

Module.SignalPlayerAdded = Signal.new() :: Signal.Signal<Player>
Module.SignalPlayerRemoved = Signal.new() :: Signal.Signal<Player>

--== Script ==--
local function OnPlayerAdded(Player: Player)
	ReadyPlayers[Player] = true

	for i,v in Objects do
		if v.ReplicateMode == "All" then
			Shared.Packets.ObjectCreated.sendTo({ Id = v.Id, Data = v.Data, Tags = v.Tags } , Player)
		end
	end

	Module.SignalPlayerAdded:Fire(Player)
end
local function OnPlayerRemoving(Player: Player)
	ReadyPlayers[Player] = nil
	
	for i,v in Objects do
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

local function Init()
	if IsInit then return end
	IsInit = true
	
	Shared.Packets.RequestData.listen(function(_, Player)
		if ReadyPlayers[Player] then return end
		
		OnPlayerAdded(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player)
		if not ReadyPlayers[Player] then return end

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

function Module.WaitForReadyPlayer(Player: Player) : boolean?
	while not ReadyPlayers[Player] and Player.Parent do 
		task.wait() 
	end
	return ReadyPlayers[Player]
end

--== Class ==--
function Module.Register<T>(Data: T, Tags: string|{string}) : Class<T>
	assert(type(Data) == "table", "Data is required to be a table.")
	if type(Tags) == "string" then
		Tags = { Tags }
	end
	
	Ids += 1
	
	local NewObject = setmetatable({}, Class)
	NewObject.Id = Ids
	NewObject.Data = Data
	NewObject.Tags = Tags or {}
	
	NewObject.Active = true
	NewObject.ReplicateMode = "None"
	
	Objects[Ids] = NewObject
	
	return NewObject
end

function Module.Is(Object: any) : Class|false
	return type(Object) == "table" and getmetatable(Object) == Class and Object
end

--== Utility ==--
function Class.IterateTargets(self: Class, Callback: (Player: Player) -> ())
	if self.ReplicateMode == "All" then
		for i,v in ReadyPlayers do
			if self.ExcludeList[i] then
				continue
			end

			Callback(i)
		end
	elseif self.ReplicateMode ~= "None" then
		for i,v in self.IncludeList do
			Callback(i)
		end
	end
end

local proxyMT = {
	Insert = function(proxy, Value, Index)
		local Path = rawget(proxy, 1) or {} :: PathType
		local Object = rawget(proxy, 2) :: Class

		Object:Insert(Path, Value, Index)
	end,
	Remove = function(proxy, Index)
		local Path = rawget(proxy, 1) or {} :: PathType
		local Object = rawget(proxy, 2) :: Class

		Object:Remove(Path, Index)
	end
}
proxyMT.__index = function(proxy, Key)
	return proxyMT[Key] or rawget(proxy, 4)[Key]
end
proxyMT.__newindex = function(proxy, Key, Value)
	local UsePath = rawget(proxy, 3) :: boolean?
	local Object = rawget(proxy, 2) :: Class
	local Path = rawget(proxy, 1) :: PathType
	
	if UsePath then
		Path[UsePath] = Key
		Object:Set(Path, Value)
		Path[UsePath] = nil
	else
		Object:Set({Key}, Value)
	end
end

--[[
	[1]: Path,
	[2]: Object,
	[3]: UsePath,
	[4]: Data,
--]]

function Class.GetShallowProxy(self: Class, Path: PathType?)
	Path = Path and table.clone(Path)
	
	local Data = self.Data
	local Len = Path and #Path
	local UsePath
	if Len and Len > 0 then
		Data = self:Get(Path)
		UsePath = Len + 1
	end
	
	local Proxy = setmetatable({ 
		Path, 
		self,
		UsePath,
		Data,
	}, proxyMT)
	
	return Proxy
end

--== Set & Get ==--
function Class.Set(self: Class, Path: PathType, Value: any, DontReplicate: boolean?)
	Path = table.clone(Path)

	local Pointer = self:Get(Path, 1)
	Pointer[Path[#Path]] = Value
	
	Path = Shared.PathToString(Path)
	Value = type(Value) == "table" and table.clone(Value) or Value -- Ensuring Value is immutable.
	local Info = { self.Id, Path, Value }
	
	self:IterateTargets(function(Player)
		Shared.Packets.Set.sendTo( Info , Player )
	end)
end
function Class.SetValues(self: Class, Path: PathType, Values: {[PathType]: any})
	Path = table.clone(Path)
	
	local Pointer = self:Get(Path)
	
	local NewValues = {}
	for Key, Value in Values do
		Pointer[Key] = Value
		
		Key = Shared.TypeToString(Key)
		NewValues[Key] = type(Value) == "table" and table.clone(Value) or Value
	end
	
	Path = Shared.PathToString(Path)
	local Info = { self.Id, Path, NewValues }
	
	self:IterateTargets(function(Player)
		Shared.Packets.SetValues.sendTo( Info , Player )
	end)
end
function Class.Get(self: Class, Path: PathType, IgnoreLast: number?) : any
	local Data = self.Data
	for i=1, #Path-(IgnoreLast or 0) do
		Data = Data[Path[i]]
	end
	return Data
end

--== Hierarchy ==--
function Class.AssignChildren(self: Class, ChildMap: {[string]: Class}, ChildName: string?, Child: Class?)
	if Module.Is(ChildMap) then
		error(`Expected string-class map, got a class.`)
	end
	if type(ChildMap) == "table" then
		for i,v in ChildMap do
			self:AssignChildren(nil, i, v)
		end
		return
	end
	
	assert(Child.Parent == nil, `Child is already parented`)
	assert(self.Children[ChildName] == nil, `Child with name '{ChildName}' already exists`)
	
	local RecursiveCheck = self
	while RecursiveCheck do
		RecursiveCheck = RecursiveCheck.Parent
		assert(RecursiveCheck ~= Child, `Child is parented to a descendant`)
	end
	
	self.Children[ChildName] = Child
	Child.Parent = self
	
	IterateGroup(Child, function(Object)
		Object.IncludeList = self.IncludeList
		Object.ExcludeList = self.ExcludeList
		Object.ReplicateMode = self.ReplicateMode
	end)
end

--== Table Operations ==--
function Class.Insert(self: Class, Path: PathType, Value: any, Index: number?)
	Path = table.clone(Path)
	local Table = self:Get(Path)
	
	Index = Index or #Table + 1
	table.insert(Table, Index, Value)
	
	table.insert(Path, Index)
	Path = Shared.PathToString(Path)
	
	Value = type(Value) == "table" and table.clone(Value) or Value
	local Info = { self.Id, Path, Value }
	
	self:IterateTargets(function(Player)
		Shared.Packets.Insert.sendTo( Info , Player )
	end)
end
function Class.Remove(self: Class, Path: PathType, Index: number?)
	Path = table.clone(Path)
	local Table = self:Get(Path)
	Index = Index or #Table
	
	table.remove(Table, Index)
	
	table.insert(Path, Index)
	Path = Shared.PathToString(Path)
	
	local Info = { self.Id, Path }
	
	self:IterateTargets(function(Player)
		Shared.Packets.Remove.sendTo( Info , Player )
	end)
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
		Object.IncludeList = self.IncludeList
		Object.ExcludeList = self.ExcludeList

		local Info = { Object.Id, Object.Data, Object.Tags }
		Object:IterateTargets(function(Player)
			Shared.Packets.ObjectCreated.sendTo( Info , Player )
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

	self.IncludeList[Player] = true
	self.ExcludeList[Player] = nil

	IterateGroup(self, function(Object)
		local Info = { Object.Id, Object.Data, Object.Tags }
		Shared.Packets.ObjectCreated.sendTo( Info , Player )
	end)
	
	return self
end
function Class.Unreplicate(self: Class)
	if self.Parent then
		warn(`Cannot change replication properties of a child object`)
		return
	end
	
	IterateGroup(self, function(Object)
		local Info = { Object.Id }
		Object:IterateTargets(function(Player)
			Shared.Packets.ObjectDestroyed.sendTo( Info , Player )
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

	self.IncludeList[Player] = nil
	if self.ReplicateMode == "All" then
		self.ExcludeList[Player] = true
	end
	
	IterateGroup(self, function(Object)
		local Info = { Object.Id }
		Shared.Packets.ObjectDestroyed.sendTo( Info , Player )
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
		Messager.sendTo( { self.Id, Message } , Player )
	else
		self:IterateTargets(function(Player)
			Messager.sendTo( { self.Id, Message } , Player )
		end)
	end
end
function Class.OnMessage(self: Class, Callback: (Player: Player, Message: any) -> (), Player: Player?, Unreliable: boolean?)
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
		
		local Info = { self.Id }
		self:IterateTargets(function(Player)
			Shared.Packets.ObjectDestroyed.sendTo( Info , Player )
		end)

		self.ReplicateMode = "None"
		self.IncludeList = nil
		self.ExcludeList = nil
		
		for i,v in SignalKeys do
			local destroySignal = rawget(self, v)
			if destroySignal then
				destroySignal:Destroy()
			end
		end
		
		Objects[self.Id] = nil
		
		table.clear(self)
		setmetatable(self, nil)
	end)
end

return Module
