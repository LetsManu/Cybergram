class_name PracticeRangeInstaller
extends Node
## Turns the OFFLINE movement-test-course session into the Practice Range
## (AppConfig.sim_plugin_scenes; W10-W4). Reuses the offline session: no new
## sim. Active only when PracticeRange.is_active(). It
##   - lets the player shop anywhere and keeps the Lumen purse full,
##   - adds static training dummies (the course already has moving ones),
##   - handles the level-up and reset keys (PracticeRangeDef),
##   - hosts the first-time tutorial overlay (offered once; F1 replays it).

const RANGE_PATH := "res://assets/data/match/practice_range.tres"
const TUTORIAL_PATH := "res://assets/data/match/tutorial_steps.tres"

## Set by AppRoot (the GameSession node).
var session: Node
var range_def: PracticeRangeDef
var overlay: TutorialOverlay
var _server: ServerWorld
var _cool: float = 0.0
var _held: Dictionary = {}
var _setup_done: bool = false


func _ready() -> void:
	if not PracticeRange.is_active():
		set_physics_process(false)
		return
	PracticeRange.active = true
	range_def = load(RANGE_PATH) as PracticeRangeDef
	_server = session.get("server") as ServerWorld if session != null else null
	if _server == null or session.get("dedicated") == true or range_def == null:
		set_physics_process(false)
		return
	if _server.progression != null:
		_server.progression.debug_shop_anywhere = true
	_add_dummies()
	var client := session.get("client") as ClientWorld
	if client != null and DisplayServer.get_name() != "headless":
		overlay = TutorialOverlay.new()
		overlay.setup(client, range_def, load(TUTORIAL_PATH) as TutorialDef)
		add_child(overlay)
		if PracticeRange.consume_tutorial() or _cmdline_has("--practice-tutorial"):
			overlay.start()  # evidence / debug: skip the offer
		elif not GameSettings.shared().tutorial_done:
			overlay.offer()
	print("[practice] range ready")


func _exit_tree() -> void:
	PracticeRange.end()


static func _cmdline_has(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


func _add_dummies() -> void:
	var spawn := _server.spawn_point(ServerWorld.PLAYER_SPAWN)
	var def := load(range_def.dummy_hero) as HeroDef
	var input := load(range_def.static_dummy_input) as ScriptedInputDef
	for off in range_def.static_dummy_offsets:
		_server.add_scripted_hero(ScriptedInputSource.new(input), spawn + off + Vector3(0.0, 0.05, 0.0), def)


func _physics_process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	var client := session.get("client") as ClientWorld
	if client == null or client.session == null:
		return
	var level_key := _edge(range_def.key_level_up, range_def.joy_level_up)
	var reset_key := _edge(range_def.key_reset, range_def.joy_reset)
	if reset_key:
		PracticeRange.request_restart(get_tree())
		return
	var h := _server.hero(client.session.own_net_id)
	if h == null or _server.progression == null:
		return
	var p := _server.progression.progress_of(h)
	if p.lumen < range_def.lumen_floor:
		p.lumen = range_def.lumen_floor
	var ui_open := client.player_input != null and client.player_input.ui_captured
	if level_key and _cool <= 0.0 and not ui_open:
		_cool = range_def.key_cooldown_s
		_server.progression.debug_set_level(h, p.level + 1)


func _edge(key: Key, joy: JoyButton) -> bool:
	var id := int(key) * 1000 + int(joy)
	var down := Input.is_physical_key_pressed(key) or Input.is_joy_button_pressed(0, joy)
	var was: bool = _held.get(id, false)
	_held[id] = down
	return down and not was
