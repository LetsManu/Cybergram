extends GdUnitTestSuite
## P7 world props (WorldProps, docs/assets/props.md): the placement on the real
## Shardline Front map and its collision is deterministic, keeps out of the
## hardpoint zones, the Armory pad, spawns and the lane corridors, keeps every
## wall prop's floor footprint in the strip along a wall, puts roof props only
## off the walkable navmesh, and stays within its count budget.
##
## Budget stated here (docs/assets/props.md "Perf"): 150..400 props on the map.

const MAP_DEF := "res://assets/data/match/map_front.tres"
const MIN_PROPS := 150
const MAX_PROPS := 400
## Ray slack when re-measuring a footprint against its wall (m).
const EPS := 0.08

var _md: MapDef
var _def: WorldPropsDef
var _map: Node3D
var _list: Array = []


func before() -> void:
	_md = load(MAP_DEF) as MapDef
	_def = load(WorldProps.DEF_PATH) as WorldPropsDef
	_map = _md.scene.instantiate()
	add_child(_map)


func after() -> void:
	if is_instance_valid(_map):
		_map.queue_free()


func _space() -> PhysicsDirectSpaceState3D:
	return _map.get_world_3d().direct_space_state


## The placement, computed once per suite (after the map's bodies are in the broadphase).
func _placements() -> Array:
	if _list.is_empty():
		await get_tree().physics_frame
		await get_tree().physics_frame
		_list = WorldProps.place(_md, _def, _space(), WorldProps.bounds_of(WorldProps.piece_meshes(_def.model_key)))
	return _list


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_kit_and_rules_load_present() -> void:
	assert_bool(WorldModel.exists(_def.model_key)).is_true()
	assert_object(_def.navmesh).is_not_null()
	assert_int(WorldProps.piece_meshes(_def.model_key).size()).is_greater_equal(12)


func test_placement_same_seed_same_props() -> void:
	var a: Array = await _placements()
	var b := WorldProps.place(_md, _def, _space(), WorldProps.bounds_of(WorldProps.piece_meshes(_def.model_key)))
	assert_int(b.size()).is_equal(a.size())
	for i in a.size():
		assert_str(String(b[i].piece)).is_equal(String(a[i].piece))
		assert_bool(b[i].xform.is_equal_approx(a[i].xform)).is_true()


func test_count_within_budget() -> void:
	var list: Array = await _placements()
	assert_int(list.size()).is_between(MIN_PROPS, MAX_PROPS)
	assert_int(list.size()).is_less_equal(_def.max_props)


func test_no_footprint_in_hardpoint_zone_armory_or_spawn() -> void:
	var list: Array = await _placements()
	for pl in list:
		for c: Vector3 in pl.foot:
			for lane in _md.lanes:
				for h in lane.hardpoints:
					assert_float(_flat(c, h.position)).override_failure_message(
						"%s in hardpoint %s" % [pl.piece, h.id]).is_greater_equal(h.zone_radius + _def.hardpoint_margin_m)
			for hq in _md.hqs:
				assert_float(_flat(c, hq.armory)).override_failure_message(
					"%s on the Armory pad" % pl.piece).is_greater_equal(_def.armory_radius_m)
				assert_float(_flat(c, hq.sanctum)).override_failure_message(
					"%s in the Sanctum" % pl.piece).is_greater_equal(hq.sanctum_radius)
				for s in hq.spawn_points:
					assert_float(_flat(c, s)).override_failure_message(
						"%s on a spawn" % pl.piece).is_greater_equal(_def.spawn_radius_m)


## The corridor rule: no floor-footprint corner within corridor_half_width_m of
## a lane's polyline (HQ A gate -> its hardpoints -> HQ B gate).
func test_footprints_off_lane_corridors() -> void:
	var list: Array = await _placements()
	var lanes := WorldProps.lane_corridors(_md)
	assert_int(lanes.size()).is_equal(3)
	for pl in list:
		for c: Vector3 in pl.foot:
			for pts in lanes:
				assert_float(WorldProps.polyline_distance(pts, c)).override_failure_message(
					"%s at %s in a lane corridor" % [pl.piece, c]).is_greater_equal(_def.corridor_half_width_m)


## The walk rule, re-measured from the geometry: from every floor-footprint
## corner of a wall prop, a ray towards its wall hits a vertical face within
## max_wall_depth_m, and the floor under the corner is there.
func test_wall_props_stay_in_the_wall_strip() -> void:
	var list: Array = await _placements()
	var space := _space()
	var n := 0
	for pl in list:
		if pl.kind != &"wall":
			continue
		n += 1
		for c: Vector3 in pl.foot:
			var from: Vector3 = c + Vector3(0, 0.6, 0) - pl.wall_dir * 0.02
			var q := PhysicsRayQueryParameters3D.create(from, from + pl.wall_dir * (_def.max_wall_depth_m + EPS),
					HeroBody.LAYER_WORLD)
			var hit := space.intersect_ray(q)
			assert_bool(hit.is_empty()).override_failure_message(
				"%s at %s: no wall within %.2f m of its footprint" % [pl.piece, c, _def.max_wall_depth_m]).is_false()
			var g := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3(0, 0.5, 0), c - Vector3(0, 0.3, 0)))
			assert_bool(g.is_empty()).override_failure_message("%s floats at %s" % [pl.piece, c]).is_false()
	assert_int(n).is_greater(MIN_PROPS / 2)


func test_roof_props_off_walkable_navmesh() -> void:
	var list: Array = await _placements()
	var walk := WorldProps.NavIndex.new(_def.walk_navmeshes)
	for pl in list:
		if pl.kind != &"roof":
			continue
		assert_float(pl.xform.origin.y).is_greater_equal(_def.roof_min_y)
		assert_bool(walk.on_walkable(pl.xform.origin, 1.5)).is_false()


func test_team_pieces_only_in_own_hq() -> void:
	var list: Array = await _placements()
	for pl in list:
		if _def.team_pieces.has(pl.piece):
			assert_int(pl.team).override_failure_message("%s outside an HQ" % pl.piece).is_greater_equal(0)
			assert_int(pl.team).is_equal(WorldProps.hq_team_at(_md, _def, pl.xform.origin))
		else:
			assert_int(pl.team).is_equal(MapDef.TEAM_NEUTRAL)


func test_excluded_spots_return_rule_name() -> void:
	var a := _md.hq(MapDef.TEAM_CONCORD)
	assert_str(WorldProps.excluded(_md, _def, a.armory, 0.5)).is_equal("armory")
	assert_str(WorldProps.excluded(_md, _def, _md.lanes[0].hardpoints[0].position, 0.5)).is_equal("hardpoint")
	# every point on a lane line is kept out; between the objectives it is the corridor rule
	var corridor := 0
	for pts in WorldProps.lane_corridors(_md):
		for i in pts.size() - 1:
			for k in 10:
				var p: Vector3 = pts[i].lerp(pts[i + 1], k / 10.0)
				var why := WorldProps.excluded(_md, _def, p, 0.5)
				assert_str(why).override_failure_message("lane line point %s allowed" % p).is_not_empty()
				if why == "corridor":
					corridor += 1
	assert_int(corridor).is_greater(20)


func test_other_map_spawn_returns_null() -> void:
	var other := MapDef.new()
	other.id = &"not_front"
	var parent: Node = auto_free(Node.new())
	assert_object(WorldProps.spawn(parent, other)).is_null()
