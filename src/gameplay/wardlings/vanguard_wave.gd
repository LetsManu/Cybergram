class_name VanguardWave
extends RefCounted
## One ownerless Vanguard wave in a lane (Canon C15, wardlings-and-economy.md
## §10). Members plus the blackboard the WaveBrain (src/ai) plans once per wave.

var id: int = 0
var team: int = 0
var lane: int = 0
var members: Array[WardlingSim] = []
var spawned_tick: int = 0

## AI blackboard (written by WaveBrain at 2 Hz).
## Front hardpoint index in the lane (-1 = not planned yet).
var target_index: int = -1
var target_point: Vector3 = Vector3.ZERO
var target_radius: float = 12.0
## Shared march path (one query per wave).
var path: PackedVector3Array = PackedVector3Array()
var threat_id: int = 0
## E10 command_vanguard (Vesper): forced threat until this tick (-1 = none).
var forced_threat_id: int = 0
var forced_until_tick: int = -1
## Path re-plans (diagnostics / tests).
var plans: int = 0


func _init(id_: int, team_: int, lane_: int, tick: int) -> void:
	id = id_
	team = team_
	lane = lane_
	spawned_tick = tick


func alive_count() -> int:
	return members.size()
