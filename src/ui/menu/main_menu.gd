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
## The held token is a guest session (may be resumed over plain UDP). An
## account token is only ever sent on a DTLS link (W11-Q1 SEC-001).
static var session_guest: bool = false
## Where the legacy profile is looked for (tests override).
static var legacy_profile_path: String = "user://profile.cfg"

## Shown under the buttons (e.g. why the last online session ended).
var notice: String = ""

## Index into HeroCatalog.entries() of the picked hero.
var _hero_index: int = 0
var _heroes: Array = []
var _status: Label
var _settings: SettingsPanel
## Overlay screens (login, profile, settings) are centred here.
var _center: CenterContainer
## The HOME page (hero banner + tiles); hidden while an overlay is open.
var _col: VBoxContainer
## The top-bar PLAY button (opens the mode select).
var _play: Button
var _chip: Button
var _friends: FriendsPanel
var _lobby_box: MarginContainer
var _lobby: LobbyScreen
var _login: LoginScreen
var _profile_screen: ProfileScreen
var _import_dialog: ConfirmationDialog
## Kit shell (design/ux/ui-kit.md §8.1).
var _root: Control
var _bg: ColorRect
var _nav: HBoxContainer
var _quick: Array[Button] = []
var _showcase: HeroShowcase
var _tiles: HBoxContainer
var _roster: HBoxContainer
var _modes: UiCard
var _mode_buttons: Array[Button] = []
var _mode: int = 0
var _confirm: Button
## The online connection (null = offline).
var _enet: ENetTransport
var _online: LobbyClient
var _server: String = ""
## Runs once the session is up (open the lobby, the profile, ...).
var _then: Callable
var _link_up: bool = false  # the server link completed its handshake
var _auto_guest_sent: bool = false

## Nav tabs of the top bar.
enum Nav { HOME, HEROES, PROFILE, SETTINGS }
const NAV_KEYS: Array[String] = ["HUD_NAV_HOME", "HUD_NAV_HEROES", "HUD_NAV_PROFILE", "HUD_NAV_SETTINGS"]
## Mode-select cards: [title key, description key]; index order = MODE_*.
const MODES: Array = [["HUD_MODE_ONLINE", "HUD_MODE_ONLINE_DESC"], ["HUD_MODE_BOTS", "HUD_MODE_BOTS_DESC"],
	["HUD_MODE_PRACTICE", "HUD_MODE_PRACTICE_DESC"], ["HUD_MODE_TUTORIAL", "HUD_MODE_TUTORIAL_DESC"],
	["HUD_MODE_COURSE", "HUD_MODE_COURSE_DESC"]]
const MODE_ONLINE := 0
const MODE_BOTS := 1
const MODE_PRACTICE := 2
const MODE_TUTORIAL := 3
const MODE_COURSE := 4
## Height of the tile row under the hero banner.
const TILE_H := 148


func _ready() -> void:
	HudStrings.ensure_loaded()  # shared UI string table (hud.csv)
	layer = 50
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var t := UiKit.tokens()
	_heroes = HeroCatalog.entries()
	_load_settings()
	_root = Control.new()
	_root.name = "Shell"
	_root.theme = UiKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_bg = UiKit.background()
	_root.add_child(_bg)
	_build_top_bar()
	# Body: content (left) + social sidebar (right).
	var body := MarginContainer.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("margin_top", t.top_bar_height + t.space_l)
	body.add_theme_constant_override("margin_left", t.space_l)
	body.add_theme_constant_override("margin_right", t.space_l)
	body.add_theme_constant_override("margin_bottom", t.space_l)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(body)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", t.space_l)
	split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(split)
	var content := Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split.add_child(content)
	_build_home(content)
	_build_modes(content)
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_center)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.back_pressed.connect(func() -> void: _go(Nav.HOME))
	_settings.changed.connect(func() -> void: UiKit.refresh_background(_bg))
	_center.add_child(_settings)
	_friends = FriendsPanel.new()
	_friends.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_friends.join_requested.connect(func(id: String) -> void: _open_lobby(online_server(), id))
	_friends.login_requested.connect(func() -> void: _with_session(Callable()))
	_friends.collapsed_changed.connect(func(_c: bool) -> void: _sync_lobby_margins())
	split.add_child(_friends)
	_lobby_box = MarginContainer.new()
	_lobby_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_lobby_box)
	_sync_lobby_margins()
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


## Top bar: PLAY (far left), nav tabs (centre), account chip + quick buttons (right).
func _build_top_bar() -> void:
	var t := UiKit.tokens()
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size.y = t.top_bar_height
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(t.bg_deep, 0.88)
	sb.border_color = Color(t.gold, 0.28)
	sb.border_width_bottom = 1
	sb.content_margin_left = t.space_l
	sb.content_margin_right = t.space_m
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 8
	bar.add_theme_stylebox_override("panel", sb)
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", t.space_l)
	bar.add_child(row)
	_play = UiKit.button(tr("HUD_MENU_PLAY"), _open_modes, &"play", 46)
	_play.custom_minimum_size.x = 168
	_play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_play)
	var mark := UiKit.label("CYBERGRAM", &"heading", t.text_dim)
	mark.add_theme_font_size_override("font_size", 13)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var sep := VSeparator.new()
	sep.custom_minimum_size.y = 28
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sep)
	var labels: Array = []
	for k in NAV_KEYS:
		labels.append(tr(k))
	_nav = UiKit.tab_bar(labels, func(i: int) -> void: _go(i), Nav.HOME, true)
	_nav.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for b: Button in _nav.get_children():
		b.custom_minimum_size.y = t.top_bar_height - 16
	row.add_child(_nav)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)
	_chip = Button.new()
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_button(_chip, &"ghost")
	UiSfx.attach(_chip)
	_chip.pressed.connect(func() -> void:
		if session().is_empty():
			_with_session(Callable())
		else:
			_go(Nav.PROFILE))
	row.add_child(_chip)
	var gear := UiKit.icon_button(&"gear", func() -> void: _go(Nav.SETTINGS), tr("HUD_QUICK_SETTINGS"), 36)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(gear)
	var quit := UiKit.icon_button(&"close", _confirm_quit, tr("HUD_QUICK_QUIT"), 36)
	quit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(quit)
	_quick = [gear, quit]


## HOME page: hero banner, status line, then news / event tiles (or the
## hero roster on the HEROES tab).
func _build_home(content: Control) -> void:
	var t := UiKit.tokens()
	_col = VBoxContainer.new()
	_col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_col.add_theme_constant_override("separation", t.space_m)
	content.add_child(_col)
	_showcase = HeroShowcase.new()
	_showcase.heroes = _heroes
	_showcase.selected = _hero_index
	_showcase.with_model = DisplayServer.get_name() != "headless"  # no 3D stage in headless runs
	_showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_showcase.hero_changed.connect(func(i: int) -> void:
		_hero_index = i
		_save_settings())
	_col.add_child(_showcase)
	var tag := UiKit.label(tr("HUD_MENU_TAGLINE") % _version(), &"caption", t.text_off)
	tag.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tag.position = Vector2(t.space_xl, t.space_l)
	_showcase.add_child(tag)
	# Status line (why the last online session ended, connection errors):
	# top right of the banner.
	_status = UiKit.label(notice, &"small", HudPalette.LUMEN, HORIZONTAL_ALIGNMENT_RIGHT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_status.offset_left = -440
	_status.offset_right = -t.space_xl
	_status.offset_top = t.space_l
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_showcase.add_child(_status)
	_tiles = HBoxContainer.new()
	_tiles.custom_minimum_size.y = TILE_H
	_tiles.add_theme_constant_override("separation", t.space_m)
	_col.add_child(_tiles)
	var news := UiKit.card(tr("HUD_NEWS_TITLE") % _version(), 12)
	news.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	news.size_flags_stretch_ratio = 1.6
	for k in ["HUD_NEWS_1", "HUD_NEWS_2", "HUD_NEWS_3"]:
		var l := UiKit.label("•  " + tr(k), &"small", t.text_dim)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		news.body.add_child(l)
	news.body.add_theme_constant_override("separation", 4)
	_tiles.add_child(news)
	_tiles.add_child(_tile(MODE_PRACTICE))
	_tiles.add_child(_tile(MODE_TUTORIAL))
	_roster = HBoxContainer.new()
	_roster.custom_minimum_size.y = TILE_H
	_roster.add_theme_constant_override("separation", t.space_s)
	_roster.visible = false
	_col.add_child(_roster)
	for i in _heroes.size():
		var h: Dictionary = _heroes[i]
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		UiKit.swatch_button(b, t.panel)
		UiSfx.attach(b)
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 4)
		var badge := HeroBadge.make(int(h.index), 56)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(badge)
		var nm := UiKit.label(str(h.name), &"small", t.text, HORIZONTAL_ALIGNMENT_CENTER)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(nm)
		var role := UiKit.label(tr(HeroShowcase.ROLE_KEYS.get(str(h.stem), "HUD_ROLE_SOLDIER")), &"caption",
			t.text_off, HORIZONTAL_ALIGNMENT_CENTER)
		role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(role)
		b.add_child(v)
		b.pressed.connect(func() -> void:
			_showcase.select(i)
			_sync_roster())
		_roster.add_child(b)


## An event tile under the banner that launches mode `m` directly.
func _tile(m: int) -> Button:
	var t := UiKit.tokens()
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_button(b, &"secondary")
	UiSfx.attach(b)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 16
	v.offset_top = 14
	v.offset_right = -16
	v.offset_bottom = -14
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_child(UiIcon.make(&"play", 14, t.gold))
	var title := UiKit.label(tr(MODES[m][0]), &"heading")
	title.add_theme_font_size_override("font_size", t.size_small + 1)
	head.add_child(title)
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var d := UiKit.label(tr(MODES[m][1]), &"small", t.text_dim)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	b.add_child(v)
	b.pressed.connect(func() -> void: _launch_mode(m))
	return b


## PLAY -> mode select (LoL-style queue picker with CONFIRM).
func _build_modes(content: Control) -> void:
	var t := UiKit.tokens()
	_modes = UiKit.card(tr("HUD_MODE_TITLE"), t.space_xl)
	_modes.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modes.visible = false
	content.add_child(_modes)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", t.space_l)
	_modes.body.add_child(row)
	var group := ButtonGroup.new()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_stretch_ratio = 1.4
	grid.add_theme_constant_override("h_separation", t.space_m)
	grid.add_theme_constant_override("v_separation", t.space_m)
	for m in MODES.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 96
		UiKit.style_button(b, &"secondary")
		var pressed := b.get_theme_stylebox("pressed") as UiBevelBox
		pressed.fill = Color(t.accent, 0.22)
		pressed.fill_hover = pressed.fill
		pressed.border = t.accent_hi
		pressed.border_hover = t.accent_hi
		pressed.glow = Color(t.accent, 0.8)
		pressed.glow_rest = 0.6
		UiSfx.attach(b)
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 18
		v.offset_top = 14
		v.offset_right = -18
		v.offset_bottom = -14
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 6)
		var title := UiKit.label(tr(MODES[m][0]), &"title" if m == MODE_ONLINE else &"heading")
		v.add_child(title)
		var d := UiKit.label(tr(MODES[m][1]), &"small", t.text_dim)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		b.add_child(v)
		var glyph := UiIcon.make([&"friends", &"play", &"target", &"check", &"up"][m],
			72.0 if m == MODE_ONLINE else 44.0, Color(t.accent_hi, 0.35))
		glyph.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		glyph.offset_left = -glyph.custom_minimum_size.x - 18
		glyph.offset_top = -glyph.custom_minimum_size.y - 16
		glyph.offset_right = -18
		glyph.offset_bottom = -16
		b.add_child(glyph)
		b.pressed.connect(func() -> void: _mode = m)
		_mode_buttons.append(b)
		if m == MODE_ONLINE:
			b.size_flags_stretch_ratio = 1.0
			row.add_child(b)
			row.add_child(grid)
		else:
			grid.add_child(b)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", t.space_m)
	_modes.body.add_child(UiKit.spacer(t.space_s))
	_modes.body.add_child(foot)
	foot.add_child(UiKit.button(tr("HUD_MODE_BACK"), func() -> void: _go(Nav.HOME), &"ghost", 44))
	_confirm = UiKit.button(tr("HUD_MODE_CONFIRM"), func() -> void: _launch_mode(_mode), &"primary", 48)
	_confirm.custom_minimum_size.x = 220
	foot.add_child(_confirm)


func _open_modes() -> void:
	if _lobby != null:
		return
	_hide_pages()
	_modes.visible = true
	UiKit.transition_in(_modes)
	_mode_buttons[_mode].set_pressed_no_signal(true)
	_mode_buttons[_mode].grab_focus.call_deferred()


func _launch_mode(m: int) -> void:
	match m:
		MODE_ONLINE:
			_join()
		MODE_BOTS:
			_play_bots()
		MODE_PRACTICE:
			_practice()
		MODE_TUTORIAL:
			_tutorial()
		_:
			_course()


## Hides every content page (home, modes, settings); overlays stay.
func _hide_pages() -> void:
	_col.visible = false
	_modes.visible = false
	_settings.visible = false


## Top-bar navigation.
func _go(i: int) -> void:
	_set_nav(i)
	match i:
		Nav.PROFILE:
			_with_session(_show_profile)
			return
		Nav.SETTINGS:
			_close_profile_only()
			_hide_pages()
			_settings.visible = true
			UiKit.transition_in(_settings)
			_settings.focus_first()
			return
	_close_profile_only()
	_hide_pages()
	_col.visible = _login == null and _lobby == null
	_tiles.visible = i == Nav.HOME
	_roster.visible = i == Nav.HEROES
	_sync_roster()
	UiKit.transition_in(_col)
	if i == Nav.HEROES:
		_showcase.focus_badge.call_deferred()
	else:
		_play.grab_focus.call_deferred()


func _set_nav(i: int) -> void:
	for k in _nav.get_child_count():
		(_nav.get_child(k) as Button).set_pressed_no_signal(k == i)


func _sync_roster() -> void:
	for k in _roster.get_child_count():
		(_roster.get_child(k) as Button).set_pressed_no_signal(k == _showcase.selected)


func _close_profile_only() -> void:
	if _profile_screen != null:
		_profile_screen.queue_free()
		_profile_screen = null


## While the lobby is open the shell's PLAY and nav are locked (the lobby owns
## the screen, LoL champ-select style); the chip and quick buttons stay.
func _sync_shell() -> void:
	var busy := _lobby != null
	_play.disabled = busy
	for b: Button in _nav.get_children():
		b.disabled = busy


func _sync_lobby_margins() -> void:
	var t := UiKit.tokens()
	_lobby_box.add_theme_constant_override("margin_left", t.space_l)
	_lobby_box.add_theme_constant_override("margin_top", t.top_bar_height + t.space_l)
	_lobby_box.add_theme_constant_override("margin_right", _friends.dock_width() + t.space_l * 2)
	_lobby_box.add_theme_constant_override("margin_bottom", t.space_l)


func _confirm_quit() -> void:
	UiKit.modal(_root, tr("HUD_QUIT_TITLE"), tr("HUD_QUIT_BODY"), tr("HUD_MENU_QUIT"),
		func() -> void: get_tree().quit(), tr("HUD_MODE_BACK"), func() -> void: _play.grab_focus(), true)


func _unhandled_input(event: InputEvent) -> void:
	if _lobby != null or _login != null or not event.is_action_pressed("ui_cancel"):
		return
	if _modes.visible or _settings.visible or _roster.visible or _profile_screen != null:
		get_viewport().set_input_as_handled()
		_go(Nav.HOME)


## The logged-in session ({} = none).
func session() -> Dictionary:
	return _online.session if _online != null else {}


func _refresh_chip() -> void:
	var t := UiKit.tokens()
	_sync_shell()
	for c in _chip.get_children():
		_chip.remove_child(c)
		c.queue_free()
	var s := session()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(8, 4)
	var ring := t.text_off
	var name_text := tr("HUD_MENU_NOT_LOGGED_IN")
	var sub := tr("HUD_FRIENDS_LOGIN")
	var em := EmblemIcon.make(0, 0, 30.0)
	if not s.is_empty():
		var guest := int(s.get("guest", 1)) != 0
		ring = t.text_dim if guest else t.accent_hi
		name_text = str(s.get("display_name", ""))
		sub = tr("HUD_ACCOUNT_GUEST_LINE") if guest else "#" + PlayerProfile.tag_of(str(s.get("id", "")))
		em = EmblemIcon.make(int(s.get("emblem", 0)), int(s.get("accent", 0)), 30.0)
	else:
		em.modulate = Color(1, 1, 1, 0.35)
	row.add_child(UiKit.avatar(em, ring, 40.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UiKit.label(name_text, &"body", t.text if not s.is_empty() else t.text_dim)
	if not s.is_empty():
		nl.add_theme_color_override("font_color", PlayerProfile.accent_of(int(s.get("accent", 0))).lerp(t.text, 0.5))
	v.add_child(nl)
	v.add_child(UiKit.label(sub, &"caption", t.text_off if not s.is_empty() else t.accent_hi))
	row.add_child(v)
	_chip.add_child(row)
	var fit := func() -> void:
		_chip.custom_minimum_size = row.get_combined_minimum_size() + Vector2(20, 8)
	row.minimum_size_changed.connect(fit)
	fit.call()
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
	if session_token != "" and session_server == a and _send_resume():
		pass
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
	session_guest = false  # the launcher only hands over account sessions
	if not _connect(server):
		return false
	if not _send_resume():
		_show_login()
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


## True when a session token of this kind may be sent on this link: an
## account token never travels over plain UDP (an attacker who blocks the DTLS
## handshake would otherwise read it after the guest-only fallback).
static func may_send_token(link_secure: bool, guest: bool) -> bool:
	return link_secure or guest


## Sends OP_RESUME with the held token when may_send_token() allows it on the
## current link. False (nothing sent) otherwise.
func _send_resume() -> bool:
	if _online == null or session_token == "":
		return false
	if not may_send_token(_enet != null and _enet.is_secure, session_guest):
		push_warning("[net] not resuming the account session over an unencrypted link")
		return false
	_online.request(AccountCodec.OP_RESUME, {"ver": MsgType.PROTOCOL_VERSION, "token": session_token})
	return true


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
		session_guest = int(d.get("guest", 0)) != 0
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
	_hide_pages()
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
	UiKit.transition_in(_login)
	if hp.size() > 0 and not secure:
		_login.show_error(tr("HUD_LOGIN_NO_TLS"))


func _close_login() -> void:
	if _login != null:
		_login.queue_free()
		_login = null
	_col.visible = _lobby == null and _profile_screen == null and not _settings.visible and not _modes.visible


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
	_hide_pages()
	_set_nav(Nav.PROFILE)
	_profile_screen = ProfileScreen.new()
	_profile_screen.session = _online.session
	_profile_screen.requested.connect(_request)
	_profile_screen.closed.connect(_close_profile)
	_center.add_child(_profile_screen)
	UiKit.transition_in(_profile_screen)


func _close_profile() -> void:
	if _profile_screen != null:
		_profile_screen.queue_free()
		_profile_screen = null
	_set_nav(Nav.HOME)
	_hide_pages()
	_tiles.visible = true
	_roster.visible = false
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
	_close_profile_only()
	_hide_pages()
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
		_go(Nav.HOME)
		_status.text = reason
		# Leaving frees the seat: reconnect and resume the session for the friends panel.
		_disconnect()
		if session_token != "":
			if _connect(addr):
				_send_resume()
		_friends.allow_join = true
		_refresh_chip()
		_play.grab_focus.call_deferred())
	# Account answers keep reaching _on_account through the shared client.
	_lobby_box.add_child(lobby)
	_friends.allow_join = false
	_refresh_chip()


func _course() -> void:
	_start(PackedStringArray(["--map", "test_course", "--hero", _hero_id()]))


func _practice() -> void:
	_start(PracticeRange.begin(_hero_id()))


func _tutorial() -> void:
	_start(PracticeRange.begin_tutorial(_hero_id()))


func _start(args: PackedStringArray) -> void:
	_save_settings()
	start_requested.emit(args)


func _hero_id() -> String:
	if _heroes.is_empty():
		return DEFAULT_HERO
	return str(_heroes[clampi(_hero_index, 0, _heroes.size() - 1)].stem)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var want := DEFAULT_HERO
	if cfg.load(SETTINGS_PATH) == OK:
		want = str(cfg.get_value("menu", "hero_id", DEFAULT_HERO))
	for i in _heroes.size():
		if _heroes[i].stem == want:
			_hero_index = i


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("menu", "hero_id", _hero_id())
	cfg.save(SETTINGS_PATH)


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
