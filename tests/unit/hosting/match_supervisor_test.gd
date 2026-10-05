extends GdUnitTestSuite
## W17-SUP MatchSupervisor + MatchHostAgent, all in memory: lifecycle
## transitions, warm pool refill, port reuse, capacity, crash/heartbeat void,
## graceful drain, version routing, join tickets and channel authentication.

const FakeFiles := preload("res://tests/unit/hosting/fakes/fake_host_files.gd")
const FakeNet := preload("res://tests/unit/hosting/fakes/fake_host_net.gd")
const FakeLauncher := preload("res://tests/unit/hosting/fakes/fake_process_launcher.gd")
const S := MatchSupervisor.State
const KEY_HEX := "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
const ACC_A := "0123456789abcdef0123456789abcdef"
const ACC_B := "fedcba9876543210fedcba9876543210"
const ACC_X := "11111111111111111111111111111111"

var files: FakeFiles
var net: FakeNet
var launcher: FakeLauncher
var sup: MatchSupervisor
var agents: Dictionary = {}  # pid -> MatchHostAgent
var now: float = 0.0
var events: Array = []


func _make(cfg_env: Dictionary = {}, warm: int = 1, max_matches: int = 4) -> void:
	files = FakeFiles.new()
	net = FakeNet.new()
	launcher = FakeLauncher.new()
	var env := {"CYBERGRAM_MATCH_PORTS": "7800-7803", "CYBERGRAM_WARM_POOL": str(warm),
		"CYBERGRAM_MAX_MATCHES": str(max_matches), "CYBERGRAM_BUILD_VERSION": "v1",
		"CYBERGRAM_PUBLIC_HOST": "play.example.net"}
	env.merge(cfg_env, true)
	var cfg := HostingConfig.from_env(env, 4)
	sup = MatchSupervisor.new(cfg, launcher, net.server, files, TicketKeyRing.parse_spec("k1:" + KEY_HEX))
	sup.log_fn = func(_l: String) -> void: pass
	agents.clear()
	events.clear()
	now = 0.0
	sup.process_ready.connect(func(slot: int) -> void: events.append(["ready", slot]))
	sup.match_started.connect(func(m: String, ep: Dictionary) -> void: events.append(["started", m, ep]))
	sup.match_result.connect(func(m: String, r: Dictionary) -> void: events.append(["result", m, r]))
	sup.match_voided.connect(func(m: String, why: String) -> void: events.append(["void", m, why]))
	sup.abandon_reported.connect(func(m: String, a: String) -> void: events.append(["abandon", m, a]))
	sup.drained.connect(func() -> void: events.append(["drained"]))


## Boots an agent for every newly spawned fake process.
func _boot_new(ready: bool = true) -> void:
	for s: Dictionary in launcher.spawned:
		if agents.has(s.pid) or not launcher.running.has(s.pid):
			continue
		var b := files.read_and_delete(MatchHostAgent.boot_path_from_args(s.args))
		assert_bool(MatchHostAgent.valid_boot(b)).is_true()
		var a := MatchHostAgent.new(b, net.new_link(), files)
		agents[s.pid] = a
		if ready:
			a.mark_ready()


## Advances time; agents and supervisor exchange messages.
func _run(seconds: float, step: float = 0.25) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		now += step
		t += step
		for pid: int in agents:
			if launcher.running.has(pid):
				agents[pid].tick(now)
		sup.tick(now)
		for pid: int in agents:
			if launcher.running.has(pid):
				agents[pid].tick(now)


func _setup(id: String, accounts: Array = [ACC_A, ACC_B]) -> Dictionary:
	var roster := []
	for i in accounts.size():
		roster.append({"account": accounts[i], "team": i % 2, "hero": "vex", "lane": "mid"})
	roster.append({"account": "", "bot": true, "team": 1, "hero": "rook"})
	return {"match_id": id, "mode": "normal_5v5", "map": "lane_map", "rules": {}, "roster": roster}


func _proc_states() -> Array:
	var out := []
	for p: MatchSupervisor.Proc in sup.procs():
		out.append(p.state)
	out.sort()
	return out


func _events(kind: String) -> Array:
	return events.filter(func(e: Array) -> bool: return e[0] == kind)


func _start_one_match(id: String) -> MatchSupervisor.Proc:
	assert_int(sup.request_match(_setup(id))).is_equal(OK)
	_run(0.5)
	_boot_new()
	_run(1.0)
	return sup.find_match(id)


# --- Lifecycle ---------------------------------------------------------------------

func test_starting_then_ready_fills_warm_pool() -> void:
	_make({}, 1)
	sup.tick(0.0)
	assert_int(launcher.spawned.size()).is_equal(1)
	assert_array(_proc_states()).is_equal([S.STARTING])
	assert_array(Array(launcher.spawned[0].args)).contains(["--server", "--port", "7800", "--host-boot"])
	_boot_new()
	_run(0.5)
	assert_array(_proc_states()).is_equal([S.READY])
	assert_int(_events("ready").size()).is_equal(1)
	assert_int(launcher.spawned.size()).is_equal(1)  # pool full: no extra spawn


func test_warm_pool_of_two() -> void:
	_make({}, 2)
	sup.tick(0.0)
	assert_int(launcher.spawned.size()).is_equal(2)


func test_allocate_runs_match_and_refills_pool() -> void:
	_make({}, 1)
	sup.tick(0.0)
	_boot_new()
	_run(0.5)
	var got: Array = []
	var a: MatchHostAgent = agents.values()[0]
	a.allocated.connect(func(s: Dictionary) -> void: got.append(s))
	assert_int(sup.request_match(_setup("match0000000001"))).is_equal(OK)
	_run(0.5)
	var p := sup.find_match("match0000000001")
	assert_int(p.state).is_equal(S.ALLOCATED)
	assert_bool(p.setup_acked).is_true()
	assert_int(got.size()).is_equal(1)
	assert_str(str(got[0].roster[0].account)).is_equal(ACC_A)
	var st := _events("started")
	assert_int(st.size()).is_equal(1)
	assert_dict(st[0][2]).is_equal({"host": "play.example.net", "port": 7800})
	# The setup file is gone after the process read it.
	assert_bool(files.exists(p.setup_path)).is_false()
	# The pool is refilled with a new Ready process on the next port.
	assert_int(launcher.spawned.size()).is_equal(2)
	assert_array(Array(launcher.spawned[1].args)).contains(["7801"])


func test_result_then_drain_then_shutdown_frees_port() -> void:
	_make({}, 0)
	var p := _start_one_match("match0000000002")
	var a: MatchHostAgent = agents[p.pid]
	a.report_abandon(ACC_B)
	a.report_result(0, [{"account": ACC_A, "team": 0, "kills": 3}], [ACC_B])
	_run(0.5)
	assert_int(_events("abandon").size()).is_equal(1)
	var r := _events("result")
	assert_int(r.size()).is_equal(1)
	assert_int(int(r[0][2].winner)).is_equal(0)
	assert_int(p.state).is_equal(S.DRAINING)
	assert_bool(a.should_exit()).is_true()
	assert_int(_events("void").size()).is_equal(0)
	launcher.end(p.pid)  # clean exit
	_run(0.25)
	assert_int(sup.procs().size()).is_equal(0)
	assert_int(sup.ports.used_count()).is_equal(0)
	assert_int(_events("void").size()).is_equal(0)


func test_result_resent_until_acked_and_counted_once() -> void:
	_make({}, 0)
	var p := _start_one_match("match0000000003")
	var a: MatchHostAgent = agents[p.pid]
	a.report_result(1, [])
	net.server.inbox.clear()
	a.tick(now + 0.01)  # sent
	var first: Array = net.server.poll()  # lost on the way
	assert_int(first.size()).is_greater(0)
	_run(1.0)
	assert_int(_events("result").size()).is_equal(1)
	assert_bool(a.report_acked).is_true()


func test_crash_voids_match_and_frees_port() -> void:
	_make({}, 0)
	var p := _start_one_match("match0000000004")
	launcher.end(p.pid)  # script error / segfault
	_run(0.25)
	var v := _events("void")
	assert_int(v.size()).is_equal(1)
	assert_array(v[0]).is_equal(["void", "match0000000004", "process_exit"])
	assert_bool(sup.ports.in_use(p.port)).is_false()
	assert_int(sup.issue_join_ticket("match0000000004", ACC_A, 1000.0).size()).is_equal(0)


func test_missed_heartbeat_kills_and_voids() -> void:
	_make({}, 0)
	var p := _start_one_match("match0000000005")
	net.links.values()[0].muted = true  # process hangs: no more heartbeats
	_run(sup.config.heartbeat_timeout_s + 1.0)
	assert_array(launcher.killed).contains([p.pid])
	assert_int(_events("void").size()).is_equal(1)
	assert_str(_events("void")[0][2]).is_equal("heartbeat_lost")


func test_start_timeout_kills_and_respawns() -> void:
	_make({}, 1)
	sup.tick(0.0)
	_boot_new(false)  # never says Ready
	_run(sup.config.start_timeout_s + 1.0)
	assert_int(launcher.killed.size()).is_greater_equal(1)
	assert_int(launcher.spawned.size()).is_greater_equal(2)
	assert_int(_events("void").size()).is_equal(0)  # no match was on it


func test_allocate_timeout_voids() -> void:
	_make({}, 1)
	sup.tick(0.0)
	_boot_new()
	_run(0.5)
	var a: MatchHostAgent = agents.values()[0]
	a.files = FakeFiles.new()  # the process cannot read its setup: never confirms
	assert_int(sup.request_match(_setup("match0000000006"))).is_equal(OK)
	_run(sup.config.allocate_timeout_s + 1.0)
	assert_str(a.match_id()).is_empty()
	var v := _events("void")
	assert_int(v.size()).is_equal(1)
	assert_array(v[0]).is_equal(["void", "match0000000006", "allocate_timeout"])
	assert_int(_events("started").size()).is_equal(0)


func test_spawn_failure_releases_port() -> void:
	_make({}, 1)
	launcher.fail_next = true
	sup.tick(0.0)
	assert_int(sup.ports.used_count()).is_equal(0)
	sup.tick(1.0)
	assert_int(launcher.spawned.size()).is_equal(1)


# --- Ports and capacity --------------------------------------------------------

func test_freed_port_is_reused_first() -> void:
	_make({}, 2)
	sup.tick(0.0)
	assert_array([sup.ports.in_use(7800), sup.ports.in_use(7801)]).is_equal([true, true])
	var first: int = launcher.spawned[0].pid
	launcher.end(first)
	sup.tick(0.5)
	# 7800 came free and the refill took it again (not 7802).
	assert_bool(sup.ports.in_use(7802)).is_false()
	assert_array(Array(launcher.spawned[2].args)).contains(["7800"])


func test_capacity_cap() -> void:
	_make({}, 1, 2)
	assert_int(sup.config.capacity()).is_equal(2)
	assert_int(sup.request_match(_setup("match00000000a1"))).is_equal(OK)
	assert_int(sup.request_match(_setup("match00000000a2"))).is_equal(OK)
	assert_int(sup.request_match(_setup("match00000000a3"))).is_equal(ERR_BUSY)
	sup.tick(0.0)
	assert_int(launcher.spawned.size()).is_equal(2)  # never above the cap


func test_capacity_from_cores_and_port_range() -> void:
	assert_int(HostingConfig.from_env({"CYBERGRAM_MATCH_PORTS": "7800-7899"}, 3).capacity()).is_equal(6)
	assert_int(HostingConfig.from_env({"CYBERGRAM_MATCH_PORTS": "7800-7801"}, 8).capacity()).is_equal(2)
	assert_int(HostingConfig.from_env({"CYBERGRAM_MATCH_PORTS": "7800-7899", "CYBERGRAM_MAX_MATCHES": "5"}, 8).capacity()).is_equal(5)


func test_request_validation() -> void:
	_make()
	assert_int(sup.request_match({"match_id": "x"})).is_equal(ERR_INVALID_DATA)
	assert_int(sup.request_match(_setup("match00000000b1", [ACC_A, ACC_A]))).is_equal(ERR_INVALID_DATA)
	assert_int(sup.request_match(_setup("match00000000b1"))).is_equal(OK)
	assert_int(sup.request_match(_setup("match00000000b1"))).is_equal(ERR_ALREADY_EXISTS)


# --- Drain -----------------------------------------------------------------------

func test_graceful_drain_lets_running_match_finish() -> void:
	_make({}, 1)
	var p := _start_one_match("match0000000007")
	var a: MatchHostAgent = agents[p.pid]
	_boot_new()
	_run(0.5)  # the warm process is Ready too
	sup.begin_drain(now, 600.0)
	_run(0.5)
	assert_bool(a.drain_asked).is_true()
	assert_int(sup.request_match(_setup("match0000000008"))).is_equal(ERR_UNAVAILABLE)
	# The idle process was told to stop and exits.
	for pid: int in agents:
		if pid != p.pid:
			assert_bool(agents[pid].should_exit()).is_true()
			launcher.end(pid)
	_run(0.5)
	assert_int(p.state).is_equal(S.ALLOCATED)  # still playing
	assert_int(_events("drained").size()).is_equal(0)
	a.report_result(1, [])
	_run(0.5)
	launcher.end(p.pid)
	_run(0.5)
	assert_int(_events("drained").size()).is_equal(1)
	assert_int(_events("void").size()).is_equal(0)


func test_drain_deadline_kills_and_voids() -> void:
	_make({}, 0)
	var p := _start_one_match("match0000000009")
	sup.begin_drain(now, 5.0)
	_run(6.0)
	assert_array(launcher.killed).contains([p.pid])
	assert_bool(_events("void").any(func(e: Array) -> bool: return e[2] == "drain_timeout")).is_true()
	assert_int(_events("drained").size()).is_equal(1)


func test_drain_file_starts_drain() -> void:
	_make({"CYBERGRAM_DRAIN_FILE": "/run/drain", "CYBERGRAM_HEALTH_FILE": "/run/health.json"}, 1)
	_run(2.5)
	assert_bool(sup.draining).is_false()
	assert_str(str(files.store.get("/run/health.json", ""))).contains("\"capacity\":4")
	files.flags["/run/drain"] = true
	_run(2.5)
	assert_bool(sup.draining).is_true()


func test_idle_processes_exit_on_shutdown_and_unacked_exit_is_killed() -> void:
	_make({}, 1)
	sup.tick(0.0)
	_boot_new()
	_run(0.5)
	sup.begin_drain(now, 600.0)
	_run(0.5)
	assert_array(_proc_states()).is_equal([S.DRAINING])
	# It ignores the request: killed after exit_grace_s, no void (no match).
	_run(sup.config.exit_grace_s + 1.0)
	assert_int(launcher.killed.size()).is_equal(1)
	assert_int(_events("void").size()).is_equal(0)
	assert_int(_events("drained").size()).is_equal(1)


# --- Versions ----------------------------------------------------------------

func test_version_routing() -> void:
	_make({}, 1)
	var old := _start_one_match("match0000000010")
	_boot_new()
	_run(0.5)  # a v1 warm process is Ready
	var v1_idle: int = launcher.spawned[1].pid
	sup.set_build("v2", now)
	assert_bool(sup.is_current_build("v2")).is_true()
	assert_bool(sup.is_current_build("v1")).is_false()
	_run(0.5)
	assert_bool(agents[v1_idle].shutdown_asked).is_true()
	launcher.end(v1_idle)
	_boot_new()
	_run(0.5)
	assert_int(sup.request_match(_setup("match0000000011"))).is_equal(OK)
	_run(0.5)
	var newp := sup.find_match("match0000000011")
	assert_str(newp.build).is_equal("v2")
	assert_str(old.build).is_equal("v1")
	assert_int(old.state).is_equal(S.ALLOCATED)  # finishes on the old build
	agents[old.pid].report_result(0, [])
	_run(0.5)
	assert_int(_events("result").size()).is_equal(1)


func test_ready_with_other_build_tag_is_not_used() -> void:
	_make({}, 1)
	sup.tick(0.0)
	var pid: int = launcher.spawned[0].pid
	_boot_new(false)
	agents[pid].boot.build = "v0-stale"
	agents[pid].mark_ready()
	_run(0.5)
	assert_bool(agents[pid].shutdown_asked).is_true()


# --- Tickets and channel security ----------------------------------------------

func test_join_ticket_for_roster_only_and_verified_by_process() -> void:
	_make({}, 0)
	var p := _start_one_match("match0000000012")
	var unix := 1_800_000_000.0
	var j := sup.issue_join_ticket("match0000000012", ACC_A, unix)
	assert_str(str(j.host)).is_equal("play.example.net")
	assert_int(int(j.port)).is_equal(p.port)
	var a: MatchHostAgent = agents[p.pid]
	var r := a.verify_ticket(j.ticket, unix + 1.0)
	assert_int(r.result).is_equal(JoinTicketVerifier.Result.OK)
	assert_str(r.account).is_equal(ACC_A)
	assert_int(a.verify_ticket(j.ticket, unix + 2.0).result).is_equal(JoinTicketVerifier.Result.REPLAYED)
	# Reconnect: a fresh ticket works.
	var j2 := sup.issue_join_ticket("match0000000012", ACC_A, unix + 60.0)
	assert_int(a.verify_ticket(j2.ticket, unix + 61.0).result).is_equal(JoinTicketVerifier.Result.OK)
	assert_dict(sup.issue_join_ticket("match0000000012", ACC_X, unix)).is_empty()
	assert_dict(sup.issue_join_ticket("nosuchmatch0001", ACC_A, unix)).is_empty()


func test_forged_and_replayed_packets_ignored() -> void:
	_make({}, 1)
	sup.tick(0.0)
	_boot_new(false)
	var p: MatchSupervisor.Proc = sup.procs()[0]
	var wrong := PackedByteArray()
	wrong.resize(32)
	net.server.inbox.append({"data": HostChannelCodec.encode(HostChannelCodec.OP_READY, p.slot, 1, {}, wrong),
		"ip": "127.0.0.1", "port": 5})
	sup.tick(0.1)
	assert_int(p.state).is_equal(S.STARTING)
	var good := HostChannelCodec.encode(HostChannelCodec.OP_READY, p.slot, 5, {}, p.secret)
	net.server.inbox.append({"data": good, "ip": "127.0.0.1", "port": 6})
	sup.tick(0.2)
	assert_int(p.state).is_equal(S.READY)
	var last := p.last_seen
	net.server.inbox.append({"data": HostChannelCodec.encode(HostChannelCodec.OP_HEARTBEAT, p.slot, 5, {}, p.secret),
		"ip": "127.0.0.1", "port": 6})
	sup.tick(3.0)
	assert_float(p.last_seen).is_equal(last)  # replayed seq dropped


func test_codec_roundtrip_and_tamper() -> void:
	var key := KEY_HEX.hex_decode()
	var d := HostChannelCodec.encode(HostChannelCodec.OP_RESULT, 7, 42, {"winner": 1}, key)
	var m := HostChannelCodec.decode(d, key)
	assert_int(m.op).is_equal(HostChannelCodec.OP_RESULT)
	assert_int(m.slot).is_equal(7)
	assert_int(m.seq).is_equal(42)
	assert_int(int(m.payload.winner)).is_equal(1)
	assert_int(HostChannelCodec.peek_slot(d)).is_equal(7)
	d[HostChannelCodec.HEADER] = d[HostChannelCodec.HEADER] ^ 1
	assert_dict(HostChannelCodec.decode(d, key)).is_empty()
	assert_dict(HostChannelCodec.decode(PackedByteArray([1, 2, 3]), key)).is_empty()


func test_boot_file_carries_no_secret_on_command_line() -> void:
	_make({}, 1)
	sup.tick(0.0)
	var args := " ".join(launcher.spawned[0].args)
	var p: MatchSupervisor.Proc = sup.procs()[0]
	assert_str(args).not_contains(p.secret.hex_encode())
	assert_str(args).not_contains(KEY_HEX)


func test_port_range_parse() -> void:
	assert_array(HostingConfig.parse_port_range("7800-7809")).is_equal([7800, 7809])
	assert_array(HostingConfig.parse_port_range("7800")).is_equal([7800, 7800])
	assert_array(HostingConfig.parse_port_range("80-90")).is_empty()
	assert_array(HostingConfig.parse_port_range("7809-7800")).is_empty()
	assert_array(HostingConfig.parse_port_range("a-b")).is_empty()
