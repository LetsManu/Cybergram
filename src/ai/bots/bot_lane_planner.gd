class_name BotLanePlanner
extends RefCounted
## W14 lane choice for bots on multi-lane maps (match-flow-and-map.md §3.2 3 lanes,
## §3.8 lane flow, §5 worked example: a 5-hero team opens 2/2/1 across N/C/S).
## One planner is shared by every bot of a match (BotDirector). Pure logic: the
## caller (BotBrain) measures each lane's need; the planner keeps the spread.
##
##   open:      bot k of a team takes OPEN_ORDER[k % 3] (Center, North, South, ...)
##   rebalance: every eval_interval_s per team, desired bots per lane =
##              team bots × need / Σ need; at most ONE bot moves per evaluation,
##              from the lane with the largest surplus to the one with the largest
##              deficit, and only if both exceed switch_margin (hysteresis).
##              Dead bots are preferred movers (they respawn anyway).
## The move itself is plain navigation: the shortest navmesh route between two
## lanes' Outer/Mid rows runs through the Undercroft flank tunnels, so a bot
## re-assigned mid-push flanks rather than walking back to the HQ. On Shardline
## Front (W18-GEO) the between-lane jungle is on the bots' nav layers too
## (BotNavigator.NAV_LAYERS), so an Inner/Outer re-assignment rotates through
## its alleys whenever that path is shorter; no planner logic is needed.

## Lane indices on a 3-lane map (MapDef order North, Center, South).
const OPEN_ORDER: Array[int] = [1, 0, 2]

var lane_count: int = 1
var eval_interval_s: float = 8.0
var switch_margin: float = 0.6

## hero net id -> lane index.
var assignment: Dictionary = {}
var _team_of: Dictionary = {}
var _opened: Dictionary = {}  # team -> bots opened so far
var _next_eval: Dictionary = {}  # team -> match seconds
## A bot that just changed lane stays at least this long (no ping-pong).
var min_stay_s: float = 20.0
var _moved_at: Dictionary = {}  # hero id -> match seconds of its last move


func _init(lanes: int = 1) -> void:
	lane_count = maxi(lanes, 1)


## Opening lane for the `rank`-th bot of a team.
static func open_lane(rank: int, lanes: int) -> int:
	if lanes <= 1:
		return 0
	if lanes == 3:
		return OPEN_ORDER[rank % 3]
	return rank % lanes


## The lane `hero_id` (of `team`) is assigned to; assigns its opening lane on first use.
func lane_of(hero_id: int, team: int) -> int:
	if lane_count <= 1:
		return 0
	if not assignment.has(hero_id):
		var r: int = _opened.get(team, 0)
		_opened[team] = r + 1
		assignment[hero_id] = open_lane(r, lane_count)
		_team_of[hero_id] = team
	return assignment[hero_id]


## Bots of `team` per lane.
func counts(team: int) -> PackedInt32Array:
	var c := PackedInt32Array()
	c.resize(lane_count)
	for id in assignment:
		if _team_of.get(id, -1) == team:
			c[assignment[id]] += 1
	return c


## True when `team` is due a rebalance at `now_s` (and books the next one).
func due(team: int, now_s: float) -> bool:
	if lane_count <= 1 or now_s < float(_next_eval.get(team, 0.0)):
		return false
	_next_eval[team] = now_s + eval_interval_s
	return true


## Desired bots per lane for `total` bots and per-lane `need` (all > 0).
static func desired(total: int, need: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(need.size())
	var sum := 0.0
	for n in need:
		sum += maxf(n, 0.0)
	for i in need.size():
		out[i] = float(total) * maxf(need[i], 0.0) / sum if sum > 0.0 else float(total) / need.size()
	return out


## One rebalance step for `team`. `need`: per-lane need (BotBrain.lane_need).
## `dead`: hero ids currently dead (preferred movers). Returns the moved hero id, or 0.
func rebalance(team: int, need: PackedFloat32Array, dead: Dictionary = {}, now_s: float = 0.0) -> int:
	if lane_count <= 1 or need.size() != lane_count:
		return 0
	var c := counts(team)
	var total := 0
	for n in c:
		total += n
	if total < 2:
		return 0
	var want := desired(total, need)
	var from := -1
	var to := -1
	var best_s := switch_margin
	var best_d := switch_margin
	for i in lane_count:
		var surplus := float(c[i]) - want[i]
		if c[i] > 0 and surplus > best_s:
			best_s = surplus
			from = i
		var deficit := want[i] - float(c[i])
		if deficit > best_d:
			best_d = deficit
			to = i
	if from < 0 or to < 0 or from == to:
		return 0
	var mover := 0
	for id in assignment:
		if _team_of.get(id, -1) != team or assignment[id] != from:
			continue
		if _moved_at.has(id) and now_s - float(_moved_at[id]) < min_stay_s:
			continue
		if mover == 0 or (dead.has(id) and not dead.has(mover)):
			mover = id
	if mover != 0:
		assignment[mover] = to
		_moved_at[mover] = now_s
	return mover


## A hero left the match (or a human took the bot over): forget it.
func release(hero_id: int) -> void:
	assignment.erase(hero_id)
	_team_of.erase(hero_id)
	_moved_at.erase(hero_id)
