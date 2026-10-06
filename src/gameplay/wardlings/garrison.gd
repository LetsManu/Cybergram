class_name Garrison
extends RefCounted
## The Sentinels of one held hardpoint (C5; wardlings-and-economy.md §11).
## Owned by WardlingWorld; the blackboard the Wardling brains read.

var hp: HardpointSim
## The team these Sentinels belong to (the hardpoint owner when they settled).
var team: int = MapDef.TEAM_NEUTRAL
## Stand points (HardpointDef.garrison_points, at most sentinels_per_hardpoint).
var posts: PackedVector3Array = PackedVector3Array()
## Living Sentinel per post (null = empty).
var members: Array = []
## Tick each empty post may mint again.
var due_tick: PackedInt64Array = PackedInt64Array()
## Picked by WardlingWorld at garrison_think_interval_ticks: the enemy to shoot (0 = none).
var threat_id: int = 0
## Dissolving (the hardpoint flipped): members despawn at this tick (-1 = no).
var dissolve_tick: int = -1


func _init(hp_: HardpointSim, team_: int, posts_: PackedVector3Array, first_tick: int) -> void:
	hp = hp_
	team = team_
	posts = posts_
	members.resize(posts.size())
	due_tick.resize(posts.size())
	due_tick.fill(first_tick)


## Zone centre (the brains' leash anchor).
func centre() -> Vector3:
	return hp.def.position


func zone_radius() -> float:
	return hp.def.zone_radius


func alive_count() -> int:
	var n := 0
	for m in members:
		if m != null:
			n += 1
	return n


func slot_of(w: WardlingSim) -> int:
	return members.find(w)
