class_name LobbyClient
extends RefCounted
## Client end of one online-server connection (design/ux/lobby-and-social.md
## §2, §6): account requests (register / login / resume / guest, profile,
## friends, export, delete), then the lobby (join, picks, team switch, chat)
## and the slot token when the match starts. One object polls the transport
## and dispatches every message. Display only: the server decides
## everything. The session token is kept in memory only (`session`).
##
## Example:
##   var lc := LobbyClient.new(enet)
##   lc.request(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": "Neo", ...})
##   lc.account_result.connect(func(d): if d.code == AccountCodec.OK: lc.join(hero, ""))
##   lc.step()  # every frame

signal state_changed(state: Dictionary)
## A chat line: {kind, code, team, accent, id, name, text}.
signal chat_received(line: Dictionary)
## An ACCOUNT_RESULT: {op, code, ...fields}.
signal account_result(result: Dictionary)
signal match_starting(token: int, team: int, hero_index: int)
## `reason` is a HUD_ translation key.
signal failed(reason: String)

## Server end of the transport (ENetTransport.SERVER_PEER; loopback tests: 1).
const SERVER_PEER: int = 1
const CHAT_KEEP := 50

var transport: Transport
var hero_index: int = 0
var ready: bool = false
var state: Dictionary = {}
## Chat lines received so far (newest last, capped).
var chat: Array = []
## The current session ({token, id, username, display_name, emblem, accent,
## favourite_hero, guest}); {} = not logged in. Memory only.
var session: Dictionary = {}
var joined: bool = false
## v17: matchmaking on this connection (queues, ready check, picks, custom games).
var matchmaking: MatchmakingClient


## `server_host`: the address used to reach the server (match tickets with no
## host point there).
func _init(t: Transport, server_host: String = "") -> void:
	transport = t
	matchmaking = MatchmakingClient.new(t, server_host)


## Sends an account request (AccountCodec.OP_*, fields per REQ_SCHEMA).
func request(op: int, fields: Dictionary = {}) -> void:
	transport.send(SERVER_PEER, Transport.CH_CONTROL, AccountCodec.encode_request(op, fields))


## Joins the lobby with the logged-in identity. `party_id`: a friend to sit with.
func join(hero_index_: int, party_id: String = "") -> void:
	hero_index = hero_index_
	joined = true
	transport.send(SERVER_PEER, Transport.CH_CONTROL,
		LobbyCodec.encode_join(MsgType.PROTOCOL_VERSION, hero_index, party_id))


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
		MsgType.MM_EVENT:
			matchmaking.handle(b)
		MsgType.ACCOUNT_RESULT:
			var d := AccountCodec.decode_result(b)
			if d.is_empty():
				return
			if d.code == AccountCodec.OK:
				if d.has("token"):
					session = d.duplicate()
				elif d.op == AccountCodec.OP_UPDATE_PROFILE and not session.is_empty():
					for k in ["display_name", "emblem", "accent", "favourite_hero"]:
						session[k] = d[k]
				elif d.op == AccountCodec.OP_LOGOUT or d.op == AccountCodec.OP_DELETE_ACCOUNT:
					session = {}
			account_result.emit(d)
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
		MsgType.REJECT_NOT_LOGGED_IN:
			return "HUD_LOBBY_REJECT_LOGIN"
	return "HUD_LOBBY_REJECT_VERSION"


## Player-facing text key for an account result code.
static func account_error_key(code: int) -> String:
	return "HUD_ACCOUNT_ERR_%d" % code
