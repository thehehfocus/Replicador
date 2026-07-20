--!strict

local Lib = require(".")
local Player = Instance.new("Player")

local Data = {
	Cash = 0,
	Items = {} :: {string},
	Structure = {
		abc = 5,
		cba = true,
	}
}

--// Server
local ServerObject = Lib.Singleton("Test", Data, Player)
if not ServerObject then
	return
end

ServerObject.Data.Cash = 100
ServerObject.Data.Structure.cba = false
ServerObject.Data.Items:Insert("Hello!")

--// Client
local ClientObject = Lib.Singleton("Test", Data)
ClientObject.Data.Cash:OnSet(function(Value, OldValue)
	print(Value, OldValue)
end)

ClientObject.Data.Items:OnInsert(function(Value, Index)
	print(Value, Index)
end)

ClientObject.Data.Structure.abc:OnSet(function(Value, OldValue)
	print(Value, OldValue)
end)
