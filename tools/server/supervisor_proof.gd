extends SceneTree
## W17-SUP local proof with REAL processes (not part of the unit suite):
##   godot --headless --path . -s res://tools/server/supervisor_proof.gd
## 1. warm pool of 2 headless match processes, both reach Ready;
## 2. two matches are allocated (one short, one long);
## 3. the long match's process is killed by its exact pid -> detected, voided;
## 4. the short match reports its result; a drain is requested and finishes.
## Prints RSS per process. Exit code 0 when every step was observed.

const ACC := ["0123456789abcdef0123456789abcdef", "fedcba9876543210fedcba9876543210"]

var sup: MatchSupervisor
var t0: float
var phase: int = 0
var phase_at: float = 0.0
var seen := {"ready": 0, "started": [], "result": [], "void": [], "drained": false}
var rss_log: Array = []
var killed_pid: int = -1


func _initialize() -> void:
	var cfg := HostingConfig.from_env({"CYBERGRAM_MATCH_PORTS": "47800-47809", "CYBERGRAM_WARM_POOL": "2",
		"CYBERGRAM_MAX_MATCHES": "4", "CYBERGRAM_BUILD_VERSION": "proof-1", "CYBERGRAM_PUBLIC_HOST": "127.0.0.1"})
	var stub_args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://src/networking/hosting/match_host_stub.gd"])
	var launcher := MatchProcessLauncher.new(OS.get_executable_path(), stub_args)
	var chan := HostChannelUdp.new()
	if chan.open_server(0) != OK:
		printerr("channel bind failed")
		quit(1)
		return
	var files := MatchHostFiles.new()
	files.prepare()
	sup = MatchSupervisor.new(cfg, launcher, chan, files, TicketKeyRing.generate("p1"))
	sup.log_fn = func(l: String) -> void: print("%7.2f %s" % [_now() - t0, l])
	sup.process_ready.connect(func(_s: int) -> void: seen.ready += 1)
	sup.match_started.connect(func(m: String, ep: Dictionary) -> void: seen.started.append(m); print("%7.2f [proof] started %s at %s" % [_now() - t0, m, ep]))
	sup.match_result.connect(func(m: String, r: Dictionary) -> void: seen.result.append(m); print("%7.2f [proof] result %s winner=%d players=%d" % [_now() - t0, m, int(r.winner), r.players.size()]))
	sup.match_voided.connect(func(m: String, why: String) -> void: seen.void.append([m, why]); print("%7.2f [proof] VOID %s (%s)" % [_now() - t0, m, why]))
	sup.drained.connect(func() -> void: seen.drained = true)
	t0 = _now()
	print("[proof] capacity %d, warm pool %d, cores %d" % [cfg.capacity(), cfg.warm_pool, cfg.cores])


func _setup(id: String, secs: float) -> Dictionary:
	return {"match_id": id, "mode": "normal_5v5", "map": "lane_map", "rules": {"stub_match_s": secs},
		"roster": [{"account": ACC[0], "team": 0, "hero": "vex"}, {"account": ACC[1], "team": 1, "hero": "rook"}]}


func _process(_d: float) -> bool:
	var now := _now()
	sup.tick(now)
	var el := now - t0
	match phase:
		0:
			var ready := sup.procs().filter(func(p: MatchSupervisor.Proc) -> bool: return p.state == MatchSupervisor.State.READY)
			if ready.size() >= 2:
				OS.delay_msec(500)  # let both settle before sampling memory
				for p: MatchSupervisor.Proc in ready:
					rss_log.append([p.slot, p.pid, sup.launcher.rss_kib(p.pid)])
					print("%7.2f [proof] slot %d pid %d READY, RSS %d KiB" % [el, p.slot, p.pid, rss_log[-1][2]])
				print("%7.2f [proof] step 1 OK: 2 processes Ready" % el)
				sup.request_match(_setup("proofshort000001", 4.0))
				sup.request_match(_setup("prooflong0000002", 600.0))
				_next(now)
		1:
			if seen.started.size() >= 2:
				var j := sup.issue_join_ticket("prooflong0000002", ACC[1], Time.get_unix_time_from_system())
				print("%7.2f [proof] step 2 OK: 2 matches running; join ticket for port %d issued" % [el, int(j.port)])
				var p := sup.find_match("prooflong0000002")
				killed_pid = p.pid
				print("%7.2f [proof] killing pid %d (match prooflong0000002)" % [el, killed_pid])
				OS.execute("kill", PackedStringArray(["-9", str(killed_pid)]))  # an outside crash, exact pid
				_next(now)
		2:
			if seen.void.any(func(v: Array) -> bool: return v[0] == "prooflong0000002"):
				print("%7.2f [proof] step 3 OK: crash detected and match voided" % el)
				_next(now)
		3:
			if seen.result.has("proofshort000001"):
				print("%7.2f [proof] step 4 OK: result received; requesting drain" % el)
				sup.begin_drain(now, 30.0)
				_next(now)
		4:
			if seen.drained:
				var ok: bool = seen.void.size() == 1 and seen.result.size() == 1 and sup.ports.used_count() == 0
				print("%7.2f [proof] step 5 %s: drain finished, ports in use %d, voids %d, results %d" % [
					el, "OK" if ok else "FAILED", sup.ports.used_count(), seen.void.size(), seen.result.size()])
				print("[proof] RSS per stub process (KiB): %s" % str(rss_log))
				quit(0 if ok else 1)
				return true
	if el > 120.0:
		printerr("[proof] TIMEOUT in phase %d" % phase)
		sup.shutdown_now("proof_timeout")
		quit(1)
		return true
	return false


func _next(now: float) -> void:
	phase += 1
	phase_at = now


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
