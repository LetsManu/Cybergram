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

var transport: Transport
var net: NetConfig
var clients: Dictionary = {}  # peer id -> ClientConnection
## Hero index each joining peer asked for in Hello (ContentDB HERO, 0 = default).
var hello_hero: Dictionary = {}  # peer id -> int
## Lobby slot token each joining peer sent in Hello (0 = none).
var hello_token: Dictionary = {}  # peer id -> int
var _scratch: Array[InputCommand] = []


func _init(t: Transport, net_config: NetConfig) -> void:
	transport = t
	net = net_config


## Receives and routes every arrived packet.
func poll() -> void:
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
	clients[peer_id] = c
	transport.send(peer_id, Transport.CH_CONTROL, ControlCodec.encode_welcome(own_net_id, server_tick, net.tick_rate_hz))


## Forgets a disconnected peer: no more snapshots or events go to it. Its
## hero stays in the match, idle (a bot takeover is future work).
func drop(peer_id: int) -> void:
	clients.erase(peer_id)


func reject(peer_id: int, reason: int) -> void:
	transport.send(peer_id, Transport.CH_CONTROL, ControlCodec.encode_reject(reason))


func send_snapshot(peer_id: int, snap: SnapshotData) -> void:
	transport.send(peer_id, Transport.CH_SNAPSHOT, SnapshotCodec.encode(snap))


## Sends a reliable batch of gameplay events (no-op when empty).
func send_events(peer_id: int, tick: int, events: Array[GameEvent]) -> void:
	if events.is_empty():
		return
	transport.send(peer_id, Transport.CH_EVENTS, EventCodec.encode(tick, events))


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
			var j := LobbyCodec.decode_join(pkt.data)
			if not j.is_empty():
				transport.send(pkt.from_peer, Transport.CH_CONTROL, LobbyCodec.encode_start(0, 255, j.hero_index))
		MsgType.LOBBY_PICK:
			pass
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
