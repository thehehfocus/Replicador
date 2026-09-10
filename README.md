# Replicador
Simple to use library for server authoritative to reactive-client replication.

Module constructs auto replication, types and methods on paths of any depth.

Has proper tag/identifier management, replication settings.

Wally link: [here](https://wally.run/package/thehehfocus/replicador) <br>

## Example use
- (using special singleton function, ensures there's only one object target, handles wait for player loading, deepcopies datatemplate)

Server:
```luau
--!strict
local Replicador = require(game.ReplicatedStorage.Replicador)
Replicador.Singleton.init() -- single init function for client/server

local Data = { -- Define data type, anything replicatable
	EquippedSlot = nil :: number?,
	Slots = {} :: {{Name: string}},
	Equipment = {
		Head = nil :: string?,
		Body = nil :: string?,
		Legs = nil :: string?
	},
}

local Object = Replicador.Singleton.new("Test", Data, Player) -- Player argument - overload and get ServerClass.

-- Simple set!
-- +Intellisense.
Object.Data.EquippedSlot:Set(1)
Object.Data.Equipment.Head:Set("Helmet")
Object.Data.Slots:Insert({Name = "Potion"}, 1)

task.wait(3)

Object.Data.Slots[1]:Set({
	Name = "PotionOverride"
})
print(Object.Data.Slots:Get())
```

Client:
```luau
local Replicador = require(game.ReplicatedStorage.Replicador)
Replicador.Singleton.init()

local Data = { -- Define data type
	EquippedSlot = nil :: number?,
	Slots = {} :: {{Name: string}},
	Equipment = {
		Head = nil :: string?,
		Body = nil :: string?,
		Legs = nil :: string?
	},
}

local Object = Replicador.Singleton.new("Test", Data) -- ClientClass with DataTemplate

Object.SignalChanged:Connect(function(Path, Value, Action) -- Runs on any Data action.
	print(`Made a change at path: {Path}, with action: {Action}, and value: {Value}`)
end)

Object.Data.Equipment:OnKeyChange(function(Key, Value, OldValue) -- Runs when child of the table changes value.
	print(`Equipment {Key} changed from {OldValue} to {Value}`)
end)

Object.Data.Equipment.Head:OnChange(function(Value, OldValue) -- Runs when value at the path changes.
	print(`Set head equipment from {OldValue} to {Value}`)
end)

Object.Data.Slots:OnInsert(function(Value, Index) -- Runs whenever an insertion method is called on the table.
	print(`Inserted a slot {Value} at {Index}`)
end)

local Name = Object.Data.Slots[1].Name -- We can cache the path proxies, even if they dont have a value yet. 
Name:OnChange(function(Value, OldValue)
	print(`First slot's name changed from {OldValue}, to {Value}`)
end)
```
