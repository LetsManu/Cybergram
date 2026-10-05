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
const SIDEBAR_W: int = 76
## Mockup reference (design/ux/mockups/v0.9/Launcher.dc.html): 1280x720.
const REF_W: float = 1280.0
const RAIL_W: int = 76
const PLAY_BAR_H: int = 112
## Home news card height and how many bullet lines it summarises.
const NEWS_CARD_H: int = 160
const NEWS_BULLETS: int = 2

var _updater: Updater
var _pages: Dictionary = {}
var _nav: Dictionary = {}
var _page_title: Label
var _headline: Label
var _news_row: VBoxContainer
var _art: Control
var _patch_label: Label
var _blurb: Label
var _detail: Label
var _verify_link: Button
var _chip_avatar: UiPortrait
var _notes_box: VBoxContainer
var _notes_scroll: ScrollContainer
var _notes_cards: Array[Control] = []
var _server_dot: Control
var _chip_name: Label
var _chip_btn: Button
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
var _launcher_notice: String = ""
var _pending_root: String = ""
# --- W15-UPD ---
var _upd: UpdCli
# --- end W15-UPD ---


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
	if LauncherCore.is_appimage(OS.get_environment("APPIMAGE")):
		# An AppImage is read-only: keep (and update) the game in a per-user folder,
		# seeded from the copy bundled inside the image on first run.
		if _settings.install_root == "":
			root = LauncherCore.appimage_data_root(OS.get_environment("XDG_DATA_HOME"), OS.get_environment("HOME"))
		var bundle: String = OS.get_environment("APPDIR")
		if bundle != "" and not args.has("update-to"):
			var serr: String = LauncherCore.seed_bundled_game(bundle.path_join("usr/share/cybergram"), String(args.get("install-root", root)))
			if serr != "":
				print("LAUNCHER: %s" % serr)
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
	# --- W15-UPD ---
	_upd = UpdCli.attach(self, _updater, OS.get_cmdline_user_args() + OS.get_cmdline_args(),
		String(args.get("settings", "user://launcher_settings.cfg")), _headless_mode != "")
	if _upd.mode != "":
		_headless_mode = "upd"
	# --- end W15-UPD ---
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
		# --- W15-UPD ---
		_upd.after_ui(_show_page)
		# --- end W15-UPD ---


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
	if LauncherCore.is_appimage(OS.get_environment("APPIMAGE")):
		# --- W15-UPD ---
		if _upd.start_appimage_update(entry, LauncherCore.base_url(_version_url)):
			return
		# --- end W15-UPD ---
		# The AppImage is a single read-only file and the feed only carries the bare
		# launcher, so it cannot be swapped in place: tell the player instead.
		print("LAUNCHER: self-update: launcher %s is available (AppImage: download the new AppImage)" % entry["version"])
		if _headless_mode == "selfupdate":
			get_tree().quit(12)
		elif _status != null:
			_launcher_notice = "Launcher %s is available. Download the new AppImage from the Releases page." % entry["version"]
		return
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
	_server_label.text = "\u25cf  " + LauncherCore.status_text(info)
	var c: Color = t.ok if info.get("reachable", false) else t.danger
	_server_dot.color = c
	_server_label.add_theme_color_override("font_color", c)


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
	_status.add_theme_color_override("font_color", t.danger if s == Updater.State.ERROR else t.text)
	_detail.text = _detail_text(s)
	_version_label.text = _version_text()
	_play_version.text = _version_text()
	_skip.visible = false
	var working: bool = s in [Updater.State.CHECKING, Updater.State.DOWNLOADING, Updater.State.INSTALLING, Updater.State.VERIFYING]
	_repair.disabled = working or _updater.installed_version() == "" and s != Updater.State.UPDATE_AVAILABLE
	_verify_link.disabled = _repair.disabled
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
	# --- W15-UPD ---
	_repair.disabled = _repair.disabled or s == Updater.State.PAUSED
	_verify_link.disabled = _repair.disabled
	# --- end W15-UPD ---
	_refresh_news()


func _headless_state(s: Updater.State, msg: String) -> void:
	# --- W15-UPD ---
	if _upd.handles(s):
		return
	# --- end W15-UPD ---
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
			_detail.text = _last_progress
		Updater.State.INSTALLING:
			_button.show_busy("UNPACKING", _last_progress, 1.0)
			_detail.text = _last_progress


func _on_button() -> void:
	# --- W15-UPD ---
	if _upd.on_button():
		return
	# --- end W15-UPD ---
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
		s += "  \u00b7  Latest %s" % _updater.latest_version
	s += "  \u00b7  Launcher %s" % _own_version
	if _launcher_notice != "":
		s += "\n" + _launcher_notice
	return s


## Second status line (mono): what the play button will do.
func _detail_text(s: Updater.State) -> String:
	match s:
		Updater.State.UPDATE_AVAILABLE:
			return "%s \u2192 %s" % [_updater.installed_version() if _updater.installed_version() != "" else "none",
				_updater.latest_version]
		Updater.State.UP_TO_DATE, Updater.State.OFFLINE_READY:
			return ("Signed in as %s" % _chip_name.text) if _login != null and _login.is_logged_in() \
				else "Cybergram %s" % _updater.installed_version()
	return ""


# --- UI (design/ux/ui-kit.md section 8.3) -----------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	var bg: ColorRect = UiKit.background()
	# Mockup spotlight: centre (980, 360) r 280 at 1280x720 = 1.125x in the shader's 1440x810 space.
	UiKit.set_background_layout(bg, 0.0, Vector2(1102, 405), 315.0, false)
	add_child(bg)
	_art = Control.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	# Key art: three heroes on the right (mockup positions, right-anchored).
	for a in [["brannoc", 640, 120, 470, 0.55], ["sable", 960, 110, 480, 0.55], ["vesper_loom", 770, 60, 560, 1.0]]:
		var img: TextureRect = TextureRect.new()
		img.texture = UiKit.portrait_texture(String(a[0]))
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		img.modulate.a = float(a[4])
		img.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		var h: float = float(a[3])
		img.offset_left = float(a[1]) - REF_W
		img.offset_right = img.offset_left + h * 0.72
		img.offset_top = float(a[2])
		img.offset_bottom = float(a[2]) + h
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art.add_child(img)
	var stack: Control = Control.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = RAIL_W
	stack.offset_bottom = -PLAY_BAR_H
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	_pages["home"] = _build_home()
	_pages["notes"] = _build_notes()
	_pages["settings"] = _build_settings()
	for key in _pages:
		var p: Control = _pages[key]
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)
	add_child(_build_sidebar())
	add_child(_build_top_bar())
	add_child(_build_play_panel())
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


## Icon rail: the CG diamond, then HOME / NOTES / SETTINGS (icon + caption,
## a 2 px brass bar on the active one).
func _build_sidebar() -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = RAIL_W
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = t.bg_deep
	sb.border_width_right = 1
	sb.border_color = t.line
	panel.add_theme_stylebox_override("panel", sb)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(UiKit.spacer(22))
	var mark: Control = Control.new()
	mark.custom_minimum_size = Vector2(34, 34)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mark.draw.connect(func() -> void:
		var c: Vector2 = Vector2(17, 17)
		var pts: PackedVector2Array = PackedVector2Array([c + Vector2(0, -16), c + Vector2(16, 0), c + Vector2(0, 16),
			c + Vector2(-16, 0), c + Vector2(0, -16)])
		mark.draw_polyline(pts, t.accent, 1.5, true)
		var f: Font = UiKit.display_font(700, 0)
		var w: float = f.get_string_size("CG", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		mark.draw_string(f, Vector2(17 - w * 0.5, 21.5), "CG", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, t.accent_hi))
	col.add_child(mark)
	col.add_child(UiKit.spacer(18))
	var group: ButtonGroup = ButtonGroup.new()
	for entry in [["HOME", "home", &"home"], ["NOTES", "notes", &"notes"], ["SETTINGS", "settings", &"gear"]]:
		var b: Button = Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(RAIL_W, 64)
		b.focus_mode = Control.FOCUS_ALL
		b.tooltip_text = String(entry[0]).capitalize()
		var empty: StyleBoxEmpty = StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, empty)
		b.add_theme_stylebox_override("focus", UiKit.focus_box())
		var icon: UiIcon = UiIcon.make(entry[2], 20, t.text_dim)
		icon.position = Vector2((RAIL_W - 20) * 0.5, 14)
		b.add_child(icon)
		var cap: Label = Label.new()
		cap.text = entry[0]
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_size_override("font_size", 10)
		cap.add_theme_font_override("font", _tracked_body(10, 0.14))
		cap.position = Vector2(0, 38)
		cap.size = Vector2(RAIL_W, 14)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cap)
		var bar: ColorRect = ColorRect.new()
		bar.color = t.accent
		bar.position = Vector2(0, 14)
		bar.size = Vector2(2, 36)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bar)
		var paint: Callable = func() -> void:
			var on: bool = b.button_pressed
			var hot: bool = b.is_hovered() or b.has_focus()
			var c: Color = t.text if on or hot else t.text_dim
			icon.color = c
			cap.add_theme_color_override("font_color", c)
			bar.visible = on
		b.draw.connect(paint)
		b.mouse_entered.connect(paint)
		b.mouse_exited.connect(paint)
		var page: String = entry[1]
		b.pressed.connect(func() -> void: _show_page(page))
		b.button_pressed = page == "home"
		_nav[page] = b
		col.add_child(b)
	return panel


## Body font with `em` tracking at `size` px.
static func _tracked_body(size: int, em: float, weight: int = 400) -> Font:
	var f: FontVariation = UiKit.body_font(weight).duplicate() as FontVariation
	f.spacing_glyph = UiKit.track(size, em)
	return f


func _show_page(key: String) -> void:
	for k in _pages:
		(_pages[k] as Control).visible = k == key
	if _art != null:
		_art.visible = key == "home"
	if _nav.has(key):
		(_nav[key] as Button).button_pressed = true
	UiKit.transition_in(_pages[key], Vector2.ZERO)


## Top right: server status line, then the account (avatar, name, log in/out).
func _build_top_bar() -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.offset_right = -28
	row.offset_top = 18
	row.offset_left = -600
	row.offset_bottom = 58
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 22)
	_server_dot = UiIcon.make(&"ring", 8, t.text_off)  # kept for _on_probed; drawn as the bullet colour
	_server_dot.visible = false
	row.add_child(_server_dot)
	_server_label = UiKit.label("Checking server...", &"small", t.text_dim)
	_server_label.add_theme_font_size_override("font_size", 13)
	_server_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_server_label)
	var chip: HBoxContainer = HBoxContainer.new()
	chip.add_theme_constant_override("separation", 10)
	row.add_child(chip)
	_chip_avatar = UiPortrait.create(null, 32.0, t.line_strong)
	_chip_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(_chip_avatar)
	_chip_name = Label.new()
	_chip_name.text = "Guest"
	_chip_name.add_theme_font_override("font", UiKit.body_font(500))
	_chip_name.add_theme_font_size_override("font_size", 14)
	_chip_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(_chip_name)
	_chip_btn = _link("Log in", _on_chip_pressed)
	_chip_btn.disabled = true
	chip.add_child(_chip_btn)
	return row


## A quiet text link (muted, ivory on hover / focus).
func _link(text: String, cb: Callable, col: Color = Color(0, 0, 0, 0)) -> Button:
	var t: UiKitTokens = UiKit.tokens()
	var b: Button = Button.new()
	b.text = text
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	b.add_theme_stylebox_override("focus", UiKit.focus_box())
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", col if col.a > 0.0 else t.text_dim)
	b.add_theme_color_override("font_hover_color", t.accent_hi if col.a > 0.0 else t.text)
	b.add_theme_color_override("font_focus_color", t.accent_hi if col.a > 0.0 else t.text)
	b.add_theme_color_override("font_disabled_color", t.text_off)
	b.pressed.connect(cb)
	return b


## HOME: wordmark eyebrow, patch label, headline, blurb, "Read patch notes"
## and a hairline news list with mono version tags.
func _build_home() -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var page: Control = Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: VBoxContainer = VBoxContainer.new()
	col.position = Vector2(124 - RAIL_W, 104)
	col.size = Vector2(500, 0)
	col.custom_minimum_size.x = 500
	col.add_theme_constant_override("separation", 0)
	page.add_child(col)
	var mark: Label = Label.new()
	mark.text = "CYBERGRAM"
	mark.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(13, 0.32)))
	mark.add_theme_font_size_override("font_size", 13)
	mark.add_theme_color_override("font_color", t.text_dim)
	col.add_child(mark)
	col.add_child(UiKit.spacer(26))
	_patch_label = Label.new()
	_patch_label.add_theme_font_override("font", _tracked_body(12, 0.24, 600))
	_patch_label.add_theme_font_size_override("font_size", 12)
	_patch_label.add_theme_color_override("font_color", t.accent)
	col.add_child(_patch_label)
	col.add_child(UiKit.spacer(8))
	_headline = Label.new()
	_headline.text = "Waiting for the update server..."
	_headline.add_theme_font_override("font", UiKit.display_font(600, 1))
	_headline.add_theme_font_size_override("font_size", 48)
	_headline.add_theme_constant_override("line_spacing", -14)
	_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline.max_lines_visible = 2
	_headline.custom_minimum_size.x = 500
	col.add_child(_headline)
	col.add_child(UiKit.spacer(14))
	_blurb = Label.new()
	_blurb.add_theme_font_size_override("font_size", 15)
	_blurb.add_theme_constant_override("line_spacing", 8)
	_blurb.add_theme_color_override("font_color", t.text_dim)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.max_lines_visible = 2
	_blurb.custom_minimum_size.x = 440
	_blurb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_blurb)
	col.add_child(UiKit.spacer(10))
	var more: Button = _link("Read patch notes  →", func() -> void: _open_note(0), t.accent)
	more.add_theme_font_size_override("font_size", 14)
	more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(more)
	col.add_child(UiKit.spacer(28))
	_news_row = VBoxContainer.new()
	_news_row.add_theme_constant_override("separation", 0)
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
	# --- W15-UPD ---
	col.add_child(UpdPanels.create(self, _updater, _upd))
	col.move_child(about, col.get_child_count() - 1)
	# --- end W15-UPD ---
	return margin


## The play bar (bottom, right of the rail): the chamfered button that fills
## with progress, the status + mono detail lines, versions and the verify /
## play-installed links on the right.
func _build_play_panel() -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var strip: PanelContainer = PanelContainer.new()
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_left = RAIL_W
	strip.offset_top = -PLAY_BAR_H
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(t.bg_deep, 0.96)
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.border_width_top = 1
	sb.border_color = t.line
	strip.add_theme_stylebox_override("panel", sb)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	strip.add_child(row)
	_button = LauncherPlayButton.new()
	_button.custom_minimum_size = Vector2(300, 64)
	_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_button.show_idle("CHECKING", true)
	_button.pressed.connect(_on_button)
	row.add_child(_button)
	var mid: VBoxContainer = VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	row.add_child(mid)
	_status = Label.new()
	_status.add_theme_font_override("font", UiKit.body_font(500))
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", t.text)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.custom_minimum_size.x = 120
	mid.add_child(_status)
	_detail = Label.new()
	_detail.add_theme_font_override("font", UiKit.mono_font())
	_detail.add_theme_font_size_override("font_size", 12)
	_detail.add_theme_color_override("font_color", t.text_dim)
	_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(_detail)
	var right: VBoxContainer = VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 0)
	row.add_child(right)
	_play_version = Label.new()
	_play_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_play_version.add_theme_font_size_override("font_size", 12)
	_play_version.add_theme_color_override("font_color", t.text_off)
	right.add_child(_play_version)
	var links: HBoxContainer = HBoxContainer.new()
	links.alignment = BoxContainer.ALIGNMENT_END
	links.add_theme_constant_override("separation", 16)
	right.add_child(links)
	_skip = _link("Play installed version", _play)
	_skip.add_theme_font_size_override("font_size", 12)
	_skip.visible = false
	links.add_child(_skip)
	_verify_link = _link("Verify files", func() -> void:
		if not _repair.disabled:
			_repairing = true
			_updater.verify_and_repair())
	_verify_link.add_theme_font_size_override("font_size", 12)
	links.add_child(_verify_link)
	# --- W15-UPD ---
	_upd.add_play_links(links, _link, _button, _detail, _status)
	# --- end W15-UPD ---
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
	var ver: String = _updater.latest_version
	_patch_label.text = ("PATCH " + ver.get_slice(".", 0) + "." + ver.get_slice(".", 1)) if ver != "" else ""
	if md == "":
		_notes_box.add_child(UiKit.label("Patch notes appear here once the update server answers.", &"body", t.text_off))
		return
	var parts: Dictionary = LauncherCore.split_notes(md)
	if parts["headline"] != "":
		_headline.text = LauncherCore.headline_title(parts["headline"])
		# Mockup: 48 px on one line; long titles step down so the news list fits.
		_headline.add_theme_font_size_override("font_size", 48 if _headline.text.length() <= 20 else 38)
		_notes_box.add_child(UiKit.label(parts["headline"], &"title"))
	if parts["intro"] != "":
		_blurb.text = LauncherCore.plain_text(parts["intro"])
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


## A hairline news row: mono version tag, the section title and its first
## bullet; opens the Patch notes page at that section.
func _news_card(sec: Dictionary, index: int) -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var b: Button = Button.new()
	b.custom_minimum_size = Vector2(500, 62)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_top = 1
	sb.border_color = t.line
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", UiKit.focus_box())
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 14
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var tag: Label = Label.new()
	tag.text = _updater.latest_version
	tag.custom_minimum_size.x = 64
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tag.add_theme_font_override("font", UiKit.mono_font())
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", t.text_off)
	row.add_child(tag)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var title: Label = Label.new()
	title.text = String(sec["title"])
	title.add_theme_font_override("font", UiKit.body_font(500))
	title.add_theme_font_size_override("font_size", 14)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(title)
	var line: Label = Label.new()
	line.text = LauncherCore.first_bullet(String(sec["md"]))
	line.add_theme_font_size_override("font_size", 12)
	line.add_theme_color_override("font_color", t.text_dim)
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(line)
	var hot: Callable = func() -> void:
		title.add_theme_color_override("font_color", t.accent_hi if b.is_hovered() or b.has_focus() else t.text)
	b.mouse_entered.connect(hot)
	b.mouse_exited.connect(hot)
	b.focus_entered.connect(hot)
	b.focus_exited.connect(hot)
	hot.call()
	b.pressed.connect(func() -> void: _open_note(index))
	return b


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
	_chip_name.text = (_login_name if _login_name != "" else _user_edit.text) if in_now else "Guest"
	_chip_btn.text = "Log out" if in_now else "Log in"
	_chip_avatar.texture = UiKit.portrait_texture("sable") if in_now else null
	_chip_avatar.ring = t.accent if in_now else t.line_strong
	_chip_avatar.ring_width = 2.0 if in_now else 1.0


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
