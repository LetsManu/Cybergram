class_name PresenceClient
extends RefCounted
## Main-menu presence check (design/ux/lobby-and-social.md §2.4): a short-lived
## connection to the server (connect -> PRESENCE_QUERY -> PRESENCE -> close),
## so a player sitting in the menu never holds one of the server's client
## slots. The query also checks the player in as "online" for a while.
## Works against the lobby and the running match alike.
##
## Example:
##   var pc := PresenceClient.new(ENetTransport.connect_to(host, port), wire, ids, names)
##   pc.finished.connect(func(entries: Array) -> void: ...)
##   pc.step(delta)  # every frame until done

## Reply entries (Array of {id, status, name}); empty on timeout / error.
signal finished(entries: Array, ok: bool)

const TIMEOUT_S := 5.0

var transport: Transport
var done: bool = false
var _waited: float = 0.0


func _init(t: Transport, profile: Dictionary, ids: PackedStringArray, names: PackedStringArray) -> void:
	transport = t
	t.send(LobbyClient.SERVER_PEER, Transport.CH_CONTROL,
		LobbyCodec.encode_presence_query(MsgType.PROTOCOL_VERSION, profile, ids, names))


func step(delta: float) -> void:
	if done:
		return
	_waited += delta
	transport.poll()
	var pkt := transport.pop_packet()
	while pkt != null:
		if not pkt.data.is_empty() and pkt.data.decode_u8(0) == MsgType.PRESENCE:
			var p := LobbyCodec.decode_presence(pkt.data)
			if not p.is_empty():
				_finish(p.entries, true)
				return
		pkt = transport.pop_packet()
	var err: String = str(transport.get("error_text")) if transport.get("error_text") != null else ""
	if _waited > TIMEOUT_S or err != "":
		_finish([], false)


func _finish(entries: Array, ok: bool) -> void:
	done = true
	if transport.has_method("close"):
		transport.call("close")
	finished.emit(entries, ok)
