class_name FrontPhases
extends RefCounted
## The front's state machines in use (P1, docs/architecture/front-state.md).
## MatchmakingFront stays the owner of queues, matches and custom lobbies;
## this class reads them, moves each player / party / lobby through
## PhaseMachine, pushes the player's state to the client (MM_EVENT PHASE,
## versioned: server epoch + per-player sequence) and answers resyncs.
##
## Players are derived from authoritative state on every sync:
##   in a match: READY -> READY_CHECK, PICK -> CHAMP_SELECT, STARTING -> LOADING,
##               RUNNING -> IN_GAME (offline before RUNNING -> RECONNECTING)
##   queued -> QUEUED (offline -> RECONNECTING while the ticket waits for the grace)
##   in a custom lobby -> CHAMP_SELECT
##   post-game window -> POST_GAME; in a party of 2+ -> IN_PARTY; online -> IDLE;
##   else OFFLINE
## A derived change the table forbids is rejected, logged (rate limited) and
## counted; the player keeps the last legal state until a legal one appears.
## Lobbies (formed matches) move on explicit calls from MatchmakingFront.
## Time is the front's clock (unix seconds).

## Minimum seconds between two identical illegal-transition log lines.
const ILLEGAL_LOG_EVERY_S := 60.0
## Seconds a player shows POST_GAME after a result unless they act first.
const POST_GAME_S := 120.0

var front: Variant  # MatchmakingFront (untyped: no class cycle)
var players := PhaseRegistry.new(PhaseMachine.Kind.PLAYER)
var parties := PhaseRegistry.new(PhaseMachine.Kind.PARTY)
var lobbies := PhaseRegistry.new(PhaseMachine.Kind.LOBBY)
## Process start (unix s): a new epoch tells clients to drop their old sequence.
var epoch: int = 0

var _post_until: Dictionary = {}      # account id -> unix s
var _illegal_logged: Dictionary = {}  # "kind:key:from:to" -> unix s
var _peer_cache: Dictionary = {}      # account id -> peer (rebuilt on every sync)


func _init(front_: Variant, epoch_: int) -> void:
	front = front_
	epoch = epoch_
	players.on_change = _on_player_change
	players.on_illegal = func(k: String, a: int, b: int, ctx: Dictionary) -> void:
		_illegal(PhaseMachine.Kind.PLAYER, k, a, b, ctx)
	parties.on_illegal = func(k: String, a: int, b: int, ctx: Dictionary) -> void:
		_illegal(PhaseMachine.Kind.PARTY, k, a, b, ctx)
	lobbies.on_illegal = func(k: String, a: int, b: int, ctx: Dictionary) -> void:
		_illegal(PhaseMachine.Kind.LOBBY, k, a, b, ctx)
	lobbies.on_change = func(k: String, e: Dictionary) -> void:
		front._ev(OpsLog.INFO, "lobby_state", "lobby %s: %s -> %s" % [k,
			PhaseMachine.name_of(PhaseMachine.Kind.LOBBY, int(e.prev)),
			PhaseMachine.name_of(PhaseMachine.Kind.LOBBY, int(e.state))], {"lobby": k, "match": k}, false)


# --- lobbies (explicit) ---------------------------------------------------------------

func lobby(match_id: String, state: PhaseMachine.Lobby, t: float) -> void:
	lobbies.request(match_id, state, t, {})
	if state == PhaseMachine.Lobby.ENDED or state == PhaseMachine.Lobby.CANCELLED:
		lobbies.forget(match_id)


# --- players ------------------------------------------------------------------------

## Marks the post-game window of a finished match's players. A player who
## already left the match (abandon: back to Idle / In party) gets none, so the
## match end never asks for an illegal Idle -> PostGame move.
func post_game(ids: Array, t: float) -> void:
	for id in ids:
		if players.can(str(id), PhaseMachine.Player.POST_GAME):
			_post_until[str(id)] = t + POST_GAME_S


## The player acted (queue, custom lobby): the post-game window ends.
func end_post_game(id: String) -> void:
	_post_until.erase(id)


## Re-derives every known player and party; call after requests and every few frames.
func sync(t: float) -> void:
	_peer_cache.clear()
	for p in front.accounts.peers:
		var id := str(front.accounts.peers[p].get("id", ""))
		if id != "":
			_peer_cache[id] = int(p)
	var ids := {}
	for id in _peer_cache:
		ids[id] = true
	for id in players.keys():
		ids[id] = true
	for id in front._account_match:
		ids[id] = true
	for id in front._queued:
		ids[id] = true
	for k in _post_until.keys():
		if t > float(_post_until[k]):
			_post_until.erase(k)
	for id: String in ids:
		var d := derive(id, t)
		_enter(id, int(d.phase), t, d.ctx)
		if int(d.phase) == PhaseMachine.Player.OFFLINE and players.state_of(id) == PhaseMachine.Player.OFFLINE:
			players.forget(id)  # nothing left to remember about an offline player
	_sync_parties(t)


## Moves `id` to `to`. Coming online while already holding a ticket or a seat
## (login and queue in one frame, a front restart, a resumed session) passes
## through RECONNECTING, the legal way back into those states.
func _enter(id: String, to: int, t: float, ctx: Dictionary) -> void:
	var P := PhaseMachine.Player
	var from := players.state_of(id)
	if from == P.OFFLINE and to != P.OFFLINE and not PhaseMachine.is_legal(PhaseMachine.Kind.PLAYER, from, to):
		players.request(id, P.RECONNECTING, t, ctx)
	players.request(id, to, t, ctx)


## {phase, ctx} of `id` from the front's live state.
func derive(id: String, t: float) -> Dictionary:
	var P := PhaseMachine.Player
	var online: bool = _peer_cache.has(id) if not _peer_cache.is_empty() else int(front._peer_of(id)) >= 0
	var party := ""
	var party_size := 1
	var leader := true
	if front.accounts.parties != null:
		var ps: Dictionary = front.accounts.parties.state_of(id, t)
		party = str(ps.party)
		if party != "":
			party_size = (ps.members as Array).size()
			leader = str(ps.leader) == id
	var ctx := {"party": party, "party_size": party_size, "leader": leader, "match": "", "queue": ""}
	var m: Variant = front._account_match.get(id)
	if m != null:
		ctx.match = m.id
		ctx.queue = String(m.queue.id) if m.queue != null else "custom"
		var by_state := [P.READY_CHECK, P.CHAMP_SELECT, P.LOADING, P.IN_GAME]
		var ph: int = by_state[int(m.state)]
		if not online and ph != P.IN_GAME:
			ph = P.RECONNECTING
		return {"phase": ph, "ctx": ctx}
	if front.matchmaker.ticket_of(id) != 0:
		ctx.queue = String(front.matchmaker.ticket(front.matchmaker.ticket_of(id)).queue)
		return {"phase": P.QUEUED if online else P.RECONNECTING, "ctx": ctx}
	if not online:
		return {"phase": P.OFFLINE, "ctx": ctx}
	if front._custom_of.has(id):
		ctx.queue = "custom"
		return {"phase": P.CHAMP_SELECT, "ctx": ctx}
	if _post_until.has(id):
		return {"phase": P.POST_GAME, "ctx": ctx}
	return {"phase": P.IN_PARTY if party_size > 1 else P.IDLE, "ctx": ctx}


## The PHASE fields for `id` (snapshot = 1 for resync answers).
func event_fields(id: String, snap: bool, t: float) -> Dictionary:
	var e := players.entry(id)
	var ctx: Dictionary = e.get("ctx", {})
	var qi := 255
	var waited := 0.0
	var est := 0.0
	var tid: int = front.matchmaker.ticket_of(id)
	if str(ctx.get("queue", "")) != "":
		qi = MatchmakingClient.queue_index(StringName(str(ctx.queue)))
	if tid != 0:
		var tk: Dictionary = front.matchmaker.ticket(tid)
		waited = t - float(tk.enqueued_at)
		est = float(front.matchmaker.estimated_wait_s(tk.queue))
	var locked: float = maxf(0.0, front.lockouts.locked_until(id, t, false) - t)
	return {"epoch": epoch, "seq": int(e.get("seq", 0)), "phase": int(e.get("state", PhaseMachine.Player.OFFLINE)),
		"prev": int(e.get("prev", PhaseMachine.Player.OFFLINE)), "snap": 1 if snap else 0,
		"queue": qi if qi >= 0 and qi < 255 else 255, "party_size": clampi(int(ctx.get("party_size", 1)), 1, 255),
		"leader": 1 if bool(ctx.get("leader", true)) else 0, "waited": clampi(int(waited), 0, 65535),
		"estimate": clampi(int(est), 0, 65535), "locked": clampi(ceili(locked), 0, 65535),
		"match": str(ctx.get("match", "")), "party": str(ctx.get("party", ""))}


## P2: friend presence of `id` ({status: LobbyCodec.STATUS_*, mode: queue
## index or 255}); {} when the front does not know the player (offline: the
## account service decides).
func presence_of(id: String) -> Dictionary:
	var e := players.entry(id)
	if e.is_empty():
		return {}
	var P := PhaseMachine.Player
	var ctx: Dictionary = e.ctx
	var q := str(ctx.get("queue", ""))
	var mode := MatchmakingClient.queue_index(StringName(q)) if q != "" else 255
	var st := LobbyCodec.STATUS_ONLINE
	match int(e.state):
		P.OFFLINE:
			return {}
		P.QUEUED:
			st = LobbyCodec.STATUS_IN_QUEUE
		P.READY_CHECK, P.CHAMP_SELECT, P.LOADING:
			st = LobbyCodec.STATUS_IN_LOBBY if q == "custom" and int(e.state) == P.CHAMP_SELECT \
				else LobbyCodec.STATUS_IN_SELECT
		P.IN_GAME, P.RECONNECTING:
			st = LobbyCodec.STATUS_IN_MATCH if int(e.state) == P.IN_GAME or str(ctx.get("match", "")) != "" \
				else LobbyCodec.STATUS_IN_QUEUE
		_:
			mode = 255
	return {"status": st, "mode": mode if mode < 255 else 255}


## Answers OP_STATE_SYNC: derive now and send the full state.
func resync(id: String, t: float) -> void:
	var d := derive(id, t)
	_enter(id, int(d.phase), t, d.ctx)
	front._send(id, MatchmakingCodec.EV_PHASE, MatchmakingCodec.OK, event_fields(id, true, t))


func _on_player_change(id: String, e: Dictionary) -> void:
	var t: float = float(e.since)
	var ctx: Dictionary = e.ctx
	front._ev(OpsLog.INFO, "player_phase", "player %s: %s -> %s" % [OpsLog.tag(id),
		PhaseMachine.name_of(PhaseMachine.Kind.PLAYER, int(e.prev)),
		PhaseMachine.name_of(PhaseMachine.Kind.PLAYER, int(e.state))],
		{"player": OpsLog.tag(id), "party": ctx.get("party", ""), "match": ctx.get("match", ""),
			"lobby": ctx.get("match", "")}, false)
	if int(e.state) != PhaseMachine.Player.OFFLINE:
		front._send(id, MatchmakingCodec.EV_PHASE, MatchmakingCodec.OK, event_fields(id, int(e.prev) ==
			PhaseMachine.Player.OFFLINE, t))


func _sync_parties(t: float) -> void:
	var ps: Variant = front.accounts.parties
	var live := {}
	if ps != null:
		for pid: String in ps.parties:
			live[pid] = true
			var members: Array = ps.parties[pid].members
			var st := PhaseMachine.Party.IDLE
			for mid in members:
				if front._account_match.has(str(mid)):
					st = PhaseMachine.Party.IN_MATCH
					break
				if front.matchmaker.ticket_of(str(mid)) != 0:
					st = PhaseMachine.Party.QUEUED
			if parties.state_of(pid) == PhaseMachine.Party.NONE:
				parties.request(pid, PhaseMachine.Party.IDLE, t, {"size": members.size()})
			parties.request(pid, st, t, {"size": members.size(), "leader": OpsLog.tag(str(ps.parties[pid].leader))})
	for pid in parties.keys():
		if not live.has(pid):
			parties.request(pid, PhaseMachine.Party.NONE, t)
			parties.forget(pid)


func _illegal(kind: PhaseMachine.Kind, key: String, from: int, to: int, ctx: Dictionary) -> void:
	var t: float = front.now()
	var k := "%d:%s:%d:%d" % [kind, key, from, to]
	if t - float(_illegal_logged.get(k, -1.0e12)) < ILLEGAL_LOG_EVERY_S:
		return
	_illegal_logged[k] = t
	if _illegal_logged.size() > 4096:
		_illegal_logged.clear()
	var who := OpsLog.tag(key) if kind == PhaseMachine.Kind.PLAYER else key
	front._ev(OpsLog.WARN, "illegal_transition", "rejected %s %s: %s -> %s" % [
		["player", "party", "lobby"][kind], who, PhaseMachine.name_of(kind, from), PhaseMachine.name_of(kind, to)],
		{"player": who if kind == PhaseMachine.Kind.PLAYER else "", "party": str(ctx.get("party", "")),
			"match": str(ctx.get("match", ""))}, true)
