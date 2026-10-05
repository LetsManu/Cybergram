class_name AppRoot
extends Node
## Main scene (architecture.md §2.1): parses the command line into a
## LaunchConfig and builds the session graph from AppConfig data.

const APP_CONFIG_PATH := "res://assets/data/app/app_config.tres"


## Set by a session that ends itself (e.g. an online connection failed): the
## next AppRoot shows the menu with this message instead of re-launching.
static var menu_notice: String = ""
static var return_to_menu: bool = false
## After an online match: the menu reopens the lobby of this server.
static var rejoin_address: String = ""
## Testing (--auto-ready): the lobby screen presses Ready by itself.
static var auto_ready: bool = false


func _ready() -> void:
	ContentPacks.mount_once()  # W15-UPD: optional .pck packs before anything loads
	var headless := DisplayServer.get_name() == "headless"
	var cfg := load(APP_CONFIG_PATH) as AppConfig
	var args := PracticeRange.boot_args(OS.get_cmdline_user_args())
	var parsed := LaunchConfig.parse(args, headless)
	var lobby_addr := parsed.open_lobby
	auto_ready = auto_ready or parsed.auto_ready
	if lobby_addr != "" and not return_to_menu:
		rejoin_address = lobby_addr
	if (args.is_empty() or return_to_menu or lobby_addr != "") and not headless and cfg.menu_scene != null:
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


## Ends an online match and returns to that server's lobby.
static func rejoin_lobby(tree: SceneTree, address: String) -> void:
	rejoin_address = address
	back_to_menu(tree, "")


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
	if session.get("match_pending"):
		# Online lobby: the match (and its AI plugins) is built later.
		session.connect("match_built", func() -> void: _add_plugins(cfg, session))
	else:
		_add_plugins(cfg, session)
	if launch.mode == LaunchConfig.Mode.DEDICATED or launch.mm_script != "":
		return  # W17B: the scripted matchmaking client is headless, no overlays
	for scene in cfg.overlay_scenes:
		var overlay := scene.instantiate()
		overlay.set("session", session)
		add_child(overlay)


func _add_plugins(cfg: AppConfig, session: Node) -> void:
	for scene in cfg.sim_plugin_scenes:
		var plugin := scene.instantiate()
		plugin.set("session", session)
		add_child(plugin)
