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
	return c
