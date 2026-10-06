extends GdUnitTestSuite
## SceneAudit checks, each with a passing and a failing fixture.


func test_missing_material_is_reported() -> void:
	var root: Node3D = auto_free(Node3D.new())
	var ok := MeshInstance3D.new()
	ok.mesh = BoxMesh.new()
	ok.material_override = StandardMaterial3D.new()
	root.add_child(ok)
	assert_array(Array(SceneAudit.missing_materials(root))).is_empty()
	var bare := MeshInstance3D.new()
	bare.name = "Bare"
	bare.mesh = BoxMesh.new()
	root.add_child(bare)
	assert_str(SceneAudit.missing_materials(root)[0]).contains("Bare")


func test_navmesh_over_air_is_reported() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(10, 1, 10)
	cs.shape = sh
	b.add_child(cs)
	b.position = Vector3(0, -0.5, 0)
	root.add_child(b)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var nm := NavigationMesh.new()
	nm.vertices = PackedVector3Array([Vector3(-1, 0.2, -1), Vector3(1, 0.2, -1), Vector3(0, 0.2, 1),
		Vector3(29, 0.2, 29), Vector3(31, 0.2, 29), Vector3(30, 0.2, 31)])
	nm.add_polygon(PackedInt32Array([0, 1, 2]))
	nm.add_polygon(PackedInt32Array([3, 4, 5]))
	var bad := SceneAudit.navmesh_off_collision(nm, root.get_world_3d().direct_space_state)
	assert_int(bad.size()).is_equal(1)
	assert_str(bad[0]).contains("polygon 1")


func test_geometry_without_range_is_reported() -> void:
	var root: Node3D = auto_free(Node3D.new())
	var a := MeshInstance3D.new()
	a.visibility_range_end = 80.0
	root.add_child(a)
	assert_array(Array(SceneAudit.unculled(root))).is_empty()
	var b := MultiMeshInstance3D.new()
	b.name = "Batch"
	root.add_child(b)
	assert_str(SceneAudit.unculled(root)[0]).contains("Batch")
