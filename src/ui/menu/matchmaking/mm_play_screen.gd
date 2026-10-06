class_name MmPlayScreen
extends Control
## W17B-UI: the PLAY page (design/gdd/matchmaking.md "Queues", "Lane
## preference", "Parties", "Low population"). LoL client style:
## - left: the queue picker (Normal 5v5, Ranked 5v5 with your medal or
##   "Calibrating x/N", 3v3 All Random labelled as the fun mode, Custom)
## - right: lane preference (primary + secondary, or Fill), the party (up to
##   5 seats, with the ranked party rules) and the queue strip
## - queued: elapsed timer, estimated wait, players in queue, CANCEL
## - locked out: a banner with the remaining time; FIND MATCH disabled.
## States: IDLE -> QUEUED -> (match found: the flow opens the ready check)
## and LOCKED. Display only: requests go to `client` (join_queue / leave_queue).

signal back_requested()
## The Custom queue's CTA: open the custom lobby.
signal custom_requested()

enum State { IDLE, QUEUED, LOCKED }

## The matchmaking client (MatchmakingFakeClient or the network client).
var client: Object
var rules: MatchmakingRulesDef
var state: State = State.IDLE
var queue: StringName = MmView.Q_NORMAL
var primary: StringName = &"north"
var secondary: StringName = &"center"
## Seconds in queue / estimate / players (from the last status).
var waited: float = 0.0
var estimate: float = 0.0
var in_queue: int = 0
var locked_left: float = 0.0

var _queue_rows: Dictionary = {}  # queue id -> {button, meta, marker}
var _ranked_meta: Label
var _primary_chips: Dictionary = {}
var _secondary_chips: Dictionary = {}
var _party_rows: VBoxContainer
var _party_rules: Label
## P2: party chat (shown in a party of 2+ when the client supports it).
var _chat: SocialChatBox
var _party_count: Label
var _find: Button
var _cancel: Button
var _queue_box: VBoxContainer
var _elapsed: Label
var _wait_line: Label
var _lock_banner: PanelContainer
var _lane_box: Control
var _members: Array = []


func _ready() -> void:
	HudStrings.ensure_loaded()
	if rules == null:
		rules = MatchmakingRulesDef.load_default()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	_build()
	select_queue(queue)
	set_party({"members": [{"id": "me", "name": tr("HUD_LOBBY_YOU"), "leader": true, "me": true}]})
	_sync()
	(func() -> void: (_queue_rows[queue].button as Button).grab_focus()).call_deferred()


func _build() -> void:
	var t := UiKit.tokens()
	add_child(MmKit.place(MmKit.back_link(tr("HUD_MODE_BACK"), func() -> void: back_requested.emit()), Vector2(40, 22)))
	var eb := UiKit.eyebrow(tr("HUD_MM_PLAY_EYEBROW"))
	add_child(MmKit.place(eb, Vector2(64, 74)))
	# Queue picker (left column).
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	add_child(MmKit.place(list, Vector2(48, 108), 560))
	var group := ButtonGroup.new()
	for q: Array in MmView.QUEUES:
		var id: StringName = q[0]
		var b := Button.new()
		b.name = "Queue_" + String(id)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(560, 104)
		var row_sb := UiKit.underline_box(t.line)
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, row_sb)
		b.add_theme_stylebox_override("focus", UiKit.focus_box())
		var marker := UiIcon.make(&"diamond", 12, t.accent)
		marker.position = Vector2(16, 34)
		b.add_child(marker)
		var nm := Label.new()
		nm.text = tr(q[1])
		nm.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(30, 0.04)))
		nm.add_theme_font_size_override("font_size", 30)
		nm.position = Vector2(44, 12)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(nm)
		var meta := Label.new()
		meta.text = tr(q[2])
		meta.add_theme_font_size_override("font_size", 13)
		meta.add_theme_color_override("font_color", t.text_dim)
		meta.position = Vector2(44, 60)
		meta.size = Vector2(500, 36)
		meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(meta)
		if id == MmView.Q_ARAM:
			var tag := MmKit.caption(tr("HUD_MM_FUN_TAG"), 11, t.cyan)
			tag.position = Vector2(420, 22)
			b.add_child(tag)
		if id == MmView.Q_RANKED:
			_ranked_meta = MmKit.caption("", 11, t.accent_hi)
			_ranked_meta.position = Vector2(330, 22)
			_ranked_meta.size.x = 200
			_ranked_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			b.add_child(_ranked_meta)
		b.pressed.connect(func() -> void: select_queue(id))
		b.focus_entered.connect(func() -> void:
			if state == State.IDLE or state == State.LOCKED:
				select_queue(id))
		UiSfx.attach(b)
		list.add_child(b)
		_queue_rows[id] = {"button": b, "marker": marker, "name": nm}
	set_ranked({})
	# Right column: lanes, party, queue strip.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 18)
	add_child(MmKit.place(right, Vector2(680, 108), 640))
	_lock_banner = MmKit.banner("", &"danger")
	_lock_banner.visible = false
	right.add_child(_lock_banner)
	var lanes := VBoxContainer.new()
	lanes.add_theme_constant_override("separation", 8)
	_lane_box = lanes
	right.add_child(lanes)
	lanes.add_child(MmKit.caption(tr("HUD_MM_LANE_PRIMARY")))
	lanes.add_child(_lane_row(true))
	lanes.add_child(MmKit.caption(tr("HUD_MM_LANE_SECONDARY")))
	lanes.add_child(_lane_row(false))
	right.add_child(UiKit.hairline())
	var ph := HBoxContainer.new()
	ph.add_child(MmKit.caption(tr("HUD_MM_PARTY")))
	_party_count = MmKit.caption("", 11, t.text_off)
	_party_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ph.add_child(_party_count)
	right.add_child(ph)
	_party_rows = VBoxContainer.new()
	_party_rows.add_theme_constant_override("separation", 6)
	right.add_child(_party_rows)
	_party_rules = UiKit.label("", &"small", t.text_dim)
	_party_rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_party_rules)
	if client != null and client.has_method("party_say"):
		_chat = SocialChatBox.new()
		_chat.view_height = 70.0
		_chat.send = func(text: String) -> void: client.call("party_say", text)
		_chat.visible = false
		right.add_child(_chat)
		if client.has_signal("party_chat_changed"):
			client.connect("party_chat_changed", func() -> void:
				if _chat != null:
					_chat.set_lines(client.call("party_chat_lines")))
	# Queue strip + CTA (bottom right).
	var foot := HBoxContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	foot.offset_left = -760
	foot.offset_right = -120
	foot.offset_top = -112
	foot.offset_bottom = -48
	foot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 20)
	add_child(foot)
	_queue_box = VBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 2)
	_queue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_box.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_child(_queue_box)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	top.add_theme_constant_override("separation", 12)
	_queue_box.add_child(top)
	var searching := MmKit.caption(tr("HUD_MM_IN_QUEUE"), 12, t.cyan)
	searching.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(searching)
	_elapsed = MmKit.mono("0:00", 30)
	top.add_child(_elapsed)
	_wait_line = UiKit.label("", &"small", t.text_dim, HORIZONTAL_ALIGNMENT_RIGHT)
	_queue_box.add_child(_wait_line)
	_cancel = UiKit.button(tr("HUD_MM_CANCEL"), cancel_queue, &"secondary", 52)
	_cancel.custom_minimum_size.x = 140
	foot.add_child(_cancel)
	_find = UiKit.button(tr("HUD_MM_FIND_MATCH"), find_match, &"play", 52)
	_find.custom_minimum_size.x = 240
	_find.add_theme_font_override("font", UiKit.display_font(700, UiKit.track(18, 0.24)))
	foot.add_child(_find)


func _lane_row(is_primary: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var g := ButtonGroup.new()
	for lane in MmView.LANES:
		if not is_primary and lane == &"fill":
			continue
		var c := MmKit.chip(tr(MmView.lane_key(lane)), g, 112)
		c.name = ("P_" if is_primary else "S_") + String(lane)
		var l := lane
		c.pressed.connect(func() -> void:
			if is_primary:
				set_lanes(l, secondary)
			else:
				set_lanes(primary, l))
		row.add_child(c)
		(_primary_chips if is_primary else _secondary_chips)[lane] = c
	return row


# --- state -----------------------------------------------------------------------

## Selects a queue row (ignored while queued).
func select_queue(id: StringName) -> void:
	if state == State.QUEUED:
		return
	queue = id
	var t := UiKit.tokens()
	for k: StringName in _queue_rows:
		var r: Dictionary = _queue_rows[k]
		(r.marker as Control).modulate.a = 1.0 if k == id else 0.0
		(r.button as Button).set_pressed_no_signal(k == id)
		(r.name as Label).add_theme_color_override("font_color", t.text if k == id else t.text_dim)
	_sync()


## Sets the lane preference; an illegal secondary is corrected.
func set_lanes(p: StringName, s: StringName) -> void:
	if state == State.QUEUED:
		_sync()
		return
	primary = p
	secondary = MmView.fix_secondary(p, s)
	_sync()


## The ranked badge info ({calibrating, games_left, rating, medal}).
func set_ranked(info: Dictionary) -> void:
	if _ranked_meta != null:
		var n := rules.calibration_games if rules != null else 10
		_ranked_meta.text = MmView.ranked_line(info, n).to_upper()


## {members: [{id, name, leader, me, rating_label}], leader}
func set_party(p: Dictionary) -> void:
	_members = p.get("members", [])
	_sync()


func find_match() -> void:
	if state != State.IDLE:
		return
	if queue == MmView.Q_CUSTOM:
		custom_requested.emit()
		return
	if not _is_leader():
		return
	if client != null:
		client.call("join_queue", queue, [] if queue == MmView.Q_ARAM else MmView.lane_prefs(primary, secondary))


func cancel_queue() -> void:
	if client != null and state == State.QUEUED:
		client.call("leave_queue")


## A QUEUE_STATUS from the client.
func on_queue_changed(st: Dictionary) -> void:
	match StringName(st.get("state", &"idle")):
		&"queued":
			state = State.QUEUED
			queue = StringName(st.get("queue", queue))
			waited = float(st.get("waited_s", 0.0))
			estimate = float(st.get("estimate_s", 0.0))
			in_queue = int(st.get("in_queue", 0))
		&"locked":
			state = State.LOCKED
			locked_left = float(st.get("locked_s", 0.0))
		_:
			state = State.IDLE
	_sync()


## Local countdowns between status messages.
func tick(delta: float) -> void:
	if state == State.QUEUED:
		waited += delta
		_sync_timer()
	elif state == State.LOCKED:
		locked_left = maxf(0.0, locked_left - delta)
		if locked_left <= 0.0:
			state = State.IDLE
			_sync()
		else:
			_sync_timer()


func _process(delta: float) -> void:
	tick(delta)


func _is_leader() -> bool:
	for m: Dictionary in _members:
		if bool(m.get("me", false)):
			return bool(m.get("leader", true))
	return true


func _sync() -> void:
	if _find == null:
		return
	var t := UiKit.tokens()
	var queued := state == State.QUEUED
	var locked := state == State.LOCKED
	var lanes_on := queue in [MmView.Q_NORMAL, MmView.Q_RANKED]
	_lane_box.modulate.a = 1.0 if lanes_on else 0.35
	for lane: StringName in _primary_chips:
		var c := _primary_chips[lane] as Button
		c.set_pressed_no_signal(lane == primary)
		c.disabled = not lanes_on
	for lane: StringName in _secondary_chips:
		var c := _secondary_chips[lane] as Button
		c.set_pressed_no_signal(lane == secondary and primary != &"fill")
		c.disabled = not lanes_on or primary == &"fill" or lane == primary
	for k: StringName in _queue_rows:
		(_queue_rows[k].button as Button).disabled = queued and k != queue
	_queue_box.visible = queued
	_cancel.visible = queued
	_find.visible = not queued
	_find.disabled = locked or not _is_leader()
	_find.text = tr("HUD_MM_CREATE_LOBBY") if queue == MmView.Q_CUSTOM else tr("HUD_MM_FIND_MATCH")
	_lock_banner.visible = locked
	# Party seats.
	for c in _party_rows.get_children():
		_party_rows.remove_child(c)
		c.queue_free()
	var cap := rules.party_max if rules != null else 5
	for i in cap:
		_party_rows.add_child(_party_row(_members[i] if i < _members.size() else {}))
	_party_count.text = tr("HUD_MM_PARTY_COUNT") % [_members.size(), cap]
	var lines: Array[String] = [tr("HUD_MM_PARTY_RULE_SIZE") % cap]
	if queue == MmView.Q_RANKED:
		lines.append(tr("HUD_MM_PARTY_RULE_RANKED") % int(rules.ranked_party_gap_max if rules != null else 500.0))
		lines.append(tr("HUD_MM_RANKED_NO_BOTS"))
	elif queue != MmView.Q_CUSTOM:
		lines.append(tr("HUD_MM_BOT_FILL_NOTE") % int(rules.bot_fill_delay_s if rules != null else 75.0))
	if not _is_leader():
		lines.append(tr("HUD_MM_LEADER_ONLY"))
	_party_rules.text = "\n".join(lines)
	if _chat != null:
		_chat.visible = _members.size() > 1  # P2: in a party the chat takes the rules' place
		_party_rules.visible = not _chat.visible
	_party_rules.add_theme_color_override("font_color", t.text_dim)
	_sync_timer()


func _sync_timer() -> void:
	if _elapsed == null:
		return
	_elapsed.text = MmView.clock(waited)
	_wait_line.text = tr("HUD_MM_QUEUE_LINE") % [tr(MmView.queue_key(queue)), MmView.clock(estimate), in_queue]
	if state == State.LOCKED:
		MmKit.set_banner_text(_lock_banner, tr("HUD_MM_LOCKOUT_BANNER") % MmView.clock(locked_left))


func _party_row(m: Dictionary) -> Control:
	var t := UiKit.tokens()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size.y = 34
	var well := UiPortrait.create(null, 30.0, t.accent if bool(m.get("leader", false)) else t.line_strong)
	well.ring_width = 1.0
	row.add_child(well)
	if m.is_empty():
		row.modulate.a = 0.45
		var l := UiKit.label(tr("HUD_MM_PARTY_OPEN"), &"small", t.text_off)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		return row
	var nm := UiKit.label(str(m.get("name", "")), &"body", t.text)
	nm.add_theme_font_override("font", UiKit.body_font(600))
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nm)
	if bool(m.get("leader", false)):
		var lead := MmKit.caption(tr("HUD_MM_PARTY_LEADER"), 10, t.accent)
		lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lead)
	if bool(m.get("ready", false)):
		var rd := MmKit.caption(tr("HUD_SOCIAL_READY"), 10, t.cyan)  # P2: ready flag (text, not colour alone)
		rd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(rd)
	var rl := UiKit.label(str(m.get("rating_label", "")) if queue == MmView.Q_RANKED else "", &"small", t.text_dim,
		HORIZONTAL_ALIGNMENT_RIGHT)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rl)
	# P2: party controls (only with a client that has them, only in a party).
	if client != null and client.has_method("party_promote") and _members.size() > 1:
		var id := str(m.get("id", ""))
		if bool(m.get("me", false)):
			var on := not bool(m.get("ready", false))
			row.add_child(UiKit.button(tr("HUD_SOCIAL_READY_SET") if on else tr("HUD_SOCIAL_READY_CLEAR"),
				func() -> void: client.call("party_ready", on), &"ghost", 28))
			row.add_child(UiKit.button(tr("HUD_SOCIAL_LEAVE"), func() -> void: client.call("party_leave"), &"ghost", 28))
		elif _is_leader():
			row.add_child(UiKit.button(tr("HUD_SOCIAL_PROMOTE"), func() -> void: client.call("party_promote", id),
				&"ghost", 28))
			row.add_child(UiKit.button(tr("HUD_SOCIAL_KICK"), func() -> void: client.call("party_kick", id),
				&"ghost", 28))
	return row
