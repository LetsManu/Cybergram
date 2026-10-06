class_name MmDraftScreen
extends Control
## W17B-UI: the 5v5 draft (design "Picking (5v5)"), built on the lobby's
## champ-select look (LobbyScreen): header with phase title, countdown and
## draining bar; your team left, the enemy right; the selected hero's stage
## in the centre; the portrait row; LOCK IN bottom right.
## - Turn track: the 1-2-2-2-2-1 order as segments (brass = yours, red =
##   enemy), the current turn lit; the seats picking now are highlighted.
## - Team-unique: heroes your team holds are greyed in the row and cannot be
##   locked; the enemy may hold the same hero.
## - Enemy picks appear on their cards as they lock in. Lanes are shown for
##   your team (the enemy's assignment is not revealed).
## - On timeout the server picks a random legal hero ("AUTO" on the card).
## - Leaving = dodge: a warning strip says so (lockout; rating in ranked) and
##   LEAVE asks to confirm.
## P3: selecting a hero declares it (hover, allies see it; an ally's hover is
## greyed for you); the ban stage bans instead of picks; blind pick (Normal)
## hides enemy picks until everyone locked; after the last lock teammates may
## offer / accept hero trades until the final countdown.
## Display only: `client.pick(hero)` / `client.hover(hero)` / `client.dodge()` /
## `client.offer_trade(seat)` / `client.accept_trade(seat)`.

signal left()

var client: Object
var rules: MatchmakingRulesDef
## Render the 3D hero stage (tests / headless turn it off).
var with_model: bool = DisplayServer.get_name() != "headless"
var state: Dictionary = {}
var left_s: float = 0.0
## The hero shown in the centre (preview / to lock).
var selected: StringName = &""

var _title: Label
var _sub: Label
var _timer: Label
var _bar: ProgressBar
var _turns: HBoxContainer
var _cols: Array[VBoxContainer] = []
var _thumbs: Dictionary = {}  # hero id -> Button
var _stage: HeroShowcase
var _hero_name: Label
var _hero_role: Label
var _lock: Button
var _dodge: PanelContainer
var _heroes: Array[StringName] = []
var _bans: Label
var _trade_box: VBoxContainer
var _hover_sent: StringName = &""


func _ready() -> void:
	HudStrings.ensure_loaded()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	if rules == null:
		rules = MatchmakingRulesDef.load_default()
	_heroes = MmView.all_heroes()
	if selected == &"" and not _heroes.is_empty():
		selected = _heroes[0]
	_build()
	_apply()
	if _thumbs.has(selected):
		(_thumbs[selected] as Button).grab_focus.call_deferred()  # P4: arrows + Accept from the start


## A PICK_STATE (mode draft) from the client.
func set_state(s: Dictionary) -> void:
	state = s
	left_s = float(s.get("deadline_s", 0.0))
	if is_my_turn() and not can_lock(selected):
		for h in _heroes:
			if can_lock(h):
				selected = h
				break
	_apply()


func me() -> String:
	return str(state.get("me", "me"))


func my_seat() -> Dictionary:
	return MmView.seat(state.get("seats", []), me())


func is_my_turn() -> bool:
	var s := my_seat()
	return bool(s.get("picking", false)) and StringName(s.get("hero", &"")) == &""


## True when `hero` may be locked now (MmView.can_pick).
func can_lock(hero: StringName) -> bool:
	return MmView.can_pick(state, me(), hero)


## True when `hero` is greyed (held by my team).
func is_greyed(hero: StringName) -> bool:
	if (state.get("bans", []) as Array).has(hero):
		return true
	if state.get("stage", &"pick") == &"ban":
		return false
	return MmView.team_taken(state.get("seats", []), int(state.get("my_team", 0)), me()).has(hero)


func preview(hero: StringName) -> void:
	selected = hero
	_send_hover(hero)
	_apply()


## P3: declare the selected hero while my pick (or ban) is open.
func _send_hover(hero: StringName) -> void:
	var s := my_seat()
	if s.is_empty() or StringName(s.get("hero", &"")) != &"" or bool(s.get("ban_locked", false)):
		return
	if is_greyed(hero) or hero == _hover_sent or client == null or not client.has_method("hover"):
		return
	_hover_sent = hero
	client.call("hover", hero)


func lock_in() -> void:
	if not can_lock(selected):
		return
	if client != null:
		client.call("pick", selected)


## LEAVE: confirm, then dodge.
func leave() -> void:
	var ranked := bool(state.get("ranked", false))
	UiKit.modal(self, tr("HUD_MM_DODGE_TITLE"), tr("HUD_MM_DODGE_BODY_RANKED") if ranked else tr("HUD_MM_DODGE_BODY"),
		tr("HUD_MM_DODGE_CONFIRM"), func() -> void:
			if client != null:
				client.call("dodge")
			left.emit(), tr("HUD_MM_STAY"), func() -> void: _lock.grab_focus(), true)


## P4: Esc / controller Back = leave (asks first: leaving is a dodge).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		leave()


func tick(delta: float) -> void:
	left_s = maxf(0.0, left_s - delta)
	_sync_timer()


func _process(delta: float) -> void:
	tick(delta)


func _build() -> void:
	var t := UiKit.tokens()
	var bg := UiKit.background()
	UiKit.set_background_layout(bg, 720.0, Vector2(720, 390), 300.0, false)
	add_child(bg)
	_stage = HeroShowcase.new()
	_stage.heroes = HeroCatalog.entries()
	_stage.chrome = false
	_stage.with_model = with_model
	_stage.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_stage.offset_left = -190
	_stage.offset_right = 190
	_stage.offset_top = 120
	_stage.offset_bottom = 600
	_stage.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_stage)
	add_child(MmKit.place(MmKit.back_link(tr("HUD_LOBBY_LEAVE"), leave), Vector2(40, 22)))
	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_CENTER_TOP)
	centre.offset_left = -400
	centre.offset_right = 400
	centre.offset_top = 18
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.add_theme_constant_override("separation", 4)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_title = MmKit.title("", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(_title)
	_sub = UiKit.label("", &"small", t.text_dim, HORIZONTAL_ALIGNMENT_CENTER)
	centre.add_child(_sub)
	_bans = UiKit.label("", &"small", t.danger, HORIZONTAL_ALIGNMENT_CENTER)
	centre.add_child(_bans)
	_turns = HBoxContainer.new()
	_turns.alignment = BoxContainer.ALIGNMENT_CENTER
	_turns.add_theme_constant_override("separation", 6)
	centre.add_child(_turns)
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
	_bar.offset_top = 100
	_bar.offset_bottom = 102
	add_child(_bar)
	for col in 2:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		if col == 0:
			box.position = Vector2(40, 124)
			box.size.x = 320
			box.custom_minimum_size.x = 320
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
		if col == 0:
			_trade_box = VBoxContainer.new()  # P3: trade offers (finalize window)
			_trade_box.add_theme_constant_override("separation", 6)
			box.add_child(_trade_box)
	var info := VBoxContainer.new()
	info.set_anchors_preset(Control.PRESET_CENTER_TOP)
	info.offset_left = -300
	info.offset_right = 300
	info.offset_top = 590
	info.grow_horizontal = Control.GROW_DIRECTION_BOTH
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)
	_hero_role = MmKit.caption("", 12, t.accent)
	_hero_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_hero_role)
	_hero_name = MmKit.title("", 32)
	_hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_hero_name)
	var grid := HBoxContainer.new()
	grid.set_anchors_preset(Control.PRESET_CENTER_TOP)
	grid.offset_left = -340
	grid.offset_right = 340
	grid.offset_top = 680
	grid.offset_bottom = 736
	grid.grow_horizontal = Control.GROW_DIRECTION_BOTH
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("separation", 14)
	add_child(grid)
	for h in _heroes:
		var b := HeroShowcase.thumb_button(MmView.hero_index(h), 56)
		b.name = "Hero_" + String(h)
		b.tooltip_text = MmView.hero_name(h)
		var hid := h
		b.pressed.connect(func() -> void:
			# P4: keyboard / controller: Accept on the hero already shown locks it in
			# (a mouse click only selects; double-click locks, below).
			if hid == selected and Input.is_action_pressed(&"ui_accept"):
				lock_in()
			else:
				preview(hid))
		b.focus_entered.connect(func() -> void: preview(hid))
		b.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).double_click:
				lock_in())
		grid.add_child(b)
		_thumbs[h] = b
	_lock = UiKit.button(tr("HUD_LOBBY_LOCK_IN"), lock_in, &"play", 52)
	_lock.name = "LockIn"
	_lock.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_lock.offset_left = -360
	_lock.offset_right = -40
	_lock.offset_top = -86
	_lock.offset_bottom = -34
	_lock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_lock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_lock.add_theme_font_override("font", UiKit.display_font(700, UiKit.track(18, 0.24)))
	add_child(_lock)
	_dodge = MmKit.banner("", &"warn")
	_dodge.position = Vector2(40, 700)
	_dodge.custom_minimum_size.x = 400
	_dodge.size.x = 400
	add_child(_dodge)


func _apply() -> void:
	if _title == null:
		return
	var t := UiKit.tokens()
	var order: PackedInt32Array = state.get("order", PackedInt32Array([1, 2, 2, 2, 2, 1]))
	var seats: Array = state.get("seats", [])
	var my_team := int(state.get("my_team", 0))
	var turn_team := int(state.get("turn_team", 0))
	var done := bool(state.get("done", false))
	var stage: StringName = state.get("stage", &"pick")
	var blind := bool(state.get("blind", false))
	if stage == &"ban":
		_title.text = tr("HUD_MM_BAN_TITLE").to_upper()
	elif done:
		_title.text = tr("HUD_MM_DRAFT_DONE").to_upper()
	elif blind:
		_title.text = tr("HUD_MM_BLIND_TITLE").to_upper()
	elif is_my_turn():
		_title.text = tr("HUD_MM_DRAFT_YOUR_TURN").to_upper()
	elif turn_team == my_team:
		_title.text = tr("HUD_MM_DRAFT_ALLY_TURN").to_upper()
	else:
		_title.text = tr("HUD_MM_DRAFT_ENEMY_TURN").to_upper()
	_title.add_theme_color_override("font_color", t.accent_hi if is_my_turn() else t.text)
	_sub.text = tr(MmView.queue_key(StringName(state.get("queue", MmView.Q_NORMAL)))) + "  ·  " + tr(
		"HUD_MM_BLIND_SUB" if blind else "HUD_MM_DRAFT_SUB")
	if done and float(state.get("trade_s", 0.0)) > 0.0:
		_sub.text = tr("HUD_MM_TRADES_OPEN")
	var bans: Array = state.get("bans", [])
	_bans.text = tr("HUD_MM_BANS") % ", ".join(bans.map(func(h: StringName) -> String: return MmView.hero_name(h))) \
		if not bans.is_empty() else ""
	# Turn track (none in blind pick: one shared turn).
	for c in _turns.get_children():
		_turns.remove_child(c)
		c.queue_free()
	if blind:
		order = PackedInt32Array()
	var plan := MmView.turn_plan(order, int(state.get("first_team", 0)))
	for i in plan.size():
		var seg := ColorRect.new()
		var p: Dictionary = plan[i]
		seg.custom_minimum_size = Vector2(18 * int(p.picks) + 6 * (int(p.picks) - 1), 5)
		var col: Color = t.accent if int(p.team) == my_team else t.danger
		var cur := int(state.get("turn", -1))
		seg.color = col if i == cur and not done else Color(col, 0.55 if i < cur or done else 0.18)
		_turns.add_child(seg)
	# Seat cards.
	for col in 2:
		for c in _cols[col].get_children():
			_cols[col].remove_child(c)
			c.queue_free()
	for s: Dictionary in seats:
		var mine := int(s.team) == my_team
		var shown := s.duplicate()
		if not mine:
			shown.lane = &""
		var picked := StringName(s.get("hero", &"")) != &""
		var status := tr("HUD_MM_SEAT_WAITING")
		var scol := t.text_off
		if picked:
			status = tr("HUD_MM_SEAT_AUTO") if bool(s.get("auto", false)) else tr("HUD_LOBBY_STATE_LOCKED")
			scol = t.accent if mine else t.danger
		elif StringName(s.get("ban", &"")) != &"":
			status = tr("HUD_MM_SEAT_BAN") % MmView.hero_name(StringName(s.ban))
			scol = t.danger
		elif StringName(s.get("hover", &"")) != &"":
			status = tr("HUD_MM_SEAT_HOVER") % MmView.hero_name(StringName(s.hover))
			scol = t.cyan
		elif bool(s.get("picking", false)):
			status = tr("HUD_LOBBY_STATE_PICKING")
			scol = t.cyan
		var card := MmKit.seat_card(shown, str(s.id) == me(), not mine, status, scol,
			bool(s.get("picking", false)) and not picked)
		card.name = "Seat_" + str(s.id)
		_cols[0 if mine else 1].add_child(card)
	# Hero row.
	for h: StringName in _thumbs:
		var b := _thumbs[h] as Button
		HeroShowcase.set_thumb_unavailable(b, is_greyed(h))
		b.set_pressed_no_signal(h == selected)
		b.queue_redraw()
	var entry := MmView.hero_entry(selected)
	if not entry.is_empty():
		var pos := 0
		for i in _stage.heroes.size():
			if _stage.heroes[i].stem == entry.stem:
				pos = i
		if _stage.is_inside_tree():
			_stage.select(pos, false)
		else:
			_stage.selected = pos
		_hero_name.text = str(entry.name).to_upper()
		_hero_role.text = tr(LobbyPhase.role_key(str(entry.stem)))
	_apply_trades(seats, my_team, done)
	var mine_hero := StringName(my_seat().get("hero", &""))
	_lock.disabled = not can_lock(selected)
	if stage == &"ban":
		_lock.text = tr("HUD_MM_BAN_LOCK") if not bool(my_seat().get("ban_locked", false)) else tr("HUD_MM_BAN_DONE")
	elif mine_hero != &"":
		_lock.text = tr("HUD_MM_LOCKED_AS") % MmView.hero_name(mine_hero)
	elif is_greyed(selected):
		_lock.text = tr("HUD_MM_TAKEN_BY_TEAM")
	else:
		_lock.text = tr("HUD_LOBBY_LOCK_IN")
	MmKit.set_banner_text(_dodge, tr("HUD_MM_DODGE_WARN_RANKED") % int(rules.dodge_rating_penalty) if bool(state.get("ranked", false))
		else tr("HUD_MM_DODGE_WARN"))
	_sync_timer()


## P3: finalize window: offer trades to locked teammates, accept offers.
func _apply_trades(seats: Array, my_team: int, done: bool) -> void:
	for c in _trade_box.get_children():
		_trade_box.remove_child(c)
		c.queue_free()
	if not done or float(state.get("trade_s", 0.0)) <= 0.0 or client == null:
		return
	for o: Dictionary in state.get("trades", []):
		var from := str(o.from)
		_trade_box.add_child(UiKit.button(tr("HUD_MM_TRADE_ACCEPT") % [str(o.name), MmView.hero_name(StringName(o.hero))],
			func() -> void: client.call("accept_trade", from), &"primary", 36))
	var row := HFlowContainer.new()  # compact: one wrapping row of small offers
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	_trade_box.add_child(row)
	for s: Dictionary in seats:
		if int(s.team) != my_team or str(s.id) == me() or bool(s.get("bot", false)) or StringName(s.get("hero", &"")) == &"":
			continue
		var to := str(s.id)
		var b := UiKit.button(tr("HUD_MM_TRADE_OFFER") % str(s.name), func() -> void: client.call("offer_trade", to),
			&"ghost", 28)
		b.tooltip_text = MmView.hero_name(StringName(s.hero))
		row.add_child(b)


func _sync_timer() -> void:
	if _timer == null:
		return
	_timer.text = MmView.clock(left_s)
	var total := float(state.get("turn_s", 30.0))
	if bool(state.get("done", false)):
		total = maxf(rules.finalize_s, 1.0)
	_bar.value = clampf(left_s / maxf(total, 1.0), 0.0, 1.0)
	var t := UiKit.tokens()
	_timer.add_theme_color_override("font_color", t.warn if left_s <= 5.0 and is_my_turn() else t.accent)
