extends GdUnitTestSuite
## W13 rigged toon heroes (design/art/hero-art-bible.md): the loader falls back
## to the procedural box model for heroes without a glb, the rigged model keeps
## the HeroModel API, and replicated state maps onto the AnimationTree.

const RIGGED: Array[StringName] = [&"vesper", &"sable", &"juniper", &"ryker", &"brannoc", &"liora", &"hex"]
const CLIPS: Array[StringName] = [&"idle", &"walk", &"run", &"run_back", &"strafe_l", &"strafe_r",
	&"crouch_idle", &"crouch_walk", &"jump", &"aim_up", &"aim_mid", &"aim_down", &"shoot", &"hit",
	&"reload", &"cast_0", &"cast_1", &"cast_2", &"cast_3", &"death"]


func after_test() -> void:
	HeroModelLoader.set_box_forced(-1)


func _build(key: StringName, team: int = ModelPalette.TEAM_CONCORD) -> HeroModel:
	var m := HeroModelLoader.build(key, team)
	add_child(auto_free(m))
	return m


# --- loader fallback -------------------------------------------------------
func test_loader_uses_glb_for_pilot_heroes() -> void:
	for k in RIGGED:
		assert_bool(HeroModelLoader.has_rigged(k)).is_true()
		assert_object(_build(k)).is_instanceof(RiggedHeroModel)


func test_loader_falls_back_to_box_model_without_glb() -> void:
	# A key with no glb on disk (every shipped hero now has one).
	assert_bool(HeroModelLoader.has_rigged(&"wardling_test_hero")).is_false()
	var m := _build(&"wardling_test_hero")
	assert_object(m).is_not_instanceof(RiggedHeroModel)
	assert_object(m.pivot(&"spine")).is_not_null()


func test_loader_forced_box_and_unknown_key() -> void:
	HeroModelLoader.set_box_forced(1)
	assert_object(_build(&"ryker")).is_not_instanceof(RiggedHeroModel)
	HeroModelLoader.set_box_forced(0)
	assert_bool(HeroModelLoader.has_rigged(&"")).is_false()
	assert_bool(HeroModelLoader.has_rigged(&"nobody")).is_false()


# --- rigged model keeps the HeroModel contract -----------------------------
func test_rigged_model_markers_clips_and_budget() -> void:
	for k in RIGGED:
		var m := _build(k) as RiggedHeroModel
		for mk in [&"HAND_R_weapon", &"HEAD_nameplate", &"BACK_attach"]:
			assert_object(m.marker(mk)).is_not_null()
		for c in CLIPS:
			assert_bool(m.anim_player.has_animation(c)).override_failure_message("%s lacks %s" % [k, c]).is_true()
		assert_object(m.tree).is_not_null()
		assert_int(m.triangle_count()).is_between(8000, ModelCatalog.HERO_TRI_BUDGET)
		assert_int(m.mesh_instance_count()).is_less_equal(ModelCatalog.HERO_MESH_BUDGET)
		assert_float(m.height_m).is_between(1.7, 2.3)


## W14: one shared material per (hero, team) - each hero binds its own baked texture
## set - and the ink hull rides on the hero's 8k LOD mesh (design/art/hero-art-bible.md §8).
func test_rigged_team_material_shared_per_team() -> void:
	var a := _build(&"ryker", ModelPalette.TEAM_CONCORD) as RiggedHeroModel
	var a2 := _build(&"ryker", ModelPalette.TEAM_CONCORD) as RiggedHeroModel
	var b := _build(&"vesper", ModelPalette.TEAM_CONCORD) as RiggedHeroModel
	var c := _build(&"ryker", ModelPalette.TEAM_SYNDICATE) as RiggedHeroModel
	var ma := a._meshes[0].material_override as ShaderMaterial
	assert_object(ma).is_same(a2._meshes[0].material_override)
	assert_object(ma).is_not_same(b._meshes[0].material_override)
	assert_object(ma).is_not_same(c._meshes[0].material_override)
	assert_float(float(ma.get_shader_parameter("use_maps"))).is_equal(1.0)
	assert_object(ma.get_shader_parameter("albedo_map")).is_not_null()
	assert_bool(a._lod_meshes.is_empty()).is_false()
	var hull := a._lod_meshes[0].material_override as ShaderMaterial
	assert_object(hull).is_same(RiggedHeroModel.hull_material(ModelPalette.TEAM_CONCORD))
	c.set_team(ModelPalette.TEAM_CONCORD)
	assert_object(c._meshes[0].material_override).is_same(ma)


## W15: each hero binds its own three maps (albedo, normal, mask) from its folder.
func test_bind_maps_binds_each_heroes_own_textures() -> void:
	for key in [&"ryker", &"vesper"]:
		var m := ShaderMaterial.new()
		RiggedHeroModel._bind_maps(m, key)
		assert_float(float(m.get_shader_parameter("use_maps"))).is_equal(1.0)
		for kind in ["albedo", "normal", "mask"]:
			var t := m.get_shader_parameter(kind + "_map") as Texture2D
			assert_object(t).is_not_null()
			assert_str(t.resource_path).is_equal(
				"res://assets/models/heroes/%s/%s_%s.png" % [key, key, kind])


## W15: without the optional "HD hero textures" pack the maps do not exist and
## the material falls back to the no-maps W13 path instead of binding nulls.
func test_bind_maps_falls_back_without_hd_textures() -> void:
	var m := ShaderMaterial.new()
	m.set_shader_parameter("use_maps", 1.0)
	var ok := RiggedHeroModel.bind_maps_from(m, "res://assets/models/heroes/no_such_hero/no_such_hero_")
	assert_bool(ok).is_false()
	assert_float(float(m.get_shader_parameter("use_maps"))).is_equal(0.0)
	assert_object(m.get_shader_parameter("albedo_map")).is_null()
	var e := ShaderMaterial.new()
	RiggedHeroModel._bind_maps(e, &"")
	assert_float(float(e.get_shader_parameter("use_maps"))).is_equal(0.0)


# --- animation state mapping ----------------------------------------------
func test_map_state_idle_and_locomotion_directions() -> void:
	var s := RiggedHeroModel.map_state(Vector3.ZERO, false, true, 0.0, false)
	assert_vector(s["parameters/loco_bs/blend_position"]).is_equal(Vector2.ZERO)
	assert_float(s["parameters/loco/scale"]).is_equal(1.0)
	assert_str(s["parameters/air/transition_request"]).is_equal("ground")
	assert_str(s["parameters/life/transition_request"]).is_equal("alive")
	assert_float(s["parameters/crouch_mix/blend_amount"]).is_equal(0.0)
	# Mocap clip speeds: walk 1.5 m/s, run 3 m/s -> run point 0.5 of RUN_SPEED (6).
	var cs := {&"walk": 1.5, &"run": 3.0, &"run_back": 1.5}
	var rv := RiggedHeroModel.run_point(cs)
	assert_float(rv).is_equal_approx(0.5, 0.001)
	var walk := RiggedHeroModel.map_state(Vector3(0, 0, -1.5), false, true, 0.0, false, cs)
	assert_vector(walk["parameters/loco_bs/blend_position"]).is_equal_approx(Vector2(0, 0.25), Vector2(0.001, 0.001))
	assert_float(walk["parameters/loco/scale"]).is_equal(1.0)
	var fwd := RiggedHeroModel.map_state(Vector3(0, 0, -6.0), false, true, 0.0, false, cs)
	assert_vector(fwd["parameters/loco_bs/blend_position"]).is_equal_approx(Vector2(0, 0.5), Vector2(0.001, 0.001))
	assert_float(fwd["parameters/loco/scale"]).is_equal_approx(2.0, 0.001)
	var back := RiggedHeroModel.map_state(Vector3(0, 0, 1.5), false, true, 0.0, false, cs)
	assert_vector(back["parameters/loco_bs/blend_position"]).is_equal_approx(Vector2(0, -0.25), Vector2(0.001, 0.001))
	var right := RiggedHeroModel.map_state(Vector3(3.0, 0, 0), false, true, 0.0, false, cs)
	assert_vector(right["parameters/loco_bs/blend_position"]).is_equal_approx(Vector2(0.5, 0), Vector2(0.001, 0.001))
	var fast := RiggedHeroModel.map_state(Vector3(30, 0, -30), false, true, 0.0, false, cs)
	assert_float(fast["parameters/loco/scale"]).is_equal(RiggedHeroModel.LOCO_RATE_MAX)


func test_map_state_crouch_air_aim_death() -> void:
	var c := RiggedHeroModel.map_state(Vector3(0, 0, -RiggedHeroModel.CROUCH_SPEED * 0.5), true, true, 0.0, false)
	assert_float(c["parameters/crouch_mix/blend_amount"]).is_equal(1.0)
	assert_float(c["parameters/crouch/blend_position"]).is_equal_approx(0.5, 0.001)
	var air := RiggedHeroModel.map_state(Vector3.ZERO, false, false, 0.0, false)
	assert_str(air["parameters/air/transition_request"]).is_equal("air")
	var up := RiggedHeroModel.map_state(Vector3.ZERO, false, true, RiggedHeroModel.AIM_PITCH_MAX * 0.5, false)
	assert_float(up["parameters/aim/blend_position"]).is_equal_approx(0.5, 0.001)
	var down := RiggedHeroModel.map_state(Vector3.ZERO, false, true, -9.0, false)
	assert_float(down["parameters/aim/blend_position"]).is_equal(-1.0)
	var dead := RiggedHeroModel.map_state(Vector3.ZERO, false, true, 0.0, true)
	assert_str(dead["parameters/life/transition_request"]).is_equal("dead")


func test_cast_clip_per_skill_slot() -> void:
	for i in RiggedHeroModel.SKILL_SLOTS:
		assert_str(String(RiggedHeroModel.cast_clip(i))).is_equal("cast_%d" % i)
	assert_str(String(RiggedHeroModel.cast_clip(9))).is_equal("cast_3")
	assert_str(String(RiggedHeroModel.cast_clip(-1))).is_equal("cast_0")


func test_hooks_drive_the_tree() -> void:
	var m := _build(&"ryker") as RiggedHeroModel
	m.set_motion(m.global_basis * Vector3(0, 0, -6.0), false, 0.3)
	m.set_grounded(false)
	m._apply_pose(1.0 / 60.0)
	assert_str(m.state()["parameters/air/transition_request"]).is_equal("air")
	var bt := m.tree.tree_root as AnimationNodeBlendTree
	m.play_cast(2)
	assert_str(String((bt.get_node(&"cast_clip") as AnimationNodeAnimation).animation)).is_equal("cast_2")
	m.set_dead(true)
	m._apply_pose(1.0 / 60.0)
	assert_str(m.state()["parameters/life/transition_request"]).is_equal("dead")
	m.flinch(1.0)
	m.set_fade(0.4)
	m._apply_pose(1.0 / 60.0)


func test_hero_view_plays_death_then_hides() -> void:
	var v := HeroView.new()
	add_child(auto_free(v))
	v.set_hero(&"ryker", ModelPalette.TEAM_CONCORD)
	assert_object(v.model).is_instanceof(RiggedHeroModel)
	v.set_health(100, 250, false)
	v.set_health(0, 250, true)
	assert_bool(v.visible).is_true()
	assert_bool((v.model as RiggedHeroModel).is_dead()).is_true()
	v._hide_if_dead()
	assert_bool(v.visible).is_false()
	v.set_health(250, 250, false)
	assert_bool(v.visible).is_true()
	assert_bool((v.model as RiggedHeroModel).is_dead()).is_false()


func test_play_showcase_loops_the_menu_clip() -> void:
	var m := _build(&"vesper") as RiggedHeroModel
	assert_bool(m.play_showcase()).is_true()
	assert_bool(m.tree.active).is_false()
	assert_str(String(m.anim_player.current_animation)).is_equal("showcase")
	assert_int(m.anim_player.get_animation(&"showcase").loop_mode).is_equal(Animation.LOOP_LINEAR)
