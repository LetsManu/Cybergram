extends GdUnitTestSuite
## Attack Target through the real input path (InputCommand -> ServerWorld
## validation -> Squad -> brains -> bolts). A base squad of 3 Tier I Pickets
## (7 dmg x 3 bolts/s each = 63 raw DPS) kills an idle 250 HP, 0-armor dummy in
## 250 / 63 = 4.0 s of fire; the GDD floor (49 DPS, §25 criterion 4) plus
## reaction and bolt travel gives the upper bound. Before the order the squad
## does not start the hero fight on its own (§9.4 hero gate).

const HZ: int = 30
const ORDER_TICK: int = 5 * HZ


func test_attack_target_kills_a_dummy_in_the_expected_time() -> void:
	var rules := WardlingFixtures.rules()
	var built := WardlingFixtures.slice_server(self, rules, false)
	var server: ServerWorld = built[0]
	auto_free(built[3])
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server)).is_true()
	var def := WardlingFixtures.map_def()
	var target_def := HeroDef.new()  # 250 HP, 0 armor, no weapon
	var dummy_id := server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		Vector3(0.0, 0.05, -18.0), target_def, ServerWorld.TEAM_DUMMIES)
	var cmdr := WardlingFixtures.Owner.new()
	cmdr.server = server
	cmdr.order_tick = ORDER_TICK
	cmdr.order_cmd = InputCommand.SQUAD_ATTACK
	cmdr.order_target = dummy_id
	var id := server.add_scripted_hero(cmdr, def.hq(MapDef.TEAM_CONCORD).spawn_points[2], CombatFixtures.vesper(),
		ServerWorld.TEAM_PLAYERS)
	cmdr.hero_id = id
	var dummy := server.hero(dummy_id)
	var died := [-1]
	server.hero_died.connect(func(v: int, _k: int) -> void:
		if v == dummy_id and died[0] < 0:
			died[0] = server.tick)
	var ordered := [false]
	server.wardlings.squad_command_issued.connect(func(o: int, c: int) -> void:
		ordered[0] = o == id and c == Squad.CMD_ATTACK)
	while server.tick < ORDER_TICK:
		server.step()
	var sq := server.wardlings.squad_of(id)
	assert_int(sq.members.size()).is_equal(3)
	assert_float(dummy.combat.health.hp).is_equal(250.0)  # no hero initiation
	while died[0] < 0 and server.tick < ORDER_TICK + 12 * HZ:
		server.step()
	assert_bool(ordered[0]).is_true()
	var seconds := float(died[0] - ORDER_TICK) / HZ
	print("attack target: dummy dead %.2f s after the order" % seconds)
	assert_int(died[0]).is_greater(0)
	var raw_dps := 3.0 * 7.0 / 0.333
	assert_float(seconds).is_between(250.0 / raw_dps - 0.1, 250.0 / 49.0 + 1.0)
	# Target gone -> the order ends and the squad reverts to Follow.
	server.step()
	server.step()
	assert_int(sq.command).is_equal(Squad.CMD_FOLLOW)
	assert_int(sq.last_end_reason).is_equal(Squad.END_TARGET_GONE)


func test_owner_death_holds_the_squad_10_s_then_dissolves_it() -> void:
	var rules := WardlingFixtures.rules()
	var built := WardlingFixtures.slice_server(self, rules, false)
	var server: ServerWorld = built[0]
	auto_free(built[3])
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server)).is_true()
	var def := WardlingFixtures.map_def()
	var cmdr := WardlingFixtures.Owner.new()
	cmdr.server = server
	var id := server.add_scripted_hero(cmdr, def.hq(MapDef.TEAM_CONCORD).spawn_points[2], CombatFixtures.vesper(),
		ServerWorld.TEAM_PLAYERS)
	cmdr.hero_id = id
	for i in 3 * HZ:
		server.step()
	var sq := server.wardlings.squad_of(id)
	assert_int(sq.members.size()).is_equal(3)
	var dissolved := [-1]
	server.wardlings.squad_dissolved.connect(func(o: int) -> void:
		if o == id:
			dissolved[0] = server.tick)
	var killed_tick := server.tick
	server.damage_hero(server.hero(id), DamageInfo.make(10000.0, 0, ServerWorld.TEAM_DUMMIES, 0, DamageInfo.Type.TRUE))
	assert_bool(sq.is_dissolving()).is_true()
	assert_object(server.wardlings.squad_of(id)).is_null()
	while dissolved[0] < 0 and server.tick < killed_tick + 15 * HZ:
		server.step()
		if server.tick < killed_tick + roundi(rules.death_hold_s * HZ) - 1:
			assert_int(sq.members.size()).is_equal(3)
	var held := float(dissolved[0] - killed_tick) / HZ
	assert_float(held).is_equal_approx(rules.death_hold_s, 0.1)
	assert_int(server.wardlings.wardlings.size()).is_equal(0)
