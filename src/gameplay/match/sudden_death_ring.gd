class_name SuddenDeathRing
extends RefCounted
## Client-side model of the Sudden Death ring (W16-SDWATER; match-flow-and-map.md
## §3.1, Canon C10). Pure logic, no nodes: the ring wall, minimap, "outside"
## warning and damage-direction hook all read this one object.
##
## The server enforces the ring (ServerWorld._step_sudden_death). This model
## recomputes the SAME radius from the replicated clock through the shared
## statics MatchRules.ring_radius / sudden_death_elapsed / outside_ring, so the
## two sides cannot drift and the wire protocol is unchanged.

var rules: MatchRulesDef
## Ring centre = MapDef.mid_plaza_center (what the server uses).
var centre: Vector3 = Vector3.ZERO
var active: bool = false
## Seconds into Sudden Death (clock-scaled), from the last snapshot.
var elapsed_s: float = 0.0


func _init(rules_: MatchRulesDef = null, centre_: Vector3 = Vector3.ZERO) -> void:
	rules = rules_ if rules_ != null else MatchRulesDef.new()
	centre = centre_


## Feed the replicated match state (null = no match info: ring off).
func apply(ms: SnapshotData.MatchState) -> void:
	active = ms != null and ms.phase == MatchRules.Phase.SUDDEN_DEATH
	elapsed_s = MatchRules.sudden_death_elapsed(rules, ms.time_s, ms.next_phase_s) if active else 0.0


func radius() -> float:
	return MatchRules.ring_radius(rules, elapsed_s)


func is_outside(pos: Vector3) -> bool:
	return active and MatchRules.outside_ring(centre, radius(), pos)


## The point the damage-direction indicator should face while the player takes
## ring damage: the ring centre at the player's height, or null when not outside.
func safe_point(pos: Vector3) -> Variant:
	if not is_outside(pos):
		return null
	return Vector3(centre.x, pos.y, centre.z)
