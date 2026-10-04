class_name LauncherSettings
extends RefCounted
## The launcher's own per-user settings (separate from the shipped launcher.cfg,
## which may sit in a read-only folder). Holds the chosen install folder and
## the remembered username. It never stores a password or a session token.

const SECTION: String = "launcher"

var path: String
var install_root: String = ""
var username: String = ""


## `path_` defaults to user://launcher_settings.cfg.
func _init(path_: String = "user://launcher_settings.cfg") -> void:
	path = path_


## Loads the file if it exists. Returns self for chaining.
func load_file() -> LauncherSettings:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(path) == OK:
		install_root = String(cfg.get_value(SECTION, "install_root", ""))
		username = String(cfg.get_value(SECTION, "username", ""))
	return self


## Writes the file. Returns false on an I/O error.
func save_file() -> bool:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "install_root", install_root)
	cfg.set_value(SECTION, "username", username)
	return cfg.save(path) == OK
