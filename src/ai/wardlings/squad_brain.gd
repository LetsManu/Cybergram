class_name SquadBrain
extends RefCounted
## Squad-level thinking (wardlings-and-economy.md §9.1, 5 Hz): anchor, formation
## / ring slots and the shared threat (utility score of §9.4, gated so a squad
## never starts a hero fight on its own). Writes only the Squad blackboard.

## §9.2: the Follow wedge spans a 140° rear arc.
const REAR_ARC_DEG: float = 140.0


static func think(sq: Squad, world: WardlingWorld, rules: WardlingRulesDef) -> void:
	var owner := world.server.hero(sq.owner_net_id)
	var owner_ok := owner != null and not owner.combat.dead and not sq.is_dissolving()
	var base_cmd := sq.prev_command if sq.command == Squad.CMD_ATTACK else sq.command
	if sq.is_dissolving():
		sq.anchor = sq.capture_point if sq.command == Squad.CMD_CAPTURE else sq.hold_point
	elif base_cmd == Squad.CMD_HOLD:
		sq.anchor = sq.hold_point
	elif base_cmd == Squad.CMD_CAPTURE:
		sq.anchor = sq.capture_point
	elif owner_ok:
		sq.anchor = owner.state.position
	_assign_slots(sq, world, rules, owner if owner_ok else null, base_cmd)
	sq.threat_id = _pick_threat(sq, world, rules, owner if owner_ok else null, base_cmd)


## Follow wedge behind the owner (3–6 m, 140° rear arc, framed on velocity or
## facing), Hold / Capture rings, or a tight ring during DeathHold.
static func formation_slots(center: Vector3, forward: Vector3, n: int, rules: WardlingRulesDef) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var back := -Vector3(forward.x, 0.0, forward.z)
	back = back.normalized() if back.length_squared() > 1e-6 else Vector3(0.0, 0.0, 1.0)
	var half := deg_to_rad(REAR_ARC_DEG) * 0.5
	for i in n:
		var t := 0.5 if n == 1 else float(i) / float(n - 1)
		var ang := lerpf(-half, half, t) * 0.6  # keep the wedge compact for 3–5 units
		var dist := lerpf(rules.follow_back_min_m, rules.follow_back_max_m, 1.0 - absf(t - 0.5) * 2.0)
		out.append(center + back.rotated(Vector3.UP, ang) * dist)
	return out


static func ring_slots(center: Vector3, radius: float, n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in n:
		var a := TAU * float(i) / float(maxi(n, 1))
		out.append(center + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	return out


static func _assign_slots(sq: Squad, world: WardlingWorld, rules: WardlingRulesDef, owner: HeroBody, cmd: int) -> void:
	var n := sq.members.size()
	var slots: Array[Vector3]
	if sq.is_dissolving():
		slots = ring_slots(sq.anchor, 1.5, n)
	elif cmd == Squad.CMD_HOLD:
		slots = ring_slots(sq.anchor, rules.hold_slot_radius_m, n)
	elif cmd == Squad.CMD_CAPTURE:
		slots = ring_slots(sq.anchor, sq.capture_radius * rules.capture_ring_frac, n)
	elif owner != null:
		var v := owner.state.velocity
		var fwd := Vector3(v.x, 0.0, v.z)
		if fwd.length_squared() < 0.25:
			fwd = Basis(Vector3.UP, owner.look_yaw) * Vector3.FORWARD
		slots = formation_slots(sq.anchor, fwd, n, rules)
	else:
		return
	sq.slots.clear()
	for i in n:
		sq.slots[sq.members[i].net_id] = world.snap(slots[i])


## Shared threat (§9.4, simplified): Score = 0.40 Threat + 0.20 Proximity +
## 0.15 Objective + 0.10 Stickiness; Threat 1.0 for whoever hit the owner,
## 0.7 for whoever hit a member. A hero with Threat 0 and Objective 0 never
## scores (no hero initiation); enemy Wardlings inside wardling_aggro_m always do.
static func _pick_threat(sq: Squad, world: WardlingWorld, rules: WardlingRulesDef, owner: HeroBody, cmd: int) -> int:
	var now := world.server.tick
	var memory := roundi(rules.threat_memory_s * world.tick_hz)
	var hitters := {}
	if owner != null and now - sq.owner_hit_tick <= memory:
		hitters[sq.owner_attacker_id] = 1.0
	for m in sq.members:
		if now - m.last_hit_tick <= memory and not hitters.has(m.last_attacker_id):
			hitters[m.last_attacker_id] = 0.7
	var radius := rules.follow_leash_m
	var zone_r := 0.0
	if cmd == Squad.CMD_HOLD:
		radius = rules.hold_slot_radius_m + rules.hold_engage_m
	elif cmd == Squad.CMD_CAPTURE:
		radius = rules.capture_leash_m
		zone_r = sq.capture_radius
	var best := 0
	var best_s := 0.0
	for e in world.enemies_near(sq.anchor, radius, sq.team):
		var id: int = e.get("net_id")
		var d := WardlingWorld._flat(WardlingWorld.feet_of(e), sq.anchor)
		var threat: float = hitters.get(id, 0.0)
		var objective := 1.0 if zone_r > 0.0 and d <= zone_r else 0.0
		var is_hero := e is HeroBody
		if is_hero and threat == 0.0 and objective == 0.0:
			continue
		var s := 0.40 * threat + 0.20 * (1.0 - clampf(d / 25.0, 0.0, 1.0)) + 0.15 * objective \
			+ (0.10 if id == sq.threat_id else 0.0)
		var always := not is_hero and d <= rules.wardling_aggro_m
		if s < 0.25 and not always and objective == 0.0:
			continue
		if always:
			s = maxf(s, 0.25)
		if s > best_s:
			best_s = s
			best = id
	return best
