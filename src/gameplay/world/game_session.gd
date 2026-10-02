class_name GameSession
extends Node
## Session graph for OFFLINE and DEDICATED modes (architecture.md §2.1, ADR-0002 §3).
## OFFLINE: ServerWorld in a SubViewport(own_world_3d) + ClientWorld in the main
## world, joined by a LoopbackLink (optionally conditioned by --net-sim).
## DEDICATED (--server or --headless): ServerWorld only, as the root world.
## A SimClock driven from _physics_process (physics rate = NetConfig.tick_rate_hz)
## issues ticks; each tick runs client then server in a fixed order.

const NET_SIM_PATH := "res://assets/data/net/net_sim_%s.tres"
## `--map <name>` selects a MapDef; its scene replaces map_scene.
const MAP_DEF_PATH := "res://assets/data/match/map_%s_lane.tres"
const HERO_PATH := "res://assets/data/heroes/hero_%s.tres"
const DEFAULT_PLAYER_HERO := "res://assets/data/heroes/hero_vesper_loom.tres"
const DEFAULT_DUMMY_HEROES: Array[String] = [
	"res://assets/data/heroes/hero_brannoc.tres",
	"res://assets/data/heroes/hero_vesper_loom.tres",
]
const DEFAULT_MATCH_RULES := "res://assets/data/match/match_rules_slice.tres"
const SERVER_PEER: int = 1
const LOCAL_CLIENT_PEER: int = 2

@export var net_config: NetConfig
@export var movement: MovementDef
@export var look: LookSettings
@export var map_scene: PackedScene
@export var net_sim: NetSimProfile
## ScriptedInputDef resources, one dummy hero each (typed as Resource for .tscn compatibility).
@export var dummy_inputs: Array[Resource] = []
## Hero for the local player (null = DEFAULT_PLAYER_HERO).
@export var player_hero: HeroDef
## HeroDef per dummy, cycled (empty = DEFAULT_DUMMY_HEROES).
@export var dummy_heroes: Array[Resource] = []
## Respawn rules (null = DEFAULT_MATCH_RULES).
@export var match_rules: MatchRulesDef

## Map layout (hardpoints, E7). Set by --map; null = no objectives.
@export var map_def: MapDef

## Set by AppRoot before _ready (core LaunchConfig; duck-typed fields used).
var launch_config: LaunchConfig
var server: ServerWorld
var client: ClientWorld
var link: LoopbackLink
var clock: SimClock
var dedicated: bool = false
var _quit_after_ticks: int = 0
var _log_every_ticks: int = 0


func _ready() -> void:
	if launch_config != null:
		dedicated = launch_config.mode == LaunchConfig.Mode.DEDICATED
		_quit_after_ticks = launch_config.quit_after_ticks
		if launch_config.net_sim_name != "":
			net_sim = load(NET_SIM_PATH % launch_config.net_sim_name) as NetSimProfile
		if launch_config.map_name != "":
			var md := load(MAP_DEF_PATH % launch_config.map_name) as MapDef
			if md != null and md.scene != null:
				map_def = md
				map_scene = md.scene
		if launch_config.hero_id != "" and ResourceLoader.exists(HERO_PATH % launch_config.hero_id):
			player_hero = load(HERO_PATH % launch_config.hero_id) as HeroDef
	if player_hero == null:
		player_hero = load(DEFAULT_PLAYER_HERO) as HeroDef
	if dummy_heroes.is_empty():
		for path in DEFAULT_DUMMY_HEROES:
			dummy_heroes.append(load(path))
	if match_rules == null:
		match_rules = load(DEFAULT_MATCH_RULES) as MatchRulesDef
	Engine.physics_ticks_per_second = net_config.tick_rate_hz
	clock = SimClock.new(net_config.tick_rate_hz)
	link = LoopbackLink.new(net_sim)
	server = ServerWorld.new()
	if dedicated:
		add_child(server)
		_log_every_ticks = net_config.tick_rate_hz * 5
	else:
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.size = Vector2i(2, 2)
		add_child(vp)
		vp.add_child(server)
	server.setup(net_config, movement, map_scene, link.create_endpoint(SERVER_PEER), player_hero, match_rules)
	server.setup_objectives(map_def)
	_apply_debug_capture()
	for i in dummy_inputs.size():
		server.add_scripted_hero(ScriptedInputSource.new(dummy_inputs[i]), server.spawn_point("DummySpawn%d" % (i + 1)),
			dummy_heroes[i % dummy_heroes.size()] as HeroDef)
	if not dedicated:
		client = ClientWorld.new()
		add_child(client)
		var source: Object
		if launch_config != null and launch_config.autofire:
			source = DebugAutoAimSource.new(client)
		else:
			var input := PlayerInputSource.new()
			input.setup(look, movement)
			add_child(input)
			source = input
		client.setup(net_config, movement, look, map_scene, link.create_endpoint(LOCAL_CLIENT_PEER), source,
			player_hero)
		client.setup_objectives(map_def)


## --debug-capture <hardpoint id>: the local player spawns inside that zone and
## the hardpoint starts mid-capture for the player's team (evidence captures).
func _apply_debug_capture() -> void:
	if launch_config == null or launch_config.debug_capture == "" or server.objectives == null:
		return
	var h := server.objectives.find(StringName(launch_config.debug_capture))
	if h == null:
		return
	var toward_home := Vector3(0.0, 0.05, h.def.zone_radius * 0.5)
	server.debug_player_spawn = h.def.position + toward_home
	server.objectives.debug_set_progress(h.def.id, ServerWorld.TEAM_PLAYERS, launch_config.debug_capture_progress)


func _physics_process(delta: float) -> void:
	for i in clock.advance(delta):
		step_tick()


func _process(delta: float) -> void:
	if client != null:
		client.render(delta)


## One fixed tick of the whole session (also called directly by tests).
func step_tick() -> void:
	link.advance(net_config.tick_dt())
	if client != null:
		client.session.poll()
		client.tick()
	server.step()
	if _log_every_ticks > 0 and server.tick % _log_every_ticks == 0:
		print("[server] tick=%d entities=%d" % [server.tick, server.registry.count()])
	if _quit_after_ticks > 0 and server.tick >= _quit_after_ticks:
		print("[server] quit after %d ticks, entities=%d" % [server.tick, server.registry.count()])
		get_tree().quit()


## One-line diagnostics for the debug overlay.
func debug_text() -> String:
	var p := net_sim if net_sim != null else NetSimProfile.new()
	var t := "tick %d | net-sim %d ms +%d jitter, %.0f%% loss" % [
		server.tick, p.one_way_latency_ms, p.jitter_ms, p.loss * 100.0]
	if client != null and client.predictor != null:
		var pr := client.predictor
		t += "\nseq %d acked %d | pred err %.4f m (max %.4f) | corrections %d | remotes %d" % [
			pr.latest_seq, server.session.clients.get(LOCAL_CLIENT_PEER).inputs.last_processed_seq,
			pr.last_error_m, pr.max_error_m, pr.corrections, client.view_count()]
	var own := server.hero(client.session.own_net_id) if client != null else null
	if own != null:
		t += "\nhero %s | kills %d deaths %d" % [own.combat.def.display_name, own.combat.kills, own.combat.deaths]
	return t
