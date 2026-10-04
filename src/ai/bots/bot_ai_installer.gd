class_name BotAiInstaller
extends Node
## Wires hero bots into a running session (AppConfig.sim_plugin_scenes), like
## WardlingAiInstaller: gameplay never names src/ai. Active only for bot
## matches (LaunchConfig.bots / bots_only) on a map with hardpoints and HQs.
##   --bots       the local player (team 0, slot 0) + bots (MatchRulesDef.team_size per team).
##   --bots-only  bots only (2 x team_size). In DEDICATED mode the match runs to End, then the
##                JSON summary is printed ("[bots] summary {...}") and the app quits.

const ROSTER_PATH := "res://assets/data/ai/bot_roster_slice.tres"

## Set by AppRoot (the GameSession node).
var session: Node
var director: BotDirector
var report: BotMatchReport
var _quit_on_end: bool = false
var _next_front_log_s: float = 60.0
var _bot_player: bool = false


func _ready() -> void:
	var lc := session.get("launch_config") as LaunchConfig if session != null else null
	if lc == null or not (lc.bots or lc.bots_only):
		return
	var server := session.get("server") as ServerWorld
	if server == null or server.objectives == null or server.match_flow == null or server.wardlings == null:
		push_warning("BotAiInstaller: bot matches need a map with hardpoints and HQs (--map slice)")
		return
	var roster := load(ROSTER_PATH) as BotRosterDef
	director = BotDirector.new()
	director.setup(server, roster, roster.profile(lc.bot_difficulty), lc.match_seed)
	var n := director.fill(not lc.bots_only)
	# Online slots: humans take over bots on join, bots take over leavers.
	server.controller_taken.connect(func(id: int) -> void:
		director.release_hero(id)
		print("[bots] a player took over bot hero %d" % id))
	server.controller_released.connect(func(id: int) -> void:
		if director.take_over(id) != null:
			print("[bots] a bot took over hero %d (player left)" % id))
	report = BotMatchReport.new(server, director, lc.match_seed)
	server.match_flow.match_ended.connect(_on_match_ended)
	_quit_on_end = lc.bots_only and lc.mode == LaunchConfig.Mode.DEDICATED
	_bot_player = lc.bot_player and lc.bots and lc.mode == LaunchConfig.Mode.OFFLINE
	print("[bots] %d bots (%s), seed %d" % [n, director.profile.id, lc.match_seed])


## --bot-player: once the local hero exists, hand its input to a BotBrain.
func _physics_process(_delta: float) -> void:
	_log_front()
	if not _bot_player:
		return
	var client := session.get("client") as ClientWorld
	var server := session.get("server") as ServerWorld
	if client == null or client.session.own_net_id == 0 or server.hero(client.session.own_net_id) == null:
		return
	_bot_player = false
	var b := BotBrain.new(server, director.profile, hash([director.seed_value, -1]), director.brains.size())
	b.hero_id = client.session.own_net_id
	b.build_order = director.roster.build_order_for(server.hero(b.hero_id).combat.def)
	b.aim.yaw = server.hero(b.hero_id).look_yaw
	director.adopt(b)
	client.input_source = BotClientSource.new(b, server)
	client.player_input = null
	print("[bots] bot drives the local hero %d" % b.hero_id)


func _on_match_ended(_winner: int, _reason: int) -> void:
	print("[bots] summary " + report.to_json())
	_write_telemetry()
	if _quit_on_end:
		get_tree().quit.call_deferred()


## E14: --telemetry <dir>: the summary as <dir>/match_seed<seed>.json (M1 soak).
func _write_telemetry() -> void:
	var lc := session.get("launch_config") as LaunchConfig if session != null else null
	if lc == null or lc.telemetry_dir == "":
		return
	var dir := lc.telemetry_dir
	if not dir.begins_with("/") and not dir.contains("://"):
		dir = "res://" + dir
	dir = ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("match_seed%d.json" % lc.match_seed)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("BotAiInstaller: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(report.summary(), "  "))
	f.close()
	print("[bots] telemetry " + path)


## E14 telemetry (dedicated bot runs): one line per match minute with the lane
## ownership, task state (Generator %, Cell state) and both Uplinks' Integrity.
func _log_front() -> void:
	if report == null or not _quit_on_end:
		return
	var server := session.get("server") as ServerWorld
	var mf := server.match_flow
	if mf == null or mf.is_over() or mf.time_s < _next_front_log_s:
		return
	_next_front_log_s += 60.0
	var parts: PackedStringArray = []
	for h in server.objectives.all:
		var o := "C" if h.owner == 0 else ("S" if h.owner == 1 else "-")
		var extra := ""
		if h.task == HardpointDef.TaskKind.BREACH:
			extra = "g%d" % roundi(h.gen_frac * 100.0) if h.breach_phase == 1 else "h%d" % roundi(h.progress * 100.0)
		elif h.task == HardpointDef.TaskKind.PLANT and h.cell_state != HardpointSim.CellState.NONE:
			extra = ["", "r", "c", "d", "p"][h.cell_state] + str(roundi(h.progress * 100.0))
		elif h.progress > 0.0:
			extra = str(roundi(h.progress * 100.0))
		parts.append(o + extra)
	var dead := [0, 0]
	for b in director.brains:
		var hh := server.hero(b.hero_id)
		if hh != null and hh.combat.dead:
			dead[hh.combat.team] += 1
	print("[front] %s %s | uplinks C %d S %d | dead C%d S%d" % [MatchRules.format_clock(mf.time_s), " ".join(parts),
		roundi(mf.uplink_of(0).integrity), roundi(mf.uplink_of(1).integrity), dead[0], dead[1]])
