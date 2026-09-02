--!optimize 2
local Module = {}

local ORIG_KEY = -1
local PARAMS_KEY = -2
local PARENT_KEY = -3
local INDEX_KEY = -4
local CHILDREN_KEY = -5
local CALLBACKS_KEY = -6

type Params = {
	SetCallback: (Proxy: {}, Key: any, Value: any) -> ()?,
	CallFunction: (Proxy: {}, ...any) -> ()?,
	IndexMethods: {}?,
	Identifier: any,
	IsServer: boolean?,
	TempDisableSetCallback: number,
}

Module._ntvst = false

local MT = {}

local function IterateProxy(Proxy: any, Function: (any) -> ())
	Function(Proxy)

	local Children = rawget(Proxy, CHILDREN_KEY)
	if Children then
		for i, v in Children do
			Function(Proxy)
		end
	end
end
local function FireProxyCallbacks(Proxy: any, Action: string, ...)
	local Params: Params = rawget(Proxy, PARAMS_KEY)
	if Params.IsServer then
		return
	end

	local Callbacks = rawget(Proxy, CALLBACKS_KEY)
	if Callbacks then
		for i, v in Callbacks do
			task.spawn(v, Action, ...)
		end
	end
end

local function Set(Proxy, Key, Value)
	local Params: Params = rawget(Proxy, PARAMS_KEY)
	local Callback = Params.SetCallback

	local Children = rawget(Proxy, CHILDREN_KEY)

	-- Assign the value to the actual table
	local OriginalValue = rawget(Proxy, ORIG_KEY)
	if OriginalValue then
		OriginalValue[Key] = Value
	else
		error("Attempt to index a nil proxy value.")
	end

	local Child = Children and Children[Key]

	if Child then
		rawset(Child, ORIG_KEY, Value)
		local ChildChildren = rawget(Child, CHILDREN_KEY)

		if ChildChildren then
			for i, v in ChildChildren do
				Set(Child, i, Value and Value[i])
			end
		end

		if not Params.IsServer then
			IterateProxy(Child, function(Proxy)
				FireProxyCallbacks(Proxy, "Set")
			end)
			FireProxyCallbacks(Proxy, "DescendantChange", Key, Value)
		end
	elseif not Params.IsServer or type(Value) == "table" or Module._ntvst then
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

		if not Params.IsServer then
			FireProxyCallbacks(new, "Set")
			FireProxyCallbacks(Proxy, "DescendantChange", Key, Value)
		end
	end

	if Callback and Params.TempDisableSetCallback < 1 then
		Callback(Proxy, Key, Value)
	end
end

function MT.__index(Proxy, Key)
	local Children = rawget(Proxy, CHILDREN_KEY)
	local Child = Children and Children[Key]
	if Child then
		return Child
	end

	local Params: Params = rawget(Proxy, PARAMS_KEY)
	local IndexMethods = Params.IndexMethods
	local Method = IndexMethods and IndexMethods[Key]
	if Method ~= nil then
		return Method
	end

	local OriginalValue = rawget(Proxy, ORIG_KEY)
	local OrigAtKey = type(OriginalValue) == "table" and OriginalValue[Key] or nil

	if not Params.IsServer or type(OrigAtKey) == "table" or Module._ntvst then
		Params.TempDisableSetCallback += 1
		Set(Proxy, Key, OrigAtKey)
		Params.TempDisableSetCallback -= 1

		return rawget(Proxy, CHILDREN_KEY)[Key]
	end

	return OrigAtKey
end
function MT.__newindex(Proxy, Key, Value)
	Set(Proxy, Key, Value)
end
function MT.__call(Proxy, ...)
	local Params: Params = rawget(Proxy, PARAMS_KEY)
	return Params.CallFunction(Proxy, ...)
end
function MT.__len(Proxy)
	return #Module.GetValue(Proxy)
end

function Module.new<T>(OriginalValue: T, Params: Params, InternalCall: boolean?): T
	Params.TempDisableSetCallback = Params.TempDisableSetCallback or 0
	local Proxy = {
		[PARAMS_KEY] = Params,
		[ORIG_KEY] = OriginalValue,
	}

	if not InternalCall then
		setmetatable(Proxy, MT)
	end

	return Proxy
end

function Module.TracePath(Proxy)
	local Path = {}

	local Pointer = Proxy
	while Pointer do
		local Parent = rawget(Pointer, PARENT_KEY)
		if not Parent then
			break
		end
		table.insert(Path, 1, rawget(Pointer, INDEX_KEY))
		Pointer = Parent
	end
	return Path
end

function Module.Connect(Proxy, Callback: (Action: string, ...any) -> ())
	local Callbacks = rawget(Proxy, CALLBACKS_KEY)
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

function Module.IsProxy(Proxy)
	return type(Proxy) == "table" and rawget(Proxy, PARAMS_KEY)
end

function Module.GetValue(Proxy): {}
	return Module.IsProxy(Proxy) and rawget(Proxy, ORIG_KEY)
end
-- function Module.SetValue(Proxy, Value)
-- 	local Parent = rawget(Proxy, PARENT_KEY)
-- 	if Parent then
-- 		local Orig = Parent[ORIG_KEY]
-- 		Orig[rawget(Proxy, INDEX_KEY)] = Value
-- 	end

-- 	rawset(Proxy, ORIG_KEY, Value)
-- end
-- function Module.GetParent(Proxy)
-- return rawget(Proxy, PARENT_KEY)
-- end
function Module.GetIdentifier(Proxy)
	local Params: Params = Module.IsProxy(Proxy)
	return Params and Params.Identifier
end
-- function Module.GetKey(Proxy)
-- 	return rawget(Proxy, INDEX_KEY)
-- end
-- function Module.ToggleSetCallback(Proxy, Increment: boolean?)
-- 	local Params: Params = Module.IsProxy(Proxy)
-- 	Params.TempDisableSetCallback += Increment and 1 or -1
-- end

function Module.Insert(Proxy, Value, Index)
	local len = #Proxy

	for i = len, Index, -1 do
		local Next = Proxy[i]
		Proxy[i + 1] = Module.GetValue(Next) or Next
	end
	Proxy[Index] = Value

	FireProxyCallbacks(Proxy, "Insert", Value, Index)
end
function Module.Remove(Proxy, Index)
	local Value = Proxy[Index]
	local len = #Proxy

	for i = Index, len - 1 do
		local Next = Proxy[i + 1]
		Proxy[i] = Module.GetValue(Next) or Next
	end
	Proxy[len] = nil

	FireProxyCallbacks(Proxy, "Remove", Value, Index)

	return Value
end

return Module
