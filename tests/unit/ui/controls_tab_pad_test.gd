extends GdUnitTestSuite
## W11-C1: Controls tab Keyboard / Gamepad toggle edits the joypad map only.


func _tab() -> SettingsTabControls:
	var t: SettingsTabControls = auto_free(SettingsTabControls.new())
	t.s = GameSettings.new()
	t.commit = func() -> void: pass
	add_child(t)
	t.build()
	return t


func test_pad_mode_binding_swaps_pad_specs_and_reset_restores() -> void:
	var t := _tab()
	t._set_pad_mode(1)
	assert_bool(t.is_pad_mode()).is_true()
	var jump_old := t.s.bindings.get_pad_spec("jump")
	t.apply_binding("reload", jump_old)
	assert_str(t.s.bindings.get_pad_spec("reload")).is_equal(jump_old)
	assert_bool(t.s.bindings.is_default()).is_true()  # keyboard map untouched
	t._reset()
	assert_bool(t.s.bindings.is_pad_default()).is_true()


func test_keyboard_mode_does_not_touch_pad_map() -> void:
	var t := _tab()
	t._set_pad_mode(0)
	t.apply_binding("jump", "k:%d" % KEY_J)
	assert_str(t.s.bindings.get_spec("jump")).is_equal("k:%d" % KEY_J)
	assert_bool(t.s.bindings.is_pad_default()).is_true()
