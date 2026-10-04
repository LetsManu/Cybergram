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
var _close_on_launch: bool = true
var _no_launch: bool = false
var _headless_mode: String = ""   ## "", "check" or "update"


func _ready() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args() + OS.get_cmdline_args())
	var cfg: ConfigFile = ConfigFile.new()
	var cfg_path: String = String(args.get("config", OS.get_executable_path().get_base_dir().path_join("launcher.cfg")))
	if FileAccess.file_exists(cfg_path):
		cfg.load(cfg_path)
	var url: String = String(cfg.get_value("launcher", "version_url", LauncherCore.DEFAULT_VERSION_URL))
	_close_on_launch = bool(cfg.get_value("launcher", "close_on_launch", true))
	_no_launch = args.has("no-launch")
	var root: String = String(args.get("install-root", OS.get_executable_path().get_base_dir()))
	if args.has("update-to"):
		root = String(args["update-to"])
		_headless_mode = "update"
	elif args.has("check-only"):
		_headless_mode = "check"
	_updater = Updater.new()
	add_child(_updater)
	_updater.setup(root, url)
	_updater.state_changed.connect(_on_state)
	_updater.progress_changed.connect(_on_progress)
	if _headless_mode == "":
		_build_ui()
	_updater.check()


func _parse_args(all: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	while i < all.size():
		var a: String = all[i]
		if a.begins_with("--") and a.length() > 2:
			var key: String = a.substr(2)
			if key in ["config", "install-root", "update-to"] and i + 1 < all.size():
				out[key] = all[i + 1]
				i += 1
			elif key in ["check-only", "no-launch"]:
				out[key] = true
		i += 1
	return out


# --- headless + shared state handling -------------------------------------

func _on_state(s: Updater.State, msg: String) -> void:
	if _headless_mode != "":
		_headless_state(s, msg)
		return
	_status.text = msg
	_version_label.text = _version_text()
	_skip.visible = false
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
		Updater.State.ERROR:
			_button.text = "RETRY"
			_skip.visible = _updater.installed_version() != ""
	if _updater.latest_notes_md != "":
		_news.text = LauncherCore.markdown_to_bbcode(_updater.latest_notes_md)


func _headless_state(s: Updater.State, msg: String) -> void:
	print("LAUNCHER: [%s] %s" % [Updater.State.keys()[s], msg])
	match s:
		Updater.State.UP_TO_DATE:
			if _headless_mode == "check" or _updater.installed_version() == _updater.latest_version:
				print("LAUNCHER: installed=%s latest=%s" % [_updater.installed_version(), _updater.latest_version])
				get_tree().quit(0)
		Updater.State.UPDATE_AVAILABLE:
			print("LAUNCHER: installed=%s latest=%s" % [_updater.installed_version(), _updater.latest_version])
			if _headless_mode == "check":
				get_tree().quit(10)
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
