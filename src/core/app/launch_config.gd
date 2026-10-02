class_name LaunchConfig
extends RefCounted
## Parsed command line (architecture.md §2.1). Only AppRoot builds one; nothing
## else reads OS arguments.
##   godot --path .                              -> OFFLINE
##   godot --path . -- --net-sim 100ms_2pct      -> OFFLINE through a conditioned loopback
##   godot --headless --path . [-- --server]     -> DEDICATED (server only)
##   ... -- --server --quit-after-ticks 900      -> soak run that exits
##   godot --path . -- --map slice               -> load assets/data/match/map_<name>_lane.tres
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
##   ... -- --bots                               -> E11: player + 9 bots, 5v5 on the slice map
##   godot --headless --fixed-fps 30 --path . -- --server --bots-only --seed 3 [--match-clock 4]
##                                                -> E11: 10 bots play to End, JSON summary, quit
##   ... -- --bot-difficulty easy|normal|hard    -> E11: bot profile (default normal)
##   ... -- --bots --bot-player                  -> E11 debug: a bot also plays the local hero
##   ... -- --debug-skill-demo                   -> debug: the local hero casts its skills on a
##                                                  schedule (E10 evidence)
##   ... -- --map slice --debug-level 7          -> debug: the local hero starts at level 7 with
##                                                  skills learned and points banked (E15 evidence)
##   ... -- --map slice --debug-armory           -> debug: spawn on the Armory pad with Lumen,
##                                                  mounts bought, Armory panel open (E13 evidence)

enum Mode { OFFLINE, DEDICATED }

var mode: Mode = Mode.OFFLINE
var net_sim_name: String = ""
var quit_after_ticks: int = 0
## Map id stem ("" = the session scene's default map). Resolved by the session.
var map_name: String = ""
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
## E11 bots: --bots (player + 9 bots), --bots-only (10 bots, no player; with
## --server the match runs to End and prints a JSON summary), --seed, --bot-difficulty.
var bots: bool = false
var bots_only: bool = false
var match_seed: int = 1
var bot_difficulty: String = ""
## E11 debug (evidence captures): a bot drives the local player's hero too.
var bot_player: bool = false


static func parse(args: PackedStringArray, headless: bool) -> LaunchConfig:
	var c := LaunchConfig.new()
	if headless:
		c.mode = Mode.DEDICATED
	var i := 0
	while i < args.size():
		match args[i]:
			"--server":
				c.mode = Mode.DEDICATED
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
	if (c.bots or c.bots_only) and c.map_name == "":
		c.map_name = "slice"  # E11: bot matches run on the slice map
	return c
