class_name ObjectiveSystem
extends RefCounted
## All hardpoints of a map, server-side (architecture.md §2 ObjectiveSystem,
## §8.3 stage 9; match-flow-and-map.md §3.4-§3.5). Each tick:
##   1. C3 eligibility and Severed state from ownership at the start of the tick;
##   2. presence per hardpoint from PresenceSources (F1, C4 AI cap);
##   3. HardpointSim.step() in lane / index order (flips resolve first, then
##      eligibility is re-evaluated next tick: a same-tick flip stands, §6);
##   4. ObjectiveEvents (flip / defence) for this tick in `events`.
## Plant and Breach (E14) read TaskActors (heroes: interact, channel, mobility)
## and Generator hits arriving through damage_generator() between steps.

signal hardpoint_flipped(hp: HardpointSim, old_team: int, new_team: int)

var rules: MatchRulesDef
var map_def: MapDef
## Per lane: Array of HardpointSim ordered by lane index.
var lanes: Array = []
## Every hardpoint, lane-major (the snapshot order).
var all: Array[HardpointSim] = []
## D_s: Surge task-duration multiplier (F5). Match flow (E9) drives it.
var duration_scale: float = 1.0
## Deploy (match-flow-and-map.md §3.1): Mid hardpoints are Locked for both
## teams. Match flow (E9 MatchRules) drives it.
var mid_locked: bool = false
var front: LaneFrontResolver
## Events produced by the last step() (cleared at the start of each step).
var events: Array[ObjectiveEvent] = []

## Plant: hero net id -> HardpointSim whose Cell it carries (one Cell per hero).
var carriers: Dictionary = {}

var _time_s: float = 0.0
var _actors: Dictionary = {}


func _init(map: MapDef, match_rules: MatchRulesDef) -> void:
	map_def = map
	rules = match_rules
	front = LaneFrontResolver.new(self)
	for li in map.lanes.size():
		var lane_hps: Array = []
		var defs := map.lanes[li].hardpoints
		for i in defs.size():
			var h := HardpointSim.new(defs[i], li, i, rules)
			lane_hps.append(h)
			all.append(h)
		lanes.append(lane_hps)
	_refresh_eligibility()


## Map-wide index of `h` (lane-major, as MapDef.hardpoint_global), or -1.
func global_index(h: HardpointSim) -> int:
	return all.find(h)


func find(id: StringName) -> HardpointSim:
	for h in all:
		if h.def.id == id:
			return h
	return null


## C3: `team` may attack lanes[lane][index] if it holds the adjacent hardpoint
## toward its own HQ (its own Inner is adjacent to its HQ, so always eligible).
## A Mid needs no prerequisite. A team never "attacks" its own hardpoint.
func eligible(lane: int, index: int, team: int) -> bool:
	var hps: Array = lanes[lane]
	var h: HardpointSim = hps[index]
	if h.owner == team:
		return false
	if h.def.tier == HardpointDef.Tier.MID:
		return not mid_locked
	var prev := index - 1 if team == MapDef.TEAM_CONCORD else index + 1
	if prev < 0 or prev >= hps.size():
		return true
	return (hps[prev] as HardpointSim).owner == team


## Severed: the owner no longer holds the adjacent node toward its own HQ (§3.4).
func is_severed(lane: int, index: int) -> bool:
	var hps: Array = lanes[lane]
	var h: HardpointSim = hps[index]
	if h.owner == MapDef.TEAM_NEUTRAL or h.def.tier == HardpointDef.Tier.MID:
		return false
	var prev := index - 1 if h.owner == MapDef.TEAM_CONCORD else index + 1
	if prev < 0 or prev >= hps.size():
		return false
	return (hps[prev] as HardpointSim).owner != h.owner


## The team's front-most held hardpoint in the lane (furthest from its HQ), or -1.
func held_front(team: int, lane: int) -> int:
	var hps: Array = lanes[lane]
	var best := -1
	for i in LaneFrontResolver._order(team, hps.size()):
		if (hps[i] as HardpointSim).owner == team:
			best = i
	return best


## The hardpoint whose zone contains `pos`, or null.
func zone_at(pos: Vector3) -> HardpointSim:
	for h in all:
		if h.zone_contains(pos):
			return h
	return null


## One server tick. `sources`: heroes and registered Wardlings (PresenceSource
## or duck-typed objects, see PresenceSource). `actors`: TaskActors (heroes) for
## Plant; empty = nobody interacts.
func step(dt: float, sources: Array, tick: int = 0, actors: Array = []) -> void:
	events.clear()
	_time_s += dt
	_refresh_eligibility()
	_count_presence(sources)
	_actors.clear()
	for a in actors:
		_actors[(a as TaskActor).net_id] = a
	for h in all:
		var old_owner := h.owner
		var r := h.step(dt, duration_scale, rules, _actors, carriers)
		if r == HardpointSim.StepResult.FLIPPED:
			events.append(_flip_event(h, tick, old_owner))
		elif r == HardpointSim.StepResult.DEFENDED:
			events.append(_defence_event(h, tick))
	for id in carriers.keys():
		if (carriers[id] as HardpointSim).carrier_id != id:
			carriers.erase(id)
	for ev in events:
		if ev.kind == ObjectiveEvent.Kind.FLIP:
			hardpoint_flipped.emit(find(ev.hardpoint_id), ev.old_team, ev.new_team)


## Plant: the hardpoint whose Cell hero `net_id` carries, or null.
func carried_by(net_id: int) -> HardpointSim:
	return carriers.get(net_id)


## Move speed multiplier for hero `net_id` (§3.4 Plant 2: a carrier moves at 90%).
func move_speed_mult(net_id: int) -> float:
	return rules.cell_carrier_speed_mult if carriers.has(net_id) else 1.0


## Breach: routes a hit on hardpoint `h`'s Generator (see HardpointSim.damage_generator).
func damage_generator(h: HardpointSim, amount: float, team: int, source_pos: Vector3) -> float:
	return h.damage_generator(amount, team, source_pos) if h != null else 0.0


## Debug / tests / evidence: sets a Plant node's Cell state (HardpointSim.debug_set_cell).
func debug_set_cell(id: StringName, state: HardpointSim.CellState, team: int, hero_id: int = 0) -> void:
	var h := find(id)
	if h != null and h.task == HardpointDef.TaskKind.PLANT:
		h.debug_set_cell(state, team, carriers, hero_id)


## Debug / evidence: sets a hardpoint mid-capture by `team`.
func debug_set_progress(id: StringName, team: int, p: float) -> void:
	var h := find(id)
	if h != null and h.owner != team:
		h.capturing_team = team
		h.progress = clampf(p, 0.0, 0.999)


## Debug / tests: hands a hardpoint to `team` (no event, no progress).
func debug_set_owner(id: StringName, team: int) -> void:
	var h := find(id)
	if h != null:
		h.owner = team
		h.progress = 0.0
		h.capturing_team = MapDef.TEAM_NEUTRAL
		_refresh_eligibility()


func _refresh_eligibility() -> void:
	for h in all:
		for t in 2:
			h.eligible[t] = eligible(h.lane, h.index, t)
		h.severed = is_severed(h.lane, h.index)


func _count_presence(sources: Array) -> void:
	var cap := rules.ai_presence_cap
	for h in all:
		var hero_p := [0.0, 0.0]
		var ai_p := [0.0, 0.0]
		var heroes := [0, 0]
		for s in sources:
			var t: int = s.team
			if t < 0 or t > 1 or not s.is_alive() or not h.zone_contains(s.global_position):
				continue
			if s.get("is_hero") == true:
				hero_p[t] += s.presence_weight
				heroes[t] += 1
				var nid = s.get("net_id")
				if nid != null and nid != 0:
					h.recent_heroes[nid] = [t, _time_s]
			else:
				ai_p[t] += s.presence_weight
		for t in 2:
			h.presence[t] = hero_p[t] + minf(cap, ai_p[t])
			h.heroes_in[t] = heroes[t]


func _flip_event(h: HardpointSim, tick: int, old_owner: int) -> ObjectiveEvent:
	var ev := _event(h, tick, ObjectiveEvent.Kind.FLIP)
	ev.new_team = h.owner
	ev.old_team = old_owner
	ev.participants = _recent(h, h.owner, rules.participant_window_s)
	if h.planter_id != 0 and not ev.participants.has(h.planter_id):
		ev.participants.append(h.planter_id)  # §16.1: planting the Cell counts
	h.planter_id = 0
	ev.lumen_each = rules.lumen_capture_participant
	ev.lumen_team = rules.lumen_capture_team
	ev.exp_each = rules.exp_capture_placeholder
	return ev


func _defence_event(h: HardpointSim, tick: int) -> ObjectiveEvent:
	var ev := _event(h, tick, ObjectiveEvent.Kind.DEFENCE)
	ev.old_team = 1 - h.owner
	ev.new_team = h.owner
	ev.participants = _recent(h, h.owner, 0.0)
	ev.lumen_each = rules.lumen_defence
	ev.exp_each = rules.exp_defence_placeholder
	return ev


func _event(h: HardpointSim, tick: int, kind: ObjectiveEvent.Kind) -> ObjectiveEvent:
	var ev := ObjectiveEvent.new()
	ev.kind = kind
	ev.hardpoint_id = h.def.id
	ev.lane = h.lane
	ev.index = h.index
	ev.tick = tick
	return ev


## Hero ids of `team` seen in the zone within `window_s` (0 = this tick).
func _recent(h: HardpointSim, team: int, window_s: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in h.recent_heroes:
		var rec: Array = h.recent_heroes[id]
		if rec[0] == team and _time_s - rec[1] <= window_s + 1e-6:
			out.append(id)
	return out
