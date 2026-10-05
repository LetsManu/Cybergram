extends GdUnitTestSuite
## W12-K1: the UI kit builds its theme, every button kind styles a button,
## the shared tokens resource loads, and animate() skips tweens under
## reduce motion (design/ux/ui-kit.md §5).


func after_test() -> void:
	UiKit.force_reduce_motion = -1


func test_tokens_resource_loads() -> void:
	var r := load(UiKit.TOKENS_PATH)
	assert_object(r).is_not_null()
	assert_bool(r is UiKitTokens).is_true()
	var t := UiKit.tokens()
	assert_object(t).is_not_null()
	assert_float(t.accent.a).is_equal(1.0)
	assert_int(t.motion_fast).is_less(t.motion_base)
	assert_int(t.motion_base).is_less(t.motion_slow)


func test_theme_builds_with_core_types() -> void:
	var th := UiKit.build_theme()
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton", "LineEdit", "PopupMenu"]:
		assert_bool(th.has_stylebox("normal", cls) or th.has_stylebox("panel", cls)).is_true()
	assert_bool(th.has_stylebox("slider", "HSlider")).is_true()
	assert_bool(th.has_icon("checked", "CheckButton")).is_true()
	assert_bool(th.has_icon("grabber", "HSlider")).is_true()
	assert_object(UiKit.theme()).is_same(UiKit.theme())


func test_every_button_kind_has_styles() -> void:
	for kind in UiKit.KINDS:
		var b: Button = auto_free(UiKit.button("X", Callable(), kind))
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			assert_bool(b.has_theme_stylebox_override(st)).override_failure_message("%s %s" % [kind, st]).is_true()
		assert_bool(b.get_theme_stylebox("normal") is UiBevelBox).is_true()
	var primary: Button = auto_free(UiKit.button("X", Callable(), &"primary"))
	assert_float((primary.get_theme_stylebox("normal") as UiBevelBox).bevel).is_greater(0.0)


func test_reduce_motion_skips_tween() -> void:
	UiKit.force_reduce_motion = 1
	var n: Control = auto_free(Control.new())
	add_child(n)
	var tw := UiKit.animate(n, n, "modulate:a", 0.25, 500)
	assert_object(tw).is_null()
	assert_float(n.modulate.a).is_equal_approx(0.25, 0.001)


func test_motion_on_tweens() -> void:
	UiKit.force_reduce_motion = 0
	var n: Control = auto_free(Control.new())
	add_child(n)
	var tw := UiKit.animate(n, n, "modulate:a", 0.25, 500)
	assert_object(tw).is_not_null()
	assert_float(n.modulate.a).is_equal_approx(1.0, 0.001)  # not jumped
	tw.kill()


func test_reduce_motion_reads_game_settings() -> void:
	var s := GameSettings.shared()
	var was := s.reduce_motion
	s.reduce_motion = true
	assert_bool(UiKit.reduce_motion()).is_true()
	s.reduce_motion = false
	assert_bool(UiKit.reduce_motion()).is_false()
	s.reduce_motion = was


func test_reduce_motion_round_trips_settings_file() -> void:
	var a := GameSettings.new()
	a.reduce_motion = true
	var cfg := ConfigFile.new()
	a.write_config(cfg)
	var b := GameSettings.new()
	b.read_config(cfg)
	assert_bool(b.reduce_motion).is_true()


func test_card_has_header_and_body() -> void:
	var c: UiCard = auto_free(UiKit.card("Title"))
	assert_object(c.body).is_not_null()
	assert_object(c.header).is_not_null()
	assert_str(c.title_label.text).is_equal("Title")
	var plain: UiCard = auto_free(UiKit.card())
	assert_object(plain.header).is_null()


func test_tab_bar_selects_one() -> void:
	var picked := []
	var bar: HBoxContainer = auto_free(UiKit.tab_bar(["A", "B", "C"], func(i: int) -> void: picked.append(i), 1))
	assert_int(bar.get_child_count()).is_equal(3)
	assert_bool((bar.get_child(1) as Button).button_pressed).is_true()
	(bar.get_child(2) as Button).pressed.emit()
	assert_array(picked).contains_exactly([2])


func test_modal_runs_callbacks() -> void:
	UiKit.force_reduce_motion = 1
	var root: Control = auto_free(Control.new())
	add_child(root)
	var hits := []
	var m := UiKit.modal(root, "T", "B", "OK", func() -> void: hits.append("ok"), "No",
		func() -> void: hits.append("no"))
	m.close(false)
	assert_array(hits).contains_exactly(["no"])


func test_toast_lands_in_lane() -> void:
	UiKit.force_reduce_motion = 1
	var root: Control = auto_free(Control.new())
	add_child(root)
	UiKit.toast(root, "hello")
	UiKit.toast(root, "again", &"warn")
	var lane := root.get_node(NodePath(UiKit.TOAST_LANE))
	assert_int(lane.get_child_count()).is_equal(2)


func test_background_freezes_under_reduce_motion() -> void:
	UiKit.force_reduce_motion = 1
	var bg: ColorRect = auto_free(UiKit.background())
	var m := bg.material as ShaderMaterial
	assert_object(m).is_not_null()
	assert_float(float(m.get_shader_parameter("speed"))).is_equal(0.0)
	UiKit.force_reduce_motion = 0
	UiKit.refresh_background(bg)
	assert_float(float(m.get_shader_parameter("speed"))).is_greater(0.0)


func test_display_font_is_cached() -> void:
	assert_object(UiKit.display_font(700, 2)).is_same(UiKit.display_font(700, 2))
