extends GdUnitTestSuite
## E14 Plant and Breach rules (match-flow-and-map.md §3.4 Plant / Breach, F3,
## F4, §9 ACs 6-8) on the slice map with the tasks live (no Hold staging):
## Cell Cradle, 1 s pickup, carrier speed, 3 s plant channel, F3 charge (half
## while out-numbered), 6 s defuse, drop on death / dash, 15 s drop life + 10 s
## Cradle refill, touch pickup and disperse; Ward Generator HP × D_s, the shield
## (zone and out-numbered), 8 s regen delay at 4 %/s, the 20 s hold after the
## breach, its 15 s idle reset, and the Inner breach exposing the Uplink.

const MAP_PATH := "res://assets/data/match/map_slice_lane.tres"
const DT: float = 1.0 / 30.0
const C := MapDef.TEAM_CONCORD
const S := MapDef.TEAM_SYNDICATE
const HERO_C: int = 11
const HERO_C2: int = 12
const HERO_S: int = 21

var _rules: MatchRulesDef
var _sys: ObjectiveSystem


func before_test() -> void:
	_rules = MatchRulesDef.new()
	_rules.stage_all_as_hold = false
	_sys = ObjectiveSystem.new(load(MAP_PATH) as MapDef, _rules)


func _hero_src(pos: Vector3, team: int, id: int) -> PresenceSource:
	var s := PresenceSource.at(pos, team, PresenceSource.HERO_WEIGHT, true)
	s.net_id = id
	return s


func _wardlings(pos: Vector3, team: int, n: int) -> Array:
	var out := []
	for i in n:
		out.append(PresenceSource.at(pos + Vector3(i * 0.3, 0.0, 0.0), team))
	return out


## Steps `seconds` with the same sources and actors; returns the events seen.
func _run(seconds: float, sources: Array = [], actors: Array = []) -> Array:
	var evs := []
	for i in roundi(seconds / DT):
		_sys.step(DT, sources, i, actors)
		evs.append_array(_sys.events)
	return evs


## Steps until `cond` holds (max `max_s`); returns the seconds taken or -1.
func _until(cond: Callable, max_s: float, sources: Array = [], actors: Array = []) -> float:
	var t := 0
	while t * DT < max_s:
		_sys.step(DT, sources, t, actors)
		t += 1
		if cond.call():
			return t * DT
	return -1.0


# ---- Plant ------------------------------------------------------------------

func test_tasks_run_as_authored_when_not_staged() -> void:
	assert_int(_sys.find(&"s_ai").task).is_equal(HardpointDef.TaskKind.BREACH)
	assert_int(_sys.find(&"s_ao").task).is_equal(HardpointDef.TaskKind.PLANT)
	assert_int(_sys.find(&"s_mid").task).is_equal(HardpointDef.TaskKind.HOLD)
	assert_float(_sys.find(&"s_ai").base_s).is_equal(20.0)
	assert_float(_sys.find(&"s_bo").base_s).is_equal(75.0)


func test_cradle_offers_a_cell_only_to_an_eligible_attacker() -> void:
	var bo := _sys.find(&"s_bo")
	_run(1.0)
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.NONE)  # Concord does not hold the Mid
	_sys.debug_set_owner(&"s_mid", C)
	_run(DT)
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.CRADLE)
	assert_int(bo.cell_team).is_equal(C)
	assert_vector(bo.cell_pos).is_equal(bo.def.cradle_for(C))
	# The Concord Cradle for S-BO sits at the Mid (the adjacent node toward Concord).
	assert_float(Vector2(bo.cell_pos.x - _sys.find(&"s_mid").def.position.x,
		bo.cell_pos.z - _sys.find(&"s_mid").def.position.z).length()).is_less(6.0)


func test_pickup_is_a_1_s_interact_and_the_carrier_moves_at_90_percent() -> void:
	_sys.debug_set_owner(&"s_mid", C)
	var bo := _sys.find(&"s_bo")
	_run(DT)
	var a := TaskActor.make(HERO_C, C, bo.cell_pos, true)
	_run(0.9, [], [a])
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.CRADLE)
	assert_float(bo.channel_t).is_equal_approx(0.9, DT)
	a.interact = false  # letting go resets the channel
	_run(DT, [], [a])
	assert_float(bo.channel_t).is_equal(0.0)
	a.interact = true
	var t := _until(func() -> bool: return bo.cell_state == HardpointSim.CellState.CARRIED, 2.0, [], [a])
	assert_float(t).is_equal_approx(_rules.cell_pickup_s, DT + 1e-4)
	assert_int(bo.carrier_id).is_equal(HERO_C)
	assert_object(_sys.carried_by(HERO_C)).is_same(bo)
	assert_float(_sys.move_speed_mult(HERO_C)).is_equal(0.9)
	assert_float(_sys.move_speed_mult(HERO_C2)).is_equal(1.0)
	# The Cell follows the carrier.
	a.position += Vector3(0.0, 0.0, -20.0)
	_run(DT, [], [a])
	assert_vector(bo.cell_pos).is_equal(a.position)


func test_plant_is_a_3_s_channel_inside_the_zone_then_charge_follows_f3() -> void:
	_sys.debug_set_owner(&"s_mid", C)
	var bo := _sys.find(&"s_bo")
	_sys.debug_set_cell(&"s_bo", HardpointSim.CellState.CARRIED, C, HERO_C)
	# Outside the zone, interact does nothing.
	var a := TaskActor.make(HERO_C, C, bo.def.position + Vector3(0.0, 0.0, 15.0), true)
	_run(4.0, [], [a])
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.CARRIED)
	a.position = bo.def.position + Vector3(2.0, 0.0, 0.0)
	var src := [_hero_src(a.position, C, HERO_C)]
	var t := _until(func() -> bool: return bo.cell_state == HardpointSim.CellState.PLANTED, 5.0, src, [a])
	assert_float(t).is_equal_approx(_rules.plant_channel_s, DT + 1e-4)
	assert_object(_sys.carried_by(HERO_C)).is_null()
	assert_float(_sys.move_speed_mult(HERO_C)).is_equal(1.0)
	assert_int(bo.planter_id).is_equal(HERO_C)
	# F3: charge = K_hl / (T_base × D_s × K_sev) = 1/75 per second with the hero in the zone.
	a.interact = false
	var flips := []
	_sys.hardpoint_flipped.connect(func(h: HardpointSim, _o: int, n: int) -> void: flips.append([h.def.id, n]))
	var took := _until(func() -> bool: return bo.owner == C, 90.0, src, [a])
	assert_float(took).is_between(75.0 - 1.0, 75.0 + 1.0)
	assert_array(flips).is_equal([[&"s_bo", C]])
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.NONE)


func test_planter_is_a_capture_participant() -> void:
	_sys.debug_set_owner(&"s_mid", C)
	var bo := _sys.find(&"s_bo")
	_sys.debug_set_cell(&"s_bo", HardpointSim.CellState.PLANTED, C, HERO_C)
	bo.progress = 0.99
	bo.capturing_team = C
	var evs := _run(2.0)  # nobody in the zone: heroless charge still completes (Outer)
	var flip: ObjectiveEvent = null
	for e in evs:
		if e.kind == ObjectiveEvent.Kind.FLIP:
			flip = e
	assert_object(flip).is_not_null()
	assert_bool(flip.participants.has(HERO_C)).is_true()


func test_charge_halves_while_outnumbered_and_with_no_attacking_hero() -> void:
	_sys.debug_set_owner(&"s_mid", C)
	var bo := _sys.find(&"s_bo")
	_sys.debug_set_cell(&"s_bo", HardpointSim.CellState.PLANTED, C, HERO_C)
	var p := bo.def.position
	# 1 attacker hero vs 2 defender heroes: half rate.
	_run(10.0, [_hero_src(p, C, HERO_C), _hero_src(p, S, HERO_S), _hero_src(p, S, HERO_S + 1)])
	assert_float(bo.progress).is_equal_approx(10.0 / 75.0 * 0.5, 1e-3)
	assert_bool(bo.contested).is_true()
	# Wardlings only (no attacking hero): K_hl = 0.5.
	bo.progress = 0.0
	_run(10.0, _wardlings(p, C, 3))
	assert_float(bo.progress).is_equal_approx(10.0 / 75.0 * 0.5, 1e-3)


func test_defuse_is_a_6_s_defender_channel_then_overtime_and_decay() -> void:
	_sys.debug_set_owner(&"s_mid", C)
	var bo := _sys.find(&"s_bo")
	_sys.debug_set_cell(&"s_bo", HardpointSim.CellState.PLANTED, C, HERO_C)
	bo.progress = 0.6
	bo.capturing_team = C
	var p := bo.def.position
	var d := TaskActor.make(HERO_S, S, p + Vector3(1.0, 0.0, 0.0), true)
	var src := [_hero_src(d.position, S, HERO_S)]
	var evs := []
	var t := 0
	while bo.cell_state == HardpointSim.CellState.PLANTED and t < 300:
		_sys.step(DT, src, t, [d])
		evs.append_array(_sys.events)
		t += 1
	assert_float(t * DT).is_equal_approx(_rules.defuse_channel_s, DT + 1e-4)
	assert_int(bo.cells_defused).is_equal(1)
	var defences := evs.filter(func(e: ObjectiveEvent) -> bool: return e.kind == ObjectiveEvent.Kind.DEFENCE)
	assert_int(defences.size()).is_equal(1)
	assert_bool((defences[0] as ObjectiveEvent).participants.has(HERO_S)).is_true()
	# While planted the charge ran at a quarter: out-numbered (0 vs 1) and no attacking hero (K_hl).
	var p_after := bo.progress
	assert_float(p_after).is_equal_approx(0.6 + 6.0 / 75.0 * 0.25, 2e-3)
	# Overtime 5 s (P < 0.75), then decay 1/(T_base) with a defender present (F3).
	d.interact = false
	_run(4.9, src, [d])
	assert_float(bo.progress).is_equal_approx(p_after, 1e-6)
	_run(10.1, src, [d])
	assert_float(bo.progress).is_equal_approx(p_after - 10.0 / 75.0, 2e-3)


func test_defuse_breaks_when_the_defender_lets_go_or_is_stunned() -> void:
	_sys.debug_set_owner(&"s_mid", C)
	var bo := _sys.find(&"s_bo")
	_sys.debug_set_cell(&"s_bo", HardpointSim.CellState.PLANTED, C, HERO_C)
	var d := TaskActor.make(HERO_S, S, bo.def.position, true)
	_run(5.0, [], [d])
	d.can_channel = false  # crowd control
	_run(DT, [], [d])
	assert_float(bo.channel_t).is_equal(0.0)
	d.can_channel = true
	_run(5.0, [], [d])
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.PLANTED)


func test_carrier_death_drops_the_cell_which_returns_to_the_cradle_15_plus_10_s_later() -> void:
	_sys.debug_set_owner(&"s_mid", C)
	var bo := _sys.find(&"s_bo")
	_sys.debug_set_cell(&"s_bo", HardpointSim.CellState.CARRIED, C, HERO_C)
	var at := bo.def.position + Vector3(0.0, 0.0, 30.0)
	var a := TaskActor.make(HERO_C, C, at)
	_run(DT, [], [a])
	a.alive = false  # the carrier dies (AC 7)
	_run(DT, [], [a])
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.DROPPED)
	assert_vector(bo.cell_pos).is_equal(at)
	assert_object(_sys.carried_by(HERO_C)).is_null()
	var gone := _until(func() -> bool: return bo.cell_state == HardpointSim.CellState.NONE, 20.0, [], [a])
	assert_float(gone).is_equal_approx(_rules.cell_drop_life_s, DT + 1e-4)
	var back := _until(func() -> bool: return bo.cell_state == HardpointSim.CellState.CRADLE, 20.0, [], [a])
	assert_float(back).is_equal_approx(_rules.cradle_respawn_s, DT + 1e-4)


func test_dash_drops_the_cell_and_an_attacker_touch_picks_it_up() -> void:
	_sys.debug_set_owner(&"s_mid", C)
	var bo := _sys.find(&"s_bo")
	_sys.debug_set_cell(&"s_bo", HardpointSim.CellState.CARRIED, C, HERO_C)
	var a := TaskActor.make(HERO_C, C, Vector3(0.0, 0.0, -240.0))
	a.mobility = true
	_run(DT, [], [a])
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.DROPPED)
	var b := TaskActor.make(HERO_C2, C, Vector3(0.0, 0.0, -240.0) + Vector3(1.0, 0.0, 0.0))
	_run(DT, [], [b])
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.CARRIED)
	assert_int(bo.carrier_id).is_equal(HERO_C2)


func test_a_defender_standing_on_a_dropped_cell_for_2_s_disperses_it() -> void:
	_sys.debug_set_owner(&"s_mid", C)
	var bo := _sys.find(&"s_bo")
	_sys.debug_set_cell(&"s_bo", HardpointSim.CellState.CARRIED, C, HERO_C)
	var at := Vector3(0.0, 0.0, -240.0)
	_run(DT, [], [TaskActor.make(HERO_C, C, at, false, false)])
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.DROPPED)
	var d := TaskActor.make(HERO_S, S, at + Vector3(0.5, 0.0, 0.0))
	var t := _until(func() -> bool: return bo.cell_state == HardpointSim.CellState.NONE, 5.0, [], [d])
	assert_float(t).is_equal_approx(_rules.cell_disperse_s, DT + 1e-4)
	assert_float(bo.cell_timer).is_equal_approx(_rules.cradle_respawn_s, DT + 1e-4)


func test_losing_eligibility_dissolves_the_cell() -> void:
	_sys.debug_set_owner(&"s_mid", C)
	var bo := _sys.find(&"s_bo")
	_sys.debug_set_cell(&"s_bo", HardpointSim.CellState.CARRIED, C, HERO_C)
	_run(DT, [], [TaskActor.make(HERO_C, C, Vector3.ZERO)])
	_sys.debug_set_owner(&"s_mid", S)
	_run(DT, [], [TaskActor.make(HERO_C, C, Vector3.ZERO)])
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.NONE)
	assert_object(_sys.carried_by(HERO_C)).is_null()


func test_waves_target_a_plant_node_only_with_an_allied_cell() -> void:
	_sys.debug_set_owner(&"s_mid", C)
	_run(DT)
	var bo := _sys.find(&"s_bo")
	assert_int(_sys.front.front_for(C, 0)).is_equal(bo.index)  # heroes push it
	assert_int(_sys.front.front_for(C, 0, true)).is_equal(_sys.find(&"s_mid").index)  # waves hold the Mid
	_sys.debug_set_cell(&"s_bo", HardpointSim.CellState.CARRIED, C, HERO_C)
	assert_int(_sys.front.front_for(C, 0, true)).is_equal(bo.index)


# ---- Breach -----------------------------------------------------------------

func _breach_ready() -> HardpointSim:
	_sys.debug_set_owner(&"s_mid", C)
	_sys.debug_set_owner(&"s_bo", C)
	var bi := _sys.find(&"s_bi")
	_run(DT)
	return bi


func test_generator_hp_is_base_times_d_s_and_takes_damage_only_from_the_eligible_attacker_inside() -> void:
	var bi := _breach_ready()
	assert_float(bi.generator_max()).is_equal(6000.0)
	assert_float(bi.generator_hp()).is_equal(6000.0)
	var inside := bi.def.position + Vector3(3.0, 0.0, 0.0)
	var outside := bi.def.position + Vector3(0.0, 0.0, 20.0)
	assert_float(_sys.damage_generator(bi, 100.0, C, outside)).is_equal(0.0)  # shield: outside the zone
	assert_float(_sys.damage_generator(bi, 100.0, S, inside)).is_equal(0.0)  # the owner
	assert_float(_sys.damage_generator(bi, 100.0, C, inside)).is_equal(100.0)
	assert_float(bi.generator_hp()).is_equal_approx(5900.0, 1e-3)
	# Ineligible (Concord loses S-BO): ignored (AC 6).
	_sys.debug_set_owner(&"s_bo", S)
	assert_float(_sys.damage_generator(bi, 100.0, C, inside)).is_equal(0.0)
	# D_s scales HP; the remaining fraction is kept (F4, F5).
	_sys.duration_scale = 0.85
	_run(DT)
	assert_float(bi.generator_max()).is_equal_approx(5100.0, 1e-3)
	assert_float(bi.generator_hp()).is_equal_approx(5900.0 * 0.85, 0.5)


func test_shield_blocks_all_damage_while_defenders_outnumber_attackers() -> void:
	var bi := _breach_ready()
	var p := bi.def.position
	var src := [_hero_src(p, C, HERO_C), _hero_src(p, S, HERO_S), _hero_src(p, S, HERO_S + 1)]
	_run(DT, src)
	assert_bool(bi.gen_shielded).is_true()
	assert_float(_sys.damage_generator(bi, 500.0, C, p)).is_equal(0.0)
	_run(DT, [_hero_src(p, C, HERO_C), _hero_src(p, S, HERO_S)])  # equal: open
	assert_bool(bi.gen_shielded).is_false()
	assert_float(_sys.damage_generator(bi, 500.0, C, p)).is_equal(500.0)


func test_generator_regenerates_4_percent_per_second_after_8_s_idle() -> void:
	var bi := _breach_ready()
	_sys.damage_generator(bi, 3000.0, C, bi.def.position)
	_run(7.9)
	assert_float(bi.generator_hp()).is_equal_approx(3000.0, 1e-3)
	_run(5.1)  # 8 s delay passed at 8.0; 5 s of regen
	assert_float(bi.generator_hp()).is_equal_approx(3000.0 + 0.04 * 6000.0 * 5.0, 6000.0 * 0.04 * DT * 2.0)


func test_breach_timing_matches_f4_then_the_hold_flips_and_exposes_the_uplink() -> void:
	var bi := _breach_ready()
	var p := bi.def.position
	# Reference push: 1 hero + 3 Wardlings (Δ 2.5 -> M 1.0) dealing 300 DPS from inside.
	var src: Array = [_hero_src(p, C, HERO_C)]
	src.append_array(_wardlings(p, C, 3))
	var t := 0
	while bi.owner == S and t < 60 * 30:
		if bi.breach_phase == 1:
			_sys.damage_generator(bi, 300.0 * DT, C, p)
		_sys.step(DT, src, t)
		t += 1
	# F4: t_breach = HP / DPS + 20 × D_s / M(Δ) = 6000/300 + 20/1.0 = 40 s.
	assert_float(t * DT).is_between(40.0 - 1.0, 40.0 + 1.0)
	assert_int(bi.owner).is_equal(C)
	assert_int(bi.breach_phase).is_equal(1)
	assert_float(bi.gen_frac).is_equal(1.0)  # the new owner's Generator is fresh
	assert_int(bi.generators_destroyed).is_equal(1)
	var m := MatchRules.new(_rules, _sys)
	assert_bool(m.exposed_now(S)).is_true()


func test_phase_2_idle_at_zero_for_15_s_restores_the_generator() -> void:
	var bi := _breach_ready()
	_sys.damage_generator(bi, 6000.0, C, bi.def.position)
	assert_int(bi.breach_phase).is_equal(2)
	_run(14.9)
	assert_int(bi.breach_phase).is_equal(2)
	_run(0.2)
	assert_int(bi.breach_phase).is_equal(1)
	assert_float(bi.gen_frac).is_equal(1.0)


func test_phase_2_attacker_progress_holds_the_breach_open() -> void:
	var bi := _breach_ready()
	var p := bi.def.position
	_sys.damage_generator(bi, 6000.0, C, p)
	_run(5.0, [_hero_src(p, C, HERO_C)])
	assert_float(bi.progress).is_greater(0.0)
	_run(20.0)  # attacker left: Overtime then decay, no reset while P > 0
	assert_int(bi.breach_phase).is_equal(2)
