class_name LaneFrontResolver
extends RefCounted
## Front hardpoint of a team in a lane (Canon C15, match-flow-and-map.md §3.8
## "Target (front)"; ADR-0005). Order of preference:
##   1. the nearest contested hardpoint (P > 0 on an own or neutral node, or the
##      team's own progress anywhere), nearest = closest to the team's HQ;
##   2. the nearest hardpoint the team may attack under C3;
##   3. the team's front-most held hardpoint (it defends there).
## Returns the lane index, or -1 if the team holds nothing and can attack nothing.
## Plant nodes would count for 2 only while an allied hero carries a Cell; Plant
## is not live yet (all nodes staged as Hold), so that filter is not applied.

var _sys: ObjectiveSystem


func _init(system: ObjectiveSystem) -> void:
	_sys = system


func front_for(team: int, lane: int) -> int:
	var hps: Array = _sys.lanes[lane]
	var order := _order(team, hps.size())
	for i in order:
		var h: HardpointSim = hps[i]
		if h.progress > 0.0 and (h.capturing_team == team or h.owner == team or h.owner == MapDef.TEAM_NEUTRAL):
			return i
	for i in order:
		var h: HardpointSim = hps[i]
		if h.owner != team and _sys.eligible(lane, i, team):
			return i
	return _sys.held_front(team, lane)


## Lane indices from `team`'s HQ outward.
static func _order(team: int, n: int) -> Array:
	var out := range(n)
	if team == MapDef.TEAM_SYNDICATE:
		out.reverse()
	return out
