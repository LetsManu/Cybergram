extends GdUnitTestSuite
## W16-HERO-B: Liora, Sable and Juniper on the gen pipeline (tools/art/hero_defs_gen_b.py).
## Baked cloth bones per the contract (design/art/baked-cloth.md), the 42-bone cap, no
## Sec_ springs mixed in, and a working death_back clip that keys the weapon bone.

## hero -> [cloth bone count, a cloth bone keyed in the run clip]
const HEROES := {
	&"liora": [20, "Cloth_coat_BL_2"],
	&"sable": [16, "Cloth_scarf_L_3"],
	&"juniper": [12, "Cloth_coat_BR_2"],
}


func after_test() -> void:
	HeroModelLoader.set_box_forced(-1)


func _build(key: StringName) -> RiggedHeroModel:
	var m := HeroModelLoader.build(key, ModelPalette.TEAM_CONCORD)
	add_child(auto_free(m))
	return m as RiggedHeroModel


func _keyed(anim: Animation, bone: String) -> bool:
	for t in anim.get_track_count():
		if String(anim.track_get_path(t)).ends_with(":" + bone) and anim.track_get_key_count(t) > 2:
			return true
	return false


func test_baked_cloth_bones_within_the_cap() -> void:
	for key: StringName in HEROES:
		var m := _build(key)
		assert_object(m).override_failure_message("%s is rigged" % key).is_not_null()
		var n := 0
		for i in m.skeleton.get_bone_count():
			var b := m.skeleton.get_bone_name(i)
			if b.begins_with("Cloth_"):
				n += 1
			assert_bool(b.begins_with("Sec_")).override_failure_message("%s: cloth and spring never mix" % key).is_false()
		assert_int(n).override_failure_message("%s cloth bones" % key).is_equal(int(HEROES[key][0]))
		assert_int(m.skeleton.get_bone_count()).is_less_equal(42)


func test_run_clip_carries_the_baked_cloth() -> void:
	for key: StringName in HEROES:
		var m := _build(key)
		assert_bool(_keyed(m.anim_player.get_animation(&"run"), String(HEROES[key][1]))) \
			.override_failure_message("%s run keys %s" % [key, HEROES[key][1]]).is_true()


func test_death_back_keys_the_weapon_bone() -> void:
	for key: StringName in HEROES:
		var m := _build(key)
		assert_bool(m.anim_player.has_animation(&"death_back")).is_true()
		assert_bool(_keyed(m.anim_player.get_animation(&"death_back"), "Weapon")) \
			.override_failure_message("%s death_back keys the Weapon bone" % key).is_true()


func test_per_hero_hatch_override() -> void:
	for key: StringName in HEROES:
		assert_bool(RiggedHeroModel.shader_overrides(key).has("hatch_strength")).is_true()
