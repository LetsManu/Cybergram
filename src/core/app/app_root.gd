class_name AppRoot
extends Node
## Main scene (architecture.md §2.1): parses the command line into a
## LaunchConfig and builds the session graph from AppConfig data.

const APP_CONFIG_PATH := "res://assets/data/app/app_config.tres"


func _ready() -> void:
	var headless := DisplayServer.get_name() == "headless"
	var launch := LaunchConfig.parse(OS.get_cmdline_user_args(), headless)
	var cfg := load(APP_CONFIG_PATH) as AppConfig
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
