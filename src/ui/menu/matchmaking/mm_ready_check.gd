class_name MmReadyCheck
extends Control
## W17B-UI: the ready-check popup (design "Ready check": 10 s accept window).
## A full-screen dim that blocks the page, a card with MATCH FOUND, the
## queue, a big countdown, a draining bar, one pip per player (filled =
## accepted), ACCEPT and DECLINE.
## - Sound cue (UI "lock" event) and an OS attention request (taskbar flash)
##   when the window is not focused, on open.
## - Keyboard / pad: focus starts on ACCEPT; Enter / A accepts; Left / Right
##   move between the buttons. Esc does NOT decline (a decline is a lockout).
## - States: OPEN -> ACCEPTED (waiting for others) / DECLINED / MISSED
##   (the local timer ran out; the server's ready_result decides).
## Display only: the reply goes to `client.reply_ready(bool)`.

signal replied(accept: bool)

enum State { OPEN, ACCEPTED, DECLINED, MISSED }

var client: Object
var state: State = State.OPEN
var info: Dictionary = {}
var left_s: float = 10.0
var total_s: float = 10.0
## Tests: skip the OS attention request.
var request_attention: bool = true

var _count: Label
var _bar: ProgressBar
var _pips: HBoxContainer
var _accept: Button
var _decline: Button
var _status: Label
var _queue: Label
var _hints: HBoxContainer


func _ready() -> void:
	HudStrings.ensure_loaded()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	_build()
	_apply()
	UiSfx.play(&"lock")
	if request_attention and DisplayServer.get_name() != "headless" and not DisplayServer.window_is_focused():
		DisplayServer.window_request_attention()
	_accept.grab_focus.call_deferred()


## Opens with a MATCH_FOUND ({match_id, queue, deadline_s, humans, accepted}).
func open_with(found: Dictionary) -> void:
	info = found
	left_s = float(found.get("deadline_s", 10.0))
	total_s = maxf(left_s, 1.0)
	_apply()


## Later MATCH_FOUND updates (accept counts).
func update(found: Dictionary) -> void:
	info = found
	left_s = minf(left_s, float(found.get("deadline_s", left_s)))
	_apply()


func accept() -> void:
	if state != State.OPEN:
		return
	state = State.ACCEPTED
	if client != null:
		client.call("reply_ready", true)
	replied.emit(true)
	_apply()


func decline() -> void:
	if state != State.OPEN:
		return
	state = State.DECLINED
	if client != null:
		client.call("reply_ready", false)
	replied.emit(false)
	_apply()


func tick(delta: float) -> void:
	if state == State.DECLINED:
		return
	left_s = maxf(0.0, left_s - delta)
	if left_s <= 0.0 and state == State.OPEN:
		state = State.MISSED
	_apply()


func _process(delta: float) -> void:
	tick(delta)


func _build() -> void:
	var t := UiKit.tokens()
	var dim := ColorRect.new()
	dim.color = Color(t.bg_deep, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := MmKit.frame(32, Color(t.panel, 0.98), t.accent_dim)
	card.custom_minimum_size = Vector2(560, 0)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	var eb := UiKit.eyebrow(tr("HUD_MM_READY_EYEBROW"))
	eb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(eb)
	var title := MmKit.title(tr("HUD_MM_READY_TITLE"), 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_queue = UiKit.label("", &"small", t.text_dim, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_queue)
	_count = MmKit.mono("10", 64, t.accent_hi)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_count)
	_bar = MmKit.progress(t.accent, 3)
	col.add_child(_bar)
	_pips = HBoxContainer.new()
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_pips.add_theme_constant_override("separation", 6)
	col.add_child(_pips)
	_status = UiKit.label("", &"body", t.text_dim, HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	col.add_child(UiKit.spacer(4))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	_decline = UiKit.button(tr("HUD_MM_DECLINE"), decline, &"danger", 52)
	_decline.custom_minimum_size.x = 170
	row.add_child(_decline)
	_accept = UiKit.button(tr("HUD_MM_ACCEPT"), accept, &"play", 52)
	_accept.custom_minimum_size.x = 230
	_accept.add_theme_font_override("font", UiKit.display_font(700, UiKit.track(18, 0.24)))
	row.add_child(_accept)
	_accept.focus_neighbor_left = _accept.get_path_to(_decline)
	_decline.focus_neighbor_right = _decline.get_path_to(_accept)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	_hints.add_theme_constant_override("separation", 18)
	_hints.add_child(MmKit.key_hint("Enter", tr("HUD_MM_ACCEPT")))
	_hints.add_child(MmKit.key_hint("A", tr("HUD_MM_ACCEPT_PAD")))
	col.add_child(_hints)


func _apply() -> void:
	if _count == null:
		return
	var t := UiKit.tokens()
	_queue.text = tr(MmView.queue_key(StringName(info.get("queue", MmView.Q_NORMAL))))
	_count.text = str(MmView.secs(left_s))
	_count.add_theme_color_override("font_color", t.warn if left_s <= 3.0 else t.accent_hi)
	_bar.value = clampf(left_s / total_s, 0.0, 1.0)
	var humans := int(info.get("humans", 10))
	var acc := int(info.get("accepted", 0))
	if _pips.get_child_count() != humans:
		for c in _pips.get_children():
			_pips.remove_child(c)
			c.queue_free()
		for i in humans:
			var p := ColorRect.new()
			p.custom_minimum_size = Vector2(26, 6)
			_pips.add_child(p)
	for i in _pips.get_child_count():
		(_pips.get_child(i) as ColorRect).color = t.cyan if i < acc else t.line_strong
	var open := state == State.OPEN
	_accept.disabled = not open
	_decline.disabled = not open
	_accept.visible = state != State.DECLINED
	_decline.visible = open
	_hints.visible = open
	match state:
		State.OPEN:
			_status.text = tr("HUD_MM_READY_ACCEPTED_N") % [acc, humans]
		State.ACCEPTED:
			_accept.text = tr("HUD_MM_ACCEPTED")
			_status.text = tr("HUD_MM_READY_WAITING") % [acc, humans]
		State.DECLINED:
			_status.text = tr("HUD_MM_READY_YOU_DECLINED")
		State.MISSED:
			_status.text = tr("HUD_MM_READY_MISSED")


func _unhandled_input(event: InputEvent) -> void:
	if state != State.OPEN:
		return
	if event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A \
			and get_viewport().gui_get_focus_owner() == null:
		get_viewport().set_input_as_handled()
		accept()
