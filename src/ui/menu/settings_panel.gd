class_name SettingsPanel
extends VBoxContainer
## Tabbed options panel (Video / Audio / Controls / Gameplay) shared by the main
## menu and the pause menu. Edits GameSettings.shared(), saves on every change
## and applies it live; `changed` lets a running session re-apply look options.
## LB / RB (or Ctrl+Tab) switch tabs; Esc / B go back (cancel a key capture first).

signal changed
signal back_pressed

const TAB_KEYS: Array[String] = ["HUD_SET_TAB_VIDEO", "HUD_SET_TAB_AUDIO", "HUD_SET_TAB_CONTROLS",
	"HUD_SET_TAB_GAMEPLAY"]
const CONTENT_H := 470.0

var _s: GameSettings
var _tab_buttons: Array[Button] = []
var _scroll: ScrollContainer
var _tab: SettingsTab
var _index: int = 0
## Debug / tests: tab to show first.
var start_tab: int = 0


func _ready() -> void:
	HudStrings.ensure_loaded()
	_s = GameSettings.shared()
	theme = SettingsTheme.build()
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(620, 0)
	var title := Label.new()
	title.text = tr("HUD_SET_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", HudPalette.TEXT)
	add_child(title)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	var group := ButtonGroup.new()
	for i in TAB_KEYS.size():
		var b := Button.new()
		b.text = tr(TAB_KEYS[i])
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 40
		b.pressed.connect(show_tab.bind(i))
		bar.add_child(b)
		_tab_buttons.append(b)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", SettingsTheme.frame())
	add_child(frame)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, CONTENT_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(_scroll)
	var hint := Label.new()
	hint.text = tr("HUD_SET_TAB_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", HudPalette.TEXT_OFF)
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)
	var back := Button.new()
	back.text = tr("HUD_SET_BACK")
	back.custom_minimum_size.y = 44
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)
	visibility_changed.connect(func() -> void:
		if visible:
			show_tab(_index))
	show_tab(start_tab)


## Index of the tab on screen.
func current_tab() -> int:
	return _index


## Shows tab `i` (rebuilt from the current settings).
func show_tab(i: int) -> void:
	_index = posmod(i, TAB_KEYS.size())
	_tab_buttons[_index].set_pressed_no_signal(true)
	if _tab != null:
		_tab.queue_free()
		_tab = null
	match _index:
		0:
			_tab = SettingsTabVideo.new()
		1:
			_tab = SettingsTabAudio.new()
		2:
			_tab = SettingsTabControls.new()
		_:
			_tab = SettingsTabGameplay.new()
	_tab.s = _s
	_tab.commit = _commit
	_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab.add_theme_constant_override("separation", 8)
	_scroll.add_child(_tab)
	_tab.build()
	_scroll.scroll_vertical = 0


## Focus the current tab button (keyboard / gamepad navigation).
func focus_first() -> void:
	_tab_buttons[_index].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			show_tab(_index + 1)
			get_viewport().set_input_as_handled()
		elif event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			show_tab(_index - 1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB and event.ctrl_pressed:
		show_tab(_index + (-1 if event.shift_pressed else 1))
		get_viewport().set_input_as_handled()


func _commit() -> void:
	_s.save()
	_s.apply_display()
	_s.apply_bindings()
	changed.emit()
