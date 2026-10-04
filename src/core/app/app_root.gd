class_name AppRoot
extends Node
## Main scene (architecture.md §2.1): parses the command line into a
## LaunchConfig and builds the session graph from AppConfig data.

const APP_CONFIG_PATH := "res://assets/data/app/app_config.tres"


## Set by a session that ends itself (e.g. an online connection failed): the
## next AppRoot shows the menu with this message instead of re-launching.
static var menu_notice: String = ""
static var return_to_menu: bool = false


func _ready() -> void:
	var headless := DisplayServer.get_name() == "headless"
	var cfg := load(APP_CONFIG_PATH) as AppConfig
	var args := OS.get_cmdline_user_args()
	if (args.is_empty() or return_to_menu) and not headless and cfg.menu_scene != null:
		return_to_menu = false
		var menu := cfg.menu_scene.instantiate()
		menu.set("notice", menu_notice)
		menu_notice = ""
		menu.connect("start_requested", func(chosen: PackedStringArray) -> void:
			menu.queue_free()
			_start(cfg, chosen, headless))
		add_child(menu)
		return
	_start(cfg, args, headless)


## Ends the running session and shows the menu with `notice`.
static func back_to_menu(tree: SceneTree, notice: String) -> void:
	menu_notice = notice
	return_to_menu = true
	tree.reload_current_scene()


func _start(cfg: AppConfig, args: PackedStringArray, headless: bool) -> void:
	var launch := LaunchConfig.parse(args, headless)
	var session := cfg.session_scene.instantiate()
	session.set("launch_config", launch)
	add_child(session)
	for scene in cfg.sim_plugin_scenes:
		var plugin := scene.instantiate()
		plugin.set("session", session)
		add_child(plugin)
	if launch.mode == LaunchConfig.Mode.DEDICATED:
		return
	for scene in cfg.overlay_scenes:
		var overlay := scene.instantiate()
		overlay.set("session", session)
		add_child(overlay)
