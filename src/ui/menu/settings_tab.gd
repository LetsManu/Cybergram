class_name SettingsTab
extends VBoxContainer
## Base of one settings tab: row factories plus the shared `commit` callback
## (the panel saves, applies live and emits `changed`). Subclasses override
## build(); the panel rebuilds tabs whenever it is shown, so values changed
## elsewhere (F-key toggles) are current.

var s: GameSettings
var commit: Callable


## Fills the tab (override).
func build() -> void:
	pass


## The first focusable control (keyboard / gamepad entry point).
func first_focus() -> Control:
	return _find_focusable(self)


func _find_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL:
			return c
		var r := _find_focusable(c)
		if r != null:
			return r
	return null


func section(text: String) -> void:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", SettingsTheme.ACCENT.lightened(0.35))
	var box := MarginContainer.new()
	box.add_theme_constant_override("margin_top", 8)
	box.add_child(l)
	add_child(box)
	add_child(HSeparator.new())


func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 200
	l.add_theme_color_override("font_color", HudPalette.TEXT_DIM)
	row.add_child(l)
	add_child(row)
	return row


## Slider row; `on_change(value)` gets the raw value. The label shows value * mult.
func slider(label: String, lo: float, hi: float, step: float, value: float, fmt: String,
		on_change: Callable, mult: float = 1.0) -> HSlider:
	var row := _row(label)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size.y = 24
	row.add_child(sl)
	var v := Label.new()
	v.custom_minimum_size.x = 64
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = fmt % (value * mult)
	row.add_child(v)
	sl.value_changed.connect(func(x: float) -> void:
		on_change.call(x)
		v.text = fmt % (x * mult)
		commit.call())
	return sl


func check(label: String, on: bool, on_change: Callable) -> CheckButton:
	var row := _row(label)
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(func(x: bool) -> void:
		on_change.call(x)
		commit.call())
	row.add_child(c)
	return c


## Drop-down row over already translated `items`.
func option(label: String, items: Array, selected: int, on_change: Callable) -> OptionButton:
	var row := _row(label)
	var o := OptionButton.new()
	o.custom_minimum_size.x = 200
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		o.add_item(str(it))
	o.selected = selected
	o.item_selected.connect(func(i: int) -> void:
		on_change.call(i)
		commit.call())
	row.add_child(o)
	return o
