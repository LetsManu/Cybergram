extends GdUnitTestSuite
## E9 integration (match-flow-and-map.md §3.6, AC 10-11; M1 "win by Uplink
## destruction" scenario): on the slice map, through the real server tick and a
## loopback client, three scripted Concord heroes (Concord already holds the Mid,
## debug setup) capture Syndicate's Outer then Inner. The Syndicate Uplink is
## sealed until the Inner flips and Exposed on that tick; a Wardling bolt deals
## 50%; the heroes walk into the HQ and destroy it with hitscan (start Integrity
## lowered by debug setup); the match ends with Concord winning, and the client
## receives the End state, the Uplink states and the phase event.

const HZ: int = 30
const MAP_PATH := "res://assets/data/match/map_slice_lane.tres"
const C := MapDef.TEAM_CONCORD
const S := MapDef.TEAM_SYNDICATE
## Debug: Syndicate Uplink Integrity at the start (keeps the siege short).
const SIEGE_INTEGRITY: float = 600.0


## Walks a navmesh path to `goal`; in siege mode aims at the Uplink core and fires.
class Siege extends WardlingFixtures.Owner:
	var siege_target: Vector3 = Vector3.INF

	func go(to: Vector3) -> void:
		goal = to
		arrived = false
		_path = PackedVector3Array()
		_i = 1

	func sample(seq: int, out: InputCommand) -> void:
		super.sample(seq, out)
		var h := server.hero(hero_id)
		if siege_target == Vector3.INF or h == null or not arrived:
			return
		var eye := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
		var to := siege_target - eye
		out.yaw = fposmod(atan2(-to.x, -to.z), TAU)
		out.pitch = atan2(to.y, Vector2(to.x, to.z).length())
		if seq % 2 == 0:
			out.buttons |= InputCommand.BTN_FIRE
		out.quantize()


var _server: ServerWorld
var _client: ClientWorld
var _link: LoopbackLink
var _net: NetConfig


func _tick() -> void:
	_link.advance(_net.tick_dt())
	_client.session.poll()
	_client.tick()
	_server.step()


func _build(clock_scale: float) -> MapDef:
	var def := load(MAP_PATH) as MapDef
	var rules := load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	var movement := load("res://assets/data/movement/movement_default.tres") as MovementDef
	_server.setup(_net, movement, def.scene, _link.create_endpoint(1), CombatFixtures.vesper(), rules)
	_server.setup_objectives(def)
	_server.setup_match(def, clock_scale)
	_server.enable_wardlings(def, WardlingFixtures.rules(), load(WardlingFixtures.PICKET) as WardlingDef)
	_server.wardlings.vanguard_enabled = false
	_client = auto_free(ClientWorld.new())
	add_child(_client)
	_client.setup(_net, movement, LookSettings.new(), def.scene, _link.create_endpoint(2),
		ScriptedInputSource.new(CombatFixtures.idle_input()), CombatFixtures.vesper())
	_client.setup_objectives(def)
	return def


func test_capture_to_enemy_inner_exposes_and_destroys_the_uplink() -> void:
	var def := _build(10.0)
	var m := _server.match_flow
	var su := m.uplink_of(S)
	su.integrity = SIEGE_INTEGRITY
	_server.objectives.debug_set_owner(&"s_mid", C)
	var bo := _server.objectives.find(&"s_bo")
	var bi := _server.objectives.find(&"s_bi")
	var squad: Array[Siege] = []
	for k in 3:
		var s := Siege.new()
		s.server = _server
		var start := _server.objectives.find(&"s_mid").def.position + Vector3(-3.0 + 3.0 * k, 0.05, 0.0)
		s.hero_id = _server.add_scripted_hero(s, start, CombatFixtures.vesper(), C)
		s.stop_m = 3.0
		s.go(bo.def.position + Vector3(-2.0 + 2.0 * k, 0.0, 0.0))
		squad.append(s)
	var ended: Array = []
	_client.match_ended.connect(func(w: int, r: int) -> void: ended.append([w, r]))
	var phases: Array = []
	_client.match_phase_changed.connect(func(p: int) -> void: phases.append(p))
	assert_bool(await WardlingFixtures.await_nav(get_tree(), _server)).is_true()
	# Capture S-BO (enemy Outer): still sealed afterwards.
	var bo_flip := -1
	for i in HZ * 180:
		_tick()
		if bo.owner == C:
			bo_flip = _server.tick
			break
	assert_int(bo_flip).is_greater(0)
	assert_bool(su.exposed).is_false()
	assert_float(su.integrity).is_equal(SIEGE_INTEGRITY)
	# Capture S-BI (enemy Inner): Exposed on the flip tick.
	for k in squad.size():
		squad[k].go(bi.def.position + Vector3(-2.0 + 2.0 * k, 0.0, 0.0))
	var bi_flip := -1
	var exposed_tick := -1
	for i in HZ * 180:
		_tick()
		if bi.owner == C:
			bi_flip = _server.tick
			if su.exposed:
				exposed_tick = _server.tick
			break
	assert_int(bi_flip).is_greater(0)
	assert_int(exposed_tick).is_equal(bi_flip)
	assert_float(su.integrity).is_equal(SIEGE_INTEGRITY)  # nothing landed while sealed
	assert_bool(m.uplink_of(C).exposed).is_false()
	# A Wardling bolt (raw 10) lands at 50% (C7).
	var core := su.aim_point()
	var from := core + Vector3(0.0, 0.0, 12.0)
	_server.wardlings.projectiles.spawn(from, Vector3.FORWARD, 55.0, 20.0, 10.0, C, 0, core)
	for i in 10:
		_tick()
	assert_float(su.integrity).is_equal_approx(SIEGE_INTEGRITY - 5.0, 1e-3)
	# Siege: the heroes walk inside the HQ gate and shoot the core with hitscan.
	for k in squad.size():
		squad[k].go(su.base + Vector3(-3.0 + 3.0 * k, 0.0, 12.0))
		squad[k].siege_target = core
	for i in HZ * 120:
		_tick()
		if m.is_over():
			break
	print("uplink siege: Outer flip t%d, Inner flip t%d, end t%d (match %s, phase %s)" % [bo_flip, bi_flip,
		_server.tick, MatchRules.format_clock(m.time_s), MatchRules.PHASE_NAMES[m.phase]])
	assert_bool(su.is_destroyed()).is_true()
	assert_int(m.phase).is_equal(MatchRules.Phase.END)
	assert_int(m.winner).is_equal(C)
	assert_int(m.end_reason).is_equal(MatchRules.EndReason.UPLINK_DESTROYED)
	# The clock ran at 10x: Surge I (15:00 match time) started on the way, D_s 0.85.
	assert_float(_server.objectives.duration_scale).is_equal_approx(0.85, 1e-6)
	# Replication: the client gets the End state, both Uplinks and the phase event.
	for i in 5:
		_tick()
	var ms := _client.match_state
	assert_object(ms).is_not_null()
	assert_int(ms.phase).is_equal(MatchRules.Phase.END)
	assert_int(ms.winner).is_equal(C)
	assert_int(ms.end_reason).is_equal(MatchRules.EndReason.UPLINK_DESTROYED)
	assert_float(_client.uplink_state(S).integrity).is_equal(0.0)
	assert_float(_client.uplink_state(C).integrity).is_equal(33000.0)
	assert_array(ended).is_equal([[C, MatchRules.EndReason.UPLINK_DESTROYED]])
	assert_array(phases).contains([MatchRules.Phase.SURGE_I, MatchRules.Phase.END])
	for v in _client.uplink_views():
		assert_bool(v.destroyed).is_equal(v.team == S)


func test_deploy_mid_lock_replicates_and_respawn_uses_match_minutes() -> void:
	_build(1.0)
	var m := _server.match_flow
	var dummy := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.objectives.find(&"s_ao").def.position + Vector3(0.0, 0.05, 0.0), CombatFixtures.vesper(), C)
	await get_tree().physics_frame
	for i in 5:
		_tick()
	assert_int(m.phase).is_equal(MatchRules.Phase.DEPLOY)
	assert_int(_client.match_state.phase).is_equal(MatchRules.Phase.DEPLOY)
	assert_bool(_client.hardpoints[2].locked[C]).is_true()
	assert_bool(_client.hardpoints[2].locked[S]).is_true()
	assert_float(_client.match_state.next_phase_s).is_equal(60.0)
	# C11 on the match clock: a death at 12:00 match time waits 10.8 s (324 ticks).
	m.time_s = 720.0
	var h := _server.hero(dummy)
	_server.damage_hero(h, DamageInfo.make(1.0e6, 0, S))
	assert_bool(h.combat.dead).is_true()
	assert_int(h.combat.respawn_tick - _server.tick).is_equal(324)
	_tick()
	assert_int(m.phase).is_equal(MatchRules.Phase.SKIRMISH)
	for i in 3:
		_tick()
	assert_bool(_client.hardpoints[2].locked[C]).is_false()
