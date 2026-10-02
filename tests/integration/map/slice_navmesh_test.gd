extends GdUnitTestSuite
## The baked ground navmesh of Shardline Causeway (E8 Wardlings) connects each
## Sanctum to every hardpoint and runs through both flank loops. Queries go
## through NavigationServer3D on the map's own navigation map.

const DEF_PATH := "res://assets/data/match/map_slice_lane.tres"

var _def: MapDef
var _lane: LaneDef
var _nav_map: RID


func before() -> void:
	_def = load(DEF_PATH) as MapDef
	_lane = _def.lanes[0]
	var scene: Node3D = auto_free(_def.scene.instantiate())
	add_child(scene)
	var region := scene.get_node("NavRegion") as NavigationRegion3D
	_nav_map = region.get_navigation_map()
	# Wait until this region is synced into the map (the map may already be live from other suites).
	var probe_a := _def_probe_a()
	for i in 120:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_path(_nav_map, probe_a[0], probe_a[1], true).size() > 1:
			break


func _path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(_nav_map, from, to, true)


static func _length(p: PackedVector3Array) -> float:
	var l := 0.0
	for i in p.size() - 1:
		l += p[i].distance_to(p[i + 1])
	return l


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func test_navmesh_is_baked() -> void:
	assert_bool(NavigationServer3D.map_get_iteration_id(_nav_map) > 0).is_true()
	var nm := (_def.scene.instantiate() as Node3D)
	var region := nm.get_node("NavRegion") as NavigationRegion3D
	assert_int(region.navigation_mesh.get_polygon_count()).is_greater(100)
	nm.free()


func test_each_sanctum_reaches_every_hardpoint() -> void:
	var lengths := {}
	for q in _def.hqs:
		var start := q.spawn_points[2]
		for h in _lane.hardpoints:
			var p := _path(start, h.position)
			assert_int(p.size()).is_greater(1)
			if p.size() < 2:
				return
			# The zone centre holds a solid core (Generator / pylon / plinth): the
			# path must end inside the zone, close to the centre.
			assert_float(_flat(p[p.size() - 1], h.position)).is_less(h.zone_radius * 0.5)
			var straight := _flat(start, h.position)
			var length := _length(p)
			assert_float(length).is_less(straight * 1.25 + 10.0)
			lengths["%d_%d" % [q.team, h.lane_index]] = length
	# Mirror symmetry of the walkable routes.
	for i in 5:
		assert_float(lengths["0_%d" % i]).is_equal_approx(lengths["1_%d" % (4 - i)], 3.0)


func test_flank_loops_are_connected_and_longer_than_the_main_path() -> void:
	for f in _lane.flank_loops:
		var outer := _lane.hardpoint(f.from_hardpoint)
		var mid := _lane.hardpoint(f.to_hardpoint)
		# The far corner of the loop: only reachable through the loop itself.
		var corner := f.waypoints[2]
		var a := _path(f.outer_door, corner)
		var b := _path(corner, f.mid_door)
		assert_int(a.size()).is_greater(1)
		assert_int(b.size()).is_greater(1)
		if a.size() < 2 or b.size() < 2:
			return
		assert_float(_flat(a[a.size() - 1], corner)).is_less(1.0)
		assert_float(_flat(b[b.size() - 1], f.mid_door)).is_less(1.0)
		var via_loop := _length(_path(outer.position, corner)) + _length(_path(corner, mid.position))
		var main := _length(_path(outer.position, mid.position))
		# GDD §3.7: loop ~90 m vs main path 65 m (navmesh paths cut corners).
		assert_float(main).is_between(55.0, 70.0)
		assert_float(via_loop).is_between(75.0, 100.0)
		# A Sanctum also reaches the loop corner.
		var home := _def.hq(MapDef.TEAM_CONCORD).spawn_points[0]
		var c := _path(home, corner)
		assert_int(c.size()).is_greater(1)
		if c.is_empty():
			return
		assert_float(_flat(c[c.size() - 1], corner)).is_less(1.0)


## Two far-apart floor points (Concord Sanctum, Syndicate Sanctum) used to detect a synced navmesh.
func _def_probe_a() -> Array[Vector3]:
	var d := load("res://assets/data/match/map_slice_lane.tres") as MapDef
	return [d.hq(MapDef.TEAM_CONCORD).sanctum, d.hq(MapDef.TEAM_SYNDICATE).sanctum]
