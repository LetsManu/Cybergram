class_name MatchEndScreen
extends CanvasLayer
## Post-match screen (W10-W4, League / Dota style): winner banner, per-team
## table (hero, name, K/D/A, hero damage, healing, objective damage, Lumen,
## level), the MVP mark (MvpFormulaDef) and Back to lobby / Main menu buttons.
## Overlay (AppConfig.overlay_scenes, receives `session`). Waits for the
## server's final stats (ClientWorld.match_summary_received), shows them
## SHOW_DELAY_S after the match end so the end banner is seen first.

const SHOW_DELAY_S := 2.5
const COLUMN_KEYS: Array[String] = ["HUD_END_COL_HERO", "HUD_END_COL_NAME", "HUD_END_COL_KDA",
	"HUD_END_COL_DAMAGE", "HUD_END_COL_HEALING", "HUD_END_COL_OBJECTIVE", "HUD_END_COL_LUMEN", "HUD_END_COL_LEVEL"]

var session: Node
var _root: Control
var _client: ClientWorld
var _pending: bool = false
var _wait: float = 0.0
var _focus: Button
var _player: PlayerInputSource


func _ready() -> void:
	HudStrings.ensure_loaded()
	layer = 55


func _process(delta: float) -> void:
	if _client == null:
		_client = session.get("client") as ClientWorld if session != null else null
		if _client != null:
			_client.match_summary_received.connect(func(_rows: Dictionary) -> void:
				_pending = true
				_wait = SHOW_DELAY_S)
		return
	if _pending:
		_wait -= delta
		if _wait <= 0.0:
			_pending = false
			show_summary(_client.match_summary, _client.match_state.winner if _client.match_state != null else -1)


func is_open() -> bool:
	return _root != null and _root.visible


## Builds and shows the screen for `summary` (net id -> {Stat -> float}).
func show_summary(summary: Dictionary, winner: int) -> void:
	if _root != null:
		_root.queue_free()
	var formula := load(MatchEndModel.FORMULA_PATH) as MvpFormulaDef
	var own_id := _client.session.own_net_id if _client != null and _client.session != null else 0
	var names: Dictionary = {}
	if _client != null and _client.session != null:
		for id: int in _client.session.player_names:
			names[id] = str(_client.session.player_names[id].name)
	var model := MatchEndModel.build(summary, winner, own_id, names, formula, MatchEndModel.hero_display_name)
	var own_team := _client.own_team() if _client != null else 0
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.05, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	var title := tr("HUD_DRAW")
	var col := HudPalette.TEXT
	if winner >= 0 and winner <= 1:
		title = tr("HUD_VICTORY") if winner == own_team else tr("HUD_DEFEAT")
		col = HudPalette.team_color(winner).lightened(0.3)
	box.add_child(MenuStyle.label(title, 64, col, HORIZONTAL_ALIGNMENT_CENTER))
	if winner >= 0 and winner <= 1:
		box.add_child(MenuStyle.label(tr("HUD_END_WINNER") % tr(MatchHeader.TEAM_KEYS[winner]), 20,
			HudPalette.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var order: Array[int] = [own_team, 1 - own_team]
	for t in order:
		box.add_child(_team_table(t, model.teams[t], t == winner))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	box.add_child(MenuStyle.spacer(6))
	box.add_child(buttons)
	var online: bool = session != null and session.get("remote") != null
	if online:
		_focus = MenuStyle.button(tr("HUD_END_BACK_LOBBY"), _back_to_lobby, true)
		buttons.add_child(_focus)
	var menu_btn := MenuStyle.button(tr("HUD_END_MAIN_MENU"), _to_menu, not online)
	buttons.add_child(menu_btn)
	if _focus == null:
		_focus = menu_btn
	_player = _client.player_input if _client != null else null
	if _player != null:
		_player.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_focus.grab_focus()


func _team_table(team: int, rows: Array, won: bool) -> Control:
	var pc := MenuStyle.panel_container(Color(HudPalette.team_color(team), 0.22), 8)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var head := tr(MatchHeader.TEAM_KEYS[team]) + ("  -  " + tr("HUD_VICTORY") if won else "")
	v.add_child(MenuStyle.label(head, 18, HudPalette.team_color(team).lightened(0.3)))
	var g := GridContainer.new()
	g.columns = COLUMN_KEYS.size()
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 3)
	v.add_child(g)
	for k in COLUMN_KEYS:
		g.add_child(MenuStyle.label(tr(k), 13, HudPalette.TEXT_DIM))
	for r: MatchEndModel.Row in rows:
		var c := HudPalette.TEXT if not r.is_self else HudPalette.team_color(team).lightened(0.5)
		var cells: Array[String] = [r.hero, r.name + ("  " + tr("HUD_END_MVP") if r.is_mvp else ""),
			"%d / %d / %d" % [r.kills, r.deaths, r.assists], str(r.hero_damage), str(r.healing),
			str(r.objective_damage), str(r.lumen), str(r.level)]
		for i in cells.size():
			var l := MenuStyle.label(cells[i], 15, Color(1.0, 0.85, 0.3) if r.is_mvp and i == 1 else c)
			g.add_child(l)
	return pc


func _back_to_lobby() -> void:
	var remote: Variant = session.get("remote") if session != null else null
	if remote == null:
		_to_menu()
		return
	var lc: Variant = session.get("launch_config")
	remote.close()
	_release()
	AppRoot.rejoin_lobby(get_tree(), "%s:%d" % [lc.connect_address, lc.port])


func _to_menu() -> void:
	var remote: Variant = session.get("remote") if session != null else null
	if remote != null:
		remote.close()
	_release()
	AppRoot.back_to_menu(get_tree(), "")


func _release() -> void:
	if _player != null:
		_player.paused = false
