extends GdUnitTestSuite
## MatchHostRuntime (W17B): no-shows, abandons, the in-match remake vote
## (all present teammates, relayed to the front as a void with
## remake_absent) and the single final report. Fake agent, injected time.

const A1 := "0000000000000000000000000000000a"
const A2 := "0000000000000000000000000000000b"
const A3 := "0000000000000000000000000000000c"
const B1 := "0000000000000000000000000000001a"


class FakeAgent:
	extends RefCounted
	var results: Array = []
	var abandons: Array = []

	func report_result(winner: int, players: Array, abandons_: Array = [], extra: Dictionary = {}) -> void:
		results.append({"winner": winner, "players": players, "abandons": abandons_, "extra": extra})

	func report_abandon(account: String) -> void:
		abandons.append(account)


var _agent: FakeAgent
var _sent: Array = []
var _rt: MatchHostRuntime


func _make(extra_rules := {}) -> void:
	_agent = FakeAgent.new()
	_sent = []
	var r := {"remake_window_s": 180.0, "remake_vote_s": 30.0, "no_show_s": 60.0, "abandon_after_s": 120.0}
	r.merge(extra_rules, true)
	var setup := {"match_id": "abcdef0123456789abcdef01", "mode": "normal_5v5", "map": "front", "rules": r,
		"roster": [{"account": A1, "team": 0}, {"account": A2, "team": 0}, {"account": A3, "team": 0},
			{"account": B1, "team": 1}, {"account": "", "team": 1, "bot": true}]}
	_rt = MatchHostRuntime.new(_agent, setup, func(p: int, b: PackedByteArray) -> void: _sent.append([p, b]))
	_rt.start(0.0)


func _vote(peer: int, yes: bool, now: float) -> void:
	_rt.handle(peer, MatchmakingCodec.encode_request(MatchmakingCodec.OP_REMAKE_VOTE, {"yes": 1 if yes else 0}), now)


func _last_state_to(peer: int) -> Dictionary:
	for i in range(_sent.size() - 1, -1, -1):
		var d := MatchmakingCodec.decode_event(_sent[i][1])
		if _sent[i][0] == peer and d.get("op", 0) == MatchmakingCodec.EV_REMAKE_STATE:
			return d
	return {}


func test_no_show_enables_remake_and_all_present_must_agree() -> void:
	_make()
	_rt.on_join(2, A1, 1.0)
	_rt.on_join(3, A2, 1.0)
	_rt.on_join(5, B1, 1.0)
	_rt.tick(61.0)  # A3 never connected: absent
	_vote(2, true, 62.0)
	assert_int(_last_state_to(3).state).is_equal(MatchmakingCodec.RV_OPEN)
	assert_int(_last_state_to(3).needed).is_equal(2)
	assert_dict(_last_state_to(5)).is_empty()  # the other team does not see it
	_vote(3, true, 63.0)
	assert_int(_agent.results.size()).is_equal(1)
	var r: Dictionary = _agent.results[0]
	assert_int(r.winner).is_equal(-1)
	assert_bool(r.extra.remake).is_true()
	assert_array(r.extra.remake_absent).is_equal([A3])


func test_one_no_fails_the_remake() -> void:
	_make()
	_rt.on_join(2, A1, 1.0)
	_rt.on_join(3, A2, 1.0)
	_rt.on_join(4, A3, 1.0)
	_rt.on_leave(4, 30.0)
	_vote(2, true, 31.0)
	_vote(3, false, 32.0)
	assert_int(_last_state_to(2).state).is_equal(MatchmakingCodec.RV_FAILED)
	assert_int(_agent.results.size()).is_equal(0)


func test_remake_without_an_absent_player_or_too_late_is_refused() -> void:
	_make()
	_rt.on_join(2, A1, 1.0)
	_rt.on_join(3, A2, 1.0)
	_rt.on_join(4, A3, 1.0)
	_vote(2, true, 10.0)
	var ack := MatchmakingCodec.decode_event(_sent.back()[1]) if _sent.back()[0] == 2 else {}
	assert_int(_rt.votes[0].state).is_equal(RemakeVote.State.IDLE)
	_rt.on_leave(4, 200.0)
	_vote(2, true, 200.0)
	var codes: Array = []
	for s in _sent:
		var d := MatchmakingCodec.decode_event(s[1])
		if d.get("op", 0) == MatchmakingCodec.EV_ACK:
			codes.append(d.code)
	assert_array(codes).contains([MatchmakingCodec.E_NOT_ALLOWED, MatchmakingCodec.E_TOO_LATE])
	assert_bool(ack.is_empty() or ack.op == MatchmakingCodec.EV_ACK).is_true()


func test_abandon_is_reported_once_and_reconnect_cancels_it() -> void:
	_make()
	_rt.on_join(2, A1, 1.0)
	_rt.on_join(3, A2, 1.0)
	_rt.on_join(4, A3, 1.0)
	_rt.on_join(5, B1, 1.0)
	_rt.on_leave(3, 10.0)
	_rt.on_join(6, A2, 50.0)  # back in time
	_rt.on_leave(2, 60.0)
	_rt.tick(170.0)
	_rt.tick(200.0)
	assert_array(_agent.abandons).is_equal([A1])


func test_finish_reports_once_with_leavers_and_duration() -> void:
	_make()
	_rt.on_join(2, A1, 0.0)
	_rt.on_join(3, A2, 0.0)
	_rt.on_leave(3, 100.0)
	_rt.finish(1, 600.0)
	_rt.finish(0, 601.0)
	assert_int(_agent.results.size()).is_equal(1)
	assert_int(_agent.results[0].winner).is_equal(1)
	assert_array(_agent.results[0].abandons).contains([A2])
	assert_int(_agent.results[0].extra.duration_s).is_equal(600)


func test_end_after_s_ends_the_match_for_smoke_runs() -> void:
	_make({"end_after_s": 20.0, "debug_winner": 1})
	_rt.tick(19.0)
	assert_int(_agent.results.size()).is_equal(0)
	_rt.tick(20.5)
	assert_int(_agent.results[0].winner).is_equal(1)


func test_malformed_and_wrong_ops_get_an_error_ack() -> void:
	_make()
	_rt.on_join(2, A1, 1.0)
	_rt.handle(2, PackedByteArray([MsgType.MM_REQ, MatchmakingCodec.OP_REMAKE_VOTE]), 2.0)
	_rt.handle(2, MatchmakingCodec.encode_request(MatchmakingCodec.OP_QUEUE_LEAVE), 2.0)
	var codes: Array = _sent.map(func(s: Array) -> int: return MatchmakingCodec.decode_event(s[1]).code)
	assert_array(codes).is_equal([MatchmakingCodec.E_BAD_REQUEST, MatchmakingCodec.E_NOT_ALLOWED])


## Owner report 2026-10-06: a match whose humans all left kept running with bots
## only (and the players kept showing InGame). It now ends as soon as the last
## human counts as an abandon: voided, no rating, leavers listed.
func test_match_ends_when_every_human_has_abandoned() -> void:
	_make()
	for p in [[2, A1], [3, A2], [4, A3], [5, B1]]:
		_rt.on_join(p[0], p[1], 1.0)
	for peer in [2, 3, 4]:
		_rt.on_leave(peer, 10.0)
	_rt.tick(200.0)
	assert_int(_agent.results.size()).is_equal(0)  # B1 still plays
	_rt.on_leave(5, 210.0)
	_rt.tick(400.0)
	assert_int(_agent.results.size()).is_equal(1)
	var r: Dictionary = _agent.results[0]
	assert_int(int(r.winner)).is_equal(-1)
	assert_bool(bool(r.extra.get("all_left", false))).is_true()
	assert_array(r.abandons).contains_exactly_in_any_order([A1, A2, A3, B1])
	_rt.tick(500.0)
	assert_int(_agent.results.size()).is_equal(1)
