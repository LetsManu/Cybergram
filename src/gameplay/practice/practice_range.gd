class_name PracticeRange
extends RefCounted
## Practice Range launch state (W10-W4). The main menu calls begin(hero_id)
## and starts the OFFLINE movement test course with the returned args; the
## PracticeRangeInstaller (a sim plugin) turns that session into the range.
## Static because no LaunchConfig flag exists for it (launch_config.gd is not
## ours); `--practice` on the command line also activates it (evidence runs).
## Reset restarts the session through AppRoot (boot_args).

const MAP := "test_course"
const FLAG := "--practice"

static var active: bool = false
static var hero_id: String = ""
static var _restart: bool = false


## Marks the next session as a practice range; returns the launch args.
static func begin(hero: String) -> PackedStringArray:
	active = true
	hero_id = hero
	return PackedStringArray(["--map", MAP, "--hero", hero])


## True when this process runs the range (menu entry or --practice).
static func is_active(cmdline: PackedStringArray = OS.get_cmdline_user_args()) -> bool:
	return active or cmdline.has(FLAG)


## Reset: reload the scene; AppRoot.boot_args() then relaunches the range.
static func request_restart(tree: SceneTree) -> void:
	_restart = true
	active = true
	tree.reload_current_scene()


## AppRoot hook: on a reset restart, the range args replace the (empty) ones.
static func boot_args(args: PackedStringArray) -> PackedStringArray:
	if not _restart:
		return args
	_restart = false
	return PackedStringArray(["--map", MAP] + (["--hero", hero_id] if hero_id != "" else []))


## Called when the range session ends for any reason but a reset.
static func end() -> void:
	if not _restart:
		active = false
