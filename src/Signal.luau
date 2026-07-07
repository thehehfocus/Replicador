--[[
MIT License
By OutOfFocus (thehehfocus)
--]]

--!optimize 2
--!strict
export type Signal<Params...> = {
	--[[ Properties ]]--
	Id: any,

	--[[ Connect operations ]]--
	Connect: (self: Signal<Params...>, Callback: (Params...) -> ()) -> Connection,
	ConnectParallel: (self: Signal<Params...>, Callback: (Params...) -> ()) -> Connection,
	Once: (self: Signal<Params...>, Callback: (Params...) -> ()) -> Connection,
	Wait: (self: Signal<Params...>) -> Params...,

	--[[ Fire operations ]]--
	Fire: (self: Signal<Params...>, Params...) -> (),
	FireSync: (self: Signal<Params...>, Params...) -> (),
	FireDeferred: (self: Signal<Params...>, Params...) -> (),
	FireProtected: (self: Signal<Params...>, ErrorHandler: (Error: string, Connection: Connection)->(), Params...) -> (),

	--[[ Utilities ]]--
	SetId: (self: Signal<Params...>, Id: any) -> (),
	GetConnections: (self: Signal<Params...>) -> {Connection},
	DisconnectAll: (self: Signal<Params...>) -> (),
	Destroy: (self: Signal<Params...>) -> (),
}
type InternalSignal = {
	Head: InternalConnection?,
	Tail: InternalConnection?,
} & Signal<any>

export type Connection = {
	Signal: InternalSignal,	
	Disconnect: (Connection: Connection) -> (),
	Connected: boolean?
}
type InternalConnection = {
	-- [1] Prev: InternalConnection?,
	-- [2] Next: InternalConnection?,
	-- [3] Callback: (...any)->(),
	-- [4] Connected: boolean?,
	-- [5] Signal: InternalSignal,
	[number]: any
}

-- Getting globals
const taskspawn = task.spawn
const taskdefer = task.defer
const sync = task.synchronize
const desync = task.desynchronize
const coroutinecreate = coroutine.create
const coroutineresume = coroutine.resume
const coroutinerunning = coroutine.running
const coroutineyield = coroutine.yield
const coroutinestatus = coroutine.status
const tableinsert = table.insert

-- Pool
const Threads = {} :: {thread}
const function ReuseCall(Thread, Callback, ...)
	Callback(...)
	tableinsert(Threads, Thread)
end
const function ReuseThread()
	while true do
		ReuseCall(coroutineyield())
	end
end

const function Disconnect(Connection: InternalConnection)
	if not Connection[4] then return end
	Connection[4] = nil

	local Signal = Connection[5]
	local Prev = Connection[1] :: InternalConnection?
	local Next = Connection[2] :: InternalConnection?

	if Prev then
		Prev[2] = Next
	else
		Signal.Tail = Next
	end

	if Next then
		Next[1] = Prev
	else
		Signal.Head = Prev
	end
end

const Storage = {} :: {[any]: Signal<any>}

const SignalClass = {}
SignalClass.__index = SignalClass
SignalClass.__tostring = function(Signal: InternalSignal)
	local __tostring = SignalClass.__tostring
	SignalClass.__tostring = nil :: any
	local address = tostring(Signal)
	SignalClass.__tostring = __tostring

	if Signal.Id then
		return `(SignalX, id: {Signal.Id}, {address})`
	else
		return "(SignalX, " .. address .. ")"
	end
end

-- Uses task.spawn to fire the callbacks, immediate
function SignalClass.Fire(Signal: InternalSignal, ...)
	local Pointer = Signal.Tail
	while Pointer do
		local len = #Threads
		if len == 0 then
			local Thread = coroutinecreate(ReuseThread)
			coroutineresume(Thread)
			taskspawn(Thread, Thread, Pointer[3], ...)
		else
			local Thread = Threads[len]
			Threads[len] = nil
			taskspawn(Thread, Thread, Pointer[3], ...)
		end
		Pointer = Pointer[2]
	end
end

-- Uses task.defer to fire the callbacks, fires last in the frame
function SignalClass.FireDeferred(Signal: InternalSignal, ...)
	local Pointer = Signal.Tail
	while Pointer do
		local len = #Threads
		if len == 0 then
			local Thread = coroutinecreate(ReuseThread)
			coroutineresume(Thread)
			taskdefer(Thread, Thread, Pointer[3], ...)
		else
			local Thread = Threads[len]
			Threads[len] = nil
			taskdefer(Thread, Thread, Pointer[3], ...)
		end
		Pointer = Pointer[2]
	end
end

const function errHandler(Error)
	warn(`Error calling callback: {Error or "unknown error"}`)
end
const function safeCall(Connection: InternalConnection, ErrorHandler, ...)
	xpcall(Connection[3], ErrorHandler and function(Error)
		ErrorHandler(Error, Connection)
	end or errHandler, ...)
end
-- Wraps callbacks in an xpcall
function SignalClass.FireProtected(Signal: InternalSignal, ErrorHandler: ()->(), ...)
	local Pointer = Signal.Tail
	while Pointer do
		local len = #Threads
		if len == 0 then
			local Thread = coroutinecreate(ReuseThread)
			coroutineresume(Thread)
			taskspawn(Thread, Thread, safeCall, Pointer, ErrorHandler, ...)
		else
			local Thread = Threads[len]
			Threads[len] = nil
			taskspawn(Thread, Thread, safeCall, Pointer, ErrorHandler, ...)
		end
		Pointer = Pointer[2]
	end
end

-- Fires all callbacks in a single thread, simplest and fastest if none yield, a.k.a. uses task.wait()
function SignalClass.FireSync(Signal: InternalSignal, ...)
	local Pointer = Signal.Tail
	while Pointer do
		Pointer[3](...)

		Pointer = Pointer[2]
	end
end

local ConnectionClass = {
	Connected = function(self: InternalConnection) return self[4] end,
	Signal = function(self: InternalConnection) return self[5] end,
	Disconnect = Disconnect,
}
ConnectionClass.__index = ConnectionClass

const function Connect(Signal: InternalSignal, Callback) : InternalConnection
	local Head = Signal.Head

	local Connection = setmetatable({
		[1] = Head,
		[2] = nil,
		[3] = Callback,
		[4] = true,
		[5] = Signal,
	}, ConnectionClass) :: InternalConnection

	if Head then
		Head[2] = Connection
	else
		Signal.Tail = Connection
	end
	Signal.Head = Connection

	return Connection
end
SignalClass.Connect = Connect 

function SignalClass.Once(Signal: InternalSignal, Callback)
	local Connection : InternalConnection
	Connection = Connect(Signal, function()
		Disconnect(Connection)
		Callback()
	end)

	return Connection
end

function SignalClass.ConnectParallel(Signal: InternalSignal, Callback)
	return Connect(Signal, function(...)
		desync()
		Callback(...)
		sync()
	end)
end

function SignalClass.Wait(Signal: InternalSignal)
	local Thread = coroutinerunning()

	local Connection: InternalConnection
	Connection = Connect(Signal, function(...)
		Disconnect(Connection)
		if coroutinestatus(Thread) == "suspended" then
			taskspawn(Thread, ...)
		end
	end)

	return coroutineyield()
end

function SignalClass.SetId(Signal: InternalSignal, Id: any)
	local oldId = Signal.Id
	if oldId and Storage[oldId] == Signal then
		Storage[oldId] = nil
	end

	Signal.Id = Id
	Storage[Id] = Signal
end

function SignalClass.GetConnections(Signal: InternalSignal)
	local Connections = {}

	local Pointer = Signal.Tail
	while Pointer do
		tableinsert(Connections, Pointer)
		Pointer = Pointer[2]
	end

	return Connections
end

function SignalClass.DisconnectAll(Signal: InternalSignal)
	local Pointer = Signal.Tail
	while Pointer do
		Pointer[4] = nil
		Pointer = Pointer[2]
	end
	Signal.Tail = nil
	Signal.Head = nil
end

function SignalClass.Destroy(Signal: InternalSignal)
	Signal:DisconnectAll()
	local Id = Signal.Id
	if Id then
		Storage[Id] = nil
		Signal.Id = nil
	end
end

const function CreateSignal(Id: any) : Signal<...any>
	local Signal = setmetatable({}, SignalClass)
	if Id then
		Storage[Id] = Signal :: any
		Signal.Id = Id
	end
	return Signal :: any
end

const function GetSignal(Id: any) : Signal<...any>
	return Storage[Id]
end

local Module = {}
Module.new = CreateSignal
Module.get = GetSignal

Module.Wrap = function<T...>(rbxSignal: RBXScriptSignal<T...>) : (Signal<T...>, Connection)
	local Signal = CreateSignal()
	return Signal, rbxSignal:Connect(function(...)
		Signal:Fire(...)
	end)
end
Module.Is = function(Signal: any) : Signal<...any>|false
	return type(Signal) == "table" and getmetatable(Signal) == SignalClass and Signal
end

Module.SignalMT = SignalClass
Module.ConnectionMT = ConnectionClass

setmetatable(Module, {__call = Module.new})

return Module
