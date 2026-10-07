extends GdUnitTestSuite
## P1: the front pushes the player's state machine (PHASE events, epoch +
## sequence) through the whole matchmade flow, answers resyncs with a
## snapshot, keeps illegal transitions out, and exposes anonymous metrics, an
## admin snapshot without account ids and JSON log lines with player tags.

const DT := 1.0 / 30.0
const P := PhaseMachine.Player


class FakeSupervisor:
	extends RefCounted
	signal match_started(match_id: String, endpoint: Dictionary)
	signal match_result(match_id: String, result: Dictionary)
	signal match_voided(match_id: String, reason: String)
	signal abandon_reported(match_id: String, account_id: String)
	var requests: Array = []

	func request_match(setup: Dictionary) -> Error:
		requests.append(setup)
		return OK

	func issue_join_ticket(match_id: String, account_id: String, _now: float) -> Dictionary:
		return {"host": "", "port": 7801, "ticket": "cgt1.fake.%s.%s" % [account_id.left(4), match_id.left(4)]}

	func find_match(_id: String) -> Variant:
		return null


var _link: LoopbackLink
var _net: NetConfig
var _acc: AccountService
var _sup: FakeSupervisor
var _front: MatchmakingFront
var _server: FrontServer
var _t: float = 1_800_000_000.0
var _rules: MatchmakingRulesDef
var _clients: Dictionary = {}
var _lines: Array = []


func before_test() -> void:
	_t = 1_800_000_000.0
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	_acc = AccountService.new(null, AuthRulesDef.new(), false, PresenceRegistry.new())
	_sup = FakeSupervisor.new()
	_rules = MatchmakingRulesDef.new()
	_rules.queues = MatchmakingRulesDef.standard_queues()
	for q in _rules.queues:
		if q.id != &"custom":
			q.team_size = 1 if q.id != &"all_random_3v3" else 3
			if q.id != &"all_random_3v3":
				q.lane_slots = []
	_rules.draft_order = PackedInt32Array([1, 1])
	_rules.pick_turn_s = 10.0
	_clients = {}
	_lines = []
	var store := MemoryRatingStore.new()
	_front = MatchmakingFront.new(null, _acc, _sup, RatingService.new(store, _rules), ReportStore.new("", _rules),
		MatchHistoryStore.new("", _rules), _rules, "")
	_front.clock = func() -> float: return _t
	_front.started_at = _t
	_front.log_fn = func(l: String) -> void: _lines.append(l)
	var ep := _link.create_endpoint(1)
	_front.transport = ep
	_server = FrontServer.new(ep, _acc, _front)


func after_test() -> void:
	OpsLog.set_json_mode(-1)


func _client(peer: int) -> LobbyClient:
	var c := LobbyClient.new(_link.create_endpoint(peer))
	_acc.peers[peer] = {"id": _id(peer), "name": "P%d" % peer, "accent": 0, "emblem": 0, "guest": false,
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


func _record(c: LobbyClient) -> Array:
	var seen: Array = []
	c.matchmaking.phase_changed.connect(func(d: Dictionary) -> void: seen.append(d))
	return seen


static func _phases(seen: Array) -> Array:
	return seen.map(func(d: Dictionary) -> int: return int(d.phase))


func test_matchmade_flow_walks_every_phase_in_order() -> void:
	var a := _client(2)
	var b := _client(3)
	var seen := _record(a)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	b.matchmaking.queue_join(&"normal_5v5")
	_step(0.5)
	a.matchmaking.ready_accept()
	b.matchmaking.ready_accept()
	_step(0.5)
	a.matchmaking.draft_pick(1)
	b.matchmaking.draft_pick(2)
	_step(_rules.pick_turn_s + 1.0)
	_sup.match_started.emit(_sup.requests[0].match_id, {"host": "", "port": 7801})
	_step(0.3)
	_sup.match_result.emit(_sup.requests[0].match_id, {"winner": 0, "players": [], "abandons": [], "duration_s": 600})
	_step(0.3)
	assert_array(_phases(seen)).is_equal([P.IDLE, P.QUEUED, P.READY_CHECK, P.CHAMP_SELECT, P.LOADING, P.IN_GAME,
		P.POST_GAME])
	for i in range(1, seen.size()):
		assert_int(int(seen[i].seq)).is_greater(int(seen[i - 1].seq))
		assert_int(int(seen[i].prev)).is_equal(int(seen[i - 1].phase))
	assert_int(int(seen[0].snap)).is_equal(1)  # first event after coming online is a full snapshot
	assert_str(str(seen[2].match)).is_not_empty()
	assert_int(_front.phases.players.illegal_count).is_equal(0)
	assert_int(_front.phases.lobbies.illegal_count).is_equal(0)


func test_queued_phase_carries_queue_wait_and_estimate() -> void:
	var a := _client(2)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	_step(3.0)
	a.matchmaking.request_state_sync()
	_step(0.2)
	var d: Dictionary = a.matchmaking.last_phase
	assert_int(int(d.phase)).is_equal(P.QUEUED)
	assert_int(int(d.queue)).is_equal(MatchmakingClient.queue_index(&"normal_5v5"))
	assert_int(int(d.waited)).is_greater_equal(2)  # 3 s of float steps
	assert_int(int(d.estimate)).is_greater(0)


func test_decline_moves_the_decliner_to_idle_and_requeues_the_other() -> void:
	var a := _client(2)
	var b := _client(3)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	b.matchmaking.queue_join(&"normal_5v5")
	_step(0.5)
	a.matchmaking.ready_accept()
	b.matchmaking.ready_decline()
	_step(0.5)
	assert_int(int(a.matchmaking.last_phase.phase)).is_equal(P.QUEUED)
	assert_int(int(b.matchmaking.last_phase.phase)).is_equal(P.IDLE)
	assert_int(int(b.matchmaking.last_phase.locked)).is_greater(0)
	assert_float(_front.metrics.value("cybergram_ready_check_declines_total")).is_equal(1.0)
	assert_int(_front.phases.players.illegal_count).is_equal(0)


func test_resync_answers_with_a_snapshot_even_after_a_lost_sequence() -> void:
	var a := _client(2)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	_step(0.3)
	var seq := int(a.matchmaking.last_phase.seq)
	a.matchmaking.last_phase = {"epoch": _front.phases.epoch, "seq": 999, "phase": P.IDLE}  # a confused client
	a.matchmaking.request_state_sync()
	_step(0.2)
	assert_int(int(a.matchmaking.last_phase.phase)).is_equal(P.QUEUED)
	assert_int(int(a.matchmaking.last_phase.snap)).is_equal(1)
	assert_int(int(a.matchmaking.last_phase.seq)).is_equal(seq)


func test_stale_and_new_epoch_rules() -> void:
	var last := {"epoch": 5, "seq": 10}
	assert_bool(MatchmakingClient.phase_is_newer(last, {"epoch": 5, "seq": 9, "snap": 0})).is_false()
	assert_bool(MatchmakingClient.phase_is_newer(last, {"epoch": 5, "seq": 10, "snap": 0})).is_false()
	assert_bool(MatchmakingClient.phase_is_newer(last, {"epoch": 5, "seq": 11, "snap": 0})).is_true()
	assert_bool(MatchmakingClient.phase_is_newer(last, {"epoch": 6, "seq": 1, "snap": 0})).is_true()  # server restart
	assert_bool(MatchmakingClient.phase_is_newer(last, {"epoch": 5, "seq": 1, "snap": 1})).is_true()
	assert_bool(MatchmakingClient.phase_is_newer({}, {"epoch": 5, "seq": 1, "snap": 0})).is_true()


func test_disconnect_while_queued_shows_reconnecting_then_drops_after_the_grace() -> void:
	var a := _client(2)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	_step(0.3)
	_acc.peers.erase(2)
	_step(0.3)
	assert_int(_front.phases.players.state_of(_id(2))).is_equal(P.RECONNECTING)
	_step(_rules.pick_disconnect_grace_s + 3.0)
	assert_int(_front.phases.players.state_of(_id(2))).is_equal(P.OFFLINE)
	assert_int(_front.matchmaker.ticket_of(_id(2))).is_equal(0)
	assert_int(_front.phases.players.illegal_count).is_equal(0)


func test_metrics_render_queue_ready_and_phase_numbers() -> void:
	var a := _client(2)
	var b := _client(3)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	b.matchmaking.queue_join(&"normal_5v5")
	_step(0.5)
	a.matchmaking.ready_accept()
	b.matchmaking.ready_accept()
	_step(0.5)
	var text := _server.metrics_text()
	assert_str(text).contains("cybergram_ready_checks_total{outcome=\"accepted\"} 1")
	assert_str(text).contains("cybergram_ready_checks_total{outcome=\"started\"} 1")
	assert_str(text).contains("cybergram_players{phase=\"ChampSelect\"} 2")
	assert_str(text).contains("cybergram_lobbies{state=\"ChampSelect\"} 1")
	assert_str(text).contains("cybergram_connected_clients 2")
	assert_str(text).contains("# TYPE cybergram_queue_players gauge")
	assert_str(text).not_contains(_id(2))


func test_admin_snapshot_has_live_state_and_no_account_ids() -> void:
	var a := _client(2)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	_step(0.3)
	var snap := _server.admin_snapshot()
	var json := JSON.stringify(snap)
	assert_str(json).not_contains(_id(2))
	assert_str(json).not_contains("P2")  # no display names
	assert_int((snap.players as Array).size()).is_equal(1)
	assert_str(str(snap.players[0].phase)).is_equal("Queued")
	assert_int(int(snap.queues[0].players)).is_equal(1)
	assert_bool(bool(snap.health.checks.transport)).is_true()
	assert_bool((snap.events as Array).size() > 0).is_true()
	assert_str(OpsAdminPage.html(snap)).contains("Queued")


func test_json_log_lines_use_player_tags() -> void:
	OpsLog.set_json_mode(1)
	var a := _client(2)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	_step(0.3)
	var found := false
	for l: String in _lines:
		var d: Variant = JSON.parse_string(l)
		assert_object(d).override_failure_message("not JSON: " + l).is_not_null()
		assert_str(l).not_contains(_id(2))
		if d is Dictionary and str(d.get("event", "")) == "player_phase" and str(d.get("msg", "")).contains("Queued"):
			found = str(d.get("player", "")) == OpsLog.tag(_id(2))
	assert_bool(found).is_true()


func test_text_mode_keeps_the_classic_front_lines() -> void:
	OpsLog.set_json_mode(0)
	var a := _client(2)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	_step(0.3)
	assert_bool(_lines.has("[front] queue normal_5v5: party of 1 joined")).is_true()


## Owner report 2026-10-06: after leaving a match the admin page still showed
## the player InGame until the match ended. Once the match reports the
## abandon (the reconnect window is over), the leaver is released: IDLE.
func test_abandon_releases_the_leaver_from_in_game() -> void:
	var a := _client(2)
	var b := _client(3)
	var seen := _record(a)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	b.matchmaking.queue_join(&"normal_5v5")
	_step(0.5)
	a.matchmaking.ready_accept()
	b.matchmaking.ready_accept()
	_step(0.5)
	a.matchmaking.draft_pick(1)
	b.matchmaking.draft_pick(2)
	_step(_rules.pick_turn_s + 1.0)
	var mid: String = _sup.requests[0].match_id
	_sup.match_started.emit(mid, {"host": "", "port": 7801})
	_step(0.3)
	assert_int(int(seen[-1].phase)).is_equal(P.IN_GAME)
	_sup.abandon_reported.emit(mid, _id(2))
	_step(0.3)
	assert_int(int(seen[-1].phase)).is_equal(P.IDLE)
	assert_int(_front.phases.players.illegal_count).is_equal(0)




## Owner log 2026-10-07: "rejected player ...: Idle -> PostGame". A player who
## abandoned (already back to Idle) must stay Idle when the match ends; only the
## players still in it get the post-game window.
func test_match_end_after_abandon_keeps_the_leaver_idle() -> void:
	var a := _client(2)
	var b := _client(3)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	b.matchmaking.queue_join(&"normal_5v5")
	_step(0.5)
	a.matchmaking.ready_accept()
	b.matchmaking.ready_accept()
	_step(0.5)
	a.matchmaking.draft_pick(1)
	b.matchmaking.draft_pick(2)
	_step(_rules.pick_turn_s + 1.0)
	var mid: String = _sup.requests[0].match_id
	_sup.match_started.emit(mid, {"host": "", "port": 7801})
	_step(0.3)
	_sup.abandon_reported.emit(mid, _id(2))
	_step(0.3)
	assert_int(_front.phases.players.state_of(_id(2))).is_equal(P.IDLE)
	_sup.match_result.emit(mid, {"winner": 0, "players": [], "abandons": [_id(2)], "duration_s": 600})
	_step(0.3)
	assert_int(_front.phases.players.state_of(_id(2))).is_equal(P.IDLE)
	assert_int(_front.phases.players.state_of(_id(3))).is_equal(P.POST_GAME)
	assert_int(_front.phases.players.illegal_count).is_equal(0)

## Owner log 2026-10-06: a player who closed the game during a running match
## (front connection gone, seat kept: InGame) stayed InGame after the match
## ended, and every sync logged "rejected player ...: InGame -> Offline".
## The match end must take them to Offline (and forget them).
func test_match_end_while_disconnected_goes_offline() -> void:
	var a := _client(2)
	var b := _client(3)
	_step(0.2)
	a.matchmaking.queue_join(&"normal_5v5")
	b.matchmaking.queue_join(&"normal_5v5")
	_step(0.5)
	a.matchmaking.ready_accept()
	b.matchmaking.ready_accept()
	_step(0.5)
	a.matchmaking.draft_pick(1)
	b.matchmaking.draft_pick(2)
	_step(_rules.pick_turn_s + 1.0)
	var mid: String = _sup.requests[0].match_id
	_sup.match_started.emit(mid, {"host": "", "port": 7801})
	_step(0.3)
	_acc.peers.erase(2)  # the game (and its front connection) closed mid-match
	_clients.erase(2)
	_step(0.3)
	assert_int(_front.phases.players.state_of(_id(2))).is_equal(P.IN_GAME)
	_sup.match_result.emit(mid, {"winner": 0, "players": [], "abandons": [], "duration_s": 600})
	_step(0.3)
	assert_int(_front.phases.players.state_of(_id(2))).is_equal(P.OFFLINE)
	assert_int(_front.phases.players.illegal_count).is_equal(0)


## Three accounts in memory (ids, usernames, created_at): what /admin/accounts reads.
class ListStore:
	extends AccountStore
	var rows: Dictionary = {}

	func ids() -> PackedStringArray:
		return PackedStringArray(rows.keys())

	func get_by_id(id: String) -> Dictionary:
		return (rows.get(id, {}) as Dictionary).duplicate(true)


## Owner request 2026-10-06: the admin sees which accounts exist, newest first,
## with the live phase and the log tag; no password or recovery data.
func test_accounts_page_lists_accounts_newest_first_without_secrets() -> void:
	var st := ListStore.new()
	for n in [2, 3, 4]:
		var a := AccountStore.new_account(_id(n), "user%d" % n, {"algo": "x", "hash": "SECRETHASH", "salt": "s", "iterations": 1},
			{"display_name": "Name %d" % n}, 1_790_000_000 + n * 100)
		st.rows[_id(n)] = a
	_acc.store = st
	_client(3)
	_step(0.3)
	var snap := _server.accounts_snapshot()
	assert_int(int(snap.total)).is_equal(3)
	var names: Array = (snap.rows as Array).map(func(r: Dictionary) -> String: return r.username)
	assert_array(names).is_equal(["user4", "user3", "user2"])
	var r3: Dictionary = (snap.rows as Array)[1]
	assert_str(r3.display_name).is_equal("Name 3")
	assert_str(r3.phase).is_equal("Idle")
	assert_str(r3.player).is_equal(OpsLog.tag(_id(3)))
	assert_str(r3.created).ends_with("Z")
	var json := JSON.stringify(snap)
	assert_str(json).not_contains("SECRETHASH")
	assert_str(json).not_contains(_id(3))
	_acc.store = null
