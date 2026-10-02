extends GdUnitTestSuite
## MapDef for the Slice Map "Shardline Causeway" (match-flow-and-map.md §3.2, §3.7)
## is consistent with the GDD and with the anchors in the map scene.

const DEF_PATH := "res://assets/data/match/map_slice_lane.tres"
const ORDER: Array[StringName] = [&"s_ai", &"s_ao", &"s_mid", &"s_bo", &"s_bi"]
const TOL_M := 0.5

var _def: MapDef
var _lane: LaneDef


func before() -> void:
	_def = load(DEF_PATH) as MapDef
	_lane = _def.lanes[0]


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func test_one_lane_five_hardpoints_in_task_order() -> void:
	assert_int(_def.lanes.size()).is_equal(1)
	assert_int(_lane.hardpoints.size()).is_equal(5)
	var K := HardpointDef.TaskKind
	var tasks := [K.BREACH, K.PLANT, K.HOLD, K.PLANT, K.BREACH]
	var tiers := [HardpointDef.Tier.INNER, HardpointDef.Tier.OUTER, HardpointDef.Tier.MID, HardpointDef.Tier.OUTER, HardpointDef.Tier.INNER]
	var owners := [MapDef.TEAM_CONCORD, MapDef.TEAM_CONCORD, MapDef.TEAM_NEUTRAL, MapDef.TEAM_SYNDICATE, MapDef.TEAM_SYNDICATE]
	for i in 5:
		var h := _lane.hardpoints[i]
		assert_str(String(h.id)).is_equal(String(ORDER[i]))
		assert_int(h.lane_index).is_equal(i)
		assert_int(h.task).is_equal(tasks[i])
		assert_int(h.tier).is_equal(tiers[i])
		assert_int(h.initial_owner).is_equal(owners[i])
		# §3.2 zone sizes: Hold/Breach r 12, Plant r 10, 6 m tall.
		assert_float(h.zone_radius).is_equal(10.0 if h.task == K.PLANT else 12.0)
		assert_float(h.zone_height).is_equal(6.0)
	# §3.7 durations: Breach Generator 6,000 + 20 s, Plant 75 s, Hold 60 s.
	assert_float(_lane.hardpoint(&"s_ai").generator_hp).is_equal(6000.0)
	assert_float(_lane.hardpoint(&"s_bi").base_duration_s).is_equal(20.0)
	assert_float(_lane.hardpoint(&"s_ao").base_duration_s).is_equal(75.0)
	assert_float(_lane.hardpoint(&"s_mid").base_duration_s).is_equal(60.0)


func test_lane_distances_match_gdd_and_are_symmetric() -> void:
	var a := _def.hq(MapDef.TEAM_CONCORD)
	var b := _def.hq(MapDef.TEAM_SYNDICATE)
	var hp := _lane.hardpoints
	# §3.7: 410 m Sanctum to Sanctum; §3.2: Sanctum -> Uplink 25 m.
	assert_float(_flat(a.sanctum, b.sanctum)).is_equal_approx(410.0, TOL_M)
	assert_float(_flat(a.sanctum, a.uplink)).is_equal_approx(25.0, TOL_M)
	# Inner -> Outer 60 m, Outer -> Mid 65 m (main path, straight on this lane).
	assert_float(_flat(hp[0].position, hp[1].position)).is_equal_approx(60.0, TOL_M)
	assert_float(_flat(hp[1].position, hp[2].position)).is_equal_approx(65.0, TOL_M)
	# Sanctum -> own Inner: GDD path 85 m (it bends round the Uplink); straight line 80 m.
	assert_float(_flat(a.sanctum, hp[0].position)).is_between(80.0 - TOL_M, 85.0 + TOL_M)
	# Mirror symmetry: each team sees the same distances to its i-th hardpoint.
	for i in 5:
		var da := _flat(a.sanctum, hp[i].position)
		var db := _flat(b.sanctum, hp[4 - i].position)
		assert_float(da).is_equal_approx(db, TOL_M)
	assert_float(_flat(hp[2].position, _def.mid_plaza_center)).is_equal_approx(0.0, TOL_M)
	assert_float(_def.mid_plaza_radius).is_equal(25.0)


func test_barricade_sockets_are_15_m_outside_each_zone() -> void:
	for h in _lane.hardpoints:
		assert_int(h.barricade_sockets.size()).is_equal(2)
		for s in h.barricade_sockets:
			assert_float(_flat(s, h.position)).is_equal_approx(h.zone_radius + 15.0, 0.01)
		# [0] faces the Concord HQ (smaller lane distance = larger z).
		assert_bool(h.barricade_sockets[0].z > h.barricade_sockets[1].z).is_true()


func test_hq_spawns_are_inside_their_sanctum() -> void:
	assert_int(_def.hqs.size()).is_equal(2)
	for q in _def.hqs:
		assert_int(q.spawn_points.size()).is_equal(5)
		for p in q.spawn_points:
			assert_float(_flat(p, q.sanctum)).is_less(q.sanctum_radius)
		# Foundry and Armory sit beside the Sanctum, the Uplink between it and the gate.
		assert_float(_flat(q.foundry, q.sanctum)).is_less(25.0)
		assert_float(_flat(q.armory, q.sanctum)).is_less(25.0)
		assert_float(_flat(q.lane_gate, q.sanctum)).is_equal_approx(35.0, TOL_M)
	assert_float(_def.hq(MapDef.TEAM_CONCORD).spawn_yaw_deg).is_equal(0.0)
	assert_float(_def.hq(MapDef.TEAM_SYNDICATE).spawn_yaw_deg).is_equal(180.0)
	assert_int(_def.sudden_death_spawns.size()).is_equal(2)


func test_one_flank_loop_per_half_about_90_m() -> void:
	assert_int(_lane.flank_loops.size()).is_equal(2)
	var lengths: Array[float] = []
	for f in _lane.flank_loops:
		var outer := _lane.hardpoint(f.from_hardpoint)
		var mid := _lane.hardpoint(f.to_hardpoint)
		assert_object(outer).is_not_null()
		assert_int(mid.tier).is_equal(HardpointDef.Tier.MID)
		assert_vector(f.waypoints[0]).is_equal(f.outer_door)
		assert_vector(f.waypoints[f.waypoints.size() - 1]).is_equal(f.mid_door)
		# Hardpoint centre -> loop -> hardpoint centre vs GDD 90 m (main path 65 m).
		var length := _flat(outer.position, f.outer_door) + _flat(f.mid_door, mid.position)
		for i in f.waypoints.size() - 1:
			length += _flat(f.waypoints[i], f.waypoints[i + 1])
		assert_float(length).is_between(81.0, 99.0)
		assert_float(length).is_greater(_flat(outer.position, mid.position))
		lengths.append(length)
	assert_float(lengths[0]).is_equal_approx(lengths[1], TOL_M)


func test_scene_anchors_match_map_def() -> void:
	var scene: Node3D = auto_free(_def.scene.instantiate())
	var anchors := scene.get_node("Anchors")
	var seen := 0
	var sockets := 0
	for n in anchors.get_children():
		if n is HardpointAnchor:
			var h := _lane.hardpoint(n.hardpoint_id)
			assert_object(h).is_not_null()
			assert_int(n.task).is_equal(h.task)
			assert_float(n.zone_radius).is_equal(h.zone_radius)
			assert_vector(n.position).is_equal_approx(h.position, Vector3.ONE * 0.01)
			seen += 1
		elif n is BarricadeSocketAnchor:
			var h := _lane.hardpoint(n.hardpoint_id)
			assert_vector(n.position).is_equal_approx(h.barricade_sockets[n.side], Vector3.ONE * 0.01)
			sockets += 1
	assert_int(seen).is_equal(5)
	assert_int(sockets).is_equal(10)
	for q in _def.hqs:
		var team := scene.get_node("Spawns/" + ("Concord" if q.team == MapDef.TEAM_CONCORD else "Syndicate"))
		for i in q.spawn_points.size():
			var m := team.get_node("Spawn%d" % (i + 1)) as Marker3D
			assert_vector(m.position).is_equal_approx(q.spawn_points[i], Vector3.ONE * 0.01)
	# Session hooks (same marker names as the test course).
	for n in ["PlayerSpawn", "DummySpawn1", "DummySpawn2"]:
		assert_object(scene.get_node_or_null(n)).is_not_null()
	assert_object(scene.get_node_or_null("NavRegion")).is_not_null()


func test_launch_arg_selects_the_slice_map() -> void:
	var c := LaunchConfig.parse(PackedStringArray(["--map", "slice"]), false)
	assert_str(c.map_name).is_equal("slice")
	assert_bool(ResourceLoader.exists(GameSession.MAP_DEF_PATH % c.map_name)).is_true()
