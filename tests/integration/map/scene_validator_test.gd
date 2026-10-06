extends GdUnitTestSuite
## Scene validator on the shipped map (owner plan 2026-10-06, docs/placement.md).
## With front_match_test (navmesh reach, mirror symmetry, slopes, flat zones),
## world_assets_test (budgets, maps, pivots) and placement_map_test it covers
## collision, navmesh, materials, budgets, LOD and symmetry.

const MAP_DEF := "res://assets/data/match/map_front.tres"

## Waived navmesh spots: [position, reason]. Matched within 1 m.
const NAV_WAIVERS := [
	[Vector3(93.4, 1.4, -324.5), "bake sliver 0.3 m past the Ramp side edge (rebake: docs/polish-backlog.md)"],
	[Vector3(94.4, 1.6, -219.4), "bake sliver 0.3 m past the RampB side edge (rebake: docs/polish-backlog.md)"],
	[Vector3(94.4, 1.4, -199.8), "mirror of the RampB sliver (rebake: docs/polish-backlog.md)"],
	[Vector3(93.4, 1.4, -95.6), "mirror of the Ramp sliver (rebake: docs/polish-backlog.md)"],
]

var _map: Node3D


func before() -> void:
	_map = (load(MAP_DEF) as MapDef).scene.instantiate()
	add_child(_map)


func after() -> void:
	if is_instance_valid(_map):
		_map.queue_free()


func test_every_map_surface_has_a_material() -> void:
	assert_array(Array(SceneAudit.missing_materials(_map))).is_empty()


func test_every_navmesh_polygon_lies_on_collision() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := _map.get_world_3d().direct_space_state
	for nr: NavigationRegion3D in _map.find_children("*", "NavigationRegion3D", true, false):
		if nr.navigation_mesh == null:
			continue
		var bad := Array(SceneAudit.navmesh_off_collision(nr.navigation_mesh, space)).filter(_not_waived)
		assert_array(bad).override_failure_message("%s: %s" % [nr.name, "\n".join(PackedStringArray(bad.slice(0, 10)))]).is_empty()


func _not_waived(line: String) -> bool:
	var at := line.get_slice(" at (", 1).get_slice(")", 0).split_floats(",")
	var p := Vector3(at[0], at[1], at[2])
	for w in NAV_WAIVERS:
		if (w[0] as Vector3).distance_to(p) < 1.0:
			return false
	return true


func test_world_props_are_range_culled() -> void:
	var md := load(MAP_DEF) as MapDef
	var props := WorldProps.new()
	props.setup(md, load(WorldProps.DEF_PATH) as WorldPropsDef)
	_map.add_child(props)
	for i in 4:
		await get_tree().physics_frame
	await get_tree().process_frame
	assert_int(props.get_child_count()).is_greater(0)
	assert_array(Array(SceneAudit.unculled(props))).is_empty()
