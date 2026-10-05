extends GdUnitTestSuite
## W17B integration: a headless front (FrontServer + MatchmakingFront) with
## the real MatchSupervisor driving fake processes (fake launcher, in-memory
## channel and files, MatchHostAgent per "process"). Two loopback clients go
## queue -> ready -> draft (timeout auto-pick) -> allocation -> join ticket
## (checked by the match side's agent) -> result -> rating change; and a
## process crash voids the match with no rating change.

const FakeFiles := preload("res://tests/unit/hosting/fakes/fake_host_files.gd")
const FakeNet := preload("res://tests/unit/hosting/fakes/fake_host_net.gd")
const FakeLauncher := preload("res://tests/unit/hosting/fakes/fake_process_launcher.gd")
const KEY_HEX := "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
const DT := 1.0 / 30.0

var _link: LoopbackLink
var _net: NetConfig
var _acc: AccountService
var _files: FakeFiles
var _hostnet: FakeNet
var _launcher: FakeLauncher
var _sup: MatchSupervisor
var _front: MatchmakingFront
var _server: FrontServer
var _agents: Dictionary = {}
var _clients: Array = []
var _mono: float = 0.0
var _unix: float = 1_800_000_000.0
var _rules: MatchmakingRulesDef


func before_test() -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	_acc = AccountService.new(null, AuthRulesDef.new(), false, PresenceRegistry.new())
	_files = FakeFiles.new()
	_hostnet = FakeNet.new()
	_launcher = FakeLauncher.new()
	var cfg := HostingConfig.from_env({"CYBERGRAM_MATCH_PORTS": "7800-7801", "CYBERGRAM_WARM_POOL": "1",
		"CYBERGRAM_MAX_MATCHES": "2", "CYBERGRAM_PUBLIC_HOST": "play.example.net"}, 2)
	_sup = MatchSupervisor.new(cfg, _launcher, _hostnet.server, _files, TicketKeyRing.parse_spec("k1:" + KEY_HEX))
	_sup.log_fn = func(_l: String) -> void: pass
	var lc := LaunchConfig.new()
	lc.mm_team_size = 1
	lc.mm_pick_s = 5.0
	_rules = GameSession.front_rules(MatchmakingRulesDef.load_default(), lc)
	var ep := _link.create_endpoint(1)
	_front = MatchmakingFront.new(ep, _acc, _sup, RatingService.new(MemoryRatingStore.new(), _rules),
		ReportStore.new("", _rules), MatchHistoryStore.new("", _rules), _rules)
	_front.clock = func() -> float: return _unix
	_front.log_fn = func(_l: String) -> void: pass
	_server = FrontServer.new(ep, _acc, _front)
	_agents = {}
	_clients = []
	_mono = 0.0


func _client(peer: int) -> LobbyClient:
	var c := LobbyClient.new(_link.create_endpoint(peer), "front.example.net")
	c.request(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": "Player %d" % peer, "emblem": 0,
		"accent": 0, "flags": AccountCodec.FLAG_PRIVACY})
	_clients.append(c)
	return c


func _run(seconds: float) -> void:
	for i in maxi(1, roundi(seconds / DT)):
		_mono += DT
		_unix += DT
		_link.advance(_net.tick_dt())
		_server.step(DT)
		for s: Dictionary in _launcher.spawned:
			if not _agents.has(s.pid) and _launcher.running.has(s.pid):
				var b := _files.read_and_delete(MatchHostAgent.boot_path_from_args(s.args))
				var a := MatchHostAgent.new(b, _hostnet.new_link(), _files)
				_agents[s.pid] = a
				a.mark_ready()
		for pid: int in _agents:
			if _launcher.running.has(pid):
				_agents[pid].tick(_mono)
		_sup.tick(_mono)
		for c: LobbyClient in _clients:
			c.step()


func _agent_of(match_id: String) -> MatchHostAgent:
	for pid: int in _agents:
		if _agents[pid].match_id() == match_id:
			return _agents[pid]
	return null


func _queue_two() -> Array:
	var a := _client(2)
	var b := _client(3)
	_run(0.5)
	a.matchmaking.queue_join(&"normal_5v5")
	b.matchmaking.queue_join(&"normal_5v5")
	_run(0.5)
	a.matchmaking.ready_accept()
	b.matchmaking.ready_accept()
	_run(_rules.pick_turn_s * 2 + 2.0)  # nobody picks: both turns time out
	return [a, b]


func test_queue_to_rating_change_through_the_supervisor() -> void:
	var ab := _queue_two()
	var a: LobbyClient = ab[0]
	var b: LobbyClient = ab[1]
	assert_dict(a.matchmaking.last_assigned).is_not_empty()
	assert_str(a.matchmaking.last_assigned.host).is_equal("play.example.net")
	var mid: String = a.matchmaking.last_assigned.match
	var agent := _agent_of(mid)
	assert_object(agent).is_not_null()
	var ta := agent.verify_ticket(str(a.matchmaking.last_assigned.ticket), _unix)
	assert_int(ta.result).is_equal(JoinTicketVerifier.Result.OK)
	assert_str(ta.account).is_equal(str(a.session.id))
	assert_int(agent.verify_ticket(str(a.matchmaking.last_assigned.ticket), _unix).result) \
		.is_equal(JoinTicketVerifier.Result.REPLAYED)
	var a_team := int(a.matchmaking.last_assigned.team)
	agent.report_result(a_team, [{"account": str(a.session.id), "team": a_team, "kills": 3, "deaths": 0, "assists": 1}])
	_run(1.5)
	assert_int(a.matchmaking.last_result.won).is_equal(1)
	assert_int(a.matchmaking.last_result.rated).is_equal(1)
	assert_float(b.matchmaking.last_result.delta).is_less(0.0)
	var me: Array = a.matchmaking.last_result.players.filter(func(p: Dictionary) -> bool:
		return p.flags & MatchmakingCodec.MEM_YOU)
	assert_int(me[0].kills).is_equal(3)


func test_reconnect_ticket_is_fresh_and_valid() -> void:
	var ab := _queue_two()
	var a: LobbyClient = ab[0]
	var first: String = a.matchmaking.last_assigned.ticket
	a.matchmaking.rejoin()
	_run(0.3)
	var second: String = a.matchmaking.last_assigned.ticket
	assert_str(second).is_not_equal(first)
	var agent := _agent_of(str(a.matchmaking.last_assigned.match))
	assert_int(agent.verify_ticket(second, _unix).result).is_equal(JoinTicketVerifier.Result.OK)


func test_process_crash_voids_without_rating_change() -> void:
	var ab := _queue_two()
	var a: LobbyClient = ab[0]
	var mid: String = a.matchmaking.last_assigned.match
	var outcome := []
	a.matchmaking.ready_result.connect(func(r: Dictionary) -> void: outcome.append(r.outcome))
	var pid := _sup.find_match(mid).pid
	_launcher.end(pid)  # the match process dies
	_run(0.5)
	assert_array(outcome).contains([MatchmakingCodec.RR_VOIDED])
	assert_bool(_front.ratings.store.get_entry(str(a.session.id), &"normal").is_empty()).is_true()
