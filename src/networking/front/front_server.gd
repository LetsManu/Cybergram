class_name FrontServer
extends RefCounted
## The front process's connection loop (W17B, `--front`): one UDP port
## (7777) for accounts, friends, parties (AccountService) and matchmaking
## (MatchmakingFront). No match runs here: matches run in match processes
## owned by the MatchSupervisor.
##
## Server authoritative: unknown or malformed packets count as violations;
## a peer over MAX_VIOLATIONS is ignored. Matchmaking requests are rate
## limited per peer (token bucket). Logs carry peer numbers only.
##
## P1: an optional operations endpoint (OpsHttpServer: /health, /metrics,
## /admin) when CYBERGRAM_OPS_PORT is set, and the main-loop time per frame
## for /metrics.
##
## Example (GameSession, front mode):
##   front_server = FrontServer.new(enet, accounts, front)
##   front_server.step(delta)   # every physics frame

const MAX_VIOLATIONS := 10
const MAX_VIOLATION_LOGS := 3
## Matchmaking request budget per peer: burst and refill per second.
const MM_BURST := 12.0
const MM_PER_S := 4.0

var transport: Transport
var accounts: AccountService
var front: MatchmakingFront
var _violations: Dictionary = {}  # peer -> count
var _budget: Dictionary = {}      # peer -> [tokens, last time]
var _now: float = 0.0
var _status := LobbyStatusWriter.new()
## W20-WEB: the website's public snapshot (CYBERGRAM_PUBLIC_DIR; off when unset).
var public_snapshot := PublicSnapshot.new()
## P1: /health, /metrics, /admin (off unless CYBERGRAM_OPS_PORT is set).
var ops := OpsHttpServer.new()
## Build label for /health (GameSession sets it from HostingConfig).
var build_version: String = "dev"
## Extra readiness checks: name -> func() -> bool (GameSession adds the supervisor).
var ready_checks: Dictionary = {}
var _tick_ms_last: float = 0.0
var _tick_ms_max: float = 0.0
## Refused connections by reason (/metrics + rate-limited log, docs/connecting.md).
## Hooked into the engine log only on a DTLS transport (handshake failures).
var rejects := ConnectionRejects.new()


func _init(t: Transport, accounts_: AccountService, front_: MatchmakingFront) -> void:
	transport = t
	accounts = accounts_
	front = front_
	if t.has_signal("peer_disconnected"):
		t.connect("peer_disconnected", on_peer_left)
	accounts.rejected.connect(func(peer: int, reason: String) -> void:
		rejects.note(reason, transport.peer_address(peer)))
	if t is ENetTransport and (t as ENetTransport).is_secure:
		OS.add_logger(rejects)
	ops.health = health_snapshot
	ops.metrics = func() -> String: return metrics_text()
	ops.admin = func() -> Dictionary: return admin_snapshot()
	ops.accounts = func() -> Dictionary: return accounts_snapshot()


## Starts the operations endpoint from the environment (CYBERGRAM_OPS_PORT).
func start_ops() -> bool:
	if not ops.listen_from_env():
		return false
	front._ev(OpsLog.INFO, "ops_listen", "ops endpoint on TCP %d (/health, /metrics%s)" % [ops.port(),
		", /admin" if ops.admin_token != "" else ""])
	return true


func step(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_now += delta
	accounts.step(delta)
	transport.poll()
	var pkt := transport.pop_packet()
	while pkt != null:
		_handle(pkt)
		pkt = transport.pop_packet()
	front.step()
	rejects.flush(front.metrics, _now)
	_status.tick(delta, accounts.peers.size(), false, 0)
	public_snapshot.tick(delta, front, accounts.peers.size())
	_tick_ms_last = (Time.get_ticks_usec() - t0) / 1000.0
	_tick_ms_max = maxf(_tick_ms_max, _tick_ms_last)
	ops.poll()


## /health: readiness of this front (accounts, transport, supervisor checks).
func health_snapshot() -> Dictionary:
	var checks := {"transport": transport != null, "accounts": accounts != null}
	for k in ready_checks:
		checks[k] = bool((ready_checks[k] as Callable).call())
	var ready := true
	for k in checks:
		ready = ready and bool(checks[k])
	return {"ready": ready, "version": build_version, "protocol": MsgType.PROTOCOL_VERSION,
		"uptime_s": int(front.now() - front.started_at), "clients": accounts.peers.size(), "checks": checks}


## /metrics: the front's metrics plus connection and main-loop numbers.
func metrics_text() -> String:
	var m := front.metrics
	m.describe("cybergram_connected_clients", "gauge", "Connections with a login or guest session.")
	m.describe("cybergram_front_tick_ms", "gauge", "Main-loop time of the last frame (ms).")
	m.describe("cybergram_front_tick_ms_max", "gauge", "Longest main-loop frame since the last scrape (ms).")
	m.describe("cybergram_protocol_violations", "gauge", "Peers with at least one malformed packet right now.")
	m.describe(ConnectionRejects.METRIC, "counter",
		"Refused connections by reason: plain_udp, bad_certificate, handshake_other, version_mismatch, auth.")
	m.set_gauge("cybergram_connected_clients", float(accounts.peers.size()))
	m.set_gauge("cybergram_front_tick_ms", _tick_ms_last)
	m.set_gauge("cybergram_front_tick_ms_max", _tick_ms_max)
	m.set_gauge("cybergram_protocol_violations", float(_violations.size()))
	m.set_gauge("cybergram_build_info", 1.0, {"version": build_version, "protocol": str(MsgType.PROTOCOL_VERSION)})
	_tick_ms_max = 0.0
	return front.render_metrics()


## /admin: the front's live state plus health.
func admin_snapshot() -> Dictionary:
	var a := front.admin_snapshot()
	a.health = health_snapshot()
	return a


## Rows shown on /admin/accounts at most (the total is always given).
const ACCOUNTS_PAGE_MAX := 1000


## /admin/accounts: registered accounts, newest first. Username, display name,
## created and last login (UTC), the live phase and the log tag (OpsLog.tag, to
## match log lines). Never passwords, recovery codes, friends or addresses;
## never logged (owner request 2026-10-06; the operator's own admin view).
func accounts_snapshot() -> Dictionary:
	var rows: Array = []
	var store: AccountStore = accounts.store
	if store == null:
		return {"total": 0, "shown": 0, "rows": rows}
	for id in store.ids():
		var a := store.get_by_id(id)
		if a.is_empty():
			continue
		rows.append(a)
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return int(x.get("created_at", 0)) > int(y.get("created_at", 0)))
	var out: Array = []
	for a: Dictionary in rows.slice(0, ACCOUNTS_PAGE_MAX):
		var id := str(a.id)
		var ph := front.phases.players.state_of(id)
		out.append({"created": _utc(a.get("created_at", 0)), "username": str(a.get("username", "")),
			"display_name": str((a.get("profile", {}) as Dictionary).get("display_name", "")),
			"last_login": _utc(a.get("last_login_at", 0)),
			"phase": PhaseMachine.name_of(PhaseMachine.Kind.PLAYER, ph), "player": OpsLog.tag(id)})
	return {"total": rows.size(), "shown": out.size(), "rows": out}


static func _utc(unix: Variant) -> String:
	var u := int(unix)
	return Time.get_datetime_string_from_unix_time(u, true) + "Z" if u > 0 else ""


func on_peer_left(peer: int) -> void:
	front.on_peer_left(peer)
	accounts.on_disconnect(peer)
	_violations.erase(peer)
	_budget.erase(peer)


func _handle(pkt: Transport.Packet) -> void:
	var peer := pkt.from_peer
	if int(_violations.get(peer, 0)) > MAX_VIOLATIONS:
		return
	if pkt.data.is_empty() or pkt.data.size() > LobbyCodec.MAX_C2S_BYTES:
		_violation(peer, "bad packet size %d" % pkt.data.size())
		return
	match pkt.data.decode_u8(0):
		MsgType.ACCOUNT_REQ:
			accounts.handle(transport, peer, pkt.data)
		MsgType.MM_REQ:
			if not _allow(peer):
				return
			if not front.handle(peer, pkt.data):
				_violation(peer, "malformed matchmaking request")
		MsgType.LOBBY_JOIN:
			# An old-style lobby client: this server has no in-process lobby.
			var j := LobbyCodec.decode_join(pkt.data)
			if j.is_empty() or j.get("legacy", false) or j.protocol_version != MsgType.PROTOCOL_VERSION:
				transport.send(peer, Transport.CH_CONTROL, ControlCodec.encode_reject(MsgType.REJECT_PROTOCOL_MISMATCH))
		MsgType.LOBBY_PICK, MsgType.LOBBY_TEAM, MsgType.LOBBY_CHAT_SEND:
			pass
		_:
			_violation(peer, "unknown message %d" % pkt.data.decode_u8(0))


func _allow(peer: int) -> bool:
	var b: Array = _budget.get_or_add(peer, [MM_BURST, _now])
	b[0] = minf(MM_BURST, float(b[0]) + (_now - float(b[1])) * MM_PER_S)
	b[1] = _now
	if float(b[0]) < 1.0:
		return false
	b[0] = float(b[0]) - 1.0
	return true


func _violation(peer: int, what: String) -> void:
	var n := int(_violations.get(peer, 0)) + 1
	_violations[peer] = n
	if n <= MAX_VIOLATION_LOGS:
		front._ev(OpsLog.WARN, "violation", "peer %d: %s (violation %d)" % [peer, what, n])
	elif n == MAX_VIOLATIONS + 1:
		front._ev(OpsLog.WARN, "violation", "peer %d: too many violations, ignoring it" % peer)
