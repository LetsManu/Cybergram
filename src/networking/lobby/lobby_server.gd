class_name LobbyServer
extends RefCounted
## Pre-match lobby of the online dedicated server (LoL-style flow on one
## server): players connect, are balanced into two teams by join order, pick a
## hero and toggle Ready. When everyone is ready a short countdown runs, then
## every player gets a slot token (LOBBY_START) and `match_started` fires so
## the session builds the match. Players then reconnect to the match with
## their token (ControlCodec Hello) to take their reserved team + hero.

## slots: Array of {token: int, team: int, hero_index: int}
signal match_started(slots: Array)

const COUNTDOWN_S := 5.0
const STATE_EVERY_S := 1.0

var transport: Transport
var team_size: int = 3
var phase: int = LobbyCodec.PHASE_WAITING
var countdown_left: float = 0.0
## Joined peers in join order: Array of {peer, hero_index, ready}.
var players: Array = []
var _since_state: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init(t: Transport, team_size_: int) -> void:
	transport = t
	team_size = team_size_
	_rng.randomize()
	if t.has_signal("peer_disconnected"):
		t.connect("peer_disconnected", _on_left)


## Call every frame while the lobby runs.
func step(delta: float) -> void:
	transport.poll()
	var pkt := transport.pop_packet()
	while pkt != null:
		_handle(pkt)
		pkt = transport.pop_packet()
	if phase == LobbyCodec.PHASE_COUNTDOWN:
		if not _all_ready():
			phase = LobbyCodec.PHASE_WAITING
			_broadcast()
		else:
			countdown_left -= delta
			if countdown_left <= 0.0:
				_start()
				return
	_since_state += delta
	if _since_state >= STATE_EVERY_S:
		_broadcast()


func team_of(i: int) -> int:
	return i % 2  # join order alternates Concord / Syndicate


func _handle(pkt: Transport.Packet) -> void:
	if pkt.data.is_empty():
		return
	match pkt.data.decode_u8(0):
		MsgType.LOBBY_JOIN:
			var j := LobbyCodec.decode_join(pkt.data)
			if j.is_empty():
				return
			if j.protocol_version != MsgType.PROTOCOL_VERSION:
				transport.send(pkt.from_peer, Transport.CH_CONTROL, ControlCodec.encode_reject(MsgType.REJECT_PROTOCOL_MISMATCH))
				return
			if _index_of(pkt.from_peer) >= 0:
				return
			if players.size() >= team_size * 2:
				transport.send(pkt.from_peer, Transport.CH_CONTROL, ControlCodec.encode_reject(MsgType.REJECT_SERVER_FULL))
				return
			players.append({"peer": pkt.from_peer, "hero_index": j.hero_index, "ready": false})
			_broadcast()
		MsgType.LOBBY_PICK:
			var p := LobbyCodec.decode_pick(pkt.data)
			var i := _index_of(pkt.from_peer)
			if p.is_empty() or i < 0:
				return
			players[i].hero_index = p.hero_index
			players[i].ready = p.ready
			if phase == LobbyCodec.PHASE_WAITING and _all_ready():
				phase = LobbyCodec.PHASE_COUNTDOWN
				countdown_left = COUNTDOWN_S
			_broadcast()


func _on_left(peer: int) -> void:
	var i := _index_of(peer)
	if i >= 0:
		players.remove_at(i)
		_broadcast()


func _all_ready() -> bool:
	if players.is_empty():
		return false
	for p in players:
		if not p.ready:
			return false
	return true


func _index_of(peer: int) -> int:
	for i in players.size():
		if players[i].peer == peer:
			return i
	return -1


func _slots() -> Array:
	var out: Array = []
	for i in players.size():
		out.append({"team": team_of(i), "hero_index": players[i].hero_index, "ready": players[i].ready})
	return out


func _broadcast() -> void:
	_since_state = 0.0
	var slots := _slots()
	for i in players.size():
		transport.send(players[i].peer, Transport.CH_CONTROL,
			LobbyCodec.encode_state(phase, ceili(countdown_left), i, slots))


func _start() -> void:
	phase = LobbyCodec.PHASE_IN_MATCH
	var out: Array = []
	var used := {}
	for i in players.size():
		var token := 0
		while token == 0 or used.has(token):
			token = _rng.randi_range(1, 65535)
		used[token] = true
		var slot := {"token": token, "team": team_of(i), "hero_index": players[i].hero_index}
		out.append(slot)
		transport.send(players[i].peer, Transport.CH_CONTROL,
			LobbyCodec.encode_start(token, slot.team, slot.hero_index))
	match_started.emit(out)
