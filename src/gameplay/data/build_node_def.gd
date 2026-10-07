class_name BuildNodeDef
extends Resource
## One step of a branching build guide (RecommendedBuildDef.nodes). A node is
## "own item_id at tier / count `target`"; it opens once every node in
## `requires` is done (or skipped), and BuildAdvisor scores the open nodes by
## `priority` plus the bonuses of matched `conditions` (AdviceRuleDef ids).
## A node also counts as done when the player owns one of its `alternatives`,
## so a guide never breaks when the player picks another valid item.
## See docs/armory.md "Adding a recommendation" for examples.

## Guide section, shown as the group heading in the Recommended tab.
enum Section { OPENING, EARLY, SPIKE, CORE, SQUAD, CONSUMABLE, DEFENSIVE, OFFENSIVE, UTILITY, COUNTER, LATE }

## Unique within the build (other nodes name it in `requires`).
@export var id: StringName = &""
## ArmoryItemDef id.
@export var item_id: StringName = &""
## Tier (mount lines) or count (consumables); 1 for squad upgrades.
@export_range(1, 99) var target: int = 1
@export var section: Section = Section.CORE
## Higher = sooner. Ties keep data order.
@export_range(0, 1000) var priority: int = 100
## Node ids that must be done (or skipped) first.
@export var requires: PackedStringArray = PackedStringArray()
## Item ids that satisfy this node instead (same target rules).
@export var alternatives: PackedStringArray = PackedStringArray()
## AdviceRuleDef ids. Empty = always eligible. Situational nodes (any
## condition set) are only offered while at least one condition matches.
@export var conditions: PackedStringArray = PackedStringArray()
## Localization key of the "why" line (falls back to the item's explain_key).
@export var reason_key: String = ""
## Part of the core path (counts toward build progress).
@export var core: bool = true
## Nice to have: never blocks later nodes.
@export var optional: bool = false
## Offered only when the preferred item of an earlier node cannot be bought
## by this hero (wrong family or disabled).
@export var fallback: bool = false
## Later nodes treat this one as done once it is no longer offered
## (outside its time window or its conditions stopped matching).
@export var skippable: bool = false
## Match-time window in seconds (max 0 = no end).
@export_range(0, 7200) var min_s: int = 0
@export_range(0, 7200) var max_s: int = 0
## For expert view only: shown when "expert detail" is on.
@export var expert: bool = false


func target_or_one() -> int:
	return maxi(1, target)


## True when `t_s` (match seconds) is inside this node's window.
func in_window(t_s: float) -> bool:
	return t_s >= min_s and (max_s <= 0 or t_s <= max_s)
