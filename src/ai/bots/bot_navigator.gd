class_name BotNavigator
extends RefCounted
## Path following on the server world's navmesh (architecture.md §9 Navigator):
## NavigationServer3D.map_get_path on goal change or at most once a second,
## waypoint advance by distance, and stuck recovery (jump + side-step + repath).

const WAYPOINT_REACH_M: float = 1.0
const GOAL_MOVED_M: float = 3.0
const STUCK_WINDOW_S: float = 1.0
const STUCK_MIN_M: float = 0.6
const UNSTICK_S: float = 0.6
## Nav layers bots path on: the lanes (1) plus the between-lane jungle (W18-GEO).
## The jungle region and its entrance links sit on MapDef.JUNGLE_NAV_LAYER only,
## so Wardling paths (layer 1) never enter it while bots take it when shorter.
const NAV_LAYERS: int = 1 | MapDef.JUNGLE_NAV_LAYER

var nav_map: RID
var tick_hz: int = 30
var path: PackedVector3Array = PackedVector3Array()
var index: int = 0
var goal: Vector3 = Vector3.INF
var queries: int = 0
## While > tick: side-step `unstick_side` and jump (stuck recovery).
var unstick_until: int = -1
var unstick_side: float = 1.0

var _repath_tick: int = 0
var _check_tick: int = 0
var _check_pos: Vector3 = Vector3.INF


func _init(map: RID, hz: int) -> void:
	nav_map = map
	tick_hz = hz


## Sets the destination; repaths when it moved or the path is stale.
func set_goal(g: Vector3, from: Vector3, tick: int) -> void:
	var moved := goal == Vector3.INF or BotBlackboard.flat_dist(g, goal) > GOAL_MOVED_M
	if not moved and tick < _repath_tick and not path.is_empty():
		return
	goal = g
	_repath(from, tick)


## Flat unit direction toward the next waypoint (ZERO when there is no path).
func direction(pos: Vector3) -> Vector3:
	while index < path.size() - 1 and BotBlackboard.flat_dist(path[index], pos) < WAYPOINT_REACH_M:
		index += 1
	if index >= path.size():
		return Vector3.ZERO
	var to := path[index] - pos
	to.y = 0.0
	return to.normalized() if to.length_squared() > 1e-4 else Vector3.ZERO


## Stuck check while trying to move; returns true when recovery just started.
func check_stuck(pos: Vector3, tick: int, wants_move: bool, rng: RandomNumberGenerator) -> bool:
	if tick < _check_tick:
		return false
	_check_tick = tick + roundi(STUCK_WINDOW_S * tick_hz)
	var stuck := wants_move and _check_pos != Vector3.INF and BotBlackboard.flat_dist(pos, _check_pos) < STUCK_MIN_M
	_check_pos = pos
	if stuck:
		unstick_until = tick + roundi(UNSTICK_S * tick_hz)
		unstick_side = -1.0 if rng.randf() < 0.5 else 1.0
		_repath_tick = 0
	return stuck


## Tick of the next stuck check (callers skip check_stuck before it: E14 bot cost).
func next_check_tick() -> int:
	return _check_tick


func unsticking(tick: int) -> bool:
	return tick < unstick_until


func clear() -> void:
	path = PackedVector3Array()
	index = 0
	goal = Vector3.INF


func _repath(from: Vector3, tick: int) -> void:
	_repath_tick = tick + tick_hz
	if not nav_map.is_valid() or NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		path = PackedVector3Array()
		return
	path = NavigationServer3D.map_get_path(nav_map, from, goal, true, NAV_LAYERS)
	queries += 1
	index = 1 if path.size() > 1 else 0
