extends GdUnitTestSuite
## CI gate (owner plan 2026-10-06, docs/placement.md): every world prop and
## floor decal the game places on the shipped map passes PlacementValidator
## against the map's collision; violations need a waiver with a reason
## (MapPlacementAudit.WAIVERS). The report is printed on failure.

const MAP_DEF := "res://assets/data/match/map_front.tres"

var _map: Node3D


func after() -> void:
	if is_instance_valid(_map):
		_map.queue_free()


func test_shipped_map_has_no_unwaived_placement_violations() -> void:
	var md := load(MAP_DEF) as MapDef
	_map = md.scene.instantiate()
	add_child(_map)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := _map.get_world_3d().direct_space_state
	var res := MapPlacementAudit.run(md, space, func(p: Vector3) -> Dictionary: return WorldDecals.physics_ground(space, p), _map)
	var report: Array = res[1]
	assert_int((res[0] as Array).size()).is_greater(300)
	if PlacementValidator.unwaived(report) > 0:
		print(PlacementValidator.format(report, (res[0] as Array).size()))
	assert_int(PlacementValidator.unwaived(report)).is_equal(0)
