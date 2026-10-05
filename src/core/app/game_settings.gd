class_name GameSettings
extends RefCounted
## Player options stored in user://settings.cfg (per machine, not game rules).
## Read once at boot; the menus edit them and call save() + apply_display().
## LookSettings values are copied onto the session's LookSettings by
## apply_look() so gameplay keeps reading its own resource. Key bindings live
## in `bindings` (InputBindings) and are applied to the InputMap at boot.
## HUD options (UI scale, colour-blind preset, damage numbers) stay in
## HudSettings' [hud] section of the same file; save() keeps foreign sections.

const PATH := "user://settings.cfg"
const SENS_MIN := 0.02
const SENS_MAX := 0.5
const FOV_MIN := 70.0
const FOV_MAX := 110.0
const PAD_SENS_MIN := 30.0
const PAD_SENS_MAX := 540.0
const PAD_DEADZONE_MIN := 0.0
const PAD_DEADZONE_MAX := 0.5
const PAD_CURVE_MIN := 1.0
const PAD_CURVE_MAX := 3.0
const RENDER_SCALE_MIN := 0.5
const RENDER_SCALE_MAX := 1.0

enum WindowMode { WINDOWED, FULLSCREEN, BORDERLESS }
## Graphics quality preset (read by the graphics code: chunk G1).
enum Quality { LOW, MEDIUM, HIGH, ULTRA }
## FPS cap choices; 0 = unlimited.
const FPS_CAPS: Array[int] = [30, 60, 120, 144, 240, 0]
## Crosshair looks and colours (CenterFeedback draws from these).
enum Crosshair { CROSS_DOT, CROSS, DOT, CIRCLE }
const CROSSHAIR_COLORS: Array[Color] = [Color.WHITE, Color("#4CE38A"), Color("#00E5FF"),
	Color("#FFD447"), Color("#FF4FD8"), Color("#FF4A3D")]
const BUS_EFFECTS := &"Effects"
const BUS_UI := &"UI"

var mouse_sensitivity_deg: float = 0.12
var invert_y: bool = false
var fov_deg: float = 90.0
## Gamepad look (W11-C1): right-stick rate at full tilt (deg/s), radial dead
## zone, response-curve exponent, invert Y, and the aim-assist toggle.
var pad_sensitivity_deg_s: float = 180.0
var pad_deadzone: float = 0.15
var pad_curve: float = 1.6
var pad_invert_y: bool = false
var aim_assist: bool = true
## Master volume, 0..1 (linear). Effects and UI buses sit below Master.
var master_volume: float = 0.8
var effects_volume: float = 1.0
var ui_volume: float = 1.0
## WindowMode.
var window_mode: int = WindowMode.WINDOWED
## 3D render resolution scale, 0.5..1.0.
var render_scale: float = 1.0
var vsync: bool = true
## Index into FPS_CAPS (default: unlimited, the last entry).
var fps_cap_index: int = 5
## Quality preset 0..3 (Quality), default High. Chunk G1 reads this field.
var graphics_quality: int = Quality.HIGH
## Crosshair style (Crosshair) and colour index (CROSSHAIR_COLORS).
var crosshair_style: int = Crosshair.CROSS_DOT
var crosshair_color: int = 0
## Key bindings (applied to the InputMap by apply_bindings()).
var bindings: InputBindings = InputBindings.new()
## W10-W4: the first-time Practice Range tutorial was finished or skipped.
var tutorial_done: bool = false

static var _shared: GameSettings
## Bumped when the Gameplay tab rewrites the [hud] section, so a running HUD
## knows to re-read it.
static var hud_revision: int = 0


## The process-wide settings (loaded from disk on first use; the key bindings
## are applied to the InputMap right then, i.e. at boot).
static func shared() -> GameSettings:
	if _shared == null:
		_shared = GameSettings.new()
		_shared.load_from_disk()
		_shared.apply_bindings()
	return _shared


## True for fullscreen or borderless (legacy accessor).
var fullscreen: bool:
	get:
		return window_mode != WindowMode.WINDOWED
	set(v):
		window_mode = WindowMode.FULLSCREEN if v else WindowMode.WINDOWED


func load_from_disk(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	read_config(cfg)


## Writes the file; sections owned by others (e.g. [hud]) are kept.
func save(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file is fine
	write_config(cfg)
	cfg.save(path)


## Reads every section; missing or invalid values keep their defaults.
func read_config(cfg: ConfigFile) -> void:
	mouse_sensitivity_deg = clampf(cfg.get_value("look", "sensitivity_deg", mouse_sensitivity_deg), SENS_MIN, SENS_MAX)
	invert_y = cfg.get_value("look", "invert_y", invert_y)
	fov_deg = clampf(cfg.get_value("look", "fov_deg", fov_deg), FOV_MIN, FOV_MAX)
	pad_sensitivity_deg_s = clampf(cfg.get_value("gamepad", "sensitivity_deg_s", pad_sensitivity_deg_s), PAD_SENS_MIN, PAD_SENS_MAX)
	pad_deadzone = clampf(cfg.get_value("gamepad", "deadzone", pad_deadzone), PAD_DEADZONE_MIN, PAD_DEADZONE_MAX)
	pad_curve = clampf(cfg.get_value("gamepad", "curve", pad_curve), PAD_CURVE_MIN, PAD_CURVE_MAX)
	pad_invert_y = bool(cfg.get_value("gamepad", "invert_y", pad_invert_y))
	aim_assist = bool(cfg.get_value("gamepad", "aim_assist", aim_assist))
	master_volume = clampf(cfg.get_value("audio", "master", master_volume), 0.0, 1.0)
	effects_volume = clampf(cfg.get_value("audio", "effects", effects_volume), 0.0, 1.0)
	ui_volume = clampf(cfg.get_value("audio", "ui", ui_volume), 0.0, 1.0)
	var legacy_fs: bool = cfg.get_value("display", "fullscreen", false)
	window_mode = clampi(int(cfg.get_value("display", "window_mode",
		WindowMode.FULLSCREEN if legacy_fs else WindowMode.WINDOWED)), 0, WindowMode.BORDERLESS)
	render_scale = clampf(cfg.get_value("display", "render_scale", render_scale), RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	vsync = cfg.get_value("display", "vsync", vsync)
	fps_cap_index = clampi(int(cfg.get_value("display", "fps_cap_index", fps_cap_index)), 0, FPS_CAPS.size() - 1)
	graphics_quality = clampi(int(cfg.get_value("display", "quality", graphics_quality)), Quality.LOW, Quality.ULTRA)
	tutorial_done = bool(cfg.get_value("tutorial", "done", tutorial_done))
	crosshair_style = clampi(int(cfg.get_value("crosshair", "style", crosshair_style)), 0, Crosshair.CIRCLE)
	crosshair_color = clampi(int(cfg.get_value("crosshair", "color", crosshair_color)), 0, CROSSHAIR_COLORS.size() - 1)
	bindings.read_config(cfg)


func write_config(cfg: ConfigFile) -> void:
	cfg.set_value("tutorial", "done", tutorial_done)
	cfg.set_value("look", "sensitivity_deg", mouse_sensitivity_deg)
	cfg.set_value("look", "invert_y", invert_y)
	cfg.set_value("look", "fov_deg", fov_deg)
	cfg.set_value("gamepad", "sensitivity_deg_s", pad_sensitivity_deg_s)
	cfg.set_value("gamepad", "deadzone", pad_deadzone)
	cfg.set_value("gamepad", "curve", pad_curve)
	cfg.set_value("gamepad", "invert_y", pad_invert_y)
	cfg.set_value("gamepad", "aim_assist", aim_assist)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "effects", effects_volume)
	cfg.set_value("audio", "ui", ui_volume)
	cfg.set_value("display", "window_mode", window_mode)
	cfg.set_value("display", "render_scale", render_scale)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "fps_cap_index", fps_cap_index)
	cfg.set_value("display", "quality", graphics_quality)
	cfg.set_value("crosshair", "style", crosshair_style)
	cfg.set_value("crosshair", "color", crosshair_color)
	bindings.write_config(cfg)


## Copies the look options onto `look` (a LookSettings, duck-typed: core
## does not name gameplay classes).
func apply_look(look: Resource) -> void:
	if look == null:
		return
	look.set("mouse_sensitivity_deg", mouse_sensitivity_deg)
	look.set("invert_y", invert_y)
	look.set("fov_deg", fov_deg)
	look.set("pad_sensitivity_deg_s", pad_sensitivity_deg_s)
	look.set("pad_deadzone", pad_deadzone)
	look.set("pad_curve", pad_curve)
	look.set("pad_invert_y", pad_invert_y)
	look.set("aim_assist", aim_assist)


## Pushes the key bindings into the InputMap.
func apply_bindings() -> void:
	bindings.apply_to_input_map()


## Creates the Effects and UI buses (children of Master) when missing.
## Returns the number of buses created.
static func ensure_buses() -> int:
	var made := 0
	for bus_name in [BUS_EFFECTS, BUS_UI]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")
			made += 1
	return made


## Sets the volume of bus `bus_name` from a linear 0..1 value.
static func set_bus_linear(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


## Master / Effects / UI bus volumes (creates the buses when missing).
func apply_audio() -> void:
	ensure_buses()
	set_bus_linear(&"Master", master_volume)
	set_bus_linear(BUS_EFFECTS, effects_volume)
	set_bus_linear(BUS_UI, ui_volume)


## Volume, window mode, render scale, VSync and FPS cap (window parts are a
## no-op headless).
func apply_display() -> void:
	apply_audio()
	Engine.max_fps = FPS_CAPS[fps_cap_index]
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.scaling_3d_scale = render_scale
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var want := DisplayServer.WINDOW_MODE_WINDOWED
	var borderless := false
	match window_mode:
		WindowMode.FULLSCREEN:
			want = DisplayServer.WINDOW_MODE_FULLSCREEN
		WindowMode.BORDERLESS:
			want = DisplayServer.WINDOW_MODE_WINDOWED
			borderless = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, borderless)
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	if borderless:
		DisplayServer.window_set_size(DisplayServer.screen_get_size())
		DisplayServer.window_set_position(DisplayServer.screen_get_position())
