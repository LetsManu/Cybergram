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
## Tried first: map_<name>.tres (W14 "front" = Shardline Front).
const MAP_DEF_PATH_PLAIN := "res://assets/data/match/map_%s.tres"
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
## CLIENT mode (--connect): the UDP link to the remote server (no local server).
var remote: ENetTransport
## CLIENT mode: why the connection failed or ended ("" = fine). Read by the HUD/menu.
var remote_status: String = ""
var _remote_wait_ticks: int = 0
## Online dedicated server: the pre-match lobby (null once the match runs).
var lobby: LobbyServer
var _lobby_enet: ENetTransport
var _lobby_ticks: int = 0
## AppRoot defers simulation plugins (bots, Wardling AI) until match_built.
var match_pending: bool = false
signal match_built
## Seconds the server shows the result before it opens a fresh lobby.
const POST_MATCH_S := 15.0
var clock: SimClock
var dedicated: bool = false
## W17B front mode (--front): the connection loop, matchmaking and the supervisor.
var front_server: FrontServer
var front: MatchmakingFront
var supervisor: MatchSupervisor
var _front_enet: ENetTransport
## W17B match process (--host-boot / --match-host): supervisor link + fair play.
var host_agent: MatchHostAgent
var host_runtime: MatchHostRuntime
var _host_enet: ENetTransport
var _quit_after_ticks: int = 0
var _log_every_ticks: int = 0
## W14 perf: whole server.step() time over the current log window (microseconds).
var _tick_us_sum: int = 0
var _tick_us_max: int = 0
var _tick_us_n: int = 0


func _ready() -> void:
	if launch_config != null:
		dedicated = launch_config.mode == LaunchConfig.Mode.DEDICATED
		_quit_after_ticks = launch_config.quit_after_ticks
		if launch_config.net_sim_name != "":
			net_sim = load(NET_SIM_PATH % launch_config.net_sim_name) as NetSimProfile
		if launch_config.map_name != "":
			var md := load_map_def(launch_config.map_name)
			if md != null and md.scene != null:
				map_def = md
				map_scene = md.scene
				if md.match_rules != null and launch_config.match_rules_path == "":
					match_rules = md.match_rules  # C1: the map's format (5v5 full / 3v3 slice)
		if launch_config.match_rules_path != "":
			match_rules = load(launch_config.match_rules_path) as MatchRulesDef
			if match_rules == null:
				push_warning("GameSession: cannot load match rules %s" % launch_config.match_rules_path)
		if launch_config.hero_id != "" and ResourceLoader.exists(HERO_PATH % launch_config.hero_id):
			player_hero = load(HERO_PATH % launch_config.hero_id) as HeroDef
	if player_hero == null:
		player_hero = load(DEFAULT_PLAYER_HERO) as HeroDef
	if dummy_heroes.is_empty():
		for path in DEFAULT_DUMMY_HEROES:
			dummy_heroes.append(load(path))
	if match_rules == null:
		match_rules = load(DEFAULT_MATCH_RULES) as MatchRulesDef
	if look != null:
		look = look.duplicate()  # player options must not touch the shared .tres
		GameSettings.shared().apply_look(look)
	Engine.physics_ticks_per_second = net_config.tick_rate_hz
	clock = SimClock.new(net_config.tick_rate_hz)
	if launch_config != null and launch_config.mm_script != "":
		_start_script_client()
		return
	if launch_config != null and launch_config.mode == LaunchConfig.Mode.CLIENT:
		_setup_remote_client()
		return
	if dedicated and launch_config != null and launch_config.front:
		_start_front()
		return
	if dedicated and launch_config != null and launch_config.match_host:
		_start_match_host()
		return
	if dedicated and launch_config != null and launch_config.port > 0 and not launch_config.no_lobby:
		_start_lobby()
		return
	_build_match()


## MapDef for a `--map` name: map_<name>.tres, else map_<name>_lane.tres (null if neither).
static func load_map_def(map_name: String) -> MapDef:
	var path := map_def_path(map_name)
	return load(path) as MapDef if path != "" else null


## Resource path of a map's MapDef ("" = no such map).
static func map_def_path(map_name: String) -> String:
	for pat in [MAP_DEF_PATH_PLAIN, MAP_DEF_PATH]:
		var path: String = pat % map_name
		if ResourceLoader.exists(path):
			return path
	return ""


## Builds the server world (and the local client unless dedicated).
func _build_match() -> void:
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
	var server_transport: Transport = link.create_endpoint(SERVER_PEER)
	if _lobby_enet != null:
		server_transport = _lobby_enet
	elif dedicated and launch_config != null and launch_config.port > 0:
		var enet := ENetTransport.listen(launch_config.port, launch_config.max_clients)
		if enet.error_text != "":
			push_error("GameSession: %s" % enet.error_text)
			get_tree().quit(1)
			return
		server_transport = enet
		# Headless main loops are uncapped; 2 frames per sim tick keeps a VPS core idle.
		Engine.max_fps = net_config.tick_rate_hz * 2
		enet.peer_connected.connect(func(id: int) -> void: print("[server] peer %d connected" % id))
		enet.peer_disconnected.connect(func(id: int) -> void:
			server.on_peer_left(id)
			print("[server] peer %d disconnected" % id))
		print("[server] online: listening on UDP %d (max %d clients)" % [launch_config.port, launch_config.max_clients])
	server.setup(net_config, movement, map_scene, server_transport, player_hero, match_rules)
	server.session.stats_log_enabled = dedicated  # W16-NET per-client [net] lines
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
		load(ArmoryCatalogDef.active_path()) as ArmoryCatalogDef, map_def)  # E13/E15
	if launch_config != null and launch_config.debug_armory and map_def != null and not map_def.hqs.is_empty():
		server.debug_player_spawn = map_def.hq(ServerWorld.TEAM_PLAYERS).armory + Vector3(0.0, 0.05, 1.5)
	if launch_config != null and launch_config.debug_water and map_def != null and not map_def.water_zones.is_empty():
		server.debug_player_spawn = map_def.water_zones[0].bounds.get_center() + Vector3(-5.0, 0.55, 0.0)
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
		elif launch_config != null and launch_config.debug_task != "" and _debug_task_aim != Vector3.INF:
			source = DebugTaskSource.new(client, _debug_task_aim)
			(source as DebugTaskSource).interact = launch_config.debug_task == "plant"
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
		HeroPlayHistory.track(client, player_hero)  # W15-UX: local hero play history
		client.match_rules = match_rules  # W16-SDWATER: same ring rules as the local server
		client.setup_objectives(map_def)
		if wardling_rules != null:
			client.wardlings.rules = wardling_rules
		if launch_config != null:
			client.wardlings.debug_camera = launch_config.debug_camera


## Heroes per team for this session's match (MatchRulesDef.team_size: Canon C1
## 5v5; the M1 slice plays 3v3). Bot fill (BotDirector) uses the same value.
func team_size() -> int:
	return match_rules.team_size if match_rules != null else 5


## E9: match flow (phases, clock, Uplinks) on maps with hardpoints and HQs.
func _setup_match() -> void:
	if map_def == null or server.objectives == null or map_def.hqs.is_empty():
		return
	var lc := launch_config
	var m := server.setup_match(map_def, lc.match_clock if lc != null else 1.0)
	if lc == null:
		return
	print("[match] format %dv%d (MatchRulesDef.team_size)" % [team_size(), team_size()])
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
	_apply_debug_task(lc)
	if lc.debug_uplink_integrity > 0.0:
		var e := m.uplink_of(1 - ServerWorld.TEAM_PLAYERS)
		if e != null:
			e.integrity = minf(lc.debug_uplink_integrity, e.max_integrity)


## E14 --debug-task: where the debug player aims (Vector3.INF = off).
var _debug_task_aim: Vector3 = Vector3.INF


## E14 evidence setups (Concord = the player team):
##   plant  - Concord holds the Mid and has a Cell planted in Scrap Bazaar (S-BO) at
##            42 % charge; the player stands in the zone by the Socket.
##   breach - Concord holds the Mid and S-BO; the player stands inside Furnace
##            Gate (S-BI) and fires at its Ward Generator with a squad on Attack.
func _apply_debug_task(lc: LaunchConfig) -> void:
	if lc.debug_task == "" or server.objectives == null:
		return
	var objs := server.objectives
	var t := ServerWorld.TEAM_PLAYERS
	objs.debug_set_owner(&"s_mid", t)
	if lc.debug_task == "plant":
		var bo := objs.find(&"s_bo")
		objs.debug_set_cell(&"s_bo", HardpointSim.CellState.PLANTED, t)
		bo.progress = 0.42
		bo.capturing_team = t
		server.debug_player_spawn = bo.def.position + Vector3(2.5, 0.05, 6.0)
		_debug_task_aim = bo.def.position + Vector3(0.0, 2.6, 0.0)
	elif lc.debug_task == "breach":
		objs.debug_set_owner(&"s_bo", t)
		var bi := objs.find(&"s_bi")
		server.debug_player_spawn = bi.def.position + Vector3(3.0, 0.05, 8.0)
		var g := server.generator_of(bi)
		_debug_task_aim = g.aim_point() if g != null else bi.def.position + Vector3(0.0, 1.2, 0.0)


## --debug-task breach: once the player's hero exists, its squad attacks the Generator.
func _debug_task_squad() -> void:
	if launch_config == null or launch_config.debug_task != "breach" or server.wardlings == null or server.tick < 45:
		return
	var h := server.hero(client.session.own_net_id) if client != null else null
	var g := server.generator_of(server.objectives.find(&"s_bi")) if server.objectives != null else null
	if h == null or g == null or not g.is_up():
		return
	var sq := server.wardlings.squad_of(h.net_id)
	if sq == null:
		sq = server.wardlings.debug_squad_at(h)
	if sq.command != Squad.CMD_ATTACK:
		sq.issue(Squad.CMD_ATTACK, server.tick, Vector3.ZERO, g.net_id)


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


# --- W19-HUD: --debug-hud-state low|dead|sd (HUD v0.12 evidence captures) ---
var _hud_state_done: bool = false


func _debug_hud_state() -> void:
	if launch_config == null or launch_config.debug_hud_state == "" or client == null or server.tick < 60:
		return
	var h := server.hero(client.session.own_net_id)
	if h == null or h.combat == null:
		return
	match launch_config.debug_hud_state:
		"low":
			var hc := h.combat.health
			if hc.hp > hc.max_hp * 0.16:
				hc.hp = hc.max_hp * 0.15
		"dead":
			if not h.combat.dead:
				var foe := 0
				for id in server.registry.ids():
					var o := server.registry.get_node_by_id(id) as HeroBody
					if o != null and o.combat != null and o.combat.team != h.combat.team:
						foe = o.net_id
						break
				server.damage_hero(h, DamageInfo.make(100000.0, foe, 1 - h.combat.team))
		"sd":
			if not _hud_state_done and server.match_flow != null:
				_hud_state_done = true
				var m := server.match_flow  # the C10 branch of resolve_time_out, without the tie-breaks
				m.def.sudden_death_enabled = true
				m._enter(MatchRules.Phase.SUDDEN_DEATH)
				m.sudden_death_s = 0.0
				for u in m.uplinks:
					u.set_exposed(false)
				m.sudden_death_started.emit()
		"end":
			if not _hud_state_done and server.match_flow != null:
				_hud_state_done = true
				server.match_flow._end(ServerWorld.TEAM_PLAYERS, MatchRules.EndReason.UPLINK_DESTROYED)
# --- end W19-HUD ---


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
	if launch_config.debug_armory and pr.is_v2():
		# Armory v2 evidence: a Core Signature, a Barrel Assembly, gear, a loose
		# part and a spare, the Chamber, and Lumen left to browse.
		pr.progress_of(h).lumen = 9000
		pr.progress_of(h).at_armory = pr.is_at_armory(h)
		var res2 := []
		for id in [&"ember_heart", &"longsight_ring", &"plate_harness", &"vital_cell", &"vital_cell",
				&"tempo_part", &"ammo_shock", &"mod_saturated", &"med_pack"]:
			res2.append(server.buy(h, id))
		print("[debug-armory] v22 buys %s, Lumen left %d" % [res2, pr.progress_of(h).lumen])
	elif launch_config.debug_armory:
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
	if front_server != null:
		_step_front(delta)
		return
	if host_agent != null:
		var mono := Time.get_ticks_msec() / 1000.0
		host_agent.tick(mono)
		if host_runtime != null:
			host_runtime.tick(mono)
		if host_agent.should_exit():
			print("[match-host] exiting (result acknowledged or shut down)")
			host_agent.close()
			if _host_enet != null:
				_host_enet.close()
			host_agent = null
			get_tree().quit()
			return
		if server == null:
			_lobby_ticks += 1
			if _quit_after_ticks > 0 and _lobby_ticks >= _quit_after_ticks:
				get_tree().quit()
			return  # waiting for the match setup
	if launch_config != null and launch_config.mm_script != "" and remote == null:
		return  # scripted client: no match until the front assigns one
	if lobby != null:
		var l := lobby  # keeps the lobby alive while _on_lobby_started drops it
		l.step(delta)
		_lobby_ticks += 1
		if _quit_after_ticks > 0 and _lobby_ticks >= _quit_after_ticks:
			print("[lobby] quit after %d ticks, %d player(s)" % [_lobby_ticks, lobby.players.size()])
			_lobby_enet.close()
			get_tree().quit()
		return
	for i in clock.advance(delta):
		step_tick()


func _process(delta: float) -> void:
	if client != null:
		client.render(delta)


## One fixed tick of the whole session (also called directly by tests).
func step_tick() -> void:
	if remote != null:
		client.session.poll()
		client.tick()
		_watch_remote()
		return
	if server == null or not is_instance_valid(server):
		# A failed server build (e.g. a script parse error) must not loop an error per tick.
		push_error("GameSession: no ServerWorld (script error at boot?); quitting")
		set_physics_process(false)
		get_tree().quit(1)
		return
	link.advance(net_config.tick_dt())
	if client != null:
		client.session.poll()
		client.tick()
	var t0 := Time.get_ticks_usec()
	server.step()
	var step_us := Time.get_ticks_usec() - t0
	_tick_us_sum += step_us
	_tick_us_max = maxi(_tick_us_max, step_us)
	_tick_us_n += 1
	_debug_uplink_squad()
	_debug_task_squad()
	_debug_progress()
	_debug_hud_state()  # W19-HUD
	_log_economy()
	if _log_every_ticks > 0 and server.tick % _log_every_ticks == 0:
		print("[server] tick=%d entities=%d | server tick avg %.2f ms max %.2f ms (budget %.1f ms)" % [server.tick,
			server.registry.count(), float(_tick_us_sum) / maxf(_tick_us_n, 1) / 1000.0, _tick_us_max / 1000.0,
			1000.0 / net_config.tick_rate_hz])
		_tick_us_sum = 0
		_tick_us_max = 0
		_tick_us_n = 0
		if server.wardlings != null and server.wardlings.steps > 0:
			var w := server.wardlings
			print("[server] wardlings=%d step avg %.3f ms (last %.3f) | AI think avg %.3f ms (last %.3f) | paths %d" % [
				w.wardlings.size(), w.step_usec_total / 1000.0 / w.steps, w.last_step_usec / 1000.0,
				w.think_usec_total / 1000.0 / w.steps, w.last_think_usec / 1000.0, w.path_queries])
			var parts := PackedStringArray()
			for k: StringName in w.section_usec:
				parts.append("%s %.3f" % [k, float(w.section_usec[k]) / 1000.0 / w.steps])
			print("[server] wardling step ms by section: " + ", ".join(parts))
	if _quit_after_ticks > 0 and server.tick >= _quit_after_ticks:
		print("[server] quit after %d ticks, entities=%d" % [server.tick, server.registry.count()])
		get_tree().quit()


## One-line diagnostics for the debug overlay (works in CLIENT mode too, where
## there is no local server).
func debug_text() -> String:
	var p := net_sim if net_sim != null else NetSimProfile.new()
	var tick := server.tick if server != null and is_instance_valid(server) else \
		(client.session.latest_snapshot_tick if client != null else 0)
	var t := "tick %d" % tick
	if remote == null:
		t += " | net-sim %d ms +%d jitter, %.0f%% loss" % [p.one_way_latency_ms, p.jitter_ms, p.loss * 100.0]
	if client != null and client.predictor != null:
		var pr := client.predictor
		t += "\nseq %d acked %d | pred err %.4f m (max %.4f) | corrections %d | remotes %d" % [
			pr.latest_seq, client.session.last_acked_seq,
			pr.last_error_m, pr.max_error_m, pr.corrections, client.view_count()]
	var own := server.hero(client.session.own_net_id) if client != null and server != null else null
	if own != null:
		t += "\nhero %s | kills %d deaths %d" % [own.combat.def.display_name, own.combat.kills, own.combat.deaths]
	return t


## W16-NET: the client's link figures for the net graph ({} without a client).
## Keys: ping_ms (-1 unknown), loss_pct, jitter_ms, jitter_p95_ms, interp_ms,
## interp_ticks, kbps_in, kbps_snap, kbps_out, snap_avg, snap_max, sizes, budget, mode.
func net_stats() -> Dictionary:
	if client == null or client.session == null:
		return {}
	var st := client.session.stats
	var ping := -1
	var mode := "UDP"
	if remote != null:
		ping = remote.rtt_ms()
		mode = "UDP DTLS" if remote.is_secure else "UDP"
	else:
		var p := net_sim if net_sim != null else NetSimProfile.new()
		ping = p.one_way_latency_ms * 2
		mode = "loopback (sim)" if p.one_way_latency_ms > 0 or p.loss > 0.0 else "loopback"
	var interp := client.interp_delay_ticks()
	return {
		"ping_ms": ping, "loss_pct": st.loss_pct(), "jitter_ms": st.jitter_mean_ms(),
		"jitter_p95_ms": st.jitter_p95_ms(), "interp_ticks": interp,
		"interp_ms": interp * 1000.0 / net_config.tick_rate_hz,
		"kbps_in": st.kbps_in(), "kbps_snap": st.kbps_snapshots(), "kbps_out": st.kbps_out(),
		"snap_avg": st.snapshot_avg_bytes(), "snap_max": st.snapshot_max_bytes(), "sizes": st.sizes(),
		"budget": net_config.snapshot_budget_bytes, "mode": mode,
	}


## CLIENT mode: a ClientWorld joined to a remote dedicated server over UDP.
func _setup_remote_client() -> void:
	var lc := launch_config
	remote = ENetTransport.connect_to(lc.connect_address, lc.port,
		AuthConfig.from_os().client_tls_for(lc.connect_address))  # L1: DTLS like the lobby link
	print("[client] connecting to %s:%d" % [lc.connect_address, lc.port])
	if net_sim != null and OS.is_debug_build() and (net_sim.one_way_latency_ms > 0 or net_sim.jitter_ms > 0 or net_sim.loss > 0.0):
		remote.debug_conditioner = NetSimConditioner.new(net_sim)  # W16-NET debug loss / jitter injector
		print("[client] debug net-sim on received packets: %d ms +%d jitter, %.0f%% loss" % [
			net_sim.one_way_latency_ms, net_sim.jitter_ms, net_sim.loss * 100.0])
	client = ClientWorld.new()
	client.hello_token = lc.token
	client.hello_ticket = lc.ticket
	add_child(client)
	var input := PlayerInputSource.new()
	input.setup(look, movement)
	add_child(input)
	client.setup(net_config, movement, look, map_scene, remote, input, player_hero)
	client.setup_objectives(map_def)
	var wardling_rules := load(WARDLING_RULES) as WardlingRulesDef
	if wardling_rules != null:
		client.wardlings.rules = wardling_rules
	HeroPlayHistory.track(client, player_hero)  # W15-UX: local hero play history
	client.match_ended.connect(func(_w: int, _r: int) -> void:
		if lc.mm_script != "" or lc.ticket != "":
			return  # matchmade: the front reports the result; the menu / script handles it
		get_tree().create_timer(POST_MATCH_S - 3.0).timeout.connect(func() -> void:
			if not is_inside_tree():
				return  # the player already left through the match-end screen
			remote.close()
			AppRoot.rejoin_lobby(get_tree(), "%s:%d" % [lc.connect_address, lc.port])))
	client.session.rejected.connect(func(reason: int) -> void:
		remote_status = "server rejected the connection (reason %d: version mismatch?)" % reason)


## Ticks to wait for the server's Welcome before giving up.
const REMOTE_TIMEOUT_TICKS: int = 30 * 8


## W16-NET: headless CLIENT runs (smoke tests) print the link figures every 10 s.
var _client_log_ticks: int = 0


func _log_client_net() -> void:
	if DisplayServer.get_name() != "headless":
		return
	_client_log_ticks += 1
	if _client_log_ticks % roundi(net_config.stats_log_interval_s * net_config.tick_rate_hz) != 0:
		return
	var n := net_stats()
	if n.is_empty():
		return
	print("[client-net] ping=%dms loss=%.1f%% jitter=%.1fms p95=%.1fms interp=%.0fms snap avg=%dB max=%dB in=%.2fkB/s out=%.2fkB/s misses=%d malformed=%d" % [
		n.ping_ms, n.loss_pct, n.jitter_ms, n.jitter_p95_ms, n.interp_ms, roundi(n.snap_avg), n.snap_max,
		n.kbps_snap, n.kbps_out, client.session.stats.baseline_misses, client.session.malformed_packets])


func _watch_remote() -> void:
	_log_client_net()
	if remote.error_text != "" and remote_status == "":
		remote_status = remote.error_text
	if not client.session.is_welcomed:
		_remote_wait_ticks += 1
		if _remote_wait_ticks == REMOTE_TIMEOUT_TICKS and remote_status == "":
			remote_status = "no answer from %s:%d (server down, wrong address, or UDP port blocked)" % [
				launch_config.connect_address, launch_config.port]
	if remote_status != "":
		push_warning("[client] %s" % remote_status)
		remote.close()
		set_physics_process(false)
		if launch_config.mm_script != "":
			return  # the scripted client waits for the front's verdict
		AppRoot.back_to_menu(get_tree(), remote_status)


## Online dedicated server: open the lobby on the UDP port; the match is built
## when the lobby starts it (see LobbyServer).
func _start_lobby() -> void:
	match_pending = true
	# L1: DTLS + server accounts when a certificate is configured, else guest-only.
	var auth := AuthConfig.from_os()
	var tls := auth.load_server_tls()
	_lobby_enet = ENetTransport.listen(launch_config.port, launch_config.max_clients, tls)
	if _lobby_enet.error_text == "":
		_open_accounts(auth, tls)
	if _lobby_enet.error_text != "":
		push_error("GameSession: %s" % _lobby_enet.error_text)
		get_tree().quit(1)
		return
	Engine.max_fps = net_config.tick_rate_hz * 2  # headless loops are uncapped
	lobby = LobbyServer.new(_lobby_enet, team_size())
	lobby.match_started.connect(_on_lobby_started)
	print("[lobby] open on UDP %d: waiting for players (all must press Ready)" % launch_config.port)


func _on_lobby_started(slots: Array) -> void:
	var enet := _lobby_enet
	lobby = null
	_build_match()
	for sl: Dictionary in slots:
		server.reserved_slots[sl.token] = {"team": sl.team, "hero_index": sl.hero_index}
		server.session.token_names[sl.token] = {"name": sl.name, "id": sl.id, "accent": sl.accent}
	enet.peer_disconnected.connect(func(id: int) -> void: server.on_peer_left(id))
	server.session.client_joined.connect(func(peer: int) -> void:
		print("[server] player joined the match (peer %d)" % peer), CONNECT_DEFERRED)
	print("[lobby] match starting with %d player(s)" % slots.size())
	match_pending = false
	match_built.emit()
	if server.match_flow != null:
		server.match_flow.match_ended.connect(func(_w: int, _r: int) -> void:
			print("[lobby] match over; new lobby in %d s" % int(POST_MATCH_S))
			get_tree().create_timer(POST_MATCH_S).timeout.connect(func() -> void:
				enet.close()
				get_tree().reload_current_scene()))


## Accounts for an online server (lobby or front): file store with DTLS,
## else guest-only. Returns the process-wide AccountService.
func _open_accounts(auth: AuthConfig, tls: TLSOptions) -> AccountService:
	var store: AccountStore = null
	if tls != null:
		store = FileAccountStore.new(auth.data_dir)
		if store.open() != OK:
			push_error("[accounts] cannot open the account store in %s" % auth.data_dir)
			store = null
	var svc := AccountService.configure_shared(store, AuthConfig.rules(), tls != null and store != null,
		auth.allow_guests)
	if store != null:
		print("[accounts] encrypted login enabled (%d account(s) in %s); guests %s" % [store.count(),
			auth.data_dir, "allowed" if svc.allow_guests else "off (login required)"])
	else:
		print("[accounts] %s; guest-only (login disabled)" % (auth.tls_error if tls == null else "no account store"))
	return svc


# --- W17B front (--front) ---------------------------------------------------------

## Front mode: accounts, parties, queues, picks and the match supervisor on the
## UDP port; matches run in supervised processes (docs/HOSTING.md).
func _start_front() -> void:
	var lc := launch_config
	var auth := AuthConfig.from_os()
	var tls := auth.load_server_tls()
	_front_enet = ENetTransport.listen(lc.port if lc.port > 0 else LaunchConfig.DEFAULT_PORT, lc.max_clients, tls)
	if _front_enet.error_text != "":
		push_error("GameSession: %s" % _front_enet.error_text)
		get_tree().quit(1)
		return
	match_pending = true  # no match in this process: AppRoot adds no sim plugins
	var accounts := _open_accounts(auth, tls)
	var rules := front_rules(MatchmakingRulesDef.load_default(), lc)
	var base := auth.data_dir.get_base_dir()
	var ratings_dir := _env_or("CYBERGRAM_RATINGS_DIR", base.path_join("ratings"))
	var reports_dir := _env_or("CYBERGRAM_REPORTS_DIR", base.path_join("reports"))
	var mm_dir := _env_or("CYBERGRAM_MM_DIR", base.path_join("matchmaking"))
	var store := FileRatingStore.new(ratings_dir)
	if store.open() != OK:
		push_error("[front] cannot open the rating store in %s" % ratings_dir)
	var reports := ReportStore.new(reports_dir, rules)
	reports.open()
	var history := MatchHistoryStore.new(mm_dir, rules)
	history.open()
	var hc := HostingConfig.from_env()
	var chan := HostChannelUdp.new()
	if chan.open_server(0) != OK:
		push_error("[front] cannot open the supervisor channel")
		get_tree().quit(1)
		return
	var files := MatchHostFiles.new()
	files.prepare()
	var engine_args := PackedStringArray(["--headless"])
	if not OS.has_feature("template"):
		engine_args.append_array(["--path", ProjectSettings.globalize_path("res://")])  # running from source
	supervisor = MatchSupervisor.new(hc, MatchProcessLauncher.new("", engine_args), chan, files, TicketKeyRing.from_env())
	front = MatchmakingFront.new(_front_enet, accounts, supervisor, RatingService.new(store, rules), reports, history,
		rules, mm_dir)
	if lc.match_clock != 1.0:
		front.setup_rules["match_clock"] = lc.match_clock
	if lc.mm_match_s > 0.0:
		front.setup_rules["end_after_s"] = lc.mm_match_s
	front.rate_guests = OS.get_environment("CYBERGRAM_RATE_GUESTS").to_lower() in ["1", "true", "yes", "on"]
	front.housekeeping(front.now())
	front_server = FrontServer.new(_front_enet, accounts, front)
	front_server.build_version = hc.build_version
	front_server.ready_checks["supervisor"] = func() -> bool: return not supervisor.draining
	front_server.start_ops()  # P1: /health, /metrics, /admin when CYBERGRAM_OPS_PORT is set
	supervisor.drained.connect(func() -> void:
		print("[front] drained: exiting")
		_front_enet.close()
		get_tree().quit())
	Engine.max_fps = net_config.tick_rate_hz * 2
	print("[front] listening on UDP %d: build %s, match ports %d-%d, capacity %d, warm pool %d" % [
		lc.port if lc.port > 0 else LaunchConfig.DEFAULT_PORT, hc.build_version, hc.port_first, hc.port_last,
		hc.capacity(), hc.warm_pool])
	print("[front] data: ratings %s, reports %s, matchmaking %s" % [ratings_dir, reports_dir, mm_dir])


## The data rules with the testing overrides of `lc` (--mm-team-size, --mm-pick-s).
static func front_rules(base: MatchmakingRulesDef, lc: LaunchConfig) -> MatchmakingRulesDef:
	if lc == null or (lc.mm_team_size <= 0 and lc.mm_pick_s <= 0.0):
		return base
	var r := base.duplicate(true) as MatchmakingRulesDef
	if lc.mm_team_size > 0:
		var qs: Array[MatchQueueDef] = []
		for q in base.queues:
			var c := q.duplicate() as MatchQueueDef
			if c.team_size == 5 and c.matchmade:
				c.team_size = lc.mm_team_size
				if lc.mm_team_size < 5:
					var none: Array[StringName] = []
					c.lane_slots = none
			qs.append(c)
		r.queues = qs
		var order := PackedInt32Array([1])
		var left := lc.mm_team_size * 2 - 1
		while left > 0:
			order.append(mini(2, left))
			left -= mini(2, left)
		r.draft_order = order
	if lc.mm_pick_s > 0.0:
		r.pick_turn_s = lc.mm_pick_s
		r.all_random_s = lc.mm_pick_s * 2.0
		r.blind_pick_s = lc.mm_pick_s  # P3: blind pick and the trade window follow the test override
		r.finalize_s = 0.0
	return r


static func _env_or(key: String, fallback: String) -> String:
	var v := OS.get_environment(key).strip_edges()
	return v if v != "" else fallback


func _step_front(delta: float) -> void:
	front_server.step(delta)
	supervisor.tick(Time.get_ticks_msec() / 1000.0)
	_lobby_ticks += 1
	if _quit_after_ticks > 0 and _lobby_ticks >= _quit_after_ticks:
		print("[front] quit after %d ticks" % _lobby_ticks)
		supervisor.shutdown_now("front_exit")
		_front_enet.close()
		get_tree().quit()


func _exit_tree() -> void:
	if supervisor != null:
		supervisor.shutdown_now("front_exit")  # never leave match processes behind


# --- W17B match process (--host-boot) -----------------------------------------------

## Match process: report Ready to the supervisor, wait for the match setup,
## then build the match directly (no lobby). Clients join with join tickets.
func _start_match_host() -> void:
	host_agent = MatchHostAgent.from_cmdline(OS.get_cmdline_user_args())
	if host_agent == null:
		push_error("[match-host] not started by a supervisor (no valid --host-boot)")
		get_tree().quit(2)
		return
	_host_enet = ENetTransport.listen(host_agent.port(), launch_config.max_clients, AuthConfig.from_os().load_server_tls())
	if _host_enet.error_text != "":
		push_error("[match-host] %s" % _host_enet.error_text)
		get_tree().quit(1)
		return
	match_pending = true
	Engine.max_fps = net_config.tick_rate_hz * 2
	host_agent.allocated.connect(_on_host_allocated)
	host_agent.mark_ready()
	print("[match-host] slot %d ready on UDP %d (build %s)" % [int(host_agent.boot.slot), host_agent.port(),
		host_agent.build()])


func _on_host_allocated(setup: Dictionary) -> void:
	var r: Dictionary = setup.get("rules", {})
	var md := load_map_def(str(setup.map))
	if md != null and md.scene != null:
		map_def = md
		map_scene = md.scene
		if md.match_rules != null:
			match_rules = md.match_rules
	if r.has("team_size") and match_rules != null and int(r.team_size) != match_rules.team_size:
		match_rules = match_rules.duplicate() as MatchRulesDef
		match_rules.team_size = clampi(int(r.team_size), 1, 5)
	if r.has("match_clock"):
		launch_config.match_clock = clampf(float(r.match_clock), 0.1, 100.0)
	launch_config.bots = true  # bots fill every seat not reserved for a human
	# v20 custom games: the host's bot difficulty and bots per team.
	var diff := str(r.get("bot_difficulty", ""))
	if diff in MatchmakingCodec.BOT_DIFFICULTIES:
		launch_config.bot_difficulty = diff
	var per: Variant = r.get("bots_per_team", null)
	if per is Array and (per as Array).size() == 2:
		var slots: Array[int] = [clampi(int(per[0]), 0, 5), clampi(int(per[1]), 0, 5)]
		launch_config.bot_slots = slots
	_lobby_enet = _host_enet
	_build_match()
	var content := ContentDB.shared()
	var token := 0
	for e: Dictionary in setup.roster:
		if bool(e.get("bot", false)):
			continue
		token += 1
		var acc := str(e.account)
		var hero := content.index_of(ContentDB.HERO, StringName(str(e.get("hero", ""))))
		server.reserved_slots[token] = {"team": int(e.team), "hero_index": hero}
		server.session.token_names[token] = {"name": str(e.get("name", "")), "id": acc, "accent": int(e.get("accent", 0))}
		server.session.account_tokens[acc] = token
		server.session.account_heroes[acc] = hero
	server.session.mood_seed = int(r.get("mood_seed", 0))
	server.session.ticket_verifier = func(t: String) -> Dictionary:
		return host_agent.verify_ticket(t, Time.get_unix_time_from_system())
	host_runtime = MatchHostRuntime.new(host_agent, setup, func(p: int, b: PackedByteArray) -> void:
		_host_enet.send(p, Transport.CH_CONTROL, b))
	host_runtime.stats_fn = _host_stats
	server.session.mm_handler = func(p: int, d: PackedByteArray) -> void:
		host_runtime.handle(p, d, Time.get_ticks_msec() / 1000.0)
	_host_enet.peer_disconnected.connect(func(id: int) -> void:
		host_runtime.on_leave(id, Time.get_ticks_msec() / 1000.0)
		server.on_peer_left(id))
	server.session.client_joined.connect(func(peer: int) -> void:
		var acc := str(server.session.peer_accounts.get(peer, ""))
		host_runtime.on_join(peer, acc, Time.get_ticks_msec() / 1000.0)
		print("[match-host] player #%s joined (peer %d)" % [PlayerProfile.tag_of(acc), peer]), CONNECT_DEFERRED)
	host_runtime.start(Time.get_ticks_msec() / 1000.0)
	if server.match_flow != null:
		server.match_flow.match_ended.connect(func(w: int, _reason: int) -> void:
			print("[match-host] match over: winner team %d" % w)
			host_runtime.finish(w, Time.get_ticks_msec() / 1000.0))
	print("[match-host] match %s started: map %s, %d human seat(s), mood %d" % [str(setup.match_id), str(setup.map),
		token, server.session.mood_seed])
	match_pending = false
	match_built.emit()


## Per-player stats for the result report (ids and numbers only).
func _host_stats() -> Array:
	var out: Array = []
	for e: Dictionary in host_agent.setup.get("roster", []):
		if bool(e.get("bot", false)):
			continue
		var acc := str(e.account)
		var h: HeroBody = server.token_heroes.get(server.session.account_tokens.get(acc, 0)) if server != null else null
		var row := {"account": acc, "team": int(e.team), "hero": str(e.get("hero", "")), "kills": 0, "deaths": 0,
			"assists": 0}
		if h != null and is_instance_valid(h):
			row.kills = int(server.stats.value(h.net_id, MatchStats.Stat.KILLS))
			row.deaths = int(server.stats.value(h.net_id, MatchStats.Stat.DEATHS))
			row.assists = int(server.stats.value(h.net_id, MatchStats.Stat.ASSISTS))
		out.append(row)
	return out


# --- W17B scripted client (--mm-script-client) ----------------------------------------

func _start_script_client() -> void:
	var lc := launch_config
	var sc := MatchmakingScriptClient.new()
	sc.session = self
	sc.scenario = lc.mm_script
	sc.user = lc.mm_user if lc.mm_user != "" else "Script"
	sc.address = lc.connect_address if lc.connect_address != "" else "127.0.0.1"
	sc.port = lc.port if lc.port > 0 else LaunchConfig.DEFAULT_PORT
	add_child(sc)


## Joins a matchmade match process (the menu or the scripted client calls it
## after MATCH_ASSIGNED): this session becomes a remote client with the ticket.
func join_matchmade(host: String, port: int, ticket: String, hero_index: int, map_name: String) -> void:
	var lc := launch_config
	lc.mode = LaunchConfig.Mode.CLIENT
	lc.connect_address = host
	lc.port = port
	lc.ticket = ticket
	var id := ContentDB.shared().id_at(ContentDB.HERO, hero_index)
	if id != &"" and ResourceLoader.exists(HERO_PATH % String(id).trim_prefix("hero_")):
		player_hero = load(HERO_PATH % String(id).trim_prefix("hero_")) as HeroDef
	if map_name != "":
		var md := load_map_def(map_name)
		if md != null and md.scene != null:
			map_def = md
			map_scene = md.scene
	_setup_remote_client()
