class_name MatchSupervisor
extends RefCounted
## Runs one headless match process per match (W17, design/gdd/matchmaking.md
## "Server architecture"). Lives in the front process; call tick(now) often.
##
## Lifecycle per process:  STARTING -> READY -> ALLOCATED -> DRAINING -> SHUTDOWN
## - STARTING: spawned with a boot file; becomes READY on its READY message.
## - READY: in the warm pool (1-2 kept), waiting for a match.
## - ALLOCATED: got a match setup; match_started fires once it confirms.
## - DRAINING: result reported (or a drain/retire asked it to stop); exiting.
## - SHUTDOWN: gone; its port is free again.
## A process that dies, misses heartbeats or never confirms its setup is killed;
## its match (if any, and without a result) is VOIDED: no rating change, the
## front tells the players and re-queues them (match_voided).
##
## Versions: every process is tagged with the build that spawned it. Only
## processes of the current build get new matches; set_build() retires idle
## old ones while running matches finish on the old build.
## Drain (SIGTERM via the drain file, or begin_drain()): no new matches, idle
## processes stop, running matches finish, anything left at the deadline is
## killed and voided; then `drained` fires.
## Collaborators are injected (launcher, channel, files) so tests run in memory.

signal process_ready(slot: int)
signal match_started(match_id: String, endpoint: Dictionary)
signal match_result(match_id: String, result: Dictionary)
signal match_voided(match_id: String, reason: String)
signal abandon_reported(match_id: String, account_id: String)
signal drained

enum State { STARTING, READY, ALLOCATED, DRAINING, SHUTDOWN }

const STATE_NAMES := ["starting", "ready", "allocated", "draining", "shutdown"]
## Seconds between drain-file checks and health-file writes.
const HOUSEKEEPING_S := 2.0


class Proc:
	var slot: int
	var pid: int = -1
	var port: int
	var build: String
	var state: int = State.STARTING
	var state_since: float
	var last_seen: float
	var secret: PackedByteArray
	var ticket_kid: String
	var boot_path: String = ""
	var setup_path: String = ""
	var match_id: String = ""
	var setup: Dictionary = {}
	var setup_acked: bool = false
	var result_in: bool = false
	var chan_ip: String = ""
	var chan_port: int = 0
	var rx_seq: int = 0


var config: HostingConfig
var launcher: MatchProcessLauncher
var channel: Variant  # HostChannelUdp or a test fake
var files: MatchHostFiles
var keys: TicketKeyRing
var ports: MatchPortPool
var draining: bool = false
var drain_deadline: float = 0.0
## Log lines go here (print by default). Never receives secrets.
var log_fn: Callable = func(line: String) -> void: print(line)

var _procs: Dictionary = {}  # slot -> Proc
var _pending: Array = []  # match setups waiting for a Ready process (FIFO)
var _next_slot: int = 1
var _tx_seq: int = 0
var _zombies: Array = []  # killed pids still to be reaped
var _housekeeping: float = 0.0
var _drained_sent: bool = false
var _crypto := Crypto.new()


func _init(config_: HostingConfig, launcher_: MatchProcessLauncher, channel_: Variant,
		files_: MatchHostFiles, keys_: TicketKeyRing) -> void:
	config = config_
	launcher = launcher_
	channel = channel_
	files = files_
	keys = keys_
	ports = MatchPortPool.new(config.port_first, config.port_last)


# --- Front API -----------------------------------------------------------------

## Queues a match. OK, ERR_UNAVAILABLE while draining, ERR_BUSY at capacity,
## ERR_INVALID_DATA for a bad setup, ERR_ALREADY_EXISTS for a known match id.
func request_match(setup: Dictionary) -> Error:
	if draining:
		return ERR_UNAVAILABLE
	if MatchSetup.validate(setup) != "":
		return ERR_INVALID_DATA
	if find_match(str(setup.match_id)) != null or _pending.any(func(s: Dictionary) -> bool: return s.match_id == setup.match_id):
		return ERR_ALREADY_EXISTS
	if _allocated_count() + _pending.size() >= config.capacity():
		return ERR_BUSY
	_pending.append(setup.duplicate(true))
	return OK


## A fresh join ticket for a player of a running match (first join and every
## reconnect): {host, port, ticket}, or {} when the match is not running or the
## account is not on its roster. Signed with the key its process was started with.
func issue_join_ticket(match_id: String, account_id: String, now_unix: float) -> Dictionary:
	var p := find_match(match_id)
	if p == null or p.state != State.ALLOCATED or not p.setup_acked or p.result_in:
		return {}
	if not MatchSetup.has_account(p.setup, account_id):
		return {}
	var t := JoinTicket.sign(keys, account_id, match_id, now_unix, config.ticket_ttl_s, p.ticket_kid)
	if t == "":
		return {}
	return {"host": config.public_host, "port": p.port, "ticket": t}


## Starts a graceful drain (SIGTERM, patch): stop allocating, stop idle
## processes, let running matches finish within `max_s` (-1 = config).
func begin_drain(now: float, max_s: float = -1.0) -> void:
	if draining:
		return
	draining = true
	drain_deadline = now + (config.drain_max_s if max_s < 0.0 else max_s)
	for s: Dictionary in _pending:
		match_voided.emit(str(s.match_id), "draining")
	_pending.clear()
	_log("[hosting] drain started: %d match(es) running, deadline in %.0f s" % [_allocated_count(), drain_deadline - now])
	for p: Proc in _procs.values():
		if p.state == State.STARTING or p.state == State.READY:
			_retire(p, now)
		elif p.state == State.ALLOCATED:
			_send(p, HostChannelCodec.OP_DRAIN, {})


## Deploy: new matches go to processes of `version` (started by `launcher_`,
## when given). Idle processes of other builds are retired; running ones finish.
func set_build(version: String, now: float, launcher_: MatchProcessLauncher = null) -> void:
	config.build_version = version
	if launcher_ != null:
		launcher = launcher_
	for p: Proc in _procs.values():
		if p.build != version and (p.state == State.STARTING or p.state == State.READY):
			_retire(p, now)
	_log("[hosting] build is now %s" % version)


## True when a client of `version` may play (the front refuses old builds).
func is_current_build(version: String) -> bool:
	return version == config.build_version


## Kills every process now (front exiting without a drain). Running matches void.
func shutdown_now(reason: String = "shutdown") -> void:
	for p: Proc in _procs.values():
		_kill_and_finish(p, reason)


## Anonymous counts for the health file and the operator (no player data).
func status() -> Dictionary:
	var by_state := {}
	for n in STATE_NAMES:
		by_state[n] = 0
	for p: Proc in _procs.values():
		by_state[STATE_NAMES[p.state]] += 1
	return {"build": config.build_version, "capacity": config.capacity(), "pending": _pending.size(),
		"draining": draining, "processes": by_state, "ports_free": ports.free_count()}


func find_match(match_id: String) -> Proc:
	for p: Proc in _procs.values():
		if p.match_id == match_id and match_id != "":
			return p
	return null


func procs() -> Array:
	return _procs.values()


func pending_count() -> int:
	return _pending.size()


# --- Main loop -------------------------------------------------------------------

func tick(now: float) -> void:
	for pkt: Dictionary in channel.poll():
		_on_packet(pkt, now)
	for pid: int in _zombies.duplicate():
		if not launcher.is_running(pid):
			_zombies.erase(pid)
	for p: Proc in _procs.values():
		_check(p, now)
	if draining and now >= drain_deadline:
		for p: Proc in _procs.values():
			_kill_and_finish(p, "drain_timeout")
	_allocate(now)
	_refill(now)
	_housekeep(now)
	if draining and _procs.is_empty() and not _drained_sent:
		_drained_sent = true
		_log("[hosting] drain finished")
		drained.emit()


func _check(p: Proc, now: float) -> void:
	if not launcher.is_running(p.pid):
		_finish(p, "process_exit" if p.state != State.DRAINING else "exited")
		return
	match p.state:
		State.STARTING:
			if now - p.state_since > config.start_timeout_s:
				_kill_and_finish(p, "start_timeout")
				return
		State.ALLOCATED:
			if not p.setup_acked and now - p.state_since > config.allocate_timeout_s:
				_kill_and_finish(p, "allocate_timeout")
				return
		State.DRAINING:
			if p.match_id == "" or p.result_in:
				if now - p.state_since > config.exit_grace_s:
					_kill_and_finish(p, "exit_timeout")
					return
	if p.state != State.STARTING and now - p.last_seen > config.heartbeat_timeout_s:
		_kill_and_finish(p, "heartbeat_lost")


func _on_packet(pkt: Dictionary, now: float) -> void:
	var data: PackedByteArray = pkt.data
	var p: Proc = _procs.get(HostChannelCodec.peek_slot(data))
	if p == null:
		return
	var m := HostChannelCodec.decode(data, p.secret)
	if m.is_empty() or int(m.seq) <= p.rx_seq or int(m.op) >= HostChannelCodec.OP_ALLOCATE:
		return
	if p.chan_port == 0:
		p.chan_ip = str(pkt.ip)
		p.chan_port = int(pkt.port)
	elif p.chan_port != int(pkt.port):
		return  # a second sender claiming this slot
	p.rx_seq = int(m.seq)
	p.last_seen = now
	var pl: Dictionary = m.payload
	match int(m.op):
		HostChannelCodec.OP_READY:
			if p.state == State.STARTING:
				var reported := str(pl.get("build", ""))
				if reported != "" and reported != p.build:
					_log("[hosting] slot %d reports build %s (spawned as %s)" % [p.slot, reported, p.build])
					p.build = reported.left(32)
				_set_state(p, State.READY, now)
				process_ready.emit(p.slot)
				if draining or p.build != config.build_version:
					_retire(p, now)
		HostChannelCodec.OP_ALLOCATED:
			if p.state == State.ALLOCATED and not p.setup_acked and str(pl.get("match_id", "")) == p.match_id:
				p.setup_acked = true
				_log("[hosting] match %s running on port %d (slot %d)" % [p.match_id, p.port, p.slot])
				match_started.emit(p.match_id, {"host": config.public_host, "port": p.port})
		HostChannelCodec.OP_RESULT, HostChannelCodec.OP_VOID:
			if p.match_id == "" or str(pl.get("match_id", "")) != p.match_id:
				return
			_send(p, HostChannelCodec.OP_RESULT_ACK, {"match_id": p.match_id})
			if p.result_in:
				return  # a resend after a lost ack
			p.result_in = true
			if int(m.op) == HostChannelCodec.OP_RESULT:
				_log("[hosting] match %s result received" % p.match_id)
				match_result.emit(p.match_id, pl)
			else:
				_log("[hosting] match %s voided by its process (%s)" % [p.match_id, str(pl.get("reason", "")).left(64)])
				match_voided.emit(p.match_id, "process:" + str(pl.get("reason", "")).left(64))
			_set_state(p, State.DRAINING, now)
		HostChannelCodec.OP_ABANDON:
			var acc := str(pl.get("account", ""))
			if p.match_id != "" and MatchSetup.has_account(p.setup, acc):
				abandon_reported.emit(p.match_id, acc)
		HostChannelCodec.OP_BYE:
			if p.state != State.DRAINING:
				_set_state(p, State.DRAINING, now)


func _allocate(now: float) -> void:
	while not _pending.is_empty():
		var p := _ready_proc()
		if p == null:
			return
		var setup: Dictionary = _pending.pop_front()
		p.match_id = str(setup.match_id)
		p.setup = setup
		p.setup_path = files.write_secure("setup-%d.json" % p.slot, setup)
		if p.setup_path == "":
			_log("[hosting] cannot write the setup file for match %s" % p.match_id)
			_kill_and_finish(p, "setup_write_failed")
			continue
		_set_state(p, State.ALLOCATED, now)
		_send(p, HostChannelCodec.OP_ALLOCATE, {"match_id": p.match_id, "path": p.setup_path})


func _ready_proc() -> Proc:
	var best: Proc = null
	for p: Proc in _procs.values():
		if p.state == State.READY and p.build == config.build_version and (best == null or p.slot < best.slot):
			best = p
	return best


func _refill(now: float) -> void:
	if draining:
		return
	var idle := 0
	for p: Proc in _procs.values():
		if (p.state == State.STARTING or p.state == State.READY) and p.build == config.build_version:
			idle += 1
	var want := config.warm_pool + _pending.size()
	while idle < want and _procs.size() < config.capacity():
		if not _spawn(now):
			return
		idle += 1


func _spawn(now: float) -> bool:
	var port := ports.acquire()
	if port == 0:
		return false
	var p := Proc.new()
	p.slot = _next_slot
	_next_slot += 1
	p.port = port
	p.build = config.build_version
	p.secret = _crypto.generate_random_bytes(32)
	p.ticket_kid = keys.active_kid
	p.state_since = now
	p.last_seen = now
	p.boot_path = files.write_secure("boot-%d.json" % p.slot, {
		"v": 1, "slot": p.slot, "port": port, "bind_host": config.bind_host,
		"channel_port": channel.local_port(), "channel_secret": p.secret.hex_encode(),
		"build": p.build, "heartbeat_s": config.heartbeat_interval_s,
		"ticket_kid": p.ticket_kid, "ticket_key": keys.key_for(p.ticket_kid).hex_encode(),
		"ticket_max_ttl_s": config.ticket_ttl_s * 2.0,
	})
	if p.boot_path == "":
		ports.release(port)
		_log("[hosting] cannot write a boot file; spawn skipped")
		return false
	p.pid = launcher.spawn(PackedStringArray(["--server", "--port", str(port), "--host-boot", p.boot_path]))
	if p.pid <= 0:
		ports.release(port)
		files.remove(p.boot_path)
		_log("[hosting] spawn failed (port %d)" % port)
		return false
	_procs[p.slot] = p
	_log("[hosting] slot %d starting: pid %d, port %d, build %s" % [p.slot, p.pid, port, p.build])
	return true


func _retire(p: Proc, now: float) -> void:
	_send(p, HostChannelCodec.OP_SHUTDOWN, {})
	_set_state(p, State.DRAINING, now)


func _kill_and_finish(p: Proc, reason: String) -> void:
	launcher.kill(p.pid)
	_zombies.append(p.pid)
	_finish(p, reason)


## Ends a record: void its match when no result came, free the port.
func _finish(p: Proc, reason: String) -> void:
	if not _procs.has(p.slot):
		return
	_procs.erase(p.slot)
	files.remove(p.boot_path)
	files.remove(p.setup_path)
	ports.release(p.port)
	p.state = State.SHUTDOWN
	_log("[hosting] slot %d shut down (%s), port %d free" % [p.slot, reason, p.port])
	if p.match_id != "" and not p.result_in:
		_log("[hosting] match %s VOID (%s)" % [p.match_id, reason])
		match_voided.emit(p.match_id, reason)


func _set_state(p: Proc, s: int, now: float) -> void:
	p.state = s
	p.state_since = now


func _send(p: Proc, op: int, payload: Dictionary) -> void:
	if p.chan_port == 0:
		return
	_tx_seq += 1
	channel.send_to(p.chan_ip, p.chan_port, HostChannelCodec.encode(op, p.slot, _tx_seq, payload, p.secret))


func _allocated_count() -> int:
	var n := 0
	for p: Proc in _procs.values():
		if p.state == State.ALLOCATED or (p.state == State.DRAINING and p.match_id != "" and not p.result_in):
			n += 1
	return n


func _housekeep(now: float) -> void:
	if now - _housekeeping < HOUSEKEEPING_S:
		return
	_housekeeping = now
	if not draining and config.drain_file != "" and files.exists(config.drain_file):
		_log("[hosting] drain requested (%s)" % config.drain_file)
		begin_drain(now)
	if config.health_file != "":
		var st := status()
		st["updated"] = int(Time.get_unix_time_from_system())
		files.write_atomic(config.health_file, JSON.stringify(st))


func _log(line: String) -> void:
	log_fn.call(line)
