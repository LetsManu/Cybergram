class_name SettingsPanel
extends VBoxContainer
## Options panel shared by the main menu and the pause menu. Edits
## GameSettings.shared(), saves on every change and applies volume / window
## mode at once. `changed` lets a running session re-apply look options.

signal changed
signal back_pressed

var _s: GameSettings


func _ready() -> void:
	HudStrings.ensure_loaded()
	_s = GameSettings.shared()
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(440, 0)
	add_child(_title(tr("HUD_SET_TITLE")))
	_slider(tr("HUD_SET_SENS"), GameSettings.SENS_MIN, GameSettings.SENS_MAX, 0.005, _s.mouse_sensitivity_deg,
		func(v: float) -> void: _s.mouse_sensitivity_deg = v, "%.3f")
	_slider(tr("HUD_SET_FOV"), GameSettings.FOV_MIN, GameSettings.FOV_MAX, 1.0, _s.fov_deg,
		func(v: float) -> void: _s.fov_deg = v, "%.0f°")
	_slider(tr("HUD_SET_VOLUME"), 0.0, 1.0, 0.05, _s.master_volume,
		func(v: float) -> void: _s.master_volume = v, "%.0f%%", 100.0)
	_check(tr("HUD_SET_INVERT"), _s.invert_y, func(on: bool) -> void: _s.invert_y = on)
	_check(tr("HUD_SET_FULLSCREEN"), _s.fullscreen, func(on: bool) -> void: _s.fullscreen = on)
	var back := Button.new()
	back.text = tr("HUD_SET_BACK")
	back.custom_minimum_size.y = 44
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)


## Focus the first control (keyboard / gamepad navigation).
func focus_first() -> void:
	for c in get_children():
		if c is HBoxContainer:
			var sl := (c as HBoxContainer).get_child(1) as Control
			sl.grab_focus()
			return


func _commit() -> void:
	_s.save()
	_s.apply_display()
	changed.emit()


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", HudPalette.TEXT)
	return l


func _slider(label: String, lo: float, hi: float, step: float, value: float, set_fn: Callable,
		fmt: String, display_mult: float = 1.0) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 170
	l.add_theme_color_override("font_color", HudPalette.TEXT_DIM)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size.x = 64
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = fmt % (value * display_mult)
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		set_fn.call(x)
		v.text = fmt % (x * display_mult)
		_commit())
	add_child(row)


func _check(label: String, on: bool, set_fn: Callable) -> void:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = on
	c.toggled.connect(func(x: bool) -> void:
		set_fn.call(x)
		_commit())
	add_child(c)
