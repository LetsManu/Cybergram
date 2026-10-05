extends GdUnitTestSuite
## W16-COMFORT: GameSettings [comfort] defaults, clamping, round trip, preset,
## launcher-key compatibility, and camera-recoil / aim consistency.


func test_defaults() -> void:
	var s := GameSettings.new()
	assert_float(s.comfort_camera_recoil).is_equal(1.0)
	assert_bool(s.comfort_weapon_bob).is_true()
	assert_float(s.comfort_fx_intensity).is_equal(1.0)
	assert_bool(s.comfort_center_dot).is_false()
	assert_float(s.comfort_dot_size_px).is_equal(3.0)
	assert_bool(s.comfort_smooth_corrections).is_true()
	assert_float(s.comfort_vignette).is_equal(0.0)
	assert_bool(s.comfort_hint_seen).is_false()
	assert_float(s.fov_deg).is_equal(90.0)


func test_clamping() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("comfort", "camera_recoil", 5.0)
	cfg.set_value("comfort", "fx_intensity", -2.0)
	cfg.set_value("comfort", "dot_size_px", 99.0)
	cfg.set_value("comfort", "dot_opacity", 0.0)
	cfg.set_value("comfort", "vignette", 9.0)
	cfg.set_value("look", "fov_deg", 500.0)
	var s := GameSettings.new()
	s.read_config(cfg)
	assert_float(s.comfort_camera_recoil).is_equal(1.0)
	assert_float(s.comfort_fx_intensity).is_equal(0.0)
	assert_float(s.comfort_dot_size_px).is_equal(GameSettings.DOT_SIZE_MAX)
	assert_float(s.comfort_dot_opacity).is_equal(GameSettings.DOT_OPACITY_MIN)
	assert_float(s.comfort_vignette).is_equal(1.0)
	assert_float(s.fov_deg).is_equal(GameSettings.FOV_MAX)
	assert_float(GameSettings.FOV_MAX).is_equal(120.0)
	cfg.set_value("comfort", "dot_size_px", 0.5)
	s.read_config(cfg)
	assert_float(s.comfort_dot_size_px).is_equal(GameSettings.DOT_SIZE_MIN)


func test_round_trip() -> void:
	var a := GameSettings.new()
	a.comfort_camera_recoil = 0.4
	a.comfort_weapon_bob = false
	a.comfort_fx_intensity = 0.25
	a.comfort_center_dot = true
	a.comfort_dot_size_px = 5.0
	a.comfort_dot_opacity = 0.6
	a.comfort_smooth_corrections = false
	a.comfort_vignette = 0.75
	a.comfort_hint_seen = true
	var cfg := ConfigFile.new()
	a.write_config(cfg)
	var b := GameSettings.new()
	b.read_config(cfg)
	assert_float(b.comfort_camera_recoil).is_equal(0.4)
	assert_bool(b.comfort_weapon_bob).is_false()
	assert_float(b.comfort_fx_intensity).is_equal(0.25)
	assert_bool(b.comfort_center_dot).is_true()
	assert_float(b.comfort_dot_size_px).is_equal(5.0)
	assert_float(b.comfort_dot_opacity).is_equal(0.6)
	assert_bool(b.comfort_smooth_corrections).is_false()
	assert_float(b.comfort_vignette).is_equal(0.75)
	assert_bool(b.comfort_hint_seen).is_true()


func test_launcher_keys_still_read() -> void:
	# The launcher writes only [display] window_mode / quality / window_w / window_h.
	var cfg := ConfigFile.new()
	cfg.set_value("display", "window_mode", 2)
	cfg.set_value("display", "quality", 3)
	cfg.set_value("display", "window_w", 1600)
	cfg.set_value("display", "window_h", 900)
	var s := GameSettings.new()
	s.read_config(cfg)
	assert_int(s.window_mode).is_equal(GameSettings.WindowMode.BORDERLESS)
	assert_int(s.graphics_quality).is_equal(GameSettings.Quality.ULTRA)
	assert_int(s.window_w).is_equal(1600)
	assert_float(s.comfort_camera_recoil).is_equal(1.0)  # comfort untouched


func test_preset() -> void:
	var s := GameSettings.new()
	s.apply_comfort_preset(ComfortRulesDef.new())
	assert_float(s.comfort_camera_recoil).is_equal(0.25)
	assert_bool(s.comfort_weapon_bob).is_false()
	assert_float(s.comfort_fx_intensity).is_equal(0.4)
	assert_bool(s.comfort_center_dot).is_true()
	assert_bool(s.comfort_smooth_corrections).is_true()
	assert_float(s.comfort_vignette).is_equal(0.5)
	assert_bool(s.reduce_motion).is_true()
	assert_float(s.fov_deg).is_equal(100.0)
	s.fov_deg = 115.0
	s.apply_comfort_preset(ComfortRulesDef.new())
	assert_float(s.fov_deg).is_equal(115.0)  # never lowered


func test_aim_is_full_kick_camera_is_scaled() -> void:
	var p := PlayerInputSource.new()
	p.recoil.kick = Vector2(0.02, 0.04)
	var cmd := InputCommand.new()
	for scale in [1.0, 0.5, 0.0]:
		p.camera_recoil_scale = scale
		p.sample(1, cmd)
		# the aim sent always includes the FULL kick (independent of the slider)
		assert_float(cmd.pitch).is_equal_approx(0.04, 0.001)
		assert_float(cmd.yaw).is_equal_approx(0.02, 0.001)
		# the camera shows kick * scale
		assert_float(p.view_pitch()).is_equal_approx(0.04 * scale, 0.0001)
		assert_float(p.view_yaw()).is_equal_approx(0.02 * scale, 0.0001)
		# the remainder is what the crosshair shows
		assert_float(p.hidden_kick().y).is_equal_approx(0.04 * (1.0 - scale), 0.0001)
		assert_float(p.hidden_kick().x).is_equal_approx(0.02 * (1.0 - scale), 0.0001)
	p.free()


func test_crosshair_offset_is_remaining_kick_projected() -> void:
	var vp := Vector2(1280, 720)
	assert_vector(ComfortMath.kick_to_screen_px(Vector2.ZERO, 90.0, vp)).is_equal(Vector2.ZERO)
	# 45 degrees up at 90 deg vertical FOV = the top edge: half the viewport height up.
	var up := ComfortMath.kick_to_screen_px(Vector2(0.0, deg_to_rad(45.0)), 90.0, vp)
	assert_float(up.y).is_equal_approx(-360.0, 0.01)
	assert_float(up.x).is_equal_approx(0.0, 0.001)
	# yaw + is left: negative x
	assert_float(ComfortMath.kick_to_screen_px(Vector2(0.05, 0.0), 90.0, vp).x).is_less(0.0)
	# a wider FOV shrinks the same kick on screen
	var a := ComfortMath.kick_to_screen_px(Vector2(0.0, 0.05), 90.0, vp).y
	var b := ComfortMath.kick_to_screen_px(Vector2(0.0, 0.05), 120.0, vp).y
	assert_float(absf(b)).is_less(absf(a))
