class_name TutorialOverlay
extends CanvasLayer
## First-time tutorial HUD of the Practice Range (W10-W4): offer panel, then
## one instruction at a time with the player's CURRENT bindings (InputBindings)
## and a gamepad hint; a step completes when TutorialObserver sees the action.
## Skippable at any step. Keys (data: PracticeRangeDef) work on keyboard and gamepad.

var client: ClientWorld
var range_def: PracticeRangeDef
var tutorial_def: TutorialDef
var model: TutorialModel
var observer: TutorialObserver
## true while the "take the tutorial?" offer is shown.
var offering: bool = false

var _panel: PanelContainer
var _title: Label
var _text: Label
var _pad: Label
var _hint: Label
var _flash_left: float = 0.0
var _held: Dictionary = {}


func setup(client_: ClientWorld, range_def_: PracticeRangeDef, tutorial_def_: TutorialDef) -> void:
	client = client_
	range_def = range_def_
	tutorial_def = tutorial_def_
	model = TutorialModel.new(tutorial_def)
	model.finished.connect(_on_finished)
	model.step_completed.connect(func(_i: int) -> void: _flash_left = tutorial_def.done_flash_s)
	observer = TutorialObserver.new(client)


func _ready() -> void:
	HudStrings.ensure_loaded()
	layer = 40
	_panel = MenuStyle.panel_container(Color(HudPalette.PANEL_STRONG, 0.9), 12)
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.position = Vector2(0.0, 150.0)
	_panel.custom_minimum_size = Vector2(560, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	_title = MenuStyle.label("", 14, HudPalette.TEXT_DIM)
	_text = MenuStyle.label("", 22, HudPalette.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pad = MenuStyle.label("", 14, HudPalette.TEXT_DIM)
	_hint = MenuStyle.label("", 13, HudPalette.TEXT_DIM)
	for l in [_title, _text, _pad, _hint]:
		v.add_child(l)
	_panel.visible = false
	_refresh()


## Starts (or replays) the tutorial from step 1.
func start() -> void:
	model.restart()
	offering = false
	_flash_left = 0.0
	_refresh()


## Shows the first-launch offer (start / skip).
func offer() -> void:
	offering = true
	_refresh()


func _on_finished(was_skipped: bool) -> void:
	GameSettings.shared().tutorial_done = true
	GameSettings.shared().save()
	_flash_left = 0.0 if was_skipped else 2.5
	_refresh()


func _process(delta: float) -> void:
	if range_def == null:
		return
	var start_key := _edge(range_def.key_tutorial, range_def.joy_tutorial)
	var skip_key := _edge(range_def.key_skip_step, range_def.joy_skip_step)
	var all_key := _edge(range_def.key_skip_all, range_def.joy_skip_all)
	if offering:
		if start_key:
			start()
		elif skip_key or all_key:
			offering = false
			GameSettings.shared().tutorial_done = true
			GameSettings.shared().save()
			_refresh()
		return
	if start_key:
		start()
		return
	if model.done:
		if _flash_left > 0.0:
			_flash_left -= delta
			if _flash_left <= 0.0:
				_refresh()
		return
	if all_key:
		model.skip_all()
	elif skip_key:
		model.skip_step()
		_refresh()
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_refresh()
		return
	if model.update(observer.poll()):
		_refresh()


func _edge(key: Key, joy: JoyButton) -> bool:
	var id := int(key) * 1000 + int(joy)
	var down := Input.is_physical_key_pressed(key) or Input.is_joy_button_pressed(0, joy)
	var was: bool = _held.get(id, false)
	_held[id] = down
	return down and not was


## Keys of `actions` joined with " / " (current bindings).
static func keys_text(actions: PackedStringArray) -> String:
	var b := GameSettings.shared().bindings
	var parts: Array[String] = []
	for a in actions:
		var t := InputBindings.spec_text(b.get_spec(a))
		if not parts.has(t):
			parts.append(t)
	return " / ".join(parts)


func _range_keys_hint() -> String:
	return tr("HUD_TUT_KEYS_HINT") % [OS.get_keycode_string(range_def.key_level_up),
		OS.get_keycode_string(range_def.key_reset), OS.get_keycode_string(range_def.key_tutorial)]


func _refresh() -> void:
	if _panel == null or model == null:
		return
	var skip_txt := "%s: %s    %s: %s" % [tr("HUD_TUT_SKIP_STEP"), OS.get_keycode_string(range_def.key_skip_step),
		tr("HUD_TUT_SKIP_ALL"), OS.get_keycode_string(range_def.key_skip_all)]
	if offering:
		_panel.visible = true
		_title.text = tr("HUD_TUT_OFFER")
		_text.text = "%s: %s    %s: %s" % [tr("HUD_TUT_OFFER_YES"), OS.get_keycode_string(range_def.key_tutorial),
			tr("HUD_TUT_OFFER_NO"), OS.get_keycode_string(range_def.key_skip_step)]
		_pad.text = ""
		_hint.text = _range_keys_hint()
		return
	if model.done:
		_panel.visible = _flash_left > 0.0 and not model.skipped
		_title.text = tr("HUD_TUT_DONE_TITLE")
		_text.text = tr("HUD_TUT_DONE_TEXT")
		_pad.text = ""
		_hint.text = _range_keys_hint()
		return
	var st := model.current()
	_panel.visible = true
	_title.text = tr("HUD_TUT_TITLE") % [model.index + 1, model.step_count()]
	var keys := keys_text(st.actions)
	_text.text = tr(st.text_key) % keys if "%s" in tr(st.text_key) else tr(st.text_key)
	_pad.text = "%s %s" % [tr("HUD_TUT_PAD_LABEL"), tr(st.pad_key)] if st.pad_key != "" else ""
	_hint.text = skip_txt
