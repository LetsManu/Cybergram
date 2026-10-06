class_name MatchHostRuntime
extends RefCounted
## Fair-play side of one matchmade match process (W17B): who is connected,
## no-shows, abandons, the early remake vote (one RemakeVote per team) and the
## final report to the front through the MatchHostAgent.
##
## - A seat never connected `no_show_s` after the start, or disconnected, is
##   absent for its team's remake vote; reconnecting makes it present again.
## - A player away `abandon_after_s` is reported once as an abandon
##   (agent.report_abandon) and listed in the result's abandons.
## - When every human has abandoned, the match ends at once (voided, all_left).
## - Remake vote (in-match MM_REQ OP_REMAKE_VOTE): the first yes starts it,
##   every present human teammate must agree (RemakeVote). REMAKE_STATE goes
##   to the team on every change. A passed vote ends the match as a void:
##   report_result(-1, ..., {remake: true, remake_absent}).
## - finish(winner) reports the normal result once; `end_after_s` (setup
##   rules, debug / smoke tests) ends the match early for team `debug_winner`.
## Time is injected (`now`, seconds); the agent and the sender are injected
## so tests run without a network.

var agent: Variant  # MatchHostAgent or a fake: report_result, report_abandon
var setup: Dictionary
var rules: MatchmakingRulesDef
## f(peer: int, bytes: PackedByteArray): sends to one match client.
var send_fn: Callable
## f() -> Array of {account, team, hero, kills, deaths, assists}.
var stats_fn: Callable = func() -> Array: return []
var started_at: float = -1.0
var finished: bool = false
var votes: Array = [null, null]
var team_of: Dictionary = {}      # account -> team
var peer_account: Dictionary = {}  # peer -> account
var connected: Dictionary = {}    # account -> peer
var seen: Dictionary = {}         # account -> true (connected at least once)
var away_since: Dictionary = {}   # account -> time it disconnected
var abandons: Dictionary = {}     # account -> true
var _no_show_done: bool = false
var _no_show_s: float
var _abandon_s: float
var _end_after_s: float
var _vote_state: Array = [-1, -1]


func _init(agent_: Variant, setup_: Dictionary, send_fn_: Callable, rules_: MatchmakingRulesDef = null) -> void:
	agent = agent_
	setup = setup_
	send_fn = send_fn_
	rules = (rules_ if rules_ != null else MatchmakingRulesDef.load_default()).duplicate() as MatchmakingRulesDef
	var r: Dictionary = setup.get("rules", {})
	rules.remake_window_s = float(r.get("remake_window_s", rules.remake_window_s))
	rules.remake_vote_s = float(r.get("remake_vote_s", rules.remake_vote_s))
	_no_show_s = float(r.get("no_show_s", rules.no_show_s))
	_abandon_s = float(r.get("abandon_after_s", rules.abandon_after_s))
	_end_after_s = float(r.get("end_after_s", 0.0))
	for e: Dictionary in setup.get("roster", []):
		if not bool(e.get("bot", false)):
			team_of[str(e.account)] = int(e.team)


## The match starts (first tick of the built world).
func start(now: float) -> void:
	started_at = now
	_vote_state = [RemakeVote.State.IDLE, RemakeVote.State.IDLE]
	for t in 2:
		var team: Array = team_of.keys().filter(func(a: String) -> bool: return team_of[a] == t)
		votes[t] = RemakeVote.new(team, now, rules)


func humans() -> Array:
	return team_of.keys()


func on_join(peer: int, account: String, _now: float) -> void:
	if not team_of.has(account):
		return
	peer_account[peer] = account
	connected[account] = peer
	seen[account] = true
	away_since.erase(account)
	if started_at >= 0.0:
		(votes[team_of[account]] as RemakeVote).mark_present(account)


func on_leave(peer: int, now: float) -> void:
	var acc: String = peer_account.get(peer, "")
	peer_account.erase(peer)
	if acc == "" or connected.get(acc, -1) != peer:
		return
	connected.erase(acc)
	away_since[acc] = now
	if started_at >= 0.0:
		(votes[team_of[acc]] as RemakeVote).mark_absent(acc)


func tick(now: float) -> void:
	if started_at < 0.0 or finished:
		return
	if not _no_show_done and now - started_at >= _no_show_s:
		_no_show_done = true
		for acc in team_of:
			if not seen.has(acc):
				(votes[team_of[acc]] as RemakeVote).mark_absent(acc)
				away_since.get_or_add(acc, started_at)
	for acc: String in away_since.keys():
		if not abandons.has(acc) and now - float(away_since[acc]) >= _abandon_s:
			abandons[acc] = true
			agent.report_abandon(acc)
	# Every human has left for good: end now instead of letting bots play on
	# (voided: no winner, no rating; the leavers are listed).
	if not team_of.is_empty() and abandons.size() >= team_of.size():
		finished = true
		agent.report_result(-1, stats_fn.call(), abandons.keys(), {"all_left": true,
			"duration_s": int(now - maxf(started_at, 0.0))})
		return
	for t in 2:
		var v: RemakeVote = votes[t]
		v.tick(now)
		if v.state != _vote_state[t]:
			_broadcast(t, now)
		if v.state == RemakeVote.State.PASSED:
			_finish_remake(v, now)
			return
	if _end_after_s > 0.0 and now - started_at >= _end_after_s:
		finish(int(setup.get("rules", {}).get("debug_winner", 0)), now)


## One MM_REQ from a match client. Only the remake vote is valid here.
func handle(peer: int, data: PackedByteArray, now: float) -> void:
	var r := MatchmakingCodec.decode_request(data)
	var op: int = r.get("op", 0)
	if r.is_empty() or op != MatchmakingCodec.OP_REMAKE_VOTE:
		_ack(peer, op, MatchmakingCodec.E_NOT_ALLOWED if not r.is_empty() else MatchmakingCodec.E_BAD_REQUEST)
		return
	var acc: String = peer_account.get(peer, "")
	if acc == "" or started_at < 0.0 or finished:
		_ack(peer, op, MatchmakingCodec.E_NOT_ALLOWED)
		return
	var team: int = team_of[acc]
	var v: RemakeVote = votes[team]
	var e: int
	if v.tick(now) != RemakeVote.State.OPEN:
		e = v.start(acc, now) if int(r.yes) != 0 else RemakeVote.Err.E_CLOSED
	else:
		e = v.vote(acc, int(r.yes) != 0, now)
	var code := MatchmakingCodec.OK
	match e:
		RemakeVote.Err.OK:
			code = MatchmakingCodec.OK
		RemakeVote.Err.E_TOO_LATE:
			code = MatchmakingCodec.E_TOO_LATE
		RemakeVote.Err.E_ALREADY_VOTED:
			code = MatchmakingCodec.E_DUPLICATE
		_:
			code = MatchmakingCodec.E_NOT_ALLOWED
	_ack(peer, op, code)
	_broadcast(team, now)
	if v.state == RemakeVote.State.PASSED:
		_finish_remake(v, now)


## The match ended normally: report once.
func finish(winner: int, now: float) -> void:
	if finished:
		return
	finished = true
	for acc: String in away_since:
		if not abandons.has(acc):
			abandons[acc] = true  # still away at the end: an abandon
	agent.report_result(winner, stats_fn.call(), abandons.keys(), {"duration_s": int(now - maxf(started_at, 0.0))})


func _finish_remake(v: RemakeVote, now: float) -> void:
	if finished:
		return
	finished = true
	agent.report_result(-1, stats_fn.call(), [], {"remake": true, "remake_absent": v.absent_at_pass.duplicate(),
		"duration_s": int(now - started_at)})


func _broadcast(team: int, now: float) -> void:
	var v: RemakeVote = votes[team]
	_vote_state[team] = v.state
	var b := MatchmakingCodec.encode_event(MatchmakingCodec.EV_REMAKE_STATE, MatchmakingCodec.OK, {
		"state": v.state, "yes": v.yes_count(), "needed": v.needed(),
		"seconds": ceili(maxf(0.0, v.deadline - now)) if v.state == RemakeVote.State.OPEN else 0, "team": team})
	for acc in connected:
		if team_of.get(acc, -1) == team:
			send_fn.call(int(connected[acc]), b)


func _ack(peer: int, req: int, code: int) -> void:
	send_fn.call(peer, MatchmakingCodec.encode_event(MatchmakingCodec.EV_ACK, code, {"req": req}))
