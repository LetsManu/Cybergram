extends Control
## Launcher window and command-line entry point.
##
## Flags (after `--` on the Godot command line, or directly on the exported exe):
##   --config <file>        launcher.cfg to use instead of the one next to the exe
##   --install-root <dir>   folder that holds game/ (default: next to the exe)
##   --check-only           headless: print update status, exit 0 current /
##                          10 update available / 20 offline or error
##   --update-to <dir>      headless: install root = <dir>; check, download,
##                          verify, unpack, write the version, exit 0 / 1
##   --repair               headless: verify files against the manifest, re-download
##                          if anything is bad; exit 0 intact/repaired, 1 failed
##   --move-install-to <d>  headless: move the install from --install-root to <d>
##   --self-update          headless: replace the launcher files in --launcher-dir with
##                          the feed's newer launcher; exit 0 updated / 11 current / 1 failed
##   --launcher-dir <dir>   where the launcher files live (default: next to the exe)
##   --launcher-version <v> pretend to be this launcher version (tests)
##   --self-updated         set by the restart after a self-update (skips another one)
##   --settings <file>      launcher settings file (default user://launcher_settings.cfg)
##   --no-launch            window mode: never start the game (screenshots)
##   --auto-update          window mode: start the update at once when one is offered (screenshots)
##   --show-login           window mode: open the sign-in dialog at start (screenshots)

## Width of the left sidebar (ui-kit.md: 72-88 px).
const SIDEBAR_W: int = 88
## Home news card height and how many bullet lines it summarises.
const NEWS_CARD_H: int = 160
const NEWS_BULLETS: int = 2

var _updater: Updater
var _pages: Dictionary = {}
var _nav: Dictionary = {}
var _page_title: Label
var _headline: Label
var _news_row: HBoxContainer
var _notes_box: VBoxContainer
var _notes_scroll: ScrollContainer
var _notes_cards: Array[Control] = []
var _server_dot: Control
var _chip_name: Label
var _chip_btn: Button
var _chip_ring: UiIcon
var _login_modal: Control
var _login_card: UiCard
var _guest_btn: Button
var _guest_only: bool = false
var _login_name: String = ""
var _repairing: bool = false
var _auto_update: bool = false
var _last_frac: float = -1.0
var _last_progress: String = ""
var _play_version: Label
var _status: Label
var _button: LauncherPlayButton
var _skip: Button
var _version_label: Label
var _server_label: Label
var _probe: StatusProbe
var _version_url: String = ""
var _close_on_launch: bool = true
var _no_launch: bool = false
var _headless_mode: String = ""   ## "", "check", "update" or "repair"
var _settings: LauncherSettings
var _repair_started: bool = false
var _login: LauncherLogin
var _game_server: String = "cyber.djboeck.at:7777"
var _login_box: VBoxContainer
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _login_btn: Button
var _login_status: Label
var _launcher_dir: String = ""
var _own_version: String = ""
var _self_done: bool = false
var _self: SelfUpdater
var _self_busy: bool = false
var _restart_args: PackedStringArray = PackedStringArray()
var _install_label: Label
var _repair: Button
var _dialog: FileDialog
var _confirm: ConfirmationDialog
var _pending_root: String = ""


func _ready() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args() + OS.get_cmdline_args())
	var cfg: ConfigFile = ConfigFile.new()
	var cfg_path: String = String(args.get("config", OS.get_executable_path().get_base_dir().path_join("launcher.cfg")))
	if FileAccess.file_exists(cfg_path):
		cfg.load(cfg_path)
	var url: String = String(cfg.get_value("launcher", "version_url", LauncherCore.DEFAULT_VERSION_URL))
	_close_on_launch = bool(cfg.get_value("launcher", "close_on_launch", true))
	_game_server = String(cfg.get_value("launcher", "game_server", _game_server))
	_no_launch = args.has("no-launch")
	_auto_update = args.has("auto-update")
	_settings = LauncherSettings.new(String(args.get("settings", "user://launcher_settings.cfg"))).load_file()
	var root: String = OS.get_executable_path().get_base_dir()
	if _settings.install_root != "":
		root = _settings.install_root
	root = String(args.get("install-root", root))
	if args.has("update-to"):
		root = String(args["update-to"])
		_headless_mode = "update"
	elif args.has("check-only"):
		_headless_mode = "check"
	elif args.has("repair"):
		_headless_mode = "repair"
	elif args.has("self-update"):
		_headless_mode = "selfupdate"
	_launcher_dir = String(args.get("launcher-dir", OS.get_executable_path().get_base_dir()))
	_own_version = String(args.get("launcher-version", ProjectSettings.get_setting("application/config/version", "0.0.0")))
	_self_done = args.has("self-updated") or (OS.has_feature("editor") and not args.has("launcher-dir"))
	_restart_args = OS.get_cmdline_user_args()
	SelfUpdater.cleanup_old(_launcher_dir)
	_updater = Updater.new()
	add_child(_updater)
	_updater.setup(root, url)
	if args.has("move-install-to"):
		var merr: String = _updater.move_install(String(args["move-install-to"]))
		print("LAUNCHER: move %s" % ("ok" if merr == "" else "failed: " + merr))
		get_tree().quit(0 if merr == "" else 1)
		return
	_version_url = url
	_probe = StatusProbe.new()
	add_child(_probe)
	_probe.probed.connect(_on_probed)
	_updater.manifest_loaded.connect(_on_manifest)
	_updater.state_changed.connect(_on_state)
	_updater.progress_changed.connect(_on_progress)
	if _headless_mode == "":
		_build_ui()
	_updater.check()
	if _headless_mode == "":
		_probe.probe(url)
		_login = LauncherLogin.new()
		add_child(_login)
		_login.link_ready.connect(_on_link_ready)
		_login.link_failed.connect(_on_link_failed)
		_login.login_result.connect(_on_login_result)
		_user_edit.text = _settings.username
		_login.open(_game_server)
		if args.has("show-login"):
			_open_login()


## Manifest arrived: replace the launcher first if the feed has a newer one.
func _on_manifest() -> void:
	if _self_done and _headless_mode != "selfupdate":
		return
	var entry: Dictionary = LauncherCore.launcher_update_for(_updater.latest_launcher, _updater.platform(), _own_version)
	if entry.is_empty():
		if _headless_mode == "selfupdate":
			print("LAUNCHER: self-update: launcher %s is current" % _own_version)
			get_tree().quit(11)
		return
	_self_done = true
	print("LAUNCHER: self-update %s -> %s" % [_own_version, entry["version"]])
	if _status != null:
		_status.text = "Updating the launcher to %s..." % entry["version"]
		_button.disabled = true
	_self_busy = true
	_self = SelfUpdater.new()
	add_child(_self)
	_self.setup(_launcher_dir, _launcher_dir.path_join("downloads"), LauncherCore.base_url(_version_url))
	_self.finished.connect(_on_self_updated.bind(entry))
	_self.start(entry)


func _on_self_updated(ok: bool, message: String, _new_version: String, entry: Dictionary) -> void:
	print("LAUNCHER: self-update: %s" % message)
	if _headless_mode == "selfupdate":
		get_tree().quit(0 if ok else 1)
		return
	if not ok:
		_self_busy = false
		if _status != null:
			_status.text = message
			_on_state(_updater.state, message)
		return
	var exe: String = _launcher_dir.path_join(String(entry["exe"]))
	var args: PackedStringArray = _restart_args.duplicate()
	args.append("--self-updated")
	OS.create_process(exe, args)
	get_tree().quit()


# --- login (the game then starts already signed in) ------------------------

# --- login (the game then starts already signed in) ------------------------

func _on_link_ready(secure: bool) -> void:
	_chip_btn.disabled = false
	_login_btn.disabled = false
	_user_edit.editable = secure
	_pass_edit.editable = secure
	if secure:
		_login_status.text = "Sign in so the game starts logged in, or play as a guest."
		_guest_btn.visible = true
	else:
		_set_guest_only("This server has no encrypted login yet, so passwords are never sent. You can still play as a guest.")


func _on_link_failed(message: String) -> void:
	_chip_btn.disabled = false
	_set_guest_only(message + " You can still play as a guest.")


## The server cannot take a login: the modal only offers "Play as guest".
func _set_guest_only(message: String) -> void:
	_guest_only = true
	_login_status.text = message
	_login_btn.visible = false
	_user_edit.visible = false
	_pass_edit.visible = false
	_guest_btn.visible = true
	_guest_btn.text = "PLAY AS GUEST"


func _on_guest_pressed() -> void:
	_close_login()
	if _updater.state in [Updater.State.UP_TO_DATE, Updater.State.OFFLINE_READY]:
		_play()


func _on_login_pressed() -> void:
	if _login.is_logged_in():
		_on_chip_pressed()
		return
	_login_btn.disabled = true
	_login_status.text = "Signing in..."
	var pw: String = _pass_edit.text
	_pass_edit.text = ""  # never keep the password around
	_login.login(_user_edit.text, pw)


func _on_login_result(ok: bool, message: String, display_name: String) -> void:
	_login_btn.disabled = false
	_login_status.text = message
	if ok:
		_settings.username = _user_edit.text.strip_edges()  # "remember username" (no password, no token)
		_settings.save_file()
		_login_btn.text = "Log out"
		_user_edit.editable = false
		_pass_edit.editable = false
		_login_name = display_name
		_refresh_chip()
		_close_login()


func _on_probed(info: Dictionary) -> void:
	if _server_label == null:
		return
	var t: UiKitTokens = UiKit.tokens()
	_server_label.text = LauncherCore.status_text(info)
	var c: Color = t.ok if info.get("reachable", false) else t.danger
	_server_dot.color = c
	_server_label.add_theme_color_override("font_color", t.text if info.get("reachable", false) else c)


func _parse_args(all: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	while i < all.size():
		var a: String = all[i]
		if a.begins_with("--") and a.length() > 2:
			var key: String = a.substr(2)
			if key in ["config", "install-root", "update-to", "settings", "move-install-to", "launcher-dir", "launcher-version"] and i + 1 < all.size():
				out[key] = all[i + 1]
				i += 1
			elif key in ["check-only", "no-launch", "repair", "self-update", "self-updated", "show-login", "auto-update"]:
				out[key] = true
		i += 1
	return out


# --- headless + shared state handling -------------------------------------

func _on_state(s: Updater.State, msg: String) -> void:
	if _headless_mode != "":
		_headless_state(s, msg)
		return
	if _self_busy:
		return
	var t: UiKitTokens = UiKit.tokens()
	_status.text = msg
	_status.add_theme_color_override("font_color", t.danger if s == Updater.State.ERROR else t.text_dim)
	_version_label.text = _version_text()
	_play_version.text = _version_text()
	_skip.visible = false
	var working: bool = s in [Updater.State.CHECKING, Updater.State.DOWNLOADING, Updater.State.INSTALLING, Updater.State.VERIFYING]
	_repair.disabled = working or _updater.installed_version() == "" and s != Updater.State.UPDATE_AVAILABLE
	_install_label.text = _updater.install_root()
	if not working:
		_repairing = false
	match s:
		Updater.State.CHECKING:
			_button.show_idle("CHECKING", true)
		Updater.State.UP_TO_DATE:
			_button.show_idle("PLAY")
		Updater.State.UPDATE_AVAILABLE:
			_button.show_idle("INSTALL" if _updater.installed_version() == "" else "UPDATE")
			_skip.visible = _updater.installed_version() != ""
			if _auto_update:
				_auto_update = false
				_updater.start_update()
		Updater.State.OFFLINE_READY:
			_button.show_idle("PLAY (OFFLINE)")
		Updater.State.OFFLINE_NONE:
			_button.show_idle("RETRY")
		Updater.State.DOWNLOADING, Updater.State.INSTALLING:
			_last_frac = -1.0
			_last_progress = ""
			_refresh_busy()
		Updater.State.VERIFYING:
			_button.show_busy("VERIFYING", msg, -1.0)
		Updater.State.ERROR:
			_button.show_idle("RETRY")
			_skip.visible = _updater.installed_version() != ""
	_refresh_news()


func _headless_state(s: Updater.State, msg: String) -> void:
	print("LAUNCHER: [%s] %s" % [Updater.State.keys()[s], msg])
	if _headless_mode == "selfupdate":
		if s in [Updater.State.OFFLINE_READY, Updater.State.OFFLINE_NONE, Updater.State.ERROR]:
			get_tree().quit(1)
		return  # the self-update result quits (see _on_manifest)
	if _headless_mode == "repair" and s in [Updater.State.UP_TO_DATE, Updater.State.UPDATE_AVAILABLE] and not _repair_started:
		_repair_started = true
		_updater.verify_and_repair()
		return
	match s:
		Updater.State.UP_TO_DATE:
			if _headless_mode == "repair" or _headless_mode == "check" or _updater.installed_version() == _updater.latest_version:
				print("LAUNCHER: installed=%s latest=%s" % [_updater.installed_version(), _updater.latest_version])
				get_tree().quit(0)
		Updater.State.UPDATE_AVAILABLE:
			print("LAUNCHER: installed=%s latest=%s" % [_updater.installed_version(), _updater.latest_version])
			if _headless_mode == "check":
				get_tree().quit(10)
			elif _headless_mode == "repair":
				pass
			else:
				_updater.start_update()
		Updater.State.OFFLINE_READY, Updater.State.OFFLINE_NONE:
			get_tree().quit(20 if _headless_mode == "check" else 1)
		Updater.State.ERROR:
			get_tree().quit(1)


# --- window ---------------------------------------------------------------

func _on_progress(frac: float, label: String) -> void:
	if _headless_mode != "":
		return
	_last_frac = frac
	_last_progress = label
	_refresh_busy()


## Busy PLAY button (updating / installing / repairing) from the updater state.
func _refresh_busy() -> void:
	match _updater.state:
		Updater.State.DOWNLOADING:
			var verb: String = "REPAIRING" if _repairing else ("INSTALLING" if _updater.installed_version() == "" else "UPDATING")
			var pct: String = " %d%%" % int(_last_frac * 100.0) if _last_frac >= 0.0 else ""
			_button.show_busy(verb + pct, _last_progress, _last_frac)
		Updater.State.INSTALLING:
			_button.show_busy("UNPACKING", _last_progress, 1.0)


func _on_button() -> void:
	match _updater.state:
		Updater.State.UP_TO_DATE, Updater.State.OFFLINE_READY:
			_play()
		Updater.State.UPDATE_AVAILABLE:
			_updater.start_update()
		_:
			_updater.check()
			_probe.probe(_version_url)


func _play() -> void:
	if _no_launch:
		_status.text = "(--no-launch) would start the game now"
		return
	var signed_in: bool = _login != null and _login.hand_over_env()
	var started: bool = _updater.launch_game()
	if signed_in:
		LauncherLogin.clear_env()
	if not started:
		_status.text = "Could not start the game. Try reinstalling (delete the game folder)."
		return
	if _close_on_launch:
		get_tree().quit()
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


## Player picked a folder: offer to move an existing install into it.
func _on_folder_chosen(dir: String) -> void:
	if dir.simplify_path() == _updater.install_root().simplify_path():
		return
	_pending_root = dir
	if _updater.installed_version() != "":
		_confirm.dialog_text = "Move the installed game to\n%s ?" % dir
		_confirm.popup_centered()
	else:
		_apply_root(dir, false)


func _apply_root(dir: String, move: bool) -> void:
	if move:
		var err: String = _updater.move_install(dir)
		if err != "":
			_status.text = err
			return
	else:
		_updater.setup(dir, _version_url)
	_settings.install_root = dir
	_settings.save_file()
	_updater.check()


func _version_text() -> String:
	var inst: String = _updater.installed_version()
	var s: String = "Installed %s" % (inst if inst != "" else "none")
	if _updater.latest_version != "":
		s += "   |   Latest %s" % _updater.latest_version
	return s


# --- UI (design/ux/ui-kit.md section 8.3) -----------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	add_child(UiKit.background())

	var shell: HBoxContainer = HBoxContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_constant_override("separation", 0)
	add_child(shell)
	shell.add_child(_build_sidebar())

	var main: VBoxContainer = VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	shell.add_child(main)
	main.add_child(_build_top_bar())
	var stack: Control = Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.clip_contents = true
	main.add_child(stack)
	_pages["home"] = _build_home()
	_pages["notes"] = _build_notes()
	_pages["settings"] = _build_settings()
	for key in _pages:
		var p: Control = _pages[key]
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)
	main.add_child(_build_play_panel())
	_show_page("home")

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.title = "Choose the Cybergram install folder"
	_dialog.dir_selected.connect(_on_folder_chosen)
	add_child(_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.ok_button_text = "Move install"
	_confirm.cancel_button_text = "Keep old, reinstall here"
	_confirm.confirmed.connect(func() -> void: _apply_root(_pending_root, true))
	_confirm.canceled.connect(func() -> void: _apply_root(_pending_root, false))
	add_child(_confirm)
	_build_login_modal()
	_refresh_chip()
	_refresh_news()
	_on_progress(-1.0, "")


func _build_sidebar() -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = SIDEBAR_W
	var sb: StyleBoxFlat = UiKit.panel_box(Color(t.bg_deep, 0.9), 0)
	sb.border_width_right = 1
	sb.border_color = t.line
	panel.add_theme_stylebox_override("panel", sb)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(UiKit.spacer(14))
	# Game tile (selected: violet frame, brass tick).
	var tile_row: CenterContainer = CenterContainer.new()
	col.add_child(tile_row)
	var tile: PanelContainer = PanelContainer.new()
	tile.custom_minimum_size = Vector2(52, 52)
	tile.add_theme_stylebox_override("panel", UiKit.panel_box(t.panel_raised, 6, t.accent))
	tile_row.add_child(tile)
	var logo: TextureRect = TextureRect.new()
	logo.texture = load("res://icon.svg")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tile.add_child(logo)
	col.add_child(UiKit.spacer(14))
	var group: ButtonGroup = ButtonGroup.new()
	for entry in [["HOME", "home"], ["PATCH\nNOTES", "notes"], ["SETTINGS", "settings"]]:
		var b: Button = Button.new()
		b.text = entry[0]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 52)
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_override("font", UiKit.display_font(600, 1))
		b.add_theme_font_size_override("font_size", 10)
		b.add_theme_color_override("font_color", t.text_dim)
		b.add_theme_color_override("font_hover_color", t.text)
		b.add_theme_color_override("font_pressed_color", t.accent_hi)
		b.add_theme_color_override("font_hover_pressed_color", t.accent_hi)
		var flat: StyleBoxFlat = StyleBoxFlat.new()
		flat.bg_color = Color(0, 0, 0, 0)
		var on: StyleBoxFlat = StyleBoxFlat.new()
		on.bg_color = Color(t.accent, 0.16)
		on.border_width_left = 3
		on.border_color = t.accent
		var hov: StyleBoxFlat = StyleBoxFlat.new()
		hov.bg_color = Color(t.text, 0.05)
		b.add_theme_stylebox_override("normal", flat)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_stylebox_override("focus", UiKit.focus_box())
		var page: String = entry[1]
		b.pressed.connect(func() -> void: _show_page(page))
		b.button_pressed = page == "home"
		_nav[page] = b
		col.add_child(b)
	var fill: Control = Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)
	col.add_child(UiKit.label("v" + _own_version, &"caption", t.text_off, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.spacer(8))
	return panel


func _show_page(key: String) -> void:
	for k in _pages:
		(_pages[k] as Control).visible = k == key
	if _page_title != null:
		_page_title.text = {"home": "HOME", "notes": "PATCH NOTES", "settings": "SETTINGS"}[key]
	if _nav.has(key):
		(_nav[key] as Button).button_pressed = true
	UiKit.transition_in(_pages[key], Vector2.ZERO)


func _build_top_bar() -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var bar: PanelContainer = PanelContainer.new()
	bar.custom_minimum_size.y = 56
	var sb: StyleBoxFlat = UiKit.panel_box(Color(t.bg_deep, 0.8), 0)
	sb.content_margin_left = 24
	sb.content_margin_right = 20
	sb.border_width_bottom = 1
	sb.border_color = t.line
	bar.add_theme_stylebox_override("panel", sb)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	_page_title = UiKit.label("HOME", &"nav", t.text)
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_page_title)
	# Server status badge.
	var badge: PanelContainer = PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", UiKit.panel_box(t.panel_sunken, 6, t.line))
	row.add_child(badge)
	var brow: HBoxContainer = HBoxContainer.new()
	brow.add_theme_constant_override("separation", 7)
	badge.add_child(brow)
	_server_dot = UiIcon.make(&"ring", 10, t.text_off)
	_server_dot.custom_minimum_size = Vector2(10, 10)
	_server_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brow.add_child(_server_dot)
	_server_label = UiKit.label("Checking server...", &"small", t.text_dim)
	brow.add_child(_server_label)
	# Account chip.
	var chip: HBoxContainer = HBoxContainer.new()
	chip.add_theme_constant_override("separation", 8)
	row.add_child(chip)
	_chip_ring = UiIcon.make(&"friends", 24, t.text_dim)
	chip.add_child(UiKit.avatar(_chip_ring, t.text_off, 36))
	_chip_name = UiKit.label("GUEST", &"nav", t.text)
	_chip_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(_chip_name)
	_chip_btn = UiKit.button("LOG IN", _on_chip_pressed, &"secondary", 34)
	_chip_btn.disabled = true
	chip.add_child(_chip_btn)
	return bar


func _build_home() -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var page: MarginContainer = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		page.add_theme_constant_override("margin_" + side, 14)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	page.add_child(col)
	# Key art: logo + tagline over the animated shader background.
	var brand: HBoxContainer = HBoxContainer.new()
	brand.add_theme_constant_override("separation", 16)
	col.add_child(brand)
	var logo: TextureRect = TextureRect.new()
	logo.texture = load("res://icon.svg")
	logo.custom_minimum_size = Vector2(52, 52)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.add_child(logo)
	var names: VBoxContainer = VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	brand.add_child(names)
	names.add_child(UiKit.label("CYBERGRAM", &"display"))
	names.add_child(UiKit.label("PvP first-person MOBA shooter", &"body", t.gold))
	col.add_child(UiKit.spacer(8))
	col.add_child(UiKit.label("LATEST RELEASE", &"caption", t.accent_hi))
	_headline = UiKit.label("Waiting for the update server...", &"title")
	_headline.add_theme_font_size_override("font_size", 23)
	_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline.max_lines_visible = 2
	_headline.custom_minimum_size.x = 400
	col.add_child(_headline)
	var fill: Control = Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)
	_news_row = HBoxContainer.new()
	_news_row.add_theme_constant_override("separation", 12)
	_news_row.custom_minimum_size.y = NEWS_CARD_H
	col.add_child(_news_row)
	return page


func _build_notes() -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_notes_scroll = scroll
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	_notes_box = VBoxContainer.new()
	_notes_box.add_theme_constant_override("separation", 12)
	margin.add_child(_notes_box)
	return scroll


func _build_settings() -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var margin: MarginContainer = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var inst: UiCard = UiKit.card("INSTALLATION", 16)
	col.add_child(inst)
	_install_label = UiKit.label("", &"small", t.text_dim)
	_install_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	inst.body.add_child(_install_label)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	inst.body.add_child(row)
	row.add_child(UiKit.button("INSTALL FOLDER...", func() -> void: _dialog.popup_centered(Vector2i(720, 460)), &"secondary", 38))
	_repair = UiKit.button("VERIFY / REPAIR", func() -> void:
		_repairing = true
		_updater.verify_and_repair(), &"secondary", 38)
	row.add_child(_repair)
	var about: UiCard = UiKit.card("ABOUT", 16)
	col.add_child(about)
	_version_label = UiKit.label("", &"small", t.text_dim)
	about.body.add_child(_version_label)
	about.body.add_child(UiKit.label("Launcher %s" % _own_version, &"small", t.text_off))
	return margin


## Persistent PLAY panel (bottom-left of the main area).
func _build_play_panel() -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var strip: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = UiKit.panel_box(Color(t.bg_deep, 0.88), 0)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.border_width_top = 1
	sb.border_color = t.gold
	strip.add_theme_stylebox_override("panel", sb)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	strip.add_child(row)
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size.x = 340
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)
	_status = UiKit.label("", &"small", t.text_dim)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 1
	_status.custom_minimum_size.y = 24
	_status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	left.add_child(_status)
	_button = LauncherPlayButton.new()
	_button.show_idle("CHECKING", true)
	_button.pressed.connect(_on_button)
	left.add_child(_button)
	var right: VBoxContainer = VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	_skip = UiKit.button("PLAY INSTALLED VERSION", _play, &"ghost", 32)
	_skip.visible = false
	_skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(_skip)
	_play_version = UiKit.label("", &"small", t.text_off, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_play_version)
	return strip


func _refresh_news() -> void:
	if _news_row == null:
		return
	var t: UiKitTokens = UiKit.tokens()
	for c in _news_row.get_children():
		c.queue_free()
	for c in _notes_box.get_children():
		c.queue_free()
	_notes_cards.clear()
	var md: String = _updater.latest_notes_md
	if md == "":
		_notes_box.add_child(UiKit.label("Patch notes appear here once the update server answers.", &"body", t.text_off))
		return
	var parts: Dictionary = LauncherCore.split_notes(md)
	if parts["headline"] != "":
		_headline.text = parts["headline"]
		_notes_box.add_child(UiKit.label(parts["headline"], &"title"))
	if parts["intro"] != "":
		_notes_box.add_child(_rich(parts["intro"], false))
	var shown: int = 0
	for sec in parts["sections"]:
		var card: UiCard = UiKit.card(String(sec["title"]).to_upper(), 14)
		card.body.add_child(_rich(sec["md"], true))
		_notes_box.add_child(card)
		_notes_cards.append(card)
		if shown < 3:
			_news_row.add_child(_news_card(sec, _notes_cards.size() - 1))
			shown += 1


## Home summary card: wrapped title, the first whole bullet lines, a soft fade
## and a "Read more" link that opens the Patch notes page at that section.
func _news_card(sec: Dictionary, index: int) -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var card: UiCard = UiKit.card("", 12)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, NEWS_CARD_H)
	card.clip_contents = true
	card.body.add_theme_constant_override("separation", 3)
	var title: Label = UiKit.label(String(sec["title"]).to_upper(), &"heading", t.text)
	title.add_theme_font_size_override("font_size", 14)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	card.body.add_child(title)
	var bullets: int = 0
	for raw in String(sec["md"]).split("\n"):
		var l: String = raw.strip_edges()
		if not (l.begins_with("- ") or l.begins_with("* ")):
			continue
		var b: Label = UiKit.label("\u2022 " + l.substr(2).replace("**", "").replace("`", ""), &"small", t.text_dim)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.max_lines_visible = 2
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.body.add_child(b)
		bullets += 1
		if bullets >= NEWS_BULLETS:
			break
	var fill: Control = Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.custom_minimum_size.y = 14
	card.body.add_child(fill)
	var more: Button = UiKit.button("Read more  \u2192", func() -> void: _open_note(index), &"ghost", 24)
	more.add_theme_font_size_override("font_size", 12)
	more.add_theme_color_override("font_color", t.accent_hi)
	more.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.body.add_child(more)
	# Soft fade above the link so a long summary never ends in a hard cut.
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(t.panel, 0.0))
	grad.set_color(1, Color(t.panel.r, t.panel.g, t.panel.b, 1.0))
	var gt: GradientTexture2D = GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 24
	var fade: TextureRect = TextureRect.new()
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.add_child(fade)
	return card


## Patch notes page, scrolled to section `index`.
func _open_note(index: int) -> void:
	_show_page("notes")
	await get_tree().process_frame
	await get_tree().process_frame
	if index < _notes_cards.size() and is_instance_valid(_notes_cards[index]):
		var c: Control = _notes_cards[index]
		_notes_scroll.scroll_vertical = int(c.global_position.y - _notes_box.global_position.y + 24)


func _rich(md: String, fit: bool) -> RichTextLabel:
	var t: UiKitTokens = UiKit.tokens()
	var rt: RichTextLabel = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = fit
	rt.scroll_active = false
	rt.add_theme_color_override("default_color", t.text_dim)
	rt.add_theme_font_size_override("normal_font_size", t.size_small)
	rt.add_theme_font_size_override("bold_font_size", t.size_small)
	rt.add_theme_font_size_override("bold_italics_font_size", t.size_small)
	rt.text = LauncherCore.markdown_to_bbcode(md.strip_edges())
	return rt


# --- account chip + login modal ---------------------------------------------

func _refresh_chip() -> void:
	if _chip_name == null:
		return
	var t: UiKitTokens = UiKit.tokens()
	var in_now: bool = _login != null and _login.is_logged_in()
	_chip_name.text = (_login_name if _login_name != "" else _user_edit.text).to_upper() if in_now else "GUEST"
	_chip_btn.text = "LOG OUT" if in_now else "LOG IN"
	_chip_ring.color = t.ok if in_now else t.text_dim


func _on_chip_pressed() -> void:
	if _login != null and _login.is_logged_in():
		_login.logout()
		_login_status.text = "Signed out."
		_login_btn.text = "Log in"
		_user_edit.editable = true
		_pass_edit.editable = true
		_login_name = ""
		_refresh_chip()
		return
	_open_login()


func _open_login() -> void:
	_login_modal.visible = true
	UiKit.transition_in(_login_card, Vector2.ZERO)
	(_guest_btn if _guest_only else _user_edit).grab_focus.call_deferred()


func _close_login() -> void:
	_login_modal.visible = false


func _build_login_modal() -> void:
	var t: UiKitTokens = UiKit.tokens()
	_login_modal = Control.new()
	_login_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_login_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_login_modal.visible = false
	add_child(_login_modal)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(t.bg_deep, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_login_modal.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_login_modal.add_child(center)
	_login_card = UiKit.card("SIGN IN", 20)
	_login_card.custom_minimum_size.x = 420
	center.add_child(_login_card)
	_login_card.header_right.add_child(UiKit.icon_button(&"close", _close_login, "Close", 28))
	_login_box = _login_card.body
	_login_box.add_theme_constant_override("separation", 8)
	_login_status = UiKit.label("Connecting to the game server...", &"small", t.text_dim)
	_login_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_login_box.add_child(_login_status)
	_user_edit = UiKit.line_edit("Username", 32)
	_login_box.add_child(_user_edit)
	_pass_edit = UiKit.line_edit("Password", 128)
	_pass_edit.secret = true
	_pass_edit.text_submitted.connect(func(_t: String) -> void: _on_login_pressed())
	_login_box.add_child(_pass_edit)
	_login_btn = UiKit.button("Log in", _on_login_pressed, &"primary", 42)
	_login_btn.disabled = true
	_login_box.add_child(_login_btn)
	_guest_btn = UiKit.button("PLAY AS GUEST", _on_guest_pressed, &"secondary", 42)
	_guest_btn.visible = false
	_login_box.add_child(_guest_btn)
