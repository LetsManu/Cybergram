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
## W15: the next OP_PARTY answer decides whether to open the lobby (launcher start).
var _party_check := false
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
## The content area left of the social rail, under the top bar.
var _content: Control
## Detail of the selected mode (PLAY overlay).
var _mode_portrait: TextureRect
var _mode_name: Label
var _mode_desc: Label
var _mode_rows: Array[Dictionary] = []
var _bg: ColorRect
var _nav: HBoxContainer
var _quick: Array[Button] = []
var _showcase: HeroShowcase
var _tiles: Control
var _roster: Control
var _roster_grid: HBoxContainer
var _modes: Control
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
## W21-U2: ends every wait on the server with a clear message and a retry.
var _watch: ConnectionWatch = ConnectionWatch.new()
var _conn_error: ConnectionErrorPanel
## W21-U2: the CAREER page container (profile + ranks).
var _career: CareerLayout
## The `then` / address of the last _with_session, kept for the retry button.
var _retry_then: Callable
var _retry_addr: String = ""

## Nav tabs of the top bar.
enum Nav { HOME, HEROES, PROFILE, SETTINGS }
const NAV_KEYS: Array[String] = ["HUD_NAV_HOME", "HUD_NAV_HEROES", "HUD_NAV_PROFILE", "HUD_NAV_SETTINGS"]
## Mode-select cards: [title key, description key]; index order = MODE_*.
const MODES: Array = [["HUD_MODE_ONLINE", "HUD_MODE_ONLINE_DESC"], ["HUD_MODE_BOTS", "HUD_MODE_BOTS_DESC"],
	["HUD_MODE_PRACTICE", "HUD_MODE_PRACTICE_DESC"], ["HUD_MODE_TUTORIAL", "HUD_MODE_TUTORIAL_DESC"],
	["HUD_MODE_COURSE", "HUD_MODE_COURSE_DESC"], ["HUD_MODE_QUICK", "HUD_MODE_QUICK_DESC"]]
## PLAY overlay rows (index = MODE_*): [name, meta line, detail, CTA, portrait stem].
const MODE_INFO: Array = [
	["HUD_MODE_NAME_ONLINE", "HUD_MODE_META_ONLINE", "HUD_MODE_LONG_ONLINE", "HUD_MODE_CTA_ONLINE", "vesper_loom"],
	["HUD_MODE_NAME_BOTS", "HUD_MODE_META_BOTS", "HUD_MODE_LONG_BOTS", "HUD_MODE_CTA_START", "brannoc"],
	["HUD_MODE_NAME_PRACTICE", "HUD_MODE_META_PRACTICE", "HUD_MODE_LONG_PRACTICE", "HUD_MODE_CTA_PRACTICE",
		"ryker_vance"],
	["HUD_MODE_NAME_TUTORIAL", "HUD_MODE_META_TUTORIAL", "HUD_MODE_LONG_TUTORIAL", "HUD_MODE_CTA_TUTORIAL",
		"liora_vale"],
	["HUD_MODE_NAME_COURSE", "HUD_MODE_META_COURSE", "HUD_MODE_COURSE_DESC", "HUD_MODE_CTA_START", "sable"],
	["HUD_MODE_NAME_QUICK", "HUD_MODE_META_QUICK", "HUD_MODE_LONG_QUICK", "HUD_MODE_CTA_START", "brannoc"]]
## Top-bar tabs (index = Nav): CAREER opens the profile; settings is the gear.
const NAV_TAB_KEYS: Array[String] = ["HUD_NAV_HOME", "HUD_NAV_HEROES", "HUD_NAV_CAREER"]
## Patch strip items: HUD_PATCH_<n>_TITLE / _SUB (built, so the key scanner
## does not read a prefix as a key).
const PATCH_ITEMS := 3
## The mockup's reference resolution: the shell is laid out at this size and scaled.
const REF_SIZE := Vector2(1440, 810)
const MODE_ONLINE := 0
const MODE_BOTS := 1
const MODE_PRACTICE := 2
const MODE_TUTORIAL := 3
const MODE_COURSE := 4
## W14: the 1-lane slice map "Shardline Causeway" as a short 3v3 vs bots.
const MODE_QUICK := 5
## Height of the tile row under the hero banner.


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
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	get_viewport().size_changed.connect(_fit_stage)
	_watch.failed.connect(_on_watch_failed)
	_fit_stage()
	_bg = UiKit.background()
	_root.add_child(_bg)
	# Content area (left of the social rail, under the top bar).
	_content = Control.new()
	_content.name = "Content"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_top = t.top_bar_height
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)
	_build_home(_content)
	_build_modes(_content)
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_center)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.back_pressed.connect(func() -> void: _go(Nav.HOME))
	_settings.changed.connect(func() -> void: UiKit.refresh_background(_bg))
	_center.add_child(_settings)
	_friends = FriendsPanel.new()
	_friends.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_friends.offset_top = t.top_bar_height
	_friends.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_friends.join_requested.connect(func(id: String) -> void: _open_lobby(online_server(), id))
	_friends.login_requested.connect(func() -> void: _with_session(Callable()))
	_friends.collapsed_changed.connect(func(_c: bool) -> void: _sync_lobby_margins())
	_root.add_child(_friends)
	_build_top_bar()
	_lobby_box = MarginContainer.new()
	_lobby_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_lobby_box)
	_sync_lobby_margins()
	GameSettings.shared().apply_display()
	_refresh_chip()
	GamePresence.show_state(GamePresence.State.IN_LAUNCHER)  # W15: Discord presence (opt-in)
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
	# Keyboard / gamepad navigation starts at PLAY on the first nav input
	# (_unhandled_input), so a mouse user never sees a focus ring at start.


## Scales the shell so the 1440x810 reference layout (design/ux/mockups/v0.9)
## fills the window: height drives the scale, the width follows the aspect.
func _fit_stage() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return
	var s := vp.y / REF_SIZE.y
	_root.scale = Vector2(s, s)
	_root.position = Vector2.ZERO
	_root.size = Vector2(vp.x / s, REF_SIZE.y)


## Top bar: brass PLAY, the CYBERGRAM wordmark and a divider, HOME / HEROES /
## CAREER text tabs, then the account (avatar, name, status), settings, quit.
func _build_top_bar() -> void:
	var t := UiKit.tokens()
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size.y = t.top_bar_height
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(t.bg, 0.94)
	sb.border_color = t.line
	sb.border_width_bottom = 1
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	bar.add_theme_stylebox_override("panel", sb)
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	bar.add_child(row)
	_play = UiKit.button(tr("HUD_MENU_PLAY"), _open_modes, &"play", 44)
	_play.custom_minimum_size.x = 136
	_play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_play)
	var mark := Label.new()
	mark.text = "CYBERGRAM"
	mark.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(14, 0.34)))
	mark.add_theme_font_size_override("font_size", 14)
	mark.add_theme_color_override("font_color", t.text_dim)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 28)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sep)
	var labels: Array = []
	for k in NAV_TAB_KEYS:
		labels.append(tr(k))
	_nav = UiKit.tab_bar(labels, func(i: int) -> void: _go(i), Nav.HOME, true)
	_nav.add_theme_constant_override("separation", 6)
	for b: Button in _nav.get_children():
		b.custom_minimum_size.y = t.top_bar_height
	row.add_child(_nav)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)
	_chip = Button.new()
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_button(_chip, &"ghost")
	var bare := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		_chip.add_theme_stylebox_override(st, bare)
	_chip.pressed.connect(func() -> void:
		if session().is_empty():
			_with_session(Callable())
		else:
			_go(Nav.PROFILE))
	row.add_child(_chip)
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 4)
	row.add_child(icons)
	var gear := UiKit.icon_button(&"gear", func() -> void: _go(Nav.SETTINGS), tr("HUD_QUICK_SETTINGS"), 44)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icons.add_child(gear)
	var quit := UiKit.icon_button(&"close", _confirm_quit, tr("HUD_QUICK_QUIT"), 44)
	quit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icons.add_child(quit)
	_quick = [gear, quit]


## HOME page (_col): the hero showcase and the patch strip; the HEROES tab
## swaps them for the roster of tall portraits.
func _build_home(content: Control) -> void:
	var t := UiKit.tokens()
	_col = VBoxContainer.new()  # kept as the page root (tests, capture scenes)
	_col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_col)
	var page := Control.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(page)
	_showcase = HeroShowcase.new()
	_showcase.heroes = _heroes
	_showcase.selected = _hero_index
	_showcase.with_model = DisplayServer.get_name() != "headless"  # no 3D stage in headless runs
	_showcase.set_anchors_preset(Control.PRESET_FULL_RECT)
	_showcase.hero_changed.connect(func(i: int) -> void:
		_hero_index = i
		_sync_roster()
		_save_settings())
	page.add_child(_showcase)
	# Status line (why the last online session ended, connection errors).
	_status = UiKit.label(notice, &"small", t.warn, HORIZONTAL_ALIGNMENT_RIGHT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_status.offset_left = -440
	_status.offset_right = -t.space_xl
	_status.offset_top = t.space_l
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	page.add_child(_status)
	# --- W16-COMFORT --- first-launch hint to Settings > Comfort (shown once)
	var comfort_hint := ComfortHint.new()
	comfort_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	comfort_hint.offset_left = -520
	comfort_hint.offset_right = -t.space_xl
	comfort_hint.offset_top = t.space_l + 44
	comfort_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	comfort_hint.open_requested.connect(func() -> void:
		_settings.start_tab = 4
		_go(Nav.SETTINGS)
		_settings.show_tab(4))
	page.add_child(comfort_hint)
	# --- end W16-COMFORT ---
	# Patch strip: three hairline-topped links.
	_tiles = VBoxContainer.new()
	_tiles.position = Vector2(64, 568)
	_tiles.size = Vector2(520, 100)
	_tiles.add_theme_constant_override("separation", 12)
	page.add_child(_tiles)
	var short_version := _version().get_slice(".", 0) + "." + _version().get_slice(".", 1)
	var head := UiKit.eyebrow(tr("HUD_PATCH_TITLE") % short_version, t.text_dim, 12)
	_tiles.add_child(head)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 20)
	_tiles.add_child(grid)
	for n in PATCH_ITEMS:
		var k := "HUD" + "_PATCH_%d" % (n + 1)
		var item := VBoxContainer.new()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.add_theme_constant_override("separation", 4)
		item.add_child(UiKit.hairline(true))
		item.add_child(UiKit.spacer(8))
		var a := Label.new()
		a.text = tr(k + "_TITLE")
		a.add_theme_font_override("font", UiKit.body_font(500))
		a.add_theme_font_size_override("font_size", 14)
		a.add_theme_color_override("font_color", t.text)
		item.add_child(a)
		var b := Label.new()
		b.text = tr(k + "_SUB")
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", t.text_dim)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.add_child(b)
		grid.add_child(item)
	_build_roster(page)


## HEROES page: eyebrow, title and one tall portrait card per hero.
func _build_roster(page: Control) -> void:
	var t := UiKit.tokens()
	_roster = Control.new()
	_roster.set_anchors_preset(Control.PRESET_FULL_RECT)
	_roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roster.visible = false
	page.add_child(_roster)
	var head := VBoxContainer.new()
	head.position = Vector2(64, 44)
	head.add_theme_constant_override("separation", 10)
	_roster.add_child(head)
	head.add_child(UiKit.eyebrow(tr("HUD_HEROES_EYEBROW") % _heroes.size()))
	var title := Label.new()
	title.text = tr("HUD_NAV_HEROES")
	title.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(40, 0.04)))
	title.add_theme_font_size_override("font_size", 40)
	head.add_child(title)
	_roster_grid = HBoxContainer.new()
	_roster_grid.position = Vector2(40, 158)
	_roster_grid.size = Vector2(1090, 440)
	_roster_grid.add_theme_constant_override("separation", 8)
	_roster.add_child(_roster_grid)
	for i in _heroes.size():
		var h: Dictionary = _heroes[i]
		var b := Button.new()
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 440
		b.tooltip_text = str(h.name)
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, empty)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())  # focus = brass name
		var well := Control.new()
		well.clip_contents = true
		well.set_anchors_preset(Control.PRESET_TOP_WIDE)
		well.custom_minimum_size.y = 380
		well.size.y = 380
		well.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(well)
		var img := TextureRect.new()
		img.texture = UiKit.portrait_texture(str(h.stem))
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.set_anchors_preset(Control.PRESET_CENTER_TOP)
		img.offset_left = -151
		img.offset_right = 151
		img.offset_top = 10
		img.offset_bottom = 430
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		well.add_child(img)
		var rule := UiKit.hairline(true)
		rule.set_anchors_preset(Control.PRESET_TOP_WIDE)
		rule.offset_top = 379
		rule.offset_bottom = 380
		b.add_child(rule)
		var nm := Label.new()
		nm.text = str(h.name)
		nm.uppercase = true
		nm.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(17, 0.06)))
		nm.add_theme_font_size_override("font_size", 17)
		nm.add_theme_color_override("font_color", t.text)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.set_anchors_preset(Control.PRESET_TOP_WIDE)
		nm.offset_top = 392
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(nm)
		var role := Label.new()
		role.text = tr(LobbyPhase.role_short_key(LobbyPhase.role_key(str(h.stem))))
		role.add_theme_font_size_override("font_size", 13)
		role.add_theme_color_override("font_color", t.text_dim)
		role.set_anchors_preset(Control.PRESET_TOP_WIDE)
		role.offset_top = 418
		role.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(role)
		var hot := func() -> void:
			var on := b.is_hovered() or b.has_focus() or b.button_pressed
			nm.add_theme_color_override("font_color", t.accent_hi if on else t.text)
		b.mouse_entered.connect(hot)
		b.mouse_exited.connect(hot)
		b.focus_entered.connect(hot)
		b.focus_exited.connect(hot)
		b.draw.connect(hot)
		UiSfx.attach(b)
		b.pressed.connect(func() -> void:
			_showcase.select(i)
			_go(Nav.HOME))
		_roster_grid.add_child(b)


## PLAY -> mode select: a dark overlay over the content with the big text
## mode list (diamond marker), the selected mode's detail, BACK and the CTA.
func _build_modes(content: Control) -> void:
	var t := UiKit.tokens()
	_modes = Panel.new()
	_modes.name = "Modes"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.027, 0.039, 0.051, 0.94)
	_modes.add_theme_stylebox_override("panel", sb)
	_modes.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modes.visible = false
	content.add_child(_modes)
	var eb := UiKit.eyebrow(tr("HUD_MODE_EYEBROW"))
	eb.position = Vector2(64, 48)
	_modes.add_child(eb)
	var list := VBoxContainer.new()
	list.position = Vector2(48, 96)
	list.size = Vector2(500, 0)
	list.custom_minimum_size.x = 500
	list.add_theme_constant_override("separation", 0)
	_modes.add_child(list)
	var group := ButtonGroup.new()
	for m in MODES.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(500, 100)
		var row_sb := UiKit.underline_box(t.line)
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, row_sb)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())  # focus = selection (marker)
		var marker := UiIcon.make(&"diamond", 12, t.accent)
		marker.position = Vector2(16, 32)
		b.add_child(marker)
		var nm := Label.new()
		nm.text = tr(MODE_INFO[m][0])
		nm.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(32, 0.04)))
		nm.add_theme_font_size_override("font_size", 32)
		nm.position = Vector2(44, 12)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(nm)
		var meta := Label.new()
		meta.text = tr(MODE_INFO[m][1])
		meta.add_theme_font_size_override("font_size", 13)
		meta.add_theme_color_override("font_color", t.text_dim)
		meta.position = Vector2(44, 62)
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(meta)
		_mode_rows.append({"button": b, "marker": marker, "name": nm})
		var hot := func() -> void: _paint_mode_rows()
		b.mouse_entered.connect(hot)
		b.mouse_exited.connect(hot)
		b.focus_entered.connect(func() -> void:
			b.button_pressed = true)
		b.focus_exited.connect(hot)
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_select_mode(m))
		b.pressed.connect(func() -> void: _select_mode(m))
		UiSfx.attach(b)
		b.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).double_click:
				_launch_mode(m))
		_mode_buttons.append(b)
		list.add_child(b)
	var detail := VBoxContainer.new()
	detail.position = Vector2(620, 108)
	detail.custom_minimum_size.x = 470
	detail.size.x = 470
	detail.add_theme_constant_override("separation", 0)
	_modes.add_child(detail)
	_mode_portrait = TextureRect.new()
	_mode_portrait.custom_minimum_size = Vector2(470, 360)
	_mode_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mode_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail.add_child(_mode_portrait)
	detail.add_child(UiKit.hairline(true))
	detail.add_child(UiKit.spacer(18))
	_mode_name = Label.new()
	_mode_name.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(22, 0.05)))
	_mode_name.add_theme_font_size_override("font_size", 22)
	detail.add_child(_mode_name)
	detail.add_child(UiKit.spacer(8))
	_mode_desc = Label.new()
	_mode_desc.add_theme_font_size_override("font_size", 15)
	_mode_desc.add_theme_constant_override("line_spacing", 7)
	_mode_desc.add_theme_color_override("font_color", t.text_dim)
	_mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_desc.custom_minimum_size.x = 470
	detail.add_child(_mode_desc)
	var foot := HBoxContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	foot.offset_right = -70
	foot.offset_bottom = -48
	foot.offset_top = -96
	foot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 16)
	_modes.add_child(foot)
	var back := UiKit.button(tr("HUD_MODE_BACK"), func() -> void: _go(Nav.HOME), &"secondary", 48)
	back.custom_minimum_size.x = 104
	foot.add_child(back)
	_confirm = UiKit.button(tr(MODE_INFO[0][3]), func() -> void: _launch_mode(_mode), &"primary", 48)
	_confirm.custom_minimum_size.x = 196
	foot.add_child(_confirm)
	_select_mode(_mode)


## Shows mode `m` in the detail column and on the CTA.
func _select_mode(m: int) -> void:
	_mode = m
	_mode_portrait.texture = UiKit.portrait_texture(str(MODE_INFO[m][4]))
	_mode_name.text = tr(MODE_INFO[m][0])
	_mode_desc.text = tr(MODE_INFO[m][2])
	_confirm.text = tr(MODE_INFO[m][3])
	_paint_mode_rows()


func _paint_mode_rows() -> void:
	var t := UiKit.tokens()
	for i in _mode_rows.size():
		var r: Dictionary = _mode_rows[i]
		var b := r.button as Button
		var sel := i == _mode
		(r.marker as Control).modulate.a = 1.0 if sel else 0.0
		var hot := b.is_hovered() or b.has_focus()
		(r.name as Label).add_theme_color_override("font_color", t.text if sel or hot else t.text_dim)


func _open_modes() -> void:
	if _lobby != null:
		return
	_hide_pages()
	_modes.visible = true
	UiKit.transition_in(_modes, Vector2.ZERO)
	_mode_buttons[_mode].set_pressed_no_signal(true)
	_select_mode(_mode)
	_mode_buttons[_mode].grab_focus.call_deferred()


func _launch_mode(m: int) -> void:
	# --- W17B-UI --- PLAY ONLINE opens the matchmaking flow when enabled.
	if m == MODE_ONLINE and _mm_mode() != "":
		_open_matchmaking()
		return
	# --- end W17B-UI ---
	match m:
		MODE_ONLINE:
			_join()
		MODE_BOTS:
			_play_bots()
		MODE_PRACTICE:
			_practice()
		MODE_TUTORIAL:
			_tutorial()
		MODE_QUICK:
			_play_quick()
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
	_showcase.visible = i == Nav.HOME
	_status.visible = i == Nav.HOME
	_roster.visible = i == Nav.HEROES
	_sync_roster()
	UiKit.transition_in(_col, Vector2.ZERO)
	if i == Nav.HEROES:
		_roster_grid.get_child(clampi(_showcase.selected, 0, _roster_grid.get_child_count() - 1)).grab_focus.call_deferred()
	else:
		_play.grab_focus.call_deferred()


func _set_nav(i: int) -> void:
	for k in _nav.get_child_count():
		(_nav.get_child(k) as Button).set_pressed_no_signal(k == i)


func _sync_roster() -> void:
	if _roster_grid == null:
		return
	for k in _roster_grid.get_child_count():
		var b := _roster_grid.get_child(k) as Button
		b.set_pressed_no_signal(k == _showcase.selected)
		b.queue_redraw()


func _close_profile_only() -> void:
	# --- W17B-UI ---
	if _mm_profile != null:
		_mm_profile.queue_free()
		_mm_profile = null
	# --- end W17B-UI ---
	if _profile_screen != null:
		_profile_screen.queue_free()
		_profile_screen = null
	if _career != null:
		_career.queue_free()
		_career = null


## While the lobby is open the shell's PLAY and nav are locked (the lobby owns
## the screen, LoL champ-select style); the chip and quick buttons stay.
func _sync_shell() -> void:
	var busy := _lobby != null
	_play.disabled = busy
	for b: Button in _nav.get_children():
		b.disabled = busy
	# Covered by the full-screen lobby: keep focus from wandering under it.
	_root.get_node("TopBar").visible = not busy
	_friends.visible = not busy
	_content.visible = not busy


func _sync_lobby_margins() -> void:
	var t := UiKit.tokens()
	# The lobby owns the whole screen (design/ux/mockups/v0.9 Lobby.dc.html).
	for side in ["left", "top", "right", "bottom"]:
		_lobby_box.add_theme_constant_override("margin_" + side, 0)
	_content.offset_right = -_friends.dock_width()
	_friends.offset_left = -_friends.dock_width()


func _confirm_quit() -> void:
	UiKit.modal(_root, tr("HUD_QUIT_TITLE"), tr("HUD_QUIT_BODY"), tr("HUD_MENU_QUIT"),
		func() -> void: get_tree().quit(), tr("HUD_MODE_BACK"), func() -> void: _play.grab_focus(), true)


func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() == null and _is_nav_input(event) and _play.is_visible_in_tree() \
			and _lobby == null and _login == null:
		get_viewport().set_input_as_handled()
		_play.grab_focus()
		return
	if _lobby != null or _login != null or not event.is_action_pressed("ui_cancel"):
		return
	if _modes.visible or _settings.visible or _roster.visible or _profile_screen != null:
		get_viewport().set_input_as_handled()
		_go(Nav.HOME)


## True for a keyboard / gamepad navigation press (arrows, Tab, Enter, D-pad, A).
static func _is_nav_input(event: InputEvent) -> bool:
	for a in ["ui_left", "ui_right", "ui_up", "ui_down", "ui_focus_next", "ui_accept"]:
		if event.is_action_pressed(a):
			return true
	return false


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
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(0, 0)
	var name_text := tr("HUD_MENU_NOT_LOGGED_IN")
	var sub := tr("HUD_FRIENDS_LOGIN")
	var sub_col := t.accent_hi
	var em := EmblemIcon.make(0, 0, 38.0)
	em.ring = t.line_strong
	em.dim = true
	if not s.is_empty():
		var guest := int(s.get("guest", 1)) != 0
		name_text = str(s.get("display_name", ""))
		sub = tr("HUD_ACCOUNT_GUEST_LINE") if guest else tr("HUD_MENU_STATUS_ONLINE")
		sub_col = t.text_dim if guest else t.ok
		em = EmblemIcon.make(int(s.get("emblem", 0)), int(s.get("accent", 0)), 38.0)
		em.ring = t.accent
		em.ring_width = 2.0
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(em)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := Label.new()
	nl.text = name_text
	nl.add_theme_font_override("font", UiKit.body_font(600))
	nl.add_theme_font_size_override("font_size", 15)
	nl.add_theme_color_override("font_color", t.text if not s.is_empty() else t.text_dim)
	v.add_child(nl)
	var sl := Label.new()
	sl.text = sub
	sl.add_theme_font_size_override("font_size", 12)
	sl.add_theme_color_override("font_color", sub_col)
	v.add_child(sl)
	row.add_child(v)
	_chip.add_child(row)
	var fit := func() -> void:
		_chip.custom_minimum_size = row.get_combined_minimum_size() + Vector2(4, 4)
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
	_retry_then = then
	_retry_addr = addr
	_hide_conn_error()
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


## W15: true when an OP_PARTY result shows a party with someone else in it.
static func should_join_party(d: Dictionary) -> bool:
	var n := 0
	for e: Dictionary in d.get("members", []):
		if int(e.kind) == AccountCodec.PARTY_LEADER or int(e.kind) == AccountCodec.PARTY_MEMBER:
			n += 1
	return n >= 2


## Launcher hand-over (W15 "sign in once"): the launcher passed a single-use
## launch token in the environment (LaunchHandoff, never the command line);
## it is read once and unset. Connects and redeems it (OP_REDEEM) on an
## encrypted link only; when anything fails the normal login screen shows.
## False when the launcher gave nothing.
func _resume_from_launcher() -> bool:
	var h := LaunchHandoff.take_from_os()
	if h.is_empty():
		return false
	if not _connect(str(h.server)):
		return false
	if _enet == null or not _enet.is_secure:
		push_warning("[net] not redeeming the launch token over an unencrypted link")
		_show_login()
		return true
	_online.request(AccountCodec.OP_REDEEM, {"ver": MsgType.PROTOCOL_VERSION, "token": h.token, "id": h.account})
	_watch.on_request_sent()
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
	_online.failed.connect(func(key: String) -> void:
		if key == LobbyClient.reject_text(MsgType.REJECT_PROTOCOL_MISMATCH):
			_watch.on_reject(MsgType.REJECT_PROTOCOL_MISMATCH))
	_watch.begin("%s:%d" % [host, port], _enet.is_secure)
	return true


## The encrypted handshake never completed: the server has no certificate yet
## (guest-only). Retry once in plain UDP; the login screen then offers guest
## play only, so no password ever travels unencrypted.
func _fall_back_to_plain() -> void:
	var addr := _server
	var host := addr.rsplit(":", true, 1)[0]
	push_warning("[net] encrypted connection to %s failed; retrying unencrypted (guest only)" % host)
	if AuthConfig.plain_hosts.has(host):
		# Plain UDP failed too: tell the player (card with Retry / Back).
		_on_watch_failed(ConnectionWatch.reason_key(ConnectionWatch.Reason.DTLS))
		return
	_close_login()
	_disconnect()
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
	_watch.on_request_sent()
	return true


func _disconnect() -> void:
	_watch.stop()
	if _enet != null:
		_enet.close()
	_enet = null
	_online = null
	_server = ""


func _exit_tree() -> void:
	UiKit.clear_cache()


func _process(delta: float) -> void:
	if _online == null or _lobby != null:
		return  # the lobby view steps the client while it is open
	_online.step()
	_watch.tick(delta)
	if _enet != null and _enet.is_server_connected() and not _link_up:
		_link_up = true
		_watch.on_link_up()
	if _enet != null and _enet.error_text != "" and _enet.is_secure and not _link_up:
		_fall_back_to_plain()
		return
	if _enet != null and _enet.error_text != "":
		_watch.on_transport_error(_enet.error_text, _link_up)
		if _watch.phase == ConnectionWatch.Phase.FAILED:
			return  # _on_watch_failed already dropped the link and showed the card
		_status.text = tr("HUD_LOBBY_CONNECTION_LOST")
		_disconnect()
		if _login != null:
			_login.show_error(tr("HUD_LOGIN_NO_SERVER") % online_server())
		_refresh_chip()


## The request Callable handed to panels and screens.
func _request(op: int, fields: Dictionary) -> void:
	if _online != null:
		_online.request(op, fields)
		if op in [AccountCodec.OP_LOGIN, AccountCodec.OP_REGISTER, AccountCodec.OP_GUEST]:
			_watch.on_request_sent()


func _on_account(d: Dictionary) -> void:
	var op: int = d.op
	var ok: bool = d.code == AccountCodec.OK
	if not ok:
		_watch.on_account_error(op, int(d.code))
	if d.has("token") and ok:
		_watch.on_login_ok()
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
		if op == AccountCodec.OP_REDEEM:
			# W15: signed in by the launcher; join the party's lobby if there is one.
			_party_check = true
			_online.request(AccountCodec.OP_PARTY)
		_run_then()
		return
	match op:
		AccountCodec.OP_RESUME:
			session_token = ""
			_show_login()  # the session expired: log in again
		AccountCodec.OP_REDEEM:
			_show_login()  # W15: the launch token failed: the normal login
		AccountCodec.OP_PARTY:
			if _party_check and ok and should_join_party(d):
				_open_lobby(_server)  # the server seats the party together
			_party_check = false
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
	_watch.on_request_sent()


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
	# W21-U2: PROFILE and RANKS share one responsive page (side by side, stacked or scrolling).
	_career = CareerLayout.new()
	_content.add_child(_career)
	_career.add_panel(_profile_screen)
	UiKit.transition_in(_profile_screen)
	# --- W17B-UI --- ranked medal, calibration and recent matches beside the profile.
	if _mm_mode() != "" and _mm_client() != null:
		_mm_profile = MmProfilePanel.new()
		_mm_profile.client = _mm_client()
		_career.add_panel(_mm_profile)
	# --- end W17B-UI ---


func _close_profile() -> void:
	_close_profile_only()
	_set_nav(Nav.HOME)
	_hide_pages()
	_tiles.visible = true
	_showcase.visible = true
	_roster.visible = false
	_col.visible = _lobby == null and _login == null
	_play.grab_focus.call_deferred()


# --- play -------------------------------------------------------------------

func _play_bots() -> void:
	_start(PackedStringArray(["--hero", _hero_id()]))


## QUICK: 3v3 vs bots on the 1-lane slice map (its MapDef carries the 3v3 rules).
func _play_quick() -> void:
	_start(PackedStringArray(["--map", "slice", "--bots", "--hero", _hero_id()]))


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
		GamePresence.show_state(GamePresence.State.IN_MATCH, "Online")  # W15
		start_requested.emit(args))
	lobby.cancelled.connect(func(reason: String) -> void:
		lobby.queue_free()
		_lobby = null
		GamePresence.show_state(GamePresence.State.IN_LAUNCHER)  # W15
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
	GamePresence.show_state(GamePresence.State.IN_LOBBY)  # W15
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
	GamePresence.show_state(GamePresence.State.IN_MATCH, GamePresence.mode_of(args))  # W15
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


# --- W17B-UI --- matchmaking flow (design/gdd/matchmaking.md) ----------------
## CYBERGRAM_MATCHMAKING: unset or "1" = the server's matchmaking (default since
## v0.13), "off"/"0" = PLAY ONLINE opens the classic lobby, "fake" = the offline
## MatchmakingFakeClient.
const MM_ENV := "CYBERGRAM_MATCHMAKING"
var _mm_flow: MatchmakingFlow
var _mm_profile: MmProfilePanel
var _mm_fake: MatchmakingFakeClient
var _mm_adapter: MmClientAdapter


func _mm_mode() -> String:
	var v := OS.get_environment(MM_ENV).strip_edges().to_lower()
	if v == "off" or v == "0":
		return ""
	return "1" if v == "" else v


## The screen-facing matchmaking client (null = not logged in yet).
func _mm_client() -> Object:
	if _mm_mode() == "fake":
		if _mm_fake == null:
			_mm_fake = MatchmakingFakeClient.new()
		return _mm_fake
	if _online == null or _online.matchmaking == null:
		return null
	if _mm_adapter == null or _mm_adapter.mm != _online.matchmaking:
		_mm_adapter = MmClientAdapter.new(_online.matchmaking, _online)
	return _mm_adapter


func _open_matchmaking() -> void:
	if _mm_mode() == "fake":
		_show_matchmaking()
	else:
		_with_session(_show_matchmaking)


func _show_matchmaking() -> void:
	if _mm_flow != null or _mm_client() == null:
		return
	_save_settings()
	_close_profile_only()
	_hide_pages()
	_mm_flow = MatchmakingFlow.new()
	_mm_flow.client = _mm_client()
	_mm_flow.drive_client = _mm_mode() == "fake"  # the menu's _process steps the online client
	for e: Dictionary in _friends.entries:
		_mm_flow.friends.append({"id": str(e.id), "name": str(e.get("display_name", e.get("username", "")))})
	_mm_flow.start_requested.connect(func(args: PackedStringArray) -> void:
		_disconnect()
		GamePresence.show_state(GamePresence.State.IN_MATCH, "Online")
		start_requested.emit(args))
	_mm_flow.closed.connect(func() -> void:
		_mm_flow.queue_free()
		_mm_flow = null
		_root.get_node("TopBar").visible = true
		_friends.visible = true
		_content.visible = true
		_go(Nav.HOME))
	_root.get_node("TopBar").visible = false
	_friends.visible = false
	_content.visible = false
	_lobby_box.add_child(_mm_flow)
	GamePresence.show_state(GamePresence.State.IN_LOBBY)
# --- end W17B-UI ---


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


# --- W21-U2: connection errors ------------------------------------------------

## The watchdog gave up (timeout, DTLS, version mismatch, link lost): drop the
## connection and show the reason with Retry / Back instead of staying silent.
func _on_watch_failed(reason_key: String) -> void:
	_close_login()
	_disconnect()
	_refresh_chip()
	if _conn_error == null:
		_conn_error = ConnectionErrorPanel.new()
		_conn_error.retry_requested.connect(_retry_connection)
		_conn_error.back_requested.connect(_leave_after_error)
		_root.add_child(_conn_error)
	_root.move_child(_conn_error, -1)
	_conn_error.show_error(tr(reason_key))


func _hide_conn_error() -> void:
	if _conn_error != null:
		_conn_error.visible = false


## Retry button: the same online action again, on a fresh connection.
func _retry_connection() -> void:
	var then := _retry_then
	var addr := _retry_addr
	_hide_conn_error()
	if _mm_flow != null:
		_mm_flow.queue_free()
		_mm_flow = null
		_root.get_node("TopBar").visible = true
		_friends.visible = true
		_content.visible = true
		then = _show_matchmaking
	_with_session(then, addr)


## Back button: leave the failed online action and return to the home page.
func _leave_after_error() -> void:
	_hide_conn_error()
	if _mm_flow != null:
		_mm_flow.queue_free()
		_mm_flow = null
		_root.get_node("TopBar").visible = true
		_friends.visible = true
		_content.visible = true
	_go(Nav.HOME)
