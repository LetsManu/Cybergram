extends GdUnitTestSuite
## WardlingModelBuilder (art bible §5.3-5.4, §10.6) and UplinkModel (§6.5):
## tiers add silhouette under the 4k budget with shared meshes; class markings
## toggle; the spire keeps its states readable under its 80k budget.


func test_wardling_tiers_under_budget_and_growing() -> void:
	var prev_tris := 0
	var prev_scale := 0.0
	for t in [1, 2, 3]:
		var w := WardlingModelBuilder.build(&"picket", t, ModelPalette.TEAM_CONCORD)
		add_child(auto_free(w))
		assert_int(w.triangle_count()).is_greater(prev_tris).is_less(ModelCatalog.WARDLING_TRI_BUDGET)
		assert_int(w.mesh_instance_count()).is_less_equal(ModelCatalog.WARDLING_MESH_BUDGET)
		assert_float(w.scale.x).is_greater(prev_scale)
		prev_tris = w.triangle_count()
		prev_scale = w.scale.x


func test_wardling_meshes_and_material_shared() -> void:
	var a := WardlingModelBuilder.build(&"picket", 2, ModelPalette.TEAM_SYNDICATE)
	var b := WardlingModelBuilder.build(&"picket", 2, ModelPalette.TEAM_SYNDICATE)
	add_child(auto_free(a))
	add_child(auto_free(b))
	var ma: MeshInstance3D = a.find_children("*", "MeshInstance3D", true, false)[0]
	var mb: MeshInstance3D = b.find_children("*", "MeshInstance3D", true, false)[0]
	assert_object(ma.mesh).is_same(mb.mesh)
	assert_object(ma.material_override).is_same(mb.material_override)


func test_wardling_class_markings_and_elite() -> void:
	var w := WardlingModelBuilder.build(&"picket", 1, ModelPalette.TEAM_CONCORD)
	add_child(auto_free(w))
	w.set_owner_kind(0)
	assert_bool(w.marks().pennant).is_true()
	assert_bool(w.marks().sash).is_false()
	w.set_owner_kind(2)
	assert_bool(w.marks().pennant).is_false()
	assert_bool(w.marks().sash).is_true()
	var s1 := w.scale.x
	w.set_elite(true)
	assert_float(w.scale.x).is_equal_approx(s1 * WardlingModelBuilder.ELITE_SCALE, 0.001)
	assert_bool(w.marks().elite).is_true()


func test_uplink_states_and_budget() -> void:
	var u := UplinkModel.new()
	add_child(auto_free(u))
	u.setup(ModelPalette.TEAM_CONCORD, 7.3)
	assert_int(u.triangle_count()).is_less(80000)
	assert_bool(u._beam.visible).is_true()
	u.set_state(true, false, 0.4)
	assert_int(u.stage).is_equal(2)
	assert_float(u._band_mats[0].get_shader_parameter("glitch_amount")).is_greater(0.0)
	u.set_state(true, true, 0.0)
	assert_bool(u._beam.visible).is_false()
	assert_float(u._crystal_mat.get_shader_parameter("dead")).is_equal(1.0)
