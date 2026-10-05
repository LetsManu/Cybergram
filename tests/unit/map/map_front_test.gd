extends GdUnitTestSuite
## W14-M2 Shardline Front MapDef (match-flow-and-map.md §3.2-§3.3, Canon C1/C2/C4/C5):
## 3 lanes x 5 hardpoints, the §3.3 task per hardpoint (each type 5 times), 3 lane
## gates per HQ, 8 Undercroft flanks between Outer and adjacent Mid, C5 placements,
## the 5v5 rules, and the scene's anchors in sync with the data.

const DEF_PATH := "res://assets/data/match/map_front.tres"
const H := HardpointDef.TaskKind.HOLD
const P := HardpointDef.TaskKind.PLANT
const B := HardpointDef.TaskKind.BREACH

## §3.3 per lane, in lane order (A-Inner, A-Outer, Mid, B-Outer, B-Inner).
const TASKS := {
	&"north": [B, H, P, H, B],
	&"center": [H, P, H, P, H],
	&"south": [P, B, B, B, P],
}

var _def: MapDef


func before() -> void:
	_def = load(DEF_PATH) as MapDef


func test_three_lanes_of_five_with_spec_tasks() -> void:
	assert_int(_def.lanes.size()).is_equal(3)
	var counts := {H: 0, P: 0, B: 0}
	for li in _def.lanes.size():
		var lane := _def.lanes[li]
		assert_array(TASKS.keys()).contains([lane.id])
		assert_int(lane.hardpoints.size()).is_equal(5)
		var tiers := [HardpointDef.Tier.INNER, HardpointDef.Tier.OUTER, HardpointDef.Tier.MID, HardpointDef.Tier.OUTER, HardpointDef.Tier.INNER]
		var owners := [0, 0, -1, 1, 1]
		for i in 5:
			var h := lane.hardpoints[i]
			assert_int(h.task).is_equal(TASKS[lane.id][i])
			assert_int(h.tier).is_equal(tiers[i])
			assert_int(h.initial_owner).is_equal(owners[i])
			assert_int(h.lane_index).is_equal(i)
			counts[h.task] += 1
			assert_int(h.barricade_sockets.size()).is_equal(2)
			assert_int(h.garrison_points.size()).is_equal(3)
			assert_bool(h.supply_cache.is_finite()).is_true()
			if h.task == P:
				assert_int(h.cell_cradles.size()).is_equal(2)
			if h.task == B:
				assert_float(h.generator_hp).is_greater(0.0)
	assert_dict(counts).is_equal({H: 5, P: 5, B: 5})


func test_layout_distances_follow_the_gdd() -> void:
	# Lanes at lateral x -80 / 0 / +80 (north = -X); Inner 85, Outer 145, Mid 210 m.
	var xs := [-80.0, 0.0, 80.0]
	var ls := [85.0, 145.0, 210.0, 275.0, 335.0]
	for li in 3:
		for i in 5:
			var p := _def.lanes[li].hardpoints[i].position
			assert_float(p.x).is_equal_approx(xs[li], 0.01)
			assert_float(-p.z).is_equal_approx(ls[i], 0.01)
	assert_float(_def.mid_plaza_radius).is_equal(30.0)
	assert_float(-_def.mid_plaza_center.z).is_equal(210.0)
	assert_int(_def.sudden_death_spawns.size()).is_equal(2)


func test_each_hq_has_three_lane_gates() -> void:
	for team in 2:
		var hq := _def.hq(team)
		assert_int(hq.lane_gates.size()).is_equal(3)
		assert_float(hq.gate_for_lane(0).x).is_less(0.0)
		assert_float(hq.gate_for_lane(1).x).is_equal(0.0)
		assert_float(hq.gate_for_lane(2).x).is_greater(0.0)
		assert_int(hq.spawn_points.size()).is_greater_equal(5)


func test_flanks_link_outer_to_adjacent_mid() -> void:
	var n := 0
	for lane in _def.lanes:
		for f in lane.flank_loops:
			n += 1
			var from := _def.lanes[_def.lane_of(f.from_hardpoint)].hardpoint(f.from_hardpoint)
			var to := _def.lanes[_def.lane_of(f.to_hardpoint)].hardpoint(f.to_hardpoint)
			assert_int(from.tier).is_equal(HardpointDef.Tier.OUTER)
			assert_int(to.tier).is_equal(HardpointDef.Tier.MID)
			# C2: adjacent lanes only (Center <-> North / South).
			assert_int(absi(_def.lane_of(f.from_hardpoint) - _def.lane_of(f.to_hardpoint))).is_equal(1)
			assert_int(f.waypoints.size()).is_greater_equal(3)
			assert_bool(from.side_doors.has(f.outer_door)).is_true()
			assert_bool(to.side_doors.has(f.mid_door)).is_true()
	assert_int(n).is_equal(8)


func test_full_map_rules_are_5v5_with_sudden_death() -> void:
	assert_object(_def.match_rules).is_not_null()
	assert_int(_def.match_rules.team_size).is_equal(5)
	assert_bool(_def.match_rules.sudden_death_enabled).is_true()
	assert_float(_def.match_rules.uplink_integrity).is_equal(33000.0)
	var slice := load("res://assets/data/match/map_slice_lane.tres") as MapDef
	assert_int(slice.match_rules.team_size).is_equal(3)


func test_global_index_round_trip() -> void:
	var k := 0
	for li in 3:
		for i in 5:
			assert_object(_def.hardpoint_global(k)).is_same(_def.lanes[li].hardpoints[i])
			assert_that(_def.lane_slot(k)).is_equal(Vector2i(li, i))
			k += 1
	assert_object(_def.hardpoint_global(15)).is_null()
	assert_that(_def.lane_slot(-1)).is_equal(Vector2i(-1, -1))


func test_scene_anchors_match_the_data() -> void:
	var scene: Node3D = auto_free(_def.scene.instantiate())
	var anchors := {}
	for a in scene.get_node("Anchors").get_children():
		if a is HardpointAnchor:
			anchors[(a as HardpointAnchor).hardpoint_id] = a
	assert_int(anchors.size()).is_equal(15)
	for lane in _def.lanes:
		for h in lane.hardpoints:
			var a: HardpointAnchor = anchors.get(h.id)
			assert_object(a).is_not_null()
			if a != null:
				assert_float(a.position.distance_to(h.position)).is_less(0.01)
				assert_int(a.task).is_equal(h.task)
