class_name BotSkillBehaviours
extends RefCounted
## W10-W3: pure decision rules for the skills a single "condition -> slot" row
## cannot express (BotSkillRules covers the rest): Liora's heal beam target,
## Sable's remote detonation, Juniper's Tripwire sites and Hex's Relay Hop.
## No engine state is read here: BotBrain gathers the inputs, so every rule is
## unit-testable. Thresholds come from BotSkillTuning (data).

enum HopMode { NONE, ESCAPE, REPOSITION }

## One allied hero as the healer sees it.
class AllyView:
	var id: int = 0
	var hp_frac: float = 1.0
	var dist: float = 0.0
	var los: bool = true

	func _init(id_: int, hp: float, d: float, line: bool = true) -> void:
		id = id_
		hp_frac = hp
		dist = d
		los = line


## Net id of the ally to beam, or 0. `current_id` keeps the lock until the ally
## reaches beam_release_hp_frac or leaves range / sight; a new lock is the most
## injured ally at or below beam_start_hp_frac (ties: nearer, then lower id).
static func pick_beam_target(allies: Array, range_m: float, current_id: int, t: BotSkillTuning) -> int:
	var reach := range_m - t.beam_range_margin_m
	if current_id != 0:
		for a in allies:
			var v := a as AllyView
			if v.id == current_id and v.los and v.dist <= reach and v.hp_frac < t.beam_release_hp_frac:
				return current_id
	var best: AllyView = null
	for a in allies:
		var v := a as AllyView
		if not v.los or v.dist > reach or v.hp_frac > t.beam_start_hp_frac:
			continue
		if best == null or v.hp_frac < best.hp_frac - 0.0001 \
				or (absf(v.hp_frac - best.hp_frac) <= 0.0001 and (v.dist < best.dist - 0.0001 \
				or (absf(v.dist - best.dist) <= 0.0001 and v.id < best.id))):
			best = v
	return best.id if best != null else 0


## True while the healer is under heavy fire (she fights or flees instead).
static func beam_blocked(hp_frac: float, secs_since_damaged: float, t: BotSkillTuning) -> bool:
	return secs_since_damaged <= t.beam_self_fire_window_s and hp_frac <= t.beam_self_hp_frac


## Mana gate with hysteresis: stop at beam_mana_stop_frac, resume at beam_mana_start_frac.
static func beam_mana_ok(mana_frac: float, holding: bool, t: BotSkillTuning) -> bool:
	return mana_frac > t.beam_mana_stop_frac if holding else mana_frac >= t.beam_mana_start_frac


## Remote detonation: an enemy hero inside `blast_radius * sabotage_hero_radius_frac`
## of an armed charge, or an enemy Ward Generator (position + hit radius) within
## the blast plus slack.
static func detonation_wanted(charges: PackedVector3Array, enemies: PackedVector3Array,
		gen_pos: PackedVector3Array, gen_hit_r: PackedFloat32Array, blast_radius: float, t: BotSkillTuning) -> bool:
	for c in charges:
		for e in enemies:
			if c.distance_to(e) <= blast_radius * t.sabotage_hero_radius_frac:
				return true
		for i in gen_pos.size():
			var hr := gen_hit_r[i] if i < gen_hit_r.size() else 0.0
			if c.distance_to(gen_pos[i]) <= blast_radius + hr + t.sabotage_generator_slack_m:
				return true
	return false


## Tripwire anchors [A, B] across the approach path to a zone, or empty.
## `path` runs from the enemy side to the zone centre (nav data). At each
## wire_path_offsets_m site (arc length back from the zone) the wire spans the
## free width perpendicular to the path, capped at `wire_len`; `probe` is a
## Callable(point: Vector3, dir: Vector3) -> free distance (m) in that direction
## (a wall ray in the brain). The narrowest site that fits wins (a chokepoint).
static func pick_wire(path: PackedVector3Array, wire_len: float, probe: Callable, t: BotSkillTuning) -> PackedVector3Array:
	var out := PackedVector3Array()
	if path.size() < 2:
		return out
	var best_w := INF
	for off in t.wire_path_offsets_m:
		var site := _site_on_path(path, off)
		if site.is_empty():
			continue
		var p: Vector3 = site[0]
		var d: Vector3 = site[1]
		var perp := Vector3(-d.z, 0.0, d.x)
		var left := minf(float(probe.call(p, perp)), wire_len * 0.5)
		var right := minf(float(probe.call(p, -perp)), wire_len * 0.5)
		var w := left + right
		if w < t.wire_min_width_m or w >= best_w - 0.0001:
			continue
		best_w = w
		out = PackedVector3Array([p + perp * left, p - perp * right])
	return out


## [point, flat unit direction of travel toward the zone] `back` metres from the path end.
static func _site_on_path(path: PackedVector3Array, back: float) -> Array:
	var left := back
	var i := path.size() - 1
	while i > 0:
		var seg := path[i - 1] - path[i]
		seg.y = 0.0
		var l := seg.length()
		if l >= left and l > 0.001:
			var p := path[i] + seg / l * left
			return [p, (-seg / l)]
		left -= l
		i -= 1
	return []


## Both anchors within the skill's range of the bot (press 1 lays A, press 2 lays B).
static func wire_in_reach(pos: Vector3, a: Vector3, b: Vector3, range_m: float, t: BotSkillTuning) -> bool:
	var r := range_m - t.wire_range_margin_m
	return BotBlackboard.flat_dist(pos, a) <= r and BotBlackboard.flat_dist(pos, b) <= r


## Which Relay Hop use applies: ESCAPE when hurt and at low HP, REPOSITION when
## healthy, unhurt and the fight is far away, else NONE.
static func hop_mode(hp_frac: float, hurt_now: bool, target_dist: float, t: BotSkillTuning) -> int:
	if hurt_now and hp_frac <= t.hop_escape_hp_frac:
		return HopMode.ESCAPE
	if not hurt_now and hp_frac >= t.hop_reposition_min_hp_frac and target_dist < INF \
			and target_dist >= t.hop_reposition_min_target_m:
		return HopMode.REPOSITION
	return HopMode.NONE


## Index of the gadget to hop to, or -1: within range, and at least hop_min_gain_m
## closer to `anchor` (home when escaping, the fight when repositioning) than
## the bot; the biggest gain wins (ties: lower index).
static func pick_hop_gadget(pos: Vector3, anchor: Vector3, gadgets: PackedVector3Array, range_m: float,
		t: BotSkillTuning) -> int:
	var best := -1
	var best_gain := t.hop_min_gain_m - 0.0001
	var base := BotBlackboard.flat_dist(pos, anchor)
	for i in gadgets.size():
		var g := gadgets[i]
		if pos.distance_to(g) > range_m - t.hop_range_margin_m:
			continue
		var gain := base - BotBlackboard.flat_dist(g, anchor)
		if gain > best_gain:
			best_gain = gain
			best = i
	return best
