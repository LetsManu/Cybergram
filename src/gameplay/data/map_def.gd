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
## Wading zones (W16-SDWATER): dock water slows 15%. Read by the shared hero
## motor (server + prediction) and Wardling movement.
@export var water_zones: Array[WaterZoneDef] = []
## W18-GEO: background-life mount points and routes (null = none).
@export var ambient_anchors: AmbientAnchorsDef
## W18-GEO: between-lane jungle. Centrelines of its walkable routes (minimap,
## overview, tests) and its pockets (future neutral camp sites).
@export var jungle_paths: Array[PackedVector3Array] = []
@export var jungle_pockets: Array[JunglePocketDef] = []
## Navigation layer bit of the jungle region. Wardlings query layer 1 only, so
## they never path through it; heroes / bots query every layer.
const JUNGLE_NAV_LAYER: int = 2
## Match rules this map plays under (format, clock, Uplink). Null = the
## session default. Canon C1: the full map is 5v5, the 1-lane slice 3v3.
@export var match_rules: MatchRulesDef
## Wardling rules for this map (null = the session default).
@export var wardling_rules: Resource


## Strongest water speed factor at `pos` (1.0 = dry).
func water_factor_at(pos: Vector3) -> float:
	return WaterZoneDef.factor_at(water_zones, pos)


func hq(team: int) -> HqDef:
	for h in hqs:
		if h.team == team:
			return h
	return null


## Hardpoint by its map-wide index (lane-major: lane 0's, then lane 1's ...;
## the snapshot / ObjectiveSystem.all order). Null if out of range.
func hardpoint_global(index: int) -> HardpointDef:
	var i := index
	for lane in lanes:
		if i < 0:
			return null
		if i < lane.hardpoints.size():
			return lane.hardpoints[i]
		i -= lane.hardpoints.size()
	return null


## Vector2i(lane, index in lane) of a map-wide hardpoint index, or (-1, -1).
func lane_slot(index: int) -> Vector2i:
	var i := index
	for li in lanes.size():
		if i < 0:
			break
		if i < lanes[li].hardpoints.size():
			return Vector2i(li, i)
		i -= lanes[li].hardpoints.size()
	return Vector2i(-1, -1)


## Index of the lane that holds hardpoint `hp_id`, or -1.
func lane_of(hp_id: StringName) -> int:
	for i in lanes.size():
		if lanes[i].hardpoint(hp_id) != null:
			return i
	return -1


## Lane index whose centreline (its hardpoints' mean lateral X) is nearest `pos`.
func nearest_lane(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in lanes.size():
		var hps := lanes[i].hardpoints
		if hps.is_empty():
			continue
		var x := 0.0
		for h in hps:
			x += h.position.x
		x /= float(hps.size())
		var d := absf(pos.x - x)
		if d < best_d:
			best_d = d
			best = i
	return best
