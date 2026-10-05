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
	if launch_config != null and launch_config.mode == LaunchConfig.Mode.CLIENT:
		_setup_remote_client()
		return
	if dedicated and launch_config != null and launch_config.port > 0 and not launch_config.no_lobby:
		_start_lobby()
		return
	_build_match()


## MapDef for a `--map` name: map_<name>.tres, else map_<name>_lane.tres (null if neither).
static func load_map_def(map_name: String) -> MapDef:
	for pat in [MAP_DEF_PATH_PLAIN, MAP_DEF_PATH]:
		var path: String = pat % map_name
		if ResourceLoader.exists(path):
			return load(path) as MapDef
	return null


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
		load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef, map_def)  # E13/E15
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
				server.match_flow.def.sudden_death_enabled = true
				server.match_flow.resolve_time_out()
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
