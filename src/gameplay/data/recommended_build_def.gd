class_name RecommendedBuildDef
extends Resource
## One recommended Armory build for a hero (the "recommended" tag of
## design/ux/hud.md §10 / §16 cognitive accessibility): an ordered shopping
## list. Step i means "own item item_ids[i] at tier / count targets[i]":
## MOUNT lines the tier to reach, SQUAD upgrades 1, CONSUMABLE the Med-Packs to
## carry. The shop highlights the first step not yet satisfied.
##
## Two modes, chosen by the data:
## - Simple (nodes empty): the ordered list above, exactly as before.
## - Guide (nodes set): a branching graph of BuildNodeDef (sections, priorities,
##   prerequisites, alternatives, situational conditions) read by BuildAdvisor.
##   item_ids / targets may still hold a plain fallback list for old readers.

## HeroDef.id this build is for.
@export var hero_id: StringName = &""
@export var display_name: String = ""
## ArmoryItemDef ids in buy order.
@export var item_ids: PackedStringArray = PackedStringArray()
## Target tier (mounts) or count (consumables) per step; same length as item_ids.
@export var targets: PackedInt32Array = PackedInt32Array()

@export_group("Guide")
## Branching guide nodes (empty = simple mode).
@export var nodes: Array[BuildNodeDef] = []
## Match modes this build is for (&"5v5", &"3v3", &"custom", &"bots"); empty = all.
@export var modes: PackedStringArray = PackedStringArray()
## Role ids this build plays (HeroDef.roles vocabulary).
@export var roles: PackedStringArray = PackedStringArray()
## Short localization key for the build's one-line summary.
@export var summary_key: String = ""
## Safe default for new players (shown first).
@export var beginner: bool = true


func steps() -> int:
	return mini(item_ids.size(), targets.size())


func item_at(step: int) -> StringName:
	return StringName(item_ids[step])


func target_at(step: int) -> int:
	return maxi(1, targets[step])


## True when this build uses the branching guide.
func is_guide() -> bool:
	return not nodes.is_empty()


## True when this build may be used in `mode` (empty modes = every mode).
func allows_mode(mode: StringName) -> bool:
	return modes.is_empty() or mode == &"" or modes.has(String(mode))


## Guide node with `node_id`, or null.
func node(node_id: StringName) -> BuildNodeDef:
	for n in nodes:
		if n != null and n.id == node_id:
			return n
	return null
