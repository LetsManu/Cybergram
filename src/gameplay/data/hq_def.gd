class_name HqDef
extends Resource
## One team HQ compound (match-flow-and-map.md §3.2 Geometry rules, Canon C6/C7).

## MapDef.TEAM_CONCORD or MapDef.TEAM_SYNDICATE.
@export var team: int = 0
## Sanctum centre and its no-entry / heal radius (C6).
@export var sanctum: Vector3
@export var sanctum_radius: float = 10.0
## Mana Uplink core position (floor level).
@export var uplink: Vector3
## Shop / squad building anchors (front pad positions).
@export var foundry: Vector3
@export var armory: Vector3
## Centre of the lane gate opening (the Center lane's on the 3-lane map).
@export var lane_gate: Vector3
## One gate per lane, indexed like MapDef.lanes (empty = every lane uses
## lane_gate, the 1-lane slice). Vanguard waves of lane i spawn here (§3.8).
@export var lane_gates: PackedVector3Array = PackedVector3Array()
## Hero spawn points inside the Sanctum (floor level).
@export var spawn_points: PackedVector3Array = PackedVector3Array()
## Facing for spawned heroes (degrees, 0 = -Z, same convention as InputCommand yaw).
@export var spawn_yaw_deg: float = 0.0


## The gate Vanguard waves and Cells for `lane` start from.
func gate_for_lane(lane: int) -> Vector3:
	return lane_gates[lane] if lane >= 0 and lane < lane_gates.size() else lane_gate
