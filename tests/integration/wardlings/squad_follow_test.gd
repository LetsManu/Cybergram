extends GdUnitTestSuite
## A hero spawning at the Concord Sanctum gets a free squad of 3 Pickets from
## the Foundry, which follows it across the slice map (Concord Sanctum -> the
## Signal Market Outer, ~140 m) in formation, never past the 30 m leash.

const HZ: int = 30


func test_squad_follows_owner_across_the_slice_map() -> void:
	var rules := WardlingFixtures.rules()
	var built := WardlingFixtures.slice_server(self, rules, false)
	var server: ServerWorld = built[0]
	auto_free(built[3])
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server)).is_true()
	var def := WardlingFixtures.map_def()
	var walker := WardlingFixtures.Owner.new()
	walker.server = server
	walker.goal = def.lanes[0].hardpoints[1].position
	walker.wait_ticks = 3 * HZ
	var id := server.add_scripted_hero(walker, def.hq(MapDef.TEAM_CONCORD).spawn_points[2], CombatFixtures.vesper(),
		ServerWorld.TEAM_PLAYERS)
	walker.hero_id = id
	var hero := server.hero(id)
	var max_d := 0.0
	var ticks := 0
	while not walker.arrived and ticks < 60 * HZ:
		server.step()
		ticks += 1
		var live := server.wardlings.squad_of(id)
		if ticks > walker.wait_ticks and live != null:
			for m in live.members:
				max_d = maxf(max_d, _flat(m.global_position, hero.state.position))
	for i in 4 * HZ:  # settle into formation
		server.step()
	var sq := server.wardlings.squad_of(id)
	print("squad follow: %.1f s walk, max member distance %.1f m" % [float(ticks) / HZ, max_d])
	assert_bool(walker.arrived).is_true()
	assert_object(sq).is_not_null()
	assert_int(sq.members.size()).is_equal(3)
	assert_int(sq.command).is_equal(Squad.CMD_FOLLOW)
	assert_float(max_d).is_less(rules.follow_leash_m)
	for m in sq.members:
		var d := _flat(m.global_position, hero.state.position)
		assert_float(d).is_less_equal(rules.follow_back_max_m + 3.0)
		assert_float(m.global_position.y).is_between(-0.5, 2.0)
	# Nothing replaced away from the Foundry; the minting stayed at 3.
	assert_int(server.wardlings.wardlings.size()).is_equal(3)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
