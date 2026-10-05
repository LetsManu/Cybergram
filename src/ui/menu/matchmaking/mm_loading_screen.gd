class_name MmLoadingScreen
extends Control
## W17B-UI: match loading / connection screen (design "Join tickets",
## "Reconnect"). Both teams as portrait cards (hero, name, lane) over the
## map name; a status line and a progress line under them.
## States: CONNECTING (ticket received, the game client is starting) ->
## the flow hands over to the match; DISCONNECTED (the match link dropped
## while the match runs: RECONNECT asks the front for a fresh ticket, LEAVE
## returns to the menu; leaving counts as abandoning); FAILED (the match is
## gone: back to PLAY).

signal reconnect_requested()
signal leave_requested()

enum State { CONNECTING, DISCONNECTED, FAILED }

var state: State = State.CONNECTING
var info: Dictionary = {}
var seats: Array = []
var my_team: int = 0

var _map: Label
var _status: Label
var _bar: ProgressBar
var _teams: Array[HBoxContainer] = []
var _reconnect: Button
var _leave: Button
var _spin: float = 0.0


func _ready() -> void:
	HudStrings.ensure_loaded()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	_build()
	_apply()


## The MATCH_ASSIGNED info and the seats of the last pick state.
func setup(assigned: Dictionary, seats_: Array, my_team_: int) -> void:
	info = assigned
	seats = seats_
	my_team = my_team_
	state = State.CONNECTING
	_apply()


func set_state(s: State) -> void:
	state = s
	_apply()
	if s == State.DISCONNECTED and _reconnect != null:
		_reconnect.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if state == State.CONNECTING and _bar != null:
		_spin += delta
		_bar.value = 0.15 + 0.8 * clampf(_spin / 3.0, 0.0, 1.0) if not UiKit.reduce_motion() else 0.5


func _build() -> void:
	var t := UiKit.tokens()
	var bg := UiKit.background()
	UiKit.set_background_layout(bg, 720.0, Vector2(720, 405), 360.0, true)
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 80
	col.offset_right = -80
	col.offset_top = 56
	col.offset_bottom = -56
	col.add_theme_constant_override("separation", 22)
	add_child(col)
	var eb := UiKit.eyebrow(tr("HUD_MM_LOADING_EYEBROW"))
	eb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(eb)
	_map = MmKit.title("", 34)
	_map.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_map)
	for i in 2:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 18)
		col.add_child(row)
		_teams.append(row)
		if i == 0:
			var vs := MmKit.caption(tr("HUD_MM_VS"), 13, t.text_off)
			vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(vs)
	_status = UiKit.label("", &"body", t.text_dim, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_status)
	_bar = MmKit.progress(t.accent, 2)
	_bar.custom_minimum_size.x = 480
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_bar)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	col.add_child(btns)
	_leave = UiKit.button(tr("HUD_MM_LEAVE_MATCH"), func() -> void: leave_requested.emit(), &"ghost", 48)
	_leave.custom_minimum_size.x = 160
	btns.add_child(_leave)
	_reconnect = UiKit.button(tr("HUD_MM_RECONNECT"), func() -> void: reconnect_requested.emit(), &"play", 48)
	_reconnect.name = "Reconnect"
	_reconnect.custom_minimum_size.x = 240
	btns.add_child(_reconnect)


func _apply() -> void:
	if _map == null:
		return
	var t := UiKit.tokens()
	var map := StringName(info.get("map", &""))
	_map.text = (tr("HUD_MM_MAP_SLICE") if map == &"slice" else tr("HUD_MM_MAP_SHARDLINE")).to_upper()
	for i in 2:
		for c in _teams[i].get_children():
			_teams[i].remove_child(c)
			c.queue_free()
	for s: Dictionary in seats:
		var team := int(s.get("team", 0))
		_teams[0 if team == my_team else 1].add_child(_card(s, team == my_team))
	_reconnect.visible = state == State.DISCONNECTED
	_leave.visible = state != State.CONNECTING
	match state:
		State.CONNECTING:
			_status.text = tr("HUD_MM_CONNECTING")
			_status.add_theme_color_override("font_color", t.text_dim)
		State.DISCONNECTED:
			_status.text = tr("HUD_MM_DISCONNECTED")
			_status.add_theme_color_override("font_color", t.warn)
			_bar.value = 0.0
		State.FAILED:
			_status.text = tr("HUD_MM_MATCH_GONE")
			_status.add_theme_color_override("font_color", t.danger)
			_bar.value = 0.0


func _card(s: Dictionary, ally: bool) -> Control:
	var t := UiKit.tokens()
	var p := MmKit.frame(0, Color(t.panel_raised, 0.9), t.accent_dim if ally else Color(t.danger, 0.5))
	p.custom_minimum_size = Vector2(176, 236)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var hero := StringName(s.get("hero", &""))
	var img := TextureRect.new()
	img.custom_minimum_size = Vector2(176, 176)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var e := MmView.hero_entry(hero)
	img.texture = UiKit.portrait_texture(str(e.stem)) if not e.is_empty() else null
	v.add_child(img)
	var nm := UiKit.label(MmView.hero_name(hero).to_upper(), &"small", t.text, HORIZONTAL_ALIGNMENT_CENTER)
	nm.add_theme_font_override("font", UiKit.display_font(600, 2))
	v.add_child(nm)
	var lane := StringName(s.get("lane", &""))
	var who := str(s.get("name", ""))
	if ally and lane != &"":
		who = "%s · %s" % [who, tr(MmView.lane_key(lane))]
	if bool(s.get("bot", false)):
		who = "%s · %s" % [tr("HUD_MM_BOT_TAG"), who]
	var l := UiKit.label(who, &"caption", t.text_dim, HORIZONTAL_ALIGNMENT_CENTER)
	l.clip_text = true
	v.add_child(l)
	return p
