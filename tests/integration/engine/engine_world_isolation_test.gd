extends GdUnitTestSuite
## Verification list item 2 (architecture.md §15, ADR-0002 "Verification Required" 2):
## does a SubViewport with own_world_3d = true give a separate physics space and a
## separate navigation map in the same process, and does that space still step when
## the SubViewport never renders (UPDATE_DISABLED)?
## Results are recorded in docs/architecture/verification-4.7.md.

const _PROBE_FROM := Vector3(0.0, 5.0, 0.0)
const _PROBE_TO := Vector3(0.0, -5.0, 0.0)
const _FALL_FRAMES: int = 10


func _make_isolated_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(2, 2)
	add_child(vp)
	return auto_free(vp)


func _make_floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	shape.shape = box
	body.add_child(shape)
	return body


func _ray_hits(space: RID) -> bool:
	var state := PhysicsServer3D.space_get_direct_state(space)
	var query := PhysicsRayQueryParameters3D.create(_PROBE_FROM, _PROBE_TO)
	return not state.intersect_ray(query).is_empty()


func test_own_world_3d_has_separate_physics_space_and_nav_map() -> void:
	var vp := _make_isolated_viewport()
	vp.add_child(_make_floor())
	await get_tree().physics_frame
	var main_world: World3D = get_tree().root.find_world_3d()
	var sub_world: World3D = vp.find_world_3d()
	assert_bool(sub_world == main_world).is_false()
	assert_bool(sub_world.space == main_world.space).is_false()
	assert_bool(sub_world.navigation_map == main_world.navigation_map).is_false()
	assert_bool(sub_world.navigation_map.is_valid()).is_true()
	# The floor exists only in the SubViewport's space.
	assert_bool(_ray_hits(sub_world.space)).is_true()
	assert_bool(_ray_hits(main_world.space)).is_false()


func test_own_world_3d_space_steps_while_viewport_never_renders() -> void:
	var vp := _make_isolated_viewport()
	var rigid := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	rigid.add_child(shape)
	vp.add_child(rigid)
	var start_y := rigid.global_position.y
	for i in _FALL_FRAMES:
		await get_tree().physics_frame
	assert_float(rigid.global_position.y).is_less(start_y)


func test_character_body_in_sub_world_ignores_main_world_geometry() -> void:
	# Main world floor at y = 0; sub world floor 3 m lower. A body dropped in the
	# sub world must pass the main-world floor height and land on its own floor.
	var main_floor := _make_floor()
	add_child(auto_free(main_floor))
	var vp := _make_isolated_viewport()
	var sub_floor := _make_floor()
	sub_floor.position = Vector3(0.0, -3.0, 0.0)
	vp.add_child(sub_floor)
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	body.add_child(shape)
	body.position = Vector3(0.0, 2.0, 0.0)
	vp.add_child(body)
	await get_tree().physics_frame
	for i in 60:
		body.velocity = Vector3(0.0, -10.0, 0.0)
		body.move_and_slide()
	assert_float(body.global_position.y).is_less(-1.0)
	assert_bool(body.is_on_floor()).is_true()
