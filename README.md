# Replicador
Advanced yet simple to use library for server authoritative to reactive-client replication.

Module constructs auto replication, types and methods on paths of any depth.

Has proper tag/identifier management, replication settings, parent-child hierarchy and tagged groups.

Wally link: [here](https://wally.run/package/thehehfocus/replicador) <br>
Docs: soon, maybe?


## Example use
- (using special singleton function, ensures there's only one object target, handles wait for player loading)

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

local Object = Replicador.Singleton("Test", Data, Player) -- Player argument - overload and get ServerClass.

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

local Object = Replicador.Singleton("Test", Data) -- ClientClass with DataTemplate

Object.Data.Slots:OnKeySet(function(Value, Action, Path) -- Runs when a child of the table changed value.
	print(`Made a change at path: {Path}, with action: {Action}, and value: {Value}`)
end)

Object.Data.Equipment.Head:OnChange(function(Value, OldValue) -- Runs when value at the path changes.
	print(`Set head equipment from {OldValue} to {Value}`)
end)

Object.Data.Slots:OnInsert(function(Value, Index) -- Runs whenever an insertion method is called on the table.
	print(`Inserted a slot {Value} at {Index}`)
end)

local Name = Object.Data.Slots[1].Name -- We can cache the path proxies, even if they dont have a value yet.
Name:OnChange(function(Value, OldValue)
	print(Value, OldValue)
end)
```
