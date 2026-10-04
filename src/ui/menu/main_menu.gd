class_name MainMenu
extends CanvasLayer
## Title screen (shown when the game starts without command-line arguments).
## It only chooses launch arguments: AppRoot turns them into a LaunchConfig and
## builds the session, exactly as if they had been typed on the command line.
##   Play vs Bots     -> --hero <id>                 (slice 3v3 vs bots)
##   Play Online      -> the official server's lobby (AppConfig.online_server)
##   Movement Course  -> --map test_course
## Also (design/ux/lobby-and-social.md): the profile chip + PROFILE screen
## (first launch asks for a profile before anything else), and the friends
## panel docked on the right with presence from the official server.
## Privacy (PRIVACY.md): offline play needs no consent; PLAY ONLINE, Join
## friend and the presence check-ins need the acknowledged privacy notice
## (PlayerProfile.can_play_online), otherwise the profile screen asks first.
## The hero pick is remembered in user://menu.cfg; the hero list comes from
## ContentDB (HeroCatalog), so new heroes appear without code changes.

## Emitted with the chosen launch arguments.
signal start_requested(args: PackedStringArray)

const SETTINGS_PATH := "user://menu.cfg"
const DEFAULT_ADDRESS := "127.0.0.1:7777"
const DEFAULT_HERO := "vesper_loom"

## Where the profile and the friends list live (evidence captures override).
static var profile_path: String = PlayerProfile.DEFAULT_PATH
static var friends_path: String = FriendList.DEFAULT_PATH
static var moderation_path: String = LocalModeration.DEFAULT_PATH
## Poll the official server for friends' presence (off in evidence captures).
static var presence_enabled: bool = true

## Shown under the buttons (e.g. why the last online session ended).
var notice: String = ""
## The local profile (null until created on first launch).
var profile: PlayerProfile

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
var _profile_screen: ProfileScreen
var _presence: PresenceClient
var _resolve_id: int = -1
var _server_ip: String = ""
var _pending_query: Array = []


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
	col.add_child(MenuStyle.button(tr("HUD_MENU_PROFILE"), func() -> void: _show_profile(), false, 44))
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

	profile = PlayerProfile.load_or_null(profile_path)
	if profile == null and AppRoot.auto_ready:
		# Automated test runs (--auto-ready) never block on the profile screen;
		# the tester running them acknowledges the notice for this local profile.
		profile = PlayerProfile.generated()
		profile.privacy_ack = PlayerProfile.PRIVACY_VERSION
		profile.save(profile_path)
	_refresh_chip()
	if profile == null:
		_show_profile(true)  # first launch: who are you?
		return
	_continue_boot()


## After the profile exists: back to the lobby after a match, or the menu.
func _continue_boot() -> void:
	if AppRoot.rejoin_address != "":
		var addr := AppRoot.rejoin_address
		AppRoot.rejoin_address = ""
		_open_lobby.call_deferred(addr)  # back to the server's lobby after a match
		return
	_play.grab_focus.call_deferred()  # keyboard / gamepad navigation starts here


func _build_social() -> void:
	# Profile chip, top left.
	_chip = MenuStyle.panel_container(HudPalette.PANEL_STRONG, 8)
	_chip.position = Vector2(16, 16)
	add_child(_chip)
	# Friends panel, docked right (LoL client).
	var dock := MarginContainer.new()
	dock.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	dock.offset_left = -312
	dock.add_theme_constant_override("margin_top", 16)
	dock.add_theme_constant_override("margin_bottom", 22)
	dock.add_theme_constant_override("margin_right", 16)
	add_child(dock)
	_friends = FriendsPanel.new()
	_friends.friends = FriendList.load_from(friends_path)
	_friends.save_path = friends_path
	_friends.join_requested.connect(func(id: String) -> void: _open_lobby(online_server(), id))
	dock.add_child(_friends)
	_use_menu_presence()
	# Lobby area: everything left of the friends panel.
	_lobby_box = MarginContainer.new()
	_lobby_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby_box.add_theme_constant_override("margin_left", 24)
	_lobby_box.add_theme_constant_override("margin_top", 16)
	_lobby_box.add_theme_constant_override("margin_right", 320)
	_lobby_box.add_theme_constant_override("margin_bottom", 16)
	_lobby_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lobby_box)


func _refresh_chip() -> void:
	for c in _chip.get_children():
		_chip.remove_child(c)
		c.queue_free()
	_chip.visible = profile != null
	if profile == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(EmblemIcon.make(profile.emblem, profile.accent, 44.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(MenuStyle.label(profile.name, 18, PlayerProfile.accent_of(profile.accent).lerp(HudPalette.TEXT, 0.4)))
	v.add_child(MenuStyle.label("#" + profile.tag(), 12, HudPalette.TEXT_OFF))
	row.add_child(v)
	var edit := MenuStyle.button(tr("HUD_MENU_PROFILE_EDIT"), func() -> void: _show_profile(), false, 30)
	edit.add_theme_font_size_override("font_size", 12)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(edit)
	_chip.add_child(row)


## Local data files (export / delete in the profile screen).
static func data_files() -> LocalData.Files:
	var f := LocalData.Files.new()
	f.profile = profile_path
	f.friends = friends_path
	f.moderation = moderation_path
	f.menu = SETTINGS_PATH
	return f


## The profile screen (first = first launch, no Cancel). `then` runs after a
## save (e.g. open the lobby once the privacy notice is acknowledged).
func _show_profile(first := false, online_required := false, then := Callable()) -> void:
	if _profile_screen != null:
		return
	_col.visible = false
	_profile_screen = ProfileScreen.new()
	_profile_screen.profile = null if first else profile
	_profile_screen.path = profile_path
	_profile_screen.files = data_files()
	_profile_screen.online_required = online_required
	_profile_screen.saved.connect(func(p: PlayerProfile) -> void:
		profile = p
		_close_profile()
		_refresh_chip()
		_use_menu_presence()
		if first:
			_continue_boot()
		if then.is_valid() and p.can_play_online():
			then.call())
	_profile_screen.cancelled.connect(_close_profile)
	_profile_screen.deleted.connect(func() -> void:
		# Right to erasure: everything local is gone; start over as on first launch.
		profile = null
		_friends.friends = FriendList.new()
		_friends.status.clear()
		_friends.rebuild()
		_close_profile()
		_refresh_chip()
		_use_menu_presence()
		_status.text = tr("HUD_PRIVACY_DELETED")
		_show_profile(true))
	_center.add_child(_profile_screen)


func _close_profile() -> void:
	if _profile_screen != null:
		_profile_screen.queue_free()
		_profile_screen = null
	_col.visible = true
	_play.grab_focus.call_deferred()


func _play_bots() -> void:
	_start(PackedStringArray(["--hero", _hero_id()]))


## PLAY ONLINE: the official server from AppConfig (no address to type).
func _join() -> void:
	_open_lobby(online_server())


## The official online server (assets/data/app/app_config.tres).
static func online_server() -> String:
	var cfg := load(AppRoot.APP_CONFIG_PATH) as AppConfig
	return cfg.online_server if cfg != null and cfg.online_server != "" else DEFAULT_ADDRESS


## Online: the server's lobby (teams, hero pick, Ready, chat) before each
## match. `party_id`: a friend to be seated with ("Join friend").
func _open_lobby(addr: String, party_id := "") -> void:
	if _lobby != null or profile == null:
		return
	if not profile.can_play_online():
		_show_profile(false, true, func() -> void: _open_lobby(addr, party_id))
		return
	_save_settings()
	_col.visible = false
	_chip.visible = false
	var lobby := LobbyScreen.new()
	_lobby = lobby
	lobby.address = addr
	lobby.profile = profile
	lobby.party_id = party_id
	lobby.hero_id = _hero_id()
	lobby.auto_ready = AppRoot.auto_ready
	lobby.friend_ids = _friends.friends.ids()
	lobby.moderation_path = moderation_path
	lobby.start_requested.connect(func(args: PackedStringArray) -> void: start_requested.emit(args))
	lobby.cancelled.connect(func(reason: String) -> void:
		lobby.queue_free()
		_lobby = null
		_use_menu_presence()
		_col.visible = true
		_chip.visible = true
		_status.text = reason
		_play.grab_focus.call_deferred())
	lobby.presence_received.connect(_friends.apply_presence)
	lobby.add_friend_requested.connect(func(id: String, n: String) -> void: _friends.add_known(id, n))
	lobby.roster_seen.connect(func(slots: Array) -> void:
		var changed := false
		for sl: Dictionary in slots:
			if _friends.friends.resolve(str(sl.id), str(sl.name)):
				changed = true
			if _friends.friends.find_id(str(sl.id)) != null:
				_friends.status[str(sl.id)] = LobbyCodec.STATUS_IN_LOBBY if sl.connected else LobbyCodec.STATUS_OFFLINE
		if changed:
			_friends.friends.save(friends_path)
			lobby.friend_ids = _friends.friends.ids()
		_friends.rebuild())
	_lobby_box.add_child(lobby)
	_friends.allow_join = false
	_friends.query = lobby.query_presence
	_friends.rebuild()


## Friends presence from the main menu: short-lived queries to the server.
func _use_menu_presence() -> void:
	_friends.allow_join = true
	var online_ok := profile != null and profile.can_play_online()
	_friends.query = _menu_query if online_ok and presence_enabled and DisplayServer.get_name() != "headless" \
		else Callable()
	_friends.rebuild()


func _menu_query(ids: PackedStringArray, names: PackedStringArray) -> void:
	if _presence != null or _resolve_id >= 0 or profile == null or not profile.can_play_online():
		return
	var hp := online_server().rsplit(":", true, 1)
	_pending_query = [ids, names]
	if hp[0].is_valid_ip_address():
		_server_ip = hp[0]
	if _server_ip != "":
		_start_presence()
	else:
		# Non-blocking DNS: the menu must never stall on a slow resolver.
		_resolve_id = IP.resolve_hostname_queue_item(hp[0], IP.TYPE_IPV4)


func _process(delta: float) -> void:
	if _resolve_id >= 0:
		var st := IP.get_resolve_item_status(_resolve_id)
		if st == IP.RESOLVER_STATUS_DONE:
			_server_ip = IP.get_resolve_item_address(_resolve_id)
			IP.erase_resolve_item(_resolve_id)
			_resolve_id = -1
			if _server_ip != "":
				_start_presence()
		elif st == IP.RESOLVER_STATUS_ERROR or st == IP.RESOLVER_STATUS_NONE:
			IP.erase_resolve_item(_resolve_id)
			_resolve_id = -1
	if _presence != null:
		_presence.step(delta)


func _start_presence() -> void:
	var hp := online_server().rsplit(":", true, 1)
	var port := hp[1].to_int() if hp.size() == 2 and hp[1].is_valid_int() else ENetTransport.DEFAULT_PORT
	var t := ENetTransport.connect_to(_server_ip, port)
	if t.error_text != "":
		return
	_presence = PresenceClient.new(t, profile.to_wire(), _pending_query[0], _pending_query[1])
	_presence.finished.connect(func(entries: Array, ok: bool) -> void:
		_presence = null
		if ok and _lobby == null:
			_friends.apply_presence(entries))


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
	cfg.set_value("menu", "hero_id", _hero_id())
	cfg.save(SETTINGS_PATH)


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
