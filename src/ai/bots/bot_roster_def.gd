class_name BotRosterDef
extends Resource
## Which heroes bots take when they fill a match (heroes.md §11: the slice has
## Vesper Loom and Brannoc, duplicates allowed). Slot k of a team takes
## heroes[k % size]; the human player's slot is skipped, never replaced.
## Profiles per difficulty live in `profiles` (key: difficulty id).

@export var heroes: Array[Resource] = []
## Difficulty id -> BotProfile resource.
@export var profiles: Dictionary = {}
@export var default_difficulty: StringName = &"normal"
## HeroDef.id -> PackedInt32Array of skill slots in learning order (E15
## points; 3 = ultimate, learned as soon as its level allows).
@export var build_orders: Dictionary = {}
## W10-T1: HeroDef.id -> PackedInt32Array(basic slot 0..2) of Fork choices
## (1 = Fork A, 2 = Fork B) the bots buy when the Fork point comes up.
@export var fork_prefs: Dictionary = {}
## Fallback heroes per team when no MatchRulesDef is set; the match format
## itself is data on MatchRulesDef.team_size (Canon C1 5v5, slice 3v3).
@export_range(1, 5) var team_size: int = 5


func profile(difficulty: String) -> BotProfile:
	var p := profiles.get(StringName(difficulty)) as BotProfile
	if p == null:
		p = profiles.get(default_difficulty) as BotProfile
	return p if p != null else BotProfile.new()


func hero_for(slot: int) -> HeroDef:
	if heroes.is_empty():
		return null
	return heroes[slot % heroes.size()] as HeroDef


func build_order_for(hero: HeroDef) -> PackedInt32Array:
	if hero != null and build_orders.has(hero.id):
		return PackedInt32Array(build_orders[hero.id])
	return PackedInt32Array([3, 0, 1, 2, 0, 1, 2])


## Fork choice (1 = A, 2 = B) per basic slot for `hero` (default: Fork A).
func fork_prefs_for(hero: HeroDef) -> PackedInt32Array:
	if hero != null and fork_prefs.has(hero.id):
		return PackedInt32Array(fork_prefs[hero.id])
	return PackedInt32Array([1, 1, 1])
