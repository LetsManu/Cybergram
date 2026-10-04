extends GdUnitTestSuite
## S1 key rebinding: defaults, conflict swap, reset, config round trip,
## InputMap applied at boot, settings persistence.

const TMP := "user://s1_test_settings.cfg"


func after_test() -> void:
	InputMap.load_from_project_settings()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)


func test_every_action_has_a_unique_valid_default() -> void:
	var seen := {}
	for a in InputBindings.ACTIONS:
		assert_object(InputBindings.event_from_spec(a[2])).is_not_null()
		assert_bool(seen.has(a[2])).is_false()
		seen[a[2]] = true
	assert_str(InputBindings.default_spec("move_forward")).is_equal("k:%d" % KEY_W)
	assert_str(InputBindings.default_spec("open_shop")).is_equal("k:%d" % KEY_B)
	assert_str(InputBindings.default_spec("scoreboard")).is_equal("k:%d" % KEY_TAB)
	assert_str(InputBindings.default_spec("net_graph")).is_equal("k:%d" % KEY_F3)
	assert_str(InputBindings.default_spec("pause")).is_equal("k:%d" % KEY_ESCAPE)
	assert_str(InputBindings.default_spec("crouch")).is_equal("k:%d" % KEY_CTRL)
	assert_str(InputBindings.default_spec("sprint")).is_equal("k:%d" % KEY_SHIFT)
	assert_str(InputBindings.default_spec("quick_spend")).is_equal("k:%d" % KEY_ALT)
	assert_str(InputBindings.default_spec("squad_wheel")).is_equal("k:%d" % KEY_V)
	assert_str(InputBindings.default_spec("fire")).is_equal("m:%d" % MOUSE_BUTTON_LEFT)


func test_assign_without_conflict() -> void:
	var b := InputBindings.new()
	assert_str(b.assign("reload", "k:%d" % KEY_T)).is_equal("")
	assert_str(b.get_spec("reload")).is_equal("k:%d" % KEY_T)


func test_conflict_swaps_the_two_actions() -> void:
	var b := InputBindings.new()
	var jump_old := b.get_spec("jump")
	var swapped := b.assign("reload", jump_old)
	assert_str(swapped).is_equal("jump")
	assert_str(b.get_spec("reload")).is_equal(jump_old)
	assert_str(b.get_spec("jump")).is_equal(InputBindings.default_spec("reload"))


func test_malformed_spec_changes_nothing() -> void:
	var b := InputBindings.new()
	b.assign("jump", "garbage")
	assert_bool(b.is_default()).is_true()


func test_reset_restores_defaults() -> void:
	var b := InputBindings.new()
	b.assign("jump", "k:%d" % KEY_J)
	b.assign("fire", "m:%d" % MOUSE_BUTTON_RIGHT)
	assert_bool(b.is_default()).is_false()
	b.reset_all()
	assert_bool(b.is_default()).is_true()


func test_config_round_trip() -> void:
	var a := InputBindings.new()
	a.assign("jump", "k:%d" % KEY_J)
	a.assign("fire", "m:%d" % MOUSE_BUTTON_RIGHT)
	a.assign("move_forward", a.get_spec("move_back"))  # swap
	var cfg := ConfigFile.new()
	a.write_config(cfg)
	var b := InputBindings.new()
	b.read_config(cfg)
	for id in InputBindings.action_ids():
		assert_str(b.get_spec(id)).is_equal(a.get_spec(id))


func test_duplicate_or_bad_values_in_file_are_repaired() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("bindings", "jump", "k:%d" % KEY_W)
	cfg.set_value("bindings", "reload", "nonsense")
	var b := InputBindings.new()
	b.read_config(cfg)
	assert_str(b.get_spec("reload")).is_equal(InputBindings.default_spec("reload"))
	var specs := {}
	for id in InputBindings.action_ids():
		var sp := b.get_spec(id)
		if sp != "":
			assert_bool(specs.has(sp)).is_false()
			specs[sp] = true


func test_apply_to_input_map_uses_the_binding() -> void:
	var b := InputBindings.new()
	b.assign("jump", "k:%d" % KEY_J)
	b.apply_to_input_map()
	var jk := InputEventKey.new()
	jk.physical_keycode = KEY_J
	var sp := InputEventKey.new()
	sp.physical_keycode = KEY_SPACE
	assert_bool(InputMap.event_is_action(jk, "jump")).is_true()
	assert_bool(InputMap.event_is_action(sp, "jump")).is_false()
	for id in InputBindings.action_ids():
		assert_bool(InputMap.has_action(id)).is_true()


func test_pause_binding_also_cancels_menus_and_esc_stays() -> void:
	var b := InputBindings.new()
	b.assign("pause", "k:%d" % KEY_P)
	b.apply_to_input_map()
	var p := InputEventKey.new()
	p.physical_keycode = KEY_P
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	assert_bool(InputMap.event_is_action(p, "ui_cancel")).is_true()
	assert_bool(InputMap.event_is_action(esc, "ui_cancel")).is_true()


func test_boot_applies_saved_bindings_to_input_map() -> void:
	var a := GameSettings.new()
	a.bindings.assign("reload", "k:%d" % KEY_T)
	a.save(TMP)
	var b := GameSettings.new()
	b.load_from_disk(TMP)
	b.apply_bindings()  # what GameSettings.shared() does at boot
	var t := InputEventKey.new()
	t.physical_keycode = KEY_T
	assert_bool(InputMap.event_is_action(t, "reload")).is_true()


func test_settings_persist_across_save_and_load() -> void:
	var a := GameSettings.new()
	a.window_mode = GameSettings.WindowMode.BORDERLESS
	a.render_scale = 0.7
	a.vsync = false
	a.fps_cap_index = 2
	a.graphics_quality = GameSettings.Quality.ULTRA
	a.master_volume = 0.3
	a.effects_volume = 0.5
	a.ui_volume = 0.1
	a.mouse_sensitivity_deg = 0.2
	a.crosshair_style = GameSettings.Crosshair.CIRCLE
	a.crosshair_color = 3
	a.save(TMP)
	var b := GameSettings.new()
	b.load_from_disk(TMP)
	assert_int(b.window_mode).is_equal(GameSettings.WindowMode.BORDERLESS)
	assert_float(b.render_scale).is_equal_approx(0.7, 0.001)
	assert_bool(b.vsync).is_false()
	assert_int(b.fps_cap_index).is_equal(2)
	assert_int(b.graphics_quality).is_equal(3)
	assert_float(b.master_volume).is_equal_approx(0.3, 0.001)
	assert_float(b.effects_volume).is_equal_approx(0.5, 0.001)
	assert_float(b.ui_volume).is_equal_approx(0.1, 0.001)
	assert_float(b.mouse_sensitivity_deg).is_equal_approx(0.2, 0.001)
	assert_int(b.crosshair_style).is_equal(GameSettings.Crosshair.CIRCLE)
	assert_int(b.crosshair_color).is_equal(3)


func test_defaults_and_clamping() -> void:
	var s := GameSettings.new()
	assert_int(s.graphics_quality).is_equal(2)
	var cfg := ConfigFile.new()
	cfg.set_value("display", "quality", 99)
	cfg.set_value("display", "render_scale", 0.1)
	cfg.set_value("display", "fps_cap_index", -4)
	s.read_config(cfg)
	assert_int(s.graphics_quality).is_equal(3)
	assert_float(s.render_scale).is_equal(GameSettings.RENDER_SCALE_MIN)
	assert_int(s.fps_cap_index).is_equal(0)


func test_legacy_fullscreen_key_migrates() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", true)
	var s := GameSettings.new()
	s.read_config(cfg)
	assert_int(s.window_mode).is_equal(GameSettings.WindowMode.FULLSCREEN)


func test_save_keeps_the_hud_section() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("hud", "ui_scale", 1.1)
	cfg.save(TMP)
	GameSettings.new().save(TMP)
	var back := ConfigFile.new()
	back.load(TMP)
	assert_float(float(back.get_value("hud", "ui_scale", 0.0))).is_equal_approx(1.1, 0.001)


func test_audio_buses_are_created() -> void:
	GameSettings.ensure_buses()
	assert_int(AudioServer.get_bus_index(GameSettings.BUS_EFFECTS)).is_greater(0)
	assert_int(AudioServer.get_bus_index(GameSettings.BUS_UI)).is_greater(0)
	assert_int(GameSettings.ensure_buses()).is_equal(0)


func test_spec_from_event_captures_keys_and_mouse() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_H
	k.pressed = true
	assert_str(InputBindings.spec_from_event(k)).is_equal("k:%d" % KEY_H)
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_RIGHT
	m.pressed = true
	assert_str(InputBindings.spec_from_event(m)).is_equal("m:2")
	m.pressed = false
	assert_str(InputBindings.spec_from_event(m)).is_equal("")
