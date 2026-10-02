class_name ArmoryCatalogDef
extends Resource
## The Armory catalog (slice subset: weapons-and-mods.md §3.10, wardlings §26).
## Item order is the wire index (InputCommand ACTION_BUY / ProgressState).

const DEFAULT_PATH := "res://assets/data/economy/armory_catalog_slice.tres"

@export var items: Array[ArmoryItemDef] = []


func index_of(id: StringName) -> int:
	for i in items.size():
		if items[i] != null and items[i].id == id:
			return i
	return -1


func find(id: StringName) -> ArmoryItemDef:
	var i := index_of(id)
	return items[i] if i >= 0 else null


func at(index: int) -> ArmoryItemDef:
	return items[index] if index >= 0 and index < items.size() else null
