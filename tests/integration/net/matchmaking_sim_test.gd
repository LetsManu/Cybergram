extends GdUnitTestSuite
## P3: headless simulation of the whole pre-match flow with many clients
## over loopback: parties and solos queue Normal (blind) and Ranked (draft),
## one player declines, one ranked player times out with nothing hovered
## (dodge), everyone else hovers / locks / times out, and matches start.
## Checks: no illegal state transition, lockouts, re-queues, metrics,
## and a wall-clock budget (the run must stay fast and always end).

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
		if q.id == &"normal_5v5" or q.id == &"ranked_5v5":
			q.lane_slots = []
		if q.id == &"normal_5v5":
			q.pick_mode = MatchQueueDef.PickMode.BLIND
		if q.id == &"ranked_5v5":
			q.pick_timeout_dodges = true
	_rules.draft_order = PackedInt32Array([1, 2, 2, 2, 2, 1])
	_rules.pick_turn_s = 10.0
	_rules.blind_pick_s = 10.0
	_rules.finalize_s = 20.0
	_rules.finalize_lock_s = 5.0
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


func _party(leader: int, member: int) -> void:
	_acc.parties.invite(_id(leader), _id(member), _t)
	_acc.parties.accept(_id(member), _id(leader), _t)


## Every client in a pick phase hovers a free hero; even peers also lock it.
func _play_picks() -> void:
	for p: int in _clients:
		var c: LobbyClient = _clients[p]
		var st: Dictionary = c.matchmaking.last_pick
		if st.is_empty() or int(st.seats[st.you].flags) & MatchmakingCodec.SEAT_PICKED != 0:
			continue
		var used := {}
		for s: Dictionary in st.seats:
			if int(s.team) == int(st.seats[st.you].team) and int(s.hero) > 0:
				used[int(s.hero)] = true
		for k in range(7):
			var h := (p + k) % 7 + 1  # spread choices: allies acting in the same frame rarely collide
			if not used.has(h):
				c.matchmaking.draft_hover(h)
				if p % 2 == 0:
					c.matchmaking.draft_pick(h)
				break


func test_twenty_clients_parties_declines_dodge_and_matches_start() -> void:
	var wall := Time.get_ticks_msec()
	OpsLog.set_json_mode(0)
	for p in range(2, 22):
		_client(p)
	_party(2, 3)
	_party(4, 5)
	_party(12, 13)
	_step(0.3)
	# Normal (blind): peers 2..11 (two parties of 2 + 6 solos); Ranked (draft): 12..21.
	for p in range(2, 22):
		if p in [3, 5, 13]:
			continue  # party members: the leader queues for them
		_clients[p].matchmaking.queue_join(&"normal_5v5" if p < 12 else &"ranked_5v5")
	_step(0.5)
	assert_int(_front.forming_matches()).is_equal(2)
	# Round 1: peer 7 declines the normal ready check; everyone else accepts.
	for p: int in _clients:
		if p == 7:
			_clients[p].matchmaking.ready_decline()
		else:
			_clients[p].matchmaking.ready_accept()
	_step(0.5)
	assert_bool(_front.lockouts.is_locked(_id(7), _t)).is_true()
	assert_int(int(_clients[2].matchmaking.last_phase.phase)).is_equal(P.QUEUED)  # re-queued with priority
	assert_int(int(_clients[12].matchmaking.last_phase.phase)).is_equal(P.CHAMP_SELECT)
	# Ranked draft: the first picker of the ranked match does nothing at all -> dodge.
	var ranked_first := ""
	for p in range(12, 22):
		var st: Dictionary = _clients[p].matchmaking.last_pick
		if not st.is_empty() and int(st.seats[st.you].flags) & MatchmakingCodec.SEAT_PICKING != 0:
			ranked_first = _id(p)
	assert_str(ranked_first).is_not_empty()
	_step(_rules.pick_turn_s + 0.5)
	assert_int(_front.lockouts.strikes(ranked_first, LockoutTracker.Kind.DODGE, _t)).is_equal(1)
	assert_float(_front.metrics.value("cybergram_dodges_total")).is_equal(1.0)
	# Fresh players log in and queue in the same frame (the Offline -> Queued
	# path goes through Reconnecting): one refills Normal; Ranked lost the
	# dodger (and, if they were in a party, their party), so two refill it.
	_client(30).matchmaking.queue_join(&"normal_5v5")
	_client(31).matchmaking.queue_join(&"ranked_5v5")
	_client(32).matchmaking.queue_join(&"ranked_5v5")
	_step(0.5)
	for p: int in _clients:
		_clients[p].matchmaking.ready_accept()
	_step(0.5)
	# Pick phases: hover everywhere, half lock, the rest auto-lock their hover at the deadline.
	for i in 24:
		_play_picks()
		_step(_rules.pick_turn_s / 3.0)
	_step(_rules.finalize_s + 1.0)
	assert_int(_sup.requests.size()).is_equal(2)
	for setup: Dictionary in _sup.requests:
		assert_str(MatchSetup.validate(setup)).is_equal("")
		for e: Dictionary in setup.roster:
			assert_str(String(e.hero)).is_not_empty()
	for setup: Dictionary in _sup.requests:
		_sup.match_started.emit(setup.match_id, {"host": "", "port": 7801})
	_step(0.3)
	assert_int(_front.running_matches()).is_equal(2)
	assert_int(_front.phases.players.illegal_count).is_equal(0)
	assert_int(_front.phases.lobbies.illegal_count).is_equal(0)
	assert_int(_front.phases.parties.illegal_count).is_equal(0)
	var text := _server.metrics_text()
	assert_str(text).contains("cybergram_matches_total{event=\"started\"} 2")
	assert_str(text).contains("cybergram_players{phase=\"InGame\"} 20")
	assert_str(text).contains("cybergram_illegal_transitions_total 0")
	assert_int(Time.get_ticks_msec() - wall).is_less(60_000)  # hard wall-clock budget
