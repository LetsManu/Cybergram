extends GdUnitTestSuite
## W14-M2 Shardline Front in a live ServerWorld:
##  * the baked navmesh reaches all 15 hardpoints, both HQs (Sanctum, Uplink,
##    Foundry, Armory, 3 lane gates) and every Undercroft junction from each Sanctum;
##  * Vanguard (C15): one wave of 4 per lane per team from that lane's gate, and
##    never more than 4 wave members per lane per team (max 1 live wave);
##  * a full 5v5 bots match on the map's own rules reaches End.

const DEF_PATH := "res://assets/data/match/map_front.tres"
const HZ: int = 30
const ROSTER := "res://assets/data/ai/bot_roster_slice.tres"


func _def() -> MapDef:
	return load(DEF_PATH) as MapDef


func _server(vanguard: bool) -> ServerWorld:
	var def := _def()
	var built := WardlingFixtures.slice_server(self, WardlingFixtures.rules(), vanguard, def.match_rules, def)
	auto_free(built[3])
	return built[0]


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func test_navmesh_reaches_every_hardpoint_hq_and_flank() -> void:
	var server := _server(false)
	var def := _def()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	var nav := server.get_world_3d().navigation_map
	var targets: Array = []
	for lane in def.lanes:
		for h in lane.hardpoints:
			targets.append([String(h.id), h.position, h.zone_radius * 0.5])
		for f in lane.flank_loops:
			targets.append([String(f.id) + "_junction", f.waypoints[2], 2.0])
			targets.append([String(f.id) + "_door", f.mid_door, 2.5])
	for hq in def.hqs:
		var t := "hq%d_" % hq.team
		targets.append([t + "sanctum", hq.spawn_points[0], 1.5])
		targets.append([t + "uplink", hq.uplink + Vector3(0, 0, 6.0 if hq.team == 0 else -6.0), 2.0])
		targets.append([t + "foundry", hq.foundry, 2.0])
		targets.append([t + "armory", hq.armory, 2.0])
		for g in hq.lane_gates:
			targets.append([t + "gate", g, 1.5])
	var bad: Array = []
	for hq in def.hqs:
		var start := hq.spawn_points[2]
		for t in targets:
			var p := NavigationServer3D.map_get_path(nav, start, t[1], true)
			if p.size() < 2 or _flat(p[p.size() - 1], t[1]) > t[2] or absf(p[p.size() - 1].y - t[1].y) > 1.5:
				bad.append("%d->%s" % [hq.team, t[0]])
	assert_array(bad).is_empty()
	assert_int(targets.size()).is_equal(15 + 16 + 2 * 7)


func test_lanes_are_mirror_symmetric_and_short() -> void:
	var server := _server(false)
	var def := _def()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	var nav := server.get_world_3d().navigation_map
	for li in 3:
		var hps := def.lanes[li].hardpoints
		var a := NavigationServer3D.map_get_path(nav, def.hq(0).spawn_points[2], hps[2].position, true)
		var b := NavigationServer3D.map_get_path(nav, def.hq(1).spawn_points[2], hps[2].position, true)
		var la := _len(a)
		var lb := _len(b)
		print("front lane %d: Sanctum -> Mid %.0f m / %.0f m" % [li, la, lb])
		assert_float(la).is_equal_approx(lb, 10.0)  # navmesh tessellation differs per half
		# GDD §3.2: Sanctum -> own C-Mid 210 m, N/S-Mid 255 m (first-person run 35-43 s).
		assert_float(la).is_between(195.0, 290.0)


static func _len(p: PackedVector3Array) -> float:
	var l := 0.0
	for i in p.size() - 1:
		l += p[i].distance_to(p[i + 1])
	return l


func test_a_vanguard_wave_per_lane_per_team() -> void:
	var server := _server(true)
	var def := _def()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	var ww := server.wardlings
	ww.clock_scale = 60.0
	var spawned := []
	ww.vanguard_wave_spawned.connect(func(team: int, lane: int, n: int) -> void: spawned.append([team, lane, n]))
	while server.tick < 3 * HZ and spawned.size() < 6:
		server.step()
	assert_int(spawned.size()).is_equal(6)
	var seen := {}
	for s in spawned:
		seen["%d:%d" % [s[0], s[1]]] = s[2]
	for team in 2:
		for lane in 3:
			assert_int(seen.get("%d:%d" % [team, lane], 0)).is_equal(4)
	# Each wave starts at its own lane gate.
	for w in ww.waves:
		var gate := def.hq(w.team).gate_for_lane(w.lane)
		for m in w.members:
			assert_float(_flat(m.global_position, gate)).is_less(20.0)
	# Max 1 live wave: per lane per team never more than 4 members.
	for i in 20 * HZ:
		server.step()
		if i % 15 == 0:
			for team in 2:
				var per := [0, 0, 0]
				for w in ww.waves:
					if w.team == team:
						per[w.lane] += w.alive_count()
				for lane in 3:
					assert_int(per[lane]).is_less_equal(4)
	assert_int(ww.vanguard_count(0)).is_less_equal(12)


func test_full_five_v_five_bots_match_reaches_end() -> void:
	var def := _def()
	var server := _server(true)
	server.setup_match(def, 120.0)  # 60:00 in 30 s of sim time
	server.wardlings.clock_scale = 120.0
	server.enable_progression(load("res://assets/data/economy/economy_rules_slice.tres") as EconomyRulesDef,
		load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef, def)
	var roster := load(ROSTER) as BotRosterDef
	var director := BotDirector.new()
	director.setup(server, roster, roster.profile("normal"), 7)
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	assert_int(director.fill(false)).is_equal(10)
	var lanes_seen := {}
	var peak_ai := 0
	while server.tick < 45 * HZ and not server.match_flow.is_over():
		server.step()
		if server.tick % HZ == 0:
			for b in director.brains:
				lanes_seen[b.lane] = true
			peak_ai = maxi(peak_ai, server.wardlings.wardlings.size())
	print("front 5v5: end %s winner %d at %s, lanes used %s, peak AI %d" % [MatchRules.EndReason.keys()[server.match_flow.end_reason],
		server.match_flow.winner, MatchRules.format_clock(server.match_flow.time_s), lanes_seen.keys(), peak_ai])
	assert_bool(server.match_flow.is_over()).is_true()
	assert_int(lanes_seen.size()).is_equal(3)
	assert_int(peak_ai).is_less_equal(110)
