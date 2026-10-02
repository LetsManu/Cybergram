extends GdUnitTestSuite
## Vanguard (Canon C15): on the (debug-scaled) wave clock each team's Foundry
## lane gate sends 4 Wardlings that march to the lane front (the neutral Mid for
## both teams at match start, LaneFrontResolver) along one shared path, stand in
## the zone and count as presence (E7 seam, 0.5 each). A lane never holds more
## than 4 Vanguard per team.

const HZ: int = 30


func test_vanguard_wave_spawns_and_reaches_the_front_hardpoint() -> void:
	var rules := WardlingFixtures.rules()
	var built := WardlingFixtures.slice_server(self, rules, true)
	var server: ServerWorld = built[0]
	auto_free(built[3])
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server)).is_true()
	var ww := server.wardlings
	ww.clock_scale = 60.0  # first wave at 1 s, then every 1 s (gated)
	var spawned := []
	ww.vanguard_wave_spawned.connect(func(team: int, lane: int, n: int) -> void: spawned.append([team, lane, n]))
	var front := ww.front_index(MapDef.TEAM_CONCORD, 0)
	var hp: HardpointDef = WardlingFixtures.map_def().lanes[0].hardpoints[front]
	assert_str(String(hp.id)).is_equal("s_mid")
	var reached := -1
	var presence := 0.0
	while server.tick < 50 * HZ and reached < 0:
		server.step()
		assert_int(ww.vanguard_count(MapDef.TEAM_CONCORD)).is_less_equal(4)
		assert_int(ww.vanguard_count(MapDef.TEAM_SYNDICATE)).is_less_equal(4)
		for w in ww.waves:
			if w.team != MapDef.TEAM_CONCORD:
				continue
			for m in w.members:
				if Vector2(m.global_position.x - hp.position.x, m.global_position.z - hp.position.z).length() <= hp.zone_radius:
					reached = server.tick
	for i in 2 * HZ:
		server.step()
	presence = server.objectives.find(&"s_mid").presence[MapDef.TEAM_CONCORD]
	print("vanguard: waves %s, reached the Mid zone after %.1f s, presence %.1f" % [spawned, float(reached) / HZ, presence])
	assert_int(spawned.size()).is_greater_equal(2)
	assert_array(spawned[0]).is_equal([MapDef.TEAM_CONCORD, 0, 4])
	assert_array(spawned[1]).is_equal([MapDef.TEAM_SYNDICATE, 0, 4])
	assert_int(reached).is_greater(0)
	# 170 m from the lane gate at 5.5 m/s is ~31 s.
	assert_float(float(reached) / HZ).is_less(45.0)
	assert_float(presence).is_greater_equal(0.5)
	# One shared path query per wave plan, not one per member.
	var plans := 0
	for w in ww.waves:
		plans += w.plans
	assert_int(plans).is_less_equal(ww.waves.size() * 3)
