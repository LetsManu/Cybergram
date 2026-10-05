extends GdUnitTestSuite
## W19-VM: FP clip timing follows gameplay (WeaponDef), never the reverse.
## FpViewmodel.clip_scale / fire_scale / reload_duration / loco_point are pure.


func _mag_gun(reload_s: float, empty_s: float, per_round: bool = false) -> WeaponDef:
	var d := WeaponDef.new()
	d.feed_kind = WeaponDef.FeedKind.MAGAZINE
	d.reload_s = reload_s
	d.reload_empty_s = empty_s
	d.reload_per_round = per_round
	return d


func _mana_gun(delay_s: float, mult: float) -> WeaponDef:
	var d := WeaponDef.new()
	d.feed_kind = WeaponDef.FeedKind.MANA
	d.mana_regen_delay_s = delay_s
	d.burnout_delay_mult = mult
	return d


func test_clip_scale_fits_clip_to_target() -> void:
	for pair in [[1.8, 1.6], [1.8, 2.4], [0.5, 0.5]]:
		var s := FpViewmodel.clip_scale(pair[0], pair[1])
		# a clip of length L at scale s lasts L / s seconds
		assert_float(pair[0] / s).is_equal_approx(pair[1], 1e-5)


func test_clip_scale_guards_non_positive() -> void:
	assert_float(FpViewmodel.clip_scale(1.8, 0.0)).is_equal(1.0)
	assert_float(FpViewmodel.clip_scale(0.0, 1.5)).is_equal(1.0)


func test_reload_duration_reads_weapon_def() -> void:
	var g := _mag_gun(1.6, 2.1)
	assert_float(FpViewmodel.reload_duration(g)).is_equal(1.6)
	assert_float(FpViewmodel.reload_duration(g, true)).is_equal(2.1)
	assert_float(FpViewmodel.reload_duration(_mag_gun(1.6, 0.0), true)).is_equal(1.6)
	assert_float(FpViewmodel.reload_duration(_mag_gun(0.5, 2.0, true), true)).is_equal(0.5)
	assert_float(FpViewmodel.reload_duration(null)).is_equal(0.0)


func test_mana_reload_fills_the_burnout_lock() -> void:
	assert_float(FpViewmodel.reload_duration(_mana_gun(1.0, 1.5))).is_equal_approx(1.5, 1e-6)


func test_reload_clip_scaled_to_threadcaster_def() -> void:
	var d := load("res://assets/data/weapons/weapon_threadcaster.tres") as WeaponDef
	var target := FpViewmodel.reload_duration(d)
	var clip_len := 1.8
	assert_float(clip_len / FpViewmodel.clip_scale(clip_len, target)).is_equal_approx(target, 1e-5)


func test_fire_clip_never_outlasts_one_shot() -> void:
	var clip_len := 8.0 / 30.0
	for rate in [2.0, 4.0, 10.0, 15.0]:
		var s := FpViewmodel.fire_scale(clip_len, rate)
		assert_float(clip_len / s).is_less_equal(maxf(1.0 / rate, clip_len) + 1e-6)
		assert_float(s).is_greater_equal(1.0)
	assert_float(FpViewmodel.fire_scale(clip_len, 0.0)).is_equal(1.0)


func test_loco_point_respects_sway_toggle() -> void:
	assert_float(FpViewmodel.loco_point(6.0, 6.0, true, false)).is_equal(0.0)
	assert_float(FpViewmodel.loco_point(6.0, 6.0, false, true)).is_equal(FpViewmodel.WALK_POINT)
	assert_float(FpViewmodel.loco_point(3.0, 6.0, false, true)).is_equal(FpViewmodel.WALK_POINT * 0.5)
	assert_float(FpViewmodel.loco_point(8.0, 6.0, true, true)).is_equal(1.0)
	assert_float(FpViewmodel.loco_point(0.0, 6.0, false, true)).is_equal(0.0)


func test_inspect_is_a_bindable_action() -> void:
	assert_bool(InputBindings.action_ids().has("inspect")).is_true()
	assert_str(InputBindings.default_spec("inspect")).is_equal("k:%d" % KEY_I)
