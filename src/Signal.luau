--[[
MIT License
By OutOfFocus (thehehfocus on github)
--]]

--!optimize 2
--!strict
export type Signal<Params... = ...any> = {
	--[[ Connect operations ]]
	Connect: (self: Signal<Params...>, Callback: (Params...) -> ()) -> Connection,
	Wait: (self: Signal<Params...>, Filter: ((Params...) -> boolean?)?) -> Params...,
	Disconnect: (Connection: InternalConnection) -> (),

	--[[ Fire operations ]]
	Fire: (self: Signal<Params...>, Params...) -> (),
	FireDeferred: (self: Signal<Params...>, Params...) -> (),

	--[[ Utilities ]]
	DisconnectAll: (self: Signal<Params...>) -> (),
	Destroy: (self: Signal<Params...>) -> (),
}
type InternalSignal = {
	Head: InternalConnection?,
	Tail: InternalConnection?,
} & Signal

export type Connection = (Disconnect: nil) -> ()
type InternalConnection = {
	-- [1] Prev: InternalConnection?,
	-- [2] Next: InternalConnection?,
	-- [3] Callback: (...any)->(),
	-- [4] Connected: boolean?,
	[number]: any,
}

-- Pool
local Threads = {} :: { thread }
local ThreadLimit = 50

local function ReuseCall(Thread, Callback, ...)
	Callback(...)

	local len = #Threads
	if len < ThreadLimit then
		Threads[len + 1] = Thread
	end
end
local function ReuseThread()
	while true do
		ReuseCall(coroutine.yield())
	end
end

local function Disconnect(Signal: any, Connection: InternalConnection)
	if not Connection[4] then
		return
	end
	Connection[4] = nil

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

local SignalClass = {}
SignalClass.__index = SignalClass

-- Uses task.spawn to fire the callbacks, immediate
function SignalClass.Fire(Signal: InternalSignal, ...)
	local Pointer = Signal.Tail
	while Pointer do
		local len = #Threads
		if len == 0 then
			local Thread = coroutine.create(ReuseThread)
			coroutine.resume(Thread)
			task.spawn(Thread, Thread, Pointer[3], ...)
		else
			local Thread = Threads[len]
			Threads[len] = nil
			task.spawn(Thread, Thread, Pointer[3], ...)
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
			local Thread = coroutine.create(ReuseThread)
			coroutine.resume(Thread)
			task.defer(Thread, Thread, Pointer[3], ...)
		else
			local Thread = Threads[len]
			Threads[len] = nil
			task.defer(Thread, Thread, Pointer[3], ...)
		end
		Pointer = Pointer[2]
	end
end

local function Connect(Signal: InternalSignal, Callback)
	local Head = Signal.Head

	local Connection = {
		[1] = Head,
		[2] = nil,
		[3] = Callback,
		[4] = true,
	} :: InternalConnection

	if Head then
		Head[2] = Connection
	else
		Signal.Tail = Connection
	end
	Signal.Head = Connection

	return function()
		Disconnect(Signal, Connection)
	end
end
SignalClass.Connect = Connect

function SignalClass.Wait(Signal: InternalSignal, Filter: ((...any) -> boolean?)?)
	local Thread = coroutine.running()

	local Connection: Connection
	Connection = Connect(Signal, function(...)
		if Filter and not Filter(...) then
			return
		end

		Connection()
		if coroutine.status(Thread) == "suspended" then
			task.spawn(Thread, ...)
		end
	end)

	return coroutine.yield()
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
end

local function CreateSignal(): Signal
	local Signal = setmetatable({}, SignalClass)

	return Signal :: any
end

local Module = {}
Module.new = CreateSignal

return Module
