class_name GameSettingsFile
extends RefCounted
## Reads and edits the game's own settings file (user://settings.cfg in the
## game's user folder) with the SAME keys and format as the game's
## GameSettings: [display] window_mode (0 windowed, 1 fullscreen, 2
## borderless), quality (0 low .. 3 ultra), window_w / window_h (0 = the
## game's default). Saving reads the whole file, changes only these keys and
## writes it back, so every other section (look, audio, hud, bindings) stays.

const FILE_NAME: String = "settings.cfg"
const WINDOW_MODES: Array[String] = ["Windowed", "Fullscreen", "Borderless"]
const QUALITIES: Array[String] = ["Low", "Medium", "High", "Ultra"]
## Window sizes offered (w, h); 0x0 = the game's default.
const RESOLUTIONS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1280, 720), Vector2i(1600, 900),
		Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]


## {"window_mode": int, "quality": int, "width": int, "height": int}; the
## game's defaults (windowed, High, 0x0) for anything missing.
static func read_values(path: String) -> Dictionary:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(path)  # a missing file just gives the defaults
	var legacy_fs: bool = bool(cfg.get_value("display", "fullscreen", false))
	return {
		"window_mode": clampi(int(cfg.get_value("display", "window_mode", 1 if legacy_fs else 0)), 0, 2),
		"quality": clampi(int(cfg.get_value("display", "quality", 2)), 0, 3),
		"width": maxi(0, int(cfg.get_value("display", "window_w", 0))),
		"height": maxi(0, int(cfg.get_value("display", "window_h", 0))),
	}


## Read, merge, write. Returns false on an I/O error. Unknown keys in
## `values` are ignored; an unreadable existing file is not overwritten.
static func write_values(path: String, values: Dictionary) -> bool:
	var cfg: ConfigFile = ConfigFile.new()
	if FileAccess.file_exists(path) and cfg.load(path) != OK:
		return false
	if values.has("window_mode"):
		cfg.set_value("display", "window_mode", clampi(int(values["window_mode"]), 0, 2))
	if values.has("quality"):
		cfg.set_value("display", "quality", clampi(int(values["quality"]), 0, 3))
	if values.has("width") and values.has("height"):
		cfg.set_value("display", "window_w", maxi(0, int(values["width"])))
		cfg.set_value("display", "window_h", maxi(0, int(values["height"])))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return cfg.save(path) == OK


## "Default" or "1920 x 1080".
static func resolution_text(r: Vector2i) -> String:
	return "Game default" if r.x <= 0 or r.y <= 0 else "%d x %d" % [r.x, r.y]
