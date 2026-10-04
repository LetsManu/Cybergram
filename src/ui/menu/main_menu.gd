class_name MainMenu
extends CanvasLayer
## Title screen (shown when the game starts without command-line arguments).
## It only chooses launch arguments: AppRoot turns them into a LaunchConfig and
## builds the session, exactly as if they had been typed on the command line.
##   Play vs Bots     -> --hero <id>                 (slice 3v3 vs bots, offline: no login)
##   Play Online      -> log in (or guest) on the official server, then its lobby
##   Movement Course  -> --map test_course
## Online (design/ux/lobby-and-social.md §6): accounts live on the server.
## The client stores nothing but the hero pick and an optional "remember
## username" (user://menu.cfg). The session token stays in memory
## (`session_token`) so the game can resume the session after a match.
## The friends panel (docked right, LoL client) and PROFILE use the session.

## Emitted with the chosen launch arguments.
signal start_requested(args: PackedStringArray)

const SETTINGS_PATH := "user://menu.cfg"
const DEFAULT_ADDRESS := "127.0.0.1:7777"
const DEFAULT_HERO := "vesper_loom"
## Pre-accounts local files (v0.5 dev builds): imported once, then deleted.
const LEGACY_FILES: Array[String] = ["user://profile.cfg", "user://friends.cfg", "user://moderation.cfg",
	"user://my_cybergram_data.json"]

## Memory only: resumes the server session after a match (never on disk).
static var session_token: String = ""
static var session_server: String = ""
## Where the legacy profile is looked for (tests override).
static var legacy_profile_path: String = "user://profile.cfg"

## Shown under the buttons (e.g. why the last online session ended).
var notice: String = ""

var _hero: OptionButton
var _heroes: Array = []
var _status: Label
var _settings: SettingsPanel
var _center: CenterContainer
var _col: VBoxContainer
var _play: Button
var _chip: PanelContainer
var _friends: FriendsPanel
var _lobby_box: MarginContainer
var _lobby: LobbyScreen
var _login: LoginScreen
var _profile_screen: ProfileScreen
var _import_dialog: ConfirmationDialog
## The online connection (null = offline).
var _enet: ENetTransport
var _online: LobbyClient
var _server: String = ""
## Runs once the session is up (open the lobby, the profile, ...).
var _then: Callable
var _link_up: bool = false  # the server link completed its handshake
var _auto_guest_sent: bool = false


func _ready() -> void:
	HudStrings.ensure_loaded()  # shared UI string table (hud.csv)
	layer = 50
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.04, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := ColorRect.new()
	glow.color = Color(HudPalette.NEUTRAL, 0.12)
	glow.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	glow.custom_minimum_size.y = 6
	add_child(glow)
	var center := CenterContainer.new()
	_center = center
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	_col = col
	col.custom_minimum_size = Vector2(440, 0)
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)

	col.add_child(MenuStyle.label("CYBERGRAM", 64, HudPalette.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(MenuStyle.label(tr("HUD_MENU_TAGLINE") % _version(), 16, HudPalette.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(MenuStyle.spacer(18))
	col.add_child(MenuStyle.label(tr("HUD_MENU_HERO"), 14, HudPalette.TEXT_DIM))
	_hero = OptionButton.new()
	_heroes = HeroCatalog.entries()
	for h: Dictionary in _heroes:
		_hero.add_item(str(h.name))
	_hero.custom_minimum_size.y = 40
	col.add_child(_hero)
	col.add_child(MenuStyle.spacer(6))
	_play = MenuStyle.button(tr("HUD_MENU_PLAY_BOTS"), _play_bots, true)
	col.add_child(_play)
	col.add_child(MenuStyle.spacer(6))
	col.add_child(MenuStyle.button(tr("HUD_MENU_PLAY_ONLINE"), _join, true))
	col.add_child(MenuStyle.spacer(6))
	col.add_child(MenuStyle.button(tr("HUD_MENU_TEST_COURSE"), _course, false, 44))
	col.add_child(MenuStyle.button(tr("HUD_MENU_PROFILE"), func() -> void: _with_session(_show_profile), false, 44))
	col.add_child(MenuStyle.button(tr("HUD_MENU_SETTINGS"), func() -> void:
		col.visible = false
		_settings.visible = true
		_settings.focus_first(), false, 44))
	col.add_child(MenuStyle.button(tr("HUD_MENU_QUIT"), func() -> void: get_tree().quit(), false, 44))
	_status = MenuStyle.label(notice, 14, HudPalette.LUMEN, HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	_load_settings()
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.back_pressed.connect(func() -> void:
		_settings.visible = false
		col.visible = true
		_play.grab_focus())
	center.add_child(_settings)
	_build_social()
	GameSettings.shared().apply_display()
	_refresh_chip()
	if AppRoot.rejoin_address != "":
		var addr := AppRoot.rejoin_address
		AppRoot.rejoin_address = ""
		# Back to the server's lobby after a match (resumes the session).
		_open_lobby.call_deferred(addr)
		return
	if _resume_from_launcher():
		pass  # signed in by the launcher: connected, OP_RESUME sent
	elif session_token != "" and session_server != "":
		_connect(session_server)  # still logged in (memory): friends panel online
	_play.grab_focus.call_deferred()  # keyboard / gamepad navigation starts here


func _build_social() -> void:
	_chip = MenuStyle.panel_container(HudPalette.PANEL_STRONG, 8)
	_chip.position = Vector2(16, 16)
	add_child(_chip)
	var dock := MarginContainer.new()
	dock.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	dock.offset_left = -312
	dock.add_theme_constant_override("margin_top", 16)
	dock.add_theme_constant_override("margin_bottom", 22)
	dock.add_theme_constant_override("margin_right", 16)
	add_child(dock)
	_friends = FriendsPanel.new()
	_friends.join_requested.connect(func(id: String) -> void: _open_lobby(online_server(), id))
	_friends.login_requested.connect(func() -> void: _with_session(Callable()))
	dock.add_child(_friends)
	_lobby_box = MarginContainer.new()
	_lobby_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby_box.add_theme_constant_override("margin_left", 24)
	_lobby_box.add_theme_constant_override("margin_top", 16)
	_lobby_box.add_theme_constant_override("margin_right", 320)
	_lobby_box.add_theme_constant_override("margin_bottom", 16)
	_lobby_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lobby_box)


## The logged-in session ({} = none).
func session() -> Dictionary:
	return _online.session if _online != null else {}


func _refresh_chip() -> void:
	_chip.visible = _lobby == null
	for c in _chip.get_children():
		_chip.remove_child(c)
		c.queue_free()
	var s := session()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if s.is_empty():
		row.add_child(MenuStyle.label(tr("HUD_MENU_NOT_LOGGED_IN"), 14, HudPalette.TEXT_DIM))
		var login := MenuStyle.button(tr("HUD_FRIENDS_LOGIN"), func() -> void: _with_session(Callable()), false, 30)
		login.add_theme_font_size_override("font_size", 12)
		row.add_child(login)
	else:
		row.add_child(EmblemIcon.make(int(s.get("emblem", 0)), int(s.get("accent", 0)), 44.0))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.add_child(MenuStyle.label(str(s.get("display_name", "")), 18,
			PlayerProfile.accent_of(int(s.get("accent", 0))).lerp(HudPalette.TEXT, 0.4)))
		var sub := tr("HUD_ACCOUNT_GUEST_LINE") if int(s.get("guest", 1)) != 0 else "#" + PlayerProfile.tag_of(str(s.get("id", "")))
		v.add_child(MenuStyle.label(sub, 12, HudPalette.TEXT_OFF))
		row.add_child(v)
		var edit := MenuStyle.button(tr("HUD_MENU_PROFILE_EDIT"), func() -> void: _with_session(_show_profile), false, 30)
		edit.add_theme_font_size_override("font_size", 12)
		edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(edit)
	_chip.add_child(row)
	var account := not s.is_empty() and int(s.get("guest", 1)) == 0
	_friends.set_session(account, _request if not s.is_empty() else Callable())


# --- online connection --------------------------------------------------------

## Runs `then` once logged in: re-uses the session, resumes it, or shows the
## login screen. An invalid `then` just logs in.
func _with_session(then: Callable, addr: String = "") -> void:
	var a := addr if addr != "" else online_server()
	_then = then
	if _online != null and not _online.session.is_empty() and _server == a:
		_run_then()
		return
	if _online == null or _server != a:
		if not _connect(a):
			return
	if session_token != "" and session_server == a:
		_online.request(AccountCodec.OP_RESUME, {"ver": MsgType.PROTOCOL_VERSION, "token": session_token})
	elif AppRoot.auto_ready and not _auto_guest_sent:
		_auto_guest()
	else:
		_show_login()


## Launcher hand-over: the launcher logged in and passed the session in the
## environment (CYBERGRAM_SESSION_TOKEN / CYBERGRAM_SESSION_SERVER), not on the
## command line. Read once, then cleared so nothing inherits it. Connects and
## resumes the session; false when the launcher gave nothing.
func _resume_from_launcher() -> bool:
	var token := OS.get_environment("CYBERGRAM_SESSION_TOKEN")
	var server := OS.get_environment("CYBERGRAM_SESSION_SERVER")
	OS.unset_environment("CYBERGRAM_SESSION_TOKEN")
	OS.unset_environment("CYBERGRAM_SESSION_SERVER")
	if token == "" or server == "":
		return false
	session_token = token
	session_server = server
	if not _connect(server):
		return false
	_online.request(AccountCodec.OP_RESUME, {"ver": MsgType.PROTOCOL_VERSION, "token": token})
	return true


func _connect(addr: String) -> bool:
	_disconnect()
	var hp := addr.rsplit(":", true, 1)
	var host := hp[0]
	var port := clampi(hp[1].to_int(), 1, 65535) if hp.size() == 2 and hp[1].is_valid_int() else ENetTransport.DEFAULT_PORT
	_enet = ENetTransport.connect_to(host, port, AuthConfig.from_os().client_tls_for(host))
	if _enet.error_text != "":
		_status.text = _enet.error_text
		_enet = null
		return false
	_server = addr
	_link_up = false
	_online = LobbyClient.new(_enet)
	_online.account_result.connect(_on_account)
	return true


## The encrypted handshake never completed: the server has no certificate yet
## (guest-only). Retry once in plain UDP; the login screen then offers guest
## play only, so no password ever travels unencrypted.
func _fall_back_to_plain() -> void:
	var addr := _server
	var host := addr.rsplit(":", true, 1)[0]
	push_warning("[net] encrypted connection to %s failed; retrying unencrypted (guest only)" % host)
	_close_login()
	_disconnect()
	if AuthConfig.plain_hosts.has(host):
		_status.text = tr("HUD_LOBBY_CONNECTION_LOST")
		_refresh_chip()
		return
	AuthConfig.plain_hosts[host] = true
	_auto_guest_sent = false
	_with_session(_then, addr)


func _disconnect() -> void:
	if _enet != null:
		_enet.close()
	_enet = null
	_online = null
	_server = ""


func _process(_delta: float) -> void:
	if _online == null or _lobby != null:
		return  # the lobby view steps the client while it is open
	_online.step()
	if _enet != null and _enet.is_server_connected():
		_link_up = true
	if _enet != null and _enet.error_text != "" and _enet.is_secure and not _link_up:
		_fall_back_to_plain()
		return
	if _enet != null and _enet.error_text != "":
		_status.text = tr("HUD_LOBBY_CONNECTION_LOST")
		_disconnect()
		if _login != null:
			_login.show_error(tr("HUD_LOGIN_NO_SERVER") % online_server())
		_refresh_chip()


## The request Callable handed to panels and screens.
func _request(op: int, fields: Dictionary) -> void:
	if _online != null:
		_online.request(op, fields)


func _on_account(d: Dictionary) -> void:
	var op: int = d.op
	var ok: bool = d.code == AccountCodec.OK
	if d.has("token") and ok:
		session_token = str(d.token)
		session_server = _server
		var was_login := _login != null
		_close_login()
		_refresh_chip()
		if was_login and int(d.guest) == 0:
			_offer_legacy_import()
		else:
			_delete_legacy_files(false)
		_run_then()
		return
	match op:
		AccountCodec.OP_RESUME:
			session_token = ""
			_show_login()  # the session expired: log in again
		AccountCodec.OP_REGISTER, AccountCodec.OP_LOGIN, AccountCodec.OP_GUEST:
			if _login != null:
				_login.show_error(_error_text(d.code))
			else:
				_status.text = _error_text(d.code)
		AccountCodec.OP_LOGOUT, AccountCodec.OP_DELETE_ACCOUNT:
			if ok:
				session_token = ""
				_close_profile()
				_status.text = tr("HUD_ACCOUNT_DELETED") if op == AccountCodec.OP_DELETE_ACCOUNT else tr("HUD_ACCOUNT_LOGGED_OUT")
				_refresh_chip()
			elif _profile_screen != null:
				_profile_screen.on_result(d)
		AccountCodec.OP_UPDATE_PROFILE:
			if _profile_screen != null:
				_profile_screen.on_result(d)
			_refresh_chip()
		AccountCodec.OP_CHANGE_PASSWORD, AccountCodec.OP_EXPORT:
			if _profile_screen != null:
				_profile_screen.on_result(d)
		_:
			_friends.on_result(d)


func _error_text(code: int) -> String:
	var t := tr(LobbyClient.account_error_key(code))
	return t % AuthConfig.rules().min_age if code == AccountCodec.E_AGE else t


func _run_then() -> void:
	var t := _then
	_then = Callable()
	if t.is_valid():
		t.call()


## Automated runs (--auto-ready): join as a generated guest (the tester is the user).
func _auto_guest() -> void:
	_auto_guest_sent = true
	var p := PlayerProfile.generated()
	_online.request(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": p.name,
		"emblem": p.emblem, "accent": p.accent, "flags": AccountCodec.FLAG_PRIVACY})


func _show_login() -> void:
	if _login != null:
		return
	_col.visible = false
	_login = LoginScreen.new()
	var hp := _server.rsplit(":", true, 1)
	var secure := _enet != null and _enet.is_secure
	_login.server_text = tr("HUD_LOGIN_SERVER") % [_server, tr("HUD_LOGIN_ENCRYPTED") if secure else tr("HUD_LOGIN_PLAIN")]
	_login.accounts_available = secure
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_login.remembered_username = str(cfg.get_value("online", "username", ""))
		_login.remember = _login.remembered_username != ""
	var legacy := PlayerProfile.load_or_null(legacy_profile_path)
	if legacy != null:
		_login.prefill_name = legacy.name
		_login.prefill_emblem = legacy.emblem
		_login.prefill_accent = legacy.accent
	_login.submitted.connect(func(op: int, f: Dictionary) -> void:
		if op == AccountCodec.OP_LOGIN:
			_save_username(_login.login_username() if _login.remember_username() else "")
		_request(op, f))
	_login.cancelled.connect(func() -> void:
		_close_login()
		_then = Callable())
	_center.add_child(_login)
	if hp.size() > 0 and not secure:
		_login.show_error(tr("HUD_LOGIN_NO_TLS"))


func _close_login() -> void:
	if _login != null:
		_login.queue_free()
		_login = null
	_col.visible = _lobby == null and _profile_screen == null


## Pre-accounts local profile: offer once to import it, then delete the files.
func _offer_legacy_import() -> void:
	var legacy := PlayerProfile.load_or_null(legacy_profile_path)
	if legacy == null:
		_delete_legacy_files(false)
		return
	_import_dialog = ConfirmationDialog.new()
	_import_dialog.title = tr("HUD_IMPORT_TITLE")
	_import_dialog.dialog_text = tr("HUD_IMPORT_BODY") % legacy.name
	_import_dialog.ok_button_text = tr("HUD_IMPORT_YES")
	_import_dialog.cancel_button_text = tr("HUD_IMPORT_NO")
	_import_dialog.confirmed.connect(func() -> void:
		_request(AccountCodec.OP_UPDATE_PROFILE, {"display_name": legacy.name, "emblem": legacy.emblem,
			"accent": legacy.accent, "favourite_hero": ""})
		_delete_legacy_files(true))
	_import_dialog.canceled.connect(func() -> void: _delete_legacy_files(false))
	add_child(_import_dialog)
	_import_dialog.popup_centered()


## Removes every pre-accounts local file (the client stores nothing now).
static func _delete_legacy_files(_imported: bool) -> void:
	var paths := LEGACY_FILES.duplicate()
	if not paths.has(legacy_profile_path):
		paths.append(legacy_profile_path)
	for p in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _save_username(u: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("online", "username", u)
	cfg.save(SETTINGS_PATH)


func _show_profile() -> void:
	if _profile_screen != null or _online == null:
		return
	_col.visible = false
	_profile_screen = ProfileScreen.new()
	_profile_screen.session = _online.session
	_profile_screen.requested.connect(_request)
	_profile_screen.closed.connect(_close_profile)
	_center.add_child(_profile_screen)


func _close_profile() -> void:
	if _profile_screen != null:
		_profile_screen.queue_free()
		_profile_screen = null
	_col.visible = _lobby == null and _login == null
	_play.grab_focus.call_deferred()


# --- play -------------------------------------------------------------------

func _play_bots() -> void:
	_start(PackedStringArray(["--hero", _hero_id()]))


## PLAY ONLINE: log in on the official server (AppConfig), then its lobby.
func _join() -> void:
	_open_lobby(online_server())


## The official online server (assets/data/app/app_config.tres).
static func online_server() -> String:
	var cfg := load(AppRoot.APP_CONFIG_PATH) as AppConfig
	return cfg.online_server if cfg != null and cfg.online_server != "" else DEFAULT_ADDRESS


## Online: the server's lobby. `party_id`: a friend to be seated with.
func _open_lobby(addr: String, party_id := "") -> void:
	if _lobby != null:
		return
	_with_session(func() -> void: _show_lobby(addr, party_id), addr)


func _show_lobby(addr: String, party_id: String) -> void:
	if _lobby != null or _online == null:
		return
	_save_settings()
	_col.visible = false
	var lobby := LobbyScreen.new()
	_lobby = lobby
	lobby.address = addr
	lobby.online = _online
	lobby.link = _enet
	lobby.party_id = party_id
	var fav := str(_online.session.get("favourite_hero", ""))
	lobby.hero_id = fav if fav != "" and not HeroCatalog.find_stem(fav).is_empty() else _hero_id()
	lobby.auto_ready = AppRoot.auto_ready
	for e: Dictionary in _friends.entries:
		lobby.friend_ids.append(str(e.id))
	lobby.start_requested.connect(func(args: PackedStringArray) -> void:
		_disconnect()  # the match opens its own connection; the session token stays in memory
		start_requested.emit(args))
	lobby.cancelled.connect(func(reason: String) -> void:
		lobby.queue_free()
		_lobby = null
		_col.visible = true
		_status.text = reason
		# Leaving frees the seat: reconnect and resume the session for the friends panel.
		_disconnect()
		if session_token != "":
			_connect(addr)
			_online.request(AccountCodec.OP_RESUME, {"ver": MsgType.PROTOCOL_VERSION, "token": session_token})
		_friends.allow_join = true
		_refresh_chip()
		_play.grab_focus.call_deferred())
	# Account answers keep reaching _on_account through the shared client.
	_lobby_box.add_child(lobby)
	_friends.allow_join = false
	_refresh_chip()


func _course() -> void:
	_start(PackedStringArray(["--map", "test_course", "--hero", _hero_id()]))


func _start(args: PackedStringArray) -> void:
	_save_settings()
	start_requested.emit(args)


func _hero_id() -> String:
	if _heroes.is_empty():
		return DEFAULT_HERO
	return str(_heroes[clampi(_hero.selected, 0, _heroes.size() - 1)].stem)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var want := DEFAULT_HERO
	if cfg.load(SETTINGS_PATH) == OK:
		want = str(cfg.get_value("menu", "hero_id", DEFAULT_HERO))
	for i in _heroes.size():
		if _heroes[i].stem == want:
			_hero.selected = i


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("menu", "hero_id", _hero_id())
	cfg.save(SETTINGS_PATH)


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
