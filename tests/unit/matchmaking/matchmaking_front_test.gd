extends GdUnitTestSuite
## MatchmakingFront state machine over loopback with a fake supervisor:
## queue -> ready -> draft (timeout auto-pick) -> allocate -> result -> rating,
## plus decline lockouts, crash void (no rating change, re-queue), remake
## strike, leaver, reconnect, ranked rules, party size, lockout persistence,
## retention, the deletion cascade and custom games. Time is a fake clock.

const DT := 1.0 / 30.0


class FakeSupervisor:
	extends RefCounted
	signal match_started(match_id: String, endpoint: Dictionary)
	signal match_result(match_id: String, result: Dictionary)
	signal match_voided(match_id: String, reason: String)
	signal abandon_reported(match_id: String, account_id: String)
	var requests: Array = []
	var busy: bool = false
	var tickets: int = 0

	func request_match(setup: Dictionary) -> Error:
		if busy:
			return ERR_BUSY
		requests.append(setup)
		return OK

	func issue_join_ticket(match_id: String, account_id: String, _now: float) -> Dictionary:
		tickets += 1
		return {"host": "", "port": 7801, "ticket": "cgt1.fake.%s.%s.%d" % [account_id.left(4), match_id.left(4), tickets]}

	func find_match(_id: String) -> Variant:
		return null


var _link: LoopbackLink
var _net: NetConfig
var _acc: AccountService


## Only what the hero select chat reads: each account's block list.
class BlockStore:
	extends AccountStore
	var blocks: Dictionary = {}

	func get_by_id(id: String) -> Dictionary:
		return {"id": id, "blocks": blocks.get(id, []), "friends": []}
var _sup: FakeSupervisor
var _front: MatchmakingFront
var _server: FrontServer
var _t: float = 1_800_000_000.0
var _rules: MatchmakingRulesDef
var _clients: Dictionary = {}  # peer -> LobbyClient
var _dir: String = ""


func before_test() -> void:
	_t = 1_800_000_000.0
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	_acc = AccountService.new(null, AuthRulesDef.new(), false, PresenceRegistry.new())
	_sup = FakeSupervisor.new()
	_rules = _small_rules()
	_clients = {}
	_dir = ""


func after_test() -> void:
	if _dir != "":
		for f in ["lockouts.json", "history.json"]:
			DirAccess.remove_absolute(_dir.path_join(f))
		DirAccess.remove_absolute(_dir)


## 1v1 normal / ranked, 1v1 all random (fast tests); everything else default.
func _small_rules() -> MatchmakingRulesDef:
	var r := MatchmakingRulesDef.new()
	r.queues = MatchmakingRulesDef.standard_queues()
	for q in r.queues:
		if q.id != &"custom":
			q.team_size = 1 if q.id != &"all_random_3v3" else 3
			if q.id != &"all_random_3v3":
				q.lane_slots = []
	r.draft_order = PackedInt32Array([1, 1])
	r.pick_turn_s = 10.0
	r.bot_fill_delay_s = 30.0
	return r


func _make_front(dir := "") -> void:
	var store := MemoryRatingStore.new()
	_front = MatchmakingFront.new(null, _acc, _sup, RatingService.new(store, _rules), ReportStore.new("", _rules),
		MatchHistoryStore.new(dir, _rules), _rules, dir)
	_front.clock = func() -> float: return _t
	_front.log_fn = func(_l: String) -> void: pass
	var ep := _link.create_endpoint(1)
	_front.transport = ep
	_server = FrontServer.new(ep, _acc, _front)


## A logged-in client: `guest` false = an account identity (set directly).
func _client(peer: int, guest := false) -> LobbyClient:
	var c := LobbyClient.new(_link.create_endpoint(peer))
	_acc.peers[peer] = {"id": _id(peer), "name": "P%d" % peer, "accent": 0, "emblem": 0, "guest": guest,
		"username": "", "favourite_hero": ""}
	_clients[peer] = c
	return c


static func _id(peer: int) -> String:
	return "%032x" % peer


func _step(seconds: float) -> void:
	for i in maxi(1, roundi(seconds / DT)):
		_t += DT
		_link.advance(_net.tick_dt())
		_server.step(DT)
		for c: LobbyClient in _clients.values():
			c.step()


## Two players through queue -> ready -> draft (b times out) -> allocation.
func _to_running(queue := &"normal_5v5") -> Array:
	var a := _client(2)
	var b := _client(3)
	a.matchmaking.queue_join(queue)
	b.matchmaking.queue_join(queue)
	_step(0.5)
	a.matchmaking.ready_accept()
	b.matchmaking.ready_accept()
	_step(0.5)
	var st: Dictionary = a.matchmaking.last_pick
	if not st.is_empty() and st.seats[st.you].flags & MatchmakingCodec.SEAT_PICKING:
		a.matchmaking.draft_pick(1)
	else:
		_step(_rules.pick_turn_s + 0.5)  # b's turn times out first
		a.matchmaking.draft_pick(1)
	_step(_rules.pick_turn_s + 1.0)
	_sup.match_started.emit(_sup.requests[0].match_id, {"host": "", "port": 7801})
	_step(0.3)
	return [a, b]


func test_full_flow_queue_ready_draft_allocate_result_changes_ratings() -> void:
	_make_front()
	var ab := _to_running()
	var a: LobbyClient = ab[0]
	var b: LobbyClient = ab[1]
	assert_int(_sup.requests.size()).is_equal(1)
	var setup: Dictionary = _sup.requests[0]
	assert_str(MatchSetup.validate(setup)).is_equal("")
	assert_bool(setup.rules.rated).is_true()
	for e: Dictionary in setup.roster:
		assert_str(e.hero).is_not_empty()  # the timed-out seat got a random legal hero
	assert_int(a.matchmaking.last_assigned.port).is_equal(7801)
	assert_str(b.matchmaking.last_assigned.ticket).starts_with("cgt1.")
	var team_a := 0 if setup.roster[0].account == _id(2) else 1
	_sup.match_result.emit(setup.match_id, {"winner": team_a, "players": [], "abandons": [], "duration_s": 600})
	_step(0.3)
	assert_int(a.matchmaking.last_result.won).is_equal(1)
	assert_float(a.matchmaking.last_result.delta).is_greater(0.0)
	assert_float(b.matchmaking.last_result.delta).is_less(0.0)
	assert_float(_front.ratings.entry(_id(2), &"normal").rating).is_greater(_rules.rating_initial)
	assert_int(_front.history.entries.size()).is_equal(1)


func test_draft_timeout_auto_picks_and_marks_the_seat() -> void:
	_make_front()
	var a := _client(2)
	var b := _client(3)
	a.matchmaking.queue_join(&"normal_5v5")
	b.matchmaking.queue_join(&"normal_5v5")
	_step(0.5)
	a.matchmaking.ready_accept()
	b.matchmaking.ready_accept()
	_step(_rules.pick_turn_s * 2 + 1.0)
	assert_int(_sup.requests.size()).is_equal(1)
	var auto := 0
	for s: Dictionary in a.matchmaking.last_pick.seats:
		if s.flags & MatchmakingCodec.SEAT_AUTO:
			auto += 1
	assert_int(auto).is_equal(2)


func test_decline_locks_the_decliner_and_requeues_the_other() -> void:
	_make_front()
	var a := _client(2)
	var b := _client(3)
	a.matchmaking.queue_join(&"normal_5v5")
	b.matchmaking.queue_join(&"normal_5v5")
	_step(0.5)
	var outcome := {}
	a.matchmaking.ready_result.connect(func(r: Dictionary) -> void: outcome["a"] = r.outcome)
	b.matchmaking.ready_result.connect(func(r: Dictionary) -> void: outcome["b"] = r.outcome)
	a.matchmaking.ready_accept()
	b.matchmaking.ready_decline()
	_step(0.5)
	assert_int(outcome.b).is_equal(MatchmakingCodec.RR_LOCKED)
	assert_int(outcome.a).is_equal(MatchmakingCodec.RR_REQUEUED)
	assert_bool(_front.lockouts.is_locked(_id(3), _t)).is_true()
	assert_int(_front.matchmaker.ticket_of(_id(2))).is_not_equal(0)
	b.matchmaking.queue_join(&"normal_5v5")
	_step(0.3)
	assert_int(b.matchmaking.last_status.state).is_equal(MatchmakingCodec.QS_LOCKED)
	assert_int(b.matchmaking.last_status.code).is_equal(MatchmakingCodec.E_LOCKED)


func test_ready_timeout_fails_the_silent_player() -> void:
	_make_front()
	var a := _client(2)
	var b := _client(3)
	a.matchmaking.queue_join(&"normal_5v5")
	b.matchmaking.queue_join(&"normal_5v5")
	_step(0.5)
	a.matchmaking.ready_accept()
	_step(_rules.ready_check_s + 0.5)
	assert_bool(_front.lockouts.is_locked(_id(3), _t)).is_true()
	assert_bool(_front.lockouts.is_locked(_id(2), _t)).is_false()


func test_crash_void_changes_no_rating_and_requeues() -> void:
	_make_front()
	var ab := _to_running()
	var a: LobbyClient = ab[0]
	var outcome := {}
	a.matchmaking.ready_result.connect(func(r: Dictionary) -> void: outcome["a"] = r.outcome)
	_sup.match_voided.emit(_sup.requests[0].match_id, "process_exit")
	_step(0.3)
	assert_int(outcome.a).is_equal(MatchmakingCodec.RR_VOIDED)
	assert_bool(_front.ratings.store.get_entry(_id(2), &"normal").is_empty()).is_true()
	assert_bool(_front.ratings.store.get_entry(_id(3), &"normal").is_empty()).is_true()
	# Re-queued with priority: both are back, so a new match forms at once.
	assert_bool(_front.matchmaker.ticket_of(_id(2)) != 0 or _front._account_match.has(_id(2))).is_true()
	assert_str(a.matchmaking.last_ready.match).is_not_equal(_sup.requests[0].match_id)
	assert_int(_front.lockouts.strikes(_id(2), LockoutTracker.Kind.LEAVE, _t)).is_equal(0)


func test_remake_voids_and_strikes_the_absent_player() -> void:
	_make_front()
	_to_running()
	_sup.match_result.emit(_sup.requests[0].match_id, {"winner": -1, "remake": true, "remake_absent": [_id(3)],
		"players": [], "abandons": []})
	_step(0.3)
	assert_bool(_front.ratings.store.get_entry(_id(2), &"normal").is_empty()).is_true()
	assert_int(_front.lockouts.strikes(_id(3), LockoutTracker.Kind.LEAVE, _t)).is_equal(1)
	assert_int(_front.lockouts.strikes(_id(2), LockoutTracker.Kind.LEAVE, _t)).is_equal(0)
	assert_int((_clients[2] as LobbyClient).matchmaking.last_result.voided).is_equal(1)


func test_leaver_gets_a_loss_and_a_leave_strike() -> void:
	_make_front()
	_to_running()
	var mid: String = _sup.requests[0].match_id
	var team_b := 1 if _sup.requests[0].roster[0].account == _id(2) else 0
	_sup.abandon_reported.emit(mid, _id(3))
	_sup.match_result.emit(mid, {"winner": team_b, "players": [], "abandons": []})
	_step(0.3)
	assert_float(_front.ratings.entry(_id(3), &"normal").rating).is_less(_rules.rating_initial)
	assert_int(_front.lockouts.strikes(_id(3), LockoutTracker.Kind.LEAVE, _t)).is_equal(1)


func test_reconnect_gets_a_fresh_ticket() -> void:
	_make_front()
	var ab := _to_running()
	var a: LobbyClient = ab[0]
	var first: String = a.matchmaking.last_assigned.ticket
	a.matchmaking.rejoin()
	_step(0.3)
	assert_str(a.matchmaking.last_assigned.ticket).is_not_equal(first)
	var c := _client(4)
	var failed := []
	c.matchmaking.request_failed.connect(func(op: int, code: int) -> void: failed.append([op, code]))
	c.matchmaking.rejoin()
	_step(0.3)
	assert_array(failed).contains([[MatchmakingCodec.OP_REJOIN, MatchmakingCodec.E_NOT_FOUND]])


func test_queue_refused_while_in_a_match() -> void:
	_make_front()
	var ab := _to_running()
	var a: LobbyClient = ab[0]
	a.matchmaking.queue_join(&"normal_5v5")
	_step(0.3)
	assert_int(a.matchmaking.last_status.code).is_equal(MatchmakingCodec.E_IN_MATCH)


func test_ranked_never_fills_with_bots_and_refuses_guests() -> void:
	_make_front()
	var a := _client(2)
	var g := _client(3, true)
	a.matchmaking.queue_join(&"ranked_5v5")
	g.matchmaking.queue_join(&"ranked_5v5")
	_step(0.3)
	assert_int(g.matchmaking.last_status.code).is_equal(MatchmakingCodec.E_GUEST)
	_step(_rules.bot_fill_delay_s * 4)
	assert_dict(a.matchmaking.last_ready).is_empty()
	assert_int(a.matchmaking.last_status.state).is_equal(MatchmakingCodec.QS_QUEUED)


func test_normal_fills_with_bots_after_the_delay_unrated() -> void:
	_make_front()
	var a := _client(2)
	a.matchmaking.queue_join(&"normal_5v5")
	_step(_rules.bot_fill_delay_s + 1.0)
	assert_int(a.matchmaking.last_ready.humans).is_equal(1)
	a.matchmaking.ready_accept()
	_step(_rules.pick_turn_s * 2 + 1.0)
	var setup: Dictionary = _sup.requests[0]
	assert_bool(setup.rules.rated).is_false()
	assert_bool(setup.rules.bots).is_true()
	_sup.match_started.emit(setup.match_id, {})
	_sup.match_result.emit(setup.match_id, {"winner": 0, "players": [], "abandons": []})
	_step(0.3)
	assert_bool(_front.ratings.store.get_entry(_id(2), &"normal").is_empty()).is_true()


func test_party_size_limit_is_five_and_checked_per_queue() -> void:
	_make_front()
	assert_int(OnlineRulesDef.load_default().party_max).is_equal(5)
	assert_int(_acc.parties.max_size).is_equal(5)
	var leader := _client(2)
	for p in [3, 4, 5, 6]:
		_client(p)
		_acc.parties.invite(_id(2), _id(p), 0.0)
		assert_int(_acc.parties.accept(_id(p), _id(2), 0.0)).is_equal(OK)
	_client(7)
	_acc.parties.invite(_id(2), _id(7), 0.0)
	assert_int(_acc.parties.accept(_id(7), _id(2), 0.0)).is_not_equal(OK)  # a sixth member is refused
	leader.matchmaking.queue_join(&"all_random_3v3")
	_step(0.3)
	assert_int(leader.matchmaking.last_status.code).is_equal(MatchmakingCodec.E_PARTY_SIZE)
	(_clients[3] as LobbyClient).matchmaking.queue_join(&"normal_5v5")
	_step(0.3)
	assert_int((_clients[3] as LobbyClient).matchmaking.last_status.code).is_equal(MatchmakingCodec.E_NOT_LEADER)


func test_lockouts_persist_across_a_front_restart_and_expire_by_retention() -> void:
	_dir = OS.get_user_data_dir().path_join("mm_front_test_%d" % Time.get_ticks_usec())
	_make_front(_dir)
	_front.lockouts.record(_id(3), LockoutTracker.Kind.DECLINE, _t)
	_front._strike(_id(3), _t)
	_front._save_lockouts()
	_make_front(_dir)
	assert_bool(_front.lockouts.is_locked(_id(3), _t)).is_true()
	_front.housekeeping(_t + (_rules.lockout_retention_days + 1) * 86400.0)
	assert_bool(_front.lockouts.ids().has(_id(3))).is_false()
	assert_bool(_front.lockouts.is_locked(_id(3), _t)).is_false()


func test_history_retention_purges_old_matches() -> void:
	_make_front()
	_front.history.add({"match_id": "m1", "ended_at": int(_t) - (_rules.history_retention_days + 1) * 86400, "players": []})
	_front.history.add({"match_id": "m2", "ended_at": int(_t), "players": []})
	_front.housekeeping(_t)
	assert_int(_front.history.entries.size()).is_equal(1)
	assert_int(_rules.history_retention_days).is_equal(180)


func test_account_deletion_erases_ratings_reports_history_lockouts() -> void:
	_make_front()
	_to_running()
	var mid: String = _sup.requests[0].match_id
	_sup.match_result.emit(mid, {"winner": 0, "players": [], "abandons": []})
	_step(0.3)
	(_clients[2] as LobbyClient).matchmaking.report(_id(3), 1)
	_step(0.3)
	_front.lockouts.record(_id(3), LockoutTracker.Kind.DECLINE, _t)
	assert_int(_front.reports.list().size()).is_equal(1)
	_acc.account_deleted.emit(_id(3))
	assert_bool(_front.ratings.store.get_entry(_id(3), &"normal").is_empty()).is_true()
	assert_int(_front.reports.list().size()).is_equal(0)
	assert_int(_front.history.of_account(_id(3)).size()).is_equal(0)
	assert_bool(_front.lockouts.ids().has(_id(3))).is_false()


func test_report_and_honour_after_the_match() -> void:
	_make_front()
	_to_running()
	_sup.match_result.emit(_sup.requests[0].match_id, {"winner": 0, "players": [], "abandons": []})
	_step(0.3)
	var a: LobbyClient = _clients[2]
	var fails := []
	a.matchmaking.request_failed.connect(func(op: int, code: int) -> void: fails.append([op, code]))
	a.matchmaking.report(_id(3), 0)
	a.matchmaking.report(_id(3), 0)
	a.matchmaking.honour(_id(3))
	a.matchmaking.honour(_id(2))
	_step(0.3)
	assert_int(_front.reports.list().size()).is_equal(1)
	assert_int(_front.reports.honour_count(_id(3))).is_equal(1)
	assert_array(fails).contains([[MatchmakingCodec.OP_REPORT, MatchmakingCodec.E_DUPLICATE],
		[MatchmakingCodec.OP_HONOUR, MatchmakingCodec.E_NOT_ALLOWED]])


func test_custom_game_with_party_invite_runs_unrated_with_bots() -> void:
	_make_front()
	var host := _client(2)
	var mate := _client(3)
	_acc.parties.invite(_id(2), _id(3), 0.0)
	_acc.parties.accept(_id(3), _id(2), 0.0)
	host.matchmaking.custom_create(1, MatchmakingCodec.PM_CUSTOM, true, 3)
	_step(0.2)
	host.matchmaking.custom_invite()
	_step(0.2)
	assert_str(mate.matchmaking.last_custom.host).is_equal(_id(2))
	mate.matchmaking.custom_join(_id(2))
	_step(0.2)
	mate.matchmaking.custom_pick(2)
	mate.matchmaking.custom_start()  # not the host: refused
	_step(0.2)
	assert_int(_sup.requests.size()).is_equal(0)
	host.matchmaking.custom_start()
	_step(0.3)
	assert_int(_sup.requests.size()).is_equal(1)
	var setup: Dictionary = _sup.requests[0]
	assert_str(MatchSetup.validate(setup)).is_equal("")
	assert_str(setup.map).is_equal("slice")
	assert_int(setup.roster.size()).is_equal(6)
	assert_bool(setup.rules.rated).is_false()
	_sup.match_started.emit(setup.match_id, {})
	_sup.match_result.emit(setup.match_id, {"winner": 0, "players": [], "abandons": [_id(3)]})
	_step(0.3)
	assert_int(_front.lockouts.strikes(_id(3), LockoutTracker.Kind.LEAVE, _t)).is_equal(0)  # custom: no strikes
	assert_int(_front.ratings.store.ids().size()).is_equal(0)


func test_custom_host_reconfigures_and_sets_bot_slots_and_difficulty() -> void:
	_make_front()
	var host := _client(2)
	host.matchmaking.custom_create(1, MatchmakingCodec.PM_CUSTOM, true, 3)
	_step(0.2)
	assert_int(int(host.matchmaking.last_custom.team_size)).is_equal(3)
	host.matchmaking.custom_create(1, MatchmakingCodec.PM_CUSTOM, true, 5)  # change the size: not E_ALREADY
	_step(0.2)
	assert_int(int(host.matchmaking.last_custom.team_size)).is_equal(5)
	assert_int(int(host.matchmaking.last_custom.bots_a)).is_equal(MatchmakingCodec.BOTS_FILL)
	host.matchmaking.custom_bots(1, 2, 2)
	_step(0.2)
	assert_int(int(host.matchmaking.last_custom.bots_a)).is_equal(1)
	assert_int(int(host.matchmaking.last_custom.bots_b)).is_equal(2)
	assert_int(int(host.matchmaking.last_custom.difficulty)).is_equal(2)
	host.matchmaking.custom_start()
	_step(0.3)
	assert_int(_sup.requests.size()).is_equal(1)
	var setup: Dictionary = _sup.requests[0]
	assert_str(MatchSetup.validate(setup)).is_equal("")
	assert_int(setup.roster.size()).is_equal(4)  # host + 1 bot ally + 2 enemy bots
	assert_str(str(setup.rules.bot_difficulty)).is_equal("hard")
	assert_array(setup.rules.bots_per_team).is_equal([1, 2])


func test_load_progress_is_relayed_to_the_match_and_only_rises() -> void:
	_make_front()
	var cl := _to_running()
	var a: LobbyClient = cl[0]
	var b: LobbyClient = cl[1]
	var got: Array = []
	b.matchmaking.load_progress.connect(func(l: Array) -> void: got.append(l.duplicate()))
	a.matchmaking.report_load(40)
	_step(0.2)
	assert_int(got.size()).is_equal(1)
	var loads: Array = got[-1]
	var setup: Dictionary = _sup.requests[0]
	assert_int(loads.size()).is_equal(setup.roster.size())
	var a_seat := -1
	for i in setup.roster.size():
		if str(setup.roster[i].account) == _id(2):
			a_seat = i
		elif bool(setup.roster[i].bot):
			assert_int(int(loads[i])).is_equal(100)  # bots are ready at once
	assert_int(int(loads[a_seat])).is_equal(40)
	a.matchmaking.report_load(20)  # lower: ignored, nothing relayed
	a.matchmaking.report_load(40)
	_step(0.2)
	assert_int(got.size()).is_equal(1)
	a.matchmaking.report_load(100)
	_step(0.2)
	assert_int(int(got[-1][a_seat])).is_equal(100)


func test_load_progress_outside_a_running_match_is_refused() -> void:
	_make_front()
	var a := _client(2)
	var fails: Array = []
	a.matchmaking.request_failed.connect(func(op: int, code: int) -> void: fails.append([op, code]))
	a.matchmaking.report_load(50)
	_step(0.2)
	assert_array(fails).contains([[MatchmakingCodec.OP_LOAD_PROGRESS, MatchmakingCodec.E_NOT_ALLOWED]])


func test_select_chat_reaches_teammates_only_cleaned_and_rate_limited() -> void:
	_make_front()
	var cls: Array[LobbyClient] = []
	for peer in range(2, 8):
		cls.append(_client(peer))
	var a := cls[0]
	_acc.parties.invite(_id(2), _id(3), 0.0)
	_acc.parties.accept(_id(3), _id(2), 0.0)
	var fails: Array = []
	a.matchmaking.request_failed.connect(func(op: int, code: int) -> void: fails.append([op, code]))
	a.matchmaking.select_say("too early")  # not in hero select
	_step(0.2)
	assert_array(fails).contains([[MatchmakingCodec.OP_SELECT_CHAT, MatchmakingCodec.E_NOT_ALLOWED]])
	for i in cls.size():
		if i != 1:  # b is queued by its party leader a
			cls[i].matchmaking.queue_join(&"all_random_3v3")
	_step(0.5)
	for cl in cls:
		cl.matchmaking.ready_accept()
	_step(0.5)
	assert_bool(a.matchmaking.last_pick.is_empty()).is_false()
	var got: Array = []
	for cl in cls:
		var lines: Array = []
		got.append(lines)
		cl.matchmaking.select_chat.connect(func(seat: int, text: String) -> void: lines.append([seat, text]))
	var store := BlockStore.new()
	_acc.store = store
	a.matchmaking.select_say("gl\u202e hf\n")
	_step(0.2)
	var a_seat := int(a.matchmaking.last_pick.you)
	var a_team := int(a.matchmaking.last_pick.seats[a_seat].team)
	var mates := 0
	for i in cls.size():
		var mine: Dictionary = cls[i].matchmaking.last_pick
		var mate := int(mine.seats[int(mine.you)].team) == a_team
		mates += 1 if mate else 0
		# Teammates (and the sender) get the cleaned line; enemies get nothing.
		assert_array(got[i]).is_equal([[a_seat, "gl hf"]] if mate else [])
	assert_int(mates).is_equal(3)
	assert_array(got[1]).is_equal([[a_seat, "gl hf"]])  # the party mate is on a's team
	store.blocks[_id(3)] = [_id(2)]  # b blocks a: b no longer gets a's lines
	a.matchmaking.select_say("again")
	_step(0.2)
	assert_int((got[1] as Array).size()).is_equal(1)
	assert_int((got[0] as Array).size()).is_equal(2)
	for i in ChatFilter.BURST + 1:
		a.matchmaking.select_say("spam %d" % i)
	_step(0.2)
	assert_array(fails).contains([[MatchmakingCodec.OP_SELECT_CHAT, MatchmakingCodec.E_RATE]])
	_acc.store = null


func test_busy_supervisor_retries_then_voids() -> void:
	_make_front()
	_sup.busy = true
	var a := _client(2)
	var b := _client(3)
	a.matchmaking.queue_join(&"normal_5v5")
	b.matchmaking.queue_join(&"normal_5v5")
	_step(0.5)
	a.matchmaking.ready_accept()
	b.matchmaking.ready_accept()
	_step(_rules.pick_turn_s * 2 + 1.0)
	_sup.busy = false
	_step(ALLOC_RETRY)
	assert_int(_sup.requests.size()).is_equal(1)


const ALLOC_RETRY := MatchmakingFront.ALLOCATE_RETRY_S + 0.5


func test_malformed_request_counts_a_violation() -> void:
	_make_front()
	var a := _client(2)
	var b := PackedByteArray([MsgType.MM_REQ, MatchmakingCodec.OP_PICK, 1])  # truncated u16
	a.transport.send(1, Transport.CH_CONTROL, b)
	_step(0.2)
	assert_int(int(_server._violations.get(2, 0))).is_equal(1)
