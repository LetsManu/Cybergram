extends GdUnitTestSuite
## E9 match flow (match-flow-and-map.md §3.1, §3.6, F5, F6, F8; Canon C7-C11;
## M1 slice: 30:00 cap, Surge I only, Time-out = 1-lane Incursion -> Uplink % -> draw).

const MAP_PATH := "res://assets/data/match/map_slice_lane.tres"
const RULES_PATH := "res://assets/data/match/match_rules_slice.tres"
const C := MapDef.TEAM_CONCORD
const S := MapDef.TEAM_SYNDICATE
const N := MapDef.TEAM_NEUTRAL
const HZ: int = 30
const DT: float = 1.0 / 30.0

var _sys: ObjectiveSystem


func _rules() -> MatchRulesDef:
	return load(RULES_PATH) as MatchRulesDef


## Uplink Integrity of the rules under test (slice data; the Canon C7 default
## 33,000 is checked in test_uplinks_are_built_at_the_map_anchors_with_c7_integrity).
func _integrity() -> float:
	return _rules().uplink_integrity


## MatchRules on the slice map with both Uplinks (nodes freed by the suite).
func _match(rules: MatchRulesDef = null) -> MatchRules:
	var r := rules if rules != null else _rules()
	var md := load(MAP_PATH) as MapDef
	_sys = ObjectiveSystem.new(md, r)
	var m := MatchRules.new(r, _sys)
	for u in m.build_uplinks(md):
		auto_free(u)
	return m


func _owners(owners: Array) -> void:
	for i in owners.size():
		(_sys.lanes[0][i] as HardpointSim).owner = owners[i]


## Steps until `m.phase` == `p` (max `limit` ticks); returns the clock at entry or -1.
func _run_until(m: MatchRules, p: int, limit: int) -> float:
	for i in limit:
		m.step(DT)
		if m.phase == p:
			return m.time_s
		if m.is_over():
			break
	return -1.0


# --- Phases -------------------------------------------------------------------

func test_slice_phases_fire_at_the_right_times_within_one_tick() -> void:
	var m := _match()
	var seen: Array = []
	m.phase_changed.connect(func(_o: int, p: int) -> void: seen.append([p, m.time_s]))
	assert_int(m.phase).is_equal(MatchRules.Phase.LOAD)
	m.step(DT)
	assert_int(m.phase).is_equal(MatchRules.Phase.DEPLOY)
	assert_float(m.time_s).is_equal(0.0)
	assert_float(_run_until(m, MatchRules.Phase.SKIRMISH, HZ * 70)).is_between(60.0, 60.0 + DT + 1e-4)
	assert_float(_run_until(m, MatchRules.Phase.SURGE_I, HZ * 900)).is_between(900.0, 900.0 + DT + 1e-3)
	assert_float(_run_until(m, MatchRules.Phase.END, HZ * 960)).is_between(1800.0, 1800.0 + DT + 1e-3)
	# Slice: Surge II (30:00) and Drought (45:00) are at/after the 30:00 cap -> never start.
	var phases: Array = seen.map(func(e: Array) -> int: return e[0])
	assert_array(phases).is_equal([MatchRules.Phase.DEPLOY, MatchRules.Phase.SKIRMISH, MatchRules.Phase.SURGE_I,
		MatchRules.Phase.TIME_OUT, MatchRules.Phase.END])


func test_standard_rules_run_surge_ii_and_drought_before_the_60_minute_cap() -> void:
	var m := _match(MatchRulesDef.new())  # defaults = standard match (cap 60:00)
	m.clock_scale = 30.0  # debug clock: 1 tick = 1 match second
	m.step(DT)
	assert_float(_run_until(m, MatchRules.Phase.SURGE_II, 2000)).is_between(1800.0, 1801.0)
	assert_float(m.task_duration_scale()).is_equal_approx(0.70, 1e-6)
	assert_int(m.wardling_tier).is_equal(3)
	assert_float(_run_until(m, MatchRules.Phase.DROUGHT, 1000)).is_between(2700.0, 2701.0)
	assert_float(_run_until(m, MatchRules.Phase.END, 1000)).is_between(3600.0, 3601.0)


func test_clock_scale_and_debug_start_time() -> void:
	var m := _match()
	m.clock_scale = 4.0
	m.debug_start_s = 1000.0
	m.step(DT)
	assert_int(m.phase).is_equal(MatchRules.Phase.SURGE_I)  # jumps straight through Skirmish
	m.step(DT)
	assert_float(m.time_s).is_equal_approx(1000.0 + 4.0 * DT, 1e-4)
	assert_float(m.next_phase_time()).is_equal(1800.0)


# --- Deploy and Surge ---------------------------------------------------------

func test_deploy_locks_the_mid_and_skirmish_unlocks_it() -> void:
	var m := _match()
	var mid: HardpointSim = _sys.lanes[0][2]
	m.step(DT)  # Deploy
	assert_bool(_sys.eligible(0, 2, C)).is_false()
	assert_bool(_sys.eligible(0, 2, S)).is_false()
	# A Concord hero standing on the Mid during Deploy makes no progress.
	var hero := PresenceSource.new()
	hero.team = C
	hero.is_hero = true
	hero.presence_weight = PresenceSource.HERO_WEIGHT
	hero.position = mid.def.position
	for i in HZ * 5:
		_sys.step(DT, [hero])
		m.step(DT)
	assert_float(mid.progress).is_equal(0.0)
	assert_bool(mid.locked_for(C)).is_true()
	_run_until(m, MatchRules.Phase.SKIRMISH, HZ * 60)
	_sys.step(DT, [hero])
	assert_bool(mid.locked_for(C)).is_false()
	assert_float(mid.progress).is_greater(0.0)


func test_surge_i_scales_task_duration_and_raises_the_wardling_tier() -> void:
	var m := _match()
	var surges: Array = []
	m.surge_started.connect(func(i: int, s: float) -> void: surges.append([i, s]))
	m.clock_scale = 30.0
	m.step(DT)
	assert_float(_sys.duration_scale).is_equal(1.0)
	_run_until(m, MatchRules.Phase.SURGE_I, 1000)
	assert_float(_sys.duration_scale).is_equal_approx(0.85, 1e-6)
	assert_int(m.wardling_tier).is_equal(2)
	assert_array(surges).has_size(1)
	assert_int(surges[0][0]).is_equal(0)
	# F2: the same push captures a Hold 1/0.85 faster.
	var r := _rules()
	assert_float(HardpointSim.capture_rate(1.0, true, 60.0, _sys.duration_scale, 1.0, r)) \
		.is_equal_approx(HardpointSim.capture_rate(1.0, true, 60.0, 1.0, 1.0, r) / 0.85, 1e-6)


# --- Uplink -------------------------------------------------------------------

func test_uplinks_are_built_at_the_map_anchors_with_c7_integrity() -> void:
	var m := _match()
	var md := load(MAP_PATH) as MapDef
	assert_int(m.uplinks.size()).is_equal(2)
	for t in 2:
		var u := m.uplink_of(t)
		assert_int(u.team).is_equal(t)
		assert_vector(u.base).is_equal(md.hq(t).uplink)
		assert_float(u.integrity).is_equal(_integrity())
		assert_float(u.max_integrity).is_equal(_integrity())
	assert_float(MatchRulesDef.new().uplink_integrity).is_equal(33000.0)  # Canon C7
	var canon := MatchRules.new(MatchRulesDef.new(), null)
	for u in canon.build_uplinks(md):
		auto_free(u)
		assert_float(u.max_integrity).is_equal(33000.0)


func test_uplink_is_invulnerable_when_not_exposed() -> void:
	var m := _match()
	m.step(DT)
	var u := m.uplink_of(S)
	assert_bool(u.exposed).is_false()
	assert_float(u.apply_damage(500.0)).is_equal(0.0)
	assert_float(u.apply_damage(500.0, true)).is_equal(0.0)
	assert_float(u.integrity).is_equal(_integrity())
	assert_int(u.immune_hits).is_equal(2)


func test_uplink_exposed_when_an_inner_is_lost_and_seals_on_retake() -> void:
	var m := _match()
	m.step(DT)
	var su := m.uplink_of(S)
	var cu := m.uplink_of(C)
	# Concord takes the Mid and Syndicate's Outer: not exposed yet (Outer only counts in Drought).
	_owners([C, C, C, C, S])
	m.step(DT)
	assert_bool(su.exposed).is_false()
	# Concord takes Syndicate's Inner (S-BI): exposed on that tick.
	_owners([C, C, C, C, C])
	m.step(DT)
	assert_bool(su.exposed).is_true()
	assert_bool(cu.exposed).is_false()
	assert_float(su.apply_damage(1000.0)).is_equal(1000.0)
	# Syndicate retakes its Inner: sealed on the retake tick.
	_owners([C, C, C, C, S])
	m.step(DT)
	assert_bool(su.exposed).is_false()
	assert_float(su.apply_damage(1000.0)).is_equal(0.0)
	assert_float(su.integrity).is_equal(_integrity() - 1000.0)
	# Mirror: Syndicate holding Concord's Inner (S-AI) exposes the Concord Uplink.
	_owners([S, S, S, S, S])
	m.step(DT)
	assert_bool(cu.exposed).is_true()
	assert_bool(su.exposed).is_false()


func test_drought_widens_exposure_to_outer_on_standard_rules() -> void:
	var m := _match(MatchRulesDef.new())
	m.step(DT)
	_owners([C, C, C, C, S])
	m.step(DT)
	assert_bool(m.uplink_of(S).exposed).is_false()
	m.time_s = 2700.0
	m.step(DT)
	assert_bool(m.uplink_of(S).exposed).is_true()


func test_wardling_hits_deal_half_and_heroes_full() -> void:
	var m := _match()
	m.step(DT)
	_owners([C, C, C, C, C])
	m.step(DT)
	var u := m.uplink_of(S)
	assert_float(u.apply_damage(21.0, true)).is_equal_approx(10.5, 1e-6)
	assert_float(u.apply_damage(29.0, false)).is_equal_approx(29.0, 1e-6)
	assert_float(u.integrity).is_equal_approx(_integrity() - 39.5, 1e-3)


func test_damage_is_permanent_no_heal_no_regen() -> void:
	var m := _match()
	m.step(DT)
	_owners([C, C, C, C, C])
	m.step(DT)
	var u := m.uplink_of(S)
	u.apply_damage(5000.0)
	assert_float(u.heal(5000.0)).is_equal(0.0)
	_owners([C, C, C, C, S])  # sealed again
	for i in HZ * 30:
		m.step(DT)
	assert_float(u.integrity).is_equal(_integrity() - 5000.0)
	assert_float(u.removed_pct()).is_equal_approx(100.0 * 5000.0 / _integrity(), 1e-4)


func test_integrity_zero_ends_the_match_with_the_attacker_winning() -> void:
	var m := _match()
	for u in m.uplinks:
		u.destroyed.connect(m.on_uplink_destroyed.bind(u.team))
	var ended: Array = []
	m.match_ended.connect(func(w: int, r: int) -> void: ended.append([w, r]))
	m.step(DT)
	_owners([S, S, S, S, S])  # Syndicate pushed to Concord's Inner
	m.step(DT)
	var cu := m.uplink_of(C)
	assert_float(cu.apply_damage(_integrity() + 7000.0)).is_equal(_integrity())
	assert_bool(cu.is_destroyed()).is_true()
	assert_int(m.phase).is_equal(MatchRules.Phase.END)
	assert_int(m.winner).is_equal(S)
	assert_int(m.end_reason).is_equal(MatchRules.EndReason.UPLINK_DESTROYED)
	assert_array(ended).is_equal([[S, MatchRules.EndReason.UPLINK_DESTROYED]])
	# Over: exposure is cleared and the clock stops.
	var t := m.time_s
	m.step(DT)
	assert_float(m.time_s).is_equal(t)
	assert_bool(m.uplink_of(S).exposed).is_false()


# --- Time-out (slice: 1-lane Incursion -> Uplink % -> draw) -------------------

func test_incursion_depths_on_one_lane() -> void:
	_match()
	var m := MatchRules.new(_rules(), _sys)
	_owners([C, C, N, S, S])
	assert_int(m.incursion(C)).is_equal(0)
	assert_int(m.incursion(S)).is_equal(0)
	_owners([C, C, C, S, S])
	assert_int(m.incursion(C)).is_equal(1)
	_owners([C, C, C, C, S])
	assert_int(m.incursion(C)).is_equal(2)
	_owners([C, C, C, C, C])
	assert_int(m.incursion(C)).is_equal(3)
	_owners([C, S, S, S, S])  # Syndicate holds Concord's Outer
	assert_int(m.incursion(S)).is_equal(2)
	assert_int(m.incursion(C)).is_equal(0)


func test_time_out_decided_by_incursion() -> void:
	var m := _match()
	m.step(DT)
	_owners([C, C, C, S, S])  # Concord 1 - Syndicate 0
	m.time_s = 1800.0 - DT * 0.5
	m.step(DT)
	assert_int(m.phase).is_equal(MatchRules.Phase.END)
	assert_int(m.winner).is_equal(C)
	assert_int(m.end_reason).is_equal(MatchRules.EndReason.INCURSION)
	assert_array(Array(m.final_incursion)).is_equal([1, 0])


func test_time_out_incursion_tied_decided_by_uplink_damage() -> void:
	var m := _match()
	m.step(DT)
	_owners([C, C, C, C, C])
	m.step(DT)
	m.uplink_of(S).apply_damage(_integrity() * 0.124)  # Concord dealt 12.4 %
	_owners([S, S, S, S, S])
	m.step(DT)
	m.uplink_of(C).apply_damage(_integrity() * 0.05)  # Syndicate dealt 5.0 %
	_owners([C, C, N, S, S])  # Incursion 0 - 0
	m.time_s = 1800.0
	m.step(DT)
	assert_int(m.winner).is_equal(C)
	assert_int(m.end_reason).is_equal(MatchRules.EndReason.UPLINK_DAMAGE)
	assert_float(m.final_uplink_pct[0]).is_equal_approx(12.4, 1e-3)
	assert_float(m.final_uplink_pct[1]).is_equal_approx(5.0, 1e-3)


func test_time_out_tied_within_one_point_is_a_draw() -> void:
	var m := _match()
	m.step(DT)
	_owners([C, C, C, C, C])
	m.step(DT)
	m.uplink_of(S).apply_damage(_integrity() * 0.124)
	_owners([S, S, S, S, S])
	m.step(DT)
	m.uplink_of(C).apply_damage(_integrity() * 0.116)  # 0.8 point gap (GDD §6 example)
	_owners([C, C, N, S, S])
	m.time_s = 1800.0
	m.step(DT)
	assert_int(m.phase).is_equal(MatchRules.Phase.END)
	assert_int(m.winner).is_equal(N)
	assert_int(m.end_reason).is_equal(MatchRules.EndReason.DRAW)


func test_time_out_with_no_damage_and_equal_fronts_is_a_draw() -> void:
	var m := _match()
	m.step(DT)
	m.time_s = 1800.0
	m.step(DT)
	assert_int(m.end_reason).is_equal(MatchRules.EndReason.DRAW)
	assert_int(m.winner).is_equal(N)


# --- Respawn (C11 on the match clock) -----------------------------------------

func test_respawn_ticks_follow_match_minutes() -> void:
	var c := MatchRulesDef.new()  # Canon C11 (F7 table)
	assert_int(RespawnSystem.respawn_ticks_at_minutes(c, 0.0, HZ)).is_equal(180)
	assert_int(RespawnSystem.respawn_ticks_at_minutes(c, 12.0, HZ)).is_equal(324)
	assert_int(RespawnSystem.respawn_ticks_at_minutes(c, 30.0, HZ)).is_equal(540)
	assert_int(RespawnSystem.respawn_ticks_at_minutes(c, 60.0, HZ)).is_equal(900)
	var r := _rules()  # the slice's coefficients (E14 slice tuning), same formula
	for m in [0.0, 12.0, 30.0, 60.0]:
		var expect := ceili(minf(r.respawn_cap_s, r.respawn_base_s + r.respawn_per_min_s * m) * HZ - 1e-6)
		assert_int(RespawnSystem.respawn_ticks_at_minutes(r, m, HZ)).is_equal(expect)
	var m := _match()
	m.debug_start_s = 720.0
	m.step(DT)
	assert_float(m.minutes()).is_equal_approx(12.0, 1e-6)


# --- Replication --------------------------------------------------------------

func test_match_block_round_trips_and_truncation_is_rejected() -> void:
	var s := SnapshotData.new()
	s.tick = 7
	var ms := SnapshotData.MatchState.new()
	ms.phase = MatchRules.Phase.END
	ms.time_s = 1234.5
	ms.next_phase_s = -1.0
	ms.winner = S
	ms.end_reason = MatchRules.EndReason.UPLINK_DESTROYED
	for t in 2:
		var u := SnapshotData.UplinkState.new()
		u.team = t
		u.integrity = 0.0 if t == C else 31000.5
		u.max_integrity = 33000.0
		u.exposed = t == S
		ms.uplinks.append(u)
	s.match_state = ms
	var b := SnapshotCodec.encode(s)
	var d := SnapshotCodec.decode(b)
	assert_object(d).is_not_null()
	assert_object(d.match_state).is_not_null()
	assert_int(d.match_state.phase).is_equal(MatchRules.Phase.END)
	assert_float(d.match_state.time_s).is_equal(1234.5)
	assert_float(d.match_state.next_phase_s).is_equal(-1.0)
	assert_int(d.match_state.winner).is_equal(S)
	assert_int(d.match_state.end_reason).is_equal(MatchRules.EndReason.UPLINK_DESTROYED)
	assert_int(d.match_state.uplinks.size()).is_equal(2)
	assert_float(d.match_state.uplinks[1].integrity).is_equal(31000.5)
	assert_bool(d.match_state.uplinks[1].exposed).is_true()
	assert_bool(d.match_state.uplinks[0].exposed).is_false()
	assert_object(SnapshotCodec.decode(b.slice(0, b.size() - 1))).is_null()
	# A server without match flow sends no block.
	var plain := SnapshotCodec.decode(SnapshotCodec.encode(SnapshotData.new()))
	assert_object(plain).is_not_null()
	assert_object(plain.match_state).is_null()


func test_match_phase_event_round_trips() -> void:
	var events: Array[GameEvent] = [GameEvent.match_phase(MatchRules.Phase.END, -1, MatchRules.EndReason.DRAW, 1800.0)]
	var out: Array[GameEvent] = []
	assert_int(EventCodec.decode(EventCodec.encode(5, events), out)).is_equal(5)
	assert_int(out[0].kind).is_equal(GameEvent.MATCH_PHASE)
	assert_int(out[0].target_net_id).is_equal(MatchRules.Phase.END)
	assert_int(out[0].source_net_id).is_equal(0)  # winner + 1: draw
	assert_int(out[0].flags).is_equal(MatchRules.EndReason.DRAW)
