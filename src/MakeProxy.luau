local Module = {}

local PARENT_KEY = "◘p"
local INDEX_KEY = "◘i"
local CHILDREN_KEY = "◘c"
local PARAMS_KEY = "◘pr"
local ORIG_KEY = "◘o"

type Params = {
	SetCallback: ({}, string | number, any | {}) -> (),
	IndexMethods: {}?,
	CallFunction: (...any) -> (),
	Identifier: any,
	IgnoreNonTableValues: boolean?,
}

local TempDisableCallback = 0

local function Set(Proxy, Key, Value)
	local ProxyMT = getmetatable(Proxy)
	local Params: Params = ProxyMT[PARAMS_KEY]
	local Callback = Params.SetCallback

	local Children = ProxyMT[CHILDREN_KEY]

	-- Assign the value to the actual table
	local OriginalValue = ProxyMT[ORIG_KEY]
	if type(OriginalValue) == "table" then
		OriginalValue[Key] = Value
	end

	local Child = Children and Children[Key]
	if Child then
		local ChildMT = getmetatable(Child)
		ChildMT[ORIG_KEY] = Value
		ChildMT[CHILDREN_KEY] = nil
		return Callback and TempDisableCallback < 1 and Callback(Proxy, Key, Value) 
	end

	if not Params.IgnoreNonTableValues or type(Value) == "table" then
		-- Make value a proxy.
		local new = Module.new(Value, Params)

		if not Children then
			Children = {}
			ProxyMT[CHILDREN_KEY] = Children
		end
		Children[Key] = new

		-- Assign info the new proxies' data
		local NewMT = getmetatable(new)
		NewMT[PARENT_KEY] = Proxy
		NewMT[INDEX_KEY] = Key
	end

	return Callback and TempDisableCallback < 1 and Callback(Proxy, Key, Value) 
end

local function __len(Proxy)
	return #Module.GetValue(Proxy)
end
local function __tostring(Proxy)
	return "(Proxy object)"
end
local function __iter(Proxy)
	return pairs(Module.GetValue())
end

function Module.new<T>(
	OriginalValue: T,
	Params: {
		SetCallback: ({}, string | number, any | {}) -> ()?,
		IndexMethods: {}?,
		CallFunction: (...any) -> ()?,
		Identifier: any,
		IgnoreNonTableValues: boolean?,
	}
): T
	local Proxy = {}

	local Metatable = {}
	Metatable[PARAMS_KEY] = Params
	Metatable[ORIG_KEY] = OriginalValue

	--// Children table for namespace safety. Created only on need in Set function.
	--local Children = {}
	--Metatable[CHILDREN_KEY] = Children

	local IndexMethods = Params.IndexMethods

	Metatable.__index = function(_, Key)
		local Children = Metatable[CHILDREN_KEY]
		local OriginalValue = Metatable[ORIG_KEY]
		local Child = Children and Children[Key]
		if Child then
			return Child
		end

		local Method = IndexMethods and IndexMethods[Key]
		if Method ~= nil then
			return Method
		end

		local OrigAtKey = type(OriginalValue) == "table" and OriginalValue[Key] or nil
		if not Params.IgnoreNonTableValues or type(OrigAtKey) == "table" then
			TempDisableCallback += 1
			Set(Proxy, Key, OrigAtKey)
			TempDisableCallback -= 1
			return Metatable[CHILDREN_KEY][Key]
		end

		return OrigAtKey
	end
	Metatable.__newindex = function(_, Key, Value)
		Set(Proxy, Key, Value)
	end
	Metatable.__call = Params.CallFunction
	Metatable.__len = __len
	Metatable.__tostring = __tostring
	Metatable.__iter = __iter

	setmetatable(Proxy, Metatable)

	return Proxy
end

function Module.TracePath(Proxy)
	local Path = {}

	local Pointer = getmetatable(Proxy)
	while Pointer do
		local Parent = Pointer[PARENT_KEY]
		if not Parent then
			break
		end
		table.insert(Path, 1, Pointer[INDEX_KEY])
		Pointer = getmetatable(Parent)
	end
	return Path
end

function Module.IsProxy(Proxy)
	local Mt = type(Proxy) == "table" and getmetatable(Proxy)

	if Mt and Mt[PARAMS_KEY] then
		return Mt
	end
	return nil
end

function Module.GetValue(Proxy): {}
	local mt = Module.IsProxy(Proxy)
	return mt and mt[ORIG_KEY]
end
function Module.SetValue(Proxy, Value)
	local mt = Module.IsProxy(Proxy)
	if not mt then
		return
	end

	local Parent = mt[PARENT_KEY]
	if Parent then
		local Orig = Parent[ORIG_KEY]
		Orig[mt[INDEX_KEY]] = Value
	end

	mt[ORIG_KEY] = Value
end
function Module.GetParent(Proxy)
	local mt = Module.IsProxy(Proxy)
	return mt and mt[PARENT_KEY]
end
function Module.GetIdentifier(Proxy)
	local mt = Module.IsProxy(Proxy)
	return mt and (mt[PARAMS_KEY] :: Params).Identifier
end

function Module.Insert(Proxy, Value, Index)
	local mt = Module.IsProxy(Proxy)
	assert(mt)

	local len = #Proxy
	if (Index > len + 1) or (Index < 1) then
		Proxy[Index] = Value
		return
	end

	for i = len, Index, -1 do
		local Next = Proxy[i]
		Proxy[i + 1] = Module.GetValue(Next) or Next
	end
	Proxy[Index] = Value
end
function Module.Remove(Proxy, Index)
	local mt = Module.IsProxy(Proxy)
	assert(mt)

	local Value = Proxy[Index]

	local len = #Proxy

	for i = Index, len - 1 do
		local Next = Proxy[i + 1]
		Proxy[i] = Module.GetValue(Next) or Next
	end
	Proxy[len] = nil

	return Value
end

return Module
