class_name RecommendedBuildDef
extends Resource
## One recommended Armory build for a hero (the "recommended" tag of
## design/ux/hud.md §10 / §16 cognitive accessibility): an ordered shopping
## list. Step i means "own item item_ids[i] at tier / count targets[i]":
## MOUNT lines the tier to reach, SQUAD upgrades 1, CONSUMABLE the Med-Packs to
## carry. The shop highlights the first step not yet satisfied.

## HeroDef.id this build is for.
@export var hero_id: StringName = &""
@export var display_name: String = ""
## ArmoryItemDef ids in buy order.
@export var item_ids: PackedStringArray = PackedStringArray()
## Target tier (mounts) or count (consumables) per step; same length as item_ids.
@export var targets: PackedInt32Array = PackedInt32Array()


func steps() -> int:
	return mini(item_ids.size(), targets.size())


func item_at(step: int) -> StringName:
	return StringName(item_ids[step])


func target_at(step: int) -> int:
	return maxi(1, targets[step])
