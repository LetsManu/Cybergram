class_name LobbyScreen
extends VBoxContainer
## Online lobby view (LoL-style queue + hero select on one server). Shows the
## two teams, lets the player pick a hero and press Ready; when the server
## starts the match it emits start_requested with the --connect/--token args.

signal start_requested(args: PackedStringArray)
signal cancelled(reason: String)

const CONNECT_TIMEOUT_S := 8.0
const HEROES := MainMenu.HEROES

var address: String = ""
var hero_id: String = "vesper_loom"

var _enet: ENetTransport
var _lobby: LobbyClient
var _host: String = ""
var _port: int = ENetTransport.DEFAULT_PORT
var _waited: float = 0.0
var _status: Label
var _teams: Array[VBoxContainer] = []
var _hero: OptionButton
var _ready_btn: Button


func _ready() -> void:
	HudStrings.ensure_loaded()
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(560, 0)
	var title := Label.new()
	title.text = tr("HUD_LOBBY_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", HudPalette.TEXT)
	add_child(title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", HudPalette.LUMEN)
	_status.text = tr("HUD_MENU_CONNECTING") % address
	add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	for t in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := Label.new()
		head.text = tr("HUD_TEAM_%d" % t)
		head.add_theme_color_override("font_color", HudPalette.TEAM_COLORS[0][t])
		col.add_child(head)
		row.add_child(col)
		_teams.append(col)
	_hero = OptionButton.new()
	for h in HEROES:
		_hero.add_item(tr(h[1]))
	for i in HEROES.size():
		if HEROES[i][0] == hero_id:
			_hero.selected = i
	_hero.custom_minimum_size.y = 40
	_hero.item_selected.connect(func(_i: int) -> void: _send_pick())
	add_child(_hero)
	_ready_btn = Button.new()
	_ready_btn.toggle_mode = true
	_ready_btn.text = tr("HUD_LOBBY_READY")
	_ready_btn.custom_minimum_size.y = 52
	_ready_btn.toggled.connect(func(_on: bool) -> void: _send_pick())
	add_child(_ready_btn)
	var leave := Button.new()
	leave.text = tr("HUD_LOBBY_LEAVE")
	leave.custom_minimum_size.y = 40
	leave.pressed.connect(func() -> void: _cancel(""))
	add_child(leave)
	var hp := address.rsplit(":", true, 1)
	_host = hp[0]
	if hp.size() == 2 and hp[1].is_valid_int():
		_port = clampi(hp[1].to_int(), 1, 65535)
	_enet = ENetTransport.connect_to(_host, _port)
	if _enet.error_text != "":
		_cancel.call_deferred(_enet.error_text)
		return
	_lobby = LobbyClient.new(_enet, _hero_index(_selected_id()))
	_lobby.state_changed.connect(_on_state)
	_lobby.match_starting.connect(_on_start)
	_lobby.failed.connect(_cancel)
	_ready_btn.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if _lobby == null:
		return
	_lobby.step()
	if _enet.error_text != "":
		_cancel(_enet.error_text)
		return
	if _lobby.state.is_empty():
		_waited += delta
		if _waited > CONNECT_TIMEOUT_S:
			_cancel(tr("HUD_LOBBY_NO_ANSWER") % address)


func _on_state(s: Dictionary) -> void:
	for t in 2:
		while _teams[t].get_child_count() > 1:
			var c := _teams[t].get_child(1)
			_teams[t].remove_child(c)
			c.queue_free()
	var slots: Array = s.slots
	for i in slots.size():
		var sl: Dictionary = slots[i]
		var l := Label.new()
		var name := tr("HUD_LOBBY_YOU") if i == s.you else tr("HUD_LOBBY_PLAYER") % (i + 1)
		l.text = "%s  ·  %s  %s" % [name, _hero_name(sl.hero_index), "✔" if sl.ready else ""]
		l.add_theme_color_override("font_color", HudPalette.TEXT if sl.ready else HudPalette.TEXT_DIM)
		_teams[clampi(sl.team, 0, 1)].add_child(l)
	if s.phase == LobbyCodec.PHASE_COUNTDOWN:
		_status.text = tr("HUD_LOBBY_STARTING") % s.countdown
	else:
		_status.text = tr("HUD_LOBBY_WAITING")


func _on_start(token: int, _team: int, hero_index: int) -> void:
	var id := _hero_id_of(hero_index)
	_enet.close()
	_lobby = null
	start_requested.emit(PackedStringArray(["--connect", "%s:%d" % [_host, _port], "--hero", id,
		"--token", str(token)]))


func _send_pick() -> void:
	if _lobby != null:
		_lobby.pick(_hero_index(_selected_id()), _ready_btn.button_pressed)


func _cancel(reason: String) -> void:
	if _enet != null:
		_enet.close()
	_lobby = null
	cancelled.emit(reason)


func _selected_id() -> String:
	return HEROES[maxi(_hero.selected, 0)][0]


static func _hero_index(id: String) -> int:
	return ContentDB.shared().index_of(ContentDB.HERO, StringName("hero_" + id))


static func _hero_id_of(index: int) -> String:
	var id := String(ContentDB.shared().id_at(ContentDB.HERO, index))
	return id.trim_prefix("hero_") if id != "" else "vesper_loom"


func _hero_name(index: int) -> String:
	var id := _hero_id_of(index)
	for h in HEROES:
		if h[0] == id:
			return tr(h[1])
	return id
