extends GdUnitTestSuite
## E12 resolution independence (design/ux/hud.md §3.2, §15, §16): scale per
## resolution, 16:9 clamp on ultrawide, 720p text floor, UI scale setting.

var _t: HudTuningDef


func before_test() -> void:
	_t = HudTuningDef.new()  # defaults mirror assets/ui/hud_tuning.tres


func test_1080p_is_design_scale() -> void:
	var r := HudLayout.compute(Vector2(1920, 1080), 1.0, true, _t)
	assert_float(r.scale).is_equal_approx(1.0, 1e-6)
	assert_that(r.region).is_equal(Rect2(0, 0, 1920, 1080))
	assert_that(r.canvas).is_equal(Vector2(1920, 1080))


func test_1440p_scales_up() -> void:
	var r := HudLayout.compute(Vector2(2560, 1440), 1.0, true, _t)
	assert_float(r.scale).is_equal_approx(1440.0 / 1080.0, 1e-6)
	assert_float(r.canvas.y).is_equal_approx(1080.0, 1e-3)


func test_720p_keeps_text_floor() -> void:
	var r := HudLayout.compute(Vector2(1280, 720), 1.0, true, _t)
	assert_float(r.scale).is_equal_approx(_t.min_scale, 1e-6)  # 0.9, not 0.667
	assert_float(18.0 * r.scale).is_greater_equal(16.0)  # hud.md §15: 16 px text @720p
	assert_float(r.canvas.x).is_equal_approx(1280.0 / 0.9, 1e-3)


func test_ultrawide_clamps_to_16_9_centre() -> void:
	var r := HudLayout.compute(Vector2(3440, 1440), 1.0, true, _t)
	assert_float(r.region.size.x).is_equal_approx(2560.0, 1e-3)
	assert_float(r.region.position.x).is_equal_approx(440.0, 1e-3)
	var native := HudLayout.compute(Vector2(3440, 1440), 1.0, false, _t)
	assert_float(native.region.size.x).is_equal(3440.0)
	assert_float(native.canvas.x).is_greater(r.canvas.x)


func test_ui_scale_multiplies() -> void:
	var r := HudLayout.compute(Vector2(1920, 1080), 1.2, true, _t)
	assert_float(r.scale).is_equal_approx(1.2, 1e-6)
	assert_float(r.canvas.x).is_equal_approx(1600.0, 1e-3)


func test_tiny_window_shrinks_instead_of_cramping() -> void:
	var r := HudLayout.compute(Vector2(640, 360), 1.0, true, _t)
	assert_float(r.canvas.x).is_greater_equal(_t.min_design_size.x - 0.01)
	assert_float(r.canvas.y).is_greater_equal(_t.min_design_size.y - 0.01)
