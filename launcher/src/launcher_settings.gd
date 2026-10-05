class_name LauncherSettings
extends RefCounted
## The launcher's own per-user settings (separate from the shipped launcher.cfg,
## which may sit in a read-only folder). Holds the chosen install folder and
## the remembered username. It never stores a password or a session token.

const SECTION: String = "launcher"

var path: String
var install_root: String = ""
var username: String = ""
## W15-UX: hero pinned as "my main" for the patch notes ("" = use play history).
var pinned_hero: String = ""
## W15-UX: what the launcher does when the game starts: "stay", "minimise" or "close".
var on_launch: String = "stay"
## W15-UX: the first-run system check has been shown.
var syscheck_done: bool = false


## `path_` defaults to user://launcher_settings.cfg.
func _init(path_: String = "user://launcher_settings.cfg") -> void:
	path = path_


## Loads the file if it exists. Returns self for chaining.
func load_file() -> LauncherSettings:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(path) == OK:
		install_root = String(cfg.get_value(SECTION, "install_root", ""))
		username = String(cfg.get_value(SECTION, "username", ""))
		pinned_hero = String(cfg.get_value(SECTION, "pinned_hero", ""))
		on_launch = String(cfg.get_value(SECTION, "on_launch", "stay"))
		if not on_launch in ["stay", "minimise", "close"]:
			on_launch = "stay"
		syscheck_done = bool(cfg.get_value(SECTION, "syscheck_done", false))
	return self


## Writes the file. Returns false on an I/O error.
func save_file() -> bool:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "install_root", install_root)
	cfg.set_value(SECTION, "username", username)
	cfg.set_value(SECTION, "pinned_hero", pinned_hero)
	cfg.set_value(SECTION, "on_launch", on_launch)
	cfg.set_value(SECTION, "syscheck_done", syscheck_done)
	return cfg.save(path) == OK
