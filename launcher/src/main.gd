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

const ACCENT: Color = Color("2fd6ff")
const PINK: Color = Color("ff4fa3")
const BG: Color = Color("0b1018")
const PANEL: Color = Color("121a26")

var _updater: Updater
var _news: RichTextLabel
var _status: Label
var _bar: ProgressBar
var _bar_label: Label
var _button: Button
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
	_no_launch = args.has("no-launch")
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


func _on_probed(info: Dictionary) -> void:
	if _server_label == null:
		return
	_server_label.text = "● " + LauncherCore.status_text(info)
	_server_label.add_theme_color_override("font_color",
		Color("3ddc84") if info.get("reachable", false) else Color("ff5470"))


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
			elif key in ["check-only", "no-launch", "repair", "self-update", "self-updated"]:
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
	_status.text = msg
	_version_label.text = _version_text()
	_skip.visible = false
	_repair.disabled = s in [Updater.State.CHECKING, Updater.State.DOWNLOADING, Updater.State.INSTALLING, Updater.State.VERIFYING] \
		or _updater.installed_version() == "" and s != Updater.State.UPDATE_AVAILABLE
	_install_label.text = "Install folder: " + _updater.install_root()
	_bar.visible = s == Updater.State.DOWNLOADING or s == Updater.State.INSTALLING
	_bar_label.visible = _bar.visible
	_button.disabled = false
	match s:
		Updater.State.CHECKING:
			_button.text = "CHECKING..."
			_button.disabled = true
		Updater.State.UP_TO_DATE:
			_button.text = "PLAY"
		Updater.State.UPDATE_AVAILABLE:
			_button.text = "INSTALL" if _updater.installed_version() == "" else "UPDATE"
			_skip.visible = _updater.installed_version() != ""
		Updater.State.OFFLINE_READY:
			_button.text = "PLAY (OFFLINE)"
		Updater.State.OFFLINE_NONE:
			_button.text = "RETRY"
		Updater.State.DOWNLOADING, Updater.State.INSTALLING:
			_button.text = "UPDATING..."
			_button.disabled = true
		Updater.State.VERIFYING:
			_button.text = "VERIFYING..."
			_button.disabled = true
		Updater.State.ERROR:
			_button.text = "RETRY"
			_skip.visible = _updater.installed_version() != ""
	if _updater.latest_notes_md != "":
		_news.text = LauncherCore.markdown_to_bbcode(_updater.latest_notes_md)


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
	_bar.indeterminate = frac < 0.0
	_bar.value = maxf(frac, 0.0) * 100.0
	_bar_label.text = label


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
	if not _updater.launch_game():
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
	var s: String = "Installed: %s" % (inst if inst != "" else "none")
	if _updater.latest_version != "":
		s += "    Latest: %s" % _updater.latest_version
	return s


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	# Header: logo + title.
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var logo: TextureRect = TextureRect.new()
	logo.texture = load("res://icon.svg")
	logo.custom_minimum_size = Vector2(64, 64)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(logo)
	var titles: VBoxContainer = VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(titles)
	var title: Label = Label.new()
	title.text = "CYBERGRAM"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", ACCENT)
	titles.add_child(title)
	var sub: Label = Label.new()
	sub.text = "PvP first-person MOBA shooter"
	sub.add_theme_color_override("font_color", Color("8a97a8"))
	titles.add_child(sub)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_server_label = Label.new()
	_server_label.text = "● Checking server..."
	_server_label.add_theme_color_override("font_color", Color("8a97a8"))
	_server_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_server_label)

	# Body: news (left) + action panel (right).
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)

	var news_panel: PanelContainer = PanelContainer.new()
	news_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	news_panel.add_theme_stylebox_override("panel", _box(PANEL, 14))
	body.add_child(news_panel)
	var news_box: VBoxContainer = VBoxContainer.new()
	news_panel.add_child(news_box)
	var news_title: Label = Label.new()
	news_title.text = "NEWS AND PATCH NOTES"
	news_title.add_theme_color_override("font_color", PINK)
	news_box.add_child(news_title)
	_news = RichTextLabel.new()
	_news.bbcode_enabled = true
	_news.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_news.text = "[color=#8a97a8]Patch notes appear here once the update server answers.[/color]"
	news_box.add_child(_news)

	var side: PanelContainer = PanelContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	side.add_theme_stylebox_override("panel", _box(PANEL, 18))
	body.add_child(side)
	var sv: VBoxContainer = VBoxContainer.new()
	sv.add_theme_constant_override("separation", 12)
	sv.alignment = BoxContainer.ALIGNMENT_END
	side.add_child(sv)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	sv.add_child(_status)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("fill", _box(ACCENT, 0, 4))
	_bar.add_theme_stylebox_override("background", _box(Color("1e2a3a"), 0, 4))
	_bar.visible = false
	sv.add_child(_bar)
	_bar_label = Label.new()
	_bar_label.add_theme_color_override("font_color", Color("8a97a8"))
	_bar_label.visible = false
	sv.add_child(_bar_label)

	_button = Button.new()
	_button.custom_minimum_size = Vector2(0, 76)
	_button.add_theme_font_size_override("font_size", 28)
	_button.add_theme_color_override("font_color", BG)
	_button.add_theme_color_override("font_hover_color", BG)
	_button.add_theme_color_override("font_pressed_color", BG)
	_button.add_theme_color_override("font_disabled_color", Color("5b6676"))
	_button.add_theme_stylebox_override("normal", _box(ACCENT, 0, 6))
	_button.add_theme_stylebox_override("hover", _box(Color("6fe4ff"), 0, 6))
	_button.add_theme_stylebox_override("pressed", _box(Color("1fa6c8"), 0, 6))
	_button.add_theme_stylebox_override("disabled", _box(Color("1e2a3a"), 0, 6))
	_button.text = "CHECKING..."
	_button.disabled = true
	_button.pressed.connect(_on_button)
	sv.add_child(_button)

	_skip = Button.new()
	_skip.text = "Play installed version without updating"
	_skip.flat = true
	_skip.visible = false
	_skip.pressed.connect(_play)
	sv.add_child(_skip)

	_repair = Button.new()
	_repair.text = "Verify / repair files"
	_repair.flat = true
	_repair.pressed.connect(func() -> void: _updater.verify_and_repair())
	sv.add_child(_repair)

	_install_label = Label.new()
	_install_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_install_label.add_theme_font_size_override("font_size", 12)
	_install_label.add_theme_color_override("font_color", Color("5b6676"))
	_install_label.text = "Install folder: " + _updater.install_root()
	sv.add_child(_install_label)
	var change: Button = Button.new()
	change.text = "Change install folder..."
	change.flat = true
	change.pressed.connect(func() -> void: _dialog.popup_centered(Vector2i(720, 460)))
	sv.add_child(change)

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

	_version_label = Label.new()
	_version_label.add_theme_color_override("font_color", Color("5b6676"))
	_version_label.text = _version_text()
	root.add_child(_version_label)


func _box(color: Color, pad: int, radius: int = 8) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb
