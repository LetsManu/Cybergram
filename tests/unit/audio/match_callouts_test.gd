extends GdUnitTestSuite
## W21-A1: announcer lines derived from match events (no protocol data).

func _c() -> MatchCallouts:
	return MatchCallouts.new(load("res://assets/data/audio/announcer.tres") as AnnouncerDef)


func test_first_blood_once_and_multikills() -> void:
	var c := _c()
	assert_array(c.on_kill(10, 1, true, 0.0)).is_equal([&"first_blood"])
	assert_array(c.on_kill(11, 1, true, 5.0)).is_equal([&"double_kill"])
	assert_array(c.on_kill(12, 1, true, 9.0)).is_equal([&"triple_kill"])
	assert_array(c.on_kill(13, 2, true, 30.0)).is_empty()


func test_multikill_window_expires() -> void:
	var c := _c()
	c.on_kill(10, 1, true, 0.0)
	assert_array(c.on_kill(11, 1, true, 10.5)).is_empty()


func test_shutdown_needs_a_streak_of_three() -> void:
	var c := _c()
	c.on_kill(10, 1, true, 0.0)
	c.on_kill(11, 1, true, 20.0)
	c.on_kill(12, 1, true, 40.0)
	assert_array(c.on_kill(1, 2, true, 60.0)).contains([&"shutdown"])


func test_non_hero_kills_do_not_count() -> void:
	var c := _c()
	assert_array(c.on_kill(10, 99, false, 0.0)).is_empty()
	assert_array(c.on_kill(11, 1, true, 1.0)).is_equal([&"first_blood"])


func test_hardpoints_uplink_phase_end_and_clock() -> void:
	var c := _c()
	assert_array(c.on_hardpoint(-1, 0, 0)).is_equal([&"hardpoint_captured"])
	assert_array(c.on_hardpoint(0, 1, 0)).is_equal([&"hardpoint_lost"])
	assert_array(c.on_uplink(1000.0, 1000.0)).is_empty()
	assert_array(c.on_uplink(999.0, 1000.0)).is_empty()
	assert_array(c.on_uplink(990.0, 1000.0)).is_equal([&"uplink_under_attack"])
	assert_array(c.on_phase(MatchRules.Phase.SUDDEN_DEATH)).is_equal([&"sudden_death"])
	assert_array(c.on_match_end(0, 0)).is_equal([&"victory"])
	assert_array(c.on_match_end(-1, 0)).is_equal([&"defeat"])
	assert_array(c.on_clock(MatchRules.Phase.DEPLOY, 45.0)).is_empty()
	assert_array(c.on_clock(MatchRules.Phase.DEPLOY, 29.8)).is_equal([&"thirty_seconds"])
	assert_array(c.on_clock(MatchRules.Phase.DEPLOY, 20.0)).is_empty()
