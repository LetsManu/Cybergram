extends GdUnitTestSuite
## W21-G2: Armory findability. Pure rules of the world marker (ArmoryMarkerView)
## and of the guidance waypoint (ArmoryWaypoint), the marker ring size against the
## server radius, and the minimap glyph tuning living in the .tres.

const HFOV_HALF := deg_to_rad(50.0)


func before() -> void:
	HudStrings.ensure_loaded()


func test_ring_outer_radius_is_the_server_armory_radius() -> void:
	var econ := load(GameSession.ECONOMY_RULES) as EconomyRulesDef
	var hq := HqDef.new()
	hq.team = MapDef.TEAM_CONCORD
	hq.armory = Vector3(19.0, 0.0, -17.0)
	var v: ArmoryMarkerView = auto_free(ArmoryMarkerView.new())
	v.setup(hq, null)
	assert_float(v.ring_outer_radius()).is_equal(econ.armory_radius_m)
	assert_float(v.position.x).is_equal(19.0)
	# A different server radius moves the ring with it (no hardcoded 6 m).
	var econ2 := econ.duplicate() as EconomyRulesDef
	econ2.armory_radius_m = 9.0
	var v2: ArmoryMarkerView = auto_free(ArmoryMarkerView.new())
	v2.setup(hq, null, null, econ2)
	assert_float(v2.ring_outer_radius()).is_equal(9.0)


func test_pulse_only_while_spending_and_never_with_reduced_motion() -> void:
	assert_float(ArmoryMarkerView.pulse_factor(0.3, false, false, 1.0, 0.5)).is_equal(1.0)
	assert_float(ArmoryMarkerView.pulse_factor(0.3, true, true, 1.0, 0.5)).is_equal(1.0)
	assert_float(ArmoryMarkerView.pulse_factor(0.0, true, false, 1.0, 0.5)).is_equal_approx(1.0, 1e-5)
	assert_float(ArmoryMarkerView.pulse_factor(0.5, true, false, 1.0, 0.5)).is_equal_approx(0.5, 1e-5)


func test_sign_hides_on_the_pad_and_fades_far_away() -> void:
	assert_float(ArmoryMarkerView.sign_alpha(3.0, 7.0, 160.0)).is_equal(0.0)
	assert_float(ArmoryMarkerView.sign_alpha(30.0, 7.0, 160.0)).is_equal(1.0)
	assert_float(ArmoryMarkerView.sign_alpha(160.0, 7.0, 160.0)).is_equal(0.0)
	assert_float(ArmoryMarkerView.sign_alpha(128.0, 7.0, 160.0)).is_between(0.1, 0.9)


func test_relative_angle_follows_yaw_convention() -> void:
	var o := Vector3.ZERO
	# Yaw 0 looks along -Z: a target ahead is 0, to +X is +90 deg (right).
	assert_float(ArmoryWaypoint.relative_angle(0.0, o, Vector3(0, 0, -10))).is_equal_approx(0.0, 1e-5)
	assert_float(ArmoryWaypoint.relative_angle(0.0, o, Vector3(10, 0, 0))).is_equal_approx(PI * 0.5, 1e-5)
	assert_float(ArmoryWaypoint.relative_angle(0.0, o, Vector3(-10, 0, 0))).is_equal_approx(-PI * 0.5, 1e-5)
	assert_float(absf(ArmoryWaypoint.relative_angle(0.0, o, Vector3(0, 0, 10)))).is_equal_approx(PI, 1e-4)
	# Turning left 90 deg (yaw +90) puts a -X target straight ahead.
	assert_float(ArmoryWaypoint.relative_angle(PI * 0.5, o, Vector3(-10, 0, 0))).is_equal_approx(0.0, 1e-5)


func test_screen_x_centres_ahead_and_pins_to_the_edge_off_screen() -> void:
	var ahead := ArmoryWaypoint.screen_x(0.0, HFOV_HALF, 1000.0, 0.06)
	assert_float(ahead[0]).is_equal_approx(500.0, 1e-3)
	assert_int(ahead[1]).is_equal(0)
	var right := ArmoryWaypoint.screen_x(deg_to_rad(80.0), HFOV_HALF, 1000.0, 0.06)
	assert_int(right[1]).is_equal(1)
	assert_float(right[0]).is_equal_approx(940.0, 1e-3)
	var behind_left := ArmoryWaypoint.screen_x(-deg_to_rad(170.0), HFOV_HALF, 1000.0, 0.06)
	assert_int(behind_left[1]).is_equal(-1)
	assert_float(behind_left[0]).is_equal_approx(60.0, 1e-3)


func test_waypoint_shows_only_in_base_off_pad_alive_with_a_reason() -> void:
	assert_bool(ArmoryWaypoint.should_show(false, false, true, true, 0.0)).is_true()
	assert_bool(ArmoryWaypoint.should_show(false, false, true, false, 5.0)).is_true()  # first-spawn window
	assert_bool(ArmoryWaypoint.should_show(false, false, true, false, 0.0)).is_false()  # nothing to buy
	assert_bool(ArmoryWaypoint.should_show(true, false, true, true, 5.0)).is_false()  # dead
	assert_bool(ArmoryWaypoint.should_show(false, true, true, true, 5.0)).is_false()  # on the pad
	assert_bool(ArmoryWaypoint.should_show(false, false, false, true, 5.0)).is_false()  # left the base


func test_in_own_base_is_flat_distance_to_the_sanctum() -> void:
	assert_bool(ArmoryWaypoint.in_own_base(Vector3(30, 9, -5), Vector3(0, 0, -5), 60.0)).is_true()
	assert_bool(ArmoryWaypoint.in_own_base(Vector3(0, 0, -100), Vector3(0, 0, -5), 60.0)).is_false()


func test_hint_names_distance_and_direction() -> void:
	assert_str(ArmoryWaypoint.hint_suffix(24.2, 0.0)).is_equal("24 m ↑")
	assert_str(ArmoryWaypoint.hint_suffix(24.2, PI * 0.5)).is_equal("24 m →")
	assert_str(ArmoryWaypoint.hint_suffix(24.2, -PI * 0.5)).is_equal("24 m ←")
	assert_str(ArmoryWaypoint.hint_suffix(24.2, PI)).is_equal("24 m ↓")
	assert_str(ArmoryWaypoint.hint_for(null, 0)).is_empty()


func test_affordability_follows_lumen() -> void:
	var cat := load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	var m := ItemShopModel.new(cat, load(GameSession.ECONOMY_RULES) as EconomyRulesDef, null, &"hero_vesper_loom",
		(load("res://assets/data/heroes/hero_vesper_loom.tres") as HeroDef).weapon)
	var p := SnapshotData.ProgressState.new()
	m.update(p)
	p.lumen = 0
	assert_bool(ArmoryWaypoint.can_afford_any(m)).is_false()
	p.lumen = 5000
	assert_bool(ArmoryWaypoint.can_afford_any(m)).is_true()
	var a := ArmoryWaypoint.progress_signature(p)
	p.lumen = 4990
	assert_int(ArmoryWaypoint.progress_signature(p)).is_not_equal(a)


func test_minimap_glyph_size_is_data() -> void:
	var d := load(ArmoryMarkerDef.DEFAULT_PATH) as ArmoryMarkerDef
	assert_float(d.minimap_glyph_r).is_greater(2.0)
	assert_float(d.ring_squash_y).is_between(0.02, 1.0)
