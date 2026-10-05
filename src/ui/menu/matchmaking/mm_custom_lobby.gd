class_name MmCustomLobby
extends Control
## W17B-UI: the Custom game lobby (design "Custom game": any map / size,
## host's choice, no rating). The host picks the map, the pick mode, the
## team size and bot fill, invites friends one by one or the whole party,
## then START. Others see the settings read-only. Both teams list their
## members. Display only: client.custom_set / custom_invite / custom_start.

signal back_requested()

var client: Object
var lobby: Dictionary = {}
## [{id, name}] friends that can be invited (from the menu's friends panel).
var friends: Array = []

var _maps: HBoxContainer
var _modes: HBoxContainer
var _size_label: Label
var _bots: CheckButton
var _teams: Array[VBoxContainer] = []
var _invites: VBoxContainer
var _start: Button
var _host_note: Label
var _ctrls: Array[Control] = []


func _ready() -> void:
	HudStrings.ensure_loaded()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	_build()
	_apply()


func set_lobby(l: Dictionary) -> void:
	lobby = l
	_apply()


func is_host() -> bool:
	return not lobby.is_empty() and str(lobby.get("host", "")) == str(lobby.get("me", ""))


func set_config(map_id: StringName, mode: StringName, bots: bool, team_size: int) -> void:
	if is_host() and client != null:
		client.call("custom_set", map_id, mode, bots, clampi(team_size, 1, 5))


func invite(id: String) -> void:
	if is_host() and client != null:
		client.call("custom_invite", id)


func start() -> void:
	if is_host() and client != null:
		client.call("custom_start")


func _build() -> void:
	var t := UiKit.tokens()
	var bg := UiKit.background()
	UiKit.set_background_layout(bg, 1000.0, Vector2(1000, 300), 300.0, true)
	add_child(bg)
	add_child(MmKit.place(MmKit.back_link(tr("HUD_LOBBY_LEAVE"), func() -> void: back_requested.emit()), Vector2(40, 22)))
	var title := MmKit.title(tr("HUD_MM_CUSTOM_TITLE"), 28)
	add_child(MmKit.place(title, Vector2(64, 64)))
	_host_note = UiKit.label("", &"small", t.text_dim)
	add_child(MmKit.place(_host_note, Vector2(64, 104), 560))
	var cfg := VBoxContainer.new()
	cfg.add_theme_constant_override("separation", 10)
	add_child(MmKit.place(cfg, Vector2(64, 140), 560))
	cfg.add_child(MmKit.caption(tr("HUD_MM_CUSTOM_MAP")))
	_maps = HBoxContainer.new()
	_maps.add_theme_constant_override("separation", 8)
	cfg.add_child(_maps)
	cfg.add_child(MmKit.caption(tr("HUD_MM_CUSTOM_MODE")))
	_modes = HBoxContainer.new()
	_modes.add_theme_constant_override("separation", 8)
	cfg.add_child(_modes)
	cfg.add_child(MmKit.caption(tr("HUD_MM_CUSTOM_SIZE")))
	var sz := HBoxContainer.new()
	sz.add_theme_constant_override("separation", 10)
	cfg.add_child(sz)
	var minus := UiKit.button("−", func() -> void: _bump_size(-1), &"secondary", 34)
	minus.custom_minimum_size.x = 40
	sz.add_child(minus)
	_size_label = MmKit.mono("5v5", 20, t.text)
	_size_label.custom_minimum_size.x = 64
	_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sz.add_child(_size_label)
	var plus := UiKit.button("+", func() -> void: _bump_size(1), &"secondary", 34)
	plus.custom_minimum_size.x = 40
	sz.add_child(plus)
	_ctrls.append_array([minus, plus])
	_bots = CheckButton.new()
	_bots.text = tr("HUD_MM_CUSTOM_BOTS")
	_bots.toggled.connect(func(on: bool) -> void:
		set_config(StringName(lobby.get("map", &"")), StringName(lobby.get("mode", &"custom")), on, int(lobby.get("team_size", 5))))
	cfg.add_child(_bots)
	_ctrls.append(_bots)
	cfg.add_child(UiKit.hairline())
	var ih := HBoxContainer.new()
	var ic := MmKit.caption(tr("HUD_MM_CUSTOM_INVITE"))
	ic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ih.add_child(ic)
	var party := UiKit.button(tr("HUD_MM_INVITE_PARTY"), func() -> void: invite(""), &"ghost", 30)
	ih.add_child(party)
	_ctrls.append(party)
	cfg.add_child(ih)
	_invites = VBoxContainer.new()
	_invites.add_theme_constant_override("separation", 4)
	cfg.add_child(_invites)
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 32)
	add_child(MmKit.place(teams, Vector2(720, 140), 640))
	for i in 2:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.custom_minimum_size.x = 300
		v.add_child(MmKit.caption(tr("HUD_TEAM_0") if i == 0 else tr("HUD_TEAM_1"), 11,
			t.accent if i == 0 else t.danger))
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 6)
		v.add_child(rows)
		_teams.append(rows)
		teams.add_child(v)
	_start = UiKit.button(tr("HUD_MM_CUSTOM_START"), start, &"play", 52)
	_start.name = "Start"
	_start.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_start.offset_left = -320
	_start.offset_right = -60
	_start.offset_top = -100
	_start.offset_bottom = -48
	_start.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_start.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_start)


func _bump_size(d: int) -> void:
	set_config(StringName(lobby.get("map", &"")), StringName(lobby.get("mode", &"custom")), bool(lobby.get("bots", true)),
		int(lobby.get("team_size", 5)) + d)


func _apply() -> void:
	if _maps == null:
		return
	var t := UiKit.tokens()
	var host := is_host()
	_host_note.text = tr("HUD_MM_CUSTOM_HOST_NOTE") if host else tr("HUD_MM_CUSTOM_GUEST_NOTE")
	for box: HBoxContainer in [_maps, _modes]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	var mg := ButtonGroup.new()
	for m: StringName in lobby.get("maps", []):
		var c := MmKit.chip(tr("HUD_MM_MAP_SLICE") if m == &"slice" else tr("HUD_MM_MAP_SHARDLINE"), mg, 180)
		c.name = "Map_" + String(m)
		c.set_pressed_no_signal(m == StringName(lobby.get("map", &"")))
		c.disabled = not host
		var mid := m
		c.pressed.connect(func() -> void:
			set_config(mid, StringName(lobby.get("mode", &"custom")), bool(lobby.get("bots", true)), int(lobby.get("team_size", 5))))
		_maps.add_child(c)
	var og := ButtonGroup.new()
	for m: StringName in lobby.get("modes", []):
		var c := MmKit.chip(tr("HUD_MM_MODE_ALL_RANDOM") if m == &"all_random" else tr("HUD_MM_MODE_FREE_PICK"), og, 180)
		c.name = "Mode_" + String(m)
		c.set_pressed_no_signal(m == StringName(lobby.get("mode", &"")))
		c.disabled = not host
		var mid := m
		c.pressed.connect(func() -> void:
			set_config(StringName(lobby.get("map", &"")), mid, bool(lobby.get("bots", true)), int(lobby.get("team_size", 5))))
		_modes.add_child(c)
	var n := int(lobby.get("team_size", 5))
	_size_label.text = "%dv%d" % [n, n]
	_bots.set_pressed_no_signal(bool(lobby.get("bots", true)))
	for c in _ctrls:
		if c is BaseButton:
			(c as BaseButton).disabled = not host
	for i in 2:
		for c in _teams[i].get_children():
			_teams[i].remove_child(c)
			c.queue_free()
	var counts := [0, 0]
	for m: Dictionary in lobby.get("members", []):
		var team := clampi(int(m.get("team", 0)), 0, 1)
		counts[team] += 1
		var nm := str(m.get("name", ""))
		if str(m.get("id", "")) == str(lobby.get("host", "")):
			nm += "  (%s)" % tr("HUD_MM_HOST")
		var l := UiKit.label(nm, &"body", t.text)
		_teams[team].add_child(l)
	for i in 2:
		for k in range(counts[i], n):
			_teams[i].add_child(UiKit.label(tr("HUD_LOBBY_BOT_FILL") if bool(lobby.get("bots", true)) else tr("HUD_LOBBY_OPEN_SLOT"),
				&"small", t.text_off))
	for c in _invites.get_children():
		_invites.remove_child(c)
		c.queue_free()
	var invited: Array = lobby.get("invited", [])
	for f: Dictionary in friends:
		var row := HBoxContainer.new()
		var l := UiKit.label(str(f.get("name", "")), &"body", t.text)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var fid := str(f.get("id", ""))
		var b := UiKit.button(tr("HUD_MM_INVITED") if invited.has(fid) else tr("HUD_MM_INVITE"), func() -> void: invite(fid),
			&"ghost", 28)
		b.name = "Invite_" + fid
		b.disabled = not host or invited.has(fid)
		row.add_child(b)
		_invites.add_child(row)
	if friends.is_empty():
		_invites.add_child(UiKit.label(tr("HUD_MM_NO_FRIENDS_ONLINE"), &"small", t.text_off))
	_start.disabled = not host or bool(lobby.get("starting", false))
	_start.text = tr("HUD_MM_CUSTOM_STARTING") if bool(lobby.get("starting", false)) else tr("HUD_MM_CUSTOM_START")
