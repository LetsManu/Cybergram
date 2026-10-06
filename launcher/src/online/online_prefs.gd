class_name OnlinePrefs
extends RefCounted
## The launcher's privacy choices (W15), in their own file next to the
## launcher settings (LauncherSettings rewrites its file whole, so they do
## not share one). Defaults are the privacy-friendly ones:
## - crash reports: "ask" = nothing is ever sent without a click (automatic
##   sending is OFF until the player opts in with "always");
## - Discord Rich Presence: off.

const SECTION: String = "privacy"
const CRASH_ASK: String = "ask"
const CRASH_ALWAYS: String = "always"
const CRASH_NEVER: String = "never"
const CRASH_MODES: Array[String] = [CRASH_ASK, CRASH_ALWAYS, CRASH_NEVER]

var path: String
var crash_mode: String = CRASH_ASK
var discord_presence: bool = false


## `path_` defaults to user://launcher_privacy.cfg.
func _init(path_: String = "user://launcher_privacy.cfg") -> void:
	path = path_


## Loads the file if it exists (unknown values fall back to the defaults).
func load_file() -> OnlinePrefs:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(path) == OK:
		var m: String = String(cfg.get_value(SECTION, "crash_reports", CRASH_ASK))
		crash_mode = m if m in CRASH_MODES else CRASH_ASK
		# Only a real `true` opts in: comparing a junk String to a bool is a
		# runtime error in Godot 4 (it aborted the load and returned null).
		var d: Variant = cfg.get_value(SECTION, "discord_presence", false)
		discord_presence = typeof(d) == TYPE_BOOL and d
	return self


func save_file() -> bool:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "crash_reports", crash_mode)
	cfg.set_value(SECTION, "discord_presence", discord_presence)
	return cfg.save(path) == OK


## What to do after a crash: "send", "ask" or "skip".
static func crash_action(mode: String) -> String:
	match mode:
		CRASH_ALWAYS:
			return "send"
		CRASH_NEVER:
			return "skip"
	return "ask"


## The mode after the crash prompt: `send` = the button, `keep_asking` = the
## "Always ask" box. Unticking it makes the choice permanent.
static func mode_after_prompt(send: bool, keep_asking: bool) -> String:
	if keep_asking:
		return CRASH_ASK
	return CRASH_ALWAYS if send else CRASH_NEVER
