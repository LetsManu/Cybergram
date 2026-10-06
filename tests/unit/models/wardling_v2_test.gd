extends GdUnitTestSuite
## Wardling v2 (docs/assets/wardling.md): the rigged mini-soldier per faction, its
## tier / class props on bones, the budget near and far, and the animation hooks
## (velocity -> locomotion, shoot, hit, death) driven by WardlingModel.


func _w(tier: int, team: int) -> WardlingModel:
	var w: WardlingModel = auto_free(WardlingModelBuilder.build(&"picket", tier, team))
	add_child(w)
	return w


func test_each_faction_gets_its_own_rigged_skin() -> void:
	for team in [ModelPalette.TEAM_CONCORD, ModelPalette.TEAM_SYNDICATE]:
		var w := _w(1, team)
		assert_object(w.rig).override_failure_message("team %d: no rig" % team).is_not_null()
		assert_str(String(w.rig.key)).is_equal("wardling_s" if team == ModelPalette.TEAM_SYNDICATE else "wardling_c")
		assert_object(w.rig.body.skeleton).is_not_null()
		var m := w.rig.body._meshes[0].material_override as ShaderMaterial
		assert_float(float(m.get_shader_parameter("use_maps"))).is_equal(1.0)


func test_tiers_add_armour_and_classes_swap_markings() -> void:
	var w := _w(1, ModelPalette.TEAM_CONCORD)
	assert_bool(w.marks().tier2).is_false()
	assert_bool(w.marks().tier3).is_false()
	w.set_tier(3)
	assert_bool(w.marks().tier2).is_true()
	assert_bool(w.marks().tier3).is_true()
	w.set_owner_kind(0)
	assert_bool(w.marks().pennant).is_true()
	assert_bool(w.marks().sash).is_false()
	w.set_owner_kind(2)
	assert_bool(w.marks().pennant).is_false()
	assert_bool(w.marks().sash).is_true()
	assert_bool(w.rig._ring_own.visible).is_true()
	w.set_elite(true)
	assert_bool(w.marks().elite).is_true()


func test_props_ride_on_the_skeleton() -> void:
	var w := _w(2, ModelPalette.TEAM_SYNDICATE)
	for n in [&"plate_l", &"plate_r", &"crest", &"pennant"]:
		var p := w.rig.prop(n)
		assert_object(p).is_not_null()
		assert_object(p.get_parent() as BoneAttachment3D).override_failure_message("%s not on a bone" % n).is_not_null()
	# the crest sits on top of the helmet, the plates at shoulder height
	var top := w.rig.body.height_m
	assert_float(w.rig.prop(&"crest").global_position.y).is_between(top - 0.12, top + 0.05)
	assert_float(w.rig.prop(&"plate_l").global_position.y).is_between(top * 0.45, top * 0.85)


func test_budget_near_and_far() -> void:
	var w := _w(3, ModelPalette.TEAM_SYNDICATE)
	w.set_owner_kind(2)
	assert_int(w.triangle_count()).is_less(ModelCatalog.WARDLING_TRI_BUDGET)
	assert_int(w.mesh_instance_count()).is_less_equal(ModelCatalog.WARDLING_MESH_BUDGET)
	var lod := w.rig.body._lod_meshes
	assert_int(lod.size()).is_equal(1)
	var n := 0
	for s in lod[0].mesh.get_surface_count():
		n += (lod[0].mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	assert_int(n).is_less(ModelCatalog.WARDLING_FAR_TRI_BUDGET)


func test_moving_drives_the_run_and_death_plays() -> void:
	var w := _w(1, ModelPalette.TEAM_CONCORD)
	# 6.5 m/s along -Z (forward) for a few frames
	for i in 8:
		w.position += Vector3(0, 0, -6.5 * 0.05)
		w._process(0.05)
		w.rig.body._apply_pose(0.05)
	assert_float(w.velocity.length()).is_between(4.0, 7.0)
	var st := w.rig.body.state()
	assert_float((st["parameters/loco_bs/blend_position"] as Vector2).length()).is_greater(0.05)
	assert_float(float(st["parameters/loco/scale"])).is_greater(RiggedHeroModel.LOCO_RATE_MAX)
	w.shoot()
	w.hit(w.global_position + Vector3(0, 0, -5))
	w.die(w.global_position + Vector3(0, 0, -5))
	assert_bool(w.rig.body.is_dead()).is_true()
	assert_bool(w.rig.body.death_back()).is_true()  # shot from the front: falls backward


func test_removed_wardling_plays_its_death_then_frees() -> void:
	var v: WardlingView = WardlingView.new()
	add_child(v)
	v.set_state(MapDef.TEAM_CONCORD, 1.0, 1)
	assert_bool(v.can_die()).is_true()
	v.die()
	assert_bool(v.dying).is_true()
	v._process(WardlingView.DEATH_S + WardlingView.FADE_S + 0.1)
	assert_bool(v.is_queued_for_deletion()).is_true()
