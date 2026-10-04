class_name MainMenu
extends CanvasLayer
## Title screen (shown when the game starts without command-line arguments).
## It only chooses launch arguments: AppRoot turns them into a LaunchConfig and
## builds the session, exactly as if they had been typed on the command line.
##   Play vs Bots     -> --hero <id>                 (slice 3v3 vs bots)
##   Play Online      -> the official server's lobby (AppConfig.online_server)
##   Movement Course  -> --map test_course
## The hero pick is remembered in user://menu.cfg.

## Emitted with the chosen launch arguments.
signal start_requested(args: PackedStringArray)

const SETTINGS_PATH := "user://menu.cfg"
const HEROES := [["vesper_loom", "HUD_MENU_HERO_VESPER"], ["brannoc", "HUD_MENU_HERO_BRANNOC"]]
const DEFAULT_ADDRESS := "127.0.0.1:7777"

## Shown under the buttons (e.g. why the last online session ended).
var notice: String = ""

var _hero: OptionButton
var _status: Label
var _settings: SettingsPanel
var _center: CenterContainer
var _col: VBoxContainer


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

	var title := _label("CYBERGRAM", 64, HudPalette.TEXT)
	col.add_child(title)
	col.add_child(_label(tr("HUD_MENU_TAGLINE") % _version(), 16, HudPalette.TEXT_DIM))
	col.add_child(_spacer(18))

	col.add_child(_label(tr("HUD_MENU_HERO"), 14, HudPalette.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	_hero = OptionButton.new()
	for h in HEROES:
		_hero.add_item(tr(h[1]))
	_hero.custom_minimum_size.y = 40
	col.add_child(_hero)
	col.add_child(_spacer(6))

	var play := _button(tr("HUD_MENU_PLAY_BOTS"), _play, true)
	col.add_child(play)
	col.add_child(_spacer(6))
	col.add_child(_button(tr("HUD_MENU_PLAY_ONLINE"), _join, true))
	col.add_child(_spacer(6))
	col.add_child(_button(tr("HUD_MENU_TEST_COURSE"), _course))
	col.add_child(_button(tr("HUD_MENU_SETTINGS"), func() -> void:
		col.visible = false
		_settings.visible = true
		_settings.focus_first()))
	col.add_child(_button(tr("HUD_MENU_QUIT"), func() -> void: get_tree().quit()))
	_status = _label(notice, 14, HudPalette.LUMEN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	_load_settings()
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.back_pressed.connect(func() -> void:
		_settings.visible = false
		col.visible = true
		play.grab_focus())
	center.add_child(_settings)
	GameSettings.shared().apply_display()
	if AppRoot.rejoin_address != "":
		var addr := AppRoot.rejoin_address
		AppRoot.rejoin_address = ""
		_open_lobby.call_deferred(addr)  # back to the server's lobby after a match
	play.grab_focus.call_deferred()  # keyboard / gamepad navigation starts here


func _play() -> void:
	_start(PackedStringArray(["--hero", _hero_id()]))


## PLAY ONLINE: the official server from AppConfig (no address to type).
func _join() -> void:
	_open_lobby(online_server())


## The official online server (assets/data/app/app_config.tres).
static func online_server() -> String:
	var cfg := load(AppRoot.APP_CONFIG_PATH) as AppConfig
	return cfg.online_server if cfg != null and cfg.online_server != "" else DEFAULT_ADDRESS


## Online: the server's lobby (teams, hero pick, Ready) before each match.
func _open_lobby(addr: String) -> void:
	_col.visible = false
	var lobby := LobbyScreen.new()
	lobby.address = addr
	lobby.hero_id = _hero_id()
	lobby.start_requested.connect(func(args: PackedStringArray) -> void: start_requested.emit(args))
	lobby.cancelled.connect(func(reason: String) -> void:
		lobby.queue_free()
		_col.visible = true
		_status.text = reason)
	_center.add_child(lobby)


func _course() -> void:
	_start(PackedStringArray(["--map", "test_course", "--hero", _hero_id()]))


func _start(args: PackedStringArray) -> void:
	_save_settings()
	start_requested.emit(args)


func _hero_id() -> String:
	return HEROES[maxi(_hero.selected, 0)][0]


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_hero.selected = clampi(cfg.get_value("menu", "hero", 0), 0, HEROES.size() - 1)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("menu", "hero", _hero.selected)
	cfg.save(SETTINGS_PATH)


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func _label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, on_press: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 52 if primary else 44
	b.add_theme_font_size_override("font_size", 20 if primary else 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(HudPalette.NEUTRAL, 0.85) if primary else HudPalette.PANEL_STRONG
	sb.border_color = HudPalette.KEYLINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = hover.bg_color.lightened(0.15)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.pressed.connect(on_press)
	return b


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c
