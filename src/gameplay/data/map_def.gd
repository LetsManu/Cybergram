class_name MapDef
extends Resource
## Map layout as data (architecture.md §6 "MapDef: lanes -> ordered HardpointDefs,
## HQ spawn data"). E7 (hardpoints), E8 (Wardlings) and E9 (match flow) read this
## instead of hard-coding positions. The scene holds the same points as anchor
## nodes; tests/unit/map keeps the two in sync.
##
## Axis convention: the lane runs along -Z. GDD lane distance x (Concord HQ back
## wall at x = 0) maps to z = -x; GDD "south" (the flank-loop side) is +X; y is up.

const TEAM_NEUTRAL: int = -1
const TEAM_CONCORD: int = 0
const TEAM_SYNDICATE: int = 1

@export var id: StringName
@export var display_name: String = ""
## The map scene (geometry, anchors, navigation region).
@export var scene: PackedScene
## Reference hero run speed used for the GDD run-times (§3.2: 6.0 m/s).
@export var reference_run_speed: float = 6.0
@export var lanes: Array[LaneDef] = []
## Indexed by team (0 = Concord, 1 = Syndicate).
@export var hqs: Array[HqDef] = []
@export var mid_plaza_center: Vector3
@export var mid_plaza_radius: float = 25.0
## Sudden Death spawn pads, indexed by team.
@export var sudden_death_spawns: PackedVector3Array = PackedVector3Array()


func hq(team: int) -> HqDef:
	for h in hqs:
		if h.team == team:
			return h
	return null
