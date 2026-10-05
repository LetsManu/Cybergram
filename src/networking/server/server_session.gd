class_name ServerSession
extends RefCounted
## Server end of the protocol (architecture.md §8.2/§8.3): handshake, input
## routing into per-client InputBuffers, packet validation and snapshot sending.
## Knows nothing about heroes; ServerWorld reacts to client_joined.

## A client completed Hello; the owner must call accept() or reject().
signal client_joined(peer_id: int)

## Per-connection state.
class ClientConnection:
	var peer_id: int
	var own_net_id: int = 0
	var inputs: InputBuffer
	var ack_snapshot_tick: int = 0
	var violations: int = 0
	## W16-NET: what the server sent this peer (bytes, snapshot sizes).
	var stats := SnapshotStats.new()
	## W16-NET: delta baselines and byte budget for this peer.
	var encoder: SnapshotEncoder

var transport: Transport
var net: NetConfig
var clients: Dictionary = {}  # peer id -> ClientConnection
## Hero index each joining peer asked for in Hello (ContentDB HERO, 0 = default).
var hello_hero: Dictionary = {}  # peer id -> int
## Lobby slot token each joining peer sent in Hello (0 = none).
var hello_token: Dictionary = {}  # peer id -> int
## v11: lobby slot token -> {name, id, accent} of the player it belongs to
## (filled by the session from the lobby slots, and for late joiners here).
var token_names: Dictionary = {}
## v11: net id -> {name, accent, id} of the joined human players (PLAYER_NAMES).
var names: Dictionary = {}
## Presence of the players in this match (process-wide by default).
var registry: PresenceRegistry = PresenceRegistry.shared()
## Accounts / guests (process-wide by default); identities of late joiners.
var accounts: AccountService = AccountService.shared()
var _rng := RandomNumberGenerator.new()
var _scratch: Array[InputCommand] = []
## W16-NET: print the per-client [net] line every net.stats_log_interval_s
## (GameSession turns it on for dedicated servers; off in tests).
var stats_log_enabled: bool = false
## W16-NET: records of state objects shared by every client this tick.
var _record_cache: Dictionary = {}
var _record_cache_tick: int = -1
## v17: the match mood seed sent in every Welcome (client ambience). The
## session sets it once per match (random; matchmade: from the setup).
var mood_seed: int = 0
## Microseconds spent encoding snapshots (benchmark).
var encode_usec: int = 0
var _stats_window_tick: int = -1


func _init(t: Transport, net_config: NetConfig) -> void:
	transport = t
	net = net_config


## Receives and routes every arrived packet.
func poll() -> void:
	accounts.step(net.tick_dt())
	transport.poll()
	var pkt := transport.pop_packet()
	while pkt != null:
		_handle(pkt)
		pkt = transport.pop_packet()


func accept(peer_id: int, own_net_id: int, server_tick: int) -> void:
	var c := ClientConnection.new()
	c.peer_id = peer_id
	c.own_net_id = own_net_id
	c.inputs = InputBuffer.new(net.max_buffered_inputs)
	c.encoder = SnapshotEncoder.new(net.delta_baseline_ticks, net.snapshot_budget_bytes)
	c.encoder.prioritiser = WardlingPrioritiser.new(net)
	clients[peer_id] = c
	_send(peer_id, Transport.CH_CONTROL, ControlCodec.encode_welcome(own_net_id, server_tick, net.tick_rate_hz, mood_seed))
	var who: Dictionary = token_names.get(hello_token.get(peer_id, 0), {})
	if not who.is_empty():
		names[own_net_id] = {"name": who.name, "accent": who.accent, "id": who.id}
		registry.claim(who.id, who.id, who.name)
		registry.set_status(who.id, LobbyCodec.STATUS_IN_MATCH, PresenceRegistry.now_s())
		accounts.adopt(who.id, peer_id)  # the login session lives while connected to the match
	_send_names()


## Forgets a disconnected peer: no more snapshots or events go to it. Its
## hero stays in the match, idle (a bot takeover is future work).
func drop(peer_id: int) -> void:
	var c: ClientConnection = clients.get(peer_id)
	clients.erase(peer_id)
	accounts.on_disconnect(peer_id)
	token_names.erase(hello_token.get(peer_id, 0))
	hello_token.erase(peer_id)
	hello_hero.erase(peer_id)
	if c != null and names.has(c.own_net_id):
		registry.forget(str(names[c.own_net_id].id))  # privacy: nothing kept after a disconnect
		names.erase(c.own_net_id)
		_send_names()


## PLAYER_NAMES to every joined client (reliable; sent on joins and leaves only).
func _send_names() -> void:
	if names.is_empty() and clients.is_empty():
		return
	var b := LobbyCodec.encode_player_names(names)
	for peer in clients:
		_send(peer, Transport.CH_CONTROL, b)


func reject(peer_id: int, reason: int) -> void:
	transport.send(peer_id, Transport.CH_CONTROL, ControlCodec.encode_reject(reason))


## Encodes `snap` for the peer (delta against its ack, within the budget) and sends it.
func send_snapshot(peer_id: int, snap: SnapshotData) -> void:
	var c: ClientConnection = clients.get(peer_id)
	if c == null:
		transport.send(peer_id, Transport.CH_SNAPSHOT, SnapshotCodec.encode(snap))
		return
	if snap.tick != _record_cache_tick:
		_record_cache.clear()
		_record_cache_tick = snap.tick
	var t0 := Time.get_ticks_usec()
	var b := c.encoder.encode(snap, c.ack_snapshot_tick, _record_cache)
	encode_usec += Time.get_ticks_usec() - t0
	_send(peer_id, Transport.CH_SNAPSHOT, b)
	c.stats.on_snapshot(b.size(), net.snapshot_budget_bytes, c.encoder.last.is_delta, c.encoder.last.deferred)


## Sends a reliable batch of gameplay events (no-op when empty).
func send_events(peer_id: int, tick: int, events: Array[GameEvent]) -> void:
	if events.is_empty():
		return
	_send(peer_id, Transport.CH_EVENTS, EventCodec.encode(tick, events))


## Sends and counts the bytes in the peer's SnapshotStats.
func _send(peer_id: int, channel: int, b: PackedByteArray) -> void:
	transport.send(peer_id, channel, b)
	var c: ClientConnection = clients.get(peer_id)
	if c != null:
		c.stats.on_send(channel, b.size())


## W16-NET: the per-client [net] lines for the window ending at `tick` (one per
## client, at most net.stats_log_max_lines plus one summary line), or [] when
## the interval has not elapsed. Peer ids only: no names (privacy).
func stats_lines(tick: int) -> PackedStringArray:
	var out := PackedStringArray()
	var every := maxi(1, roundi(net.stats_log_interval_s * net.tick_rate_hz))
	if _stats_window_tick < 0:
		_stats_window_tick = tick
		return out
	if tick - _stats_window_tick < every:
		return out
	var secs := (tick - _stats_window_tick) / float(net.tick_rate_hz)
	_stats_window_tick = tick
	var skipped := 0
	for peer in clients:
		var w: Dictionary = clients[peer].stats.take_window(secs)
		if out.size() < net.stats_log_max_lines:
			out.append(SnapshotStats.format_line(peer, w, transport.peer_stats(peer)))
		else:
			skipped += 1
	if skipped > 0:
		out.append("[net] ... %d more client(s) not shown (rate limit)" % skipped)
	return out


## Prints stats_lines() when logging is on (call once per tick).
func log_stats(tick: int) -> void:
	if not stats_log_enabled:
		return
	for line in stats_lines(tick):
		print(line)


func _handle(pkt: Transport.Packet) -> void:
	if pkt.data.is_empty() or pkt.data.size() > net.max_packet_bytes:
		_violation(pkt.from_peer)
		return
	match pkt.data.decode_u8(0):
		MsgType.HELLO:
			var hello := ControlCodec.decode_hello(pkt.data)
			if hello.is_empty():
				_violation(pkt.from_peer)
			elif hello.protocol_version != MsgType.PROTOCOL_VERSION:
				reject(pkt.from_peer, MsgType.REJECT_PROTOCOL_MISMATCH)
			elif not clients.has(pkt.from_peer):
				hello_hero[pkt.from_peer] = hello.hero_index
				hello_token[pkt.from_peer] = hello.token
				client_joined.emit(pkt.from_peer)
		MsgType.LOBBY_JOIN:
			# A lobby client while the match runs: tell it to join right away
			# (token 0 = take over a bot slot, see ServerWorld).
			# v11: the late joiner gets its own token so the match knows its name.
			var j := LobbyCodec.decode_join(pkt.data)
			if j.is_empty():
				return
			if j.get("legacy", false) or j.protocol_version != MsgType.PROTOCOL_VERSION:
				reject(pkt.from_peer, MsgType.REJECT_PROTOCOL_MISMATCH)
			elif accounts.identity(pkt.from_peer).is_empty():
				reject(pkt.from_peer, MsgType.REJECT_NOT_LOGGED_IN)
			else:
				var who := accounts.identity(pkt.from_peer)
				var token := 0
				while token == 0 or token_names.has(token):
					token = _rng.randi_range(1, 65535)
				token_names[token] = {"name": who.name, "id": who.id, "accent": who.accent}
				transport.send(pkt.from_peer, Transport.CH_CONTROL, LobbyCodec.encode_start(token, 255, j.hero_index))
		MsgType.ACCOUNT_REQ:
			accounts.handle(transport, pkt.from_peer, pkt.data)
		MsgType.LOBBY_PICK, MsgType.LOBBY_TEAM, MsgType.LOBBY_CHAT_SEND:
			pass  # a lobby client that has not seen the match start yet
		MsgType.INPUT_BATCH:
			var c: ClientConnection = clients.get(pkt.from_peer)
			if c == null:
				return
			var ack := InputBatchCodec.decode(pkt.data, net.input_redundancy, _scratch)
			if ack < 0:
				_violation(pkt.from_peer)
				return
			c.ack_snapshot_tick = maxi(c.ack_snapshot_tick, ack)
			for cmd in _scratch:
				c.inputs.push(cmd)
		_:
			_violation(pkt.from_peer)


func _violation(peer_id: int) -> void:
	var c: ClientConnection = clients.get(peer_id)
	if c == null:
		return
	c.violations += 1
	if c.violations > net.max_violations:
		clients.erase(peer_id)  # dropped; ServerWorld hands the slot to a bot later (E11)
