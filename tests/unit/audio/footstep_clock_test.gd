extends GdUnitTestSuite
## W11-C1: own footstep cadence follows ground speed; silent airborne / standing;
## feel archetypes exist and the voice pools stay bounded.


func _steps(speed: float, grounded: bool, seconds: float, mult: float = 1.0) -> int:
	var c := FootstepClock.new(2.0, 1.0)
	var n := 0
	var t := 0.0
	while t < seconds:
		if c.advance(speed, grounded, 0.01, mult):
			n += 1
		t += 0.01
	return n


func test_cadence_scales_with_speed() -> void:
	assert_int(_steps(4.0, true, 5.0)).is_between(9, 11)   # 20 m / 2 m
	assert_int(_steps(8.0, true, 5.0)).is_between(19, 21)  # sprint: twice as often


func test_silent_when_airborne_or_too_slow() -> void:
	assert_int(_steps(6.0, false, 3.0)).is_equal(0)
	assert_int(_steps(0.5, true, 3.0)).is_equal(0)
	assert_int(_steps(0.0, true, 3.0)).is_equal(0)


func test_crouch_stride_is_longer() -> void:
	assert_int(_steps(4.0, true, 5.0, 2.0)).is_between(4, 6)


func test_landing_while_moving_steps_once_and_airtime_resets() -> void:
	var c := FootstepClock.new(2.0, 1.0)
	for i in 50:
		assert_bool(c.advance(5.0, false, 0.01)).is_false()
	assert_bool(c.advance(5.0, true, 0.01)).is_true()  # touchdown
	assert_bool(c.advance(5.0, true, 0.01)).is_false()


func test_feel_archetypes_resolve_and_pools_are_bounded() -> void:
	var bank := SfxBank.shared()
	for k in [&"reload_start", &"reload_done", &"dry_fire", &"footstep"]:
		var st := bank.feel_stream(k)
		assert_object(st).is_not_null()
		assert_int(st.data.size()).is_greater(0)
	assert_int(bank.def.pool_feet).is_less_equal(4)
	assert_float(bank.synth_ms).is_less(300.0)
