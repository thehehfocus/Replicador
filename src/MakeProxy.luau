--!optimize 2
--!strict

local Module = {}

local IsServer = game:GetService("RunService"):IsServer()

local ORIG_KEY = -1
local PARAMS_KEY = -2
local PARENT_KEY = -3
local INDEX_KEY = -4
local CHILDREN_KEY = -5
local CALLBACKS_KEY = -6

type Params = {
	CallFunction: (Proxy: {}, ...any) -> ()?,
	IndexMethods: { [any]: any }?,
	Identifier: any,
}
type Proxy = { [any]: any }

local function IterateProxy(Proxy: Proxy, Function: (any) -> ())
	Function(Proxy)

	local Children = rawget(Proxy, CHILDREN_KEY)
	if Children then
		for i, v in Children do
			Function(Proxy)
		end
	end
end
local function FireProxyCallbacks(Proxy: any, Action: string, ...)
	if IsServer then
		return
	end

	local Callbacks = rawget(Proxy, CALLBACKS_KEY)
	if Callbacks then
		for i, v in Callbacks do
			task.spawn(v, Action, ...)
		end
	end
end

local MT = {}

local function Set(Proxy: Proxy, Key: any, Value: any)
	local Params = rawget(Proxy, PARAMS_KEY) :: Params
	local Children = rawget(Proxy, CHILDREN_KEY) :: any

	-- Assign the value to the actual table
	local OriginalValue = rawget(Proxy, ORIG_KEY) :: any
	local OldValue = nil
	if OriginalValue then
		OldValue = OriginalValue[Key]
		OriginalValue[Key] = Value
	end

	local Child = Children and Children[Key]
	if Child then
		rawset(Child, ORIG_KEY, Value)

		local ChildChildren = rawget(Child, CHILDREN_KEY)
		if ChildChildren then
			for i, v in ChildChildren do
				Set(Child, i, Value and Value[i] or nil)
			end
		end

		IterateProxy(Child, function(Proxy)
			FireProxyCallbacks(Proxy, "Set")
		end)
		FireProxyCallbacks(Proxy, "DescendantChange", Key, Value, OldValue)

		return
	end

	-- Make value a proxy.
	local new = Module.new(Value, Params, true)
	new[PARENT_KEY] = Proxy
	new[INDEX_KEY] = Key
	setmetatable(new, MT)

	if not Children then
		Children = {}
		rawset(Proxy, CHILDREN_KEY, Children)
	end
	Children[Key] = new
	
	FireProxyCallbacks(new, "Set")
	FireProxyCallbacks(Proxy, "DescendantChange", Key, Value, OldValue)
end

function MT.__index(Proxy, Key)
	local Children = rawget(Proxy, CHILDREN_KEY) :: any
	local Child = Children and Children[Key]
	if Child then
		return Child
	end

	local Params = rawget(Proxy, PARAMS_KEY) :: Params
	local IndexMethods = Params.IndexMethods
	local Method = IndexMethods and IndexMethods[Key]
	if Method ~= nil then
		return Method
	end

	local OriginalValue = rawget(Proxy, ORIG_KEY) :: any

	local OrigAtKey = OriginalValue and OriginalValue[Key] or nil
	Set(Proxy, Key, OrigAtKey)

	local NewChildren = rawget(Proxy, CHILDREN_KEY) :: any
	return NewChildren[Key]
end
function MT.__newindex(Proxy, Key, Value)
	Set(Proxy, Key, Value)
end
function MT.__call(Proxy, ...)
	local Params = rawget(Proxy, PARAMS_KEY) :: Params
	local Cf = Params.CallFunction
	return if Cf then Cf(Proxy, ...) else nil
end

function Module.new<T>(OriginalValue: T, Params: Params, InternalCall: boolean?): T
	local Proxy = {
		[PARAMS_KEY] = Params,
		[ORIG_KEY] = OriginalValue,
	}

	if not InternalCall then
		setmetatable(Proxy, MT)
	end

	return Proxy
end

function Module.TracePath(Proxy): { string | number }
	local Path = {}

	local Pointer = Proxy
	while Pointer do
		local Parent = rawget(Pointer, PARENT_KEY)
		if not Parent then
			break
		end
		table.insert(Path, 1, rawget(Pointer, INDEX_KEY) :: any)
		Pointer = Parent
	end
	return Path
end

function Module.Connect(Proxy, Callback: (Action: string, ...any) -> ()): (Disconnect: nil) -> ()
	local Callbacks: any = rawget(Proxy, CALLBACKS_KEY)
	if not Callbacks then
		Callbacks = {}
		rawset(Proxy, CALLBACKS_KEY, Callbacks)
	end

	local Index = #Callbacks + 1
	Callbacks[Index] = Callback

	return function()
		table.remove(Callbacks, Index)
	end
end

function Module.GetParams(Proxy): Params?
	return type(Proxy) == "table" and rawget(Proxy, PARAMS_KEY) :: Params or nil
end
function Module.GetIdentifier(Proxy): any
	local Params = Module.GetParams(Proxy)
	return Params and Params.Identifier
end
function Module.GetParent(Proxy: Proxy)
	return rawget(Proxy, PARENT_KEY) :: Proxy
end
function Module.GetKey(Proxy: Proxy)
	return rawget(Proxy, INDEX_KEY) :: any
end
function Module.GetValue(Proxy: Proxy)
	return rawget(Proxy, ORIG_KEY) :: any
end

function Module.Insert(Proxy: Proxy, Value: any, Index: number)
	local len = #rawget(Proxy, ORIG_KEY)

	for i = len, Index, -1 do
		local Next = Proxy[i]
		Proxy[i + 1] = rawget(Next, ORIG_KEY)
	end
	Proxy[Index] = Value

	FireProxyCallbacks(Proxy, "Insert", Value, Index)
end
function Module.Remove(Proxy: Proxy, Index: number): any
	local Value = Proxy[Index]
	local len = #rawget(Proxy, ORIG_KEY)

	for i = Index, len - 1 do
		local Next = Proxy[i + 1]
		Proxy[i] = rawget(Next, ORIG_KEY)
	end
	Proxy[len] = nil

	FireProxyCallbacks(Proxy, "Remove", Value, Index)

	return Value
end

return Module
