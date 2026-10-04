extends GdUnitTestSuite
## Protocol v9: the Hello carries the player's hero pick so an online server
## spawns the hero chosen in the menu (not its own default).


func test_hello_round_trips_version_and_hero_index() -> void:
	var b := ControlCodec.encode_hello(MsgType.PROTOCOL_VERSION, 2)
	var h := ControlCodec.decode_hello(b)
	assert_int(h.protocol_version).is_equal(MsgType.PROTOCOL_VERSION)
	assert_int(h.hero_index).is_equal(2)


func test_pre_v9_hello_decodes_so_the_server_can_reject_it_cleanly() -> void:
	var old := PackedByteArray([MsgType.HELLO, 8, 0])
	var h := ControlCodec.decode_hello(old)
	assert_int(h.protocol_version).is_equal(8)
	assert_int(h.hero_index).is_equal(0)


func test_server_spawns_the_hero_the_client_picked() -> void:
	var net := NetFixtures.net_config()
	var link := LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	var server := ServerWorld.new()
	vp.add_child(server)
	var scene := CombatFixtures.range_scene(false)
	# Server default hero: Vesper. The client asks for Brannoc.
	server.setup(net, MovementDef.new(), scene, link.create_endpoint(1), CombatFixtures.vesper(),
		load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	var client := ClientWorld.new()
	add_child(auto_free(client))
	var brannoc := load("res://assets/data/heroes/hero_brannoc.tres") as HeroDef
	client.setup(net, MovementDef.new(), LookSettings.new(), scene, link.create_endpoint(2),
		ScriptedInputSource.new(CombatFixtures.idle_input()), brannoc)
	await get_tree().physics_frame
	for i in 10:
		link.advance(net.tick_dt())
		client.session.poll()
		client.tick()
		server.step()
	assert_bool(client.session.is_welcomed).is_true()
	var own := server.hero(client.session.own_net_id)
	assert_object(own).is_not_null()
	assert_str(own.combat.def.resource_path).ends_with("hero_brannoc.tres")
