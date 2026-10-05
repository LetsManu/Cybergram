extends GdUnitTestSuite
## W16-COMFORT: correction smoothing (blend + threshold snap), vignette model,
## viewmodel FOV factor.

const THRESHOLD := 1.5
const TIME := 0.1


func test_small_error_is_blended_not_snapped() -> void:
	var c := CorrectionSmoother.new()
	var snapped := c.push(Vector3(0.5, 0.0, 0.0), THRESHOLD)
	assert_bool(snapped).is_false()
	assert_float(c.offset.x).is_equal(0.5)
	c.step(TIME * 0.5, TIME)
	assert_float(c.offset.x).is_between(0.05, 0.5)
	c.step(TIME, TIME)  # 1.5 * time in total: ~99% gone
	assert_float(c.offset.length()).is_less(0.02)


func test_blend_reaches_95_percent_at_time() -> void:
	var c := CorrectionSmoother.new()
	c.push(Vector3(1.0, 0.0, 0.0), THRESHOLD)
	c.step(TIME, TIME)
	assert_float(c.offset.x).is_equal_approx(0.0498, 0.002)


func test_large_error_snaps() -> void:
	var c := CorrectionSmoother.new()
	c.offset = Vector3(0.3, 0.0, 0.0)
	assert_bool(c.push(Vector3(0.0, 0.0, THRESHOLD), THRESHOLD)).is_true()
	assert_vector(c.offset).is_equal(Vector3.ZERO)
	assert_bool(c.push(Vector3(0.0, 40.0, 0.0), THRESHOLD)).is_true()  # teleport / respawn
	assert_vector(c.offset).is_equal(Vector3.ZERO)


func test_accumulated_offset_over_threshold_snaps() -> void:
	var c := CorrectionSmoother.new()
	c.push(Vector3(1.0, 0.0, 0.0), THRESHOLD)
	assert_bool(c.push(Vector3(1.0, 0.0, 0.0), THRESHOLD)).is_true()
	assert_vector(c.offset).is_equal(Vector3.ZERO)


func test_zero_time_snaps_and_tail_ends() -> void:
	var c := CorrectionSmoother.new()
	c.push(Vector3(0.2, 0.0, 0.0), THRESHOLD)
	c.step(0.016, 0.0)
	assert_vector(c.offset).is_equal(Vector3.ZERO)


func test_vignette_only_on_fast_or_forced_moves() -> void:
	var m := ComfortVignetteModel.new(ComfortRulesDef.new())
	for i in 30:
		m.step(0.05, Vector3(8.1, 0.0, 0.0), false)  # sprint: nothing
	assert_float(m.level).is_equal(0.0)
	for i in 30:
		m.step(0.05, Vector3(20.0, 0.0, 0.0), false)  # very fast
	assert_float(m.level).is_equal(1.0)
	for i in 100:
		m.step(0.05, Vector3.ZERO, false)  # fades back out
	assert_float(m.level).is_equal(0.0)
	m.step(0.5, Vector3.ZERO, true)  # slide / dash / knockback
	assert_float(m.level).is_equal(1.0)
	m.level = 0.0
	m.step(1.0, Vector3(0.0, -25.0, 0.0), false)  # fall / jump pad
	assert_float(m.level).is_equal(1.0)


func test_vignette_alpha_scales_with_strength() -> void:
	var m := ComfortVignetteModel.new(ComfortRulesDef.new())
	m.level = 1.0
	assert_float(m.alpha(0.0)).is_equal(0.0)
	assert_float(m.alpha(1.0)).is_equal(ComfortRulesDef.new().vignette_max_alpha)


func test_viewmodel_fov_factor() -> void:
	assert_float(ComfortMath.viewmodel_fov_factor(90.0)).is_equal_approx(1.0, 0.0001)
	assert_float(ComfortMath.viewmodel_fov_factor(120.0)).is_equal_approx(1.732, 0.001)
	assert_float(ComfortMath.viewmodel_fov_factor(70.0)).is_less(1.0)


func test_fx_intensity_zero_blocks_flashes() -> void:
	var d := FxDirector.new()
	d.settings = GameSettings.new()
	d.settings.comfort_fx_intensity = 0.0
	assert_float(d.fx_intensity()).is_equal(0.0)
	d.flash(Vector3.ZERO, Color.WHITE, 1.0, 0.1)  # pool empty / intensity 0: no crash, no flash
	d.free()
