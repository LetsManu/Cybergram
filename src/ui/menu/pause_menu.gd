class_name PauseMenu
extends CanvasLayer
## In-match Esc menu (overlay; receives `session`). The match keeps running
## (the server is authoritative and may be remote): opening it only stops the
## local hero's input and frees the mouse. Esc toggles it, except while the
## Armory panel is open (Esc closes the Armory first).

var session: Node

var _root: Control
var _main: VBoxContainer
var _card: PanelContainer
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
	_root.theme = UiKit.theme()
	var t := UiKit.tokens()
	var dim := ColorRect.new()
	dim.color = Color(t.bg_deep, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	center.add_child(box)
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(400, 0)
	box.add_child(_card)
	_main = UiKit.screen_frame(_card, tr("HUD_PAUSE_TITLE"), "", 22)
	_main.add_theme_constant_override("separation", t.space_m)
	var note := UiKit.label(tr("HUD_PAUSE_NOTE"), &"small", t.text_dim)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main.add_child(note)
	_main.add_child(UiKit.spacer(2))
	_resume = _button(tr("HUD_PAUSE_RESUME"), close, &"primary")
	_button(tr("HUD_PAUSE_SETTINGS"), _show_settings)
	_button(tr("HUD_PAUSE_MENU"), _to_menu)
	_main.add_child(HSeparator.new())
	_button(tr("HUD_PAUSE_QUIT"), func() -> void: get_tree().quit(), &"danger")
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
				if lc.debug_settings_tab >= 0:
					_settings.show_tab.call_deferred(lc.debug_settings_tab)
					_show_settings.call_deferred()
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
	_card.visible = true
	UiKit.transition_in(_card)
	_resume.grab_focus()


func _show_settings() -> void:
	_card.visible = false
	_settings.visible = true
	UiKit.transition_in(_settings)
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


func _button(text: String, on_press: Callable, kind: StringName = &"secondary") -> Button:
	var b := UiKit.button(text, on_press, kind, 46)
	_main.add_child(b)
	return b
