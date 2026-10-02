class_name PresenceSource
extends RefCounted
## Something that counts toward Hold presence in a hardpoint zone
## (match-flow-and-map.md §3.4 / F1, Canon C4).
##
## The seam between objectives (E7) and anything that stands in a zone:
##   - heroes: ServerWorld wraps every hero itself (weight 1.0, uncapped);
##   - Wardlings (E8): register via ServerWorld.register_presence_source(src)
##     and unregister_presence_source(src) on despawn.
##
## Duck typing is accepted too: ObjectiveSystem reads only `team: int`,
## `presence_weight: float`, `global_position: Vector3`, `is_alive() -> bool`
## and, optionally, `is_hero: bool` (absent = false = AI). A Wardling node that
## carries those members can be registered directly; otherwise wrap it with
## PresenceSource.for_node(). AI presence (is_hero false) is capped per team per
## hardpoint (MatchRulesDef.ai_presence_cap, C4 = 3.0); hero presence is not.

const HERO_WEIGHT: float = 1.0
const WARDLING_WEIGHT: float = 0.5

## MapDef.TEAM_CONCORD (0) or MapDef.TEAM_SYNDICATE (1).
var team: int = 0
var presence_weight: float = WARDLING_WEIGHT
## True only for heroes: uncapped, and enables the heroless rule (K_hl).
var is_hero: bool = false
## Optional node whose global_position is tracked (freed node = not alive).
var node: Node3D
## Fixed position used when `node` is null.
var position: Vector3 = Vector3.ZERO
## Optional `func() -> bool`; when valid it decides is_alive().
var alive_check: Callable
## Optional net id of the entity (heroes: participant rewards on a flip).
var net_id: int = 0

var global_position: Vector3:
	get:
		return node.global_position if node != null and is_instance_valid(node) else position


func is_alive() -> bool:
	if node != null and not is_instance_valid(node):
		return false
	if alive_check.is_valid():
		return alive_check.call()
	return true


## A source that follows `n`. `alive` is an optional `func() -> bool`.
static func for_node(n: Node3D, team_: int, weight: float = WARDLING_WEIGHT,
		alive: Callable = Callable()) -> PresenceSource:
	var s := PresenceSource.new()
	s.node = n
	s.team = team_
	s.presence_weight = weight
	s.alive_check = alive
	return s


## A fixed-position source (tests, debug).
static func at(pos: Vector3, team_: int, weight: float = WARDLING_WEIGHT, hero: bool = false) -> PresenceSource:
	var s := PresenceSource.new()
	s.position = pos
	s.team = team_
	s.presence_weight = weight
	s.is_hero = hero
	return s
