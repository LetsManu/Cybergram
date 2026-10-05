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


func _init(t: Transport, accounts_: AccountService, front_: MatchmakingFront) -> void:
	transport = t
	accounts = accounts_
	front = front_
	if t.has_signal("peer_disconnected"):
		t.connect("peer_disconnected", on_peer_left)


func step(delta: float) -> void:
	_now += delta
	accounts.step(delta)
	transport.poll()
	var pkt := transport.pop_packet()
	while pkt != null:
		_handle(pkt)
		pkt = transport.pop_packet()
	front.step()
	_status.tick(delta, accounts.peers.size(), false, 0)
	public_snapshot.tick(delta, front, accounts.peers.size())


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
		print("[front] peer %d: %s (violation %d)" % [peer, what, n])
	elif n == MAX_VIOLATIONS + 1:
		print("[front] peer %d: too many violations, ignoring it" % peer)
