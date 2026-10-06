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
	# Part 6: the six Forward Beacon pads (two per Mid) are in the audit, with no waiver.
	var pads := (res[0] as Array).filter(func(it: PlacementValidator.Item) -> bool: return it.id.begins_with("forward_beacon_"))
	assert_int(pads.size()).is_equal(6)
	# C5: the 15 Supply Cache crates too.
	var caches := (res[0] as Array).filter(func(it: PlacementValidator.Item) -> bool: return it.id.begins_with("supply_cache_"))
	assert_int(caches.size()).is_equal(15)
	# C5: two Garrison sockets per hardpoint (30).
	var sockets := (res[0] as Array).filter(func(it: PlacementValidator.Item) -> bool: return it.id.begins_with("garrison_socket_"))
	assert_int(sockets.size()).is_equal(30)
	for v: PlacementValidator.Violation in report:
		assert_bool(v.item.begins_with("forward_beacon_") or v.item.begins_with("supply_cache_")
			or v.item.begins_with("garrison_socket_")) \
			.override_failure_message(v.text()).is_false()
