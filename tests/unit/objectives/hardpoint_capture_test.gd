extends GdUnitTestSuite
## E7 Hold rules (match-flow-and-map.md §3.4, F1-F3, §9 ACs 3-6): capture rate,
## contest freeze, Overtime + decay, C3 adjacency, the C4 AI presence cap,
## neutral Mid drain, heroless Inner cap, Severed retake and flip events.

const MAP_PATH := "res://assets/data/match/map_slice_lane.tres"
const DT: float = 1.0 / 30.0
const C := MapDef.TEAM_CONCORD
const S := MapDef.TEAM_SYNDICATE

var _rules: MatchRulesDef


func before_test() -> void:
	_rules = MatchRulesDef.new()


func _system() -> ObjectiveSystem:
	return ObjectiveSystem.new(load(MAP_PATH) as MapDef, _rules)


func _hero(pos: Vector3, team: int, net_id: int = 0) -> PresenceSource:
	var s := PresenceSource.at(pos, team, PresenceSource.HERO_WEIGHT, true)
	s.net_id = net_id
	return s


func _wardlings(pos: Vector3, team: int, n: int) -> Array:
	var out := []
	for i in n:
		out.append(PresenceSource.at(pos + Vector3(i * 0.3, 0.0, 0.0), team))
	return out


## Steps until `h` flips or `max_s` passes; returns seconds taken (or -1).
func _run_until_flip(sys: ObjectiveSystem, h: HardpointSim, sources: Array, max_s: float) -> float:
	var start_owner := h.owner
	var ticks := 0
	while ticks * DT < max_s:
		sys.step(DT, sources, ticks)
		ticks += 1
		if h.owner != start_owner:
			return ticks * DT
	return -1.0


func _run(sys: ObjectiveSystem, sources: Array, seconds: float) -> void:
	for i in roundi(seconds / DT):
		sys.step(DT, sources, i)


# ---- F2 capture rate ------------------------------------------------------

func test_capture_rate_matches_f2_at_several_deltas() -> void:
	# M(Δ) = min(2.0, 0.4 + 0.24 Δ); dP/dt = K_hl M / (T D_s K_sev)
	var cases := [
		[0.5, true, 0.52 / 60.0],
		[1.0, true, 0.64 / 60.0],
		[2.5, true, 1.0 / 60.0],
		[5.0, true, 1.6 / 60.0],
		[8.0, true, 2.0 / 60.0],      # capped at M_max
		[2.0, false, 0.5 * 0.88 / 60.0],  # heroless K_hl
		[0.0, true, 0.0],
		[-1.5, true, 0.0],
	]
	for c in cases:
		assert_float(HardpointSim.capture_rate(c[0], c[1], 60.0, 1.0, 1.0, _rules)).is_equal_approx(c[2], 1e-6)
	# GDD F2 worked example: Δ 3.0 at D_s 0.85 on the Spindle -> 0.0220/s (45.5 s).
	assert_float(HardpointSim.capture_rate(3.0, true, 60.0, 0.85, 1.0, _rules)).is_equal_approx(0.02196, 1e-4)
	# Fastest case: M 2.0, T 60, D_s 0.70, K_sev 0.75 -> 0.0635/s.
	assert_float(HardpointSim.capture_rate(8.0, true, 60.0, 0.7, 0.75, _rules)).is_equal_approx(0.0635, 1e-4)


func test_neutral_mid_reference_push_captures_in_60s_and_double_in_37_5s() -> void:
	# AC 3: 1 hero + 3 Wardlings (Δ 2.5) -> 60 ± 1 s; 2H + 6W (Δ 5.0) -> 37.5 ± 1 s.
	var sys := _system()
	var mid := sys.find(&"s_mid")
	var srcs := [_hero(mid.def.position, C)] + _wardlings(mid.def.position, C, 3)
	assert_float(_run_until_flip(sys, mid, srcs, 70.0)).is_between(59.0, 61.0)
	assert_int(mid.owner).is_equal(C)
	sys = _system()
	mid = sys.find(&"s_mid")
	srcs = [_hero(mid.def.position, S), _hero(mid.def.position, S)] + _wardlings(mid.def.position, S, 6)
	assert_float(_run_until_flip(sys, mid, srcs, 50.0)).is_between(36.5, 38.5)
	assert_int(mid.owner).is_equal(S)


# ---- contest, Overtime, decay ----------------------------------------------

func test_equal_presence_freezes_progress_for_30s() -> void:
	# AC 4.
	var sys := _system()
	var mid := sys.find(&"s_mid")
	var p := mid.def.position
	_run(sys, [_hero(p, C)], 10.0)
	var frozen := mid.progress
	assert_float(frozen).is_greater(0.0)
	_run(sys, [_hero(p, C), _hero(p, S)], 30.0)
	assert_float(mid.progress).is_equal(frozen)
	assert_bool(mid.contested).is_true()
	# Owned hardpoint: attacker present but not out-numbering -> frozen too.
	sys = _system()
	var bo := sys.find(&"s_bo")
	sys.find(&"s_mid").owner = C
	_run(sys, [_hero(bo.def.position, C)], 10.0)
	frozen = bo.progress
	assert_float(frozen).is_greater(0.0)
	_run(sys, [_hero(bo.def.position, C)] + _wardlings(bo.def.position, S, 2), 30.0)
	assert_float(bo.progress).is_equal(frozen)
	assert_bool(bo.contested).is_true()


func test_overtime_then_decay_without_and_with_a_defender() -> void:
	# AC 5: last attacker leaves at P = 0.5 -> held 5 s, then 0 in 120 s
	# without a defender (decay 0.5 / T) and 60 s with one (1.0 / T).
	for defended in [false, true]:
		var sys := _system()
		var bo := sys.find(&"s_bo")  # Syndicate Outer, staged Hold T = 65
		sys.find(&"s_mid").owner = C
		bo.capturing_team = C
		bo.progress = 0.5
		var srcs := [_hero(bo.def.position, C)]
		sys.step(DT, srcs)
		var p := bo.progress
		var away: Array = [_hero(bo.def.position, S)] if defended else []
		_run(sys, away, 4.9)
		assert_float(bo.progress).is_equal(p)
		assert_bool(bo.overtime_left > 0.0).is_true()
		var expected := p / ((1.0 if defended else 0.5) / 65.0)
		var t := 4.9
		while bo.progress > 0.0 and t < 200.0:
			sys.step(DT, away)
			t += DT
		assert_float(t - 5.0).is_between(expected - 0.2, expected + 0.2)
		assert_int(bo.capturing_team).is_equal(MapDef.TEAM_NEUTRAL)


func test_long_overtime_window_above_threshold_and_reentry_keeps_progress() -> void:
	var sys := _system()
	var mid := sys.find(&"s_mid")
	mid.capturing_team = C
	mid.progress = 0.8
	sys.step(DT, [_hero(mid.def.position, C)])
	var p := mid.progress
	_run(sys, [], 9.9)
	assert_float(mid.progress).is_equal(p)
	sys.step(DT, [_hero(mid.def.position, C)])
	assert_float(mid.progress).is_greater(p)


func test_defence_event_when_progress_from_half_decays_to_zero() -> void:
	var sys := _system()
	var bo := sys.find(&"s_bo")
	sys.find(&"s_mid").owner = C
	bo.capturing_team = C
	bo.progress = 0.55
	sys.step(DT, [_hero(bo.def.position, C)])
	var defender := _hero(bo.def.position, S, 42)
	var got: Array = []
	for i in 2000:
		sys.step(DT, [defender], i)
		got.append_array(sys.events)
		if bo.progress == 0.0:
			break
	assert_int(got.size()).is_equal(1)
	var ev: ObjectiveEvent = got[0]
	assert_int(ev.kind).is_equal(ObjectiveEvent.Kind.DEFENCE)
	assert_int(ev.new_team).is_equal(S)
	assert_array(Array(ev.participants)).contains([42])
	assert_int(ev.lumen_each).is_equal(60)


# ---- C3 adjacency ------------------------------------------------------------

func test_c3_rejects_attack_without_the_adjacent_hardpoint() -> void:
	# AC 6: Concord cannot work Scrap Bazaar (S Outer) while the Mid is not Concord's.
	var sys := _system()
	var bo := sys.find(&"s_bo")
	assert_bool(sys.eligible(0, 3, C)).is_false()
	assert_bool(bo.locked_for(C)).is_true()
	_run(sys, [_hero(bo.def.position, C), _hero(bo.def.position, C)], 20.0)
	assert_float(bo.progress).is_equal(0.0)
	assert_int(bo.owner).is_equal(S)
	# Syndicate cannot hit Concord's Inner without Concord's Outer.
	assert_bool(sys.eligible(0, 0, S)).is_false()
	# Mid needs no prerequisite; own Inner always adjacent to own HQ.
	assert_bool(sys.eligible(0, 2, C)).is_true()
	assert_bool(sys.eligible(0, 2, S)).is_true()
	# Holding the Mid unlocks the enemy Outer.
	sys.find(&"s_mid").owner = C
	_run(sys, [_hero(bo.def.position, C)], 1.0)
	assert_bool(bo.locked_for(C)).is_false()
	assert_float(bo.progress).is_greater(0.0)


func test_losing_the_prerequisite_mid_task_drains_at_double_decay() -> void:
	var sys := _system()
	var bo := sys.find(&"s_bo")
	var mid := sys.find(&"s_mid")
	mid.owner = C
	bo.capturing_team = C
	bo.progress = 0.5
	mid.owner = S  # prerequisite lost
	var srcs := [_hero(bo.def.position, C)]
	_run(sys, srcs, 1.0)
	# No Overtime: 2 x 0.5/65 per second, attacker presence ignored.
	assert_float(bo.progress).is_equal_approx(0.5 - 2.0 * 0.5 / 65.0, 1e-3)


func test_flip_goes_straight_to_the_capturing_team_with_participants() -> void:
	var sys := _system()
	var mid := sys.find(&"s_mid")
	mid.owner = C
	var bo := sys.find(&"s_bo")
	var flips: Array = []
	sys.hardpoint_flipped.connect(func(h: HardpointSim, o: int, n: int) -> void: flips.append([h.def.id, o, n]))
	var got: Array = []
	var srcs := [_hero(bo.def.position, C, 7)]
	for i in 30 * 200:
		sys.step(DT, srcs, i)
		got.append_array(sys.events)
		if bo.owner == C:
			break
	assert_int(bo.owner).is_equal(C)
	assert_array(flips).is_equal([[&"s_bo", S, C]])
	var ev: ObjectiveEvent = got[0]
	assert_int(ev.kind).is_equal(ObjectiveEvent.Kind.FLIP)
	assert_array(Array(ev.participants)).is_equal([7])
	assert_int(ev.lumen_each).is_equal(120)
	assert_int(ev.lumen_team).is_equal(40)


# ---- neutral Mid, heroless, Severed -------------------------------------------

func test_neutral_mid_other_team_progress_drains_first_at_double_decay() -> void:
	var sys := _system()
	var mid := sys.find(&"s_mid")
	mid.capturing_team = C
	mid.progress = 0.3
	_run(sys, [_hero(mid.def.position, S)], 1.0)
	assert_int(mid.capturing_team).is_equal(C)
	assert_float(mid.progress).is_equal_approx(0.3 - 2.0 * 0.5 / 60.0, 1e-3)
	_run(sys, [_hero(mid.def.position, S)], 20.0)
	assert_int(mid.capturing_team).is_equal(S)
	assert_float(mid.progress).is_greater(0.0)


func test_heroless_force_cannot_complete_an_inner() -> void:
	var sys := _system()
	var ai := sys.find(&"s_ai")  # Concord Inner
	sys.find(&"s_ao").owner = S
	_run(sys, _wardlings(ai.def.position, S, 6), 400.0)
	assert_int(ai.owner).is_equal(C)
	assert_float(ai.progress).is_equal_approx(0.99, 1e-6)


func test_severed_hardpoint_retakes_faster() -> void:
	# Concord holds Scrap Bazaar but Syndicate retook the Mid: Bazaar is Severed (x0.75).
	var sys := _system()
	sys.find(&"s_bo").owner = C
	sys.find(&"s_mid").owner = S
	var bo := sys.find(&"s_bo")
	sys.step(DT, [])
	assert_bool(bo.severed).is_true()
	var t := _run_until_flip(sys, bo, [_hero(bo.def.position, S)], 200.0)
	assert_float(t).is_between(65.0 * 0.75 / 0.64 - 0.5, 65.0 * 0.75 / 0.64 + 0.5)


# ---- C4 presence ----------------------------------------------------------------

func test_ai_presence_capped_at_3_per_team_heroes_uncapped() -> void:
	var sys := _system()
	var mid := sys.find(&"s_mid")
	var p := mid.def.position
	sys.step(DT, _wardlings(p, C, 8))
	assert_float(mid.presence[C]).is_equal(3.0)
	sys.step(DT, _wardlings(p, C, 8) + [_hero(p, C)])
	assert_float(mid.presence[C]).is_equal(4.0)  # F1 example: 1 + min(3.0, 5.5)
	var five := []
	for i in 5:
		five.append(_hero(p, S))
	sys.step(DT, five + _wardlings(p, S, 4))
	assert_float(mid.presence[S]).is_equal(7.0)
	# Dead and out-of-zone sources count 0.
	var dead := PresenceSource.at(p, C, PresenceSource.HERO_WEIGHT, true)
	dead.alive_check = func() -> bool: return false
	sys.step(DT, [dead, _hero(p + Vector3(0, 0, 13.0), C)])
	assert_float(mid.presence[C]).is_equal(0.0)


func test_duck_typed_presence_source_is_counted() -> void:
	var sys := _system()
	var mid := sys.find(&"s_mid")
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	n.global_position = mid.def.position
	var src := PresenceSource.for_node(n, S)
	sys.step(DT, [src])
	assert_float(mid.presence[S]).is_equal(0.5)
	n.free()
	sys.step(DT, [src])
	assert_float(mid.presence[S]).is_equal(0.0)


func test_server_world_presence_registration_is_idempotent() -> void:
	var w: ServerWorld = auto_free(ServerWorld.new())
	var src := PresenceSource.at(Vector3.ZERO, C)
	w.register_presence_source(src)
	w.register_presence_source(src)
	assert_int(w.presence_sources().size()).is_equal(1)
	w.unregister_presence_source(src)
	assert_int(w.presence_sources().size()).is_equal(0)


func test_staged_hold_durations_keep_task_kind_in_data() -> void:
	var sys := _system()
	var ai := sys.find(&"s_ai")
	assert_int(ai.def.task).is_equal(HardpointDef.TaskKind.BREACH)
	assert_int(ai.task).is_equal(HardpointDef.TaskKind.HOLD)
	assert_float(ai.base_s).is_equal(75.0)
	assert_float(sys.find(&"s_ao").base_s).is_equal(65.0)
	assert_float(sys.find(&"s_mid").base_s).is_equal(60.0)
