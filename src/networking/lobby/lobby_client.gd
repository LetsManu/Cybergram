class_name LobbyClient
extends RefCounted
## Client end of the server lobby: joins with the player's profile and hero
## pick, mirrors the lobby state, sends picks / team switches / chat, asks for
## friends' presence and reports the slot token when the match starts.
## Display only: the server decides seats, teams, readiness and chat text.
##
## Example:
##   var lc := LobbyClient.new(enet, profile.to_wire(), hero_index)
##   lc.state_changed.connect(_on_state)
##   lc.step()  # every frame

signal state_changed(state: Dictionary)
## A chat line: {kind, code, team, accent, name, text}.
signal chat_received(line: Dictionary)
## Presence reply entries: Array of {id, status, name}.
signal presence_received(entries: Array)
signal match_starting(token: int, team: int, hero_index: int)
signal failed(reason: String)

## Server end of the transport (ENetTransport.SERVER_PEER; loopback tests: 1).
const SERVER_PEER: int = 1

var transport: Transport
var profile: Dictionary = {}
var hero_index: int = 0
var ready: bool = false
var state: Dictionary = {}
## Chat lines received so far (newest last, capped).
var chat: Array = []
const CHAT_KEEP := 50


## `profile_`: {id, key, name, emblem, accent} (PlayerProfile fields).
## `party_id`: a friend's id to be seated with ("" = none).
func _init(t: Transport, profile_: Dictionary, hero_index_: int, party_id: String = "") -> void:
	transport = t
	profile = profile_
	hero_index = hero_index_
	transport.send(SERVER_PEER, Transport.CH_CONTROL,
		LobbyCodec.encode_join(MsgType.PROTOCOL_VERSION, profile, hero_index, party_id))


func pick(hero_index_: int, ready_: bool) -> void:
	hero_index = hero_index_
	ready = ready_
	transport.send(SERVER_PEER, Transport.CH_CONTROL, LobbyCodec.encode_pick(hero_index, ready))


## Asks to move to `team` (the server checks room and phase).
func switch_team(team: int) -> void:
	ready = false
	transport.send(SERVER_PEER, Transport.CH_CONTROL, LobbyCodec.encode_team(clampi(team, 0, 1)))


## Sends a chat line (the server sanitises and rate-limits it).
func say(text: String) -> void:
	var t := text.strip_edges()
	if t != "":
		transport.send(SERVER_PEER, Transport.CH_CONTROL, LobbyCodec.encode_chat_send(t))


## Asks for the presence of `ids` (resolved friends) and `names` (unresolved).
func query_presence(ids: PackedStringArray, names: PackedStringArray) -> void:
	transport.send(SERVER_PEER, Transport.CH_CONTROL,
		LobbyCodec.encode_presence_query(MsgType.PROTOCOL_VERSION, profile, ids, names))


## Own seat in the last state ({} before the first state).
func own_slot() -> Dictionary:
	if state.is_empty():
		return {}
	var you: int = state.you
	var slots: Array = state.slots
	return slots[you] if you < slots.size() else {}


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
				var own := own_slot()
				if not own.is_empty():
					ready = own.ready
				state_changed.emit(s)
		MsgType.LOBBY_CHAT:
			var c := LobbyCodec.decode_chat(b)
			if not c.is_empty():
				chat.append(c)
				while chat.size() > CHAT_KEEP:
					chat.remove_at(0)
				chat_received.emit(c)
		MsgType.PRESENCE:
			var p := LobbyCodec.decode_presence(b)
			if not p.is_empty():
				presence_received.emit(p.entries)
		MsgType.LOBBY_START:
			var st := LobbyCodec.decode_start(b)
			if not st.is_empty():
				match_starting.emit(st.token, st.team, st.hero_index)
		MsgType.REJECT:
			var r := ControlCodec.decode_reject(b)
			failed.emit(reject_text(int(r.get("reason", 0))))


## Player-facing reason for a Reject (HUD_ keys; tr() at the view).
static func reject_text(reason: int) -> String:
	match reason:
		MsgType.REJECT_SERVER_FULL:
			return "HUD_LOBBY_REJECT_FULL"
		MsgType.REJECT_ID_TAKEN:
			return "HUD_LOBBY_REJECT_ID"
		MsgType.REJECT_BAD_PROFILE:
			return "HUD_LOBBY_REJECT_PROFILE"
	return "HUD_LOBBY_REJECT_VERSION"
