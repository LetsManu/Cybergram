class_name ClientSession
extends RefCounted
## Client end of the protocol: Hello, Welcome/Reject, InputBatch sending and
## snapshot decoding (architecture.md §8.2/§8.4).

signal welcomed(own_net_id: int, server_tick: int)
signal rejected(reason: int)
signal snapshot_received(snap: SnapshotData)
## A reliable gameplay event (hit confirm, kill).
signal event_received(event: GameEvent, server_tick: int)
## v11: the server's table of human player names changed (see player_names).
signal player_names_changed(names: Dictionary)

const SERVER_PEER: int = 1

var transport: Transport
var net: NetConfig
var own_net_id: int = 0
var is_welcomed: bool = false
## Newest snapshot tick received (acked in every InputBatch).
var latest_snapshot_tick: int = 0
var malformed_packets: int = 0
## Hero the player picked (ContentDB HERO index, 0 = server default); sent in Hello.
var hero_index: int = 0
## Lobby slot token (0 = none); sent in Hello.
var token: int = 0
## v11: net id -> {name, accent, id} of the human players (PLAYER_NAMES); bots are absent.
var player_names: Dictionary = {}
var _recent: Array[InputCommand] = []


func _init(t: Transport, net_config: NetConfig) -> void:
	transport = t
	net = net_config


func connect_to_server() -> void:
	transport.send(SERVER_PEER, Transport.CH_CONTROL, ControlCodec.encode_hello(MsgType.PROTOCOL_VERSION, hero_index, token))


func poll() -> void:
	transport.poll()
	var pkt := transport.pop_packet()
	while pkt != null:
		_handle(pkt)
		pkt = transport.pop_packet()


## Sends `cmd` plus the previous (input_redundancy - 1) commands.
func send_input(cmd: InputCommand) -> void:
	_recent.append(cmd.duplicate_command())
	while _recent.size() > net.input_redundancy:
		_recent.pop_front()
	transport.send(SERVER_PEER, Transport.CH_INPUT, InputBatchCodec.encode(latest_snapshot_tick, _recent))


func _handle(pkt: Transport.Packet) -> void:
	if pkt.data.is_empty():
		malformed_packets += 1
		return
	match pkt.data.decode_u8(0):
		MsgType.WELCOME:
			var w := ControlCodec.decode_welcome(pkt.data)
			if w.is_empty():
				malformed_packets += 1
				return
			own_net_id = w.own_net_id
			is_welcomed = true
			welcomed.emit(own_net_id, w.server_tick)
		MsgType.REJECT:
			var r := ControlCodec.decode_reject(pkt.data)
			rejected.emit(r.get("reason", 0))
		MsgType.SNAPSHOT:
			var s := SnapshotCodec.decode(pkt.data)
			if s == null:
				malformed_packets += 1
				return
			if s.tick <= latest_snapshot_tick:
				return  # stale or duplicate (unreliable channel may reorder)
			latest_snapshot_tick = s.tick
			snapshot_received.emit(s)
		MsgType.EVENT:
			var events: Array[GameEvent] = []
			var t := EventCodec.decode(pkt.data, events)
			if t < 0:
				malformed_packets += 1
				return
			for e in events:
				event_received.emit(e, t)
		MsgType.PLAYER_NAMES:
			var names: Variant = LobbyCodec.decode_player_names(pkt.data)
			if names == null:
				malformed_packets += 1
				return
			player_names = names
			player_names_changed.emit(player_names)
		_:
			malformed_packets += 1
