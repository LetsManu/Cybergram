class_name BotAiInstaller
extends Node
## Wires hero bots into a running session (AppConfig.sim_plugin_scenes), like
## WardlingAiInstaller: gameplay never names src/ai. Active only for bot
## matches (LaunchConfig.bots / bots_only) on a map with hardpoints and HQs.
##   --bots       the local player (team 0, slot 0) + 9 bots.
##   --bots-only  10 bots. In DEDICATED mode the match runs to End, then the
##                JSON summary is printed ("[bots] summary {...}") and the app quits.

const ROSTER_PATH := "res://assets/data/ai/bot_roster_slice.tres"

## Set by AppRoot (the GameSession node).
var session: Node
var director: BotDirector
var report: BotMatchReport
var _quit_on_end: bool = false
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
	report = BotMatchReport.new(server, director, lc.match_seed)
	server.match_flow.match_ended.connect(_on_match_ended)
	_quit_on_end = lc.bots_only and lc.mode == LaunchConfig.Mode.DEDICATED
	_bot_player = lc.bot_player and lc.bots and lc.mode == LaunchConfig.Mode.OFFLINE
	print("[bots] %d bots (%s), seed %d" % [n, director.profile.id, lc.match_seed])


## --bot-player: once the local hero exists, hand its input to a BotBrain.
func _physics_process(_delta: float) -> void:
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
	if _quit_on_end:
		get_tree().quit.call_deferred()
