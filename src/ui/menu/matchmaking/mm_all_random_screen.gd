class_name MmAllRandomScreen
extends Control
## W17B-UI: the 3v3 All Random hero phase (design "3v3 All Random", ARAM
## style), on the lobby look: your dealt hero big in the centre with REROLL
## (rerolls left), the team's shared reroll bench under it (click a hero to
## take it; yours goes onto the bench), your teammates on the left with a
## SWAP link each, incoming swap requests as cards with ACCEPT / DECLINE,
## the enemy team on the right (heroes shown, as in ARAM), and the phase
## countdown. Display only: client.reroll / take_bench / request_swap /
## answer_swap.

var client: Object
var with_model: bool = DisplayServer.get_name() != "headless"
var state: Dictionary = {}
var left_s: float = 0.0

var _timer: Label
var _bar: ProgressBar
var _title: Label
var _stage: HeroShowcase
var _hero_name: Label
var _hero_role: Label
var _reroll: Button
var _bench_row: HBoxContainer
var _bench_empty: Label
var _cols: Array[VBoxContainer] = []
var _requests: VBoxContainer


func _ready() -> void:
	HudStrings.ensure_loaded()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	_build()
	_apply()
	_reroll.grab_focus.call_deferred()


## A PICK_STATE (mode all_random).
func set_state(s: Dictionary) -> void:
	state = s
	left_s = float(s.get("deadline_s", 0.0))
	_apply()


func me() -> String:
	return str(state.get("me", "me"))


func my_hero() -> StringName:
	return StringName(MmView.seat(state.get("seats", []), me()).get("hero", &""))


func reroll() -> void:
	if MmView.can_reroll(state) and client != null:
		client.call("reroll")


func take(hero: StringName) -> void:
	if MmView.can_take_bench(state, hero) and client != null:
		client.call("take_bench", hero)


func ask_swap(seat_id: String) -> void:
	if bool(state.get("open", true)) and client != null and not (state.get("outgoing", []) as Array).has(seat_id):
		client.call("request_swap", seat_id)


func answer(from: String, accept: bool) -> void:
	if client != null:
		client.call("answer_swap", from, accept)


func tick(delta: float) -> void:
	left_s = maxf(0.0, left_s - delta)
	if _timer != null:
		_timer.text = MmView.clock(left_s)
		_bar.value = clampf(left_s / maxf(float(state.get("turn_s", 45.0)), 1.0), 0.0, 1.0)


func _process(delta: float) -> void:
	tick(delta)


func _build() -> void:
	var t := UiKit.tokens()
	var bg := UiKit.background()
	UiKit.set_background_layout(bg, 720.0, Vector2(720, 360), 300.0, false)
	add_child(bg)
	_stage = HeroShowcase.new()
	_stage.heroes = HeroCatalog.entries()
	_stage.chrome = false
	_stage.with_model = with_model
	_stage.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_stage.offset_left = -180
	_stage.offset_right = 180
	_stage.offset_top = 110
	_stage.offset_bottom = 540
	_stage.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_stage)
	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_CENTER_TOP)
	centre.offset_left = -400
	centre.offset_right = 400
	centre.offset_top = 18
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_title = MmKit.title(tr("HUD_MM_ARAM_TITLE"), 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(_title)
	var sub := UiKit.label(tr("HUD_MM_ARAM_SUB"), &"small", t.text_dim, HORIZONTAL_ALIGNMENT_CENTER)
	centre.add_child(sub)
	_timer = MmKit.mono("", 26)
	_timer.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer.offset_left = -200
	_timer.offset_right = -40
	_timer.offset_top = 22
	_timer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_timer)
	_bar = MmKit.progress(t.accent, 2)
	_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_left = 40
	_bar.offset_right = -40
	_bar.offset_top = 92
	_bar.offset_bottom = 94
	add_child(_bar)
	var tag := MmKit.caption(tr("HUD_MM_FUN_TAG"), 11, t.cyan)
	add_child(MmKit.place(tag, Vector2(44, 30)))
	for col in 2:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		if col == 0:
			box.position = Vector2(40, 124)
			box.size.x = 330
			box.custom_minimum_size.x = 330
		else:
			box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			box.offset_left = -360
			box.offset_right = -40
			box.offset_top = 124
			box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		add_child(box)
		var head := MmKit.caption(tr("HUD_MM_YOUR_TEAM") if col == 0 else tr("HUD_MM_ENEMY_TEAM"), 11,
			t.accent if col == 0 else t.danger)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if col == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(head)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 8)
		box.add_child(rows)
		_cols.append(rows)
	_requests = VBoxContainer.new()
	_requests.add_theme_constant_override("separation", 8)
	add_child(MmKit.place(_requests, Vector2(40, 480), 330))
	var info := VBoxContainer.new()
	info.set_anchors_preset(Control.PRESET_CENTER_TOP)
	info.offset_left = -300
	info.offset_right = 300
	info.offset_top = 540
	info.grow_horizontal = Control.GROW_DIRECTION_BOTH
	info.add_theme_constant_override("separation", 6)
	add_child(info)
	_hero_role = MmKit.caption("", 12, t.accent)
	_hero_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_hero_role)
	_hero_name = MmKit.title("", 32)
	_hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_hero_name)
	var rr := HBoxContainer.new()
	rr.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_child(rr)
	_reroll = UiKit.button("", reroll, &"primary", 44)
	_reroll.name = "Reroll"
	_reroll.custom_minimum_size.x = 220
	rr.add_child(_reroll)
	var bench := VBoxContainer.new()
	bench.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bench.offset_left = -300
	bench.offset_right = 300
	bench.offset_top = 676
	bench.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bench.add_theme_constant_override("separation", 8)
	add_child(bench)
	var bh := MmKit.caption(tr("HUD_MM_BENCH"), 11)
	bh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bench.add_child(bh)
	_bench_row = HBoxContainer.new()
	_bench_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_bench_row.add_theme_constant_override("separation", 12)
	_bench_row.custom_minimum_size.y = 52
	bench.add_child(_bench_row)
	_bench_empty = UiKit.label(tr("HUD_MM_BENCH_EMPTY"), &"small", t.text_off, HORIZONTAL_ALIGNMENT_CENTER)
	bench.add_child(_bench_empty)


func _apply() -> void:
	if _title == null:
		return
	var t := UiKit.tokens()
	var open := bool(state.get("open", true))
	var mine := my_hero()
	var entry := MmView.hero_entry(mine)
	if not entry.is_empty():
		for i in _stage.heroes.size():
			if _stage.heroes[i].stem == entry.stem:
				if _stage.is_inside_tree():
					_stage.select(i, false)
				else:
					_stage.selected = i
		_hero_name.text = str(entry.name).to_upper()
		_hero_role.text = tr(LobbyPhase.role_key(str(entry.stem)))
	_title.text = (tr("HUD_MM_ARAM_TITLE") if open else tr("HUD_MM_ARAM_LOCKED")).to_upper()
	var n := int(state.get("rerolls_left", 0))
	_reroll.text = tr("HUD_MM_REROLL") % n
	_reroll.disabled = not MmView.can_reroll(state)
	# Bench.
	for c in _bench_row.get_children():
		_bench_row.remove_child(c)
		c.queue_free()
	var bench: Array = state.get("bench", [])
	for h: StringName in bench:
		var b := HeroShowcase.thumb_button(MmView.hero_index(h), 52)
		b.name = "Bench_" + String(h)
		b.tooltip_text = tr("HUD_MM_BENCH_TAKE") % MmView.hero_name(h)
		b.disabled = not open
		var hid := h
		b.pressed.connect(func() -> void: take(hid))
		_bench_row.add_child(b)
	_bench_empty.visible = bench.is_empty()
	# Teams.
	for col in 2:
		for c in _cols[col].get_children():
			_cols[col].remove_child(c)
			c.queue_free()
	var my_team := int(state.get("my_team", 0))
	var outgoing: Array = state.get("outgoing", [])
	for s: Dictionary in state.get("seats", []):
		var ally := int(s.team) == my_team
		var is_me := str(s.id) == me()
		var status := tr("HUD_MM_SEAT_DEALT")
		if ally and outgoing.has(str(s.id)):
			status = tr("HUD_MM_SWAP_SENT")
		var card := MmKit.seat_card(s, is_me, not ally, status, t.accent if ally else t.danger, is_me)
		card.name = "Seat_" + str(s.id)
		_cols[0 if ally else 1].add_child(card)
		if ally and not is_me and not bool(s.get("bot", false)):
			var sw := UiKit.button(tr("HUD_MM_SWAP"), Callable(), &"ghost", 30)
			sw.name = "Swap_" + str(s.id)
			var sid := str(s.id)
			sw.pressed.connect(func() -> void: ask_swap(sid))
			sw.disabled = not open or outgoing.has(sid)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			(card.get_child(0) as HBoxContainer).add_child(sw)
	# Swap requests.
	for c in _requests.get_children():
		_requests.remove_child(c)
		c.queue_free()
	for r: Dictionary in state.get("swap_requests", []):
		_requests.add_child(_request_card(r, open))
	tick(0.0)


func _request_card(r: Dictionary, open: bool) -> Control:
	var t := UiKit.tokens()
	var p := MmKit.frame(12, Color(t.panel_raised, 0.95), t.cyan)
	p.name = "Request_" + str(r.from)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	p.add_child(col)
	var l := UiKit.label(tr("HUD_MM_SWAP_ASK") % [str(r.name), MmView.hero_name(StringName(r.get("hero", &"")))],
		&"small", t.text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var from := str(r.from)
	var no := UiKit.button(tr("HUD_MM_DECLINE"), func() -> void: answer(from, false), &"ghost", 32)
	no.disabled = not open
	row.add_child(no)
	var yes := UiKit.button(tr("HUD_MM_ACCEPT"), func() -> void: answer(from, true), &"primary", 32)
	yes.name = "AcceptSwap"
	yes.disabled = not open
	row.add_child(yes)
	return p
