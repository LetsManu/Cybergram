extends GdUnitTestSuite
## W18-LIFE: World ambience level capping and the comfort scaling.


func test_level_is_capped_by_graphics_quality() -> void:
	assert_int(AmbientComfort.level(AmbientComfort.HIGH, GfxQuality.LOW)).is_equal(AmbientComfort.LOW)
	assert_int(AmbientComfort.level(AmbientComfort.HIGH, GfxQuality.MEDIUM)).is_equal(AmbientComfort.MEDIUM)
	assert_int(AmbientComfort.level(AmbientComfort.HIGH, GfxQuality.ULTRA)).is_equal(AmbientComfort.HIGH)
	assert_int(AmbientComfort.level(AmbientComfort.LOW, GfxQuality.ULTRA)).is_equal(AmbientComfort.LOW)
	assert_int(AmbientComfort.level(9, 9)).is_equal(AmbientComfort.HIGH)


func test_budgets_grow_with_level() -> void:
	for key in ["traffic_lanes", "cars_per_lane", "drones", "billboards", "signs", "shafts", "motes", "rain", "birds"]:
		assert_int(int(AmbientComfort.budget(0)[key])).is_less_equal(int(AmbientComfort.budget(1)[key]))
		assert_int(int(AmbientComfort.budget(1)[key])).is_less_equal(int(AmbientComfort.budget(2)[key]))


func test_flicker_is_steady_with_reduce_motion_or_low_fx() -> void:
	assert_float(AmbientComfort.flicker_amount(1.0, true)).is_equal(0.0)
	assert_float(AmbientComfort.flicker_amount(0.3, false)).is_equal(0.0)
	assert_float(AmbientComfort.flicker_amount(0.0, false)).is_equal(0.0)
	assert_float(AmbientComfort.flicker_amount(1.0, false)).is_equal_approx(AmbientComfort.FLICKER_MAX_DIP, 0.0001)
	for i in 200:
		assert_float(AmbientComfort.flicker(i * 0.137, 0.4, 0.0)).is_equal(1.0)


func test_flicker_is_subtle() -> void:
	var amt := AmbientComfort.flicker_amount(1.0, false)
	var lo := 1.0
	for i in 4000:
		var f := AmbientComfort.flicker(i * 0.013, 0.618, amt)
		assert_float(f).is_between(1.0 - amt, 1.0)
		lo = minf(lo, f)
	assert_float(lo).is_greater_equal(0.78)


func test_glow_dims_never_brightens() -> void:
	assert_float(AmbientComfort.glow_gain(0.0)).is_equal_approx(0.6, 0.0001)
	assert_float(AmbientComfort.glow_gain(1.0)).is_equal_approx(1.0, 0.0001)
	assert_float(AmbientComfort.glow_gain(5.0)).is_equal_approx(1.0, 0.0001)
	assert_float(AmbientComfort.glow_gain(0.4)).is_less(AmbientComfort.glow_gain(0.8))


func test_motion_and_rain_follow_settings() -> void:
	assert_float(AmbientComfort.anim_speed(true)).is_equal(0.0)
	assert_float(AmbientComfort.anim_speed(false)).is_equal(1.0)
	assert_float(AmbientComfort.traffic_speed(true)).is_less(1.0)
	assert_int(AmbientComfort.rain_amount(2, 1.0, false)).is_equal(0)
	assert_int(AmbientComfort.rain_amount(2, 0.0, true)).is_equal(0)
	assert_int(AmbientComfort.rain_amount(2, 1.0, true)).is_equal(int(AmbientComfort.budget(2).rain))
	assert_bool(AmbientComfort.shafts_enabled(0.0)).is_false()


func test_settings_round_trip() -> void:
	var a := GameSettings.new()
	a.ambient_level = 0
	a.ambient_rain = false
	var cfg := ConfigFile.new()
	a.write_config(cfg)
	var b := GameSettings.new()
	b.read_config(cfg)
	assert_int(b.ambient_level).is_equal(0)
	assert_bool(b.ambient_rain).is_false()
	cfg.set_value("display", "ambient_level", 99)
	b.read_config(cfg)
	assert_int(b.ambient_level).is_equal(2)
