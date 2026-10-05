extends GdUnitTestSuite
## W11-C1: stick dead zone / response curve math, and the gamepad-only aim
## assist slowdown (only near targets, only on the stick path).


func test_deadzone_swallows_small_input() -> void:
	assert_vector(StickMath.shape(Vector2(0.1, 0.05), 0.15, 1.0)).is_equal(Vector2.ZERO)
	assert_vector(StickMath.shape(Vector2(0.14, 0.0), 0.15, 1.0)).is_equal(Vector2.ZERO)


func test_full_deflection_is_one_and_rescaled_linear() -> void:
	assert_float(StickMath.shape(Vector2(1, 0), 0.2, 2.0).length()).is_equal_approx(1.0, 0.0001)
	# linear curve, dz 0.2: |v| 0.6 -> (0.6-0.2)/0.8 = 0.5
	assert_float(StickMath.shape(Vector2(0.6, 0), 0.2, 1.0).x).is_equal_approx(0.5, 0.0001)


func test_curve_exponent_gives_finer_control_near_centre() -> void:
	var lin := StickMath.shape(Vector2(0.5, 0), 0.0, 1.0).x
	var cur := StickMath.shape(Vector2(0.5, 0), 0.0, 2.0).x
	assert_float(lin).is_equal_approx(0.5, 0.0001)
	assert_float(cur).is_equal_approx(0.25, 0.0001)


func test_shape_is_radial_and_keeps_direction() -> void:
	var out := StickMath.shape(Vector2(0.6, 0.6), 0.2, 1.5)
	assert_float(out.x).is_equal_approx(out.y, 0.0001)
	assert_float(StickMath.shape(Vector2(0.0, -2.0), 0.2, 1.0).length()).is_equal_approx(1.0, 0.0001)  # clamps


func test_assist_scale_only_inside_radius() -> void:
	var r := deg_to_rad(4.0)
	assert_float(AimAssist.scale_for_angle(r, r, 0.4)).is_equal(1.0)
	assert_float(AimAssist.scale_for_angle(r * 3.0, r, 0.4)).is_equal(1.0)
	assert_float(AimAssist.scale_for_angle(0.0, r, 0.4)).is_equal_approx(0.4, 0.0001)
	var mid := AimAssist.scale_for_angle(r * 0.5, r, 0.4)
	assert_float(mid).is_between(0.4, 1.0)


func test_targets_near_slow_far_or_behind_do_not() -> void:
	var fwd := Vector3.FORWARD
	var near_target: Array = [Vector3(0.5, 0.0, -20.0)]  # ~1.4 deg off, 20 m
	var far_off: Array = [Vector3(15.0, 0.0, -20.0)]
	var behind: Array = [Vector3(0.0, 0.0, 10.0)]
	var too_far: Array = [Vector3(0.0, 0.0, -100.0)]
	assert_float(AimAssist.scale_for_targets(fwd, near_target, 4.0, 0.45, 0.4, 60.0)).is_less(1.0)
	assert_float(AimAssist.scale_for_targets(fwd, far_off, 4.0, 0.45, 0.4, 60.0)).is_equal(1.0)
	assert_float(AimAssist.scale_for_targets(fwd, behind, 4.0, 0.45, 0.4, 60.0)).is_equal(1.0)
	assert_float(AimAssist.scale_for_targets(fwd, too_far, 4.0, 0.45, 0.4, 60.0)).is_equal(1.0)
	assert_float(AimAssist.scale_for_targets(fwd, [], 4.0, 0.45, 0.4, 60.0)).is_equal(1.0)
	# dead centre on the hitbox gives the full slowdown
	var centre: Array = [Vector3(0.0, 0.0, -10.0)]
	assert_float(AimAssist.scale_for_targets(fwd, centre, 4.0, 0.45, 0.4, 60.0)).is_equal_approx(0.45, 0.0001)


func _src() -> PlayerInputSource:
	var src: PlayerInputSource = auto_free(PlayerInputSource.new())
	src.setup(LookSettings.new(), MovementDef.new())
	src.look.pad_deadzone = 0.0
	src.look.pad_curve = 1.0
	return src


func test_stick_step_slows_near_target_only_when_assist_on() -> void:
	var src := _src()
	var stick := Vector2(1.0, 0.0)
	var targets: Array = [Vector3(0.0, 0.0, -10.0)]
	var free := src.stick_look_step(stick, 0.1, [])
	var assisted := src.stick_look_step(stick, 0.1, targets)
	assert_float(src.last_aim_scale).is_less(1.0)
	assert_float(absf(assisted.x)).is_less(absf(free.x))
	assert_float(free.x).is_less(0.0)  # stick right turns the view right (yaw decreases)
	src.look.aim_assist = false
	var off := src.stick_look_step(stick, 0.1, targets)
	assert_float(off.x).is_equal_approx(free.x, 0.00001)
	assert_float(src.last_aim_scale).is_equal(1.0)


func test_stick_step_rate_invert_and_neutral() -> void:
	var src := _src()
	src.look.pad_sensitivity_deg_s = 90.0
	var step := src.stick_look_step(Vector2(0.0, -1.0), 1.0, [])  # stick up looks up
	assert_float(step.y).is_equal_approx(deg_to_rad(90.0), 0.0001)
	src.look.pad_invert_y = true
	assert_float(src.stick_look_step(Vector2(0.0, -1.0), 1.0, []).y).is_equal_approx(-deg_to_rad(90.0), 0.0001)
	assert_vector(src.stick_look_step(Vector2.ZERO, 1.0, [])).is_equal(Vector2.ZERO)


func test_mouse_look_ignores_aim_assist() -> void:
	# The assist lives only in stick_look_step(); the mouse handler never reads it.
	var src := _src()
	var src_text := FileAccess.get_file_as_string("res://src/gameplay/input/player_input_source.gd")
	var mouse_block := src_text.substr(src_text.find("InputEventMouseMotion and Input.mouse_mode"), 400)
	assert_bool(mouse_block.contains("aim_")).is_false()
	assert_bool(src.look.aim_assist).is_true()
