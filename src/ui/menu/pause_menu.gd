class_name PauseMenu
extends CanvasLayer
## In-match Esc menu (overlay; receives `session`). The match keeps running
## (the server is authoritative and may be remote): opening it only stops the
## local hero's input and frees the mouse. Esc toggles it, except while the
## Armory panel is open (Esc closes the Armory first).

var session: Node

var _root: Control
var _main: VBoxContainer
var _settings: SettingsPanel
var _resume: Button
var _player: PlayerInputSource
var _ui_was_captured: bool = false


func _ready() -> void:
	HudStrings.ensure_loaded()
	layer = 60
	GameSettings.shared().apply_display()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks never reach the game
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.05, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	center.add_child(box)
	_main = VBoxContainer.new()
	_main.custom_minimum_size = Vector2(360, 0)
	_main.add_theme_constant_override("separation", 10)
	box.add_child(_main)
	var title := Label.new()
	title.text = tr("HUD_PAUSE_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", HudPalette.TEXT)
	_main.add_child(title)
	var note := Label.new()
	note.text = tr("HUD_PAUSE_NOTE")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", HudPalette.TEXT_DIM)
	_main.add_child(note)
	_resume = _button(tr("HUD_PAUSE_RESUME"), close)
	_button(tr("HUD_PAUSE_SETTINGS"), _show_settings)
	_button(tr("HUD_PAUSE_MENU"), _to_menu)
	_button(tr("HUD_PAUSE_QUIT"), func() -> void: get_tree().quit())
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.back_pressed.connect(_show_main)
	_settings.changed.connect(_apply_look)
	box.add_child(_settings)
	_apply_look()


func _process(_delta: float) -> void:
	if _player == null:
		_player = _find_input()
		if _player != null:
			_player.has_pause_menu = true
			var lc: Variant = session.get("launch_config")
			if lc != null and lc.debug_pause_menu:
				open.call_deferred()
	if _player != null and not _root.visible:
		_ui_was_captured = _player.ui_captured


func _input_event_is_cancel(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton
		and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START)


func _input(event: InputEvent) -> void:
	if _player == null or not _input_event_is_cancel(event):
		return
	if _root.visible:
		if _settings.visible:
			_show_main()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif not _ui_was_captured:
		open()
		get_viewport().set_input_as_handled()


func open() -> void:
	_root.visible = true
	_show_main()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _player != null:
		_player.paused = true


func close() -> void:
	_root.visible = false
	if _player != null:
		_player.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return _root.visible


func _show_main() -> void:
	_settings.visible = false
	_main.visible = true
	_resume.grab_focus()


func _show_settings() -> void:
	_main.visible = false
	_settings.visible = true
	_settings.focus_first()


func _to_menu() -> void:
	var remote: Variant = session.get("remote") if session != null else null
	if remote != null:
		remote.close()
	if _player != null:
		_player.paused = false
	AppRoot.back_to_menu(get_tree(), "")


## Pushes look settings onto the running session (sensitivity / invert live,
## FOV on the first-person camera).
func _apply_look() -> void:
	if session == null:
		return
	var look: Resource = session.get("look")
	GameSettings.shared().apply_look(look)
	var client: Variant = session.get("client")
	if client != null and client.rig != null and client.rig.camera != null:
		client.rig.camera.fov = GameSettings.shared().fov_deg


func _find_input() -> PlayerInputSource:
	if session == null:
		return null
	var client: Variant = session.get("client")
	if client == null:
		return null
	return client.player_input


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 46
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(on_press)
	_main.add_child(b)
	return b
