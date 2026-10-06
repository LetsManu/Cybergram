class_name MatchmakingClient
extends RefCounted
## Client side of matchmaking (protocol v17, MatchmakingCodec). The UI calls
## the request methods and listens to the signals; the server decides
## everything (display only). Full contract:
## docs/architecture/matchmaking-client-api.md.
##
## One instance per server connection. It does not poll the transport itself:
## the owner of the connection feeds it every MM_EVENT packet through
## handle(). LobbyClient does that for the front connection
## (LobbyClient.matchmaking); ClientSession does it for the match connection
## (ClientSession.matchmaking, remake vote only).
##
## Example (menu / launcher, after login on the front):
##   var mm := lobby_client.matchmaking
##   mm.queue_status.connect(func(est, queued): ...)
##   mm.match_assigned.connect(func(host, port, ticket): start_match_client(host, port, ticket))
##   mm.queue_join(&"normal_5v5", [&"north", &"center"])
##
## Deadlines in signals are local monotonic seconds (clock(), i.e.
## Time.get_ticks_msec() / 1000.0): compare them with MatchmakingClient.clock().

## Queue state changed. `est_s` = estimated wait (s), `in_queue` = queued now.
signal queue_status(est_s: int, in_queue: bool)
## Every QUEUE_STATUS in full: {state, queue, waited, estimate, players, locked, code}.
signal queue_detail(status: Dictionary)
## A match was found: accept before `deadline` (local seconds). Also re-sent
## while others accept: see last_ready ({match, queue, humans, accepted, you_accepted}).
signal ready_check(deadline: float)
## The ready check ended: {outcome (RR_*), locked (s)}.
signal ready_result(result: Dictionary)
## Draft (5v5) state: see docs (seats, turn, deadline, you, ...).
signal draft_state(state: Dictionary)
## 3v3 All Random state: seats, rerolls, bench, swap_from, deadline.
signal aram_state(state: Dictionary)
## Join the match: connect the game client to host:port with the ticket in Hello.
## `host` is already resolved ("" from the server = the front's address).
signal match_assigned(host: String, port: int, ticket: String)
## Ratings: {tracks: [{track, track_id, rating (-1 hidden), games_left, band, division}]}.
signal rating_update(info: Dictionary)
## Queue lockout: {seconds, until (local s), ranked, reason}.
signal lockout(info: Dictionary)
## In-match remake vote: {state (RV_*), yes, needed, seconds, deadline, team}.
signal remake_prompt(info: Dictionary)
## Post-match summary (front): {match, queue, won, voided, duration, rated, delta, players}.
signal match_result(result: Dictionary)
## Custom lobby state: {host, phase, map, mode, bots, team_size, members}.
signal custom_state(state: Dictionary)
## A request failed: `op` = the MatchmakingCodec.OP_*, `code` = MatchmakingCodec.E_*.
signal request_failed(op: int, code: int)
## v20: the player's state on the server changed (PhaseMachine.Player): {epoch,
## seq, phase, prev, snap, queue, party_size, leader, waited, estimate, locked,
## match, party, at (local s when received)}. Stale events (an older seq of
## the same epoch, not a snapshot) are dropped and never emitted.
signal phase_changed(state: Dictionary)
## v20: loading percent of every seat (EV_PICK_STATE seat order; bots 100).
signal load_progress(loads: Array)
## v20: a hero select team chat line (seat index in last_pick, server-cleaned
## text; your own lines come back too).
signal select_chat(seat: int, text: String)

const SERVER_PEER: int = 1

var transport: Transport
## Address used to reach this server (for host "" in MATCH_ASSIGNED).
var server_host: String = ""
## Local monotonic clock in seconds (tests inject a fake).
var clock: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0

## Last state of each kind ({} = none yet).
var last_status: Dictionary = {}
var last_ready: Dictionary = {}
var last_pick: Dictionary = {}
var last_assigned: Dictionary = {}
var last_ranked: Dictionary = {}
var last_remake: Dictionary = {}
var last_result: Dictionary = {}
var last_custom: Dictionary = {}
## v20: last accepted PHASE event ({} = none yet).
var last_phase: Dictionary = {}
## Stale PHASE events dropped (diagnostics).
var stale_phases: int = 0


func _init(t: Transport, server_host_: String = "") -> void:
	transport = t
	server_host = server_host_


# --- requests ------------------------------------------------------------------

## Queue (party leader only). `queue`: queue id (&"normal_5v5", &"ranked_5v5",
## &"all_random_3v3") or its index; `lanes`: [primary, secondary] lane ids
## (&"north", &"center", &"south", &"flex") or [&"fill"].
func queue_join(queue: Variant, lanes: Array = [&"fill"]) -> void:
	var qi: int = queue if queue is int else queue_index(StringName(queue))
	var l1: int = MatchmakingCodec.lane_byte(StringName(lanes[0])) if lanes.size() > 0 else MatchmakingCodec.LANE_FILL
	var l2: int = MatchmakingCodec.lane_byte(StringName(lanes[1])) if lanes.size() > 1 else MatchmakingCodec.LANE_FILL
	_send(MatchmakingCodec.OP_QUEUE_JOIN, {"queue": qi, "lane1": l1, "lane2": l2})


func queue_leave() -> void:
	_send(MatchmakingCodec.OP_QUEUE_LEAVE)


func ready_accept() -> void:
	_send(MatchmakingCodec.OP_READY_REPLY, {"accept": 1})


func ready_decline() -> void:
	_send(MatchmakingCodec.OP_READY_REPLY, {"accept": 0})


## Draft pick (5v5) or custom-lobby pick: ContentDB HERO index. In the ban
## phase (v20) the same request locks the ban.
func draft_pick(hero: int) -> void:
	_send(MatchmakingCodec.OP_PICK, {"hero": hero})


## v20: declare a hero (allies see it; ban phase: the ban). 0 clears.
func draft_hover(hero: int) -> void:
	_send(MatchmakingCodec.OP_HOVER, {"hero": hero})


func aram_reroll() -> void:
	_send(MatchmakingCodec.OP_ARAM_REROLL)


## Take `hero` (HERO index) from the team bench.
func aram_take_bench(hero: int) -> void:
	_send(MatchmakingCodec.OP_ARAM_BENCH, {"hero": hero})


## Ask the teammate in seat `seat` (index in the state's seats) to swap.
func aram_swap_request(seat: int) -> void:
	_send(MatchmakingCodec.OP_ARAM_SWAP_REQUEST, {"seat": seat})


## Accept the swap the teammate in seat `seat` asked for.
func aram_swap_accept(seat: int) -> void:
	_send(MatchmakingCodec.OP_ARAM_SWAP_ACCEPT, {"seat": seat})


## In match: the first yes starts the vote (needs an absent teammate).
func remake_vote(yes: bool) -> void:
	_send(MatchmakingCodec.OP_REMAKE_VOTE, {"yes": 1 if yes else 0})


## Post-match report: `category` = index into MatchmakingRulesDef.report_categories
## (cheating, griefing, abusive_chat, afk, offensive_name).
func report(target_id: String, category: int, match_id: String = "") -> void:
	_send(MatchmakingCodec.OP_REPORT, {"match": _match_or_last(match_id), "target": target_id,
		"category": category})


func honour(target_id: String, match_id: String = "") -> void:
	_send(MatchmakingCodec.OP_HONOUR, {"match": _match_or_last(match_id), "target": target_id})


func request_ranked_info() -> void:
	_send(MatchmakingCodec.OP_RANKED_INFO)


## Reconnect: asks the front for a fresh ticket to the own running match
## (answered with match_assigned, or request_failed(OP_REJOIN, E_NOT_FOUND)).
func rejoin() -> void:
	_send(MatchmakingCodec.OP_REJOIN)


## v20: asks for a full PHASE snapshot (after a reconnect or when the UI
## doubts its state). Answered with phase_changed (snap = 1).
func request_state_sync() -> void:
	_send(MatchmakingCodec.OP_STATE_SYNC)


## True when a PHASE event `d` is newer than `last` (same epoch, higher seq),
## from a new server epoch, or a snapshot.
static func phase_is_newer(last: Dictionary, d: Dictionary) -> bool:
	if last.is_empty() or int(d.get("snap", 0)) == 1 or int(d.epoch) != int(last.epoch):
		return true
	return int(d.seq) > int(last.seq)


## Custom game: `map` index into MatchmakingCodec.CUSTOM_MAPS, `mode` PM_CUSTOM
## (free pick) or PM_ALL_RANDOM, bots fill empty seats when `bots`.
func custom_create(map: int, mode: int = MatchmakingCodec.PM_CUSTOM, bots: bool = true, team_size: int = 5) -> void:
	_send(MatchmakingCodec.OP_CUSTOM_CREATE, {"map": map, "mode": mode, "bots": 1 if bots else 0,
		"team_size": team_size})


## Host: invite a friend; "" invites the whole party.
func custom_invite(friend_id: String = "") -> void:
	_send(MatchmakingCodec.OP_CUSTOM_INVITE, {"id": friend_id})


func custom_join(host_id: String) -> void:
	_send(MatchmakingCodec.OP_CUSTOM_JOIN, {"host": host_id})


func custom_leave() -> void:
	_send(MatchmakingCodec.OP_CUSTOM_LEAVE)


func custom_team(team: int) -> void:
	_send(MatchmakingCodec.OP_CUSTOM_TEAM, {"team": clampi(team, 0, 1)})


func custom_pick(hero: int) -> void:
	_send(MatchmakingCodec.OP_CUSTOM_PICK, {"hero": hero})


func custom_start() -> void:
	_send(MatchmakingCodec.OP_CUSTOM_START)


## v20 host: bots per team (MatchmakingCodec.BOTS_FILL = fill the empty seats)
## and the bot difficulty (index into MatchmakingCodec.BOT_DIFFICULTIES).
func custom_bots(bots_a: int, bots_b: int, difficulty: int) -> void:
	_send(MatchmakingCodec.OP_CUSTOM_BOTS, {"bots_a": bots_a, "bots_b": bots_b, "difficulty": difficulty})


## v20: own match loading progress in percent (the front only takes rising values).
func report_load(pct: int) -> void:
	_send(MatchmakingCodec.OP_LOAD_PROGRESS, {"pct": clampi(pct, 0, 100)})


## v20: a line to the own team in hero select (the server cleans and relays it).
func select_say(text: String) -> void:
	var s := text.strip_edges()
	if s != "":
		_send(MatchmakingCodec.OP_SELECT_CHAT, {"text": s.left(LobbyCodec.CHAT_MAX_CHARS)})


## Index of a queue id in the standard queue list (MatchmakingRulesDef order), or 255.
static func queue_index(id: StringName) -> int:
	var i := QUEUE_IDS.find(id)
	return i if i >= 0 else 255


## Queue ids by wire index (the order of MatchmakingRulesDef.standard_queues()).
const QUEUE_IDS: Array[StringName] = [&"normal_5v5", &"ranked_5v5", &"all_random_3v3", &"custom"]


# --- incoming --------------------------------------------------------------------

## Feeds one packet. True when it was a matchmaking event (consumed).
func handle(b: PackedByteArray) -> bool:
	if b.is_empty() or b.decode_u8(0) != MsgType.MM_EVENT:
		return false
	var d := MatchmakingCodec.decode_event(b)
	if d.is_empty():
		return true
	var now: float = clock.call()
	var code: int = d.code
	match int(d.op):
		MatchmakingCodec.EV_QUEUE_STATUS:
			last_status = d
			queue_detail.emit(d)
			queue_status.emit(int(d.estimate), int(d.state) == MatchmakingCodec.QS_QUEUED)
			if code != MatchmakingCodec.OK:
				request_failed.emit(MatchmakingCodec.OP_QUEUE_JOIN, code)
		MatchmakingCodec.EV_MATCH_FOUND:
			if code == MatchmakingCodec.OK:
				d["deadline"] = now + float(d.seconds)
				last_ready = d
				ready_check.emit(float(d.deadline))
		MatchmakingCodec.EV_READY_RESULT:
			ready_result.emit(d)
		MatchmakingCodec.EV_PICK_STATE:
			if code == MatchmakingCodec.OK:
				d["deadline"] = now + float(d.seconds)
				last_pick = d
				if int(d.mode) == MatchmakingCodec.PM_ALL_RANDOM:
					aram_state.emit(d)
				else:
					draft_state.emit(d)
		MatchmakingCodec.EV_MATCH_ASSIGNED:
			if code == MatchmakingCodec.OK:
				var host: String = d.host if str(d.host) != "" else server_host
				d["host"] = host
				last_assigned = d
				match_assigned.emit(host, int(d.port), str(d.ticket))
		MatchmakingCodec.EV_RANKED_INFO:
			if code == MatchmakingCodec.OK:
				for e: Dictionary in d.tracks:
					e["track_id"] = MatchmakingCodec.TRACKS[e.track] if e.track < MatchmakingCodec.TRACKS.size() else &""
					if int(e.rating) == MatchmakingCodec.RATING_HIDDEN:
						e["rating"] = -1
				last_ranked = d
				rating_update.emit(d)
		MatchmakingCodec.EV_LOCKOUT:
			if code == MatchmakingCodec.OK:
				d["until"] = now + float(d.seconds)
				lockout.emit(d)
		MatchmakingCodec.EV_REMAKE_STATE:
			if code == MatchmakingCodec.OK:
				d["deadline"] = now + float(d.seconds)
				last_remake = d
				remake_prompt.emit(d)
		MatchmakingCodec.EV_MATCH_RESULT:
			if code == MatchmakingCodec.OK:
				d["delta"] = float(d.delta) / 10.0
				last_result = d
				match_result.emit(d)
		MatchmakingCodec.EV_CUSTOM_STATE:
			if code == MatchmakingCodec.OK:
				last_custom = d
				custom_state.emit(d)
		MatchmakingCodec.EV_ACK:
			if code != MatchmakingCodec.OK:
				request_failed.emit(int(d.req), code)
		MatchmakingCodec.EV_PHASE:
			if code == MatchmakingCodec.OK:
				if phase_is_newer(last_phase, d):
					d["at"] = now
					last_phase = d
					phase_changed.emit(d)
				else:
					stale_phases += 1
		MatchmakingCodec.EV_LOAD_PROGRESS:
			if code == MatchmakingCodec.OK:
				load_progress.emit(d.loads)
		MatchmakingCodec.EV_SELECT_CHAT:
			if code == MatchmakingCodec.OK:
				select_chat.emit(int(d.seat), str(d.text))
	return true


func _match_or_last(match_id: String) -> String:
	return match_id if match_id != "" else str(last_result.get("match", ""))


func _send(op: int, fields: Dictionary = {}) -> void:
	if transport != null:
		transport.send(SERVER_PEER, Transport.CH_CONTROL, MatchmakingCodec.encode_request(op, fields))
