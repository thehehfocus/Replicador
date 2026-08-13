--!optimize 2
local Module = {}

local PARENT_KEY = "◘p"
local INDEX_KEY = "◘i"
local CHILDREN_KEY = "◘c"
local PARAMS_KEY = "◘pr"
local ORIG_KEY = "◘o"
local CALLBACKS_KEY = "◘ca"

type Params = {
	SetCallback: ({}, string | number, any | {}) -> (),
	IndexMethods: {}?,
	CallFunction: (...any) -> (),
	Identifier: any,
	IgnoreNonTableValues: boolean?,
}

local TempDisableSetCallback = 0
local TempDisableCallbacks = 0

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
	if TempDisableCallbacks > 0 then
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
	if type(OriginalValue) == "table" then
		OriginalValue[Key] = Value
	end

	local Child = Children and Children[Key]
	if Child then
		rawset(Child, ORIG_KEY, Value)
		local ChildChildren = rawget(Child, CHILDREN_KEY)

		if ChildChildren then
			if Params.IgnoreNonTableValues then
				TempDisableSetCallback += 1
			end

			for i,v in ChildChildren do
				Set(Child, i, Value and Value[i])
			end

			if Params.IgnoreNonTableValues then
				TempDisableSetCallback -= 1
			end
		end
		
		IterateProxy(Child, function(Proxy)
			FireProxyCallbacks(Proxy, "Set")
		end)
		FireProxyCallbacks(Proxy, "DescendantChange", Key, Value)
	elseif not Params.IgnoreNonTableValues or type(Value) == "table" then
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
		FireProxyCallbacks(Proxy, "DescendantChange", Key, Value)
	end

	return Callback and TempDisableSetCallback < 1 and Callback(Proxy, Key, Value) 
end

MT.__index = function(Proxy, Key)
	local Children = rawget(Proxy, CHILDREN_KEY)
	local OriginalValue = rawget(Proxy, ORIG_KEY)
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

	local OrigAtKey = type(OriginalValue) == "table" and OriginalValue[Key] or nil
	if not Params.IgnoreNonTableValues or type(OrigAtKey) == "table" then
		TempDisableSetCallback += 1
		Set(Proxy, Key, OrigAtKey)
		TempDisableSetCallback -= 1

		return rawget(Proxy, CHILDREN_KEY)[Key]
	end

	return OrigAtKey
end
MT.__newindex = function(Proxy, Key, Value)
	Set(Proxy, Key, Value)
end
MT.__call = function(Proxy, ...)
	local Params: Params = rawget(Proxy, PARAMS_KEY)
	return Params.CallFunction(Proxy, ...)
end
MT.__len = function(Proxy)
	return #Module.GetValue(Proxy)
end

function Module.new<T>(
	OriginalValue: T,
	Params: {
		SetCallback: ({}, string | number, any | {}) -> ()?,
		IndexMethods: {}?,
		CallFunction: (...any) -> ()?,
		Identifier: any,
		IgnoreNonTableValues: boolean?,
	},
	NMT: unknown?
): T
	local Proxy = {
		[PARAMS_KEY] = Params,
		[ORIG_KEY] = OriginalValue
	}

	if not NMT then
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
function Module.SetValue(Proxy, Value)
	local Parent = rawget(Proxy, PARENT_KEY)
	if Parent then
		local Orig = Parent[ORIG_KEY]
		Orig[rawget(Proxy, INDEX_KEY)] = Value
	end

	rawset(Proxy, ORIG_KEY, Value)
end
function Module.GetParent(Proxy)
	return Module.IsProxy(Proxy) and rawget(Proxy, PARENT_KEY)
end
function Module.GetIdentifier(Proxy)
	local Params: Params = Module.IsProxy(Proxy) and rawget(Proxy, PARAMS_KEY)
	return Params and Params.Identifier
end

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
