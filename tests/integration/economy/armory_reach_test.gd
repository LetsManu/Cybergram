extends GdUnitTestSuite
## W21-G2: the Armory is reachable and openable on the real Shardline Front map.
## A hero spawned at the Sanctum walks (navmesh path, real physics) to the HQ
## Armory pad: the server's `at_armory` flag arrives on the client over the
## loopback and a buy is accepted there. Both team halves are not needed: the
## player is always the Concord half. Owner decision 2026-10-06: the Sanctum
## counts as the Armory (LoL shop at the spawn), so a fresh spawn can buy at once.

const MAP_PATH := "res://assets/data/match/map_front.tres"
const C := MapDef.TEAM_CONCORD


class Walker extends WardlingFixtures.Owner:
	var queued: Array = []

	func sample(seq: int, out: InputCommand) -> void:
		super.sample(seq, out)
		if not queued.is_empty():
			var a: Array = queued.pop_front()
			out.action = a[0]
			out.action_arg = a[1]
		out.quantize()

	func go(to: Vector3) -> void:
		goal = to
		stop_m = 1.0
		arrived = false
		_path = PackedVector3Array()
		_i = 1


var _server: ServerWorld
var _client: ClientWorld
var _link: LoopbackLink
var _net: NetConfig
var _input: Walker


func _tick(n: int = 1) -> void:
	for i in n:
		_link.advance(_net.tick_dt())
		_client.session.poll()
		_client.tick()
		_server.step()


func _build(shop_in_sanctum := true) -> MapDef:
	var def := load(MAP_PATH) as MapDef
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	var movement := load("res://assets/data/movement/movement_default.tres") as MovementDef
	_server.setup(_net, movement, def.scene, _link.create_endpoint(1), CombatFixtures.vesper(), def.match_rules)
	_server.setup_objectives(def)
	_server.setup_match(def, 1.0)
	_server.enable_wardlings(def, WardlingFixtures.rules(), load(WardlingFixtures.PICKET) as WardlingDef)
	_server.wardlings.vanguard_enabled = false
	var econ := (load("res://assets/data/economy/economy_rules_slice.tres") as EconomyRulesDef).duplicate() as EconomyRulesDef
	econ.shop_in_sanctum = shop_in_sanctum
	_server.enable_progression(econ,
		load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef, def)
	_input = Walker.new()
	_input.server = _server
	_client = auto_free(ClientWorld.new())
	add_child(_client)
	_client.setup(_net, movement, LookSettings.new(), def.scene, _link.create_endpoint(2), _input, CombatFixtures.vesper())
	_client.setup_objectives(def)
	return def


func test_a_fresh_spawn_can_shop_in_the_sanctum() -> void:
	var def := _build()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), _server, def)).is_true()
	_tick(10)
	var h := _server.hero(_client.session.own_net_id)
	assert_object(h).is_not_null()
	_input.hero_id = h.net_id
	assert_int(_client.progress.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY).is_not_equal(0)
	_input.queued.append([InputCommand.ACTION_BUY, _server.progression.catalog.index_of(&"ember_part")])
	_tick(4)
	assert_bool(_client.progress.inv_items.has(_server.progression.catalog.index_of(&"ember_part"))).is_true()


func test_walking_from_spawn_reaches_the_pad_and_the_flag_replicates() -> void:
	var def := _build(false)
	assert_bool(await WardlingFixtures.await_nav(get_tree(), _server, def)).is_true()
	_tick(10)
	var h := _server.hero(_client.session.own_net_id)
	assert_object(h).is_not_null()
	_input.hero_id = h.net_id
	assert_int(_client.progress.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY).is_equal(0)
	var pad := def.hq(C).armory
	_input.go(pad)
	var ticks := 0
	for i in 900:
		_tick()
		ticks = i
		if (_client.progress.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY) != 0:
			break
	var d := Vector2(h.state.position.x - pad.x, h.state.position.z - pad.z).length()
	print("armory reach: %d ticks, %.2f m from the pad centre at %s" % [ticks, d, h.state.position])
	assert_int(_client.progress.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY).is_not_equal(0)
	_input.queued.append([InputCommand.ACTION_BUY, _server.progression.catalog.index_of(&"ember_part")])
	_tick(4)
	assert_bool(_client.progress.inv_items.has(_server.progression.catalog.index_of(&"ember_part"))).is_true()
