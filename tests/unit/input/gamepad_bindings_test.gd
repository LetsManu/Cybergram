extends GdUnitTestSuite
## W11-C1: joypad spec parsing, round trip, conflict swap, InputMap application,
## and the gamepad look options persisting in settings.cfg.

const TMP := "user://w11c1_test_settings.cfg"


func after_test() -> void:
	InputMap.load_from_project_settings()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)


func test_spec_parsing_buttons_and_axes() -> void:
	var b := InputBindings.joy_event_from_spec("j:%d" % JOY_BUTTON_A) as InputEventJoypadButton
	assert_object(b).is_not_null()
	assert_int(b.button_index).is_equal(JOY_BUTTON_A)
	var a := InputBindings.joy_event_from_spec("a:%d:-1" % JOY_AXIS_LEFT_Y) as InputEventJoypadMotion
	assert_int(a.axis).is_equal(JOY_AXIS_LEFT_Y)
	assert_float(a.axis_value).is_equal(-1.0)
	for bad in ["", "j:", "j:x", "j:-1", "j:999", "a:1", "a:1:0", "a:1:2", "a:99:1", "k:65", "a:1:1:1"]:
		assert_object(InputBindings.joy_event_from_spec(bad)).is_null()


func test_defaults_are_valid_and_unique_when_bound() -> void:
	var seen := {}
	for a in InputBindings.ACTIONS:
		var spec: String = a[3]
		if spec == "":
			continue
		assert_object(InputBindings.joy_event_from_spec(spec)).is_not_null()
		assert_bool(seen.has(spec)).is_false()
		seen[spec] = true
	assert_str(InputBindings.default_pad_spec("fire")).is_equal("a:%d:1" % JOY_AXIS_TRIGGER_RIGHT)
	assert_str(InputBindings.default_pad_spec("alt_fire")).is_equal("a:%d:1" % JOY_AXIS_TRIGGER_LEFT)
	assert_str(InputBindings.default_pad_spec("jump")).is_equal("j:%d" % JOY_BUTTON_A)
	assert_str(InputBindings.default_pad_spec("crouch")).is_equal("j:%d" % JOY_BUTTON_B)
	assert_str(InputBindings.default_pad_spec("sprint")).is_equal("j:%d" % JOY_BUTTON_LEFT_STICK)
	assert_str(InputBindings.default_pad_spec("reload")).is_equal("j:%d" % JOY_BUTTON_X)
	assert_str(InputBindings.default_pad_spec("interact")).is_equal("j:%d" % JOY_BUTTON_Y)
	assert_str(InputBindings.default_pad_spec("scoreboard")).is_equal("j:%d" % JOY_BUTTON_BACK)
	assert_str(InputBindings.default_pad_spec("pause")).is_equal("j:%d" % JOY_BUTTON_START)
	assert_bool(InputBindings.new().is_pad_default()).is_true()


func test_event_capture_specs() -> void:
	var btn := InputEventJoypadButton.new()
	btn.button_index = JOY_BUTTON_Y
	btn.pressed = true
	assert_str(InputBindings.joy_spec_from_event(btn)).is_equal("j:%d" % JOY_BUTTON_Y)
	btn.pressed = false
	assert_str(InputBindings.joy_spec_from_event(btn)).is_equal("")
	var m := InputEventJoypadMotion.new()
	m.axis = JOY_AXIS_TRIGGER_LEFT
	m.axis_value = 0.3  # below the capture threshold
	assert_str(InputBindings.joy_spec_from_event(m)).is_equal("")
	m.axis_value = 0.9
	assert_str(InputBindings.joy_spec_from_event(m)).is_equal("a:%d:1" % JOY_AXIS_TRIGGER_LEFT)
	m.axis = JOY_AXIS_RIGHT_X
	m.axis_value = -1.0
	assert_str(InputBindings.joy_spec_from_event(m)).is_equal("a:%d:-1" % JOY_AXIS_RIGHT_X)
	assert_str(InputBindings.joy_spec_text("j:%d" % JOY_BUTTON_LEFT_SHOULDER)).is_equal("LB")
	assert_str(InputBindings.joy_spec_text("a:%d:1" % JOY_AXIS_TRIGGER_RIGHT)).is_equal("RT")
	assert_str(InputBindings.joy_spec_text("")).is_equal("-")


func test_conflict_swaps_and_keyboard_map_is_independent() -> void:
	var b := InputBindings.new()
	var jump_old := b.get_pad_spec("jump")
	assert_str(b.assign_pad("reload", jump_old)).is_equal("jump")
	assert_str(b.get_pad_spec("reload")).is_equal(jump_old)
	assert_str(b.get_pad_spec("jump")).is_equal(InputBindings.default_pad_spec("reload"))
	assert_bool(b.is_default()).is_true()  # keyboard side untouched
	assert_str(b.assign_pad("jump", "garbage")).is_equal("")
	assert_str(b.assign_pad("jump", "")).is_equal("")  # unbind, never a swap
	assert_str(b.get_pad_spec("jump")).is_equal("")
	b.reset_pad()
	assert_bool(b.is_pad_default()).is_true()


func test_round_trip_and_repair() -> void:
	var a := InputBindings.new()
	a.assign_pad("jump", "j:%d" % JOY_BUTTON_RIGHT_STICK)
	a.assign_pad("fire", "j:%d" % JOY_BUTTON_RIGHT_SHOULDER)
	var cfg := ConfigFile.new()
	a.write_config(cfg)
	var b := InputBindings.new()
	b.read_config(cfg)
	for id in InputBindings.action_ids():
		assert_str(b.get_pad_spec(id)).is_equal(a.get_pad_spec(id))
	var bad := ConfigFile.new()
	bad.set_value("bindings_pad", "jump", "j:%d" % JOY_BUTTON_X)  # duplicates reload's default
	bad.set_value("bindings_pad", "crouch", "nonsense")
	var c := InputBindings.new()
	c.read_config(bad)
	assert_str(c.get_pad_spec("crouch")).is_equal(InputBindings.default_pad_spec("crouch"))
	var seen := {}
	for id in InputBindings.action_ids():
		var sp := c.get_pad_spec(id)
		if sp != "":
			assert_bool(seen.has(sp)).is_false()
			seen[sp] = true


func test_pad_events_reach_the_input_map() -> void:
	var b := InputBindings.new()
	b.assign_pad("jump", "j:%d" % JOY_BUTTON_RIGHT_SHOULDER)
	b.apply_to_input_map()
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	assert_bool(InputMap.event_is_action(rb, "jump")).is_true()
	assert_bool(InputMap.event_is_action(a, "jump")).is_false()
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	assert_bool(InputMap.event_is_action(rt, "fire")).is_true()
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	assert_bool(InputMap.event_is_action(start, "ui_cancel")).is_true()


func test_gamepad_look_options_persist_and_clamp() -> void:
	var a := GameSettings.new()
	a.pad_sensitivity_deg_s = 300.0
	a.pad_deadzone = 0.25
	a.pad_curve = 2.0
	a.pad_invert_y = true
	a.aim_assist = false
	a.bindings.assign_pad("reload", "j:%d" % JOY_BUTTON_LEFT_SHOULDER)
	a.save(TMP)
	var b := GameSettings.new()
	b.load_from_disk(TMP)
	assert_float(b.pad_sensitivity_deg_s).is_equal(300.0)
	assert_float(b.pad_deadzone).is_equal(0.25)
	assert_float(b.pad_curve).is_equal(2.0)
	assert_bool(b.pad_invert_y).is_true()
	assert_bool(b.aim_assist).is_false()
	assert_str(b.bindings.get_pad_spec("reload")).is_equal("j:%d" % JOY_BUTTON_LEFT_SHOULDER)
	var cfg := ConfigFile.new()
	cfg.set_value("gamepad", "deadzone", 9.0)
	cfg.set_value("gamepad", "curve", 0.0)
	var c := GameSettings.new()
	c.read_config(cfg)
	assert_float(c.pad_deadzone).is_equal(GameSettings.PAD_DEADZONE_MAX)
	assert_float(c.pad_curve).is_equal(GameSettings.PAD_CURVE_MIN)
	var look := LookSettings.new()
	a.apply_look(look)
	assert_float(look.pad_sensitivity_deg_s).is_equal(300.0)
	assert_bool(look.aim_assist).is_false()
