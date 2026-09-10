--!optimize 2

local Server = {}

--== Services ==--
local Players = game:GetService("Players")

--== Dependencies ==--
local Shared = require("./Shared")
local Signal = require("./Signal")
local MakeProxy = require("./MakeProxy")

--== Variables ==--
local Ids = 0

local SignalKeys = {
	"SignalChanged",
}
local TableKeys = {
	"Children",
	"IncludeList",
	"ExcludeList",
}

local Class = {}
function Class.__index(self: InternalClass, Key)
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

		if Key == "SignalChanged" then
			self._changetrack = true
		end

		return newSignal
	end
	return nil
end

type PathType = Shared.PathType
export type InternalClass<T = {}> = Shared.ServerClass<T> & {
	ReplicateMode: "All" | "None",

	IncludeList: { [Player]: boolean },
	ExcludeList: { [Player]: boolean },

	Parent: any?,
	Children: any,

	_creation: {},
	_raw: {},
	_changetrack: boolean?,
}

local ReadyPlayers = {} :: { [Player]: boolean }
local Objects = {} :: { [number]: InternalClass }
local Identifiers = {} :: { [string]: InternalClass }

Server.SignalPlayerAdded = Signal.new() :: Signal.Signal<Player>
Server.SignalPlayerRemoved = Signal.new() :: Signal.Signal<Player>

--== Script ==--
local function OnPlayerAdded(Player: Player)
	ReadyPlayers[Player] = true

	for i, v in Objects do
		if v.ReplicateMode == "All" then
			local Info = v._creation
			Shared.Packets.ObjectCreated.sendTo(Info, Player)
		end
	end

	Server.SignalPlayerAdded:Fire(Player)
end
local function OnPlayerRemoving(Player: Player)
	ReadyPlayers[Player] = nil

	for i, v in Objects do
		v.IncludeList[Player] = nil
		v.ExcludeList[Player] = nil
	end

	Server.SignalPlayerRemoved:Fire(Player)
end

local ProxyMethods = {
	Insert = function(Proxy, Value, Index)
		local Object = Objects[MakeProxy.GetIdentifier(Proxy)]
		local Raw = MakeProxy.GetValue(Proxy)

		Index = Index or #Raw + 1
		MakeProxy.Insert(Proxy, Value, Index)

		local Path = MakeProxy.TracePath(Proxy)
		table.insert(Path, Index)

		Value = type(Value) == "table" and Shared.DeepCopy(Value) or Value
		local Info = { Object.Id, Path, Value }

		Object:IterateTargets(function(Player)
			Shared.Packets.Insert.sendTo(Info, Player)
		end)

		if Object._changetrack then
			Object.SignalChanged:Fire(Path, Value, "Insert")
		end
	end,
	Remove = function(Proxy, Index)
		local Object = Objects[MakeProxy.GetIdentifier(Proxy)]
		local Raw = MakeProxy.GetValue(Proxy)

		Index = Index or #Raw
		MakeProxy.Remove(Proxy, Index)

		local Path = MakeProxy.TracePath(Proxy)
		table.insert(Path, Index)

		local Info = { Object.Id, Path }
		Object:IterateTargets(function(Player)
			Shared.Packets.Remove.sendTo(Info, Player)
		end)

		if Object._changetrack then
			Object.SignalChanged:Fire(Path, nil, "Remove")
		end
	end,

	Get = MakeProxy.GetValue,
	Set = function(Proxy, Value)
		if type(Value) == "function" then
			Value = Value(MakeProxy.GetValue(Proxy))
		end

		local Object = Objects[MakeProxy.GetIdentifier(Proxy)]
		local Parent = MakeProxy.GetParent(Proxy)
		local Key = MakeProxy.GetKey(Proxy)

		local Path = MakeProxy.TracePath(Parent)
		table.insert(Path, Key)
		Object:PathSet(Path, Value, MakeProxy.GetValue(Parent))

		return Value
	end,
}

local IsInit = false
function Server.Init()
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
end

--== Class ==--
function Server.Register<T>(Props: {
	Data: T,
	Identifier: string?,
	Tags: { string }?,
	[string]: any,
}): Shared.ServerClass<T>
	local Identifier = Props.Identifier
	local Data = Props.Data
	local Tags = Props.Tags

	assert(not (Identifier and Identifiers[Identifier]), `Object with identifier {Identifier} already exists.`)
	assert(type(Data) == "table", "Data is required to be a table.")

	Ids += 1

	local NewObject = setmetatable({}, Class) :: InternalClass
	NewObject.Id = Ids
	NewObject.Identifier = Props.Identifier
	NewObject.Tags = Tags or {}

	NewObject.Active = true
	NewObject.ReplicateMode = "None"

	NewObject._raw = Data
	NewObject._creation = { NewObject.Id, NewObject._raw, NewObject.Tags, NewObject.Identifier }

	NewObject.Data = MakeProxy.new(Data, {
		CallFunction = function(Proxy, ...)
			if select("#", ...) > 0 then
				local Value = ...
				if type(Value) == "function" then
					Value = Value(MakeProxy.GetValue(Proxy))
				end

				local Parent = MakeProxy.GetParent(Proxy)
				local Key = MakeProxy.GetKey(Proxy)

				local Path = MakeProxy.TracePath(Parent)
				table.insert(Path, Key)
				NewObject:PathSet(Path, Value, MakeProxy.GetValue(Parent))

				return Value
			else
				return MakeProxy.GetValue(Proxy)
			end
		end,
		Identifier = NewObject.Id,
		IndexMethods = ProxyMethods,
	})

	Objects[Ids] = NewObject
	if Identifier then
		Identifiers[Identifier] = NewObject
	end

	return NewObject
end

function Server.Get<T>(Identifier: string, Template: T?): Shared.ServerClass<T>?
	return Identifiers[Identifier]
end

function Server.WaitForReadyPlayer(Player: Player): boolean?
	if ReadyPlayers[Player] then
		return Player
	end
	
	local Left: boolean?
	
	local Disconnect: Signal.Connection
	Disconnect = Server.SignalPlayerRemoved:Connect(function(RemovedPlayer)
		if RemovedPlayer ~= Player then
			return
		end
		
		Left = true
		Disconnect()
	end)
	
	local AddedPlayer
	repeat
		AddedPlayer = Server.SignalPlayerAdded:Wait()
	until Left or AddedPlayer == Player
	Disconnect()
	
	return if Left then false else true
end

function Class.PathSet(self: InternalClass, Path: PathType, Value: any, tbl: any)
	local Pointer = tbl or self:PathGet(Path, 1)
	Pointer[Path[#Path]] = Value

	Value = type(Value) == "table" and Shared.DeepCopy(Value) or Value -- Ensuring Value is immutable.
	local Info = { self.Id, Path, Value }

	self:IterateTargets(function(Player)
		Shared.Packets.Set.sendTo(Info, Player)
	end)

	if self._changetrack then
		self.SignalChanged:Fire(Path, Value, "Set")
	end
end
function Class.PathGet(self: InternalClass, Path: PathType, IgnoreLast: number?, notraw: boolean?): any
	local Data = if notraw then self.Data else self._raw
	for i = 1, #Path - (IgnoreLast or 0) do
		Data = Data[Path[i]]
	end
	return Data
end

--== Utility ==--
function Class.IterateTargets(self: InternalClass, Callback: (Player: Player) -> ())
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
function Class.IsTarget(self: InternalClass, Player: Player): boolean?
	return ReadyPlayers[Player]
		and if self.ReplicateMode == "All" then not self.ExcludeList[Player] else self.IncludeList[Player]
end

--== Replication ==--
function Class.Replicate(self: InternalClass)
	self.ReplicateMode = "All"
	self.IncludeList = nil
	self.ExcludeList = nil

	local Info = self._creation
	self:IterateTargets(function(Player)
		Shared.Packets.ObjectCreated.sendTo(Info, Player)
	end)

	return self
end
function Class.Subscribe(self: InternalClass, Player: Player)
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

	local Info = self._creation
	self:IterateTargets(function(Player)
		Shared.Packets.ObjectCreated.sendTo(Info, Player)
	end)

	return self
end
function Class.Unreplicate(self: InternalClass)
	local Info = self.Id
	self:IterateTargets(function(Player)
		Shared.Packets.ObjectDestroyed.sendTo(Info, Player)
	end)

	self.ReplicateMode = "None"
	self.IncludeList = nil
	self.ExcludeList = nil

	return self
end
function Class.Unsubscribe(self: InternalClass, Player: Player)
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

	local Info = self.Id
	Shared.Packets.ObjectDestroyed.sendTo(Info, Player)

	return self
end

--== Destruction ==--
function Class.Destroy(self: InternalClass)
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
end

return Server
