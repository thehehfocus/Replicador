# Replicador
Advanced library for server authoritative to reactive-client replication.

Abandons the idea of string paths, provides really comfortable API with full intellisense. As well as being rather lightweight. 

Module constructs auto replication, types and methods on paths of any depth.

Has proper tag/identifier management, replication settings, parent-child hierarchy and tagged groups.

Wally link: [here](https://wally.run/package/thehehfocus/replicador)
Docs: soon, maybe?


## Example use
Server:
```luau
local Replicador = require(game.ReplicatedStorage.Replicador)
local Data = { -- Define data type, anything replicatable
	EquippedSlot = nil :: number?,
	Slots = {} :: {string},
	Equipment = {
		Head = nil :: string?,
		Body = nil :: string?,
		Legs = nil :: string?
	},
}

local Object = Replicador.Server.Register({ -- Register the object, set Data, Identifier, Tags.
	Identifier = "Test", 
	Data = Data, 
})

local Success = Replicador.Server.WaitForReadyPlayer(Plr) -- Error handling.
if Success then
	Object:Subscribe(Plr)
end

-- Simple set!
-- No manual path typing + Autocompletion and Intellisense.
Object.Data.EquippedSlot = 1
Object.Data.Equipment.Head = "Helmet"
Object.Data.Slots:Insert({Name = "Potion"}, 1)

task.wait(3)

Object.Data.Slots[1] = {
	Name = "PotionOverride"
}
```

Client:
```luau
local Replicador = require(game.ReplicatedStorage.Replicador)

local Data = {
	EquippedSlot = nil :: number?,
	Slots = {} :: {string},
	Equipment = {
		Head = nil :: string?,
		Body = nil :: string?,
		Legs = nil :: string?
	},
}

local Object = Replicador.Client.AwaitFor("Test", Data)

Object.Data.Slots:OnDescendantChange(function(Value, Action, Path) -- Runs when an action target is a descendant or equal to path.
	print(`Made a change at path: {Path}, with action: {Action}, and value: {Value}`)
end)

Object.Data.EquippedSlot:OnSet(function(Value, OldValue) -- Runs when the value is explicitly set.
	print(`Equipped slot {Value}`)
end)

Object.Data.Equipment.Head:OnValueChange(function(Value, OldValue) -- Runs when value at the path changes.
	print(`Set head equipment from {OldValue} to {Value}`)
end)

Object.Data.Slots:OnInsert(function(Value, Index) -- Runs whenever an insertion method is called on the table.
	print(`Inserted a slot {Value} at {Index}`)
end)

local Name = Object.Data.Slots[1].Name -- We can cache the path proxies, even if they dont have a value yet.
Name:OnValueChange(function(Value, OldValue)
	print(Value, OldValue)
end)
```

## Or using special singleton function (ensures there's only one object target):
Server
```luau
local Object = Replicador.Singleton("Test", Data, Plr) -- Plr argument - overload and get ServerClass.
if not Object then
	return
end
```

Client
```luau
local Object = Replicador.Singleton("Test", Data) -- ClientClass with DataTemplate
```
