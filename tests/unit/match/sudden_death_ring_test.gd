extends GdUnitTestSuite
## W16-SDWATER: the client ring (SuddenDeathRing) matches the server ring.

const RULES_PATH := "res://assets/data/match/match_rules_front.tres"
const MAP_PATH := "res://assets/data/match/map_front.tres"


func _rules() -> MatchRulesDef:
	return load(RULES_PATH) as MatchRulesDef


func _snapshot_of(m: MatchRules) -> SnapshotData.MatchState:
	var ms := SnapshotData.MatchState.new()
	ms.phase = m.phase
	ms.time_s = m.time_s
	ms.next_phase_s = m.next_phase_time()
	return ms


func test_client_radius_matches_server_over_time() -> void:
	var m := MatchRules.new(_rules())
	m.phase = MatchRules.Phase.SUDDEN_DEATH
	m.time_s = 3600.0
	m.clock_scale = 4.0
	var ring := SuddenDeathRing.new(_rules(), Vector3.ZERO)
	var t := 0.0
	while m.phase == MatchRules.Phase.SUDDEN_DEATH:  # through the shrink and the hold
		m.step(1.0 / 30.0)
		t += 1.0 / 30.0
		if m.phase != MatchRules.Phase.SUDDEN_DEATH:
			break  # the draw cap ended it
		ring.apply(_snapshot_of(m))
		assert_float(ring.radius()).is_equal_approx(m.sudden_death_radius(), 0.02)


func test_ring_inactive_outside_sudden_death() -> void:
	var m := MatchRules.new(_rules())
	m.phase = MatchRules.Phase.SKIRMISH
	var ring := SuddenDeathRing.new(_rules())
	ring.apply(_snapshot_of(m))
	assert_bool(ring.active).is_false()
	assert_bool(ring.is_outside(Vector3(500, 0, 500))).is_false()
	assert_object(ring.safe_point(Vector3(500, 0, 500))).is_null()


func test_inside_outside_and_safe_point() -> void:
	var r := _rules()
	var ring := SuddenDeathRing.new(r, Vector3(10, 5, -20))
	ring.active = true
	ring.elapsed_s = 0.0
	var start := r.sudden_death_ring_start_m
	assert_bool(ring.is_outside(Vector3(10 + start - 1.0, 0, -20))).is_false()
	assert_bool(ring.is_outside(Vector3(10 + start + 1.0, 0, -20))).is_true()
	var sp: Variant = ring.safe_point(Vector3(10 + start + 1.0, 2.0, -20))
	assert_vector(sp).is_equal(Vector3(10, 2.0, -20))
	assert_object(ring.safe_point(Vector3(10, 0, -20))).is_null()


func test_ring_centre_is_the_maps_mid_plaza() -> void:
	var md := load(MAP_PATH) as MapDef
	var c := ClientWorld.new()
	c.setup_objectives(md)
	assert_vector(c.sudden_death.centre).is_equal(md.mid_plaza_center)
	c.free()


func test_shimmer_follows_effects_intensity_and_reduce_motion() -> void:
	assert_float(SuddenDeathView.shimmer_amount(0.4, false)).is_equal(0.4)
	assert_float(SuddenDeathView.shimmer_amount(1.0, true)).is_equal(0.0)
	assert_float(SuddenDeathView.shimmer_amount(0.0, false)).is_equal(0.0)


func test_warning_only_outside_and_alive() -> void:
	var ring := SuddenDeathRing.new(_rules(), Vector3.ZERO)
	ring.active = true
	var far := Vector3(500, 0, 0)
	assert_bool(RingWarning.shows(ring, far, false)).is_true()
	assert_bool(RingWarning.shows(ring, far, true)).is_false()
	assert_bool(RingWarning.shows(ring, Vector3.ZERO, false)).is_false()
	assert_bool(RingWarning.shows(null, far, false)).is_false()
