class_name LobbyServer
extends RefCounted
## Pre-match lobby of the online dedicated server (LoL-style flow on one
## server, design/ux/lobby-and-social.md §2.2): players log in (or play as
## guest) through AccountService, then join with their session's identity, sit in two team columns (smaller team first, or their party
## friend's team), may switch teams while there is room, pick a hero, lock in
## with Ready and chat. When every connected player is ready a countdown runs;
## its last LOCK_S seconds are locked (no un-ready). Then every player gets a
## slot token (LOBBY_START) and `match_started` fires so the session builds
## the match. Players reconnect to the match with their token (Hello) to take
## their reserved team + hero; the token also carries their name.
##
## Server authoritative: every field from a client is validated here (sizes in
## LobbyCodec, values below). Malformed packets count as violations; a peer
## over MAX_VIOLATIONS is ignored from then on.
##
## Privacy (design/ux/lobby-and-social.md §4): seats, names and the chat
## replay buffer live in memory only, for this lobby (the buffer is cleared
## when the match starts). Logs never contain chat text or display names,
## only the 4-char id tag ("player #1A2B").
##
## Example (GameSession):
##   lobby = LobbyServer.new(enet, team_size())
##   lobby.match_started.connect(_on_lobby_started)
##   lobby.step(delta)   # every physics frame

## slots: Array of {token, team, hero_index, name, id, accent}
signal match_started(slots: Array)

const COUNTDOWN_S := 5.0
## The final seconds of the countdown in which nobody can un-ready.
const LOCK_S := 2.0
const STATE_EVERY_S := 1.0
## A dropped player keeps their slot this long (reconnect with the same id).
const RECONNECT_GRACE_S := 15.0
const CHAT_HISTORY := 20
const MAX_VIOLATIONS := 10
## Violation log lines per peer (the rest are counted silently).
const MAX_VIOLATION_LOGS := 3


## One seat in the lobby.
class Player:
	extends RefCounted
	var peer: int = -1  ## -1 = disconnected (inside the reconnect grace)
	var id: String = ""
	var key: String = ""
	var name: String = ""
	var emblem: int = 0
	var accent: int = 0
	var hero_index: int = 0
	var team: int = 0
	var ready: bool = false
	var left_at: float = 0.0
	var announced_hero: int = -1
	var chat := ChatFilter.RateLimiter.new()

var transport: Transport
var registry: PresenceRegistry
## Logins, guests, friends (process-wide by default).
var accounts: AccountService
var team_size: int = 3
var phase: int = LobbyCodec.PHASE_WAITING
var countdown_left: float = 0.0
## Seats in join order.
var players: Array[Player] = []
## Last chat lines (encoded LOBBY_CHAT packets), replayed to joiners.
var history: Array[PackedByteArray] = []
## Lobby clock (seconds of step() time).
var now: float = 0.0
var _since_state: float = 0.0
var _violations: Dictionary = {}  # peer -> count
var _rng := RandomNumberGenerator.new()
## Optional anonymous counts for the launcher (see LobbyStatusWriter).
var _status := LobbyStatusWriter.new()


## `registry_` / `accounts_` default to the process-wide instances.
func _init(t: Transport, team_size_: int, registry_: PresenceRegistry = null, accounts_: AccountService = null) -> void:
	transport = t
	team_size = team_size_
	registry = registry_ if registry_ != null else PresenceRegistry.shared()
	accounts = accounts_ if accounts_ != null else AccountService.shared()
	accounts.reset_peers()
	registry.end_match(PresenceRegistry.now_s())
	_rng.randomize()
	if t.has_signal("peer_disconnected"):
		t.connect("peer_disconnected", on_peer_left)


## Call every frame while the lobby runs.
func step(delta: float) -> void:
	now += delta
	accounts.step(delta)
	transport.poll()
	var pkt := transport.pop_packet()
	while pkt != null:
		_handle(pkt)
		pkt = transport.pop_packet()
	_expire_disconnected()
	_status.tick(delta, _connected_count(), phase == LobbyCodec.PHASE_IN_MATCH, 0)
	if phase == LobbyCodec.PHASE_COUNTDOWN or phase == LobbyCodec.PHASE_LOCKED:
		if phase == LobbyCodec.PHASE_COUNTDOWN and not _all_ready():
			print("[lobby] countdown cancelled (someone is not ready)")
			phase = LobbyCodec.PHASE_WAITING
			_broadcast()
		elif _connected_count() == 0:
			phase = LobbyCodec.PHASE_WAITING
		else:
			countdown_left -= delta
			if countdown_left <= 0.0:
				_start()
				return
			if phase == LobbyCodec.PHASE_COUNTDOWN and countdown_left <= LOCK_S:
				phase = LobbyCodec.PHASE_LOCKED
				print("[lobby] locked: picks are final")
				_broadcast()
	_since_state += delta
	if _since_state >= STATE_EVERY_S:
		_broadcast()


## Seat index of `peer`, or -1.
func index_of_peer(peer: int) -> int:
	for i in players.size():
		if players[i].peer == peer:
			return i
	return -1


## Seated players on `team` (connected or inside the reconnect grace).
func team_count(team: int) -> int:
	var n := 0
	for p in players:
		if p.team == team:
			n += 1
	return n


## A peer disconnected: its seat is kept for RECONNECT_GRACE_S.
func on_peer_left(peer: int) -> void:
	_violations.erase(peer)
	accounts.on_disconnect(peer)
	var i := index_of_peer(peer)
	if i < 0:
		return
	var p := players[i]
	p.peer = -1
	p.ready = false
	p.left_at = now
	registry.forget(p.id)
	print("[lobby] %s (peer %d) disconnected; seat kept %d s, %d connected" % [
		_who(p), peer, int(RECONNECT_GRACE_S), _connected_count()])
	_system(LobbyCodec.SYS_RECONNECTING, p)
	_broadcast()


func _handle(pkt: Transport.Packet) -> void:
	if int(_violations.get(pkt.from_peer, 0)) > MAX_VIOLATIONS:
		return
	if pkt.data.is_empty() or pkt.data.size() > LobbyCodec.MAX_C2S_BYTES:
		_violation(pkt.from_peer, "bad packet size %d" % pkt.data.size())
		return
	match pkt.data.decode_u8(0):
		MsgType.LOBBY_JOIN:
			_on_join(pkt.from_peer, LobbyCodec.decode_join(pkt.data))
		MsgType.LOBBY_PICK:
			_on_pick(pkt.from_peer, LobbyCodec.decode_pick(pkt.data))
		MsgType.LOBBY_TEAM:
			_on_team(pkt.from_peer, LobbyCodec.decode_team(pkt.data))
		MsgType.LOBBY_CHAT_SEND:
			_on_chat(pkt.from_peer, LobbyCodec.decode_chat_send(pkt.data))
		MsgType.ACCOUNT_REQ:
			accounts.handle(transport, pkt.from_peer, pkt.data)
		_:
			_violation(pkt.from_peer, "unknown message %d" % pkt.data.decode_u8(0))


func _on_join(peer: int, j: Dictionary) -> void:
	if j.is_empty():
		_violation(peer, "malformed join")
		return
	if j.get("legacy", false) or j.protocol_version != MsgType.PROTOCOL_VERSION:
		print("[lobby] peer %d rejected: client protocol v%d, server v%d (update the game)" % [
			peer, j.protocol_version, MsgType.PROTOCOL_VERSION])
		transport.send(peer, Transport.CH_CONTROL, ControlCodec.encode_reject(MsgType.REJECT_PROTOCOL_MISMATCH))
		return
	var who := accounts.identity(peer)
	if who.is_empty():
		print("[lobby] peer %d rejected: not logged in" % peer)
		transport.send(peer, Transport.CH_CONTROL, ControlCodec.encode_reject(MsgType.REJECT_NOT_LOGGED_IN))
		return
	if index_of_peer(peer) >= 0:
		return  # duplicate join on the same connection
	j["id"] = who.id
	j["key"] = who.id  # the session authenticated the id
	j["name"] = who.name
	j["emblem"] = who.emblem
	j["accent"] = who.accent
	var seat := _seat_of_id(j.id)
	if seat == null and players.size() >= team_size * 2:
		print("[lobby] peer %d rejected: lobby full (%d players)" % [peer, players.size()])
		transport.send(peer, Transport.CH_CONTROL, ControlCodec.encode_reject(MsgType.REJECT_SERVER_FULL))
		return
	if (seat != null and seat.key != j.key) or not registry.claim(j.id, j.key, j.name):
		print("[lobby] peer %d rejected: id %s is held by another key" % [peer, PlayerProfile.tag_of(j.id)])
		transport.send(peer, Transport.CH_CONTROL, ControlCodec.encode_reject(MsgType.REJECT_ID_TAKEN))
		return
	var hero := _valid_hero(int(j.hero_index))
	var p := seat
	if p != null:
		# Reconnect (or a second connection taking over the seat).
		var old_peer := p.peer
		p.peer = peer
		p.name = j.name
		p.emblem = j.emblem
		p.accent = j.accent
		if not p.ready and phase != LobbyCodec.PHASE_LOCKED:
			p.hero_index = hero
		print("[lobby] %s reconnected (peer %d%s)" % [_who(p), peer,
			", replacing peer %d" % old_peer if old_peer >= 0 else ""])
		_system(LobbyCodec.SYS_RECONNECTED, p)
	else:
		p = Player.new()
		p.peer = peer
		p.id = j.id
		p.key = j.key
		p.name = j.name
		p.emblem = j.emblem
		p.accent = j.accent
		p.hero_index = hero
		p.team = _team_for_joiner(str(j.get("party_id", "")))
		players.append(p)
		print("[lobby] %s joined (peer %d, team %d, hero %d), %d in lobby" % [
			_who(p), peer, p.team, p.hero_index, players.size()])
		_system(LobbyCodec.SYS_JOINED, p)
	registry.set_status(p.id, LobbyCodec.STATUS_IN_LOBBY, PresenceRegistry.now_s())
	for line in history:
		transport.send(peer, Transport.CH_CONTROL, line)
	_broadcast()


func _on_pick(peer: int, d: Dictionary) -> void:
	if d.is_empty():
		_violation(peer, "malformed pick")
		return
	var i := index_of_peer(peer)
	if i < 0:
		return
	var p := players[i]
	if phase == LobbyCodec.PHASE_LOCKED:
		_broadcast()  # picks are final; resync the client's toggle
		return
	var hero := _valid_hero(int(d.hero_index))
	var changed := false
	if not (p.ready and d.ready) and hero != p.hero_index:
		p.hero_index = hero  # a locked-in (ready) player cannot change hero
		changed = true
	if p.ready != d.ready:
		p.ready = d.ready
		changed = true
	if changed:
		print("[lobby] %s: hero %d, %s" % [_who(p), p.hero_index, "READY" if p.ready else "not ready"])
	if p.ready and p.announced_hero != p.hero_index:
		p.announced_hero = p.hero_index
		_system(LobbyCodec.SYS_LOCKED_IN, p)
	if phase == LobbyCodec.PHASE_WAITING and _all_ready():
		phase = LobbyCodec.PHASE_COUNTDOWN
		countdown_left = COUNTDOWN_S
		print("[lobby] everyone ready: match starts in %d s" % int(COUNTDOWN_S))
	_broadcast()


func _on_team(peer: int, d: Dictionary) -> void:
	if d.is_empty():
		_violation(peer, "malformed team switch")
		return
	var i := index_of_peer(peer)
	if i < 0:
		return
	var p := players[i]
	if phase == LobbyCodec.PHASE_LOCKED or d.team == p.team:
		return
	if team_count(d.team) >= team_size:
		_system_to(peer, LobbyCodec.SYS_TEAM_FULL, p)
		return
	p.team = d.team
	p.ready = false
	print("[lobby] %s switched to team %d" % [_who(p), p.team])
	_system(LobbyCodec.SYS_SWITCHED, p)
	_broadcast()


func _on_chat(peer: int, d: Dictionary) -> void:
	if d.is_empty():
		_violation(peer, "malformed chat")
		return
	var i := index_of_peer(peer)
	if i < 0:
		return
	var p := players[i]
	var text := ChatFilter.sanitize(str(d.text))
	if text == "":
		return
	if not p.chat.allow(now):
		_system_to(peer, LobbyCodec.SYS_SLOW_DOWN, p)
		return
	var line := LobbyCodec.encode_chat(LobbyCodec.CHAT_PLAYER, 0, p.team, p.accent, p.name, text, p.id)
	history.append(line)
	while history.size() > CHAT_HISTORY:
		history.remove_at(0)
	for q in players:
		# Server-side blocks: a player who blocked the sender does not get the line.
		if q.peer >= 0 and not accounts.blocks_of(q.peer).has(p.id):
			transport.send(q.peer, Transport.CH_CONTROL, line)


func _valid_hero(index: int) -> int:
	return index if index >= 1 and index <= ContentDB.shared().count(ContentDB.HERO) else ContentDB.NONE


func _seat_of_id(id: String) -> Player:
	for p in players:
		if p.id == id:
			return p
	return null


func _team_for_joiner(party_id: String) -> int:
	if party_id != "":
		var friend := _seat_of_id(party_id)
		if friend != null and team_count(friend.team) < team_size:
			return friend.team
	return 0 if team_count(0) <= team_count(1) else 1


func _expire_disconnected() -> void:
	for i in range(players.size() - 1, -1, -1):
		var p := players[i]
		if p.peer < 0 and now - p.left_at >= RECONNECT_GRACE_S:
			players.remove_at(i)
			print("[lobby] %s left (no reconnect), %d in lobby" % [_who(p), players.size()])
			_system(LobbyCodec.SYS_LEFT, p)
			_broadcast()


func _connected_count() -> int:
	var n := 0
	for p in players:
		if p.peer >= 0:
			n += 1
	return n


## Every connected player is ready (and at least one is connected).
func _all_ready() -> bool:
	var any := false
	for p in players:
		if p.peer < 0:
			continue
		if not p.ready:
			return false
		any = true
	return any


func _slots() -> Array:
	var out: Array = []
	for p in players:
		out.append({"team": p.team, "hero_index": p.hero_index, "ready": p.ready, "connected": p.peer >= 0,
			"emblem": p.emblem, "accent": p.accent, "id": p.id, "name": p.name})
	return out


func _broadcast() -> void:
	_since_state = 0.0
	var slots := _slots()
	for i in players.size():
		if players[i].peer >= 0:
			transport.send(players[i].peer, Transport.CH_CONTROL,
				LobbyCodec.encode_state(phase, ceili(countdown_left), i, slots, team_size))


## A chat line to everyone connected (and into the replay history).
func _push(line: PackedByteArray) -> void:
	history.append(line)
	while history.size() > CHAT_HISTORY:
		history.remove_at(0)
	for p in players:
		if p.peer >= 0:
			transport.send(p.peer, Transport.CH_CONTROL, line)


func _system(code: int, about: Player) -> void:
	_push(LobbyCodec.encode_chat(LobbyCodec.CHAT_SYSTEM, code, about.team, about.accent, about.name, "", about.id))


## A system line for one peer only (not kept in the history).
func _system_to(peer: int, code: int, about: Player) -> void:
	transport.send(peer, Transport.CH_CONTROL,
		LobbyCodec.encode_chat(LobbyCodec.CHAT_SYSTEM, code, about.team, about.accent, about.name, "", about.id))


## Log label of a player: the id tag only (no display name in server logs).
static func _who(p: Player) -> String:
	return "player #" + PlayerProfile.tag_of(p.id)


func _violation(peer: int, what: String) -> void:
	var n := int(_violations.get(peer, 0)) + 1
	_violations[peer] = n
	if n <= MAX_VIOLATION_LOGS:
		print("[lobby] peer %d: %s (violation %d)" % [peer, what, n])
	elif n == MAX_VIOLATIONS + 1:
		print("[lobby] peer %d: too many violations, ignoring it" % peer)


func _start() -> void:
	phase = LobbyCodec.PHASE_IN_MATCH
	var out: Array = []
	var used := {}
	var at_s := PresenceRegistry.now_s()
	for p in players:
		if p.peer < 0:
			continue  # dropped and not back: the slot goes to a bot
		var token := 0
		while token == 0 or used.has(token):
			token = _rng.randi_range(1, 65535)
		used[token] = true
		var slot := {"token": token, "team": p.team, "hero_index": p.hero_index, "name": p.name,
			"id": p.id, "accent": p.accent}
		out.append(slot)
		registry.set_status(p.id, LobbyCodec.STATUS_IN_MATCH, at_s)
		transport.send(p.peer, Transport.CH_CONTROL, LobbyCodec.encode_start(token, p.team, p.hero_index))
	history.clear()  # chat is not kept beyond the lobby
	match_started.emit(out)
