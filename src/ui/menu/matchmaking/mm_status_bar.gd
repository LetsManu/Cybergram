class_name MmStatusBar
extends PanelContainer
## P1: the persistent status strip at the bottom of the matchmaking flow:
## connection + ping, the server-side phase, queue timer with estimate,
## lockout countdown and a plain-language hint when a wait runs long. The
## "Diagnostics" button opens the last client events with a Copy button.
## Display only: everything comes from MmStatusModel (fed by the client
## adapter); the bar never decides anything. Visual check: see
## docs/manual-checklist.md.
##
## Example (MatchmakingFlow):
##   var bar := MmStatusBar.new()
##   bar.client = client          # MmClientAdapter (or the fake: then it stays quiet)
##   add_child(bar)

const HEIGHT := 30

## MmClientAdapter-like object: signals phase_changed / connection_changed,
## methods connection_info() and diagnostics_text() (all optional).
var client: Object
var model := MmStatusModel.new()
var clock: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0

var _conn: Label
var _phase: Label
var _timer: Label
var _hint: Label
var _diag_btn: Button
var _diag: PanelContainer
var _diag_text: TextEdit
var _since_poll: float = 0.0


func _ready() -> void:
	var t := UiKit.tokens()
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -HEIGHT
	grow_vertical = Control.GROW_DIRECTION_BEGIN  # taller content grows up, never off-screen
	add_theme_stylebox_override("panel", UiKit.panel_box(t.panel_sunken, 4, t.line))
	mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	_conn = UiKit.label("", &"caption")
	_phase = UiKit.label("", &"caption", t.text)
	_timer = MmKit.mono("", 13)
	_hint = UiKit.label("", &"caption")
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_diag_btn = Button.new()  # compact: a full UiKit button is taller than the strip
	_diag_btn.text = tr("HUD_MMS_DIAG")
	_diag_btn.flat = true
	_diag_btn.focus_mode = Control.FOCUS_ALL
	_diag_btn.add_theme_font_size_override("font_size", UiKit.size_of(&"caption"))
	_diag_btn.add_theme_color_override("font_color", t.text_dim)
	_diag_btn.add_theme_stylebox_override("focus", UiKit.focus_box())
	_diag_btn.pressed.connect(toggle_diagnostics)
	for c in [_conn, _phase, _timer, _hint, _diag_btn]:
		row.add_child(c)
	_build_diagnostics()
	if client == null or not client.has_method("connection_info"):
		model.set_connection(MmStatusModel.Conn.ONLINE, clock.call())  # offline fake / preview
	if client != null:
		if client.has_signal("phase_changed"):
			client.connect("phase_changed", func(d: Dictionary) -> void: model.set_phase(d, clock.call()))
		if client.has_signal("connection_changed"):
			client.connect("connection_changed", func(st: int, rtt: int) -> void:
				model.set_connection(st as MmStatusModel.Conn, clock.call(), rtt))
	_refresh()


func _process(delta: float) -> void:
	_since_poll += delta
	if _since_poll >= 0.5:
		_since_poll = 0.0
		if client != null and client.has_method("connection_info"):
			var ci: Dictionary = client.call("connection_info")
			model.set_connection(int(ci.get("state", MmStatusModel.Conn.ONLINE)) as MmStatusModel.Conn, clock.call(),
				int(ci.get("rtt_ms", -1)))
		_refresh()


func _refresh() -> void:
	var t := UiKit.tokens()
	var v := model.view(clock.call())
	var col: Color = {&"ok": t.ok, &"busy": t.accent, &"warn": t.warn, &"error": t.danger}.get(v.tone, t.text_dim)
	_conn.text = tr(v.connection) + (("  " + v.ping) if v.ping != "" else "")
	_conn.add_theme_color_override("font_color", col)
	_phase.text = tr(v.phase) if v.phase != "" else ""
	var timer: String = v.timer
	if v.lockout != "":
		timer = tr("HUD_MMS_LOCKED") % v.lockout
	_timer.text = timer
	_hint.text = tr(v.hint) if v.hint != "" else ""
	_hint.add_theme_color_override("font_color", col if v.tone != &"ok" else t.text_dim)
	if _diag.visible and client != null and client.has_method("diagnostics_text"):
		_diag_text.text = client.call("diagnostics_text")


func toggle_diagnostics() -> void:
	_diag.visible = not _diag.visible
	if _diag.visible:
		_refresh()
		_diag_text.grab_focus()


func _build_diagnostics() -> void:
	var t := UiKit.tokens()
	_diag = PanelContainer.new()
	_diag.visible = false
	_diag.add_theme_stylebox_override("panel", UiKit.panel_box(t.panel, 10))
	_diag.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_diag.offset_left = -576
	_diag.offset_top = -316 - HEIGHT
	_diag.offset_right = -16
	_diag.offset_bottom = -8 - HEIGHT
	var col := VBoxContainer.new()
	_diag.add_child(col)
	col.add_child(UiKit.label(tr("HUD_MMS_DIAG_TITLE"), &"heading"))
	_diag_text = TextEdit.new()
	_diag_text.editable = false
	_diag_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_diag_text.add_theme_font_override("font", UiKit.mono_font())
	_diag_text.add_theme_font_size_override("font_size", 12)
	col.add_child(_diag_text)
	var row := HBoxContainer.new()
	col.add_child(row)
	row.add_child(UiKit.button(tr("HUD_MMS_COPY"), func() -> void:
		DisplayServer.clipboard_set(_diag_text.text)
		UiKit.toast(get_parent() as Control, tr("HUD_MMS_COPIED"), &"info"), &"secondary"))
	row.add_child(UiKit.button(tr("HUD_MMS_CLOSE"), toggle_diagnostics, &"ghost"))
	# A sibling, not a child: a PanelContainer would stretch it over the bar.
	var host: Node = get_parent() if get_parent() != null else self
	host.add_child.call_deferred(_diag)
