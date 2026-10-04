class_name GameSettings
extends RefCounted
## Player options stored in user://settings.cfg (per machine, not game rules).
## Read once at boot; the menus edit them and call save() + apply_display().
## LookSettings values are copied onto the session's LookSettings by
## apply_look() so gameplay keeps reading its own resource.

const PATH := "user://settings.cfg"
const SENS_MIN := 0.02
const SENS_MAX := 0.5
const FOV_MIN := 70.0
const FOV_MAX := 110.0

var mouse_sensitivity_deg: float = 0.12
var invert_y: bool = false
var fov_deg: float = 90.0
## Master volume, 0..1 (linear).
var master_volume: float = 0.8
var fullscreen: bool = false

static var _shared: GameSettings


## The process-wide settings (loaded from disk on first use).
static func shared() -> GameSettings:
	if _shared == null:
		_shared = GameSettings.new()
		_shared.load_from_disk()
	return _shared


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sensitivity_deg = clampf(cfg.get_value("look", "sensitivity_deg", mouse_sensitivity_deg), SENS_MIN, SENS_MAX)
	invert_y = cfg.get_value("look", "invert_y", invert_y)
	fov_deg = clampf(cfg.get_value("look", "fov_deg", fov_deg), FOV_MIN, FOV_MAX)
	master_volume = clampf(cfg.get_value("audio", "master", master_volume), 0.0, 1.0)
	fullscreen = cfg.get_value("display", "fullscreen", fullscreen)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("look", "sensitivity_deg", mouse_sensitivity_deg)
	cfg.set_value("look", "invert_y", invert_y)
	cfg.set_value("look", "fov_deg", fov_deg)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(PATH)


## Copies the look options onto `look` (a LookSettings, duck-typed: core
## does not name gameplay classes).
func apply_look(look: Resource) -> void:
	if look == null:
		return
	look.set("mouse_sensitivity_deg", mouse_sensitivity_deg)
	look.set("invert_y", invert_y)
	look.set("fov_deg", fov_deg)


## Volume and window mode (no-op headless).
func apply_display() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
