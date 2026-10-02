class_name WaveBrain
extends RefCounted
## One per Vanguard wave (architecture.md §10.1 "wave-level thinking",
## wardlings-and-economy.md §10, 2 Hz). Plans the expensive things once per
## wave: the front target (LaneFrontResolver / C15 rule), ONE shared navmesh
## path for all members, and the threat list. Members then only follow the
## path with a formation offset and pick from the wave's threat.

var wave: VanguardWave
var world: WardlingWorld
var rules: WardlingRulesDef


func _init(w: VanguardWave, ww: WardlingWorld, r: WardlingRulesDef) -> void:
	wave = w
	world = ww
	rules = r


func think(_tick: int) -> void:
	if wave.members.is_empty():
		return
	var lane: LaneDef = world.map_def.lanes[wave.lane]
	var front := world.front_index(wave.team, wave.lane)
	if front >= 0 and (front != wave.target_index or wave.path.is_empty()):
		var hp: HardpointDef = lane.hardpoints[front]
		wave.target_index = front
		wave.target_point = hp.position
		wave.target_radius = hp.zone_radius
		_plan()
	wave.threat_id = _pick_threat()


## One path query for the whole wave, from its lead member to the front zone.
func _plan() -> void:
	if not world.nav_ready():
		return
	var from := _centroid()
	var p := world.query_path(from, wave.target_point)
	if p.size() < 2:
		return
	wave.path = p
	wave.plans += 1


func _centroid() -> Vector3:
	var c := Vector3.ZERO
	for m in wave.members:
		c += m.global_position
	return c / wave.members.size()


## §10: enemy Wardlings within wave_engage_m, anyone who damaged a member, and
## any enemy inside the target zone. Heroes otherwise pass (hero gate, §9.4).
func _pick_threat() -> int:
	var now := world.server.tick
	var memory := roundi(rules.threat_memory_s * world.tick_hz)
	var hitters := {}
	for m in wave.members:
		if now - m.last_hit_tick <= memory:
			hitters[m.last_attacker_id] = true
	var c := _centroid()
	var best := 0
	var best_d := INF
	for e in world.enemies_near(c, rules.wave_engage_m + 4.0, wave.team):
		var id: int = e.get("net_id")
		var p := WardlingWorld.feet_of(e)
		var d := WardlingWorld._flat(p, c)
		var in_zone := wave.target_index >= 0 and WardlingWorld._flat(p, wave.target_point) <= wave.target_radius
		var ok := hitters.has(id) or in_zone or (e is WardlingSim and d <= rules.wave_engage_m)
		if ok and (d < best_d or id == wave.threat_id and d < best_d + 3.0):
			best_d = d
			best = id
	return best
