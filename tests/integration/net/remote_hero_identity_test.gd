extends GdUnitTestSuite
## M1 fix: remote heroes render as their own hero, not the baseline (Ryker).
## A Vesper client sees a Brannoc and a Vesper dummy through the loopback
## server; the snapshot carries each hero's ContentDB index and ClientWorld
## drives HeroView.set_hero from it.

const HZ: int = 30

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


func test_remote_views_show_the_replicated_hero() -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	var scene := CombatFixtures.range_scene(false)
	var vesper := load("res://assets/data/heroes/hero_vesper_loom.tres") as HeroDef
	var brannoc := load("res://assets/data/heroes/hero_brannoc.tres") as HeroDef
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(_net, MovementDef.new(), scene, _link.create_endpoint(1), vesper, MatchRulesDef.new())
	var b_id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("DummySpawn1"), brannoc, 1)
	var v_id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("DummySpawn1") + Vector3(3.0, 0.0, 0.0), vesper, 1)
	_client = auto_free(ClientWorld.new())
	add_child(_client)
	_client.setup(_net, MovementDef.new(), LookSettings.new(), scene, _link.create_endpoint(2),
		ScriptedInputSource.new(CombatFixtures.idle_input()), vesper)
	var indices := {}
	_client.session.snapshot_received.connect(func(s: SnapshotData) -> void:
		for e in s.entities:
			indices[e.net_id] = e.hero_index)
	await get_tree().physics_frame
	_tick(10)
	var db := ContentDB.shared()
	assert_int(indices.get(b_id, -1)).is_equal(db.index_of(ContentDB.HERO, &"hero_brannoc"))
	assert_int(indices.get(v_id, -1)).is_equal(db.index_of(ContentDB.HERO, &"hero_vesper_loom"))
	assert_int(indices.get(b_id, -1)).is_greater(ContentDB.NONE)
	var bv := _client.view(b_id)
	var vv := _client.view(v_id)
	assert_object(bv).is_not_null()
	assert_object(vv).is_not_null()
	if ModelCatalog.models_enabled():
		assert_str(String(bv.model_key)).is_equal("brannoc")
		assert_str(String(vv.model_key)).is_equal("vesper")
		assert_object(bv.model).is_not_null()
		assert_int(bv.model.team).is_equal(1)
