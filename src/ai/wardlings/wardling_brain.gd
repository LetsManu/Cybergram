class_name WardlingBrain
extends RefCounted
## Per-Wardling FSM (architecture.md §10.1, ADR-0005 §5). A RefCounted
## struct-of-state: it reads the Squad / VanguardWave blackboards and world
## queries, and writes ONLY intents on its WardlingSim (set_move_target,
## set_attack_target, stop...) plus the squad's LOS report.
## Transitions are table-driven (TRANSITIONS) and validated; decide() is pure
## so every command's transition row is unit-testable.

enum State { FOLLOW, HOLD, ENGAGE, RETURN, ATTACK_TARGET, CAPTURE, GARRISONED, MARCH, DISSOLVING }
enum Allegiance { SQUAD, VANGUARD, GARRISON }

## Allowed exits per state. Squads use FOLLOW/HOLD/ATTACK_TARGET/CAPTURE/ENGAGE/
## RETURN/DISSOLVING; Vanguard uses MARCH/ENGAGE/CAPTURE (architecture.md §10.1).
const TRANSITIONS := {
	State.FOLLOW: [State.HOLD, State.ENGAGE, State.RETURN, State.ATTACK_TARGET, State.CAPTURE, State.DISSOLVING],
	State.HOLD: [State.FOLLOW, State.ENGAGE, State.RETURN, State.ATTACK_TARGET, State.CAPTURE, State.DISSOLVING],
	State.ENGAGE: [State.FOLLOW, State.HOLD, State.RETURN, State.ATTACK_TARGET, State.CAPTURE, State.MARCH,
		State.DISSOLVING],
	State.RETURN: [State.FOLLOW, State.HOLD, State.ENGAGE, State.ATTACK_TARGET, State.CAPTURE, State.DISSOLVING],
	State.ATTACK_TARGET: [State.FOLLOW, State.HOLD, State.ENGAGE, State.RETURN, State.CAPTURE, State.DISSOLVING],
	State.CAPTURE: [State.FOLLOW, State.HOLD, State.ENGAGE, State.RETURN, State.ATTACK_TARGET, State.MARCH,
		State.DISSOLVING],
	State.MARCH: [State.ENGAGE, State.CAPTURE],
	State.GARRISONED: [State.ENGAGE],
	State.DISSOLVING: [],
}

const STATE_LETTER := ["F", "H", "!", "R", "A", "C", "G", "M", "D"]


## What one decision sees (filled by perceive(); built directly in unit tests).
class Percept:
	var allegiance: int = Allegiance.SQUAD
	## Squad.CMD_* (squads only).
	var command: int = Squad.CMD_FOLLOW
	## Owner dead: DeathHold until the squad dissolves.
	var dissolving: bool = false
	## The Attack Target order is live and its target exists.
	var attack_valid: bool = false
	## A scored threat exists (retaliation / Wardlings in aggro / enemy in zone).
	var threat: bool = false
	## Beyond the command's leash (Follow 30 m from the owner, Hold, Capture zone).
	var out_of_leash: bool = false
	## Back inside the return radius (Follow: 20 m) - RETURN may end.
	var returned: bool = true
	## Vanguard: inside the front hardpoint zone.
	var at_front: bool = false


var body: WardlingSim
var world: WardlingWorld
var rules: WardlingRulesDef
var state: int = State.FOLLOW
var state_since_tick: int = 0
## Decision was deferred by the per-tick cap (or never ran yet).
var overdue: bool = true
## Wave plan this member follows (WaveBrain bumps wave.plans on a re-plan).
var _plan_seen: int = -1
var _march_offset: Vector2 = Vector2.ZERO
var _target: Node3D
var transitions: int = 0
## Set by the director: func(from: Vector3, to: Vector3) -> int (1 clear, 0 blocked, -1 no budget).
var los_probe: Callable
var on_transition: Callable


func _init(w: WardlingSim, ww: WardlingWorld, r: WardlingRulesDef) -> void:
	body = w
	world = ww
	rules = r
	state = State.MARCH if w.wave != null else State.FOLLOW


## Pure transition choice (no side effects). Always returns `state` or one of
## TRANSITIONS[state].
static func decide(from: int, p: Percept) -> int:
	var next := _want(from, p)
	if next == from or TRANSITIONS[from].has(next):
		return next
	return from


static func _want(from: int, p: Percept) -> int:
	if p.dissolving:
		return State.DISSOLVING
	if p.allegiance == Allegiance.VANGUARD:
		if p.threat:
			return State.ENGAGE
		return State.CAPTURE if p.at_front else State.MARCH
	if p.allegiance == Allegiance.GARRISON:
		return State.ENGAGE if p.threat else State.GARRISONED
	# Squad. Attack Target beats retaliation (C15, §10.1).
	if p.command == Squad.CMD_ATTACK and p.attack_valid:
		return State.ATTACK_TARGET
	if from == State.RETURN and not p.returned:
		return State.RETURN
	if p.out_of_leash:
		return State.RETURN
	if p.threat:
		return State.ENGAGE
	match p.command:
		Squad.CMD_HOLD:
			return State.HOLD
		Squad.CMD_CAPTURE:
			return State.CAPTURE
	return State.FOLLOW


static func is_allowed(from: int, to: int) -> bool:
	return from == to or TRANSITIONS[from].has(to)


## One decision (10 Hz, staggered by the director).
func think(tick: int) -> void:
	overdue = false
	var p := perceive()
	var next := decide(state, p)
	if next != state:
		var from := state
		state = next
		state_since_tick = tick
		transitions += 1
		if on_transition.is_valid():
			on_transition.call(body.net_id, from, next)
	body.brain_state = state
	_act(tick)


func perceive() -> Percept:
	var p := Percept.new()
	var pos := body.global_position
	if body.wave != null:
		var wv := body.wave
		p.allegiance = Allegiance.VANGUARD
		_target = world.live_entity(wv.threat_id)
		var own := _own_attacker()
		if own != null:
			_target = own
		p.threat = _target != null
		p.at_front = wv.target_index >= 0 and _flat(pos, wv.target_point) <= wv.target_radius * rules.front_arrive_frac
		return p
	var sq := body.squad
	if sq == null:
		p.dissolving = true
		return p
	p.command = sq.command
	p.dissolving = sq.is_dissolving()
	if sq.command == Squad.CMD_ATTACK:
		_target = world.live_entity(sq.attack_target_id)
		p.attack_valid = _target != null
	else:
		_target = world.live_entity(sq.threat_id)
		var own := _own_attacker()
		if _target == null and own != null:
			_target = own
		p.threat = _target != null
	var anchor := sq.anchor
	var d := _flat(pos, anchor)
	match sq.command:
		Squad.CMD_HOLD:
			p.out_of_leash = d > rules.hold_slot_radius_m + rules.hold_engage_m
			p.returned = d <= rules.hold_slot_radius_m + rules.arrive_return_m
		Squad.CMD_CAPTURE:
			p.out_of_leash = d > rules.capture_leash_m
			p.returned = d <= sq.capture_radius
		_:
			p.out_of_leash = d > rules.follow_leash_m
			p.returned = d <= rules.return_fire_m
	return p


func _own_attacker() -> Node3D:
	if world.server.tick - body.last_hit_tick > roundi(rules.threat_memory_s * world.tick_hz):
		return null
	var a := world.live_entity(body.last_attacker_id)
	if a == null or WardlingWorld.team_of(a) == body.team:
		return null
	if _flat(body.global_position, WardlingWorld.feet_of(a)) > body.def.range_m + rules.attacker_margin_m:
		return null
	return a


func _act(tick: int) -> void:
	var sq := body.squad
	match state:
		State.FOLLOW, State.HOLD, State.CAPTURE:
			body.clear_attack()
			body.set_display_flags(0)
			if body.wave != null:
				_go_slot(_ring_slot(body.wave.target_point, body.wave.target_radius * rules.capture_ring_frac,
					body.wave.members.find(body), body.wave.members.size()), body.def.move_speed)
			else:
				_go_slot(sq.slots.get(body.net_id, sq.anchor), body.def.move_speed)
		State.RETURN:
			body.clear_attack()
			body.set_display_flags(WardlingSim.FLAG_RETURNING)
			body.set_move_target(sq.slots.get(body.net_id, sq.anchor), body.def.sprint_speed, rules.arrive_return_m)
		State.ENGAGE, State.ATTACK_TARGET:
			_engage(tick, state == State.ATTACK_TARGET)
		State.MARCH:
			body.clear_attack()
			body.set_display_flags(0)
			_march()
		State.DISSOLVING:
			body.stop()
			if sq != null and _target == null:
				_target = world.live_entity(sq.threat_id)
			if _target != null:
				_fire_at(tick, false, false)
			else:
				body.clear_attack()


## Move to a slot; sprint when far behind (§9.2).
func _go_slot(slot: Vector3, speed: float) -> void:
	var far := _flat(body.global_position, slot) > rules.catch_up_m
	body.set_move_target(slot, body.def.sprint_speed if far else speed, rules.arrive_slot_m)


func _engage(tick: int, focused: bool) -> void:
	if _target == null:
		body.clear_attack()
		return
	var los := _fire_at(tick, focused, true)
	body.set_display_flags(WardlingSim.FLAG_COMBAT)
	var tpos := WardlingWorld.feet_of(_target)
	var dist := _flat(body.global_position, tpos)
	if los and dist <= body.def.range_m * rules.engage_range_frac:
		body.stop()
		return
	# Close in (no LOS or out of range), but never past the leash.
	var dest := tpos
	var anchor := _leash_anchor()
	var leash := _leash_radius(focused)
	if _flat(dest, anchor) > leash:
		var dir := Vector3(dest.x - anchor.x, 0.0, dest.z - anchor.z).normalized()
		dest = anchor + dir * leash
	var speed := rules.wave_march_speed if body.wave != null else body.def.move_speed
	body.set_move_target(dest, speed, rules.arrive_chase_m)


## Aims at the current target; returns the LOS result used for firing.
func _fire_at(tick: int, focused: bool, report: bool) -> bool:
	var from := body.chest()
	var to := world.chest_of(_target)
	var clear: bool = body.fire_clear and body.attack_target_id == int(_target.get("net_id"))
	if from.distance_to(to) <= body.def.range_m + rules.arrive_chase_m:
		var r: int = los_probe.call(from, to) if los_probe.is_valid() else (1 if world.has_los(from, to) else 0)
		if r >= 0:
			clear = r == 1
	else:
		clear = false
	body.set_attack_target(_target.get("net_id"), focused, clear)
	if clear and report and focused and body.squad != null:
		body.squad.note_target_seen(tick)
	return clear


func _leash_anchor() -> Vector3:
	if body.wave != null:
		return body.wave.target_point if body.wave.target_index >= 0 else body.global_position
	return body.squad.anchor


func _leash_radius(focused: bool) -> float:
	if body.wave != null:
		return rules.wave_engage_m + body.wave.target_radius
	var sq := body.squad
	if focused:
		return rules.attack_leash_hold_m if sq.prev_command == Squad.CMD_HOLD else rules.attack_leash_owner_m
	match sq.command:
		Squad.CMD_HOLD:
			return rules.hold_slot_radius_m + rules.hold_engage_m
		Squad.CMD_CAPTURE:
			return rules.capture_leash_m
	return rules.follow_leash_m


func _march() -> void:
	var wv := body.wave
	if wv.path.is_empty():
		body.stop()
		return
	if _plan_seen != wv.plans:
		_plan_seen = wv.plans
		var i := wv.members.find(body)
		_march_offset = Vector2((float(i % 2) - 0.5) * rules.wave_spacing_m, float((i >> 1) % 2) * rules.wave_spacing_m)
		body.set_path(_offset_path(wv.path, _march_offset), rules.wave_march_speed, rules.arrive_march_m)
	elif not body.has_move_target:
		body.set_path(_offset_path(wv.path, _march_offset), rules.wave_march_speed, rules.arrive_march_m)


## The shared path shifted sideways by offset.x (2 x 2 block); the rear rank
## keeps its spacing because it starts behind.
static func _offset_path(path: PackedVector3Array, offset: Vector2) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(path.size())
	for i in path.size():
		var a := path[maxi(i - 1, 0)]
		var b := path[mini(i + 1, path.size() - 1)]
		var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var side := Vector3(-d.z, 0.0, d.x).normalized() if d.length_squared() > 1e-6 else Vector3.ZERO
		out[i] = path[i] + side * offset.x
	return out


static func _ring_slot(center: Vector3, radius: float, i: int, n: int) -> Vector3:
	var a := TAU * float(maxi(i, 0)) / float(maxi(n, 1))
	return center + Vector3(cos(a) * radius, 0.0, sin(a) * radius)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
