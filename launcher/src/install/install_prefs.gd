class_name InstallPrefs
extends RefCounted
## Download preferences of this player (W15-UPD), kept next to the launcher
## settings file but in their own file so neither overwrites the other.

const SECTION: String = "install"
## Choices offered in Settings, in KiB/s (0 = unlimited).
const SPEED_STEPS: PackedInt32Array = [0, 1024, 2048, 5120, 10240, 25600]

var path: String
## Download speed limit in KiB/s (0 = unlimited).
var speed_limit_kib: int = 0


## `settings_path` is the launcher settings file; prefs go to <base>_install.cfg.
func _init(settings_path: String = "user://launcher_settings.cfg") -> void:
	path = settings_path.get_basename() + "_install.cfg"


func load_file() -> InstallPrefs:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		speed_limit_kib = maxi(0, int(cfg.get_value(SECTION, "speed_limit_kib", 0)))
	return self


func save_file() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "speed_limit_kib", speed_limit_kib)
	return cfg.save(path) == OK


static func speed_text(kib: int) -> String:
	return "Unlimited" if kib <= 0 else "%d MB/s" % (kib / 1024) if kib % 1024 == 0 else "%d KB/s" % kib
