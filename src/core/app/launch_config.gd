class_name LaunchConfig
extends RefCounted
## Parsed command line (architecture.md §2.1). Only AppRoot builds one; nothing
## else reads OS arguments.
##   godot --path .                              -> OFFLINE playable match: Shardline Front, 5v5 (--map slice: 3v3)
##                                                  (MatchRulesDef.team_size) vs normal bots,
##                                                  as Vesper Loom (--hero brannoc for Brannoc)
##   godot --path . -- --map test_course         -> OFFLINE movement test course (dummies, no bots)
##   godot --path . -- --map slice               -> the slice without bots (evidence / debug setups)
##   godot --path . -- --net-sim 100ms_2pct      -> OFFLINE through a conditioned loopback
##   godot --headless --path . [-- --server]     -> DEDICATED (server only)
##   godot --headless --path . -- --server --port 7777 [--max-clients 8]
##                                                -> ONLINE dedicated server (UDP), slice 3v3,
##                                                  bots fill the slots humans do not
##   godot --path . -- --connect 1.2.3.4[:7777]  -> CLIENT: join that server (no local server)
##   godot --path . -- --open-lobby 1.2.3.4[:7777] -> menu opened straight into that server's lobby
##   ... -- --server --quit-after-ticks 900      -> soak run that exits
##   godot --path . -- --map slice               -> load assets/data/match/map_<name>.tres (or map_<name>_lane.tres)
##   ... -- --hero brannoc                       -> play hero_brannoc.tres (also --hero=brannoc)
##   ... -- --autofire                           -> debug: the local client aims and fires at
##                                                  the nearest enemy (evidence captures)
##   ... -- --map slice --spawn-wardlings 80     -> debug: 80 extra ownerless Wardlings (E8 perf)
##   ... -- --map slice --wave-clock 30         -> debug: Vanguard cadence 30x faster
##   ... -- --debug-camera vanguard             -> debug: overview camera on the Concord wave
##   ... -- --debug-squad-demo                  -> debug: the local hero backs down the lane
##                                                  facing its squad (E8 evidence)
##   ... -- --map slice --debug-capture s_mid    -> debug: spawn inside that hardpoint's zone,
##                                                  which starts mid-capture (E7 evidence)
##   ... -- --map slice --match-clock 20         -> debug: match clock (phases, Surges,
##                                                  Time-out, C11 minutes) 20x faster
##   ... -- --debug-match-time 1040             -> debug: the match clock starts at 17:20
##   ... -- --debug-uplink                      -> debug: Concord holds the lane to S-BI, the
##                                                  player spawns at the Syndicate Uplink and
##                                                  fires at it with its squad (E9 evidence)
##   ... -- --debug-uplink-integrity 2000       -> debug: Syndicate Uplink starts at 2000
##   ... -- --grant-ult                          -> debug: ultimates usable below level 6 (E10)
##   ... -- --bots                               -> E11: player + bots filling MatchRulesDef.team_size
##                                                  per team (slice: 3v3, player + 5 bots)
##   godot --headless --fixed-fps 30 --path . -- --server --bots-only --seed 3 [--match-clock 4]
##                                                -> E11: 2 x team_size bots play to End, JSON summary, quit
##   ... -- --bot-difficulty easy|normal|hard    -> E11: bot profile (default normal)
##   ... -- --bots-only --telemetry production/qa/telemetry/m1
##                                                -> E14: also write the match summary JSON there
##   ... -- --match-rules /abs/or/res/path.tres  -> tuning: MatchRulesDef replacing the slice rules
##   ... -- --debug-task plant|breach            -> debug: a Concord Cell planted at S-BO / the player
##                                                  inside S-BI shooting its Generator (E14 evidence)
##   ... -- --bots --bot-player                  -> E11 debug: a bot also plays the local hero
##   ... -- --debug-skill-demo                   -> debug: the local hero casts its skills on a
##                                                  schedule (E10 evidence)
##   ... -- --map slice --debug-level 7          -> debug: the local hero starts at level 7 with
##                                                  skills learned and points banked (E15 evidence)
##   ... -- --map slice --debug-armory           -> debug: spawn on the Armory pad with Lumen,
##                                                  mounts bought, Armory panel open (E13 evidence)

## CLIENT: no local server; the client connects over UDP (--connect).
enum Mode { OFFLINE, DEDICATED, CLIENT }

var mode: Mode = Mode.OFFLINE
var net_sim_name: String = ""
var quit_after_ticks: int = 0
## Map id stem ("" = the session scene's default map). Resolved by the session.
var map_name: String = ""
## W14: the map a match runs on when --map is not given (Online, Vs Bots, default
## launch): the 3-lane "Shardline Front" (5v5). `--map slice` selects the 1-lane
## Shardline Causeway (3v3, the menu's Quick Match).
const DEFAULT_MAP := "front"
## Hero id suffix (assets/data/heroes/hero_<id>.tres); "" = session default.
var hero_id: String = ""
var autofire: bool = false
## Debug: hardpoint id to start in, mid-capture ("" = off).
var debug_capture: String = ""
var debug_capture_progress: float = 0.45
## E8 debug: extra Wardlings to spawn, Vanguard clock scale, camera mode, demo input.
var spawn_wardlings: int = 0
var wave_clock: float = 1.0
var debug_camera: String = ""
var debug_squad_demo: bool = false
## E10 debug: ultimate unlocked below level 6; scripted skill casts.
var grant_ult: bool = false
var debug_skill_demo: bool = false
## E9 debug: match clock scale, start time, Uplink siege setup and start Integrity (< 0 = off).
var match_clock: float = 1.0
var debug_match_time: float = 0.0
var debug_uplink: bool = false
var debug_uplink_integrity: float = -1.0
## E13/E15 debug: start level (0 = off) and the Armory evidence setup.
var debug_level: int = 0
var debug_armory: bool = false
## W16-SDWATER debug: spawn in the first water zone of the map (splash / wading evidence).
var debug_water: bool = false
## E11 bots: --bots (player + 9 bots), --bots-only (10 bots, no player; with
## --server the match runs to End and prints a JSON summary), --seed, --bot-difficulty.
var bots: bool = false
var bots_only: bool = false
var match_seed: int = 1
var bot_difficulty: String = ""
## E11 debug (evidence captures): a bot drives the local player's hero too.
var bot_player: bool = false
## E14: directory for the per-match telemetry JSON ("" = print only).
var telemetry_dir: String = ""
## E14 debug: "plant" or "breach" evidence setup ("" = off).
var debug_task: String = ""
## Tuning runs: a MatchRulesDef .tres path replacing the slice rules ("" = default).
var match_rules_path: String = ""
## Online (ENetTransport): UDP port the dedicated server listens on (0 = no
## network, loopback only) or the client connects to.
var port: int = 0
## CLIENT mode: server address (host name or IP).
var connect_address: String = ""
## Dedicated server: most simultaneous remote clients.
var max_clients: int = 12  # W14: a full 5v5 lobby (10 seats) + spare
# --- W19-HUD ---
## Debug (HUD evidence): "low" keeps the own hero at 15% HP, "dead" kills it
## (by an enemy hero) whenever it is alive, "sd" starts Sudden Death. "" = off.
var debug_hud_state: String = ""
# --- end W19-HUD ---
## Debug: open the pause menu on start (UI evidence captures).
var debug_pause_menu: bool = false
## Debug: with --debug-settings <video|audio|controls|gameplay|comfort|0-4> the pause menu
## opens on that settings tab (-1 = off). Implies --debug-pause-menu.
var debug_settings_tab: int = -1
## CLIENT: lobby slot token for the match (from LOBBY_START).
var token: int = 0
## Dedicated online server without the pre-match lobby (old behaviour).
var no_lobby: bool = false
## Open the main menu straight into this server's lobby (host[:port]).
var open_lobby: String = ""
## Testing: the lobby screen presses Ready by itself.
var auto_ready: bool = false


## `--map test_course` selects the movement test course (no MapDef).
const TEST_COURSE := "test_course"
## UDP port when --connect gives none (matches ENetTransport.DEFAULT_PORT).
const DEFAULT_PORT: int = 7777


static func parse(args: PackedStringArray, headless: bool) -> LaunchConfig:
	var c := LaunchConfig.new()
	if headless:
		c.mode = Mode.DEDICATED
	var i := 0
	while i < args.size():
		match args[i]:
			"--server":
				c.mode = Mode.DEDICATED
			"--port":
				if i + 1 < args.size():
					i += 1
					c.port = clampi(args[i].to_int(), 1, 65535)
			"--token":
				if i + 1 < args.size():
					i += 1
					c.token = clampi(args[i].to_int(), 0, 65535)
			"--auto-ready":
				c.auto_ready = true
			"--open-lobby":
				if i + 1 < args.size():
					i += 1
					c.open_lobby = args[i]
			"--no-lobby":
				c.no_lobby = true
			"--debug-hud-state":  # W19-HUD
				if i + 1 < args.size():
					i += 1
					c.debug_hud_state = args[i].validate_filename()
			"--debug-pause-menu":
				c.debug_pause_menu = true
			"--debug-settings":
				c.debug_pause_menu = true
				c.debug_settings_tab = 0
				if i + 1 < args.size():
					i += 1
					var tabs := ["video", "audio", "controls", "gameplay", "comfort"]
					var t := tabs.find(args[i].to_lower())
					c.debug_settings_tab = t if t >= 0 else clampi(args[i].to_int(), 0, 4)
			"--max-clients":
				if i + 1 < args.size():
					i += 1
					c.max_clients = clampi(args[i].to_int(), 1, 32)
			"--connect":
				if i + 1 < args.size():
					i += 1
					c.mode = Mode.CLIENT
					var hp := args[i].rsplit(":", true, 1)
					c.connect_address = hp[0]
					if hp.size() == 2 and hp[1].is_valid_int():
						c.port = clampi(hp[1].to_int(), 1, 65535)
			"--net-sim":
				if i + 1 < args.size():
					i += 1
					c.net_sim_name = args[i].validate_filename()
			"--autofire":
				c.autofire = true
			"--spawn-wardlings":
				if i + 1 < args.size():
					i += 1
					c.spawn_wardlings = clampi(args[i].to_int(), 0, 512)
			"--wave-clock":
				if i + 1 < args.size():
					i += 1
					c.wave_clock = clampf(args[i].to_float(), 0.01, 1000.0)
			"--debug-camera":
				if i + 1 < args.size():
					i += 1
					c.debug_camera = args[i].validate_filename()
			"--debug-squad-demo":
				c.debug_squad_demo = true
			"--bots":
				c.bots = true
			"--bots-only", "--slice-autoplay":
				c.bots_only = true
			"--seed":
				if i + 1 < args.size():
					i += 1
					c.match_seed = args[i].to_int()
			"--bot-player":
				c.bot_player = true
			"--telemetry":
				if i + 1 < args.size():
					i += 1
					c.telemetry_dir = args[i]
			"--match-rules":
				if i + 1 < args.size():
					i += 1
					c.match_rules_path = args[i]
			"--debug-task":
				if i + 1 < args.size():
					i += 1
					c.debug_task = args[i].validate_filename()
			"--bot-difficulty":
				if i + 1 < args.size():
					i += 1
					c.bot_difficulty = args[i].validate_filename()
			"--grant-ult":
				c.grant_ult = true
			"--debug-level":
				if i + 1 < args.size():
					i += 1
					c.debug_level = clampi(args[i].to_int(), 0, 15)
			"--debug-armory":
				c.debug_armory = true
			"--debug-water":
				c.debug_water = true
			"--debug-skill-demo":
				c.debug_skill_demo = true
			"--match-clock":
				if i + 1 < args.size():
					i += 1
					c.match_clock = clampf(args[i].to_float(), 0.01, 1000.0)
			"--debug-match-time":
				if i + 1 < args.size():
					i += 1
					c.debug_match_time = maxf(args[i].to_float(), 0.0)
			"--debug-uplink":
				c.debug_uplink = true
			"--debug-uplink-integrity":
				if i + 1 < args.size():
					i += 1
					c.debug_uplink_integrity = maxf(args[i].to_float(), 1.0)
			"--debug-capture":
				if i + 1 < args.size():
					i += 1
					c.debug_capture = args[i].validate_filename()
			"--hero":
				if i + 1 < args.size():
					i += 1
					c.hero_id = args[i].validate_filename()
			"--map":
				if i + 1 < args.size():
					i += 1
					c.map_name = args[i].validate_filename()
			"--quit-after-ticks":
				if i + 1 < args.size():
					i += 1
					c.quit_after_ticks = maxi(args[i].to_int(), 0)
			_:
				if args[i].begins_with("--hero="):
					c.hero_id = args[i].trim_prefix("--hero=").validate_filename()
		i += 1
	var map_given := c.map_name != ""
	if c.map_name == TEST_COURSE:
		c.map_name = ""  # the session scene's default map (movement test course)
	elif (c.bots or c.bots_only) and c.map_name == "":
		c.map_name = DEFAULT_MAP  # W14: bot matches run on the full 3-lane map
	elif not map_given and (c.mode == Mode.CLIENT or (c.mode == Mode.DEDICATED and c.port > 0)):
		# Online: the full-map match; the server fills empty slots with bots.
		c.map_name = DEFAULT_MAP
		c.bots = c.mode == Mode.DEDICATED
	elif not map_given and c.mode == Mode.OFFLINE \
			and not (c.autofire or c.debug_skill_demo or c.debug_squad_demo):
		# Default launch (no arguments): a playable 5v5 Shardline Front match vs bots.
		c.map_name = DEFAULT_MAP
		c.bots = true
	if c.mode == Mode.CLIENT and c.port == 0:
		c.port = DEFAULT_PORT
	return c
