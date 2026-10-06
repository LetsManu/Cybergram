extends GdUnitTestSuite
## P3: champ select over the network (2v2 queues for speed): ally-only
## hovers, blind pick hides enemy heroes until everyone locked, ranked pick
## timeout with nothing hovered = dodge (own lockout ladder + rating
## penalty), a hovered hero auto-locks, trades in the finalize window.

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
			q.team_size = 2
			q.lane_slots = []
		if q.id == &"normal_5v5":
			q.pick_mode = MatchQueueDef.PickMode.BLIND
		if q.id == &"ranked_5v5":
			q.pick_timeout_dodges = true
	_rules.draft_order = PackedInt32Array([1, 2, 1])
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


func _record(c: LobbyClient) -> Array:
	var seen: Array = []
	c.matchmaking.phase_changed.connect(func(d: Dictionary) -> void: seen.append(d))
	return seen


static func _phases(seen: Array) -> Array:
	return seen.map(func(d: Dictionary) -> int: return int(d.phase))




## Four players queue `queue` and accept; returns [a, b, c, d] (peers 2..5).
func _to_select(queue: StringName) -> Array:
	var cs: Array = []
	for p in range(2, 6):
		cs.append(_client(p))
	_step(0.2)
	for c: LobbyClient in cs:
		c.matchmaking.queue_join(queue)
	_step(0.5)
	for c: LobbyClient in cs:
		c.matchmaking.ready_accept()
	_step(0.5)
	return cs


static func _seat_of(st: Dictionary, own: bool) -> Array:
	return (st.seats as Array).filter(func(s: Dictionary) -> bool:
		return (int(s.team) == int(st.seats[st.you].team)) == own)


func _mate(cs: Array, c: LobbyClient) -> LobbyClient:
	var st: Dictionary = c.matchmaking.last_pick
	var my_team := int(st.seats[st.you].team)
	for o: LobbyClient in cs:
		if o != c and int(o.matchmaking.last_pick.seats[o.matchmaking.last_pick.you].team) == my_team:
			return o
	return null


func test_blind_hover_is_ally_only_and_enemy_picks_stay_hidden() -> void:
	var cs := _to_select(&"normal_5v5")
	var a: LobbyClient = cs[0]
	var st: Dictionary = a.matchmaking.last_pick
	assert_int(int(st.mode)).is_equal(MatchmakingCodec.PM_BLIND)
	assert_int(int(st.turn_team)).is_equal(DraftSession.BOTH)
	var mate := _mate(cs, a)
	a.matchmaking.draft_hover(3)
	_step(0.3)
	var seen_by_mate: Dictionary = mate.matchmaking.last_pick
	var hovered := _seat_of(seen_by_mate, true).filter(func(s: Dictionary) -> bool:
		return int(s.flags) & MatchmakingCodec.SEAT_HOVER != 0)
	assert_int(hovered.size()).is_equal(1)
	assert_int(int(hovered[0].hero)).is_equal(3)
	for o: LobbyClient in cs:
		if o != a and o != mate:
			for s: Dictionary in _seat_of(o.matchmaking.last_pick, false):
				assert_int(int(s.hero)).is_equal(0)  # the enemy never sees a hover
	mate.matchmaking.draft_pick(3)  # the ally declared it
	_step(0.3)
	assert_int(int(mate.matchmaking.last_pick.seats[mate.matchmaking.last_pick.you].hero)).is_equal(0)
	a.matchmaking.draft_pick(3)
	_step(0.3)
	for o: LobbyClient in cs:
		if o != a and o != mate:
			for s: Dictionary in _seat_of(o.matchmaking.last_pick, false):
				assert_int(int(s.hero)).is_equal(0)  # locked but hidden until everyone locked
	mate.matchmaking.draft_pick(1)
	_pick_enemies(cs, a, mate)
	_step(0.3)
	var fin: Dictionary = cs[3].matchmaking.last_pick
	assert_int(int(fin.stage)).is_equal(MatchmakingCodec.PS_FINALIZE)
	for s: Dictionary in fin.seats:
		assert_int(int(s.hero)).is_greater(0)  # revealed
	assert_int(int(fin.trade_s)).is_greater(10)


func test_trade_in_the_finalize_window_swaps_heroes() -> void:
	var cs := _to_select(&"normal_5v5")
	var a: LobbyClient = cs[0]
	var mate := _mate(cs, a)
	a.matchmaking.draft_pick(1)
	mate.matchmaking.draft_pick(2)
	_pick_enemies(cs, a, mate)
	_step(0.3)
	var a_seat := int(a.matchmaking.last_pick.you)  # seat indices are the same wire order for everyone
	a.matchmaking.aram_swap_request(int(mate.matchmaking.last_pick.you))
	_step(0.3)
	assert_array(mate.matchmaking.last_pick.swap_from).is_equal([a_seat])
	mate.matchmaking.aram_swap_accept(a_seat)
	_step(0.3)
	assert_int(int(a.matchmaking.last_pick.seats[a.matchmaking.last_pick.you].hero)).is_equal(2)
	assert_int(int(mate.matchmaking.last_pick.seats[mate.matchmaking.last_pick.you].hero)).is_equal(1)
	_step(_rules.finalize_s)
	assert_int(_sup.requests.size()).is_equal(1)


## The two enemies of `a` lock distinct heroes (4 and 6).
func _pick_enemies(cs: Array, a: LobbyClient, mate: LobbyClient) -> void:
	var h := 4
	for o: LobbyClient in cs:
		if o != a and o != mate:
			o.matchmaking.draft_pick(h)
			h += 2


func test_ranked_timeout_without_hover_is_a_dodge_with_its_own_ladder() -> void:
	var cs := _to_select(&"ranked_5v5")
	_step(_rules.pick_turn_s + 0.5)  # first picker does nothing at all
	var dodger := ""
	for c: LobbyClient in cs:
		var id := str(_acc.peers[_clients.find_key(c)].id)
		if _front.lockouts.strikes(id, LockoutTracker.Kind.DODGE, _t) == 1:
			dodger = id
	assert_str(dodger).is_not_empty()
	assert_float(_front.lockouts.locked_until(dodger, _t) - _t).is_greater(300.0)  # 360 s ladder step
	assert_int(_front.lockouts.strikes(dodger, LockoutTracker.Kind.DECLINE, _t)).is_equal(0)
	assert_float(_front.ratings.entry(dodger, &"ranked").rating).is_equal(_rules.rating_initial - _rules.dodge_rating_penalty)
	assert_float(_front.metrics.value("cybergram_dodges_total")).is_equal(1.0)
	var requeued := 0
	for c: LobbyClient in cs:
		if int(c.matchmaking.last_phase.phase) == P.QUEUED:
			requeued += 1
	assert_int(requeued).is_equal(3)


func test_ranked_hover_auto_locks_instead_of_dodging() -> void:
	var cs := _to_select(&"ranked_5v5")
	for c: LobbyClient in cs:
		c.matchmaking.draft_hover(5)  # everyone hovers; allies cannot share it, so only one per team holds
	_step(0.3)
	for c: LobbyClient in cs:
		if int(c.matchmaking.last_pick.seats[c.matchmaking.last_pick.you].flags) & MatchmakingCodec.SEAT_HOVER == 0:
			c.matchmaking.draft_hover(6)
	_step(_rules.pick_turn_s + 0.5)
	assert_float(_front.metrics.value("cybergram_dodges_total")).is_equal(0.0)
	assert_int(int(cs[0].matchmaking.last_phase.phase)).is_equal(P.CHAMP_SELECT)
