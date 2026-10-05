extends GdUnitTestSuite
## W19-VM: FirstPersonRig loads a hero's FP glb (hands, own weapon, clips) and
## falls back to the procedural box weapon for heroes without one.

const HEROES_DIR := "res://assets/data/heroes/"


func _hero(id: String) -> HeroDef:
	return load(HEROES_DIR + id + ".tres") as HeroDef


func _rig() -> FirstPersonRig:
	var rig := FirstPersonRig.new()
	rig.setup(LookSettings.new())
	add_child(auto_free(rig))
	return rig


func _no_fp_hero() -> HeroDef:
	for f in DirAccess.get_files_at(HEROES_DIR):
		if not f.ends_with(".tres"):
			continue
		var hd := load(HEROES_DIR + f) as HeroDef
		if hd != null and hd.weapon != null and not FpViewmodel.has_fp(ModelCatalog.hero_key(hd)):
			return hd
	return null


func test_vesper_loads_fp_glb_with_clips_and_sockets() -> void:
	assert_bool(FpViewmodel.has_fp(&"vesper")).is_true()
	var rig := _rig()
	var hd := _hero("hero_vesper_loom")
	rig.set_weapon(hd.weapon, &"vesper", ModelPalette.TEAM_CONCORD)
	assert_object(rig.fp_model).is_not_null()
	assert_object(rig.weapon_model).is_null()
	assert_bool(rig.gun.visible).is_false()
	for c in [&"idle", &"walk", &"sprint", &"jump", &"land", &"fire", &"reload", &"draw", &"holster", &"cast",
			&"cast_ult", &"inspect"]:
		assert_bool(rig.fp_model.has_clip(c)).override_failure_message("missing clip %s" % c).is_true()
	for s in [&"socket_core", &"socket_frame", &"socket_chamber", &"fx_muzzle"]:
		assert_object(rig.fp_model.socket(s)).is_not_null()
	assert_int(rig.fp_model.triangle_count()).is_less_equal(ModelCatalog.WEAPON_FP_TRI_BUDGET)
	await get_tree().process_frame
	assert_object(rig.muzzle_global()).is_not_null()


func test_fp_mounts_attach_to_fp_sockets() -> void:
	var rig := _rig()
	var hd := _hero("hero_vesper_loom")
	rig.set_weapon(hd.weapon, &"vesper", ModelPalette.TEAM_CONCORD)
	var cat := load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	var ember: ArmoryItemDef
	for it in cat.items:
		if (it as ArmoryItemDef).id == &"ember_heart":
			ember = it
	rig.set_mounts([ember, null, null], PackedInt32Array([3, 0, 0]))
	assert_int(rig.mount_mesh_count()).is_equal(1)
	assert_int(rig.fp_model.socket(&"socket_core").get_child_count()).is_equal(1)


func test_hero_without_fp_glb_falls_back_to_box_weapon() -> void:
	var hd := _no_fp_hero()
	if hd == null:
		return  # every hero has an FP set: nothing to fall back from
	var rig := _rig()
	rig.set_weapon(hd.weapon, ModelCatalog.hero_key(hd), ModelPalette.TEAM_CONCORD)
	assert_object(rig.fp_model).is_null()
	assert_object(rig.weapon_model).is_not_null()


func test_box_forced_falls_back_even_with_fp_glb() -> void:
	HeroModelLoader.set_box_forced(1)
	var rig := _rig()
	rig.set_weapon(_hero("hero_vesper_loom").weapon, &"vesper", ModelPalette.TEAM_CONCORD)
	HeroModelLoader.set_box_forced(-1)
	assert_object(rig.fp_model).is_null()
	assert_object(rig.weapon_model).is_not_null()
	assert_object(rig.muzzle_global()).is_not_null()


func test_burnout_plays_reload_scaled_to_weapon_def() -> void:
	var rig := _rig()
	var hd := _hero("hero_vesper_loom")
	rig.set_weapon(hd.weapon, &"vesper", ModelPalette.TEAM_CONCORD)
	var c := SnapshotData.OwnCombat.new()
	rig.on_own_combat(c)
	c.ammo_flags = AmmoFeed.FLAG_BURNOUT
	rig.on_own_combat(c)
	var want := FpViewmodel.clip_scale(rig.fp_model.clip_length(&"reload"), FpViewmodel.reload_duration(hd.weapon))
	assert_float(float(rig.fp_model.tree.get("parameters/reload_ts/scale"))).is_equal_approx(want, 1e-5)


func test_cooldown_restart_picks_cast_or_ultimate_gesture() -> void:
	var rig := _rig()
	rig.set_weapon(_hero("hero_vesper_loom").weapon, &"vesper", ModelPalette.TEAM_CONCORD)
	var c := SnapshotData.OwnCombat.new()
	rig.on_own_combat(c)
	var c2 := SnapshotData.OwnCombat.new()
	c2.skill_cd_left = PackedInt32Array([0, 0, 0, 90])
	rig.on_own_combat(c2)
	var bt := rig.fp_model.tree.tree_root as AnimationNodeBlendTree
	assert_str(String((bt.get_node(&"cast_clip") as AnimationNodeAnimation).animation)).is_equal("cast_ult")
	var c3 := SnapshotData.OwnCombat.new()
	c3.skill_cd_left = PackedInt32Array([60, 0, 0, 90])
	rig.on_own_combat(c3)
	assert_str(String((bt.get_node(&"cast_clip") as AnimationNodeAnimation).animation)).is_equal("cast")


func test_fov_refit_scales_fp_viewmodel() -> void:
	var rig := _rig()
	rig.set_weapon(_hero("hero_vesper_loom").weapon, &"vesper", ModelPalette.TEAM_CONCORD)
	rig.set_fov(120.0)
	var f := ComfortMath.viewmodel_fov_factor(120.0, rig.comfort_rules.viewmodel_ref_fov_deg)
	var vm := rig.fp_model.get_parent() as Node3D
	assert_float(vm.scale.x).is_equal_approx(f, 1e-5)
	rig.follow(Vector3.ZERO, 1.6, 0.0, 0.0)
	assert_float(vm.position.x).is_equal_approx(rig.fp_model.fp_pos.x * f, 1e-4)
	assert_float(vm.position.z).is_equal_approx(rig.fp_model.fp_pos.z, 1e-4)
