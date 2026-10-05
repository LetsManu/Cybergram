extends GdUnitTestSuite
## W16-COMFORT: damage direction indicator + damage vignette model.

const OWN := Vector3(10.0, 1.0, 10.0)


func _rel(yaw: float, at: Vector3) -> float:
	return DamageFeedbackModel.relative_angle(OWN, yaw, at)


func test_direction_relative_to_yaw() -> void:
	# yaw 0 faces -Z; right is +X.
	assert_float(_rel(0.0, OWN + Vector3(0, 0, -5))).is_equal_approx(0.0, 0.001)  # front
	assert_float(absf(_rel(0.0, OWN + Vector3(0, 0, 5)))).is_equal_approx(PI, 0.001)  # back
	assert_float(_rel(0.0, OWN + Vector3(5, 0, 0))).is_equal_approx(PI * 0.5, 0.001)  # right
	assert_float(_rel(0.0, OWN + Vector3(-5, 0, 0))).is_equal_approx(-PI * 0.5, 0.001)  # left
	# turning left by 90 deg (yaw +90) puts the -X attacker in front
	assert_float(_rel(PI * 0.5, OWN + Vector3(-5, 0, 0))).is_equal_approx(0.0, 0.001)
	# and the +Z (was behind) attacker to the left... yaw +90: forward is -X, right is -Z
	assert_float(_rel(PI * 0.5, OWN + Vector3(0, 0, 5))).is_equal_approx(-PI * 0.5, 0.001)


func test_world_pos_round_trip() -> void:
	for rel in [0.0, 1.0, -2.0, PI * 0.5]:
		var p := DamageFeedbackModel.world_pos_at(OWN, 0.7, rel)
		assert_float(_rel(0.7, p)).is_equal_approx(rel, 0.001)


func test_fade_and_removal() -> void:
	var m := DamageFeedbackModel.new()
	m.hit(60.0, 250.0, OWN + Vector3(0, 0, -5))
	var ind: Dictionary = m.indicators[0]
	var a0 := m.indicator_alpha(ind, 1.0, false)
	m.step(m.rules.indicator_fade_s * 0.5)
	assert_float(m.indicator_alpha(m.indicators[0], 1.0, false)).is_less(a0)
	m.step(m.rules.indicator_fade_s)
	assert_int(m.indicators.size()).is_equal(0)


func test_bigger_hits_are_stronger_and_thicker() -> void:
	var m := DamageFeedbackModel.new()
	m.hit(10.0, 250.0, Vector3.ONE)
	m.hit(120.0, 250.0, Vector3.ONE)
	var small: Dictionary = m.indicators[0]
	var big: Dictionary = m.indicators[1]
	assert_float(m.indicator_alpha(big, 1.0, true)).is_greater(m.indicator_alpha(small, 1.0, true))
	assert_float(m.indicator_width_px(big, 1.0, true)).is_greater(m.indicator_width_px(small, 1.0, true))


func test_intensity_scaling_and_zero_is_static() -> void:
	var m := DamageFeedbackModel.new()
	m.hit(60.0, 250.0, Vector3.ONE)
	var ind: Dictionary = m.indicators[0]
	var full := m.indicator_alpha(ind, 1.0, false)
	var low := m.indicator_alpha(ind, 0.4, false)
	var zero := m.indicator_alpha(ind, 0.0, false)
	assert_float(full).is_greater(low)
	assert_float(low).is_greater(zero)
	assert_float(zero).is_greater(0.4)  # still shown at 0% (gameplay-critical)
	# no pulse at 0% or with reduce motion: width does not punch
	assert_float(m.punch(0.0, 0.0, false)).is_equal(0.0)
	assert_float(m.punch(0.0, 1.0, true)).is_equal(0.0)
	assert_float(m.punch(0.0, 1.0, false)).is_greater(0.5)
	# static: alpha at 0% is a plain fade (same pulse-free value at age 0 and 0.05)
	var a0 := m.indicator_alpha(ind, 0.0, false)
	ind.age = 0.05
	assert_float(m.indicator_alpha(ind, 0.0, false)).is_less_equal(a0)
	assert_float(m.indicator_width_px(ind, 0.0, false)).is_equal(m.indicator_width_px({"strength": ind.strength, "age": 9.0}, 0.0, false))


func test_environment_damage_is_non_directional() -> void:
	var m := DamageFeedbackModel.new()
	m.hit(20.0, 250.0, null)  # fall / Sudden Death ring / Leyfall
	assert_bool(m.indicators[0].has_dir).is_false()
	m.hit(20.0, 250.0, Vector3.ONE)
	assert_bool(m.indicators[1].has_dir).is_true()
	m.hit(0.0, 250.0, null)  # no damage, no indicator
	assert_int(m.indicators.size()).is_equal(2)


func test_vignette_scales_and_zero_is_thin_static_tint() -> void:
	var m := DamageFeedbackModel.new()
	m.hit(125.0, 250.0, null)
	var full := m.vignette_alpha(1.0, false)
	var low := m.vignette_alpha(0.4, false)
	var zero := m.vignette_alpha(0.0, false)
	assert_float(full).is_greater(low)
	assert_float(low).is_greater(zero)
	assert_float(zero).is_greater(0.0)
	assert_float(zero).is_less_equal(m.rules.damage_static_alpha)
	assert_float(m.vignette_inner(0.0)).is_greater(m.vignette_inner(1.0))  # thin band
	m.step(m.rules.damage_vignette_fade_s + 0.01)
	assert_float(m.vignette_alpha(1.0, false)).is_equal(0.0)
