class_name LobbyClient
extends RefCounted
## Client end of the server lobby: joins with a hero pick, mirrors the lobby
## state and reports the slot token when the match starts.

signal state_changed(state: Dictionary)
signal match_starting(token: int, team: int, hero_index: int)
signal failed(reason: String)

var transport: Transport
var hero_index: int = 0
var ready: bool = false
var state: Dictionary = {}


func _init(t: Transport, hero_index_: int) -> void:
	transport = t
	hero_index = hero_index_
	transport.send(ENetTransport.SERVER_PEER, Transport.CH_CONTROL,
		LobbyCodec.encode_join(MsgType.PROTOCOL_VERSION, hero_index))


func pick(hero_index_: int, ready_: bool) -> void:
	hero_index = hero_index_
	ready = ready_
	transport.send(ENetTransport.SERVER_PEER, Transport.CH_CONTROL, LobbyCodec.encode_pick(hero_index, ready))


func step() -> void:
	transport.poll()
	var pkt := transport.pop_packet()
	while pkt != null:
		_handle(pkt.data)
		pkt = transport.pop_packet()


func _handle(b: PackedByteArray) -> void:
	if b.is_empty():
		return
	match b.decode_u8(0):
		MsgType.LOBBY_STATE:
			var s := LobbyCodec.decode_state(b)
			if not s.is_empty():
				state = s
				state_changed.emit(s)
		MsgType.LOBBY_START:
			var st := LobbyCodec.decode_start(b)
			if not st.is_empty():
				match_starting.emit(st.token, st.team, st.hero_index)
		MsgType.REJECT:
			var r := ControlCodec.decode_reject(b)
			var reason: int = r.get("reason", 0)
			failed.emit("server is full" if reason == MsgType.REJECT_SERVER_FULL \
				else "version mismatch: update the game to the server's version")
