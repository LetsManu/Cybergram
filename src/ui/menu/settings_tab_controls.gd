class_name SettingsTabControls
extends SettingsTab
## Controls tab: mouse look (sensitivity, invert Y, FOV) and the full rebind
## list. Click a row (or press Accept on it) -> "press a key..." -> the next key
## or mouse button is bound; Esc cancels. A conflict swaps the two actions and
## says so. Reset restores every default binding.
## W11-C1: a Keyboard / Gamepad toggle switches the rebind list between the
## key/mouse specs and the joypad specs (buttons, stick directions, triggers are
## captured the same way); the gamepad options (stick sensitivity, dead zone,
## response curve, invert Y, aim assist) sit above the list.

## Emitted while a capture is running (the panel must not treat Esc as Back).
signal capture_changed(active: bool)

const GROUP_KEYS := {
	"move": "HUD_SET_SEC_MOVE", "combat": "HUD_SET_SEC_COMBAT", "skills": "HUD_SET_SEC_SKILLS",
	"squad": "HUD_SET_SEC_SQUAD", "interface": "HUD_SET_SEC_INTERFACE",
}
const ACTION_KEYS := {
	"move_forward": "HUD_ACT_MOVE_FORWARD", "move_back": "HUD_ACT_MOVE_BACK",
	"move_left": "HUD_ACT_MOVE_LEFT", "move_right": "HUD_ACT_MOVE_RIGHT",
	"jump": "HUD_ACT_JUMP", "crouch": "HUD_ACT_CROUCH", "sprint": "HUD_ACT_SPRINT",
	"fire": "HUD_ACT_FIRE", "alt_fire": "HUD_ACT_ALT_FIRE", "reload": "HUD_ACT_RELOAD", "interact": "HUD_ACT_INTERACT",
	"use_medpack": "HUD_ACT_MEDPACK", "skill_1": "HUD_ACT_SKILL_1", "skill_2": "HUD_ACT_SKILL_2",
	"skill_3": "HUD_ACT_SKILL_3", "skill_4": "HUD_ACT_SKILL_4", "quick_spend": "HUD_ACT_QUICK_SPEND",
	"fork_a": "HUD_ACT_FORK_A", "fork_b": "HUD_ACT_FORK_B",
	"squad_smart": "HUD_ACT_SQUAD_SMART", "squad_follow": "HUD_ACT_SQUAD_FOLLOW",
	"squad_wheel": "HUD_ACT_SQUAD_WHEEL", "open_shop": "HUD_ACT_OPEN_SHOP",
	"scoreboard": "HUD_ACT_SCOREBOARD", "net_graph": "HUD_ACT_NET_GRAPH", "pause": "HUD_ACT_PAUSE",
}

var _buttons: Dictionary = {}  # action -> Button
var _notice: Label
var _reset_button: Button
var _pad_mode: bool = false
var _capturing: String = ""
var _capture_armed_at: int = 0


func build() -> void:
	# Open on the gamepad list when a pad is plugged in (or CYBERGRAM_DEBUG_PAD=1,
	# used for screenshots).
	_pad_mode = not Input.get_connected_joypads().is_empty() or OS.get_environment("CYBERGRAM_DEBUG_PAD") == "1"
	option(tr("HUD_SET_INPUT_DEVICE"), [tr("HUD_SET_DEVICE_KEYBOARD"), tr("HUD_SET_DEVICE_GAMEPAD")],
		1 if _pad_mode else 0, _set_pad_mode)
	section(tr("HUD_SET_SEC_VIEW"))
	slider(tr("HUD_SET_SENS"), GameSettings.SENS_MIN, GameSettings.SENS_MAX, 0.005, s.mouse_sensitivity_deg,
		"%.3f", func(v: float) -> void: s.mouse_sensitivity_deg = v)
	slider(tr("HUD_SET_FOV"), GameSettings.FOV_MIN, GameSettings.FOV_MAX, 1.0, s.fov_deg, "%.0f°",
		func(v: float) -> void: s.fov_deg = v)
	check(tr("HUD_SET_INVERT"), s.invert_y, func(on: bool) -> void: s.invert_y = on)
	section(tr("HUD_SET_SEC_GAMEPAD"))
	slider(tr("HUD_SET_PAD_SENS"), GameSettings.PAD_SENS_MIN, GameSettings.PAD_SENS_MAX, 5.0,
		s.pad_sensitivity_deg_s, "%.0f°/s", func(v: float) -> void: s.pad_sensitivity_deg_s = v)
	slider(tr("HUD_SET_PAD_DEADZONE"), GameSettings.PAD_DEADZONE_MIN, GameSettings.PAD_DEADZONE_MAX, 0.01,
		s.pad_deadzone, "%.0f%%", func(v: float) -> void: s.pad_deadzone = v, 100.0)
	slider(tr("HUD_SET_PAD_CURVE"), GameSettings.PAD_CURVE_MIN, GameSettings.PAD_CURVE_MAX, 0.05,
		s.pad_curve, "%.2f", func(v: float) -> void: s.pad_curve = v)
	check(tr("HUD_SET_PAD_INVERT"), s.pad_invert_y, func(on: bool) -> void: s.pad_invert_y = on)
	check(tr("HUD_SET_AIM_ASSIST"), s.aim_assist, func(on: bool) -> void: s.aim_assist = on)
	_notice = Label.new()
	_notice.add_theme_color_override("font_color", HudPalette.WARN)
	_notice.text = tr("HUD_SET_CAPTURE_HINT_PAD") if _pad_mode else tr("HUD_SET_CAPTURE_HINT")
	_notice.add_theme_color_override("font_color", HudPalette.TEXT_DIM)
	var reset := Button.new()
	reset.text = tr("HUD_SET_RESET_PAD") if _pad_mode else tr("HUD_SET_RESET_BINDINGS")
	reset.pressed.connect(_reset)
	_reset_button = reset
	add_child(reset)
	add_child(_notice)
	for g in InputBindings.GROUPS:
		section(tr(GROUP_KEYS[g]))
		for a in InputBindings.ACTIONS:
			if a[1] == g:
				_binding_row(a[0])
	_refresh_texts()


func _binding_row(action: String) -> void:
	var row := _row(tr(ACTION_KEYS[action]))
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 30
	b.pressed.connect(func() -> void: _begin_capture(action))
	row.add_child(b)
	_buttons[action] = b


func _refresh_texts(highlight: Array = []) -> void:
	for action in _buttons:
		var b: Button = _buttons[action]
		b.text = tr("HUD_SET_PRESS_BUTTON" if _pad_mode else "HUD_SET_PRESS_KEY") if action == _capturing else _spec_text(action)
		var col := HudPalette.TEXT
		if action == _capturing:
			col = HudPalette.LUMEN
		elif action in highlight:
			col = HudPalette.WARN
		b.add_theme_color_override("font_color", col)


func _spec_text(action: String) -> String:
	if _pad_mode:
		return InputBindings.joy_spec_text(s.bindings.get_pad_spec(action))
	return InputBindings.spec_text(s.bindings.get_spec(action))


## Keyboard / Gamepad toggle: same rows, other binding map.
func _set_pad_mode(index: int) -> void:
	_end_capture()
	_pad_mode = index == 1
	_reset_button.text = tr("HUD_SET_RESET_PAD") if _pad_mode else tr("HUD_SET_RESET_BINDINGS")
	_notice.text = tr("HUD_SET_CAPTURE_HINT_PAD") if _pad_mode else tr("HUD_SET_CAPTURE_HINT")
	_notice.add_theme_color_override("font_color", HudPalette.TEXT_DIM)
	_refresh_texts()


## True while the list shows the gamepad bindings.
func is_pad_mode() -> bool:
	return _pad_mode


func _begin_capture(action: String) -> void:
	_capturing = action
	_capture_armed_at = Time.get_ticks_msec()
	_notice.text = tr("HUD_SET_CAPTURE_HINT_PAD") if _pad_mode else tr("HUD_SET_CAPTURE_HINT")
	_notice.add_theme_color_override("font_color", HudPalette.LUMEN)
	_refresh_texts()
	capture_changed.emit(true)


func _end_capture() -> void:
	_capturing = ""
	capture_changed.emit(false)


func _input(event: InputEvent) -> void:
	if _capturing == "" or not is_visible_in_tree():
		return
	if Time.get_ticks_msec() - _capture_armed_at < 120:
		return  # the click / Accept that started the capture
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_end_capture()
		_refresh_texts()
		_notice.add_theme_color_override("font_color", HudPalette.TEXT_DIM)
		return
	var spec := InputBindings.joy_spec_from_event(event) if _pad_mode else InputBindings.spec_from_event(event)
	if spec == InputBindings.UNBOUND:
		return
	get_viewport().set_input_as_handled()
	var action := _capturing
	_end_capture()
	apply_binding(action, spec)


## Binds `spec` to `action` (swapping on conflict), saves and reports it.
func apply_binding(action: String, spec: String) -> void:
	var other := s.bindings.assign_pad(action, spec) if _pad_mode else s.bindings.assign(action, spec)
	commit.call()
	if other != "":
		_notice.text = tr("HUD_SET_SWAPPED_PAD" if _pad_mode else "HUD_SET_SWAPPED") % [tr(ACTION_KEYS[action]), tr(ACTION_KEYS[other])]
		_notice.add_theme_color_override("font_color", HudPalette.WARN)
		_refresh_texts([action, other])
	else:
		_notice.text = tr("HUD_SET_CAPTURE_HINT_PAD") if _pad_mode else tr("HUD_SET_CAPTURE_HINT")
		_notice.add_theme_color_override("font_color", HudPalette.TEXT_DIM)
		_refresh_texts()


func _reset() -> void:
	_end_capture()
	if _pad_mode:
		s.bindings.reset_pad()
	else:
		s.bindings.reset_all()
	commit.call()
	_notice.text = tr("HUD_SET_RESET_DONE_PAD") if _pad_mode else tr("HUD_SET_RESET_DONE")
	_notice.add_theme_color_override("font_color", HudPalette.HEAL)
	_refresh_texts()


## True while waiting for a key press.
func is_capturing() -> bool:
	return _capturing != ""
