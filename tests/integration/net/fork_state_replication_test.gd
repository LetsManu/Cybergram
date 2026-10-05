extends GdUnitTestSuite
## W11-V1: a remote client sees another hero's Fork / Mastery state (snapshot, protocol
## v14) and its SKILL_CAST event through the loopback server.

class CastingSource:
	extends ScriptedInputSource
	var cast_seq: int = 15

	func sample(seq: int, out: InputCommand) -> void:
		super(seq, out)
		if seq == cast_seq:
			out.buttons |= InputCommand.BTN_SKILL1
			out.quantize()


var _server: ServerWorld
var _client: ClientWorld
var _link: LoopbackLink
var _net: NetConfig


func _tick(n: int) -> void:
	for i in n:
		_link.advance(_net.tick_dt())
		_client.session.poll()
		_client.tick()
		_server.step()


func test_remote_client_sees_fork_state_and_cast_event() -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	var scene := CombatFixtures.range_scene(false)
	var vesper := load("res://assets/data/heroes/hero_vesper_loom.tres") as HeroDef
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(_net, MovementDef.new(), scene, _link.create_endpoint(1), vesper, MatchRulesDef.new())
	var v_id := _server.add_scripted_hero(CastingSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("DummySpawn1"), vesper, 1)
	_client = auto_free(ClientWorld.new())
	add_child(_client)
	_client.setup(_net, MovementDef.new(), LookSettings.new(), scene, _link.create_endpoint(2),
		ScriptedInputSource.new(CombatFixtures.idle_input()), vesper)
	await get_tree().physics_frame
	var h := _server.hero(v_id)
	var sk := h.combat.abilities.skill(0)
	for k in [SkillNodeDef.Kind.UNLOCK, SkillNodeDef.Kind.BOOST, SkillNodeDef.Kind.FORK_B, SkillNodeDef.Kind.MASTERY]:
		var n := sk.node_of(k)
		if n != null and not sk.has_node(k):
			sk.learn(n, h.combat.stats)
	assert_int(sk.fork()).is_equal(2)
	var casts: Array[GameEvent] = []
	_client.skill_cast_received.connect(func(e: GameEvent) -> void: casts.append(e))
	_tick(40)
	var bits := _client.fork_bits_of(v_id)
	assert_int(NamePlateModel.fork_of(bits, 0)).is_equal(2)
	assert_int(NamePlateModel.fork_of(bits, 1)).is_equal(0)
	assert_int(NamePlateModel.mastery_count(bits)).is_equal(1 if sk.has_mastery() else 0)
	var mine := casts.filter(func(e: GameEvent) -> bool: return e.source_net_id == v_id)
	assert_int(mine.size()).is_greater_equal(1)
	assert_int((mine[0] as GameEvent).cast_slot()).is_equal(0)
	assert_int((mine[0] as GameEvent).cast_fork()).is_equal(2)
