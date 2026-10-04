extends GdUnitTestSuite
## G1: quality tiers scale the environment, sun and particle budgets, and the
## headless server builds no visual layer.


func test_default_level_is_high_when_setting_missing() -> void:
	# GameSettings has no graphics_quality yet (chunk S1 adds it): High.
	var gs := GameSettings.shared()
	if gs.get("graphics_quality") == null:
		assert_int(GfxQuality.level()).is_equal(GfxQuality.HIGH)
	else:
		assert_int(GfxQuality.level()).is_between(GfxQuality.LOW, GfxQuality.ULTRA)


func test_low_disables_expensive_features() -> void:
	var env := GfxQuality.make_environment()
	var sun := GfxQuality.make_sun()
	GfxQuality.apply(GfxQuality.LOW, env, sun, null)
	assert_bool(env.glow_enabled).is_false()
	assert_bool(env.ssao_enabled).is_false()
	assert_bool(env.volumetric_fog_enabled).is_false()
	assert_bool(sun.shadow_enabled).is_false()
	sun.free()


func test_ultra_enables_everything() -> void:
	var env := GfxQuality.make_environment()
	var sun := GfxQuality.make_sun()
	GfxQuality.apply(GfxQuality.ULTRA, env, sun, null)
	assert_bool(env.glow_enabled).is_true()
	assert_bool(env.ssao_enabled).is_true()
	assert_bool(env.volumetric_fog_enabled).is_true()
	assert_bool(sun.shadow_enabled).is_true()
	sun.free()


func test_particle_budget_is_monotonic() -> void:
	for l in 3:
		assert_float(GfxQuality.particle_scale(l)).is_less(GfxQuality.particle_scale(l + 1))
		assert_int(GfxQuality.muzzle_lights(l)).is_less_equal(GfxQuality.muzzle_lights(l + 1))


func test_headless_builds_no_fx() -> void:
	# The test runner is headless: the director must create no pooled nodes.
	assert_bool(GfxQuality.is_headless()).is_true()
	var fx: FxDirector = auto_free(FxDirector.new())
	add_child(fx)
	assert_int(fx.get_child_count()).is_equal(0)
