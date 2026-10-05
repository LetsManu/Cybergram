extends SceneTree
## Stand-in match process (W17 phase A): runs only the MatchHostAgent, no game.
## Used by the supervisor proof and for dry runs of the hosting setup until
## phase B wires the agent into the real dedicated server:
##   godot --headless --path . -s res://src/networking/hosting/match_host_stub.gd -- --host-boot <file>
## On allocation it "plays" for setup.rules.stub_match_s seconds (default 3),
## reports a result with zeroed stats and exits once the result is acknowledged.

var agent: MatchHostAgent
var match_end_at: float = -1.0


func _initialize() -> void:
	agent = MatchHostAgent.from_cmdline(OS.get_cmdline_user_args())
	if agent == null:
		printerr("[stub] no --host-boot: not started by a supervisor")
		quit(2)
		return
	agent.allocated.connect(_on_allocated)
	agent.mark_ready()
	print("[stub] slot %d ready on port %d (build %s)" % [int(agent.boot.slot), agent.port(), agent.build()])


func _on_allocated(setup: Dictionary) -> void:
	var secs := float(setup.get("rules", {}).get("stub_match_s", 3.0))
	match_end_at = _now() + secs
	print("[stub] match %s started, ends in %.0f s" % [str(setup.match_id), secs])


func _process(_delta: float) -> bool:
	if agent == null:
		return true
	agent.tick(_now())
	if match_end_at > 0.0 and _now() >= match_end_at:
		match_end_at = -1.0
		var players := []
		for e: Dictionary in agent.setup.roster:
			if not bool(e.get("bot", false)):
				players.append({"account": e.account, "team": int(e.team), "kills": 0, "deaths": 0, "assists": 0})
		agent.report_result(0, players)
	if agent.should_exit():
		agent.close()
		print("[stub] slot %d exiting" % int(agent.boot.slot))
		return true
	return false


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
