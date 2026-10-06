extends GdUnitTestSuite
## PlacementValidator / PlacementKit (owner plan 2026-10-06, docs/placement.md):
## one passing and one failing case per rule against a small level: a floor
## (top y = 0), a wall whose face is at z = -5 (4 m tall), a 0.3 m step at x >= 10.

const BOX := AABB(Vector3(-0.5, 0.0, -0.4), Vector3(1.0, 1.0, 0.8))

var _root: Node3D


func before() -> void:
	_root = Node3D.new()
	add_child(_root)
	_solid(Vector3(0, -0.5, 0), Vector3(60, 1, 60))      # floor
	_solid(Vector3(0, 2.0, -5.25), Vector3(20, 4, 0.5))   # wall, face at z = -5
	_solid(Vector3(15, 0.15, 0), Vector3(10, 0.3, 10))   # step x 10..20, top 0.3


func after() -> void:
	_root.free()


func _solid(at: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = at
	_root.add_child(b)


func _report(items: Array, keep: Callable = Callable()) -> Array:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var v := PlacementValidator.new()
	v.keep_out = keep
	return v.validate(_root.get_world_3d().direct_space_state, items)


func _rules(report: Array) -> Array:
	return report.map(func(x: PlacementValidator.Violation) -> String: return String(x.rule))


func _floor(id: String, at: Vector3, basis := Basis()) -> PlacementValidator.Item:
	return PlacementValidator.Item.new(id, &"floor", Transform3D(basis, at), BOX)


func test_a_prop_standing_on_the_floor_passes_every_rule() -> void:
	var r: Array = await _report([_floor("ok", Vector3(0, 0, 0))])
	assert_array(_rules(r)).is_empty()


func test_grounded_fails_for_a_floating_prop() -> void:
	var r: Array = await _report([_floor("float", Vector3(0, 0.3, 0))])
	assert_array(_rules(r)).contains(["grounded"])


func test_supported_fails_when_the_footprint_hangs_over_a_step() -> void:
	# centre on the step top, half the footprint over the lower floor
	var it := _floor("ledge", Vector3(10.1, 0.3, 0))
	var r: Array = await _report([it])
	assert_array(_rules(r)).contains(["supported"])
	assert_array(_rules(await _report([_floor("on_step", Vector3(12, 0.3, 0))]))).is_empty()


func test_upright_fails_for_a_tipped_prop() -> void:
	var r: Array = await _report([_floor("tipped", Vector3(0, 0, 0), Basis(Vector3.RIGHT, deg_to_rad(25)))])
	assert_array(_rules(r)).contains(["upright"])


func test_no_overlap_fails_inside_the_wall_and_between_props() -> void:
	var r: Array = await _report([_floor("in_wall", Vector3(0, 0, -5.1))])
	assert_array(_rules(r)).contains(["no_overlap"])
	var r2: Array = await _report([_floor("a", Vector3(3, 0, 0)), _floor("b", Vector3(3.5, 0, 0))])
	assert_array(_rules(r2)).contains(["no_overlap"])
	var r3: Array = await _report([_floor("a", Vector3(3, 0, 0)), _floor("b", Vector3(4.05, 0, 0))])
	assert_array(_rules(r3)).is_empty()


func test_mounted_needs_the_wall_behind_it() -> void:
	# back face (local +Z = 0.4) towards the wall at z = -5: basis turned 180 deg
	var turned := Basis(Vector3.UP, PI)
	var on := PlacementValidator.Item.new("lamp", &"mounted", Transform3D(turned, Vector3(0, 1.5, -4.62)), BOX)
	assert_array(_rules(await _report([on]))).is_empty()
	var off := PlacementValidator.Item.new("lamp_off", &"mounted", Transform3D(turned, Vector3(0, 1.5, -3.5)), BOX)
	assert_array(_rules(await _report([off]))).contains(["mounted"])


func test_scale_against_the_hero() -> void:
	var giant := PlacementValidator.Item.new("giant", &"floor", Transform3D(Basis().scaled(Vector3(1, 6, 1)), Vector3(-6, 0, 0)), BOX)
	var crumb := PlacementValidator.Item.new("crumb", &"floor", Transform3D(Basis().scaled(Vector3(1, 0.1, 1)), Vector3(6, 0, 3)), BOX)
	var r: Array = await _report([giant, crumb])
	assert_int(_rules(r).count("scale")).is_equal(2)


func test_faces_floor_needs_open_floor_in_front() -> void:
	# a kiosk with its back on the wall faces +Z (open floor): passes
	var turned := Basis(Vector3.UP, PI)
	var kiosk := PlacementValidator.Item.new("kiosk", &"wall", Transform3D(turned, Vector3(-3, 0, -4.6)), BOX)
	kiosk.faces_walkable = true
	assert_array(_rules(await _report([kiosk]))).is_empty()
	# turned to face the wall: fails
	var wrong := PlacementValidator.Item.new("kiosk_wrong", &"wall", Transform3D(Basis(), Vector3(-3, 0, -4.4)), BOX)
	wrong.faces_walkable = true
	assert_array(_rules(await _report([wrong]))).contains(["faces_floor"])


func test_keep_out_reports_the_zone() -> void:
	var keep := func(p: Vector3, _r: float) -> String: return "lane_corridor" if absf(p.x) < 1.0 else ""
	var r: Array = await _report([_floor("in_lane", Vector3(0, 0, 0))], keep)
	assert_array(_rules(r)).contains(["keep_out"])
	assert_str((r[0] as PlacementValidator.Violation).detail).contains("lane_corridor")


func test_decals_need_a_floor_and_a_clear_box() -> void:
	var dbox := AABB(Vector3(-1, -0.4, -1), Vector3(2, 0.8, 2))
	var ok := PlacementValidator.Item.new("arrow", &"decal", Transform3D(Basis(), Vector3(-8, 0, 5)), dbox)
	assert_array(_rules(await _report([ok]))).is_empty()
	var at_wall := PlacementValidator.Item.new("arrow_wall", &"decal", Transform3D(Basis(), Vector3(-8, 0, -4.5)), dbox)
	assert_array(_rules(await _report([at_wall]))).contains(["decal_clear"])
	var at_step := PlacementValidator.Item.new("arrow_step", &"decal", Transform3D(Basis(), Vector3(9.5, 0, 0)), dbox)
	assert_array(_rules(await _report([at_step]))).contains(["decal_clear"])
	var on_prop := PlacementValidator.Item.new("arrow_crate", &"decal", Transform3D(Basis(), Vector3(-12, 0, 5)), dbox)
	assert_array(_rules(await _report([on_prop, _floor("crate", Vector3(-12, 0, 5))]))).contains(["decal_clear"])
	var air := PlacementValidator.Item.new("arrow_air", &"decal", Transform3D(Basis(), Vector3(-8, 2, 5)), dbox)
	assert_array(_rules(await _report([air]))).contains(["decal_surface"])


func test_waived_violations_are_reported_but_do_not_count() -> void:
	var it := _floor("float", Vector3(0, 0.3, 0))
	it.waiver = "hover crate (anti-grav prop)"
	var r: Array = await _report([it])
	assert_int(r.size()).is_greater(0)
	assert_int(PlacementValidator.unwaived(r)).is_equal(0)
	assert_str(PlacementValidator.format(r, 1)).contains("waived: hover crate")


func test_kit_snap_and_align() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := _root.get_world_3d().direct_space_state
	var xf := PlacementKit.snap(space, Transform3D(Basis(), Vector3(12, 0.9, 0)), BOX, 1.5)
	assert_float(xf.origin.y).is_equal_approx(0.3, 0.01)
	var b := PlacementKit.align_up(Basis(Vector3.UP, 0.7), Vector3(0, 1, 1).normalized())
	assert_float(b.y.dot(Vector3(0, 1, 1).normalized())).is_equal_approx(1.0, 0.001)
