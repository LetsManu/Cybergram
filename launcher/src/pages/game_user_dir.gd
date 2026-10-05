class_name GameUserDir
extends RefCounted
## Where the game keeps its per-user files (settings.cfg, the hero play
## history). The game's project name is "Cybergram" and it does not use a
## custom user dir, so Godot puts them in app_userdata/Cybergram:
##   Windows: %APPDATA%/Godot/app_userdata/Cybergram
##   Linux:   $XDG_DATA_HOME or ~/.local/share/godot/app_userdata/Cybergram
## A launcher test can point at another folder with `--game-userdir`.

const APP_NAME: String = "Cybergram"


## `os_name` is OS.get_name(); the rest are the environment values.
static func resolve(os_name: String, appdata: String, xdg_data_home: String, home: String) -> String:
	match os_name:
		"Windows":
			if appdata == "":
				return ""
			return appdata.replace("\\", "/").path_join("Godot/app_userdata").path_join(APP_NAME)
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			var base: String = xdg_data_home if xdg_data_home != "" else home.path_join(".local/share")
			if base == "" or (xdg_data_home == "" and home == ""):
				return ""
			return base.path_join("godot/app_userdata").path_join(APP_NAME)
		"macOS":
			if home == "":
				return ""
			return home.path_join("Library/Application Support/Godot/app_userdata").path_join(APP_NAME)
	return ""


## The folder on this machine ("" when it cannot be worked out).
static func current(override: String = "") -> String:
	if override != "":
		return override
	return resolve(OS.get_name(), OS.get_environment("APPDATA"), OS.get_environment("XDG_DATA_HOME"), OS.get_environment("HOME"))
