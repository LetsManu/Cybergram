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
## E8 Wardling data (squads + Vanguard on maps with HQs).
const WARDLING_RULES := "res://assets/data/wardlings/wardling_rules_slice.tres"
const WARDLING_PICKET := "res://assets/data/wardlings/wardling_picket.tres"
## E13/E15 economy rules and the Armory catalog (slice subset).
const ECONOMY_RULES := "res://assets/data/economy/economy_rules_slice.tres"
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
	_setup_match()
	_apply_debug_capture()
	if launch_config != null:
		# E10 debug; with the E15 tree on, the scripted skill demo needs every skill usable.
		server.abilities.grant_ult = launch_config.grant_ult or launch_config.debug_skill_demo
	var wardling_rules := load(WARDLING_RULES) as WardlingRulesDef
	if server.enable_wardlings(map_def, wardling_rules, load(WARDLING_PICKET) as WardlingDef) != null \
			and launch_config != null:
		# The Vanguard cadence follows the match clock unless --wave-clock overrides it.
		server.wardlings.clock_scale = launch_config.wave_clock if launch_config.wave_clock != 1.0 \
			else launch_config.match_clock
		if launch_config.spawn_wardlings > 0:
			server.wardlings.debug_spawn(launch_config.spawn_wardlings)
	server.enable_progression(load(ECONOMY_RULES) as EconomyRulesDef,
		load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef, map_def)  # E13/E15
	if launch_config != null and launch_config.debug_armory and map_def != null and not map_def.hqs.is_empty():
		server.debug_player_spawn = map_def.hq(ServerWorld.TEAM_PLAYERS).armory + Vector3(0.0, 0.05, 1.5)
	# E11: bot matches fill the slots from src/ai (BotAiInstaller); no training dummies.
	var bot_match := launch_config != null and (launch_config.bots or launch_config.bots_only)
	for i in dummy_inputs.size() if not bot_match else 0:
		server.add_scripted_hero(ScriptedInputSource.new(dummy_inputs[i]), server.spawn_point("DummySpawn%d" % (i + 1)),
			dummy_heroes[i % dummy_heroes.size()] as HeroDef)
	if not dedicated:
		client = ClientWorld.new()
		add_child(client)
		var source: Object
		if launch_config != null and launch_config.debug_uplink:
			source = DebugUplinkSiegeSource.new(client)
		elif launch_config != null and launch_config.autofire:
			source = DebugAutoAimSource.new(client)
		elif launch_config != null and launch_config.debug_skill_demo:
			source = DebugSkillDemoSource.new(client)
		elif launch_config != null and launch_config.debug_squad_demo:
			source = DebugSquadDemoSource.new(client)
		else:
			var input := PlayerInputSource.new()
			input.setup(look, movement)
			add_child(input)
			source = input
		client.setup(net_config, movement, look, map_scene, link.create_endpoint(LOCAL_CLIENT_PEER), source,
			player_hero)
		client.setup_objectives(map_def)
		if wardling_rules != null:
			client.wardlings.rules = wardling_rules
		if launch_config != null:
			client.wardlings.debug_camera = launch_config.debug_camera


## E9: match flow (phases, clock, Uplinks) on maps with hardpoints and HQs.
func _setup_match() -> void:
	if map_def == null or server.objectives == null or map_def.hqs.is_empty():
		return
	var lc := launch_config
	var m := server.setup_match(map_def, lc.match_clock if lc != null else 1.0)
	if lc == null:
		return
	m.debug_start_s = lc.debug_match_time
	m.phase_changed.connect(func(_old: int, p: int) -> void:
		print("[match] tick %d  %s  at %s" % [server.tick, MatchRules.PHASE_NAMES[p], MatchRules.format_clock(m.time_s)]))
	if lc.debug_uplink:
		# Concord (the player team) holds the whole lane, so the Syndicate Uplink is
		# Exposed; the player spawns 20 m in front of it.
		for h in server.objectives.all:
			server.objectives.debug_set_owner(h.def.id, ServerWorld.TEAM_PLAYERS)
		var u := m.uplink_of(1 - ServerWorld.TEAM_PLAYERS)
		if u != null:
			var toward := map_def.hq(ServerWorld.TEAM_PLAYERS).uplink - u.base
			server.debug_player_spawn = u.base + Vector3(toward.x, 0.0, toward.z).normalized() * 20.0 + Vector3(0.0, 0.05, 0.0)
	if lc.debug_uplink_integrity > 0.0:
		var e := m.uplink_of(1 - ServerWorld.TEAM_PLAYERS)
		if e != null:
			e.integrity = minf(lc.debug_uplink_integrity, e.max_integrity)


## --debug-uplink: once the player's hero exists, give it a squad and order it
## onto the Exposed enemy Uplink (bolts at 50%, E9 evidence).
func _debug_uplink_squad() -> void:
	if launch_config == null or not launch_config.debug_uplink or server.wardlings == null \
			or server.match_flow == null or server.tick < 45:
		return
	var h := server.hero(client.session.own_net_id) if client != null else null
	var u := server.match_flow.uplink_of(1 - ServerWorld.TEAM_PLAYERS)
	if h == null or u == null or not u.exposed:
		return
	var sq := server.wardlings.squad_of(h.net_id)
	if sq == null:
		sq = server.wardlings.debug_squad_at(h)
	if sq.command != Squad.CMD_ATTACK:
		sq.issue(Squad.CMD_ATTACK, server.tick, Vector3.ZERO, u.net_id)


## --debug-level N / --debug-armory (E13/E15 evidence): once the player's hero
## exists, set its level and learn skills (Unlock all basics, Boost S1 at L3+,
## ult rank 1 at L6+; the rest stays banked), and on the Armory pad buy a gun
## build that fits its weapon. Runs once.
var _debug_progress_done: bool = false


func _debug_progress() -> void:
	if _debug_progress_done or launch_config == null or server.progression == null or client == null \
			or (launch_config.debug_level <= 0 and not launch_config.debug_armory):
		return
	var h := server.hero(client.session.own_net_id)
	if h == null or server.tick < 5:
		return
	_debug_progress_done = true
	var pr := server.progression
	if launch_config.debug_level > 0:
		pr.debug_set_level(h, launch_config.debug_level)
		pr.progress_of(h).exp += 0.45 * EconomyMath.exp_to_next(pr.rules, launch_config.debug_level)
		for slot in 3:
			server.learn_skill(h, slot)
		server.learn_skill(h, 0)
		server.learn_skill(h, 3)
	if launch_config.debug_armory:
		pr.progress_of(h).lumen = 6000
		pr.progress_of(h).at_armory = pr.is_at_armory(h)
		var mana := h.combat.weapon != null and h.combat.weapon.def.feed_kind == WeaponDef.FeedKind.MANA
		var res := [server.buy(h, &"ember_heart" if mana else &"overclock", 3),
			server.buy(h, &"flux_coil" if mana else &"quickload", 2),
			server.buy(h, &"ammo_piercing" if mana else &"ammo_sunder"),
			server.buy(h, &"med_pack")]
		print("[debug-armory] buys %s, Lumen left %d" % [res, pr.progress_of(h).lumen])


## E13/E15 telemetry (dedicated runs): Lumen earned and levels across heroes at
## match minutes 5 / 10 / 20 / 30 (the wardlings-and-economy.md §18 checkpoints).
var _econ_marks: Array[int] = [5, 10, 20, 30]


func _log_economy() -> void:
	if not dedicated or server.progression == null or _econ_marks.is_empty() \
			or server.match_seconds() < _econ_marks[0] * 60.0:
		return
	var m: int = _econ_marks.pop_front()
	var earned: Array[int] = []
	var levels: Array[int] = []
	for id in server.progression.progress:
		var p: HeroProgress = server.progression.progress[id]
		earned.append(p.total_earned())
		levels.append(p.level)
	if earned.is_empty():
		return
	earned.sort()
	levels.sort()
	var sum := 0
	var lsum := 0
	for i in earned.size():
		sum += earned[i]
		lsum += levels[i]
	print("[economy] %d:00 heroes %d | Lumen earned median %d mean %d (min %d max %d) | level median %d mean %.1f (min %d max %d)" % [
		m, earned.size(), earned[earned.size() / 2], sum / earned.size(), earned[0], earned[-1],
		levels[levels.size() / 2], float(lsum) / levels.size(), levels[0], levels[-1]])
	var src := {}
	var xsrc := {}
	for id in server.progression.progress:
		var p: HeroProgress = server.progression.progress[id]
		for k in p.earned:
			src[k] = int(src.get(k, 0)) + int(p.earned[k])
		for k in p.exp_by:
			xsrc[k] = float(xsrc.get(k, 0.0)) + float(p.exp_by[k])
	for k in src:
		src[k] = int(src[k]) / earned.size()
	for k in xsrc:
		xsrc[k] = roundi(float(xsrc[k]) / earned.size())
	print("[economy] %d:00 mean Lumen by source %s | mean EXP by source %s" % [m, src, xsrc])


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
	_debug_uplink_squad()
	_debug_progress()
	_log_economy()
	if _log_every_ticks > 0 and server.tick % _log_every_ticks == 0:
		print("[server] tick=%d entities=%d" % [server.tick, server.registry.count()])
		if server.wardlings != null and server.wardlings.steps > 0:
			var w := server.wardlings
			print("[server] wardlings=%d step avg %.3f ms (last %.3f) | AI think avg %.3f ms (last %.3f) | paths %d" % [
				w.wardlings.size(), w.step_usec_total / 1000.0 / w.steps, w.last_step_usec / 1000.0,
				w.think_usec_total / 1000.0 / w.steps, w.last_think_usec / 1000.0, w.path_queries])
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
