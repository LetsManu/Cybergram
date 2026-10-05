extends GdUnitTestSuite
## W11-C1: client view punch per shot and its recovery; never touches WeaponSim.


func _def() -> WeaponDef:
	var d := WeaponDef.new()
	d.fire_rate = 10.0
	d.recoil_v = 1.0
	d.recoil_h = 0.0
	d.recoil_max_deg = 5.0
	d.recoil_recovery_deg_s = 10.0
	d.recoil_recovery_delay_s = 0.1
	return d


func test_shot_kicks_view_up_by_recoil_v() -> void:
	var k := RecoilKick.new(1)
	assert_bool(k.tick(true, true, _def(), 0.05)).is_true()
	assert_float(k.kick.y).is_equal_approx(deg_to_rad(1.0), 0.0001)


func test_fire_rate_limits_kicks_and_cap_holds() -> void:
	var k := RecoilKick.new(1)
	var d := _def()
	for i in 200:  # 10 s of held fire at 20 ticks/s
		k.tick(true, true, d, 0.05)
	assert_int(k.shots).is_between(95, 101)  # ~10 shots/s
	assert_float(k.kick.length()).is_less_equal(deg_to_rad(5.0) + 0.0001)


func test_no_ammo_no_kick_and_semi_auto_needs_release() -> void:
	var k := RecoilKick.new(1)
	assert_bool(k.tick(true, false, _def(), 0.05)).is_false()
	var d := _def()
	d.semi_auto = true
	var k2 := RecoilKick.new(1)
	assert_bool(k2.tick(true, true, d, 0.2)).is_true()
	assert_bool(k2.tick(true, true, d, 0.2)).is_false()  # still held
	k2.tick(false, true, d, 0.2)
	assert_bool(k2.tick(true, true, d, 0.2)).is_true()


func test_recovery_waits_for_delay_then_returns_to_zero() -> void:
	var k := RecoilKick.new(1)
	var d := _def()
	k.tick(true, true, d, 0.05)
	var start := k.kick.y
	k.recover(0.05, d)  # inside the 0.1 s delay
	assert_float(k.kick.y).is_equal(start)
	k.recover(0.1, d)
	assert_float(k.kick.y).is_less(start)
	for i in 20:
		k.recover(0.05, d)
	assert_vector(k.kick).is_equal(Vector2.ZERO)


func test_multiplier_halves_kick_and_zero_def_is_inert() -> void:
	var d := _def()
	var a := RecoilKick.new(1)
	var b := RecoilKick.new(1)
	a.tick(true, true, d, 0.05, 1.0)
	b.tick(true, true, d, 0.05, 0.5)
	assert_float(b.kick.y).is_equal_approx(a.kick.y * 0.5, 0.00001)
	var none := RecoilKick.new(1)
	none.tick(true, true, WeaponDef.new(), 0.05)
	assert_vector(none.kick).is_equal(Vector2.ZERO)


func test_view_angles_add_kick_but_live_aim_is_kept() -> void:
	var src: PlayerInputSource = auto_free(PlayerInputSource.new())
	src.setup(LookSettings.new(), MovementDef.new())
	src.live_pitch = 0.1
	src.recoil.kick = Vector2(0.02, 0.05)
	assert_float(src.view_pitch()).is_equal_approx(0.15, 0.0001)
	assert_float(src.live_pitch).is_equal(0.1)
	var cmd := InputCommand.new()
	src.sample(1, cmd)
	assert_float(cmd.pitch).is_equal_approx(0.15, 0.01)
