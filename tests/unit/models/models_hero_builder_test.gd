extends GdUnitTestSuite
## HeroModelBuilder (design/art-bible.md §5.2, §10.6): every hero builds an
## articulated model with the attach markers, its signature weapon and stays
## under the triangle / draw-call budgets. Meshes are shared per hero.

const HEROES := [[&"vesper"], [&"sable"], [&"juniper"], [&"ryker"], [&"brannoc"], [&"liora"], [&"hex"]]
const PIVOTS: Array[StringName] = [&"hips", &"spine", &"head", &"arm_l", &"arm_r", &"fore_l", &"fore_r",
	&"leg_l", &"leg_r", &"shin_l", &"shin_r", &"aim"]


func _build(key: StringName, team: int = ModelPalette.TEAM_CONCORD) -> HeroModel:
	var m := HeroModelBuilder.build(key, team)
	add_child(auto_free(m))
	return m


@warning_ignore("unused_parameter")
func test_hero_builds_markers_pivots_and_budget(key: StringName, test_parameters := HEROES) -> void:
	var m := _build(key)
	for mk in [&"HAND_R_weapon", &"HEAD_nameplate", &"BACK_attach"]:
		assert_object(m.marker(mk)).is_not_null()
	for p in PIVOTS:
		assert_object(m.pivot(p)).is_not_null()
	assert_object(m.weapon).is_not_null()
	assert_str(String(m.weapon.key)).is_equal(String(ModelCatalog.HERO_WEAPON[key]))
	assert_int(m.triangle_count()).is_greater(500).is_less(ModelCatalog.HERO_TRI_BUDGET)
	assert_int(m.mesh_instance_count()).is_less_equal(ModelCatalog.HERO_MESH_BUDGET)


@warning_ignore("unused_parameter")
func test_hero_meshes_shared_between_instances_and_teams(key: StringName, test_parameters := HEROES) -> void:
	var a := _build(key, ModelPalette.TEAM_CONCORD)
	var b := _build(key, ModelPalette.TEAM_SYNDICATE)
	var ma := a.find_children("*", "MeshInstance3D", true, false)
	var mb := b.find_children("*", "MeshInstance3D", true, false)
	assert_int(ma.size()).is_equal(mb.size())
	assert_object((ma[0] as MeshInstance3D).mesh).is_same((mb[0] as MeshInstance3D).mesh)


func test_team_tint_uses_one_shared_toon_material_per_team() -> void:
	var a := _build(&"ryker", ModelPalette.TEAM_CONCORD)
	var b := _build(&"brannoc", ModelPalette.TEAM_CONCORD)
	var c := _build(&"ryker", ModelPalette.TEAM_SYNDICATE)
	var toon_a := (a.pivot(&"spine").get_node("Mesh_toon") as MeshInstance3D).material_override
	var toon_b := (b.pivot(&"spine").get_node("Mesh_toon") as MeshInstance3D).material_override
	var toon_c := (c.pivot(&"spine").get_node("Mesh_toon") as MeshInstance3D).material_override
	assert_object(toon_a).is_same(toon_b)
	assert_object(toon_a).is_not_same(toon_c)
	assert_object((toon_a as ShaderMaterial).next_pass).is_not_null()  # outline


func test_heights_follow_art_bible_sable_smallest_brannoc_tallest() -> void:
	var h := {}
	for k in ModelCatalog.HERO_KEYS:
		h[k] = HeroModelBuilder.blueprint(k).height
	assert_float(h[&"sable"]).is_equal_approx(1.70, 0.001)
	assert_float(h[&"brannoc"]).is_equal_approx(2.2, 0.001)
	for k in ModelCatalog.HERO_KEYS:
		assert_float(h[k]).is_between(1.70, 2.2)


func test_crouch_pose_lowers_hips_and_walk_swings_legs() -> void:
	var m := _build(&"ryker")
	var hips := m.pivot(&"hips")
	m._apply_pose(0.5)
	var stand_y := hips.position.y
	m.set_motion(Vector3.ZERO, true, 0.0)
	for i in 30:
		m._apply_pose(1.0 / 30.0)
	assert_float(hips.position.y).is_less(stand_y - 0.15)
	m.set_motion(m.global_basis * Vector3(0, 0, -6.0), false, 0.0)
	var max_swing := 0.0
	for i in 30:
		m._apply_pose(1.0 / 30.0)
		max_swing = maxf(max_swing, absf(m.pivot(&"leg_l").rotation.x))
	assert_float(max_swing).is_greater(0.3)


func test_flinch_tilts_spine_then_decays() -> void:
	var m := _build(&"liora")
	m._apply_pose(0.1)
	var rest := m.pivot(&"spine").rotation.x
	m.flinch(1.0)
	m._apply_pose(0.01)
	assert_float(m.pivot(&"spine").rotation.x).is_less(rest - 0.2)
	for i in 30:
		m._apply_pose(1.0 / 30.0)
	assert_float(m.pivot(&"spine").rotation.x).is_equal_approx(rest, 0.05)
